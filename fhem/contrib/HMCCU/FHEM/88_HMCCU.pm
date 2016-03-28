#########################################################################
#
#  88_HMCCU.pm
#
#  $Id$
#
#  Version 3.1
#
#  Module for communication between FHEM and Homematic CCU2.
#  Supports BidCos-RF, BidCos-Wired, HmIP-RF.
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
#########################################################################
#
#  define <name> HMCCU <hostname_or_ip_of_ccu>
#
#  set <name> config {<device>|<channel>} <parameter>=<value> [...]
#  set <name> datapoint {<device>|<channel>}.<datapoint> <value> [...]
#  set <name> devstate <channel> <value> [...]
#  set <name> execute <ccu_program>
#  set <name> hmscript <hm_script_file>
#  set <name> restartrpc
#  set <name> rpcserver {on|off}
#  set <name> var <value> [...]
#
#  get <name> channel {<device>|<channel>}[.<datapoint_exp>][=<subst_rule>]
#  get <name> config {<device>|<channel>}
#  get <name> configdesc {<device>|<channel>}
#  get <name> datapoint <channel>.<datapoint> [<reading>]
#  get <name> deviceinfo <device>
#  get <name> devicelist [dump]
#  get <name> devstate <channel> [<reading>]
#  get <name> dump {devtypes|datapoints} [<filter>]
#  get <name> parfile [<parfile>]
#  get <name> rpcstate
#  get <name> update [<fhemdevexp> [{ State | Value }]]
#  get <name> updateccu [<devexp> [{ State | Value }]]
#  get <name> vars <regexp>
#
#  attr <name> ccuflags { singlerpc,extrpc,dptnocheck }
#  attr <name> ccuget { State | Value }
#  attr <name> ccureadingfilter <filter_rule>
#  attr <name> ccureadingformat { name | address }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccutrace {<ccudevname_exp>|<ccudevaddr_exp>}
#  attr <name> parfile <parfile>
#  attr <name> rpcinterval <seconds>
#  attr <name> rpcport <ccu_rpc_port>
#  attr <name> rpcqueue <file>
#  attr <name> rpcserver { on | off }
#  attr <name> statedatapoint <datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> stripchar <character>
#  attr <name> stripnumber { 0 | 1 | 2 }
#  attr <name> substitute <subst_rule>
#  attr <name> updatemode { client | both | hmccu }
#
#  filter_rule := [channel-regexp!]datapoint-regexp[,...]
#  subst_rule := [datapoint[,...]!]<regexp>:<subtext>[,...][;...]
#########################################################################

package main;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use strict;
use warnings;
use SetExtensions;
use IO::File;
use Fcntl 'SEEK_END', 'SEEK_SET', 'O_CREAT', 'O_RDWR';
use RPC::XML::Client;
use RPC::XML::Server;
# use File::Queue;
# use Data::Dumper;
# use FindBin qw($Bin);
# use lib "$Bin";
# use RPCQueue;

# RPC Ports
my %HMCCU_RPC_PORT = ('BidCos-Wired', 2000, 'BidCos-RF', 2001, 'HmIP-RF', 2010);

# Initial interval for reading RPC queue
my $HMCCU_INIT_INTERVAL = 10;

# CCU Device names, key = CCU device address
my %HMCCU_Devices;
# CCU Device addresses, key = CCU device name
my %HMCCU_Addresses;
# Last update of device list
# my $HMCCU_UpdateTime = 0;
# Last event from CCU
# my $HMCCU_EventTime = 0;

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
sub HMCCU_Define ($$);
sub HMCCU_Undef ($$);
sub HMCCU_Shutdown ($);
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_Attr ($@);
sub HMCCU_Notify ($$);
sub HMCCU_ParseObject ($$);
sub HMCCU_FilterReading ($$$);
sub HMCCU_GetReadingName ($$$$$$);
sub HMCCU_FormatReadingValue ($$);
sub HMCCU_SetError ($$);
sub HMCCU_SetState ($$);
sub HMCCU_Substitute ($$$$);
sub HMCCU_SubstRule ($$$);
sub HMCCU_UpdateClients ($$$$);
sub HMCCU_UpdateClientReading ($@);
sub HMCCU_DeleteDevices ($);
sub HMCCU_StartRPCServer ($);
sub HMCCU_StopRPCServer ($);
sub HMCCU_ForceStopRPCServer ($);
sub HMCCU_IsRPCStateBlocking ($);
sub HMCCU_IsRPCServerRunning ($$$);
sub HMCCU_CheckProcess ($$);
sub HMCCU_GetDeviceInfo ($$$);
sub HMCCU_FormatDeviceInfo ($);
sub HMCCU_GetDeviceList ($);
sub HMCCU_GetDatapointList ($);
sub HMCCU_GetAddress ($$$);
sub HMCCU_IsDevAddr ($$);
sub HMCCU_IsChnAddr ($$);
sub HMCCU_SplitChnAddr ($);
sub HMCCU_GetCCUObjectAttribute ($$);
sub HMCCU_GetHash ($@);
sub HMCCU_GetAttribute ($$$$);
sub HMCCU_GetSpecialDatapoints ($$$$$);
sub HMCCU_IsValidDevice ($);
sub HMCCU_GetValidDatapoints ($$$$$);
sub HMCCU_IsValidDatapoint ($$$$$);
sub HMCCU_GetMatchingDevices ($$$$);
sub HMCCU_GetDeviceName ($$);
sub HMCCU_GetChannelName ($$);
sub HMCCU_GetDeviceType ($$);
sub HMCCU_GetDeviceChannels ($);
sub HMCCU_GetDeviceInterface ($$);
sub HMCCU_ResetRPCQueue ($);
sub HMCCU_ReadRPCQueue ($);
sub HMCCU_HMScript ($$);
sub HMCCU_GetDatapoint ($@);
sub HMCCU_SetDatapoint ($$$);
sub HMCCU_GetVariables ($$);
sub HMCCU_SetVariable ($$$);
sub HMCCU_GetUpdate ($$$);
sub HMCCU_UpdateDeviceReadings ($$);
sub HMCCU_GetChannel ($$);
sub HMCCU_RPCGetConfig ($$$);
sub HMCCU_RPCSetConfig ($$$);

# File queue functions
sub HMCCU_QueueOpen ($$);
sub HMCCU_QueueClose ($);
sub HMCCU_QueueReset ($);
sub HMCCU_QueueEnq ($$);
sub HMCCU_QueueDeq ($);

# Helper functions
sub HMCCU_AggReadings ($$$$$);
sub HMCCU_Dewpoint ($$$$);


#####################################
# Initialize module
#####################################

sub HMCCU_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCU_Define";
	$hash->{UndefFn} = "HMCCU_Undef";
	$hash->{SetFn} = "HMCCU_Set";
	$hash->{GetFn} = "HMCCU_Get";
	$hash->{AttrFn} = "HMCCU_Attr";
	$hash->{NotifyFn} = "HMCCU_Notify";
	$hash->{ShutdownFn} = "HMCCU_Shutdown";

	$hash->{AttrList} = "stripchar stripnumber:0,1,2 ccuflags:multiple-strict,singlerpc,extrpc,dptnocheck ccureadings:0,1 ccureadingfilter ccureadingformat:name,address rpcinterval:3,5,7,10 rpcqueue rpcport:multiple-strict,2000,2001,2010 rpcserver:on,off parfile statedatapoint statevals substitute updatemode:client,both,hmccu ccutrace ccuget:Value,State ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCU_Define ($$)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return "Define CCU hostname or IP address as a parameter" if(@a < 3);

	$hash->{host} = $a[2];
	$hash->{Clients} = ':HMCCUDEV:HMCCUCHN:';

	$hash->{DevCount} = HMCCU_GetDeviceList ($hash);
	$hash->{NewDevices} = 0;
        $hash->{DelDevices} = 0;
	$hash->{RPCState} = "stopped";
	
	$hash->{hmccu}{eventtime} = 0;
	$hash->{hmccu}{updatetime} = 0;
	$hash->{hmccu}{rpccount} = 0;

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCU_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	return undef;
}

#####################################
# Handle global FHEM events
#####################################

sub HMCCU_Notify ($$)
{
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME};
	
	my $disable = AttrVal ($name, 'disable', 0);
	my $rpcserver = AttrVal ($name, 'rpcserver', 'off');
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	return if ($dev->{NAME} ne "global" || $disable);
#	return if (!grep (m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
	return if (!grep (m/^INITIALIZED$/, @{$dev->{CHANGED}}));

	if ($rpcserver eq 'on') {
		my $delay = 10;
		Log3 $name, 0, "HMCCU: Autostart of RPC server after FHEM initialization in $delay seconds";
		InternalTimer (gettimeofday()+$delay, "HMCCU_StartRPCServer", $hash, 0) ;
	}

	return undef;
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
	sleep (3);
	HMCCU_ForceStopRPCServer ($hash);
	RemoveInternalTimer ($hash);

	return undef;
}

#####################################
# Set commands
#####################################

sub HMCCU_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;
	my $options = "devstate datapoint var execute hmscript config rpcserver:on,off restartrpc:noArg";
	my $host = $hash->{host};

	if (HMCCU_IsRPCStateBlocking ($hash)) {
		return undef if ($opt eq '?');
		return HMCCU_SetState ($hash, "busy");
	}

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $stripchar = AttrVal ($name, "stripchar", '');
	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my $statevals = AttrVal ($name, "statevals", '');
	my $ccureadings = AttrVal ($name, "ccureadings", 'name');
	my $readingformat = AttrVal ($name, "ccureadingformat", 'name');
	my $substitute = AttrVal ($name, "substitute", '');

	if ($opt eq 'devstate' || $opt eq 'datapoint' || $opt eq 'var') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);
		my $result;

		if (!defined ($objname) || !defined ($objvalue)) {
			return HMCCU_SetError ($hash, "Usage: set $name $opt {ccuobject} {value} [...]");
		}

		$objname =~ s/$stripchar$// if ($stripchar ne '');
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		if ($opt eq 'var') {
			$result = HMCCU_SetVariable ($hash, $objname, $objvalue);
		}
		elsif ($opt eq 'devstate') {
			$result = HMCCU_SetDatapoint ($hash, $objname.'.'.$statedatapoint, $objvalue);
		}
		else {
			$result = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		}

		return HMCCU_SetError ($hash, $result) if ($result < 0);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq "execute") {
		my $program = shift @a;
		my $response;

		return HMCCU_SetError ($hash, "Usage: set $name execute {program-name}") if (!defined ($program));

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
		my $scrfile = shift @a;
		my $script;
		my $response;

		return HMCCU_SetError ($hash, "Usage: set $name hmscript {scriptfile}") if (!defined ($scrfile));
		if (open (SCRFILE, "<$scrfile")) {
			my @lines = <SCRFILE>;
			$script = join ("\n", @lines);
			close (SCRFILE);
		}
		else {
			return HMCCU_SetError ($hash, "Can't open file $scrfile");
		}

		$response = HMCCU_HMScript ($hash, $script);
		return HMCCU_SetError ($hash, -2) if ($response eq '');

		HMCCU_SetState ($hash, "OK");
		return $response if (! $ccureadings);

		foreach my $line (split /\n/, $response) {
			my @tokens = split /=/, $line;
			next if (@tokens != 2);
			my $reading;
			my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($tokens[0], $HMCCU_FLAG_INTERFACE);
			($add, $chn) = HMCCU_GetAddress ($nam, '', '') if ($flags == $HMCCU_FLAGS_NCD);
			if ($flags == $HMCCU_FLAGS_IACD || $flags == $HMCCU_FLAGS_NCD) {
				$reading = HMCCU_GetReadingName ($int, $add, $chn, $dpt, $nam, $readingformat);
				HMCCU_UpdateClientReading ($hash, $add, $chn, $reading, $tokens[1]);
			}
			else {
				my $Value = HMCCU_Substitute ($tokens[1], $substitute, 0, $tokens[0]);
				readingsSingleUpdate ($hash, $tokens[0], $Value, 1);
			}
		}

		return undef;
	}
	elsif ($opt eq 'config') {
		my $ccuobj = shift @a;

		return HMCCU_SetError ($hash, "Usage: set $name config {device|channel} {param=value} [...]")
		   if (!defined ($ccuobj) || @a < 1);

		my $rc = HMCCU_RPCSetConfig ($hash, $ccuobj, \@a);

		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'rpcserver') {
		my $action = shift @a;

		return HMCCU_SetError ($hash, "Usage: set $name rpcserver {on|off}")
		   if (!defined ($action) || $action !~ /^(on|off)$/);
		   
		if ($action eq 'on') {
			return HMCCU_SetError ($hash, "Start of RPC server failed")
			   if (!HMCCU_StartRPCServer ($hash));
		}
		elsif ($action eq 'off') {
			HMCCU_StopRPCServer ($hash);
		}
		
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'restartrpc') {
		my @hm_pids;
		my @ex_pids;
		if (HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids)) {
			if (HMCCU_StopRPCServer ($hash)) {
				$hash->{RPCState} = "restarting";
				readingsSingleUpdate ($hash, "rpcstate", "restarting", 1);
				DoTrigger ($name, "RPC server restarting");
				return undef;
			}
			else {
				return "HMCCU: Can't stop RPC server";
			}
		}
		else {
			return "HMCCU: RPC server not running";
		}
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
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;
	my $options = "devicelist:noArg devstate datapoint dump vars channel update updateccu parfile config configdesc rpcstate:noArg deviceinfo";
	my $host = $hash->{host};

	if (HMCCU_IsRPCStateBlocking ($hash)) {
		return undef if ($opt eq '?');
		return HMCCU_SetState ($hash, "busy");
	}

	my $ccureadingformat = AttrVal ($name, "ccureadingformat", 'name');
	my $ccureadings = AttrVal ($name, "ccureadings", 1);
	my $parfile = AttrVal ($name, "parfile", '');
	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my $substitute = AttrVal ($name, 'substitute', '');
	my $rpcport = AttrVal ($name, 'rpcport', '2001');

	my $readname;
	my $readaddr;
	my $result = '';
	my $rc;

	if ($opt eq 'devstate') {
		my $ccuobj = shift @a;
		my $reading = shift @a;

		return HMCCU_SetError ($hash, "Usage: get $name devstate {channel} [reading]")
		   if (!defined ($ccuobj));
		$reading = '' if (!defined ($reading));

		($rc, $result) = HMCCU_GetDatapoint ($hash, $ccuobj.'.'.$statedatapoint, $reading);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'datapoint') {
		my $ccuobj = shift @a;
		my $reading = shift @a;

		return HMCCU_SetError ($hash, "Usage: get $name datapoint {channel}.{datapoint} [reading]")
		   if (!defined ($ccuobj));
		$reading = '' if (!defined ($reading));

		($rc, $result) = HMCCU_GetDatapoint ($hash, $ccuobj, $reading);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'dump') {
		my $content = shift @a;
		my $filter = shift @a;
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
			return HMCCU_SetError ($hash, "Usage: get $name dump {datapoints|devtypes} {filter}");
		}
		
		return "No data found" if ($result eq '');
		return $result;
	}
	elsif ($opt eq 'vars') {
		my $varname = shift @a;

		return HMCCU_SetError ($hash, "Usage: get $name vars {regexp}[,...]")
		   if (!defined ($varname));

		($rc, $result) = HMCCU_GetVariables ($hash, $varname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'channel') {
		my @chnlist;

		foreach my $objname (@a) {
			last if (!defined ($objname));
			if ($objname =~ /^.*=/) {
				$objname =~ s/=/ /;
			}
			push (@chnlist, $objname);
		}

		return HMCCU_SetError ($hash, "Usage: get $name channel {channel}[.{datapoint-expr}] [...]")
		   if (@chnlist == 0);

		($rc, $result) = HMCCU_GetChannel ($hash, \@chnlist);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'update' || $opt eq 'updateccu') {
		my $devexp = shift @a;
		$devexp = '.*' if (!defined ($devexp));
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name $opt [device-expr [{'State'|'Value'}]]");
		}

		my ($c_ok, $c_err) = HMCCU_UpdateClients ($hash, $devexp, $ccuget, ($opt eq 'updateccu') ? 1 : 0);

		HMCCU_SetState ($hash, "OK");
		return "$c_ok client devices successfully updated. Update for $c_err client devices failed";
	}
	elsif ($opt eq 'parfile') {
		my $par_parfile = shift @a;
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
			return HMCCU_SetError ($hash, "Can't open file $parfile");
		}

		return HMCCU_SetError ($hash, "Empty parameter file") if ($parcount < 1);

		($rc, $result) = HMCCU_GetChannel ($hash, \@parameters);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'deviceinfo') {
		my $device = shift @a;

		return HMCCU_SetError ($hash, "Usage: get $name deviceinfo {device} [{'State'|'Value'}]")
		   if (!defined ($device));

		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		return HMCCU_SetError ($hash, "Usage: get $name deviceinfo {device} [{'State'|'Value'}]")
		   if ($ccuget !~ /^(Attr|State|Value)$/);

		return HMCCU_SetError ($hash, -1) if (!HMCCU_IsValidDevice ($device));
		$result = HMCCU_GetDeviceInfo ($hash, $device, $ccuget);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		return HMCCU_FormatDeviceInfo ($result);
	}
	elsif ($opt eq 'rpcstate') {
		my @pidlist;
		foreach my $port (split (',', $rpcport)) {
			my $pid = HMCCU_CheckProcess ($hash, $port);
			push (@pidlist, $pid) if ($pid > 0);
		}
		if (@pidlist > 0) {
			return "RPC process(es) running with pid(s) ".join (',', @pidlist);;
		}
		else {
			return "RPC process not running";
		}
	}
	elsif ($opt eq 'devicelist') {
		my $dumplist = shift @a;

		$hash->{DevCount} = HMCCU_GetDeviceList ($hash);

		if ($hash->{DevCount} < 0) {
			return HMCCU_SetError ($hash, -2);
		}
		elsif ($hash->{DevCount} == 0) {
			return HMCCU_SetError ($hash, "No devices received from CCU");
		}

		HMCCU_SetState ($hash, "OK");

		if (defined ($dumplist) && $dumplist eq 'dump') {
			foreach my $add (sort keys %HMCCU_Devices) {
				$result .= $HMCCU_Devices{$add}{name}."\n";
			}
			return $result;
		}

		return "Read ".$hash->{DevCount}." devices/channels from CCU";
	}
	elsif ($opt eq 'config') {
		my $ccuobj = shift @a;

		return HMCCU_SetError ($hash, "Usage: get $name config {device|channel}")
		   if (!defined ($ccuobj));

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamset");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $res;
	}
	elsif ($opt eq 'configdesc') {
		my $ccuobj = shift @a;

		return HMCCU_SetError ($hash, "Usage: get $name configdesc {device|channel}")
		   if (!defined ($ccuobj));

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $res;
	}
	else {
		return "HMCCU: Unknown argument $opt, choose one of ".$options;
	}
}

##################################################################
# Parse CCU object specification
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
#
# Return list of detected attributes:
#   (Interface, Address, Channel, Datapoint, Name, Flags)
##################################################################

sub HMCCU_ParseObject ($$)
{
	my ($object, $flags) = @_;
	my ($i, $a, $c, $d, $n, $f) = ('', '', '', '', '', '', 0);

	if ($object =~ /^(.+?)\.([A-Z]{3}[0-9]{7}):([0-9]{1,2})\.(.+)$/ ||
		$object =~ /^(.+?)\.([0-9A-F]{14}):([0-9]{1,2})\.(.+)$/) {
		#
		# Interface.Address:Channel.Datapoint [30=11110]
		#
		$f = $HMCCU_FLAGS_IACD;
		($i, $a, $c, $d) = ($1, $2, $3, $4);
	}
	elsif ($object =~ /^(.+)\.([A-Z]{3}[0-9]{7}):([0-9]{1,2})$/ ||
		$object =~ /^(.+)\.([0-9A-F]{14}):([0-9]{1,2})$/) {
		#
		# Interface.Address:Channel [26=11010]
		#
		$f = $HMCCU_FLAGS_IAC | ($flags & $HMCCU_FLAG_DATAPOINT);
		($i, $a, $c, $d) = ($1, $2, $3, $flags & $HMCCU_FLAG_DATAPOINT ? '.*' : '');
	}
	elsif ($object =~ /^([A-Z]{3}[0-9]{7}):([0-9]){1,2}\.(.+)$/ ||
		$object =~ /^([0-9A-F]{14}):([0-9]){1,2}\.(.+)$/) {
		#
		# Address:Channel.Datapoint [14=01110]
		#
		$f = $HMCCU_FLAGS_ACD;
		($a, $c, $d) = ($1, $2, $3);
	}
	elsif ($object =~ /^([A-Z]{3}[0-9]{7}):([0-9]){1,2}$/ ||
		$object =~ /^([0-9A-Z]{14}):([0-9]){1,2}$/) {
		#
		# Address:Channel [10=01010]
		#
		$f = $HMCCU_FLAGS_AC | ($flags & $HMCCU_FLAG_DATAPOINT);
		($a, $c, $d) = ($1, $2, $flags & $HMCCU_FLAG_DATAPOINT ? '.*' : '');
	}
	elsif ($object =~ /^([A-Z]{3}[0-9]{7})$/ ||
		$object =~ /^([0-9A-Z]{14})$/) {
		#
		# Address
		#
		$f = $HMCCU_FLAG_ADDRESS;
		$a = $1;
	}
	elsif ($object =~ /^(.+?)\.(.+)$/) {
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
		my ($add, $chn) = HMCCU_GetAddress ($n, '', '');
		if ($chn ne '') {
			$f = $f | $HMCCU_FLAG_CHANNEL;
		}
		if ($flags & $HMCCU_FLAG_FULLADDR) {
			($i, $a, $c) = (HMCCU_GetDeviceInterface ($add, 'BidCos-RF'), $add, $chn);
			$f |= $HMCCU_FLAG_INTERFACE;
			$f |= $HMCCU_FLAG_ADDRESS if ($add ne '');
			$f |= $HMCCU_FLAG_CHANNEL if ($chn ne '');
		}
	}
	elsif ($f & $HMCCU_FLAG_ADDRESS && $i eq '' &&
	   ($flags & $HMCCU_FLAG_FULLADDR || $flags & $HMCCU_FLAG_INTERFACE)) {
		$i = HMCCU_GetDeviceInterface ($a, 'BidCos-RF');
		$f |= $HMCCU_FLAG_INTERFACE;
	}

	return ($i, $a, $c, $d, $n, $f);
}

##################################################################
# Filter reading by datapoint and optionally by channel name
# Parameters: hash, channel, datapoint
##################################################################

sub HMCCU_FilterReading ($$$)
{
	my ($hash, $chn, $dpt) = @_;
	my $name = $hash->{NAME};

	my $rf = AttrVal ($name, 'ccureadingfilter', '.*');
	return 1 if ($rf eq '.*');

	my $chnnam = HMCCU_IsChnAddr ($chn, 0) ? HMCCU_GetChannelName ($chn, '') : $chn;

	my @rules = split (",", $rf);
	foreach my $r (@rules) {
		my ($c, $f) = split ("!", $r);
		if (defined ($f) && $chnnam ne '') {
			if ($chnnam =~ /$c/) {
				return ($dpt =~ /$f/) ? 1 : 0;
			}
		}
		else {
			return 1 if ($dpt =~ /$r/);
		}
	}

	return 0;
}

##################################################################
# Build reading name
#
# Parameters:
#
#   Interface,Address,ChannelNo,Datapoint,ChannelNam,ReadingFormat
#
#   ReadingFormat := { name | datapoint | address }
#
# Valid combinations:
#
#   ChannelNam,Datapoint
#   Address,Datapoint
#   Address,ChannelNo,Datapoint
##################################################################

sub HMCCU_GetReadingName ($$$$$$)
{
	my ($i, $a, $c, $d, $n, $rf) = @_;
	my $rn = '';

	Log3 undef, 1, "HMCCU: ChannelNo undefined: Addr=".$a if (!defined ($c));
	
	# Datapoint is mandatory
	return '' if ($d eq '');

	if ($rf eq 'datapoint') {
		$rn = $d;
	}
	elsif ($rf eq 'name') {
		if ($n eq '') {
			if ($a ne '' && $c ne '') {
				$n = HMCCU_GetChannelName ($a.':'.$c, '');
			}
			elsif ($a ne '' && $c eq '') {
				$n = HMCCU_GetDeviceName ($a, '');
			}
			else {
				return '';
			}
		}

		$n =~ s/\:/\./g;
		$n =~ s/[^A-Za-z\d_\.-]+/_/g;

		$rn = $n ne '' ? $n.'.'.$d : '';
	}
	elsif ($rf eq 'address') {
		if ($a eq '' && $n ne '') {
			($a, $c) = HMCCU_GetAddress ($n, '', '');
		}

		if ($a ne '') {
			my $t = $a;
			$i = HMCCU_GetDeviceInterface ($a, '') if ($i  eq '');
			$t = $i.'.'.$t if ($i ne '');
			$t = $t.'.'.$c if ($c ne '');

			$rn = $t.'.'.$d;
		}
	}

	return $rn;
}

##################################################################
# Format reading value depending attribute stripnumber.
##################################################################

sub HMCCU_FormatReadingValue ($$)
{
	my ($hash, $value) = @_;

	my $stripnumber = AttrVal ($hash->{NAME}, 'stripnumber', 0);

	if ($stripnumber == 1) {
		$value =~ s/(\.[0-9])[0-9]+/$1/;
	}
	elsif ($stripnumber == 2) {
		$value =~ s/[0]+$//;
		$value =~ s/\.$//;
	}

	return $value;
}

##################################################################
# Set error state and write log file message
##################################################################

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
	   -9 => 'Interface does not support RPC calls'
	);

	$msg = exists ($errlist{$text}) ? $errlist{$text} : $text;
	$msg = $type.": ".$name." ". $msg;

	HMCCU_SetState ($hash, "Error");
	Log3 $name, 1, $msg;
	return $msg;
}

##################################################################
# Set state
##################################################################

sub HMCCU_SetState ($$)
{
	my ($hash, $text) = @_;

	if (defined ($hash) && defined ($text)) {
		readingsSingleUpdate ($hash, "state", $text, 1);
	}

	return ($text eq "busy") ? "HMCCU: CCU busy" : undef;
}

##################################################################
# Substitute first occurrence of regular expressions or fixed
# string. Floating point values are ignored. Integer values are
# compared with complete value.
# mode: 0=Substitute regular expression, 1=Substitute text
##################################################################

sub HMCCU_Substitute ($$$$)
{
	my ($value, $substrule, $mode, $reading) = @_;
	my $rc = 0;
	my $newvalue;

	return $value if (!defined ($substrule) || $substrule eq '');
	return $value if ($value !~ /^[+-]?\d+$/ && $value =~ /^[+-]?\d*\.?\d+(?:(?:e|E)\d+)?$/);

	$reading =~ s/.+\.(.+)$/$1/;

	my @rulelist = split (';', $substrule);
	foreach my $rule (@rulelist) {
		my @ruletoks = split ('!', $rule);
		if (@ruletoks == 2 && $reading ne '' && $mode == 0) {
			my @dptlist = split (',', $ruletoks[0]);
			foreach my $dpt (@dptlist) {
				if ($dpt eq $reading) {
					($rc, $newvalue) = HMCCU_SubstRule ($value, $ruletoks[1], $mode);
					return $newvalue;
				}
			}
		}
		elsif (@ruletoks == 1) {
			($rc, $newvalue) = HMCCU_SubstRule ($value, $ruletoks[0], $mode);
			return $newvalue if ($rc == 1);
		}
	}

	return $value;
}

##################################################################
# Execute substitution
##################################################################

sub HMCCU_SubstRule ($$$)
{
	my ($value, $substitutes, $mode ) = @_;
	my $rc = 0;

	my @sub_list = split /,/,$substitutes;
	foreach my $s (@sub_list) {
		my ($regexp, $text) = split /:/,$s;
		next if (!defined ($regexp) || !defined($text));
		if ($mode == 0 && $value =~ /$regexp/ && $value !~ /^[+-]?\d+$/) {
			$value =~ s/$regexp/$text/;
			$rc = 1;
			last;
		}
		elsif (($mode == 1 || $value =~/^[+-]?\d+$/) && $value =~ /^$regexp$/) {
			$value =~ s/^$regexp$/$text/;
			$rc = 1;
			last;
		}
	}

	return ($rc, $value);
}

##################################################################
# Update all datapoint/readings of all client devices. Update
# will fail if attribute ccureadings of a device is set to 0.
##################################################################

sub HMCCU_UpdateClients ($$$$)
{
	my ($hash, $devexp, $ccuget, $fromccu) = @_;
	my $fhname = $hash->{NAME};
	my $c_ok = 0;
	my $c_err = 0;

	if ($fromccu) {
		foreach my $name (sort keys %HMCCU_Addresses) {
			next if ($name !~ /$devexp/ || !($HMCCU_Addresses{$name}{valid}));

			foreach my $d (keys %defs) {
				my $ch = $defs{$d};
				next if ($ch->{TYPE} ne 'HMCCUDEV' && $ch->{TYPE} ne 'HMCCUCHN');
				next if ($ch->{ccudevstate} ne 'Active');
				next if ($ch->{ccuaddr} ne $HMCCU_Addresses{$name}{address});
				next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));

				my $rc = HMCCU_GetUpdate ($ch, $HMCCU_Addresses{$name}{address}, $ccuget);
				if ($rc <= 0) {
					Log3 $fhname, 1, "HMCCU: Update of device $name failed";
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
			next if ($ch->{TYPE} ne 'HMCCUDEV' && $ch->{TYPE} ne 'HMCCUCHN');
			next if ($ch->{ccudevstate} ne 'Active');
			next if ($ch->{NAME} !~ /$devexp/);
			next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));

			my $rc = HMCCU_GetUpdate ($ch, $ch->{ccuaddr}, $ccuget);
			if ($rc <= 0) {
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
# Update HMCCU readings and client readings.
#
# Parameters:
#   hash, devadd, channelno, reading, value, [mode]
#
# Parameter devadd can be a device or a channel address. If
# devadd is a channel address parameter channel should be ''.
# Valid modes are: hmccu, rpcevent, client.
# Reading values are substituted if attribute substitute is set
# in client device.
##################################################################

sub HMCCU_UpdateClientReading ($@)
{
	my ($hash, $devadd, $channel, $reading, $value, $mode) = @_;
	my $name = $hash->{NAME};

	my $hmccu_substitute = AttrVal ($name, 'substitute', '');
	my $hmccu_updreadings = AttrVal ($name, 'ccureadings', 1);
#	my $hmccu_flt = AttrVal ($name, 'ccureadingfilter', '.*');
	my $updatemode = AttrVal ($name, 'updatemode', 'hmccu');

	# Update mode can be: client, hmccu, both, rpcevent
	$updatemode = $mode if (defined ($mode));

	# Check syntax
	return 0 if (!defined ($hash) || !defined ($devadd) ||
	   !defined ($channel) || !defined ($reading) || !defined ($value));

	my $chnadd = $channel ne '' ? $devadd.':'.$channel : $devadd;
	my $hmccu_value = '';
	my $dpt = '';
	if ($reading =~ /.*\.(.+)$/) {
		$dpt = $1;
	}

	if ($hmccu_updreadings && $updatemode ne 'client') {
		$hmccu_value = HMCCU_Substitute ($value, $hmccu_substitute, 0, $reading);
		$hmccu_value = HMCCU_FormatReadingValue ($hash, $hmccu_value);
#		if ($updatemode ne 'rpcevent' && ($dpt eq '' || $dpt =~ /$hmccu_flt/)) {
		if ($updatemode ne 'rpcevent' && ($dpt eq '' ||
		   HMCCU_FilterReading ($hash, $chnadd, $dpt))) {
			readingsSingleUpdate ($hash, $reading, $hmccu_value, 1);
		}
		return $hmccu_value if ($updatemode eq 'hmccu');
	}

	# Update client readings
	foreach my $d (keys %defs) {
		# Get hash and name of client device
		my $ch = $defs{$d};
		my $cn = $ch->{NAME};

		next if ($ch->{TYPE} ne 'HMCCUDEV' && $ch->{TYPE} ne 'HMCCUCHN');
		next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));
		next if ($ch->{IODev} != $hash);
		if ($ch->{ccuif} eq "VirtualDevices" && exists ($ch->{ccugroup})) {
			my @gdevs = split (",", $ch->{ccugroup});
			next if (!($devadd ~~ @gdevs) && !($chnadd ~~ @gdevs));
		}
		else {
			next if ($ch->{ccuaddr} ne $devadd && $ch->{ccuaddr} ne $chnadd);
		}

		# Get attributes of client device
		my $dis = AttrVal ($cn, 'disable', 0);
		my $upd = AttrVal ($cn, 'ccureadings', 1);
		my $crf = AttrVal ($cn, 'ccureadingformat', 'name');
#		my $flt = AttrVal ($cn, 'ccureadingfilter', '.*');
		my $mapdatapoints = AttrVal ($cn, 'mapdatapoints', '');
		my $substitute = AttrVal ($cn, 'substitute', '');
		my ($sc, $st, $cc, $cd) = HMCCU_GetSpecialDatapoints ($ch, 'STATE', '', '', '');
		last if ($upd == 0 || $dis == 1);
		next if (!HMCCU_FilterReading ($ch, $chnadd, $dpt));
#		next if ($dpt eq '' || $dpt !~ /$flt/);

		my $clreading = HMCCU_GetReadingName ('', $devadd, $channel, $dpt, '', $crf);
		next if ($clreading eq '');

		# Client substitute attribute has priority
		my $cl_value;
		if ($substitute ne '') {
			$cl_value = HMCCU_Substitute ($value, $substitute, 0, $clreading);
		}
		else {
			$cl_value = HMCCU_Substitute ($value, $hmccu_substitute, 0, $clreading);
		}
		$cl_value = HMCCU_FormatReadingValue ($ch, $cl_value);

		# Update reading and control/state readings
		readingsSingleUpdate ($ch, $clreading, $cl_value, 1);
		if ($cd ne '' && $dpt eq $cd && $channel eq $cc) {
			readingsSingleUpdate ($ch, 'control', $cl_value, 1);
		}
		if ($clreading =~ /\.$st$/ && ($sc eq '' || $sc eq $channel)) {
			HMCCU_SetState ($ch, $cl_value);
		}

		# Map datapoints for virtual devices (groups)
		if ($mapdatapoints ne '') {
			foreach my $m (split (",", $mapdatapoints)) {
				my @mr = split ("=", $m);
				next if (@mr != 2);
#				Log3 $name, 1, "HMCCU: Mapping dp ".$mr[0]." to ".$mr[1];
				my ($i1, $a1, $c1, $d1, $n1, $f1) =
				   HMCCU_ParseObject ($mr[0], $HMCCU_FLAG_FULLADDR);
				my ($i2, $a2, $c2, $d2, $n2, $f2) =
				   HMCCU_ParseObject ($mr[1], $HMCCU_FLAG_FULLADDR);
#				Log3 $name, 1, "HMCCU: f1 or f2 != FLAGS_AC" if (($f1 & $HMCCU_FLAGS_AC) != $HMCCU_FLAGS_AC || ($f2 & $HMCCU_FLAGS_AC) != $HMCCU_FLAGS_AC);
				next if (($f1 & $HMCCU_FLAGS_AC) != $HMCCU_FLAGS_AC ||
				   ($f2 & $HMCCU_FLAGS_AC) != $HMCCU_FLAGS_AC);
#				Log3 $name, 1, "HMCCU: $devadd ne $a1 or $channel ne $c1 or $dpt ne $d1" if ($devadd ne $a1 || $channel ne $c1 || $dpt ne $d1);
				next if ($devadd ne $a1 || $channel ne $c1 || $dpt ne $d1);
				my $mreading = HMCCU_GetReadingName ('', $a2, $c2, $d2, '', $crf);
#				Log3 $name, 1, "HMCCU: Can't get reading name for $a2, $c2, $d2" if ($mreading eq '');
				next if ($mreading eq '');
				readingsSingleUpdate ($ch, $mreading, $cl_value, 1);
				if ($cd ne '' && $d2 eq $cd && $c2 eq $cc) {
					readingsSingleUpdate ($ch, 'control', $cl_value, 1);
				}
				if ($mreading =~ /\.$st/ && ($sc eq '' || $sc eq $c2)) {
					HMCCU_SetState ($ch, $cl_value);
				}
			}
		}
	}

	return $hmccu_value;
}

####################################################
# Mark client devices deleted in CCU as invalid
####################################################

sub HMCCU_DeleteDevices ($)
{
	my ($devlist) = @_;

	foreach my $a (@$devlist) {
		my $cc = $HMCCU_Devices{$a}{channels};
		$HMCCU_Devices{$a}{valid} = 0;
		$HMCCU_Addresses{$HMCCU_Devices{$a}{name}}{valid} = 0;
		for (my $i=0; $i<$cc; $i++) {
			$HMCCU_Devices{$a.':'.$i}{valid} = 0;
			$HMCCU_Addresses{$HMCCU_Devices{$a.':'.$i}{name}}{valid} = 0;
		}
		foreach my $d (keys %defs) {
			my $ch = $defs{$d};
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
# Start RPC server
####################################################

sub HMCCU_StartRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $modpath = AttrVal ('global', 'modpath', '/opt/fhem');
	my $logfile = $modpath."/log/ccurpcd";
	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
	my $rpcport = AttrVal ($name, 'rpcport', '2001');
	
	my $serveraddr = $hash->{host};
	my $localaddr = '';

	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	if (@hm_pids > 0) {
		Log3 $name, 1, "HMCCU: RPC server(s) already running with PIDs ".join (',', @hm_pids);
		return scalar (@hm_pids);
	}
	elsif (@ex_pids > 0 && $ccuflags !~ /extrpc/) {
		Log3 $name, 1, "HMCCU: Externally launched RPC server(s) detected. Kill process(es) manually with command kill -SIGINT pid for pid=".join (',', @ex_pids);
		return 0;
	}

	# Check if RPC server exists
	my $rpcserver = $modpath."/FHEM/ccurpcd.pl";
	if (! -e $rpcserver) {
		Log3 $name, 1, "HMCCU: RPC server file ccurpcd.pl not found in ".$modpath."/FHEM";
		return 0;
	}
	
	# Clear RPC queues
	HMCCU_ResetRPCQueue ($hash);

	my $fork_cnt = 0;
	my $callbackport = 0;
	
	# Fork child process(es)
	foreach my $port (split (',', $rpcport)) {
		$callbackport = 5400+$port if ($callbackport == 0 || $ccuflags !~ /singlerpc/);
	
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

		# Create RPC client
		my $clkey = 'CB'.$port;
		my $rpcclient = RPC::XML::Client->new ("http://$serveraddr:$port/");
		$hash->{hmccu}{rpc}{$clkey}{port} = $port;

		# Check if RPC daemon on CCU is listening on port
		my $resp = $rpcclient->send_request ('system.listMethods');
		if (!ref($resp)) {
			Log3 $name, 1, "No response from CCU on port $port. $resp";
			next;
		}
	
		my $rpcqueueport = $rpcqueue."_".$port;
		my $logfileport = $logfile."_".$port.".log";

		if ($fork_cnt == 0 || $ccuflags !~ /singlerpc/) {
			my $pid = fork ();
			if (!defined ($pid)) {
				Log3 $name, 1, "HMCCU: Can't fork child process for CCU port $port";
				next;
			}
			if (!$pid) {
				# Child process. Replaced by RPC server
				exec ($rpcserver." ".$serveraddr." ".$port." ".$rpcqueueport." ".$logfileport);

				# When we reach this line start of RPC server failed and child process can exit
				die;
			}
			
			# Parent process
			# Wait 2 seconds to ensure that RPC server is listening
			sleep (2);
			
			# Store PID
			push (@hm_pids, $pid);
			$hash->{hmccu}{rpc}{$clkey}{pid} = $pid;
			$hash->{hmccu}{rpc}{$clkey}{queue} = $rpcqueueport;
			$hash->{hmccu}{rpc}{$clkey}{state} = "starting";
			Log3 $name, 0, "HMCCU: RPC server started with pid ".$pid;
		
			$fork_cnt++;
		}
		else {
			$hash->{hmccu}{rpc}{$clkey}{pid} = 0;
			$hash->{hmccu}{rpc}{$clkey}{state} = "stopped";
			$hash->{hmccu}{rpc}{$clkey}{queue} = '';
		}

		# Register callback in CCU
		my $callbackurl = "http://".$localaddr.":".$callbackport."/fh".$port;
		$hash->{hmccu}{rpc}{$clkey}{cburl} = $callbackurl;
		$hash->{hmccu}{rpccount} = $fork_cnt;
		Log3 $name, 1, "HMCCU: Registering callback $callbackurl with ID CB".$port;
		$rpcclient->send_request ("init", $callbackurl, "CB".$port);
		Log3 $name, 1, "HMCCU: RPC callback with URL ".$callbackurl." initialized";
	}

	$hash->{RPCPID} = join (',', @hm_pids);
	$hash->{RPCPRC} = $rpcserver;
	$hash->{RPCState} = "starting";
	readingsSingleUpdate ($hash, "rpcstate", "starting", 1);	
	DoTrigger ($name, "RPC server starting");

	InternalTimer (gettimeofday()+$HMCCU_INIT_INTERVAL, 'HMCCU_ReadRPCQueue', $hash, 0);

	return scalar (@hm_pids);
}

####################################################
# Stop RPC server(s) / send SIGINT to process(es)
####################################################

sub HMCCU_StopRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $rpcport = AttrVal ($name, 'rpcport', '2001');
	my $serveraddr = $hash->{host};

	# Deregister callback URLs in CCU
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		if (exists ($hash->{hmccu}{rpc}{$clkey}{cburl}) && $hash->{hmccu}{rpc}{$clkey}{cburl} ne '') {
			my $port = $hash->{hmccu}{rpc}{$clkey}{port};
			my $rpcclient = RPC::XML::Client->new ("http://$serveraddr:$port/");
			Log3 $name, 1, "HMCCU: Deregistering RPC server ".$hash->{hmccu}{rpc}{$clkey}{cburl};
			$rpcclient->send_request("init", $hash->{hmccu}{rpc}{$clkey}{cburl});
			$hash->{hmccu}{rpc}{$clkey}{cburl} = '';
		}
	}
	
	# Send signal SIGINT to RPC server processes
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		my $pid = $hash->{hmccu}{rpc}{$clkey}{pid};
		if ($pid > 0) {
			Log3 $name, 0, "HMCCU: Stopping RPC server $clkey with PID $pid";
			kill ('INT', $pid);
			$hash->{hmccu}{rpc}{$clkey}{state} = "stopping";
		}
	}
	
	if ($hash->{hmccu}{rpccount} > 0) {
		readingsSingleUpdate ($hash, "rpcstate", "stopping", 1);
		$hash->{RPCState} = "stopping";
	}
	
	# Kill the rest
	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	if (@hm_pids > 0) {
		foreach my $pid (@hm_pids) {
			Log3 $name, 0, "HMCCU: Stopping RPC server with PID $pid";
			kill ('INT', $pid);
		}		
	}
	else {
		Log3 $name, 0, "HMCCU: RPC server not running";
		return 0;
	}

	if (@ex_pids > 0 && $ccuflags !~ /extrpc/) {
		Log3 $name, 0, "HMCCU: Externally launched RPC server detected.";
		foreach my $pid (@ex_pids) {
			kill ('INT', $pid);
		}
		return 0;
	}

	return 1;
}

sub HMCCU_ForceStopRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	# Send signal SIGINT to RPC server processes
	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	if (@hm_pids > 0) {
		foreach my $pid (@hm_pids) {
			Log3 $name, 0, "HMCCU: RPC Server with PID $pid still running. Sending SIGINT again";
			kill ('INT', $pid);
		}
	}
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

	my @rpcpids;
	if (defined ($hash->{RPCPID}) && $hash->{RPCPID} ne '0') {
		@rpcpids = split (',', $hash->{RPCPID});
	}

	my $rpcport = AttrVal ($hash->{NAME}, 'rpcport', '2001');
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
#		return $procattr[1] if ($procattr[1] != $$ && $procattr[7] =~ /perl$/ &&
#		   $procattr[8] eq $rpcserver && $procattr[10] eq "$port");
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

	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($device, 0);
	if ($flags == $HMCCU_FLAG_ADDRESS) {
		$devname = HMCCU_GetDeviceName ($add, '');
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
	if ($ccutrace ne '' && ($device =~ /$ccutrace/ || $devname =~ /$ccutrace/)) {
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
	
	my %vtypes = (2, "b", 4, "f", 11, "s", 16, "i", 20, "s", 29, "e");
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

	%HMCCU_Devices = ();
	%HMCCU_Addresses = ();
	$hash->{hmccu}{updatetime} = time ();

	foreach my $hmdef (split /\n/,$response) {
		my @hmdata = split /;/,$hmdef;
		if ($hmdata[0] eq 'D') {
			# 1=Interface 2=Device-Address 3=Device-Name 4=Device-Type 5=Channel-Count
			$HMCCU_Devices{$hmdata[2]}{name} = $hmdata[3];
			$HMCCU_Devices{$hmdata[2]}{type} = $hmdata[4];
			$HMCCU_Devices{$hmdata[2]}{interface} = $hmdata[1];
			$HMCCU_Devices{$hmdata[2]}{channels} = $hmdata[5];
			$HMCCU_Devices{$hmdata[2]}{addtype} = 'dev';
			$HMCCU_Devices{$hmdata[2]}{valid} = 1;
			$HMCCU_Addresses{$hmdata[3]}{address} = $hmdata[2];
			$HMCCU_Addresses{$hmdata[3]}{addtype} = 'dev';
			$HMCCU_Addresses{$hmdata[3]}{valid} = 1;
			$count++;
		}
		elsif ($hmdata[0] eq 'C') {
			# 1=Channel-Address 2=Channel-Name
			$HMCCU_Devices{$hmdata[1]}{name} = $hmdata[2];
			$HMCCU_Devices{$hmdata[1]}{channels} = 1;
			$HMCCU_Devices{$hmdata[1]}{addtype} = 'chn';
			$HMCCU_Devices{$hmdata[1]}{valid} = 1;
			$HMCCU_Addresses{$hmdata[2]}{address} = $hmdata[1];
			$HMCCU_Addresses{$hmdata[2]}{addtype} = 'chn';
			$HMCCU_Addresses{$hmdata[2]}{valid} = 1;
			$count++;
		}
	}

	HMCCU_GetDatapointList ($hash);
	
	# Update client devices
	foreach my $d (keys %defs) {
		# Get hash of client device
		my $ch = $defs{$d};
		next if ($ch->{TYPE} ne 'HMCCUDEV' && $ch->{TYPE} ne 'HMCCUCHN');
		next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));
		next if ($ch->{TYPE} eq 'HMCCUDEV' && $ch->{ccuif} eq "VirtualDevices" &&
		   $ch->{ccuname} eq 'none');
		my $add = $ch->{ccuaddr};
		my $dadd = $add;
		$dadd =~ s/:[0-9]+$//;

		# Update device or channel attributes if it has changed in CCU
		$ch->{ccuname} = $HMCCU_Devices{$add}{name}
		   if (!defined ($ch->{ccuname}) || $ch->{ccuname} ne $HMCCU_Devices{$add}{name});
		$ch->{ccuif} = $HMCCU_Devices{$dadd}{interface}
		   if (!defined ($ch->{ccuif}) || $ch->{ccuif} ne $HMCCU_Devices{$dadd}{interface});
		$ch->{ccutype} = $HMCCU_Devices{$dadd}{type}
		   if (!defined ($ch->{ccutype}) || $ch->{ccutype} ne $HMCCU_Devices{$dadd}{type});
		$ch->{channels} = $HMCCU_Devices{$add}{channels}
		   if (!defined ($ch->{channels}) || $ch->{channels} != $HMCCU_Devices{$add}{channels});
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
	foreach my $add (sort keys %HMCCU_Devices) {
		next if ($HMCCU_Devices{$add}{addtype} ne 'dev' ||
		   $HMCCU_Devices{$add}{interface} eq 'CUxD');
		my $dt = $HMCCU_Devices{$add}{type};
		if ($dt ne '' && !exists ($alltypes{$dt})) {
			$alltypes{$dt} = 1;
			push @devunique, $HMCCU_Devices{$add}{name};
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
            WriteLine (sType # ";" # sChnNo # ";" # sDPName # ";" # oDP.ValueType() # ";" # oDP.Operations());
          }
        }
      }
    }
  }
}
	);

	my $response = HMCCU_HMScript ($hash, $script);
	return 0 if ($response eq '');
#	Log3 $name, 1, $response;
	
	my $c = 0;
	foreach my $dpspec (split /\n/,$response) {
		my ($devt, $devc, $dptn, $dptt, $dpto) = split (";", $dpspec);
		$hash->{hmccu}{$devt}{ontime} = $devc.".".$dptn if ($dptn eq "ON_TIME");
		$hash->{hmccu}{dp}{$devt}{ch}{$devc}{$dptn}{type} = $dptt;
		$hash->{hmccu}{dp}{$devt}{ch}{$devc}{$dptn}{oper} = $dpto;
		$c++;
	}
	
#	Log3 $name, 1, Dumper($hash->{hmccu}{dp});
	
	return $c;
}

####################################################
# Check if device/channel name or address is valid
# and refers to an existing device or channel.
####################################################

sub HMCCU_IsValidDevice ($)
{
	my ($param) = @_;

	if (HMCCU_IsDevAddr ($param, 0) || HMCCU_IsChnAddr ($param, 0)) {
		return 0 if (! exists ($HMCCU_Devices{$param}));
		return $HMCCU_Devices{$param}{valid};
	}
	else {
		return 0 if (! exists ($HMCCU_Addresses{$param}));
		return $HMCCU_Addresses{$param}{valid};
	}
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
# Check if datapoint is valid.
# Parameter chn can be a channel address or a channel
# number.
# Return 1 if datapoint information is not available
# in IO device.
####################################################

sub HMCCU_IsValidDatapoint ($$$$$)
{
	my ($hash, $devtype, $chn, $dpt, $oper) = @_;

	my $hmccu_hash = HMCCU_GetHash ($hash);
	
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

	foreach my $name (sort keys %HMCCU_Addresses) {
		next if ($name !~/$regexp/ || $HMCCU_Addresses{$name}{addtype} ne $mode ||
		   $HMCCU_Addresses{$name}{valid} == 0);
		push (@$listref, $HMCCU_Addresses{$name}{address});
		$c++;
	}

	return $c;
}

####################################################
# Get name of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceName ($$)
{
	my ($addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($HMCCU_Devices{$addr})) {
			return $HMCCU_Devices{$addr}{name};
		}
	}

	return $default;
}

####################################################
# Get name of a CCU device channel by address.
####################################################

sub HMCCU_GetChannelName ($$)
{
	my ($addr, $default) = @_;

	if (HMCCU_IsChnAddr ($addr, 0)) {
		if (exists ($HMCCU_Devices{$addr})) {
			return $HMCCU_Devices{$addr}{name};
		}
	}

	return $default;
}

####################################################
# Get type of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceType ($$)
{
	my ($addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($HMCCU_Devices{$addr})) {
			return $HMCCU_Devices{$addr}{type};
		}
	}

	return $default;
}


####################################################
# Get number of channels of a CCU device.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceChannels ($)
{
	my ($addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($HMCCU_Devices{$addr})) {
			return $HMCCU_Devices{$addr}{channels};
		}
	}

	return 0;
}

####################################################
# Get interface of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceInterface ($$)
{
	my ($addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($HMCCU_Devices{$addr})) {
			return $HMCCU_Devices{$addr}{interface};
		}
	}

	return $default;
}

####################################################
# Get address of a CCU device or channel by name.
# Return array with device address and channel no.
####################################################

sub HMCCU_GetAddress ($$$)
{
	my ($name, $defadd, $defchn) = @_;
	my $add = $defadd;
	my $chn = $defchn;

	if (exists ($HMCCU_Addresses{$name})) {
		# Address known by HMCCU
		my $addr = $HMCCU_Addresses{$name}{address};
		if (HMCCU_IsChnAddr ($addr, 0)) {
			($add, $chn) = split (":", $addr);
		}
		elsif (HMCCU_IsDevAddr ($addr, 0)) {
			$add = $addr;
		}
	}
	else {
		# Address not known. Query CCU
		my $response = HMCCU_GetCCUObjectAttribute ($name, "Address()");
		if (defined ($response)) {
			if (HMCCU_IsChnAddr ($response, 0)) {
				($add, $chn) = split (":", $response);
				$HMCCU_Addresses{$name}{address} = $response;
				$HMCCU_Addresses{$name}{addtype} = 'chn';
			}
			elsif (HMCCU_IsDevAddr ($response, 0)) {
				$add = $response;
				$HMCCU_Addresses{$name}{address} = $response;
				$HMCCU_Addresses{$name}{addtype} = 'dev';
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
		return ($id =~ /^.+\.[A-Z]{3}[0-9]{7}:[0-9]{1,2}$/ || $id =~ /^.+\.[0-9A-F]{14}:[0-9]{1,2}$/) ? 1 : 0;
	}
	else {
		return ($id =~ /^[A-Z]{3}[0-9]{7}:[0-9]{1,2}$/ || $id =~ /^[0-9A-F]{14}:[0-9]{1,2}$/) ? 1 : 0;
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
		return ($id =~ /^.+\.[A-Z]{3}[0-9]{7}$/ || $id =~ /^.+\.[0-9A-F]{14}$/) ? 1 : 0;
	}
	else {
		return ($id =~ /^[A-Z]{3}[0-9]{7}$/ || $id =~ /^[0-9A-F]{14}$/) ? 1 : 0;
	}
}

####################################################
# Split channel address into device address and
# channel number
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

sub HMCCU_GetCCUObjectAttribute ($$)
{
	my ($object, $attr) = @_;

	my $hash = HMCCU_GetHash (0);
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
		}
		elsif ($hash->{TYPE} eq 'HMCCU') {
			return $hash;
		}
	}

	# Search for first HMCCU device
	foreach my $dn (sort keys %defs) {
		return $defs{$dn} if ($defs{$dn}->{TYPE} eq 'HMCCU');
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
# Get channels and datapoints from attributes
# statechannel, statedatapoint and controldatapoint.
# Return attribute values. Attribute controldatapoint
# is splittet into controlchannel and datapoint name.
####################################################

sub HMCCU_GetSpecialDatapoints ($$$$$)
{
	my ($hash, $defsd, $defsc, $defcd, $defcc) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};

	my $sd = AttrVal ($name, 'statedatapoint', $defsd);
	my $sc = AttrVal ($name, 'statechannel', $defsc);
	my $ccd = AttrVal ($name, 'controldatapoint', '');
	if ($type eq 'HMCCUCHN') {
		$ccd = $hash->{ccuaddr}.$ccd;
		$ccd =~ s/^[A-Z]{3,3}[0-9]{7,7}://;
	}
	my $cd = $defcd;
	my $cc = $defcc;

	if ($ccd =~ /^([0-9]+)\.(.+)$/) {
		($cc, $cd) = ($1, $2);
	}

	return ($sc, $sd, $cc, $cd);
}

####################################################
# Clear RPC queue(s)
####################################################

sub HMCCU_ResetRPCQueue ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
	my $rpcport = AttrVal ($name, 'rpcport', '2001');

	my @portlist = split (',', $rpcport);
	foreach my $port (@portlist) {
		my $clkey = 'CB'.$port;
		if (HMCCU_QueueOpen ($hash, $rpcqueue."_".$port)) {
			HMCCU_QueueReset ($hash);
			HMCCU_QueueClose ($hash);
		}
		delete $hash->{hmccu}{rpc}{$clkey}{queue};
		
#		my $queue = new RPCQueue (File => $rpcqueue."_".$port, Mode => 0666);
#		$queue->reset();
#		$queue->close();
	}
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
	my $ccureadingformat = AttrVal ($name, 'ccureadingformat', 'name');
	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
	my $rpcport = AttrVal ($name, 'rpcport', '2001');
	my $rpctimeout = AttrVal ($name, 'rpctimeout', 300);
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
			Log3 $name, 2, "HMCCU: Can't open file queue $queuename";
			next;
		}
		# my $queue = new RPCQueue (File => $rpcqueue."_".$port, Mode => 0666);

		my $element = HMCCU_QueueDeq ($hash);
		# my $element = $queue->deq();
		while ($element) {
#			Log3 $name, 2, "HMCCU: queueelement = $element";

			$hash->{hmccu}{eventtime} = time () if ($eventno == 0);
			my @Tokens = split (/\|/, $element);
			if ($Tokens[0] eq 'EV') {
				#### Event ####
				$eventno++;

				# Handle special events
				if ($Tokens[1] eq 'CENTRAL' && $Tokens[2] eq 'PONG') {
					Log3 $name, 2, "HMCCU: Received PONG event from ".$Tokens[3];
				}
				else {
					# Standard event
					my ($add, $chn) = split (/:/, $Tokens[1]);
					my $reading = HMCCU_GetReadingName ('', $add, $chn, $Tokens[2], '',
					   $ccureadingformat);
					HMCCU_UpdateClientReading ($hash, $add, $chn, $reading, $Tokens[3], 'rpcevent');
				}
				last if ($eventno == $maxevents);
			}
			elsif ($Tokens[0] eq 'ND') {
				#### New device added in CCU ####
				if (! exists ($HMCCU_Devices{$Tokens[1]})) {
					$newcount++;
				}
			}
			elsif ($Tokens[0] eq 'DD') {
				#### Device deleted in CCU ####
				push (@deldevices, $Tokens[1]);
				$delcount++;
			}
			elsif ($Tokens[0] eq 'IN') {
				#### RPC Server initialized ####
				Log3 $name, 0, "HMCCU: Received IN event. RPC server ".$Tokens[3]." initialized.";
				$hash->{hmccu}{rpc}{$Tokens[3]}{state} = "running";
				my $norun = 0;
		
				# Check if all RPC servers were initialized. Set overall status
				foreach my $ser (keys %{$hash->{hmccu}{rpc}}) {
					$norun++ if ($hash->{hmccu}{rpc}{$ser}{state} ne "running" &&
					   $hash->{hmccu}{rpc}{$ser}{pid} > 0);
				}
				if ($norun == 0) {
					$hash->{RPCState} = "running";
					readingsSingleUpdate ($hash, "rpcstate", "running", 1);
					HMCCU_SetState ($hash, "OK");
					my ($c_ok, $c_err) = HMCCU_UpdateClients ($hash, '.*', 'Attr', 0);
					DoTrigger ($name, "RPC server running");
				}				
			}
			elsif ($Tokens[0] eq 'EX') {
				#### RPC Server shut down ####
				push (@termpids, $Tokens[2]);
				Log3 $name, 0, "HMCCU: Received EX event. RPC server ".$Tokens[3]." terminated.";
				if ($hash->{RPCState} ne "restarting") {
					$hash->{hmccu}{rpc}{$Tokens[3]}{state} = "stopped";
					$hash->{hmccu}{rpc}{$Tokens[3]}{pid} = 0;
					$hash->{hmccu}{rpc}{$Tokens[3]}{cburl} = '';
					$hash->{hmccu}{rpc}{$Tokens[3]}{queue} = '';
			
					# Check if all RPC servers were terminated. Set overall status
					my $run = 0;
					foreach my $ser (keys %{$hash->{hmccu}{rpc}}) {
						$run++ if ($hash->{hmccu}{rpc}{$ser}{state} ne "stopped");
					}
					if ($run == 0) {
						$hash->{RPCState} = "stopped";
						readingsSingleUpdate ($hash, "rpcstate", "stopped", 1);
						$hash->{RPCPID} = '0';
					}
					$hash->{hmccu}{rpccount} = $run;
					$f = 1;
				}
				else {
					$f = 2;
				}
				last;
			}
			else {
				Log3 $name, 2, "HMCCU: Unknown RPC event type [".$Tokens[0]."]";
			}

			$element = HMCCU_QueueDeq ($hash);
			# $element = $queue->deq();
		}

		HMCCU_QueueClose ($hash);
		# $queue->close();
	}

	# Check if RPC server still running if events from CCU timed out
	if ($hash->{hmccu}{eventtime} > 0 && time()-$hash->{hmccu}{eventtime} > $rpctimeout) {
		Log3 $name, 2, "HMCCU: Received no events from CCU since $rpctimeout seconds";
		DoTrigger ($name, "No events from CCU since $rpctimeout seconds");
	}

	# CCU devices deleted
	$delcount = scalar @deldevices;
	if ($delcount > 0) {
		HMCCU_DeleteDevices (\@deldevices);
		$hash->{DelDevices} = $delcount;
		DoTrigger ($name, "$delcount devices deleted in CCU");
	}

	# CCU devices added
	if ($newcount > 0) {
		$hash->{NewDevices} = $newcount;
		DoTrigger ($name, "$newcount devices added in CCU");
	}

	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	my $nhm_pids = scalar (@hm_pids);
	my $nex_pids = scalar (@ex_pids);

	if ($nex_pids > 0 && $ccuflags !~ /extrpc/) {
		Log3 $name, 1, "HMCCU: Externally launched RPC server(s) detected. Kill process(es) manually with command kill -SIGINT pid for pids ".join (',', @ex_pids)." f=$f";
	}

	if ($f > 0) {
		# At least one RPC server has been stopped. Update PID list
		$hash->{RPCPID} = $nhm_pids > 0 ? join(',',@hm_pids) : '0';
		Log3 $name, 0, "HMCCU: RPC server(s) with PID(s) ".join(',',@termpids)." shut down. f=$f";
	}

	if ($f == 2 && $nhm_pids == 0) {
		# All RPC servers terminated and restart flag set
		$hash->{hmccu}{eventtime} = 0;
		return if (HMCCU_StartRPCServer ($hash));
		Log3 $name, 0, "HMCCU: Restart of RPC server failed";
	}

	if ($nhm_pids > 0) {
		# Reschedule reading of RPC queues if at least one RPC server is running
		InternalTimer (gettimeofday()+$rpcinterval, 'HMCCU_ReadRPCQueue', $hash, 0);
	}
	else {
		# No more RPC servers active
		$hash->{RPCPID} = '0';
		$hash->{RPCPRC} = 'none';
		$hash->{RPCState} = "stopped";
		readingsSingleUpdate ($hash, "rpcstate", "stopped", 1);
		if ($hash->{hmccu}{rpccount} > 0) {
			foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
				$hash->{hmccu}{rpc}{$clkey}{state} = "stopped";
				$hash->{hmccu}{rpc}{$clkey}{pid} = 0;
				$hash->{hmccu}{rpc}{$clkey}{queue} = '';
				$hash->{hmccu}{rpc}{$clkey}{cburl} = '';
			}
			$hash->{hmccu}{rpccount} = 0;
		}
		Log3 $name, 0, "HMCCU: All RPC servers stopped";
		DoTrigger ($name, "All RPC servers stopped");
	}
}

####################################################
# Execute Homematic script on CCU
####################################################

sub HMCCU_HMScript ($$)
{
	# Hostname, Script-Code
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
# Get datapoint and update reading.
####################################################

sub HMCCU_GetDatapoint ($@)
{
	my ($hash, $param, $reading) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $hmccu_hash;
	my $value = '';

	$hmccu_hash = HMCCU_GetHash ($hash);
	return (-3, $value) if (!defined ($hmccu_hash));
	return (-4, $value) if ($type ne 'HMCCU' && $hash->{ccudevstate} eq 'Deleted');

	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my $readingformat = AttrVal ($name, 'ccureadingformat', 'name');
	my $substitute = AttrVal ($name, 'substitute', '');
	my ($statechn, $statedpt, $controlchn, $controldpt) = HMCCU_GetSpecialDatapoints (
	   $hash, 'STATE', '', '', '');

	my $ccuget = HMCCU_GetAttribute ($hmccu_hash, $hash, 'ccuget', 'Value');
	my $ccutrace = AttrVal ($hmccu_hash->{NAME}, 'ccutrace', '');
	my $tf = ($ccutrace ne '' && $param =~ /$ccutrace/) ? 1 : 0;

	my $url = 'http://'.$hmccu_hash->{host}.':8181/do.exe?r1=dom.GetObject("';
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($param, $HMCCU_FLAG_INTERFACE);
	if ($flags == $HMCCU_FLAGS_IACD) {
		$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").'.$ccuget.'()';
	}
	elsif ($flags == $HMCCU_FLAGS_NCD) {
		$url .= $nam.'").DPByHssDP("'.$dpt.'").'.$ccuget.'()';
		($add, $chn) = HMCCU_GetAddress ($nam, '', '');
	}
	else {
		return (-1, $value);
	}

	if ($tf) {
		Log3 $name, 2, "HMCCU: GetDatapoint()";
		Log3 $name, 2, "HMCCU:   URL=$url";
		Log3 $name, 2, "HMCCU:   param=$param";
		Log3 $name, 2, "HMCCU:   ccuget=$ccuget";
	}

	my $rawresponse = GetFileFromURL ($url);
	my $response = $rawresponse;
	$response =~ m/<r1>(.*)<\/r1>/;
	$value = $1;

	Log3 ($name, 2, "HMCCU: Response = ".$rawresponse) if ($tf);

	if (defined ($value) && $value ne '' && $value ne 'null') {
		if (!defined ($reading) || $reading eq '') {
			$reading = HMCCU_GetReadingName ($int, $add, $chn, $dpt, $nam, $readingformat);
		}
		return (0, $value) if ($reading eq '');

		if ($type eq 'HMCCU') {
			$value = HMCCU_UpdateClientReading ($hmccu_hash, $add, $chn, $reading,
			   $value);
		}
		else {
			$value = HMCCU_Substitute ($value, $substitute, 0, $reading);
			$value = HMCCU_FormatReadingValue ($hash, $value);
			readingsSingleUpdate ($hash, $reading, $value, 1) if ($ccureadings);
			if ($controldpt ne '' && $dpt eq $controldpt && $chn eq $controlchn) {
				readingsSingleUpdate ($hash, 'control', $value, 1);
			}
			if (($reading =~ /\.$statedpt$/ || $reading eq $statedpt) && $ccureadings) {
				if ($statechn eq '' || $statechn eq $chn) {
					HMCCU_SetState ($hash, $value);
				}
			}
		}

		return (1, $value);
	}
	else {
		Log3 $name, 1, "HMCCU: Error URL = ".$url;
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
	return -4 if ($type ne 'HMCCU' && $hash->{ccudevstate} eq 'Deleted');
	my $name = $hmccu_hash->{NAME};
	
	my $ccutrace = AttrVal ($name, 'ccutrace', '');

	my $url = 'http://'.$hmccu_hash->{host}.':8181/do.exe?r1=dom.GetObject("';
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($param, $HMCCU_FLAG_INTERFACE);
	if ($flags == $HMCCU_FLAGS_IACD) {
		$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").State('.$value.')';
		$nam = HMCCU_GetChannelName ($add.":".$chn, '');
	}
	elsif ($flags == $HMCCU_FLAGS_NCD) {
		$url .= $nam.'").DPByHssDP("'.$dpt.'").State('.$value.')';
		($add, $chn) = HMCCU_GetAddress ($nam, '', '');
	}
	else {
		return -1;
	}
	my $addr = $add.":".$chn;
	
	my $response = GetFileFromURL ($url);
	if ($ccutrace ne '' && ($addr =~ /$ccutrace/ || $nam =~ /$ccutrace/)) {
		Log3 $name, 2, "HMCCU: Addr=$addr Name=$nam";
		Log3 $name, 2, "HMCCU: Script response = \n".$response;
		Log3 $name, 2, "HMCCU: Script = \n".$url;
	}
	return -2 if (!defined ($response) || $response =~ /<r1>null</);

	return 0;
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

	if (HMCCU_IsChnAddr ($addr, 0)) {
		$nam = HMCCU_GetChannelName ($addr, '');
		return -1 if ($nam eq '');

		$script = qq(
string sDPId;
string sChnName = "$nam";
object oChannel = dom.GetObject (sChnName);
if (oChannel) {
  foreach(sDPId, oChannel.DPs()) {
    object oDP = dom.GetObject(sDPId);
    if (oDP) {
      WriteLine (sChnName # "=" # oDP.Name() # "=" # oDP.$ccuget());
    }
  }
}
		);
	}
	elsif (HMCCU_IsDevAddr ($addr, 0)) {
		$nam = HMCCU_GetDeviceName ($addr, '');
		return -1 if ($nam eq '');

		$script = qq(
string chnid;
string sDPId;
object odev = dom.GetObject ("$nam");
if (odev) {
  foreach (chnid, odev.Channels()) {
    object ochn = dom.GetObject(chnid);
    if (ochn) {
      foreach(sDPId, ochn.DPs()) {
        object oDP = dom.GetObject(sDPId);
        if (oDP) {
          WriteLine (ochn.Name() # "=" # oDP.Name() # "=" # oDP.$ccuget());
        }
      }
    }
  }
}
		);
	}
	else {
		return -1;
	}

	my $response = HMCCU_HMScript ($hmccu_hash, $script);
	if ($ccutrace ne '' && ($addr =~ /$ccutrace/ || $nam =~ /$ccutrace/)) {
		Log3 $name, 2, "HMCCU: Addr=$addr Name=$nam";
		Log3 $name, 2, "HMCCU: Script response = \n".$response;
		Log3 $name, 2, "HMCCU: Script = \n".$script;
	}
	return -2 if ($response eq '');

	my @dpdef = split /\n/, $response;

	# Update client device
	my $rc = HMCCU_UpdateDeviceReadings ($cl_hash, \@dpdef);
	return $rc if ($rc < 0);

	# Update virtual devices
	my ($da, $cno) = HMCCU_SplitChnAddr ($cl_hash->{ccuaddr});
	foreach my $dn (sort keys %defs) {
		my $ch = $defs{$dn};
		next if ($ch->{TYPE} ne 'HMCCUDEV');
		next if ($ch->{ccuif} ne "VirtualDevices" || !exists ($ch->{ccugroup}));
		my @vdevs = split (",", $ch->{ccugroup});
		if ($da ~~ @vdevs || ($cno ne '' && $cl_hash->{ccuaddr} ~~ @vdevs)) {
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

	my $uc = 0;

	my $cn = $cl_hash->{NAME};
	my $disable = AttrVal ($cn, 'disable', 0);
	return 0 if ($disable == 1);
	my $ccureadings = AttrVal ($cn, 'ccureadings', 1);
	return -6 if ($ccureadings == 0);
#	my $ccureadingfilter = AttrVal ($cn, 'ccureadingfilter', '.*');
	my $readingformat = AttrVal ($cn, 'ccureadingformat', 'name');
	my $substitute = AttrVal ($cn, 'substitute', '');
	my ($statechn, $statedpt, $controlchn, $controldpt) = HMCCU_GetSpecialDatapoints (
	   $cl_hash, 'STATE', '', '', '');

	readingsBeginUpdate ($cl_hash);

	foreach my $dpdef (@$dp) {
		my @dpdata = split /=/, $dpdef;
		next if (@dpdata < 2);
		my @adrtoks = split /\./, $dpdata[1];
		next if (@adrtoks != 3);
#		next if ($adrtoks[2] !~ /$ccureadingfilter/);
                 
		my ($add, $chn) = split /:/, $adrtoks[1];
		next if (!HMCCU_FilterReading ($cl_hash, $adrtoks[1], $adrtoks[2]));
		my $reading = HMCCU_GetReadingName ($adrtoks[0], $add, $chn, $adrtoks[2],
		   $dpdata[0], $readingformat);
		next if ($reading eq '');
                 
		my $value = (defined ($dpdata[2]) && $dpdata[2] ne '') ? $dpdata[2] : 'N/A';
		$value = HMCCU_Substitute ($value, $substitute, 0, $reading);
		$value = HMCCU_FormatReadingValue ($cl_hash, $value);
		readingsBulkUpdate ($cl_hash, $reading, $value); 
		if ($controldpt ne '' && $adrtoks[2] eq $controldpt && $chn eq $controlchn) {
			readingsBulkUpdate ($cl_hash, 'control', $value);
		}
		if ($reading =~ /\.$statedpt$/ && ($statechn eq '' || $statechn eq $chn)) {
			readingsBulkUpdate ($cl_hash, "state", $value);
		}
		$uc++;
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

	my $ccuget = HMCCU_GetAttribute ($hmccu_hash, $hash, 'ccuget', 'Value');
	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my $readingformat = AttrVal ($name, 'ccureadingformat', 'name');
	my $defsubstitute = AttrVal ($name, 'substitute', '');
	my ($statechn, $statedpt, $controlchn, $controldpt) = HMCCU_GetSpecialDatapoints (
	   $hash, 'STATE', '', '', '');

	# Build channel list
	foreach my $chndef (@$chnref) {
		my ($channel, $substitute) = split /\s+/, $chndef;
		next if (!defined ($channel) || $channel =~ /^#/ || $channel eq '');
		$substitute = $defsubstitute if (!defined ($substitute));
		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($channel,
		   $HMCCU_FLAG_INTERFACE | $HMCCU_FLAG_DATAPOINT);
		if ($flags == $HMCCU_FLAGS_IACD || $flags == $HMCCU_FLAGS_NCD) {
			if ($flags == $HMCCU_FLAGS_IACD) {
				$nam = HMCCU_GetChannelName ($add.':'.$chn, '');
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
		my $reading = HMCCU_GetReadingName ($adrtoks[0], $add, $chn, $adrtoks[2],
		   $dpdata[0], $readingformat);
		next if ($reading eq '');
                 
		my $value = HMCCU_Substitute ($dpdata[2], $chnpars{$dpdata[0]}{sub}, 0, $reading);
		if ($hash->{TYPE} eq 'HMCCU') {
			HMCCU_UpdateClientReading ($hmccu_hash, $add, $chn, $reading, $value);
		}
		else {
			$value = HMCCU_FormatReadingValue ($hash, $value);
			if ($ccureadings) {
				readingsBulkUpdate ($hash, $reading, $value); 
				if ($controldpt ne '' && $adrtoks[2] eq $controldpt && $chn eq $controlchn) {
					readingsBulkUpdate ($hash, 'control', $value);
				}
				if ($reading =~ /\.$statedpt$/ && ($statechn eq '' || $statechn eq $chn)) {
					readingsBulkUpdate ($hash, "state", $value);
				}
			}
		}

		$result .= $reading.'='.$value."\n";
		$count++;
	}

	readingsEndUpdate ($hash, 1) if ($type ne 'HMCCU' && $ccureadings);

	return ($count, $result);
}

####################################################
# Get RPC paramSet or paramSetDescription
####################################################

sub HMCCU_RPCGetConfig ($$$)
{
	my ($hash, $param, $mode) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	
	my $addr;
	my $result = '';

	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my $readingformat = AttrVal ($name, 'ccureadingformat', 'name');
	my $substitute = AttrVal ($name, 'substitute', '');

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return (-3, $result) if (!defined ($hmccu_hash));
	return (-4, $result) if ($type ne 'HMCCU' && $hash->{ccudevstate} eq 'Deleted');

	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($param, $HMCCU_FLAG_FULLADDR);
	return (-1, '') if (!($flags & $HMCCU_FLAG_ADDRESS));
	$addr = $add;
	$addr .= ':'.$chn if ($flags & $HMCCU_FLAG_CHANNEL);

	return (-9, '') if (exists ($HMCCU_RPC_PORT{$int}));
	my $port = $HMCCU_RPC_PORT{$int};

	my $client = RPC::XML::Client->new ("http://".$hmccu_hash->{host}.":".$port."/");
	my $res = $client->simple_request ($mode, $addr, "MASTER");
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

		return (0, $result);
	}

	readingsBeginUpdate ($hash) if ($ccureadings);

	foreach my $key (sort keys %$res) {
		my $value = $res->{$key};
		$result .= "$key=$value\n";

		if ($ccureadings) {
			my $reading = HMCCU_GetReadingName ($int, $add, $chn, $key, $nam,
			   $readingformat);
			if ($reading ne '') {
				$value = HMCCU_Substitute ($value, $substitute, 0, $reading);
				$value = HMCCU_FormatReadingValue ($hash, $value);
				$reading = "R-".$reading;
				readingsBulkUpdate ($hash, $reading, $value);
			}
		}
	}

	readingsEndUpdate ($hash, 1) if ($ccureadings);

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
	
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($param, $HMCCU_FLAG_FULLADDR);
	return -1 if (!($flags & $HMCCU_FLAG_ADDRESS));
	$addr = $add;
	$addr .= ':'.$chn if ($flags & $HMCCU_FLAG_CHANNEL);

	return -9 if (!exists ($HMCCU_RPC_PORT{$int}));
	my $port = $HMCCU_RPC_PORT{$int};

	# Build param set
	foreach my $pardef (@$parref) {
		my ($par,$val) = split ("=", $pardef);
		next if (!defined ($par) || !defined ($val));
		$paramset{$par} = $val;
	}
	
	my $client = RPC::XML::Client->new ("http://".$hmccu_hash->{host}.":".$port."/");
	my $res = $client->simple_request ("putParamset", $addr, "MASTER", \%paramset);
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
	$element =~ s/$hash->{hmccu}{queue}{separator}//g;
	$hash->{hmccu}{queue}{queue}->syswrite($element.$hash->{hmccu}{queue}{seperator}) or return 0;
  
	return 1;  
}

sub HMCCU_QueueDeq ($)
{
	my ($hash) = @_;
	my $element;

	return undef if (!exists ($hash->{hmccu}{queue}));

	$hash->{hmccu}{queue}{queue}->sysseek($hash->{hmccu}{queue}{ptr}, SEEK_SET);

	my $i;
	while($hash->{hmccu}{queue}{queue}->sysread($_, $hash->{hmccu}{queue}{block_size})) {
		$i = index($_, $hash->{hmccu}{queue}{seperator});
		if($i != -1) {
			$element .= substr($_, 0, $i);
			$hash->{hmccu}{queue}{ptr} += $i + $hash->{hmccu}{queue}{sep_length};
			$hash->{hmccu}{queue}{queue}->sysseek($hash->{hmccu}{queue}{ptr}, SEEK_SET);
			last;
		}
		else {
			## If seperator isn't found, go back 'sep_length' spaces to ensure we don't miss it between reads
			$element .= substr($_, 0, -$hash->{hmccu}{queue}{sep_length}, '');
			$hash->{hmccu}{queue}{ptr} += $hash->{hmccu}{queue}{block_size} - 				$hash->{hmccu}{queue}{sep_length};
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

	return $element;
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
# *** External process part ***
####################################################

# Initialize hash
# my %rpchash;
# $rpchash{hmccu}{pid} = $$;
# $rpchash{hmccu}{name} = $0;
# my $pash = \%rpchash;

# foreach my $carg (@ARGV) {
#	print "Arg=$carg\n";
# }

# Process command line arguments
# if ($#ARGV+1 != 4) {
#	print "Usage: $0 CCU-Host Port QueueFile LogFile\n";
#	print "       $0 shutdown CCU-Host Port PID\n";
#	exit 1;
# }

1;


=pod
=begin html

<a name="HMCCU"></a>
<h3>HMCCU</h3>
<ul>
   The module provides an easy get/set interface for Homematic CCU. It acts as an
   IO device for HMCCUDEV client devices. The module requires additional Perl modules
   XML::Simple and File::Queue.
   </br></br>
   <a name="HMCCUdefine"></a>
   <b>Define</b>
   <ul>
      <br/>
      <code>define &lt;name&gt; HMCCU &lt;HostOrIP&gt;</code>
      <br/><br/>
      Example:
      <br/>
      <code>define myccu HMCCU 192.168.1.10</code>
      <br/><br/>
      HostOrIP - Hostname or IP address of Homematic CCU.
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUset"></a>
   <b>Set</b><br/>
   <ul>
      <br/>
      <li>set &lt;name&gt; config {&lt;device&gt;|&lt;channel&gt;} &lt;parameter&gt;=&lt;value&gt; [...]<br/>
        Set configuration parameters of CCU device or channel.
      </li><br/>
      <li>set &lt;name&gt; devstate {[&lt;interface&gt;.]&lt;channel-address&gt;|&lt;channel-name&gt;} &lt;value&gt; [...]<br/>
         Set state of a CCU device. Specified CCU channel must have a datapoint STATE.
         <br/><br/>
         Example:<br/>
         <code>set d_ccu devstate ST-WZ-Bass false</code><br/>
         <code>set d_ccu devstate BidCos-RF.LEQ1462664:1 false</code>
      </li><br/>
      <li>set &lt;name&gt; datapoint {[&lt;interface&gt;.]&lt;channel-address&gt;.&lt;datapoint&gt;|&lt;channel-name&gt;.&lt;datapoint&gt;} &lt;value&gt; [...]
        <br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code> set d_ccu datapoint THERMOSTAT_CHN2.SET_TEMPERATURE 21</code><br/>
        <code> set d_ccu datapoint LEQ1234567:2.SET_TEMPERATURE 21</code>
      </li><br/>
      <li>set &lt;name&gt; var &lt;variable>&gt; &lt;Value&gt; [...]<br/>
        Set CCU variable value.
      </li><br/>
      <li>set &lt;name&gt; execute &lt;program&gt;<br/>
         Execute CCU program.
         <br/><br/>
         Example:<br/>
         <code>set d_ccu execute PR-TEST</code>
      </li><br/>
      <li>set &lt;name&gt; hmscript &lt;script-file&gt;<br/>
         Execute HM script on CCU. If output of script contains lines in format
         Object=Value readings will be set. Object can be the name of a CCU system
         variable or a valid datapoint specification.
      </li><br/>
      <li>set &lt;name&gt; restartrpc<br/>
         Restart RPC server(s).
      </li><br/>
      <li>set &lt;name&gt; rpcserver {on|off}<br/>
         Start or stop RPC server.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <br/>
      <li>get &lt;name&gt; config {&lt;device&gt;|&lt;channel&gt;}
         Get configuration parameters of CCU device or channel. If attribute ccureadings is 0 parameters will
         be displayed in browser window.
      </li><br/>
      <li>get &lt;name&gt; configdesc {&lt;device&gt;|&lt;channel&gt;}
         Get configuration parameter description  of CCU device or channel.
      </li><br/>
      <li>get &lt;name&gt; devstate {[&lt;interface&gt;.]&lt;channel-address&gt;|&lt;channel-name&gt;} [&lt;reading&gt;]<br/>
         Get state of a CCU device. Specified channel must have a datapoint STATE. If &lt;reading&gt;
         is specified the value will be stored using this name.
      </li><br/>
      <li>get &lt;name&gt; vars &lt;regexp&gt;<br/>
         Get CCU system variables matching &lt;regexp&gt; and store them as readings.
      </li><br/>
      <li>get &lt;name&gt; channel {[&lt;interface&gt;.]&lt;channel-address&gt;[.&lt;datapoint-expr&gt;]|&lt;channel-name&gt;[.&lt;datapoint-expr&gt;]}[=[regexp1:subst1[,...]]] [...]
         <br/>
         Get value of datapoint(s). If no datapoint is specified all datapoints of specified
         channel are read. &lt;datapoint&gt; can be specified as a regular expression.
      </li><br/>
      <li>get &lt;name&gt; deviceinfo &lt;device-name&gt; [{'State'|'Value'}]<br/>
         List device channels and datapoints.
      </li><br/>
      <li>get &lt;name&gt; devicelist [dump]<br/>
         Read list of devices and channels from CCU. This command is executed automatically after device
         definition. Must be executed after module HMCCU is reloaded. With option dump devices are displayed
         in browser window.
      </li><br/>
      <li>get &lt;name&gt; parfile [&lt;parfile&gt;]<br/>
         Get values of all channels / datapoints specified in &lt;parfile&gt;. &lt;parfile&gt; can also
         be defined as an attribute. The file must contain one channel / datapoint definition per line.
         Datapoints are optional (for syntax see command 'get channel'). After the channel definition
         a list of string substitution rules for datapoint values can be specified (like attribute
         'substitute').<br/>
         The syntax of Parfile entries is:
         <br/><br/>
         {[&lt;interface&gt;.]&lt;channel-address&gt;[.&lt;datapoint-expr&gt;]|&lt;channel-name&gt;[.&lt;datapoint-expr&gt;]} &lt;regexp&gt;:&lt;subsstr&gt;[,...]
         <br/><br/>
         Empty lines or lines starting with a # are ignored.
      </li><br/>
      <li>get &lt;name&gt; rpcstate<br/>
         Check if RPC server process is running.
      </li><br/>
      <li>get &lt;name&gt; update [&lt;devexp&gt; [&lt;'State'|'Value'&gt;]]<br/>
         Update all datapoints / readings of client devices with FHEM device name matching &lt;devexp&gt;
      </li><br/>
      <li>get &lt;name&gt; updateccu [&lt;devexp&gt; [&lt;'State'|'Value'&gt;]]<br/>
         Update all datapoints / readings of client devices with CCU device name matching &lt;devexp&gt;
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccuget &lt;State | Value&gt;<br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value' because
         each request is sent to the device. With method 'Value' only CCU is queried. Default is 'Value'.
      </li><br/>
      <li>ccureadingformat &lt;name | address&gt;<br/>
        Format of reading names (channel name or channel address)
      </li><br/>
      <li>ccureadings &lt;0 | 1&gt;<br/>
         If set to 1 values read from CCU will be stored as readings. Otherwise output
         is displayed in browser window.
      </li><br/>
      <li>ccutrace &lt;ccu-devname-exp|ccu-address-exp&gt;<br/>
         Turn on trace mode for devices matching specified expression. Will write extended
         information into FHEM log (level 1).
      </li><br/>
      <li>parfile &lt;filename&gt;<br/>
         Define parameter file for command 'get parfile'.
      </li><br/>
      <li>rpcinterval &lt;Seconds&gt;<br/>
         Specifiy how often RPC queue is read. Default is 5 seconds.
      </li><br/>
      <li>rpcport &lt;value[,...]&gt;<br/>
         Specify list of RPC ports on CCU. Default is 2001.
      </li><br/>
      <li>rpcqueue &lt;queue-file&gt;<br/>
         Specify name of RPC queue file. This parameter is only a prefix for the
         queue files with extension .idx and .dat. Default is /tmp/ccuqueue.
      </li><br/>
      <li>rpcserver &lt;on | off&gt;<br/>
         Specify if RPC server is automatically started on FHEM startup.
      </li><br/>
      <li>statedatapoint &lt;datapoint&gt;<br/>
         Set datapoint for devstate commands. Default is 'STATE'.
      </li><br/>
      <li>statevals &lt;text:substext[,...]&gt;<br/>
         Define substitutions for values in 'set devstate/datapoint' command.
      </li><br/>
      <li>substitude &lt;expression&gt;:&lt;substext&gt;[,...]<br/>
         Define substitions for reading values. Substitutions for parfile values must
         be specified in parfiles.
      </li><br/>
      <li>stripchar &lt;character&gt;<br/>
         Strip the specified character from variable or device name in set commands. This
         is useful if a variable should be set in CCU using the reading with trailing colon.
      </li><br/>
      <li>updatemode { client | both | hmccu }<br/>
         Set update mode for readings.<br/>
         'client' = update only readings of client devices<br/>
         'both' = update readings of client devices and IO device<br/>
         'hmccu' = update readings of IO device
      </li>
   </ul>
</ul>

=end html
=cut


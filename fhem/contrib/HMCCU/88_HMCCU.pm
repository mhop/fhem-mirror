################################################################
#
#  88_HMCCU.pm
#
#  $Id$
#
#  Version 1.9
#
#  (c) 2015 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCU <host_or_ip> [<read_interval>]
#
#  set <name> devstate <ccu_object> <value> [...]
#  set <name> datapoint <device>:<channel>.<datapoint> <value> [...]
#  set <name> var <value> [...]
#  set <name> execute <ccu_program>
#  set <name> clearmsg
#
#  get <name> devicelist
#  get <name> devstate <ccu_object> [<reading>]
#  get <name> vars <regexp>[,...]
#  get <name> channel <device>:<channel>[.<datapoint_exp>]
#  get <name> datapoint <channel>.<datapoint> [<reading>]
#  get <name> parfile [<parfile>]
#
#  attr <name> ccureadingformat { name | address }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> parfile <parfile>
#  attr <name> rpcinterval { 3 | 5 | 10 }
#  attr <name> rpcport <ccu_rpc_port>
#  attr <name> rpcserver { on | off }
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> stripchar <character>
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#
#  Notes:
#
#  - Attribute 'unit' is no longer supported.
################################################################

package main;

use strict;
use warnings;
use SetExtensions;
use XML::Simple qw(:strict);
use File::Queue;
# use Data::Dumper;

# CCU Device names, key = CCU device address
my %HMCCU_Devices;
# CCU Device addresses, key = CCU device name
my %HMCCU_Addresses;

# Flags for CCU object specification
my $HMCCU_FLAG_NAME      = 1;
my $HMCCU_FLAG_CHANNEL   = 2;
my $HMCCU_FLAG_DATAPOINT = 4;
my $HMCCU_FLAG_ADDRESS   = 8;
my $HMCCU_FLAG_INTERFACE = 16;

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
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_Attr ($@);
sub HMCCU_ParseObject ($$);
sub HMCCU_GetReadingName ($$$$$$);
sub HMCCU_SetError ($$);
sub HMCCU_SetState ($$);
sub HMCCU_Substitute ($$);
sub HMCCU_UpdateClientReading ($$$$);
sub HMCCU_StartRPCServer ($);
sub HMCCU_StopRPCServer ($);
sub HMCCU_IsRPCServerRunning ($);
sub HMCCU_GetDeviceList ($);
sub HMCCU_GetAddress ($$$);
sub HMCCU_GetDeviceName ($$);
sub HMCCU_GetChannelName ($$);
sub HMCCU_GetDeviceType ($$);
sub HMCCU_GetDeviceInterface ($$);
sub HMCCU_ReadRPCQueue ($);


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

	$hash->{AttrList} = "stripchar ccureadings:0,1 ccureadingformat:name,address rpcinterval:3,5,10 rpcport rpcserver:on,off parfile statevals substitute units:0,1 loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
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
	$hash->{Clients} = ':HMCCUDEV:';

	$hash->{DevCount} = HMCCU_GetDeviceList ($hash);

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCU_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if (defined ($attrval) && $cmd eq "set") {
		if ($attrname eq "rpcserver") {
			if ($attrval eq 'on') {
				HMCCU_StartRPCServer ($hash);
				InternalTimer (gettimeofday()+60,
				   'HMCCU_ReadRPCQueue', $hash, 0);
			}
			elsif ($attrval eq 'off') {
				HMCCU_StopRPCServer ($defs{$name});
				RemoveInternalTimer ($hash);
			}
		}
	}

	return undef;
}

#####################################
# Delete device
#####################################

sub HMCCU_Undef ($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	# Shutdown RPC server
	HMCCU_StopRPCServer ($hash);

	RemoveInternalTimer ($hash);

	# Delete reference to IO module in client devices
	foreach my $d (sort keys %defs) {
		if (defined ($defs{$d}) && defined($defs{$d}{IODev}) &&
		    $defs{$d}{IODev} == $hash) {
        		delete $defs{$d}{IODev};
		}
	}

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
	my $options = "devstate datapoint var execute clearmsg:noArg";
	my $host = $hash->{host};

	my $stripchar = AttrVal ($name, "stripchar", '');
	my $statevals = AttrVal ($name, "statevals", '');

	# process set <name> command par1 par2 ...
	# if more than one parameter is specified parameters
	# are concatenated by blanks
	if ($opt eq 'state' || $opt eq 'devstate' || $opt eq 'datapoint' || $opt eq 'var') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);
		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("';

		if (!defined ($objname) || !defined ($objvalue)) {
			return HMCCU_SetError ($hash, "Usage: set <device> $opt <ccuobject> <objvalue>");
		}

		$objname =~ s/$stripchar$// if ($stripchar ne '');
		$objvalue = HMCCU_Substitute ($objvalue, $statevals);

		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($objname, $HMCCU_FLAG_INTERFACE);
		if ($opt eq 'var') {
			if ($flags & $HMCCU_FLAG_NAME) {
				$url .= $objname.'").State("'.$objvalue.'")';
			}
			else {
				return HMCCU_SetError ($hash, "Invalid variable name");
			}
		}
		elsif ($opt eq 'devstate' || $opt eq 'state') {
			if ($flags == $HMCCU_FLAGS_NC) {
				$url .= $objname.'").State("'.$objvalue.'")';
			}
			elsif ($flags == $HMCCU_FLAGS_IAC) {
				$url .= $int.'.'.$add.':'.$chn.'.STATE").State("'.$objvalue.'")';
			}
			else {
				return HMCCU_SetError ($hash, "Object := channelname | [interface.]address:channel");
			}
		}
		else {
			# Datapoint
			if ($flags == $HMCCU_FLAGS_IACD) {
				$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").State("'.$objvalue.'")';
			}
			elsif ($flags == $HMCCU_FLAGS_NCD) {
				$url .= $nam.'").DPByHssDP("'.$dpt.'").State("'.$objvalue.'")';
			}
			else {
				return HMCCU_SetError ($hash, "Object := channelname.datapoint | interface.address:channel.datapoint");
			}
		}

		my $response = GetFileFromURL ($url);
		if ($response =~ /<r1>null</) {
			Log 1,"HMCCU: Error URL = ".$url;
			return HMCCU_SetError ($hash, "Error during CCU communication");
		}

		HMCCU_SetState ($hash, "OK");

		return undef;
	}
	elsif ($opt eq "execute") {
		my $program = shift @a;
		my $url = 'http://'.$host.'/config/xmlapi/programlist.cgi';
		my $runurl = 'http://'.$host.'/config/xmlapi/runprogram.cgi?program_id=';
		my $response;
		my $retcode;
		my $programid;

		if (!defined ($program)) {
			return HMCCU_SetError ($hash, "Usage: set <device> execute <program name>");
		}

		# Query program ID
		$response = GetFileFromURL ($url);
		if ($response !~ /^<\?xml.*<programList>.*<\/programList>$/) {
			return HMCCU_SetError ($hash, "XML-API request error (programlist.cgi)");
		}

		my $xmlin = XMLin ($response, ForceArray => 0, KeyAttr => ['name']);
		if (!defined ($xmlin->{program}->{$program}->{id})) {
			return HMCCU_SetError ($hash, "Program not found");
		}
		else {
			$programid = $xmlin->{program}->{$program}->{id};
		}

		GetFileFromURL ($runurl . $programid);

		HMCCU_SetState ($hash, "OK");

		return undef;
	}
	elsif ($opt eq 'clearmsg') {
		my $url = 'http://'.$host.'/config/xmlapi/systemNotificationClear.cgi';

		GetFileFromURL ($url);

		HMCCU_SetState ($hash, "OK");

		return undef;
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
	my $options = "devicelist:noArg devstate datapoint vars channel parfile";
	my $host = $hash->{host};

	my $ccureadingformat = AttrVal ($name, "ccureadingformat", 'name');
	my $ccureadings = AttrVal ($name, "ccureadings", 1);
	my $parfile = AttrVal ($name, "parfile", '');

	my $readname;
	my $readaddr;

	if ($opt eq 'state' || $opt eq 'devstate') {
		my $ccuobj = shift @a;
		my $reading = shift @a;
		my $response;
		my $retcode;
		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("';

		if (!defined ($ccuobj)) {
			return HMCCU_SetError ($hash,
			   "Usage: get <device> devstate { <channelname> | [<interface>.]<address>:<channel> } [<reading>]");
		}

		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($ccuobj, $HMCCU_FLAG_INTERFACE);
		if ($flags == $HMCCU_FLAGS_NC) {
			$url .= $ccuobj.'").State()';
			$add = HMCCU_GetAddress ($nam, '', 1);
		}
		elsif ($flags == $HMCCU_FLAGS_IAC) {
			$url .= $int.'.'.$add.':'.$chn.'.STATE").State()';
		}
		else {
			return HMCCU_SetError ($hash, "object := channelname | [interface.]address:channel");
		}

		# Build reading name
		if (!defined ($reading)) {
			$reading = HMCCU_GetReadingName ($int, $add, $chn, 'STATE', $nam,
			   $ccureadingformat);
		}

		# Send request to CCU
		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		$retcode = $1;

		if (defined ($retcode) && $retcode ne '' && $retcode ne 'null') {
			HMCCU_SetState ($hash, "OK");
			if ($reading ne '') {
				$retcode = HMCCU_UpdateClientReading ($hash, $add, $reading, $retcode);
			}
			return $ccureadings ? undef : $retcode;
		}
		else {
			Log 1,"HMCCU: Error URL = ".$url;
			return HMCCU_SetError ($hash, "Error during CCU request");
		}
	}
	elsif ($opt eq 'datapoint') {
		my $ccuobj = shift @a;
		my $reading = shift @a;
		my $response;
		my $retcode;
		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("';

		if (!defined ($ccuobj)) {
			return HMCCU_SetError ($hash,
			   "Usage: get <device> datapoint { <channelname>.<datapoint> | [<interface>.]<address>:<channel>.<datapoint> } [<reading>]");
		}

		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($ccuobj, $HMCCU_FLAG_INTERFACE);
		if ($flags == $HMCCU_FLAGS_IACD) {
			$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").State()';
		}
		elsif ($flags == $HMCCU_FLAGS_NCD) {
			$url .= $nam.'").DPByHssDP("'.$dpt.'").State()';
			$add = HMCCU_GetAddress ($nam, '', 1);
		}
		else {
			return HMCCU_SetError ($hash, "object := channelname.datapoint | [interface.]address:channel.datapoint");
		}

		if (!defined ($reading)) {
			$reading = HMCCU_GetReadingName ($int, $add, $chn, $dpt, $nam, $ccureadingformat);
		}

		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		$retcode = $1;

		if (defined ($retcode) && $retcode ne '' && $retcode ne 'null') {
			HMCCU_SetState ($hash, "OK");
			if ($reading ne '') {
				$retcode = HMCCU_UpdateClientReading ($hash, $add, $reading, $retcode);
			}
			return $ccureadings ? undef : $retcode;
		}
		else {
			Log 1,"HMCCU: Error URL = ".$url;
			return HMCCU_SetError ($hash, "Error during CCU request");
		}
	}
	elsif ($opt eq 'vars') {
		my $varname = shift @a;
		my $url = 'http://'.$host.'/config/xmlapi/sysvarlist.cgi';
		my $response;
		my $result = '';

		if (!defined ($varname)) {
			return HMCCU_SetError ($hash, "Usage: get <device> vars <regexp>[,...]");
		}

		my @varlist = split /,/, $varname;

		$response = GetFileFromURL ($url);
		if ($response !~ /^<\?xml.*<systemVariables>.*<\/systemVariables>$/) {
			return HMCCU_SetError ($hash, "XML-API request error (sysvarlist.cgi)");
		}

		my $xmlin = XMLin ($response, ForceArray => 0, KeyAttr => ['systemVariable']);

		if ($ccureadings) {
			readingsBeginUpdate ($hash);
		}

		foreach my $variable (@{$xmlin->{systemVariable}}) {
			foreach my $varexp (@varlist) {
				if ($variable->{name} =~ /$varexp/) {
					$result .= $variable->{name}."=".$variable->{value}."\n";
					if ($ccureadings) {
						readingsBulkUpdate ($hash, $variable->{name}, $variable->{value}); 
					}
				}
			}
		}

		if ($ccureadings) {
			readingsEndUpdate ($hash, 1);
			HMCCU_SetState ($hash, "OK");
			return undef;
		}
		else {
			HMCCU_SetState ($hash, "OK");
			return $result;
		}
	}
	elsif ($opt eq 'channel') {
		my $param = shift @a;
		my $url = 'http://'.$host.'/config/xmlapi/statelist.cgi';
		my $response;
		my $result = '';
		my $rname;
		my $devname = '';
		my $chnname = '';

		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($param,
		   $HMCCU_FLAG_INTERFACE | $HMCCU_FLAG_DATAPOINT);

		if ($flags == $HMCCU_FLAGS_NCD || $flags == $HMCCU_FLAGS_IACD) {
			$response = GetFileFromURL ($url);
			if ($response !~ /^<\?xml.*<stateList>.*<\/stateList>$/) {
				return HMCCU_SetError ($hash, "XML-API request error (statelist.cgi)");
			}

			if ($flags == $HMCCU_FLAGS_IACD) {
				$devname = HMCCU_GetDeviceName ($add, '');
				$chnname = HMCCU_GetChannelName ($add.':'.$chn, '');
				if ($devname eq '' || $chnname eq '') {
					return HMCCU_SetError ($hash, "Device name or channel name not found for address $add");
				}
			}
			else {
				$chnname = $nam;
				$add = HMCCU_GetAddress ($nam, '', 1);
				$devname = HMCCU_GetDeviceName ($add, '');
			}

			my $xmlin = XMLin ($response,
			   ForceArray => ['device', 'channel', 'datapoint'],
			   KeyAttr => { device => 'name', channel => 'name' }
			);
			if (!defined (@{$xmlin->{device}->{$devname}->{channel}->{$chnname}->{datapoint}})) {
				return HMCCU_SetError ($hash, "Device $devname or channel $chnname not defined in CCU");
			}

			my @dps = @{$xmlin->{device}->{$devname}->{channel}->{$chnname}->{datapoint}};

			foreach my $dp (@dps) {
				if ($dp->{name} =~ /$dpt/) {
					my $dpname = $dp->{name};
					my $v = $dp->{value};

					$dpname =~ /.*\.(.*)$/;
					$rname = HMCCU_GetReadingName ($int, $add, $chn, $1,
					   $chnname, $ccureadingformat);
					if ($rname ne '') {
						$v = HMCCU_UpdateClientReading ($hash, $add, $rname, $v);
					}
					$result .= $rname."=".$v."\n";
				}
			}
		}
		else {
			HMCCU_SetError ($hash, "object := channelname.datapoint_expression | [interface.]address:channel.datapoint_expression");
		}

		HMCCU_SetState ($hash, "OK");

		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'parfile') {
		my $par_parfile = shift @a;
		my $url = 'http://'.$host.'/config/xmlapi/statelist.cgi';
		my @parameters;
		my $parcount;
		my $response;
		my $result = '';
		my $rname;
		my $text;
		my $devname = '';
		my $chnname = '';

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

		$response = GetFileFromURL ($url);
		if ($response !~ /^<\?xml.*<stateList>.*<\/stateList>$/) {
			return HMCCU_SetError ($hash, "XML-API request error (statelist.cgi)");
		}

		my $xmlin = XMLin (
		   $response,
		   ForceArray => ['device', 'channel', 'datapoint'],
		   KeyAttr => { device => 'name', channel => 'name' }
		);

		my $lineno = 0;
		foreach my $param (@parameters) {
			my @partoks = split /\s+/, $param;
			$lineno++;

			# Ignore empty lines or comments
			next if (scalar @partoks == 0);
			next if ($partoks[0] =~ /^#/);

			my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($partoks[0],
			   $HMCCU_FLAG_INTERFACE | $HMCCU_FLAG_DATAPOINT);

			# Ignore wrong CCU object specifications
			if ($flags != $HMCCU_FLAGS_IACD && $flags != $HMCCU_FLAGS_NCD) {
				Log 1, "Invalid CCU object name or address ".$partoks[0]." in line $lineno";
				next;
			}

			if ($flags == $HMCCU_FLAGS_IACD) {
				$devname = HMCCU_GetDeviceName ($add, '');
				$chnname = HMCCU_GetChannelName ($add.':'.$chn, '');
				if ($devname eq '' || $chnname eq '') {
					Log 1, "Device name or channel name not found for address $add in line $lineno";
					next;
				}
			}
			else {
				$chnname = $nam;
				$add = HMCCU_GetAddress ($nam, '', 1);
				$devname = HMCCU_GetDeviceName ($add, '');
			}

			# Ignore not existing devices/channels/datapoints
			if (!defined (@{$xmlin->{device}->{$devname}->{channel}->{$chnname}->{datapoint}})) {
				Log 1,"Device $devname or channel $chnname not defined in CCU in line $lineno";
				next;
			}

			my @dps = @{$xmlin->{device}->{$devname}->{channel}->{$chnname}->{datapoint}};

			foreach my $dp (@dps) {
				if ($dp->{name} =~ /$dpt/) {
					my $dpname = $dp->{name};
					my $v = $dp->{value};

					$v = HMCCU_Substitute ($v, $partoks[1]) if (@partoks > 1);
					$dpname =~ /.*\.(.*)$/;
					$rname = HMCCU_GetReadingName ($int, $add, $chn, $1,
					   $chnname, $ccureadingformat);
					if ($rname ne '') {
						$v = HMCCU_UpdateClientReading ($hash, $add, $rname, $v);
					}
					$result .= $rname."=".$v.' '.$dp->{valueunit}."\n";
				}
			}
		}

		HMCCU_SetState ($hash, "OK");

		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'devicelist') {
		$hash->{DevCount} = HMCCU_GetDeviceList ($hash);

		if ($hash->{DevCount} > 0) {
			HMCCU_SetState ($hash, "OK");
		}

		return undef;
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

	if ($object =~ /^(.+?)\.([A-Z]{3,3}[0-9]{7,7}):([0-9]{1,2})\.(.+)$/) {
		#
		# Interface.Address:Channel.Datapoint [30=11110]
		#
		$f = $HMCCU_FLAGS_IACD;
		($i, $a, $c, $d) = ($1, $2, $3, $4);
	}
	elsif ($object =~ /^(.+)\.([A-Z]{3,3}[0-9]{7,7}):([0-9]{1,2})$/) {
		#
		# Interface.Address:Channel [26=11010]
		#
		$f = $HMCCU_FLAGS_IAC | ($flags & $HMCCU_FLAG_DATAPOINT);
		($i, $a, $c, $d) = ($1, $2, $3, $flags & $HMCCU_FLAG_DATAPOINT ? '.*' : '');
	}
	elsif ($object =~ /^([A-Z]{3,3}[0-9]{7,7}):([0-9]){1,2}\.(.+)$/) {
		#
		# Address:Channel.Datapoint [14=01110]
		#
		$f = $HMCCU_FLAGS_ACD | ($flags & $HMCCU_FLAG_INTERFACE);
		($i, $a, $c, $d) = ($flags & $HMCCU_FLAG_INTERFACE ? 'BidCos-RF' : '', $1, $2, $3);;
	}
	elsif ($object =~ /^([A-Z]{3,3}[0-9]{7,7}):([0-9]){1,2}$/) {
		#
		# Address:Channel [10=01010]
		#
		$f = $HMCCU_FLAGS_AC | ($flags & $HMCCU_FLAG_DATAPOINT) | ($flags & $HMCCU_FLAG_INTERFACE);
		($i, $a, $c, $d) = ($flags & $HMCCU_FLAG_INTERFACE ? 'BidCos-RF' : '', $1, $2,
		   $flags & $HMCCU_FLAG_DATAPOINT ? '.*' : '');
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
		my $add = HMCCU_GetAddress ($n, '', 0);
		if ($add ne '' && $add =~ /:[0-9]$/) {
			$f = $f | $HMCCU_FLAG_CHANNEL;
		}
	}

	return ($i, $a, $c, $d, $n, $f);
}

sub HMCCU_GetReadingName ($$$$$$)
{
	my ($i, $a, $c, $d, $n, $rf) = @_;

	return '' if ($d eq '');

	if (($a eq '' || $c eq '') && $n ne '') {
		$a = HMCCU_GetAddress ($n, '', 0);
		if ($a =~ /:[0-9]+$/) {
			$c = $a;
			$a =~ s/:[0-9]+$//;
			$c =~ s/^.+://;
		}
		$i = HMCCU_GetDeviceInterface ($n, '');
	}
	elsif ($a ne '' && $n eq '') {
		if ($c ne '') {
			$n = HMCCU_GetChannelName ($a.":".$c, '');
		}
		else {
			$n = HMCCU_GetDeviceName ($a, '');
		}
	}

	$i = HMCCU_GetDeviceInterface ($a, '') if ($a ne '');

	if ($rf eq 'name') {
		return ($n ne '') ? $n.'.'.$d : '';
	}
	else {
		return ($i ne '' && $a ne '' && $c ne '') ? $i.'.'.$a.':'.$c.'.'.$d : '';
	}
}

sub HMCCU_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};

	$text = "HMCCU: ".$name." ". $text;
	HMCCU_SetState ($hash, "Error");
	Log 1, $text;
	return $text;
}

sub HMCCU_SetState ($$)
{
	my ($hash, $text) = @_;

	if (defined ($hash) && defined ($text)) {
		readingsSingleUpdate ($hash, "state", $text, 1);
	}
}

sub HMCCU_Substitute ($$)
{
	my ($value, $substitutes) = @_;

	return $value if (!defined ($substitutes) || $substitutes eq '');

	my @sub_list = split /,/,$substitutes;

	foreach my $s (@sub_list) {
		my ($regexp, $text) = split /:/,$s;
		next if (!defined ($regexp) || !defined($text));
		if ($value =~ /$regexp/) {
			$value =~ s/$regexp/$text/;
			last;
		}
	}

	return $value;
}

####################################################
# Update HMCCU readings and client readings.
# Reading values are substituted if attribute
# substitute is set in client device.
# Parameters: hash, clientdev, reading, value
####################################################

sub HMCCU_UpdateClientReading ($$$$)
{
	my ($hash, $clientadd, $reading, $value) = @_;
	my $name = $hash->{NAME};

	my $hmccu_substitute = AttrVal ($name, 'substitute', '');
	my $hmccu_updreadings = AttrVal ($name, 'ccureadings', 1);

	# Check syntax
	return 0 if (!defined ($hash) || !defined ($clientadd) ||
	   !defined ($reading) || !defined ($value));

	my $hmccu_value = '';

	# Update client readings
	foreach my $d (keys %defs) {
		# Get hash of device
		my $ch = $defs{$d};

		if (defined ($ch->{IODev}) && $ch->{IODev} == $hash &&
		    defined ($ch->{ccuaddr}) && $ch->{ccuaddr} eq $clientadd) {
			my $upd = AttrVal ($ch->{NAME}, 'ccureadings', 1);
			my $crf = AttrVal ($ch->{NAME}, 'ccureadingformat', 'name');
			my $substitute = AttrVal ($ch->{NAME}, 'substitute', '');

			last if ($upd == 0);

			my $clreading = $reading;
			if ($crf eq 'datapoint') {
				$clreading =~ s/.*\.(.+)$/$1/;
			}

			# Client substitute attribute has priority
			if ($substitute ne '') {
				$hmccu_value = HMCCU_Substitute ($value, $substitute);
				$value = HMCCU_Substitute ($value, $substitute);
			}
			else {
				$hmccu_value = HMCCU_Substitute ($value, $hmccu_substitute);
				$value = $hmccu_value;
			}

			readingsSingleUpdate ($ch, $clreading, $value, 1);
			if ($reading =~ /\.STATE$/) {
				HMCCU_SetState ($ch, $value);
			}

			# There should be no duplicate devices
			last;
		}
	}

	if ($hmccu_substitute ne '') {
		$hmccu_value = HMCCU_Substitute ($value, $hmccu_substitute);
	}
	if ($hmccu_updreadings) {
		readingsSingleUpdate ($hash, $reading, $hmccu_value, 1);
	}

	return $hmccu_value;
}

####################################################
# Start RPC server
####################################################

sub HMCCU_StartRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $modpath = AttrVal ('global', 'modpath', '/opt/fhem');
	my $logfile = $modpath."/log/ccurpcd.log";
	my $queue = "/tmp/ccuqueue";
	my $rpcport = AttrVal ($name, 'rpcport', '2001');

	if (HMCCU_IsRPCServerRunning ($hash)) {
		Log 1, "HMCCU: RPC Server already running";
		return 0;
	}

	# Check if RPC server exists
	my $rpcserver = $modpath."/FHEM/ccurpcd.pl";
	if (! -e $rpcserver) {
		Log 1, "HMCCU: RPC server not found";
		return 0;
	}

	# Fork child process
	my $pid = fork ();
	if (!defined ($pid)) {
		Log 1, "HMCCU: Can't fork child process";
		return 0;
	}

	if (!$pid) {
		# Child process, replace it by RPC server
		exec ($rpcserver." ".$hash->{host}." ".$rpcport." ".$queue." ".$logfile);

		# When we reach this line start of RPC server failed
		die;
	}

	Log 1, "HMCCU: RPC server started with pid ".$pid;
	$hash->{RPCPID} = $pid;

	return $pid;
}

####################################################
# Start RPC server
####################################################

sub HMCCU_StopRPCServer ($)
{
	my ($hash) = @_;

	if (HMCCU_IsRPCServerRunning ($hash)) {
		Log 1, "HMCCU: Stoppinng RPC server";
		kill ('INT', $hash->{RPCPID});
		$hash->{RPCPID} = 0;
		return 1;
	}
	else {
		Log 1, "HMCCU: RPC server not running";
		return 0;
	}
}

####################################################
# Check if RPC server is running
####################################################

sub HMCCU_IsRPCServerRunning ($)
{
	my ($hash) = @_;

	if (defined ($hash->{RPCPID}) && $hash->{RPCPID} > 0) {
		return kill (0, $hash->{RPCPID}) ? 1 : 0;
	}
	else {
		return 0;
	}
}

####################################################
# Read list of CCU devices via XML-API.
# Update addresses of client devices if not set.
####################################################

sub HMCCU_GetDeviceList ($)
{
	my ($hash) = @_;
	my $count = 0;
        
	my $url = "http://".$hash->{host}."/config/xmlapi/devicelist.cgi?show_internal=1";
	my $response = GetFileFromURL ($url);
	if ($response !~ /^<\?xml.*<deviceList>.*<\/deviceList>$/) {
		HMCCU_SetError ($hash, "XML-API request error (devicelist.cgi)");
		return 0;
	}

	my $devlist = XMLin ($response, ForceArray => ['channel'], KeyAttr => ['address']);
	%HMCCU_Devices = ();
	%HMCCU_Addresses = ();

	foreach my $da (keys %{$devlist->{'device'}}) {
		# Device address in format CCCNNNNNNN
		my $devname = $devlist->{'device'}->{$da}->{'name'};
		$HMCCU_Devices{$da}{name} = $devname;
		$HMCCU_Devices{$da}{type} = $devlist->{'device'}->{$da}->{'device_type'};
		$HMCCU_Devices{$da}{interface} = $devlist->{'device'}->{$da}->{'interface'};
		$HMCCU_Addresses{$devname} = $da;
		$count++;

		# Channels. Channel address in format CCCNNNNNNN:N
		foreach my $ca (keys %{$devlist->{'device'}->{$da}->{'channel'}}) {
			my $chnname = $devlist->{'device'}->{$da}->{'channel'}->{$ca}->{'name'};
			$HMCCU_Devices{$ca}{name} = $chnname;
			$HMCCU_Addresses{$chnname} = $ca;
			$count++;
		}
	}

	return $count;
}

####################################################
# Get name of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceName ($$)
{
	my ($addr, $default) = @_;

	if ($addr =~ /^[A-Z]{3,3}[0-9]{7,7}$/ || $addr =~ /^[A-Z]{3,3}[0-9]{7,7}:[0-9]+$/) {
		$addr =~ s/:[0-9]+$//;
		if (defined ($HMCCU_Devices{$addr})) {
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

	if ($addr =~ /^[A-Z]{3,3}[0-9]{7,7}:[0-9]+$/ && defined ($HMCCU_Devices{$addr})) {
		return $HMCCU_Devices{$addr}{name};
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

	if ($addr =~ /^[A-Z]{3,3}[0-9]{7,7}$/ || $addr =~ /^[A-Z]{3,3}[0-9]{7,7}:[0-9]+$/) {
		$addr =~ s/:[0-9]+$//;
		if (defined ($HMCCU_Devices{$addr})) {
			return $HMCCU_Devices{$addr}{type};
		}
	}

	return $default;
}

####################################################
# Get interface of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceInterface ($$)
{
	my ($addr, $default) = @_;

	if ($addr =~ /^[A-Z]{3,3}[0-9]{7,7}$/ || $addr =~ /^[A-Z]{3,3}[0-9]{7,7}:[0-9]+$/) {
		$addr =~ s/:[0-9]+$//;
		if (defined ($HMCCU_Devices{$addr})) {
			return $HMCCU_Devices{$addr}{interface};
		}
	}

	return $default;
}

####################################################
# Get address of a CCU device or channel by name.
# If parameter devaddress is set to 1, channel
# number will be removed from address.
####################################################

sub HMCCU_GetAddress ($$$)
{
	my ($name, $default, $devaddress) = @_;

	if (defined ($HMCCU_Addresses{$name})) {
		my $addr = $HMCCU_Addresses{$name};
		$addr =~ s/:[0-9]+$// if ($devaddress == 1);
		return $addr;
	}

	return $default;
}

####################################################
# Timer function for reading RPC queue
####################################################

sub HMCCU_ReadRPCQueue ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $maxevents = 10;
	my $eventno = 0;

	my $rpcinterval = AttrVal ($name, 'rpcinterval', 3);

	my $queue = new File::Queue (File => '/tmp/ccuqueue');

	my $element = $queue->deq();
	while ($element) {
		my @Tokens = split ('|', $element);
		if ($Tokens[0] eq 'EV') {
			$eventno++;
			last if ($eventno == $maxevents);
		}
		elsif ($Tokens[0] eq 'ND') {
			$HMCCU_Devices{$Tokens[1]}{name} = $Tokens[2];
		}
		elsif ($Tokens[0] eq 'EX') {
		}

		$element = $queue->deq();
	}

	if (HMCCU_IsRPCServerRunning ($hash)) {
		InternalTimer (gettimeofday()+$rpcinterval, 'HMCCU_ReadRPCQueue', $hash, 0);
	}
	else {
		$hash->{RPCPID} = 0;
	}
}


1;


=pod
=begin html

<a name="HMCCU"></a>
<h3>HMCCU</h3>
<div style="width:800px"> 
<ul>
   The module provides an easy get/set interface for Homematic CCU. It acts as an
   IO device for HMCCUDEV client devices. The module requires additional Perl modules
   XML::Simple and File::Queue.
   </br></br>
   <a name="HMCCUdefine"></a>
   <b>Define</b>
   <ul>
      <br/>
      <code>define &lt;name&gt; HMCCU &lt;<i>HostOrIP</i>&gt;</code>
      <br/><br/>
      Example:
      <br/>
      <code>define myccu HMCCU 192.168.1.10</code>
      <br/><br/>
      <i>HostOrIP</i> - Hostname or IP address of Homematic CCU.
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUset"></a>
   <b>Set</b><br/>
   <ul>
      <br/>
      <li>set &lt;name&gt; devstate {[&lt;interface&gt;.]&lt;channel-address&gt;|&lt;channel-name&gt;} &lt;value&gt; [...]
         <br/>
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
      <li>set &lt;name&gt; var &lt;variable>&gt; &lt;Value&gt; [...]
        <br/>
        Set CCU variable value.
      </li><br/>
      <li>set &lt;name&gt; clearmsg
        <br/>
        Clear CCU messages.
      </li><br/>
      <li>set &lt;name&gt; execute &lt;program&gt;
         <br/>
         Execute CCU program.
         <br/><br/>
         Example:<br/>
         <code>set d_ccu execute PR-TEST</code>
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <br/>
      <li>get &lt;name&gt; devstate {[&lt;interface&gt;.]&lt;channel-address&gt;|&lt;channel-name&gt;} [&lt;reading&gt;]
         <br/>
         Get state of a CCU device. Specified channel must have a datapoint STATE. If &lt;reading&gt;
         is specified the value will be stored using this name.
      </li><br/>
      <li>get &lt;name&gt; vars &lt;regexp&gt;[,...]
         <br/>
         Get CCU system variables matching &lt;regexp&gt; and store them as readings.
      </li><br/>
      <li>get &lt;name>&gt; channel {[&lt;interface&gt;.]&lt;channel-address&gt;[.&lt;datapoint-expr&gt;]|&lt;channel-name&gt;[.&lt;datapoint-expr&gt;]}
         <br/>
         Get value of datapoint(s). If no datapoint is specified all datapoints of specified
         channel are read. &lt;datapoint&gt; can be specified as a regular expression.
      </li><br/>
      <li>get &lt;name&gt; devicelist
         <br/>
         Read list of devices and channels from CCU. This command is executed automatically after device
         definition. Must be executed after module HMCCU is reloaded.
      </li><br/>
      <li>get &lt;name&gt; parfile [&lt;parfile&gt;]
         <br/>
         Get values of all channels / datapoints specified in &lt;parfile&gt;. &lt;parfile&gt; can also
         be defined as an attribute. The file must contain one channel / datapoint definition per line.
         Datapoints are optional (for syntax see command <i>get channel</i>). After the channel definition
         a list of string substitution rules for datapoint values can be specified (like attribute
         <i>substitute</i>).<br/>
         The syntax of Parfile entries is:
         <br/><br/>
         {[&lt;interface&gt;.]&lt;channel-address&gt;[.&lt;datapoint-expr&gt;]|&lt;channel-name&gt;[.&lt;datapoint-expr&gt;]} &lt;regexp&gt;:&lt;subsstr&gt;[,...]
         <br/><br/>
         Empty lines or lines starting with a # are ignored.
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccureadingformat &lt;name | address&gt;
         <br/>
           Format of reading names (channel name or channel address)
      </li><br/>
      <li>ccureadings &lt;0 | 1&gt;
         <br/>
            If set to 1 values read from CCU will be stored as readings. Otherwise output
            is displayed in browser window.
      </li><br/>
      <li>parfile &lt;filename&gt;
         <br/>
            Define parameter file for command <i>get parfile</i>.
      </li><br/>
      <li>statevals &lt;text:substext[,...]</i>&gt;
         <br/>
            Define substitutions for values in <i>set devstate/datapoint</i> command.
      </li><br/>
      <li>substitude &lt;expression&gt;:&lt;substext&gt;[,...]
         <br/>
            Define substitions for reading values. Substitutions for parfile values must
            be specified in parfiles.
      </li><br/>
      <li>stripchar &lt;character&gt;
         <br/>
            Strip the specified character from variable or device name in set commands. This
            is useful if a variable should be set in CCU using the reading with trailing colon.
      </li><br/>
   </ul>
</ul>
</div>

=end html
=cut


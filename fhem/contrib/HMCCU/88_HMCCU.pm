################################################################
#
#  88_HMCCU.pm
#
#  $Id$
#
#  Version 2.0
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
#  set <name> hmscript <hm_script_file>
#
#  get <name> devicelist
#  get <name> devstate <ccu_object> [<reading>]
#  get <name> vars <regexp>
#  get <name> channel <device>:<channel>[.<datapoint_exp>]
#  get <name> datapoint <channel>.<datapoint> [<reading>]
#  get <name> parfile [<parfile>]
#
#  attr <name> ccureadingformat { name | address }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> parfile <parfile>
#  attr <name> rpcinterval { 3 | 5 | 10 }
#  attr <name> rpcport <ccu_rpc_port>
#  attr <name> rpcqueue <file>
#  attr <name> rpcserver { on | off }
#  attr <name> statedatapoint <datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> stripchar <character>
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#  attr <name> updatemode { client | both | hmccu }
################################################################

package main;

use strict;
use warnings;
use SetExtensions;
# use XML::Simple qw(:strict);
use RPC::XML::Client;
use File::Queue;
# use Data::Dumper;

# CCU Device names, key = CCU device address
my %HMCCU_Devices;
# CCU Device addresses, key = CCU device name
my %HMCCU_Addresses;
# Last update of device list
my $HMCCU_UpdateTime = 0;

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
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_Attr ($@);
sub HMCCU_ParseObject ($$);
sub HMCCU_GetReadingName ($$$$$$);
sub HMCCU_SetError ($$);
sub HMCCU_SetState ($$);
sub HMCCU_Substitute ($$);
sub HMCCU_UpdateClientReading ($@);
sub HMCCU_StartRPCServer ($);
sub HMCCU_StopRPCServer ($);
sub HMCCU_IsRPCServerRunning ($);
sub HMCCU_GetDeviceList ($);
sub HMCCU_GetAddress ($$$);
sub HMCCU_GetCCUObjectAttribute ($$);
sub HMCCU_GetHash;
sub HMCCU_GetDeviceName ($$);
sub HMCCU_GetChannelName ($$);
sub HMCCU_GetDeviceType ($$);
sub HMCCU_GetDeviceInterface ($$);
sub HMCCU_ReadRPCQueue ($);
sub HMCCU_HTTPRequest ($@);
sub HMCCU_HMScript ($$);
sub HMCCU_GetDatapoint ($@);
sub HMCCU_SetDatapoint ($$$);
sub HMCCU_GetVariables ($$);
sub HMCCU_SetVariable ($$$);
sub HMCCU_GetChannel ($$);


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

	$hash->{AttrList} = "stripchar ccureadings:0,1 ccureadingformat:name,address rpcinterval:3,5,10 rpcqueue rpcport rpcserver:on,off parfile statedatapoint statevals substitute updatemode:client,both,hmccu loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
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
	my $options = "devstate datapoint var execute hmscript";
	my $host = $hash->{host};

	my $stripchar = AttrVal ($name, "stripchar", '');
	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my $statevals = AttrVal ($name, "statevals", '');
	my $ccureadings = AttrVal ($name, "ccureadings", 'name');
	my $readingformat = AttrVal ($name, "ccureadingformat", 'name');
	my $substitute = AttrVal ($name, "substitute", '');

	# process set <name> command par1 par2 ...
	# if more than one parameter is specified parameters
	# are concatenated by blanks
	if ($opt eq 'devstate' || $opt eq 'datapoint' || $opt eq 'var') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);
		my $result;

		if (!defined ($objname) || !defined ($objvalue)) {
			return HMCCU_SetError ($hash, "Usage: set <device> $opt <ccuobject> <value> [...]");
		}

		$objname =~ s/$stripchar$// if ($stripchar ne '');
		$objvalue = HMCCU_Substitute ($objvalue, $statevals);

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

		HMCCU_SetState ($hash, "OK");

		return undef;
	}
	elsif ($opt eq "execute") {
		my $program = shift @a;
		my $response;

		return HMCCU_SetError ($hash, "Usage: set <device> execute <program name>") if (!defined ($program));

		my $url = qq(http://$host:8181/do.exe?r1=dom.GetObject("$program").ProgramExecute());
		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		my $value = $1;
		if (defined ($value) && $value ne '' && $value ne 'null') {
			HMCCU_SetState ($hash, "OK");
		}
		else {
			HMCCU_SetError ($hash, "Program execution error");
		}

		return undef;
	}
	elsif ($opt eq 'hmscript') {
		my $scrfile = shift @a;
		my $script;
		my $response;

		return HMCCU_SetError ($hash, "Usage: set <device> hmscript <scriptfile>") if (!defined ($scrfile));
		if (open (SCRFILE, "<$scrfile")) {
			my @lines = <SCRFILE>;
			$script = join ("\n", @lines);
			close (SCRFILE);
		}
		else {
			return HMCCU_SetError ($hash, "Can't open file $scrfile");
		}

		$response = HMCCU_HMScript ($host, $script);
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
				my $Value = HMCCU_Substitute ($tokens[1], $substitute);
				readingsSingleUpdate ($hash, $tokens[0], $Value, 1);
			}
		}

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
	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my $substitute = AttrVal ($name, 'substitute', '');

	my $readname;
	my $readaddr;
	my $result = '';
	my $rc;

	if ($opt eq 'devstate') {
		my $ccuobj = shift @a;
		my $reading = shift @a;

		if (!defined ($ccuobj)) {
			return HMCCU_SetError ($hash,
			   "Usage: get <device> devstate { <channelname> | [<interface>.]<address>:<channel> } [<reading>]");
		}
		$reading = '' if (!defined ($reading));

		($rc, $result) = HMCCU_GetDatapoint ($hash, $ccuobj.'.'.$statedatapoint, $reading);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $ccuobj = shift @a;
		my $reading = shift @a;

		return HMCCU_SetError ($hash,
		   "Usage: get <device> datapoint {<channelname>|<channeladdress>}.<datapoint> [<reading>]") if (!defined ($ccuobj));
		$reading = '' if (!defined ($reading));

		($rc, $result) = HMCCU_GetDatapoint ($hash, $ccuobj, $reading);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'vars') {
		my $varname = shift @a;

		return HMCCU_SetError ($hash, "Usage: get <device> vars <regexp>[,...]") if (!defined ($varname));

		($rc, $result) = HMCCU_GetVariables ($hash, $varname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'channel') {
		my $param = shift @a;

		return HMCCU_SetError ($hash, "object := {channelname|channeladdress}.datapoint_expression") if (!defined ($param));

		my @chnlist = ($param);
		($rc, $result) = HMCCU_GetChannel ($hash, \@chnlist);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
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
	elsif ($opt eq 'devicelist') {
		my $dumplist = shift @a;

		$hash->{DevCount} = HMCCU_GetDeviceList ($hash);

		if ($hash->{DevCount} < 0) {
			return HMCCU_SetError ($hash, "HM Script execution failed");
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

	return ($i, $a, $c, $d, $n, $f);
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
#
##################################################################

sub HMCCU_GetReadingName ($$$$$$)
{
	my ($i, $a, $c, $d, $n, $rf) = @_;

	# Datapoint is mandatory
	return '' if ($d eq '');

	if ($rf eq 'datapoint') {
		return $d;
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

		return $n ne '' ? $n.'.'.$d : '';
	}
	elsif ($rf eq 'address') {
		if ($a eq '' && $n ne '') {
			($a, $c) = HMCCU_GetAddress ($n, '', '');
		}

		if ($a ne '') {
			my $t = $a;
			$i = HMCCU_GetDeviceInterface ($a, '') if ($i  eq '');
			$t = $i.'.'.$t if ($i ne '');
			$t = $t.':'.$c if ($c ne '');
			return $t.'.'.$d;
		}
	}

	return '';
}

sub HMCCU_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};
	my $msg;
	my %errlist = (
	   -1 => 'Channel name or address invalid',
	   -2 => 'Execution of CCU script or command failed',
	   -3 => 'Cannot detect IO device'
	);

	if (exists ($errlist{$text})) {
		$msg = $errlist{$text};
	}
	else {
		$msg = $text;
	}

	$msg = "HMCCU: ".$name." ". $msg;
	HMCCU_SetState ($hash, "Error");
	Log 1, $msg;
	return $msg;
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

##############################################################
# Update HMCCU readings and client readings.
#
# Parameters:
#   hash, devadd, channelno, reading, value, [mode]
#
# Parameter devadd can be a device or a channel address.
# Parameter clientonly is ignored!
# Reading values are substituted if attribute substitute is
# is set in client device.
##############################################################

sub HMCCU_UpdateClientReading ($@)
{
	my ($hash, $devadd, $channel, $reading, $value, $mode) = @_;
	my $name = $hash->{NAME};

	my $hmccu_substitute = AttrVal ($name, 'substitute', '');
	my $hmccu_updreadings = AttrVal ($name, 'ccureadings', 1);
	my $updatemode = AttrVal ($name, 'updatemode', 'hmccu');
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

	if ($hmccu_updreadings && ($updatemode eq 'hmccu' || $updatemode eq 'both')) {
		$hmccu_value = HMCCU_Substitute ($value, $hmccu_substitute);
		readingsSingleUpdate ($hash, $reading, $hmccu_value, 1);
		return $hmccu_value if ($updatemode eq 'hmccu');
	}

	# Update client readings
	foreach my $d (keys %defs) {
		# Get hash and name of client device
		my $ch = $defs{$d};
		my $cn = $ch->{NAME};

		next if (!defined ($ch->{IODev}) || !defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));
		next if ($ch->{ccuaddr} ne $devadd && $ch->{ccuaddr} ne $chnadd);

		# Get attributes of client device
		my $upd = AttrVal ($cn, 'ccureadings', 1);
		my $crf = AttrVal ($cn, 'ccureadingformat', 'name');
		my $substitute = AttrVal ($cn, 'substitute', '');
		last if ($upd == 0);

		my $clreading = $reading;
		if ($crf eq 'datapoint') {
			$clreading = $dpt ne '' ? $dpt : $reading;
		}
		elsif ($crf eq 'name') {
			$clreading = HMCCU_GetChannelName ($chnadd, $reading);
			$clreading .= '.'.$dpt if ($dpt ne '');
		}
		elsif ($crf eq 'address') {
			my $int = HMCCU_GetDeviceInterface ($devadd, 'BidCos-RF');
			$clreading = $int.'.'.$chnadd;
			$clreading .= '.'.$dpt if ($dpt ne '');
		}

		# Client substitute attribute has priority
		my $cl_value;
		if ($substitute ne '') {
			$cl_value = HMCCU_Substitute ($value, $substitute);
		}
		else {
			$cl_value = HMCCU_Substitute ($value, $hmccu_substitute);
		}

		readingsSingleUpdate ($ch, $clreading, $cl_value, 1);
		if ($clreading =~ /\.STATE$/) {
			HMCCU_SetState ($ch, $cl_value);
		}
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
	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
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
		exec ($rpcserver." ".$hash->{host}." ".$rpcport." ".$rpcqueue." ".$logfile);

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
		Log 1, "HMCCU: Stopping RPC server";
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
        
	my $script = qq(
string devid;
string chnid;
foreach(devid, root.Devices().EnumUsedIDs())
{
   object odev=dom.GetObject(devid);
   string intid=odev.Interface();
   string intna=dom.GetObject(intid).Name();
   integer cc=0;
   foreach (chnid, odev.Channels())
   {
      object ochn=dom.GetObject(chnid);
      WriteLine("C;" # ochn.Address() # ";" # ochn.Name());
      cc=cc+1;
   }
   WriteLine("D;" # intna # ";" # odev.Address() # ";" # odev.Name() # ";" # odev.HssType()) # ";" # cc;
}
	);

	my $response = HMCCU_HMScript ($hash->{host}, $script);
	return -1 if ($response eq '');

	%HMCCU_Devices = ();
	%HMCCU_Addresses = ();
	$HMCCU_UpdateTime = time ();

	foreach my $hmdef (split /\n/,$response) {
		my @hmdata = split /;/,$hmdef;
		if ($hmdata[0] eq 'D') {
			$HMCCU_Devices{$hmdata[2]}{name} = $hmdata[3];
			$HMCCU_Devices{$hmdata[2]}{type} = $hmdata[4];
			$HMCCU_Devices{$hmdata[2]}{interface} = $hmdata[1];
			$HMCCU_Devices{$hmdata[2]}{channels} = $hmdata[5];
			$HMCCU_Devices{$hmdata[2]}{addtype} = 'dev';
			$HMCCU_Addresses{$hmdata[3]}{address} = $hmdata[2];
			$HMCCU_Addresses{$hmdata[3]}{addtype} = 'dev';
			$count++;
		}
		elsif ($hmdata[0] eq 'C') {
			$HMCCU_Devices{$hmdata[1]}{name} = $hmdata[2];
			$HMCCU_Devices{$hmdata[1]}{addtype} = 'chn';
			$HMCCU_Addresses{$hmdata[2]}{address} = $hmdata[1];
			$HMCCU_Addresses{$hmdata[2]}{addtype} = 'chn';
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

	if ($addr =~ /^[A-Z]{3,3}[0-9]{7,7}:[0-9]+$/) {
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

	if ($addr =~ /^[A-Z]{3,3}[0-9]{7,7}$/ || $addr =~ /^[A-Z]{3,3}[0-9]{7,7}:[0-9]+$/) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($HMCCU_Devices{$addr})) {
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
		my $addr = $HMCCU_Addresses{$name}{address};
		if ($addr =~ /^([A-Z]{3,3}[0-9]{7,7}):([0-9]+)$/) {
			($add, $chn) = ($1, $2);
		}
		elsif ($addr =~ /^[A-Z]{3,3}[0-9]{7,7}$/) {
			$add = $addr;
		}
	}
	else {
		my $response = HMCCU_GetCCUObjectAttribute ($name, "Address()");
		if (defined ($response)) {
			if ($response =~ /^([A-Z]{3,3}[0-9]{7,7}):([0-9]+)$/) {
				($add, $chn) = ($1, $2);
				$HMCCU_Addresses{$name}{address} = $response;
				$HMCCU_Addresses{$name}{addtype} = 'chn';
			}
			elsif ($response =~ /^([A-Z]{3,3}[0-9]{7,7})$/) {
				$add = $1;
				$HMCCU_Addresses{$name}{address} = $response;
				$HMCCU_Addresses{$name}{addtype} = 'dev';
			}
		}
	}

	return ($add, $chn);
}

sub HMCCU_GetCCUObjectAttribute ($$)
{
	my ($object, $attr) = @_;

	my $hash = HMCCU_GetHash ();
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
# Get hash of HMCCU device
# Useful for client devices.
####################################################

sub HMCCU_GetHash
{
	foreach my $dn (sort keys %defs) {
		return $defs{$dn} if ($defs{$dn}->{TYPE} eq 'HMCCU');
	}

	return undef;
}

sub HMCCU_HTTPRequest ($@)
{
	my ($hash, $int, $add, $chn, $dpt, $val) = @_;

	my $host = $hash->{host};
	my $addr = $int.'.'.$add.':'.$chn.'.'.$dpt;
	my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("'.$addr.'")';

	if (defined ($val)) {
		$url .= '.State("'.$val.'")';
	}
	else {
		$url .= '.State()';
	}

	my $response = GetFileFromURL ($url);
	if (defined ($response) && $response =~ /<r1>(.+)<\/r1>/) {
		my $retval = $1;
		if ($retval ne 'null') {
			return defined ($val) ? 1 : $retval;
		}
	}

	return 0;
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
	my $f = 0;

	my $rpcinterval = AttrVal ($name, 'rpcinterval', 5);
	my $ccureadingformat = AttrVal ($name, 'ccureadingformat', 'name');
	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');

	my $queue = new File::Queue (File => $rpcqueue, Mode => 0666);

	my $element = $queue->deq();
	while ($element) {
		my @Tokens = split (/\|/, $element);
		if ($Tokens[0] eq 'EV') {
			my ($add, $chn) = split (/:/, $Tokens[1]);
			my $reading = HMCCU_GetReadingName ('', $add, $chn, $Tokens[2], '',
			   $ccureadingformat);
			HMCCU_UpdateClientReading ($hash, $add, $chn, $reading, $Tokens[3], 'client');
			$eventno++;
			last if ($eventno == $maxevents);
		}
		elsif ($Tokens[0] eq 'ND') {
		}
		elsif ($Tokens[0] eq 'EX') {
			Log 1, "HMCCU: Received EX event. RPC server terminated.";
			$f = 1;
			last;
		}
		else {
#			Log 1,"HMCCU: Unknown RPC event type ".$Tokens[0];
		}

		$element = $queue->deq();
	}

	if ($f == 0 && HMCCU_IsRPCServerRunning ($hash)) {
		InternalTimer (gettimeofday()+$rpcinterval, 'HMCCU_ReadRPCQueue', $hash, 0);
	}
	else {
		Log 1, "HMCCU: RPC server has been shut down. f=$f";
		$hash->{RPCPID} = 0;
		$attr{$name}{rpcserver} = "off";
	}
}

####################################################
# Execute Homematic script on CCU
####################################################

sub HMCCU_HMScript ($$)
{
	# Hostname, Script-Code
	my ($host, $hmscript) = @_;

	my $url = "http://".$host.":8181/tclrega.exe";
	my $ua = new LWP::UserAgent ();
	my $response = $ua->post($url, Content => $hmscript);

	if (! $response->is_success ()) {
		Log 1, "HMCCU: ".$response->status_line();
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
	my $hmccu_hash;
	my $value = '';

	my $ccureadings = AttrVal ($hash->{NAME}, 'ccureadings', 1);
	my $readingformat = AttrVal ($hash->{NAME}, 'ccureadingformat', 'name');
	my $substitute = AttrVal ($hash->{NAME}, 'substitute', '');

	if ($hash->{TYPE} ne 'HMCCU') {
		# Get hash of HMCCU IO device
		return (-3, $value) if (!exists ($hash->{IODev}));
		$hmccu_hash = $hash->{IODev};
	}
	else {
		# Hash of HMCCU IO device supplied as parameter
		$hmccu_hash = $hash;
	}

	my $url = 'http://'.$hmccu_hash->{host}.':8181/do.exe?r1=dom.GetObject("';
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($param, $HMCCU_FLAG_INTERFACE);
	if ($flags == $HMCCU_FLAGS_IACD) {
		$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").State()';
	}
	elsif ($flags == $HMCCU_FLAGS_NCD) {
		$url .= $nam.'").DPByHssDP("'.$dpt.'").State()';
		($add, $chn) = HMCCU_GetAddress ($nam, '', '');
	}
	else {
		return (-1, $value);
	}

	my $response = GetFileFromURL ($url);
	$response =~ m/<r1>(.*)<\/r1>/;
	$value = $1;

	if (defined ($value) && $value ne '' && $value ne 'null') {
		if (!defined ($reading) || $reading eq '') {
			$reading = HMCCU_GetReadingName ($int, $add, $chn, $dpt, $nam, $readingformat);
		}
		return (0, $value) if ($reading eq '');

		if ($hash->{TYPE} eq 'HMCCU') {
			$value = HMCCU_UpdateClientReading ($hmccu_hash, $add, $chn, $reading,
			   $value);
		}
		else {
			$value = HMCCU_Substitute ($value, $substitute);
			readingsSingleUpdate ($hash, $reading, $value, 1) if ($ccureadings);
			if (($reading =~ /\.STATE$/ || $reading eq 'STATE')&& $ccureadings) {
                        	HMCCU_SetState ($hash, $value);
                	}
		}

		return (1, $value);
	}
	else {
		Log 1,"HMCCU: Error URL = ".$url;
		return (-2, '');
	}
}

####################################################
# Set datapoint
####################################################

sub HMCCU_SetDatapoint ($$$)
{
	my ($hash, $param, $value) = @_;
	my $hmccu_hash;

	if ($hash->{TYPE} ne 'HMCCU') {
		# Get hash of HMCCU IO device
		return -3 if (!exists ($hash->{IODev}));
		$hmccu_hash = $hash->{IODev};
	}
	else {
		# Hash of HMCCU IO device supplied as parameter
		$hmccu_hash = $hash;
	}

	my $url = 'http://'.$hmccu_hash->{host}.':8181/do.exe?r1=dom.GetObject("';
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($param, $HMCCU_FLAG_INTERFACE);
	if ($flags == $HMCCU_FLAGS_IACD) {
		$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").State('.$value.')';
	}
	elsif ($flags == $HMCCU_FLAGS_NCD) {
		$url .= $nam.'").DPByHssDP("'.$dpt.'").State('.$value.')';
		($add, $chn) = HMCCU_GetAddress ($nam, '', '');
	}
	else {
		return -1;
	}

	my $response = GetFileFromURL ($url);
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

	my $response = HMCCU_HMScript ($hash->{host}, $script);
	return (-2, $result) if ($response eq '');
  
	readingsBeginUpdate ($hash) if ($ccureadings);

	foreach my $vardef (split /\n/, $response) {
		my @vardata = split /=/, $vardef;
		next if (@vardata != 3);
		next if ($vardata[0] !~ /$pattern/);
		readingsBulkUpdate ($hash, $vardata[0], $vardata[2]) if ($ccureadings); 
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
	my $url = 'http://'.$hash->{host}.':8181/do.exe?r1=dom.GetObject("'.$param.'").State("'.$value.'")';

	my $response = GetFileFromURL ($url);
	if (!defined ($response) || $response =~ /<r1>null</) {
		Log 1, "HMCCU: URL=$url";
		return -2;
	}

	return 0;
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
	my $count = 0;
	my $hmccu_hash;
	my %chnpars;
	my $chnlist = '';
	my $result = '';

	my $ccureadings = AttrVal ($hash->{NAME}, 'ccureadings', 1);
	my $readingformat = AttrVal ($hash->{NAME}, 'ccureadingformat', 'name');

	if ($hash->{TYPE} ne 'HMCCU') {
		# Get hash of HMCCU IO device
		return (-3, $result) if (!exists ($hash->{IODev}));
		$hmccu_hash = $hash->{IODev};
	}
	else {
		# Hash of HMCCU IO device supplied as parameter
		$hmccu_hash = $hash;
	}

	# Build channel list
	foreach my $chndef (@$chnref) {
		my ($channel, $substitute) = split /\s+/, $chndef;
		next if (!defined ($channel) || $channel =~ /^#/ || $channel eq '');
		$substitute = '' if (!defined ($substitute));
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
foreach (sChannel, sChnList.Split(","))
{
   object oChannel = dom.GetObject (sChannel);
   foreach(sDPId, oChannel.DPs().EnumUsedIDs())
   {
      object oDP = dom.GetObject(sDPId);
      WriteLine (sChannel # "=" # oDP.Name() # "=" # oDP.Value());
   }
}
	);

	my $response = HMCCU_HMScript ($hmccu_hash->{host}, $script);
	return (-2, $result) if ($response eq '');
  
	readingsBeginUpdate ($hash) if ($hash->{TYPE} ne 'HMCCU' && $ccureadings);

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
                 
		my $value = HMCCU_Substitute ($dpdata[2], $chnpars{$dpdata[0]}{sub});
		if ($hash->{TYPE} eq 'HMCCU') {
			HMCCU_UpdateClientReading ($hmccu_hash, $add, $chn, $reading, $value);
		}
		else {
			if ($ccureadings) {
				readingsBulkUpdate ($hash, $reading, $value); 
				HMCCU_SetState ($hash, $value) if ($reading =~ /\.STATE$/);
			}
		}

		$result .= $reading.'='.$value."\n";
		$count++;
	}

	readingsEndUpdate ($hash, 1) if ($hash->{TYPE} ne 'HMCCU' && $ccureadings);

	return ($count, $result);
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
      <li>set &lt;name&gt; execute &lt;program&gt; 
         <br/>
         Execute CCU program.
         <br/><br/>
         Example:<br/>
         <code>set d_ccu execute PR-TEST</code>
      </li><br/>
      <li>set &lt;name&gt; hmscript &lt;script-file&gt;
         <br/>
         Execute HM script on CCU. If output of script contains lines in format
         Object=Value readings will be set. Object can be the name of a CCU system
         variable or a valid datapoint specification.
      </li>
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
      <li>get &lt;name&gt; vars &lt;regexp&gt;
         <br/>
         Get CCU system variables matching &lt;regexp&gt; and store them as readings.
      </li><br/>
      <li>get &lt;name&gt; channel {[&lt;interface&gt;.]&lt;channel-address&gt;[.&lt;datapoint-expr&gt;]|&lt;channel-name&gt;[.&lt;datapoint-expr&gt;]}
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
      <li>rpcinterval &lt;3 | 5 | 10&gt;
         <br/>
            Specifiy how often RPC queue is read. Default is 5 seconds.
      </li><br/>
      <li>rpcport &lt;value&gt;
         <br/>
            Specify RPC port on CCU. Default is 2001.
      </li><br/>
      <li>rpcqueue &lt;queue-file&gt;
         <br/>
            Specify name of RPC queue file. This parameter is only a prefix for the
            queue files with extension .idx and .dat. Default is /tmp/ccuqueue.
      </li><br/>
      <li>rpcserver &lt;on | off&gt;
         <br/>
            Start or stop RPC server.
      </li><br/>
      <li>statedatapoint &lt;datapoint&gt;
         <br/>
            Set datapoint for devstate commands. Default is 'STATE'.
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
      <li>updatemode { client | both | hmccu }
         <br/>
            Set update mode for readings.<br/>
            'client' = update only readings of client devices<br/>
            'both' = update readings of client devices and IO device<br/>
            'hmccu' = update readings of IO device
      </li>
   </ul>
</ul>
</div>

=end html
=cut


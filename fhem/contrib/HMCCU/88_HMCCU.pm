################################################################
#
#  88_HMCCU.pm
#
#  $Id$
#
#  Version 1.8
#
#  (c) 2015 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCU <host_or_ip>
#
#  set <name> devstate <ccu_object> <value>
#  set <name> datapoint <device>:<channel>.<datapoint> <value>
#  set <name> var <value>
#  set <name> execute <ccu_program>
#  set <name> clearmsg
#
#  get <name> devstate <ccu_object> [<reading>]
#  get <name> vars <regexp>[,...]
#  get <name> channel <device>:<channel>[.<datapoint_exp>]
#  get <name> datapoint <channel>.<datapoint> [<reading>]
#  get <name> parfile [<parfile>]
#
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> stripchar <character>
#  attr <name> parfile <parfile>
#  attr <name> stateval <text1>:<subtext1>[,...]
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#
################################################################

package main;

use strict;
use warnings;
use SetExtensions;
use XML::Simple qw(:strict);
# use Data::Dumper;

sub HMCCU_Define ($$);
sub HMCCU_Undef ($$);
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_Attr ($@);
sub HMCCU_ParseCCUDev ($);
sub HMCCU_SetError ($$);
sub HMCCU_SetState ($$);
sub HMCCU_Substitute ($$);
sub HMCCU_UpdateClientReading ($$$);

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

	$hash->{AttrList} = "stripchar ccureadings:0,1 parfile stateval substitute units:0,1 loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
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

	my $host = $a[2];

	$hash->{host} = $host;
	$hash->{Clients} = ':HMCCUDEV:';

	HMCCU_SetState ($hash, "Initialized");

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCU_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;

	return undef;
}

#####################################
# Delete device
#####################################

sub HMCCU_Undef ($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

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
	my $options = "devstate datapoint var execute clearmsg";
	my $host = $hash->{host};

	my $stripchar = AttrVal ($name, "stripchar", '');
	my $stateval = AttrVal ($name, "stateval", '');

	# process set <name> command par1 par2 ...
	# if more than one parameter is specified parameters
	# are concatenated by blanks
	if ($opt eq 'state' || $opt eq 'devstate' || $opt eq 'datapoint' || $opt eq 'var') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);
		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("';

		if (!defined ($objname) || !defined ($objvalue)) {
			return HMCCU_SetError ($hash, "Usage: set <device> $opt <objname> <objvalue>");
		}

		$objname =~ s/$stripchar$// if ($stripchar ne '');
		$objvalue = HMCCU_Substitute ($objvalue, $stateval);

		my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($objname);
		if ($opt eq 'devstate' || $opt eq 'state' || $opt eq 'var') {
			if ($flags > 3) {
				return HMCCU_SetError ($hash, "Specify varname or device:channel");
			}
			$url = $url.$objname.'").State("'.$objvalue.'")';
		}
		else {
			if ($flags != 7) {
				return HMCCU_SetError ($hash, "Specify device:channel.datapoint");
			}
			$url = $url.$dev.':'.$chn.'").DPByHssDP("'.$dpt.'").State("'.$objvalue.'")';
		}

		my $response = GetFileFromURL ($url);
		if ($response =~ /<r1>null</) {
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
			return HMCCU_SetError ($hash, "Usage: set <device> execute <program>");
		}

		# Query program ID
		$response = GetFileFromURL ($url);
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
	my $options = "devstate datapoint vars channel parfile";
	my $host = $hash->{host};

	my $readings = AttrVal ($name, "ccureadings", 1);
	my $parfile = AttrVal ($name, "parfile", '');

	if ($opt eq 'state' || $opt eq 'devstate') {
		my $ccuobj = shift @a;
		my $reading = shift @a;
		my $response;
		my $retcode;

		if (!defined ($ccuobj)) {
			return HMCCU_SetError ($hash,
			   "Usage: get <device> devstate <device>:<channel> [<reading>]");
		}

		my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($ccuobj);
		if ($flags != 3) {
			return HMCCU_SetError ($hash, "Specify <device>:<channel>");
		}

		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("'.$ccuobj.'").State()';
		$reading = $ccuobj.".STATE" if (!defined ($reading));

		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		$retcode = $1;

		if (defined ($retcode) && $retcode ne '' && $retcode ne 'null') {
			HMCCU_SetState ($hash, "OK");
			$retcode = HMCCU_UpdateClientReading ($hash, $reading, $retcode);
			return $readings ? undef : $retcode;
		}
		else {
			return HMCCU_SetError ($hash, "Error during CCU request");
		}
	}
	elsif ($opt eq 'datapoint') {
		my $ccuobj = shift @a;
		my $reading = shift @a;
		my $response;
		my $retcode;

		if (!defined ($ccuobj)) {
			return HMCCU_SetError ($hash,
			   "Usage: get <device> datapoint <device>:<channel>.<datapoint> [<reading>]");
		}
		my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($ccuobj);
		if ($flags != 7) {
			return HMCCU_SetError ($hash, "Specify device:channel.datapoint");
		}

		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("'.$dev.':'.$chn.'").DPByHssDP("'.$dpt.'").Value()';
		$reading = $ccuobj if (!defined ($reading));

		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		$retcode = $1;

		if (defined ($retcode) && $retcode ne '' && $retcode ne 'null') {
			HMCCU_SetState ($hash, "OK");
			$retcode = HMCCU_UpdateClientReading ($hash, $ccuobj, $retcode);
			return $readings ? undef : $retcode;
		}
		else {
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
		my $xmlin = XMLin ($response, ForceArray => 0, KeyAttr => ['systemVariable']);

		if ($readings) {
			readingsBeginUpdate ($hash);
		}

		foreach my $variable (@{$xmlin->{systemVariable}}) {
			foreach my $varexp (@varlist) {
				if ($variable->{name} =~ /$varexp/) {
					$result .= $variable->{name}."=".$variable->{value}."\n";
					if ($readings) {
						readingsBulkUpdate ($hash, $variable->{name}, $variable->{value}); 
					}
				}
			}
		}

		if ($readings) {
			readingsEndUpdate ($hash, 1);
			return undef;
		}
		else {
			return $result;
		}
	}
	elsif ($opt eq 'channel') {
		my $param = shift @a;
		my $url = 'http://'.$host.'/config/xmlapi/statelist.cgi';
		my $response;
		my $result = '';
		my $rname;

		my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($param);
		if (($flags & 3 ) != 3) {
			return HMCCU_SetError ($hash,
			   "Usage: get <device> channel <ccudev>:<channel>[.<datapoint>]");
		}

		my $devch = $dev.':'.$chn;
		$response = GetFileFromURL ($url);
		my $xmlin = XMLin ($response,
		   ForceArray => ['device', 'channel', 'datapoint'],
		   KeyAttr => { device => 'name', channel => 'name' }
		);
		if (!defined (@{$xmlin->{device}->{$dev}->{channel}->{$devch}->{datapoint}})) {
			return HMCCU_SetError ($hash, "Device or channel not defined");
		}

		my @dps = @{$xmlin->{device}->{$dev}->{channel}->{$devch}->{datapoint}};

		foreach my $dp (@dps) {
			if ($dp->{name} =~ /$dpt/) {
				my $dpname = $dp->{name};
				my $v = $dp->{value};

				$dpname =~ /.*\.(.*)$/;
				$rname = $devch.".$1";

				$v = HMCCU_UpdateClientReading ($hash, $rname, $v);
				$result .= $rname."=".$v."\n";
			}
		}

		HMCCU_SetState ($hash, "OK");

		return $readings ? undef : $result;
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

		if (defined ($par_parfile)) {
			$parfile = $par_parfile;
		}
		else {
			if ($parfile eq '') {
				return HMCCU_SetError ($hash, "No parameter file specified");
			}
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

		if ($parcount < 1) {
			return HMCCU_SetError ($hash, "Empty parameter file");
		}

		$response = GetFileFromURL ($url);
		my $xmlin = XMLin (
		   $response,
		   ForceArray => ['device', 'channel', 'datapoint'],
		   KeyAttr => { device => 'name', channel => 'name' }
		);

		foreach my $param (@parameters) {
			my @partoks = split /\s+/, $param;

			# Ignore empty lines or comments
			next if (scalar @partoks == 0);
			next if ($partoks[0] =~ /^#/);

			# Ignore wrong CCU device specifications
			my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($partoks[0]);
			next if (($flags & 3) != 3);
			my $devch = $dev.':'.$chn;

			# Ignore not existing devices/channels/datapoints
			next if (!defined (@{$xmlin->{device}->{$dev}->{channel}->{$devch}->{datapoint}}));
			my @dps = @{$xmlin->{device}->{$dev}->{channel}->{$devch}->{datapoint}};

			foreach my $dp (@dps) {
				if ($dp->{name} =~ /$dpt/) {
					my $dpname = $dp->{name};
					my $v = $dp->{value};

					$v = HMCCU_Substitute ($v, $partoks[1]) if (@partoks > 1);
					$dpname =~ /.*\.(.*)$/;
					$rname = $devch.".$1";
					$v = HMCCU_UpdateClientReading ($hash, $rname, $v);
					$result .= $rname."=".$v.' '.$dp->{valueunit}."\n";
				}
			}
		}

		HMCCU_SetState ($hash, "OK");

		return $readings ? undef : $result;
	}
	else {
		return "HMCCU: Unknown argument $opt, choose one of ".$options;
	}
}

##################################################################
# Parse CCU object name.
#
# Input: object name in format device:channel.datapoint
#
# Output: array with ( device, channel, datapoint, flags )
#   flag bits: 0=Device 1=Channel 2=Datapoint
##################################################################

sub HMCCU_ParseCCUDev ($)
{
	my $param = $_[0];
	my $p1 = '?';
	my $p2 = '?';
	my $p3 = '.*';
	my $p4 = 0;

	# Syntax of CCU device specification is:
	# devicename:channelno[.datapoint]
	if ($param =~ /^.+:/) {
		$param =~ /^(.*):/;
		$p1 = $1;
		$p4 = 1;

		if ($param =~ /^.+:[0-9]+/) {
			$param =~ /^.*:([0-9]+)/;
			$p2 = $1;
			$p4 |= 2;

			if ($param =~ /\..*$/) {
				$param =~ /\.(.*)$/;
				$p3 = $1;
				$p4 |= 4;
			}
		}
	}

	return ($p1, $p2, $p3, $p4);
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
# Reading values are substituted with client priority
####################################################

sub HMCCU_UpdateClientReading ($$$)
{
	my ($hash, $reading, $value) = @_;
	my $name = $hash->{NAME};

	my $hmccu_substitute = AttrVal ($name, 'substitute', '');
	my $hmccu_updreadings = AttrVal ($name, 'ccureadings', 1);

	# Check syntax
	return 0 if (!defined ($hash) || !defined ($reading) || !defined ($value));

	# Get CCU device name from reading name
	my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($reading);
	return 0 if ($flags == 0);

	# Update HMCCU reading
	my $hmccu_value = HMCCU_Substitute ($value, $hmccu_substitute);
	if ($hmccu_updreadings) {
		readingsSingleUpdate ($hash, $reading, $hmccu_value, 1);
	}

	# Update client readings
	foreach my $d (keys %defs) {
		# Get hash of device
		my $ch = $defs{$d};

		if (defined ($ch->{IODev}) && $ch->{IODev} == $hash &&
		    defined ($ch->{ccudev}) && $ch->{ccudev} eq $dev) {
			my $upd = AttrVal ($ch->{NAME}, 'ccureadings', 1);
			my $substitute = AttrVal ($ch->{NAME}, 'substitute', '');

			# Client substitute attribute has priority
			if ($substitute ne '') {
				$value = HMCCU_Substitute ($value, $substitute);
			}
			else {
				$value = $hmccu_value;
			}

			if ($upd == 1) {
				readingsSingleUpdate ($ch, $reading, $value, 1);
				if ($dpt eq 'STATE') {
					HMCCU_SetState ($ch, $value);
				}
			}

			last;
		}
	}

	return $hmccu_value;
}

1;


=pod
=begin html

<a name="HMCCU"></a>
<h3>HMCCU</h3>
<div style="width:800px"> 
<ul>
   The module provides an easy get/set interface for Homematic CCU.
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
      <li>set &lt;<i>Name</i>&gt; devstate &lt;<i>Device</i>:<i>Channel</i>&gt; &lt;<i>Value</i>&gt;
         <br/>
         Set state of a CCU device or value of a CCU system variable.
         <br/><br/>
         Example:<br/>
         <code>set d_ccu devstate ST-WZ-Bass:1 0</code>
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; datapoint &lt;<i>device</i>:<i>channel</i>.<i>datapoint</i>&gt; &lt;<i>Value</i>&gt;
        <br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code> set d_ccu datapoint THERMOSTAT_WOHNEN:2.SET_TEMPERATURE 21</code>
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; var &lt;<i>variable</i>&gt; &lt;<i>Value</i>&gt;
        <br/>
        Set CCU variable value.
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; clearmsg
        <br/>
        Clear CCU messages.
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; execute &lt;<i>Program</i>&gt;
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
      <li>get &lt;<i>Name</i>&gt; devstate &lt;<i>Device</i>:<i>Channel</i>&gt; [&lt;<i>Reading</i>&gt;]
         <br/>
         Get state of a CCU device or value of a CCU system variable. If <i>Reading</i>
         is specified the value will be stored using this name.
      </li><br/>
      <li>get &lt;<i>Name</i>&gt; vars &lt;<i>RegExp</i>&gt;[,...]
         <br/>
         Get CCU system variables matching <i>RegExp</i> and store them as readings.
      </li><br/>
      <li>get &lt;<i>Name</i>&gt; channel &lt;<i>Device</i>:<i>Channel</i>[.<i>Datapoint</i>]&gt;
         <br/>
         Get value of channel datapoint. If no datapoint is specified all datapoints of specified
         channel is read. <i>Datapoint</i> can be specified as a regular expression.
      </li><br/>
      <li>get &lt;<i>Name</i>&gt; parfile [&lt;<i>ParFile</i>&gt;]
         <br/>
         Get values of all channels / datapoints specified in <i>ParFile</i>. <i>ParFile</i> can also
         be defined as an attribute. The file must contain one channel / datapoint definition per line.
         Datapoints are optional (for syntax see command get channel). After the channel definition
         a list of string substitution rules for datapoint values can be specified.<br/>
         The syntax of Parfile entries is:
         <br/><br/>
         <i>Device</i>:<i>Channel</i>[<i>Datapoint</i>] <i>RegExp</i>:<i>SubstString</i>[,...]
         <br/><br/>
         Empty lines or lines starting with a # are ignored.
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccureadings &lt;0 | 1&gt;
         <br/>
            If set to 1 values read from CCU will be stored as readings.
      </li><br/>
      <li>parfile &lt;<i>Filename</i>&gt;
         <br/>
            Define parameter file for command get parfile.
      </li><br/>
      <li>stateval &lt;<i>text</i>:<i>text</i>[,...]</i>&gt;
         <br/>
            Define substitions for values in set devstate/datapoint command.
      </li><br/>
      <li>substitude &lt;<i>expression</i>:<i>string</i>[,...]</i>&gt;
         <br/>
            Define substitions for reading values. Substitutions for parfile values must
            be specified in parfiles.
      </li><br/>
      <li>stripchar &lt;<i>Character</i>&gt;
         <br/>
            Strip the specified character from variable or device name in set commands. This
            is useful if a variable should be set in CCU using the reading with trailing colon.
      <li>units &lt;0 | 1&gt;
         <br/>
            If set to 1 value units will be appended to readings.
      </li><br/>
   </ul>
</ul>
</div>

=end html
=cut


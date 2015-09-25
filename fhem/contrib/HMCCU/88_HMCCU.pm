################################################################
#
#  88_HMCCU.pm
#
#  $Id$
#
#  Version 1.7
#
#  (c) 2015 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCU <host_or_ip>
#
#  set <name> devstate <ccu_object> <value>
#  set <name> datapoint <channel>.<datapoint> <value>
#  set <name> execute <ccu_program>
#  set <name> clearmsg
#
#  get <name> devstate <ccu_object> [<reading>]
#  get <name> vars <regexp>[,...]
#  get <name> channel <channel>[.<datapoint>]
#  get <name> datapoint <channel>.<datapoint> [<reading>]
#  get <name> parfile [<parfile>]
#
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> stripchar <character>
#  attr <name> parfile <parfile>
#  attr <name> substitute <regexp>:<text>[,...]
#  attr <name> units { 0 | 1 }
#
################################################################

package main;

use strict;
use warnings;
use SetExtensions;
use XML::Simple qw(:strict);
# use Data::Dumper;

sub HMCCU_Define ($$);
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_ParseCCUDev ($);
sub HMCCU_SetError ($$);
sub HMCCU_Substitute ($$);

#####################################

sub HMCCU_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCU_Define";
	$hash->{SetFn} = "HMCCU_Set";
	$hash->{GetFn} = "HMCCU_Get";

	$hash->{AttrList} = "model:HMCCU stripchar ccureadings:0,1 parfile substitute units:0,1 loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
}

#####################################

sub HMCCU_Define ($$)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return "Define the CCU hostname or IP address as a parameter i.e. MyCCU" if(@a < 3);

	my $host = $a[2];

	$attr{$name}{stripchar} = '';
	$attr{$name}{ccureadings} = 1;
	$attr{$name}{parfile} = '';
	$attr{$name}{substitute} = '';
	$attr{$name}{units} = 0;
  
	$hash->{host} = $host;
	readingsSingleUpdate ($hash, "state", "Initialized", 1);

	return undef;
}

#####################################

sub HMCCU_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;
	my $stripchar = AttrVal ($name, "stripchar", '');
	my $host = $hash->{host};

	# process set <name> command par1 par2 ...
	# if more than one parameter is specified parameters
	# are concatenated by blanks
	if ($opt eq "state" || $opt eq "devstate") {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);

		if (!defined ($objname) || !defined ($objvalue)) {
			return HMCCU_SetError ($hash, "Usage: set <device> devstate <objname> <objvalue>");
		}

		$objname =~ s/$stripchar$// if ($stripchar ne '');

		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("'.$objname.'").State("'.$objvalue.'")';

		my $response;
		my $retcode = '';

		$response = GetFileFromURL ($url);
		if ($response =~ /<r1>null</) {
			return HMCCU_SetError ($hash, "Error during CCU communication");
		}

		readingsSingleUpdate ($hash, "state", "OK", 1);

		return $retcode;
	}
	elsif ($opt eq "datapoint") {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);

		if (!defined ($objname) || !defined ($objvalue)) {
			return HMCCU_SetError ($hash, "Usage: set <device> datapoint <objname> <objvalue>");
		}

		my ($device, $channel, $datapoint) = HMCCU_ParseCCUDev ($objname);
		if ($device eq '?' || $channel eq '?' || $datapoint eq '.*') {
			return HMCCU_SetError ($hash, "Format for objname is device:channel.datapoint");
		}

		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("'.$channel.'").DPByHssDP("'.$datapoint.'").State("'.$objvalue.'")';

		my $response;
		my $retcode = '';

		$response = GetFileFromURL ($url);
		if ($response =~ /<r1>null</) {
			return HMCCU_SetError ($hash, "Error during CCU communication");
		}

		readingsSingleUpdate ($hash, "state", "OK", 1);

		return $retcode;
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

		$response = GetFileFromURL ($runurl . $programid);
		readingsSingleUpdate ($hash, "state", "OK", 1);

		return $response;
	}
	elsif ($opt eq 'clearmsg') {
		my $url = 'http://'.$host.'/config/xmlapi/systemNotificationClear.cgi';
		my $response;

		$response = GetFileFromURL ($url);
		readingsSingleUpdate ($hash, "state", "OK", 1);

		return '';
	}
	else {
		return "HMCCU: Unknown argument $opt, choose one of devstate datapoint execute clearmsg";
	}
}

#####################################

sub HMCCU_Get ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;
my $host = $hash->{host};

	my $readings = AttrVal ($name, "ccureadings", 1);
	my $parfile = AttrVal ($name, "parfile", '');
	my $substitute = AttrVal ($name, "substitute", '');
	my $units = AttrVal ($name, "units", 0);

	if ($opt eq 'state' || $opt eq 'devstate') {
		my $ccuobj = shift @a;
		my $reading = shift @a;
		my $response;
		my $retcode;

		if (!defined ($ccuobj)) {
			return HMCCU_SetError ($hash, "Usage: get <device> devstate <objname> [<reading>]");
		}

		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("'.$ccuobj.'").State()';
		$reading = $ccuobj if (!defined ($reading));

		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		$retcode = $1;

		if (defined ($retcode) && $retcode ne '' && $retcode ne 'null') {
			readingsSingleUpdate ($hash, "state", "OK", 1);
			if ($readings) {
				readingsSingleUpdate ($hash, $reading, $retcode, 1);
				return '';
			}
			else {
				return $retcode;
			}
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
			return HMCCU_SetError ($hash, "Usage: get <device> datapoint <objname> [<reading>]");
		}
		my ($device, $channel, $datapoint) = HMCCU_ParseCCUDev ($ccuobj);
		if ($device eq '?' || $channel eq '?' || $datapoint eq '.*') {
			return HMCCU_SetError ($hash, "Format for objname is device:channel.datapoint");
		}

		my $url = 'http://'.$host.':8181/do.exe?r1=dom.GetObject("'.$channel.'").DPByHssDP("'.$datapoint.'").Value()';
		$reading = $ccuobj if (!defined ($reading));

		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		$retcode = $1;

		if (defined ($retcode) && $retcode ne '' && $retcode ne 'null') {
			readingsSingleUpdate ($hash, "state", "OK", 1);
			if ($readings) {
				readingsSingleUpdate ($hash, $reading, $retcode, 1);
				return '';
			}
			else {
				return $retcode;
			}
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
			return HMCCU_SetError ($hash, "Usage: get <device> vars <regexp>");
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
					$result = $result . $variable->{name} . "=" . $variable->{value} . "\n";
					if ($readings) {
						readingsBulkUpdate ($hash, $variable->{name}, $variable->{value}); 
					}
				}
			}
		}

		if ($readings) {
			readingsEndUpdate ($hash, defined ($hash->{LOCAL} ? 0 : 1));
			return '';
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

		my ($device, $channel, $datapoint) = HMCCU_ParseCCUDev ($param);
		if ($device eq '?' || $channel eq '?') {
			return HMCCU_SetError ($hash, "Usage: get <device> channel <ccudev>:<channel>[.<datapoint>]");
		}

		$response = GetFileFromURL ($url);
		my $xmlin = XMLin ($response, ForceArray => ['device', 'channel', 'datapoint'], KeyAttr => { device => 'name', channel => 'name' });

		if (!defined (@{$xmlin->{device}->{$device}->{channel}->{$channel}->{datapoint}})) {
			return HMCCU_SetError ($hash, "Device or channel not defined");
		}

		my @dps = @{$xmlin->{device}->{$device}->{channel}->{$channel}->{datapoint}};
		if ($readings) {
			readingsBeginUpdate ($hash);
		}

		foreach my $dp (@dps) {
			if ($dp->{name} =~ /$datapoint/) {
				my $dpname = $dp->{name};
				my $v = $dp->{value};

				$dpname =~ /.*\.(.*)$/;
				$rname = $channel . ".$1";

				$v = HMCCU_Substitute ($v, $substitute);
				if ($units == 1) {
					$v .= ' ' . $dp->{valueunit};
				}
				$result = $result . $rname . "=" . $v . "\n";
				if ($readings) {
					readingsBulkUpdate ($hash, $rname, $v); 
				}
			}
		}

		readingsSingleUpdate ($hash, "state", "OK", 1);

		if ($readings) {
			readingsEndUpdate ($hash, defined ($hash->{LOCAL} ? 0 : 1));
			return '';
		}
		else {
			return $result;
		}
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
		my $xmlin = XMLin ($response, ForceArray => ['device', 'channel', 'datapoint'], KeyAttr => { device => 'name', channel => 'name' });

		if ($readings) {
			readingsBeginUpdate ($hash);
		}

		foreach my $param (@parameters) {
			my @partoks = split /\s+/, $param;

			# Ignore empty lines or comments
			next if (scalar @partoks == 0);
			next if ($partoks[0] =~ /^#/);

			my ($device, $channel, $datapoint) = HMCCU_ParseCCUDev ($partoks[0]);

			# Ignore wrong CCU device specifications
			next if ($device eq '?' || $channel eq '?');

			# Ignore not existing devices/channels/datapoints
			next if (!defined (@{$xmlin->{device}->{$device}->{channel}->{$channel}->{datapoint}}));
			my @dps = @{$xmlin->{device}->{$device}->{channel}->{$channel}->{datapoint}};

			foreach my $dp (@dps) {
				if ($dp->{name} =~ /$datapoint/) {
					my $dpname = $dp->{name};
					my $v = $dp->{value};

					if (@partoks > 1) {
						$v = HMCCU_Substitute ($v, $partoks[1]);
					}
					$dpname =~ /.*\.(.*)$/;
					$rname = $channel . ".$1";
					$result = $result . $rname . "=" . $v . ' ' . $dp->{valueunit} . "\n";
					if ($readings) {
						readingsBulkUpdate ($hash, $rname, $v); 
					}
				}
			}
		}

		readingsSingleUpdate ($hash, "state", "OK", 1);

		if ($readings) {
			readingsEndUpdate ($hash, defined ($hash->{LOCAL} ? 0 : 1));
			return '';
		}
		else {
			return $result;
		}
	}
	else {
		return "HMCCU: Unknown argument $opt, choose one of devstate datapoint vars channel parfile";
	}
}

#####################################
# Parse CCU object name
#
# Input: object name in format device:channel.datapoint
# Output: array with ( device, device:channel, datapoint )
#####################################

sub HMCCU_ParseCCUDev ($)
{
	my $param = $_[0];
	my $p1 = '?';
	my $p2 = '?';
	my $p3 = '.*';

	#
	# Syntax of CCU device specification is:
	#
	# devicename:channelno[.datapoint]
	#
	# Parameter datapoint is optional. 
	#
	if ($param =~ /^.+:/) {
		$param =~ /^(.*):/;
		$p1 = $1;

		if ($param =~ /^.+:[0-9]+/) {
			$param =~ /^.*:([0-9]+)/;
			$p2 = $p1 . ":" . $1;

			if ($param =~ /\..*$/) {
				$param =~ /\.(.*)$/;
				$p3 = $1;
			}
		}
	}

	return ($p1, $p2, $p3);
}

sub HMCCU_SetError ($$)
{
	my ($hash, $text) = @_;

	$text = "HMCCU: " . $text;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log 1, $text;
	return $text;
}

sub HMCCU_Substitute ($$)
{
	my ($value, $substitutes) = @_;

	return $value if (!defined ($substitutes));

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


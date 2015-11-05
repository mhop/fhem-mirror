################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id:$
#
#  Version 1.9
#
#  (c) 2015 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCUDEV <ccudev> [readonly]
#
#  set <name> datapoint <channel>.<datapoint> <value>
#  set <name> devstate <value>
#  set <name> <stateval_cmds>
#
#  get <name> devstate
#  get <name> datapoint <channel>.<datapoint>
#  get <name> update
#
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> statechannel <channel>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#
################################################################
#  Requires module 88_HMCCU
################################################################

package main;

use strict;
use warnings;
use SetExtensions;

sub HMCCUDEV_Define ($$);
sub HMCCUDEV_Set ($@);
sub HMCCUDEV_Get ($@);
sub HMCCUDEV_Attr ($@);
sub HMCCUDEV_SetError ($$);

#####################################
# Initialize module
#####################################

sub HMCCUDEV_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCUDEV_Define";
	$hash->{SetFn} = "HMCCUDEV_Set";
	$hash->{GetFn} = "HMCCUDEV_Get";
	$hash->{AttrFn} = "HMCCUDEV_Attr";

	$hash->{AttrList} = "IODev ccureadingformat:name,address,datapoint ccureadings:0,1 statevals substitute statechannel loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCUDEV_Define ($$)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return "Specifiy the CCU device name or address as parameters" if (@a < 3);

	my $devname = shift @a;
	my $devtype = shift @a;
	my $devspec = shift @a;

	if ($devspec =~ /^[A-Z]{3,3}[0-9]{7,7}$/) {
		# CCU Device address
		$hash->{ccuaddr} = $devspec;
		$hash->{ccuname} = HMCCU_GetDeviceName ($devspec, '');
	}
	elsif ($devspec =~ /^(.*):/ || $devspec =~ /\..+$/) {
		# Channel and/or datapoint specified
		return "Channel or datapoint not allowed in CCU device name";
	}
	else {
		# CCU Device name
		$hash->{ccuname} = $devspec;
		$hash->{ccuaddr} = HMCCU_GetAddress ($devspec, '', 1);
	}

	return "CCU device address not found" if ($hash->{ccuaddr} eq '');
	return "CCU device name not found" if ($hash->{ccuname} eq '');

	$hash->{ccutype} = HMCCU_GetDeviceType ($hash->{ccuaddr}, '');
	$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, '');
	$hash->{statevals} = 'devstate';
	$hash->{statechannel} = '';

	my $arg = shift @a;
	while (defined ($arg)) {
		if ($arg eq 'readonly') {
			$hash->{statevals} = $arg;
		}
		else {
			return "State channel must be numeric" if ($arg !~ /^[0-9]+$/);
			$hash->{statechannel} = $arg;
		}
		$arg = shift @a;
	}

	# Inform HMCCU device about client device
	AssignIoPort ($hash);

	readingsSingleUpdate ($hash, "state", "Initialized", 1);

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCUDEV_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;

	if (defined ($attrval) && $cmd eq "set") {
		if ($attrname eq "IODev") {
			$defs{$name}{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq "statevals") {
			$defs{$name}{statevals} = "devstate";
			my @states = split /,/,$attrval;
			foreach my $st (@states) {
				my @statesubs = split /:/,$st;
				next if (@statesubs != 2);
				$defs{$name}{statevals} .= '|'.$statesubs[0];
			}
		}
		elsif ($attrname eq "statechannel") {
			$defs{$name}{statechannel} = $attrval;
		}
	}

	return undef;
}

#####################################
# Set commands
#####################################

sub HMCCUDEV_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	if (!defined ($hash->{IODev})) {
		return HMCCUDEV_SetError ($hash, "No IO device defined");
	}
	if ($hash->{statevals} eq 'readonly') {
		return undef;
	}

	# my $statechannel = AttrVal ($name, "statechannel", '');
	my $statechannel = $hash->{statechannel};
	my $statevals = AttrVal ($name, "statevals", '');
	my $substitute = AttrVal ($name, "substitute", '');

	my $hmccu_hash = $hash->{IODev};
	my $hmccu_name = $hash->{IODev}->{NAME};

	# process set <name> command par1 ...
	if ($opt eq 'datapoint') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);

		if (!defined ($objname) || $objname !~ /^[0-9]+\..+$/ || !defined ($objvalue)) {
			return HMCCUDEV_SetError ($hash, "Usage: set <device> datapoint <channel>.<datapoint> <value> [...]");
		}
		$objvalue = HMCCU_Substitute ($objvalue, $substitute);

		# Build datapoint address
		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname;

		HMCCU_Set ($hmccu_hash, $hmccu_name, 'datapoint', $objname, $objvalue);
		usleep (100000);
		HMCCU_Get ($hmccu_hash, $hmccu_name, 'datapoint', $objname);

		return undef;
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : join ('%20', @a);

		if ($statechannel eq '') {
			return HMCCUDEV_SetError ($hash, "No STATE channel specified");
		}
		if (!defined ($objvalue)) {
			return HMCCUDEV_SetError ($hash, "Usage: set <device> devstate <value>");
		}
		$objvalue = HMCCU_Substitute ($objvalue, $statevals);

		# Build datapoint address
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel.'.STATE';

		HMCCU_Set ($hmccu_hash, $hmccu_name, 'datapoint', $objname, $objvalue);
		usleep (100000);
		HMCCU_Get ($hmccu_hash, $hmccu_name, 'datapoint', $objname);

		return undef;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of datapoint devstate";
		return undef if ($hash->{statevals} eq 'readonly');

		if ($statevals ne '') {
			my @cmdlist = split /\|/,$hash->{statevals};
			shift @cmdlist;
			$retmsg .= ':'.join(',',@cmdlist);
			foreach my $sv (@cmdlist) {
				$retmsg .= ' '.$sv.':noArg';
			}
		}

		return $retmsg;
	}
}

#####################################
# Get commands
#####################################

sub HMCCUDEV_Get ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	if (!defined ($hash->{IODev})) {
		return HMCCUDEV_SetError ($hash, "No IO device defined");
	}

	my $hmccu_hash = $hash->{IODev};
	my $hmccu_name = $hash->{IODev}->{NAME};

	if ($opt eq 'devstate') {
		# my $statechannel = AttrVal ($name, 'statechannel', '');
		my $statechannel = $hash->{statechannel};
		if ($statechannel eq '') {
			return HMCCUDEV_SetError ($hash, "No STATE channel specified");
		}

		# Build datapoint address
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel;
		HMCCU_Get ($hmccu_hash, $hmccu_name, 'devstate', $objname);

		return undef;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @a;
		if (!defined ($objname) || $objname !~ /^[0-9]+\..*$/) {
			return HMCCUDEV_SetError ($hash, "Usage: get <device> datapoint <channel>.<datapoint>");
		}

		# Build datapoint address
		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname;

		HMCCU_Get ($hmccu_hash, $hmccu_name, 'datapoint', $objname);

		return undef;
	}
	elsif ($opt eq 'update') {
		foreach my $r (keys %{$hash->{READINGS}}) {
			if ($r =~ /^.+:[0-9]+\..+/) {
				HMCCU_Get ($hmccu_hash, $hmccu_name, 'datapoint', $r);
			}
		}
	}
	else {
		return "HMCCUDEV: Unknown argument $opt, choose one of devstate:noArg datapoint update:noArg";
	}
}

#####################################
# Set error status
#####################################

sub HMCCUDEV_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};

	$text = "HMCCUDEV: ".$name." ". $text;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log 1, $text;
	return $text;
}

1;

=pod
=begin html

<a name="HMCCUDEV"></a>
<h3>HMCCUDEV</h3>
<div style="width:800px"> 
<ul>
   The module implements client devices for HMCCU. A HMCCU device must exist
   before a client device can be defined.
   </br></br>
   <a name="HMCCUDEVdefine"></a>
   <b>Define</b>
   <ul>
      <br/>
      <code>define &lt;name&gt; HMCCUDEV &lt;<i>CCU_Device</i>&gt; [readonly]</code>
      <br/><br/>
      If <i>readonly</i> parameter is specified no set command will be available.
      <br/><br/>
      Examples:<br/>
      <code>define window_living HMCCUDEV WIN-LIV-1 readonly</code><br/>
      <code>define temp_control HMCCUDEV TEMP-CONTROL</code>
      <br/><br/>
      <i>CCU_Device</i> - Name of device in CCU without channel or datapoint.
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVset"></a>
   <b>Set</b><br/>
   <ul>
      <br/>
      <li>set &lt;<i>Name</i>&gt; devstate &lt;<i>Value</i>&gt;
         <br/>
         Set state of a CCU device channel. Channel must be defined as attribute
         statechannel.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate on</code>
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; &lt;<i>StateValue</i>&gt;
         <br/>
         State of a CCU device channel is set to <i>StateValue</i>. Channel must
         be defined as attribute statechannel. State values can be replaced
         by setting attribute statevals.
         <br/><br/>
         Example:<br/>
         <code>
         attr myswitch statechannel 1<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; datapoint &lt;<i>channel</i>.<i>datapoint</i>&gt; &lt;<i>Value</i>&gt;
        <br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint TEMP_CONTROL:2.SET_TEMPERATURE 21</code>
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVget"></a>
   <b>Get</b><br/>
   <ul>
      <br/>
      <li>get &lt;<i>Name</i>&gt; devstate
         <br/>
         Get state of CCU device. Attribute 'statechannel' must be set.
      </li><br/>
      <li>get &lt;<i>Name</i>&gt; datapoint &lt;<i>Device</i>:<i>Channel</i>.<i>datapoint</i>&gt;
         <br/>
         Get value of a CCU device datapoint.
      </li><br/>
      <li>get &lt;<i>Name</i>&gt; update
         <br/>
         Update current readings matching CCU device name.
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccureadings &lt;0 | 1&gt;
         <br/>
            If set to 1 values read from CCU will be stored as readings.
      </li><br/>
      <li>statechannel &lt;channel-number&gt;
         <br/>
            Channel for setting device state by devstate command.
      </li><br/>
      <li>statevals &lt;text&gt;:&lt;text&gt;[,...]
         <br/>
            Define substitution for set commands values. The parameters &lt;text&gt;
            are available as set commands. Example:<br/>
            <code>attr my_switch statevals on:true,off:false</code><br/>
            <code>set my_switch on</code>
      </li><br/>
      <li>substitude &lt;expression&gt;:&lt;subststr&gt;[,...]
         <br/>
            Define substitions for reading values. Substitutions for parfile values must
            be specified in parfiles.
      </li><br/>
   </ul>
</ul>
</div>

=end html
=cut


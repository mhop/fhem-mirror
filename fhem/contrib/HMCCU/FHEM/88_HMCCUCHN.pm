################################################################
#
#  88_HMCCUCHN.pm
#
#  $Id:$
#
#  Version 3.3
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCUCHN <ccudev> [readonly]
#
#  set <name> control <value>
#  set <name> datapoint <datapoint> <value>
#  set <name> devstate <value>
#  set <name> <stateval_cmds>
#  set <name> toggle
#  set <name> config <parameter>=<value> [...]
#
#  get <name> devstate
#  get <name> datapoint <datapoint>
#  get <name> channel <datapoint-expr>
#  get <name> config
#  get <name> configdesc
#  get <name> update
#
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccureadingfilter <datapoint-expr>
#  attr <name> ccureadingformat { name | address | datapoint }
#  attr <name> ccuverify { 0 | 1 | 2 }
#  attr <name> controldatapoint <datapoint>
#  attr <name> disable { 0 | 1 }
#  attr <name> statedatapoint <datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> substitute <subst-rule>[;...]
#
################################################################
#  Requires module 88_HMCCU.pm
################################################################

package main;

use strict;
use warnings;
use SetExtensions;

use Time::HiRes qw( gettimeofday usleep );

sub HMCCUCHN_Define ($@);
sub HMCCUCHN_Set ($@);
sub HMCCUCHN_Get ($@);
sub HMCCUCHN_Attr ($@);
sub HMCCUCHN_SetError ($$);

#####################################
# Initialize module
#####################################

sub HMCCUCHN_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCUCHN_Define";
	$hash->{SetFn} = "HMCCUCHN_Set";
	$hash->{GetFn} = "HMCCUCHN_Get";
	$hash->{AttrFn} = "HMCCUCHN_Attr";

	$hash->{AttrList} = "IODev ccureadingfilter ccureadingformat:name,address,datapoint ccureadings:0,1 ccuscaleval ccuverify:0,1,2 ccuget:State,Value controldatapoint disable:0,1 statedatapoint statevals substitute stripnumber:0,1,2 ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCUCHN_Define ($@)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return "Specifiy the CCU device name or address as parameters" if (@a < 3);

	my $devname = shift @a;
	my $devtype = shift @a;
	my $devspec = shift @a;

	return "Invalid or unknown CCU channel name or address" if (! HMCCU_IsValidDevice ($devspec));

	if (HMCCU_IsChnAddr ($devspec, 1)) {
		# CCU Channel address with interface
		$hash->{ccuif} = $1;
		$hash->{ccuaddr} = $2;
		$hash->{ccuname} = HMCCU_GetChannelName ($hash->{ccuaddr}, '');
		return "CCU device name not found for channel address $devspec" if ($hash->{ccuname} eq '');
	}
	elsif (HMCCU_IsChnAddr ($devspec, 0)) {
		# CCU Channel address
		$hash->{ccuaddr} = $devspec;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
		$hash->{ccuname} = HMCCU_GetChannelName ($devspec, '');
		return "CCU device name not found for channel address $devspec" if ($hash->{ccuname} eq '');
	}
	else {
		# CCU Channel name
		$hash->{ccuname} = $devspec;
		my ($add, $chn) = HMCCU_GetAddress ($devspec, '', '');
		return "Channel address not found for channel name $devspec" if ($add eq '' || $chn eq '');
		$hash->{ccuaddr} = $add.':'.$chn;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}

	$hash->{ccutype} = HMCCU_GetDeviceType ($hash->{ccuaddr}, '');
	$hash->{channels} = 1;
	$hash->{statevals} = 'devstate';

	my $arg = shift @a;
	if (defined ($arg) && $arg eq 'readonly') {
		$hash->{statevals} = $arg;
	}

	# Inform HMCCU device about client device
	AssignIoPort ($hash);

	readingsSingleUpdate ($hash, "state", "Initialized", 1);
	$hash->{ccudevstate} = 'Active';

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCUCHN_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if ($cmd eq "set") {
		return "Missing attribute value" if (!defined ($attrval));
		if ($attrname eq 'IODev') {
			$hash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq 'statevals') {
			return "Device is read only" if ($hash->{statevals} eq 'readonly');
			$hash->{statevals} = "devstate";
			my @states = split /,/,$attrval;
			foreach my $st (@states) {
				my @statesubs = split /:/,$st;
				return "value := text:substext[,...]" if (@statesubs != 2);
				$hash->{statevals} .= '|'.$statesubs[0];
			}
		}
	}
	elsif ($cmd eq "del") {
		if ($attrname eq 'statevals') {
			$hash->{statevals} = "devstate";
		}
	}

	return undef;
}

#####################################
# Set commands
#####################################

sub HMCCUCHN_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));
	return undef if ($hash->{statevals} eq 'readonly' && $opt ne 'config');

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

	my $statevals = AttrVal ($name, "statevals", '');
#	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
#	my $controldatapoint = AttrVal ($name, "controldatapoint", '');
	my ($sc, $statedatapoint, $cc, $controldatapoint) = HMCCU_GetSpecialDatapoints (
	   $hash, '', 'STATE', '', '');

	my $result = '';
	my $rc;

	if ($opt eq 'datapoint') {
		my $objname = shift @a;
#		my $objvalue = join ('%20', @a);
		my $objvalue = shift @a;

		return HMCCU_SetError ($hash, "Usage: set $name datapoint {datapoint} {value} [...]")
		   if (!defined ($objname) || !defined ($objvalue));
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $hash->{ccutype},
		   $hash->{ccuaddr}, $objname, 2));
		   
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		# Build datapoint address
		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$objname;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'control') {
		return HMCCU_SetError ($hash, "Attribute controldatapoint not set") if ($controldatapoint eq '');
		my $objvalue = shift @a;
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$controldatapoint;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : shift @a;

		return HMCCU_SetError ($hash, "Usage: set $name devstate {value}") if (!defined ($objvalue));

		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		# Build datapoint address
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$statedatapoint;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_SetError ($hash, "Attribute statevals not set")
		   if ($statevals eq '' || !exists($hash->{statevals}));

		my $tstates = $hash->{statevals};
		$tstates =~ s/devstate\|//;
		my @states = split /\|/, $tstates;
		my $sc = scalar (@states);

		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$statedatapoint;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		my $objvalue = '';
		my $st = 0;
		while ($st < $sc) {
			if ($states[$st] eq $result) {
				$objvalue = ($st == $sc-1) ? $states[0] : $states[$st+1];
				last;
			}
			else {
				$st++;
			}
		}

		return HMCCU_SetError ($hash, "Current device state doesn't match statevals")
		   if ($objvalue eq '');

		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'config') {
		return HMCCU_SetError ($hash, "Usage: set $name config {parameter}={value} [...]") if (@a < 1);;

		my $rc = HMCCU_RPCSetConfig ($hash, $hash->{ccuaddr}, \@a);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	else {
		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of config datapoint devstate";
		return undef if ($hash->{statevals} eq 'readonly');

		if ($hash->{statevals} ne '') {
			my @cmdlist = split /\|/,$hash->{statevals};
			shift @cmdlist;
			$retmsg .= ':'.join(',',@cmdlist) if (@cmdlist > 0);
			foreach my $sv (@cmdlist) {
				$retmsg .= ' '.$sv.':noArg';
			}
			$retmsg .= " toggle:noArg";
		}

		return $retmsg;
	}
}

#####################################
# Get commands
#####################################

sub HMCCUCHN_Get ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

#	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my ($sc, $statedatapoint, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');
	my $ccureadings = AttrVal ($name, "ccureadings", 1);

	my $result = '';
	my $rc;

	if ($opt eq 'devstate') {
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$statedatapoint;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @a;
		return HMCCU_SetError ($hash, "Usage: get $name datapoint {datapoint}") if (!defined ($objname));
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $hash->{ccutype},
		   $hash->{ccuaddr}, $objname, 1));

		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'channel') {
		my $dptexpr = shift @a;
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr};
		$objname .= '.'.$dptexpr if (defined ($dptexpr));
		my @chnlist = ($objname);
		($rc, $result) = HMCCU_GetChannel ($hash, \@chnlist);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'update') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name update [{'State'|'Value'}]");
		}
		$rc = HMCCU_GetUpdate ($hash, $hash->{ccuaddr}, $ccuget);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return undef;
	}
	elsif ($opt eq 'config') {
		my $ccuobj = $hash->{ccuaddr};

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamset");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $res;
	}
	elsif ($opt eq 'configdesc') {
		my $ccuobj = $hash->{ccuaddr};

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $res;
	}
	else {
		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of devstate:noArg datapoint";
		
		my ($a, $c) = split(":", $hash->{ccuaddr});
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $hash->{ccutype}, $c, 1, \@valuelist);	
		$retmsg .= ":".join(",",@valuelist) if ($valuecount > 0);
		$retmsg .= " channel update:noArg config:noArg configdesc:noArg";
		
		return $retmsg;
	}
}

#####################################
# Set error status
#####################################

sub HMCCUCHN_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};
	my $msg;
	my %errlist = (
		-1 => 'Channel name or address invalid',
		-2 => 'Execution of CCU script failed',
		-3 => 'Cannot detect IO device',
		-4 => 'Device deleted in CCU',
		-5 => 'No response from CCU',
		-6 => 'Update of readings disabled. Set attribute ccureadings first'
	);

	if (exists ($errlist{$text})) {
		$msg = $errlist{$text};
	}
	else {
		$msg = $text;
	}

	$msg = "HMCCUCHN: ".$name." ". $msg;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log3 $name, 1, $msg;
	return $msg;
}

1;

=pod
=begin html

<a name="HMCCUCHN"></a>
<h3>HMCCUCHN</h3>
<ul>
   The module implements client devices for HMCCU. A HMCCU device must exist
   before a client device can be defined.
   </br></br>
   <a name="HMCCUCHNdefine"></a>
   <b>Define</b>
   <ul>
      <br/>
      <code>define &lt;name&gt; HMCCUCHN {&lt;channel-name&gt;|&lt;channel-address&gt;} [readonly]</code>
      <br/><br/>
      If <i>readonly</i> parameter is specified no set command will be available.
      <br/><br/>
      Examples:<br/>
      <code>define window_living HMCCUCHN WIN-LIV-1 readonly</code><br/>
      <code>define temp_control HMCCUCHN BidCos-RF.LEQ1234567:1</code>
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUCHNset"></a>
   <b>Set</b><br/>
   <ul>
      <br/>
      <li>set &lt;name&gt; devstate &lt;value&gt; [...]<br/>
         Set state of a CCU device channel. Channel datapoint must be defined
         by setting attribute 'statedatapoint'.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate on</code>
      </li><br/>
      <li>set &lt;name&gt; &lt;statevalue&gt;<br/>
         State of a CCU device channel is set to <i>StateValue</i>. State datapoint
         must be defined as attribute statedatapoint. State values can be replaced
         by setting attribute statevals.
         <br/><br/>
         Example:<br/>
         <code>
         attr myswitch statedatapoint TEST<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li>set &lt;name&gt; toggle<br/>
        Toggles between values defined by attribute 'statevals'.
      </li><br/>
      <li>set &lt;name&gt; datapoint &lt;datapoint&gt; &lt;value&gt;<br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint SET_TEMPERATURE 21</code>
      </li><br/>
      <li>set &lt;name&gt; config [&lt;rpcport&gt;] &lt;parameter&gt;=&lt;value&gt;] [...] <br/>
        Set config parameters of CCU channel.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNget"></a>
   <b>Get</b><br/>
   <ul>
      <br/>
      <li>get &lt;name&gt; devstate<br/>
         Get state of CCU device. Default datapoint STATE can be changed by setting
         attribute 'statedatapoint'.
      </li><br/>
      <li>get &lt;name&gt; datapoint &lt;datapoint&gt;<br/>
         Get value of a CCU device datapoint.
      </li><br/>
      <li>get &lt;name&gt; config<br/>
         Get configuration parameters of CCU channel. If attribute ccureadings is 0 results will be
         displayed in browser window.
      </li><br/>
      <li>get &lt;name&gt; configdesc<br/>
         Get description of configuration parameters of CCU channel.
      </li><br/>
      <li>get &lt;name&gt; update [{'State'|'Value'}]<br/>
         Update all datapoints / readings of channel.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccuget &lt;State | Value&gt;<br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value' because
         each request is sent to the device. With method 'Value' only CCU is queried. Default is 'Value'.
      </li><br/>
      <li>ccureadings &lt;0 | 1&gt;<br/>
         If set to 1 values read from CCU will be stored as readings. Default is 1.
      </li><br/>
      <li>ccureadingfilter &lt;filter-rule[,...]&gt;<br/>
         Only datapoints matching specified expression are stored as readings.<br/>
         Syntax for filter rule is: [channel-no:]RegExp<br/>
         If channel-no is specified the following rule applies only to this channel.
      </li><br/>
      <li>ccuscaleval &lt;datapoint&gt;:&lt;factor&gt;[,...] <br/>
         Scale datapoint values before executing set datapoint commands or after executing get
         datapoint commands. During get the value read from CCU is devided by factor. During set
         the value is multiplied by factor.
      </li><br/>
      <li>ccuverify &lt;0 | 1 | 2&gt;<br/>
         If set to 1 a datapoint is read for verification after set operation. If set to 2 the
         corresponding reading will be set to the new value directly after setting a datapoint
         in CCU.
      </li><br/>
      <li>controldatapoint &lt;datapoint&gt;<br/>
         Set datapoint for device control. Can be use to realize user defined control elements for
         setting control datapoint. For example if datapoint of thermostat control is 
         SET_TEMPERATURE one can define a slider for setting the destination temperature with
         following attributes:<br/><br/>
         attr mydev controldatapoint SET_TEMPERATURE
         attr mydev webCmd control
         attr mydev widgetOverride control:slider,10,1,25
      </li><br/>
      <li>disable &lt;0 | 1&gt;<br/>
      	Disable client device.
      </li><br/>
      <li>statedatapoint &lt;datapoint&gt;<br/>
         Set datapoint for devstate commands.
      </li><br/>
      <li>statevals &lt;text&gt;:&lt;text&gt;[,...]<br/>
         Define substitution for set commands values. The parameters &lt;text&gt;
         are available as set commands. Example:<br/>
         <code>attr my_switch statevals on:true,off:false</code><br/>
         <code>set my_switch on</code>
      </li><br/>
      <li>substitude &lt;subst-rule&gt;[;...]<br/>
         Define substitions for reading values. Substitutions for parfile values must
         be specified in parfiles. Syntax of subst-rule is<br/><br/>
         [datapoint!]&lt;regexp1&gt;:&lt;text1&gt;[,...]
      </li>
   </ul>
</ul>

=end html
=cut


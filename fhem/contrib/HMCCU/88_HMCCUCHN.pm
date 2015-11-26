################################################################
#
#  88_HMCCUCHN.pm
#
#  $Id:$
#
#  Version 2.0
#
#  (c) 2015 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCUCHN <ccudev> [readonly]
#
#  set <name> datapoint <datapoint> <value> [...]
#  set <name> devstate <value> [...]
#  set <name> <stateval_cmds>
#
#  get <name> devstate
#  get <name> datapoint <datapoint>
#  get <name> channel <datapoint-expr>
#
#  attr <name> ccureadings { 0 | 1 }
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

	$hash->{AttrList} = "IODev ccureadingformat:name,address,datapoint ccureadings:0,1 statedatapoint statevals substitute loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
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

	if ($devspec =~ /^(.+)\.([A-Z]{3,3}[0-9]{7,7}:[0-9]+)$/) {
		# CCU Channel address with interface
		$hash->{ccuif} = $1;
		$hash->{ccuaddr} = $2;
		$hash->{ccuname} = HMCCU_GetDeviceName ($hash->{ccuaddr}, '');
		return "CCU device name not found for channel address $devspec" if ($hash->{ccuname} eq '');
	}
	elsif ($devspec =~ /^[A-Z]{3,3}[0-9]{7,7}:[0-9]+$/) {
		# CCU Channel address
		$hash->{ccuaddr} = $devspec;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
		$hash->{ccuname} = HMCCU_GetDeviceName ($devspec, '');
		return "CCU device name not found for channel address $devspec" if ($hash->{ccuname} eq '');
	}
	else {
		# CCU Device name
		$hash->{ccuname} = $devspec;
		my ($add, $chn) = HMCCU_GetAddress ($devspec, '', '');
		return "Channel address not found for channel name $devspec" if ($add eq '' || $chn eq '');
		$hash->{ccuaddr} = $add.':'.$chn;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}

	$hash->{ccutype} = HMCCU_GetDeviceType ($hash->{ccuaddr}, '');
	$hash->{statevals} = 'devstate';

	my $arg = shift @a;
	if (defined ($arg) && $arg eq 'readonly') {
		$hash->{statevals} = $arg;
	}

	# Inform HMCCU device about client device
	AssignIoPort ($hash);

	readingsSingleUpdate ($hash, "state", "Initialized", 1);

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

	if (!defined ($hash->{IODev})) {
		return HMCCUCHN_SetError ($hash, "No IO device defined");
	}
	if ($hash->{statevals} eq 'readonly') {
		return undef;
	}

	my $statevals = AttrVal ($name, "statevals", '');
	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');

	my $result = '';
	my $rc;

	if ($opt eq 'datapoint') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);

		if (!defined ($objname) || !defined ($objvalue)) {
			return HMCCUCHN_SetError ($hash, "Usage: set <name> datapoint <datapoint> <value> [...]");
		}
		$objvalue = HMCCU_Substitute ($objvalue, $statevals);

		# Build datapoint address
		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$objname;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCUCHN_SetError ($hash, $rc) if ($rc < 0);

		usleep (100000);
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCUCHN_SetError ($hash, $rc) if ($rc < 0);

		return undef;
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : join ('%20', @a);

		if (!defined ($objvalue)) {
			return HMCCUCHN_SetError ($hash, "Usage: set <device> devstate <value>");
		}
		$objvalue = HMCCU_Substitute ($objvalue, $statevals);

		# Build datapoint address
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$statedatapoint;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCUCHN_SetError ($hash, $rc) if ($rc < 0);

		usleep (100000);
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCUCHN_SetError ($hash, $rc) if ($rc < 0);

		return undef;
	}
	else {
		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of datapoint devstate";
		return undef if ($hash->{statevals} eq 'readonly');

		if ($hash->{statevals} ne '') {
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

sub HMCCUCHN_Get ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	if (!defined ($hash->{IODev})) {
		return HMCCUCHN_SetError ($hash, "No IO device defined");
	}

	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my $ccureadings = AttrVal ($name, "ccureadings", 1);

	my $result = '';
	my $rc;

	if ($opt eq 'devstate') {
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$statedatapoint;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCUCHN_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @a;
		return HMCCUCHN_SetError ($hash, "Usage: get <name> datapoint <datapoint>") if (!defined ($objname));

		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.'.'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCUCHN_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'channel') {
		my $dptexpr = shift @a;
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr};
		$objname .= '.'.$dptexpr if (defined ($dptexpr));
		my @chnlist = ($objname);
		($rc, $result) = HMCCU_GetChannel ($hash, \@chnlist);
		return HMCCUCHN_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	else {
		return "HMCCUCHN: Unknown argument $opt, choose one of devstate:noArg datapoint channel";
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
	   -3 => 'Cannot detect IO device'
	);

	if (exists ($errlist{$text})) {
		$msg = $errlist{$text};
	}
	else {
		$msg = $text;
	}

	$msg = "HMCCUCHN: ".$name." ". $msg;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log 1, $msg;
	return $msg;
}

1;

=pod
=begin html

<a name="HMCCUCHN"></a>
<h3>HMCCUCHN</h3>
<div style="width:800px"> 
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
      <li>set &lt;name&gt; devstate &lt;value&gt; [...]
         <br/>
         Set state of a CCU device channel. Channel datapoint must be defined
         by setting attribute 'statedatapoint'.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate on</code>
      </li><br/>
      <li>set &lt;name&gt; &lt;statevalue&gt;
         <br/>
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
      <li>set &lt;name&gt; datapoint &lt;datapoint&gt; &lt;value&gt; [...]
        <br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint SET_TEMPERATURE 21</code>
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNget"></a>
   <b>Get</b><br/>
   <ul>
      <br/>
      <li>get &lt;name&gt; devstate
         <br/>
         Get state of CCU device. Default datapoint STATE can be changed by setting
         attribute 'statedatapoint'.
      </li><br/>
      <li>get &lt;name&gt; datapoint &lt;datapoint&gt;
         <br/>
         Get value of a CCU device datapoint.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccureadings &lt;0 | 1&gt;
         <br/>
            If set to 1 values read from CCU will be stored as readings.
      </li><br/>
      <li>statedatapoint &lt;datapoint&gt;
         <br/>
            Set datapoint for devstate commands.
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
            Define substitions for reading values.
      </li>
   </ul>
</ul>
</div>

=end html
=cut


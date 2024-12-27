######################################################################
#
#  88_HMCCUCHN.pm
#
#  $Id$
#
#  Version 5.0
#
#  (c) 2024 zap (zap01 <at> t-online <dot> de)
#
######################################################################
#  Client device for Homematic channels.
#  Requires module 88_HMCCU.pm
######################################################################

package main;

use strict;
use warnings;
use SetExtensions;

# require "$attr{global}{modpath}/FHEM/88_HMCCU.pm";

sub HMCCUCHN_Initialize ($);
sub HMCCUCHN_Define ($@);
sub HMCCUCHN_InitDevice ($$);
sub HMCCUCHN_Undef ($$);
sub HMCCUCHN_Rename ($$);
sub HMCCUCHN_Set ($@);
sub HMCCUCHN_Get ($@);
sub HMCCUCHN_Attr ($@);

my $HMCCUCHN_VERSION = '2024-12';

######################################################################
# Initialize module
######################################################################

sub HMCCUCHN_Initialize ($)
{
	my ($hash) = @_;

	$hash->{version} = $HMCCUCHN_VERSION;

	$hash->{DefFn}    = 'HMCCUCHN_Define';
	$hash->{UndefFn}  = 'HMCCUCHN_Undef';
	$hash->{RenameFn} = 'HMCCUCHN_Rename';
	$hash->{SetFn}    = 'HMCCUCHN_Set';
	$hash->{GetFn}    = 'HMCCUCHN_Get';
	$hash->{AttrFn}   = 'HMCCUCHN_Attr';
	$hash->{parseParams} = 1;

	$hash->{AttrList} = 'IODev ccucalculate '.
		'ccuflags:multiple-strict,hideStdReadings,replaceStdReadings,noBoundsChecking,ackState,logCommand,noAutoSubstitute,noReadings,trace,simulate,showMasterReadings,showLinkReadings,showDeviceReadings '.
		'ccureadingfilter:textField-long statedatapoint controldatapoint '.
		'ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc '.
		'ccureadingname:textField-long ccuSetOnChange ccuReadingPrefix '.
		'ccuscaleval ccuverify:0,1,2 ccuget:State,Value devStateFlags '.
		'disable:0,1 hmstatevals:textField-long statevals substitute:textField-long '.
		'substexcl stripnumber traceFilter '. $readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCUCHN_Define ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};

	my $usage = "Usage: define $name HMCCUCHN {device} ['readonly'] ['noDefaults'|'defaults'] [iodev={iodevname}]";
	return $usage if (@$a < 3);

	my ($devname, $devtype, $devspec) = splice (@$a, 0, 3);
	my $ioHash;

	my @errmsg = (
		"OK",
		"Invalid or unknown CCU device name or address",
		"Can't assign I/O device"
	);

	my @warnmsg = (
		"OK",
		"Unknown warning message",
		"Device type not known by HMCCU. Please set control and/or state channel with attributes controldatapoint and statedatapoint"
	);

	my $existDev = HMCCU_ExistsClientDevice ($devspec, $devtype);
	return "FHEM device $existDev for CCU device $devspec already exists" if ($existDev ne '');
		
	# Store some definitions for delayed initialization
	$hash->{hmccu}{devspec} = $devspec;
	
	# Defaults
	$hash->{readonly} = 'no';
	$hash->{hmccu}{channels} = 1;
	$hash->{hmccu}{nodefaults} = $init_done ? 0 : 1;
	$hash->{hmccu}{detect} = 0;
	$hash->{hmccu}{setDefaults} = 0;
	
	# Parse optional command line parameters
	my $n = 0;
	while (my $arg = shift @$a) {
		return $usage if ($n == 3);
		if    ($arg eq 'readonly')       { $hash->{readonly} = 'yes'; }
		elsif (lc($arg) eq 'nodefaults') { $hash->{hmccu}{nodefaults} = 1 if ($init_done); }
		elsif (lc($arg) eq 'defaults')   { $hash->{hmccu}{nodefaults} = 0 if ($init_done); }
		else                             { return $usage; }
		$n++;
	}
	
	# IO device can be set by command line parameter iodev, otherwise try to detect IO device
	if (exists($h->{iodev})) {
		return "Device $h->{iodev} does not exist" if (!exists($defs{$h->{iodev}}));
		return "Type of device $h->{iodev} is not HMCCU" if ($defs{$h->{iodev}}->{TYPE} ne 'HMCCU');
		$ioHash = $defs{$h->{iodev}};
	}
	else {
		# The following call will fail during FHEM start if CCU is not ready
		$ioHash = HMCCU_FindIODevice ($devspec);
	}
	
	if ($init_done) {
		# Interactive define command while CCU not ready or no IO device defined
		if (!defined($ioHash)) {
			my ($ccuactive, $ccuinactive) = HMCCU_IODeviceStates ();
			return $ccuinactive > 0 ?
				'CCU and/or IO device not ready. Please try again later' :
				'Cannot detect IO device or CCU device not found';
		}
	}
	else {
		# CCU not ready during FHEM start
		if (!defined($ioHash) || $ioHash->{ccustate} ne 'active') {
			HMCCU_Log ($hash, 3, "Cannot detect IO device, maybe CCU not ready or device doesn't exist on CCU");
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}
	
	# Initialize FHEM device, set IO device
	my $rc = HMCCUCHN_InitDevice ($ioHash, $hash);
	if (HMCCU_IsIntNum ($rc)) {
		return $errmsg[$rc] if ($rc > 0 && $rc < scalar(@errmsg));
		HMCCU_LogDisplay ($hash, 2, $warnmsg[-$rc]) if ($rc < 0 && -$rc < scalar(@warnmsg));
		return undef;
	}
	else {
		return $rc;
	}
}

######################################################################
# Initialization of FHEM device.
# Called during Define() or by HMCCU after CCU ready.
# Return 0 on successful initialization or >0 on error:
# 1 = Invalid channel name or address
# 2 = Cannot assign IO device
# -2 = Device type not known by HMCCU
######################################################################

sub HMCCUCHN_InitDevice ($$)
{
	my ($ioHash, $devHash) = @_;
	my $name = $devHash->{NAME};
	my $devspec = $devHash->{hmccu}{devspec};
	
	return 1 if (!HMCCU_IsValidChannel ($ioHash, $devspec, 7));

	my ($di, $da, $dn, $dt, $dc) = HMCCU_GetCCUDeviceParam ($ioHash, $devspec);
	return 1 if (!defined($da));

	# Inform HMCCU device about client device
	return 2 if (!HMCCU_AssignIODevice ($devHash, $ioHash->{NAME}));

	$devHash->{ccuif}       = $di;
	$devHash->{ccuaddr}     = $da;
	$devHash->{ccuname}     = $dn;
	$devHash->{ccutype}     = $dt;
	$devHash->{ccudevstate} = 'active';
	
	my $rc = 0;

	if ($init_done && !HMCCU_IsDelayedInit ($ioHash)) {
		my $detect = HMCCU_DetectDevice ($ioHash, $da, $di);
		
		# Interactive device definition
		HMCCU_SetSCAttributes ($ioHash, $devHash, $detect);		# Set selection lists for attributes statedatapoint and controldatapoint
		HMCCU_AddDevice ($ioHash, $di, $da, $devHash->{NAME});	# Add device to internal IO device hashes
		HMCCU_UpdateDevice ($ioHash, $devHash);					# Set device information like firmware and links
		HMCCU_UpdateDeviceRoles ($ioHash, $devHash);			# Set CCU type, CCU subtype and roles
		HMCCU_SetInitialAttributes ($ioHash, $name);			# Set global attributes as defined in IO device attribute ccudef-attributes
		
		if (defined($detect) && $detect->{level} > 0) {
			my ($sc, $sd, $cc, $cd, $rsd, $rcd) = HMCCU_SetDefaultSCDatapoints ($ioHash, $devHash, $detect, 1);
			HMCCU_Log ($devHash, 2, "Cannot set default state- and/or control datapoints. Maybe device type not known by HMCCU")
				if ($rsd == 0 && $rcd == 0);

			if (!exists($devHash->{hmccu}{nodefaults}) || $devHash->{hmccu}{nodefaults} == 0) {
				# Don't let device definition fail if default attributes cannot be set
				my ($rc, $retMsg) = HMCCU_SetDefaultAttributes ($devHash);
				if (!$rc) {
					HMCCU_Log ($devHash, 2, $retMsg);
					HMCCU_Log ($devHash, 2, 'No HMCCU 4.3 default attributes found during device definition')
						if (!HMCCU_SetDefaults ($devHash));
				}
			}
		}
		else {
			$rc = -2;
		}

		HMCCU_ExecuteGetExtValuesCommand ($devHash, $da);
	}

	return $rc;
}

######################################################################
# Delete device
######################################################################

sub HMCCUCHN_Undef ($$)
{
	my ($hash, $arg) = @_;

	if (defined($hash->{IODev})) {
		HMCCU_RemoveDevice ($hash->{IODev}, $hash->{ccuif}, $hash->{ccuaddr}, $hash->{NAME});
	}
	
	return undef;
}

######################################################################
# Rename device
######################################################################

sub HMCCUCHN_Rename ($$)
{
	my ($newName, $oldName) = @_;
	
	my $clHash = $defs{$newName};
	my $ioHash = defined($clHash) ? $clHash->{IODev} : undef;
	
	HMCCU_RenameDevice ($ioHash, $clHash, $oldName);
}

######################################################################
# Set attribute
######################################################################

sub HMCCUCHN_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $clHash = $defs{$name};
	my $ioHash = HMCCU_GetHash ($clHash);
	my $clType = $clHash->{TYPE};

	if ($cmd eq 'set') {
		return 'Missing attribute value' if (!defined($attrval));
		if ($attrname eq 'IODev') {
			$clHash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq 'statevals') {
			return "$clType [$name] Attribute statevals ignored. Device is read only" if ($clHash->{readonly} eq 'yes');
			return "$clType [$name] Attribute statevals ignored. Device type is known by HMCCU" if ($clHash->{hmccu}{detect} > 0);
			if ($init_done && !HMCCU_IsValidControlDatapoint ($clHash)) {
				HMCCU_LogDisplay ($clHash, 2, 'Warning: Attribute controldatapoint not set or set to invalid datapoint');
			}
		}
		elsif ($attrname =~ /^(state|control)datapoint$/) {
			my $role = HMCCU_GetChannelRole ($clHash);
			return "$clType [$name] Invalid value $attrval for attribute $attrname"
				if (!HMCCU_SetSCDatapoints ($clHash, $attrname, $attrval, $role, 1));
		}
		elsif ($attrname eq 'devStateFlags') {
			my @t = split(':', $attrval);
			return "$clType [$name] Missing flag and or value expression in attribute $attrname" if (scalar(@t) != 3);
		}
		elsif ($attrname eq 'peer') {
			return "$clType [$name] Attribute 'peer' is no longer supported. Please use DOIF or NOTIFY";
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname =~ /^(state|control)datapoint$/) {
			# Reset value
			HMCCU_SetSCDatapoints ($clHash, $attrname);
			delete $clHash->{hmccu}{roleCmds}
				if (exists($clHash->{hmccu}{roleCmds}) &&
					(!exists($clHash->{hmccu}{control}{chn}) || $clHash->{hmccu}{control}{chn} eq ''));
			if ($init_done && $clHash->{hmccu}{setDefaults} == 0) {
				my ($sc, $sd, $cc, $cd, $rsd, $rcd) = HMCCU_SetDefaultSCDatapoints ($ioHash, $clHash, undef, 1);
				HMCCU_Log ($clHash, 2, "Cannot set default state- and/or control datapoints")
					if ($rsd == 0 && $rcd == 0);
			}
		}
	}

	return undef;
}

######################################################################
# Set commands
######################################################################

sub HMCCUCHN_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt  = shift @$a // return 'No set command specified';
	my $lcopt = lc($opt);

	# Check device state
	return "Device state doesn't allow set commands"
		if (!defined($hash->{ccudevstate}) ||
			$hash->{ccudevstate} eq 'pending' || !defined($hash->{IODev}) ||
			($hash->{readonly} eq 'yes' && $lcopt !~ /^(\?|clear|config|defaults)$/) ||
			AttrVal ($name, 'disable', 0) == 1);

	my $ioHash = $hash->{IODev};
	my $ioName = $ioHash->{NAME};
	return ($opt eq '?' ? undef : 'Cannot perform set commands. CCU busy')
		if (HMCCU_IsRPCStateBlocking ($ioHash));

	# Build set command syntax
	my $syntax = 'clear defaults:reset,update,old,forceReset';
	
	# Command readingFilter depends on readable datapoints
	my ($add, $chn) = split(":", $hash->{ccuaddr});
	my @dpRList = ();
	my $dpRCount = HMCCU_GetValidParameters ($hash, $chn, 'VALUES', 5, \@dpRList);
	$syntax .= ' readingFilter:multiple-strict,'.join(',', @dpRList) if ($dpRCount > 0);

	# Commands only available in read/write mode
	if ($hash->{readonly} ne 'yes') {
		$syntax .= ' config';
		my $dpWCount = HMCCU_GetValidParameters ($hash, $chn, 'VALUES', 2);
		$syntax .= ' datapoint' if ($dpWCount > 0);
		my $addCmds = $hash->{hmccu}{cmdlist}{set} // '';
		$syntax .= " $addCmds" if ($addCmds ne '');
	}

	# Log commands
	HMCCU_Log ($hash, 3, "set $name $opt ".join (' ', @$a))
		if ($opt ne '?' && (HMCCU_IsFlag ($name, 'logCommand') || HMCCU_IsFlag ($ioName, 'logCommand')));
	
	if ($lcopt eq 'control') {
		return HMCCU_ExecuteSetControlCommand ($hash, $a, $h);
	}
	elsif ($lcopt eq 'datapoint') {
		return HMCCU_ExecuteSetDatapointCommand ($hash, $a, $h);
	}
	elsif (exists($hash->{hmccu}{roleCmds}{set}{$opt})) {
		return HMCCU_ExecuteRoleCommand ($ioHash, $hash, 'set', $opt, $a, $h);
	}
	elsif ($opt eq 'clear') {
		return HMCCU_ExecuteSetClearCommand ($hash, $a);
	}
	elsif ($lcopt =~ /^(config|values)$/) {
		return HMCCU_ExecuteSetParameterCommand ($ioHash, $hash, $lcopt, $a, $h);
	}
	elsif ($lcopt eq 'readingfilter') {
		my $filter = shift @$a // return HMCCU_SetError ($hash, "Usage: set $name readingFilter {datapointList}");
		$filter =~ s/,/\|/g;
		$filter = '^('.$filter.')$';
		return CommandAttr (undef, "$name ccureadingfilter $filter");
	}
	elsif ($lcopt eq 'defaults') {
		my $mode = shift @$a // 'update';
		return HMCCU_SetError ($hash, "Usage: get $name defaults [forceReset|old|reset|update]")
			if ($mode !~ /^(forceReset|reset|old|update)$/);
		my $rc = 0;
		my $retMsg = '';
		$hash->{hmccu}{setDefaults} = 1; # Make sure that readings are not refreshed after each set attribute command
		($rc, $retMsg) = HMCCU_SetDefaultAttributes ($hash, { mode => $mode, role => undef, roleChn => undef }) if ($mode ne 'old');
		if (!$rc) {
			$rc = HMCCU_SetDefaults ($hash);
			$retMsg .= $rc ? "\nSet version 4.3 attributes" : "\nNo version 4.3 default attributes found";
		}
		$retMsg = 'OK' if ($retMsg eq '');
		$hash->{hmccu}{setDefaults} = 0;
		HMCCU_RefreshReadings ($hash) if ($rc);
		return HMCCU_SetError ($hash, $retMsg);
	}
	elsif ($lcopt eq 'echo') {
		return HMCCU_RefToString ($h);
	}
	else {
		return "Unknown argument $opt choose one of $syntax";
	}
}

######################################################################
# Get commands
######################################################################

sub HMCCUCHN_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a // return 'No get command specified';
	my $lcopt = lc($opt);

	return undef if (!defined ($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' ||
		!defined ($hash->{IODev}) || AttrVal ($name, "disable", 0) == 1);

	my $ioHash = $hash->{IODev};
	my $ioName = $ioHash->{NAME};

	return $opt eq '?' ? undef : 'Cannot perform get command. CCU busy'
		if (HMCCU_IsRPCStateBlocking ($ioHash));

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	# Build set command syntax
	my $syntax = 'update config paramsetDesc:noArg deviceInfo:noArg values extValues metaData';
	
	# Command datapoint depends on readable datapoints
	my ($add, $chn) = split(":", $hash->{ccuaddr});
	my @dpRList;
	my $dpRCount = HMCCU_GetValidParameters ($hash, $chn, 'VALUES', 1, \@dpRList);   
	$syntax .= ' datapoint:'.join(",", @dpRList) if ($dpRCount > 0);
	
	# Additional device specific commands
	my $addCmds = $hash->{hmccu}{cmdlist}{get} // '';
	$syntax .= " $addCmds" if ($addCmds ne '');

	# Log commands
	HMCCU_Log ($hash, 3, "get $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($ioName, 'logCommand')); 

	if ($lcopt eq 'datapoint') {
		return HMCCU_ExecuteGetDatapointCommand ($hash, $a);
	}
	elsif ($lcopt eq 'deviceinfo') {
		my $extended = shift @$a;
		my ($devAddr, undef) = HMCCU_SplitChnAddr ($ccuaddr);
		return HMCCU_ExecuteGetDeviceInfoCommand ($ioHash, $hash, $devAddr, defined($extended) ? 1 : 0);
	}
	elsif ($lcopt =~ /^(config|values|update)$/) {
		my $filter = shift @$a;
		my ($devAddr, undef) = HMCCU_SplitChnAddr ($ccuaddr);
		my @addList = ($devAddr, "$devAddr:0", $ccuaddr);	
		my $result = HMCCU_ExecuteGetParameterCommand ($ioHash, $hash, $lcopt, \@addList, $filter);
		return HMCCU_SetError ($hash, "Can't get device description") if (!defined($result));
		return HMCCU_DisplayGetParameterResult ($ioHash, $hash, $result);
	}
	elsif ($lcopt eq 'extvalues') {
		my $filter = shift @$a;
		my $rc = HMCCU_ExecuteGetExtValuesCommand ($hash, $ccuaddr, $filter);
		return $rc < 0 ? HMCCU_SetError ($hash, $rc) : 'OK';
	}
	elsif ($lcopt eq 'paramsetdesc') {
		my $result = HMCCU_ParamsetDescToStr ($ioHash, $hash);
		return defined($result) ? $result : HMCCU_SetError ($hash, "Can't get device model");
	}
	elsif ($lcopt eq 'metadata') {
		my $filter = shift @$a;
		my ($rc, $result) = HMCCU_ExecuteGetMetaDataCommand ($ioHash, $hash, $filter);
		return $rc < 0 ? HMCCU_SetError ($hash, $rc, $result) : $result;
	}
	elsif (exists($hash->{hmccu}{roleCmds}{get}{$opt})) {
		return HMCCU_ExecuteRoleCommand ($ioHash, $hash, 'get', $opt, $a, $h);
	}
	else {
		return "Unknown argument $opt choose one of $syntax";
	}
}


1;

=pod
=item device
=item summary controls HMCCU client devices for Homematic CCU2/3 - FHEM integration
=begin html

<a name="HMCCUCHN"></a>
<h3>HMCCUCHN</h3>
<ul>
   The module implements Homematic CCU channels as client devices for HMCCU. A HMCCU I/O device must
   exist before a client device can be defined. If a CCU channel is not found, execute command
   'get ccuConfig' in I/O device. This will synchronize devices and channels between CCU
   and HMCCU.
   <br/><br/>
   <a name="HMCCUCHNdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCUCHN {&lt;channel-name&gt; | &lt;channel-address&gt;}
      [readonly] [<u>defaults</u>|noDefaults] [iodev=&lt;iodev-name&gt;]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. With option 'noDefaults'
      no default attributes will be set during interactive device definition. <br/>
      The define command accepts a CCU channel name or channel address as parameter.
      <br/><br/>
      Examples:<br/>
      <code>define window_living HMCCUCHN WIN-LIV-1 readonly</code><br/>
      <code>define temp_control HMCCUCHN BidCos-RF.LEQ1234567:1</code>
      <br/><br/>
      The interface part of a channel address is optional. Channel addresses can be found with command
	  'get deviceinfo &lt;CCU-DeviceName&gt;' executed in I/O device.<br/><br/>
	  Internals:<br/>
	  <ul>
	  	<li>ccuaddr: Address of channel in CCU</li>
		<li>ccudevstate: State of device in CCU (active/inactive/dead)</li>
		<li>ccuif: Interface of device</li>
	  	<li>ccuname: Name of channel in CCU</li>
		<li>ccurole: Role of channel</li>
		<li>ccusubtype: Homematic subtype of device (different from ccutype for HmIP devices)</li>
		<li>ccutype: Homematic type of device</li>
		<li>readonly: Indicates whether FHEM device is writeable</li>
		<li>receiver: List of peered devices with role 'receiver'. If no FHEM device exists for a receiver, the
		name of the CCU device is displayed preceeded by 'ccu:'</li> 
		<li>sender: List of peered devices with role 'sender'. If no FHEM device exists for a sender, the
		name of the CCU device is displayed preceeded by 'ccu:'</li> 
	  </ul>
   </ul>
   <br/>
   
   <a name="HMCCUCHNset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; armState {DISARMED|EXTSENS_ARMED|ALLSENS_ARMED|ALARM_BLOCKED}</b><br/>
	     [alarm siren] Set arm state.
	  </li><br/>
	  <li><b>set &lt;name&gt; auto</b><br/>
         [thermostat] Turn auto mode on.
	  </li><br/>
	  <li><b>set &lt;name&gt; boost {on|off}</b><br/>
         [thermostat] Turn boost mode on or off
	  </li><br/>
	  <li><b>set &lt;name&gt; calibrate {START|STOP}</b><br/>
		 [blind] Run calibration.
	  </li><br/>
      <li><b>set &lt;name&gt; clear [&lt;reading-exp&gt;|reset]</b><br/>
         Delete readings matching specified reading name expression. Default expression is '.*'.
         Readings 'state' and 'control' are not deleted. With option 'reset' all readings
         and all internally stored device parameter values are deleted.
      </li><br/>
	  <li><b>set &lt;name&gt; close</b><br/>
		[blind,door] Set level of a shutter or blind to 0%.
	  </li><br/>
	  <li><b>set &lt;name&gt; color &lt;color-name&gt;</b><br/>
	    [light] Set color of LED light.
      </li><br/>
	  <li><b>set &lt;name&gt; config [device|&lt;receiver&gt;] &lt;parameter&gt;=&lt;value&gt;[:&lt;type&gt;] [...]</b><br/>
         Set multiple config (parameter set MASTER) or link (parameter set LINKS) parameters.
         If neither 'device' nor <i>receiver</i> is specified, configuration parameters of
         current channel are set. With option 'device' configuration parameters of the device
         are set.<br/>
         If a <i>receiver</i> is specified, parameters will be set for the specified link.
         Parameter <i>receiver</i> is the name of a FHEM device of type HMCCUDEV or HMCCUCHN or
         a channel address or a CCU channel name. For FHEM devices of type HMCCUDEV the number 
         of the linked <i>channel</i> must be specified.<br/>
         Parameter <i>parameter</i> must be a valid configuration parameter.
         If <i>type</i> is not specified, it's taken from parameter set definition. If type 
         cannot be determined, the default <i>type</i> STRING is used.
         Valid types are STRING, BOOL, INTEGER, FLOAT, DOUBLE.<br>
		 If unit of <i>parameter</i> is 'minutes' (i.e. endtime in a week profile), value/time can
		 be specified in minutes after midnight or in format hh:mm (hh=hours, mm=minutes).<br/><br/>
         Example 1: Set device parameter AES<br/>
         <code>set myDev config device AES=1</code><br/>
         Example 2: Set channel parameters MIN and MAX with type definition<br/>
         <code>set myDev config MIN=0.5:FLOAT MAX=10.0:FLOAT</code><br/>
         Example 3: Set link parameter. DEV_PARTNER is a HMCCUDEV device, so channel number (3) is required<br/>
         <code>set myDev config DEV_PARTNER:3 MYPARAM=1</code>
      </li><br/>
      <li><b>set &lt;name&gt; control &lt;value&gt;</b><br/>
      	Set value of control datapoint. This command is available only on command line
      	for compatibility reasons. It should not be used any more.
      </li><br/>
      <li><b>set &lt;name&gt; datapoint [&lt;no&gt;:][&lt;channel&gt;.]&lt;datapoint&gt; &lt;{value|'oldval'}&gt; | [&lt;no&gt;:][&lt;channel&gt;.]&lt;datapoint&gt=&lt;value&gt; [...]</b><br/>
        Set datapoint values of a CCU channel. If value contains blank characters it must be
        enclosed in double quotes. This command is only available, if channel contains a writeable datapoint.<br/>
		By using parameter <i>no</i> one can specify the order in which datapoints are set (see 3rd example below).<br/>
		When using syntax <i>datapoint</i>=<i>value</i> with multiple datapoints always specify a <i>no</i> to ensure 
		that datapoints are set in the desired order.<br/>
		The special <i>value</i> 'oldval' will set the datapoint to its previous value. This can be used to realize a toggle function
		for each datapoint. Note: the previous value of a datapoint is not available at the first 'set datapoint' command after
		FHEM start.<br/><br/>
        Examples:<br/>
        <code>set temp_control datapoint SET_TEMPERATURE 21</code><br/>
        <code>set temp_control datapoint AUTO_MODE 1 SET_TEMPERATURE=21</code><br/>
		<code>set temp_control datapoint 2:AUTO_MODE=0 1:SET_TEMPERATURE=21</code>
      </li><br/>
      <li><b>set &lt;name&gt; defaults ['reset'|'forceReset'|'old'|'<u>update</u>']</b><br/>
   		Set default attributes for CCU device type. Default attributes are only available for
   		some device types and for some channels of a device type. With option 'reset' obsolete attributes
		are deleted if they are matching the default attributes of HMCCU 4.3. Attributes modified
		by the user will be kept.<br/>
		With option 'forceReset' all obsolete attributes will be deleted. The following attributes are
		obsolete in HMCCU 5.x:  'ccureadingname', 'ccuscaleval', 'eventMap', 'substexcl', 'webCmd', 'widgetOverride'.
		In addition 'statedatapoint', 'statechannel', 'controldatapoint' and 'controlchannel' are removed if HMCCU
		is able to detect these values automatically.<br/>
   		During update to version 5.x it's recommended to use option 'reset' or 'forceReset'. With option 'old'
		the attributes are set according to HMCCU 4.3 defaults mechanism.
      </li><br/>
      <li><b>set &lt;name&gt; down [&lt;value&gt;]</b><br/>
      	[dimmer, blind] Decrement value of datapoint LEVEL. This command is only available
      	if channel contains a datapoint LEVEL. Default for <i>value</i> is 20.
      </li><br/>
	  <li><b>set &lt;name&gt; manu [&lt;temperature&gt;]</b><br/>
	    [thermostat] Set manual mode. Default temperature is 20.
	  </li><br/>
	  <li><b>set &lt;name&gt; off</b><br/>
	  	[switch,thermostat,dimmer] Turn device off.
	  </li><br/>
	  <li><b>set &lt;name&gt; oldLevel</b><br/>
	    [dimmer, blind, jalousie, shutter] Set level to previous value.
	  </li><br/>
	  <li><b>set &lt;name&gt; on</b><br/>
	  	[switch,thermostat,dimmer] Turn device on.
	  </li><br/>
      <li><b>set &lt;name&gt; on-for-timer &lt;ontime&gt;</b><br/>
         [switch] Switch device on for specified number of seconds. This command is only available if
         channel contains a datapoint ON_TIME. Parameter <i>ontime</i> can be specified
         in seconds or in format HH:MM:SS<br/><br/>
         Example: Turn switch on for 300 seconds<br/>
         <code>set myswitch on-for-timer 300</code>
      </li><br/>
      <li><b>set &lt;name&gt; on-till &lt;timestamp&gt;</b><br/>
         [switch,dimmer] Switch device on until <i>timestamp</i>. Parameter <i>timestamp</i> can be a time in
         format HH:MM or HH:MM:SS. This command is only available if channel contains a datapoint
         ON_TIME. 
      </li><br/>
	  <li><b>set &lt;name&gt; open</b><br/>
		[blind,door] Set level of a shutter or blind to 100%.
	  </li><br/>
	  <li><b>set &lt;name&gt; party &lt;temperature&gt; &lt;start-time&gt; &lt;end-time&gt;</b><br/>
         [thermostat] Turn party mode on. Timestamps must be in format "YYYY_MM_DD HH:MM".
	  </li><br/>
      <li><b>set &lt;name&gt; pct &lt;value&gt; [&lt;ontime&gt; [&lt;ramptime&gt;]]</b><br/>
         [dimmer,blind] Set datapoint LEVEL of a channel to the specified <i>value</i>. Optionally a <i>ontime</i>
         and a <i>ramptime</i> (both in seconds) can be specified. This command is only available
         if channel contains at least a datapoint LEVEL and optionally datapoints ON_TIME and
         RAMP_TIME. The parameter <i>ontime</i> can be specified in seconds or as timestamp in
         format HH:MM or HH:MM:SS. If <i>ontime</i> is 0 it's ignored. This syntax can be used to
         modify the ramp time only.<br/><br/>
         Example: Turn dimmer on for 600 second. Increase light to 100% over 10 seconds<br>
         <code>set myswitch pct 100 600 10</code>
      </li><br/>
	  <li><b>set &lt;name&gt; pctSlats &lt;value&gt;</b><br/>
	  	[blind] Like command 'set pct', but changes the level of slats (if available).
	  </li><br/>
	  <li><b>set &lt;name&gt; press</b><br/>
	    [key] Submit a short key press.
	  </li><br/>
	  <li><b>set &lt;name&gt; pressLong</b><br/>
	    [key] Submit a long key press.
	  </li><br/>
	  <li><b>set &lt;name&gt; readingFilter &lt;datapoint-list&gt;</b><br/>
		Set attribute ccureadingfilter by selecting a list of datapoints. Parameter <i>datapoint-list</i>
		is a comma seperated list of datapoints.
	  </li><br/>
      <li><b>set &lt;name&gt; stop</b><br/>
      	[blind,door] Set datapoint STOP of a channel to true. This command is only available, if the
      	channel contains a datapoint STOP.
      </li><br/>
      <li><b>set &lt;name&gt; toggle</b><br/>
		[switch,dimmer,blind] Toggle state between values on/off or open/close.
      </li><br/>
      <li><b>set &lt;name&gt; up [&lt;value&gt;]</b><br/>
      	[blind,dimmer] Increment value of datapoint LEVEL. This command is only available
      	if channel contains a datapoint LEVEL. Default for <i>value</i> is 20.
      </li><br/>
      <li><b>set &lt;name&gt; values &lt;parameter&gt;=&lt;value&gt;[:&lt;type&gt;] [...]</b><br/>
      	Set multiple datapoint values (parameter set VALUES). Parameter <i>parameter</i>
      	must be a valid datapoint name. If <i>type</i> is not specified, it's taken from
         parameter set definition. The default <i>type</i> is STRING.
         Valid types are STRING, BOOL, INTEGER, FLOAT, DOUBLE.
      </li><br/>
	  <li><b>set &lt;name&gt; ventilate</b><br/>
	    [garage door] Set door position to ventilation.
	  </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; config [&lt;filter-expr&gt;]</b><br/>
		Get configuration parameters of device and channel. If <i>filter-expr</i> is specified,
		only parameters matching the expression are stored as readings.<br/>
		Values related to configuration or link parameters are stored as readings beginning
		with "R-" for MASTER parameter set and "L-" for LINK parameter set. 
		Prefixes "R-" and "L-" can be modified with attribute 'ccuReadingPrefix'. Whether parameters are
		stored as readings or not, can be controlled by setting the following flags in
		attribute ccuflags:<br/>
		<ul>
			<li>noReadings: Do not store any reading.</li>
			<li>showMasterReadings: Store configuration readings of parameter set 'MASTER' of current channel.</li>
			<li>showDeviceReadings: Store configuration readings of device and value readings of channel 0.</li>
			<li>showLinkReadings: Store readings of links.</li>
		</ul>
		If non of the flags is set, only readings belonging to parameter set VALUES (datapoints)
		are stored.
      </li><br/>
      <li><b>get &lt;name&gt; datapoint &lt;datapoint&gt;</b><br/>
        Get value of a CCU channel datapoint. Format of <i>datapoint</i> is ChannelNo.DatapointName.
		For HMCCUCHN devices the ChannelNo is not needed. This command is only available if a 
		readable datapoint exists.
      </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	This command has been removed in version 4.4. The default attributes are included in the
		output of command 'get deviceInfo'.
      </li><br/>
      <li><b>get &lt;name&gt; deviceInfo ['extended']</b><br/>
		Display information about device type and channels:<br/>
		<ul>
			<li>all channels and datapoints of device with datapoint values and types</li>
			<li>statedatapoint and controldatapoint</li>
			<li>device and channel description</li>
			<li>default attributes (if device is not supported by built in functionality)</li>
		</ul>
		The output of this command is helpful to gather information about new / not yet supported devices.
		Please add this information to your post in the FHEM forum, if you have a question about
		the integration of a new device. See also command 'get paramsetDesc'.
      </li><br/>
	  <li><b>get &lt;name&gt; extValues [&lt;filter-expr&gt;]</b><br/>
      	Update all readings for all parameters of parameter set VALUES (datapoints) and connected system
		variables by using CCU Rega (Homematic script). This command will also update system variables bound
		to the device.
		If <i>filter-expr</i> is specified, only datapoints matching the expression are stored as readings.
	  </li><br/>
	  <li><b>get &lt;name&gt; metaData [&lt;filter-expr&gt;]</b><br/>
	  	Read meta data for device or channel. If <i>filter-expr</i> is specified only meta data IDs matching
		the specified regular expression are stored as readings.<br/>
		Example: get myDev metaData energy.*
	  </li><br/>
      <li><b>get &lt;name&gt; paramsetDesc</b><br/>
		Display description of parameter sets of channel and device. The output of this command
		is helpful to gather information about new / not yet supported devices. Please add this
		information to your post in the FHEM forum, if you have a question about
		the integration of a new device. See also command 'get deviceInfo'.
      </li><br/>
      <li><b>get &lt;name&gt; update [&lt;filter-expr&gt;]</b><br/>
        Update all readings for all parameters of all parameter sets (MASTER, LINK, VALUES).
		If <i>filter-expr</i> is specified, only parameters matching the expression are stored as readings.
      </li><br/>
      <li><b>get &lt;name&gt; values [&lt;filter-expr&gt;]</b><br/>
      	Update all readings for all parameters of parameter set VALUES (datapoints). Hint: This command won't 
		update system variables bound to the device. These variables can be read by using command 'get extValues'.
		If <i>filter-expr</i> is specified, only parameters matching the expression are stored as readings.
      </li><br/>
      <li><b>get &lt;name&gt; week-program [&lt;program-number&gt;|<u>all</u>]</b><br/>
      	Display week programs. This command is only available if a device supports week programs.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNattr"></a>
   <b>Attributes</b><br/><br/>
   <ul>
      To reduce the amount of events it's recommended to set attribute 'event-on-change-reading'
      to '.*'.
      <br/><br/>
      <a name="calculate"></a>
      <li><b>ccucalculate &lt;value-type&gt;:&lt;reading&gt;[:&lt;dp-list&gt;[;...]</b><br/>
      	Calculate special values like dewpoint based on datapoints specified in
      	<i>dp-list</i>. The result is stored in <i>reading</i>.<br/>
      	The following <i>value-types</i> are supported:<br/>
      	dewpoint = calculate dewpoint, <i>dp-list</i> = &lt;temperature&gt;,&lt;humidity&gt;<br/>
      	abshumidity = calculate absolute humidity, <i>dp-list</i> = &lt;temperature&gt;,&lt;humidity&gt;<br/>
      	equ = compare datapoint values. Result is "n/a" if values are not equal.<br/>
      	inc = increment datapoint value considering reset of datapoint, <i>dp-list</i> = &lt;counter-datapoint&gt;<br/>
      	min = calculate minimum continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	max = calculate maximum continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	sum = calculate sum continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	avg = calculate average continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	Example:<br/>
      	<code>dewpoint:taupunkt:1.TEMPERATURE,1.HUMIDITY</code>
      </li><br/>
      <a name="ccuflags"></a>
      <li><b>ccuflags {ackState, logCommand, noBoundsChecking, noReadings, hideStdReadings, replaceStdReadings, showDeviceReadings, showLinkReadings, showConfigReadings, trace}</b><br/>
      	Control behaviour of device:<br/>
      	ackState: Acknowledge command execution by setting STATE to error or success.<br/>
		hideStdReadings: Do not show standard readings like 'measured-temp'<br/>
		replaceStdReadings: Replace original readings like 'ACTUAL_TEMPERATURE' by standard readings like 'measured-temp' instead of adding standard readings<br/>
      	logCommand: Write get and set commands to FHEM log with verbose level 3.<br/>
		noBoundsChecking: Datapoint values are not checked for min/max boundaries<br/>
			noAutoSubstitute - Do not substitute reading values by names. This local flag affects only the current device. You can turn off all substitutes by setting this flag in I/O device.<br/>
      	noReadings: Do not update readings<br/>
		simulate: Do not execute set datapoint commands. Use this flag together with 'trace'<br/>
      	showDeviceReadings: Show readings of device and channel 0.<br/>
      	showLinkReadings: Show link readings.<br/>
      	showMasterReadings: Show configuration readings.<br/>
      	trace: Write log file information for operations related to this device.
      </li><br/>
      <a name="ccuget"></a>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value'
         because each request is sent to the device. With method 'Value' only CCU is queried.
         Default is 'Value'.
      </li><br/>
      <a name="ccureadingfilter"></a>
      <li><b>ccureadingfilter &lt;filter-rule[;...]&gt;</b><br/>
         Only datapoints matching specified expression <i>RegExp</i> are stored as readings.<br/>
         Syntax for <i>filter-rule</i> is either:<br/>
         [N:]{&lt;channel-name-expr&gt;}!RegExp&gt; or:<br/>
         [N:][&lt;channel-number&gt;[,&lt;channel-number&gt;].]&lt;RegExp&gt;<br/>
         If <i>channel-name-expr</i> or <i>channel-number</i> is specified the following rule 
         applies only to the specified or matching channel(s).<br/>
         If a rule starts with 'N:' the filter is negated which means that a reading is stored if rule doesn't match.<br/>
		 If you like to suppress the standard device readings like 'battery', a negated filter rule for the 
		 corresponding datapoint must be specified (see example for LOW_BAT/battery below)<br/><br/>
         Examples:<br/>
         <code>
		 # Show readings for all datapoints<br/>
         attr mydev ccureadingfilter .*<br/>
		 # Show readings for matching datapoints of channel 1 and matching datapoints of all channels (2nd rule)<br/>
         attr mydev ccureadingfilter 1.(^ACTUAL|CONTROL|^SET_TEMP);(^WINDOW_OPEN|^VALVE)<br/>
		 # Show reading datapoint LEVEL of channel MyBlindChannel<br/>
         attr mydev ccureadingfilter MyBlindChannel!^LEVEL$<br/>
		 # Show every reading except LEVEL
		 attr mydev ccureadingfilter N:LEVEL<br/>
         </code>
      </li><br/>
      <a name="ccureadingformat"></a>
      <li><b>ccureadingformat {address[lc] | name[lc] | datapoint[lc] | &lt;format-string&gt;}</b><br/>
         Set format of reading names. Default for virtual device groups and HMCCUCHN devices is 'name'.
         The default for HMCCUDEV is 'datapoint'. If set to 'address' format of reading names
         is channel-address.datapoint. If set to 'name' format of reading names is
         channel-name.datapoint. If set to 'datapoint' format is channel-number.datapoint.
         For HMCCUCHN devices the channel part is ignored. With suffix 'lc' reading names are converted
         to lowercase. The reading format can also contain format specifiers %a (address), 
         %n (name) and %c (channel). Use %A, %N, %C for conversion to upper case. The readings will
		 be refreshed automatically if this attribute is changed. The default value for this
		 attribute can be defined by setting attribute ccudef-readingformat in the I/O device.<br/><br/>
         Example:<br/>
         <code>
         attr mydev ccureadingformat HM_%c_%N
         </code>
      </li><br/>
      <a name="ccureadingname"></a>
      <li><b>ccureadingname &lt;old-readingname-expr&gt;:[[+]&lt;new-readingname&gt;[,...]][;...]</b><br/>
         Set alternative or additional reading names or group readings. Only part of old reading
         name matching <i>old-readingname-expr</i> is substituted by <i>new-readingname</i>. If no 
		 <i>new-readingname</i> is specified, default readings like battery can be suppressed.
         If <i>new-readingname</i> is preceded by '+' an additional reading is created. If 
         <i>old-readingname-expr</i> matches more than one reading the values of these readings
         are stored in one reading. This makes sense only in some cases, i.e. if a device has
         several pressed_short datapoints and a reading should contain a value if any button
         is pressed.<br/><br/>
         Examples:<br/>
         <code>
         # Rename readings 0.LOWBAT and 0.LOW_BAT as battery<br/>
         attr mydev ccureadingname 0.(LOWBAT|LOW_BAT):battery<br/>
		 # Suppress battery reading (no new reading specified after ':')<br/>
		 attr mydev ccureadingname battery:<br/>
         # Add reading battery as a copy of readings LOWBAT and LOW_BAT (HMCCU does this by default).<br/>
         # Rename reading 4.SET_TEMPERATURE as desired-temp<br/>
         attr mydev ccureadingname 1.SET_TEMPERATURE:desired-temp<br/>
         # Store values of readings n.PRESS_SHORT in new reading pressed.<br/>
         # Value of pressed is 1/true if any button is pressed<br/>
         attr mydev ccureadingname [1-4].PRESSED_SHORT:+pressed
         </code>
      </li><br/>
      <a name="ccuReadingPrefix"></a>
      <li><b>ccuReadingPrefix &lt;paramset&gt;[:&lt;prefix&gt;][,...]</b><br/>
      	Set reading name prefix for parameter sets. Default values for parameter sets are:<br/>
			VALUES (state values): No prefix<br/>
			MASTER (configuration parameters): 'R-'<br/>
			LINK (links parameters): 'L-'<br/>
			PEER (peering parameters): 'P-'<br/>
		To hide prefix do not specify <i>prefix</i>.
      </li><br/>
      <a name="ccuscaleval"></a>
      <li><b>ccuscaleval &lt;[channelno.]datapoint&gt;:&lt;factor&gt;[,...]</b><br/>
      <b>ccuscaleval &lt;[!][channelno.]datapoint&gt;:&lt;min&gt;:&lt;max&gt;:&lt;minn&gt;:&lt;maxn&gt;[,...]
      </b><br/>
         Scale, spread, shift and optionally reverse values before executing set datapoint commands
         or after executing get datapoint commands / before storing values in readings.<br/>
         If first syntax is used during get the value read from CCU is devided by <i>factor</i>.
         During set the value is multiplied by factor.<br/>
         With second syntax one must specify the interval in CCU (<i>min,max</i>) and the interval
         in FHEM (<i>minn, maxn</i>). The scaling factor is calculated automatically. If parameter
         <i>datapoint</i> starts with a '!' the resulting value is reversed.
         <br/><br/>
         Example: Scale values of datapoint LEVEL for blind actor and reverse values<br/>
         <code>
         attr myblind ccuscale !LEVEL:0:1:0:100
         </code>
      </li><br/>
      <a name="ccuSetOnChange"></a>
      <li><b>ccuSetOnChange &lt;expression&gt;</b><br/>
      	Check if datapoint value will be changed by set command before changing datapoint value.
      	This attribute can reduce the traffic between CCU and devices. It presumes that datapoint
      	state in CCU is current.
      </li><br/>
      <li><b>ccuverify {<u>0</u> | 1 | 2}</b><br/>
         If set to 1 a datapoint is read for verification after set operation. If set to 2 the
         corresponding reading will be set to the new value directly after setting a datapoint
         in CCU without any verification.
      </li><br/>
      <a name="controldatapoint"></a>
      <li><b>controldatapoint &lt;datapoint&gt;</b><br/>
         Set datapoint for device control by commands 'set control' and 'set toggle'.
         This attribute must be set if control datapoint cannot be detected automatically. 
      </li><br/>
	  <a name="devStateFlags"></a>
	  <li><b>devStateFlags &lt;datapoint&gt;:&lt;value-regexp&gt;:&lt;flag&gt; [...]</b><br/>
	     Define flags depending on datapoint values which should appear in reading 'devstate'. All specified
		 datapoints must be readable or updated by CCU events.<br/>
		 Example: Add a flag 'unreachable' representing datapoint 0.UNREACH to reading 'devstate' (this will
		 override the default setting for '0.UNREACH'):<br/>
		 attr myDev devStateFlags 0.UNREACH:0|true:unreachable<br/>
		 By default the following flags exists:<br/>
		 0.CONFIG_PENDING:cfgPending<br/>
		 0.DEVICE_IN_BOOTLOADER:boot<br/>
		 0.UNREACH:unreach<br/>
		 0.STICKY_UNREACH:stickyUnreach<br/>
		 0.UPDATE_PENDING:updPending<br/>
		 0.SABOTAGE:sabotage<br/>
		 0.ERROR_SABOTAGE:sabotage<br/>
	  </li><br/>
      <a name="disable"></a>
      <li><b>disable {<u>0</u> | 1}</b><br/>
      	Disable client device.
      </li><br/>
      <a name="hmstatevals"></a>
		<li><b>hmstatevals &lt;subst-rule&gt;[;...]</b><br/>
         Define building rules and substitutions for reading hmstate. Syntax of <i>subst-rule</i>
         is<br/>
         [=&lt;reading&gt;;]&lt;datapoint-expr&gt;!&lt;{#n1-m1|regexp}&gt;:&lt;text&gt;[,...]
         <br/><br/>
         The syntax is almost the same as of attribute 'substitute', except there's no channel
         specification possible for datapoint and parameter <i>datapoint-expr</i> is a regular
         expression.<br/>
         The value of the I/O device attribute 'ccudef-hmstatevals' is appended to the value of
         this attribute. The default value of 'ccudef-hmstatevals' is
         '^UNREACH!(1|true):unreachable;LOW_?BAT!(1|true):warn_battery'.
         Normally one should not specify a substitution rule for the "good" value of an error
         datapoint (i.e. 0 for UNREACH). If none of the rules is matching, reading 'hmstate' is set
         to value of reading 'state'.<br/>
         Parameter <i>text</i> can contain variables in format ${<i>varname</i>}. The variable
         $value is substituted by the original datapoint value. All other variables must match
         with a valid datapoint name or a combination of channel number and datapoint name
         seperated by a '.'.<br/>
         Optionally the name of the HomeMatic state reading can be specified at the beginning of
         the attribute in format =&lt;reading&gt;;. The default reading name is 'hmstate'.
      </li><br/>
	  <a name="statedatapoint"></a>
      <li><b>statedatapoint &lt;datapoint&gt;</b><br/>
         Set datapoint used for displaying device state. This attribute must be set, if 
         state datapoint cannot be detected automatically.
      </li><br/>
      <a name="statevals"></a>
      <li><b>statevals &lt;new-command&gt;:&lt;control-datapoint-value&gt;[,...]</b><br/>
         Define set commands for control datapoint. This attribute should only be used if the device
		 type is not recognized by HMCCU. Using this attribute for automatically detected devices
		 could lead to problems!
         <br/><br/>
         Example: controldatapoint of a device is STATE. Device is not recognized by HMCCU:<br/>
         <code>
		 # Define 2 new commands on and off representing the possible states of STATE:<br/>
         attr my_switch statevals on:true,off:false<br/>
		 # After attr the commands on and off are available:<br/>
         set my_switch on<br/>
		 set my_switch off
         </code>
      </li><br/>
      <a name="stripnumber"></a>
      <li><b>stripnumber [&lt;datapoint-expr&gt;!]{0|1|2|-n|%fmt}[;...]</b><br/>
      	Remove trailing digits or zeroes from floating point numbers, round or format
      	numbers. If attribute is negative (-0 is valid) floating point values are rounded
      	to the specified number of digits before they are stored in readings. The meaning of
      	values 0,1,2 is:<br/>
      	0 = Floating point numbers are stored as integer.<br/>
      	1 = Trailing zeros are stripped from floating point numbers except one digit.<br/>
   		2 = All trailing zeros are stripped from floating point numbers.<br/>
   		With %fmt one can specify any valid sprintf() format string.<br/>
   		If <i>datapoint-expr</i> is specified the formatting applies only to datapoints 
   		matching the regular expression.<br/>
   		Example:<br>
   		<code>
   		attr myDev stripnumber TEMPERATURE!%.2f degree
   		</code>
      </li><br/>
      <a name="substexcl"></a>
      <li><b>substexcl &lt;reading-expr&gt;</b><br/>
      	Exclude values of readings matching <i>reading-expr</i> from substitution. This is helpful
      	for reading 'control' if the reading is used for a slider widget and the corresponding
      	datapoint is assigned to attribute statedatapoint and controldatapoint.
      </li><br/>
      <a name="substitute"></a>
      <li><b>substitute &lt;subst-rule&gt;[;...]</b><br/>
         Define substitutions for datapoint/reading values. This attribute is helpful / necessary if
		 a device is not automatically detected by HMCCU.<br/>
		 Syntax of <i>subst-rule</i> is<br/><br/>
         [[&lt;type&gt;:][&lt;channelno&gt;.]&lt;datapoint&gt;[,...]!]&lt;{#n1-m1|regexp}&gt;:&lt;text&gt;[,...]
         <br/><br/>
         Parameter <i>type</i> is a valid channel type/role, i.e. "SHUTTER_CONTACT".
         Parameter <i>text</i> can contain variables in format ${<i>varname</i>}. The variable 
         ${value} is
         substituted by the original datapoint value. All other variables must match with a valid
         datapoint name or a combination of channel number and datapoint name seperated by a '.'.
         <br/><br/>
         Example: Substitute the value of datapoint TEMPERATURE by the string 
         'T=<i>val</i> deg' and append current value of datapoint 1.HUMIDITY<br/>
         <code>
         attr my_weather substitute TEMPERATURE!.+:T=${value} deg H=${1.HUMIDITY}%
         </code><br/><br/>
         If rule expression starts with a hash sign a numeric datapoint value is substituted if
         it fits in the number range n &lt;= value &lt;= m.
         <br/><br/>
         Example: Interpret LEVEL values 100 and 0 of dimmer as "on" and "off"<br/>
         <code>
         attr my_dim substitute LEVEL!#0-0:off,#1-100:on
         </code>
      </li><br/>
      <a name="traceFilter"></a>
      <li><b>traceFilter &lt;filter-expr&gt;</b><br/>
      	Trace only function calls which are maching <i>filter-expr</i>.
      </li><br/>
   </ul>
</ul>

=end html
=cut


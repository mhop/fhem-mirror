######################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id: 88_HMCCUDEV.pm 18552 2019-02-10 11:52:28Z zap $
#
#  Version 4.4.047
#
#  (c) 2021 zap (zap01 <at> t-online <dot> de)
#
######################################################################
#  Client device for Homematic devices.
#  Requires module 88_HMCCU.pm
######################################################################

package main;

use strict;
use warnings;
# use Data::Dumper;
use SetExtensions;

require "$attr{global}{modpath}/FHEM/88_HMCCU.pm";

sub HMCCUDEV_Initialize ($);
sub HMCCUDEV_Define ($@);
sub HMCCUDEV_InitDevice ($$);
sub HMCCUDEV_Undef ($$);
sub HMCCUDEV_Rename ($$);
sub HMCCUDEV_Set ($@);
sub HMCCUDEV_Get ($@);
sub HMCCUDEV_Attr ($@);

######################################################################
# Initialize module
######################################################################

sub HMCCUDEV_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn}    = 'HMCCUDEV_Define';
	$hash->{UndefFn}  = 'HMCCUDEV_Undef';
	$hash->{RenameFn} = 'HMCCUDEV_Rename';
	$hash->{SetFn}    = 'HMCCUDEV_Set';
	$hash->{GetFn}    = 'HMCCUDEV_Get';
	$hash->{AttrFn}   = 'HMCCUDEV_Attr';
	$hash->{parseParams} = 1;

	$hash->{AttrList} = 'IODev ccuaggregate:textField-long ccucalculate:textField-long '. 
		'ccuflags:multiple-strict,ackState,logCommand,noReadings,trace,showMasterReadings,showLinkReadings,showDeviceReadings,showServiceReadings '.
		'ccureadingfilter:textField-long '.
		'ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc '.
		'ccureadingname:textField-long ccuSetOnChange ccuReadingPrefix '.
		'ccuget:State,Value ccuscaleval ccuverify:0,1,2 disable:0,1 '.
		'hmstatevals:textField-long statevals substexcl substitute:textField-long statechannel statedatapoint '.
		'controlchannel controldatapoint stripnumber peer:textField-long traceFilter '.
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCUDEV_Define ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	
	my $usage = "Usage: define $name HMCCUDEV device [control-channel] ".
		"['readonly'] ['noDefaults'|'defaults'] [forceDev] [iodev={iodev-name}]";
	return $usage if (scalar(@$a) < 3);
	
	my @errmsg = (
		"OK",
		"Invalid or unknown CCU device name or address",
		"Can't assign I/O device",
		"No devices in group",
		"No matching CCU devices found",
		"Type of virtual device not defined",
		"Device type not found",
		"Too many virtual devices",
		"Use HMCCUCHN instead"
	);
	
	my @warnmsg = (
		"OK",
		"Control channel ambiguous. You can change the default control channel in device definition or with attribute controldatapoint",
		"Device type not known by HMCCU. Please set control and/or state channel with attributes controldatapoint and statedatapoint"
	);

	my ($devname, $devtype, $devspec) = splice (@$a, 0, 3);
	my $ioHash = undef;

	# Handle some legacy options
	return 'Virtual devices are no longer supported. Use FHEM built in features like readingsgroup or structure'
		if ($devspec eq 'virtual');
	HMCCU_Log ($hash, 2, "Found old device definition syntax using group or groupexp. Group options will be ignored in furture versions.")
		if (exists($h->{group}) || exists($h->{groupexp}));

	# Store some definitions for delayed initialization
	$hash->{readonly} = 'no';
	$hash->{hmccu}{devspec}     = $devspec;
	$hash->{hmccu}{groupexp}    = $h->{groupexp} if (exists ($h->{groupexp}));
	$hash->{hmccu}{group}       = $h->{group} if (exists ($h->{group}));
	$hash->{hmccu}{nodefaults}  = $init_done ? 0 : 1;
	$hash->{hmccu}{semDefaults} = 0;
	$hash->{hmccu}{forcedev}    = 0;
	
	# Parse optional command line parameters
	foreach my $arg (@$a) {
		if    (lc($arg) eq 'readonly')                 { $hash->{readonly} = 'yes'; }
		elsif (lc($arg) eq 'nodefaults' && $init_done) { $hash->{hmccu}{nodefaults} = 1; }
		elsif (lc($arg) eq 'defaults' && $init_done)   { $hash->{hmccu}{nodefaults} = 0; }
		elsif (lc($arg) eq 'forcedev')                 { $hash->{hmccu}{forcedev} = 1; }
		elsif ($arg =~ /^[0-9]+$/)                     { $attr{$name}{controlchannel} = $arg; }
		else                                           { return $usage; }
	}
	
	# IO device can be set by command line parameter iodev, otherwise try to detect IO device
	if (exists($h->{iodev})) {
		return "IO device $h->{iodev} does not exist" if (!exists($defs{$h->{iodev}}));
		return "Type of device $h->{iodev} is not HMCCU" if ($defs{$h->{iodev}}->{TYPE} ne 'HMCCU');
		$ioHash = $defs{$h->{iodev}};
	}
	else {
		# The following call will fail for non virtual devices during FHEM start if CCU is not ready
		$ioHash = $devspec eq 'virtual' ? HMCCU_GetHash (0) : HMCCU_FindIODevice ($devspec);
	}

	if ($init_done) {
		# Interactive define command while CCU not ready
		if (!defined($ioHash)) {
			my ($ccuactive, $ccuinactive) = HMCCU_IODeviceStates ();
			return $ccuinactive > 0 ? 'CCU and/or IO device not ready. Please try again later' :
				'Cannot detect IO device';
		}
	}
	else {
		# CCU not ready during FHEM start
		if (!defined($ioHash) || $ioHash->{ccustate} ne 'active') {
			HMCCU_Log ($hash, 3, 'Cannot detect IO device, maybe CCU not ready. Trying later ...');
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}

	# Initialize FHEM device, set IO device
	my $rc = HMCCUDEV_InitDevice ($ioHash, $hash);
	if (HMCCU_IsIntNum ($rc)) {
		return $errmsg[$rc] if ($rc > 0 && $rc < scalar(@errmsg));
		HMCCU_LogDisplay ($hash, 2, $warnmsg[-$rc]) if ($init_done && $rc < 0 && -$rc < scalar(@warnmsg));
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
# 3 = No devices in group
# 4 = No matching CCU devices found
# 5 = Type of virtual device not defined
# 6 = Device type not found
# 7 = Too many virtual devices
# -1 = Control channel must be specified
######################################################################

sub HMCCUDEV_InitDevice ($$)
{
	my ($ioHash, $devHash) = @_;
	my $name = $devHash->{NAME};
	my $devspec = $devHash->{hmccu}{devspec};
	my $gdcount = 0;
	my $gdname = $devspec;

	# Check if device is valid
	return 1 if (!HMCCU_IsValidDevice ($ioHash, $devspec, 7));

	my ($di, $da, $dn, $dt, $dc) = HMCCU_GetCCUDeviceParam ($ioHash, $devspec);
	return 1 if (!defined($da));

	$gdname = $dn;
	$devHash->{ccuif}           = $di;
	$devHash->{ccuaddr}         = $da;
	$devHash->{ccuname}         = $dn;
	$devHash->{ccutype}         = $dt;
	$devHash->{hmccu}{channels} = $dc;

	# Inform HMCCU device about client device
	return 2 if (!HMCCU_AssignIODevice ($devHash, $ioHash->{NAME}));

	$devHash->{ccudevstate} = 'active';

	if ($init_done) {
		# Initialize user attributes
		my $detect = HMCCU_DetectDevice ($ioHash, $da, $di);
		return "Specify option 'forceDev' for HMCCUDEV or use HMCCUCHN instead (recommended). Command: define $name HMCCUCHN $detect->{defAdd}"
			if (defined($detect) && $detect->{defMod} eq 'HMCCUCHN' && $devHash->{hmccu}{forcedev} == 0);

		# Interactive device definition
		HMCCU_SetSCAttributes ($ioHash, $devHash, $detect);
		HMCCU_AddDevice ($ioHash, $di, $da, $devHash->{NAME});
		HMCCU_UpdateDevice ($ioHash, $devHash);
		HMCCU_UpdateDeviceRoles ($ioHash, $devHash);

		return -2 if (!defined($detect) || $detect->{level} == 0);   # Device not detected

		if (!HMCCU_SetDefaultSCDatapoints ($ioHash, $devHash, $detect)) {
			HMCCU_Log ($devHash, 2, "Cannot set default state- and control datapoints");
		}

		HMCCU_SetInitialAttributes ($ioHash, $name);

		if (!exists($devHash->{hmccu}{nodefaults}) || $devHash->{hmccu}{nodefaults} == 0) {
			my $chn = $detect->{defCCh} != -1 ? $detect->{defCCh} : $detect->{defSCh};
			if (!HMCCU_SetDefaultAttributes ($devHash, {
				mode => 'update', role => undef, roleChn => $chn,
			})) {
				HMCCU_Log ($devHash, 2, "No role attributes found for channel $chn");
				HMCCU_SetDefaults ($devHash);
			}
		}

		HMCCU_GetUpdate ($devHash, $da, 'Value');

		return -1 if ($detect->{level} == 2);	# More than 1 control channel
	}
	
	# Parse group options
	if ($devHash->{ccuif} eq 'VirtualDevices') {
		my @devlist = ();
		if (exists ($devHash->{hmccu}{groupexp})) {
			# Group devices specified by name expression
			$gdcount = HMCCU_GetMatchingDevices ($ioHash, $devHash->{hmccu}{groupexp}, 'dev', \@devlist);
			return 4 if ($gdcount == 0);
		}
		elsif (exists ($devHash->{hmccu}{group})) {
			# Group devices specified by comma separated name list
			my @gdevlist = split (',', $devHash->{hmccu}{group});
			$devHash->{ccugroup} = '' if (scalar(@gdevlist) > 0);
			foreach my $gd (@gdevlist) {
				return 1 if (!HMCCU_IsValidDevice ($ioHash, $gd, 7));
				my ($gda, $gdc) = HMCCU_GetAddress ($ioHash, $gd);
				push @devlist, $gdc eq '' ? "$gda:$gdc" : $gda;
				$gdcount++;
			}
		}
		else {
			# Group specified by CCU virtual group name
			@devlist = HMCCU_GetGroupMembers ($ioHash, $gdname);
			$gdcount = scalar (@devlist);
		}

		return 3 if ($gdcount == 0);
		
		$devHash->{ccugroup} = join (',', @devlist);
	}

	return 0;
}

######################################################################
# Delete device
######################################################################

sub HMCCUDEV_Undef ($$)
{
	my ($hash, $arg) = @_;

	if ($hash->{IODev}) {
		HMCCU_RemoveDevice ($hash->{IODev}, $hash->{ccuif}, $hash->{ccuaddr}, $hash->{NAME});
	}
	
	return undef;
}

######################################################################
# Rename device
######################################################################

sub HMCCUDEV_Rename ($$)
{
	my ($newName, $oldName) = @_;
	
	my $clHash = $defs{$newName};
	my $ioHash = defined($clHash) ? $clHash->{IODev} : undef;
	
	HMCCU_RenameDevice ($ioHash, $clHash, $oldName);
}

######################################################################
# Set attribute
######################################################################

sub HMCCUDEV_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $clHash = $defs{$name};
	my $ioHash = HMCCU_GetHash ($clHash);

	if ($cmd eq 'set') {
		return "Missing value of attribute $attrname" if (!defined($attrval));
		if ($attrname eq 'IODev') {
			$clHash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq 'statevals') {
			return "Device is read only" if ($clHash->{readonly} eq 'yes');
		}
		elsif ($attrname =~ /^(state|control)(channel|datapoint)$/) {
			my $chn = $attrval;
			if ($attrname eq 'statedatapoint' || $attrname eq 'controldatapoint') {
				if ($attrval =~ /^([0-9]{1,2})\.(.+)$/) {
					$chn = $1;
				}
				else {
					return "Attribute value must be in format channel.datapoint";
				}
			}
			else {
				return "Attribute value must be a valid channel number" if (!HMCCU_IsIntNum ($attrval));
				$chn = $attrval;
			}

			my $role = HMCCU_GetChannelRole ($clHash, $chn);
			return "Invalid value $attrval" if (!HMCCU_SetSCDatapoints ($clHash, $attrname, $attrval, $role));
			if ($init_done && exists($clHash->{hmccu}{control}{chn}) && $clHash->{hmccu}{control}{chn} ne '') {
				HMCCU_UpdateRoleCommands ($ioHash, $clHash, $clHash->{hmccu}{control}{chn});
				HMCCU_UpdateAdditionalCommands ($ioHash, $clHash, $clHash->{hmccu}{control}{chn}, $clHash->{hmccu}{control}{dpt})
					if (exists($clHash->{hmccu}{control}{dpt}) && $clHash->{hmccu}{control}{dpt} ne '');
			}
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname =~ /^(state|control)(channel|datapoint)$/) {
			# Reset value
			HMCCU_SetSCDatapoints ($clHash, $attrname);
			delete $clHash->{hmccu}{roleCmds}
				if (exists($clHash->{hmccu}{roleCmds}) &&
					(!exists($clHash->{hmccu}{control}{chn}) || $clHash->{hmccu}{control}{chn} eq ''));
			if ($init_done) {
				if (!HMCCU_SetDefaultSCDatapoints ($ioHash, $clHash)) {
					HMCCU_Log ($clHash, 2, "Cannot set default state- and control datapoints");
				}
			}
		}
	}
	
	return;
}

######################################################################
# Set commands
######################################################################

sub HMCCUDEV_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a // return 'No set command specified';
	my $lcopt = lc($opt);

	# Check device state
	return "Device state doesn't allow set commands"
		if (!defined($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' || !defined($hash->{IODev}) ||
			($hash->{readonly} eq 'yes' && $opt !~ /^(\?|clear|config|defaults)$/) || 
			AttrVal ($name, 'disable', 0) == 1);

	my $ioHash = $hash->{IODev};
	my $ioName = $ioHash->{NAME};
	return ($opt eq '?' ? undef : 'Cannot perform set commands. CCU busy')
		if (HMCCU_IsRPCStateBlocking ($ioHash));

	# Build set command syntax
	my $syntax = 'clear defaults:reset,update';
	
	# Command readingFilter depends on readable datapoints
	my @dpRList = ();
	my $dpRCount = HMCCU_GetValidDatapoints ($hash, $hash->{ccutype}, -1, 5, \@dpRList);
	$syntax .= ' readingFilter:multiple-strict,'.join(',', @dpRList) if ($dpRCount > 0);
	
	# Commands only available in read/write mode
	if ($hash->{readonly} ne 'yes') {
		$syntax .= ' config';
		my $dpWCount = HMCCU_GetValidDatapoints ($hash, $hash->{ccutype}, -1, 2);
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
	elsif ($lcopt eq 'toggle') {
		return HMCCU_ExecuteToggleCommand ($hash);
	}
	elsif (exists($hash->{hmccu}{roleCmds}{set}{$opt})) {
		return HMCCU_ExecuteRoleCommand ($ioHash, $hash, 'set', $opt, $a, $h);
	}
	elsif ($lcopt eq 'clear') {
		return HMCCU_ExecuteSetClearCommand ($hash, $a);
	}
	elsif ($lcopt =~ /^(config|values)$/) {
		return HMCCU_ExecuteSetParameterCommand ($ioHash, $hash, $opt, $a, $h);
	}
	elsif ($lcopt =~ 'readingfilter') {
		my $filter = shift @$a // return HMCCU_SetError ($hash, "Usage: set $name readingFilter {datapointList}");
		$filter = join(';', map { (my $f = $_) =~ s/\.(.+)/\.\^$1\$/; $f } split(',', $filter));
		return CommandAttr (undef, "$name ccureadingfilter $filter");
	}
	elsif ($lcopt eq 'defaults') {
		my $mode = shift @$a // 'update';
		my $rc = HMCCU_SetDefaultAttributes ($hash, { mode => $mode, role => undef, roleChn => undef });
		$rc = HMCCU_SetDefaults ($hash) if (!$rc);
		HMCCU_RefreshReadings ($hash) if ($rc);
		return HMCCU_SetError ($hash, $rc == 0 ? 'No default attributes found' : 'OK');
	}
	else {
		return "Unknown argument $opt choose one of $syntax";
	}
}

######################################################################
# Get commands
######################################################################

sub HMCCUDEV_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a // return 'No get command specified';
	my $lcopt = lc($opt);
	
	# Get I/O device
	return "Device state doesn't allow set commands"
		if (!defined ($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' ||
			!defined ($hash->{IODev}) || AttrVal ($name, "disable", 0) == 1);
	my $ioHash = $hash->{IODev};
	my $ioName = $ioHash->{NAME};

	# Check if CCU is busy
	return $opt eq '?' ? undef : 'Cannot perform get commands. CCU busy'
		if (HMCCU_IsRPCStateBlocking ($ioHash));
	
	# Get parameters of current device
	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	# Build set command syntax
	my $syntax = 'update:noArg config:noArg paramsetDesc:noArg deviceInfo:noArg values:noArg';
	
	# Command datapoint depends on readable datapoints
	my @dpRList;
	my $dpRCount = HMCCU_GetValidDatapoints ($hash, $ccutype, -1, 1, \@dpRList);   
	$syntax .= ' datapoint:'.join(",", @dpRList) if ($dpRCount > 0);
	
	# Additional device specific commands
	my $addCmds = $hash->{hmccu}{cmdlist}{get} // '';
	$syntax .= " $addCmds" if ($addCmds ne '');
	
	# Log commands
	HMCCU_Log ($hash, 3, "get $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($ioName, 'logCommand')); 

	if ($lcopt eq 'datapoint') {
		my $objname = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name datapoint [{channel-number}.]{datapoint}");

		if ($objname =~ /^([0-9]+)\..+$/) {
			my $chn = $1;
			return HMCCU_SetError ($hash, -7) if ($chn >= $hash->{hmccu}{channels});
		}
		else {
			my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($hash);
			return HMCCU_SetError ($hash, -11) if ($sc eq '');
			$objname = $sc.'.'.$objname;
		}

		return HMCCU_SetError ($hash, -8, $objname)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, undef, $objname, 1));

		$objname = $ccuif.'.'.$ccuaddr.':'.$objname;
		my ($rc, $result) = HMCCU_GetDatapoint ($hash, $objname, 0);

		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		return $result;
	}
	elsif ($lcopt eq 'deviceinfo') {
		my $extended = shift @$a;
		return HMCCU_ExecuteGetDeviceInfoCommand ($ioHash, $hash, $ccuaddr, defined($extended) ? 1 : 0);
	}
	elsif ($lcopt =~ /^(config|values|update)$/) {
		my @addList = ($ccuaddr);

		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $ccuaddr, $ccuif);
		return HMCCU_SetError ($hash, "Can't get device description") if (!defined($devDesc));
		push @addList, split (',', $devDesc->{CHILDREN});

		my $result = HMCCU_ExecuteGetParameterCommand ($ioHash, $hash, $lcopt, \@addList);
		return HMCCU_SetError ($hash, "Can't get device description") if (!defined($result));
		return HMCCU_DisplayGetParameterResult ($ioHash, $hash, $result);
	}
	elsif ($lcopt eq 'paramsetdesc') {
		my $result = HMCCU_ParamsetDescToStr ($ioHash, $hash);
		return defined($result) ? $result : HMCCU_SetError ($hash, "Can't get device model");
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
=item summary controls HMCCU client devices for Homematic CCU - FHEM integration
=begin html

<a name="HMCCUDEV"></a>
<h3>HMCCUDEV</h3>
<ul>
   The module implements Homematic CCU devices as client devices for HMCCU. A HMCCU I/O device must
   exist before a client device can be defined. If a CCU channel is not found execute command
   'get devicelist' in I/O device.<br/>
   This reference contains only commands and attributes which differ from module
   <a href="#HMCCUCHN">HMCCUCHN</a>.
   </br></br>
   <a name="HMCCUDEVdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCUDEV &lt;device&gt; [&lt;controlchannel&gt;]
      [readonly] [<u>defaults</u>|noDefaults] [forceDev] [iodev=&lt;iodev-name&gt;]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. With option 'defaults'
      some default attributes depending on CCU device type will be set. Default attributes are only
      available for some device types. The option is ignored during FHEM start.
		Option 'forceDev' must be specified to define a HMCCUDEV device even if the preferred and
		recommended type is HMCCUCHN.<br/>
      Parameter <i>controlchannel</i> corresponds to attribute 'controlchannel'. If a device 
      has several identical channels, some commands need to know the channel number for
      controlling the device.<br/>
      <br/>
      Examples:<br/>
      <code>
      # Simple device by using CCU device name<br/>
      define window_living HMCCUDEV WIN-LIV-1<br/>
      # Simple device by using CCU device address and with state channel<br/>
      define temp_control HMCCUDEV BidCos-RF.LEQ1234567 1<br/>
      # Simple read only device by using CCU device address and with default attributes<br/>
      define temp_sensor HMCCUDEV BidCos-RF.LEQ2345678 1 readonly defaults
      </code>
      <br/><br/>
 	  Internals:<br/>
	  <ul>
	  	<li>ccuaddr: Address of device in CCU</li>
		<li>ccudevstate: State of device in CCU (active/inactive/dead)</li>
		<li>ccuif: Interface of device</li>
	  	<li>ccuname: Name of device in CCU</li>
		<li>ccurole: Role of device</li>
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
   
   <a name="HMCCUDEVset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; clear [&lt;reading-exp&gt;]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a> 
      </li><br/>
      <li><b>set &lt;name&gt; config [&lt;channel-number&gt;] &lt;parameter&gt;=&lt;value&gt;
        [...]</b><br/>
        Set configuration parameter of CCU device or channel. Valid parameters can be listed by 
        using command 'get configdesc'.
      </li><br/>
      <li><b>set &lt;name&gt; control &lt;value&gt;</b><br/>
      	Set value of control datapoint. This command is available for compatibility reasons.
      	It should not be used any more.
      </li><br/>
      <li><b>set &lt;name&gt; datapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;
       &lt;value&gt; [...]</b><br/>
        Set datapoint values of a CCU device channel. If channel number is not specified
        state channel is used. String \_ is substituted by blank.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint 2.SET_TEMPERATURE 21</code><br/>
        <code>set temp_control datapoint 2.AUTO_MODE 1 2.SET_TEMPERATURE 21</code>
      </li><br/>
      <li><b>set &lt;name&gt; defaults ['reset'|'<u>update</u>']</b><br/>
   		Set default attributes for CCU device type. Default attributes are only available for
   		some device types and for some channels of a device type. If option 'reset' is specified,
   		the following attributes are deleted before the new attributes are set: 
   		'ccureadingname', 'ccuscaleval', 'eventMap', 'substexcl', 'webCmd', 'widgetOverride'.
   		During update to version 4.4 it's recommended to use option 'reset'.
      </li><br/>
      <li><b>set &lt;name&gt; down [&lt;value&gt;]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; on-for-timer &lt;ontime&gt;</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; on-till &lt;timestamp&gt;</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; pct &lt;value;&gt; [&lt;ontime&gt; [&lt;ramptime&gt;]]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
		<li><b>set &lt;name&gt; readingFilter &lt;datapoint-list&gt;</b><br/>
			Set attribute ccureadingfilter by selecting a list of datapoints. Parameter <i>datapoint-list</i>
			is a comma seperated list of datapoints. The datapoints must be specifed in format
			"channel-number.datapoint-name".
		</li><br/>
      <li><b>set &lt;name&gt; &lt;statevalue&gt;</b><br/>
         State datapoint of a CCU device channel is set to 'statevalue'. State channel and state
         datapoint must be defined as attribute 'statedatapoint'. Values for <i>statevalue</i>
         are defined by setting attribute 'statevals'.
         <br/><br/>
         Example:<br/>
         <code>
         attr myswitch statedatapoint 1.STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; toggle</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; up [&lt;value&gt;]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>ePaper Display</b><br/><br/>
      This display has 5 text lines. The lines 1,2 and 4,5 are accessible via config parameters
      TEXTLINE_1 and TEXTLINE_2 in channels 1 and 2. Example:<br/><br/>
      <code>
      define HM_EPDISP HMCCUDEV CCU_EPDISP<br/>
      set HM_EPDISP config 2 TEXTLINE_1=Line1<br/>
		set HM_EPDISP config 2 TEXTLINE_2=Line2<br/>
		set HM_EPDISP config 1 TEXTLINE_1=Line4<br/>
		set HM_EPDISP config 1 TEXTLINE_2=Line5<br/>
      </code>
      <br/>
      The lines 2,3 and 4 of the display can be accessed by setting the datapoint SUBMIT of the
      display to a string containing command tokens in format 'parameter=value'. The following
      commands are allowed:
      <br/><br/>
      <ul>
      <li>text1-3=Text - Content of display line 2-4</li>
      <li>icon1-3=IconCode - Icons of display line 2-4</li>
      <li>sound=SoundCode - Sound</li>
      <li>signal=SignalCode - Optical signal</li>
      <li>pause=Seconds - Pause between signals (1-160)</li>
      <li>repeat=Count - Repeat count for sound (0-15)</li>
      </ul>
      <br/>
      IconCode := ico_off, ico_on, ico_open, ico_closed, ico_error, ico_ok, ico_info,
      ico_newmsg, ico_svcmsg<br/>
      SignalCode := sig_off, sig_red, sig_green, sig_orange<br/>
      SoundCode := snd_off, snd_longlong, snd_longshort, snd_long2short, snd_short, snd_shortshort,
      snd_long<br/><br/>
      Example:<br/>
      <code>
      set HM_EPDISP datapoint 3.SUBMIT text1=Line2,text2=Line3,text3=Line4,sound=snd_short,
      signal=sig_red
      </code>
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; config [&lt;filter-expr&gt;]</b><br/>
         Get configuration parameters of CCU device and all its channels. If ccuflag noReadings is set 
         parameters are displayed in browser window (no readings set). Parameters can be filtered
         by <i>filter-expr</i>.
      </li><br/>
      <li><b>get &lt;name&gt; datapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;</b><br/>
         Get value of a CCU device datapoint. If <i>channel-number</i> is not specified state 
         channel is used.
      </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	<a href="#HMCCUCHNget">see HMCCUCHN</a>
      </li><br/>
      <li><b>get &lt;name&gt; deviceinfo ['extended']</b><br/>
         Display information about device and channels:<br/>
         <ul>
         <li>all channels and datapoints of device with datapoint values and types</li>
         <li>statedatapoint and controldatapoint</li>
         <li>device and channel description</li>
         </ul>
      </li><br/>
      <li><b>get &lt;name&gt; update [{State | <u>Value</u>}]</b><br/>
      	<a href="#HMCCUCHNget">see HMCCUCHN</a>
      </li><br/>
      <li><b>get &lt;name&gt; weekProgram [&lt;program-number&gt;|<u>all</u>]</b><br/>
      	Display week programs. This command is only available if a device supports week programs.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVattr"></a>
   <b>Attributes</b><br/><br/>
   <ul>
      To reduce the amount of events it's recommended to set attribute 'event-on-change-reading'
      to '.*'.<br/><br/>
      <li><b>ccucalculate &lt;value-type&gt;:&lt;reading&gt;[:&lt;dp-list&gt;[;...]</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuflags {nochn0, trace}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingfilter &lt;filter-rule[,...]&gt;</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingformat {address[lc] | name[lc] | datapoint[lc]}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingname &lt;old-readingname-expr&gt;:&lt;new-readingname&gt;[,...]</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuscaleval &lt;datapoint&gt;:&lt;factor&gt;[,...]</b><br/>
      ccuscaleval &lt;[!]datapoint&gt;:&lt;min&gt;:&lt;max&gt;:&lt;minn&gt;:&lt;maxn&gt;[,...]<br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuSetOnChange &lt;expression&gt;</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuverify {0 | 1 | 2}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>controlchannel &lt;channel-number&gt;</b><br/>
         Channel used for setting device states.
      </li><br/>
      <li><b>controldatapoint &lt;channel-number.datapoint&gt;</b><br/>
         Set channel number and datapoint for device control.
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>disable {<u>0</u> | 1}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
		<li><b>hmstatevals &lt;subst-rule&gt;[;...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
		</li><br/>
		<li><b>peer [&lt;datapoints&gt;:&lt;condition&gt;:
			{ccu:&lt;object&gt;=&lt;value&gt;|hmccu:&lt;object&gt;=&lt;value&gt;}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
		</li><br/>
      <li><b>statechannel &lt;channel-number&gt;</b><br/>
         Channel for getting device state. Deprecated, use attribute 'statedatapoint' instead.
      </li><br/>
      <li><b>statedatapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;</b><br/>
         Set state channel and state datapoint.
         Default is STATE. If 'statedatapoint' is not defined at least attribute 'statechannel'
         must be set.
      </li><br/>
      <li><b>statevals &lt;text&gt;:&lt;text&gt;[,...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>stripnumber {0 | 1 | 2 | -n}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>substexcl &lt;reading-expr&gt;</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>substitute &lt;subst-rule&gt;[;...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>traceFilter &lt;filter-expr&gt;</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
   </ul>
</ul>

=end html
=cut


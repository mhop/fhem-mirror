######################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id: 88_HMCCUDEV.pm 18552 2019-02-10 11:52:28Z zap $
#
#  Version 4.4.025
#
#  (c) 2020 zap (zap01 <at> t-online <dot> de)
#
######################################################################
#  Client device for Homematic devices.
#  Requires module 88_HMCCU.pm
######################################################################

package main;

use strict;
use warnings;
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
	$hash->{UndefFn}  = 'HMCCUCHN_Undef';
	$hash->{RenameFn} = 'HMCCUDEV_Rename';
	$hash->{SetFn}    = 'HMCCUDEV_Set';
	$hash->{GetFn}    = 'HMCCUDEV_Get';
	$hash->{AttrFn}   = 'HMCCUDEV_Attr';
	$hash->{parseParams} = 1;

	$hash->{AttrList} = 'IODev ccuaggregate:textField-long ccucalculate:textField-long '. 
		'ccuflags:multiple-strict,ackState,logCommand,noReadings,trace,showMasterReadings,showLinkReadings,showDeviceReadings '.
		'ccureadingfilter:textField-long '.
		'ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc '.
		'ccureadingname:textField-long ccuSetOnChange ccuReadingPrefix '.
		'ccuget:State,Value ccuscaleval ccuverify:0,1,2 disable:0,1 '.
		'hmstatevals:textField-long statevals substexcl substitute:textField-long statechannel '.
		'controlchannel statedatapoint controldatapoint stripnumber peer:textField-long '.
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCUDEV_Define ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	
	my $usage = "Usage: define $name HMCCUDEV {device|'virtual'} [control-channel] ".
		"['readonly'] ['noDefaults'|'defaults'] [iodev={iodev-name}] [address={virtual-device-no}]".
		"[{groupexp=regexp|group={device|channel}[,...]]";
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
		"Control channel ambiguous. Please specify control channel in device definition"
	);

	my ($devname, $devtype, $devspec) = splice (@$a, 0, 3);
	my $ioHash = undef;

	# Store some definitions for delayed initialization
	$hash->{readonly} = 'no';
	$hash->{hmccu}{devspec}  = $devspec;
	$hash->{hmccu}{groupexp} = $h->{groupexp} if (exists ($h->{groupexp}));
	$hash->{hmccu}{group}    = $h->{group} if (exists ($h->{group}));
	$hash->{hmccu}{nodefaults} = $init_done ? 0 : 1;
	$hash->{hmccu}{semDefaults} = 0;

	if (exists($h->{address})) {
		return 'Option address not allowed' if ($init_done || $devspec ne 'virtual');
		$hash->{hmccu}{address}  = $h->{address};
	}
	else {
		return 'Option address not specified' if (!$init_done && $devspec eq 'virtual');
	}
	
	# Parse optional command line parameters
	foreach my $arg (@$a) {
		if    ($arg eq 'readonly')                     { $hash->{readonly} = 'yes'; }
		elsif (lc($arg) eq 'nodefaults' && $init_done) { $hash->{hmccu}{nodefaults} = 1; }
		elsif ($arg eq 'defaults' && $init_done)       { $hash->{hmccu}{nodefaults} = 0; }
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
			HMCCU_Log ($hash, 2, 'Cannot detect IO device, maybe CCU not ready. Trying later ...');
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}

	# Initialize FHEM device, set IO device
	my $rc = HMCCUDEV_InitDevice ($ioHash, $hash);
	return $errmsg[$rc] if ($rc > 0 && $rc < scalar(@errmsg));

	return undef;
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
# 8 = Control channel must be specified
######################################################################

sub HMCCUDEV_InitDevice ($$)
{
	my ($ioHash, $devHash) = @_;
	my $name = $devHash->{NAME};
	my $devspec = $devHash->{hmccu}{devspec};
	my $gdcount = 0;
	my $gdname = $devspec;

	if ($devspec eq 'virtual') {
		my $no = 0;
		if (exists($devHash->{hmccu}{address})) {
			# Only true during FHEM start
			$no = $devHash->{hmccu}{address};
		}
		else {
			# Search for free address. Maximum of 10000 virtual devices allowed.
			for (my $i=1; $i<=10000; $i++) {
				my $va = sprintf ("VIR%07d", $i);
				if (!HMCCU_IsValidDevice ($ioHash, $va, 1)) {
					$no = $i;
					last;
				}
			}
			return 7 if ($no == 0);
			$devHash->{DEF} .= " address=$no";
		}

		# Inform HMCCU device about client device
		return 2 if (!HMCCU_AssignIODevice ($devHash, $ioHash->{NAME}));

		$devHash->{ccuif}       = 'fhem';
		$devHash->{ccuaddr}     = sprintf ("VIR%07d", $no);
		$devHash->{ccuname}     = $name;
		$devHash->{ccudevstate} = 'active';
	}
	else {
		return 1 if (!HMCCU_IsValidDevice ($ioHash, $devspec, 7));

		my ($di, $da, $dn, $dt, $dc) = HMCCU_GetCCUDeviceParam ($ioHash, $devspec);
		return 1 if (!defined($da));
		$gdname = $dn;

		# Inform HMCCU device about client device
		return 2 if (!HMCCU_AssignIODevice ($devHash, $ioHash->{NAME}));

		$devHash->{ccuif}           = $di;
		$devHash->{ccuaddr}         = $da;
		$devHash->{ccuname}         = $dn;
		$devHash->{ccutype}         = $dt;
		$devHash->{ccudevstate}     = 'active';
		$devHash->{hmccu}{channels} = $dc;

		if ($init_done) {
			# Interactive device definition
			HMCCU_AddDevice ($ioHash, $di, $da, $devHash->{NAME});
			HMCCU_UpdateDevice ($ioHash, $devHash);
			HMCCU_UpdateDeviceRoles ($ioHash, $devHash);

			my ($sc, $sd, $cc, $cd, $sdCnt, $cdCnt) = HMCCU_GetSpecialDatapoints ($devHash);
			return 8 if ($cdCnt > 2);

			HMCCU_UpdateRoleCommands ($ioHash, $devHash, $attr{$devHash->{NAME}}{controlchannel});

			if (!exists($devHash->{hmccu}{nodefaults}) || $devHash->{hmccu}{nodefaults} == 0) {
				if (!HMCCU_SetDefaultAttributes ($devHash, {
					mode => 'update', role => undef, ctrlChn => $cc eq '' ? undef : $cc
				})) {
					HMCCU_Log ($devHash, 2, "No role attributes found");
					HMCCU_SetDefaults ($devHash);
				}
			}
			HMCCU_GetUpdate ($devHash, $da, 'Value');
		}
	}
	
	# Parse group options
	if ($devHash->{ccuif} eq 'VirtualDevices' || $devHash->{ccuif} eq 'fhem') {
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
		if ($devspec eq 'virtual') {
			my $dev = shift @devlist;
			my $devtype = HMCCU_GetDeviceType ($ioHash, $dev, 'n/a');
			my $devna = $devtype eq 'n/a' ? 1 : 0;
			for my $d (@devlist) {
				if (HMCCU_GetDeviceType ($ioHash, $d, 'n/a') ne $devtype) {
					$devna = 1;
					last;
				}
			}
			
			my $rc = 0;
			if ($devna) {
				$devHash->{ccutype} = 'n/a';
				$devHash->{readonly} = 'yes';
				$rc = HMCCU_CreateDevice ($ioHash, $devHash->{ccuaddr}, $name, undef, $dev); 
			}
			else {
				$devHash->{ccutype} = $devtype;
				$rc = HMCCU_CreateDevice ($ioHash, $devHash->{ccuaddr}, $name, $devtype, $dev); 
			}
			return $rc+4 if ($rc > 0);
						
			# Set default attributes
			$attr{$name}{ccureadingformat} = 'name';
		}
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
		HMCCU_DeleteDevice ($hash->{IODev}) if ($hash->{ccuif} eq 'fhem');
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
	my $hash = $defs{$name};

	if ($cmd eq 'set') {
		return "Missing value of attribute $attrname" if (!defined($attrval));
		if ($attrname eq 'IODev') {
			$hash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq 'statevals') {
			return "Device is read only" if ($hash->{readonly} eq 'yes');
		}
	}

	HMCCU_RefreshReadings ($hash) if ($init_done);
	
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
	$opt = lc($opt);

	# Check device state
	return "Device state doesn't allow set commands"
		if (!defined($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' || !defined($hash->{IODev}) ||
			($hash->{readonly} eq 'yes' && $opt !~ /^(\?|clear|config|defaults)$/) || 
			AttrVal ($name, 'disable', 0) == 1);

	my $ioHash = $hash->{IODev};
	my $ioName = $ioHash->{NAME};
	return ($opt eq '?' ? undef : 'Cannot perform set commands. CCU busy')
		if (HMCCU_IsRPCStateBlocking ($ioHash));

	# Get parameters of current device
	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	# Get state and control datapoints
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash);

	# Get additional commands
	my $cmdList = $hash->{hmccu}{cmdlist} // '';
	
	# Get state values related to control command and datapoint
	my $stateVals = HMCCU_GetStateValues ($hash, $cd, $cc);
	my @stateCmdList = split (/[:,]/, $stateVals);
	my %stateCmds = @stateCmdList;
	my @states = keys %stateCmds;

	# Some commands require a control channel and datapoint
	if ($opt =~ /^(control|toggle)$/) {
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, -12) if ($cc eq '');
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $cc, $cd, 2));
		return HMCCU_SetError ($hash, -7) if ($cc >= $hash->{hmccu}{channels});
	}

	my $result = '';
	my $rc;

	# Log commands
	HMCCU_Log ($hash, 3, "set $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($ioName, 'logCommand')); 
	
	if ($opt eq 'control') {
		my $value = shift @$a // return HMCCU_SetError ($hash, "Usage: set $name control {value}");
		$rc = HMCCU_SetMultipleDatapoints ($hash,
			{ "001.$ccuif.$ccuaddr:$cc.$cd" => HMCCU_Substitute ($value, $stateVals, 1, undef, '') }
		);
		return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
	}
	elsif ($opt eq 'datapoint') {
		my $usage = "Usage: set $name datapoint [{channel-number}.]{datapoint} {value} [...]";
		my %dpval;
		my $i = 0;

		push (@$a, %${h}) if (defined($h));
		while (my $objname = shift @$a) {
			my $value = shift @$a;
			$i += 1;

			if ($ccutype eq 'HM-Dis-EP-WM55' && !defined($value)) {
				$value = '';
				foreach my $t (keys %{$h}) {
					$value .= $value eq '' ? $t.'='.$h->{$t} : ','.$t.'='.$h->{$t};
				}
			}

			return HMCCU_SetError ($hash, $usage) if (!defined($value) || $value eq '');

			if ($objname =~ /^([0-9]+)\..+$/) {
				return HMCCU_SetError ($hash, -7) if ($1 >= $hash->{hmccu}{channels});
			}
			else {
				$objname = "$cc.$objname";
			}
		   
		   my $no = sprintf ("%03d", $i);
			$dpval{"$no.$ccuif.$ccuaddr:$objname"} = HMCCU_Substitute ($value, $stateVals, 1, undef, '');
		}

		return HMCCU_SetError ($hash, $usage) if (scalar(keys %dpval) < 1);
		
		$rc = HMCCU_SetMultipleDatapoints ($hash, \%dpval);
		return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_ExecuteToggleCommand ($hash, $cc, $cd);
	}
	elsif (exists($hash->{hmccu}{roleCmds}{$opt})) {
		return HMCCU_ExecuteRoleCommand ($ioHash, $hash, $opt, $cc, $a, $h);
	}
	elsif ($opt eq 'clear') {
		my $rnexp = shift @$a;
		HMCCU_DeleteReadings ($hash, $rnexp);
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt =~ /^(config|values)$/) {
		my %parSets = ('config' => 'MASTER', 'values' => 'VALUES');
		my $paramset = $parSets{$opt};
		my $receiver = '';
		my $ccuobj = $ccuaddr;
		
		return HMCCU_SetError ($hash, 'No parameter specified') if ((scalar keys %{$h}) < 1);	

		# Channel number is optional because parameter can be related to device or channel
		my $p = shift @$a;
		if (defined($p)) {
			if ($p =~ /^([0-9]{1,2})$/) {
				return HMCCU_SetError ($hash, -7) if ($p >= $hash->{hmccu}{channels});
				$ccuobj .= ':'.$p;
			}
			else {
				$receiver = $p;
				$paramset = 'LINK';
			}
		}
		
		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $ccuobj, $ccuif);
		return HMCCU_SetError ($hash, "Can't get device description") if (!defined($devDesc));
		return HMCCU_SetError ($hash, "Paramset $paramset not supported by device or channel")
			if ($devDesc->{PARAMSETS} !~ /$paramset/);
		if (!HMCCU_IsValidParameter ($ioHash, $devDesc, $paramset, $h)) {
			my @parList = HMCCU_GetParamDef ($ioHash, $devDesc, $paramset);
			return HMCCU_SetError ($hash, 'Invalid parameter specified. Valid parameters are '.
				join(',', @parList));
		}
				
		if ($paramset eq 'VALUES' || $paramset eq 'MASTER') {
			($rc, $result) = HMCCU_SetMultipleParameters ($hash, $ccuobj, $h, $paramset);
		}
		else {
			if (exists($defs{$receiver}) && defined($defs{$receiver}->{TYPE})) {
				my $clHash = $defs{$receiver};
				if ($clHash->{TYPE} eq 'HMCCUDEV') {
					my $chnNo = shift @$a;
					return HMCCU_SetError ($hash, 'Channel number required for link receiver')
						if (!defined($chnNo) || $chnNo !~ /^[0-9]{1,2}$/);
					$receiver = $clHash->{ccuaddr}.":$chnNo";
				}
				elsif ($clHash->{TYPE} eq 'HMCCUCHN') {
					$receiver = $clHash->{ccuaddr};
				}
				else {
					return HMCCU_SetError ($hash, "Receiver $receiver is not a HMCCUCHN or HMCCUDEV device");
				}
			}
			elsif (!HMCCU_IsChnAddr ($receiver, 0)) {
				my ($rcvAdd, $rcvChn) = HMCCU_GetAddress ($ioHash, $receiver);
				return HMCCU_SetError ($hash, "$receiver is not a valid CCU channel name")
					if ($rcvAdd eq '' || $rcvChn eq '');
				$receiver = "$rcvAdd:$rcvChn";
			}

			return HMCCU_SetError ($hash, "$receiver is not a link receiver of $name")
				if (!HMCCU_IsValidReceiver ($ioHash, $ccuaddr, $ccuif, $receiver));
			($rc, $result) = HMCCU_RPCRequest ($hash, 'putParamset', $ccuaddr, $receiver, $h);
		}

		return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
	}
	elsif ($opt eq 'defaults') {
		my $mode = shift @$a // 'update';
		$rc = HMCCU_SetDefaultAttributes ($hash, { mode => $mode, role => undef, ctrlChn => $cc });
		$rc = HMCCU_SetDefaults ($hash) if (!$rc);
		HMCCU_RefreshReadings ($hash) if ($rc);
		return HMCCU_SetError ($hash, $rc == 0 ? 'No default attributes found' : 'OK');
	}
	else {
		my $retmsg = 'clear defaults:reset,update';
		
		if ($hash->{readonly} ne 'yes') {
			$retmsg .= ' config datapoint';
			$retmsg .= " $cmdList" if ($cmdList ne '');
			$retmsg .= ' toggle:noArg' if (scalar(@states) > 0);
		}
		return AttrTemplate_Set ($hash, $retmsg, $name, $opt, @$a);
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
	$opt = lc($opt);
	
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
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash);

	# Virtual devices only support command get update
	return "HMCCUDEV: Unknown argument $opt, choose one of update:noArg"
		if ($ccuif eq 'fhem' && $opt ne 'update');

	my $result = '';
	my $rc;

	# Log commands
	HMCCU_Log ($hash, 3, "get $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($ioName, 'logCommand')); 

	if ($opt eq 'datapoint') {
		my $objname = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name datapoint [{channel-number}.]{datapoint}");

		if ($objname =~ /^([0-9]+)\..+$/) {
			my $chn = $1;
			return HMCCU_SetError ($hash, -7) if ($chn >= $hash->{hmccu}{channels});
		}
		else {
			return HMCCU_SetError ($hash, -11) if ($sc eq '');
			$objname = $sc.'.'.$objname;
		}

		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, undef, $objname, 1));

		$objname = $ccuif.'.'.$ccuaddr.':'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname, 0);

		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $result;
	}
	elsif ($opt eq 'deviceinfo') {
		$result = HMCCU_GetDeviceInfo ($hash, $ccuaddr);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		my $devInfo = HMCCU_FormatDeviceInfo ($result);
		$devInfo .= "StateDatapoint = $sc.$sd\nControlDatapoint = $cc.$cd";
		return $devInfo;
	}
	elsif ($opt =~ /^(config|values|update)$/) {
		my @addList = ($ccuaddr);

		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $ccuaddr, $ccuif);
		return HMCCU_SetError ($hash, "Can't get device description") if (!defined($devDesc));
		push @addList, split (',', $devDesc->{CHILDREN});

		return HMCCU_ExecuteGetParameterCommand ($ioHash, $hash, $opt, \@addList);
	}
	elsif ($opt eq 'paramsetdesc') {
		$result = HMCCU_ParamsetDescToStr ($ioHash, $hash);
		return defined($result) ? $result : HMCCU_SetError ($hash, "Can't get device model");
	}
	elsif ($opt eq 'devicedesc') {
		$result = HMCCU_DeviceDescToStr ($ioHash, $hash);
		return defined($result) ? $result : HMCCU_SetError ($hash, "Can't get device description");
	}
	elsif ($opt eq 'defaults') {
		$result = HMCCU_GetDefaults ($hash, 0);
		return $result;
	}
	elsif ($opt eq 'weekprogram') {
		my $program = shift @$a;
		return HMCCU_DisplayWeekProgram ($hash, $program);
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of datapoint";
		
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $ccutype, -1, 1, \@valuelist);   
		$retmsg .= ':'.join(",", @valuelist) if ($valuecount > 0);
		$retmsg .= ' defaults:noArg update:noArg config:noArg'.
			' paramsetDesc:noArg deviceDesc:noArg deviceInfo:noArg values:noArg';
		$retmsg .= ' weekProgram:all,'.join(',', sort keys %{$hash->{hmccu}{tt}})
			if (exists($hash->{hmccu}{tt}));

		return $retmsg;
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
      <code>define &lt;name&gt; HMCCUDEV {&lt;device&gt; | 'virtual'} [&lt;controlchannel&gt;]
      [readonly] [<u>defaults</u>|noDefaults] [{group={device|channel}[,...]|groupexp=regexp] 
      [iodev=&lt;iodev-name&gt;]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. With option 'defaults'
      some default attributes depending on CCU device type will be set. Default attributes are only
      available for some device types. The option is ignored during FHEM start.
      Parameter <i>controlchannel</i> corresponds to attribute 'controlchannel'.<br/>
      A HMCCUDEV device supports CCU group devices. The CCU devices or channels related to a group
      device are specified by using options 'group' or 'groupexp' followed by the names or
      addresses of the CCU devices or channels. By using 'groupexp' one can specify a regular
      expression for CCU device or channel names. Since version 4.2.009 of HMCCU HMCCUDEV
      is able to detect members of group devices automatically. So options 'group' or
      'groupexp' are no longer necessary to define a group device.<br/>
      It's also possible to group any kind of CCU devices without defining a real group
      in CCU by using option 'virtual' instead of a CCU device specification. 
      <br/><br/>
      Examples:<br/>
      <code>
      # Simple device by using CCU device name<br/>
      define window_living HMCCUDEV WIN-LIV-1<br/>
      # Simple device by using CCU device address and with state channel<br/>
      define temp_control HMCCUDEV BidCos-RF.LEQ1234567 1<br/>
      # Simple read only device by using CCU device address and with default attributes<br/>
      define temp_sensor HMCCUDEV BidCos-RF.LEQ2345678 1 readonly defaults
      # Group device by using CCU group device and 3 group members<br/>
      define heating_living HMCCUDEV GRP-LIV group=WIN-LIV,HEAT-LIV,THERM-LIV
      </code>
      <br/>
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
      <li><b>get &lt;name&gt; devicedesc [&lt;channel-number&gt;]</b><br/>
      	Display device description.
      </li><br/>
      <li><b>get &lt;name&gt; deviceinfo [{State | <u>Value</u>}]</b><br/>
         Display all channels and datapoints of device with datapoint values and types.
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
			{ccu:&lt;object&gt;=&lt;value&gt;|hmccu:&lt;object&gt;=&lt;value&gt;|fhem:&lt;command&gt;}</b><br/>
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
   </ul>
</ul>

=end html
=cut


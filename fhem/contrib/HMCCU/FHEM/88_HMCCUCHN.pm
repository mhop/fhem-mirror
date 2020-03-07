######################################################################
#
#  88_HMCCUCHN.pm
#
#  $Id: 88_HMCCUCHN.pm 18552 2019-02-10 11:52:28Z zap $
#
#  Version 4.4.012
#
#  (c) 2020 zap (zap01 <at> t-online <dot> de)
#
######################################################################
#  Client device for Homematic channels.
#  Requires module 88_HMCCU.pm
######################################################################

package main;

use strict;
use warnings;
use SetExtensions;
# use Data::Dumper;

require "$attr{global}{modpath}/FHEM/88_HMCCU.pm";

sub HMCCUCHN_Initialize ($);
sub HMCCUCHN_Define ($@);
sub HMCCUCHN_InitDevice ($$);
sub HMCCUCHN_Undef ($$);
sub HMCCUCHN_Rename ($$);
sub HMCCUCHN_Set ($@);
sub HMCCUCHN_Get ($@);
sub HMCCUCHN_Attr ($@);

######################################################################
# Initialize module
######################################################################

sub HMCCUCHN_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCUCHN_Define";
	$hash->{UndefFn} = "HMCCUCHN_Undef";
	$hash->{RenameFn} = "HMCCUCHN_Rename";
	$hash->{SetFn} = "HMCCUCHN_Set";
	$hash->{GetFn} = "HMCCUCHN_Get";
	$hash->{AttrFn} = "HMCCUCHN_Attr";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "IODev ccucalculate ".
		"ccuflags:multiple-strict,ackState,logCommand,noReadings,trace,showMasterReadings,showLinkReadings,showDeviceReadings ".
		"ccureadingfilter ".
		"ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc ".
		"ccureadingname:textField-long ccuSetOnChange ccuReadingPrefix ".
		"ccuscaleval ccuverify:0,1,2 ccuget:State,Value controldatapoint ".
		"disable:0,1 hmstatevals:textField-long statedatapoint statevals substitute:textField-long ".
		"substexcl stripnumber peer:textField-long ". $readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCUCHN_Define ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};

	my $usage = "Usage: define $name HMCCUCHN {device} ['readonly'] ['noDefaults'] [iodev={iodevname}]";
	return $usage if (@$a < 3);

	my $devname = shift @$a;
	my $devtype = shift @$a;
	my $devspec = shift @$a;

	my $ioHash = undef;

	my $existDev = HMCCU_ExistsClientDevice ($devspec, $devtype);
	return "FHEM device $existDev for CCU device $devspec already exists" if (defined($existDev));
		
	# Store some definitions for delayed initialization
	$hash->{hmccu}{devspec} = $devspec;
	
	# Defaults
	$hash->{readonly} = "no";
	$hash->{hmccu}{channels} = 1;
	
	# Parse optional command line parameters
	my $n = 0;
	my $arg = shift @$a;
	while (defined ($arg)) {
		return $usage if ($n == 3);
		if    ($arg eq 'readonly') { $hash->{readonly} = "yes"; }
		elsif ($arg ne 'noDefaults' && $init_done) { $hash->{hmccu}{nodefaults} = 1; }
		else { return $usage; }
		$n++;
		$arg = shift @$a;
	}
	
	# IO device can be set by command line parameter iodev, otherwise try to detect IO device
	if (exists ($h->{iodev})) {
		return "Specified IO Device ".$h->{iodev}." does not exist" if (!exists ($defs{$h->{iodev}}));
		return "Specified IO Device ".$h->{iodev}." is not a HMCCU device"
			if ($defs{$h->{iodev}}->{TYPE} ne 'HMCCU');
		$ioHash = $defs{$h->{iodev}};
	}
	else {
		# The following call will fail during FHEM start if CCU is not ready
		$ioHash = HMCCU_FindIODevice ($devspec);
	}
	
	if ($init_done) {
		# Interactive define command while CCU not ready or no IO device defined
		if (!defined ($ioHash)) {
			my ($ccuactive, $ccuinactive) = HMCCU_IODeviceStates ();
			if ($ccuinactive > 0) {
				return "CCU and/or IO device not ready. Please try again later";
			}
			else {
				return "Cannot detect IO device";
			}
		}
	}
	else {
		# CCU not ready during FHEM start
		if (!defined ($ioHash) || $ioHash->{ccustate} ne 'active') {
			Log3 $name, 2, "HMCCUCHN: [$devname] Cannot detect IO device, maybe CCU not ready. Trying later ...";
#			readingsSingleUpdate ($hash, "state", "Pending", 1);
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}
	
	# Initialize FHEM device, set IO device
	my $rc = HMCCUCHN_InitDevice ($ioHash, $hash);
	return "Invalid or unknown CCU channel name or address" if ($rc == 1);
	return "Can't assign I/O device ".$ioHash->{NAME} if ($rc == 2);

	return undef;
}

######################################################################
# Initialization of FHEM device.
# Called during Define() or by HMCCU after CCU ready.
# Return 0 on successful initialization or >0 on error:
# 1 = Invalid channel name or address
# 2 = Cannot assign IO device
######################################################################

sub HMCCUCHN_InitDevice ($$)
{
	my ($ioHash, $devHash) = @_;
	my $devspec = $devHash->{hmccu}{devspec};
	
	return 1 if (!HMCCU_IsValidChannel ($ioHash, $devspec, 7));

	my ($di, $da, $dn, $dt, $dc) = HMCCU_GetCCUDeviceParam ($ioHash, $devspec);
	return 1 if (!defined ($da));

	# Inform HMCCU device about client device
	return 2 if (!HMCCU_AssignIODevice ($devHash, $ioHash->{NAME}, undef));

	$devHash->{ccuif} = $di;
	$devHash->{ccuaddr} = $da;
	$devHash->{ccuname} = $dn;
	$devHash->{ccutype} = $dt;
	$devHash->{ccudevstate} = 'active';
	
	if ($init_done) {
		# Interactive device definition
		HMCCU_AddDevice ($ioHash, $di, $da, $devHash->{NAME});
		HMCCU_UpdateDevice ($ioHash, $devHash);
		HMCCU_UpdateDeviceRoles ($ioHash, $devHash);
		if (!exists($devHash->{hmccu}{nodefaults})) {
			if (!HMCCU_SetDefaultAttributes ($devHash)) {
				HMCCU_SetDefaults ($devHash);
			}
		}
		HMCCU_GetUpdate ($devHash, $da, 'Value');
	}

	return 0;
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
	my $hash = $defs{$name};

	if ($cmd eq "set") {
		return "Missing attribute value" if (!defined ($attrval));
		if ($attrname eq 'IODev') {
			$hash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq 'statevals') {
			return "Device is read only" if ($hash->{readonly} eq 'yes');
		}
	}

	if ($init_done) {
		HMCCU_RefreshReadings ($hash);
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
	my $opt = shift @$a;

	return "No set command specified" if (!defined ($opt));
	$opt = lc($opt);

	my $rocmds = "clear defaults:noArg";
	my $rwcmds = "clear config control datapoint defaults:noArg values";
	
	# Get I/O device, check device state
	return undef if (!defined ($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' ||
		!defined ($hash->{IODev}));
	return undef if ($hash->{readonly} eq 'yes' && $opt ne '?' &&
		$opt !~ /^(clear|config|defaults)$/);

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $ioHash = $hash->{IODev};
	my $ioName = $ioHash->{NAME};
	if (HMCCU_IsRPCStateBlocking ($ioHash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	
	# Get state and control datapoints
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', '', '', '');
	
	# Get additional commands (including state commands)
	my $roleCmds = HMCCU_GetSpecialCommands ($hash, $cc);
	
	my $cmdList = '';
	foreach my $cmd (keys %$roleCmds) {
		$cmdList .= " $cmd";
		my @setList = split (/\s+/, $roleCmds->{$cmd});
		foreach my $set (@setList) {
			my ($ps, $dpt, $par) = split(/:/, $set);
			if ($par !~ /^\?/) {
				my @argList = split (',', $par);
				$cmdList .= scalar(@argList) > 1 ? ":$par" : ":noArg";
			}
		}
	}
	
	# Get state values related to control command and datapoint
	my $stateVals = HMCCU_GetStateValues ($hash, $cd);
	my @stateCmdList = split (/[:,]/, $stateVals);
	my %stateCmds = @stateCmdList;
	my @states = keys %stateCmds;

	my $result = '';
	my $rc;

	# Log commands
	HMCCU_Log ($hash, 3, "set $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($ioName, 'logCommand')); 

	if ($opt eq 'datapoint') {
		my $usage = "Usage: set $name datapoint {{datapoint} {value} | {datapoint}={value}} [...]";
		my %dpval;
		my $i = 0;

		while (my $objname = shift @$a) {
			my $objvalue = shift @$a;
			$i++;

			return HMCCU_SetError ($hash, $usage) if (!defined ($objvalue));
			return HMCCU_SetError ($hash, -8)
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $objname, 2));

		   my $no = sprintf ("%03d", $i);
			$objvalue =~ s/\\_/%20/g;
			$objvalue = HMCCU_Substitute ($objvalue, $stateVals, 1, undef, '')
				if ($stateVals ne '' && $objname eq $cd);
			$dpval{"$no.$ccuif.$ccuaddr.$objname"} = $objvalue;
		}
		
		if (defined($h)) {
			foreach my $objname (keys %$h) {
				my $objvalue = $h->{$objname};
				$i++;
				my $no = sprintf ("%03d", $i);
				return HMCCU_SetError ($hash, -8)
					if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $objname, 2));
				$objvalue =~ s/\\_/%20/g;
				$objvalue = HMCCU_Substitute ($objvalue, $stateVals, 1, undef, '')
					if ($stateVals ne '' && $objname eq $cd);
				$dpval{"$no.$ccuif.$ccuaddr.$objname"} = $objvalue;
			}
		}

		return HMCCU_SetError ($hash, $usage) if (scalar (keys %dpval) < 1);

		$rc = HMCCU_SetMultipleDatapoints ($hash, \%dpval);
		return HMCCU_SetError ($hash, min(0, $rc));
	}
	elsif ($opt eq 'control') {
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $cc, $cd, 2)) {
			HMCCU_Trace ($hash, 2, "Set", "Invalid datapoint $cc $cd");
			return HMCCU_SetError ($hash, -8);
		}
		my $objvalue = shift @$a;
		return HMCCU_SetError ($hash, "Usage: set $name control {value}") if (!defined ($objvalue));

		$objvalue =~ s/\\_/%20/g;
		$objvalue =~ HMCCU_Substitute ($objvalue, $stateVals, 1, undef, '');

		$rc = HMCCU_SetMultipleDatapoints ($hash,
			{ "001.$ccuif.$ccuaddr.$cd" => $objvalue }
		);
		return HMCCU_SetError ($hash, min(0, $rc));
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_SetError ($hash, -15) if ($stateVals eq '');
		return HMCCU_SetError ($hash, -12) if ($cc eq '');
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $cd, 2));

		my $stc = scalar (@states);
		my $curState = defined($hash->{hmccu}{dp}{"$cc.$cd"}{VALUES}{SVAL}) ?
			$hash->{hmccu}{dp}{"$cc.$cd"}{VALUES}{SVAL} : $states[0];

		my $newState = '';
		my $st = 0;
		while ($st < $stc) {
			if ($states[$st] eq $curState) {
				$newState = ($st == $stc-1) ? $states[0] : $states[$st+1];
				last;
			}
			else {
				$st++;
			}
		}

		return HMCCU_SetError ($hash, "Current device state doesn't match any state value")
		   if ($newState eq '');

		$rc = HMCCU_SetMultipleDatapoints ($hash,
			{ "001.$ccuif.$ccuaddr.$cd" => $stateCmds{$newState} }
		);
		return HMCCU_SetError ($hash, min(0, $rc));
	}
	elsif (defined($roleCmds) && exists($roleCmds->{$opt})) {
		my $value;
		my %dpval;
		my %cfval;
		
		my @setList = split (/\s+/, $roleCmds->{$opt});
		my $i = 0;
		foreach my $set (@setList) {
			my ($ps, $dpt, $par) = split(/:/, $set);
			$ps = $ps eq 'V' ? 'VALUES' : 'MASTER';
		
			return HMCCU_SetError ($hash, "Syntax error in definition of command $opt")
				if (!defined($par));
	      if (!HMCCU_IsValidParameter ($hash, $ccuaddr, $ps, $dpt)) {
	      	HMCCU_Trace ($hash, 2, "Set", "Invalid parameter $ps $dpt");
				return HMCCU_SetError ($hash, -8);
			}

			if ($par =~ /^\?(.+)$/) {
				$par = $1;
				my ($parName, $parDef) = split ('=', $par);
				$value = shift @$a;
				if (!defined($value) && defined($parDef)) {
					if ($parDef =~ /^[+-][0-9]+$/) {
						return HMCCU_SetError ($hash, "Current value of $cc.$dpt not available")
							if (!defined($hash->{hmccu}{dp}{"$cc.$dpt"}{$ps}{SVAL}));
						$value = $hash->{hmccu}{dp}{"$cc.$dpt"}{$ps}{SVAL}+int($parDef);
					}
					else {
						$value = $parDef;
					}
				}
				
				return HMCCU_SetError ($hash, "Missing parameter $parName")
					if (!defined($value));
			}
			else {
				$value = $par;
			}
		
			if ($opt eq 'pct' || $opt eq 'level') {
				my $timespec = shift @$a;
				my $ramptime = shift @$a;

				# Set on time
				if (defined ($timespec)) {
					return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type $ccutype")
						if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "ON_TIME", 2));
					if ($timespec =~ /^[0-9]{2}:[0-9]{2}/) {
						$timespec = HMCCU_GetTimeSpec ($timespec);
						return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM[:SS]") if ($timespec < 0);
					}
					$dpval{"001.$ccuif.$ccuaddr.ON_TIME"} = $timespec if ($timespec > 0);
				}

				# Set ramp time
				if (defined($ramptime)) {
					return HMCCU_SetError ($hash, "Can't find RAMP_TIME datapoint for device type $ccutype")
						if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "RAMP_TIME", 2));
					$dpval{"002.$ccuif.$ccuaddr.RAMP_TIME"} = $ramptime if (defined ($ramptime));
				}
				
				$dpval{"003.$ccuif.$ccuaddr.$dpt"} = $value;
				last;
			}
			else {
				if ($ps eq 'VALUES') {
					my $no = sprintf ("%03d", $i);
					$dpval{"$i.$ccuif.$ccuaddr.$dpt"} = $value;
					$i++;
				}
				else {
					$cfval{$dpt} = $value;
				}
			}
		}

		if (scalar(keys %dpval) > 0) {
			$rc = HMCCU_SetMultipleDatapoints ($hash, \%dpval);
			return HMCCU_SetError ($hash, min(0, $rc));
		}
		if (scalar(keys %cfval) > 0) {
			($rc, $result) = HMCCU_SetMultipleParameters ($hash, $ccuaddr, $h, 'MASTER');
			return HMCCU_SetError ($hash, min(0, $rc));
		}
	}
	elsif ($opt eq 'on-for-timer' || $opt eq 'on-till') {
		return HMCCU_SetError ($hash, -15) if ($stateVals eq '');
		return HMCCU_SetError ($hash, "No state value for 'on' defined")
		   if (!exists($stateCmds{"on"}));
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $cd, 2));
		return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "ON_TIME", 2));

		my $timespec = shift @$a;
		return HMCCU_SetError ($hash, "Usage: set $name $opt {ontime-spec}")
			if (!defined ($timespec));
			
		if ($opt eq 'on-till') {
			$timespec = HMCCU_GetTimeSpec ($timespec);
			return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM[:SS]") if ($timespec < 0);
		}
		
		$rc = HMCCU_SetMultipleDatapoints ($hash, {
			"001.$ccuif.$ccuaddr.ON_TIME" => $timespec,
			"002.$ccuif.$ccuaddr.$cd" => $stateCmds{"on"}
		});
		return HMCCU_SetError ($hash, min(0, $rc));
	}
	elsif ($opt eq 'clear') {
		my $rnexp = shift @$a;
		HMCCU_DeleteReadings ($hash, $rnexp);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt =~ /^(config|values)$/) {
		my %parSets = ('config' => 'MASTER', 'values' => 'VALUES');
		my $paramset = $parSets{$opt};
		my $receiver = '';
		
		return HMCCU_SetError ($hash, "No parameter specified")
			if ((scalar keys %{$h}) < 1);	

		my $ccuobj = $ccuaddr;
		my $p = shift @$a;
		if (defined($p)) {
			if ($p eq 'device') {
				($ccuobj, undef) = HMCCU_SplitChnAddr ($ccuaddr);
			}
			else {
				$receiver = $p;
				$paramset = 'LINK';
			}
		}
		
		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $ccuobj, $ccuif);
		return HMCCU_SetError ($hash, "Can't get device description")
			if (!defined($devDesc));
		return HMCCU_SetError ($hash, "Paramset $paramset not supported by device or channel")
			if ($devDesc->{PARAMSETS} !~ /$paramset/);
		if (!HMCCU_IsValidParameter ($ioHash, $devDesc, $paramset, $h)) {
			my @parList = HMCCU_GetParamDef ($ioHash, $devDesc, $paramset);
			return HMCCU_SetError ($hash, "Invalid parameter specified. Valid parameters are ".
				join(',', @parList));
		}
				
		if ($paramset eq 'VALUES' || $paramset eq 'MASTER') {
			($rc, $result) = HMCCU_SetMultipleParameters ($hash, $ccuaddr, $h, $paramset);
		}
		else {
			if (exists($defs{$receiver}) && defined($defs{$receiver}->{TYPE})) {
				my $clHash = $defs{$receiver};
				if ($clHash->{TYPE} eq 'HMCCUDEV') {
					my $chnNo = shift @$a;
					return HMCCU_SetError ($hash, "Channel number required for link receiver")
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
				my ($rcvAdd, $rcvChn) = HMCCU_GetAddress ($ioHash, $receiver, '', '');
				return HMCCU_SetError ($hash, "$receiver is not a valid CCU channel name")
					if ($rcvAdd eq '' || $rcvChn eq '');
				$receiver = "$rcvAdd:$rcvChn";
			}

			return HMCCU_SetError ($hash, "$receiver is not a link receiver of $name")
				if (!HMCCU_IsValidReceiver ($ioHash, $ccuaddr, $ccuif, $receiver));
			($rc, $result) = HMCCU_RPCRequest ($hash, "putParamset", $ccuaddr, $receiver, $h);
		}

		return HMCCU_SetError ($hash, min(0, $rc));
	}
	elsif ($opt eq 'defaults') {
		$rc = HMCCU_SetDefaultAttributes ($hash);
		$rc = HMCCU_SetDefaults ($hash) if (!$rc);
		return HMCCU_SetError ($hash, $rc == 0 ? "No default attributes found" : "OK");
	}
	else {
		my $retmsg = "clear defaults:noArg";
		if ($hash->{readonly} ne 'yes') {
			$retmsg .= " config control";
			$retmsg .= ':'.join(',', @states) if (scalar(@states) > 0);
			$retmsg .= " datapoint".$cmdList;
			$retmsg .= ' toggle:noArg' if (scalar(@states) > 0);
			$retmsg .= " on-for-timer on-till"
				if ($sc ne '' && HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, "ON_TIME", 2));
		}
		return AttrTemplate_Set ($hash, $retmsg, $name, $opt, @$a);
	}
}

######################################################################
# Get commands
######################################################################

sub HMCCUCHN_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	return "No get command specified" if (!defined ($opt));
	$opt = lc($opt);

	return undef if (!defined ($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' ||
		!defined ($hash->{IODev}));

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $ioHash = $hash->{IODev};
	my $ioName = $ioHash->{NAME};
	if (HMCCU_IsRPCStateBlocking ($ioHash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	my $result = '';
	my $rc;

	# Log commands
	HMCCU_Log ($hash, 3, "get $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($ioName, 'logCommand')); 

	if ($opt eq 'datapoint') {
		my $objname = shift @$a;
		
		return HMCCU_SetError ($hash, "Usage: get $name datapoint {datapoint}")
			if (!defined ($objname));		
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $objname, 1));

		$objname = $ccuif.'.'.$ccuaddr.'.'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname, 0);
		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		return $result;
	}
	elsif ($opt eq 'update') {
		my $ccuget = shift @$a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name update [{'State'|'Value'}]");
		}
		$rc = HMCCU_GetUpdate ($hash, $ccuaddr, $ccuget);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return undef;
	}
	elsif ($opt eq 'deviceinfo') {
		my ($a, $c) = HMCCU_SplitChnAddr ($ccuaddr);
		$result = HMCCU_GetDeviceInfo ($hash, $a);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		return HMCCU_FormatDeviceInfo ($result);
	}
	elsif ($opt =~ /^(config|values)$/) {
		my %parSets = ('config' => 'MASTER,LINK', 'values' => 'VALUES');
		my $defParamset = $parSets{$opt};
		my ($devAddr, undef) = HMCCU_SplitChnAddr ($ccuaddr);
		my @addList = ($devAddr, "$devAddr:0", $ccuaddr);
		
		my %objects;
		foreach my $a (@addList) {
			my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $a, $ccuif);
			return HMCCU_SetError ($hash, "Can't get device description") if (!defined($devDesc));
			
			my $paramset = $defParamset eq '' ? $devDesc->{PARAMSETS} : $defParamset;
			my ($da, $dc) = HMCCU_SplitChnAddr ($a);
			$dc = 'd' if ($dc eq '');

			foreach my $ps (split (',', $paramset)) {
				next if ($devDesc->{PARAMSETS} !~ /$ps/);

				if ($ps eq 'LINK') {
					foreach my $rcv (HMCCU_GetReceivers ($ioHash, $ccuaddr, $ccuif)) {
						($rc, $result) = HMCCU_RPCRequest ($hash, 'getRawParamset', $a, $rcv, undef, undef);
						next if ($rc < 0);
						foreach my $p (keys %$result) {
							$objects{$da}{$dc}{"LINK.$rcv"}{$p} = $result->{$p};
						}					
					}
				}
				else {
					($rc, $result) = HMCCU_RPCRequest ($hash, 'getRawParamset', $a, $ps, undef, undef);
					return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
					foreach my $p (keys %$result) { $objects{$da}{$dc}{$ps}{$p} = $result->{$p}; }
				}
			}
		}
		
		my $res = '';
		if (scalar(keys %objects) > 0) {
			my $convRes = HMCCU_UpdateParamsetReadings ($ioHash, $hash, \%objects);
			if (defined($convRes)) {
				foreach my $da (sort keys %$convRes) {
					$res .= "Device $da\n";
					foreach my $dc (sort keys %{$convRes->{$da}}) {
						foreach my $ps (sort keys %{$convRes->{$da}{$dc}}) { 
							$res .= "  Channel $dc [$ps]\n";
							$res .= join ("\n", map { 
								"    ".$_.' = '.$convRes->{$da}{$dc}{$ps}{$_}
							} sort keys %{$convRes->{$da}{$dc}{$ps}})."\n";
						}
					}
				}
			}
		}
		
		return $res eq '' ? "No data found" : $res;
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
		return HMCCU_GetDefaults ($hash, 0);
	}
	else {
		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of defaults:noArg datapoint";
		
		my ($a, $c) = split(":", $hash->{ccuaddr});
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $hash->{ccutype}, $c, 1, \@valuelist);	
		$retmsg .= ":".join(",",@valuelist) if ($valuecount > 0);
		$retmsg .= " update:noArg deviceInfo:noArg config:noArg".
			" deviceDesc:noArg paramsetDesc:noArg values:noArg";
		
		return $retmsg;
	}
}


1;

=pod
=item device
=item summary controls HMCCU client devices for Homematic CCU2 - FHEM integration
=begin html

<a name="HMCCUCHN"></a>
<h3>HMCCUCHN</h3>
<ul>
   The module implements Homematic CCU channels as client devices for HMCCU. A HMCCU I/O device must
   exist before a client device can be defined. If a CCU channel is not found execute command
   'get devicelist' in I/O device. This will synchronize devices and channels between CCU
   and HMCCU.
   </br></br>
   <a name="HMCCUCHNdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCUCHN {&lt;channel-name&gt; | &lt;channel-address&gt;}
      [readonly] [noDefaults] [iodev=&lt;iodev-name&gt;]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. With option 'noDefaults'
      no default attributes will be set during interactive device definition. <br/>
      The define command accepts a CCU2 channel name or channel address as parameter.
      <br/><br/>
      Examples:<br/>
      <code>define window_living HMCCUCHN WIN-LIV-1 readonly</code><br/>
      <code>define temp_control HMCCUCHN BidCos-RF.LEQ1234567:1</code>
      <br/><br/>
      The interface part of a channel address must not be specified. The default is 'BidCos-RF'.
      Channel addresses can be found with command 'get deviceinfo &lt;devicename&gt;' executed
      in I/O device.
   </ul>
   <br/>
   
   <a name="HMCCUCHNset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; clear [&lt;reading-exp&gt;]</b><br/>
         Delete readings matching specified reading name expression. Default expression is '.*'.
         Readings 'state' and 'control' are not deleted.
      </li><br/>
      <li><b>set &lt;name&gt; config [device|&lt;receiver&gt;] &lt;parameter&gt;=&lt;value&gt;[:&lt;type&gt;]</b><br/>
         Set multiple config or link parameters. If neither 'device' nor <i>receiver</i> is
         specified, configuration parameters of current channel are set.
         With option 'device' configuration parameters of the device are set.<br/>
         If a <i>receiver</i> is specified, parameters will be set for the specified link.
         Parameter <i>receiver</i> is the 
         name of a FHEM device of type HMCCUDEV or HMCCUCHN or a channel address or a CCU
         channel name. For FHEM devices of type HMCCUDEV a <i>channel</i> number must be specified.
         Parameter <i>parameter</i> must be a valid configuration parameter.
         If <i>type</i> is not specified, it's taken from
         parameter set definition. The default <i>type</i> is STRING.
         Valid types are STRING, BOOL, INTEGER, FLOAT, DOUBLE.
      </li><br/>
      <li><b>set &lt;name&gt; datapoint &lt;datapoint&gt; &lt;value&gt; | &lt;datapoint&gt=&lt;value&gt; [...]</b><br/>
        Set datapoint values of a CCU channel. If parameter <i>value</i> contains special
        character \_ it's substituted by blank.
        <br/><br/>
        Examples:<br/>
        <code>set temp_control datapoint SET_TEMPERATURE 21</code><br/>
        <code>set temp_control datapoint AUTO_MODE 1 SET_TEMPERATURE 21</code>
      </li><br/>
      <li><b>set &lt;name&gt; defaults</b><br/>
   		Set default attributes for CCU device type. Default attributes are only available for
   		some device types and for some channels of a device type.
      </li><br/>
      <li><b>set &lt;name&gt; down [&lt;value&gt;]</b><br/>
      	Decrement value of datapoint LEVEL. This command is only available if channel contains
      	a datapoint LEVEL. Default for <i>value</i> is 20.
      </li><br/>
      <li><b>set &lt;name&gt; link &lt;receiver&gt; [&lt;channel&gt;] &lt;parameter&gt;=&lt;value&gt;[:&lt;type&gt;]</b><br/>
         Set multiple link parameters (parameter set LINK). Parameter <i>receiver</i> is the 
         name of a FHEM device of type HMCCUDEV or HMCCUCHN or a channel address or a CCU
         channel name. For FHEM devices of type HMCCUDEV a <i>channel</i> number must be specified.
         Parameter <i>parameter</i> must be a valid
         link configuration parameter name. If <i>type</i> is not specified, it's taken from
         parameter set definition. The default <i>type</i> is STRING.
         Valid types are STRING, BOOL, INTEGER, FLOAT, DOUBLE.
      </li><br/>
      <li><b>set &lt;name&gt; &lt;statevalue&gt;</b><br/>
         Set state of a CCU device channel to <i>StateValue</i>. The state datapoint of a channel
         must be defined by setting attribute 'statedatapoint'. The available state values must
         be defined by setting attribute 'statevals'.<br/>
         If 'statedatapoint' or 'statevals' is not set, HMCCUCHN tries to detect the parameters
         depending on the device type and the available datapoints.
         <br/><br/>
         Example: Turn switch on<br/>
         <code>
         attr myswitch statedatapoint STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; on-for-timer &lt;ontime&gt;</b><br/>
         Switch device on for specified number of seconds. This command is only available if
         channel contains a datapoint ON_TIME. The attribute 'statevals' must contain at least a
         value for 'on'. The attribute 'statedatapoint' must be set to a writeable datapoint.
         <br/><br/>
         Example: Turn switch on for 300 seconds<br/>
         <code>
         attr myswitch statedatapoint STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on-for-timer 300
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; on-till &lt;timestamp&gt;</b><br/>
         Switch device on until <i>timestamp</i>. Parameter <i>timestamp</i> can be a time in
         format HH:MM or HH:MM:SS. This command is only available if channel contains a datapoint
         ON_TIME. The attribute 'statevals' must contain at least a value for 'on'. The Attribute
         'statedatapoint' must be set to a writeable datapoint.
      </li><br/>
      <li><b>set &lt;name&gt; pct &lt;value&gt; [&lt;ontime&gt; [&lt;ramptime&gt;]]</b><br/>
         Set datapoint LEVEL of a channel to the specified <i>value</i>. Optionally a <i>ontime</i>
         and a <i>ramptime</i> (both in seconds) can be specified. This command is only available
         if channel contains at least a datapoint LEVEL and optionally datapoints ON_TIME and
         RAMP_TIME. The parameter <i>ontime</i> can be specified in seconds or as timestamp in
         format HH:MM or HH:MM:SS. If <i>ontime</i> is 0 it's ignored. This syntax can be used to
         modify the ramp time only.
         <br/><br/>
         Example: Turn dimmer on for 600 second. Increase light to 100% over 10 seconds<br>
         <code>
         attr myswitch statedatapoint LEVEL<br/>
         attr myswitch statevals on:100,off:0<br/>
         set myswitch pct 100 600 10
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; stop</b><br/>
      	Set datapoint STOP of a channel to true. This command is only available, if the
      	channel contains a writeable datapoint STOP.
      </li><br/>
      <li><b>set &lt;name&gt; toggle</b><br/>
        Toggle state datapoint between values defined by attribute 'statevals'. This command is
        only available if attribute 'statevals' is set. Toggling supports more than two state
        values.
        <br/><br/>
        Example: Toggle blind actor<br/>
        <code>
        attr myswitch statedatapoint LEVEL<br/>
        attr myswitch statevals up:100,down:0<br/>
        set myswitch toggle
        </code>
      </li><br/>
      <li><b>set &lt;name&gt; up [&lt;value&gt;]</b><br/>
      	Increment value of datapoint LEVEL. This command is only available if channel contains
      	a datapoint LEVEL. Default for <i>value</i> is 20.
      </li><br/>
      <li><b>set &lt;name&gt; values &lt;parameter&gt;=&lt;value&gt;[:&lt;type&gt;]</b><br/>
         Set multiple datapoint values (parameter set VALUES).
         Supports attribute 'ccuscaleval'. Parameter <i>parameter</i> must be a valid
         datapoint name. If <i>type</i> is not specified, it's taken from
         parameter set definition. The default <i>type</i> is STRING.
         Valid types are STRING, BOOL, INTEGER, FLOAT, DOUBLE.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; config</b><br/>
         Get configuration parameters of device and channel.
         If ccuflag noReadings is set results are displayed in browser window. Otherwise
         they are stored as readings beginning with "R-" for MASTER parameters and "L-" for
         LINK parameters. 
         Prefixes can be modified with attribute 'ccuReadingPrefix'. If option 'device' is specified parameters
         of device are read. Without option 'device' parameters of current channel and channel 0 are read.
      </li><br/>
      <li><b>get &lt;name&gt; datapoint &lt;datapoint&gt;</b><br/>
         Get value of a CCU channel datapoint.
      </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	Display default attributes for CCU device type.
      </li><br/>
      <li><b>get &lt;name&gt; deviceDesc</b><br/>
      	Display device or channel description. A channel description always includes channel 0.
      </li><br/>
      <li><b>get &lt;name&gt; deviceInfo</b><br/>
         Display all channels and datapoints of device with datapoint values and types.
      </li><br/>
      <li><b>get &lt;name&gt; paramsetDesc</b><br/>
         Display description of parameter sets of channel and device.
      </li><br/>
      <li><b>get &lt;name&gt; update [{State | <u>Value</u>}]</b><br/>
         Update all datapoints / readings of channel. With option 'State' the device is queried.
         This request method is more accurate but slower then 'Value'.
      </li><br/>
      <li><b>get &lt;name&gt; values</b><br/>
      	Same as 'get update' but using RPC instead of ReGa. 
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNattr"></a>
   <b>Attributes</b><br/><br/>
   <ul>
      To reduce the amount of events it's recommended to set attribute 'event-on-change-reading'
      to '.*'.
      <br/><br/>
      <li><b>ccucalculate &lt;value-type&gt;:&lt;reading&gt;[:&lt;dp-list&gt;[;...]</b><br/>
      	Calculate special values like dewpoint based on datapoints specified in
      	<i>dp-list</i>. The result is stored in <i>reading</i>. For datapoints in <i>dp-list</i>
      	also variable notation is supported (for more information on variables see documentation of
      	attribute 'peer').<br/>
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
      <li><b>ccuflags {ackState, logCommand, noReadings, showDeviceReadings, showLinkReadings, showConfigReadings, trace}</b><br/>
      	Control behaviour of device:<br/>
      	ackState: Acknowledge command execution by setting STATE to error or success.<br/>
      	logCommand: Write get and set commands to FHEM log with verbose level 3.<br/>
      	noReadings: Do not update readings<br/>
      	showDeviceReadings: Show readings of device and channel 0.<br/>
      	showLinkReadings: Show link readings.<br/>
      	showMasterReadings: Show configuration readings.<br/>
      	trace: Write log file information for operations related to this device.
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value'
         because each request is sent to the device. With method 'Value' only CCU is queried.
         Default is 'Value'.
      </li><br/>
      <li><b>ccureadingfilter &lt;filter-rule[;...]&gt;</b><br/>
         Only datapoints matching specified expression <i>RegExp</i> are stored as readings.<br/>
         Syntax for <i>filter-rule</i> is either:<br/>
         [N:]{&lt;channel-name&gt;}!RegExp&gt; or:<br/>
         [N:][&lt;channel-number&gt;.]&lt;RegExp&gt;<br/>
         If <i>channel-name</i> or <i>channel-number</i> is specified the following rule 
         applies only to this channel.<br/>
         If a rule starts with 'N:' the filter is negated which means that a reading is 
         stored if rule doesn't match.<br/>
         The following table describes the dependencies between this attribute and attribute
         ccudef-readingfilter in I/O device. The filtering of readings depends on which attribute
         is set.<br/>
         <table>
         <tr><th>ccureadingfilter<br/>Device</th><th>ccudef-readingfilter<br/>I/O Device</th><th>Update Readings/Datapoints</th></tr>
         <tr><td>not set</td><td>not set</td><td>all readings</td></tr>
         <tr><td>not set</td><td>set</td><td>only readings from ccudef-readingfilter</td></tr>
         <tr><td>set</td><td>not set</td><td>only readings from ccureadingfilter</td></tr>
         <tr><td>set</td><td>set</td><td>both readings from ccureadingfilter and ccudef-readingfilter</td></tr>
         </table>
         So if ccudef-readingfilter is set in I/O device one must also set ccureadingfilter to
         get updates for additional, device specific readings. Please keep in mind, that readings updates
         are also affected by attributes event-on-change-reading and event-on-update-reading.<br/><br/>
         Examples:<br/>
         <code>
         attr mydev ccureadingfilter .*<br/>
         attr mydev ccureadingfilter 1.(^ACTUAL|CONTROL|^SET_TEMP);(^WINDOW_OPEN|^VALVE)<br/>
         attr mydev ccureadingfilter MyBlindChannel!^LEVEL$<br/>
         </code>
      </li><br/>
      <li><b>ccureadingformat {address[lc] | name[lc] | datapoint[lc]}</b><br/>
         Set format of reading names. Default for virtual device groups is 'name'. The default for all
         other device types is 'datapoint'. If set to 'address' format of reading names
         is channel-address.datapoint. If set to 'name' format of reading names is
         channel-name.datapoint. If set to 'datapoint' format is channel-number.datapoint. With
         suffix 'lc' reading names are converted to lowercase.
      </li><br/>
      <li><b>ccureadingname &lt;old-readingname-expr&gt;:[+]&lt;new-readingname&gt[,...];[;...]</b><br/>
         Set alternative or additional reading names or group readings. Only part of old reading
         name matching <i>old-readingname-exptr</i> is substituted by <i>new-readingname</i>.
         If <i>new-readingname</i> is preceded by '+' an additional reading is created. If 
         <i>old-readingname-expr</i> matches more than one reading the values of these readings
         are stored in one reading. This makes sense only in some cases, i.e. if a device has
         several pressed_short datapoints and a reading should contain a value if any button
         is pressed.<br/><br/>
         Examples:<br/>
         <code>
         # Rename readings 0.LOWBAT and 0.LOW_BAT as battery<br/>
         attr mydev ccureadingname 0.(LOWBAT|LOW_BAT):battery<br/>
         # Add reading battery as a copy of readings LOWBAT and LOW_BAT.<br/>
         # Rename reading 4.SET_TEMPERATURE as desired-temp<br/>
         attr mydev ccureadingname 0.(LOWBAT|LOW_BAT):+battery;1.SET_TEMPERATURE:desired-temp<br/>
         # Store values of readings n.PRESS_SHORT in new reading pressed.<br/>
         # Value of pressed is 1/true if any button is pressed<br/>
         attr mydev ccureadingname [1-4].PRESSED_SHORT:+pressed
         </code>
      </li><br/>
      <li><b>ccuReadingPrefix &lt;paramset&gt;:&lt;prefix&gt;[,...]</b><br/>
      	Set reading name prefix for parameter sets. The special parameter set 'peer' can
      	be used for link readings.
      </li><br/>
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
      <li><b>controldatapoint &lt;datapoint&gt;</b><br/>
         Set datapoint for device control. Can be use to realize user defined control elements for
         setting control datapoint. For example if datapoint of thermostat control is 
         SET_TEMPERATURE one can define a slider for setting the destination temperature with
         following attributes:<br/><br/>
         attr mydev controldatapoint SET_TEMPERATURE<br/>
         attr mydev webCmd control<br/>
         attr mydev widgetOverride control:slider,10,1,25
      </li><br/>
      <li><b>disable {<u>0</u> | 1}</b><br/>
      	Disable client device.
      </li><br/>
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
		<li><b>peer &lt;datapoints&gt;:&lt;condition&gt;:
			{ccu:&lt;object&gt;=&lt;value&gt;|hmccu:&lt;object&gt;=&lt;value&gt;|
			fhem:&lt;command&gt;}</b><br/>
      	Logically peer datapoints of a HMCCUCHN or HMCCUDEV device with another device or any
      	FHEM command.<br/>
      	Parameter <i>datapoints</i> is a comma separated list of datapoints in format
      	<i>channelno.datapoint</i> which can trigger the action.<br/>
      	Parameter <i>condition</i> is a valid Perl expression which can contain
      	<i>channelno.datapoint</i> names as variables. Variables must start with a '$' or a '%'.
      	If a variable is preceded by a '$' the variable is substituted by the converted datapoint
      	value (i.e. "on" instead of "true"). If variable is preceded by a '%' the raw value
      	(i.e. "true") is used. If '$' or '%' is doubled the previous values will be used.<br/>
      	If the result of this operation is true, the action specified after the second colon
      	is executed. Three types of actions are supported:<br/>
      	<b>hmccu</b>: Parameter <i>object</i> refers to a FHEM device/datapoint in format
      	&lt;device&gt;:&lt;channelno&gt;.&lt;datapoint&gt;<br/>
      	<b>ccu</b>: Parameter <i>object</i> refers to a CCU channel/datapoint in format
      	&lt;channel&gt;.&lt;datapoint&gt;. <i>channel</i> can be a channel name or address.<br/>
      	<b>fhem</b>: The specified <i>command</i> will be executed<br/>
      	If action contains the string $value it is substituted by the current value of the 
      	datapoint which triggered the action. The attribute supports multiple peering rules
      	separated by semicolons and optionally by newline characters.<br/><br/>
      	Examples:<br/>
      	# Set FHEM device mydummy to value if formatted value of 1.STATE is 'on'<br/>
      	<code>attr mydev peer 1.STATE:'$1.STATE' eq 'on':fhem:set mydummy $value</code><br/>
      	# Set 2.LEVEL of device myBlind to 100 if raw value of 1.STATE is 1<br/>
      	<code>attr mydev peer 1.STATE:'%1.STATE' eq '1':hmccu:myBlind:2.LEVEL=100</code><br/>
      	# Set 1.STATE of device LEQ1234567 to true if 1.LEVEL < 100<br/>
      	<code>attr mydev peer 1.LEVEL:$1.LEVEL < 100:ccu:LEQ1234567:1.STATE=true</code><br/>
      	# Set 1.STATE of device LEQ1234567 to true if current level is different from old level<br/>
      	<code>attr mydev peer 1.LEVEL:$1.LEVEL != $$1.LEVEL:ccu:LEQ1234567:1.STATE=true</code><br/>
		</li><br/>
      <li><b>statedatapoint &lt;datapoint&gt;</b><br/>
         Set state datapoint used by some commands like 'set devstate'.
      </li><br/>
      <li><b>statevals &lt;text&gt;:&lt;text&gt;[,...]</b><br/>
         Define substitution for values of set commands. The parameters <i>text</i> are available
         as set commands.
         <br/><br/>
         Example:<br/>
         <code>
         attr my_switch statevals on:true,off:false<br/>
         set my_switch on
         </code>
      </li><br/>
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
      <li><b>substexcl &lt;reading-expr&gt;</b><br/>
      	Exclude values of readings matching <i>reading-expr</i> from substitution. This is helpful
      	for reading 'control' if the reading is used for a slider widget and the corresponding
      	datapoint is assigned to attribute statedatapoint and controldatapoint.
      </li><br/>
      <li><b>substitute &lt;subst-rule&gt;[;...]</b><br/>
         Define substitutions for datapoint/reading values. Syntax of <i>subst-rule</i> is<br/><br/>
         [[&lt;type&gt;:][&lt;channelno&gt;.]&lt;datapoint&gt;[,...]!]&lt;{#n1-m1|regexp}&gt;:&lt;text&gt;[,...]
         <br/><br/>
         Parameter <i>type</i> is a valid channel type, i.e. "SHUTTER_CONTACT".
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
      </li>
   </ul>
</ul>

=end html
=cut


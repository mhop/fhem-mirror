######################################################################
#
#  88_HMCCUCHN.pm
#
#  $Id$
#
#  Version 4.3
#
#  (c) 2018 zap (zap01 <at> t-online <dot> de)
#
######################################################################
#
#  define <name> HMCCUCHN <ccudev> [readonly] [defaults]
#         [iodev=<iodevname>]
#
#  set <name> config [device] <parameter>=<value> [...]
#  set <name> control <value>
#  set <name> datapoint <datapoint> <value> [...]
#  set <name> defaults
#  set <name> devstate <value>
#  set <name> <stateval_cmds>
#  set <name> on-till <timestamp>
#  set <name> on-for-timer <ontime>
#  set <name> pct <level> [{ <ontime> | 0 } [<ramptime>]]
#  set <name> toggle
#
#  get <name> config [device] [<filter-expr>]
#  get <name> configdesc [device]
#  get <name> configlist [device] [<filtet-expr>]
#  get <name> datapoint <datapoint>
#  get <name> defaults
#  get <name> deviceinfo
#  get <name> devstate
#  get <name> update
#
#  attr <name> ccucalculate <value>:<reading>[:<dp-list>][...]
#  attr <name> ccuflags { ackState, nochn0, trace }
#  attr <name> ccuget { State | Value }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccureadingfilter <filter-rule>[;...]
#  attr <name> ccureadingformat { name[lc] | address[lc] | datapoint[lc] }
#  attr <name> ccureadingname <oldname>:<newname>[;...]
#  attr <name> ccuverify { 0 | 1 | 2 }
#  attr <name> controldatapoint <datapoint>
#  attr <name> disable { 0 | 1 }
#  attr <name> peer datapoints:condition:{hmccu:object=value|ccu:object=value|fhem:command}
#  attr <name> hmstatevals <subst-rule>[;...]
#  attr <name> statedatapoint <datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> substexcl <reading-expr>
#  attr <name> substitute <subst-rule>[;...]
#
######################################################################
#  Requires modules 88_HMCCU.pm, HMCCUConf.pm
######################################################################

package main;

use strict;
use warnings;
use SetExtensions;

# use Time::HiRes qw( gettimeofday usleep );

sub HMCCUCHN_Initialize ($);
sub HMCCUCHN_Define ($@);
sub HMCCUCHN_InitDevice ($$);
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
	$hash->{SetFn} = "HMCCUCHN_Set";
	$hash->{GetFn} = "HMCCUCHN_Get";
	$hash->{AttrFn} = "HMCCUCHN_Attr";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "IODev ccucalculate ".
		"ccuflags:multiple-strict,ackState,nochn0,trace ccureadingfilter ".
		"ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc ".
		"ccureadingname:textField-long ".
		"ccureadings:0,1 ccuscaleval ccuverify:0,1,2 ccuget:State,Value controldatapoint ".
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

	my $usage = "Usage: define $name HMCCUCHN {device} ['readonly'] ['defaults'] [iodev={iodevname}]";
	return $usage if (@$a < 3);

	my $devname = shift @$a;
	my $devtype = shift @$a;
	my $devspec = shift @$a;

	my $hmccu_hash = undef;
	
	# Store some definitions for delayed initialization
	$hash->{hmccu}{devspec} = $devspec;
	
	# Defaults
	$hash->{channels} = 1;
	$hash->{statevals} = 'devstate';
	
	# Parse optional command line parameters
	my $n = 0;
	my $arg = shift @$a;
	while (defined ($arg)) {
		return $usage if ($n == 3);
		if    ($arg eq 'readonly') { $hash->{statevals} = $arg; }
		elsif ($arg eq 'defaults' && !$init_done) { HMCCU_SetDefaults ($hash); }
		else { return $usage; }
		$n++;
		$arg = shift @$a;
	}
	
	# IO device can be set by command line parameter iodev, otherwise try to detect IO device
	if (exists ($h->{iodev})) {
		return "Specified IO Device ".$h->{iodev}." does not exist" if (!exists ($defs{$h->{iodev}}));
		return "Specified IO Device ".$h->{iodev}." is not a HMCCU device"
			if ($defs{$h->{iodev}}->{TYPE} ne 'HMCCU');
		$hmccu_hash = $defs{$h->{iodev}};
	}
	else {
		# The following call will fail during FHEM start if CCU is not ready
		$hmccu_hash = HMCCU_FindIODevice ($devspec);
	}
	
	if ($init_done) {
		# Interactive define command while CCU not ready or no IO device defined
		if (!defined ($hmccu_hash)) {
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
		if (!defined ($hmccu_hash) || $hmccu_hash->{ccustate} ne 'active') {
			Log3 $name, 2, "HMCCUCHN: [$devname] Cannot detect IO device, maybe CCU not ready. Trying later ...";
			readingsSingleUpdate ($hash, "state", "Pending", 1);
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}
	
	# Initialize FHEM device, set IO device
	my $rc = HMCCUCHN_InitDevice ($hmccu_hash, $hash);
	return "Invalid or unknown CCU channel name or address" if ($rc == 1);
	return "Can't assign I/O device ".$hmccu_hash->{NAME} if ($rc == 2);

	return undef;
}

######################################################################
# Initialization of FHEM device.
# Called during Define() or by HMCCU after CCU ready.
# Return 0 on successful initialization or >0 on error:
# 1 = Invalid channel name or address
# 2 = Cannot assign IO device
######################################################################

sub HMCCUCHN_InitDevice ($$) {
	my ($hmccu_hash, $dev_hash) = @_;
	my $devspec = $dev_hash->{hmccu}{devspec};
	
	return 1 if (!HMCCU_IsValidChannel ($hmccu_hash, $devspec, 7));

	my ($di, $da, $dn, $dt, $dc) = HMCCU_GetCCUDeviceParam ($hmccu_hash, $devspec);
	return 1 if (!defined ($da));

	# Inform HMCCU device about client device
	return 2 if (!HMCCU_AssignIODevice ($dev_hash, $hmccu_hash->{NAME}, undef));

	$dev_hash->{ccuif} = $di;
	$dev_hash->{ccuaddr} = $da;
	$dev_hash->{ccuname} = $dn;
	$dev_hash->{ccutype} = $dt;

	readingsSingleUpdate ($dev_hash, "state", "Initialized", 1);
	$dev_hash->{ccudevstate} = 'active';
	
	return 0;
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
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	my $rocmds = "clear config defaults:noArg";
	
	# Get I/O device, check device state
	return HMCCU_SetError ($hash, -19) if (!defined ($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending');
	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));
	return undef if ($hash->{statevals} eq 'readonly' && $opt ne '?' &&
		$opt !~ /^(clear|config|defaults)$/);

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $statevals = AttrVal ($name, 'statevals', '');
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');

	my $result = '';
	my $rc;

	if ($opt eq 'datapoint') {
		my $usage = "Usage: set $name datapoint {datapoint} {value} [...]";
		my %dpval;
		while (my $objname = shift @$a) {
			my $objvalue = shift @$a;

			return HMCCU_SetError ($hash, $usage) if (!defined ($objvalue));
			return HMCCU_SetError ($hash, -8)
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $objname, 2));
		   
			$objvalue =~ s/\\_/%20/g;
			$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, undef, '');

			$objname = $ccuif.'.'.$ccuaddr.'.'.$objname;
			$dpval{$objname} = $objvalue;
		}

		return HMCCU_SetError ($hash, $usage) if (scalar (keys %dpval) < 1);
		
		foreach my $dpt (keys %dpval) {
			$rc = HMCCU_SetDatapoint ($hash, $dpt, $dpval{$dpt});
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}

		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'control') {
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $cc, $cd, 2));
		my $objvalue = shift @$a;
		return HMCCU_SetError ($hash, "Usage: set $name control {value}") if (!defined ($objvalue));

		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, undef, '');
		
		my $objname = $ccuif.'.'.$ccuaddr.'.'.$cd;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : shift @$a;

		return HMCCU_SetError ($hash, -13) if ($sd eq '');		
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 2));
		return HMCCU_SetError ($hash, "Usage: set $name devstate {value}") if (!defined ($objvalue));

		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, undef, '');

		my $objname = $ccuif.'.'.$ccuaddr.'.'.$sd;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_SetError ($hash, -15) if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, -13) if ($sd eq '');	
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 2));

		my $tstates = $hash->{statevals};
		$tstates =~ s/devstate\|//;
		my @states = split /\|/, $tstates;
		my $stc = scalar (@states);

		my $objname = $ccuif.'.'.$ccuaddr.'.'.$sd;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);

		my $objvalue = '';
		my $st = 0;
		while ($st < $stc) {
			if ($states[$st] eq $result) {
				$objvalue = ($st == $stc-1) ? $states[0] : $states[$st+1];
				last;
			}
			else {
				$st++;
			}
		}

		return HMCCU_SetError ($hash, "Current device state doesn't match statevals")
		   if ($objvalue eq '');

		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, undef, '');
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'pct') {
		return HMCCU_SetError ($hash, "Can't find LEVEL datapoint for device type $ccutype")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "LEVEL", 2));
		   
		my $objname = '';
		my $objvalue = shift @$a;
		return HMCCU_SetError ($hash, "Usage: set $name pct {value} [{ontime} [{ramptime}]]")
			if (!defined ($objvalue));
		
		my $timespec = shift @$a;
		my $ramptime = shift @$a;

		# Set on time
		if (defined ($timespec)) {
			return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type $ccutype")
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "ON_TIME", 2));
			if ($timespec =~ /^[0-9]{2}:[0-9]{2}/) {
				my (undef, $h, $m, $s)  = GetTimeSpec ($timespec);
				return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM or HH:MM:SS")
					if (!defined ($h));
				$s += $h*3600+$m*60;
				my @lt = localtime;
				my $cs = $lt[2]*3600+$lt[1]*60+$lt[0];
				$s += 86400 if ($cs > $s);
				$timespec = $s-$cs;
			}
			if ($timespec > 0) {
				$objname = $ccuif.'.'.$ccuaddr.'.ON_TIME';
				$rc = HMCCU_SetDatapoint ($hash, $objname, $timespec);
				return HMCCU_SetError ($hash, $rc) if ($rc < 0);
			}
		}
		
		# Set ramp time
		if (defined ($ramptime)) {
			return HMCCU_SetError ($hash, "Can't find RAMP_TIME datapoint for device type $ccutype")
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "RAMP_TIME", 2));
			$objname = $ccuif.'.'.$ccuaddr.'.RAMP_TIME';
			$rc = HMCCU_SetDatapoint ($hash, $objname, $ramptime);
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}

		# Set level	
		$objname = $ccuif.'.'.$ccuaddr.'.LEVEL';
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'on-for-timer' || $opt eq 'on-till') {
		return HMCCU_SetError ($hash, -15) if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, "No state value for 'on' defined")
		   if ("on" !~ /($hash->{statevals})/);
		return HMCCU_SetError ($hash, -13) if ($sd eq '');
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 2));
		return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "ON_TIME", 2));

		my $timespec = shift @$a;
		return HMCCU_SetError ($hash, "Usage: set $name $opt {ontime-spec}")
			if (!defined ($timespec));
			
		if ($opt eq 'on-till') {
			my (undef, $h, $m, $s)  = GetTimeSpec ($timespec);
			return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM or HH:MM:SS")
				if (!defined ($h));
			$s += $h*3600+$m*60;
			my @lt = localtime;
			my $cs = $lt[2]*3600+$lt[1]*60+$lt[0];
			$s += 86400 if ($cs > $s);
			$timespec = $s-$cs;
		}

		# Set time
		my $objname = $ccuif.'.'.$ccuaddr.'.ON_TIME';
		$rc = HMCCU_SetDatapoint ($hash, $objname, $timespec);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
				
		# Set state
		$objname = $ccuif.'.'.$ccuaddr.'.'.$sd;
		my $objvalue = HMCCU_Substitute ("on", $statevals, 1, undef, '');
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'clear') {
		my $rnexp = shift @$a;
		$rnexp = '.*' if (!defined ($rnexp));
		my @readlist = keys %{$hash->{READINGS}};
		foreach my $rd (@readlist) {
			delete ($hash->{READINGS}{$rd}) if ($rd ne 'state' && $rd ne 'control' && $rd =~ /$rnexp/);
		}
	}
	elsif ($opt eq 'config') {
		return HMCCU_SetError ($hash, "Usage: set $name config [device] {parameter}={value} [...]")
			if ((scalar keys %{$h}) < 1);

		my $ccuobj = $ccuaddr;
		my $par = shift @$a;
		if (defined ($par) && $par eq 'device') {
			($ccuobj, undef) = HMCCU_SplitChnAddr ($ccuaddr);
		}
		my $rc = HMCCU_RPCSetConfig ($hash, $ccuobj, $h);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'defaults') {
		my $rc = HMCCU_SetDefaults ($hash);
		return HMCCU_SetError ($hash, "HMCCU: No default attributes found") if ($rc == 0);
		return HMCCU_SetState ($hash, "OK");
	}
	else {
		return "HMCCUCHN: Unknown argument $opt, choose one of ".$rocmds
			if ($hash->{statevals} eq 'readonly');

		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of clear config control datapoint defaults:noArg devstate";
		if ($hash->{statevals} ne '') {
			my @cmdlist = split /\|/,$hash->{statevals};
			shift @cmdlist;
			$retmsg .= ':'.join(',',@cmdlist) if (@cmdlist > 0);
			foreach my $sv (@cmdlist) {
				$retmsg .= ' '.$sv.':noArg';
			}
			$retmsg .= " toggle:noArg";
			$retmsg .= " on-for-timer on-till"
				if (HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $ccuaddr, "ON_TIME", 2));
			$retmsg .= " pct"
				if (HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $ccuaddr, "LEVEL", 2));
		}

		return $retmsg;
	}
}

#####################################
# Get commands
#####################################

sub HMCCUCHN_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');
	my $ccureadings = AttrVal ($name, "ccureadings", 1);

	my $result = '';
	my $rc;

	if ($opt eq 'devstate') {
		return HMCCU_SetError ($hash, -13) if ($sd eq '');
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 1));

		my $objname = $ccuif.'.'.$ccuaddr.'.'.$sd;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @$a;
		
		return HMCCU_SetError ($hash, "Usage: get $name datapoint {datapoint}")
			if (!defined ($objname));		
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $objname, 1));

		$objname = $ccuif.'.'.$ccuaddr.'.'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		return $ccureadings ? undef : $result;
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
		my $ccuget = shift @$a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name deviceinfo [{'State'|'Value'}]");
		}
		my ($a, $c) = split(":", $hash->{ccuaddr});
		$result = HMCCU_GetDeviceInfo ($hash, $a, $ccuget);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		return HMCCU_FormatDeviceInfo ($result);
	}
	elsif ($opt eq 'config') {
		my $ccuobj = $ccuaddr;
		my $par = shift @$a;
		if (defined ($par)) {
			if ($par eq 'device') {
				($ccuobj, undef) = HMCCU_SplitChnAddr ($ccuaddr);
				$par = shift @$a;
			}
		}
		$par = '.*' if (!defined ($par));

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamset", $par);
		return HMCCU_SetError ($hash, $rc, $res) if ($rc < 0);
		return $ccureadings ? undef : $res;
	}
	elsif ($opt eq 'configlist') {
		my $ccuobj = $ccuaddr;
		my $par = shift @$a;
		if (defined ($par)) {
			if ($par eq 'device') {
				($ccuobj, undef) = HMCCU_SplitChnAddr ($ccuaddr);
				$par = shift @$a;
			}
		}
		$par = '.*' if (!defined ($par));

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "listParamset", $par);
		return HMCCU_SetError ($hash, $rc, $res) if ($rc < 0);
		return $res;
	}
	elsif ($opt eq 'configdesc') {
		my $ccuobj = $ccuaddr;
		my $par = shift @$a;
		if (defined ($par) && $par eq 'device') {
			($ccuobj, undef) = HMCCU_SplitChnAddr ($ccuaddr);
		}
		
		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription", undef);
		return HMCCU_SetError ($hash, $rc, $res) if ($rc < 0);
		return $res;
	}
	elsif ($opt eq 'defaults') {
		$result = HMCCU_GetDefaults ($hash, 0);
		return $result;
	}
	else {
		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of devstate:noArg defaults:noArg datapoint";
		
		my ($a, $c) = split(":", $hash->{ccuaddr});
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $hash->{ccutype}, $c, 1, \@valuelist);	
		$retmsg .= ":".join(",",@valuelist) if ($valuecount > 0);
		$retmsg .= " update:noArg deviceinfo config configlist configdesc:noArg";
		
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
   'get devicelist' in I/O device.
   </br></br>
   <a name="HMCCUCHNdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCUCHN {&lt;channel-name&gt; | &lt;channel-address&gt;}
      [readonly] [defaults] [iodev=&lt;iodev-name&gt;]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. With option 'defaults'
      some default attributes depending on CCU device type will be set. Default attributes are only
      available for some device types.<br/>
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
      <li><b>set &lt;name&gt; config [device] [&lt;rpcport&gt;] &lt;parameter&gt;=&lt;value&gt;]
      [...]</b><br/>
        Set config parameters of CCU channel. This is equal to setting device parameters in CCU.
        Valid parameters can be listed by using commands 'get configdesc' or 'get configlist'.
        With option 'device' specified parameters are set in device instead of channel.
      </li><br/>
      <li><b>set &lt;name&gt; datapoint &lt;datapoint&gt; &lt;value&gt; [...]</b><br/>
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
      <li><b>set &lt;name&gt; devstate &lt;value&gt;</b><br/>
         Set state of a CCU device channel. The state datapoint of a channel must be defined
         by setting attribute 'statedatapoint' to a valid datapoint name.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate true</code>
      </li><br/>
      <li><b>set &lt;name&gt; &lt;statevalue&gt;</b><br/>
         Set state of a CCU device channel to <i>StateValue</i>. The state datapoint of a channel
         must be defined by setting attribute 'statedatapoint'. The available state values must
         be defined by setting attribute 'statevals'.
         <br/><br/>
         Example: Turn switch on<br/>
         <code>
         attr myswitch statedatapoint STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
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
   </ul>
   <br/>
   
   <a name="HMCCUCHNget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; config [device] [&lt;filter-expr&gt;]</b><br/>
         Get configuration parameters of CCU channel. If attribute 'ccureadings' is 0 results
         are displayed in browser window. Parameters can be filtered by <i>filter-expr</i>.
         Parameters to be stored as readings must be part of 'ccureadingfilter'. If option
         'device' is specified parameters of device are read.
      </li><br/>
      <li><b>get &lt;name&gt; configdesc [device]</b><br/>
         Get description of configuration parameters of CCU channel or device if option 'device'
         is specified.
      </li><br/>
      <li><b>get &lt;name&gt; configlist [device] [&lt;filter-expr&gt;]</b><br/>
         Get configuration parameters of CCU channel. Parameters can be filtered by 
         <i>filter-expr</i>. With option 'device' device parameters are listed.
      </li><br/>
      <li><b>get &lt;name&gt; datapoint &lt;datapoint&gt;</b><br/>
         Get value of a CCU channel datapoint.
      </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	Display default attributes for CCU device type.
      </li><br/>
      <li><b>get &lt;name&gt; deviceinfo [{State | <u>Value</u>}]</b><br/>
         Display all channels and datapoints of device with datapoint values and types.
      </li><br/>
      <li><b>get &lt;name&gt; devstate</b><br/>
         Get state of CCU device. Default datapoint STATE can be changed by setting
         attribute 'statedatapoint'. Command will fail if state datapoint does not exist in
         channel.
      </li><br/>
      <li><b>get &lt;name&gt; update [{State | <u>Value</u>}]</b><br/>
         Update all datapoints / readings of channel. With option 'State' the device is queried.
         This request method is more accurate but slower then 'Value'.
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
      	<i>dp-list</i>. The result is stored in <i>reading</i>. The following <i>values</i>
      	are supported:<br/>
      	dewpoint = calculate dewpoint, <i>dp-list</i> = &lt;temperature&gt;,&lt;humidity&gt;<br/>
      	abshumidity = calculate absolute humidity, <i>dp-list</i> = &lt;temperature&gt;,&lt;humidity&gt;<br/>
      	inc = increment datapoint value considering reset of datapoint, <i>dp-list</i> = &lt;counter-datapoint&gt;<br/>
      	min = calculate minimum continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	max = calculate maximum continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	sum = calculate sum continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	avg = calculate average continuously, <i>dp-list</i> = &lt;datapoint&gt;<br/>
      	Example:<br/>
      	<code>dewpoint:taupunkt:1.TEMPERATURE,1.HUMIDITY</code>
      </li><br/>
      <li><b>ccuflags {nochn0, trace}</b><br/>
      	Control behaviour of device:<br/>
      	ackState: Acknowledge command execution by setting STATE to error or success.<br/>
      	nochn0: Prevent update of status channel 0 datapoints / readings.<br/>
      	trace: Write log file information for operations related to this device.
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value'
         because each request is sent to the device. With method 'Value' only CCU is queried.
         Default is 'Value'.
      </li><br/>
      <li><b>ccureadings {0 | <u>1</u>}</b><br/>
         If set to 1 values read from CCU will be stored as readings. Default is 1.
      </li><br/>
      <li><b>ccureadingfilter &lt;filter-rule[;...]&gt;</b><br/>
         Only datapoints matching specified expression are stored as readings.<br/>
         Syntax for <i>filter-rule</i> is either:<br/>
         [N:]{&lt;channel-name&gt;|&lt;channel-number&gt;}!&lt;RegExp&gt; or:<br/>
         [N:][&lt;channel-number&gt;.]&lt;RegExp&gt;<br/>
         If <i>channel-name</i> or <i>channel-number</i> is specified the following rule 
         applies only to this channel.
         By default all datapoints will be stored as readings. Attribute ccudef-readingfilter
         of I/O device will be checked before this attribute.<br/>
         If a rule starts with 'N:' the filter is negated which means that a reading is 
         stored if rule doesn't match.
      </li><br/>
      <li><b>ccureadingformat {address[lc] | name[lc] | datapoint[lc]}</b><br/>
         Set format of reading names. Default for virtual device groups is 'name'. The default for all
         other device types is 'datapoint'. If set to 'address' format of reading names
         is channel-address.datapoint. If set to 'name' format of reading names is
         channel-name.datapoint. If set to 'datapoint' format is channel-number.datapoint. With
         suffix 'lc' reading names are converted to lowercase.
      </li><br/>
      <li><b>ccureadingname &lt;old-readingname-expr&gt;:[+]&lt;new-readingname&gt;[;...]</b><br/>
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
         [[&lt;channelno&gt;.]&lt;datapoint&gt;[,...]!]&lt;{#n1-m1|regexp}&gt;:&lt;text&gt;[,...]
         <br/><br/>
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


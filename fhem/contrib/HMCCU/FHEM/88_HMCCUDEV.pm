#####################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id:$
#
#  Version 3.3
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
#####################################################################
#
#  define <name> HMCCUDEV {<ccudev>|virtual} [statechannel] [readonly]
#     [{group={<device>|<channel>}[,...]|groupexp=<regexp>}]
#
#  set <name> config [<channel>] <parameter>=<value> [...]
#  set <name> control <value>
#  set <name> datapoint <channel>.<datapoint> <value>
#  set <name> defaults
#  set <name> devstate <value>
#  set <name> on-for-timer <seconds>
#  set <name> <stateval_cmds>
#  set <name> toggle
#
#  get <name> devstate
#  get <name> datapoint <channel>.<datapoint>
#  get <name> defaults
#  get <name> channel <channel>[.<datapoint-expr>]
#  get <name> config [<channel>]
#  get <name> configdesc [<channel>]
#  get <name> update
#
#  attr <name> ccuget { State | Value }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccureadingformat { address | name }
#  attr <name> ccureadingfilter <filter-rule>[,...]
#  attr <name> ccuscaleval <datapoint>:<factor>[,...]
#  attr <name> ccuverify { 0 | 1 | 2}
#  attr <name> controldatapoint <channel-number>.<datapoint>
#  attr <name> disable { 0 | 1 }
#  attr <name> mapdatapoints <channel>.<datapoint>=<channel>.<datapoint>[,...]
#  attr <name> statechannel <channel>
#  attr <name> statedatapoint [<channel-number>.]<datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#
#####################################################################
#  Requires module 88_HMCCU
#####################################################################

package main;

use strict;
use warnings;
use SetExtensions;
# use Data::Dumper;

use Time::HiRes qw( gettimeofday usleep );

sub HMCCUDEV_Define ($@);
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

	$hash->{AttrList} = "IODev ccureadingfilter:textField-long ccureadingformat:name,address ccureadings:0,1 ccuget:State,Value ccuscaleval ccuverify:0,1,2 disable:0,1 mapdatapoints:textField-long statevals substitute statechannel statedatapoint controldatapoint stripnumber:0,1,2 ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCUDEV_Define ($@)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	my $usage = "Usage: define $name HMCCUDEV {device|'virtual'} [state-channel] ['readonly'] [{groupexp=regexp|group={device|channel}[,...]]";
	return $usage if (@a < 3);

	my $devname = shift @a;
	my $devtype = shift @a;
	my $devspec = shift @a;

	my $hmccu_hash = undef;

	if ($devspec ne 'virtual') {
		return "Invalid or unknown CCU device name or address" if (!HMCCU_IsValidDevice ($devspec));
	}

	if ($devspec eq 'virtual') {
		# Virtual device FHEM only
		my $no = 0;
		foreach my $d (sort keys %defs) {
			my $ch = $defs{$d};
			$hmccu_hash = $ch if ($ch->{TYPE} eq 'HMCCU' && !defined ($hmccu_hash));
			next if ($ch->{TYPE} ne 'HMCCUDEV');
			next if ($d eq $name);
			next if ($ch->{ccuif} ne 'VirtualDevices' || $ch->{ccuname} ne 'none');
			$no++;
		}
		return "No IO device found" if (!defined ($hmccu_hash));
		$hash->{ccuif} = "VirtualDevices";
		$hash->{ccuaddr} = sprintf ("VIR%07d", $no+1);
		$hash->{ccuname} = "none";
	}
	elsif (HMCCU_IsDevAddr ($devspec, 1)) {
		# CCU Device address with interface
		$hash->{ccuif} = $1;
		$hash->{ccuaddr} = $2;
		$hash->{ccuname} = HMCCU_GetDeviceName ($hash->{ccuaddr}, '');
	}
	elsif (HMCCU_IsDevAddr ($devspec, 0)) {
		# CCU Device address without interface
		$hash->{ccuaddr} = $devspec;
		$hash->{ccuname} = HMCCU_GetDeviceName ($devspec, '');
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}
	else {
		# CCU Device name
		$hash->{ccuname} = $devspec;
		my ($add, $chn) = HMCCU_GetAddress ($devspec, '', '');
		return "Name is a channel name" if ($chn ne '');
		$hash->{ccuaddr} = $add;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}

	return "CCU device address not found for $devspec" if ($hash->{ccuaddr} eq '');
	return "CCU device name not found for $devspec" if ($hash->{ccuname} eq '');

	$hash->{ccutype} = HMCCU_GetDeviceType ($hash->{ccuaddr}, '');
	$hash->{channels} = HMCCU_GetDeviceChannels ($hash->{ccuaddr});

	if ($hash->{ccuif} eq "VirtualDevices" && $hash->{ccuname} eq 'none') {
		$hash->{statevals} = 'readonly';
	}
	else {
		$hash->{statevals} = 'devstate';
	}

	my $n = 0;
	my $arg = shift @a;
	while (defined ($arg)) {
		return $usage if ($n == 3);
		if ($arg eq 'readonly') {
			$hash->{statevals} = $arg;
			$n++;
		}
		elsif ($arg =~ /^groupexp=/ && $hash->{ccuif} eq "VirtualDevices") {
			my ($g, $gdev) = split ("=", $arg);
			return $usage if (!defined ($gdev));
			my @devlist;
			my $cnt = HMCCU_GetMatchingDevices ($hmccu_hash, $gdev, 'dev', \@devlist);
			return "No matching CCU devices found" if ($cnt == 0);
			$hash->{ccugroup} = shift @devlist;
			foreach my $gd (@devlist) {
				$hash->{ccugroup} .= ",".$gd;
			}
		}
		elsif ($arg =~ /^group=/ && $hash->{ccuif} eq "VirtualDevices") {
			my ($g, $gdev) = split ("=", $arg);
			return $usage if (!defined ($gdev));
			my @gdevlist = split (",", $gdev);
			$hash->{ccugroup} = '' if (@gdevlist > 0);
			foreach my $gd (@gdevlist) {
				my ($gda, $gdc, $gdo) = ('', '', '', '');

				return "Invalid device or channel $gd"
				   if (!HMCCU_IsValidDevice ($gd));

				if (HMCCU_IsDevAddr ($gd, 0) || HMCCU_IsChnAddr ($gd, 1)) {
					$gdo = $gd;
				}
				else {
					($gda, $gdc) = HMCCU_GetAddress ($gd, '', '');
					$gdo = $gda;
					$gdo .= ':'.$gdc if ($gdc ne '');
				}

				if (exists ($hash->{ccugroup}) && $hash->{ccugroup} ne '') {
					$hash->{ccugroup} .= ",".$gdo;
				}
				else {
					$hash->{ccugroup} = $gdo;
				}
			}
		}
		elsif ($arg =~ /^[0-9]+$/) {
			$attr{$name}{statechannel} = $arg;
			$n++;
		}
		else {
			return $usage;
		}
		$arg = shift @a;
	}

	return "No devices in group" if ($hash->{ccuif} eq "VirtualDevices" && (
	   !exists ($hash->{ccugroup}) || $hash->{ccugroup} eq ''));

	# Inform HMCCU device about client device
	AssignIoPort ($hash);

	readingsSingleUpdate ($hash, "state", "Initialized", 1);
	$hash->{ccudevstate} = 'Active';

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCUDEV_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if ($cmd eq "set") {
		return "Missing attribute value" if (!defined ($attrval));
		if ($attrname eq 'IODev') {
			$hash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq "statevals") {
			return "Device is read only" if ($hash->{statevals} eq 'readonly');
			$hash->{statevals} = 'devstate';
			my @states = split /,/,$attrval;
			foreach my $st (@states) {
				my @statesubs = split /:/,$st;
				return "value := text:substext[,...]" if (@statesubs != 2);
				$hash->{statevals} .= '|'.$statesubs[0];
			}
		}
		elsif ($attrname eq "mapdatapoints") {
			return "Not a virtual device" if ($hash->{ccuif} ne "VirtualDevices");
		}
	}
	elsif ($cmd eq "del") {
		if ($attrname eq "statevals") {
			$hash->{statevals} = "devstate";
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

	return HMCCU_SetError ($hash, -3) if (!exists ($hash->{IODev}));
	return undef if ($hash->{statevals} eq 'readonly');

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	my $hmccu_name = $hash->{IODev}->{NAME};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUDEV: CCU busy";
	}

#	my $statechannel = AttrVal ($name, "statechannel", '');
#	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my $statevals = AttrVal ($name, "statevals", '');
#	my $controldatapoint = AttrVal ($name, "controldatapoint", '');
	my ($statechannel, $statedatapoint, $controlchannel, $controldatapoint) = 
	   HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');

	my $result = '';
	my $rc;

	if ($opt eq 'datapoint') {
		my $objname = shift @a;
#		my $objvalue = join ('%20', @a);
		my $objvalue = shift @a;

		if (!defined ($objname) || $objname !~ /^[0-9]+\..+$/ || !defined ($objvalue)) {
			return HMCCU_SetError ($hash, "Usage: set $name datapoint {channel-number}.{datapoint} {value}");
		}
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, 
		   $hash->{ccuaddr}, $objname, 2));
		   
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		# Build datapoint address
		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'control') {
		return HMCCU_SetError ($hash, "Attribute controldatapoint not set") if ($controldatapoint eq '');
		my $objvalue = shift @a;
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$controlchannel.'.'.$controldatapoint;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : shift @a;

		return HMCCU_SetError ($hash, "No state channel specified") if ($statechannel eq '');
		return HMCCU_SetError ($hash, "Usage: set $name devstate {value}") if (!defined ($objvalue));

		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		# Build datapoint address
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel.'.'.$statedatapoint;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_SetError ($hash, "Attribute statevals not set")
		   if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, "No state channel specified") if ($statechannel eq '');

		my $tstates = $hash->{statevals};
		$tstates =~ s/devstate\|//;
		my @states = split /\|/, $tstates;
		my $sc = scalar (@states);

		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel.'.'.$statedatapoint;
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
	elsif ($opt eq 'on-for-timer') {
		return HMCCU_SetError ($hash, "Attribute statevals not set")
		   if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, "No state channel specified") if ($statechannel eq '');
		return HMCCU_SetError ($hash, "No state value for 'on' defined")
		   if ("on" !~ /($hash->{statevals})/);
			
		my $timespec = shift @a;
		return HMCCU_SetError ($hash, "Usage: set $name on-for-timer {on-time} [{ramp-time}]")
		   if (!defined ($timespec));

		my $swrtdpt = '';
		my $ramptime = shift @a;
		if (defined ($ramptime)) {
			$swrtdpt = HMCCU_GetSwitchDatapoint ($hash, $hash->{ccutype}, 'ramptime');
			return HMCCU_SetError ($hash, "Can't find ramp-time datapoint for device type")
			   if ($swrtdpt eq '');
		}
		
		my $swotdpt = HMCCU_GetSwitchDatapoint ($hash, $hash->{ccutype}, 'ontime');
		return HMCCU_SetError ($hash, "Can't find on-time datapoint for device type")
		   if ($swotdpt eq '');
		
		# Set on time		
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$swotdpt;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $timespec);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		# Set ramp time
		if ($swrtdpt ne '') {
			my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$swrtdpt;
			$rc = HMCCU_SetDatapoint ($hash, $objname, $ramptime);
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}

		# Set state
		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel.'.'.$statedatapoint;
		my $objvalue = HMCCU_Substitute ("on", $statevals, 1, '');
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'config') {
		return HMCCU_SetError ($hash, "Usage: set $name config [{channel-number}] {parameter}={value} [...]")
		   if (@a < 1);
		my $objname = $hash->{ccuaddr};
		$objname .= ':'.shift @a if ($a[0] =~ /^[0-9]$/);

		my $rc = HMCCU_RPCSetConfig ($hash, $objname, \@a);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'defaults') {
		HMCCU_SetDefaults ($hash);
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of config control datapoint defaults:noArg";
		return undef if ($hash->{statevals} eq 'readonly');

		if ($statechannel ne '') {
			$retmsg .= " devstate";
			if ($hash->{statevals} ne '') {
				my @cmdlist = split /\|/,$hash->{statevals};
				shift @cmdlist;
				$retmsg .= ':'.join(',',@cmdlist) if (@cmdlist > 0);
				foreach my $sv (@cmdlist) {
					$retmsg .= ' '.$sv.':noArg';
				}
				$retmsg .= " toggle:noArg";
				$retmsg .= " on-for-timer" if ($statechannel ne '' &&
				   HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $statechannel, "ON_TIME", 2));
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

	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUDEV: CCU busy";
	}

#	my $statechannel = AttrVal ($name, 'statechannel', '');
#	my $statedatapoint = AttrVal ($name, 'statedatapoint', 'STATE');
	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my ($statechannel, $statedatapoint, $cc, $cd) = HMCCU_GetSpecialDatapoints (
	   $hash, '', 'STATE', '', '');

	my $result = '';
	my $rc;

	if ($hash->{ccuif} eq "VirtualDevices" && $hash->{ccuname} eq "none" && $opt ne 'update') {
		return "HMCCUDEV: Unknown argument $opt, choose one of update:noArg";
	}

	if ($opt eq 'devstate') {
		return HMCCU_SetError ($hash, "No state channel specified") if ($statechannel eq '');

		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel.'.'.$statedatapoint;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);

		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @a;
		if (!defined ($objname) || $objname !~ /^[0-9]+\..*$/) {
			return HMCCU_SetError ($hash, "Usage: get $name datapoint {channel-number}.{datapoint}");
		}
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $hash->{ccutype},
		   $hash->{ccuaddr}, $objname, 1));

		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);

		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'channel') {
		my @chnlist;
		foreach my $objname (@a) {
			last if (!defined ($objname));
			if ($objname =~ /^([0-9]+)/ && exists ($hash->{channels})) {
				return HMCCU_SetError ($hash, -7) if ($1 >= $hash->{channels});
			}
			else {
				return HMCCU_SetError ($hash, -7);
			}
			if ($objname =~ /^[0-9]{1,2}.*=/) {
				$objname =~ s/=/ /;
			}
			push (@chnlist, $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname);
		}
		if (@chnlist == 0) {
			return HMCCU_SetError ($hash, "Usage: get $name channel {channel-number}[.{datapoint-expr}] [...]");
		}

		($rc, $result) = HMCCU_GetChannel ($hash, \@chnlist);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'update') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name update [{'State'|'Value'}]");
		}

		if ($hash->{ccuname} ne 'none') {
			$rc = HMCCU_GetUpdate ($hash, $hash->{ccuaddr}, $ccuget);
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}

		# Update other devices belonging to group
		if ($hash->{ccuif} eq "VirtualDevices" && exists ($hash->{ccugroup})) {
			my @vdevs = split (",", $hash->{ccugroup});
			foreach my $vd (@vdevs) {
				$rc = HMCCU_GetUpdate ($hash, $vd, $ccuget);
				return HMCCU_SetError ($hash, $rc) if ($rc < 0);
			}
		}

		return undef;
	}
	elsif ($opt eq 'deviceinfo') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name deviceinfo [{'State'|'Value'}]");
		}
		$result = HMCCU_GetDeviceInfo ($hash, $hash->{ccuaddr}, $ccuget);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		return HMCCU_FormatDeviceInfo ($result);
	}
	elsif ($opt eq 'config') {
		my $channel = undef;
		my $par = shift @a;
		if (defined ($par)) {
			$channel = $par if ($par =~ /^[0-9]{1,2}$/);
		}

		my $ccuobj = $hash->{ccuaddr};
		$ccuobj .= ':'.$channel if (defined ($channel));

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamset");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $ccureadings ? undef : $res;
	}
	elsif ($opt eq 'configdesc') {
		my $channel = undef;
		my $par = shift @a;
		if (defined ($par)) {
			$channel = $par if ($par =~ /^[0-9]{1,2}$/);
		}

		my $ccuobj = $hash->{ccuaddr};
		$ccuobj .= ':'.$channel if (defined ($channel));

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $res;
	}
	elsif ($opt eq 'defaults') {
		$result = HMCCU_GetDefaults ($hash);
		return $result;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of datapoint";
		
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $hash->{ccutype}, -1, 1, \@valuelist);
		   
		$retmsg .= ":".join(",", @valuelist) if ($valuecount > 0);
		$retmsg .= " defaults:noArg channel update:noArg config configdesc deviceinfo:noArg";
		
		if ($statechannel ne '') {
			$retmsg .= ' devstate:noArg';
		}
		return $retmsg;
	}
}

#####################################
# Set error status
#####################################

sub HMCCUDEV_SetError ($$)
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

	$msg = "HMCCUDEV: ".$name." ". $msg;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log3 $name, 1, $msg;
	return $msg;
}

1;

=pod
=begin html

<a name="HMCCUDEV"></a>
<h3>HMCCUDEV</h3>
<ul>
   The module implements client devices for HMCCU. A HMCCU device must exist
   before a client device can be defined.
   </br></br>
   <a name="HMCCUDEVdefine"></a>
   <b>Define</b>
   <ul>
      <br/>
      <code>define &lt;name&gt; HMCCUDEV {&lt;device-name&gt;|&lt;device-address&gt;} [&lt;statechannel&gt;] [readonly] [{group={device|channel}[,...]|groupexp=regexp]</code>
      <br/><br/>
      If <i>readonly</i> parameter is specified no set command will be available.
      <br/><br/>
      Examples:<br/>
      <code>define window_living HMCCUDEV WIN-LIV-1 readonly</code><br/>
      <code>define temp_control HMCCUDEV BidCos-RF.LEQ1234567 1</code>
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVset"></a>
   <b>Set</b><br/>
   <ul>
      <br/>
      <li>set &lt;name&gt; devstate &lt;value&gt; [...]<br/>
         Set state of a CCU device channel. Channel must be defined as attribute
         'statechannel'. Default datapoint can be modfied by setting attribute
         'statedatapoint'.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate on</code>
      </li><br/>
      <li>set &lt;name&gt; defaults<br/>
   		Set default attributes for CCU device type.
      </li><br/>
      <li>set &lt;name&gt; on-for-timer &lt;seconds&gt; &lt;seconds&gt;<br/>
         Switch device on for specified time. Requires that device contains a datapoint
         ON_TIME and optionally RAMP_TIME. Attribute 'statevals' must contain value 'on'.
      </li><br/>
      <li>set &lt;name&gt; &lt;statevalue&gt; <br/>
         State of a CCU device channel is set to 'statevalue'. Channel must
         be defined as attribute 'statechannel'. Default datapoint STATE can be
         modified by setting attribute 'statedatapoint'. Values for <i>statevalue</i>
         are defined by setting attribute 'statevals'.
         <br/><br/>
         Example:<br/>
         <code>
         attr myswitch statechannel 1<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li>set &lt;name&gt; toggle<br/>
        Toggles between values defined by attribute 'statevals'.
      </li><br/>
      <li>set &lt;name&gt; datapoint &lt;channel-number&gt;.&lt;datapoint&gt; &lt;value&gt; [...]<br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint 1.SET_TEMPERATURE 21</code>
      </li><br/>
      <li>set &lt;name&gt; config [&lt;channel-number&gt;] &lt;parameter&gt;=&lt;value&gt; [...]<br/>
        Set configuration parameter of CCU device or channel.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVget"></a>
   <b>Get</b><br/>
   <ul>
      <br/>
      <li>get &lt;name&gt; devstate<br/>
         Get state of CCU device. Attribute 'statechannel' must be set.
      </li><br/>
      <li>get &lt;name&gt; datapoint &lt;channel-number&gt;.&lt;datapoint&gt;<br/>
         Get value of a CCU device datapoint.
      </li><br/>
      <li>get &lt;name&gt; config [&lt;channel-number&gt;]<br/>
         Get configuration parameters of CCU device. If attribute ccureadings is set to 0
         parameters are displayed in browser window (no readings set).
      </li><br/>
      <li>get &lt;name&gt; configdesc [&lt;channel-number&gt;] [&lt;rpcport&gt;]<br/>
         Get description of configuration parameters for CCU device.
      </li><br/>
      <li>get &lt;name&gt; defaults<br/>
      	Display default attributes for CCU device type.
      </li><br/>
      <li>get &lt;name&gt; update [{'State'|'Value'}]<br/>
         Update datapoints / readings of device.
      </li><br/>
      <li>get &lt;name&gt; deviceinfo [{'State'|'Value'}]<br/>
         Display all channels and datapoints of device.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccuget &lt;State | <u>Value</u>&gt;<br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value' because
         each request is sent to the device. With method 'Value' only CCU is queried. Default is 'Value'.
      </li><br/>
      <li>ccureadings &lt;0 | <u>1</u>&gt;<br/>
         If set to 1 values read from CCU will be stored as readings. Default is 1.
      </li><br/>
      <li>ccureadingfilter &lt;filter-rule[,...]&gt;<br/>
         Only datapoints matching specified expression are stored as readings.
         Syntax for filter rule is: [channel-no:]RegExp<br/>
         If channel-no is specified the following rule applies only to this channel.
      </li><br/>
      <li>ccureadingformat &lt;address | name&gt; <br/>
         Set format of readings. Default is 'name'.
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
      <li>controldatapoint &lt;channel-number.datapoint&gt;<br/>
         Set datapoint for device control. Can be use to realize user defined control elements for
         setting control datapoint. For example if datapoint of thermostat control is
         2.SET_TEMPERATURE one can define a slider for setting the destination temperature with
         following attributes:<br/><br/>
         attr mydev controldatapoint 2.SET_TEMPERATURE
         attr mydev webCmd control
         attr mydev widgetOverride control:slider,10,1,25
      </li><br/>
      <li>disable &lt;0 | 1&gt;<br/>
         Disable client device.
      </li><br/>
      <li>mapdatapoints &lt;channel.datapoint&gt;=&lt;channel.datapoint&gt;[,...]
         Map channel to other channel in virtual devices (groups). Readings will be duplicated.
      </li><br/>
      <li>statechannel &lt;channel-number&gt;<br/>
         Channel for setting device state by devstate command.
      </li><br/>
      <li>statedatapoint &lt;datapoint&gt;<br/>
         Datapoint for setting device state by devstate command.
      </li><br/>
      <li>statevals &lt;text&gt;:&lt;text&gt;[,...]<br/>
         Define substitution for set commands values. The parameters &lt;text&gt;
         are available as set commands. Example:<br/>
         <code>attr my_switch statevals on:true,off:false</code><br/>
         <code>set my_switch on</code>
      </li><br/>
      <li>substitute &lt;subst-rule&gt;[;...]<br/>
         Define substitutions for reading values. Substitutions for parfile values must
         be specified in parfiles. Syntax of subst-rule is<br/><br/>
         [datapoint!]&lt;regexp&gt;:&lt;text&gt;[,...]
      </li><br/>
   </ul>
</ul>

=end html
=cut


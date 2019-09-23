##############################################################################
#
#  89_FULLY.pm 1.35
#
#  $Id$
#
#  Control Fully browser on Android tablets from FHEM.
#  Requires Fully App Plus license!
#
#  (c) 2019 by zap (zap01 <at> t-online <dot> de)
#
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;
use SetExtensions;

# Declare functions
sub FULLY_Initialize ($);
sub FULLY_Define ($$);
sub FULLY_Undef ($$);
sub FULLY_Shutdown ($);
sub FULLY_Set ($@);
sub FULLY_Get ($@);
sub FULLY_Attr ($@);
sub FULLY_Detail ($@);
sub FULLY_UpdateDeviceInfo ($);
sub FULLY_Execute ($$$$);
sub FULLY_ExecuteNB ($$$$);
sub FULLY_ExecuteCB ($$$);
sub FULLY_ScreenOff ($);
sub FULLY_GetDeviceInfo ($);
sub FULLY_ProcessDeviceInfo ($$);
sub FULLY_UpdateReadings ($$);
sub FULLY_Ping ($$);

my $FULLY_VERSION = "1.35";

# Timeout for Fully requests
my $FULLY_TIMEOUT = 5;

# Polling interval
my $FULLY_POLL_INTERVAL = 3600;
my @FULLY_POLL_RANGE = (10, 86400);

# Minimum version of Fully app
my $FULLY_REQUIRED_VERSION = 1.27;

# Default protocol and port for Fully requests
my $FULLY_DEFAULT_PROT = 'http';
my $FULLY_DEFAULT_PORT = '2323';

# Code for Fully Javascript injection. Not implemented because of problems with Tablet UI.
my $FULLY_FHEM_COMMAND = qq(
function SendRequest(FHEM_Address, Devicename, Command) {
	var Port = "8085"

	var url =  "http://" + FHEM_Address + ":" + Port + "/fhem?XHR=1&cmd." + Devicename + "=" + Command;
	
	var req = new XMLHttpRequest();
	req.open("GET", url);
	req.send(null);	
	
	req = null;
}
);

######################################################################
# Initialize module
######################################################################

sub FULLY_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "FULLY_Define";
	$hash->{UndefFn} = "FULLY_Undef";
	$hash->{SetFn} = "FULLY_Set";
	$hash->{GetFn} = "FULLY_Get";
	$hash->{AttrFn} = "FULLY_Attr";
	$hash->{ShutdownFn} = "FULLY_Shutdown";
	$hash->{FW_detailFn} = "FULLY_Detail";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "pingBeforeCmd:0,1,2 pollInterval requestTimeout repeatCommand:0,1,2 " .
		"disable:0,1 expert:0,1 waitAfterPing:0,1,2" .
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub FULLY_Define ($$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $rc = 0;
	
	return "Usage: define devname [http|https]://IP_or_Hostname password [poll-interval]"
		if (@$a < 4);
	return "FULLY: polling interval must be in range ".$FULLY_POLL_RANGE[0]."-".$FULLY_POLL_RANGE[1]
		if (@$a == 5 &&
		   ($$a[4] !~ /^[1-9][0-9]+$/ || $$a[4] < $FULLY_POLL_RANGE[0] || $$a[4] > $FULLY_POLL_RANGE[1]));

	if ($$a[2] =~ /^(https?):\/\/(.+)/) {
		$hash->{prot} = $1;
		$hash->{host} = $2;
	}
	else {
		$hash->{prot} = $FULLY_DEFAULT_PROT;
		$hash->{host} = $$a[2];
	}

	$hash->{port} = $FULLY_DEFAULT_PORT;
	$hash->{version} = $FULLY_VERSION;
	$hash->{onForTimer} = 'off';
	$hash->{fully}{password} = $$a[3];
	$hash->{fully}{schedule} = 0;

	Log3 $name, 1, "FULLY: [$name] Version $FULLY_VERSION Opening device ".$hash->{host};
	
	FULLY_GetDeviceInfo ($name);

	if (@$a == 5) {
		$attr{$name}{'pollInterval'} = $$a[4];
		$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$$a[4]);
		InternalTimer (gettimeofday()+$$a[4], "FULLY_UpdateDeviceInfo", $hash, 0);
	}
	else {
		$hash->{nextUpdate} = 'off';
	}

	return undef;
}

######################################################################
# Set or delete attribute
######################################################################

sub FULLY_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if ($cmd eq 'set') {
		if ($attrname eq 'pollInterval') {
			if ($attrval >= $FULLY_POLL_RANGE[0]  && $attrval <= $FULLY_POLL_RANGE[1]) {
				my $curval = AttrVal ($name, 'pollInterval', $FULLY_POLL_INTERVAL);
				if ($attrval != $curval) {
					Log3 $name, 2, "FULLY: [$name] Polling interval set to $attrval";
					RemoveInternalTimer ($hash);
					$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$attrval);
					InternalTimer (gettimeofday()+$attrval, "FULLY_UpdateDeviceInfo", $hash, 0);
				}
			}
			elsif ($attrval == 0) {
				RemoveInternalTimer ($hash);
				$hash->{nextUpdate} = 'off';
			}
			else {
				return "FULLY: Polling interval must be in range ".$FULLY_POLL_RANGE[0]."-".$FULLY_POLL_RANGE[1];
			}
		}
		elsif ($attrname eq 'requestTimeout') {
			return "FULLY: Timeout must be greater than 0" if ($attrval < 1);
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'pollInterval') {
				RemoveInternalTimer ($hash);
				$hash->{nextUpdate} = 'off';			
		}
	}
	
	return undef;
}

######################################################################
# Delete device
######################################################################

sub FULLY_Undef ($$)
{
	my ($hash, $arg) = @_;

	RemoveInternalTimer ($hash);
	
	return undef;
}

######################################################################
# Shutdown FHEM
######################################################################

sub FULLY_Shutdown ($)
{
	my ($hash) = @_;

	RemoveInternalTimer ($hash);

	return undef;
}

######################################################################
# Enhance device detail view
######################################################################

sub FULLY_Detail ($@)
{
	my ($FW_wname, $name, $room, $pageHash) = @_;
	my $hash = $defs{$name};
	
	my $html = qq(
	<span class='mkTitle'>Device Administration</span>
	<table class="block wide">
	<tr class="odd">
	<td><div class="col1">
	<a target="_blank" href="$hash->{prot}://$hash->{host}:$hash->{port}">Remote Admin</a>
	</div></td>
	</tr>
	</table>
	);
	
	return $html;
}
	
######################################################################
# Set commands
######################################################################

sub FULLY_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;
	my $options = "brightness photo:noArg clearCache:noArg exit:noArg lock:noArg motionDetection:on,off ".
		"off:noArg on:noArg on-for-timer playSound restart:noArg screenOffTimer screenSaver:start,stop ".
		"screenSaverTimer screenSaverURL speak startURL stopSound:noArg unlock:noArg url ".
		"volume";
	
	# Fully commands without argument
	my %cmds = (
		"clearCache" => "clearCache",
		"photo" => "getCamshot",
		"exit" => "exitApp",
		"restart" => "restartApp",
		"on" => "screenOn", "off" => "screenOff",
		"lock" => "enabledLockedMode", "unlock" => "disableLockedMode",
		"stopSound" => "stopSound"
	);
	
	my @c = ();
	my @p = ();
	
	my $disable = AttrVal ($name, 'disable', 0);
	return undef if ($disable);
	my $expert = AttrVal ($name, 'expert', 0);
	$options .= " setStringSetting setBooleanSetting" if ($expert);
	
	if (exists ($cmds{$opt})) {
		push (@c, $cmds{$opt});
	}
	elsif ($opt eq 'on-for-timer') {
		my $par = shift @$a;
		$par = "forever" if (!defined ($par));

		if ($par eq 'forever') {
			push (@c, "setBooleanSetting", "screenOn");
			push (@p, { "key" => "keepScreenOn", "value" => "true" }, undef);
			RemoveInternalTimer ($hash, "FULLY_ScreenOff");
		}
		elsif ($par eq 'off') {
			push (@c, "setBooleanSetting", "setStringSetting");
			push (@p, { "key" => "keepScreenOn", "value" => "false" },
				{ "key" => "timeToScreenOffV2", "value" => "0" });
			RemoveInternalTimer ($hash, "FULLY_ScreenOff");
		}
		elsif ($par =~ /^[0-9]+$/) {
			push (@c, "setBooleanSetting", "screenOn");
			push (@p, { "key" => "keepScreenOn", "value" => "false" }, undef);
			InternalTimer (gettimeofday()+$par, "FULLY_ScreenOff", $hash, 0);
		}
		else {
			return "Usage: set $name on-for-timer [{ Seconds | forever | off }]";
		}
		
		$hash->{onForTimer} = $par;
	}
	elsif ($opt eq 'screenOffTimer') {
		my $value = shift @$a;
		return "Usage: set $name $opt {seconds}" if (!defined ($value));
		push (@c, "setStringSetting");
		push (@p, { "key" => "timeToScreenOffV2", "value" => "$value" });
	}
	elsif ($opt eq 'screenSaver') {
		my $state = shift @$a;
		return "Usage: set $name $opt { start | stop }" if (!defined ($state) || $state !~ /^(start|stop)$/);
		push (@c, ($state eq 'start') ? "startScreensaver" : "stopScreensaver");
	}
	elsif ($opt eq 'screenSaverTimer') {
		my $value = shift @$a;
		return "Usage: set $name $opt {seconds}" if (!defined ($value));
		push (@c, "setStringSetting");
		push (@p, { "key" => "timeToScreensaverV2", "value" => "$value" });
	}
	elsif ($opt eq 'screenSaverURL') {
		my $value = shift @$a;
		return "Usage: set $name $opt {URL}" if (!defined ($value));
		push (@c, "setStringSetting");
		push (@p, { "key" => "screensaverURL", "value" => "$value" });
	}
	elsif ($opt eq 'startURL') {
		my $value = shift @$a;
		return "Usage: set $name $opt {URL}" if (!defined ($value));
		push (@c, "setStringSetting");
		push (@p, { "key" => "startURL", "value" => "$value" });
	}
	elsif ($opt eq 'brightness') {
		my $value = shift @$a;
		return "Usage: set $name brightness 0-255" if (!defined ($value));
		$value = 255 if ($value > 255);
		push (@c, "setStringSetting");
		push (@p, { "key" => "screenBrightness", "value" => "$value" });
	}
	elsif ($opt eq 'motionDetection') {
		my $state = shift @$a;
		return "Usage: set $name motionDetection { on | off }" if (!defined ($state));
		my $value = $state eq 'on' ? 'true' : 'false';
		push (@c, "setBooleanSetting");
		push (@p, { "key" => "motionDetection", "value" => "$value" });
	}
	elsif ($opt eq 'speak') {
		my $text = shift @$a;
		return 'Usage: set $name speak "{Text}"' if (!defined ($text));
		while ($text =~ /\[(.+):(.+)\]/) {
			my ($device, $reading) = ($1, $2);
			my $value = ReadingsVal ($device, $reading, '');
			$text =~ s/\[$device:$reading\]/$value/g;
		}
		my $enctext = urlEncode ($text);
		push (@c, "textToSpeech");
		push (@p, { "text" => "$enctext" });
	}
	elsif ($opt eq 'playSound') {
		my $url = shift @$a;
		my $loop = shift @$a;
		$loop = defined ($loop) ? 'true' : 'false';
		return "Usage: set $name playSound {url} [loop]" if (!defined ($url));
		push (@c, "playSound");
		push (@p, { "url" => "$url", "loop" => "$loop"});
	}
	elsif ($opt eq 'volume') {
		my $level = shift @$a;
		my $stream = shift @$a;
		return "Usage: set $name volume {level} {stream}"
			if (!defined ($stream) || $level !~ /^[0-9]+$/ || $stream !~ /^[0-9]+$/);
		push (@c, "setAudioVolume");
		push (@p, { "level" => "$level", "stream" => "$stream"});
	}
	elsif ($opt eq 'url') {
		my $url = shift @$a;
		if (defined ($url)) {
			push (@c, "loadURL");
			push (@p, { "url" => "$url" });
		}
		else {
			push (@c, "loadStartURL");
		}
	}
	elsif ($opt eq 'setStringSetting' || $opt eq 'setBooleanSetting') {
		return "FULLY: Command $opt only available in expert mode" if ($expert == 0);
		my $key = shift @$a;
		my $value = shift @$a;
		return "Usage: set $name $opt {key} {value}" if (!defined ($value));
		push (@c, $opt);
		push (@p, { "key" => "$key", "value" => "$value" });
	}
	else {
		return "FULLY: Unknown argument $opt, choose one of ".$options;
	}
	
	# Execute command requests
	FULLY_ExecuteNB ($hash, \@c, \@p, 1) if (scalar (@c) > 0);
	
	return undef;
}

######################################################################
# Get commands
######################################################################

sub FULLY_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;
	my $options = "info:noArg stats:noArg update:noArg";
	my $response;
	
	my $disable = AttrVal ($name, 'disable', 0);
	return undef if ($disable);
	
	if ($opt eq 'info') {
		my $result = FULLY_Execute ($hash, 'deviceInfo', undef, 1);
		if (!defined ($result) || $result eq '') {
			Log3 $name, 2, "FULLY: [$name] Command failed";
			return "FULLY: Command failed";
		}
		elsif ($result =~ /Wrong password/) {
			Log3 $name, 2, "FULLY: [$name] Wrong password";
			return "FULLY: Wrong password";
		}

		$response = '';
#		while ($result =~ /table-cell.>([^<]+)<\/td><td class=.table-cell.>([^<]+)</g) {
		while ($result =~ /table-cell.>([^<]+)<\/td><td class=.table-cell.>(.*?)<\/td>/g) {
			my ($in, $iv) = ($1, $2);
			if ($iv =~ /^<a .*?>(.*?)<\/a>/) {
				$iv = $1;
			}
			elsif ($iv =~ /(.*?)</) {
				$iv = $1;
			}
			$iv =~ s/[ ]+$//;
			$response .= "$in = $iv<br/>\n";
		}
		
		return $response;
	}
	elsif ($opt eq 'stats') {
		return "FULLY: Command not implemented";
	}
	elsif ($opt eq 'update') {
		FULLY_GetDeviceInfo ($name);
	}
	else {
		return "FULLY: Unknown argument $opt, choose one of ".$options;
	}

	return undef;
}

######################################################################
# Execute Fully command
######################################################################

sub FULLY_Execute ($$$$)
{
	my ($hash, $command, $param, $doping) = @_;
	my $name = $hash->{NAME};

	# Get attributes
	my $timeout = AttrVal ($name, 'requestTimeout', $FULLY_TIMEOUT);
	my $repeatCommand = min (AttrVal ($name, 'repeatCommand', 0), 2);
	my $ping = min (AttrVal ($name, 'pingBeforeCmd', 0), 2);
	
	my $response = '';
	my $url = $hash->{prot}.'://'.$hash->{host}.':'.$hash->{port}."/?cmd=$command";
	
	if (defined ($param)) {
		foreach my $parname (keys %$param) {
			if (defined ($param->{$parname})) {
				$url .= "&$parname=".$param->{$parname};
			}
		}
	}

	# Ping tablet device
	FULLY_Ping ($hash, $ping) if ($doping && $ping > 0);
	
	my $i = 0;
	while ($i <= $repeatCommand && (!defined ($response) || $response eq '')) {
		$response = GetFileFromURL ("$url&password=".$hash->{fully}{password}, $timeout);
		Log3 $name, 4, "FULLY: [$name] HTTP response empty" if (defined ($response) && $response eq '');
		$i++;
	}
	
	return $response;
}

######################################################################
# Execute Fully commands non blocking
######################################################################

sub FULLY_ExecuteNB ($$$$)
{
	my ($hash, $command, $param, $doping) = @_;
	my $name = $hash->{NAME};

	# Get attributes
	my $timeout = AttrVal ($name, 'requestTimeout', $FULLY_TIMEOUT);
	my $repeatCommand = min (AttrVal ($name, 'repeatCommand', 0), 2);
	my $ping = min (AttrVal ($name, 'pingBeforeCmd', 0), 2);

	my @urllist;
	my $nc = scalar (@$command);	
	for (my $i=0; $i<$nc; $i++) {
		my $url = $hash->{prot}.'://'.$hash->{host}.':'.$hash->{port}."/?cmd=".$$command[$i];
	
		if (defined ($param) && defined ($$param[$i])) {
			foreach my $parname (keys %{$$param[$i]}) {
				if (defined ($$param[$i]->{$parname})) {
					$url .= "&$parname=".$$param[$i]->{$parname};
				}
			}
		}
		
		Log3 $name, 4, "FULLY: [$name] Pushing $url on command stack";
		push (@urllist, "$url&password=".$hash->{fully}{password});
	}

	# Ping tablet device
	FULLY_Ping ($hash, $ping) if ($doping && $ping > 0);
	
	my $reqpar = {
		url => $urllist[0],
		orgurl => $urllist[0],
		urllist => [@urllist],
		timeout => $timeout,
		method => "GET",
		hash => $hash,
		cmdno => 1,
		cmdcnt => $nc,
		repeat => $repeatCommand,
		execcnt => 0,
		callback => \&FULLY_ExecuteCB
	};

	Log3 $name, 4, "FULLY: [$name] Executing command ".$urllist[0];
	HttpUtils_NonblockingGet ($reqpar);
}

######################################################################
# Callback function for non blocking requests
######################################################################

sub FULLY_ExecuteCB ($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	if ($err eq '') {
		if ($param->{cmdno} == $param->{cmdcnt}) {
			# Last request, update readings
			Log3 $name, 4, "FULLY: [$name] Last command executed. Processing results";
			Log3 $name, 5, "FULLY: [$name] $data";
			my $result = FULLY_ProcessDeviceInfo ($name, $data);
			Log3 $name, 4, "FULLY: [$name] $result";
			if (!FULLY_UpdateReadings ($hash, $result)) {
				Log3 $name, 2, "FULLY: [$name] Command failed";
			}
		}
		else {
			# Execute next request
			my @urllist = @{$param->{urllist}};
			my $reqpar = {
				url => $urllist[$param->{cmdno}],
				orgurl => $urllist[$param->{cmdno}],
				urllist => $param->{urllist},
				timeout => $param->{timeout},
				method => "GET",
				hash => $hash,
				cmdno => $param->{cmdno}+1,
				cmdcnt => $param->{cmdcnt},
				repeat => $param->{repeat},
				execcnt => 0,
				callback => \&FULLY_ExecuteCB
			};

			Log3 $name, 4, "FULLY: [$name] Executing command ".$urllist[$param->{cmdno}];
			HttpUtils_NonblockingGet ($reqpar);
		}
	}
	else {
		# Repeat failed request
		if ($param->{execcnt} < $param->{repeat}) {
			my $reqpar = {
				url => $param->{orgurl},
				orgurl => $param->{orgurl},
				urllist => $param->{urllist},
				timeout => $param->{timeout},
				method => "GET",
				hash => $hash,
				cmdno => $param->{cmdno},
				cmdcnt => $param->{cmdcnt},
				repeat => $param->{repeat},
				execcnt => $param->{execcnt}+1,
				callback => \&FULLY_ExecuteCB
			};

			Log3 $name, 4, "FULLY: [$name] Repeating command ".$param->{orgurl};
			HttpUtils_NonblockingGet ($reqpar);
		}
		else {
			Log3 $name, 2, "FULLY: [$name] Error during request. $err";
		}
	}
}

######################################################################
# Timer function: Turn screen off
######################################################################

sub FULLY_ScreenOff ($)
{
	my ($hash) = @_;
	
	my @c = ("setBooleanSetting", "screenOff");
	my @p = ({ "key" => "keepScreenOn", "value" => "false" }, undef);
	FULLY_ExecuteNB ($hash, \@c, \@p, 1);
	$hash->{onForTimer} = 'off';
}

######################################################################
# Timer function: Read device info
######################################################################

sub FULLY_UpdateDeviceInfo ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $disable = AttrVal ($name, 'disable', 0);
	return if ($disable);
	
	my $pollInterval = AttrVal ($name, 'pollInterval', $FULLY_POLL_INTERVAL);

	my @c = ("deviceInfo");
	
	FULLY_ExecuteNB ($hash, \@c, undef, 1);

	if ($pollInterval > 0) {
		$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$pollInterval);
		InternalTimer (gettimeofday()+$pollInterval, "FULLY_UpdateDeviceInfo", $hash, 0);
	}
	else {
		$hash->{nextUpdate} = "none";
	}
}

######################################################################
# Get tablet device information
######################################################################

sub FULLY_GetDeviceInfo ($)
{
	my ($name) = @_;
	my $hash = $defs{$name};
	
	my @c = ("deviceInfo");
	FULLY_ExecuteNB ($hash, \@c, undef, 1);
}

######################################################################
# Extract parameters from HTML code
######################################################################

sub FULLY_ProcessDeviceInfo ($$)
{
	my ($name, $result) = @_;

	return "$name|0|state=failed" if (!defined ($result) || $result eq '');
	return "$name|0|state=wrong password" if ($result =~ /Wrong password/);
	
	# HTML code format
	# <td class='table-cell'>Kiosk mode</td><td class='table-cell'>off</td>
	
	my $parameters = "$name|1";
	while ($result =~ /table-cell.>([^<]+)<\/td><td class=.table-cell.>(.*?)<\/td>/g) {
		my $rn = lc($1);
		my $rv = $2;
		
		if ($rv =~ /^<a .*?>(.*?)<\/a>/) {
			$rv = $1;
		}
		elsif ($rv =~ /(.*?)</) {
			$rv = $1;
		}
		$rv =~ s/[ ]+$//;
		
		$rv =~ s/\s+$//;
		$rn =~ s/\:/\./g;
		$rn =~ s/[^A-Za-z\d_\.-]+/_/g;
		$rn =~ s/[_]+$//;
		next if ($rn eq 'webview_ua');
		if ($rn eq 'battery_level') {
			if ($rv =~ /^([0-9]+)% \(([^\)]+)\)$/) {
				$parameters .= "|$rn=$1|power=$2";
				next;
			}
		}
		elsif ($rn eq 'screen_brightness') {
			$rn = "brightness";
		}
		elsif ($rn eq 'screen_status') {
			$parameters .= "|state=$rv";
		}
		elsif ($rn eq 'fully_version') {
			if ($rv =~ /^([0-9]\.[0-9]+).*/) {
				my $cv = $1;
				Log3 $name, 1, "FULLY: [$name] Version of fully browser is $rv. Version $FULLY_REQUIRED_VERSION is required."
					if ($cv < $FULLY_REQUIRED_VERSION);
			}
			else {
				Log3 $name, 2, "FULLY: [$name] Cannot detect version of fully browser.";
			}
		}
		$parameters .= "|$rn=$rv";
	}
	
	return $parameters;
}

######################################################################
# Update readings
######################################################################

sub FULLY_UpdateReadings ($$)
{
	my ($hash, $result) = @_;
	my $name = $hash->{NAME};
	my $rc = 1;

	if (!defined ($result) || $result eq '') {
		Log3 $name, 2, "FULLY: [$name] empty response";
		return 0;
	}
	
	my @parameters = split ('\|', $result);
	if (scalar (@parameters) == 0) {
		Log3 $name, 2, "FULLY: [$name] empty response";
		return 0;
	}
	
	if ($parameters[0] eq $name) {
		my $n = shift @parameters;
		$rc = shift @parameters;
	}
	
	readingsBeginUpdate ($hash);
	foreach my $parval (@parameters) {
		my ($rn, $rv) = split ('=', $parval);
		readingsBulkUpdate ($hash, $rn, $rv);
	}
	readingsEndUpdate ($hash, 1);
	
	return $rc;	
}

######################################################################
# Send ICMP request to tablet device
# Adapted from presence module.
# Thx Markus.
######################################################################

sub FULLY_Ping ($$)
{
	my ($hash, $count) = @_;
	my $name = $hash->{NAME};
	my $host = $hash->{host};
	my $temp;

	my $waitAfterPing = min (AttrVal ($name, 'waitAfterPing', 0), 2);
	
	my $os = $^O;
	Log3 $name, 4, "FULLY: [$name] Sending $count ping request(s) to tablet $host. OS=$os";
	
	if ($^O =~ m/(Win|cygwin)/) {
		$temp = qx(ping -n $count -4 $host >nul);
	}
	elsif ($^O =~ m/solaris/) {
		$temp = qx(ping $host $count 2>&1 >/dev/null);
	}
	elsif ($^O =~ m/darwin/) {
		$temp = qx(ping -c $count -t 1 $host 2>&1 >/dev/null);
	}
	else {
		$temp = qx(ping -c $count -W 1 $host 2>&1 >/dev/null);
	}
	
	sleep ($waitAfterPing) if ($waitAfterPing > 0);
	
	return $temp;
}

1;


=pod
=item device
=item summary FULLY Browser Integration
=begin html

<a name="FULLY"></a>
<h3>FULLY</h3>
<ul>
   Module for controlling of Fully browser on Android tablets. Requires a Plus license
   of Fully browser app. Remote device management and remote admin in local network
   must be enabled in Fully app. Requires Fully app version 1.27 or later.
   </br></br>
   
   <a name="HMCCUdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; FULLY [&lt;Protocol&gt;://]&lt;HostOrIP&gt; &lt;password&gt; [&lt;poll-interval&gt;]</code>
      <br/><br/>
	  The parameter <i>password</i> is the password set in Fully browser. Parameter <i>Protocol</i> is
	  optional. Valid protocols are 'http' and 'https'. Default protocol is 'http'. 
   </ul>
   <br/>
   
   <a name="FULLYset"></a>
   <b>Set</b><br/><br/>
   <ul>
		<li><b>set &lt;name&gt; brightness 0-255</b><br/>
			Adjust screen brightness.
		</li><br/>
		<li><b>set &lt;name&gt; clearCache</b><br/>
			Clear browser cache.
		</li><br/>
		<li><b>set &lt;name&gt; exit</b><br/>
			Terminate Fully.
		</li><br/>
		<li><b>set &lt;name&gt; motionDetection { on | off }</b><br/>
			Turn motion detection by camera on or off.
		</li><br/>
		<li><b>set &lt;name&gt; { lock | unlock }</b><br/>
			Lock or unlock display.
		</li><br/>
		<li><b>set &lt;name&gt; { on | off }</b><br/>
			Turn tablet display on or off.
		</li><br/>
		<li><b>set &lt;name&gt; on-for-timer [{ &lt;Seconds&gt; | <u>forever</u> | off }]</b><br/>
			Set timer for display. Default is forever.
		</li><br/>
		<li><b>set &lt;name&gt; photo</b><br/>
			Take a picture with device cam. Setting motion detection must be enabled. Picture
			can be viewed in remote admin interface under device info.
		</li><br/>
		<li><b>set &lt;name&gt; playSound &lt;url&gt; [loop]</b><br/>
			Play sound from URL.
		</li><br/>
		<li><b>set &lt;name&gt; restart</b><br/>
			Restart Fully.
		</li><br/>
		<li><b>set &lt;name&gt; screenOffTimer &lt;seconds&gt;</b><br/>
			Turn screen off after some idle seconds, set to 0 to disable timer.
		</li><br/>
		<li><b>set &lt;name&gt; screenSaver { start | stop }</b><br/>
		   Start or stop screen saver. Screen saver URL can be set with command <b>set screenSaverURL</b>.
		</li><br/>
		<li><b>set &lt;name&gt; screenSaverTimer &lt;seconds&gt;</b><br/>
			Show screen saver URL after some idle seconds, set to 0 to disable timer.
		</li><br/>
		<li><b>set &lt;name&gt; screenSaverURL &lt;URL&gt;</b><br/>
			Show this URL when screensaver starts, set daydream: for Android daydream or dim: for black.<br/>
		</li><br/>
		<li><b>set &lt;name&gt; setBooleanSetting &lt;Key&gt; &lt;Value&gt;</b><br/>
			Set boolean value in Fully app. Command is ony available if attribute expert is 1.
			Valid keys can be found in Fully remote admin interface.
		</li><br/>
		<li><b>set &lt;name&gt; setStringSetting &lt;Key&gt; &lt;Value&gt;</b><br/>
			Set string value in Fully app. Command is ony available if attribute expert is 1.
			Valid keys can be found in Fully remote admin interface.
		</li><br/>
		<li><b>set &lt;name&gt; speak &lt;text&gt;</b><br/>
			Audio output of <i>text</i>. If <i>text</i> contains blanks it must be enclosed
			in double quotes. The text can contain device readings in format [device:reading].
		</li><br/>
		<li><b>set &lt;name&gt; startURL &lt;URL&gt;</b><br/>
			Show this URL when FULLY starts.<br/>
		</li><br/>
		<li><b>set &lt;name&gt; stopSound</b><br/>
			Stop playback of sound if playback has been started with option <i>loop</i>.
		</li><br/>
		<li><b>set &lt;name&gt; url [&lt;URL&gt;]</b><br/>
			Navigate to <i>URL</i>. If no URL is specified navigate to start URL.
		</li><br/>
		<li><b>set &lt;name&gt; volume &lt;level&gt; &lt;stream&gt;</b><br/>
			Set audio volume. Range of parameter <i>level</i> is 0-100, range of parameter
			<i>stream</i> is 1-10. 
		</li><br/>
   </ul>
   <br/>
   
   <a name="FULLYget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; info</b><br/>
      	Display Fully information. This is command blocks FHEM until completion.
      </li><br/>
      <li><b>get &lt;name&gt; stats</b><br/>
      	Show Fully statistics.
      </li><br/>
      <li><b>get &lt;name&gt; update</b><br/>
      	Update readings.
      </li><br/>
   </ul>
   <br/>
   
   <a name="FULLYattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li><b>disable &lt;0 | 1&gt;</b><br/>
      	Disable device and automatic polling.
      </li><br/>
      <li><b>expert &lt;0 | 1&gt;</b><br/>
      	Activate expert mode.
      </li><br/>
   	<li><b>pingBeforeCmd &lt;Count&gt;</b><br/>
   		Send <i>Count</i> ping request to tablet before executing commands. Valid values 
   		for <i>Count</i> are 0,1,2. Default is 0 (do not send ping request).
   	</li><br/>
      <li><b>pollInterval &lt;seconds&gt;</b><br/>
         Set polling interval for FULLY device information.
         If <i>seconds</i> is 0 polling is turned off. Valid values are from 10 to
         86400 seconds.
      </li><br/>
      <li><b>repeatCommand &lt;Count&gt;</b><br/>
         Repeat fully command on failure. Valid values for <i>Count</i> are 0,1,2. Default
         is 0 (do not repeat commands).
      </li><br/>
      <li><b>requestTimeout &lt;seconds&gt;</b><br/>
         Set timeout for http requests. Default is 5 seconds.
      </li><br/>
      <li><b>waitAfterPing &lt;Seconds&gt;</b><br/>
      	Wait specified amount of time after sending ping request to tablet device. Valid
      	values for <i>Seconds</i> are 0,1,2. Default is 0 (do not wait). Only used if
      	attribute pingBeforeCmd is greater than 0.
      </li><br/>
   </ul>
</ul>

=end html
=cut


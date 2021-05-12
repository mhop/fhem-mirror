##############################################################################
#
#  89_FULLY.pm 2.2
#
#  $Id$
#
#  Control Fully browser on Android tablets from FHEM.
#  Requires Fully App Plus license!
#
#  This program free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License V2.
#
#  (c) 2021 by zap (zap01 <at> t-online <dot> de)
#
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;
use JSON;
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
sub FULLY_Notify ($$);
sub FULLY_UpdateDeviceInfo ($);
sub FULLY_Execute ($$$$);
sub FULLY_ExecuteNB ($$$$);
sub FULLY_ExecuteCB ($$$);
sub FULLY_ScreenOff ($);
sub FULLY_GetDeviceInfo ($);
sub FULLY_UpdateReadings ($$);
sub FULLY_Encrypt ($);
sub FULLY_Decrypt ($);
sub FULLY_Ping ($$);
sub FULLY_SetPolling ($$;$);

my $FULLY_VERSION = '2.2';

# Timeout for Fully requests
my $FULLY_TIMEOUT = 5;

# Polling interval
my $FULLY_POLL_INTERVAL = 3600;
my @FULLY_POLL_RANGE = (10, 86400);

# Minimum version of Fully app
my $FULLY_REQUIRED_VERSION = 1.42;

# Default protocol and port for Fully requests
my $FULLY_DEFAULT_PROT = 'http';
my $FULLY_DEFAULT_PORT = '2323';



######################################################################
# Initialize module
######################################################################

sub FULLY_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn}       = "FULLY_Define";
	$hash->{UndefFn}     = "FULLY_Undef";
	$hash->{SetFn}       = "FULLY_Set";
	$hash->{GetFn}       = "FULLY_Get";
	$hash->{AttrFn}      = "FULLY_Attr";
	$hash->{NotifyFn}    = "FULLY_Notify";
	$hash->{ShutdownFn}  = "FULLY_Shutdown";
	$hash->{FW_detailFn} = "FULLY_Detail";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "pingBeforeCmd:0,1,2 pollInterval:slider,10,10,86400 requestTimeout:slider,1,1,20 repeatCommand:0,1,2 " .
		"disable:0,1 expert:0,1 waitAfterPing:0,1,2 updateAfterCommand:0,1 " .
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub FULLY_Define ($$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $host = '';
	
	return "Usage: define devname FULLY [http|https]://IP_or_Hostname [password] [poll-interval]"
		if (@$a < 3);

	if ($$a[2] =~ /^(https?):\/\/(.+)/) {
		$hash->{prot} = $1;
		$host = $2;
	}
	else {
		$hash->{prot} = $FULLY_DEFAULT_PROT;
		$host = $$a[2];
	}

	if ($host =~ /^([^:]+):([0-9]+)$/) {
		$hash->{host} = $1;
		$hash->{port} = $2;
	}
	else {
		$hash->{host} = $host;
		$hash->{port} = $FULLY_DEFAULT_PORT;
	}

	$hash->{version}         = $FULLY_VERSION;
	$hash->{NOTIFYDEV}       = 'global,TYPE=FULLY';
	$hash->{onForTimer}      = 'off';
	$hash->{nextUpdate}      = 'off';
	$hash->{fully}{schedule} = 0;
	
	if (@$a == 4) {
		if ($$a[3] =~ /^[0-9]+$/) {
			$hash->{fully}{interval} = $$a[3];
		}
		else {
			$hash->{fully}{password} = $$a[3];
		}
	}
	elsif (@$a == 5) {
		$hash->{fully}{password} = $$a[3];
		$hash->{fully}{interval} = $$a[4];
	}

	if (!exists($hash->{fully}{password})) {
		my ($errpass, $encpass) = getKeyValue ($name.'_password');
		if (!defined($errpass) && defined($encpass)) {
			$hash->{fully}{password} = FULLY_Decrypt ($encpass);
		}
		else {
			FULLY_Log ($hash, 2, "Fully password not defined");
		}
	}

	if (!$init_done && exists($hash->{fully}{password})) {
		FULLY_Log ($hash, 1, "Version $FULLY_VERSION Opening device ".$hash->{host});
		FULLY_GetDeviceInfo ($name);
		if (exists($hash->{fully}{interval})) {
			FULLY_SetPolling ($hash, 1, $hash->{fully}{interval});
		}
	}
	
	if ($init_done && !exists($hash->{fully}{password}) && exists($hash->{CL})) {
		asyncOutput ($hash->{CL}, "Please use command 'set $name authentication' to set the Fully password");
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
				FULLY_SetPolling ($hash, 1, $attrval);
			}
			elsif ($attrval == 0) {
				FULLY_SetPolling ($hash, 0);
			}
			else {
				return "FULLY: Polling interval must be in range ".$FULLY_POLL_RANGE[0]."-".$FULLY_POLL_RANGE[1];
			}
		}
		elsif ($attrname eq 'requestTimeout') {
			return "FULLY: Timeout must be greater than 0" if ($attrval < 1);
		}
		elsif ($attrname eq 'disable') {
			if ($attrval eq '0') {
				# Set the polling interval to default or the value specified in pollInterval
				FULLY_Log ($hash, 2, "Device activated");
				FULLY_SetPolling ($hash, 1);
			}
			elsif ($attrval eq '1') {
				FULLY_SetPolling ($hash, 0);
				FULLY_Log ($hash, 2, "Device deactivated");
			}
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'pollInterval') {
			# Set the polling interval to default
			FULLY_SetPolling ($hash, 1);
		}
		elsif ($attrname eq 'disable') {
			# Set the polling interval to default or the value specified in pollInterval
			FULLY_Log ($hash, 2, "Device activated");
			FULLY_SetPolling ($hash, 1);
		}
	}
	
	return undef;
}

######################################################################
# Set polling on or off
######################################################################

sub FULLY_SetPolling ($$;$)
{
	my ($hash, $mode, $interval) = @_;
	my $name = $hash->{NAME};
	$interval //= AttrVal ($name, 'pollInterval', $hash->{fully}{interval} // $FULLY_POLL_INTERVAL);
	
	if ($mode == 0 || $interval == 0) {
		RemoveInternalTimer ($hash, 'FULLY_UpdateDeviceInfo');
		FULLY_Log ($hash, 2, "Polling deactivated")
			if (!exists($hash->{nextUpdate}) || $hash->{nextUpdate} ne 'off');		
		$hash->{nextUpdate} = 'off';
	}
	elsif ($mode == 1) {
		RemoveInternalTimer ($hash, 'FULLY_UpdateDeviceInfo');
		if (!exists($hash->{fully}{password})) {
			FULLY_Log ($hash, 2, "Polling not activated. Fully password not defined");
			return;
		}
		$interval = $FULLY_POLL_RANGE[0] if ($interval < $FULLY_POLL_RANGE[0]);
		$interval = $FULLY_POLL_RANGE[1] if ($interval > $FULLY_POLL_RANGE[1]);
		FULLY_Log ($hash, 2, "Polling activated")
			if (exists($hash->{nextUpdate}) && $hash->{nextUpdate} eq 'off');
		$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$interval);
		InternalTimer (gettimeofday()+$interval, "FULLY_UpdateDeviceInfo", $hash, 0);
	}
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
# FHEM notifications
######################################################################

sub FULLY_Notify ($$)
{
	my ($hash, $devhash) = @_;

	return if (AttrVal ($hash->{NAME}, 'disable', 0) == 1);
		
	my $events = deviceEvents ($devhash, 1);
	return if (!$events);
	
	if ($devhash->{NAME} eq 'global' && grep (/INITIALIZED/, @$events)) {
		FULLY_SetPolling ($hash, 1);
	}
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
	my $options = "brightness:slider,0,1,255 photo:noArg clearCache:noArg clearWebstorage:noArg ".
		"clearCookies:noArg exit:noArg foreground:noArg lock:noArg startApp ".
		"motionDetection:on,off off:noArg on:noArg on-for-timer playSound playVideo restart:noArg ".
		"screenOffTimer screenSaver:start,stop screenSaverTimer screenSaverURL speak startURL ".
		"stopSound:noArg stopVideo:noArg lockKiosk:noArg unlockKiosk:noArg unlock:noArg url ".
		"volume overlayMessage authentication";
	
	# Fully commands without argument
	my %cmds = (
		"clearCache"      => "clearCache",
		"clearWebstorage" => "clearWebstorage",
		"clearCookies"    => "clearCookies",
		"photo"           => "getCamshot",
		"exit"            => "exitApp",
		"restart"         => "restartApp",
		"on"              => "screenOn",
		"off"             => "screenOff",
		"lock"            => "enabledLockedMode",
		"unlock"          => "disableLockedMode",
		"lockKiosk"       => "lockKiosk",
		"unlockKiosk"     => "unlockKiosk",
		"stopSound"       => "stopSound",
		"stopVideo"       => "stopVideo",
		"foreground"      => "toForeground"
	);
	
	my @c = ();
	my @p = ();
	
	return "Device disabled" if (AttrVal ($name, 'disable', 0) == 1);
	return "FULLY: Missing password, choose one of authentication"
		if (!exists($hash->{fully}{password}) && $opt ne 'authentication');
	
	my $expert = AttrVal ($name, 'expert', 0);
	$options .= " setStringSetting setBooleanSetting" if ($expert);
	my $updateAfterCommand = AttrVal ($name, 'updateAfterCommand', 0);
	
	if (exists ($cmds{$opt})) {
		push (@c, $cmds{$opt});
	}
	elsif ($opt eq 'authentication') {
		my $password = shift @$a;

		if (!defined($password)) {
			setKeyValue ($name."_password", undef);
			delete $hash->{fully}{password};
			return 'Password for FULLY authentication deleted';
		}		

		my $encpass = FULLY_Encrypt ($password);
		return 'Encryption of password failed' if ($encpass eq '');
		
		my $err = setKeyValue ($name."_password", $encpass);
		return "Can't store credentials. $err" if (defined($err));
		
		$hash->{fully}{password} = $password;
		FULLY_SetPolling ($hash, 1);
		
		return 'Password for FULLY authentication stored';		
	}
	elsif ($opt eq 'on-for-timer') {
		my $par = shift @$a // "forever";

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
		my $value = shift @$a // return "Usage: set $name $opt {seconds}";
		push (@c, "setStringSetting");
		push (@p, { "key" => "timeToScreenOffV2", "value" => "$value" });
	}
	elsif ($opt eq 'screenSaver') {
		my $state = shift @$a;
		return "Usage: set $name $opt { start | stop }" if (!defined ($state) || $state !~ /^(start|stop)$/);
		push (@c, ($state eq 'start') ? "startScreensaver" : "stopScreensaver");
	}
	elsif ($opt eq 'screenSaverTimer') {
		my $value = shift @$a // return "Usage: set $name $opt {seconds}";
		push (@c, "setStringSetting");
		push (@p, { "key" => "timeToScreensaverV2", "value" => "$value" });
	}
	elsif ($opt eq 'screenSaverURL') {
		my $value = shift @$a // return "Usage: set $name $opt {URL}";
		push (@c, "setStringSetting");
		push (@p, { "key" => "screensaverURL", "value" => "$value" });
	}
	elsif ($opt eq 'startURL') {
		my $value = shift @$a // return "Usage: set $name $opt {URL}";
		push (@c, "setStringSetting");
		push (@p, { "key" => "startURL", "value" => "$value" });
	}
	elsif ($opt eq 'startApp') {
		my $app = shift @$a // return "Usage set $name $opt {APK-Name}";
		push (@c, "startApplication");
		push (@p, { "package" => "$app" } );
	}
	elsif ($opt eq 'brightness') {
		my $value = shift @$a // return "Usage: set $name brightness 0-255";
		$value = 255 if ($value > 255);
		push (@c, "setStringSetting");
		push (@p, { "key" => "screenBrightness", "value" => "$value" });
	}
	elsif ($opt eq 'motionDetection') {
		my $state = shift @$a // return "Usage: set $name motionDetection { on | off }";
		my $value = $state eq 'on' ? 'true' : 'false';
		push (@c, "setBooleanSetting");
		push (@p, { "key" => "motionDetection", "value" => "$value" });
	}
	elsif ($opt eq 'speak') {
		my $text = shift @$a // return 'Usage: set $name speak "{Text}"';
		my $enctext = FULLY_SubstDeviceReading ($text);
		push (@c, "textToSpeech");
		push (@p, { "text" => "$enctext" });
	}
	elsif ($opt eq 'overlayMessage') {
		my $text = shift @$a // return 'Usage: set $name overlayMessage "{Text}"';
		my $enctext = FULLY_SubstDeviceReading ($text);
		push (@c, "setOverlayMessage");
		push (@p, { "text" => "$enctext" });
	}
	elsif ($opt eq 'playSound') {
		my $url = shift @$a // return "Usage: set $name playSound {url} [loop]";
		my $loop = shift @$a;
		$loop = defined ($loop) ? 'true' : 'false';
		push (@c, "playSound");
		push (@p, { "url" => "$url", "loop" => "$loop"});
	}
	elsif ($opt eq 'playVideo') {
		my $url = shift @$a // return "Usage: set $name playVideo {url} [showControls] [exitOnTouch] [exitOnCompletion] [loop]";
		my %pvo = ('loop' => 0, 'showControls' => 0, 'exitOnTouch' => 0, 'exitOnCompletion' => 0);
		while (my $pvf = shift @$a) {
			return "Illegal option $pvf" if (!exists($pvo{$pvf}));
			$pvo{$pvf} = 1;
		}
		$pvo{'url'} = $url;
		push (@c, "playVideo");
		push (@p, \%pvo);
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
	if ($updateAfterCommand) {
		push (@c, 'deviceInfo');
		push (@p, undef);
	}
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
	my $options = "info:noArg update:noArg";
	
	return "Device disabled" if (AttrVal ($name, 'disable', 0) == 1);
	return "No password defined for Fully access" if (!exists($hash->{fully}{password}));
	
	if ($opt eq 'info') {
		my $result = FULLY_Execute ($hash, 'deviceInfo', undef, 1) //
			return FULLY_Log ($hash, 2, 'Command deviceInfo failed');
		return FULLY_Log ($hash, 2, $result->{'statustext'} // $result->{'status'})
			if (exists($result->{'status'}));
		return join ("\n", map { "$_ = $result->{$_}" } sort keys %$result);
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
# Write error message to FHEM log and return specified value
######################################################################

sub FULLY_Log ($$$;$)
{
	my ($hash, $level, $message, $retval) = @_;
	$retval //= $message;
	my $name = $hash->{NAME};
	
	Log3 $name, $level, "FULLY: [$name] $message";
	return $retval;
}

######################################################################
# Execute Fully command (blocking)
######################################################################

sub FULLY_Execute ($$$$)
{
	my ($hash, $command, $param, $doping) = @_;
	my $name = $hash->{NAME};

	if (!exists($hash->{fully}{password})) {
		asyncOutput ($hash->{CL}, "Please use command 'set $name authentication' to set the Fully password")
			if (exists($hash->{CL}));
		return undef;
	}
	
	# Get attributes
	my $timeout = AttrVal ($name, 'requestTimeout', $FULLY_TIMEOUT);
	my $repeatCommand = minNum (AttrVal ($name, 'repeatCommand', 0), 2);
	my $ping = minNum (AttrVal ($name, 'pingBeforeCmd', 0), 2);
	
	my $response = '';
	my $url = $hash->{prot}.'://'.$hash->{host}.':'.$hash->{port}."/?cmd=$command";
	
	if (defined ($param)) {
		foreach my $parname (keys %$param) {
			if (defined($param->{$parname})) {
				$url .= "&$parname=".$param->{$parname};
			}
		}
	}

	# Ping tablet device
	FULLY_Ping ($hash, $ping) if ($doping && $ping > 0);
	
	my $i = 0;
	while ($i <= $repeatCommand && (!defined ($response) || $response eq '')) {
		$response = GetFileFromURL ("$url&password=".$hash->{fully}{password}.'&type=json', $timeout);
		FULLY_Log ($hash, 4, "HTTP response empty") if (defined($response) && $response eq '');
		$i++;
	}
	
	my $result = eval { decode_json ($response) };
	FULLY_Log ($hash, 2, "Error in JSON data") if (!defined($result));

	return $result;
}

######################################################################
# Substitute device readings in string
######################################################################

sub FULLY_SubstDeviceReading ($)
{
	my ($text) = @_;
	 
	while ($text =~ /\[(.+):(.+)\]/) {
		my ($device, $reading) = ($1, $2);
		my $value = ReadingsVal ($device, $reading, '');
		$text =~ s/\[$device:$reading\]/$value/g;
	}
	
	return (urlEncode ($text));
}

######################################################################
# Execute Fully commands (non blocking)
######################################################################

sub FULLY_ExecuteNB ($$$$)
{
	my ($hash, $command, $param, $doping) = @_;
	my $name = $hash->{NAME};

	# Get attributes
	my $timeout = AttrVal ($name, 'requestTimeout', $FULLY_TIMEOUT);
	my $repeatCommand = minNum (AttrVal ($name, 'repeatCommand', 0), 2);
	my $ping = minNum (AttrVal ($name, 'pingBeforeCmd', 0), 2);

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
		
		FULLY_Log ($hash, 4, "Pushing $url on command stack");
		push (@urllist, "$url&password=".$hash->{fully}{password}."&type=json");
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

	FULLY_Log ($hash, 4, "Executing command ".$urllist[0]);
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
		# Process response
		FULLY_Log ($hash, 5, $data, 0);
		my $result = eval { decode_json ($data) };
		if (!defined($result)) {
			FULLY_Log ($hash, 2, "Error in JSON data");
			return;
		}
		
		if (!exists($result->{status})) {
			$result->{status} = 'OK';
			$result->{statustext} //= 'N/A';
		}
		$result->{execstate} = $result->{status};
		if (exists($result->{statustext})) {
			$result->{statustext} =~ s/password=[^&]+//;
			$result->{execstate} .= " $result->{statustext}";
		}
		else {
			$result->{statustext} = 'N/A';
		}
		FULLY_UpdateReadings ($hash, $result);
		
		if ($result->{status} =~ /^Error/i) {
			FULLY_Log ($hash, 2, "Command $param->{orgurl} failed: $result->{status} $result->{statustext}");
		}
		else {
			$hash->{lastUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time)
				if ($param->{orgurl} =~ /deviceInfo/);
			FULLY_Log ($hash, 4, "Command $param->{orgurl} executed: $result->{status} $result->{statustext}");
		}

		if ($param->{cmdno} < $param->{cmdcnt}) {
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

			FULLY_Log ($hash, 4, "Executing command ".$urllist[$param->{cmdno}]);
			HttpUtils_NonblockingGet ($reqpar);
		}
		else {
			FULLY_Log ($hash, 4, 'Last command executed.');
			return;
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

			FULLY_Log ($hash, 4, "Repeating command ".$param->{orgurl});
			HttpUtils_NonblockingGet ($reqpar);
		}
		else {
			if ($err =~ /^empty answer/) {
				$err .= ' (probable reason: timeout)';
			}
			FULLY_UpdateReadings ($hash, {
				"status" => "Error",
				"statustext" => "$err",
				"execstate" => "Error $err"
			});
			FULLY_Log ($hash, 2, "Error during request $param->{orgurl}. $err");
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

	return if (AttrVal ($hash->{NAME}, 'disable', 0) == 1);
	
	FULLY_ExecuteNB ($hash, ['deviceInfo'], undef, 1);
	FULLY_SetPolling ($hash, 1);
}

######################################################################
# Get tablet device information
######################################################################

sub FULLY_GetDeviceInfo ($)
{
	my ($name) = @_;
	my $hash = $defs{$name};
	
	FULLY_ExecuteNB ($hash, ['deviceInfo'], undef, 1);
}

######################################################################
# Update readings
######################################################################

sub FULLY_UpdateReadings ($$)
{
	my ($hash, $result) = @_;
	
	my %readings = (
		'isdeviceadmin' => 'bool',
		'isdeviceowner' => 'bool',
		'isindaydream' => 'bool',
		'isinforcedsleep' => 'bool',
		'isinscreensaver' => 'bool',
		'islicensed' => 'bool',
		'ismenuopen' => 'bool',
		'ismobiledataenabled' => 'bool',
		'isplugged' => 'bool',
		'isrooted' => 'bool',
		'keyguardlocked' => 'bool',
		'kiosklocked' => 'bool',
		'kioskmode' => 'bool',
		'maintenancemode' => 'bool',
		'motiondetectorstatus' => 'bool',
		'mqttconnected' => 'bool',
		'plugged' => 'bool',
		'screenlocked' => 'bool',
		'screenon' => 'bool',
		'webviewua' => 'ignore'
	);
	
	readingsBeginUpdate ($hash);
	foreach my $rn (keys %$result) {
		my $key = lc($rn);
		next if (exists($readings{$key}) && $readings{$key} eq 'ignore');
		if (ref($result->{$rn}) eq 'ARRAY') {
			if ($key eq 'sensorinfo') {
				foreach my $e (@{$result->{$rn}}) {
					$key = lc($e->{name});
					$key =~ s/ /_/g;
					my $rv = ref($e->{values}) eq 'ARRAY' ? join(',', @{$e->{values}}) : $e->{values};
					readingsBulkUpdate ($hash, $key, $rv);
				}
			}
		}
		else {
			readingsBulkUpdate ($hash, $key, exists($readings{$key}) && $readings{$key} eq 'bool' ?
				($result->{$rn} eq '0' ? 'no' : 'yes') : $result->{$rn});
		}
	}
	
	my $screenOn = $result->{isScreenOn} // $result->{screenOn};
	if (defined($screenOn)) {
		readingsBulkUpdate ($hash, 'state', $screenOn eq '0' ? 'off' : 'on');
	}
	if (exists($result->{appVersionName}) && $result->{appVersionName} =~ /^([0-9]\.[0-9]+).*/) {
		if ($1 < $FULLY_REQUIRED_VERSION && !exists($hash->{fully}{versionWarn})) {
			FULLY_Log ($hash, 1, "Version of fully browser is $1. Version $FULLY_REQUIRED_VERSION is required.");
			$hash->{fully}{versionWarn} = 1;
		}
	}
	readingsEndUpdate ($hash, 1);
}

######################################################################
# Encrypt string with FHEM unique ID
######################################################################

sub FULLY_Encrypt ($)
{
	my ($istr) = @_;
	my $ostr = '';
	
	my $id = getUniqueId() // '';
	return '' if ($id eq '');
	
	my $key = $id;
	foreach my $c (split //, $istr) {
		my $k = chop($key);
		if ($k eq '') {
			$key = $id;
			$k = chop($key);
		}
		$ostr .= sprintf ("%.2x",ord($c)^ord($k));
	}

	return $ostr;	
}

######################################################################
# Decrypt string with FHEM unique ID
######################################################################

sub FULLY_Decrypt ($)
{
	my ($istr) = @_;
	my $ostr = '';

	my $id = getUniqueId() // '';
	return '' if ($id eq '');

	my $key = $id;
	for my $c (map { pack('C', hex($_)) } ($istr =~ /(..)/g)) {
		my $k = chop($key);
		if ($k eq '') {
			$key = $id;
			$k = chop($key);
		}
		$ostr .= chr(ord($c)^ord($k));
	}

	return $ostr;
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

	my $waitAfterPing = minNum (AttrVal ($name, 'waitAfterPing', 0), 2);
	
	my $os = $^O;
	FULLY_Log ($hash, 4, "Sending $count ping request(s) to tablet $host. OS=$os");
	
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
   
   <a name="FULLYdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; FULLY [&lt;Protocol&gt;://]&lt;HostOrIP&gt;[:&lt;Port&gt;] [&lt;password&gt;] [&lt;poll-interval&gt;]</code>
      <br/><br/>
	  The parameter <i>password</i> is the password set in Fully browser. Parameter <i>Protocol</i> is
	  optional. Valid protocols are 'http' and 'https'. Default protocol is 'http'. 
	  Default <i>Port</i> is 2323.<br/>
	  The password is optional. If you don't want the password to appear in the device definition,
	  set the password by using command 'set authentication'.
   </ul>
   <br/>
   
   <a name="FULLYset"></a>
   <b>Set</b><br/><br/>
   <ul>
   	<li><b>set &lt;name&gt; authentication [&lt;password&gt;]</b><br/>
   		Set Fully password. This password is used for each Fully opteration.
   		If no password is specified, the current password is deleted.
		</li><br/>
		<li><b>set &lt;name&gt; brightness 0-255</b><br/>
			Adjust screen brightness.
		</li><br/>
		<li><b>set &lt;name&gt; clearCache</b><br/>
			Clear browser cache.
		</li><br/>
		<li><b>set &lt;name&gt; clearCookies</b><br/>
			Clear cookies.
		</li><br/>
		<li><b>set &lt;name&gt; clearWebstorage</b><br/>
			Clear web storage.
		</li><br/>
		<li><b>set &lt;name&gt; exit</b><br/>
			Terminate Fully.
		</li><br/>
		<li><b>set &lt;name&gt; foreground</b><br/>
			Bring fully app to foreground.
		</li><br/>
		<li><b>set &lt;name&gt; lockKiosk</b><br/>
			Lock kiosk mode.
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
		<li><b>set &lt;name&gt; overlayMessage { text }</b><br/>
			Show overlay message. Placeholders in format [device:reading] are supported and will
			be substituted by the corresponding reading value.
		</li><br/>
		<li><b>set &lt;name&gt; photo</b><br/>
			Take a picture with device cam. Setting motion detection must be enabled. Picture
			can be viewed in remote admin interface under device info.
		</li><br/>
		<li><b>set &lt;name&gt; playSound &lt;url&gt; [loop]</b><br/>
			Play sound from URL.
		</li><br/>
		<li><b>set &lt;name&gt; playVideo &lt;url&gt; [loop] [showControls] [exitOnTouch] [exitOnCompletion]</b><br/>
			Play video from URL.
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
		<li><b>set &lt;name&gt; stopVideo</b><br/>
			Stop playback of video if playback has been started with option <i>loop</i>.
		</li><br/>
		<li><b>set &lt;name&gt; unlockKiosk</b><br/>
			Unlock kiosk mode.
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
      	Show Fully statistics. Will be implemented later.
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
   	<a name="disable"></a>
      <li><b>disable &lt;0 | 1&gt;</b><br/>
      	Disable device and automatic polling.
      </li><br/>
   	<a name="expert"></a>
      <li><b>expert &lt;0 | 1&gt;</b><br/>
      	Activate expert mode.
      </li><br/>
   	<a name="pingBeforeCmd"></a>
   	<li><b>pingBeforeCmd &lt;Count&gt;</b><br/>
   		Send <i>Count</i> ping request to tablet before executing commands. Valid values 
   		for <i>Count</i> are 0,1,2. Default is 0 (do not send ping request).
   	</li><br/>
   	<a name="pollInterval"></a>
      <li><b>pollInterval &lt;seconds&gt;</b><br/>
         Set polling interval for FULLY device information.
         If <i>seconds</i> is 0 polling is turned off. Valid values are from 10 to
         86400 seconds.
      </li><br/>
   	<a name="repeatCommand"></a>
      <li><b>repeatCommand &lt;Count&gt;</b><br/>
         Repeat fully command on failure. Valid values for <i>Count</i> are 0,1,2. Default
         is 0 (do not repeat commands).
      </li><br/>
   	<a name="requestTimeout"></a>
      <li><b>requestTimeout &lt;seconds&gt;</b><br/>
         Set timeout for http requests. Default is 5 seconds. Increase this value if commands
         are failing with a timeout error.
      </li><br/>
   	<a name="updateAfterCommand"></a>
      <li><b>updateAfterCommand &lt;0 | 1&gt;</b><br/>
      	When set to 1 update readings after a set command. Default is 0.
      </li><br/>
   	<a name="waitAfterPing"></a>
      <li><b>waitAfterPing &lt;Seconds&gt;</b><br/>
      	Wait specified amount of time after sending ping request to tablet device. Valid
      	values for <i>Seconds</i> are 0,1,2. Default is 0 (do not wait). Only used if
      	attribute pingBeforeCmd is greater than 0.
      </li><br/>
   </ul>
</ul>

=end html
=cut


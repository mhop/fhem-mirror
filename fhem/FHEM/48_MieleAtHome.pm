########################################################################################
#
# MieleAtHome.pm
#
# FHEM module for Miele@home Devices
#
# Christian Hoenig
#
# $Id$
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################
package main;

use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use List::Util qw[min max];
use JSON;

my $version = "1.1.0";

my $MAH_hasMimeBase64 = 1;

use constant PROCESS_ACTIONS => {
		0x01 => "start",              # 1 START
		0x02 => "stop",               # 2 STOP
		0x03 => "pause",              # 3 PAUSE
		0x04 => "startSuperFreezing", # 4 START SUPERFREEZING
		0x05 => "stopSuperFreezing",  # 5 STOP SUPERFREEZING
		0x06 => "startSuperCooling",  # 6 START SUPERCOOLING
		0x07 => "stopSuperCooling",   # 7 STOP SUPERCOOLING
};

use constant LIGHT_ACTIONS => {
		0x01 => "enable",   # 1 Enable
		0x02 => "disable",  # 2 Disable
};

use constant VENTILATION_STEPS => {
		0x01 => "Step1",  # 1 Step1
		0x02 => "Step2",  # 2 Step2
		0x03 => "Step3",  # 3 Step3
		0x04 => "Step4",  # 4 Step4
};

# TODO: <option value="programId">programId</option>
# TODO: <option value="targetTemperature">targetTemperature</option>
# TODO: <option value="deviceName">deviceName</option>
# TODO: <option value="colors">colors</option>
# TODO: <option value="modes">modes</option>

use constant COUNTRIES => {
		"Miele-Deutschland"          => "de-DE",
		"Miele-Eesti"                => "et-EE",
		"Miele-Norge"                => "no-NO",
		"Miele-Serbien"              => "sr-RS", # "Miele-Србија"               => "sr-RS",
		"Miele-Belgie"               => "nl-BE", # "Miele-België"               => "nl-BE",
		"Miele-Suomi"                => "fi-FI",
		"Miele-Hong-Kong"            => "zh-HK",
		"Miele-Russland"             => "ru-RU", # "Miele-Россия"               => "ru-RU",
		"Miele-United-Arab-Emirates" => "en-AE",
		"Miele-Portugual"            => "pt-PT",
		"Miele-Bulgarien"            => "bg-BG", # "Miele-България"             => "bg-BG",
		"Miele-Schweiz"              => "de-CH",
		"Miele-India"                => "en-IN",
		"Miele-Semi-Pro"             => "de-SX",
		"Miele-Nihon"                => "ja-JP",
		"Miele-Danmark"              => "da-DK",
		"Miele-Hanguk"               => "ko-KR",
		"Miele-South-Africa"         => "en-ZA",
		"Miele-Lietuva"              => "lt-LT",
		"Miele-Chile"                => "es-CL",
		"Miele-Luxemburg"            => "de-LU",
		"Miele-Croatia"              => "hr-HR",
		"Miele-Latvija"              => "lv-LV",
		"Miele-China"                => "zh-CN", # "Miele-Zhōngguó"             => "zh-CN",
		"Miele-Griechenland"         => "el-GR", # "Miele-Ελλάδα"               => "el-GR",
		"Miele-Italia"               => "it-IT",
		"Miele-Mexico"               => "es-MX", # "Miele-México"               => "es-MX",
		"Miele-France"               => "fr-FR",
		"Miele-Malaysia"             => "en-MY",
		"Miele-New-Zealand"          => "en-NZ",
		"Miele-Ukraine"              => "ru-UA", # "Miele-Україна"              => "ru-UA",
		"Miele-Magyarorszag"         => "hu-HU", # "Miele-Magyarország"         => "hu-HU",
		"Miele-Espana"               => "es-ES", # "Miele-España"               => "es-ES",
		"Miele-Kasachstan"           => "ru-KZ", # "Miele-Казахстан"            => "ru-KZ",
		"Miele-Sverige"              => "sv-SE",
		"Miele-Oesterreich"          => "de-AT", # "Miele-Österreich"           => "de-AT",
		"Miele-Australia"            => "en-AU",
		"Miele-Singapore"            => "en-SG",
		"Miele-Thailand"             => "en-TH",
		"Miele-Kypros"               => "el-CY",
		"Miele-Slovenia"             => "sl-SI",
		"Miele-Weissrussland"        => "ru-BY", # "Miele-Беларуси"             => "ru-BY",
		"Miele-Czechia"              => "cs-CZ",
		"Miele-Slovensko"            => "sk-SK",
		"Miele-UK"                   => "en-GB",
		"Miele-Ireland"              => "en-IE",
		"Miele-Polska"               => "pl-PL",
		"Miele-Romania"              => "ro-RO", # "Miele-România"              => "ro-RO",
		"Miele-Canada"               => "en-CA",
		"Miele-Nederland"            => "nl-NL",
		"Miele-Tuerkiye"             => "tr-TR", # "Miele-Türkiye"              => "tr-TR"
		"Miele-USA"                  => "en-US",
};

#------------------------------------------------------------------------------------------------------
# Initialize
#------------------------------------------------------------------------------------------------------
sub MieleAtHome_Initialize($)
{
	my ($hash) = @_;

	MAH_Log(undef, 5, "called");

	eval "use MIME::Base64";
	$MAH_hasMimeBase64 = 0 if($@);

	$hash->{DefFn}     = "MAH_DefFn";
	$hash->{UndefFn}   = "MAH_UndefFn";
	$hash->{DeleteFn}  = "MAH_DeleteFn";
	$hash->{AttrFn}    = "MAH_AttrFn";
	$hash->{SetFn}     = "MAH_SetFn";
	$hash->{GetFn}     = "MAH_GetFn";
	$hash->{RenameFn}  = "MAH_RenameFn";

	$hash->{AttrList}       = "";
	$hash->{AttrList}      .= "clientId ";
	$hash->{AttrList}      .= "disable:1 ";
	$hash->{AttrList}      .= "login ";
	$hash->{AttrList}      .= "lang:de,en ";
	$hash->{AttrList}      .= "country:" . join(",", keys %{COUNTRIES()}) . " ";
	$hash->{AttrList}      .= $readingFnAttributes;

	# maintenance
	foreach my $d (sort keys %{$modules{MieleAtHome}{defptr}}) {
		my $hash = $modules{MieleAtHome}{defptr}{$d};

		# update version in devices
		$hash->{VERSION} = $version;

		# rename IODev -> IODevName (0.12.0)
		if (defined($hash->{IODev})) {
			$hash->{IODevName} = $hash->{IODev};
			delete($hash->{IODev});
		}
	}
}

#------------------------------------------------------------------------------------------------------
# Define
#------------------------------------------------------------------------------------------------------
sub MAH_DefFn($$)
{
	my ( $hash, $def ) = @_;

	my @a = split( "[ \t]+", $def );
	splice( @a, 1, 1 );

	# check syntax
	my $pCount = int(@a);
	if ($pCount < 1 || $pCount > 3) {
		return "Wrong syntax: use define <name> MAH [deviceId] [interval]";
	}

	my $name     = shift(@a);
	my $deviceId = shift(@a);
	my $interval = shift(@a);
	MAH_Log($hash, 5, "called");

	my $ioDevName = "";
	if ($deviceId && $deviceId =~ /([0-9]+)+@(.+)/) {
		$deviceId  = $1;
		$ioDevName = $2;
	}

	if    ($deviceId)  { $hash->{DEVICE_ID} = $deviceId;  }
	else               { delete($hash->{DEVICE_ID});      }
	if    ($ioDevName) { $hash->{IODevName} = $ioDevName; }
	else               { delete($hash->{IODevName});      }
	if    ($interval)  { $hash->{INTERVAL}  = $interval;  }
	elsif ($deviceId)  { $hash->{INTERVAL}  = 120;        } # default: 120
	else               { delete($hash->{INTERVAL});       }
	$hash->{VERSION} = $version;

	$hash->{HAS_MimeBase64} = $MAH_hasMimeBase64;

	MAH_restoreOAuth2Credentials($hash);

	$attr{$name}{room}         = "MieleAtHome" if(!defined($attr{$name}{room}));
	$attr{$name}{devStateIcon} = ".*:noIcon"   if(!defined($attr{$name}{devStateIcon}));

	$modules{MieleAtHome}{defptr}{"mah_".$name} = $hash;

	if (defined($deviceId)) {
		# check if $deviceId exists already
		my $d = $modules{MieleAtHome}{defptr}{"deviceid_".$deviceId};
		if (defined($d) && $d->{NAME} ne $name) {
			$hash->{STATE} = 'Error';
			readingsSingleUpdate($hash, "lastError", "MAH device with DeviceId $deviceId already defined as $d->{NAME}.", 1);
			$hash->{DUPLICATE_INSTANCE} = "1";
			return;
		}

		# remember our deviceId
		$modules{MieleAtHome}{defptr}{"deviceid_".$deviceId} = $hash;

		MAH_Log($hash, 4, "finished define with deviceId: $deviceId");
	}

	fhem("deletereading $name lastError");

	if (MAH_isDisabled($hash)) {
		readingsSingleUpdate( $hash, "state", "disabled", 1 );
		return undef;
	}
	$hash->{STATE} = 'Initialized';

	if (defined($deviceId)) {
		# this will call MAH_refreshAccessToken itself if required
		InternalTimer(gettimeofday()+($init_done ? 0 : 10), "MAH_updateValues", $hash);
	} else {
		InternalTimer(gettimeofday()+($init_done ? 0 : 10), "MAH_refreshAccessToken", $hash);
	}

	# if MAH_getAccessToken returns "", it will request a new token on its own
	if (MAH_getAccessToken($hash) ne "") {
		InternalTimer(gettimeofday()+0, "MAH_updateValues", $hash);
	}

	return undef;
}


#------------------------------------------------------------------------------------------------------
# Undefine
#------------------------------------------------------------------------------------------------------
sub MAH_UndefFn($$)
{
	my ($hash, $name) = @_;

	RemoveInternalTimer($hash);

	delete($modules{MieleAtHome}{defptr}{"mah_".$name});

	my $deviceId = $hash->{DEVICE_ID};
	if (defined($deviceId)) {
		MAH_Log($hash, 4, "undefined with deviceId: $deviceId");
		delete($modules{MieleAtHome}{defptr}{"deviceid_".$deviceId});
	}

	MAH_Log($hash, 4, "undefined");
	return undef;
}

#------------------------------------------------------------------------------------------------------
# Delete
#------------------------------------------------------------------------------------------------------
sub MAH_DeleteFn($$)
{
	my ($hash, $name) = @_;

	MAH_deletePassword($hash);
	MAH_deleteClientSecret($hash);
	MAH_deleteOAuth2Credentials($hash);

	MAH_Log($hash, 4, "deleted");
	return undef;
}

#------------------------------------------------------------------------------------------------------
# AttrFn
#------------------------------------------------------------------------------------------------------
sub MAH_AttrFn(@)
{
	my ($cmd, $name, $attrName, $attrVal) = @_;
	my $hash = $defs{$name};

	######################
	#### disable #########

	if ($attrName eq "disable") {
		if ($cmd eq "set" && $attrVal eq "1") {
			readingsSingleUpdate ( $hash, "state", "disabled", 1 );
			MAH_Log($hash, 3, "disabled");
		}
		elsif ($cmd eq "del") {
			readingsSingleUpdate ( $hash, "state", "active", 1 );
			MAH_Log($hash, 3, "enabled");
			InternalTimer(gettimeofday()+0, "MAH_updateValues", $hash);
		}
	}

	#################
	#### lang ######

	if ($attrName eq "lang") {
		if ($cmd eq "set") {
			return "Invalid value for attribute $attrName" if ($attrVal ne "de" && $attrVal ne "en");
		}
	}

	#################
	#### login ######

	if ($attrName eq "login") {
		if ($cmd eq "set") {
			return "Invalid value for attribute $attrName" if (!$attrVal);
			#MAH_Log($hash, 1, "setting 'login' calls 'MAH_refreshAccessToken' ($init_done)");
			InternalTimer(gettimeofday()+0, "MAH_refreshAccessToken", $hash) if ($init_done);
		}
	}

	####################
	#### clientId ######

	if ($attrName eq "clientId") {
		if ($cmd eq "set") {
			return "Invalid value for attribute $attrName" if (!$attrVal);
			#MAH_Log($hash, 1, "setting 'clientId' calls 'MAH_refreshAccessToken' ($init_done)");
			InternalTimer(gettimeofday()+0, "MAH_refreshAccessToken", $hash) if ($init_done);
		}
	}

	####################
	#### country ######

	if ($attrName eq "country") {
		if ($cmd eq "set") {
			if (!$attrVal ||
			    (!defined(COUNTRIES->{$attrVal}) &&
			     !grep { $_ eq $attrVal } values %{COUNTRIES()})) {
				return "Invalid value for attribute $attrName" 
			}
			#InternalTimer(gettimeofday()+0, "MAH_refreshAccessToken", $hash) if ($init_done);
		}
	}

	return undef;
}

#------------------------------------------------------------------------------------------------------
# SetFn
#------------------------------------------------------------------------------------------------------
sub MAH_SetFn($$@)
{
	my ($hash, $name, @aa) = @_;
	my ($cmd, @args) = @aa;

	# password and clientSecret are allowed even when 'disabled' (but only if we don't use an IODev)
	my $list = "";
	$list .= "password "     if (!defined($hash->{IODevName}));
	$list .= "clientSecret " if (!defined($hash->{IODevName}));

	if ($cmd eq "?") {
		return "Unknown argument $cmd, choose one of $list" if (MAH_isDisabled($hash));
	}

	if( $cmd eq 'clientSecret' ) {
		return "usage: callback <secret>" if(@args != 1);
		MAH_saveClientSecret($hash, $args[0]);
		InternalTimer(gettimeofday()+0, "MAH_refreshAccessToken", $hash);
		return undef;
	}
	elsif( $cmd eq 'password' ) {
		return "usage: password <password>" if(@args != 1);
		MAH_savePassword($hash, $args[0]);
		InternalTimer(gettimeofday()+0, "MAH_refreshAccessToken", $hash);
		return undef;
	}
	elsif( $cmd eq 'autocreate' ) {
		return "autocreate needs a valid ACCESS_TOKEN, please try again" if (MAH_getAccessToken($hash) == "");
		return "use $cmd without arguments" if(@args != 0);
		InternalTimer(gettimeofday()+0, "MAH_autocreate", $hash);
		return undef;
	}
	elsif( $cmd eq 'on' || $cmd eq 'off' ) {
		return "use $cmd without arguments" if(@args != 0);
		return MAH_setPower($hash, $cmd)
	}
	elsif( $cmd eq 'start' || $cmd eq 'stop' || $cmd eq 'pause' || 
	       $cmd eq 'startSuperFreezing' || $cmd eq 'stopSuperFreezing' || 
		   $cmd eq 'startSuperCooling'  || $cmd eq 'stopSuperCooling' ) {
		return "use $cmd without arguments" if(@args != 0);
		return MAH_setProcessAction($hash, $cmd)
	}
	elsif( $cmd eq 'startTime') {
		return "usage: startTime <OFFSET_H:MM>" if(@args != 1);
		return MAH_setStartTime($hash, $args[0])
	}
	elsif( $cmd eq 'update' ) {
		return "use $cmd without arguments" if(@args != 0);
		InternalTimer(gettimeofday()+0, "MAH_updateValues", $hash);
		return undef;
	}
	elsif( $cmd eq 'ventilationStep') {
		return "usage: ventilationStep <step>" if(@args != 1);
		return MAH_setVentilationStep($hash, $args[0])
	}
	elsif( $cmd eq 'light') {
		return "usage: light enable|disable" if(@args != 1);
		return MAH_setLight($hash, $args[0])
	}
	else
	{
		$list   .= "autocreate:noArg " if (!defined($hash->{IODevName}));
		$list   .= "update:noArg "     if (defined($hash->{DEVICE_ID}));

		$list   .= "on:noArg "   if (defined($hash->{DEVICE_ID}) && ReadingsNum($name, "actions_powerOn",  0) == 1);
		$list   .= "off:noArg "  if (defined($hash->{DEVICE_ID}) && ReadingsNum($name, "actions_powerOff", 0) == 1);
		$list   .= "startTime "  if (defined($hash->{DEVICE_ID}) && ReadingsNum($name, "actions_startTime", 0) == 1);

		# process actions
		my @processActionIds = split(/,/, ReadingsVal($name, "actions_processAction", ""));
		foreach my $processActionId (@processActionIds) {
			if (defined PROCESS_ACTIONS->{$processActionId}) {
				$list .= PROCESS_ACTIONS->{$processActionId} . ":noArg ";
			}
		}

		# light actions
		my $lightCmds = "";
		my @lightIds = split(/,/, ReadingsVal($name, "actions_light", ""));
		foreach my $lightId (@lightIds) {
			if (defined LIGHT_ACTIONS->{$lightId}) {
				$lightCmds .= LIGHT_ACTIONS->{$lightId} . ",";
			}
		}
		chop($lightCmds); # remove trailing ','
		$list   .= "light:${lightCmds} " if ($lightCmds ne "");

		# ventilation steps
		my $ventilationStepCmds = "";
		my @ventilationStepIds = split(/,/, ReadingsVal($name, "actions_ventilationStep", ""));
		foreach my $ventilationStepId (@ventilationStepIds) {
			if (defined VENTILATION_STEPS->{$ventilationStepId}) {
				$ventilationStepCmds .= VENTILATION_STEPS->{$ventilationStepId} . ",";
			}
		}
		chop($ventilationStepCmds); # remove trailing ','
		$list   .= "ventilationStep:${ventilationStepCmds} " if ($ventilationStepCmds ne "");

		return "Unknown argument $cmd, choose one of $list";
	}
}

#------------------------------------------------------------------------------------------------------
# SetFn
#------------------------------------------------------------------------------------------------------
sub MAH_GetFn($$@)
{
	my ($hash, $name, $opt, @args ) = @_;

	my $list = "";

	if ($opt eq "?") {
		return "Unknown argument $opt, choose one of $list" if (MAH_isDisabled($hash));
	}

	if( $opt eq 'listDevices' ) {
		return "listDevices needs a valid ACCESS_TOKEN, please try again" if (MAH_getAccessToken($hash) eq "");
		my $devices = MAH_blockingGetAllDevicesRequest($hash);
		if(ref($devices) ne 'ARRAY') {
			readingsSingleUpdate($hash, "lastError", "listDevices failed: $devices", 1);
			return;
		}

		my $retval;
		for my $d (@{$devices}) {
			$retval .= sprintf("%s (%s)", @{$d}[0], @{$d}[1]);
		}
		return $retval;
	}
	else
	{
		# these are only allowed when MAH is not 'disabled'
		$list   .= "listDevices:noArg " if (!defined($hash->{IODevName}) && !MAH_isDisabled($hash));
		return "Unknown argument $opt, choose one of $list";
	}
}

#------------------------------------------------------------------------------------------------------
# MAH_RenameFn
#------------------------------------------------------------------------------------------------------
sub MAH_RenameFn($$)
{
	my ($newName, $oldName) = @_;

	return unless (defined($defs{$newName}));
	my $newHash = $defs{$newName};

	# rename mah_-reference
	if (defined($modules{MieleAtHome}{defptr}{"mah_".$oldName})) {
		$modules{MieleAtHome}{defptr}{"mah_".$newName} = $newHash;
		delete($modules{MieleAtHome}{defptr}{"mah_".$oldName});
	}

	MAH_renameClientSecret($newHash, $oldName, $newName);
	MAH_renamePassword($newHash, $oldName, $newName);
	MAH_renameOAuth2Credentials($newHash, $oldName, $newName);
}

#------------------------------------------------------------------------------------------------------
# request values from 3rd party api
#------------------------------------------------------------------------------------------------------
sub MAH_updateValues($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "called");

	RemoveInternalTimer($hash, "MAH_updateValues");

	return undef if (MAH_isDisabled($hash));
	return undef unless (defined($hash->{DEVICE_ID}));
	return undef unless (MAH_hasLoginCredentials($hash));

	my $interval = $hash->{INTERVAL};
	# force interval of 60s while != Off
	$interval = min($interval, 60) if ReadingsNum($name, "statusRaw", 1) != 1; # != Off
	InternalTimer(gettimeofday()+$interval, "MAH_updateValues", $hash) if (defined($interval));

	# MAH_getAccessToken will request a new one, if there is none
	if (MAH_getAccessToken($hash) eq "") {
		return;
	}

	MAH_sendGetDeviceIdentAndState($hash);
	MAH_sendGetDeviceActionsRequest($hash);
}


#------------------------------------------------------------------------------------------------------
# MAH_refreshAccessToken
#------------------------------------------------------------------------------------------------------
sub MAH_refreshAccessToken($); # workaround for perl warning
sub MAH_refreshAccessToken($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "called");

	# let the IODev update the token
	my $iohash = MAH_getIODevHash($hash);
	return MAH_refreshAccessToken($iohash) if (defined($iohash));

	# only refresh the token once
	if (defined($hash->{TOKEN_REFRESH_IN_PROGRESS}) && $hash->{TOKEN_REFRESH_IN_PROGRESS} == 1) {
		MAH_Log($hash, 4, "token refresh already in progress, skipping");
		return;
	}
	$hash->{TOKEN_REFRESH_IN_PROGRESS} = 1;

	if (MAH_getAccessTokenPrivate($hash) ne "" && MAH_getRemainingTokenLifetime($hash) > 24 * 60 * 60) {
		MAH_Log($hash, 4, "access-token still valid, skipping refresh. Call '{delete(\$defs{$name}{OAUTH2_ACCESS_TOKEN})}' in command bar to force refresh");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	if (!MAH_hasLoginCredentials($hash)) {
		readingsSingleUpdate($hash, "lastError", "please set login, password, clientId and clientSecret", 1);
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	} else {
		fhem("deletereading $name lastError");
	}

	my $refreshToken = MAH_getRefreshTokenPrivate($hash);
	if ($refreshToken ne "" && MAH_getRemainingTokenLifetime($hash) > 0) {
		MAH_Log($hash, 4, "already have a refresh-token, using this for token-refresh");
		MAH_doThirdpartyTokenRequest($hash, "", $refreshToken)
	} else {
		MAH_doThirdpartyLoginRequest($hash);
	}
}

#------------------------------------------------------------------------------------------------------
sub MAH_doThirdpartyLoginRequest($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "called");

	my $clientId = MAH_getClientId($hash);
	if (!defined($clientId)) {
		readingsSingleUpdate($hash, "lastError", "clientId missing", 1);
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	# Step 1: Authorization
	my $url = "https://api.mcs3.miele.com/thirdparty/login/"
			. "?response_type=code"
			. "&state=login"
			. "&client_id=" . urlEncode($clientId)
			. "&scope="
			. "&redirect_uri=https%3A%2F%2Fapi.mcs3.miele.com%2Fthirdparty%2Flogin%2F";

	my ($err, $reply) = HttpUtils_NonblockingGet({
		url         => $url,
		timeout     => 5,
		hash        => $hash,
		method      => "GET",
		callback    => \&MAH_onThirdpartyLoginReply,
	});
}

sub MAH_onThirdpartyLoginReply($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "reply: err:$err, code:$param->{code}, headers:$param->{httpheader}, data:$data");

	if ($err) {
		MAH_Log($hash, 3, "Error: $err");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return $err;
	}

	MAH_doOauthLoginRequest($hash);
}

#------------------------------------------------------------------------------------------------------
sub MAH_doOauthLoginRequest($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "called");

	my $login = MAH_getLogin($hash);
	if (!defined($login)) {
		readingsSingleUpdate($hash, "lastError", "login missing", 1);
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}
	my $password = MAH_getPassword($hash);
	if (!defined($password)) {
		readingsSingleUpdate($hash, "lastError", "password missing", 1);
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}
	my $clientId = AttrVal($name, "clientId", "");
	if (!defined($clientId)) {
		readingsSingleUpdate($hash, "lastError", "clientId missing", 1);
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	my $country = COUNTRIES->{AttrVal($name, "country", "Miele-Deutschland")};
	MAH_Log($hash, 5, "country for /oauth/auth is $country");

	# Step 2: oauth
	my $url = "https://api.mcs3.miele.com/oauth/auth";
	my $data = "email=" . urlEncode($login)
			.  "&password=" . urlEncode($password)
			.  "&state=login"
			.  "&response_type=code"
			.  "&client_id=" . urlEncode($clientId)
			.  "&vgInformationSelector=$country"
			.  "&redirect_uri=https%3A%2F%2Fapi.mcs3.miele.com%2Fthirdparty%2Flogin%2F";

	my ($err, $reply) = HttpUtils_NonblockingGet({
		url         => $url,
		data        => $data,
		timeout     => 5,
		hash        => $hash,
		method      => "POST",
		ignoreredirects => 1,
		callback    => \&MAH_onOauthLoginReply,
	});
}

sub MAH_onOauthLoginReply($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "reply: err:$err, code:$param->{code}, headers:$param->{httpheader}, data:$data");

	if ($err) {
		MAH_Log($hash, 3, "Error: $err");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	my $code = "";
	my $headers = $param->{httpheader};
	if ($headers =~ /(?s)code=([A-Z]{2}_[0-9a-f]+)/) {
		MAH_Log($hash, 5, "Bearer found in headers");
		$code = $1;
	}

	if ($code eq "") {
		$code = scrapeGrantAccessPage($hash, $data);
		if ($code ne "") {
			MAH_Log($hash, 5, "Bearer found in HTML");
		}
	}

	if ($code eq "") {
		MAH_Log($hash, 2, "Error: Bearer code not found, giving up");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	MAH_doThirdpartyTokenRequest($hash, $code, "");
}

sub scrapeGrantAccessPage($$)
{
	my ($hash, $data) = (@_);

	# <form class="hidden" method="get" action="https://api.mcs3.miele.com/thirdparty/login/">
	# <input type="hidden" name="code" value="DE_...">
	# <input type="hidden" name="state" value="login">
	# <input id="button" class="waves-effect waves-light btn miele-red" type="submit"
	# value="ZULASSEN">
	# </form>

	if ($data !~ /name="code" value="([^"]+)"/) {
		MAH_Log($hash, 5, "code not found");
		return "";
	}
	my $code = $1;
	MAH_Log($hash, 2, "code found: $code");

	# check if it looks like the right page (this could be removed!)
	if (index($data, 'method="get" action="https://api.mcs3.miele.com/thirdparty/login/"') == -1) {
		MAH_Log($hash, 2, "get-action not found");
		return "";
	}

	return $code;
}

#------------------------------------------------------------------------------------------------------
# either use 2nd or 3rd parameter: 
#   2nd: do authorization_code
#   3rd: do refresh_token
sub MAH_doThirdpartyTokenRequest($$$)
{
	my ($hash, $bearerCode, $refreshToken) = @_;
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "called");

	my $clientId = AttrVal($name, "clientId", "");
	if ($clientId eq "") {
		readingsSingleUpdate($hash, "lastError", "clientId missing", 1);
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}
	my $clientSecret = MAH_getClientSecret($hash);
	if ($clientSecret eq "") {
		readingsSingleUpdate($hash, "lastError", "clientSecret missing", 1);
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	# Step 3: token
	my $url = "https://api.mcs3.miele.com/thirdparty/token/";
	my $data = "client_id="      . urlEncode($clientId)
	        .  "&client_secret=" . urlEncode($clientSecret);

	if ($bearerCode ne "") {
		$data .= "&grant_type=authorization_code"
		      .  "&code=" . urlEncode($bearerCode)
		      .  "&redirect_uri=https%3A%2F%2Fapi.mcs3.miele.com%2Fthirdparty%2Flogin%2F";
	} elsif ($refreshToken ne "") {
		$data .= "&grant_type=refresh_token"
		      .  "&refresh_token=" . urlEncode($refreshToken);
	} else {
		MAH_Log($hash, 1, "ERROR: called with neither bearerCode nor refreshToken, this is a bug. plz report!");
		return;
	}

	if ($bearerCode ne "") {
		readingsSingleUpdate($hash, "tokenRefreshCount_withBearer",       ReadingsNum($name, "tokenRefreshCount_withBearer", 0) + 1, 1);
	} else {
		readingsSingleUpdate($hash, "tokenRefreshCount_withRefreshToken", ReadingsNum($name, "tokenRefreshCount_withRefreshToken", 0) + 1, 1);
	}

	my ($err, $reply) = HttpUtils_NonblockingGet({
		url         => $url,
		data        => $data,
		timeout     => 5,
		hash        => $hash,
		method      => "POST",
		ignoreredirects => 1,
		callback    => \&MAH_onThirdpartyTokenReply,
	});
}
sub MAH_onThirdpartyTokenReply($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "reply: err:$err, code:$param->{code}, headers:$param->{httpheader}, data:$data");

	if ($err) {
		MAH_Log($hash, 3, "Error: $err");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	if ($param->{code} != 200) {
		MAH_Log($hash, 3, "Error: code != 200: $param->{code}");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	my $json = eval{decode_json($data)};
	if ($@) {
		MAH_Log($hash, 3, "JSON error while request: $@");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	if (ref($json) ne "HASH") {
		MAH_Log($hash, 3, "got wrong message for $name: $json");
		$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;
		return;
	}

	no strict "refs";

	$hash->{OAUTH2_ACCESS_TOKEN}  = $json->{access_token};
	$hash->{OAUTH2_REFRESH_TOKEN} = $json->{refresh_token};
	$hash->{OAUTH2_EXPIRES_IN}    = $json->{expires_in};
	$hash->{OAUTH2_EXPIRES_AT}    = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime(time + $json->{expires_in}));

	use strict "refs";

	# store in key/value so that they survive restart
	MAH_saveOAuth2Credentials($hash);

	# success
	$hash->{TOKEN_REFRESH_IN_PROGRESS} = 0;

	if (MAH_getAccessToken($hash) ne "") {
		InternalTimer(gettimeofday()+0, "MAH_updateValues", $hash);
	}
}

#------------------------------------------------------------------------------------------------------
# MAH_blockingGetAllDevicesRequest
#------------------------------------------------------------------------------------------------------
sub MAH_blockingGetAllDevicesRequest($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $token = MAH_getAccessToken($hash);
	if ($token eq "") {
		return "Please authenticate first";
	}

	my $lang = AttrVal($name, "lang", "en");
	my $url = "https://api.mcs3.miele.com/v1/devices/?language=${lang}";
	my $header = { "accept"        => "application/json; charset=utf-8",
	               "Authorization" => "Bearer " . $token };
	my ($err, $data) = HttpUtils_BlockingGet({
		url         => $url,
		header      => $header,
		timeout     => 5,
		hash        => $hash,
		method      => "GET",
	});

	MAH_Log($hash, 5, "reply: err:$err, data:$data");

	if ($err) {
		MAH_Log($hash, 3, "Error: $err");
		return $err;
	}

	my $decoded = eval{decode_json($data)};
	if ($@) {
		MAH_Log($hash, 3, "JSON error while request: $@");
		return;
	}

	if (ref($decoded) ne "HASH") {
		MAH_Log($hash, 3, "got wrong message for $name: $decoded");
		return;
	}

	no strict "refs";

	my @retval;
	foreach my $id (keys %{$decoded}) {
		push(@retval, [$id, $decoded->{$id}->{ident}->{type}->{value_localized}]);
	}

	use strict "refs";

	return \@retval;
}

#------------------------------------------------------------------------------------------------------
# MAH_sendGetDeviceIdentAndState
#------------------------------------------------------------------------------------------------------
sub MAH_sendGetDeviceIdentAndState($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $deviceId = $hash->{DEVICE_ID};
	if ($deviceId eq "") {
		return "Please set deviceId first";
	}

	my $token = MAH_getAccessToken($hash);
	if ($token eq "") {
		return "Please authenticate first";
	}

	my $lang = AttrVal($name, "lang", "en");
	my $url = "https://api.mcs3.miele.com/v1/devices/${deviceId}?language=${lang}";
	my $header = { "accept"        => "application/json; charset=utf-8",
	               "Authorization" => "Bearer " . $token };
	my ($err, $data) = HttpUtils_NonblockingGet({
		url         => $url,
		header      => $header,
		timeout     => 5,
		hash        => $hash,
		method      => "GET",
		callback    => \&MAH_onGetDeviceIdentAndStateReply,
	});
}
sub MAH_onGetDeviceIdentAndStateReply($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "reply: err:$err, code:$param->{code}, data:$data");

	if ($err) {
		MAH_Log($hash, 3, "Error: $err");
		return $err;
	}

	if ($param->{code} != 200) {
		MAH_Log($hash, 3, "Error: code != 200: $param->{code}");
		return "invalid status code: " . $param->{code};
	}

	my $json = eval{decode_json($data)};
	if ($@) {
		MAH_Log($hash, 3, "JSON error while request: $@");
		return;
	}

	if (ref($json) ne "HASH") {
		MAH_Log($hash, 3, "got wrong message for $name: $json");
		return;
	}

	# {"code":500,"message":"There was an error processing your request. It has been logged (ID xx)."}
	if (exists($json->{code})) {
		MAH_Log($hash, 3, "got error code: $json");
		return;
	}

	# decode_utf8() is required due do something like:
	# dein json ist utf8 aber das problem scheint zu sein das decode_json bei zeichen
	# <255 aus dem \u ein \x{..} macht. d.h. es erzeugt kein utf8 2-byte zeichen wie
	# es richtig wäre sondern macht aus dem code point ein 1-byte zeichen das dann
	# als latin-1 erscheint.

	no strict "refs";

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "communicationModuleReleaseVersion", encode_utf8($json->{ident}->{xkmIdentLabel}->{releaseVersion}));
	readingsBulkUpdate($hash, "communicationModuleTechType",       encode_utf8($json->{ident}->{xkmIdentLabel}->{techType}));
	readingsBulkUpdate($hash, "deviceHardwareFabIndex",            encode_utf8($json->{ident}->{deviceIdentLabel}->{fabIndex}));
	readingsBulkUpdate($hash, "deviceHardwareFabNumber",           encode_utf8($json->{ident}->{deviceIdentLabel}->{fabNumber}));
	readingsBulkUpdate($hash, "deviceHardwareMatNumber",           encode_utf8($json->{ident}->{deviceIdentLabel}->{matNumber}));
	readingsBulkUpdate($hash, "deviceHardwareTechType",            encode_utf8($json->{ident}->{deviceIdentLabel}->{techType}));
	readingsBulkUpdate($hash, "deviceName",                        encode_utf8($json->{ident}->{deviceName}));
	readingsBulkUpdate($hash, "deviceType",                        encode_utf8($json->{ident}->{type}->{value_localized}));

	readingsBulkUpdate($hash, "elapsedTime",           MAH_formatTime(@{$json->{state}->{elapsedTime}}));
	readingsBulkUpdate($hash, "remainingTime",         MAH_formatTime(@{$json->{state}->{remainingTime}}));
	readingsBulkUpdate($hash, "startTime",             MAH_formatTime(@{$json->{state}->{startTime}}));

	readingsBulkUpdate($hash, "dryingStep",            encode_utf8($json->{state}->{dryingStep}->{value_localized}));
	readingsBulkUpdate($hash, "light",                 encode_utf8($json->{state}->{light}));
	readingsBulkUpdate($hash, "programID",             encode_utf8($json->{state}->{ProgramID}->{value_localized}));
	readingsBulkUpdate($hash, "programPhase",          encode_utf8($json->{state}->{programPhase}->{value_localized}));
	readingsBulkUpdate($hash, "programType",           encode_utf8($json->{state}->{programType}->{value_localized}));
	readingsBulkUpdate($hash, "spinningSpeed",         encode_utf8($json->{state}->{spinningSpeed}->{value_localized}));
	readingsBulkUpdate($hash, "status",                encode_utf8($json->{state}->{status}->{value_localized}));
	readingsBulkUpdate($hash, "statusRaw",             $json->{state}->{status}->{value_raw});
	readingsBulkUpdate($hash, "ventilationStep",       encode_utf8($json->{state}->{ventilationStep}->{value_localized}));

	# not documented yet
	#readingsBulkUpdate($hash, "plateStep",             @{$json->{state}->{plateStep}});

	# not documented yet
	readingsBulkUpdate($hash, "ecoFeedbackCurrentWaterConsumption",   encode_utf8($json->{state}->{ecoFeedback}->{currentWaterConsumption}->{value}));
	readingsBulkUpdate($hash, "ecoFeedbackCurrentEnergyConsumption",  encode_utf8($json->{state}->{ecoFeedback}->{currentEnergyConsumption}->{value}));
	readingsBulkUpdate($hash, "ecoFeedbackWaterForecast",             encode_utf8($json->{state}->{ecoFeedback}->{waterForecast}));
	readingsBulkUpdate($hash, "ecoFeedbackEnergyForecast",            encode_utf8($json->{state}->{ecoFeedback}->{energyForecast}));

	readingsBulkUpdate($hash, "remoteEnableFullRC",    $json->{state}->{remoteEnable}->{fullRemoteControl});
	readingsBulkUpdate($hash, "remoteEnableSmartGrid", $json->{state}->{remoteEnable}->{smartGrid});
	readingsBulkUpdate($hash, "signalDoor",            $json->{state}->{signalDoor});
	readingsBulkUpdate($hash, "signalFailure",         $json->{state}->{signalFailure});
	readingsBulkUpdate($hash, "signalInfo",            $json->{state}->{signalInfo});

	# temperature
	readingsBulkUpdate($hash, "targetTemperature", MAH_decodeTemperature($hash, @{$json->{state}->{targetTemperature}}));
	readingsBulkUpdate($hash, "temperature",       MAH_decodeTemperature($hash, @{$json->{state}->{temperature}}));

	#eta & state
	my ($eta, $etaHR) = MAH_calculateETA($json->{state}->{remainingTime},
	                                     $json->{state}->{startTime},
	                                     $json->{state}->{status}->{value_raw});
	readingsBulkUpdate($hash, "eta",   $eta);
	readingsBulkUpdate($hash, "etaHR", $etaHR);
	readingsBulkUpdate($hash, "state", sprintf("%s (%s)",
	                   encode_utf8($json->{state}->{status}->{value_localized}), $eta));

	readingsEndUpdate($hash, 1 );

	use strict "refs";

	return undef;
}

#------------------------------------------------------------------------------------------------------
# MAH_sendGetDeviceActionsRequest
#------------------------------------------------------------------------------------------------------
sub MAH_sendGetDeviceActionsRequest($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $deviceId = $hash->{DEVICE_ID};
	if ($deviceId eq "") {
		return "Please set deviceId first";
	}

	my $token = MAH_getAccessToken($hash);
	if ($token eq "") {
		return "Please authenticate first";
	}

	my $lang = AttrVal($name, "lang", "en");
	my $url = "https://api.mcs3.miele.com/v1/devices/${deviceId}/actions?language=${lang}";
	my $header = { "accept"        => "application/json; charset=utf-8",
	               "Authorization" => "Bearer " . $token };
	my ($err, $data) = HttpUtils_NonblockingGet({
		url         => $url,
		header      => $header,
		timeout     => 5,
		hash        => $hash,
		method      => "GET",
		callback    => \&MAH_onGetDeviceActionsReply,
	});
}
sub MAH_onGetDeviceActionsReply($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "reply: err:$err, code:$param->{code}, data:$data");

	if ($err) {
		MAH_Log($hash, 3, "Error: $err");
		return $err;
	}

	if ($param->{code} != 200) {
		MAH_Log($hash, 3, "Error: code != 200: $param->{code}");
		return;
	}

	my $json = eval{decode_json($data)};
	if ($@) {
		MAH_Log($hash, 3, "JSON error while request: $@");
		return;
	}

	if (ref($json) ne "HASH") {
		MAH_Log($hash, 3, "got wrong message for $name: $json");
		return;
	}

	# {"code":500,"message":"There was an error processing your request. It has been logged (ID xx)."}
	if (exists($json->{code})) {
		MAH_Log($hash, 3, "got error code: $json");
		return;
	}

	# possible processAction out of
	# 1 START
	# 2 STOP
	# 3 PAUSE
	# 4 START SUPERFREEZING
	# 5 STOP SUPERFREEZING
	# 6 START SUPERCOOLING
	# 7 STOP SUPERCOOLING

	no strict "refs";

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "actions_processAction",   join(",", @{$json->{processAction}}));
	readingsBulkUpdate($hash, "actions_light",           join(",", @{$json->{light}}));
	readingsBulkUpdate($hash, "actions_startTime",       join(",", @{$json->{startTime}}));
	readingsBulkUpdate($hash, "actions_ventilationStep", join(",", @{$json->{ventilationStep}}));
	readingsBulkUpdate($hash, "actions_programId",       join(",", @{$json->{programId}}));
	readingsBulkUpdate($hash, "actions_startTime",       join(",", MAH_parseActionsStartTime($json->{startTime})));
	readingsBulkUpdate($hash, "actions_deviceName",      $json->{deviceName});
	readingsBulkUpdate($hash, "actions_powerOn",         defined($json->{powerOn})  ? $json->{powerOn}  : "0");
	readingsBulkUpdate($hash, "actions_powerOff",        defined($json->{powerOff}) ? $json->{powerOff} : "0");
	readingsEndUpdate($hash, 1 );

	use strict "refs";

	return undef;
}

#------------------------------------------------------------------------------------------------------
# format time from array
#------------------------------------------------------------------------------------------------------
sub MAH_decodeTemperature($@)
{
	my ($hash, @temps) = @_;
	my $name = $hash->{NAME};

	my @retval;
	foreach my $t (@temps) {
		if ($t->{value_raw} != -32768) {
			push(@retval, $t->{value_localized});
		}
	}

	return join(", ", @retval);
}

#------------------------------------------------------------------------------------------------------
# parse the startTime from actions which is either [] or [[0,0],[23,59]]
#------------------------------------------------------------------------------------------------------
sub MAH_parseActionsStartTime($)
{
	my ($startTime) = @_;

	my @startTimeArray = @{$startTime};
	if (scalar(@startTimeArray) == 0) {
		return "";
	}

	if (scalar(@startTimeArray) == 2) {
		return MAH_formatTime(@{$startTimeArray[0]}) . "-" . MAH_formatTime(@{$startTimeArray[1]});
	}

	return "[?]";
}

#------------------------------------------------------------------------------------------------------
# calculate the estimated time of arrival (as HH:MM and as human readable version)
#------------------------------------------------------------------------------------------------------
sub MAH_calculateETA($$$)
{
	my ($remaining, $start, $statusRaw) = @_;

	# 1 = OFF
	# 2 = ON
	# 3 = PROGRAMMED
	# 4 = PROGRAMMED WAITING TO START
	# 5 = RUNNING
	# 6 = PAUSE
	# 7 = END PROGRAMMED
	# 8 = FAILURE
	# 9 = PROGRAMME INTERRUPTED
	# 10 = IDLE
	# 11 = RINSE HOLD
	# 12 = SERVICE
	# 13 = SUPERFREEZING
	# 14 = SUPERCOOLING
	# 15 = SUPERHEATING
	# 146 = SUPERCOOLING_SUPERFREEZING
	# 255 = NOT_CONNECTED

	my ($remainingHour, $remainingMinute) = @{$remaining};
	my ($startHour,     $startMinute)     = @{$start};

	return ("-:-", "-:-") if ($statusRaw == 1 || $statusRaw == 255); # Off

	my $startOffsetSecs = $startHour     * 3600 + $startMinute     * 60;
	my $remainingSecs   = $remainingHour * 3600 + $remainingMinute * 60;

	if ($statusRaw == 4) { # delay active
		my $eta   = POSIX::strftime("%H:%M", localtime(time + $startOffsetSecs + $remainingSecs));
		my $etaHR = $eta;
		return ($eta, $etaHR);
	}

	if ($statusRaw == 2 || $statusRaw == 7) { # On (but not running) or End
		my $eta   = POSIX::strftime("%H:%M", localtime(time + $remainingSecs)); # ignore startOffsetSecs here as this is very strange
		my $etaHR = "+" . MAH_formatTime($remainingHour, $remainingMinute);
		$etaHR = "Ende" if ($remainingHour == 0 && $remainingMinute == 0);
		return ($eta, $etaHR);
	}

	# if ($statusRaw == 5) { # In Betrieb
		my $eta   = POSIX::strftime("%H:%M", localtime(time + $remainingSecs)); # ignore startOffsetSecs here as this is very strange
		my $etaHR = $eta;

		# write remaining minutes in the last 15 minutes instead of
		$etaHR = "+" . MAH_formatTime($remainingHour, $remainingMinute) if ($remainingSecs <= 15 * 60);

		return ($eta, $etaHR);
	# }
	# return POSIX::strftime("%Y-%m-%d %H:%M", localtime(time + $offset));
}

#------------------------------------------------------------------------------------------------------
# format time from array
#------------------------------------------------------------------------------------------------------
sub MAH_formatTime(@)
{
	my ($hour, $minute) = @_;
	return sprintf("%d:%02d", $hour, $minute);
}

#------------------------------------------------------------------------------------------------------
# MAH_autocreate
#------------------------------------------------------------------------------------------------------
sub MAH_autocreate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $devices = MAH_blockingGetAllDevicesRequest($hash);
	if(ref($devices) ne 'ARRAY') {
		readingsSingleUpdate($hash, "lastError", "autocreate failed: $devices", 1);
		return;
	}

	for my $d (@{$devices}) {
		my $deviceId = @{$d}[0];
		if (defined($modules{MieleAtHome}{defptr}{"deviceid_".$deviceId})) {
			MAH_Log($hash, 3, "autocreate - device with deviceId $deviceId already exists");
		} else {
			my $nameOfDevice = "Miele_${deviceId}";
			if (IsDevice($nameOfDevice)) {
				MAH_Log($hash, 3, "not autocreating device, as device with proposed name already exists (${nameOfDevice})");
			} else {
				fhem("define $nameOfDevice MieleAtHome ${deviceId}\@${name}");
				if (IsDevice($nameOfDevice)) {
					# return "Can't create, device $nameOfDevice already existing."
					# 	unless (IsDevice($nameOfDevice, "IPCAM"));

					fhem("attr ".$nameOfDevice." comment Auto-created by $name")
						unless (defined($attr{$nameOfDevice}{comment}));

					MAH_Log($hash, 3, "created device ${nameOfDevice}, with deviceId ${deviceId}");
				}
			}
		}
	}
}

#------------------------------------------------------------------------------------------------------
# MAH_setPower
#------------------------------------------------------------------------------------------------------
sub MAH_setPower($$)
{
	my ($hash, $onOrOff) = @_;
	my $name = $hash->{NAME};

	if ($onOrOff eq "on") {
		return "power 'on' is currently not available" if (ReadingsNum($name, "actions_powerOn", 0) != 1);
		return MAH_setAction($hash, "powerOn", "true");
	} elsif ($onOrOff eq "off") {
		return "power 'off' is currently not available" if (ReadingsNum($name, "actions_powerOff", 0) != 1);
		return MAH_setAction($hash, "powerOff", "true");
	} else {
		return "use either 'on' or 'off'";
	}
}

#------------------------------------------------------------------------------------------------------
# MAH_setProcessAction
#------------------------------------------------------------------------------------------------------
sub MAH_setProcessAction($$)
{
	my ($hash, $processActionName) = @_;
	my $name = $hash->{NAME};

	my ($processActionId) = grep{ PROCESS_ACTIONS->{$_} eq $processActionName } keys %{PROCESS_ACTIONS()};
	if (!defined $processActionId) {
		return "invalid processAction: '${processActionName}'";
	}

	my @availableProcessActions = split(/,/, ReadingsVal($name, "actions_processAction", ""));
	if (! grep {$_ eq $processActionId} @availableProcessActions) {
		return "'${processActionName}' is currently not available";
	}

	return MAH_setAction($hash, "processAction", "${processActionId}");
}

#------------------------------------------------------------------------------------------------------
# MAH_setLight
#------------------------------------------------------------------------------------------------------
sub MAH_setLight($$)
{
	my ($hash, $lightActionName) = @_;
	my $name = $hash->{NAME};

	my ($lightActionId) = grep{ LIGHT_ACTIONS->{$_} eq $lightActionName } keys %{LIGHT_ACTIONS()};
	if (!defined $lightActionId) {
		return "invalid light action: '${lightActionName}'";
	}

	my @availableLightActions = split(/,/, ReadingsVal($name, "actions_light", ""));
	if (! grep {$_ eq $lightActionId} @availableLightActions) {
		return "'${lightActionName}' is currently not available";
	}

	return MAH_setAction($hash, "light", "${lightActionId}");
}

#------------------------------------------------------------------------------------------------------
# MAH_setVentilationStep
#------------------------------------------------------------------------------------------------------
sub MAH_setVentilationStep($$)
{
	my ($hash, $ventilationStepName) = @_;
	my $name = $hash->{NAME};

	my ($ventilationStepId) = grep{ VENTILATION_STEPS->{$_} eq $ventilationStepName } keys %{VENTILATION_STEPS()};
	if (!defined $ventilationStepId) {
		return "invalid ventilation step: '${ventilationStepName}'";
	}

	my @availableVentilationStepIds = split(/,/, ReadingsVal($name, "actions_ventilationStep", ""));
	if (! grep {$_ eq $ventilationStepId} @availableVentilationStepIds) {
		return "'${ventilationStepName}' is currently not available";
	}

	return MAH_setAction($hash, "ventilationStep", "${ventilationStepId}");
}

#------------------------------------------------------------------------------------------------------
# MAH_setStartTime
#------------------------------------------------------------------------------------------------------
sub MAH_setStartTime($$)
{
	my ($hash, $startTimeString) = @_;
	my $name = $hash->{NAME};

	if ($startTimeString =~ m/$[0-9]+:[0-9]+]^/) {
		return "invalid startTime format: '${startTimeString}', offset must be [h]h:mm";
	}

	if (ReadingsNum($name, "actions_startTime", 0) != 1) {
		return "'startTime' is currently not setable";
	}

	$startTimeString =~ s/:/,/;
	return MAH_setAction($hash, "startTime", "[${startTimeString}]");
}

#------------------------------------------------------------------------------------------------------
# MAH_setAction
#------------------------------------------------------------------------------------------------------
sub MAH_setAction($$$)
{
	my ($hash, $action, $value) = @_;

	my $actionJson = "{\"$action\":$value}";
	return MAH_sendSetActionRequest($hash, $actionJson);
}

#------------------------------------------------------------------------------------------------------
# MAH_sendSetActionRequest, $action needs to be the json-encoded action like »{"powerOn":true}«
#------------------------------------------------------------------------------------------------------
sub MAH_sendSetActionRequest($$)
{
	my ($hash, $action) = @_;
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "called with action $action");

	my $deviceId = $hash->{DEVICE_ID};
	if ($deviceId eq "") {
		return "Please set deviceId first";
	}

	my $token = MAH_getAccessToken($hash);
	if ($token eq "") {
		return "Please authenticate first";
	}

	my $url = "https://api.mcs3.miele.com/v1/devices/${deviceId}/actions";
	my $header = { "accept"        => "*/*",
	               "Content-Type"  => "application/json",
	               "Authorization" => "Bearer " . $token };
	my ($err, $reply) = HttpUtils_NonblockingGet({
		url         => $url,
		header      => $header,
		timeout     => 30, # this somethimes takes soooome time
		hash        => $hash,
		method      => "PUT",
		data        => $action,
		callback    => \&MAH_onSetActionReply,
	});

	return undef;
}
sub MAH_onSetActionReply($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	MAH_Log($hash, 5, "reply: err:$err, code:$param->{code}, data:$data");

	if ($err) {
		MAH_Log($hash, 3, "Error: $err");
		return $err;
	}

	# it generally takes some time for the API to react to changes
	InternalTimer(gettimeofday()+5, "MAH_sendGetDeviceActionsRequest", $hash);
}

#------------------------------------------------------------------------------------------------------
# * if it is a duplicate instance -> bah
# * if disabled -> ...
#------------------------------------------------------------------------------------------------------
sub MAH_isDisabled($)
{
	my ($hash) = @_;
	return $hash->{DUPLICATE_INSTANCE} ||
	       AttrVal($hash->{NAME}, "disable", "") ||
	       IsDisabled($hash->{NAME});
}

#------------------------------------------------------------------------------------------------------
# MAH_hasLoginCredentials
#------------------------------------------------------------------------------------------------------
sub MAH_hasLoginCredentials($)
{
	my ($hash) = @_;

	return 0 unless (defined(MAH_getClientId($hash)));
	return 0 unless (defined(MAH_getLogin($hash)));
	return 0 unless (defined(MAH_getPassword($hash)));
	return 0 unless (defined(MAH_getClientSecret($hash)));
	return 1;
}

#------------------------------------------------------------------------------------------------------
# MAH_getClientId(), MAH_getLogin(), MAH_getPassword(), MAH_getClientSecret()
#------------------------------------------------------------------------------------------------------
sub MAH_getClientId($); # workaround for perl warning
sub MAH_getClientId($)
{
	my ($hash) = @_;

	my $retval = AttrVal($hash->{NAME}, "clientId", "");
	return $retval if ($retval ne "");

	my $iohash = MAH_getIODevHash($hash);
	return MAH_getClientId($iohash) if (defined($iohash));

	return undef;
}
sub MAH_getLogin($); # workaround for perl warning
sub MAH_getLogin($)
{
	my ($hash) = @_;

	my $retval = AttrVal($hash->{NAME}, "login", "");
	return $retval if ($retval ne "");

	my $iohash = MAH_getIODevHash($hash);
	return MAH_getLogin($iohash) if (defined($iohash));

	return undef;
}
sub MAH_getPassword($); # workaround for perl warning
sub MAH_getPassword($)
{
	my ($hash) = @_;

	my $retval = MAH_loadPassword($hash);
	return $retval if (defined($retval));

	my $iohash = MAH_getIODevHash($hash);
	return MAH_getPassword($iohash) if (defined($iohash));

	return undef;
}
sub MAH_getClientSecret($); # workaround for perl warning
sub MAH_getClientSecret($)
{
	my ($hash) = @_;

	my $retval = MAH_loadClientSecret($hash);
	return $retval if (defined($retval));

	my $iohash = MAH_getIODevHash($hash);
	return MAH_getClientSecret($iohash) if (defined($iohash));

	return undef;
}
sub MAH_getAccessToken($); # workaround for perl warning
sub MAH_getAccessToken($)
{
	my ($hash) = @_;

	# try to find token
	my $accessToken = MAH_getAccessTokenPrivate($hash);
	if ($accessToken ne "") {
		my $secs = MAH_getRemainingTokenLifetime($hash);
		MAH_Log($hash, 4, "found local token with remaining lifetime of ${secs} seconds");
		MAH_refreshAccessToken($hash) if ($secs < 24 * 60 * 60);
		return $accessToken           if ($secs > 0);
	}

	# if we could not find a token, refrehs it async
	MAH_refreshAccessToken($hash);

	return "";
}
sub MAH_getAccessTokenPrivate($); # workaround for perl warning
sub MAH_getAccessTokenPrivate($)
{
	my ($hash) = @_;

	# try to find local token
	if (defined($hash->{OAUTH2_ACCESS_TOKEN})) {
		return $hash->{OAUTH2_ACCESS_TOKEN};
	}

	# try to find token in IODev
	my $iohash = MAH_getIODevHash($hash);
	return MAH_getAccessTokenPrivate($iohash) if (defined($iohash));

	return "";
}
sub MAH_getRefreshTokenPrivate($); # workaround for perl warning
sub MAH_getRefreshTokenPrivate($)
{
	my ($hash) = @_;

	# try to find local token
	if (defined($hash->{OAUTH2_REFRESH_TOKEN})) {
		return $hash->{OAUTH2_REFRESH_TOKEN};
	}

	# try to find token in IODev
	my $iohash = MAH_getIODevHash($hash);
	return MAH_getRefreshTokenPrivate($iohash) if (defined($iohash));

	return "";
}
sub MAH_getRemainingTokenLifetime($); # workaround for perl warning
sub MAH_getRemainingTokenLifetime($)
{
	my ($hash) = @_;

	if (defined($hash->{OAUTH2_EXPIRES_AT})) {
		my $secs = time_str2num($hash->{OAUTH2_EXPIRES_AT}) - time;
		return $secs;
	}

	# try to find token in IODev
	my $iohash = MAH_getIODevHash($hash);
	return MAH_getRemainingTokenLifetime($iohash) if (defined($iohash));

	return 0;
}


#------------------------------------------------------------------------------------------------------
# MAH_getIODevHash
#------------------------------------------------------------------------------------------------------
sub MAH_getIODevHash($)
{
	my ($hash) = @_;

	return undef unless (defined($hash->{IODevName}));
	return undef unless (defined($defs{$hash->{IODevName}}));
	return $defs{$hash->{IODevName}};
}

#------------------------------------------------------------------------------------------------------
# Util: clientSecret
#------------------------------------------------------------------------------------------------------
sub MAH_saveClientSecret($$)
{
	my ($hash,$clientSecret) = @_;
	return MAH_setKeyValue($hash, "clientSecret", $clientSecret);
}
sub MAH_loadClientSecret($)
{
	my ($hash) = @_;
	return MAH_getKeyValue($hash, "clientSecret");
}
sub MAH_renameClientSecret($$$)
{
	my ($newHash,$oldName,$newName) = @_;
	MAH_renameKeyValue($newHash, $oldName, $newName, "clientSecret");
}
sub MAH_deleteClientSecret($)
{
	my ($hash) = @_;
	return MAH_deleteKeyValue($hash, "clientSecret");
}

#------------------------------------------------------------------------------------------------------
# Util: password
#------------------------------------------------------------------------------------------------------
sub MAH_savePassword($$)
{
	my ($hash,$password) = @_;
	return MAH_setKeyValue($hash, "passwd", $password);
}
sub MAH_loadPassword($)
{
	my ($hash) = @_;
	return MAH_getKeyValue($hash, "passwd");
}
sub MAH_renamePassword($$$)
{
	my ($newHash,$oldName,$newName) = @_;
	MAH_renameKeyValue($newHash, $oldName, $newName, "passwd");
}
sub MAH_deletePassword($)
{
	my ($hash) = @_;
	return MAH_deleteKeyValue($hash, "passwd");
}

#------------------------------------------------------------------------------------------------------
# Util: oauth2 credentials
#------------------------------------------------------------------------------------------------------
sub MAH_saveOAuth2Credentials($)
{
	my ($hash) = @_;

	MAH_setKeyValue($hash, "OAUTH2_ACCESS_TOKEN",  $hash->{OAUTH2_ACCESS_TOKEN});
	MAH_setKeyValue($hash, "OAUTH2_REFRESH_TOKEN", $hash->{OAUTH2_REFRESH_TOKEN});
	MAH_setKeyValue($hash, "OAUTH2_EXPIRES_IN",    $hash->{OAUTH2_EXPIRES_IN});
	MAH_setKeyValue($hash, "OAUTH2_EXPIRES_AT",    $hash->{OAUTH2_EXPIRES_AT});
}
sub MAH_restoreOAuth2Credentials($)
{
	my ($hash) = @_;

	my $v = MAH_getKeyValue($hash, "OAUTH2_ACCESS_TOKEN");
	if (defined($v) && !defined($hash->{OAUTH2_ACCESS_TOKEN})) {
		$hash->{OAUTH2_ACCESS_TOKEN} = $v;
	}

	$v = MAH_getKeyValue($hash, "OAUTH2_REFRESH_TOKEN");
	if (defined($v) && !defined($hash->{OAUTH2_REFRESH_TOKEN})) {
		$hash->{OAUTH2_REFRESH_TOKEN} = $v;
	}

	$v = MAH_getKeyValue($hash, "OAUTH2_EXPIRES_IN");
	if (defined($v) && !defined($hash->{OAUTH2_EXPIRES_IN})) {
		$hash->{OAUTH2_EXPIRES_IN} = $v;
	}

	$v = MAH_getKeyValue($hash, "OAUTH2_EXPIRES_AT");
	if (defined($v) && !defined($hash->{OAUTH2_EXPIRES_AT})) {
		$hash->{OAUTH2_EXPIRES_AT} = $v;
	}
}
sub MAH_renameOAuth2Credentials($$$)
{
	my ($newHash,$oldName,$newName) = @_;
	MAH_renameKeyValue($newHash, $oldName, $newName, "OAUTH2_ACCESS_TOKEN");
	MAH_renameKeyValue($newHash, $oldName, $newName, "OAUTH2_REFRESH_TOKEN");
	MAH_renameKeyValue($newHash, $oldName, $newName, "OAUTH2_EXPIRES_IN");
	MAH_renameKeyValue($newHash, $oldName, $newName, "OAUTH2_EXPIRES_AT");
}
sub MAH_deleteOAuth2Credentials($)
{
	my ($hash) = @_;
	MAH_deleteKeyValue($hash, "OAUTH2_ACCESS_TOKEN");
	MAH_deleteKeyValue($hash, "OAUTH2_REFRESH_TOKEN");
	MAH_deleteKeyValue($hash, "OAUTH2_EXPIRES_IN");
	MAH_deleteKeyValue($hash, "OAUTH2_EXPIRES_AT");
}

#------------------------------------------------------------------------------------------------------
# Util: MAH_setKeyValue
#------------------------------------------------------------------------------------------------------
sub MAH_setKeyValue($$$)
{
	my ($hash,$subkey,$value) = @_;
	my $type = $hash->{TYPE};
	my $name = $hash->{NAME};

	my $key = "${type}_${name}_${subkey}";

	# always prepend passwords with '=' to allow to upgrade from having no
	# base64 encoding to using base64. decode_base64() ignores everything
	# after the '=' so if we try to decode a not decoded password (starting
	# with '='), this will result in an empty value which can be detected.
	$value = "=" . $value;

	# base64 encode if possible
	$value = encode_base64($value) if ($MAH_hasMimeBase64);

	my $err = setKeyValue($key, $value);
	MAH_Log($hash, 3, "Error when setting $key: $err") if ($err);
	return $err;
}

#------------------------------------------------------------------------------------------------------
# Util: MAH_getKeyValue
#------------------------------------------------------------------------------------------------------
sub MAH_getKeyValue($$)
{
	my ($hash,$subkey) = @_;
	my $type = $hash->{TYPE};
	my $name = $hash->{NAME};

	my $key = "${type}_${name}_${subkey}";
	my ($err, $value) = getKeyValue($key);

	# error
	if ($err) {
		MAH_Log($hash, 3, "Error when fetching $key: $err");
		return undef;
	}

	# no value found
	return undef unless (defined($value));

	my $retval = $value;
	if ($MAH_hasMimeBase64) {
		# try to base64-decode the retval.
		$retval = decode_base64($value);

		# if it is empty, it was not encoded (as decode_base64() ignores everything
		# after our initial '=')
		$retval = $value if ($retval eq "");
	}

	# our retval is always stored with a leading '='
	if ($retval !~ /^=.*/) {
		MAH_Log($hash, 3, "failed to fetch retval: $retval");
		return undef;
	}

	# remove the leading '=' which was added in MAH_setBasicAuth()
	return substr($retval, 1);
}

#------------------------------------------------------------------------------------------------------
# Util: MAH_renameKeyValue
#------------------------------------------------------------------------------------------------------
sub MAH_renameKeyValue($$$$)
{
	my ($newHash,$oldName,$newName,$subkey) = @_;
	my $type = $newHash->{TYPE};

	my $oldKey = "${type}_${oldName}_${subkey}";
	my $newKey = "${type}_${newName}_${subkey}";

	my ($err, $data) = getKeyValue($oldKey);
	return undef unless(defined($data));

	setKeyValue($newKey, $data);
	setKeyValue($oldKey, undef);
}

#------------------------------------------------------------------------------------------------------
# Util: MAH_deleteKeyValue
#------------------------------------------------------------------------------------------------------
sub MAH_deleteKeyValue($$)
{
	my ($hash,$subkey) = @_;
	my $type = $hash->{TYPE};
	my $name = $hash->{NAME};

	my $key = "${type}_${name}_${subkey}";
	my $err = setKeyValue($key, undef);
}

#------------------------------------------------------------------------------------------------------
# Util: Log
#------------------------------------------------------------------------------------------------------
sub MAH_Log($$$)
{
	my ($hash, $logLevel, $logMessage) = @_;
	my $line       = ( caller(0) )[2];
	my $modAndSub  = ( caller(1) )[3];
	my $subroutine = ( split(':', $modAndSub) )[2];
	my $name       = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : "MieleAtHome";

	Log3($hash, $logLevel, "${name} (MieleAtHome::${subroutine}:${line}) " . $logMessage);
	#Log3($hash, $logLevel, "${name} (MieleAtHome::${subroutine}:${line}) Stack was: " . MAH_getStacktrace());
}

#------------------------------------------------------------------------------------------------------
# Util: returns a stacktrace as a string (for debbugging)
#------------------------------------------------------------------------------------------------------
sub MAH_getStacktrace()
{
	my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash);
	my $i = 2; # skip MAH_getStacktrace() and MAH_Log()
	my @r;
	my $retval = "";
	while (@r = caller($i)) {
		($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = @r;
		$subroutine = ( split( ':', $subroutine ) )[2];
		$retval = "->${line}:${subroutine}${retval}";
		$i++;
	}
	return $retval;
}


# must be last
1;


=pod
=item device
=item summary    Module to control Miele@home-devices via their 3rd party API
=item summary_DE Modul zur Steuerung von Miele@home-Geräten mittels 3rd Party API

=begin html

<a id="MieleAtHome"></a>
<h3>MieleAtHome</h3>
<ul>
	<u><b>MieleAtHome - Controls Miele@home Devices</b></u><br>
	<br>
	<b>About</b><br>
	<br> 
	The MieleAtHome module uses the Miele 3rd Party Cloud API. You need a Miele Developer Account to use it! See below for details.<br>
	To use the MieleAtHome module you first have to define a device which will act als shared provider for your credentials. When this one is set up, you can use the <code>autocreate</code>-feature to create devices for your appliances.<br>
	<br>
	<b>Miele Developer Account:</b><br>
	<br>
	To use this module you need to register as a developer at <a href="https://www.miele.com/f/com/en/register_api.aspx">https://www.miele.com/f/com/en/register_api.aspx</a>. After you successfully registered, you will receive a <i>clientId</i> and a <i>clientSecret</i> which you'll need to configure in your <code>&lt;gateway&gt;</code>-device.<br>
	<br>
	<a id="MieleAtHome-define"></a>
	<b>Define</b><br>
	<br>
	<u>(1) Setup gateway:</u><br>
	<code>define &lt;gateway&gt; MieleAtHome</code><br>
	<br>
	<u>(2a) Autocreate devices:</u><br>
	<code>set &lt;gateway&gt; autocreate</code><br>
	<br>
	<u>(2b) Manually create devices:</u><br>
	<code>define &lt;MieleDevice&gt; MieleAtHome &lt;DeviceId&gt;@&lt;gateway&gt; [Interval]</code><br>
	<br>
	<b>Example</b><br>
	<br>
	<u>(1) Setup gateway:</u><br>
	<code>define MieleConnection MieleAtHome</code><br>
	<code>attr MieleConnection login mylogin@example.com</code><br>
	<code>attr MieleConnection clientId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx</code><br>
	<code>set  MieleConnection password mypassword</code><br>
	<code>set  MieleConnection clientSecret yyyyyyyyyyyyyyyyyyyy</code><br>
	<br>
	This instance (MieleConnection) will be used to share the credentials. You have to set the attributes <i>login</i> and <i>clientId</i>. Then you have to set <i>password</i> and <i>clientSecret</i> via <code>set MieleConnection</code>-command.<br>
	<br>
	<u>(2a) Autocreate devices:</u><br>
	<code>set MieleConnection autocreate</code><br>
	<br>
	This will create a device called <code>Miele_xxxxxxxxxxxxx</code>. You can rename autocreated devices afterwards.<br>
	<br>
	<u>(2b) Manually create devices:</u><br>
	<code>define Waschmaschine MieleAtHome 000123456789@MieleConnection 120</code><br>
	<br>
	This statement creates the instance of your specific Miele@home appliance with the name Waschmaschine and the DeviceId 000123456789 and a refresh-interval of 120 seconds. The interval is optional, its default is 120 seconds.<br>
	<br>

<!--
	<a name="MieleAtHomereadings"></a>
	<b>Readings</b>
	<ul>
		<li>
			<i>event</i><br>
			contains the last event that was triggered by the ALP-600. (<code>motion</code> or <code>ring</code>).
		</li>
		<li>
			<i>motion</i><br>
			the timestamp of the last <code>motion</code> event triggered by the ALP-600.
		</li>
		<li>
			<i>ping</i><br>
			The ping status of the ALP-600 (<code>disabled</code>, <code>ok</code> or <code>unreachable</code>).
		</li>
		<li>
			<i>ring</i><br>
			the timestamp of the last <code>ring</code> event triggered by the ALP-600.
		</li>
	</ul>
	<br>

		<li><a name="altitude"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>altitude </b>&lt;<b>height</b>&gt;</code></dt>
			Specifies the mean sea level in meters. Default is 0. Used to calculate the <code>pressureRel_calculated</code>-reading. If unset, the altitude from global is used.
		</li>

-->
	<a id="MieleAtHome-set"></a>
	<b>Set</b>
	<ul>
		<li><a id="MieleAtHome-set-autocreate"></a>
			<dt><code><b>autocreate</b></code></dt>
			autocreate fhem-devices for each Miele@home appliance found in your account. Needs <i>login</i>, <i>clientId</i>, <i>password</i> and <i>clientSecret</i> to be configured properly. Only available for the gateway device.
		</li>
		<li><a id="MieleAtHome-set-clientSecret"></a>
			<dt><code><b>clientSecret &lt;secret&gt;</b></code></dt>
			sets the <i>clientSecret</i> of your Miele@home-developer Account and stores it in a file (base64-encoded if you have MIME::Base64 installed).
		</li>
		<li><a id="MieleAtHome-set-light"></a>
			<dt><code><b>light [enable|disable]</b></code></dt>
			enable/disable the light of your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-on"></a>
			<dt><code><b>on</b></code></dt>
			power up your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-off"></a>
			<dt><code><b>off</b></code></dt>
			power off your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-password"></a>
			<dt><code><b>password &lt;pass&gt;</b></code></dt>
			set the <i>password</i> of your Miele@home Account and stores it in a file (base64-encoded if you have MIME::Base64 installed).
		</li>
		<li><a id="MieleAtHome-set-pause"></a>
			<dt><code><b>pause</b></code></dt>
			pause your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-start"></a>
			<dt><code><b>start</b></code></dt>
			start your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-startTime"></a>
			<dt><code><b>startTime &lt;[H]H:MM&gt;</b></code></dt>
			modify the start time of your device relative from current time. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-stop"></a>
			<dt><code><b>stop</b></code></dt>
			stop your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-startSuperFreezing"></a>
			<dt><code><b>startSuperFreezing</b></code></dt>
			start super freezing your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-stopSuperFreezing"></a>
			<dt><code><b>stopSuperFreezing</b></code></dt>
			stop super freezing your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-startSuperCooling"></a>
			<dt><code><b>startSuperCooling</b></code></dt>
			start super cooling your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-stopSuperCooling"></a>
			<dt><code><b>stopSuperCooling</b></code></dt>
			stop super cooling your device. only available depending on the type and state of your appliance.
		</li>
		<li><a id="MieleAtHome-set-update"></a>
			<dt><code><b>update</b></code></dt>
			instantly update all readings.
		</li>
		<li><a id="MieleAtHome-set-ventilationStep"></a>
			<dt><code><b>ventilationStep [Step1|Step2|Step3|Step4]</b></code></dt>
			set the ventilation step of your device. only available depending on the type and state of your appliance.
		</li>
	</ul>
	<br>

	<a id="MieleAtHome-get"></a>
	<b>Get</b>
	<ul>
		<li><a id="MieleAtHome-get-listDevices"></a>
			<dt><code><b>listDevices</b></code></dt>
			lists the devices associated with your Miele@home-account. Needs <i>login</i>, <i>clientId</i>, <i>password</i> and <i>clientSecret</i> to be configured properly.
		</li>
	</ul>
	<br>

	<a id="MieleAtHome-attr"></a>
	<b>Attributes</b>
	<ul>
		<li><a id="MieleAtHome-attr-clientId"></a>
			<dt><code><b>clientId</b></code></dt>
			set the <i>clientId</i> of your Miele@home-developer account.
		</li>
		<li><a id="MieleAtHome-attr-country"></a>
			<dt><code><b>country</b></code></dt>
			set the <i>country</i> where you registered your Miele@home account.
		</li>
		<li><a id="MieleAtHome-attr-login"></a>
			<dt><code><b>login</b></code></dt>
			set the <i>login</i> of your Miele@home account.
		</li>
		<li><a id="MieleAtHome-attr-disable"></a>
			<dt><code><b>disable</b></code></dt>
			disables this MieleAtHome-instance.
		</li>
		<li><a id="MieleAtHome-attr-lang"></a>
			<dt><code><b>lang [de|en]</b></code></dt>
			request the readings in either german or english. <i>en</i> is default.
		</li>
	</ul>
</ul>

=end html
# =begin html_DE
#
#
# =end html_DE
=cut

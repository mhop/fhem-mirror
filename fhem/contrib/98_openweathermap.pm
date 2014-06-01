# $Id: 98_openweathermap.pm 5500 2014-04-09 18:57:05Z betateilchen $
##############################################################################
#
#	98_openweathermap.pm
#	An FHEM Perl module connecting to www.openweathermap.org (owo)
#	providing the following tasks:
#
#	1.	send weather data from your own weather station to owo network
#
#	2.	set a wheater station as datasource inside your fhem installation
#
#	3.	retrieve wheather date via owo APII from any weather station
#		inside owo network
#
#	All tasks can be accessed single or in any desired combination.
#	Copyright: betateilchen ®
#	e-mail   : fhem.development@betateilchen.de
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#	Changelog:
#
#	2013-07-28	initial release
#
#	2013-07-29	fixed:	some typos in documentation
#				added:	"set <name> send"
#
#	2013-07-30	modi:	replaced try/catch by eval
#				added:	some more logging
#				added:	delete some station readings before update
#				added:	attribute owoSendUrl
#
#	2013-08-08	added:	proxy support by reading env-Settings
#
#	2013-08-11	modi:	switched from GetLogLevel() to Log3()
#				fixed:	use JSON (due to Fritzbox problems)
#
#	2013-08-12	added:	XML for decoding, controlled by attribute owoUseXml
#				added:	attribute owoProxy for proxy configuration
#
#	2013-08-13	added:	new reading for html response on "send"
#				added:	new reading for html response on "get/set"
#	2013-10-12	added:	NotifyFn
#
#	2013-12-08	fixed:	first try to remove duplicate processing
#
#	2014-02-04	added:	shutdownFn
#
#	2014-02-14	modi:	changed Loglevel from 3 to 4 where possible
#
#	2014-03-22	added:	added set command 'clear'
#

package main;

use strict;
use warnings;
use POSIX;
use XML::Simple;
eval {require JSON};
use feature qw/say switch/;

require LWP::UserAgent;			# test
my	$ua = LWP::UserAgent->new;	# test
	$ua->timeout(10);				# test
	$ua->env_proxy;					# test

sub OWO_abs2rel($$$);
sub OWO_isday($$);

###################################

sub openweathermap_Initialize($) {
	my ($hash) = @_;
	$hash->{SetFn}		=	"OWO_Set";
	$hash->{GetFn}		=	"OWO_Get";
	$hash->{DefFn}		=	"OWO_Define";
	$hash->{UndefFn}	=	"OWO_Undefine";
	$hash->{NotifyFn}	=	"OWO_Notify";
	$hash->{AttrFn}		=	"OWO_Attr";
	$hash->{ShutdownFn}	=	"OWO_Shutdown";

	$hash->{AttrList}	=	"do_not_notify:0,1 ".
							"owoGetUrl owoSendUrl owoInterval:600,900,1800,3600 ".
							"owoApiKey owoProxy owoStation owoUser owoUseXml:1,0 ".
							"owoDebug:0,1 owoRaw:0,1 owoTimestamp:0,1 ".
							"owoSrc00 owoSrc01 owoSrc02 owoSrc03 owoSrc04 ".
							"owoSrc05 owoSrc06 owoSrc07 owoSrc08 owoSrc09 ".
							"owoSrc10 owoSrc11 owoSrc12 owoSrc13 owoSrc14 ".
							"owoSrc15 owoSrc16 owoSrc17 owoSrc18 owoSrc19 ".
							$readingFnAttributes;
}


sub OWO_Shutdown($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 ($name,4,"owo $name: shutdown requested");
	return undef;
}

sub OWO_Set($@){
	my ($hash, @a)	= @_;
	my $name		= $hash->{NAME};
	my $usage		= "Unknown argument, choose one of clear:noArg stationById stationByGeo stationByName send:noArg";
	my $response;
	
	return "No Argument given" if(!defined($a[1]));

	my $urlString = AttrVal($name, "owoGetUrl", undef);
	return "Please set attribute owoGetUrl!" if(!defined($urlString));

	my $cmd		=	$a[1];
	
	given($cmd){
		when("?")		{ return $usage; }
		
		when("clear"){
			CommandDeleteReading(undef, "$name _.*");
			CommandDeleteReading(undef, "$name c_.*");
			CommandDeleteReading(undef, "$name g_.*");
			return;
		}

		when("send"){
			OWO_GetStatus($hash,1);
			return;
		}

		when("stationByName"){
			$urlString = $urlString."?q=";
			my $count;
			my $element = @a;
			for ($count = 2; $count < $element; $count++) {
				$urlString = $urlString."%20".$a[$count];
			}
		}

		when("stationById"){
			$urlString = $urlString."?id=".$a[2];
		}

		when("stationByGeo"){
			$a[2] = AttrVal("global", "latitude", 0) unless(defined($a[2]));
			$a[3] = AttrVal("global", "longitude", 0) unless(defined($a[3]));
			$urlString = $urlString."?lat=$a[2]&lon=$a[3]";
		}

		default: { return $usage; }
	}

	UpdateReadings($hash, $urlString, "c_");
	

	return;
}

sub OWO_Get($@){
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage = "Unknown argument, choose one of stationById stationByGeo stationByName";
	my $response;
	
	return "No Argument given" if(!defined($a[1]));

	my $urlString = AttrVal($name, "owoGetUrl", undef);
	return "Please set attribute owoGetUrl!" if(!defined($urlString));

	my $cmd		=	$a[1];
	
	given($cmd){
		when("?")		{ return $usage; }

		when("stationByName"){
			$urlString = $urlString."?q=";
			my $count;
			my $element = @a;
			for ($count = 2; $count < $element; $count++) {
				$urlString = $urlString."%20".$a[$count];
			}
		}

		when("stationById"){
			$urlString = $urlString."?id=".$a[2];
		}

		when("stationByGeo"){
			$a[2] = AttrVal("global", "latitude", 0) unless(defined($a[2]));
			$a[3] = AttrVal("global", "longitude", 0) unless(defined($a[3]));
			$urlString = $urlString."?lat=$a[2]&lon=$a[3]";
		}

		default: { return $usage; }
	}

	UpdateReadings($hash, $urlString, "g_");

	return;

#	return $response;
}

sub OWO_Attr(@){
	my @a = @_;
	my $hash = $defs{$a[1]};
	my (undef, $name, $attrName, $attrValue) = @a;

	given($attrName){

		when("owoInterval"){
			if($attrValue ne ""){
				$attrValue = 600 if($attrValue < 600);
				$hash->{helper}{INTERVAL} = $attrValue;
			} else {
				$hash->{helper}{INTERVAL} = 1800;
			}
			$attr{$name}{$attrName} = $attrValue;
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "OWO_GetStatus", $hash, 0);
			break;
		}

		when("owoProxy"){
			if($attrValue ne ""){
				$ua->proxy(['http'], $attrValue);
			}
		}

		default {
			$attr{$name}{$attrName} = $attrValue;
		}
	}
	return "";
}

sub OWO_Notify($$) {
	my ($hash,$dev) = @_;

	if( grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}) ) {
		delete $modules{openweathermap}->{NotifyFn};

		foreach my $d (keys %defs) {
			next if($defs{$d}{TYPE} ne "openweathermap");
			OWO_GetStatus($hash);
		}
	}
}

sub OWO_GetStatus($;$){
	my ($hash, $local) = @_;
	my $name = $hash->{NAME};
	my $htmlDummy;
	$local = 0 unless(defined($local));

	$attr{$name}{"owoInterval"} = 600 if(AttrVal($name,"owoInterval",0) < 600);

	RemoveInternalTimer($hash);

##### start of send job (own weather data)
#
#	do we have anything to send from our own station?
#

	my ($user, $pass) = split(":", AttrVal($name, "owoUser",""));
	my $station		= AttrVal($name, "owoStation", undef);

	if(defined($user) && defined($station)){
		Log3($name, 3, "owo $name: started: SendData");

		my $lat			= AttrVal("global", "latitude", "");
		my $lon			= AttrVal("global", "longitude", "");
		my $alt			= AttrVal("global", "altitude", "");

		my $urlString = AttrVal($name, "owoSendUrl", "http://openweathermap.org/data/post");
		my ($p1, $p2) = split("//", $urlString);
		$urlString = $p1."//$user:$pass\@".$p2;

		my $dataString = "name=$station&lat=$lat&long=$lon&alt=$alt";

		my ($count, $paraName, $paraVal, $p, $s, $v, $o);
		for ($count = 0; $count < 20; $count++) {
			$paraName = "owoSrc".sprintf("%02d",$count);
			$paraVal = AttrVal($name, $paraName, undef);
			if(defined($paraVal)){
				($p, $s, $v, $o) = split(":", AttrVal($name, $paraName, ""));
				$o = 0 if(!defined($o));
				$v = ReadingsVal($s, $v, "?") + $o;
				$dataString = $dataString."&$p=$v";
				Log3($name, 4, "owo $name: reading: $paraName $p $s $v");
				readingsSingleUpdate($hash, "my_".$p, $v, 1);
			}
		}

		$dataString .= "&APPID=".AttrVal($name, "owoApiKey", "");

		my $sendString = $urlString."?".$dataString;
		if(AttrVal($name, "owoDebug",1) == 0){
			Log3($name, 4, "owo $name: sending: $dataString");
			$htmlDummy = $ua->post($sendString);
			Log3($name, 3, "owo $name: htmlResponse: ".$htmlDummy->status_line);
		} else {
			Log3($name, 3, "owo $name: debug:   $dataString");
		}

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "_httpResponse_my", $htmlDummy->status_line) if $htmlDummy;
		readingsBulkUpdate($hash, "my_response", $htmlDummy->decoded_content) if $htmlDummy;
		readingsBulkUpdate($hash, "state","active");
		if(AttrVal($name, "owoTimestamp", 0) == 1){
			readingsBulkUpdate($hash, "my_lastSent", time);
		} else {
			readingsBulkUpdate($hash, "my_lastSent", localtime(time));
		}
		readingsEndUpdate($hash, 1);
		if(defined($htmlDummy)){
			CommandDeleteReading(undef, "$name my_.*") if $htmlDummy->is_error;
		}
	}

##### end of send job

##### start of update job (set station)
#
#	Do we already have a stationId set?
#	If yes => update this station
#
	my $cId = ReadingsVal($name,"c_stationId", undef);
	if(defined($cId)){
		my $cName = ReadingsVal($name,"stationName", "");
		Log3($name, 4, "owo $name: retrievingStationData: Id: $cId Name: $cName");
		fhem("set $name stationById $cId");
	}

##### end of update job

	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "OWO_GetStatus", $hash, 0) unless($local == 1);
	return;
}

sub OWO_Define($$){
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $name = $hash->{NAME};

	$hash->{helper}{INTERVAL} = 1800;
	$hash->{helper}{AVAILABLE} = 1;

	$attr{$name}{"owoDebug"}	= 1;
	$attr{$name}{"owoUseXml"}	= 1;
	$attr{$name}{"owoInterval"}	= 1800;
	$attr{$name}{"owoGetUrl"}	= "http://api.openweathermap.org/data/2.5/weather";
	$attr{$name}{"owoSendUrl"}	= "http://openweathermap.org/data/post";

	if( $init_done ) {
		delete $modules{openweathermap}->{NotifyFn};
		OWO_GetStatus($hash);
	} else {
		readingsSingleUpdate($hash, "state", "defined",1);
	}

#	readingsSingleUpdate($hash, "state","defined",1);
#	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "OWO_GetStatus", $hash, 0);

	Log3($name, 4, "owo $name: created");

	return;
}

sub OWO_Undefine($$){
	my($hash, $name) = @_;
	RemoveInternalTimer($hash);
	return undef;
}

sub UpdateReadings($$$){
	my ($hash, $url, $prefix) = @_;
	my $name = $hash->{NAME};
	my ($jsonWeather, $response);

	my $xmlMode = AttrVal($name, "owoUseXml", "");
	$url .= "&mode=xml" if($xmlMode eq "1");
	$url .= "&APPID=".AttrVal($name, "owoApiKey", "");
	eval {$response = $ua->get("$url")};

#
#	error handling for not found stations (error 404 from server)
#
	if($response->decoded_content =~ m/error/i){
		CommandDeleteReading(undef, "$name $prefix.*");
		readingsSingleUpdate($hash, "_httpResponse_".substr($prefix,0,1), $response->decoded_content, 1);
		return;
	}

	if(defined($response)){
		if(AttrVal($name, "owoDebug", 1) == 1){
			Log3($name, 4, "owo $name: response:\n".$response->decoded_content);
		}
	} else {
		Log3($name, 4, "owo $name: error: no response from server");
		return;
	}

	CommandDeleteReading(undef, "$name $prefix.*");
	readingsSingleUpdate($hash, "_httpResponse_".substr($prefix,0,1), $response->status_line, 1);

	if($xmlMode eq "1" && $response->is_success){
		Log3($name, 4, "owo $name: decoding XML");
		my $xml			= new XML::Simple;
		$jsonWeather	= undef;
		$jsonWeather	= $xml->XMLin($response->decoded_content, KeyAttr => 'current' );

		if(defined($jsonWeather)){
			readingsBeginUpdate($hash);
			if(AttrVal($name, "owoRaw", 0) == 1){
				readingsBulkUpdate($hash, $prefix."rawData", $response->decoded_content);
			}
			readingsBulkUpdate($hash, "_dataSource",			"www.openweathermap.org");
			readingsBulkUpdate($hash, "_decodedWith",			"XML");
			readingsBulkUpdate($hash, $prefix."lastWx",			$jsonWeather->{lastupdate}{value});
			readingsBulkUpdate($hash, $prefix."sunrise",		$jsonWeather->{city}{sun}{rise});
			readingsBulkUpdate($hash, $prefix."sunset",			$jsonWeather->{city}{sun}{set});
			readingsBulkUpdate($hash, $prefix."stationId",		$jsonWeather->{city}{id});
			readingsBulkUpdate($hash, $prefix."stationName",	utf8ToLatin1($jsonWeather->{city}{name}));
			readingsBulkUpdate($hash, $prefix."stationCountry",	$jsonWeather->{city}{country});
			readingsBulkUpdate($hash, $prefix."stationLat",		sprintf("%.4f",$jsonWeather->{city}{coord}{lat}));
			readingsBulkUpdate($hash, $prefix."stationLon",		sprintf("%.4f",$jsonWeather->{city}{coord}{lon}));
			readingsBulkUpdate($hash, $prefix."temperature",	sprintf("%.1f",$jsonWeather->{temperature}{value}-273.15));
			readingsBulkUpdate($hash, $prefix."tempMin",		sprintf("%.1f",$jsonWeather->{temperature}{min}-273.15));
			readingsBulkUpdate($hash, $prefix."tempMax",		sprintf("%.1f",$jsonWeather->{temperature}{max}-273.15));
			readingsBulkUpdate($hash, $prefix."humidity",		$jsonWeather->{humidity}{value});
			readingsBulkUpdate($hash, $prefix."pressure",		$jsonWeather->{pressure}{value});
#			readingsBulkUpdate($hash, $prefix."pressureRel",	$jsonWeather->{main}{sea_level});
			readingsBulkUpdate($hash, $prefix."windSpeed",		$jsonWeather->{wind}{speed}{value});
			readingsBulkUpdate($hash, $prefix."windDir",		$jsonWeather->{wind}{direction}{value});
			readingsBulkUpdate($hash, $prefix."clouds",			$jsonWeather->{clouds}{value});
			readingsBulkUpdate($hash, $prefix."rain3h",			$jsonWeather->{rain}{"3h"});
			readingsBulkUpdate($hash, $prefix."snow3h",			$jsonWeather->{snow}{"3h"});
			readingsBulkUpdate($hash, "state", "active");
			readingsEndUpdate($hash, 1);
		} else { 
			Log3($name, 2, "owo $name error: update not possible!"); 
		}
	}
	
	if($xmlMode ne "1" && $response->is_success){
		Log3($name, 4, "owo $name: decoding JSON");
		my $json = JSON->new->allow_nonref;
		eval {$jsonWeather = $json->decode($response->decoded_content)}; warn $@ if $@;

		if(defined($jsonWeather)){
			readingsBeginUpdate($hash);
			if(AttrVal($name, "owoRaw", 0) == 1){
				readingsBulkUpdate($hash, $prefix."rawData",  $response->decoded_content);
			}
			if(AttrVal($name, "owoTimestamp", 0) == 1){
				readingsBulkUpdate($hash, $prefix."lastWx",   $jsonWeather->{dt});
				readingsBulkUpdate($hash, $prefix."sunrise",  $jsonWeather->{sys}{sunrise});
				readingsBulkUpdate($hash, $prefix."sunset",   $jsonWeather->{sys}{sunset});
			} else {
				readingsBulkUpdate($hash, $prefix."lastWx",   localtime($jsonWeather->{dt}));
				readingsBulkUpdate($hash, $prefix."sunrise",  localtime($jsonWeather->{sys}{sunrise}));
				readingsBulkUpdate($hash, $prefix."sunset",   localtime($jsonWeather->{sys}{sunset}));
			}
			readingsBulkUpdate($hash, "_dataSource",			"www.openweathermap.org");
			readingsBulkUpdate($hash, "_decodedWith",			"JSON");
			readingsBulkUpdate($hash, $prefix."stationId",    $jsonWeather->{id});
			readingsBulkUpdate($hash, $prefix."lastRxCode",   $jsonWeather->{cod});
			readingsBulkUpdate($hash, $prefix."stationName",  utf8ToLatin1($jsonWeather->{name}));
			readingsBulkUpdate($hash, $prefix."humidity",     $jsonWeather->{main}{humidity});
			readingsBulkUpdate($hash, $prefix."pressureAbs",  $jsonWeather->{main}{pressure});
			readingsBulkUpdate($hash, $prefix."pressureRel",  $jsonWeather->{main}{sea_level});
			readingsBulkUpdate($hash, $prefix."windSpeed",    $jsonWeather->{wind}{speed});
			readingsBulkUpdate($hash, $prefix."windDir",      $jsonWeather->{wind}{deg});
			readingsBulkUpdate($hash, $prefix."clouds",       $jsonWeather->{clouds}{all});
			readingsBulkUpdate($hash, $prefix."rain3h",       $jsonWeather->{rain}{"3h"});
			readingsBulkUpdate($hash, $prefix."snow3h",       $jsonWeather->{snow}{"3h"});
			readingsBulkUpdate($hash, $prefix."stationLat",   sprintf("%.4f",$jsonWeather->{coord}{lat}));
			readingsBulkUpdate($hash, $prefix."stationLon",   sprintf("%.4f",$jsonWeather->{coord}{lon}));
			readingsBulkUpdate($hash, $prefix."temperature",  sprintf("%.1f",$jsonWeather->{main}{temp}-273.15));
			readingsBulkUpdate($hash, $prefix."tempMin",      sprintf("%.1f",$jsonWeather->{main}{temp_min}-273.15));
			readingsBulkUpdate($hash, $prefix."tempMax",      sprintf("%.1f",$jsonWeather->{main}{temp_max}-273.15));
			readingsBulkUpdate($hash, "state", "active");
			readingsEndUpdate($hash, 1);
		} else { 
			Log3($name, 2, "owo $name error: update not possible!"); 
		}
	}
	return;
}

sub OWO_abs2rel($$$){
# Messwerte
my $Pa   = $_[0];
my $Temp = $_[1];
my $Alti = $_[2];

# Konstanten
my $g0 = 9.80665;
my $R  = 287.05;
my $T  = 273.15;
my $Ch = 0.12;
my $a  = 0.065;
my $E  = 0;

if($Temp < 9.1)	{ $E = 5.6402*(-0.0916 + exp(0.06 * $Temp)); }
	else		{ $E = 18.2194*(1.0463 - exp(-0.0666 * $Temp)); }

my $xp = $Alti * $g0 / ($R*($T+$Temp + $Ch*$E + $a*$Alti/2));
my $Pr = $Pa*exp($xp);

return int($Pr);
}

sub OWO_isday($$){
	my $name = $_[0];
	my $src  = $_[1];
	my $response;

	if(AttrVal($name, "owoTimestamp",0)){
		$response = (time > ReadingsVal($name, $src."_sunrise", 0) && time < ReadingsVal($name, $src."_sunset", 0) ? "1" : "0");
	} else {
		$response = "Attribute owoTimestamp not set to 1!";
	}
	return $response;
}


# OpenWeatherMap API parameters
# -----------------------------
# 01 wind_dir - wind direction, grad
# 02 wind_speed - wind speed, mps
# 03 temp - temperature, grad C
# 04 humidity - relative humidity, %
# 05 pressure - atmosphere pressure
# 06 wind_gust - speed of wind gust, mps
# 07 rain_1h - rain in recent hour, mm
# 08 rain_24h - rain in recent 24 hours, mm
# 09 rain_today - rain today, mm
# 10 snow - snow in recent 24 hours, mm
# 11 lum - illumination, W/M²
# 12 radiation - radiation
# 13 dewpoint - dewpoint
# 14 uv - UV index
# name - station name
# lat - latitude
# long - longitude
# alt - altitude, m

1;

=pod
not to be translated
=begin html

<a name="openweathermap"></a>
<h3>openweathermap</h3>
<ul>

	<b>Prerequisits</b>
	<ul>
		<br/>
		<li>Module uses following additional Perl modules:<br/><br/>
		<code>XML::Simple, JSON</code><br/><br/>
		If not already installed in your environment, please install them using appropriate commands from your environment.<br/>
		Use of JSON is optional. You can activate it by setting attribute owoUseXml to 0</li><br/>
		<li>please check global attributes latitude, longitude and altitude are set correctly</li>
		<li>you can use all task alone, in any combination or all together</li>
	</ul>
	<br/><br/>

	<a name="openweathermapdefine"></a>
	<b>Define</b>
	<ul>
		<br/>
		<code>define &lt;name&gt; openweathermap</code>
		<br/><br/>
		This module provides connection to openweathermap-network www.openweathermap.org (owo)<br/>
		You can use this module to do three different tasks:<br/>
		<br/>
		<ul>
			<li>1.	send weather data from your own weather station to owo network.</li>
			<li>2.	set any weather data in owo network as datasource for your fhem installation. Data from this station will be updated periodically.</li>
			<li>3.	retrieve weather data from any weather station in owo network once. (same as 2. but without update)</li>
		</ul>
		<br/>
		Example:<br/>
		<br/>
		<ul><code>define owo openweathermap</code></ul>
	</ul>
	<br/><br/>

	<b>Configuration of your owo tasks</b><br/><br/>
	<ul>
		<a name="owoconfiguration1"></a>
		<li>1. providing your own weather data to owo network</li>
		<br/>
		<ul><code>
			define owo openweathermap<br/>
			attr owo owoUser myuser:mypassword<br/>
			attr owo owoStation myStationName<br/>
			attr owo owoInterval 600<br/>
			attr owo owoSrc00 temp:sensorname:temperature<br/>
		</code></ul><br/>

		<a name="owoconfiguration2"></a>
		<li>2. set a weather station from owo network as data source for your fhem installation</li>
		<br/>
		<ul><code>
			set owo stationByName Leimen
			<br/><br/>
			set owo stationById 2879241
			<br/><br/>
			set owo stationByGeo 49.3511 8.6894
		</code></ul>
		<br/><br/>
		<ul>
			<li>All commands will retrieve weather data for Leimen (near Heidelberg,DE)</li>
			<li>Readings will be updated periodically, based on value of owoInterval.</li>
			<li>If lat and lon value in stationByGeo are omitted, the corresponding values from global attributes are used.</li>
			<li>All readings will use prefix "c_"</li>
		</ul>
		<br/>

		<a name="owoconfiguration3"></a>
		<li>3. get weather data from a selected weather station once (e.g. to do own presentations)</li>
		<br/>
		<ul><code>
			get owo stationByName Leimen
			<br/><br/>
			get owo stationById 2879241
			<br/><br/>
			get owo stationByGeo 49.3511 8.6894
		</code></ul>
		<br/><br/>
		<ul>
			<li>All commands will retrieve weather data for Leimen (near Heidelberg,DE) once.</li>
			<li>Readings will not be updated periodically.</li>
			<li>If lat and lon value in stationByGeo are omitted, the corresponding values from global attributes are used.</li>
			<li>All readings will use prefix "g_"</li>
		</ul>
		<br/>

	</ul>
	<br/><br/>

	<a name="openweathermapset"></a>
	<b>Set-Commands</b><br/>
	<ul>
		<br/>
		<code>set &lt;name&gt; clear</code><br/>
		<br/>
		<ul>Delete all readings for cleanup</ul>
		<br/><br/>
		<code>set &lt;name&gt; send</code><br/>
		<br/>
		<ul>start an update cycle manually:
			<ul>
				<li>send own data</li>
				<li>update c_* readings from "set" station (if defined)</li>
				<br/>
				<li>does not affect or re-trigger running timer cycles!</li>
				<li>main purpose: for debugging and testing</li>
			</ul>
		</ul>
		<br/><br/>
		<code>set &lt;name&gt; &lt;stationById stationId&gt;|&lt;stationByName stationName&gt;|&lt;stationByGeo> [lat lon]&gt;</code>
		<br/><br/>
		<ul>see description above: <a href="#owoconfiguration2">Configuration task 2</a></ul>
		<br/><br/>
	</ul>
	<br/><br/>
	<a name="openweathermapget"></a>
	<b>Get-Commands</b><br/>
	<ul>
		<br/>
		<code>get &lt;name&gt; &lt;stationById stationId&gt;|&lt;stationByName stationName&gt;|&lt;stationByGeo> [lat lon]&gt;</code>
		<br/><br/>
		<ul>see description above: <a href="#owoconfiguration3">Configuration task 3</a></ul>
		<br/>
		Used exactly as the "set" command, but with two differences:<br/><br/>
		<ul>
			<li>all generated readings use prefix "g_" instead of "c_"</li>
			<li>readings will not be updated automatically</li>
		</ul>
	</ul>
	<br/><br/>
	<a name="openweathermapattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<br/>
		<li><b>owoApiKey</b></li>
		&lt;yourOpenweathermapApiKey&gt; - find it in your owo account! If set, it will be used in all owo requests.<br/>
		<li><b>owoDebug</b></li>
		&lt;0|1&gt; this attribute <b>must be defined and set to 0</b> to start sending own weather data to owo network. Otherwise you can find all data as debug informations in logfile.<br/>
		<li><b>owoGetUrl</b></li>
		&lt;owoApiUrl&gt; - current URL to owo api. If this url changes, you can correct it here unless updated version of 98_openweather becomes available.<br/>
		<li><b>owoInterval</b></li>
		&lt;intervalSeconds&gt; - define the interval used for sending own weather data and for updating SET station. Default = 1800sec. If deleted, default will be used.<br/>
		<b>Please do not set interval below 600 seconds! This regulation is defined by openweathermap.org.</b><br/>
		Values below 600 will be corrected to 600.<br/>
		<li><b>owoProxy</b></li>
		&lt;proxyAddress&gt; - define a proxy server address, please give full url and port, e.g. http://192.168.111.222:8080<br/>
		<li><b>owoStation</b></li>
		&lt;yourStationName&gt; - define the station name to be used in "my stats" in owo account<br/>
		<li><b>owoUser</b></li>
		&lt;user:password&gt; - define your username and password for owo access here<br/>
		<li><b>owoRaw</b></li>
		&lt;0|1&gt; - defines wether JSON date from owo will be shown in an additional reading (e.g. to use it for own presentations)<br/>
		<li><b>owoSendUrl</b></li>
		Current URL to post your own data. If this url changes, you can correct it here unless updated version of 98_openweather becomes available.<br/>
		<li><b>owoTimestamp</b></li>
		&lt;0|1&gt; - defines whether date/time readings show timestamps or localtime-formatted informations<br/>
		<li><b>owoSrc00 ... owoSrc19</b></li>
		Each of this attributes contains information about weather data to be sent in format <code>owoParam:sensorName:readingName:offset</code><br/>
		Example: <code>attr owo owoSrc00 temp:outside:temperature</code> will define an attribut owoSrc00, and <br/>
		reading "temperature" from device "outside" will be sent to owo network als paramater "temp" (which indicates current temperature)<br/>
		Parameter "offset" will be added to the read value (e.g. necessary to send dewpoint - use offset 273.15 to send correct value)
		<li><b>owoUseXml</b></li>
		&lt;0|1&gt; - defines wether data must be decoded from XML, e.g. JSON not available on Fritzbox<br/>
	</ul>
	<br/><br/>
	<b>Generated Readings/Events:</b><br/><br/>
	<ul>
		<li><b>state</b> - current device state (defined|active)</li>
		<li><b>c_&lt;readingName&gt;</b> - weather data from SET weather station. Readings will be updated periodically</li>
		<li><b>g_&lt;readingName&gt;</b> - weather data from GET command. Readings will NOT be updated periodically</li>
		<li><b>my_lastSent</b> - time of last upload to owo network</li>
		<li><b>my_&lt;readingName&gt;</b> - all readings from own weather station. These readings will be sent to owo network.</li>
	</ul>
	<br/><br/>
	<b>Author's notes</b><br/><br/>
	<ul>
		<li>further informations about sending your own weather data to owo: <a href="http://openweathermap.org/stations">Link</a></li>
		<li>further informations about owo location search: <a href="http://openweathermap.org/API">Link</a></li>
		<li>further informations about owo weather data: <a href="http://bugs.openweathermap.org/projects/api/wiki/Weather_Data">Link</a></li>
	</ul>
</ul>

=end html
=begin html_DE

<a name="openweathermap"></a>
<h3>openweathermap</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#openweathermap'>openweathermap</a><br/>
</ul>
=end html_DE
=cut

# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use feature qw/say switch/;

require XML::Simple;
require LWP::UserAgent;

use Data::Dumper;

sub geodata_Initialize($){
	my ($hash) = @_;
	$hash->{DefFn}			=	"geodata_Define";
	$hash->{UndefFn}		=	"geodata_Undefine";
	$hash->{AttrFn}			=	"geodata_Attr";
	$hash->{ShutdownFn}	=	"geodata_Shutdown";
	$hash->{AttrList}		=	"geo_wuApiKey geo_googleApiKey ".
												"geo_language:de,en geo_owoGetUrl ".
												$readingFnAttributes;
}

sub geodata_Define($$){

	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return 'usage: define <name> geodata <latitude> <longitude> <altitude>' if @a < 4;

	Log3($name, 4, 'Setting global attributes lat/lon/alt');
	$attr{global}{latitude}	= $a[2];
	$attr{global}{longitude}	= $a[3];
#	$attr{global}{altitude}	= $a[4];

	Log3($name, 4, 'Updating readings lat/lon/alt/state');
	readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'latitude',  $a[2]);
		readingsBulkUpdate($hash, 'longitude', $a[3]);
#		readingsBulkUpdate($hash, 'altitude',  $a[4]);
		readingsBulkUpdate($hash, 'state', 'defined');
	readingsEndUpdate($hash,1);

	geodata_collectData($hash);

	return;
}

sub geodata_Undefine($$){
	my($hash, $name) = @_;
	RemoveInternalTimer($hash);
	return;
}

sub geodata_Attr($){
	my @a = @_;
	my $hash = $defs{$a[1]};
	my (undef, $name, $attrName, $attrValue) = @a;

	given($attrName){

		when("geo_googleApiKey"){
			$attr{$name}{$attrName} = $attrValue;
			geodata_collectData($hash);
			break;
		}

		when("geo_wuApiKey"){
			$attr{$name}{$attrName} = $attrValue;
			geodata_collectData($hash);
			break;
		}

		default {
			$attr{$name}{$attrName} = $attrValue;
		}
	}
	return "";
	return;
}

sub geodata_Shutdown($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 ($name,4,"geodata $name: shutdown requested");
	return undef;
}

sub geodata_collectData($){
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my	$ua = LWP::UserAgent->new;
	$ua->timeout(10);				# test
	$ua->env_proxy;
	
	_geodata_owoInfo($hash, $ua);

	my $apiKey;
	$apiKey = AttrVal($name, 'geo_wuApiKey', undef);
	_wu_geolookup($hash, $ua, $apiKey) if(defined($apiKey));
	
	$apiKey = AttrVal($name, 'geo_googleApiKey', undef);
	_geodata_googledata($hash, $ua, $apiKey) if(defined($apiKey));

	InternalTimer(gettimeofday()+3600, "geodata_collectData", $hash, 0);

	return;
}

sub _wu_geolookup($$$) {
	my ($hash, $ua, $wuapikey) = @_;
	my $name		= $hash->{NAME};


	my $lat = ReadingsVal($name, 'latitude', '');
	my $lon = ReadingsVal($name, 'longitude', '');
	my $geolookupUrl = "http://api.wunderground.com/api/$wuapikey/geolookup/q/$lat,$lon.xml";
	my $xml			= new XML::Simple;
	my ($response, $htmldata, $query, $dummy);

#----------------------------------------------------------
# retrieving: geolookup data
#
	eval {$response = $ua->get("$geolookupUrl")};
## ToDo: errorhandling

	$htmldata = $xml->XMLin($response->decoded_content, KeyAttr => '' );
	$dummy = $htmldata->{location}{country};
	$query = "/lang:$dummy".$htmldata->{location}{l};

	$hash->{HELPER}{WUQUERY} = $query;

	readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'wuTerms',	$htmldata->{termsofService});
		readingsBulkUpdate($hash, 'wuVersion',				$htmldata->{version});
		readingsBulkUpdate($hash, 'nextAirportCity', $htmldata->{location}{nearby_weather_stations}{airport}{station}[0]{city});
		readingsBulkUpdate($hash, 'nextAirportICAO', $htmldata->{location}{nearby_weather_stations}{airport}{station}[0]{icao});

#----------------------------------------------------------
# retrieving astronomy data
#
		$geolookupUrl = "http://api.wunderground.com/api/$wuapikey/astronomy/$query.xml";
		eval {$response = $ua->get("$geolookupUrl")};
## ToDo: errorhandling

		$htmldata = $xml->XMLin($response->decoded_content, KeyAttr => '' );

		$dummy = $htmldata->{sun_phase}{sunrise}{hour}.':'.$htmldata->{sun_phase}{sunrise}{minute};
		readingsBulkUpdate($hash, 'sunrise', $dummy);
		$dummy = $htmldata->{sun_phase}{sunset}{hour}.':'.$htmldata->{sun_phase}{sunset}{minute};
		readingsBulkUpdate($hash, 'sunset', $dummy);
		readingsBulkUpdate($hash, 'moon_phase', $htmldata->{moon_phase}{percentIlluminated});
		readingsBulkUpdate($hash, 'moon_age_days', $htmldata->{moon_phase}{ageOfMoon});

#----------------------------------------------------------
# retrieving conditions data
#
		$geolookupUrl = "http://api.wunderground.com/api/$wuapikey/conditions/$query.xml";
		eval {$response = $ua->get("$geolookupUrl")};
## ToDo: errorhandling

		$htmldata = $xml->XMLin($response->decoded_content, KeyAttr => '' );

		$dummy = sprintf("%.0f", $htmldata->{current_observation}{display_location}{elevation});
		readingsBulkUpdate($hash, 'altitude', $dummy);
		readingsBulkUpdate($hash, 'city', $htmldata->{current_observation}{display_location}{city});
		readingsBulkUpdate($hash, 'country', $htmldata->{current_observation}{display_location}{country});
		readingsBulkUpdate($hash, 'country_iso', $htmldata->{current_observation}{display_location}{country_iso3166});
		readingsBulkUpdate($hash, 'country_name', $htmldata->{current_observation}{display_location}{state_name});
		readingsBulkUpdate($hash, 'observation', $htmldata->{current_observation}{observation_epoch});
		readingsBulkUpdate($hash, 'tz_long', $htmldata->{current_observation}{local_tz_long});
		readingsBulkUpdate($hash, 'tz_offset', $htmldata->{current_observation}{local_tz_offset});
		readingsBulkUpdate($hash, 'tz_short', $htmldata->{current_observation}{local_tz_short});
		$dummy = $htmldata->{current_observation}{display_location}{zip};
		readingsBulkUpdate($hash, 'zip',							$dummy) if $dummy ne '00000';


#Debug(Dumper($htmldata));

		readingsBulkUpdate($hash, 'state',						'active');
	readingsEndUpdate($hash, 1);
	return;
}

sub _geodata_googledata($$$) {

	my ($hash, $ua, $apiKey) = @_;
	my $name = $hash->{NAME};

	if(!defined($apiKey)) {
		Log3($name, 2, 'Api key for elevation not found!');
		return;
	}

	my $urlString = AttrVal($name, 'geo_elevationUrl','https://maps.googleapis.com/maps/api/elevation/xml');
	my $lat = ReadingsVal($name, 'latitude', '');
	my $lon = ReadingsVal($name, 'longitude', '');
	my $xml			= new XML::Simple;
	my ($response, $owodata, $dummy);

	my $urlString2 = "?sensor=false&locations=$lat,$lon&key=$apiKey";
	$urlString .= $urlString2;
	eval {$response = $ua->get("$urlString")};
	
	readingsBeginUpdate($hash);
		$owodata	= $xml->XMLin($response->decoded_content, KeyAttr => 'result' );
		$dummy = $owodata->{result}{elevation};
		$dummy = sprintf("%.0f", $dummy);
		readingsBulkUpdate($hash, 'altitude', $dummy);
		$attr{global}{altitude} = $dummy;

		$urlString   = AttrVal($name, 'geo_timezoneUrl', 'https://maps.googleapis.com/maps/api/timezone/xml');
		$urlString2  = "?sensor=false&location=$lat,$lon&key=$apiKey&timestamp=".time;
		$urlString2 .= "&language=".AttrVal($name, 'geo_language', 'en');
		$urlString  .= $urlString2;
		eval {$response = $ua->get("$urlString")};

		$owodata	= $xml->XMLin($response->decoded_content, KeyAttr => '' );
		readingsBulkUpdate($hash, 'timeZoneId',   $owodata->{time_zone_id});
		readingsBulkUpdate($hash, 'dstOffset',    $owodata->{dst_offset});
		readingsBulkUpdate($hash, 'timeZoneName', latin1ToUtf8($owodata->{time_zone_name}));
		readingsBulkUpdate($hash, 'rawOffset',    $owodata->{raw_offset});
	readingsEndUpdate($hash, 1);
	return;
}

sub _geodata_owoInfo($$){
	my ($hash,$ua) = @_;
	my $name = $hash->{NAME};
	my $urlString = AttrVal($name, "geo_owoGetUrl", "http://api.openweathermap.org/data/2.5/weather");
	my $lat = ReadingsVal($name, 'latitude', '');
	my $lon = ReadingsVal($name, 'longitude', '');
	my $xml			= new XML::Simple;
	my ($response, $owodata, $dummy);

	$urlString .= "?lat=$lat&lon=$lon&mode=xml";
	eval {$response = $ua->get("$urlString")};

#
#	error handling for not found stations (error 404 from server)
#
#	if($response->decoded_content =~ m/error/i){ do errorhandling}

	$owodata	= $xml->XMLin($response->decoded_content, KeyAttr => 'current' );

	if(defined($owodata)){
		(undef, $dummy) = split(/T/, $owodata->{city}{sun}{rise});
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "sunriseToday", $dummy); #		$owodata->{city}{sun}{rise});
		(undef, $dummy) = split(/T/, $owodata->{city}{sun}{set});
		readingsBulkUpdate($hash, "sunsetToday", $dummy); #$owodata->{city}{sun}{set});
		readingsBulkUpdate($hash, "country",	$owodata->{city}{country});
		readingsBulkUpdate($hash, "state", "active");
		readingsEndUpdate($hash, 1);
	}

	return;
}

1;

#	$attr{$name}{geo_owoGetUrl}			= "http://api.openweathermap.org/data/2.5/weather";

=pod
=begin html

<a name="geodata"></a>
<h3>geodata</h3>
<ul>

  Collect some location based data from various internet sources.<br/>
  Data will be updated once an hour.<br/>
  <br/><ul>
  <li><b>openweathermap</b> will always be used.</li>
  <li><b>wunderground api</b> will be used, if wunderground api key is provided by attribute.</li>
  <li><b>google api</b> will be used, if google api key is provided by attribute.<br/>
      Currently google's elevation api and timezone api are used, so check access to those apis for your api key.</li>
  </ul>
  <br/>

  <a name="geodatadefine"></a>
  <b>Define</b><br/>
  <br/>
  <ul><code>define &lt;location&gt; latitude longitude</code><br/></ul>
  <br/>

  <a name="geodataset"></a>
  <b>Set</b>
  <ul>n/a</ul><br/>
  <br/>

  <a name="geodataget"></a>
  <b>Get</b>
  <ul>n/a</ul><br/>
  <br/>

  <a name="geodataattr"></a>
  <b>Attributes</b><br/>
  <br/>
  <ul>
  <li><b>geo_owoGetUrl</b> - used to correct owo api url manually, normally not needed.</li>
  <li><b>geo_wuApiKey</b> - enter your wunderground api key to access wunderground data.</li>
  <li><b>geo_googleApiKey</b> - enter your google api key to access google api.</li>
  <li><b>geo_language:de,en</b> - select language to be used if supported by api.</li>
  </ul><br/>
  <br/>


</ul>

=end html

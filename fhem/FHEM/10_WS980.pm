########################################################################################
#
# WS980.pm
#
# FHEM module for WS980-Wifi Weather Station
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
use IO::Socket::INET;
use POSIX qw(strftime);

my $version = "1.1.1";

#------------------------------------------------------------------------------------------------------
# global constants
#------------------------------------------------------------------------------------------------------
use constant REQUESTS => {
	"firmware" => { # \xff\xff\x50\x03\x53
		"type"  => "\x50",
		"value" => {
			"name" => "firmware",
			"width" => "auto",
		}
	},
	"current" => { # \xff\xff\x0b\x00\x06\x04\x04\x19
		"type"    => "\x0b",
		"subtype" => "\x04",
	},
	"historyMax" => { # \xff\xff\x0b\x00\x06\x05\x05\x1b,
		"type"    => "\x0b",
		"subtype" => "\x05",
		"postfix" => "_historyMax",
	},
	"historyMin" => { # \xff\xff\x0b\x00\x06\x06\x06\x1d
		"type"    => "\x0b",
		"subtype" => "\x06",
		"postfix" => "_historyMin",
	},
	"todayMax" => { # \xff\xff\x0b\x00\x06\x07\x07\x1f
		"type"    => "\x0b",
		"subtype" => "\x07",
		"postfix" => "_todayMax",
	},
	"todayMin" => { #\xff\xff\x0b\x00\x06\x08\x08\x21
		"type"    => "\x0b",
		"subtype" => "\x08",
		"postfix" => "_todayMin",
	},
};

use constant HAS_TIME => 0x40;
use constant HAS_DATE => 0x80;
use constant VALUES => {
		0x01 => {"name" => "temperatureInside",  "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "°C"    }, # °C  ## x / 10.0 - 40.0
		0x02 => {"name" => "temperature",        "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "°C"    }, # °C  ## x / 10.0 - 40.0
		0x03 => {"name" => "dewPoint",           "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "°C"    }, # °C  ## x / 10.0 - 40.0
		0x04 => {"name" => "windChill",          "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "°C"    }, # °C  ## x / 10.0 - 40.0
		0x05 => {"name" => "heatIndex",          "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "°C"    }, # °C  ## x / 10.0 - 40.0
		0x06 => {"name" => "humidityInside",     "bytes" => 1, "factor" =>  1, "format" => "%d"  , "unit" => "%"     }, # %
		0x07 => {"name" => "humidity",           "bytes" => 1, "factor" =>  1, "format" => "%d"  , "unit" => "%"     }, # %
		0x08 => {"name" => "pressureAbs",        "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "hPa"   }, # hPa
		0x09 => {"name" => "pressureRel",        "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "hPa"   }, # hPa
		0x0A => {"name" => "windDirection",      "bytes" => 2, "factor" =>  1, "format" => "%d"  , "unit" => "deg"   }, # °
		0x0B => {"name" => "wind",               "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "m/s"   }, # m/s
		0x0C => {"name" => "windGusts",          "bytes" => 2, "factor" => 10, "format" => "%.1f", "unit" => "m/s"   }, # m/s
		0x0D => {"name" => "rainEvent",          "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, # mm
		0x0E => {"name" => "rainRate",           "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, # mm
		0x0F => {"name" => "rainPerHour",        "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, #
		0x10 => {"name" => "rainPerDay",         "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, # mm
		0x11 => {"name" => "rainPerWeek",        "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, # mm
		0x12 => {"name" => "rainPerMonth",       "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, # mm
		0x13 => {"name" => "rainPerYear",        "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, # mm
		0x14 => {"name" => "rainTotal",          "bytes" => 4, "factor" => 10, "format" => "%.1f", "unit" => "mm"    }, # mm
		0x15 => {"name" => "brightness",         "bytes" => 4, "factor" => 10, "format" => "%d"  , "unit" => "lux"   }, # lux
		0x16 => {"name" => "uv",                 "bytes" => 2, "factor" =>  1, "format" => "%d"  , "unit" => "uW/m^2"}, # uW/m^2
		0x17 => {"name" => "uvIndex",            "bytes" => 1, "factor" =>  1, "format" => "%d"  , "unit" => "uvi"   }, # 0-15 index ??
};

use constant UNIT_CONVERSIONS => {
	"°C" => {
		"attr" => "unit_temperature", # °C °F
		"fnc"  => {
			"°C" => sub { my ($c) = @_; return $c },
			"°F" => sub { my ($c) = @_; return 9/5 * $c + 32 },
		},
	},
	"hPa" => {
		"attr" => "unit_pressure",    # hPa inHg mmHg
		"fnc"  => {
			"hPa"  => sub { my ($c) = @_; return $c },
			"inHg" => sub { my ($c) = @_; return $c * 0.75006375541921 / 10 / 2.54},
			"mmHg" => sub { my ($c) = @_; return $c * 0.75006375541921},
		},
	},
	"m/s" => {
		"attr" => "unit_wind",        # m/s km/h knot mph bft
		"fnc"  => {
			"m/s"  => sub { my ($c) = @_; return $c },
			"km/h" => sub { my ($c) = @_; return $c * 3.6 },
			"knot" => sub { my ($c) = @_; return $c * 1.943844 },
			"mph"  => sub { my ($c) = @_; return $c * 2.236936 },
			"bft"  => sub { my ($c) = @_; return ($c / 0.836) ** (2/3) },
		},
	},
	"mm"     => {
		"attr" => "unit_rain",        # mm in
		"fnc"  => {
			"mm" => sub { my ($c) = @_; return $c },
			"in" => sub { my ($c) = @_; return $c / 10 / 2.54 },
		},
	},
	"lux"    => {
		"attr" => "unit_light",       # lux fc w/m^2
		"fnc"  => {
			"lux"   => sub { my ($c) = @_; return $c },
			"fc"    => sub { my ($c) = @_; return $c * 0.09290304000008},
			"w/m^2" => sub { my ($c) = @_; return $c * 0.001464128843338},
		},
	},
};


#------------------------------------------------------------------------------------------------------
# Initialize
#------------------------------------------------------------------------------------------------------
sub WS980_Initialize($)
{
	my ($hash) = @_;

	Log3 undef, 5, "WS980 - WS980_Initialize() called";

	$hash->{DefFn}     = "WS980_DefFn";
	$hash->{UndefFn}   = "WS980_UndefFn";
	$hash->{AttrFn}    = "WS980_AttrFn";
	$hash->{SetFn}     = "WS980_SetFn";
	#$hash->{GetFn}     = "WS980_GetFn";

	$hash->{ReadFn}    = "WS980_ReadFn";
	$hash->{WriteFn}   = "WS980_WriteFn";

	$hash->{AttrList}  = "altitude ".
	                     "events:textField-long ".
	                     "connection:Keep-Alive,Close ".
	                     "requests:multiple-strict,".join(",", sort keys %{REQUESTS()})." ".
	                     "showRawBuffer:1 ".
	                     "silentReconnect:1 ".
	                     "disable:1 ".
	                     WS980_extractAttrsFromUnits() .
	                     $readingFnAttributes;

	foreach my $d (sort keys %{$modules{WS980}{defptr}}) {
		my $hash = $modules{WS980}{defptr}{$d};
		# update version in devices
		$hash->{VERSION} = $version;
		# initialize PORT if not done yet - PORT was introduced in 0.12.0
		if (!defined($hash->{PORT})) {
			$hash->{PORT} = 45000;
		}
		$hash->{helper}{requestInProgress} = 0;
	}
}


#------------------------------------------------------------------------------------------------------
# Define
#------------------------------------------------------------------------------------------------------
sub WS980_DefFn($$)
{
	my ( $hash, $def ) = @_;

	my @a = split( "[ \t]+", $def );
	splice( @a, 1, 1 );

	# check syntax
	if(int(@a) < 1) {
		return "Wrong syntax: use define <name> WS980 [IP] [INTERVAL]";
	}

	my ($name, $ip, $interval) = @a;
	Log3 $name, 5, "WS980 ($name) - WS980_DefFn() called";

	my $port = 45000;
	# try to auto-discover the IP
	if (!defined($ip)) {
		($ip, $port) = WS980_autodiscoverIP($hash);
	}
	return "Autodiscovery failed, please set IP by hand" unless (defined($ip));

	$hash->{IP}       = $ip;
	$hash->{PORT}     = $port;
	$hash->{VERSION}  = $version;
	$hash->{INTERVAL} = $interval ? $interval : 30;
	$hash->{helper}{requestInProgress} = 0;

	$modules{WS980}{defptr}{$hash->{IP}} = $hash;

	my $eventsCfg = AttrVal($name, "events", "");
	if ($eventsCfg ne "") {
		WS980_parseEventsAttr($hash, $eventsCfg)
	}

	if ($init_done) {
		InternalTimer( gettimeofday()+0, "WS980_updateValues", $hash);
	} else {
		InternalTimer( gettimeofday()+10, "WS980_updateValues", $hash);
	}

	return undef;
}


#------------------------------------------------------------------------------------------------------
# Undefine
#------------------------------------------------------------------------------------------------------
sub WS980_UndefFn($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "WS980 ($name) - WS980_UndefFn() called";

	delete $modules{WS980}{defptr}{$hash->{IP}};

	RemoveInternalTimer($hash);
	WS980_Close($hash);

	return undef;
}


#------------------------------------------------------------------------------------------------------
# AttrFn
#------------------------------------------------------------------------------------------------------
sub WS980_AttrFn(@)
{
	my ($cmd, $name, $attrName, $attrVal) = @_;
	my $hash = $defs{$name};

	##################
	#### altitude ####

	if ($attrName eq "altitude") {
		if ($cmd eq "set") {
			my $isNumeric = ($attrVal eq $attrVal+0);
			if ($isNumeric) {
				WS980_updateRelPressure($hash);
				return undef;
			} else {
				return "'altitude' must be a numeric value";
			}
		}
	}

	####################
	#### connection ####

	if ($attrName eq "connection") {
		if ($cmd eq "set") {
			if ($attrVal eq "Keep-Alive") {
				return undef;
			}
			elsif ($attrVal eq "Close") {
				WS980_Close($hash);
				return undef;
			}
			else {
				return "'connection' must be either Keep-Alive or Close";
			}
		}
	}

	################
	#### events ####

	if ($attrName eq "events") {
		if ($cmd eq "set") {
			WS980_parseEventsAttr($hash, $attrVal);
		} elsif ($cmd eq "del") {
			WS980_parseEventsAttr($hash, undef);
		}
	}

	##################
	#### requests ####

	if ($attrName eq "requests") {
		if ($cmd eq "set") {
			my @parts = split(/[, ]/, $attrVal);
			foreach my $part (@parts) {
				if (!defined REQUESTS->{$part}) {
					return "Invalid 'requests'-type: $part";
				}
			}
		}
	}

	#################
	#### disable ####

	if ($attrName eq "disable") {
		if ($cmd eq "set" and $attrVal eq "1") {
			WS980_Close($hash);
			readingsSingleUpdate ( $hash, "state", "disabled", 1 );
			Log3 $name, 2, "WS980 ($name) - disabled";
		}
		elsif ($cmd eq "del") {
			readingsSingleUpdate ( $hash, "state", "active", 1 );
			Log3 $name, 2, "WS980 ($name) - enabled";
		}
	}

	#######################
	#### showRawBuffer ####

	if ($attrName eq "showRawBuffer") {
		if ($cmd eq "set" and $attrVal eq "1") {
			# nothing here :)
		}
		elsif ($cmd eq "del") {
			CommandDeleteReading(undef, "$name rawBuffer.*");
		}
	}

	return undef;
}


#------------------------------------------------------------------------------------------------------
# SetFn
#------------------------------------------------------------------------------------------------------
sub WS980_SetFn($$@)
{
	my ($hash, $name, @aa) = @_;
	my ($cmd, @args) = @aa;

	if ($cmd eq "?") {
		return "Unknown argument $cmd, choose one of " if WS980_isDisabled($hash);
	}

	if ($cmd eq 'update') {
		return "usage: update" if( @args != 0 );
		WS980_updateValues($hash);
		return undef;
	}

	my  $list = "update:noArg";
	return "Unknown argument $cmd, choose one of $list";
}

#------------------------------------------------------------------------------------------------------
# request values from WS980 device
#------------------------------------------------------------------------------------------------------
sub WS980_autodiscoverIP($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "WS980 ($name) - WS980_autodiscoverIP";

	my $socket = IO::Socket::INET->new(
		PeerAddr => inet_ntoa(INADDR_BROADCAST),
		Broadcast => 1,
		ReusAddr => 1,
		ReusePort => 1,
		PeerPort => '46000',
		Proto    => 'udp',
		Type     => SOCK_DGRAM
	);

	if (!$socket) {
		Log3 $name, 1, "WS980 ($name) - autodiscovery failed: no socket";
		return (undef,undef);
	}

	my $recvSocket = IO::Socket::INET->new(
		Proto    => 'udp',
		LocalPort => $socket->sockport(),
		ReusAddr => 1,
		ReusePort => 1,
	);

	if (!$recvSocket) {
		Log3 $name, 1, "WS980 ($name) - autodiscovery failed: no recvSocket";
		return (undef,undef);
	}

	# set receive timeout to 500msecs second (format is: secs, microsecs)
	if (!$recvSocket->setsockopt(SOL_SOCKET, SO_RCVTIMEO, pack('l!l!', 0, 500*1000))) {
		Log3 $name, 1, "WS980 ($name) - autodiscovery failed: could not set SO_RCVTIMEO on recvSocket";
		return (undef,undef);
	}

	# Broadcast auf 255.255.255.255:46000
	# -> ffff12000416
	my $req = WS980_createRequestRaw("\x12");

	# send request
	Log3 $name, 4, "WS980 ($name) - broadcasting auto-discovery: " . WS980_hexDump($req);
	if ($socket->send($req) == 0) {
		Log3 $name, 1, "WS980 ($name) - autodiscovery failed: cannot send request";
		return (undef,undef);
	}
	$socket->close();

	# receive a response of up to 10240 characters from server
	my $rawbuf;
	$recvSocket->recv($rawbuf, 10240);
	$recvSocket->close();

	# ffff 12 LLLL ?? ?? ?? ?? ?? ?? I1 I2 I3 I4 PPPP LN NN..NN C2
	#              84 f3 eb 21 8c d1
	Log3 $name, 4, "WS980 ($name) - received raw reply: " . WS980_hexDump($rawbuf);

	my ($typeStr, $buf) = WS980_handleReply($hash, $rawbuf);
	my ($ip1, $ip2, $ip3, $ip4, $port, $stationName) = unpack("x[6]CCCCnC/A", $buf);
	Log3 $name, 2, "WS980 ($name) - reply: $ip1, $ip2, $ip3, $ip4, $port, $stationName";

	return (sprintf("%d.%d.%d.%d", $ip1, $ip2, $ip3, $ip4), $port);
}


#------------------------------------------------------------------------------------------------------
# request values from WS980 device
#------------------------------------------------------------------------------------------------------
sub WS980_updateValues($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $ip = $hash->{IP};

	Log3 $name, 5, "WS980 ($name) - WS980_updateValues called";

	my $interval = $hash->{INTERVAL};
	RemoveInternalTimer($hash, "WS980_updateValues");
	InternalTimer(gettimeofday()+$interval, "WS980_updateValues", $hash);

	return undef if (WS980_isDisabled($hash));

	if ($hash->{helper}{requestInProgress} == 1) {
		my $logLevel = AttrVal($name, "silentReconnect", "") eq "1" ? 4 : 3;
		Log3 $name, $logLevel, "WS980 ($name) - looks like the last request did not receive an answer, trying to reconnect";
		WS980_Close($hash);
	}

	my @activeRequests = split(/[, ]/, AttrVal($name, "requests", ""));
	if (!@activeRequests) {
		@activeRequests = keys %{REQUESTS()};
	}
	$hash->{helper}{activeRequests} = \@activeRequests;

	my $ok = WS980_Open($hash);
	WS980_writeNextActiveRequest($hash) if ($ok);

	return undef;
}


#------------------------------------------------------------------------------------------------------
# takes the next request from @activeRequests and sends it to the WS980
#------------------------------------------------------------------------------------------------------
sub WS980_writeNextActiveRequest($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "WS980 ($name) - activeRquests: " . join(" ", @{$hash->{helper}{activeRequests}});

	my $valueType = shift(@{$hash->{helper}{activeRequests}});
	if (!defined($valueType)) {
		my $datestring = strftime "%F %T", localtime;
		readingsSingleUpdate($hash, "lastUpdate", "$datestring", 1);

		if (AttrVal($name, "connection", "Keep-Alive") eq "Close") {
			WS980_Close($hash);
		}
		return;
	}

	my $buf = WS980_createRequest($hash, $valueType);
	if (defined $buf) {
		my $logLevel = AttrVal($name, "silentReconnect", "") eq "1" ? 4 : 3;
		Log3 $name, $logLevel, "WS980 ($name) - Sending new request for '$valueType'...";
		WS980_WriteFn($hash, $buf);
	} else {
		WS980_Close($hash);
	}
}


#------------------------------------------------------------------------------------------------------
# update multiple 'values'
#------------------------------------------------------------------------------------------------------
sub WS980_handleMultiValuesUpdate($$$)
{
	my ($hash, $valueType, $buf) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "WS980 ($name) - decoding block: " . WS980_hexDump($buf);

	for (my $i = 0; $i < length($buf); )
	{
		my $id = unpack("x[$i] C", $buf);
		$i += 1;

		my $hasDate = ($id & HAS_DATE);
		my $hasTime = ($id & HAS_TIME);

		$id = $id & ~HAS_DATE & ~HAS_TIME;

		if (!(exists VALUES->{$id})) {
			my $decs = "";
			my $hexs = "";
			for (my $j = $i; $j < length($buf); $j++) {
				my $hex = WS980_binToHex(substr($buf,$j,1));
				$decs .= sprintf("%d ", hex($hex));
				$hexs .= sprintf("%s ", $hex);
			}
			WS980_error($hash, sprintf("%d not found\n[%s]\n[%s]", $id, $decs, $hexs));
			last;
		}

		my $reading = VALUES->{$id}{"name"};
		if (defined(REQUESTS->{$valueType}{"prefix"})) {
			$reading = REQUESTS->{$valueType}{"prefix"} . $reading;
		};
		if (defined(REQUESTS->{$valueType}{"postfix"})) {
			$reading .= REQUESTS->{$valueType}{"postfix"};
		};

		my $bytes  = VALUES->{$id}{"bytes"};
		my $factor = VALUES->{$id}{"factor"};
		my $format = VALUES->{$id}{"format"};
		my $unit   = VALUES->{$id}{"unit"};

		my $ffff   = "\xff"x($bytes);

		my $value = substr($buf, $i, $bytes);
		$i += $bytes;

		# just print the hex values if $format is "raw"
		if ($format eq "raw") {
			$value = WS980_hexDump($value);
		} elsif ($value eq $ffff) {
			$value = "n/a";
		} else {
			$value = hex(WS980_binToHex($value));
			# convert negative values
			my $lbit = 1 << ($bytes * 2 * 4) - 1;
			if ($value & $lbit) {
				$value = $value - ($lbit << 1);
			}
			# respect $factor
			$value = $value / $factor;

			# handle unit conversion
			if (defined(UNIT_CONVERSIONS->{$unit})) {
				my $newUnit = AttrVal($name, UNIT_CONVERSIONS->{$unit}{attr}, $unit);
				if ($newUnit ne $unit) {
					if (defined(UNIT_CONVERSIONS->{$unit}{"fnc"}{$newUnit})) {
						my $fnc = UNIT_CONVERSIONS->{$unit}{"fnc"}{$newUnit};
						$value = $fnc->($value);
					}
				}
			}

			# and format
			$value = sprintf($format, $value)
		}

		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
		if ($hasDate) {
			($year, $mon, $mday) = unpack("x[$i] CCC", $buf);
			$year += 2000;
			$i += 1 + 1 + 1; # 2000+year + month + day
			WS980_error($hash, sprintf("hasDate is not handeled"));
		}

		if ($hasTime) {
			($hour, $min) = unpack("x[$i] CC", $buf);
			$i += 1 + 1; # hour + minute
		}

		my $ts;
		if ($hasDate || $hasTime) {
			$ts = sprintf("%04d-%02d-%02d %02d:%02d:00", $year+1900, $mon+1, $mday, $hour, $min);
		}

		readingsBeginUpdate($hash);
		if ($hasDate || $hasTime) {
			$hash->{".updateTimestamp"} = $ts;;
		}
		my $offset = $#{ $hash->{CHANGED} };
		readingsBulkUpdate($hash, $reading, $value, 1);
		if (($hasDate || $hasTime) && ($#{ $hash->{CHANGED} } != $offset)) {
			# only add ts if there is a event to
			$hash->{CHANGETIME}->[$#{ $hash->{CHANGED} }] = $ts;
		}
		readingsEndUpdate($hash,1);
	}
}


#------------------------------------------------------------------------------------------------------
# update a single 'value'
#------------------------------------------------------------------------------------------------------
sub WS980_handleSingleValuesUpdate($$$)
{
	my ($hash, $valueType, $buf) = @_;
	my $name = $hash->{NAME};

	my $len = REQUESTS->{$valueType}{"value"}{"width"};
	if ($len eq "auto") {
		my $value = unpack("C/A", $buf);
		readingsSingleUpdate($hash, REQUESTS->{$valueType}{"value"}{"name"}, $value, 1);
	} else {
		WS980_error($hash, "cannot decode value in WS980_handleSingleValuesUpdate: " . $valueType);
	}
}

#------------------------------------------------------------------------------------------------------
# * if disabled -> ...
#------------------------------------------------------------------------------------------------------
sub WS980_isDisabled($)
{
	my ($hash) = @_;
	return AttrVal($hash->{NAME}, "disable", "0") eq "1" ||
	       IsDisabled($hash->{NAME});
}

#------------------------------------------------------------------------------------------------------
# creates the binary request buffer for $valueType from %{REQUESTS()}
#------------------------------------------------------------------------------------------------------
sub WS980_createRequest($$)
{
	my ($hash, $valueType) = @_;
	my $name = $hash->{NAME};

	if (!defined REQUESTS->{$valueType}) {
		WS980_error($hash, "WS980_createRequest failed to create request: no config for $valueType");
		return undef;
	}

	if (defined REQUESTS->{$valueType}{"req"}) {
		return REQUESTS->{$valueType}{"req"};
	}

	return WS980_createRequestRaw(
		defined(REQUESTS->{$valueType}{"type"})    ? REQUESTS->{$valueType}{"type"}    : undef,
		defined(REQUESTS->{$valueType}{"subtype"}) ? REQUESTS->{$valueType}{"subtype"} : undef,
		defined(REQUESTS->{$valueType}{"data"})    ? REQUESTS->{$valueType}{"data"}    : undef
	);
}

#------------------------------------------------------------------------------------------------------
# creates the binary request buffer for $type, $subtype and $data
#------------------------------------------------------------------------------------------------------
sub WS980_createRequestRaw($;$$)
{
	my ($type, $subtype, $data) = @_;

	$type    = "" if (!defined($type));
	$subtype = "" if (!defined($subtype));
	$data    = "" if (!defined($data));

	if ($type eq "\x0b") {
		# ffff 0b LLLL XX C1 C2
		my $cmd     = $subtype . $data;
		my $c1      = WS980_calculateChecksum($cmd);

		my $len     = 1 + 2 + length($cmd) + 1 + 1; # $type + LLLL + $cmd + $c1 + $c2
		my $req     = $type . pack("n", $len) . $cmd . pack("C", $c1);
		my $c2      = WS980_calculateChecksum($req);
		return "\xff\xff" . $req . pack("C", $c2);
	}
	elsif ($type eq "\x12") {
		# ffff 12 LLLL C2
		my $len  = 1 + 2 + 1; # $type + LLLL + $c2
		my $req  = $type . pack("n", $len);
		my $c2   = WS980_calculateChecksum($req);
		return "\xff\xff" . $req . pack("C", $c2);
	}
	elsif ($type eq "\x50") {
		# ffff 50 LL C2
		my $len  = 1 + 1 + 1; # $type + LL + $c2
		my $req  = $type . pack("C", $len);
		my $c2   = WS980_calculateChecksum($req);
		return "\xff\xff" . $req . pack("C", $c2);
	}

	return undef;
}


#------------------------------------------------------------------------------------------------------
# parses the reply from the WS980
#------------------------------------------------------------------------------------------------------
sub WS980_handleReply($$)
{
	my ($hash, $buf) = @_;
	my $name = $hash->{NAME};

	# remove leading 'ffff'
	if ($buf =~ /^\xff\xff/) {
		$buf = substr($buf, 2);
	} else {
		WS980_error($hash, "msg did not start with ffff");
		return (undef, undef);
	}

	my $typeStr = "";
	my $type = substr($buf, 0, 1);

	if ($type eq "\x0b") {
		# 0b has a checksum and a 2 byte length field
		if (!WS980_checkChecksum($buf)) {
			WS980_error($hash, "first checksum did not match");
			return (undef, undef);
		}

		# remove $type
		$buf = substr($buf, 1);

		# check and remove the 2 byte length-field
		my $len = unpack("n", $buf);
		if ($len != length($buf) + 1) { # incl $type
			WS980_error($hash, "length did not match: " . sprintf("%02x vs %02x", $len, length($buf)+1));
			return (undef, undef);
		}
		$buf = substr($buf, 2);

		# remove the first checksum
		$buf = substr($buf, 0, -1);

		# check the second checksum
		if (!WS980_checkChecksum($buf)) {
			WS980_error($hash, "second checksum did not match");
			return (undef, undef);
		}

		# remove the second checksum
		$buf = substr($buf, 0, -1);

		# the next byte encodes the subtype (04, 05, 06, ...)
		my $subType = substr($buf, 0, 1);
		$typeStr = WS980_findConfigKey($type, $subType);
		$buf = substr($buf, 1);
	}
	elsif ($type eq "\x12") { # autodiscovery
		# 12 has a checksum and a 2 byte length field
		if (!WS980_checkChecksum($buf)) {
			WS980_error($hash, "first checksum did not match");
			return (undef, undef);
		}

		# remove $type
		$buf = substr($buf, 1);

		# check and remove the 2 byte length-field
		my $len = unpack("n", $buf);
		if ($len != length($buf) + 1 + 2) { # incl $type + FFFF
			WS980_error($hash, "length did not match: " . sprintf("%02x vs %02x", $len, length($buf)+3));
			return (undef, undef);
		}
		$buf = substr($buf, 2);
	}
	elsif ($type eq "\x50") { # firmware
		# remove '50'
		$buf = substr($buf, 1);

		$typeStr = WS980_findConfigKey($type);

		# check and remove length-field
		my $len = unpack("C", $buf);
		if ($len != length($buf) + 1) {
			# 50 is missing the checksum, so the length check fails
			# WS980_error($hash, "length did not match: " . sprintf("%02x vs %02x", $len, length($buf)+3));
			# return undef;
		}
		$buf = substr($buf, 1);
	}

	return ($typeStr, $buf);
}

#------------------------------------------------------------------------------------------------------
# returns the configKey for the given type and subtype (0b, 04 -> 'current')
#------------------------------------------------------------------------------------------------------
sub WS980_findConfigKey($;$)
{
	my ($type, $subType) = @_; # bytearrays

	foreach my $key (keys %{REQUESTS()}) {
		if (defined(REQUESTS->{$key}{"type"}) && REQUESTS->{$key}{"type"} eq $type) {
			if (!defined($subType) && !defined(REQUESTS->{$key}{"subtype"})) {
				return $key;
			}
			if (defined(REQUESTS->{$key}{"subtype"}) && REQUESTS->{$key}{"subtype"} eq $subType) {
				return $key;
			}
		}
	}
	return undef;
}


#------------------------------------------------------------------------------------------------------
# opens a connection to IP:PORT
#------------------------------------------------------------------------------------------------------
sub WS980_Open($)
{
	my ($hash) = @_;
	my $name    = $hash->{NAME};
	my $ip      = $hash->{IP};
	my $port    = $hash->{PORT};
	my $timeout = 0.25;

	return 1 if ($hash->{CD});

	my $logLevel = AttrVal($name, "silentReconnect", "") eq "1" ? 4 : 3;
	Log3 $name, $logLevel, "WS980 ($name) - Creating socket connection to $ip:$port";

	my $socket = new IO::Socket::INET(
		PeerAddr => $ip,
		PeerPort => $port,
		Proto    => 'tcp',
		Timeout  => $timeout,
	);

	if (!$socket) {
		$hash->{ConnectionState} = 'disconnected';
		WS980_error($hash, "Couldn't connect to $ip:$port: " . $@);
		return 0;
	}

	# set receive timeout to 500msecs second (format is: secs, microsecs)
	if (!$socket->setsockopt(SOL_SOCKET, SO_RCVTIMEO, pack('l!l!', 0, 500*1000))) {
		WS980_error($hash, "Could not set SO_RCVTIMEO on socket");
		return 0;
	}

	$hash->{FD}    = $socket->fileno();
	$hash->{CD}    = $socket;         # sysread / close won't work on fileno
	$selectlist{$name} = $hash;

	$hash->{ConnectionState} = 'connected';

	Log3 $name, $logLevel, "WS980 ($name) - Socket Connected";
	return 1;
}


#------------------------------------------------------------------------------------------------------
# ReadFn
#------------------------------------------------------------------------------------------------------
sub WS980_ReadFn($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "WS980 ($name) - ReadFn started";

	my $rawbuf;
	my $len = sysread($hash->{CD}, $rawbuf, 10240);

	Log3 $name, 4, "WS980 ($name) - received reply: " . WS980_hexDump($rawbuf);

	$hash->{helper}{requestInProgress} = 0;

	if (!defined($len) or !$len or $len < 1 ) {
		WS980_Close($hash);
		return;
	}

	my ($typeStr, $buf) = WS980_handleReply($hash, $rawbuf);
	$typeStr = "" if (!defined($typeStr));

	if (AttrVal($name, "showRawBuffer", "0") eq "1") {
		readingsSingleUpdate($hash, "rawBuffer_" . $typeStr, WS980_hexDump($rawbuf), 1);
	} else {
		CommandDeleteReading(undef, "$name rawBuffer.*");
	}

	if ($typeStr ne "" && defined($buf)) {
		if ($typeStr eq "firmware") {
			WS980_handleSingleValuesUpdate($hash, $typeStr, $buf);
		} else {
			WS980_handleMultiValuesUpdate($hash, $typeStr, $buf);
		}

		WS980_doPostUpdate($hash, $typeStr);
	}
	else
	{
		Log3 $name, 1, "WS980 ($name) - looks like the reply could not be decoded, skipping";
	}

	WS980_writeNextActiveRequest($hash);
}

#------------------------------------------------------------------------------------------------------
# called just after updating readings
#------------------------------------------------------------------------------------------------------
sub WS980_doPostUpdate($$)
{
	my ($hash, $typeStr)  = @_;
	my $name = $hash->{NAME};

	if ($typeStr eq "current") {
		WS980_updateState($hash);
		WS980_updateRain24h($hash);
		WS980_updateRelPressure($hash);
		WS980_updateEvents($hash);
	}
}


#------------------------------------------------------------------------------------------------------
# updates the state-reading
#------------------------------------------------------------------------------------------------------
sub WS980_updateState($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $val = 'T: ' . ReadingsNum($name, "temperature", 0.0) . AttrVal($name, UNIT_CONVERSIONS->{"°C"}{"attr"}, "°C")   . " "
			. 'H: ' . ReadingsNum($name, "humidity",    0.0) . '% '
			. 'W: ' . ReadingsNum($name, "wind",        0.0) . AttrVal($name, UNIT_CONVERSIONS->{"m/s"}{"attr"}, "m/s") . " "
			. 'P: ' . ReadingsNum($name, "pressureAbs", 0.0) . AttrVal($name, UNIT_CONVERSIONS->{"hPa"}{"attr"}, "hPa") . " ";

	readingsSingleUpdate($hash, "state", $val, 1);
}


#------------------------------------------------------------------------------------------------------
# calculates and updates the rain24h-reading
#------------------------------------------------------------------------------------------------------
sub WS980_updateRain24h($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $interval = 3600;

	my $lastTS = ReadingsNum($name, ".rain24h_lastTS", 0);
	my $curTS  = int(gettimeofday() / $interval);
	return if ($lastTS == $curTS);

	Log3 $name, 5, "WS980 ($name) - updating rain24h ...";
	readingsSingleUpdate($hash, ".rain24h_lastTS", $curTS, 1);

	my $curRainTotal = ReadingsNum($name, "rainTotal", -1);
	return if ($curRainTotal == -1);

	my @values = split(/[|]/, ReadingsVal($name, ".rain24h_hourly", ""));
	push(@values, $curRainTotal);

	my $count = scalar(@values);
	if ($count > 24) {
		my $lastRainTotal = shift(@values);
		readingsSingleUpdate($hash, "rain24h", sprintf("%.1f", $curRainTotal - $lastRainTotal), 1);
	} else {
		my $lastRainTotal = $values[0];
		readingsSingleUpdate($hash, "rain24h", sprintf("(%.1f in %dh)", $curRainTotal - $lastRainTotal, $count), 1);
	}

	readingsSingleUpdate($hash, ".rain24h_hourly", join('|', @values), 1);
}

#------------------------------------------------------------------------------------------------------
# calculates and update the relative pressure
#------------------------------------------------------------------------------------------------------
sub WS980_updateRelPressure($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $altitude = 0;
	if (defined($attr{$name}{"altitude"})){
		$altitude = $attr{$name}{"altitude"};
	} elsif (defined($attr{"global"}{"altitude"})) {
		$altitude = $attr{"global"}{"altitude"};
	}

	my $relPressure = WS980_calculateRelPressure_QFF(
		ReadingsVal($name, "temperature", 0.0),
		ReadingsVal($name, "pressureAbs", 0.0),
		$altitude,
		ReadingsVal($name, "humidity", 0.0));

	readingsSingleUpdate($hash, "pressureRel_calculated", sprintf("%.1f", $relPressure), 1);
}

#------------------------------------------------------------------------------------------------------
# https://www.symcon.de/forum/threads/6480-Relativen-Luftdruck-aus-absoluten-Luftdruck-errechnen
# QNH: Luftdruckangabe auf Meereshöhe nach einer Standardatmosphäre (nach ICAO) reduziert (Flughäfen,
# CWOP-Stationen, APRS) nach http://dk0te.ba-ravensburg.de/cgi-bin/navi?m=WX_BAROMETER
#------------------------------------------------------------------------------------------------------
sub WS980_calculateRelPressure_QNH($$$)
{
	my ($Temperature, $AirPressureAbsolute, $Altitude) = @_;

	my $g_n = 9.80665;       # Erdbeschleunigung (m/s^2)
	my $gam = 0.0065;        # Temperaturabnahme in K pro geopotentiellen Metern (K/gpm)
	my $R   = 287.06;        # Gaskonstante für trockene Luft (R = R_0 / M)
	my $M   = 0.0289644;     # Molare Masse trockener Luft (J/kgK)
	my $R_0 = 8.314472;      # allgemeine Gaskonstante (J/molK)
	my $T_0 = 273.15;        # Umrechnung von °C in K

	my $p = $AirPressureAbsolute * ((($gam * $Altitude + $Temperature + $T_0) / ($Temperature + $T_0)) ** ($g_n / ($R * $gam)));
	return $p;
}

#------------------------------------------------------------------------------------------------------
# https://www.symcon.de/forum/threads/6480-Relativen-Luftdruck-aus-absoluten-Luftdruck-errechnen
# QFF: Luftdruckangabe auf Meereshöhe umgerechnet (DWD)
# nach http://dk0te.ba-ravensburg.de/cgi-bin/navi?m=WX_BAROMETER
#------------------------------------------------------------------------------------------------------
sub WS980_calculateRelPressure_QFF($$$$)
{
	my ($Temperature, $AirPressureAbsolute, $Altitude, $Humidity) = @_;

	my $g_n = 9.80665;     # Erdbeschleunigung (m/s^2)
	my $gam = 0.0065;      # Temperaturabnahme in K pro geopotentiellen Metern (K/gpm)
	my $R   = 287.06;      # Gaskonstante für trockene Luft (R = R_0 / M)
	my $M   = 0.0289644;   # Molare Masse trockener Luft (J/kgK)
	my $R_0 = 8.314472;    # allgemeine Gaskonstante (J/molK)
	my $T_0 = 273.15;      # Umrechnung von °C in K
	my $C   = 0.11;        # DWD-Beiwert für die Berücksichtigung der Luftfeuchte

	my $E_0 = 6.11213;                # (hPa)
	my $f_rel = $Humidity / 100;      # relative Luftfeuchte (0-1.0)
	# momentaner Stationsdampfdruck (hPa)
	my $e_d = $f_rel * $E_0 * exp((17.5043 * $Temperature) / (241.2 + $Temperature));

	my $p = $AirPressureAbsolute * exp(($g_n * $Altitude) / ($R * ($Temperature + $T_0 + $C * $e_d + (($gam * $Altitude) / 2))));
	return $p;
}

#------------------------------------------------------------------------------------------------------
# converts the 'event'-attribute into an internal structure
#------------------------------------------------------------------------------------------------------
sub WS980_parseEventsAttr($$)
{
	my ($hash, $attrVal)  = @_;
	my $name = $hash->{NAME};

	my %oldEventsConfig;
	if ($hash->{helper}{eventsConfig}) {
		%oldEventsConfig = %{$hash->{helper}{eventsConfig}}
	}

	# compact the input to be able to parse it right
	$attrVal =~ s/\n/|/g;  # newline -> |
	$attrVal =~ s/\s//g;   # " " -> ""
	$attrVal =~ s/\|+/|/g; # || -> |

	Log3 $name, 5, "WS980 ($name) - WS980_parseEventsAttr for $attrVal";

	# parse attribute
	my %eventsConfig;
	my @cfgs = split("[|]", $attrVal);
	foreach my $cfg (@cfgs) {
		my ($event, $readingAndLimit, $hysterese) = split(/[,:]/, $cfg);        # dusk:brightness<20,20
		my ($srcReading, $type, $limit) = split(/\b/, $readingAndLimit);        # brightness<20

		my $eventReading = "is" . uc(substr($event, 0, 1)) . substr($event, 1); # isDusk
		$eventsConfig{$eventReading}{"src"}   = $srcReading;
		$eventsConfig{$eventReading}{"type"}  = $type;
		$eventsConfig{$eventReading}{"limit"} = $limit;
		$eventsConfig{$eventReading}{"hyst"}  = int($hysterese);

		Log3 $name, 5, "WS980 ($name) - adding event-configuration for $eventReading: $srcReading, $type, $limit, $hysterese";
	}

	# remember config in $hash->{helper}
	$hash->{helper}{eventsConfig} = \%eventsConfig;

	# delete removed events
	foreach my $oldReading (keys %oldEventsConfig) {
		if (!defined($eventsConfig{$oldReading})) {
			Log3 $name, 5, "WS980 ($name) - removing event-configuration for $oldReading";
			CommandDeleteReading( undef, "$name ".    $oldReading);
			CommandDeleteReading( undef, "$name ".".".$oldReading."_hyst");
		}
	}

	# initialize new events if init was done already
	if ($init_done) {
		WS980_updateEvents($hash)
	}
}

#------------------------------------------------------------------------------------------------------
# updates all events from readings
#------------------------------------------------------------------------------------------------------
sub WS980_updateEvents($)
{
	my ($hash)  = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "WS980 ($name) - WS980_updateEvents";
	if (!$hash->{helper}{eventsConfig}) {
		return
	}

	my %beConfig = %{$hash->{helper}{eventsConfig}};

	# handle events
	readingsBeginUpdate($hash);
	foreach my $readingName (keys %beConfig)
	{
		my $hystReadingName = "." . $readingName . "_hyst";
		my $src   = $beConfig{$readingName}{"src"};           # brightness
		my $type  = $beConfig{$readingName}{"type"};          # <|>
		my $limit = $beConfig{$readingName}{"limit"};         # 5000
		my $hyst  = $beConfig{$readingName}{"hyst"};          # 100

		my $prevState     = ReadingsNum($name, $readingName,     -1); # 0, 1
		my $prevHystState = ReadingsNum($name, $hystReadingName, -1); # 0, 1

		my $srcValue = ReadingsNum($name, $src, -1);          # 23540

		if ($type eq "<") {
			if ($prevState == -1) {
				Log3 $name, 5, "WS980 ($name) - adding event $readingName";
				readingsBulkUpdate($hash, $readingName,     $srcValue <= $limit ? "1" : "0", 1);
				readingsBulkUpdate($hash, $hystReadingName, "0",                             0);
			} else {
				if ($srcValue <= maxNum(0, $limit - $hyst)) {
					readingsBulkUpdate($hash, $readingName,     "1", 1);
					readingsBulkUpdate($hash, $hystReadingName, "0", 0);
				} elsif ($srcValue <= $limit) {
					if ($prevState == 0 && $prevHystState == 0) {
						readingsBulkUpdate($hash, $readingName,     "1", 1);
						readingsBulkUpdate($hash, $hystReadingName, "1", 0);
					}
				} elsif ($srcValue <= $limit + $hyst) {
					if ($prevState == 1 && $prevHystState == 0) {
						readingsBulkUpdate($hash, $readingName,     "0", 1);
						readingsBulkUpdate($hash, $hystReadingName, "1", 0);
					}
				} else {
					readingsBulkUpdate($hash, $readingName,     "0", 1);
					readingsBulkUpdate($hash, $hystReadingName, "0", 0);
				}
			}
		}
		elsif ($type eq ">") {
			if ($prevState == -1) {
				Log3 $name, 5, "WS980 ($name) - adding event $readingName";
				readingsBulkUpdate($hash, $readingName,     $srcValue >= $limit ? "1" : "0", 1);
				readingsBulkUpdate($hash, $hystReadingName, "0",                             0);
			} else {
				if ($srcValue >= $limit + $hyst) {
					readingsBulkUpdate($hash, $readingName,     "1", 1);
					readingsBulkUpdate($hash, $hystReadingName, "0", 01);
				} elsif ($srcValue >= $limit) {
					if ($prevState == 0 && $prevHystState == 0) {
						readingsBulkUpdate($hash, $readingName,     "1", 1);
						readingsBulkUpdate($hash, $hystReadingName, "1", 0);
					}
				} elsif ($srcValue >= maxNum(0, $limit - $hyst)) {
					if ($prevState == 1 && $prevHystState == 0) {
						readingsBulkUpdate($hash, $readingName,     "0", 1);
						readingsBulkUpdate($hash, $hystReadingName, "1", 0);
					}
				} else {
					readingsBulkUpdate($hash, $readingName,     "0", 1);
					readingsBulkUpdate($hash, $hystReadingName, "0", 0);
				}
			}
		}
		else {
			# ERROR
		}
	}
	readingsEndUpdate($hash, 1);
}

#------------------------------------------------------------------------------------------------------
# WriteFn
#------------------------------------------------------------------------------------------------------
sub WS980_WriteFn($$)
{
	my ($hash, $buf)  = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "WS980 ($name) - WriteFn called";

	return Log3 $name, 1, "WS980 ($name) - socket not connected" unless($hash->{CD});

	Log3 $name, 5, "WS980 ($name) - sending " . WS980_hexDump($buf);
	my $bytes = syswrite($hash->{CD}, $buf);

	# success?
	if (defined($bytes) && $bytes == length($buf)) {
		$hash->{helper}{requestInProgress} = 1;
		Log3 $name, 5, "WS980 ($name) - sent $bytes bytes";
	} else {
		my $err = "Wrote incomplete data";
		if (!defined ($bytes)) {
			$err = $!;
		}
		WS980_error($hash, "error sending data: " . $err);
		WS980_Close($hash);
	}
	return undef;
}


#------------------------------------------------------------------------------------------------------
# close
#------------------------------------------------------------------------------------------------------
sub WS980_Close($)
{
	my ($hash) = @_;
	my $name    = $hash->{NAME};

	return if( !$hash->{CD} );

	close($hash->{CD}) if($hash->{CD});
	delete($hash->{FD});
	delete($hash->{CD});
	delete($selectlist{$name});

	$hash->{ConnectionState} = 'disconnected';

	my $logLevel = AttrVal($name, "silentReconnect", "") eq "1" ? 4 : 3;
	Log3 $name, $logLevel, "WS980 ($name) - Socket Disconnected";
}


#------------------------------------------------------------------------------------------------------
# updates lastError-Reading and logs the message
#------------------------------------------------------------------------------------------------------
sub WS980_error($$)
{
	my ($hash, $msg) = @_;
	my $name = $hash->{NAME};

	readingsSingleUpdate($hash, "lastError", $msg, 1);
	Log3 $name, 1, "WS980 ($name) - ERROR: $msg";
}


#------------------------------------------------------------------------------------------------------
# used to automatically extract attributes from UNIT_CONVERSIONS for AttrList
#------------------------------------------------------------------------------------------------------
sub WS980_extractAttrsFromUnits()
{
	my $retval;
	foreach my $unit (keys %{UNIT_CONVERSIONS()}) {
		my $attr = UNIT_CONVERSIONS->{$unit}{"attr"} . ":";
		my @units =  keys %{UNIT_CONVERSIONS->{$unit}{"fnc"}};
		$retval .= $attr . join(",", @units) . " ";
	}
	return $retval;
}


#------------------------------------------------------------------------------------------------------
# converts a binary input to hex-string '\x23\xff' -> "23ff"
#------------------------------------------------------------------------------------------------------
sub WS980_binToHex($)
{
	my ($bin) = @_;

	my @array = split('', $bin);

	my $hex = "";
	foreach (@array) {
		$hex .= sprintf("%02x", ord($_));
	}
	return $hex;
}

#------------------------------------------------------------------------------------------------------
# returns a readable representation of the already hex formated input like "ffff0b005004..."
#------------------------------------------------------------------------------------------------------
sub WS980_hexDump($)
{
	my ($buf) = @_;

	my @retval;
	my @array = unpack("C*", $buf);
	for (my $i = 0; $i < scalar(@array); $i++) {
		push (@retval, sprintf('%02x', $array[$i]));
	}
	return "[" . join(" ", @retval) . "]";
}

#------------------------------------------------------------------------------------------------------
# calculates the checksum of $buf and returns it
#   The checksum is the sum of each byte & 0xff
#------------------------------------------------------------------------------------------------------
sub WS980_calculateChecksum($)
{
	my ($buf) = @_;

	return unpack('%16C*', $buf);
}

#------------------------------------------------------------------------------------------------------
# calculates the checksum of $buf[0..-2] and compares it to $buf[-1..-0]
#------------------------------------------------------------------------------------------------------
sub WS980_checkChecksum($)
{
	my ($buf) = @_;

	my $actual   = WS980_calculateChecksum(substr($buf, -1)); # exclude the checksum
	my $expected = ord(substr($buf, -1));
	return $actual == $expected;
}

1;


=pod
=item device
=item summary    Module to request weather data form WS980WiFi weather stations
=item summary_DE Modul zum Abfragen von Wetterdaten aus WS980WiFi-Wetterstationen

=begin html

<a name="WS980"></a>
<h3>WS980</h3>
<ul>
	<b>WS980 - Requests weather data locally from WS980WiFi weather stations</b><br>

	<br>

	<a name="WS980define"></a>
	<b>Define</b><br>
	<br>
	<code>define &lt;name&gt; WS980 [IP] [INTERVAL]</code><br>
	<br>
	<code>[IP]</code> Optional: The IP of the WS980WiFi. If no IP is given, the station is auto-discovered.<br>
	<code>[INTERVAL]</code> Optional: The interval in seconds to request updates, default: 30 seconds.<br>
	<br>
	Example:<br>
	<br>
	<code>define ws980wifi WS980 192.168.2.177 60</code><br>
	<br>
	This statement creates an WS980 instance with the name ws980wifi with the IP 192.168.2.177.<br>
	With an interval of 60 seconds the weather information are requested.
	<br>
	<br>

	<a name="WS980readings"></a>
	<b>Readings</b>
	<ul>
		<li>
			<dt><code><b>temperatureInside</b> [<b>°C</b>]</code></dt>
			The IN-temperature at the display.
		</li>
		<li>
			<dt><code><b>temperature</b> [<b>°C</b>]</code></dt>
			The temperature measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>dewPoint</b> [<b>°C</b>]</code></dt>
			The dew-point calculated by the weather station.
		</li>
		<li>
			<dt><code><b>windChill</b> [<b>°C</b>]</code></dt>
			The wind-chill calculated by the weather station.
		</li>
		<li>
			<dt><code><b>heatIndex</b> [<b>°C</b>]</code></dt>
			The heat-index calculated by the weather station.
		</li>
		<li>
			<dt><code><b>humidityInside</b> [<b>%</b>]</code></dt>
			The IN-humidity at the display.
		</li>
		<li>
			<dt><code><b>humidity</b> [<b>%</b>]</code></dt>
			The humidity measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>pressureAbs</b> [<b>hPa</b>]</code></dt>
			The absolute pressure measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>pressureRel</b> [<b>hPa</b>]</code></dt>
			The relative pressure measured by the outdoor probe. This only differs from <i>pressureAbs</i> if you have an offset configured in your weather station.
		</li>
		<li>
			<dt><code><b>pressureRel_calculated</b> [<b>hPa</b>]</code></dt>
			The relative pressure calculated using the QFF forumula based on temperature, pressureAbs, altitude and humidity.
		</li>
		<li>
			<dt><code><b>windDirection</b> [<b>°</b>]</code></dt>
			The wind-direction measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>wind</b> [<b>m/s</b>]</code></dt>
			The wind-seed measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>windGusts</b> [<b>m/s</b>]</code></dt>
			The speed of wind-gusts measured by the outdoor probe.
		</li>
		<!--
		<li>
			<dt><code><b>rainEvent</b> [<b>mm</b>]</code></dt>
			**Not Supported**.
		</li>
		-->
		<li>
			<dt><code><b>rainRate</b> [<b>mm</b>]</code></dt>
			The current rain-rate measured by the outdoor probe.
		</li>
		<!--
		<li>
			<dt><code><b>rainPerHour</b> [<b>mm</b>]</code></dt>
			**Not Supported** The rain-rate per hour measured by the outdoor probe.
		</li>
		-->
		<li>
			<dt><code><b>rainPerDay</b> [<b>mm</b>]</code></dt>
			The rain-rate per day measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>rainPerWeek</b> [<b>mm</b>]</code></dt>
			The rain-rate per week measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>rainPerMonth</b> [<b>mm</b>]</code></dt>
			The rain-rate per month measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>rainPerYear</b> [<b>mm</b>]</code></dt>
			The rain-rate per year measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>rainTotal</b> [<b>mm</b>]</code></dt>
			The total rain-rate measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>rain24h</b> [<b>mm</b>]</code></dt>
			The amount of rain in the last 24h. This value is calculated from <code>rainTotal</code> and is updated once per hour. In the first 24h, the amunt is displayed in "()" and shows the count of hours recorded already.
		</li>
		<li>
			<dt><code><b>brightness</b> [<b>lux</b>]</code></dt>
			The brightness measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>uv</b> [<b>uW/m²</b>]</code></dt>
			The raw UV-values measured by the outdoor probe.
		</li>
		<li>
			<dt><code><b>uvIndex</b> [<b>0-15</b>]</code></dt>
			The UV-Index calculated by the weather station.
		</li>
	</ul>
	<br>

	<a name="WS980set"></a>
	<b>Set</b>
	<ul>
		<li>
			<i>update</i><br>
			manually update current weather data
		</li>
	</ul>
	<br>

	<a name="WS980attribut"></a>
	<b>Attributes</b>
	<ul>
		<li><a name="altitude"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>altitude </b>&lt;<b>height</b>&gt;</code></dt>
			Specifies the mean sea level in meters. Default is 0. Used to calculate the <code>pressureRel_calculated</code>-reading. If unset, the altitude from global is used.
		</li>
		<li><a name="connection"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>connection </b>&lt;<b>Keep-Alive</b>|<b>Close</b>&gt;</code></dt>
			<code>Keep-Alive</code>: The connection to the WS980 is kept open as long as possible. Reconnect is only done if necessary. <code>Keep-Alive</code> is default and a good setting in most cases.<br>
			<code>Close</code>: The connection is opened on-the-fly and closed directly after doing requests. <code>Close</code> should only be used if you have multiple clients connection to your WS980 which might cause frequent read-timeouts. <code>ConnectionState</code> will display <code>disconnected</code> most of the time, this is OK!
		</li>
		<li><a name="events"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>events </b>&lt;<b>Configuration</b>&gt;|&lt;<b>Configuration</b>&gt;|...</code></dt>
			Allows to configure custom events based on the readings of this instance.<br>
			&lt;<b>Configuration</b>&gt; must have the form:
			<b><code>NAME:READING&lt;LIMIT,HYSTERESIS</code></b> or <b><code>NAME:READING&gt;LIMIT,HYSTERESIS</code></b>.
			<ul>
				<li><b><code>NAME</code></b>: The name used for the reading and the event. To reduce the possibility of collisions with existing readings, the Name of the reading will always be prefixed with 'is'.</li>
				<li><b><code>READING</code></b>:The name of the reading which will be compared to LIMIT to set the resulting event to 0 or 1.</li>
				<li><b><code>&lt; or &gt</code></b>: For '&lt;' the reading-value must be less than the LIMIT to result in 1, for '&gt;' the reading-value must be above LIMIT to result in 1.</li>
				<li><b><code>LIMIT</code></b>: The value which will be compared to the READINGs current value.</li>
				<li><b><code>HYSTERESIS</code></b>: The hysteresis-value is used to reduce fast flipping of 0 and 1.</li>
			</ul>
			Configurations can be separated by either "|" or newline. All whitespace will be removed when parsing <i>events</i>.
			<br>
			<b>Examples:</b><br>
			<dt><code><b>attr</b> &lt;name&gt; <b>events dusk:brightness&lt;30,20</b></code></dt>
			A new reading <i>isDusk</i> will be autogenerated with possible values 0 or 1. As soon as the <i>brightness</i> drops below 30lux, <i>isDusk</i> will switch to 1. The hystereses value of 20 means, that <i>isDusk</i> will switch back to 0 only after <b>either</b> the <i>brightness</i> has reached 50lux (30+20) <b>or</b> the <i>brightness</i> dropped below 10lux (30-20) and then rises above 30lux again.
			<dt><code><b>attr</b> &lt;name&gt; <b>brightSunlight:brightness&gt;80000,5000</b></code></dt>
			A new reading <i>isBrightSunlight</i> will be autogenerated with possible values 0 or 1. As soon as the <i>brightness</i> rises above 80000lux, <i>isBrightSunlight</i> will switch to 1. The hystereses value of 5000 means, that <i>isBrightSunlight</i> will switch back to 0 only after <b>either</b> the <i>brightness</i> has dropped below 75000lux <b>or</b> the <i>brightness</i> was above 85000lux and then drops below 80000lux again.<br>
			You can concatenate as many <b>Configurations</b> with '|' as you like. For example:
			<dt><code><b>attr</b> &lt;name&gt; <b>dusk:brightness&lt;30,20|brightSunlight:brightness&gt;80000,5000</b></code></dt>
			<br>
		</li>
		<li><a name="requests"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>requests </b>current todayMax ... </code></dt>
			A comma or space separated list of values to requests. If empty, all known values are requested.<br>
			Valid values: firmware, current, todayMax, todayMin, historyMax, historyMin.
		</li>
		<li><a name="showRawBuffer"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>showRawBuffer </b>1</code></dt>
			used for development: show raw data received from the WS980WiFi
		</li>
		<li><a name="silentReconnect"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>silentReconnect </b>1</code></dt>
			If set to 1, then it will set the loglevel for connect- and reconnect-messages to 2 instead of 1
		</li>
		<li><a name="unit_temperature"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>unit_temperature </b>&lt;<b>unit</b>&gt;</code></dt>
			set the unit used for temperature-readings. Default: °C
		</li>
		<li><a name="unit_pressure"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>unit_pressure </b>&lt;<b>unit</b>&gt;</code></dt>
			set the unit used for pressure-readings. Default: hPa
		</li>
		<li><a name="unit_wind"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>unit_wind </b>&lt;<b>unit</b>&gt;</code></dt>
			set the unit used for wind-readings. Default: m/s
		</li>
		<li><a name="unit_rain"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>unit_rain </b>&lt;<b>unit</b>&gt;</code></dt>
			set the unit used for rain-readings. Default: mm
		</li>
		<li><a name="unit_light"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>unit_light </b>&lt;<b>unit</b>&gt;</code></dt>
			set the unit used for brightness-readings. Default: lux
		</li>
		<li><a name="disable"></a>
			<dt><code><b>attr</b> &lt;name&gt; <b>disable </b>1</code></dt>
			disables this WS980-instance
		</li>
	</ul>
</ul>
=end html

# =begin html_DE
#
#
# =end html_DE

# Ende der Commandref
=cut

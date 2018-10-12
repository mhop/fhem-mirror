##############################################################################
#
#     70_ZoneMinder.pm
#
#     This file is part of Fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#  
# ZoneMinder (c) Martin Gutenbrunner / https://github.com/delmar43/FHEM
#
# This module enables FHEM to interact with ZoneMinder surveillance system (see https://zoneminder.com)
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,91847.0.html
#
# $Id$
#
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;
use Crypt::MySQL qw(password41);
use DevIo;
use Digest::MD5 qw(md5 md5_hex md5_base64);

sub ZoneMinder_Initialize {
  my ($hash) = @_;
  $hash->{NotifyOrderPrefix} = "70-";
  $hash->{Clients} = "ZM_Monitor";

  $hash->{GetFn}     = "ZoneMinder_Get";
  $hash->{SetFn}     = "ZoneMinder_Set";
  $hash->{DefFn}     = "ZoneMinder_Define";
  $hash->{UndefFn}   = "ZoneMinder_Undef";
  $hash->{ReadFn}    = "ZoneMinder_Read";
  $hash->{ShutdownFn}= "ZoneMinder_Shutdown";
  $hash->{FW_detailFn} = "ZoneMinder_DetailFn";
  $hash->{WriteFn}   = "ZoneMinder_Write";
  $hash->{ReadyFn}   = "ZoneMinder_Ready";

  $hash->{AttrList} = "interval publicAddress webConsoleContext " . $readingFnAttributes;
  $hash->{MatchList} = { "1:ZM_Monitor" => "^.*" };

  Log3 '', 3, "ZoneMinder - Initialize done ...";
}

sub ZoneMinder_Define {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  $hash->{NOTIFYDEV} = "global";

  my $name   = $a[0];
  $hash->{NAME} = $name;
 
  my $nrArgs = scalar @a;
  if ($nrArgs < 3) {
    my $msg = "ZoneMinder ($name) - Wrong syntax: define <name> ZoneMinder <ZM_URL>";
    Log3 $name, 2, $msg;
    return $msg;
  }

  my $module = $a[1];
  my $zmHost = $a[2];
  $hash->{helper}{ZM_HOST} = $zmHost;
  $zmHost .= ':6802' if (not $zmHost =~ m/:\d+$/);
  $hash->{DeviceName} = $zmHost;

  if ($nrArgs == 4 || $nrArgs > 6) {
    my $msg = "ZoneMinder ($name) - Wrong syntax: define <name> ZoneMinder <ZM_URL> [<ZM_USERNAME> <ZM_PASSWORD>]";
    Log3 $name, 2, $msg;
    return $msg;
  }
 
  if ($nrArgs == 5 || $nrArgs == 6) {
    $hash->{helper}{ZM_USERNAME} = $a[3];
    $hash->{helper}{ZM_PASSWORD} = $a[4];
  }

  DevIo_CloseDev($hash) if (DevIo_IsOpen($hash));
  DevIo_OpenDev($hash, 0, undef);

  ZoneMinder_afterInitialized($hash);

  return undef;
}

sub ZoneMinder_afterInitialized {
  my ($hash) = @_;

  ZoneMinder_API_Login($hash);

  return undef;
}

# so far only used for generating the link to the ZM Web console
# usePublic 0: zmHost, usePublic 1: publicAddress, usePublic undef: use public if publicAddress defined
sub ZoneMinder_getZmWebUrl {
  my ($hash, $usePublic) = @_;
  my $name = $hash->{NAME};
  
  #use private or public LAN for Web access?
  my $publicAddress = ZoneMinder_getPublicAddress($hash);
  my $zmHost = '';

  if ($publicAddress and $usePublic) {
    $zmHost = $publicAddress;
  } else {
    $zmHost = $hash->{helper}{ZM_HOST};
    $zmHost = "http://$zmHost";
  }
  $zmHost .= '/' if (not $zmHost =~ m/\/$/);

  my $zmWebContext = $attr{$name}{webConsoleContext};
  if (not $zmWebContext) {
    $zmWebContext = 'zm';
  }
  $zmHost .= $zmWebContext;
  
  return $zmHost;
}

sub ZoneMinder_getPublicAddress {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return $attr{$name}{publicAddress};
}

# is built by using web-url, and adding /api
sub ZoneMinder_getZmApiUrl {
  my ($hash) = @_;
  
  #use private LAN for API access for a start
  my $zmWebUrl = ZoneMinder_getZmWebUrl($hash, 0);
  return "$zmWebUrl/api";
}

sub ZoneMinder_API_Login {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $username = urlEncode($hash->{helper}{ZM_USERNAME});
  my $password = urlEncode($hash->{helper}{ZM_PASSWORD});

  my $zmWebUrl = ZoneMinder_getZmWebUrl($hash);
  my $loginUrl = "$zmWebUrl/index.php?username=$username&password=$password&action=login&view=console";

  Log3 $name, 4, "ZoneMinder ($name) - loginUrl: $loginUrl";
  my $apiParam = {
    url => $loginUrl,
    method => "POST",
    callback => \&ZoneMinder_API_Login_Callback,
    hash => $hash
  };
  HttpUtils_NonblockingGet($apiParam);
  
#  Log3 $name, 3, "ZoneMinder ($name) - ZoneMinder_API_Login err: $apiErr, data: $apiParam->{httpheader}";
  
  return undef;
}

sub ZoneMinder_API_Login_Callback {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  $hash->{APILoginStatus} = $param->{code};

  if($err ne "") {
    Log3 $name, 0, "error while requesting ".$param->{url}." - $err";
    $hash->{APILoginError} = $err;
  } elsif($data ne "") {
    if ($data =~ m/Invalid username or password/) {
      $hash->{APILoginError} = "Invalid username or password.";
    } else {
      delete($defs{$name}{APILoginError});
      
      ZoneMinder_GetCookies($hash, $param->{httpheader});

      my $isFirst = !$hash->{helper}{apiInitialized};
      if ($isFirst) {
        $hash->{helper}{apiInitialized} = 1;
        my $zmApiUrl = ZoneMinder_getZmApiUrl($hash);
        ZoneMinder_SimpleGet($hash, "$zmApiUrl/host/getVersion.json", \&ZoneMinder_API_ReadHostInfo_Callback);
        ZoneMinder_SimpleGet($hash, "$zmApiUrl/configs.json", \&ZoneMinder_API_ReadConfig_Callback);
        ZoneMinder_API_getLoad($hash);
      }
    }
  }

  InternalTimer(gettimeofday() + 3600, "ZoneMinder_API_Login", $hash);
  
  return undef;
}

sub ZoneMinder_API_getLoad {
  my ($hash) = @_;

  my $zmApiUrl = ZoneMinder_getZmApiUrl($hash);
  ZoneMinder_SimpleGet($hash, "$zmApiUrl/host/getLoad.json", \&ZoneMinder_API_ReadHostLoad_Callback);
}

sub ZoneMinder_SimpleGet {
  my ($hash, $url, $callback) = @_;
  my $name = $hash->{NAME};

  my $apiParam = {
    url => $url,
    method => "GET",
    callback => $callback,
    hash => $hash
  };

  if ($hash->{HTTPCookies}) {
    $apiParam->{header} .= "\r\n" if ($apiParam->{header});
    $apiParam->{header} .= "Cookie: " . $hash->{HTTPCookies};
  }

  HttpUtils_NonblockingGet($apiParam);
}

sub ZoneMinder_API_ReadHostInfo_Callback {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if($err ne "") {
    Log3 $name, 0, "error while requesting ".$param->{url}." - $err";
    $hash->{ZM_VERSION} = 'error';
    $hash->{ZM_API_VERSION} = 'error';
  } elsif($data ne "") {
      
      my $zmVersion = ZoneMinder_GetConfigValueByKey($hash, $data, 'version');
      if (not $zmVersion) {
        $zmVersion = 'unknown';
      }
      $hash->{ZM_VERSION} = $zmVersion;

      my $zmApiVersion = ZoneMinder_GetConfigValueByKey($hash, $data, 'apiversion');
      if (not $zmApiVersion) {
        $zmApiVersion = 'unknown';
      }
      $hash->{ZM_API_VERSION} = $zmApiVersion;
  }

  return undef;
}

sub ZoneMinder_API_ReadHostLoad_Callback {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if($err ne "") {
    Log3 $name, 0, "error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash, 'CPU_Load', 'error', 0);
  } elsif($data ne "") {
    my $load = ZoneMinder_GetConfigArrayByKey($hash, $data, 'load');
    readingsSingleUpdate($hash, 'CPU_Load', $load, 1);

    InternalTimer(gettimeofday() + 60, "ZoneMinder_API_getLoad", $hash);
  }

  return undef;
}

#this extracts ZM_PATH_ZMS and ZM_AUTH_HASH_SECRET from the ZoneMinder config
sub ZoneMinder_API_ReadConfig_Callback {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if($err ne "") {
    Log3 $name, 0, "error while requesting ".$param->{url}." - $err";
  } elsif($data ne "") {
      my $zmPathZms = ZoneMinder_GetConfigValueByName($hash, $data, 'ZM_PATH_ZMS');
      if ($zmPathZms) {
        $zmPathZms =~ s/\\//g;
        $hash->{helper}{ZM_PATH_ZMS} = $zmPathZms;
      }

      my $authHashSecret = ZoneMinder_GetConfigValueByName($hash, $data, 'ZM_AUTH_HASH_SECRET');
      if ($authHashSecret) {
        $hash->{helper}{ZM_AUTH_HASH_SECRET} = $authHashSecret;
        ZoneMinder_calcAuthHash($hash);
      }
  }

  return undef;
}

sub ZoneMinder_GetConfigValueByKey {
  my ($hash, $config, $key) = @_;
  my $searchString = '"'.$key.'":"';
  return ZoneMinder_GetFromJson($hash, $config, $searchString, '"');
}

sub ZoneMinder_GetConfigArrayByKey {
  my ($hash, $config, $key) = @_;
  my $searchString = '"'.$key.'":[';
  return ZoneMinder_GetFromJson($hash, $config, $searchString, ']');
}

sub ZoneMinder_GetConfigValueByName {
  my ($hash, $config, $key) = @_;
  my $searchString = '"Name":"'.$key.'","Value":"';
  return ZoneMinder_GetFromJson($hash, $config, $searchString, '"');
}

sub ZoneMinder_GetFromJson {
  my ($hash, $config, $searchString, $endChar) = @_;
  my $name = $hash->{NAME};

#  Log3 $name, 5, "json: $config";
  my $searchLength = length($searchString);
  my $startIdx = index($config, $searchString);
  Log3 $name, 5, "$searchString found at $startIdx";
  $startIdx += $searchLength;
  my $endIdx = index($config, $endChar, $startIdx);
  my $frame = $endIdx - $startIdx;
  my $searchResult = substr $config, $startIdx, $frame;

  Log3 $name, 5, "looking for $searchString - length: $searchLength. start: $startIdx. end: $endIdx. result: $searchResult";
  
  return $searchResult;
}

sub ZoneMinder_API_UpdateMonitors_Callback {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  my @monitors = split(/\{"Monitor"\:\{/, $data);

  foreach my $monitorData (@monitors) {
    my $monitorId = ZoneMinder_GetConfigValueByKey($hash, $monitorData, 'Id');

    if ( $monitorId =~ /^[0-9]+$/ ) {
      ZoneMinder_UpdateMonitorAttributes($hash, $monitorData, $monitorId);
    } else {
      Log3 $name, 0, "Invalid monitorId: $monitorId" unless ('itors' eq $monitorId);
    }
  }

  return undef;
}

sub ZoneMinder_UpdateMonitorAttributes {
  my ( $hash, $monitorData, $monitorId ) = @_;

  my $function = ZoneMinder_GetConfigValueByKey($hash, $monitorData, 'Function');
  my $enabled = ZoneMinder_GetConfigValueByKey($hash, $monitorData, 'Enabled');
  my $streamReplayBuffer = ZoneMinder_GetConfigValueByKey($hash, $monitorData, 'StreamReplayBuffer');

  my $msg = "monitor:$monitorId|$function|$enabled|$streamReplayBuffer";
  
  my $dispatchResult = Dispatch($hash, $msg, undef);
}

sub ZoneMinder_API_CreateMonitors_Callback {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  my @monitors = split(/\{"Monitor"\:\{/, $data);

  foreach my $monitorData (@monitors) {
    my $monitorId = ZoneMinder_GetConfigValueByKey($hash, $monitorData, 'Id');

    if ( $monitorId =~ /^[0-9]+$/ ) {
      my $dispatchResult = Dispatch($hash, "createMonitor:$monitorId", undef);
    }
  }
  my $zmApiUrl = ZoneMinder_getZmApiUrl($hash);
  ZoneMinder_SimpleGet($hash, "$zmApiUrl/monitors.json", \&ZoneMinder_API_UpdateMonitors_Callback);

  return undef;
}

sub ZoneMinder_GetCookies {
    my ($hash, $header) = @_;
    my $name = $hash->{NAME};
    foreach my $cookie ($header =~ m/set-cookie: ?(.*)/gi) {
        $cookie =~ /([^,; ]+)=([^,; ]+)[;, ]*(.*)/;
        $hash->{HTTPCookieHash}{$1}{Value} = $2;
        $hash->{HTTPCookieHash}{$1}{Options} = ($3 ? $3 : "");
    }
    $hash->{HTTPCookies} = join ("; ", map ($_ . "=".$hash->{HTTPCookieHash}{$_}{Value},
                                        sort keys %{$hash->{HTTPCookieHash}}));
}

sub ZoneMinder_Write {
  my ( $hash, $arguments) = @_;
  my $method = $arguments->{method};

  if ($method eq 'changeMonitorFunction') {

    my $zmMonitorId = $arguments->{zmMonitorId};
    my $zmFunction = $arguments->{zmFunction};
    Log3 $hash->{NAME}, 4, "method: $method, monitorId:$zmMonitorId, Function:$zmFunction";
    return ZoneMinder_API_ChangeMonitorState($hash, $zmMonitorId, $zmFunction, undef);

  } elsif ($method eq 'changeMonitorEnabled') {

    my $zmMonitorId = $arguments->{zmMonitorId};
    my $zmEnabled = $arguments->{zmEnabled};
    Log3 $hash->{NAME}, 4, "method: $method, monitorId:$zmMonitorId, Enabled:$zmEnabled";
    return ZoneMinder_API_ChangeMonitorState($hash, $zmMonitorId, undef, $zmEnabled);

  } elsif ($method eq 'changeMonitorAlarm') {

    my $zmMonitorId = $arguments->{zmMonitorId};
    my $zmAlarm = $arguments->{zmAlarm};
    Log3 $hash->{NAME}, 4, "method: $method, monitorId:$zmMonitorId, Alarm:$zmAlarm";
    return ZoneMinder_Trigger_ChangeAlarmState($hash, $zmMonitorId, $zmAlarm);

  } elsif ($method eq 'changeMonitorText') {

    my $zmMonitorId = $arguments->{zmMonitorId};
    my $zmText = $arguments->{text};
    Log3 $hash->{NAME}, 4, "method: $method, monitorId:$zmMonitorId, Text:$zmText";
    return ZoneMinder_Trigger_ChangeText($hash, $zmMonitorId, $zmText);

  }

  return undef;
}

sub ZoneMinder_API_ChangeMonitorState {
  my ( $hash, $zmMonitorId, $zmFunction, $zmEnabled ) = @_;
  my $name = $hash->{NAME};

  my $zmApiUrl = ZoneMinder_getZmApiUrl($hash);
  my $apiParam = {
    url => "$zmApiUrl/monitors/$zmMonitorId.json",
    method => "POST",
    callback => \&ZoneMinder_API_ChangeMonitorState_Callback,
    hash => $hash,
    zmMonitorId => $zmMonitorId,
    zmFunction => $zmFunction,
    zmEnabled => $zmEnabled
  };

  if ( $zmFunction ) {
    $apiParam->{data} = "Monitor[Function]=$zmFunction";
  } elsif ( $zmEnabled || $zmEnabled eq '0' ) {
    $apiParam->{data} = "Monitor[Enabled]=$zmEnabled";
  }

  if ($hash->{HTTPCookies}) {
    $apiParam->{header} .= "\r\n" if ($apiParam->{header});
    $apiParam->{header} .= "Cookie: " . $hash->{HTTPCookies};
  }

  HttpUtils_NonblockingGet($apiParam);

  return undef;
}

sub ZoneMinder_API_ChangeMonitorState_Callback {
  my ($param, $err, $data) = @_;  
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($data) {
    my $monitorId = $param->{zmMonitorId};
    my $logDevHash = $modules{ZM_Monitor}{defptr}{$name.'_'.$monitorId};
    my $function = $param->{zmFunction};
    my $enabled = $param->{zmEnabled};
    Log3 $name, 4, "ZM_Monitor ($name) - ChangeMonitorState callback data: $data, enabled: $enabled";

    if ($function) {
      readingsSingleUpdate($logDevHash, 'monitorFunction', $function, 1);
    } elsif ($enabled || $enabled eq '0') {
      readingsSingleUpdate($logDevHash, 'motionDetectionEnabled', $enabled, 1);
    }

  } else {
    Log3 $name, 2, "ZoneMinder ($name) - ChangeMonitorState callback err: $err";
  }
  
  return undef;
}

sub ZoneMinder_Trigger_ChangeAlarmState {
  my ( $hash, $zmMonitorId, $zmAlarm ) = @_;
  my $name = $hash->{NAME};

  my $msg = "$zmMonitorId|";
  if ( 'on' eq $zmAlarm ) {
    DevIo_SimpleWrite( $hash, $msg.'on|1|fhem', 2 );
  } elsif ( 'off' eq $zmAlarm ) {
    DevIo_SimpleWrite( $hash, $msg.'off|1|fhem', 2);
  } elsif ( $zmAlarm =~ /^on\-for\-timer/ ) {
    my $duration = $zmAlarm =~ s/on\-for\-timer\ /on\ /r;
    DevIo_SimpleWrite( $hash, $msg.$duration.'|1|fhem', 2);
  }

  return undef;
}

sub ZoneMinder_Trigger_ChangeText {
  my ( $hash, $zmMonitorId, $zmText ) = @_;
  my $name = $hash->{NAME};

  my $msg = "$zmMonitorId|show||||$zmText";
  Log3 $name, 4, "ZoneMinder ($name) - Change Text $msg";
  DevIo_SimpleWrite( $hash, $msg, 2 );

  return undef;
}

sub ZoneMinder_calcAuthHash {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "ZoneMinder ($name) - calling calcAuthHash";

  my ($sec,$min,$curHour,$dayOfMonth,$curMonth,$curYear,$wday,$yday,$isdst) = localtime();

  my $zmAuthHashSecret = $hash->{helper}{ZM_AUTH_HASH_SECRET};
  if (not $zmAuthHashSecret) {
    Log3 $name, 0, "ZoneMinder ($name) - calcAuthHash was called, but no hash secret was found. This shouldn't happen. Please contact the module maintainer.";
    return undef;
  }
  my $username = $hash->{helper}{ZM_USERNAME};
  my $password = $hash->{helper}{ZM_PASSWORD};
  my $hashedPassword = password41($password);

  my $authHash = $zmAuthHashSecret . $username . $hashedPassword . $curHour . $dayOfMonth . $curMonth . $curYear;
  my $authKey = md5_hex($authHash);
  
  readingsSingleUpdate($hash, 'authHash', $authKey, 1);
  InternalTimer(gettimeofday() + 3600, "ZoneMinder_calcAuthHash", $hash);

  return undef;
}

sub ZoneMinder_Shutdown {
  ZoneMinder_Undef(@_);
}  

sub ZoneMinder_Undef {
  my ($hash, $arg) = @_; 
  my $name = $hash->{NAME};

  DevIo_CloseDev($hash) if (DevIo_IsOpen($hash));
  RemoveInternalTimer($hash);

  return undef;
}

sub ZoneMinder_Read {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $data = DevIo_SimpleRead($hash);
  return if (!defined($data)); # connection lost

  my $buffer = $hash->{PARTIAL};
  $buffer .= $data;
  #as long as the buffer contains newlines
  while ($buffer =~ m/\n/) {
    my $msg;
    ($msg, $buffer) = split("\n", $buffer, 2);
    chomp $msg;
    $msg = "event:$msg";
#    Log3 $name, 3, "ZoneMinder ($name) incoming message $msg.";
    my $dispatchResult = Dispatch($hash, $msg, undef);
  }
  $hash->{PARTIAL} = $buffer;
}

sub ZoneMinder_DetailFn {
  my ( $FW_wname, $deviceName, $FW_room ) = @_;

  my $hash = $defs{$deviceName};

  my $zmWebUrl = ZoneMinder_getZmWebUrl($hash, 1);
  my $zmUsername = urlEncode($hash->{helper}{ZM_USERNAME});
  my $zmPassword = urlEncode($hash->{helper}{ZM_PASSWORD});
  my $zmConsoleUrl = "$zmWebUrl/index.php?username=$zmUsername&password=$zmPassword&action=login&view=console";

  if ($zmConsoleUrl) {
    return "<div><a href='$zmConsoleUrl' target='_blank'>Go to ZoneMinder console</a></div>";
  } else {
    return undef;
  }
}

sub ZoneMinder_Get {
  my ( $hash, $name, $opt, $args ) = @_;

  my $zmApiUrl = ZoneMinder_getZmApiUrl($hash);
  if ("autocreateMonitors" eq $opt) {
    ZoneMinder_SimpleGet($hash, "$zmApiUrl/monitors.json", \&ZoneMinder_API_CreateMonitors_Callback);
    return undef;
  } elsif ("updateMonitorConfig" eq $opt) {
    ZoneMinder_SimpleGet($hash, "$zmApiUrl/monitors.json", \&ZoneMinder_API_UpdateMonitors_Callback);
    return undef;
  } elsif ("calcAuthHash" eq $opt) {
    ZoneMinder_calcAuthHash($hash);
    return undef;
  }

#  Log3 $name, 3, "ZoneMinder ($name) - Get done ...";
  return "Unknown argument $opt, choose one of autocreateMonitors updateMonitorConfig calcAuthHash";
}

sub ZoneMinder_Set {
  my ( $hash, $param ) = @_;

  my $name = $hash->{NAME};
#  Log3 $name, 3, "ZoneMinder ($name) - Set done ...";
  return undef;
}

sub ZoneMinder_Ready {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};

  if ( $hash->{STATE} eq "disconnected" ) {
    my $err = DevIo_OpenDev($hash, 1, undef ); #if success, $err is undef
    if (not $err) {
      Log3 $name, 3, "ZoneMinder ($name) - reconnect to ZoneMinder successful";
      return 1;
    } else {
      Log3 $name, 0, "ZoneMinder ($name) - reconnect to ZoneMinder failed: $err";
      return $err;
    }
  }

  # This is relevant for Windows/USB only
  if(defined($hash->{USBDev})) {
    my $po = $hash->{USBDev};
    my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
    return ( $InBytes > 0 );
  }
}

1;


# Beginn der Commandref

=pod
=item device
=item summary Maintain ZoneMinder events and monitor operation modes in FHEM
=item summary_DE ZoneMinder events und Monitor Konfiguration in FHEM warten

=begin html

<a name="ZoneMinder"></a>
<h3>ZoneMinder</h3>

<a name="ZoneMinderdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ZoneMinder  &lt;ZM-Host&gt; [&lt;username&gt; &lt;password&gt;]</code>
    <br><br>
    Defines a ZoneMinder device at the given host address. This allows you to exchange events between ZoneMinder and FHEM.
    Also providing <code>username</code> and <code>password</code> provides access to ZoneMinder API and more functionality.
    <br>
    Example:
    <ul>
      <code>define zm ZoneMinder 10.0.0.100</code><br>
      <code>define zm ZoneMinder 10.0.0.100 fhemApiUser fhemApiPass</code>
    </ul>
    <br>
  </ul>
  <br><br>

  <a name="ZoneMinderget"></a>
  <b>Get</b>
  <ul>
    <li><code>autocreateMonitors</code><br>Queries the ZoneMinder API and autocreates all ZM_Monitor devices that belong to that installation.
    </li>
    <li><code>updateMonitorConfig</code><br>Queries the ZoneMinder API and updates the Readings of ZM_Monitor devices (monitorFunction, motionDetectionEnabled, ...)
    </li>
    <li><code>calcAuthHash</code><br>Calculates a fresh auth hash. Please note that the hash only changes with every full hour. So, calling this doesn't necessarily change any Readings, depending on the age of the current hash.
    </li>
  </ul>

  <br><br>
  <a name="ZoneMinderattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>publicAddress &lt;address&gt;</code><br>This configures public accessibility of your LAN (eg your ddns address). Define a valid URL here, eg <code>https://my.own.domain:2344</code></li>
    <li><code>webConsoleContext &lt;path&gt;</code><br>If not set, this defaults to <code>/zm</code>. This is used for building the URL to the ZoneMinder web console.</li> 
  </ul>

  <br><br>
  
  <a name="ZoneMinderreadings"></a>
  <b>Readings</b>
  <br><br>
  <ul>
    <li>CPU_Load<br/>The CPU load of the ZoneMinder host. Provides 1, 5 and 15 minutes interval.</li>
    <li>authHash<br/>The auth hash that allows access to Stream URLs without requiring username or password.</li>
    <li>state<br/>The current connection state to the ZoneMinder Trigger Port (6802 per default)</li>
  </ul>
  

=end html

# Ende der Commandref
=cut

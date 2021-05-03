# $Id$

package main;

use strict;
use warnings;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::SSL;
use HTTP::Request;
use HTTP::Cookies;
use LWP::UserAgent;
use MIME::Base64;
use HttpUtils;
use JSON;
  
my $MODULE='Arlo';

sub Arlo_Initialize($$) {
  my ($hash) = @_;
  $hash->{DefFn}    = "Arlo_Define";
  $hash->{UndefFn}  = "Arlo_Undef";
  $hash->{GetFn}    = "Arlo_Get";
  $hash->{SetFn}    = "Arlo_Set";
  $hash->{AttrList} = "disable:1 expiryTime pingInterval updateInterval downloadDir downloadLink mailServer ssePollingInterval videoDownloadFix:0,1 ".$readingFnAttributes;  
  $hash->{AttrFn}   = "Arlo_Attr";
}

sub Arlo_Define($$) {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $subtype = $a[2];
  if ($subtype eq 'ACCOUNT' && @a >= 5) {
    my $user = Arlo_decrypt($a[3]);
    my $passwd = Arlo_decrypt($a[4]);
    my $mailPasswd = '';
    $hash->{helper}{username} = $user;
    $hash->{helper}{password} = $passwd;
    if (@a > 5) {
       $mailPasswd = Arlo_decrypt($a[5]);
       $hash->{helper}{mailPassword} = $mailPasswd;
    }
    my $mailUser = '';
    if (@a > 6) {
       $mailUser = $a[6];
       $hash->{helper}{mailUser} = $mailUser;
    } else {
       $hash->{helper}{mailUser} = $user;
    }
    $modules{$MODULE}{defptr}{"account"} = $hash;
    
    my $cryptUser = Arlo_encrypt($user);
    my $cryptPasswd = Arlo_encrypt($passwd);
    my $cryptMailPasswd = Arlo_encrypt($mailPasswd);
    $hash->{DEF} = "ACCOUNT $cryptUser $cryptPasswd $cryptMailPasswd $mailUser";
    InternalTimer(gettimeofday() + 3, "Arlo_Login", $hash);

  } elsif (($subtype eq 'BASESTATION' || $subtype eq 'ROUTER') && @a == 5) {
    my $serialNumber = $a[3];
    my $xCloudId = $a[4];
    my $d = $modules{$MODULE}{defptr}{"B$serialNumber"};
    return "basestation $serialNumber already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    Arlo_InitDevice($hash, 'B', $serialNumber, $xCloudId);
    InternalTimer(gettimeofday() + 5, "Arlo_Subscribe", $hash);

  } elsif ($subtype eq 'BRIDGE' && @a == 5) {
    my $serialNumber = $a[3];
    my $xCloudId = $a[4];
    my $d = $modules{$MODULE}{defptr}{"B$serialNumber"};
    return "bridge $serialNumber already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    Arlo_InitDevice($hash, 'B', $serialNumber, $xCloudId);

  } elsif ($subtype eq 'BABYCAM' && @a == 5) {  # ArloQ = Kamera mit integrierter Basestation
    my $serialNumber = $a[3];
    my $xCloudId = $a[4];
    my $d = $modules{$MODULE}{defptr}{"B$serialNumber"};
    return "BabyCam $serialNumber already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    Arlo_InitDevice($hash, 'B', $serialNumber, $xCloudId);
    Arlo_InitDevice($hash, 'C', $serialNumber, $xCloudId, $serialNumber);
    InternalTimer(gettimeofday() + 5, "Arlo_Subscribe", $hash);

  } elsif ($subtype eq 'CAMERA' && @a == 6) {
    my $basestationSerialNumber = $a[3];
    my $serialNumber = $a[4];
    my $xCloudId = $a[5];
    my $d = $modules{$MODULE}{defptr}{"C$serialNumber"};
    return "camera $serialNumber already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    Arlo_InitDevice($hash, 'C', $serialNumber, $xCloudId, $basestationSerialNumber);

  } elsif ($subtype eq 'ARLOQ' && @a == 5) {  # ArloQ = Kamera mit integrierter Basestation
    my $serialNumber = $a[3];
    my $xCloudId = $a[4];
    my $d = $modules{$MODULE}{defptr}{"B$serialNumber"};
    return "ArloQ $serialNumber already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    Arlo_InitDevice($hash, 'B', $serialNumber, $xCloudId);
    Arlo_InitDevice($hash, 'C', $serialNumber, $xCloudId, $serialNumber);
    InternalTimer(gettimeofday() + 5, "Arlo_Subscribe", $hash);
    
  } elsif ($subtype eq 'LIGHT' && @a == 6) {
    my $basestationSerialNumber = $a[3];
    my $serialNumber = $a[4];
    my $xCloudId = $a[5];
    my $d = $modules{$MODULE}{defptr}{"L$serialNumber"};
    return "Arlo light $serialNumber already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    Arlo_InitDevice($hash, 'L', $serialNumber, $xCloudId, $basestationSerialNumber);

  } else {
    return "Usage: define <name> Arlo ACCOUNT username password\
       define <name> Arlo BASESTATION deviceName serialNumber xCloudId\
       define <name> Arlo CAMERA basestationSerialNumber deviceName serialNumber xCloudId";
  }
  
  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;
  $hash->{STATE} = 'initialized';

  $attr{$name}{room} = "Arlo";
  
  return undef;
}

sub Arlo_InitDevice($$$$;$) {
  my ($hash, $prefix, $serialNumber, $xCloudId, $basestationSerialNumber) = @_;
  if (defined($basestationSerialNumber)) {
    my $basestation = $modules{$MODULE}{defptr}{"B$basestationSerialNumber"};
    $hash->{BASESTATION} = $basestation;
    $hash->{basestationSerialNumber} = $basestationSerialNumber;
  }
  $hash->{serialNumber} = $serialNumber;
  $hash->{xCloudId} = $xCloudId;
  $modules{$MODULE}{defptr}{"$prefix$serialNumber"} = $hash;
}

sub Arlo_Undef($$) {
  my ($hash, $arg) = @_;
  my $subtype = $hash->{SUBTYPE};
  delete($modules{$MODULE}{defptr}{"L$hash->{serialNumber}"}) if ($subtype eq 'LIGHT');
  delete($modules{$MODULE}{defptr}{"C$hash->{serialNumber}"}) if ($subtype eq 'CAMERA' || $subtype eq 'ARLOQ' || $subtype eq 'BABYCAM');
  delete($modules{$MODULE}{defptr}{"B$hash->{serialNumber}"}) if ($subtype eq 'BASESTATION' || $subtype eq 'BRIDGE' || $subtype eq 'ROUTER' || $subtype eq 'ARLOQ' || $subtype eq 'BABYCAM');
  if ($subtype eq 'ACCOUNT') {
    delete($modules{$MODULE}{defptr}{'account'});
    Arlo_Logout($hash);
  }
  RemoveInternalTimer($hash);
  return undef;
}

sub Arlo_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  return undef if (!defined($hash));

  if ($hash->{SUBTYPE} eq 'ACCOUNT') {
    if ($attrName eq 'disable') {
      RemoveInternalTimer($hash);
      if ($cmd eq 'del') {
        InternalTimer(gettimeofday() + 1, "Arlo_Login", $hash);
      } else {
        Arlo_Logout($hash);
        $hash->{STATE} = 'disabled';
      }
    }
  }

  return undef;
}

sub Arlo_Set($) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name = shift @a;
  my $opt = shift @a;
  my $value = join(' ', @a);
  my $subtype = $hash->{SUBTYPE};

  if ($subtype eq 'ACCOUNT') {
    if ($opt eq 'autocreate') {
 	    Arlo_CreateDevices($hash);
    } elsif ($opt eq 'reconnect') {
 	    Arlo_Login($hash);
    } elsif ($opt eq 'readModes') {
 	    Arlo_ReadModes($hash);
    } elsif ($opt eq 'updateReadings') {
      Arlo_UpdateReadings($hash);
    } else {
      return "Unknown argument $opt, choose one of autocreate:noArg readModes:noArg reconnect:noArg updateReadings:noArg ";
    }
  } elsif ($subtype eq 'BASESTATION' || $subtype eq 'ROUTER') {
    if (!Arlo_SetBasestationCmd($hash, $opt, $value)) {
      return "Unknown argument $opt, choose one of arm:noArg disarm:noArg mode subscribe:noArg unsubscribe:noArg siren:on,off";
    }
  } elsif ($subtype eq 'BRIDGE') {
    if (!Arlo_SetBasestationCmd($hash, $opt, $value)) {
      return "Unknown argument $opt, choose one of arm:noArg disarm:noArg mode";
    }
  } elsif ($subtype eq 'LIGHT') {
    if ($opt eq 'on') {
      Arlo_SetLightState($hash, 'on');
    } elsif ($opt eq 'off') {
      Arlo_SetLightState($hash, 'off');
    } else {
      return "Unknown argument $opt, choose one of on:noArg off:noArg";
    }
  } elsif ($subtype eq 'ARLOQ') {
    if (!Arlo_SetBasestationCmd($hash, $opt, $value)) {
      if (!Arlo_SetCameraCmd($hash, $opt, $value)) {
        return "Unknown argument $opt, choose one of arm:noArg disarm:noArg subscribe:noArg unsubscribe:noArg snapshot:noArg startRecording:noArg stopRecording:noArg brightness:-2,-1,0,1,2";
      }
    }
  } elsif ($subtype eq 'BABYCAM') {
    if (!Arlo_SetBasestationCmd($hash, $opt, $value)) {
      if (!Arlo_SetCameraCmd($hash, $opt, $value)) {
        return "Unknown argument $opt, choose one of arm:noArg disarm:noArg subscribe:noArg unsubscribe:noArg nightlight:on,off nightlight-brightness nightlight-color snapshot:noArg startRecording:noArg stopRecording:noArg brightness:-2,-1,0,1,2";
      }
    }
  } else {
     if (!Arlo_SetCameraCmd($hash, $opt, $value)) {
        return "Unknown argument $opt, choose one of on:noArg off:noArg snapshot:noArg startRecording:noArg stopRecording:noArg brightness:-2,-1,0,1,2 downloadLastVideo:noArg";
	  }
  }
  
  return undef;  
}

sub Arlo_SetBasestationCmd($$$) {
  my ($hash, $opt, $value) = @_;
  if ($opt eq 'mode') {
    Arlo_SetBasestationMode($hash, $value);
  } elsif ($opt eq 'siren') {
    Arlo_SetBasestationSiren($hash, $value);
  } elsif ($opt eq 'arm') {
    Arlo_BasestationArm($hash);
  } elsif ($opt eq 'disarm') {
    Arlo_BasestationDisarm($hash);
  } elsif ($opt eq 'subscribe') {
    Arlo_Subscribe($hash);
  } elsif ($opt eq 'unsubscribe') {
    Arlo_Unsubscribe($hash);
  } else {
    return undef;
  }
  return 1;
}

sub Arlo_SetCameraCmd($$$) {
  my ($hash, $opt, $value) = @_;
 	if ($opt eq 'on' || $opt eq 'off') {
    Arlo_ToggleCamera($hash, $opt);
  } elsif ($opt eq 'snapshot') {
    Arlo_Snapshot($hash);
  } elsif ($opt eq 'startRecording') {
    Arlo_StartRecording($hash);
  } elsif ($opt eq 'stopRecording') {
    Arlo_CameraAction($hash, 'stopRecord');
  } elsif ($opt eq 'brightness') {
    Arlo_SetBrightness($hash, $value);
  } elsif ($opt eq 'nightlight') {
    Arlo_SetNightLight($hash, $value);
  } elsif ($opt eq 'nightlight-brightness') {
    Arlo_SetNightLightBrightness($hash, $value);
  } elsif ($opt eq 'nightlight-color') {
    Arlo_SetNightLightColor($hash, $value);
  } elsif ($opt eq 'downloadLastVideo') {
    Arlo_DownloadLastVideo($hash);
  } else {
    return undef;
  }
  return 1;
}

sub Arlo_Get($) {
  my ($hash, @a)	= @_;
  my $subtype = $hash->{SUBTYPE};
  my $cmd = $a[1];
  return "Unknown argument $cmd, choose one of" if ($subtype ne 'CAMERA');

  my $date = $a[2];
  return "Unknown argument $cmd, choose one of recordings" if ($cmd ne "recordings");
  return "Paramter date (format YYYYMMDD) needed." if (!defined($date) || length($date) != 8);
  my @result = Arlo_GetRecordings($hash, $date);
  return encode_json(\@result);
}

sub Arlo_Poll($) {
  my ($hash) = @_;
  return undef if (AttrVal($hash->{NAME}, 'disable', 0) eq '1' || $hash->{SUBTYPE} ne 'ACCOUNT');
  my $delay = AttrVal($hash->{NAME}, 'updateInterval', 3600); 
  eval {
    Arlo_UpdateReadings($hash);
  };
  if ($@) {
    Log3 $hash->{NAME}, 2, "Error while update Arlo readings. Try again in $delay seconds.";
  } else {
    Log3 $hash->{NAME}, 3, "Updated Arlo readings. Next automatic update in $delay seconds.";
  }
  InternalTimer(gettimeofday() + $delay, 'Arlo_Poll', $hash);
}

sub Arlo_GetBasestations($) {
  my ($hash) = @_;
  my @devices = ();
  foreach my $key (keys %{$modules{$MODULE}{defptr}}) {
    if (substr($key, 0, 1) eq 'B') {
      my $serialNumber = substr($key, 1);
      my $device = $modules{$MODULE}{defptr}{"B$serialNumber"};
      push @devices, $serialNumber;
    }
  }
  return @devices;
}

sub Arlo_Ping($) {
  my ($hash) = @_;
  my $delay = AttrVal($hash->{NAME}, 'pingInterval', 90);
  Log3 $hash->{NAME}, 5, "Arlo Ping: $hash->{NAME} $hash->{SUBTYPE} $delay";
  return undef if (AttrVal($hash->{NAME}, 'disable', 0) eq '1' || $hash->{SUBTYPE} ne 'ACCOUNT');
  if ($hash->{SSE_STATUS} == 200) {
    Arlo_SubscribeAll($hash);
  }
  InternalTimer(gettimeofday() + $delay, 'Arlo_Ping', $hash);
}

sub Arlo_SetReading($$$$) {
  my ($hash, $serialNumber, $name, $value) = @_;
  if (defined($value)) {
    my $device = $modules{$MODULE}{defptr}{"C$serialNumber"};
    $device = $modules{$MODULE}{defptr}{"B$serialNumber"} if (!defined($device));
    $device = $modules{$MODULE}{defptr}{"L$serialNumber"} if (!defined($device));
    if (defined($device)) {
      readingsSingleUpdate($device, $name, $value, 1);
      if (($name eq 'state' or $name eq 'activityState') and ReadingsVal($device->{NAME}, 'error', '') ne '') {
        fhem("deletereading $device->{NAME} error");
      }
      if ($name eq 'activityState' and $value eq 'idle' and defined($device->{streamURL})) {
        delete $device->{streamURL};
      }
    }
  }
}

sub Arlo_SetReadingAndDownload($$$$$$) {
  my ($hash, $reading, $url, $cameraId, $fileSuffix, $recording) = @_;
  my $name = $hash->{NAME};
  if (defined($url)) {
    my $downloadDir = AttrVal($name, 'downloadDir', '');
    my $downloadLink = AttrVal($name, 'downloadLink', '');
    if ($downloadDir ne '') {
      my $ua = LWP::UserAgent->new();
      my $fileName = $downloadDir.'/'.$cameraId.$fileSuffix;
      if (!open(FH, ">$fileName")) {
        Log3 $name, 1, "Arlo can't write file $fileName!";
        return;
      }
      my $response = $ua->get($url, ':content_cb' => \&Arlo_WriteResponseToFile, ':read_size_hint' => 65536);
      close(FH);
    } 
    if ($downloadLink ne '' && $downloadDir ne '') {
      Arlo_SetReading($hash, $cameraId, $reading, $downloadLink.'/'.$cameraId.$fileSuffix);
    } else {
      Arlo_SetReading($hash, $cameraId, $reading, $url);
    }
  }
}

sub Arlo_WriteResponseToFile($$) {
  my($data, $response) = @_;
  print FH $data;
}

sub Arlo_Camera_Readings($$$$$$) {
  my ($hash, $serialNumber, $state, $batteryLevel, $signalStrength, $brightness) = @_;
  Log3 $hash->{NAME}, 5, "Update readings for Arlo Device $serialNumber: state=$state batteryLevel=$batteryLevel";
  my $cam = $modules{$MODULE}{defptr}{"C$serialNumber"};
  if (defined($cam)) {
    readingsBeginUpdate($cam);
    readingsBulkUpdate($cam, 'batteryLevel', $batteryLevel * 1); 
    readingsBulkUpdate($cam, 'brightness', $brightness);
    readingsBulkUpdate($cam, 'signalStrength', $signalStrength * 1); 
    readingsBulkUpdate($cam, 'state', $state) if ($cam->{basestationSerialNumber} ne $cam->{serialNumber});
    readingsBulkUpdate($cam, 'error', '') if (ReadingsVal($cam->{NAME}, 'error', '') ne '');
    readingsEndUpdate($cam, 1);
    Log3 $hash->{NAME}, 5, "Update readings for device $cam->{NAME} finished.";
  }
}

sub Arlo_Event($$) {
  my ($hash, $args) = @_;
  my @a = split("[ \t][ \t]*", $args);
  my $serialNumber = shift @a;
  my $key = shift @a;
  my $value = shift @a;
  my $cam = $modules{$MODULE}{defptr}{"C$serialNumber"};
  readingsSingleUpdate($cam, $key, $value, 1);
}


#
# Schnittstelle zur Arlo-Cloud - Aktionen
#

sub Arlo_PrepareRequest($$;$$$$) {
  my ($hash, $url, $method, $body, $additionalHeader) = @_;
  $method = "GET" if (!defined($method));
  
  my $account = $modules{$MODULE}{defptr}{"account"};
  
  my $name = $account->{NAME};
  my $token = $account->{helper}{token};
  my $cookies = $account->{helper}{cookies};
  my $serviceHeaders;
  
  $url = 'https://myapi.arlo.com/hmsweb'.$url;
  
  my $headers = "Accept: application/json\r\nAuth-Version: 2\r\n";
  $headers = $headers."Authorization: $token\r\n" if (defined($token)); 
  $headers = $headers."Cookie: $cookies\r\n" if (defined($cookies)); 
  $headers = $headers."Content-Type: application/json; charset=utf-8\r\nOrigin: https://myapi.arlo.com\r\nReferer: https://myapi.arlo.com\r\nschemaVersion: 1\r\n";
  $headers = $headers."User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.96 Safari/537.36";
  $headers = $headers."\r\n".$additionalHeader if (defined($additionalHeader));
  Log3 $name, 5, "Arlo header: $headers";
  
  Log3 $name, 4, "Arlo URL: $url";

  my $request = {url => $url, method => $method, header => $headers, keepalive => 1, httpversion => '1.1', loglevel => 4};
  
  if (defined($body)) {
    my $bodyJson = encode_json $body;
    Log3 $name, 5, "Arlo body: $bodyJson";
    $request->{data} = $bodyJson;
  }
  
  return $request;
}

sub Arlo_Request($$;$$$$$$) {
  my ($hash, $urlSuffix, $method, $body, $additionalHeader, $callback, $origin) = @_;
  my $request = Arlo_PrepareRequest($hash, $urlSuffix, $method, $body, $additionalHeader);

  if (defined($callback)) {
    $request->{callbackArlo} = $callback;
  } else {
    $request->{callbackArlo} = \&Arlo_DefaultCallback;
  }
  if (defined($origin)) {
    $request->{origin} = $origin;
  }

  # request für HttpUtils_NonblockingGet($request);
  my $err = HttpUtils_Connect($request);
  if ($err) {
    $request->{callbackArlo}($request, $err, '');
    return;
  }
  
  $request->{buf} = '';
  $request->{readCounter} = 0;
  delete($request->{httpdatalen});
  delete($request->{httpheader});
  InternalTimer(gettimeofday() + 0.5, 'Arlo_HttpRead', $request);
}

sub Arlo_HttpRead($) {
  my ($hash) = @_;

  if (!defined($hash->{conn})) {
    Log3 $hash, 3, "Arlo HTTP connection not defined, stop reading.";
    return;
  }

  my ($rout, $rin) = ('', '');
  vec($rin, $hash->{conn}->fileno(), 1) = 1;
  Log3 $hash, $hash->{loglevel}, "Read http response from $hash->{url}";
  my $nfound = select($rout=$rin, undef, undef, 0.1);
  while ($nfound > 0) {
    my $buf = '';
    my $len = sysread($hash->{conn}, $buf, 65536);
    if (!defined($len) || $len <= 0) {
      my ($err, $ret, $redirect) = HttpUtils_ParseAnswer($hash);
      $hash->{callbackArlo}($hash, $err, $ret);
      return;
    }
    $hash->{buf} = $hash->{buf} . $buf;
    $nfound = select($rout=$rin, undef, undef, 0.1);
  }
  
  if (HttpUtils_DataComplete($hash)) {
    Log3 $hash, $hash->{loglevel}, "Arlo read http DataComplete";
    my ($err, $ret, $redirect) = HttpUtils_ParseAnswer($hash);
    $hash->{callbackArlo}($hash, $err, $ret);
    return;
  } 
  
  my $counter = $hash->{readCounter};
  if ($counter < 8) {
    $hash->{readCounter} = $counter + 1;
    InternalTimer(gettimeofday() + 0.5, 'Arlo_HttpRead', $hash);
  } else {
    HttpUtils_Close($hash);
    $hash->{callbackArlo}($hash, "$hash->{addr} timed out", '');
  }
}

sub Arlo_RequestWithLogin($$;$$$$$$) {
  my ($hash, $urlSuffix, $method, $body, $additionalHeader, $callback, $origin) = @_;

  my $account = $modules{$MODULE}{defptr}{"account"};
  if ($account->{STATE} eq 'inactive') {
    if (defined($account->{helper}{followUpRequest})) {
      return 'Please wait until login is finished.';
    } 

    Arlo_Login($account);
    my $followUpRequest = {hash => $hash, urlSuffix => $urlSuffix, method => $method, body => $body, additionalHeader => $additionalHeader, callback => $callback, origin => $origin};
    $account->{helper}{followUpRequest} = $followUpRequest;
    return 'Action will be executed after login.';
  } 

  Arlo_Request($hash, $urlSuffix, $method, $body, $additionalHeader, $callback, $origin);
}

sub Arlo_BlockingRequest($$;$$$$) {
  my ($hash, $urlSuffix, $method, $body, $additionalHeader) = @_;
  my $request = Arlo_PrepareRequest($hash, $urlSuffix, $method, $body, $additionalHeader);
  return HttpUtils_BlockingGet($request);
}

sub Arlo_DefaultCallback($$$) {
  my ($hash, $err, $jsonData) = @_;
  my $account = $modules{$MODULE}{defptr}{"account"};
  my $name = $account->{NAME};
  if ($err) {
    Log3 $name, 2, "Error occured when calling Arlo daemon: $err";
    return undef;
  } elsif ($jsonData) {
    my $response;
    eval {
      $response = decode_json $jsonData;
      if ($response->{success}) {
        Arlo_SetCookies($account, $hash->{httpheader});
        Log3 $name, 5, "Response from Arlo: $jsonData";
      } else {
	      my $logLevel = 2;
        if ($response->{data}) {
	        my $data = $response->{data};
		      my $origin = $hash->{origin};
		      if ($origin && $data->{error} eq '2059' && $data->{reason} eq 'Device is offline.') {
            readingsSingleUpdate($origin, 'state', 'offline', 1) if (ReadingsVal($origin->{NAME}, 'state', '') ne 'offline');
			      $logLevel = 5;
		      } elsif ($data->{error} eq '1022' && $data->{reason} eq 'Access token is invalid') {
  			    Log3 $name, 3, "Arlo access token was invalid. Reconnect to Arlo.";
	  		    if ($account->{STATE} eq 'active') {
              Arlo_Login($account);
            }
			      $logLevel = 5;
		      }
		    } 
        Log3 $name, $logLevel, "Arlo call was not successful: $jsonData";
        $response = undef;
      }
    };
    if ($@) {
      Log3 $name, 3, 'Invalid Arlo callback response: '.$jsonData;
    }
    return $response;
  } else {
    Log3 $name, 2, 'Arlo callback response code '.$hash->{code};
    Log3 $name, 4, 'Arlo callback response header '.$hash->{header};
  }
}

sub Arlo_SetCookies($$) {
  my ($hash, $httpHeader) = @_;

  my %cookies;
  if (defined($hash->{helper}{cookies})) {
    foreach my $cookie (split("; ", $hash->{helper}{cookies})) {
      my($key, $val) = split(/=/, $cookie, 2);
      $cookies{$key} = $val;
    }
  }

  if (defined($httpHeader)) {
    my @header = split("\n", $httpHeader);
    foreach my $line (@header) {
      if ($line =~ m/^Set-Cookie: ([^;]+)/g) {
        my($key, $val) = split(/=/, $1, 2);
        $cookies{$key} = $val;
      }
    }
  }

  $hash->{helper}{cookies} = join('; ', map { "$_=$cookies{$_}" } keys %cookies);
}


sub Arlo_CreateDevices($) {
  my ($hash) = @_;
  Arlo_RequestWithLogin($hash, '/users/devices', 'GET', undef, undef, \&Arlo_CreateDevicesCallback);
}

sub Arlo_CreateDevice($$$$$$$;$) {
  my ($hash, $deviceType, $prefix, $deviceName, $serialNumber, $xCloudId, $model, $basestationSerialNumber) = @_;
  my $d = $modules{$MODULE}{defptr}{"$prefix$serialNumber"};
  if (!defined($d)) {
    if (defined($basestationSerialNumber)) {
      CommandDefine(undef, "Arlo_$deviceName Arlo $deviceType $basestationSerialNumber $serialNumber $xCloudId");
    } else {
      CommandDefine(undef, "Arlo_$deviceName Arlo $deviceType $serialNumber $xCloudId");
    }
    $d = $modules{$MODULE}{defptr}{"$prefix$serialNumber"};
  }
  readingsSingleUpdate($d, 'model', $model, 0) if (defined($d));
}

sub Arlo_GetNameWithoutUmlaut($) {
  my ($string) = @_;
  my %umlaute = ('ä' => 'ae', 'Ä' => 'Ae', 'ü' => 'ue', 'Ü' => 'Ue', 'ö' => 'oe', 'Ö' => 'Oe', 'ß' => 'ss', ' ' => '_' );
  my $umlautkeys = join ('|', keys(%umlaute));
  $string =~ s/($umlautkeys)/$umlaute{$1}/g;
  return $string;
}

sub Arlo_CreateDevicesCallback($$$)  {
  my ($hash, $err, $jsonData) = @_;
  my $response = Arlo_DefaultCallback($hash, $err, $jsonData);
  if (defined($response)) {
    my @data = @{$response->{data}};
    foreach my $device (@data) {
      my $serialNumber = $device->{deviceId};
      my $deviceName = $device->{deviceName};
      $deviceName = Arlo_GetNameWithoutUmlaut($deviceName);
      my $deviceType = $device->{deviceType};
      my $xCloudId = $device->{xCloudId};
	  my $model = $device->{modelId};
      Log3 $hash->{NAME}, 3, "Found device $deviceType with name $deviceName.";
      if ($deviceType eq 'basestation') {
        Arlo_CreateDevice($hash, 'BASESTATION', 'B', $deviceName, $serialNumber, $xCloudId, $model);
      } elsif ($deviceType eq 'routerM1') {
        Arlo_CreateDevice($hash, 'ROUTER', 'B', $deviceName, $serialNumber, $xCloudId, $model);
      } elsif ($deviceType eq 'arlobridge') {
        Arlo_CreateDevice($hash, 'BRIDGE', 'B', $deviceName, $serialNumber, $xCloudId, $model);
      } elsif ($deviceType eq 'camera') {
        my $parentId = $device->{parentId};
        if ($serialNumber ne $parentId) {
          Arlo_CreateDevice($hash, 'CAMERA', 'C', $deviceName, $serialNumber, $xCloudId, $model, $parentId);
        } else {
          Arlo_CreateDevice($hash, 'BABYCAM', 'B', $deviceName, $serialNumber, $xCloudId, $model);
        }
      } elsif ($deviceType eq 'arloq') {
        Arlo_CreateDevice($hash, 'ARLOQ', 'B', $deviceName, $serialNumber, $xCloudId, $model);
      } elsif ($deviceType eq 'lights') {
        Arlo_CreateDevice($hash, 'LIGHT', 'L', $deviceName, $serialNumber, $xCloudId, $model, $device->{parentId});
      }
    }
  }
}


sub Arlo_GenTransId() {
   my $now = int(gettimeofday() * 1000);
   my $random = unpack 'H*', pack 'd', rand(300000) * exp(32); 
   my $transId = 'web!'.$random."!".$now;
   return $transId
}   


sub Arlo_PreparePostRequest($$) {
  my ($device, $body) = @_;
  my $account = $modules{$device->{TYPE}}{defptr}{"account"};

  my $userId = $account->{helper}{userId};
  my $deviceId = $device->{serialNumber}; 
  my $xCloudId = $device->{xCloudId};
 
  my $transId = Arlo_GenTransId();

  $body->{transId} = $transId;
  $body->{from} = $userId.'_web';
  $body->{to} = $deviceId;
  
  return ($account, $deviceId, $xCloudId);
}

sub Arlo_Notify($$;$) {
  my ($hash, $body, $callback) = @_;
  my ($account, $deviceId, $xCloudId) = Arlo_PreparePostRequest($hash, $body);
  Log3 $account->{NAME}, 4, "Notify $deviceId, action: $body->{action} $body->{resource}";
  Arlo_RequestWithLogin($account, '/users/devices/notify/'.$deviceId, 'POST', $body, 'xcloudId: '.$xCloudId, $callback, $hash);
}

sub Arlo_Subscribe($) {
  my ($hash) = @_;
  my $account = $modules{$MODULE}{defptr}{'account'};
  my $userId = $account->{helper}{userId};
  if (!defined($userId)) {
    Log3 $account->{NAME}, 3, 'User id missing in subscribe request.';
    return;
  }
  my $basestationId = $hash->{serialNumber};
  my @devices = ($basestationId);
  my $props = {devices => \@devices};
  my $body = {action => 'set', resource => 'subscriptions/'.$userId.'_web', publishResponse => \0, properties => $props};
  if (!defined($account->{RESPONSE_TIMEOUT})) {
    $account->{RESPONSE_TIMEOUT} = gettimeofday() + 30;
  }
  Arlo_Notify($hash, $body, \&Arlo_SubscribeCallback);
}

sub Arlo_SubscribeAll($) {
  my ($hash) = @_;
  my @basestations = Arlo_GetBasestations($hash);
  foreach my $serialNumber (@basestations) {
    my $device = $modules{$MODULE}{defptr}{"B$serialNumber"};
    Arlo_Subscribe($device);
  }
}

sub Arlo_SubscribeCallback($$$)  {
  my ($hash, $err, $jsonData) = @_;
  my $response = Arlo_DefaultCallback($hash, $err, $jsonData);
  my $origin = $hash->{origin};
  if (defined($response) && $origin && ReadingsVal($origin->{NAME}, 'state', '') eq 'offline') {
    readingsSingleUpdate($origin, 'state', 'online', 1);
    InternalTimer(gettimeofday() + 1, 'Arlo_UpdateBasestationReadings', $hash);
  }
}

sub Arlo_Unsubscribe($) {
  my ($hash) = @_;
  Arlo_RequestWithLogin($hash, '/client/unsubscribe');
}

sub Arlo_ReadModes($) {
  my ($hash) = @_;
  Arlo_RequestWithLogin($hash, '/users/automation/definitions?uniqueIds=all', 'GET', undef, undef, \&Arlo_ReadModesCallback);
};

sub Arlo_ReadModesCallback($$$)  {
  my ($hash, $err, $jsonData) = @_;
  my $response = Arlo_DefaultCallback($hash, $err, $jsonData);
  if (defined($response)) {
    foreach my $key (keys %{$response->{data}}) {
      if (defined($response->{data}{$key}{modes})) {
        my $account = $modules{$MODULE}{defptr}{'account'};
        my @modes = @{$response->{data}{$key}{modes}};
        foreach my $mode (@modes) {
          my $id = $mode->{id};
          my $bsMode = {name => $mode->{name}, type => $mode->{type}};
          $account->{MODES}{$id} = $bsMode;
        }
      }
    }
  }
}

sub Arlo_ReadCamerasAndLights($) {
  my ($hash) = @_;
  my $cam = {action => 'get', resource => 'cameras', publishResponse => \0};
  my ($account, $deviceId, $xCloudId) = Arlo_PreparePostRequest($hash, $cam);
  my $lights = {action => 'get', resource => 'lights', publishResponse => \0};
  Arlo_PreparePostRequest($hash, $lights);
  my @body = ($cam, $lights);
  if (defined($hash->{basestationSerialNumber}) && $hash->{basestationSerialNumber} eq $hash->{serialNumber}) {
    my $mode = {action => 'get', resource => 'modes', publishResponse => \0};
    Arlo_PreparePostRequest($hash, $mode);
	  push @body, $mode;
  }
  Arlo_RequestWithLogin($account, '/users/devices/notify/'.$deviceId, 'POST', \@body, 'xcloudId: '.$xCloudId);
}

sub Arlo_UpdateReadings($) {
  my ($hash) = @_;
  Arlo_UpdateBasestationReadings($hash);
  my @basestations = Arlo_GetBasestations($hash);
  my $delay = 2;
  foreach my $serialNumber (@basestations) {
    my $device = $modules{$MODULE}{defptr}{"B$serialNumber"};
    InternalTimer(gettimeofday() + $delay, "Arlo_ReadCamerasAndLights", $device);
    $delay += 2;
  }
}

sub Arlo_UpdateBasestationReadings($) {
  my ($hash) = @_;
  Arlo_RequestWithLogin($hash, '/users/devices/automation/active', 'GET', undef, undef, \&Arlo_UpdateReadingsCallback);
}

sub Arlo_UpdateReadingsCallback($$$)  {
  my ($hash, $err, $jsonData) = @_;
  my $response = Arlo_DefaultCallback($hash, $err, $jsonData);
  if (defined($response) && defined($response->{data})) {
    my @data = @{$response->{data}};
    foreach my $event (@data) {
      if ($event->{type} eq 'activeAutomations') {
        my $serialNumber = $event->{gatewayId};
        my @activeModes = @{$event->{activeModes}};
        if (@activeModes > 0) {
          Arlo_SetModeReading($serialNumber, $activeModes[0]);
        }
      }
    }
  }
}

sub Arlo_SetModeReading($$) {
  my ($serialNumber, $mode) = @_;
  my $basestation = $modules{$MODULE}{defptr}{"B$serialNumber"};
  if (defined($mode) && defined($basestation)) {
    my $modeName;
    my $account = $modules{$MODULE}{defptr}{"account"};
    if (defined($account->{MODES})) {
      $modeName = $account->{MODES}{$mode}{name};
      $modeName = $account->{MODES}{$mode}{type} if (!defined($modeName) || $modeName eq '');
    } else {
      if ($mode eq 'mode0') {
        $modeName = 'disarmed';
      } elsif ($mode eq 'mode1') {
        $modeName = 'armed';
      } else {
        InternalTimer(gettimeofday() + 1, "Arlo_ReadModes", $basestation);
      }
    }
    $modeName = $mode if (!defined($modeName) || $modeName eq '');
    readingsSingleUpdate($basestation, 'state', $modeName, 1);
    Arlo_CheckExpiry($account, $modeName);
  }
}

sub Arlo_CheckExpiry($$) {
  my ($account, $modeName) = @_;
  my $expiryTime = AttrVal($account->{NAME}, 'expiryTime', 600);
  if ($account->{STATE} eq 'active' && $expiryTime > 0) {
    if ($modeName ne 'disarmed' && defined($account->{EXPIRY})) {
      delete $account->{EXPIRY};
    } elsif ($modeName eq 'disarmed' && Arlo_CheckBasestationsInactive()) {
      $account->{EXPIRY} = gettimeofday() + $expiryTime;
    }
  } elsif ($account->{STATE} eq 'inactive' && $modeName ne 'disarmed') {
    Arlo_Login($account);
  }
}

sub Arlo_CheckBasestationsInactive() {
  my %defptr = %{$modules{$MODULE}{defptr}};
  foreach my $key (keys %defptr) {
    if (substr($key, 0, 1) eq 'B') {
      my $state = $defptr{$key}->{STATE};
      if ($state ne 'disarmed' && $state ne 'offline') {
        return \0;
      }
    }
  }
  return \1;
}

sub Arlo_BasestationArm($) {
  my ($hash) = @_;
  Arlo_DoSetBasestationMode($hash, 'mode1')

}

sub Arlo_BasestationDisarm($) {
  my ($hash) = @_;
  Arlo_DoSetBasestationMode($hash, 'mode0')
}

sub Arlo_SetBasestationMode($$) {
  my ($hash, $modeName) = @_;
  my $account = $modules{$MODULE}{defptr}{"account"};
  if (defined($account->{MODES})) {
    foreach my $id (keys %{$account->{MODES}}) {
      my $nameOfId = $account->{MODES}{$id}{name};
      if ($modeName ne '' && $modeName eq $nameOfId) {
        Log3 $hash->{NAME}, 3, "Set Arlo basestation mode to $id";
        Arlo_DoSetBasestationMode($hash, $id);
      }
    }
  } else {
    Log3 $hash->{NAME}, 2, "Could not set arlo mode $modeName, because modes for basestation have to be loaded. Please try a again in a few seconds.";
    Arlo_ReadModes($hash);
  }
}

sub Arlo_DoSetBasestationMode($$) {
  my ($hash, $mode) = @_;
  if (defined($hash->{basestationSerialNumber}) || $hash->{SUBTYPE} eq 'ROUTER') {  # Kamera mit integrierter Basestation oder Router M1
    my $props = {active => $mode};
    my $body = {action => 'set', resource => 'modes', publishResponse => \1,  properties => $props};
    Arlo_Notify($hash, $body);
  } else {
    my @modes = ($mode);
    my @schedules = ();
    my $now = int(gettimeofday() * 1000);
    my $automation = {deviceId => $hash->{serialNumber}, timestamp => $now, activeModes => \@modes, activeSchedules => \@schedules};
    my @automations = ($automation);
    my $body = { activeAutomations => \@automations };
    Arlo_RequestWithLogin($hash, '/users/devices/automation/active', 'POST', $body);
  }
}

sub Arlo_SetBasestationSiren($$) {
  my ($hash, $state) = @_;
  my $props = {sirenState => $state, duration => 300, volume => 8, pattern => 'alarm'};
  my $body = {action => 'set', resource => 'siren', publishResponse => \1,  properties => $props};
  Arlo_Notify($hash, $body);
}

sub Arlo_GetBasestationForCamera($) {
  my ($hash) = @_;
  my $serialNumber = $hash->{basestationSerialNumber};
  return $modules{$MODULE}{defptr}{"B$serialNumber"};
}

sub Arlo_ToggleCamera($$) {
	my ($hash, $newState) = @_;
  my $basestation = Arlo_GetBasestationForCamera($hash);
  my $cameraId = $hash->{serialNumber};
  my $privacyActive = $newState eq 'off' ? \1 : \0;
  my $props = {privacyActive => $privacyActive};
  my $body = {action => 'set', resource => "cameras/$cameraId", publishResponse => \1,  properties => $props};
  Arlo_Notify($basestation, $body);
}

sub Arlo_Snapshot($) {
  my ($hash) = @_;
  my $basestation = Arlo_GetBasestationForCamera($hash);
  my $cameraId = $hash->{serialNumber};
  my $props = {activityState => 'fullFrameSnapshot'};
  my $body = {action => 'set', resource => "cameras/$cameraId", publishResponse => \1,  properties => $props};
  my ($account, $basestationId, $xCloudId) = Arlo_PreparePostRequest($basestation, $body);
  Log3 $account->{NAME}, 4, "Take snapshot for camera $cameraId.";
  Arlo_RequestWithLogin($account, '/users/devices/fullFrameSnapshot', 'POST', $body, 'xcloudId: '.$xCloudId);
}

sub Arlo_StartRecording($)  {
  my ($hash) = @_;
  my $activityState = ReadingsVal($hash->{NAME}, 'activityState', 'idle');
  if ($activityState eq 'userStreamActive' && defined($hash->{streamURL})) {
    Arlo_Subscribe($hash);
	return "Camera is still recording.";
  } else {
    my $basestation = Arlo_GetBasestationForCamera($hash);
    my $cameraId = $hash->{serialNumber};
    my $props = {activityState => 'startUserStream', camera => $cameraId};
    my $body = {action => 'set', resource => "cameras/$cameraId", publishResponse => \1, properties => $props};
    my ($account, $basestationId, $xCloudId) = Arlo_PreparePostRequest($basestation, $body);
    Log3 $account->{NAME}, 4, "Start streaming for camera $cameraId.";
    $hash->{FOLLOW_CALL} = 'startRecord';
    Arlo_RequestWithLogin($account, '/users/devices/startStream', 'POST', $body, 'xcloudId: '.$xCloudId);
    InternalTimer(gettimeofday() + 10, "Arlo_CheckStreamStart", $hash);
  }
  return undef;
}

sub Arlo_StartRecordingStep2($) {
  my ($hash) = @_;
  if (defined($hash->{FOLLOW_CALL})) {
    Arlo_CameraAction($hash, 'startRecord');
    delete($hash->{FOLLOW_CALL});
  }
}

sub Arlo_CheckStreamStart($) {
  my ($hash) = @_;
  if (defined($hash->{FOLLOW_CALL})) {
    readingsSingleUpdate($hash,'activityState', 'timeout', 1);
	delete($hash->{FOLLOW_CALL});
  }
}

sub Arlo_CameraAction($$) {
  my ($hash, $action) = @_;
  my $account = $modules{$MODULE}{defptr}{"account"};
  my $xCloudId = $hash->{xCloudId};
  my $cameraId = $hash->{serialNumber};
  my $basestationId = $hash->{basestationSerialNumber};
  my $body = {xcloudId => $xCloudId, parentId => $basestationId, deviceId => $cameraId, olsonTimeZone => 'Europe/Berlin'};
  Log3 $account->{NAME}, 4, "Action $action for camera $cameraId.";
  Arlo_RequestWithLogin($account, '/users/devices/'.$action, 'POST', $body, 'xcloudId: '.$xCloudId);
}  

sub Arlo_SetBrightness($$) {
  my ($hash, $brightness) = @_;
  my $basestation = Arlo_GetBasestationForCamera($hash);
  my $cameraId = $hash->{serialNumber};
  my $props = {brightness => ($brightness + 0)};
  my $body = {action => 'set', resource => "cameras/$cameraId", publishResponse => \1,  properties => $props};
  Arlo_Notify($basestation, $body);
}

sub Arlo_SetNightLight($$) {
  my ($hash, $state) = @_;
  my $basestation = Arlo_GetBasestationForCamera($hash);
  my $cameraId = $hash->{serialNumber};
  my $enabled = \0;
  $enabled = \1 if ($state eq 'on');
  my $nightLight = {enabled => $enabled};
  my $props = {nightLight => $nightLight};
  my $body = {action => 'set', resource => "cameras/$cameraId", publishResponse => \1,  properties => $props};
  Arlo_Notify($basestation, $body);
}

sub Arlo_SetNightLightBrightness($$) {
  my ($hash, $brightness) = @_;
  my $basestation = Arlo_GetBasestationForCamera($hash);
  my $cameraId = $hash->{serialNumber};
  my $nightLight = {brightness => ($brightness + 0)};
  my $props = {nightLight => $nightLight};
  my $body = {action => 'set', resource => "cameras/$cameraId", publishResponse => \1,  properties => $props};
  Arlo_Notify($basestation, $body);
}

sub Arlo_GetValueBetweenBrackets($) {
  my ($cmd) = @_;
  my $pb = index($cmd, '(');
  my $pe = index($cmd, ')');
  return substr($cmd, $pb + 1, $pe - $pb - 1);
}

sub Arlo_SetNightLightColor($$) {
	my ($hash, $color) = @_;
  my $nightLight;
  if (substr($color, 0, 5) eq 'white') {
    $color = Arlo_GetValueBetweenBrackets($color);
    $nightLight = { mode => 'temperature', temperature => ($color + 0)};
  } elsif (substr($color, 0, 3) eq 'rgb') {
   $color = Arlo_GetValueBetweenBrackets($color);
    my $p1 = index($color, ',');
    my $p2 = index($color, ',', $p1 + 1);
    return "Invalid format. Please use rgb(red,green,blue)." if ($p1 <= 0 || $p2 <= 0);
    my $red = substr($color, 0, $p1) + 0;
    my $green = substr($color, $p1 + 1, $p2 - $p1 - 1) + 0;
    my $blue = substr($color, $p2 + 1) + 0;
    $nightLight = { mode => 'rgb', rgb => { red => $red, green => $green, blue => $blue }};
  } else {
    return "Invalid format. Please use white(temperature) or rgb(red,green,blue).";
  }

  my $basestation = Arlo_GetBasestationForCamera($hash);
  my $cameraId = $hash->{serialNumber};
  my $props = {nightLight => $nightLight};
  my $body = {action => 'set', resource => "cameras/$cameraId", publishResponse => \1,  properties => $props};
  Arlo_Notify($basestation, $body);
}

sub Arlo_SetLightState($$) {
  my ($hash, $state) = @_;
  my $basestation = Arlo_GetBasestationForCamera($hash);
  my $cameraId = $hash->{serialNumber};
  my $props = {lampState => $state};
  my $body = {action => 'set', resource => "lights/$cameraId", publishResponse => \1,  properties => $props};
  Arlo_Notify($basestation, $body);
}

sub Arlo_GetRecordings($$) {
  my ($hash, $date) = @_;
  my $body = {dateFrom => $date, dateTo => $date};
  # new https://myapi.arlo.com/hmsweb/users/library?eventId=FE!c985adde-bed3-4aa2-abe9-3baab559adae&time=1602097428821
  my ($err, $jsonData) = Arlo_BlockingRequest($hash, '/users/library', 'POST', $body);
  my $response = Arlo_DefaultCallback($hash, $err, $jsonData); 
  my @result = ();
  my $deviceId = $hash->{serialNumber};
  if (defined($response)) {
    my @data = @{$response->{data}};
    foreach my $r (@data) {
      if ($deviceId eq $r->{deviceId}) {
        my $rec = { time => $r->{localCreatedDate}, video => $r->{presignedContentUrl}, thumbnail => $r->{presignedThumbnailUrl} };
        push @result, $rec;
      }
    }
    
  }
  return @result;
}

sub Arlo_DownloadLastVideo($) {
  my ($hash) = @_;
  my $cameraId = $hash->{serialNumber};
  my $date = strftime '%Y%m%d', localtime;
  my @recordings = Arlo_GetRecordings($hash, $date);
  my $length = @recordings;
  if ($length > 0) {
    my $rec = $recordings[0];
    my $lastVideoTime = $hash->{lastVideoTime};
    my $newVideoTime = int($rec->{time});
    my $account = $modules{$MODULE}{defptr}{"account"};
    if (!defined($lastVideoTime) || $newVideoTime > $lastVideoTime) {
      $hash->{lastVideoTime} = $newVideoTime;
      Log3 $account->{NAME}, 4, "Download new recording $newVideoTime.";
      Arlo_SetReadingAndDownload($account, 'lastVideoThumbnailUrl', $rec->{thumbnail}, $cameraId, '_thumb.jpg', \0);
      Arlo_SetReadingAndDownload($account, 'lastVideoUrl', $rec->{video}, $cameraId, '.mp4', \1);
    } else {
      Log3 $account->{NAME}, 4, "Don't download recording because there is now new recording. Last Video: $lastVideoTime New Video: $newVideoTime";
    }
  }
}

#
# Login and Event-Polling
# 

sub Arlo_Login($) {
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  my $name = $hash->{NAME};

  if (AttrVal($name, 'disable', 0) == 1) {
    return;
  }

  $hash->{STATE} = 'python-login';
  delete $hash->{EXPIRY};
  delete $hash->{helper}{followUpRequest};
  
  delete $hash->{helper}{cookies};
  delete $hash->{helper}{token};
  my $mailServer = AttrVal($name, 'mailServer', '');
  if ($mailServer eq '') {
    Log3 $name, 1, 'Bei 2-Faktor-Authentifizierung muss das Attribut mailServer gesetzt sein, damit die Mail mit dem Authentifizerungs-Code abgerufen werden kann.';
    return;
  }
  
  my $tmpFile = '/tmp/arlo';
  system "python3 contrib/49_Arlo.py $hash->{helper}{username} $hash->{helper}{password} $mailServer $hash->{helper}{mailUser} $hash->{helper}{mailPassword} > $tmpFile &";

  open(my $fh, '<', $tmpFile);
  $hash->{helper}{pythonFh} = $fh;
  $hash->{helper}{pythonTimeout} = gettimeofday() + 120;
  InternalTimer(gettimeofday() + 1, "Arlo_ReadPythonResult", $hash);
}

sub Arlo_ReadPythonResult($) {
  my ($hash) = @_;
  if (gettimeofday() > $hash->{helper}{pythonTimeout}) {
    $hash->{STATE} = 'login timeout';
    Arlo_ClosePythonFile($hash);
    return;
  }
  my $fh = $hash->{helper}{pythonFh};
  my $line = <$fh>;
  while (defined($line)) {
    $line =~ s/\s+$//;
    if ($line eq "end") {
      Arlo_ClosePythonFile($hash);
      Arlo_Request($hash, '/users/session/v2', 'GET', undef, undef, \&Arlo_FinishLogin);
      return;
    }
    my $p = index($line, ': ');
    my $key = substr($line, 0, $p);
    my $value = substr($line, $p + 2);
    if ($key eq 'error') {
      $hash->{STATE} = 'login failed';
      Log3 $hash->{NAME}, 2, "Arlo: $value";
      Arlo_ClosePythonFile($hash);
      return;
    } elsif ($key eq 'log') {
      Log3 $hash->{NAME}, 3, "Arlo: $value";
    } elsif ($key eq 'status') {
      $hash->{STATE} = $value;
    } elsif ($key eq 'cookies') {
      $hash->{helper}{cookies} = $value;
    } elsif ($key eq 'token') {
      $hash->{helper}{token} = $value;
    } elsif ($key eq 'userId') {
      $hash->{helper}{userId} = $value;
    } else {
      Log3 $hash->{NAME}, 2, "Arlo: unknown command $line";
    }
    $line = <$fh>;
  }
  InternalTimer(gettimeofday() + 1, "Arlo_ReadPythonResult", $hash);
}

sub Arlo_ClosePythonFile($) {
  my ($hash) = @_;
  my $fh = $hash->{helper}{pythonFh};
  close($fh);
  unlink('/tmp/arlo');
  delete $hash->{helper}{pythonFh};
  delete $hash->{helper}{pythonTimeout};
}

sub Arlo_FinishLogin($$$) {
  my ($hash, $err, $jsonData) = @_;
  my $response = Arlo_DefaultCallback($hash, $err, $jsonData);
  if (defined($response)) {
    my $account = $modules{$MODULE}{defptr}{"account"};
		$account->{SSE_STATUS} = 200;
		$account->{STATE} = 'active';
		Arlo_Request($account, '/users/devices');
    
    my $req = $account->{helper}{followUpRequest};
    if (defined($req)) {
		  Arlo_Request($req->{hash}, $req->{urlSuffix}, $req->{method}, $req->{body}, $req->{additionalHeader}, $req->{callback}, $req->{origin});
      delete $account->{helper}{followUpRequest};
    }

		Arlo_EventQueue($account);
		Arlo_Ping($account);
		if (!defined($account->{MODES})) {
		  InternalTimer(gettimeofday() + 5, "Arlo_ReadModes", $account);
		}
		InternalTimer(gettimeofday() + 30, "Arlo_Poll", $account);
	}
}

sub Arlo_Logout($) {
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  delete $hash->{EXPIRY};
  Arlo_Request($hash, '/logout', 'PUT');
  $hash->{STATE} = 'inactive';
}  

sub Arlo_EventQueue($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $cookies = $hash->{helper}{cookies};
  my $token = $hash->{helper}{token};
  delete $hash->{RESPONSE_TIMEOUT};

  my $headers = {'Auth-Version' => 2, Authorization => $token, Accept => 'text/event-stream', 'Access-Control-Request-Headers' => 'auth-version,authorization',
    'Access-Control-Request-Method' => 'GET', Cookie => $cookies, Origin => 'https://my.arlo.com', Referer => 'https://myapi.arlo.com',
    'User-Agent' => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.96 Safari/537.36' };
  my $con = {url => 'https://myapi.arlo.com/hmsweb/client/subscribe', method => "GET", header => $headers, keepalive => 1, host => 'myapi.arlo.com', httpversion => '1.1', loglevel => 4};
  my $err = HttpUtils_Connect($con);
  if ($err) {
    Log3 $name, 2, "Error in Arlo event queue: $err";
    if ($hash->{SSE_STATUS} == 0) { # aus EventPolling heraus gestartet
      Log3 $name, 3, "Try to restart Arlo event listener in 60 seconds.";
      InternalTimer(gettimeofday() + 60, "Arlo_EventQueue", $hash);
    }
    return;
  }
  
  delete($con->{httpdatalen});
  delete($con->{httpheader});
  
  $hash->{helper}{con} = $con;
  Log3 $name, 2, "(Re)starting Arlo event listener.";
  Arlo_EventPolling($hash);
}
  
sub Arlo_EventPolling($) {  
  my ($hash) = @_;
  my $con = $hash->{helper}{con};
  my $name = $hash->{NAME};

  if (!defined($con->{conn})) {
    Log3 $name, 3, "Arlo connection not defined, stop event polling.";
    return;
  }
  
  my ($rout, $rin) = ('', '');
  vec($rin, $con->{conn}->fileno(), 1) = 1;
  Log3 $name, 5, "Checking for Arlo server response.";
  my $nfound = select($rout=$rin, undef, undef, 0.1);
  my $content = '';
  while ($nfound > 0) {
    my $buf = '';
    my $len = sysread($con->{conn}, $buf, 65536);
    if (!defined($len) || $len <= 0) {
      HttpUtils_Close($con);
      if ($hash->{SSE_STATUS} == 200) {
        $hash->{SSE_STATUS} = 0;
        Log3 $name, 3, "Arlo connection stopped, try to restart event listener.";
        Arlo_EventQueue($hash);
      } else {
        Log3 $name, 2, "Stopping Arlo event listener.";
      }
      return;
    }
    $content = $content . $buf;
    $nfound = select($rout=$rin, undef, undef, 0.1);
  }
  Arlo_ProcessResponse($hash, $content) if ($content ne '');
  
  my $expiry = $hash->{EXPIRY};
  my $timeout = $hash->{RESPONSE_TIMEOUT};
  my $sseStatus = $hash->{SSE_STATUS};

  if (defined($expiry)) {
     if ($expiry < gettimeofday() || $sseStatus == 299 || (defined($timeout) && $timeout < gettimeofday())) {
      Log3 $name, 3, "Arlo set to inactive.";
      HttpUtils_Close($con);
      Arlo_Logout($hash);
      return;
    }
  } else {
    if ($sseStatus == 299) {
      InternalTimer(gettimeofday() + 60, "Arlo_Login", $hash);
      return;
    } elsif ($sseStatus == 298) {
      $hash->{SSE_STATUS} = 0;
      InternalTimer(gettimeofday() + 5, "Arlo_EventQueue", $hash);
      return;
    } else {
      if (defined($timeout) && $timeout < gettimeofday()) {
        $hash->{SSE_STATUS} = 0;
        Log3 $name, 3, "Arlo connection timeout, try to restart event listener.";
        HttpUtils_Close($con);
        Arlo_EventQueue($hash);
		    return;
      }
    }
  }
  my $ssePollingInterval = AttrVal($name, 'ssePollingInterval', 2);
  InternalTimer(gettimeofday() + $ssePollingInterval, "Arlo_EventPolling", $hash);
}


sub Arlo_ProcessResponse($$) {
  my ($hash, $response) = @_;
  delete $hash->{RESPONSE_TIMEOUT};
  for my $line (split("\n", $response)) {
    if (length($line) > 5) {
      my $check = substr($line, 0, 5);
      if (($check eq 'data:' && length($line) > 7) || $hash->{helper}{incompleteLine}) {
        eval {
          if ($hash->{helper}{incompleteLine}) {
            $line = join('', $hash->{helper}{incompleteLine}, $line);
          } 
          if (substr($line, 6, 1) eq '{' && substr($line, length($line)-1, 1) eq '}') {
            delete $hash->{helper}{incompleteLine};
            my $event = decode_json substr($line, 5);
            Log3 $hash->{NAME}, 4, $line;
            Arlo_ProcessEvent($hash, $event);
          } else {
            $line =~ s/\\|\R//g;
            $hash->{helper}{incompleteLine} = $line;
          }
        };
        if ($@) {
          Log3 $hash->{NAME}, 2, 'Invalid Arlo JSON response: '.$line;
        }
      } elsif ($check eq 'HTTP/') {
        my $status = substr($line, 9, 3);
        $hash->{SSE_STATUS} = $status;
        if ($status != 200) {
          Log3 $hash->{NAME}, 2, "Arlo event queue error: wrong http status $status.";
        }
      } elsif ($check eq 'Conne' && substr($line, 0, 11) eq 'Connection:') {
        if (index($line, 'keep-alive') < 0) {
          Log3 $hash->{NAME}, 2, "Arlo event queue error: connection has no keep-alive header.";
          $hash->{SSE_STATUS} = 299;
        }
      } elsif ($check eq 'Set-C' && substr($line, 0, 11) eq 'Set-Cookie:') {
        if (index($line, 'JSESSIONID') > 0) {
          Log3 $hash->{NAME}, 2, "Arlo event queue error: session lost.";
          $hash->{SSE_STATUS} = 299;
        }
      } elsif ($check eq 'Vary:') {
          Log3 $hash->{NAME}, 3, "Arlo event queue error: subscription declined (Header $line). Retry event subscription.";
          $hash->{SSE_STATUS} = 298;
      } elsif ($check ne 'event' && $check ne 'Cache' && $check ne 'Conte' && $check ne 'Date:' && $check ne 'Pragm' && $check ne 'Server' && $check ne 'Acces'
          && substr($check, 0, 2) ne 'X-' && $check ne 'trans' && $check ne 'Serve' && $check ne 'Expir' && $check ne 'Stric' && $check ne 'Trans'
          && $check ne 'Expec' && $check ne 'CF-RA' && $check ne 'CF-Ca' && $check ne 'reque' && $check ne 'x-tra' && $check ne 'cf-re') {
        Log3 $hash->{NAME}, 2, "Invalid Arlo event response: $line";
      }
    } 
  }
}
    
sub Arlo_ProcessEvent($$) {
  my ($hash, $event) = @_;
  my $name = $hash->{NAME};
  my $resource = $event->{resource};
  my $basestationId = $event->{from};
  if (defined($resource)) {
    Log3 $name, 3, "Process Arlo event $resource for $basestationId" if (defined($basestationId));
    Log3 $name, 3, "Process Arlo event $resource" if (!defined($basestationId));
    if ($resource eq 'modes') {
      my $props = $event->{properties};
      my $activeMode = $props->{activeMode};
	  $activeMode = $props->{active} if (!defined($activeMode));
      Arlo_SetModeReading($basestationId, $activeMode);
    } elsif ($resource eq 'cameras') {
      my @props = @{$event->{properties}};
      for my $prop (@props) {
        my $state = $prop->{privacyActive} ? 'off' : 'on';
        my $cameraId = $prop->{serialNumber};
        my $batteryLevel = $prop->{batteryLevel};
        my $signalStrength = $prop->{signalStrength};
        my $brightness = $prop->{brightness};
        Arlo_Camera_Readings($hash, $cameraId, $state, $batteryLevel, $signalStrength, $brightness);
      }
    } elsif (substr($resource,0,8) eq 'cameras/') {
      my $props = $event->{properties};
      my $cameraId = substr($resource, 8);
      my $action = $event->{action};
      if ($action eq 'fullFrameSnapshotAvailable') {
        Arlo_SetReading($hash, $cameraId, 'activityState', 'idle');
        Arlo_SetReadingAndDownload($hash, 'snapshotUrl', $props->{presignedFullFrameSnapshotUrl}, $cameraId, '_snapshot.jpg', \0);
      } elsif ($action eq 'is') {
        Arlo_SetReading($hash, $cameraId, 'chargingState', $props->{chargingState});
        Arlo_SetReading($hash, $cameraId, 'batteryLevel', $props->{batteryLevel});
        Arlo_SetReading($hash, $cameraId, 'signalStrength', $props->{signalStrength});
        Arlo_SetReading($hash, $cameraId, 'brightness', $props->{brightness});
        Arlo_SetReading($hash, $cameraId, 'motionDetected', $props->{motionDetected});

        my $privacyActive = $props->{privacyActive};
        if (defined($privacyActive)) {
          my $state = $privacyActive ? 'off' : 'on';
          Arlo_SetReading($hash, $cameraId, 'state', $state);
        } 
         
        my $activityState = $props->{activityState};
        if ($activityState) {
          my $camera = $modules{$MODULE}{defptr}{"C$cameraId"};
          my $oldActivityState = ReadingsVal($camera->{NAME}, 'activityState', '');
          Arlo_SetReading($hash, $cameraId, 'activityState', $activityState);
          if ($activityState eq 'startUserStream') {
            my $streamURL = $props->{streamURL};
            if (defined($streamURL)) {
              $camera->{streamURL} = $streamURL =~ s/rtsp:/rtsps:/r;
            }
          } elsif ($activityState eq 'userStreamActive') {
		    InternalTimer(gettimeofday() + 0.5, "Arlo_StartRecordingStep2", $camera);
          } elsif ($activityState eq 'idle' && ($oldActivityState eq 'alertStreamActive' || $oldActivityState eq 'userStreamActive') && AttrVal($name, 'videoDownloadFix', 0) == 1) {
            Log3 $name, 4, "Download latest video for $camera->{NAME} in 2 seconds";
            InternalTimer(gettimeofday() + 2, "Arlo_DownloadLastVideo", $camera);
          }
        }
      }
    } elsif (substr($resource,0,7) eq 'lights/') {
      my $props = $event->{properties};
      my $deviceId = substr($resource, 7);
      my $action = $event->{action};
      if ($action eq 'is') {
        Arlo_SetReading($hash, $deviceId, 'activityState', $props->{activityState});
        Arlo_SetReading($hash, $deviceId, 'batteryLevel', $props->{batteryLevel});
        Arlo_SetReading($hash, $deviceId, 'chargingState', $props->{chargingState});
        Arlo_SetReading($hash, $deviceId, 'motionDetected', $props->{motionDetected});
        Arlo_SetReading($hash, $deviceId, 'state', $props->{lampState});
      }
    } elsif ($resource eq 'mediaUploadNotification' && AttrVal($name, 'videoDownloadFix', 0) == 0) {
      my $cameraId = $event->{deviceId};
      Arlo_SetReading($hash, $cameraId, 'activityState', 'idle');
      Arlo_SetReadingAndDownload($hash, 'lastVideoThumbnailUrl', $event->{presignedThumbnailUrl}, $cameraId, '_thumb.jpg', \0);
      Arlo_SetReadingAndDownload($hash, 'lastVideoImageUrl', $event->{presignedLastImageUrl}, $cameraId, '.jpg', \0);
      Arlo_SetReadingAndDownload($hash, 'lastVideoUrl', $event->{presignedContentUrl}, $cameraId, '.mp4', \1);
    } 
    my $error = $event->{error};
    if ($error) {
      Arlo_SetReading($hash, $event->{deviceId}, 'error', $event->{message});
    }
  } else {
    my $action = $event->{action};
    if (defined($action) && $action eq 'logout') {
      Log3 $name, 3, "Received Arlo logout event.";
      Arlo_SubscribeAll($hash);
    }
  }
}

#
# Helper
#

sub Arlo_encrypt($) {
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /crypt:/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'.$encoded;
}

sub Arlo_decrypt($) {
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if( $encoded !~ /crypt:/ );
  
  $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}
1;

=pod
=item summary Communicates to Arlo cameras
=item summary_DE Kommuniziert mit Arlo Kameras
=begin html

<a name="Arlo"></a> 
<h3>Arlo</h3>
<ul>
  <p>Arlo security cams are connected to the Arlo Cloud via base stations. The base stations and cameras can be controlled with a REST API. 
     Events (like movement and state changes) are delivery by server-sent events (SSE).</p>

  <p><a name="ArloDefine"></a> <b>Define</b></p>
  <ul>
    <code>define Arlo_Cloud Arlo ACCOUNT &lt;hans.mustermann@xyz.de&gt; &lt;myArloPassword&gt; &lt;myEmailPassword&gt; &lt;myEmailUsername&gt;</code>
    
	<p>Please replace hans.mustermann@xyz.de by the e-mail address you have registered at Arlo and myArloPassword by the password used there.
    For the 2 factor authentication you also have to set the password of the email account. The email server which receives the Arlo mails has to be set
    with attr Arlo_Cloud mailServer imap.gmx.net, where imap.gmx.net has to be replaced by the IMAP server of your mail provider. Only IMAP with encryption is supported.
    You can skip the parameter myEmailUsername if the username matches the email address.</p>
    
  <p>After you have successfully created the account definition, you can call <code>set Arlo_Cloud autocreate</code>.
    Now the base station(s) and cameras which are assigned to the Arlo account will be created in FHEM. All new devices are created in the room Arlo.</p>
    
  <p>In the background there is a permanent SSE connection to the Arlo server. If you temporary don't use Arlo in FHEM, you can stop this SSE connection by setting
     the attribute "disable" at the Arlo_Cloud device to 1.</p>
  </ul>
  
  <p><a name="ArloSet"></a> <b>Set</b></p>
  <ul>
		<li>autocreate (subtype ACCOUNT)<br>
		    Reads all devices which are assigned to the Arlo account and creates FHEM devices, if the devices don't exist in FHEM.
		</li>
		<li>reconnect (subtype ACCOUNT)<br>
		    Connect or reconnect to the Arlo server. First FHEM logs in, then a SSE connection is established. This method is only used if the connection
			to the Arlo server was interrupted.
		</li>
		<li>readModes (subtype ACCOUNT)<br>
		    Reads the modes of the base stations (iincl. custom modes). Is called automatically, normally you don't have to call this manually.
		</li>
		<li>updateReadings (subtype ACCOUNT)<br>
		   The data of all base stations and cameras are retrieved from the Arlo cloud. This is done every hour automatically, if you don't set the 
		   attribute disable=1 at the Cloud device. The interval can be changed by setting the attribute updateInterval (in seconds, e.g. 600 for 10 minutes, 7200 for 2 hours).
        </li>	
		<li>arm (subtype BASESTATION, BRIDGE, ARLOQ and BABYCAM)<br>
		    Activates the motion detection.
		</li>	
		<li>disarm (subtype BASESTATION, BRIDGE, ARLOQ and BABYCAM)<br>
		    Deactivates the motion detection.
		</li>	
		<li>mode (subtype BASESTATION and BRIDGE)<br>
		    Set a custom mode (parameter: name of the mode).
		</li>	
		<li>siren (subtype BASESTATION)<br>
		    Activates or deactivates the siren of the base station (attention: the siren is loud!).
		</li>	
		<li>subscribe (subtype BASESTATION, ARLOQ and BABYCAM)<br>
		    Subscribe base station for the SSE connection. Normally you don't have to do this manually, this is done automatically after login.
		</li>
		<li>unsubscribe (subtype BASESTATION, ARLOQ and BABYCAM)<br>
		    Unsubscribe base station for the current SSE connection.			
		</li>
		<li>brightness (subtype CAMERA, ARLOQ and BABYCAM)<br>
			Adjust brightness of the camera (possible values: -2 to +2).
		</li>	
		<li>on (Subtype CAMERA)<br>
		    Switch on camera (deactivate privacy mode).
		</li>	
		<li>off (subtype CAMERA)<br>
		    Switch off camera (activate privacy mode).
		</li>		
		<li>snapshot (subtype CAMERA, ARLOQ and BABYCAM)<br>
		    Take a snapshot. The snapshot url is written to the reading snapshotUrl. This command only works if the camera has the state on.
		</li>	
		<li>startRecording (subtype CAMERA, ARLOQ and BABYCAM)<br>
		    Start recording. This command only works if the camera has the state on.
		</li>	
		<li>stopRecording (subtype CAMERA, ARLOQ and BABYCAM)<br>
		    Stops an active recording. The recording url is stored in the reading lastVideoUrl, a frame of the recording in lastVideoImageUrl and a thumbnail of the recording in lastVideoThumbnailUrl.
		</li>	
		<li>nightlight (Subtype BABYCAM)<br>
			Switch nightlight on or off.
		</li>	
		<li>nightlight-brightness (Subtype BABYCAM)<br>
			Set brightness of nightlight.
		</li>	
		<li>nightlight-color (Subtype BABYCAM)<br>
			Set color of nightlight.
		</li>	
  </ul>
  
  <p><a name="ArloAttr"></a> <b>Attributes</b></p>
  <ul>Common attributes:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	  <a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="ArloDownloadDir"></a> <b>downloadDir</b></p>
  <ul>
    If this attribute is set at the cloud device (subtype ACCOUNT), the files which are stored at the Arlo Cloud (videos / images) will also be downloaded to the given directory.
	If you want to access these files via FHEM http you have to use a subdirectory of /opt/fhem/www.
	Attention: the fhem user has to have write access to the directory.
  </ul> 

  <p><a name="ArloDownloadLink"></a> <b>downloadLink</b></p>
  <ul> 
    If the attribute downloadDir is set and the files will be downloaded from Arlo Cloud, you can set this attribute to create a correct URL to the last video, last snapshot and so on.
	A correct value is like http://hostname:8083/fhem/subdirectory-of-www
  </ul> 

  <p><a name="ArloDisable"></a> <b>disable</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Deactivates the SSE connection to Arlo Cloud.</p>
    <p>Subtype BASESTATION: Deactivates the periodic update of the readings from Arlo Cloud.</p>
  </ul> 

  <p><a name="ArloExpiryTime"></a> <b>expiryTime</b></p>
  <ul> 
    <p>Subtype ACCOUNT: If all base stations have the status "disarmed" the connection to the cloud will be closed after this time. A new connection will be established if needed.
	  Unit is seconds, default 600 (10 minutes). If you set the value to 0 the connection will not be closed.</p>
  </ul> 

  <p><a name="ArloMailServer"></a> <b>mailServer</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Name of the IMAP mail server which receives the Arlo 2FA code mail. The passwort for the mail server has to be set in the define of Arlo_Cloud device.</p>
  </ul> 
  
  <p><a name="ArloPingVideoDownloadFix"></a> <b>videoDownloadFix</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Set this attribute to 1 if videos are not downloaded automatically. Normally the server sents a notification when there is a new video available but sometimes 
	this doesn't work. Default is 0.</p>
  </ul>	

  <p><a name="ArloPingInterval"></a> <b>pingInterval</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Set the interval in seconds for the heartbeat-ping. Without a heartbeat-ping the session in Arlo Cloud would expire and FHEM wouldn't receive any more events.
    Default is 90.</p>
  </ul>	

  <p><a name="ArloUpdateInterval"></a> <b>updateInterval</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Set the interval in seconds how often the readings of base statations and cameras will be updated. Default is 3600 = 1 hour.</p>
  </ul>	

  <p><a name="ArloSsePollingInterval"></a> <b>ssePollingInterval</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Set the interval in seconds how often the SSE events are checked. Default is 2 seconds.</p>
  </ul>	

</ul>
=end html

=begin html_DE

<a name="Arlo"></a> 
<h3>Arlo</h3>
<ul>
  <p>Arlo Sicherheitskameras werden über eine Basisstation an die Arlo Cloud angebunden. Diese kann über eine REST-API angesprochen werden und liefert
    Ereignisse (wie z.B. erkannte Bewegungen oder sonstige Statusänderungen) über Server-Sent Events (SSE) zurück.</p>

  <p><a name="ArloDefine"></a> <b>Define</b></p>
  <ul>
    <code>define Arlo_Cloud Arlo ACCOUNT &lt;hans.mustermann@xyz.de&gt; &lt;meinArloPasswort&gt; &lt;meinEmailPasswort&gt; &lt;meinEmailBenutzername&gt;</code>
    
	<p>hans.mustermann@xyz.de durch die E-Mail-Adresse ersetzen, mit der man bei Arlo registriert ist, meinArloPasswort durch das Passwort bei Arlo. 
    Für die 2-Faktor-Authentifizierung wird zusätzlich das Passwort des E-Mail-Accounts benötigt. Der E-Mail-Server, von dem die Arlo-Mails abgerufen werden sollen,
    muss mit attr Arlo_Cloud mailServer imap.gmx.net angegeben werden, wobei imap.gmx.net durch den IMAP-Mailserver des Providers ersetzt werden muss, bei dem
    das E-Mail-Konto liegt. Es wird ausschließlich IMAP mit Verschlüsselung unterstützt. Der Parameter meinEmailBenutzername muss nur angegeben werden, falls
    der Benutzernamen, mit dem man sich am Mailserver anmeldet, von der E-Mail-Adresse abweicht.</p>
    
  <p>Nach der erfolgreichen Definition des Account kann auf dem neu erzeugten Device <code>set Arlo_Cloud autocreate</code> aufgerufen werden. 
    Dies legt die Basistation(en) und Kameras an, die zu dem Arlo Account zugeordnet sind. Die neuen Devices befinden sich initial im Raum Arlo.</p>
    
  <p>Aufgrund der SSE-Schnittstelle ist es notwendig, dass dauerhaft im Hintergrund eine Verbindung zum Arlo-Server gehalten wird. Falls dies nicht gewünscht ist, 
    da Arlo z.B. vorübergehend nicht genutzt wird, kann der Hintergrund-Job verhindert werden, indem das Attribut "disable" des Arlo_Cloud-Device auf 1 gesetzt wird.</p>
  </ul>
  
  <p><a name="ArloSet"></a> <b>Set</b></p>
  <ul>
		<li>autocreate (Subtype ACCOUNT)<br>
			Liest alle dem Arlo-Account zugeordneten Geräte und legt dafür FHEM-Devices an, falls es diese nicht schon gibt.
		</li>
		<li>reconnect (Subtype ACCOUNT)<br>
			Neuaufbau der Verbindung zum Arlo-Server. Zunächst loggt sich FHEM neu bei Arlo ein, danach wird die SSE-Verbindung aufgebaut. Wird nur benötigt, 
			falls unerwartete Verbindungsabbrüche auftreten.
		</li>
		<li>readModes (Subtype ACCOUNT)<br>
			Liest die Modes der Basisstationen (inkl. Custom Modes). Wird automatisch aufgerufen, daher normalerweise kein manueller Aufruf notwendig.
		</li>
		<li>updateReadings (Subtype ACCOUNT)<br>
			Aktuelle Daten aller Basisstationen und Kameras aus der Cloud abrufen. Dies passiert einmal stündlich automatisch, falls dies nicht 
			durch Setzen des Attributes disabled=1 am Cloud-Device unterbunden wird. Den Abruf-Intervall kann man durch Setzen des Attributs updateInterval 
			anpassen (Angabe von Sekunden, also z.B. 600 für Abruf alle 10 Minuten oder 7200 für Abruf alle 2 Stunden).		
		</li>	
		<li>arm (Subtypes BASESTATION, BRIDGE, ARLOQ und BABYCAM)<br>
			Aktivieren der Bewegungserkennung.
		</li>	
		<li>disarm (Subtype BASESTATION, BRIDGE, ARLOQ und BABYCAM)<br>
			Deaktivieren der Bewegungserkennung.
		</li>	
		<li>mode (Subtype BASESTATION und BRIDGE)<br>
			Setzen eines benutzerdefinierten Modus (Parameter: Name des Modus).
		</li>	
		<li>siren (Subtype BASESTATION)<br>
			Schaltet die Siren der Basisstation an oder aus (Achtung: laut!!).
		</li>	
		<li>subscribe (Subtype BASESTATION, ARLOQ und BABYCAM)<br>
			Basisstation für die SSE-Schnittstelle registrieren. Muss normalerweise nie manuell aufgerufen werden, da dies beim Login automatisch passiert.
		</li>
		<li>unsubscribe (Subtype BASESTATION, ARLOQ und BABYCAM)<br>
			Registrierung einer Basisstation für die SSE-Schnittstelle rückgängig machen.
		</li>
		<li>brightness (Subtype CAMERA, ARLOQ und BABYCAM)<br>
			Helligkeit der Kamera anpassen (mögliche Werte: -2 bis +2).
		</li>	
		<li>on (Subtype CAMERA und LIGHT)<br>
			Kamera/Licht einschalten.
		</li>	
		<li>off (Subtype CAMERA und LIGHT)<br>
			Kamera/Licht ausschalten.
		</li>		
		<li>snapshot (Subtype CAMERA, ARLOQ und BABYCAM)<br>
			Ein Standbild aufnehmen. Dieses kann danach über die URL aus dem Reading snapshotUrl aufgerufen werden. Damit der Befehl funktioniert, muss die Kamera den Status on haben.
		</li>	
		<li>startRecording (Subtype CAMERA, ARLOQ und BABYCAM)<br>
			 Aufnahme starten. Damit der Befehl funktioniert, muss die Kamera den Status on haben.
		</li>	
		<li>stopRecording (Subtype CAMERA, ARLOQ und BABYCAM)<br>
			 Aufnahme stoppen. Die Aufnahme kann danach über lastVideoUrl abgerufen werden, das Standbild dazu unter lastVideoImageUrl und lastVideoThumbnailUrl (klein).
		</li>	
		<li>nightlight (Subtype BABYCAM)<br>
			Nachtlicht ein-/ausschalten (on/off).
		</li>	
		<li>nightlight-brightness (Subtype BABYCAM)<br>
			Helligkeit des Nachtlichts anpassen.
		</li>	
		<li>nightlight-color (Subtype BABYCAM)<br>
			Farbe des Nachtlichts anpassen.
		</li>	
  </ul>
  
  <p><a name="ArloAttr"></a> <b>Attribute</b></p>
  <ul>Allgemeine Attribute:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	  <a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="ArloDownloadDir"></a> <b>downloadDir</b></p>
  <ul> 
    Falls dieses Attribut am Cloud-Device (Subtype ACCOUNT) gesetzt ist, werden Dateien, die in der Arlo Cloud erzeugt werden (Videos / Bilder) in das hier angegebene Verzeichnis heruntergeladen.
    Damit man auf die Dateien über http zugreifen kann, muss ein Verzeichnis unterhalb /opt/fhem/www angegeben werden (oder dieses selbst).
    Wichtig: der fhem-User muss in in diesem Verzeichnis Schreibrechte haben.
  </ul> 

  <p><a name="ArloDownloadLink"></a> <b>downloadLink</b></p>
  <ul> 
    Falls über das Attribut downloadDir die Dateien ins lokale Verzeichnis heruntergeladen werden, kann über dieses Attribut am Cloud-Device angegeben werden, dass die in den Kameras gesetzten Links auf die lokale Kopie zeigen sollen.
    Die Angabe des Links muss in der Form http://hostname:8083/fhem/unterverzeichnis-unter-www angegeben werden.
  </ul> 

  <p><a name="ArloDisable"></a> <b>disable</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Deaktiviert die Verbindung zur Arlo-Cloud.</p>
    <p>Subtype BASESTATION: Deaktiviert die regelmäßige Abfrage der Readings aus der Arlo Cloud.</p>
  </ul> 

  <p><a name="ArloExpiryTime"></a> <b>expiryTime</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Wenn alle Basisstation auf "disarmed" stehen, wird die Verbindung zur Cloud nach der hier angegebenen Zeit beendet. Bei einer Aktion mit einem Arlo-Gerät wird eine neue Verbindung aufgebaut.
	  Angabe in Sekunden, Standard ist 600 (10 Minuten). Durch Angabe von 0 kann die Verbindung dauerhaft bestehen bleiben.</p>
  </ul> 

  <p><a name="ArloMailServer"></a> <b>mailServer</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Name des IMAP Mailservers, an den Arlo den Code für die 2-Faktor-Authentifizierung sendet. Das Passwort muss beim define des Arlo_Cloud-Devices angegeben werden.</p>
  </ul> 

  <p><a name="ArloPingVideoDownloadFix"></a> <b>videoDownloadFix</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Dieser Wert muss auf 1 gesetzt werden, falls Videos nach der Aufnahme nicht automatisch heruntergeladen werden. Normalerweise werden Events vom Server gesendet,
	sobald eine neue Aufnahme vorhanden ist, aber manchmal funktioniert das nicht. Standard ist 0 (ausgeschaltet).</p>
  </ul>	

  <p><a name="ArloPingInterval"></a> <b>pingInterval</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Setzt das Intervall in Sekunden, wie häfuig ein Heartbeat-Ping gesendet wird. Ohne den Heartbeat-Ping würde die Session ablaufen und 
    es könnten keine Events mehr empfangen werden. Standard ist 90.</p>
  </ul>	

  <p><a name="ArloUpdateInterval"></a> <b>updateInterval</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Setzt das Intervall in Sekunden, wie häufig die Readings der Basisstationen und  Kameras abgefragt werden. Standard ist 3600 = 1 Stunde.</p>
  </ul>	

  <p><a name="ArloSsePollingInterval"></a> <b>ssePollingInterval</b></p>
  <ul> 
    <p>Subtype ACCOUNT: Setzt das Intervall in Sekunden, wie häufig die SSE Events abgefragt werden sollen. Standard ist 2 Sekunden.</p>
  </ul>	

</ul>
=end html_DE

=cut

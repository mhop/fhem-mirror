# $Id$
# HTTP API commands
#   set command: http://<ip-addr>:<ip-port>/<apiName>/set?device=<devname>&action=<cmd>
#   get command: http://<ip-addr>:<ip-port>/<apiName>/get?device=<devname>&action=<cmd>
#   read reading: http://<ip-addr>:<ip-port>/<apiName>/read?device=<devname>&reading=<name>
#   write reading: http://<ip-addr><ip-port>/<apiName>/write?device=<devname>&reading=<name>&value=<val>

package main;
use Encode qw(decode encode);
use SetExtensions;
use strict;
use TcpServerUtils;
use warnings;

my $gPath = '';
BEGIN {
  $gPath = substr($0, 0, rindex($0, '/'));
}
if (lc(substr($0, -7)) eq 'fhem.pl') {
  $gPath = $attr{global}{modpath}.'/FHEM';
}
use lib ($gPath.'/lib', $gPath.'/FHEM/lib', './FHEM/lib', './lib', './FHEM', './', '/usr/local/FHEM/share/fhem/FHEM/lib');

my $encoding = 'UTF-8';
my $infix = 'api';
my $linkPattern = "^\/?(([^\/]*(\/[^\/]+)*)\/?)\$";
my $tcpServAdr = 'global';
my $tcpServPort = 8087;

sub HTTPAPI_Initialize($) {
  my ($hash) = @_;
  $hash->{AttrFn} = "HTTPAPI_Attr";
  $hash->{DefFn} = "HTTPAPI_Define";
  $hash->{ReadFn}  = "HTTPAPI_Read";
  $hash->{UndefFn} = "HTTPAPI_Undef";
  $hash->{AttrList} = "disable:0,1 devicesCtrl " . $readingFnAttributes;
  $hash->{parseParams} = 1;
  return undef;
}

sub HTTPAPI_Define($$) {
  my ($hash, $a, $h) = @_;
  my $name = $a->[0];
  if (defined $a->[2]) {
    $hash->{INFIX} = $a->[2];
    $infix = $a->[2];
  } elsif (exists $h->{infix}) {
    $hash->{INFIX} = $h->{infix};
    $infix = $h->{infix};
  } else {
    $hash->{INFIX} = $infix;
  }
  # check if valid folder name
  if ($hash->{INFIX} !~ /^[^\\\/\?\*\"\'\>\<\:\|]*$/) {
    return "HTTPAPI: wrong syntax, correct is: define <name> HTTPAPI [infix=]<infix> [port=][[IPV6:]<port>] [global=][global|local|<hostname>]";
  }
  my ($pport, $port);
  if (defined $a->[3]) {
    $pport = $a->[3];
  } elsif (exists $h->{port}) {
    $pport = $h->{port};
  } else {
    $pport = $tcpServPort;
  }
  $port = $pport;
  $port =~ s/^IPV6://;
  return "HTTPAPI: wrong syntax, correct is: define <name> HTTPAPI [infix=]<infix> [port=][[IPV6:]<port>] [global=][global|local|<hostname>]" if ($port !~ m/^\d+$/);
  if (defined $a->[4]) {
    $hash->{GLOBAL} = $a->[4];
  } elsif (exists $h->{global}) {
    $hash->{GLOBAL} = $h->{global};
  } else {
    $hash->{GLOBAL} = $tcpServAdr;
  }

  # open TCP server for HTTP API service
  my $ret = TcpServer_Open($hash, $pport, (($hash->{GLOBAL} eq 'local') ? undef : $hash->{GLOBAL}));
  if($ret && !$init_done) {
    Log3 $name, 1, "HTTPAPI $ret already exists";
    exit(1);
  }
  readingsSingleUpdate($hash, "state", "initialized", 1);
  Log3 $name, 2, "HTTPAPI $name initialized";
  return $ret;
}

sub HTTPAPI_Attr(@) {
  my ($cmd, $name, $aName, $aVal) = @_;
  if ($cmd eq "set") {
    if ($aName =~ "devicesCtrl") {
      if ($aVal !~ /^[A-Z_a-z0-9\,]+$/) {
        Log3 $name, 2, "HTTPAPI $name invalid reading list in attr $name $aName $aVal (only A-Z, a-z, 0-9, _ and , allowed)";
        return "Invalid reading name $aVal (only A-Z, a-z, 0-9, _ and , allowed)";
      }
      #addToDevAttrList($name, $aName);
    }
  }
  return undef;
}

sub HTTPAPI_CGI($$$) {
  # execute request to http://<host>:<port>/$infix?<cmd string>
  my ($hash, $name, $request) = @_;
  my $apiCmd;
  my $apiCmdString;
  my $fhemDevName;
  my $link;
  return($hash, 503, 'close', "text/plain; charset=utf-8", encode($encoding, "error=503 Service Unavailable")) if(IsDisabled($name));

  if($request =~ m/^(\/$infix)\/(set|get|read|readtimestamp|write)\?(.*)$/) {
    $link = $1;
    $apiCmd = $2;
    $apiCmdString = $3;

    # url decoding
    $request =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    #readingsSingleUpdate($defs{$name}, 'request', $request, 0);

    if ($apiCmdString =~ /&device(\=[^&]*)?(?=&|$)|^device(\=[^&]*)?(&|$)/) {
      $fhemDevName = substr(($1 // $2), 1);
      # url decoding
      $fhemDevName =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
      if (IsDevice($fhemDevName) && !IsDisabled($fhemDevName) && !IsIgnored($fhemDevName)) {
        # Control of the device allowed?
        my $devicesCtrl = AttrVal($name, 'devicesCtrl', undef);
        my $allowedDev;
        if (defined $devicesCtrl) {
          my @devicesCtrl = split(',', $devicesCtrl);
          foreach (@devicesCtrl) {
            next if($_ ne $fhemDevName);
            $allowedDev = $fhemDevName;
            last;
          }
          return($hash, 403, 'close', "text/plain; charset=utf-8", encode($encoding, "error=403 Forbidden,  $request > control of the device $fhemDevName not allowed")) if (!defined($allowedDev))
        }
        if ($apiCmd eq 'get') {
          my $getCmd;
          if ($apiCmdString =~ /&action(\=[^&]*)?(?=&|$)|^action(\=[^&]*)?(&|$)/) {
            $getCmd = substr(($1 // $2), 1);
            # url decoding
            $getCmd =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
            my $ret = CommandGet(undef, "$fhemDevName $getCmd");
            if ($ret) {
              return($hash, 200, 'close', "text/plain; charset=utf-8", encode($encoding, "$getCmd=$ret"))
            } else {
              return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > get $fhemDevName $getCmd"))
            }
          } else {
            return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > attribute action is missing"))
          }
        } elsif ($apiCmd =~ /^read|readtimestamp$/) {
          my $readingName;
          if ($apiCmdString =~ /&reading(\=[^&]*)?(?=&|$)|^reading(\=[^&]*)?(&|$)/) {
            $readingName = substr(($1 // $2), 1);
            # url decoding
            $readingName =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
            my $readingVal = $apiCmd eq 'readtimestamp' ? ReadingsTimestamp($fhemDevName, $readingName, undef) : ReadingsVal($fhemDevName, $readingName, undef);
            #readingsSingleUpdate($defs{$name}, 'reponse', "$readingName=$readingVal", 1);
            if (defined $readingVal) {
              return($hash, 200, 'close', "text/plain; charset=utf-8", encode($encoding, "$readingName=$readingVal"));
            } else {
              return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > reading $readingName unknown"))
            }
          } else {
            return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > attribute reading is missing"))
          }

        } elsif ($apiCmd eq 'set') {
          my $setCmd;
          if ($apiCmdString =~ /&action(\=[^&]*)?(?=&|$)|^action(\=[^&]*)?(&|$)/) {
            $setCmd = substr(($1 // $2), 1);
            # url decoding
            $setCmd =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
            #my $ret = CommandSet(undef, "$fhemDevName $setCmd");
            #my $ret = AnalyzeCommand($defs{$hash->{SNAME}}, "set $fhemDevName $setCmd");
            my $ret = AnalyzeCommand($defs{$name}, "set $fhemDevName $setCmd");
            if ($ret) {
              return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > $ret"))
            } else {
              return($hash, 200, 'close', "text/plain; charset=utf-8", encode($encoding, "$fhemDevName=$setCmd"))
            }
          } else {
            return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > attribute action is missing"))
          }

        } elsif ($apiCmd eq 'write') {
          my $readingName;
          if ($apiCmdString =~ /&reading(\=[^&]*)?(?=&|$)|^reading(\=[^&]*)?(&|$)/) {
            $readingName = substr(($1 // $2), 1);
            # url decoding
            $readingName =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
            my $readingVal;

            if ($apiCmdString =~ /&value(\=[^&]*)?(?=&|$)|^value(\=[^&]*)?(&|$)/) {
              $readingVal = substr(($1 // $2), 1);
              # url decoding
              $readingVal =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
              if ($readingVal ne '') {
                ($readingName, $readingVal) = split(/:\s?/, readingsSingleUpdate($defs{$fhemDevName}, $readingName, $readingVal, 1));
                return($hash, 200, 'close', "text/plain; charset=utf-8", encode($encoding, "$readingName=$readingVal"))
              } else {
                readingsDelete($defs{$fhemDevName}, $readingName);
                return($hash, 200, 'close', "text/plain; charset=utf-8", encode($encoding, "$readingName="))
              }
            } else {
              # delete reading if value is not found
              readingsDelete($defs{$fhemDevName}, $readingName);
              return($hash, 200, 'close', "text/plain; charset=utf-8", encode($encoding, "$readingName="))
            }
          } else {
            return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > attribute reading is missing"))
          }
        } else {
          return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > action $apiCmd unknown"))
        }
      } else {
        return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > device $fhemDevName unknown, disabled or ignored by the user"))
      }
    } else {
      return($hash, 400, 'close', "text/plain; charset=utf-8", encode($encoding, "error=400 Bad Request, $request > attribute device missing"))
    }

  } else {
    return HTTPAPI_CommandRef($hash);
  }
  return;
}

sub HTTPAPI_CommandRef($) {
  my ($hash) = @_;
  my $fileName = $gPath . '/02_HTTPAPI.pm';
  my ($err, @contents) = FileRead({FileName => $fileName, ForceType => 'file'});
  return ($hash, 404, 'close', "text/plain; charset=utf-8", encode($encoding, "error=404 Not Found, file $fileName not found")) if ($err);
  my $contents = join("\n", @contents);
  $contents =~ /\n=begin.html([\s\S]*)\n=end.html/gs;
  return ($hash, 200, 'close', "text/html; charset=utf-8", encode($encoding, $1));
}

sub HTTPAPI_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # accept request and create a child
  if ($hash->{SERVERSOCKET}) {
    my $chash = TcpServer_Accept($hash, "HTTPAPI");
    return if (!$chash);
    $chash->{encoding} = $encoding;
    $chash->{CD}->blocking(0);
    return;
  }

  # read data
  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 2048);

  # connection error, 0=EOF, undef=error
  if (!defined($ret) || $ret <= 0) {
    TcpServer_Close($hash, 1);
    delete $hash->{BUF};
    return;
  }

  $hash->{BUF} .= $buf;
  my $content = '';
  my $contentType = '';

  while(exists($hash->{BUF}) && length($hash->{BUF}) > 0) {
    if (!$hash->{HDR}) {
      last if ($hash->{BUF} !~ m/^(.*?)(\n\n|\r\n\r\n)(.*)$/s);
      $hash->{HDR} = $1;
      $hash->{BUF} = $3;
      if ($hash->{HDR} =~ m/Content-Length:\s*([^\r\n]*)/si) {
        $hash->{CONTENT_LENGTH} = $1;
      }
      if ($hash->{HDR} =~ m/Content-Type:\s*([^\r\n]*)/si) {
        $contentType = $1;
      }
    }

    if ($hash->{CONTENT_LENGTH}) {
      return if (length($hash->{BUF}) < $hash->{CONTENT_LENGTH});
      $content = substr($hash->{BUF}, 0, $hash->{CONTENT_LENGTH});
      $hash->{BUF} = substr($hash->{BUF}, $hash->{CONTENT_LENGTH});
    }
    my @httpheader = split(/[\r\n]+/, $hash->{HDR});
    my ($method, $url, $httpvers) = split(" ", $httpheader[0], 3) if ($httpheader[0]);
    $method = "" if (!$method);
    delete ($hash->{HDR});

    if ($method !~ m/^(GET|POST)$/i) {
      $ret = HTTPAPI_TcpServerWrite($hash, 405, 'close', "text/plain; charset=utf-8", "error=405 Method Not Allowed");
      delete $hash->{CONTENT_LENGTH};
      next;
    } elsif ($method eq 'POST' && $contentType ne 'application/xml') {
      $ret = HTTPAPI_TcpServerWrite($hash, 400, 'close', "text/plain; charset=utf-8", "error=400 Bad Request");
      delete $hash->{CONTENT_LENGTH};
      next;
    } elsif ($url eq "/favicon.ico") {
      $ret = HTTPAPI_TcpServerWrite($hash, 404, 'close', "text/plain; charset=utf-8", "error=404 Not Found");
      delete $hash->{CONTENT_LENGTH};
      next;
    } elsif ($url !~ m/\/$infix\//i) {
      $ret = HTTPAPI_TcpServerWrite($hash, 400, 'close', "text/plain; charset=utf-8", "error=400 Bad Request");
      delete $hash->{CONTENT_LENGTH};
      next;
    } else {
      $url =~ m/\/$infix\/(.*)\?(.*)$/i;
      my ($requestCmd, $cmdString) = ($1, $2);
      # CGI Aufruf
      $ret = HTTPAPI_TcpServerWrite(HTTPAPI_CGI($hash, $name, $url));
      delete $hash->{CONTENT_LENGTH};
      next:
    }

  }
  TcpServer_Close($hash, 1);
  delete $hash->{BUF};
  return;
}

sub HTTPAPI_TcpServerWrite($$$$$) {
  my ($hash, $httpState, $connection, $contentType, $content) = @_;
  my ($contentLength, $header) = (0, "HTTP/1.1 ");
  my %httpState = (
    200 => '200 OK',
    400 => '400 Bad Request',
    403 => '403 Forbidden',
    404 => '404 Not Found',
    405 => '405 Method Not Allowed',
    503 => '503 Service Unavailable'
  );
  $content = $content // '';
  $contentLength = length($content);
  $header .= "$httpState{$httpState}\r\nContent-Length: $contentLength\r\n";
  $header .= "Allow: GET, POST\r\n" if ($httpState == 405);
  $header .= "Connection: $connection\r\n" if (defined $connection);
  $header .= "Content-Type: $contentType\r\n" if (defined $contentType);
  $header .= "\r\n";
  return TcpServer_WriteBlocking($hash, $header . $content);
}

sub HTTPAPI_Undef($) {
  my ($hash) = @_;
  return TcpServer_Close($hash, 1);
}

1;

=pod
=item device
=item summary HTTP API server that executes set/get commands and sets/reads readings
=item summary_DE HTTP API-Server, der set-/get-Befehle ausführt und Readings setzt/liest
=begin html

<a id="HTTPAPI"></a>
<h3>HTTPAPI</h3>
<ul>
  HTTPAPI is a compact HTML API server that performs http requests to execute set and get commands
  and reads and writes readings.<br><br>

  <a id="HTTPAPI-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HTTPAPI [infix=][&lt;apiName&gt;] [port=][[IPV6:]&lt;port&gt;] [global=][global|local|&lt;hostname&gt;]</code><br><br>

    Defines the HTTP API server.<br>
    <ul>
    <li>
      <code>&lt;apiName&gt;</code> is the portion behind the base URL (usually <code>http://&lt;hostname&gt;:&lt;port&gt;/&lt;apiName&gt;</code>).<br>
      <code>[&lt;apiName&gt] = api</code> is default.
    </li>
    <li>
    <code>[[IPV6:]&lt;port&gt;] = 8087</code> is default.<br>
    To use IPV6, specify the portNumber as <code>IPV6:&lt;number&gt;</code>, in this case the perl module IO::Socket:INET6 will be requested.
    On Linux you may have to install it with <code>cpan -i IO::Socket::INET6</code> or <code>apt-get libio-socket-inet6-perl</code>.
    </li>
    <li>
    <code>[global|local|&lt;hostname&gt;] = global</code> is default.<br>
    If the parameter is set to local, the server will only listen to localhost connections. If is set to global, the server
    will listen on all interfaces, else it wil try to resolve the parameter as a hostname, and listen only on this interface.
    </li>
    </ul>
    <br>

    Example:
    <ul>
      <code>define httpapi HTTPAPI</code> (Configuration with default values)<br>
      or<br>
      <code>define httpapi HTTPAPI api 8087 global</code><br>
      or<br>
      <code>define httpapi HTTPAPI infix=api1 port=8089 global=local</code><br>
    </ul>
  </ul>
  <br><br>

  <a id="HTTPAPI-get"></a>
  <b>Get</b>
  <ul>
    <li>API command line for executing a get command<br>
      Request:
      <ul>
        <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/get?device=&lt;devname&gt;&action=&lt;cmd&gt;</code><br>
      </ul>
      Response:
      <ul>
        <code>&lt;action&gt;=&lt;response&gt;|error=&lt;error message&gt;</code><br>
      </ul>
    </li>
  </ul>
  <br><br>

  <a id="HTTPAPI-set"></a>
  <b>Set</b>
  <ul>
    <li>API command line for executing a set command<br>
      Request:
      <ul>
        <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/set?device=&lt;devname&gt;&action=&lt;cmd&gt;</code><br>
      </ul>
      Response:
      <ul>
        <code>&lt;device&gt;=&lt;cmd&gt;|error=&lt;error message&gt;</code><br>
      </ul>
    </li>
  </ul>
  <br><br>

  <a id="HTTPAPI-events"></a>
  <b>Generated events</b>
  <ul>
    <li>API command line for setting a reading<br>
      Request:
      <ul>
        <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/write?device=&lt;devname&gt;&reading=&lt;name&gt;&value=&lt;val&gt;</code><br>
      </ul>
      Response:
      <ul>
        <code>&lt;reading name&gt;=&lt;val&gt;|error=&lt;error message&gt;</code><br>
      </ul>
    </li>
    <li>API command line for querying a reading<br>
      Request:
      <ul>
        <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/read?device=&lt;devname&gt;&reading=&lt;name&gt;</code><br>
      </ul>
      Response:
      <ul>
        <code>&lt;reading name&gt;=&lt;val&gt;|error=&lt;error message&gt;</code><br>
      </ul>
    </li>
    <li>API command line for querying the timestamp of a reading<br>
      Request:
      <ul>
        <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/readtimestamp?device=&lt;devname&gt;&reading=&lt;name&gt;</code><br>
      </ul>
      Response:
      <ul>
        <code>&lt;reading name&gt;=&lt;timestamp&gt;|error=&lt;error message&gt;</code><br>
      </ul>
    </li>
    <li>API command line for deleting a reading<br>
      Request:
      <ul>
        <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/write?device=&lt;devname&gt;&reading=&lt;name&gt;&value=</code><br>
        <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/write?device=&lt;devname&gt;&reading=&lt;name&gt;</code><br>
      </ul>
      Response:
      <ul>
        <code>&lt;reading name&gt;=|error=&lt;error message&gt;</code><br>
      </ul>
    </li>
  </ul>
  <br><br>

  <b>Usage information</b>
  <ul>
    <li>All links are relative to <code>http://&lt;ip-addr&gt;:&lt;port&gt;/</code>.</li>
    <li>Commands are not executed if the disable or ignore attribute of the device is set. See also <a href="#HTTPAPI-attr-devicesCtrl">devicesCtrl</a>.</li>
    <li>The <code>http://&lt;ip-addr&gt;:&lt;port&gt;/&lt;apiName&gt;/</code> command displays the module-specific commandref.</li>
    <li>The response message is encoded to UTF-8.</li>
  </ul>
  <br><br>

  <a id="HTTPAPI-attr"></a>
  <b>Attributes</b>
  <ul>
   <li><a id="HTTPAPI-attr-devicesCtrl">devicesCtrl</a> &lt;device_1&gt;,...,&lt;device_n&gt;,
    A comma separated list all devices to be controlled.<br>
    [devicesCtrl] = &lt; &gt; is default, all devices can be controlled.
    </li>
    <li><a href="#disable">disable</a> 0|1<br>
      If applied commands will not be executed.
    </li>
    <li><a href="#verbose">verbose</a> 0...5
    </li>
  </ul>
</ul>

=end html
=cut

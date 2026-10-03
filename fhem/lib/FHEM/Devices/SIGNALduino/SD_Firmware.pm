# $Id$
package FHEM::Devices::SIGNALduino::SD_Firmware;

use strict;
use warnings;
use Carp;
use Exporter qw(import);
use Symbol 'gensym';
use Time::HiRes qw(gettimeofday);
use File::Spec;
use IPC::Open3;

our $VERSION = "0.01";

use constant {
  SDUINO_ESP_FLASH_TIMEOUT => 120,          # an OTA upload takes considerably longer than a request
  SDUINO_ESP_REBOOT_WAIT   => 15,           # the device restarts before it answers again
  SDUINO_ESP_MAX_IMAGE     => 4 * 1024 * 1024,  # larger than any esp image, guards against a wrong file
};

our @EXPORT_OK = qw(
  SIGNALduino_flashLogName
  SIGNALduino_flashLogFile
  SIGNALduino_avrdude
  SIGNALduino_EspFlash
  SIGNALduino_EspFlashResponse
  SIGNALduino_EspReopen
  SIGNALduino_PrepareFlash
  SIGNALduino_Set_flash
  SIGNALduino_Get_availableFirmware
  SIGNALduino_ParseHttpResponse
  SIGNALduino_querygithubreleases
  SIGNALduino_githubParseHttpResponse
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );


############################# package main
## Bare name of the flash log, used for the FileLog_logWrapper URL behind the
## "Last Flashlog" menu entry.
sub SIGNALduino_flashLogName {
  my $hash = shift;

  return "$hash->{TYPE}-Flash.log";
}

############################# package main
## Full path of the flash log. avrdude writes it and SIGNALduino_FW_Detail decides
## by it whether to offer the menu entry, so both have to derive it the same way.
## catfile inserts exactly one separator: "logdir" may or may not carry one, and
## plain concatenation turned "/var/log/fhem" into "/var/log/fhemSIGNALduino-Flash.log".
sub SIGNALduino_flashLogFile {
  my $hash = shift;

  return File::Spec->catfile(main::AttrVal('global', 'logdir', './log/'), SIGNALduino_flashLogName($hash));
}

############################# package main
## Runs the flash command and returns its exit status. Everything the call needs -
## the shell (the nano command chains two attempts with ||) and the default SIGCHLD
## handling - is kept together here, separate from the evaluation of the result.
sub _run_avrdude {
  my $cmd = shift;

  local $SIG{CHLD} = 'DEFAULT';
  qx($cmd);

  return $?;
}

############################# package main
sub SIGNALduino_avrdude {
  my $name = shift;
  my $hash = $main::defs{$name};

  if (defined($hash->{helper}{stty_pid}))
  {
    waitpid( $hash->{helper}{stty_pid}, 0 );
    delete ( $hash->{helper}{stty_pid});
  }

  main::readingsSingleUpdate($hash,'state','FIRMWARE UPDATE running',1);
  $hash->{helper}{avrdudelogs} .= "$name closed\n";
  my $logFile = SIGNALduino_flashLogFile($hash);

  if (-e $logFile) {
    unlink $logFile;
  }

  $hash->{helper}{avrdudecmd} =~ s/\Q[LOGFILE]\E/$logFile/g;
  delete($hash->{FLASH_RESULT}) if (exists($hash->{FLASH_RESULT}));

  my $exitStatus = _run_avrdude($hash->{helper}{avrdudecmd});

  if ($exitStatus != 0 )
  {
    main::readingsSingleUpdate($hash,'state','FIRMWARE UPDATE with error',1);    # processed in tests
    $hash->{logMethod}->($name ,3, "$name: avrdude, ERROR: avrdude exited with error $exitStatus");
    if (defined $main::FW_wname)
    {
      main::FW_directNotify("FILTER=$name", "FHEMWEB:$main::FW_wname", "FW_okDialog('ERROR: avrdude exited with error, for details see last flashlog.')", '');
    }
    $hash->{FLASH_RESULT}='ERROR: avrdude exited with error';              # processed in tests
  } else {
    $hash->{logMethod}->($name ,3, "$name: avrdude, Firmware update was successfull");
    main::readingsSingleUpdate($hash,'state','FIRMWARE UPDATE successfull',1);   # processed in tests
  }

  local $/=undef;
  if (-e $logFile) {
    open my $file, '<', $logFile;
    $hash->{helper}{avrdudelogs} .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
    $hash->{helper}{avrdudelogs} .= <$file>;
    $hash->{helper}{avrdudelogs} .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
    close $file;
  } else {
    $hash->{helper}{avrdudelogs} .= "WARNING: avrdude created no log file\n\n";
    main::readingsSingleUpdate($hash,'state','FIRMWARE UPDATE with error',1);
    $hash->{FLASH_RESULT}= 'WARNING: avrdude created no log file';         # processed in tests
  }

  main::DevIo_OpenDev($hash, 0, \&main::SIGNALduino_DoInit, \&main::SIGNALduino_Connect);
  $hash->{helper}{avrdudelogs} .= "$name reopen started\n";
  return $hash->{FLASH_RESULT};
}

############################# package main
## Where the firmware has to go: the "flashDevice" attribute when set, the address
## from the definition otherwise. Deliberately transport-neutral - avrdude spells a
## network address differently than, say, an OTA upload would, so the formatting is
## left to the caller.
sub _resolve_flash_target {
  my $hash = shift;

  my $dev = main::AttrVal($hash->{NAME}, 'flashDevice', q{});
  $dev = $hash->{DeviceName} if $dev eq q{};
  ($dev) = split m{@}xms, $dev;                        # strip a trailing @baudrate

  return $dev;
}

############################# package main
## The same address in avrdude's notation: a network address gets the "net:" prefix
## it needs, a device file is passed through untouched.
sub _avrdude_port {
  my $dev = shift;

  return $dev if $dev =~ m{\A net: }xms;               # already spelled out
  return "net:$dev" if $dev =~ m{\A [^:\s/\\]+ : \d+ \z}xms;   # host:port

  return $dev;
}

############################# package main
## True for an address that names a local device file rather than a network endpoint.
sub _is_local_device {
  my $target = shift;

  return $target =~ m{\A (?: / | [A-Za-z]: [\\/] | COM \d )}ixms ? 1 : 0;
}

## Guards against whitespace and control characters reaching the Host header. The address
## comes from an attribute or the definition, so it is trusted but not necessarily correct.
sub _is_valid_url {
  my $url = shift;

  return 0 if $url =~ m{[[:space:][:cntrl:]]}xms;

  return $url =~ m{\A https?:// [^/]+ / }ixms ? 1 : 0;
}

## Writes the collected protocol to the file SIGNALduino_FW_Detail offers as "Last Flashlog",
## so an ESP flash leaves the same trace as an avrdude run instead of the previous one.
sub _write_flash_log {
  my $hash = shift;

  my $logFile = SIGNALduino_flashLogFile($hash);
  open my $fh, '>', $logFile or do {
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: cannot write flash log $logFile: $!");
    return;
  };
  print {$fh} $hash->{helper}{avrdudelogs} // q{};
  close $fh;

  return;
}

## The OTA endpoint of an ESP. Its firmware runs the WiFiManager web portal permanently
## (startWebPortal with a non blocking config portal), which serves the form at /update but
## takes the upload at /u.
## A port is only kept when the user spelled the address out in flashDevice - the one from
## the definition is the telnet port the firmware listens on, not its web server.
sub _esp_update_url {
  my ($target, $from_attribute) = @_;

  return $target if $target =~ m{\A https?:// }ixms;   # a complete URL wins

  my ($host, $port) = $target =~ m{\A (.*) : (\d+) \z}xms;
  $host = $target if !defined $host;                   # no port in the address at all

  return "http://$host:$port/u" if $from_attribute && defined $port;

  return "http://$host/u";
}

############################# package main
## Builds the multipart/form-data body for the upload. Returns body and boundary; the
## caller needs the boundary for the Content-Type header.
sub _esp_multipart_body {
  my ($filename, $image) = @_;

  $filename =~ s{["\r\n]}{}gxms;   # must not break out of the header field

  my $boundary = sprintf 'SIGNALduinoFlash%08x%08x', int(rand(0xffffffff)), int(rand(0xffffffff));
  my $body = "--$boundary\r\n"
           . qq{Content-Disposition: form-data; name="update"; filename="$filename"\r\n}
           . "Content-Type: application/octet-stream\r\n\r\n"
           . $image
           . "\r\n--$boundary--\r\n";

  return ($body, $boundary);
}

############################# package main
sub SIGNALduino_EspFlash {
  my ($hash, $binFile) = @_;

  ref($hash) eq 'HASH' or carp 'SIGNALduino_EspFlash: parameter 1 is not a hash reference';

  my $name      = $hash->{NAME};
  my $attribute = main::AttrVal($name, 'flashDevice', q{});
  my $target    = _resolve_flash_target($hash);

  # An ESP on a serial line has no http endpoint. Without this the address would be turned
  # into a nonsensical URL and the device would be disconnected for nothing.
  if (_is_local_device($target))
  {
    $hash->{logMethod}->($name, 1, "$name: EspFlash, $target is a serial device, flashing over http needs a network address");
    $hash->{FLASH_RESULT} = "ERROR: $target is not reachable over http, an ESP is flashed over the network";
    return $hash->{FLASH_RESULT};
  }

  my $url = _esp_update_url($target, $attribute ne q{});
  if (!_is_valid_url($url))
  {
    $hash->{logMethod}->($name, 1, "$name: EspFlash, refusing to upload to malformed address $url");
    $hash->{FLASH_RESULT} = 'ERROR: address of the device is not a usable url';
    return $hash->{FLASH_RESULT};
  }

  open my $fh, '<', $binFile or do {
    my $error = $!;
    $hash->{logMethod}->($name, 1, "$name: EspFlash, cannot read firmware file $binFile: $error");
    $hash->{FLASH_RESULT} = "ERROR: cannot read $binFile";
    return $hash->{FLASH_RESULT};
  };
  binmode $fh;

  my $size = -s $fh // 0;
  if ($size <= 0 || $size > SDUINO_ESP_MAX_IMAGE)
  {
    close $fh;
    $hash->{logMethod}->($name, 1, "$name: EspFlash, implausible size of $binFile: $size bytes");
    $hash->{FLASH_RESULT} = "ERROR: implausible firmware size ($size bytes)";
    return $hash->{FLASH_RESULT};
  }

  my $image = do { local $/ = undef; <$fh> };
  close $fh;

  # HttpUtils runs the body through Encode::encode when "encoding unicode" is set, which
  # would turn every byte above 0x7f into two and corrupt the image silently.
  utf8::downgrade($image, 1);

  # Both ESP8266 and ESP32 images start with this magic byte. Catching it here saves a
  # pointless upload and the reboot that follows a rejected one.
  if (substr($image, 0, 1) ne "\xE9")
  {
    $hash->{logMethod}->($name, 1, "$name: EspFlash, $binFile does not look like an ESP firmware image");
    $hash->{FLASH_RESULT} = 'ERROR: not an ESP firmware image';
    return $hash->{FLASH_RESULT};
  }

  my ($filename) = $binFile =~ m{([^/\\]+)\z}xms;
  $filename //= 'firmware.bin';
  my ($body, $boundary) = _esp_multipart_body($filename, $image);

  $hash->{logMethod}->($name, 3, "$name: EspFlash, uploading $filename ($size bytes) to $url");
  $hash->{helper}{avrdudelogs} = "flashing ESP $name\n"
                               . "firmware: $binFile\n"
                               . "size: $size bytes\n"
                               . "url: $url\n\n";

  # The device reboots after a successful upload, so the operational connection has to go
  # before the upload rather than after it. DevState keeps the keepalive from resetting the
  # device mid upload: it only bails out on 'disconnected', and DevIo_CloseDev leaves it be.
  $hash->{DevState} = 'disconnected';
  main::DevIo_CloseDev($hash);
  main::readingsSingleUpdate($hash, 'state', 'FIRMWARE UPDATE running', 1);
  delete $hash->{FLASH_RESULT};

  main::HttpUtils_NonblockingGet({
    url      => $url,
    method   => 'POST',
    timeout  => SDUINO_ESP_FLASH_TIMEOUT,
    hash     => $hash,
    data     => $body,
    header   => "Content-Type: multipart/form-data; boundary=$boundary",
    callback => \&SIGNALduino_EspFlashResponse,
    command  => 'espflash',
    hideurl  => 1,   # the address may carry credentials, keep them out of the log
  });

  return;
}

############################# package main
## Evaluates the upload. WiFiManager answers with 200 in both cases and only differs in the
## page it returns, so the body decides - see HTTP_UPDATE_SUCCESS / HTTP_UPDATE_FAIL in
## wm_strings_en.h. On success the device restarts, hence the delayed reconnect.
sub SIGNALduino_EspFlashResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  # Scheduled before anything is evaluated: whatever happens below, the device has to be
  # picked up again, otherwise it stays offline until someone runs "set <device> reset".
  main::FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_ESP_REBOOT_WAIT, \&SIGNALduino_EspReopen, $name);

  $data //= q{};

  my $error;
  if ($err ne q{})
  {
    $error = "ERROR: firmware upload failed - $err";
    $hash->{logMethod}->($name, 1, "$name: EspFlashResponse, upload failed: $err");
  }
  elsif (defined $param->{code} && $param->{code} != 200)
  {
    $error = "ERROR: device answered with HTTP $param->{code}";
    $hash->{logMethod}->($name, 1, "$name: EspFlashResponse, device answered with HTTP $param->{code}");
  }
  elsif ($data !~ m{Update\s+successful}ixms)
  {
    # A rejected image is answered with 200 as well and only the page differs, so success
    # has to be stated explicitly. Anything else - the upload form, a captive portal, an
    # empty body because the device rebooted early - counts as failure rather than success.
    my ($reason) = $data =~ m{OTA \s+ Error: \s* ([\w\ .:,()/-]{0,200})}ixms;
    $reason //= $data =~ m{Update\s+failed}ixms ? 'no reason reported' : 'unexpected answer from the device';
    $error = "ERROR: device did not confirm the update - $reason";
    $hash->{logMethod}->($name, 1, "$name: EspFlashResponse, device did not confirm the update: $reason");
  }
  else
  {
    $hash->{logMethod}->($name, 3, "$name: EspFlashResponse, firmware update was successfull");
  }

  $hash->{helper}{avrdudelogs} .= "--- ESP ---------------------------------------------------------------------------------\n";
  $hash->{helper}{avrdudelogs} .= $error // 'Update successful, device rebooting';
  $hash->{helper}{avrdudelogs} .= "\n\n";
  _write_flash_log($hash);

  if (defined $error)
  {
    $hash->{FLASH_RESULT} = $error;                                              # processed in tests
    main::readingsSingleUpdate($hash, 'state', 'FIRMWARE UPDATE with error', 1); # processed in tests
    if (defined $main::FW_wname)
    {
      # The reason comes from the device, so it is escaped before it ends up inside a
      # javascript string literal.
      my $dialog = $error;
      $dialog =~ s{([\\'])}{\\$1}gxms;
      $dialog =~ s{\s+}{ }gxms;
      main::FW_directNotify("FILTER=$name", "#FHEMWEB:$main::FW_wname", "FW_okDialog('$dialog')", q{});
    }
  }
  else
  {
    main::readingsSingleUpdate($hash, 'state', 'FIRMWARE UPDATE successfull', 1); # processed in tests
  }

  return;
}

############################# package main
sub SIGNALduino_EspReopen {
  my $name = shift;
  my $hash = $main::defs{$name};

  return if !defined $hash;

  main::DevIo_OpenDev($hash, 0, \&main::SIGNALduino_DoInit, \&main::SIGNALduino_Connect);
  $hash->{helper}{avrdudelogs} .= "$name reopen started\n";

  return;
}

############################# package main
sub SIGNALduino_PrepareFlash {
  my ($hash,$hexFile) = @_;

  ref($hash) eq 'HASH' or carp "SIGNALduino_PrepareFlash: parameter 1 is not a hash reference";

  my $name=$hash->{NAME};
  my $hardware=main::AttrVal($name,'hardware','');
  my $port = _avrdude_port(_resolve_flash_target($hash));
  my $baudrate= 57600;
  my $log = '';
  my $avrdudefound=0;
  my $tool_name = 'avrdude';
  my $path_separator = ':';
  if ($^O eq 'MSWin32') {
    $tool_name .= '.exe';
    $path_separator = ';';
  }
  for my $path ( split /$path_separator/, $ENV{PATH} ) {
    if ( -f "$path/$tool_name" && -x _ ) {
      $avrdudefound=1;
      last;
    }
  }
  $hash->{logMethod}->($name, 5, "$name: PrepareFlash, avrdude found = $avrdudefound");
  return 'avrdude is not installed. Please provide avrdude tool example: sudo apt-get install avrdude' if($avrdudefound == 0);

  $log .= "flashing Arduino $name\n";
  $log .= "hex file: $hexFile\n";
  $log .= "port: $port\n";

  # prepare default Flashcommand
  my $defaultflashCommand = ($hardware eq 'radinoCC1101'
    ? 'avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]'
    : 'avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]');

  # get User defined Flashcommand
  my $flashCommand = main::AttrVal($name,'flashCommand',$defaultflashCommand);

  if ($defaultflashCommand eq $flashCommand)  {
    $hash->{logMethod}->($name, 5, "$name: PrepareFlash, standard flashCommand is used to flash.");
  } else {
    $hash->{logMethod}->($name, 3, "$name: PrepareFlash, custom flashCommand is manual defined! $flashCommand");
  }

  main::DevIo_CloseDev($hash);
  if ($hardware eq 'radinoCC1101' && $^O eq 'linux' && $port =~ m{\A net: }xms) {
    # stty needs a device file, and the usb id rewrite below has no meaning for a
    # network address. With ser2net the reset comes from reopening the serial port
    # on the server side anyway.
    $hash->{logMethod}->($name, 3, "$name: PrepareFlash, skipping stty reset for $hardware, $port is a network device");
  }
  elsif ($hardware eq 'radinoCC1101' && $^O eq 'linux') {
    $hash->{logMethod}->($name, 3, "$name: PrepareFlash, forcing special reset for $hardware on $port");
    # Mit dem Linux-Kommando 'stty' die Port-Einstellungen setzen

    my($chld_out, $chld_in);
    # open3 only creates a handle of its own for stdin and stdout. An undefined
    # third argument means "send stderr to stdout", and $chld_err stays undef -
    # reading from it then warns instead of collecting stty's error output.
    my $chld_err = gensym;
    my $pid;
    eval {
      $pid = IPC::Open3::open3($chld_in,$chld_out, $chld_err,  "stty -F $port ospeed 1200 ispeed 1200");
      close($chld_in);  # give end of file to kid, or feed him
    };
    if ($@) {
      $hash->{helper}{stty_output}=$@;
    } else {
      my @outlines = <$chld_out>;              # read till EOF
      my @errlines = <$chld_err>;              # XXX: block potential if massive
      $hash->{helper}{stty_pid}=$pid;
      $hash->{helper}{stty_output} = join(' ',@outlines).join(' ',@errlines);
    }
    $port =~ s/usb-Unknown_radino/usb-In-Circuit_radino/g;
    $hash->{logMethod}->($name ,3, "$name: PrepareFlash, changed usb port to \"$port\" for avrdude flashcommand compatible with radino");
  }
  $hash->{helper}{avrdudecmd} = $flashCommand;
  $hash->{helper}{avrdudecmd}=~ s/\Q[PORT]\E/$port/g;
  $hash->{helper}{avrdudecmd} =~ s/\Q[HEXFILE]\E/$hexFile/g;
  if ($hardware =~ '^nano' && $^O eq 'linux') {
    $hash->{logMethod}->($name ,5, "$name: PrepareFlash, try additional flash with baudrate 115200 for optiboot");
    $hash->{helper}{avrdudecmd} = $hash->{helper}{avrdudecmd}." || ". $hash->{helper}{avrdudecmd};
    $hash->{helper}{avrdudecmd} =~ s/\Q[BAUDRATE]\E/$baudrate/;
    $baudrate=115200;
  }
  $hash->{helper}{avrdudecmd} =~ s/\Q[BAUDRATE]\E/$baudrate/;
  $log .= "command: $hash->{helper}{avrdudecmd}\n\n";
  main::FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + 1,\&SIGNALduino_avrdude,$name);
  $hash->{helper}{avrdudelogs} = $log;
  return ;
}

############################# package main
 sub SIGNALduino_Set_flash {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  return "Please define your hardware! (attr $name hardware <model of your receiver>) " if (main::AttrVal($name,'hardware','') eq '');

  my @args = @a[1..$#a];
  return 'ERROR: argument failed! flash [hexFile|url]' if (!$args[0]);

  my %http_param = (
    timeout    => 5,
    hash       => $hash,                                                     # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
    method     => 'GET',                                                     # Lesen von Inhalten
    header     => "User-Agent: perl_fhem\r\nAccept: application/json",       # Den Header gemaess abzufragender Daten aendern
  );

  my $hexFile = '';
  if( ( exists $hash->{additionalSets}{flash} ) && ( grep $args[0] eq $_ , split(',',$hash->{additionalSets}{flash}) ) )
  {
    $hash->{logMethod}->($hash, 3, "$name: Set_flash, $args[0] try to fetch github assets for tag $args[0]");
    my $ghurl = "https://api.github.com/repos/RFD-FHEM/SIGNALDuino/releases/tags/$args[0]";
    $hash->{logMethod}->($hash, 3, "$name: Set_flash, $args[0] try to fetch release $ghurl");

    $http_param{url}        = $ghurl;
    $http_param{callback}   = \&SIGNALduino_githubParseHttpResponse;  # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
    $http_param{command}    = 'getReleaseByTag';
    main::HttpUtils_NonblockingGet(\%http_param);                         # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    return;
  } elsif ($args[0] =~ m/^https?:\/\// ) {
    $http_param{url}        = $args[0];
    $http_param{callback}   = \&SIGNALduino_ParseHttpResponse;        # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
    $http_param{command}    = 'flash';
    main::HttpUtils_NonblockingGet(\%http_param);
    return;
  } else {
    $hexFile = $args[0];
  }
  $hash->{logMethod}->($name, 3, "$name: Set_flash, filename $hexFile provided, trying to flash");

  my $hardware = main::AttrVal($name,'hardware','');
  if ($hardware =~ m/(?:nano|mini|radino)/)
  {
    return SIGNALduino_PrepareFlash($hash,$hexFile);   # avrdude over serial or network
  } elsif ($hardware =~ m/\Aesp/ixms)
  {
    return SIGNALduino_EspFlash($hash,$hexFile);       # http upload to the device itself
  } else {
    if (defined $main::FW_wname)
    {
      main::FW_directNotify("FILTER=$name", "#FHEMWEB:$main::FW_wname", "FW_okDialog('<u>ERROR:</u><br>Sorry, flashing your $hardware is currently not supported.<br>The file is only downloaded in /opt/fhem/FHEM/firmware.')", '');
    }
    return "Sorry, Flashing your $hardware via Module is currently not supported.";    # processed in tests
  }
}

############################# package main
sub SIGNALduino_Get_availableFirmware {
  my ($hash, @a) = @_;

  if ( !main::HAS_JSON() )
  {
    $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: get $a[0] failed. Please install Perl module JSON. Example: sudo apt-get install libjson-perl");
    return "$a[0]: \n\nFetching from github is not possible. Please install JSON. Example:<br><code>sudo apt-get install libjson-perl</code>";
  }

  my $channel=main::AttrVal($hash->{NAME},'updateChannelFW','stable');
  my $hardware=main::AttrVal($hash->{NAME},'hardware',undef);

  my ($validHw) = $main::modules{$hash->{TYPE}}{AttrList} =~ /.*hardware:(.*?)\s/;
  $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: found availableFirmware for $validHw");

  if (!defined($hardware) || $validHw !~ /$hardware(?:,|$)/ )
  {
    $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: get $a[0] failed. Please set attribute hardware first");
    return "$a[0]: \n\n$hash->{NAME}: get $a[0] failed. Please choose one of $validHw attribute hardware";
  }
  SIGNALduino_querygithubreleases($hash);
  return "$a[0]: \n\nFetching $channel firmware versions for $hardware from github\n";
}

############################# package main
## Parses a HTTP Response for example for flash via http download
sub SIGNALduino_ParseHttpResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if($err ne '')                                              # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
  {
    $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, error while requesting ".$param->{url}." - $err");                  # Eintrag fuers Log
  }
  elsif($param->{code} eq '200' && $data ne '')               # wenn die Abfrage erfolgreich war ($data enthaelt die Ergebnisdaten des HTTP Aufrufes)
    {
      $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, url ".$param->{url}.' returned: '.length($data).' bytes Data');   # Eintrag fuers Log

      if ($param->{command} eq 'flash')
      {
        my $filename;

        if ($param->{httpheader} =~ /Content-Disposition: attachment;.?filename=\"?([-+.\w]+)?\"?/)
        {
          $filename = $1;
        } else {  # Filename via path if not specifyied via Content-Disposition
          $param->{path} =~ /\/([-+.\w]+)$/;    #(?:[^\/][\d\w\.]+)+$   \/([-+.\w]+)$
          $filename = $1;
        }
        $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, Downloaded $filename firmware from ".$param->{host});
        $hash->{logMethod}->($name, 5, "$name: ParseHttpResponse, Header = ".$param->{httpheader});

        $filename = 'FHEM/firmware/' . $filename;

        # This sub runs as a HttpUtils callback and nothing there catches a die(),
        # so a failed write has to abort the flash only, never the whole instance.
        my $file;
        if (!open($file, '>', $filename))
        {
          my $error = $!;
          $hash->{logMethod}->($name, 1, "$name: ParseHttpResponse, cannot write firmware file $filename: $error");
          if (defined $main::FW_wname)
          {
            main::FW_directNotify("FILTER=$name", "#FHEMWEB:$main::FW_wname", "FW_okDialog('<u>ERROR:</u><br>Could not write firmware file $filename:<br>$error')", '');
          }
          return;
        }
        print $file $data;
        close $file;

        # Den Flash Befehl mit der soebene heruntergeladenen Datei ausfuehren
        #SIGNALduino_Log3 $name, 3, "$name: ParseHttpResponse, calling set ".$param->{command}." $filename";        # Eintrag fuers Log

        my $set_return = main::SIGNALduino_Set($hash,$name,$param->{command},$filename); # $hash->{SetFn}
        if (defined($set_return))
        {
          $hash->{logMethod}->($name ,3, "$name: ParseHttpResponse, Error while flashing: $set_return");
        }
      }
    } else {
      $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, undefined error while requesting ".$param->{url}." - $err - code=".$param->{code});   # Eintrag fuers Log
    }
}

############################# package main
sub SIGNALduino_querygithubreleases {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $param = {
                url        => 'https://api.github.com/repos/RFD-FHEM/SIGNALDuino/releases',
                timeout    => 5,
                hash       => $hash,                                                    # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                method     => 'GET',                                                    # Lesen von Inhalten
                header     => "User-Agent: perl_fhem\r\nAccept: application/json",      # Den Header gemaess abzufragender Daten aendern
                callback   =>  \&SIGNALduino_githubParseHttpResponse,                   # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
                command    => "queryReleases"
              };

  main::HttpUtils_NonblockingGet($param);                                                     # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
}

############################# package main
#return -10 = hardeware attribute is not set
sub SIGNALduino_githubParseHttpResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $hardware=main::AttrVal($name,'hardware',undef);

  if($err ne '')                                                                                                        # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
  {
    $hash->{logMethod}->($name, 3, "$name: githubParseHttpResponse, error while requesting ".$param->{url}." - $err (command: $param->{command}");   # Eintrag fuers Log
    #readingsSingleUpdate($hash, 'fullResponse', 'ERROR');                                                              # Readings erzeugen
  }
  elsif($data ne '' && defined($hardware))                                                                              # wenn die Abfrage erfolgreich war ($data enthaelt die Ergebnisdaten des HTTP Aufrufes)
  {

    my $json_array = JSON::decode_json($data);
    #print  Dumper($json_array);
    if ($param->{command} eq 'queryReleases') {
      #Log3 $name, 3, "$name: githubParseHttpResponse, url ".$param->{url}." returned: $data";                          # Eintrag fuers Log

      my $releaselist='';
      if (ref($json_array) eq "ARRAY") {
        foreach my $item( @$json_array ) {
          next if (main::AttrVal($name,'updateChannelFW','stable') eq 'stable' && $item->{prerelease});

          #Debug ' item = '.Dumper($item);

          foreach my $asset (@{$item->{assets}})
          {
            next if ($asset->{name} !~ m/$hardware/i);
            $releaselist.=$item->{tag_name}.',' ;
            last;
          }
        }
      }

      $releaselist =~ s/,$//;
      $hash->{additionalSets}{flash} = $releaselist;
    } elsif ($param->{command} eq 'getReleaseByTag' && defined($hardware)) {
      #Debug ' json response = '.Dumper($json_array);

      my @fwfiles;
      foreach my $asset (@{$json_array->{assets}})
      {
        my %fileinfo;
        if ( $asset->{name} =~ m/$hardware/i)
        {
          $fileinfo{filename} = $asset->{name};
          $fileinfo{dlurl} = $asset->{browser_download_url};
          $fileinfo{create_date} = $asset->{created_at};
          #Debug ' firmwarefiles = '.Dumper(@fwfiles);
          push @fwfiles, \%fileinfo;

          my $set_return = main::SIGNALduino_Set($hash,$name,'flash',$asset->{browser_download_url}); # $hash->{SetFn
          if(defined($set_return))
          {
            $hash->{logMethod}->($name, 3, "$name: githubParseHttpResponse, Error while trying to download firmware: $set_return");
          }
          last;
        }
      }

    }
  } elsif (!defined($hardware))  {
    $hash->{logMethod}->($name, 5, "$name: githubParseHttpResponse, hardware is not defined");
  }
  # wenn
  # Damit ist die Abfrage zuende.
  # Evtl. einen InternalTimer neu schedulen
  if (defined $main::FW_wname)
  {
     main::FW_directNotify("FILTER=$name", "#FHEMWEB:$main::FW_wname", "location.reload('true')", '');
  }
  return 0;
}

1;

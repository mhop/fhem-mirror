###############################################################################
# $Id$
#
# this module is part of fhem under the same license
# copyright 2015, joerg herrmann
# 
# history
# initial checkin
#
###############################################################################
package main;

use strict;
use warnings;

use Time::HiRes qw(time);

my %typeText = (
  '62' => 'warm water',   # 
  '72' => 'cold water',   #
  '43' => 'heat meter',   # compact V
);
  
sub 
TechemWZ_Initialize(@) {
  my ($hash) = @_;

  # require "Broker.pm";
  
  $hash->{Match}      = "^b..446850[\\d]{8}..(?:43|45|62|72).*";

  $hash->{DefFn}      = "TechemWZ_Define";
  $hash->{UndefFn}    = "TechemWZ_Undef";
  $hash->{SetFn}      = "TechemWZ_Set";
  $hash->{GetFn}      = "TechemWZ_Get";
  $hash->{NotifyFn}   = "TechemWZ_Notify";
  $hash->{ParseFn}    = "TechemWZ_Parse";

  $hash->{AttrList}   = "".$readingFnAttributes;

  return undef;
}

sub
TechemWZ_Define(@) {
  my ($hash, $def) = @_;
  my ($name, $t, $id);
  ($name, $t, $id, $def) = split(/ /, $def,4);

  return "ID must have 8 digits" if ($id !~ /^\d{8}$/);
  return "ID $id already defined" if exists($modules{TechemWZ}{defptr}{$id});
  
  # house keeping
  if (exists($hash->{OLDDEF}) && ($hash->{DEF} ne $hash->{OLDDEF}) ) {
    my @a = split(/ /, $hash->{OLDDEF});
    delete($hash->{VERSION});
    delete($hash->{METER});
    delete($hash->{READINGS});
    delete($modules{TechemWZ}{defptr}{$a[0]});
    delete($hash->{helper}->{list});
  }
  
  # create crc table if required
  $data{WMBUS}{crc_table_13757} = TechemWZ_createCrcTable() unless (exists($data{WMBUS}{crc_table_13757}));

  $hash->{helper}->{listmode} = ($id eq '00000000')?1:0;
  $hash->{ID} = $id;
  $modules{TechemWZ}{defptr}{$id} = $hash;
  $hash->{FRIENDLY} = $def if (defined($def));

  # subscribe broadcast channels 
  # TechemWZ_subscribe($hash, 'foo');
  TechemWZ_Run($hash) if $init_done;
  return undef;
}

sub
TechemWZ_Undef(@) {
  my ($hash) = @_;
  my $id = $hash->{ID};
  delete($modules{TechemWZ}{defptr}{$id});
  return undef;
}

sub
TechemWZ_Set(@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;

  return undef;
}

sub
TechemWZ_Get(@) {
  my ($hash, $name, $cmd, @args) = @_;
  return undef unless ($hash->{helper}->{listmode});
  return "unknown command ($cmd): choose one of list" if ($cmd eq "?");
  return "unknown command ($cmd): choose one of list" if ($cmd ne "list");
 
  my $result = "";

  my $l = $hash->{helper}->{list};

  foreach my $key (sort { $l->{$a}->{msg}->{meter} <=> $l->{$b}->{msg}->{meter} } keys %{$l} ) {
    $result .= "$l->{$key}->{msg}->{long}\t";
    $result .=  $typeText{$l->{$key}->{msg}->{type}}."\t";
    $result .= "$l->{$key}->{msg}->{meter}\t";
    $result .= "$l->{$key}->{msg}->{rssi}\t\n";
  }

  return $result;
}

sub 
TechemWZ_Notify (@) {
  my ($hash, $ntfyDev) = @_;
  return unless (($ntfyDev->{TYPE} eq 'CUL') || ($ntfyDev->{TYPE} eq 'Global'));
  foreach my $event (@{$ntfyDev->{CHANGED}}) {
    my @e = split(' ', $event);
    next unless defined($e[0]);
    TechemWZ_Run($hash) if ($e[0] eq 'INITIALIZED');
    # patch CUL.pm
    TechemWZ_IOPatch($hash, $e[1]) if (($e[0] eq 'ATTR') && ($e[2] eq 'rfmode') && ($e[3] eq 'WMBus_T'));
    # disable receiver
    if (($e[0] eq 'ATTR') && ($e[2] eq 'rfmode') && ($e[3] ne 'WMBus_T')) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "standby (IO missing)", 1);
    readingsEndUpdate($hash, 1);
    }
  }
  return undef;
}

sub
TechemWZ_Receive(@) {
  my ($hash, $msg, $raw) = @_;
  	
  my @t = localtime(time);
  my ($ats, $ts);
  
  $hash->{VERSION} = $msg->{version};
  $hash->{METER} = $typeText{$msg->{type}};
  delete $hash->{CHANGETIME}; # clean up, workaround for fhem prior http://forum.fhem.de/index.php/topic,47474.msg391964.html#msg391964

  # day period changed
  $ats = ReadingsTimestamp($hash->{NAME},"current_period", "0");
  $ts = sprintf ("%02d-%02d-%02d 00:00:00", $msg->{actual}->{year}, $msg->{actual}->{month}, $msg->{actual}->{day});
  if ($ats ne $ts) {
    my $i;
    readingsBeginUpdate($hash);
    $hash->{".updateTimestamp"} = $ts;
    $i = $#{ $hash->{CHANGED} };
    readingsBulkUpdate($hash, "meter", $msg->{meter});
    $hash->{CHANGETIME}->[$#{ $hash->{CHANGED} }] = $ts if ($#{ $hash->{CHANGED} } != $i ); # only add ts if there is a event to
    $i = $#{ $hash->{CHANGED} };
    readingsBulkUpdate($hash, "current_period", $msg->{actualVal});
    $hash->{CHANGETIME}->[$#{ $hash->{CHANGED} }] = $ts if ($#{ $hash->{CHANGED} } != $i ); # only add ts if there is a event to
    readingsEndUpdate($hash, 1);
  }

  # billing period changed
  $ats = ReadingsTimestamp($hash->{NAME},"previous_period", "0");
  $ts = sprintf ("20%02d-%02d-%02d 00:00:00", $msg->{last}->{year}, $msg->{last}->{month}, $msg->{last}->{day});
  if ($ats ne $ts) {
    my $i;
    readingsBeginUpdate($hash);
    $hash->{".updateTimestamp"} = $ts;
    $i = $#{ $hash->{CHANGED} };
    readingsBulkUpdate($hash, "previous_period", $msg->{lastVal});
    $hash->{CHANGETIME}->[$#{ $hash->{CHANGED} }] = $ts if ($#{ $hash->{CHANGED} } != $i ); # only add ts if there is a event to
    readingsEndUpdate($hash, 1);
  }

  return undef;
}

sub 
TechemWZ_Run(@) {
  my ($hash) = @_;
  # find a CUL
  foreach my $d (keys %defs) {
    # live patch CUL.pm
    TechemWZ_IOPatch($hash, $d) if ($defs{$d}{TYPE} eq "CUL");
  }
  return undef;
}

# live patch CUL.pm, aka THE HACK
sub
TechemWZ_IOPatch(@) {
  my ($hash, $iodev) = @_;
  return undef unless (AttrVal($iodev, 'rfmode', '') eq 'WMBus_T');
  # see if already patched
  readingsSingleUpdate($hash, 'state', 'listening', 1);
  return undef if ($defs{$iodev}{Clients} =~ /TechemWZ/ );
  $defs{$iodev}{Clients} = ':TechemWZ'.$defs{$iodev}{Clients};
  $defs{$iodev}{'.clientArray'} = undef;
  return undef;
}

sub
TechemWZ_Parse(@) {

  my ($iohash, $msg) = @_;
  my ($message, $rssi);
  ($msg, $rssi) = split (/::/, $msg);
  $msg = TechemWZ_SanityCheck($msg);
  return '' unless $msg; 

  my @m = ($msg =~ m/../g);
  my @d;

  # parse
  ($message->{long}, $message->{short}) = TechemWZ_ParseID(@m);
  $message->{type} = TechemWZ_ParseSubType(@m);
  $message->{version} = TechemWZ_ParseSubVersion(@m);
  $message->{rssi} = ($rssi)?$rssi:"?";
  
  # metertype specific adjustment
  if ($message->{type} =~ /62|72/) {
    $message->{lastVal} = TechemWZ_ParseLastPeriod(@m);
    $message->{actualVal} = TechemWZ_ParseActualPeriod(@m);
    ($message->{actual}->{year}, $message->{actual}->{month}, $message->{actual}->{day}) = TechemWZ_ParseActualDate(@m);
    ($message->{last}->{year}, $message->{last}->{month}, $message->{last}->{day}) = TechemWZ_ParseLastDate(@m);
    $message->{lastVal} /= 10;
    $message->{actualVal} /= 10;
    $message->{meter} = $message->{lastVal} + $message->{actualVal};
  } elsif ($message->{type} =~ /43|45/) {
    $message->{lastVal} = TechemWZ_WMZ_Type1_ParseLastPeriod(@m);
    $message->{actualVal} = TechemWZ_WMZ_Type1_ParseActualPeriod(@m);
    ($message->{actual}->{year}, $message->{actual}->{month}, $message->{actual}->{day}) = TechemWZ_WMZ_Type1_ParseActualDate(@m);
    ($message->{last}->{year}, $message->{last}->{month}, $message->{last}->{day}) = TechemWZ_ParseLastDate(@m);
    $message->{meter} = $message->{lastVal} + $message->{actualVal};
  }
  
  # list
  if (exists( $modules{TechemWZ}{defptr}{'00000000'} ) && defined( $defs{$modules{TechemWZ}{defptr}{'00000000'}->{NAME}} )) { 
    my $listdev = $modules{TechemWZ}{defptr}{'00000000'};
    $listdev->{helper}->{list}->{$message->{long}}->{msg} = $message;
    push @d, $listdev->{NAME};
  }
  
  # dispatch
  if (exists( $modules{TechemWZ}{defptr}{$message->{long}})) {
    my $deviceHash = $modules{TechemWZ}{defptr}{$message->{long}};
    TechemWZ_Receive($deviceHash, $message);
    push @d, $deviceHash->{NAME};
  }
  
  if (defined($d[0])) {
    return (@d);
  } else {
    return (''); # discard neighbor devices
  }
}

sub
TechemWZ_SanityCheck(@) {

  my ($msg) = @_;
  my $rssi;
  my $t;
  my $dbg = 4;
    
  #($msg, $rssi) = split (/::/, $msg); 
  my @m = ((substr $msg,1) =~ m/../g);
  # at least 3 chars
  if (length($msg) < 3) {
    Log3 ("TechemWZ", $dbg, "msg incomplete $msg");
    return undef;
  }
  # msg length without crc blocks
  my $l = hex(substr $msg, 1, 2) + 1;
  # full crc payload blocks 
  my $fb = int(($l - 10) / 16);
  # remaining bytes ?
  my $rb = ($l - 10) % 16;
  # required len
  my $rl = $l + 2 + ($fb * 2) + (($rb)?2:0);

  if (($rl * 2) > (length($msg) -1)) {
    Log3 ("TechemWZ", $dbg, "msg incomplete $msg");
    return undef;
  }

  # CRC first 10 byte, then chunks of 16 byte then remaining
  if ((substr $msg, 21, 4) ne TechemWZ_crc16_13757(substr $msg, 1, 20)) {
    Log3 ("TechemWZ", $dbg, "crc error $msg");
    return undef;
  } else {
    $t = substr $msg, 3, 18;
  }
  for (my $i = 0; $i<$fb; $i++) {
    if ((substr $msg, 57 + ($i * 36), 4) ne TechemWZ_crc16_13757(substr $msg, 25 + ($i * 36), 32)) {
      Log3 ("TechemWZ", $dbg, "crc error $msg");
      return undef;
    } else {
      $t .= substr $msg, 25 + ($i * 36), 32;
    }
  }
  if ($rb) {
    if ((substr $msg, 25 + ($fb * 36) + ($rb * 2), 4) ne TechemWZ_crc16_13757(substr $msg, 25 + ($fb * 36), $rb * 2)) {
      Log3 ("TechemWZ", $dbg, "crc error $msg");
      return undef;
    } else {
      $t .= substr $msg, 25 + ($fb * 36), ($rb * 2);
    }
  }
  return $t;
}

sub
TechemWZ_ParseID(@) {
  my @m = @_;
  return ("$m[6]$m[5]$m[4]$m[3]", "$m[4]$m[3]"); 
}

sub
TechemWZ_ParseSubType(@) {
  my @m = @_;
  return "$m[8]"; 
}

sub
TechemWZ_ParseSubVersion(@) {
  my @m = @_;
  return "$m[7]"; 
}

sub
TechemWZ_ParseLastPeriod(@) {
  my @m = @_;
  return hex("$m[14]$m[13]"); 
}


sub
TechemWZ_ParseActualPeriod(@) {
  my @m = @_;
  return hex("$m[18]$m[17]"); 
}


sub
TechemWZ_ParseActualDate(@) {
  my @m = @_;
  my @t = localtime(time);
  my $b = hex("$m[16]$m[15]");
  my $d = ($b >> 4) & 0x1F;
  my $m = ($b >> 9) & 0x0F;
  my $y = $t[5] + 1900;
  return ($y, $m, $d);
}

sub
TechemWZ_ParseLastDate(@) {
  my @m = @_;
  my $b = hex("$m[12]$m[11]");
  my $d = ($b >> 0) & 0x1F;
  my $m = ($b >> 5) & 0x0F;
  my $y = ($b >> 9) & 0x3F;
  return ($y, $m, $d);
}

###############################################################################
#
# Compact 5 heatmeter
#
###############################################################################

sub
TechemWZ_WMZ_Type1_ParseLastPeriod(@) {
  my @m = @_;
  return hex("$m[15]$m[14]$m[13]"); 
}

sub
TechemWZ_WMZ_Type1_ParseActualPeriod(@) {
  my @m = @_;
  return hex("$m[19]$m[18]$m[17]"); 
}

sub
TechemWZ_WMZ_Type1_ParseActualDate(@) {
  my @m = @_;
  my @t = localtime(time);
  my $b = hex("$m[21]$m[20]");
  my $d = ($b >> 7) & 0x1F;
  my $m = (hex("$m[16]") >> 3) & 0x0F;
  my $y = $t[5] + 1900;
  return ($y, $m, $d);
}

sub 
TechemWZ_createCrcTable(@) {

  my $poly = 0x3D65;
  my $c;
  my @table;
  
  for (my $i=0; $i<256; $i++) {
    $c = ($i << 8); 

    for (my $j=0; $j<8; $j++) {
      if (($c & 0x8000) != 0) {
        $c = 0xFFFF & (($c << 1) ^ $poly);

      } else {
        $c <<= 1;

      }
    }
    $table[$i] = $c;
  }
  return \@table;
}

sub
TechemWZ_crc16_13757(@) {

  my ($msg) = @_;
  my @table = @{$data{WMBUS}{crc_table_13757}};

  my @in = split '', pack 'H*', $msg;
  my $crc = 0x0000;
  for (my $i=0; $i<int(@in); $i++) {
    $crc  = 0xffff & ( ($crc << 8) ^ $table[(($crc >> 8) ^ ord($in[$i]))] );

  }
  return sprintf ("%04lX", $crc ^ 0xFFFF);
}

# message bus ahead
# sub
#TechemWZ_subscribe(@) {
#  my ($hash, $topic) = @_;
#  broker::subscribe ($topic, $hash->{NAME}, \&TechemWZ_rcvBCST);
#  return undef;
#}

#sub
#TechemWZ_sendBCST(@) {
#  my ($hash, $topic, $msg) = @_;
#  broker::publish ($topic, $hash->{NAME}, $msg);
#  return undef;
#}

#sub
#TechemWZ_rcvBCST(@) {
#  my ($name, $topic, $sender, $msg) = @_;
#  my $hash = $defs{$name};
#  return undef;
#}

1;

=pod
=item summary This module reads the transmission of techem volume data meter.
=item summary_DE Das modul empfängt Daten von Techem Volumenzählern.
=begin html

<a name="TechemWZ"></a>
<h3>TechemWZ</h3>
<ul>
  This module reads the transmission of techem volume data meter. Currently supported device:
  <p>
  <ul>
    <li>Messkapsel-Wasserzähler radio 3 (cold, warm water)</li>
    <li>Messkapsel-Wärmemengenzähler compact V (heating energy)</li>
  </ul>
  <br>
  It will display
  <ul>
    <li>meter data for current billing period</li>
    <li>meter data for previous billing period including date of request</li>
    <li>cumulative meter data</li>
  </ul> 
  <br>
  It will require a CUL in WMBUS_T mode, although the CUL may temporary set into that mode. 
  The module keeps track of the CUL rfmode.
  <br>
  <br>
  <a name="TechemWZ_preliminary"></a>
  <b>preliminary</b>
  <p>
  Techem volume data meter does not transmit their printed meter ID. Instead they transmit the ID of the build in radio module.
  <p>
  Therefore a <b>"list-mode"</b> is available which collects all Techem meter device in range to help you find out the right one.
  That "list-mode" will be activated by defining a TechemWZ device with id "00000000". Let it run for a while and do a "get &lt;name&gt; list". 
  You will see a list of available (received) Techem device with their ID and meter data. Choose the right one (keep in mind that the meter reading reflects last midnight), note down their ID and define the appropriate device. After done the device with ID "00000000" can be removed.
  <br>
  <br>
  <a name="TechemWZ_Define"></a>
  <b>Define</b>
    <br>
    <code>define &lt;name&gt; TechemWZ &lt;8 digit ID&gt; [&lt;speaking name&gt;]</code>
    <ul>
      <li>ID: 8 digit ID (see list mode above)</li>
      <li>speaking name: (optional) human readable identification</li>
    </ul>
  <br>
  <a name="TechemWZ_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>current_period: meter data for current billing period
      <br><i>cumulated since the start of the current billing period. The reading will be updated once a day, after receiving the first update. Reading time will reflect the time of data (not the time where the data were received)</i></br>
    </li>
    <li>previous_period: meter data for last billing period
      <br><i>meter rading at the end of the last billing period. The reading will be updated if a new billing period starts. Reading time will reflect the last day of previous billing period (not the time where the data were received)</i></br>
    </li>
    <li>meter: cumulative meter data.
      <br><i>The same data that will be shown at the Techem (mechanical) display</i></br>
    </li>
    <br>
  </ul>
  <a name="TechemWZ_Get"></a>
  <b>Get</b>
  <ul>
    <li>list: print a list of available (received) Techem device with their ID and meter data
    <br><i><u>only available if device ID is "00000000" (list-mode)</u></i></br> 
    </li>
    <br>
  </ul>
  <a name="TechemWZ_Internals"></a>
  <b>Internals</b>
  <ul>
    <li>friendly: human readable identification of meter as specified by define</li>
    <br>
  </ul>
</ul>
=end html
=begin html_DE

<a name="TechemWZ"></a>
<h3>TechemWZ</h3>
<ul>
  Das modul empfängt Daten von Techem Volumenzählern. Unterstützte Zählertypen sind 
  <p>
  <ul>
    <li>Messkapsel-Wasserzähler radio 3 (Kalt-, Warmwasser)</li>
    <li>Messkapsel-Wärmemengenzähler compact V</li>
  </ul>
  <br>
  Empfangen werden:
  <ul>
    <li>Wert des aktuellen Abrechnungszeitraumes</li>
    <li>Wert des vorhergehenden Abrechnungszeitraumes einschließlich des Ablesedatums</li>
    <li>Gesamter aufgelaufener Verbrauchswert</li>
  </ul> 
  <br>
  Zum Empfang wird ein CUL im WMBUS_T mode benötigt. Dabei ist es ausreichend ihn vorrübergehend in diesen Modus zu schalten. Das Modul überwacht den rfmode aller verfügbaren CUL 
  <br>
  <br>
  <a name="TechemWZ_preliminary"></a>
  <b>Vorbereitung</b>
  <p>
  Leider übertragen die Techem Volumenzähler nicht die aufgedruckte Zählernummer. Übertragen wird nur die ID des eingebauten Funkmoduls. 
  <p>
  Das Modul stellt daher einen <b>"list-mode"</b> zur Verfügung. Damit kann eine Liste aller empfangenen Techem Volumenzähler anzeigt werden. Der "list-mode" wird aktiviert indem ein TechemWZ device mit der ID "00000000" definiert wird.
  Lassen Sie dieses device einige Zeit laufen damit es Informationen über die verfügbaren Zähler sammeln kann. Rufen Sie dann "get &lt;name&gt; list" auf um eine Liste der empfangenen Techem Volumenzähler, ihrer ID sowie der dazugehörigen Zählerstände zu sehen. Denken Sie daran das dies die Werte des letzten Tageswechsels sind.
  Notieren Sie sich anhand dieser Angaben die ID der gesuchten Zähler und definieren sie damit die entsprechenden TechemWZ device. Das list-mode device mit der ID "00000000" kann danach gefahrlos gelöscht werden.
  <br>
  <br>
  <a name="TechemWZ_Define"></a>
  <b>Define</b>
    <br>
    <code>define &lt;name&gt; TechemWZ &lt;8 digit ID&gt; [&lt;speaking name&gt;]</code>
    <ul>
      <li>ID: 8 stellige ID des Funkmoduls(siehe "list-mode")</li>
      <li>speaking name: (optional) Bezeichnung</li>
    </ul>
  <br>
  <a name="TechemWZ_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>current_period: Wert des aktuellen Abrechnungszeitraumes
      <br><i>Der kumulierte Verbrauch seid dem Start des aktuellen Abrechnungszeitraumes. Das reading wird einmal am Tag aktualisiert. Die Zeit kennzeichnet den Stand der Daten. (und nicht den Empfangszeitpunkt der Daten)</i></br>
    </li>
    <li>previous_period: Wert des letzten Ablesezeitpunktes 
      <br><i>Zählerstand zum letzten Abrechnungszeitpunkt. Das reading wird zum Ablesezeitpunkt aktualisiert. Die Zeit kennzeichnet das Ablesedatum (und nicht den Empfangszeitpunkt der Daten)</i></br>
    </li>
    <li>meter: gesamter Verbrauch.
      <br><i>Der Zählerstand so wie er an der (mechanischen) Anzeige des Zählers abgelesen werden kann</i></br>
    </li>
    <br>
  </ul>
  <a name="TechemWZ_Get"></a>
  <b>Get</b>
  <ul>
    <li>list: gibt eine Liste der empfangenen Techem Volumenzähler, ihrer ID sowie der dazugehörigen Zählerstände aus.
    <br><i><u>nur im "list-mode" (ID "00000000") verfügbar</u></i></br> 
    </li>
    <br>
  </ul>
  <a name="TechemWZ_Internals"></a>
  <b>Internals</b>
  <ul>
    <li>friendly: die beim define übergebene, zusätzliche Bezeichnung</li>
    <br>
  </ul>
</ul>
=end html_DE
=cut

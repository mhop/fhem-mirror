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
  '80' => 'Funkheizkostenverteiler data III'
);

sub 
TechemHKV_Initialize(@) {
  my ($hash) = @_;

  # require "Broker.pm";

  # TECHEM HKV
  # 61, 64 without T1 and T2
  $hash->{Match}      = "^b..446850[\\d]{8}(61|64|69|94)80.*";

  $hash->{DefFn}      = "TechemHKV_Define";
  $hash->{UndefFn}    = "TechemHKV_Undef";
  $hash->{SetFn}      = "TechemHKV_Set";
  $hash->{GetFn}      = "TechemHKV_Get";
  $hash->{NotifyFn}   = "TechemHKV_Notify";
  $hash->{ParseFn}    = "TechemHKV_Parse";

  $hash->{AttrList}   = "".$readingFnAttributes;

  return undef;
}

sub
TechemHKV_Define(@) {
  my ($hash, $def) = @_;
  my ($name, $t, $id);
  ($name, $t, $id, $def) = split(/ /, $def,4);

  return "ID must have 4 or 8 digits" if ($id !~ /^\d{4}(?:\d{4})?$/);

  $modules{TechemHKV}{defptr}{$id} = $hash;

  $hash->{FRIENDLY} = $def if (defined($def));
  $hash->{LONGID} = $id if (length($id) == 8);
  
  # create crc table if required
  $data{WMBUS}{crc_table_13757} = TechemHKV_createCrcTable() unless (exists($data{WMBUS}{crc_table_13757}));

  # subscribe broadcast channels 
  # TechemHKV_subscribe($hash, 'foo');
  # TechemHKV_Parse($hash, 'b334468500180560094804C3AA20F9F211202B038E80411FD0B81104E6D6265006554261A1B000000000000000001DCBC1706085875BCFADDBEC0F25480');
  TechemHKV_Run($hash) if $init_done;
  return undef;
}

sub
TechemHKV_Undef(@) {
  my ($hash) = @_;
  return undef;
};

sub
TechemHKV_Set(@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;

  return undef;
};

sub
TechemHKV_Get(@) {
  my ($hash) = @_;
  
  return undef;
};

sub 
TechemHKV_Notify (@) {
  my ($hash, $ntfyDev) = @_;
  return unless (($ntfyDev->{TYPE} =~ /CUL|STACKABLE/) || ($ntfyDev->{TYPE} eq 'Global'));
  foreach my $event (@{$ntfyDev->{CHANGED}}) {
    my @e = split(' ', $event);
    next unless defined($e[0]);
    TechemHKV_Run($hash) if ($e[0] eq 'INITIALIZED');
    # patch CUL.pm
    TechemHKV_IOPatch($hash, $e[1]) if (($e[0] eq 'ATTR') && ($e[2] eq 'rfmode') && ($e[3] eq 'WMBus_T'));
    # disable receiver
    if (($e[0] eq 'ATTR') && ($e[2] eq 'rfmode') && ($e[3] ne 'WMBus_T')) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", "standby (IO missing)", 1);
      readingsBulkUpdate($hash, "temp1", "--.--") if exists($hash->{READINGS}->{'temp1'}); # exlude versions without t1,t2
      readingsBulkUpdate($hash, "temp2", "--.--") if exists($hash->{READINGS}->{'temp2'});
      readingsEndUpdate($hash, 1);
    };
  };
  return undef;
};

sub
TechemHKV_Receive(@) {
  my ($hash, $msg) = @_;
	
  $hash->{LONGID} = $msg->{long} unless defined($hash->{LONGID});
  # TODO log collision if any ...	

  my @t = localtime(time);
  my ($ats, $ts);
  
  $hash->{VERSION} = $msg->{version};
  $hash->{METER} = $typeText{$msg->{type}};
  delete $hash->{CHANGETIME}; # clean up, workaround for fhem prior http://forum.fhem.de/index.php/topic,47474.msg391964.html#msg391964
  
  if (($msg->{version} || '') =~ /69|94/) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "temp1", $msg->{temp1});
    readingsBulkUpdate($hash, "temp2", $msg->{temp2});
    readingsEndUpdate($hash, 1);
  };

  # day period changed
  $ats = ReadingsTimestamp($hash->{NAME},"current_period", "0");
  $ts = sprintf ("%02d-%02d-%02d 00:00:00", $msg->{actual}->{year}, $msg->{actual}->{month}, $msg->{actual}->{day});
  if ($ats ne $ts) {
    my $i;
    readingsBeginUpdate($hash);
    $hash->{".updateTimestamp"} = $ts;
    $i = $#{ $hash->{CHANGED} };
    readingsBulkUpdate($hash, "current_period", $msg->{actualVal});
    $hash->{CHANGETIME}->[$#{ $hash->{CHANGED} }] = $ts if ($#{ $hash->{CHANGED} } != $i ); # only add ts if there is a event to
    readingsEndUpdate($hash, 1);
  };

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
  };
  return undef;
};

sub 
TechemHKV_Run(@) {
  my ($hash) = @_;
  # find a CUL
  foreach my $d (keys %defs) {
    # live patch CUL.pm
    TechemHKV_IOPatch($hash, $d) if ($defs{$d}{TYPE} =~ /CUL|STACKABLE/);
  }
  return undef;
}

# live patch CUL.pm, aka THE HACK
sub
TechemHKV_IOPatch(@) {
  my ($hash, $iodev) = @_;
  return undef unless (AttrVal($iodev, "rfmode", '') eq "WMBus_T");
  # see if already patched
  readingsSingleUpdate($hash, "state", "listening", 1);
  return undef if ($defs{$iodev}{Clients} =~ /TechemHKV/ );
  $defs{$iodev}{Clients} = ":TechemHKV".$defs{$iodev}{Clients};
  $defs{$iodev}{'.clientArray'} = undef;
  return undef;
}

sub
TechemHKV_Parse(@) {

  my ($iohash, $msg) = @_;
  my ($message, $rssi);
  ($msg, $rssi) = split (/::/, $msg);
  $msg = TechemHKV_SanityCheck($msg);
  return ('') unless $msg;
  
  $message->{long} = join '', reverse split /(..)/, substr $msg, 6, 8;
  $message->{short} = substr $message->{long}, 4, 4;
  $message->{version} = substr $msg, 14, 2;
  $message->{type} = substr $msg, 16, 2;
  
  # last_date
  #if ($message->{version} eq '94') {
  #  ($message->{last}->{year}, $message->{last}->{month}, $message->{last}->{day}) 
  #    = TechemHKV_ParseLastDate(join '', reverse split /(..)/, substr $msg, 24, 4);
  #} else {
    ($message->{last}->{year}, $message->{last}->{month}, $message->{last}->{day}) 
      = TechemHKV_ParseLastDate(join '', reverse split /(..)/, substr $msg, 22, 4);
  #}  
  # previous_period
  #if ($message->{version} eq '94') {
  #  $message->{lastVal} = hex(join '', reverse split /(..)/, substr $msg, 28, 4);
  #} else {
    $message->{lastVal} = hex(join '', reverse split /(..)/, substr $msg, 26, 4);
  #}
  
  # actual_date
  #if ($message->{version} eq '94') {
  #  ($message->{actual}->{year}, $message->{actual}->{month}, $message->{actual}->{day}) 
  #    = TechemHKV_ParseActualDate(join '', reverse split /(..)/, substr $msg, 32, 4);
  #} else {
    ($message->{actual}->{year}, $message->{actual}->{month}, $message->{actual}->{day}) 
      = TechemHKV_ParseActualDate(join '', reverse split /(..)/, substr $msg, 30, 4);
  #}
  # actual_period
  #if ($message->{version} eq '94') {
  #  $message->{actualVal} = hex(join '', reverse split /(..)/, substr $msg, 36, 4);
  #} else {
    $message->{actualVal} = hex(join '', reverse split /(..)/, substr $msg, 34, 4);
  #}
  
  # temp sensor 1
  if ($message->{version} eq '94') {
    $message->{temp1} = sprintf "%.2f", (hex(join '', reverse split /(..)/, substr $msg, 40, 4) / 100);
  } elsif ($message->{version} eq '69') {
    $message->{temp1} = sprintf "%.2f", (hex(join '', reverse split /(..)/, substr $msg, 38, 4) / 100);
  }

  # temp sensor 2
  if ($message->{version} eq '94') {
    $message->{temp2} = sprintf "%.2f", (hex(join '', reverse split /(..)/, substr $msg, 44, 4) / 100);
  } elsif ($message->{version} eq '69') {
    $message->{temp2} = sprintf "%.2f", (hex(join '', reverse split /(..)/, substr $msg, 42, 4) / 100);
  }
  
  # dispatch
  if (exists($modules{TechemHKV}{defptr}{$message->{long}})) {
    my $deviceHash = $modules{TechemHKV}{defptr}{$message->{long}};
    TechemHKV_Receive($deviceHash, $message);
    return ($deviceHash->{NAME});
  } elsif (exists($modules{TechemHKV}{defptr}{$message->{short}})) {
    my $deviceHash = $modules{TechemHKV}{defptr}{$message->{short}};
    $modules{TechemHKV}{defptr}{$message->{long}} = $deviceHash;
    delete($modules{TechemHKV}{defptr}{$message->{short}});
    TechemHKV_Receive($deviceHash, $message);
    return ($deviceHash->{NAME});
  }
  # broadcast

  return ('');
}

sub
TechemHKV_SanityCheck(@) {

  my ($msg) = @_;
  my $rssi;
  my $t;
  my $dbg = 4;
    
  #($msg, $rssi) = split (/::/, $msg); 
  my @m = ((substr $msg,1) =~ m/../g);
  # at least 3 chars
  if (length($msg) < 3) {
    Log3 ("TechemHKV", $dbg, "msg incomplete $msg");
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
    Log3 ("TechemHKV", $dbg, "msg incomplete $msg");
    return undef;
  }

  # CRC first 10 byte, then chunks of 16 byte then remaining
  if ((substr $msg, 21, 4) ne TechemHKV_crc16_13757(substr $msg, 1, 20)) {
    Log3 ("TechemHKV", $dbg, "crc error $msg");
    return undef;
  } else {
    $t = substr $msg, 3, 18;
  }
  for (my $i = 0; $i<$fb; $i++) {
    if ((substr $msg, 57 + ($i * 36), 4) ne TechemHKV_crc16_13757(substr $msg, 25 + ($i * 36), 32)) {
      Log3 ("TechemHKV", $dbg, "crc error $msg");
      return undef;
    } else {
      $t .= substr $msg, 25 + ($i * 36), 32;
    }
  }
  if ($rb) {
    if ((substr $msg, 25 + ($fb * 36) + ($rb * 2), 4) ne TechemHKV_crc16_13757(substr $msg, 25 + ($fb * 36), $rb * 2)) {
      Log3 ("TechemHKV", $dbg, "crc error $msg");
      return undef;
    } else {
      $t .= substr $msg, 25 + ($fb * 36), ($rb * 2);
    }
  }
  Log3 ("TechemHKV", $dbg, "ok $t");
  return $t;
}

sub
TechemHKV_ParseActualDate(@) {
  my $b = hex($_[0]);
  my @t = localtime(time);
  my $d = ($b >> 4) & 0x1F;
  my $m = ($b >> 9) & 0x0F;
  my $y = $t[5] + 1900;
  return ($y, $m, $d);
}

sub
TechemHKV_ParseLastDate(@) {
  my $b = hex($_[0]);
  my $d = ($b >> 0) & 0x1F;
  my $m = ($b >> 5) & 0x0F;
  my $y = ($b >> 9) & 0x3F;
  return ($y, $m, $d);
}

sub 
TechemHKV_createCrcTable(@) {

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
TechemHKV_crc16_13757(@) {

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
#TechemHKV_subscribe(@) {
#  my ($hash, $topic) = @_;
#  broker::subscribe ($topic, $hash->{NAME}, \&TechemHKV_rcvBCST);
#  return undef;
#}

#sub
#TechemHKV_sendBCST(@) {
#  my ($hash, $topic, $msg) = @_;
#  broker::publish ($topic, $hash->{NAME}, $msg);
#  return undef;
#}

#sub
#TechemHKV_rcvBCST(@) {
#  my ($name, $topic, $sender, $msg) = @_;
#  my $hash = $defs{$name};
#  return undef;
#}

1;

=pod
=item summary    read techem data meter for heating device.
=item summary_DE Anbindung von Techem Heizkostenverteilern.
=begin html

<a name="TechemHKV"></a>
<h3>TechemHKV</h3>
<ul>
  This module reads the transmission of techem data meter for heating device.
  <br><br>
  It will display
  <ul>
    <li>meter data for current billing period</li>
    <li>meter data for previous billing period including date of request</li>
    <li>both temperature sensors (if supported by data meter)</li>
  </ul> 
  <br>
  It will require a CUL in WMBUS_T mode, although the CUL may temporary set into that mode. 
  The module keeps track of the CUL rfmode.
  <br>
  <br>
  <a name="TechemHKV_Define"></a>
  <b>Define</b>
    <br>
    <code>define &lt;name&gt; TechemHKV &lt;4|8 digit ID&gt; [&lt;speaking name&gt;]</code>
    <ul>
      <li>ID: 4 digit ID displayed at techem or 8 digit as printed on bill</li>
      <li>speaking name: (optional) human readable identification</li>
    </ul>
  <br>
  <a name="TechemHKV_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>current_period: meter data for current billing period
      <br><i>unit-less data, cumulated since start of the current billing period. The reading will be updated once a day, after receiving the first update. Reading time will reflect the time of data (not the time where they were received)</i></br>
    </li>
    <li>previous_period: meter data for last billing period
      <br><i>unit-less data, sum of the last billing period. The reading will be updated only if a new billing period starts. Reading time will reflect the last day of previous billing period (not the time where they were received)</i></br>
    </li>
    <li>temp1: ambient temperature</li>
    <li>temp2: heater surface temperature</li>
    <br>
  </ul>
  <a name="TechemHKV_Internals"></a>
  <b>Internals</b>
  <ul>
    <li>friendly: human readable identification of meter as specified by define</li>
    <li>longID: 8 digit id of meter</li>
    <br>
  </ul>
</ul>
=end html

=begin html_DE

<a name="TechemHKV"></a>
<h3>TechemHKV</h3>
<ul>
  Das modul empfängt Daten eines Techem Heizkostenverteilers.
  <br><br>
  Empfangen werden
  <ul>
    <li>Wert des aktuellen Abrechnungszeitraumes</li>
    <li>Wert des vorhergehenden Abrechnungszeitraumes einschließlich des Ablesedatums</li>
    <li>Beide Temperatur Sensoren (sofern der Heizkostenverteiler sie sendet)</li>
  </ul> 
  <br>
  Zum Empfang wird ein CUL im WMBUS_T mode benötigt. Dabei ist es ausreichend ihn vorrübergehend in diesen Modus zu schalten.
  Das Modul überwacht den rfmode aller verfügbaren CUL
  <br>
  <br>
  <a name="TechemHKV_Define"></a>
  <b>Define</b>
    <br>
    <code>define &lt;name&gt; TechemHKV &lt;4|8 digit ID&gt; [&lt;speaking name&gt;]</code>
    <ul>
      <li>ID: 4 Ziffern wie auf dem Heizkostenverteiler angezeigt oder 8 Ziffern aus der Abrechnung</li>
      <li>speaking name: (optional) Bezeichnung</li>
    </ul>
  <br>
  <a name="TechemHKV_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>current_period: Wert des aktuellen Abrechnungszeitraumes
      <br><i>Der kumulierte (einheitenlose) Verbrauch seid dem Start des aktuellen Abrechnungszeitraumes. Das reading wird einmal am Tag aktualisiert. Die Zeit kennzeichnet den Stand der Daten. (und nicht den Empfangszeitpunkt der Daten)</i></br>
    </li>
    <li>previous_period: Summe des letzten Abrechnungszeitraum
      <br><i>Die (einheitenlose) Summe der Verbauchs im gesamten letzten Abrechnungszeitraum. Das reading wird jeweils zu Beginn eines neuen Abrechnungszeitraumes aktualisiert. Die Zeit kennzeichnet das Ablesedatum also das Ende des vorherigen Abrechnugszeitraumes. (und nicht den Empfangszeitpunkt der Daten)</i></br>
    </li>
    <li>temp1: Umgebungstemperatur</li>
    <li>temp2: Oberflächentemperatur des Heizkörpers</li>
    <br>
  </ul>
  <a name="TechemHKV_Internals"></a>
  <b>Internals</b>
  <ul>
    <li>friendly: die beim define übergebene, zusätzliche Bezeichnung</li>
    <li>longID: 8 Ziffern ID des Heizkostenverteilers</li>
    <br>
  </ul>
</ul>

=end html_DE
=cut


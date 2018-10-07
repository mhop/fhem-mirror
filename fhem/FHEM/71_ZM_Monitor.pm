##############################################################################
#
#     71_ZM_Monitor.pm
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
# This module is designed to work as a logical device in connection with 70_ZoneMinder
# as a physical device.
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

my @ZM_Functions = qw( None Monitor Modect Record Mocord Nodect );
my @ZM_Alarms = qw( on off on-for-timer );

sub ZM_Monitor_Initialize {
  my ($hash) = @_;
  $hash->{NotifyOrderPrefix} = "71-";

  $hash->{GetFn}       = "ZM_Monitor_Get";
  $hash->{SetFn}       = "ZM_Monitor_Set";
  $hash->{DefFn}       = "ZM_Monitor_Define";
  $hash->{UndefFn}     = "ZM_Monitor_Undef";
  $hash->{FW_detailFn} = "ZM_Monitor_DetailFn";
  $hash->{ParseFn}     = "ZM_Monitor_Parse";
  $hash->{NotifyFn}    = "ZM_Monitor_Notify";

  $hash->{AttrList} = 'showLiveStreamInDetail:0,1 '.$readingFnAttributes;
  $hash->{Match} = "^.*";

  return undef;
}

sub ZM_Monitor_Define {
  my ( $hash, $def ) = @_;
  $hash->{NOTIFYDEV} = "TYPE=ZoneMinder";

  my @a = split( "[ \t][ \t]*", $def );
 
  my $name   = $a[0];
  my $module = $a[1];
  my $zmMonitorId = $a[2];
  
  if(@a < 3 || @a > 3) {
     my $msg = "ZM_Monitor ($name) - Wrong syntax: define <name> ZM_Monitor <ZM_MONITOR_ID>";
     Log3 $name, 2, $msg;
     return $msg;
  }

  $hash->{NAME} = $name;
  readingsSingleUpdate($hash, "state", "idle", 1);

  AssignIoPort($hash);
  
  my $ioDevName = $hash->{IODev}{NAME};
  my $logDevAddress = $ioDevName.'_'.$zmMonitorId;
  # Adresse rückwärts dem Hash zuordnen (für ParseFn)
#  Log3 $name, 3, "ZM_Monitor ($name) - Logical device address: $logDevAddress";
  $modules{ZM_Monitor}{defptr}{$logDevAddress} = $hash;
  
#  Log3 $name, 3, "ZM_Monitor ($name) - Define done ... module=$module, zmHost=$zmHost, zmMonitorId=$zmMonitorId";

  $hash->{helper}{ZM_MONITOR_ID} = $zmMonitorId;

  ZM_Monitor_UpdateStreamUrls($hash);

  return undef;
}

sub ZM_Monitor_UpdateStreamUrls {
  my ( $hash ) = @_;
  my $ioDevName = $hash->{IODev}{NAME};

  my $zmPathZms = $hash->{IODev}{helper}{ZM_PATH_ZMS};
  if (not $zmPathZms) {
    return undef;
  }

  my $zmHost = $hash->{IODev}{helper}{ZM_HOST};
  my $streamUrl = "http://$zmHost";
  my $zmUsername = urlEncode($hash->{IODev}{helper}{ZM_USERNAME});
  my $zmPassword = urlEncode($hash->{IODev}{helper}{ZM_PASSWORD});
  my $authPart = "&user=$zmUsername&pass=$zmPassword";

  readingsBeginUpdate($hash);
  ZM_Monitor_WriteStreamUrlToReading($hash, $streamUrl, 'streamUrl', $authPart);

  my $pubStreamUrl = $attr{$ioDevName}{publicAddress};
  if ($pubStreamUrl) {
    my $authHash = ReadingsVal($ioDevName, 'authHash', '');
    if ($authHash) { #if ZM_AUTH_KEY is defined, use the auth-hash. otherwise, use the previously defined username/pwd
      $authPart = "&auth=$authHash";
    }
    ZM_Monitor_WriteStreamUrlToReading($hash, $pubStreamUrl, 'pubStreamUrl', $authPart);
  }
  readingsEndUpdate($hash, 1);

  return undef;
}

# is build by using hosname, NPH_ZMS, monitorId, streamBufferSize, and auth
sub ZM_Monitor_getZmStreamUrl {
  my ($hash) = @_;

  #use private or public LAN for streaming access?

  return undef;
}

sub ZM_Monitor_WriteStreamUrlToReading {
  my ( $hash, $streamUrl, $readingName, $authPart ) = @_;
  my $name = $hash->{NAME};

  my $zmPathZms = $hash->{IODev}{helper}{ZM_PATH_ZMS};
  my $zmMonitorId = $hash->{helper}{ZM_MONITOR_ID};
  my $buffer = ReadingsVal($name, 'streamReplayBuffer', '1000');

  my $imageUrl = $streamUrl."$zmPathZms?mode=single&scale=100&monitor=$zmMonitorId".$authPart;
  my $imageReadingName = $readingName;
  $imageReadingName =~ s/Stream/Image/g;
  readingsBulkUpdate($hash, $imageReadingName, $imageUrl, 1);
  
  $streamUrl = $streamUrl."$zmPathZms?mode=jpeg&scale=100&maxfps=30&buffer=$buffer&monitor=$zmMonitorId".$authPart;
  readingsBulkUpdate($hash, $readingName, "$streamUrl", 1);
}

sub ZM_Monitor_DetailFn {
  my ( $FW_wname, $deviceName, $FW_room ) = @_;

  my $hash = $defs{$deviceName};
  my $name = $hash->{NAME};
  
  my $showLiveStream = $attr{$name}{showLiveStreamInDetail};
  return "<div>To view a live stream here, execute: attr $name showLiveStreamInDetail 1</div>" if (not $showLiveStream);

  my $streamDisabled = (ReadingsVal($deviceName, 'monitorFunction', 'None') eq 'None');
  if ($streamDisabled) {
    return '<div>Streaming disabled</div>';
  }

  my $streamUrl = ReadingsVal($deviceName, 'pubStreamUrl', undef);
  if (not $streamUrl) {
    $streamUrl = ReadingsVal($deviceName, 'streamUrl', undef);
  }
  if ($streamUrl) {
    return "<div><img src='$streamUrl'></img></div>";
  } else {
    return undef;
  }
}

sub ZM_Monitor_Undef {
  my ($hash, $arg) = @_; 
  my $name = $hash->{NAME};

  return undef;
}

sub ZM_Monitor_Get {
  my ( $hash, $name, $opt, @args ) = @_;

#  return "Unknown argument $opt, choose one of config";
  return undef;
}

sub ZM_Monitor_Set {
  my ( $hash, $name, $cmd, @args ) = @_;

  if ( "monitorFunction" eq $cmd ) {
    my $arg = $args[0];
    if (grep { $_ eq $arg } @ZM_Functions) {
      my $arguments = {
        method => 'changeMonitorFunction',
        zmMonitorId => $hash->{helper}{ZM_MONITOR_ID},
        zmFunction => $arg
      };
      my $result = IOWrite($hash, $arguments);
      return $result;
    }
    return "Unknown value $arg for $cmd, choose one of ".join(' ', @ZM_Functions);
  } elsif ("motionDetectionEnabled" eq $cmd ) {
    my $arg = $args[0];
    if ($arg eq '1' || $arg eq '0') {
      my $arguments = {
        method => 'changeMonitorEnabled',
        zmMonitorId => $hash->{helper}{ZM_MONITOR_ID},
        zmEnabled => $arg
      };
      my $result = IOWrite($hash, $arguments);
      return $result;
    }
    return "Unknown value $arg for $cmd, choose one of 0 1";
  } elsif ("alarmState" eq $cmd) {
    my $arg = $args[0];
    if (grep { $_ eq $arg } @ZM_Alarms) {

      $arg .= ' '.$args[1] if ( 'on-for-timer' eq $arg );
      my $arguments = {
        method => 'changeMonitorAlarm',
        zmMonitorId => $hash->{helper}{ZM_MONITOR_ID},
        zmAlarm => $arg
      };
      my $result = IOWrite($hash, $arguments);
      return $result;
    }
    return "Unknown value $arg for $cmd, chose one of ".join(' '. @ZM_Alarms);
  } elsif ("text" eq $cmd) {
    my $arg = join ' ', @args;
    if (not $arg) {
      $arg = '';    
    }

    my $arguments = {
      method => 'changeMonitorText',
      zmMonitorId => $hash->{helper}{ZM_MONITOR_ID},
      text => $arg
    };
    my $result = IOWrite($hash, $arguments);
    return $result;
  }

  return 'monitorFunction:'.join(',', @ZM_Functions).' motionDetectionEnabled:0,1 alarmState:on,off,on-for-timer text';
}

# incoming messages from physical device module (70_ZoneMinder in this case).
sub ZM_Monitor_Parse {
  my ( $io_hash, $message) = @_;

  my @msg = split(/\:/, $message, 2);
  my $msgType = $msg[0];
  if ($msgType eq 'event') {
    return ZM_Monitor_handleEvent($io_hash, $msg[1]);
  } elsif ($msgType eq 'createMonitor') {
    return ZM_Monitor_handleMonitorCreation($io_hash, $msg[1]);
  } elsif ($msgType eq 'monitor') {
    return ZM_Monitor_handleMonitorUpdate($io_hash, $msg[1]);
  } else {
    Log3 $io_hash, 0, "Unknown message type: $msgType";
  }

  return undef;
}

sub ZM_Monitor_handleEvent {
  my ( $io_hash, $message ) = @_;

  my $ioName = $io_hash->{NAME};
  my @msgTokens = split(/\|/, $message);
  my $zmMonitorId = $msgTokens[0];
  my $alertState = $msgTokens[1];
  my $eventTs = $msgTokens[2];
  my $eventId = $msgTokens[3];

  my $logDevAddress = $ioName.'_'.$zmMonitorId;
  Log3 $io_hash, 5, "Handling event for logical device $logDevAddress";
  # wenn bereits eine Gerätedefinition existiert (via Definition Pointer aus Define-Funktion)
  if(my $hash = $modules{ZM_Monitor}{defptr}{$logDevAddress}) {
    Log3 $hash, 5, "Logical device $logDevAddress found. Writing readings";

    readingsBeginUpdate($hash);
    ZM_Monitor_createEventStreamUrl($hash, $eventId);
    my $state;
    if ($alertState eq "on") {
      $state = "alert";
    } elsif ($alertState eq "off") {
      $state = "idle";
    }
    readingsBulkUpdate($hash, "state", $state, 1);
    readingsBulkUpdate($hash, "alert", $alertState, 1);
    readingsBulkUpdate($hash, "lastEventTimestamp", $eventTs);
    readingsBulkUpdate($hash, "lastEventId", $eventId);
    readingsEndUpdate($hash, 1);

    Log3 $hash, 5, "Writing readings done. Now returning log dev name: $hash->{NAME}";
    # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.
    return $hash->{NAME};
  } else {
    # Keine Gerätedefinition verfügbar. Daher Vorschlag define-Befehl: <NAME> <MODULNAME> <ADDRESSE>
    my $autocreate = "UNDEFINED ZM_Monitor_$logDevAddress ZM_Monitor $zmMonitorId";
    Log3 $io_hash, 5, "logical device with address $logDevAddress not found. returning autocreate: $autocreate";
    return $autocreate;
  }
}

#for now, this is nearly a duplicate of writing the streamUrl reading.
#will need some love to make better use of existing code.
sub ZM_Monitor_createEventStreamUrl {
  my ( $hash, $eventId ) = @_;
  my $ioDevName = $hash->{IODev}{NAME};

  my $zmPathZms = $hash->{IODev}{helper}{ZM_PATH_ZMS};
  if (not $zmPathZms) {
    return undef;
  }

  my $zmHost = $hash->{IODev}{helper}{ZM_HOST};
  my $streamUrl = "http://$zmHost";
  my $zmUsername = urlEncode($hash->{IODev}{helper}{ZM_USERNAME});
  my $zmPassword = urlEncode($hash->{IODev}{helper}{ZM_PASSWORD});
  my $authPart = "&user=$zmUsername&pass=$zmPassword";
  ZM_Monitor_WriteEventStreamUrlToReading($hash, $streamUrl, 'eventStreamUrl', $authPart, $eventId);

  my $pubStreamUrl = $attr{$ioDevName}{publicAddress};
  if ($pubStreamUrl) {
    my $authHash = ReadingsVal($ioDevName, 'authHash', '');
    if ($authHash) { #if ZM_AUTH_KEY is defined, use the auth-hash. otherwise, use the previously defined username/pwd
      $authPart = "&auth=$authHash";
    }
    ZM_Monitor_WriteEventStreamUrlToReading($hash, $pubStreamUrl, 'pubEventStreamUrl', $authPart, $eventId);
  }
}

sub ZM_Monitor_handleMonitorUpdate {
  my ( $io_hash, $message ) = @_;

  my $ioName = $io_hash->{NAME};
  my @msgTokens = split(/\|/, $message); #$message = "$monitorId|$function|$enabled|$streamReplayBuffer";
  my $zmMonitorId = $msgTokens[0];
  my $function = $msgTokens[1];
  my $enabled = $msgTokens[2];
  my $streamReplayBuffer = $msgTokens[3];
  my $logDevAddress = $ioName.'_'.$zmMonitorId;

  if ( my $hash = $modules{ZM_Monitor}{defptr}{$logDevAddress} ) {
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash, 'monitorFunction', $function);
    readingsBulkUpdateIfChanged($hash, 'motionDetectionEnabled', $enabled);
    my $bufferChanged = readingsBulkUpdateIfChanged($hash, 'streamReplayBuffer', $streamReplayBuffer);
    readingsEndUpdate($hash, 1);

    ZM_Monitor_UpdateStreamUrls($hash);

    return $hash->{NAME};
#  } else {
#    my $autocreate = "UNDEFINED ZM_Monitor_$logDevAddress ZM_Monitor $zmMonitorId";
#    Log3 $io_hash, 5, "logical device with address $logDevAddress not found. returning autocreate: $autocreate";
#    return $autocreate;
  }

  return undef;
}

sub ZM_Monitor_handleMonitorCreation {
  my ( $io_hash, $message ) = @_;

  my $ioName = $io_hash->{NAME};
  my @msgTokens = split(/\|/, $message); #$message = "$monitorId";
  my $zmMonitorId = $msgTokens[0];
  my $logDevAddress = $ioName.'_'.$zmMonitorId;

  if ( my $hash = $modules{ZM_Monitor}{defptr}{$logDevAddress} ) {
    return $hash->{NAME};
  } else {
    my $autocreate = "UNDEFINED ZM_Monitor_$logDevAddress ZM_Monitor $zmMonitorId";
    Log3 $io_hash, 5, "logical device with address $logDevAddress not found. returning autocreate: $autocreate";
    return $autocreate;
  }

  return undef;
}

sub ZM_Monitor_WriteEventStreamUrlToReading {
  my ( $hash, $streamUrl, $readingName, $authPart, $eventId ) = @_;

  my $zmPathZms = $hash->{IODev}{helper}{ZM_PATH_ZMS};
  $streamUrl = $streamUrl."/" if (not $streamUrl =~ m/\/$/);

  my $zmMonitorId = $hash->{helper}{ZM_MONITOR_ID};
  my $imageUrl = $streamUrl."$zmPathZms?mode=single&scale=100&monitor=$zmMonitorId".$authPart;
  my $imageReadingName = $readingName;
  $imageReadingName =~ s/Stream/Image/g;
  readingsBulkUpdate($hash, $imageReadingName, $imageUrl, 1);

  $streamUrl = $streamUrl."$zmPathZms?source=event&mode=jpeg&event=$eventId&frame=1&scale=100&rate=100&maxfps=30".$authPart;
  readingsBulkUpdate($hash, $readingName, $streamUrl, 1);

}

sub ZM_Monitor_Notify {
  my ($own_hash, $dev_hash) = @_;
  my $name = $own_hash->{NAME}; # own name / hash

  return "" if(IsDisabled($name)); # Return without any further action if the module is disabled

  my $devName = $dev_hash->{NAME}; # Device that created the events

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );

  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));
    Log3 $name, 4, "ZM_Monitor ($name) - Incoming event: $event";

    my @msg = split(/\:/, $event, 2);
    if ($msg[0] eq 'authHash') {
      ZM_Monitor_UpdateStreamUrls($own_hash);
    } else {
      Log3 $name, 4, "ZM_Monitor ($name) - ignoring";
    }

    # Examples:
    # $event = "readingname: value" 
    # or
    # $event = "INITIALIZED" (for $devName equal "global")
    #
    # processing $event with further code
  }
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item device
=item summary Logical device to change Monitor operation modes in ZoneMinder
=item summary_DE Logisches Modul zum Verändern der Kameraeinstellungen in ZoneMinder

=begin html

<a name="ZM_Monitor"></a>
<h3>ZM_Monitor</h3>

<a name="ZM_Monitordefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ZM_Monitor  &lt;ZM-Monitor ID&gt;</code>
    <br><br>
    This is usually called by autocreate and triggered by the ZoneMinder IODevice.
    <br>
  </ul>
  <br><br>

  <a name="ZM_Monitorset"></a>
  <b>Set</b>
  <ul>
    <li><code>alarmState</code><br>Puts a monitor into alarm state or out of alarm state via the ZoneMinder trigger port.</li>
    <li><code>monitorFunction</code><br>Sets the operating mode of a Monitor in ZoneMinder via the ZoneMinder API.</li>
    <li><code>motionDetectionEnabled</code><br>Enables or disables monitor detection of a monitor via ZoneMinder API.</li>
    <li><code>text</code><br/>Allows you to set a text for a Timestamp's <code>%Q</code> portion in ZoneMinder via the ZoneMinder trigger port.</li>
  </ul>

  <br><br>
  <a name="ZM_Monitorattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>showLiveStreamInDetail</code><br/>If set to <code>1</code>, a live-stream of the current monitor will be shown on top of the FHEMWEB detail page.</li>
  </ul>

  <br><br>

  <a name="ZM_Monitorreadings"></a>
  <b>Readings</b>
  <br><br>
  <ul>
    <li><code>alert</code><br/>The alert state.</li>
    <li><code>eventImageUrl</code><br/>Link to the first image of the latest event recording, based on the ZM-Host parameter used in the device definition.</li>
    <li><code>eventStreamUrl</code><br/>Link to the latest event recording, based on the ZM-Host parameter used in the device definition.</li>
    <li><code>lastEventId</code><br/>ID of the latest event in ZoneMinder.</li>
    <li><code>lastEventTimestamp</code><br/>Timestamp of the latest event from ZoneMinder.</li>
    <li><code>monitorFunction</code><br/>Current operation mode of the monitor.</li>
    <li><code>motionDetectionEnabled</code><br/>Equals the 'enabled' setting in ZoneMinder. Allows you to put the monitor into a more passive state (according to ZoneMinder documentation).</li>
    <li><code>pubEventImageUrl</code><br/>Link to the first image of the latest event recording, based on the <code>publicAddress</code> attribute used in the ZoneMinder device.</li>
    <li><code>pubEventStreamUrl</code><br/>Link to the latest event recording, based on the <code>publicAddress</code> attribute used in the ZoneMinder device.</li>
    <li><code>pubImageUrl</code><br/>Link to the current live image, based on the <code>publicAddress</code> attribute used in the ZoneMinder device.</li>
    <li><code>pubStreamUrl</code>Link to the live-stream, based on the <code>publicAddress</code> attribute used in the ZoneMinder device.<br/></li>
    <li><code>streamReplayBuffer</code><br/>Taken from the ZoneMinder configuration. Used for the <code>buffer</code> parameter of stream URLs.</li>
    <li><code>streamUrl</code><br/>Link to the live-stream, based on the ZM-Host parameter used in the device definition.</li>

  </ul>

=end html

# Ende der Commandref
=cut

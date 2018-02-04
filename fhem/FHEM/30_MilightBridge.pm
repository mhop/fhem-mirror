# $Id$
##############################################
#
#     30_MilightBridge.pm (Use with 31_MilightDevice.pm)
#     FHEM module for Milight Wifi bridges which control Milight lightbulbs.
#
#     Author: Matthew Wire (mattwire)
#
#     This file is part of fhem.
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
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;

use IO::Handle;
use IO::Socket;
use IO::Select;
use Time::HiRes;
use Net::Ping;

sub MilightBridge_Initialize($)
{
  my ($hash) = @_;

  # Provider
  # $hash->{ReadFn}  = "MilightBridge_Read";
  $hash->{WriteFn}  = "MilightBridge_Write";

  #Consumer
  $hash->{DefFn}    = "MilightBridge_Define";
  $hash->{UndefFn}  = "MilightBridge_Undefine";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "MilightBridge_Notify";
  $hash->{AttrFn}   = "MilightBridge_Attr";
  $hash->{AttrList} = "port protocol:udp,tcp sendInterval disable:0,1 tcpPing:1 checkInterval ".$readingFnAttributes;

  return undef;
}

#####################################
# Define bridge device
sub MilightBridge_Define($$)
{
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);

  return "Usage: define <name> MilightBridge <host/ip:port>"  if(@args < 3);

  my ($name, $type, $hostandport) = @args;

  $hash->{Clients} = ":MilightDevice:";
  my %matchList = ( "1:MilightDevice" => ".*" );
  $hash->{MatchList} = \%matchList;

  my ($host, $port) = split(":", $hostandport);
  # Parameters
  $hash->{HOST} = $host;
  # Set Port (Default 8899, old bridge (V2) uses 50000
  $port = "8899" if (!defined($port));
  $hash->{PORT} = $port;

  $attr{$name}{"protocol"} = "udp" if (!defined($attr{$name}{"protocol"}));

  # Create local socket
  my $sock = IO::Socket::INET-> new (
      PeerPort => 48899,
      Blocking => 0,
      Proto => $attr{$name}{"protocol"},
      Broadcast => 1) or return "can't bind: $@";
  my $select = IO::Select->new($sock);
  $hash->{SOCKET} = $sock;
  $hash->{SELECT} = $select;

  # Note: Milight API specifies 100ms bridge delay for sending commands
  # Define sendInterval
  $attr{$name}{"sendInterval"} = 100 if (!defined($attr{$name}{"sendInterval"}));
  $hash->{INTERVAL} = $attr{$name}{"sendInterval"};

  # Create command queue to hold commands
  my @cmdQueue = ();
  $hash->{cmdQueue} = \@cmdQueue;
  $hash->{cmdQueueLock} = 0;
  $hash->{cmdLastSent} = gettimeofday();

  # Set Attributes
  $attr{$name}{"event-on-change-reading"} = "state" if (!defined($attr{$name}{"event-on-change-reading"}));
  $attr{$name}{"checkInterval"} = 10 if (!defined($attr{$name}{"checkInterval"}));

  delete $hash->{helper}{RUNNING_PID};

  readingsSingleUpdate($hash, "state", "Initialized", 1);

  # Set state
  $hash->{SENDFAIL} = 0;

  # Get initial bridge state
  MilightBridge_SetNextTimer($hash);

  return undef;
}

#####################################
# Undefine Bridge device
sub MilightBridge_Undefine($$)
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
  return undef;
}

#####################################
# Manage attribute changes
sub MilightBridge_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $defs{$name};

  $value = "" if(!defined($value));
  Log3 ($hash, 5, "$hash->{NAME}_Attr: Attr $attribute; Value $value");

  # Handle "sendInterval" attribute which defaults to 100(ms)
  if ($attribute eq "sendInterval")
  {
    if (($value !~ /^\d*$/) || ($value < 1))
    {
      $attr{$name}{"sendInterval"} = 100;
      $hash->{INTERVAL} = $attr{$name}{"sendInterval"};
      return "sendInterval is required in ms (default: 100)";
    }
    else
    {
      $hash->{INTERVAL} = $attr{$name}{"sendInterval"};
    }
  }
  if ($attribute eq "checkInterval")
  {
    if (($value !~ /^\d*$/) || ($value < 0))
    {
      $attr{$name}{"checkInterval"} = 10;
      return "checkInterval is required in s (default: 10, min: 0)";
    }
    readingsSingleUpdate($hash, "state", "Initialized", 1);
    MilightBridge_SetNextTimer($hash);
  }
  elsif ($attribute eq "protocol")
  {
    if (($value eq "tcp" || $value eq "udp"))
    {
      my $protocolchanged = (defined($attr{$name}{"protocol"}) && $attr{$name}{"protocol"} ne $value);
      $attr{$name}{"protocol"} = $value;
      return "You need to restart fhem or modify to enable new protocol." if($protocolchanged);
    }
    else
    {
      return "protocol must be one of 'tcp|udp'";
    }
  }

  # Handle "disable" attribute by opening/closing connection to device
  elsif ($attribute eq "disable")
  {
    # Disable on 1, enable on anything else.
    if ($value eq "1")
    {
      readingsSingleUpdate($hash, "state", "disabled", 1);
    }
    else
    {
      readingsSingleUpdate($hash, "state", "Initialized", 1);
    }
  }

  return undef;
}

#####################################
# Update slot information when a global notify event is fired
sub MilightBridge_Notify($$)
{
  my ($hash,$dev) = @_;

  if(grep(m/^(INITIALIZED|REREADCFG|DEFINED.*|MODIFIED.*|DELETED.*)$/, @{$dev->{CHANGED}}))
  {
    MilightBridge_SlotUpdate($hash);
  }

  return undef;
}

#####################################
# Set next timer for ping check
sub MilightBridge_SetNextTimer($)
{
  my ($hash) = @_;
  # Check state every X seconds
  RemoveInternalTimer($hash);
  my $interval=AttrVal($hash->{NAME}, "checkInterval", "10");
  if ($interval > 0) {
    InternalTimer(gettimeofday() + $interval, "MilightBridge_DoPingStart", $hash, 0);
  }
}

#####################################
# Prepare and start the blocking call in new thread
sub MilightBridge_DoPingStart($)
{
  my ($hash) = @_;

  return undef if (IsDisabled($hash->{NAME}));

  my $timeout = 2;
  my $mode = 'udp';
  $mode = 'tcp' if(defined($attr{$hash->{NAME}}{tcpPing}));

  my $arg = $hash->{NAME}."|".$hash->{HOST}."|".$mode."|".$timeout;
  my $blockingFn = "MilightBridge_DoPing";
  my $finishFn = "MilightBridge_DoPingDone";
  my $abortFn = "MilightBridge_DoPingAbort";

  if (!(exists($hash->{helper}{RUNNING_PID}))) {
    $hash->{helper}{RUNNING_PID} =
          BlockingCall($blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash);
  } else {
    Log3 $hash, 3, "$hash->{NAME} Blocking Call running no new started";
    MilightBridge_SetNextTimer($hash);
  }
}

#####################################
# BlockingCall DoPing in separate thread
sub MilightBridge_DoPing(@)
{
  my ($string) = @_;
  my ($name, $host, $mode, $timeout) = split("\\|", $string);

  Log3 ($name, 5, $name."_DoPing: Executing ping");

  # check via ping
  my $p;
  $p = Net::Ping->new($mode);
  my $result = $p->ping($host, $timeout);
  $p->close();

  $result="" if !(defined($result));
  return "$name|$result";
}

#####################################
# Ping thread completed
sub MilightBridge_DoPingDone($)
{
  my ($string) = @_;
  my ($name, $result) = split("\\|", $string);
  my $hash = $defs{$name};

  my $status = "ok";
  $status = "unreachable" if !($result);

  # Update readings
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "state", $status);
  readingsBulkUpdate( $hash, "sendFail", $hash->{SENDFAIL});
  readingsEndUpdate($hash, 1);

  delete($hash->{helper}{RUNNING_PID});
  MilightBridge_SetNextTimer($hash);
}

#####################################
# Ping thread timeout
sub MilightBridge_DoPingAbort($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  Log3 $hash->{NAME}, 3, "BlockingCall for ".$hash->{NAME}." was aborted";
  MilightBridge_SetNextTimer($hash);
}

#####################################
# Update readings to show which slots have devices defined
sub MilightBridge_SlotUpdate(@)
{
  # Update readings to show what is connected to which slot
  my ($hash) = @_;

  Log3 ( $hash, 5, "$hash->{NAME}_State: Updating Slot readings");

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "slot0", (defined($hash->{0}->{NAME}) ? $hash->{0}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot1", (defined($hash->{1}->{NAME}) ? $hash->{1}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot2", (defined($hash->{2}->{NAME}) ? $hash->{2}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot3", (defined($hash->{3}->{NAME}) ? $hash->{3}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot4", (defined($hash->{4}->{NAME}) ? $hash->{4}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot5", (defined($hash->{5}->{NAME}) ? $hash->{5}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot6", (defined($hash->{6}->{NAME}) ? $hash->{6}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot7", (defined($hash->{7}->{NAME}) ? $hash->{7}->{NAME} : ""));
  readingsBulkUpdate($hash, "slot8", (defined($hash->{8}->{NAME}) ? $hash->{8}->{NAME} : ""));
  readingsEndUpdate($hash, 1);

  return undef;
}

#####################################
# Device write function.  Receives a command and triggers the send queue
sub MilightBridge_Write(@)
{
  # Client sent a new command
  my ($hash, $cmd) = @_;

  Log3 ($hash, 3, "$hash->{NAME}_Write: Command not defined") if (!defined($cmd));
  my $hexStr = unpack("H*", $cmd || '');
  Log3 ($hash, 4, "$hash->{NAME}_Write: Command: $hexStr");

  # Add command to queue
  push @{$hash->{cmdQueue}}, $cmd;

  MilightBridge_CmdQueue_Send($hash);
}

#####################################
# Send a queued command to the bridge hardware
sub MilightBridge_CmdQueue_Send(@)
{
  my ($hash) = @_;

  # Check that queue is not locked. If it is we should just return because another instance of this function has locked it.
  if ($hash->{cmdQueueLock} != 0)
  {
    Log3 ($hash, 5, "$hash->{NAME}_cmdQueue_Send: Send Queue Locked: cmdQueueLock = $hash->{cmdQueueLock}. Return.");
    return undef;
  }

  # Check if we are called again before send interval has elapsed
  my $now = gettimeofday();
  if ((($hash->{cmdLastSent} + ($hash->{INTERVAL} / 1000)) < $now) && $init_done)
  {
    # Lock cmdQueue
    $hash->{cmdQueueLock} = 1;

    # Extract current command
    my $command = @{$hash->{cmdQueue}}[0];

    # Check if we have any commands in queue
    if (!defined($command))
    {
      Log3 ($hash, 5, "$hash->{NAME}_cmdQueue_Send: No commands in queue");
    }
    else
    {
      # Send the command
      my $hexStr = unpack("H*", $command || '');
      Log3 ($hash, 5, "$hash->{NAME} send: $hexStr@".gettimeofday()."; Queue Length: ".@{$hash->{cmdQueue}});

      # Check bridge is not disabled, and send command
      if (!IsDisabled($hash->{NAME}))
      {
        my $hostip = inet_aton($hash->{HOST});
        if (!defined($hostip) || $hostip eq '')
        {
          Log3 ($hash, 3, "$hash->{NAME}: Could not resolve hostname " . $hash->{HOST});
          return undef;
        }
        # sockaddr_in crashes if ip address is undef
        my $portaddr = sockaddr_in($hash->{PORT}, $hostip);
        if (!send($hash->{SOCKET}, $command, 0, $portaddr))
        {
          # Send failed
          Log3 ($hash, 3, "$hash->{NAME} Send FAILED! ".gettimeofday().":$hexStr. Queue Length: ".@{$hash->{cmdQueue}});
          $hash->{SENDFAIL} = 1;
        }
        else
        {
          # Send successful
          $hash->{cmdLastSent} = gettimeofday(); # Update time last sent
          shift @{$hash->{cmdQueue}}; # transmission complete, remove command from queue
        }
      }
    }
  }
  elsif (!$init_done)
  {
    # fhem not initialized, wait for init
    Log3 ($hash, 3, "$hash->{NAME}_cmdQueue_Send: init not done, delay sending from queue");
  }
  else
  {
    # We were called again before send interval elapsed
    Log3 ($hash, 5, "$hash->{NAME}_cmdQueue_Send: Waiting for send interval. cmdLastSent: $hash->{cmdLastSent}. Now: $now");
  }

  # Unlock cmdQueue
  $hash->{cmdQueueLock} = 0;

  # Set next cycle if there are commands in the queue
  if (@{$hash->{cmdQueue}} > 0)
  {
    # INTERVAL is in msec, need to add seconds to gettimeofday (eg 100/1000 = 0.1 seconds)
    #Log3 ($hash, 5, "$hash->{NAME}_cmdQueue_Send: cmdLastSent: $hash->{cmdLastSent}; Next: ".(gettimeofday()+($hash->{INTERVAL}/1000)));

    # Remove any existing timers and trigger a new one
    RemoveInternalTimer($hash, 'MilightBridge_CmdQueue_Send');
    InternalTimer(gettimeofday()+($hash->{INTERVAL}/1000), "MilightBridge_CmdQueue_Send", $hash, 0);
  }

  return undef;

}

1;

=pod
=item device
=item summary Interface to a Milight Bridge connected to the network using a Wifi connection
=begin html

<a name="MilightBridge"></a>
<h3>MilightBridge</h3>
<ul>
  <p>This module is the interface to a Milight Bridge which is connected to the network using a Wifi connection.  It uses a UDP protocal with no acknowledgement so there is no guarantee that your command was received.</p>
  <p>The Milight system is sold under various brands around the world including "LimitlessLED, EasyBulb, AppLamp"</p>
  <p>The API documentation is available here: <a href="http://www.limitlessled.com/dev/">http://www.limitlessled.com/dev/</a></p>

  <a name="MilightBridge_define"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MilightBridge &lt;host/ip:port&gt;</code></p>
    <p>Specifies the MilightBridge device.<br/>
       &lt;host/ip&gt; is the hostname or IP address of the Bridge with optional port (defaults to 8899 if not defined, use 50000 for V1,V2 bridges)</p>
  </ul>
  <a name="MilightBridge_readings"></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <b>state</b><br/>
         [Initialized|ok|unreachable]: Shows reachable status of bridge using "ping" check every 10 (checkInterval) seconds.
    </li>
    <li>
      <b>sendFail</b><br/>
         0 if everything is OK. 1 if the send function was unable to send the command - this would indicate a problem with your network and/or host/port parameters.
    </li>
    <li>
      <b>slot[0|1|2|3|4|5|6|7|8]</b><br/>
         The slotX reading will display the name of the <a href="#MilightDevice">MilightDevice</a> that is defined with this Bridge as it's <a href="#IODev">IODev</a>.  It will be blank if no device is defined for that slot.
    </li>
  </ul>
  <a name="MilightBridge_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <b>sendInterval</b><br/>
         Default: 100ms. The bridge has a minimum send delay of 100ms between commands.
    </li>
    <li>
      <b>checkInterval</b><br/>
         Default: 10s. Time after the bridge connection is re-checked.<br>
         If this is set to 0 checking is disabled and state = "Initialized".
    </li>
    <li>
      <b>protocol</b><br/>
         Default: udp. Change to tcp if you have enabled tcp mode on your bridge.
    </li>
    <li>
      <b>tcpPing</b><br/>
         If this attribute is defined, ping will use TCP instead of UDP.
    </li>
  </ul>
</ul>

=end html
=cut

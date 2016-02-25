# $Id$
##############################################
#
#     98_ping.pm
#     FHEM module to check remote network device using ping.
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
use Net::Ping;

sub ping_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "ping_Define";
  $hash->{UndefFn}  = "ping_Undefine";
  $hash->{AttrFn}   = "ping_Attr";
  $hash->{AttrList} = "disable:1 checkInterval minFailCount ".$readingFnAttributes;

  return undef;
}

#####################################
# Define ping device
sub ping_Define($$)
{
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);

  return "Usage: define <name> ping <host/ip> <mode> <timeout>"  if(@args < 5);

  my ($name, $type, $host, $mode, $timeout) = @args;

  # Parameters
  $hash->{HOST} = $host;
  $hash->{MODE} = lc($mode);
  $hash->{TIMEOUT} = $timeout;
  $hash->{FAILCOUNT} = 0;

  delete $hash->{helper}{RUNNING_PID};

  readingsSingleUpdate($hash, "state", "Initialized", 1);

  return "ERROR: mode must be one of tcp,udp,icmp" if ($hash->{MODE} !~ "tcp|udp|icmp");
  return "ERROR: timeout must be 0 or higher." if (($hash->{TIMEOUT} !~ /^\d*$/) || ($hash->{TIMEOUT} < 0));

  $attr{$name}{"checkInterval"} = 10 if (!defined($attr{$name}{"checkInterval"}));
  $attr{$name}{"event-on-change-reading"} = "state" if (!defined($attr{$name}{"event-on-change-reading"}));

  ping_SetNextTimer($hash);

  return undef;
}

#####################################
# Undefine ping device
sub ping_Undefine($$)
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
  return undef;
}

#####################################
# Manage attribute changes
sub ping_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $defs{$name};

  Log3 ($hash, 5, "$hash->{NAME}_Attr: Attr $attribute; Value $value");

  if ($command eq "set") {

    if ($attribute eq "checkInterval")
    {
      if (($value !~ /^\d*$/) || ($value < 5))
      {
        $attr{$name}{"checkInterval"} = 10;
        return "checkInterval is required in s (default: 10, min: 5)";
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
  }

  return undef;
}

#####################################
# Set next timer for ping check
sub ping_SetNextTimer($)
{
  my ($hash) = @_;
  # Check state every X seconds
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday() + AttrVal($hash->{NAME}, "checkInterval", "10"), "ping_Start", $hash, 0);
}

#####################################
# Prepare and start the blocking call in new thread
sub ping_Start($)
{
  my ($hash) = @_;

  return undef if (IsDisabled($hash->{NAME}));

  my $timeout = $hash->{TIMEOUT};
  my $arg = $hash->{NAME}."|".$hash->{HOST}."|".$hash->{MODE}."|".$hash->{TIMEOUT};
  my $blockingFn = "ping_DoPing";
  my $finishFn = "ping_DoPingDone";
  my $abortFn = "ping_DoPingAbort";

  if (!(exists($hash->{helper}{RUNNING_PID}))) {
    $hash->{helper}{RUNNING_PID} =
          BlockingCall($blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash);
  } else {
    Log3 $hash, 3, "$hash->{NAME} Blocking Call running no new started";
    ping_SetNextTimer($hash);
  }
}

#####################################
# BlockingCall DoPing in separate thread
sub ping_DoPing(@)
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
sub ping_DoPingDone($)
{
  my ($string) = @_;
  my ($name, $result) = split("\\|", $string);
  my $hash = $defs{$name};

  if ($result) {
    # State is ok
    $hash->{FAILCOUNT} = 0;
    readingsSingleUpdate($hash, "state", "ok", 1);
  } else {
    # Increment failcount and report unreachable if over limit
    $hash->{FAILCOUNT} += 1;
    if ($hash->{FAILCOUNT} >= AttrVal($hash->{NAME}, "minFailCount", 1)) {
      readingsSingleUpdate($hash, "state", "unreachable", 1);
    }
  }

  delete($hash->{helper}{RUNNING_PID});
  ping_SetNextTimer($hash);
}

#####################################
# Ping thread timeout
sub ping_DoPingAbort($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  Log3 $hash->{NAME}, 3, "BlockingCall for ".$hash->{NAME}." was aborted";
  ping_SetNextTimer($hash);
}

1;

=pod
=begin html

<a name="ping"></a>
<h3>ping</h3>
<ul>
  <p>This module provides a simple "ping" function for testing the state of a remote network device.</p>
  <p>It allows for alerts to be triggered when devices cannot be reached using a notify function.</p>

  <a name="ping_define"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; ping &lt;host/ip&gt; &lt;mode&gt; &lt;timeout&gt;</code></p>
    <p>Specifies the ping device.<br/>
       &lt;host/ip&gt; is the hostname or IP address of the Bridge.</p>
    <p>Specifies ping mode.<br/>
       &lt;mode&gt; One of: tcp|udp|icmp.  Read the perl docs for more detail: http://perldoc.perl.org/Net/Ping.html</p>
    <p>Timeout.<br/>
       &lt;timeout&gt; is the maximum time to wait for each ping.</p>
  </ul>
  <a name="ping_readings"></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <b>state</b><br/>
        [Initialized|ok|unreachable]: Shows reachable status check every 10 (checkInterval) seconds.
    </li>
  </ul>
  <a name="ping_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <b>checkInterval</b><br/>
         Default: 10s. Time after the bridge connection is re-checked.
    </li>
    <li>
      <b>minFailCount</b><br/>
         Default: 1. Number of failures before reporting "unreachable".
    </li>
  </ul>
</ul>

=end html
=cut

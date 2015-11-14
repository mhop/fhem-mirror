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

#use IO::Handle;
#use IO::Socket;
#use IO::Select;
#use Time::HiRes;
use Net::Ping;

sub ping_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "ping_Define";
  $hash->{UndefFn}  = "ping_Undefine";
  $hash->{AttrFn}   = "ping_Attr";
  $hash->{AttrList} = "disable:0,1 checkInterval ".$readingFnAttributes;

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
  
  return "ERROR: mode must be one of tcp,udp,icmp" if ($hash->{MODE} !~ "tcp|udp|icmp");
  return "ERROR: timeout must be 0 or higher." if (($hash->{timeout} !~ /^\d*$/) || ($hash->{timeout} < 0));
  
  $attr{$name}{"checkInterval"} = 10 if (!defined($attr{$name}{"checkInterval"}));
  
  ping_State($hash);

  return undef;
}

#####################################
# Undefine ping device
sub ping_Undefine($$)
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  
  return undef;
}

#####################################
# Manage attribute changes
sub ping_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $defs{$name};
  
  Log3 ($hash, 5, "$hash->{NAME}_Attr: Attr $attribute; Value $value");

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

  return undef;  
}

#####################################
# Perform a ping and set state to result
sub ping_State(@)
{
  # Update Bridge state
  my ($hash) = @_;
  
  return undef if (IsDisabled($hash->{NAME}));
  
  Log3 ( $hash, 5, "$hash->{NAME}_State: Executing ping");
  
  # check via ping
  my $pingstatus = "unreachable";
  my $p;
  $p = Net::Ping->new($hash->{MODE});

  my $alive = $p->ping($hash->{HOST}, $hash->{TIMEOUT});
  $p->close();
  $pingstatus = "ok" if $alive;

  # And update state
  readingsSingleUpdate($hash, "state", $pingstatus, 1);
  
  # Check state every X seconds  
  InternalTimer(gettimeofday() + AttrVal($hash->{NAME}, "checkInterval", "10"), "ping_State", $hash, 0);
  
  return undef;
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
  </ul>
</ul>

=end html
=cut

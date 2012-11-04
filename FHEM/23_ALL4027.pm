################################################################
#
#  Copyright notice
#
#  (c) 2010 Sacha Gloor (sacha@imp.ch)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################
# $Id$

##############################################
package main;

use strict;
use warnings;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;

sub
ALL4027_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "ALL4027_Set";
  $hash->{DefFn}     = "ALL4027_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###################################
sub
ALL4027_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of on off toggle on-for-timer" if($a[1] eq "?");

  my $v = $a[1];
  my $v2= "";
  if(defined($a[2])) { $v2=$a[2]; }

  if($v eq "toggle")
  {
	if(defined $hash->{READINGS}{state}{VAL})
	{
		if($hash->{READINGS}{state}{VAL} eq "off")
		{
			$v="on";
		}
		else
		{
			$v="off";
		}
	}
	else
	{
		$v="off";
	}
  }
  elsif($v eq "on-for-timer")
  {
	InternalTimer(gettimeofday()+$v2, "ALL4027_on_timeout",$hash, 0);
# on-for-timer is now a on.
	$v="on";
  }
  ALL4027_execute($hash->{DEF},$v);

  Log GetLogLevel($a[0],2), "ALL4027 set @a";

  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;

  DoTrigger($hash->{NAME}, undef);

  return undef;
}
sub 
ALL4027_on_timeout($)
{
  my ($hash) = @_;
  my @a;

  $a[0]=$hash->{NAME};
  $a[1]="off"; 

  ALL4027_Set($hash,@a);

  return undef;
}
###################################
sub
ALL4027_execute($@)
{
	my ($target,$cmd) = @_;
	my $URL='';

  	my @a = split("[ \t][ \t]*", $target);

	if($cmd eq "on")
	{
		$URL="http://".$a[0]."/t8?s=".$a[1]."&n=0&bt=".$a[2]."&z=0&tm=0";
	}
	elsif($cmd eq "off")
	{
		$URL="http://".$a[0]."/t8?s=".$a[1]."&n=0&bt=".$a[2]."&z=1&tm=0";
	}
	else
	{
		return undef;
	}
#	print "URL: $URL\n";

	my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 3);
	my $header = HTTP::Request->new(GET => $URL);
	my $request = HTTP::Request->new('GET', $URL, $header);
	my $response = $agent->request($request);

	return undef;
}

sub
ALL4027_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $host = $a[2];
  my $host_port = $a[3];
  my $relay_nr = $a[4];
  my $delay=$a[5];
  $attr{$name}{delay}=$delay if $delay;

  return "Wrong syntax: use define <name> ALL4027 <ip-address> <port-nr> <relay-nr> <pool-delay>" if(int(@a) != 6);

  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port; 
  $hash->{Relay_Nr} = $relay_nr; 
 
  InternalTimer(gettimeofday()+$delay, "ALL4027_GetStatus", $hash, 0);
 
  return undef;
}

#####################################

sub
ALL4027_GetStatus($)
{
  my ($hash) = @_;
  my $err_log='';
  my $line;

  my $name = $hash->{NAME};
  my $host = $hash->{Host};

  my $delay=$attr{$name}{delay}||300;
  InternalTimer(gettimeofday()+$delay, "ALL4027_GetStatus", $hash, 0);

  if(!defined($hash->{Host_Port})) { return(""); }
  my $host_port = $hash->{Host_Port};
  my $relay_nr = $hash->{Relay_Nr};

  my $URL="http://".$host."/t8?s=".$host_port;
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 3);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  $err_log.= "Can't get $URL -- ".$response->status_line
                unless $response->is_success;

  if($err_log ne "")
  {
        Log GetLogLevel($name,2), "ALL4027 ".$err_log;
        return("");
  }

  my $body =  $response->content;
  my @lines=split(/\n/,$body);

  my $bitvalue=2**$relay_nr;
  my $state="???";

  foreach $line (@lines)
  {
	if(substr($line,0,16) eq "<BR>Dezimalwert:")
	{
		$line =~ s/<BR>//g;
	 	my($tmp,$a)=split(/ /,$line);

		my $value=$a;
		my $result=$value&$bitvalue;
		if($result == 0) { $state="on"; }
                else { $state="off"; }
	}
  }
  if($state ne "???")
  {
  	if($state ne $hash->{STATE})
  	{
  		Log 4, "ALL4027_GetStatus: $host_port $relay_nr ".$hash->{STATE}." -> ".$state;

		$hash->{STATE} = $state;

		$hash->{CHANGED}[0] = $state;
 		$hash->{READINGS}{state}{TIME} = TimeNow();
  		$hash->{READINGS}{state}{VAL} = $state;
		DoTrigger($name, undef) if($init_done);
  	}
  }
}
1;

=pod
=begin html

<a name="ALL4027"></a>
<h3>ALL4027</h3>
<ul>
  Note: this module needs the HTTP::Request and LWP::UserAgent perl modules.
  <br><br>
  <a name="ALL4027define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ALL4027 &lt;ip-address&gt; &lt;port&gt; &lt;relay_nr&gt; &lt;delay&gt;</code>
    <br><br>
    Defines an Allnet 4027 device (Box with 8 relays) connected to an ALL4000 via its ip address. The status of the device is also pooled (delay interval), because someone else is able  to change the state via the webinterface of the device.<br><br>


    Examples:
    <ul>
      <code>define lamp1 ALL4027 192.168.8.200 0 7 60</code><br>
    </ul>
  </ul>
  <br>

  <a name="ALL4027set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    off
    on
    on-for-timer &lt;Seconds&gt;
    toggle
    </pre>
    Examples:
    <ul>
      <code>set poolpump on</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>Toggle is special implemented. List name returns "on" or "off" even after a toggle command</li>
    </ul>
  </ul>
</ul>

=end html
=cut

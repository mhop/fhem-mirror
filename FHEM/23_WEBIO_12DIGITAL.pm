################################################################
#
#  Copyright notice
#
#  (c) 2011 Sacha Gloor (sacha@imp.ch)
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
use IO::Socket;
#use LWP::UserAgent;
#use HTTP::Request;

sub
WEBIO_12DIGITAL_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "WEBIO_12DIGITAL_Set";
  $hash->{DefFn}     = "WEBIO_12DIGITAL_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###################################
sub
WEBIO_12DIGITAL_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of on off on-for-timer" if($a[1] eq "?");

  my $v = $a[1];
  my $v2= "";
  if(defined($a[2])) { $v2=$a[2]; }

  RemoveInternalTimer("WEBIO_12DIGITAL_on_timeout");

  if($v eq "on-for-timer")
  {
	InternalTimer(gettimeofday()+$v2, "WEBIO_12DIGITAL_on_timeout",$hash, 0);
# on-for-timer is now a on.
	$v="on";
  }

  WEBIO_12DIGITAL_execute($hash->{DEF},$v);

  Log GetLogLevel($a[0],2), "WEBIO_12DIGITAL set @a";

  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;

  DoTrigger($hash->{NAME}, undef);

  return undef;

}
sub 
WEBIO_12DIGITAL_on_timeout($)
{
  my ($hash) = @_;
  my @a;

  $a[0]=$hash->{NAME};
  $a[1]="off"; 

  WEBIO_12DIGITAL_Set($hash,@a);

  return undef;
}


###################################
sub
WEBIO_12DIGITAL_execute($@)
{
	my ($target,$cmd) = @_;
	my $URL='';
	my $v='';
	my $err_log='';

	if($cmd eq "on") { $v="ON"; }
	else { $v="OFF"; }

  	my @a = split("[ \t][ \t]*", $target);

	my $sock = new IO::Socket::INET (
	        PeerAddr => $a[0],
       		PeerPort => '80',
        	Proto => 'tcp',
        	Timeout => "3",
        );
  	$err_log = "Could not create socket: $!\n" unless $sock;

  	if($err_log ne "") { return undef; }

  	print $sock "GET /outputaccess".$a[1]."?PW=&State=".$v."\n";
  	close($sock);

	return undef;
}

sub
WEBIO_12DIGITAL_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $host = $a[2];
  my $host_port = $a[3];
  my $delay=$a[4];
  $attr{$name}{delay}=$delay if $delay;

  return "Wrong syntax: use define <name> WEBIO_12DIGITAL <ip-address> <port-nr> <poll-delay>" if(int(@a) != 5);

  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port; 
 
  InternalTimer(gettimeofday()+$delay, "WEBIO_12DIGITAL_GetStatus", $hash, 0);
 
  return undef;
}

#####################################

sub
WEBIO_12DIGITAL_GetStatus($)
{
  my ($hash) = @_;
  my $err_log='';
  my $line;
  my $state;

  my $name = $hash->{NAME};
  my $host = $hash->{Host};

  my $delay=$attr{$name}{delay}||300;
  InternalTimer(gettimeofday()+$delay, "WEBIO_12DIGITAL_GetStatus", $hash, 0);

  if(!defined($hash->{Host_Port})) { return(""); }
  my $host_port = $hash->{Host_Port};

  my $sock = new IO::Socket::INET (
        PeerAddr => $host,
        PeerPort => '80',
        Proto => 'tcp',
        Timeout => "3",
        );
  $err_log = "Could not create socket: $!\n" unless $sock;

  if($err_log ne "")
  {
        Log GetLogLevel($name,2), "WEBIO_12DIGITAL ".$err_log;
        return("");
  }
  print $sock "GET /output".$host_port."?PW=&\n";
  $line = <$sock>;
  close($sock);

  if($line =~ /ON/) { $state="on"; } else { $state="off"; }
  if($hash->{STATE} ne $state)
  {
  	Log 4, "WEBIO_12DIGITAL_GetStatus: $host_port ".$hash->{STATE}." -> ".$state;

  	$hash->{STATE} = $state;

  	$hash->{CHANGED}[0] = $state;
  	$hash->{READINGS}{state}{TIME} = TimeNow();
  	$hash->{READINGS}{state}{VAL} = $state;
  	DoTrigger($name, undef) if($init_done);
  }
}

1;

=pod
=begin html

<a name="WEBIO_12DIGITAL"></a>
<h3>WEBIO_12DIGITAL</h3>
<ul>
  Note: this module needs the HTTP::Request and LWP::UserAgent perl modules.
  <br><br>
  <a name="WEBIO_12DIGITALdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WEBIO_12DIGITAL &lt;ip-address&gt; &lt;outputport&gt; &lt;delay&gt;</code>
    <br><br>
    Defines an Web-IO-Digital device (Box with up to 12 digital in/outputs, www.wut.de) via ip address. The status of the device is also pooled (delay interval).<br><br>

    Examples:
    <ul>
      <code>define motor1 WEBIO_12DIGITAL 192.168.8.200 1 60</code><br>
    </ul>
  </ul>
  <br>

  <a name="WEBIO_12DIGITALset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
       on off
    </pre>
    Examples:
    <ul>
      <code>set motor1 on</code><br>
    </ul>
    <br>
  </ul>
</ul>

=end html
=cut

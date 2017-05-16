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
WEBIO_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "WEBIO_Set";
  $hash->{DefFn}     = "WEBIO_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###################################
sub
WEBIO_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of 0 1 2 3 4 5 6 7 8 9 10" if($a[1] eq "?");

  my $v = $a[1];
  my $sensor="volt";

  WEBIO_execute($hash->{DEF},$v);

  Log GetLogLevel($a[0],2), "WEBIO set @a";

  $hash->{CHANGED}[0] = "Volt:";
  $hash->{STATE} = "V: ".$v;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $v." (Volt)";
  return undef;

}
###################################
sub
WEBIO_execute($@)
{
	my ($target,$cmd) = @_;
	my $URL='';

  	my @a = split("[ \t][ \t]*", $target);

	$URL="http://".$a[0]."/outputaccess".$a[1]."?PW=&State=".$cmd."&";

	my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 1);
	my $header = HTTP::Request->new(GET => $URL);
	my $request = HTTP::Request->new('GET', $URL, $header);
	my $response = $agent->request($request);

	return undef;
}

sub
WEBIO_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $host = $a[2];
  my $host_port = $a[3];
  my $delay=$a[4];
  $attr{$name}{delay}=$delay if $delay;

  return "Wrong syntax: use define <name> WEBIO <ip-address> <port-nr> <poll-delay>" if(int(@a) != 5);

  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port; 
 
  InternalTimer(gettimeofday()+$delay, "WEBIO_GetStatus", $hash, 0);
 
  return undef;
}

#####################################

sub
WEBIO_GetStatus($)
{
  my ($hash) = @_;
  my $err_log='';
  my $line;

  my $name = $hash->{NAME};
  my $host = $hash->{Host};

  my $delay=$attr{$name}{delay}||300;
  InternalTimer(gettimeofday()+$delay, "WEBIO_GetStatus", $hash, 0);

  if(!defined($hash->{Host_Port})) { return(""); }
  my $host_port = $hash->{Host_Port};

  my $URL="http://".$host."/Single".$host_port;
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 3);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  $err_log.= "Can't get $URL -- ".$response->status_line
                unless $response->is_success;

  if($err_log ne "")
  {
        Log GetLogLevel($name,2), "WEBIO ".$err_log;
        return("");
  }

  my $body =  $response->content;

#  print $body."\n";
  my @values=split(/;/,$body);
  my $last=$values[$#values];
  my @v=split(/ /,$last);
  my $state=$v[0];
  $state=~s/,/./g;

  my $sensor="volt";
  Log 4, "WEBIO_GetStatus: $host_port ".$hash->{STATE}." -> ".$state;

  $hash->{STATE} = "V: ".$state;

  $hash->{CHANGED}[0] = $state;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $state." (Volt)";
  DoTrigger($name, undef) if($init_done);
}

1;

=pod
=begin html

<a name="WEBIO"></a>
<h3>WEBIO</h3>
<ul>
  Note: this module needs the HTTP::Request and LWP::UserAgent perl modules.
  <br><br>
  <a name="WEBIOdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WEBIO &lt;ip-address&gt; &lt;port&gt; &lt;delay&gt;</code>
    <br><br>
    Defines an Web-IO device (Box with 2 Analog-In/Out 0..10V, www.wut.de) via ip address. The status of the device is also pooled (delay interval).<br><br>


    Examples:
    <ul>
      <code>define pumpspeed WEBIO 192.168.8.200 1 60</code><br>
    </ul>
  </ul>
  <br>

  <a name="WEBIOset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    0.00 - 10.00
    </pre>
    Examples:
    <ul>
      <code>set pumpspeed 6.75</code><br>
    </ul>
    <br>
  </ul>
</ul>

=end html
=cut

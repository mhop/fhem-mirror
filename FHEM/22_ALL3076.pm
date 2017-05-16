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
ALL3076_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "ALL3076_Set";
  $hash->{DefFn}     = "ALL3076_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###################################
sub
ALL3076_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of on off toggle dimdown dimup dim10% dim20% dim30% dim40% dim50% dim60% dim70% dim80% dim90% dim100%" if($a[1] eq "?");

  my $v = $a[1];
  my $v2 = "";
  my $err_log="";

  if(defined $a[2]) { $v2=$a[2]; }

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
  Log GetLogLevel($a[0],2), "ALL3076 set @a";
  $err_log=ALL3076_execute($hash->{DEF},$v,$v2);
  if($err_log ne "")
  {
  	Log GetLogLevel($a[0],2), "ALL3076 ".$err_log;
  }

  $hash->{CHANGED}[0] = $v.$v2;
  $hash->{STATE} = $v.$v2;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v.$v2;
  return undef;
}
###################################
sub
ALL3076_execute($@)
{
	my ($target,$cmd,$cmd2) = @_;
	my $URL='';
	my $log='';

	if($cmd eq "on")
	{
		$URL="http://".$target."/r?r=0&s=1";
	}
	elsif($cmd eq "off")
	{
		$URL="http://".$target."/r?r=0&s=0";
	}
	elsif($cmd eq "dimdown")
	{
		# We switch it on first
		$log.=ALL3076_execute($target,"on");
		$URL="http://".$target."/r?d=0";
	}
	elsif($cmd eq "dimup")
	{
		# We switch it on first
		$log.=ALL3076_execute($target,"on");
		$URL="http://".$target."/r?d=1";
	}
	elsif(substr($cmd,0,3) eq "dim")
	{
		# We switch it on first
		$log.=ALL3076_execute($target,"on");

		my $proz=substr($cmd,3,length($cmd)-4);
		my $proz_v=sprintf("%d",$proz*255/100);

		$URL="http://".$target."/r?d=".$proz_v;
	}
	elsif($cmd eq "on-old-for-timer")
	{
		sleep(1); # Todo
	}
	else
	{
		return($log);
	}
#	print "URL: $URL\n";
	my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
	my $header = HTTP::Request->new(GET => $URL);
	my $request = HTTP::Request->new('GET', $URL, $header);
	my $response = $agent->request($request);

	$log.= "Can't get $URL -- ".$response->status_line
		unless $response->is_success;

	return($log);
}

sub
ALL3076_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> ALL3076 <ip-address>" if(int(@a) != 3);
  return undef;
}

1;

=pod
=begin html

<a name="ALL3076"></a>
<h3>ALL3076</h3>
<ul>
  Note: this module needs the HTTP::Request and LWP::UserAgent perl modules.
  <br><br>
  <a name="ALL3076define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ALL3076 &lt;ip-address&gt; </code>
    <br><br>
    Defines an Allnet 3076 device (Dimmable lightswitch) via its ip address or dns name<br><br>

    Examples:
    <ul>
      <code>define lamp1 ALL3076 192.168.1.200</code><br>
    </ul>
  </ul>
  <br>

  <a name="ALL3076set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    dimdown
    dim10%
    dim20%
    dim30%
    dim40%
    dim50%
    dim60%
    dim70%
    dim80%
    dim90%
    dim100%
    dim[0-100]%
    dimup
    off
    on
    toggle
    </pre>
    Examples:
    <ul>
      <code>set lamp1 on</code><br>
      <code>set lamp1 dim11%</code><br>
      <code>set lamp2 toggle</code><br>
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

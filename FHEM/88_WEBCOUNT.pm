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

package main;

use strict;
use warnings;
use XML::Simple;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;

sub Log($$);
#####################################

sub 
trim($)
{
        my $string = shift;
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
        return $string;
}

sub
WEBCOUNT_Initialize($)
{
  my ($hash) = @_;
  # Consumer
  $hash->{DefFn}   = "WEBCOUNT_Define";
  $hash->{AttrList}= "model:WEBCOUNT delay loglevel:0,1,2,3,4,5,6";
}

#####################################

sub
WEBCOUNT_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);
  Log 5, "WEBCOUNT Define: $a[0] $a[1] $a[2] $a[3] $a[4]";
  return "Define the host as a parameter i.e. WEBCOUNT"  if(@a < 4);

  my $host = $a[2];
  my $host_port = $a[3];
  my $delay=$a[4];
  $attr{$name}{delay}=$delay if $delay;
  Log 1, "WEBCOUNT device is none, commands will be echoed only" if($host eq "none");
  
  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port;
  $hash->{STATE} = "Initialized";
  Log 4,"$name: Delay $delay";

  InternalTimer(gettimeofday()+$delay, "WEBCOUNT_GetStatus", $hash, 0);
  return undef;

}

#####################################

sub
WEBCOUNT_GetStatus($)
{
  my ($hash) = @_;
  
  my $buf;

  if(!defined($hash->{Host_Port})) { return(""); }

  Log 5, "WEBCOUNT_GetStatus";
  my $name = $hash->{NAME};
  my $host = $hash->{Host};
  my $host_port = $hash->{Host_Port};
  my $text='';
  my $err_log='';
  
  my $delay=$attr{$name}{delay}||300;
  InternalTimer(gettimeofday()+$delay, "WEBCOUNT_GetStatus", $hash, 0);
    
  my $xml = new XML::Simple;

  my $URL="http://".$host."/counter?PW=&";
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 3);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  $err_log.= "Can't get $URL -- ".$response->status_line
                unless $response->is_success;

  if($err_log ne "")
  {
	Log GetLogLevel($name,2), "WEBCOUNT ".$err_log;
	return("");
  }

  my $body =  $response->content;

  my @cur = split(";", $body);

  my $current=$cur[$host_port];

  $text="Counter: ".$current;
  my $sensor="counter";
  Log 4,"$name: $text";
  if (!$hash->{local}){
       $hash->{CHANGED}[0] = $text;
       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
       $hash->{READINGS}{$sensor}{VAL} = $current;
       DoTrigger($name, undef) if($init_done);    
  }
  $hash->{STATE} = $current;
  return($text);
}


1;


=pod
=begin html

<a name="WEBCOUNT"></a>
<h3>WEBCOUNT</h3>
<ul>
  Note: this module needs the HTTP::Request and LWP::UserAgent perl modules.
  <br><br>
  <a name="WEBCOUNTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WEBCOUNT &lt;ip-address&gt; &lt;port&gt; &lt;delay&gt;</code>
    <br><br>
    Defines an WEBCOUNT device (Box with 6 count pulses, www.wut.de) via ip address. The device is pooled (delay interval).<br><br>


    Examples:
    <ul>
      <code>define pump WEBCOUNT 192.168.8.200 1 60</code><br>
    </ul>
  </ul>
  <br>
</ul>
=end html
=cut

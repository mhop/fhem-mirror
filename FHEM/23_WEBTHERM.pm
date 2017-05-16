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
WEBTHERM_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "WEBTHERM_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

sub
WEBTHERM_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $host = $a[2];
  my $host_port = $a[3];
  my $delay=$a[4];
  $attr{$name}{delay}=$delay if $delay;

  return "Wrong syntax: use define <name> WEBTHERM <ip-address> <port-nr> <poll-delay>" if(int(@a) != 5);

  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port; 
 
  InternalTimer(gettimeofday()+$delay, "WEBTHERM_GetStatus", $hash, 0);
 
  return undef;
}

#####################################

sub
WEBTHERM_GetStatus($)
{
  my ($hash) = @_;
  my $err_log='';
  my $line;

  my $name = $hash->{NAME};
  my $host = $hash->{Host};

  my $delay=$attr{$name}{delay}||300;
  InternalTimer(gettimeofday()+$delay, "WEBTHERM_GetStatus", $hash, 0);

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
        Log GetLogLevel($name,2), "WEBTHERM ".$err_log;
        return("");
  }

  my $body =  $response->content;
  my $text='';
#  print $body."\n";
  my @values=split(/;/,$body);
  my $last=$values[$#values];
  my $state=$last;
  $state=~s/,/./g;
  $state=substr($state,0,-2);

  my $sensor="temperature";
  Log 4, "WEBTHERM_GetStatus: $name $host_port ".$hash->{STATE}." -> ".$state;

  $text="Temperature: ".$state;
  $hash->{STATE} = "T: ".$state;

  $hash->{CHANGED}[0] = $text;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $state." (Celsius)";
  DoTrigger($name, undef) if($init_done);
}

1;

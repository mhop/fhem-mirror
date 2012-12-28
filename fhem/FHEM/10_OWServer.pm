# $Id$
################################################################
#
#  Copyright notice
#
#  (c) 2012 Copyright: Dr. Boris Neubert
#  omega at online dot de
#
#  This file is part of fhem.
#
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################

package main;

use strict;
use warnings;
# this must be the latest OWNet from
#  http://owfs.cvs.sourceforge.net/viewvc/owfs/owfs/module/ownet/perl5/OWNet/lib/OWNet.pm
# the version at CPAN is outdated and malfunctioning as at 2012-12-19
use OWNet;

#####################################
sub
OWServer_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn}= "OWServer_Write";
  $hash->{ReadFn} = "OWServer_Read";
  $hash->{Clients}= ":OWDevice:";

# Consumer
  $hash->{DefFn}   = "OWServer_Define";
  $hash->{UndefFn} = "OWServer_Undef";
  $hash->{GetFn}   = "OWServer_Get";
  $hash->{SetFn}   = "OWServer_Set";
# $hash->{AttrFn}  = "OWServer_Attr";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5";
}

#####################################
sub
OWServer_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def, 3);
  my $name = $a[0];
  if(@a < 3) {
    my $msg = "wrong syntax for $name: define <name> OWServer <protocol>";
    Log 2, $msg;
    return $msg;
  }

  my $protocol = $a[2];
  
  OWServer_CloseDev($hash);

  $hash->{fhem}{protocol}= $protocol;

  OWServer_OpenDev($hash);
  return undef;
}


#####################################
sub
OWServer_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting OWServer for $d";
        delete $defs{$d}{IODev};
      }
  }

  OWServer_CloseDev($hash);
  return undef;
}

#####################################
sub
OWServer_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return unless(defined($hash->{fhem}{owserver}));
  DoTrigger($name, "DISCONNECTED");
  delete $hash->{fhem}{owserver};

}

########################
sub
OWServer_OpenDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  OWServer_CloseDev($hash);
  my $protocol= $hash->{fhem}{protocol};
  Log 4, "$name: Opening connection to OWServer $protocol...";
  my $owserver= OWNet->new($protocol);
  if($owserver) {
    Log 4, "$name: Successfully connected to $protocol.";
    $hash->{fhem}{owserver}= $owserver;
    DoTrigger($name, "CONNECTED") if($owserver);
    $hash->{STATE}= "";       # Allow InitDev to set the state
    my $ret  = OWServer_DoInit($hash);
    
  }
  return $owserver
}

#####################################
sub
OWServer_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  return undef;
}

#####################################
sub
OWServer_Read($@)
{
  my ($hash,$path)= @_;

  return undef unless(defined($hash->{fhem}{owserver}));
  return $hash->{fhem}{owserver}->read($path);
}
  
#####################################
sub
OWServer_Write($@)
{
  my ($hash,$path,$value)= @_;

  return undef unless(defined($hash->{fhem}{owserver}));
  return $hash->{fhem}{owserver}->write($path,$value);
}


#####################################
sub
OWServer_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];

  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];
  #my $arg = ($a[2] ? $a[2] : "");
  #my @args= @a; shift @args; shift @args;

  my $owserver= $hash->{fhem}{owserver};

  if($cmd eq "devices") {
        my @dir= split(",", $owserver->dir());
        my @devices= grep { m/^\/[0-9a-f]{2}.[0-9a-f]{12}$/i } @dir;
        my $ret;
        for my $device (@devices) {
          $ret .= substr($device,1) . " " . $owserver->read($device . "/type") . "\n";
        }
        return $ret;
  }  else {
        return "Unknown argument $cmd, choose one of devices"
  }

}

#####################################
sub
OWServer_Set($@)
{
        my ($hash, @a) = @_;
        my $name = $a[0];

        # usage check
        #my $usage= "Usage: set $name classdef <classname> <filename> OR set $name reopen";
        my $usage= "Unknown argument $a[1], choose one of reopen";
        if((@a == 2) && ($a[1] eq "reopen")) {
                return OWServer_OpenDev($hash);
        }
        return undef;

}
#####################################


1;


=pod
=begin html

<a name="OWServer"></a>
<h3>OWServer</h3>
<ul>
  <br>
  <a name="OWDevicedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OWDevice &lt;protocol&gt;</code>
    <br><br>

    Defines a logical OWServer device. OWServer is the server component of the
    <a href="http://owfs.org">1-Wire Filesystem</a>. It serves as abstraction layer
    for any 1-wire devices on a host. &lt;protocol&gt; has
    format &lt;hostname&gt;:&lt;port&gt;. For details see
    <a href="http://owfs.org/index.php?page=owserver_protocol">owserver documentation</a>.
    <br><br>
    You need <a href="http://owfs.cvs.sourceforge.net/viewvc/owfs/owfs/module/ownet/perl5/OWNet/lib/OWNet.pm">OWNet.pm from owfs.org</a>. Just drop it into your <code>FHEM</code>
    folder alongside the <code>10_OWServer.pm</code> module. As at 2012-12-23 the OWNet module
    on CPAN has an issue which renders it useless for remote connections.
    <br><br>
    The actual 1-wire devices are defined as <a href="#OWDevice">OWDevice</a> devices.
    <br><br>
    This module is completely unrelated to the 1-wire modules with names all in uppercase.
    <br><br>
    Examples:
    <ul>
      <code>define myLocalOWServer OWServer localhost:4304</code><br>
      <code>define myRemoteOWServer OWServer raspi:4304</code><br>
    </ul>
    <br><br>
    Notice: if you get no devices add both <code>localhost</code> and the FQDN of your owserver as server directives
    to the owserver configuration file
    on the remote host.
    <br><br>
    
  </ul>

  <a name="OWServerset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; reopen</code>
    <br><br>
    Reopens the connection to the owserver.
    <br><br>
  </ul>
  <br><br>


  <a name="OWServerget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; devices</code>
    <br><br>
    Lists the addresses and types of all 1-wire devices provided by the owserver.
    <br><br>
  </ul>
  <br><br>


  <a name="OWDeviceattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
  </ul>
  <br><br>



</ul>


=end html
=cut

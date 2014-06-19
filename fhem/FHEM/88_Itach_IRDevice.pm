##############################################
# 88_Itach_IRDevice
# $Id: $
#
################################################################
#
#  Copyright notice
#
#  (c) 2014 Copyright: Ulrich Maass
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
#  Disclaimer: The Author takes no responsibility whatsoever 
#  for damages potentially done by this program.
#
################################################################################
#
# This module serves as frontend to 10_Itach_IR
#
################################################################################

package main;
use strict;
use warnings;

#########################
# Forward declaration
sub IIRD_Define();
sub IIRD_Attr(@);
sub IIRD_Set($@);
sub IIRD_Get($@);
sub IIRD_getDeviceCommands($);
sub IIRD_send($$$);
sub IIRD_getIRcode($$);
sub IIRD_clearIRcodes($@);

#####################################
# Initialize module
sub
Itach_IRDevice_Initialize($)
{
  my ($hash) = @_;
  $hash->{GetFn}                 = "IIRD_Get";
  $hash->{SetFn}                 = "IIRD_Set";
  $hash->{AttrFn}                = "IIRD_Attr";
  $hash->{DefFn}                 = "IIRD_Define";
  $hash->{AttrList}              = "verbose:0,1,2,3,4,5,6 IODev";
}


#####################################
# Initialize every new instance
sub
IIRD_Define() {
  my ($hash, $def) = @_;
  my $ret;
  my ($name, $type, $file, $iodev) = split("[ \t]+", $def);
  return "Usage: define <name> ItachIRDevice <IR-config-file>"  if(!$file);
  
  #should check if file exists
  
  $hash->{STATE}       = "Initialized";
  $hash->{FILE}        = $file if ($file);

  AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
  
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 4, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
	my $ret = "$name: no I/O device";
	Log3 $name, 1, $ret;
  }
  
  my $cmdret= CommandAttr(undef,"$name room ItachIR") if (!AttrVal($name,'room',undef));
  
  return $ret;
}


#####################################
# Ensure .IRcodes is created from scratch after an attribute value has been changed
sub 
IIRD_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  delete $hash->{'.IRcodes'}; # reset IRcodes so they will be loaded anew
  return;
}

#####################################
# Digest set-commands
sub
IIRD_Set($@)
{
  my ($hash, @a) = @_;
  my ($nam,$cmd,$par)=@a;
  return if (!defined($cmd));
  if ($cmd eq '?') {
    return "Unknown argument $cmd choose one of rereadIRfile seqsingle ". IIRD_getDeviceCommands($hash);
  } elsif ($cmd eq 'rereadIRfile') {
    IIRD_clearIRcodes($hash);
	IIRD_getDeviceCommands($hash);
  } else {
    IIRD_send($hash,$cmd,$par);
  }
  return undef;
}

#####################################
# Digest get-commands
sub
IIRD_Get($@)
{
  my ($hash, @a) = @_;
  my $arg = (defined($a[1]) ? $a[1] : ""); #command
  my $name = $hash->{NAME};

  ## get htmlcode
  if($arg eq "validcommands") {
    my @vc = split(' ',IIRD_getDeviceCommands($hash)); 
    return join(' ', sort @vc);
  } else {
    return "Unknown argument $arg choose one of validcommands";
  }
}

#####################################
# Send commands to ItachIR
sub
 IIRD_send($$$) {
  my ($hash,$cmd,$par)=@_;
  my $IRcode;
  my $name=$hash->{NAME};
  if ($cmd eq 'seqsingle') {
    for (my $i=0;$i<length($par);$i++) {
	  $IRcode .= IIRD_getIRcode($hash,substr($par,$i,1)).';';
	}
	$IRcode =~ s/;$//; #delete final ;
	$cmd.=' '.$par;
  } else {
    $IRcode = IIRD_getIRcode($hash,$cmd);
  }
  Log3 $name, 5, "IIRD136 Writing $name, $cmd, $IRcode";
  my $ret = IOWrite($hash, $name, $cmd, $IRcode) if (defined($IRcode));
  readingsSingleUpdate($hash,"state",$cmd,1);
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+7200, "IIRD_clearIRcodes", $hash, 0); # delete hash->{'.IRcodes'} 2 hours after last use
}

#####################################
# Get IRcode
sub
IIRD_getIRcode($$) {
  my ($hash,$cmd)=@_;
  my $nam=$hash->{NAME};
  my $scmd = $cmd;
  $scmd =~ s/^0$/chr0/;
  if (!$hash->{'.IRcodes'} || !$hash->{'.IRcodes'}{$scmd}) {
    IIRD_getDeviceCommands($hash);
    if (!$hash->{'.IRcodes'} || !$hash->{'.IRcodes'}{$scmd}) {
	  Log3 $nam, 3, "No IRcode defined for device $nam, command $cmd";
	  return undef;
	}
  }
  return $hash->{'.IRcodes'}{$scmd};
}

#####################################
## get all defined commands of device
sub
IIRD_getDeviceCommands($) {
  my $hash = shift;
  my $ret;
  my $filename=$hash->{FILE};
  if (!$hash->{'.IRcodes'}) {
    my $filename = AttrVal('global','modpath','.').'/'.$filename;
	Log3 $hash->{NAME}, 5, "Reading $filename ...";
    # open IR-file
    if (! open(IRCODES, "< $filename")) {  
       Log3 $hash->{NAME}, 1, "Cannot open file $filename : $!";
    } else {
      # read commands from IR-file
      my $line;
      while (defined ($line = <IRCODES>)) {
        $line =~ m/^\[(.*)\]\s(.*)/;
	    $ret .= $1.' ';
		my $scmd = $1;
        my $IR = $2;
        $scmd =~ s/^0$/chr0/;
		$hash->{'.IRcodes'}{$scmd} = $IR;
	    next;
	  }
    }
  } else {
    foreach my $cmd (keys %{$hash->{'.IRcodes'}}) {
	  $cmd =~ s/^chr0$/0/;
	  $ret .= $cmd . ' ' if (defined($cmd));
	}
  }
  $ret =~ s/ $//; #delete final blank
  return $ret;
}

#####################################
# Delete IRcodes from hash to save memory
sub
IIRD_clearIRcodes($@) {
  my $hash = shift;
  delete $hash->{'.IRcodes'};
  return undef;
}

1;


=pod
=begin html

<a name="Itach_IRDevice"></a>
<h3>Itach_IRDevice</h3>
<ul>
  Itach IR is a physical device that serves to emit Infrared (IR) commands, hence it is a general IR remote control that can be controlled via WLAN (WF2IR) or LAN (IP2IR).<br> 
  Using the iLearn-Software that ships with every Itach IR, record the IR-squences per original remotecontrol-button and store all these IR-codes as an IR-config-file. 
  This IR-config-file can then be used directly with this module. All commands stored in the IR-config-file will be available immediately for use.<br>
  For more information, check the <a href="http://www.fhemwiki.de/wiki/ITach">Wiki page</a>.<br>
  
  <a name="Itach_IRDevicedefine"></a><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Itach_IRDevice &lt;IR-config-file&gt;</code><br>
    Store the IR-config-file in the same directory where fhem.cfg resides.<br>
    <b>Hint:</b> define an <a href="#Itach_IR">Itach_IR</a> device first!<br>
	Example:<br>
    <code>define IR_mac Itach_IRDevice IR-codes-mac.txt</code><br>
	<code>define IR_amp Itach_IRDevice IR-codes-media-amplifier.txt</code>
  </ul>

  <a name="Itach_IRDeviceset"></a><br>
  <b>Set</b><br>

    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br><br>
    The list of available commands depends on the content of the IR-config-file. 
	<br>There are only two module specific commands:
  <ul>
    <li><code>set &lt;name&gt; rereadIRfile</code><br>
	For performance reasons, the IR-config-File is read into memory upon definition of the device. If you change the configuration within that file, use this set-command to read its content into fhem once again.</li>
	<li><code>set &lt;name&gt; seqsingle &lt;parameter&gt;</code><br>
	Will send the digits of a sequence one after the other. Useful when you have a sequence of digits to be sent, e.g. 123.  Each digit must be a valid command in your IR-config-file.</li>
  </ul>
  
  <a name="Itach_IRDeviceget"></a><br>
  <b>Get</b>
  <ul>
    <li><code>get &lt;name&gt; validcommands</code><br>
    Lists the valid commands for this device according to your IR-config-file.</li>
  </ul>
  
  <a name="Itach_IRDeviceattr"></a><br>
  <b>Attributes</b>
  <ul>
    <li><a href="#verbose">verbose</a></li>
	<li><a href="#IODev">IODev</a><br>
	Needs to be stated if more than one ItachIR-device is part of your fhem-configuration.</li>
  </ul>
</ul>

=end html
=cut



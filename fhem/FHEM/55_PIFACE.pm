# $Id$
####################################################################################################
#
#	55_PIFACE.pm
#
#	An FHEM Perl module to control RaspberryPi extension board PiFace
#
#	The PiFace is an add-on board for the Raspberry Pi featuring 8 open-collector outputs,
#	with 2 relays and 8 inputs (with 4 on-board buttons). 
#	These functions are fairly well fixed in the hardware, 
#	so only the read, write and internal pull-up commands are implemented.
#
#	Please read commandref for details on prerequisits!
#	Depends on wiringPi library from http://wiringpi.com
#
#	maintainer: klaus.schauer (see MAINTAINER.txt)
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package main;

use strict;
use warnings;

sub PIFACE_Define($$);
sub PIFACE_Undefine($$);
sub PIFACE_Set($@);
sub PIFACE_Get($@);
sub PIFACE_Attr(@);

my $base = 200;

sub PIFACE_Initialize($){
  my ($hash) = @_;
  $hash->{DefFn}	= "PIFACE_Define";
  $hash->{UndefFn}	= "PIFACE_Undefine";
  $hash->{SetFn}	= "PIFACE_Set";
  $hash->{GetFn}	= "PIFACE_Get";
  $hash->{NotifyFn}     = "PIFACE_Notify";
  $hash->{AttrFn}	= "PIFACE_Attr";
  $hash->{AttrList}	= $readingFnAttributes .
                          " defaultState:0,1,last,off pollInterval:1,2,3,4,5,6,7,8,9,10,off" .
                          " portMode0:tri,up" .
                          " portMode1:tri,up" .
                          " portMode2:tri,up" .
                          " portMode3:tri,up" .
                          " portMode4:tri,up" .
                          " portMode5:tri,up" .
                          " portMode6:tri,up" .
                          " portMode7:tri,up";
}

sub PIFACE_Define($$){
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  Log3($name, 3, "PIFACE $name active");
  readingsSingleUpdate($hash, "state", "active",1);
  return;
}

sub PIFACE_Undefine($$){
	my($hash, $name) = @_;
	RemoveInternalTimer($hash);
	return;
}

sub PIFACE_Set($@) {
	my ($hash, @a)	= @_;
	my $name = $hash->{NAME};
	my $port = $a[1];
	my $val  = $a[2];
	my ($adr, $cmd, $i, $j, $k);	
	my $usage = "Unknown argument $port, choose one of all 0:0,1 1:0,1 2:0,1 3:0,1 4:0,1 5:0,1 6:0,1 7:0,1 ";
	return $usage if $port eq "?";	
	if ($port ne "all") {
		$adr = $base + $port;
		Log3($name, 3, "PIFACE $name set port $port $val");
		$cmd = "/usr/local/bin/gpio -p write $adr $val";
		$cmd = `$cmd`;
		readingsSingleUpdate($hash, 'out'.$port, $val, 1);
	} else {
		Log3($name, 3, "PIFACE $name set ports $val");
		readingsBeginUpdate($hash);
		for($i = 0; $i < 8; $i ++) {
			$j = 2**$i;
			$k = ($val & $j);
			$k = ($k) ? 1 : 0;
			Log3($name, 3, "PIFACE $name set port $i $k");
			$adr = $base + $i;
			$cmd = "/usr/local/bin/gpio -p write $adr $k";
			$cmd = `$cmd`;
			readingsBulkUpdate($hash, 'out'.$i, $k);
		}
		readingsEndUpdate($hash, 1);
	}
	return;
}

sub PIFACE_Get($@){
	my ($hash, @a)	= @_;
	my $name = $hash->{NAME};
	my $port = $a[1];
	my ($adr, $cmd, $pin, $portMode, $val);
	my $usage = "Unknown argument $port, choose one of all:noArg in:noArg out:noArg ".
				"0:noArg 1:noArg  2:noArg  3:noArg  4:noArg ".
				"5:noArg  6:noArg  7:noArg";
	return $usage if $port eq "?";
	if ($port eq "all") {
	  PIFACE_Read_Inports(1, $hash);
          PIFACE_Read_Outports(1, $hash);                
	} elsif ($port eq "in") {
	  PIFACE_Read_Inports(0, $hash);	
	} elsif ($port eq "out") {
          PIFACE_Read_Outports(0, $hash);	
	} else {
	  $adr  = $base + $port;
	  $cmd = '/usr/local/bin/gpio -p read '.$adr;
	  $val = `$cmd`;
	  $val =~ s/\n//g;
	  $val =~ s/\r//g;
	  readingsSingleUpdate($hash, 'in'.$port, $val, 1);
	}
	return;
}

sub PIFACE_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  if ($attrName eq "pollInterval") {
    if (!defined $attrVal) {
      RemoveInternalTimer($hash);    
    } elsif ($attrVal !~ m/^(off|[1..10])$/) {
      RemoveInternalTimer($hash);    
      Log3($name, 3, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name pollInterval");
    } else {
      PIFACE_GetUpdate($hash);
    }
  } elsif ($attrName eq "defaultState") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(last|off|[01])$/) {
      Log3($name, 3, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name defaultState");
    }
  } elsif ($attrName =~ m/^portMode/) {
    my $port = substr($attrName, 8, 1);
    my $adr = $base + $port;
    my $portMode = $attrVal;
    my $val;
    $portMode = "tri" if (!defined $attrVal);
    if ($attrVal !~ m/^(tri|up)$/) {
      $portMode = "tri" ;
      Log3($name, 3, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name $port");
    }
    $cmd = '/usr/local/bin/gpio -p mode ' . $adr . ' ' . $portMode;
    $val = `$cmd`;
    $cmd = '/usr/local/bin/gpio -p read ' . $adr;
    $val = `$cmd`;
    $val =~ s/\n//g;
    $val =~ s/\r//g;
    readingsSingleUpdate($hash, 'in' . $port, $val, 1);
  }
  return;
}

sub PIFACE_Notify(@) {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME}; 
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED$/,@{$dev->{CHANGED}})){
    Log3($name, 3, "PIFACE $name initialized");
    PIFACE_Restore_Outports_State($hash);
    PIFACE_Read_Inports(0, $hash);
    PIFACE_Read_Outports(0, $hash);
    PIFACE_GetUpdate($hash);    
  }
  return;
}

sub PIFACE_Read_Outports($$){
	my ($updateMode, $hash) = @_;
        my $name = $hash->{NAME};
	my ($cmd, $i, $port, $val);
	readingsBeginUpdate($hash);
	for($i=0; $i<8; $i++){
		$port = $base + $i + 8;
		$cmd = '/usr/local/bin/gpio -p read '.$port;
		$val = `$cmd`;
		$val =~ s/\n//g;
		$val =~ s/\r//g;
		if ($updateMode == 1){
		  readingsBulkUpdate($hash, 'out'.$i, $val);
		} else {
		  readingsBulkUpdate($hash, 'out'.$i, $val) if(ReadingsVal($name, 'out'.$i, '') ne $val);		
		}
	}
	readingsEndUpdate($hash, 1);
	return;
}

sub PIFACE_Read_Inports($$){
	my ($updateMode, $hash) = @_;
        my $name = $hash->{NAME};
	my ($cmd, $i, $j, $port, $portMode, $val);
	readingsBeginUpdate($hash);
	for($i=0; $i<8; $i++){
	  $port = $base + $i;
	  $cmd = '/usr/local/bin/gpio -p read '.$port;
	  $val = `$cmd`;
	  $val =~ s/\n//g;
	  $val =~ s/\r//g;
	  if ($updateMode == 1) {
	    readingsBulkUpdate($hash, 'in'.$i, $val);
	  } else {
	    readingsBulkUpdate($hash, 'in'.$i, $val) if(ReadingsVal($name, 'in'.$i, '') ne $val);		
	  }
	}
	readingsEndUpdate($hash, 1);
	return;
}

sub PIFACE_Restore_Outports_State($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @cmd = ($name, 0, 0);
  my $defaultState = AttrVal($name, "defaultState", "off");
  if ($defaultState ne "off") {
    for(my $port = 0; $port < 8; $port ++){
      $cmd[1] = $port;
      if ($defaultState eq "last") {
        $cmd[2] = ReadingsVal($name, "out" . $port, 0);
      } elsif ($defaultState == 1) {
        $cmd[2] = 1;    
      } else {
        $cmd[2] = 0;    
      }
      PIFACE_Set($hash, @cmd);
    }
  }
  PIFACE_Read_Outports(1, $hash);
  return;
}

sub
PIFACE_GetUpdate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $pollInterval = AttrVal($name, "pollInterval", "off");
  if ($pollInterval ne "off") {
    InternalTimer(gettimeofday() + $pollInterval, "PIFACE_GetUpdate", $hash, 1);
    PIFACE_Read_Inports(0, $hash);
    PIFACE_Read_Outports(0, $hash);
  }  
  return;
}

1;

=pod
=begin html

<a name="PIFACE"></a>
<h3>PIFACE</h3>
<ul>

	<b>Prerequesits</b>
	<ul>
	
		<br/>
		Module needs wiringPi tools from <a href=http://wiringpi.com>http://wiringpi.com</a><br/><br/>
		<code>	git clone git://git.drogon.net/wiringPi<br/>
				cd wiringPi<br/>
				./build</code>
		<br/>

	</ul>
	<br/><br/>
	
	<a name="PIFACEdefine"></a>
	<b>Define</b>
	<ul>

		<br/>
		<code>define &lt;name&gt; PIFACE</code>
		<br/><br/>
		This module provides set/get functionality to control ports on RaspberryPi extension board PiFace
		<br/>

	</ul>
	<br/><br/>

	<a name="PIFACEset"></a>
	<b>Set-Commands</b><br/>
	<ul>

		<br/>
		<code>set &lt;name&gt; &lt;port&gt; &lt;value&gt;</code>
		<br/><br/>
		<ul>
			<li>set single port n to 1 (on) or 0 (off)<br/><br/>
				Examples:<br/>
				set &lt;name&gt; 3 1 =&gt; set port 3 on<br/>
				set &lt;name&gt; 5 0 =&gt; set port 5 off<br/></li>
			<br/>
			<li>set all ports in one command by bitmask<br/><br/>
				Example:<br/>
				set &lt;name&gt; all 255 =&gt; set all ports on<br/>
				set &lt;name&gt; all 0 =&gt; set all ports off<br/>
				set &lt;name&gt; all 170 =&gt; bitmask(170) = 10101010 =&gt; set ports 1 3 5 7 on, ports 0 2 4 6 off<br/>
				<br/>
				<ul>
					<code>port 76543210<br/>
					bit&nbsp; 10101010</code>
				</ul></li>
		</ul>

	</ul>
	<br/><br/>

	<a name="PIFACEget"></a>
	<b>Get-Commands</b><br/>
	<ul>

		<br/>
		<code>get &lt;name&gt; &lt;port&gt;</code>
		<br/><br/>
		<ul>
			<li>get state of single port<br/><br/>
				Example:<br/>
				get &lt;name&gt; 3 =&gt; get state of port 3<br/>
			</li>
			<br/>
			<li>get state of input ports and update changed readings<br/><br/>
				Example:<br/>
				get &lt;name&gt; in =&gt; get state of all input ports<br/>
			</li>
			<br/>
			<li>get state of out ports and update changed readings<br/><br/>
				Example:<br/>
				get &lt;name&gt; out =&gt; get state of all output ports<br/>
			</li>
			<br/>
			<li>get state of input and out ports and update all readings<br/><br/>
				Example:<br/>
				get &lt;name&gt; all =&gt; get state of all ports<br/>
			</li>
		</ul>

	</ul>
	<br/><br/>

	<a name="PIFACEattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
          <li><a name="defaultState">defaultState</a> last|off|0|1,
            [defaultState] = off is default.<br>
            Restoration of the status of the output port after a Fhem reboot.
          </li>
          <li><a name="pollInterval">pollInterval</a> off|1,2,...,9,10,
            [pollInterval] = off is default.<br>
            Define the polling interval of the input ports in seconds.
          </li>
          <li><a name="portMode&lt;0..7&gt;">portMode&lt;0..7&gt;</a> tri|up,
            [portMode&lt;0..7&gt;] = tri is default.<br>
            This enables (up) or disables (tri) the internal pull-up resistor on the given input port.
            You need to enable the pull-up if you want to read any of the on-board switches on the PiFace board.
          </li>
	  <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	</ul>
	<br/><br/>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>
		<li><b>&lt;out0..out7&gt;</b> - state of output port 0..7</li>
		<li><b>&lt;in0..in7&gt;</b> - state of input port 0..7</li>
	</ul>
	<br/><br/>

	<b>Author's notes</b><br/><br/>
	<ul>
		<li>Relays 0 and 1 have corresponding port 0 and 1</li>
		<li>Switches 0..3 have corresponding ports 0..3 and must be read with attr portMode<0..7> = up</li>
		<br/>
		<li>Have fun!</li><br/>

	</ul>

</ul>

=end html
=cut

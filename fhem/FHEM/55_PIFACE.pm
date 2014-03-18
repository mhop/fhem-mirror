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
sub PIFACE_Notify(@);
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
                          " disable:0,1 disabledForIntervals" .
                          " portMode0:tri,up" .
                          " portMode1:tri,up" .
                          " portMode2:tri,up" .
                          " portMode3:tri,up" .
                          " portMode4:tri,up" .
                          " portMode5:tri,up" .
                          " portMode6:tri,up" .
                          " portMode7:tri,up" .
                          " watchdog:on,off,silent watchdogInterval";
}

sub PIFACE_Define($$){
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  $hash->{NOTIFYDEV} = "global";
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
        if (IsDisabled($name)) {
          Log3 $name, 4, "PIFACE $name set commands disabled.";  
          return;
        }
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
      #RemoveInternalTimer($hash);    
    } elsif ($attrVal eq "off" || $attrVal ~~ [1..10]) {
      PIFACE_GetUpdate($hash);
    } else {
      #RemoveInternalTimer($hash);    
      Log3($name, 3, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name pollInterval");
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
    
  } elsif ($attrName eq "watchdog") {
    if (!defined $attrVal) {
      $attrVal = "off" ;
      CommandDeleteReading(undef, "$name watchdog");
    }
    if ($attrVal !~ m/^(on|off|silent)$/) {
      Log3($name, 3, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name watchdog");
    }
    if ($attrVal =~ m/^(on|silent)$/) {
      readingsSingleUpdate($hash, 'watchdog', 'start', 1);
      PIFACE_Watchdog($hash);
    }
    
  } elsif ($attrName eq "watchdogInterval") {
    if ($attrVal !~ m/^\d+$/ || $attrVal < 10) {
      Log3($name, 3, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name watchdogInterval");
    }
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
    PIFACE_Watchdog($hash);
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

sub
PIFACE_Watchdog($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my ($cmd, $port, $portMode, $valIn, $valOut0, $valOut1);
  my $watchdog = AttrVal($name, "watchdog", undef);
  my $watchdogInterval = AttrVal($name, "watchdogInterval", 60);
  $watchdogInterval = 10 if ($watchdogInterval !~ m/^\d+$/ || $watchdogInterval < 10);
  
  if (!defined $watchdog) {
    CommandDeleteReading(undef, "$name watchdog");
    
  } elsif ($watchdog =~ m/^(on|silent)$/) {
    InternalTimer(gettimeofday() + $watchdogInterval, "PIFACE_Watchdog", $hash, 1);
    for (my $i=0; $i<7; $i++) {
     $port = $base + $i;
     $portMode = AttrVal($name, "portMode" . $i, "tri");     
     $cmd = '/usr/local/bin/gpio -p mode ' . $port . ' ' . $portMode;
     $valIn = `$cmd`;
    }    
    $cmd = '/usr/local/bin/gpio -p mode 207 up';
    $valIn = `$cmd`;
    $cmd = '/usr/local/bin/gpio -p read 207';
    $valIn = `$cmd`;
    $valIn =~ s/\n//g;
    $valIn =~ s/\r//g;
    $cmd = '/usr/local/bin/gpio -p write 207 0';
    $cmd = `$cmd`;    
    $cmd = '/usr/local/bin/gpio -p read 215';
    $valOut0 = `$cmd`;
    $valOut0 =~ s/\n//g;
    $valOut0 =~ s/\r//g;    
    $cmd = '/usr/local/bin/gpio -p write 207 1';
    $cmd = `$cmd`;    
    $cmd = '/usr/local/bin/gpio -p read 215';
    $valOut1 = `$cmd`;
    $valOut1 =~ s/\n//g;
    $valOut1 =~ s/\r//g;    
    if ($valIn == 0 && $valOut0 == 0 && $valOut1 == 1) {
      readingsSingleUpdate($hash, "state", "active", 1) if (ReadingsVal($name, "state", undef) ne "active");
      readingsSingleUpdate($hash, ".watchdogRestart", 0, 1);
      if ($watchdog eq "on") {
        Log3($name, 3, "PIFACE $name Watchdog active");
        readingsSingleUpdate($hash, "watchdog", "ok", 1);
      } elsif ($watchdog eq "silent") {
        readingsSingleUpdate($hash, "watchdog", "ok", 1) if (ReadingsVal($name, "watchdog", undef) ne "ok");
      }
    } else {
      if ($watchdog eq "on") {    
        Log3($name, 3, "PIFACE $name Watchdog error");
        readingsSingleUpdate($hash, "watchdog", "error", 1);      
      } elsif ($watchdog eq "silent") {
        my $watchdogRestart = ReadingsVal($name, ".watchdogRestart", undef);      
        if (!defined($watchdogRestart) || $watchdogRestart == 0) {
          Log3($name, 3, "PIFACE $name Watchdog Fhem restart");
          readingsSingleUpdate($hash, "watchdog", "restart", 1);      
          readingsSingleUpdate($hash, ".watchdogRestart", 1, 1);      
          CommandSave(undef, undef);
          CommandShutdown(undef, "restart");
        } elsif ($watchdogRestart == 1) {
          Log3($name, 3, "PIFACE $name Watchdog OS restart");
          readingsSingleUpdate($hash, "watchdog", "restart", 1);
          readingsSingleUpdate($hash, ".watchdogRestart", 2, 1);      
          CommandSave(undef, undef);
          $cmd = 'shutdown -r now';
          #$cmd = 'sudo /sbin/shutdown -r now';
          #$cmd = 'sudo /sbin/shutdown -r now > /dev/null 2>&1';
	  $cmd = `$cmd`;        
        } elsif ($watchdogRestart == 2) {
          $attr{$name}{watchdog} = "off";
          Log3($name, 3, "PIFACE $name Watchdog error");
          Log3($name, 3, "PIFACE $name Watchdog deactivated");
          CommandDeleteReading(undef, "$name .watchdogRestart");          
          readingsSingleUpdate($hash, "watchdog", "error", 1);
          readingsSingleUpdate($hash, "state", "error",1);
          CommandSave(undef, undef);
        }
      }
    } 
  } else {
    Log3($name, 3, "PIFACE $name Watchdog off");  
    readingsSingleUpdate($hash, "watchdog", "off", 1);
  }
  return;
}

1;

=pod
=begin html

<a name="PIFACE"></a>
<h3>PIFACE</h3>
<ul>
  The PIFACE module managed the <a href=http://www.raspberrypi.org/>Raspberry Pi</a> extension board <a href=http://www.piface.org.uk/products/piface_digital/>PiFace Digital</a>.<br>
  PIFACE controls the input ports 0..7 and output ports 0..7.
  <ul>
  <li>The relays 0 and 1 have corresponding output port 0 and 1.</li>
  <li>The switches 0..3 have corresponding input ports 0..3 and must be read with attr portMode<0..7> = up</li>
  </ul>
  The status of the ports can be displayed periodically. The update of the states via interrupt is not supported.<br>
  The module can be periodically monitored by a watchdog function.<br>
  The ports can be read and controlled individually by the function <a href="#readingsProxy">readingsProxy</a>.<br>
  PIFACE is tested with the Raspbian OS.<br><br>
  
  <b>Preparatory Work</b><br>
  The use of PIFACE module requires some preparatory work.
  <ul>
    <br>
    <li>Module needs tools from <a href=http://wiringpi.com>Wiring Pi</a>. Install it with<br>
      <code>git clone git://git.drogon.net/wiringPi<br>
        cd wiringPi<br>
        ./build</code><br>
    </li>
    <li>PiFace Digital need the SPI pins on the Raspberry Pi to be enabled in order to function.
    Start <code>sudo raspi-config</code>, select <code>Option 8 Advanced Options</code>
    and set the <code>A5 SPI</code> option to "Yes".
    </li>
    <li>The function of the PiFace Digital can be tested at OS command line. For example:<br>
    <code>gpio -p readall</code><br>
    <code>gpio -p read 200</code><br>
    <code>gpio -p write 201 0</code> or <code>gpio -p write 201 1</code><br>
    </li>
    <li>The watchdog function monitors the input port 7 and the output port 7.<br>
      If the watchdog is enabled, this ports can not be used for other tasks.
      In order to monitor the input port 7, it must be connected to the ground!<br>
      The OS command "shutdown" must be enable for fhem if an OS restart is to
      be executed in case of malfunction. For example, with <code>chmod +s /sbin/shutdown</code>
      or <code>sudo chmod +s /sbin/shutdown</code>.<br>
    </li>
    
  </ul>
  <br>
	
  <a name="PIFACEdefine"></a>
  <b>Define</b>
    <ul><br>
       <code>define &lt;name&gt; PIFACE</code><br>
    </ul><br>

	<a name="PIFACEset"></a>
	<b>Set</b><br/>
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
	<br>

	<a name="PIFACEget"></a>
	<b>Get</b><br/>
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
	<br>

	<a name="PIFACEattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
          <li><a name="PIFACE_defaultState">defaultState</a> last|off|0|1,
            [defaultState] = off is default.<br>
            Restoration of the status of the output port after a Fhem reboot.
          </li>
          <li><a href="#PIFACE_disable">disable</a> 0|1<br>
            If applied set commands will not be executed.
          </li>
          <li><a href="#PIFACE_disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...<br>
            Space separated list of HH:MM tupels. If the current time is between
            the two time specifications, set commands will not be executed. Instead of
            HH:MM you can also specify HH or HH:MM:SS. To specify an interval
            spawning midnight, you have to specify two intervals, e.g.:
            <ul>
              23:00-24:00 00:00-01:00
            </ul>
          </li>
          <li><a name="PIFACE_pollInterval">pollInterval</a> off|1,2,...,9,10,
            [pollInterval] = off is default.<br>
            Define the polling interval of the input ports in seconds.
          </li>
          <li><a name="PIFACE_portMode&lt;0..7&gt;">portMode&lt;0..7&gt;</a> tri|up,
            [portMode&lt;0..7&gt;] = tri is default.<br>
            This enables (up) or disables (tri) the internal pull-up resistor on the given input port.
            You need to enable the pull-up if you want to read any of the on-board switches on the PiFace board.
          </li>
	  <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
          <li><a name="PIFACE_watchdog">watchdog</a> off|on|silent,
            [watchdog] = off is default.<br>
            The function of the PiFace extension can be monitored periodically.
            The watchdog module checks the function of ports in7 and out7.
            If the watchdog function is to be used, ports in7 and out7 are reserved for this purpose.
            The port 7 must be connected to ground.<br>
            If [watchdog] = on, the result of which is periodically logged and written to the reading watchdog.<br>
            If [watchdog] = silent, FHEM is restarted after the first error detected.
            If the error could not be eliminated, then the Raspberry operating system is restarted.
            If the error is not corrected as well, the monitoring function is disabled and the error is logged.
          </li>
          <li><a name="PIFACE_watchdogInterval">watchdogInterval</a> 10..65535,
            [watchdogInterval] = 60 is default.<br>
            Interval between two monitoring tests in seconds.
          </li>
	</ul>
	<br>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>
		<li>&lt;out0..out7&gt;: 0|1<br>
		state of output port 0..7</li>
		<li>&lt;in0..in7&gt;: 0|1<br>
		state of input port 0..7</li>
		<li>watchdog: off|ok|error|restart|start<br>
		state of the watchdog function</li>
		<li>state: active|error</li><br>
	</ul>
	
</ul>

=end html
=cut

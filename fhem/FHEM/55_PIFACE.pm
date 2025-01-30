# $Id$
# An FHEM Perl module to control RaspberryPi extension board PiFace Digital
# The PiFace Digital is an add-on board for the Raspberry Pi featuring 8 open-collector outputs,
# with 2 relays and 8 inputs (with 4 on-board buttons).
# These functions are fairly well fixed in the hardware,
# so only the read, write and internal pull-up commands are implemented.

package main;
use strict;
use warnings;

sub PIFACE_Define;
sub PIFACE_Undefine;
sub PIFACE_Set;
sub PIFACE_Get;
sub PIFACE_Notify;
sub PIFACE_Attr;

my $base = 200;
my $gpioCmd;
if (-e '/usr/local/bin/gpio') {
  $gpioCmd = '/usr/local/bin/gpio';
} else {
  $gpioCmd = 'gpio';
}

sub PIFACE_Initialize {
  my ($hash) = @_;
  $hash->{DefFn}	= "PIFACE_Define";
  $hash->{UndefFn}	= "PIFACE_Undefine";
  $hash->{SetFn}	= "PIFACE_Set";
  $hash->{GetFn}	= "PIFACE_Get";
  $hash->{NotifyFn}     = "PIFACE_Notify";
  $hash->{ShutdownFn}   = "PIFACE_Shutdown";
  $hash->{AttrFn}	= "PIFACE_Attr";
  $hash->{AttrList}	= $readingFnAttributes .
                          " defaultState:0,1,last,off pollInterval:0.5,0.75,1,1.5,2,3,4,5,6,7,8,9,10,off" .
                          " disable:0,1 disabledForIntervals" .
                          " portMode0:tri,up" .
                          " portMode1:tri,up" .
                          " portMode2:tri,up" .
                          " portMode3:tri,up" .
                          " portMode4:tri,up" .
                          " portMode5:tri,up" .
                          " portMode6:tri,up" .
                          " portMode7:tri,up" .
                          " shutdownClearIO:no,yes" .
                          " watchdog:on,off,silent watchdogInterval";
}

sub PIFACE_Define {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  $hash->{NOTIFYDEV} = "global";
  $hash->{helper}{timer}{poll} = {hash => $hash, param => 'PIFACE_GetUpdate'};
  $hash->{helper}{timer}{watchdog} = {hash => $hash, param => 'PIFACE_Watchdog'};
  Log3($name, 2, "PIFACE $name active");
  readingsSingleUpdate($hash, "state", "active",1);
  return;
}

sub PIFACE_Undefine {
  my($hash, $name) = @_;
  RemoveInternalTimer($hash->{helper}{timer}{poll});
  RemoveInternalTimer($hash->{helper}{timer}{watchdog});
  return;
}

sub PIFACE_Set {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
        if (IsDisabled($name)) {
          Log3 $name, 4, "PIFACE $name set commands disabled.";
          return;
        }
        shift @a;
        my $port = '';
        $port = shift @a if (defined $a[0]);
	my $val = shift @a if (defined $a[0]);
	my $all = ReadingsVal($name, 'all', 0);
	my ($adr, $cmd, $i, $j, $k);
	my $usage = "Unknown argument $port, choose one of all:bitfield,8,255 0:0,1 1:0,1 2:0,1 3:0,1 4:0,1 5:0,1 6:0,1 7:0,1 ";
	return $usage if ($port eq '' || $port eq "?" || !defined($val));
	readingsBeginUpdate($hash);
	if ($port ne "all") {
		$adr = $base + $port;
		Log3($name, 3, "PIFACE $name set port $port $val");
		$cmd = "$gpioCmd -x mcp23s17:$base:0:0 write $adr $val";
		$cmd = `$cmd`;
		readingsBulkUpdate($hash, 'out' . $port, $val);
		$all = $val == 1 ? $all | 2 ** $port : $all & (2 ** $port ^ 255);
		readingsBulkUpdate($hash, 'all', $all);
	} else {
		readingsBulkUpdateIfChanged($hash, 'all', $val);
		for($i = 0; $i < 8; $i ++) {
			$j = 2**$i;
			$k = $val & $j;
			$k = $k ? 1 : 0;
			Log3($name, 3, "PIFACE $name set port $i $k");
			$adr = $base + $i;
			$cmd = "$gpioCmd -x mcp23s17:$base:0:0 write $adr $k";
			$cmd = `$cmd`;
			readingsBulkUpdate($hash, 'out' . $i, $k);
		}
	}
	readingsEndUpdate($hash, 1);
	return;
}

sub PIFACE_Get {
  my ($hash, @a)	= @_;
  my $name = $hash->{NAME};
  return undef if (IsDisabled($name));
  shift @a;
  my $port = '';
  $port = shift @a if (defined $a[0]);
  my ($adr, $cmd, $pin, $portMode, $val);
  my $usage = "Unknown argument $port, choose one of all:noArg in:noArg out:noArg ".
		"0:noArg 1:noArg  2:noArg  3:noArg  4:noArg ".
		"5:noArg  6:noArg  7:noArg";
  return $usage if ($port eq '' || $port eq "?");
  if ($port eq "all") {
    PIFACE_Read_Inports(1, $hash);
    PIFACE_Read_Outports(1, $hash);
    Log3($name, 3, "PIFACE $name get port $port");
  } elsif ($port eq "in") {
    PIFACE_Read_Inports(1, $hash);
    Log3($name, 3, "PIFACE $name get port $port");
  } elsif ($port eq "out") {
    PIFACE_Read_Outports(1, $hash);
    Log3($name, 3, "PIFACE $name get port $port");
  } else {
    # get state of in port
    $adr  = $base + 8 + $port;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 read $adr";
    $val = `$cmd`;
    $val =~ s/\n//g;
    $val =~ s/\r//g;
    readingsSingleUpdate($hash, 'in' . $port, $val, 1);
    Log3($name, 3, "PIFACE $name get port in$port");
  }
  return;
}

sub PIFACE_Attr {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  return undef if (!$init_done);
  if ($attrName eq "pollInterval") {
    if (!defined $attrVal) {
      RemoveInternalTimer($hash->{helper}{timer}{poll}, $hash->{helper}{timer}{poll}{param});
    } elsif ($attrVal eq "off" || ($attrVal =~ m/^\d+(\.\d+)?$/ && $attrVal > 0.5 && $attrVal <= 10)) {
      PIFACE_GetUpdate($hash->{helper}{timer}{poll});
    } else {
      RemoveInternalTimer($hash->{helper}{timer}{poll}, $hash->{helper}{timer}{poll}{param});
      Log3($name, 2, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name pollInterval");
    }

  } elsif ($attrName eq "defaultState") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^last|off|[01]$/) {
      Log3($name, 2, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name defaultState");
    }

  } elsif ($attrName =~ m/^portMode(.)/) {
    my $port = $1;
    #my $port = substr($attrName, 8, 1);
    my $adr = $base + 8 + $port;
    my $portMode = $attrVal;
    my $val;
    $portMode = "tri" if (!defined $attrVal);
    if ($attrVal !~ m/^tri|up$/) {
      $portMode = "tri" ;
      Log3($name, 2, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name portMode$port");
    }
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 mode $adr $portMode";
    $val = `$cmd`;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 read $adr";
    $val = `$cmd`;
    $val =~ s/\n//g;
    $val =~ s/\r//g;
    readingsSingleUpdate($hash, 'in' . $port, $val, 1);

  } elsif ($attrName eq "shutdownClearIO") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^no|yes$/) {
      Log3($name, 2, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name defaultState");
    }

  } elsif ($attrName eq "watchdog") {
    if (!defined $attrVal) {
      $attrVal = "off" ;
      readingsDelete($hash, "watchdog");
    }
    if ($attrVal !~ m/^on|off|silent$/) {
      Log3($name, 2, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name watchdog");
    }
    if ($attrVal =~ m/^on|silent$/) {
      readingsSingleUpdate($hash, 'watchdog', 'start', 1);
      $attr{$name}{$attrName} = $attrVal;
      $hash->{helper}{timer}{watchdog} = {hash => $hash, param => 'PIFACE_Watchdog'};
      PIFACE_Watchdog($hash->{helper}{timer}{watchdog});
    }

  } elsif ($attrName eq "watchdogInterval") {
    if ($attrVal !~ m/^\d+$/ || $attrVal < 10) {
      Log3($name, 2, "PIFACE $name attribute-value [$attrName] = $attrVal wrong");
      CommandDeleteAttr(undef, "$name watchdogInterval");
    }
  }
  return;
}

sub PIFACE_Notify {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  return undef if (IsDisabled($name));
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED|REREADCFG$/,@{$dev->{CHANGED}})){
    PIFACE_Restore_Inports_Mode($hash);
    PIFACE_Restore_Outports_State($hash);
    PIFACE_GetUpdate($hash->{helper}{timer}{poll});
    PIFACE_Watchdog($hash->{helper}{timer}{watchdog});
    Log3($name, 2, "PIFACE $name initialized");
  }
  return undef;
}

sub PIFACE_Read_Outports {
	my ($updateMode, $hash) = @_;
        my $name = $hash->{NAME};
	my ($all, $cmd, $i, $j, $port, $val);
	$all = 0;
	readingsBeginUpdate($hash);
	for($i = 0; $i < 8; $i++){
		$port = $base + $i;
		$cmd = "$gpioCmd -x mcp23s17:$base:0:0 read $port";
		$val = `$cmd`;
		$val =~ s/\n//g;
		$val =~ s/\r//g;
		$j = 2**$i;
		$all |= $j if ($val == 1);
		if ($updateMode == 1){
		  readingsBulkUpdate($hash, 'out'.$i, $val);
		} else {
		  readingsBulkUpdateIfChanged($hash, 'out'.$i, $val);
		}
	}
	readingsBulkUpdateIfChanged($hash, 'all', $all);
	readingsEndUpdate($hash, 1);
	return;
}

sub PIFACE_Read_Inports {
	my ($updateMode, $hash) = @_;
        my $name = $hash->{NAME};
	my ($cmd, $i, $j, $port, $portMode, $val);
	readingsBeginUpdate($hash);
	for($i = 0; $i < 8; $i++){
	  $port = $base + 8 + $i;
	  $cmd = "$gpioCmd -x mcp23s17:$base:0:0 read $port";
	  $val = `$cmd`;
	  $val =~ s/\n//g;
	  $val =~ s/\r//g;
	  if ($updateMode == 1) {
	    readingsBulkUpdate($hash, 'in'.$i, $val);
	  } else {
	    readingsBulkUpdateIfChanged($hash, 'in'.$i, $val);
	  }
	}
	readingsEndUpdate($hash, 1);
	return;
}

sub PIFACE_Restore_Outports_State {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @cmd = ($name, 0, 0);
  my $defaultState = AttrVal($name, "defaultState", "off");
  my ($adr, $cmd, $valOut);
  if ($defaultState ne "off") {
    for (my $port = 0; $port < 8; $port ++) {
      $cmd[1] = $port;
      $adr = $base + $port;
      $cmd = "$gpioCmd -x mcp23s17:$base:0:0 mode $adr out";
      $valOut = `$cmd`;
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

sub PIFACE_Restore_Inports_Mode {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my ($cmd, $port, $portMode, $valIn);
  for (my $i = 0; $i <= 7; $i++) {
    $port = $base + 8 + $i;
    $portMode = AttrVal($name, "portMode" . $i, "tri");
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 mode $port in";
    $valIn = `$cmd`;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 mode $port $portMode";
    $valIn = `$cmd`;
  }
  PIFACE_Read_Inports(1, $hash);
  return;
}

sub PIFACE_GetUpdate {
  #my ($hash) = @_;
  my ($functionHash) = @_;
  my $hash = $functionHash->{hash};
  my $param = $functionHash->{param};
  my $name = $hash->{NAME};
  my $pollInterval = AttrVal($name, "pollInterval", "off");
  if ($pollInterval ne "off") {
    RemoveInternalTimer($hash->{helper}{timer}{poll}, $param);
    InternalTimer(gettimeofday() + $pollInterval, $param, $hash->{helper}{timer}{poll}, 0);
    PIFACE_Read_Inports(0, $hash);
    PIFACE_Read_Outports(0, $hash);
  }
  return;
}

sub PIFACE_Watchdog {
  #my ($hash) = @_;
  my ($functionHash) = @_;
  my $hash = $functionHash->{hash};
  my $param = $functionHash->{param};
  my $name = $hash->{NAME};
  return undef if (IsDisabled($name));
  my ($cmd, $port, $portMode, $valIn, $valOut0, $valOut1);
  my $watchdog = AttrVal($name, "watchdog", undef);
  my $watchdogInterval = AttrVal($name, "watchdogInterval", 60);
  $watchdogInterval = 10 if ($watchdogInterval !~ m/^\d+$/ || $watchdogInterval < 10);

  if (!defined $watchdog) {
    readingsDelete($hash, "watchdog");

  } elsif ($watchdog =~ m/^on|silent$/) {
    RemoveInternalTimer($hash->{helper}{timer}{watchdog}, $param);
    InternalTimer(gettimeofday() + $watchdogInterval, $param, $hash->{helper}{timer}{watchdog}, 0);
    for (my $i = 0; $i < 7; $i++) {
     $port = $base + 8 + $i;
     $portMode = AttrVal($name, "portMode" . $i, "tri");
     $cmd = "$gpioCmd -x mcp23s17:$base:0:0 mode $port $portMode";
     $valIn = `$cmd`;
    }
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 mode 215 up";
    $valIn = `$cmd`;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 read 215";
    $valIn = `$cmd`;
    $valIn =~ s/\n//g;
    $valIn =~ s/\r//g;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 write 207 0";
    $cmd = `$cmd`;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 read 207";
    $valOut0 = `$cmd`;
    $valOut0 =~ s/\n//g;
    $valOut0 =~ s/\r//g;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 write 207 1";
    $cmd = `$cmd`;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 read 207";
    $valOut1 = `$cmd`;
    $valOut1 =~ s/\n//g;
    $valOut1 =~ s/\r//g;
    #Log3($name, 3, "PIFACE $name Watchdog in7: $valIn out7: $valOut0 $valOut1");
    if ($valIn == 0 && $valOut0 == 0 && $valOut1 == 1) {
      readingsSingleUpdate($hash, "state", "active", 1) if (ReadingsVal($name, "state", '') ne "active");
      readingsSingleUpdate($hash, ".watchdogRestart", 0, 1);
      if ($watchdog eq "on") {
        Log3($name, 2, "PIFACE $name Watchdog active");
        readingsSingleUpdate($hash, "watchdog", "ok", 1);
      } elsif ($watchdog eq "silent") {
        readingsSingleUpdate($hash, "watchdog", "ok", 1) if (ReadingsVal($name, "watchdog", '') ne "ok");
      }
    } else {
      if ($watchdog eq "on") {
        Log3($name, 2, "PIFACE $name Watchdog error");
        readingsSingleUpdate($hash, "watchdog", "error", 1);
      } elsif ($watchdog eq "silent") {
        my $watchdogRestart = ReadingsVal($name, ".watchdogRestart", undef);
        if (!defined($watchdogRestart) || $watchdogRestart == 0) {
          Log3($name, 2, "PIFACE $name Watchdog Fhem restart");
          readingsSingleUpdate($hash, "watchdog", "restart", 1);
          readingsSingleUpdate($hash, ".watchdogRestart", 1, 1);
          CommandSave(undef, undef);
          CommandShutdown(undef, "restart");
        } elsif ($watchdogRestart == 1) {
          Log3($name, 2, "PIFACE $name Watchdog OS restart");
          readingsSingleUpdate($hash, "watchdog", "restart", 1);
          readingsSingleUpdate($hash, ".watchdogRestart", 2, 1);
          CommandSave(undef, undef);
          $cmd = '/sbin/shutdown -a -r now';
          #$cmd = 'shutdown -r now';
          #$cmd = 'sudo /sbin/shutdown -r now';
          #$cmd = 'sudo /sbin/shutdown -r now > /dev/null 2>&1';
	  $cmd = `$cmd`;
        } elsif ($watchdogRestart == 2) {
          $attr{$name}{watchdog} = "off";
          Log3($name, 2, "PIFACE $name Watchdog error");
          Log3($name, 2, "PIFACE $name Watchdog deactivated");
          readingsDelete($hash, ".watchdogRestart");
          readingsSingleUpdate($hash, "watchdog", "error", 1);
          readingsSingleUpdate($hash, "state", "error",1);
          CommandSave(undef, undef);
        }
      }
    }
  } else {
    Log3($name, 2, "PIFACE $name Watchdog off");
    readingsSingleUpdate($hash, "watchdog", "off", 1);
  }
  return;
}

sub PIFACE_Shutdown {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return undef if (AttrVal($name, "shutdownClearIO", 'no') eq 'no');
  my ($cmd, $port);
  for (my $i = 0; $i <= 7; $i++) {
    $port = $base + $i;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 write $port 0";
    $cmd = `$cmd`;
    $port = $base + $i + 8;
    $cmd = "$gpioCmd -x mcp23s17:$base:0:0 mode $port tri";
    $cmd = `$cmd`;
  }
  return undef;
}

1;

=pod
=item summary    Raspberry PiFace Digital Controler
=item summary_DE Raspberry PiFace Digital Schnittstellenerweiterung
=begin html

<a id="PIFACE"></a>
<h3>PIFACE</h3>
<ul>
  The PIFACE module managed the <a href=http://www.raspberrypi.org/>Raspberry Pi</a> extension board PiFace Digital.<br>
  PIFACE controls the input ports 0..7 and output ports 0..7.
  <ul>
  <li>The relays 0 and 1 have corresponding output port 0 and 1.</li>
  <li>The switches 0..3 have corresponding input ports 0..3 and must be read with attr portMode<0..7> = up</li>
  </ul>
  The status of the ports can be displayed periodically. The update of the states via interrupt is not supported.<br>
  The module can be periodically monitored by a watchdog function.<br>
  The ports can be read and controlled individually by the function <a href="#readingsProxy">readingsProxy</a>.<br>
  PIFACE is tested with
  <ul>
  <li>Raspbian OS, Debian version 11 (bullseye) 32 bit and wiringpi_3.2-bullseye_armhf</li>
  <li>Raspbian OS, Debian version 12 (bookworm) 64 bit and wiringpi_3.12_arm64 (Raspberry Pi 5 B)</li>
  </ul>
  <br><br>
  <b>Preparatory Work</b><br>
  The use of PIFACE module requires some preparatory work. The module needs the <a href=http://wiringpi.com>Wiring Pi</a> tool.
  <ul>
    <br>
    Raspberry Pi OS Bullseye<br>
    The current WiringPi software package can be found at <code>https://github.com/WiringPi/WiringPi/</code>.
    Please note the current version number for the download path and the file name.<br>.
    <li>Install 64 bit version with<br>
      <code>wget https://github.com/WiringPi/WiringPi/releases/download/x.y/wiringpi-x.y-arm64.deb<br>
        dpkg -i wiringpi-x.y-arm64.deb</code><br>
    </li>
    <li>Install 32 bit version with<br>
      <code>wget https://github.com/WiringPi/WiringPi/releases/download/x.y/wiringpi-x.y-armhf.deb<br>
        dpkg -i wiringpi-x.y-armhf.deb</code><br>
    </li>
    <li>PiFace Digital need the SPI pins on the Raspberry Pi to be enabled in order to function.
    Start <code>sudo raspi-config</code> and set the <code>SPI</code> option to "Yes".
    </li>
    <li>The function of the PiFace Digital can be tested at OS command line. For example:<br>
    <code>gpio -x mcp23s17:200:0:0 readall</code><br>
    <code>gpio -x mcp23s17:200:0:0 read 200</code><br>
    <code>gpio -x mcp23s17:200:0:0 write 201 0</code> or <code>gpio -x mcp23s17:200:0:0 write 201 1</code><br>
    </li>
    <li>The watchdog function monitors the input port 7 and the output port 7.<br>
      If the watchdog is enabled, this ports can not be used for other tasks.
      In order to monitor the input port 7, it must be connected to the ground!<br>
      The OS command "shutdown" must be enable for fhem if an OS restart is to
      be executed in case of malfunction. For example, with <code>chmod +s /sbin/shutdown</code>
      or <code>sudo chmod +s /sbin/shutdown</code>.<br>
    </li>
  </ul>
  <ul>
    <br>
    Raspberry Pi OS Jessie / Stretch / Buster<br>
    <li>Install it with<br>
      <code>sudo apt-get install wiringpi</code><br>
    </li>
    <li>PiFace Digital need the SPI pins on the Raspberry Pi to be enabled in order to function.
    Start <code>sudo raspi-config</code> and set the <code>SPI</code> option to "Yes".
    </li>
    <li>The function of the PiFace Digital can be tested at OS command line. For example:<br>
    <code>gpio -x mcp23s17:200:0:0 readall</code><br>
    <code>gpio -x mcp23s17:200:0:0 read 200</code><br>
    <code>gpio -x mcp23s17:200:0:0 write 201 0</code> or <code>gpio -x mcp23s17:200:0:0 write 201 1</code><br>
    </li>
    <li>The watchdog function monitors the input port 7 and the output port 7.<br>
      If the watchdog is enabled, this ports can not be used for other tasks.
      In order to monitor the input port 7, it must be connected to the ground!<br>
      The OS command "shutdown" must be enable for Fhem if an OS restart is to
      be executed in case of malfunction. For example, with the help of the shutdown ACLs (Access Control Lists).
      This allows you to privilege a maximum of 32 users to boot the computer. To do this, edit the file
      <code>/etc/shutdown.allow</code> and insert the authorized user <code>fhem</code> there (each the login name per line).
      Now Fhem can reboot the operating system with <code>/sbin/shutdown -a -r now</code>.<br>
    </li>
  </ul>
  <br>

  <a id="PIFACE-define"></a>
  <b>Define</b>
    <ul><br>
       <code>define &lt;name&gt; PIFACE</code><br>
    </ul><br>

  <a id="PIFACE-set"></a>
  <b>Set</b><br/>
    <ul><br/>
      <code>set &lt;name&gt; &lt;port&gt; &lt;value&gt;</code>
    <br/><br/>
      <ul>
        <li>set single port n to 1 (on) or 0 (off)<br/><br/>
	  Examples:<br/>
	  set &lt;name&gt; 3 1 =&gt; set port 3 on<br/>
	  set &lt;name&gt; 5 0 =&gt; set port 5 off<br/>
	</li>
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

  <a id="PIFACE-get"></a>
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

	<a id="PIFACE-attr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
          <li><a id="PIFACE-attr-defaultState">defaultState</a> last|off|0|1,
            [defaultState] = off is default.<br>
            Restoration of the status of the output port after a Fhem reboot.
          </li>
          <li><a href="#disable">disable</a> 0|1<br>
            If applied set commands will not be executed.
          </li>
          <li><a href="#disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...<br>
            Space separated list of HH:MM tupels. If the current time is between
            the two time specifications, set commands will not be executed. Instead of
            HH:MM you can also specify HH or HH:MM:SS. To specify an interval
            spawning midnight, you have to specify two intervals, e.g.:
            <ul>
              23:00-24:00 00:00-01:00
            </ul>
          </li>
          <li><a id="PIFACE-attr-pollInterval">pollInterval</a> off|0.5|0.75|1,1.5,2,...,9,10,
            [pollInterval] = off is default.<br>
            Define the polling interval of the input ports in seconds.
          </li>
          <li><a id="PIFACE-attr-portMode0">portMode0</a><br>
              <a id="PIFACE-attr-portMode1">portMode1</a><br>
              <a id="PIFACE-attr-portMode2">portMode2</a><br>
              <a id="PIFACE-attr-portMode3">portMode3</a><br>
              <a id="PIFACE-attr-portMode4">portMode4</a><br>
              <a id="PIFACE-attr-portMode5">portMode5</a><br>
              <a id="PIFACE-attr-portMode6">portMode6</a><br>
              <a id="PIFACE-attr-portMode7">portMode7</a> tri|up,
            [portMode&lt;0..7&gt;] = tri is default.<br>
            This enables (up) or disables (tri) the internal pull-up resistor on the given input port.
            You need to enable the pull-up if you want to read any of the on-board switches on the PiFace board.
          </li>
	  <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
          <li><a id="PIFACE-attr-shutdownClearIO">shutdownClearIO</a> no|yes,
            [shutdownClearIO] = no is default.<br>
            Clear IO ports during shutdown.
          </li>
          <li><a id="PIFACE-attr-watchdog">watchdog</a> off|on|silent,
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
          <li><a id="PIFACE-attr-watchdogInterval">watchdogInterval</a> 10..65535,
            [watchdogInterval] = 60 is default.<br>
            Interval between two monitoring tests in seconds.
          </li>
	</ul>
	<br>

        <a id="PIFACE-events"></a>
	<b>Generated Events:</b>
	<br/><br/>
	<ul>
		<li>&lt;all&gt;: 0...255<br>
		state of all output port as bitmap</li>
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

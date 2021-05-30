
#
# $Id$
#
# 89_AndroidDBHost
#
# Version 0.4
#
# FHEM Integration for Android Debug Bridge
#
# Dependencies:
#
#   - Perl Packages: IPC::Open3
#   - Android Platform Tools
#
# Install Android Platform Tools:
#
#   Raspbian/Debian: apt-get install android-sdk-platform-tools
#   Windows/MacOSX/Linux x86: https://developer.android.com/studio/releases/platform-tools
#



package main;

use strict;
use warnings;

sub AndroidDBHost_Initialize ($)
{
   my ($hash) = @_;

   $hash->{DefFn}      = "AndroidDBHost::Define";
   $hash->{UndefFn}    = "AndroidDBHost::Undef";
   $hash->{SetFn}      = "AndroidDBHost::Set";
   $hash->{GetFn}      = "AndroidDBHost::Get";
   $hash->{NotifyFn}   = "AndroidDBHost::Notify";
   $hash->{ShutdownFn} = "AndroidDBHost::Shutdown";

	$hash->{parseParams} = 1;
}

package AndroidDBHost;

use strict;
use warnings;

use Data::Dumper;
use IPC::Open3;

use SetExtensions;
# use POSIX;

use GPUtils qw(:all); 

BEGIN {
    GP_Import(qw(
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBulkUpdateIfChanged
        readingsBeginUpdate
        readingsEndUpdate
		  devspec2array
        Log3
        AttrVal
        ReadingsVal
        InternalTimer
        RemoveInternalTimer
        init_done
        deviceEvents
        gettimeofday
        defs
    ))
};

sub Define ($$$)
{
   my ($hash, $a, $h) = @_;
   
	my $name = $hash->{NAME};
	my $usage = "define $name AndroidDB [server={host}[:{port}]] [adb={path}]";
	
	# Set parameters
	my ($host, $port) = split (':', $h->{ADB} // 'localhost:5037');
	$hash->{adb}{host} = $host;
	$hash->{adb}{port} = $port // 5037;
	$hash->{adb}{cmd}  = $h->{adb} // '/usr/bin/adb';
	$hash->{Clients}   = ':AndroidDB:';
	$hash->{NOTIFYDEV} = 'global,TYPE=(AndroidDBHost|AndroidDB)';
	
	# Check path and rights of platform tools
	return "ADB command not found or is not executable in $hash->{adb}{pt}" if (! -x "$hash->{adb}{cmd}");
	
	# Check ADB settings, start adb server
	CheckADBServer ($hash);
	
	return "ADB server not running or cannot be started on host $hash->{adb}{host}" if ($hash->{STATE} eq 'stopped');
	
   return undef;
}

sub Undef ($$)
{
   my ($hash, $name) = @_;
   
   Log3 $name, 2, "Stopping ADB server ...";
   RemoveInternalTimer ($hash);
	Execute ($hash, 'kill-server') if (IsADBServerRunning ($hash));
   
   return undef;
}

sub Shutdown ($)
{
	my $hash = shift;
	
   RemoveInternalTimer ($hash);
	Execute ($hash, 'kill-server') if (IsADBServerRunning ($hash));
}

##############################################################################
# Initialize ADB server checking timer after FHEM is initialized
##############################################################################

sub Notify ($$)
{
	my ($hash, $devhash) = @_;

	return if (AttrVal ($hash->{NAME}, 'disable', 0) == 1);
		
	my $events = deviceEvents ($devhash, 1);
	return if (!$events);
	
	if ($devhash->{NAME} eq 'global' && grep (/INITIALIZED/, @$events)) {
		InternalTimer (gettimeofday()+60, 'AndroidDBHost::CheckADBServerTimer', $hash, 0);
	}
}

##############################################################################
# Timer function to check periodically, if ADB server is running
##############################################################################

sub CheckADBServerTimer ($)
{
	my $hash = shift;
	
	CheckADBServer ($hash);
	
	InternalTimer (gettimeofday()+60, 'AndroidDBHost::CheckADBServerTimer', $hash, 0);
}

##############################################################################
# Start ADB server if it's not running
##############################################################################

sub CheckADBServer ($)
{
	my $hash = shift;
	
	my $newState = 'stopped';
	for (my $i=0; $i<3; $i++) {
		Log3 $hash->{NAME}, 4, 'Check if ADB server is running. '.($i+1).'. attempt';
		if (IsADBServerRunning ($hash)) {
			$newState = 'running';
			last;
		}
	
		if ($hash->{adb}{host} eq 'localhost') {
			# Start ADB server
			Log3 $hash->{NAME}, 2, "Periodical check found no running ADB server. Starting ADB server ...";
			Execute ($hash, 'start-server');
		}

		sleep (1);
	}
	
	readingsSingleUpdate ($hash, 'state', $newState, 1);

	# Update status of client devices
	UpdateClientStates ($hash) if ($newState eq 'running');
	
	return $newState eq 'running' ? 1 : 0;
}

##############################################################################
# Update connection states of client devices
##############################################################################

sub UpdateClientStates ($)
{
	my $hash = shift;
	
	my $device = GetDeviceList ($hash) // return 0;

	foreach my $d (keys %defs) {
		my $clHash = $defs{$d};
		if ($clHash->{TYPE} eq 'AndroidDB') {
			my $clState = $device->{$clHash->{ADBDevice}} // 'disconnected';
			$clState =~ s/device/connected/;
			readingsSingleUpdate ($clHash, 'state', $clState, 1);
		}
	}
	
	return 1;
}

##############################################################################
# Check if ADB server is running by connecting to port
##############################################################################

sub IsADBServerRunning ($)
{
	my $hash = shift;
	
	return TCPConnect ($hash->{adb}{host}, $hash->{adb}{port}, 1);
}

##############################################################################
# Set commands
##############################################################################

sub Set ($@)
{
	my ($hash, $a, $h) = @_;
	
	my $name = shift @$a;
	my $opt = shift @$a // return 'No set command specified';

	# Preprare list of available commands
	my $options = 'command disconnectAll:noArg start:noArg stop:noArg';

	$opt = lc($opt);

	if ($opt eq 'start') {
		RemoveInternalTimer ($hash, 'AndroidDBHost::CheckADBServerTimer');
		CheckADBServer ($hash);
		return "Cannot start server" if ($hash->{STATE} eq 'stopped');
	}
	elsif ($opt eq 'stop') {
		my ($rc, $result, $error) = Execute ($hash, 'kill-server');
		return $error if ($rc == 0);
		sleep (2);
		if (!IsADBServerRunning ($hash)) {
			RemoveInternalTimer ($hash, 'AndroidDBHost::CheckADBServerTimer');
			readingsSingleUpdate ($hash, 'state', 'stopped', 1);
		}
		else {
			return "ADB server still running. Please try again.";
		}
	}
	elsif ($opt eq 'command') {
		my $command = shift @$a // return "Usage: set $name $opt Command [Args]";
		my ($rc, $result, $error) = Execute ($hash, $command, '.*', @$a);
		return $result.$error;
	}
	elsif ($opt eq 'disconnect') {
		my ($rc, $result, $error) = Execute ($hash, 'disconnect', 'disconnected');
		UpdateClientStates ($hash);
		return "Disconnecting all devices failed $result $error" if ($rc == 0);
	}
	else {
		return "Unknown argument $opt, choose one of $options";
	}
}

##############################################################################
# Get commands
##############################################################################

sub Get ($@)
{
	my ($hash, $a, $h) = @_;

	my $name = shift @$a;
	my $opt = shift @$a // return 'No get command specified';
	
	# Prepare list of available commands
	my $options = 'devices:noArg status:noArg';
	
	$opt = lc($opt);
	
	if ($opt eq 'status') {
		my $status = IsADBServerRunning ($hash) ? 'running' : 'stopped';
		readingsSingleUpdate ($hash, 'state', $status, 1);
		return "ADB server $status";
	}
	elsif ($opt eq 'devices') {
		my $device = GetDeviceList ($hash) // return 'Cannot read device list';
		my @clDevices = devspec2array ('TYPE=AndroidDB');
		my $list = '<html>List of devices:<br/><br/>';
		foreach my $d (keys %$device) {
			my @f = ();
			foreach my $cd (@clDevices) {
				if (exists($defs{$cd}) && $defs{$cd}{ADBDevice} eq $d) {
					push @f, $cd;
				}
			}
			$list .= sprintf ('%22s %20s %s<br/>', $d, join(',', @f), $device->{$d});
		}
		$list .= '</html>';
		return $list;
	}
	else {
		return "Unknown argument $opt, choose one of $options";
	}
}

##############################################################################
# Execute adb commmand and return status code and command output
#
# Return value:
#   (returncode, stdout, stderr)
# Return codes:
#   0 - error
#   1 - success
##############################################################################

sub Execute ($@)
{
	my ($ioHash, $command, $succExp, @args) = @_;
	$succExp //= '.*';
	
	if ($command ne 'start-server' && !IsADBServerRunning ($ioHash)) {
		Log3 $ioHash->{NAME}, 2, 'Execute: ADB server not running';
		return (0, '', 'ADB server not running');
	}

	# Execute ADB command	
	local (*CHILDIN, *CHILDOUT, *CHILDERR);
	my $pid = open3 (*CHILDIN, *CHILDOUT, *CHILDERR, $ioHash->{adb}{cmd}, $command, @args);
	close (CHILDIN);

	# Read output
	my $result = '';
	while (my $line = <CHILDOUT>) { $result .= $line; }
	my $error = '';
	while (my $line = <CHILDERR>) { $error .= $line; }

	close (CHILDOUT);
	close (CHILDERR);
	waitpid ($pid, 0);

	Log3 $ioHash->{NAME}, 5, "stdout=$result";
	Log3 $ioHash->{NAME}, 5, "stderr=$error";

	my $rc = 0;
	if ($error eq '') {
		if ($result !~ /$succExp/i) {
			$error = "Response doesn't match $succExp for command $command";
			$rc = 0;
		}
		else {
			$rc = 1;
			$ioHash->{ADBPID} = $pid if ($command eq 'start-server');
		}
	}

	return ($rc, $result, $error);
}

##############################################################################
# Check Android device connection(s)
#
# Return value:
#  -1 = Error
#   0 = No active connections
#   1 = Current device connected
#   2 = Other / multiple device(s) connected (need to disconnect)
##############################################################################

sub IsConnected ($)
{
	my $clHash = shift // return 0;

	my $ioHash = $clHash->{IODev} // return -1;
	
	# Get active connections
	my $device = GetDeviceList ($ioHash) // return -1;
	my $devCount = keys %$device;

	if ($devCount == 1) {
		return exists($device->{$clHash->{ADBDevice}}) ? 1 : 2;
	}
	elsif ($devCount > 1) {
		return 2;
	}

	return 0;
}

##############################################################################
# Connect to Android device
#
# Return value:
#  0 = error
#  1 = connected
##############################################################################

sub Connect ($)
{
	my $clHash = shift // return 0;

	my $ioHash = $clHash->{IODev} // return -1;
	
	my $connect = IsConnected ($clHash);
	if ($connect == 1) {
		return 1;
	}
	elsif ($connect == 2) {
		# Disconnect all devices
		my ($rc, $result, $error) = Execute ($ioHash, 'disconnect', 'disconnected');
		return -1 if ($rc == 0);
	}
	elsif ($connect == -1) {
		Log3 $clHash->{NAME}, 2, 'Cannot detect connection state';
		return 0;
	}

	# Connect
	my ($rc, $state, $error) = Execute ($ioHash, 'connect', 'connected', $clHash->{ADBDevice});
	readingsSingleUpdate ($clHash, 'state', 'connected', 1) if ($rc == 1);
	
	return $rc;
}

##############################################################################
# Connect to Android device
#
# Return value:
#  0 = error
#  1 = connected
##############################################################################

sub Disconnect ($)
{
	my $clHash = shift // return 0;
	
	my $ioHash = $clHash->{IODev} // return (-1, '', 'Cannot detect IO device');
	
	my ($rc, $result, $error) = Execute ($ioHash, 'disconnect', 'disconnected', $clHash->{ADBDevice});
	readingsSingleUpdate ($clHash, 'state', 'disconnected', 1) if ($rc == 1);

	return $rc;
}

##############################################################################
# Get list of devices
##############################################################################

sub GetDeviceList ($)
{
	my $hash = shift;

	my ($rc, $result, $error) = Execute ($hash, 'devices');
	return undef if ($rc == 0);	

	my %devState = ();
	my @devices = $result =~ /([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+\s+[a-zA-Z0-9]+)/g;
	foreach my $d (@devices) {
		my ($address, $state) = split /\s+/, $d;
		$devState{$address} = $state // 'disconnected';
	}

	return \%devState;
}

##############################################################################
# Execute commmand and return status code and command output
#
# Return value:
#   (returncode, stdout, stderr)
# Return codes:
#   0 - error
#   1 - success
##############################################################################

sub Run ($@)
{
	my ($clHash, $command, $succExp, @args) = @_;
	$succExp //= '.*';

	my $ioHash = $clHash->{IODev} // return (0, '', 'Cannot detect IO device');

	if (!Connect ($clHash)) {
		readingsSingleUpdate ($clHash, 'state', 'connected', 1);
		return (0, '', 'Cannot connect to device');
	}
	
	readingsSingleUpdate ($clHash, 'state', 'connected', 1);

	return Execute ($ioHash, $command, $succExp, @args);
}

######################################################################
# Check if TCP connection to specified host and port is possible
######################################################################

sub TCPConnect ($$$)
{
	my ($addr, $port, $timeout) = @_;
	
	my $socket = IO::Socket::INET->new (PeerAddr => $addr, PeerPort => $port, Timeout => $timeout);
	if ($socket) {
		close ($socket);
		return 1;
	}

	return 0;
}


1;

=pod
=item device
=item summary Provides I/O device for AndroidDB devices
=begin html

<a name="AndroidDBHost"></a>
<h3>AndroidDBHost</h3>
<ul>
   Provides I/O device for AndroidDB devices. 
	<br/><br/>
	Dependencies: Perl module IPC::Open3, Android Platform Tools
   <br/><br/>
   Android DB Platform Tools installation:<br/>
   <ul>
   <li>Debian/Raspbian: apt-get install android-sdk-platform-tools</li>
   <li>Windows/MacOSX/Linux x86: <a href="https://developer.android.com/studio/releases/platform-tools">Android Developer Portal</a></li>
   </ul>
   <br/>
   <a name="AndroidDBHostdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; AndroidDBHost [server=&lt;host&gt;}[:&lt;port&gt;]] [adb=&lt;path&gt;]</code><br/><br/>
		The parameter 'host' is the hostname of the system, where the ADB server is running. Default is 'localhost'.
		Parameter 'adb' can be used to specify the path to the adb command (must include 'adb' or 'adb.exe').<br/>
		<b>Note:</b> The adb command must be executable by the account under which FHEM is running.
   </ul>
   <br/>
</ul>

<a name="AndroidDBHostset"></a>
<b>Set</b><br/><br/>
<ul>
	<li><b>set &lt;name&gt; command &lt;Command&gt; [&lt;Args&gt;]</b><br/>
		Execute ADB command.
	</li><br/>
	<li><b>set &lt;name&gt; start</b><br/>
		Start ADB server.
	</li><br/>
	<li><b>set &lt;name&gt; stop</b><br/>
		Stop ADB server.
	</li><br/>
</ul>

<a name="AndroidDBHostget"></a>
<b>Get</b><br/><br/>
<ul>
	<li><b>get &lt;name&gt; status</b><br/>
		Get status of ADB server.
	</li><br/>
</ul>

=end html
=cut

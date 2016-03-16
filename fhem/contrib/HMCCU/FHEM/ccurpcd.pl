#!/usr/bin/perl

#########################################################
# ccurpcd.pl
#
# $Id:
#
# Version 2.0
#
# FHEM RPC server for Homematic CCU.
#
# (C) 2016 by zap
#--------------------------------------------------------
# Usage:
#
#   ccurpcd.pl Hostname Port QueueFile LogFile
#   ccurpcd.pl shutdown Hostname Port PID
#--------------------------------------------------------
# Queue file entries:
#
#   Code|Data[|...]
#
#   Initialized:    IN|INIT|0
#   New device:     ND|Address|Type
#   Updated device: UD|Address|Hint
#   Deleted device: DD|Address
#   Replace device: RD|Address1|Address2
#   Readd device:   RA|Address
#   Event:          EV|Address|Attribute|Value
#   Shutdown:       EX|SHUTDOWN|pid
#########################################################

use strict;
use warnings;
# use File::Queue;
use RPC::XML::Server;
use RPC::XML::Client;
use IO::Socket::INET;
use FindBin qw($Bin);
use lib "$Bin";
use RPCQueue;

# Global variables
my $client;
my $server;
my $queue;
my $logfile;
my $shutdown = 0;
my $eventcount = 0;

# Functions
sub CheckProcess ($$);
sub Log ($);
sub WriteQueue ($);
sub CCURPC_Shutdown ($$$);
sub CCURPC_Initialize ($$);


#####################################
# Get PID of running RPC server or 0
#####################################

sub CheckProcess ($$)
{
	my ($prcname, $port) = @_;

	my $filename = $prcname;
	my $pdump = `ps ax | grep $prcname | grep -v grep`;
	my @plist = split "\n", $pdump;
	foreach my $proc (@plist) {
		# Remove leading blanks, fix for MacOS. Thanks to mcdeck
		$proc =~ s/^\s+//;
		my @procattr = split /\s+/, $proc;
		if ($procattr[0] != $$ && $procattr[4] =~ /perl$/ &&
		    ($procattr[5] eq $prcname || $procattr[5] =~ /\/ccurpcd\.pl$/) &&
		    $procattr[7] eq "$port") {
			Log "Process $proc is running connected to CCU port $port";
			return $procattr[0];
		}
	}

	return 0;
}

#####################################
# Write logfile entry
#####################################

sub Log ($)
{
	my @messages = @_;
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime ();

	if (open (LOGFILE, '>>', $logfile)) {
		printf LOGFILE "%02d.%02d.%04d %02d:%02d:%02d ",
		   $mday,$mon+1,$year+1900,$hour,$min,$sec;
		foreach my $token (@messages) {
			print LOGFILE $token;
		}
		print LOGFILE "\n";
		close LOGFILE;
	}
}

#####################################
# Write queue entry
#####################################

sub WriteQueue ($)
{
	my ($message) = @_;

	$queue->enq ($message);

	return 1;
}

#####################################
# Shutdown RPC connection
#####################################

sub CCURPC_Shutdown ($$$)
{
	my ($serveraddr, $serverport, $pid) = @_;

	# Detect local IP
	my $socket = IO::Socket::INET->new (PeerAddr => $serveraddr, PeerPort => $serverport);
	if (!$socket) {
		print "Can't connect to CCU port $serverport";
		return undef;
	}
	my $localaddr = $socket->sockhost ();
	close ($socket);

	my $ccurpcport = 5400+$serverport;
	my $callbackurl = "http://".$localaddr.":".$ccurpcport."/fh".$serverport;
	
	$client = RPC::XML::Client->new ("http://$serveraddr:$serverport/");

	print "Trying to deregister RPC server $callbackurl\n";
	$client->send_request("init", $callbackurl);
	sleep (3);
	
	print "Sending SIGINT to PID $pid\n";
	kill ('INT', $pid);

	return undef;
}

#####################################
# Initialize RPC connection
#####################################

sub CCURPC_Initialize ($$)
{
	my ($serveraddr, $serverport) = @_;
	my $callbackport = 5400+$serverport;
	
	# Create RPC server
	$server = RPC::XML::Server->new (port=>$callbackport);
	if (!ref($server))
	{
		Log "Can't create RPC callback server on port $callbackport. Port in use?";
		return undef;
	}
	else {
		Log "Callback server created listening on port $callbackport";
	}
	
	# Callback for events
	Log "Adding callback for events";
	$server->add_method (
	   { name=>"event",
	     signature=> ["string string string string int","string string string string double","string string string string boolean","string string string string i4"],
	     code=>\&CCURPC_EventCB
	   }
	);

	# Callback for new devices
	Log "Adding callback for new devices";
	$server->add_method (
	   { name=>"newDevices",
	     signature=>["string string array"],
             code=>\&CCURPC_NewDevicesCB
	   }
	);

	# Callback for deleted devices
	Log "Adding callback for deleted devices";
	$server->add_method (
	   { name=>"deleteDevices",
	     signature=>["string string array"],
             code=>\&CCURPC_DeleteDevicesCB
	   }
	);

	# Callback for modified devices
	Log "Adding callback for modified devices";
	$server->add_method (
	   { name=>"updateDevice",
	     signature=>["string string string int"],
	     code=>\&CCURPC_UpdateDeviceCB
	   }
	);

	# Callback for replaced devices
	Log "Adding callback for replaced devices";
	$server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string string string"],
	     code=>\&CCURPC_ReplaceDeviceCB
	   }
	);

	# Callback for readded devices
	Log "Adding callback for readded devices";
	$server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string array"],
	     code=>\&CCURPC_ReaddDeviceCB
	   }
	);
	
	# Dummy implementation, always return an empty array
	$server->add_method (
	   { name=>"listDevices",
	     signature=>["array string"],
	     code=>\&CCURPC_ListDevicesCB
	   }
	);

	return "OK";
}

#####################################
# Callback for new devices
#####################################

sub CCURPC_NewDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	
	Log "NewDevice: received ".scalar(@$a)." device specifications";
	
	for my $dev (@$a) {
		WriteQueue ("ND|".$dev->{ADDRESS}."|".$dev->{TYPE});
	}

#	return RPC::XML::array->new();
	return;
}

#####################################
# Callback for deleted devices
#####################################

sub CCURPC_DeleteDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;

	Log "DeleteDevice: received ".scalar(@$a)." device addresses";

	for my $dev (@$a) {
		WriteQueue ("DD|".$dev);
	}

	return;
}

#####################################
# Callback for modified devices
#####################################

sub CCURPC_UpdateDeviceCB ($$$$)
{
	my ($server, $cb, $devid, $hint) = @_;

	WriteQueue ("UD|".$devid."|".$hint);

	return;
}

#####################################
# Callback for replaced devices
#####################################

sub CCURPC_ReplaceDeviceCB ($$$$)
{
	my ($server, $cb, $devid1, $devid2) = @_;

	WriteQueue ("RD|".$devid1."|".$devid2);

	return;
}

#####################################
# Callback for readded devices
#####################################

sub CCURPC_ReaddDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;

	Log "ReaddDevice: received ".scalar(@$a)." device addresses";

	for my $dev (@$a) {
		WriteQueue ("RA|".$dev);
	}

	return;
}

#####################################
# Callback for handling CCU events
#####################################

sub CCURPC_EventCB ($$$$$)
{
	my ($server,$cb,$devid,$attr,$val)=@_;
	
	WriteQueue ("EV|".$devid."|".$attr."|".$val);

	$eventcount++;
	if ($eventcount == 250) {
		Log "Received $eventcount events from CCU since last check";
		$eventcount++;
	}

	# Never remove this statement!
	return;
}

#####################################
# Callback for list devices
#####################################

sub CCURPC_ListDevicesCB ()
{
	Log "ListDevices";
	
	WriteQueue ("IN|INIT|1");

	return RPC::XML::array->new();
}

#####################################
# MAIN 
#####################################

my $name = $0;

# Process command line arguments
if ($#ARGV+1 != 4) {
	print "Usage: $name CCU-Host Port QueueFile LogFile\n";
	print "       $name shutdown CCU-Host Port PID\n";
	exit 1;
}

#
# Manually shutdown RPC server
#
if ($ARGV[0] eq 'shutdown') {
	CCURPC_Shutdown ($ARGV[1], $ARGV[2], $ARGV[3]);
	exit 0;
}

#
# Start RPC server
#
my $ccuhost = $ARGV[0];
my $ccuport = $ARGV[1];
my $queuefile = $ARGV[2];
$logfile = $ARGV[3];

my $pid = CheckProcess ($name, $ccuport);
if ($pid > 0) {
	Log "Error: ccurpcd.pl is already running (PID=$pid) for CCU port $ccuport";
	die "Error: ccurpcd.pl is already running (PID=$pid) for CCU port $ccuport\n";
}

# Create or open queue
Log "Creating file queue";
$queue = new RPCQueue (File => $queuefile, Mode => 0666);
if (!defined ($queue)) {
	Log "Error: Can't create queue";
	die "Error: Can't create queue\n";
}
else {
	$queue->reset ();
	while ($queue->deq ()) { }
}

# Initialize RPC server
Log "Initializing RPC server";
my $callbackurl = CCURPC_Initialize ($ccuhost, $ccuport);
if (!defined ($callbackurl)) {
	Log "Error: Can't initialize RPC server";
	die "Error: Can't initialize RPC server\n";
}

# Server loop is interruptable bei signal SIGINT
Log "Entering server loop. Use kill -SIGINT $$ to terminate program";
$server->server_loop;

WriteQueue ("EX|SHUTDOWN|$$");
Log "RPC server terminated";


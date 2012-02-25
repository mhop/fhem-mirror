################################################################
# fhem-module for NetIO 230B Power Distribution Unit
#
# http://www.koukaam.se/showproduct.php?article_id=1502
#
# Usage:
# There are 2 modes:
#
# (1) - define the IP, user and password directly in fhem's fhem.cfg (or UI).
#
#		define NetIO1 <IP address> <socket number> [<user> <password>];
#		e.g. define NetIO1 192.168.178.2 1 admin admin;
#
#		if you omit the user credentials, the module will look for a configuration file,
#		if no configuration file is found, it tries with 'admin', 'admin'
#
#
# (2) - define your credentials using a config file.
#
#		define NetIO1 <IP address> <socket number> [<path_to_configuration_file>];
#		define NetIO1 192.168.178.2 1 /var/log/fhem/netio.conf);
#
#		if you omit the configuration parameter, the module will look for a configuration
#		file at: /var/log/fhem/netio.conf
#
#  NetIO230B Configuration file format:
#
#		%config= (
#			host => "192.168.xx.xx",
#			user => "anyusername_without_spaces",
#			password => "anypassword_without_spaces"
#		);
#
################################################################
# created 2012 by Andy Fuchs
#---------
# Changes:
#---------
# 2012-02-03	0.1		initial realease
# 2012-02-25	0.2		removed dependencies for LWP::UserAgent and HTTP::Request;

################################################################
package main;

use strict;
use warnings;
use Data::Dumper;
use IO::Socket;

use constant PARAM_NAME 	=> 1;
use constant PARAM_HOST 	=> 2;
use constant PARAM_SOCK		=> 3;
use constant PARAM_USER		=> 4;
use constant PARAM_PASS		=> 5;
use constant PARAM_FILE		=> 4;

use constant DEBUG			=> 1;

sub
NetIO230B_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "NetIO230B_Set";
  $hash->{GetFn}     = "NetIO230B_Get";
  $hash->{DefFn}     = "NetIO230B_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";

}

###################################
sub
NetIO230B_Set($@)
{
	my ($hash, @a) = @_;

	return "no set value specified" if(int(@a) != 2);
	return "Unknown argument $a[1], choose one of on off " if($a[1] eq "?");

	my $state = $a[1]; #initialize state to the passed parameter
	my $result = "command was not executed - $state is not 'on' or 'off'";
	if ($state eq "on" || $state eq "off")
	{
		$hash->{STATE} = $state;
		$state = int($state eq "on");
		#prepare the sockets default parameters; 'u' means: don't touch
		my @values=("u","u","u","u");
		my @sockets = @{$hash->{SOCKETS}};

		foreach (@sockets) {
			$values[$_-1] = $state;
			$hash->{READINGS}{"socket$_"}{TIME} = TimeNow();
			$hash->{READINGS}{"socket$_"}{VAL} = $state;
		}

		$result = NetIO230B_Request($hash, "set", join("",@values));
	}

	Log 3, "NetIO230B set @a => $result";

	return undef;
}

###################################
sub
NetIO230B_Get($@)
{
	my ($hash, @a) = @_;
	my $result = NetIO230B_Request($hash, "get");
	Log 3, "NetIO230B get @a => $result";

	return $hash->{STATE};
}

###################################
sub
NetIO230B_Request($@)
{
	my ($hash, $cmd, $list) = @_;
	my $URL='';
	my $log='';

	my $response = GetHttpFile($hash->{HOST}.":80","/tgi/control.tgi?l=p:". $hash->{USER}.":".$hash->{PASS}."&p=l");
	if(!$response or length($response)==0)
	{
		Log 3, "NetIO230B_Request failed: ".$log;
		return("");
  	}

	# strip html tags
	$response =~ s/<(?:[^>'"]*|(['"]).*?\1)*>//gs;

	# strip leading whitespace
	$response =~ s/^\s+//;

	#strip trailing whitespace
	$response =~ s/\s+$//;

	return $response if ($cmd eq "set");

	#+++todo
	#555 FORBIDDEN

	#split the result into an array
	my @values=split(/ */,$response);

	#save the values to the readings hash
	my $state = "???";
	my @sockets = @{$hash->{SOCKETS}};
	foreach (@sockets) {
		$hash->{READINGS}{"socket$_"}{TIME} = TimeNow();
		$hash->{READINGS}{"socket$_"}{VAL} = $values[$_-1];
		if ($state == "???") { #initialize state
			$state = $values[$_-1];
		} else {
			$state = "???" if ($values[$_-1] != $state);  #if states are mixed show ???
		}
	}

	$hash->{STATE} = $state;

	# debug output
	#my %k = %{$hash->{READINGS}};
	#foreach my $r (sort keys %k) {
	#	Log 1,  "$r  S: $k{$r}{VAL}  T: $k{$r}{TIME}";
	#}

    return $response;
}

### _Define routing is called when fhem starts -> 'reloading' of the module does not call the define routine!!
###
sub
NetIO230B_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $paramCount = int(@a);

	Log 3, "Wrong syntax: use 'define <name> NetIO230B <ip-address> [<socket_number> <username> <password>]' or 'define <name> NetIO230B <ip-address> [<socket_number> <configfilename>]'" if(int(@a) < 4);  #5 = mit user/pass #4 = mit config

	#provide some default settings
	$hash->{CONFIGFILEPATH} = "/var/log/fhem/netio.conf"; #default file path is /var/log/fhem/netio.conf
	$hash->{USER} = "admin";
	$hash->{PASS} = "admin";
	@{$hash->{SOCKETS}} = (1,2,3,4); #default to all sockets

	#mandatory parameter: 'HOST'
	$hash->{HOST}   = $a[PARAM_HOST]; #can be overridden, if using a config file

	#mandatory parameter: 'SOCKET #'; negative numbers are ignored
	my $buf = $a[PARAM_SOCK];
	if (($buf =~ m/^\d+$/) && ($buf >=0)) {  #make sure input value is a positive number

		if ($buf == 0) #input socket '0' is used as 'all'
		{
				@{$hash->{SOCKETS}} = (1,2,3,4);  #use this number as 'array of socket-numbers' to operate on

		} elsif ($buf <= 4)  #input socket is a single number <=4
		{
			@{$hash->{SOCKETS}} = ($buf);  #use this number as 'array of socket-numbers' to operate on

		} else {

			@{$hash->{SOCKETS}} = split("",$buf);  #convert the input values to an array of sockets to operate on
		}
	}

	#optional parameter: 'CONFIGFILE_NAME_or_PATH'
	if ($paramCount == 5) #seems a config file is passed
	{
		$hash->{CONFIGFILEPATH} = $a[PARAM_FILE] if defined($a[PARAM_FILE]);;
	}

	#optional parameters: 'USER  and PASS'
	if ($paramCount != 6)
	{
		my %config = NetIO230B_GetConfiguration($hash);
		if (%config) {
			$hash->{HOST} = $config{host} 	  if (defined($config{host}));
			$hash->{USER} = $config{user} 	  if (defined($config{user}));
			$hash->{PASS} = $config{password} if (defined($config{password}));
		} else {

			Log 3, "NetIO230B: Configuration could not be read. Trying default values...\n";
		}

	} else {
		#in any other case
		$hash->{USER} = $a[PARAM_USER] if defined($a[PARAM_USER]);
		$hash->{PASS} = $a[PARAM_PASS] if defined($a[PARAM_PASS]);
	}

	Log 3, "NetIO230B: device opened at host: $hash->{HOST} => @a\n";

	return undef;
}
##########################################
#
#  NetIO230B Configuration-Format:
#
#		%config= (
#			host => "192.168.xx.xx",
#			user => "anyusername_without_spaces",
#			password => "anypassword_without_spaces"
#		);
#
#
##########################################

### _GetConfiguration reads a plain text file containing arbitrary information
sub
NetIO230B_GetConfiguration($)
{
	my ($hash)= @_;
	my $configfilename = $hash->{CONFIGFILEPATH};

	if(!open(CONFIGFILE, $configfilename))
	{
		Log 3, "NetIO230B: Cannot open settings file '$configfilename'.";
		return ();
	 }
	my @configfile=<CONFIGFILE>;
	close(CONFIGFILE);

	my %config;
	eval join("", @configfile);

	return %config;
}

1;

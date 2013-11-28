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
#		define NetIO1 <IP address:port number> <socket number> [<user> <password>];
#		e.g. define NetIO1 192.168.178.2:80 1 admin admin;
#
#		if you omit the user credentials, the module will look for a configuration file,
#		if no configuration file is found, it tries with 'admin', 'admin'
#
#
# (2) - define your credentials using a config file.
#
#		define NetIO1 <IP address:port number> <socket number> [<path_to_configuration_file>];
#		define NetIO1 192.168.178.2:80 1 /var/log/fhem/netio.conf);
#
#		if you omit the configuration parameter, the module will look for a configuration
#		file at: /var/log/fhem/netio.conf
#
#  NetIO230B Configuration file format:
#
#		%config= (
#			host => "192.168.xx.xx:80",
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
# 2012-09-15	0.3		fixed missing param-list;
#						added slight checking of passed device-address (now explicitely requires setting a port)

################################################################
package main;

use strict;
use warnings;
use Data::Dumper;
use IO::Socket;
use HttpUtils;

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
	my $parm='l';
	if($cmd eq "set") {
	  $parm = $list;
	}

	my $response = GetFileFromURL("http://"."$hash->{HOST}/tgi/control.tgi?l=p:". $hash->{USER}.":".$hash->{PASS}."&p=".$parm);
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

	Log 3, "Wrong syntax: use 'define <name> NetIO230B <ip-address>:<portnumber> [<socket_number> <username> <password>]' or 'define <name> NetIO230B <ip-address>:<portnumber> [<socket_number> <configfilename>]'" if(int(@a) < 4);  #5 = mit user/pass #4 = mit config

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
	
	Log 1,"NetIO230B: Invalid device-address! Please use an address in the format: <ip-address>:<portnumber>" unless ($hash->{HOST} =~ m/^(.+):([0-9]+)$/);

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

=pod
=begin html

<a name="NetIO230B"></a>
<h3>NetIO230B</h3>
<ul>
  <p>
  fhem-module for NetIO 230B Power Distribution Unit &nbsp;&nbsp; (see: <a
  href="http://www.koukaam.se/showproduct.php?article_id=1502">NetIO 230B
  (koukaam.se)</a>)
  </p>
  Note: this module needs the HTTP::Request and LWP::UserAgent perl modules.
  <br />
  Please also note: the PDU must use firmware 3.1 or later and set to unencrypted mode.
  <br /><br />
  <a name="NETIO230Bdefine"></a>
  <b>Define</b>
  <ul>

    <li><code>define &lt;name&gt; NetIO230B &lt;ip-address&gt; &lt;socket number(s)
    &gt; [&lt;user name&gt; &lt;password&gt;]</code></li>

    <li><code>define &lt;name&gt; NetIO230B &lt;ip-address&gt; &lt;socket number(s)
    &gt; [&lt;config file path&gt;]</code></li>

    <p>
	    Defines a switching device, where sockets can be switched
    </p>
    <ul>
    	<li>separately 	(just use 0-4 as socket number)</li>
		<li>all together  (use 1234 as socket number)</li>
                <li>in arbitrary groups (e.g 13 switches socket 1 and 3, 42
                switches socket 2 and 4, etc...), invalid numbers are
                ignored</li>
	</ul>
	<p>
                User name and password are optional. When no user name or
                password is passed, the module looks for a configfile at
                '/var/log/fhem/netio.conf'.  If no config file is found, it
                uses 'admin/admin' as user/pass, since this is the default
                configuration for the device.
        <p>
                Alternatively you can pass a path to a configfile instead of
                the user/pass combo. (e.g. /var/tmp/tmp.conf)
                Configfile-Format:<br />
		<ul>
			<code>
			%config= (<br />
					&nbsp;&nbsp;&nbsp;host => "192.168.61.40",<br />
					&nbsp;&nbsp;&nbsp;user => "admin",<br />
					&nbsp;&nbsp;&nbsp;password => "admin"<br />
			);</code>
			<br /><br /><small>(All settings optional)</small>
		</ul>
    </p>
    <p>Examples:</p>
    <ul>
    	<li><code>define Socket3 NetIO230B 192.168.178.10 3</code></li>
    	<li><code>define Socket1_and_4 NetIO230B 192.168.178.10 14</code></li>
    	<li><code>define coffeemaker NetIO230B 192.168.178.10 1 username secretpassword</code></li>
    	<li><code>define coffeemaker_and_light NetIO230B 192.168.178.10 23 /var/log/kitchen.conf</code></li>
    </ul>
  </ul>
  <br>

  <a name="NETIO230Bget"></a>
  <b>Get </b>
 	 <ul>
		<code>get &lt;name&gt; state</code>
		<br><br>
		returns the state of the socket(s)<br>

		Example:
		<ul>
		  <code>get coffeemaker_and_light</code>&nbsp;&nbsp; => <code>on or off</code><br>
		</ul>
		<br>
	  </ul>

	  <a name="NETIO230Bset"></a>
  <b>Set </b>
 	 <ul>
		<code>set &lt;name&gt; &lt;value&gt;</code>
		<br><br>
		where <code>value</code> is one of:<br>
		<pre>
		on
		off
		</pre>
		Examples:
		<ul>
		  <code>set coffeemaker_and_light on</code><br>
		</ul>
		<br>
	  </ul>
  </ul>


=end html
=cut

################################################################################
#
# 72_UBUS_CLIENT.pm
#
# Connects as a client to a server implementing the uBus command line / JSON-RPC interface.
#
# $Id$
#
################################################################################

package FHEM::UBUS_CLIENT; ## no critic "Package declaration"

use strict;
use warnings;

use Exporter qw(import);
use Carp qw(carp);
use DevIo;
use HttpUtils;
use FHEM::Core::Authentication::Passwords qw(:ALL);
use JSON qw(encode_json decode_json);
use GPUtils qw(GP_Import);

BEGIN {
	GP_Import (
		qw(
			DevIo_OpenDev
			DevIo_SimpleWrite
			DevIo_SimpleRead
			DevIo_CloseDev
			DevIo_IsOpen
			HttpUtils_NonblockingGet
			Log3
			Debug
			IsDisabled
			Dispatch
			InternalTimer
			RemoveInternalTimer
			AttrVal
			ReadingsVal
			ReadingsNum
			ReadingsAge
			readingsSingleUpdate
			readingsBeginUpdate
			readingsBulkUpdate
			readingsEndUpdate
			readingsDelete
			makeReadingName
			deviceEvents
			gettimeofday
		)
	)
};

sub ::UBUS_CLIENT_Initialize { goto &Initialize };

sub Initialize
{
	my $hash = shift // return;

	$hash->{DefFn}    = \&Define;
	$hash->{UndefFn}  = \&Undef;
	$hash->{SetFn}    = \&Set;
	$hash->{AttrFn}   = \&Attr;
	$hash->{ReadFn}   = \&Read;
	$hash->{ReadyFn}  = \&Ready;
	$hash->{WriteFn}  = \&Write;
	$hash->{RenameFn} = \&Rename;

	$hash->{AttrList}  = 'disable:1,0 disabledForIntervals timeout refresh username ' . $main::readingFnAttributes;
	$hash->{Clients}   = 'UBUS_CALL';
	$hash->{MatchList} = {'1:UBUS_CALL' => '^.'};

	$hash->{parseParams} = 1;
	return;
}

sub Define
{
	my $hash = shift;
	my $apar = shift;
	my $hpar = shift;

	my $name = shift @{$apar};
	my $type = shift @{$apar};
	my $dev = shift @{$apar} // 'ubus';

	$hash->{helper}->{passObj} = FHEM::Core::Authentication::Passwords->new($hash->{TYPE});
	$hash->{helper}->{updateFunc} = sub {my $item = shift // return; GetUpdate($hash, $item); return;};

	Disconnect($hash);

	if($dev =~ m,^(ws|wss)://([^/:]+)(:[0-9]+)?(.*?)$,)
	{
		my ($proto, $host, $port, $path) = ($1, $2, $3 ? $3 : ':' . ($1 eq 'wss' ? '443' : '80'), $4);
		$hash->{method} = 'websocket';
		$hash->{DeviceName} = "$proto:$host$port$path";
		%{$hash->{header}} = ('Sec-WebSocket-Protocol' => 'ubus-json');
	}
	elsif($dev =~ m,^(http|https)://([^/:]+)(:[0-9]+)?(.*?)$,)
	{
		$hash->{method} = 'http';
		$hash->{url} = $dev;
	}
	elsif($dev eq 'ubus')
	{
		$hash->{method} = 'shell';
		$hash->{cmd} = 'ubus';
	}
	else
	{
		return "invalid device specifier $dev";
	}

	readingsSingleUpdate($hash, 'state', 'initialized', 1);

	return $main::init_done ? Connect($hash) : InternalTimer(gettimeofday() + 1, \&Connect, $hash);
}

sub Undef
{
	my $hash = shift // return;

	Disconnect($hash);

	return;
}

sub Rename
{
	my $name_new = shift // return;
	my $name_old = shift // return;

	my $passObj = $main::defs{$name_new}->{helper}->{passObj};

	my $password = $passObj->getReadPassword($name_old) // return;

	$passObj->setStorePassword($name_new, $password);
	$passObj->deletePassword($name_old);

	return;
}

sub Ready
{
	my $hash = shift // return;
	my $name = $hash->{NAME};

	return if DevIo_IsOpen($hash) || $hash->{method} ne 'websocket' || IsDisabled($name);

	#Log3($name, 5, "UBUS ($name) - reconnect");

	return DevIo_OpenDev($hash, 1, \&Init, \&Callback);
}

sub Read
{
	my $hash = shift // return;
	my $name = $hash->{NAME};

	my $buf = DevIo_SimpleRead($hash) // return;

	my @items = $buf =~ /( \{ (?: [^{}]* | (?0) )* \} )/xg;

	for my $item (@items)
	{
		Log3($name, 5, "UBUS ($name) - received: $item");
		Decode($hash, $item);
	}

	return;
}

sub Response
{
	my $param = shift // return;
	my $error = shift // q{};
	my $data = shift // q{};

	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	if($error ne q{})
	{
		Log3($name, 1, "UBUS ($name) - error performing request: $error");
	}
	elsif($data ne q{})
	{
		Log3($name, 5, "UBUS ($name) - received: $data");
		Decode($hash, $data);
	}

	return;
}

sub Set
{
	my $hash = shift;
	my $apar = shift;
	my $hpar = shift;

	my $name = shift @{$apar} // return;
	my $cmd = shift @{$apar} // return qq{"set $name" needs at least one argument};

	if($cmd eq 'password')
	{
		my $password = $apar->[0];

		my ($res, $error) = defined $password ? $hash->{helper}->{passObj}->setStorePassword($name, $password) : $hash->{helper}->{passObj}->deletePassword($name);

		if(defined $error && !defined $res)
		{
			Log3($name, 1, "UBUS ($name) - could not update password");
			return "Error while updating the password - $error";
		}

		Disconnect($hash);
		Connect($hash);

		return;
	}

	if($cmd eq 'disable')
	{
		Disconnect($hash);
		readingsSingleUpdate($hash, 'state', 'inactive', 1);

		return;
	}

	if($cmd eq 'enable')
	{
		readingsSingleUpdate($hash, 'state', 'active', 1);
		Connect($hash);

		return;
	}

	return "Unknown argument $cmd, choose one of disable:noArg enable:noArg password";
}

sub Attr
{
	my $cmd = shift // return;
	my $name = shift // return;
	my $attr = shift // return;
	my $value = shift // return;

	if($cmd eq 'set')
	{
		if($attr eq 'timeout' || $attr eq 'refresh')
		{
			return "$attr must be non-negative." if $value < 0;
		}
	}

	return;
}

sub Init
{
	my $hash = shift // return;

	Login($hash);

	return;
}

sub Callback
{
	my $hash = shift // return;
	my $error = shift // q{};
	my $name = $hash->{NAME};

	Log3($name, 1, "UBUS ($name) - error while connecting: $error") if $error;

	return;
}

sub Connect
{
	my $hash = shift // return;
	my $name = $hash->{NAME};

	return if IsDisabled($name);

	if($hash->{method} eq 'websocket')
	{
		Log3($name, 5, "UBUS ($name) - connect");

		return DevIo_OpenDev($hash, 0, \&Init, \&Callback) if !DevIo_IsOpen($hash);
		return;
	}

	readingsSingleUpdate($hash, 'state', 'active', 1);


	if($hash->{method} eq 'http')
	{
		Login($hash);
	}
	else
	{
		UpdatesStart($hash);
	}

	return;
}

sub Disconnect
{
	my $hash = shift // return;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash, \&CheckSession);

	return if !defined $hash->{method};

	delete $hash->{session};
	delete $hash->{lastid};

	if($hash->{method} eq 'websocket')
	{
		Log3($name, 5, "UBUS ($name) - disconnect");

		return DevIo_CloseDev($hash) if DevIo_IsOpen($hash);
		return;
	}

	readingsSingleUpdate($hash, 'state', 'stopped', 1);

	return;
}

sub Write
{
	my $hash = shift // return; # Physical device hash
	my $name = $hash->{NAME};

	return if IsDisabled($name);

	my $dev = shift // return; # Logical device name
	my $method = shift // q{}; # Mehod (list, call, subscribe...)
	my $id = "$dev:$method:" . (++$hash->{lastid});
	my $rpcparam;

	if($method ne 'cmd' && $dev ne $name) # Catch calls while not logged in.
	{
		return if !defined $hash->{session};
		return if $hash->{session} eq '00000000000000000000000000000000';
	}

	if($method eq 'call')
	{
		my $module = shift // q{};
		my $function = shift // q{};
		my $param = shift // {};

		if($hash->{method} eq 'cmd')
		{
			my $json;
			eval { $json = encode_json($param); };

			if($@)
			{
				Log3($name, 1, "UBUS ($name) - encode_json error: $@");
				return;
			}

			my $ret = qx{ubus call $module $function '$json'};

			InternalTimer(gettimeofday() + 1, sub () { Dispatch($hash, qq/{"jsonrpc":"2.0","id":"$id","result":[0,$ret]}/); }, $hash);
		}

		$rpcparam = [
			$hash->{session},
			$module,
			$function,
			$param
		];
	}
	elsif($method eq 'list')
	{
		my $pattern = shift // '*';

		if($hash->{method} eq 'cmd')
		{
			Log3($name, 1, "UBUS ($name) - list not implemented for command line mode");
			return;
		}

		$rpcparam = [
			$hash->{session},
			$pattern
		];
	}
	elsif($method eq 'subscribe')
	{
		if($hash->{method} eq 'cmd')
		{
			Log3($name, 1, "UBUS ($name) - subscribe not implemented for command line mode");
			return;
		}

		my $channel = shift // return;
		$rpcparam = [
			$hash->{session},
			$channel
		];
	}
	else
	{
		Log3($name, 1, "UBUS ($name) - unknown method $method in Write");
		return;
	}

	my $request = {
		'jsonrpc' => '2.0',
		'method' => $method,
		'params' => $rpcparam,
		'id' => $id
	};

	my $json;
	eval { $json = encode_json($request); };

	if($@)
	{
		Log3($name, 1, "UBUS ($name) - encode_json error: $@");
		return;
	}

	Log3($name, 5, "UBUS ($name) - sent: $json");

	$hash->{rpc}{$id} = $request;

	if($hash->{method} eq 'websocket')
	{
		DevIo_SimpleWrite($hash, $json, 2);
	}
	else
	{
		my $http = {
			'url' => $hash->{url},
			'method' => 'POST',
			'data' => $json,
			'timeout' => 5,
			'hash' => $hash,
			'callback' => \&Response
		};

		HttpUtils_NonblockingGet($http);
	}

	return $id;
}

sub Login
{
	my $hash = shift // return;
	my $name = $hash->{NAME};

	my $password = $hash->{helper}->{passObj}->getReadPassword($name) // q{};

	my $param = {
		'username' => AttrVal($name, 'username', 'user'),
		'password' => $password,
		'timeout' => AttrVal($name, 'timeout', 300)
	};

	$hash->{session} = '00000000000000000000000000000000';
	$hash->{lastid} = -1;

	Log3($name, 5, "UBUS ($name) - login of user " . $param->{username});

	Write($hash, $hash->{NAME}, 'call', 'session', 'login', $param);

	return;
}

sub CheckSession
{
	my $hash = shift // return;
	Write($hash, $hash->{NAME}, 'call', 'session', 'list');
}

sub Decode
{
	my $hash = shift // return;
	my $buf = shift // return;
	my $name = $hash->{NAME};

	$buf =~ s/{"unknown"}/{}/g;

	my $data;
	eval { $data = decode_json($buf); };

	if($@)
	{
		Log3($name, 1, "UBUS ($name) - decode_json error: $@");
		return;
	}

	if(!defined $data->{id}) # Missing ID - response to some subscription? Dispatch it.
	{
		Dispatch($hash, $buf);
		return;
	}

	my $id = $data->{id};

	if($id !~ m/^$name:([a-z]*):([0-9]*)$/) # Was this call made by someone else?
	{
		Dispatch($hash, $buf);
		return;
	}

	# We made the call (login, session etc.) - handle it.

	my $method = $1;

	my $error = 0;
	my $result = $data->{result};

	if(ref $result eq 'ARRAY')
	{
		$error = $result->[0];
		$result = $result->[1];
	}

	if($method eq 'call')
	{
		my $session = $hash->{rpc}{$id}{params}[0];
		my $module = $hash->{rpc}{$id}{params}[1];
		my $function = $hash->{rpc}{$id}{params}[2];
		my $param = $hash->{rpc}{$id}{params}[3];

		if($error == 0)
		{
			if($module eq 'session')
			{
				if($function eq 'login') # Successfully logged in.
				{
					$hash->{session} = $result->{ubus_rpc_session};
					Write($hash, $hash->{NAME}, 'list', '*');
				}
				elsif($function eq 'list')
				{
					if(!defined $result->{ubus_rpc_session})
					{
						Log3($name, 3, "UBUS ($name) - no session data, consider setting attr refresh to 0");
					}
					elsif($hash->{session} ne $result->{ubus_rpc_session})
					{
						Log3($name, 3, "UBUS ($name) - unexpected session " . $result->{ubus_rpc_session} . " instead of expected " . $hash->{session});
						$hash->{session} = $result->{ubus_rpc_session};
					}
				}
				if(AttrVal($name, 'refresh', 180))
				{
					InternalTimer(gettimeofday() + AttrVal($name, 'refresh', 180), \&CheckSession, $hash);
				}
			}
		}
		elsif($error == 6)
		{
			if($module eq 'session' && $function eq 'login') # Login failed. Log and disconnect.
			{
				Log3($name, 1, "UBUS ($name) - login error");
				Disconnect($hash);
			}
			else # Other authentication problem - try login again.
			{
				Login($hash);
			}
		}
	}
	elsif($method eq 'list')
	{
		if($error == 0)
		{
			my $m = 0;
			readingsBeginUpdate($hash);
			for my $module (sort keys %{$result})
			{
				my $f = 0;
				readingsBulkUpdate($hash, makeReadingName("mod_${m}_name"), $module);
				for my $function (sort keys %{$result->{$module}})
				{
					my $p = 0;
					readingsBulkUpdate($hash, makeReadingName("mod_${m}_func_${f}_name"), $function);
					for my $param (sort keys %{$result->{$module}->{$function}})
					{
						readingsBulkUpdate($hash, makeReadingName("mod_${m}_func_${f}_param_${p}_name"), $param);
						readingsBulkUpdate($hash, makeReadingName("mod_${m}_func_${f}_param_${p}_type"), $result->{$module}->{$function}->{$param});
					}
					$f++;
				}
				$m++;
			}
			readingsEndUpdate($hash, 1);
		}
		elsif($error == 6)
		{
			Log3($name, 1, "UBUS ($name) - list resulted in authentication failure");
		}
	}

	delete $hash->{rpc}{$id};
	return;
}

1;

__END__

=pod

=item device
=item summary Provides access to the uBus JSON-RPC interface.
=item summary_DE Erlaubt den Zugriff auf die uBus JSON-RPC Schnittstelle.

=begin html

<a id="UBUS_CLIENT"></a>
<h3>UBUS_CLIENT</h3>

<ul>
<p>The <a href="http://openwrt.org/docs/guide-developer/ubus">uBus IPC/RPC system</a> is a common interconnect system used by OpenWrt. Services can connect to the bus and provide methods that can be called by other services or clients or deliver events to subscribers. This module provides different methods to connect to an uBus interface, either using its command line interface or remotely via websocket or HTTP.</p>

<a id="UBUS_CLIENT-define"></a>
<h4>Define</h4>

<pre>define &lt;name&gt; UBUS_CLIENT &lt;method&gt;</pre>
<p>The following connection methods for <code>&lt;method&gt;</code> are supported:</p>
<ul>
<li>For a <b>websocket</b> connection, a url of the form <code>(ws|wss)://&lt;host&gt;[:port][/path]</code> is used. Example:
<pre>define &lt;name&gt; UBUS_CLIENT ws://192.168.1.1</pre></li>
<li>For a <b>HTTP</b> connection, a url of the form <code>(http|https)://&lt;host&gt;[:port][/path]</code> is used. Example:
<pre>define &lt;name&gt; UBUS_CLIENT http://192.168.1.1/ubus</pre></li>
<!--<li>To use the ubus <b>command line</b> tool (if FHEM is running on the same device as ubus), use <code>ubus</code>. Example:
<pre>define &lt;name&gt; UBUS_CLIENT ubus</pre></li>-->
</ul>
<p>When using the websocket or HTTP connection methods, a valid user name and password must be provided. The user name defaults to <code>user</code>, but can be changed with an attribute:</p>
<pre>attr &lt;name&gt; username &lt;username&gt;</pre>
<p>The password is set with the following command, which must be issued only once, and stored as an obfuscated value on disk:</p>
<pre>set &lt;name&gt; password &lt;password&gt;</pre>
<p>When a connection and login have been performed successfully, a <code>list</code> command is executed to obtain the available calls supported by this device, and the result is filled into the <a href="#UBUS_CLIENT-readings">readings</a> of the device.</p>
<p>See the <a href="http://wiki.fhem.de/wiki/UBus">FHEM wiki</a> for further examples.</p>

<a id="UBUS_CLIENT-set"></a>
<h4>Set</h4>

<ul>
<li>
<a id="UBUS-set-disable"></a>
<pre>set &lt;name&gt; disable</pre>
Sets the <code>state</code> of the device to <code>inactive</code>, disables periodic updates and disconnects a websocket connection.
</li>

<li>
<a id="UBUS_CLIENT-set-enable"></a>
<pre>set &lt;name&gt; enable</pre>
Enables the device, establishing a websocket connection first if necessary.
</li>

<li>
<a id="UBUS_CLIENT-set-password"></a>
<pre>set &lt;name&gt; password &lt;password&gt;</pre>
Sets the password used to authenticate via websocket or HTTP and stores it on disk.
</li>
</ul>

<a id="UBUS_CLIENT-get"></a>
<h4>Get</h4>
<p>There are no get commands defined.</p>

<a id="UBUS_CLIENT-attr"></a>
<h4>Attributes</h4>

<ul>
<li>
<a id="UBUS_CLIENT-attr-disable"></a>
<a href="#disable">disable</a>
</li>

<li>
<a id="UBUS_CLIENT-attr-disabledForIntervals"></a>
<a href="#disabledForIntervals">disabledForIntervals</a>
</li>

<li>
<a id="UBUS_CLIENT-attr-refresh"></a>
<pre>attr &lt;name&gt; refresh &lt;period&gt;</pre>
Automatically check the connection after <code>period</code> seconds by issuing a <code>session list</code> request. If the session is expired, a new login is attempted. Some devices do not allow the <code>session list</code> command; in this case, set the value to 0 in order to disable the periodic refresh. The default value is 180 seconds.
</li>

<li>
<a id="UBUS_CLIENT-attr-timeout"></a>
<pre>attr &lt;name&gt; timeout &lt;period&gt;</pre>
Sets the timeout value in the login request, i.e., the period of inactivity after which a session expires. This should be set larger than the time between requests. The default value is 300 seconds.
</li>

<li>
<a id="UBUS_CLIENT-attr-username"></a>
<pre>attr &lt;name&gt; username &lt;username&gt;</pre>
Defines the username to be used for login via websocket or HTTP. The default value is <code>user</code>.
</li>
</ul>

<a id="UBUS_CLIENT-readings"></a>
<h4>Readings</h4>
<p>When the connection is established, the module executes a <code>list</code> command and creates the following readings:</p>
<ul>
<li><code>mod_&lt;n&gt;_name</code>: name (path) of the n'th module in the uBus tree</li>
<li><code>mod_&lt;n&gt;_func_&lt;m&gt;_name</code>: name of the m'th function supported by the n'th module</li>
<li><code>mod_&lt;n&gt;_func_&lt;m&gt;_param_&lt;k&gt;_name</code>: name of the k'th parameter of the m'th function of the n'th module</li>
<li><code>mod_&lt;n&gt;_func_&lt;m&gt;_param_&lt;k&gt;_type</code>: type of the k'th parameter of the m'th function of the n'th module</li>
</ul>
<p>These can be used to perform calls using the <a href="#UBUS_CALL">UBUS_CALL</a> module.</p>
</ul>

=end html

=begin html_DE

<a id="UBUS_CLIENT"></a>
<h3>UBUS_CLIENT</h3>

=end html_DE

=cut

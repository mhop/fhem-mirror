################################################################################
#
# 72_UBUS_CALL.pm
#
# Performs "call" requests to the uBus command line / JSON-RPC interface.
#
# $Id$
#
################################################################################

package FHEM::UBUS_CALL; ## no critic "Package declaration"

use strict;
use warnings;

use Exporter qw(import);
use Carp qw(carp);
use JSON qw(encode_json decode_json);
use GPUtils qw(GP_Import);
use Data::Dumper;

BEGIN {
	GP_Import (
		qw(
			AssignIoPort
			IOWrite
			Log3
			Debug
			IsDisabled
			InternalTimer
			RemoveInternalTimer
			EvalSpecials
			AnalyzePerlCommand
			AttrVal
			ReadingsVal
			ReadingsNum
			ReadingsAge
			readingsSingleUpdate
			readingsBeginUpdate
			readingsBulkUpdate
			readingsBulkUpdateIfChanged
			readingsEndUpdate
			readingsDelete
			makeReadingName
			deviceEvents
			gettimeofday
			json2nameValue
		)
	)
};

sub ::UBUS_CALL_Initialize { goto &Initialize };

sub Initialize
{
	my $hash = shift // return;

	$hash->{DefFn}    = \&Define;
	$hash->{UndefFn}  = \&Undef;
	$hash->{SetFn}    = \&Set;
	$hash->{AttrFn}   = \&Attr;
	$hash->{ParseFn}   = \&Parse;
	$hash->{RenameFn} = \&Rename;

	$hash->{AttrList} = 'disable disabledForIntervals IODev interval readings:textField-long ' . $main::readingFnAttributes;
	$hash->{parseParams} = 1;

	$hash->{Match} = '.*:call:.*';
	return;
}

sub Define
{
	my $hash = shift;
	my $apar = shift;
	my $hpar = shift;

	if(int(@{$apar}) != 4)
	{
		return "Correct syntax: 'define <name> UBUS_CALL <module> <function> [<parameters>]'";
	}

	$hash->{module} = $apar->[2];
	$hash->{function} = $apar->[3];
	$hash->{params} = $hpar;

	AssignIoPort($hash);

	return $main::init_done ? GetUpdate($hash) : InternalTimer(gettimeofday() + 1, \&GetUpdate, $hash);
}

sub Undef
{
	my $hash = shift // return;

	Disconnect($hash);

	return;
}

sub Rename
{
	return;
}

sub Set
{
	my $hash = shift;
	my $apar = shift;
	my $hpar = shift;

	my $name = shift @{$apar} // return;
	my $cmd = shift @{$apar} // return qq{"set $name" needs at least one argument};

	if($cmd eq 'update')
	{
		GetUpdate($hash);
		return;
	}

	if($cmd eq 'disable')
	{
		RemoveInternalTimer($hash, \&GetUpdate);
		readingsSingleUpdate($hash, 'state', 'inactive', 1);

		return;
	}

	if($cmd eq 'enable')
	{
		readingsSingleUpdate($hash, 'state', 'active', 1);
		GetUpdate($hash);

		return;
	}

	return "Unknown argument $cmd, choose one of disable:noArg enable:noArg update:noArg";
}

sub Attr
{
	my $cmd = shift // return;
	my $name = shift // return;
	my $attr = shift // return;
	my $value = shift // return;

	if($cmd eq 'set')
	{
		if($attr eq 'IODev')
		{
			my $iohash = $main::defs{$value};
			return "Unknown physical device $value." if !defined $iohash;
			return "Physical device $value must be of type UBUS_CLIENT." if $iohash->{TYPE} ne "UBUS_CLIENT";
		}

		if($attr eq 'interval')
		{
			return "$attr must be non-negative." if $value < 0;
		}
	}

	return;
}

sub GetUpdate
{
	my $hash = shift // return;
	my $name = $hash->{NAME};
	my $module = $hash->{module};
	my $function = $hash->{function};
	my $params = $hash->{params};

	if(!$module || !$function || IsDisabled($name))
	{
		return;
	}

	# Clean up possible previous / stale call IDs.

	RemoveInternalTimer($hash, \&GetUpdate);

	$hash->{rpc} = {};
	$hash->{rpccount} = 0;

	# Check for Perl code.

	if($module =~ m/^{.*}$/)
	{
		my $emodule = EvalSpecials(
			$module,
			(
				'%NAME' => $name
			)
		);
		$module = AnalyzePerlCommand(undef, $emodule);
	}

	if($function =~ m/^{.*}$/)
	{
		my $efunction = EvalSpecials(
			$function,
			(
				'%NAME' => $name
			)
		);
		$function = AnalyzePerlCommand(undef, $efunction);
	}

	foreach my $key (keys %{$params})
	{
		if($params->{$key} =~ m/^{.*}$/)
		{
			my $eparam = EvalSpecials(
				$params->{$key},
				(
					'%NAME' => $name
				)
			);
			$params->{$key} = AnalyzePerlCommand(undef, $eparam);
		}
	}

	# Expand comma-separated lists / array references.

	my @calls = ({module => $module, function => $function, params => $params});

	my @modules = (ref $module eq 'ARRAY' ? @{$module} : split(',', $module));
	if(scalar @modules > 1)
	{
		my @ecalls = ();
		foreach my $call (@calls)
		{
			foreach my $m (@modules)
			{
				push(@ecalls, {module => $m, function => $call->{function}, params => $call->{params}});
			}
		}
		@calls = @ecalls;
	}

	my @functions = (ref $function eq 'ARRAY' ? @{$function} : split(',', $function));
	if(scalar @functions > 1)
	{
		my @ecalls = ();
		foreach my $call (@calls)
		{
			foreach my $f (@functions)
			{
				push(@ecalls, {module => $call->{module}, function => $f, params => $call->{params}});
			}
		}
		@calls = @ecalls;
	}

	foreach my $key (keys %{$params})
	{
		my @pvals = (ref $params->{$key} eq 'ARRAY' ? @{$params->{$key}} : split(',', $params->{$key}));
		if(scalar @pvals > 1)
		{
			my @ecalls = ();
			foreach my $call (@calls)
			{
				foreach my $p (@pvals)
				{
					my %par = %{$call->{params}};
					$par{$key} = $p;
					push(@ecalls, {module => $call->{module}, function => $call->{function}, params => \%par});
				}
			}
			@calls = @ecalls;
		}
	}

	# Send calls to physical module.

	foreach my $call (@calls)
	{
		Log3($name, 5, "UBUS_CALL ($name) - sending call: " . Dumper($call));

		my $id = IOWrite($hash, $name, 'call', $call->{module}, $call->{function}, $call->{params});

		next if(!defined $id);

		if($id =~ m/^$name:call:(.*)$/)
		{
			$hash->{rpc}{$1} = $call;
			$hash->{rpccount}++;
		}
		else
		{
			Log3($name, 2, "UBUS_CALL ($name) - UBUS_CLIENT returned unexpected call ID $id");
		}
	}

	if($hash->{rpccount} == 0)
	{
		readingsSingleUpdate($hash, 'state', 'disconnected', 1);
	}
	elsif($hash->{rpccount} == scalar @calls)
	{
		readingsSingleUpdate($hash, 'state', 'updating', 1);
	}
	else
	{
		readingsSingleUpdate($hash, 'state', 'unknown', 1);
	}

	my $interval = AttrVal($name, 'interval', 60);

	if($interval)
	{
		InternalTimer(gettimeofday() + $interval, \&GetUpdate, $hash);
	}

	return;
}

sub Parse
{
	my $iohash = shift // return;
	my $buf = shift // return;
	my $ioname = $iohash->{NAME};

	my $data;
	eval { $data = decode_json($buf); };

	if($@)
	{
		Log3($ioname, 1, "UBUS - decode_json error: $@");
		return;
	}

	my $error = $data->{result}[0];
	my $result = $data->{result}[1];
	my $id = $data->{id};

	if($id !~ m/^(.*):call:(.*)/)
	{
		return;
	}

	my $name = $1;
	$id = $2;
	my $hash = $main::defs{$name};

	readingsSingleUpdate($hash, 'state', 'received', 1);

	if(!defined $hash)
	{
		Log3($ioname, 1, "UBUS - received message for unknown device $name");
		return;
	}

	if($hash->{TYPE} ne 'UBUS_CALL')
	{
		Log3($ioname, 1, "UBUS - received message for unexpected device type " . $hash->{TYPE});
		return;
	}

	my ($module, $function, $params);

	if(!defined $hash->{rpc}{$id})
	{
		Log3($name, 2, "UBUS_CALL ($name) - received message with unexpected ID $id");
		return $name;
	}

	Log3($name, 5, "UBUS_CALL ($name) - received message with ID $id: " . Dumper($hash->{rpc}{$id}));
	$module = $hash->{rpc}{$id}{module} // q{};
	$function = $hash->{rpc}{$id}{function} // q{};
	$params = $hash->{rpc}{$id}{params} // {};

	if($error)
	{
		Log3($name, 2, "UBUS_CALL ($name) - call returned error $error: " . Dumper($hash->{rpc}{$id}));
	}

	delete $hash->{rpc}{$id};
	$hash->{rpccount}--;

	# Parse response into readings

	my $code = AttrVal($name, 'readings', '{FHEM::UBUS_CALL::DefaultReadings($RAW)}');
	my $ecode = EvalSpecials(
		$code,
		(
			'%RAW' => $buf,
			'%DATA' => $result,
			'%ERROR' => $error,
			'%NAME' => $name,
			'%MODULE' => $module,
			'%FUNCTION' => $function,
			'%PARAMS' => $params
		)
	);
	my $ret = AnalyzePerlCommand(undef, $ecode);

	if($ret && ref $ret eq 'HASH')
	{
		readingsBeginUpdate($hash);
		foreach my $key (keys %{$ret})
		{
			readingsBulkUpdate($hash, makeReadingName($key), $ret->{$key});
		}
		readingsEndUpdate($hash, 1);
	}

	if($hash->{rpccount} == 0)
	{
		readingsSingleUpdate($hash, 'state', 'updated', 1);
	}

	return $name;
}

sub DefaultReadings
{
	my $raw = shift // return {};
	my $prefix = shift;
	if($raw =~ m/"result"\s*:\s*\[\s*(\d+)\s*,\s*(\{.*})\s*\]/)
	{
		my $ret = json2nameValue($2, $prefix);
		$ret->{error} = $1;
		return $ret;
	}
	return {};
}

1;

__END__

=pod

=item device
=item summary Performs calls via the JSON-RPC interface.
=item summary_DE Sendet Anfragen mittels einer JSON-RPC Schnittstelle.

=begin html

<a id="UBUS_CALL"></a>
<h3>UBUS_CALL</h3>

<ul>
<p>The <a href="http://openwrt.org/docs/guide-developer/ubus">uBus IPC/RPC system</a> is a common interconnect system used by OpenWrt. Services can connect to the bus and provide methods that can be called by other services or clients or deliver events to subscribers. This module implements the "call" type request. It is supposed to be used together with an <a href="#UBUS_CLIENT">UBUS_CLIENT</a> device, which must be defined first.</p>

<a id="UBUS_CALL-define"></a>
<h4>Define</h4>

<pre>define &lt;name&gt; UBUS_CALL &lt;module&gt; &lt;function&gt; [&lt;parameters&gt;]</pre>
<p>uBus calls are grouped under separate modules or "paths". In order to call a particular function, one needs to specify this path, the function to be called and optional parameters as <code>&lt;key&gt;=&lt;value&gt;</code> pairs. Examples:</p>
<ul>
<li><pre>define &lt;name&gt; UBUS_CALL system board</pre></li>
<li><pre>define &lt;name&gt; UBUS_CALL iwinfo devices</pre></li>
<li><pre>define &lt;name&gt; UBUS_CALL network.device status name=eth0</pre></li>
<li><pre>define &lt;name&gt; UBUS_CALL file list path=/tmp</pre></li>
<li><pre>define &lt;name&gt; UBUS_CALL file read path=/etc/hosts</pre></li>
</ul>
<p>The supported calls highly depend on the device on which the uBus daemon is running and its firmware. To get an overview of the calls supported by your device, consult the <a href="#UBUS_CLIENT-readings">readings of the UBUS_CLIENT device</a> which represents the connection to the physical device. The <code>&lt;module&gt;</code>, <code>&lt;function&gt;</code> and each <code>&lt;value&gt;</code> can be in any of the following forms:</p>
<ul>
<li>
A single keyword. In this case, only one call will be performed, with the module / function / parameter value set to the given content.
</li>

<li>
A comma-separated list. In this case, one call will be performed for every value given in the list. Example:
<pre>define &lt;name&gt; UBUS_CALL system board,info</pre>
This will perform two calls, one to the function <code>board</code> and another to the function <code>info</code>.
</li>

<li>
Perl code (enclosed in {}). The code may return a single keyword, a comma-separated list or an array reference. It is called whenever an uBus call is performed, and thus allows to set the value dynamically. If a single keyword is returned, only one call is performed, as if the keyword is given directly. If a comma-separated list or an array of keywords are returned, the call is performed for each of the returned values. Example:
<pre>define &lt;name&gt; UBUS_CALL network.device status name={&lt;code returning a list of network devices&gt>}</pre>
</li>
</ul>
<p>Note that the <code>&lt;module&gt;</code>, <code>&lt;function&gt;</code> and each <code>&lt;value&gt;</code> <b>must not</b> contain whitespace (since whitespace is used to separate the arguments). This also applies to Perl code. For longer pieces of code, it is recommended to define a sub in 99_myUtils.pm and call it from there.</p>
<p>If more than one comma-separated list or Perl code returning an array reference is used, calls are performed for each possible configuration. Example:</p>
<pre>define &lt;name&gt; UBUS_CALL file stat,read path=/etc/hosts,/etc/group</pre>
<p>This will perform four calls, to perform both <code>stat</code> and <code>read</code> on each of the two files. To distinguish the different calls when the response is received and parsed into readings, use a custom <a href="#UBUS_CALL-attr-readings">readings</a> parser code, that makes use of the variables <code>$MODULE</code>, <code>$FUNCTION</code> and <code>%PARAMS</code>. These will contain the values used for the call, for which the response has been received.</p>
<p>See the <a href="http://wiki.fhem.de/wiki/UBus">FHEM wiki</a> for further examples.</p>

<a id="UBUS_CALL-set"></a>
<h4>Set</h4>

<ul>
<li>
<a id="UBUS_CALL-set-disable"></a>
<pre>set &lt;name&gt; disable</pre>
Sets the <code>state</code> of the device to <code>inactive</code>, disables periodic updates and disconnects a websocket connection.
</li>

<li>
<a id="UBUS_CALL-set-enable"></a>
<pre>set &lt;name&gt; enable</pre>
Enables the device, so that automatic updates are performed.
</li>

<li>
<a id="UBUS_CALL-set-update"></a>
<pre>set &lt;name&gt; update</pre>
Performs an uBus call, updates the corresponding readings and resets any pending interval timer.
</li>
</ul>

<a id="UBUS_CALL-get"></a>
<h4>Get</h4>
<p>There are no get commands defined.</p>

<a id="UBUS_CALL-attr"></a>
<h4>Attributes</h4>

<ul>
<li>
<a id="UBUS_CALL-attr-disable"></a>
<a href="#disable">disable</a>
</li>

<li>
<a id="UBUS_CALL-attr-disabledForIntervals"></a>
<a href="#disabledForIntervals">disabledForIntervals</a>
</li>

<li>
<a id="UBUS_CALL-attr-interval"></a>
<pre>attr &lt;name&gt; interval &lt;interval&gt;</pre>
Defines the interval (in seconds) between performing consecutive calls and updating the readings.
</li>

<li>
<a id="UBUS_CALL-attr-IODev"></a>
<pre>attr &lt;name&gt; IODev &lt;device&gt;</pre>
If there are multiple <a href="#UBUS_CLIENT">UBUS_CLIENT</a> devices defined, set this attribute to the value of the device which should be used to make the connection. It is not needed if there is only one device.
</li>

<li>
<a id="UBUS_CALL-attr-readings"></a>
<pre>attr &lt;name&gt; readings {&lt;Perl-code&gt;}</pre>
<p>Perl code which must return a hash of <code>&lt;key&gt; =&gt; &lt;value&gt;</code> pairs, where <code>&lt;key&gt;</code> is the name of the reading and <code>&lt;value&gt;</code> is its value. The following variables are available in the code:</p>
<ul>
<li><code>$NAME</code>: name of the UBUS_CALL device.</li>
<li><code>$MODULE</code>: module name used in the call (see <a href="#UBUS_CALL-define">definition</a>).</li>
<li><code>$FUNCTION</code>: function name used in the call (see <a href="#UBUS_CALL-define">definition</a>).</li>
<li><code>%PARAMS</code>: hash of parameters used in the call (see <a href="#UBUS_CALL-define">definition</a>).</li>
<li><code>$RAW</code>: raw JSON response returned by the call.</li>
<li><code>$ERROR</code>: reported error code, 0 means success.</li>
<li><code>%DATA</code>: decoded result data as Perl hash.</li>
</ul>
<p>If this attribute is omitted, its default value is <code>{FHEM::UBUS_CALL::DefaultReadings($RAW)}</code>. This function executes <code>json2nameValue</code> in the JSON result and turns all returned data into readings named by their position in the JSON tree. It is also possible to call this function in user-defined Perl code first, and then modify the returned hash, for example by deleting unwanted readings or adding additional, computed readings. The variables <code>$MODULE</code>, <code>$FUNCTION</code> and <code>%PARAMS</code> contain the values used for the call, for which the response has been received, and can be used to give unique names to the readings.</p>
</li>
</ul>

<a id="UBUS_CALL-readings"></a>
<h4>Readings</h4>
<p>Any readings are defined by the attribute <a href="#UBUS_CALL-attr-readings">readings</a>.</p>
</ul>

=end html

=begin html_DE

<a id="UBUS_CALL"></a>
<h3>UBUS_CALL</h3>

=end html_DE

=cut

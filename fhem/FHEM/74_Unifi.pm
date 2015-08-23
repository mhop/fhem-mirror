###############################################################################
# $Id: 74_Unifi.pm 2015-08-23 23:00 - rapster - rapster at x0e dot de $ 

package main;
use strict;
use warnings;
use HttpUtils;
use POSIX qw(strftime);
use JSON qw(decode_json);
###############################################################################

sub Unifi_Initialize($$) { 
    my ($hash) = @_; 
    $hash->{DefFn}     = "Unifi_Define";
    $hash->{UndefFn}   = "Unifi_Undef";
    $hash->{SetFn}     = "Unifi_Set";
    $hash->{GetFn}     = "Unifi_Get";
    $hash->{AttrFn}    = 'Unifi_Attr';
    $hash->{NOTIFYDEV} = "global";
    $hash->{NotifyFn}  = "Unifi_Notify";
    $hash->{AttrList}  = "disable:1,0 "
                         .$readingFnAttributes;
}
###############################################################################

sub Unifi_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    return "Wrong syntax: use define <name> Unifi <ip> <port> <username> <password> [<interval> [<siteID> [<version>]]]" if(int(@a) < 6);
    return "Wrong syntax: <port> is not a number!"                           if(!looks_like_number($a[3]));
    return "Wrong syntax: <interval> is not a number!"                       if($a[6] && !looks_like_number($a[6]));
    return "Wrong syntax: <interval> too small, must be at least 10"         if($a[6] && $a[6] < 10);
    return "Wrong syntax: <version> is not a valid number! Must be 3 or 4."  if($a[8] && (!looks_like_number($a[8]) || $a[8] !~ /3|4/));
    
    my $name = $a[0];
    my $oldLoginData = ($hash->{loginParams}) ? $hash->{loginParams}->{data}.$hash->{url} : 0;
    %$hash = (   %$hash,
        url      => "https://".$a[2].(($a[3] != 443) ? ':'.$a[3] : '').'/',
        interval => $a[6] || 30,
        siteID   => $a[7] || 'default',
        version  => $a[8] || 4,
    );
    $hash->{httpParams} = {
        hash            => $hash,
        timeout         => 5,
        method          => "POST",
        noshutdown      => 0,
        ignoreredirects => 1,
        loglevel        => 5,
        sslargs         => { SSL_verify_mode => 'SSL_VERIFY_NONE' },
        header          => "Content-Type: application/json;charset=UTF-8"
    };
    $hash->{loginParams} = {
        %{$hash->{httpParams}},
        url      => $hash->{url}."api/login",
        data     => "{'username':'".$a[4]."', 'password':'".$a[5]."'}",
        cookies  => ($hash->{loginParams}->{cookies}) ? $hash->{loginParams}->{cookies} : '',
        callback => \&Unifi_Login_Receive
    };
    
    # Don't use old cookies when user, pw or url changed
    if($oldLoginData && $oldLoginData ne $hash->{loginParams}->{data}.$hash->{url}) {
        $hash->{loginParams}->{cookies} = '';
        readingsSingleUpdate($hash,"state","disconnected",1);
    }

    Log3 $name, 5, "$name: Defined with url:$hash->{url}, interval:$hash->{interval}, siteID:$hash->{siteID}, version:$hash->{version}";
    return undef;
}
###############################################################################

sub Unifi_Undef($$) {
    my ($hash,$arg) = @_;
    
    RemoveInternalTimer($hash);
    return undef;
}
###############################################################################

sub Unifi_Notify($$) {
    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};

    return if($dev->{NAME} ne "global");
    return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

    if(AttrVal($name, "disable", 0)) {
        Log3 $name, 5, "$name: Notify - Detect disabled state, do nothing...";
        readingsSingleUpdate($hash,"state","disabled",0) if($hash->{STATE} ne "disabled");
    } else {
        Log3 $name, 5, "$name: Notify - Call DoUpdate...";
        RemoveInternalTimer($hash);
        readingsSingleUpdate($hash,"state","initialized",0);
        Unifi_DoUpdate($hash);
    }
    return undef;
}
###############################################################################

sub Unifi_Set($@) {
    my ($hash,@a) = @_;
    return "\"set $hash->{NAME}\" needs at least an argument" if ( @a < 2 );

    my ($name,$setName,$setVal) = @a;

    if (AttrVal($name, "disable", 0) && $setName !~ /clear/) {
        if($setName eq "?") {
            return "Unknown argument $setName, choose one of clear:all,readings,clientData";
        } else {
            Log3 $name, 5, "$name: set called with $setName but device is disabled!";
        }
        return undef;
    }
    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "") if ($setName ne "?");

    if($hash->{STATE} ne 'connected' && $setName !~ /clear/) {
        return "Unknown argument $setName, choose one of clear:all,readings,clientData";
    }
    elsif($setName !~ /update|clear/) {
        return "Unknown argument $setName, choose one of update:noArg clear:all,readings,clientData";
    }
    else {
        Log3 $name, 4, "$name: set $setName";
        
        if ($setName eq 'update') {
            Unifi_DoUpdate($hash,1);
        } 
        elsif ($setName eq 'clear') {
            if ($setVal eq 'readings' || $setVal eq 'all') {
                for (keys %{$hash->{READINGS}}) {
                    delete $hash->{READINGS}->{$_} if($_ ne 'state');
                }
            }
            if ($setVal eq 'clientData' || $setVal eq 'all') {
                for (keys %{$hash->{clients}}) {
                    delete $hash->{clients}->{$_};
                }
            }
        }
    }
    return undef;
}
###############################################################################

sub Unifi_Get($@) {
    my ($hash,@a) = @_;
	return "\"get $hash->{NAME}\" needs at least one argument" if ( @a < 2 );
    my ($name,$getName,$getVal) = @a;
    my $clients = join(',',keys(%{$hash->{clients}}));
    
    if($getName !~ /clientData/) {
        return "Unknown argument $getName, choose one of ".(($clients) ? "clientData:all,$clients" : "");
    } 
    elsif ($getName eq 'clientData' && $clients) {
        my $clientData = '';
        if(!$getVal || $getVal eq 'all') {
            $clientData .= "======================================\n";
            for my $client (sort keys %{$hash->{clients}}) {
                for (sort keys %{$hash->{clients}->{$client}}) {
                    $clientData .= "$_ = $hash->{clients}->{$client}->{$_}\n";
                }
                $clientData .= "======================================\n";
            }
            return $clientData;
        } 
        elsif(defined($hash->{clients}->{$getVal})) {
            $clientData .= "======================================\n";
            for (sort keys %{$hash->{clients}->{$getVal}}) {
                $clientData .= "$_ = $hash->{clients}->{$getVal}->{$_}\n";
            }
            $clientData .= "======================================\n";
            return $clientData;
        } 
        else {
            return "$hash->{NAME}: Unknown client '$getVal' in command '$getName', choose one of: $clients";
        }
    }
    return undef;
}
###############################################################################

sub Unifi_Attr(@) {
    my ($cmd,$name,$attr_name,$attr_value) = @_;
    my $hash = $defs{$name};
    
    if($cmd eq "set") {
        if($attr_name eq "disable") {
            if($attr_value == 1) {
                readingsSingleUpdate($hash,"state","disabled",1);
                RemoveInternalTimer($hash);
            }
            elsif($attr_value == 0 && $hash->{STATE} eq "disabled") {
                readingsSingleUpdate($hash,"state","initialized",1);
                Unifi_DoUpdate($hash);
            }
        }
    }
    elsif($cmd eq "del") {
        if($attr_name eq "disable" && $hash->{STATE} eq "disabled") {
            readingsSingleUpdate($hash,"state","initialized",1);
            Unifi_DoUpdate($hash);
        }
    }
    return undef;
}
###############################################################################

sub Unifi_DoUpdate($@) {
    my ($hash,$manual) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: DoUpdate - executed.";
    
    if($hash->{STATE} eq "disabled") {
        Log3 $name, 5, "$name: DoUpdate - Detect disabled state, End now...";
        return undef;
    }
    
    if ($hash->{STATE} ne 'connected') {
        if($manual) {
            Log3 $name, 3, "$name: DoUpdate - Manual Updates only allowed while connected, End now...";
        } else {
            Unifi_Login_Send($hash)
        }
    } else {
        Unifi_GetClients_Send($hash);
        # Do more...
        if($manual) {
            Log3 $name, 5, "$name: DoUpdate - This was a manual-updated.";
        } else {
            InternalTimer(time()+$hash->{interval}, 'Unifi_DoUpdate', $hash, 0);
        }
    }
    return undef;
}
###############################################################################

sub Unifi_Login_Send($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: Login_Send - executed.";
    
    if($hash->{STATE} eq "disabled") {
        Log3 $name, 5, "$name: Login_Receive - Detect disabled state, End now...";
        return undef;
    }
    HttpUtils_NonblockingGet($hash->{loginParams});
    return undef;
}
sub Unifi_Login_Receive($) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: Login_Receive - executed.";
    
    if ($err ne "") {
        Log3 $name, 5, "$name: Login_Receive - Error while requesting ".$param->{url}." - $err";
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400) {
            eval {
                $data = decode_json($data);
                1;
            } or do {
                my $e = $@;
                Log3 $name, 5, "$name: Login_Receive - Failed to decode returned json object! Will try again after interval... - error:$e";
                
                InternalTimer(time()+$hash->{interval}, 'Unifi_Login_Send', $hash, 0);
                return undef;
            };
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name: Login_Receive - Login successfully! - state:'$data->{meta}->{rc}'";
                $param->{cookies} = '';
                for (split("\r\n",$param->{httpheader})) {
                    if(/^Set-Cookie/) {
                        s/Set-Cookie:\s(.*?);.*/Cookie: $1/;
                        $param->{cookies} .= $_.'\r\n';
                    }
                }
                Log3 $name, 5, "$name: Login_Receive - Received-cookies:$param->{cookies}";
                
                readingsSingleUpdate($hash,"state","connected",1);
                Unifi_DoUpdate($hash);
                return undef;
            }
            else {
                if (defined($data->{meta}->{msg})) {
                    my $loglevel = ($data->{meta}->{msg} eq 'api.err.Invalid') ? 1 : 5;
                    Log3 $name, $loglevel, "$name: Login_Receive - Login Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'";
                } else {
                    Log3 $name, 5, "$name: Login_Receive - Login Failed (without message)! - state:'$data->{meta}->{rc}'";
                }
                $param->{cookies} = '';
                readingsSingleUpdate($hash,"state","disconnected",1) if($hash->{READINGS}->{state}->{VAL} ne "disconnected");
            }
        } else {
            Log3 $name, 5, "$name: Login_Receive - Failed with HTTP Code $param->{code}!";
            readingsSingleUpdate($hash,"state","disconnected",1) if($hash->{READINGS}->{state}->{VAL} ne "disconnected");
        }
    }
    Log3 $name, 5, "$name: Login_Receive - Connect/Login to Unifi-Controller failed! Will try again after interval...";
    readingsSingleUpdate($hash,"state","disconnected",1) if($hash->{READINGS}->{state}->{VAL} ne "disconnected");
    InternalTimer(time()+$hash->{interval}, 'Unifi_Login_Send', $hash, 0);
    return undef;
}
###############################################################################

sub Unifi_GetClients_Send($) {
    my ($hash) = @_;
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: GetClients_Send - executed.";
    
    my $param = {
        %{$hash->{httpParams}},
        url      => $hash->{url}."api/s/$hash->{siteID}/stat/sta",
        header   => $hash->{loginParams}->{cookies}.$hash->{httpParams}->{header},
        callback => \&Unifi_GetClients_Receive
    };
    HttpUtils_NonblockingGet($param);
    return undef;
}
sub Unifi_GetClients_Receive($) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: GetClients_Receive - executed.";
    
    if ($err ne "") {
        Log3 $name, 5, "$name: GetClients_Receive - Error while requesting ".$param->{url}." - $err";
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 401  || $param->{code} == 400) {
            eval {
                $data = decode_json($data);
                1;
            } or do {
                my $e = $@;
                Log3 $name, 5, "$name: GetClients_Receive - Failed to decode returned json object! - error:$e";
                return undef;
            };
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name: GetClients_Receive - Data received successfully! - state:'$data->{meta}->{rc}'";
                
                readingsBeginUpdate($hash);
                my $connectedClientIDs = {};
                my $i = 1;
                for my $h (@{$data->{data}}) {
                    $hash->{clients}->{$h->{user_id}} = $h;
                    $connectedClientIDs->{$h->{user_id}} = 1;
                    readingsBulkUpdate($hash,$h->{user_id}."_hostname",($h->{hostname}) ? $h->{hostname} : ($h->{ip}) ? $h->{ip} : 'Unknown');
                    readingsBulkUpdate($hash,$h->{user_id}."_last_seen",strftime "%Y-%m-%d %H:%M:%S",localtime($h->{last_seen}));
                    readingsBulkUpdate($hash,$h->{user_id}."_uptime",$h->{uptime});
                    readingsBulkUpdate($hash,$h->{user_id},'connected');
                }
                for my $clientID (keys %{$hash->{clients}}) {
                    if (!defined($connectedClientIDs->{$clientID}) && $hash->{READINGS}->{$clientID}->{VAL} ne 'disconnected') {
                        Log3 $name, 5, "$name: GetClients_Receive - Client '$clientID' previously connected is now disconnected.";
                        readingsBulkUpdate($hash,$clientID,'disconnected');
                    }
                }
                readingsEndUpdate($hash,1);
            }
            else {
                if (defined($data->{meta}->{msg})) {
                    Log3 $name, 5, "$name: GetClients_Receive - Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'";
                    if($data->{meta}->{msg} eq 'api.err.LoginRequired') {
                        Log3 $name, 5, "$name: GetClients_Receive - LoginRequired detected. Set state to disconnected...";
                        readingsSingleUpdate($hash,"state","disconnected",1) if($hash->{READINGS}->{state}->{VAL} ne "disconnected");
                    }
                } else {
                    Log3 $name, 5, "$name: GetClients_Receive - Failed (without message)! - state:'$data->{meta}->{rc}'";
                }
            }
        }
        else {
            Log3 $name, 5, "$name: GetClients_Receive - Failed with HTTP Code $param->{code}!";
        }
    }
    return undef;
}
###############################################################################

### KNOWN RESPONSES ###
# { "data" : [ ] , "meta" : { "msg" : "api.err.Invalid" , "rc" : "error"}}
# { "data" : [ ] , "meta" : { "rc" : "ok"}}
# { "data" : [ ] , "meta" : { "msg" : "api.err.NoSiteContext" , "rc" : "error"}}
# { "data" : [ ] , "meta" : { "msg" : "api.err.LoginRequired" , "rc" : "error"}}
###############################################################################


1;


=pod
=begin html

<a name="Unifi"></a>
<h3>Unifi</h3>
<ul>

Unifi is the fhem module for the Ubiquiti Networks (UBNT) - Unifi Controller.<br><br>
This module is very new, therefore it supports only a limited function selection of the unifi-controller.<br><br>
At the moment you can use the 'PRESENCE' function, which will tell you if a device is connected to your WLAN (even in PowerSave Mode!) and get some informations.<br>
Immediately after connecting to your WLAN it will set the device-reading to 'connected' and about 5 minutes after leaving your WLAN it will set the reading to 'disconnected'.<br>
The device will be still connected, even it is in PowerSave-Mode. (In this mode the devices are not pingable, but the connection to the unifi-controller does not break off.)
<br>
<h4>Prerequisites</h4>
  <ul>
      The Perl module JSON is required. <br>
      On Debian/Raspbian: <code>apt-get install libjson-perl </code><br>
      Via CPAN: <code>cpan install JSON</code>
  </ul>

<h4>Define</h4>
<ul>
    <code>define &lt;name&gt; Unifi &lt;ip&gt; &lt;port&gt; &lt;username&gt; &lt;password&gt; [&lt;interval&gt; [&lt;siteID&gt; [&lt;version&gt;]]]</code>
    <br><br>
	<br>
    &lt;name&gt;:
    <ul>
    <code>The FHEM device name for the device.</code><br>
    </ul>
    &lt;ip&gt;:
    <ul>
    <code>The ip of your unifi-controller.</code><br>
    </ul>
    &lt;port&gt;:
    <ul>
    <code>The port of your unifi-controller. Normally it's 8443 or 443.</code><br>
    </ul>
    &lt;username&gt;:
    <ul>
    <code>The Username to log on.</code><br>
    </ul>
    &lt;password&gt;:
    <ul>
    <code>The password to log on.</code><br>
    </ul>
    [&lt;interval&gt;]:
    <ul>
    <code>optional: interval to fetch the information from the unifi-api. <br>
          default: 30 seconds</code><br>
    </ul>
    [&lt;siteID&gt;]:
    <ul>
    <code>optional: You can find the site-ID by selecting the site in the UniFi web interface.<br>
          e.g. (https://localhost:8443/manage/s/foobar) siteId = 'foobar'.<br>
          default: 'default'</code><br>
    </ul>
    [&lt;version&gt;]:
    <ul>
    <code>optional: Your unifi-controller version.<br>
          This is not used at the moment, both v3.x and v4.x controller are supported.<br>
          default: 4</code><br>
    </ul> <br>
    <br>
    Notes:<br>
    <li>If the login-cookie gets invalid (timeout or change of user-credentials / url), 'update with login' will be executed in next interval. </li>
    <li>If you change &lt;interval&gt; while Unifi is running, the interval is changed only after the next automatic-update. <br>
        To change it immediately, disable Unifi with "attr disable 1" and enable it again.</li>

</ul>
<h4>Example</h4>
<ul>
    <code>define my_unifi_controller Unifi 192.168.1.15 443 user password</code><br>
</ul>

<h4>Set</h4>
<ul>
    <li><code>set &lt;name&gt; update</code><br>
    Makes immediately a manual update. </li><br>
    Note: Manual updates are only possible while unifi-controller is connected and device is not disabled.
</ul><br>
<ul>
    <li><code>set &lt;name&gt; clear &lt;readings|clientData|all&gt</code><br>
    Clears the readings, clientData or all. </li>
</ul>


<h4>Get</h4>
<ul>
    <li><code>get &lt;name&gt; clientData &lt;all|clientID&gt</code><br>
    Show more details about clients.</li>
</ul>


<h4>Attributes</h4>
<ul>
    <li>attr disable &lt;1|0&gt;<br>
    With this attribute you can disable the whole module. <br>
    If set to 1 the module will be stopped and no updates are performed.<br>
    If set to 0 the automatic updating will performed.</li>
    <li>attr <a href="#verbose">verbose</a> 5<br>
    This attribute will help you if something does not work as espected.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
</ul>

<h4>Readings</h4>
<ul>
    Note: All readings generate events. You can control this with <a href="#readingFnAttributes">these global attributes</a>.
    <li>Each device has multiple readings.<br></li>
    <li>The unifi-device reading 'state' represents the connection-state to the unifi-controller.<br>
    Possible states are 'connected', 'disconnected', 'initialized' and 'disabled'</li>
</ul>
<br>

</ul>

=end html
=cut

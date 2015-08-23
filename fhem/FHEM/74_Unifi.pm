###############################################################################
# $Id: 74_Unifi.pm 2015-08-23 01:00 - rapster - rapster at x0e dot de $ 

package main;
use strict;
use warnings;
use HttpUtils;
use POSIX qw(strftime);
use JSON qw(decode_json);
###############################################################################

sub Unifi_Initialize($$) { 
    my ($hash) = @_; 
    $hash->{DefFn}    = "Unifi_Define";
    $hash->{UndefFn}  = "Unifi_Undef";
    $hash->{SetFn}    = "Unifi_Set";
    $hash->{GetFn}    = "Unifi_Get";
    $hash->{AttrList} = $readingFnAttributes;
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
        cookies  => '',
        callback => \&Unifi_Login_Receive
    };
    
    readingsSingleUpdate($hash,"state","initialized",0);
    Log3 $name, 5, "$name: Defined with url:$hash->{url}, interval:$hash->{interval}, siteID:$hash->{siteID}, version:$hash->{version}";	
    
    RemoveInternalTimer($hash);
    Unifi_DoUpdate($hash);
    
    return undef;
}
###############################################################################

sub Unifi_Undef($$) {
    my ($hash,$arg) = @_;
    
    RemoveInternalTimer($hash);
    return undef;
}
###############################################################################

sub Unifi_Set($@) {
    my ($hash,@a) = @_;
    return "\"set $hash->{NAME}\" needs at least an argument" if ( @a < 2 );

    my ($name,$setName,$setVal) = @a;

    if (AttrVal($name, "disable", 0)) {
        Log3 $name, 5, "$name: set called with $setName but device is disabled" if ($setName ne "?");
        return undef;
    }
    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "") if ($setName ne "?");

    if($setName !~ /update|clear/) {
        return "Unknown argument $setName, choose one of update:noArg clear:all,readings,clientData";
    } else {
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
                undef $hash->{clients};
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
    
    if($getName !~ /clientDetails/) {
        return "Unknown argument $getName, choose one of clientDetails:noArg";
    } 
    elsif ($getName eq 'clientDetails') {
        my $clientDetails = '';
        for my $client (sort keys %{$hash->{clients}}) {
            for (sort keys %{$hash->{clients}->{$client}}) {
                $clientDetails .= "$_ = $hash->{clients}->{$client}->{$_}\n";
            }
            $clientDetails .= "============================================\n";
        }
        return $clientDetails if($clientDetails ne '');
    }
    return undef;
}
###############################################################################

sub Unifi_DoUpdate($@) {
    my ($hash,$manual) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: DoUpdate - executed.";
    
    if ( $hash->{STATE} ne 'connected' ) {
        Unifi_Login_Send($hash);
    } else {
        Unifi_GetClients_Send($hash);
        if($manual) {
            Log3 $name, 5, "$name: DoUpdate - Manual updated executed.";
        } else {
            InternalTimer(time()+$hash->{interval}, 'Unifi_DoUpdate', $hash, 0);
        }
    }
    return undef;
}
###############################################################################

sub Unifi_Login_Send($) {
    my ($hash) = @_;
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: Login_Send - executed.";
    
    HttpUtils_NonblockingGet($hash->{loginParams});
    return undef;
}
sub Unifi_Login_Receive($) {
    my ($param, $err, $data) = @_;
    my $name = $param->{hash}->{NAME};
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
                
                InternalTimer(time()+$param->{hash}->{interval}, 'Unifi_Login_Send', $param->{hash}, 0);
                return undef;
            };
            Log3 $name, 5, "$name: Login_Receive - state:'$data->{meta}->{rc}'";
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name: Login_Receive - Login successfully!";
                $param->{cookies} = '';
                for (split("\r\n",$param->{httpheader})) {
                    if(/^Set-Cookie/) {
                        s/Set-Cookie:\s(.*?);.*/Cookie: $1/;
                        $param->{cookies} .= $_.'\r\n';
                    }
                }
                Log3 $name, 5, "$name: Login_Receive - Received-cookies:$param->{cookies}";
                readingsSingleUpdate($param->{hash},"state","connected",1);
                
                Unifi_DoUpdate($param->{hash});
                return undef;
            }
            else {
                $param->{cookies} = '';
                if (defined($data->{meta}->{msg})) {
                    my $loglevel = ($data->{meta}->{msg} eq 'api.err.Invalid') ? 1 : 5;
                    Log3 $name, $loglevel, "$name: Login_Receive - Login Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'";
                } else {
                    Log3 $name, 5, "$name: Login_Receive - Login Failed (without message)!";
                }
                readingsSingleUpdate($param->{hash},"state","disconnected",1) if($param->{hash}->{READINGS}->{state}->{VAL} ne "disconnected");
            }
        } else {
            readingsSingleUpdate($param->{hash},"state","disconnected",1) if($param->{hash}->{READINGS}->{state}->{VAL} ne "disconnected");
            Log3 $name, 5, "$name: Login_Receive - Failed with HTTP Code $param->{code}!";
        }
    }
    Log3 $name, 5, "$name: Login_Receive - Connect/Login to Unifi-Controller failed! Will try again after interval...";
    readingsSingleUpdate($param->{hash},"state","disconnected",1) if($param->{hash}->{READINGS}->{state}->{VAL} ne "disconnected");
    InternalTimer(time()+$param->{hash}->{interval}, 'Unifi_Login_Send', $param->{hash}, 0);
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
    my $name = $param->{hash}->{NAME};
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
            Log3 $name, 5, "$name: GetClients_Receive - state:'$data->{meta}->{rc}'";
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name: GetClients_Receive - Data received successfully!";
                
                readingsBeginUpdate($param->{hash});
                my $connectedClientIDs = {};
                my $i = 1;
                for my $h (@{$data->{data}}) {
                    $param->{hash}->{clients}->{$h->{user_id}} = $h;
                    $connectedClientIDs->{$h->{user_id}} = 1;
                    readingsBulkUpdate($param->{hash},$h->{user_id}."_hostname",$h->{hostname});
                    readingsBulkUpdate($param->{hash},$h->{user_id}."_last_seen",strftime "%Y-%m-%d %H:%M:%S",localtime($h->{last_seen}));
                    readingsBulkUpdate($param->{hash},$h->{user_id}."_essid",$h->{essid});
                    readingsBulkUpdate($param->{hash},$h->{user_id}."_ip",$h->{ip});
                    readingsBulkUpdate($param->{hash},$h->{user_id}."_uptime",$h->{uptime});
                    readingsBulkUpdate($param->{hash},$h->{user_id},'connected');
                }
                for my $clientID (keys %{$param->{hash}->{clients}}) {
                    if (!defined($connectedClientIDs->{$clientID}) && $param->{hash}->{READINGS}->{$clientID}->{VAL} ne 'disconnected') {
                        readingsBulkUpdate($param->{hash},$clientID,'disconnected');
                        Log3 $name, 5, "$name: GetClients_Receive - Client '$clientID' previously connected is now disconnected.";
                    }
                }
                readingsEndUpdate($param->{hash},1);
            }
            else {
                if (defined($data->{meta}->{msg})) {
                    Log3 $name, 5, "$name: GetClients_Receive - Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'";
                    if($data->{meta}->{msg} eq 'api.err.LoginRequired') {
                        readingsSingleUpdate($param->{hash},"state","disconnected",1) if($param->{hash}->{READINGS}->{state}->{VAL} ne "disconnected");
                        Log3 $name, 5, "$name: GetClients_Receive - LoginRequired detected. Set state to disconnected...";
                    }
                } else {
                    Log3 $name, 5, "$name: GetClients_Receive - Failed (without message)!";
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
<br><br>

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
    </ul>
</ul>
<h4>Example</h4>
<ul>
    <code>define my_unifi_controller Unifi 192.168.1.15 443 user password</code><br>
</ul>

<h4>Set</h4>
<ul>
    <li><code>set &lt;name&gt; update</code><br>
    Makes immediately a manual update. </li>
</ul><br>
<ul>
    <li><code>set &lt;name&gt; clear &lt;readings|clientData|all&gt</code><br>
    Clears the readings, clientData or both. </li>
</ul>


<h4>Get</h4>
<ul>
    <li><code>get &lt;name&gt; clientDetails</code><br>
    Show more details about each client.</li>
</ul>


<h4>Attributes</h4>
<ul>
    <li>attr <a href="#verbose">verbose</a> 5<br>
    Unifi itself has no attributes, but this attribute will help you if something does not work as espected.</li>
</ul>

<h4>Readings</h4>
<ul>
    <li>Each device has multiple readings.<br></li>
    <li>The unifi-device reading 'state' represents the connections-state to the unifi-controller.</li>
</ul>
<br>

</ul>

=end html
=cut

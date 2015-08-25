###############################################################################
# $Id: 74_Unifi.pm 2015-08-25 20:00 - rapster - rapster at x0e dot de $ 

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
                         ."devAlias "
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
        CONNECTED => $hash->{CONNECTED} || 0,
        url       => "https://".$a[2].(($a[3] != 443) ? ':'.$a[3] : '').'/',
        interval  => $a[6] || 30,
        siteID    => $a[7] || 'default',
        version   => $a[8] || 4,
    );
    $hash->{httpParams} = {
        hash            => $hash,
        timeout         => 5,
        method          => "POST",
        noshutdown      => 0,
        ignoreredirects => 1,
        loglevel        => 5,
        sslargs         => { SSL_verify_mode => 'SSL_VERIFY_NONE' },
        header          => ($hash->{version} == 3) ? undef : "Content-Type: application/json;charset=UTF-8"
    };
    $hash->{loginParams} = {
        %{$hash->{httpParams}},
        cookies  => ($hash->{loginParams}->{cookies}) ? $hash->{loginParams}->{cookies} : '',
        callback => \&Unifi_Login_Receive
    };
    if($hash->{version} == 3) {
        $hash->{loginParams}->{url} = $hash->{url}."login";
        $hash->{loginParams}->{data} = "login=login&username=".Unifi_Urlencode($a[4])."&password=".Unifi_Urlencode($a[5]);
    }else {
        $hash->{loginParams}->{url} = $hash->{url}."api/login";
        $hash->{loginParams}->{data} = "{'username':'".$a[4]."', 'password':'".$a[5]."'}";
    }
    
    # Don't use old cookies when user, pw or url changed
    if($oldLoginData && $oldLoginData ne $hash->{loginParams}->{data}.$hash->{url}) {
        $hash->{loginParams}->{cookies} = '';
        Unifi_CONNECTED($hash,'disconnected');
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
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());

    return if($dev->{NAME} ne "global");
    return if(!grep(m/^DEFINED|MODIFIED|INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

    if(AttrVal($name, "disable", 0)) {
        Log3 $name, 5, "$name ($self) - DEFINED|MODIFIED|INITIALIZED|REREADCFG - Device '$name' is disabled, do nothing...";
        Unifi_CONNECTED($hash,'disabled');
    } else {
        Log3 $name, 5, "$name ($self) - DEFINED|MODIFIED|INITIALIZED|REREADCFG - Remove all Timers & Call DoUpdate...";
        Unifi_CONNECTED($hash,'initialized');
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

    if(!Unifi_CONNECTED($hash) && $setName !~ /clear/) {
        return "Unknown argument $setName, choose one of clear:all,readings,clientData";
    }
    elsif($setName !~ /update|clear/) {
        return "Unknown argument $setName, choose one of update:noArg clear:all,readings,clientData";
    }
    else {
        Log3 $name, 4, "$name: set $setName";
        
        if ($setName eq 'update') {
            RemoveInternalTimer($hash);
            Unifi_DoUpdate($hash,1);
        } 
        elsif ($setName eq 'clear') {
            if ($setVal eq 'readings' || $setVal eq 'all') {
                for (keys %{$hash->{READINGS}}) {
                    delete $hash->{READINGS}->{$_} if($_ ne 'state');
                }
            }
            if ($setVal eq 'clientData' || $setVal eq 'all') {
                %{$hash->{clients}} = ();
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
    
    my $clients = '';
    my $devAliases = AttrVal($name,"devAlias",0);
    if($devAliases) {   # Replace ID's with Aliases
        for (keys %{$hash->{clients}}) {
            $_ = $1 if($devAliases && $devAliases =~ /$_:(.+?)(\s|$)/);
            $clients .= ','.$_;
        }
    }
    
    if($getName !~ /clientData/) {
        return "Unknown argument $getName, choose one of ".(($clients) ? "clientData:all$clients" : "");
    } 
    elsif ($getName eq 'clientData' && $clients) {
        if($getVal && $devAliases) {   # Make ID from Alias
            for (keys %{$hash->{clients}}) {
                $getVal = $_ if($devAliases =~ /$_:$getVal/);
            }
        }
        my $clientData = '';
        if(!$getVal || $getVal eq 'all') {
            $clientData .= "======================================\n";
            for my $client (sort keys %{$hash->{clients}}) {
                for (sort keys %{$hash->{clients}->{$client}}) {
                    $clientData .= "$_ = ".((defined($hash->{clients}->{$client}->{$_})) ? $hash->{clients}->{$client}->{$_} : '')."\n";
                }
                $clientData .= "======================================\n";
            }
            return $clientData;
        } 
        elsif(defined($hash->{clients}->{$getVal})) {
            $clientData .= "======================================\n";
            for (sort keys %{$hash->{clients}->{$getVal}}) {
                $clientData .= "$_ = ".((defined($hash->{clients}->{$getVal}->{$_})) ? $hash->{clients}->{$getVal}->{$_} : '')."\n";
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
                Unifi_CONNECTED($hash,'disabled');
            }
            elsif($attr_value == 0 && Unifi_CONNECTED($hash) eq "disabled") {
                Unifi_CONNECTED($hash,'initialized');
                Unifi_DoUpdate($hash);
            }
        }
    }
    elsif($cmd eq "del") {
        if($attr_name eq "disable" && Unifi_CONNECTED($hash) eq "disabled") {
            Unifi_CONNECTED($hash,'initialized');
            Unifi_DoUpdate($hash);
        }
    }
    return undef;
}
###############################################################################

sub Unifi_DoUpdate($@) {
    my ($hash,$manual) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    if (Unifi_CONNECTED($hash) eq "disabled") {
        Log3 $name, 5, "$name ($self) - Device '$name' is disabled, End now...";
        return undef;
    }
    
    if (Unifi_CONNECTED($hash)) {
        $hash->{updateDispatch} = {  # {updateDispatch}->{callFn}[callFnRef,'receiveFn',receiveFnRef]
            Unifi_GetClients_Send => [\&Unifi_GetClients_Send,'Unifi_GetClients_Receive',\&Unifi_GetClients_Receive],
            Unifi_GetAnother_Send => [\&Unifi_GetAnother_Send,'Unifi_GetAnother_Receive',\&Unifi_GetAnother_Receive],
            Unifi_DoAfterUpdate   => [\&Unifi_DoAfterUpdate,''],
        };
        Unifi_NextUpdateFn($hash,$self);
        InternalTimer(time()+$hash->{interval}, 'Unifi_DoUpdate', $hash, 0);
    }
    else {
        Unifi_CONNECTED($hash,'disconnected');
        Unifi_Login_Send($hash)
    }
    return undef;
}
###############################################################################

sub Unifi_Login_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    HttpUtils_NonblockingGet($hash->{loginParams});
    return undef;
}
sub Unifi_Login_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Log3 $name, 5, "$name ($self) - Error while requesting ".$param->{url}." - $err";
    }
    elsif ($data ne "" && $hash->{version} == 3) {
        if ($data =~ /Invalid username or password/si) {
            Log3 $name, 1, "$name ($self) - Login Failed! Invalid username or password!";
        } else {
            Log3 $name, 5, "$name ($self) - Login Failed! Version 3 should not deliver data on successfull login.";
        }
    }
    elsif ($data ne "" || $hash->{version} == 3) { # v3 Login is empty if login is successfully
        if ($param->{code} == 200 || $param->{code} == 400 || $param->{code} == 401 || ($hash->{version} == 3 && ($param->{code} == 302 || $param->{code} == 200))) {
            if($data ne "") {
                eval {
                    $data = decode_json($data);
                    1;
                } or do {
                    my $e = $@;
                    $data->{meta}->{rc}  = 'error';
                    $data->{meta}->{msg} = 'Unifi.FailedToDecodeJSON - $e';
                };
            }
            if ($hash->{version} == 3 || $data->{meta}->{rc} eq "ok") {  # v3 has no rc-state
                Log3 $name, 5, "$name ($self) - state=ok || version=3";
                $param->{cookies} = '';
                for (split("\r\n",$param->{httpheader})) {
                    if(/^Set-Cookie/) {
                        s/Set-Cookie:\s(.*?);.*/Cookie: $1/;
                        $param->{cookies} .= $_.(($hash->{version} == 3) ? '' : '\r\n'); #v3 has only one cookie and no header at all
                    }
                }
                
                if($param->{cookies} ne '') {
                    Log3 $name, 5, "$name ($self) - Login successfully!  $param->{cookies}";
                    Unifi_CONNECTED($hash,'connected');
                    Unifi_DoUpdate($hash);
                    return undef;
                } else {
                    Log3 $name, 5, "$name ($self) - Something went wrong, login seems ok but no cookies received.";
                }
            }
            else {
                if (defined($data->{meta}->{msg})) {
                    if ($data->{meta}->{msg} eq 'api.err.Invalid') {
                        Log3 $name, 1, "$name ($self) - Login Failed! Invalid username or password!"
                                       ." - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'";
                    } elsif ($data->{meta}->{msg} eq 'api.err.LoginRequired') {
                        Log3 $name, 1, "$name ($self) - Login Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}' -"
                                       ." This error while login indicates that you use wrong <version> or"
                                       ." have to define <version> in your fhem definition.";
                    } else {
                        Log3 $name, 5, "$name ($self) - Login Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'";
                    }
                } else {
                    Log3 $name, 5, "$name ($self) - Login Failed (without message)! - state:'$data->{meta}->{rc}'";
                }
                $param->{cookies} = '';
            }
        } else {
            Log3 $name, 5, "$name ($self) - Failed with HTTP Code $param->{code}!";
        }
    } else {
        Log3 $name, 5, "$name ($self) - Failed because no data was received!";
    }
    Log3 $name, 5, "$name ($self) - Connect/Login to Unifi-Controller failed. Will try again after interval...";
    Unifi_CONNECTED($hash,'disconnected');
    InternalTimer(time()+$hash->{interval}, 'Unifi_Login_Send', $hash, 0);
    return undef;
}
###############################################################################

sub Unifi_GetClients_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    my $param = {
        %{$hash->{httpParams}},
        url      => $hash->{url}."api/s/$hash->{siteID}/stat/sta",
        header   => ($hash->{version} == 3) ? $hash->{loginParams}->{cookies} : $hash->{loginParams}->{cookies}.$hash->{httpParams}->{header},
        callback => $hash->{updateDispatch}->{$self}[2]
    };
    HttpUtils_NonblockingGet($param);
    return undef;
}
sub Unifi_GetClients_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Log3 $name, 5, "$name ($self) - Error while requesting ".$param->{url}." - $err";
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
            eval {
                $data = decode_json($data);
                1;
            } or do {
                my $e = $@;
                $data->{meta}->{rc}  = 'error';
                $data->{meta}->{msg} = 'Unifi.FailedToDecodeJSON - $e';
            };
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name ($self) - state:'$data->{meta}->{rc}'";
                
                readingsBeginUpdate($hash);
                my $devAliases = AttrVal($name,"devAlias",0);
                my $connectedClientIDs = {};
                my $i = 1;
                my $clientName;
                for my $h (@{$data->{data}}) {
                    $clientName = $h->{user_id};
                    $clientName = $1 if $devAliases =~ /$clientName:(.+?)(\s|$)/;
                    $hash->{clients}->{$h->{user_id}} = $h;
                    $connectedClientIDs->{$h->{user_id}} = 1;
                    readingsBulkUpdate($hash,$clientName."_hostname",($h->{hostname}) ? $h->{hostname} : ($h->{ip}) ? $h->{ip} : 'Unknown');
                    readingsBulkUpdate($hash,$clientName."_last_seen",strftime "%Y-%m-%d %H:%M:%S",localtime($h->{last_seen}));
                    readingsBulkUpdate($hash,$clientName."_uptime",$h->{uptime});
                    readingsBulkUpdate($hash,$clientName,'connected');
                }
                for my $clientID (keys %{$hash->{clients}}) {
                    if (!defined($connectedClientIDs->{$clientID}) && $hash->{READINGS}->{$clientID}->{VAL} ne 'disconnected') {
                        Log3 $name, 5, "$name ($self) - Client '$clientID' previously connected is now disconnected.";
                        $clientID = $1 if $devAliases =~ /$clientID:(.+?)(\s|$)/;
                        readingsBulkUpdate($hash,$clientID,'disconnected') if($hash->{READINGS}->{$clientID}->{VAL} ne 'disconnected');
                    }
                }
                readingsEndUpdate($hash,1);
            }
            else {
                if (defined($data->{meta}->{msg})) {
                    if ($data->{meta}->{msg} eq 'api.err.LoginRequired') {
                        Log3 $name, 5, "$name ($self) - LoginRequired detected...";
                        if(Unifi_CONNECTED($hash)) {
                            Log3 $name, 5, "$name ($self) - I am the first who detected LoginRequired. Do re-login...";
                            Unifi_CONNECTED($hash,'disconnected');
                            Unifi_DoUpdate($hash);
                            return undef;
                        }
                    }
                    elsif ($data->{meta}->{msg} eq "api.err.NoSiteContext" || ($hash->{version} == 3 && $data->{meta}->{msg} eq "api.err.InvalidObject")) {
                        Log3 $name, 1, "$name ($self) - Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'"
                                       ." - This error indicates that the <siteID> in your definition is wrong."
                                       ." Try to modify your definition with <sideID> = default.";
                    }
                    else {
                        Log3 $name, 5, "$name ($self) - Failed! - state:'$data->{meta}->{rc}' - msg:'$data->{meta}->{msg}'";
                    }
                } else {
                    Log3 $name, 5, "$name ($self) - Failed (without message)! - state:'$data->{meta}->{rc}'";
                }
            }
        }
        else {
            Log3 $name, 5, "$name ($self) - Failed with HTTP Code $param->{code}.";
        }
    }
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################

sub Unifi_GetAnother_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    $hash->{updateDispatch}->{$self}[2]->( {hash => $hash} ); # DUMMY
    #HttpUtils_NonblockingGet($param);
    return undef;
}
sub Unifi_GetAnother_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $hash->{NAME}, 5, "$hash->{NAME} ($self) - executed.";
    
    # Do   
    
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################

sub Unifi_DoAfterUpdate($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    return undef;
}
###############################################################################

sub Unifi_NextUpdateFn($$) {
    my ($hash,$fn) = @_;
    
    my $NextUpdateFn = 0;
    for (keys %{$hash->{updateDispatch}}) {   # {updateDispatch}->{callFn}[callFnRef,'receiveFn',receiveFnRef]
        if($hash->{updateDispatch}->{$_}[1] && $hash->{updateDispatch}->{$_}[1] eq $fn) {
            delete $hash->{updateDispatch}->{$_};
        } elsif(!$NextUpdateFn && $hash->{updateDispatch}->{$_}[0] && $_ ne 'Unifi_DoAfterUpdate') {
            $NextUpdateFn = $hash->{updateDispatch}->{$_}[0];
        }
    }
    if (!$NextUpdateFn && $hash->{updateDispatch}->{Unifi_DoAfterUpdate}[0]) {
        $NextUpdateFn = $hash->{updateDispatch}->{Unifi_DoAfterUpdate}[0];
        delete $hash->{updateDispatch}->{Unifi_DoAfterUpdate};
    }
    $NextUpdateFn->($hash) if($NextUpdateFn);
    return undef;
}
###############################################################################

sub Unifi_CONNECTED($@) {
    my ($hash,$set) = @_;
    
    if ($set) {
        $hash->{CONNECTED} = $set;
        RemoveInternalTimer($hash);
        %{$hash->{updateDispatch}} = ();
        if ($hash->{READINGS}->{state}->{VAL} ne $set) {
            readingsSingleUpdate($hash,"state",$set,1);
        }
        return undef;
    } 
    else {
        if ($hash->{CONNECTED} eq 'disabled') {
            return 'disabled';
        }
        elsif ($hash->{CONNECTED} eq 'connected') {
            return 1;
        } else {
            return 0;
        }
    }
}
###############################################################################

sub Unifi_Urlencode($) {
    my ($s) = @_;
    $s =~ s/ /+/g;
    $s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
    return $s;
}
sub Unifi_Urldecode($) {
    my ($s) = @_;
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
    $s =~ s/\+/ /g;
    return $s;
}
sub Unifi_Whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }
###############################################################################

### KNOWN RESPONSES ###
# { "data" : [ ] , "meta" : { "msg" : "api.err.Invalid" , "rc" : "error"}}         //Invalid Login credentials in v4, in v3 the login-html-page is returned
# { "data" : [ ] , "meta" : { "rc" : "ok"}}
# { "data" : [ ] , "meta" : { "msg" : "api.err.InvalidObject" , "rc" : "error"}}   //Wrong siteID in v3
# { "data" : [ ] , "meta" : { "msg" : "api.err.NoSiteContext" , "rc" : "error"}}   //Wrong siteID in v4
# { "data" : [ ] , "meta" : { "msg" : "api.err.LoginRequired" , "rc" : "error"}}   //Login Required / cookie is invalid / Unifi v4 is used wiith controller v3
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
    <code>(optional without &lt;siteID&gt; and &lt;version&gt;)<br>
          Interval to fetch the information from the unifi-api. <br>
          default: 30 seconds</code><br>
    </ul>
    [&lt;siteID&gt;]:
    <ul>
    <code>(optional without &lt;version&gt;)<br>
          You can find the site-ID by selecting the site in the UniFi web interface.<br>
          e.g. https://192.168.12.13:8443/manage/s/foobar the siteId you must use is: foobar.<br>
          default: default</code><br>
    </ul>
    [&lt;version&gt;]:
    <ul>
    <code>(optional if you use unifi v4)<br>
           Unifi-controller version. <br>
          Version must be specified if version is not 4. At the moment version 3 and 4 are supported.<br>
          default: 4</code><br>
    </ul> <br>

</ul>
<h4>Examples</h4>
<ul>
    <code>define my_unifi_controller Unifi 192.168.1.15 443 admin secret</code><br>
    <br>
    Or with optional parameters &lt;interval&gt;, &lt;siteID&gt; and &lt;version&gt;:<br>
    <code>define my_unifi_controller Unifi 192.168.1.15 443 admin secret 30 default 3</code><br>
</ul>

<h4>Set</h4>
<ul>
    <li><code>set &lt;name&gt; update</code><br>
    Makes immediately a manual update. </li>
</ul><br>
<ul>
    <li><code>set &lt;name&gt; clear &lt;readings|clientData|all&gt</code><br>
    Clears the readings, clientData or all. </li>
</ul>


<h4>Get</h4>
<ul>
    <li><code>get &lt;name&gt; clientData &lt;all|devAlias|clientID&gt</code><br>
    Show more details about clients.</li>
</ul>


<h4>Attributes</h4>
<ul>
    <li>attr devAlias<br>
    Can be used to rename device names in the format DEVICEUUID:Aliasname.<br>
    Separate using blank to rename multiple devices.<br>
    Example:<code> attr unifi devAlias 5537d138e4b033c1832c5c84:iPhone-Claudiu</code></li>
    <br>
    <li>attr disable &lt;1|0&gt;<br>
    With this attribute you can disable the whole module. <br>
    If set to 1 the module will be stopped and no updates are performed.<br>
    If set to 0 the automatic updating will performed.</li>
    <br>
    <li>attr <a href="#verbose">verbose</a> 5<br>
    This attribute will help you if something does not work as espected.</li>
    <br>
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

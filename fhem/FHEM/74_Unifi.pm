###############################################################################
# $Id: 74_Unifi.pm 2015-08-29 21:00 - rapster - rapster at x0e dot de $ 

package main;
use strict;
use warnings;
use HttpUtils;
use POSIX;
use JSON qw(decode_json);
###############################################################################

sub Unifi_Initialize($$) { 
    my ($hash) = @_; 
    $hash->{DefFn}     = "Unifi_Define";
    $hash->{UndefFn}   = "Unifi_Undef";
    $hash->{SetFn}     = "Unifi_Set";
    $hash->{GetFn}     = "Unifi_Get";
    $hash->{AttrFn}    = 'Unifi_Attr';
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
    return "Wrong syntax: <interval> too small, must be at least 5"          if($a[6] && $a[6] < 5);
    return "Wrong syntax: <version> is not a valid number! Must be 3 or 4."  if($a[8] && (!looks_like_number($a[8]) || $a[8] !~ /3|4/));
    
    my $name = $a[0];
    %$hash = (   %$hash,
        NOTIFYDEV => 'global',
        unifi     => { 
            CONNECTED => 0,
            interval  => $a[6] || 30,
            version   => $a[8] || 4,
            url       => "https://".$a[2].(($a[3] == 443) ? '' : ':'.$a[3]).'/api/s/'.(($a[7]) ? $a[7] : 'default').'/',
        },
    );
    $hash->{httpParams} = {
        hash            => $hash,
        timeout         => 4,
        method          => "POST",
        noshutdown      => 0,
        ignoreredirects => 1,
        loglevel        => 5,
        sslargs         => { SSL_verify_mode => 'SSL_VERIFY_NONE' },
    };
    if($hash->{unifi}->{version} == 3) {
        ( $hash->{httpParams}->{loginUrl} = $hash->{unifi}->{url} ) =~ s/api\/s.+/login/;
        $hash->{httpParams}->{loginData} = "login=login&username=".$a[4]."&password=".$a[5];
    }else {
        ( $hash->{httpParams}->{loginUrl} = $hash->{unifi}->{url} ) =~ s/api\/s.+/api\/login/;
        $hash->{httpParams}->{loginData} = '{"username":"'.$a[4].'", "password":"'.$a[5].'"}';
    }
    
    Log3 $name, 5, "$name: Defined with url:$hash->{unifi}->{url}, interval:$hash->{unifi}->{interval}, version:$hash->{unifi}->{version}";
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

    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "") if ($setName ne "?");

    if(Unifi_CONNECTED($hash) eq 'disabled' && $setName !~ /clear/) {
        return "Unknown argument $setName, choose one of clear:all,readings,clientData";
        Log3 $name, 5, "$name: set called with $setName but device is disabled!" if($setName ne "?");
        return undef;
    }
    
    if($setName !~ /update|clear/) {
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
    for (keys %{$hash->{clients}}) {  # Replace ID's with Aliases
        if (   ($devAliases && $devAliases =~ /$_:(.+?)(\s|$)/)
            || ($devAliases && defined $hash->{clients}->{$_}->{name} && $devAliases =~ /$hash->{clients}->{$_}->{name}:(.+?)(\s|$)/)
            || ($devAliases && defined $hash->{clients}->{$_}->{hostname} && $devAliases =~ /$hash->{clients}->{$_}->{hostname}:(.+?)(\s|$)/)
            || (defined $hash->{clients}->{$_}->{name} && $hash->{clients}->{$_}->{name} =~ /^([\w\.\-]+)$/) 
            || (defined $hash->{clients}->{$_}->{hostname} && $hash->{clients}->{$_}->{hostname} =~ /^([\w\.\-]+)$/)
           ) { 
            $_ = $1; 
        }
        $clients .= ','.$_;
    }
    
    if($getName !~ /clientData/) {
        return "Unknown argument $getName, choose one of ".(($clients) ? "clientData:all$clients" : "");
    } 
    elsif ($getName eq 'clientData' && $clients) {
        if($getVal && $getVal ne 'all') {   # Make ID from Alias
            for (keys %{$hash->{clients}}) {
                if (   ($devAliases && $devAliases =~ /$_:$getVal/)
                    || ($devAliases && defined $hash->{clients}->{$_}->{name} && $devAliases =~ /$hash->{clients}->{$_}->{name}:$getVal/)
                    || ($devAliases && defined $hash->{clients}->{$_}->{hostname} && $devAliases =~ /$hash->{clients}->{$_}->{hostname}:$getVal/)
                    || (defined $hash->{clients}->{$_}->{name} && $hash->{clients}->{$_}->{name} eq $getVal) 
                    || (defined $hash->{clients}->{$_}->{hostname} && $hash->{clients}->{$_}->{hostname} eq $getVal)
                   ) { 
                    $getVal = $_;
                    last;
                }
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
            return "$hash->{NAME}: Unknown client '$getVal' in command '$getName', choose one of: all$clients";
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
        elsif($attr_name eq "devAlias") {
            if (!$attr_value) {
                CommandDeleteAttr(undef, $name.' '.$attr_name);
                return 1;
            }
            elsif ($attr_value !~ /^([\w\.\-]+:[\w\.\-]+\s?)+$/) {
                return "$name: Value \"$attr_value\" is not allowed for devAlias!\n"
                       ."Must be \"<ID>:<ALIAS> <ID2>:<ALIAS2>\", e.g. 123abc:MyIphone\n"
                       ."Only these characters are allowed: [alphanumeric - _ .]";
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
        $hash->{unifi}->{updateStartTime} = time();
        $hash->{updateDispatch} = {  # {updateDispatch}->{callFn}[callFnRef,'receiveFn',receiveFnRef]
            Unifi_GetClients_Send => [\&Unifi_GetClients_Send,'Unifi_GetClients_Receive',\&Unifi_GetClients_Receive],
            Unifi_GetAccesspoints_Send => [\&Unifi_GetAccesspoints_Send,'Unifi_GetAccesspoints_Receive',\&Unifi_GetAccesspoints_Receive],
            Unifi_GetWlans_Send => [\&Unifi_GetWlans_Send,'Unifi_GetWlans_Receive',\&Unifi_GetWlans_Receive],
            Unifi_GetUnarchivedAlerts_Send => [\&Unifi_GetUnarchivedAlerts_Send,'Unifi_GetUnarchivedAlerts_Receive',\&Unifi_GetUnarchivedAlerts_Receive],
            Unifi_GetEvents_Send => [\&Unifi_GetEvents_Send,'Unifi_GetEvents_Receive',\&Unifi_GetEvents_Receive],
            Unifi_GetWlanGroups_Send => [\&Unifi_GetWlanGroups_Send,'Unifi_GetWlanGroups_Receive',\&Unifi_GetWlanGroups_Receive],
            Unifi_ProcessUpdate   => [\&Unifi_ProcessUpdate,''],
        };
        Unifi_NextUpdateFn($hash,$self);
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
    
    HttpUtils_NonblockingGet( {
                 %{$hash->{httpParams}},
        url      => $hash->{httpParams}->{loginUrl},
        data     => $hash->{httpParams}->{loginData},
        callback => \&Unifi_Login_Receive
    } );
    return undef;
}
sub Unifi_Login_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Log3 $name, 5, "$name ($self) - Error while requesting ".$param->{url}." - $err";
    }
    elsif ($data ne "" && $hash->{unifi}->{version} == 3) {
        if ($data =~ /Invalid username or password/si) {
            Log3 $name, 1, "$name ($self) - Login Failed! Invalid username or password!";
        } else {
            Log3 $name, 5, "$name ($self) - Login Failed! Version 3 should not deliver data on successfull login.";
        }
    }
    elsif ($data ne "" || $hash->{unifi}->{version} == 3) { # v3 Login is empty if login is successfully
        if ($param->{code} == 200 || $param->{code} == 400 || $param->{code} == 401 || ($hash->{unifi}->{version} == 3 && ($param->{code} == 302 || $param->{code} == 200))) {
            eval { $data = decode_json($data); 1; } or do { $data = { meta => {rc => 'error.decode_json', msg => $@} }; };
            
            if ($hash->{unifi}->{version} == 3 || $data->{meta}->{rc} eq "ok") {  # v3 has no rc-state
                Log3 $name, 5, "$name ($self) - state=ok || version=3";
                $hash->{httpParams}->{header} = '';
                for (split("\r\n",$param->{httpheader})) {
                    if(/^Set-Cookie/) {
                        s/Set-Cookie:\s(.*?);.*/Cookie: $1/;
                        $hash->{httpParams}->{header} .= $_.'\r\n';
                    }
                }
                if($hash->{httpParams}->{header} ne '') {
                    $hash->{httpParams}->{header} =~ s/\\r\\n$//;
                    Log3 $name, 5, "$name ($self) - Login successfully!  $hash->{httpParams}->{header}";
                    Unifi_CONNECTED($hash,'connected');
                    Unifi_DoUpdate($hash);
                    return undef;
                } else {
                    $hash->{httpParams}->{header} = undef;
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
                    Log3 $name, 5, "$name ($self) - Login Failed (without msg)! - state:'$data->{meta}->{rc}'";
                }
                $hash->{httpParams}->{header} = undef;
            }
        } else {
            Log3 $name, 5, "$name ($self) - Failed with HTTP Code $param->{code}!";
        }
    } else {
        Log3 $name, 5, "$name ($self) - Failed because no data was received!";
    }
    Log3 $name, 5, "$name ($self) - Connect/Login to Unifi-Controller failed. Will try again after interval...";
    Unifi_CONNECTED($hash,'disconnected');
    InternalTimer(time()+$hash->{unifi}->{interval}, 'Unifi_Login_Send', $hash, 0);
    return undef;
}
###############################################################################

sub Unifi_GetClients_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    HttpUtils_NonblockingGet( {
                 %{$hash->{httpParams}},
        url      => $hash->{unifi}->{url}."stat/sta",
        callback => $hash->{updateDispatch}->{$self}[2]
    } );
    return undef;
}
sub Unifi_GetClients_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Unifi_ReceiveFailure($hash,{rc => 'Error while requesting', msg => $param->{url}." - $err"});
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
            eval { $data = decode_json($data); 1; } or do { $data = { meta => {rc => 'error.decode_json', msg => $@} }; };
            
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name ($self) - state:'$data->{meta}->{rc}'";
                
                $hash->{unifi}->{connectedClients} = undef;
                for my $h (@{$data->{data}}) {
                    $hash->{unifi}->{connectedClients}->{$h->{_id}} = 1;
                    $hash->{clients}->{$h->{_id}} = $h;
                }
            }
            else { Unifi_ReceiveFailure($hash,$data->{meta}); }
        } else {
            Unifi_ReceiveFailure($hash,{rc => $param->{code}, msg => "Failed with HTTP Code $param->{code}."});
        }
    }
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################
sub Unifi_GetWlans_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    HttpUtils_NonblockingGet( {
                 %{$hash->{httpParams}},
        url      => $hash->{unifi}->{url}."list/wlanconf",
        callback => $hash->{updateDispatch}->{$self}[2],
    } );
    return undef;
}
sub Unifi_GetWlans_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Unifi_ReceiveFailure($hash,{rc => 'Error while requesting', msg => $param->{url}." - $err"});
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
            eval { $data = decode_json($data); 1; } or do { $data = { meta => {rc => 'error.decode_json', msg => $@} }; };
            
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name ($self) - state:'$data->{meta}->{rc}'";
                
                for my $h (@{$data->{data}}) {
                    $hash->{wlans}->{$h->{_id}} = $h;
                    $hash->{wlans}->{$h->{_id}}->{x_passphrase} = '***'; # Don't show passphrase in list
                }
            }
            else { Unifi_ReceiveFailure($hash,$data->{meta}); }
        } else {
            Unifi_ReceiveFailure($hash,{rc => $param->{code}, msg => "Failed with HTTP Code $param->{code}."});
        }
    }
    
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################
sub Unifi_GetWlanGroups_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    HttpUtils_NonblockingGet( {
                 %{$hash->{httpParams}},
        url      => $hash->{unifi}->{url}."list/wlangroup",
        callback => $hash->{updateDispatch}->{$self}[2],
    } );
    return undef;
}
sub Unifi_GetWlanGroups_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Unifi_ReceiveFailure($hash,{rc => 'Error while requesting', msg => $param->{url}." - $err"});
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
            eval { $data = decode_json($data); 1; } or do { $data = { meta => {rc => 'error.decode_json', msg => $@} }; };
            
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name ($self) - state:'$data->{meta}->{rc}'";
                
                for my $h (@{$data->{data}}) {
                    $hash->{wlangroups}->{$h->{_id}} = $h;
                }
            }
            else { Unifi_ReceiveFailure($hash,$data->{meta}); }
        } else {
            Unifi_ReceiveFailure($hash,{rc => $param->{code}, msg => "Failed with HTTP Code $param->{code}."});
        }
    }
    
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################
sub Unifi_GetUnarchivedAlerts_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    HttpUtils_NonblockingGet( {
                 %{$hash->{httpParams}},
        url      => $hash->{unifi}->{url}."list/alarm",
        callback => $hash->{updateDispatch}->{$self}[2],
        data     => "{'_sort': '-time', 'archived': False}",
    } );
    return undef;
}
sub Unifi_GetUnarchivedAlerts_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Unifi_ReceiveFailure($hash,{rc => 'Error while requesting', msg => $param->{url}." - $err"});
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
            eval { $data = decode_json($data); 1; } or do { $data = { meta => {rc => 'error.decode_json', msg => $@} }; };
            
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name ($self) - state:'$data->{meta}->{rc}'";
                
                for my $h (@{$data->{data}}) {
                    $hash->{alerts_unarchived}->{$h->{_id}} = $h;
                }
            }
            else { Unifi_ReceiveFailure($hash,$data->{meta}); }
        } else {
            Unifi_ReceiveFailure($hash,{rc => $param->{code}, msg => "Failed with HTTP Code $param->{code}."});
        }
    }
    
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################
sub Unifi_GetEvents_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    HttpUtils_NonblockingGet( {
                 %{$hash->{httpParams}},
        url      => $hash->{unifi}->{url}."stat/event",
        callback => $hash->{updateDispatch}->{$self}[2],
        data     => "{'within': 24}",    # last 24 hours
    } );
    return undef;
}
sub Unifi_GetEvents_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Unifi_ReceiveFailure($hash,{rc => 'Error while requesting', msg => $param->{url}." - $err"});
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
            eval { $data = decode_json($data); 1; } or do { $data = { meta => {rc => 'error.decode_json', msg => $@} }; };
            
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name ($self) - state:'$data->{meta}->{rc}'";
                
                for my $h (@{$data->{data}}) {
                    $hash->{events}->{$h->{_id}} = $h;
                }
            }
            else { Unifi_ReceiveFailure($hash,$data->{meta}); }
        } else {
            Unifi_ReceiveFailure($hash,{rc => $param->{code}, msg => "Failed with HTTP Code $param->{code}."});
        }
    }
    
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################
sub Unifi_GetAccesspoints_Send($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
    
    HttpUtils_NonblockingGet( {
                 %{$hash->{httpParams}},
        url      => $hash->{unifi}->{url}."stat/device",
        callback => $hash->{updateDispatch}->{$self}[2],
        data     => "{'_depth': 2, 'test': 0}",
    } );
    return undef;
}
sub Unifi_GetAccesspoints_Receive($) {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Unifi_Whoami(),$param->{hash});
    Log3 $name, 5, "$name ($self) - executed.";
    
    if ($err ne "") {
        Unifi_ReceiveFailure($hash,{rc => 'Error while requesting', msg => $param->{url}." - $err"});
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
            eval { $data = decode_json($data); 1; } or do { $data = { meta => {rc => 'error.decode_json', msg => $@} }; };
            
            if ($data->{meta}->{rc} eq "ok") {
                Log3 $name, 5, "$name ($self) - state:'$data->{meta}->{rc}'";
                
                for my $h (@{$data->{data}}) {
                    $hash->{accespoints}->{$h->{_id}} = $h;
                }
            }
            else { Unifi_ReceiveFailure($hash,$data->{meta}); }
        } else {
            Unifi_ReceiveFailure($hash,{rc => $param->{code}, msg => "Failed with HTTP Code $param->{code}."});
        }
    }
    
    Unifi_NextUpdateFn($hash,$self);
    return undef;
}
###############################################################################

sub Unifi_ProcessUpdate($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed after ".sprintf('%.4f',time() - $hash->{unifi}->{updateStartTime})." seconds.";
    
    readingsBeginUpdate($hash);
    #'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''#
    
    ### WLAN Client Readings
    my ($clientName,$clientRef);
    my $devAliases = AttrVal($name,"devAlias",0);
    for my $clientID (keys %{$hash->{clients}}) {
        $clientRef = $hash->{clients}->{$clientID};
        
        if (   ($devAliases && $devAliases =~ /$clientID:(.+?)(\s|$)/)
            || ($devAliases && defined $clientRef->{name} && $devAliases =~ /$clientRef->{name}:(.+?)(\s|$)/)
            || ($devAliases && defined $clientRef->{hostname} && $devAliases =~ /$clientRef->{hostname}:(.+?)(\s|$)/)
            || (defined $clientRef->{name} && $clientRef->{name} =~ /^([\w\.\-]+)$/) 
            || (defined $clientRef->{hostname} && $clientRef->{hostname} =~ /^([\w\.\-]+)$/)
           ) {
            $clientName = $1;
        } else { $clientName = $clientID; }
        
        if (defined $hash->{unifi}->{connectedClients}->{$clientID}) {
            readingsBulkUpdate($hash,$clientName."_hostname",(defined $clientRef->{hostname}) ? $clientRef->{hostname} : (defined $clientRef->{ip}) ? $clientRef->{ip} : 'Unknown');
            readingsBulkUpdate($hash,$clientName."_last_seen",strftime "%Y-%m-%d %H:%M:%S",localtime($clientRef->{last_seen}));
            readingsBulkUpdate($hash,$clientName."_uptime",$clientRef->{uptime});
            readingsBulkUpdate($hash,$clientName,'connected');
        }
        elsif (defined($hash->{READINGS}->{$clientName}) && $hash->{READINGS}->{$clientName}->{VAL} ne 'disconnected') {
            Log3 $name, 5, "$name ($self) - Client '$clientName' previously connected is now disconnected.";
            readingsBulkUpdate($hash,$clientName,'disconnected');
        }
    }
    ### Other...
    
    #'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''#
    readingsEndUpdate($hash,1);
    
    Log3 $name, 5, "$name ($self) - finished after ".sprintf('%.4f',time() - $hash->{unifi}->{updateStartTime})." seconds.";
    InternalTimer(time()+$hash->{unifi}->{interval}, 'Unifi_DoUpdate', $hash, 0);
    
    return undef;
}
###############################################################################

sub Unifi_NextUpdateFn($$) {
    my ($hash,$fn) = @_;
    
    my $NextUpdateFn = 0;
    for (keys %{$hash->{updateDispatch}}) {   # {updateDispatch}->{callFn}[callFnRef,'receiveFn',receiveFnRef]
        if($hash->{updateDispatch}->{$_}[1] && $hash->{updateDispatch}->{$_}[1] eq $fn) {
            delete $hash->{updateDispatch}->{$_};
        } elsif(!$NextUpdateFn && $hash->{updateDispatch}->{$_}[0] && $_ ne 'Unifi_ProcessUpdate') {
            $NextUpdateFn = $hash->{updateDispatch}->{$_}[0];
        }
    }
    if (!$NextUpdateFn && $hash->{updateDispatch}->{Unifi_ProcessUpdate}[0]) {
        $NextUpdateFn = $hash->{updateDispatch}->{Unifi_ProcessUpdate}[0];
        delete $hash->{updateDispatch}->{Unifi_ProcessUpdate};
    }
    $NextUpdateFn->($hash) if($NextUpdateFn);
    return undef;
}
###############################################################################

sub Unifi_ReceiveFailure($$$) {
    my ($hash,$meta) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whowasi());
    
    if (defined $meta->{msg}) {
        if ($meta->{msg} eq 'api.err.LoginRequired') {
            Log3 $name, 5, "$name ($self) - LoginRequired detected...";
            if(Unifi_CONNECTED($hash)) {
                Log3 $name, 5, "$name ($self) - I am the first who detected LoginRequired. Do re-login...";
                Unifi_CONNECTED($hash,'disconnected');
                Unifi_DoUpdate($hash);
                return undef;
            }
        }
        elsif ($meta->{msg} eq "api.err.NoSiteContext" || ($hash->{unifi}->{version} == 3 && $meta->{msg} eq "api.err.InvalidObject")) {
            Log3 $name, 1, "$name ($self) - Failed! - state:'$meta->{rc}' - msg:'$meta->{msg}'"
                           ." - This error indicates that the <siteID> in your definition is wrong."
                           ." Try to modify your definition with <sideID> = default.";
        }
        else {
            Log3 $name, 5, "$name ($self) - Failed! - state:'$meta->{rc}' - msg:'$meta->{msg}'";
        }
    } else {
        Log3 $name, 5, "$name ($self) - Failed (without message)! - state:'$meta->{rc}'";
    }
}
###############################################################################

sub Unifi_CONNECTED($@) {
    my ($hash,$set) = @_;
    
    if ($set) {
        $hash->{unifi}->{CONNECTED} = $set;
        RemoveInternalTimer($hash);
        %{$hash->{updateDispatch}} = ();
        if (!defined($hash->{READINGS}->{state}->{VAL}) || $hash->{READINGS}->{state}->{VAL} ne $set) {
            readingsSingleUpdate($hash,"state",$set,1);
        }
        return undef;
    } 
    else {
        if ($hash->{unifi}->{CONNECTED} eq 'disabled') {
            return 'disabled';
        }
        elsif ($hash->{unifi}->{CONNECTED} eq 'connected') {
            return 1;
        } else {
            return 0;
        }
    }
}
###############################################################################

sub Unifi_Whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }
sub Unifi_Whowasi() { return (split('::',(caller(2))[3]))[1] || ''; }
###############################################################################

### KNOWN RESPONSES ###
# { "data" : [ ] , "meta" : { "msg" : "api.err.Invalid" , "rc" : "error"}}         //Invalid Login credentials in v4, in v3 the login-html-page is returned
# { "data" : [ ] , "meta" : { "rc" : "ok"}}
# "api.err.NoPermission"
# { "data" : [ ] , "meta" : { "msg" : "api.err.InvalidArgs" , "rc" : "error"}}     //posted data is not ok
# { "data" : [ ] , "meta" : { "msg" : "api.err.InvalidObject" , "rc" : "error"}}   //Wrong siteID in v3
# { "data" : [ ] , "meta" : { "msg" : "api.err.NoSiteContext" , "rc" : "error"}}   //Wrong siteID in v4
# { "data" : [ ] , "meta" : { "msg" : "api.err.LoginRequired" , "rc" : "error"}}   //Login Required / cookie is invalid / While Login: Unifi v4 is used wiith controller v3
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
    <li><code>get &lt;name&gt; clientData &lt;all|_id|controllerAlias|hostname|devAlias&gt;</code><br>
    Show more details about clients.</li>
</ul>


<h4>Attributes</h4>
<ul>
    <li>attr devAlias<br>
    Can be used to rename device names in the format <code>&lt;_id|controllerAlias|hostname&gt;:Aliasname.</code><br>
    Separate using blank to rename multiple devices.<br>
    Example (_id):<code> attr unifi devAlias 5537d138e4b033c1832c5c84:iPhone-Claudiu</code><br>
    Example (controllerAlias):<code> attr unifi devAlias iPhoneControllerAlias:iPhone-Claudiu</code><br>
    Example (hostname):<code> attr unifi devAlias iphone:iPhone-Claudiu</code><br></li>
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

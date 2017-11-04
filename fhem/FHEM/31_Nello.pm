##############################################################################
# $Id$
#
#  31_Nello.pm
#
#  2017 Oskar Neumann
#  oskar.neumann@me.com
#
##############################################################################

# required packets
# Net::MQTT
# libcpan-meta-yaml-perl

package main;

use strict;
use warnings;

use JSON;

use Date::Parse;


sub Nello_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = 'Nello_Define';
    $hash->{NotifyFn} = 'Nello_Notify';
    $hash->{UndefFn}  = 'Nello_Undefine';
    $hash->{SetFn}    = 'Nello_Set';
    $hash->{GetFn}    = 'Nello_Get';
    $hash->{AttrFn}   = "Nello_Attr";
    $hash->{AttrList} = 'updateInterval disable:0,1 deviceID ';
    $hash->{AttrList} .= $readingFnAttributes;
    $hash->{NOTIFYDEV} = "global";
}

sub Nello_Define($) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my @a = split("[ \t][ \t]*", $def);

    Nello_loadInternals($hash) if($init_done);

    return undef;
}

sub Nello_Undefine($$) {                     
    my ($hash, $name) = @_;               
    RemoveInternalTimer($hash);    
    return undef;
}

sub Nello_Notify($$) {
    my ($own_hash, $dev_hash) = @_;
    my $ownName = $own_hash->{NAME}; # own name / hash
   
    return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
   
    my $devName = $dev_hash->{NAME}; # Device that created the events
    my $events = deviceEvents($dev_hash, 1);

    if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
        Nello_loadInternals($own_hash);
    }

    my $deviceID = $attr{$ownName}{deviceID};
    if (defined $deviceID && $devName eq 'Nello_Events') {
        my $events = deviceEvents( $dev_hash, 1 );
        return "" unless ($events);

        foreach ( @{$events} ) {
            if(my ($action) = $_ =~ m/${deviceID}_(door|ring|tw):.*/) {
                if($action eq 'ring') {
                    $own_hash->{helper}{last_ring} = time();
                    Log3 "Nello", 3, $ownName . " ring";
                    readingsSingleUpdate($own_hash, 'last_ring', time(), 1);
                }

                if($action eq 'door' && (!defined $own_hash->{helper}{last_opened} || time() - $own_hash->{helper}{last_opened} > 3)) {
                    Log3 "Nello", 3, $ownName. " opened";
                    readingsSingleUpdate($own_hash, 'last_user_open', time(), 1);
                    readingsSingleUpdate($own_hash, 'last_open', time(), 1);
                }

                InternalTimer(gettimeofday()+1, "Nello_updateActivities", $own_hash);
                InternalTimer(gettimeofday()+2, "Nello_updateActivities", $own_hash);
            }
        }
    }
}

sub Nello_Set($$@) {
    my ($hash, $name, $cmd, @args) = @_;

    return "\"set $name\" needs at least one argument" unless(defined($cmd));

    my $list = '';

    if(!defined $hash->{helper}{session}) {
        $list .= ' login recoverPassword';
    } else {
        $list .= ' open:noArg update:noArg detectDeviceID:noArg';
    }

    return Nello_login($hash, $args[0], $args[1]) if($cmd eq 'login');
    return Nello_detectDeviceID($hash) if($cmd eq 'detectDeviceID');
    return Nello_recoverPassword($hash, $args[0], $args[1], $args[2]) if($cmd eq 'recoverPassword');
    if($cmd eq 'update') {
        Nello_updateLocations($hash);
        return Nello_updateActivities($hash);
    } 
    return Nello_open($hash, $args[0]) if($cmd eq 'open');

    return "Unknown argument $cmd, choose one of $list";
}

sub Nello_Get($$@) {
    my ($hash, $name, $cmd, @args) = @_;

    my $list = "";

    return "Unknown argument $cmd, choose one of $list";
}

sub Nello_Attr(@) {
    my ($cmd, $name, $attrName, $attrValue) = @_;

    my $hash = $main::defs{$name};
    if($attrName eq 'updateInterval') {
        RemoveInternalTimer($hash);
        Nello_poll($hash);
    }

    if($attrName eq 'deviceID' && $init_done) {
        my $bridge = 'Nello_MQTT';
        if(!defined InternalVal($bridge, "TYPE", undef)) {
            CommandDefine(undef, $bridge . ' MQTT 18.194.251.238:1883');
            CommandAttr(undef, $bridge . ' room hidden');
            CommandSave(undef, undef);
        }

        my $eventdevice = 'Nello_Events';
        if(!defined InternalVal($eventdevice, 'TYPE', undef)) {
            CommandDefine(undef, $eventdevice . ' MQTT_DEVICE');
            CommandAttr(undef, $eventdevice . ' room hidden');
            CommandAttr(undef, $eventdevice . ' IODEV '. $bridge);
            CommandAttr(undef, $eventdevice . ' subscribeReading_'. $attrValue .'_door /nello_one/'. $attrValue . '/door/');
            CommandAttr(undef, $eventdevice . ' subscribeReading_'. $attrValue .'_ring /nello_one/'. $attrValue . '/ring/');
            CommandAttr(undef, $eventdevice . ' subscribeReading_'. $attrValue .'_tw /nello_one/'. $attrValue . '/tw/');
            CommandSave(undef, undef);
        }  
    }

    return undef;
}

sub Nello_loadInternals($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    $hash->{helper}{expires} = ReadingsVal($name, '.expires', undef);
    $hash->{helper}{session} = ReadingsVal($name, '.session', undef);

    if(!defined(ReadingsVal($name, '.session', undef))) {
        $hash->{STATE} = 'authorization pending';
    } else {
        $hash->{STATE} = 'connected';
        $attr{$name}{webCmd} = 'open' if(!defined $attr{$name}{webCmd});

        Nello_updateLocations($hash, 0);
        Nello_poll($hash);
    }

    InternalTimer(gettimeofday()+10, "Nello_updateMQTTIP", $hash);
}

sub Nello_login {
    my ($hash, $username, $password) = @_;
    my $name = $hash->{NAME};

    return 'wrong syntax: set <name> login <username> <password>' if(!defined $username || !defined $password);
    Nello_authenticate($hash, $username, $password);

    return undef;
}

sub Nello_authenticate {
    my ($hash, $username, $authhash) = @_;
    my $name = $hash->{NAME};

    $username = ReadingsVal($name, "username", undef) if(!defined $username);
    $authhash = ReadingsVal($name, ".authtoken", undef) if(!defined $authhash);

    Nello_apiRequest($hash, 'login', {username => $username, password => $authhash}, 'POST', 0);
    return undef;
}

sub Nello_updateLocations {
    my ($hash, $blocking) = @_;
    Nello_apiRequest($hash, 'locations/', undef, 'GET', $blocking);
    return undef;
}

sub Nello_updateActivities {
    my ($hash) = @_;
    Nello_apiRequest($hash, 'locations/'. Nello_defaultLocationID($hash) . '/activity', undef, 'GET', 0);
    return undef;
}

sub Nello_apiRequest {
    my ($hash, $path, $args, $method, $blocking) = @_;

    if(!defined $blocking || !$blocking) {
        HttpUtils_NonblockingGet({
            url => "https://api.nello.io/$path",
            method => $method,
            hash => $hash,
            apiPath => $path,
            timeout => 15,
            noshutdown => 1,
            data => $method eq 'POST' && defined $args ? encode_json $args : $args,
            header => "Cookie: session=". $hash->{helper}{session},
            callback => \&Nello_dispatch
        });
    } else {
        my ($err,$data) = HttpUtils_BlockingGet({
            url => "https://api.nello.io/$path",
            method => $method,
            hash => $hash,
            apiPath => $path,
            timeout => 15,
            noshutdown => 1,
            data => $method eq 'POST' && defined $args ? encode_json $args : $args,
            header => "Cookie: session=". $hash->{helper}{session}
        });
        return Nello_dispatch({hash => $hash, apiPath => $path, method => $method, data => $args}, $err, $data);
    }
}

sub Nello_dispatch($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my ($path) = split('\?', $param->{apiPath}, 2);
    my ($pathpt0, $pathpt1, $pathpt2, $pathpt3, $pathpt4) = split('/', $path, 5);
    my $method = $param->{method};
    my $header = $param->{httpheader};
    my $args = $param->{data};
    delete $hash->{helper}{dispatch};

    if(!defined($param->{hash})){
        Log3 "Nello", 2, 'Nello: dispatch fail (hash missing)';
        return undef;
    }

    $args = eval { JSON->new->utf8(0)->decode($args) } if(defined $args);

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    $hash->{helper}{dispatch}{json} = $json;
    my $status = $json->{result}{status};
    my $successful = $status && ($status eq "200" || lc $status eq "ok");

    #Log3 "Nello", 3, $header;
    #Log3 $name, 3, $name . ' : ' . $hash . $data;

    if($path eq 'login') {
        if(defined $json->{authentication} && $json->{authentication} && defined $header) {
            Log3 "Nello", 3, "$name: login successful";

            my ($session, $expires) = $header =~ m/:[^:]*session=([^;]*); Expires=([^;]*);/;

            readingsBeginUpdate($hash);
            readingsBulkUpdateIfChanged($hash, 'username', $args->{username});
            readingsBulkUpdateIfChanged($hash, '.authtoken', $args->{password});
            readingsBulkUpdateIfChanged($hash, '.session', $session);
            readingsBulkUpdate($hash, '.expires', $expires);
            readingsBulkUpdateIfChanged($hash, 'user_id', $json->{user}{user_id});
            Nello_saveLocations($hash, $json->{user}{roles}, 0);
            readingsEndUpdate($hash, 1);

            Nello_poll($hash) if($hash->{STATE} ne 'connected');
            $hash->{STATE} = 'connected';
            $hash->{helper}{session} = $session;

            my $failReq = $hash->{helper}{authfail};
            Nello_apiRequest($hash, $failReq->{path}, $failReq->{data}, $failReq->{method}, 0) if(defined $failReq); # repeat failed request
        } else {
            Log3 "Nello", 3, "$name: login failed";
            CommandDeleteReading(undef, "$name .*");
            $hash->{STATE} = 'authentication pending';
            delete $hash->{helper}{session};
        }

        delete $hash->{helper}{authfail};
    }

    if(defined $json->{result} && defined $json->{result}{status} && $json->{result}{status} eq "400") {
        Nello_authenticate($hash);
        $hash->{helper}{authfail} = {data => $args, path => $path, method => $method};
    }

    if($path eq 'locations/') {
        Nello_saveLocations($hash, $json->{user}{roles}, 1);
        Nello_open($hash) if(defined $hash->{helper}{retryopen});
    }

    if(defined $pathpt4 && $pathpt4 eq 'open') {
        Log3 $name, 3, $name . ': ' . ($successful ? 'opened' : 'open failed');
        if(!defined $attr{$name}{deviceID}) {
            Nello_updateActivities($hash);
            InternalTimer(gettimeofday()+2, "Nello_updateActivities", $hash);
        }
    }

    if(defined $pathpt2 && $pathpt2 eq 'activity') {
        my $last = ReadingsVal($name, '.last_activity', undef);

        if(defined $json->{activities} && @{$json->{activities}} > 0) {
            if(defined $last) {
                foreach my $activity (reverse @{$json->{activities}}) {
                    my $time = str2time($activity->{date});
                    $time = round($time, 0) if(defined $time);
                    if($time > $last) {
                        my $didring = ($activity->{type} eq 'door.open.one.tw' || $activity->{type} =~ m/bell.ring/) && (!defined $hash->{helper}{last_ring} || time() - $hash->{helper}{last_ring} > 5);
                        delete $hash->{helper}{last_ring};

                        readingsBeginUpdate($hash);
                        readingsBulkUpdate($hash, 'activity', $activity->{type});
                        readingsBulkUpdate($hash, 'activity_text', $activity->{description});
                        readingsBulkUpdate($hash, 'activity_time', $time);
                        readingsBulkUpdate($hash, 'last_user_open', $time) if($activity->{type} eq 'door.open.one.user');
                        readingsBulkUpdate($hash, 'last_timewindow_open', $time) if($activity->{type} eq 'door.open.one.tw');
                        readingsBulkUpdate($hash, 'last_open', $time) if($activity->{type} =~ m/open/);
                        readingsBulkUpdate($hash, 'last_ring', $time) if($didring);
                        readingsBulkUpdate($hash, 'last_ring_denied', $time) if($activity->{type} eq 'bell.ring.denied');
                        readingsEndUpdate($hash, 1);

                        Log3 $name, 3, $name. ' ring' if($didring);
                        Log3 $name, 3, $name. ': '. $activity->{description};
                    }
                }
            }   
            
            my $next = $json->{activities}[0];
            $last = round(str2time($next->{date}), 0);
        } else {
            $last = time();
        }

        readingsSingleUpdate($hash, '.last_activity', $last, 1);
    }

    if($path eq 'detectMQTT') {
        if($successful) {
            CommandAttr(undef, $name . " deviceID ". $json->{id});
            CommandSave(undef, undef);
            Log3 $name, 3, $name . ": successfully detected device ID";
        } else {
            delete $hash->{helper}{detectMQTT};
            if($status eq 'busy') {
                Log3 $name, 3, $name . ": busy detecting device ID, trying again.";
                InternalTimer(gettimeofday()+5, "Nello_detectDeviceID", $hash);
            } else {
                Log3 $name, 3, $name . ": failed to detect deviceID";
            }
            
        }
    }

    if($path eq 'recover-password') {
        Log3 $name, 3, $name .": " . $json->{result}{message};
    }

    return undef;
}

sub Nello_saveLocations($$$) {
    my ($hash, $locations, $beginUpdate) = @_;
    my $name = $hash->{NAME};

    CommandDeleteReading(undef, "$name location_.*");

    readingsBeginUpdate($hash) if($beginUpdate);

    my $index = 0;
    foreach my $location (@{$locations}) {
        my $prefix = "location_". ($index+1);
        readingsBulkUpdate($hash, $prefix. "_id", $location->{location_id}, 1);
        readingsBulkUpdate($hash, $prefix. "_ssid", $location->{home_ssid}, 1);
        readingsBulkUpdate($hash, $prefix. "_role", $location->{role}, 1);
        readingsBulkUpdate($hash, $prefix. "_active", $location->{is_active} ? 1 : 0, 1);
        $index++;
    }

    readingsBulkUpdate($hash, "locations", $index, 1);
    readingsEndUpdate($hash, 1) if($beginUpdate);
}

sub Nello_open {
    my ($hash, $location_id) = @_;
    my $name = $hash->{NAME};

    $location_id = ReadingsVal($name, 'location_'. $location_id . '_id', undef) if(defined $location_id);
    $location_id = Nello_defaultLocationID($hash) if(!defined $location_id);
    if(!defined $location_id && !defined $hash->{helper}{retryopen}) {
        $hash->{helper}{retryopen} = 1;
        return Nello_updateLocations($hash);
    }

    delete $hash->{helper}{retryopen} if(defined $hash->{helper}{retryopen});
    return 'no location available' if(!defined $location_id);

    my $user_id = ReadingsVal($name, 'user_id', undef);
    Nello_apiRequest($hash, "locations/$location_id/users/$user_id/open", {type => "swipe"}, 'POST', 0);
    $hash->{helper}{last_opened} = time();

    return undef;
}

sub Nello_recoverPassword {
    my ($hash, $username) = @_;
    return 'wrong syntax: set <name> recoverPassword <username>' if(!defined $username);

    return Nello_apiRequest($hash, 'recover-password', {username => $username}, 'POST', 0);
}

sub Nello_poll {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    return if(Nello_isDisabled($hash));
  
    my $pollInterval = $attr{$name}{updateInterval};
    InternalTimer(gettimeofday()+(defined $pollInterval ? $pollInterval : (!defined $attr{$name}{deviceID} ? 15 : 15*60)), "Nello_poll", $hash);
    Nello_updateActivities($hash);
}

sub Nello_isDisabled($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    return defined $attr{$name}{disable};
}

sub Nello_defaultLocationID {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    return ReadingsVal($name, 'location_1_id', undef);
}

sub Nello_detectDeviceID {
    my ($hash) = @_;
    HttpUtils_NonblockingGet({
            url => "http://nello.oskar.pw/detectMQTT.php",
            method => 'GET',
            hash => $hash,
            apiPath => 'detectMQTT',
            timeout => 15,
            noshutdown => 1,
            callback => \&Nello_dispatch
    });

    $hash->{helper}{detectMQTT} = 1;
    InternalTimer(gettimeofday()+2, "Nello_detectExecute", $hash);

    return undef;
}

sub Nello_detectExecute {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!defined $hash->{helper}{detectMQTT});

    Log3 $name, 3, $name . ": opening door to detect device ID now.";

    Nello_open($hash);
    Nello_open($hash);
}

sub Nello_updateMQTTIP {
    my $mqtt_ip = trim(InternalVal("Nello_MQTT", "DEF", undef));
    if(defined $mqtt_ip && $mqtt_ip ne "18.194.251.238:1883") {
        fhem("defmod Nello_MQTT MQTT 18.194.251.238:1883");
        CommandSave(undef, undef);
    }
}

1;

=pod
=item device
=item summary    control your intercom with nello one
=item summary_DE Steuerung der Gegensprechanlage mit nello one
=begin html

<a name="Nello"></a>
<h3>Nello</h3>
<ul>
  The <i>Nello</i> module enables you to control your intercom using the <a target="_blank" rel="nofollow" href="https://www.nello.io/en/">nello one</a> module.<br>
  To set it up, you need to <b>add a new user with admin rights</b> via the nello app just for use with fhem. You cannot use your main account since only one session at a time is possible.<br>
  After that, you can define the device and continue with login.<br>
  <b>ATTENTION:</b> If the login fails, try resetting your password using the recoverPassword function.<br>
  <b>Recommendation:</b> To receive instant events, call the detectDeviceID function after login.<br>
  <br>
  <p><b>Required Packages</b></p>
  <code>
  sudo apt-get install libcpan-meta-yaml-perl<br>
  sudo cpan -i Net::MQTT::Simple
  </code>
  <br>
  <br>
  <br>
  <a name="Nello_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Nello</code><br>
  </ul>
  <br>
  <ul>
   Example: <code>define nello Nello</code><br>
  </ul>
  <br>
  <br>
  <a name="Nello_set"></a>
  <p><b>set &lt;required&gt; [ &lt;optional&gt; ]</b></p>
  <ul>
    <li>
      <i>login &lt;username&gt; &lt;password&gt;</i><br>
      login to your created account
    </li>
    <li>
      <i>recoverPassword &lt;username&gt;</i><br>
      recovers the password
    </li>

    <li>
      <i>detectDeviceID</i><br>
      detects your device ID by opening the door and creates MQTT helper (used for event hooks)
    </li>
    <li>
      <i>open [ &lt;location_id&gt; ]</i><br>
      opens the door for a given location (if the account has only access to one location the default one will be used automatically).
    </li>
    <li>
      <i>update</i><br>
      updates your locations and activities
    </li>
  </ul>  
  <br>
  <a name="Nello_get"></a>
  <p><b>Get</b></p>
  <ul>
    N/A
  </ul>
  <br>
  <a name="Nello_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>updateInterval</i><br>
      the interval to fetch new activites in seconds<br>
      default: 900 (if deviceID is available), 15 otherwise
    </li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="Nello"></a>
<h3>Nello</h3>
<ul>
  Das <i>Nello</i> Modul ermöglicht die Steuerung des <a target="_blank" rel="nofollow" href="https://www.nello.io/de/">nello one</a> Chips.<br>
  Um es aufzusetzen, muss zunächst ein <b>neuer Nutzer mit Admin-Rechten</b> in der Nello-App angelegt werden, der nur für FHEM verwendet wird - eine Nutzung per App ist mit diesem Account dann nicht mehr möglich.<br>
  Anschließend kann das Gerät angelegt werden. Sobald das Gerät erstellt wurde, kann der Login durchgeführt werden.<br>
  <b>ACHTUNG:</b> Sollte der Login fehlschlagen, versuche das Passwort über die recoverPassword Funktion zurückzusetzen.<br>
  <b>Dringend empfohlen:</b> Für verzögerungsfreie Events die detectDeviceID Funktion nach dem Login aufrufen.<br>
  <br>
  <p><b>Benötigte Pakete</b></p>
  <code>
  sudo apt-get install libcpan-meta-yaml-perl<br>
  sudo cpan -i Net::MQTT::Simple
  </code>
  <br>
  <br>
  <br>
  <a name="Nello_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Nello</code><br>
  </ul>
  <br>
  <ul>
   Beispiel: <code>define nello Nello</code><br>
  </ul>
  <br>
  <a name="Nello_set"></a>
  <p><b>set &lt;required&gt; [ &lt;optional&gt; ]</b></p>
  <ul>
    <li>
      <i>login &lt;username&gt; &lt;password&gt;</i><br>
      Login
    </li>
    <li>
      <i>recoverPassword &lt;username&gt;</i><br>
      setzt das Passwort zurück
    </li>

    <li>
      <i>detectDeviceID</i><br>
      erkennt die Geräte-ID des Nellos durch einmaliges Öffnen der Tür und erstellt MQTT-Helper-Geräte für verzögerungsfreie Ereignisse
    </li>
    <li>
      <i>open [ &lt;location_id&gt; ]</i><br>
      öffnet die Tür
    </li>
    <li>
      <i>update</i><br>
      aktualisiert Aktionen und Ereignisse
    </li>
  </ul>  
  <br>
  <a name="Nello_get"></a>
  <p><b>Get</b></p>
  <ul>
    N/A
  </ul>
  <br>
  <a name="Nello_attr"></a>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <i>updateInterval</i><br>
      das Intervall in Sekunden, in dem Ereignisse gepollt werden (nur relevant, wenn deviceID nicht erkannt wurde)<br>
      default: 900 (wenn Geräte-ID erkannt wurde), ansonten 15
    </li>
  </ul>
</ul>

=end html_DE
=cut
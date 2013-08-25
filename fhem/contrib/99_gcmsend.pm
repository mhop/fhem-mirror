package main;

use HTTP::Request;
use LWP::UserAgent;
use IO::Socket::SSL;
use utf8;

my @gets = ('dummy');

sub
gcmsend_Initialize($)
{
 my ($hash) = @_;
 $hash->{DefFn}    = "gcmsend_Define";
 $hash->{NotifyFn} = "gcmsend_notify";
 $hash->{SetFn} = "gcmsend_set";
 $hash->{AttrList} = "loglevel:0,1,2,3,4,5 regIds apiKey stateFilter";
}

sub 
gcmsend_set {
  my ($hash, @a) = @_;
  my $v = @a[1];
  if ($v eq "delete_saved_states") {
    $hash->{STATES} = {};
    return "deleted";
  } else {
    return "unknown set value, choose one of delete_saved_states";
  }
}

sub
gcmsend_Define($$)
{
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);

 if (int(@args) < 1)
 {
  return "gcmsend_Define: too many arguments. Usage:\n" .
         "define <name> gcmsend";
 }
 return "Invalid arguments. Usage: \n define <name> gcmsend" if(int(@a) != 0);
 
 $hash->{STATE} = 'Initialized';

 return undef;
}

sub gcmsend_array_to_json(@) {
  my (@array) = @_;
  my $ret = "";

  for (my $i = 0; $i < int(@array); $i++) {
    if ($i != 0) {
      $ret .= ",";
    }
    my $value = @array[$i];
    $ret .= ("\"" . $value . "\"");
  }
  
  return "[" . $ret . "]";
}

sub gcmsend_message($$$) {
  my ($hash, $deviceName, $changes) = @_;
  my $name = $hash->{NAME};
  my $client = LWP::UserAgent->new();
  my $regIdsText =  AttrVal($name, "regIds", "");
  my $apikey =  AttrVal($name, "apiKey", "");
  my @registrationIds = split(/\|/, $regIdsText);
  my $unixTtimestamp = time*1000;

  my $data = 
    "{" . 
      "\"registration_ids\":" . gcmsend_array_to_json(@registrationIds) . "," .
      "\"data\": {" .
        "\"deviceName\": \"$deviceName\"," .
        "\"changes\":\"$changes\"" .
        "\"source\":\"gcmsend_fhem\"" .
      "}".
    "}";

  my $req = HTTP::Request->new(POST => "https://android.googleapis.com/gcm/send");
  $req->header(Authorization  => 'key='.$apikey);
  $req->header('Content-Type' => 'application/json; charset=UTF-8');
  $req->content($data);

  my $response = $client->request($req);
  if (! $response->is_success) {
    Log 3, "error during request: " . $response->status_line;
    $hash->{STATE} = $response->status_line;
  }
  $hash->{STATE} = "OK";
  return undef;
}

sub gcmsend_notify($$)
{
  my ($ntfy, $dev) = @_;

  my $name = $dev->{NAME};

  return if(!$dev->{CHANGED}); # Some previous notify deleted the array.
  
  my $val = "";
  my $max = int(@{$dev->{CHANGED}});

  my $key;
  my $value;

  if (! $dev->{STATES}) {
    $dev->{STATES} = {};
  }

  my $stateFilter =  AttrVal($name, "stateFilter", "");

  my $states = $ntfy->{STATES};
  if (!$states->{$name}) {
    $states->{$name} = {};
  }

  my $deviceStates = $states->{$name};  

  my $count = 0;
  for (my $i = 0; $i < $max; $i++) {
    my @keyValue = split(":", $dev->{CHANGED}[$i]);
    my $length = int($keyValue);


    if ($length == 0) {
      $key = "state";
      $value = $keyValue[0];
    } else {
      $key = @keyValue[0];
      $value = @keyValue[1];
    }

    if (
      ($stateFilter != "" && $value =~ m/$stateFilter/) &&
      (! $deviceStates->{$key} || !($deviceStates->{$key} eq $value))
    ) {
      $deviceStates->{$key} = $value;
      if ($count != 0) {
        $val .= "<|>";
      }
      $count += 1;
      $val .= "$key:$value";
    }  
  } 

  if ($count > 0) {
    gcmsend_message($ntfy, $name, $val);
  }
} 

1;

=pod
=begin html

<a name="GCMSend"></a>
<h3>GCMSend</h3>
<ul>
  Google Cloud Messaging (GCM) is a toolset to send push notifications to Android handset
  devices. This can be used to refresh the internal state of, for example, andFHEM to achieve
  a nearly up-to-date internal state of other applications. <br/>
  The module pushes any internal updates to GCM, which can be used by other apps. As payload,
  there is a data hash including the deviceName, the source (which is always gcmsend_fhem) and
  an amount of changes. The changes are concatenated by "<|>", whereas each change itself is formatted
  like "key:value". <br />
  For instance, the changes could look like: "state:on<|>measured:2013-08-11".

  <br><br>

  <a name="GCMSenddefine"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; gcmsend</code>
    <br><br>

    Defines a GCMSend device.<br><br>

    Example:
    <ul>
      <code>define gcm gcmsend</code><br>
    </ul>
    Notes:
    <ul>
      <li>Module to send messages to GCM (Google Cloud Messaging).</li>
      <li>Prerequisite is a GCM Account with Google (see <a href="https://code.google.com/apis/console/">Google API Console</a></li>
    </ul>
  </ul>

  <a name="GCMSendSet"></a>
  <h4>Set </h4>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    delete_saved_states    # deletes all saved states
    </pre>

    Examples:
    <ul>
      <code>set gcm delete_saved_states</code><br>
    </ul>
  </ul>

  <a name="GCMSendAttr"></a>
  <h4>Attributes</h4> 
  <ul>
    <li><a name="gcmsend_regIds"><code>attr &lt;name&gt; regIds &lt;string&gt;</code></a>
                <br />Registration IDs Google sends the messages to (multiple values separated by "|"</li>
    <li><a name="gcmsend_apiKey"><code>attr &lt;name&gt; apiKey &lt;string&gt;</code></a>
                <br />API-Key for GCM (can be found within the Google API Console)</li>
    <li><a name="gcmsend_stateFilter"><code>attr &lt;name&gt; stateFilter &lt;string&gt;</code></a>
                <br />Send a GCM message only if the attribute matches the attribute filter regexp</li>

  </ul>
</ul>

=end html
=cut



###############################################
#$Id: 70_PushNotifier.pm 2014-12-16 17:00:00 xusader
#
#	download client-app http://pushnotifier.de/apps/
#	create account http://pushnotifier.de/login/
#	get apiToken from http://gidix.de/setings/api/ and add a new app 
#
#	Define example:
#	define yourname PushNotifier apiToken appname user password deviceID
#
#	notify example:
#	define LampON notify Lamp:on set yourDefineName message Your message!
#

package main;
use LWP::UserAgent;

sub
PushNotifier_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}   = "PushNotifier_Define";
  $hash->{SetFn}   = "PushNotifier_Set";

}

#####################################
sub
PushNotifier_Define($$)
{
  my ($hash, $def) = @_;
  my @args = split("[ \t]+", $def);

  my ($name, $type, $apiToken, $app, $user, $passwd, $deviceID) = @args;
  
  $hash->{STATE} = 'Initialized';

 if(defined($apiToken) && defined($app)&& defined($user)&& defined($passwd)&& defined($deviceID)) {
  $hash->{apiToken} = $apiToken;
  $hash->{app} = $app;
  $hash->{user} = $user;
  $hash->{passwd} = $passwd;
  $hash->{deviceID} = $deviceID;

  my $responseAT = LWP::UserAgent->new()->post("http://a.pushnotifier.de/1/login", 
	['apiToken' => $apiToken,
        'username' => $user,
        'password' => $passwd]);

  my $strg_chkAT = $responseAT->as_string;
  $strg_chkAT =~ m{"appToken":"([\w]+)};
  my $appToken = $1;
  $hash->{appToken} = $appToken;

  my $responseID = LWP::UserAgent->new()->post("http://a.pushnotifier.de/1/getDevices", 
	['apiToken' => $apiToken,
	'appToken' => $appToken]);
  my $strg_chkID = $responseID->as_string;
  $strg_chkID =~ s/[-"{}_]//g;

  $re1='.*?';
  $re2='(\\[.*?\\])';

  $re=$re1.$re2;
  if ($strg_chkID =~ m/$re/is)
  {
    $sbraces1=$1;
    my $devices = $sbraces1;
    $hash->{devices} = $devices;
  }

  return undef; 
  }
}

#####################################
sub
PushNotifier_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
	my %sets = ('message' => 1);
	if(!defined($sets{$cmd})) {
		return "Unknown argument ". $cmd . ", choose one of " . join(" ", sort keys %sets);
	}
    return PushNotifier_Send_Message($hash, @args);
}
#####################################
sub
PushNotifier_Send_Message
{
  my $hash = shift;
  my $msg = join(" ", @_);
  $msg =~ s/\_/\n/g;

  my $response = LWP::UserAgent->new()->post('http://a.pushnotifier.de/1/sendToDevice', 
	['apiToken' => $hash->{apiToken},
	'appToken' => $hash->{appToken},
	'app' => $hash->{app},
	'deviceID' => $hash->{deviceID},
	'type' => 'MESSAGE',
	'content' => "$msg"]);

    my $error_chk = $response->as_string; 

    if($error_chk =~ m/"status":"ok"/) {
	return "OK!\n\n$msg";
	}
	else 
	{
	return $error_chk; 
    }   
}

1;

###############################################################################

=pod
=begin html

<a name="PushNotifier"></a>
<h3>PushNotifier</h3>
<ul>
  PushNotifier is a service to receive instant push notifications on your
  phone or tablet from a variety of sources.<br>
  You need an account to use this module.<br>
  For further information about the service see <a href="http://www.fhemwiki.de/wiki/PushNotifier">FhemWiki PushNotifier</a>.<br>
  <br>
  Discuss the module <a href="http://forum.fhem.de/index.php/topic,25440.0.html">here</a>.<br>
  <br>
  <br>
  <a name="PushNotifierDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PushNotifier &lt;apiToken&gt; &lt;appName&gt; &lt;user&gt; &lt;password&gt; &lt;deviceID&gt;</code><br>
    <br>
    You have to create an account to get the apiToken.<br>
    And you have to create an application to get the appToken.<br>
    <br>
    Example:
    <ul>
      <code>define PushNotifier1 PushNotifier 01234 appname user password 012</code>
    </ul>
  </ul>
  <br>
  <a name="PushNotifierSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;PushNotifier_device&gt; message</code>
    <br>
    <br>
    Examples:
    <ul>
      <code>set PushNotifier1 message This is a text.</code><br>
    </ul>
    Linebreak:
    <ul>
      <code>set PushNotifier1 message This is a text._New Line.</code><br>
    </ul>
  </ul>
  <br>
  <a name="PushNotifierEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html
=begin html_DE

<a name="PushNotifier"></a>
<h3>PushNotifier</h3>
<ul>
  PushNotifier ist ein Dienst, um Benachrichtigungen von einer vielzahl
  von Quellen auf Deinem Smartphone oder Tablet zu empfangen.<br>
  Du brauchst einen Account um dieses Modul zu verwenden.<br>
  Für weitere Informationen besuche <a href="http://www.fhemwiki.de/wiki/PushNotifier">FhemWiki PushNotifier</a>.<br>
  <br>
  Diskutiere das Modul <a href="http://forum.fhem.de/index.php/topic,25440.0.html">hier</a>.<br>
  <br>
  <br>
  <a name="PushNotifierDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PushNotifier &lt;apiToken&gt;  &lt;appName&gt; &lt;user&gt; &lt;password&gt; &lt;deviceID&gt;</code><br>
    <br>
    Du musst einen Account erstellen, um das apiToken zu bekommen.<br>
    Und du musst eine Anwendung erstellen, um einen appToken zu bekommen.<br>
    <br>
    Beispiel:
    <ul>
      <code>define PushNotifier1 PushNotifier 01234 appname user password 012</code>
    </ul>
  </ul>
  <br>
  <a name="PushNotifierSet"></a>
  <b>Set</b>
  <ul>
	<code>set &lt;PushNotifier_device&gt; message </code>
    <br>
    <br>
    Beispiele:
    <ul>
      <code>set PushNotifier1 message Dies ist ein Text.</code><br>
    </ul>
    Zeilenumbruch:
    <ul>
      <code>set PushNotifier1 message Dies ist ein Text._Neue Zeile.</code><br>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <br>
  <a name="PushNotifierEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html_DE
=cut


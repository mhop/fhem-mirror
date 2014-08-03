###############################################
#$Id: 70_PushNotifier.pm 2014-07-22 11:07:00 xusader
#
#	download client-app http://pushnotifier.de/apps/
#	create account http://pushnotifier.de/login/
#	get apiToken from http://gidix.de/setings/api/ and add a new app 
#	get appToken with:
#	curl -s -F apiToken="apiToken=your apiToken" -F username="your username" -F password="your password" http://a.pushnotifier.de/1/login 
#	get deviceID with:
#	curl -s -F "apiToken=your apiToken" -F "appToken=your appToken" http://a.pushnotifier.de/1/getDevices
#
#	Define example:
#	define yourname PushNotifier apiToken appToken appname deviceID
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

  my ($name, $type, $apiToken, $appToken, $app, $deviceID) = @args;
  
  $hash->{STATE} = 'Initialized';

 if(defined($apiToken) && defined($appToken)&& defined($app)&& defined($deviceID)) {
  $hash->{apiToken} = $apiToken;
  $hash->{appToken} = $appToken;
  $hash->{app} = $app;
  $hash->{deviceID} = $deviceID;
  
  return undef;
  }
}

#####################################
sub
PushNotifier_Set($@)
{
  my ($hash, $name, $cmd, @a) = @_;
	my %sets = ('message' => 1);
	if(!defined($sets{$cmd})) {
		return "Unknown argument $cmd, choose one of " . join(" ", sort keys %sets);
	}  
    return PushNotifier_Send_Message($hash, @a);
}
#####################################
sub
PushNotifier_Send_Message#($@)
{
  my $hash = shift;
  my $msg = join(" ", @_);
  my $apiToken = $hash->{apiToken};
  my $appToken = $hash->{appToken};
  my $app = $hash->{app};
  my $deviceID = $hash->{deviceID};

  my %settings = (
	'apiToken' => $apiToken,
	'appToken' => $appToken,
	'app' => $app,
	'deviceID' => $deviceID,
	'type' => 'MESSAGE',
	'content' => "$msg"
    );

    my $response = LWP::UserAgent->new()->post("http://a.pushnotifier.de/1/sendToDevice", \%settings);
 
    my $error_chk = $response->as_string;    

    if($error_chk =~ m/"status":"ok"/) {
	return "OK";
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
    <code>define &lt;name&gt; PushNotifier &lt;apiToken&gt; &lt;appToken&gt; &lt;appName&gt; &lt;deviceID&gt;</code><br>
    <br>
    You have to create an account to get the apiToken.<br>
    And you have to create an application to get the appToken.<br>
    <br>
    Example:
    <ul>
      <code>define PushNotifier1 PushNotifier 01234 56789 appname 012</code>
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
    <code>define &lt;name&gt; PushNotifier &lt;apiToken&gt; &lt;appToken&gt; &lt;appName&gt; &lt;deviceID&gt;</code><br>
    <br>
    Du musst einen Account erstellen, um das apiToken zu bekommen.<br>
    Und du musst eine Anwendung erstellen, um einen appToken zu bekommen.<br>
    <br>
    Beispiel:
    <ul>
      <code>define PushNotifier1 PushNotifier 01234 56789 appname 012</code>
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


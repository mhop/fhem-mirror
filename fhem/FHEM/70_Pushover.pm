##############################################
#
# A module to send notifications to Pushover.
#
# written 2013 by Johannes B <johannes_b at icloud.com>
#
##############################################
#
# Definition:
# define <name> Pushover <token> <user>
#
# Example:
# define Pushover1 Pushover 12345 6789
#
#
# You can send messages via the following command:
# set <Pushover_device> msg <title> <msg> <device> <priority> <sound> [<retry> <expire>]
#
# Examples:
# set Pushover1 msg 'Titel' 'This is a text.' '' 0 ''
# set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600
#
# Explantation:
# If device is empty, the message will be sent to all devices.
# If sound is empty, the default setting in the app will be used.
# If priority is higher or equal 2, retry and expire must be defined.
#
#
# For further documentation of these parameters:
# https://pushover.net/api


package main;

use HttpUtils;
use utf8;

my %sets = (
  "msg" => 1
);

sub Pushover_Initialize($$)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "Pushover_Define";
  $hash->{SetFn}    = "Pushover_Set";
  $hash->{AttrList} = "timestamp:0,1";
}

sub Pushover_Define($$)
{
  my ($hash, $def) = @_;
  
  my @args = split("[ \t]+", $def);
  
  if (int(@args) < 2)
  {
    return "Invalid number of arguments: define <name> Pushover <token> <user>";
  }
  
  my ($name, $type, $token, $user) = @args;
  
  $hash->{STATE} = 'Initialized';
  
  if(defined($token) && defined($user))
  {    
    $hash->{Token} = $token;
    $hash->{User} = $user;
    return undef;
  }
  else
  {
    return "Token and/or user missing.";
  }
}

sub Pushover_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  
  if (!defined($sets{$cmd}))
  {
    return "Unknown argument " . $cmd . ", choose one of " . join(" ", sort keys %sets);
  }

  if ($cmd eq 'msg')
  {
    return Pushover_Set_Message($hash, @args);
  }
}

sub Pushover_Set_Message
{
  my $hash = shift;
  
  my $attr = join(" ", @_);
  
  my $shortExpressionMatched = 0;
  my $longExpressionMatched = 0;
  
  if($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*(".*"|'.*')\s*(\d+)\s*(\d+)\s*$/s)
  {
    $longExpressionMatched = 1;
  }
  elsif($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*(".*"|'.*')\s*$/s)
  {
    $shortExpressionMatched = 1;
  }
  
  my $title = "";
  my $message = "";
  my $device = "";
  my $priority = "";
  my $sound = "";
  my $retry = "";
  my $expire = "";
  
  if(($shortExpressionMatched == 1) || ($longExpressionMatched == 1))
  {
    $title = $1;
    $message = $2;
    $device = $3;
    $priority = $4;
    $sound = $5;
    
    if($longExpressionMatched == 1)
    {
      $retry = $6;
      $expire = $7;
    }
    
    if($title =~ /^['"](.*)['"]$/s)
    {
      $title = $1;
    }
    
    if($message =~ /^['"](.*)['"]$/s)
    {
      $message = $1;
    }
    
    if($device =~ /^['"](.*)['"]$/s)
    {
      $device = $1;
    }
    
    if($priority =~ /^['"](.*)['"]$/)
    {
      $priority = $1;
    }
    
    if($sound =~ /^['"](.*)['"]$/s)
    {
      $sound = $1;
    }
    
    if($retry =~ /^['"](.*)['"]$/s)
    {
      $retry = $1;
    }
    
    if($expire =~ /^['"](.*)['"]$/s)
    {
      $expire = $1;
    }
  }
  
  if((($title ne "") && ($message ne "")) && ((($retry ne "") && ($expire ne "")) || ($priority < 2)))
  {
    my $body = "token=" . $hash->{Token} . "&" .
    "user=" . $hash->{User} . "&" .
    "title=" . $title . "&" .
    "message=" . $message;
    
    if ($device ne "")
    {
      $body = $body . "&" . "device=" . $device;
    }
    
    if ($priority ne "")
    {
      $body = $body . "&" . "priority=" . $priority;
    }
    
    if ($sound ne "")
    {
      $body = $body . "&" . "sound=" . $sound;
    }
    
    if ($retry ne "")
    {
      $body = $body . "&" . "retry=" . $retry;
    }
    
    if ($expire ne "")
    {
      $body = $body . "&" . "expire=" . $expire;
    }
    
    my $timestamp = AttrVal($hash->{NAME}, "timestamp", 0);
    
    if (1 == $timestamp)
    {
      $body = $body . "&" . "timestamp=" . time();
    }
    
    my $result = Pushover_HTTP_Call($hash, $body);
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "last-message", $title . ": " . $message);
    readingsBulkUpdate($hash, "last-result", $result);
    readingsEndUpdate($hash, 1);
    
    return $result;
  }
  else
  {
    return "Syntax: set <Pushover_device> msg <title> <msg> <device> <priority> <sound> [<retry> <expire>]";
  }
}

sub Pushover_HTTP_Call($$) 
{
  my ($hash,$body) = @_;
  
  my $url = "https://api.pushover.net/1/messages.json";
  
  $response = GetFileFromURL($url, 10, $body, 0, 5);
  
  if ($response =~ m/"status":(.*),/)
  {
  	if ($1 eq "1")
  	{
      return "OK";
  	}
  	elsif ($response =~ m/"errors":\[(.*)\]/)
  	{
      return "Error: " . $1;
  	}
  	else
  	{
      return "Error";
  	}
  }
  else
  {
  	return "Error: No known response"
  }
}

1;

=pod
=begin html

<a name="Pushover"></a>
<h3>Pushover</h3>
<ul>
  Pushover is a service to receive instant push notifications on your
  phone or tablet from a variety of sources.<br>
  You need an account to use this module.<br>
  For further information about the service see <a href="https://pushover.net">pushover.net</a>.<br>
  <br>
  Discuss the module <a href="http://forum.fhem.de/index.php/topic,16215.0.html">here</a>.<br>
  <br>
  <br>
  <a name="PushoverDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushover &lt;token&gt; &lt;user&gt;</code><br>
    <br>
    You have to create an account to get the user key.<br>
    And you have to create an application to get the API token.<br>
    <br>
    Example:
    <ul>
      <code>define Pushover1 Pushover 01234 56789</code>
    </ul>
  </ul>
  <br>
  <a name="PushoverSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; msg &lt;title&gt; &lt;msg&gt; &lt;device&gt; &lt;priority&gt; &lt;sound&gt; [&lt;retry&gt; &lt;expire&gt;]</code>
    <br>
    <br>
    Examples:
    <ul>
      <code>set Pushover1 msg 'Titel' 'This is a text.' '' 0 ''</code><br>
      <code>set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>If device is empty, the message will be sent to all devices.
      </li>
      <li>If sound is empty, the default setting in the app will be used.
      </li>
      <li>If priority is higher or equal 2, retry and expire must be defined.
      </li>
      <li>For further documentation of these parameters have a look at the <a href="https://pushover.net/api">Pushover API</a>.
      </li>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushoverAttr"></a>
  <b>Attributes</b>
  <ul>
    <a name="timestamp"></a>
    <li>timestamp<br>
        Send the unix timestamp with each message.
    </li><br>
  </ul>
  <br>
  <a name="PushoverEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html
=begin html_DE

<a name="Pushover"></a>
<h3>Pushover</h3>
<ul>
  Pushover ist ein Dienst, um Benachrichtigungen von einer vielzahl
  von Quellen auf Deinem Smartphone oder Tablet zu empfangen.<br>
  Du brauchst einen Account um dieses Modul zu verwenden.<br>
  Für weitere Informationen über den Dienst besuche <a href="https://pushover.net">pushover.net</a>.<br>
  <br>
  Diskutiere das Modul <a href="http://forum.fhem.de/index.php/topic,16215.0.html">hier</a>.<br>
  <br>
  <br>
  <a name="PushoverDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushover &lt;token&gt; &lt;user&gt;</code><br>
    <br>
    Du musst einen Account erstellen, um den User Key zu bekommen.<br>
    Und du musst eine Anwendung erstellen, um einen API Token zu bekommen.<br>
    <br>
    Beispiel:
    <ul>
      <code>define Pushover1 Pushover 01234 56789</code>
    </ul>
  </ul>
  <br>
  <a name="PushoverSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; msg &lt;title&gt; &lt;msg&gt; &lt;device&gt; &lt;priority&gt; &lt;sound&gt; [&lt;retry&gt; &lt;expire&gt;]</code>
    <br>
    <br>
    Beispiele:
    <ul>
      <code>set Pushover1 msg 'Titel' 'Dies ist ein Text.' '' 0 ''</code><br>
      <code>set Pushover1 msg 'Notfall' 'Sicherheitsproblem im Wohnzimmer.' '' 2 'siren' 30 3600</code><br>
    </ul>
    <br>
    Anmerkungen:
    <ul>
      <li>Wenn device leer ist, wird die Nachricht an alle Geräte geschickt.
      </li>
      <li>Wenn sound leer ist, dann wird die Standardeinstellung in der App verwendet.
      </li>
      <li>Wenn die Priorität höher oder gleich 2 ist müssen retry und expire definiert sein.
      </li>
      <li>Für weiterführende Dokumentation über diese Parameter lies Dir die <a href="https://pushover.net/api">Pushover API</a> durch.
      </li>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushoverAttr"></a>
  <b>Attributes</b>
  <ul>
    <a name="timestamp"></a>
    <li>timestamp<br>
        Sende den Unix-Zeitstempel mit jeder Nachricht.
    </li><br>
  </ul>
  <br>
  <a name="PushoverEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html_DE
=cut

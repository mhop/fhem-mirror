###############################################################################
#
# A module to send notifications to Pushover.
#
# written        2013 by Johannes B <johannes_b at icloud.com>
# modified 24.02.2014 by Benjamin Battran <fhem.contrib at benni.achalmblick.de>
#	-> Added title, device, priority and sound attributes (see documentation below)
#
###############################################################################
#
# Definition:
# define <name> Pushover <token> <user>
#
# Example:
# define Pushover1 Pushover 12345 6789
#
#
# You can send messages via the following command:
# set <Pushover_device> msg ['title'] '<msg>' ['<device>' <priority> '<sound>' [<retry> <expire>]]
#
# Examples:
# set Pushover1 msg 'This is a text.'
# set Pushover1 msg 'Title' 'This is a text.'
# set Pushover1 msg 'Title' 'This is a text.' '' 0 ''
# set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600
#
# Explantation:
#
# For the first and the second example the corresponding device attributes for the
# missing arguments must be set with valid values (see attributes section)
#
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

#------------------------------------------------------------------------------
sub Pushover_Initialize($$)
#------------------------------------------------------------------------------
{
  my ($hash) = @_;
  $hash->{DefFn}    = "Pushover_Define";
  $hash->{SetFn}    = "Pushover_Set";
  $hash->{AttrList} = "timestamp:0,1 title sound device priority:0,1,-1";
  #a priority value of 2 is not predifined as for this also a value for retry and expire must be set
  #which will most likely not be used with default values.
}

#------------------------------------------------------------------------------
sub Pushover_Define($$)
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
sub Pushover_Set($@)
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
sub Pushover_Set_Message
#------------------------------------------------------------------------------
{
  my $hash = shift;
  
  my $attr = join(" ", @_);

  #Set defaults
  my $title=AttrVal($hash->{NAME}, "title", "");
  my $message="";
  my $device=AttrVal($hash->{NAME}, "device", "");
  my $priority=AttrVal($hash->{NAME}, "priority", 0);
  my $sound=AttrVal($hash->{NAME}, "sound", "");
  my $retry="";
  my $expire="";


  #Split parameters
  my $argc=0;
  if($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*(".*"|'.*')\s*(\d+)\s*(\d+)\s*$/s) 
  {
    $argc=7;
  } elsif ($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*(".*"|'.*')\s*$/s) 
  {
    $argc=5;
  } elsif ($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*$/s) 
  {
    $argc=2;
  } elsif ($attr =~ /(".*"|'.*')\s*$/s) 
  {
    $argc=1
  }

  if($argc > 1) {
    $title=$1;
    $message=$2;
	
    if($argc >2) {
      $device=$3;
      $priority=$4;
      $sound=$5;
		
      if($argc > 5) {
        $retry=$6;
        $expire=$7;
      }
    }
  }
  elsif ($argc==1) {
    $message=$1;
  }

  #Remove quotation marks
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
  if($priority =~ /^['"](.*)['"]$/s) 
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

  #Check if all mandatory arguments are filled 
  #"title" and "message" can not be empty and if "priority" is set to "2" "retry" and "expire" must also be set
  if((($title ne "") && ($message ne "")) && ((($retry ne "") && ($expire ne "")) || ($priority < 2)))
  {
    #Build the "body" for the URL-Call of Pushover-Service (see Pushover-API-Documentation)
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
    
	#Save result and data of the last call to the readings.
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "last-message", $title . ": " . $message);
    readingsBulkUpdate($hash, "last-result", $result);
    readingsEndUpdate($hash, 1);
    
    return $result;
  }
  else
  {
	#There was a problem with the arguments, so tell the user the correct usage of the 'set msg' command
	if ((1 == $argc) && ($title eq ""))
	{
		return "Please define the default title in the pushover device arguments.";
	}
	else
	{
		return "Syntax: <Pushover_device> msg [title] <msg> [<device> <priority> <sound> [<retry> <expire>]]";
	}
  }
}

#------------------------------------------------------------------------------
sub Pushover_HTTP_Call($$) 
#------------------------------------------------------------------------------
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

###############################################################################

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
    <code>set &lt;Pushover_device&gt; msg [title] &lt;msg&gt; [&lt;device&gt; &lt;priority&gt; &lt;sound&gt; [&lt;retry&gt; &lt;expire&gt;]]</code>
    <br>
    <br>
    Examples:
    <ul>
      <code>set Pushover1 msg 'This is a text.'</code><br>
      <code>set Pushover1 msg 'Title' 'This is a text.'</code><br>
      <code>set Pushover1 msg 'Title' 'This is a text.' '' 0 ''</code><br>
      <code>set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>For the first and the second example the corresponding default attributes for the missing arguments must be defined for the device (see attributes section)
      </li>
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
    <a name="title"></a>
    <li>title<br>
        Will be used as title if title is not specified as an argument.
    </li><br>
    <a name="device"></a>
    <li>device<br>
        Will be used for the device name if device is not specified as an argument. If left blank, the message will be sent to all devices.
    </li><br>
    <a name="priority"></a>
    <li>priority<br>
        Will be used as priority value if priority is not specified as an argument. Valid values are -1 = silent / 0 = normal priority / 1 = high priority
    </li><br>
    <a name="sound"></a>
    <li>sound<br>
        Will be used as the default sound if sound argument is missing. If left blank the adjusted sound of the app will be used. 
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
	<code>set &lt;Pushover_device&gt; msg [title] &lt;msg&gt; [&lt;device&gt; &lt;priority&gt; &lt;sound&gt; [&lt;retry&gt; &lt;expire&gt;]]</code>
    <br>
    <br>
    Beispiele:
    <ul>
      <code>set Pushover1 msg 'Dies ist ein Text.'</code><br>
      <code>set Pushover1 msg 'Titel' 'Dies ist ein Text.'</code><br>
      <code>set Pushover1 msg 'Titel' 'Dies ist ein Text.' '' 0 ''</code><br>
      <code>set Pushover1 msg 'Notfall' 'Sicherheitsproblem im Wohnzimmer.' '' 2 'siren' 30 3600</code><br>
    </ul>
    <br>
    Anmerkungen:
    <ul>
      <li>Bei der Verwendung der ersten beiden Beispiele müssen die entsprechenden Attribute als Ersatz für die fehlenden Parameter belegt sein (s. Attribute)
      </li>
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
    <a name="title"></a>
    <li>title<br>
        Wird beim Senden als Titel verwendet, sofern dieser nicht als Aufrufargument angegeben wurde.
    </li><br>
    <a name="device"></a>
    <li>device<br>
        Wird beim Senden als Gerätename verwendet, sofern dieser nicht als Aufrufargument angegeben wurde. Kann auch generell entfallen, bzw. leer sein, dann wird an alle Geräte gesendet.
    </li><br>
    <a name="priority"></a>
    <li>priority<br>
        Wird beim Senden als Priorität verwendet, sofern diese nicht als Aufrufargument angegeben wurde. Zulässige Werte sind -1 = leise / 0 = normale Priorität / 1 = hohe Priorität
    </li><br>
    <a name="sound"></a>
    <li>sound<br>
        Wird beim Senden als Titel verwendet, sofern dieser nicht als Aufrufargument angegeben wurde. Kann auch generell entfallen, dann wird der eingestellte Ton der App verwendet.
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

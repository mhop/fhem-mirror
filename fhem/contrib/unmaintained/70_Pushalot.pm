###############################################################################
# $Id$
#
# A module to send notifications to Pushalot.
#
# written        2015 by Talkabout B <talk dot about at gmx dot de>
#
###############################################################################
#
# Definition:
# define <name> Pushalot <token> [<source>]
#
# Example:
# define PushNotification Pushalot 123234 FHEM
#
#
# You can send messages via the following command:
# set <Pushalot_device> message "<message>" ["<title>"] ["<image>"] ["<link>"] ["<link_title>"] [<important>] [<silent>]
#
# Examples:
# set PushNotification message "This is my message."
# set PushNotification message "This is my message." "With Title"
# set PushNotification message "This is my message." "With Title" "http://www.xyz/image.png"
# set PushNotification message "This is my message." "With Title" "http://www.xyz/image.png" "http://www.xyz.com""
# set PushNotification message "This is my message." "With Title" "http://www.xyz/image.png" "http://www.xyz.com" "Link Title"
# set PushNotification message "This is my message." "With Title" "http://www.xyz/image.png" "http://www.xyz.com" "Link Title"  True False
# set PushNotification message "This is my message." "With Title" "http://www.xyz/image.png" "http://www.xyz.com" "Link Title"  True False 5
#
# Explantation:
#
#  - The first parameter is the message to send
#  - The second parameter is an optional title for the message
#  - The third parameter is an optional image for the message
#  - The fourth parameter is an optional link for the message
#  - The fifth parameter is an optional link title for the message
#  - The sixth parameter defines whether the message should be marked as important
#  - The seventh parameter defines whether the message should be delivered silently
#  - The eigth parameter defines the "time to live" in seconds for the message. After this time the message is automatically purged. Note: The Pushalot service is checking
#    messages for purge every 5 minutes
#
# For further documentation
# https://pushalot.com/api:


package main;

use HttpUtils;
use utf8;
use JSON;
use URI::Escape;

my %sets = (
  "message" => 1
);

#------------------------------------------------------------------------------
sub Pushalot_Initialize($$)
#------------------------------------------------------------------------------
{
  my ($hash) = @_;
  $hash->{DefFn}    = "Pushalot_Define";
  $hash->{SetFn}    = "Pushalot_Set";
  $hash->{AttrList} = "disable:0,1";

  Log3 $hash, 3, "Pushalot initialized";

  return undef;
}

#------------------------------------------------------------------------------
sub Pushalot_Define($$)
#------------------------------------------------------------------------------
{
  my ($hash, $def) = @_;
  
  my @args = split("[ \t]+", $def);
  
  if (int(@args) < 1)
  {
    return "Invalid number of arguments: define <name> Pushalot <token> [<source>]";
  }
  
  my ($name, $type, $token, $source) = @args;
  
  $hash->{STATE}       = 'Initialized';
  $hash->{helper}{Url} = "https://pushalot.com/api/sendmessage";
  
  if(defined($token))
  {    
    $hash->{Token} = $token;
  }
  else
  {
    return "Token and/or user missing.";
  }

  if(defined($source))
  {    
    $hash->{Source} = $source;
  }
  else
  {
    $hash->{Source} = '';
  }

  Log3 $hash, 3, "Pushalot defined for token: " . $token;

  return undef;
}

#------------------------------------------------------------------------------
sub Pushalot_Set($@)
#------------------------------------------------------------------------------
{
  my ($hash, $name, $cmd, @args) = @_;

  if (!defined($sets{$cmd}))
  {
    return "Unknown argument " . $cmd . ", choose one of " . join(" ", sort keys %sets);
  }

  if (@args < 1) 
  {
    return "Argument \"message\" missing";
  }

  if (AttrVal($name, "disable", 0 ) == 1)
  {
    return "Device is disabled";
  }

  if ($cmd eq 'message')
  {
    return Pushalot_Send($hash, Pushalot_Build_Body($hash, @args));
  }
}

#------------------------------------------------------------------------------
sub Pushalot_Build_Body($@)
#------------------------------------------------------------------------------
{
  my ($hash, @args) = @_;

  my $string             = join(" ", @args);
  my @matches            = ($string =~ /"[^"]*"| True| False| \d+/g);

  my ($message, $title, $image, $link, $linkTitle, $important, $silent, $timeToLive)  = @matches;

  $message    =~ s/^[\s"]+|[\s"]+$//g;
  $title      =~ s/^[\s"]+|[\s"]+$//g;
  $image      =~ s/^[\s"]+|[\s"]+$//g;
  $link       =~ s/^[\s"]+|[\s"]+$//g;
  $linkTitle  =~ s/^[\s"]+|[\s"]+$//g;
  $important  =~ s/^[\s"]+|[\s"]+$//g;
  $silent     =~ s/^[\s"]+|[\s"]+$//g;
  $timeToLive =~ s/^[\s"]+|[\s"]+$//g;

  if ($message eq "")
  {
    $message = $string;
  }

  return 
    "AuthorizationToken="
      . $hash->{Token} 
      . "&Source=" . $hash->{Source} 
      . "&Body=" . uri_escape($message) 
      . "&Title=" . uri_escape($title) 
      . ($image ? "&Image=" . uri_escape($image) : "")
      . ($link ? "&Link=" . uri_escape($link) : "")
      . ($linkTitle ? "&LinkTitle=" . uri_escape($linkTitle) : "")
      . "&IsImportant=" . $important
      . "&IsSilent=" . $silent
      . "&TimeToLive=" . $timeToLive;
}

#------------------------------------------------------------------------------
sub Pushalot_Send($$)
#------------------------------------------------------------------------------
{
  my ($hash,$body) = @_;

  my $params = {
    url         => $hash->{helper}{Url},
    timeout     => 10,
    hash        => $hash,
    data        => $body,
    message     => $body,
    method      => "POST",
    callback    => \&Pushalot_Callback
  };

  HttpUtils_NonblockingGet($params);

  return undef;
}

#------------------------------------------------------------------------------
sub Pushalot_Callback($)
#------------------------------------------------------------------------------
{
  my ($params, $err, $data) = @_;
  my $hash = $params->{hash};

  if($err ne "")
  {
    $returnObject = {
      Success     => false,
      Status      => 500,
      Description => "Request could not be completed: " . $err
    };

    Pushalot_Parse_Result($hash, $params->{message}, encode_json $returnObject);
  }

  elsif($data ne "")
  {
    Pushalot_Parse_Result($hash, $params->{message}, $data);
  }

  return undef;
}

#------------------------------------------------------------------------------
sub Pushalot_Parse_Result($$$)
#------------------------------------------------------------------------------
{
  my ($hash, $message, $result) = @_;

  my $returnObject = decode_json $result;

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "last-message-raw", $message);
  readingsBulkUpdate($hash, "last-result-raw", $result);
  readingsBulkUpdate($hash, "last-success", $returnObject->{"Success"});
  readingsBulkUpdate($hash, "last-status", $returnObject->{"Status"});
  readingsBulkUpdate($hash, "last-description", $returnObject->{"Description"});
  readingsEndUpdate($hash, 1);
}

    
1;

###############################################################################

=pod
=begin html

<a name="Pushalot"></a>
<h3>Pushalot</h3>
<ul>
  Pushalot is a service to receive instant push notifications on your
  Windows Phone device from a variety of sources.<br>
  You need an account to use this module.<br>
  For further information about the service see <a href="https://pushalot.com" target="_blank">pushalot.com</a>.<br>
  <br>
  Discuss the module <a href="http://forum.fhem.de/index.php/topic,37775.0.html" target="_blank">here</a>.<br>
  <br>
  <br>
  <a name="PushalotDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushalot &lt;token&gt; [&lt;source&gt;]</code><br>
    <br>
    <table>
      <colgroup>
        <col style="width: 100px";"></col>
        <col></col>
      </colgroup>
      <tr>
        <td>&lt;token&gt;</td>
        <td>The token that identifies a pushalot-account. You need to create if no account yet.</td>
      </tr>
      <tr>
        <td>&lt;source&gt;</td>
        <td>The source defines what will be shown in the 'from'-field of the message (the sender).</td>
      </tr>
    </table>
    <br>
    Example:
    <ul>
      <code>define PushNotification Pushalot 123234 FHEM</code>
    </ul>
  </ul>
  <br>
  <a name="PushalotSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;Pushalot_device&gt; "&lt;message&gt;" ["&lt;title&gt;"] ["&lt;image&gt;"] ["&lt;link&gt;"] ["&lt;link_title&gt;"] ["&lt;important&gt;"] ["&lt;silent&gt;"]</code>
    <br>
    <br>
    <table>
      <colgroup>
        <col style="width: 100px";"></col>
        <col></col>
      </colgroup>
      <tr>
        <td>&lt;message&gt;</td>
        <td>The message body that should appear in the message.</td>
      </tr>
      <tr>
        <td>&lt;title&gt;</td>
        <td>The title of the message.</td>
      </tr>
      <tr>
        <td>&lt;image&gt;</td>
        <td>An optional image URL that is shown in the message.</td>
      </tr>
      <tr>
        <td>&lt;link&gt;</td>
        <td>An optional link that should be appended to the message body.</td>
      </tr>
      <tr>
        <td>&lt;link_title&gt;</td>
        <td>An optional link title. If no title is set, the URL is shown as title in the message.</td>
      </tr>
      <tr>
        <td>&lt;important&gt;</td>
        <td>True|False: True if the message should be marked as 'important', otherwise False (Default)</td>
      </tr>
      <tr>
        <td>&lt;silent&gt;</td>
        <td>True|False: True if the message should be delivered silently (no notify sound is played), otherwise False (Default)</td>
      </tr>
      <tr>
        <td>&lt;time_to_live&gt;</td>
        <td>The time in minutes after which the message is automatically purged</td>
      </tr>
    </table>
    <br>
    Examples:
    <ul>
      <code>set PushNotification message "This is my message."</code><br>
      <code>set PushNotification message "This is my message." "With Title"</code><br>
      <code>set PushNotification message "This is my message." "With Title" "http://www.xyz.com/image.png"</code><br>
      <code>set PushNotification message "This is my message." "With Title" "http://www.xyz.com/image.png" "http://www.xyz.com"</code><br>
      <code>set PushNotification message "This is my message." "With Title" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Title" </code><br>
      <code>set PushNotification message "This is my message." "With Title" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Title" True</code><br>
      <code>set PushNotification message "This is my message." "With Title" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Title" True False</code><br>
      <code>set PushNotification message "This is my message." "With Title" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Title" True False 5</code><br>
    </ul>
    <br>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushalotAttr"></a>
  <b>Attributes</b> <ul>N/A</ul><br>
  <ul>
  </ul>
  <br>
  <a name="PushalotEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html
=begin html_DE

<a name="Pushalot"></a>
<h3>Pushalot</h3>
<ul>
  Pusalot ist ein Dienst, um Benachrichtigungen von einer vielzahl
  von Quellen auf ein Windows Phone Device zu empfangen.<br>
  Du brauchst einen Account um dieses Modul zu verwenden.<br>
  Für weitere Informationen über den Dienst besuche <a href="https://pushalot.com" target="_blank">pushalot.com</a>.<br>
  <br>
  Diskutiere das Modul <a href="http://forum.fhem.de/index.php/topic,37775.0.html" target="_blank">hier</a>.<br>
  <br>
  <br>
  <a name="PushalotDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushalot &lt;token&gt; [&lt;source&gt;]</code><br>
    <br>
    <table>
      <colgroup>
        <col style="width: 100px";"></col>
        <col></col>
      </colgroup>
      <tr>
        <td>&lt;token&gt;</td>
        <td>Der Token der den pushalot-Account identifiziert. Um diesen zu bekommen, muss ein Account erstellt werden.</td>
      </tr>
      <tr>
        <td>&lt;source&gt;</td>
        <td>Definiert den Absender, der in der Nachricht angezeigt werden soll.</td>
      </tr>
    </table>
    <br>
    Beispiel:
    <ul>
      <code>define Pushalot PushNotification 123234 FHEM</code>
    </ul>
  </ul>
  <br>
  <a name="PushalotSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;Pushalot_device&gt; "&lt;message&gt;" ["&lt;title&gt;"] ["&lt;image&gt;"] ["&lt;link&gt;"] ["&lt;link_title&gt;"] ["&lt;important&gt;"] ["&lt;silent&gt;"]</code>
    <br>
    <br>
    <table>
      <colgroup>
        <col style="width: 100px";"></col>
        <col></col>
      </colgroup>
      <tr>
        <td>&lt;message&gt;</td>
        <td>Der Nachrichten-Text.</td>
      </tr>
      <tr>
        <td>&lt;title&gt;</td>
        <td>Der Titel der Nachricht.</td>
      </tr>
      <tr>
        <td>&lt;image&gt;</td>
        <td>Optionale Bild-URL die in der Nachricht angezeigt werden soll.</td>
      </tr>
      <tr>
        <td>&lt;link&gt;</td>
        <td>Ein optionaler Link der an die Nachricht angehängt werden soll.</td>
      </tr>
      <tr>
        <td>&lt;link_title&gt;</td>
        <td>Optionaler Link Titel. Wenn kein Titel angegeben wird, ist dieser die URL.</td>
      </tr>
      <tr>
        <td>&lt;important&gt;</td>
        <td>True|False: True wenn die Nachricht als 'wichtig' markiert werden soll, sonst False (Default)</td>
      </tr>
      <tr>
        <td>&lt;silent&gt;</td>
        <td>True|False: True wenn die Nachricht 'still' ausgeliefert werden soll (kein Benachrichtigungssound wird abgespielt), ansonsten False  (Default)</td>
      </tr>
      <tr>
        <td>&lt;time_to_live&gt;</td>
        <td>Zeit in Minuten nach der die Nachricht automatisch entfernt wird. Achtung: Der Pushalot Service prüft zu löschende Nachrichten alle 5 Minuten</td>
      </tr>
    </table>
    <br>
    Beispiele:
    <ul>
      <code>set PushNotification message "Das ist meine Nachricht."</code><br>
      <code>set PushNotification message "Das ist meine Nachricht." "Mit Titel"</code><br>
      <code>set PushNotification message "Das ist meine Nachricht." "Mit Titel" "http://www.xyz.com/image.png"</code><br>
      <code>set PushNotification message "Das ist meine Nachricht." "Mit Titel" "http://www.xyz.com/image.png" "http://www.xyz.com"</code><br>
      <code>set PushNotification message "Das ist meine Nachricht." "Mit Titel" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Titel" </code><br>
      <code>set PushNotification message "Das ist meine Nachricht." "Mit Titel" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Titel" True</code><br>
      <code>set PushNotification message "Das ist meine Nachricht." "Mit Titel" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Title" True False</code><br>
      <code>set PushNotification message "Das ist meine Nachricht." "Mit Titel" "http://www.xyz.com/image.png" "http://www.xyz.com" "Link Title" True False 5</code><br>
    </ul>
    <br>
    Notes:
    <ul>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushalotAttr"></a>
  <b>Attribute</b> <ul>N/A</ul><br>
  <ul>
  </ul>
  <br>
  <a name="PushalotEvents"></a>
  <b>Generierte events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html_DE
=cut

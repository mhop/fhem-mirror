# $Id$
##############################################################################
#
#     70_Pushsafer.pm
#     Sents messages to your Pushsafer accout which will be delivered to
#     any configured device (e.g. iOS, Andriod, Windows).
#
#     This module is based on the Pushsafer API description
#     which is available at https://www.pushsafer.com/en/pushapi:
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################


package main;

use HttpUtils;
use MIME::Base64 qw(encode_base64 encode_base64url);
use utf8;

my %Pushsaver_Params = (
    "title"     => {"short" => "t", "check" => qr/^.*$/},
    "sound"     => {"short" => "s", "check" => qr/^\d+$/},
    "vibration" => {"short" => "v", "check" => qr/^\d+$/},
    "icon"      => {"short" => "i", "check" => qr/^\d+$/},
    "url"       => {"short" => "u", "check" => qr/^[a-z]+:/},
    "device"    => {"short" => "d", "check" => qr/^(?:gs)?\d+$/},
    "key"       => {"short" => "k", "check" => qr/^(?:[a-zA-Z\d]{20}|[a-zA-Z\d]{15})$/},
    "urlText"   => {"short" => "ut"},
    "message"   => {"short" => "m"},
    "ttl"       => {"short" => "l", "check" => qr/^\d+$/},
    "picture"   => {"short" => "p"},
    "picture2"  => {"short" => "p2"},
    "picture3"  => {"short" => "p3"}
);


#############################
sub Pushsafer_Initialize($$)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "Pushsafer_Define";
  $hash->{SetFn}    = "Pushsafer_Set";
  $hash->{AttrList} = "disable:0,1 ".
                      "disabledForIntervals ".
                      "do_not_notify:0,1 ".
                      $readingFnAttributes;
  return undef;
}

#############################
sub Pushsafer_Define($$)
{
    my ($hash, $def) = @_;

    my @args = split("[ \t]+", $def);

    if(!@args == 3)
    {
        return "wrong define syntax: define <name> Pushsafer <privatekey>";
    }

    my $privatekey = @args[2];

    return "invalid private key: ".$privatekey if ($privatekey !~ /^[a-z\d]{20}$/i);

    $hash->{PrivateKey} = $privatekey;
    $hash->{helper}{URL} = "https://www.pushsafer.com/api";

    Log3 $hash, 4, "Pushsafer ($name) - defined with private key: ".$privatekey;

    $hash->{STATE} = "Initialized";

    return undef;
}

#############################
sub Pushsafer_Set($$$@)
{
    my ($hash, $name, $cmd, @args) = @_;

    my $usage = "Unknown argument " . $cmd . ", choose one of message";

    if ($cmd eq 'message')
    {
        return "Arguments for command \"message\" missing" unless (@args >= 1);
        return "Device $name is disabled" if(IsDisabled($name));

        my ($a, $h) = parseParams(\@args);

        unless(defined($a->[0]))
        {
            return "No message text given";
        }

        if(scalar(@{$a}) > 1 and scalar(keys(%{$h})) == 0)
        {
            $h->{m} = join(" ", @{$a});
        }

        elsif(scalar(@{$a}) == 1 and scalar(keys(%{$h})) >= 0)
        {
            $h->{m} = $a->[0];
        }
        else
        {
            return "invalid syntax";
        }

        $h->{m} =~ s/\\n/\n/g; # replace \n with newlines

        my ($err, $data) = Pushsafer_createBody($hash, $h);

        return $err if(defined($err));

        my $data_scrambled = $data;

        $data_scrambled =~ s/k=[^&]+/k=HIDDEN/g; # remove private key from log output

        Log3 $name, 5, "Pushsafer ($name) - sending data: $data_scrambled";

        Pushsafer_Send($hash, $data);

        return undef;
    }
    else
    {
        return $usage;
    }
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

#############################
# creates the HTTP Body to sent a message
sub Pushsafer_createBody($$)
{
    my ($hash, $args) = @_;
    my $name = $hash->{NAME};

    my @urlParts;
    my @errs;

    push @urlParts, "k=".$hash->{PrivateKey} unless(exists($args->{k}) and exists($args->{key}));

    foreach my $item (keys %{$args})
    {
        my $key;
        my $val;

        if(exists($Pushsaver_Params{$item}))
        {
            if(exists($Pushsaver_Params{$item}{check}) and $args->{$item} !~ $Pushsaver_Params{$item}{check})
            {
                push @errs, "wrong syntax for option $item: ".$args->{$item};
            }
            else
            {
                $key = $Pushsaver_Params{$item}{short};
                $val = $args->{$item}
            }
        }
        elsif(grep($Pushsaver_Params{$_}{short} eq $item,  keys(%Pushsaver_Params)))
        {
            my $command = join "", grep($Pushsaver_Params{$_}{short} eq $item,  keys(%Pushsaver_Params));

            if(exists($Pushsaver_Params{$command}{check}) and $args->{$item} !~ $Pushsaver_Params{$command}{check})
            {
                push @errs, "wrong syntax for option $item: ".$args->{$item};
            }
            else
            {
                $key = $item;
                $val = $args->{$item}
            }
        }
        else
        {
            push @errs, "unsupported parameter: $item";
            next;
        }

        if($key =~/^p\d?$/)
        {
            if($val =~ /^IPCAM:(\S+)$/)
            {
                my $ipcam = $1;

                if(!exists($defs{$ipcam}) or !exists($defs{$ipcam}{TYPE}) or $defs{$ipcam}{TYPE} ne "IPCAM")
                {
                    Log3 $name, 3, "Pushsafer ($name) - no such IPCAM device: $ipcam. sending message without a picture...";
                    next;
                }

                my $path = AttrVal($ipcam, "storage",AttrVal("global", "modpath", ".")."/www/snapshots");
                $path .= "/" unless($path =~ m,/$,);
                $path .= ReadingsVal($ipcam, "last", "");

                $val = Pushsafer_createDataUrl($hash, $path);
                next unless(defined($val));
            }
            elsif(-e $val)
            {
                $val = Pushsafer_createDataUrl($hash, $val);
                next unless(defined($val));
            }
            else
            {
                Log3 $name, 3, "Pushsafer ($name) - picture file does not exist: $val - sending message without a picture...";
                next;
            }
        }

        push @urlParts, $key."=".urlEncode($val);
    }

    return join("\n", @errs) if(@errs);
    return (undef, join("&", @urlParts));
}


#####################################
# determine the image file format (reused from IPCAM module by Martin Fischer)
sub Pushsafer_guessFileFormat($)
{
    my ($src) = shift;
    my $header;
    my $srcHeader;

    open(my $s, "<", $src) || return undef;
    $src = $s;

    my $reading = read($src, $srcHeader, 64);
    return undef if(!$reading);

    local($_) = $srcHeader;

    return "image/jpeg" if /^\xFF\xD8/;
    return "image/png"  if /^\x89PNG\x0d\x0a\x1a\x0a/;
    return "image/gif"  if /^GIF8[79]a/;
    return undef;
}
#####################################
# create a data URL schema from a image file
sub Pushsafer_createDataUrl($$)
{
    my ($hash, $file) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 4, "Pushsafer ($name) - open image file: $file";

    my ($err, @content) = FileRead({FileName => $file, ForceType => "file"});

    if(defined($err))
    {
        Log3 $name, 3, "Pushsafer ($name) - unable to open image file $file: $err";
        Log3 $name, 3, "Pushsafer ($name) - sending message without picture...";
    }
    else
    {
        my $image = join($/, @content);
        my $mime_type = Pushsafer_guessFileFormat(\$image);

        if(defined($mime_type))
        {
            Log3 $name, 5, "Pushsafer ($name) - found image of type: $mime_type";

            my $base_64 = encode_base64($image);

            return "data:$mime_type;base64,".$base_64;
        }
        else
        {
            Log3 $name, 3, "Pushsafer ($name) - unsupported image type for $file - see commandref for supported image formats";
        }
    }

    return undef;
}

#############################
# sents a message via HTTP request
sub Pushsafer_Send($$)
{
  my ($hash, $body) = @_;

  my $params = {
    url         => $hash->{helper}{URL},
    timeout     => 10,
    hash        => $hash,
    data        => $body,
    method      => "POST",
    callback    => \&Pushsafer_Callback
  };

  HttpUtils_NonblockingGet($params);

  return undef;
}

#############################
# processes the HTTP answer
sub Pushsafer_Callback($$$)
{
    my ($params, $err, $data) = @_;
    my $hash = $params->{hash};
    my $name = $hash->{NAME};

    $err = "" unless(defined($err));
    $data = "" unless(defined($err));

    if($data ne "")
    {
        Log3 $name, 5, "Pushsafer ($name) - received ".(defined($params->{code}) ? "HTTP status ".$params->{code}." with " : "")."data: $data";
    }

    if($err ne "")
    {
        readingsSingleUpdate($hash, "last-error", $err,1);
        Log3 $name, 3, "Pushsafer ($name) - error while sending message: $err";
    }

    if(exists($params->{code}) and $params->{code} != 200)
    {
        if($data ne "" and $data =~ /error"?\s*:\s*"?(.+?)"?(?:,|}|$)/)
        {
             readingsSingleUpdate($hash, "lastError", $1, 1);
        }
        else
        {
            readingsSingleUpdate($hash, "lastError", "received HTTP status ".$params->{code}, 1);
            Log3 $name, 3, "Pushsafer ($name) - error while sending message: received HTTP status $params->{code}";
        }
        return undef;
    }

    if($data ne "")
    {
        readingsBeginUpdate($hash);

        if($data =~ /success"?\s*:\s*"?(.+?)"?(?:,|}|$)/)
        {
            readingsBulkUpdate($hash, "lastSuccess", $1);
        }

        if($data =~ /available"?\s*:\s*{(.+)\s*}\s*}\s*$/gcs)
        {
            my %devices =  grep { defined($_) } map { /^"?(\d+)"?:({.+})$/ ? ($1 => $2) : undef } split(",", $1);

            foreach my $dev (keys %devices)
            {
                if(defined($devices{$dev}) and $devices{$dev} =~ /^{\s*"?([^":]+)"?\s*:\s*"?([^":]+)"?\s*}$/)
                {
                    my ($devname, $available) = ($1, $2);

                    $devname =~ s/\s+//g;

                    readingsBulkUpdate($hash, "availableMessages-$dev-$devname", $available);
                }
            }
        }

        readingsEndUpdate($hash, 1);
    }

    return undef;
}


1;


=pod
=item device
=item summary sents text message notifications via pushsafer.com
=item summary_DE verschickt Texnachrichten zur Benachrichtigung via Pushsafer
=begin html

<a name="Pushsafer"></a>
<h3>Pushsafer</h3>
<ul>
  Pushsafer is a web service to receive instant push notifications on your
  iOS, Android or Windows 10 Phone or Desktop device from a variety of sources.<br>
  You need a Pushsafer account to use this module.<br>
  For further information about the service see <a href="https://www.pushsafer.com" target="_new">pushsafer.com</a>.<br>
  <br>
  This module is only capable to send messages via Pushsafer.<br>
  <br>
  <a name="PushsaferDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushsafer &lt;key&gt;</code><br>
    <br>
    The parameter &lt;key&gt; must be a alphanumeric string. This can be a regular private key (20 digits) from your Pushsafer account or an E-Mail alias key (15 digits) which needs to be setup in your account.<br>
    <br>
    Example:
    <ul>
      <code>define PushsaferAccount Pushsafer A1b2c3D4E5F6g7h8i9J0</code>
    </ul>
  </ul>
  <br>
  <a name="PushsaferSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; message &lt;text&gt; [&lt;option1&gt;=&lt;value&gt; &lt;option2&gt;=&lt;value&gt; ...]</code><br>
    <br>
    Currently only the message command is available to sent a message.<br>
    <br>
    So the very basic use case is to send a simple text message like the following example:<br>
    <br>
    <code>set PushsaferAccount message "My first Pushsafer message."</code><br>
    <br>
    To send a multiline message, use the placeholder "\n" to indicate a newline:<br>
    <br>
    <code>set PushsaferAccount message "My second Pushsafer message.\nThis time with two lines."</code><br>
    <br>
    <u>Optional Modifiers</u><br>
    <br>
    It is possible to customize a message with special options that can be given in the message command after the message text. Several options can be combined together. The possible options are:<br>
    <br>
    <code><b>title</b>&nbsp;&nbsp;&nbsp;&nbsp;</code> - short: <code>t&nbsp;</code> - type: text - A special title for the message text.<br>
    <code><b>device</b>&nbsp;&nbsp;&nbsp;</code> - short: <code>d&nbsp;</code> - type: text - The device ID as number, to send the message to a specific device, or "gs" + group ID to send to a device group (e.g. "gs23" for group id 23). By default the message will be send to all registered devices.<br>
    <code><b>sound</b>&nbsp;&nbsp;&nbsp;&nbsp;</code> - short: <code>s&nbsp;</code> - type: number - The ID of a specific sound to play on the target device upon reception (see <a href="https://www.pushsafer.com/en/pushapi" target="_new">Pushsafer.com</a> for a complete list of values and their meaning).<br>
    <code><b>icon</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - short: <code>i&nbsp;</code> - type: number - The ID of a specific icon to show on the target device for this text (see <a href="https://www.pushsafer.com/en/pushapi" target="_new">Pushsafer.com</a> for a complete list of values and their meaning).<br>
    <code><b>vibration</b></code> - short: <code>v&nbsp;</code> - type: number - The number of times the device should vibrate upon reception (maximum: 3 times; iOS/Android only). If not set, the default behavior of the device is used.<br>
    <code><b>url</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - short: <code>u&nbsp;</code> - type: text - A URL that should be included in the message. This can be regular http:// URL's but also specific app schemas. See <a href="https://www.pushsafer.com/en/url_schemes" target="_new">Pushsafer.com</a> for a complete list of supported URL schemas.<br>
    <code><b>urlText</b>&nbsp;&nbsp;</code> - short: <code>ut</code> - type: text - A text that should be used to display a URL from the "url" option.<br>
    <code><b>key</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - short: <code>k&nbsp;</code> - type: text - Overrides the private key given in the define statement. Also an alias key can be used.<br>
    <code><b>ttl</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - short: <code>l&nbsp;</code> - type: number - Defines a "time-to-live" given in minutes after the message will be deleted on the target device(s). Possible range is between 1 - 43200 minutes (30 days).<br>
    <code><b>picture</b>&nbsp;&nbsp;</code> - short: <code>p&nbsp;</code> - type: text - Attach a image to the message. This can be a file path located in your filesystem (e.g. <code>picture=/home/user/picture.jpg</code>) or the name of a IPCAM instance (like <code>picture=IPCAM:<i>&lt;name&gt;</i></code>) to send the last snapshot image (e.g. <code>picture=IPCAM:IpCam_Front_House</code>). The supported image formats are JPG, PNG and GIF.<br>
    <code><b>picture2</b>&nbsp;</code> - short: <code>p2</code> - type: text - same syntax as for option <code>"picture"</code><br>
    <code><b>picture3</b>&nbsp;</code> - short: <code>p3</code> - type: text - same syntax as for option <code>"picture"</code><br>
    <br>
    Examples:<br>
    <br>
    <ul>
      <code>set PushsaferAccount message "This is a message with a title." title="Super important"</code><br>
      <code>set PushsaferAccount message "Get down here\nWe're waiting" title="Lunch is ready" device=100</code><br>
      <code>set PushsaferAccount message "Server is down" sound=25 icon=5 vibration=3</code><br>
      <code>set PushsaferAccount message "Look at my photos" url="http://www.foo.com/myphotos" urlText="Summer Vacation"</code><br>
    <br>
    It is also possible to use the short-term versions of options:<br>
    <br>
      <code>set PushsaferAccount message "This is a message with a title." t="Super important"</code><br>
      <code>set PushsaferAccount message "Get down here\nWe're waiting" t="Lunch is ready" d=100</code><br>
      <code>set PushsaferAccount message "Server is down" s=25 i=5 v=3</code><br>
      <code>set PushsaferAccount message "Look at my photos" u="http://www.foo.com/myphotos" ut="Summer Vacation"</code><br>
    </ul>
    <br>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushsaferAttr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
  </ul>
  <br>
  <a name="PushsaferEvents"></a>
  <b>Generated Readings/Events:</b><br>
  <ul>
    <li><b>lastSuccess</b> - The last successful status message received by the Pushsafer server</li>
    <li><b>lastError</b> - The last errur message received by the Pushsafer server</li>
    <li><b>availableMessages-<i>&lt;device ID&gt;</i>-<i>&lt;device name&gt;</i></b> - The remaining messages that can be send to this device</li>
  </ul>
</ul>
=end html
=begin html_DE

<a name="Pushsafer"></a>
<h3>Pushsafer</h3>
<ul>
  Pushsafer ist ein Dienst, um Benachrichtigungen von einer Vielzahl
  unterschiedlicher Quellen auf einem iOS-, Android-, Windows 10 Phone oder Desktop-Ger&auml;t zu empfangen.<br>
  Es wird ein personalisierter Account ben&ouml;tigt um dieses Modul zu verwenden.<br>
  Weitere Information zum Pushsafer-Dienst gibt es unter  <a href="https://www.pushsafer.com" target="_new">pushsafer.com</a>.<br>
  <br>
  Dieses Modul dient lediglich zum Versand von Nachrichten &uuml;ber Pushsafer.<br>
  <br>
  <br>
  <a name="PushsaferDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;Name&gt; Pushsafer &lt;Schl&uuml;ssel&gt;</code><br>
    <br>
    Der Parameter &lt;Schl&uuml;ssel&gt; muss eine alphanumerische Zeichenkette sein. Hierbei kann es sich um einen regul&auml;ren privaten Schl&uuml;ssel (20 Zeichen lang) handeln oder um einen Email-Alias-Schl&uuml;ssel (15 Zeichen lang), welcher in einem Account entsprechend eingerichtet sein muss.<br>
    <br>
    Beispiel:
    <ul>
      <code>define PushsaferAccount Pushsafer A1b2c3D4E5F6g7h8i9J0</code>
    </ul>
  </ul>
  <br>
  <a name="PushsaferSet"></a>
  <b>Set</b>
   <ul>
    <code>set &lt;Name&gt; message &lt;Nachricht&gt; [&lt;Option1&gt;=&lt;Wert&gt; &lt;Option2&gt;=&lt;Wert&gt; ...]</code><br>
    <br>
    Aktuell wird nur das "message"-Kommando unterst&uuml;tzt um Nachrichten zu versenden.<br>
    <br>
    Der einfachste Anwendungsfall ist das Versenden einer einfachen Textnachricht wie im folgenden Beispiel:<br>
    <br>
    <code>set PushsaferAccount message "Meine erste Pushsafer Nachricht."</code><br>
    <br>
    Um eine mehrzeilige Nachricht zu schicken, kann man den Platzhalter "\n" f&uuml;r einen Zeilenumbruch verwenden:<br>
    <br>
    <code>set PushsaferAccount message "Meine zweite Pushsafer Nachricht.\nDiesmal mit zwei Zeilen."</code><br>
    <br>
    <u>Optionale Zusatzparameter</u><br>
    <br>
    Es ist m&ouml;glich die zu versendende Nachricht durch zus&auml;tzliche Optionen an die eigenen W&uuml;nsche anzupassen. Diese Optionen k&ouml;nnen hinter dem Nachrichtentext beliebig kombiniert werden um die Nachricht zu individualisieren. Die m&ouml;glichen Optionen sind:<br>
    <br>
    <code><b>title</b>&nbsp;&nbsp;&nbsp;&nbsp;</code> - Kurzform: <code>t&nbsp;</code> - Typ: Text - Eine &Uuml;berschrift, die &uuml;ber der Nachricht hervorgehoben angezeigt werden soll.<br>
    <code><b>device</b>&nbsp;&nbsp;&nbsp;</code> - Kurzform: <code>d&nbsp;</code> - Typ: Text - Die Ger&auml;te-ID als Ganzzahl an welche die Nachricht gezielt geschickt werden soll. Um eine Gruppen-ID direkt zu addressieren muss der ID das Pr&auml;fix "gs" vorangestellt werden (Bsp. "gs23" f&uuml;r die Gruppen-ID 23). Standardm&auml;&szlig;ig wird eine Nachricht immer an alle Ger&auml;te geschickt, die mit dem Account verkn&uuml;pft sind.<br>
    <code><b>sound</b>&nbsp;&nbsp;&nbsp;&nbsp;</code> - Kurzform: <code>s&nbsp;</code> - Typ: Ganzzahl - Die Nummer eines Tons, welcher beim Empfang der Nachricht auf dem Zielger&auml;t ert&ouml;nen soll (siehe <a href="https://www.pushsafer.com/de/pushapi" target="_new">pushsafer.com</a> f&uuml;r eine Liste m&ouml;glicher Werte).<br>
    <code><b>icon</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - Kurzform: <code>i&nbsp;</code> - Typ: Ganzzahl - Die Nummer eines Icons, welches zusammen mit der Nachricht auf dem Zielger&auml;t angezeigt werden soll (siehe <a href="https://www.pushsafer.com/de/pushapi" target="_new">Pushsafer.com</a> f&uuml;r eine Liste m&ouml;glicher Werte).<br>
    <code><b>vibration</b></code> - Kurzform: <code>v&nbsp;</code> - Typ: Ganzzahl - Die Anzahl, wie oft das Zielger&auml;t vibrieren soll beim Empfang der Nachricht (maximal 3 mal; nur f&uuml;r iOS-/Android-Ger&auml;te nutzbar). Falls nicht benutzt, wird die ger&auml;teinterne Einstellung verwendet.<br>
    <code><b>url</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - Kurzform: <code>u&nbsp;</code> - Typ: Text - Eine URL, welche der Nachricht angehangen werden soll. Dies kann eine normale http:// bzw. https:// URL sein, es sind jedoch auch weitere spezielle Schemas m&ouml;glich. Eine Liste aller m&ouml;glichen URL-Schemas gibt es unter <a href="https://www.pushsafer.com/de/url_schemes" target="_new">pushsafer.com</a> .<br>
    <code><b>urlText</b>&nbsp;&nbsp;</code> - Kurzform: <code>ut</code> - Typ: Text - Der Text, welcher zum Anzeigen der URL benutzt werden soll anstatt der Zieladresse.<br>
    <code><b>key</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - Kurzform: <code>k&nbsp;</code> - Typ: Text - &Uuml;bersteuert den zu nutzenden Schl&uuml;ssel zur Identifikation aus dem define-Kommando. Es kann hierbei auch ein Email-Alias-Schl&uuml;ssel benutzt werden.<br>
    <code><b>ttl</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code> - Kurzform: <code>l&nbsp;</code> - Typ: Ganzzahl - Die Lebensdauer der Nachricht in Minuten. Sobald die Lebensdauer erreicht ist, wird die Nachricht selbstst&auml;ndig auf allen Ger&auml;ten gel&ouml;scht. Der m&ouml;gliche Wertebereich liegt zwischen 1 - 43200 Minuten (entspricht 30 Tagen).<br>
    <code><b>picture</b>&nbsp;&nbsp;</code> - Kurzform: <code>p&nbsp;</code> - Typ: Text - Anh&auml;ngen eines Bildes zur Nachricht. Dies kann ein Dateipfad zu einer Bilddatei sein (z.B. <code>picture=/home/user/Bild.jpg</code>) oder der Name einer IPCAM-Instanz (im Format: <code>picture=IPCAM:<i>&lt;Name&gt;</i></code>) um die letzte Aufnahme zu senden (Bsp. <code>picture=IPCAM:IpKamera_Einganstuer</code>). Es werden die Dateiformate JPG, PNG und GIF unterst&uuml;zt.<br>
    <code><b>picture2</b>&nbsp;</code> - Kurzform: <code>p2</code> - Typ: Text - Gleiche Syntax wie die Option <code>"picture"</code>.<br>
    <code><b>picture3</b>&nbsp;</code> - Kurzform: <code>p3</code> - Typ: Text - Gleiche Syntax wie die Option <code>"picture"</code>.<br>

    <br>
    Beispiele:<br>
    <br>
    <ul>
      <code>set PushsaferAccount message "Dies ist eine Nachricht mit &Uuml;berschrift." title="Sehr Wichtig!!"</code><br>
      <code>set PushsaferAccount message "Komm runter\nwir warten" title="Mittag ist fertig" device=100</code><br>
      <code>set PushsaferAccount message "Server ist nicht erreichbar" sound=25 icon=5 vibration=3</code><br>
      <code>set PushsaferAccount message "Hier sind die Urlaubsfotos" url="http://www.foo.de/fotos" urlText="Sommerurlaub"</code><br>
    <br>
    It is also possible to use the short-term versions of options:<br>
    <br>
      <code>set PushsaferAccount message "Dies ist eine Nachricht mit &Uuml;berschrift." t="Sehr Wichtig!!"</code><br>
      <code>set PushsaferAccount message "Komm runter\nwir warten" t="Mittag ist fertig" d=100</code><br>
      <code>set PushsaferAccount message "Server ist nicht erreichbar" s=25 i5 v=3</code><br>
      <code>set PushsaferAccount message "Hier sind die Urlaubsfotos" u="http://www.foo.de/fotos" ut="Sommerurlaub"</code><br>
    </ul>
    <br>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushsaferAttr"></a>
  <a name="PushsaferAttr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#disabled">disabled</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
  </ul>
  <br>
  <a name="PushsaferEvents"></a>
  <b>Generierte Readings/Events:</b><br>
  <ul>
    <li><b>lastSuccess</b> - Die letzte erfolgreiche Statusmeldung vom Pushsafer Server</li>
    <li><b>lastError</b> - Die letzte Fehlermeldung vom Pushsafer Server</li>
    <li><b>availableMessages-<i>&lt;Ger&auml;te-ID&gt;</i>-<i>&lt;Ger&auml;te-Name&gt;</i></b> - Die verbleibende Anzahl an Nachrichten die zu diesem Ger&auml;t noch gesendet werden k&ouml;nnen</li>
  </ul>
</ul>

=end html_DE
=cut

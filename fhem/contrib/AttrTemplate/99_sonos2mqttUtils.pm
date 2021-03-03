##############################################
# $Id$
# from myUtilsTemplate.pm 21509 2020-03-25 11:20:51Z rudolfkoenig
# utils for sonos2mqtt Implementation
# They are then available in every Perl expression.

package main;

use strict;
use warnings;

sub
sonos2mqttUtils_Initialize($$)
{
  my ($hash) = @_;
}

# Enter you functions below _this_ line.

##### Responses for getList and setList commands
sub sonos2mqtt
{ 
my ($NAME,$EVENT)=@_;
my @arr = split(' ',$EVENT);
my ($cmd,$vol,$text,$value);
$cmd = $arr[0];
# quick response for devStateIcon
if($cmd eq 'devStateIcon') {return sonos2mqtt_devStateIcon($NAME)}

my $bridge = (devspec2array('a:model=sonos2mqtt_bridge'))[0];
my $devicetopic = ReadingsVal($bridge,'devicetopic','sonos');
my $tts = ReadingsVal($bridge,'tts','SonosTTS');
# special cmds for the bridge
if ($NAME eq $bridge){
   if($cmd eq 'notifyall') {return qq($devicetopic/cmd/notify {"trackUri":"$arr[2]","onlyWhenPlaying":false,"timeout":100,"volume":$arr[1],"delayMs":700})}
   if($cmd eq 'announcementall') {
      ($cmd,$text) = split(' ', $EVENT,2);
      fhem("setreading $tts text ".ReadingsVal($tts,'text',' ').' '.$text.";sleep 0.4 tts;set $tts tts [$tts:text];sleep $tts:playing:.0 ;set $NAME notifyall [$tts:vol] [$tts:httpName];deletereading $tts text");
   }
   if($cmd eq 'Favorites') {return "$devicetopic/".ReadingsVal((devspec2array('a:model=sonos2mqtt_speaker'))[0],'uuid','').q(/control {"command": "adv-command","input": {"cmd": "GetFavorites","reply": "Favorites"}})}
   if($cmd eq 'setplayFav') {sonos2mqtt_mod_list('a:model=sonos2mqtt_speaker','setList','playFav:'.ReadingsVal($NAME,'favlist','').' {sonos2mqtt($NAME,$EVENT)}')}
   if($cmd eq 'setjoinGroup') {sonos2mqtt_mod_list('a:model=sonos2mqtt_speaker','setList','joinGroup:'.ReadingsVal($NAME,'grouplist','').' {sonos2mqtt($NAME,$EVENT)}')}
   return ''
}
# from here cmds for speaker
if($cmd eq 'sayText') { ($cmd,$text) = split(' ', $EVENT,2)}
my $uuid = ReadingsVal($NAME,'uuid','error');
my $topic = "$devicetopic/$uuid/control";
my $payload = $EVENT;
if (@arr == 1){$payload = "leer"} else {$payload =~ s/$cmd //}

# if Radio next Station
my $Input = ReadingsVal($NAME,'Input','');
if($cmd eq 'next' and $Input eq 'Radio') {
   fhem("set $NAME playFav {(Each('$bridge',ReadingsVal('$bridge','favlist','')))}");
   return ''
}
my @easycmd = ('stop','play','pause','toggle','volumeUp','volumeDown','next','previous');
if (grep { $_ eq $cmd } @easycmd) {return lc( qq($topic { "command": "$cmd" }) )}

if($cmd eq 'volume') {return qq($topic { "command": "volume", "input": $payload })}
if($cmd eq 'joinGroup') {return qq($topic { "command": "joingroup",  "input": "$payload"})}
if($cmd eq 'setAVTUri') {return qq($topic { "command": "setavtransporturi",  "input": "$payload"})}
if($cmd eq 'notify') {return qq($topic { "command":"notify","input":{"trackUri":"$arr[2]","onlyWhenPlaying":false,"timeout":100,"volume":$arr[1],"delayMs":700}})}

my %t=('true'=>'mute','false'=>'unmute');
if($cmd eq 'mute')   {return qq(sonos/$uuid/control { "command": "$t{$payload}" } )}
if($cmd eq 'input')  {
   $value = $payload eq "TV" ? "tv" : $payload eq "Line_In" ? "line" : "queue"; 
   return qq($topic { "command": "switchto$value" } ) 
}
if($cmd eq 'leaveGroup') {
   $value = ReadingsVal($uuid,"groupName","all");
   return qq($topic { "command": "leavegroup",  "input": "$value" } ) 
}
if($cmd eq 'playUri') {fhem("set $NAME setAVTUri $payload; sleep 1; set $NAME play")}
if($cmd eq 'sayText') {fhem("setreading $tts text ".ReadingsVal($tts,'text',' ').' '.$text.";sleep 0.4 tts;set $tts tts [$tts:text];sleep $tts:playing:.0 ;set $NAME notify [$tts:vol] [$tts:httpName];deletereading $tts text")}

# for tts-polly command set EG.KU.Sonos speak de-DE Vicki 25 Test
# test first of String like de-DE 
if($cmd eq 'speak') {
  if ($arr[1] =~ /^[a-z]{2}-[A-Z]{2}$/) { 
     my (undef, $lang, $voice, $volume, @text) = split(/ /, $EVENT); 
     return sprintf('%s {"command":"speak","input":{"lang": "%s", "name":"%s", "volume":%s, "text": "%s","delayMs":700}}', $topic, $lang, $voice, $volume, join(" ", @text));
  }
  else {
    ($cmd,$vol,$text) = split(' ', $EVENT,3);
    fhem("set $tts tts $text;sleep $tts:playing:.0 ;set $NAME notify $vol [$tts:httpName]");
  }
}
if($cmd eq 'playFav') {
    use JSON;use HTML::Entities;use Encode qw(encode decode);
    my $enc = 'UTF8';my $uri='';my $search=(split(' ', $EVENT,2))[1];
    $search=~s/[\/()]/./g;
    my $dev = (devspec2array('model=sonos2mqtt_bridge'))[0];
    my $decoded = decode_json(ReadingsVal($dev,'Favorites',''));
    my @array=@{$decoded->{'Result'}};
    for (@array) {
      if (encode($enc, decode_entities($_->{'Title'}))=~/$search/i)
         {$uri = $_->{'TrackUri'} }
   }
   fhem("set $NAME playUri $uri") if ($uri ne '');
}
if($cmd eq 'sleep') {
    $payload = strftime("%H:%M:%S",gmtime($payload*60));
    return qq($topic { "command": "sleep", "input": "$payload" }) 
}
if($cmd eq 'test') {Log 1, "Das Device $NAME hat ausgeloest, die uuid ist >$uuid< der Befehl war >$cmd< der Teil danach sah so aus: $payload"}
if($cmd eq 'x_raw_payload') {return qq($topic $payload)}
# if return for other reasons, the response had to be '' 0 or undef
return '';
}
####### devStateIcon
sub sonos2mqtt_devStateIcon
{
my ($name) = @_;
my $wpix = '210px';
my $master = ReadingsVal($name,'Master',$name);
my $inGroup = ReadingsNum($name,'inGroup','0');
my $isMaster = ReadingsNum($name,'isMaster','0');
my $inCouple = ReadingsNum($name,'inCouple','0');
my $Input = ReadingsVal($name,'Input','');
my $cover = ReadingsVal($name,'currentTrack_AlbumArtUri','');
my $mutecmd = ReadingsVal($name,'mute','0') eq 'false'?'true':'false';
my $mystate = $isMaster ? Value($name) : Value((devspec2array('DEF='.ReadingsVal($name,'coordinatorUuid','0')))[0]);
my $playpic = $mystate eq 'PLAYING'
  ? 'rc_PAUSE@red'    : $mystate eq 'PAUSED_PLAYBACK'
  ? 'rc_PLAY@green'   : $mystate eq 'STOPPED'
  ? 'rc_PLAY@green'   : $mystate eq 'TRANSITIONING'
  ? 'rc_PLAY@blue'    : 'rc_PLAY@yellow';
my $mutepic = $mutecmd eq 'true'?'rc_MUTE':'rc_VOLUP';
my $line2 = '';
my $title = $mystate eq 'TRANSITIONING' ? 'Puffern...' : ReadingsVal($name,'enqueuedMetadata_Title','FEHLER');
my $linePic = ($inGroup and !$isMaster and !$inCouple) ? "<a href=\"/fhem?cmd.dummy=set $name leaveGroup&XHR=1\">".FW_makeImage('rc_LEFT')."</a>" : "";
if ($isMaster) {$linePic .= " <a href=\"/fhem?cmd.dummy=set $name toggle&XHR=1\">".FW_makeImage($playpic)."</a>"};
   $linePic .= "&nbsp;&nbsp"
            ."<a href=\"/fhem?cmd.dummy=set $name volumeDown&XHR=1\">".FW_makeImage('rc_VOLDOWN')."</a>"
            ."<a href=\"/fhem?cmd.dummy=set $name previous&XHR=1\">".FW_makeImage('rc_PREVIOUS')."</a>"
            ."<a href=\"/fhem?cmd.dummy=set $name next&XHR=1\">".FW_makeImage('rc_NEXT')."</a>"
            ."<a href=\"/fhem?cmd.dummy=set $name volumeUp&XHR=1\">".FW_makeImage('rc_VOLUP')."</a>"
            ."&nbsp;&nbsp"
            ."<a href=\"/fhem?cmd.dummy=set $name mute $mutecmd&XHR=1\">".FW_makeImage($mutepic)."</a>";
if ($isMaster and $mystate eq 'PLAYING') {$line2 = $Input =~ /LineIn|TV/ ? $Input : "$title"}
    elsif ($inGroup and !$isMaster or $inCouple) {$line2 .= $inCouple ? "Stereopaar":"Steuerung: $master"}
my $style = 'display:inline-block;margin-right:5px;border:1px solid lightgray;height:4.00em;width:4.00em;background-size:contain;background-image:';
my $style2 ='background-repeat: no-repeat; background-size: contain; background-position: center center';
return "<div><table>
     <tr>
       <td><div style='$style url($cover);$style2'></div></td>
       <td>$linePic<br><div>$line2</div></td>
     </tr>
  </table></div>"
}

# usage sonos2mqtt_mod_list(devspec,attrName,line)
# usage {sonos2mqtt_mod_list('a:model=sonos2mqtt_bridge','readingList','sonos/RINCON_([0-9A-Z]+)/Reply:.* Reply')}
sub sonos2mqtt_mod_list
{
my ($devspec,$attr,$item) = @_;
my @devlist = devspec2array($devspec);
my ($first,$sec)=split(':',$item,2);
$first=~s/^\s+//;
for (@devlist) {
   my @arr = grep {$_ !~ /\Q$first\E/} split("\n",AttrVal($_,$attr,'')); # grep searches exactly for the string between \Q...\E
   push @arr,$item;
   my $val = join "\n",sort @arr;
   $val =~ s/;/;;/g;
   fhem("attr $_ $attr $val")
  }
return ''
}

#### Setup some additional features in speaker and bridge
sub sonos2mqtt_setup
{
my $devspec = shift @_ // 'a:model=sonos2mqtt_speaker';
my $bridge = (devspec2array('a:model=sonos2mqtt_bridge'))[0];

if ($devspec eq 'a:model=sonos2mqtt_bridge'){
   sonos2mqtt_mod_list($devspec,'setList','notifyall:textField'.q( {sonos2mqtt($NAME,$EVENT)}));
   sonos2mqtt_mod_list($devspec,'setList','announcementall:textField'.q( {sonos2mqtt($NAME,$EVENT)}));
   sonos2mqtt_mod_list($devspec,'readingList',AttrVal($bridge,"devicetopic",'sonos').'/RINCON_([0-9A-Z]+)/Favorites:.* Favorites');
   sonos2mqtt_mod_list($devspec,'readingList',AttrVal($bridge,"devicetopic",'sonos').'/RINCON_([0-9A-Z]+)/Reply:.* Reply');
   return undef
}

fhem("attr $devspec".q( devStateIcon {sonos2mqtt($name,'devStateIcon')}));
for ('stop:noArg','play:noArg','pause:noArg','toggle:noArg','volume:slider,0,1,100','volumeUp:noArg','volumeDown:noArg',
     'mute:true,false','next:noArg','previous:noArg','leaveGroup:noArg','setAVTUri:textField','playUri:textField',
     'notify:textField','x_raw_payload:textField','sayText:textField','speak:textField','input:Queue',
     'sleep:selectnumbers,0,15,120,0,lin') {
           sonos2mqtt_mod_list($devspec,'setList',$_.q( {sonos2mqtt($NAME,$EVENT)}));
    }
my @tv   = ("S14","S11","S9");
my @line = ("S5","Z90","ZP120");
# to get the Favorites at this point is only a workaround. Bad for the first player
if (!ReadingsVal($bridge,'favlist',0)) {my $fav = fhem("get $bridge Favorites")}
for (devspec2array($devspec)) {
    my $mn = ReadingsVal($_,'modelNumber','');
    fhem("set $_ volume ".ReadingsVal($_,'volume','10')); # trick to initiate the userReadings 
    if (grep {/$mn/} @tv) {sonos2mqtt_mod_list($_,'setList','input:Queue,TV'.q( {sonos2mqtt($NAME,$EVENT)}))}
    if (grep {/$mn/} @line) {sonos2mqtt_mod_list($_,'setList','input:Queue,Line_In'.q( {sonos2mqtt($NAME,$EVENT)}))}
    sonos2mqtt_mod_list($_,'setList','joinGroup:'.ReadingsVal($bridge,'grouplist','').q( {sonos2mqtt($NAME,$EVENT)}));
    sonos2mqtt_mod_list($_,'setList','playFav:'.ReadingsVal($bridge,'favlist','').q( {sonos2mqtt($NAME,$EVENT)}));
  }
return ''
}

#### code for notify for two different triggers: defined and IPAddress is responded 
# delete n_configSonos.
# defmod n_configSonos notify global:DEFINED.MQTT2_RINCON_[A-Z0-9]+|MQTT2_RINCON_[A-Z0-9]+:IPAddress:.* {sonos2mqtt_nty($NAME,$EVENT)}
# for Test use "test $EVENT"
sub sonos2mqtt_nty
{
my ($NAME,$EVENT) = @_;
my @arr = split(' ',$EVENT);
if ($arr[0] eq 'test') {Log 1, "Device $NAME, EVENT >$EVENT<";shift @arr}
if ($NAME eq 'global'){
      fhem(qq(sleep 1; set $arr[1] attrTemplate sonos2mqtt_speaker))
   }
 else{
      my $url="http://$arr[1]:1400";
      my $xmltext = GetFileFromURL("$url/xml/device_description.xml");
      my ($mn)=$xmltext =~ /<modelNumber>([SZ]P?[0-9]{1,3})/;
      my ($img)=$xmltext =~ /<url>(.*)<\/url>/;
      my $icon="Sonos2mqtt_icon-$mn";
      fhem("setreading $NAME modelNumber $mn");
      fhem("\"wget -qO ./www/images/default/$icon.png $url$img\"");
      fhem("attr $NAME icon $icon;sleep 4 WI;set WEB rereadicons");
      sonos2mqtt_setup($NAME);
   }
return ''
}

#### sub for userReadings
#
sub sonos2mqtt_ur
{
my $name = shift @_ // 'name';
my $reading = shift @_ // 'reading';
my @out;

if ($reading eq 'grouplist'){
   for (devspec2array('a:model=sonos2mqtt_speaker')) {
     if (ReadingsVal($_,'isMaster','')) {
        push @out,ReadingsVal($_,'name','')
     }
   }
  return join(',', sort @out)
}
if ($reading eq 'favlist'){
   use JSON;
   use HTML::Entities;
   use Encode qw(encode decode);
   my $enc = 'UTF8';
   my $decoded = decode_json(ReadingsVal($name,'Favorites',''));
   my @arr  = @{$decoded->{'Result'}};
   for (@arr) {
     my $dec = encode($enc, decode_entities($_->{'Title'}));
     $dec =~ s/\s/./g;
     if ($_->{'TrackUri'} =~ /x-sonosapi-stream/) {push @out,$dec}
   }
  return join ',', sort @out
}

if ($reading eq 'Input') {
   my $currentTrack_TrackUri = ReadingsVal($name,'currentTrack_TrackUri','');
   return $currentTrack_TrackUri =~ 'x-rincon-stream'
      ? 'LineIn': $currentTrack_TrackUri =~ 'spdif'
      ? 'TV'    : ReadingsVal($name,'enqueuedMetadata_UpnpClass','') eq 'object.item.audioItem.audioBroadcast'
      ? 'Radio' : 'Playlist'
  }
}

1;
=pod
=begin html
Some Subroutines for generic MQTT2 Sonos Devices based on sonos2mqtt.
=end html
=begin html_DE
Enthaelt einige Subroutinen fuer generische MQTT2 Sonos Geraete auf Basis von sonos2mqtt.
=end html_DE
=cut

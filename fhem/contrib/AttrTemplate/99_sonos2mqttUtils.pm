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

sub sonos2mqtt
{ 
my ($NAME,$EVENT)=@_;
my @arr = split(' ',$EVENT);
my ($cmd,$vol,$text,$value);
$cmd = $arr[0];

if($cmd eq 'devStateIcon') {return sonos2mqtt_devStateIcon($NAME)}

my $bridge = (devspec2array('a:model=sonos2mqtt_bridge'))[0];
my $tts = ReadingsVal($bridge,'tts','SonosTTS');
if($cmd eq 'sayText') { ($cmd,$text) = split(' ', $EVENT,2)}
if($cmd eq 'speak') { ($cmd,$vol,$text) = split(' ', $EVENT,3)}
my $uuid = ReadingsVal($NAME,'uuid','error');
my $topic = "sonos/$uuid/control";
my $payload = $EVENT;
if (@arr == 1){$payload = "leer"} else {$payload =~ s/$cmd //}

my @easycmd = ('stop','play','pause','toggle','volumeUp','volumeDown','next','previous');
if (grep { $_ eq $cmd } @easycmd) {return lc( qq($topic { "command": "$cmd" }) )}

if($cmd eq 'volume') {return qq(sonos/$uuid/control { "command": "volume", "input": $payload })}
if($cmd eq 'joinGroup') {return qq(sonos/$uuid/control { "command": "joingroup",  "input": "$payload"})}
if($cmd eq 'setAVTUri') {return qq(sonos/$uuid/control { "command": "setavtransporturi",  "input": "$payload"})}
# alternativ code for the last two lines
#my %t=('joinGroup'=>'joingroup','setAVTUri'=>'setavtransporturi');
#if (grep { $_ eq $cmd } %t) {return qq(sonos/$uuid/control { "command": "$t{$cmd}", "input": "$payload" })}

if($cmd eq 'notify') {return qq(sonos/$uuid/control { "command":"notify","input":{"trackUri":"$arr[2]","onlyWhenPlaying":false,"timeout":100,"volume":$arr[1],"delayMs":700}})}
if($cmd eq 'x_raw_payload') {return qq(sonos/$uuid/control $payload)}

#%t=('true'=>'mute','false'=>'unmute');
#if($cmd eq 'mute')   {return qq(sonos/$uuid/control { "command": "$t{$payload}" } )}
if($cmd eq 'mute')   {$value = $payload eq "true" ? "mute" : "unmute"; return qq(sonos/$uuid/control { "command": "$value" } )}
#%t=('TV'=>'tv','Line_In'=>'line','Queue'=>'queue');
#if($cmd eq 'input')  {return qq(sonos/$uuid/control { "command": "switchto$t{$payload}" } ) }
if($cmd eq 'input')  {$value = $payload eq "TV" ? "tv" : $payload eq "Line_In" ? "line" : "queue"; return qq(sonos/$uuid/control { "command": "switchto$value" } ) }

if($cmd eq 'leaveGroup') {$value = ReadingsVal($uuid,"groupName","all"); return qq(sonos/$uuid/control { "command": "leavegroup",  "input": "$value" } ) }

if($cmd eq 'playUri') {fhem("set $NAME setAVTUri $payload; sleep 1; set $NAME play")}
if($cmd eq 'sayText') {fhem("setreading $tts text ".ReadingsVal($tts,'text',' ').' '.$text.";sleep 0.4 tts;set $tts tts [$tts:text];sleep $tts:playing:.0 ;set $NAME notify [$tts:vol] [$tts:httpName];deletereading $tts text")}
if($cmd eq 'speak') {fhem("set $tts tts $text;sleep $tts:playing:.0 ;set $NAME notify $vol [$tts:httpName]")}
if($cmd eq 'playFav') {
	use JSON;use HTML::Entities;use Encode qw(encode decode);
	my $enc = 'UTF8';my $uri='';my $search=(split(' ', $EVENT,2))[1];
	$search=~s/[\/()]/./g;
	my $dev = (devspec2array('model=sonos2mqtt_bridge'))[0];
	my $decoded = decode_json(ReadingsVal($dev,'Favorites',''));
	my @array=@{$decoded->{'Result'}};
	foreach (@array) {if (encode($enc, decode_entities($_->{'Title'}))=~/$search/i)
	                   {$uri = $_->{'TrackUri'} }
		    };
			fhem("set $NAME playUri $uri") if ($uri ne '');
}

if($cmd eq 'test') {Log 1, "Das Device $NAME hat ausgeloest, die uuid ist >$uuid< der Befehl war >$cmd< der Teil danach sah so aus: $payload"}

return undef;
}
#######
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
"<div><table>
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
foreach (@devlist) {
   my @arr = grep {$_ !~ $first} split("\n",AttrVal($_,$attr,''));
   push @arr,$item;
   my $val = join "\n",sort @arr;
   $val =~ s/;/;;/g;
   fhem("attr $_ $attr $val")}
}

sub sonos2mqtt_setup
{
my $devspec = shift @_ // 'a:model=sonos2mqtt_speaker';
my $bridge = (devspec2array('a:model=sonos2mqtt_bridge'))[0];
fhem("attr $devspec".q( devStateIcon {sonos2mqtt($name,'devStateIcon')}));
sonos2mqtt_mod_list('a:model=sonos2mqtt_bridge','readingList','sonos/RINCON_([0-9A-Z]+)/Reply:.* Reply');
for ('stop:noArg','play:noArg','pause:noArg','toggle:noArg','volumeUp:noArg','volumeDown:noArg','volume:slider,0,1,100',
     'mute:true,false','next:noArg','previous:noArg','leaveGroup:noArg','setAVTUri:textField','playUri:textField',
     'notify:textField','x_raw_payload:textField','sayText:textField','speak:textField','input:Queue') {
           sonos2mqtt_mod_list($devspec,'setList',$_.q( {sonos2mqtt($NAME,$EVENT)}));
    }

my @tv = ("S14","S11","S9");
my @line = ("S5","Z90","ZP120");
for (devspec2array($devspec)) {
    my $mn = ReadingsVal($_,'modelNumber','');
    fhem("set $_ volume ".ReadingsVal($_,'volume','10')); # trick to initiate the userReadings 
    if (grep(/$mn/, @tv)) {sonos2mqtt_mod_list($_,'setList','input:Queue,TV'.q( {sonos2mqtt($NAME,$EVENT)}))}
    if (grep(/$mn/, @line)) {sonos2mqtt_mod_list($_,'setList','input:Queue,Line_In'.q( {sonos2mqtt($NAME,$EVENT)}))}
    sonos2mqtt_mod_list($_,'setList','joinGroup:'.ReadingsVal($bridge,'grouplist','').q( {sonos2mqtt($NAME,$EVENT)}));
    sonos2mqtt_mod_list($_,'setList','playFav:'.ReadingsVal($bridge,'favlist','').q( {sonos2mqtt($NAME,$EVENT)}));
  }
}

# delete n_configSonos.
# defmod n_configSonos notify global:DEFINED.MQTT2_RINCON_[A-Z0-9]+|MQTT2_RINCON_[A-Z0-9]+:IPAddress:.* {sonos2mqtt_nty($NAME,$EVENT)}
# for Test use "test $EVENT"
sub sonos2mqtt_nty
{
my ($NAME,$EVENT) = @_;
my @arr = split(' ',$EVENT);
if ($arr[0] eq 'test') {Log 1, "Device $NAME, EVENT >$EVENT<";shift @arr}
if ($NAME eq 'global'){
      fhem(qq(sleep 1; set $arr[1] attrTemplate sonos2mqtt_speaker; set $arr[1] x_raw_payload {"command": "adv-command","input": {"cmd":"GetZoneInfo","reply":"ZoneInfo"}}))
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
}

1;

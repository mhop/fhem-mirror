##############################################
# 95_remotecontrol
# $Id: $
#
################################################################
#
#  Copyright notice
#
#  (c) 2013 Copyright: Ulrich Maass
#
#  This file is part of fhem.
# 
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
# 
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# 
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#  Disclaimer: The Author takes no responsibility whatsoever 
#  for damages potentially done by this program.
#
################################################################################
#
# Implementation:
# 1 - set WEB rereadicons
# 2 - define rc1 remotecontrol    (defines fresh remotecontrol, has no keys defined yet)
# 3a- get rc1 layout              (display list of available "keybiard"-layouts)
# 3 - set rc1 layout samsung      (assigns standard-key-layout for e.g. samsungTV)
# 4 - set rc1 makeweblink         (creates a weblink weblink_rc1)
# 4a- for testing: attr rc1 room TestRemote , attr weblink_rc1 room TestRemote
# 5 - set rc1 makenotify <executingDevice> (creates a notify of the form: define notify_rc1 notify rc1 set <executingDevice> $EVENT)
#
# Published June 23, 2013
# bugfix "use strict" upon foreign makenotify - June 24, 2013
# converted to UNIX-LF - June 25, 2013
# fixed minor html-bug - June 26, 2013
# added css-tags rc_body and rc_button - June 27, 2013
# deleted leading \n at beginning of html-code - June 30, 2013
# fhemweb-detailscreen of remotecontrol now displays a preview, added htmlNoTable for RC_attr2html(), added RC_summaryFn incl attr rc_devStateIcon


package main;
use strict;
use warnings;

#########################
# Forward declaration
sub RC_Define();
sub RC_Set($@);
sub RC_Get($@);
sub RC_Attr(@);
sub RC_array2attr($@);
sub RC_attr2html($@);
sub RC_layout_delete($);
sub RC_layout_samsung();
sub RC_layout_itunes();
sub RC_detailFn($$$$);
sub RC_webCmdFn($$$);
sub RC_summaryFn($$$$);

#####################################
# Initialize module
sub
remotecontrol_Initialize($)
{
  my ($hash) = @_;
  $hash->{GetFn}                 = "RC_Get";
  $hash->{SetFn}                 = "RC_Set";
  $hash->{AttrFn}                = "RC_Attr";
  $hash->{DefFn}                 = "RC_Define";
  $hash->{AttrList}              = "rc_iconpath rc_iconprefix loglevel:0,1,2,3,4,5,6 rc_devStateIcon:0,1 ".
                                   "row00 row01 row02 row03 row04 row05 row06 row07 row08 row09 ".
                                   "row10 row11 row12 row13 row14 row15 row16 row17 row18 row19";
  $hash->{FW_detailFn}           = "RC_detailFn";           # displays rc preview in fhemweb detail-screen 
  $hash->{FW_summaryFn}          = "RC_summaryFn";          # displays rc instead of status icon in fhemweb room-view
  $data{webCmdFn}{remotecontrol} = "RC_webCmdFn";           # displays rc instead of device-commands on the calling device

  $data{RC_layout}{samsung}      = "RC_layout_samsung";
  $data{RC_layout}{itunes}       = "RC_layout_itunes";
  
# $data{RC_layout}{enigma}       = "RC_layout_enigma";
# $data{RC_makenotify}{enigma}   = "RC_makenotify_enigma";

}


#####################################
# Initialize every new instance
sub
RC_Define() 
{
  my ($hash, $def) = @_;
  $hash->{STATE}       = "initialized";
  $hash->{".htmlCode"} = "";
  return undef;
}


#####################################
# Ensure htmlcode is created from scratch after an attribute value has been changed
sub 
RC_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  $hash->{".htmlCode"} = "";
  return;
}


#####################################
# Digest set-commands
sub
RC_Set($@)
{
  my ($hash, @a) = @_;
  my $nam = $a[0];
  my $cmd = (defined($a[1]) ? $a[1] : ""); #command
  my $par = (defined($a[2]) ? $a[2] : ""); #parameter
  
  ## set layout
  if ($cmd eq "layout") {
    if ($par eq "delete") {
      RC_layout_delete($nam);
      $hash->{".htmlCode"} = "";
    } else {    # layout
      my $layoutlist = "";
      my @rows;
      foreach my $fn (sort keys %{$data{RC_layout}}) {
        $layoutlist .= $fn."\n";
        next if ($fn ne $par);
        no strict "refs";
        @rows = &{$data{RC_layout}{$fn}}($fn);
        use strict "refs";
      }
      if ($#rows > 0) {
         RC_layout_delete($nam);
         RC_array2attr($nam, @rows);
         $hash->{".htmlCode"} = "";
      } else {
        return "Missing or invalid parameter \"$par\" for set ... layout. Use one of\n".
             "delete\n".$layoutlist;
      }
    }
  ## set makeweblink
  } elsif ($cmd eq "makeweblink") {
    my $wname = $a[2] ? $a[2] : "weblink_".$nam;
    fhem("define $wname weblink htmlCode {fhem(\"get $hash->{NAME} htmlcode\", 1)}");
    Log 2, "[remotecontrol] Weblink created: $wname";
    return "Weblink created: $wname";
  ## set makenotify
  } elsif ($cmd eq "makenotify") {
    if ($a[2]) {
      my $ndev = $a[2];
      my $fn = $defs{$ndev}{TYPE} ? $defs{$ndev}{TYPE} : undef;
      if (defined($fn) && defined($data{RC_makenotify}{$fn})) {   #foreign makenotify
        no strict "refs";
        my $msg = &{$data{RC_makenotify}{$fn}}($nam,$ndev);
        use strict "refs";
        return $msg;
      } else {
        my $nname="notify_$nam";
        fhem("define $nname notify $nam set $ndev ".'$EVENT',1);
        Log 2, "[remotecontrol] Notify created: $nname";
        return "Notify created: $nname";
      }
    } else {
      return "set $nam makenotify <executingdevice>:\n name of executing device missing.";    
    }
  ## set ?
  } elsif ($cmd eq "?") {
    my $ret = "Unknown argument $cmd choose one of makeweblink makenotify state .remotecontrol:remotecontrol layout:";
    foreach my $fn (sort keys %{$data{RC_layout}}) {
      $ret .= $fn . ",";
    }
    $ret =~ s/[:,]$//;
    return $ret;
  ## set state <command>
  } else {
    Log GetLogLevel($nam,4), "[remotecontrol] set $nam $cmd $par";
    readingsSingleUpdate($hash,"state",$cmd,1) if (!$par);
  }
}


#####################################
# Digest get-commands
sub
RC_Get($@)
{
  my ($hash, @a) = @_;
  my $arg = (defined($a[1]) ? $a[1] : ""); #command
  my $name = $hash->{NAME};

  ## get htmlcode
  if($arg eq "htmlcode") {
    $hash->{".htmlCode"} = RC_attr2html($name) if ($hash->{".htmlCode"} eq "");
    return $hash->{".htmlCode"};
  ## get layout
  } elsif ($arg eq "layout") {
    my $layoutlist = "Available predefined layouts are:\n";
    foreach my $fn (sort keys %{$data{RC_layout}}) {
    $layoutlist .= $fn."\n";
    }
    return $layoutlist;
  ## get -> error
  } else {
    return "Unknown argument $arg choose one of: htmlcode layout";
  }
}


#####################################
# Convert all rowXX-attribute-values into htmlcode
sub
RC_attr2html($@) {
  my ($name,$htmlNoTable) = @_;
  my $iconpath   = AttrVal("$name","rc_iconpath","icons/remotecontrol");
  my $iconprefix = AttrVal("$name","rc_iconprefix","");
  my $rc_html;
  my $row;
  $rc_html = "<div class=\"remotecontrol\">";
# $rc_html = "<div class=\"remotecontrol\" id=\"$name\">"; # provokes update by longpoll
  $rc_html.= '<table class="rc_body">' if (!$htmlNoTable);
  foreach my $rownr (0..19) {
    $rownr = sprintf("%2.2d",$rownr);
    $row   = AttrVal("$name","row$rownr",undef);
    next if (!$row);
    $rc_html .= "<tr>\n" if (!$htmlNoTable);
    my @btn = split (",",$row);
    foreach my $btnnr (0..$#btn) {
      $rc_html .= '<td class="rc_button">';# if (!$htmlNoTable);
      if ($btn[$btnnr] ne "") {
        my $cmd;
        my $img;
        if ($btn[$btnnr] =~ /(.*?):(.*)/) {    # button has format <command>:<image>
          $cmd = $1;
          $img = $2;
        } else {                               # button has format <command> or is empty
          $cmd = $btn[$btnnr];
          $img = $btn[$btnnr];
        }
		if ($img =~ m/\.svg/) {                # convert svg-images
		   $img = FW_makeImage($img, $cmd, "rc-button");
		} else {
          $img      = "<img src=\"$FW_ME/$iconpath/$iconprefix$img\">";
		}
        if ($cmd || $cmd eq "0") {
          $cmd      = "cmd.$name=set $name $cmd";
          $rc_html .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a>";
        } else {
          $rc_html .= $img;
        }
      }
      $rc_html .= "</td>";# if (!$htmlNoTable);
      $rc_html .= "\n";    
    }
    $rc_html .= "</tr>\n" if (!$htmlNoTable);
  }
  $rc_html .= "</table>" if (!$htmlNoTable);
  $rc_html .= "</div>";
  return $rc_html;
}


#####################################
# Delete all rowXX-attributes
sub 
RC_layout_delete($) {
  my $name = shift;
  foreach my $rownr (0..19) {
    $rownr = sprintf("%2.2d",$rownr);
    fhem("deleteattr $name row$rownr",1);
  }
}


#####################################
# Convert array-values into rowXX-attribute-values
sub 
RC_array2attr($@)
{
  my ($name, @row) = @_;
  my $ret;
  foreach my $rownr (0..21) {
    next if (!$row[$rownr]);
    $rownr = sprintf("%2.2d",$rownr);
    if ($row[$rownr] =~ m/^attr (.*?)\s(.*)/) {
      $ret = fhem("attr $name $1 $2");
    } else {
      $ret = fhem("attr $name row$rownr $row[$rownr]") if ($row[$rownr]);
    }
  }
}


##################
#remotecontrol-specific fhemweb detail-screen
sub 
RC_detailFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  $hash->{".htmlCode"} = RC_attr2html($d) if ($hash->{".htmlCode"} eq "");
  return $hash->{".htmlCode"};
}


##################
#remotecontrol-specific webCmdFn to be used
# calling module needs to provide ".remotecontrol:remotecontrol" in its return to 'set <device> ?'
sub
RC_webCmdFn($$$) {
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;
  return undef if($values !~ m/remotecontrol/);
  my @args = split("[ \t]+", $cmd);
  return RC_attr2html($args[1],1) if ($args[1]);
  return undef;
}


##################
#remotecontrol-specific summaryFn to be used
# displays the remote on the remote-device itself in FHEMWEB room-overview
sub
RC_summaryFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $name = $hash->{NAME};
  return undef if (AttrVal($name,"rc_devStateIcon",1) != 1);
  return RC_attr2html($name);
}


#####################################
# Default-layout for samsung
sub 
RC_layout_samsung() {
  my $ret;
  my @row;
  $row[0]="POWEROFF,TV,HDMI";
  $row[1]=":blank,:blank,:blank";
  $row[2]="1,2,3";
  $row[3]="4,5,6";
  $row[4]="7,8,9";
  $row[5]=":blank,0,PRECH";
  $row[6]=":blank,:blank,:blank";
  $row[7]="VOLUP:UP,MUTE,CHUP";
  $row[8]=":VOL,:blank,:PROG";
  $row[9]="VOLDOWN:DOWN,CH_LIST,CHDOWN";
  $row[10]="MENU,:blank,GUIDE";
  $row[11]=":blank,:blank,:blank";
  $row[12]="TOOLS,UP,INFO";
  $row[13]="LEFT,ENTER,RIGHT";
  $row[14]="RETURN,DOWN,EXIT";
  $row[15]="attr rc_iconpath icons/remotecontrol";
  $row[16]="attr rc_iconprefix black_btn_";
  # unused available commands
  # AD PICTURE_SIZE  SOURCE
  # CONTENTS W_LINK
  # RSS MTS SRS CAPTION TOPMENU SLEEP ESAVING
  # PLAY PAUSE REWIND FF REC STOP
  # PIP_ONOFF ASPECT
  return @row;
}


#####################################
# Default-layout for itunes
sub 
RC_layout_itunes() {
  my $ret;
  my @row;
  $row[0]="play:PLAY,pause:PAUSE,prev:REWIND,next:FF,quieter:VOLDOWN,louder:VOLUP";
  $row[1]="attr rc_iconpath icons/remotecontrol";
  $row[2]="attr rc_iconprefix black_btn_";
  # unused available commands
  return @row;
}


1;


=pod
=begin html

<a name="remotecontrol"></a>
<h3>remotecontrol</h3>
<ul>
  Displays a graphical remote control. Buttons (=icons) can be chosen and arranged. Predefined layouts are available for e.g. Samsung-TV or iTunes.
  Any buttonclick can be forwarded to the actual fhem-device. For further explanation, please check the <a href="http://www.fhemwiki.de/wiki/Remotecontrol">Wiki-Entry</<>.<br>

  <a name="remotecontroldefine"></a><br>
  <b>Define</b>
  <ul>
    <code>define &lt;rc-name&gt; remotecontrol</code><br><br>
      Typical steps to implement a remotecontrol:<br>
    <table>
    <tr><td><code>define rc1 remotecontrol</code></td><td><code># defines a "blank" remotecontrol</code></td></tr>
    <tr><td><code>get rc1 layout</code></td><td><code># displays all available predefined layouts</code></td></tr>
    <tr><td><code>set rc1 layout samsung</code></td><td><code># assigns keys for a SamsungTV</code></td></tr>
    <tr><td><code>set rc1 makenotify myTV</code></td><td><code># creates notify_rc1 which forwards every buttonclick to myTV for execution</code></td></tr>
    <tr><td colspan="2"><b>Note:</b> keys can be changed at any time, it is not necessary to redefine the weblink</td></tr>
    <tr><td><code>attr rc1 row15 VOLUP,VOLDOWN</code></td></tr>
    </table>
  </ul>

  <a name="remotecontrolset"></a><br>
  <b>Set</b>
  <ul>
    <li><code>set &lt;rc-name&gt; layout [delete|&lt;layoutname&gt;]</code><br>
    <code>layout delete</code> deletes all rowXX-attributes<br>
    <code>layout &lt;layoutname&gt;</code> assigns a predefined layout to rowXX-attributes</li>
    <li><code>set &lt;rc-name&gt; makeweblink [&lt;name&gt;]</code><br>
    creates a weblink to display the graphical remotecontrol. Default-name is weblink_&lt;rc-name&gt; .</li>
    <li><code>set &lt;rc-name&gt; makenotify &lt;executingDevice&gt;</code><br>
    creates a notify to trigger &lt;executingDevice&gt; every time a button has been pressed. name is notify_&lt;rc-name&gt; .</li>
  </ul>
  
  <a name="remotecontrolget"></a><br>
  <b>Get</b>
  <ul>
    <code>get &lt;rc-name&gt; [htmlcode|layout]</code><br>
    <li><code>htmlcode</code> displays htmlcode for the remotecontrol on fhem-page</li>
    <li><code>layout</code> shows which predefined layouts ae available</li>
  </ul>
  
  <a name="remotecontrolattr"></a><br>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a name="rc_iconpath">rc_iconpath</a><br>
      path for icons, default is "icons" . The attribute-value will be used for all icon-files except .svg .</li>
    <li><a name="rc_iconprefix">rc_iconprefix</a><br>
      prefix for icon-files, default is "" . The attribute-value will be used for all icon-files except .svg .</li>
    <li>Note: Icon-names (button-image-file-names) will be composed as <code>fhem/&lt;rc_iconpath&gt;/&lt;rc_iconprefix&gt;&lt;command|image&gt;</code><br>
	For .svg -icons, the access sequence is according to the FHEMWEB-attribute iconPath, default is openautomation:fhemSVG:default .</li>
    <li><a name="rc_devStateIcon">rc_devStateIcon</a><br>
    In FHEMWEB-room-overview, displays the button-layout on the rc-device itself. Default is 1, set to 0 is the remotecontrol-device should not display its buttons in FHEMWEB roomview.</li>
    <br>
    <li><a href="#rowXX">rowXX</a><br>
    <code>attr &lt;rc-name&gt; rowXX &lt;command&gt;[:&lt;image&gt;][,&lt;command&gt;[:&lt;image&gt;]][,...]</code><br>
    Comma-separated list of buttons/images per row. Any number of buttons can be placed in one row. For each button, use</li>
    <ul>
      <li><code>&lt;command&gt;</code> is the command that will trigger the event after a buttonclick. Case sensitive.</li>
      <li><code>&lt;image&gt;</code> is the filename of the image</li><br>
      <li>Per button for the remotecontrol, use</li>
      <li><code>&lt;command&gt;</code> where an icon with the name <rc_iconprefix>&lt;command&gt; is displayed<br>
      Example:<br>
        <code>attr rc1 rc_iconprefix black_btn_  # used for ALL icons on remotecontrol rc1</code><br>
        <code>attr rc1 row00 VOLUP </code><br>
               icon is <code>black_btn_VOLUP</code>, a buttonclick creates the event <code>VOLUP</code>
      </li>
      or
      <li><code>&lt;command&gt;:&lt;image&gt;</code> where an icon with the name <code>&lt;rc_iconprefix&gt;&lt;image&gt;</code> is displayed<br>
        Example: <br>
         <code>row00=LOUDER:VOLUP</code><br>
         icon is <code>black_btn_VOLUP</code>, a buttonclick creates the event <code>LOUDER</code>
        <br>
        Examples:<br>
        <code>attr rc1 row00 1,2,3,TV,HDMI</code><br>
        <code>attr rc2 row00 play:PLAY,pause:PAUSE,louder:VOLUP,quieter:VOLDOWN</code><br>
      </li>
      <li><b>Hint:</b> use :blank for a blank space, use e.g. :blank,:blank,:blank for a blank row</li>
    </ul>
  </ul>
</ul>

=end html
=begin html_DE

<a name="remotecontrol"></a>
<h3>remotecontrol</h3>
<ul>
  Erzeugt eine graphische Fernbedienung. Buttons (=icons) können frei ausgewählt und angeordnet werden. Vordefinierte layouts sind verfügbar für z.B. Samsung-TV und iTunes.
  Jeder "Knopfdruck" kann an das entsprechende fhem-Gerät weitergegeben werden.<br>
  Weitere Erklaerungen finden sich im <a href="http://www.fhemwiki.de/wiki/Remotecontrol">Wiki-Eintrag</<>.<br>

  <a name="remotecontroldefine"></a><br>
  <b>Define</b>
  <ul>
    <code>define &lt;rc-name&gt; remotecontrol</code><br><br>
      Typische Schritte zur Einrichtung:<br>
    <table>
    <tr><td><code>define rc1 remotecontrol</code></td><td><code># erzeugt eine "leere" remotecontrol</code></td></tr>
    <tr><td><code>get rc1 layout</code></td><td><code># zeigt alle vorhandenen vordefinierten layouts an</code></td></tr>
    <tr><td><code>set rc1 layout samsung</code></td><td><code># laedt das layout für SamsungTV</code></td></tr>
    <tr><td><code>set rc1 makenotify myTV</code></td><td><code># erzeugt notify_rc1, das jeden Tastendruck an myTV weitergibt</code></td></tr>
    <tr><td colspan="2"><b>Hinweis:</b>die Tastenbelegung kann jederzeit geaendert werden, ohne dass der weblink erneut erzeugt werden muss.</td></tr>
    <tr><td><code>attr rc1 row15 VOLUP,VOLDOWN</code></td></tr>
    </table>
  </ul>

  <a name="remotecontrolset"></a><br>
  <b>Set</b>
  <ul>
    <li><code>set &lt;rc-name&gt; layout [delete|&lt;layoutname&gt;]</code><br>
    <code>layout delete</code> loescht alle rowXX-Attribute<br>
    <code>layout &lt;layoutname&gt;</code> laedt das  vordefinierte layout in die rowXX-Attribute</li>
    <li><code>set &lt;rc-name&gt; makeweblink [&lt;name&gt;]</code><br>
    erzeugt einen weblink zur Anzeige der remotecontrol in FHEMWEB oder FLOORPLAN. Default-Name ist weblink_&lt;rc-name&gt; .</li>
    <li><code>set rc1 makenotify mySamsungTV</code><br>
    erzeugt <code>notify_rc1</code> das jeden Tastendruck an mySamsungTV zur Ausfuehrung weitergibt</li>
  </ul>
  
  <a name="remotecontrolattr"></a><br>
  <b>Attribute</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a name="rc_iconpath">rc_iconpath</a><br>
      Pfad für icons, default ist "icons" . Der Attribut-Wert wird für alle icon-Dateien verwendet ausser .svg .</li>
    <li><a name="rc_iconprefix">rc_iconprefix</a><br>
      Prefix für icon-Dateien, default ist "" . Der Attribut-Wert wird für alle icon-Dateien verwendet ausser .svg .</li>
    <li>Note: Icon-Namen (Tasten-Bild-Datei-Namen) werden zusammengesetzt als fhem/&lt;rc_iconpath&gt;/&lt;rc_iconprefix&gt;&lt;command|image&gt;<br>
	Fuer .svg -icons ist die Zugriffsfolge gemaess dem FHEMWEB-Attribut iconPath, default ist openautomation:fhemSVG:default .
	</li>
    <li><a name="rc_devStateIcon">rc_devStateIcon</a><br>
    Zeigt das button-layout auf dem remotecontrol-device selbst in der FHEMWEB-Raumansicht an. Default ist 1, durch setzen auf 0 erscheint in der FHEMWEB-Raumansciht nicht das layout, sondern nur der Status "Initialized".</li>
    <br>

    <li><a href="#rowXX">rowXX</a><br>
    <code>attr &lt;rc-name&gt; rowXX &lt;command&gt;[:&lt;image&gt;]</code><br>
    Komma-separarierte Liste von Tasten/Icons je Tastaturzeile. Eine Tastaturzeile kann beliebig viele Tasten enthalten.</li><br>
    <li>&lt;command&gt; ist der event, der bei Tastendruck ausgelöst wird. Gross/Kleinschreibung beachten.</li>
    <li>&lt;image&gt; ist der Dateiname des als Taste angezeigten icons</li>
    <li>Verwenden Sie je Taste</li>
    <li>&lt;command&gt; wobei als Taste/icon <code><rc_iconprefix>&lt;command&gt;</code> angezeigt wird<br>
     Beispiel:<br>
     <code>attr rc1 rc_iconprefix black_btn_  # gilt für alle Tasten/icons</code><br>
     <code>attr rc1 row00 VOLUP</code><br>
        -> icon ist <code>black_btn_VOLUP</code>, ein Tastendruck erzeugt den event <code>VOLUP</code>
    </li><br>
    oder
    <li>&lt;command&gt;:&lt;image&gt; wobei als Taste/icon &lt;rc_iconprefix&gt;&lt;image&gt; angezeigt wird.<br>
      Beispiel:<br>
      <code>attr rc1 row00 LOUDER:VOLUP</code><br>
      icon ist black_btn_VOLUP, ein Tastendruck erzeugt den event LOUDER<br>
      Beispiele:
        <code>attr rc1 row00 1,2,3,TV,HDMI</code><br>
        <code>attr rc2 row00 play:PLAY,pause:PAUSE,louder:VOLUP,quieter:VOLDOWN</code><br>
    </li>
    <li><b>Hinweis:</b> verwenden Sie :blank für eine 'leere Taste', oder z.B. :blank,:blank,:blank für eine Abstands-Leerzeile.</li>
  </ul>
</ul>

=end html_DE
=cut



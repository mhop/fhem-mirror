#############################################
# $Id$
# 
# This file is part of fhem.
# 
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################


package main;
use strict;
use warnings;
use Time::Local;

sub DOIFtools_Initialize($);
sub DOIFtools_Set($@);
sub DOIFtools_Get($@);
sub DOIFtools_Undef;
sub DOIFtools_Define($$$);
sub DOIFtools_Attr(@);
sub DOIFtools_Notify($$);
sub DOIFtoolsRg;
sub DOIFtoolsNxTimer;
sub DOIFtoolsNextTimer;
sub DOIFtoolsGetAssocDev;
sub DOIFtoolsCheckDOIF;
sub DOIFtoolsCheckDOIFcoll;
sub DOIFtools_fhemwebFn($$$$);
sub DOIFtools_eM($$$$);
sub DOIFtools_dO ($$$$);
sub DOIFtoolsSetNotifyDev;
sub DOIFtools_logWrapper($);
sub DOIFtoolsCounterReset($);

my @DOIFtools_we =();


#########################
sub DOIFtools_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "DOIFtools_Define";
  $hash->{SetFn}   = "DOIFtools_Set";
  $hash->{GetFn}   = "DOIFtools_Get";
  $hash->{UndefFn}  = "DOIFtools_Undef";
  $hash->{AttrFn}   = "DOIFtools_Attr";
  $hash->{NotifyFn} = "DOIFtools_Notify";
  
  $hash->{FW_detailFn} = "DOIFtools_fhemwebFn";

  $data{FWEXT}{"/DOIFtools_logWrapper"}{CONTENTFUNC} = "DOIFtools_logWrapper";

  my $oldAttr = "target_room:noArg target_group:noArg executeDefinition:noArg executeSave:noArg eventMonitorInDOIF:noArg readingsPrefix:noArg";
  $hash->{AttrList} = "DOIFtoolsExecuteDefinition:1,0 DOIFtoolsTargetRoom DOIFtoolsTargetGroup DOIFtoolsExecuteSave:1,0 DOIFtoolsReadingsPrefix DOIFtoolsEventMonitorInDOIF:1,0 DOIFtoolsHideModulShortcuts:1,0 DOIFtoolsHideGetSet:1,0 DOIFtoolsMyShortcuts:textField-long DOIFtoolsMenuEntry:1,0 DOIFtoolsHideStatReadings:1,0 disabledForIntervals ".$oldAttr;
}

sub DOIFtools_dO ($$$$){return "";}
# FW_detailFn for DOIF injecting event monitor
sub DOIFtools_eM($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $ret = "";
  # Event Monitor
  my $a0 = ReadingsVal($d,".eM", "off") eq "on" ? "off" : "on"; 
  $ret .= "<div class=\"dval\"><br>Event monitor: <a href=\"/fhem?detail=$d&amp;cmd.$d=setreading $d .eM $a0\">toggle</a>&nbsp;&nbsp;";
  $ret .= "</div>";

  my $a = "";
  if (ReadingsVal($d,".eM","off") eq "on") {
    $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/console.js\"></script>";
    my $filter = $a ? ($a eq "log" ? "global" : $a) : ".*";
    $ret .= "<div><br>";
    $ret .= "Events (Filter: <a href=\"#\" id=\"eventFilter\">$filter</a>) ".
          "&nbsp;&nbsp;<span class='fhemlog'>FHEM log ".
                "<input id='eventWithLog' type='checkbox'".
                ($a && $a eq "log" ? " checked":"")."></span>".
          "&nbsp;&nbsp;<button id='eventReset'>Reset</button></div>\n";
    $ret .= "<div>";
    $ret .= "<textarea id=\"console\" style=\"width:99%; top:.1em; bottom:1em; position:relative;\" readonly=\"readonly\" rows=\"25\" cols=\"60\"></textarea>";
    $ret .= "</div>";
  }
  return $ret;
}
######################
# Show the content of the log (plain text), or an image and offer a link
# to convert it to an SVG instance
# If text and no reverse required, try to return the data as a stream;
sub DOIFtools_logWrapper($) {
  my ($cmd) = @_;

  my $d    = $FW_webArgs{dev};
  my $type = $FW_webArgs{type};
  my $file = $FW_webArgs{file};
  my $ret = "";

  if(!$d || !$type || !$file) {
    FW_pO '<div id="content">DOIFtools_logWrapper: bad arguments</div>';
    return 0;
  }

  if(defined($type) && $type eq "text") {
    $defs{$d}{logfile} =~ m,^(.*)/([^/]*)$,; # Dir and File
    my $path = "$1/$file";
    $path =~ s/%L/$attr{global}{logdir}/g
        if($path =~ m/%/ && $attr{global}{logdir});
    $path = AttrVal($d,"archivedir","") . "/$file" if(!-f $path);

    FW_pO "<div id=\"content\">";
    FW_pO "<div class=\"tiny\">" if($FW_ss);
    FW_pO "<pre class=\"log\"><b>jump to: <a name='top'></a><a href=\"#end_of_file\">the end</a> <a href=\"#listing\">first listing</a></b><br>";
    my $suffix = "<br/><b>jump to: <a name='end_of_file'></a><a href='#top'>the top</a> <a href=\"#listing\">first listing</a></b><br/></pre>".($FW_ss ? "</div>" : "")."</div>";

    my $reverseLogs = AttrVal($FW_wname, "reverseLogs", 0);
    if(!$reverseLogs) {
      $suffix .= "</body></html>";
      return FW_returnFileAsStream($path, $suffix, "text/html", 0, 0);
    }

    if(!open(FH, $path)) {
      FW_pO "<div id=\"content\">$path: $!</div></body></html>";
      return 0;
    }
    my $cnt = join("", reverse <FH>);
    close(FH);
#   $cnt = FW_htmlEscape($cnt);
    FW_pO $cnt;
    FW_pO $suffix;
    return 1;
  }
  return 0;
}

sub DOIFtools_fhemwebFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $ret = "";
  # Logfile Liste
  if($FW_ss && $pageHash) {
        $ret."<div id=\"$d\" align=\"center\" class=\"FileLog col2\">".
                  "$defs{$d}{STATE}</div>";
  } else {
  my $row = 0;
  $ret .= sprintf("<table class=\"FileLog %swide\">",
                        $pageHash ? "" : "block ");
  foreach my $f (FW_fileList($defs{$d}{logfile})) {
    my $class = (!$pageHash ? (($row++&1)?"odd":"even") : "");
    $ret .= "<tr class=\"$class\">";
    $ret .= "<td><div class=\"dname\">$f</div></td>";
    my $idx = 0;
    foreach my $ln (split(",", AttrVal($d, "logtype", "text"))) {
      if($FW_ss && $idx++) {
        $ret .= "</tr><tr class=\"".(($row++&1)?"odd":"even")."\"><td>";
      }
      my ($lt, $name) = split(":", $ln);
      $name = $lt if(!$name);
      $ret .= FW_pH("$FW_ME/DOIFtools_logWrapper&dev=$d&type=$lt&file=$f",
                    "<div class=\"dval\">$name</div>", 1, "dval", 1);
    }
  }
  $ret .= "</table>";
  }
  # Event Monitor
  my $a0 = ReadingsVal($d,".eM", "off") eq "on" ? "off" : "on"; 
  $ret .= "<div class=\"dval\"><br>Event monitor: <a href=\"/fhem?detail=$d&amp;cmd.$d=setreading $d .eM $a0\">toggle</a>&nbsp;&nbsp;";
  $ret .= "Shortcuts: " if (!AttrVal($d,"DOIFtoolsHideModulShortcuts",0) or AttrVal($d,"DOIFtoolsMyShortcuts",""));
  if (!AttrVal($d,"DOIFtoolsHideModulShortcuts",0)) {
    $ret .= "<a href=\"/fhem?detail=$d&amp;cmd.$d=reload 98_DOIFtools.pm\">reload DOIFtools</a>&nbsp;&nbsp;" if(ReadingsVal($d,".debug",""));
    $ret .= "<a href=\"/fhem?detail=$d&amp;cmd.$d=update check\">update check</a>&nbsp;&nbsp;";
    $ret .= "<a href=\"/fhem?detail=$d&amp;cmd.$d=update\">update</a>&nbsp;&nbsp;" if(!ReadingsVal($d,".debug",""));
    $ret .= "<a href=\"/fhem?detail=$d&amp;cmd.$d=set%20update_du:FILTER=state=0%201\">update</a>&nbsp;&nbsp;" if(ReadingsVal($d,".debug",""));
    $ret .= "<a href=\"/fhem?detail=$d&amp;cmd.$d=shutdown restart\">shutdown restart</a>&nbsp;&nbsp;";
    $ret .= "<a href=\"/fhem?detail=$d&amp;cmd.$d=fheminfo send\">fheminfo send</a>&nbsp;&nbsp;";
  }
  if (AttrVal($d,"DOIFtoolsMyShortcuts","")) {
    my @sc = split(",",AttrVal($d,"DOIFtoolsMyShortcuts",""));
    for (my $i = 0; $i < @sc; $i+=2) {
      if ($sc[$i] =~ m/^\#\#(.*)/) {
        $ret .= "$1&nbsp;&nbsp;";
      } else {
        $ret .= "<a href=\"/$sc[$i+1]\">$sc[$i]</a>&nbsp;&nbsp;" if($sc[$i] and $sc[$i+1]);
      }
    }
  }
  if (!AttrVal($d, "DOIFtoolsHideGetSet", 0)) {
      $ret .= "<br><br>";
      my $a1 = ReadingsVal($d,"doStatistics", "disabled") =~ "disabled|deleted" ? "enabled" : "disabled"; 
      my $a2 = ReadingsVal($d,"specialLog", 0) ? 0 : 1; 
      # set doStatistics enabled/disabled
      $ret .= "<form method=\"post\" action=\"/fhem\" autocomplete=\"off\"><input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.set$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.set$d\" value=\"set\" class=\"set\" type=\"submit\">
      <div class=\"set downText\">&nbsp;doStatistics $a1&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-doStatistics\">
      <input name=\"val.set$d\" value=\"doStatistics $a1\" type=\"hidden\">
      </div></form>";
      # set doStatistics deleted
      $ret .= "<form method=\"post\" action=\"/fhem\" autocomplete=\"off\"><input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.set$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.set$d\" value=\"set\" class=\"set\" type=\"submit\">
      <div class=\"set downText\">&nbsp;doStatistics deleted&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-doStatistics\">
      <input name=\"val.set$d\" value=\"doStatistics deleted\" type=\"hidden\">
      </div></form>";
      # set specialLog 0/1
      $ret .= "<form method=\"post\" action=\"/fhem\" autocomplete=\"off\"><input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.set$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.set$d\" value=\"set\" class=\"set\" type=\"submit\">
      <div class=\"set downText\">&nbsp;specialLog $a2&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-doStatistics\">
      <input name=\"val.set$d\" value=\"specialLog $a2\" type=\"hidden\">
      </div></form>";
      $ret .= "<br><br>";
      # get statisticsReport
      $ret .= "<form method=\"post\" action=\"/fhem\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.get$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.get$d\" value=\"get\" class=\"get\" type=\"submit\">
      <div class=\"get downText\">&nbsp;statisticsReport&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-statisticsReport\">
      <input name=\"val.get$d\" value=\"statisticsReport\" type=\"hidden\">
      </div></form>";
      # get checkDOIF
      $ret .= "<form method=\"post\" action=\"/fhem\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.get$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.get$d\" value=\"get\" class=\"get\" type=\"submit\">
      <div class=\"get downText\">&nbsp;checkDOIF&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-checkDOIF\">
      <input name=\"val.get$d\" value=\"checkDOIF\" type=\"hidden\">
      </div></form>";
      # get runningTimerInDOIF
      $ret .= "<form method=\"post\" action=\"/fhem\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.get$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.get$d\" value=\"get\" class=\"get\" type=\"submit\">
      <div class=\"get downText\">&nbsp;runningTimerInDOIF&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-runningTimerInDOIF\">
      <input name=\"val.get$d\" value=\"runningTimerInDOIF\" type=\"hidden\">
      </div></form>";
  }
  $ret .= "</div><br>";
  my $a = "";
  if (ReadingsVal($d,".eM","off") eq "on") {
    $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/console.js\"></script>";
    my $filter = $a ? ($a eq "log" ? "global" : $a) : ".*";
    $ret .= "<div><br>";
    $ret .= "Events (Filter: <a href=\"#\" id=\"eventFilter\">$filter</a>) ".
          "&nbsp;&nbsp;<span class='fhemlog'>FHEM log ".
                "<input id='eventWithLog' type='checkbox'".
                ($a && $a eq "log" ? " checked":"")."></span>".
          "&nbsp;&nbsp;<button id='eventReset'>Reset</button></div>\n";
    $ret .= "<div>";
    $ret .= "<textarea id=\"console\" style=\"width:99%; top:.1em; bottom:1em; position:relative;\" readonly=\"readonly\" rows=\"25\" cols=\"60\"></textarea>";
    $ret .= "</div>";
  }
  return $ret;
}
sub DOIFtools_Notify($$) {
  my ($hash, $source) = @_;
  my $pn = $hash->{NAME};
  my $sn = $source->{NAME};
  my $events = deviceEvents($source,1);
  return if( !$events );
  # \@DOIFtools_we aktualisieren
  if ($sn eq AttrVal("global","holiday2we","")) {
    my $we;
    my $val;
    my $a;
    my $b;
    for (my $i = 0; $i < 8; $i++) { 
      $DOIFtools_we[$i] = 0;
      $val = CommandGet(undef,"get $sn days $i");
      if($val) {
        ($a, $b) = ReplaceEventMap($sn, [$sn, $val], 0);
        $DOIFtools_we[$i] = 1 if($b ne "none");
      }
    }
  }
  my $ldi = ReadingsVal($pn,"specialLog","") ? ReadingsVal($pn,"doif_to_log","") : "";
  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));
    # add list to DOIFtoolsLog
    if ($ldi and $ldi =~ "$sn"  and $event =~ m/(^cmd: \d+(\.\d+)?|^wait_timer: \d\d.*)/) {
      $hash->{helper}{counter}{0}++;
      my $trig = "<a name=\"list$hash->{helper}{counter}{0}\"><a name=\"listing\">";
      $trig .= "</a><strong>\[$hash->{helper}{counter}{0}\] +++++ Listing $sn:$1 +++++</strong>\n";
      my $prev = $hash->{helper}{counter}{0} - 1;
      my $next = $hash->{helper}{counter}{0} + 1;
      $trig .= $prev ? "<b>jump to: <a href=\"#list$prev\">prev</a>&nbsp;&nbsp;<a href=\"#list$next\">next</a> Listing</b><br>" : "<b>jump to: <a href=\"#list$next\">next</a> Listing</b><br>";
      $trig .= "DOIF-Version: ".ReadingsVal($pn,"DOIF_version","n/a")."<br>";
      $trig .= CommandList(undef,$sn);
      foreach my $itm (keys %defs) {
        $trig =~ s,([\[\" ])$itm([\"\:\] ]),$1<a href="/fhem?detail=$itm">$itm</a>$2,g;
      }
      CommandTrigger(undef,"$hash->{TYPE}Log $trig");
    }
    # DOIFtools DEF addition
    if ($sn eq "global" and $event =~ "MODIFIED|INITIALIZED|DEFINED|DELETED|RENAMED|UNDEFINED") {
    my @doifList = devspec2array("TYPE=DOIF");
      $hash->{DEF} = "associated DOIF: ".join(" ",sort @doifList);
      readingsSingleUpdate($hash,"DOIF_version",fhem("version 98_DOIF.pm noheader",1),0);
    }
    # get DOIF version, FHEM revision and default values
    if ($sn eq "global" and $event =~ "INITIALIZED|MODIFIED $pn") {
      readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"DOIF_version",fhem("version 98_DOIF.pm noheader",1));
        readingsBulkUpdate($hash,"FHEM_revision",fhem("version revision noheader",1));
        readingsBulkUpdate($hash,"sourceAttribute","readingList") unless ReadingsVal($pn,"sourceAttribute","");
        readingsBulkUpdate($hash,"recording_target_duration",0) unless ReadingsVal($pn,"recording_target_duration","0");
        readingsBulkUpdate($hash,"doStatistics","disabled") unless ReadingsVal($pn,"doStatistics","");
        readingsBulkUpdate($hash,".eM", ReadingsVal($pn,".eM","off"));
        readingsBulkUpdate($hash,"statisticsDeviceFilterRegex", ".*") unless ReadingsVal($pn,"statisticsDeviceFilterRegex","");
      readingsEndUpdate($hash,0);
      $defs{$pn}{VERSION} = fhem("version 98_DOIFtools.pm noheader",1);
      DOIFtoolsSetNotifyDev($hash,1,1);
      #set new attributes and delete old ones
      CommandAttr(undef,"$pn DOIFtoolsExecuteDefinition ".AttrVal($pn,"executeDefinition","")) if (AttrVal($pn,"executeDefinition",""));
      CommandDeleteAttr(undef,"$pn executeDefinition") if (AttrVal($pn,"executeDefinition",""));
      CommandAttr(undef,"$pn DOIFtoolsExecuteSave ".AttrVal($pn,"executeSave","")) if (AttrVal($pn,"executeSave",""));
      CommandDeleteAttr(undef,"$pn executeSave") if (AttrVal($pn,"executeSave",""));
      CommandAttr(undef,"$pn DOIFtoolsTargetRoom ".AttrVal($pn,"target_room","")) if (AttrVal($pn,"target_room",""));
      CommandDeleteAttr(undef,"$pn target_room") if (AttrVal($pn,"target_room",""));
      CommandAttr(undef,"$pn DOIFtoolsTargetGroup ".AttrVal($pn,"target_group","")) if (AttrVal($pn,"target_group",""));
      CommandDeleteAttr(undef,"$pn target_group") if (AttrVal($pn,"target_group",""));
      CommandAttr(undef,"$pn DOIFtoolsReadingsPrefix ".AttrVal($pn,"readingsPrefix","")) if (AttrVal($pn,"readingsPrefix",""));
      CommandDeleteAttr(undef,"$pn readingsPrefix") if (AttrVal($pn,"readingsPrefix",""));
      CommandAttr(undef,"$pn DOIFtoolsEventMonitorInDOIF ".AttrVal($pn,"eventMonitorInDOIF","")) if (AttrVal($pn,"eventMonitorInDOIF",""));
      CommandDeleteAttr(undef,"$pn eventMonitorInDOIF") if (AttrVal($pn,"eventMonitorInDOIF",""));
      CommandSave(undef,undef);
    }
    # Event monitor in DOIF
    if ($modules{DOIF}{LOADED} and !defined $modules{DOIF}->{FW_detailFn} and $sn eq "global" and $event =~ "INITIALIZED" and AttrVal($pn,"DOIFtoolsEventMonitorInDOIF","")) {
      $modules{DOIF}->{FW_detailFn} = "DOIFtools_eM" if (!defined $modules{DOIF}->{FW_detailFn});
      readingsSingleUpdate($hash,".DOIFdO",$modules{DOIF}->{FW_deviceOverview},0);
      $modules{DOIF}->{FW_deviceOverview} = 1;
    }
    # Statistics event recording
    if (ReadingsVal($pn,"doStatistics","disabled") eq "enabled" and !IsDisabled($pn) and $sn ne "global" and (ReadingsVal($pn,"statisticHours",0) <= ReadingsVal($pn,"recording_target_duration",0) or !ReadingsVal($pn,"recording_target_duration",0)))  {
      my $st = AttrVal($pn,"DOIFtoolsHideStatReadings","") ? ".stat_" : "stat_";
      readingsSingleUpdate($hash,"$st$sn",ReadingsVal($pn,"$st$sn",0)+1,0);
    }
  }
  #statistics time counter updating 
  if (ReadingsVal($pn,"doStatistics","disabled") eq "enabled" and !IsDisabled($pn) and $sn ne "global")  {
    if (!ReadingsVal($pn,"recording_target_duration",0) or ReadingsVal($pn,"statisticHours",0) <= ReadingsVal($pn,"recording_target_duration",0)) {
    my $t = gettimeofday();
    my $te = ReadingsVal($pn,".te",gettimeofday()) + $t - ReadingsVal($pn,".t0",gettimeofday());
    my $tH = int($te*100/3600 +.5)/100;
    readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,".te",$te);
      readingsBulkUpdate($hash,".t0",$t);
      readingsBulkUpdate($hash,"statisticHours",sprintf("%.2f",$tH));
    readingsEndUpdate($hash,0);
    } else {
      DOIFtoolsSetNotifyDev($hash,1,0);
    readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"Action","event recording target duration reached");
      readingsBulkUpdate($hash,"doStatistics","disabled");
    readingsEndUpdate($hash,0);
    }
  }
  return undef;
}
sub DOIFtoolsRg
{
  my ($hash,$arg) = @_;
  my $pn = $hash->{NAME};
  my $pnRg= "rg_$arg";
  my $ret = "";
  my @ret;
  my $defRg = "";
  my @defRg;
  my $cL = "";
  my @rL = split(/ /,AttrVal($arg,"readingList",""));
  for (my $i=0; $i<@rL; $i++) {
    $defRg .= ",<$rL[$i]>,$rL[$i]";
    $cL .= "\"$rL[$i]\"=>\"$rL[$i]:\",";
  }
  push @defRg, "$pnRg readingsGroup $arg:+STATE$defRg";
  my $rooms = AttrVal($pn,"DOIFtoolsTargetRoom","") ? AttrVal($pn,"DOIFtoolsTargetRoom","") : AttrVal($arg,"room","");
  push @defRg, "$pnRg room $rooms" if($rooms);
  my $groups = AttrVal($pn,"DOIFtoolsTargetGroup","") ? AttrVal($pn,"DOIFtoolsTargetGroup","") : AttrVal($arg,"group","");
  push @defRg, "$pnRg group $groups" if($groups);
  push @defRg, "$pnRg commands {$cL}" if ($cL);
  push @defRg, "$pnRg noheading 1";
  $defRg = "defmod $defRg[0]\rattr ".join("\rattr ",@defRg[1..@defRg-1]);
  if (AttrVal($pn,"DOIFtoolsExecuteDefinition","")) {
      $ret = CommandDefMod(undef,$defRg[0]);
      push @ret, $ret if ($ret);
      for (my $i = 1; $i < @defRg; $i++) {
        $ret = CommandAttr(undef,$defRg[$i]);
        push @ret, $ret if ($ret);
      }
      if (@ret) {
          $ret = join("\n", @ret);
          return $ret;
      } else {
          $ret = "Created device <b>$pnRg</b>.\n";
          $ret .= CommandSave(undef,undef) if (AttrVal($pn,"DOIFtoolsExecuteSave",""));
          return $ret;
      }
  } else {
      $defRg =~ s/</&lt;/g;
      $defRg =~ s/>/&gt;/g;
      return $defRg;
  }
}
# calculate real date in userReadings
sub DOIFtoolsNextTimer {
  my ($timer_str) = @_;
  $timer_str =~ /(\d\d).(\d\d).(\d\d\d\d) (\d\d):(\d\d):(\d\d)\|([0-8]+)/;
  my $tdays = $7;
  return "$1.$2.$3 $4:$5:$6" if (length($7)==0); 
  my $timer = timelocal($6,$5,$4,$1,$2-1,$3);
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($timer);
  my $ilook = 0;
  my $we;
  for (my $iday = $wday; $iday < 7; $iday++) { 
    $we = (($iday==0 || $iday==6) ? 1 : 0);
    if(!$we) {
      $we = $DOIFtools_we[$ilook + 1];
    }
    if ($tdays =~ /$iday/ or ($tdays =~ /7/ and $we) or ($tdays =~ /8/ and !$we)) {
      return strftime("%d.%m.%Y %H:%M:%S",localtime($timer + $ilook * 86400));
    }
    $ilook++;
  }
  for (my $iday = 0; $iday < $wday; $iday++) { 
    $we = (($iday==0 || $iday==6) ? 1 : 0);
    if(!$we) {
      $we = $DOIFtools_we[$ilook + 1];
    }
    if ($tdays =~ /$iday/ or ($tdays =~ /7/ and $we) or ($tdays =~ /8/ and !$we)) {
      return strftime("%d.%m.%Y %H:%M:%S",localtime($timer + $ilook * 86400));
    }
    $ilook++;
  }
}

sub DOIFtoolsNxTimer {
  my ($hash,$arg) = @_;
  my $pn = $hash->{NAME};
  my $tn= $arg;
  my $thash = $defs{$arg};
  my $ret = "";
  my @ret;
  foreach my $key (keys %{$thash->{READINGS}}) {
    if ($key =~ m/^timer_\d\d_c\d\d/ && $thash->{READINGS}{$key}{VAL} =~ m/.*\|[0-8]+/) {
      $ret = AttrVal($pn,"DOIFtoolsReadingsPrefix","N_")."$key:$key.* \{DOIFtoolsNextTimer(ReadingsVal(\"$tn\",\"$key\",\"none\"))\}";
      push @ret, $ret if ($ret);
    }
  }
  if (@ret) {
    $ret = join(",", @ret);
    if (!AttrVal($tn,"userReadings","")) {
      CommandAttr(undef,"$tn userReadings $ret");
      $ret = "Created userReadings for <b>$tn</b>.\n";
      $ret .= CommandSave(undef,undef) if (AttrVal($pn,"DOIFtoolsExecuteSave",""));
    return $ret;
    } else {
      $ret = "A userReadings Attribute already exists, adding is not implemented, try it manually.\r\r $ret\r"; 
      return $ret;
    }
  }
  return join("\n", @ret);
}

sub DOIFtoolsGetAssocDev {
  my ($hash,$arg) = @_;
  my $pn = $hash->{NAME};
  my $tn= $arg;
  my $thash = $defs{$arg};
  my $ret = "";
  my @ret = ();
  push @ret ,$arg;
  $ret .= $thash->{devices}{all} if ($thash->{devices}{all});
  $ret =~ s/^\s|\s$//;
  push @ret, split(/ /,$ret);
  push @ret, getPawList($tn);
  return @ret;
}

sub DOIFtoolsCheckDOIFcoll {
  my ($hash,$tn) = @_;
  my $ret = "";
  my $tail = $defs{$tn}{DEF};
  if (!$tail) {
    $tail="";
  } else {
    $tail =~ s/(##.*\n)|(##.*$)|\n/ /g;
  }
  return("") if ($tail =~ /^ *$/);
  $ret .= $tn if ($tail =~ m/(DOELSEIF )/ and !($tail =~ m/(DOELSE )/) and AttrVal($tn,"do","") !~ "always");
  return $ret;
}

sub DOIFtoolsCheckDOIF {
  my ($hash,$tn) = @_;
  my $ret = "";
  my $tail = $defs{$tn}{DEF};
  if (!$tail) {
    $tail="";
  } else {
    $tail =~ s/(##.*\n)|(##.*$)|\n/ /g;
  }
  return("") if ($tail =~ /^ *$/);
  $ret .= "<li>replace <b>DOIF name</b> with <b>\$SELF</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events\">utilization of events</a>)</li>\n" if ($tail =~ m/[\[|\?]($tn)/);
  $ret .= "<li>replace <b>ReadingsVal(...)</b> with <b>[</b>name<b>:</b>reading<b>,</b>default value<b>]</b>, if not used in an <b><a href=\"https://fhem.de/commandref.html#IF\">IF command</a></b>, otherwise there is no possibility to use a default value (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung\">controlling by events</a>)</li>\n" if ($tail =~ m/(ReadingsVal)/);
  $ret .= "<li>replace <b>ReadingsNum(...)</b> with <b>[</b>name<b>:</b>reading<b>:d,</b>default value]</b>, if not used in an <b><a href=\"https://fhem.de/commandref.html#IF\">IF command</a></b>, otherwise there is no possibility to use a default value (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Filtern_nach_Zahlen\">filtering numbers</a>)</li>\n" if ($tail =~ m/(ReadingsNum)/);
  $ret .= "<li>replace <b>InternalVal(...)</b> with <b>[</b>name<b>:</b>&amp;internal,</b>default value<b>]</b>, if not used in an <b><a href=\"https://fhem.de/commandref.html#IF\">IF command</a></b>, otherwise there is no possibility to use a default value (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung\">controlling by events</a>)</li>\n" if ($tail =~ m/(InternalVal)/);
  $ret .= "<li>replace <b>$1...\")}</b> with <b>$2...</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref.html#command\">plain FHEM command</a>)</li>\n" if ($tail =~ m/(\{\s*fhem.*?\"\s*(set|get))/);
  $ret .= "<li>replace <b>{system \"</b>&lt;shell command&gt;<b>\"}</b> with <b>\"</b>\&lt;shell command&gt;<b>\"</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref.html#command\">plain FHEM shell command, non blocking</a>)</li>\n" if ($tail =~ m/(\{\s*system.*?\})/);
  $ret .= "<li><b>sleep</b> is not recommended in DOIF, use attribute <b>wait</b> for (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_wait\">delay</a>)</li>\n" if ($tail =~ m/(sleep\s\d+\.?\d+\s*[;|,]?)/);
  $ret .= "<li>replace <b>[</b>name<b>:?</b>regex<b>]</b> by <b>[</b>name<b>:\"</b>regex<b>\"]</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events\">avoid old syntax</a>)</li>\n" if ($tail =~ m/(\[.*?[^"]?:[^"]?\?.*?\])/);

  $ret .= "<li>the first <b>command</b> after <b>DOELSE</b> seems to be a <b>condition</b> indicated by <b>$2</b>, check it.</li>\n" if ($tail =~ m/(DOELSE .*?\]\s*?(\!\S|\=\~|\!\~|and|or|xor|not|\|\||\&\&|\=\=|\!\=|ne|eq|lt|gt|le|ge)\s*?).*?\)/);
  my @wait = SplitDoIf(":",AttrVal($tn,"wait",""));
  my @sub0 = ();
  my @tmp = ();
  if (@wait and !AttrVal($tn,"timerWithWait","")) {
    for (my $i = 0; $i < @wait; $i++) {
      ($sub0[$i],@tmp) = SplitDoIf(",",$wait[$i]);
      $sub0[$i] =~ s/\s// if($sub0[$i]);
    }
    foreach my $key (sort keys %{$defs{$tn}{timeCond}}) {
      if ($defs{$tn}{timeCond}{$key} and $sub0[$defs{$tn}{timeCond}{$key}]) {
        $ret .= "<li><b>Timer</b> in <b>condition</b> and <b>wait timer</b> for <b>commands</b> in the same <b>DOIF branch</b>.<br>If you observe unexpected behaviour, try attribute <b>timerWithWait</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_timerWithWait\">delay of Timer</a>)</li>\n";
        last;
      }
    }
  }
  my $wait = AttrVal($tn,"wait","");
  if ($wait) {
    $ret .= "<li>At least one <b>indirect timer</b> in attribute <b>wait</b> is referring <b>DOIF's name</b> ( $tn ) and has no <b>default value</b>, you should add <b>default values</b>. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_notexist\">default value</a>)</li>\n" 
        if($wait =~ m/(\[(\$SELF|$tn).*?(\,.*?)?\])/ and $2 and !$3); 
  }
  foreach my $key (sort keys %{$defs{$tn}{time}}) {
    if ($defs{$tn}{time}{$key} =~ m/(\[(\$SELF|$tn).*?(\,.*?)?\])/ and $2 and !$3) {
      $ret .= "<li>At least one <b>indirect timer</b> in <b>condition</b> is referring <b>DOIF's name</b> ( $tn ) and has no <b>default value</b>, you should add <b>default values</b>. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_notexist\">default value</a>)</li>\n";
      last;
    }
  }

  $ret = $ret ? "$tn\n<ul>$ret</ul> " : "";
  return $ret;
}

# param: $hash, doif_to_log, statisticsTypes as 1 or 0
sub DOIFtoolsSetNotifyDev {
  my ($hash,@a) = @_;
  my $pn = $hash->{NAME};
  $hash->{NOTIFYDEV} = "global";
  $hash->{NOTIFYDEV} .= ",$attr{global}{holiday2we}" if ($attr{global}{holiday2we});
  $hash->{NOTIFYDEV} .= ",".ReadingsVal($pn,"doif_to_log","") if ($a[0] and ReadingsVal($pn,"doif_to_log","") and ReadingsVal($pn,"specialLog",0));
  $hash->{NOTIFYDEV} .= ",TYPE=".ReadingsVal($pn,"statisticsTYPEs","") if ($a[1] and ReadingsVal($pn,"statisticsTYPEs","") and ReadingsVal($pn,"doStatistics","deleted") eq "enabled");
  return undef;
}
sub DOIFtoolsCounterReset($) {
  my ($pn) = @_;
  RemoveInternalTimer($pn,"DOIFtoolsCounterReset");
  $defs{$pn}->{helper}{counter}{0} = 0;
  my $nt = gettimeofday();
  my @lt = localtime($nt);
  $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0]);         # Midnight
  $nt += 86400 + 3;                              # Tomorrow
  InternalTimer($nt, "DOIFtoolsCounterReset", $pn, 0);
  return undef;
}
#################################
sub DOIFtools_Define($$$)
{
  my ($hash, $def) = @_;
  my ($pn, $type, $cmd) = split(/[\s]+/, $def, 3);
  my @Liste = devspec2array("TYPE=DOIFtools");
  if (@Liste > 1) {
    CommandDelete(undef,$pn);
    CommandSave(undef,undef);
    return "Only one instance of DOIFtools is allowed per FHEM installation. Delete the old one first.";
  }
  $hash->{STATE} = "initialized";
  $hash->{logfile} = AttrVal("global","logdir","./log/")."$hash->{TYPE}Log-%Y-%j.log";
  DOIFtoolsCounterReset($pn);
  return undef;
}

sub DOIFtools_Attr(@)
{
  my @a = @_;
  my $cmd = $a[0];
  my $pn = $a[1];
  my $attr = $a[2];
  my $value = (defined $a[3]) ? $a[3] : "";
  my $hash = $defs{$pn};
  my $ret="";
  if ($init_done and $attr eq "DOIFtoolsEventMonitorInDOIF") {
    if (!defined $modules{DOIF}->{FW_detailFn} and $cmd eq "set" and $value) {
        $modules{DOIF}->{FW_detailFn} = "DOIFtools_eM";
        readingsSingleUpdate($hash,".DOIFdO",$modules{DOIF}->{FW_deviceOverview},0);
        $modules{DOIF}->{FW_deviceOverview} = "DOIFtools_dO";
    } elsif ($modules{DOIF}->{FW_detailFn} eq "DOIFtools_eM" and ($cmd eq "del" or !$value)) {
        delete $modules{DOIF}->{FW_detailFn};
        $modules{DOIF}->{FW_deviceOverview} = ReadingsVal($pn,"DOIFtools_dO","");
    }
  } elsif ($init_done and $attr eq "DOIFtoolsMenuEntry") {
    if ($cmd eq "set" and $value) {
      if (!(AttrVal($FW_wname, "menuEntries","") =~ m/(DOIFtools\,\/fhem\?detail\=DOIFtools\,)/)) {
        CommandAttr(undef, "$FW_wname menuEntries DOIFtools,/fhem?detail=DOIFtools,".AttrVal($FW_wname, "menuEntries",""));
        CommandSave(undef, undef);
      }
    } elsif ($init_done and $cmd eq "del" or !$value) {
      if (AttrVal($FW_wname, "menuEntries","") =~ m/(DOIFtools\,\/fhem\?detail\=DOIFtools\,)/) {
        my $me = AttrVal($FW_wname, "menuEntries","");
        $me =~ s/DOIFtools\,\/fhem\?detail\=DOIFtools\,//;
        CommandAttr(undef, "$FW_wname menuEntries $me");
        CommandSave(undef, undef);
      }
    
    }
  } elsif ($init_done and $attr eq "DOIFtoolsHideStatReadings") {
      DOIFtoolsSetNotifyDev($hash,1,0);
      readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Action","event recording stopped");
        readingsBulkUpdate($hash,"doStatistics","disabled");
        readingsBulkUpdate($hash,"statisticHours","0.00");
        readingsBulkUpdate($hash,".t0",gettimeofday());
        readingsBulkUpdate($hash,".te",0);
      readingsEndUpdate($hash,0);
      foreach my $key (keys %{$defs{$pn}->{READINGS}}) {
        delete $defs{$pn}->{READINGS}{$key} if ($key =~ "^(stat_|\.stat_)");
      }
  } elsif ($init_done and $cmd eq "set" and 
           $attr =~ m/^(executeDefinition|executeSave|target_room|target_group|readingsPrefix|eventMonitorInDOIF)$/) {
    $ret .= "\n$1 is an old attribute name use a new one beginning with DOIFtools...";
    return $ret;
  }
  return undef;
}

sub DOIFtools_Undef
{
  my ($hash, $pn) = @_;
  $hash->{DELETED} = 1;
  if (devspec2array("TYPE=DOIFtools") <=1 and defined($modules{DOIF}->{FW_detailFn}) and $modules{DOIF}->{FW_detailFn} eq "DOIFtools_eM") {
      delete $modules{DOIF}->{FW_detailFn};
      $modules{DOIF}->{FW_deviceOverview} = ReadingsVal($pn,"DOIFtools_dO","");
  }
  if (AttrVal($pn,"DOIFtoolsMenuEntry","")) {
    CommandDeleteAttr(undef, "$pn DOIFtoolsMenuEntry");
  }
  RemoveInternalTimer($pn,"DOIFtoolsCounterReset");
  return undef;
}

sub DOIFtools_Set($@)
{
  my ($hash, @a) = @_;
  my $pn = $hash->{NAME};
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";
  my $ret = "";
  my @ret = ();
  my @doifList = devspec2array("TYPE=DOIF");
  my @ntL =();
  my $dL = join(",",sort @doifList);
  my $st = AttrVal($pn,"DOIFtoolsHideStatReadings","") ? ".stat_" : "stat_";
  my %types = ();

  foreach my $d (keys %defs ) {
    next if(IsIgnored($d));
    my $t = $defs{$d}{TYPE};
    $types{$t} = "";
  }
  my $tL = join(",",sort keys %types);

  if ($arg eq "sourceAttribute") {
      readingsSingleUpdate($hash,"sourceAttribute",$value,0);
      return $ret;
  } elsif ($arg eq "targetDOIF") {
      readingsSingleUpdate($hash,"targetDOIF",$value,0);
  } elsif ($arg eq "deleteReadingsInTargetDOIF") {
      if ($value) {
        my @i = split(",",$value);
        foreach my $i (@i) {
          $ret = CommandDeleteReading(undef,ReadingsVal($pn,"targetDOIF","")." $i");
          push @ret, $ret if($ret);
        }
        $ret = join("\n", @ret);
        return $ret;
      } else {
        return "no reading selected.";
      }
  } elsif ($arg eq "doStatistics") {
      if ($value eq "deleted") {
        DOIFtoolsSetNotifyDev($hash,1,0);
        readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"Action","event recording stopped");
          readingsBulkUpdate($hash,"doStatistics","disabled");
          readingsBulkUpdate($hash,"statisticHours","0.00");
          readingsBulkUpdate($hash,".t0",gettimeofday());
          readingsBulkUpdate($hash,".te",0);
        readingsEndUpdate($hash,0);
        foreach my $key (keys %{$defs{$pn}->{READINGS}}) {
          delete $defs{$pn}->{READINGS}{$key} if ($key =~ "^(stat_|\.stat_)");
        }
      } elsif ($value eq "disabled") {
        readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"Action","event recording paused");
          readingsBulkUpdate($hash,"doStatistics","disabled");
        readingsEndUpdate($hash,0);
        DOIFtoolsSetNotifyDev($hash,1,0);
      } elsif ($value eq "enabled") {
        readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"Action","<html><div style=\"color:red;\" >recording events</div></html>");
          readingsBulkUpdate($hash,"doStatistics","enabled");
          readingsBulkUpdate($hash,".t0",gettimeofday());
        readingsEndUpdate($hash,0);
        DOIFtoolsSetNotifyDev($hash,1,1);
      }
  } elsif ($arg eq "statisticsTYPEs") {
        $value =~ s/\,/|/g;
        readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"statisticsTYPEs",$value);
          readingsBulkUpdate($hash,"doStatistics","disabled");
          readingsBulkUpdate($hash,".te",0);
          readingsBulkUpdate($hash,".t0",gettimeofday());
          readingsBulkUpdate($hash,"statisticHours","0.00");
        readingsEndUpdate($hash,0);
        foreach my $key (keys %{$defs{$pn}->{READINGS}}) {
          delete $defs{$pn}->{READINGS}{$key} if ($key =~ "^(stat_|\.stat_)");
        }
        DOIFtoolsSetNotifyDev($hash,1,0);
  } elsif ($arg eq "recording_target_duration") {
        $value =~ m/(\d+)/;
        readingsSingleUpdate($hash,"recording_target_duration",$1 ? $1 : 0,0);
  } elsif ($arg eq "statisticsShowRate_ge") {
        $value =~ m/(\d+)/;
        readingsSingleUpdate($hash,"statisticsShowRate_ge",$1 ? $1 : 0,0);
  } elsif ($arg eq "specialLog") {
        if ($value) {
          readingsSingleUpdate($hash,"specialLog",1,0);
          DOIFtoolsSetNotifyDev($hash,1,1);
        } else {
          readingsSingleUpdate($hash,"specialLog",0,0);
          DOIFtoolsSetNotifyDev($hash,0,1);
        }
  } elsif ($arg eq "statisticsDeviceFilterRegex") {
      $ret = "Bad regexp: starting with *" if($value =~ m/^\*/);
      eval { "Hallo" =~ m/^$value$/ };
      $ret .= "\nBad regexp: $@" if($@);
      if ($ret or !$value) {
        readingsSingleUpdate($hash,"statisticsDeviceFilterRegex", ".*",0);
        return "$ret\nRegexp is set to: .*";
      } else {
        readingsSingleUpdate($hash,"statisticsDeviceFilterRegex", $value,0);
      }
  } else {
      my $hardcoded = "doStatistics:disabled,enabled,deleted specialLog:0,1";
      if (ReadingsVal($pn,"targetDOIF","")) {
        my $tn = ReadingsVal($pn,"targetDOIF","");
        my @rL = ();
        foreach my $key (keys %{$defs{$tn}->{READINGS}}) {
          push @rL, $key if ($key !~ "^(Device|state|error|cmd|e_|timer_|wait_|matched_|last_cmd|mode)");
        }
        my $rL = join(",",@rL);
        return "unknown argument $arg for $pn, choose one of statisticsTYPEs:multiple-strict,.*,$tL sourceAttribute:readingList targetDOIF:$dL deleteReadingsInTargetDOIF:multiple-strict,$rL recording_target_duration:0,1,6,12,24,168 statisticsDeviceFilterRegex statisticsShowRate_ge ".(AttrVal($pn,"DOIFtoolsHideGetSet",0) ? $hardcoded :"");
      } else {
        return "unknown argument $arg for $pn, choose one of statisticsTYPEs:multiple-strict,.*,$tL sourceAttribute:readingList targetDOIF:$dL recording_target_duration:0,1,6,12,24,168 statisticsDeviceFilterRegex statisticsShowRate_ge ".(AttrVal($pn,"DOIFtoolsHideGetSet",0) ? $hardcoded :"");
      }
  }
return $ret;
}

sub DOIFtools_Get($@)
{
  my ($hash, @a) = @_;
  my $pn = $hash->{NAME};
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";
  my $ret="";
  my @ret=();
  my @doifList = devspec2array("TYPE=DOIF");
  my @ntL =();
  my $dL = join(",",sort @doifList);

  foreach my $i (@doifList) {
    foreach my $key (keys %{$defs{$i}{READINGS}}) {
      if ($key =~ m/^timer_\d\d_c\d\d/ && $defs{$i}{READINGS}{$key}{VAL} =~ m/.*\|[0-8]+/) {
        push @ntL, $i;
        last;
      }
    }
  }
  my $ntL = join(",",@ntL);

  my %types = ();
  foreach my $d (keys %defs ) {
    next if(IsIgnored($d));
    my $t = $defs{$d}{TYPE};
    $types{$t} = "";
  }

  if ($arg eq "readingsGroup_for") {
      foreach my $i (split(",",$value)) {
        push @ret, DOIFtoolsRg($hash,$i);
      }
      $ret .= join("\n",@ret);
      $ret = "<b>Definition for a simple readingsGroup prepared for import with \"Raw definition\":</b>\r--->\r$ret\r<---\r\r";
      Log3 $pn, 3, $ret if($ret);
      return $ret;
  } elsif ($arg eq "DOIF_to_Log") {
      my @regex = ();
      my $regex = "";
      my $pnLog = "$hash->{TYPE}Log";
      push @regex, $pnLog;
      readingsSingleUpdate($hash,"doif_to_log",$value,0);
      return unless($value);

      foreach my $i (split(",",$value)) {
        push @regex, DOIFtoolsGetAssocDev($hash,$i);
      }
      @regex = keys %{{ map { $_ => 1 } @regex}};
      $regex = join("|",@regex).":.*";
      if (AttrVal($pn,"DOIFtoolsExecuteDefinition","")) {
        push @ret, "Create device <b>$pnLog</b>.\n";
        $ret = CommandDefMod(undef,"$pnLog FileLog ".AttrVal("global","logdir","./log/")."$pnLog-%Y-%j.log $regex");
        push @ret, $ret if($ret);
        $ret = CommandAttr(undef,"$pnLog mseclog ".AttrVal($pnLog,"mseclog","1"));
        push @ret, $ret if($ret);
        $ret = CommandAttr(undef,"$pnLog nrarchive ".AttrVal($pnLog,"nrarchive","3"));
        push @ret, $ret if($ret);
        $ret = CommandSave(undef,undef) if (AttrVal($pn,"DOIFtoolsExecuteSave",""));
        push @ret, $ret if($ret);
        $ret = join("\n", @ret);
        Log3 $pn, 3, $ret if($ret);
        return $ret;
      } else {
        $ret = "<b>Definition for a FileLog prepared for import with \"Raw definition\":</b>\r--->\r";
        $ret .= "defmod $pnLog FileLog ".AttrVal("global","logdir","./log/")."$pnLog-%Y-%j.log $regex\r";
        $ret .= "attr $pnLog mseclog 1\r<---\r\r";
        return $ret;
      }
  } elsif ($arg eq "userReading_nextTimer_for") {
      foreach my $i (split(",",$value)) {
        push @ret, DOIFtoolsNxTimer($hash,$i);
      }
      $ret .= join("\n",@ret);
      Log3 $pn, 3, $ret if($ret);
      return $ret;
  } elsif ($arg eq "statisticsReport") {
      # event statistics
      my $regex = ReadingsVal($pn,"statisticsDeviceFilterRegex",".*");
      my $evtsum = 0;
      my $rate = 0;
      my $typsum = 0;
      my $typerate = 0;
      my $allattr = "";
      my $rx = AttrVal($pn,"DOIFtoolsHideStatReadings","") ? "\.stat_" : "stat_";

      $ret = "<b>".sprintf("%-17s","TYPE").sprintf("%-25s","Name").sprintf("%-12s","Anzahl").sprintf("%-8s","Rate").sprintf("%-12s","<a href=\"https://wiki.fhem.de/wiki/Event#Beschr.C3.A4nken_von_Events\">Begrenzung</a>")."</b>\n";
      $ret .= sprintf("%-17s","").sprintf("%-25s","").sprintf("%-12s","Events").sprintf("%-8s","1/h").sprintf("%-12s","event-on...")."\n";
      $ret .= sprintf("-"x76)."\n";
      my $te = ReadingsVal($pn,".te",0)/3600;
      my $i = 0;
      my $t = 0;
      foreach my $typ (sort keys %types) {
        $typsum = 0;
        $t=0;
        foreach my $key (sort keys %{$defs{$pn}->{READINGS}}) {
          $rate = ($te ? int($hash->{READINGS}{$key}{VAL}/$te + 0.5) : 0) if ($key =~ m/^$rx($regex)/ and $defs{$1}->{TYPE} eq $typ);
          if ($key =~ m/^$rx($regex)/ and $defs{$1}->{TYPE} eq $typ and $rate >= ReadingsNum($pn,"statisticsShowRate_ge",0)) {
              $evtsum += $hash->{READINGS}{$key}{VAL};
              $typsum += $hash->{READINGS}{$key}{VAL};
              $allattr = " ".join(" ",keys %{$attr{$1}});
              $ret .= sprintf("%-17s",$typ).sprintf("%-25s",$1).sprintf("%-12s",$hash->{READINGS}{$key}{VAL}).sprintf("%-8s",$rate).sprintf("%-12s",($allattr =~ " event-on") ? "ja" : "nein")."\n";
              $i++;
              $t++;
          }
        }
        if ($t) {
          $typerate = $te ? int($typsum/$te + 0.5) : 0;
          if($typerate >= ReadingsNum($pn,"statisticsShowRate_ge",0)) {
            $ret .= sprintf("%52s","="x10).sprintf("%2s","  ").sprintf("="x6)."\n";
            $ret .= sprintf("%42s","Summe: ").sprintf("%-10s",$typsum).sprintf("%2s","&empty;:").sprintf("%-8s",$typerate)."\n";
            $ret .= sprintf("%43s","Geräte: ").sprintf("%-10s",$t)."\n";
            $ret .= sprintf("%43s","Events/Gerät: ").sprintf("%-10s",int($typsum/$t + 0.5))."\n";
            $ret .= "<div style=\"color:#d9d9d9\" >".sprintf("-"x71)."</div>";
          }
        }
      }
      $ret .= sprintf("%52s","="x10).sprintf("%2s","  ").sprintf("="x6)."\n";
      $ret .= sprintf("%42s","Summe: ").sprintf("%-10s",$evtsum).sprintf("%2s","&empty;:").sprintf("%-8s",$te ? int($evtsum/$te + 0.5) : "")."\n";
      $ret .= sprintf("%42s","Dauer: ").sprintf("%d:%02d",int($te),int(($te-int($te))*60+.5))."\n";
      $ret .= sprintf("%43s","Geräte: ").sprintf("%-10s",$i)."\n";
      $ret .= sprintf("%43s","Events/Gerät: ").sprintf("%-10s",int($evtsum/$i + 0.5))."\n\n" if ($i);
      fhem("count",1) =~ m/(\d+)/;
      $ret .= sprintf("%43s","Geräte total: ").sprintf("%-10s","$1\n\n");
      $ret .= sprintf("%43s","<u>Filter</u>\n");
      $ret .= sprintf("%42s","TYPE: ").sprintf("%-10s",ReadingsVal($pn,"statisticsTYPEs","")."\n");
      $ret .= sprintf("%35s","NAME: ").sprintf("%-10s",ReadingsVal($pn,"statisticsDeviceFilterRegex",".*")."\n");
      $ret .= sprintf("%35s","Rate: ").sprintf("%-10s","&gt;= ".ReadingsVal($pn,"statisticsShowRate_ge","0")."\n\n");
      $ret .= "<div style=\"color:#d9d9d9\" >".sprintf("-"x71)."</div>";
      # attibute statistics
      $ret .= "<b>".sprintf("%-30s","gesetzte Attribute in DOIF").sprintf("%-12s","Anzahl")."</b>\n";
      $ret .= sprintf("-"x42)."\n";
      my %da = ();
      foreach my $di (@doifList) {
        foreach my $dia (keys %{$attr{$di}}) {
          if ($modules{DOIF}{AttrList} =~ m/(^|\s)$dia(:|\s)/) {
            if ($dia =~ "do|selftrigger|checkall") {
              $dia = "* $dia ".AttrVal($di,$dia,"");
              $da{$dia} = ($da{$dia} ? $da{$dia} : 0) + 1;
            } else {
              $dia = "* $dia";
              $da{$dia} = ($da{$dia} ? $da{$dia} : 0) + 1;
            }
          } else {
            $da{$dia} = ($da{$dia} ? $da{$dia} : 0) + 1;
          }
        }
      }
      foreach $i (sort keys %da) {
        $ret .= sprintf("%-28s","$i").sprintf("%-12s","$da{$i}")."\n"; 
      }
  } elsif ($arg eq "checkDOIF") {
      my @coll = ();
      my $coll = "";
      foreach my $di (@doifList) {
        $coll = DOIFtoolsCheckDOIFcoll($hash,$di);
        push @coll, $coll if($coll);
      }
      $ret .= join(" ",@coll);
      $ret .= "\n<ul><li><b>DOELSIF</b> without <b>DOELSE</b> is o.k., if state changes between, the same condition becomes true again,<br>otherwise use attribute <b>do always</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_do_always\">controlling by events</a>, <a target=\"_blank\" href=\"https://wiki.fhem.de/wiki/DOIF/Einsteigerleitfaden,_Grundfunktionen_und_Erl%C3%A4uterungen#Verhaltensweise_ohne_steuernde_Attribute\">behaviour without attributes</a>)</li></ul> \n" if (@coll);
      foreach my $di (@doifList) {
        $ret .= DOIFtoolsCheckDOIF($hash,$di);
      }
      
      $ret = $ret ? "Found recommendation for:\n\n$ret" : "No recommendation found.";
      return $ret;
      
  } elsif ($arg eq "runningTimerInDOIF") {
      my $erg ="";
      foreach my $di (@doifList) {
        push @ret, sprintf("%-28s","$di").sprintf("%-40s",ReadingsVal($di,"wait_timer",""))."\n" if (ReadingsVal($di,"wait_timer","no timer") ne "no timer");
      }
      $ret .= join("",@ret);
      $ret = $ret ? "Found running wait_timer for:\n\n$ret" : "No running wait_timer found.";
      return $ret;
      
  } else {
      my $hardcoded = "checkDOIF:noArg statisticsReport:noArg runningTimerInDOIF:noArg";
      return "unknown argument $arg for $pn, choose one of readingsGroup_for:multiple-strict,$dL DOIF_to_Log:multiple-strict,$dL userReading_nextTimer_for:multiple-strict,$ntL ".(AttrVal($pn,"DOIFtoolsHideGetSet",1) ? $hardcoded :"");
  } 

  return $ret;
}


1;

=pod
=item helper
=item summary    tools to support DOIF
=item summary_DE Werkzeuge zur Unterstützung von DOIF
=begin html

<a name="DOIFtools"></a>
<h3>DOIFtools</h3>
<ul>
DOIFtools contains tools to support DOIF.<br>
<br>
  <ul>
    <li>create readingsGroup definitions for labeling frontend widgets.</li>
    <li>create a debug logfile for some DOIF and quoted devices with optional device listing each state or wait timer update.</li>
    <li>optional device listing in debug logfile each state or wait timer update.</li>
    <li>navigation between device listings in logfile if opened via DOIFtools.</li>
    <li>create userReadings in DOIF devices displaying real dates for weekday restricted timer.</li>
    <li>delete user defined readings in DOIF devices with multiple choice.</li>
    <li>record statistics data about events.</li>
    <li>limitting recordig duration.</li>
    <li>generate a statistics report.</li>
    <li>lists every DOIF definition in <i>probably associated with</i>.</li>
    <li>access to DOIFtools from any DOIF device via <i>probably associated with</i></li>
    <li>access from DOIFtools to existing DOIFtoolsLog logfiles</li>
    <li>show event monitor in device overview and optionally DOIF</li>
    <li>check definitions and offer recommendations</li>
    <li>create shortcuts</li>
    <li>optionally create a menu entry</li>
    <li>show a list of running wait timer</li>
  </ul>
<br>
Just one definition per FHEM-installation is allowed. <a href="#DOIFtools"More in the german section.</a>
<br>
</ul>
=end html
=begin html_DE

<a name="DOIFtools"></a>
<h3>DOIFtools</h3>
<ul>
DOIFtools stellt Funktionen zur Unterstützung von DOIF-Geräten bereit.<br>
<br>
  <ul>
    <li>erstellen von readingsGroup Definitionen, zur Beschriftung von Frontendelementen.</li>
    <li>erstellen eines Debug-Logfiles, in dem mehrere DOIF und zugehörige Geräte geloggt werden.</li>
    <li>optionales DOIF-Listing bei jeder Status und Wait-Timer Aktualisierung im Debug-Logfile.</li>
    <li>Navigation zwischen den DOIF-Listings im Logfile, wenn es über DOIFtools geöffnet wird.</li>
    <li>erstellen von userReadings in DOIF-Geräten zur Anzeige des realen Datums bei Wochentag behafteten Timern.</li>
    <li>löschen von benutzerdefinierten Readings in DOIF-Definitionen über eine Mehrfachauswahl.</li>
    <li>erfassen statistischer Daten über Events.</li>
    <li>Begrenzung der Datenaufzeichnungsdauer.</li>
    <li>erstellen eines Statistikreports.</li>
    <li>Liste aller DOIF-Definitionen in <i>probably associated with</i>.</li>
    <li>Zugriff auf DOIFtools aus jeder DOIF-Definition über die Liste in <i>probably associated with</i>.</li>
    <li>Zugriff aus DOIFtools auf vorhandene DOIFtoolsLog-Logdateien.</li>
    <li>zeigt den Event Monitor in der Detailansicht von DOIFtools.</li>
    <li>ermöglicht den Zugriff auf den Event Monitor in der Detailansicht von DOIF.</li>
    <li>prüfen der DOIF Definitionen mit Empfehlungen.</li>
    <li>erstellen von Shortcuts</li>
    <li>optionalen Menüeintrag erstellen</li>
    <li>Liste der laufenden Wait-Timer anzeigen</li>
  </ul>
<br>

<a name="DOIFtoolsBedienungsanleitung"></a>
<b>Bedienungsanleitung</b>
<br>
    <ul>
        Eine <a href="https://wiki.fhem.de/wiki/DOIFtools">Bedienungsanleitung für DOIFtools</a> gibt es im FHEM-Wiki.
    </ul>
<br>

<a name="DOIFtoolsDefinition"></a>
<b>Definition</b>
<br>
    <ul>
        <code>define &lt;name&gt; DOIFtools</code><br>
        Es ist nur eine Definition pro FHEM Installation notwendig. Die Definition wird mit den vorhanden DOIF-Namen ergänzt, daher erscheinen alle DOIF-Geräte in der Liste <i>probably associated with</i>. Zusätzlich wird in jedem DOIF-Gerät in dieser Liste auf das DOIFtool verwiesen.<br>
        <br>
        <u>Definitionsvorschlag</u> zum Import mit <a href="https://wiki.fhem.de/wiki/DOIF/Import_von_Code_Snippets">Raw definition</a>:<br>
        <code>
        defmod DOIFtools DOIFtools<br>
        attr DOIFtools DOIFtoolsEventMonitorInDOIF 1<br>
        attr DOIFtools DOIFtoolsExecuteDefinition 1<br>
        attr DOIFtools DOIFtoolsExecuteSave 1<br>
        attr DOIFtools DOIFtoolsMenuEntry 1<br>
        attr DOIFtools DOIFtoolsMyShortcuts ##&lt;br&gt;My Shortcuts:,,list DOIFtools,fhem?cmd=list DOIFtools<br>
        </code>
    </ul>
<br>

<a name="DOIFtoolsSet"></a>
<b>Set</b>
<br>
    <ul>
        <code>set &lt;name&gt; deleteReadingInTargetDOIF &lt;readings to delete name&gt;</code><br>
        <b>deleteReadingInTargetDOIF</b> löscht die benutzerdefinierten Readings im Ziel-DOIF<br>
        <br>
        <code>set &lt;name&gt; targetDOIF &lt;target name&gt;</code><br>
        <b>targetDOIF</b> vor dem Löschen der Readings muss das Ziel-DOIF gesetzt werden.<br>
        <br>
        <code>set &lt;name&gt; sourceAttribute &lt;readingList&gt; </code><br>
        <b>sourceAttribute</b> vor dem Erstellen einer ReadingsGroup muss das Attribut gesetzt werden aus dem die Readings gelesen werden, um die ReadingsGroup zu erstellen und zu beschriften. <b>Default, readingsList</b><br>
        <br>
        <code>set &lt;name&gt; statisticsDeviceFilterRegex &lt;regular expression as device filter&gt;</code><br>
        <b>statisticsDeviceFilterRegex</b> setzt einen Filter auf Gerätenamen, nur die gefilterten Geräte werden im Bericht ausgewertet. <b>Default, ".*"</b>.<br>
        <br>
        <code>set &lt;name&gt; statisticsTYPEs &lt;List of TYPE used for statistics generation&gt;</code><br>
        <b>statisticsTYPEs</b> setzt eine Liste von TYPE für die Statistikdaten erfasst werden, bestehende Statistikdaten werden gelöscht. <b>Default, ""</b>.<br>
        <br>
        <code>set &lt;name&gt; statisticsShowRate_ge &lt;integer value for event rate&gt;</code><br>
        <b>statisticsShowRate_ge</b> setzt eine Event-Rate, ab der ein Gerät in die Auswertung einbezogen wird. <b>Default, 0</b>.<br>
        <br>
        <code>set &lt;name&gt; specialLog &lt;0|1&gt;</code><br>
        <b>specialLog</b> <b>1</b> DOIF-Listing bei Status und Wait-Timer Aktualisierung im Debug-Logfile. <b>Default, 0</b>.<br>
        <br>
        <code>set &lt;name&gt; doStatistics &lt;enabled|disabled|deleted&gt;</code><br>
        <b>doStatistics</b><br>
            &emsp;<b>deleted</b> setzt die Statistik zurück und löscht alle <i>stat_</i> Readings.<br>
            &emsp;<b>disabled</b> pausiert die Statistikdatenerfassung.<br>
            &emsp;<b>enabled</b> startet die Statistikdatenerfassung.<br>
        <br>
        <code>set &lt;name&gt; recording_target_duration &lt;hours&gt;</code><br>
        <b>recording_target_duration</b> gibt an wie lange Daten erfasst werden sollen. <b>Default, 0</b> die Dauer ist nicht begrenzt.<br>
        <br>
    </ul>

<a name="DOIFtoolsGet"></a>
<b>Get</b>
<br>
    <ul>
        <code>get &lt;name&gt; DOIF_to_Log &lt;DOIF names for logging&gt;</code><br>
        <b>DOIF_to_Log</b> erstellt eine FileLog-Definition, die für alle angegebenen DOIF-Definitionen loggt. Der <i>Reguläre Ausdruck</i> wird aus den, direkt in den DOIF-Greräte angegebenen und den wahrscheinlich verbundenen Geräten, ermittelt.<br>
        <br>
        <code>get &lt;name&gt; checkDOIF</code><br>
        <b>checkDOIF</b> führt eine einfache Syntaxprüfung durch und empfiehlt Änderungen.<br>
        <br>
        <code>get &lt;name&gt; readingsGroup_for &lt;DOIF names to create readings groups&gt;</code><br>
        <b>readingsGroup_for</b> erstellt readingsGroup-Definitionen für die angegebenen DOIF-namen. <b>sourceAttribute</b> verweist auf das Attribut, dessen Readingsliste als Basis verwendet wird. Die Eingabeelemente im Frontend werden mit den Readingsnamen beschriftet.<br>
        <br>
        <code>get &lt;name&gt; userReading_nextTimer_for &lt;DOIF names where to create real date timer readings&gt;</code><br>
        <b>userReading_nextTimer_for</b> erstellt userReadings-Attribute für Timer-Readings mit realem Datum für Timer, die mit Wochentagangaben angegeben sind, davon ausgenommen sind indirekte Wochentagsangaben.<br>
        <br>
        <code>get &lt;name&gt; statisticsReport </code><br>
        <b>statisticsReport</b> erstellt einen Bericht aus der laufenden Datenerfassung.<br><br>Die Statistik kann genutzt werden, um Geräte mit hohen Ereignisaufkommen zu erkennen. Bei einer hohen Rate, sollte im Interesse der Systemperformance geprüft werden, ob die <a href="https://wiki.fhem.de/wiki/Event">Events</a> eingeschränkt werden können. Werden keine Events eines Gerätes weiterverarbeitet, kann das Attribut <i>event-on-change-reading</i> auf <i>none</i> oder eine andere Zeichenfolge, die im Gerät nicht als Readingname vorkommt, gesetzt werden.<br>
        <br>
        <code>get &lt;name&gt; runningTimerInDOIF</code><br>
        <b>runningTimerInDOIF</b> zeigt eine Liste der laufenden Timer. Damit kann entschieden werden, ob bei einem Neustart wichtige Timer gelöscht werden und der Neustart ggf. verschoben werden sollte.<br>
        <br>
    </ul>

<a name="DOIFtoolsAttribute"></a>
<b>Attribute</b><br>
    <ul>
        <code>attr &lt;name&gt; DOIFtoolsExecuteDefinition &lt;0|1&gt;</code><br>
        <b>DOIFtoolsExecuteDefinition</b> <b>1</b> führt die erzeugten Definitionen aus. <b>Default 0</b>, zeigt die erzeugten Definitionen an, sie können mit <i>Raw definition</i> importiert werden.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsExecuteSave &lt;0|1&gt;</code><br>
        <b>DOIFtoolsExecuteSave</b> <b>1</b>, die Definitionen werden automatisch gespeichert. <b>Default 0</b>, der Benutzer kann die Definitionen speichern.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsTargetGroup &lt;group names for target&gt;</code><br>
        <b>DOIFtoolsTargetGroup</b> gibt die Gruppen für die zu erstellenden Definitionen an. <b>Default</b>, die Gruppe der Ursprungs Definition.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsTargetRoom &lt;room names for target&gt;</code><br>
        <b>DOIFtoolsTargetRoom</b> gibt die Räume für die zu erstellenden Definitionen an. <b>Default</b>, der Raum der Ursprungs Definition.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsReadingsPrefix &lt;user defined prefix&gt;</code><br>
        <b>DOIFtoolsReadingsPrefix</b> legt den Präfix der benutzerdefinierten Readingsnamen für die Zieldefinition fest. <b>Default</b>, DOIFtools bestimmt den Präfix.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsEventMonitorInDOIF &lt;1|0&gt;</code><br>
        <b>DOIFtoolsEventMonitorInDOIF</b> <b>1</b>, die Anzeige des Event-Monitors wird in DOIF ermöglicht. <b>Default 0</b>, kein Zugriff auf den Event-Monitor im DOIF.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsHideGetSet &lt;0|1&gt;</code><br>
        <b>DOIFtoolsHideModulGetSet</b> <b>1</b>, verstecken der Set- und Get-Shortcuts. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsHideModulShortcuts &lt;0|1&gt;</code><br>
        <b>DOIFtoolsHideModulShortcuts</b> <b>1</b>, verstecken der DOIFtools Shortcuts. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsHideStatReadings &lt;0|1&gt;</code><br>
        <b>DOIFtoolsHideStatReadings</b> <b>1</b>, verstecken der <i>stat_</i> Readings. Das Ändern des Attributs löscht eine bestehende Event-Aufzeichnung. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsMyShortcuts &lt;shortcut name&gt,&lt;command&gt;, ...</code><br>
        <b>DOIFtoolsMyShortcuts</b> &lt;Bezeichnung&gt;<b>,</b>&lt;Befehl&gt;<b>,...</b> anzeigen eigener Shortcuts, siehe globales Attribut <a href="#menuEntries">menuEntries</a>.<br>
        Zusätzlich gilt, wenn ein Eintrag mit ## beginnt und mit ,, endet, wird er als HTML interpretiert.<br>
        <u>Beispiel:</u><br>
        <code>attr DOIFtools DOIFtoolsMyShortcuts ##&lt;br&gt;My Shortcuts:,,list DOIFtools,fhem?cmd=list DOIFtools</code><br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsMenuEntry &lt;0|1&gt;</code><br>
        <b>DOIFtoolsMenuEntry</b> <b>1</b>, erzeugt einen Menüeintrag im FHEM-Menü. <b>Default 0</b>.<br>
        <br>
        <a href="#disabledForIntervals"><b>disabledForIntervals</b></a> pausiert die Statistikdatenerfassung.<br>
        <br>
    </ul>
<a name="DOIFtoolsReadings"></a>
<b>Readings</b>
<br>
    <ul>
    DOIFtools erzeugt bei der Aktualisierung von Readings keine Events, daher muss die Seite im Browser aktualisiert werden, um aktuelle Werte zu sehen.<br>
    <br>
    <li><b>Action</b> zeigt den Status der Event-Aufzeichnung an.</li>
    <li><b>DOIF_version</b> zeigt die Version des DOIF an.</li>
    <li><b>FHEM_revision</b> zeigt die Revision von FHEM an.</li>
    <li><b>doStatistics</b> zeigt den Status der Statistikerzeugung an</li>
    <li><b>logfile</b> gibt den Pfad und den Dateinamen mit Ersetzungszeichen an.</li>
    <li><b>recording_target_duration</b> gibt an wie lange Daten erfasst werden sollen.</li>
    <li><b>stat_</b>&lt;<b>devicename</b>&gt; zeigt die Anzahl der gezählten Ereignisse, die das jeweilige Gerät erzeugt hat.</li>
    <li><b>statisticHours</b> zeigt die kumulierte Zeit für den Status <i>enabled</i> an, während der, Statistikdaten erfasst werden.</li>
    <li><b>statisticShowRate_ge</b> zeigt die Event-Rate, ab der Geräte in die Auswertung einbezogen werden.</li>
    <li><b>statisticsDeviceFilterRegex</b> zeigt den aktuellen Gerätefilterausdruck an.</li>
    <li><b>statisticsTYPEs</b> zeigt eine Liste von <i>TYPE</i> an, für deren Geräte die Statistik erzeugt wird.</li>
    <li><b>specialLog</b> zeigt an ob DOIF-Listing im Log eingeschaltet ist.</li>
    </ul>
</br>
<a name="DOIFtoolsLinks"></a>
<b>Links</b>
<br>
<ul>
<a href="https://forum.fhem.de/index.php/topic,63938.0.html">DOIFtools im FHEM-Forum</a><br>
<a href="https://wiki.fhem.de/wiki/DOIFtools">DOIFtools im FHEM-Wiki</a>
</ul>
</ul>
=end html_DE
=cut

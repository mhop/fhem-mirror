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
use Color;

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
sub DOIFtoolsDeleteStatReadings;

my @DOIFtools_we = [0,0,0,0,0,0,0,0];
my $DOIFtoolsJSfuncEM = <<'EOF';
<script type="text/javascript">
//functions
function doiftoolsCopyToClipboard() {
    var r = $("head").attr("root");
    var myFW_root = FW_root;
    if(r)
      myFW_root = r;
    var lang = $('#doiftoolstype').attr('lang');
    var txtarea = document.getElementById("console");
    var start = txtarea.selectionStart;
    var finish = txtarea.selectionEnd;
    var txt = $("textarea#console").text().substring(start, finish);
    var hlp = lang ? "Bitte, genau eine komplette Eventzeile markieren." : "Please highlight exactly one complete event line.";
    $('#console').attr('disabled', 'disabled');
    $('#console').removeAttr('disabled');
    if(!txt)
      return FW_okDialog(hlp);
    var redi=/^....-..-..\s..:..:..(\....)?\s([^\s]+)\s([^\s]+)\s([^\s]+:\s)?(.*)([\n]*)?$/;
    var retdi = txt.match(redi);
    if(!retdi)
      return FW_okDialog("\""+txt+"\" "+(lang ? "ist keine gültige Auswahl." : "is not a valid selection.")+"<br>"+hlp);
    var evtDev = retdi[3];
    var retdi1;
    var evtRead ="";
    var evtVal ="";
    if (retdi[4]) {
      retdi1 = retdi[4].match(/(.*):\s$/);
      evtRead = retdi1[1];
    }
    evtVal = retdi[5];
    var treffer = evtVal.match(/(-?\d+(\.\d+)?)/);
    var evtNum;
    try {
      evtNum = treffer[1];
    } catch (e) {
      evtNum = "";
    }

    var treffer = evtVal.match(/(\d\d:\d\d)/);
    var evtHM;
    try {
      evtHM = treffer[1];
    } catch (e) {
      evtHM = "";
    }

    var treffer = evtVal.match(/^(\d\d:\d\d(:\d\d)?)$/);
    var evtHMex;
    try {
      evtHMex = treffer[1];
    } catch (e) {
      evtHMex = "";
    }

    var evtEvt = evtVal.replace(/\s/g, ".")
                       .replace(/[\^\$\[\]\(\)\\]/g, function(s){return"\\"+s});

    var diop = [];
    var diophlp = [];
    var icnt = 0;
    diophlp[icnt] = lang ? "a) einfacher auslösender Zugriff auf ein Reading-Wert eines Gerätes oder auf den Wert des Internal STATE, wenn kein Reading im Ereignis vorkommt" : "a) simple triggering access to device reading or internal STATE";
    diop[icnt] = "["+evtDev+(evtRead ? ":"+evtRead : "")+"]"; icnt++;
    
    diophlp[icnt] = lang ? "b) wie a), zusätzlich mit Angabe eines Vergleichsoperators für Zeichenketten (eq &#8793; equal) und Vergleichswert" : "b) like a) additionally with string operator (eq &#8793; equal) and reference value";
    diop[icnt] = "["+evtDev+(evtRead ? ":"+evtRead : "")+"] eq \""+evtVal+"\""; icnt++;
    
    if (evtNum != "") {
        diophlp[icnt] = lang ? "c) wie a) aber mit Zugriff nur auf die erste Zahl der Wertes und eines Vergleichsoperators für Zahlen (==) und numerischem Vergleichswert" : "c) like a) but with access to the first number and a relational operator for numbers (==) and a numeric reference value";
        diop[icnt] = "["+evtDev+(evtRead ? ":"+evtRead : ":state")+":d] == "+evtNum; icnt++;}
        
    if (evtHM != "") {
        diophlp[icnt] = lang ? "d) wie a) aber mit Filter für eine Zeitangabe (hh:mm), einer Zeitvorgabe für nicht existierende Readings/Internals, zusätzlich mit Angabe eines Vergleichsoperators für Zeichenketten (ge &#8793; greater equal) und Vergleichswert" : "d) like a) with filter for time (hh:mm), default value for nonexisting readings or Internals and a relational string operator (ge &#8793; greater equal) and a reference value";
        diop[icnt] = "["+evtDev+(evtRead ? ":"+evtRead : ":state")+":\"(\\d\\d:\\d\\d)\",\"00:00\"] ge $hm"; icnt++;
        
        diophlp[icnt] = lang ? "e1) Zeitpunkt (hh:mm) als Auslöser" : "e1) time specification (hh:mm) as trigger";
        diop[icnt] = "["+evtHM+"]"; icnt++;}
        
    if (evtHMex != "") {
        diophlp[icnt] = lang ? "e2) indirekte Angabe eines Zeitpunktes als Auslöser" : "e2) indirect time specification as trigger";
        diop[icnt] = "[["+evtDev+(evtRead ? ":"+evtRead : "")+"]]"; icnt++;}
        
    diophlp[icnt] = lang ? "f) auslösender Zugriff auf ein Gerät mit Angabe eines \"regulären Ausdrucks\" für ein Reading mit beliebigen Reading-Wert" : "f) triggering access to a device with \"regular expression\" for a reading with arbitrary value";
    diop[icnt] = "["+evtDev+(evtRead ? ":\"^"+evtRead+": " : ":\"")+"\"]"; icnt++;
    
    diophlp[icnt] = lang ? "g) Zugriff mit Angabe eines \"regulären Ausdrucks\" für ein Gerät und ein Reading mit beliebigen Reading-Wert" : "g) access by a \"regular expression\" for a device and a reading with arbitrary value";
    diop[icnt] = "[\"^"+evtDev+(evtRead ? "$:^"+evtRead+": " : "$: ")+"\"]"; icnt++;
    
    diophlp[icnt] = lang ? "h) Zugriff mit Angabe eines \"regulären Ausdrucks\" für ein Gerät und ein Reading mit exaktem Reding-Wert" : "h) access by a \"regular expression\" for a device and a reading with distinct value";
    diop[icnt] = "[\"^"+evtDev+(evtRead ? "$:^"+evtRead+": " : "$:^")+evtEvt+"$\"]"; icnt++;
    
    if (evtHM != "") {
        diophlp[icnt] = lang ? "i) Zugriff mit Angabe eines \"regulären Ausdrucks\" für ein Gerät und ein Reading mit Filter für eine Zeitangabe (hh:mm), einer Zeitvorgabe falls ein anderer Operand auslöst" : "i) access by a \"regular expression\" for a device and a reading and a filter for a time value (hh:mm), a default value in case a different operator triggers and a relational string operator (ge &#8793; greater equal) and a reference value";
        diop[icnt] = "[\"^"+evtDev+(evtRead ? "$:^"+evtRead+"\"" : "$:\"")+":\"(\\d\\d:\\d\\d)\",\"00:00\"] ge $hm"; icnt++}
    var maxlength = 33;
    for (var i = 0; i < diop.length; i++)
        maxlength = diop[i].length > maxlength ? diop[i].length : maxlength;

    // build the dialog
    var txt = '<style type="text/css">\n'+
              'div.opdi label { display:block; margin-left:2em; font-family:Courier}\n'+
              'div.opdi input { float:left; }\n'+
              '</style>\n';
    var inputPrf = "<input type='radio' name=";

    txt += (lang ? "Bitte einen Opranden wählen." : "Select an Operand please.") + "<br><br>";
    for (var i = 0; i < diop.length; i++) {
        txt += "<div class='opdi'>"+inputPrf+"'opType' id='di"+i+"' />"+
           "<label title='"+diophlp[i]+"' >"+diop[i]+"</label></div><br>";
    }

    if ($('#doiftoolstype').attr('devtype') == 'doif') {
        txt += "<input class='opdi' id='opditmp' type='text' size='"+(maxlength+10)+"' style='font-family:Courier' title='"+
        (lang ? "Der gewählte Operand könnte vor dem Kopieren geändert werden." : "The selected operand may be changed before copying.")+
        "' ></input>";
    } else if ($('#doiftoolstype').attr('devtype') == 'doiftools') {
        txt += "<input newdev='' class='opdi' id='opditmp' type='text' size='"+(maxlength+36)+"' style='font-family:Courier' title='"+
        (lang ? "Die Definition kann vor der Weiterverarbeitung angepasst werden." : "The definition may be changed before processing.")+
        "' ></input>";
    }

    $('body').append('<div id="evtCoM" style="display:none">'+txt+'</div>');
    if ($('#doiftoolstype').attr('devtype') == 'doif') {
      $('#evtCoM').dialog(
        { modal:true, closeOnEscape:true, width:"auto",
          close:function(){ $('#evtCoM').remove(); },
          buttons:[
          { text:"Cancel", click:function(){ $(this).dialog('close'); }},
          { text:"Open DEF-Editor", title:(lang ? "Kopiert die Eingabezeile in die Zwischenablage und öffnet den DEF-Editor der aktuellen Detailansicht. Mit Strg-v kann der Inhalt der Zwischenablage in die Definition eingefügt werden." : "Copies the input line to clipboard and opens the DEF editor of the current detail view. Paste the content of the clipboard to the editor by using ctrl-v"), click:function(){
            $("input#opditmp").select();
            document.execCommand("copy");
            if ($("#edit").css("display") == "none")
              $("#DEFa").click();
              $(this).dialog('close');
            }}],
          open:function(){
            $("#evtCoM input[name='opType'],#evtCoM select").change(doiftoolsOptChanged);
          }
        });
    } else if ($('#doiftoolstype').attr('devtype') == 'doiftools') {
      $('#evtCoM').dialog(
        { modal:true, closeOnEscape:true, width:"auto",
          close:function(){ $('#evtCoM').remove(); },
          buttons:[
          { text:"Cancel", click:function(){ $(this).dialog('close'); }},
          { text:"Execute Definition", title:(lang ? "Führt den define-Befehl aus und öffnet die Detailansicht des erzeugten Gerätes." : "Executes the define command and opens the detail view of the created device."), click:function(){
            FW_cmd(myFW_root+"?cmd="+$("input#opditmp").val()+"&XHR=1");
            $("input[class='maininput'][name='cmd']").val($("input#opditmp").val());
            var newDev = $("input#opditmp").val();
            $(this).dialog('close');
            var rex = newDev.match(/define\s+(.*)\s+DOIF/);
            try {
            location = myFW_root+'?detail='+rex[1];
            } catch (e) {
            
            }
            }}],
          open:function(){
            $("#evtCoM input[name='opType'],#evtCoM select").change(doiftoolsOptChanged);
          }
        });
    }

}

function doiftoolsOptChanged() {
    if ($('#doiftoolstype').attr('devtype') == 'doif') {
      $("input#opditmp").val($("#evtCoM input:checked").next("label").text());
    } else if ($('#doiftoolstype').attr('devtype') == 'doiftools') {
      var N = 8;
      var newDev = Array(N+1).join((Math.random().toString(36)+'00000000000000000').slice(2, 18)).slice(0, N);
      $("input#opditmp").val('define newDevice_'+newDev+' DOIF ('+$("#evtCoM input:checked").next("label").text()+') ()');
      var inpt = document.getElementById("opditmp");
      inpt.focus();
      inpt.setSelectionRange(7,17+N);
    }
}
function doiftoolsReplaceBR() {
        $("textarea#console").html($("textarea#console").html().replace(/<br(.*)?>/g,""));
}

function delbutton() {
    if ($('#doiftoolstype').attr('embefore') == 1) {
      var ins = document.getElementsByClassName('makeTable wide readings');
      var del = document.getElementById('doiftoolscons');
      if (del) {
        ins[0].parentNode.insertBefore(del,ins[0]);
      }
    }
    var del = document.getElementById('addRegexpPart');
    if (del) {
      $( window ).off( "load", delbutton );
      del.parentNode.removeChild(del);
    }
}
  //execute
  $( window ).on( "load", delbutton );
  $('#console').on('select', doiftoolsCopyToClipboard);
  $('#console').on('mouseover',doiftoolsReplaceBR);
</script>
EOF
my $DOIFtoolsJSfuncStart = <<'EOF';
<script type="text/javascript">
//functions
function doiftoolsRemoveLookUp () {
    $('#addLookUp').dialog( "close" );
}
function doiftoolsAddLookUp () {
    var tn = $(this).text();
    var target = this;
    var txt = "Internals<table class='block wide internals' style='font-size:12px'>";
    FW_cmd(FW_root+"?cmd=jsonlist2 "+tn+"&XHR=1", function(data){
      var devList = JSON.parse(data);
      var dev = devList.Results[0];
      var row = 0;
      for (var item in dev.Internals) {
        if (item == "DEF") {dev.Internals[item] = "<pre>"+dev.Internals[item]+"</pre>"}
        var cla = ((row++&1)?"odd":"even");
        txt += "<tr class='"+cla+"'><td>"+item+"</td><td>"+dev.Internals[item].replace(/\n/g,"<br>")+"</td></tr>\n";
      }
      txt += "</table>Readings<table class='block wide readings' style='font-size:12px'><br>";
      row = 0;
      for (var item in dev.Readings) {
        var cla = ((row++&1)?"odd":"even");
        txt += "<tr class='"+cla+"'><td>"+item+"</td><td>"+dev.Readings[item].Value+"</td><td>"+dev.Readings[item].Time+"</td></tr>\n";
      }
      txt += "</table>Attributes<table class='block wide attributes' style='font-size:12px'><br>";
      row = 0;
      for (var item in dev.Attributes) {
        if (item.match(/(userReadings|wait|setList)/) ) {dev.Attributes[item] = "<pre>"+dev.Attributes[item]+"</pre>"}
        var cla = ((row++&1)?"odd":"even");
        txt += "<tr class='"+cla+"'><td>"+item+"</td><td>"+dev.Attributes[item]+"</td></tr>\n";
      }
      txt += "</table>";
      $('#addLookUp').html(txt);
      $('#addLookUp').dialog("open");
    });
}
$(document).ready(function(){
    $('body').append('<div id="addLookUp" style="display:none"></div>');
    $('#addLookUp').dialog({
        width:"60%",
        height:"auto",
        maxHeight:900,
        modal: false,
        position: { at: "right"},
        collusion: "fit fit",
        buttons: [
          {
            text: "Ok",
            style:"margin-right: 100%",
            click: function() {
              $( this ).dialog( "close" );
            }
          }
        ]
    });
    $('#addLookUp').dialog( "close" );
    $(".assoc").find("a:even").each(function() {
        $(this).on("mouseover",doiftoolsAddLookUp);
    });
    $("table[class*='block wide']").each(function() {
        $(this).on("mouseenter",doiftoolsRemoveLookUp);
    });
});
</script>
EOF

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

  $hash->{AttrList} = "DOIFtoolsExecuteDefinition:1,0 DOIFtoolsTargetRoom DOIFtoolsTargetGroup DOIFtoolsExecuteSave:1,0 DOIFtoolsReadingsPrefix DOIFtoolsEventMonitorInDOIF:1,0 DOIFtoolsHideModulShortcuts:1,0 DOIFtoolsHideGetSet:1,0 DOIFtoolsMyShortcuts:textField-long DOIFtoolsMenuEntry:1,0 DOIFtoolsHideStatReadings:1,0 DOIFtoolsEventOnDeleted:1,0 DOIFtoolsEMbeforeReadings:1,0 DOIFtoolsNoLookUp:1,0 DOIFtoolsNoLookUpInDOIF:1,0 DOIFtoolsLogDir disabledForIntervals ".$oldAttr; #DOIFtoolsForceGet:true 
}

sub DOIFtools_dO ($$$$){
return "";}

# FW_detailFn for DOIF injecting event monitor
sub DOIFtools_eM($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my @dtn = devspec2array("TYPE=DOIFtools"); 
  my $lang = AttrVal("global","language","EN");
  my $ret = "";
  # call DOIF_detailFn
  no strict "refs";
  my $retfn = &{ReadingsVal($dtn[0],".DOIF_detailFn","")}($FW_wname, $d, $room, $pageHash) if (ReadingsVal($dtn[0],".DOIF_detailFn",""));
  $ret .= $retfn if ($retfn);
  use strict "refs";
  if (!$room) {
      # LookUp in probably associated with
      $ret .= $DOIFtoolsJSfuncStart if (!AttrVal($dtn[0],"DOIFtoolsNoLookUpInDOIF",""));
      # Event Monitor
      if (AttrVal($dtn[0],"DOIFtoolsEventMonitorInDOIF","")) {
        my $a0 = ReadingsVal($d,".eM", "off") eq "on" ? "off" : "on";
        $ret .= "<br>" if (ReadingsVal($dtn[0],".DOIF_detailFn",""));
        $ret .= "<table class=\"block\"><tr><td><div class=\"dval\"><span title=\"".($lang eq "DE" ? "toggle schaltet den Event-Monitor ein/aus" : "toggle switches event monitor on/off")."\">Event monitor: <a href=\"$FW_ME?detail=$d&amp;cmd.$d=setreading $d .eM $a0$FW_CSRF\">toggle</a>&nbsp;&nbsp;</span>";
        $ret .= "</div></td>";
        $ret .= "</tr></table>";

        my $a = "";
        if (ReadingsVal($d,".eM","off") eq "on") {
          $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/console.js\"></script>";
          my $filter = $a ? ($a eq "log" ? "global" : $a) : ".*";
          $ret .= "<div id='doiftoolscons'>";
          my $embefore = AttrVal($dtn[0],"DOIFtoolsEMbeforeReadings","0") ? "1" : "";
          $ret .= "<div id='doiftoolstype' devtype='doif' embefore='".$embefore."' lang='".($lang eq "DE" ? 1 : 0)."'><br>";
          $ret .= "Events (Filter: <a href=\"#\" id=\"eventFilter\">$filter</a>) ".
              "&nbsp;&nbsp;<span id=\"doiftoolsdel\" class='fhemlog'>FHEM log ".
                    "<input id='eventWithLog' type='checkbox'".
                    ($a && $a eq "log" ? " checked":"")."></span>".
              "&nbsp;&nbsp;<button id='eventReset'>Reset</button>".($lang eq "DE" ? "&emsp;<b>Hinweis:</b> Eventzeile markieren, Operanden auswählen, Definition ergänzen" : "&emsp;<b>Hint:</b> select event line, choose operand, modify definition")."</div>\n";
          $ret .= "<textarea id=\"console\" style=\"width:99%; top:.1em; bottom:1em; position:relative;\" readonly=\"readonly\" rows=\"25\" cols=\"60\" title=\"".($lang eq "DE" ? "Die Auswahl einer Event-Zeile zeigt Operanden für DOIF an, sie können im DEF-Editor eingefügt werden (Strg V)." : "Selecting an event line displays operands for DOIFs definition, they can be inserted to DEF-Editor (Ctrl V).")."\" ></textarea>";
          $ret .= "</div>";
          $ret .= $DOIFtoolsJSfuncEM;
        }
      }
  }
  return $ret ? $ret : undef;
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
    FW_pO "<pre class=\"log\"><b>jump to: <a name='top'></a><a href=\"#end_of_file\">the end</a> <a href=\"#listing\">top listing</a></b><br>";
    my $suffix = "<br/><b>jump to: <a name='end_of_file'></a><a href='#top'>the top</a> <a href=\"#listing\">top listing</a></b><br/></pre>".($FW_ss ? "</div>" : "")."</div>";

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
  # $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/myfunction.js\"></script>";
  $ret .= $DOIFtoolsJSfuncStart if ($DOIFtoolsJSfuncStart && !AttrVal($d,"DOIFtoolsNoLookUp",""));
  # Logfile Liste
  if($FW_ss && $pageHash) {
        $ret.= "<div id=\"$d\" align=\"center\" class=\"FileLog col2\">".
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
  $ret .= "<div class=\"dval\"><table>";
  $ret .= "<tr><td><span title=\"toggle to switch event monitor on/off\">Event monitor: <a href=\"$FW_ME?detail=$d&amp;cmd.$d=setreading $d .eM $a0$FW_CSRF\">toggle</a>&nbsp;&nbsp;</span>";
  if (!AttrVal($d,"DOIFtoolsHideModulShortcuts",0)) {
    $ret .= "Shortcuts: ";
    $ret .= "<a href=\"$FW_ME?detail=$d&amp;cmd.$d=reload 98_DOIFtools.pm$FW_CSRF\">reload DOIFtools</a>&nbsp;&nbsp;" if(ReadingsVal($d,".debug",""));
    $ret .= "<a href=\"$FW_ME?detail=$d&amp;cmd.$d=update check$FW_CSRF\">update check</a>&nbsp;&nbsp;";
    $ret .= "<a href=\"$FW_ME?detail=$d&amp;cmd.$d=update$FW_CSRF\">update</a>&nbsp;&nbsp;";
    $ret .= "<a href=\"$FW_ME?detail=$d&amp;cmd.$d=shutdown restart$FW_CSRF\">shutdown restart</a>&nbsp;&nbsp;";
    $ret .= "<a href=\"$FW_ME?detail=$d&amp;cmd.$d=fheminfo send$FW_CSRF\">fheminfo send</a>&nbsp;&nbsp;";
  }
  $ret .= "</td></tr>";
  if (AttrVal($d,"DOIFtoolsMyShortcuts","")) {
  $ret .= "<tr><td>";
    my @sc = split(",",AttrVal($d,"DOIFtoolsMyShortcuts",""));
    for (my $i = 0; $i < @sc; $i+=2) {
      if ($sc[$i] =~ m/^\#\#(.*)/) {
        $ret .= "$1&nbsp;&nbsp;";
      } else {
        $ret .= "<a href=\"/$sc[$i+1]$FW_CSRF\">$sc[$i]</a>&nbsp;&nbsp;" if($sc[$i] and $sc[$i+1]);
      }
    }
    $ret .= "</td></tr>";
  }
  $ret .= "</table>";

  if (!AttrVal($d, "DOIFtoolsHideGetSet", 0)) {
      my $a1 = ReadingsVal($d,"doStatistics", "disabled") =~ "disabled|deleted" ? "enabled" : "disabled"; 
      my $a2 = ReadingsVal($d,"specialLog", 0) ? 0 : 1; 
      $ret .= "<table ><tr>";
      # set doStatistics enabled/disabled
      $ret .= "<td><form method=\"post\" action=\"$FW_ME\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">";
      $ret .= FW_hidden("fwcsrf", $defs{$FW_wname}{CSRFTOKEN}) if($FW_CSRF);
      $ret .= "<input name=\"dev.set$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.set$d\" value=\"set\" class=\"set\" type=\"submit\">
      <div class=\"set downText\">&nbsp;doStatistics $a1&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-doStatistics\">
      <input name=\"val.set$d\" value=\"doStatistics $a1\" type=\"hidden\">
      </div></form></td>";
      # set doStatistics deleted
      $ret .= "<td><form method=\"post\" action=\"$FW_ME\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">";
      $ret .= FW_hidden("fwcsrf", $defs{$FW_wname}{CSRFTOKEN}) if($FW_CSRF);
      $ret .= "<input name=\"dev.set$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.set$d\" value=\"set\" class=\"set\" type=\"submit\">
      <div class=\"set downText\">&nbsp;doStatistics deleted&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-doStatistics\">
      <input name=\"val.set$d\" value=\"doStatistics deleted\" type=\"hidden\">
      </div></form></td>";
      # set specialLog 0/1
      $ret .= "<td><form method=\"post\" action=\"$FW_ME\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">";
      $ret .= FW_hidden("fwcsrf", $defs{$FW_wname}{CSRFTOKEN}) if($FW_CSRF);
      $ret .= "<input name=\"dev.set$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.set$d\" value=\"set\" class=\"set\" type=\"submit\">
      <div class=\"set downText\">&nbsp;specialLog $a2&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-doStatistics\">
      <input name=\"val.set$d\" value=\"specialLog $a2\" type=\"hidden\">
      </div></form></td>";
      $ret .= "</tr><tr>";
      # get statisticsReport
      $ret .= "<td><form method=\"post\" action=\"$FW_ME\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.get$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.get$d\" value=\"get\" class=\"get\" type=\"submit\">
      <div class=\"get downText\">&nbsp;statisticsReport&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-statisticsReport\">
      <input name=\"val.get$d\" value=\"statisticsReport\" type=\"hidden\">
      </div></form></td>";
      # get checkDOIF
      $ret .= "<td><form method=\"post\" action=\"$FW_ME\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.get$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.get$d\" value=\"get\" class=\"get\" type=\"submit\">
      <div class=\"get downText\">&nbsp;checkDOIF&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-checkDOIF\">
      <input name=\"val.get$d\" value=\"checkDOIF\" type=\"hidden\">
      </div></form></td>";
      # get runningTimerInDOIF
      $ret .= "<td><form method=\"post\" action=\"$FW_ME\" autocomplete=\"off\">
      <input name=\"detail\" value=\"$d\" type=\"hidden\">
      <input name=\"dev.get$d\" value=\"$d\" type=\"hidden\">
      <input name=\"cmd.get$d\" value=\"get\" class=\"get\" type=\"submit\">
      <div class=\"get downText\">&nbsp;runningTimerInDOIF&emsp;</div>
      <div style=\"display:none\" class=\"noArg_widget\" informid=\"$d-runningTimerInDOIF\">
      <input name=\"val.get$d\" value=\"runningTimerInDOIF\" type=\"hidden\">
      </div></form></td>";
      $ret .= "</tr></table>";
  }
  $ret .= "</div>";
  my $a = "";
  if (ReadingsVal($d,".eM","off") eq "on") {
    my $lang = AttrVal("global","language","EN");
    $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/console.js\"></script>";
    # $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/doiftools.js\"></script>";
    my $filter = $a ? ($a eq "log" ? "global" : $a) : ".*";
    $ret .= "<div><table><tr><td>";
    $ret .= "Events (Filter: <a href=\"#\" id=\"eventFilter\">$filter</a>) ".
          "&nbsp;&nbsp;<span id=\"doiftoolsdel\" class='fhemlog'>FHEM log ".
                "<input id='eventWithLog' type='checkbox'".
                ($a && $a eq "log" ? " checked":"")."></span>".
          "&nbsp;&nbsp;<button id='eventReset'>Reset</button>".($lang eq "DE" ? "&emsp;<b>Hinweis:</b> Eventzeile markieren, Operanden auswählen, neue Definition erzeugen" : "&emsp;<b>Hint:</b> select event line, choose operand, create definition")."</td></tr></table></div>\n";
    my $embefore = AttrVal($d,"DOIFtoolsEMbeforeReadings","0") ? "1" : "";
    $ret .= "<div id='doiftoolstype' devtype='doiftools' embefore='".$embefore."' lang='".($lang eq "DE" ? 1 : 0)."'>";
    $ret .= "<textarea id=\"console\" style=\"width:99%; top:.1em; bottom:1em; position:relative;\" readonly=\"readonly\" rows=\"25\" cols=\"60\" title=\"".($lang eq "DE" ? "Die Auswahl einer Event-Zeile zeigt Operanden für DOIF an, mit ihnen kann eine neue DOIF-Definition erzeugt werden." : "Selecting an event line displays operands for DOIFs definition, they are used to create a new DOIF definition.")."\"></textarea>";
    $ret .= "</div>";
    $ret .= $DOIFtoolsJSfuncEM;
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
      $val = CommandGet(undef,"$sn days $i");
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
      $trig .= $prev ? "<b>jump to: <a href=\"#list$prev\">prev</a>&nbsp;&nbsp;<a href=\"#list$next\">next</a> Listing</b><br>" : "<b>jump to: prev&nbsp;&nbsp;<a href=\"#list$next\">next</a> Listing</b><br>";
      $trig .= "DOIF-Version: ".ReadingsVal($pn,"DOIF_version","n/a")."<br>";
      $trig .= CommandList(undef,$sn);
      foreach my $itm (keys %defs) {
        $trig =~ s,([\[\" ])$itm([\"\:\] ]),$1<a href="$FW_ME?detail=$itm">$itm</a>$2,g;
      }
      CommandTrigger(undef,"$hash->{TYPE}Log $trig");
    }
    # DOIFtools DEF addition
    if ($sn eq "global" and $event =~ "^INITIALIZED\$|^MODIFIED|^DEFINED|^DELETED|^RENAMED|^UNDEFINED") {
      my @doifList = devspec2array("TYPE=DOIF");
      $hash->{DEF} = "associated DOIF: ".join(" ",sort @doifList);
      readingsSingleUpdate($hash,"DOIF_version",fhem("version 98_DOIF.pm noheader",1),0);
    }
    # get DOIF version, FHEM revision and default values
    if ($sn eq "global" and $event =~ "^INITIALIZED\$|^MODIFIED $pn") {
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
      # CommandSave(undef,undef);
    }
    # Event monitor in DOIF FW_detailFn
    if ($modules{DOIF}{LOADED} and (!$modules{DOIF}->{FW_detailFn} or $modules{DOIF}->{FW_detailFn} and $modules{DOIF}->{FW_detailFn} ne "DOIFtools_eM") and $sn eq "global" and $event =~ "^INITIALIZED\$" ) {
        readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,".DOIF_detailFn",$modules{DOIF}->{FW_detailFn});
          $modules{DOIF}->{FW_detailFn} = "DOIFtools_eM";
          readingsBulkUpdate($hash,".DOIFdO",$modules{DOIF}->{FW_deviceOverview});
          $modules{DOIF}->{FW_deviceOverview} = 1;
        readingsEndUpdate($hash,0);
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

# DOIFtoolsLinColorGrad(start_color,end_color,percent|[$min,max,current])
# start_color, end_color: 6 hexadecimal values as string with or without leading #
# percent: from 0 to 1
# min: minmal value
# max: maximal value
# current: current value
# return: 6 hexadecimal value as string, prefix depends on input
sub DOIFtoolsLinColorGrad {
  my ($sc,$ec,$pct,$max,$cur) = @_;
  $pct = ($cur-$pct)/($max-$pct) if (@_ == 5);
  my $prefix = "";
  $prefix = "#" if ("$sc $ec"=~"#");
  $sc =~ s/^#//;
  $ec =~ s/^#//;
  $pct = $pct > 1 ? 1 : $pct;
  $pct = $pct < 0 ? 0 : $pct;
  $sc =~/([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})/;
  my @sc = (hex($1),hex($2),hex($3));
  $ec =~/([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})/;
  my @ec = (hex($1),hex($2),hex($3));
  my @rgb;
  for (0..2) {
    $rgb[$_] = sprintf("%02X", int(($ec[$_] - $sc[$_])*$pct + $sc[$_] + .5));
  }
  return $prefix.join("",@rgb);
}

sub DOIFtoolsHsvColorGrad {
  my ($cur,$min,$max,$min_s,$max_s,$s,$v)=@_;
  
  my $m=($max_s-$min_s)/($max-$min);
  my $n=$min_s-$min*$m;
  if ($cur>$max) {
   $cur=$max;
  } elsif ($cur<$min) {
    $cur=$min;
  }
    
  my $h=$cur*$m+$n;
  $h /=360;
  $s /=100;
  $v /=100;  
  
  my($r,$g,$b)=Color::hsv2rgb ($h,$s,$v);
  $r *= 255;
  $g *= 255;
  $b *= 255;
  return sprintf("#%02X%02X%02X", $r+0.5, $g+0.5, $b+0.5);
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
  my ($timer_str,$tn) = @_;
  $timer_str =~ /(\d\d).(\d\d).(\d\d\d\d) (\d\d):(\d\d):(\d\d)\|?(.*)/;
  my $tstr = "$1.$2.$3 $4:$5:$6";
  return $tstr if (length($7) == 0); 
  my $timer = timelocal($6,$5,$4,$1,$2-1,$3);
  my $tdays = "";
  $tdays = $tn ? DOIF_weekdays($defs{$tn},$7) : $7;
  $tdays =~/([0-8])/;
  return $tstr if (length($1) == 0); 
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
  return "no timer next 7 days";
}

sub DOIFtoolsNxTimer {
  my ($hash,$arg) = @_;
  my $pn = $hash->{NAME};
  my $tn= $arg;
  my $thash = $defs{$arg};
  my $ret = "";
  my @ret;
  foreach my $key (keys %{$thash->{READINGS}}) {
    if ($key =~ m/^timer_\d\d_c\d\d/ && $thash->{READINGS}{$key}{VAL} =~ m/\d\d.\d\d.\d\d\d\d \d\d:\d\d:\d\d\|.*/) {
      $ret = AttrVal($pn,"DOIFtoolsReadingsPrefix","N_")."$key:$key.* \{DOIFtoolsNextTimer(ReadingsVal(\"$tn\",\"$key\",\"none\"),\"$tn\")\}";
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
      $ret = "A userReadings attribute already exists, adding is not implemented, try it manually.\r\r $ret\r"; 
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
  my $DE = AttrVal("global", "language", "") eq "DE" ? 1 : 0;
  if ($DE) {
      $ret .= "<li>ersetze <b>DOIF name</b> durch <b>\$SELF</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events\">Auswertung von Events</a>)</li>\n" if ($tail =~ m/[\[|\?]($tn)/);
      $ret .= "<li>ersetze <b>ReadingsVal(...)</b> durch <b>[</b>name<b>:</b>reading<b>,</b>default value<b>]</b>, wenn es nicht in einem <b><a href=\"https://fhem.de/commandref.html#IF\">IF-Befehl</a></b> verwendet wird, dort ist es nicht anders möglich einen Default-Wert anzugeben. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung\">Steuerung durch Events</a>)</li>\n" if ($tail =~ m/(ReadingsVal)/);
      
      $ret .= "<li>ersetze <b>ReadingsNum(...)</b> durch <b>[</b>name<b>:</b>reading<b>:d,</b>default value]</b>, wenn es nicht in einem <b><a href=\"https://fhem.de/commandref.html#IF\">IF-Befehl</a></b> verwendet wird, dort ist es nicht anders möglich einen Default-Wert anzugeben. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Filtern_nach_Zahlen\">Filtern nach Zahlen</a>)</li>\n" if ($tail =~ m/(ReadingsNum)/);
      $ret .= "<li>ersetze <b>InternalVal(...)</b> durch <b>[</b>name<b>:</b>&amp;internal,</b>default value<b>]</b>, wenn es nicht in einem <b><a href=\"https://fhem.de/commandref.html#IF\">IF-Befehl</a></b> verwendet wird, dort ist es nicht anders möglich einen Default-Wert anzugeben. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung\">Steuerung durch Events</a>)</li>\n" if ($tail =~ m/(InternalVal)/);
      $ret .= "<li>ersetze <b>$1...\")}</b> durch <b>$2...</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#command\">FHEM-Befehl</a>)</li>\n" if ($tail =~ m/(\{\s*fhem.*?\"\s*(set|get))/);
      $ret .= "<li>ersetze <b>{system \"</b>&lt;SHELL-Befehl&gt;<b>\"}</b> durch <b>\"</b>\&lt;SHELL-Befehl&gt;<b>\"</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#command\">FHEM SHELL-Befehl, nicht blockierend</a>)</li>\n" if ($tail =~ m/(\{\s*system.*?\})/);
      $ret .= "<li><b>sleep</b> im DOIF zu nutzen, wird nicht empfohlen, nutze das Attribut <b>wait</b> für (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_wait\">Verzögerungen</a>)</li>\n" if ($tail =~ m/(sleep\s\d+\.?\d+\s*[;|,]?)/);
      $ret .= "<li>ersetze <b>[</b>name<b>:?</b>regex<b>]</b> durch <b>[</b>name<b>:\"</b>regex<b>\"]</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events\">Vermeidung veralteter Syntax</a>)</li>\n" if ($tail =~ m/(\[.*?[^"]?:[^"]?\?.*?\])/);

      $ret .= "<li>der erste <b>Befehl</b> nach <b>DOELSE</b> scheint eine  <b>Bedingung</b> zu sein, weil <b>$2</b> enthalten ist, bitte prüfen.</li>\n" if ($tail =~ m/(DOELSE .*?\]\s*?(\!\S|\=\~|\!\~|and|or|xor|not|\|\||\&\&|\=\=|\!\=|ne|eq|lt|gt|le|ge)\s*?).*?\)/);
      my @wait = SplitDoIf(":",AttrVal($tn,"wait",""));
      my @sub0 = ();
      my @tmp = ();
      if (@wait and !AttrVal($tn,"timerWithWait","")) {
        for (my $i = 0; $i < @wait; $i++) {
          ($sub0[$i],@tmp) = SplitDoIf(",",$wait[$i]);
          $sub0[$i] =~ s/\s// if($sub0[$i]);
        }
        if (defined $defs{$tn}{timeCond}) {
          foreach my $key (sort keys %{$defs{$tn}{timeCond}}) {
            if (defined($defs{$tn}{timeCond}{$key}) and $defs{$tn}{timeCond}{$key} and $sub0[$defs{$tn}{timeCond}{$key}]) {
              $ret .= "<li><b>Timer</b> in der <b>Bedingung</b> and <b>Wait-Timer</b> für <b>Befehle</b> im selben <b>DOIF-Zweig</b>.<br>Wenn ein unerwartetes Verhalten beobachtet wird, nutze das Attribut <b>timerWithWait</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_timerWithWait\">Verzögerung von Timern</a>)</li>\n";
              last;
            }
          }
        }
      }
      my $wait = AttrVal($tn,"wait","");
      if ($wait) {
        $ret .= "<li>Mindestens ein <b>indirekter Timer</b> im Attribut <b>wait</b> bezieht sich auf den <b>DOIF-Namen</b> ( $tn ) und hat keinen <b>Default-Wert</b>, er sollte angegeben werden.</b>. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_notexist\">Default-Wert</a>)</li>\n" 
            if($wait =~ m/(\[(\$SELF|$tn).*?(\,.*?)?\])/ and $2 and !$3); 
      }
      if (defined $defs{$tn}{time}) {
        foreach my $key (sort keys %{$defs{$tn}{time}}) {
          if (defined $defs{$tn}{time}{$key} and $defs{$tn}{time}{$key} =~ m/(\[(\$SELF|$tn).*?(\,.*?)?\])/ and $2 and !$3) {
            $ret .= "<li>Mindestens ein <b>indirekter Timer</b> in einer <b>Bedingung</b> bezieht sich auf den <b>DOIF-Namen</b> ( $tn ) und hat keinen <b>Default-Wert</b>, er sollte angegeben werden. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_notexist\">Default-Wert</a>)</li>\n";
            last;
          }
        }
      }
      
      if (defined $defs{$tn}{devices}{all}) {
        @tmp = ();
        my $devi = $defs{$tn}{devices}{all};
        $devi =~ s/^ | $//g;
        my @devi = split(/ /,$defs{$tn}{devices}{all});
        foreach my $key (@devi) {
          push @tmp, $key if (defined $defs{$key} and $defs{$key}{TYPE} eq "dummy");
        }
        if (@tmp) {
          @tmp = keys %{{ map { $_ => 1 } @tmp}};
          my $tmp = join(" ",sort @tmp);
          $ret .= "<li>Dummy-Geräte ( $tmp ) in der Bedingung von DOIF $tn können durch <b>benutzerdefinierte Readings des DOIF</b> ersetzt werden, wenn sie als Frontend-Elemente genutzt werden. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#https://fhem.de/commandref_DE.html#DOIF_setList__readingList\">readingList, setList, webCmd</a>)</li>\n";
        }
      }
      
      if (defined $defs{$tn}{do}) {
        @tmp = ();
        foreach my $key (keys %{$defs{$tn}{do}}) {
          foreach my $subkey (keys %{$defs{$tn}{do}{$key}}) {
            push @tmp, $1 if ($defs{$tn}{do}{$key}{$subkey} =~ m/set (.*?) / and defined $defs{$1} and $defs{$1}{TYPE} eq "dummy");
          }
        }
        if (@tmp) {
          @tmp = keys %{{ map { $_ => 1 } @tmp}};
          my $tmp = join(" ",sort @tmp);
          $ret .= "<li>Statt Dummys ( $tmp ) zu setzen, könnte ggf. der Status des DOIF $tn zur Anzeige im Frontend genutzt werden. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#https://fhem.de/commandref_DE.html#DOIF_cmdState\">DOIF-Status ersetzen</a>)</li>\n";
        }
      }
  } else {
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
        if (defined $defs{$tn}{timeCond}) {
          foreach my $key (sort keys %{$defs{$tn}{timeCond}}) {
            if (defined($defs{$tn}{timeCond}{$key}) and $defs{$tn}{timeCond}{$key} and $sub0[$defs{$tn}{timeCond}{$key}]) {
              $ret .= "<li><b>Timer</b> in <b>condition</b> and <b>wait timer</b> for <b>commands</b> in the same <b>DOIF branch</b>.<br>If you observe unexpected behaviour, try attribute <b>timerWithWait</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_timerWithWait\">delay of Timer</a>)</li>\n";
              last;
            }
          }
        }
      }
      my $wait = AttrVal($tn,"wait","");
      if ($wait) {
        $ret .= "<li>At least one <b>indirect timer</b> in attribute <b>wait</b> is referring <b>DOIF's name</b> ( $tn ) and has no <b>default value</b>, you should add <b>default values</b>. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_notexist\">default value</a>)</li>\n" 
            if($wait =~ m/(\[(\$SELF|$tn).*?(\,.*?)?\])/ and $2 and !$3); 
      }
      if (defined $defs{$tn}{time}) {
        foreach my $key (sort keys %{$defs{$tn}{time}}) {
          if (defined $defs{$tn}{time}{$key} and $defs{$tn}{time}{$key} =~ m/(\[(\$SELF|$tn).*?(\,.*?)?\])/ and $2 and !$3) {
            $ret .= "<li>At least one <b>indirect timer</b> in <b>condition</b> is referring <b>DOIF's name</b> ( $tn ) and has no <b>default value</b>, you should add <b>default values</b>. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_notexist\">default value</a>)</li>\n";
            last;
          }
        }
      }
      
      if (defined $defs{$tn}{devices}{all}) {
        @tmp = ();
        my $devi = $defs{$tn}{devices}{all};
        $devi =~ s/^ | $//g;
        my @devi = split(/ /,$defs{$tn}{devices}{all});
        foreach my $key (@devi) {
          push @tmp, $key if (defined $defs{$key} and $defs{$key}{TYPE} eq "dummy");
        }
        if (@tmp) {
          my $tmp = join(" ",sort @tmp);
          $ret .= "<li>dummy devices  in DOIF $tn condition could replaced by <b>user defined readings</b> in DOIF, if they are used as frontend elements. (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#https://fhem.de/commandref_DE.html#DOIF_setList__readingList\">readingList, setList, webCmd</a>)</li>\n";
        }
      }
      if (defined $defs{$tn}{do}) {
        @tmp = ();
        foreach my $key (keys %{$defs{$tn}{do}}) {
          foreach my $subkey (keys %{$defs{$tn}{do}{$key}}) {
            push @tmp, $1 if ($defs{$tn}{do}{$key}{$subkey} =~ m/set (.*?) / and defined $defs{$1} and $defs{$1}{TYPE} eq "dummy");
          }
        }
        if (@tmp) {
          my $tmp = join(" ",sort @tmp);
          $ret .= "<li>The state of DOIF $tn could be eventually used as display element in frontend, instead of setting a dummy device ( $tmp ). (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#https://fhem.de/commandref_DE.html#DOIF_cmdState\">replace DOIF state</a>)</li>\n";
        }
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
sub DOIFtoolsDeleteStatReadings {
  my ($hash, @a) = @_;
  my $pn = $hash->{NAME};
  my $st = AttrVal($pn,"DOIFtoolsHideStatReadings","") ? ".stat_" : "stat_";  readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"Action","event recording stopped and data deleted");
    readingsBulkUpdate($hash,"doStatistics","disabled");
    readingsBulkUpdate($hash,"statisticHours","0.00");
    readingsBulkUpdate($hash,".t0",gettimeofday());
    readingsBulkUpdate($hash,".te",0);
  readingsEndUpdate($hash,0);
  if (AttrVal($pn,"DOIFtoolsEventOnDeleted","")){
    readingsBeginUpdate($hash);
      foreach my $key (keys %{$hash->{READINGS}}) {
        readingsBulkUpdate($hash,"stat_$1",ReadingsVal($pn,"$key",0)) if ($key =~ m/^$st(.*)/);
      }
    readingsEndUpdate($hash,1);
  }
  foreach my $key (keys %{$hash->{READINGS}}) {
    delete $hash->{READINGS}{$key} if ($key =~ "^(stat_|\.stat_)");
  }
}
#################################
sub DOIFtools_Define($$$)
{
  my ($hash, $def) = @_;
  my ($pn, $type, $cmd) = split(/[\s]+/, $def, 3);
  my @Liste = devspec2array("TYPE=DOIFtools");
  if (@Liste > 1) {
    CommandDelete(undef,$pn);
    # CommandSave(undef,undef);
    return "Only one instance of DOIFtools is allowed per FHEM installation. Delete the old one first.";
  }
  $hash->{STATE} = "initialized";
  $hash->{logfile} = AttrVal($pn,"DOIFtoolsLogDir",AttrVal("global","logdir","./log/"))."$hash->{TYPE}Log-%Y-%j.log";
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
  if ($init_done and $attr eq "DOIFtoolsMenuEntry") {
    if ($cmd eq "set" and $value) {
      if (!(AttrVal($FW_wname, "menuEntries","") =~ m/(DOIFtools\,$FW_ME\?detail\=DOIFtools\,)/)) {
        CommandAttr(undef, "$FW_wname menuEntries DOIFtools,$FW_ME?detail=DOIFtools,".AttrVal($FW_wname, "menuEntries",""));
        # CommandSave(undef, undef);
      }
    } elsif ($init_done and $cmd eq "del" or !$value) {
      if (AttrVal($FW_wname, "menuEntries","") =~ m/(DOIFtools\,$FW_ME\?detail\=DOIFtools\,)/) {
        my $me = AttrVal($FW_wname, "menuEntries","");
        $me =~ s/DOIFtools\,$FW_ME\?detail\=DOIFtools\,//;
        CommandAttr(undef, "$FW_wname menuEntries $me");
        # CommandSave(undef, undef);
      }
    
    }
  } elsif ($init_done and $attr eq "DOIFtoolsLogDir") {
      if ($cmd eq "set") {
        if ($value and -d $value) {
          $value =~ m,^(.*)/$,;
          return "Path \"$value\" needs a final slash." if (!$1);
          $hash->{logfile} = "$value$hash->{TYPE}Log-%Y-%j.log";
        } else {
          return "\"$value\" is not a valid directory";
        }
      } elsif ($cmd eq "del" or !$value) {
        $hash->{logfile} = AttrVal("global","logdir","./log/")."$hash->{TYPE}Log-%Y-%j.log";
      }
  } elsif ($init_done and $attr eq "DOIFtoolsHideStatReadings") {
      DOIFtoolsSetNotifyDev($hash,1,0);
      DOIFtoolsDeleteStatReadings($hash);
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
      $modules{DOIF}->{FW_detailFn} = ReadingsVal($pn,".DOIF_detailFn","");
      $modules{DOIF}->{FW_deviceOverview} = ReadingsVal($pn,".DOIFdO","");
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
  my @deviList = devspec2array("TYPE!=DOIF");
  my @ntL =();
  my $dL = join(",",sort @doifList);
  my $deL = join(",",sort @deviList);
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
      FW_directNotify("#FHEMWEB:$FW_wname", "location.reload('".AttrVal($pn,"DOIFtoolsForceGet","")."')", "");
  } elsif ($arg eq "deleteReadingsInTargetDOIF") {
      if ($value) {
        my @i = split(",",$value);
        foreach my $i (@i) {
          $ret = CommandDeleteReading(undef,ReadingsVal($pn,"targetDOIF","")." $i");
          push @ret, $ret if($ret);
        }
        $ret = join("\n", @ret);
        readingsSingleUpdate($hash,"targetDOIF","",0);
        return $ret;
      } else {
        readingsSingleUpdate($hash,"targetDOIF","",0);
        return "no reading selected.";
      }
  } elsif ($arg eq "targetDevice") {
      readingsSingleUpdate($hash,"targetDevice",$value,0);
      FW_directNotify("#FHEMWEB:$FW_wname", "location.reload('".AttrVal($pn,"DOIFtoolsForceGet","")."')", "");
  } elsif ($arg eq "deleteReadingsInTargetDevice") {
      if ($value) {
        my @i = split(",",$value);
        foreach my $i (@i) {
          $ret = CommandDeleteReading(undef,ReadingsVal($pn,"targetDevice","")." $i");
          push @ret, $ret if($ret);
        }
        $ret = join("\n", @ret);
        readingsSingleUpdate($hash,"targetDevice","",0);
        return $ret;
      } else {
        readingsSingleUpdate($hash,"targetDevice","",0);
        return "no reading selected.";
      }
  } elsif ($arg eq "doStatistics") {
      if ($value eq "deleted") {
        DOIFtoolsSetNotifyDev($hash,1,0);
        DOIFtoolsDeleteStatReadings($hash);
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
        readingsEndUpdate($hash,0);
        DOIFtoolsDeleteStatReadings($hash);
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
      my $retL = "unknown argument $arg for $pn, choose one of statisticsTYPEs:multiple-strict,.*,$tL sourceAttribute:readingList targetDOIF:$dL targetDevice:$deL recording_target_duration:0,1,6,12,24,168 statisticsDeviceFilterRegex statisticsShowRate_ge ".(AttrVal($pn,"DOIFtoolsHideGetSet",0) ? $hardcoded :"");

      if (ReadingsVal($pn,"targetDOIF","")) {
        my $tn = ReadingsVal($pn,"targetDOIF","");
        my @rL = ();
        foreach my $key (keys %{$defs{$tn}->{READINGS}}) {
          push @rL, $key if ($key !~ "^(Device|state|error|cmd|e_|timer_|wait_|matched_|last_cmd|mode|\.eM)");
        }
        $retL .= " deleteReadingsInTargetDOIF:multiple-strict,".join(",", sort @rL);
      }
      if (ReadingsVal($pn,"targetDevice","")) {
        my $tn = ReadingsVal($pn,"targetDevice","");
        my @rL = ();
        my $rx = ReadingsVal($pn,".debug","") ? "^(state)" : "^(state|[.])";
        foreach my $key (keys %{$defs{$tn}->{READINGS}}) {
          push @rL, $key if ($key !~ $rx);
        }
        $retL .= " deleteReadingsInTargetDevice:multiple-strict,".join(",", sort @rL);
      }
      return $retL;
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
  my $DE = AttrVal("global", "language", "") eq "DE" ? 1 : 0;

  foreach my $i (@doifList) {
    foreach my $key (keys %{$defs{$i}{READINGS}}) {
      if ($key =~ m/^timer_\d\d_c\d\d/ && $defs{$i}{READINGS}{$key}{VAL} =~ m/\d\d.\d\d.\d\d\d\d \d\d:\d\d:\d\d\|.*/) {
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
      $ret = "<b>Die Definition einer einfachen readingsGroup ist für den Import mit \"Raw definition\"</b> vorbereitet:\r--->\r$ret\r<---\r\r" if ($DE);
      Log3 $pn, 3, $ret if($ret);
      return $ret;
  } elsif ($arg eq "DOIF_to_Log") {
      my @regex = ();
      my $regex = "";
      my $pnLog = "$hash->{TYPE}Log";
      push @regex, $pnLog;
      readingsSingleUpdate($hash,"doif_to_log",$value,0);
      readingsSingleUpdate($hash,"specialLog",0,0) if (!$value);      
      DOIFtoolsSetNotifyDev($hash,0,1);
      # return unless($value);

      foreach my $i (split(",",$value)) {
        push @regex, DOIFtoolsGetAssocDev($hash,$i);
      }
      @regex = keys %{{ map { $_ => 1 } @regex}};
      $regex = join("|",@regex).":.*";
      if (AttrVal($pn,"DOIFtoolsExecuteDefinition","")) {
        push @ret, "Create device <b>$pnLog</b>.\n";
        $ret = CommandDefMod(undef,"$pnLog FileLog ".InternalVal($pn,"logfile","./log/$pnLog-%Y-%j.log")." $regex");
        push @ret, $ret if($ret);
        $ret = CommandAttr(undef,"$pnLog mseclog ".AttrVal($pnLog,"mseclog","1"));
        push @ret, $ret if($ret);
        $ret = CommandAttr(undef,"$pnLog nrarchive ".AttrVal($pnLog,"nrarchive","3"));
        push @ret, $ret if($ret);
        $ret = CommandAttr(undef,"$pnLog disable ".($value ? "0" : "1"));
        push @ret, $ret if($ret);
        $ret = CommandSave(undef,undef) if (AttrVal($pn,"DOIFtoolsExecuteSave",""));
        push @ret, $ret if($ret);
        $ret = join("\n", @ret);
        Log3 $pn, 3, $ret if($ret);
        return $ret;
      } else {
        $ret = "<b>Definition for a FileLog prepared for import with \"Raw definition\":</b>\r--->\r";
        $ret = "<b>Die FileLog-Definition ist zum Import mit \"Raw definition\"</b>vorbereitet:\r--->\r" if ($DE);
        $ret .= "defmod $pnLog FileLog ".InternalVal($pn,"logfile","./log/$pnLog-%Y-%j.log")." $regex\r";
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
      my $evtlen = 15 + 2;
      my $rate = 0;
      my $typsum = 0;
      my $typlen = 10 + 2;
      my $typerate = 0;
      my $allattr = "";
      my $rx = AttrVal($pn,"DOIFtoolsHideStatReadings","") ? "\.stat_" : "stat_";
      my $te = ReadingsVal($pn,".te",0)/3600;
      my $compRate = ReadingsNum($pn,"statisticsShowRate_ge",0);
      foreach my $typ ( keys %types) {
        $typlen = length($typ)+2 > $typlen ? length($typ)+2 : $typlen;
      }
      foreach my $key (sort keys %{$defs{$pn}->{READINGS}}) {
        $rate = ($te ? int($hash->{READINGS}{$key}{VAL}/$te + 0.5) : 0) if ($key =~ m/^$rx($regex)/);
        if ($key =~ m/^$rx($regex)/ and $rate >= $compRate) {
          $evtlen = length($1)+2 > $evtlen ? length($1)+2 : $evtlen;
        }
      }

      $ret = "<b>".sprintf("%-".$typlen."s","TYPE").sprintf("%-".$evtlen."s","NAME").sprintf("%-12s","Number").sprintf("%-8s","Rate").sprintf("%-12s","<a href=\"https://wiki.fhem.de/wiki/Event#Beschr.C3.A4nken_von_Events\">Restriction</a>")."</b>\n";
      $ret = "<b>".sprintf("%-".$typlen."s","TYPE").sprintf("%-".$evtlen."s","NAME").sprintf("%-12s","Anzahl").sprintf("%-8s","Rate").sprintf("%-12s","<a href=\"https://wiki.fhem.de/wiki/Event#Beschr.C3.A4nken_von_Events\">Begrenzung</a>")."</b>\n" if ($DE);
      $ret .= sprintf("%-".$typlen."s","").sprintf("%-".$evtlen."s","").sprintf("%-12s","Events").sprintf("%-8s","1/h").sprintf("%-12s","event-on...")."\n";
      $ret .= sprintf("-"x($typlen+$evtlen+33))."\n";
      my $i = 0;
      my $t = 0;
      foreach my $typ (sort keys %types) {
        $typsum = 0;
        $t=0;
        foreach my $key (sort keys %{$defs{$pn}->{READINGS}}) {
          $rate = ($te ? int($hash->{READINGS}{$key}{VAL}/$te + 0.5) : 0) if ($key =~ m/^$rx($regex)/ and defined($defs{$1}) and $defs{$1}->{TYPE} eq $typ);
          if ($key =~ m/^$rx($regex)/ and defined($defs{$1}) and $defs{$1}->{TYPE} eq $typ and $rate >= $compRate) {
              $evtsum += $hash->{READINGS}{$key}{VAL};
              $typsum += $hash->{READINGS}{$key}{VAL};
              $allattr = " ".join(" ",keys %{$attr{$1}});
              $ret .= sprintf("%-".$typlen."s",$typ).sprintf("%-".$evtlen."s",$1).sprintf("%-12s",$hash->{READINGS}{$key}{VAL}).sprintf("%-8s",$rate).sprintf("%-12s",($DE ? ($allattr =~ " event-on" ? "ja" : "nein") : ($allattr =~ " event-on" ? "yes" : "no")))."\n";
              $i++;
              $t++;
          }
        }
        if ($t) {
          $typerate = $te ? int($typsum/$te + 0.5) : 0;
          if($typerate >= $compRate) {
            $ret .= sprintf("%".($typlen+$evtlen+10)."s","="x10).sprintf("%2s","  ").sprintf("="x6)."\n";
            if ($DE) {
              $ret .= sprintf("%".($typlen+$evtlen)."s","Summe: ").sprintf("%-10s",$typsum).sprintf("%2s","&empty;:").sprintf("%-8s",$typerate)."\n";
              $ret .= sprintf("%".($typlen+$evtlen+1)."s","Geräte: ").sprintf("%-10s",$t)."\n";
              $ret .= sprintf("%".($typlen+$evtlen+1)."s","Events/Gerät: ").sprintf("%-10s",int($typsum/$t + 0.5))."\n";
            } else {
              $ret .= sprintf("%".($typlen+$evtlen)."s","Total: ").sprintf("%-10s",$typsum).sprintf("%2s","&empty;:").sprintf("%-8s",$typerate)."\n";
              $ret .= sprintf("%".($typlen+$evtlen)."s","Devices: ").sprintf("%-10s",$t)."\n";
              $ret .= sprintf("%".($typlen+$evtlen)."s","Events/device: ").sprintf("%-10s",int($typsum/$t + 0.5))."\n";
            }
            $ret .= "<div style=\"color:#d9d9d9\" >".sprintf("-"x($typlen+$evtlen+33))."</div>";
          }
        }
      }
      if ($DE) {
          $ret .= sprintf("%".($typlen+$evtlen+10)."s","="x10).sprintf("%2s","  ").sprintf("="x6)."\n";
          $ret .= sprintf("%".($typlen+$evtlen)."s","Summe: ").sprintf("%-10s",$evtsum).sprintf("%2s","&empty;:").sprintf("%-8s",$te ? int($evtsum/$te + 0.5) : "")."\n";
          $ret .= sprintf("%".($typlen+$evtlen)."s","Dauer: ").sprintf("%d:%02d",int($te),int(($te-int($te))*60+.5))."\n";
          $ret .= sprintf("%".($typlen+$evtlen+1)."s","Geräte: ").sprintf("%-10s",$i)."\n";
          $ret .= sprintf("%".($typlen+$evtlen+1)."s","Events/Gerät: ").sprintf("%-10s",int($evtsum/$i + 0.5))."\n\n" if ($i);
          fhem("count",1) =~ m/(\d+)/;
          $ret .= sprintf("%".($typlen+$evtlen+1)."s","Geräte total: ").sprintf("%-10s","$1\n\n");
          $ret .= sprintf("%".($typlen+$evtlen+1)."s","<u>Filter</u>\n");
          $ret .= sprintf("%".($typlen+$evtlen)."s","TYPE: ").sprintf("%-10s",ReadingsVal($pn,"statisticsTYPEs","")."\n");
          $ret .= sprintf("%".($typlen+$evtlen-7)."s","NAME: ").sprintf("%-10s",ReadingsVal($pn,"statisticsDeviceFilterRegex",".*")."\n");
          $ret .= sprintf("%".($typlen+$evtlen-7)."s","Rate: ").sprintf("%-10s","&gt;= $compRate\n\n");
      } else {
          $ret .= sprintf("%".($typlen+$evtlen+10)."s","="x10).sprintf("%2s","  ").sprintf("="x6)."\n";
          $ret .= sprintf("%".($typlen+$evtlen)."s","Total: ").sprintf("%-10s",$evtsum).sprintf("%2s","&empty;:").sprintf("%-8s",$te ? int($evtsum/$te + 0.5) : "")."\n";
          $ret .= sprintf("%".($typlen+$evtlen)."s","Duration: ").sprintf("%d:%02d",int($te),int(($te-int($te))*60+.5))."\n";
          $ret .= sprintf("%".($typlen+$evtlen)."s","Devices: ").sprintf("%-10s",$i)."\n";
          $ret .= sprintf("%".($typlen+$evtlen)."s","Events/device: ").sprintf("%-10s",int($evtsum/$i + 0.5))."\n\n" if ($i);
          fhem("count",1) =~ m/(\d+)/;
          $ret .= sprintf("%".($typlen+$evtlen)."s","Devices total: ").sprintf("%-10s","$1\n\n");
          $ret .= sprintf("%".($typlen+$evtlen+1)."s","<u>Filter</u>\n");
          $ret .= sprintf("%".($typlen+$evtlen)."s","TYPE: ").sprintf("%-10s",ReadingsVal($pn,"statisticsTYPEs","")."\n");
          $ret .= sprintf("%".($typlen+$evtlen-7)."s","NAME: ").sprintf("%-10s",ReadingsVal($pn,"statisticsDeviceFilterRegex",".*")."\n");
          $ret .= sprintf("%".($typlen+$evtlen-7)."s","Rate: ").sprintf("%-10s","&gt;= $compRate\n\n");
      }
      $ret .= "<div style=\"color:#d9d9d9\" >".sprintf("-"x($typlen+$evtlen+33))."</div>";
      # attibute statistics
      if ($DE) {
        $ret .= "<b>".sprintf("%-30s","genutzte Attribute in DOIF").sprintf("%-12s","Anzahl")."</b>\n";
      } else {
        $ret .= "<b>".sprintf("%-30s","used attributes in DOIF").sprintf("%-12s","Number")."</b>\n";
      }
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
        $ret .= sprintf("%-30s","$i").sprintf("%-12s","$da{$i}")."\n"; 
      }
  } elsif ($arg eq "checkDOIF") {
      my @coll = ();
      my $coll = "";
      foreach my $di (@doifList) {
        $coll = DOIFtoolsCheckDOIFcoll($hash,$di);
        push @coll, $coll if($coll);
      }
      $ret .= join(" ",@coll);
      if ($DE) {
        $ret .= "\n<ul><li><b>DOELSEIF</b> ohne <b>DOELSE</b> ist o.k., wenn der Status wechselt, bevor die selbe Bedingung wiederholt wahr wird,<br> andernfalls sollte <b>do always</b> genutzt werden (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_do_always\">Steuerung durch Events</a>, <a target=\"_blank\" href=\"https://wiki.fhem.de/wiki/DOIF/Einsteigerleitfaden,_Grundfunktionen_und_Erl%C3%A4uterungen#Verhaltensweise_ohne_steuernde_Attribute\">Verhalten ohne Attribute</a>)</li></ul> \n" if (@coll);
      } else {
        $ret .= "\n<ul><li><b>DOELSEIF</b> without <b>DOELSE</b> is o.k., if state changes between, the same condition becomes true again,<br>otherwise use attribute <b>do always</b> (<a target=\"_blank\" href=\"https://fhem.de/commandref_DE.html#DOIF_do_always\">controlling by events</a>, <a target=\"_blank\" href=\"https://wiki.fhem.de/wiki/DOIF/Einsteigerleitfaden,_Grundfunktionen_und_Erl%C3%A4uterungen#Verhaltensweise_ohne_steuernde_Attribute\">behaviour without attributes</a>)</li></ul> \n" if (@coll);
      }
      foreach my $di (@doifList) {
        $ret .= DOIFtoolsCheckDOIF($hash,$di);
      }
      
      $ret = $DE ? ($ret ? "Empfehlung gefunden für:\n\n$ret" : "Keine Empfehlung gefunden.") : ($ret ? "Found recommendation for:\n\n$ret" : "No recommendation found.");
      return $ret;
      
  } elsif ($arg eq "runningTimerInDOIF") {
      my $erg ="";
      foreach my $di (@doifList) {
        push @ret, sprintf("%-28s","$di").sprintf("%-40s",ReadingsVal($di,"wait_timer",""))."\n" if (ReadingsVal($di,"wait_timer","no timer") ne "no timer");
      }
      $ret .= join("",@ret);
      $ret = $ret ? "Found running wait_timer for:\n\n$ret" : "No running wait_timer found.";
      return $ret;
      
  } elsif ($arg eq "SetAttrIconForDOIF") {
      $ret .= CommandAttr(undef,"$value icon helper_doif");
      $ret .= CommandSave(undef,undef) if (AttrVal($pn,"DOIFtoolsExecuteSave",""));
      return $ret;
  } elsif ($arg eq "linearColorGradient") {
      my ($sc,$ec,$min,$max,$step) = split(",",$value);
      if ($value && $sc =~ /[0-9A-F]{6}/ && $ec =~ /[0-9A-F]{6}/ && $min =~ /(-?\d+(\.\d+)?)/ &&  $max =~ /(-?\d+(\.\d+)?)/ && $step =~ /(-?\d+(\.\d+)?)/) {
        $ret .= "<br></pre><table>";
        $ret .= "<tr><td colspan=4 style='font-weight:bold;'>Color Table</td></tr>";
        $ret .= "<tr><td colspan=4><div>";
        for (my $i=0;$i<=127;$i++) {
          my $col = DOIFtoolsLinColorGrad($sc,$ec,0,127,$i);
          $ret .= "<span style='background-color:$col;'>&nbsp;</span>";
        }
        $ret .= "</div></td></tr>";
        $ret .= "<tr style='text-align:center;'><td> Value </td><td> Color Number </td><td> RGB values </td><td> Color</td> </tr>";
        for (my $i=$min;$i<=$max;$i+=$step) {
          my $col = DOIFtoolsLinColorGrad($sc,$ec,$min,$max,$i);
          $col =~ /^#?([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})$/;
          $ret .= "<tr style='text-align:center;'><td>".sprintf("%.1f",$i)."</td><td>$col</td><td> ".hex($1).",".hex($2).",".hex($3)." </td><td style='background-color:$col;'>&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;</td></tr>";
        }
        $ret .= "</table><pre>";
        
       return $ret;
      } else {
        $ret = $DE ? "<br></pre>
Falsche Eingabe: <code>$value</code><br>
Syntax: <code>&lt;Startfarbnummer&gt;,&lt;Endfarbnummer&gt;,&lt;Minimalwert&gt;,&lt;Maximalwert&gt;,&lt;Schrittweite&gt;</code><br>
<ul>
<li><code>&lt;Startfarbnummer&gt;</code>, ist eine HTML-Farbnummer, Beispiel: #0000FF für Blau.</li>
<li><code>&lt;Endfarbnummer&gt;</code>, ist eine HTML-Farbnummer, Beispiel: #FF0000 für Rot.</li>
<li><code>&lt;Minimalwert&gt;</code>, der Minimalwert auf den die Startfarbnummer skaliert wird, Beispiel: 7.</li>
<li><code>&lt;Maximalwert&gt;</code>, der Maximalwert auf den die Endfarbnummer skaliert wird, Beispiel: 30.</li>
<li><code>&lt;Schrittweite&gt;</code>, für jeden Schritt wird ein Farbwert erzeugt, Beispiel: 1.</li>
</ul>
Beispielangabe: <code>#0000FF,#FF0000,7,30,1</code>
<pre>":"<br></pre>
Wrong input: <code>$value</code><br>
Syntax: <code>&lt;start color number&gt;,&lt;end color number&gt;,&lt;minimal value&gt;,&lt;maximal value&gt;,&lt;step width&gt;</code><br>
<ul>
<li><code>&lt;start color number&gt;</code>, a HTML color number, example: #0000FF for blue.</li>
<li><code>&lt;end color number&gt;</code>, a HTML color number, example: #FF0000 for red.</li>
<li><code>&lt;minimal value&gt;</code>, the start color number will be scaled to it, example: 7.</li>
<li><code>&lt;maximal value&gt;</code>, the end color number will be scaled to it, example: 30.</li>
<li><code>&lt;step width&gt;</code>, for each step a color number will be generated, example: 1.</li>
</ul>
Example specification: <code>#0000FF,#FF0000,7,30,1</code>
<pre>";
        return $ret
      }
  } elsif ($arg eq "hsvColorGradient") {
      my ($min_s,$max_s,$min,$max,$step,$s,$v)=split(",",$value);
      if ($value && $s >= 0 && $s <= 100 && $v >= 0 && $v <= 100  && $min_s >= 0 && $min_s <= 360 && $max_s >= 0 && $max_s <= 360) {
        $ret .= "<br></pre><table>";
        $ret .= "<tr><td colspan=4 style='font-weight:bold;'>Color Table</td></tr>";
        $ret .= "<tr><td colspan=4><div>";
        for (my $i=0;$i<=127;$i++) {
          my $col = DOIFtoolsHsvColorGrad($i,0,127,$min_s,$max_s,$s,$v);
          $ret .= "<span style='background-color:$col;'>&nbsp;</span>";
        }
        $ret .= "</div></td></tr>";
        $ret .= "<tr style='text-align:center;'><td> Value </td><td> Color Number </td><td> RGB values </td><td> Color</td> </tr>";
        for (my $i=$min;$i<=$max;$i+=$step) {
          my $col = DOIFtoolsHsvColorGrad($i,$min,$max,$min_s,$max_s,$s,$v);
          $col =~ /^#?([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})$/;
          $ret .= "<tr style='text-align:center;'><td>".sprintf("%.1f",$i)."</td><td>$col</td><td> ".hex($1).",".hex($2).",".hex($3)." </td><td style='background-color:$col;'>&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;</td></tr>";
        }
        $ret .= "</table><pre>";
        
       return $ret;
      } else {
        $ret = $DE ? "<br></pre>
Falsche Eingabe: <code>$value</code><br>
Syntax: <code>&lt;HUE-Startwert&gt;,&lt;HUE-Endwert&gt;,&lt;Minimalwert&gt;,&lt;Maximalwert&gt;,&lt;Schrittweite&gt;,&lt;Sättigung&gt;,&lt;Hellwert&gt;</code><br>
<ul>
<li><code>&lt;HUE-Startwert&gt;</code>, ist ein HUE-Wert <code>0-360</code>, Beispiel: 240 für Blau.</li>
<li><code>&lt;HUE-Endwert&gt;</code>, ist ein HUE-Wert <code>0-360</code>, Beispiel: 360 für Rot.</li>
<li><code>&lt;Minimalwert&gt;</code>, der Minimalwert auf den der HUE-Startwert skaliert wird, Beispiel: 7.</li>
<li><code>&lt;Maximalwert&gt;</code>, der Maximalwert auf den der HUE-Endwert skaliert wird, Beispiel: 30.</li>
<li><code>&lt;Schrittweite&gt;</code>, für jeden Schritt wird ein Farbwert erzeugt, Beispiel: 1.</li>
<li><code>&lt;Sättigung&gt;</code>, die verwendete Farbsätigung <code>0-100</code>, Beispiel: 80.</li>
<li><code>&lt;Hellwert&gt;</code>, Angabe der Helligkeit <code>0-100</code>, Beispiel: 80.</li>
</ul>
Beispielangabe: <code>240,360,7,30,1,80,80</code>
<pre>":"<br></pre>
Wrong input: <code>$value</code><br>
Syntax: <code>&lt;HUE start value&gt;,&lt;HUE end value&gt;,&lt;minimal value&gt;,&lt;maximal value&gt;,&lt;step width&gt;,&lt;saturation&gt;,&lt;lightness&gt;</code><br>
<ul>
<li><code>&lt;HUE start value&gt;</code>, a HUE value <code>0-360</code>, example: 240 for blue.</li>
<li><code>&lt;HUE end value&gt;</code>, a HUE value <code>0-360</code>, example: 360 for red.</li>
<li><code>&lt;minimal value&gt;</code>, the HUE start value will be scaled to it, example: 7.</li>
<li><code>&lt;maximal value&gt;</code>, the HUE end value will be scaled to it, example: 30.</li>
<li><code>&lt;step width&gt;</code>, for each step a color number will be generated, example: 1.</li>
<li><code>&lt;saturation&gt;</code>, a value of saturation <code>0-100</code>, example: 80.</li>
<li><code>&lt;lightness&gt;</code>, a value of lightness <code>0-100</code>, example: 80.</li>
</ul>
Example specification: <code>240,360,7,30,1,80,80</code>
<pre>";
        return $ret
      }
  } elsif ($arg eq "modelColorGradient") {
    my $err_ret = $DE ? "<br></pre>
Falsche Eingabe: <code>$value</code><br>
Syntax: <code>&lt;Minimalwert&gt;,&lt;Zwischenwert&gt;,&lt;Maximalwert&gt;,&lt;Schrittweite&gt;&lt;Farbmodel&gt;</code><br>
<ul>
<li><code>&lt;Minimalwert&gt;</code>, der Minimalwert auf den die Startfarbnummer skaliert wird, Beispiel: 7.</li>
<li><code>&lt;Zwischenwert&gt;</code>, der Fixpunkt zwischen Start- u. Endwert, Beispiel: 20.</li>
<li><code>&lt;Maximalwert&gt;</code>, der Maximalwert auf den die Endfarbnummer skaliert wird, Beispiel: 30.</li>
<li><code>&lt;Schrittweite&gt;</code>, für jeden Schritt wird ein Farbwert erzeugt, Beispiel: 1.</li>
<li><code>&lt;Farbmodel&gt;</code>, die Angabe eines vordefinierten Modells <code>&lt;0|1|2&gt;</code> oder fünf RGB-Werte <br>als Array <code>[r1,g1,b1,r2,g2,b2,r3,g3,b3,r4,g4,b4,r5,g5,b5]</code> für ein eigenes Model.</li>
</ul>
Beispiele:<br>
<code>30,60,100,5,[255,255,0,127,255,0,0,255,0,0,255,255,0,127,255]</code>, z.B. Luftfeuchte<br>
<code>7,20,30,1,[0,0,255,63,0,192,127,0,127,192,0,63,255,0,0]</code>, z.B. Temperatur<br>
<code>0,2.6,5.2,0.0625,[192,0,0,208,63,0,224,127,0,240,192,0,255,255,0]</code>, z.B. Exponent der Helligkeit<br>
<code>7,20,30,1,0</code>
<pre>":"<br></pre>
Wrong input: <code>$value</code><br>
Syntax: <code>&lt;minimal value&gt;,&lt;middle value&gt;,&lt;maximal value&gt;,&lt;step width&gt;,&lt;color model&gt;</code><br>
<ul>
<li><code>&lt;minimal value&gt;</code>, the start color number will be scaled to it, example: 7.</li>
<li><code>&lt;middle value&gt;</code>, a fix point between min and max, example: 20.</li>
<li><code>&lt;maximal value&gt;</code>, the end color number will be scaled to it, example: 30.</li>
<li><code>&lt;step width&gt;</code>, for each step a color number will be generated, example: 1.</li>
<li><code>&lt;color model&gt;</code>, a predefined number &lt;0|1|2&gt; or an array of five RGB values, <br><code>[r1,g1,b1,r2,g2,b2,r3,g3,b3,r4,g4,b4,r5,g5,b5]</code></li>
</ul>
Example specifications:<br>
<code>0,50,100,5,[255,255,0,127,255,0,0,255,0,0,255,255,0,127,255]</code> e.g. humidity<br>
<code>7,20,30,1,[0,0,255,63,0,192,127,0,127,192,0,63,255,0,0]</code>, e.g. temperature<br>
<code>0,2.6,5.2,0.0625,[192,0,0,208,63,0,224,127,0,240,192,0,255,255,0]</code>, e.g. brightness exponent<br>
<code>7,20,30,1,0</code>
<pre>";
    return $err_ret if (!$value);
    my ($min,$mid,$max,$step,$colors);
    my $err = "";
    $value =~ s/,(\[.*\])//;
    if ($1) {
      $colors = eval($1);
      if ($@) {
        $err="Error eval 1567: $@\n".$err_ret;
        Log3 $hash->{NAME},3,"modelColorGradient \n".$err; 
        return $err;
      }
      ($min,$mid,$max,$step) = split(",",$value);
    } else {
      ($min,$mid,$max,$step,$colors) = split(",",$value);
    }
    return $err_ret if ($min>=$mid or $mid >= $max or $step <= 0 or (ref($colors) ne "ARRAY" && $colors !~ "0|1|2"));
    my $erg=eval("\"".Color::pahColor($min,$mid,$max,$min+$step,$colors)."\"");
    if ($@) {
      $err="Error eval 1577: $@\n".$err_ret;
      Log3 $hash->{NAME},3,"modelColorGradient \n".$err; 
    return $err;
    }
    $ret .= "<br></pre><table>";
    $ret .= "<tr><td colspan=4 style='font-weight:bold;'>Color Table</td></tr>";
    $ret .= "<tr><td colspan=4><div>";
    for (my $i=0;$i<=127;$i++) {
      my $col = eval("\"".Color::pahColor($min,$mid,$max,$min+$i*($max-$min)/127,$colors)."\"");
      if ($@) {
        $err="Error eval 1567: $@\n".$err_ret;
        Log3 $hash->{NAME},3,"modelColorGradient \n".$err; 
        return $err;
      }
      $col = "#".substr($col,0,6);
      $ret .= "<span style='background-color:$col;'>&nbsp;</span>";
    }
    $ret .= "</div></td></tr>";
    $ret .= "<tr style='text-align:center;'><td> Value </td><td> Color Number </td><td> RGB values </td><td> Color</td> </tr>";
    for (my $i=$min;$i<=$max;$i+=$step) {
      my $col = eval("\"".Color::pahColor($min,$mid,$max,$i,$colors)."\"");
      if ($@) {
        $err="Error eval 1567: $@\n".$err_ret;
        Log3 $hash->{NAME},3,"modelColorGradient \n".$err; 
        return $err;
      }
      $col = "#".substr($col,0,6);
      $col =~ /^#?([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})$/;
      $ret .= "<tr style='text-align:center;'><td>".sprintf("%.1f",$i)."</td><td>$col</td><td> ".hex($1).",".hex($2).",".hex($3)." </td><td style='background-color:$col;'>&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;</td></tr>";
    }
    $ret .= "</table><pre>";
    
    return $ret;
  } else {
      my $hardcoded = "checkDOIF:noArg statisticsReport:noArg runningTimerInDOIF:noArg";
      return "unknown argument $arg for $pn, choose one of readingsGroup_for:multiple-strict,$dL DOIF_to_Log:multiple-strict,$dL SetAttrIconForDOIF:multiple-strict,$dL userReading_nextTimer_for:multiple-strict,$ntL ".(AttrVal($pn,"DOIFtoolsHideGetSet",0) ? $hardcoded :"")." linearColorGradient:textField modelColorGradient:textField hsvColorGradient:textField";
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
    <li>delete visible readings in other devices with multiple choice, but not <i>state</i>.</li>
    <li>record statistics data about events.</li>
    <li>limitting recordig duration.</li>
    <li>generate a statistics report.</li>
    <li>lists every DOIF definition in <i>probably associated with</i>.</li>
    <li>access to DOIFtools from any DOIF device via <i>probably associated with</i></li>
    <li>access from DOIFtools to existing DOIFtoolsLog logfiles</li>
    <li>show event monitor in device detail view and optionally in DOIFs detail view</li>
    <li>convert events to DOIF operands, a selected operand is copied to clipboard and the DEF editor will open</li>
    <li>check definitions and offer recommendations</li>
    <li>create shortcuts</li>
    <li>optionally create a menu entry</li>
    <li>show a list of running wait timer</li>
    <li>scale values to color numbers and RGB values for coloration</li>
  </ul>
<br>
Just one definition per FHEM-installation is allowed. <a href="https://fhem.de/commandref_DE.html#DOIFtools">More in the german section.</a>
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
    <li>löschen von  Readings in anderen Geräten über eine Mehrfachauswahl, nicht <i>state</i>.</li>
    <li>erfassen statistischer Daten über Events.</li>
    <li>Begrenzung der Datenaufzeichnungsdauer.</li>
    <li>erstellen eines Statistikreports.</li>
    <li>Liste aller DOIF-Definitionen in <i>probably associated with</i>.</li>
    <li>Zugriff auf DOIFtools aus jeder DOIF-Definition über die Liste in <i>probably associated with</i>.</li>
    <li>Zugriff aus DOIFtools auf vorhandene DOIFtoolsLog-Logdateien.</li>
    <li>zeigt den Event Monitor in der Detailansicht von DOIFtools.</li>
    <li>ermöglicht den Zugriff auf den Event Monitor in der Detailansicht von DOIF.</li>
    <li>erzeugt DOIF-Operanden aus einer Event-Zeile des Event-Monitors.</li>
    <ul>
      <li>Ist der <b>Event-Monitor in DOIF</b> geöffnet, dann kann die Definition des <b>DOIF geändert</b> werden.</li>
      <li>Ist der <b>Event-Monitor in DOIFtools</b> geöffnet, dann kann die Definition eines <b>DOIF erzeugt</b> werden.</li>
    </ul>
    <li>prüfen der DOIF Definitionen mit Empfehlungen.</li>
    <li>erstellen von Shortcuts</li>
    <li>optionalen Menüeintrag erstellen</li>
    <li>Liste der laufenden Wait-Timer anzeigen</li>
    <li>skaliert Werte zu Farbnummern und RGB Werten zum Einfärben, z.B. von Icons.</li>
  </ul>
<br>
<b>Inhalt</b><br>
<ul>
  <a href="#DOIFtoolsBedienungsanleitung">Bedienungsanleitung</a><br>
  <a href="#DOIFtoolsDefinition">Definition</a><br>
  <a href="#DOIFtoolsSet">Set-Befehl</a><br>
  <a href="#DOIFtoolsGet">Get-Befehl</a><br>
  <a href="#DOIFtoolsAttribute">Attribute</a><br>
  <a href="#DOIFtoolsReadings">Readings</a><br>
  <a href="#DOIFtoolsLinks">Links</a><br>
</ul><br>

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
        Es ist nur eine Definition pro FHEM Installation möglich. Die Definition wird mit den vorhanden DOIF-Namen ergänzt, daher erscheinen alle DOIF-Geräte in der Liste <i>probably associated with</i>. Zusätzlich wird in jedem DOIF-Gerät in dieser Liste auf das DOIFtool verwiesen.<br>
        <br>
        <u>Definitionsvorschlag</u> zum Import mit <a href="https://wiki.fhem.de/wiki/DOIF/Import_von_Code_Snippets">Raw definition</a>:<br>
        <code>
        defmod DOIFtools DOIFtools<br>
        attr DOIFtools DOIFtoolsEventMonitorInDOIF 1<br>
        attr DOIFtools DOIFtoolsExecuteDefinition 1<br>
        attr DOIFtools DOIFtoolsExecuteSave 1<br>
        attr DOIFtools DOIFtoolsMenuEntry 1<br>
        attr DOIFtools DOIFtoolsMyShortcuts ##My Shortcuts:,,list DOIFtools,fhem?cmd=list DOIFtools<br>
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
        <code>set &lt;name&gt; deleteReadingInTargetDevice &lt;readings to delete name&gt;</code><br>
        <b>deleteReadingInTargetDevice</b> löscht sichtbare Readings, ausser <i>state</i> im Ziel-Gerät. Bitte den Gefahrenhinweis zum Befehl <a href="https://fhem.de/commandref_DE.html#deletereading">deletereading</a> beachten!<br>
        <br>
        <code>set &lt;name&gt; targetDevice &lt;target name&gt;</code><br>
        <b>targetDevice</b> vor dem Löschen der Readings muss das Ziel-Gerät gesetzt werden.<br>
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
        <code>get &lt;name&gt; SetAttrIconForDOIF &lt;DOIF names for setting the attribute icon to helper_doif&gt;</code><br>
        <b>SetAttrIconForDOIF</b> setzt für die ausgewählten DOIF das Attribut <i>icon</i> auf <i>helper_doif</i>.<br>
        <br>
        <code>get &lt;name&gt; linearColorGradient &lt;start color number&gt;,&lt;end color number&gt;,&lt;minimal value&gt;,&lt;maximal value&gt;,&lt;step width&gt;</code><br>
        <b>linearColorGradient</b> erzeugt eine Tabelle mit linear abgestuften Farbnummern und RGB-Werten.<br>
        &lt;start color number&gt;, ist eine HTML-Farbnummer, Beispiel: #0000FF für Blau.<br>
        &lt;end color number&gt;, , ist eine HTML-Farbnummer, Beispiel: #FF0000 für Rot.<br>
        &lt;minimal value&gt;, der Minimalwert auf den die Startfarbnummer skaliert wird, Beispiel: 7.<br>
        &lt;maximal value&gt;, der Maximalwert auf den die Endfarbnummer skaliert wird, Beispiel: 30.<br>
        &lt;step width&gt;, für jeden Schritt wird ein Farbwert erzeugt, Beispiel: 0.5.
        <br>
        Beispiel: <code>get DOIFtools linearColorGradient #0000FF,#FF0000,7,30,0.5</code><br>
        <br>
        <code>get &lt;name&gt; modelColorGradient &lt;minimal value&gt;,&lt;middle value&gt;,&lt;maximal value&gt;,&lt;step width&gt;,&lt;color model&gt;</code><br>
        <b>modelColorGradient</b> erzeugt eine Tabelle mit modellbedingt abgestuften Farbnummern und RGB-Werten, siehe FHEM-Wiki<a href="https://wiki.fhem.de/wiki/Color#Farbskala_mit_Color::pahColor"> Farbskala mit Color::pahColor </a><br>
        &lt;minimal value&gt;, der Minimalwert auf den die Startfarbnummer skaliert wird, Beispiel: 7.<br>
        &lt;middle value&gt;, der Mittenwert ist ein Fixpunkt zwischen Minimal- u. Maximalwert, Beispiel: 20.<br>
        &lt;maximal value&gt;, der Maximalwert auf den die Endfarbnummer skaliert wird, Beispiel: 30.<br>
        &lt;step width&gt;, für jeden Schritt wird ein Farbwert erzeugt, Beispiel: 1.<br>
        &lt;color model&gt;, die Angabe eines vordefinierten Modells &lt;0|1|2&gt; oder fünf RGB-Werte als Array [r1,g1,b1,r2,g2,b2,r3,g3,b3,r4,g4,b4,r5,g5,b5] für ein eigenes Model.<br>
        <br>
        Beispiele:<br>
        <code>get DOIFtools modelColorGradient 7,20,30,1,0</code><br>
        <code>get DOIFtools modelColorGradient 0,50,100,5,[255,255,0,127,255,0,0,255,0,0,255,255,0,127,255]</code><br>
        <br>
        <code>get &lt;name&gt; hsvColorGradient &lt;HUE start value&gt;,&lt;HUE end value&gt;,&lt;minimal value&gt;,&lt;maximal value&gt;,&lt;step width&gt;,&lt;saturation&gt;,&lt;lightness&gt;</code><br>
        <b>hsvColorGradient</b> erzeugt eine Tabelle über HUE-Werte abgestufte Farbnummern und RGB-Werten.<br>
        &lt;Hue start value&gt;, der HUE-Startwert, Beispiel: 240 für Blau.<br>
        &lt;HUE end value&gt;, der HUE-Endwert, Beispiel: 360 für Rot.<br>
        &lt;minimal value&gt;, der Minimalwert auf den der HUE-Startwert skaliert wird, Beispiel: 7.<br 20.<br>
        &lt;maximal value&gt;, der Maximalwert auf den der HUE-Endwert skaliert wird, Beispiel: 30.<br>
        &lt;step width&gt;, für jeden Schritt wird ein Farbwert erzeugt, Beispiel: 1.<br>
        &lt;saturation&gt;, die Angabe eines Wertes für die Farbsättigung &lt;0-100&gt;, Beispiel 80.<br>
        &lt;lightness&gt;, die Angabe eines Wertes für die Helligkeit &lt;0-100&gt;, Beispiel 80.<br>
        <br>
        Beispiele:<br>
        <code>get DOIFtools hsvColorGradient 240,360,7,30,1,80,80</code><br>
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
        <code>attr &lt;name&gt; DOIFtoolsEMbeforeReadings &lt;1|0&gt;</code><br>
        <b>DOIFtoolsEMbeforeReading</b> <b>1</b>, die Anzeige des Event-Monitors wird in DOIF direkt über den Readings angezeigt. <b>Default 0</b>, anzeige des Event-Monitors über den Internals.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsHideGetSet &lt;0|1&gt;</code><br>
        <b>DOIFtoolsHideModulGetSet</b> <b>1</b>, verstecken der Set- und Get-Shortcuts. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsNoLookUp &lt;0|1&gt;</code><br>
        <b>DOIFtoolsNoLookUp</b> <b>1</b>, es werden keine Lookup-Fenster in DOIFtools geöffnet. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsNoLookUpInDOIF &lt;0|1&gt;</code><br>
        <b>DOIFtoolsNoLookUpInDOIF</b> <b>1</b>, es werden keine Lookup-Fenster in DOIF geöffnet. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsHideModulShortcuts &lt;0|1&gt;</code><br>
        <b>DOIFtoolsHideModulShortcuts</b> <b>1</b>, verstecken der DOIFtools Shortcuts. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsHideStatReadings &lt;0|1&gt;</code><br>
        <b>DOIFtoolsHideStatReadings</b> <b>1</b>, verstecken der <i>stat_</i> Readings. Das Ändern des Attributs löscht eine bestehende Event-Aufzeichnung. <b>Default 0</b>.<br>
        <br>
        <code>attr &lt;name&gt; DOIFtoolsEventOnDeleted &lt;0|1&gt;</code><br>
        <b>DOIFtoolsEventOnDeleted</b> <b>1</b>, es werden Events für alle <i>stat_</i> erzeugt, bevor sie gelöscht werden. Damit könnten die erfassten Daten geloggt werden. <b>Default 0</b>.<br>
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
        <code>attr &lt;name&gt; DOIFtoolsLogDir &lt;path to DOIFtools logfile&gt;</code><br>
        <b>DOIFtoolsLogDir</b> <b>&lt;path&gt;</b>, gibt den Pfad zum Logfile an <b>Default <i>./log</i> oder der Pfad aus dem Attribut <i>global logdir</i></b>.<br>
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
    <li><b>targetDOIF</b> zeigt das Ziel-DOIF, bei dem Readings gelöscht werden sollen.</li>
    <li><b>targetDevice</b> zeigt das Ziel-Gerät, bei dem Readings gelöscht werden sollen.</li>
    </ul>
</br>
<a name="DOIFtoolsLinks"></a>
<b>Links</b>
<br>
<ul>
<a href="https://forum.fhem.de/index.php/topic,63938.0.html">DOIFtools im FHEM-Forum</a><br>
<a href="https://wiki.fhem.de/wiki/DOIFtools">DOIFtools im FHEM-Wiki</a><br>
<br>
<a href="https://wiki.fhem.de/wiki/DOIF">DOIF im FHEM-Wiki</a><br>
<a href="https://wiki.fhem.de/wiki/DOIF/Einsteigerleitfaden,_Grundfunktionen_und_Erl%C3%A4uterungen#Erste_Schritte_mit_DOIF:_Zeit-_und_Ereignissteuerung">Erste Schritte mit DOIF</a><br>
<a href="https://wiki.fhem.de/wiki/DOIF/Einsteigerleitfaden,_Grundfunktionen_und_Erl%C3%A4uterungen">DOIF: Einsteigerleitfaden, Grundfunktionen und Erläuterungen</a><br>
<a href="https://wiki.fhem.de/wiki/DOIF/Labor_-_ausf%C3%BChrbare,_praxisnahe_Beispiele_als_Probleml%C3%B6sung_zum_Experimentieren">DOIF-Labor - ausführbare, praxisnahe Beispiele als Problemlösung zum Experimentieren</a><br>
<a href="https://wiki.fhem.de/wiki/DOIF/Tipps_zur_leichteren_Bedienung">DOIF: Tipps zur leichteren Bedienung</a><br>
<a href="https://wiki.fhem.de/wiki/DOIF/Tools_und_Fehlersuche">DOIF: Tools und Fehlersuche</a><br>
</ul>
</ul>
=end html_DE
=cut

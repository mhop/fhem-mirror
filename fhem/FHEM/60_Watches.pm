########################################################################################################################
# $Id$
#########################################################################################################################
#       60_Watches.pm
#
#       (c) 2018-2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#       The script is based on sources from following sites:
#       # modern clock: https://www.w3schools.com/graphics/canvas_clock_start.asp
#       # station clock: http://www.3quarks.com/de/Bahnhofsuhr/
#       # digital clock: http://www.3quarks.com/de/Segmentanzeige/index.html
#
#########################################################################################################################
package FHEM::Watches;                                 ## no critic 'package'

use strict;
use warnings;
use Time::HiRes qw(time gettimeofday tv_interval);
use GPUtils qw(GP_Import GP_Export);                   # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;      ## no critic 'eval'

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          AttrVal
          defs
          IsDisabled
          Log3 
          modules          
          ReadingsVal
          readingsDelete 
          readingsBeginUpdate
          readingsBulkUpdate
          readingsEndUpdate
          readingsSingleUpdate   
          sortTopicNum          
        )
  );
  
  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/gx;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
        )
  );  
}

# Versions History intern
my %vNotesIntern = (
  "0.25.0" => "03.06.2020  set reading 'stoptime' in type 'stopwatch' ",                               
  "0.24.0" => "26.05.2020  entry of countDownInit can be in format <seconds> ",
  "0.23.2" => "20.05.2020  english commandref ",
  "0.23.1" => "10.05.2020  some more changes for PBP severity 3 ",
  "0.23.0" => "10.05.2020  attr 'digitalBorderDistance' now also valid for digital watches, some changes for PBP ", 
  "0.22.0" => "09.05.2020  new attr 'digitalBorderDistance' for left and rigtht border distance of digital text ", 
  "0.21.1" => "09.05.2020  fix calculate forerun of 'text' dynamically if digitalTextDigitNumber=0 ",
  "0.21.0" => "08.05.2020  support of alarm time of model digital 'watch' ",
  "0.20.1" => "08.05.2020  asynchron read digital text and much more fixes, set client as default timeSource ",
  "0.20.0" => "07.05.2020  asynchron read alarmTime reading, some fixes ",
  "0.19.0" => "06.05.2020  alarm event creation for watch models 'Station' and 'Station' ",
  "0.18.0" => "06.05.2020  attr 'digitalTextTicker' deleted and switched to setter 'textTicker', default text switched to blank ",
  "0.17.0" => "05.05.2020  new attr 'digitalTextTicker', 'digitalTextDigitNumber' ",
  "0.16.0" => "04.05.2020  delete attr 'digitalDisplayText', new setter 'displayText', 'displayTextDel' ",
  "0.15.1" => "04.05.2020  fix permanently events when no alarmTime is set in countdownwatch and countdown is finished ",
  "0.15.0" => "04.05.2020  new attribute 'digitalSegmentType' for different segement count, also new attributes ".
                           "'digitalDigitAngle', 'digitalDigitDistance', 'digitalDigitHeight', 'digitalDigitWidth', 'digitalSegmentDistance' ".
                           "'digitalSegmentWidth', stopwatches don't stop when alarm is triggered (use notify to do it) ",
  "0.14.0" => "03.05.2020  switch to packages, use setVersionInfo, support of Meta.pm ",
  "0.13.0" => "03.05.2020  set resume for countdownwatch, set 'continue' removed ",
  "0.12.0" => "03.05.2020  set resume for stopwatch, new 'alarmDel' command for stop watches, alarmHMS renamed to 'alarmHMSdelset' ",
  "0.11.0" => "02.05.2020  alarm event stabilized, reset command for 'countdownwatch', event alarmed contains alarm time ",
  "0.10.0" => "02.05.2020  renamed 'countDownDone' to 'alarmed', bug fix ",
  "0.9.0"  => "02.05.2020  new attribute 'timeSource' for selection of client/server time ",
  "0.8.0"  => "01.05.2020  new values 'countdownwatch' for attribute digitalDisplayPattern, switch all watches to server time ",
  "0.7.0"  => "30.04.2020  new set 'continue' for stopwatch ",
  "0.6.0"  => "29.04.2020  new set 'reset' for stopwatch, read 'state' and 'starttime' from readings, add csrf token support ",
  "0.5.0"  => "28.04.2020  new values 'stopwatch', 'staticwatch' for attribute digitalDisplayPattern ",
  "0.4.0"  => "20.11.2018  text display ",
  "0.3.0"  => "19.11.2018  digital clock added ",
  "0.2.0"  => "14.11.2018  station clock added ",
  "0.1.0"  => "13.11.2018  initial Version with modern analog clock"
);

##############################################################################
#         Initialize Funktion
##############################################################################
sub Initialize {
  my ($hash) = @_;
  
  $hash->{DefFn}              = \&Define;
  $hash->{SetFn}              = \&Set;
  $hash->{FW_summaryFn}       = \&FWebFn;
  $hash->{FW_detailFn}        = \&FWebFn;
  $hash->{AttrFn}             = \&Attr;
  $hash->{AttrList}           = "digitalBorderDistance:slider,0,1,40 ".
                                "digitalColorBackground:colorpicker ".
                                "digitalColorDigits:colorpicker ".
                                "digitalDisplayPattern:countdownwatch,staticwatch,stopwatch,text,watch ".
                                "digitalDigitAngle:slider,-30,0.5,30,1 ".
                                "digitalDigitDistance:slider,0.5,0.1,10,1 ".
                                "digitalDigitHeight:slider,5,0.1,50,1 ".
                                "digitalDigitWidth:slider,5,0.1,50,1 ".
                                "digitalSegmentDistance:slider,0,0.1,5,1 ".
                                "digitalSegmentType:7,14,16 ".
                                "digitalSegmentWidth:slider,0.3,0.1,3.5,1 ".
                                "digitalTextDigitNumber ".
                                "disable:1,0 ".
                                "hideDisplayName:1,0 ".
                                "htmlattr ".
                                "modernColorBackground:colorpicker ".
                                "modernColorHand:colorpicker ".
                                "modernColorFigure:colorpicker ".
                                "modernColorFace:colorpicker ".
                                "modernColorRing:colorpicker ".
                                "modernColorRingEdge:colorpicker ".
                                "stationSecondHand:Bar,HoleShaped,NewHoleShaped,No ".
                                "stationSecondHandBehavoir:Bouncing,Overhasty,Creeping,ElasticBouncing ".
                                "stationMinuteHandBehavoir:Bouncing,Creeping,ElasticBouncing ".
                                "stationBoss:Red,Black,Vienna,No ".
                                "stationMinuteHand:Bar,Pointed,Swiss,Vienna ".
                                "stationHourHand:Bar,Pointed,Swiss,Vienna ".
                                "stationStrokeDial:GermanHour,German,Austria,Swiss,Vienna,No ".
                                "stationBody:Round,SmallWhite,RoundGreen,Square,Vienna,No ".
                                "timeSource:server,client ".
                                "";

  $hash->{FW_hideDisplayName} = 1;                        # Forum 88667
  # $hash->{FW_addDetailToSummary} = 1;
  $hash->{FW_atPageEnd}       = 1;                        # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };        ## no critic 'eval' # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)
  
return;
}

##############################################################################
#         Define Funktion
##############################################################################
sub Define {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a    = split m{\s+}x, $def;
  
  if(!$a[2]) {
      return "You need to specify more parameters.\n". "Format: define <name> Watches [Modern | Station | Digital]";
  }
  
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);      # Modul Meta.pm nicht vorhanden
  $hash->{MODEL}                 = uc($a[2]);
  
  setVersionInfo($hash);                                      # Versionsinformationen setzen
  
  readingsSingleUpdate($hash,"state", "initialized", 1);      # Init für "state" 
  
return;
}

##############################################################################
#         Set Funktion
##############################################################################
sub Set {                                                    ## no critic 'complexity'   
  my ($hash, @a) = @_;
  return qq{"set X" needs at least an argument} if ( @a < 2 );
  my $name  = $a[0];
  my $opt   = $a[1];
  my $prop  = $a[2];
  my $prop1 = $a[3];
  my $prop2 = $a[4];
  my $prop3 = $a[5];
  my $addp  = AttrVal($name, "digitalDisplayPattern", "watch");
    
  return if(IsDisabled($name));
                                                           
  my $setlist = "Unknown argument $opt, choose one of ";
  $setlist .= "time "                                                                     if($addp =~ /staticwatch/x);               
  $setlist .= "alarmSet alarmDel:noArg reset:noArg resume:noArg start:noArg stop:noArg "  if($addp =~ /stopwatch|countdownwatch/x); 
  $setlist .= "countDownInit "                                                            if($addp =~ /countdownwatch/x);
  $setlist .= "alarmSet alarmDel:noArg "                                                  if($addp =~ /\bwatch\b/x);
  $setlist .= "displayTextSet displayTextDel:noArg textTicker:on,off "                    if($addp eq "text");    

  if ($opt eq "start") {                                    ## no critic 'Cascading'
      return qq{Please set "countDownInit" before !} if($addp =~ /countdownwatch/x && !ReadingsVal($name, "countInitVal", ""));
      
      my $ms = int(time*1000);
      
      readingsBeginUpdate ($hash);
      readingsBulkUpdate  ($hash, "alarmed", 0)      if($addp =~ /stopwatch|countdownwatch/x); 
      readingsBulkUpdate  ($hash, "starttime", $ms);
      readingsBulkUpdate  ($hash, "state", "started");
      readingsEndUpdate   ($hash, 1);
      
  } elsif ($opt eq "alarmSet") {
      $prop  = ($prop  ne "") ? $prop  : 70;                               # Stunden
      $prop1 = ($prop1 ne "") ? $prop1 : 70;                               # Minuten
      $prop2 = ($prop2 ne "") ? $prop2 : 70;                               # Sekunden
      return qq{The value for "$opt" is invalid. Use parameter "hh mm ss" like "19 45 13".} if($prop>23 || $prop1>59 || $prop2>59);
      
      my $at = sprintf("%02d",$prop).":".sprintf("%02d",$prop1).":".sprintf("%02d",$prop2);
            
      readingsSingleUpdate($hash, "alarmed",     0, 0);
      readingsSingleUpdate($hash, "alarmTime", $at, 1);
      
  } elsif ($opt eq "alarmDel") {      
      delReadings ($name, "alarmTime");
      delReadings ($name, "alarmed");
      
  } elsif ($opt eq "countDownInit") {
      my $ct;
      if($prop && $prop1) {                                                # Format: hh mm ss
          $prop2 = ($prop2 ne "") ? $prop2 : 70;                           # Sekunden
          return qq{The value for "$opt" is invalid. Use parameter "hh mm ss" like "19 45 13" \nor alternatively only one entry in seconds.} if($prop>23 || $prop1>59 || $prop2>59);
          $ct = $prop*3600 + $prop1*60 + $prop2;                           # in Sekunden umgewandelt !
          
      } elsif ($prop && !$prop1) {                                         # Format: Sekundenangabe
          $ct = $prop;
          
      } else {
         return qq{The value for "$opt" is invalid. Use parameter "hh mm ss" like "19 45 13" \nor alternatively only one entry in seconds.};   
      
      }
      
      delReadings         ($name, "countInitVal");
      
      readingsBeginUpdate ($hash);
      readingsBulkUpdate  ($hash, "countInitVal", $ct); 
      readingsBulkUpdate  ($hash, "state", "initialized");
      readingsEndUpdate   ($hash, 1);
      
  } elsif ($opt eq "resume") {
      return qq{Please set "countDownInit" before !} if($addp =~ /countdownwatch/x && !ReadingsVal($name, "countInitVal", ""));
      
      my $ms = int(time*1000);
      readingsSingleUpdate($hash, "starttime", $ms, 0);
      
      return if(ReadingsVal($name, "state", "") eq "started");
      readingsSingleUpdate($hash, "state", "resumed",  1);
      
  } elsif ($opt eq "stop") {
      readingsSingleUpdate($hash, "state", "stopped",  1);
      
  } elsif ($opt eq "displayTextSet") {
      shift @a; shift @a;
      
      my $txt = join (" ", @a);
      $txt    =~ s/[\r\n]//gx;
      readingsSingleUpdate($hash, "displayText", $txt, 1);
      
  } elsif ($opt eq "displayTextDel") {      
      delReadings ($name, "displayText");
      
  } elsif ($opt eq "textTicker") {
      if($prop eq "on") {
          readingsSingleUpdate($hash, "displayTextTicker", "on", 1); 
      } else {
          readingsSingleUpdate($hash, "displayTextTicker", "off", 1); 
      }
      
  } elsif ($opt eq "reset") {
      delReadings         ($name);
      readingsSingleUpdate($hash, "state", "initialized", 1);
      
  } elsif ($opt eq "time") {
      return qq{The value for "$opt" is invalid. Use parameter "hh mm ss" like "19 45 13".} if($prop>23 || $prop1>59 || $prop2>59);
  
      readingsBeginUpdate ($hash); 
      readingsBulkUpdate  ($hash, "hour",   $prop);
      readingsBulkUpdate  ($hash, "minute", $prop1);
      readingsBulkUpdate  ($hash, "second", $prop2);                    
      readingsEndUpdate   ($hash, 1);
      
  } else {
      return "$setlist"; 
  }
  
return;
}

##############################################################################
#         Attributfunktion
##############################################################################
sub Attr {                                                         ## no critic 'complexity'
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash                     = $defs{$name};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($cmd eq "set" && $hash->{MODEL} !~ /modern/ix && $aName =~ /^modern/x) {
         return qq{"$aName" is only valid for Watches model "Modern"};
    }
    
    if ($cmd eq "set" && $hash->{MODEL} !~ /station/ix && $aName =~ /^station/x) {
         return qq{"$aName" is only valid for Watches model "Station"};
    }
    
    if ($cmd eq "set" && $hash->{MODEL} !~ /digital/ix && $aName =~ /^digital/x) {
         return qq{"$aName" is only valid for Watches model "Digital"};
    }
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do  = 0 if($cmd eq "del");
        $val = ($do == 1 ? "disabled" : "initialized");
    
        readingsSingleUpdate($hash, "state", $val, 1);
    }
    
    if ($aName eq "digitalDisplayPattern") {
        if($cmd eq "set") {
            $do = $aVal;
        }
        $do = 0 if($cmd eq "del");
        
        if($do ne "text") {
            delReadings ($name); 
        } else {
            delReadings ($name,undef,"^display.*"); 
        }        
 
        readingsSingleUpdate($hash, "state", "initialized", 1); 
        
        if($do =~ /\bstopwatch\b/x) {
            my $ms = int(time*1000);
            readingsSingleUpdate($hash, "starttime", $ms, 0);
        }
    } 

    if ($cmd eq "set") {
        if ($aName =~ /digitalTextDigitNumber|digitalBorderDistance/x && $aVal !~ /^[0-9]+$/x) {
            return qq{The value of "$aName" is not valid. Only integers are allowed !};
        }
    }    

return;
}

##############################################################################
#                      Webanzeige des Devices
##############################################################################
sub FWebFn {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash  = $defs{$d};
  
  my $alias = AttrVal($d, "alias", $d);                            # Linktext als Aliasname oder Devicename setzen
  my $dlink = qq{<a href="/fhem?detail=$d">$alias</a>}; 
  
  my $ret = "";
  $ret   .= "<span>$dlink </span><br>"  if(!AttrVal($d,"hideDisplayName",0));
  if(IsDisabled($d)) {
      if(AttrVal($d,"hideDisplayName",0)) {
          $ret .= qq{Watch <a href="/fhem?detail=$d">$d</a> is disabled};
      } else {
          $ret .= "<html>Watch is disabled</html>";
      }  
  } else {
      $ret .= modernWatch ($d) if($hash->{MODEL} =~ /modern/ix);
      $ret .= stationWatch($d) if($hash->{MODEL} =~ /station/ix);
      $ret .= digitalWatch($d) if($hash->{MODEL} =~ /digital/ix);
  }
    
return $ret;
}

##############################################################################
#         löscht alle oder das spezifizierte Reading (außer state)
#         $todel   = nur dieses Reading löschen
#         $supress = Reading (Regex) nicht löschen
##############################################################################
sub delReadings {
  my ($name,$todel,$supress) = @_;
  my $hash = $defs{$name};
  
  my $addp = AttrVal($name, "digitalDisplayPattern", "watch");
  
  if($todel) {
      readingsDelete($hash,$todel);
      return;
  }
  
  my @allrds = keys%{$hash->{READINGS}};
  for my $key(@allrds) {
      next if($key =~ /\bstate\b/x);     
      next if(defined $supress && $key =~ /$supress/x);        
      readingsDelete($hash,$key);
  }    
    
return;
} 

##############################################################################
#                      Digitale Uhr / Anzeige aus:
#            http://www.3quarks.com/de/Segmentanzeige/index.html
#
##############################################################################
sub digitalWatch {
  my ($d)      = @_;
  my $hash     = $defs{$d};
  my $alarmdef = "00:00:00";
  my $bgc      = AttrVal($d, "digitalColorBackground", "C4C4C4");
  my $dcd      = AttrVal($d, "digitalColorDigits",     "000000"); 
  my $addp     = AttrVal($d, "digitalDisplayPattern",  "watch");  
  my $adst     = AttrVal($d, "digitalSegmentType",     7);
  my $adsw     = AttrVal($d, "digitalSegmentWidth",    1.5);
  my $addh     = AttrVal($d, "digitalDigitHeight",     20);
  my $addw     = AttrVal($d, "digitalDigitWidth",      12);
  my $addd     = AttrVal($d, "digitalDigitDistance",   2);
  my $adsd     = AttrVal($d, "digitalSegmentDistance", 0.5);
  my $adda     = AttrVal($d, "digitalDigitAngle",      9);
  my $adtdn    = AttrVal($d, "digitalTextDigitNumber", 0);
  my $abdist   = AttrVal($d, "digitalBorderDistance",  8);
  my $hattr    = AttrVal($d, "htmlattr",               "width='150' height='50'");
  my $tsou     = AttrVal($d, "timeSource",             "client");
  
  my $deftxt   =  "    ";
  my $rdtt     =  ReadingsVal ($d, "displayTextTicker", "off");
  my $ddt      =  ReadingsVal ($d, "displayText",       $deftxt);
  my $alarm    =  ReadingsVal ($d, "alarmTime",         "aa:bb:cc");
  
  my ($h,$m,$s,$txtc) = (0,0,0,0);
  
  my $bdist = "";                                                             # Abstand zum linken und rechten Rand
  for (my $i=0; $i<=$abdist; $i++ ) {
      $bdist .= " ";
  }
  
  if ($addp eq "stopwatch") {
      $alarmdef = "aa:bb:cc";                                                 # Stoppuhr bei Start 00:00:00 nicht Alerm auslösen
  }
  
  if ($addp eq "staticwatch") {                                               # statische Uhrzeitanzeige
      $h   = ReadingsVal($d, "hour"  , 0);
      $m   = ReadingsVal($d, "minute", 0);
      $s   = ReadingsVal($d, "second", 0);
  }

  my $back = << "END_JS";
     <html>
     <body>
     
     <canvas id='display_$d' $hattr style='background-color:#$bgc'></canvas>
    
     <script>
    // Segment display types
    SegmentDisplay_$d.SevenSegment    = 7;
    SegmentDisplay_$d.FourteenSegment = 14;
    SegmentDisplay_$d.SixteenSegment  = 16;

    // Segment corner types
    SegmentDisplay_$d.SymmetricCorner = 0;
    SegmentDisplay_$d.SquaredCorner   = 1;
    SegmentDisplay_$d.RoundedCorner   = 3;

    // Definition variables
    var state_$d;
    var st_$d;
    var ct_$d;
    var ci_$d;
    var csrf;
    var url_$d;
    var devName_$d;
    var selVal_$d;
    var hours_$d;
    var minutes_$d;
    var seconds_$d;
    var startDate_$d;
    var  ddt_$d;
    var almtime0_$d        = '$alarm';                // Alarmzeit initialisieren
    var digitxt_$d         = '$deftxt';               // default Digitaltext initialisieren
    var tticker_$d         = '$rdtt';                 // Tickereinstellung initialisieren
    var zmodulo_$d         = 0;                       // Hilfszähler
    var distBorderright_$d = '$bdist';                // Abstand zum rechten Rand
    var distBorderleft_$d  = '$bdist';                // Abstand zum linken Rand   
    var allowSetStopTime;                             // erlaube / verbiete Setzen Reading stoptime 

    function SegmentDisplay_$d(displayId_$d) {
        this.displayId_$d    = displayId_$d;
        this.pattern         = '##:##:##';
        this.value           = '12:34:56';
        this.digitHeight     = 20;
        this.digitWidth      = 10;
        this.digitDistance   = 2.5;
        this.displayAngle    = 12;
        this.segmentWidth    = 2.5;
        this.segmentDistance = 0.2;

        if ($adst == '7') {
            this.segmentCount = SegmentDisplay_$d.SevenSegment;
        }
        
        if ($adst == '14') {
            this.segmentCount = SegmentDisplay_$d.FourteenSegment;
        }
        
        if ($adst == '16') {
            this.segmentCount = SegmentDisplay_$d.SixteenSegment;
        }
        
        this.cornerType      = SegmentDisplay_$d.RoundedCorner;
        this.colorOn         = 'rgb(233, 93, 15)';
        this.colorOff        = 'rgb(75, 30, 5)';
    };
    
    var display_$d = new SegmentDisplay_$d('display_$d');
    display_$d.cornerType      = 2;
    display_$d.displayAngle    = $adda;                          // Zeichenwinkel:  -30 - 30 (9)
    display_$d.digitHeight     = $addh;                          // Zeichenhöhe:    5   - 50 (20)
    display_$d.digitWidth      = $addw;                          // Zeichenbreite:  5   - 50 (12)
    display_$d.digitDistance   = $addd;                          // Zeichenabstand: 0.5 - 10 (2)
    display_$d.segmentWidth    = $adsw;                          // Stärke des einzelnen Segments: 0.3 - 3.5 (1.5)
    display_$d.segmentDistance = $adsd;                          // Abstand der Einzelsegmente:    0   - 5   (0.5)
    display_$d.colorOn         = '#$dcd';                        // original: display_$d.colorOn = 'rgba(0, 0, 0, 0.9)';
    display_$d.colorOff        = 'rgba(0, 0, 0, 0.1)';

    SegmentDisplay_$d.prototype.setValue = function(value) {
                                               this.value = value;
                                               this.draw();
                                           };

    SegmentDisplay_$d.prototype.draw = function() {
        var display_$d = document.getElementById(this.displayId_$d);
        if (display_$d) {
            var context = display_$d.getContext('2d');
            if (context) {
                // clear canvas
                context.clearRect(0, 0, display_$d.width, display_$d.height);
          
                // compute and check display width
                var width = 0;
                var first = true;
                if (this.pattern) {
                    for (var i = 0; i < this.pattern.length; i++) {
                        var c = this.pattern.charAt(i).toLowerCase();
                        if (c == '#') {
                            width += this.digitWidth;
                        } else if (c == '.' || c == ':') {
                            width += this.segmentWidth;
                        } else if (c != ' ') {
                            return;
                        }
                        width += first ? 0 : this.digitDistance;
                        first = false;
                    }
                }
                if (width <= 0) {
                    return;
                }
          
                // compute skew factor
                var angle = -1.0 * Math.max(-45.0, Math.min(45.0, this.displayAngle));
                var skew  = Math.tan((angle * Math.PI) / 180.0);
          
                // compute scale factor
                var scale = Math.min(display_$d.width / (width + Math.abs(skew * this.digitHeight)), display_$d.height / this.digitHeight);
          
                // compute display offset
                var offsetX = (display_$d.width - (width + skew * this.digitHeight) * scale) / 2.0;
                var offsetY = (display_$d.height - this.digitHeight * scale) / 2.0;
          
                // context transformation
                context.save();
                context.translate(offsetX, offsetY);
                context.scale(scale, scale);
                context.transform(1, 0, skew, 1, 0, 0);

                // draw segments
                var xPos = 0;
                var size = (this.value) ? this.value.length : 0;
                for (var i = 0; i < this.pattern.length; i++) {
                    var mask  = this.pattern.charAt(i);
                    var value = (i < size) ? this.value.charAt(i).toLowerCase() : ' ';
                    xPos += this.drawDigit(context, xPos, mask, value);
                }

                // finish drawing
                context.restore();
            }
        }
    };

    SegmentDisplay_$d.prototype.drawDigit = function(context, xPos, mask, c) {
        switch (mask) {
            case '#':
            var r = Math.sqrt(this.segmentWidth * this.segmentWidth / 2.0);
            var d = Math.sqrt(this.segmentDistance * this.segmentDistance / 2.0);
            var e = d / 2.0; 
            var f = (this.segmentWidth - d) * Math.sin((45.0 * Math.PI) / 180.0);
            var g = f / 2.0;
            var h = (this.digitHeight - 3.0 * this.segmentWidth) / 2.0;
            var w = (this.digitWidth - 3.0 * this.segmentWidth) / 2.0;
            var s = this.segmentWidth / 2.0;
            var t = this.digitWidth / 2.0;

            // draw segment a (a1 and a2 for 16 segments)
            if (this.segmentCount == 16) {
                var x = xPos;
                var y = 0;
                context.fillStyle = this.getSegmentColor_$d(c, null, '02356789abcdefgiopqrstz@%');
                context.beginPath();
                switch (this.cornerType) {
                    case SegmentDisplay_$d.SymmetricCorner:
                        context.moveTo(x + s + d, y + s);
                        context.lineTo(x + this.segmentWidth + d, y);
                        break;
                    case SegmentDisplay_$d.SquaredCorner:
                        context.moveTo(x + s + e, y + s - e);
                        context.lineTo(x + this.segmentWidth, y);
                        break;
                    default:
                        context.moveTo(x + this.segmentWidth - f, y + this.segmentWidth - f - d);
                        context.quadraticCurveTo(x + this.segmentWidth - g, y, x + this.segmentWidth, y);
                }
                context.lineTo(x + t - d - s, y);
                context.lineTo(x + t - d, y + s);
                context.lineTo(x + t - d - s, y + this.segmentWidth);
                context.lineTo(x + this.segmentWidth + d, y + this.segmentWidth);
                context.fill();
            
                var x = xPos;
                var y = 0;
                context.fillStyle = this.getSegmentColor_$d(c, null, '02356789abcdefgiopqrstz\@');
                context.beginPath();
                context.moveTo(x + this.digitWidth - this.segmentWidth - d, y + this.segmentWidth);
                context.lineTo(x + t + d + s, y + this.segmentWidth);
                context.lineTo(x + t + d, y + s);
                context.lineTo(x + t + d + s, y);
                switch (this.cornerType) {
                    case SegmentDisplay_$d.SymmetricCorner:
                        context.lineTo(x + this.digitWidth - this.segmentWidth - d, y);
                        context.lineTo(x + this.digitWidth - s - d, y + s);
                        break;
                    case SegmentDisplay_$d.SquaredCorner:
                        context.lineTo(x + this.digitWidth - this.segmentWidth, y);
                        context.lineTo(x + this.digitWidth - s - e, y + s - e);
                        break;
                    default:
                        context.lineTo(x + this.digitWidth - this.segmentWidth, y);
                        context.quadraticCurveTo(x + this.digitWidth - this.segmentWidth + g, y, x + this.digitWidth - this.segmentWidth + f, y + this.segmentWidth - f - d);
                }
                context.fill();
            
            } else {
                var x = xPos;
                var y = 0;
                context.fillStyle = this.getSegmentColor_$d(c, '02356789acefp', '02356789abcdefgiopqrstz\@');
                context.beginPath();
                switch (this.cornerType) {
                    case SegmentDisplay_$d.SymmetricCorner:
                        context.moveTo(x + s + d, y + s);
                        context.lineTo(x + this.segmentWidth + d, y);
                        context.lineTo(x + this.digitWidth - this.segmentWidth - d, y);
                        context.lineTo(x + this.digitWidth - s - d, y + s);
                        break;
                    case SegmentDisplay_$d.SquaredCorner:
                        context.moveTo(x + s + e, y + s - e);
                        context.lineTo(x + this.segmentWidth, y);
                        context.lineTo(x + this.digitWidth - this.segmentWidth, y);
                        context.lineTo(x + this.digitWidth - s - e, y + s - e);
                        break;
                    default:
                        context.moveTo(x + this.segmentWidth - f, y + this.segmentWidth - f - d);
                        context.quadraticCurveTo(x + this.segmentWidth - g, y, x + this.segmentWidth, y);
                        context.lineTo(x + this.digitWidth - this.segmentWidth, y);
                        context.quadraticCurveTo(x + this.digitWidth - this.segmentWidth + g, y, x + this.digitWidth - this.segmentWidth + f, y + this.segmentWidth - f - d);
                }
                context.lineTo(x + this.digitWidth - this.segmentWidth - d, y + this.segmentWidth);
                context.lineTo(x + this.segmentWidth + d, y + this.segmentWidth);
                context.fill();
            }
          
            // draw segment b
            x = xPos + this.digitWidth - this.segmentWidth;
            y = 0;
            context.fillStyle = this.getSegmentColor_$d(c, '01234789adhpy', '01234789abdhjmnopqruwy');
            context.beginPath();
            switch (this.cornerType) {
                case SegmentDisplay_$d.SymmetricCorner:
                    context.moveTo(x + s, y + s + d);
                    context.lineTo(x + this.segmentWidth, y + this.segmentWidth + d);
                    break;
                case SegmentDisplay_$d.SquaredCorner:
                    context.moveTo(x + s + e, y + s + e);
                    context.lineTo(x + this.segmentWidth, y + this.segmentWidth);
                    break;
                default:
                    context.moveTo(x + f + d, y + this.segmentWidth - f);
                    context.quadraticCurveTo(x + this.segmentWidth, y + this.segmentWidth - g, x + this.segmentWidth, y + this.segmentWidth);
            }
            context.lineTo(x + this.segmentWidth, y + h + this.segmentWidth - d);
            context.lineTo(x + s, y + h + this.segmentWidth + s - d);
            context.lineTo(x, y + h + this.segmentWidth - d);
            context.lineTo(x, y + this.segmentWidth + d);
            context.fill();
          
            // draw segment c
            x = xPos + this.digitWidth - this.segmentWidth;
            y = h + this.segmentWidth;
            context.fillStyle = this.getSegmentColor_$d(c, '013456789abdhnouy', '01346789abdghjmnoqsuw\@', '%');
            context.beginPath();
            context.moveTo(x, y + this.segmentWidth + d);
            context.lineTo(x + s, y + s + d);
            context.lineTo(x + this.segmentWidth, y + this.segmentWidth + d);
            context.lineTo(x + this.segmentWidth, y + h + this.segmentWidth - d);
            switch (this.cornerType) {
                case SegmentDisplay_$d.SymmetricCorner:
                    context.lineTo(x + s, y + h + this.segmentWidth + s - d);
                    context.lineTo(x, y + h + this.segmentWidth - d);
                    break;
                case SegmentDisplay_$d.SquaredCorner:
                    context.lineTo(x + s + e, y + h + this.segmentWidth + s - e);
                    context.lineTo(x, y + h + this.segmentWidth - d);
                    break;
                default:
                    context.quadraticCurveTo(x + this.segmentWidth, y + h + this.segmentWidth + g, x + f + d, y + h + this.segmentWidth + f);
                    context.lineTo(x, y + h + this.segmentWidth - d);
            }
            context.fill();
          
            // draw segment d (d1 and d2 for 16 segments)
            if (this.segmentCount == 16) {
                x = xPos;
                y = this.digitHeight - this.segmentWidth;
                context.fillStyle = this.getSegmentColor_$d(c, null, '0235689bcdegijloqsuz_=\@');
                context.beginPath();
                context.moveTo(x + this.segmentWidth + d, y);
                context.lineTo(x + t - d - s, y);
                context.lineTo(x + t - d, y + s);
                context.lineTo(x + t - d - s, y + this.segmentWidth);
                switch (this.cornerType) {
                    case SegmentDisplay_$d.SymmetricCorner:
                        context.lineTo(x + this.segmentWidth + d, y + this.segmentWidth);
                        context.lineTo(x + s + d, y + s);
                        break;
                    case SegmentDisplay_$d.SquaredCorner:
                        context.lineTo(x + this.segmentWidth, y + this.segmentWidth);
                        context.lineTo(x + s + e, y + s + e);
                        break;
                    default:
                        context.lineTo(x + this.segmentWidth, y + this.segmentWidth);
                        context.quadraticCurveTo(x + this.segmentWidth - g, y + this.segmentWidth, x + this.segmentWidth - f, y + f + d);
                        context.lineTo(x + this.segmentWidth - f, y + f + d);
                }
                context.fill();

                x = xPos;
                y = this.digitHeight - this.segmentWidth;
                context.fillStyle = this.getSegmentColor_$d(c, null, '0235689bcdegijloqsuz_=\@', '%');
                context.beginPath();
                context.moveTo(x + t + d + s, y + this.segmentWidth);
                context.lineTo(x + t + d, y + s);
                context.lineTo(x + t + d + s, y);
                context.lineTo(x + this.digitWidth - this.segmentWidth - d, y);
                switch (this.cornerType) {
                    case SegmentDisplay_$d.SymmetricCorner:
                        context.lineTo(x + this.digitWidth - s - d, y + s);
                        context.lineTo(x + this.digitWidth - this.segmentWidth - d, y + this.segmentWidth);
                        break;
                    case SegmentDisplay_$d.SquaredCorner:
                        context.lineTo(x + this.digitWidth - s - e, y + s + e);
                        context.lineTo(x + this.digitWidth - this.segmentWidth, y + this.segmentWidth);
                        break;
                    default:
                        context.lineTo(x + this.digitWidth - this.segmentWidth + f, y + f + d);
                        context.quadraticCurveTo(x + this.digitWidth - this.segmentWidth + g, y + this.segmentWidth, x + this.digitWidth - this.segmentWidth, y + this.segmentWidth);
                }
                context.fill();
            
            } else {
                x = xPos;
                y = this.digitHeight - this.segmentWidth;
                context.fillStyle = this.getSegmentColor_$d(c, '0235689bcdelotuy_', '0235689bcdegijloqsuz_=\@');
                context.beginPath();
                context.moveTo(x + this.segmentWidth + d, y);
                context.lineTo(x + this.digitWidth - this.segmentWidth - d, y);
                switch (this.cornerType) {
                    case SegmentDisplay_$d.SymmetricCorner:
                        context.lineTo(x + this.digitWidth - s - d, y + s);
                        context.lineTo(x + this.digitWidth - this.segmentWidth - d, y + this.segmentWidth);
                        context.lineTo(x + this.segmentWidth + d, y + this.segmentWidth);
                        context.lineTo(x + s + d, y + s);
                        break;
                    case SegmentDisplay_$d.SquaredCorner:
                        context.lineTo(x + this.digitWidth - s - e, y + s + e);
                        context.lineTo(x + this.digitWidth - this.segmentWidth, y + this.segmentWidth);
                        context.lineTo(x + this.segmentWidth, y + this.segmentWidth);
                        context.lineTo(x + s + e, y + s + e);
                        break;
                    default:
                        context.lineTo(x + this.digitWidth - this.segmentWidth + f, y + f + d);
                        context.quadraticCurveTo(x + this.digitWidth - this.segmentWidth + g, y + this.segmentWidth, x + this.digitWidth - this.segmentWidth, y + this.segmentWidth);
                        context.lineTo(x + this.segmentWidth, y + this.segmentWidth);
                        context.quadraticCurveTo(x + this.segmentWidth - g, y + this.segmentWidth, x + this.segmentWidth - f, y + f + d);
                        context.lineTo(x + this.segmentWidth - f, y + f + d);
                }
                context.fill();
            }
          
            // draw segment e
            x = xPos;
            y = h + this.segmentWidth;
            context.fillStyle = this.getSegmentColor_$d(c, '0268abcdefhlnoprtu', '0268acefghjklmnopqruvw\@');
            context.beginPath();
            context.moveTo(x, y + this.segmentWidth + d);
            context.lineTo(x + s, y + s + d);
            context.lineTo(x + this.segmentWidth, y + this.segmentWidth + d);
            context.lineTo(x + this.segmentWidth, y + h + this.segmentWidth - d);
            switch (this.cornerType) {
                case SegmentDisplay_$d.SymmetricCorner:
                    context.lineTo(x + s, y + h + this.segmentWidth + s - d);
                    context.lineTo(x, y + h + this.segmentWidth - d);
                    break;
                case SegmentDisplay_$d.SquaredCorner:
                    context.lineTo(x + s - e, y + h + this.segmentWidth + s - d + e);
                    context.lineTo(x, y + h + this.segmentWidth);
                    break;
                default:
                    context.lineTo(x + this.segmentWidth - f - d, y + h + this.segmentWidth + f); 
                    context.quadraticCurveTo(x, y + h + this.segmentWidth + g, x, y + h + this.segmentWidth);
            }
            context.fill();
          
            // draw segment f
            x = xPos;
            y = 0;
            context.fillStyle = this.getSegmentColor_$d(c, '045689abcefhlpty', '045689acefghklmnopqrsuvwy\@', '%');
            context.beginPath();
            context.moveTo(x + this.segmentWidth, y + this.segmentWidth + d);
            context.lineTo(x + this.segmentWidth, y + h + this.segmentWidth - d);
            context.lineTo(x + s, y + h + this.segmentWidth + s - d);
            context.lineTo(x, y + h + this.segmentWidth - d);
            switch (this.cornerType) {
                case SegmentDisplay_$d.SymmetricCorner:
                    context.lineTo(x, y + this.segmentWidth + d);
                    context.lineTo(x + s, y + s + d);
                    break;
                case SegmentDisplay_$d.SquaredCorner:
                    context.lineTo(x, y + this.segmentWidth);
                    context.lineTo(x + s - e, y + s + e);
                    break;
                default:
                    context.lineTo(x, y + this.segmentWidth);
                    context.quadraticCurveTo(x, y + this.segmentWidth - g, x + this.segmentWidth - f - d, y + this.segmentWidth - f); 
                    context.lineTo(x + this.segmentWidth - f - d, y + this.segmentWidth - f); 
            }
            context.fill();

            // draw segment g for 7 segments
            if (this.segmentCount == 7) {
                x = xPos;
                y = (this.digitHeight - this.segmentWidth) / 2.0;
                context.fillStyle = this.getSegmentColor_$d(c, '2345689abdefhnoprty-=');
                context.beginPath();
                context.moveTo(x + s + d, y + s);
                context.lineTo(x + this.segmentWidth + d, y);
                context.lineTo(x + this.digitWidth - this.segmentWidth - d, y);
                context.lineTo(x + this.digitWidth - s - d, y + s);
                context.lineTo(x + this.digitWidth - this.segmentWidth - d, y + this.segmentWidth);
                context.lineTo(x + this.segmentWidth + d, y + this.segmentWidth);
                context.fill();
            }
                
            // draw inner segments for the fourteen- and sixteen-segment-display
            if (this.segmentCount != 7) {
                // draw segment g1
                x = xPos;
                y = (this.digitHeight - this.segmentWidth) / 2.0;
                context.fillStyle = this.getSegmentColor_$d(c, null, '2345689aefhkprsy-+*=', '%');
                context.beginPath();
                context.moveTo(x + s + d, y + s);
                context.lineTo(x + this.segmentWidth + d, y);
                context.lineTo(x + t - d - s, y);
                context.lineTo(x + t - d, y + s);
                context.lineTo(x + t - d - s, y + this.segmentWidth);
                context.lineTo(x + this.segmentWidth + d, y + this.segmentWidth);
                context.fill();
                
                // draw segment g2
                x = xPos;
                y = (this.digitHeight - this.segmentWidth) / 2.0;
                context.fillStyle = this.getSegmentColor_$d(c, null, '234689abefghprsy-+*=\@', '%');
                context.beginPath();
                context.moveTo(x + t + d, y + s);
                context.lineTo(x + t + d + s, y);
                context.lineTo(x + this.digitWidth - this.segmentWidth - d, y);
                context.lineTo(x + this.digitWidth - s - d, y + s);
                context.lineTo(x + this.digitWidth - this.segmentWidth - d, y + this.segmentWidth);
                context.lineTo(x + t + d + s, y + this.segmentWidth);
                context.fill();
                
                // draw segment j 
                x = xPos + t - s;
                y = 0;
                context.fillStyle = this.getSegmentColor_$d(c, null, 'bdit+*', '%');
                context.beginPath();
                if (this.segmentCount == 14) {
                    context.moveTo(x, y + this.segmentWidth + this.segmentDistance);
                    context.lineTo(x + this.segmentWidth, y + this.segmentWidth + this.segmentDistance);
                } else {
                    context.moveTo(x, y + this.segmentWidth + d);
                    context.lineTo(x + s, y + s + d);
                    context.lineTo(x + this.segmentWidth, y + this.segmentWidth + d);
                }
                context.lineTo(x + this.segmentWidth, y + h + this.segmentWidth - d);
                context.lineTo(x + s, y + h + this.segmentWidth + s - d);
                context.lineTo(x, y + h + this.segmentWidth - d);
                context.fill();
            
                // draw segment m
                x = xPos + t - s;
                y = this.digitHeight;
                context.fillStyle = this.getSegmentColor_$d(c, null, 'bdity+*\@', '%');
                context.beginPath();
                if (this.segmentCount == 14) {
                    context.moveTo(x, y - this.segmentWidth - this.segmentDistance);
                    context.lineTo(x + this.segmentWidth, y - this.segmentWidth - this.segmentDistance);
                } else {
                    context.moveTo(x, y - this.segmentWidth - d);
                    context.lineTo(x + s, y - s - d);
                    context.lineTo(x + this.segmentWidth, y - this.segmentWidth - d);
                }
                context.lineTo(x + this.segmentWidth, y - h - this.segmentWidth + d);
                context.lineTo(x + s, y - h - this.segmentWidth - s + d);
                context.lineTo(x, y - h - this.segmentWidth + d);
                context.fill();
            
                // draw segment h
                x = xPos + this.segmentWidth;
                y = this.segmentWidth;
                context.fillStyle = this.getSegmentColor_$d(c, null, 'mnx\\\\*');
                context.beginPath();
                context.moveTo(x + this.segmentDistance, y + this.segmentDistance);
                context.lineTo(x + this.segmentDistance + r, y + this.segmentDistance);
                context.lineTo(x + w - this.segmentDistance , y + h - this.segmentDistance - r);
                context.lineTo(x + w - this.segmentDistance , y + h - this.segmentDistance);
                context.lineTo(x + w - this.segmentDistance - r , y + h - this.segmentDistance);
                context.lineTo(x + this.segmentDistance, y + this.segmentDistance + r);
                context.fill();
                
                // draw segment k
                x = xPos + w + 2.0 * this.segmentWidth;
                y = this.segmentWidth;
                context.fillStyle = this.getSegmentColor_$d(c, null, '0kmvxz/*', '%');
                context.beginPath();
                context.moveTo(x + w - this.segmentDistance, y + this.segmentDistance);
                context.lineTo(x + w - this.segmentDistance, y + this.segmentDistance + r);
                context.lineTo(x + this.segmentDistance + r, y + h - this.segmentDistance);
                context.lineTo(x + this.segmentDistance, y + h - this.segmentDistance);
                context.lineTo(x + this.segmentDistance, y + h - this.segmentDistance - r);
                context.lineTo(x + w - this.segmentDistance - r, y + this.segmentDistance);
                context.fill();
            
                // draw segment l
                x = xPos + w + 2.0 * this.segmentWidth;
                y = h + 2.0 * this.segmentWidth;
                context.fillStyle = this.getSegmentColor_$d(c, null, '5knqrwx\\\\*');
                context.beginPath();
                context.moveTo(x + this.segmentDistance, y + this.segmentDistance);
                context.lineTo(x + this.segmentDistance + r, y + this.segmentDistance);
                context.lineTo(x + w - this.segmentDistance , y + h - this.segmentDistance - r);
                context.lineTo(x + w - this.segmentDistance , y + h - this.segmentDistance);
                context.lineTo(x + w - this.segmentDistance - r , y + h - this.segmentDistance);
                context.lineTo(x + this.segmentDistance, y + this.segmentDistance + r);
                context.fill();
                
                // draw segment n
                x = xPos + this.segmentWidth;
                y = h + 2.0 * this.segmentWidth;
                context.fillStyle = this.getSegmentColor_$d(c, null, '0vwxz/*', '%');
                context.beginPath();
                context.moveTo(x + w - this.segmentDistance, y + this.segmentDistance);
                context.lineTo(x + w - this.segmentDistance, y + this.segmentDistance + r);
                context.lineTo(x + this.segmentDistance + r, y + h - this.segmentDistance);
                context.lineTo(x + this.segmentDistance, y + h - this.segmentDistance);
                context.lineTo(x + this.segmentDistance, y + h - this.segmentDistance - r);
                context.lineTo(x + w - this.segmentDistance - r, y + this.segmentDistance);
                context.fill();
            }
          
            return this.digitDistance + this.digitWidth;
          
            case '.':
                context.fillStyle = (c == '#') || (c == '.') ? this.colorOn : this.colorOff;
                this.drawPoint(context, xPos, this.digitHeight - this.segmentWidth, this.segmentWidth);
                return this.digitDistance + this.segmentWidth;
          
            case ':':
                context.fillStyle = (c == '#') || (c == ':') ? this.colorOn : this.colorOff;
                var y = (this.digitHeight - this.segmentWidth) / 2.0 - this.segmentWidth;
                this.drawPoint(context, xPos, y, this.segmentWidth);
                this.drawPoint(context, xPos, y + 2.0 * this.segmentWidth, this.segmentWidth);
                return this.digitDistance + this.segmentWidth;
          
            default:
                return this.digitDistance;    
        }
    };

    SegmentDisplay_$d.prototype.drawPoint = function(context, x1, y1, size) {
        var x2 = x1 + size;
        var y2 = y1 + size;
        var d  = size / 4.0;
      
        context.beginPath();
        context.moveTo(x2 - d, y1);
        context.quadraticCurveTo(x2, y1, x2, y1 + d);
        context.lineTo(x2, y2 - d);
        context.quadraticCurveTo(x2, y2, x2 - d, y2);
        context.lineTo(x1 + d, y2);
        context.quadraticCurveTo(x1, y2, x1, y2 - d);
        context.lineTo(x1, y1 + d);
        context.quadraticCurveTo(x1, y1, x1 + d, y1);
        context.fill();
    }; 

    SegmentDisplay_$d.prototype.getSegmentColor_$d = function(c, charSet7, charSet14, charSet16) {
                                                         if (c == '#') {
                                                             return this.colorOn;
                                                         } else {
                                                             switch (this.segmentCount) {
                                                                 case 7:  return (charSet7.indexOf(c) == -1) ? this.colorOff : this.colorOn;
                                                                 case 14: return (charSet14.indexOf(c) == -1) ? this.colorOff : this.colorOn;
                                                                 case 16: var pattern = charSet14 + (charSet16 === undefined ? '' : charSet16);
                                                                 return (pattern.indexOf(c) == -1) ? this.colorOff : this.colorOn;
                                                                 default: return this.colorOff;
                                                             }
                                                         }
                                                     };
    
    // CSRF-Token auslesen
    var body = document.querySelector("body");
    if( body != null ) {
        csrf = body.getAttribute("fwcsrf");
    }
 
    // get the base url
    function getBaseUrl () {
        var url = window.location.href.split("?")[0];
        url += "?";
        if( csrf != null ) {
            url += "fwcsrf="+csrf+"&";
        }
        return url;
    }

    function makeCommand (cmd) {
        return getBaseUrl()+"cmd="+encodeURIComponent(cmd)+"&XHR=1";
    }
    
    // Template digital time display
    function buildtime (hours, minutes, seconds) {
        var ddt = ((hours   < 10) ? '0' : '') + hours   + ':' + 
                  ((minutes < 10) ? '0' : '') + minutes + ':' + 
                  ((seconds < 10) ? '0' : '') + seconds
                  ;   
        return ddt;
    }
    
    // localStorage Set 
    function localStoreSet_$d (hours, minutes, seconds, sumsecs, aSetStopT) {
        if (Number.isInteger(hours))     { localStorage.setItem('h_$d',   hours);     }
        if (Number.isInteger(minutes))   { localStorage.setItem('m_$d',   minutes);   }
        if (Number.isInteger(seconds))   { localStorage.setItem('s_$d',   seconds);   }
        if (Number.isInteger(sumsecs))   { localStorage.setItem('ss_$d',  sumsecs);   }
        if (Number.isInteger(aSetStopT)) { localStorage.setItem('ast_$d', aSetStopT); }
    }
    
    // localStorage speichern letzte Alarmzeit
    function localStoreSetLastalm_$d (dev, lastalmtime) {
        localStorage.setItem('lastalmtime_'+dev, lastalmtime);
    }
    
    // Check ob Alarm ausgelöst werden soll und ggf. Alarmevent triggern
    function checkAndDoAlm_$d (dev, acttime, almtime) {
        lastalmtime_$d = localStorage.getItem('lastalmtime_$d');                              // letzte Alarmzeit laden        
        if ( (acttime == almtime || acttime == '$alarmdef') && acttime != lastalmtime_$d ) {
            command = '{ CommandSetReading(undef, "$d alarmed '+acttime+'") }';
            url_$d  = makeCommand(command);
              
            localStoreSetLastalm_$d (dev, acttime);                                           // aktuelle Alarmzeit sichern 
              
            if(acttime == almtime) {
               \$.get(url_$d);
            
            } else {
                \$.get(url_$d, function (data) {
                                command = '{ CommandSetReading(undef, "$d state stopped") }';
                                url_$d  = makeCommand(command);
                                \$.get(url_$d);
                            }
                      );                                       
            }
        }
    }
    
    animate_$d();
    
    function animate_$d() {
        var watchkind_$d = '$addp';
        var cycletime    = new Date();
        var cycleseconds = cycletime.getSeconds();
        modulo2_$d       = cycleseconds % 2;                                           // Taktung für Readingabruf (Serverauslastung reduzieren)

        if (watchkind_$d == 'watch') {                  
            if (modulo2_$d != zmodulo_$d) {
                command = '{ReadingsVal("$d","alarmTime","+almtime0_$d+")}';     // alarmTime Reading lesen
                url_$d  = makeCommand(command);
                \$.get( url_$d, function (data) {
                                    almtime0_$d = data.replace(/\\n/g, '');
                                    zmodulo_$d = modulo2_$d;
                                    return (almtime0_$d, zmodulo_$d);
                                } 
                      );
            }            
            
            // Zeitsteuerung - aktueller Timestamp in Millisekunden
            if ('$tsou' == 'server') {                   // Serverzeit
                command = '{ int(time*1000) }';
                url_$d  = makeCommand(command);
                \$.get( url_$d, function (data) {
                                    data = data.replace(/\\n/g, ''); 
                                    ct_$d = parseInt(data); 
                                    return ct_$d;
                                } 
                      ); 
              
                time_$d  = new Date(ct_$d);
              
            } else {
                time_$d  = new Date();                   // Clientzeit
            }
          
            if (typeof ct_$d === 'undefined') {          // wenn Zeit noch undef mit lokaler Zeit initialisieren -> springen Zeiger verhindern
                time_$d  = new Date();                   
            } else {
                time_$d  = new Date(ct_$d);
            }                  
                  
            var hours_$d   = time_$d.getHours();
            var minutes_$d = time_$d.getMinutes();
            var seconds_$d = time_$d.getSeconds();
            
            acttime_$d = ((hours_$d   < 10) ? '0' : '') + hours_$d   + ':' + 
                         ((minutes_$d < 10) ? '0' : '') + minutes_$d + ':' + 
                         ((seconds_$d < 10) ? '0' : '') + seconds_$d;
                         
            if (acttime_$d == '00:00:00') {
                localStoreSetLastalm_$d ('$d', 'NaN');               // letzte Alarmzeit zurücksetzen zum Tageswechsel            
            }

            checkAndDoAlm_$d ('$d', acttime_$d, almtime0_$d);
        }
        
        if (watchkind_$d == 'staticwatch') {
            var hours_$d   = '$h';
            var minutes_$d = '$m';
            var seconds_$d = '$s';
        }
        
        if (watchkind_$d == 'stopwatch') {           
            command = '{ReadingsVal("$d","state","")}';                          // state Reading lesen
            url_$d  = makeCommand(command);
            \$.get( url_$d, function (data) {
                                state_$d = data.replace(/\\n/g, '');                                
                                return state_$d;
                            } 
                  );
            
            if (state_$d == 'started' || state_$d == 'resumed') { 
                localStoreSet_$d        (NaN, NaN, NaN, NaN, 1);                     // set Reading stoptime freischalten
                
                if (modulo2_$d != zmodulo_$d) {
                    command = '{ReadingsVal("$d","alarmTime","+almtime0_$d+")}';     // alarmTime Reading lesen
                    url_$d  = makeCommand(command);
                    \$.get( url_$d, function (data) {
                                        almtime0_$d = data.replace(/\\n/g, '');
                                        zmodulo_$d = modulo2_$d;
                                        return (almtime0_$d, zmodulo_$d);
                                    } 
                          );
                }
                
                // == Startzeit für CountDown ==            
                command   = '{ReadingsNum("$d","starttime", 0)}';
                url_$d    = makeCommand(command);
                \$.get( url_$d, function (data) {
                                    data  = data.replace(/\\n/g, ''); 
                                    st_$d = parseInt(data); 
                                    return st_$d;
                                } 
                      );
                
                startDate_$d = new Date(st_$d);
                
                // aktueller Timestamp in Millisekunden      
                currDate_$d  = new Date();            
                elapsesec_$d = ((currDate_$d.getTime() - startDate_$d.getTime()))/1000;    // vergangene Millisekunden in Sekunden
                
                if (state_$d == 'resumed') {
                    lastsumsec_$d = localStorage.getItem('ss_$d');                                                      
                    elapsesec_$d  = parseInt(elapsesec_$d) + parseInt(lastsumsec_$d);
                } else {
                    elapsesec_$d  = parseInt(elapsesec_$d);
                }
                
                if (state_$d == 'started' && elapsesec_$d <= 5) {
                    localStoreSetLastalm_$d ('$d', 'NaN');                               // letzte Alarmzeit zurücksetzen bis 2 s nach Start            
                }
                
                hours_$d       = parseInt(elapsesec_$d / 3600);
                elapsesec_$d  -= hours_$d * 3600;
                minutes_$d     = parseInt(elapsesec_$d / 60);
                seconds_$d     = parseInt(elapsesec_$d - minutes_$d * 60);
                
                ddt_$d = buildtime (hours_$d, minutes_$d, seconds_$d);
                
                checkAndDoAlm_$d ('$d', ddt_$d, almtime0_$d);                           // Alarm auslösen wenn zutreffend
                
                localStoreSet_$d (hours_$d, minutes_$d, seconds_$d, NaN);
            }
            
            if (state_$d == 'stopped') {
                hours_$d   = localStorage.getItem('h_$d');
                minutes_$d = localStorage.getItem('m_$d');
                seconds_$d = localStorage.getItem('s_$d');
                
                sumsecs_$d = parseInt(hours_$d*3600) + parseInt(minutes_$d*60) + parseInt(seconds_$d);
                localStoreSet_$d        (NaN, NaN, NaN, sumsecs_$d);
                
                allowSetStopTime = localStorage.getItem('ast_$d');
                if(allowSetStopTime == 1) {
                    ddt_$d = buildtime (hours_$d, minutes_$d, seconds_$d);             // Reading mit Stoppzeit setzen

                    command = '{ CommandSetReading(undef, "$d stoptime '+ddt_$d+'") }';
                    url_$d  = makeCommand(command);
                    \$.get(url_$d);
                }
                localStoreSet_$d        (NaN, NaN, NaN, NaN, 0);                      // set Reading stoptime verbieten
            }

            if (state_$d == 'initialized') {
                hours_$d   = 0;
                minutes_$d = 0;
                seconds_$d = 0;

                localStoreSet_$d (hours_$d, minutes_$d, seconds_$d);
                localStoreSetLastalm_$d ('$d', 'NaN');                                  // letzte Alarmzeit zurücksetzen                 
            }
        }
        
        if (watchkind_$d == 'countdownwatch') {                                    
            command = '{ReadingsVal("$d","state","")}';
            url_$d  = makeCommand(command);
            \$.get( url_$d, function (data) {
                                state_$d = data.replace(/\\n/g, '');                      
                                return state_$d;
                            } 
                  );
            
            if (state_$d == 'started' || state_$d == 'resumed') {                
                if (modulo2_$d != zmodulo_$d) {
                    command = '{ReadingsVal("$d","alarmTime","+almtime0_$d+")}';     // alarmTime Reading lesen
                    url_$d  = makeCommand(command);
                    \$.get( url_$d, function (data) {
                                        almtime0_$d = data.replace(/\\n/g, '');
                                        zmodulo_$d = modulo2_$d;  
                                        return (almtime0_$d, zmodulo_$d);
                                    } 
                          );
                }
                
                // == Ermittlung Countdown Startwert ==
                if (modulo2_$d != zmodulo_$d) {                
                    command   = '{ReadingsNum("$d","countInitVal", 0)}';
                    url_$d    = makeCommand(command);
                    \$.get( url_$d, function (data) {
                                        data  = data.replace(/\\n/g, ''); 
                                        ci_$d = parseInt(data); 
                                        return ci_$d;
                                    } 
                          );
                }
                      
                if (state_$d == 'resumed') {
                    countInitVal_$d = localStorage.getItem('ss_$d');
                } else {
                    countInitVal_$d = parseInt(ci_$d);                                   // Initialwert Countdown in Sekunden 
                }
                
                // == Ermittlung vergangene Sekunden ==                  
                command = '{ReadingsNum("$d","starttime", 0)}';
                url_$d  = makeCommand(command);
                \$.get( url_$d, function (data) {
                                    data  = data.replace(/\\n/g, ''); 
                                    st_$d = parseInt(data); 
                                    return st_$d;
                                } 
                      );
                      
                startDate_$d = new Date(st_$d);
                
                // aktueller Timestamp in Millisekunden 
                command   = '{ int(time*1000) }';
                url_$d    = makeCommand(command);
                \$.get( url_$d, function (data) {
                                    data  = data.replace(/\\n/g, ''); 
                                    ct_$d = parseInt(data);                               
                                    return ct_$d;
                                } 
                      );
     
                currDate_$d  = new Date(ct_$d);
                elapsesec_$d = (currDate_$d.getTime() - startDate_$d.getTime())/1000;    // vergangene Millisekunden in Sekunden umrechnen
                
                if (state_$d == 'started' && elapsesec_$d <= 5) {
                    localStoreSetLastalm_$d ('$d', 'NaN');                               // letzte Alarmzeit zurücksetzen bis 2 s nach Start            
                }                
                
                // == Countdown errechnen ==
                countcurr_$d = parseInt(countInitVal_$d) - parseInt(elapsesec_$d);
                //log("countcurr_$d: "+countcurr_$d);
                
                hours_$d       = parseInt(countcurr_$d / 3600);
                countcurr_$d  -= hours_$d * 3600;
                minutes_$d     = parseInt(countcurr_$d / 60);
                seconds_$d     = parseInt(countcurr_$d - minutes_$d * 60);
     
                if (countcurr_$d >= 0) {
                    ddt_$d = buildtime (hours_$d, minutes_$d, seconds_$d);
                    checkAndDoAlm_$d ('$d', ddt_$d, almtime0_$d);                       // Alarm auslösen wenn zutreffend
                    localStoreSet_$d (hours_$d, minutes_$d, seconds_$d, NaN);
                }
            }
            
            if (state_$d == 'stopped') {
                hours_$d   = localStorage.getItem('h_$d');
                minutes_$d = localStorage.getItem('m_$d');
                seconds_$d = localStorage.getItem('s_$d');
                
                pastsumsec_$d = parseInt(hours_$d*3600) + parseInt(minutes_$d*60) + parseInt(seconds_$d);
                localStoreSet_$d (NaN, NaN, NaN, pastsumsec_$d);
            }

            if (state_$d == 'initialized') {
                hours_$d   = 0;
                minutes_$d = 0;
                seconds_$d = 0;
                
                localStoreSet_$d (hours_$d, minutes_$d, seconds_$d);
                localStoreSetLastalm_$d ('$d', 'NaN');                                 // letzte Alarmzeit zurücksetzen
            }
        }
        
        if (watchkind_$d == 'text') {  
            tlength_$d = digitxt_$d.length;                                   // Länge des Textes
            if($adtdn > 0) {
                tlength_$d = $adtdn;
            }  
            
            display_$d.pattern = '';                                          // Template erstellen
            forerun_$d         = '';                                          // Vorlauf Textticker initialisieren
            for (var i = 0; i <= tlength_$d; i++) {
                display_$d.pattern += '#';
                forerun_$d         += ' ';
            }
            display_$d.pattern += distBorderright_$d;                         // Abstand Text zum rechten Rand  
            display_$d.pattern  = distBorderleft_$d + display_$d.pattern      
                        
            if (tticker_$d == 'on') {                                         // Text als Laufband ?                         
                var rttime    = new Date();
                var rthours   = rttime.getHours();
                var rtminutes = rttime.getMinutes();
                var rtseconds = rttime.getSeconds();
                var rtmillis  = rttime.getMilliseconds();
                
                var text_$d  = forerun_$d+digitxt_$d+'      ';
                var index_$d = ( 2 * (rtseconds + 60*rtminutes + 24*60*rthours) + Math.floor(rtmillis / 500) ) % (text_$d.length - 6);
                value_$d     = distBorderleft_$d + text_$d.substr(index_$d, tlength_$d+1);
            
            } else {
                value_$d = distBorderleft_$d + digitxt_$d;
            }
            
            if (modulo2_$d != zmodulo_$d) {
                command = '{ReadingsVal("$d","displayText", "$deftxt")}';     // Text dynamisch aus Reading lesen
                url_$d  = makeCommand(command);
                \$.get( url_$d, function (data) {
                                    digitxt_$d = data.replace(/\\n/g, '');
                                    return (digitxt_$d);                                     
                                } 
                      );
            }
                  
            if (modulo2_$d != zmodulo_$d) {
                command = '{ReadingsVal("$d","displayTextTicker", "off")}';         // Textticker Einstellung aus Reading lesen
                url_$d  = makeCommand(command);
                \$.get( url_$d, function (data) {
                                    tticker_$d = data.replace(/\\n/g, '');
                                    zmodulo_$d = modulo2_$d;  
                                    return (tticker_$d, zmodulo_$d);                                    
                                } 
                      );
            }
        
        } else { 
            display_$d.pattern = distBorderleft_$d + '##:##:##' + distBorderright_$d;    // Textschablone initialisieren        
            ddt_$d   = buildtime (hours_$d, minutes_$d, seconds_$d);            
            value_$d = distBorderleft_$d + ddt_$d;
            
            if(value_$d == distBorderleft_$d + 'undefined:undefined:undefined' || value_$d == distBorderleft_$d + 'NaN:NaN:NaN') {
               value_$d = distBorderleft_$d + '  :  :  '; 
            }
        }
        
        display_$d.setValue(value_$d);
        window.setTimeout('animate_$d()', 200);
    }

    </script>
    </body>
    </html>      
  
END_JS

return qq{$back};
}

##############################################################################
#                            Bahnhofsuhr aus:
#                  http://www.3quarks.com/de/Bahnhofsuhr
#
##############################################################################
sub stationWatch {
  my ($d)    = @_;
  my $hash   = $defs{$d};
  my $ssh    = AttrVal ($d, "stationSecondHand",         "Bar").      "SecondHand";
  my $shb    = AttrVal ($d, "stationSecondHandBehavoir", "Bouncing"). "SecondHand";
  my $smh    = AttrVal ($d, "stationMinuteHand",         "Pointed").  "MinuteHand";
  my $mhb    = AttrVal ($d, "stationMinuteHandBehavoir", "Bouncing"). "MinuteHand";
  my $shh    = AttrVal ($d, "stationHourHand",           "Pointed").  "HourHand";
  my $sb     = AttrVal ($d, "stationBoss",               "Red").      "Boss"; 
  my $ssd    = AttrVal ($d, "stationStrokeDial",         "Swiss").    "StrokeDial";
  my $sbody  = AttrVal ($d, "stationBody",               "Round").    "Body";
  my $hattr  = AttrVal ($d, "htmlattr",                  "width='150' height='150'");
  my $tsou   = AttrVal ($d, "timeSource",                "client"); 
  
  my $alarm  = ReadingsVal($d, "alarmTime", "aa:bb:cc");

  my $back = << "END_JS";
      <html>
      <body>  
      <canvas id='clock_$d' $hattr> 
      </canvas>
      
      <script>  
      
      var ct_$d;
      var almtime0_$d = '$alarm';
      var time_$d;       
      var zmodulo_$d  = 0;                              // Hilfszähler      
      
      // clock body (Uhrgehäuse)
      StationClock_$d.NoBody         = 0;
      StationClock_$d.SmallWhiteBody = 1;
      StationClock_$d.RoundBody      = 2;
      StationClock_$d.RoundGreenBody = 3;
      StationClock_$d.SquareBody     = 4;
      StationClock_$d.ViennaBody     = 5;

      // stroke dial (Zifferblatt)
      StationClock_$d.NoDial               = 0;
      StationClock_$d.GermanHourStrokeDial = 1;
      StationClock_$d.GermanStrokeDial     = 2;
      StationClock_$d.AustriaStrokeDial    = 3;
      StationClock_$d.SwissStrokeDial      = 4;
      StationClock_$d.ViennaStrokeDial     = 5;

      //clock hour hand (Stundenzeiger)
      StationClock_$d.PointedHourHand = 1;
      StationClock_$d.BarHourHand     = 2;
      StationClock_$d.SwissHourHand   = 3;
      StationClock_$d.ViennaHourHand  = 4;

      //clock minute hand (Minutenzeiger)
      StationClock_$d.PointedMinuteHand = 1;
      StationClock_$d.BarMinuteHand     = 2;
      StationClock_$d.SwissMinuteHand   = 3;
      StationClock_$d.ViennaMinuteHand  = 4;

      //clock second hand (Sekundenzeiger)
      StationClock_$d.NoSecondHand            = 0;
      StationClock_$d.BarSecondHand           = 1;
      StationClock_$d.HoleShapedSecondHand    = 2;
      StationClock_$d.NewHoleShapedSecondHand = 3;
      StationClock_$d.SwissSecondHand         = 4;

      // clock boss (Zeigerabdeckung)
      StationClock_$d.NoBoss     = 0;
      StationClock_$d.BlackBoss  = 1;
      StationClock_$d.RedBoss    = 2;
      StationClock_$d.ViennaBoss = 3;

      // minute hand behavoir
      StationClock_$d.CreepingMinuteHand        = 0;
      StationClock_$d.BouncingMinuteHand        = 1;
      StationClock_$d.ElasticBouncingMinuteHand = 2;

      // second hand behavoir
      StationClock_$d.CreepingSecondHand        = 0;
      StationClock_$d.BouncingSecondHand        = 1;
      StationClock_$d.ElasticBouncingSecondHand = 2;
      StationClock_$d.OverhastySecondHand       = 3;
      
      // CSRF-Token auslesen
      var body = document.querySelector("body");
      if( body != null ) {
          csrf = body.getAttribute("fwcsrf");
      }
 
      // get the base url
      function getBaseUrl () {
          var url = window.location.href.split("?")[0];
          url += "?";
          if( csrf != null ) {
              url += "fwcsrf="+csrf+"&";
          }
          return url;
      }

      function makeCommand (cmd) {
          return getBaseUrl()+"cmd="+encodeURIComponent(cmd)+"&XHR=1";
      }
      
      // localStorage speichern letzte Alarmzeit
      function localStoreSetLastalm_$d (dev, lastalmtime) {
          localStorage.setItem('lastalmtime_'+dev, lastalmtime);
      }
    
      // Check ob Alarm ausgelöst werden soll und ggf. Alarmevent triggern
      function checkAndDoAlm_$d (dev, acttime, almtime) {
          lastalmtime_$d = localStorage.getItem('lastalmtime_$d');                             // letzte Alarmzeit laden   
          if ( acttime == almtime && acttime != lastalmtime_$d ) {
              command = '{ CommandSetReading(undef, "$d alarmed '+acttime+'") }';
              url_$d  = makeCommand(command);
              
              localStoreSetLastalm_$d (dev, acttime);                                          // aktuelle Alarmzeit sichern 
              
              if(acttime == almtime) {
                 \$.get(url_$d);
            
              } else {
                  \$.get(url_$d, function (data) {
                                     command = '{ CommandSetReading(undef, "$d state stopped") }';
                                     url_$d  = makeCommand(command);
                                     \$.get(url_$d);
                                }
                        );                                       
              }
          }
      }

      function StationClock_$d(clockId_$d) {
          this.clockId_$d = clockId_$d; 
          this.radius     = 0;

          // hour offset
          this.hourOffset = 0;
          
          // clock body
          this.body              = StationClock_$d.RoundBody;
          this.bodyShadowColor   = 'rgba(0,0,0,0.5)';
          this.bodyShadowOffsetX = 0.03;
          this.bodyShadowOffsetY = 0.03;
          this.bodyShadowBlur    = 0.06;
          
          // body dial
          this.dial              = StationClock_$d.GermanStrokeDial;
          this.dialColor         = 'rgb(60,60,60)';
          
          // clock hands
          this.hourHand          = StationClock_$d.PointedHourHand;
          this.minuteHand        = StationClock_$d.PointedMinuteHand;
          this.secondHand        = StationClock_$d.HoleShapedSecondHand;
          this.handShadowColor   = 'rgba(0,0,0,0.3)';
          this.handShadowOffsetX = 0.03;
          this.handShadowOffsetY = 0.03;
          this.handShadowBlur    = 0.04;
            
          // clock colors
          this.hourHandColor     = 'rgb(0,0,0)';
          this.minuteHandColor   = 'rgb(0,0,0)';
          this.secondHandColor   = 'rgb(200,0,0)';
          
          // clock boss
          this.boss              = StationClock_$d.NoBoss;
          this.bossShadowColor   = 'rgba(0,0,0,0.2)';
          this.bossShadowOffsetX = 0.02;
          this.bossShadowOffsetY = 0.02;
          this.bossShadowBlur    = 0.03;
          
          // hand behavoir
          this.minuteHandBehavoir = StationClock_$d.CreepingMinuteHand;
          this.secondHandBehavoir = StationClock_$d.OverhastySecondHand;
          
          // hand animation
          this.minuteHandAnimationStep = 0;
          this.secondHandAnimationStep = 0;
          this.lastMinute              = 0;
          this.lastSecond              = 0;
      };

      StationClock_$d.prototype.draw = function() {
          var clock_$d = document.getElementById(this.clockId_$d);
          
          if (clock_$d) {
              var context = clock_$d.getContext('2d');
              if (context) {
                  this.radius = 0.75 * (Math.min(clock_$d.width, clock_$d.height) / 2);
          
                  // clear canvas and set new origin
                  context.clearRect(0, 0, clock_$d.width, clock_$d.height);
                  context.save();
                  context.translate(clock_$d.width / 2, clock_$d.height / 2);
                  
                  // draw body
                  if (this.body != StationClock_$d.NoStrokeBody) {
                      context.save();
                      switch (this.body) {
                          case StationClock_$d.SmallWhiteBody:
                            this.fillCircle(context, 'rgb(255,255,255)', 0, 0, 1);
                            break;
                          case StationClock_$d.RoundBody:
                            this.fillCircle(context, 'rgb(255,255,255)', 0, 0, 1.1);
                            context.save();
                            this.setShadow(context, this.bodyShadowColor, this.bodyShadowOffsetX, this.bodyShadowOffsetY, this.bodyShadowBlur);
                            this.strokeCircle(context, 'rgb(0,0,0)', 0, 0, 1.1, 0.07);
                            context.restore();
                            break;
                          case StationClock_$d.RoundGreenBody:
                            this.fillCircle(context, 'rgb(235,236,212)', 0, 0, 1.1);
                            context.save();
                            this.setShadow(context, this.bodyShadowColor, this.bodyShadowOffsetX, this.bodyShadowOffsetY, this.bodyShadowBlur);
                            this.strokeCircle(context, 'rgb(180,180,180)', 0, 0, 1.1, 0.2);
                            context.restore();
                            this.strokeCircle(context, 'rgb(29,84,31)', 0, 0, 1.15, 0.1);
                            context.save();
                            this.setShadow(context, 'rgba(235,236,212,100)', -0.02, -0.02, 0.09);
                            this.strokeCircle(context, 'rgb(76,128,110)', 0, 0, 1.1, 0.08);
                            context.restore();
                            break;
                          case StationClock_$d.SquareBody:
                            context.save();
                            this.setShadow(context, this.bodyShadowColor, this.bodyShadowOffsetX, this.bodyShadowOffsetY, this.bodyShadowBlur);
                            this.fillSquare(context, 'rgb(237,235,226)', 0, 0, 2.4);
                            this.strokeSquare(context, 'rgb(38,106,186)', 0, 0, 2.32, 0.16);
                            context.restore();
                            context.save();
                            this.setShadow(context, this.bodyShadowColor, this.bodyShadowOffsetX, this.bodyShadowOffsetY, this.bodyShadowBlur);
                            this.strokeSquare(context, 'rgb(42,119,208)', 0, 0, 2.24, 0.08);
                            context.restore();
                            break;
                          case StationClock_$d.ViennaBody:
                            context.save();
                            this.fillSymmetricPolygon(context, 'rgb(156,156,156)', [[-1.2,1.2],[-1.2,-1.2]],0.1);
                            this.fillPolygon(context, 'rgb(156,156,156)', 0,1.2 , 1.2,1.2 , 1.2,0);
                            this.fillCircle(context, 'rgb(255,255,255)', 0, 0, 1.05, 0.08);
                            this.strokeCircle(context, 'rgb(0,0,0)', 0, 0, 1.05, 0.01);
                            this.strokeCircle(context, 'rgb(100,100,100)', 0, 0, 1.1, 0.01);
                            this.fillPolygon(context, 'rgb(100,100,100)', 0.45,1.2 , 1.2,1.2 , 1.2,0.45);
                            this.fillPolygon(context, 'rgb(170,170,170)', 0.45,-1.2 , 1.2,-1.2 , 1.2,-0.45);
                            this.fillPolygon(context, 'rgb(120,120,120)', -0.45,1.2 , -1.2,1.2 , -1.2,0.45);
                            this.fillPolygon(context, 'rgb(200,200,200)', -0.45,-1.2 , -1.2,-1.2 , -1.2,-0.45);
                            this.strokeSymmetricPolygon(context, 'rgb(156,156,156)', [[-1.2,1.2],[-1.2,-1.2]],0.01);
                            this.fillPolygon(context, 'rgb(255,0,0)', 0.05,-0.6 , 0.15,-0.6 , 0.15,-0.45 , 0.05,-0.45);
                            this.fillPolygon(context, 'rgb(255,0,0)', -0.05,-0.6 , -0.15,-0.6 , -0.15,-0.45 , -0.05,-0.45);
                            this.fillPolygon(context, 'rgb(255,0,0)', 0.05,-0.35 , 0.15,-0.35 , 0.15,-0.30 ,  0.10,-0.20 , 0.05,-0.20);
                            this.fillPolygon(context, 'rgb(255,0,0)', -0.05,-0.35 , -0.15,-0.35 , -0.15,-0.30 ,  -0.10,-0.20 , -0.05,-0.20);
                            context.restore();
                            break;
                      }
                      context.restore();
                  }
                  
                  // draw dial
                  for (var i = 0; i < 60; i++) {
                      context.save();
                      context.rotate(i * Math.PI / 30);
                      switch (this.dial) {
                          case StationClock_$d.SwissStrokeDial:
                          if ((i % 5) == 0) {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.75, 0.07);
                          } else {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.92, 0.026);
                          }
                          break;
                          case StationClock_$d.AustriaStrokeDial:
                          if ((i % 5) == 0) {
                              this.fillPolygon(context, this.dialColor, -0.04, -1.0, 0.04, -1.0, 0.03, -0.78, -0.03, -0.78);
                          } else {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.94, 0.02);
                          }
                          break;
                          case StationClock_$d.GermanStrokeDial:
                          if ((i % 15) == 0) {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.70, 0.08);
                          } else if ((i % 5) == 0) {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.76, 0.08);
                          } else {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.92, 0.036);
                          }
                          break;
                          case StationClock_$d.GermanHourStrokeDial:
                          if ((i % 15) == 0) {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.70, 0.10);
                          } else if ((i % 5) == 0) {
                              this.strokeLine(context, this.dialColor, 0.0, -1.0, 0.0, -0.74, 0.08);
                          }
                          break;
                          case StationClock_$d.ViennaStrokeDial:
                          if ((i % 15) == 0) {
                              this.fillPolygon(context, this.dialColor, 0.7,-0.1, 0.6,0, 0.7,0.1,  1,0.03,  1,-0.03);
                          } else if ((i % 5) == 0) {
                              this.fillPolygon(context, this.dialColor, 0.85,-0.06, 0.78,0, 0.85,0.06,  1,0.03,  1,-0.03);
                          }
                          this.fillCircle(context, this.dialColor, 0.0, -1.0, 0.03);
                          break;
                      }
                      context.restore();
                  }
                  
                  var cycletime    = new Date();
                  var cycleseconds = cycletime.getSeconds();
                  modulo2_$d       = cycleseconds % 2;                                       // Taktung für Readingabruf (Serverauslastung reduzieren)

                  if (modulo2_$d != zmodulo_$d) {
                      command = '{ReadingsVal("$d","alarmTime","+almtime0_$d+")}';           // alarmTime Reading lesen
                      url_$d  = makeCommand(command);
                      \$.get( url_$d, function (data) {
                                          almtime0_$d = data.replace(/\\n/g, '');
                                          zmodulo_$d = modulo2_$d;  
                                          return (almtime0_$d, zmodulo_$d);
                                      } 
                            );
                  }
                
                  // Zeitsteuerung
                  if ('$tsou' == 'server') {                   // Serverzeit
                      // aktueller Timestamp in Millisekunden 
                      command = '{ int(time*1000) }';
                      url_$d  = makeCommand(command);
                      \$.get( url_$d, function (data) {
                                          data = data.replace(/\\n/g, ''); 
                                          ct_$d = parseInt(data); 
                                          return ct_$d;
                                      } 
                            ); 
                      
                      time_$d  = new Date(ct_$d);
                      
                  } else {
                      time_$d  = new Date();                   // Clientzeit
                  }
                  
                  if (typeof ct_$d === 'undefined') {          // wenn Zeit noch undef mit lokaler Zeit initialisieren -> springen Zeiger verhindern
                      time_$d  = new Date();                   
                  } else {
                      time_$d  = new Date(ct_$d);
                  }

                  var millis_$d  = time_$d.getMilliseconds() / 1000.0;
                  var seconds_$d = time_$d.getSeconds();
                  var minutes_$d = time_$d.getMinutes();
                  var hours_$d   = time_$d.getHours() + this.hourOffset;
                  
                  acttime_$d = ((hours_$d   < 10) ? '0' : '') + hours_$d   + ':' + 
                               ((minutes_$d < 10) ? '0' : '') + minutes_$d + ':' + 
                               ((seconds_$d < 10) ? '0' : '') + seconds_$d;
                               
                  if (acttime_$d == '00:00:00') {
                      localStoreSetLastalm_$d ('$d', 'NaN');               // letzte Alarmzeit zurücksetzen zum Tageswechsel            
                  }

                  checkAndDoAlm_$d ('$d', acttime_$d, almtime0_$d);                 

                  // draw hour hand
                  context.save();
                  context.rotate(hours_$d * Math.PI / 6 + minutes_$d * Math.PI / 360);
                  this.setShadow(context, this.handShadowColor, this.handShadowOffsetX, this.handShadowOffsetY, this.handShadowBlur);
                  switch (this.hourHand) {
                    case StationClock_$d.BarHourHand:
                      this.fillPolygon(context, this.hourHandColor, -0.05, -0.6, 0.05, -0.6, 0.05, 0.15, -0.05, 0.15);
                      break;
                    case StationClock_$d.PointedHourHand:
                      this.fillPolygon(context, this.hourHandColor, 0.0, -0.6,  0.065, -0.53, 0.065, 0.19, -0.065, 0.19, -0.065, -0.53);
                      break;
                    case StationClock_$d.SwissHourHand:
                      this.fillPolygon(context, this.hourHandColor, -0.05, -0.6, 0.05, -0.6, 0.065, 0.26, -0.065, 0.26);
                      break;
                    case StationClock_$d.ViennaHourHand:
                      this.fillSymmetricPolygon(context, this.hourHandColor, [[-0.02,-0.72],[-0.08,-0.56],[-0.15,-0.45],[-0.06,-0.30],[-0.03,0],[-0.1,0.2],[-0.05,0.23],[-0.03,0.2]]);
                  }
                  context.restore();
                  
                  // draw minute hand
                  context.save();
                  switch (this.minuteHandBehavoir) {
                    case StationClock_$d.CreepingMinuteHand:
                      context.rotate((minutes_$d + seconds_$d / 60) * Math.PI / 30);
                      break;
                    case StationClock_$d.BouncingMinuteHand:
                      context.rotate(minutes_$d * Math.PI / 30);
                      break;
                    case StationClock_$d.ElasticBouncingMinuteHand:
                      if (this.lastMinute != minutes_$d) {
                          this.minuteHandAnimationStep = 3;
                          this.lastMinute = minutes_$d;
                      }
                      context.rotate((minutes_$d + this.getAnimationOffset(this.minuteHandAnimationStep)) * Math.PI / 30);
                      this.minuteHandAnimationStep--;
                      break;
                  }
                  this.setShadow(context, this.handShadowColor, this.handShadowOffsetX, this.handShadowOffsetY, this.handShadowBlur);
                  switch (this.minuteHand) {
                    case StationClock_$d.BarMinuteHand:
                      this.fillPolygon(context, this.minuteHandColor, -0.05, -0.9, 0.035, -0.9, 0.035, 0.23, -0.05, 0.23);
                      break;
                    case StationClock_$d.PointedMinuteHand:
                      this.fillPolygon(context, this.minuteHandColor, 0.0, -0.93,  0.045, -0.885, 0.045, 0.23, -0.045, 0.23, -0.045, -0.885);
                      break;
                    case StationClock_$d.SwissMinuteHand:
                      this.fillPolygon(context, this.minuteHandColor, -0.035, -0.93, 0.035, -0.93, 0.05, 0.25, -0.05, 0.25);
                      break;
                    case StationClock_$d.ViennaMinuteHand:
                      this.fillSymmetricPolygon(context, this.minuteHandColor, [[-0.02,-0.98],[-0.09,-0.7],[-0.03,0],[-0.05,0.2],[-0.01,0.4]]);
                  }
                  context.restore();
                  
                  // draw second hand
                  context.save();
                  switch (this.secondHandBehavoir) {
                    case StationClock_$d.OverhastySecondHand:
                      context.rotate(Math.min((seconds_$d + millis_$d) * (60.0 / 58.5), 60.0) * Math.PI / 30);
                      break;
                    case StationClock_$d.CreepingSecondHand:
                      context.rotate((seconds_$d + millis_$d) * Math.PI / 30);
                      break;
                    case StationClock_$d.BouncingSecondHand:
                      context.rotate(seconds_$d * Math.PI / 30);
                      break;
                    case StationClock_$d.ElasticBouncingSecondHand:
                      if (this.lastSecond != seconds_$d) {
                          this.secondHandAnimationStep = 3;
                          this.lastSecond = seconds_$d;
                      }
                      context.rotate((seconds_$d + this.getAnimationOffset(this.secondHandAnimationStep)) * Math.PI / 30);
                      this.secondHandAnimationStep--;
                      break;
                  }
                  this.setShadow(context, this.handShadowColor, this.handShadowOffsetX, this.handShadowOffsetY, this.handShadowBlur);
                  switch (this.secondHand) {
                    case StationClock_$d.BarSecondHand:
                      this.fillPolygon(context, this.secondHandColor, -0.006, -0.92, 0.006, -0.92, 0.028, 0.23, -0.028, 0.23);
                      break;
                    case StationClock_$d.HoleShapedSecondHand:
                      this.fillPolygon(context, this.secondHandColor, 0.0, -0.9, 0.011, -0.889, 0.01875, -0.6, -0.01875, -0.6, -0.011, -0.889);
                      this.fillPolygon(context, this.secondHandColor, 0.02, -0.4, 0.025, 0.22, -0.025, 0.22, -0.02, -0.4);
                      this.strokeCircle(context, this.secondHandColor, 0, -0.5, 0.083, 0.066);
                      break;
                    case StationClock_$d.NewHoleShapedSecondHand:
                      this.fillPolygon(context, this.secondHandColor, 0.0, -0.95, 0.015, -0.935, 0.0187, -0.65, -0.0187, -0.65, -0.015, -0.935);
                      this.fillPolygon(context, this.secondHandColor, 0.022, -0.45, 0.03, 0.27, -0.03, 0.27, -0.022, -0.45);
                      this.strokeCircle(context, this.secondHandColor, 0, -0.55, 0.085, 0.07);
                      break;
                    case StationClock_$d.SwissSecondHand:
                      this.strokeLine(context, this.secondHandColor, 0.0, -0.6, 0.0, 0.35, 0.026);
                      this.fillCircle(context, this.secondHandColor, 0, -0.64, 0.1);
                      break;
                    case StationClock_$d.ViennaSecondHand:
                      this.strokeLine(context, this.secondHandColor, 0.0, -0.6, 0.0, 0.35, 0.026);
                      this.fillCircle(context, this.secondHandColor, 0, -0.64, 0.1);
                      break;
                  }
                  context.restore();
                  
                  // draw clock boss
                  if (this.boss != StationClock_$d.NoBoss) {
                      context.save();
                      this.setShadow(context, this.bossShadowColor, this.bossShadowOffsetX, this.bossShadowOffsetY, this.bossShadowBlur);
                      switch (this.boss) {
                          case StationClock_$d.BlackBoss:
                            this.fillCircle(context, 'rgb(0,0,0)', 0, 0, 0.1);
                            break;
                          case StationClock_$d.RedBoss:
                            this.fillCircle(context, 'rgb(220,0,0)', 0, 0, 0.06);
                            break;
                          case StationClock_$d.ViennaBoss:
                            this.fillCircle(context, 'rgb(0,0,0)', 0, 0, 0.07);
                            break;
                      }
                      context.restore();
                  }
                  context.restore();
              }
          }
      };

      StationClock_$d.prototype.getAnimationOffset = function(animationStep) {
          switch (animationStep) {
            case 3: return  0.2;
            case 2: return -0.1;
            case 1: return  0.05;
          }
      return 0;
      };

      StationClock_$d.prototype.setShadow = function(context, color, offsetX, offsetY, blur) {
          if (color) {
              context.shadowColor   = color;
              context.shadowOffsetX = this.radius * offsetX;
              context.shadowOffsetY = this.radius * offsetY;
              context.shadowBlur    = this.radius * blur;
          }
      };

      StationClock_$d.prototype.fillCircle = function(context, color, x, y, radius) {
          if (color) {
              context.beginPath();
              context.fillStyle = color;
              context.arc(x * this.radius, y * this.radius, radius * this.radius, 0, 2 * Math.PI, true);
              context.fill();
          }
      };

      StationClock_$d.prototype.strokeCircle = function(context, color, x, y, radius, lineWidth) {
          if (color) {
              context.beginPath();
              context.strokeStyle = color;
              context.lineWidth = lineWidth * this.radius;
              context.arc(x * this.radius, y * this.radius, radius * this.radius, 0, 2 * Math.PI, true);
              context.stroke();
          }
      };

      StationClock_$d.prototype.fillSquare = function(context, color, x, y, size) {
          if (color) {
              context.fillStyle = color;
              context.fillRect((x - size / 2) * this.radius, (y -size / 2) * this.radius, size * this.radius, size * this.radius);
          }
      };

      StationClock_$d.prototype.strokeSquare = function(context, color, x, y, size, lineWidth) {
          if (color) {
              context.strokeStyle = color;
              context.lineWidth = lineWidth * this.radius;
              context.strokeRect((x - size / 2) * this.radius, (y -size / 2) * this.radius, size * this.radius, size * this.radius);
          }
      };

      StationClock_$d.prototype.strokeLine = function(context, color, x1, y1, x2, y2, width) {
          if (color) {
              context.beginPath();
              context.strokeStyle = color;
              context.moveTo(x1 * this.radius, y1 * this.radius);
              context.lineTo(x2 * this.radius, y2 * this.radius);
              context.lineWidth = width * this.radius;
              context.stroke();
          }
      };

      StationClock_$d.prototype.fillPolygon = function(context, color, x1, y1, x2, y2, x3, y3, x4, y4, x5, y5) {
          if (color) {
              context.beginPath();
              context.fillStyle = color;
              context.moveTo(x1 * this.radius, y1 * this.radius);
              context.lineTo(x2 * this.radius, y2 * this.radius);
              context.lineTo(x3 * this.radius, y3 * this.radius);
              context.lineTo(x4 * this.radius, y4 * this.radius);
              if ((x5 != undefined) && (y5 != undefined)) {
                 context.lineTo(x5 * this.radius, y5 * this.radius);
              }
              context.lineTo(x1 * this.radius, y1 * this.radius);
              context.fill();
          }
      };

      StationClock_$d.prototype.fillSymmetricPolygon = function(context, color, points) {
          context.beginPath();
          context.fillStyle = color;
          context.moveTo(points[0][0] * this.radius, points[0][1] * this.radius);
          for (var i = 1; i < points.length; i++) {
              context.lineTo(points[i][0] * this.radius, points[i][1] * this.radius);
          }
          for (var i = points.length - 1; i >= 0; i--) {
              context.lineTo(0 - points[i][0] * this.radius, points[i][1] * this.radius);
          }
          context.lineTo(points[0][0] * this.radius, points[0][1] * this.radius);
          context.fill();
      };

      StationClock_$d.prototype.strokeSymmetricPolygon = function(context, color, points, width) {
          context.beginPath();
          context.strokeStyle = color;
          context.moveTo(points[0][0] * this.radius, points[0][1] * this.radius);
          for (var i = 1; i < points.length; i++) {
              context.lineTo(points[i][0] * this.radius, points[i][1] * this.radius);
          }
          for (var i = points.length - 1; i >= 0; i--) {
              context.lineTo(0 - points[i][0] * this.radius, points[i][1] * this.radius);
          }
          context.lineTo(points[0][0] * this.radius, points[0][1] * this.radius);
          context.lineWidth = width * this.radius;
          context.stroke();
      };
        
      var clock_$d                = new StationClock_$d('clock_$d');
      clock_$d.body               = StationClock_$d.$sbody;
      clock_$d.dial               = StationClock_$d.$ssd;
      clock_$d.hourHand           = StationClock_$d.$shh;
      clock_$d.minuteHand         = StationClock_$d.$smh;
      clock_$d.secondHand         = StationClock_$d.$ssh;
      clock_$d.boss               = StationClock_$d.$sb;
      clock_$d.minuteHandBehavoir = StationClock_$d.$mhb;
      clock_$d.secondHandBehavoir = StationClock_$d.$shb;

      function animate(clock_$d) {
          clock_$d.draw();
          // window.setTimeout(function(){animate(clock_$d)}, 50);     // alte Variante
          window.setTimeout(function(){animate(clock_$d)}, 100);
      }

      animate(clock_$d);   
      </script>
      
      </body>
      </html>      

END_JS

return qq{$back};
}

##############################################################################
#                            Moderne Uhr aus:
#         https://www.w3schools.com/graphics/canvas_clock_start.asp
#
##############################################################################
sub modernWatch {
  my ($d)    = @_;
  my $hash   = $defs{$d};
  my $facec  = AttrVal($d, "modernColorFace",       "FFFEFA");
  my $bgc    = AttrVal($d, "modernColorBackground", "333");
  my $fc     = AttrVal($d, "modernColorFigure",     "333");
  my $hc     = AttrVal($d, "modernColorHand",       "333");
  my $fr     = AttrVal($d, "modernColorRing",       "FFFFFF");
  my $fre    = AttrVal($d, "modernColorRingEdge",   "333");
  my $hattr  = AttrVal($d, "htmlattr",              "width='150' height='150'");
  my $tsou   = AttrVal($d, "timeSource",            "client");

  my $alarm  = ReadingsVal($d, "alarmTime", "aa:bb:cc");  

  my $back = << "END_JS";
      <html>
      <body>

      <canvas id='canvas_$d' $hattr style='background-color:#$bgc'>
      </canvas>

      <script>
      
      var ct_$d;
      var almtime0_$d = '$alarm';
      var zmodulo_$d  = 0;                              // Hilfszähler 
      
      // CSRF-Token auslesen
      var body = document.querySelector("body");
      if( body != null ) {
          csrf = body.getAttribute("fwcsrf");
      }
 
      // get the base url
      function getBaseUrl () {
          var url = window.location.href.split("?")[0];
          url += "?";
          if( csrf != null ) {
              url += "fwcsrf="+csrf+"&";
          }
          return url;
      }

      function makeCommand (cmd) {
          return getBaseUrl()+"cmd="+encodeURIComponent(cmd)+"&XHR=1";
      }
      
      // localStorage speichern letzte Alarmzeit
      function localStoreSetLastalm_$d (dev, lastalmtime) {
          localStorage.setItem('lastalmtime_'+dev, lastalmtime);
      }
    
      // Check ob Alarm ausgelöst werden soll und ggf. Alarmevent triggern
      function checkAndDoAlm_$d (dev, acttime, almtime) {
          lastalmtime_$d = localStorage.getItem('lastalmtime_$d');                             // letzte Alarmzeit laden   
          if ( acttime == almtime && acttime != lastalmtime_$d ) {
              command = '{ CommandSetReading(undef, "$d alarmed '+acttime+'") }';
              url_$d  = makeCommand(command);
              
              localStoreSetLastalm_$d (dev, acttime);                                        // aktuelle Alarmzeit sichern 
              
              if(acttime == almtime) {
                 \$.get(url_$d);
            
              } else {
                  \$.get(url_$d, function (data) {
                                     command = '{ CommandSetReading(undef, "$d state stopped") }';
                                     url_$d  = makeCommand(command);
                                     \$.get(url_$d);
                                }
                        );                                       
              }
          }
      }     
      
      var canvas_$d = document.getElementById('canvas_$d');
      var ctx_$d    = canvas_$d.getContext('2d');
      var radius_$d = canvas_$d.height / 2;
      
      ctx_$d.translate(radius_$d, radius_$d);
      radius_$d = radius_$d * 0.90
      // setInterval(drawClock_$d, 1000);                // alte Variante
      setInterval(drawClock_$d, 100);

      function drawClock_$d() {
          drawFace_$d    (ctx_$d, radius_$d);
          drawnumbers_$d (ctx_$d, radius_$d);
          drawTime_$d    (ctx_$d, radius_$d);
      }

      function drawFace_$d(ctx_$d, radius_$d) {
          var grad_$d;
          ctx_$d.beginPath();
          ctx_$d.arc(0, 0, radius_$d, 0, 2*Math.PI);
          ctx_$d.fillStyle = '#$facec';                    // Füllung Uhr
          ctx_$d.fill();
          grad_$d = ctx_$d.createRadialGradient(0,0,radius_$d*0.95, 0,0,radius_$d*1.05);
          grad_$d.addColorStop(0, '#$hc');                // Farbe Zeiger und innere Ringgrenze
          grad_$d.addColorStop(0.5, '#$fr');              // Farbe Ziffernblattring
          grad_$d.addColorStop(1, '#$fre');               // Farbe äußere Ringgrenze
          ctx_$d.strokeStyle = grad_$d;
          ctx_$d.lineWidth   = radius_$d*0.1;
          ctx_$d.stroke();
          ctx_$d.beginPath();
          ctx_$d.arc(0, 0, radius_$d*0.1, 0, 2*Math.PI);
          ctx_$d.fillStyle = '#$fc';                      // Farbe Ziffern und Zeigerwelle
          ctx_$d.fill();
      }

      function drawnumbers_$d(ctx_$d, radius_$d) {
          var ang_$d;
          var num_$d;
          ctx_$d.font         = radius_$d*0.15 + 'px arial';
          ctx_$d.textBaseline ='middle';
          ctx_$d.textAlign    ='center';
          
          for(num_$d = 1; num_$d < 13; num_$d++){
              ang_$d = num_$d * Math.PI / 6;
              ctx_$d.rotate(ang_$d);
              ctx_$d.translate(0, -radius_$d*0.85);
              ctx_$d.rotate(-ang_$d);
              ctx_$d.fillText(num_$d.toString(), 0, 0);
              ctx_$d.rotate(ang_$d);
              ctx_$d.translate(0, radius_$d*0.85);
              ctx_$d.rotate(-ang_$d);
          }
      }

      function drawTime_$d(ctx_$d, radius_$d){
          var cycletime    = new Date();
          var cycleseconds = cycletime.getSeconds();
          modulo2_$d       = cycleseconds % 2;                                       // Taktung für Readingabruf (Serverauslastung reduzieren)

          if (modulo2_$d != zmodulo_$d) {
              command = '{ReadingsVal("$d","alarmTime","+almtime0_$d+")}';     // alarmTime Reading lesen
              url_$d  = makeCommand(command);
              \$.get( url_$d, function (data) {
                                  almtime0_$d = data.replace(/\\n/g, '');
                                  zmodulo_$d = modulo2_$d;  
                                  return (almtime0_$d, zmodulo_$d);
                              } 
                    );
          }
          // Zeitsteuerung
          if ('$tsou' == 'server') {                   // Serverzeit
              // aktueller Timestamp in Millisekunden 
              command = '{ int(time*1000) }';
              url_$d  = makeCommand(command);
              \$.get( url_$d, function (data) {
                                  data = data.replace(/\\n/g, ''); 
                                  ct_$d = parseInt(data); 
                                  return ct_$d;
                              } 
                    ); 
              
              time_$d  = new Date(ct_$d);
              
          } else {
              time_$d  = new Date();                   // Clientzeit
          }
          
          if (typeof ct_$d === 'undefined') {          // wenn Zeit noch undef mit lokaler Zeit initialisieren -> springen Zeiger verhindern
              time_$d  = new Date();                   
          } else {
              time_$d  = new Date(ct_$d);
          }
          
          var hour_$d   = time_$d.getHours();
          var minute_$d = time_$d.getMinutes();
          var second_$d = time_$d.getSeconds();
          
          acttime_$d = ((hour_$d   < 10) ? '0' : '') + hour_$d   + ':' + 
                       ((minute_$d < 10) ? '0' : '') + minute_$d + ':' + 
                       ((second_$d < 10) ? '0' : '') + second_$d;
                       
          if (acttime_$d == '00:00:00') {
              localStoreSetLastalm_$d ('$d', 'NaN');               // letzte Alarmzeit zurücksetzen zum Tageswechsel            
          }

          checkAndDoAlm_$d ('$d', acttime_$d, almtime0_$d);
          
          //hour_$d
          hour_$d = hour_$d%12;
          hour_$d = (hour_$d*Math.PI/6)+
                    (minute_$d*Math.PI/(6*60))+
                    (second_$d*Math.PI/(360*60));
          drawHand_$d(ctx_$d, hour_$d, radius_$d*0.5, radius_$d*0.07);
          
          //minute_$d
          minute_$d = (minute_$d*Math.PI/30)+(second_$d*Math.PI/(30*60));
          drawHand_$d(ctx_$d, minute_$d, radius_$d*0.8, radius_$d*0.07);
          
          // second_$d
          second_$d = (second_$d*Math.PI/30);
          drawHand_$d(ctx_$d, second_$d, radius_$d*0.9, radius_$d*0.02);
      }

      function drawHand_$d(ctx_$d, pos, length, width) {
          ctx_$d.beginPath();
          ctx_$d.lineWidth  = width;
          ctx_$d.lineCap    = 'round';
          ctx_$d.moveTo(0,0);
          ctx_$d.rotate(pos);
          ctx_$d.lineTo(0, -length);
          ctx_$d.stroke();
          ctx_$d.rotate(-pos);
      }
      </script>

      </body>
      </html>
      
END_JS

return qq{$back};
}

##############################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#
##############################################################################
sub setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
      # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                         # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
      if($modules{$type}{META}{x_version}) {                                                                             
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                                                
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );        ## no critic 'VERSION'                                      
      }
  } else {
      # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

1;

=pod
=item helper
=item summary    Clock display in different variants
=item summary_DE Uhrenanzeige in verschiedenen Varianten

=begin html

<a name="Watches"></a>
<h3>Watches</h3>

<br>
The module Watches provides watches in different styles as Device. 
The user can influence the design of the watches via attributes. <br>
The clocks are based on scripts of these pages: <br>

<a href='https://www.w3schools.com/graphics/canvas_clock_start.asp'>modern watch</a>, 
<a href='http://www.3quarks.com/de/Bahnhofsuhr/'>Station clock</a>, 
<a href='http://www.3quarks.com/de/Segmentanzeige/'>Digital display</a> 
<br><br>

A device of the model <b>Digital</b> can also be used as stopwatch, countdown timer or
universal text display (for sixteen segment mode see attribute <a href="#digitalSegmentType">digitalSegmentType</a>). <br>
As time source the client (browser time) as well as the FHEM server can be set 
(attribute <a href="#timeSource">timeSource</a>). <br>

<ul>
  <a name="WatchesDefine"></a>
  <b>Define</b>
  
  <ul>
    define &lt;name&gt; Watches [Modern | Station | Digital]  
    <br><br>
    
  <table>  
     <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> <b>Modern</b>     </td><td>: creates an analog clock with a modern design </td></tr>
     <tr><td> <b>Station</b>    </td><td>: creates a station clock </td></tr>
     <tr><td> <b>Digital</b>    </td><td>: creates a digital display (clock, (CountDown)stop watch, static time display or text) </td></tr>
  </table>
  <br>
  <br>
  </ul>

  <a name="WatchesSet"></a>
  <b>Set</b> 
  
  <ul>
  <ul>
  
    <a name="alarmSet"></a>
    <li><b>alarmSet &lt;hh&gt; &lt;mm&gt; &lt;ss&gt; </b><br>
      Sets the alarm time in the format hh hours, mm minutes and ss seconds. <br>
      If the time reaches the defined value, an event of the reading "alarmed" is triggered. <br>
      This set command is only available for digital stopwatches. <br><br>
      
      <ul>
      <b>Example</b> <br>
      set &lt;name&gt; alarmSet 0 30 10
      </ul>
      <br>
      
    </li>
    <br>
    
    <a name="alarmDel"></a>
    <li><b>alarmDel</b><br>
      Clears the set alarm time and its status. <br>
      This set command is only available for digital stopwatches. <br>
    </li>
    <br>
    
    <a name="countDownInit"></a>
    <li><b>countDownInit &lt;hh&gt; &lt;mm&gt; &lt;ss&gt; | &lt;seconds&gt; </b><br>
      Sets the start time of a countdown stopwatch.
      The format can be &lt;hh&gt; hours, &lt;mm&gt; minutes and &lt;ss&gt; seconds or alternatively only one entry in seconds. <br>
      This set command is only available with a digital countdown stopwatch. <br><br>
      
      <ul>
      <b>Examples</b> <br>
      set &lt;name&gt; countDownInit 0 30 10 <br>
      set &lt;name&gt; countDownInit 3600
      </ul>
      <br>
      
    </li>
    <br>
    
    <a name="displayTextSet"></a>
    <li><b>displayTextSet</b><br>
      Sets the text to be displayed. <br> 
      This set command is only available for a digital segment display with "digitalDisplayPattern = text". <br>
      (default: blank display) <br><br>
      
      <b>Note:</b> <br>
      The displayable characters depend on the attribute "digitalSegmentType". <br>
      With the (default) seven-segment display, only numbers, hyphen, underscore and the letters 
      A, b, C, d, E, F, H, L, n, o, P, r, t, U and Y are displayed. 
      In addition to numbers, short texts such as "Error", "HELP", "run" or "PLAY" can also be displayed. <br>
      For text display it is recommended to set the sixteen segment display with the attribute "digitalSegmentType" ! 
    </li>
    <br>
    
    <a name="displayTextDel"></a>
    <li><b>displayTextDel</b><br>
      Deletes the display text. <br>
      This set command is only available for a digital segment display with "digitalDisplayPattern = text". <br>
    </li>
    <br>
    
    <a name="reset"></a>
    <li><b>reset</b><br>
      Stops the stopwatch (if running) and clears all specific readings or resets it to initialized. <br>
      This set command is only available for digital stopwatches. <br>
    </li>
    <br>
    
    <a name="resume"></a>
    <li><b>resume</b><br>
      Resumes counting a stopped stopwatch. <br>
      This set command is only available for digital stopwatches. <br>
    </li>
    <br>
    
    <a name="start"></a>
    <li><b>start</b><br>
      Starts the stopwatch. <br>
      This set command is only available for digital stopwatches. <br>
    </li>
    <br>  
    
    <a name="stop"></a>
    <li><b>stop</b><br>
      Stop the stopwatch. The achieved time is retained. <br>
      This set command is only available for digital stopwatches. <br>
    </li>
    <br>
    
    <a name="textTicker"></a>
    <li><b>textTicker on | off </b><br>
      Switches the ticker mode of a text display (see attribute digitalDisplayPattern) on or off. <br>
      (default: off)      
    </li>
    <br>
    
    <a name="time"></a>
    <li><b>time &lt;hh&gt; &lt;mm&gt; &lt;ss&gt; </b><br>
      Sets a static time display with hh hours, mm minutes and ss seconds. <br>
      This set command is only available for a digital clock with static time display. <br><br>
      
      <ul>
      <b>Example</b> <br>
      set &lt;name&gt; time 8 15 3
      </ul>
      
    </li>
    <br>
  
  </ul>
  </ul>
  <br>

  <a name="WatchesGet"></a>
  <b>Get</b> 
  
  <ul>
  
    N/A
    
  </ul>
  <br>

  <a name="WatchesAttr"></a>
  <b>Attribute</b>
  <br><br>
  
  <ul>
  <ul>
  
    <a name="disable"></a>
    <li><b>disable</b><br>
      Activates/deactivates the Device.
    </li>
    <br>
    
    <a name="hideDisplayName"></a>
    <li><b>hideDisplayName</b><br>
      Hides the Device/Alias name (link to detail view).    
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      Additional HTML tags to resize the clock / display. <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; htmlattr width="125" height="125" <br>
      </ul>
    </li>
    <br>
    
    <a name="timeSource"></a>
    <li><b>timeSource</b><br>
      Selects the time source. The local client time (browser) or the FHEM server time can be displayed. <br>
      This setting is not relevant for (countdown) stopwatches. <br>
      [default: client]
    </li>
    <br>
    
  </ul>  
    
  The following attributes must be set specifically for a clock type. <br>
  <br>
   
  <b>Model: Modern</b>  <br><br>
  
  <ul>
    <a name="modernColorBackground"></a>
    <li><b>modernColorBackground</b><br>
      Background color of the clock.    
    </li>
    <br>
    
    <a name="modernColorFace"></a>
    <li><b>modernColorFace</b><br>
      Colouring of the dial.    
    </li>
    <br>
    
    <a name="modernColorFigure"></a>
    <li><b>modernColorFigure</b><br>
      Colour of the numbers on the dial and the pointer axle cover.    
    </li>
    <br>
    
    <a name="modernColorHand"></a>
    <li><b>modernColorHand</b><br>
      Colour of the watch hands.    
    </li>
    <br>
    
    <a name="modernColorRing"></a>
    <li><b>modernColorRing</b><br>
      Colour of the dial frame.    
    </li>
    <br>
    
    <a name="modernColorRingEdge"></a>
    <li><b>modernColorRingEdge</b><br>
      Colour of the outer ring of the dial frame.  
    </li>
    <br>
  </ul>
  <br>
  
  <b>Model: Station</b>  <br><br>
  
  <ul>
    <a name="stationBody"></a>
    <li><b>stationBody</b><br>
      Type of watch case.     
    </li>
    <br>
    
    <a name="stationBoss"></a>
    <li><b>stationBoss</b><br>
      Type and colour of the pointer axle cover.    
    </li>
    <br>

    <a name="stationHourHand"></a>
    <li><b>stationHourHand</b><br>
      Type of hour hand.    
    </li>
    <br>    
    
    <a name="stationMinuteHand"></a>
    <li><b>stationMinuteHand</b><br>
      Type of minute hand.    
    </li>
    <br> 

    <a name="stationMinuteHandBehavoir"></a>
    <li><b>stationMinuteHandBehavoir</b><br>
      Behavior of the minute hand.    
    </li>
    <br>   

    <a name="stationSecondHand"></a>
    <li><b>stationSecondHand</b><br>
      Type of second hand.   
    </li>
    <br>  

    <a name="stationSecondHandBehavoir"></a>
    <li><b>stationSecondHandBehavoir</b><br>
      Behavior of the second hand.    
    </li>
    <br>  

    <a name="stationStrokeDial"></a>
    <li><b>stationStrokeDial</b><br>
      Selection of the dial.    
    </li>
    <br>      
    
  </ul>
  <br>
  
  <b>Model: Digital</b>  <br><br>
  
  <ul>
    <a name="digitalBorderDistance"></a>
    <li><b>digitalBorderDistance</b><br>
      Left and right distance of the digital text display from the background edge. <br>
      (default: 8)      
    </li>
    <br>  
  
    <a name="digitalColorBackground"></a>
    <li><b>digitalColorBackground</b><br>
      Digital clock background color.    
    </li>
    <br>  

    <a name="digitalColorDigits"></a>
    <li><b>digitalColorDigits</b><br>
      Color of the bar display in a digital watch.    
    </li>
    <br> 

    <a name="digitalDigitAngle"></a>
    <li><b>digitalDigitAngle </b><br>
      Adjusts the tilt angle of the displayed characters. <br>
      (default: 9)      
    </li>
    <br> 
    
    <a name="digitalDigitDistance"></a>
    <li><b>digitalDigitDistance </b><br>
      Adjusts the character spacing. <br>
      (default: 2)     
    </li>
    <br>  
    
    <a name="digitalDigitHeight"></a>
    <li><b>digitalDigitHeight </b><br>
      Adjusts the character height. <br>
      (default: 20)      
    </li>
    <br>

    <a name="digitalDigitWidth"></a>
    <li><b>digitalDigitWidth </b><br>
      Adjusts the character width. <br>
      (default: 12)      
    </li>
    <br>     
  
    <a name="digitalDisplayPattern"></a>
    <li><b>digitalDisplayPattern [countdownwatch | staticwatch | stopwatch | text | watch]</b><br>
      Switching the digital display between a clock (default), a stopwatch, static time display or text display. 
      The text to be displayed in text display mode can be defined with <br>
      <b>set &lt;name&gt displayText</b>. <br><br>
      
      <b>Note:</b> For text display it is recommended to set the attribute "digitalSegmentType" to "16". <br><br>
      
    <ul>
    <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>countdownwatch </b> </td><td>: CountDown Stopwatch            </td></tr>
       <tr><td> <b>staticwatch</b>     </td><td>: static time display            </td></tr>
       <tr><td> <b>stopwatch</b>       </td><td>: Stopwatch                      </td></tr>
       <tr><td> <b>text</b>            </td><td>: Display of a definable text    </td></tr>
       <tr><td> <b>watch</b>           </td><td>: Watch                          </td></tr>
    </table>
    </ul>
    <br>
    <br>
    </li> 
    
    <a name="digitalSegmentDistance"></a>
    <li><b>digitalSegmentDistance </b><br>
      Defines the distance between the segments. <br>
      (default: 0.5)      
    </li>
    <br> 
    
    <a name="digitalSegmentType"></a>
    <li><b>digitalSegmentType </b><br>
      Switches the segment number of the digital display. <br>
      (default: 7)      
    </li>
    <br> 

    <a name="digitalSegmentWidth"></a>
    <li><b>digitalSegmentWidth </b><br>
      Changes the width of the individual segments. <br>
      (default: 1.5)     
    </li>
    <br> 

    <a name="digitalTextDigitNumber"></a>
    <li><b>digitalTextDigitNumber &lt;Quantity&gt; </b><br>
      If &lt;Quantity&gt > 0, the number of digits of a text display (digitalDisplayPattern = text) is fixed. 
      If &lt;Quantity&gt = 0 or not set, the setting is made automatically. In this case an adaptation is made
      of the character size to the number depending on the set display size (see htmlattr). <br>
      (default: 0)      
    </li>
    <br>      
    
  </ul>
  </ul>
  
</ul>

=end html
=begin html_DE

<a name="Watches"></a>
<h3>Watches</h3>

<br>
Das Modul Watches stellt Uhren in unterschiedlichen Stilen als Device zur Verfügung. 
Der Nutzer kann das Design der Uhren über Attribute beeinflussen. <br>
Die Uhren basieren auf Skripten dieser Seiten: <br>

<a href='https://www.w3schools.com/graphics/canvas_clock_start.asp'>moderne Uhr</a>, 
<a href='http://www.3quarks.com/de/Bahnhofsuhr/'>Bahnhofsuhr</a>, 
<a href='http://www.3quarks.com/de/Segmentanzeige/'>Digitalanzeige</a> 
<br><br>

Ein Device vom Model <b>Digital</b> kann ebenfalls als Stoppuhr, CountDown-Timer oder
universelle Textanzeige (für Sechzehnsegment-Modus siehe Attribut <a href="#digitalSegmentType">digitalSegmentType</a>) 
verwendet werden. <br>
Als Zeitquelle können sowohl der Client (Browserzeit) als auch der FHEM-Server eingestellt werden 
(Attribut <a href="#timeSource">timeSource</a>). <br>

<ul>
  <a name="WatchesDefine"></a>
  <b>Define</b>
  
  <ul>
    define &lt;name&gt; Watches [Modern | Station | Digital]  
    <br><br>
    
  <table>  
     <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> <b>Modern</b>     </td><td>: erstellt eine analoge Uhr im modernen Design </td></tr>
     <tr><td> <b>Station</b>    </td><td>: erstellt eine Bahnhofsuhr </td></tr>
     <tr><td> <b>Digital</b>    </td><td>: erstellt eine Digitalanzeige (Uhr, (CountDown)Stoppuhr, statische Zeitanzeige oder Text) </td></tr>
  </table>
  <br>
  <br>
  </ul>

  <a name="WatchesSet"></a>
  <b>Set</b> 
  
  <ul>
  <ul>
  
    <a name="alarmSet"></a>
    <li><b>alarmSet &lt;hh&gt; &lt;mm&gt; &lt;ss&gt; </b><br>
      Setzt die Alarmzeit im Format hh-Stunden, mm-Minuten und ss-Sekunden. <br>
      Erreicht die Zeit den definierten Wert, wird ein Event des Readings "alarmed" ausgelöst. <br>
      Dieses Set-Kommando ist nur bei digitalen Stoppuhren vorhanden. <br><br>
      
      <ul>
      <b>Beispiel</b> <br>
      set &lt;name&gt; alarmSet 0 30 10
      </ul>
      <br>
      
    </li>
    <br>
    
    <a name="alarmDel"></a>
    <li><b>alarmDel</b><br>
      Löscht die gesetzte Alarmzeit und deren Status. <br>
      Dieses Set-Kommando ist nur bei digitalen Stoppuhren vorhanden. <br>
    </li>
    <br>
    
    <a name="countDownInit"></a>
    <li><b>countDownInit &lt;hh&gt; &lt;mm&gt; &lt;ss&gt; | &lt;Sekunden&gt; </b><br>
      Setzt die Startzeit einer CountDown-Stoppuhr.
      Das Format kann sein &lt;hh&gt; Stunden, &lt;mm&gt; Minuten und &lt;ss&gt; Sekunden oder alternativ nur eine Angabe in Sekunden. <br>
      Dieses Set-Kommando ist nur bei einer digitalen CountDown-Stoppuhr vorhanden. <br><br>
      
      <ul>
      <b>Beispiel</b> <br>
      set &lt;name&gt; countDownInit 0 30 10 <br>
      set &lt;name&gt; countDownInit 3600
      </ul>
      <br>
      
    </li>
    <br>
    
    <a name="displayTextSet"></a>
    <li><b>displayTextSet</b><br>
      Stellt den anzuzeigenden Text ein. <br> 
      Dieses Set-Kommando ist nur bei einer digitalen Segmentanzeige mit "digitalDisplayPattern = text" vorhanden. <br>
      (default: leere Anzeige) <br><br>
      
      <b>Hinweis:</b> <br>
      Die darstellbaren Zeichen sind vom Attribut "digitalSegmentType" abhängig. <br>
      Mit der (default) Siebensegmentanzeige können lediglich Ziffern, Bindestrich, Unterstrich und die Buchstaben 
      A, b, C, d, E, F, H, L, n, o, P, r, t, U und Y angezeigt werden. 
      Damit lassen sich außer Zahlen auch kurze Texte wie „Error“, „HELP“, „run“ oder „PLAY“ anzeigen. <br>
      Für Textdarstellung wird empfohlen die Sechzehnsegmentanzeige mit dem Attribut "digitalSegmentType" einzustellen !    
    </li>
    <br>
    
    <a name="displayTextDel"></a>
    <li><b>displayTextDel</b><br>
      Löscht den Anzeigetext. <br>
      Dieses Set-Kommando ist nur bei einer digitalen Segmentanzeige mit "digitalDisplayPattern = text" vorhanden. <br>
    </li>
    <br>
    
    <a name="reset"></a>
    <li><b>reset</b><br>
      Stoppt die Stoppuhr (falls sie läuft) und löscht alle spezifischen Readings bzw. setzt sie auf initialized zurück. <br>
      Dieses Set-Kommando ist nur bei digitalen Stoppuhren vorhanden. <br>
    </li>
    <br>
    
    <a name="resume"></a>
    <li><b>resume</b><br>
      Setzt die Zählung einer angehaltenen Stoppuhr fort. <br>
      Dieses Set-Kommando ist nur bei digitalen Stoppuhren vorhanden. <br>
    </li>
    <br>
    
    <a name="start"></a>
    <li><b>start</b><br>
      Startet die Stoppuhr. <br>
      Dieses Set-Kommando ist nur bei digitalen Stoppuhren vorhanden. <br>
    </li>
    <br>  
    
    <a name="stop"></a>
    <li><b>stop</b><br>
      Stoppt die Stoppuhr. Die erreichte Zeit bleibt erhalten. <br>
      Dieses Set-Kommando ist nur bei digitalen Stoppuhren vorhanden. <br>
    </li>
    <br>
    
    <a name="textTicker"></a>
    <li><b>textTicker on | off </b><br>
      Schaltet den Laufschriftmodus einer Textanzeige (siehe Attribut digitalDisplayPattern) ein bzw. aus. <br>
      (default: off)      
    </li>
    <br>
    
    <a name="time"></a>
    <li><b>time &lt;hh&gt; &lt;mm&gt; &lt;ss&gt; </b><br>
      Setzt eine statische Zeitanzeige mit hh-Stunden, mm-Minuten und ss-Sekunden. <br>
      Dieses Set-Kommando ist nur bei einer Digitaluhr mit statischer Zeitanzeige vorhanden. <br><br>
      
      <ul>
      <b>Beispiel</b> <br>
      set &lt;name&gt; time 8 15 3
      </ul>
      
    </li>
    <br>
  
  </ul>
  </ul>
  <br>

  <a name="WatchesGet"></a>
  <b>Get</b> 
  
  <ul>
  
    N/A
    
  </ul>
  <br>

  <a name="WatchesAttr"></a>
  <b>Attribute</b>
  <br><br>
  
  <ul>
  <ul>
  
    <a name="disable"></a>
    <li><b>disable</b><br>
      Aktiviert/deaktiviert das Device.
    </li>
    <br>
    
    <a name="hideDisplayName"></a>
    <li><b>hideDisplayName</b><br>
      Verbirgt den Device/Alias-Namen (Link zur Detailansicht).    
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      Zusätzliche HTML Tags zur Größenänderung der Uhr / Anzeige. <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; htmlattr width="125" height="125" <br>
      </ul>
    </li>
    <br>
    
    <a name="timeSource"></a>
    <li><b>timeSource</b><br>
      Wählt die Zeitquelle aus. Es kann die lokale Clientzeit (Browser) oder die Zeit des FHEM-Servers angezeigt werden. <br>
      Diese Einstellung ist bei (CountDown-)Stoppuhren nicht relevant. <br>
      (default: client)
    </li>
    <br>
    
  </ul>  
    
  Die nachfolgenden Attribute sind spezifisch für einen Uhrentyp zu setzen. <br>
  <br>
   
  <b>Model: Modern</b>  <br><br>
  
  <ul>
    <a name="modernColorBackground"></a>
    <li><b>modernColorBackground</b><br>
      Hintergrundfarbe der Uhr.    
    </li>
    <br>
    
    <a name="modernColorFace"></a>
    <li><b>modernColorFace</b><br>
      Einfärbung des Ziffernblattes.    
    </li>
    <br>
    
    <a name="modernColorFigure"></a>
    <li><b>modernColorFigure</b><br>
      Farbe der Ziffern im Ziffernblatt und der Zeigerachsabdeckung.    
    </li>
    <br>
    
    <a name="modernColorHand"></a>
    <li><b>modernColorHand</b><br>
      Farbe der UhrenZeiger.    
    </li>
    <br>
    
    <a name="modernColorRing"></a>
    <li><b>modernColorRing</b><br>
      Farbe des Ziffernblattrahmens.    
    </li>
    <br>
    
    <a name="modernColorRingEdge"></a>
    <li><b>modernColorRingEdge</b><br>
      Farbe des Außenringes vom Ziffernblattrahmen.    
    </li>
    <br>
  </ul>
  <br>
  
  <b>Model: Station</b>  <br><br>
  
  <ul>
    <a name="stationBody"></a>
    <li><b>stationBody</b><br>
      Art des Uhrengehäuses.    
    </li>
    <br>
    
    <a name="stationBoss"></a>
    <li><b>stationBoss</b><br>
      Art und Farbe der Zeigerachsabdeckung.    
    </li>
    <br>

    <a name="stationHourHand"></a>
    <li><b>stationHourHand</b><br>
      Art des Stundenzeigers.    
    </li>
    <br>    
    
    <a name="stationMinuteHand"></a>
    <li><b>stationMinuteHand</b><br>
      Art des Minutenzeigers.    
    </li>
    <br> 

    <a name="stationMinuteHandBehavoir"></a>
    <li><b>stationMinuteHandBehavoir</b><br>
      Verhalten des Minutenzeigers.    
    </li>
    <br>   

    <a name="stationSecondHand"></a>
    <li><b>stationSecondHand</b><br>
      Art des Sekundenzeigers.    
    </li>
    <br>  

    <a name="stationSecondHandBehavoir"></a>
    <li><b>stationSecondHandBehavoir</b><br>
      Verhalten des Sekundenzeigers.    
    </li>
    <br>  

    <a name="stationStrokeDial"></a>
    <li><b>stationStrokeDial</b><br>
      Auswahl des Ziffernblattes.    
    </li>
    <br>      
    
  </ul>
  <br>
  
  <b>Model: Digital</b>  <br><br>
  
  <ul>
    <a name="digitalBorderDistance"></a>
    <li><b>digitalBorderDistance</b><br>
      Linker und rechter Abstand der digitalen Textanzeige vom Hintergrundrand. <br>
      (default: 8)      
    </li>
    <br>  
  
    <a name="digitalColorBackground"></a>
    <li><b>digitalColorBackground</b><br>
      Digitaluhr Hintergrundfarbe.    
    </li>
    <br>  

    <a name="digitalColorDigits"></a>
    <li><b>digitalColorDigits</b><br>
      Farbe der Balkenanzeige in einer Digitaluhr.    
    </li>
    <br> 

    <a name="digitalDigitAngle"></a>
    <li><b>digitalDigitAngle </b><br>
      Stellt den Neigungswinkel der dargestellten Zeichen ein. <br>
      (default: 9)      
    </li>
    <br> 
    
    <a name="digitalDigitDistance"></a>
    <li><b>digitalDigitDistance </b><br>
      Stellt den Zeichenabstand ein. <br>
      (default: 2)      
    </li>
    <br>  
    
    <a name="digitalDigitHeight"></a>
    <li><b>digitalDigitHeight </b><br>
      Stellt die Zeichenhöhe ein. <br>
      (default: 20)      
    </li>
    <br>

    <a name="digitalDigitWidth"></a>
    <li><b>digitalDigitWidth </b><br>
      Stellt die Zeichenbreite ein. <br>
      (default: 12)      
    </li>
    <br>     
  
    <a name="digitalDisplayPattern"></a>
    <li><b>digitalDisplayPattern [countdownwatch | staticwatch | stopwatch | text | watch]</b><br>
      Umschaltung der Digitalanzeige zwischen einer Uhr (default), einer Stoppuhr, statischen Zeitanzeige oder Textanzeige. 
      Der anzuzeigende Text im Modus Textanzeige kann mit <br>
      <b>set &lt;name&gt displayText</b>. <br><br>
      
      <b>Hinweis:</b> Bei Textanzeige wird empfohlen das Attribut "digitalSegmentType" auf "16" zu stellen. <br><br>
      
    <ul>
    <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>countdownwatch </b> </td><td>: CountDown Stoppuhr                 </td></tr>
       <tr><td> <b>staticwatch</b>     </td><td>: statische Zeitanzeige              </td></tr>
       <tr><td> <b>stopwatch</b>       </td><td>: Stoppuhr                           </td></tr>
       <tr><td> <b>text</b>            </td><td>: Anzeige eines definierbaren Textes </td></tr>
       <tr><td> <b>watch</b>           </td><td>: Uhr                                </td></tr>
    </table>
    </ul>
    <br>
    <br>
    </li> 
    
    <a name="digitalSegmentDistance"></a>
    <li><b>digitalSegmentDistance </b><br>
      Legt den Abstand zwischen den Segmenten fest. <br>
      (default: 0.5)      
    </li>
    <br> 
    
    <a name="digitalSegmentType"></a>
    <li><b>digitalSegmentType </b><br>
      Schaltet die Segmentanzahl der Digitalanzeige um. <br>
      (default: 7)      
    </li>
    <br> 

    <a name="digitalSegmentWidth"></a>
    <li><b>digitalSegmentWidth </b><br>
      Verändert die Breite der einzelnen Segmente. <br>
      (default: 1.5)      
    </li>
    <br> 

    <a name="digitalTextDigitNumber"></a>
    <li><b>digitalTextDigitNumber &lt;Anzahl&gt; </b><br>
      Wenn &lt;Anzahl&gt > 0 wird die Anzahl der Stellen einer Textanzeige (digitalDisplayPattern = text) fest eingestellt. 
      Wenn &lt;Anzahl&gt = 0 oder nicht gesetzt erfolgt die Festlegung automatisch. In diesem Fall erfolgt eine Adaption
      der Zeichengröße an die Anzahl abhängig von der eingestellten Displaygröße (siehe htmlattr). <br>
      (default: 0)      
    </li>
    <br>      
    
  </ul>
  </ul>
  
</ul>

=end html_DE

=for :application/json;q=META.json 60_Watches.pm
{
  "abstract": "Clock display in different variants",
  "x_lang": {
    "de": {
      "abstract": "Uhrenanzeige in verschiedenen Varianten"
    }
  },
  "keywords": [
    "Watch",
    "Modern clock",
    "clock",
    "Station clock",
    "Digital display"
  ],
  "version": "v1.1.1",
  "release_status": "testing",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>",
    null
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "Time::HiRes": 0,
        "GPUtils": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut

########################################################################################################################
# $Id:  $
#########################################################################################################################
#       60_Watches.pm
#
#       (c) 2018 by Heiko Maaz
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

package main;

use strict;
use warnings;

# Versions History intern
our %Watches_vNotesIntern = (
  "0.4.0"  => "20.11.2018  text display ",
  "0.3.0"  => "19.11.2018  digital clock added ",
  "0.2.0"  => "14.11.2018  station clock added ",
  "0.1.0"  => "13.11.2018  initial Version with modern analog clock"
);

sub Watches_modern($);

################################################################
sub Watches_Initialize($) {
  my ($hash) = @_;
  
  $hash->{DefFn}              = "Watches_Define";
  $hash->{AttrList}           = "digitalColorBackground:colorpicker ".
                                "digitalColorDigits:colorpicker ".
                                "digitalDisplayPattern:text,watch ".
                                "digitalDisplayText ".
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
                                "disable:1,0 ".
                                "htmlattr ".
                                "hideDisplayName:1,0 "
                                ;
  $hash->{FW_summaryFn}       = "Watches_FwFn";
  $hash->{FW_detailFn}        = "Watches_FwFn";
  $hash->{AttrFn}             = "Watches_Attr";
  $hash->{FW_hideDisplayName} = 1;        # Forum 88667
  # $hash->{FW_addDetailToSummary} = 1;
  $hash->{FW_atPageEnd} = 1;            # wenn 1 -> kein Longpoll ohne informid in HTML-Tag
}


################################################################
sub Watches_Define($$) {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(!$a[2]) {
      return "You need to specify more parameters.\n". "Format: define <name> Watches [Modern | Station | Digital]";
  }
  
  $hash->{MODEL}   = $a[2];
  $hash->{VERSION} = $hash->{VERSION} = (reverse sort(keys %Watches_vNotesIntern))[0];
  
  readingsSingleUpdate($hash,"state", "initialized", 1);      # Init für "state" 
  
return undef;
}

################################################################
sub Watches_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
	
	if ($cmd eq "set" && $hash->{MODEL} !~ /modern/i && $aName =~ /^modern.*/) {
         return "\"$aName\" is only valid for Watches model \"Modern\"";
	}
	
	if ($cmd eq "set" && $hash->{MODEL} !~ /station/i && $aName =~ /^station.*/) {
         return "\"$aName\" is only valid for Watches model \"Station\"";
	}
	
	if ($cmd eq "set" && $hash->{MODEL} !~ /digital/i && $aName =~ /^digital.*/) {
         return "\"$aName\" is only valid for Watches model \"Digital\"";
	}
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
		$val = ($do == 1 ? "disabled" : "initialized");
    
        readingsSingleUpdate($hash, "state", $val, 1);
    }

return undef;
}

################################################################
sub Watches_FwFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  
  my $alias = AttrVal($d, "alias", $d);                            # Linktext als Aliasname oder Devicename setzen
  my $dlink = "<a href=\"/fhem?detail=$d\">$alias</a>"; 
  
  my $ret = "";
  $ret .= "<span>$dlink </span><br>"  if(!AttrVal($d,"hideDisplayName",0));
  if(IsDisabled($d)) {
      if(AttrVal($d,"hideDisplayName",0)) {
          $ret .= "Watch <a href=\"/fhem?detail=$d\">$d</a> is disabled";
      } else {
          $ret .= "<html>Watch is disabled</html>";
      }  
  } else {
      $ret .= Watches_modern($d) if($hash->{MODEL} =~ /modern/i);
      $ret .= Watches_station($d) if($hash->{MODEL} =~ /station/i);
	  $ret .= Watches_digital($d) if($hash->{MODEL} =~ /digital/i);
  }
    
return $ret;
}

################################################################
sub Watches_digital($) {
  my ($d) = @_;
  my $hash   = $defs{$d};
  my $hattr  = AttrVal($d,"htmlattr","width='150' height='50'");
  my $bgc    = AttrVal($d,"digitalColorBackground","C4C4C4");
  my $dcd    = AttrVal($d,"digitalColorDigits","000000"); 
  my $ddp    = AttrVal($d,"digitalDisplayPattern","watch");  
  my $ddt    = AttrVal($d,"digitalDisplayText","Play");
  
  if($ddp eq "watch") {
      $ddp = "##:##:##";
      $ddt = "  "."((hours < 10) ? ' ' : '') + hours
                    + ':' + ((minutes < 10) ? '0' : '') + minutes
                    + ':' + ((seconds < 10) ? '0' : '') + seconds";
  } elsif($ddp eq "text") {
      $ddp = "##########";
	  my $txtc = length($ddt);
	  $ddp = "";
	  for(my $i = 0; $i <= $txtc; $i++) {
		  $ddp .= "#";
      }
	  $ddt = "' ".$ddt."'";
  }
 
  # Segmentanzeige aus: http://www.3quarks.com/de/Segmentanzeige/index.html

  return "
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
    SegmentDisplay_$d.RoundedCorner   = 2;


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
        this.segmentCount    = SegmentDisplay_$d.SevenSegment;
        this.cornerType      = SegmentDisplay_$d.RoundedCorner;
        this.colorOn         = 'rgb(233, 93, 15)';
        this.colorOff        = 'rgb(75, 30, 5)';
    };

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

    var display_$d = new SegmentDisplay_$d('display_$d');
    display_$d.pattern         = '$ddp       ';
    display_$d.cornerType      = 2;
    display_$d.displayType     = 7;
    display_$d.displayAngle    = 9;
    display_$d.digitHeight     = 20;
    display_$d.digitWidth      = 12;
    display_$d.digitDistance   = 2;
    display_$d.segmentWidth    = 3;
    display_$d.segmentDistance = 0.5;
    //display_$d.colorOn         = 'rgba(0, 0, 0, 0.9)';
    display_$d.colorOn         = '#$dcd';
    display_$d.colorOff        = 'rgba(0, 0, 0, 0.1)';

    animate_$d();

    function animate_$d() {
        var time    = new Date();
        var hours   = time.getHours();
        var minutes = time.getMinutes();
        var seconds = time.getSeconds();
        var value   = $ddt;
        display_$d.setValue(value);
        window.setTimeout('animate_$d()', 100);
    }

    </script>
    </body>
    </html>      
  ";
}

################################################################
sub Watches_station($) {
  my ($d) = @_;
  my $hash   = $defs{$d};
  my $ssh    = AttrVal($d,"stationSecondHand","Bar")."SecondHand";
  my $shb    = AttrVal($d,"stationSecondHandBehavoir","Bouncing")."SecondHand";
  my $smh    = AttrVal($d,"stationMinuteHand","Pointed")."MinuteHand";
  my $mhb    = AttrVal($d,"stationMinuteHandBehavoir","Bouncing")."MinuteHand";
  my $shh    = AttrVal($d,"stationHourHand","Pointed")."HourHand";
  my $sb     = AttrVal($d,"stationBoss","Red")."Boss"; 
  my $ssd    = AttrVal($d,"stationStrokeDial","Swiss")."StrokeDial";
  my $sbody  = AttrVal($d,"stationBody","Round")."Body";
  my $hattr  = AttrVal($d,"htmlattr","width='150' height='150'");

  # Bahnhofsuhr aus http://www.3quarks.com/de/Bahnhofsuhr/
  return "
      <html>
      <body>  
      <canvas id='clock_$d' $hattr> 
      </canvas>
      
      <script>  
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


      function StationClock_$d(clockId_$d) {
          this.clockId_$d = clockId_$d; 
          this.radius  = 0;

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
          this.lastMinute = 0;
          this.lastSecond = 0;
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

                  // get current time
                  var time    = new Date();
                  var millis  = time.getMilliseconds() / 1000.0;
                  var seconds = time.getSeconds();
                  var minutes = time.getMinutes();
                  var hours   = time.getHours() + this.hourOffset;

                  // draw hour hand
                  context.save();
                  context.rotate(hours * Math.PI / 6 + minutes * Math.PI / 360);
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
                      context.rotate((minutes + seconds / 60) * Math.PI / 30);
                      break;
                    case StationClock_$d.BouncingMinuteHand:
                      context.rotate(minutes * Math.PI / 30);
                      break;
                    case StationClock_$d.ElasticBouncingMinuteHand:
                      if (this.lastMinute != minutes) {
                          this.minuteHandAnimationStep = 3;
                          this.lastMinute = minutes;
                      }
                      context.rotate((minutes + this.getAnimationOffset(this.minuteHandAnimationStep)) * Math.PI / 30);
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
                      context.rotate(Math.min((seconds + millis) * (60.0 / 58.5), 60.0) * Math.PI / 30);
                      break;
                    case StationClock_$d.CreepingSecondHand:
                      context.rotate((seconds + millis) * Math.PI / 30);
                      break;
                    case StationClock_$d.BouncingSecondHand:
                      context.rotate(seconds * Math.PI / 30);
                      break;
                    case StationClock_$d.ElasticBouncingSecondHand:
                      if (this.lastSecond != seconds) {
                          this.secondHandAnimationStep = 3;
                          this.lastSecond = seconds;
                      }
                      context.rotate((seconds + this.getAnimationOffset(this.secondHandAnimationStep)) * Math.PI / 30);
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
        
      var clock_$d = new StationClock_$d('clock_$d');
      clock_$d.body = StationClock_$d.$sbody;
      clock_$d.dial = StationClock_$d.$ssd;
      clock_$d.hourHand = StationClock_$d.$shh;
      clock_$d.minuteHand = StationClock_$d.$smh;
      clock_$d.secondHand = StationClock_$d.$ssh;
      clock_$d.boss = StationClock_$d.$sb;
      clock_$d.minuteHandBehavoir = StationClock_$d.$mhb;
      clock_$d.secondHandBehavoir = StationClock_$d.$shb;

      function animate(clock_$d) {
          clock_$d.draw();
          window.setTimeout(function(){animate(clock_$d)}, 50);
      }

      animate(clock_$d);   
      </script>
      
      </body>
      </html>      
  ";
}

################################################################
sub Watches_modern($) {
  my ($d) = @_;
  my $hash   = $defs{$d};
  my $facec  = AttrVal($d,"modernColorFace","FFFEFA");
  my $bgc    = AttrVal($d,"modernColorBackground","333");
  my $fc     = AttrVal($d,"modernColorFigure","333");
  my $hc     = AttrVal($d,"modernColorHand","333");
  my $fr     = AttrVal($d,"modernColorRing","FFFFFF");
  my $fre    = AttrVal($d,"modernColorRingEdge","333");
  my $hattr  = AttrVal($d,"htmlattr","width='150' height='150'");

  # moderne Uhr aus https://www.w3schools.com/graphics/canvas_clock_start.asp
  return "
      <html>
      <body>

      <canvas id='canvas_$d' $hattr style='background-color:#$bgc'>
      </canvas>

      <script>
      var canvas_$d = document.getElementById('canvas_$d');
      var ctx_$d = canvas_$d.getContext('2d');
      var radius_$d = canvas_$d.height / 2;
      ctx_$d.translate(radius_$d, radius_$d);
      radius_$d = radius_$d * 0.90
      setInterval(drawClock_$d, 1000);

      function drawClock_$d() {
          drawFace_$d(ctx_$d, radius_$d);
          drawnumbers_$d(ctx_$d, radius_$d);
          drawTime_$d(ctx_$d, radius_$d);
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
          ctx_$d.lineWidth = radius_$d*0.1;
          ctx_$d.stroke();
          ctx_$d.beginPath();
          ctx_$d.arc(0, 0, radius_$d*0.1, 0, 2*Math.PI);
          ctx_$d.fillStyle = '#$fc';                      // Farbe Ziffern und Zeigerwelle
          ctx_$d.fill();
      }

      function drawnumbers_$d(ctx_$d, radius_$d) {
          var ang_$d;
          var num_$d;
          ctx_$d.font = radius_$d*0.15 + 'px arial';
          ctx_$d.textBaseline='middle';
          ctx_$d.textAlign='center';
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
          var now_$d = new Date();
          var hour_$d = now_$d.getHours();
          var minute_$d = now_$d.getMinutes();
          var second_$d = now_$d.getSeconds();
          //hour_$d
          hour_$d=hour_$d%12;
          hour_$d=(hour_$d*Math.PI/6)+
          (minute_$d*Math.PI/(6*60))+
          (second_$d*Math.PI/(360*60));
          drawHand_$d(ctx_$d, hour_$d, radius_$d*0.5, radius_$d*0.07);
          //minute_$d
          minute_$d=(minute_$d*Math.PI/30)+(second_$d*Math.PI/(30*60));
          drawHand_$d(ctx_$d, minute_$d, radius_$d*0.8, radius_$d*0.07);
          // second_$d
          second_$d=(second_$d*Math.PI/30);
          drawHand_$d(ctx_$d, second_$d, radius_$d*0.9, radius_$d*0.02);
      }

      function drawHand_$d(ctx_$d, pos, length, width) {
          ctx_$d.beginPath();
          ctx_$d.lineWidth = width;
          ctx_$d.lineCap = 'round';
          ctx_$d.moveTo(0,0);
          ctx_$d.rotate(pos);
          ctx_$d.lineTo(0, -length);
          ctx_$d.stroke();
          ctx_$d.rotate(-pos);
      }
      </script>

      </body>
      </html>
  ";
}

1;

=pod
=item helper
=item summary    create a watch in modern, station or digital style
=item summary_DE erstellt eine Uhr: Modern, Bahnhofsuhr oder Digital


=begin html

<a name="Watches"></a>
<h3>Watches</h3>

<br>
Das Modul Watches stellt eine Modern-, Bahnhofs- oder Digitalanzeige als Device zur Verfügung. <br>
Die Uhren basieren auf Skripten dieser Seiten: <br>
<a href='https://www.w3schools.com/graphics/canvas_clock_start.asp'>moderne Uhr</a>, 
<a href='http://www.3quarks.com/de/Bahnhofsuhr/'>Bahnhofsuhr</a>, 
<a href='http://www.3quarks.com/de/Segmentanzeige/'>Digitalanzeige</a> 
<br>
<br>

<ul>
  <a name="WatchesDefine"></a>
  <b>Define</b>
  
  <ul>
    define &lt;name&gt; Watches [Modern | Station | Digital]  
    <br><br>
    
  <table>  
     <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> <b>Modern</b>     </td><td>: erstellt eine analoge Uhr im modernen Design  </td></tr>
     <tr><td> <b>Station</b>    </td><td>: erstellt eine Bahnhofsuhr </td></tr>
     <tr><td> <b>Digital</b>    </td><td>: erstellt eine Digitalanzeige (Uhr oder Text) </td></tr>
  </table>
  <br>
  <br>
  </ul>

  <a name="WatchesSet"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="WatchesGet"></a>
  <b>Get</b> <ul>N/A</ul><br>

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
      Zusätzliche HTML Tags zur Größenänderung de Uhr. <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; htmlattr width="125" height="125" <br>
      </ul>
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
	
    <a name="digitalDisplayPattern"></a>
    <li><b>digitalDisplayPattern [text | watch]</b><br>
      Umschaltung der Digitalanzeige zwischen Uhrenmodus (default) und Textanzeige. Der anzuzeigende Text 
	  kann mit dem Attribut "digitalDisplayText" definiert werden. <br><br>
    <ul>
	<table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>watch</b>     </td><td>: Anzeige einer Uhr </td></tr>
       <tr><td> <b>text</b>      </td><td>: Anzeige eines definierbaren Textes </td></tr>
    </table>
	</ul>
    <br>
    </li>
	
    <a name="digitalDisplayText"></a>
    <li><b>digitalDisplayText</b><br>
      Ist das Attribut "digitalDisplayPattern = text" gesetzt, kann mit "digitalDisplayText" der 
	  anzuzeigende Text eingestellt werden. Im Default wird "Play" anzgezeigt. <br>
	  Mit der Siebensegmentanzeige können Ziffern, Bindestrich, Unterstrich und die Buchstaben 
	  A, b, C, d, E, F, H, L, n, o, P, r, t, U und Y angezeigt werden. 
	  So lassen sich außer Zahlen auch kurze Texte wie „Error“, „HELP“, „run“ oder „PLAY“ anzeigen. 
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
Das Modul Watches stellt eine Modern-, Bahnhofs- oder Digitalanzeige als Device zur Verfügung. <br>
Die Uhren basieren auf Skripten dieser Seiten: <br>
<a href='https://www.w3schools.com/graphics/canvas_clock_start.asp'>moderne Uhr</a>, 
<a href='http://www.3quarks.com/de/Bahnhofsuhr/'>Bahnhofsuhr</a>, 
<a href='http://www.3quarks.com/de/Segmentanzeige/'>Digitalanzeige</a> 
<br>
<br>

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
     <tr><td> <b>Digital</b>    </td><td>: erstellt eine Digitalanzeige (Uhr oder Text) </td></tr>
  </table>
  <br>
  <br>
  </ul>

  <a name="WatchesSet"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="WatchesGet"></a>
  <b>Get</b> <ul>N/A</ul><br>

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
      Zusätzliche HTML Tags zur Größenänderung de Uhr. <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; htmlattr width="125" height="125" <br>
      </ul>
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
  
    <a name="digitalDisplayPattern"></a>
    <li><b>digitalDisplayPattern [text | watch]</b><br>
      Umschaltung der Digitalanzeige zwischen Uhrenmodus (default) und Textanzeige. Der anzuzeigende Text 
	  kann mit dem Attribut "digitalDisplayText" definiert werden. <br><br>
    <ul>
	<table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>watch</b>     </td><td>: Anzeige einer Uhr </td></tr>
       <tr><td> <b>text</b>      </td><td>: Anzeige eines definierbaren Textes </td></tr>
    </table>
	</ul>
    <br>
    </li>
	
    <a name="digitalDisplayText"></a>
    <li><b>digitalDisplayText</b><br>
      Ist das Attribut "digitalDisplayPattern = text" gesetzt, kann mit "digitalDisplayText" der 
	  anzuzeigende Text eingestellt werden. Im Default wird "Play" anzgezeigt. <br>
	  Mit der Siebensegmentanzeige können Ziffern, Bindestrich, Unterstrich und die Buchstaben 
	  A, b, C, d, E, F, H, L, n, o, P, r, t, U und Y angezeigt werden. 
	  So lassen sich außer Zahlen auch kurze Texte wie „Error“, „HELP“, „run“ oder „PLAY“ anzeigen. 
    </li>
    <br> 
	
  </ul>
  
  </ul>
  
</ul>

=end html_DE
=cut

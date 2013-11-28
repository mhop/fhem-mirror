################################################################################
# 95 VIEW
# Feedback: http://groups.google.com/group/fhem-users
# Define Custom View
# Stand: 04.2011
# Version: 1.0
################################################################
#
#  Copyright notice
#
#  (c) 2011 Copyright: Axel Rieger (fhem bei anax punkt info)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################################
# Usage
# define <NAME> VIEW
# attr <NAME> ViewRegExType -> Chose Device-Type (Perl-RegExp)
# attr <NAME> ViewRegExName -> Chose Device-Name (Perl-RegExp)
# attr <NAME> ViewRegExReading -> Chose Readings (Perl-RegExp)
# attr <Name> ViewRegExReadingStringCompare -> Chose ReadingValue (Perl-RegEx)
#
# Examples:
# Show all Device with Type FHT
# attr MyFHT ViewRegExType FHT
# attr MyFHT ViewRegExName * or NotSet
# attr MyFHT ViewRegExReading  * or NotSet
# attr MyFHT ViewRegExReadingStringCompare * or Notset
#
# Show all Warnings of ALL Devices without "none"-Values
# attr MyFHT ViewRegExType * or NotSet
# attr MyFHT ViewRegExName * or NotSet
# attr MyFHT ViewRegExReading warnings
# attr MyFHT ViewRegExReadingStringCompare [^none]
################################################################################
package main;
use strict;
use warnings;
use Data::Dumper;
use vars qw(%data);
#-------------------------------------------------------------------------------
sub VIEW_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn} = "VIEW_Define";
  $hash->{AttrList}  = "ViewRegExType ViewRegExName ViewRegExReading ViewRegExReadingStringCompare  loglevel:0,5";
  # CGI
  my $name = "MyVIEWS";
  my $fhem_url = "/" . $name ;
  $data{FWEXT}{$fhem_url}{FUNC} = "VIEW_CGI";
  $data{FWEXT}{$fhem_url}{LINK} = $name;
  $data{FWEXT}{$fhem_url}{NAME} = $name;
  # Global-Config for CSS
  # $attr{global}{VIEW_CSS} = "";
  $modules{_internal_}{AttrList} .= " VIEW_CSS";
  return undef;
}
#-------------------------------------------------------------------------------
sub VIEW_Define(){
  my ($hash, $def) = @_;
  $hash->{STATE} = $hash->{NAME};
  return undef;
  }
#-------------------------------------------------------------------------------
sub VIEW_CGI(){
  my ($htmlarg) = @_;
  # Remove trailing slash
  $htmlarg =~ s/^\///;
  # Log 0,"VIEW: htmlarg: " . $htmlarg ."\n";
  # URL: http(s)://[FHEM:xxxx]/fhem/MyVIEWS/<View-Name>
  my @params = split(/\//,$htmlarg);
  my $ret_html;
  if(int(@params) > 2) {
    $ret_html = "ERROR: Wrong URL \n";
    return ("text/plain; charset=ISO-8859-1", $ret_html);
    }
  my $view = $params[1];
  if($htmlarg ne "MyVIEWS"){
  if(!defined($defs{$view})){
    $ret_html = "ERROR: View $view not definde \n";
    return ("text/plain; charset=ISO-8859-1", $ret_html);
    }
  }
  $ret_html = "<!DOCTYPE html PUBLIC \"-\/\/W3C\/\/DTD HTML 4.01\/\/EN\" \"http:\/\/www.w3.org\/TR\/html4\/strict.dtd\">\n";
  $ret_html .= "<html>\n";
  $ret_html .= "<head>\n";
  # Select CSS-Style-Sheet
  my $css = $attr{global}{VIEW_CSS};
  if($css eq ""){$ret_html .= "<link href=\"$FW_ME/style.css\" rel=\"stylesheet\"/>\n";}
  else {$ret_html .= "<link href=\"$FW_ME/$css\" rel=\"stylesheet\"/>\n";}
  $ret_html .= "<title>FHEM VIEWS<\/title>\n";
  $ret_html .= "<\/head>\n";
  $ret_html .= "<body>\n";
  # DIV HDR
  $ret_html .= &VIEW_CGI_TOP($view);
  # DIV LEFT
  $ret_html .= &VIEW_CGI_LEFT();
  # DIV RIGHT
  if($view) {
    $ret_html .= &VIEW_CGI_RIGHT($view);
    }
  else{
    $ret_html .= "<div id=\"content\">\n";
    $ret_html .= "</div>\n";
    }
  # HTML
  $ret_html .= "</body>\n";
  $ret_html .= "</html>\n";
  return ("text/html; charset=ISO-8859-1", $ret_html);
}
#-------------------------------------------------------------------------------
sub VIEW_CGI_TOP($) {
  my $v = shift(@_);
  # rh = return-Html
  my $rh;
  $rh = "<div id=\"hdr\">\n";
  $rh .= "<form method=\"get\" action=\"" . $FW_ME . "\">\n";
  $rh .= "<table WIDTH=\"100%\">\n";
  $rh .= "<tr>";
  if($v) {
    $rh .= "<td><a href=\"" . $FW_ME . "\">FHEM:</a>$v</td>";
    }
  else {
    $rh .= "<td><a href=\"" . $FW_ME . "\">FHEM:</a></td>";
    }
  $rh .= "<td><input type=\"text\" name=\"cmd\" size=\"30\"/></td>";
  $rh .= "</tr>\n";
  $rh .= "</table>\n";
  $rh .= "</form>\n";
  $rh .= "<br>\n";
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub VIEW_CGI_LEFT(){
  # rh = return-Html
  my $rh;
  $rh = "<div id=\"logo\"><img src=\"" . $FW_ME . "/fhem.png\"></div>";
  $rh .= "<div id=\"menu\">\n";
  # Print VIEWS
  $rh .= "<table class=\"room\">\n";
  foreach my $d (sort keys %defs) {
    next if ($defs{$d}{TYPE} ne "VIEW");
    $rh .= "<tr><td>";
    $rh .= "<a href=\"" . $FW_ME . "/MyVIEWS/$d\">$d</a></h3>";
    $rh .= "</td></tr>\n";
  }
  $rh .= "</table><br>\n";
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub VIEW_CGI_RIGHT(){
  my ($v) = @_;
  # rh = return-Html
  my $rh;
  # Filters ViewRegExType ViewRegExName ViewRegExReading
  my $f_type = ".*";
  if(defined($attr{$v}{ViewRegExType})) {
    $f_type = $attr{$v}{ViewRegExType};
    }
  my $f_name = ".*";
  if(defined($attr{$v}{ViewRegExName})){
    $f_name = $attr{$v}{ViewRegExName};
    }
  my $f_reading = ".*";
  if(defined($attr{$v}{ViewRegExReading})) {
    $f_reading = $attr{$v}{ViewRegExReading};
  }
  my $f_reading_val = ".*";
  if(defined($attr{$v}{ViewRegExReadingStringCompare})) {
    $f_reading_val = $attr{$v}{ViewRegExReadingStringCompare};
  }
  my $row = 1;
  $rh = "<div id=\"content\">\n";
  $rh .= "<hr>\n";
  $rh .= "[RegEx] Type: \"$f_type\" Name: \"$f_name\" Reading: \"$f_reading\" Value:\"$f_reading_val\"\n";
  $rh .= "<hr>\n";
  my ($d,$r,$tr_class);
  my $th = undef;
  # Get Devices and Readings
  foreach $d (sort keys %defs){
    if($defs{$d}{TYPE} =~ m/$f_type/ && $d =~ m/$f_name/){
    # Log 0,"VIEW-RIGHT: Device-Match $d";
    # Weblink
      my $web_rt;
      if($defs{$d}{TYPE} eq "weblink" && $f_reading eq ".*" && $f_reading_val eq ".*") {
        $rh .= "<table class=\"block\">\n";
        $rh .="<tr><td>WEBLINK: $d</td></tr>\n";
        # $rh .= FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE});
        $rh .= VIEW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE});
        # Log 0,"VIEW-RIGHT: FW_showWeblink \n $web_rt\n"; 
        # FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE});
        # Log 0,"VIEW-RIGHT: Render-Weblink $d";
        $rh .= "</table>\n";
      }
      else {
        foreach $r (sort keys %{$defs{$d}{READINGS}}) {
          if($r =~ m/$f_reading/) {
            # ViewRegExReadingStringCompare
            if($defs{$d}{READINGS}{$r}{VAL} =~ m/$f_reading_val/){
              $tr_class = $row?"odd":"even";
              if(!$th) {
                $rh .= "<br>\n";
                $rh .= "<table class=\"block\" id=\"" . $defs{$d}{TYPE} . "\" >\n";
                $rh .= "<tr class=\"" . $tr_class . "\">";
                $rh .= "<td align=\"left\"><a href=\"$FW_ME?detail=$d\">$d</a></td>";
                if(defined($attr{$d}{comment})) {
                  $rh .= "<td>" . $attr{$d}{comment} . "</td>";
                }
                else {
                  $rh .= "<td>" . $defs{$d}{TYPE} . "</td>";
                }
                $rh .= "<td>" . $defs{$d}{STATE} . "</td>";
                $rh .= "</tr>\n";
                $th = 1;
                $row = ($row+1)%2;
                $tr_class = $row?"odd":"even";
              }
              $rh .= "<tr class=\"" . $tr_class . "\">";
              $rh .= "<td>$r</td>";
              $rh .= "<td>" . $defs{$d}{READINGS}{$r}{VAL} . "</td>";
              $rh .= "<td>" . $defs{$d}{READINGS}{$r}{TIME} . "</td>";
              $rh .= "</tr>\n";
              $row = ($row+1)%2;
             # ViewRegExReadingStringCompare
            }
          }
        }
        $rh .= "</table>\n";
      }
    }
  $th = undef;
  }
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub VIEW_showWeblink($$$)
{
  # Customized Function from 01_FHEMWEB.pm
  my $FW_plotmode = "gnuplot-scroll";
  my $FW_plotsize = "800,225";
  my ($d, $v, $t) = @_;
  my $rh;
  if($t eq "link") {
    $rh .= "<td><a href=\"$v\">$d</a></td>\n";    # no pH, want to open extra browser
  } 
  elsif($t eq "image") {
    $rh .= "<td><img src=\"$v\"><br>";
    $rh .= "<a href=\"$FW_ME?detail=$d\">$d</a>";
    $rh .= "</td>\n";
  }
  elsif($t eq "fileplot") {
    my @va = split(":", $v, 3);
    if(@va != 3 || !$defs{$va[0]} || !$defs{$va[0]}{currentlogfile}) {
      $rh .= "<td>Broken definition: $v</td>\n";
    } 
    else {
      if($va[2] eq "CURRENT") {
        $defs{$va[0]}{currentlogfile} =~ m,([^/]*)$,;
        $va[2] = $1;
      }
      $rh .= "<table><tr><td>";
      my $wl = "&amp;pos=";
      my $arg="$FW_ME?cmd=showlog $d $va[0] $va[1] $va[2]$wl";
      if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
        my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
        $rh .= "<embed src=\"$arg\" type=\"image/svg+xml\"" .
              "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";
      } 
      else {
        $rh .= "<img src=\"$arg\"/>";
      }
    $rh .= "</td>\n";
    $rh .= "<td><a href=\"$FW_ME?detail=$d\">$d</a></td>\n";
    $rh .= "</tr></table>";
      

    }
  }
}

#-------------------------------------------------------------------------------
1;

################################################################################
# 95 VIEW
# Feedback: http://groups.google.com/group/fhem-users
# Define Custom View
# Stand: 04.2011
# Version: 0.9
################################################################################
# Usage
# define <NAME> VIEW
# attr <NAME> ViewRegExType -> Chose Device-Type (Perl-RegExp)
# attr <NAME> ViewRegExName -> Chose Device-Name (Perl-RegExp)
# attr <NAME> ViewRegExReading -> Chose Readings (Perl-RegExp)
#
# Examples:
# Show all Device with Type FHT
# attr MyFHT ViewRegExType FHT
# attr MyFHT ViewRegExName * or NotSet
# attr MyFHT ViewRegExReading  * or NotSet
#
# Show all Warnings of ALL Devices
# attr MyFHT ViewRegExType * or NotSet
# attr MyFHT ViewRegExName * or NotSet
# attr MyFHT ViewRegExReading Warning
#
# Ausgabe
# <Device-Name> <Device-Type>
#               <READING-Name> <Reading-Value> <Reading-Time>
# Reihenfolge
 # foreach $d (sort keys %defs){
  # if($defs{$defs{$d}{TYPE}}{TYPE} =~ m/$attr{$d}{Type}/ && $d =~ m/$attr{<NAME>}{NAME}/){
    # foreach $r (sort keys %{$defs{$d}{READINGS}}) {
      # if($r =~ m/$attr{$d}{Reading}/) {
        # print $d . ": " $r;
        # }
      # }
    # }
  # }
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
  $hash->{AttrList}  = "ViewRegExType ViewRegExName ViewRegExReading loglevel:0,5";
  # CGI
  my $name = "MyVIEWS";
  my $fhem_url = "/" . $name ;
  $data{FWEXT}{$fhem_url}{FUNC} = "VIEW_CGI";
  $data{FWEXT}{$fhem_url}{LINK} = $name;
  $data{FWEXT}{$fhem_url}{NAME} = $name;
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
  Log 0,"VIEW: htmlarg: " . $htmlarg ."\n";
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
  $ret_html .= "VIEW: $view\n";
   $ret_html = "<!DOCTYPE html PUBLIC \"-\/\/W3C\/\/DTD HTML 4.01\/\/EN\" \"http:\/\/www.w3.org\/TR\/html4\/strict.dtd\">\n";
  $ret_html .= "<html>\n";
  $ret_html .= "<head>\n";
  $ret_html .= &VIEW_CGI_CSS();
  $ret_html .= "<title>FHEM GROUPS<\/title>\n";
  $ret_html .= "<link href=\"$FW_ME/style.css\" rel=\"stylesheet\"/>\n";
  $ret_html .= "<\/head>\n";
  $ret_html .= "<body>\n";
  # DIV HDR
  $ret_html .= &VIEW_CGI_TOP($view);
  # DIV LEFT
  $ret_html .= &VIEW_CGI_LEFT();
  # DIV RIGHT
  $ret_html .= &VIEW_CGI_RIGHT($view);
  # HTML
  $ret_html .= "</body>\n";
  $ret_html .= "</html>\n";
  return ("text/html; charset=ISO-8859-1", $ret_html);
  # return ("text/plain; charset=ISO-8859-1", $ret_html);
}
#-------------------------------------------------------------------------------
sub VIEW_CGI_CSS() {
  my $css;
  $css   =  "<style type=\"text/css\"><!--\n";
  $css .= "\#left {float: left; width: 15%; height:100%;}\n";
  $css .= "table.VIEW { border:thin solid; background: #E0E0E0; text-align:left;}\n";
  $css .= "table.VIEW tr.odd { background: #F0F0F0;}\n";
  $css .= "table.VIEW td.odd { background: #F0F0F0;}\n";
  $css .= "table.VIEW td {nowrap;}";
  $css .= "\/\/--><\/style>";
  return $css;
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
  $rh .= "<td><a href=\"" . $FW_ME . "\">FHEM:</a>$v</td>";
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
  # $rh = "<div id=\"left\">\n";
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
  my $row = 1;
  $rh = "<div id=\"content\">\n";
  $rh .= "<hr>\n";
  $rh .= "[RegEx] Type: \"$f_type\" Name: \"$f_name\" Reading: \"$f_reading\"\n";
  $rh .= "<hr>\n";
  my ($d,$r,$tr_class);
  my $th = undef;
  # Get Devices and Readings
  # $rh .= "<table class=\"VIEW\" WIDTH=\"85%\">\n";
  foreach $d (sort keys %defs){
  if($defs{$d}{TYPE} =~ m/$f_type/ && $d =~ m/$f_name/){
  # Weblink
    if($defs{$d}{TYPE} eq "weblink") {
      $rh .= "<table class=\"VIEW\">\n";
      $rh .= FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE});
      $rh .= "</table>\n";
    }
    else {
      foreach $r (sort keys %{$defs{$d}{READINGS}}) {
        if($r =~ m/$f_reading/) {
          $tr_class = $row?"odd":"even";
          if(!$th) {
            $rh .= "<br>\n";
            $rh .= "<table class=\"VIEW\">\n";
            # $rh .= "<table class=\"VIEW\" WIDTH=\"85%\">\n";
            $rh .= "<tr class=\"" . $tr_class . "\">";
            $rh .= "<td align=\"left\"><a href=\"$FW_ME?detail=$d\">$d</a></td>";
            $rh .= "<td></td>";
            $rh .= "<td>" . $defs{$d}{TYPE} . "</td>";
            $rh .= "<td>" . $defs{$d}{STATE} . "</td>";
            $rh .= "</tr>\n";
            $th = 1;
            $row = ($row+1)%2;
            $tr_class = $row?"odd":"even";
          }
          $rh .= "<tr class=\"" . $tr_class . "\">";
          $rh .= "<td></td>";
          $rh .= "<td>$r</td>";
          $rh .= "<td>" . $defs{$d}{READINGS}{$r}{VAL} . "</td>";
          $rh .= "<td>" . $defs{$d}{READINGS}{$r}{TIME} . "</td>";
          $rh .= "</tr>\n";
          $row = ($row+1)%2;
        }
      }
      $rh .= "</table>\n";
      # $rh .= "<br>\n";
    }
  }
  $th = undef;

  }
  # $rh .= "</table>\n";
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
1;

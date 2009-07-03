# Beispiel für FHEM PRIV-CGI Schnittstelle
#
# Danke an Rudi für die Schnittstelle....
#
# "Eigentlich wollte ich nur sehen, wie meine FHT's eingestellt sind,
# "und eine Übersicht aller vergbener FS20-Code's. ;-)"
#
# Das Modul verändert nichts an FHEM
# das Orginal-Mudol ist im CVS unter Contrib 99_priv_cgi.pm zu finden
#
# Beschreibung
# Es werden lediglich vorhanden Information aus FHEM in eigenen Ansichten/Listen dargestellt.
#
# Ansicht/List
# ALL
# Überblick über alle Devices
#
# FHT
# Übersicht aller FHT's
# Die eingestellten Schaltzeitpunkte an denen der FHT zwischen Tag- und Nacht-Temperatur wechslet; bzw. umgekehrt.
#
# FS20
# Übersicht alle FS20-Devices
#
# TH
# Temperatur & Humidity
# Alle Devices (die ich habe) die eine Temperatur oder Luftfeuchte messen (FHT,KS300,HMS,S300TH...)
#
# DUMMY (als Beispiel für eigene Functionen)
#   Überischt aller DUMMY-Devices
#
#
# Installation
#
# Modul ins FHEM-Modul Verzeichnis kopieren
# entweder FHEM neu starten
# oder "reload 99_priv_cgi.pm"
#

# Aufruf:
# Bsp.: FHEMWEB => http://localhost:8083/fhem
# PROC-CGI => http://localhost:8083/fhem/privcgi
#
#
# Eigene Erweiterungen implementieren:
# A. Ergänzung LIST-Funktion
#  - Eigene Funktion schreiben z.B. sub priv_cgi_my_function($)
#  - Eigenen Key festlegen z.B. myKey
#  - Function sub priv_cgi_Initialize($) ergänzen $data{$cgi_key}{TASK_LIST}{TYPE}{myKey} = "priv_cgi_my_function";
#  - reload 99_priv_cgi.pm
#
# B. Eigene Funktion
# - z.B. MyFunc
# - eigenen Key im HASH $data{$cgi_key}{TASK} erzeugen
# - $data{$cgi_key}{TASK}{MyFunc} = "Function_Aufruf"
##############################################
package main;

# call it whith http://localhost:8083/fhem/privcgi

use strict;
use warnings;
use vars qw(%data);

sub priv_cgi_Initialize($)
{
	my $cgi_key = "privcgi";
	my $fhem_url = "/" . $cgi_key ; 
#	$data{FWEXT}{$fhem_url} = "priv_cgi_callback";
	$data{FWEXT}{$fhem_url}{FUNC} = "priv_cgi_callback";
	$data{FWEXT}{$fhem_url}{LINK} = "privcgi";
	$data{FWEXT}{$fhem_url}{NAME} = "MyFHEM";
	$data{$cgi_key}{QUERY} = {};
    # Default:  in Case of /privcgi
	# Task=List&Type=FHT
	$data{$cgi_key}{default}{QUERY} = "Task=List&Type=ALL";
	# Dispatcher Functions
	# Task = List -> Call Function
	$data{$cgi_key}{TASK}{List} = "priv_cgi_list";
    # List -> Type -> Call Function
    $data{$cgi_key}{TASK_LIST}{TYPE} = {};;
    $data{$cgi_key}{TASK_LIST}{TYPE}{ALL} = "priv_cgi_print_all";
    $data{$cgi_key}{TASK_LIST}{TYPE}{FHT} = "priv_cgi_print_fht";
    $data{$cgi_key}{TASK_LIST}{TYPE}{FS20} = "priv_cgi_print_fs20";
	$data{$cgi_key}{TASK_LIST}{TYPE}{TH} = "priv_cgi_print_th";
#	$data{$cgi_key}{TASK_LIST}{TYPE}{DUMMY} = "priv_cgi_print_dummy";


}

sub
priv_cgi_callback($$)
{
  my ($htmlarg) = @_;
  my ($ret_html, $func,$qtask);
  my $cgikey = &priv_cgi_get_start($htmlarg);
  Log 0, "CGI-KEY: $cgikey";
  # Dispatch TASK... choose Function
  $qtask = $data{$cgikey}{QUERY}{Task};
  $func = $data{$cgikey}{TASK}{$qtask};
  Log 0, "Func: $func";
  no strict "refs";
  # Call Function
  $ret_html .= &$func($cgikey);
  use strict "refs";
  Log 1, "Got $htmlarg";
  return ("text/html; charset=ISO-8859-1", $ret_html);
}

sub
priv_cgi_get_start($)
{
 my $in = shift;
 my (@tmp,$n,$v,$cgikey,$param);
 # Aufruf mit oder ohne Argumente
 # /privcgi oder /privcgi?ToDo=List&What=FHT
 if($in =~ /\?/)
  {
  # Aufruf mit Argumenten: /privcgi?ToDo=List&What=FHT
  @tmp = split(/\?/, $in);
  $cgikey = shift(@tmp);
  $cgikey =~ s/\///;
  $param = shift(@tmp);
  }
 else 
 {
	$cgikey = $in;
	# Aufruf OHNE Argumenten: /privcgi
	$cgikey =~ s/\///;
	# Default Werte
	$param = $data{$cgikey}{default}{QUERY};
  }	
# Param nach $data{$cgikey}{QUERY} schreiben
Log 0, "PRIV-CGI: START -> param: " . $param;
 @tmp = split(/&/, $param);
 foreach my $pair(@tmp)
	{
	($n,$v) = split(/=/, $pair);
    Log 0, "PRIV-CGI: START -> param: $n - $v";
   $data{$cgikey}{QUERY}{$n} = $v;
   }
 return $cgikey;
 }


sub 
priv_cgi_html_head($)
{
# HTML-Content for HEAD
  my $cgikey = shift;
  my $html = "<!DOCTYPE html PUBLIC \"-\/\/W3C\/\/DTD HTML 4.01\/\/EN\" \"http:\/\/www.w3.org\/TR\/html4\/strict.dtd\">\n";
  $html .= "<html>\n";
  $html .= "<head>\n";
  $html .=  "<style type=\"text/css\"><!--";
  $html .= "\#hdr {margin: 0em 0em 1em 0em;padding: 0em 1em;background-color: \#CCCCCC;}";
  $html .= "\#left {float: left; width: 15%; padding: 1em;}";
  $html .= "\#right {float: left;width: 70%;}";
  $html .= "body {font-size: 14px;padding: 0px;margin: 0px;font-family: 'Courier New', Courier, Monospace;";
  $html .= "\/\/--><\/style>";
  $html .= "<title>FHEM PRIV-CGI<\/title>\n";
  $html .= "<\/head>\n";
  $html .= "<body>\n";
  return $html;
}

sub
priv_cgi_html_body_div_hdr($)
{
# HTML-Content BODY & DIV-ID HDR
  my $cgikey = shift;
  my $html = "<div id=\"hdr\">";
  $html .= "<h3><a href=\"/fhem\">FHEM</a></h3>\n";
  $html .= "<p style=\"font-size:8pt;\">";
  $html .= $attr{global}{version} . "<br></p>\n";
  $html .= "<hr><br>\n";
  return $html;
}

sub
priv_cgi_html_div_left($)
{
# HTML-Content BODY & DIV-ID LEFT
 my $cgikey = shift;
  my  $html = "<\/div>";
  $html .= "<div id=\"left\">";
  $html .= "<h3>Ansichten:<h3>";
  $html .= "<form method=\"get\" action=\"\/fhem\/privcgi\" name=\"myfhem\">\n";
  $html .= "<select name=\"Type\">\n";
  
  foreach my $d (sort keys %{$data{$cgikey}{TASK_LIST}{TYPE}}) {
  $html .= "<option value=\"$d\">$d</option>\n";
  }
  $html .= "</select>\n";
  $html .= "<input name=\"Task\" value=\"List\"type=\"submit\"><br>\n";
  $html .= "</form>\n";
  $html .= "<\/div>";
  return $html ;
}

sub
priv_cgi_list($) 
{
  my $cgikey = shift;
  my $html;
  Log 0,"PRIV_CGI_LIST: START";
  # HTML-HEAD
  $html = &priv_cgi_html_head($cgikey);
  # HTML-BODY-DIV-HDR
  $html .= &priv_cgi_html_body_div_hdr($cgikey);
  # HTML-BODY-DIV-ID-LEFT
  $html .= &priv_cgi_html_div_left($cgikey);
  my $type = $data{$cgikey}{QUERY}{Type};
  Log 0,"PRIV_CGI_LIST: TYPE = " . $type;
  my $func = $data{$cgikey}{TASK_LIST}{TYPE}{$type};
  Log 0,"PRIV_CGI_LIST: TYPE = $type -> Func -> $func";
  no strict "refs";
  # Call Function
  $html .= &$func;
  use strict "refs";
  
  # HTML-BODY-FOOTER
  $html .= priv_cgi_html_footer();
  return $html;
}
sub
priv_cgi_html_footer()
{
 # HTML-BODY Footer
  my $html = "<\/body>\n";
  $html .= "<\/html>\n";
  return $html;
}

sub priv_cgi_print_fs20() 
	{
  my $str = "<table summary=\"List of FS20 devices\">\n"; 
  $str .= "<tr ALIGN=LEFT><th>Name<\/th><th>Model<\/th><th>State<\/th><th>Code<\/th><th>Button<\/th><th>Room<\/th><\/tr>\n";
  $str .= "<colgroup>\n";
  $str .= "<col width=\"130\"><col width=\"130\"><col width=\"130\"><col width=\"130\">\n";
  $str .= "</colgroup>\n";
  foreach my $d (sort keys %defs) {
    next if($defs{$d}{TYPE} ne "FS20");
    $str .= "<tr ALIGN=LEFT><td>" . $d . "<\/td><td>" . $attr{$d}{model} . "<\/td><td>". $defs{$d}{STATE} . "<\/td><td>". $defs{$d}{XMIT} . "<\/td><td>". $defs{$d}{BTN} . "<\/td><td>". $attr{$d}{room} . "<\/td><\/tr>\n";
    }
    $str .= "<\/table>\n";
    return ($str);
	}
sub priv_cgi_print_fht()
  {
    my ($str,@fp);
    $str = "<table class=\"Fht\" summary=\"List of fht devices\">\n";
    $str .= "<tr ALIGN=LEFT><th>Name<\/th><th>Ventil<\/th><th>Ziel<\/th><th>Aktuell<\/th>" ;
	$str .= "<th>Nacht<\/th><th>Tag<\/th><th>Fenster<\/th><th>IODev<\/th><th>Time<\/th><th>CODE<\/th><\/tr>\n";
    # Init Tabel FHT-Program
    $fp[0] .= "<th></th>"; 
    $fp[1] .= "<td>Montag</td>"; 
    $fp[2] .= "<td></td>"; 
    $fp[3] .= "<td>Dienstag</td>";
    $fp[4] .= "<td></td>";
    $fp[5] .= "<td>Mittwoch</td>"; 
    $fp[6] .= "<td></td>"; 
    $fp[7] .= "<td>Donnerstag</td>";
    $fp[8] .= "<td></td>"; 
    $fp[9] .= "<td>Freitag</td>";
    $fp[10] .= "<td></td>";
    $fp[11] .= "<td>Samstag</td>";
    $fp[12] .= "<td></td>";
    $fp[13] .= "<td>Sonntag</td>";
    $fp[14] .= "<td></td>";

    
    # actuator desired-temp measured-temp night-temp day-temp windowopen-temp
    foreach my $d (sort keys %defs)
    {
    next if($defs{$d}{TYPE} ne "FHT");
    $str .= "<tr ALIGN=LEFT>" ;
    $str .= "<td>" . $d . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{READINGS}{"actuator"}{VAL} . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{READINGS}{"desired-temp"}{VAL} . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{READINGS}{"measured-temp"}{VAL} . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{READINGS}{"night-temp"}{VAL} . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{READINGS}{"day-temp"}{VAL} . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{READINGS}{"windowopen-temp"}{VAL} . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{IODev}{NAME} . "<\/td>" ;
    $str .= "<td>" . $defs{$d}{READINGS}{"actuator"}{TIME} . "<\/td>" ;
	$str .= "<td>" . $defs{$d}{CODE} . "<\/td>" ;
    $str .= "<\/tr>\n";
    # FHT-Programme
    no strict "subs";
    $fp[0] .= "<th>" . $d . "</th>";
    $fp[1] .= "<td>" . $defs{$d}{READINGS}{'mon-from1'}{VAL} . "-" . $defs{$d}{READINGS}{'mon-to1'}{VAL} . "</td>";
    $fp[2] .= "<td>" . $defs{$d}{READINGS}{'mon-from2'}{VAL} . "-" . $defs{$d}{READINGS}{'mon-to2'}{VAL} . "</td>";
    $fp[3] .= "<td>" . $defs{$d}{READINGS}{'tue-from1'}{VAL} . "-" . $defs{$d}{READINGS}{'tue-to1'}{VAL} . "</td>";
    $fp[4] .= "<td>" . $defs{$d}{READINGS}{'tue-from2'}{VAL} . "-" . $defs{$d}{READINGS}{'tue-to2'}{VAL} . "</td>";
    $fp[5] .= "<td>" . $defs{$d}{READINGS}{'wed-from1'}{VAL} . "-" . $defs{$d}{READINGS}{'wed-to1'}{VAL} . "</td>";
    $fp[6] .= "<td>" . $defs{$d}{READINGS}{'wed-from2'}{VAL} . "-" . $defs{$d}{READINGS}{'wed-to2'}{VAL} . "</td>";
    $fp[7] .= "<td>" . $defs{$d}{READINGS}{'thu-from1'}{VAL} . "-" . $defs{$d}{READINGS}{'thu-to1'}{VAL} . "</td>";
    $fp[8] .= "<td>" . $defs{$d}{READINGS}{'thu-from2'}{VAL} . "-" . $defs{$d}{READINGS}{'thu-to2'}{VAL} . "</td>";
    $fp[9] .= "<td>" . $defs{$d}{READINGS}{'fri-from1'}{VAL} . "-" . $defs{$d}{READINGS}{'fri-to1'}{VAL} . "</td>";
    $fp[10] .= "<td>" . $defs{$d}{READINGS}{'fri-from2'}{VAL} . "-" . $defs{$d}{READINGS}{'fri-to2'}{VAL} . "</td>";
    $fp[11] .= "<td>" . $defs{$d}{READINGS}{'sat-from1'}{VAL} . "-" . $defs{$d}{READINGS}{'sat-to1'}{VAL} . "</td>";
    $fp[12] .= "<td>" . $defs{$d}{READINGS}{'sat-from2'}{VAL} . "-" . $defs{$d}{READINGS}{'sat-to2'}{VAL} . "</td>";
    $fp[13] .= "<td>" . $defs{$d}{READINGS}{'sun-from1'}{VAL} . "-" . $defs{$d}{READINGS}{'sun-to1'}{VAL} . "</td>";
    $fp[14] .= "<td>" . $defs{$d}{READINGS}{'sun-from2'}{VAL} . "-" . $defs{$d}{READINGS}{'sun-to2'}{VAL} . "</td>";
    use strict "subs";
    }
    $str .= "<\/table>\n";
    
    $str .= "<br>\n";
    $str .= "<table>\n";
    $str .= "<colgroup>\n";
    $str .= "<col width=\"130\"><col width=\"130\"><col width=\"130\"><col width=\"130\">\n";
    $str .= "<col width=\"130\"><col width=\"130\"><col width=\"130\"><col width=\"130\">\n";
    $str .= "</colgroup>\n";

    foreach (@fp) {
      $str .= "<tr ALIGN=LEFT>" . $_ . "</tr>\n";
      }
    $str .= "<\/table>\n";
   return ($str);
  } 
sub priv_cgi_print_dummy()
{
my $str = "<table summary=\"List of Dummy devices\">\n";
    $str .= "<colgroup>\n";
    $str .= "<col width=\"130\"><col width=\"130\">\n";
    $str .= "</colgroup>\n";
    $str .= "<tr ALIGN=LEFT><th>Name<\/th><th>State<\/th><\/tr>\n";
    foreach my $d (keys %defs) {
    	next if($defs{$d}{TYPE} ne "dummy");
    $str .= "<tr ALIGN=LEFT><td>" . $d . "<\/td><td>". $defs{$d}{STATE} . "<\/td><\/tr>\n";}
    $str .= "<\/table>\n";
  return ($str);

}

sub priv_cgi_print_th() 
{
  # List All-Devices with Temp od Humidity
  my ($type,$str,$s,$t,$h,$i);
  $str = "<table summary=\"List of ALL devices\">\n";
  $str .= "<tr ALIGN=LEFT><th>Name</th><th>Temperature</th><th>Humidity</th><th>Information</th><th>Type</th><th>Room</th></tr>";
  foreach my $d (sort keys %defs) {
    $type = $defs{$d}{TYPE};
	next if(!($type =~ m/^(FHT|HMS|KS300|CUL_WS)/));
	#next if($type ne "FHT" || $type ne "HMS" || $type ne "KS300" || $type ne "CUL_WS");
    $t = "";
    $h = "";
    $i = "";
    if ($type eq "FHT"){
                        $i = $defs{$d}{'READINGS'}{'warnings'}{'VAL'};
                        $t = $defs{$d}{'READINGS'}{'measured-temp'}{'VAL'};
                        $t =~ s/\(Celsius\)//;};
    if ($type eq "HMS" || $type eq "CUL_WS"){
                        $i = $defs{$d}{'READINGS'}{'battery'}{'VAL'};
                        $t = $defs{$d}{'READINGS'}{'temperature'}{'VAL'};
                        $t =~ s/\(Celsius\)//;
                        $h = $defs{$d}{'READINGS'}{'humidity'}{'VAL'};
                        $h =~ s/\(%\)//;};
    if ($type eq "KS300"){
                        $i = "Raining: " . $defs{$d}{'READINGS'}{'israining'}{'VAL'};
                        $i =~ s/\(yes\/no\)//;
                        $t = $defs{$d}{'READINGS'}{'temperature'}{'VAL'};
                        $t =~ s/\(Celsius\)//;
                        $h = $defs{$d}{'READINGS'}{'humidity'}{'VAL'};
                        $h =~ s/\(%\)//;};
    $str .= "<tr ALIGN=LEFT><td>" . $d . "<\/td><td>". $t . "<\/td><td>". $h . "<\/td><td>". $i . "<\/td><td>". $type . "<\/td><td>". $attr{$d}{room} . "<\/td><\/tr>\n";
    }
    $str .= "<\/table>\n";
    return ($str);
}
sub priv_cgi_print_all() 
{
  # List All-Devices
  my ($type,$str,$s,$t,$h,$i);
  $str = "<table summary=\"List of ALL devices\">\n";
  $str .= "<tr ALIGN=LEFT><th>Name</th><th>State</th><th>Type</th><th>Model</th><th>Room</th><th>IODev</th></tr>";
  foreach my $d (sort keys %defs)
	{
	$str .= "<tr ALIGN=LEFT><td>" . $d . "<\/td><td>". $defs{$d}{STATE} . "<\/td><td>". $defs{$d}{TYPE} . "<\/td><td>". $attr{$d}{model} . "<\/td><td>". $attr{$d}{room} . "<\/td><td>". $defs{$d}{IODev}{NAME} . "<\/td><\/tr>\n";
	}
  $str .= "<\/table>\n";
  return ($str);
}
1;

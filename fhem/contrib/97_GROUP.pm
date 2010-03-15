################################################################################
#*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA
# 97 GROUP for the 01_FHEMWEB module
# Feedback: http://groups.google.com/group/fhem-users 
# Logging to RRDs
# Autor: a[PUNKT]r[BEI]oo2p[PUNKT]net
# Stand: 26.01.2010
# Version: 0.5.0
#*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA
################################################################################
# Usage:
# define <New-Group-Name> GROUP <CATEGORY>
# set <New-Group-Name> ADD/DEL <NAME>:<DEVICENAME>:<READING>
#
# Spezial Categories:
# SHOWLEFT -> This cat shows  Name und Value of READING on the Left-Side
# (DIV-Left) Example:
#
# define 01.OG.SCHLAFZIMMMER GROUP 01.OG
# set GRP001 ADD FHT8v:FHT_1234:actuator
# set GRP001 ADD Temperatur:CUL_WS_3:temperature
# set GRP001 ADD Fenster:CUL_FHTTFK_1234:Window
#
# define 01.OG.BAD GROUP 01.OG
# set GRP001 ADD Temperatur:CUL_WS_4:temperature
# set GRP001 ADD Luftfeuchte:CUL_WS_4:humidity
#
################################################################################
package main;
use strict;
use warnings;
use Data::Dumper;
use vars qw(%data);
#-------------------------------------------------------------------------------
sub GROUP_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn} = "GRP_Define";
  $hash->{SetFn}    = "GRP_Set";
  $hash->{UndefFn}   = "GRP_Undef";
  $hash->{AttrList}  = "loglevel:0,5";
  # CGI
  my $name = "GROUPS";
  my $fhem_url = "/" . $name ; 
  $data{FWEXT}{$fhem_url}{FUNC} = "GRP_CGI";
  $data{FWEXT}{$fhem_url}{LINK} = $name;
  $data{FWEXT}{$fhem_url}{NAME} = $name;
  
  # Rebuild
  delete $hash->{defptr};
  delete $hash->{conf};
  foreach my $d (sort keys %defs) {
    Log 0, "GROUP INIT $d:" . $defs{$d}{TYPE};
    next if(!defined($defs{$d}{TYPE}));
    next if($defs{$d}{TYPE} ne "GROUP");
    my $cat = $defs{$d}{STATE};
    my $ret = &GRP_HANDLE_CAT($d,$cat);
  }

  return undef;
}
#-------------------------------------------------------------------------------
sub GRP_Define(){
  # define <GROUP-NMAE> GROUP <CATEGORY-NAME>
  # If no Cat is defined:<GROUP-NMAE> = <CATEGORY-NAME>
  # define <GROUP-NMAE> GROUP <CONF> SHOWLEFT
  # Show this Values in DIV-Container LEFT 
  my ($self, $defs) = @_;
  Log 0, "GROUP DEFINE " . Dumper(@_);
  my $name = $self->{NAME};
  # defs = $a[0] <GROUP-NAME> $a[1] GROUP $a[2]<CATEGORY-NAME> $a[3] SHOWLEFT
  # $VAR2 = 'L01 GROUP SHOWLEFT';
  my @a = split(/ /, $defs);
  # CATEGORY
  my $cat = $name;
  if(int(@a) gt 2){$cat = $a[2];}
  Log 0, "GROUP DEFINE CAT:" . $cat;
  my $ret = &GRP_HANDLE_CAT($name,$cat);
  # Save cat to State
  $self->{STATE} = $cat;
  #Default ROOM DEF.GROUP
  $attr{$self->{NAME}}{room} = "DEF.GROUP";
  return undef;
  }
#-------------------------------------------------------------------------------
sub GRP_Undef(){
  my ($self, $name) = @_;
  ??? empty CAT is left ??? 
  if(defined($modules{GROUP}{defptr}{$name})) {
    delete $modules{GROUP}{defptr}{$name};
  }
  if(defined($modules{GROUP}{conf})) {
    foreach my $c (sort keys %{$modules{GROUP}{conf}}){
      if(defined($modules{GROUP}{conf}{$c}{$name})){
      delete $modules{GROUP}{conf}{$c}{$name};
      }
    }
  }
  return undef;
}
#-------------------------------------------------------------------------------
sub GRP_Set()
 {
  # set <NAME> ADD/DEL <NAME>:<DEVICE-NAME>:<READING>
  # @a => a[0]:<NAME>; a[1]=ADD; a[2]= <DEVICE-NAME>:<READING>
  my ($self, @a) = @_;
  # FHEMWEB Frage....Auswahliste
  Log 0, "GROUP SET " . Dumper(@_);
  return "GROUP Unknown argument $a[1], choose one of ". join(" ",sort keys %{$self->{READINGS}}) if($a[1] eq "?");
  # ADD
  if($a[1] eq "ADD") {
  my ($name,$dev,$reading) = split(/:/,$a[2]);
  if(!defined($defs{$dev})){return "Device unkwon";}
  Log 0 , "GRP SET ". $a[0] . ":" . $a[1] . ":" . $dev . ":" . $reading;
  $self->{READINGS}{$name}{VAL} = $dev . ":" . $reading;
  $self->{READINGS}{$name}{TIME} = TimeNow();
  }
  if($a[1] eq "DEL") {
  # @a => a[0]:<NAME>; a[1]=DEL; a[2]= <READING>
  delete $self->{READINGS}{$a[2]};
  }
  # Set GROUP-CAT
  # set <NAME> CAT <CATEGORY-NAME>
  if($a[1] eq "CAT") {
    $self->{STATE} = $a[2];
  }
  return undef;
}
#-------------------------------------------------------------------------------
sub GRP_CGI()
{
  my ($htmlarg) = @_;
  # htmlarg = /GROUPS/<CAT-NAME>
  my $Cat = GRP_CGI_DISPTACH_URL($htmlarg);
  my ($ret_html);
  $ret_html = "<!DOCTYPE html PUBLIC \"-\/\/W3C\/\/DTD HTML 4.01\/\/EN\" \"http:\/\/www.w3.org\/TR\/html4\/strict.dtd\">\n";
  $ret_html .= "<html>\n";
  $ret_html .= "<head>\n";
  $ret_html .= &GRP_CGI_CSS();
  $ret_html .= "<title>FHEM GROUPS<\/title>\n";
  $ret_html .= "<link href=\"$__ME/style.css\" rel=\"stylesheet\"/>\n";
  $ret_html .= "<\/head>\n";
  $ret_html .= "<body>\n";
  # DIV HDR
  $ret_html .= &GRP_CGI_TOP($Cat);
  # DIV LEFT
  $ret_html .= &GRP_CGI_LEFT($Cat);
  # DIV RIGHT
  $ret_html .= &GRP_CGI_RIGHT($Cat);
  # HTML
  $ret_html .= "</body>\n";
  $ret_html .= "</html>\n";
  return ("text/html; charset=ISO-8859-1", $ret_html);
}
#-------------------------------------------------------------------------------
sub GRP_CGI_CSS() {
  my $css;
  $css   =  "<style type=\"text/css\"><!--\n";
  $css .= "\#left {float: left; width: 15%; height:100%;}\n";
  $css .= "table.GROUP { border:thin solid; background: #E0E0E0;}\n";
  $css .= "table.GROUP tr.odd { background: #F0F0F0;}\n";
  $css .= "\/\/--><\/style>";
  #$css = "<link href=\"$__ME/group.css\" rel=\"stylesheet\"/>\n";
  return $css;
}
#-------------------------------------------------------------------------------
sub GRP_CGI_TOP($) {
  my $CAT = shift(@_);
  # rh = return-Html
  my $rh;
  $rh = "<div id=\"hdr\">\n";
  $rh .= "<form method=\"get\" action=\"" . $__ME . "\">\n";
  $rh .= "<table WIDTH=\"100%\">\n";
  $rh .= "<tr>";
  $rh .= "<td><a href=\"" . $__ME . "\">FHEM:</a>$CAT</td>";
  $rh .= "<td><input type=\"text\" name=\"cmd\" size=\"30\"/></td>";
  $rh .= "</tr>\n";
  $rh .= "</table>\n";
  $rh .= "</form>\n";
  $rh .= "<br>\n";
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub GRP_CGI_LEFT(){
  # rh = return-Html
  my $rh;
  $rh = "<div id=\"left\">\n";
  # Print Groups
  $rh .= "<table class=\"room\">\n";
  foreach my $g (sort keys %{$modules{GROUP}{defptr}}){
    $rh .= "<tr><td>";
    $rh .= "<a href=\"" . $__ME . "/GROUPS/$g\">$g</a></h3>";
    $rh .= "</td></tr>\n";
  }
  $rh .= "</table><br>\n";
  #SHOWLEFT
  if(defined($modules{GROUP}{conf}{SHOWLEFT})){
    $rh .= "<table class=\"room\">\n";
    foreach my $g (sort keys %{$modules{GROUP}{conf}{SHOWLEFT}}){
      #Tabelle
      $rh .= "<tr><th>$g</th><th></th></tr>\n";
      foreach my $r (sort keys %{$defs{$g}{READINGS}}){
        # Name | Value
        my ($device,$reading) = split(/:/,$defs{$g}{READINGS}{$r}{VAL});
        my $value = $defs{$device}{READINGS}{$reading}{VAL};
        $rh .= "<tr><td>$r</td><td>$value</td></tr>\n"
      }
    }
    $rh .= "</table>\n";
  }
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub GRP_CGI_RIGHT(){
  my ($CAT) = @_;
  Log 0,"GROUP CGI-RIGHT CAT: $CAT";
  my ($name,$device,$reading,$vtype,$value,$vtime,$rh,$tr_class);
  # rh = return-Html
  my $row = 1;
  # Table
  # GROUP
  # Name | Value | Time | Device-Type
  $rh = "<div id=\"right\">\n";
  # Category -> DEVICE
  foreach my $c (sort keys %{$modules{GROUP}{defptr}{$CAT}}){
    # Log 0,"GROUP CGI-RIGHT DEV: $c";
    $rh .= "<table class=\"GROUP\">\n";
    $rh .= "<tr>";
    $rh .= "<th align=\"left\" WIDTH=\"10%\">$c</th>";
    $rh .= "<th align=\"left\" WIDTH=\"10%\"></th>";
    $rh .= "<th align=\"left\" WIDTH=\"10%\"></th>";
    $rh .= "<th align=\"left\" WIDTH=\"10%\"></th>";
    $rh .= "</tr>\n";
    # GROUP -> READING
      foreach my $r (sort keys %{$defs{$c}{READINGS}}){
        # Name | Value
        ($device,$reading) = split(/:/,$defs{$c}{READINGS}{$r}{VAL});
        $value = $defs{$device}{READINGS}{$reading}{VAL};
        $vtime = $defs{$device}{READINGS}{$reading}{TIME};
        $vtype = $defs{$device}{TYPE};
        $tr_class = $row?"odd":"even";
        $rh .= "<tr class=\"" . $tr_class . "\"><td>$r</td><td>$value</td><td>$vtime</td><td>$vtype</td></tr>\n";
        $row = ($row+1)%2;
      }
    $rh .= "</table><br>\n";
  }
  $rh .= "</div>\n";
  return $rh;
}
#-------------------------------------------------------------------------------
sub GRP_CGI_DISPTACH_URL($){
  my ($htmlarg) = @_;
  # htmlarg = /GROUPS/<GRP-NAME>
  Log 0,"GRP URL-DISP: " . $htmlarg;
  my @params = split(/\//,$htmlarg);
  my $CAT = undef;
  if($params[2]) {
    $CAT = $params[2];
    Log 0,"GRP URL-DISP-CAT: " . $CAT;}
  return $CAT;
}
#-------------------------------------------------------------------------------
sub GRP_HANDLE_CAT($$){
  my($device,$cat) = @_;
  Log 0,"GRP CAT-DISP: $device:$cat";
  # Normal Categories -> %modules{GROUP}{defptr}{<CAT-NAME>}{<GROUP-DEVICE-NAME>}
  # Spezial Categories -> %modules{GROUP}{conf}{<CAT-NAME>}{<GROUP-DEVICE-NAME>}
  if($cat eq "SHOWLEFT") {
    Log 0,"GRP CAT-DISP-> SHOWLEFT -> $cat -> $device";
    $modules{GROUP}{conf}{$cat}{$device} = 1;
    return undef;
  }
  $modules{GROUP}{defptr}{$cat}{$device} = 1;
  return undef;
}
1;

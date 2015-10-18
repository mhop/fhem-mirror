################################################################
#+$Id$
#+vim: ts=2:et
#
#+ (c) 2012 Copyright: Martin Fischer (m_fischer at gmx dot de)
#+ All rights reserved
#
#+ This script free software; you can redistribute it and/or modify
#+ it under the terms of the GNU General Public License as published by
#+ the Free Software Foundation; either version 2 of the License, or
#  any later version.
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
################################################################
package main;
use strict;
use warnings;
use Config;


sub CommandFheminfo($$);

########################################
sub
fheminfo_Initialize($$)
{
  my %hash = (
    Fn  => "CommandFheminfo",
    Hlp => "[send],show or send Fhem statistics",
  );
  $cmds{fheminfo} = \%hash;
}

########################################
sub
CommandFheminfo($$)
{
  my ($cl,$param) = @_;

  # split arguments
  my @args = split(/ +/,$param);

  my $name = "fheminfo";
  my %info;

  my $module = "HTTP::Request::Common";
  my $err = "Missing perl module '$module'. Please install this module first.";
  if(!checkModule($module)) {
    Log 1, "$name $err";
    return $err;
  }

  $module = "LWP::UserAgent";
  if(!checkModule($module)) {
    Log 1, "$name $err";
    return $err;
  }

  return "Unknown argument $args[0], usage: fheminfo [send]"
    if(@args && lc($args[0]) ne "send");

  return "Won't send, as sendStatistics is set to 'never'."
    if(@args && 
       lc($args[0]) eq "send" &&
       lc(AttrVal("global","sendStatistics","")) eq "never");

  my $branch   = "DEVELOPMENT"; # UNUSED
  my $release  = "5.6";
  my $os       = $^O;
  my $arch     = $Config{"archname"};
  my $perl     = $^V;
  my $uniqueID = getUniqueId();
  my $sendStatistics = AttrVal("global","sendStatistics",undef);
  my $moddir   = $attr{global}{modpath}."/FHEM";
  my $upTime = fhemUptime();
  
  my %official_module;

  opendir(DH, $moddir) || return("$moddir: $!");
  foreach my $file (grep /^controls.*.txt$/, readdir(DH)) {
    open(FH, "$moddir/$file") || next;
    while(my $l = <FH>) {
      $official_module{$1} = 1 if($l =~ m+^UPD.* FHEM/\d\d_(.*).pm+);
    }
    close(FH);
  }
  closedir(DH);
  return "Can't read FHEM/controls_fhem.txt, execute update first."
        if(!%official_module);

  foreach my $d (sort keys %defs) {
    my $n = $defs{$d}{NAME};
    my $t = $defs{$d}{TYPE};
    my $m = "unknown";
    $m = $defs{$d}{model} if( defined($defs{$d}{model}) );
    $m = AttrVal($n,"model",$m);
    if($official_module{$t} && !$defs{$d}{TEMPORARY} && !$attr{$d}{ignore}) {
      $info{modules}{$t}{$n} = $m;
    }
  }

  $info{modules}{configDB}{configDB} = 'unknown' if (configDBUsed());

  my $str;
  $str  = "Fhem info:\n";
  $str .= sprintf("  Release%*s: %s\n",2," ",$release);
  $str .= sprintf("  OS%*s: %s\n",7," ",$os);
  $str .= sprintf("  Arch%*s: %s\n",5," ",$arch);
  $str .= sprintf("  Perl%*s: %s\n",5," ",$perl);
  $str .= sprintf("  uniqueID%*s: %s\n",0," ",$uniqueID);
  $str .= sprintf("  upTime%*s: %s\n",3,"  ",$upTime); 
  $str .= "\n";

  my $contModules;
  my $contModels;
  my $modStr;
  my @modules = keys %{$info{modules}};
  my $length = (reverse sort { $a <=> $b } map { length($_) } @modules)[0];

  $str .= "Defined modules:\n";
  foreach my $t (sort keys %{$info{modules}}) {
    my $c = scalar keys %{$info{modules}{$t}};
    my @models;
    foreach my $n (sort keys %{$info{modules}{$t}}) {
      my $model = $info{modules}{$t}{$n};
      if($model ne "unknown" && $t ne "dummy") {
        push(@models,$model) if(!grep {$_ =~ /$model/} @models);
      }
    }
    $str .= sprintf("  %s%*s: %d\n",$t,$length-length($t)+1," ",$c);
    if(@models != 0) {
      $modStr .= sprintf("  %s%*s: %s\n",
                        $t,$length-length($t)+1," ", join(",",sort @models));
      $contModels .= join(",",sort @models)."|";
    }
    $contModules .= "$t:$c|";
  }

  if($modStr) {
    $str .= "\n";
    $str .= "Defined models per module:\n";
    $str .= $modStr;
  }

  my $td = (lc(AttrVal("global", "sendStatistics", "")) eq "onupdate") ?
                "yes" : "no";

  $str .= "\n";
  $str .= "Transmitting this information during an update: $td\n";
  $str .= "You can change this via the global attribute sendStatistics\n";

  if(@args != 0 && $args[0] eq "send") {
    my $uri = "http://fhem.de/stats/statistics.cgi";
    my $req = HTTP::Request->new("POST",$uri);
    $req->content_type("application/x-www-form-urlencoded");
    my $contInfo;
    $contInfo  = "Release:$release|";
    $contInfo .= "Branch:$branch|";
    $contInfo .= "OS:$os|";
    $contInfo .= "Arch:$arch|";
    $contInfo .= "Perl:$perl";
    chop($contModules);
    if(!$contModels) {
      $req->content("uniqueID=$uniqueID&system=$contInfo&modules=$contModules");
    } else {
      chop($contModels);
      $req->content("uniqueID=$uniqueID&system=$contInfo&modules=$contModules&models=$contModels");
    }
 
    my $ua  = LWP::UserAgent->new(
        agent => "Fhem/$release",
        timeout => 60);
    my $res = $ua->request($req);

    $str .= "\nserver response: ";
    if($res->is_success) {
      $str .= $res->content."\n";
    } else {
      $str .= $res->status_line."\n";
    }
  }

  return $str;
}

########################################
sub checkModule($) {
  my $module = shift;
  eval("use $module");

  if($@) {
    return(0);
  } else {
    return(1);
  }
}

sub 
fhemUptime()
{
  my $diff = time - $fhem_started;
  my ($d,$h,$m,$ret);
  
  ($d,$diff) = _myDiv($diff,86400);
  ($h,$diff) = _myDiv($diff,3600);
  ($m,$diff) = _myDiv($diff,60);

  $ret  = "";
  $ret .= "$d days, " if($d >  1);
  $ret .= "1 day, "   if($d == 1);
  $ret .= sprintf("%02s:%02s:%02s", $h, $m, $diff);

  return $ret;
}

sub 
_myDiv($$)
{
  my ($p1,$p2) = @_;
  return (int($p1/$p2), $p1 % $p2);
}

1;

=pod
=begin html

<a name="fheminfo"></a>
<h3>fheminfo</h3>
<ul>
  <code>fheminfo [send]</code>
  <br>
  <br>
    fheminfo displays information about the system and FHEM definitions.
  <br>
  <br>
    The optional parameter <code>send</code> transmitts the collected data
    to a central server in order to support the development of FHEM. The
    transmitted data is processed graphically. The results can be viewed
    on <a href="http://fhem.de/stats/statistics.html">http://fhem.de/stats/statistics.html</a>.
    Based on the IP address, the approximate location is determined with
    an accuracy of about 40-80 km. The IP address is not saved.
  <br>
  <br>
    Features:<br>
    <ul>
      <li>Operating System Information</li>
      <li>Hardware architecture</li>
      <li>Installed Perl version</li>
      <li>Installed FHEM release</li>
      <li>Defined modules (only official FHEM Modules are counted)</li>
      <li>Defined models per module</li>
    </ul>
  <br>
    Example:
    <pre>
      fhem&gt; fheminfo
      Fhem info:
        Release  : 5.3
        OS       : linux
        Arch     : i686-linux-gnu-thread-multi-64int
        Perl     : v5.14.2
        uniqueID : 87c5cca38dc75a4f388ef87bdcbfbf6f

      Defined modules:
        ACU        : 1
        CUL        : 1
        CUL_FHTTK  : 12
        CUL_HM     : 66
        CUL_WS     : 3
        FHEM2FHEM  : 1
        FHEMWEB    : 3
        FHT        : 9
      [...]
        at         : 4
        autocreate : 1
        dummy      : 23
        notify     : 54
        structure  : 3
        telnet     : 2
        watchdog   : 9
        weblink    : 17
      
      Defined models per module:
        CUL        : CUN
        CUL_FHTTK  : FHT80TF
        CUL_HM     : HM-CC-TC,HM-CC-VD,HM-LC-DIM1T-CV,HM-LC-DIM1T-FM,HM-LC-SW1-PL,[...]
        CUL_WS     : S555TH
        FHT        : fht80b
        FS20       : fs20pira,fs20s16,fs20s4a,fs20sd,fs20st
        HMS        : hms100-mg,hms100-tf,hms100-wd
        KS300      : ks300
        OWSWITCH   : DS2413
    </pre>
  <br>

  <a name="fheminfoattr"></a>
  <b>Attributes</b>
  <br>
  <br>
    The following attributes are used only in conjunction with the
    <code>send</code> parameter. They are set on <code>attr global</code>.
  <br>
  <br>
  <ul>
    <li>sendStatistics<br>
      This attribute is used in conjunction with the <code>update</code> command.
      <br>
      <code>onUpdate</code>: transfer of data on every update (recommended setting).
      <br>
      <code>manually</code>: manually transfer of data via the <code>fheminfo send</code> command.
      <br>
      <code>never</code>: prevents transmission of data at anytime.
    </li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="fheminfo"></a>
<h3>fheminfo</h3>
<ul>
  <code>fheminfo [send]</code>
  <br>
  <br>
    fheminfo zeigt Informationen &uuml;ber das System und FHEM Definitionen an.
  <br>
  <br>
    Der optionale Parameter <code>send</code> &uuml;bertr&auml;gt die Informationen
    an einen zentralen Server um die Entwicklung von FHEM zu unterst&uuml;tzen.
    Die &uuml;bermittelten Daten werden grafisch aufbereitet und k&ouml;nnen auf
    <a href="http://fhem.de/stats/statistics.html">http://fhem.de/stats/statistics.html</a>
    abgerufen werden. Anhand der IP-Adresse wird der ungef&auml;hre Standort mit
    einer Genauigkeit von ca. 40-80 km ermittelt. Die IP-Adresse wird nicht gespeichert.
  <br>
  <br>
    Eigenschaften:<br>
    <ul>
      <li>Eingesetztes Betriebssystem</li>
      <li>Hardware Architektur</li>
      <li>Installierte Perl Version</li>
      <li>Installierte FHEM release</li>
      <li>Definierte Module (nur offizielle FHEM Module werden ermittelt)</li>
      <li>Definierte Modelle je Modul</li>
    </ul>
  <br>
    Beispiel:
    <pre>
      fhem&gt; fheminfo
      Fhem info:
        Release  : 5.3
        OS       : linux
        Arch     : i686-linux-gnu-thread-multi-64int
        Perl     : v5.14.2
        uniqueID : 87c5cca38dc75a4f388ef87bdcbfbf6f

      Defined modules:
        ACU        : 1
        CUL        : 1
        CUL_FHTTK  : 12
        CUL_HM     : 66
        CUL_WS     : 3
        FHEM2FHEM  : 1
        FHEMWEB    : 3
        FHT        : 9
      [...]
        at         : 4
        autocreate : 1
        dummy      : 23
        notify     : 54
        structure  : 3
        telnet     : 2
        watchdog   : 9
        weblink    : 17
      
      Defined models per module:
        CUL        : CUN
        CUL_FHTTK  : FHT80TF
        CUL_HM     : HM-CC-TC,HM-CC-VD,HM-LC-DIM1T-CV,HM-LC-DIM1T-FM,HM-LC-SW1-PL,[...]
        CUL_WS     : S555TH
        FHT        : fht80b
        FS20       : fs20pira,fs20s16,fs20s4a,fs20sd,fs20st
        HMS        : hms100-mg,hms100-tf,hms100-wd
        KS300      : ks300
        OWSWITCH   : DS2413
    </pre>
  <br>

  <a name="fheminfoattr"></a>
  <b>Attribute</b>
  <br>
  <br>
    Die folgenden Attribute werden nur in Verbindung mit dem Parameter
    <code>send</code> genutzt. Sie werden über <code>attr global</code> gesetzt.
  <br>
  <br>
  <ul>
    <li>sendStatistics<br>
      Dieses Attribut wird in Verbindung mit dem <code>update</code> Befehl verwendet.
      <br>
      <code>onUpdate</code>: &Uuml;bertr&auml;gt die Daten bei jedem Update (empfohlene Einstellung).
      <br>
      <code>manually</code>: Manuelle &Uuml;bertr&auml;gung der Daten &uuml;ber <code>fheminfo send</code>.
      <br>
      <code>never</code>: Verhindert die &Uuml;bertr&auml;gung der Daten.
    </li>
    <br>
  </ul>
</ul>

=end html_DE
=cut

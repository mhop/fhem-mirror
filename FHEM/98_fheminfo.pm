################################################################
# $Id$
# vim: ts=2:et
#
#  (c) 2012 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
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
  if(!eval "require FhemUtils::release") {
    require release;
  }

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

  return "Unknown argument $args[0], usage: fheminfo [send]" if(@args && lc($args[0]) ne "send");

  my $branch   = $DISTRIB_BRANCH;
  my $release  = $DISTRIB_RELEASE;
  my $os       = $^O;
  my $arch     = $Config{"archname"};
  my $perl     = $^V;
  my $uniqueID = AttrVal("global","uniqueID",join "", map { unpack "H*", chr(rand(256)) } 1..16);
  my $sendStatistics = AttrVal("global","sendStatistics",1);

  $attr{global}{uniqueID} = $uniqueID;
  $attr{global}{sendStatistics} = $sendStatistics;

  my $ret      = checkConfigFile($uniqueID);

  return $ret if($ret);

  foreach my $d (sort keys %defs) {
    my $n = $defs{$d}{NAME};
    my $t = $defs{$d}{TYPE};
    my $m = AttrVal($n,"model","unknown");
    $info{modules}{$t}{$n} = $m;
  }

  my $str;
  $str  = "Fhem info:\n";
  $str .= sprintf("  Release%*s: %s\n",2," ",$release);
  $str .= sprintf("  Branch%*s: %s\n",3," ",$branch);
  $str .= sprintf("  OS%*s: %s\n",7," ",$os);
  $str .= sprintf("  Arch%*s: %s\n",5," ",$arch);
  $str .= sprintf("  Perl%*s: %s\n",5," ",$perl);
  $str .= sprintf("  uniqueID%*s: %s\n",0," ",$uniqueID);
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
      if($model ne "unknown") {
        push(@models,$model) if(!grep {$_ =~ /$model/} @models);
      }
    }
    $str .= sprintf("  %s%*s: %d\n",$t,$length-length($t)+1," ",$c);
    if(@models != 0) {
      $modStr .= sprintf("  %s%*s: %s\n",$t,$length-length($t)+1," ",join(",",sort @models));
      $contModels .= join(",",sort @models)."|";
    }
    $contModules .= "$t:$c|";
  }

  if($modStr) {
    $str .= "\n";
    $str .= "Defined models per module:\n";
    $str .= $modStr;
  }

  $ret = $str;

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

    $ret .= "\nserver response: ";
    if($res->is_success) {
      $ret .= $res->content."\n";
    } else {
      $ret .= $res->status_line."\n";
    }
  }

  return $ret;
}

########################################
sub checkConfigFile($) {
  my $uniqueID = shift;
  my $name = "fheminfo";
  my $configFile = AttrVal("global","configfile","");

  if($configFile) {
    my $fh;
    if(!open($fh,"<".$configFile)) {
      return "Can't open $configFile: $!";
    }

    my @currentConfig = <$fh>;
    close $fh;

    if(!grep {$_ =~ /uniqueID/} @currentConfig) {
      my @newConfig;
      my $done = 0;

      foreach my $line (@currentConfig) {
        push(@newConfig,$line);
        if($line =~ /modpath/ && $done == 0) {
          push(@newConfig,"attr global uniqueID $uniqueID\n");
          push(@newConfig,"attr global sendStatistics 1\n");
          $done = 1;
        }
      }

      if(!open($fh,">".$configFile)) {
        return "Can't open $configFile: $!";
      }

      foreach (@newConfig) {
        print $fh $_;
      }
      close $fh;
      Log 1, "$name global attributes 'uniqueID' and 'sendStatistics' added to configfile $configFile";
    }
  }

}

sub checkModule($) {
  my $module = shift;
  eval("use $module");

  if($@) {
    return(0);
  } else {
    return(1);
  }
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
    on <a href="http://fhem.de/stats/statistics.cgi">http://fhem.de/stats/statistics.cgi</a>.
    Based on the IP address, the approximate location is determined with
    an accuracy of about 40-80 km. The IP address is not saved.
  <br>
  <br>
    Features:<br>
    <ul>
      <li>Operating System Information</li>
      <li>Hardware architecture</li>
      <li>Installed Perl version</li>
      <li>Installed FHEM release and branch</li>
      <li>Defined modules</li>
      <li>Defined models per module</li>
    </ul>
  <br>
    Example:
    <pre>
      fhem&gt; fheminfo
      Fhem info:
        Release  : 5.3
        Branch   : DEVELOPMENT
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
    <li>uniqueID<br>
      A randomly generated ID (16 pairs of hash values), e.g.
      <code>87c5cca38dc75a4f388ef87bdcbfbf6f</code> which is assigned to the transmitted
      data to prevent duplicate entries.
      <br>
      The <code>uniqueID</code> is stored automatically in the configuration file of FHEM.
    </li>
    <br>
    <li>sendStatistics<br>
      This attribute is reserved for a future usage in conjunction with the
      <code>update</code> command.
      <br>
      <code>0</code>: prevents transmission of data during an update.
      <br>
      <code>1</code>: transfer of data on every update. This is the default.
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
    <a href="http://fhem.de/stats/statistics.cgi">http://fhem.de/stats/statistics.cgi</a>
    abgerufen werden. Anhand der IP-Adresse wird der ungef&auml;hre Standort mit
    einer Genauigkeit von ca. 40-80 km ermittelt. Die IP-Adresse wird nicht gespeichert.
  <br>
  <br>
    Eigenschaften:<br>
    <ul>
      <li>Eingesetztes Betriebssystem</li>
      <li>Hardware Architektur</li>
      <li>Installierte Perl Version</li>
      <li>Installierte FHEM release und "branch"</li>
      <li>Definierte Module</li>
      <li>Definierte Modelle je Modul</li>
    </ul>
  <br>
    Beispiel:
    <pre>
      fhem&gt; fheminfo
      Fhem info:
        Release  : 5.3
        Branch   : DEVELOPMENT
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
    <li>uniqueID<br>
      Eine zuf&auml;llig generierte ID (16 Paare aus Hash Werten), z.B.
      <code>87c5cca38dc75a4f388ef87bdcbfbf6f</code> welche den &uuml;bertragenen Daten
      zur Vermeidung von doppelten Eintr&auml;ge zugewiesen wird.
      <br>
      Die <code>uniqueID</code> wird automatisch in der Konfigurationsdatei von FHEM
      gespeichert.
    </li>
    <br>
    <li>sendStatistics<br>
      Dieses Attribut ist f&uuml;r die k&uuml;nftige Verwendung in Verbindung mit dem
      <code>update</code> Befehl reserviert.
      <br>
      <code>0</code>: verhindert die &Uuml;bertragung der Daten w&auml;hrend eines Updates.
      <br>
      <code>1</code>: &uuml;bertr&auml;gt die Daten bei jedem Update. Dies ist die Standardeinstellung.
    </li>
    <br>
  </ul>
</ul>

=end html_DE
=cut

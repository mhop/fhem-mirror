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
use FhemUtils::release;                                               

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
  return "Argument 'send' is not useful, if global attribute 'sendStatistics' is set to 'never'."
    if(@args && lc($args[0]) eq "send" && lc(AttrVal("global","sendStatistics",undef)) eq "never");

  my $branch   = $DISTRIB_BRANCH;
  my $release  = $DISTRIB_RELEASE;
  my $os       = $^O;
  my $arch     = $Config{"archname"};
  my $perl     = $^V;
  my $uniqueID = AttrVal("global","uniqueID",undef);
  my $sendStatistics = AttrVal("global","sendStatistics",undef);
  my $moddir   = $attr{global}{modpath}."/FHEM";
  my $uidFile  = $moddir."/FhemUtils/uniqueID";
  my $upTime;
     $upTime   = fhemUptime();

  if(defined($uniqueID) && $uniqueID eq $uidFile) {
    my $fh;
    if(open($fh,"<".$uidFile)) {
      Log 5, "fheminfo get uniqueID from $uidFile";
      while (my $line = <$fh>) {
        chomp $line;
        if($line =~ m/^uniqueID:[\da-fA-F]{32}$/) {
          (undef,$uniqueID) = split(":",$line);
        }
      }
      close $fh;
    }
  }

  if(!defined($uniqueID) || $uniqueID !~ m/^[\da-fA-F]{32}$/ || !-e $uidFile) {
    my $fh;
    if(!open($fh,">".$uidFile)) {
      return "Can't open $uidFile: $!";
    }
    if(!defined($uniqueID) || defined($uniqueID) && $uniqueID !~ m/^[\da-fA-F]{32}$/) {
      $uniqueID = join "",map { unpack "H*", chr(rand(256)) } 1..16;
    }
    print $fh "################################################################\n";
    print $fh "# IMPORTANT NOTE:\n";
    print $fh "# This file is auto generated from the fheminfo command.\n";
    print $fh "# Please do not modify, move or delete this file!\n";
    print $fh "#\n";
    print $fh "# This file contains an unique ID for this installation. It is\n";
    print $fh "# to be used for statistical purposes only.\n";
    print $fh "# Based on this unique ID, no conclusions can be drawn to any\n";
    print $fh "# personal information of this installation.\n";
    print $fh "################################################################\n";
    print $fh "\n";
    print $fh "uniqueID:$uniqueID\n";
    close $fh;
    Log 5, "fheminfo 'uniqueID' generated and stored in file '$uidFile'";
  }

  $attr{global}{uniqueID} = $uidFile;

  my $ret = checkConfigFile($uidFile);

  return $ret if($ret);

  # get list of files
  my $fail;
  my $control_ref = {};

  foreach my $pack (split(" ",uc($UPDATE{packages}))) {
    $UPDATE{$pack}{control} = "controls_".lc($pack).".txt";
  }

  my $pack = "FHEM";

  if(!-e "$moddir/$UPDATE{$pack}{control}") {
    my $server = $UPDATE{server};
    my $BRANCH = ($DISTRIB_BRANCH eq "DEVELOPMENT") ? "SVN" : "STABLE";
    my $srcdir = $UPDATE{path}."/".lc($BRANCH);
    Log 5, "fheminfo get $server/$srcdir/$UPDATE{$pack}{control}";
    my $controlFile = GetFileFromURL("$server/$srcdir/$UPDATE{$pack}{control}");
    return "Can't get '$UPDATE{$pack}{control}' from $server" if (!$controlFile);
    # parse remote controlfile
    ($fail,$control_ref) = parseControlFile($pack,$controlFile,$control_ref,0);
    return "$fail\nfheminfo canceled..." if ($fail);
  } else {
    Log 5, "fheminfo get $moddir/$UPDATE{$pack}{control}";
    # parse local controlfile
    ($fail,$control_ref) = parseControlFile($pack,"$moddir/$UPDATE{$pack}{control}",$control_ref,1);
  }

  foreach my $d (sort keys %defs) {
    my $n = $defs{$d}{NAME};
    my $t = $defs{$d}{TYPE};
    my $m = "unknown";
    $m = $defs{$d}{model} if( defined($defs{$d}{model}) );
    $m = AttrVal($n,"model",$m);
    if(exists $control_ref->{$t}) {
      Log 5, "fheminfo name:$n type:$t model:$m";
      $info{modules}{$t}{$n} = $m;
    }
  }

  $info{modules}{configDB}{configDB} = 'unknown' if (configDBUsed());

  my $str;
  $str  = "Fhem info:\n";
  $str .= sprintf("  Release%*s: %s\n",2," ",$release);
  $str .= sprintf("  Branch%*s: %s\n",3," ",$branch);
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

  my $transmitData = ($attr{global}{sendStatistics}) ? $attr{global}{sendStatistics} : "not set";
  $str .= "\n";
  $str .= "Transmitting this information during an update:\n";
  $str .= "  $transmitData (Note: You can change this via the global attribute sendStatistics)\n";

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
sub parseControlFile($$$$) {
  my ($pack,$controlFile,$control_ref,$local) = @_;
  my %control = %$control_ref if ($control_ref && ref($control_ref) eq "HASH");
  my $from = ($local ? "local" : "remote");
  my $ret;

  if ($local) {
    my $str = "";
    # read local controlfile in string
    if (open FH, "$controlFile") {
      $str = do { local $/; <FH> };
    }
    close(FH);
    $controlFile = $str
  }
  # parse file
  if ($controlFile) {
    foreach my $l (split("[\r\n]", $controlFile)) {
      chomp($l);
      Log 5, "fheminfo $from controls_".lc($pack).".txt: $l";
      my ($ctrl,$date,$size,$file,$move) = "";
      if ($l =~ m/^(UPD) (20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d) (\d+) (\S+)$/) {
        $ctrl = $1;
        $date = $2;
        $size = $3;
        $file = $4;
      } elsif ($l =~ m/^(DIR) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
      } elsif ($l =~ m/^(MOV) (\S+) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
        $move = $3;
      } elsif ($l =~ m/^(DEL) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
      } else {
        $ctrl = "ESC"
      }
      if ($ctrl eq "ESC") {
        Log 1, "fheminfo File 'controls_".lc($pack).".txt' ($from) is corrupt";
        $ret = "File 'controls_".lc($pack).".txt' ($from) is corrupt";
      }
      last if ($ret);
      if ($l =~ m/^UPD/ && $file =~ m/^FHEM/) {
        if ($file =~ m/^.*(\d\d_)(.*).pm$/) {
          my $modName = $2;
          $control{$modName} = $file;
        }
      }
    }
  }
  return ($ret, \%control);
}

########################################
sub checkConfigFile($) {
  my $uidFile = shift;
  my $name = "fheminfo";
  my $configFile = AttrVal("global","configfile","");

  if($configFile && !configDBUsed()) {
    my $fh;
    if(!open($fh,"<".$configFile)) {
      return "Can't open $configFile: $!";
    }

    my @currentConfig = <$fh>;
    close $fh;

    my @newConfig;
    my $done = 0;

    if(grep {$_ =~ /uniqueID/} @currentConfig) {
      Log 5, "fheminfo uniqueID in configfile";
      foreach my $line (@currentConfig) {
        if($line =~ m/uniqueID/ && $line =~ m/[\da-fA-F]{32}/) {
          Log 5, "fheminfo uniqueID in configfile and hex";
          $line = "attr global uniqueID $uidFile\n";
          $done = 1;
        }
        push(@newConfig,$line);
      }
    } else {
      Log 5, "fheminfo uniqueID not in configfile";
      foreach my $line (@currentConfig) {
        push(@newConfig,$line);
        if($line =~ /modpath/ && $done == 0) {
          push(@newConfig,"attr global uniqueID $uidFile\n");
          $done = 1;
        }
      }
    }

    if($done) {
      if(!open($fh,">".$configFile)) {
        return "Can't open $configFile: $!";
      }

      foreach (@newConfig) {
        print $fh $_;
      }
      close $fh;
      Log 1, "$name global attributes 'uniqueID' added to configfile $configFile";
    }
  }

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

sub fhemUptime {
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

sub _myDiv($$) {
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
      <li>Defined modules (only official FHEM Modules are counted)</li>
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
      The <code>uniqueID</code> is stored automatically in a file named <code>FhemUtils/uniqueID</code>
      in FHEM's modules path.
      <br>
      <strong>IMPORTANT NOTE:</strong>
      <br>
      Every installation of FHEM should have to have his own unique ID.
      <br>
      Please do not modify, move or delete this file! You should always backup this file
      (this is normally done by the <code>update</code> command automatically) and please restore
      this file to the same path (<code>FhemUtils</code> in FHEM's modules path), if you plan to
      reinstall your FHEM installation. This prevents duplicate entries for identical
      installations on the same hardware in the statistics.
      <br>
      Otherwise, please use different unique IDs for each installation of FHEM on different
      hardware, e.g. one randomly generated unique ID for FRITZ!Box, another one for the first
      Raspberry Pi, another one for the second Raspberry Pi, etc.
      <br>
      Thanks for your support!
    </li>
    <br>
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
      <li>Definierte Module (nur offizielle FHEM Module werden ermittelt)</li>
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
      Die <code>uniqueID</code> wird automatisch in einer Datei namens <code>FHemUtils/uniqueID</code>
      im FHEM Modulverzeichnis gespeichert.
      <br>
      <strong>WICHTIGER HINWEIS:</strong>
      <br>
      Jede Installation von FHEM sollte seine eigene eindeutige ID haben.
      <br>
      Bitte diese Datei nicht ver&auml;ndern, verschieben oder l&ouml;schen! Diese Datei sollte
      immer gesichert (wird normalerweise automatisch durch den <code>update</code> Befehl
      erledigt) und bei einer Neuinstallation auf der gleichen Hardware im gleichen Verzeichnis
      (<code>FhemtUtils</code> im FHEM Modulverzeichnis) wieder hergestellt werden. Dies verhindert
      doppelte Eintr&auml;ge identischer Installationen auf der gleichen Hardware in der Statistik.
      <br>
      Anderfalls, sollten bitte f&uuml;r jede Installation auf unterschiedlicher Hardware eigene
      IDs genutzt werden, z.B. eine zuf&auml;llig erzeugte ID f&uuml;r FRITZ!Box, eine weitere f&uuml;r
      den ersten Raspberry Pi, eine weitere f&uuml;r einen zweiten Raspberry Pi, usw.
      <br>
      Vielen Dank f&uuml;r die Unterst&uuml;tzung!
    </li>
    <br>
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

# $Id$
################################################################
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
use HttpUtils;

my %fhemInfo =();

sub fheminfo2_Initialize($$) {
  my %hash = (
    Fn  => "CommandFheminfo2",
    uri => "http://fhem.j65.de/stats/statistics2.cgi",
    Hlp => "[send],show or send Fhem statistics",
  );
  $cmds{fheminfo2} = \%hash;
}

sub CommandFheminfo2($$) {
  my ($cl,$param) = @_;
  my @args = split("[ \t]+", $param);
  $args[0] = defined($args[0]) ? lc($args[0]) : "";
  my $doSend = ($args[0] eq 'send') ? 1 : 0;

  return "Unknown argument $args[0], usage: fheminfo2 [send]"
    if($args[0] ne "send" && $args[0] ne "");

  return "Won't send, as sendStatistics is set to 'never'."
    if($doSend &&  lc(AttrVal("global","sendStatistics","")) eq "never");

  _fi2_Count();

  _fi2_Send() if $args[0] eq 'send';

  return _fi2_TelnetTable($doSend) if ($cl && $cl->{TYPE} eq 'telnet');
  return _fi2_HtmlTable($doSend);
}

################################################################
# tools
#
sub _fi2_Count() {

   my $uniqueID = getUniqueId();
   my $release  = "5.8";
   my $feature  = $featurelevel ? $featurelevel : $release;
   my $os       = $^O;
   my $arch     = $Config{"archname"};
   my $perl     = sprintf("%vd", $^V);

   %fhemInfo = ();

   $fhemInfo{'system'}{'uniqueID'} = $uniqueID;
   $fhemInfo{'system'}{'release'}  = $release;
   $fhemInfo{'system'}{'feature'}  = $feature;
   $fhemInfo{'system'}{'os'}       = $os;
   $fhemInfo{'system'}{'arch'}     = $arch;
   $fhemInfo{'system'}{'perl'}     = $perl;

   foreach my $key ( keys %defs )
   {
      my $name  = $defs{$key}{NAME};
      my $type  = $defs{$key}{TYPE};
      my $model = 'noModel';
         $model = defined($defs{$key}{model}) ? $defs{$key}{model} : $model;
         $model = defined($defs{$key}{MODEL}) ? $defs{$key}{MODEL} : $model;
         $model = AttrVal($name,'model',$model);
#         $model = ReadingsVal($name,'type',$model);
         $model = ReadingsVal($name,'model',$model);
      $fhemInfo{$type}{$model}++ unless defined($defs{$key}{'chanNo'}); # exclude Homematic channels
   }

   return;
}

sub _fi2_Send() {
   my $json = _fi2_to_json(\%fhemInfo);

   Log3("fheminfo",4,"fheminfo: $json");

   my %hu_hash = ();
   $hu_hash{url}      = $cmds{fheminfo2}{uri};
   $hu_hash{data}     = "uniqueID=".$fhemInfo{'system'}{'uniqueID'}."&json=$json";
   $hu_hash{header}   = "User-Agent: FHEM/".$fhemInfo{'system'}{'release'};
   $hu_hash{callback} = sub($$$) {
        my ($hash, $err, $data) = @_;
        if($err) {
          Log 1, "fheminfo send: Server ERROR: $err";
        } else {
          Log3("fheminfo",4,"fheminfo send: Server RESPONSE: $data");
        }
      };
   HttpUtils_NonblockingGet(\%hu_hash);
   return;
}

sub _fi2_TelnetTable($) {
  my ($doSend) = shift;
  my $upTime = _fi2_Uptime();
  my $str =  "Following statistics data will be sent to server:\n(see Logfile for server response)\n\n" if($doSend == 1);
  $str .= "System Info\n";
  $str .= sprintf("  Release%*s: %s\n",6," ",$fhemInfo{'system'}{'release'});
  $str .= sprintf("  FeatureLevel%*s: %s\n",0," ",$fhemInfo{'system'}{'feature'});
  $str .= sprintf("  OS%*s: %s\n",11," ",$fhemInfo{'system'}{'os'});
  $str .= sprintf("  Arch%*s: %s\n",9," ",$fhemInfo{'system'}{'arch'});
  $str .= sprintf("  Perl%*s: %s\n",9," ",$fhemInfo{'system'}{'perl'});
  $str .= sprintf("  uniqueID%*s: %s\n",5," ",$fhemInfo{'system'}{'uniqueID'});
  $str .= sprintf("  upTime%*s: %s\n",7,"  ",$upTime); 

   my @keys = keys %fhemInfo;
   foreach my $type (sort @keys)
   {
      next if $type eq 'system';
      $str .= "\nType: $type ";
      $str .= "Count: ".$fhemInfo{$type}{'noModel'} if defined $fhemInfo{$type}{'noModel'};
      $str .= "\n";
      while ( my ($model, $count) = each(%{$fhemInfo{$type}}) )
      { $str .= "     $model = $fhemInfo{$type}{$model}\n" unless $model eq 'noModel'; }
   }

  return $str;
}

sub _fi2_HtmlTable($) {
   my ($doSend) = shift;
   my $upTime = _fi2_Uptime();
   my $result  = "<html><table>";
      $result .= "<tr><td colspan='3'>Following statistics data will be sent to server:</br>(see Logfile for server response)</td></tr>" if($doSend == 1);
      $result .= "<tr><td>System Info</td></tr>";
      $result .= "<tr><td> </td><td>Release:</td><td>$fhemInfo{'system'}{'release'}</td></tr>";
      $result .= "<tr><td> </td><td>FeatureLevel:</td><td>$fhemInfo{'system'}{'feature'}</td></tr>";
      $result .= "<tr><td> </td><td>OS:</td><td>$fhemInfo{'system'}{'os'}</td></tr>";
      $result .= "<tr><td> </td><td>Arch:</td><td>$fhemInfo{'system'}{'arch'}</td></tr>";
      $result .= "<tr><td> </td><td>Perl:</td><td>$fhemInfo{'system'}{'perl'}</td></tr>";
      $result .= "<tr><td> </td><td>uniqueId:</td><td>$fhemInfo{'system'}{'uniqueID'}</td></tr>";
      $result .= "<tr><td> </td><td>upTime:</td><td>$upTime</td></tr>";
      $result .= "<tr><td>Modules</td><td>Model</td><td>Count</td></tr>";

   my @keys = keys %fhemInfo;
   foreach my $type (sort @keys)
   {
      next if $type eq 'system';
      $result .= "<tr><td>$type</td><td> </td><td>$fhemInfo{$type}{'noModel'}</td></tr>";
      while ( my ($model, $count) = each(%{$fhemInfo{$type}}) )
      { $result .= "<tr><td> </td><td>$model</td><td>$fhemInfo{$type}{$model}</td></tr>" unless $model eq 'noModel'; }
   }  

   $result .= "</table></html>";
   return $result;
}

sub _fi2_Uptime() {
  my $diff = time - $fhem_started;
  my ($d,$h,$m,$ret);
  
  ($d,$diff) = _fi2_Div($diff,86400);
  ($h,$diff) = _fi2_Div($diff,3600);
  ($m,$diff) = _fi2_Div($diff,60);

  $ret  = "";
  $ret .= "$d days, " if($d >  1);
  $ret .= "1 day, "   if($d == 1);
  $ret .= sprintf("%02s:%02s:%02s", $h, $m, $diff);

  return $ret;
}

sub _fi2_Div($$) {
  my ($p1,$p2) = @_;
  return (int($p1/$p2), $p1 % $p2);
}

sub _fi2_to_json {
    my $val = shift;
    if (not defined $val) {
        return "null";
    } elsif (not ref $val) {
        $val =~ s/([\0-\x1f\"\\])/sprintf "\\u%04x", ord $1/eg;
        return '"' . $val . '"';
    } elsif (ref $val eq 'ARRAY') {
        return '[' . join(',', map to_json($_), @$val) . ']';
    } elsif (ref $val eq 'HASH') {
        return '{' . join(',', map to_json($_) . ":" . to_json($val->{$_}), sort keys %$val) . '}';
    } else {
        return "Cannot encode $val as JSON!\n";
    }
}

1;

=pod
=item command
=item summary    display information about the system and FHEM definitions
=item summary_DE zeigt Systeminformationen an
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

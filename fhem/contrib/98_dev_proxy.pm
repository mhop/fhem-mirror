##############################################################################
#
#     98_dev_proxy.pm
#     Copyright by A. Schulz
#     e-mail: 
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
# $Id: $
package main;

use strict;
use warnings;
use List::Util qw[min max];
use Data::Dumper;

#####################################
sub dev_proxy_setDefaultObservedReadings($);
sub dev_proxy_setObservedReading($@);
sub dev_proxy_addDevice($$);
sub dev_proxy_updateReadings($$);
sub dev_proxy_computeCombReading($$);
sub dev_proxy_mapDeviceReadingValueDefultMap($$$$$);
sub dev_proxy_mapDeviceReadingValue($$$$$);
sub dev_proxy_mapValue($$$);
sub dev_proxy_eval_map_readings($$);
sub dev_proxy_remap_reading($$$);
sub dev_proxy_cleanup_readings($);
#####################################
sub dev_proxy_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}     = "dev_proxy_Define";
  $hash->{UndefFn}   = "dev_proxy_Undef";
  $hash->{NotifyFn}  = "dev_proxy_Notify";
  $hash->{SetFn}     = "dev_proxy_Set";
  $hash->{AttrFn}    = "dev_proxy_Attr";
  $hash->{AttrList}  = "observedReadings setList mapValues mapReadings ". "disable disabledForIntervals ". $readingFnAttributes;

}

sub dev_proxy_Define($$) {
my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> dev_proxy [device ...]*";
  return $u if(int(@a) < 3);

  my $devname = shift(@a);
  my $modname = shift(@a);

  $hash->{CHANGEDCNT} = 0;
  my $or = AttrVal($devname, "observedReadings", undef);
  if(defined($or)) {
    dev_proxy_setObservedReading($or);
  } else {
    dev_proxy_setDefaultObservedReadings($hash);
  }
  
  my %list;
  $hash->{CONTENT} = \%list;
  foreach my $a (@a) {
    foreach my $d (devspec2array($a)) {
        dev_proxy_addDevice($hash, $d);
    }
  }
  
  my $valuesMap = AttrVal($devname,'mapValues',undef);
  if (defined $valuesMap) {
    $hash->{DEV_READING_VALUE_MAP} = eval($valuesMap);
  } else {
    $hash->{DEV_READING_VALUE_MAP} = undef;
  }
  dev_proxy_eval_map_readings($hash, AttrVal($devname,'mapReadings',undef));
  dev_proxy_updateReadings($hash, undef);
  
  return undef;
}

sub dev_proxy_setDefaultObservedReadings($) {
  my ($hash) = @_;
  #$hash->{OBSERVED_READINGS} = ["state","dim", "position"];
  $hash->{OBSERVED_READINGS} = {};
  $hash->{OBSERVED_READINGS} ->{"state"}=1;
  $hash->{OBSERVED_READINGS} ->{"dim"}=1;
  $hash->{OBSERVED_READINGS} ->{"position"}=1;
}

sub dev_proxy_setObservedReading($@) {
  my ($hash, @list) = @_;

  $hash->{OBSERVED_READINGS} = {};
  foreach my $a (@list) {
    $hash->{OBSERVED_READINGS} -> {$a} = 1;
  }
}

sub dev_proxy_addDevice($$) {
  my ($hash, $d) = @_;
  if($defs{$d}) {
    $hash->{CONTENT}{$d} = 1;
  }
}

sub dev_proxy_Undef($$) {
  my ($hash, $def) = @_;
  return undef;
}

sub dev_proxy_Notify($$) {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  
  if( $dev->{NAME} eq "global" ) {
    my $max = int(@{$dev->{CHANGED}});
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      $s = "" if(!defined($s));
      if($s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
        my ($old, $new) = ($1, $2);
        if( exists($hash->{CONTENT}{$old}) ) {

          $hash->{DEF} =~ s/(\s+)$old(\s*)/$1$new$2/;

          delete( $hash->{CONTENT}{$old} );
          $hash->{CONTENT}{$new} = 1;
        }
      } elsif($s =~ m/^DELETED ([^ ]*)$/) {
        my ($name) = ($1);

        if( exists($hash->{CONTENT}{$name}) ) {

          $hash->{DEF} =~ s/(\s+)$name(\s*)/ /;
          $hash->{DEF} =~ s/^ //;
          $hash->{DEF} =~ s/ $//;

          delete $hash->{CONTENT}{$name};
          delete $hash->{".cachedHelp"};
        }
      }
    }
  }

  return "" if(IsDisabled($name));
  
  # pruefen ob Devices welches das notify ausgeloest hat Mitglied dieser Gruppe ist
  return "" if (! exists $hash->{CONTENT}->{$dev->{NAME}});
  
  dev_proxy_updateReadings($hash, $dev);

  readingsSingleUpdate($hash, "LastDevice", $dev->{NAME}, 0);
  
  return undef;
}

sub dev_proxy_updateReadings($$) {
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  
  if($hash->{INNTFY}) {
    Log3 $name, 1, "ERROR: endless loop detected in composite_Notify $name";
    return "";
  }
  $hash->{INNTFY} = 1;
  
#  my $nrmap;
#  foreach my $or (keys %{ $hash->{OBSERVED_READINGS}} ) { 
#    my $map;
#    foreach my $d (keys %{ $hash->{CONTENT}} ) {
#      next if(!$defs{$d});
#      my $or_mapped = dev_proxy_remap_reading($hash, $d, $or);
#      my $devReadings = ReadingsVal($d,$or_mapped,undef);
#      if(defined($devReadings)) {
#        ($devReadings) = dev_proxy_mapDeviceReadingValueDefultMap($hash,$d,$or,$devReadings,1);
#        $map->{$d}=$devReadings;
#      }
#    }
#    my $newReading = dev_proxy_computeCombReading($or, $map);
#    if(defined($newReading)) {
#      $nrmap->{$or}=$newReading;
#    }
#  }

  my $map;
  foreach my $or (keys %{ $hash->{OBSERVED_READINGS}} ) { 
    foreach my $d (keys %{ $hash->{CONTENT}} ) {
      next if(!$defs{$d});
      my $or_mapped = dev_proxy_remap_reading($hash, $d, $or);
      my $devReadings = ReadingsVal($d,$or_mapped,undef);
      if(defined($devReadings)) {
        my $nReading;
        ($devReadings, $nReading) = dev_proxy_mapDeviceReadingValueDefultMap($hash,$d,$or,$devReadings,1);
        # Nur wenn nicht ueberschrieben wurde
        if(!defined($map->{$or}->{$d})) {
          $map->{$or}->{$d}=$devReadings;
        }
        # falls umgemappt werden soll, den neuen Wert auch aufnehmen (ueberschreibt den eigentlichen Wert für das andere Reading)
        if($or ne $nReading) {
          $map->{$nReading}->{$d}=$devReadings;
        }
      }
    }
  }
  
  # jetzt gesammelten Werte kombinieren / zusammenrechnen
  my $nrmap;
  foreach my $or (keys %{ $map } ) {
    my $newReading = dev_proxy_computeCombReading($or, $map->{$or});
    if(defined($newReading)) {
      $nrmap->{$or}=$newReading;
    }
  }
  
  readingsBeginUpdate($hash);
  foreach my $d (sort keys %{ $nrmap }) {
    my $newState = $nrmap->{$d};
    my $dd = defined($dev)?" because device $dev->{NAME} has changed":"";
    Log3 ($name, 5, "Update composite '$name' reading $d to $newState $dd");
    readingsBulkUpdate($hash, $d, $newState);
  }
  readingsEndUpdate($hash, 1);
  
  $hash->{CHANGEDCNT}++;
  delete($hash->{INNTFY});
  
  dev_proxy_cleanup_readings($hash);
}

sub dev_proxy_computeCombReading($$) {
  my ($rName, $map) = @_;
  my $size = keys %{$map};
  if($size<1) {
    return undef;
  }
  
  my @values = values %{$map};
  
  if($rName eq 'state') {
    my $tm;
    foreach my $d (@values) {
      $tm->{$d}=1;
    }
    return join(" ", keys %{ $tm });
  }
  
  my $maxV = max(@values);
  my $minV = min(@values);
  #if($maxV-$minV<10) {
    return $minV+($maxV-$minV)/2;
  #}
  
  return $maxV;
  
  return undef;
}

sub dev_proxy_mapDeviceReadingValueDefultMap($$$$$) {
  my ($hash, $dev, $reading, $val, $incoming) = @_;
  return dev_proxy_mapDeviceReadingValue($hash->{DEV_READING_VALUE_MAP}, $dev, $reading, $val,$incoming);
}

# Definition: map {'dev:reading'=>{'val'=>'valnew',.},..}
# Priority: zuerst richtungsspezifische (in/out): 
#   in:dev:reading, in:dev:*, in:*:reading, in:*:* (or in:*), 
#   dann Standard: dev:reading, dev:*, *:reading, *:* (or *)
# Nur bei out-Richtung (also set) relevant:
#   Moeglichkeit, Zielreading umzudefinieren.
#   Dafuer soll der Zielwert in Form WERT:NEWREADINGNAME geliefert werden:
#     ...{'val'=>'valnew:newreading',..}...
sub dev_proxy_mapDeviceReadingValue($$$$$) {
  my ($map, $dev, $reading, $val, $incoming) = @_;
    
  return ($val, $reading) unless defined $map;
  my $nval;
  my $selectedMap;
  # zuerst richtungsspeziefische Map (in/out) ausprobieren
  my $prefix = $incoming ? 'in:' : 'out:';
  $selectedMap = $map->{$prefix.$dev.':'.$reading};
  $selectedMap = $map->{$prefix.$dev.':*'} unless defined $selectedMap;
  $selectedMap = $map->{$prefix.'*:'.$reading} unless defined $selectedMap;
  $selectedMap = $map->{$prefix.'*:*'} unless defined $selectedMap;
  $selectedMap = $map->{$prefix.'*'} unless defined $selectedMap;
  # falls keine passende Map vorhanden ist, oder sie keine passende Regel
  # enthaelt, dann Standardmap verwenden
  if(defined $selectedMap) {
    $nval = dev_proxy_mapValue($selectedMap, $val, $incoming);
    if(defined $nval) {
      my ($nval, @areading) = split(/:/, $nval);
      my $nreading = @areading ? join(':',@areading) : $reading;
      return ($nval, $nreading);  
    }
  }
  
  $selectedMap = $map->{$dev.':'.$reading};
  $selectedMap = $map->{$dev.':*'} unless defined $selectedMap;
  $selectedMap = $map->{'*:'.$reading} unless defined $selectedMap;
  $selectedMap = $map->{'*:*'} unless defined $selectedMap;
  $selectedMap = $map->{'*'} unless defined $selectedMap;
  # Originalwert, falls kein passendes Map
  return ($val, $reading) unless defined $selectedMap;
  
  $nval = dev_proxy_mapValue($selectedMap, $val, $incoming);
  return ($nval, $reading) if defined $nval;
  # Originalwert, falls keine Entsprechung im Map
  return ($val, $reading);
}

sub dev_proxy_mapValue($$$) {
  my ($map, $val, $incoming) = @_;

  my $nv=$map->{$val};
  if(!defined($nv)) {
    $nv=$map->{'*'};
  }
  
  return undef unless(defined($nv)) ;
  
  if($nv=~/^{/) {
      $nv = eval($nv);
  }
  
  return $nv;
}

sub dev_proxy_Set($@){
  my ($hash,$name,$command,@values) = @_;
  
  return "no set value specified" if(!defined($command));
  
  if ($command eq '?') {
    my $setList = AttrVal($name, "setList", undef);
    if(!defined $setList) {
      $setList = "";
      foreach my $n (sort keys %{ $hash->{READINGS} }) {
       next if($n eq 'LastDevice' || $n eq 'state');
       $setList.=$n;
       if($n eq 'position' || $n eq 'dim' ) {
         $setList.=":slider,0,1,100";
       }
       $setList.=" ";
      }
    }
    $setList =~ s/\n/ /g;  
    return "Unknown argument $command, choose one of $setList";
  }

  if(int(@values)>0 && !defined($hash->{READINGS}->{$command})) {
    return "Unknown reading $command";
  }
  
  my $ret;
  my @devList = keys %{$hash->{CONTENT}};
  foreach my $d (@devList) {
    my $val;
    if(int(@values)<1) {
      # state
      my $cmd = "state";
      ($val, $cmd) = dev_proxy_mapDeviceReadingValueDefultMap($hash, $d, "state", $command,0);
      $cmd = dev_proxy_remap_reading($hash, $d, $cmd);
      my $cmdstr;
      if($cmd ne "state") {
        $cmdstr = join(" ", ($d, $cmd, $val));
      } else {
        $cmdstr = join(" ", ($d, $val));
      }
      #Log3 $hash, 1, "SET: >>> ".$cmdstr;
      $ret .= CommandSet(undef, $cmdstr);
    } else {
      # benannte readings
      my $cmd = $command;
      ($val, $cmd) = dev_proxy_mapDeviceReadingValueDefultMap($hash, $d, $command, join(" ", @values),0);
      $cmd = dev_proxy_remap_reading($hash, $d, $cmd);
      my $cmdstr;
      if($cmd ne "state") {
         $cmdstr = join(" ", ($d, $cmd, $val));
      } else {
         $cmdstr = join(" ", ($d, $val));
      }
      #Log3 $hash, 1, "SET: >>> ".$cmdstr;
      $ret .= CommandSet(undef, $cmdstr);
    }
  }
  Log3 $hash, 5, "SET: $ret" if($ret);


  return undef;
}

sub dev_proxy_Attr($@){
  my ($type, $name, $attrName, $attrVal) = @_;
  my %ignore = (
    alias=>1,
    devStateIcon=>1,
    disable=>1,
    disabledForIntervals=>1,
    group=>1,
    icon=>1,
    room=>1,
    stateFormat=>1,
    webCmd=>1,
    userattr=>1
  );

  return undef if($ignore{$attrName});
  
  my $hash = $defs{$name};
  
  if($attrName eq "observedReadings") {
    if($type eq "del") {
      dev_proxy_setDefaultObservedReadings($hash);
    } else {
      my @a=split("[ \t][ \t]*",$attrVal);
      dev_proxy_setObservedReading($hash, @a);
    }
  } elsif($attrName eq "mapValues") {
    if($type ne "del") {
      $hash->{DEV_READING_VALUE_MAP} = eval($attrVal);
    } else {
      $hash->{DEV_READING_VALUE_MAP} = undef;
    }
  } elsif($attrName eq "mapReadings") {
    if($type ne "del") {
      dev_proxy_eval_map_readings($hash, $attrVal);
    } else {
      $hash->{READING_NAME_MAP} = undef;
    }
  } 
  
  dev_proxy_updateReadings($hash, undef);

  Log3 $name, 4, "dev_proxy attr $type";
  return undef;
}

sub dev_proxy_eval_map_readings($$) {
  my ($hash, $attrVal) = @_;
  $hash->{READING_NAME_MAP} = undef unless defined $attrVal;
  my $map;
  if(defined $attrVal) {
    my @list = split("[ \t][ \t]*", $attrVal);
    foreach (@list) {
      my($devName, $devReading, $newReading) = split(/:/, $_);
      $map->{$devName} -> {$newReading} = $devReading;
    }
  }
  $hash->{READING_NAME_MAP} = $map;
}

# Readings remappen, die von hier in die Richtung anderen Devices gesendet werden
sub dev_proxy_remap_reading($$$) {
  my ($hash, $devName, $readingName) = @_;
  my $map = $hash->{READING_NAME_MAP};
  return $readingName unless defined $map;
  
  my $t = $map->{$devName};
  $t = $map->{"*"} unless defined $t;
  my $newReadingName = $t->{$readingName} if defined $t;
  
  return $readingName unless defined $newReadingName;
  return $newReadingName;
}

sub dev_proxy_cleanup_readings($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $map = $hash->{OBSERVED_READINGS};
  return unless defined $map;
  
  foreach my $aName (keys %{$defs{$name}{READINGS}}) {
    if(!defined $map->{$aName} && ($aName ne "LastDevice") && ($aName ne "state")) {
      delete $defs{$name}{READINGS}{$aName};
    }
  }
}

1;

=pod
=item helper
=item summary    organize devices and readings, remap / rename readings
=item summary_DE mehrere Ger&auml;te zu einem zusammenfassen, Readings umbenennen / umrechnen
=begin html

<a name="dev_proxy"></a>
<h3>dev_proxy</h3>

=end html
=begin html_DE

<a name="dev_proxy"></a>
<h3>dev_proxy</h3>
<ul>
  <br>
  <a name="dev_proxydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dev_proxy &lt;dev1&gt; &lt;dev2&gt; ...</code> <br><br>

    Mit diesem virtuellem Ger&auml;t k&ouml;nnen ausgew&auml;hlte Readings eines anderen oder mehreren Ger&auml;te 
    an einer Stelle zusammengefasst werden. Diese k&ouml;nnen dabei ggf. umbenannt 
    und / oder umgerechnet werden.
    <br>Beispiel:<br>
    <code>defmod testdev_proxy dev_proxy MQ_DG_WZ_O_Rollo1 MQ_DG_WZ_O_Rollo2</code>
   </ul> 

  <br>
  <a name="dev_proxyset"></a>
  <b>Set</b>
  <ul>
    Die hier angegebenen Werte werden an die Originalger&auml;te weitergeleitet. 
    Definierte Umbenennungen und Umrechnungen werden ber&uuml;cksichtigt.
  </ul>

  <br>
  <a name="dev_proxyget"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>

  <br>
  <a name="dev_proxyattr"></a>
  <b>Attributes</b>
  <ul>
    <li>
      observedReadings: bestimmt zu &uuml;berwachende Readings (durch Leerzeichen separierte liste)<br>
      (wenn dieses Attrubut nicht angegeben wird, werden 'state', 'dim'und 'position' &uuml;berwacht)
      <br>Beispiel: <br>
      <code>attr &lt;name&gt; observedReadings state level</code>
      <br>
    </li><br>
    <li>
      setList: Durch Leerzeichen getrennte Liste der Werte f&uuml;r Set-Befehl.<br>
      Diese Liste wird bei "set name ?" ausgegeben. 
      Damit kann das FHEMWEB-Frontend Auswahl-Men&uuml;s oder Schalter erzeugen.
      <br>Die gesetzten Werte werden an die entsprechende Readings der Ger&auml;te weitergereicht.
      Dabei wird im mapReadings definierte Umsetzungsregel beachtet. 
      <br>Es wird jedoch nicht gepr&uuml;fft, ob angegebene Reading in observed_reading vorhanden ist.
      Ggf. wird einfach 'blind' weitergereicht.<br>
      Beispiel: <br>
      <code>attr &lt;name&gt; setList opens:noArg closes:noArg stop:noArg up:noArg down:noArg position:slider,0,1,100</code>
      <br>
    </li><br>
    <li>
      mapValues: Erlaubt &Auml;nderungen/Umrechnungen an den Werte der Readings 
      ggf. abh&auml;ngig von den jeweiligen Device- und Readingsnamen.
      Umrechnungstabellen k&ouml;nnen je nach Richtung ('in' aus Notify oder 'out' f&uuml;r set) getrennt definiert werden.
      Falls die Definition mit dem Richtungsprefix nicht existiert oder kein Ergebnis liefert, 
      werden Standartdefinitionen (die parallel angegeben werden k&ouml;nnen) verwendet.
      F&uuml;r ausgehende Werte kann die Ziel-Reading auch umdefiniert werden, dieser wird im Zielwert nach dem ':' angegeben.
      Die Angabe ist auch bei 'in:' m&ouml;glich, dann wird dieser Wert den Wert der angegebenen Reading (bei dem selben Device) ersetzen.
      Das kann n&uuml;tzlich sein, um spezielle Werte an andere Readings umzuleiten.
      <br>
      Die Werte m&uuml;ssen in als eine Hash-Map angegeben werden. 
      &lt;STATE&gt; soll als state angesprochen werden.<br>
      Form: <code>{'&lt;device&gt;:&lt;reading&gt;'=>{'&lt;value&gt;'=>'new value',..},..}</code><br>
      Oder mit Richtungsprefix: <code>{'out:&lt;device&gt;:&lt;reading&gt;'=>{'&lt;value&gt;'=>'new value[:new reading]',..},..}</code><br>
      &lt;device&gt;, &lt;reading&gt; und &lt;value&gt; k&ouml;nnen auch mit * angegeben werden.
      Diese Angabe wird als 'Default' verwendet, wenn keine andere gepasst haben.<br>
      Priorit&auml;tenreihenfolge f&uuml;r die &lt;device&gt;:&lt;reading&gt;-Paaren: &lt;device&gt;:&lt;reading&gt;, &lt;device&gt;:*, *:&lt;reading&gt;, *:* (oder auch *).<br>
      F&uuml;r die Umrechnung steht das Originalvalue als $val-Variable zur Verf&uuml;gung.
      Falls Richtung (von Original-Ger&auml;t (bei Notify) oder zu dem Original-Ger&auml;t (bei set))
      wichtig ist, kann diese durch Abfrage der Variable $incoming 
      (jeweils 1 oder 0) abgefragt werden.
      <br>Beispiel: <br>
      <code>attr &lt;name&gt; mapValues {'*:position'=>{'*'=>'{100-$val}','down'=>'100', 'closed'=>'100', 'up'=>'0', 'open'=>'0', 'open_ack'=>'0', 'off'=>'0', 'on'=>'100'}}</code>
      <br>
    </li><br>
    <li>
      mapReadings: Erlaubt Ger&auml;te-Readings unter anderem Namen verwenden. 
      * kann als Default anstatt Ger&auml;tenamen verwendet werden. &lt;STATE&gt; soll als state angesprochen werden.
      <br>
      <code>attr &lt;name&gt; mapReadings &lt;device&gt;:&lt;original reading&gt;:&lt;hier zu verwendende reading&gt; ...</code>
      <br>
      Beispiel: <br>
      <code>attr &lt;name&gt; mapReadings Rollo1:pct:position Rollo2:pct:position</code>
    </li>
  </ul>
  <br>
  <b>Beispiele:</b>
  <ul>
    <li>
      Zusammenfassung zweier Rolll&auml;den, Steuerung &uuml;ber die Reading 'position', Umkehrung der Prozentwerte.
      <br>
      <code>
      defmod test1 dev_proxy Rollo1 Rollo2 <br>
      attr test1 mapValues {'*:position'=>{'*'=>'{100-$val}','down'=>'100', 'closed'=>'100', 'up'=>'0', 'open'=>'0', 'open_ack'=>'0', 'off'=>'0', 'on'=>'100'}} <br>
      attr test1 setList opens:noArg closes:noArg stop:noArg up:noArg down:noArg position:slider,0,1,100 <br>
      attr test1 webCmd opens:closes:stop:position <br>
      </code>
    </li><br>
    <li>
      Abbildung f&uuml;r ein Rollladen, Umbenennung der Original-Reading 'position' in 'pos', Umkehrung der Prozentwerte.
      <br>
      <code>
      defmod test2 dev_proxy Rollo1 <br>
      attr test2 observed_readings pos state <br>
      attr test2 mapValues {'*:pos'=>{'*'=>'{100-$val}','down'=>'100', 'closed'=>'100', 'up'=>'0', 'open'=>'0', 'open_ack'=>'0', 'off'=>'0', 'on'=>'100'}} <br>
      attr test2 setList opens:noArg closes:noArg stop:noArg up:noArg down:noArg pos:slider,0,1,100 <br>
      attr test2 mapReadings *:position:pos <br>
      attr test2 webCmd up:down:stop:pos <br>
      </code>
      </li>
  </ul>

</ul>
=end html_DE
=cut

################################################################
#
#  Copyright notice
#
#  (c) 2014 Alexander Schulz
#
#  This script is free software; you can redistribute it and/or modify
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

# $Id$

package main;

use strict;
use warnings;
use Data::Dumper;

my $VERSION = "0.9.7";

my $DEFAULT_INTERVAL = 60; # in minuten

sub SMARTMON_refreshReadings($);
sub SMARTMON_obtainParameters($);
sub SMARTMON_getSmartDataReadings($$);
sub SMARTMON_interpretKnownData($$$);
sub SMARTMON_readSmartData($;$);
sub SMARTMON_readDeviceData($%);
sub SMARTMON_sec2Dauer($);
sub SMARTMON_hour2Dauer($);
sub SMARTMON_execute($$);


sub SMARTMON_Initialize($)
{
  my ($hash) = @_;

  Log 5, "SMARTMON Initialize";

  $hash->{DefFn}    = "SMARTMON_Define";
  $hash->{UndefFn}  = "SMARTMON_Undefine";
  $hash->{GetFn}    = "SMARTMON_Get";
  #$hash->{SetFn}    = "SMARTMON_Set";
  $hash->{AttrFn}   = "SMARTMON_Attr";
  $hash->{AttrList} = "show_raw:0,1,2 disable:0,1 include parameters show_device_info:0,1 ".$readingFnAttributes;
}

sub SMARTMON_Log($$$) {
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/SMARTMON_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "SMARTMON $instName: $sub.$xline " . $text;
}

my $device;

sub SMARTMON_Define($$)
{
  my ($hash, $def) = @_;

  SMARTMON_Log($hash, 4, "Define $def");

  my @a = split("[ \t][ \t]*", $def);

  SMARTMON_Log($hash, 5, "Define: ".Dumper(@a));

  return "Usage: define <name> SMARTMON <device> [M1]" if(@a < 3);

  $hash->{DEVICE} = $a[2];
  if(int(@a)>=4)
  {
    $hash->{INTERVAL} = $a[3]*60;
  } else {
    $hash->{INTERVAL} = $DEFAULT_INTERVAL*60;
  }

  $hash->{STATE} = "Initialized";

  RemoveInternalTimer($hash);
  # erstes update zeitversetzt starten
  InternalTimer(gettimeofday()+10, "SMARTMON_Update", $hash, 0);

  return undef;
}

sub SMARTMON_Undefine($$)
{
  my ($hash, $arg) = @_;

  SMARTMON_Log($hash, 4, "Undefine");

  RemoveInternalTimer($hash);
  return undef;
}

sub SMARTMON_Get($@)
{
  # http://www.linux-community.de/Internal/Artikel/Print-Artikel/LinuxUser/2004/10/Die-Zuverlaessigkeit-von-Festplatten-ueberwachen-mit-smartmontools
  my ($hash, @a) = @_;

  my $name = $a[0];

  if(@a < 2)
  {
    return "$name: get needs at least one parameter";
  }

  my $cmd= $a[1];

  SMARTMON_Log($hash, 5, "Get: ".Dumper(@a));

  if($cmd eq "update")
  {
    SMARTMON_refreshReadings($hash);
    return undef;
  }

  my $param="";
  if($hash->{PARAMETERS}) {$param=" ".$hash->{PARAMETERS};}
  
  if($cmd eq "list")
  {
    if(@a<3) {return "$name: get list needs at least one parameter"; }
    my $subcmd=$a[2];
    my @t;
    my $r;
    if($subcmd eq "info") {
      my $tdev = $hash->{DEVICE};
      if(@a>3) {$tdev=$a[3];}
      ($r, @t) = SMARTMON_execute($hash, "sudo smartctl -i".$param." ".$tdev);
    }
    if($subcmd eq "data") {
      my $tdev = $hash->{DEVICE};
      if(@a>3) {$tdev=$a[3];}
      ($r, @t) = SMARTMON_execute($hash, "sudo smartctl -A".$param." ".$tdev);
    }
    if($subcmd eq "health") {
      my $tdev = $hash->{DEVICE};
      if(@a>3) {$tdev=$a[3];}
      ($r, @t) = SMARTMON_execute($hash, "sudo smartctl -H".$param." ".$tdev);
    }
    if($subcmd eq "devices") {
      ($r, @t) = SMARTMON_execute($hash, "sudo smartctl --scan");
    }
    
    my $tt;
    if(defined($t[0])) {
      if(scalar(@t)>0) {
        $tt = join('',@t);
      }
    }
    if(!$tt) {return "unknown parameter";}
    return $tt."\nreturn code: ".$r;
  }
  
  if($cmd eq "version")
  {
    return $VERSION;
  }
  
  return "Unknown argument $cmd, choose one of update:noArg version:noArg list:devices,info,data,health";
}

sub SMARTMON_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  $attrVal= "" unless defined($attrVal);
  
  Log 5, "SMARTMON Attr: $cmd $name $attrName $attrVal";

  my $hash = $main::defs{$name};
  
  my $orig = AttrVal($name, $attrName, "");

  if( $cmd eq "set" ) {# set, del
    if( $orig ne $attrVal ) {
      
      $attr{$name}{$attrName} = $attrVal;
      
      if($attrName eq "disable") {
        # NOP
      }
      
      if($attrName eq "parameters") {
        $hash->{PARAMETERS}=$attrVal;
      }
      
      if($attrName eq "show_raw") {
        SMARTMON_refreshReadings($hash);  
      }
      
      if($attrName eq "include") {
        SMARTMON_refreshReadings($hash);  
      }
      
      if($attrName eq "show_device_info") {
        SMARTMON_refreshReadings($hash);  
      }

      #return $attrName ." set to ". $attrVal;
      return undef;
    }
  }
  
  if( $cmd eq "del" ) {# set, 
    if($attrName eq "show_raw") {
      delete $attr{$name}{$attrName};
      SMARTMON_refreshReadings($hash);  
    }
    
    if($attrName eq "show_device_info") {
      delete $attr{$name}{$attrName};
      SMARTMON_refreshReadings($hash);  
    }
    
    if($attrName eq "include") {
      delete $attr{$name}{$attrName};
      SMARTMON_refreshReadings($hash);  
    }

    if($attrName eq "parameters") {
        delete $hash->{PARAMETERS};
    }
  }
  
  return;
}

sub SMARTMON_Update($)
{
  my ($hash) = @_;

  SMARTMON_Log($hash, 5, "Update");
  
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SMARTMON_Update", $hash, 1);
  
  SMARTMON_refreshReadings($hash);
}

# Alle Readings neuerstellen
sub SMARTMON_refreshReadings($) {
  my ($hash) = @_;
  
  SMARTMON_Log($hash, 5, "Refresh readings");
  
  my $name = $hash->{NAME};
  
  readingsBeginUpdate($hash);
  
  if( AttrVal($name, "disable", "") eq "1" ) {
    SMARTMON_Log($hash, 5, "Update disabled");
    $hash->{STATE} = "Inactive";
  } else {
    # Parameter holen
    my $map = SMARTMON_obtainParameters($hash);
    
    $hash->{STATE} = "Active";

    foreach my $aName (keys %{$map}) {
      my $value = $map->{$aName};
      #SMARTMON_Log($hash, 5, "Update: ".$value);
      # Nur aktualisieren, wenn ein gueltiges Value vorliegt
      if(defined $value) {
        readingsBulkUpdate($hash,$aName,$value);
      }

    }
    
    # Alle anderen Readings entfernen
    foreach my $rName (sort keys %{$hash->{READINGS}}) {
      if(!defined($map->{$rName})) {
        delete $hash->{READINGS}->{$rName};
      }
    }
     
  }

  readingsEndUpdate($hash,1); 
}

# Alle Readings erstellen
sub SMARTMON_obtainParameters($) {
  my ($hash) = @_;
  SMARTMON_Log($hash, 5, "Obtain parameters");
  my $map;

  # /usr/sbin/smartctl in /etc/sudoers aufnehmen
  # fhem ALL=(ALL) NOPASSWD: [...,] /usr/sbin/smartctl 
  # Natuerlich muss der user auch der Gruppe "sudo" angehören.

  # Health  
  my $param="";
  if($hash->{PARAMETERS}) {$param=" ".$hash->{PARAMETERS};}
  my ($rcode, @adev_health) = SMARTMON_execute($hash, "sudo smartctl -H".$param." ".$hash->{DEVICE}." | grep 'test result:'");
  my $dev_health;
  my $tt;
  if(defined($adev_health[0])) {
    if(scalar(@adev_health)>0) {
      $dev_health = join('',@adev_health);
    }
  }

  delete $map->{"overall_health_test"};
  if(defined($dev_health)) {
    SMARTMON_Log($hash, 5, "health: $dev_health");
    if($dev_health=~m/test\s+result:\s+(\S+).*/) {
      $map->{"overall_health_test"} = $1;
    }
  }
  
  $map = SMARTMON_getSmartDataReadings($hash, $map);
  
  return $map;
}

# Readings zu gelesenen RAW-Daten
sub SMARTMON_getSmartDataReadings($$) {
  my ($hash, $map) = @_;
  
  my $name = $hash->{NAME};
  
  # Attribut lesen, splitten, als Keys eines Hashes setzen
  my $t_include = AttrVal($name, "include", undef);
  my %h_include;
  if(defined($t_include)) {
    my @a_include = split(/,\s*/, trim($t_include));
    %h_include = map { int($_) => 1 } @a_include; # 1 oder 001 soll gleichwertig sein
  }
  
  # S.M.A.R.T. RAW-Daten auslesen
  my $dmap = SMARTMON_readSmartData($hash, defined($t_include)?\%h_include:undef);
  #$dmap->{1}->{failed}="FAILING_NOW";
  # Bekannte Werte einspielen
  # per Referenz uebergeben!
  my $done_map = SMARTMON_interpretKnownData($hash, \%{$dmap}, \%{$map});

  my $cnt_oldage=0;
  my $cnt_prefail=0;
  my $sr = AttrVal($name, "show_raw", "0");
  foreach my $id (sort keys %{$dmap}) {
    if($id eq "RC") {next}
    # warnings zaehlen
    if($dmap->{$id}->{failed} ne "-") {
      if($dmap->{$id}->{type} eq "Pre-fail") {$cnt_prefail++;}
      if($dmap->{$id}->{type} eq "Old_age") {$cnt_oldage++;}
    }
    # restlichen RAW-Werte ggf. einspielen, per Attribut (show_raw) abschaltbar   
    if( $sr eq "1" || $sr eq "2" ) {
      # nur wenn noch nicht frueher interpretiert werden, 
      # oder wenn explizit erwuenscht (Attribut show_raw) 
      if(!defined($done_map->{$id}) || $sr eq "2") {
        my $m = $dmap->{$id};
        my $rName = $m->{name};
        #my $raw   = $dmap->{$id}->{raw};
        $map->{sprintf("%03d_%s",$id,$rName)} = 
           sprintf("Flag: %s Val: %s Worst: %s Thresh: %s ".
                   "Type: %s Updated: %s When_Failed: %s Raw: %s",
                   $m->{flag},$m->{value},$m->{worst},$m->{thresh},$m->{type},
                   $m->{updated},$m->{failed},$m->{raw});
      }
    }
  }
  
  $map->{warnings}="Pre-fail: $cnt_prefail Old_age: $cnt_oldage";
  
  SMARTMON_readDeviceData($hash, \%{$map});
    
  return $map;
}

sub SMARTMON_readDeviceData($%) {
  my ($hash, $map) = @_;

  my $param="";
  if($hash->{PARAMETERS}) {$param=" ".$hash->{PARAMETERS};}
  my ($r, @dev_data) = SMARTMON_execute($hash, "sudo smartctl -i".$param." ".$hash->{DEVICE});
  SMARTMON_Log($hash, 5, "device data: ".Dumper(@dev_data));
  my $sd = AttrVal($hash->{NAME}, "show_device_info", "0");
  if(defined($dev_data[0])) {
    while(scalar(@dev_data)>0) {
      my $line = $dev_data[0];
      shift @dev_data;
      my($k,$v) = split(/:\s*/,$line);
      $v = trim($v);
      if($k eq "Device Model") {
        $hash->{DEVICE_MODEL}=$v;
        $map->{"deviceModel"}=$v if($sd eq '1');
      }
      if($k eq "Serial Number") {
        $hash->{DEVICE_SERIAL}=$v;
        $map->{"deviceSerial"}=$v if($sd eq '1');
      }
      if($k eq "Firmware Version") {
        $hash->{DEVICE_FIRMWARE}=$v;
        $map->{"deviceFirmware"}=$v if($sd eq '1');
      }
      if($k eq "User Capacity") {
        $hash->{DEVICE_CAPACITY}=$v;
        $map->{"deviceCapacity"}=$v if($sd eq '1');
      }
    }
  }
  
}

# Readings zu bekannten Werten erstellen
sub SMARTMON_interpretKnownData($$$) {
  my ($hash, $dmap, $map) = @_;
  my $known;
  #$map->{TEST}="TestX";
  
  # smartctl 5.41 2011-06-09 r3365 [armv7l-linux-3.4.98-sun7i+] (local build)
  # Copyright (C) 2002-11 by Bruce Allen, http://smartmontools.sourceforge.net
  # 
  # === START OF READ SMART DATA SECTION ===
  # SMART Attributes Data Structure revision number: 16
  # Vendor Specific SMART Attributes with Thresholds:
  # ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  #   1 Raw_Read_Error_Rate     0x002f   200   200   051    Pre-fail  Always       -       0
  #   3 Spin_Up_Time            0x0027   184   183   021    Pre-fail  Always       -       1800
  #   4 Start_Stop_Count        0x0032   100   100   000    Old_age   Always       -       28
  #   5 Reallocated_Sector_Ct   0x0033   200   200   140    Pre-fail  Always       -       0
  #   7 Seek_Error_Rate         0x002e   200   200   000    Old_age   Always       -       0
  #   9 Power_On_Hours          0x0032   096   096   000    Old_age   Always       -       3444
  #  10 Spin_Retry_Count        0x0032   100   253   000    Old_age   Always       -       0
  #  11 Calibration_Retry_Count 0x0032   100   253   000    Old_age   Always       -       0
  #  12 Power_Cycle_Count       0x0032   100   100   000    Old_age   Always       -       28
  # 192 Power-Off_Retract_Count 0x0032   200   200   000    Old_age   Always       -       20
  # 193 Load_Cycle_Count        0x0032   200   200   000    Old_age   Always       -       7
  # 194 Temperature_Celsius     0x0022   103   097   000    Old_age   Always       -       44
  # 196 Reallocated_Event_Count 0x0032   200   200   000    Old_age   Always       -       0
  # 197 Current_Pending_Sector  0x0032   200   200   000    Old_age   Always       -       0
  # 198 Offline_Uncorrectable   0x0030   100   253   000    Old_age   Offline      -       0
  # 199 UDMA_CRC_Error_Count    0x0032   200   200   000    Old_age   Always       -       0
  # 200 Multi_Zone_Error_Rate   0x0008   100   253   000    Old_age   Offline      -       0

  
  if($dmap->{3}) {
    $map->{spin_up_time} = $dmap->{3}->{raw};
    $known->{3}=1;
  }
  if($dmap->{4}) {
    $map->{start_stop_count} = $dmap->{4}->{raw};
    $known->{4}=1;
  }
  if($dmap->{5}) {
    $map->{reallocated_sector_count} = $dmap->{5}->{raw};
    $known->{5}=1;
  }
  if($dmap->{9}) {
    $map->{power_on_hours} = $dmap->{9}->{raw};
    $map->{power_on_text} = SMARTMON_hour2Dauer($dmap->{9}->{raw});
    $known->{9}=1;
  }
  if($dmap->{10}) {
    $map->{spin_retry_count} = $dmap->{10}->{raw};
    $known->{10}=1;
  }
  if($dmap->{12}) {
    $map->{power_cycle_count} = $dmap->{12}->{raw};
    $known->{12}=1;
  }

  if($dmap->{190}) {
    $map->{airflow_temperature} = $dmap->{190}->{raw};
    $known->{190}=1;
  }
  if($dmap->{194}) {
    $map->{temperature} = $dmap->{194}->{raw};
    $known->{194}=1;
  }
  
  # TODO
  
  if($dmap->{"RC"}) {
    $map->{last_exit_code} = $dmap->{"RC"}->{raw};
    $known->{"RC"}=1;
  }
  
  return $known;
}

# Ausrechnet aus der Zahl der Sekunden Anzeige in Tagen:Stunden:Minuten:Sekunden.
sub SMARTMON_sec2Dauer($){
  my ($t) = @_;
  my $d = int($t/86400);
  my $r = $t-($d*86400);
  my $h = int($r/3600);
     $r = $r - ($h*3600);
  my $m = int($r/60);
  my $s = $r - $m*60;
  return sprintf("%02d Tage %02d Std. %02d Min. %02d Sec.",$d,$h,$m,$s);
}

# Ausrechnet aus der Zahl der Stunden Anzeige in Tagen:Stunden:Minuten:Sekunden.
sub SMARTMON_hour2Dauer($){
  my ($t) = @_;
  #return SMARTMON_sec2Dauer($t*3600);
  $t =~ /([0-9]*)/;
  my $d=int($1/24);
  $t = $1-($d*24);
  #my $d=int($t/24);
  #$t = $t-($d*24);
  my $y=int($d/365);
  $d = $d-($y*365);
  return sprintf("%d Jahre %d Tage %d Std.",$y,$d,$t);
}

# liest RAW-Daten
# Params: 
#  HASH: Device-HASH 
#  Include-HASH: Wenn definiert,werden nur die ID zurueckgegeben, die in 
#   diesem HASH enthalten sind.
sub SMARTMON_readSmartData($;$) {
  my ($hash, $include) = @_;
  my $map;

  my $param="";
  if($hash->{PARAMETERS}) {$param=" ".$hash->{PARAMETERS};}
  my ($r, @dev_data) = SMARTMON_execute($hash, "sudo smartctl -A".$param." ".$hash->{DEVICE});
  SMARTMON_Log($hash, 5, "device SMART data: ".Dumper(@dev_data));
  if(defined($r)) {$map->{"RC"}->{raw} = $r;}
  if(defined($dev_data[0])) {
    while(scalar(@dev_data)>0) {
      shift @dev_data;
      if(scalar(@dev_data)>0 && $dev_data[0]=~m/ID#.*/) {
        shift @dev_data;
        while(scalar(@dev_data)>0) {
          my ($d_id, $d_attr_name, $d_flag, $d_value, $d_worst, $d_thresh, 
              $d_type, $d_updated, $d_when_failed, $d_raw_value) 
              = split(/\s+/, trim($dev_data[0]));
          shift @dev_data;
          
          if(!defined($include) || defined($include->{$d_id})) {
            if(defined($d_attr_name)) {
              #$map->{$d_attr_name} = "Value: $d_value, Worst: $d_worst, Type: $d_type, Raw: $d_raw_value";
              $map->{$d_id}->{name}    = $d_attr_name;
              $map->{$d_id}->{flag}    = $d_flag;
              $map->{$d_id}->{value}   = $d_value;
              $map->{$d_id}->{worst}   = $d_worst;
              $map->{$d_id}->{thresh}  = $d_thresh;
              $map->{$d_id}->{type}    = $d_type;
              $map->{$d_id}->{updated} = $d_updated;
              $map->{$d_id}->{failed}  = $d_when_failed;
              $map->{$d_id}->{raw}     = $d_raw_value;
            }
          }
        }
      }
    }
  }
  
  return $map;
} 

# BS-Befehl ausfuehren
sub SMARTMON_execute($$) {
  my ($hash, $cmd) = @_;
  
  SMARTMON_Log($hash, 5, "Execute: $cmd");
  
  local $SIG{'CHLD'}='DEFAULT';
  my @ret = qx($cmd);
  my $rcode = $?>>8;
  SMARTMON_Log($hash, 5, "Returncode: ".$rcode);
  return ($rcode,@ret);
}

1;

=pod
=item device
=item summary    provides some statistics about the S.M.A.R.T. capable drive
=item summary_DE liefert einige Statistiken ueber S.M.A.R.T. kompatible Ger&auml;te
=begin html

<!-- ================================ -->
<a name="SMARTMON"></a>
<h3>SMARTMON</h3>
<ul>
  This module is a FHEM frontend to the Linux tool smartctl.
  It provides various information on the SMART System of the hard drive.
  <br><br>
  <b>Define</b>
  <br><br>
    <code>define &lt;name&gt; SMARTMON &lt;device&gt; [&lt;Interval&gt;]</code><br>
    <br>
    This statement creates a new SMARTMON instance.
    The parameters specify a device to be monitored and the update interval in minutes.<br>
    <br>
    
    Example: <code>define sm SMARTMON /dev/sda 60</code>
    <br>
  <br>

  <b>Readings:</b>
  <br><br>
  <ul>
    <li>last_exit_code<br>
        Exit code of smartctl.
    </li>
    <li>overall_health_test<br>
        Specifies the general condition of the HDD (PASSED or FAILED).
    </li>
    <br>
    <li>warnings<br>
        Specifies the number of stored alerts.
    </li>
    <br>
    Furthermore, the available SMART parameters can be displayed as Readings (RAW and / or (partially) interpreted).
  </ul>
  <br>

  <b>Get:</b><br><br>
    <ul>
    <li>version<br>
    Displays the module version.
    </li>
    <br>
    <li>update<br>
    Updates all readings.
    </li>
    <br>
    <li>list<br>
    Displays various information:
     <ul>
      <li>devices:<br>List of available devices in the system.</li>
     </ul><br>
     <ul>
      <li>info:<br>Information about the current device.</li>
     </ul><br>
     <ul>
      <li>data:<br>List of SMART parameters for the current device.</li>
     </ul><br>
     <ul>
      <li>health:<br>Information about overall health status for the device.</li>
     </ul><br>
     For the Last 3 commands can also be another Device specified (as an additional parameter).
    </li>
    <br>
    </ul><br>

  <b>Attributes:</b><br><br>
    <ul>
    <li>show_raw<br>
    Valid values: 0: no RAW Readings (default), 1: show all, are not included in interpreted Readings, 2: show all.
    </li>
    <br>
    <li>show_device_info<br>
    Valid values: 0: no device info as reading, 1: show show device info as readings.
    </li>
    <br>
    <li>include<br>
    Comma separated list of IDs for desired SMART parameters. If nothing passed, all available values are displayed.
    </li>
    <br>
    <li>disable<br>
    Valid values: 0: Module active (default), 1: module is disabled (no updates).
    </li>
    <br>
    <li>parameters<br>
    Additional values for smartctl.
    </li>
    <br>
    </ul><br>
    For more information see smartctrl documentation.
  </ul>
<!-- ================================ -->

=end html
=begin html_DE

<a name="SMARTMON"></a>
<h3>SMARTMON</h3>
<ul>
  Dieses Modul ist ein FHEM-Frontend zu dem Linux-Tool smartctl. 
  Es liefert diverse Informationen zu dem S.M.A.R.T. System einer Festplatte.
  <br><br>
  <b>Define</b>
  <br><br>
    <code>define &lt;name&gt; SMARTMON &lt;device&gt; [&lt;Interval&gt;]</code><br>
    <br>
    Diese Anweisung erstellt eine neue SMARTMON-Instanz.
    Die Parameter geben ein zu &uuml;berwachenden Ger&auml;t und den Aktualisierungsinterval in Minuten an.<br>
    <br>
    
    Beispiel: <code>define sm SMARTMON /dev/sda 60</code>
    <br>
  <br>

  <b>Readings:</b>
  <br><br>
  <ul>
    <li>last_exit_code<br>
        Gibt den Exitcode bei der letzten Ausf&uuml;hrung vom smartctl.
    </li>
    <br>
    <li>overall_health_test<br>
        Gibt den allgemeinen Zustand der Platte an. Kann PASSED oder FAILED sein.
    </li>
    <br>
    <li>warnings<br>
        Gibt die Anzahl der vermerkten Warnungen an.
    </li>
    <br>
    Weiterhin k&ouml;nnen die verf&uuml;gbaren SMART-Parameter als Readings angezeigt werden (RAW und/oder (teilweise) interpretiert).
  </ul>
  <br>

  <b>Get:</b><br><br>
    <ul>
    <li>version<br>
    Zeigt die verwendete Modul-Version an.
    </li>
    <br>
    <li>update<br>
    Veranlasst die Aktualisierung der gelesenen Parameter.
    </li>
    <br>
    <li>list<br>
    Zeigt verschiedenen Informationen an:
     <ul>
      <li>devices:<br>Liste der im System verf&uuml;gbaren Ger&auml;ten.</li>
     </ul><br>
     <ul>
      <li>info:<br>Information zu dem aktuellen Ger&auml;t.</li>
     </ul><br>
     <ul>
      <li>data:<br>Liste der SMART-Parameter zu dem aktuellen Ger&auml;t.</li>
     </ul><br>
     <ul>
      <li>health:<br>Information zu dem allgemeinen Gesundheitsstatus f&uuml;r das verwendete Ger&auml;t.</li>
     </ul><br>
     F&uuml;r letzten 3 Befehle kann auch noch ein anderes Ger&auml;t als zus&auml;tzliche Parameter mitgegeben werden.
    </li>
    <br>
    </ul><br>

  <b>Attributes:</b><br><br>
    <ul>
    <li>show_raw<br>
    G&uuml;ltige Werte: 0: keine RAW-Readings anzeigen (default), 1: alle anzeigen, die nicht in interpretierten Readings enthalten sind, 2: alle anzeigen.
    </li>
    <br>
    <li>show_device_info<br>
    G&uuml;ltige Werte: 0: keine Ger&auml;teinforamtionen in readings, 1: Ger&auml;teinformationen in readings anzeigen.
    </li>
    <br>
    <li>include<br>
    Kommaseparierte Liste der IDs gew&uuml;nschten SMART-Parameter. Wenn nichts angegeben, werden alle verf&uuml;gbaren angezeigt.
    </li>
    <br>
    <li>disable<br>
    G&uuml;ltige Werte: 0: Modul aktiv (default), 1: Modul deaktiviert (keine Aktualisierungen).
    </li>
    <br>
    <li>parameters<br>
    Zusatzparameter f&uuml;r den Aufruf von smartctl.
    </li>
    <br>
    </ul><br>
    F&uuml;r weitere Informationen wird die smartctrl-Dokumentation empfohlen.

  </ul>

=end html_DE
=cut

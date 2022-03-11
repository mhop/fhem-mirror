##############################################
# $Id$
#

package FHEM::attrT_go_e_Utils;    ## no critic 'Package declaration'

use strict;
use warnings;
#use Time::HiRes qw( gettimeofday );
#use List::Util qw( min max );

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          AttrVal
          InternalVal
          ReadingsVal
          ReadingsNum
          ReadingsAge
          json2nameValue
          defs
          )
    );
}

sub ::attrT_go_e_Utils_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

my %jsonmap = ( 
    "alw" => "allow_charging", 
    "amp" => "ampere", 
    "tmp" => "temperature", 
    "rbc" => "reboot_counter",
    "rbt" => "reboot_timer",
    "err" => "error",
    "ast" => "access_state",
    "stp" => "stop_state",
    "cbl" => "cable_code",
    "pha" => "phase",
    "dws" => "deca_watt_sec",
    "dwo" => "stop_energy",
    "adi" => "adapter_in",
    "uby" => "unlocked_by",
    "eto" => "energy_total",
    "wst" => "wifi_state",
    "nrg_1" => "voltage_l1",
    "nrg_2" => "voltage_l2",
    "nrg_3" => "voltage_l3",
    "nrg_4" => "voltage_n",
    "nrg_5" => "ampere_l1",
    "nrg_6" => "ampere_l2",
    "nrg_7" => "ampere_l3",
    "nrg_8" => "power_l1",
    "nrg_9" => "power_l2",
    "nrg_10" => "power_l3",
    "nrg_11" => "power_n",
    "nrg_12" => "power_total",
    "nrg_13" => "power_factor_l1",
    "nrg_14" => "power_factor_l2",
    "nrg_15" => "power_factor_l3",
    "nrg_16" => "power_factor_n",
    "fwv" => "firmware_version",
    "sse" => "serial_number",
    "wss" => "wifi_ssid",
    "wke" => "wifi_key",
    "wen" => "wifi_enabled",
    "tof" => "time_offset",
    "tds" => "daylight_saving_offset",
    "lbr" => "led_brightness",
    "aho" => "hours_charging",
    "afi" => "time_charging",
    "azo" => "awattar_zone",
    "ama" => "max_ampere",
    "al1" => "ampere_level1",
    "al2" => "ampere_level2",
    "al3" => "ampere_level3",
    "al4" => "ampere_level4",
    "al5" => "ampere_level5",
    "cid" => "color_idle",
    "cch" => "color_charging",
    "cfi" => "color_charging_done",
    "lse" => "led_save_energy",
    "ust" => "unlock_state",
    "wak" => "wifi_hotspot_key",
    "r1x" => "flags",
    "dto" => "remaining_time",
    "nmo" => "norway_mode",
    "eca" => "rfid1_energy",
    "ecr" => "rfid2_energy",
    "ecd" => "rfid3_energy",
    "ec4" => "rfid4_energy",
    "ec5" => "rfid5_energy",
    "ec6" => "rfid6_energy",
    "ec7" => "rfid7_energy",
    "ec8" => "rfid8_energy",
    "ec9" => "rfid9_energy",
    "ec1" => "rfid10_energy",
    "rca" => "rfid1_id",
    "rcr" => "rfid2_id",
    "rcd" => "rfid3_id",
    "rc4" => "rfid4_id",
    "rc5" => "rfid5_id",
    "rc6" => "rfid6_id",
    "rc7" => "rfid7_id",
    "rc8" => "rfid8_id",
    "rc9" => "rfid9_id",
    "rc1" => "rfid10_id",
    "rna" => "rfid1_name",
    "rnm" => "rfid2_name",
    "rne" => "rfid3_name",
    "rn4" => "rfid4_name",
    "rn5" => "rfid5_name",
    "rn6" => "rfid6_name",
    "rn7" => "rfid7_name",
    "rn8" => "rfid8_name",
    "rn9" => "rfid9_name",
    "rn1" => "rfid10_name",
    "tma_1" => "internal_temperature_sensor_1",
    "tma_2" => "internal_temperature_sensor_2",
    "tma_3" => "internal_temperature_sensor_3",
    "tma_4" => "internal_temperature_sensor_4",
    "amt" => "max_ampere_temperature",
    "tme" => "time",
    "sch" => "scheduler",
    "sdp" => "scheduler_double_press",
    "upd" => "update_available",
    "cdi" => "cloud_disabled",
    "loe" => "loadmanagement_enabled",
    "lot" => "loadmanagement_total_ampere",
    "lom" => "loadmanagement_min_ampere",
    "lop" => "loadmanagement_priority",
    "log" => "loadmanagement_group_id",
    "lon" => "loadmanagement_number_charger",
    "lof" => "loadmanagement_fallback_ampere",
    "loa" => "loadmanagement_ampere",
    "lch" => "loadmanagement_seconds_power",
    "mce" => "mqtt_enabled",
    "mcs" => "mqtt_server",
    "mcp" => "mqtt_port",
    "mcu" => "mqtt_username",
    "mck" => "mqtt_key",
    "mcc" => "mqtt_connected"
);

my %stationStates = (
    "none" => "-1",
    "1" => "Ready",
    "2" => "Charging",
    "3" => "waiting for car",
    "4" => "Charging finished"
);

my %todelete = (
  "always"  => ["wifi_key","reboot_timer","loadmanagement_seconds_power","time"], 
  "hourly"  => ["mqtt_enabled","mqtt_server","mqtt_port","mqtt_username","mqtt_key","mqtt_connected"]
);

sub j2rN_extended {
  my $name    = shift;
  my $event   = shift // return;
  my $useSNrs = shift // 0;
  my $aDiffV  = shift; #absolute voltage difference for eocr
  my $rDiffV  = shift; #relative voltage difference for eocr (in %)
  my $tDiffV  = shift // 600; #max timespan for triggering next value w/o changes; (defaults to 10 minutes)
  my $aDiffA  = shift; #absolute ampere difference for eocr
  my $rDiffA  = shift; #relative ampere difference for eocr (in %)
  my $tDiffA  = shift // $tDiffV; #max timespan, s.a.
  my $aDiffP  = shift; #absolute kW difference for eocr
  my $rDiffP  = shift; #relative kW difference for eocr (in %)
  my $tDiffP  = shift // $tDiffA; #max timespan, s.a.
  my $aDiffwF = shift; #absolute Leistungsfaktor difference for eocr
  my $rDiffwF = shift; #relative Leistungsfaktor difference for eocr (in %)
  my $tDiffwF = shift // $tDiffA; #max timespan, s.a.
  
  
  #Array mit Werten des Strom- und Spannungssensors
  #nrg[0]​: Spannung auf L1 in Volt
  #nrg[1]​: Spannung auf L2 in Volt
  #nrg[2]​: Spannung auf L3 in Volt
  #nrg[3]​: Spannung auf N in Volt
  #nrg[4]​: Ampere auf L1 in 0.1A ​(123 entspricht 12,3A)
  #nrg[5]​: Ampere auf L2 in 0.1A
  #nrg[6]​: Ampere auf L3 in 0.1A
  #nrg[7]​: Leistung auf L1 in 0.1kW ​(36 entspricht 3,6kW)
  #nrg[8]​: Leistung auf L2 in 0.1kW
  #nrg[9]​: Leistung auf L3 in 0.1kW
  #nrg[10]​: Leistung auf N in 0.1kW
  #nrg[11]​: Leistung gesamt  in 0.01kW ​(360 entspricht 3,6kW)
  #nrg[12]​: Leistungsfaktor auf L1 in %
  #nrg[13]​: Leistungsfaktor auf L2 in %
  #nrg[14]​: Leistungsfaktor auf L3 in %
  #nrg[15]​: Leistungsfaktor auf N in %
  
  my %toCompare = (
    "Voltage" => { 
      "a" => $aDiffV,
      "r" => $rDiffV,
      "t" => $tDiffV,
      "elements"  => ["voltage_l1","voltage_l2","voltage_l3"]
    },
    "Ampere" => { 
      "a" => $aDiffA,
      "r" => $rDiffA,
      "t" => $tDiffA
    },
    "Power" => { 
      "a" => $aDiffP,
      "r" => $rDiffP,
      "t" => $tDiffP
    },
    "PowerFactor" => { 
      "a" => $aDiffwF,
      "r" => $rDiffwF,
      "t" => $tDiffwF
    }
  );
  
  my $rets = json2nameValue($event); #get reference to a flat hash
  
  #renaming; adopted form fhem.pl, end of json2nameValue()
  my %ret2;
  for my $kname (keys %$rets) {
    my $oname = $kname;
    if(defined($jsonmap{$kname})) {
      next if(!$jsonmap{$kname});
      $kname = $jsonmap{$kname};
    }
    $ret2{$kname} = $rets->{$oname};
  }
  
  #replace stationStates
  $ret2{car} = $stationStates{$ret2{car}} if !$useSNrs;
  
  for my $obsolete (@{$todelete{always}}) {
    delete $ret2{$obsolete}; 
  }
  
  for my $kname (keys %ret2) {
    delete $ret2{$kname} if $ret2{$kname} eq "";
  }
  
  my $firstelement = ${$todelete{hourly}}[0];
  my $lastloop = ReadingsAge($name, $firstelement, 10000000);
  
  if ($lastloop < 3600) {
    for my $obsolete (@{$todelete{hourly}}) {
      delete $ret2{$obsolete}; 
    }
  } else {
    for my $obsolete (@{$todelete{hourly}}) {
      delete $ret2{$obsolete} if ReadingsVal($name,$obsolete,"unknown") eq $ret2{$obsolete}; 
    }
  }
  
  sub
  compAbs {
    my ($ret,$name,$val,$limit) = @_;
    my $actual = ReadingsNum($name,$ret,0);
    return 1 if $val >= $actual - $limit && $val <= $actual + $limit;
    return;
  }
  
  sub
  compRel {
    my ($ret,$name,$val,$limit) = @_;
    my $actual = ReadingsNum($name,$ret,0);
    return 1 if $val >= $actual*(1 - $limit) && $val <= $actual*( 1 + $limit);
    return;
  }

  $firstelement = ${$toCompare{Voltage}}{elements}[0];
  $lastloop = ReadingsAge($name, $firstelement, 10000000);
  if ($firstelement && $lastloop < $toCompare{Voltage}{t}) {
    for my $obsolete (@{$toCompare{Voltage}{elements}}) {
      delete $ret2{$obsolete} if compAbs($obsolete, $name, $ret2{$obsolete}, $toCompare{Voltage}{a}) && compRel($obsolete, $name, $ret2{$obsolete}, $toCompare{Voltage}{r}) ; 
    }
  }
  
  #main loop for comparisons
  for my $k (sort keys %ret2) {
    
  }
  
  return \%ret2;
}


1;

__END__

=pod
=begin html

<a id="attrT_go_e_Utils"></a>
<h3>attrT_go_e_Utils</h3>
<ul>
  <b>Functions to support attrTemplates for go-e-Chargers</b><br> 
</ul>
<ul>
  <li><b>FHEM::attrT_go_e_Utils::j2rN_extended</b><br>
  <code>FHEM::attrT_go_e_Utils::j2rN_extended($$,$$$$$$$$$$$$$)</code><br>
  This is an extended wrapper to fhem.pl json2nameValue() to prevent the device "spamming" FHEM with a lot of obsolete, unwanted, not changed and cryptically named readings due to a very poorly programmed MQTT interface. First two parameters ($NAME (device name) and $EVENT (original JSON payload)) are mandatory, next is recommended to be set to 1 to show station numbers, all the remaining parameters may allow tweaking the exact behaviour of the internal "event-on-change-reading" (and so on) mechanisms and may be subject to changes...<br>
  There may be room for improvement, please adress any issues in https://forum.fhem.de/index.php/topic,115620.0.html.
  </li>
</ul>
=end html
=cut
 

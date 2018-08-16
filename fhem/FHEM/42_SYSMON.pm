################################################################
#
#  Copyright notice
#
#  (c) 2013 Alexander Schulz
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
#
# SSH support by PitpatV 
#
################################################################

# $Id$

package main;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

use Blocking;

use Data::Dumper;

my $missingModulRemote;
eval "use Net::Telnet;1" or $missingModulRemote .= "Net::Telnet ";

my $VERSION = "2.3.3";

use constant {
  PERL_VERSION    => "perl_version",
  DATE            => "date",
  UPTIME          => "uptime",
  UPTIME_TEXT     => "uptime_text",
  STARTTIME_TEXT  => "starttime_text",
  STARTTIME       => "starttime",
  FHEMSTARTTIME_TEXT => "fhemstarttime_text",
  FHEMSTARTTIME   => "fhemstarttime",
  FHEMUPTIME      => "fhemuptime",
  FHEMUPTIME_TEXT => "fhemuptime_text",
  IDLETIME        => "idletime",
  IDLETIME_TEXT   => "idletime_text"
};

use constant {
	CPU_CORE_CNT  => "cpu_core_count",
  CPU_FREQ      => "cpu_freq",
  CPU0_FREQ     => "cpu0_freq",
  CPU1_FREQ     => "cpu1_freq",
  CPU2_FREQ     => "cpu2_freq",
  CPU3_FREQ     => "cpu3_freq",
  CPU4_FREQ     => "cpu4_freq",
  CPU5_FREQ     => "cpu5_freq",
  CPU6_FREQ     => "cpu6_freq",
  CPU7_FREQ     => "cpu7_freq",
  CPU_BOGOMIPS => "cpu_bogomips",
  CPU_MODEL_NAME=>"cpu_model_name",
  CPU_TEMP     => "cpu_temp",
  CPU0_TEMP     => "cpu0_temp",
  CPU1_TEMP     => "cpu1_temp",
  CPU2_TEMP     => "cpu2_temp",
  CPU3_TEMP     => "cpu3_temp",
  CPU4_TEMP     => "cpu4_temp",
  CPU5_TEMP     => "cpu5_temp",
  CPU6_TEMP     => "cpu6_temp",
  CPU7_TEMP     => "cpu7_temp",
  CPU_TEMP_AVG => "cpu_temp_avg",
  CPU0_TEMP_AVG => "cpu0_temp_avg",
  CPU1_TEMP_AVG => "cpu1_temp_avg",
  CPU2_TEMP_AVG => "cpu2_temp_avg",
  CPU3_TEMP_AVG => "cpu3_temp_avg",
  CPU4_TEMP_AVG => "cpu4_temp_avg",
  CPU5_TEMP_AVG => "cpu5_temp_avg",
  CPU6_TEMP_AVG => "cpu6_temp_avg",
  CPU7_TEMP_AVG => "cpu7_temp_avg",
  LOADAVG      => "loadavg"
};

use constant {
  RAM  => "ram",
  SWAP => "swap"
};

use constant {
  ETH0        => "eth0",
  WLAN0       => "wlan0",
  DIFF_SUFFIX => "_diff",
  SPEED_SUFFIX => "_speed",
  IP_SUFFIX   => "_ip",
  IP6_SUFFIX  => "_ip6",
  FB_WLAN_STATE       => "wlan_state",
  FB_WLAN_GUEST_STATE => "wlan_guest_state",
  FB_INET_IP          => "internet_ip",
  FB_INET_STATE       => "internet_state",
  FB_N_TIME_CTRL      => "night_time_ctrl",
  FB_NUM_NEW_MESSAGES => "num_new_messages",
  FB_FW_VERSION       => "fw_version_info",
  FB_DECT_TEMP        => "dect_temp",
    
  FB_DSL_RATE         => "dsl_rate",
  FB_DSL_SYNCTIME     => "dsl_synctime",
  FB_DSL_FEC_15       => "dsl_fec_15",
  FB_DSL_CRC_15       => "dsl_crc_15",
};

use constant FS_PREFIX => "~ ";
#use constant FS_PREFIX_N => "fs_";
my $DEFAULT_INTERVAL_BASE = 60;

sub
SYSMON_Initialize($)
{
  my ($hash) = @_;

  SYSMON_Log($hash, 5, "");

  $hash->{DefFn}    = "SYSMON_Define";
  $hash->{UndefFn}  = "SYSMON_Undefine";
  $hash->{GetFn}    = "SYSMON_Get";
  $hash->{SetFn}    = "SYSMON_Set";
  $hash->{AttrFn}   = "SYSMON_Attr";
  $hash->{AttrList} = "filesystems network-interfaces user-defined disable:0,1 nonblocking:0,1 ".
                      "telnet-time-out ".
                      "user-fn2 user-fn ".
                      "telnet-prompt-regx telnet-login-prompt-regx ".
                      "exclude ".
                       $readingFnAttributes;
}
### attr NAME user-defined osUpdates:1440:Aktualisierungen:cat ./updates.txt [,<readingsName>:<Interval_Minutes>:<Comment>:<Cmd>]

sub
SYSMON_Define($$)
{
  my ($hash, $def) = @_;

  SYSMON_Log($hash, 5, "$def");

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> SYSMON [MODE[:[USER@]HOST][:PORT]] [M1 [M2 [M3 [M4]]]]"  if(@a < 2);
  # define sysmon SYSMON local
  # define sysmon SYSMON local 1 1 1 10
  # define sysmon SYSMON telnet:fritz.box
  # define sysmon SYSMON telnet:fritz.box:23
  # define sysmon SYSMON telnet:fritz.box:23 10 10 10 60
  # define sysmon SYSMON telnet:user@fritz.box:23
  
  if(int(@a)>=3)
  {
    my @na = @a[2..scalar(@a)-1];  
    
    # wenn das erste Element nicht numerisch
    if(!($na[0] =~ /^\d+$/)) {
      # set mode/host/port
      my($mode, $host, $port) = split(/:/, $na[0]);
      $mode=lc($mode);
      # TODO SSH
      if(defined($mode)&&($mode eq 'local' || $mode eq 'telnet' || $mode eq 'ssh')) {
        $hash->{MODE} = $mode;
        delete($hash->{HOST});
        delete($hash->{USER});
        # erkennen, wenn User angegeben ist
        if($host) {
          my($user,$th) = split(/@/,$host);
          if(defined($th)) {
            $hash->{USER} = lc($user);
            $host = $th;
          }
          $hash->{HOST} = lc($host) if(defined($host));
          # DefaultPort je nach Protokol
          if(!defined($port)) {
            $port = '23' if($mode eq 'telnet');
            $port = '22' if($mode eq 'ssh');
          }
          $hash->{PORT} = lc($port);
        }
      } else {
        return "unexpected mode. Use local, ssh or telnet only.";
      }
      shift @na;
    } else {
      $hash->{MODE}='local';
    }

    SYSMON_setInterval($hash, @na);
  } else {
    $hash->{MODE}='local';
    SYSMON_setInterval($hash, undef);
  }

  $hash->{STATE} = "Initialized";

  #$hash->{DEF_TIME} = time() unless defined($hash->{DEF_TIME});

  #SYSMON_updateCurrentReadingsMap($hash);

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL_BASE}, "SYSMON_Update", $hash, 0);

  #$hash->{LOCAL} = 1;
  #SYSMON_Update($hash); #-> so nicht. hat im Startvorgang gelegentlich (oft) den Server 'aufgehaengt'
  #delete $hash->{LOCAL};
  
  return undef;
}

sub
SYSMON_setInterval($@)
{
  my ($hash, @a) = @_;

  my $interval = $DEFAULT_INTERVAL_BASE;
  $hash->{INTERVAL_BASE} = $interval;

  my $p1=1;
  my $p2=1;
  my $p3=1;
  my $p4=10;

  if(defined($a[0]) && int($a[0]) eq $a[0]) {$p1 = $a[0];}
  if(defined($a[1]) && int($a[1]) eq $a[1]) {$p2 = $a[1];} else {$p2 = $p1;}
  if(defined($a[2]) && int($a[2]) eq $a[2]) {$p3 = $a[2];} else {$p3 = $p1;}
  if(defined($a[3]) && int($a[3]) eq $a[3]) {$p4 = $a[3];} else {$p4 = $p1*10;}

  $hash->{INTERVAL_MULTIPLIERS} = $p1." ".$p2." ".$p3." ".$p4;
}


#my $cur_readings_map; => $hash->{helper}{cur_readings_map}
sub
SYSMON_updateCurrentReadingsMap($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  if( AttrVal($name, "disable", "") eq "1" ) {
    return undef;
  }

  my $rMap;
  
  # Map aktueller Namen erstellen
  
  # Feste Werte
  my $mode = $hash->{MODE};#AttrVal( $name, 'mode', 'local');
  if($mode eq 'local'){
    $rMap->{+PERL_VERSION}       = "Perl Version";
  }
  $rMap->{+DATE}               = "Date";
  $rMap->{+CPU_BOGOMIPS}       = "BogoMIPS";
  $rMap->{+CPU_MODEL_NAME}       = "CPU model name";
  if(SYSMON_isCPUFreqRPiBBB($hash)) {
    $rMap->{"cpu_freq"}       = "CPU frequency";
    $rMap->{"cpu0_freq"}       = "CPU frequency";
    $rMap->{"cpu_freq_stat"}       = "CPU frequency stat";
    $rMap->{"cpu0_freq_stat"}       = "CPU frequency stat";
  }
  foreach my $li (0..7) {
    if(SYSMON_isCPUXFreq($hash, $li)) {
      $rMap->{"cpu".$li."_freq"}        = "CPU frequency (core $li)";
      $rMap->{"cpu".$li."_freq_stat"}        = "CPU frequency (core $li) stat";
    }
  }
  if(SYSMON_isCPUTempRPi($hash) || SYSMON_isCPUTempBBB($hash) || SYSMON_isCPUTempFB($hash)) {
    #$rMap->{+CPU_TEMP}       = "CPU Temperatur";
    #$rMap->{"cpu_temp_avg"}  = "Durchschnittliche CPU Temperatur";
    $rMap->{+CPU_TEMP}        = "CPU temperature";
    $rMap->{+CPU_TEMP.'_stat'}= "CPU temperature stat";
    #$rMap->{"cpu0_temp"}      = "CPU temperature (core 0)";
    $rMap->{"cpu_temp_avg"}   = "Average CPU temperature";
    #$rMap->{"cpu0_temp_avg"}   = "Average CPU temperature (core 0)";
  }
  foreach my $li (0..7) {
    if(SYSMON_isCPUTemp_X($hash, $li)) {
      $rMap->{"cpu".$li."_temp"}      = "CPU temperature (core $li)";
      $rMap->{"cpu".$li."_temp_avg"}  = "Average CPU temperature (core $li)";
      $rMap->{"cpu".$li."_temp_stat"} = "CPU temperature stat (core $li)";
    }
  }  
  
  $rMap->{+CPU_CORE_CNT}   = "Number of CPU cores";
  
  if(SYSMON_isSysPowerAc($hash)) {
    #$rMap->{"power_ac_online"}  = "AC-Versorgung Status";
    #$rMap->{"power_ac_present"} = "AC-Versorgung vorhanden";
    #$rMap->{"power_ac_current"} = "AC-Versorgung Strom";
    #$rMap->{"power_ac_voltage"} = "AC-Versorgung Spannung";
    $rMap->{"power_ac_stat"}    = "AC-Versorgung Info";
    $rMap->{"power_ac_text"}    = "AC-Versorgung Info";
  }

  if(SYSMON_isSysPowerUsb($hash)) {
    #$rMap->{"power_usb_online"}  = "USB-Versorgung Status";
    #$rMap->{"power_usb_present"} = "USB-Versorgung vorhanden";
    #$rMap->{"power_usb_current"} = "USB-Versorgung Strom";
    #$rMap->{"power_usb_voltage"} = "USB-Versorgung Spannung";
    $rMap->{"power_usb_stat"}    = "USB-Versorgung Info";
    $rMap->{"power_usb_text"}    = "USB-Versorgung Info";
  }
  
  if(SYSMON_isSysPowerBat($hash)) {
    #$rMap->{"power_battery_online"}  = "Batterie-Versorgung Status";
    #$rMap->{"power_battery_present"} = "Batterie-Versorgung vorhanden";
    #$rMap->{"power_battery_current"} = "Batterie-Versorgung Strom";
    #$rMap->{"power_battery_voltage"} = "Batterie-Versorgung Spannung";
    $rMap->{"power_battery_stat"}    = "Batterie-Versorgung Info";
    $rMap->{"power_battery_text"}    = "Batterie-Versorgung  Info";
    $rMap->{"power_battery_info"}    = "Batterie-Versorgung  Zusatzinfo";
  }

  #$rMap->{"fhemuptime"}      = "Betriebszeit FHEM";
  #$rMap->{"fhemuptime_text"} = "Betriebszeit FHEM";
  #$rMap->{"idletime"}        = "Leerlaufzeit";
  #$rMap->{"idletime_text"}   = "Leerlaufzeit";
  #$rMap->{"loadavg"}         = "Durchschnittliche Auslastung";
  #$rMap->{"ram"}             = "RAM";
  #$rMap->{"swap"}            = "Swap";
  #$rMap->{"uptime"}          = "Betriebszeit";
  #$rMap->{"uptime_text"}     = "Betriebszeit";
  $rMap->{"fhemuptime"}      = "System up time";
  $rMap->{"fhemuptime_text"} = "FHEM up time";
  $rMap->{"idletime"}        = "Idle time";
  $rMap->{"idletime_text"}   = "Idle time";
  $rMap->{"loadavg"}         = "Load average";
  $rMap->{"loadavg_1"}       = "Load average 1";
  $rMap->{"loadavg_5"}       = "Load average 5";
  $rMap->{"loadavg_15"}      = "Load average 15";
  
  $rMap->{"ram"}             = "RAM";
  $rMap->{"ram_used_stat"}   = "RAM used stat";
  $rMap->{"ram_total"}       = "RAM total";
  $rMap->{"ram_used"}        = "RAM used";
  $rMap->{"ram_free"}        = "RAM free";
  $rMap->{"ram_free_percent"}= "RAM free %";
  
  $rMap->{"swap"}            = "swap";
  $rMap->{"swap_used_stat"}  = "swap used stat";
  $rMap->{"swap_total"}      = "swap total";
  $rMap->{"swap_used"}       = "swap used";
  $rMap->{"swap_free"}       = "swap free";
  $rMap->{"swap_used_percent"}= "swap used %";
  
  $rMap->{"uptime"}          = "System up time";
  $rMap->{"uptime_text"}     = "System up time";
  $rMap->{+STARTTIME_TEXT}   = "System start time";
  $rMap->{+STARTTIME}        = "System start time";

  $rMap->{+FHEMSTARTTIME}    = "Fhem start time";
  $rMap->{+FHEMSTARTTIME_TEXT} = "Fhem start time";

  # Werte fuer GesamtCPU
  $rMap->{"stat_cpu"}          = "CPU statistics";
  $rMap->{"stat_cpu_diff"}     = "CPU statistics (diff)";
  $rMap->{"stat_cpu_percent"}  = "CPU statistics (diff, percent)";
  $rMap->{"stat_cpu_text"}     = "CPU statistics (text)";
  $rMap->{"cpu_idle_stat"}     = "CPU min/max/avg (idle)";
  
  $rMap->{"stat_cpu_user_percent"} = "CPU statistics user %";
  $rMap->{"stat_cpu_nice_percent"} = "CPU statistics nice %";
  $rMap->{"stat_cpu_sys_percent"}  = "CPU statistics sys %";
  $rMap->{"stat_cpu_idle_percent"} = "CPU statistics idle %";
  $rMap->{"stat_cpu_io_percent"}   = "CPU statistics io %";
  $rMap->{"stat_cpu_irq_percent"}  = "CPU statistics irq %";
  $rMap->{"stat_cpu_sirq_percent"} = "CPU statistics sirq %";
  
  # CPU 0-7 (sollte reichen)
  for my $i (0..7) { 
    $rMap->{"stat_cpu".$i}            = "CPU".$i." statistics";
    $rMap->{"stat_cpu".$i."_diff"}    = "CPU".$i." statistics (diff)";
    $rMap->{"stat_cpu".$i."_percent"} = "CPU".$i." statistics (diff, percent)";
    $rMap->{"stat_cpu".$i."_text"} = "CPU".$i." statistics (text)";
    $rMap->{"cpu".$i."_idle_stat"}     = "CPU".$i." min/max/avg (idle)";
  }
  
  # Filesystems <readingName>[:<mountPoint>[:<Comment>]]
  my $filesystems = AttrVal($name, "filesystems", undef);
  if(defined $filesystems) {
    my @filesystem_list = split(/,\s*/, trim($filesystems));
    foreach (@filesystem_list) {
      my($fName, $fDef, $nComment) = split(/:/, $_);
      my $fPt; 
      if(defined $nComment) {
        $fPt = $nComment;
      } else {
        if(defined $fDef) {
          # Benannte
          $fPt = "Filesystem ".$fDef;
        } else {
          # Unbenannte
          $fPt = "Mount point ".$fName;
        }
      }
      
      $rMap->{$fName}         =  $fPt;
      $rMap->{$fName."_used"} =  $fPt." (used)";
      $rMap->{$fName."_used_percent"} =  $fPt." (used %)";
      $rMap->{$fName."_free"} =  $fPt." (free)";
      
    }
  } else {
    $rMap->{"root"}     = "Filesystem /";
  }

  # Networkadapters: <readingName>[:<interfaceName>[:<Comment>]]
  my $networkadapters = AttrVal($name, "network-interfaces", undef);
  if(defined $networkadapters) {
    my @networkadapters_list = split(/,\s*/, trim($networkadapters));
    foreach (@networkadapters_list) {
      my($nName, $nDef, $nComment) = split(/:/, $_);
      my $nPt; 
      if(defined $nComment) {
        $nPt = $nComment;
      } else {
        if(defined $nDef) {
          # Benannte
          $nPt = "Network ".$nDef;
        } else {
          # Unbenannte
          $nPt = "Network adapter ".$nName;
        }
      }
      
      $rMap->{$nName}           =  $nPt;
      $rMap->{$nName."_diff"}   =  $nPt." (diff)";
      $rMap->{$nName."_speed"}   =  $nPt." (speed)";
      $rMap->{$nName."_rx"}     =  $nPt." (RX)";
      $rMap->{$nName."_tx"}     =  $nPt." (TX)";
      $rMap->{$nName."_ip"}     =  $nPt." (IP)";
      $rMap->{$nName."_ip6"}    =  $nPt." (IP6)";
      
    }
  } else {
    # Default Networkadapters
    # Wenn nichts definiert, werden Default-Werte verwendet
    if(SYSMON_isFB($hash)) {
      my $nName = "ath0";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = "ath1";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = "cpmac0";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = "dsl";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = ETH0;
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = "guest";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = "hotspot";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = "lan";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = "vdsl";
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
    } else {
      my $nName = ETH0;
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
      
      $nName = WLAN0;
      $rMap->{$nName}         = "Network adapter ".$nName;
      $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_speed"} = "Network adapter ".$nName." (speed)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
      $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
      $rMap->{$nName."_ip"} = "Network adapter ".$nName." (IP)";
      $rMap->{$nName."_ip6"} = "Network adapter ".$nName." (IP6)";
    }
  }
  
  if(SYSMON_isFB($hash)) {
    # FB WLAN state
    $rMap->{+FB_WLAN_STATE}       = "WLAN State";
    $rMap->{+FB_WLAN_GUEST_STATE} = "WLAN Guest State";
    $rMap->{+FB_INET_IP}          = "Internet IP";
    $rMap->{+FB_INET_STATE}       = "Internet connection state";
    $rMap->{+FB_N_TIME_CTRL}      = "night time control";
    $rMap->{+FB_NUM_NEW_MESSAGES} = "new messages";
    $rMap->{+FB_FW_VERSION}       = "firmware info";
    $rMap->{+FB_DECT_TEMP}        = "DECT temperatur";
    
    $rMap->{+FB_DSL_RATE}       = "DSL rate",
    $rMap->{+FB_DSL_SYNCTIME}   = "DSL synctime";
    $rMap->{+FB_DSL_FEC_15}     = "DSL recoverable errors per 15 minutes"; # forward error correction
    $rMap->{+FB_DSL_CRC_15}     = "DSL unrecoverable errors per 15 minutes"; # cyclic redundancy check
    
  }
  
  # User defined
  my $userdefined = AttrVal($name, "user-defined", undef);
  if(defined $userdefined) {
    my @userdefined_list = split(/,\s*/, trim($userdefined));
    foreach (@userdefined_list) {
       # <readingName>:<Interval_Minutes>:<Comment>:<Cmd>
       my($uName, $uInterval, $uComment, $uCmd) = split(/:/, $_);
       if(defined $uComment) {
        # Nur gueltige
        $rMap->{$uName} = $uComment;
      }
    }
  }

  # User defined functions
  my $userfn = AttrVal($name, "user-fn", undef);
  if(defined $userfn) {
    my @userfn_list = split(/,\s*/, trim($userfn));
    foreach (@userfn_list) {
       # <fnName>:<Interval_Minutes>:<reading1>:<reading2>...
       my($fnName, $uInterval, @readings) = split(/:/, $_);
       foreach my $rName (@readings) {
        $rMap->{$rName} = "user defined: $fnName";
      }
    }
  }

# TEST: TODO
$rMap->{"io_sda_raw"}         = "TEST";
$rMap->{"io_sda_diff"}         = "TEST";
$rMap->{"io_sda"}         = "TEST";

  $hash->{helper}{cur_readings_map} = $rMap;
  return $rMap;
}

sub
SYSMON_getObsoleteReadingsMap($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $rMap; 
  
  #return $rMap; # TODO TEST
  
  if(!defined($hash->{helper}{cur_readings_map})) {
    SYSMON_updateCurrentReadingsMap($hash);
  }

  # alle READINGS durchgehen
  my @cKeys=keys (%{$defs{$name}{READINGS}});
  foreach my $aName (@cKeys) {
    if(defined ($aName)) {
      # alles hinzufuegen, was nicht in der Aktuellen Liste ist
      if(!defined($hash->{helper}{cur_readings_map}->{$aName})) {
        #Log 3, "SYSMON>>>>>>>>>>>>>>>>> SYSMON_getObsoleteReadingsMap >>> $aName";
        $rMap->{$aName} = 1;
      }
    }
  }
  
  return $rMap;
}

sub
SYSMON_Undefine($$)
{
  my ($hash, $arg) = @_;

  SYSMON_Log($hash, 5, "$arg");

  RemoveInternalTimer($hash);
  
  BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} )
      if exists $hash->{helper}{READOUT_RUNNING_PID}; 
  
  return undef;
}

sub
SYSMON_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];

  if(@a < 2)
  {
    SYSMON_Log($hash, 3, "@a: get needs at least one parameter");
    return "$name: get needs at least one parameter";
  }

  my $cmd= $a[1];

  SYSMON_Log($hash, 5, "@a");

  if($cmd eq "update")
  {
    #$hash->{LOCAL} = 1;
    SYSMON_Update($hash, 1);
    #delete $hash->{LOCAL};
    return undef;
  }

  if($cmd eq "list") {
    my $map = SYSMON_obtainParameters($hash, 1);
    my $ret = "";
    foreach my $name (keys %{$map}) {
      my $value = $map->{$name};
      $ret = "$ret\n".sprintf("%-20s %s", $name, $value);
    }
    
    my $msg = $hash->{helper}{error_msg};
    if($msg) {
      # Problem mit der Verbindung
      return $msg;
    }
  
    return $ret;
  }

  if($cmd eq "version")
  {
    return $VERSION;
  }

  if($cmd eq "interval_base")
  {
    return $hash->{INTERVAL_BASE};
  }

  if($cmd eq "interval_multipliers")
  {
    return $hash->{INTERVAL_MULTIPLIERS};
  }
  
  if($cmd eq "list_lan_devices")
  {
    my $ret='';
    my $map = SYSMON_getFBLanDeviceList($hash);
    if(defined($map)) {
      foreach my $dname (sort keys %{$map}) {
        my $dev_ip  =  $map->{$dname}{ip};
        $dev_ip='' unless defined $dev_ip;
        my $dev_mac =  $map->{$dname}{mac};
        my $dev_active = $map->{$dname}{active};
        my $dev_active_txt = $dev_active?'true':'false';
        #$ret.="\n"."$dname : active: $dev_active_txt, IP: $dev_ip, MAC: $dev_mac";
        $ret = "$ret\n".sprintf("%-25s : active: %-5s  IP: %-16s  MAC: %-17s", $dname, $dev_active_txt, $dev_ip, $dev_mac);
      }
    }
    return $ret;
  }

  my $sfb='';
  if(SYSMON_isFB($hash)) {
    $sfb=' list_lan_devices:noArg';
  }
  return "Unknown argument $cmd, choose one of list:noArg update:noArg interval_base:noArg interval_multipliers:noArg version:noArg".$sfb;
}

sub
SYSMON_Set($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];

  if(@a < 2)
  {
    SYSMON_Log($hash, 3, "@a: set needs at least one parameter");
    return "$name: set needs at least one parameter";
  }

  my $cmd= $a[1];

  SYSMON_Log($hash, 5, "@a");

  if($cmd eq "interval_multipliers")
  {
    if(@a < 3) {
      SYSMON_Log($hash, 3, "$name: not enought parameters");
      return "$name: not enought parameters";
    }

    my @na = @a[2..scalar(@a)-1];
    SYSMON_setInterval($hash, @na);
    return $cmd ." set to ".($hash->{INTERVAL_MULTIPLIERS});
  }

  if($cmd eq "clean") {    
    # Nicht mehr benoetigte Readings loeschen
    my $omap = SYSMON_getObsoleteReadingsMap($hash);
    foreach my $aName (keys %{$omap}) {
      delete $defs{$name}{READINGS}{$aName};
    }
    return;
  }
  
  if($cmd eq "clear")
  {
    my $subcmd = my $cmd= $a[2];
    if(defined $subcmd) {
      delete $defs{$name}{READINGS}{$subcmd};
      return;
    }
    
    return "missing parameter. use clear <reading name>";
  }
  
  if ( lc $cmd eq 'password') {
    my $subcmd = $a[2];
    if(defined $subcmd) {
       my $ret = SYSMON_storePassword ($hash, $subcmd);
       if(!defined($hash->{helper}{error_msg})) {
         SYSMON_Update($hash, 1);
       }
       return $ret;
    }
  }
  
  # TEST
  if($cmd eq "reset")
  {
    delete $defs{$name}->{helper};
    return 'ok';
  }

  return "Unknown argument $cmd, choose one of password interval_multipliers clean:noArg clear";
}

sub
SYSMON_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $hash = $main::defs{$name};
  SYSMON_Log($hash, 5, "SYSMON Attr: $cmd $name ".$attrName?$attrName:''." $attrVal");

  $attrVal= "" unless defined($attrVal);
  my $orig = AttrVal($name, $attrName, "");
  
  if( $orig ne $attrVal ) {
    if( $cmd eq "set" ) {# set, del  
      
      if($attrName eq "exclude") {
  		  my @elist = split(/,\s*/, trim($attrVal));
  		  my %ehash = map { $_ => 1 } @elist;
  		  $hash->{helper}->{excludes}=\%ehash;
  	  }

      if($attrName eq "disable")
      {
        RemoveInternalTimer($hash);
        if($attrVal ne "1")
        {
          InternalTimer(gettimeofday()+$hash->{INTERVAL_BASE}, "SYSMON_Update", $hash, 0);
          $hash->{STATE} = "Active";
        } else {
          $hash->{STATE} = "Inactive"; 
        }
        #$hash->{LOCAL} = 1;
        #SYSMON_Update($hash);
        #delete $hash->{LOCAL};
      }

      $attr{$name}{$attrName} = $attrVal;
      
      SYSMON_updateCurrentReadingsMap($hash);
      
      #return $attrName ." set to ". $attrVal;
      return undef;
    } elsif( $cmd eq "del" ) {
    	if($attrName eq "exclude") {
  		  $hash->{helper}->{excludes}=undef;
  	  }
    }
  }
  return;
}

#my $u_first_mark = undef;

sub
SYSMON_Update($;$)
{
  my ($hash, $refresh_all) = @_;
  
  $refresh_all="0" unless defined $refresh_all;

  #SYSMON_Log($hash, 5, "refresh_all: ".$refresh_all);

  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL_BASE}, "SYSMON_Update", $hash, 1);
  }

  if( AttrVal($name, "disable", "") eq "1" )
  {
    #SYSMON_Log($hash, 5, "disabled");
    #$hash->{STATE} = "Inactive";
  } else {
    # Beim ersten mal alles aktualisieren!
    if(!$hash->{helper}{u_first_mark}) {
      $refresh_all = 1;
    }

    SYSMON_obtainLocalCPUFreq($hash);
    
    my $map;
    if(!AttrVal($name, "nonblocking", 1)) {
      # direkt call
      
      # Parameter holen
      $map = SYSMON_obtainParameters($hash, $refresh_all);
			
      # Mark setzen 
      if(!$hash->{helper}{u_first_mark}) {
        $hash->{helper}{u_first_mark} = 1;
      }
    
      SYSMON_updateReadings($hash,$map);
      #$hash->{STATE} = "Active";
    } else {
      # blocking call
      if ( exists( $hash->{helper}{READOUT_RUNNING_PID} ) ) {
        SYSMON_Log($hash, 5, "blockingCall: Old readout process still running. Killing old process ".$hash->{helper}{READOUT_RUNNING_PID});
        BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} ); 
        delete($hash->{helper}{READOUT_RUNNING_PID});
      }
      
      $hash->{helper}{READOUT_RUNNING_PID} = BlockingCall("SYSMON_blockingCall", $name."|".$refresh_all, "SYSMON_blockingFinish", 55, "SYSMON_blockingAbort", $hash);
    }
    
    
       
  }

}

sub SYSMON_obtainLocalCPUFreq($) {
	my ($hash) = @_;
	
	my $map;
	#--------------------------------------------------------------------------
  my $base=$DEFAULT_INTERVAL_BASE; 
  my $im = "1 1 1 10";
  # Wenn wesentliche Parameter nicht definiert sind, soll aktualisierung immer vorgenommen werden
  if((defined $hash->{INTERVAL_BASE})) {
    $base = $hash->{INTERVAL_BASE};
  }
  if((defined $hash->{INTERVAL_MULTIPLIERS})) {
    $im = $hash->{INTERVAL_MULTIPLIERS};
  }

  my $ref =  int(time()/$base);
  my ($m1, $m2, $m3, $m4) = split(/\s+/, $im);
  
  if($m1 gt 0) { # Nur wenn > 0
    # M1: cpu_freq, cpu_temp, cpu_temp_avg, loadavg, procstat, iostat
    if(($ref % $m1) eq 0) {
	    # Sonderlocke: CPUFreq
	    my $mode = $hash->{MODE};
	    if ($mode eq 'local') {
		    foreach my $li (0..7) {
		      if(SYSMON_isCPUXFreq($hash, $li)) {
		        $map = SYSMON_getCPUFreqLocal($hash, $map, $li);
		      }
		    }
	    }
	  }
	}
  #--------------------------------------------------------------------------
  SYSMON_updateReadings($hash,$map);
}

sub SYSMON_blockingCall($) {
  my ($tparam) = @_;
  my ($name, $refresh_all) = split(/\|/,$tparam);
  my $hash = $main::defs{$name};
  SYSMON_Log($hash, 5, "$name, ".($refresh_all?$refresh_all:''));

  my $map = SYSMON_obtainParameters($hash, $refresh_all);

  # Device-Name mitnehmen
  my $ret = "name|".$name;
  
  my $msg = $hash->{helper}{error_msg};
  if($msg) {
    # Problem mit der Verbindung
    return $ret."|error|".$msg;
  }

  # to String
  foreach my $aName (keys %{$map}) {
    my $value = $map->{$aName};
    # Nur wenn ein gueltiges Value vorliegt
    if(defined $value) {
      # Zeichen maskieren
      $value=~s/#/§²§/g;
      $value=~s/\|/§³§/g;
      $ret.="|".$aName."|".$value;
    }
  }
  
  return $ret;
}

sub SYSMON_test() {
  
  #foreach my $d (sort keys %defs) {
  #  my $h = $defs{$d};
  #  if(defined ($h->{TYPE})) {} else {return $d."-".Dumper($h);}
  #}
  
  my $map;
  
  my $name="TESTNAME";
  
  $map->{test1}="val1";
  $map->{test2}="val2";
  $map->{test3}="val3";
  
  #return Dumper($map);
  
  my $ret = "name|".$name;
  # to ret String
  foreach my $aName (keys %{$map}) {
    my $value = $map->{$aName};
    # Nur wenn ein gueltiges Value vorliegt
    if(defined $value) {
      $value=~s/#/§²§/g;
      $ret.="|".$aName."|".$value;
    }
  }
  
  my @ta = split(/\|/,$ret);
  #return Dumper(@ta);
  my %map2 = @ta;
  
  return Dumper(\%map2);
  
  return $ret;
}

sub SYSMON_blockingAbort($) {
  my ($hash) = @_;
  delete($hash->{helper}{READOUT_RUNNING_PID});
  SYSMON_Log($hash, 5, "");
  $hash->{STATE} = "Error: Blocking call aborted (timeout)";
}

sub SYSMON_blockingFinish($) {
  my ($map_str) = @_;
  
  my $map;
  # to map
  my @ta = split(/\|/,$map_str);
  my %tm = @ta;
  $map = \%tm;
  
  my $name=$map->{name};
  delete $map->{name};
  
  my $hash = $main::defs{$name};
  delete($hash->{helper}{READOUT_RUNNING_PID});
  
  SYSMON_Log($hash, 5, $map_str);
  # Mark setzen 
  if(!$hash->{helper}{u_first_mark}) {
    $hash->{helper}{u_first_mark} = 1;
  }
  
  my $msg = $map->{error};
  if($msg) {
    # Im Fehlerfall State ebtsprechend setzen und nichts aktualisieren.
    $hash->{STATE} = "Error: ".$msg;
    return;
  }
  
  SYSMON_updateReadings($hash,$map);
  #$hash->{STATE} = "Active";
}

sub SYSMON_updateReadings($$) {
  my ($hash,$map) = @_;
  SYSMON_Log($hash, 5, "");
  my $name = $hash->{NAME};
  
  readingsBeginUpdate($hash);
  
  
  # Wenn UserFn benutzt wird, werden die erstellten Eintraege erfasst und die entsprechenden Readings nicht erhalten
  my $h_keys;
  my $uFnReadings = $map->{"xuser_fnr"};
  my @a_keys;
  if(defined($uFnReadings)) {
    delete $map->{"xuser_fnr"};
    @a_keys = split(/,\s*/, trim($uFnReadings));
    #$h_keys = map { $_ => "1" } @a_keys;
  }
  
  foreach my $aName (keys %{$map}) {
    my $value = $map->{$aName};
    # Nur aktualisieren, wenn ein gueltiges Value vorliegt
    if(defined $value) {
      # Maskierte Zeichen zuruechersetzen
      $value=~s/§²§/#/g;
      $value=~s/§³§/\|/g;
      readingsBulkUpdate($hash,$aName,$value);
    }
  }
    
  # Nicht mehr benoetigte Readings loeschen
  my $omap = SYSMON_getObsoleteReadingsMap($hash);
  
  # UserFn Keys entfernen
  foreach my $aName (@a_keys) {
    delete($omap->{$aName});
  }
  foreach my $aName (keys %{$omap}) {
    #  SYSMON_Log($hash, 5, ">>>>>>>>>>>>>>>>>>>> ".$aName."->".Dumper($defs{$name}{READINGS}{$aName}));
      delete $defs{$name}{READINGS}{$aName};
  }

  readingsEndUpdate($hash,defined($hash->{LOCAL}) ? 0 : 1);    
}

sub SYSMON_obtainParameters($$) {
  my ($hash, $refresh_all) = @_;
    
  my $name = $hash->{NAME};
  # ---
  #TODO: SSH
  my $msg = undef;
  my $openedTelnet = 0;
  my $telnet = $hash->{".telnet"};
  #$telnet = undef;
  my $mode = $hash->{MODE};
  # Wenn remote: open connection
  if ($mode eq 'telnet') {
    unless (defined $telnet) {
      SYSMON_Log($hash, 5, "$name: Open shared telnet connection");
      $msg = SYSMON_Open_Connection($hash);
      $hash->{helper}{error_msg}=$msg;
      if (!$msg) {
        $openedTelnet = 1;
        $hash->{helper}{error_msg}=undef;
      }
    }
  }
  # ---
  
  my $map;
  if (!$msg) {
    $map = SYSMON_obtainParameters_intern($hash, $refresh_all);
  }
  
  # ---
  # Wenn remote: close connection
  if ($mode eq 'telnet') {
    if($openedTelnet) {
      SYSMON_Log($hash, 5, "$name: Close shared telnet connection");
      SYSMON_Close_Connection( $hash );
    }
  }
  # ---
  
  return $map;
}


# Schattenmap mit den zuletzt gesammelten Werten (merged)
#my %shadow_map;
sub
SYSMON_obtainParameters_intern($$)
{
  my ($hash, $refresh_all) = @_;
  my $name = $hash->{NAME};

  my $map;

  my $base=$DEFAULT_INTERVAL_BASE; 
  my $im = "1 1 1 10";
  # Wenn wesentliche Parameter nicht definiert sind, soll aktualisierung immer vorgenommen werden
  if((defined $hash->{INTERVAL_BASE})) {
    $base = $hash->{INTERVAL_BASE};
  }
  if((defined $hash->{INTERVAL_MULTIPLIERS})) {
    $im = $hash->{INTERVAL_MULTIPLIERS};
  }

  my $ref =  int(time()/$base);
  my ($m1, $m2, $m3, $m4) = split(/\s+/, $im);
   
  my $mode = $hash->{MODE};#AttrVal( $name, 'mode', 'local');
  # Einmaliges
  if(!$hash->{helper}{u_first_mark}) {
    # nur lokal abfragen (macht remote keinen Sinn)
    if ($mode eq 'local') {
      # Perl version
      $map->{+PERL_VERSION} = "$^V";
    }
    
    if(SYSMON_isProcFS($hash)) {
      $map = SYSMON_getCPUInfo($hash, $map);
    }
  
    if(SYSMON_isFB($hash)) {
      $map = SYSMON_FBVersionInfo($hash, $map);
    }
  }

  # immer aktualisieren: uptime, uptime_text, fhemuptime, fhemuptime_text, idletime, idletime_text
  if(SYSMON_isProcFS($hash)) {
    $map = SYSMON_getUptime($hash, $map);
  } else {
    $map = SYSMON_getUptime2($hash, $map);
  }
  
  # nur lokal abfragen
  if ($mode eq 'local') {
    $map = SYSMON_getFHEMUptime($hash, $map);
  }

  if($m1 gt 0) { # Nur wenn > 0
    # M1: cpu_freq, cpu_temp, cpu_temp_avg, loadavg, procstat, iostat
    if($refresh_all || ($ref % $m1) eq 0) {
    	
    	$map = SYSMON_getCPUCoreNum($hash, $map);
    	
      #Log 3, "SYSMON -----------> DEBUG: read CPU-Temp"; 
      if(SYSMON_isCPUTempRPi($hash)) { # Rasp
         $map = SYSMON_getCPUTemp_RPi($hash, $map);
      } 
      if (SYSMON_isCPUTempBBB($hash)) {
        $map = SYSMON_getCPUTemp_BBB($hash, $map);
      }
      foreach my $li (0..7) {
        if(SYSMON_isCPUTemp_X($hash, $li)) {
          $map = SYSMON_getCPUTemp_X($hash, $map, $li);
        }
      }  
      if (SYSMON_isCPUTempFB($hash)) {
        $map = SYSMON_getCPUTemp_FB($hash, $map);
      }
      #if(SYSMON_isCPUFreqRPiBBB($hash)) {
      #  $map = SYSMON_getCPUFreq($hash, $map, 0);
      #}
      foreach my $li (0..7) {
        if(SYSMON_isCPUXFreq($hash, $li)) {
          $map = SYSMON_getCPUFreq($hash, $map, $li);
        }
      }
      if(SYSMON_isProcFS($hash)) {
        $map = SYSMON_getLoadAvg($hash, $map);
        $map = SYSMON_getCPUProcStat($hash, $map);
      } else {
        #TODO: Ohne ProcFS
      }
      #$map = SYSMON_getDiskStat($hash, $map);
      
      # Power info (cubietruck)
      if(SYSMON_isSysPowerAc($hash)) {
        $map = SYSMON_PowerAcInfo($hash, $map);
      }
      if(SYSMON_isSysPowerUsb($hash)) {
        $map = SYSMON_PowerUsbInfo($hash, $map);
      }
      if(SYSMON_isSysPowerBat($hash)) {
        $map = SYSMON_PowerBatInfo($hash, $map);
      }
    }
  }

  if($m2 gt 0) { # Nur wenn > 0
    # M2: ram, swap
    if($refresh_all || ($ref % $m2) eq 0) {
      if(SYSMON_isOSX()){
        $map = SYSMON_getRamAndSwapOSX($hash, $map);
      } else {
        $map = SYSMON_getRamAndSwap($hash, $map);
      }
    }
  }

  if($m3 gt 0) { # Nur wenn > 0
    # M3: eth0, eth0_diff, wlan0, wlan0_diff, wlan_on (FritzBox)
    my $update_ns = ($refresh_all || ($ref % $m3) eq 0);
    #if($refresh_all || ($ref % $m3) eq 0) {
    my $networks = AttrVal($name, "network-interfaces", undef);
    if($update_ns) {
      if(defined $networks) {
        my @networks_list = split(/,\s*/, trim($networks));
        foreach (@networks_list) {
          $map = SYSMON_getNetworkInfo($hash, $map, $_);
        }
      } else {
        # Wenn nichts definiert, werden Default-Werte verwendet
        #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> NETWORK";
        if(SYSMON_isFB($hash)) {
          $map = SYSMON_getNetworkInfo($hash, $map, "ath0");
          $map = SYSMON_getNetworkInfo($hash, $map, "ath1");
          $map = SYSMON_getNetworkInfo($hash, $map, "cpmac0");
          $map = SYSMON_getNetworkInfo($hash, $map, "dsl");
          $map = SYSMON_getNetworkInfo($hash, $map, "eth0");
          $map = SYSMON_getNetworkInfo($hash, $map, "guest");
          $map = SYSMON_getNetworkInfo($hash, $map, "hotspot");
          $map = SYSMON_getNetworkInfo($hash, $map, "lan");
          $map = SYSMON_getNetworkInfo($hash, $map, "vdsl");
        } else {
          #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".ETH0;
          $map = SYSMON_getNetworkInfo($hash, $map, ETH0);
          #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".$map->{+ETH0};
          #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".WLAN0;
          $map = SYSMON_getNetworkInfo($hash, $map, WLAN0);
          #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".$map->{+WLAN0};
        }
      }
      if(SYSMON_isFB($hash)) {
        $map = SYSMON_getFBWLANState($hash, $map);
        $map = SYSMON_getFBWLANGuestState($hash, $map);
        $map = SYSMON_getFBInetIP($hash, $map);
        $map = SYSMON_getFBInetConnectionState($hash, $map);
        $map = SYSMON_getFBNightTimeControl($hash, $map);
        $map = SYSMON_getFBNumNewMessages($hash, $map);
        $map = SYSMON_getFBDECTTemp($hash, $map);
        
        #DSL-Downstream und DSL-Upstream abfragen
        $map = SYSMON_getFBStreamRate($hash, $map);
        #Sync-Zeit mit Vermittlungsstelle abfragen
        $map = SYSMON_getFBSyncTime($hash, $map);
        #Uebertragungsfehler abfragen (nicht behebbar und behebbar)
        $map = SYSMON_getFBCRCFEC($hash, $map);
      }
    }
  }
  
  if($m4 gt 0) { # Nur wenn > 0
    # M4: Filesystem-Informationen
    my $update_fs = ($refresh_all || ($ref % $m4) eq 0);
    my $filesystems = AttrVal($name, "filesystems", undef);
    if($update_fs) {
      if(defined $filesystems)
      {
        my @filesystem_list = split(/,\s*/, trim($filesystems));
        foreach (@filesystem_list)
        {
          $map = SYSMON_getFileSystemInfo($hash, $map, $_);
        }
      } else {
        $map = SYSMON_getFileSystemInfo($hash, $map, "root:/");
      }
    } else {
      # Workaround: Damit die Readings zw. den Update-Punkten nicht geloescht werden, werden die Schluessel leer angelegt
      # Wenn noch keine Update notwendig, dan einfach alte Schluessel (mit undef als Wert) angeben,
      # damit werden die Readings in der Update-Methode nicht geloescht.
      # Die ggf. notwendige Loeschung findet nur bei tatsaechlichen Update statt.
      my @cKeys=keys (%{$defs{$name}{READINGS}});
      foreach my $aName (@cKeys) {
        #if(defined ($aName) && (index($aName, FS_PREFIX) == 0 || index($aName, FS_PREFIX_N) == 0)) {
        if(defined ($aName) && (index($aName, FS_PREFIX) == 0 )) {
          $map->{$aName} = undef;
        }
      }
    }
  }
  
  #Log 3, "SYSMON >>> USER_DEFINED >>>>>>>>>>>>>>> START";
  my $userdefined = AttrVal($name, "user-defined", undef);
  if(defined $userdefined) {
    my @userdefined_list = split(/,\s*/, trim($userdefined));
    foreach (@userdefined_list) {
       # <readingName>:<Interval_Minutes>:<Comment>:<Cmd>
       my $ud = $_;
       my($uName, $uInterval, $uComment, $uCmd) = split(/:/, $ud);
       SYSMON_Log($hash, 5, "User-Defined Reading: [$uName][$uInterval][$uComment][$uCmd]");
       if(defined $uCmd) { # Also, wenn alle Parameter vorhanden
         my $iInt = int($uInterval);
         if($iInt>0) {
           my $update_ud = ($refresh_all || ($ref % $iInt) eq 0);
           if($update_ud) {
             $map = SYSMON_getUserDefined($hash, $map, $uName, $uCmd);
           } else {
             SYSMON_Log($hash, 5, "User-Defined Reading: [$uName][$uInterval][$uComment][$uCmd] out of refresh interval");
           }
         }
      }
    }
  }
  
  #Log 3, "SYSMON >>> USER_DEFINED FUNCTIONS >>>>>>>>>>>>>>> START";
  my $userfn = AttrVal($name, "user-fn", undef);
  if(defined $userfn) {
    my @userfn_list = split(/,\s+/, trim($userfn));
    foreach my $ud (@userfn_list) {
       # <fnName>:<Interval_Minutes>:<reading1>:<reading2>..., [<fn-name>:...]
       my($fnName, $uInterval, @readings) = split(/:/, $ud);
       SYSMON_Log($hash, 5, "User-Defined Fn: [$fnName][$uInterval]");
       if(defined $uInterval) {
         my $iInt = int($uInterval);
         if($iInt>0) {
           my $update_ud = ($refresh_all || ($ref % $iInt) eq 0);
           if($update_ud) {
             $map = SYSMON_getUserDefinedFn($hash, $map, $fnName, @readings);
           } else {
             SYSMON_Log($hash, 5, "User-Defined Fn: [$fnName][$uInterval] out of refresh interval");
           }
         }
      }
    }
  }
  
  # User Functions2
  my $uMap;
  $userfn = AttrVal($name, "user-fn2", undef);
  #TEST$userfn=undef;
  if(defined $userfn) {
    my @userfn_list = split(/,\s*/, trim($userfn));
    foreach (@userfn_list) {
      my $ufn = $_;
      SYSMON_Log($hash, 5, "User-Function Reading: [$ufn]");
      if(defined $ufn) {
        no strict "refs";
        $uMap = &{$ufn}($hash, $uMap);
        use strict "refs";
      }
    }
  }
  # Werte umverpacken, KeyNamen sichern
  my $uNames='';
  if(defined($uMap)) {
    foreach my $uName (keys %{$uMap}) {
      $uNames.=','.$uName;
      $map->{$uName}=$uMap->{$uName};
    }
    # Erste Komma entfernen
    $uNames=substr($uNames,1);
    $map->{"xuser_fnr"}=$uNames;
  }
  
  #TEST
  #my $rt = "#";
  #$rt=~s/#/[]/g;
  #$map->{SYS_TEST}=$rt;
  
  if(defined($map)) {
  # Aktuelle Werte in ShattenHash mergen
  my %hashT = %{$map};
  #@shadow_map{ keys %hashT } = values %hashT;
  my %shadow_map;
  @shadow_map{ keys %hashT } = values %hashT;
  $hash->{helper}{shadow_map} = \%shadow_map;
  }

  return $map;
}

# For test purpose only
sub SYSMON_TestUserFn($$) {
  my ($hash, $map) = @_;
  
  $map->{"my_test_reading"}="my test";
  #$map->{"my"}="my";
  
  return $map;  
}

#------------------------------------------------------------------------------
# Liefert gesammelte Werte ( = Readings)
# Parameter: array der gewuenschten keys (Readings names)
# Beispiele:
#   {(SYSMON_getValues("sysmon"))->{'cpu_temp'}}
#   {(SYSMON_getValues("sysmon",("cpu_freq","cpu_temp")))->{"cpu_temp"}}
#   {join(" ", values (SYSMON_getValues("sysmon")))}
#   {join(" ", values (SYSMON_getValues("sysmon",("cpu_freq","cpu_temp"))))}
#------------------------------------------------------------------------------
sub
SYSMON_getValues($;@)
{
  my ($name,@filter_keys) = @_;
  
  my $hash = $main::defs{$name};
  my %shadow_map = %{$hash->{helper}{shadow_map}};
  if(scalar(@filter_keys)>0) {
    my %clean_hash;
    #@clean_hash{ @filter_keys } = @shadow_map{ @filter_keys };
    @clean_hash{ @filter_keys } = @shadow_map{ @filter_keys };
    return \%clean_hash;
  }
  # alles liefern
  return \%shadow_map;
}

sub SYSMON_getComputeStat($$$$) {
	my ($hash, $map, $val, $name) = @_;
	
	if (defined($val)) {
	my $t = ReadingsVal($hash->{NAME},$name,"$val $val $val");
	
	my($min, $max, $avg) = split(/ /,$t);
	$min = $val if $min>$val;
	$max = $val if $max<$val;
	$avg = (3*$avg + $val)/4;
	
	$t = sprintf( "%.2f %.2f %.2f", $min, $max, $avg );
	
	$map->{$name} = $t;
	
	#SYSMON_Log($hash, 3, ">>>>>>>>>>>>>>>>> ".$name." => $t");
	}
	return $map;
}

#------------------------------------------------------------------------------
# Liest Benutzerdefinierte Eintraege
#------------------------------------------------------------------------------
sub
SYSMON_getUserDefined($$$$)
{
  my ($hash, $map, $uName, $uCmd) = @_;
  SYSMON_Log($hash, 5, "Name=[$uName] Cmd=[$uCmd]");
  
  if($hash->{helper}->{excludes}{'user-defined'}) {return $map;}
  
  my @out_arr = SYSMON_execute($hash, $uCmd);
  
  my $out_str = "";
  foreach my $k (@out_arr) {
  	if(defined($k)) {
      chomp($k);
      $out_str.=$k." ";
    }
  }
  #my $out_str = join(" ",@out_arr);
  ##my $out_str = SYSMON_execute($hash, $uCmd);
  ##chomp $out_str;
  #$out_str=~s/\n/ /g;
  #$out_str=~s/\r/ /g;
  $map->{$uName} = $out_str;
  SYSMON_Log($hash, 5, "User-Defined Result: $uName='$out_str'");
  
  return $map;
}

sub SYSMON_getUserDefinedFn($$$@) {
  my($hash, $map, $fnName, @readings) = @_;
  
  #SYSMON_Log($hash, 3, ">>>>>>>>>>>>>>>>>>>>> exclude: ".Dumper($hash->{helper}->{excludes}));
  if($hash->{helper}->{excludes}{'user-defined'}) {return $map;}
  
  SYSMON_Log($hash, 5, "call User-Function: [$fnName]");
  if(defined $fnName) {
    no strict "refs";
    my @rarr;
    if($fnName=~/^{/) {
      my $HASH = $hash;
      my $NAME = $hash->{NAME};
      @rarr = eval($fnName);
    } else {
      @rarr = &{$fnName}($hash);
    }
    use strict "refs";
    SYSMON_Log($hash, 5, "result User-Function [$fnName]: ".Dumper(@rarr));
    
    my $cnt1 = scalar(@readings);
    my $cnt2 = scalar(@rarr);
    my $cnt = min($cnt1,$cnt2);
    if($cnt1!=$cnt2) { # zu wenig readings geliefert ($cnt1>$cnt2) oder zu viel
      SYSMON_Log($hash, 3, "User-Function [$fnName]: expected readings: [$cnt1], provided [$cnt2]");
    }
    #SYSMON_Log($hash, 5, ">>>> User-Function [$fnName]: $cnt1 / $cnt2: $rarr[0]");
    for (my $i=0;$i<$cnt;$i++) { 
      if(defined($rarr[$i])) {
        my $val = trim($rarr[$i]);
        #SYSMON_Log($hash, 5, ">>>> User-Function [$fnName]: put: '".$readings[$i]."' => '".$val."'");
        $map->{$readings[$i]} = $val;
        #$map->{$readings[$i]}="Dead OWTHERM devices: none";
        #SYSMON_Log($hash, 5, ">>>> User-Function [$fnName]: ok");
      }
    }
  }
  
  return $map;
}

#my $sys_cpu_core_num = undef;
sub
SYSMON_getCPUCoreNum_intern($) {
  my ($hash) = @_;
  
  return $hash->{helper}{sys_cpu_core_num} if $hash->{helper}{sys_cpu_core_num};
  
  # TODO: Umstellung auf 
  # cat /sys/devices/system/cpu/present
  # cat /sys/devices/system/cpu/online
  
  # nur wenn verfuegbar
  if(SYSMON_isSysCpuNum($hash)) {
    my $str = SYSMON_execute($hash, "cat /sys/devices/system/cpu/kernel_max");
    if(defined($str)) {
      if($str ne "") {
        if(int($str)!=0) {
          $hash->{helper}{sys_cpu_core_num} = int($str)+1;
          return $hash->{helper}{sys_cpu_core_num};
        }
      }
    }
  }
  
  # Default / unbekannt
  $hash->{helper}{sys_cpu_core_num} = 1;
  return $hash->{helper}{sys_cpu_core_num};
}

#------------------------------------------------------------------------------
# leifert Anzahl CPU Kerne
#------------------------------------------------------------------------------
sub SYSMON_getCPUCoreNum($$) {
	 my ($hash, $map) = @_;
	 
	 if($hash->{helper}->{excludes}{'cpucount'}) {return $map;}
	 
   my $cpuCoreCnt = SYSMON_getCPUCoreNum_intern($hash);
   $map->{+CPU_CORE_CNT}=$cpuCoreCnt;
   return $map;
}

#------------------------------------------------------------------------------
# leifert Zeit seit dem Systemstart
#------------------------------------------------------------------------------
sub
SYSMON_getUptime($$)
{
  my ($hash, $map) = @_;

  if($hash->{helper}->{excludes}{'uptime'}) {return $map;}

  #my $uptime_str = qx(cat /proc/uptime );
  my $uptime_str = SYSMON_execute($hash, "cat /proc/uptime");
  if(defined($uptime_str)) {
    my ($uptime, $idle) = split(/\s+/, trim($uptime_str));
    #postfux use idle from /proc/stat instead
    my $stat_str = SYSMON_execute($hash, "cat /proc/stat|grep 'cpu '");
    my($tName, $neuCPUuser, $neuCPUnice, $neuCPUsystem, $neuCPUidle, $neuCPUiowait, $neuCPUirq, $neuCPUsoftirq) = split(/\s+/, trim($stat_str));
    if(defined($neuCPUidle)){
      $idle=$neuCPUidle/100;
    }
    #postfux
    if(defined($uptime) && int($uptime)!=0) {
      # Anzahl Cores beruecksichtigen
      my $core_num = SYSMON_getCPUCoreNum_intern($hash);
      my $idle_percent = $idle/($uptime*$core_num)*100;
      
      $idle = $idle/$core_num;

      $map->{+UPTIME}=sprintf("%d",$uptime);
      #$map->{+UPTIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes, %02d seconds",SYSMON_decode_time_diff($uptime));
      $map->{+UPTIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes",SYSMON_decode_time_diff($uptime));
    
      my $startTime = time()-$uptime;
      $map->{+STARTTIME} = sprintf("%d",$startTime);
      $map->{+STARTTIME_TEXT} = strftime("%d.%m.%Y %H:%M:%S", localtime($startTime));
    
      $map->{+IDLETIME}=sprintf("%d %.2f %%",$idle, $idle_percent);
      $map->{+IDLETIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes",SYSMON_decode_time_diff($idle)).sprintf(" (%.2f %%)",$idle_percent);
      #$map->{+IDLETIME_PERCENT} = sprintf ("%.2f %",$idle_percent);
    }
  }  
  return $map;
}

#------------------------------------------------------------------------------
# leifert Zeit seit dem Systemstart. 
# Alternative Version fuer Systemen ohne procfs (z.B. MACOS)
#------------------------------------------------------------------------------
sub
SYSMON_getUptime2($$)
{
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'uptime'}) {return $map;}

#TODO
  my $uptime = SYSMON_execute($hash,"uptime");

  if(defined($uptime)){
    #SYSMON_Log($hash, 5, ">>>>>>>>>>>>>>>>>>>>>>".$uptime."<");
    
    #$uptime = $1 if( $uptime && $uptime =~ m/[[:alpha:]]{2}\s+(((\d+)\D+,?\s+)?(\d+):(\d+))/ );
    $uptime = $1 if( $uptime && $uptime =~ m/[[:alpha:]]{2}\s+(((\d+)\D+,?\s+)?(\d+):(\d+)).*load.*: (.*)/ );
    $uptime = "0 days, $uptime" if( $uptime && !$2);
    
    
    my $days = $3?$3:0;
    my $hours = $4;
    my $minutes = $5;
    
    if(defined($days) && defined($hours) && defined($minutes)) {
      $uptime = $days * 24;
      $uptime += $hours;
      $uptime *= 60;
      $uptime += $minutes;
      $uptime *= 60;
    } else {
    	$uptime = 0;
    }
    
    $map->{+UPTIME}=sprintf("%d",$uptime);
    $map->{+UPTIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes",SYSMON_decode_time_diff($uptime));
    
    my $startTime = time()-$uptime;
    $map->{+STARTTIME} = sprintf("%d",$startTime);
    $map->{+STARTTIME_TEXT} = strftime("%d.%m.%Y %H:%M:%S", localtime($startTime));
    
    my $loadavg=$6;
    if(defined($loadavg)) {
      my ($la1, $la5, $la15, $prc, $lastpid) = split(/\s+/, trim($loadavg));
      if(defined($la1) && defined($la5) && defined($la15)) {
        $la1 =~ s/,$//; 
        $la5 =~ s/,$//; 
        $la1 =~ s/,/./; 
        $la5 =~ s/,/./; 
        $la15 =~ s/,/./; 
        $map->{+LOADAVG}="$la1 $la5 $la15";
      }
    }
  }
  
  return $map;
}

#------------------------------------------------------------------------------
# leifert Zeit seit FHEM-Start
#------------------------------------------------------------------------------
sub
SYSMON_getFHEMUptime($$)
{
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fhemuptime'}) {return $map;}

  #if(defined ($hash->{DEF_TIME})) {
  if(defined($fhem_started)) {
    #my $fhemuptime = time()-$hash->{DEF_TIME};
    my $fhemuptime = time()-$fhem_started;
    $map->{+FHEMUPTIME} = sprintf("%d",$fhemuptime);
    $map->{+FHEMUPTIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes",SYSMON_decode_time_diff($fhemuptime));
    
    my $startTime = time()-$fhemuptime;
    $map->{+FHEMSTARTTIME} = sprintf("%d",$startTime);
    $map->{+FHEMSTARTTIME_TEXT} = strftime("%d.%m.%Y %H:%M:%S", localtime($startTime));
  }

  return $map;
}

#------------------------------------------------------------------------------
# leifert CPU-Auslastung
#------------------------------------------------------------------------------
sub
SYSMON_getLoadAvg($$)
{
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'loadavg'}) {return $map;}

  my $la_str = SYSMON_execute($hash, "cat /proc/loadavg");
  if(defined($la_str)) {
    my ($la1, $la5, $la15, $prc, $lastpid) = split(/\s+/, trim($la_str));
    if(defined($la1) && defined($la5) && defined($la15)) {
      $map->{+LOADAVG}="$la1 $la5 $la15";
      #$map->{"load"}="$la1";
      #$map->{"load5"}="$la5";
      #$map->{"load15"}="$la15";
    }
  }
  
  return $map;
}

#------------------------------------------------------------------------------
# liefert CPU Temperature (Raspberry Pi)
#------------------------------------------------------------------------------
sub
SYSMON_getCPUTemp_RPi($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'cputemp'}) {return $map;}
  
  my $val = SYSMON_execute($hash, "cat /sys/class/thermal/thermal_zone0/temp 2>&1");  
  $val = int($val);
  if($val>1000) { # Manche Systeme scheinen die Daten verschieden zu skalieren (z.B. utilite)...
    $val = $val/1000;
  }
  my $val_txt = sprintf("%.2f", $val);
  $map->{+CPU_TEMP}="$val_txt";
  my $t_avg = sprintf( "%.1f", (3 * ReadingsVal($hash->{NAME},CPU_TEMP_AVG,$val_txt) + $val_txt ) / 4 );
  $map->{+CPU_TEMP_AVG}="$t_avg";
  
  $map = SYSMON_getComputeStat($hash, $map, $val_txt, CPU_TEMP."_stat");
  
  return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Temperature (BeagleBone Black)
#------------------------------------------------------------------------------
sub
SYSMON_getCPUTemp_BBB($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'cputemp'}) {return $map;}
  
  my $val = SYSMON_execute($hash, "cat /sys/class/hwmon/hwmon0/device/temp1_input 2>&1");
  if(!looks_like_number($val)) {return $map;}
  
  $val = int($val);
  if ($val > 200) {
    $val = $val / 1000;
  }
  my $val_txt = sprintf("%.2f", $val);
  $map->{+CPU_TEMP}="$val_txt";
  $map->{"cpu0_temp"}="$val_txt";
  my $t_avg = sprintf( "%.1f", (3 * ReadingsVal($hash->{NAME},CPU_TEMP_AVG,$val_txt) + $val_txt ) / 4 );
  $map->{+CPU_TEMP_AVG}=$t_avg;  
  $t_avg = sprintf( "%.1f", (3 * ReadingsVal($hash->{NAME},"cpu0_temp_avg",$val_txt) + $val_txt ) / 4 );
  $map->{"cpu0_temp_avg"}=$t_avg;  
  
  $map = SYSMON_getComputeStat($hash, $map, $val_txt, CPU_TEMP."_stat");
  
  return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Temperature (mehrere Kerne eines ?)
#------------------------------------------------------------------------------
sub
SYSMON_getCPUTemp_X($$;$) {
  my ($hash, $map, $cpuNum) = @_;
  
  if($hash->{helper}->{excludes}{'cputemp'}) {return $map;}
  
  $cpuNum = 0 unless defined $cpuNum;
  
  my $val = SYSMON_execute($hash, "cat /sys/class/hwmon/hwmon0/device/hwmon/hwmon0/temp".($cpuNum+1)."_input 2>&1");
  $val = int($val);
  my $val_txt = sprintf("%.2f", $val/1000);
  $map->{"cpu".$cpuNum."_temp"}="$val_txt";
  my $t_avg = sprintf( "%.1f", (3 * ReadingsVal($hash->{NAME},"cpu".$cpuNum."_temp_avg",$val_txt) + $val_txt ) / 4 );
  $map->{"cpu".$cpuNum."_temp_avg"}=$t_avg;  
  
  $map = SYSMON_getComputeStat($hash, $map, $val_txt, "cpu".$cpuNum."_temp"."_stat");
  
  return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Temperature (FritzBox)
#------------------------------------------------------------------------------
sub
SYSMON_getCPUTemp_FB($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'cputemp'}) {return $map;}
  
  my $val = SYSMON_execute($hash, "ctlmgr_ctl r cpu status/StatTemperature");  
  if(defined($val)) {
    if($val=~m/(\d+),/) {
      my $fval = $1;
      my $val_txt = sprintf("%.2f", $fval);
      $map->{+CPU_TEMP}="$val_txt";
      my $t_avg = sprintf( "%.1f", (3 * ReadingsVal($hash->{NAME},CPU_TEMP_AVG,$val_txt) + $val_txt ) / 4 );
      $map->{+CPU_TEMP_AVG}="$t_avg";
      
      $map = SYSMON_getComputeStat($hash, $map, $val_txt, CPU_TEMP."_stat");
      
    }
  }
  return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Frequenz (Raspberry Pi, BeagleBone Black, Cubietruck, etc.)
# Sonderlocke fuer lokale Erfassung (damit die CPU nicht auf Max. gefahren wird)
# Dazu darf nicht in BlockingCall und keine System-Aufrufe wie 'cat' etc.
#------------------------------------------------------------------------------
sub
SYSMON_getCPUFreqLocal($$;$) {
	my ($hash, $map, $cpuNum) = @_;
	
	if($hash->{helper}->{excludes}{'cpufreq'}) {return $map;}
  
  $cpuNum = 0 unless defined $cpuNum;
  
	my $val;
  if(open(my $fh, '<', "/sys/devices/system/cpu/cpu".$cpuNum."/cpufreq/scaling_cur_freq")) {
    $val = <$fh>;
    close($fh);
  }
  
  $val = int($val);
  my $val_txt = sprintf("%d", $val/1000);
  if($cpuNum == 0) {
  	# aus Kompatibilitaetsgruenden
    $map->{+CPU_FREQ}="$val_txt";
    $map = SYSMON_getComputeStat($hash, $map, $val_txt, CPU_FREQ."_stat");
  }
  
  $map->{"cpu".$cpuNum."_freq"}="$val_txt";

  $map = SYSMON_getComputeStat($hash, $map, $val_txt, "cpu".$cpuNum."_freq"."_stat");
  
  return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Frequenz (Raspberry Pi, BeagleBone Black, Cubietruck, etc.)
# Nur Remote Aufrufe
#------------------------------------------------------------------------------
sub
SYSMON_getCPUFreq($$;$) {
  my ($hash, $map, $cpuNum) = @_;
  
  if($hash->{helper}->{excludes}{'cpufreq'}) {return $map;}
  
  $cpuNum = 0 unless defined $cpuNum;
  
  my $val;
  
  my $mode = $hash->{MODE};
  if ($mode eq 'local') {
  	# do nothing
  	return $map;
  }
  # XXX Hack: Versuch zu vermeiden, dass Frequenz immer als Maximum gelesen wird
  #my $mode = $hash->{MODE};#AttrVal( $name, 'mode', 'local');
  #if ($mode eq 'local') {
  #  if(open(my $fh, '<', "/sys/devices/system/cpu/cpu".$cpuNum."/cpufreq/scaling_cur_freq")) {
  #    $val = <$fh>;
  #    close($fh);
  #  }
  #} else {
    $val = SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/cpu".$cpuNum."/cpufreq/scaling_cur_freq ] && cat /sys/devices/system/cpu/cpu".$cpuNum."/cpufreq/scaling_cur_freq 2>&1 || echo 0");
  #}
  
  $val = int($val);
  my $val_txt = sprintf("%d", $val/1000);
  if($cpuNum == 0) {
  	# aus Kompatibilitaetsgruenden
    $map->{+CPU_FREQ}="$val_txt";
    $map = SYSMON_getComputeStat($hash, $map, $val_txt, CPU_FREQ."_stat");
  }
  
  $map->{"cpu".$cpuNum."_freq"}="$val_txt";

  $map = SYSMON_getComputeStat($hash, $map, $val_txt, "cpu".$cpuNum."_freq"."_stat");
  
  return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Frequenz fuer 2te CPU (Cubietruck, etc.)
#------------------------------------------------------------------------------
#sub
#SYSMON_getCPU1Freq($$)
#{
#  my ($hash, $map) = @_;
#  my $val = SYSMON_execute($hash, "cat /sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq 2>&1");
#  $val = int($val);
#  my $val_txt = sprintf("%d", $val/1000);
#  $map->{+CPU1_FREQ}="$val_txt";
#  return $map;
#}

#------------------------------------------------------------------------------
# leifert CPU Infos (Model name & Speed in BogoMIPS)
# TEST:  {Dumper(SYSMON_getCPUInfo($defs{sysmon},undef))}
#------------------------------------------------------------------------------
sub
SYSMON_getCPUInfo($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'cpuinfo'}) {return $map;}
  
  my $old_val1 = ReadingsVal($hash->{NAME},CPU_BOGOMIPS,undef);
  my $old_val2 = ReadingsVal($hash->{NAME},CPU_MODEL_NAME,undef);
  # nur einmalig ermitteln (wird sich ja nicht aendern
  if(!defined($old_val1) || !defined($old_val2)) {
    #my @aval = SYSMON_execute($hash, "cat /proc/cpuinfo | grep 'BogoMIPS'");
    my @aval = SYSMON_execute($hash, "cat /proc/cpuinfo");
    foreach my $line (@aval) {
      my($key, $val) = split(/\s*:\s+/, $line);
      if(defined($key)) {
        if($key=~m/Processor/ || $key=~m/model name/ || $key=~m/system type/) {
          if($val) {
            $val = trim($val);
            $map->{+CPU_MODEL_NAME}=$val;
          }
        } elsif ($key=~m/BogoMIPS/) {
          if($val) {
            $val = trim($val);
            $map->{+CPU_BOGOMIPS}=$val;
          }
        }
      }
    }
  } else {
    $map->{+CPU_BOGOMIPS}=$old_val1;
    $map->{+CPU_MODEL_NAME}=$old_val2;
  }
  
  return $map;
}

#------------------------------------------------------------------------------
# leifert Werte aus /proc/diskstat
# Werte:
# 1 - major number
# 2 - minor mumber
# 3 - device name
# Dann Datenwerte:
#   Field  1 -- # of reads issued
#   Field  2 -- # of reads merged
#   Field  3 -- # of sectors read
#   Field  4 -- # of milliseconds spent reading
#   Field  5 -- # of writes completed
#   Field  6 -- # of writes merged
#   Field  7 -- # of sectors written
#   Field  8 -- # of milliseconds spent writing
#   Field  9 -- # of I/Os currently in progress
#   Field 10 -- # of milliseconds spent doing I/Os
#   Field 11 -- weighted # of milliseconds spent doing I/Os
# Interessant sind eigentlich "nur" Feld 2 (readin), Feld 5 (write)
# Wenn es eher "um die zeit" geht, Feld 4 (reading), Feld 8 (writing), Feld 10 (Komplett)
# Kleiner Hinweis, Fled 1 ist das 4. der Liste, das 3. Giebt den Namen an. 
# Es giebt fuer jedes Devine und jede Partition ein Eintrag. 
# A /proc/diskstats continuously updated and all that is necessary for us - 
# make measurements for "second field" and "fourth field" in two different moment of time, 
# receiving a difference of values and dividing it into an interval of time, 
# we shall have Disk I/O stats in sectors/sec. Multiply this result on 512 (number of bytes in one sector) 
# we shall have Disk I/O stats in bytes/sec. 
#
# ...
# https://www.kernel.org/doc/Documentation/iostats.txt
#   Field  1 -- # of reads completed
#       This is the total number of reads completed successfully.
#   Field  2 -- # of reads merged, field 6 -- # of writes merged
#       Reads and writes which are adjacent to each other may be merged for
#       efficiency.  Thus two 4K reads may become one 8K read before it is
#       ultimately handed to the disk, and so it will be counted (and queued)
#       as only one I/O.  This field lets you know how often this was done.
#   Field  3 -- # of sectors read
#       This is the total number of sectors read successfully.
#   Field  4 -- # of milliseconds spent reading
#       This is the total number of milliseconds spent by all reads (as
#       measured from __make_request() to end_that_request_last()).
#   Field  5 -- # of writes completed
#       This is the total number of writes completed successfully.
#   Field  6 -- # of writes merged
#       See the description of field 2.
#   Field  7 -- # of sectors written
#       This is the total number of sectors written successfully.
#   Field  8 -- # of milliseconds spent writing
#       This is the total number of milliseconds spent by all writes (as
#       measured from __make_request() to end_that_request_last()).
#   Field  9 -- # of I/Os currently in progress
#       The only field that should go to zero. Incremented as requests are
#       given to appropriate struct request_queue and decremented as they finish.
#   Field 10 -- # of milliseconds spent doing I/Os
#       This field increases so long as field 9 is nonzero.
#   Field 11 -- weighted # of milliseconds spent doing I/Os
#       This field is incremented at each I/O start, I/O completion, I/O
#       merge, or read of these stats by the number of I/Os in progress
#       (field 9) times the number of milliseconds spent doing I/O since the
#       last update of this field.  This can provide an easy measure of both
#       I/O completion time and the backlog that may be accumulating.
#
# 
#   Disks vs Partitions
#   -------------------
#   
#   There were significant changes between 2.4 and 2.6 in the I/O subsystem.
#   As a result, some statistic information disappeared. The translation from
#   a disk address relative to a partition to the disk address relative to
#   the host disk happens much earlier.  All merges and timings now happen
#   at the disk level rather than at both the disk and partition level as
#   in 2.4.  Consequently, you'll see a different statistics output on 2.6 for
#   partitions from that for disks.  There are only *four* fields available
#   for partitions on 2.6 machines.  This is reflected in the examples above.
#   
#   Field  1 -- # of reads issued
#       This is the total number of reads issued to this partition.
#   Field  2 -- # of sectors read
#       This is the total number of sectors requested to be read from this
#       partition.
#   Field  3 -- # of writes issued
#       This is the total number of writes issued to this partition.
#   Field  4 -- # of sectors written
#       This is the total number of sectors requested to be written to
#       this partition.
#------------------------------------------------------------------------------
sub SYSMON_getDiskStat($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'diskstat'}) {return $map;}
  
  my @values = SYSMON_execute($hash, "cat /proc/diskstats");

  for my $entry (@values){
    $map = SYSMON_getDiskStat_intern($hash, $map, $entry);
    #Log 3, "SYSMON-DEBUG-IOSTAT:   ".$entry;
  }

  return $map;
}

sub
SYSMON_getDiskStat_intern($$$) 
{
  my ($hash, $map, $entry) = @_;
  
  my ($d1, $d2, $pName, $nf1, $nf2, $nf3, $nf4, $nf5, $nf6, $nf7, $nf8, $nf9, $nf10, $nf11) = split(/\s+/, trim($entry));
  
  SYSMON_Log($hash, 5, "SYSMON-DEBUG-IOSTAT:   ".$pName." = ".$nf1." ".$nf2." ".$nf3." ".$nf4." ".$nf5." ".$nf6." ".$nf7." ".$nf8." ".$nf9." ".$nf10." ".$nf11);
  
  # Nur nicht-null-Werte
  if($nf1 eq "0") {
    return $map;
  } 
  
  $pName = "io_".$pName;
  #Log 3, "SYSMON-DEBUG-IOSTAT:   ".$pName;
  
  # Partition and 2.6-Kernel?
  if(defined($nf5)) {
    # no
    $map->{$pName."_raw"}=$nf1." ".$nf2." ".$nf3." ".$nf4." ".$nf5." ".$nf6." ".$nf7." ".$nf8." ".$nf9." ".$nf10." ".$nf11;
  } else {
    $map->{$pName."_raw"}=$nf1." ".$nf2." ".$nf3." ".$nf4;
  }
  #$map->{"iostat_test"}="TEST";
  my $lastVal = ReadingsVal($hash->{NAME},$pName."_raw",undef);
  if(defined($lastVal)) {
    SYSMON_Log($hash,5, "SYSMON-DEBUG-IOSTAT:   lastVal: $pName=".$lastVal);
  }
  if(defined $lastVal) {
    # Diff. ausrechnen, falls vorherigen Werte vorhanden sind.
    my($af1, $af2, $af3, $af4, $af5, $af6, $af7, $af8, $af9, $af10, $af11) = split(/\s+/, $lastVal);
    
    SYSMON_Log($hash,5, "SYSMON-DEBUG-IOSTAT:   X: ".$pName." = ".$af1." ".$af2." ".$af3." ".$af4." ".$af5." ".$af6." ".$af7." ".$af8." ".$af9." ".$af10." ".$af11);
    
    my $sectorsRead;
    my $sectorsWritten;
  
    my $df1 = $nf1-$af1;
    my $df2 = $nf2-$af2;
    my $df3 = $nf3-$af3;
    my $df4 = $nf4-$af4;
    # Partition and 2.6-Kernel?
    if(defined($nf5)) {
      # no
      my $df5 = $nf5-$af5;
      my $df6 = $nf6-$af6;
      my $df7 = $nf7-$af7;
      my $df8 = $nf8-$af8;
      my $df9 = $nf9-$af9;
      my $df10 = $nf10-$af10;
      my $df11 = $nf11-$af11;
      $map->{$pName."_diff"}=$df1." ".$df2." ".$df3." ".$df4." ".$df5." ".$df6." ".$df7." ".$df8." ".$df9." ".$df10." ".$df11;
      
      $sectorsRead = $df3;
      $sectorsWritten = $df7;
    } else {
      $map->{$pName."_diff"}=$df1." ".$df2." ".$df3." ".$df4;     
      
      $sectorsRead = $df2;
      $sectorsWritten = $df4;
    }
    
    my $sectorBytes = 512;
    
    my $BytesRead    = $sectorsRead*$sectorBytes;
    my $BytesWritten = $sectorsWritten*$sectorBytes;
    
    # TODO: Summenwerte
    $map->{$pName.""}=sprintf("bytes read: %d bytes written: %d",$BytesRead, $BytesWritten);
  }

  return $map;
}


#------------------------------------------------------------------------------
# leifert Werte aus /proc/stat
# Werte:
#   neuCPUuser, neuCPUnice, neuCPUsystem, neuCPUidle, neuCPUiowait, neuCPUirq, neuCPUsoftirq
# Differenzberechnung:
#   CPUuser = neuCPUuser - altCPUuser (fuer alle anderen analog)
#   GesammtCPU = CPUuser + CPUnice + CPUsystem + CPUidle + CPUiowait + CPUirq + CPUsoftirq
# Belastung in %:
#   ProzCPUuser = (CPUuser / GesammtCPU) * 100
#------------------------------------------------------------------------------
sub
SYSMON_getCPUProcStat($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'cpustat'}) {return $map;}
  
  my @values = SYSMON_execute($hash, "cat /proc/stat");
  
  for my $entry (@values){
    if (index($entry, "cpu") < 0){
      last;
    }
    $map = SYSMON_getCPUProcStat_intern($hash, $map, $entry);
  }
  
  # Wenn nur eine CPU vorhanden ist, loeschen Werte fuer CPU0 (nur Gesamt belassen)
  if(!defined($map->{"stat_cpu1"})){
    delete $map->{"stat_cpu0"};
    delete $map->{"stat_cpu0_diff"};
    delete $map->{"stat_cpu0_percent"};
  }
  
  return $map;
}

sub
SYSMON_getCPUProcStat_intern($$$) 
{
  my ($hash, $map, $entry) = @_;
  
  my($tName, $neuCPUuser, $neuCPUnice, $neuCPUsystem, $neuCPUidle, $neuCPUiowait, $neuCPUirq, $neuCPUsoftirq) = split(/\s+/, trim($entry));
  my $pName = "stat_".$tName;
  $map->{$pName}=$neuCPUuser." ".$neuCPUnice." ".$neuCPUsystem." ".$neuCPUidle." ".$neuCPUiowait." ".$neuCPUirq." ".$neuCPUsoftirq;
  
  my $lastVal = ReadingsVal($hash->{NAME},$pName,undef);
  if(defined $lastVal) {
    # Diff. ausrechnen, falls vorherigen Werte vorhanden sind.
    my($altCPUuser, $altCPUnice, $altCPUsystem, $altCPUidle, $altCPUiowait, $altCPUirq, $altCPUsoftirq) = split(/\s+/, $lastVal);
    
    my ($CPUuser, $CPUnice, $CPUsystem, $CPUidle, $CPUiowait, $CPUirq, $CPUsoftirq);

  	if($neuCPUuser < $altCPUuser) {
        $CPUuser    = $neuCPUuser;
        $CPUnice    = $neuCPUnice;
        $CPUsystem  = $neuCPUsystem;
        $CPUidle    = $neuCPUidle;
        $CPUiowait  = $neuCPUiowait;
        $CPUirq     = $neuCPUirq;
        $CPUsoftirq = $neuCPUsoftirq;
  	}
  	else {
        $CPUuser    = $neuCPUuser    - $altCPUuser;
        $CPUnice    = $neuCPUnice    - $altCPUnice;
        $CPUsystem  = $neuCPUsystem  - $altCPUsystem;
        $CPUidle    = $neuCPUidle    - $altCPUidle;
        $CPUiowait  = $neuCPUiowait  - $altCPUiowait;
        $CPUirq     = $neuCPUirq     - $altCPUirq;
        $CPUsoftirq = $neuCPUsoftirq - $altCPUsoftirq;
  	}
    
    $map->{$pName."_diff"}=$CPUuser." ".$CPUnice." ".$CPUsystem." ".$CPUidle." ".$CPUiowait." ".$CPUirq." ".$CPUsoftirq;
    
    my $GesammtCPU = $CPUuser + $CPUnice + $CPUsystem + $CPUidle + $CPUiowait + $CPUirq + $CPUsoftirq;
    my $PercentCPUuser    = ($CPUuser    / $GesammtCPU) * 100;
    my $PercentCPUnice    = ($CPUnice    / $GesammtCPU) * 100;
    my $PercentCPUsystem  = ($CPUsystem  / $GesammtCPU) * 100;
    my $PercentCPUidle    = ($CPUidle    / $GesammtCPU) * 100;
    my $PercentCPUiowait  = ($CPUiowait  / $GesammtCPU) * 100;
    my $PercentCPUirq     = ($CPUirq     / $GesammtCPU) * 100;
    my $PercentCPUsoftirq = ($CPUsoftirq / $GesammtCPU) * 100;
    
    $map->{$pName."_percent"}=sprintf ("%.2f %.2f %.2f %.2f %.2f %.2f %.2f",$PercentCPUuser,$PercentCPUnice,$PercentCPUsystem,$PercentCPUidle,$PercentCPUiowait,$PercentCPUirq,$PercentCPUsoftirq);
    $map->{$pName."_text"}=sprintf ("user: %.2f %%, nice: %.2f %%, sys: %.2f %%, idle: %.2f %%, io: %.2f %%, irq: %.2f %%, sirq: %.2f %%",$PercentCPUuser,$PercentCPUnice,$PercentCPUsystem,$PercentCPUidle,$PercentCPUiowait,$PercentCPUirq,$PercentCPUsoftirq);
    
    $map = SYSMON_getComputeStat($hash, $map, $PercentCPUidle, $tName."_idle_stat");
  }

  return $map;
}

#------------------------------------------------------------------------------
# Liefert Werte fuer RAM und SWAP (Gesamt, Verwendet, Frei).
#------------------------------------------------------------------------------
sub SYSMON_getRamAndSwap($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'ramswap'}) {return $map;}

  #my @speicher = qx(free -m);
  #my @speicher = SYSMON_execute($hash, "LANG=en free");
  my $free_version = SYSMON_execute($hash, 'free -V');
  $free_version =~ s/\D//g;
  my @speicher = SYSMON_execute($hash, 'LANG=en ' . ($free_version > 339 ? 'free -w' : 'free'));


  if(!@speicher) {
    return $map;
  }

  shift @speicher;
  my ($fs_desc, $total, $used, $free, $shared, $buffers, $cached);
  if(defined ($speicher[0])) {
    ($fs_desc, $total, $used, $free, $shared, $buffers, $cached) = split(/\s+/, trim($speicher[0]));
  }
  
  shift @speicher;
  my ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2);
  
  if(defined ($speicher[0])) {
    ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim($speicher[0]))  
  }
  
  if(defined($fs_desc2)) {
    if($fs_desc2 ne "Swap:") {
      shift @speicher;
      if(defined ($speicher[0])) {
        ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim($speicher[0]));
      }
    }
  }

  my $ram;
  my $swap;
  #my $percentage_ram;
  #my $percentage_swap;
  
  my $used_clean;
  
  if(defined($total) && $total > 0) {
  
    $total   = $total / 1024;
    $used    = $used / 1024;
    $free    = $free / 1024;
    $buffers = $buffers / 1024;
    if(defined($cached)) {
      $cached  = $cached / 1024;
    } else {
      # Bei FritzBox wird dieser Wert nicht ausgegeben
      $cached  = 0;
    }
    #$used_clean = $used - $buffers - $cached;
    #$ram = sprintf("Total: %.2f MB, Used: %.2f MB, %.2f %%, Free: %.2f MB", $total, $used_clean, ($used_clean / $total * 100), ($free + $buffers + $cached));
    #if ($total > 2048) {
    if ($free_version > 339) {
       $used_clean = $used;
       $ram = sprintf("Total: %.2f MB, Used: %.2f MB, %.2f %%, Free: %.2f MB", $total, $used_clean, ($used_clean / $total * 100), ($free));
     } else {
       $used_clean = $used - $buffers - $cached;
       $ram = sprintf("Total: %.2f MB, Used: %.2f MB, %.2f %%, Free: %.2f MB", $total, $used_clean, ($used_clean / $total * 100), ($free + $buffers + $cached));
     }
  }
  else
  {
    $ram = "n/a";
  }
  $map->{+RAM} = $ram;
  
  $map = SYSMON_getComputeStat($hash, $map, $used_clean, "ram_used_stat");
  
  # wenn kein swap definiert ist, ist die Groesse (total2) gleich Null. Dies wuerde eine Exception (division by zero) ausloesen
  if(defined($total2) && $total2 > 0 && defined($used2) && defined($free2)) {
    $total2   = $total2 / 1024;
    $used2    = $used2 / 1024;
    $free2    = $free2 / 1024;
  
    $swap = sprintf("Total: %.2f MB, Used: %.2f MB,  %.2f %%, Free: %.2f MB", $total2, $used2, ($used2 / $total2 * 100), $free2);
  } else {
    $swap = "n/a"
  }

  $map->{+SWAP} = $swap;
  $map = SYSMON_getComputeStat($hash, $map, $used2, "swap_used_stat");
  
  return $map;
}

#------------------------------------------------------------------------------
# Prueft, ob das Host-System OSX ist (darvin).
#------------------------------------------------------------------------------
sub SYSMON_isOSX()
{
  return $^O eq 'darwin';
}

#------------------------------------------------------------------------------
# Prueft, ob das Host-System Linux ist (linux).
#------------------------------------------------------------------------------
sub SYSMON_isLinux()
{
  return $^O eq 'linux';
}

#------------------------------------------------------------------------------
# Liefert Werte fuer RAM und SWAP (Gesamt, Verwendet, Frei).
#------------------------------------------------------------------------------
sub SYSMON_getRamAndSwapOSX($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'ramswap'}) {return $map;}
  
  my $debug = 0; # Nur zum Testen!

  #my @speicher = qx(free -m);
  my @amemsize = SYSMON_execute($hash, "sysctl hw.memsize");
  
  if($debug) {
    @amemsize = ("hw.memsize: 8589934592");
  }
  
  if($amemsize[0]=~m/hw.memsize:\s+(.+)/) {
    my $total = $1;
    
    my @avmstat = SYSMON_execute($hash, "vm_stat");
    if($debug) {
      @avmstat = ('Mach Virtual Memory Statistics: (page size of 4096 bytes)',
                  'Pages free:                                5268.',
                  'Pages active:                            440314.',
                  'Pages inactive:                          430905.',
                  'Pages speculative:                          878.',
                  'Pages throttled:                              0.',
                  'Pages wired down:                        398445.',
                  'Pages purgeable:                             69.',
                  '"Translation faults":                 508984629.',
                  'Pages copy-on-write:                    5668036.',
                  'Pages zero filled:                    347281743.',
                  'Pages reactivated:                    114745855.',
                  'Pages purged:                          13495647.',
                  'File-backed pages:                        88747.',
                  'Anonymous pages:                         783350.',
                  'Pages stored in compressor:             1760568.',
                  'Pages occupied by compressor:            820444.',
                  'Decompressions:                        48558417.',
                  'Compressions:                          63022425.',
                  'Pageins:                                3754238.',
                  'Pageouts:                                589840.',
                  'Swapins:                                 714378.',
                  'Swapouts:                               1017813.');
    }
    
    #wired down, active, inactive
    my $wired_down=0;
    my $active=0;
    my $inactive=0;
    my $blockSize = 4096;
    foreach my $k (@avmstat) {
      if($k=~m/page\s+size\s+of\s+(\d+)\s+bytes/) {
        $blockSize = $1;
      }
      if($k=~m/Pages\s+wired\s+down:\s+(.+)\./) {
        $wired_down = $1;
      }
      if($k=~m/Pages\s+active:\s+(.+)\./) {
        $active = $1;
      }
      if($k=~m/Pages\s+inactive:\s+(.+)\./) {
        $inactive = $1;
      }
    }
    
    $wired_down = $wired_down * $blockSize / 1048576; # In Megabyte umrechnen
    $active = $active * $blockSize / 1048576;
    $inactive = $inactive * $blockSize / 1048576;
    
    my $used = $wired_down+$active+$inactive;
    
    $total = $total/1048576;
    my $free = $total-$used;
    my $ram = sprintf("Total: %.2f MB, Used: %.2f MB, %.2f %%, Free: %.2f MB", $total, $used , ($used / $total * 100), $free);
    #Log 3, "SYSMON >>>>>>>>>>>>>>>>>>>>>>>>> OSX: RAM:  ".$ram;
    $map->{+RAM} = $ram;
    $map = SYSMON_getComputeStat($hash, $map, $used, "ram_used_stat");
  
    my @avm = SYSMON_execute($hash, "sysctl vm.swapusage");
    if($debug) {
      @avm=(
      #'vm.loadavg: { 2.45 2.19 3.34 }',
      'vm.swapusage: total = 1024.00M  used = 529.25M  free = 494.75M  (encrypted)',
      #'vm.cs_force_kill: 0',
      #'vm.cs_force_hard: 0',
      #'vm.cs_debug: 0',
      #'vm.cs_all_vnodes: 0',
      #'vm.cs_enforcement: 0',
      #'vm.cs_enforcement_panic: 0',
      #'vm.sigpup_disable: 0',
      #'vm.global_no_user_wire_amount: 67108864',
      #'vm.global_user_wire_limit: 8522825728',
      #'vm.user_wire_limit: 8522825728',
      #'vm.vm_copy_src_not_internal: 129',
      #'vm.vm_copy_src_not_symmetric: 14994',
      #'vm.vm_copy_src_large: 0',
      #'vm.vm_page_external_count: 355255',
      #'vm.vm_page_filecache_min: 104857',
      #'vm.compressor_mode: 4',
      #'vm.compressor_bytes_used: 2984467096',
      #'vm.compressor_swapout_target_age: 0',
      #'vm.compressor_eval_period_in_msecs: 250',
      #'vm.compressor_sample_min_in_msecs: 500',
      #'vm.compressor_sample_max_in_msecs: 10000',
      #'vm.compressor_thrashing_threshold_per_10msecs: 50',
      #'vm.compressor_thrashing_min_per_10msecs: 20',
      #'vm.compressor_minorcompact_threshold_divisor: 20',
      #'vm.compressor_majorcompact_threshold_divisor: 25',
      #'vm.compressor_unthrottle_threshold_divisor: 35',
      #'vm.compressor_catchup_threshold_divisor: 50',
      #'vm.cs_validation: 1',
      #'vm.cs_blob_count: 616',
      #'vm.cs_blob_size: 8053170',
      #'vm.cs_blob_count_peak: 693',
      #'vm.cs_blob_size_peak: 8389641',
      #'vm.cs_blob_size_max: 1675264',
      #'vm.vm_debug_events: 0',
      #'vm.allow_stack_exec: 0',
      #'vm.allow_data_exec: 1',
      #'vm.shared_region_unnest_logging: 1',
      #'vm.shared_region_trace_level: 1',
      #'vm.shared_region_version: 3',
      #'vm.shared_region_persistence: 0',
      #'vm.vm_page_free_target: 2000',
      #'vm.memory_pressure: 0',
      #'vm.page_free_wanted: 86',
      #'vm.page_purgeable_count: 1055',
      #'vm.page_purgeable_wired_count: 0',
      #'vm.madvise_free_debug: 0',
      #'vm.page_reusable_count: 39048',
      #'vm.reusable_success: 11350536',
      #'vm.reusable_failure: 1060241',
      #'vm.reusable_shared: 248771',
      #'vm.all_reusable_calls: 290574',
      #'vm.partial_reusable_calls: 11142306',
      #'vm.reuse_success: 9593371',
      #'vm.reuse_failure: 5124',
      #'vm.all_reuse_calls: 257820',
      #'vm.partial_reuse_calls: 9684238',
      #'vm.can_reuse_success: 6171792',
      #'vm.can_reuse_failure: 79183',
      #'vm.reusable_reclaimed: 0',
      #'vm.page_free_count: 1914',
      #'vm.page_speculative_count: 810',
      #'vm.page_cleaned_count: 0',
      #'vm.pageout_inactive_dirty_internal: 63170734',
      #'vm.pageout_inactive_dirty_external: 465495',
      #'vm.pageout_inactive_clean: 18967682',
      #'vm.pageout_speculative_clean: 32929182',
      #'vm.pageout_inactive_used: 115155398',
      #'vm.pageout_freed_from_inactive_clean: 18423099',
      #'vm.pageout_freed_from_speculative: 32929182',
      #'vm.pageout_freed_from_cleaned: 568334',
      #'vm.pageout_enqueued_cleaned: 1010912',
      #'vm.pageout_enqueued_cleaned_from_inactive_clean: 0',
      #'vm.pageout_enqueued_cleaned_from_inactive_dirty: 1011010',
      #'vm.pageout_cleaned: 568334',
      #'vm.pageout_cleaned_reactivated: 407922',
      #'vm.pageout_cleaned_reference_reactivated: 4',
      #'vm.pageout_cleaned_volatile_reactivated: 0',
      #'vm.pageout_cleaned_fault_reactivated: 557',
      #'vm.pageout_cleaned_commit_reactivated: 407361',
      #'vm.pageout_cleaned_busy: 33',
      #'vm.pageout_cleaned_nolock: 12931'
      );
    }
    
    #vm.swapusage: total = 1024.00M  used = 529.25M  free = 494.75M  (encrypted)
    if($avm[0]=~m/vm.swapusage:\s+total\s+=\s+(\S*)\s+used\s+=\s+(\S*)\s+free\s+=\s+(\S*)\s+(.*)/) {
      my $total2 = SYSMON_fmtStorageAmount_($1);
      my $used2  = SYSMON_fmtStorageAmount_($2);
      my $free2  = SYSMON_fmtStorageAmount_($3);
      my $swap = sprintf("Total: %.2f MB, Used: %.2f MB,  %.2f %%, Free: %.2f MB", $total2, $used2, ($used2 / $total2 * 100), $free2);
      $map->{+SWAP} = $swap; 
      $map = SYSMON_getComputeStat($hash, $map, $used2, "swap_used_stat");
      #Log 3, "SYSMON >>>>>>>>>>>>>>>>>>>>>>>>> OSX: SWAP: ".$swap;
    }
  }
  
  return $map;
}

sub SYSMON_fmtStorageAmount_($) {
  my ($t) = @_;
  if($t=~m/([\d|\.]+)(.*)/) {
    my $r=$1;
    my $m=$2;
    if($m) {
      # Modifier testen
      if($m eq 'M') {
        # Megabyte ist OK,so lassen
        return $r;
      }
      if($m eq 'G') {
        # Gigabyte: in MB umwandeln
        $r=$r*1024;
      }
      # K, oder P nehmen ich nicht mehr bzw. noch nicht an ;)
      return $r;
    }
  }
  return $t;
}



#------------------------------------------------------------------------------
# Liefert Fuellstand fuer das angegebene Dateisystem (z.B. '/dev/root', '/dev/sda1' (USB stick)).
# Eingabeparameter: HASH; MAP; FS-Bezeichnung
#------------------------------------------------------------------------------
sub SYSMON_getFileSystemInfo ($$$) {
  my ($hash, $map, $fs) = @_;
  
  if($hash->{helper}->{excludes}{'filesystem'}) {return $map;}
  
  SYSMON_Log($hash, 5, "get $fs");
  
  # Neue Syntax: benannte Filesystems: <name>:<definition>
  my($fName, $fDef, $fComment) = split(/:/, $fs);
  if(defined $fDef) {
    $fs = $fDef;
  }

  #my $disk = "df ".$fs." -m 2>&1"; # in case of failure get string from stderr
  my $disk = "df ".$fs." -m 2>/dev/null";
  
  SYSMON_Log($hash, 5, "exec $disk");

  #my @filesystems = qx($disk);
  my @filesystems = SYSMON_execute($hash, $disk);
  
  SYSMON_Log($hash, 5, "recieved ".scalar(scalar(@filesystems))." lines");
  
  # - DEBUG -
  #if($fs eq "/test") {
  #  @filesystems=(
  #    "Filesystem           1M-blocks      Used Available Use% Mounted on",
  #    "/dev/mapper/n40l-root",
  #    "                        226741     22032    193192  11% /"
  #  );
  #  $fs = "/";
  #}
  #- DEBUG -
  
  
  #if(!defined @filesystems) { return $map; } # Ausgabe leer
  #if(scalar(@filesystems) == 0) { return $map; } # Array leer

  if(defined($filesystems[0])) {
    SYSMON_Log($hash, 5, "recieved line0 $filesystems[0]");
  } else {
    SYSMON_Log($hash, 5, "recieved empty line");
  }

  shift @filesystems;
  
  # Falls kein Eintrag gefunden (z.B: kein Medium im Laufwerk), mit Nullen fuellen (damit die Plots richtig funktionieren).
  if(defined $fDef) {
    $map->{$fName} = "Total: 0 MB, Used: 0 MB, 0 %, Available: 0 MB at ".$fs." (not available)";
  } else {
    $map->{+FS_PREFIX.$fs} = "Total: 0 MB, Used: 0 MB, 0 %, Available: 0 MB at ".$fs." (not available)";
  }
  
  #return $map unless defined(@filesystems);
  return $map unless int(@filesystems)>0;
  #if(!defined $filesystems[0]) { return $map; } # Ausgabe leer
  
  SYSMON_Log($hash, 5, "analyse line $filesystems[0] for $fs");
  
  #if (!($filesystems[0]=~ /$fs\s*$/)){ shift @filesystems; }
  if (!($filesystems[0]=~ /$fs$/)){ 
    shift @filesystems; 
    if(int(@filesystems)>0) {
      SYSMON_Log($hash, 5, "analyse line $filesystems[0] for $fs");
    }
  } else {
    SYSMON_Log($hash, 5, "pattern ($fs) found");
  }
  #if (index($filesystems[0], $fs) < 0) { shift @filesystems; } # Wenn die Bezeichnung so lang ist, dass die Zeile umgebrochen wird...
  #if (index($filesystems[0], $fs) >= 0) # check if filesystem available -> gives failure on console
  if (int(@filesystems)>0 && $filesystems[0]=~ /$fs$/)
  {
    SYSMON_Log($hash, 5, "use line $filesystems[0]");
    
    my ($fs_desc, $total, $used, $available, $percentage_used, $mnt_point) = split(/\s+/, $filesystems[0]);
    $percentage_used =~ /^(.+)%$/;
    $percentage_used = $1;
    my $out_txt = "Total: ".$total." MB, Used: ".$used." MB, ".$percentage_used." %, Available: ".$available." MB at ".$mnt_point;
    if(defined $fDef) {
      $map->{$fName} = $out_txt;
    } else {
      $map->{+FS_PREFIX.$mnt_point} = $out_txt;
    }
  }

  # else {
  # if(defined $fDef) {
  #   $map->{$fName} = "not available";
  # } else {
  #   $map->{+FS_PREFIX.$fs} = "not available";
  # }
  #}

  return $map;
}

#------------------------------------------------------------------------------
# Liefert Netztwerkinformationen
# Parameter: HASH; MAP; DEVICE (eth0 or wlan0)
#------------------------------------------------------------------------------
sub SYSMON_getNetworkInfo ($$$) {
  my ($hash, $map, $device) = @_;
  
  if($hash->{helper}->{excludes}{'network'}) {return $map;}

  return $map unless (-e "/sbin/ifconfig");
  
  SYSMON_Log($hash, 5, "get $device");
  my($nName, $nDef) = split(/:/, $device);
  if(!defined $nDef) {
    $nDef = $nName;
  }
  $device = $nDef;

  # in case of network not present get failure from stderr (2>&1)
  my $cmd="/sbin/ifconfig ".$device." 2>&1";

  #my @dataThroughput = qx($cmd);
  my @dataThroughput = SYSMON_execute($hash, $cmd);
  SYSMON_Log ($hash, 5, "SYSMON_getNetworkInfo>>>>>>>>>>>>>>>>".Dumper(@dataThroughput));
  
  #--- DEBUG ---
  if($device eq "_test1") {
    @dataThroughput = (
    "enp4s0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1492",
    "        inet 192.168.2.7  netmask 255.255.255.0  broadcast 192.168.2.255",
    "        ether 00:21:85:5a:0d:e0  txqueuelen 1000  (Ethernet)",
    "        RX packets 1553313  bytes 651891540 (621.6 MiB)",
    "        RX errors 0  dropped 0  overruns 0  frame 0",
    "        TX packets 1915387  bytes 587386206 (560.1 MiB)",
    "        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0");
  }
  
  if($device eq "_test2") {
    @dataThroughput = (
    "eth0      Link encap:Ethernet  Hardware Adresse b8:27:eb:47:a9:8d",
    "          inet Adresse:192.168.2.118  Bcast:192.168.2.255  Maske:255.255.255.0",
    "          inet6-Adresse: 2003:46:b6b:3100:ba27:ebff:fe47:a98d/64 Gültigkeitsbereich:Global",
    "          inet6-Adresse: fe80::ba27:ebff:fe47:a98d/64 Gültigkeitsbereich:Verbindung",
    "          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metrik:1",
    "          RX packets:1224709 errors:0 dropped:0 overruns:0 frame:0",
    "          TX packets:1156620 errors:0 dropped:0 overruns:0 carrier:0",
    "          Kollisionen:0 Sendewarteschlangenlänge:1000",
    "          RX bytes:180806073 (172.4 MiB)  TX bytes:108919337 (103.8 MiB)");
  }
  #--- DEBUG ---

  # check if network available
  if (defined($dataThroughput[0]) && index($dataThroughput[0], 'Fehler') < 0 && index($dataThroughput[0], 'error') < 0)
  {
    #Log 3, "SYSMON>>>>>>>>>>>>>>>>> OK >>>".$dataThroughput[0];
    my $dataThroughput = undef;
    
    # Suche nach der Daten in Form:
    # eth0      Link encap:Ethernet  Hardware Adresse b8:27:eb:a5:e0:85
    #           inet Adresse:192.168.0.10  Bcast:192.168.0.255  Maske:255.255.255.0
    #           UP BROADCAST RUNNING MULTICAST  MTU:1500  Metrik:1
    #           RX packets:339826 errors:0 dropped:45 overruns:0 frame:0
    #           TX packets:533293 errors:0 dropped:0 overruns:0 carrier:0
    #           Kollisionen:0 Sendewarteschlangenlaenge:1000
    #           RX bytes:25517384 (24.3 MiB)  TX bytes:683970999 (652.2 MiB)
    

    my $ip = undef; my $ip6 = undef;
    foreach (@dataThroughput) {
      if($_=~ m/inet\s+(Adresse:)*(\S*)/) {
        $ip=$2;
      }
      if(!$ip && $_=~ m/inet\s+(addr:)*(\S*)/) {
        $ip=$2;
        SYSMON_Log ($hash, 3, "SYSMON_getNetworkInfo:ip: ".$ip);
      }
      
      if($_=~ m/inet6-(Adresse:)*\s*(\S*)\s+G.ltigkeitsbereich:Verbindung/) {
        $ip6=$2;
      }
      if(!$ip && $_=~ m/inet6\s+(addr:)*\s*(\S*)\s+Scope:Link/) {
        $ip6=$2;
      }
      if(!$ip && $_=~ m/inet6\s+(addr:)*\s*(\S*)/) {
        $ip6=$2;
      }

      if(index($_, 'RX bytes') >= 0) {
        $dataThroughput = $_;
        last;
      }
    }
    
    if(defined $ip) {
      $ip =~ s/addr://;
      $map->{$nName.IP_SUFFIX} = $ip;
    }
    
    if(defined $ip6) {
        $ip6 =~ s/addr://;
      $map->{$nName.IP6_SUFFIX} = $ip6;
    }

    my $rxRaw = -1;
    my $txRaw = -1;
    # if(-e "/sys/class/net/$nName/statistics/rx_bytes" && -e "/sys/class/net/$nName/statistics/tx_bytes") {
    if(SYSMON_isNetStatClass($hash, $nName)) {
        $rxRaw = SYSMON_execute($hash, "cat /sys/class/net/$nName/statistics/rx_bytes");
        $rxRaw = -1 unless (defined($rxRaw) && looks_like_number($rxRaw));
        $txRaw = SYSMON_execute($hash, "cat /sys/class/net/$nName/statistics/tx_bytes");
        $txRaw = -1 unless (defined($txRaw) && looks_like_number($txRaw));
    }

  if($rxRaw<0||$txRaw<0) {
    if(defined $dataThroughput) {
      # remove RX bytes or TX bytes from string
      $dataThroughput =~ s/RX bytes://;
      $dataThroughput =~ s/TX bytes://;
      $dataThroughput = trim($dataThroughput);

      @dataThroughput = split(/ /, $dataThroughput); # return of split is array
      $rxRaw = $dataThroughput[0] if(defined $dataThroughput[0]);
      $txRaw = $dataThroughput[4] if(defined $dataThroughput[4]);
    } else {
      #
      # an manchen Systemen kann die Ausgabe leider auch anders aussehen:
      # enp4s0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1492
        #         inet 192.168.2.7  netmask 255.255.255.0  broadcast 192.168.2.255
        #         ether 00:21:85:5a:0d:e0  txqueuelen 1000  (Ethernet)
        #         RX packets 1553313  bytes 651891540 (621.6 MiB)
        #         RX errors 0  dropped 0  overruns 0  frame 0
        #         TX packets 1915387  bytes 587386206 (560.1 MiB)
        #         TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
      #
        my $d;
        foreach $d (@dataThroughput) {
          if($d =~ m/RX\s.*\sbytes\s(\d*)\s/) {
            $rxRaw = $1;
          }
          if($d =~ m/TX\s.*\sbytes\s(\d*)\s/) {
            $txRaw = $1;
          }
        }
      }
    }
    
    if($rxRaw<0) {
      # Daten nicht gefunden / Format unbekannt
      $map->{$nName} = "unexpected format";
      $map->{$nName.DIFF_SUFFIX} = "unexpected format";
    } else {
      $map->{$nName."_rx"} = $rxRaw;       
      $map->{$nName."_tx"} = $txRaw;
      
      $rxRaw = $rxRaw / 1048576; # Bytes in MB
      $txRaw = $txRaw / 1048576;
      
      my $rx = sprintf ("%.2f", $rxRaw);
      my $tx = sprintf ("%.2f", $txRaw);
      my $totalRxTx = $rx + $tx;

      my $out_txt = "RX: ".$rx." MB, TX: ".$tx." MB, Total: ".$totalRxTx." MB";
      $map->{$nName} = $out_txt;

      my $lastVal = ReadingsVal($hash->{NAME},$nName,"RX: 0 MB, TX: 0 MB, Total: 0 MB");
      my ($d0, $o_rx, $d1, $d2, $o_tx, $d3, $d4, $o_tt, $d5) = split(/\s+/, trim($lastVal));

      if(defined($o_tx) && defined($o_tt)) {
        my $d_rx = $rx-$o_rx;
        if($d_rx<0) {$d_rx=0;}
        my $d_tx = $tx-$o_tx;
        if($d_tx<0) {$d_tx=0;}
        my $d_tt = $totalRxTx-$o_tt;
        if($d_tt<0) {$d_tt=0;}
        my $out_txt_diff = "RX: ".sprintf ("%.2f", $d_rx)." MB, TX: ".sprintf ("%.2f", $d_tx)." MB, Total: ".sprintf ("%.2f", $d_tt)." MB";
        $map->{$nName.DIFF_SUFFIX} = $out_txt_diff;
      }
      
      my $speed;
      #if ($nName eq "wlan0") {
      if($nName=~m/wlan/) {
        #my @iwData = SYSMON_execute($hash, "/sbin/iwconfig $nName 2>/dev/null");
        my @iwData = SYSMON_execute($hash, "/sbin/iwconfig $nDef 2>/dev/null");
        foreach (@iwData) {
          next unless ($_);
          if($_=~ m/Bit\sRate+(=|:)*(\S*)/) {
            $speed=$2;
          }
        }
      }
      elsif (1 eq SYSMON_execute($hash, "[ -f /sys/class/net/$nName/speed ] && echo 1 || echo 0")) {
        $speed = SYSMON_execute($hash, "cat /sys/class/net/$nName/speed 2>/dev/null");
      }
      else {
        $speed = "not available";
      }
      if(defined($speed)) {
      	 $map->{$nName.SPEED_SUFFIX} = $speed;
      }
    }
  } else {
    #Log 3, "SYSMON>>>>>>>>>>>>>>>>> NOK ";
    #Log 3, "SYSMON>>>>>>>>>>>>>>>>> >>> ".$nName;
    $map->{$nName} = "not available";
    $map->{$nName.DIFF_SUFFIX} = "not available";
  }

  return $map;
}

#------------------------------------------------------------------------------
# Liefert Informationen, ob WLAN an oder aus ist (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBWLANState($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'network'}) {return $map;}
  
  #SYSMON_Log($hash, 5, "");
  
  $map->{+FB_WLAN_STATE}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r wlan settings/ap_enabled",1);
  
  return $map;
}

#------------------------------------------------------------------------------
# Liefert Informationen, ob WLAN-Gastzugang an oder aus ist (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBWLANGuestState($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'network'}) {return $map;}
  
  #SYSMON_Log($hash, 5, "");
  
  $map->{+FB_WLAN_GUEST_STATE}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r wlan settings/guest_ap_enabled",1);
  
  return $map;
}

#------------------------------------------------------------------------------
# Liefert IP Adresse im Internet (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBInetIP($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'network'}) {return $map;}
  
  $map->{+FB_INET_IP}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r dslstatistic status/ifacestat0/ipaddr");
  
  return $map;
}

#------------------------------------------------------------------------------
# Liefert Status Internet-Verbindung (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBInetConnectionState($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'network'}) {return $map;}
  
  $map->{+FB_INET_STATE}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r dslstatistic status/ifacestat0/connection_status");
  
  return $map;
}

#------------------------------------------------------------------------------
# Liefert Status Klingelsperre (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBNightTimeControl($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbnightctrl'}) {return $map;}
  
  $map->{+FB_N_TIME_CTRL}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r box settings/night_time_control_enabled",1);
  
  return $map;
}

#------------------------------------------------------------------------------
# Liefert Anzahl der nicht abgehoerten Nachrichten auf dem Anrufbeantworter (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBNumNewMessages($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbnewmessages'}) {return $map;}
  
  $map->{+FB_NUM_NEW_MESSAGES}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r tam status/NumNewMessages");
  
  return $map;
}

#------------------------------------------------------------------------------
# Liefert DECT-Temperatur einer FritzBox.
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBDECTTemp($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbdecttemp'}) {return $map;}
  
  $map->{+FB_DECT_TEMP}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r dect status/Temperature");
  
  return $map;
}

#------------------------------------------------------------------------------
# Liefert Liste an der FritzBox bekannter Devices.
# Parameter: HASH
# Return Hash mit Devices
#------------------------------------------------------------------------------
sub SYSMON_getFBLanDeviceList($) {
  my ($hash) = @_;
  
  if(!SYSMON_isFB($hash)) {
    return undef;
  }
  
  my $map;
  
  my $name = $hash->{NAME};
  # ---
  #TODO: SSH
  my $msg = undef;
  my $openedTelnet = 0;
  my $telnet = $hash->{".telnet"};
  #$telnet = undef;
  my $mode = $hash->{MODE};
  # Wenn remote: open connection
  if ($mode eq 'telnet') {
    unless (defined $telnet) {
      SYSMON_Log($hash, 5, "$name: Open single telnet connection");
      $msg = SYSMON_Open_Connection($hash);
      $hash->{helper}{error_msg}=$msg;
      if (!$msg) {
        $openedTelnet = 1;
        $hash->{helper}{error_msg}=undef;
      }
    }
  }
  # ---

  my $count = SYSMON_execute($hash, "ctlmgr_ctl r landevice settings/landevice/count");
  if(defined($count)) {
    for (my $i=0;$i<$count;$i++) { 
      #landevice0/...  
      # ip=192.168.178.12,  mac=00:1F:3F:MM:AA:CC, name=PC-192-168-178-12, manu_name=0,
      # dhcp=0, static_dhcp=0, wlan=0, ethernet=1, active=1, online=0, speed=100,
      # deleteable=2, wakeup=0, source=4096, neighbour_name=, is_double_neighbour_name=0
      # ipv6addrs=, ipv6_ifid=

      my $dev_name   = SYSMON_execute($hash, "ctlmgr_ctl r landevice settings/landevice".$i."/name");
      my $dev_ip     = SYSMON_execute($hash, "ctlmgr_ctl r landevice settings/landevice".$i."/ip");
      my $dev_mac    = SYSMON_execute($hash, "ctlmgr_ctl r landevice settings/landevice".$i."/mac");
      my $dev_active = SYSMON_execute($hash, "ctlmgr_ctl r landevice settings/landevice".$i."/active");
      
      $map->{$dev_name}{id}     = $i;
      $map->{$dev_name}{name}   = $dev_name;
      $map->{$dev_name}{ip}     = $dev_ip;
      $map->{$dev_name}{mac}    = $dev_mac;
      $map->{$dev_name}{active} = $dev_active;
    }
  }
  
  # ---
  # Wenn remote: close connection
  if ($mode eq 'telnet') {
    if($openedTelnet) {
      SYSMON_Log($hash, 5, "$name: Close shared telnet connection");
      SYSMON_Close_Connection( $hash );
    }
  }
  # ---
  
  return $map;
}


# TODO: FritzBox-Infos: Dateien /var/env oder /proc/sys/urlader/environment. 

#------------------------------------------------------------------------------
# Liefert Informationen zu verschiedenen Eigenschaften durch Aufruf von entsprechenden Befehlen
# Parameter: HASH; cmd; Art (Interpretieren als: 1=on/off)
#------------------------------------------------------------------------------
sub SYSMON_acquireInfo_intern($$;$)
{
  my ($hash, $cmd, $art) = @_;
  
  SYSMON_Log($hash, 5, "cmd: ".$cmd);
  
  my $str = SYSMON_execute($hash, $cmd);
  if(defined($str)) {
    $str = trim($str);
  }
  my $ret;
  
  if(!defined($art)) { $art= 0; }

  $ret = $str;
  no warnings;
  if($art == 1) {
    if($str+0 == 1) {
     $ret="on";
    } else {
      if($str+0 == 0) {
        $ret="off";
      } else {
        $ret="unknown";
      }
    }
  }
  use warnings;
  return $ret;
}

sub SYSMON_FBVersionInfo($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbversion'}) {return $map;}
  
  my @ar = SYSMON_execute($hash, "/etc/version --version --date");
  my $data = $ar[0];
  
  my($v, $d, $t) = split(/\s+/, $data);
  
  my $version = "";
  if(defined($v)) { $version = $v; }
  if(defined($d)) { $version.= " ".$d; }
  if(defined($t)) { $version.= " ".$t; }
  
  #if(defined($data[0])) {
  # #Version
  # $version = $data[0];
  #}
  #if(defined($data[1])) {
  # #Date
  # $version = $version." ".$data[1];
  #}
  
  if($version ne "") {
    $map->{+FB_FW_VERSION}=$version;
  }
  
  return $map;
}


#DSL-Downstream und DSL-Upstream abfragen
sub SYSMON_getFBStreamRate($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbdsl'}) {return $map;}
  
  my $ds_rate = SYSMON_execute($hash, "ctlmgr_ctl r sar status/dsl_ds_rate");
  unless($ds_rate) {
    return SYSMON_getFBStreamRate2($hash, $map);
  }
  my $us_rate = SYSMON_execute($hash, "ctlmgr_ctl r sar status/dsl_us_rate");
  
  if($ds_rate ne "" && $us_rate ne "") {
    $map->{+FB_DSL_RATE}="down: ".int($ds_rate)." kBit/s, up: ".int($us_rate)." kBit/s";
  }
  
  return $map;
}

# DSL-Geschwindigkeit mit neuer FritzOS (6.23)
sub SYSMON_getFBStreamRate2($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbdsl'}) {return $map;}
  
  my $ds_rate = SYSMON_execute($hash, "ctlmgr_ctl r dslstatglobal status/in");
  my $us_rate = SYSMON_execute($hash, "ctlmgr_ctl r dslstatglobal status/out");
  
  if(defined($ds_rate) && defined($us_rate) && $ds_rate ne "" && $us_rate ne "") {
    $ds_rate = $ds_rate/1000;
    $us_rate = $us_rate/1000;
    $map->{+FB_DSL_RATE}="down: ".int($ds_rate)." kBit/s, up: ".int($us_rate)." kBit/s";
  }
  
  return $map;
}

# Ausrechnet aus der Zahl der Sekunden Anzeige in Tagen:Stunden:Minuten:Sekunden.
sub SYSMON_sec2Dauer($){
  my ($t) = @_;
  my $d = int($t/86400);
  my $r = $t-($d*86400);
  my $h = int($r/3600);
     $r = $r - ($h*3600);
  my $m = int($r/60);
  my $s = $r - $m*60;
  return sprintf("%02d Tage %02d Std. %02d Min. %02d Sec.",$d,$h,$m,$s);
}

#Sync-Zeit mit Vermittlungsstelle abfragen
sub SYSMON_getFBSyncTime($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbdsl'}) {return $map;}
  
  my $data = SYSMON_execute($hash, "ctlmgr_ctl r sar status/modem_ShowtimeSecs");
  unless($data) {
    return SYSMON_getFBSyncTime2($hash, $map);
  }
  
  if($data ne "") {
    my $idata = int($data);
    $map->{+FB_DSL_SYNCTIME}=SYSMON_sec2Dauer($idata);
  }
  
  return $map;
}

#Sync-Zeit mit Vermittlungsstelle abfragen mit neuer FritzOS (6.23)
sub SYSMON_getFBSyncTime2($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbdsl'}) {return $map;}
  
  my $data = SYSMON_execute($hash, "ctlmgr_ctl r dslstatistic status/ifacestat0/connect_time");
  
  if(defined($data) && $data ne "") {
    $map->{+FB_DSL_SYNCTIME}=$data;
  }
  
  return $map;
}

#Uebertragungsfehler abfragen (nicht behebbar und behebbar)
sub SYSMON_getFBCRCFEC($$) {
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'fbdsl'}) {return $map;}
  
  my $ds_crc = SYSMON_execute($hash, "ctlmgr_ctl r sar status/ds_crc_per15min");
  my $us_crc = SYSMON_execute($hash, "ctlmgr_ctl r sar status/us_crc_per15min");
  
  my $ds_fec = SYSMON_execute($hash, "ctlmgr_ctl r sar status/ds_fec_per15min");
  my $us_fec = SYSMON_execute($hash, "ctlmgr_ctl r sar status/us_fec_per15min");  
  
  if(defined($ds_crc) && $ds_crc ne "") {
    # FB_DSL_CRC_15
    $map->{+FB_DSL_CRC_15}="down: ".int($ds_crc)." up: ".int($us_crc);
  }
  if(defined($ds_fec) && $ds_fec ne "") {
    # FB_DSL_FEC_15
    $map->{+FB_DSL_FEC_15}="down: ".int($ds_fec)." up: ".int($us_fec);
  }
  
  return $map;
}

#------------------------------------------------------------------------------
# Systemparameter als HTML-Tabelle ausgeben
# Parameter: Name des SYSMON-Geraetes (muss existieren, kann auch anderer Modul genutzt werden), dessen Daten zur Anzeige gebracht werden sollen.
# (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix[:FormatString]]],...)
# Beispiel: define sysv weblink htmlCode {SYSMON_ShowValuesHTML('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: °C', 'cpu_freq:CPU Frequenz: MHz'))}
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesHTML ($;@)
{
  my ($name, @data) = @_;
  return SYSMON_ShowValuesFmt($name, undef, 1, @data);
}

#------------------------------------------------------------------------------
# Systemparameter als HTML-Tabelle ausgeben. Zusaetzlich wird eine Ueberschrift ausgegeben.
# Parameter: Name des SYSMON-Geraetes (muss existieren, kann auch anderer Modul genutzt werden), dessen Daten zur Anzeige gebracht werden sollen.
# Title: Ueberschrift (Text)
# (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix[:FormatString]]],...)
# Beispiel: define sysv weblink htmlCode {SYSMON_ShowValuesHTML('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: °C', 'cpu_freq:CPU Frequenz: MHz'))}
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesHTMLTitled ($;$@)
{
  my ($name, $title, @data) = @_;
  $title = $attr{$name}{'alias'} unless $title;
  $title = $name unless $title;
  return SYSMON_ShowValuesFmt($name, $title, 1, @data);
}

#------------------------------------------------------------------------------
# Systemparameter im Textformat ausgeben
# Parameter: Name des SYSMON-Geraetes (muss existieren, kann auch anderer Modul genutzt werden), dessen Daten zur Anzeige gebracht werden sollen.
# (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix[:FormatString]]],...)
# Beispiel: define sysv weblink htmlCode {SYSMON_ShowValuesText('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: °C', 'cpu_freq:CPU Frequenz: MHz'))}
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesText ($;@)
{
  my ($name, @data) = @_;
  return SYSMON_ShowValuesFmt($name, undef, 0, @data);
}

#------------------------------------------------------------------------------
# Systemparameter im Textformat ausgeben
# Parameter: Name des SYSMON-Geraetes (muss existieren, kann auch anderer Modul genutzt werden), dessen Daten zur Anzeige gebracht werden sollen.
# Title: Ueberschrift (Text)
# (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix[:FormatString]]],...)
# Beispiel: define sysv weblink htmlCode {SYSMON_ShowValuesText('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: °C', 'cpu_freq:CPU Frequenz: MHz'))}
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesTextTitled ($;$@)
{
  my ($name, $title, @data) = @_;
  $title = $attr{$name}{'alias'} unless $title;
  $title = $name unless $title;
  return SYSMON_ShowValuesFmt($name, $title, 0, @data);
}

#------------------------------------------------------------------------------
# Systemparameter formatiert ausgeben
# Parameter: 
#   Name des SYSMON-Geraetes (muss existieren), dessen Daten zur Anzeige gebracht werden sollen.
#   Title: Ueberschrift
#   Format: 0 = Text, 1 = HTML
#   (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix[:FormatString]]],...)
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesFmt ($$$;@)
{
  my ($name, $title, $format, @data) = @_;
    
  if($format != 0 && $format != 1) {
    return "unknown output format\r\n";
  }
    
  my $hash = $main::defs{$name};
      
  # nur, wenn es sich um eine SYSMON Instanz handelt
  if($hash->{TYPE} eq 'SYSMON') {  
    SYSMON_updateCurrentReadingsMap($hash);
  }
  #Log 3, "SYSMON $>name, @data<";
  my @dataDescription = @data;
  if(scalar(@data)<=0) {
    # Array mit anzuzeigenden Parametern (Prefix, Name (in Map), Postfix)
    my $deg = "°";
    if($format == 1) {
      $deg = "&deg;";
    }
    # bei der Benutzung mit CloneDummies ist $cur_readings_map nicht unbedingt definiert
    @dataDescription = (DATE,
                        #CPU_TEMP.":".$hash->{helper}{cur_readings_map}->{+CPU_TEMP}.": ".$deg."C", 
                        CPU_TEMP.":"."CPU temperature".": ".$deg."C".":%.1f", 
                        #CPU_FREQ.":".$hash->{helper}{cur_readings_map}->{+CPU_FREQ}.": "."MHz", 
                        CPU_FREQ.":"."CPU frequency".": "."MHz", 
                        CPU_MODEL_NAME, CPU_BOGOMIPS,
                        UPTIME_TEXT, FHEMUPTIME_TEXT, LOADAVG, RAM, SWAP, 
                        "power_ac_text", "power_usb_text", "power_battery_text");

    # network-interfaces
    my $networks = AttrVal($name, "network-interfaces", undef);
    if(defined $networks) {
      my @networks_list = split(/,\s*/, trim($networks));
      foreach (@networks_list) {
        my($nName, $nDef, $nComment) = split(/:/, $_);
        push(@dataDescription, $nName);
      }
    }
    
    # named filesystems
    my $filesystems = AttrVal($name, "filesystems", undef);
    if(defined $filesystems) {
      my @filesystem_list = split(/,\s*/, trim($filesystems));
      foreach (@filesystem_list) {
        my($fName, $fDef, $fComment) = split(/:/, $_);
        push(@dataDescription, $fName);
      }
    }   

    # User defined
    my $userdefined = AttrVal($name, "user-defined", undef);
    if(defined $userdefined) {
      my @userdefined_list = split(/,\s*/, trim($userdefined));
      foreach (@userdefined_list) {
         # <readingName>:<Interval_Minutes>:<Comment>:<Cmd>
         my($uName, $uInterval, $uComment, $uCmd) = split(/:/, $_);
         push(@dataDescription, $uName);
      }
    }
  }
  
  #TODO: UserDefinedFn?
  
  my $map;
  if($hash->{TYPE} eq 'SYSMON') {  
    $map = SYSMON_obtainParameters($hash, 1);
  } else {
    # Wenn nicht SYSMON, dann versuchen, die Daten aus den Readings auszulesen
    #$map = SYSMON_obtainReadings($hash);
    foreach my $rname (keys %{$hash->{READINGS}}) {
      my $rval=$hash->{READINGS}->{$rname}->{VAL};
      $map->{$rname}=$rval;
    }
  }

  my $div_class="sysmon";

  my $htmlcode;
  if($format == 1) {
    $htmlcode = "<div  class='".$div_class."'><table>";
  } else {
    if($format == 0) {
      $htmlcode = "";
    }
  }
  
  if(defined $title) {
    if($format == 1) {
      $htmlcode .= "<tr><td valign='top' colspan='2'>".$title."</td></tr>";
    } else {
      if($format == 0) {
        $htmlcode .= sprintf("%s\r\n", $title);
      }
    }
  }
  
  # oben definierte Werte anzeigen
  foreach (@dataDescription) {
    my($rName, $rComment, $rPostfix, $fmtStr) = split(/:/, $_);
    if(defined $rName) {
      if(!defined $rComment) {
        $rComment = $hash->{helper}{cur_readings_map}->{$rName};
      }
      my $rVal = $map->{$rName};
      if(!defined $rVal) {
        # ggf. userReadings verarbeiten
        $rVal = ReadingsVal($name,$rName,undef);
      }
      if($rName eq DATE) {
        # Datum anzeigen
        $rVal = strftime("%d.%m.%Y %H:%M:%S", localtime());
      }
      if(!defined $rPostfix) { $rPostfix = ""; }
      if(defined $rVal) {
        if(defined($fmtStr)) {
          $rVal = sprintf($fmtStr,$rVal);
        }
        if($format == 1) {
          $htmlcode .= "<tr><td valign='top'>".$rComment.":&nbsp;</td><td>".$rVal.$rPostfix."</td></tr>";
        } else {
          if($format == 0) {
            $htmlcode .= sprintf("%-24s: %s%s\r\n", $rComment, $rVal,$rPostfix);
          }
        }
      }
    }
  }
  
  # nur Default (also alles anzeigen)
  if(scalar(@data)<=0) {
    # File systems
    foreach my $aName (sort keys %{$map}) {
      if(defined ($aName) && index($aName, FS_PREFIX) == 0) {
        $aName =~ /^~ (.+)/;
        if($format == 1) {
          $htmlcode .= "<tr><td valign='top'>File System: ".$1."&nbsp;</td><td>".$map->{$aName}."</td></tr>";
        } else {
          if($format == 0) {
            $htmlcode .= sprintf("%-24s: %s\r\n", "File System: ".$1,$map->{$aName});
          }
        }
      }
    }
  }

  if($format == 1) {
    $htmlcode .= "</table></div><br>";
  } else {
    if($format == 0) {
      $htmlcode .= "";
    }
  }

  return $htmlcode;
}

#sub SYSMON_first($) {
# my (@d) = @_;
# return @d[0];
# 
# #my ($d) = @_;
# #
# #return undef unless defined $d;
# 
# ##return ref ($d)." - ".ref(\$d);
# #if (ref $d eq "ARRAY") {
# #   return @{$d}[0];
# #} else {
# #  return $d;
# #}
#}
#
#sub SYSMON_last($) {
# my (@d) = @_;
# 
# return undef unless defined @d;
# 
# return @d[-1];
# 
# #return ref ($d)." - ".ref(\$d);
# #if (ref $d eq "ARRAY") {
# #   return @{$d}[-1];
# #} else {
# #  return $d;
# #}
#}

#my $proc_fs = undef;
sub
SYSMON_isProcFS($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{proc_fs}) {
    $hash->{helper}{proc_fs} = int(SYSMON_execute($hash, "[ -d /proc/ ] && echo 1 || echo 0"));
  }

  return $hash->{helper}{proc_fs};
}

#my $sys_cpu_temp_rpi = undef;
sub
SYSMON_isCPUTempRPi($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{sys_cpu_temp_rpi}) {
    $hash->{helper}{sys_cpu_temp_rpi} = int(SYSMON_execute($hash, "[ -f /sys/class/thermal/thermal_zone0/temp ] && echo 1 || echo 0"));
  }

  return $hash->{helper}{sys_cpu_temp_rpi};
}

#my $sys_cpu_temp_bbb = undef;
sub
SYSMON_isCPUTempBBB($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{sys_cpu_temp_bbb}) {
    $hash->{helper}{sys_cpu_temp_bbb} = int(SYSMON_execute($hash, "[ -f /sys/class/hwmon/hwmon0/device/temp1_input ] && echo 1 || echo 0"));
  }

  return $hash->{helper}{sys_cpu_temp_bbb};
}

#my $sys_cpu_freq_rpi_bbb = undef;
sub
SYSMON_isCPUFreqRPiBBB($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{sys_cpu_freq_rpi_bbb}) {
    #$hash->{helper}{sys_cpu_freq_rpi_bbb} = int(SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ] && echo 1 || echo 0"));
    # Diese abenteuerliche Konstruktion ist noetig, weil bei zu langen Zeilen ueber Telnet der Rest der Zeile als erstes Element kommt
    my @t = SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ] && echo 1 || echo 0");
    if(@t) {
      $hash->{helper}{sys_cpu_freq_rpi_bbb} = int($t[-1]);
    }
  }

  return $hash->{helper}{sys_cpu_freq_rpi_bbb};
}

# DUMMY
sub SYSMON_isCPUTempFB($) {
  my ($hash) = @_;
  return SYSMON_isFB($hash);
}

sub
SYSMON_isCPUTemp_X($$) {
  my ($hash, $cpuNum) = @_;
  
  if(!defined $hash->{helper}{"sys_cpu".$cpuNum."_temp"}) {
  	#/sys/class/hwmon/hwmon0/device/hwmon/hwmon0/temp2_input
    #$hash->{helper}{"sys_cpu".$cpuNum."_temp"} = int(SYSMON_execute($hash, "[ -f /sys/class/hwmon/hwmon0/device/hwmon/hwmon0/temp".$cpuNum."_input ] && echo 1 || echo 0"));
    # s. o. 
    my @t = SYSMON_execute($hash, "[ -f /sys/class/hwmon/hwmon0/device/hwmon/hwmon0/temp".($cpuNum+1)."_input ] && echo 1 || echo 0");
    if(@t) {
      $hash->{helper}{"sys_cpu".$cpuNum."_temp"} = int($t[-1]);
    }
  }

  return $hash->{helper}{"sys_cpu".$cpuNum."_temp"};
}

sub
SYSMON_isCPUXFreq($$) {
  my ($hash, $cpuNum) = @_;
  if(!defined $hash->{helper}{"sys_cpu".$cpuNum."_freq"}) {
    #$hash->{helper}{"sys_cpu".$cpuNum."_freq"} = int(SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/cpu".$cpuNum."/cpufreq/scaling_cur_freq ] && echo 1 || echo 0"));
    # s. o. 
    my @t = SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/cpu".$cpuNum."/cpufreq/scaling_cur_freq ] && echo 1 || echo 0");
    if(@t) {
      $hash->{helper}{"sys_cpu".$cpuNum."_freq"} = int($t[-1]);
    }
  }

  return $hash->{helper}{"sys_cpu".$cpuNum."_freq"};
}

#my $sys_fb = undef;
sub
SYSMON_isFB($) {
  my ($hash) = @_;
  if(!defined ($hash->{helper}{sys_fb})) {
    $hash->{helper}{sys_fb} = int(SYSMON_execute($hash, "[ -f /usr/bin/ctlmgr_ctl ] && echo 1 || echo 0"));
  }
  return $hash->{helper}{sys_fb};
}

#-Power-------
#my $sys_power_ac = undef;
sub
SYSMON_isSysPowerAc($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{sys_power_ac}) {
    $hash->{helper}{sys_power_ac} = int(SYSMON_execute($hash, "[ -f /sys/class/power_supply/ac/online ] && echo 1 || echo 0"));
  }

  return $hash->{helper}{sys_power_ac};
}

#my $sys_power_usb = undef;
sub
SYSMON_isSysPowerUsb($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{sys_power_usb}) {
    $hash->{helper}{sys_power_usb} = int(SYSMON_execute($hash, "[ -f /sys/class/power_supply/usb/online ] && echo 1 || echo 0"));
  }

  return $hash->{helper}{sys_power_usb};
}

#my $sys_power_bat = undef;
sub
SYSMON_isSysPowerBat($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{sys_power_bat}) {
    $hash->{helper}{sys_power_bat} = int(SYSMON_execute($hash, "[ -f /sys/class/power_supply/battery/online ] && echo 1 || echo 0"));
  }

  return $hash->{helper}{sys_power_bat};
}

#my $sys_cpu_num = undef;
sub
SYSMON_isSysCpuNum($) {
  my ($hash) = @_;
  if(!defined $hash->{helper}{sys_cpu_num}) {
    $hash->{helper}{sys_cpu_num} = int(SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/kernel_max ] && echo 1 || echo 0"));
  }

  return $hash->{helper}{sys_cpu_num};
}

sub
SYSMON_isNetStatClass($$) {
  my ($hash, $nName) = @_;
  if(!defined $hash->{helper}{'net_'.$nName.'_stat_class'}) {
    $hash->{helper}{'net_'.$nName.'_stat_class'} = int(SYSMON_execute($hash, "[ -f /sys/class/net/$nName/statistics/rx_bytes ] && echo 1 || echo 0"));
    # /sys/class/net/$nName/statistics/tx_bytes
  }

  return $hash->{helper}{'net_'.$nName.'_stat_class'};
}

sub SYSMON_PowerAcInfo($$) {
  #online, present, current_now (/1000 =>mA), voltage_now (/1000000 => V)
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'powerinfo'}) {return $map;}
  
  my $type="ac";
  my $base = "cat /sys/class/power_supply/".$type."/";
   
  my $d_online_t = SYSMON_execute($hash, $base."online");
  if($d_online_t) {
    my $d_online = trim($d_online_t);
    my $d_present = trim(SYSMON_execute($hash, $base."present 2>/dev/null"));
    my $d_current = SYSMON_execute($hash, $base."current_now 2>/dev/null");
    if(defined $d_current) {$d_current/=1000;} else {return $map;}
    my $d_voltage = SYSMON_execute($hash, $base."voltage_now 2>/dev/null");
    if(defined $d_voltage) {$d_voltage/=1000000;} else {return $map;}
    
    #$map->{"power_".$type."_online"}=$d_online;
    #$map->{"power_".$type."_present"}=$d_present;
    #$map->{"power_".$type."_current"}=$d_current;
    #$map->{"power_".$type."_voltage"}=$d_voltage;
    $map->{"power_".$type."_stat"}="$d_online $d_present $d_voltage $d_current";
    $map->{"power_".$type."_text"}=$type.": ".(($d_present eq "1") ? "present" : "absent")." / ".($d_online eq "1" ? "online" : "offline").", voltage: ".$d_voltage." V, current: ".$d_current." mA, ".(int(($d_voltage*$d_current/100+0.5))/10)." W";
  }
  return $map;
}

sub SYSMON_PowerUsbInfo($$) {
  #online, present, current_now (/1000 =>mA), voltage_now (/1000000 => V)
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'powerinfo'}) {return $map;}
  
  my $type="usb";
  my $base = "cat /sys/class/power_supply/".$type."/";
    
  my $d_online = trim(SYSMON_execute($hash, $base."online"));
  my $d_present = trim(SYSMON_execute($hash, $base."present 2>/dev/null"));
  my $d_current = SYSMON_execute($hash, $base."current_now 2>/dev/null");
  if(defined $d_current) {$d_current/=1000;} else {return $map;}
  my $d_voltage = SYSMON_execute($hash, $base."voltage_now 2>/dev/null");
  if(defined $d_voltage) {$d_voltage/=1000000;} else {return $map;}
  
  #$map->{"power_".$type."_online"}=$d_online;
  #$map->{"power_".$type."_present"}=$d_present;
  #$map->{"power_".$type."_current"}=$d_current;
  #$map->{"power_".$type."_voltage"}=$d_voltage;
  $map->{"power_".$type."_stat"}="$d_online $d_present $d_voltage $d_current";
  $map->{"power_".$type."_text"}=$type.": ".(($d_present eq "1") ? "present" : "absent")." / ".($d_online eq "1" ? "online" : "offline").", voltage: ".$d_voltage." V, current: ".$d_current." mA, ".(int(($d_voltage*$d_current/100+0.5))/10)." W";
  
  return $map;
}

sub SYSMON_PowerBatInfo($$) {
  #online, present, current_now (/1000 =>mA), voltage_now (/1000000 => V)
  my ($hash, $map) = @_;
  
  if($hash->{helper}->{excludes}{'powerinfo'}) {return $map;}
  
  my $type="battery";
  my $base = "cat /sys/class/power_supply/".$type."/";
    
  my $d_online = trim(SYSMON_execute($hash, $base."online"));
  my $d_present = trim(SYSMON_execute($hash, $base."present 2>/dev/null"));
  my $d_current = SYSMON_execute($hash, $base."current_now 2>/dev/null");
  if(defined $d_current) {$d_current/=1000;} else {return $map;}
  my $d_voltage = SYSMON_execute($hash, $base."voltage_now 2>/dev/null");
  if(defined $d_voltage) {$d_voltage/=1000000;} else {return $map;}
  
  my $d_capacity = trim(SYSMON_execute($hash, $base."capacity 2>/dev/null"));
  if($d_present ne "1") {
    $d_capacity = "0";
  }
  #$map->{"power_".$type."_online"}=$d_online;
  #$map->{"power_".$type."_present"}=$d_present;
  #$map->{"power_".$type."_current"}=$d_current;
  #$map->{"power_".$type."_voltage"}=$d_voltage;
  $map->{"power_".$type."_stat"}="$d_online $d_present $d_voltage $d_current $d_capacity";
  $map->{"power_".$type."_text"}=$type.": ".(($d_present eq "1") ? "present" : "absent")." / ".($d_online eq "1" ? "online" : "offline").", voltage: ".$d_voltage." V, current: ".$d_current." mA, ".(int(($d_voltage*$d_current/100+0.5))/10)." W, "."capacity: ".$d_capacity." %";
  
  if($d_present eq "1") {
    # Zusaetzlich: technology, capacity, status, health, temp (/10 => °C)
    my $d_technology = trim(SYSMON_execute($hash, $base."technology 2>/dev/null"));
    my $d_status = trim(SYSMON_execute($hash, $base."status 2>/dev/null"));
    my $d_health = trim(SYSMON_execute($hash, $base."health 2>/dev/null"));
    my $d_energy_full_design = trim(SYSMON_execute($hash, $base."energy_full_design 2>/dev/null"));
    
    $map->{"power_".$type."_info"}=$type." info: ".$d_technology." , capacity: ".$d_capacity." %, status: ".$d_status." , health: ".$d_health." , total capacity: ".$d_energy_full_design." mAh";
    
    # ggf. noch irgendwann: model_name, voltage_max_design, voltage_min_design
  } else {
    $map->{"power_".$type."_info"}=$type." info: n/a , capacity: n/a %, status: n/a , health: n/a , total capacity: n/a mAh";
  }
  
  return $map;
}
#-------------

sub SYSMON_execute($$)
{
  my ($hash, $cmd) = @_;
  return SYSMON_Exec($hash, $cmd);
  #return qx($cmd);
}

#------------------------------------------------------------------------------

# checks and stores password used for remote connection
sub SYSMON_storePassword($$)
{
    my ($hash, $password) = @_;
     
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    
    my $enc_pwd = "";
    
    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    
    my $err = setKeyValue($index, $enc_pwd);
    $hash->{helper}{error_msg}=$err;
    return "error while saving the password - $err" if(defined($err));
    
    return "password successfully saved";
}

# read password
sub SYSMON_readPassword($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
   my $key = getUniqueId().$index;

   my ($password, $err);

   SYSMON_Log($hash, 5, "Read password from file");
   ($err, $password) = getKeyValue($index);

   if(defined($err))
   {
      SYSMON_Log($hash, 3, "unable to read password from file: $err");
      return undef;
   }  

   if(defined($password))
   {
      if(eval "use Digest::MD5;1")
      {
         $key = Digest::MD5::md5_hex(unpack "H*", $key);
         $key .= Digest::MD5::md5_hex($key);
      }

      my $dec_pwd = '';
     
      for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g))
      {
         my $decode=chop($key);
         $dec_pwd.=chr(ord($char)^ord($decode));
         $key=$decode.$key;
      }
     
      return $dec_pwd;
   }
   else
   {
      SYSMON_Log($hash, 5, "No password in file");
      return undef;
   }
}

# Opens a Telnet Connection to an external Machine
############################################
sub SYSMON_Open_Connection($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $msg;
 
   my $mode = $hash->{MODE};#AttrVal( $name, 'mode', 'local');
   if ($mode eq 'local') {
     return undef;
   }

   if($missingModulRemote) {
     $msg="Error: Perl modul ".$missingModulRemote."is missing on this system. Please install before using this modul.";
     SYSMON_Log($hash, 3, $msg);
     return $msg;
   }

   my $host = $hash->{HOST};#AttrVal( $name, "remote_host", undef );
  
   if(!defined $host) {
     $msg="Error: no remote host provided";
     SYSMON_Log($hash, 3, $msg);
     return $msg unless defined $host;
   }
   my $port = $hash->{PORT};#AttrVal( $name, "remote_port", 23 );
   my $pwd = SYSMON_readPassword($hash);#AttrVal( $name, "remote_password", undef );
   my $user = $hash->{USER};#AttrVal( $name, "remote_user", "" );
   $user="" unless defined($user);
  #test
  #$pwd="dummy";
  #test
   my $before;
   my $match;
   
   #if(!defined($pwd)) {
   #  my $pwdFile = AttrVal( $name, "pwdFile", undef);
   #  if(defined($pwdFile)) {
   #    SYSMON_Log($hash, 5, "Open password file '$pwdFile' to extract password");
   #    if (open(IN, "<" . $pwdFile)) {
   #      $pwd = <IN>;
   #      close(IN);
   #      SYSMON_Log($hash, 5, "Close password file");
   #    } else {
   #      $msg = "Error: Cannot open password file '$pwdFile': $!";
   #      SYSMON_Log($hash, 2, $msg);
   #      return $msg;
   #    }
   #  }
   #}
   
   if(!defined($pwd)) {
     $msg="Error: no password provided";
     SYSMON_Log($hash, 3, $msg);
     return $msg unless defined $pwd;
   }
 
   SYSMON_Log($hash, 5, "Open Telnet connection to $host:$port");
   my $timeout = AttrVal( $name, "telnet-time-out", "10");
   my $t_prompt=AttrVal($name,'telnet-prompt-regx','(#|\$)\s*$');
   #my $telnet = new Net::Telnet ( Host=>$host, Port => $port, Timeout=>$timeout, Errmode=>'return', Prompt=>'/(#|\$) $/');
   my $telnet = new Net::Telnet ( Host=>$host, Port => $port, Timeout=>$timeout, Errmode=>'return', Prompt=>'/'.$t_prompt.'/');
   if (!$telnet) {
      $msg = "Could not open telnet connection to $host:$port";
      SYSMON_Log($hash, 2, $msg);
      $telnet = undef;
      $hash->{".telnet"}=$telnet;
      return $msg;
   }
   $hash->{".telnet"}=$telnet;

   SYSMON_Log($hash, 5, "Wait for user or password prompt.");
   unless ( ($before,$match) = $telnet->waitfor('/(user|login|password): $/i') )
   {
      $msg = "Telnet error while waiting for user or password prompt: ".$telnet->errmsg;
      SYSMON_Log($hash, 2, $msg);
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   if ( $match =~ /(user|login): / && $user eq "")
   {
      $msg = "Telnet login requires user name but attribute 'telnetUser' not defined";
      SYSMON_Log($hash, 2, $msg);
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   elsif ( $match =~ /(user|login): /)
   {
      SYSMON_Log($hash, 5, "Entering user name");
      $telnet->print( $user );

      SYSMON_Log($hash, 5, "Wait for password prompt");
      unless ($telnet->waitfor( '/password: $/i' ))
      {
         $msg = "Telnet error while waiting for password prompt: ".$telnet->errmsg;
         SYSMON_Log($hash, 2, $msg);
         $telnet->close;
         $telnet = undef;
         return $msg;
      }
   }
   elsif ( $match eq "password: " && $user ne "")
   {
      SYSMON_Log($hash, 3, "remote user was defined but telnet login did not prompt for user name.");
   }

   SYSMON_Log($hash, 5, "Entering password");
   $telnet->print( $pwd );

   SYSMON_Log($hash, 5, "Wait for command prompt");
   my $tlogin_prompt=AttrVal($name,'telnet-login-prompt-regx','(#|\$|>)\s*$|Login failed.');
   #unless ( ($before,$match) = $telnet->waitfor( '/# $|Login failed./i' ))
   unless ( ($before,$match) = $telnet->waitfor( '/'.$tlogin_prompt.'/i' ))
   {
      $msg = "Telnet error while waiting for command prompt: ".$telnet->errmsg;
      SYSMON_Log($hash, 2, $msg);
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   elsif ( $match eq "Login failed.")
   {
      $msg = "Telnet error: Login failed. Wrong password.";
      SYSMON_Log($hash, 2, $msg);
      $telnet->close;
      $telnet = undef;
      return $msg;
   }
   #SYSMON_Log($hash, 2, "Prompt: ".Dumper($before)." > ".$match);
   
   # Promptzeile erkenen
   if(!($hash->{helper}{recognized_prompt})) {
     my @prompt = SYSMON_Exec_Remote($hash, '');
     if(scalar(@prompt) == 1) {
       $hash->{helper}{recognized_prompt}=$prompt[0];
     }
   }
   #SYSMON_Log($hash, 2, "Prompt: '".Dumper(@retVal)."'");
   
   return undef;
} # end SYSMON_Open_Connection

   
# Closes a Telnet Connection to an external Machine
############################################
sub SYSMON_Close_Connection($)
{
   my ($hash) = @_;
   
   my $name = $hash->{NAME};
   my $mode = $hash->{MODE};#AttrVal( $name, 'mode', 'local');
   if (!defined($mode) || $mode eq 'local') {
     return undef;
   }
   
   my $telnet = $hash->{".telnet"};
   if (defined $telnet)
   {
      SYSMON_Log ($hash, 5, "Close Telnet connection");
      $telnet->close;
      $telnet = undef;
      $hash->{".telnet"}=$telnet;
   }
   else
   {
      SYSMON_Log($hash, 1, "Cannot close an undefined Telnet connection");
   }
} # end SYSMON_Close_Connection

# Executed the command on the remote Shell
############################################
sub SYSMON_Exec($$;$)
{
   my ($hash, $cmd,$is_arr) = @_;
   my $openedTelnet = 0;
   my $telnet = $hash->{".telnet"};
   
   my $name = $hash->{NAME};
   my $mode = $hash->{MODE};#AttrVal( $name, 'mode', 'local');
   if ($mode eq 'telnet') {
      unless (defined $telnet)
      {
        SYSMON_Log($hash, 5, "$name: Open single telnet connection");
        my $msg = SYSMON_Open_Connection($hash);
        $hash->{helper}{error_msg}=$msg;
        if ($msg) {
          return undef;
        }
        $openedTelnet = 1;
        $hash->{helper}{error_msg}=undef;
      }
      my @retVal = SYSMON_Exec_Remote($hash, $cmd);
      
      if($openedTelnet) {
        SYSMON_Log($hash, 5, "$name: Close single telnet connection");
        SYSMON_Close_Connection( $hash );
      }

      #Prompt-Zeile entfernen, falls vorhanden
      my $recognized_prompt = $hash->{helper}{recognized_prompt};
      if(defined($recognized_prompt)) {
        if(scalar(@retVal)>=1) {
          if($retVal[-1] eq $recognized_prompt) {
            SYSMON_Log ($hash, 5, "remove prompt: ".$retVal[-1]."'");
            splice @retVal, -1, 1;# $retVal[-1];
          }
        }
      }
      
      # Arrays als solche zurueckgeben
      #if($is_arr && scalar(@retVal)>1) {
      if(scalar(@retVal)>1) {
        SYSMON_Log ($hash, 5, "Result A: '".Dumper(@retVal)."'");
        return @retVal; 
      }
      # Einzeiler als normale Scalars
      my $line = $retVal[0];
      if(defined($line)) {
        chomp $line;
        SYSMON_Log ($hash, 5, "Result L: '$line'");
      } else {
        SYSMON_Log ($hash, 5, "Result undef");
      }
      return $line;
      #return $retVal;
   } else {
      if ($mode eq 'ssh') {
        return SYSMON_Exec_Ssh($hash, $cmd);
      } else {
      return SYSMON_Exec_Local($hash, $cmd);
   }
   }

}

sub MYTEST() {
  my @output=(
  '',
'[~] ',
'',
'[~] # ',
'',
'',
'',
'          Interrupt:16 Memory:c0100000-c0120000 ',
'',
'          RX bytes:483322579219 (450.1 GiB)  TX bytes:3757348645531 (3.4 TiB)',
'',
'          collisions:0 txqueuelen:1000 ',
'',
'          TX packets:3656315540 errors:0 dropped:0 overruns:0 carrier:0',
'',
'          RX packets:2817622543 errors:8 dropped:265294 overruns:0 frame:8',
'',
'          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1',
'',
'          inet addr:192.168.178.80  Bcast:192.168.178.255  Mask:255.255.255.0',
'',
'eth0      Link encap:Ethernet  HWaddr 00:08:9B:D3:8D:9E'
  );
  @output = reverse(@output);
  for (my $i=0;$i<scalar(@output);$i++) {
     if($output[$i]=~ /^\[~\]/) {undef ($output[$i]);}
   }
   @output = grep{ defined($_) && trim($_) ne '' }@output;
   return Dumper(@output);
}

# Executed the command via Telnet
sub ############################################
SYSMON_Exec_Remote($$)
{
   my ($hash, $cmd) = @_;
   my @output;
   my $result;

   my $telnet = $hash->{".telnet"};

   SYSMON_Log($hash, 5, "Execute '".$cmd."'");
   @output=$telnet->cmd($cmd);
   #SYSMON_Log($hash, 5, "Result '".Dumper(@output)."'"); # TODO: remove

   # Sonderlocke fuer QNAP: letzten Zeilen mit "[~] " am Anfang entfernen
   #while((scalar(@output)>0) && ($output[-1]=~ /^\[~\]/)) {
   #  SYSMON_Log ($hash, 5, "Remove line: '".$output[-1]."'");
   #  splice @output, -1, 1;
   #}
   for (my $i=0;$i<scalar(@output);$i++) {
     #SYSMON_Log($hash, 5, "Result >>> Line >>> '".$output[$i]."'"); # TODO: remove
     if($output[$i]=~ /^\[~\]/) {undef ($output[$i]);}
   }
   #SYSMON_Log($hash, 5, "Result >>> vgrep >>>'".Dumper(@output)."'"); # TODO: remove
   @output = grep{ defined($_) && trim($_) ne '' }@output;
   #SYSMON_Log($hash, 5, "Result >>> ngrep >>>'".Dumper(@output)."'"); # TODO: remove
   
   return @output;
   ## Arrays als solche zurueckgeben
   #if(scalar(@output)>1) {
   #  SYSMON_Log ($hash, 5, "Result '".Dumper(@output)."'");
   #  return @output; 
   #}
   ## Einzeiler als normale Scalars
   #my $line = @output[0];
   #chomp $line;
   #SYSMON_Log ($hash, 5, "Result '$line'");
   #return $line;
   
   #$result = $output[0];
   ##chomp $result;
   #my $log = join " ", @output;
   #chomp $log;
   #SYSMON_Log($hash, 5, "Result '$log'");
   #return $result;
}

# Executed the command on the remote Shell
sub ############################################
SYSMON_Exec_Local($$)
{
   my ($hash, $cmd) = @_;
   
   SYSMON_Log($hash, 5, "Execute '".$cmd."'");
   #return qx($cmd);
   my @result = qx($cmd);
   # Arrays als solche zurueckgeben
   if(scalar(@result)>1) {
     SYSMON_Log ($hash, 5, "Result '".Dumper(@result)."'");
     return @result;  
   }
   # Einzeiler als normale Scalars
   my $line = $result[0];
   
   if(defined($line)) {
     chomp $line;
     SYSMON_Log ($hash, 5, "Result '$line'");
   } else {
     SYSMON_Log ($hash, 5, "Result undef");
   }

   return $line;
   
   #chomp $result;
   #SYSMON_Log ($hash, 5, "Result '$result'");
   #return $result;
}

# Executed the command on the remote SSH Shell
sub ############################################
SYSMON_Exec_Ssh($$)
{
   my ($hash, $cmd) = @_;
   
   my $msg;

   my $host = $hash->{HOST};#AttrVal( $name, "remote_host", undef );
   if(!defined $host) {
     $msg="Error: no remote host provided";
     SYSMON_Log($hash, 3, $msg);
     return $msg unless defined $host;
   }
   my $pwd = SYSMON_readPassword($hash);#AttrVal( $name, "remote_password", undef );
   my $t_sshpass = '';
   if(defined($pwd)) {
     #$msg="Error: no passwort provided";
     #SYSMON_Log($hash, 3, $msg);
     #return $msg unless defined $pwd;
     $t_sshpass = 'echo '.$pwd.' | sshpass ';
     #$t_sshpass = 'sshpass -p '.$pwd.' ';
   }
   my $user = $hash->{USER};#AttrVal( $name, "remote_user", "" );
   my $port = $hash->{PORT};#AttrVal( $name, "remote_port", "22" );
   
   SYSMON_Log($hash, 5, "Execute '".$cmd."' by SSH");
   my $p_tmp = '';
   if(!defined($port)) {
     $p_tmp = ' -p '.$port.' ';
   }
   
   my $call = "ssh ".$p_tmp.$user."\@".$host." ".'"'.$cmd.'"';
   SYSMON_Log ($hash, 5, "Call: '".$call."'");
   $call = $t_sshpass.$call;
   
   # $call = $call.' 2>/dev/null';
   
   my @result = qx($call);
   # Arrays als solche zurueckgeben
   if(scalar(@result)>1) {
     SYSMON_Log ($hash, 5, "Result '".Dumper(@result)."'");
     return @result;  
   }
   # Einzeiler als normale Scalars
   my $line = $result[0];
   
   if(defined($line)) {
     chomp $line;
     SYSMON_Log ($hash, 5, "Result '$line'");
   } else {
     SYSMON_Log ($hash, 5, "Result undef");
   }

   return $line;
   
   #chomp $result;
   #SYSMON_Log ($hash, 5, "Result '$result'");
   #return $result;
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Uebersetzt Sekunden (Dauer) in Tage/Stunden/Minuten/Sekunden
#------------------------------------------------------------------------------
sub SYSMON_decode_time_diff($)
{
  my $s = shift;

  my $d = int($s/86400);
  $s -= $d*86400;
  my $h = int($s/3600);
  $s -= $h*3600;
  my $m = int($s/60);
  #$s -= $m*60;
  #return ($d,$h,$m,$s);
  return ($d,$h,$m);
}

#------------------------------------------------------------------------------
# Logging: Funkrionsaufrufe
#   Parameter: HASH, Funktionsname, Message
#------------------------------------------------------------------------------
#sub logF($$$)
#{
# my ($hash, $fname, $msg) = @_;
#  #Log 5, "SYSMON $fname (".$hash->{NAME}."): $msg";
#  Log 5, "SYSMON $fname $msg";
#}

sub SYSMON_Log($$$) {
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/SYSMON_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   $instName="" unless $instName;
   Log3 $hash, $loglevel, "SYSMON $instName: $sub.$xline " . $text;
}

# -----------------------------------------------------------------------------

1;

=pod
=item device
=item summary    provides some statistics about the system
=item summary_DE liefert einige Statistiken ueber das Host-System
=begin html

<!-- ================================ -->
<a name="SYSMON"></a>
<h3>SYSMON</h3>
(en | <a href="commandref_DE.html#SYSMON">de</a>)
<ul>
   This module provides statistics about the system running FHEM server. Furthermore, remote systems can be accessed (Telnet). Only Linux-based systems are supported.
   Some informations are hardware specific and are not available on every platform.
   So far, this module has been tested on the following systems:
   Raspberry Pi (Debian Wheezy), BeagleBone Black, FritzBox 7390, WR703N under OpenWrt, CubieTruck and some others.
   <br><br>
   For more information on a FritzBox check other moduls: <a href="#FRITZBOX">FRITZBOX</a> and <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <br>
   <i>The modul uses the Perl modul 'Net::Telnet' for remote access. Please make sure that this module is installed.</i>
   <br><br>
   <b>Define</b>
   <br><br>
   <code>define &lt;name&gt; SYSMON [MODE[:[USER@]HOST][:PORT]] [&lt;M1&gt;[ &lt;M2&gt;[ &lt;M3&gt;[ &lt;M4&gt;]]]]</code><br>
   <br>
   This statement creates a new SYSMON instance. The parameters M1 to M4 define the refresh interval for various Readings (statistics). The parameters are to be understood as multipliers for the time defined by INTERVAL_BASE. Because this time is fixed at 60 seconds, the Mx-parameter can be considered as time intervals in minutes.<br>
   If one (or more) of the multiplier is set to zero, the corresponding readings is deactivated.
   <br>
   <br>
   The parameters are responsible for updating the readings according to the following scheme:
   <ul>
      <li>M1: (Default: 1)<br>
         cpu_freq, cpu_temp, cpu_temp_avg, loadavg, stat_cpu, stat_cpu_diff, stat_cpu_percent, stat_cpu_text, power readings<br><br>
      </li>
      <li>M2: (Default: M1)<br>
         ram, swap<br>
      </li>
      <li>M3: (Default: M1)<br>
         eth0, eth0_diff, wlan0, wlan0_diff<br><br>
      </li>
      <li>M4: (Default: 10*M1)<br>
         Filesystem informations<br><br>
      </li>
      <li>The following parameters are always updated with the base interval (regardless of the Mx-parameter):<br>
         fhemuptime, fhemuptime_text, idletime, idletime_text, uptime, uptime_text, starttime, starttime_text<br><br>
      </li>
   </ul>
   To query a remote system at least the address (HOST) must be specified. Accompanied by the port and / or user name, if necessary. The password (if needed) has to be defined once with the command 'set password &lt;password&gt;'. For MODE parameter are 'telnet', 'ssh' and 'local' only allowed. 'local' does not require any other parameters and can also be omitted.
   <br>
    For SSH login with password, 'sshpass' must be installed (note: not recommended! Use public key authentication instead).
    For SSH login to work, a manual SSH connection to the remote machine from the FHEM-Acount may need to be done once
    (under whose rights FHEM runs) the fingerprint must be confirmed.
   <br>
   <br>
   <b>Readings:</b>
   <br><br>
   <ul>
      <li>cpu_core_count<br>
         CPU core count
      </li>
      <li>cpu_model_name<br>
         CPU model name
      </li>
      <li>cpu_bogomips<br>
         CPU Speed: BogoMIPS
      </li>
      <li>cpu_freq (and cpu1_freq for dual core systems)<br>
         CPU frequency
      </li>
      <br>
      <li>cpu_temp<br>
         CPU temperature
      </li>
      <br>
      <li>cpu_temp_avg<br>
         Average of the CPU temperature, formed over the last 4 values.
      </li>
      <br>
      <li>fhemuptime<br>
         Time (in seconds) since the start of FHEM server.
      </li>
      <br>
      <li>fhemuptime_text<br>
         Time since the start of the FHEM server: human-readable output (text representation).
      </li>
      <br>
      <li>fhemstarttime<br>
         Start time (in seconds since 1.1.1970 1:00:00) of FHEM server.
      </li>
      <br>
      <li>fhemstarttime_text<br>
         Start time of the FHEM server: human-readable output (text representation).
      </li>
      <br>
      <li>idletime<br>
         Time spent by the system since the start in the idle mode (period of inactivity).
      </li>
      <br>
      <li>idletime_text<br>
         The inactivity time of the system since system start in human readable form.
      </li>
      <br>
      <li>loadavg<br>
         System load (load average): 1 minute, 5 minutes and 15 minutes.
      </li>
      <br>
      <li>ram<br>
         memory usage.
      </li>
      <br>
      <li>swap<br>
         swap usage.
      </li>
      <br>
      <li>uptime<br>
         System uptime.
      </li>
      <br>
      <li>uptime_text<br>
         System uptime (human readable).
      </li>
      <br>
      <li>starttime<br>
         System starttime.
      </li>
      <br>
      <li>starttime_text<br>
         System starttime (human readable).
      </li>
      <br>
      <li>Network statistics<br>
         Statistics for the specified network interface about the data volumes transferred and the difference since the previous measurement.
         <br>
         Examples:<br>
         Amount of the transmitted data via interface eth0.<br>
         <code>eth0: RX: 940.58 MB, TX: 736.19 MB, Total: 1676.77 MB</code><br>
         Change of the amount of the transferred data in relation to the previous call (for eth0).<br>
         <code>eth0_diff: RX: 0.66 MB, TX: 0.06 MB, Total: 0.72 MB</code><br>
         IP and IP v6 adresses
         <code>eth0_ip 192.168.0.15</code><br>
         <code>eth0_ip6 fe85::49:4ff:fe85:f885/64</code><br>
      </li>
      <br>
      <li>Network Speed (if avialable)<br>
         speed of the network connection.
         <br>
         Examples:<br>
         <code>eth0_speed 100</code><br>
      </li>
      <br>
      <li>File system information<br>
         Usage of the desired file systems.<br>
         Example:<br>
         <code>fs_root: Total: 7340 MB, Used: 3573 MB, 52 %, Available: 3425 MB at /</code>
      </li>
      <br>
      <li>CPU utilization<br>
         Information about the utilization of CPUs.<br>
         Example:<br>
         <code>stat_cpu: 10145283 0 2187286 90586051 542691 69393 400342</code><br>
         <code>stat_cpu_diff: 2151 0 1239 2522 10 3 761</code><br>
         <code>stat_cpu_percent: 4.82 0.00 1.81 93.11 0.05 0.00 0.20</code><br>
         <code>stat_cpu_text: user: 32.17 %, nice: 0.00 %, sys: 18.53 %, idle: 37.72 %, io: 0.15 %, irq: 0.04 %, sirq: 11.38 %</code>
      </li>
      <br>
      <li>user defined<br>
         These readings provide output of commands, which are passed to the operating system or delivered by user defined functions.
      </li>
      <br>
      <b>FritzBox specific Readings</b>
      <li>wlan_state<br>
         WLAN state: on/off
      </li>
      <br>
      <li>wlan_guest_state<br>
         GuestWLAN state: on/off
      </li>
      <br>
      <li>internet_ip<br>
         current IP-Adresse
      </li>
      <br>
      <li>internet_state<br>
         state of the Internet connection: connected/disconnected
      </li>
      <br>
      <li>night_time_ctrl<br>
         state night time control (do not disturb): on/off
      </li>
      <br>
      <li>num_new_messages<br>
         Number of new Voice Mail messages
      </li>
      <br>
      <li>fw_version_info<br>
         Information on the installed firmware version: &lt;VersionNum&gt; &lt;creation date&gt; &lt;time&gt;
      </li>
      <br>
      <b>DSL Informations (FritzBox)</b>
      <li>dsl_rate<br>
         Information about the down und up stream rate
      </li>
      <br>
      <li>dsl_synctime<br>
         sync time with DSLAM
      </li>
      <br>
      <li>dsl_crc_15<br>
         number of uncorrectable errors (CRC) for the last 15 minutes
      </li>
      <br>
      <li>dsl_fec_15<br>
         number of correctable errors (FEC) for the last 15 minutes
      </li>
      <br>
      <b>Power Supply Readings</b>
      <li>power_ac_stat<br>
         status information to the AC socket: online (0|1), present (0|1), voltage, current<br>
         Example:<br>
         <code>power_ac_stat: 1 1 4.807 264</code><br>
      </li>
      <br>
      <li>power_ac_text<br>
         human readable status information to the AC socket<br>
         Example:<br>
         <code>power_ac_text ac: present / online, voltage: 4.807 V, current: 264 mA</code><br>
      </li>
      <br>
      <li>power_usb_stat<br>
         status information to the USB socket
      </li>
      <br>
      <li>power_usb_text<br>
         human readable status information to the USB socket
      </li>
      <br>
      <li>power_battery_stat<br>
         status information to the battery (if installed): online (0|1), present (0|1), voltage, current, actual capacity<br>
         Example:<br>
         <code>power_battery_stat: 1 1 4.807 264 100</code><br>
      </li>
      <br>
      <li>power_battery_text<br>
         human readable status information to the battery (if installed)
      </li>
      <br>
      <li>power_battery_info<br>
         human readable additional information to the battery (if installed): technology, capacity, status, health, total capacity<br>
         Example:<br>
         <code>power_battery_info: battery info: Li-Ion , capacity: 100 %, status: Full , health: Good , total capacity: 2100 mAh</code><br>
         The capacity must be defined in script.bin (e.g. ct-hdmi.bin). Parameter name pmu_battery_cap. Convert with bin2fex (bin2fex -> script.fex -> edit -> fex2bin -> script.bin).<br>
      </li>
      <br>
      <li>cpuX_freq_stat<br>
         Frequency statistics for CPU X: minimum,  maximum and average values<br>
         Example:<br>
         <code>cpu0_freq_stat: 100 1000 900</code><br>
      </li>
      <br>
      <li>cpuX_idle_stat<br>
         Idle statistik for CPU X: minimum,  maximum and average values<br>
         Example:<br>
         <code>cpu0_freq_stat: 23.76 94.74 90.75</code><br>
      </li>
      <br>
      <li>cpu[X]_temp_stat<br>
         Temperature statistik for CPU: minimum,  maximum and average values<br>
         Example:<br>
         <code>cpu_temp_stat: 41.00 42.50 42.00</code><br>
      </li>
      <br>
      <li>ram_used_stat<br>
         RAM usage statistics: minimum,  maximum and average values<br>
         Example:<br>
         <code>ram_used_stat: 267.55 1267.75 855.00</code><br>
      </li>
      <br>
      <li>swap_used_stat<br>
         SWAP usage statistics: minimum,  maximum and average values<br>
         Example:<br>
         <code>swap_used_stat: 0 1024.00 250.00</code><br>
      </li>
      <br>
      <br>
   </ul>

   <br>
   <b>Get:</b><br><br>
   <ul>
      <li>interval_base<br>
         Lists the specified polling intervalls.
      </li>
      <br>
      <li>interval_multipliers<br>
         Displays update intervals.
      </li>
      <br>
      <li>list<br>
         Lists all readings.
      </li>
      <br>
      <li>update<br>
         Refreshs all readings.
      </li>
      <br>
      <li>version<br>
         Displays the version of SYSMON module.
      </li>
      <br>
      <li>list_lan_devices<br>
         Displays known LAN Devices (FritzBox only).
      </li>
      <br>
   </ul>
   <br>
   <b>Set:</b><br><br>
   <ul>
      <li>interval_multipliers<br>
         Defines update intervals (as in the definition of the device).
      </li>
      <br>
      <li>clean<br>
         Clears user-definable Readings. After an update (manual or automatic) new readings are generated.<br>
      </li>
      <br>
      <li>clear &lt;reading name&gt;<br>
         Deletes the Reading entry with the given name. After an update this entry is possibly re-created (if defined). This mechanism allows the selective deleting unnecessary custom entries.<br>
      </li>
      <br>
      <li>password &lt;Passwort&gt;<br>
         Specify the password for remote access (usually only necessary once).
      </li>
      <br>
   </ul>
   <br>
   <b>Attributes:</b><br><br>
   <ul>
      <li>filesystems &lt;reading name&gt;[:&lt;mountpoint&gt;[:&lt;comment&gt;]],...<br>
         Specifies the file system to be monitored (a comma-separated list). <br>
         Reading-name is used in the display and logging, the mount point is the basis of the evaluation, comment is relevant to the HTML display (see SYSMON_ShowValuesHTML)<br>
         Examples: <br>
         <code>/boot,/,/media/usb1</code><br>
         <code>fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick</code><br>
      </li>
      <br>
      <li>network-interfaces &lt;name&gt;[:&lt;interface&gt;[:&lt;comment&gt;]],...<br>
         Comma-separated list of network interfaces that are to be monitored. Each entry consists of the Reading-name, the name of the Netwerk adapter and a comment for the HTML output (see SYSMON_ShowValuesHTML). If no colon is used, the value is used simultaneously as a Reading-name and interface name.<br>
         Example <code>ethernet:eth0:Ethernet,wlan:wlan0:WiFi</code><br>
      </li>
      <br>
      <li>user-defined &lt;readingsName&gt;:&lt;Interval_Minutes&gt;:&lt;Comment&gt;:&lt;Cmd&gt;,...<br>
         This comma-separated list defines user defined Readings with the following data: Reading name, refresh interval (in minutes), a Comment, and operating system command.
         <br>The os commands are executed according to the specified Intervals and are noted as Readings with the specified name. Comments are used for the HTML output (see SYSMON_ShowValuesHTML)..
         <br>All parameter parts are required!
         <br>It is important that the specified commands are executed quickly, because at this time the entire FHEM server is blocked!<br>
         If results of the long-running operations required, these should be set up as a CRON job and store results as a text file.<br><br>
         Example: Display of package updates for the operating system:<br>
         cron-Job:<br>
         <code> sudo apt-get update 2>/dev/null >/dev/null</code>
         <code> apt-get upgrade --dry-run| perl -ne '/(\d*)\s[upgraded|aktualisiert]\D*(\d*)\D*install|^ \S+.*/ and print "$1 aktualisierte, $2 neue Pakete"' 2>/dev/null &gt; /opt/fhem/data/updatestatus.txt</code>
         <br>
         <code>uder-defined</code> attribute<br><code>sys_updates:1440:System Aktualisierungen:cat /opt/fhem/data/updatestatus.txt</code><br>
         the number of available updates is daily recorded as 'sys_updates'.
      </li>
      <br>
      <li>user-fn &lt;fn_name&gt;:&lt;interval_minutes&gt;:&lt;reading_name1&gt;:&lt;reading_name2&gt;...[:&lt;reading_nameX&gt;], ...<br>
         List of perl user subroutines.<br>
         As &lt;fn_name&gt; can be used either the name of a Perl subroutine or a Perl expression.
         The perl function gets the device hash as parameter and must provide an array of values.
         These values are taken according to the parameter &lt;reading_nameX&gt; in Readings.<br>
         A Perl expression must be enclosed in curly braces and can use the following parameters: $ HASH (device hash) and $ NAME (device name).
         Return is expected analogous to a Perl subroutine.<br>
         Important! The separation between multiple user functions must be done with a comma AND a space! Within the function definition commas may not be followed by spaces.
      </li>
      <br>
      <li>disable<br>
         Possible values: 0 and 1. '1' means that the update is stopped.
      </li>
      <br>
      <li>telnet-prompt-regx, telnet-login-prompt-regx<br>
         RegExp to detect login and command line prompt. (Only for access via Telnet.)
      </li>
      <br>
      <li>exclude<br>
         Allows to suppress reading certain information. <br>
         supported values: user-defined (s. user-defined und user-fn), cpucount, uptime, fhemuptime,
         loadavg, cputemp, cpufreq, cpuinfo, diskstat, cpustat, ramswap, filesystem, network,
         fbwlan, fbnightctrl, fbnewmessages, fbdecttemp, fbversion, fbdsl, powerinfo
      </li>
      <br>
   </ul>
   <br>
   <b>Plots:</b><br><br>
   <ul>
      predefined gplot files:<br>
      <ul>
         FileLog versions:<br>
         <code>
         SM_RAM.gplot<br>
         SM_CPUTemp.gplot<br>
         SM_FS_root.gplot<br>
         SM_FS_usb1.gplot<br>
         SM_Load.gplot<br>
         SM_Network_eth0.gplot<br>
         SM_Network_eth0t.gplot<br>
         SM_Network_wlan0.gplot<br>
         SM_CPUStat.gplot<br>
         SM_CPUStatSum.gplot<br>
         SM_CPUStatTotal.gplot<br>
         SM_power_ac.gplot<br>
         SM_power_usb.gplot<br>
         SM_power_battery.gplot<br>
         </code>
         DbLog versions:<br>
         <code>
         SM_DB_all.gplot<br>
         SM_DB_CPUFreq.gplot<br>
         SM_DB_CPUTemp.gplot<br>
         SM_DB_Load.gplot<br>
         SM_DB_Network_eth0.gplot<br>
         SM_DB_RAM.gplot<br>
         </code>
      </ul>
   </ul>
   <br>
   <b>HTML output method (see Weblink): SYSMON_ShowValuesHTML(&lt;SYSMON-Instance&gt;[,&lt;Liste&gt;])</b><br><br>
   <ul>
      The module provides a function that returns selected Readings as HTML.<br>
      As a parameter the name of the defined SYSMON device is expected.<br>
      It can also Reading Group, Clone dummy or other modules be used. Their readings are simple used for display. <br>
      The second parameter is optional and specifies a list of readings to be displayed in the format <code>&lt;ReadingName&gt;[:&lt;Comment&gt;[:&lt;Postfix&gt;[:&lt;FormatString&gt;]]]</code>.<br>
      <code>ReadingName</code> is the Name of desired Reading, <code>Comment</code> is used as the display name and postfix is displayed after the value (such as units or as MHz can be displayed).
      If FormatString is specified, the output is formatted with sprintf (s. sprintf in Perl documentation).<br>
      If no <code>Comment</code> is specified, an internally predefined description is used.<br>
      If no list specified, a predefined selection is used (all values are displayed).<br><br>
      <code>define sysv1 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}</code><br>
      <code>define sysv2 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: &deg;C:%.1f'', 'cpu_freq:CPU Frequenz: MHz'))}</code>
   </ul>
   <br>
   <b>Text output method (see Weblink): SYSMON_ShowValuesHTMLTitled(&lt;SYSMON-Instance&gt;[,&lt;Title&gt;,&lt;Liste&gt;])</b><br><br>
   <ul>
      According to SYSMON_ShowValuesHTML, but with a Title text above. If no title provided, device alias will be used (if any)<br>
   </ul>
   <br>
   <b>Text output method (see Weblink): SYSMON_ShowValuesText(&lt;SYSMON-Instance&gt;[,&lt;Liste&gt;])</b><br><br>
   <ul>
      According to SYSMON_ShowValuesHTML, but formatted as plain text.<br>
   </ul>
   <br>
   <b>Text output method (see Weblink): SYSMON_ShowValuesTextTitled(&lt;SYSMON-Instance&gt;[,&lt;Title&gt;,&lt;Liste&gt;])</b><br><br>
   <ul>
      According to SYSMON_ShowValuesHTMLTitled, but formatted as plain text.<br>
   </ul>
   <br>
   <b>Reading values with perl: SYSMON_getValues(&lt;name&gt;[, &lt;array of desired keys&gt;])</b><br><br>
   <ul>
      Returns a hash ref with desired values. If no array is passed, all values are returned.<br>
      {(SYSMON_getValues("sysmon"))->{'cpu_temp'}}<br>
      {(SYSMON_getValues("sysmon",("cpu_freq","cpu_temp")))->{"cpu_temp"}}<br>
      {join(" ", values (SYSMON_getValues("sysmon")))}<br>
      {join(" ", values (SYSMON_getValues("sysmon",("cpu_freq","cpu_temp"))))}<br>
   </ul>
   <br>
   <b>Examples:</b><br><br>
   <ul>
      <code>
      # Modul-Definition<br>
      define sysmon SYSMON 1 1 1 10<br>
      #attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,^~ /.*usb.*,~ /$<br>
      attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,fs_.*,stat_cpu_percent<br>
      attr sysmon filesystems fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick<br>
      attr sysmon network-interfaces eth0:eth0:Ethernet,wlan0:wlan0:WiFi<br>
      attr sysmon group RPi<br>
      attr sysmon room 9.03_Tech<br>
      <br>
      # Log<br>
      define FileLog_sysmon FileLog ./log/sysmon-%Y-%m.log sysmon<br>
      attr FileLog_sysmon group RPi<br>
      attr FileLog_sysmon logtype SM_CPUTemp:Plot,text<br>
      attr FileLog_sysmon room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Temperatur<br>
      define wl_sysmon_temp SVG FileLog_sysmon:SM_CPUTemp:CURRENT<br>
      attr wl_sysmon_temp group RPi<br>
      attr wl_sysmon_temp label "CPU Temperatur: Min $data{min2}, Max $data{max2}, Last $data{currval2}"<br>
      attr wl_sysmon_temp room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r eth0<br>
      define wl_sysmon_eth0 SVG FileLog_sysmon:SM_Network_eth0:CURRENT<br>
      attr wl_sysmon_eth0 group RPi<br>
      attr wl_sysmon_eth0 label "Netzwerk-Traffic eth0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_eth0 room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r wlan0<br>
      define wl_sysmon_wlan0 SVG FileLog_sysmon:SM_Network_wlan0:CURRENT<br>
      attr wl_sysmon_wlan0 group RPi<br>
      attr wl_sysmon_wlan0 label "Netzwerk-Traffic wlan0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_wlan0 room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Auslastung (load average)<br>
      define wl_sysmon_load SVG FileLog_sysmon:SM_Load:CURRENT<br>
      attr wl_sysmon_load group RPi<br>
      attr wl_sysmon_load label "Load Min: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_load room 9.03_Tech<br>
      <br>
      # Visualisierung: RAM-Nutzung<br>
      define wl_sysmon_ram SVG FileLog_sysmon:SM_RAM:CURRENT<br>
      attr wl_sysmon_ram group RPi<br>
      attr wl_sysmon_ram label "RAM-Nutzung Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_ram room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: Root-Partition<br>
      define wl_sysmon_fs_root SVG FileLog_sysmon:SM_FS_root:CURRENT<br>
      attr wl_sysmon_fs_root group RPi<br>
      attr wl_sysmon_fs_root label "Root Partition Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_root room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: USB-Stick<br>
      define wl_sysmon_fs_usb1 SVG FileLog_sysmon:SM_FS_usb1:CURRENT<br>
      attr wl_sysmon_fs_usb1 group RPi<br>
      attr wl_sysmon_fs_usb1 label "USB1 Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_usb1 room 9.03_Tech<br>
      <br>
      # Anzeige der Readings zum Einbinden in ein 'Raum'.<br>
      define SysValues weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}<br>
      attr SysValues group RPi<br>
      attr SysValues room 9.03_Tech<br>
      <br>
      # Anzeige CPU Auslasung<br>
      define wl_sysmon_cpustat SVG FileLog_sysmon:SM_CPUStat:CURRENT<br>
      attr wl_sysmon_cpustat label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat group RPi<br>
      attr wl_sysmon_cpustat room 9.99_Test<br>
      attr wl_sysmon_cpustat plotsize 840,420<br>
      define wl_sysmon_cpustat_s SVG FileLog_sysmon:SM_CPUStatSum:CURRENT<br>
      attr wl_sysmon_cpustat_s label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat_s group RPi<br>
      attr wl_sysmon_cpustat_s room 9.99_Test<br>
      attr wl_sysmon_cpustat_s plotsize 840,420<br>
      define wl_sysmon_cpustatT SVG FileLog_sysmon:SM_CPUStatTotal:CURRENT<br>
      attr wl_sysmon_cpustatT label "CPU-Auslastung"<br>
      attr wl_sysmon_cpustatT group RPi<br>
      attr wl_sysmon_cpustatT plotsize 840,420<br>
      attr wl_sysmon_cpustatT room 9.99_Test<br>
      <br>
      # Anzeige Stromversorgung AC<br>
      define wl_sysmon_power_ac SVG FileLog_sysmon:SM_power_ac:CURRENT<br>
      attr wl_sysmon_power_ac label "Stromversorgung (ac) Spannung: $data{min1} - $data{max1} V,  Strom: $data{min2} - $data{max2} mA"<br>
      attr wl_sysmon_power_ac room Technik<br>
      attr wl_sysmon_power_ac group system<br>
      # Anzeige Stromversorgung Battery<br>
      define wl_sysmon_power_bat SVG FileLog_sysmon:SM_power_battery:CURRENT<br>
      attr wl_sysmon_power_bat label "Stromversorgung (bat) Spannung: $data{min1} - $data{max1} V,  Strom: $data{min2} - $data{max2} mA"<br>
      attr wl_sysmon_power_bat room Technik<br>
      attr wl_sysmon_power_bat group system<br>
      </code>
   </ul>
</ul>
<!-- ================================ -->
=end html
=begin html_DE

<a name="SYSMON"></a>
<h3>SYSMON</h3>
(<a href="commandref.html#SYSMON">en</a> | de)
<ul>
   Dieses Modul liefert diverse Informationen und Statistiken zu dem System, auf dem FHEM-Server ausgef&uuml;hrt wird.
   Weiterhin k&ouml;nnen auch Remote-Systeme abgefragt werden (Telnet).
   Es werden nur Linux-basierte Systeme unterst&uuml;tzt. Manche Informationen sind hardwarespezifisch und sind daher nicht auf jeder Plattform
   verf&uuml;gbar.
   Bis jetzt wurde dieses Modul auf folgenden Systemen getestet: Raspberry Pi (Debian Wheezy), BeagleBone Black,
   FritzBox 7390, WR703N unter OpenWrt, CubieTruck und einige andere.
   <br>
   <br>
   F&uuml;r Informationen zu einer FritzBox beachten Sie bitte auch Module: <a href="#FRITZBOX">FRITZBOX</a> und <a href="#FB_CALLMONITOR">FB_CALLMONITOR</a>.
   <i>Das Modul nutzt das Perlmodule 'Net::Telnet' f&uuml;r den Fernzugriff. Dieses muss ggf. nachinstalliert werden.</i>
   <br><br>
   <b>Define</b>
   <br><br>
   <code>define &lt;name&gt; SYSMON [MODE[:[USER@]HOST][:PORT]] [&lt;M1&gt;[ &lt;M2&gt;[ &lt;M3&gt;[ &lt;M4&gt;]]]]</code><br>
   <br>
   Diese Anweisung erstellt eine neue SYSMON-Instanz.
   Die Parameter M1 bis M4 legen die Aktualisierungsintervalle f&uuml;r verschiedenen Readings (Statistiken) fest.
   Die Parameter sind als Multiplikatoren f&uuml;r die Zeit, die durch INTERVAL_BASE definiert ist, zu verstehen.
   Da diese Zeit fest auf 60 Sekunden gesetzt ist, k&ouml;nnen die Mx-Parameters als Zeitintervalle in Minuten angesehen werden.<br>
   Wird einer (oder mehrere) Multiplikatoren auf Null gesetzt werden, wird das entsprechende Readings deaktiviert.<br>
   <br>
   Die Parameter sind f&uuml;r die Aktualisierung der Readings nach folgender Schema zust&auml;ndig:
   <ul>
      <li>M1: (Default-Wert: 1)<br>
         cpu_freq, cpu_temp, cpu_temp_avg, loadavg, stat_cpu, stat_cpu_diff, stat_cpu_percent, stat_cpu_text, power readings<br><br>
      </li>
      <li>M2: (Default-Wert: M1)<br>
         ram, swap<br>
      </li>
      <li>M3: (Default-Wert: M1)<br>
         eth0, eth0_diff, wlan0, wlan0_diff<br><br>
      </li>
      <li>M4: (Default-Wert: 10*M1)<br>
         Filesystem-Informationen<br><br>
      </li>
      <li>folgende Parameter werden immer anhand des Basisintervalls (unabh&auml;ngig von den Mx-Parameters) aktualisiert:<br>
         fhemuptime, fhemuptime_text, idletime, idletime_text, uptime, uptime_text, starttime, starttime_text<br><br>
      </li>
   </ul>
   F&uuml;r Abfrage eines entfernten Systems muss mindestens deren Adresse (HOST) angegeben werden, bei Bedarf erg&auml;nzt durch den Port und/oder den Benutzernamen.
   Das eventuell ben&ouml;tigte Passwort muss einmalig mit dem Befehl 'set password &lt;pass&gt;' definiert werden.
   Als MODE sind derzeit 'telnet', 'ssh' und 'local' erlaubt. 'local' erfordert keine weiteren Angaben und kann auch ganz weggelassen werden.
   <br>
   Bei SSH-Anmeldung mit Passwort muss 'sshpass' installiert sein (Achtung! Sicherheitstechnisch nicht empfehlenswert! Besser Public-Key-Verfahren benutzen).
   Damit SSH-Anmeldung funktioniert, muss ggf. einmalig eine manuelle SSH-Verbindung an die Remote-Machine von dem FHEM-Acount 
   (unter dessen Rechten FHEM läuft) durchgef&uuml;hrt und fingerprint best&auml;tigt werden.
   <br>
   <br>
   <b>Readings:</b>
   <br><br>
   <ul>
      <li>cpu_core_count<br>
         Anzahl der CPU Kerne
      </li>
      <li>cpu_model_name<br>
         CPU Modellname
      </li>
      <li>cpu_bogomips<br>
         CPU Speed: BogoMIPS
      </li>
      <li>cpu_freq (auf den DualCore-Systemen wie Cubietruck auch cpu1_freq)<br>
         CPU-Frequenz
      </li>
      <br>
      <li>cpu_temp<br>
         CPU-Temperatur
      </li>
      <br>
      <li>cpu_temp_avg<br>
         Durchschnitt der CPU-Temperatur, gebildet &uuml;ber die letzten 4 Werte.
      </li>
      <br>
      <li>fhemuptime<br>
         Zeit (in Sekunden) seit dem Start des FHEM-Servers.
      </li>
      <br>
      <li>fhemuptime_text<br>
         Zeit seit dem Start des FHEM-Servers: Menschenlesbare Ausgabe (texttuelle Darstellung).
      </li>
      <br>
      <li>fhemstarttime<br>
         Startzeit (in Sekunden seit 1.1.1970 1:00:00) des FHEM-Servers.
      </li>
      <br>
      <li>fhemstarttime_text<br>
         Startzeit des FHEM-Servers: Menschenlesbare Ausgabe (texttuelle Darstellung).
      </li>
      <br>
      <li>idletime<br>
         Zeit (in Sekunden und in Prozent), die das System (nicht der FHEM-Server!)
         seit dem Start in dem Idle-Modus verbracht hat. Also die Zeit der Inaktivit&auml;t.
      </li>
      <br>
      <li>idletime_text<br>
         Zeit der Inaktivit&auml;t des Systems seit dem Systemstart in menschenlesbarer Form.
      </li>
      <br>
      <li>loadavg<br>
         Ausgabe der Werte f&uuml;r die Systemauslastung (load average): 1 Minute-, 5 Minuten- und 15 Minuten-Werte.
      </li>
      <br>
      <li>ram<br>
         Ausgabe der Speicherauslastung.
      </li>
      <br>
      <li>swap<br>
         Benutzung und Auslastung der SWAP-Datei (bzw. Partition).
      </li>
      <br>
      <li>uptime<br>
         Zeit (in Sekenden) seit dem Systemstart.
      </li>
      <br>
      <li>uptime_text<br>
         Zeit seit dem Systemstart in menschenlesbarer Form.
      </li>
      <br>
      <li>starttime<br>
         Systemstart (Sekunden seit Thu Jan  1 01:00:00 1970).
      </li>
      <br>
      <li>starttime_text<br>
         Systemstart in menschenlesbarer Form.
      </li>
      <br>
      <li>Netzwerkinformationen<br>
         Informationen zu den &uuml;ber die angegebene Netzwerkschnittstellen &uuml;bertragene Datenmengen
         und der Differenz zu der vorherigen Messung.
         <br>
         Beispiele:<br>
         Menge der &uuml;bertragenen Daten &uuml;ber die Schnittstelle eth0.<br>
         <code>eth0: RX: 940.58 MB, TX: 736.19 MB, Total: 1676.77 MB</code><br>
         &Auml;nderung der &uuml;bertragenen Datenmenge in Bezug auf den vorherigen Aufruf (f&uuml;r eth0).<br>
         <code>eth0_diff: RX: 0.66 MB, TX: 0.06 MB, Total: 0.72 MB</code><br>
         IP and IP v6 Adressen
         <code>eth0_ip 192.168.0.15</code><br>
         <code>eth0_ip6 fe85::49:4ff:fe85:f885/64</code><br>
      </li>
      <br>
      <li>Network Speed (wenn verf&uuml;gbar)<br>
         Geschwindigkeit der aktuellen Netzwerkverbindung.
         <br>
         Beispiel:<br>
         <code>eth0_speed 100</code><br>
      </li>
      <br>
      <li>Dateisysteminformationen<br>
         Informationen zu der Gr&ouml;&szlig;e und der Belegung der gew&uuml;nschten Dateisystemen.<br>
         Seit Version 1.1.0 k&ouml;nnen Dateisysteme auch benannt werden (s.u.). <br>
         In diesem Fall werden f&uuml;r die diese Readings die angegebenen Namen verwendet.<br>
         Dies soll die &Uuml;bersicht verbessern und die Erstellung von Plots erleichten.<br>
         Beispiel:<br>
         <code>fs_root: Total: 7340 MB, Used: 3573 MB, 52 %, Available: 3425 MB at /</code>
      </li>
      <br>
      <li>CPU Auslastung<br>
         Informationen zu der Auslastung der CPU(s).<br>
         Beispiel:<br>
         <code>stat_cpu: 10145283 0 2187286 90586051 542691 69393 400342</code><br>
         <code>stat_cpu_diff: 2151 0 1239 2522 10 3 761</code><br>
         <code>stat_cpu_percent: 4.82 0.00 1.81 93.11 0.05 0.00 0.20</code><br>
         <code>stat_cpu_text: user: 32.17 %, nice: 0.00 %, sys: 18.53 %, idle: 37.72 %, io: 0.15 %, irq: 0.04 %, sirq: 11.38 %</code>
      </li>
      <br>
      <li>Benutzerdefinierte Eintr&auml;ge<br>
         Diese Readings sind Ausgaben der Kommanden, die an das Betriebssystem &uuml;bergeben werden.
         Die entsprechende Angaben werden durch Attributen <code>user-defined</code> und <code>user-fn</code> definiert.
      </li>
      <br>
      <b>FritzBox-spezifische Readings</b>
      <li>wlan_state<br>
         WLAN-Status: on/off
      </li>
      <br>
      <li>wlan_guest_state<br>
         Gast-WLAN-Status: on/off
      </li>
      <br>
      <li>internet_ip<br>
         aktuelle IP-Adresse
      </li>
      <br>
      <li>internet_state<br>
         Status der Internetverbindung: connected/disconnected
      </li>
      <br>
      <li>night_time_ctrl<br>
         Status der Klingelsperre on/off
      </li>
      <br>
      <li>num_new_messages<br>
         Anzahl der neuen Anrufbeantworter-Meldungen
      </li>
      <br>
      <li>fw_version_info<br>
         Angaben zu der installierten Firmware-Version: &lt;VersionNr&gt; &lt;Erstelldatum&gt; &lt;Zeit&gt;
      </li>
      <br>
      <b>DSL Informationen (FritzBox)</b>
      <li>dsl_rate<br>
         Down/Up Verbindungsgeschwindigkeit
      </li>
      <br>
      <li>dsl_synctime<br>
         Sync-Zeit mit Vermittlungsstelle
      </li>
      <br>
      <li>dsl_crc_15<br>
         Nicht behebbare &Uuml;bertragungsfehler in den letzten 15 Minuten
      </li>
      <br>
      <li>dsl_fec_15<br>
         Behebbare &Uuml;bertragungsfehler in den letzten 15 Minuten
      </li>
      <br>
      <b>Readings zur Stromversorgung</b>
      <li>power_ac_stat<br>
         Statusinformation f&uuml;r die AC-Buchse: online (0|1), present (0|1), voltage, current<br>
         Beispiel:<br>
         <code>power_ac_stat: 1 1 4.807 264</code><br>
      </li>
      <br>
      <li>power_ac_text<br>
         Statusinformation f&uuml;r die AC-Buchse in menschenlesbarer Form<br>
         Beispiel:<br>
         <code>power_ac_text ac: present / online, Voltage: 4.807 V, Current: 264 mA</code><br>
      </li>
      <br>
      <li>power_usb_stat<br>
         Statusinformation f&uuml;r die USB-Buchse
      </li>
      <br>
      <li>power_usb_text<br>
         Statusinformation f&uuml;r die USB-Buchse in menschenlesbarer Form
      </li>
      <br>
      <li>power_battery_stat<br>
         Statusinformation f&uuml;r die Batterie (wenn vorhanden): online (0|1), present (0|1), voltage, current, actual capacity<br>
         Beispiel:<br>
         <code>power_battery_stat: 1 1 4.807 264 100</code><br>
      </li>
      <br>
      <li>power_battery_text<br>
         Statusinformation f&uuml;r die Batterie (wenn vorhanden) in menschenlesbarer Form
      </li>
      <br>
      <li>power_battery_info<br>
         Menschenlesbare Zusatzinformationen  f&uuml;r die Batterie (wenn vorhanden): Technologie, Kapazit&auml;t, Status, Zustand, Gesamtkapazit&auml;t<br>
         Beispiel:<br>
         <code>power_battery_info: battery info: Li-Ion , capacity: 100 %, status: Full , health: Good , total capacity: 2100 mAh</code><br>
         Die Kapazit&auml;t soll in script.bin (z.B. ct-hdmi.bin) eingestellt werden (Parameter pmu_battery_cap). Mit bin2fex konvertieren (bin2fex -> script.fex -> edit -> fex2bin -> script.bin)<br>
      </li>
      <br>
      <li>cpuX_freq_stat<br>
         Frequenz-Statistik f&uuml;r die CPU X: Minimum, Maximum und Durchschnittswert<br>
         Beispiel:<br>
         <code>cpu0_freq_stat: 100 1000 900</code><br>
      </li>
      <br>
      <li>cpuX_idle_stat<br>
         Leerlaufzeit-Statistik f&uuml;r die CPU X: Minimum, Maximum und Durchschnittswert<br>
         Beispiel:<br>
         <code>cpu0_freq_stat: 23.76 94.74 90.75</code><br>
      </li>
      <br>
      <li>cpu[X]_temp_stat<br>
         Temperatur-Statistik f&uuml;r CPU: Minimum, Maximum und Durchschnittswert<br>
         Beispiel:<br>
         <code>cpu_temp_stat: 41.00 42.50 42.00</code><br>
      </li>
      <br>
      <li>ram_used_stat<br>
         Statistik der RAM-Nutzung: Minimum, Maximum und Durchschnittswert<br>
         Example:<br>
         <code>ram_used_stat: 267.55 1267.75 855.00</code><br>
      </li>
      <br>
      <li>swap_used_stat<br>
         Statistik der SWAP-Nutzung: Minimum, Maximum und Durchschnittswert<br>
         Example:<br>
         <code>swap_used_stat: 0 1024.00 250.00</code><br>
      </li>
      <br>
      <br>
   </ul>

   <br>
   <b>Get:</b><br><br>
   <ul>
      <li>interval<br>
         Listet die bei der Definition angegebene Polling-Intervalle auf.
      </li>
      <br>
      <li>interval_multipliers<br>
         Listet die definierten Multipliers.
      </li>
      <br>
      <li>list<br>
         Gibt alle Readings aus.
      </li>
      <br>
      <li>update<br>
         Aktualisiert alle Readings. Alle Werte werden neu abgefragt.
      </li>
      <br>
      <li>version<br>
         Zeigt die Version des SYSMON-Moduls.
      </li>
      <br>
      <br>
      <li>list_lan_devices<br>
         Listet bekannte Ger&auml;te im LAN (nur FritzBox).
      </li>
   </ul>
   <br>
   <b>Set:</b><br><br>
   <ul>
      <li>interval_multipliers<br>
         Definiert Multipliers (wie bei der Definition des Ger&auml;tes).
      </li>
      <br>
      <li>clean<br>
         L&ouml;scht benutzerdefinierbare Readings. Nach einem Update (oder nach der automatischen Aktualisierung) werden neue Readings generiert.<br>
      </li>
      <br>
      <li>clear &lt;reading name&gt;<br>
         L&ouml;scht den Reading-Eintrag mit dem gegebenen Namen. Nach einem Update (oder nach der automatischen Aktualisierung)
         wird dieser Eintrag ggf. neu erstellt (falls noch definiert). Dieses Mechanismus erlaubt das gezielte L&ouml;schen nicht mehr ben&ouml;tigter
         benutzerdefinierten Eintr&auml;ge.<br>
      </li>
      <br>
      <li>password &lt;Passwort&gt;<br>
         Definiert das Passwort f&uuml;r den Remote-Zugriff (i.d.R. nur einmalig notwendig).
      </li>
      <br>
   </ul>
   <br>
   <b>Attributes:</b><br><br>
   <ul>
      <li>filesystems &lt;reading name&gt;[:&lt;mountpoint&gt;[:&lt;comment&gt;]],...<br>
         Gibt die zu &uuml;berwachende Dateisysteme an. Es wird eine kommaseparierte Liste erwartet.<br>
         Reading-Name wird bei der Anzeige und Logging verwendet, Mount-Point ist die Grundlage der Auswertung,
         Kommentar ist relevant f&uuml;r die HTML-Anzeige (s. SYSMON_ShowValuesHTML)<br>
         Beispiel: <code>/boot,/,/media/usb1</code><br>
         oder: <code>fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick</code><br>
         Im Sinne der besseren &Uuml;bersicht sollten zumindest Name und MountPoint angegeben werden.
      </li>
      <br>
      <li>network-interfaces &lt;name&gt;[:&lt;interface&gt;[:&lt;comment&gt;]],...<br>
         Kommaseparierte Liste der Netzwerk-Interfaces, die &uuml;berwacht werden sollen.
         Jeder Eintrag besteht aus dem Reading-Namen, dem Namen
         des Netwerk-Adapters und einem Kommentar f&uuml;r die HTML-Anzeige (s. SYSMON_ShowValuesHTML). Wird kein Doppelpunkt verwendet,
         wird der Wert gleichzeitig als Reading-Name und Interface-Name verwendet.<br>
         Beispiel <code>ethernet:eth0:Ethernet,wlan:wlan0:WiFi</code><br>
      </li>
      <br>
      <li>user-defined &lt;readingsName&gt;:&lt;Interval_Minutes&gt;:&lt;Comment&gt;:&lt;Cmd&gt;,...<br>
         Diese kommaseparierte Liste definiert Eintr&auml;ge mit jeweils folgenden Daten:
         Reading-Name, Aktualisierungsintervall in Minuten, Kommentar und Betriebssystem-Commando.
         <br>Die BS-Befehle werden entsprechend des angegebenen Intervalls ausgef&uuml;hrt und als Readings mit den angegebenen Namen vermerkt.
         Kommentare werden f&uuml;r die HTML-Ausgaben (s. SYSMON_ShowValuesHTML) ben&ouml;tigt.
         <br>Alle Parameter sind nicht optional!
         <br>Es ist wichtig, dass die angegebenen Befehle schnell ausgef&uuml;hrt werden, denn in dieser Zeit wird der gesamte FHEM-Server blockiert!
         <br>Werden Ergebnisse der lang laufenden Operationen ben&ouml;tigt, sollten diese z.B als CRON-Job eingerichtet werden
         und in FHEM nur die davor gespeicherten Ausgaben visualisiert.<br><br>
         Beispiel: Anzeige der vorliegenden Paket-Aktualisierungen f&uuml;r das Betriebssystem:<br>
         In einem cron-Job wird folgendes t&auml;glich ausgef&uuml;hrt: <br>
         <code> sudo apt-get update 2>/dev/null >/dev/null</code>
         <code> apt-get upgrade --dry-run| perl -ne '/(\d*)\s[upgraded|aktualisiert]\D*(\d*)\D*install|^ \S+.*/ and print "$1 aktualisierte, $2 neue Pakete"' 2>/dev/null &gt; /opt/fhem/data/updatestatus.txt</code>
         <br>
         Das Attribute <code>uder-defined</code> wird auf <br><code>sys_updates:1440:System Aktualisierungen:cat /opt/fhem/data/updatestatus.txt</code><br> gesetzt.
         Danach wird die Anzahl der verf&uuml;gbaren Aktualisierungen t&auml;glich als Reading 'sys_updates' protokolliert.
      </li>
      <br>
      <li>user-fn &lt;fn_name&gt;:&lt;Interval_Minutes&gt;:&lt;reading_name1&gt;:&lt;reading_name2&gt;...[:&lt;reading_nameX&gt;],...<br>
         Liste der benutzerdefinierten Perlfunktionen.<br>
         Als &lt;fn_name&gt; k&ouml;nnen entweder Name einer Perlfunktion oder ein Perlausdruck verwendet werden.
         Die Perlfunktion bekommt den Device-Hash als &Uuml;bergabeparameter und muss ein Array mit Werte liefern.
         Diese Werte werden entsprechend den Parameter &lt;reading_nameX&gt; in Readings &uuml;bernommen.<br>
         Ein Perlausdruck muss in geschweifte Klammer eingeschlossen werden und kann folgende Paramter verwenden: $HASH (Device-Hash) und $NAME (Device-Name).
         R&uuml;ckgabe wird analog einer Perlfunktion erwartet.<br>
         Wichtig! Die Trennung zwischen mehreren Benutzerfunktionen muss mit einem Komma UND einem Leerzeichen erfolgen! Innerhalb der Funktiondefinition d&uuml;rfen Kommas nicht durch Leerzeichen gefolgt werden.
      </li>
      <br>
      <li>disable<br>
         M&ouml;gliche Werte: <code>0,1</code>. Bei <code>1</code> wird die Aktualisierung gestoppt.
      </li>
      <br>
      <li>telnet-prompt-regx, telnet-login-prompt-regx<br>
         RegExp zur Erkennung von Login- und Kommandozeile-Prompt. (Nur f&uuml;r Zugriffe &uuml;ber Telnet relevant.)
      </li>
      <br>
      <li>exclude<br>
         Erlaubt das Abfragen bestimmten Informationen zu unterbinden. <br>
         Mögliche Werte: user-defined (s. user-defined und user-fn), cpucount, uptime, fhemuptime,
         loadavg, cputemp, cpufreq, cpuinfo, diskstat, cpustat, ramswap, filesystem, network,
         fbwlan, fbnightctrl, fbnewmessages, fbdecttemp, fbversion, fbdsl, powerinfo
      </li>
      <br>
   </ul>
   <br>
   <b>Plots:</b><br><br>
   <ul>
      F&uuml;r dieses Modul sind bereits einige gplot-Dateien vordefiniert:<br>
      <ul>
         FileLog-Versionen:<br>
         <code>
         SM_RAM.gplot<br>
         SM_CPUTemp.gplot<br>
         SM_FS_root.gplot<br>
         SM_FS_usb1.gplot<br>
         SM_Load.gplot<br>
         SM_Network_eth0.gplot<br>
         SM_Network_eth0t.gplot<br>
         SM_Network_wlan0.gplot<br>
         SM_CPUStat.gplot<br>
         SM_CPUStatSum.gplot<br>
         SM_CPUStatTotal.gplot<br>
         SM_power_ac.gplot<br>
         SM_power_usb.gplot<br>
         SM_power_battery.gplot<br>
         </code>
         DbLog-Versionen:<br>
         <code>
         SM_DB_all.gplot<br>
         SM_DB_CPUFreq.gplot<br>
         SM_DB_CPUTemp.gplot<br>
         SM_DB_Load.gplot<br>
         SM_DB_Network_eth0.gplot<br>
         SM_DB_RAM.gplot<br>
         </code>
      </ul>
   </ul>
   <br>
   <b>HTML-Ausgabe-Methode (f&uuml;r ein Weblink): SYSMON_ShowValuesHTML(&lt;SYSMON-Instanz&gt;[,&lt;Liste&gt;])</b><br><br>
   <ul>
      Das Modul definiert eine Funktion, die ausgew&auml;hlte Readings in HTML-Format ausgibt. <br>
      Als Parameter wird der Name des definierten SYSMON-Ger&auml;ts erwartet.<br>
      Es kann auch ReadingsGroup, CloneDummy oder andere Module genutzt werden, dann werden einfach deren Readings verwendet.<br>
      Der zweite Parameter ist optional und gibt eine Liste der anzuzeigende Readings
      im Format <code>&lt;ReadingName&gt;[:&lt;Comment&gt;[:&lt;Postfix&gt;[:&lt;FormatString&gt;]]]</code> an.<br>
      Dabei gibt <code>ReadingName</code> den anzuzeigenden Reading an, der Wert aus <code>Comment</code> wird als der Anzeigename verwendet
      und <code>Postfix</code> wird nach dem eihentlichen Wert angezeigt (so k&ouml;nnen z.B. Einheiten wie MHz angezeigt werden). 
      Mit Hilfe von FormatString kann die Ausgabe beeinflusst werden (s. sprintf in PerlDoku).<br>
      Falls kein <code>Comment</code> angegeben ist, wird eine intern vordefinierte Beschreibung angegeben.
      Bei benutzerdefinierbaren Readings wird ggf. <code>Comment</code> aus der Definition verwendet.<br>
      Wird keine Liste angegeben, wird eine vordefinierte Auswahl verwendet (alle Werte).<br><br>
      <code>define sysv1 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}</code><br>
      <code>define sysv2 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: &deg;C', 'cpu_freq:CPU Frequenz: MHz'))}</code>
   </ul>
   <br>
   <b>HTML-Ausgabe-Methode (f&uuml;r ein Weblink): SYSMON_ShowValuesHTMLTitled(&lt;SYSMON-Instance&gt;[,&lt;Title&gt;,&lt;Liste&gt;])</b><br><br>
   <ul>
      Wie SYSMON_ShowValuesHTML, aber mit einer &Uuml;berschrift dar&uuml;ber. Wird keine &Uuml;berschrift angegeben, wird alias des Moduls genutzt (falls definiert).<br>
   </ul>
   <br>
   <b>Text-Ausgabe-Methode (see Weblink): SYSMON_ShowValuesText(&lt;SYSMON-Instance&gt;[,&lt;Liste&gt;])</b><br><br>
   <ul>
      Analog SYSMON_ShowValuesHTML, jedoch formatiert als reines Text.<br>
   </ul>
   <br>
   <b>HTML-Ausgabe-Methode (f&uuml;r ein Weblink): SYSMON_ShowValuesTextTitled(&lt;SYSMON-Instance&gt;[,&lt;Title&gt;,&lt;Liste&gt;])</b><br><br>
   <ul>
      Wie SYSMON_ShowValuesText, aber mit einer &Uuml;berschrift dar&uuml;ber.<br>
   </ul>
   <br>
   <b>Readings-Werte mit Perl lesen: SYSMON_getValues(&lt;name&gt;[, &lt;Liste der gew&uuml;nschten Schl&uuml;ssel&gt;])</b><br><br>
   <ul>
      Liefert ein Hash-Ref mit den gew&uuml;nschten Werten. Wenn keine Liste (array) &uuml;bergeben wird, werden alle Werte geliefert.<br>
      {(SYSMON_getValues("sysmon"))->{'cpu_temp'}}<br>
      {(SYSMON_getValues("sysmon",("cpu_freq","cpu_temp")))->{"cpu_temp"}}<br>
      {join(" ", values (SYSMON_getValues("sysmon")))}<br>
      {join(" ", values (SYSMON_getValues("sysmon",("cpu_freq","cpu_temp"))))}<br>
   </ul>
   <br>
   <b>Beispiele:</b><br><br>
   <ul>
      <code>
      # Modul-Definition<br>
      define sysmon SYSMON 1 1 1 10<br>
      #attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,^~ /.*usb.*,~ /$<br>
      attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,fs_.*,stat_cpu_percent<br>
      attr sysmon filesystems fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick<br>
      attr sysmon network-interfaces eth0:eth0:Ethernet,wlan0:wlan0:WiFi<br>
      attr sysmon group RPi<br>
      attr sysmon room 9.03_Tech<br>
      <br>
      # Log<br>
      define FileLog_sysmon FileLog ./log/sysmon-%Y-%m.log sysmon<br>
      attr FileLog_sysmon group RPi<br>
      attr FileLog_sysmon logtype SM_CPUTemp:Plot,text<br>
      attr FileLog_sysmon room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Temperatur<br>
      define wl_sysmon_temp SVG FileLog_sysmon:SM_CPUTemp:CURRENT<br>
      attr wl_sysmon_temp group RPi<br>
      attr wl_sysmon_temp label "CPU Temperatur: Min $data{min2}, Max $data{max2}, Last $data{currval2}"<br>
      attr wl_sysmon_temp room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r eth0<br>
      define wl_sysmon_eth0 SVG FileLog_sysmon:SM_Network_eth0:CURRENT<br>
      attr wl_sysmon_eth0 group RPi<br>
      attr wl_sysmon_eth0 label "Netzwerk-Traffic eth0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_eth0 room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r wlan0<br>
      define wl_sysmon_wlan0 SVG FileLog_sysmon:SM_Network_wlan0:CURRENT<br>
      attr wl_sysmon_wlan0 group RPi<br>
      attr wl_sysmon_wlan0 label "Netzwerk-Traffic wlan0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_wlan0 room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Auslastung (load average)<br>
      define wl_sysmon_load SVG FileLog_sysmon:SM_Load:CURRENT<br>
      attr wl_sysmon_load group RPi<br>
      attr wl_sysmon_load label "Load Min: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_load room 9.03_Tech<br>
      <br>
      # Visualisierung: RAM-Nutzung<br>
      define wl_sysmon_ram SVG FileLog_sysmon:SM_RAM:CURRENT<br>
      attr wl_sysmon_ram group RPi<br>
      attr wl_sysmon_ram label "RAM-Nutzung Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_ram room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: Root-Partition<br>
      define wl_sysmon_fs_root SVG FileLog_sysmon:SM_FS_root:CURRENT<br>
      attr wl_sysmon_fs_root group RPi<br>
      attr wl_sysmon_fs_root label "Root Partition Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_root room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: USB-Stick<br>
      define wl_sysmon_fs_usb1 SVG FileLog_sysmon:SM_FS_usb1:CURRENT<br>
      attr wl_sysmon_fs_usb1 group RPi<br>
      attr wl_sysmon_fs_usb1 label "USB1 Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_usb1 room 9.03_Tech<br>
      <br>
      # Anzeige der Readings zum Einbinden in ein 'Raum'.<br>
      define SysValues weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}<br>
      attr SysValues group RPi<br>
      attr SysValues room 9.03_Tech<br>
      <br>
      # Anzeige CPU Auslasung<br>
      define wl_sysmon_cpustat SVG FileLog_sysmon:SM_CPUStat:CURRENT<br>
      attr wl_sysmon_cpustat label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat group RPi<br>
      attr wl_sysmon_cpustat room 9.99_Test<br>
      attr wl_sysmon_cpustat plotsize 840,420<br>
      define wl_sysmon_cpustat_s SVG FileLog_sysmon:SM_CPUStatSum:CURRENT<br>
      attr wl_sysmon_cpustat_s label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat_s group RPi<br>
      attr wl_sysmon_cpustat_s room 9.99_Test<br>
      attr wl_sysmon_cpustat_s plotsize 840,420<br>
      define wl_sysmon_cpustatT SVG FileLog_sysmon:SM_CPUStatTotal:CURRENT<br>
      attr wl_sysmon_cpustatT label "CPU-Auslastung"<br>
      attr wl_sysmon_cpustatT group RPi<br>
      attr wl_sysmon_cpustatT plotsize 840,420<br>
      attr wl_sysmon_cpustatT room 9.99_Test<br>
      <br>
      # Anzeige Stromversorgung AC<br>
      define wl_sysmon_power_ac SVG FileLog_sysmon:SM_power_ac:CURRENT<br>
      attr wl_sysmon_power_ac label "Stromversorgung (ac) Spannung: $data{min1} - $data{max1} V,  Strom: $data{min2} - $data{max2} mA"<br>
      attr wl_sysmon_power_ac room Technik<br>
      attr wl_sysmon_power_ac group system<br>
      # Anzeige Stromversorgung Battery<br>
      define wl_sysmon_power_bat SVG FileLog_sysmon:SM_power_battery:CURRENT<br>
      attr wl_sysmon_power_bat label "Stromversorgung (bat) Spannung: $data{min1} - $data{max1} V,  Strom: $data{min2} - $data{max2} mA"<br>
      attr wl_sysmon_power_bat room Technik<br>
      attr wl_sysmon_power_bat group system<br>
      </code>
   </ul>
</ul>




=end html_DE
=cut

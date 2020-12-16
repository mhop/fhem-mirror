########################################################################################################################
# $Id: 76_SolarForecast.pm 21735 2020-04-20 20:53:24Z DS_Starter $
#########################################################################################################################
#       76_SolarForecast.pm
#
#       (c) 2020 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module is used by module 76_SMAPortal to create graphic devices.
#       It can't be used standalone without any SMAPortal-Device.
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################
package FHEM::SolarForecast;                              ## no critic 'package'

use strict;
use warnings;
use POSIX;
use GPUtils qw(GP_Import GP_Export);                      # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday);
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;         ## no critic 'eval'
use Encode;
use utf8;

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          AnalyzePerlCommand
          AttrVal
          AttrNum
          defs
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          Debug
          fhemTimeLocal
          FmtDateTime
          FmtTime
          FW_makeImage
          getKeyValue
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3            
          modules
          parseParams          
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          readingFnAttributes
          setKeyValue
          sortTopicNum   
          FW_cmd
          FW_directNotify
          FW_ME                                     
          FW_subdir                                 
          FW_room                                  
          FW_detail                                 
          FW_wname     
        )
  );
  
  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
          pageAsHtml
        )
  );  
  
}

# Versions History intern
my %vNotesIntern = (
  "0.1.0"  => "09.12.2020  initial Version "
);

# Voreinstellungen

my %hset = (                                                                # Hash der Set-Funktion
  forecastDevice          => { fn => \&_setforecastDevice         },
  moduleArea              => { fn => \&_setmoduleArea             },
  moduleEfficiency        => { fn => \&_setmoduleEfficiency       },
  inverterEfficiency      => { fn => \&_setinverterEfficiency     },
  inverterDevice          => { fn => \&_setinverterDevice         },
  meterDevice             => { fn => \&_setmeterDevice            },
  pvCorrectionFactor_05   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_06   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_07   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_08   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_09   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_10   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_11   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_12   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_13   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_14   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_15   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_16   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_17   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_18   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_19   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_20   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_21   => { fn => \&_setpvCorrectionFactor     },
  pvCorrectionFactor_Auto => { fn => \&_setpvCorrectionFactorAuto },
);

my @chours      = (5..21);                                                  # Stunden des Tages mit möglichen Korrekturwerten                              
my $defpvme     = 16.52;                                                    # default Wirkungsgrad Solarmodule
my $definve     = 98.3;                                                     # default Wirkungsgrad Wechselrichter
my $kJtokWh     = 0.00027778;                                               # Umrechnungsfaktor kJ in kWh
my $maxvariance = 0.6;                                                      # max. Varianz pro Durchlauf Berechnung Autokorrekturfaktor
my $definterval = 70;                                                       # Standard Abfrageintervall
  
################################################################
#               Init Fn
################################################################
sub Initialize {
  my ($hash) = @_;

  my $fwd = join(",",devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized")); 
  
  $hash->{DefFn}              = \&Define;
  $hash->{GetFn}              = \&Get;
  $hash->{SetFn}              = \&Set;
  $hash->{FW_summaryFn}       = \&FwFn;
  $hash->{FW_detailFn}        = \&FwFn;
  $hash->{AttrFn}             = \&Attr;
  $hash->{NotifyFn}           = \&Notify;
  $hash->{AttrList}           = "autoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "autoRefreshFW:$fwd ".
                                "beamColor:colorpicker,RGB ".
                                "beamColor2:colorpicker,RGB ".
                                "beamHeight ".
                                "beamWidth ".
                                # "consumerList ".
                                # "consumerLegend:none,icon_top,icon_bottom,text_top,text_bottom ".
                                # "consumerAdviceIcon ".
                                "disable:1,0 ".
                                "forcePageRefresh:1,0 ".
                                "headerAlignment:center,left,right ".                                       
                                "headerDetail:all,co,pv,pvco,statusLink ".
                                "hourCount:slider,4,1,24 ".
                                "hourStyle ".
                                "maxPV ".
                                "htmlStart ".
                                "htmlEnd ".
                                "interval ".
                                "showDiff:no,top,bottom ".
                                "showHeader:1,0 ".
                                "showLink:1,0 ".
                                "showNight:1,0 ".
                                "showWeather:1,0 ".
                                "spaceSize ".   
                                "layoutType:pv,co,pvco,diff ".
                                "Wh/kWh:Wh,kWh ".
                                "weatherColor:colorpicker,RGB ".                                
                                $readingFnAttributes;

  $hash->{FW_hideDisplayName} = 1;                     # Forum 88667

  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;                         # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)
 
return; 
}

###############################################################
#                  SolarForecast Define
###############################################################
sub Define {
  my ($hash, $def) = @_;

  my @a = split(/\s+/x, $def);

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden
  
  setVersionInfo  ($hash);                                                         # Versionsinformationen setzen
  createNotifyDev ($hash);
  
  readingsSingleUpdate($hash, "state", "initialized", 1); 

  centralTask ($hash);                                                             # Einstieg in Abfrage  
  
return;
}

###############################################################
#                  SolarForecast Set
###############################################################
sub Set {                             
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name  = shift @a;
  my $opt   = shift @a;
  my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
  my $prop  = shift @a;
  my $prop1 = shift @a;
  
  my ($setlist,@fcdevs,@indevs,@medevs,@cfs);
  my ($fcd,$ind,$med,$cf) = ("","","","");
    
  return if(IsDisabled($name));
 
  @fcdevs = devspec2array("TYPE=DWD_OpenData");
  $fcd    = join ",", @fcdevs if(@fcdevs);

  for my $h (@chours) {
      push @cfs, "pvCorrectionFactor_".sprintf("%02d",$h); 
  }
  $cf = join " ", @cfs if(@cfs);

  $setlist = "Unknown argument $opt, choose one of ".
             "forecastDevice:$fcd ".
             "inverterDevice ".
             "inverterEfficiency ".
             "meterDevice ".
             "moduleArea ".
             "moduleEfficiency ".
             "pvCorrectionFactor_Auto:on,off ".
             $cf
             ;
            
  my $params = {
      hash  => $hash,
      name  => $name,
      opt   => $opt,
      arg   => $arg,
      prop  => $prop,
      prop1 => $prop1
  };
    
  if($hset{$opt} && defined &{$hset{$opt}{fn}}) {
      my $ret = q{};
      $ret    = &{$hset{$opt}{fn}} ($params); 
      return $ret;
  }

return "$setlist";
}

################################################################
#                      Setter forecastDevice
################################################################
sub _setforecastDevice {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no PV forecast device specified};

  if(!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData") {
      return qq{Forecast device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};
  }

  readingsSingleUpdate($hash, "currentForecastDev", $prop, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter inverterDevice
################################################################
sub _setinverterDevice {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  my $indev  = $a->[0] // "";
  
  if(!$indev || !$defs{$indev}) {
      return qq{The device "$indev" doesn't exist!};
  }

  readingsSingleUpdate($hash, "currentInverterDev", $arg, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter meterDevice
################################################################
sub _setmeterDevice {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  my $medev  = $a->[0] // "";
  
  if(!$medev || !$defs{$medev}) {
      return qq{The device "$medev" doesn't exist!};
  }

  readingsSingleUpdate($hash, "currentMeterDev", $arg, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter moduleArea
################################################################
sub _setmoduleArea {                     ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no PV module area specified};

  if($prop !~ /[0-9,.]/x) {
      return qq{The module area must be specified by numbers and optionally with decimal places};
  }
  
  $prop =~ s/,/./x;

  readingsSingleUpdate($hash, "moduleArea", $prop, 1);

return;
}

################################################################
#                      Setter moduleEfficiency
################################################################
sub _setmoduleEfficiency {               ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no PV module efficiency specified};

  if($prop !~ /[0-9,.]/x) {
      return qq{The module efficiency must be specified by numbers and optionally with decimal places};
  }
  
  $prop =~ s/,/./x;

  readingsSingleUpdate($hash, "moduleEfficiency", $prop, 1);

return;
}

################################################################
#                      Setter inverterEfficiency
################################################################
sub _setinverterEfficiency {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no inverter efficiency specified};

  if($prop !~ /[0-9,.]/x) {
      return qq{The inverter efficiency must be specified by numbers and optionally with decimal places};
  }
  
  $prop =~ s/,/./x;

  readingsSingleUpdate($hash, "inverterEfficiency", $prop, 1);

return;
}

################################################################
#                      Setter pvCorrectionFactor
################################################################
sub _setpvCorrectionFactor {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop} // return qq{no correction value specified};

  if($prop !~ /[0-9,.]/x) {
      return qq{The correction value must be specified by numbers and optionally with decimal places};
  }
  
  $prop =~ s/,/./x;
  
  readingsSingleUpdate($hash, $opt, $prop." (manual set)", 1);
  
  my @da;
  my $t      = time;                                                                                # aktuelle Unix-Zeit 
  my $chour  = strftime "%H", localtime($t);                                                        # aktuelle Stunde
  my $fcdev  = ReadingsVal($name, "currentForecastDev", "");                                        # aktuelles Forecast Device
  
  my $params = {
      myHash  => $hash,
      myName  => $name,
      t       => $t,
      chour   => $chour,
      daref   => \@da
  };
  
  _transferForecastValues ($params);
  
  if(@da) {
      push @da, "state:updated";                                                                   # Abschluß state 
      createReadings ($hash, \@da);
  }

return;
}

################################################################
#                 Setter pvCorrectionFactor_Auto
################################################################
sub _setpvCorrectionFactorAuto {         ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop} // return qq{no correction value specified};
  
  readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", $prop, 1);

return;
}

###############################################################
#                  SolarForecast Get
###############################################################
sub Get {
 my ($hash, @a) = @_;
 return "\"get X\" needs at least an argument" if ( @a < 2 );
 my $name = shift @a;
 my $cmd  = shift @a;
 
 my $getlist = "Unknown argument $cmd, choose one of ".
               "data:noArg ".
               "html:noArg ".
               "ftui:noArg ";
               
 if ($cmd eq "data") {
     return centralTask ($hash);
 } 
       
 if ($cmd eq "html") {
     return pageAsHtml($hash);
 } 
 
 if ($cmd eq "ftui") {
     return pageAsHtml($hash,"ftui");
 } 
 
return;
}

################################################################
sub Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        $val = ($do == 1 ? "disabled" : "initialized");
        readingsSingleUpdate($hash, "state", $val, 1);
        
        if($do == 1) {
            my @allrds = keys%{$defs{$name}{READINGS}};
            foreach my $key(@allrds) {
                delete($defs{$name}{READINGS}{$key}) if($key ne "state");
            }
        }
    }
    
    if($aName eq "icon") {
        $_[2] = "consumerAdviceIcon";
    }
    
    if ($cmd eq "set") {
        if ($aName eq "interval") {
            unless ($aVal =~ /^[0-9]+$/x) {return "The value for $aName is not valid. Use only figures 0-9 !";}
            InternalTimer(gettimeofday()+1.0, "FHEM::SolarForecast::centralTask", $hash, 0);
        }          
    }

return;
}

###################################################################################
#                                 Eventverarbeitung
###################################################################################
sub Notify {
  # Es werden nur die Events von Geräten verarbeitet die im Hash $hash->{NOTIFYDEV} gelistet sind (wenn definiert).
  # Dadurch kann die Menge der Events verringert werden. In sub DbRep_Define angeben. 
  my $myHash   = shift;
  my $dev_hash = shift;
  my $myName   = $myHash->{NAME};                                                                  # Name des eigenen Devices
  my $devName  = $dev_hash->{NAME};                                                                # Device welches Events erzeugt hat
 
  return if(IsDisabled($myName) || !$myHash->{NOTIFYDEV}); 
  
  my $events = deviceEvents($dev_hash, 1);  
  return if(!$events);
 
return;
}

################################################################
#                       Zentraler Datenabruf
################################################################
sub centralTask {
  my $hash = shift;
  my $name = $hash->{NAME};                                                                        # Name des eigenen Devices 
  
  RemoveInternalTimer($hash, "FHEM::SolarForecast::centralTask");

  my $interval = controlParams ($name); 
  
  if($init_done == 1) {
      if(!$interval) {
          $hash->{MODE} = "Manual";
      } 
      else {
          my $new = gettimeofday()+$interval; 
          InternalTimer($new, "FHEM::SolarForecast::centralTask", $hash, 0);                       # Wiederholungsintervall
          $hash->{MODE} = "Automatic - next polltime: ".FmtTime($new);
      }
      
      return if(IsDisabled($name));
      
      readingsSingleUpdate($hash, "state", "running", 1); 
      
      my @da;
      my $t     = time;                                                                            # aktuelle Unix-Zeit 
      my $chour = strftime "%H", localtime($t);                                                    # aktuelle Stunde
            
      my $params = {
          myHash  => $hash,
          myName  => $name,
          t       => $t,
          chour   => $chour,
          daref   => \@da
      };
      
      _transferForecastValues ($params);                                                             # Forecast Werte übertragen                                           
      _transferInverterValues ($params);                                                             # WR Werte übertragen
      _transferMeterValues    ($params);
      
      if(@da) {
          createReadings ($hash, \@da);
      }
      
      sumNextHours ($hash, $chour, \@da);                                                            # Zusammenfassung nächste 4 Stunden erstellen
      calcVariance ($params);                                                                        # Autokorrektur berechnen
      
      readingsSingleUpdate($hash, "state", "updated", 1);                                            # Abschluß state 
  }
  else {
      InternalTimer(gettimeofday()+5, "FHEM::SolarForecast::centralTask", $hash, 0);
  }
  
return;
}

################################################################
#             Steuerparameter berechnen / festlegen
################################################################
sub controlParams {
  my $name = shift;

  my $interval = AttrVal($name, "interval", $definterval);           # 0 wenn manuell gesteuert

return $interval;
}

################################################################
#    Werte Forecast Device ermitteln und übertragen
################################################################
sub _transferForecastValues {               
  my $paref   = shift;
  my $myHash  = $paref->{myHash};
  my $myName  = $paref->{myName};
  my $t       = $paref->{t};
  my $chour   = $paref->{chour};
  my $daref   = $paref->{daref};
  
  my $fcname  = ReadingsVal($myName, "currentForecastDev", "");                                 # aktuelles Forecast Device
  return if(!$fcname || !$defs{$fcname});
  
  my ($time_str,$epoche,$fd,$v);
  
  my $fc0_SunRise = (split ":", ReadingsVal($fcname, "fc0_SunRise", "00:00"))[0];               # Sonnenaufgang heute    (hh)
  my $fc0_SunSet  = (split ":", ReadingsVal($fcname, "fc0_SunSet",  "00:00"))[0];               # Sonnenuntergang heute  (hh)
  my $fc1_SunRise = (split ":", ReadingsVal($fcname, "fc1_SunRise", "00:00"))[0];               # Sonnenaufgang morgen   (hh)
  my $fc1_SunSet  = (split ":", ReadingsVal($fcname, "fc1_SunSet",  "00:00"))[0];               # Sonnenuntergang morgen (hh)
  
  push @$daref, "Today_HourSunRise:".   $fc0_SunRise;
  push @$daref, "Today_HourSunSet:".    $fc0_SunSet;
  push @$daref, "Tomorrow_HourSunRise:".$fc1_SunRise;
  push @$daref, "Tomorrow_HourSunSet:". $fc1_SunSet;
  
  deleteReadingspec ($myHash, "NextHour.*");
  
  for my $num (0..47) {                      
      my $fh = $chour + $num; 
      $fd    = int ($fh / 24) ;
      $fh    = $fh - ($fd * 24); 
      
      next if($fd > 1);
      
      Log3($myName, 5, "$myName - collect DWD data: device=$fcname, rad=fc${fd}_${fh}_Rad1h, wid=fc${fd}_${fh}_ww");

      $v = ReadingsVal($fcname, "fc${fd}_${fh}_Rad1h", 0);
      
      ## PV Forecast
      ###############
      if($num == 0) {          
          $time_str = "ThisHour";
          $epoche   = $t;                                                                     # Epoche Zeit
      }
      else {
          $time_str = "NextHour".sprintf "%02d", $num;
          $epoche   = $t + (3600*$num);
      }
      
      my $calcpv = calcPVforecast ($myName, $v, $fh);                                         # Vorhersage gewichtet kalkulieren
      
      push @$daref, "${time_str}_PVforecast:".$calcpv;
      push @$daref, "${time_str}_Time:"      .TimeAdjust     ($epoche);                       # Zeit fortschreiben 
      
      $myHash->{HELPER}{"fc${fd}_".sprintf("%02d",$fh)."_PVforecast"} = $calcpv;              # Vorhersagedaten zur Berechnung Korrekturfaktor in Helper speichern           
      
      ## Wetter Forecast
      ###################

      my $wid   = ReadingsVal($fcname, "fc${fd}_${fh}_ww", 0);
      $wid      = sprintf "%02d", $wid;                                                       # führende 0 einfügen wenn nötig
      my $fhstr = sprintf "%02d", $fh;
      
      if($fd == 0 && ($fhstr lt $fc0_SunRise || $fhstr gt $fc0_SunSet)) {                     # Zeit vor Sonnenaufgang oder nach Sonnenuntergang heute
          $wid = "1".$wid;                                                                    # "1" der WeatherID voranstellen wenn Nacht
      }
      elsif ($fd == 1 && ($fhstr lt $fc1_SunRise || $fhstr gt $fc1_SunSet)) {                 # Zeit vor Sonnenaufgang oder nach Sonnenuntergang morgen
          $wid = "1".$wid;                                                                    # "1" der WeatherID voranstellen wenn Nacht
      }
      
      $myHash->{HELPER}{"${time_str}_WeatherId"} = $wid;
  }
      
return;
}

################################################################
#    Werte Inverter Device ermitteln und übertragen
################################################################
sub _transferInverterValues {               
  my $paref   = shift;
  my $myHash  = $paref->{myHash};
  my $myName  = $paref->{myName};
  my $t       = $paref->{t};
  my $chour   = $paref->{chour};
  my $daref   = $paref->{daref};  

  my $indev   = ReadingsVal($myName, "currentInverterDev", "");
  my ($a,$h)  = parseParams ($indev);
  $indev      = $a->[0] // "";
  return if(!$indev || !$defs{$indev});
  
  my $tlim = "0|23";                                                                          # Stunde 23 -> bestimmte Aktionen
  
  if($chour =~ /^($tlim)$/x) {
      my @allrds = keys %{$myHash->{READINGS}};
      for my $key(@allrds) {
          readingsDelete($myHash, $key) if($key =~ m/^Today_Hour\d{2}_PVreal$/x);
      }
  }
  
  ## aktuelle PV-Erzeugung
  #########################
  my ($pvread,$pvunit) = split ":", $h->{pv};                                                 # Readingname/Unit für aktuelle PV Erzeugung
  my ($edread,$edunit) = split ":", $h->{etoday};                                             # Readingname/Unit für Tagesenergie
  
  Log3($myName, 5, "$myName - collect Inverter data: device=$indev, pv=$pvread ($pvunit), etoday=$edread ($edunit)");
  
  my $pvuf   = $pvunit =~ /^kW$/xi ? 1000 : 1;
  my $pv     = ReadingsNum ($indev, $pvread, 0) * $pvuf;                                      # aktuelle Erzeugung (W)  
      
  push @$daref, "Current_PV:". $pv." W";                                          
  
  my $eduf   = $edunit =~ /^kWh$/xi ? 1000 : 1;
  my $etoday = ReadingsNum ($indev, $edread, 0) * $eduf;                                      # aktuelle Erzeugung (W) 
  
  my $edaypast   = 0;
  for my $h (0..int($chour)-1) {                                                              # alle bisherigen Erzeugungen des Tages summieren                                            
      $edaypast += ReadingsNum ($myName, "Today_Hour".sprintf("%02d",$h)."_PVreal", 0);
  }
  
  my $ethishour  = $etoday - $edaypast;
  
  push @$daref, "Today_Hour${chour}_PVreal:". $ethishour." Wh" if($chour !~ /^($tlim)$/x);    # nicht setzen wenn Stunde 23 des Tages
      
return;
}

################################################################
#    Werte Meter Device ermitteln und übertragen
################################################################
sub _transferMeterValues {               
  my $paref   = shift;
  my $myHash  = $paref->{myHash};
  my $myName  = $paref->{myName};
  my $t       = $paref->{t};
  my $chour   = $paref->{chour};
  my $daref   = $paref->{daref};  

  my $medev   = ReadingsVal($myName, "currentMeterDev", "");                              # aktuelles Meter device
  my ($a,$h)  = parseParams ($medev);
  $medev      = $a->[0] // "";
  return if(!$medev || !$defs{$medev});
  
  ## aktuelle Consumption
  #########################
  my ($gc,$gcunit) = split ":", $h->{gcon};                                               # Readingname/Unit für aktuellen Netzbezug
  
  Log3($myName, 5, "$myName - collect Meter data: device=$medev, gcon=$gc ($gcunit)");
  
  my $gcuf = $gcunit =~ /^kW$/xi ? 1000 : 1;
  my $co   = ReadingsNum ($medev, $gc, 0) * $gcuf;                                        # aktueller Bezug (-) oder Einspeisung
  
  push @$daref, "Current_GridConsumption:".$co." W";
      
return;
}

################################################################
#              FHEMWEB Fn
################################################################
sub FwFn {
  my ($FW_wname, $d, $room, $pageHash) = @_;                       # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $height;
  
  RemoveInternalTimer($hash, \&pageRefresh);
  $hash->{HELPER}{FW} = $FW_wname;
       
  my $link  = forecastGraphic ($d);

  my $alias = AttrVal($d, "alias", $d);                            # Linktext als Aliasname oder Devicename setzen
  my $dlink = "<a href=\"/fhem?detail=$d\">$alias</a>"; 
  
  my $ret = "";
  if(IsDisabled($d)) {
      $height = AttrNum($d, 'beamHeight', 200);   
      $ret   .= "<table class='roomoverview'>";
      $ret   .= "<tr style='height:".$height."px'>";
      $ret   .= "<td>";
      $ret   .= "Solar forecast graphic device <a href=\"/fhem?detail=$d\">$d</a> is disabled"; 
      $ret   .= "</td>";
      $ret   .= "</tr>";
      $ret   .= "</table>";
  } 
  else {
      $ret .= "<span>$dlink </span><br>"  if(AttrVal($d,"showLink",0));
      $ret .= $link;  
  }
  
  # Autorefresh nur des aufrufenden FHEMWEB-Devices
  my $al = AttrVal($d, "autoRefresh", 0);
  if($al) {  
      InternalTimer(gettimeofday()+$al, \&pageRefresh, $hash, 0);
      Log3($d, 5, "$d - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  }

return $ret;
}

################################################################
sub pageRefresh { 
  my ($hash) = @_;
  my $d      = $hash->{NAME};
  
  # Seitenrefresh festgelegt durch SolarForecast-Attribut "autoRefresh" und "autoRefreshFW"
  my $rd = AttrVal($d, "autoRefreshFW", $hash->{HELPER}{FW});
  { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }
  
  my $al = AttrVal($d, "autoRefresh", 0);
  
  if($al) {      
      InternalTimer(gettimeofday()+$al, \&pageRefresh, $hash, 0);
      Log3($d, 5, "$d - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  } 
  else {
      RemoveInternalTimer($hash, \&pageRefresh);
  }
  
return;
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
      # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
      if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: 76_SolarForecast.pm 21735 2020-04-20 20:53:24Z DS_Starter $ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/g;
      } 
      else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 76_SolarForecast.pm 21735 2020-04-20 20:53:24Z DS_Starter $ im Kopf komplett! vorhanden )
      
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          
      }
  } 
  else {                                                                                                                # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

################################################################
#    Grafik als HTML zurück liefern    (z.B. für Widget)
################################################################
sub pageAsHtml { 
  my ($hash,$ftui) = @_;
  my $name         = $hash->{NAME};
  my $height;
  
  my $link  = forecastGraphic ($name, $ftui);

  my $alias = AttrVal($name, "alias", $name);                            # Linktext als Aliasname oder Devicename setzen
  my $dlink = "<a href=\"/fhem?detail=$name\">$alias</a>"; 
  
  my $ret = "<html>";
  if(IsDisabled($name)) {
      $height = AttrNum($name, 'beamHeight', 200);   
      $ret   .= "<table class='roomoverview'>";
      $ret   .= "<tr style='height:".$height."px'>";
      $ret   .= "<td>";
      $ret   .= "SMA Portal graphic device <a href=\"/fhem?detail=$name\">$name</a> is disabled"; 
      $ret   .= "</td>";
      $ret   .= "</tr>";
      $ret   .= "</table>";
  } 
  else {
      $ret .= "<span>$dlink </span><br>"  if(AttrVal($name,"showLink",0));
      $ret .= $link;  
  }    
  $ret .= "</html>";
  
return $ret;
}

###############################################################################
#                  Subroutine für Vorhersagegrafik
###############################################################################
sub forecastGraphic {                                                                      ## no critic 'complexity'
  my $name = shift;
  my $ftui = shift // "";
  
  my $hash = $defs{$name};
  my $ret  = "";
  
  my ($val,$height);
  my ($z2,$z3,$z4);
  my $he;                                                                                  # Balkenhöhe
  my (%pv,%is,%t,%we,%di,%co);
  my @pgCDev;
  
  ##########################################################
  # Kontext des SolarForecast-Devices speichern für Refresh
  $hash->{HELPER}{SPGDEV}    = $name;                                                      # Name des aufrufenden SMAPortalSPG-Devices
  $hash->{HELPER}{SPGROOM}   = $FW_room   ? $FW_room   : "";                               # Raum aus dem das SMAPortalSPG-Device die Funktion aufrief
  $hash->{HELPER}{SPGDETAIL} = $FW_detail ? $FW_detail : "";                               # Name des SMAPortalSPG-Devices (wenn Detailansicht)
  
  my $fcdev  = ReadingsVal($name, "currentForecastDev", "");                               # aktuelles Forecast Device  
  my $indev  = ReadingsVal($name, "currentInverterDev", "");                               # aktuelles Inverter Device
  my ($a,$h) = parseParams ($indev);
  $indev     = $a->[0] // "";  
  my $cclv   = "L05";
  
  my $pv0   = ReadingsNum ($name, "ThisHour_PVforecast", undef);
  my $ma    = ReadingsNum ($name, "moduleArea",              0);                           # Solar Modulfläche (qm)
  
  if(!$fcdev || !$ma || !defined $pv0) {
      $height = AttrNum($name, 'beamHeight', 200);   
      $ret   .= "<table class='roomoverview'>";
      $ret   .= "<tr style='height:".$height."px'>";
      $ret   .= "<td>";
      
      if(!$fcdev) {
          $ret .= qq{Please select a Solar Forecast device of Type "DWD_OpenData" with "set $name forecastDevice"};
      }
      elsif(!$indev) {
          $ret .= qq{Please select an Inverter device with "set $name inverterDevice"};   
      }
      elsif(!$ma) {
          $ret .= qq{Please specify the total module area with "set $name moduleArea"};   
      }
      elsif(!defined $pv0) {
          $ret .= qq{Awaiting data from selected Solar Forecast device ...};   
      }
      
      $ret   .= "</td>";
      $ret   .= "</tr>";
      $ret   .= "</table>";
      return $ret;
  }

  @pgCDev                     = split(',',AttrVal($name,"consumerList",""));            # definierte Verbraucher ermitteln
  my ($legend_style, $legend) = split('_',AttrVal($name,'consumerLegend','icon_top'));

  $legend = '' if(($legend_style eq 'none') || (!int(@pgCDev)));
  
  ###################################
  # Verbraucherlegende und Steuerung
  ###################################
  my $legend_txt;
  if ($legend) {
      for (@pgCDev) {
          my($txt,$im) = split(':',$_);                                                 # $txt ist der Verbrauchername
          my $cmdon   = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name $txt on')\"";
          my $cmdoff  = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name $txt off')\"";
          my $cmdauto = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name $txt auto')\"";
          
          if ($ftui eq "ftui") {
              $cmdon   = "\"ftui.setFhemStatus('set $name $txt on')\"";
              $cmdoff  = "\"ftui.setFhemStatus('set $name $txt off')\"";
              $cmdauto = "\"ftui.setFhemStatus('set $name $txt auto')\"";      
          }
          
          my $swstate  = ReadingsVal($name,"${cclv}_".$txt."_Switch", "undef");
          my $swicon   = "<img src=\"$FW_ME/www/images/default/1px-spacer.png\">";
          
          if($swstate eq "off") {
              $swicon = "<a onClick=$cmdon><img src=\"$FW_ME/www/images/default/10px-kreis-rot.png\"></a>";
          } 
          elsif ($swstate eq "on") {
              $swicon = "<a onClick=$cmdauto><img src=\"$FW_ME/www/images/default/10px-kreis-gruen.png\"></a>";
          } 
          elsif ($swstate =~ /off.*automatic.*/ix) {
              $swicon = "<a onClick=$cmdon><img src=\"$FW_ME/www/images/default/10px-kreis-gelb.png\"></a>";
          }
          
          if ($legend_style eq 'icon') {                                                           # mögliche Umbruchstellen mit normalen Blanks vorsehen !
              $legend_txt .= $txt.'&nbsp;'.FW_makeImage($im).' '.$swicon.'&nbsp;&nbsp;'; 
          } 
          else {
              my (undef,$co) = split('\@',$im);
              $co            = '#cccccc' if (!$co);                                                # Farbe per default
              $legend_txt   .= '<font color=\''.$co.'\'>'.$txt.'</font> '.$swicon.'&nbsp;&nbsp;';  # hier auch Umbruch erlauben
          }
      }
  }

  ###################################
  # Parameter f. Anzeige extrahieren
  ###################################  
  my $maxhours   =  AttrNum ($name, 'hourCount',             24   );
  my $hourstyle  =  AttrVal ($name, 'hourStyle',          undef   );
  my $colorfc    =  AttrVal ($name, 'beamColor',          undef   );
  my $colorc     =  AttrVal ($name, 'beamColor2',         'C4C4A7');               
  my $icon       =  AttrVal ($name, 'consumerAdviceIcon', undef   );
  my $html_start =  AttrVal ($name, 'htmlStart',          undef   );                      # beliebige HTML Strings die vor der Grafik ausgegeben werden
  my $html_end   =  AttrVal ($name, 'htmlEnd',            undef   );                      # beliebige HTML Strings die nach der Grafik ausgegeben werden

  my $type       =  AttrVal ($name, 'layoutType',          'pv'   );
  my $kw         =  AttrVal ($name, 'Wh/kWh',              'Wh'   );

  $height        =  AttrNum ($name, 'beamHeight',           200   );
  my $width      =  AttrNum ($name, 'beamWidth',              6   );                      # zu klein ist nicht problematisch
  my $w          =  $width*$maxhours;                                                     # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  my $fsize      =  AttrNum ($name, 'spaceSize',             24   );
  my $maxVal     =  AttrNum ($name, 'maxPV',                  0   );                      # dyn. Anpassung der Balkenhöhe oder statisch ?

  my $show_night =  AttrNum ($name, 'showNight',              0   );                      # alle Balken (Spalten) anzeigen ?
  my $show_diff  =  AttrVal ($name, 'showDiff',            'no'   );                      # zusätzliche Anzeige $di{} in allen Typen
  my $weather    =  AttrNum ($name, 'showWeather',            1   );
  my $colorw     =  AttrVal ($name, 'weatherColor',       undef   );

  my $wlalias    =  AttrVal ($name, 'alias',              $name   );
  my $header     =  AttrNum ($name, 'showHeader',             1   ); 
  my $hdrAlign   =  AttrVal ($name, 'headerAlignment', 'center'   );                      # ermöglicht per attr die Ausrichtung der Tabelle zu setzen
  my $hdrDetail  =  AttrVal ($name, 'headerDetail',       'all'   );                      # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten

  # Icon Erstellung, mit @<Farbe> ergänzen falls einfärben
  # Beispiel mit Farbe:  $icon = FW_makeImage('light_light_dim_100.svg@green');
 
  $icon    = FW_makeImage($icon) if (defined($icon));
  my $co4h = ReadingsNum ($name,"Next04Hours_Consumption", 0);
  my $coRe = ReadingsNum ($name,"RestOfDay_Consumption",   0); 
  my $coTo = ReadingsNum ($name,"Tomorrow_Consumption",    0);
  my $coCu = ReadingsNum ($name,"Current_GridConsumption", 0);

  my $pv4h = ReadingsNum ($name,"Next04Hours_PV",          0);
  my $pvRe = ReadingsNum ($name,"RestOfDay_PV",            0); 
  my $pvTo = ReadingsNum ($name,"Tomorrow_PV",             0);
  my $pvCu = ReadingsNum ($name,"Current_PV",              0);

  if ($kw eq 'kWh') {
      $co4h = sprintf("%.1f" , $co4h/1000)."&nbsp;kWh";
      $coRe = sprintf("%.1f" , $coRe/1000)."&nbsp;kWh";
      $coTo = sprintf("%.1f" , $coTo/1000)."&nbsp;kWh";
      $coCu = sprintf("%.1f" , $coCu/1000)."&nbsp;kW";
      $pv4h = sprintf("%.1f" , $pv4h/1000)."&nbsp;kWh";
      $pvRe = sprintf("%.1f" , $pvRe/1000)."&nbsp;kWh";
      $pvTo = sprintf("%.1f" , $pvTo/1000)."&nbsp;kWh";
      $pvCu = sprintf("%.1f" , $pvCu/1000)."&nbsp;kW";
  } 
  else {
      $co4h .= "&nbsp;Wh";
      $coRe .= "&nbsp;Wh";
      $coTo .= "&nbsp;Wh";
      $coCu .= "&nbsp;W";
      $pv4h .= "&nbsp;Wh";
      $pvRe .= "&nbsp;Wh";
      $pvTo .= "&nbsp;Wh";
      $pvCu .= "&nbsp;W";
  }

  ##########################
  # Headerzeile generieren 
  ##########################  
  if ($header) {
      my $lang    = AttrVal    ("global", "language",           "EN"  );
      my $alias   = AttrVal    ($name,    "alias",              $name );                            # Linktext als Aliasname
      
      my $dlink   = "<a href=\"/fhem?detail=$name\">$alias</a>";      
      my $lup     = ReadingsTimestamp($name, "ThisHour_PVforecast", "0000-00-00 00:00:00");         # letzter Forecast Update  
      
      my $lupt    = "last update:";  
      my $lblPv4h = "next&nbsp;4h:";
      my $lblPvRe = "remain today:";
      my $lblPvTo = "tomorrow:";
      my $lblPvCu = "actual";
     
      if(AttrVal("global", "language", "EN") eq "DE") {                                             # Header globales Sprachschema Deutsch
          $lupt    = "Stand:"; 
          $lblPv4h = encode("utf8", "nächste&nbsp;4h:");
          $lblPvRe = "Rest heute:";
          $lblPvTo = "morgen:";
          $lblPvCu = "aktuell";
      }  

      $header = "<table align=\"$hdrAlign\">"; 
      
      #########################################
      # Header Link + Status + Update Button      
      if($hdrDetail eq "all" || $hdrDetail eq "statusLink") {
          my ($year, $month, $day, $time) = $lup =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x;
          
          if(AttrVal("global","language","EN") eq "DE") {
             $lup = "$day.$month.$year&nbsp;$time"; 
          } 
          else {
             $lup = "$year-$month-$day&nbsp;$time"; 
          }

          my $cmdupdate = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=get $name data')\"";    # Update Button generieren        

          if ($ftui eq "ftui") {
              $cmdupdate = "\"ftui.setFhemStatus('get $name data')\"";     
          }
          
          my $upstate  = ReadingsVal($name, "state", "");
          my $upicon;
          
          if ($upstate =~ /updated/ix) {
              $upicon = "<a onClick=$cmdupdate><img src=\"$FW_ME/www/images/default/10px-kreis-gruen.png\"></a>";
          } 
          elsif ($upstate =~ /running/ix) {
              $upicon = "<img src=\"$FW_ME/www/images/default/10px-kreis-gelb.png\"></a>";
          } 
          elsif ($upstate =~ /initialized/ix) {
              $upicon = "<img src=\"$FW_ME/www/images/default/1px-spacer.png\"></a>";
          } 
          else {
              $upicon = "<a onClick=$cmdupdate><img src=\"$FW_ME/www/images/default/10px-kreis-rot.png\"></a>";
          }
  
          $header .= "<tr><td colspan=\"3\" align=\"left\"><b>".$dlink."</b></td><td colspan=\"3\" align=\"right\">(".$lupt."&nbsp;".$lup.")&nbsp;".$upicon."</td></tr>";
      }
      
      ########################
      # Header Information pv 
      if($hdrDetail eq "all" || $hdrDetail eq "pv" || $hdrDetail eq "pvco") {   
          $header .= "<tr>";
          $header .= "<td><b>PV&nbsp;=></b></td>"; 
          $header .= "<td><b>$lblPvCu</b></td> <td align=right>$pvCu</td>"; 
          $header .= "<td><b>$lblPv4h</b></td> <td align=right>$pv4h</td>"; 
          $header .= "<td><b>$lblPvRe</b></td> <td align=right>$pvRe</td>"; 
          $header .= "<td><b>$lblPvTo</b></td> <td align=right>$pvTo</td>"; 
          $header .= "</tr>";
      }
      
      ########################
      # Header Information co 
      if($hdrDetail eq "all" || $hdrDetail eq "co" || $hdrDetail eq "pvco") {
          $header .= "<tr>";
          $header .= "<td><b>CO&nbsp;=></b></td>";
          $header .= "<td><b>$lblPvCu</b></td> <td align=right>$coCu</td>";           
          $header .= "<td><b>$lblPv4h</b></td> <td align=right>$co4h</td>"; 
          $header .= "<td><b>$lblPvRe</b></td> <td align=right>$coRe</td>"; 
          $header .= "<td><b>$lblPvTo</b></td> <td align=right>$coTo</td>"; 
          $header .= "</tr>"; 
      }

      $header .= "</table>";     
  }

  ##########################
  # Werte aktuelle Stunde
  ##########################
  $pv{0} = ReadingsNum($name, "ThisHour_PVforecast",  0);
  $co{0} = ReadingsNum($name, "ThisHour_Consumption", 0);
  $di{0} = $pv{0} - $co{0}; 
  $is{0} = (ReadingsVal($name,"ThisHour_IsConsumptionRecommended",'no') eq 'yes' ) ? $icon : undef;  
  $we{0} = $hash->{HELPER}{"ThisHour_WeatherId"} if($weather);                                   # für Wettericons 
  $we{0} = $we{0} // 999;

  if(AttrVal("global","language","EN") eq "DE") {
      (undef,undef,undef,$t{0}) = ReadingsVal($name, "ThisHour_Time", '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
  } 
  else {
      (undef,undef,undef,$t{0}) = ReadingsVal($name, "ThisHour_Time", '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
  }
  
  $t{0} = int($t{0});                                                                            # zum Rechnen Integer ohne führende Null

  ###########################################################
  # get consumer list and display it in portalGraphics
  ###########################################################  
  for (@pgCDev) {
      my ($itemName, undef) = split(':',$_);
      $itemName =~ s/^\s+|\s+$//gx;                                                              #trim it, if blanks were used
      $_        =~ s/^\s+|\s+$//gx;                                                              #trim it, if blanks were used
    
      ##################################
      #check if listed device is planned
      if (ReadingsVal($name, $itemName."_Planned", "no") eq "yes") {
          #get start and end hour
          my ($start, $end);                                                                     # werden auf Balken Pos 0 - 23 umgerechnet, nicht auf Stunde !!, Pos = 24 -> ungültige Pos = keine Anzeige

          if(AttrVal("global","language","EN") eq "DE") {
              (undef,undef,undef,$start) = ReadingsVal($name, $itemName."_PlannedOpTimeBegin", '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name, $itemName."_PlannedOpTimeEnd",   '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
          } 
          else {
              (undef,undef,undef,$start) = ReadingsVal($name, $itemName."_PlannedOpTimeBegin", '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name, $itemName."_PlannedOpTimeEnd",   '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
          }

          $start   = int($start);
          $end     = int($end);
          my $flag = 0;                                                                          # default kein Tagesverschieber

          #######################################
          #correct the hour for accurate display
          if ($start < $t{0}) {                                                                  # consumption seems to be tomorrow
              $start = 24-$t{0}+$start;
              $flag  = 1;
          } 
          else { 
              $start -= $t{0};          
          }

          if ($flag) {                                                                           # consumption seems to be tomorrow
              $end = 24-$t{0}+$end;
          } 
          else { 
              $end -= $t{0}; 
          }

          $_ .= ":".$start.":".$end;
      } 
      else { 
          $_ .= ":24:24"; 
      } 
      Log3($name, 4, "$name - Consumer planned data: $_");
  }

  $maxVal    = !$maxVal ? $pv{0} : $maxVal;                                                      # Startwert wenn kein Wert bereits via attr vorgegeben ist
  my $maxCon = $co{0};                                                                           # für Typ co
  my $maxDif = $di{0};                                                                           # für Typ diff
  my $minDif = $di{0};                                                                           # für Typ diff

  for my $i (1..$maxhours-1) {
     $pv{$i} = ReadingsNum($name, "NextHour".sprintf("%02d",$i)."_PVforecast",  0);              # Erzeugung
     $co{$i} = ReadingsNum($name, "NextHour".sprintf("%02d",$i)."_Consumption", 0);              # Verbrauch
     $di{$i} = $pv{$i} - $co{$i};

     $maxVal = $pv{$i} if ($pv{$i} > $maxVal); 
     $maxCon = $co{$i} if ($co{$i} > $maxCon);
     $maxDif = $di{$i} if ($di{$i} > $maxDif);
     $minDif = $di{$i} if ($di{$i} < $minDif);

     $is{$i} = (ReadingsVal($name,"NextHour".sprintf("%02d",$i)."_IsConsumptionRecommended",'no') eq 'yes') ? $icon : undef;
     $we{$i} = $hash->{HELPER}{"NextHour".   sprintf("%02d",$i)."_WeatherId"} if($weather);      # für Wettericons 
     $we{$i} = $we{$i} // 999;

     if(AttrVal("global","language","EN") eq "DE") {
        (undef,undef,undef,$t{$i}) = ReadingsVal($name,"NextHour".sprintf("%02d",$i)."_Time", '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
     } 
     else {
        (undef,undef,undef,$t{$i}) = ReadingsVal($name,"NextHour".sprintf("%02d",$i)."_Time", '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
     }

     $t{$i} = int($t{$i});                                  # keine führende 0
  }

  ######################################
  # Tabellen Ausgabe erzeugen
  ######################################
  
  # Wenn Table class=block alleine steht, zieht es bei manchen Styles die Ausgabe auf 100% Seitenbreite
  # lässt sich durch einbetten in eine zusätzliche Table roomoverview eindämmen
  # Die Tabelle ist recht schmal angelegt, aber nur so lassen sich Umbrüche erzwingen
   
  $ret  = "<html>";
  $ret .= $html_start if (defined($html_start));
  $ret .= "<style>TD.smaportal {text-align: center; padding-left:1px; padding-right:1px; margin:0px;}</style>";
  $ret .= "<table class='roomoverview' width='$w' style='width:".$w."px'><tr class='devTypeTr'></tr>";
  $ret .= "<tr><td class='smaportal'>";
  $ret .= "\n<table class='block'>";                                                                        # das \n erleichtert das Lesen der debug Quelltextausgabe

  if ($header) {                                                                                            # Header ausgeben 
      $ret .= "<tr class='odd'>";
      # mit einem extra <td></td> ein wenig mehr Platz machen, ergibt i.d.R. weniger als ein Zeichen
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$header</td></tr>";
  }

  if ($legend_txt && ($legend eq 'top')) {
      $ret .= "<tr class='odd'>";
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$legend_txt</td></tr>";
  }

  if ($weather) {
      $ret .= "<tr class='even'><td class='smaportal'></td>";                                # freier Platz am Anfang

      for my $i (0..$maxhours-1) {                                                           # keine Anzeige bei Null Ertrag bzw. in der Nacht , Typ pcvo & diff haben aber immer Daten in der Nacht
          if ($pv{$i} || $show_night || ($type eq 'pvco') || ($type eq 'diff')) {            # FHEM Wetter Icons (weather_xxx) , Skalierung und Farbe durch FHEM Bordmittel
              my $icon_name = weather_icon($we{$i});                                         # unknown -> FHEM Icon Fragezeichen im Kreis wird als Ersatz Icon ausgegeben
              Log3($name, 3,"$name - unknown weather id: ".$we{$i}.", please inform the maintainer") if($icon_name eq 'unknown');
              
              $icon_name .='@'.$colorw if (defined($colorw));
              $val        = FW_makeImage($icon_name);
      
              $val  ='<b>???<b/>' if ($val eq $icon_name);                                   # passendes Icon beim User nicht vorhanden ! ( attr web iconPath falsch/prüfen/update ? )
              $ret .= "<td class='smaportal' width='$width' style='margin:1px; vertical-align:middle align:center; padding-bottom:1px;'>$val</td>";
          
          } 
          else {                                                                             # Kein Ertrag oder show_night = 0
              $ret .= "<td></td>"; $we{$i} = undef; 
          } 
                                                                                             # mit $we{$i} = undef kann man unten leicht feststellen ob für diese Spalte bereits ein Icon ausgegeben wurde oder nicht
      }
      
      $ret .= "<td class='smaportal'></td></tr>";                                            # freier Platz am Ende der Icon Zeile
  }

  if($show_diff eq 'top') {                                                                  # Zusätzliche Zeile Ertrag - Verbrauch
      $ret .= "<tr class='even'><td class='smaportal'></td>";                                # freier Platz am Anfang
      
      for my $i (0..$maxhours-1) {
          $val  = formatVal6($di{$i},$kw,$we{$i});
          $val  = ($di{$i} < 0) ?  '<b>'.$val.'<b/>' : '+'.$val;                             # negative Zahlen in Fettschrift 
          $ret .= "<td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td>"; 
      }
      $ret .= "<td class='smaportal'></td></tr>"; # freier Platz am Ende 
  }

  $ret .= "<tr class='even'><td class='smaportal'></td>";                                    # Neue Zeile mit freiem Platz am Anfang

  for my $i (0..$maxhours-1) {
      # Achtung Falle, Division by Zero möglich, 
      # maxVal kann gerade bei kleineren maxhours Ausgaben in der Nacht leicht auf 0 fallen  
      $height = 200 if (!$height);                                                           # Fallback, sollte eigentlich nicht vorkommen, außer der User setzt es auf 0
      $maxVal = 1   if (!int $maxVal);
      $maxCon = 1   if (!$maxCon);

      # Der zusätzliche Offset durch $fsize verhindert bei den meisten Skins 
      # dass die Grundlinie der Balken nach unten durchbrochen wird
      if($type eq 'co') { 
          $he = int(($maxCon-$co{$i})/$maxCon*$height) + $fsize;                             # he - freier der Raum über den Balken.
          $z3 = int($height + $fsize - $he);                                                 # Resthöhe
      } 
      elsif($type eq 'pv') {
          $he = int(($maxVal-$pv{$i}) / $maxVal*$height) + $fsize;
          $z3 = int($height + $fsize - $he);
      } 
      elsif($type eq 'pvco') {
          # Berechnung der Zonen
          # he - freier der Raum über den Balken. fsize wird nicht verwendet, da bei diesem Typ keine Zahlen über den Balken stehen 
          # z2 - der Ertrag ggf mit Icon
          # z3 - der Verbrauch , bei zu kleinem Wert wird der Platz komplett Zone 2 zugeschlagen und nicht angezeigt
          # z2 und z3 nach Bedarf tauschen, wenn der Verbrauch größer als der Ertrag ist

          $maxVal = $maxCon if ($maxCon > $maxVal);                                         # wer hat den größten Wert ?

          if ($pv{$i} > $co{$i}) {                                                          # pv oben , co unten
              $z2 = $pv{$i}; $z3 = $co{$i}; 
          } 
          else {                                                                            # tauschen, Verbrauch ist größer als Ertrag
              $z3 = $pv{$i}; $z2 = $co{$i}; 
          }

          $he = int(($maxVal-$z2)/$maxVal*$height);
          $z2 = int(($z2 - $z3)/$maxVal*$height);

          $z3 = int($height - $he - $z2);                                                   # was von maxVal noch übrig ist
          
          if ($z3 < int($fsize/2)) {                                                        # dünnen Strichbalken vermeiden / ca. halbe Zeichenhöhe
              $z2 += $z3; $z3 = 0; 
          }
      } 
      else {                                                                                # Typ diff
          # Berechnung der Zonen
          # he - freier der Raum über den Balken , Zahl positiver Wert + fsize
          # z2 - positiver Balken inkl Icon
          # z3 - negativer Balken
          # z4 - Zahl negativer Wert + fsize

          my ($px_pos,$px_neg);
          my $maxPV = 0;                                                                    # ToDo:  maxPV noch aus Attribut maxPV ableiten

          if ($maxPV) {                                                                     # Feste Aufteilung +/- , jeder 50 % bei maxPV = 0
              $px_pos = int($height/2);
              $px_neg = $height - $px_pos;                                                  # Rundungsfehler vermeiden
          } 
          else {                                                                            # Dynamische hoch/runter Verschiebung der Null-Linie        
              if  ($minDif >= 0 ) {                                                         # keine negativen Balken vorhanden, die Positiven bekommen den gesammten Raum
                  $px_neg = 0;
                  $px_pos = $height;
              } 
              else {
                  if ($maxDif > 0) {
                      $px_neg = int($height * abs($minDif) / ($maxDif + abs($minDif)));     # Wieviel % entfallen auf unten ?
                      $px_pos = $height-$px_neg;                                            # der Rest ist oben
                  } 
                  else {                                                                    # keine positiven Balken vorhanden, die Negativen bekommen den gesammten Raum
                      $px_neg = $height;
                      $px_pos = 0;
                  }
              }
          }

          if ($di{$i} >= 0) {                                                               # Zone 2 & 3 mit ihren direkten Werten vorbesetzen
              $z2 = $di{$i};
              $z3 = abs($minDif);
          } 
          else {
              $z2 = $maxDif;
              $z3 = abs($di{$i}); # Nur Betrag ohne Vorzeichen
          }
 
          # Alle vorbesetzen Werte umrechnen auf echte Ausgabe px
          $he = (!$px_pos) ? 0 : int(($maxDif-$z2)/$maxDif*$px_pos);                        # Teilung durch 0 vermeiden
          $z2 = ($px_pos - $he) ;

          $z4 = (!$px_neg) ? 0 : int((abs($minDif)-$z3)/abs($minDif)*$px_neg);              # Teilung durch 0 unbedingt vermeiden
          $z3 = ($px_neg - $z4);

          # Beiden Zonen die Werte ausgeben könnten muß fsize als zusätzlicher Raum zugeschlagen werden !
          $he += $fsize; 
          $z4 += $fsize if ($z3);                                                           # komplette Grafik ohne negativ Balken, keine Ausgabe von z3 & z4
      }

      # das style des nächsten TD bestimmt ganz wesentlich das gesammte Design
      # das \n erleichtert das lesen des Seitenquelltext beim debugging
      # vertical-align:bottom damit alle Balken und Ausgaben wirklich auf der gleichen Grundlinie sitzen

      $ret .="<td style='text-align: center; padding-left:1px; padding-right:1px; margin:0px; vertical-align:bottom; padding-top:0px'>\n";
      
      my $v;
      if (($type eq 'pv') || ($type eq 'co')) {
          $v   = ($type eq 'co') ? $co{$i} : $pv{$i} ; 
          $v   = 0 if (($type eq 'co') && !$pv{$i} && !$show_night);                        # auch bei type co die Nacht ggf. unterdrücken
          $val = formatVal6($v,$kw,$we{$i});

          $ret .="<table width='100%' height='100%'>";                                      # mit width=100% etwas bessere Füllung der Balken
          $ret .="<tr class='even' style='height:".$he."px'>";
          $ret .="<td class='smaportal' style='vertical-align:bottom'>".$val."</td></tr>";

          if ($v || $show_night) {                                                          # Balken nur einfärben wenn der User via Attr eine Farbe vorgibt, sonst bestimmt class odd von TR alleine die Farbe
              my $style = "style=\"padding-bottom:0px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style   .= defined $colorfc ? " background-color:#$colorfc\"" : '"';         # Syntaxhilight 

              $ret .= "<tr class='odd' style='height:".$z3."px;'>";
              $ret .= "<td align='center' class='smaportal' ".$style.">";
              
              my $sicon = 1;                                                    
              $ret .= $is{$i} if (defined ($is{$i}) && $sicon);

              ##################################
              # inject the new icon if defined
              $ret .= consinject($hash,$i,@pgCDev) if($ret);
              
              $ret .= "</td></tr>";
         }   
      } 
      elsif ($type eq 'pvco') { 
          my ($color1, $color2, $style1, $style2);

          $ret .="<table width='100%' height='100%'>\n";                                   # mit width=100% etwas bessere Füllung der Balken

          if($he) {                                                                        # der Freiraum oben kann beim größten Balken ganz entfallen
              $ret .="<tr class='even' style='height:".$he."px'><td class='smaportal'></td></tr>";
          }

          if($pv{$i} > $co{$i}) {                                                          # wer ist oben, co pder pv ? Wert und Farbe für Zone 2 & 3 vorbesetzen
              $val     = formatVal6($pv{$i},$kw,$we{$i});
              $color1  = $colorfc;
              $style1  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style1 .= (defined($color1)) ? " background-color:#$color1\"" : '"';
              
              if($z3) {                                                                    # die Zuweisung können wir uns sparen wenn Zone 3 nachher eh nicht ausgegeben wird
                  $v       = formatVal6($co{$i},$kw,$we{$i});
                  $color2  = $colorc;
                  $style2  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
                  $style2 .= (defined($color2)) ? " background-color:#$color2\"" : '"';
              } 
          } 
          else {
              $val     = formatVal6($co{$i},$kw,$we{$i});
              $color1  = $colorc;
              $style1  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style1 .= (defined($color1)) ? " background-color:#$color1\"" : '"';
              
              if($z3) {
                  $v       = formatVal6($pv{$i},$kw,$we{$i});
                  $color2  = $colorfc;
                  $style2  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
                  $style2 .= (defined($color2)) ? " background-color:#$color2\"" : '"';
              }
          }

         $ret .= "<tr class='odd' style='height:".$z2."px'>";
         $ret .= "<td align='center' class='smaportal' ".$style1.">$val";     
         $ret .= $is{$i} if (defined $is{$i});
         
         ##################################
         # inject the new icon if defined
         $ret .= consinject($hash,$i,@pgCDev) if($ret);
         
         $ret .= "</td></tr>";

         if($z3) {                                                                                 # die Zone 3 lassen wir bei zu kleinen Werten auch ganz weg 
             $ret .= "<tr class='odd' style='height:".$z3."px'>";
             $ret .= "<td align='center' class='smaportal' ".$style2.">$v</td></tr>";
         }
      } 
      else {                                                                                       # Type diff
          my $style = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
          $ret     .= "<table width='100%' border='0'>\n";                                         # Tipp : das nachfolgende border=0 auf 1 setzen hilft sehr Ausgabefehler zu endecken
          $val      = ($di{$i} >= 0) ? formatVal6($di{$i},$kw,$we{$i}) : '';
          $val      = '&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;' if ($di{$i} == 0);                         # Sonderfall , hier wird die 0 gebraucht !

          if($val) {
              $ret .= "<tr class='even' style='height:".$he."px'>";
              $ret .= "<td class='smaportal' style='vertical-align:bottom'>".$val."</td></tr>";
          }

          if($di{$i} >= 0) {                                                                       # mit Farbe 1 colorfc füllen
              $style .= defined $colorfc ? " background-color:#$colorfc\"" : '"';
              $z2     = 1 if ($di{$i} == 0);                                                       # Sonderfall , 1px dünnen Strich ausgeben
              $ret   .= "<tr class='odd' style='height:".$z2."px'>";
              $ret   .= "<td align='center' class='smaportal' ".$style.">";
              $ret   .= $is{$i} if (defined $is{$i});
              $ret   .= "</td></tr>";
          } 
          else {                                                                                   # ohne Farbe
              $z2 = 2 if ($di{$i} == 0);                                                           # Sonderfall, hier wird die 0 gebraucht !
              if ($z2 && $val) {                                                                   # z2 weglassen wenn nicht unbedigt nötig bzw. wenn zuvor he mit val keinen Wert hatte
                  $ret .= "<tr class='even' style='height:".$z2."px'>";
                  $ret .= "<td class='smaportal'></td></tr>";
              }
          }
     
          if($di{$i} < 0) {                                                                        # Negativ Balken anzeigen ?
              $style .= (defined($colorc)) ? " background-color:#$colorc\"" : '"';                 # mit Farbe 2 colorc füllen
              $ret   .= "<tr class='odd' style='height:".$z3."px'>";
              $ret   .= "<td align='center' class='smaportal' ".$style."></td></tr>";
          } 
          elsif($z3) {                                                                             # ohne Farbe
              $ret .= "<tr class='even' style='height:".$z3."px'>";
              $ret .= "<td class='smaportal'></td></tr>";
          }

          if($z4) {                                                                                # kann entfallen wenn auch z3 0 ist
              $val  = ($di{$i} < 0) ? formatVal6($di{$i},$kw,$we{$i}) : '&nbsp;';
              $ret .= "<tr class='even' style='height:".$z4."px'>";
              $ret .= "<td class='smaportal' style='vertical-align:top'>".$val."</td></tr>";
          }
      }

      if ($show_diff eq 'bottom') {                                                                # zusätzliche diff Anzeige
          $val  = formatVal6($di{$i},$kw,$we{$i});
          $val  = ($di{$i} < 0) ?  '<b>'.$val.'<b/>' : '+'.$val;                                   # Kommentar siehe oben bei show_diff eq top
          $ret .= "<tr class='even'><td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td></tr>"; 
      }

      $ret  .= "<tr class='even'><td class='smaportal' style='vertical-align:bottom; text-align:center;'>";
      $t{$i} = $t{$i}.$hourstyle if(defined($hourstyle));                                          # z.B. 10:00 statt 10
      $ret  .= $t{$i}."</td></tr></table></td>";                                                   # Stundenwerte ohne führende 0
  }
  
  $ret .= "<td class='smaportal'></td></tr>";

  ###################
  # Legende unten
  if ($legend_txt && ($legend eq 'bottom')) {
      $ret .= "<tr class='odd'>";
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>";
      $ret .= "$legend_txt</td></tr>";
  }

  $ret .=  "</table></td></tr></table>";
  $ret .= $html_end if (defined($html_end));
  $ret .= "</html>";
  
return $ret;  
}

################################################################
#                 Inject consumer icon
################################################################
sub consinject {
  my ($hash,$i,@pgCDev) = @_;
  my $name              = $hash->{NAME};
  my $ret               = "";

  for (@pgCDev) {
      if ($_) {
          my ($cons,$im,$start,$end) = split (':', $_);
          Log3($name, 4, "$name - Consumer to show -> $cons, relative to current time -> start: $start, end: $end") if($i<1); 
          
          if ($im && ($i >= $start) && ($i <= $end)) {
              $ret .= FW_makeImage($im);
         }
      }
  }
      
return $ret;
}

###############################################################################
#                            Balkenbreite normieren
#
# Die Balkenbreite wird bestimmt durch den Wert.
# Damit alle Balken die gleiche Breite bekommen, müssen die Werte auf 
# 6 Ausgabezeichen angeglichen werden.
# "align=center" gleicht gleicht es aus, alternativ könnte man sie auch 
# komplett rechtsbündig ausgeben.
# Es ergibt bei fast allen Styles gute Ergebnisse, Ausnahme IOS12 & 6, da diese 
# beiden Styles einen recht großen Font benutzen.
# Wird Wetter benutzt, wird die Balkenbreite durch das Icon bestimmt
#
###############################################################################
sub formatVal6 {
  my ($v,$kw,$w) = @_;
  my $n          = '&nbsp;';                                # positive Zahl

  if($v < 0) {
      $n = '-';                                             # negatives Vorzeichen merken
      $v = abs($v);
  }

  if($kw eq 'kWh') {                                        # bei Anzeige in kWh muss weniger aufgefüllt werden
      $v  = sprintf('%.1f',($v/1000));
      $v  += 0;                                             # keine 0.0 oder 6.0 etc

      return ($n eq '-') ? ($v*-1) : $v if defined($w) ;

      my $t = $v - int($v);                                 # Nachkommstelle ?

      if(!$t) {                                             # glatte Zahl ohne Nachkommastelle
          if(!$v) { 
              return '&nbsp;';                              # 0 nicht anzeigen, passt eigentlich immer bis auf einen Fall im Typ diff
          } 
          elsif ($v < 10) { 
              return '&nbsp;&nbsp;'.$n.$v.'&nbsp;&nbsp;'; 
          } 
          else { 
              return '&nbsp;&nbsp;'.$n.$v.'&nbsp;'; 
          }
      } 
      else {                                                # mit Nachkommastelle -> zwei Zeichen mehr .X
          if ($v < 10) { 
              return '&nbsp;'.$n.$v.'&nbsp;'; 
          } 
          else { 
              return $n.$v.'&nbsp;'; 
          }
      }
  }

  return ($n eq '-') ? ($v*-1) : $v if defined($w);

  # Werte bleiben in Watt
  if    (!$v)         { return '&nbsp;'; }                            ## no critic "Cascading" # keine Anzeige bei Null 
  elsif ($v <    10)  { return '&nbsp;&nbsp;'.$n.$v.'&nbsp;&nbsp;'; } # z.B. 0
  elsif ($v <   100)  { return '&nbsp;'.$n.$v.'&nbsp;&nbsp;'; }
  elsif ($v <  1000)  { return '&nbsp;'.$n.$v.'&nbsp;'; }
  elsif ($v < 10000)  { return  $n.$v.'&nbsp;'; }
  else                { return  $n.$v; }                              # mehr als 10.000 W :)
}

###############################################################################
#         Zuordungstabelle "WeatherId" angepasst auf FHEM Icons
###############################################################################
sub weather_icon {
  my $id = shift;

  my %weather_ids = (
     '00' => 'weather_sun',                         # Sonne (klar)                                          # vorhanden
     '01' => 'weather_cloudy_light',                # leichte Bewölkung (1/3)                               # vorhanden
     '02' => 'weather_cloudy',                      # mittlere Bewölkung (2/3)                              # vorhanden
     '03' => 'weather_cloudy_heavy',                # starke Bewölkung (3/3)                                # vorhanden
     '10' => 'weather_fog',                         # Nebel                                                 # neu
     '11' => 'weather_rain_fog',                    # Nebel mit Regen                                       # neu
     '20' => 'weather_rain_heavy',                  # Regen (viel)                                          # vorhanden
     '21' => 'weather_rain_snow_heavy',             # Regen (viel) mit Schneefall                           # neu
     '30' => 'weather_rain_light',                  # leichter Regen (1 Tropfen)                            # vorhanden
     '31' => 'weather_rain',                        # leichter Regen (2 Tropfen)                            # vorhanden
     '32' => 'weather_rain_heavy',                  # leichter Regen (3 Tropfen)                            # vorhanden
     '40' => 'weather_rain_snow_light',             # leichter Regen mit Schneefall (1 Tropfen)             # neu
     '41' => 'weather_rain_snow',                   # leichter Regen mit Schneefall (3 Tropfen)             # neu
     '50' => 'weather_snow_light',                  # bewölkt mit Schneefall (1 Flocke)                     # vorhanden
     '51' => 'weather_snow',                        # bewölkt mit Schneefall (2 Flocken)                    # vorhanden
     '52' => 'weather_snow_heavy',                  # bewölkt mit Schneefall (3 Flocken)                    # vorhanden
     '60' => 'weather_rain_light',                  # Sonne, Wolke mit Regen (1 Tropfen)                    # vorhanden
     '61' => 'weather_rain',                        # Sonne, Wolke mit Regen (2 Tropfen)                    # vorhanden
     '62' => 'weather_rain_heavy',                  # Sonne, Wolke mit Regen (3 Tropfen)                    # vorhanden
     '70' => 'weather_snow_light',                  # Sonne, Wolke mit Schnee (1 Flocke)                    # vorhanden
     '71' => 'weather_snow_heavy',                  # Sonne, Wolke mit Schnee (3 Flocken)                   # vorhanden
     '80' => 'weather_thunderstorm',                # Wolke mit Blitz                                       # vorhanden
     '81' => 'weather_storm',                       # Wolke mit Blitz und Starkregen                        # vorhanden
     '90' => 'weather_sun',                         # Sonne (klar)                                          # vorhanden
     '91' => 'weather_sun',                         # Sonne (klar) wie 90                                   # vorhanden
    '100' => 'weather_night',                       # Mond - Nacht                                          # neu
    '101' => 'weather_night_cloudy_light',          # Mond mit Wolken -                                     # neu
    '102' => 'weather_night_cloudy',                # Wolken mittel (2/2) - Nacht                           # neu
    '103' => 'weather_night_cloudy_heavy',          # Wolken stark (3/3) - Nacht                            # neu
    '110' => 'weather_night_fog',                   # Nebel - Nacht                                         # neu
    '111' => 'weather_night_rain_fog',              # Nebel mit Regen (3 Tropfen) - Nacht                   # neu
    '120' => 'weather_night_rain_heavy',            # Regen (viel) - Nacht                                  # neu
    '121' => 'weather_night_snow_rain_heavy',       # Regen (viel) mit Schneefall - Nacht                   # neu
    '130' => 'weather_night_rain_light',            # leichter Regen (1 Tropfen) - Nacht                    # neu
    '131' => 'weather_night_rain',                  # leichter Regen (2 Tropfen) - Nacht                    # neu
    '132' => 'weather_night_rain_heavy',            # leichter Regen (3 Tropfen) - Nacht                    # neu
    '140' => 'weather_night_snow_rain_light',       # leichter Regen mit Schneefall (1 Tropfen) - Nacht     # neu
    '141' => 'weather_night_snow_rain_heavy',       # leichter Regen mit Schneefall (3 Tropfen) - Nacht     # neu
    '150' => 'weather_night_snow_light',            # bewölkt mit Schneefall (1 Flocke) - Nacht             # neu
    '151' => 'weather_night_snow',                  # bewölkt mit Schneefall (2 Flocken) - Nacht            # neu
    '152' => 'weather_night_snow_heavy',            # bewölkt mit Schneefall (3 Flocken) - Nacht            # neu
    '160' => 'weather_night_rain_light',            # Mond, Wolke mit Regen (1 Tropfen) - Nacht             # neu
    '161' => 'weather_night_rain',                  # Mond, Wolke mit Regen (2 Tropfen) - Nacht             # neu
    '162' => 'weather_night_rain_heavy',            # Mond, Wolke mit Regen (3 Tropfen) - Nacht             # neu
    '170' => 'weather_night_snow_rain',             # Mond, Wolke mit Schnee (1 Flocke) - Nacht             # neu
    '171' => 'weather_night_snow_heavy',            # Mond, Wolke mit Schnee (3 Flocken) - Nacht            # neu
    '180' => 'weather_night_thunderstorm_light',    # Wolke mit Blitz - Nacht                               # neu
    '181' => 'weather_night_thunderstorm',          # Wolke mit Blitz und Starkregen - Nacht                # neu
    '999' => '1px-spacer'                           # Dummy - keine Anzeige Wettericon                      # vorhanden
  );
  
return $weather_ids{$id} if(defined($weather_ids{$id}));
return 'unknown';
}

################################################################
#                   Timestamp berechnen
################################################################
sub TimeAdjust {
  my $epoch = shift;
  
  my ($lyear,$lmonth,$lday,$lhour) = (localtime($epoch))[5,4,3,2];
  
  $lyear += 1900;                  # year is 1900 based
  $lmonth++;                       # month number is zero based
  
  if(AttrVal("global","language","EN") eq "DE") {
      return (sprintf("%02d.%02d.%04d %02d:%s", $lday,$lmonth,$lyear,$lhour,"00:00"));
  } 
  else {
      return (sprintf("%04d-%02d-%02d %02d:%s", $lyear,$lmonth,$lday,$lhour,"00:00"));
  }
}

##################################################################################################
#            PV Forecast Rad1h in kWh / Wh
# Für die Umrechnung in einen kWh/Wh-Wert benötigt man einen entsprechenden Faktorwert:
#
#    * Faktor für Umwandlung kJ in kWh:   0.00027778
#    * Eigene Modulfläche in qm z.B.:     31,04
#    * Wirkungsgrad der Module in % z.B.: 16,52
#    * Wirkungsgrad WR in % z.B.:         98,3
#    * Korrekturwerte wegen Ausrichtung/Verschattung: 83% wegen Ost/West und Schatten (Iteration)
#
# Die Formel wäre dann: 
# Ertrag in kWh = Rad1h * 0.00027778 * 31,04 qm * 16,52% * 98,3% * 100%
#
# Damit ergibt sich ein Umrechnungsfaktor von: 0,00140019 für kWh / 1,40019 für Wh
#
# Bei einem Rad1h-Wert von 500 ergibt dies bei mir also  0,700095 kWh / 700,095 Wh
##################################################################################################
sub calcPVforecast {            
  my $name = shift;
  my $rad  = shift;                                                                     # Nominale Strahlung aus DWD Device
  my $fh   = shift;                                                                     # Stunde des Tages 
  
  my $ma = ReadingsNum ($name, "moduleArea",                              0        );   # Solar Modulfläche (gesamt)
  my $me = ReadingsNum ($name, "moduleEfficiency",                        $defpvme );   # Solar Modul Wirkungsgrad (%)
  my $ie = ReadingsNum ($name, "inverterEfficiency",                      $definve );   # Solar Inverter Wirkungsgrad (%)
  my $hc = ReadingsNum ($name, "pvCorrectionFactor_".sprintf("%02d",$fh), 1        );   # Korrekturfaktor für die Stunde des Tages
  
  my $pv = sprintf "%.1f", ($rad * $kJtokWh * $ma * $me/100 * $ie/100 * $hc * 1000);
  
return $pv." Wh";
}

################################################################
#       Abweichung PVreal / PVforecast berechnen
################################################################
sub calcVariance {               
  my $paref   = shift;
  my $myHash  = $paref->{myHash};
  my $myName  = $paref->{myName};
  
  my $dcauto = ReadingsVal ($myName, "pvCorrectionFactor_Auto", "off");                   # nur bei "on" automatische Varianzkalkulation
  if($dcauto =~ /^off/x) {
      Log3($myName, 4, "$myName - automatic Variance calculation is switched off."); 
      return;      
  }
  
  my $idts = $myHash->{HELPER}{INVERTERDEFTS};                                            # FHEM Start oder Definitionstimestamp des Inverterdevice
  return if(!$idts);
  
  my $t = time;                                                                           # aktuelle Unix-Zeit

  if($t - $idts < 86400) {
      my $rmh = sprintf "%.1f", ((86400 - ($t - $idts)) / 3600);
      Log3($myName, 4, "$myName - Variance calculation in standby. It starts in $rmh hours."); 
      readingsSingleUpdate($myHash, "pvCorrectionFactor_Auto", "on (remains in standby for $rmh hours)", 0); 
      return;      
  }  

  my @da;
  for my $h (1..23) {
      my $fcval = $myHash->{HELPER}{"fc0_".sprintf("%02d",$h)."_PVforecast"} // 0;
      my $fcnum = int ((split " ", $fcval)[0]);
      next if(!$fcnum);
      
      my $oldfac = ReadingsNum ($myName, "pvCorrectionFactor_".sprintf("%02d",$h),  1);           # bisher definierter Korrekturfaktor
      my $pvval  = ReadingsNum ($myName, "Today_Hour".sprintf("%02d",$h)."_PVreal", 0);
      my $factor = sprintf "%.2f", ($pvval / $fcnum);                                             # Faktor reale PV / Prognose
      
      if(abs($factor - $oldfac) > $maxvariance) {
          $factor = sprintf "%.2f", ($factor > $oldfac ? $oldfac + $maxvariance : $oldfac - $maxvariance);
          Log3($myName, 4, "$myName - Use new limited Variance factor: $factor for hour: $h");
      }
      else {
          Log3($myName, 4, "$myName - new Variance factor: $factor for hour: $h calculated");
      }
      
      push @da, "pvCorrectionFactor_".sprintf("%02d",$h).":".$factor." (auto calc)";
  }
  
  createReadings ($myHash, \@da);
      
return;
}

################################################################
#               Zusammenfassungen erstellen
################################################################
sub sumNextHours {            
  my $hash  = shift;
  my $chour = shift;                          # aktuelle Stunde
  my $daref = shift;
  
  my $name  = $hash->{NAME};

  my $next4HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $restOfDaySum  = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $tomorrowSum   = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  
  my $rdh              = 24 - $chour - 1;                                         # verbleibende Anzahl Stunden am Tag beginnend mit 00 (abzüglich aktuelle Stunde)
  my $thforecast       = ReadingsNum ($name, "ThisHour_PVforecast", 0);
  $next4HoursSum->{PV} = $thforecast;
  $restOfDaySum->{PV}  = $thforecast;
  
  for my $h (1..47) {
      $next4HoursSum->{PV} += ReadingsNum ($name, "NextHour".(sprintf "%02d", $h)."_PVforecast", 0) if($h <= 3);
      $restOfDaySum->{PV}  += ReadingsNum ($name, "NextHour".(sprintf "%02d", $h)."_PVforecast", 0) if($h <= $rdh);
      $tomorrowSum->{PV}   += ReadingsNum ($name, "NextHour".(sprintf "%02d", $h)."_PVforecast", 0) if($h >  $rdh);
  }
  
  push @$daref, "Next04Hours_PV:". (int $next4HoursSum->{PV})." Wh";
  push @$daref, "RestOfDay_PV:".   (int $restOfDaySum->{PV}). " Wh";
  push @$daref, "Tomorrow_PV:".    (int $tomorrowSum->{PV}).  " Wh";

  createReadings ($hash, $daref);
  
return;
}

################################################################
#                   Readings erstellen
################################################################
sub createReadings {
  my $hash  = shift;
  my $daref = shift;
  
  readingsBeginUpdate($hash);
  
  for my $elem (@$daref) {
      my ($rn,$rval) = split ":", $elem, 2;
      readingsBulkUpdate($hash, $rn, $rval);      
  }

  readingsEndUpdate($hash, 1);
  
return;
}

################################################################
#    alle Readings eines Devices oder nur Reaging-Regex 
#    löschen
################################################################
sub deleteReadingspec {
  my $hash = shift;
  my $spec = shift // ".*";
  
  my $readingspec = '^'.$spec.'$';
  
  for my $reading ( grep { /$readingspec/ } keys %{$hash->{READINGS}} ) {
      readingsDelete($hash, $reading);
  }
  
return;
}

######################################################################################
#                   NOTIFYDEV erstellen
######################################################################################
sub createNotifyDev {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "FHEM::SolarForecast::createNotifyDev");
  
  if($init_done == 1) {
      my @nd;
      my ($a,$h);
      
      my $fcdev = ReadingsVal($name, "currentForecastDev", "");      # Forecast Device
      my $indev = ReadingsVal($name, "currentInverterDev", "");      # Inverter Device
      
      ($a,$h) = parseParams ($indev);
      $indev  = $a->[0] // "";
      
      my $medev = ReadingsVal($name, "currentMeterDev",    "");      # Meter Device
      
      ($a,$h) = parseParams ($medev);
      $medev  = $a->[0] // "";
      
      $hash->{HELPER}{INVERTERDEFTS} = time if($indev);              # Timestamp der Inverterdefinition speichern für calcVariance
      
      push @nd, $fcdev;
      push @nd, $indev;
      push @nd, $medev;
      
      $hash->{NOTIFYDEV} = join ",", @nd if(@nd);
  } 
  else {
      InternalTimer(gettimeofday()+3, "FHEM::SolarForecast::createNotifyDev", $hash, 0);
  }
  
return;
}

1;

=pod
=item summary    Visualization of solar predictions for PV systems
=item summary_DE Visualisierung von solaren Vorhersagen für PV Anlagen

=begin html


=end html
=begin html_DE

<a name="SolarForecast"></a>
<h3>SolarForecast</h3>

<br>
Das Modul SolarForecast erstellt auf Grundlage der Werte aus Devices vom Typ DWD_OpenData sowie weiteren Input-Devices eine 
Vorhersage für den solaren Ertrag und weitere Informationen als Grundlage für abhängige Steuerungen. <br>
Die Solargrafik kann ebenfalls in FHEM Tablet UI mit dem 
<a href="https://wiki.fhem.de/wiki/FTUI_Widget_SolarForecast">"SolarForecast Widget"</a> integriert werden. <br><br>

Die solare Vorhersage basiert auf der durch den Deutschen Wetterdienst (DWD) prognostizierten Globalstrahlung am 
Anlagenstandort. Im zugeordneten DWD_OpenData Device ist die passende Wetterstation mit dem Attribut "forecastStation" 
festulegen um eine Prognose für diesen Standort zu erhalten. <br>
Abhängig von der physikalischen Anlagengestaltung (Ausrichtung, Winkel, Aufteilung in mehrere Strings, u.a.) wird die 
verfügbare Globalstrahlung ganz spezifisch in elektrische Energie umgewandelt. 
Um eine Anpassung an die persönliche Anlage zu ermöglichen, können Korrekturfaktoren manuell 
(set &lt;name&gt; pvCorrectionFactor_XX) oder automatisiert (set &lt;name&gt; pvCorrectionFactor_Auto) eingefügt werden.

<ul>
  <a name="SolarForecastdefine"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
    Ein SolarForecast Device wird einfach erstellt mit: <br><br>
    
    <ul>
      <b>define &lt;name&gt; SolarForecast </b>
    </ul>
    <br>
    
    Nach der Definition des Devices ist zwingend ein Vorhersage-Device des Typs DWD_OpenData zuzuordnen sowie weitere 
    anlagenspezifische Angaben mit dem entsprechenden set-Kommando vorzunehmen. Empfohlen wird ebenfalls ein Inverter-Device 
    des Typs SMAInverter zuzuordnen um eine automatische Vorhersagekorrektur zu ermöglichen (Auto Learning Mode). 
 
    <br><br>
  </ul>

  <a name="SolarForecastset"></a>
  <b>Set</b> 
  <ul>
    <ul>
      <a name="forecastDevice"></a>
      <li><b>forecastDevice </b> <br> 
      Legt das Device (Typ DWD_OpenData) fest, welches die Daten der solaren Vorhersage liefert. Ist noch kein Device dieses Typs
      vorhanden, muß es manuell definiert werden (siehe <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      Im ausgewählten DWD_OpenData Device müssen mindestens diese Attribute gesetzt sein: <br><br>

      <ul>
         <table>  
         <colgroup> <col width=35%> <col width=65%> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                  </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>Rad1h,TTT,Neff,R600,ww,SunUp,SunRise,SunSet        </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                  </td></tr>         
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Stationscode der ausgewerteten DWD Station&gt; </td></tr>
         </table>
      </ul>
      <br>

      <b>Hinweis:</b> Die ausgewählte forecastStation muß Strahlungswerte (Rad1h Readings) liefern.       
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="inverterDevice"></a>
      <li><b>inverterDevice &lt;Inverter Device Name&gt; pv=&lt;Reading aktuelle PV-Leistung&gt;:&lt;Einheit&gt; etoday=&lt;Reading Energieerzeugung aktueller Tag&gt;:&lt;Einheit&gt;  </b> <br> 
      Legt ein beliebiges Device zur Lieferung der aktuellen PV Erzeugungswerte fest. 
      Es ist anzugeben, welche Readings die aktuelle PV-Leistung und die erzeugte Energie des aktuellen Tages liefern sowie deren Einheit (W,kW,Wh,kWh).
      <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; inverterDevice STP5000 pv=total_pac:kW etoday=etoday:kWh <br>
        # Device STP5000 liefert PV-Werte. Die aktuell erzeugte Leistung im Reading "total_pac" (kW) und die tägliche Energie im 
          Reading "etoday" (kWh)
      </ul>
      </li>
    </ul>
    <br>
  
    <ul>
      <a name="inverterEfficiency"></a>
      <li><b>inverterEfficiency &lt;Zahl&gt; </b> <br> 
      Wirkungsgrad des Wechselrichters (inverterDevice) in %. <br>
      (default: 98.3)      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="meterDevice"></a>
      <li><b>meterDevice &lt;Meter Device Name&gt; gcon=&lt;Reading aktueller Netzbezug&gt;:&lt;Einheit&gt; </b> <br> 
      Legt ein beliebiges Device zur Messung des aktuellen Energiebezugs fest. 
      Es ist das Reading anzugeben welches die aktuell aus dem Netz bezogene Leistung liefert sowie dessen Einheit (W,kW).
      <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; meterDevice SMA_Energymeter gcon=Bezug_Wirkleistung:W <br>
        # Device SMA_Energymeter liefert den aktuellen Netzbezug im Reading "Bezug_Wirkleistung" (W)
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="moduleArea"></a>
      <li><b>moduleArea &lt;Zahl&gt; </b> <br> 
      Gesamte installierte Solarmodulfläche in qm.       
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="moduleEfficiency"></a>
      <li><b>moduleEfficiency &lt;Zahl&gt; </b> <br> 
      Wirkungsgrad der Solarmodule in %.  <br>
      (default: 16.52)      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="pvCorrectionFactor_Auto"></a>
      <li><b>pvCorrectionFactor_Auto &lt;on | off&gt; </b> <br> 
      Schaltet die automatische Vorhersagekorrektur ein / aus. <br>
      Ist die Automatik eingeschaltet, wird nach einer Mindestlaufzeit von FHEM bzw. des Moduls von 24 Stunden für jede Stunde 
      ein Korrekturfaktor der Solarvorhersage berechnet und auf die Erwartung des kommenden Tages angewendet.
      Dazu wird die tatsächliche Energierzeugung mit dem vorhergesagten Wert des aktuellen Tages und Stunde vergleichen und
      daraus eine Korrektur abgeleitet. <br>      
      (default: off)      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="pvCorrectionFactor_XX"></a>
      <li><b>pvCorrectionFactor_XX &lt;Zahl&gt; </b> <br> 
      Manueller Korrekturfaktor für die Stunde XX des Tages zur Anpassung der Vorhersage an die individuelle Anlage. <br>
      (default: 1.0)      
      </li>
    </ul>
    <br>
  
  </ul>
  <br>
  
  <a name="SolarForecastget"></a>
  <b>Get</b> 
  <ul>
    <ul>
      <a name="html"></a>
      <li><b>html </b> <br>  
      Die Solar Grafik wird als HTML-Code abgerufen und wiedergegeben.
      </li>      
    </ul>
    <br>
    
    <ul>
      <a name="data"></a>
      <li><b>data </b> <br>  
      Startet die Datensammlung zur Bestimmung der solaren Vorhersage und anderer Werte.
      </li>      
    </ul>
    <br>
    
  </ul>
  <br>

  <a name="SolarForecastattr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
     <ul>
        <a name="alias"></a>
        <li><b>alias </b><br>
          In Verbindung mit "showLink" ein beliebiger Abzeigename.
        </li>
        <br>  
       
       <a name="autoRefresh"></a>
       <li><b>autoRefresh</b><br>
         Wenn gesetzt, werden aktive Browserseiten des FHEMWEB-Devices welches das SolarForecast-Device aufgerufen hat, nach der 
         eingestellten Zeit (Sekunden) neu geladen. Sollen statt dessen Browserseiten eines bestimmten FHEMWEB-Devices neu 
         geladen werden, kann dieses Device mit dem Attribut "autoRefreshFW" festgelegt werden.
       </li>
       <br>
    
       <a name="autoRefreshFW"></a>
       <li><b>autoRefreshFW</b><br>
         Ist "autoRefresh" aktiviert, kann mit diesem Attribut das FHEMWEB-Device bestimmt werden dessen aktive Browserseiten
         regelmäßig neu geladen werden sollen.
       </li>
       <br>
    
       <a name="beamColor"></a>
       <li><b>beamColor </b><br>
         Farbauswahl der primären Balken.  
       </li>
       <br>
       
       <a name="beamColor2"></a>
       <li><b>beamColor2 </b><br>
         Farbauswahl der sekundären Balken. Die zweite Farbe ist nur sinnvoll für den Anzeigedevice-Typ "Generation_Consumption" 
         (pvco) und "Differential" (diff).
       </li>
       <br>  
       
       <a name="beamHeight"></a>
       <li><b>beamHeight &lt;value&gt; </b><br>
         Höhe der Balken in px und damit Bestimmung der gesammten Höhe.
         In Verbindung mit "hourCount" lassen sich damit auch recht kleine Grafikausgaben erzeugen. <br>
         (default: 200)
       </li>
       <br>
       
       <a name="beamWidth"></a>
       <li><b>beamWidth &lt;value&gt; </b><br>
         Breite der Balken in px. <br>
         (default: 6 (auto))
       </li>
       <br>  

       <a name="consumerList"></a>
       <li><b>consumerList &lt;Verbraucher1&gt;:&lt;Icon&gt;@&lt;Farbe&gt;,&lt;Verbraucher2&gt;:&lt;Icon&gt;@&lt;Farbe&gt;,...</b><br>
         Komma getrennte Liste der am SMA Sunny Home Manager angeschlossenen Geräte. <br>
         Sobald die Aktivierung einer der angegebenen Verbraucher geplant ist, wird der geplante Zeitraum in der Grafik 
         angezeigt. 
         Der Name des Verbrauchers muss dabei dem Namen im Reading "L3_&lt;Verbrauchername&gt;_Planned" entsprechen. <br><br>
       
         <b>Beispiel: </b> <br>
         attr &lt;name&gt; consumerList Trockner:scene_clothes_dryer@yellow,Waschmaschine:scene_washing_machine@lightgreen,Geschirrspueler:scene_dishwasher@orange
         <br>
       </li>
       <br>  
           
       <a name="consumerLegend"></a>
       <li><b>consumerLegend &ltnone | icon_top | icon_bottom | text_top | text_bottom&gt; </b><br>
         Lage bzw. Art und Weise der angezeigten Verbraucherlegende.
       </li>
       <br>       
  
       <a name="disable"></a>
       <li><b>disable</b><br>
         Aktiviert/deaktiviert das Device.
       </li>
       <br>
     
       <a name="forcePageRefresh"></a>
       <li><b>forcePageRefresh</b><br>
         Das Attribut wird durch das SMAPortal-Device ausgewertet. <br>
         Wenn gesetzt, wird ein Reload aller Browserseiten mit aktiven FHEMWEB-Verbindungen nach dem Update des 
         Eltern-SMAPortal-Devices erzwungen.    
       </li>
       <br>
       
       <a name="headerAlignment"></a>
       <li><b>headerAlignment &lt;center | left | right&gt; </b><br>
         Ausrichtung der Kopfzeilen. <br>
         (default: center)
       </li>
       <br>
       
       <a name="headerDetail"></a>
       <li><b>headerDetail &lt;all | co | pv | pvco | statusLink&gt; </b><br>
         Detailiierungsgrad der Kopfzeilen. <br>
         (default: all)
         
         <ul>   
         <table>  
         <colgroup> <col width=15%> <col width=85%> </colgroup>
            <tr><td> <b>all</b>        </td><td>Anzeige Erzeugung (PV), Verbrauch (CO), Link zur Device Detailanzeige + Aktualisierungszeit (default) </td></tr>
            <tr><td> <b>co</b>         </td><td>nur Verbrauch (CO)                                                                                    </td></tr>
            <tr><td> <b>pv</b>         </td><td>nur Erzeugung (PV)                                                                                    </td></tr>
            <tr><td> <b>pvco</b>       </td><td>Erzeugung (PV) und Verbrauch (CO)                                                                     </td></tr>         
            <tr><td> <b>statusLink</b> </td><td>Link zur Device Detailanzeige + Aktualisierungszeit                                                   </td></tr>
         </table>
         </ul>       
       </li>
       <br>                                      
       
       <a name="hourCount"></a>
       <li><b>hourCount &lt;4...24&gt; </b><br>
         Anzahl der Balken/Stunden. <br>
         (default: 24)
       </li>
       <br>
       
       <a name="hourStyle"></a>
       <li><b>hourStyle </b><br>
         Format der Zeitangabe. <br><br>
       
       <ul>   
         <table>  
           <colgroup> <col width=10%> <col width=90%> </colgroup>
           <tr><td> <b>nicht gesetzt</b>  </td><td>- nur Stundenangabe ohne Minuten (default)</td></tr>
           <tr><td> <b>:00</b>            </td><td>- Stunden sowie Minuten zweistellig, z.B. 10:00 </td></tr>
           <tr><td> <b>:0</b>             </td><td>- Stunden sowie Minuten einstellig, z.B. 8:0 </td></tr>
         </table>
       </ul>       
       </li>
       <br>
       
       <a name="interval"></a>
       <li><b>interval &lt;Sekunden&gt; </b><br>
         Zeitintervall der Datensammlung. <br>
         Ist interval explizit auf "0" gesetzt, erfolgt keine automatische Datensammlung und muss mit "get &lt;name&gt; data" 
         manuell erfolgen. <br>
         (default: 70)
       </li><br>
 
       <a name="maxPV"></a>
       <li><b>maxPV &lt;0...val&gt; </b><br>
         Maximaler Ertrag in einer Stunde zur Berechnung der Balkenhöhe. <br>
         (default: 0 -> dynamisch)
       </li>
       <br>
       
       <a name="htmlStart"></a>
       <li><b>htmlStart &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der vor dem Grafik-Code ausgeführt wird. 
       </li>
       <br>

       <a name="htmlEnd"></a>
       <li><b>htmlEnd &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der nach dem Grafik-Code ausgeführt wird. 
       </li>
       <br> 
   
       <a name="showDiff"></a>
       <li><b>showDiff &lt;no | top | bottom&gt; </b><br>
         Zusätzliche Anzeige der Differenz "Ertrag - Verbrauch" wie beim Anzeigetyp Differential (diff). <br>
         (default: no)
       </li>
       <br>
       
       <a name="showHeader"></a>
       <li><b>showHeader </b><br>
         Anzeige der Kopfzeile mit Prognosedaten, Rest des aktuellen Tages und des nächsten Tages <br>
         (default: 1)
       </li>
       <br>
       
       <a name="showLink"></a>
       <li><b>showLink </b><br>
         Anzeige des Detail-Links über dem Grafik-Device <br>
         (default: 1)
       </li>
       <br>
       
       <a name="showNight"></a>
       <li><b>showNight </b><br>
         Die Nachtstunden (ohne Ertragsprognose) werden mit angezeigt. <br>
         (default: 0)
       </li>
       <br>

       <a name="showWeather"></a>
       <li><b>showWeather </b><br>
         Wettericons anzeigen. <br>
         (default: 1)
       </li>
       <br> 
       
       <a name="spaceSize"></a>
       <li><b>spaceSize &lt;value&gt; </b><br>
         Legt fest wieviel Platz in px über oder unter den Balken (bei Anzeigetyp Differential (diff)) zur Anzeige der 
         Werte freigehalten wird. Bei Styles mit große Fonts kann der default-Wert zu klein sein bzw. rutscht ein 
         Balken u.U. über die Grundlinie. In diesen Fällen bitte den Wert erhöhen. <br>
         (default: 24)
       </li>
       <br> 
       
       <a name="consumerAdviceIcon"></a>
       <li><b>consumerAdviceIcon </b><br>
         Setzt das Icon zur Darstellung der Zeiten mit Verbraucherempfehlung. 
         Dazu kann ein beliebiges Icon mit Hilfe der Standard "Select Icon"-Funktion (links unten im FHEMWEB) direkt ausgewählt 
         werden. 
       </li>  
       <br>

       <a name="layoutType"></a>
       <li><b>layoutType &lt;pv | co | pvco | diff&gt; </b><br>
       Layout der Portalgrafik. <br>
       (default: pv)  
       <br><br>
       
       <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>pv</b>    </td><td>- Erzeugung </td></tr>
          <tr><td> <b>co</b>    </td><td>- Verbrauch </td></tr>
          <tr><td> <b>pvco</b>  </td><td>- Erzeugung und Verbrauch </td></tr>
          <tr><td> <b>diff</b>  </td><td>- Differenz von Erzeugung und Verbrauch </td></tr>
       </table>
       </ul>
       </li>
       <br> 
       
       <a name="Wh/kWh"></a>
       <li><b>Wh/kWh &lt;Wh | kWh&gt; </b><br>
         Definiert die Anzeigeeinheit in Wh oder in kWh auf eine Nachkommastelle gerundet. <br>
         (default: W)
       </li>
       <br>   

       <a name="weatherColor"></a>
       <li><b>weatherColor </b><br>
         Farbe der Wetter-Icons.
       </li>
       <br>        

     </ul>
  </ul>
  
</ul>

=end html_DE

=for :application/json;q=META.json 76_SolarForecast.pm
{
  "abstract": "Visualization of solar predictions for PV systems",
  "x_lang": {
    "de": {
      "abstract": "Visualisierung von solaren Vorhersagen für PV Anlagen"
    }
  },
  "keywords": [
    "sma",
    "photovoltaik",
    "electricity",
    "portal",
    "smaportal",
    "graphics",
    "longpoll",
    "refresh"
  ],
  "version": "v1.1.1",
  "release_status": "testing",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "Time::HiRes": 0        
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut

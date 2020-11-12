#########################################################################################################################
# $Id: 76_SMAPortal.pm 23105 2020-11-05 22:24:21Z DS_Starter $
#########################################################################################################################
#       76_SMAPortal.pm
#
#       (c) 2019-2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This module can be used to get data from SMA Portal https://www.sunnyportal.com/Templates/Start.aspx .
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
#       Credits (Thanks to all!):
#           Brun von der Gönne <brun at goenne dot de> :  author of 98_SHM.pm
#           BerndArnold                                :  author of 98_SHMForecastRelative.pm / add get statistic data
#           Wzut/XGuide                                :  creation of SMAPortal graphics
#       
#       FHEM Forum: http://forum.fhem.de/index.php/topic,27667.0.html 
#
#########################################################################################################################
#
# Definition: define <name> SMAPortal
#
#########################################################################################################################
package FHEM::SMAPortal;                               ## no critic 'package'
use strict;
use warnings;
use GPUtils qw(GP_Import GP_Export);                   # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use POSIX;
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;      ## no critic 'eval'
use Data::Dumper;
use Blocking;
use Time::HiRes qw(gettimeofday time sleep);
use Time::Local;
use LWP::UserAgent;
use HTTP::Cookies;
use JSON qw(decode_json);
use MIME::Base64;
use Encode;
use utf8;

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          attr
          AnalyzePerlCommand
          AttrVal
          AttrNum
          addToDevAttrList
          addToAttrList
          BlockingCall
          BlockingKill
          BlockingInformParent
          CommandAttr
          CommandDefine
          CommandDeleteAttr
          CommandDeleteReading
          CommandSet
          CommandGet
          defs
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          Debug
          FmtDateTime
          FmtTime
          fhemTzOffset
          FW_makeImage
          fhemTimeGm
          fhemTimeLocal
          getKeyValue
          gettimeofday
          genUUID
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3    
          makeReadingName          
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
          TimeNow
          Value
          json2nameValue
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
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/gx;
  #     for (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
        )
  );  
  
}

# Versions History intern
my %vNotesIntern = (
  "9.9.9"  => "12.11.2020  Studieb Kamik ",
  "3.6.4"  => "11.11.2020  preselect the user agent randomly, set min. interval to 180 s ",
  "3.6.3"  => "05.11.2020  fix only four consumer are shown in set command drop down list ",
  "3.6.2"  => "03.11.2020  new function _detailViewOn to Switch the detail view on SMA energy balance site, new default userAgent ",
  "3.6.1"  => "31.10.2020  adjust anchortime in getBalanceMonthData ",
  "3.6.0"  => "11.10.2020  new relative time arguments for attr balanceDay, balanceMonth, balanceYear, new attribute useRelativeNames ",
  "3.5.0"  => "10.10.2020  _getLiveData: get data from Dashboard instead of homemanager site depending of attr noHomeManager, ".
                           "extract OperationHealth key, new attr cookieDelete ",
  "3.4.1"  => "18.08.2020  add selected providerlevel to deletion blacklist # Forum: https://forum.fhem.de/index.php/topic,102112.msg1078990.html#msg1078990 ",
  "3.4.0"  => "09.08.2020  attr balanceDay, balanceMonth, balanceYear for data provider balanceDayData, balanceMonthData, balanceYearData ".
                           "set getData command, update button in header of PortalAsHtml, minor code changes according PBP",
  "3.3.4"  => "12.07.2020  fix break in header if attribute hourCount was reduced ",
  "3.3.3"  => "07.07.2020  change extractLiveData, minor fixes ",
  "3.3.2"  => "05.07.2020  change timeout calc, new reading lastSuccessTime ",
  "3.3.1"  => "03.07.2020  change retry repetition and new cycle wait time ",
  "3.3.0"  => "02.07.2020  fix typo, new attribute noHomeManager ",
  "3.2.0"  => "30.06.2020  add data provider balanceCurrentData (experimental), balanceMonthData, balanceYearData ",
  "3.1.2"  => "25.06.2020  don't delete cookie after every data retrieval, change login management ",
  "3.1.1"  => "24.06.2020  change german Error regex, get plantOid from cookie if not in JSON ",
  "3.1.0"  => "20.06.2020  language of SMA Portal messages depend on global language attribute, avoid order problems by ".
                           "executing retrieve master data firstly every time",
  "3.0.0"  => "18.06.2020  refactored readings and subroutines, detailLevel deleted, new attr providerLevel, integrate logbook data ",
  "2.10.6" => "12.06.2020  add hash dataprovider ",
  "2.10.5" => "12.06.2020  add check login by /Templates/, deeper/mulitple choice verbose5Data ",
  "2.10.4" => "11.06.2020  additional L1 Readings for Battery and more ",
  "2.10.3" => "11.06.2020  internal code changes, bug fixes show weather_icon ",
  "2.10.2" => "10.06.2020  bug fixes get/switch consumers ",
  "2.10.1" => "08.06.2020  internal code changes, bug fixes ",
  "2.10.0" => "03.06.2020  refactored login process ",
  "2.9.0"  => "01.06.2020  add get today statistic data ",
  "2.8.1"  => "31.05.2020  attribute timeout, maxCallCycle deleted ",
  "2.8.0"  => "31.05.2020  refactored process logic, attribute cookielifetime & getDataRetries deleted, command delCookieFile deleted ".
                           "new attribute maxCallCycle ",
  "2.7.2"  => "28.05.2020  delete cookie file if threshold of read retries reached ",
  "2.7.1"  => "28.05.2020  change cookie default location to ./log/<name>_cookie.txt ",
  "2.7.0"  => "27.05.2020  improve stability of data retrieval, new command delCookieFile, new readings dailyCallCounter and dailyIssueCookieCounter ".
                           "current PV generation and consumption available in SMA graphics, some more improvements ",
  "2.6.1"  => "21.04.2020  update time in portalgraphics changed to last successful live data retrieval, credentials are not shown in list device ",  
  "2.6.0"  => "20.04.2020  change package config, improve cookie management, decouple switch consumers from livedata retrieval ".
                           "some improvements according to PBP ",
  "2.5.0"  => "25.08.2019  change switch consumer to on<->automatic only in graphic overview, Forum: https://forum.fhem.de/index.php/topic,102112.msg969002.html#msg969002",
  "2.4.5"  => "22.08.2019  fix some warnings, Forum: https://forum.fhem.de/index.php/topic,102112.msg968829.html#msg968829 ",
  "2.4.4"  => "11.07.2019  fix consinject to show multiple consumer icons if planned ",
  "2.4.3"  => "07.07.2019  change header design of portal graphics again ",
  "2.4.2"  => "02.07.2019  change header design of portal graphics ",
  "2.4.1"  => "01.07.2019  replace space in consumer name by a valid sign for reading creation ",
  "2.4.0"  => "26.06.2019  support for FTUI-Widget ",
  "2.3.7"  => "24.06.2019  replace suggestIcon by consumerAdviceIcon ",
  "2.3.6"  => "21.06.2019  revise commandref ",                        
  "2.3.5"  => "20.06.2019  subroutine consinject added to pv, pvco style ",
  "2.3.4"  => "19.06.2019  change some readingnames, delete L4_plantOid, next04hours_state ",
  "2.3.3"  => "16.06.2019  change verbose 4 output, fix warning if no weather info was got ",
  "2.3.2"  => "14.06.2019  add request string to verbose 5, add battery data to live and historical consumer data ",
  "2.3.1"  => "13.06.2019  switch Credentials read from RAM to verbose 4, changed W/h->Wh and kW/h->kWh in PortalAsHtml ",
  "2.3.0"  => "12.06.2019  add set on,off,automatic cmd for controlled devices ",
  "2.2.0"  => "10.06.2019  relocate RestOfDay and Tomorrow data from level 3 to level 2, change readings to start all with uppercase, ".
                           "add consumer energy data of current day/month/year, new attribute \"verbose5Data\" ",
  "2.1.2"  => "08.06.2019  correct planned time of consumer in PortalAsHtml if planned time is at next day ",
  "2.1.1"  => "08.06.2019  add units to values, some bugs fixed ",
  "2.1.0"  => "07.06.2019  add informations about consumer switch and power state ",
  "2.0.0"  => "03.06.2019  designed for SMAPortalSPG graphics device ",
  "1.8.0"  => "27.05.2019  redesign of SMAPortal graphics by Wzut/XGuide ",
  "1.7.1"  => "01.05.2019  PortalAsHtml: use of colored svg-icons possible ",
  "1.7.0"  => "01.05.2019  code change of PortalAsHtml, new attributes \"portalGraphicColor\" and \"portalGraphicStyle\" ",
  "1.6.0"  => "29.04.2019  function PortalAsHtml ",
  "1.5.5"  => "22.04.2019  fix readings for BattryOut and BatteryIn ",
  "1.5.4"  => "26.03.2019  delete L1_InfoMessages if no info occur ",
  "1.5.3"  => "26.03.2019  delete L1_ErrorMessages, L1_WarningMessages if no errors or warnings occur ",
  "1.5.2"  => "25.03.2019  prevent module from deactivation in case of unavailable Meta.pm ",
  "1.5.1"  => "24.03.2019  fix \$VAR1 problem Forum: #27667.msg922983.html#msg922983 ",
  "1.5.0"  => "23.03.2019  add consumer data ",
  "1.4.0"  => "22.03.2019  add function extractPlantMasterData, DbLog_split, change L2 Readings ",
  "1.3.0"  => "18.03.2019  change module to use package FHEM::SMAPortal and Meta.pm, new sub setVersionInfo ",
  "1.2.3"  => "12.03.2019  make ready for 98_Installer.pm ", 
  "1.2.2"  => "11.03.2019  new Errormessage analyze added, make ready for Meta.pm ", 
  "1.2.1"  => "10.03.2019  behavior of state changed, commandref revised ", 
  "1.2.0"  => "09.03.2019  integrate weather data, minor fixes ",
  "1.1.0"  => "09.03.2019  make get data more stable, new attribute 'getDataRetries' ",
  "1.0.0"  => "03.03.2019  initial "
);

# Voreinstellungen
my $maxretries   = 6;                      # max. Anzahl Wiederholungen in einem Abruf-Zyklus
my $thold        = int($maxretries/2);     # Schwellenwert nicht erfolgreicher Leseversuche in einem Zyklus mit dem gleichen Cookie, Standard: int($maxretries/2)
my $sleepretry   = 60;                     # Sleep zwischen Data Call Retries
my $sleepexc     = 90;                     # Sleep vor neuem Cycle
my $defmaxcycles = 10;                     # Standard max. Anzahl Datenabrufzyklen

my %statkeys = (                           # Statistikdaten auszulesende Schlüssel
  Energy                => 1,
  FeedIn                => 1,
  GridConsumption       => 1,
  SelfConsumption       => 1,
  SelfSupply            => 1,
  DirectConsumption     => 1,
  TotalConsumption      => 1,
  BackupOut             => 1,
  BackupIn              => 1,
  SelfConsumptionRate   => 1,
  DirectConsumptionRate => 1,
  AutarkyRate           => 1,
);  

my %hset = (                                                                                           # Hash der Set-Funktion
  credentials         => { fn => \&_setCredentials         }, 
  getData             => { fn => \&_setGetData             },
  createPortalGraphic => { fn => \&_setCreatePortalGraphic },     
);

my %mandatory;                                                                                         # Arbeitskopie von %stpl -> abzurufenden Datenprovider Stammdaten nach Login
my %subs;                                                                                              # Arbeitskopie von %stpl -> Festlegung abzurufenden Datenprovider
my %stpl = (                                                                                           # Ausgangstemplate Subfunktionen der Datenprovider
  consumerMasterdata  => { doit => 1, nohm => 1, level => 'L00', func => '_getConsumerMasterdata'  },  # mandatory (außer wenn kein SMA Home Manager vorhanden)
  plantMasterData     => { doit => 1, nohm => 1, level => 'L00', func => '_getPlantMasterData'     },  # mandatory (außer wenn kein SMA Home Manager vorhanden)
  liveData            => { doit => 0, nohm => 0, level => 'L01', func => '_getLiveData'            },
  weatherData         => { doit => 0, nohm => 0, level => 'L02', func => '_getWeatherData'         },
  forecastData        => { doit => 0, nohm => 1, level => 'L04', func => '_getForecastData'        },
  consumerCurrentdata => { doit => 0, nohm => 1, level => 'L05', func => '_getConsumerCurrData'    },
  consumerDayData     => { doit => 0, nohm => 1, level => 'L06', func => '_getConsumerDayData'     },
  consumerMonthData   => { doit => 0, nohm => 1, level => 'L07', func => '_getConsumerMonthData'   },
  consumerYearData    => { doit => 0, nohm => 1, level => 'L08', func => '_getConsumerYearData'    },
  plantLogbook        => { doit => 0, nohm => 0, level => 'L09', func => '_getPlantLogbook'        },
  balanceDayData      => { doit => 0, nohm => 0, level => 'L11', func => '_getBalanceDayData'      },
  balanceMonthData    => { doit => 0, nohm => 0, level => 'L12', func => '_getBalanceMonthData'    },
  balanceYearData     => { doit => 0, nohm => 0, level => 'L13', func => '_getBalanceYearData'     },
  balanceTotalData    => { doit => 0, nohm => 0, level => 'L14', func => '_getBalanceTotalData'    },
);

my %hua = (                                                                                            # mögliche UserAgents für eine Round-Robin-Liste
  1  => "Mozilla/5.0 (Windows NT 10.0; rv:81.0) Gecko/20100101 Firefox/81.0", 
  2  => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.195 Safari/537.36",
  3  => "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.111 Safari/537.36",   
  4  => "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.75 Safari/537.36 Edg/86.0.622.38",	
);

                                                                   # Tags der verfügbaren Datenquellen
my @pd = qw( plantMasterData
             consumerMasterdata
             balanceDayData
             balanceMonthData
             balanceYearData
             balanceTotalData
             consumerCurrentdata             
             consumerDayData 
             consumerMonthData 
             consumerYearData           
             forecastData
             liveData
             weatherData
             plantLogbook
           );

###############################################################
#                  SMAPortal Initialize
###############################################################
sub Initialize {
  my ($hash) = @_;
  
  my @pls;
  for my $p (@pd) {
      push @pls, $p if(!$stpl{$p}{doit});
  }
  my $prov               = join ",", @pls;   
  my $v5d                = join ",", @pd;  
  
  $hash->{DefFn}         = \&Define;
  $hash->{UndefFn}       = \&Undefine;
  $hash->{DeleteFn}      = \&Delete; 
  $hash->{AttrFn}        = \&Attr;
  $hash->{SetFn}         = \&Set;
  $hash->{GetFn}         = \&Get;
  $hash->{DbLog_splitFn} = \&DbLog_split;
  $hash->{AttrList}      = "balanceDay ".
                           "balanceMonth ".
                           "balanceYear ".
                           "cookieLocation ".
                           "cookieDelete:auto,afterRun,afterCycle,afterAttempt,afterAttempt&Run ".
                           "disable:0,1 ".
                           "interval ".
                           "noHomeManager:1,0 ".
                           "plantLogbookTypes:multiple-strict,Info,Warning,Disturbance,Error ".
                           "plantLogbookApprovalState:Any,NotApproved ".
                           "providerLevel:multiple-strict,".$prov." ".
                           "showPassInLog:1,0 ".
                           "userAgent ".
                           "useRelativeNames:1,0 ".
                           "verbose5Data:multiple-strict,none,loginData,detailViewSwitch,".$v5d." ".
                           $readingFnAttributes;

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };          ## no critic 'eval' # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return; 
}

###############################################################
#                         SMAPortal Define
###############################################################
sub Define {
  my ($hash, $def) = @_;
  my @a = split(/\s+/x, $def);
  
  return "Wrong syntax: use \"define <name> SMAPortal\" " if(int(@a) < 1);

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);   # Modul Meta.pm nicht vorhanden
  
  $hash->{HELPER}{GETTER} = "all";
  $hash->{HELPER}{SETTER} = "none";
  
  setVersionInfo($hash);                                   # Versionsinformationen setzen
  getcredentials($hash,1);                                 # Credentials lesen und in RAM laden ($boot=1)
  CallInfo      ($hash);                                   # Start Daten Abrufschleife
 
return;
}

###############################################################
#                         SMAPortal Undefine
###############################################################
sub Undefine {
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  BlockingKill($hash->{HELPER}{RUNNING_PID}) if($hash->{HELPER}{RUNNING_PID});

return;
}

###############################################################
#                         SMAPortal Delete
###############################################################
sub Delete {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    my $name  = $hash->{NAME};
    
    # gespeicherte Credentials löschen
    setKeyValue($index, undef);
    
return;
}

###############################################################
#                          SMAPortal Set
###############################################################
sub Set {                             
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name  = shift @a;
  my $opt   = shift @a;
  my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
  my $prop  = shift @a;
  my $prop1 = shift @a;
  my ($setlist,@ads);
  my $ad      = "";
    
  return if(IsDisabled($name));
 
  if(!$hash->{CREDENTIALS}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
                 "credentials "
                 ;  
  } 
  else {
      # erweiterte Setlist wenn Credentials gesetzt
      $setlist = "Unknown argument $opt, choose one of ".
                 "credentials ".
                 "createPortalGraphic:Generation,Consumption,Generation_Consumption,Differential ".
                 "getData:noArg "
                 ;   
      if($hash->{HELPER}{PLANTOID} && $hash->{HELPER}{CONSUMER}) {
          for my $key (keys %{$hash->{HELPER}{CONSUMER}}) {
              my $dev = $hash->{HELPER}{CONSUMER}{$key}{DeviceName};
              if($dev) {
                  push @ads, $dev; 
                  $setlist .= "$dev ";
              }
          }
      }       
  }  
  
  if(@ads) {
      $ad = join "|", @ads;
  }
  
  my ($a,$h) = parseParams ($arg);
  my $gcval  = $h->{gcval}    // 24;                         # GridConsumptionValue
  my $pvval  = $h->{pvval}    // 76;                         # PvValue
  my $lval   = $h->{lval}     // 0;                          # LimitedEnergyValue
  
  $gcval = sprintf "%.10f", $gcval/100;
  $pvval = sprintf "%.10f", $pvval/100;
  $lval  = sprintf "%.10f", $lval/100;
  
  $gcval =~ s/\./,/x;
  $pvval =~ s/\./,/x;
  $lval  =~ s/\./,/x;
            
  if ($opt && $ad && $opt =~ /$ad/x) {
      # Verbraucher schalten
      $hash->{HELPER}{GETTER} = "none";
      $hash->{HELPER}{SETTER} = "$opt:$gcval#$pvval#$lval";
      CallInfo($hash);      
  } 
  else {
      my $params = {
          hash  => $hash,
          name  => $name,
          opt   => $opt,
          prop  => $prop,
          prop1 => $prop1,
          aref  => \@a,
      };
        
      if($hset{$opt} && defined &{$hset{$opt}{fn}}) {
          my $ret = q{};
          $ret    = &{$hset{$opt}{fn}} ($params); 
          return $ret;
      }

      return "$setlist";
  } 
  
return;
}

################################################################
#                      Setter credentials
#                    credentials speichern
################################################################
sub _setCredentials {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};

  return qq{Credentials are incomplete, use "set $name credentials <username> <password>"} if (!$prop || !$prop1);    
  my ($success) = setcredentials($hash,$prop,$prop1); 
  
  if($success) {
      delcookiefile ($hash);
      CallInfo($hash);
      return "Username and Password saved successfully";
  } 
  else {
       return "Error while saving Username / Password - see logfile for details";
  }

return;
}

################################################################
#                      Setter getData
#       identisch zu "get gata", Workaround um mit webCmd 
#       arbeiten zu können
################################################################
sub _setGetData {                        ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};

  CommandGet(undef, "$name data");

return;
}

################################################################
#                      Setter createPortalGraphic
#                 create createPortalGraphic devices
################################################################
sub _setCreatePortalGraphic {            ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};

  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
  my ($htmldev,$ret,$c,$type,$color2);
  
  if ($prop eq "Generation") {                                                      ## no critic "Cascading"
      $htmldev = "SPG1.$name";                                                      # Grafiktyp Generation (Erzeugung)
      $type    = 'pv';        
      $c       = "SMA Sunny Portal Graphics - Forecast Generation";
      $color2  = "000000";                                                          # zweite Farbe als schwarz setzen
  } 
  elsif ($prop eq "Consumption") {
      $htmldev = "SPG2.$name";                                                      # Grafiktyp Consumption (Verbrauch)
      $type    = 'co';    
      $c       = "SMA Sunny Portal Graphics - Forecast Consumption"; 
      $color2  = "000000";                                                          # zweite Farbe als schwarz setzen          
  } 
  elsif ($prop eq "Generation_Consumption") {
      $htmldev = "SPG3.$name";                                                      # Grafiktyp Generation_Consumption (Erzeugung und Verbrauch)
      $type    = 'pvco'; 
      $c       = "SMA Sunny Portal Graphics - Forecast Generation & Consumption";
      $color2  = "FF5C82";                                                          # zweite Farbe als rot setzen          
  } 
  elsif ($prop eq "Differential") {
      $htmldev = "SPG4.$name";                                                      # Grafiktyp Differential (Differenzanzeige)
      $type    = 'diff';   
      $c       = "SMA Sunny Portal Graphics - Forecast Differential";   
      $color2  = "FF5C82";                                                          # zweite Farbe als rot setzen           
  } 
  else {
      return "Invalid portal graphic devicetype ! Use one of \"Generation\", \"Consumption\", \"Generation_Consumption\", \"Differential\". "
  }

  $ret = CommandDefine($hash->{CL},"$htmldev SMAPortalSPG {FHEM::SMAPortal::PortalAsHtml ('$name','$htmldev')}");
  return $ret if($ret);
  
  CommandAttr($hash->{CL},"$htmldev alias $c");                                     # Alias setzen
  
  $c = qq{This device provides a praphical output of SMA Sunny Portal values.\n}.
       qq{It is important that a SMA Home Manager is installed. Otherwise no forecast data are provided by SMA!\n}.      
       qq{The device "$name" needs to contain "forecastData" in attribute "providerLevel".\n}.
       qq{The attribute "providerLevel" must also contain "consumerCurrentdata" if you want switch your consumer connectet to the SMA Home Manager.};
  
  CommandAttr($hash->{CL},"$htmldev comment $c");     

  # es muß nicht unbedingt jedes der möglichen userattr unbedingt vorbesetzt werden
  # bzw muß überhaupt hier etwas vorbesetzt werden ?
  # alle Werte enstprechen eh den AttrVal/ AttrNum default Werten
  
  CommandAttr($hash->{CL},"$htmldev hourCount 24");
  CommandAttr($hash->{CL},"$htmldev consumerAdviceIcon on");
  CommandAttr($hash->{CL},"$htmldev showHeader 1");
  CommandAttr($hash->{CL},"$htmldev showLink 1");
  CommandAttr($hash->{CL},"$htmldev spaceSize 24");
  CommandAttr($hash->{CL},"$htmldev showWeather 1");
  CommandAttr($hash->{CL},"$htmldev layoutType $type");                             # Anzeigetyp setzen

  # eine mögliche Startfarbe steht beim installiertem f18 Style direkt zur Verfügung
  # ohne vorhanden f18 Style bestimmt später tr.odd aus der Style css die Anfangsfarbe
  my $color;
  my $jh = json2nameValue(AttrVal('WEB','styleData',''));
  if($jh && ref $jh eq "HASH") {
      $color = $jh->{'f18_cols.header'};
  }
  if (defined($color)) {
      CommandAttr($hash->{CL},"$htmldev beamColor $color");
  }
  
  # zweite Farbe setzen
  CommandAttr($hash->{CL},"$htmldev beamColor2 $color2");

  my $room = AttrVal($name,"room","SMAPortal");
  CommandAttr($hash->{CL},"$htmldev room $room");
  
return "SMA Portal Graphics device \"$htmldev\" created and assigned to room \"$room\".";
}

###############################################################
#                          SMAPortal Get
###############################################################
sub Get {
 my ($hash, @a) = @_;
 return "\"get X\" needs at least an argument" if ( @a < 2 );
 my $name = shift @a;
 my $opt  = shift @a;
   
 my $getlist = "Unknown argument $opt, choose one of ".
               "storedCredentials:noArg ".
               "data:noArg ";
                   
 return "module is disabled" if(IsDisabled($name));
  
 if ($opt eq "data") {
     $hash->{HELPER}{GETTER} = "all";
     $hash->{HELPER}{SETTER} = "none";
     
     CallInfo($hash);
 } 
 elsif ($opt eq "storedCredentials") {
        if(!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials &lt;username&gt; &lt;password&gt;\"";}
        # Credentials abrufen
        my ($success, $username, $password) = getcredentials($hash,0);
        unless ($success) {return "Credentials couldn't be retrieved successfully - see logfile"};
        
        return "Stored Credentials to access SMA Portal:\n".
               "========================================\n".
               "Username: $username, Password: $password\n".
               "\n";               
 } 
 else {
     return "$getlist";
 } 
 
return;
}

###############################################################
#               SMAPortal DbLog_splitFn
###############################################################
sub DbLog_split {
  my ($event, $device) = @_;
  my ($reading, $value, $unit);
  
  if($event =~ /\s(Wh|W|kWh|%|h)$/xms) {
      ($reading, $value, $unit) = $event =~ /(.*):\s(.*)\s(.*)/x;
  } 
  
return ($reading, $value, $unit);
}

######################################################################################
#                            Username / Paßwort speichern
######################################################################################
sub setcredentials {
    my ($hash, @credentials) = @_;
    my $name                 = $hash->{NAME};
    my ($success, $credstr, $index, $retcode);
    my (@key,$len,$i);    
    
    $credstr = encode_base64(join(':', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len; chr((ord($_) + $key[$i]) % 256) } split //, $credstr;   ## no critic 'Map blocks';
    # End Scramble-Routine    
       
    $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 1, "$name - Error while saving the Credentials - $retcode");
        $success = 0;
    } 
    else {
        getcredentials($hash,1);                                                               # Credentials nach Speicherung lesen und in RAM laden ($boot=1)
        $success = 1;
    }

return ($success);
}

######################################################################################
#                             Username / Paßwort abrufen
######################################################################################
sub getcredentials {
    my ($hash,$boot) = @_;
    my $name         = $hash->{NAME};
    my ($success, $username, $passwd, $index, $retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot) {                                                                        # mit $boot=1 Credentials von Platte lesen und als scrambled-String in RAM legen
        $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read password from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {                                                                 # beim Boot scrambled Credentials in den RAM laden
            $hash->{HELPER}{".CREDENTIALS"} = $credstr;
    
            $hash->{CREDENTIALS} = "Set";                                               # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $success = 1;
        }
    } 
    else {                                                                              # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
        $credstr = $hash->{HELPER}{".CREDENTIALS"} // $hash->{HELPER}{CREDENTIALS};     # Kompatibilität zu Versionen vor 2.6.1 
        
        if($credstr) {
            # Beginn Descramble-Routine
            @key = qw(1 3 4 5 6 3 2 1 9); 
            $len = scalar @key;  
            $i = 0;  
            $credstr = join "",  
            map { $i = ($i + 1) % $len; chr((ord($_) - $key[$i] + 256) % 256) } split //, $credstr;   ## no critic 'Map blocks';
            # Ende Descramble-Routine
            
            ($username, $passwd) = split(":",decode_base64($credstr));
            
            my $logpw = AttrVal($name, "showPassInLog", 0) ? $passwd : "********";
        
            Log3($name, 4, "$name - Credentials read from RAM: $username $logpw");
        } 
        else {
            Log3($name, 1, "$name - Credentials not set in RAM !");
        }
        
        $success = (defined($passwd)) ? 1 : 0;
    }

return ($success, $username, $passwd);        
}

###############################################################
#                          SMAPortal Attr
###############################################################
sub Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
    
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do  = 0 if($cmd eq "del");
        $val = ($do == 1 ? "disabled" : "initialized");
        
        if($do) {
            deleteData    ($hash);
            delcookiefile ($hash); 
            delete $hash->{MODE};
            RemoveInternalTimer($hash);                      
        } 
        else {
            InternalTimer(gettimeofday()+1.0, "FHEM::SMAPortal::CallInfo", $hash, 0);
        }
        
        readingsBeginUpdate($hash);
        readingsBulkUpdate ($hash, "state",           $val);
        readingsBulkUpdate ($hash, "loginState", "unknown");
        readingsEndUpdate  ($hash, 1);
        
        InternalTimer(gettimeofday()+2.0, "FHEM::SMAPortal::SPGRefresh", "$name,0,1", 0);
    }
    
    if ($cmd eq "set") {
        if ($aName eq "interval") {
            unless ($aVal =~ /^\d+$/x) {return "The value for $aName is not valid. Use only figures 0-9 !";}
            return qq{The interval must be >= 180 seconds or 0 if you don't want use automatic updates} if($aVal > 0 && $aVal < 180);
            InternalTimer(gettimeofday()+1.0, "FHEM::SMAPortal::CallInfo", $hash, 0);
        }          
    }

return;
}

################################################################
#               Hauptschleife BlockingCall
#   $hash->{HELPER}{GETTER} -> Flag für get Informationen
#   $hash->{HELPER}{SETTER} -> Parameter für set-Befehl
#   $nc = 1 weiterer Cycle (Cycle Zähler nicht zurücksetzten)
#   $nr = 1 weiterer Retry (Zähler nicht zurücksetzten)
################################################################
sub CallInfo {                         ## no critic 'complexity'
  my ($hash,$nc,$nr) = @_;
  my $name           = $hash->{NAME};
  my $new;
  
  RemoveInternalTimer($hash,"FHEM::SMAPortal::CallInfo");
  
  my ($interval,$maxcycles,$timeout) = controlParams ($name);
  
  if($init_done == 1) {
      if(!$hash->{CREDENTIALS}) {
          Log3($name, 1, "$name - Credentials not set. Set it with \"set $name credentials <username> <password>\""); 
          readingsSingleUpdate($hash, "state", "Credentials not set", 1);    
          return;          
      }
      
      if(!$interval) {
          $hash->{MODE} = "Manual";
      } 
      else {
          $new = gettimeofday()+$interval; 
          InternalTimer($new, "FHEM::SMAPortal::CallInfo", $hash, 0);          # Wiederholungsintervall
          $hash->{MODE} = "Automatic - next polltime: ".FmtTime($new);
      }

      return if(IsDisabled($name));
      
      for my $key (keys %stpl) {                                               # festlegen welche Daten geliefert werden sollen
          if($stpl{$key}{doit}) {                                              # Datenprovider nach Login ausführen (mandatories)
              $mandatory{$name}{$key}{doit}  = $stpl{$key}{doit};        
              $mandatory{$name}{$key}{level} = $stpl{$key}{level};
              $mandatory{$name}{$key}{func}  = $stpl{$key}{func}; 
              next;
          }                                       
          $subs{$name}{$key}{doit}  = $stpl{$key}{doit};
          $subs{$name}{$key}{level} = $stpl{$key}{level};
          $subs{$name}{$key}{func}  = $stpl{$key}{func};
      }
      
      my @pl = split ",", AttrVal($name, "providerLevel", "");
      for my $p (@pl) {
          $subs{$name}{$p}{doit} = 1;
      }
      
      if ($hash->{HELPER}{RUNNING_PID}) {
          Log3 ($name, 3, "$name - An old data cycle is still running, the new data cycle start is postponed.");
          return;
      } 
      
      my $getp = $hash->{HELPER}{GETTER};
      my $setp = $hash->{HELPER}{SETTER};
     
      if(!$nc && !$nr) {
          Log3 ($name, 3, "$name - ################################################################");
          Log3 ($name, 3, "$name - ###      start new set/get data from SMA Sunny Portal        ###");
          Log3 ($name, 3, "$name - ################################################################"); 
          Log3 ($name, 5, "$name - SMAPortal version:          $hash->{HELPER}{VERSION}");
          Log3 ($name, 4, "$name - calculated maximum cycles:  $maxcycles");
          Log3 ($name, 4, "$name - calculated timeout:         $timeout");
      }
      
      if(AttrVal($name, "noHomeManager", 0)) {                                 # wenn kein Home Manager installiert ist keine mandatories ausführen
          %mandatory = ();
          for my $k (keys %stpl) {
              if($stpl{$k}{nohm}) {
                  $subs{$name}{$k}{doit} = 0; 
                  Log3 ($name, 3, qq{$name - ignore provider "$k" - SMA Home Manager is not installed}) if(!$nc && !$nr);
              }
          }
      }
      
      if(!$nc) {                                                               # kein weiterer Cycle, d.h. erster Cycle
          $hash->{HELPER}{ACTCYCLE}   = 1;
          $hash->{HELPER}{CYCLEBTIME} = (gettimeofday())[0];
      }
      else {                                                                   # es ist ein weiterer Cycle
          if(AttrVal($name, "cookieDelete", "auto") eq "afterCycle") {
              delcookiefile ($hash);
          }
      }
      
      if(!$nr) {                                                               # es ist keine weiterer Attempt, d.h. erster Attempt                                                              
          $hash->{HELPER}{RETRIES} = 1;
      }
      
      my $ac = $hash->{HELPER}{ACTCYCLE};
      
      Log3 ($name, 3, "$name - Running data cycle: $ac of $maxcycles");
      
      readingsBeginUpdate         ($hash);
      readingsBulkUpdateIfChanged ($hash,"state","running - call cycle $ac");
      readingsEndUpdate           ($hash,1); 
      
      $hash->{HELPER}{RUNNING_PID}           = BlockingCall("FHEM::SMAPortal::GetSetData", "$name|$getp|$setp", "FHEM::SMAPortal::ParseData", $timeout, "FHEM::SMAPortal::ParseAborted", $hash);
      $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
  
  } else {
      InternalTimer(gettimeofday()+5, "FHEM::SMAPortal::CallInfo", $hash, 0);
  }
    
return;  
}

################################################################
#             Steuerparameter berechnen / festlegen
################################################################
sub controlParams {
  my $name = shift;

  # Voreinstellungen
  my $timeoutdef   = 3600;                   # Standard Timeout
  my $definterval  = 300;                    # Standard Interval
  my $buffer       = 5;                      # Sicherheitspuffer zum nächsten Intervall

  my $interval     = AttrVal($name, "interval", $definterval);           # 0 wenn manuell gesteuert
  my $maxcycles    = $defmaxcycles;

return ($interval,$maxcycles,$timeoutdef);
}

################################################################
##                  Datenabruf SMA-Portal
##      schaltet auch Verbraucher des Sunny Home Managers
################################################################
sub GetSetData {                       ## no critic 'complexity'
  my ($string) = @_;
  my ($name,$getp,$setp) = split("\\|",$string);
  my $hash               = $defs{$name}; 
  my $cookieLocation     = AttrVal($name, "cookieLocation", "./log/".$name."_cookie.txt");
  my $v5d                = AttrVal($name, "verbose5Data", "none"); 
  my $verbose            = AttrVal($name, "verbose", 3);
  my $lang               = AttrVal("global", "language", "EN");
  my $state              = "ok";
  my ($st,$lc)           = ("","");
  my @da                 = ();
  
  my ($errstate,$reread,$retry,$exceed,$newcycle) = (0,0,0,0,0);
  
  my @ak           = keys %hua;                                        # UserAgent zufällig vorbelegen
  my $randomua     = $ak[rand @ak];
  my $defuseragent = $hua{$randomua};
  my $useragent    = AttrVal($name, "userAgent", $defuseragent);
  BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "usedUserAgent:$useragent", "NULL" ], 1);
  
  my %hal = (                                                          # Header Accept-Language sprachenabhängig
      "DE" => "de,en-US;q=0.7,en;q=0.3",
      "EN" => "en-US;q=0.7,en;q=0.3"
  );
 
  my ($d,$op);  
  if($setp ne "none") {
      # Verbraucher soll in den Status $op geschaltet werden
      ($d,$op) = split(":",$setp);
  }
  
  Log3 ($name, 5, "$name - Start operation with CookieLocation: $cookieLocation and UserAgent: $useragent");
  Log3 ($name, 5, "$name - data get: $getp, data set: ".(($d && $op)?($d." ".$op):$setp));
  
  my $ua = LWP::UserAgent->new;
  
  # Default Header Daten
  $ua->default_header("Accept"           => "*/*",
                      "Accept-Encoding"  => "gzip, deflate, br",
                      "Accept-Language"  => $hal{$lang},               # deutsch: de,en-US;q=0.7,en;q=0.3 , englisch: en-US;q=0.7,en;q=0.3 
                      "Connection"       => "keep-alive",
                      "Cookie"           => "collapseNavi_state=shown",
                      "DNT"              => 1,
                      "Host"             => "www.sunnyportal.com",
                      "Referer"          => "https://www.sunnyportal.com/FixedPages/HoManLive.aspx",
                      "User-Agent"       => $useragent,
                      "X-Requested-With" => "XMLHttpRequest"
                     );
  
  # Cookies
  $ua->cookie_jar(HTTP::Cookies->new( file           => "$cookieLocation",
                                      ignore_discard => 1,
                                      autosave       => 1
                                    )
                 );
  
  handleCounter ($name, "dailyCallCounter");                                          # Abfragezähler setzen (Anzahl tägliche Wiederholungen von GetSetData)

  ### Login 
  ##############
  my $paref           = [ $name, $ua, $state, $errstate ];
  ($state, $errstate) = _doLogin ($paref);

  if($errstate) {
      $st = encode_base64 ( $state,"");
      return "$name|0|0|$errstate|$getp|$setp|$st";
  }

  ### die Anlagen Asset Daten auslesen (Funktionen aus %mandatory mit doit=1)
  ### (Hash %mandatory ist leer wenn kein SMA Home Manager eingesetzt)
  ##################################################################################
  for my $k (keys %{$mandatory{$name}}) { 
      next if(!$mandatory{$name}{$k}{doit});        
      no strict "refs";                                      ## no critic 'NoStrict'  
      ($errstate,$state,$reread,$retry) = &{$mandatory{$name}{$k}{func}} ({ name  => $name,
                                                                            ua    => $ua,
                                                                            state => $state, 
                                                                            daref => \@da
                                                                         });
      use strict "refs";                                                                
      
      if($errstate) {
          $st = encode_base64 ( $state,"");
          return "$name|0|0|$errstate|$getp|$setp|$st";
      }   
  }  
  
  ### Verbraucher schalten
  #######################################
  if($setp ne "none") {                                   
      my ($serial,$id,$oid,$h);
      
      my ($gcval, $pvval, $lval) = split "#",$setp; 
      
      for my $key (keys %{$hash->{HELPER}{CONSUMER}}) {
          $h = $hash->{HELPER}{CONSUMER}{$key}{DeviceName};
          if($h && $h eq $d) {
              $serial = $hash->{HELPER}{CONSUMER}{$key}{SerialNumber};
              $id     = $hash->{HELPER}{CONSUMER}{$key}{SUSyID};
              $oid    = $hash->{HELPER}{CONSUMER}{$key}{ConsumerOid};
          }
      }
      my $plantOid = $hash->{HELPER}{PLANTOID};

  if($verbose == 5) {
      $ua->add_handler( request_send  => sub { shift->dump; return } );         # for debugging
      $ua->add_handler( response_done => sub { shift->dump; return } );
  }

      my %fields  = ("Content-Type" => "application/json; charset=utf-8");      
      my $content = {
                      'UsePriceLimit'             => qq{"False"}, 
                      'UsesCanFrames'             => qq{"True"}, 
                      'ConsumerOid'               => qq{"$oid"}, 
                      'DeviceStatus'              => qq{"DeviceActive"},
                      'DataAcceptance'            => "[…]",
                      '0'                         => qq{"true"},
                      '1'                         => qq{"false"},
                      'PowerConsumerName'         => qq{"$h"},
                      'Priority'                  => qq{"1"},
                      'RbTimeframeTypeEnergyPv_0' => qq{"pv"},
                      'MaxPriceAllowedValue'      => qq{"0,1283000000"},
                      'GridConsumptionValue'      => qq{"$gcval"},
                      'PvValue'                   => qq{"$pvval"},
                      'LimitedEnergyValue'        => qq{"$lval"},
                      'ConsumerIcon'              => qq{"/Images/DeviceIcons/ChargingStation.png"},
                      'ConsumerColor.ColorString' => qq{"rgba(49,101,255,1)"},
                    } ;
  
      my $res      = $ua->post("https://www.sunnyportal.com/HoMan/Consumer/Semp/$oid",
                                %fields,      
                                Content => $content
                              ); 
                              
  if($verbose == 5) {
      Log3 ($name, 5, "$name - Return Code: ".$res->code); 
  }
  
  $ua->remove_handler('request_send');
  $ua->remove_handler('response_done');
  
      $res = $res->decoded_content();
      Log3 ($name, 3, "$name - Set \"$d $op\" result: ".$res);
      if($res eq "true") {
          $state = "ok - switched consumer $d to $op";
          BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "NULL", "GETTER:all" ], 1);
          BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "NULL", "SETTER:none"], 1);
      } 
      else {
          $state = "Error - couldn't switch consumer $d to $op";
      }
  } 
  
  ### Daten abrufen 
  #############################
  if($getp ne "none") {            

      _detailViewOn ({ name     => $name,
                       ua       => $ua,
                       state    => $state, 
                       daref    => \@da
                    });                                      # Detailanzeige einschalten
      
      for my $k (keys %{$subs{$name}}) {
          next if(!$subs{$name}{$k}{doit});           
          
          no strict "refs";                                  ## no critic 'NoStrict'  
          
          if(!defined &{$subs{$name}{$k}{func}}) {
              Log3 ($name, 2, qq{$name - WARNING - data provider '$k' call function '$subs{$name}{$k}{func}' doesn't exist and is ignored }); 
              next;
          }            
          
          ($errstate,$state,$reread,$retry) = &{$subs{$name}{$k}{func}} ({ name     => $name,
                                                                           ua       => $ua,
                                                                           state    => $state, 
                                                                           daref    => \@da
                                                                        });
          use strict "refs";                                                                
          
          if($errstate) {
              $st = encode_base64 ( $state,"");
              return "$name|0|0|$errstate|$getp|$setp|$st";
          } 
          
          goto &GetSetData if($reread);
          
          # Wiederholung Datenabruf innerhalb eines Cycle
          my $retc = $hash->{HELPER}{RETRIES};                                                     # aktuelle Retry-Zähler
          
          if($retry && $retc < $maxretries) {                                                      # neuer Retry im gleichen Zyklus (nicht wenn Verbraucher schalten)      
              $hash->{HELPER}{RETRIES}++;
              my $cd = AttrVal($name, "cookieDelete", "auto");
			  
			  if($retc == $thold || $cd =~ /Attempt/x) {                                           # Schwellenwert Leseversuche erreicht -> Cookie File löschen
                  my $msg = qq{$name - Threshold reached, delete cookie file before retry...};
				  
				  if($cd =~ /Attempt/x) {
				      $msg = qq{$name - force delete cookie file before retry...};
				  }
				  
				  Log3 ($name, 3, $msg); 
                  sleep $sleepretry;                                                               # Threshold exceed  -> Retry mit Cookie löschen
                  $exceed = 1;
                  BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "NULL", "RETRIES:".$hash->{HELPER}{RETRIES} ], 1);
                  return "$name|$exceed|$newcycle|$errstate|$getp|$setp";                
              }
              
			  sleep $sleepretry;                                                     
              goto &GetSetData;
          }  

          # Wiederholung Datenabruf in einem neuen Cycle
          my $ac        = $hash->{HELPER}{ACTCYCLE};
          my $maxcycles = (controlParams $name)[1];
          if($retry && $ac < $maxcycles) {                                                         # neuer Zyklus (nicht wenn Verbraucher schalten)     
              Log3 ($name, 3, qq{$name - Maximum retries reached, start new data get cycle in $sleepexc seconds ...}); 
              $newcycle = 1;
              return "$name|$exceed|$newcycle|$errstate|$getp|$setp";          
          }    
      }
      
      if(!@da) {
          $state = "Warning - empty data received, values not current";
          if(AttrVal("global","language","EN") eq "DE") {
             $state = "Warnung - leere Daten empfangen, Werte nicht aktuell";
          }
      }
  }

  # Daten müssen als Einzeiler zurückgegeben werden
  $st  = encode_base64 ($state, "");
  if(@da) {
      $lc = join "###", @da;
      $lc = encode_base64 ($lc, ""); 
      Log3 ($name, 3, "$name - data retrieved successfully.");
  }

return "$name|$exceed|$newcycle|$errstate|$getp|$setp|$st|$lc";
}

################################################################
#       Login Status checken und ggf. einloggen
################################################################
sub _doLogin {
  my $paref       = shift;
  my $name        = $paref->[0];
  my $ua          = $paref->[1];
  my $state       = $paref->[2];
  my $errstate    = $paref->[3];

  my $hash     = $defs{$name};
  my $v5d      = AttrVal($name, "verbose5Data", "none");  
  my $verbose  = AttrVal($name, "verbose", 3);
  
  if($verbose == 5 && $v5d =~ /loginData/) {
      $ua->add_handler( request_send  => sub { shift->dump; return } );         # for debugging
      $ua->add_handler( response_done => sub { shift->dump; return } );
  }
  
  my ($success, $username, $password) = getcredentials($hash,0);                # gespeicherte Credentials abrufen
  
  my $loginp   = $ua->post('https://www.sunnyportal.com/Templates/Start.aspx');
  my $retcode  = $loginp->code;
  my $location = $loginp->header('Location')   // "";
  my $cookie   = $loginp->header('Set-Cookie') // "";
  
  if ($loginp->is_success) {
      if($v5d =~ /loginData/) {
          Log3 ($name, 5, "$name - Status Login Page: ".$loginp->status_line);
          Log3 ($name, 5, "$name - Header Location: ".  $location);
          Log3 ($name, 5, "$name - Header Set-Cookie: ".$cookie);
      }
  
      $retcode  = $loginp->code;
      $location = $loginp->header('Location') // "";
      
      if(!__isLoggedIn ($name,$username,$loginp)) {                                                # keine aktive Session -> neuer Login
          Log3 ($name, 4, "$name - User not logged in. Try login with credentials ...");
      
          if(!$success) {
              Log3($name, 1, qq{$name - Credentials couldn't be retrieved successfully - make sure you've set it with "set $name credentials <username> <password>"});   
              $state       = "Credentials couldn't be read";
              $errstate = 1;
          } 
          else {
              my $usernameField = "ctl00\$ContentPlaceHolder1\$Logincontrol1\$txtUserName";
              my $passwordField = "ctl00\$ContentPlaceHolder1\$Logincontrol1\$txtPassword";
              my $mempasswd     = "ctl00\$ContentPlaceHolder1\$Logincontrol1\$MemorizePassword";
              my $loginField    = "__EVENTTARGET";
              my $loginButton   = "ctl00\$ContentPlaceHolder1\$Logincontrol1\$LoginBtn";   

              $loginp   = $ua->post('https://www.sunnyportal.com/Templates/Start.aspx',[$usernameField => $username, $passwordField => $password, $mempasswd => "on", "__EVENTTARGET" => $loginButton]);
              $retcode  = $loginp->code;
              $location = $loginp->header('Location') // "";

              if($v5d =~ /loginData/) {
                  Log3 ($name, 5, "$name - Status Redirect Page : ".$retcode);
                  Log3 ($name, 5, "$name - Header Redirect Location: ".$location); 
              }
              
              my $sc        = $loginp->header('Set-Cookie') // "";   
              my ($logname) = $sc =~ /SunnyPortalLoginInfo=Username=(.*?)&/sx;
              Log3 ($name, 5, "$name - Header Set-Cookie: ".$sc) if($v5d =~ /loginData/); 

              if(__isLoggedIn ($name,$username,$loginp)) {                                  # Login erfolgeich(Landing Pages können im Portal eingestellt werden!)
                  handleCounter ($name, "dailyIssueCookieCounter");                         # Cookie Ausstellungszähler setzen
                  BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "loginState:successful", "oldlogintime:".(gettimeofday())[0] ], 1);
                  $errstate = 0;
              } 
              else {
                  Log3 ($name, 2, "$name - ERROR - Login into SMA-Portal failed !");
                  $state       = "login failed";
                  BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "loginState:failed", "NULL" ], 1);
                  $errstate = 1; 
              }              
          }         
      }
  } 
  elsif ($loginp->is_redirect) {
      $retcode  = $loginp->code;
      $location = $loginp->header('Location') // "";
      Log3 ($name, 3, "$name - User is already logged in.");      
      
      if($v5d =~ /loginData/) {
          Log3 ($name, 5, "$name - Redirect return code: ".    $retcode );
          Log3 ($name, 5, "$name - Redirect Header Location: ".$location); 
      }      
      
      BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "loginState:successful", "NULL" ], 1);
      $errstate = 0;
  } 
  else {
      $errstate = 1;
      $state       = $loginp->status_line;
      BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "loginState:failed", "NULL" ], 1);
      Log3 ($name, 1, "$name - ERROR Login Page: ".$state);
  }
  
  $ua->remove_handler('request_send');
  $ua->remove_handler('response_done');
  
return ($state, $errstate); 
}

################################################################
#                  Login Status testen
################################################################
sub __isLoggedIn {
  my $name     = shift;
  my $username = shift;
  my $loginp   = shift;

  my $sc        = $loginp->header('Set-Cookie') // "";   
  my ($logname) = $sc =~ /SunnyPortalLoginInfo=Username=(.*?)&/sx;
   
  if($logname && $logname eq $username) {
      Log3 ($name, 3, "$name - Login into SMA-Portal successfully done with user: $logname");      
      return 1;
  }
  
return 0; 
}

################################################################
#                    Abruf Live Daten
################################################################
sub _getLiveData {                       ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};
  my $ua    = $paref->{ua};                                         # LWP Useragent
  my $state = $paref->{state};                  
  my $daref = $paref->{daref};                                      # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0);
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $cts    = fhemTimeLocal(0, 0, 0, $mday, $mon, $year);
  my $offset = fhemTzOffset($cts);
  my $time   = int(($cts + $offset) * 1000);                        # add Timestamp in Millisekunden and UTC 
  my $call   = 'https://www.sunnyportal.com/homemanager?t=';
  
  if (AttrVal($name, "noHomeManager", 0)) {                         # Dashboard Seite abfragen wenn kein Home Manager vorhanden ist
      $call = 'https://www.sunnyportal.com/Dashboard?t=';
  }
  
  ($errstate,$state,$reread,$retry) = __dispatchGet ({ name     => $name,
                                                       ua       => $ua,
                                                       call     => $call.$time,
                                                       tag      => "liveData",
                                                       state    => $state, 
                                                       fnaref   => [ qw( extractLiveData ) ],
                                                       addon    => "",
                                                       daref    => $daref
                                                    });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Wetterdaten
################################################################
sub _getWeatherData {                    ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0);
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => 'https://www.sunnyportal.com/Dashboard/Weather',
                                        tag      => "weatherData",
                                        state    => $state, 
                                        fnaref   => [ qw( extractWeatherData ) ],
                                        addon    => "",
                                        daref    => $daref
                                     });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Anlagen Stammdaten
################################################################
sub _getPlantMasterData {                      ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0);
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => 'https://www.sunnyportal.com/HoMan/Forecast/LoadRecommendationData',
                                        tag      => "plantMasterData",
                                        state    => $state, 
                                        fnaref   => [ qw( extractPlantMasterData ) ],
                                        addon    => "",
                                        daref    => $daref
                                    });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Consumer Stammdaten
################################################################
sub _getConsumerMasterdata {             ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0);
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => 'https://www.sunnyportal.com/Homan/ConsumerBalance/GetLiveProxyValues',
                                        tag      => "consumerMasterdata",
                                        state    => $state, 
                                        fnaref   => [ qw( extractConsumerMasterdata ) ],
                                        addon    => "",
                                        daref    => $daref
                                     });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Consumer current Data
################################################################
sub _getConsumerCurrData {               ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0);
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => 'https://www.sunnyportal.com/Homan/ConsumerBalance/GetLiveProxyValues',
                                        tag      => "consumerCurrentdata",
                                        state    => $state, 
                                        fnaref   => [ qw( extractConsumerCurrentdata ) ],
                                        addon    => "",
                                        daref    => $daref
                                     });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Consumer Tagesdaten
################################################################
sub _getConsumerDayData {                ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  my $hash     = $defs{$name};
  
  my ($reread,$retry,$errstate) = (0,0,0);
                                     
  if(!$hash->{HELPER}{PLANTOID}) {
      $errstate = 1;
      $state    = qq{The consumer data cannot be retrieved because the plant ID isn't set.};      
      Log3 $name, 2, "$name - $state";
      return ($errstate,$state,$reread,$retry);
  }  
  
  my $PlantOid = $hash->{HELPER}{PLANTOID};
  my $dds      = (split(/\s+/x, TimeNow()))[0];
  my $dde      = (split(/\s+/x, FmtDateTime(time()+86400)))[0];
  
  my $ccdd = 'https://www.sunnyportal.com/Homan/ConsumerBalance/GetMeasuredValues?IntervalId=2&'.$PlantOid.'&StartTime='.$dds.'&EndTime='.$dde.'';
  
  # Energiedaten aktueller Tag
  Log3 ($name, 4, "$name - getting consumer energy data of current day");
  Log3 ($name, 4, "$name - Request date -> start: $dds, end: $dde");
  Log3 ($name, 5, "$name - Request consumer current day data string ->\n$ccdd");
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => $ccdd,
                                        tag      => "consumerDayData",
                                        state    => $state, 
                                        fnaref   => [ qw( extractConsumerHistData ) ],
                                        addon    => "day",
                                        daref    => $daref
                                     });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Consumer Monatsdaten
################################################################
sub _getConsumerMonthData {             ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  my $hash     = $defs{$name};
  
  my ($reread,$retry,$errstate) = (0,0,0);
                                     
  if(!$hash->{HELPER}{PLANTOID}) {
      $errstate = 1;
      $state    = qq{The consumer data cannot be retrieved because the plant ID isn't set.};      
      Log3 $name, 2, "$name - $state";
      return ($errstate,$state,$reread,$retry);
  }  
  
  my $PlantOid = $hash->{HELPER}{PLANTOID};
  my $dds      = (split(/\s+/x, TimeNow()))[0];
  my $dde      = (split(/\s+/x, FmtDateTime(time()+86400)))[0];                                   
                                     
  my ($mds,$me,$ye,$mde);
  if($dds =~ /(.*)-(.*)-(.*)/x) {
      $mds = "$1-$2-01";
      $me  = (($2+1)<=12) ? $2+1 : 1;
      $me  = sprintf("%02d", $me);
      $ye  = ($2>$me) ? $1+1 : $1;
      $mde = "$ye-$me-01";
  }
  
  my $ccmd = 'https://www.sunnyportal.com/Homan/ConsumerBalance/GetMeasuredValues?IntervalId=4&'.$PlantOid.'&StartTime='.$mds.'&EndTime='.$mde.'';

  # Energiedaten aktueller Monat
  Log3 ($name, 4, "$name - getting consumer energy data of current month");
  Log3 ($name, 4, "$name - Request date -> start: $mds, end: $mde"); 
  Log3 ($name, 5, "$name - Request consumer current month data string ->\n$ccmd");
 
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => $ccmd,
                                        tag      => "consumerMonthData",
                                        state    => $state, 
                                        fnaref   => [ qw( extractConsumerHistData ) ],
                                        addon    => "month",
                                        daref    => $daref
                                     });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Consumer Jahresdaten
################################################################
sub _getConsumerYearData {              ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  my $hash     = $defs{$name};
  
  my ($reread,$retry,$errstate) = (0,0,0);
                                     
  if(!$hash->{HELPER}{PLANTOID}) {
      $errstate = 1;
      $state    = qq{The consumer data cannot be retrieved because of the plant ID isn't set.};      
      Log3 $name, 2, "$name - $state";
      return ($errstate,$state,$reread,$retry);
  }  
  
  my $PlantOid = $hash->{HELPER}{PLANTOID};
  my $dds      = (split(/\s+/x, TimeNow()))[0];
  my $dde      = (split(/\s+/x, FmtDateTime(time()+86400)))[0];                                   
                                                                         
  my ($mds,$me,$ye,$mde,$yds,$yde);
  if($dds =~ /(.*)-(.*)-(.*)/x) {
      $mds = "$1-$2-01";
      $me  = (($2+1)<=12) ? $2+1 : 1;
      $me  = sprintf("%02d", $me);
      $ye  = ($2>$me) ? $1+1 : $1;
      $mde = "$ye-$me-01";
      $yds = "$1-01-01";
      $yde = ($1+1)."-01-01";
  }
  
  my $ccyd = 'https://www.sunnyportal.com/Homan/ConsumerBalance/GetMeasuredValues?IntervalId=5&'.$PlantOid.'&StartTime='.$yds.'&EndTime='.$yde.'';

  # Energiedaten aktuelles Jahr
  Log3 ($name, 4, "$name - getting consumer energy data of current year");
  Log3 ($name, 4, "$name - Request date -> start: $yds, end: $yde"); 
  Log3 ($name, 5, "$name - Request consumer current year data string ->\n$ccyd");
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => $ccyd,
                                        tag      => "consumerYearData",
                                        state    => $state, 
                                        fnaref   => [ qw( extractConsumerHistData ) ],
                                        addon    => "year",
                                        daref    => $daref
                                     });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Vorhersage Daten
################################################################
sub _getForecastData {                   ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0);
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => 'https://www.sunnyportal.com/HoMan/Forecast/LoadRecommendationData',
                                        tag      => "forecastData",
                                        state    => $state, 
                                        fnaref   => [ qw( extractForecastData extractConsumerPlanData ) ],
                                        addon    => "",
                                        daref    => $daref
                                     });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#           Abruf Statistik Daten Day
#            (anchorTime beachten !)
################################################################
sub _getBalanceDayData {                 ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};
  my $ua    = $paref->{ua};                                                       # LWP Useragent
  my $state = $paref->{state};                  
  my $daref = $paref->{daref};                                                    # Referenz zum Datenarray
  
  # _detailViewOn ($paref);                                                         # Detailanzeige einschalten
  
  my ($reread,$retry,$errstate) = (0,0,0); 
  
  my @bd  = split /\s+/x ,AttrVal($name, "balanceDay", "current");
  my $tag = "balanceDayData";

  for my $bal (@bd) {
      my ($y,$m,$d);
      my $addon = "Day_";
      
      if($bal !~ /current/ixms) {
          ($y,$m,$d) = $bal =~ /(\d{4})-(\d{2})-(\d{2})/x;
          
          if(!$y || !$m || !$d) {
              Log3 ($name, 2, qq{$name - The attribute "balanceDay" value "$bal" is ignored. A valid date with form "YYYY-MM-DD" is needed});
              next;
          }
          
          $addon .= $bal;
          $y     -= 1900;
          $m     -= 1;
      } 
      else {
          my $mp                       = (split "-", $bal)[1] // 0;               # Multiplikator: z.B. current-1 -> 1       
          my $time                     = time - ($mp * 86400);
          (undef,undef,undef,$d,$m,$y) = localtime($time);
          
          my $addon1 = ($y+1900)."-".(sprintf "%02d", $m+1)."-".sprintf "%02d",$d;
          
          my $params = {
              name   => $name,
              bal    => $bal,
              tag    => $tag,
              daref  => $daref,
              addon  => $addon,
              addon1 => $addon1,
          };        
          $addon = createDateAddon ($params);
      }  
 
      eval { timelocal(0, 0, 0, $d, $m, $y) } or do { $state    = (split(" at", $@))[0];
                                                      $errstate = 1;
                                                      Log3($name, 2, "$name - ERROR - invalid date/time format in attribute 'balanceDay' detected: $state");
                                                      return ($errstate,$state,$reread,$retry);
                                                   };
                                                   
      Log3 ($name, 4, "$name - retrieve $tag ".($y+1900)."-".(sprintf "%02d", $m+1)."-".sprintf "%02d",$d );
   
      my $cts     = fhemTimeLocal(0, 0, 0, $d, $m, $y);
      my $offset  = fhemTzOffset($cts);
      my $anchort = int($cts + $offset);                                          # anchorTime in UTC -> abzurufendes Datum
       
      my $tab     = 1;                                                            # Tab 1 -> Tag , 2->Monat, 3->Jahr, 4->Gesamt
      my %fields  = ("Content-Type" => "application/json; charset=utf-8");      
      my $cont    = qq{{"tabNumber":$tab,"anchorTime":$anchort}};
      
      ($errstate,$state) = __dispatchPost ({ name     => $name,
                                             ua       => $ua,
                                             call     => 'https://www.sunnyportal.com/FixedPages/HoManEnergyRedesign.aspx/GetLegendWithValues',
                                             tag      => $tag,
                                             state    => $state, 
                                             fnaref   => [ qw( extractStatisticData ) ],
                                             fields   => \%fields,
                                             content  => $cont,
                                             addon    => $addon,
                                             daref    => $daref
                                          });
      }
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#           Abruf Statistik Daten Month
#            (anchorTime beachten !)
################################################################
sub _getBalanceMonthData {                 ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};
  my $ua    = $paref->{ua};                                          # LWP Useragent
  my $state = $paref->{state};                  
  my $daref = $paref->{daref};                                       # Referenz zum Datenarray
  
  # _detailViewOn ($paref);                                            # Detailanzeige einschalten
  
  my ($reread,$retry,$errstate) = (0,0,0);   

  my @bd  = split /\s+/x ,AttrVal($name, "balanceMonth", "current");
  my $tag = "balanceMonthData";

  for my $bal (@bd) {
      my ($y,$m);
      my $addon = "Month_";
      
      if($bal !~ /current/ixms) {
          ($y,$m) = $bal =~ /^(\d{4})-(\d{2})$/x;
          
          if(!$y || !$m) {
              Log3 ($name, 2, qq{$name - The attribute "balanceMonth" value "$bal" is ignored. A valid date with form "YYYY-MM" is needed});
              next;
          }
          
          $addon .= $bal;  
          $y     -= 1900;
          $m     -= 1;
      } 
      else {
          my $mp = (split "-", $bal)[1] // 0;
          my $yc = int($mp/12);                                      # Anzahl der Jahre
          my $mc = $mp % 12;                                         # Anzahl Restmonate
          
          $y     = (localtime(time))[5];
          $y    -= $yc;
          $m     = (localtime(time))[4];
          
          if($m-$mc < 1) {
              $m = 12-abs($m-$mc);
              $y--;
          }
          else {
              $m = $m-$mc;
          }
          
          my $addon1 = ($y+1900)."-".sprintf "%02d", $m+1;
          
          my $params = {
              name   => $name,
              bal    => $bal,
              tag    => $tag,
              daref  => $daref,
              addon  => $addon,
              addon1 => $addon1,
          };        
          $addon = createDateAddon ($params);
      }  

      my $dim = daysInMonth ($m+1, $y+1900);                                      # errechnet wieviel Tage der gegebene Monat hat
 
      eval { timelocal(0, 0, 0, $dim, $m, $y) } or do { $state    = (split(" at", $@))[0];
                                                        $errstate = 1;
                                                        Log3($name, 2, "$name - ERROR - invalid date/time format in attribute 'balanceMonth' detected: $state");
                                                        return ($errstate,$state,$reread,$retry);
                                                      };
                                                   
      Log3 ($name, 4, "$name - retrieve $tag ".($y+1900)."-".sprintf "%02d", $m+1);
                                                   
      my $cts     = fhemTimeLocal(0, 0, 0, $dim, $m, $y);
      my $offset  = fhemTzOffset($cts);
      my $anchort = int($cts + $offset);                                          # anchorTime in UTC -> abzurufendes Datum
       
      my $tab     = 2;                                                            # Tab 1 -> Tag , 2->Monat, 3->Jahr, 4->Gesamt
      my %fields  = ("Content-Type" => "application/json; charset=utf-8");      
      my $cont    = qq{{"tabNumber":$tab,"anchorTime":$anchort}};
      
      ($errstate,$state) = __dispatchPost ({ name     => $name,
                                             ua       => $ua,
                                             call     => 'https://www.sunnyportal.com/FixedPages/HoManEnergyRedesign.aspx/GetLegendWithValues',
                                             tag      => $tag,
                                             state    => $state, 
                                             fnaref   => [ qw( extractStatisticData ) ],
                                             fields   => \%fields,
                                             content  => $cont,
                                             addon    => $addon,
                                             daref    => $daref
                                          });
  }
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#           Abruf Statistik Daten Year
#            (anchorTime beachten !)
################################################################
sub _getBalanceYearData {                 ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};
  my $ua    = $paref->{ua};                                                      # LWP Useragent
  my $state = $paref->{state};                  
  my $daref = $paref->{daref};                                                   # Referenz zum Datenarray
  
  # _detailViewOn ($paref);                                                        # Detailanzeige einschalten
  
  my ($reread,$retry,$errstate) = (0,0,0);                                 
 
  my @bd  = split /\s+/x ,AttrVal($name, "balanceYear", "current");
  my $tag = "balanceYearData";

  for my $bal (@bd) {
      my $y;
      my $addon = "Year_";
      
      if($bal !~ /current/ixms) {
          ($y) = $bal =~ /^(\d{4})$/x;
          
          if(!$y) {
              Log3 ($name, 2, qq{$name - The attribute "balanceYear" value "$bal" is ignored. A valid date with form "YYYY" is needed});
              next;
          }
          
          $addon .= $bal;
          $y     -= 1900;
      } 
      else {
          my $mp     = (split "-", $bal)[1] // 0;
          $y         = (localtime(time))[5];
          $y        -= $mp;
          my $addon1 = $y+1900;
          
          my $params = {
              name   => $name,
              bal    => $bal,
              tag    => $tag,
              daref  => $daref,
              addon  => $addon,
              addon1 => $addon1,
          };        
          $addon = createDateAddon ($params);          
      }
      
      eval { timelocal(0, 0, 0, 1, 1, $y) } or do { $state    = (split(" at", $@))[0];
                                                    $errstate = 1;
                                                    Log3($name, 2, "$name - ERROR - invalid date/time format in attribute 'balanceYear' detected: $state");
                                                    return ($errstate,$state,$reread,$retry);
                                                  };
                                                  
      Log3 ($name, 4, "$name - retrieve $tag ".($y+1900));
                                                   
      my $cts     = fhemTimeLocal(0, 0, 0, 1, 1, $y);
      my $offset  = fhemTzOffset($cts);
      my $anchort = int($cts + $offset);                                          # anchorTime in UTC -> abzurufendes Datum
       
      my $tab     = 3;                                                            # Tab 1 -> Tag , 2->Monat, 3->Jahr, 4->Gesamt
      my %fields  = ("Content-Type" => "application/json; charset=utf-8");      
      my $cont    = qq{{"tabNumber":$tab,"anchorTime":$anchort}};
      
      ($errstate,$state) = __dispatchPost ({ name     => $name,
                                             ua       => $ua,
                                             call     => 'https://www.sunnyportal.com/FixedPages/HoManEnergyRedesign.aspx/GetLegendWithValues',
                                             tag      => $tag,
                                             state    => $state, 
                                             fnaref   => [ qw( extractStatisticData ) ],
                                             fields   => \%fields,
                                             content  => $cont,
                                             addon    => $addon,
                                             daref    => $daref
                                          });                                     
  }
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#           Abruf Statistik Daten Year
#            (anchorTime beachten !)
################################################################
sub _getBalanceTotalData {               ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0);                                 
 
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $cts      = fhemTimeLocal(0, 0, 0, $mday, $mon, $year);
  my $offset   = fhemTzOffset($cts);
  my $anchort  = int($cts + $offset);                                         # anchorTime in UTC -> abzurufendes Datum
   
  my $tab     = 4;                                                            # Tab 1 -> Tag , 2->Monat, 3->Jahr, 4->Gesamt
  my %fields  = ("Content-Type" => "application/json; charset=utf-8");      
  my $cont    = qq{{"tabNumber":$tab,"anchorTime":$anchort}};
  
  ($errstate,$state) = __dispatchPost ({ name     => $name,
                                         ua       => $ua,
                                         call     => 'https://www.sunnyportal.com/FixedPages/HoManEnergyRedesign.aspx/GetLegendWithValues',
                                         tag      => "balanceTotalData",
                                         state    => $state, 
                                         fnaref   => [ qw( extractStatisticData ) ],
                                         fields   => \%fields,
                                         content  => $cont,
                                         addon    => "Total",
                                         daref    => $daref
                                      });                                     
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Abruf Anlagen Logbuch
################################################################
sub _getPlantLogbook {                   ## no critic "not used"
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $state    = $paref->{state};                  
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  my $hash     = $defs{$name};  

  my ($reread,$retry,$errstate) = (0,0,0); 
  
  if(!$hash->{HELPER}{PLANTOID}) {
      $errstate = 1;
      $state    = qq{The logbook cannot be retrieved because of the plant ID isn't set.};      
      Log3 $name, 2, "$name - $state";
      return ($errstate,$state,$reread,$retry);
  }  
  
  my $PlantOid = $hash->{HELPER}{PLANTOID};
  my $msgtypes = AttrVal($name, "plantLogbookTypes", "Warning,Disturbance,Error");      # möglich:  Warning,Info,Disturbance,Error  
  my $appstate = AttrVal($name, "plantLogbookApprovalState", "Any");     
  my $date     = (split(/\s+/x, TimeNow()))[0];
  my $call     = 'https://www.sunnyportal.com/Plants/'.$PlantOid.'/Log/Get?MessageTypes='.$msgtypes.'&ApprovalState='.$appstate.'&Device=None&MaxDateTime='.$date.'&Ticks=0';
  
  Log3 ($name, 4, "$name - Retrieving the logbook data up to the date: $date");
  
  ($errstate,$state) = __dispatchGet ({ name     => $name,
                                        ua       => $ua,
                                        call     => $call,
                                        tag      => "plantLogbook",
                                        state    => $state, 
                                        fnaref   => [ qw( extractPlantLogbook ) ],
                                        addon    => "",
                                        daref    => $daref
                                    });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                Detailanzeige einschalten
#             vor dem eigentlichen Datenabruf
################################################################
sub _detailViewOn {
  my $paref = shift;
  my $name  = $paref->{name};
  my $ua    = $paref->{ua};                                                       # LWP Useragent
  my $state = $paref->{state};                  
  my $daref = $paref->{daref};                                                    # Referenz zum Datenarray
  
  my ($reread,$retry,$errstate) = (0,0,0); 

  my $tag     = "detailViewSwitch";
  my %fields  = ("Content-Type" => "application/json; charset=utf-8");      
  my $cont    = qq{{"showDetailMode":true}};
  
  ($errstate,$state) = __dispatchPost ({ name     => $name,
                                         ua       => $ua,
                                         call     => 'https://www.sunnyportal.com/FixedPages/HoManEnergyRedesign.aspx/UpdateDisplayOption',
                                         tag      => $tag,
                                         state    => $state, 
                                         fnaref   => [ qw( extractHelperData ) ],
                                         fields   => \%fields,
                                         content  => $cont,
                                         addon    => "",
                                         daref    => $daref
                                      });
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Dispatcher GET
################################################################
sub __dispatchGet {
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $call     = $paref->{call};                   # Seitenaufruf zur Datenquelle
  my $tag      = $paref->{tag};                    # Kennzeichen der abzurufenen Daten
  my $state    = $paref->{state};                  
  my $fnref    = $paref->{fnaref};                 # Referenz zu Array der aufzurufenden Funktion(en) zur Datenextraktion
  my $fnaddon  = $paref->{addon};                  # optionales Addon für aufzurufende Funktion
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  my $hash     = $defs{$name};
  
  my ($reread,$retry,$errstate)     = (0,0,0);
  
  my ($data,$data_cont)             = ___getData ({ name => $name,
                                                    ua   => $ua,
                                                    call => $call,
                                                    tag  => $tag
                                                 });
                          
  ($reread,$retry,$errstate,$state) = ___analyzeData ({ name     => $name,
                                                        errstate => $errstate,
                                                        state    => $state,
                                                        data     => $data
                                                     });
  
  return ($errstate,$state,$reread,$retry) if($errstate || $reread || $retry);
  
  if ($data_cont && $data_cont !~ m/undefined/ix) {
      my @func = @$fnref;
      no strict "refs";                                  ## no critic 'NoStrict'       
      for my $fn (@func) {
          &{$fn} ($hash,$daref,$data_cont,$fnaddon,$data);
      }
      use strict "refs";
  }
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                    Dispatcher POST
################################################################
sub __dispatchPost {
  my $paref    = shift;
  my $name     = $paref->{name};
  my $ua       = $paref->{ua};                     # LWP Useragent
  my $call     = $paref->{call};                   # Seitenaufruf zur Datenquelle
  my $tag      = $paref->{tag};                    # Kennzeichen der abzurufenen Daten
  my $state    = $paref->{state};                  
  my $fnref    = $paref->{fnaref};                 # Referenz zu Array der aufzurufenden Funktion(en) zur Datenextraktion
  my $fields   = $paref->{fields};                 # Referenz zum Hash der zu übertragenden PUSH Header
  my $cont     = $paref->{content};                # Content Daten für PUSH (String)
  my $fnaddon  = $paref->{addon};                  # optionales Addon für aufzurufende Funktion
  my $daref    = $paref->{daref};                  # Referenz zum Datenarray
  my $hash     = $defs{$name};
  
  my ($reread,$retry,$errstate)     = (0,0,0);
                                                   
  my ($data,$data_cont)             = ___postData ({ name    => $name,
                                                     ua      => $ua,
                                                     call    => $call,
                                                     tag     => $tag,
                                                     fields  => $fields,
                                                     content => $cont
                                                  });
                                                              
  ($reread,$retry,$errstate,$state) = ___analyzeData ({ name     => $name,
                                                        ua       => $ua,
                                                        errstate => $errstate,
                                                        state    => $state,
                                                        data     => $data
                                                     });
  
  return ($errstate,$state) if($errstate);
  
  if ($data_cont && $data_cont !~ m/undefined/ix) {
      my @func = @$fnref;
      no strict "refs";                                  ## no critic 'NoStrict'       
      for my $fn (@func) {
          &{$fn} ($hash,$daref,$data_cont,$fnaddon,$tag);
      }
      use strict "refs";
  }
  
return ($errstate,$state,$reread,$retry); 
}

################################################################
#                      Standard Abruf Daten GET
################################################################
sub ___getData {
  my $paref = shift;
  my $name  = $paref->{name};
  my $ua    = $paref->{ua};
  my $call  = $paref->{call};
  my $tag   = $paref->{tag};
  
  my $v5d     = AttrVal($name, "verbose5Data", "none");
  my $verbose = AttrVal($name, "verbose", 3);
  
  my $cont;   

  Log3 ($name, 4, "$name - getting $tag"); 
  
  if($verbose == 5 && $v5d =~ /$tag/x) {
      $ua->add_handler( request_send  => sub { shift->dump; return } );         # for debugging
      $ua->add_handler( response_done => sub { shift->dump; return } );
  }
  
  my $data  = $ua->get( $call );  
  my $dcont = $data->content;                                                  

  $cont = eval{decode_json($dcont)} or do { $cont = $dcont };
  
  if($v5d =~ /$tag/x) {
      Log3 ($name, 5, "$name - Return Code: ".$data->code); 
      Log3 ($name, 5, "$name - $tag received:\n".Dumper $cont);
  }
  
  $ua->remove_handler('request_send');
  $ua->remove_handler('response_done');
  
return ($data,$dcont); 
}

################################################################
#                      Standard Abruf Daten POST
################################################################
sub ___postData {
  my $paref   = shift;
  my $name    = $paref->{name};
  my $ua      = $paref->{ua};
  my $call    = $paref->{call};
  my $fields  = $paref->{fields};
  my $content = $paref->{content};
  my $tag     = $paref->{tag};
  
  my $v5d     = AttrVal($name, "verbose5Data", "none");
  my $verbose = AttrVal($name, "verbose", 3);
  
  my $cont;   

  Log3 ($name, 4, "$name - getting $tag");
  
  if($verbose == 5 && $v5d =~ /$tag/x) {
      $ua->add_handler( request_send  => sub { shift->dump; return } );         # for debugging
      $ua->add_handler( response_done => sub { shift->dump; return } );
  }

  my $data  = $ua->post( $call, %$fields, Content => $content );
                         
  my $dcont = $data->content;                                                  

  $cont = eval{decode_json($dcont)} or do { $cont = $dcont };
  
  if($v5d =~ /$tag/x) {
      Log3 ($name, 5, "$name - Return Code: ".$data->code); 
      Log3 ($name, 5, "$name - $tag received:\n".Dumper $cont);
  }
  
  $ua->remove_handler('request_send');
  $ua->remove_handler('response_done');
  
return ($data,$dcont); 
}

################################################################
#                 analysiere abgerufene Daten
################################################################
sub ___analyzeData {                   ## no critic 'complexity'
  my $paref           = shift;
  my $name            = $paref->{name};
  my $errstate        = $paref->{errstate};
  my $state           = $paref->{state};
  my $ua              = $paref->{ua};
  my $ad              = $paref->{data};
  my $hash            = $defs{$name};
  my ($reread,$retry) = (0,0);
  my $data            = "";
    
  my $v5d             = AttrVal($name, "verbose5Data", "none");
  my $ad_content      = encode("utf8", $ad->decoded_content); 
  my $act             = $hash->{HELPER}{RETRIES};                                                     # Index aktueller Wiederholungsversuch
  my $attstr          = "Attempts read data again in $sleepretry s ... ($act of $maxretries)";        # Log vorbereiten
  
  my $wm1e            = qq{Updating of the live data was interrupted};
  my $wm1d            = qq{Die Aktualisierung der Live-Daten wurde unterbrochen};
  my $wm2e            = qq{The current consumption could not be determined. The current purchased electricity is unknown};
  my $wm2d            = qq{Der aktuelle Verbrauch konnte nicht ermittelt werden. Der aktuelle Netzbezug ist unbekannt};
  my $em1e            = qq{Communication with the Sunny Home Manager is currently not possible};
  my $em1d            = qq{Die Kommunikation mit dem Sunny Home Manager ist zurzeit nicht m};
  my $em2e            = qq{The current data cannot be retrieved from the PV system. Check the cabling and configuration};
  my $em2d            = qq{Die aktuellen Daten .*? nicht von der Anlage abgerufen werden.*? Sie die Verkabelung und Konfiguration}; 

  ___extractCookie ({ ua   => $ua,
                      data => $ad,
                      name => $name,
                   });  
  
  $data = eval{decode_json($ad_content)} or do { $data = $ad_content };
  
  my $jsonerror = $ad->header('Jsonerror') // "";                                                     # Portal meldet keine Verarbeitung des Reaquests möglich (z.B. Jahr 0000 zur Auswertung angefordert)
  
  if($jsonerror) {
      $errstate = 1;
      $state    = "SMA Portal failure: "."Message -> ".$data->{Message}.",\nStackTrace -> ".$data->{StackTrace}.",\nExceptionType -> ".$data->{ExceptionType};
      return ($reread,$retry,$errstate,$state);
  }
  
  if(ref $data eq "HASH") {
      for my $k (keys %{$data}) {
          my $val = $data->{$k};
          next if(!defined $val);
          
          my @da;
          
          if(ref $val eq "ARRAY") {
              for my $a (@{$val}) {              
                  push @da, $a if(!ref $a);
              }
          }
          
          if(ref $val eq "HASH") {
              for my $b (keys %{$val}) {                    
                  push @da, $b;
              }              
          }
          
          $val = join " ", @da if(@da);
          
          if ($val && $k !~ /__type/ix) {
              if($k =~ m/WarningMessages/x && $val =~ /$wm1e|$wm1d/) {                                        ## no critic 'regular expression' # Regular expression without "/x" flag nicht anwenden !!!
                  Log3 ($name, 3, "$name - Updating of the live data was interrupted. $attstr");
                  $retry = 1;
                  return ($reread,$retry,$errstate,$state);
              }
              if($k =~ m/WarningMessages/x && $val =~ /$wm2e|$wm2d/) {                                        ## no critic 'regular expression' # Regular expression without "/x" flag nicht anwenden !!!
                  Log3 ($name, 3, "$name - The current consumption could not be determined. The current purchased electricity is unknown. $attstr");
                  $retry = 1;
                  return ($reread,$retry,$errstate,$state);
              }  
              if($k =~ m/ErrorMessages/x && $val =~ /$em1e|$em1d/) {                                          ## no critic 'regular expression' # Regular expression without "/x" flag nicht anwenden !!!
                  # Energiedaten konnten nicht ermittelt werden, Daten neu lesen mit Zeitverzögerung
                  Log3 ($name, 3, "$name - Communication with the Sunny Home Manager currently impossible. $attstr");
                  $retry = 1;
                  return ($reread,$retry,$errstate,$state);
              }              
              if($k =~ m/ErrorMessages/x && $val =~ /$em2e|$em2d/) {                                          ## no critic 'regular expression' # Regular expression without "/x" flag nicht anwenden !!!
                  # Energiedaten konnten nicht ermittelt werden, Daten neu lesen mit Zeitverzögerung
                  Log3 ($name, 3, "$name - The current data cannot be retrieved from the PV system. $attstr");
                  $retry = 1;
                  return ($reread,$retry,$errstate,$state);
              }
          }
      }
  } 
  else {
      my $njdat = encode("utf8", $ad->as_string); 
      
      if($njdat =~ /401\s-\sUnauthorized/x) {
          Log3 ($name, 2, "$name - ERROR - User logged in but unauthorized");
          my($p1,$p2) = $njdat =~ /<h2>401\s-\sUnauthorized:.(.*)?<\/h2>.*?<h3>(.*)?<\/h3>/sx;
          $state      = ($p1 // "")." ".($p2 // "");          
      }
      
      Log3 ($name, 5, "$name - No JSON Data received:\n ".$njdat);
      
      $errstate = 1;
  }
  
return ($reread,$retry,$errstate,$state);
}

################################################################
#            Cookie Daten analysieren & extrahieren
# Die extract_cookies()-Methode sucht im HTTP::Response-Objekt, 
# das als Argument übergeben wird, nach Set-Cookie: und 
# Set-Cookie2: Headern.
################################################################
sub ___extractCookie {                   
  my $paref = shift;
  my $ua    = $paref->{ua};
  my $data  = $paref->{data};           # empfangene Rohdaten
  
  eval { $ua->cookie_jar->extract_cookies($data) } or return;
  
return;
}

################################################################
##  Verarbeitung empfangene Daten, setzen Readings
################################################################
sub ParseData {
  my $string = shift;
  my @a      = split("\\|",$string);
  my $hash   = $defs{$a[0]};
  my $name   = $hash->{NAME};
  my @da     = ();
  
  my $lc;
  
  my $exceed    = $a[1];
  my $newcycle  = $a[2];
  my $errstate  = $a[3];
  my $getp      = $a[4];
  my $setp      = $a[5];  
  
  my $ac        = $hash->{HELPER}{ACTCYCLE};
  my $maxcycles = (controlParams $name)[1];
  
  if($exceed) {                  
      delete($hash->{HELPER}{RUNNING_PID}); 
      delcookiefile ($hash);      
      $hash->{HELPER}{GETTER} = $getp;
      $hash->{HELPER}{SETTER} = $setp;   
      CallInfo($hash,1,1);                                     # neuer Versuch (nach Threshold exceed) im gleichen Cycle mit gelöschtem Cookie 
      return;
  } 
  
  if($newcycle && $ac < $maxcycles) {                  
      delete($hash->{HELPER}{RUNNING_PID});     
      delcookiefile ($hash); 
      $hash->{HELPER}{GETTER} = $getp;
      $hash->{HELPER}{SETTER} = $setp;
      $hash->{HELPER}{ACTCYCLE}++;    
      CallInfo($hash,1,0);                                     # neuer Abrufcycle 
      return;
  }
  
  # Laufzeit für einen Cycle berechnen
  my $btime  = $hash->{HELPER}{CYCLEBTIME};
  my $etime  = (gettimeofday())[0];
  my $cycles = $hash->{HELPER}{ACTCYCLE};
  my $ctime  = int(($etime - $btime) / $cycles);               # durchschnittliche Laufzeit für einen Zyklus
  
  my $state  = decode_base64($a[6]);
  
  if($a[7]) {
      $lc = decode_base64($a[7]);
      @da = split "###", $lc;
  }
  
  deleteData($hash, 1) if($getp ne "none");                    # Daten nur löschen wenn Datenabruf (kein Verbraucher schalten)
  
  readingsBeginUpdate($hash);
  
  for my $elem (@da) {
      my ($rn,$rval) = split ":", $elem, 2;
      readingsBulkUpdate($hash, $rn, $rval);      
  }

  readingsEndUpdate($hash, 1);
  
  my $ldlv = $stpl{liveData}{level};
  my $cclv = $stpl{consumerCurrentdata}{level};
  my $lddo = $subs{$name}{liveData}{doit};
  
  my $pv   = ReadingsNum($name, "${ldlv}_PV"             , 0);
  my $fi   = ReadingsNum($name, "${ldlv}_FeedIn"         , 0);
  my $gc   = ReadingsNum($name, "${ldlv}_GridConsumption", 0);
  my $sum  = $fi-$gc;
  
  my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime);
  if(AttrVal("global", "language", "EN") eq "DE") {
      $ts = strftime('%d.%m.%Y %H:%M:%S', localtime);
  }
  
  readingsBeginUpdate($hash);
  
  if(!$errstate) {
      if($setp ne "none") {
          my ($d,$op) = split(":",$setp);
          $op         = ($op eq "auto") ? "off (automatic)" : $op;
          readingsBulkUpdate($hash, "${cclv}_${d}_Switch", $op);
      }
      readingsBulkUpdate($hash, "lastCycleTime",   $ctime   ) if($ctime > 0);
      readingsBulkUpdate($hash, "summary",         $sum." W") if($subs{$name}{liveData}{doit});
      readingsBulkUpdate($hash, "lastSuccessTime", $ts      );
  }
  
  readingsBulkUpdate($hash, "state", $state);
  
  readingsEndUpdate($hash, 1);  
  
  finalCleanup($hash);
  
  SPGRefresh($hash,0,1);
  
return;
}

################################################################
##                   Timeout  BlockingCall
################################################################
sub ParseAborted {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
   
  $cause = $cause // "Timeout >process terminated<";
  Log3 ($name, 1, "$name - BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");
  
  readingsSingleUpdate($hash, "state", "broken: ".$cause, 1);
  
  finalCleanup($hash);
  
return;
}

################################################################
##             Final cleanup of an execution
################################################################
sub finalCleanup {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  delete($hash->{HELPER}{RUNNING_PID});
  
  $hash->{HELPER}{GETTER} = "all";
  $hash->{HELPER}{SETTER} = "none";
  
  if(AttrVal($name, "cookieDelete", "auto") =~ /Run/x) {
      Log3 ($name, 3, "$name - force delete cookie file");
      delcookiefile ($hash);
  }
  
return;
}

################################################################
#             Cookie-Datei löschen 
################################################################
sub delcookiefile {
   my $hash   = shift;
   my $source = shift;;
   my $name   = $hash->{NAME};
   my $err    = "";

   my $cookieLocation = AttrVal($name, "cookieLocation", "./log/".$name."_cookie.txt"); 
   my $delfile        = unlink ($cookieLocation) or $err = $!;
    
   if($delfile) {
       Log3 $name, 3, "$name - Cookie file deleted: $cookieLocation";  
   }

return ($err);
}

################################################################
##         Auswertung Live Daten
################################################################
sub extractLiveData {                  ## no critic 'complexity'
  my $hash    = shift;
  my $daref   = shift;
  my $live    = shift;  
  my $name    = $hash->{NAME};
  my $val     = "";
  
  Log3 ($name, 4, "$name - ##### extracting live data #### ");
  
  $live = eval{decode_json($live)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                           return;
                                         };
                                                                                             
  my ($errMsg,$warnMsg,$infoMsg) = (0,0,0);
  my $lv                         = $stpl{liveData}{level};
  my $lang                       = AttrVal ("global", "language", "EN");
  
  my %hm = (                                          # Header Messages sprachenabhängig
      "DE" => "Nachricht von SMA Sunny Portal erhalten:",
      "EN" => "Message got from SMA Sunny Portal:"
  );
  
  if (ref $live eq "HASH") {
      push @$daref, "${lv}_FeedIn:"                  .$live->{FeedIn}." W"                 if(defined $live->{FeedIn});
      push @$daref, "${lv}_GridConsumption:"         .$live->{GridConsumption}." W"        if(defined $live->{GridConsumption});
      push @$daref, "${lv}_PV:"                      .$live->{PV}." W"                     if(defined $live->{PV});    
      push @$daref, "${lv}_AutarkyQuote:"            .$live->{AutarkyQuote}." %"           if(defined $live->{AutarkyQuote});
      push @$daref, "${lv}_SelfConsumption:"         .$live->{SelfConsumption}." W"        if(defined $live->{SelfConsumption});
      push @$daref, "${lv}_SelfConsumptionQuote:"    .$live->{SelfConsumptionQuote}." %"   if(defined $live->{SelfConsumptionQuote});
      push @$daref, "${lv}_SelfSupply:"              .$live->{SelfSupply}." W"             if(defined $live->{SelfSupply});
      push @$daref, "${lv}_TotalConsumption:"        .$live->{TotalConsumption}." W"       if(defined $live->{TotalConsumption});
      
      push @$daref, "${lv}_BatteryIn:"               .$live->{BatteryIn}. " W"             if(defined $live->{BatteryIn});
      push @$daref, "${lv}_BatteryOut:"              .$live->{BatteryOut}." W"             if(defined $live->{BatteryOut});
      push @$daref, "${lv}_BatteryMode:"             .$live->{BatteryMode}.""              if(defined $live->{BatteryMode});
      push @$daref, "${lv}_BatteryStateOfHealth:"    .$live->{BatteryStateOfHealth}.""     if(defined $live->{BatteryStateOfHealth});
      push @$daref, "${lv}_BatteryChargeStatus:"     .$live->{BatteryChargeStatus}." %"    if(defined $live->{BatteryChargeStatus});
      push @$daref, "${lv}_DirectConsumption:"       .$live->{DirectConsumption}." W"      if(defined $live->{DirectConsumption});
      push @$daref, "${lv}_DirectConsumptionQuote:"  .$live->{DirectConsumptionQuote}." %" if(defined $live->{DirectConsumptionQuote});
      
      push @$daref, "${lv}_ModuleTemperature:"       .$live->{ModuleTemperature}.""        if(defined $live->{ModuleTemperature});
      push @$daref, "${lv}_Insolation:"              .$live->{Insolation}.""               if(defined $live->{Insolation});
      push @$daref, "${lv}_WindSpeed:"               .$live->{WindSpeed}.""                if(defined $live->{WindSpeed});
      push @$daref, "${lv}_EnvironmentTemperature:"  .$live->{EnvironmentTemperature}.""   if(defined $live->{EnvironmentTemperature});
      
      if($live->{OperationHealth}) {
          my $o = "Ok: "     .$live->{OperationHealth}{Ok};
          my $w = "Warning: ".$live->{OperationHealth}{Warning};
          my $e = "Error: "  .$live->{OperationHealth}{Error};
          my $u = "Unknown: ".$live->{OperationHealth}{Unknown};
          push @$daref, "${lv}_OperationHealth: $o, $w, $e, $u";
      }
      
      if($live->{ErrorMessages}[0]) {
          my @em;
          $errMsg = 1; 
          for my $a (@{$live->{ErrorMessages}}) {                    
              push @em, encode ("utf8", $a);
          }
          $val = join " ", @em if(@em);
          push @$daref, "${lv}_ErrorMessages:".qq{<html><b>$hm{$lang}</b><br>$val</html>};
      }
      
      if($live->{WarningMessages}[0]) {
          my @wm;
          $warnMsg = 1; 
          for my $a (@{$live->{WarningMessages}}) {                    
              push @wm, encode ("utf8", $a);
          }
          $val = join " ", @wm if(@wm);
          push @$daref, "${lv}_WarningMessages:".qq{<html><b>$hm{$lang}</b><br>$val</html>};
      }
      
      if($live->{InfoMessages}[0]) {
          my @im;
          $infoMsg = 1; 
          for my $a (@{$live->{InfoMessages}}) {                    
              push @im, encode ("utf8", $a);
          }
          $val = join " ", @im if(@im);
          push @$daref, "${lv}_InfoMessages:".qq{<html><b>$hm{$lang}</b><br>$val</html>};
      }      
  }
  
  BlockingInformParent("FHEM::SMAPortal::delReadingFromBlocking", [$name, "${lv}_ErrorMessages"]  , 1) if(!$errMsg);
  BlockingInformParent("FHEM::SMAPortal::delReadingFromBlocking", [$name, "${lv}_WarningMessages"], 1) if(!$warnMsg);
  BlockingInformParent("FHEM::SMAPortal::delReadingFromBlocking", [$name, "${lv}_InfoMessages"]   , 1) if(!$infoMsg);

return;
}

################################################################
##         Auswertung Forecast Daten
################################################################
sub extractForecastData {              ## no critic 'complexity'                      
  my $hash     = shift;
  my $daref    = shift;
  my $forecast = shift;
  my $name     = $hash->{NAME};
  
  Log3 ($name, 4, "$name - ##### extracting forecast data #### ");
  
  $forecast = eval{decode_json($forecast)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                   return;
                                                 };
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year    += 1900;
  $mon     += 1;
  my $today = "$year-".sprintf("%02d", $mon)."-".sprintf("%02d", $mday)."T";

  my $lv         = $stpl{forecastData}{level};
  my $PV_sum     = 0;
  my $consum_sum = 0;
  my $sum        = 0; 

  # Counter for forecast objects
  my $obj_nr = 0;

  # The next few hours...
  my %nextFewHoursSum = ("PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0);

  # Rest of the day...
  my %restOfDaySum = ("PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0);

  # Tomorrow...
  my %tomorrowSum = ("PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0);

  # Get the current day (for 2016-02-26, this is 26)
  my $current_day = (localtime)[3];

  # Loop through all forecast objects
  # Energie wird als "J" geliefert, Wh = J / 3600
  for my $fc_obj (@{$forecast->{'ForecastSeries'}}) {
      my $fc_datetime = $fc_obj->{'TimeStamp'}->{'DateTime'};                       # Example for DateTime: 2016-02-15T23:00:00
      my $tkind       = $fc_obj->{'TimeStamp'}->{'Kind'};                           # Zeitart: Unspecified, Utc

      # Calculate Unix timestamp (month begins at 0, year at 1900)
      my ($fc_year, $fc_month, $fc_day, $fc_hour) = $fc_datetime =~ /^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):00:00$/x;
      my $fc_uts          = POSIX::mktime( 0, 0, $fc_hour,  $fc_day, $fc_month - 1, $fc_year - 1900 );
      my $fc_diff_seconds = $fc_uts - time + 3600;  # So we go above 0 for the current hour                                                                        
      my $fc_diff_hours   = int( $fc_diff_seconds / 3600 );
      
      # Use also old data to integrate daily PV and Consumption
      if ($current_day == $fc_day) {
         $PV_sum     += int($fc_obj->{'PvMeanPower'}->{'Amount'});                 # integrator of daily PV in Wh
         $consum_sum += int($fc_obj->{'ConsumptionForecast'}->{'Amount'}/3600);    # integrator of daily Consumption forecast in Wh
      }

      # Don't use old data
      next if $fc_diff_seconds < 0;

      # Sum up for the next few hours (4 hours total, this is current hour plus the next 3 hours)
      if ($obj_nr < 4) {
         $nextFewHoursSum{'PV'}          += $fc_obj->{'PvMeanPower'}->{'Amount'};                   # Wh
         $nextFewHoursSum{'Consumption'} += $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;    # Wh
         $nextFewHoursSum{'Total'}       += $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;   # Wh
         $nextFewHoursSum{'ConsumpRcmd'} += $fc_obj->{'IsConsumptionRecommended'} ? 1 : 0;         
      }

      # If data is for the rest of the current day
      if ( $current_day == $fc_day ) {
         $restOfDaySum{'PV'}          += $fc_obj->{'PvMeanPower'}->{'Amount'};                      # Wh
         $restOfDaySum{'Consumption'} += $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;       # Wh
         $restOfDaySum{'Total'}       += $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;      # Wh
         $restOfDaySum{'ConsumpRcmd'} += $fc_obj->{'IsConsumptionRecommended'} ? 1 : 0; 
     }
      
      # If data is for the next day (quick and dirty: current day different from this object's day)
      # Assuming only the current day and the next day are returned from Sunny Portal
      if ( $current_day != $fc_day ) {
         $tomorrowSum{'PV'}          += $fc_obj->{'PvMeanPower'}->{'Amount'} if(exists($fc_obj->{'PvMeanPower'}->{'Amount'}));            # Wh
         $tomorrowSum{'Consumption'} += $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;                                              # Wh
         $tomorrowSum{'Total'}       += $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 if ($fc_obj->{'PvMeanPower'}->{'Amount'});   # Wh
         $tomorrowSum{'ConsumpRcmd'} += $fc_obj->{'IsConsumptionRecommended'} ? 1 : 0;
      }
      
      # Update values in Fhem if less than 24 hours in the future
      # TimeStamp Kind: "Unspecified"
      if ($obj_nr < 24) {
          my $time_str = "ThisHour";
          $time_str = "NextHour".sprintf("%02d", $obj_nr) if($fc_diff_hours>0);
          if($time_str =~ /NextHour/x) {
              push @$daref, "${lv}_${time_str}_Time:".                     TimeAdjust($hash,$fc_obj->{'TimeStamp'}->{'DateTime'},$tkind);                                     
              push @$daref, "${lv}_${time_str}_PvMeanPower:".              int( $fc_obj->{'PvMeanPower'}->{'Amount'} )." Wh";                                                        # in W als Durchschnitt geliefet, d.h. eine Stunde -> Wh                    
              push @$daref, "${lv}_${time_str}_Consumption:".              int( $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 )." Wh";                                         # {'ConsumptionForecast'}->{'Amount'} wird als J = Ws geliefert
              push @$daref, "${lv}_${time_str}_IsConsumptionRecommended:". ($fc_obj->{'IsConsumptionRecommended'} ? "yes" : "no");
              push @$daref, "${lv}_${time_str}_Total:".                    (int($fc_obj->{'PvMeanPower'}->{'Amount'}) - int($fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600))." Wh";
              
              # add WeatherId Helper to show weather icon
              BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "NULL", "${lv}_".${time_str}."_WeatherId:".int($fc_obj->{'WeatherId'}) ], 1) if(defined $fc_obj->{'WeatherId'});
          }
          if($time_str =~ /ThisHour/x) {
              push @$daref, "${lv}_${time_str}_Time:".                     TimeAdjust($hash,$fc_obj->{'TimeStamp'}->{'DateTime'},$tkind);                                    
              push @$daref, "${lv}_${time_str}_PvMeanPower:".              int( $fc_obj->{'PvMeanPower'}->{'Amount'} )." Wh";                                                       # in W als Durchschnitt geliefet, d.h. eine Stunde -> Wh                 
              push @$daref, "${lv}_${time_str}_Consumption:".              int( $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 )." Wh";                                        # {'ConsumptionForecast'}->{'Amount'} wird als J = Ws geliefert
              push @$daref, "${lv}_${time_str}_IsConsumptionRecommended:". ($fc_obj->{'IsConsumptionRecommended'} ? "yes" : "no");
              push @$daref, "${lv}_${time_str}_Total:".                    (int($fc_obj->{'PvMeanPower'}->{'Amount'}) - int($fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600))." Wh";
              
              # add WeatherId Helper to show weather icon
              BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "NULL", "${lv}_".${time_str}."_WeatherId:".int($fc_obj->{'WeatherId'}) ], 1) if(defined $fc_obj->{'WeatherId'});  
          }
      }

      # Increment object counter
      $obj_nr++;
  }
  
  push @$daref, "${lv}_Next04Hours_Consumption:".                  int( $nextFewHoursSum{'Consumption'} )." Wh";
  push @$daref, "${lv}_Next04Hours_PV:".                           int( $nextFewHoursSum{'PV'}          )." Wh";
  push @$daref, "${lv}_Next04Hours_Total:".                        int( $nextFewHoursSum{'Total'}       )." Wh";
  push @$daref, "${lv}_Next04Hours_IsConsumptionRecommended:".     int( $nextFewHoursSum{'ConsumpRcmd'} )." h";
  push @$daref, "${lv}_ForecastToday_Consumption:".                $consum_sum." Wh";    
  push @$daref, "${lv}_ForecastToday_PV:".                         $PV_sum." Wh";
  push @$daref, "${lv}_RestOfDay_Consumption:".                    int( $restOfDaySum{'Consumption'}    )." Wh";
  push @$daref, "${lv}_RestOfDay_PV:".                             int( $restOfDaySum{'PV'}             )." Wh";
  push @$daref, "${lv}_RestOfDay_Total:".                          int( $restOfDaySum{'Total'}          )." Wh";
  push @$daref, "${lv}_RestOfDay_IsConsumptionRecommended:".       int( $restOfDaySum{'ConsumpRcmd'}    )." h";
  push @$daref, "${lv}_Tomorrow_Consumption:".                     int( $tomorrowSum{'Consumption'}     )." Wh";
  push @$daref, "${lv}_Tomorrow_PV:".                              int( $tomorrowSum{'PV'}              )." Wh";
  push @$daref, "${lv}_Tomorrow_Total:".                           int( $tomorrowSum{'Total'}           )." Wh";
  push @$daref, "${lv}_Tomorrow_IsConsumptionRecommended:".        int( $tomorrowSum{'ConsumpRcmd'}     )." h";

return;
}

################################################################
##         Auswertung Wetterdaten
################################################################
sub extractWeatherData {
  my $hash    = shift;
  my $daref   = shift;
  my $weather = shift;
  my $name    = $hash->{NAME};
  
  Log3 ($name, 4, "$name - ##### extracting weather data #### ");
  
  $weather = eval{decode_json($weather)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                 return;
                                               };
  my $lv = $stpl{weatherData}{level};
  
  for my $k (keys %$weather) {
      next if(!$k);

      Log3 ($name, 4, qq{$name - Weatherdata content "$k": }.Dumper $weather->{$k});
      
      if (ref $weather->{$k} eq "HASH") {
          my $ih = $weather->{$k};
          
          my $day    = $k;
          my $symbol = encode("utf8",  $weather->{$k}{TemperatureSymbol});
          my $temp   = sprintf("%.1f", $weather->{$k}{Temperature});
          my $wdesc  = encode ("utf8", $weather->{$k}{WeatherDescription});
          $wdesc     =~ s/t/T/x if($wdesc =~ /^t/x);
          $day       =~ s/t/T/x;
          
          push @$daref, "${lv}_${day}_Temperature:$temp $symbol"; 
          push @$daref, "${lv}_${day}_WeatherDescription:$wdesc"; 
      }
  } 

return;
}

################################################################
#          Auswertung Statistic Daten
#          $period = Day[_<date>]   | 
#                    Month[_<date>] | 
#                    Year[_<date>]  | 
#                    Total
################################################################
sub extractStatisticData {
  my $hash      = shift;
  my $daref     = shift;
  my $statistic = shift;
  my $period    = shift;
  my $tag       = shift;
  my $name      = $hash->{NAME};
  my $sd;
  
  Log3 ($name, 4, "$name - extracting balance data ");
  
  $statistic = eval{decode_json($statistic)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                     return;
                                                   };
  my $lv = $stpl{$tag}{level};
  
  if(ref $statistic eq "HASH") {
      $sd = decode_json ( encode('UTF-8', $statistic->{d}) );
  }

  if($sd && ref $sd eq "ARRAY") {
      for my $a (@$sd) {                                              # jedes ARRAY-Element ist ein HASH
          my $k = $a->{Key};
          my $v = $a->{Value};
          push @$daref, "${lv}_${period}_${k}:$v" if(defined $statkeys{$k});                  
      }
  } 
  
return; 
}

################################################################
##                     Auswertung Anlagendaten
################################################################
sub extractPlantMasterData {
  my $hash     = shift;
  my $daref    = shift;
  my $forecast = shift;
  my $addon    = shift;
  my $data     = shift;                       # gelieferte Rohdaten
  my $name     = $hash->{NAME};
  my ($amount,$unit);
  
  Log3 ($name, 4, "$name - ##### extracting plant master data #### ");
  
  $forecast = eval{decode_json($forecast)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                   return;
                                                 };
  my $lv       = $stpl{plantMasterData}{level};
  my $plantOid = $forecast->{'ForecastTimeframes'}->{'PlantOid'};                 # Plant ID aus JSON filtern
  
  if(!$plantOid) {                                                                # Plant ID aus Cookie Header extrhieren wenn nicht mi JSON geliefert (kommt vor)
      Log3 ($name, 4, "$name - Plant ID  not set in data, get it from cookie ...");
      my $sc = $data->header('Set-Cookie') // "";
      ($plantOid) = $sc =~ /plantOid=([0-9a-z-]*);/x;
  }
  
  if ($plantOid) {                                                                # wichtig für erweiterte Selektionen
      Log3 ($name, 4, "$name - Plant ID: ".$plantOid);
      $hash->{HELPER}{PLANTOID} = $plantOid;
      BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "NULL", "PLANTOID:$plantOid"], 1);      
  } 
  else {
      Log3 ($name, 4, "$name - Plant ID  not set !");
  }
  
  my $ppp = $forecast->{'PlantPeakPower'};
  if($ppp) {
      $amount = $forecast->{'PlantPeakPower'}{'Amount'}; 
      $unit   = $forecast->{'PlantPeakPower'}{'StandardUnit'}{'Symbol'};

      push @$daref, "${lv}_PlantPeakPower:$amount $unit";             
      
      Log3 $name, 4, "$name - plantMasterData \"PlantPeakPower Amount\": $amount";
      Log3 $name, 4, "$name - plantMasterData \"PlantPeakPower Symbol\": $unit";
  }
  
return;
}

################################################################
##                     Auswertung Anlagenlogbuch
################################################################
sub extractPlantLogbook {
  my $hash     = shift;
  my $daref    = shift;
  my $logdata  = shift;
  my $name     = $hash->{NAME};
  
  Log3 ($name, 4, "$name - ##### extracting plant logbook data #### ");
  
  $logdata = eval{decode_json($logdata)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                 return;
                                               };
  my $lv = $stpl{plantLogbook}{level};
  
  my %colors = (                                                # Farben Highlighting
      "Info"        => qq{<span style="color: green;">},
      "Warning"     => qq{<span style="color: orange;">},
      "Warnung"     => qq{<span style="color: orange;">},
      "Disturbance" => qq{<span style="color: red;">},
      "Störung"     => qq{<span style="color: red;">},
      "Error"       => qq{<span style="color: red;">},
      "Fehler"      => qq{<span style="color: red;">},
      "Unknown"     => qq{<span style="color: black;">},
  );
  my $eh = "</span>";                                           # Endestring Highlighting
      
  if(ref $logdata->{aaData} eq "ARRAY") {
      my @ld = @{$logdata->{aaData}};
      for my $ae (@ld) {                                        # jedes ARRAY-Element ist ein HASH
          my $dn   = encode("utf8", $ae->{DeviceName} );
          my $ts   = $ae->{Timestamp};                   
          my $dc   = encode("utf8", $ae->{Description} );
          my $id   = $ae->{MessageId};
          my ($mt) = $ae->{MessageType} =~ /alt='(.*?)'/x;
          $mt      = encode("utf8", $mt) // "Unknown";
          
          my $bh   = $colors{$mt};
          my $v    = qq{<html><b>$bh $mt $eh</b><br>$dn : $ts <br>$dc</html>};

          push @$daref, "${lv}_LogbookEntry_${id}:$v";
      }
  }

return;
}

################################################################
##    Auswertung Consumer Plan Data (aus forecastData)
################################################################
sub extractConsumerPlanData {
  my $hash     = shift;
  my $daref    = shift;
  my $forecast = shift;
  my $name     = $hash->{NAME};
  my %consumers;
  my ($key,$val);
  
  Log3 ($name, 4, "$name - ##### extracting consumer plan data #### ");
  
  $forecast = eval{decode_json($forecast)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                   return;
                                                 };
  
  my $lv = $stpl{forecastData}{level};
  
  # Schleife über alle Consumer Objekte
  my $i = 0;
  for my $c (@{$forecast->{'Consumers'}}) {
      $consumers{"${i}_ConsumerName"} = $c->{'ConsumerName'};
      $consumers{"${i}_ConsumerOid"}  = $c->{'ConsumerOid'};
      $i++;
  }
  
  if(%consumers && $forecast->{'ForecastTimeframes'}) {
      # es sind Vorhersagen zu geplanten Verbraucherschaltzeiten vorhanden
      # TimeFrameStart/End Kind: "Utc"
      for my $c (@{$forecast->{'ForecastTimeframes'}{'PlannedTimeFrames'}}) {
          my $tkind          = $c->{'TimeFrameStart'}->{'Kind'};                             # Zeitart: Unspecified, Utc
          my $deviceOid      = $c->{'DeviceOid'};   
          my $timeFrameStart = TimeAdjust($hash,$c->{'TimeFrameStart'}{'DateTime'},$tkind);  # wandele UTC        
          my $timeFrameEnd   = TimeAdjust($hash,$c->{'TimeFrameEnd'}{'DateTime'},$tkind);    # wandele UTC
          my $tz             = $c->{'TimeFrameStart'}{'Kind'};
          for my $k (keys(%consumers)) {
               $val = $consumers{$k};
               if($val eq $deviceOid && $k =~ /^(\d+)_.*$/x) {
                   my $lfn = $1;
                   $consumers{"${lfn}_PlannedOpTimeStart"} = $timeFrameStart;
                   $consumers{"${lfn}_PlannedOpTimeEnd"}   = $timeFrameEnd;
               }
          }          
      }
  }

  if(%consumers) {
      for my $key (keys(%consumers)) {
          Log3 $name, 4, "$name - Consumer data \"$key\": ".encode("utf8", $consumers{$key});
          if($key =~ /ConsumerName/x && $key =~ /^(\d+)_.*$/x) {
               my $lfn = $1; 
               my $cn  = $consumers{"${lfn}_ConsumerName"};            # Verbrauchername
               next if(!$cn);
               $cn     = replaceJunkSigns($cn);                        # evtl. Umlaute/Leerzeichen im Verbrauchernamen ersetzen
               my $pos = $consumers{"${lfn}_PlannedOpTimeStart"};      # geplanter Start
               my $poe = $consumers{"${lfn}_PlannedOpTimeEnd"};        # geplantes Ende
               my $rb  = "${lv}_${cn}_PlannedOpTimeBegin"; 
               my $re  = "${lv}_${cn}_PlannedOpTimeEnd";
               my $rp  = "${lv}_${cn}_Planned";
               
               if($pos) {              
                   push @$daref, "$rb:$pos";
                   push @$daref, "$rp:yes";                   
               } 
               else {
                   push @$daref, "$rb:undefined";  
                   push @$daref, "$rp:no";
               }   
               
               if($poe) {             
                   push @$daref, "$re:$poe";              
               } 
               else {
                   push @$daref, "$re:undefined"; 
               }                  
          }
      }
  }
  
return;
} 

################################################################
##          Auswertung Consumer Stammdaten
################################################################
sub extractConsumerMasterdata {
  my $hash      = shift; 
  my $daref     = shift;
  my $clivedata = shift;
  my $name      = $hash->{NAME};
  my %consumers;
  my %hcon;
  my ($i,$res);
  
  Log3 ($name, 4, "$name - ##### extracting consumer master data #### ");
  
  $clivedata = eval{decode_json($clivedata)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                     return;
                                                   };
  my $lv = $stpl{consumerMasterdata}{level};
  
  # allen Consumer Objekten die ID zuordnen
  $i = 0;
  for my $c (@{$clivedata->{'MeasurementData'}}) {
      $consumers{"${i}_ConsumerName"} = $c->{'DeviceName'};
      $consumers{"${i}_ConsumerOid"}  = $c->{'Consume'}{'ConsumerOid'};
      $consumers{"${i}_ConsumerLfd"}  = $i;
      my $cn                          = $consumers{"${i}_ConsumerName"};          # Verbrauchername
      next if(!$cn);
      $cn                             = replaceJunkSigns($cn);
      
      $hcon{$i}{DeviceName}           = $cn;
      $hcon{$i}{ConsumerOid}          = $consumers{"${i}_ConsumerOid"};
      $hcon{$i}{SerialNumber}         = $c->{'SerialNumber'};
      $hcon{$i}{SUSyID}               = $c->{'SUSyID'};
      
      $i++;
  }
  
  for my $key (keys %hcon) {          
      for my $parname (keys %{$hcon{$key}}) { 
          my $val = $hcon{$key}{$parname};
          
          next if(!$val);
          
          Log3 ($name, 4, "$name - CONSUMER master data: $key -> $parname = $val");
          BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, "NULL", "CONSUMER:$key:$parname:$val"], 1);
      }
  }
  
return;
}

################################################################
##          Auswertung Consumer Current Data
################################################################
sub extractConsumerCurrentdata {
  my $hash      = shift; 
  my $daref     = shift;
  my $clivedata = shift;
  my $name      = $hash->{NAME};
  my %consumers;
  my ($i,$res);
  
  Log3 ($name, 4, "$name - ##### extracting consumer current data #### ");
  
  $clivedata = eval{decode_json($clivedata)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                                     return;
                                                   };
  my $lv = $stpl{consumerCurrentdata}{level};
  
  # allen Consumer Objekten die ID zuordnen
  $i = 0;
  for my $c (@{$clivedata->{'MeasurementData'}}) {
      $consumers{"${i}_ConsumerName"} = $c->{'DeviceName'};
      $consumers{"${i}_ConsumerOid"}  = $c->{'Consume'}{'ConsumerOid'};
      $consumers{"${i}_ConsumerLfd"}  = $i;
      my $cpower                      = $c->{'Consume'}{'Measurement'};           # aktueller Energieverbrauch in W
      my $cn                          = $consumers{"${i}_ConsumerName"};          # Verbrauchername
      next if(!$cn);
      $cn                             = replaceJunkSigns($cn);
 
      push @$daref, "${lv}_${cn}_Power:".$cpower." W" if(defined $cpower);  
      
      $i++;
  }
  
  if(%consumers && $clivedata->{'ParameterData'}) {
      # es sind Daten zu den Verbrauchern vorhanden
      # Kind: "Utc" ?
      $i = 0;
      for my $c (@{$clivedata->{'ParameterData'}}) {
          my $tkind            = $c->{'Parameters'}[0]{'Timestamp'}{'Kind'};                               # Zeitart: Unspecified, Utc
          my $GriSwStt         = $c->{'Parameters'}[0]{'Value'};                                           # on: 1, off: 0
          my $GriSwAuto        = $c->{'Parameters'}[1]{'Value'};                                           # automatic = 1
          my $OperationAutoEna = $c->{'Parameters'}[2]{'Value'};                                           # Automatic Betrieb erlaubt ?
          my $ltchange         = TimeAdjust($hash,$c->{'Parameters'}[0]{'Timestamp'}{'DateTime'},$tkind);  # letzter Schaltzeitpunkt der Bluetooth-Steckdose (Verbraucher)
          my $cn               = $consumers{"${i}_ConsumerName"};                                          # Verbrauchername
          next if(!$cn);
          $cn = replaceJunkSigns($cn);                                                                     # evtl. Umlaute/Leerzeichen im Verbrauchernamen ersetzen
          
          if(!$GriSwStt && $GriSwAuto) {
              $res = "off (automatic)";
          } 
          elsif (!$GriSwStt && !$GriSwAuto) {
              $res = "off";         
          } 
          elsif ($GriSwStt) {
              $res = "on";           
          } 
          else {
              $res = "undefined";            
          }
          
          push @$daref, "${lv}_${cn}_Switch:$res";
          push @$daref, "${lv}_${cn}_SwitchLastTime:$ltchange";
          
          $i++;
      }
  }
  
return;
}

################################################################
##          Auswertung Consumer History Energy Data
##          $tf = Time Frame
################################################################
sub extractConsumerHistData {                                                  ## no critic 'complexity'
  my $hash   = shift;
  my $daref  = shift;
  my $chdata = shift;
  my $tf     = shift;
  my $name   = $hash->{NAME};
  my %consumers;
  my ($i,$gcr,$gct,$pcr,$pct,$tct,$bcr,$bct);
  
  Log3 ($name, 4, "$name - ##### extracting consumer history data #### ");
  
  $chdata = eval{decode_json($chdata)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                               return;
                                             };
  my $livelvl = $stpl{liveData}{level};
  my $bataval = (defined(ReadingsNum($name,"${livelvl}_BatteryIn", undef)) || defined(ReadingsNum($name,"${livelvl}_BatteryOut", undef)))?1:0;     # Identifikation ist Battery vorhanden ?
  
  my $dlvl = $stpl{consumerDayData}{level};
  my $mlvl = $stpl{consumerMonthData}{level};
  my $ylvl = $stpl{consumerYearData}{level};
  
  # allen Consumer Objekte die ID zuordnen
  $i = 0;
  for my $c (@{$chdata->{'Consumers'}}) {
      $consumers{"${i}_ConsumerName"} = $c->{'DeviceName'};
      $consumers{"${i}_ConsumerOid"}  = $c->{'ConsumerOid'};
      $consumers{"${i}_ConsumerLfd"}  = $i;
      my $cpower                      = $c->{'TotalEnergy'}{'Measurement'};    # Energieverbrauch im Timeframe in Wh                                         
      my $cn                          = $consumers{"${i}_ConsumerName"};       # Verbrauchername
      next if(!$cn);
      $cn                             = replaceJunkSigns($cn);
      
      if($tf =~ /month|year/x) {
          $tct = $c->{'TotalEnergyMix'}{'TotalConsumptionTotal'};              # Gesamtverbrauch im Timeframe in Wh
          $gcr = $c->{'TotalEnergyMix'}{'GridConsumptionRelative'};            # Anteil des Netzbezugs im Timeframe am Gesamtverbrauch in %
          $gct = $c->{'TotalEnergyMix'}{'GridConsumptionTotal'};               # Anteil des Netzbezugs im Timeframe am Gesamtverbrauch in Wh
          $pcr = $c->{'TotalEnergyMix'}{'PvConsumptionRelative'};              # Anteil des PV-Nutzung im Timeframe am Gesamtverbrauch in %
          $pct = $c->{'TotalEnergyMix'}{'PvConsumptionTotal'};                 # Anteil des PV-Nutzung im Timeframe am Gesamtverbrauch in Wh
          $bcr = $c->{'TotalEnergyMix'}{'BatteryConsumptionRelative'};         # Anteil der Batterie-Nutzung im Timeframe am Gesamtverbrauch in %
          $bct = $c->{'TotalEnergyMix'}{'BatteryConsumptionTotal'};            # Anteil der Batterie-Nutzung im Timeframe am Gesamtverbrauch in Wh
      }
      
      push @$daref, "${dlvl}_${cn}_EnergyTotalDay:".           sprintf("%.0f", $cpower). " Wh"    if(defined($cpower) && $tf eq "day");  
      push @$daref, "${mlvl}_${cn}_EnergyTotalMonth:".         sprintf("%.0f", $cpower). " Wh"    if(defined($cpower) && $tf eq "month");
      push @$daref, "${ylvl}_${cn}_EnergyTotalYear:".          sprintf("%.0f", $cpower). " Wh"    if(defined($cpower) && $tf eq "year");             
      
      push @$daref, "${mlvl}_${cn}_EnergyRelativeMonthGrid:".  sprintf("%.0f", $gcr).    " %"     if(defined($gcr)    && $tf eq "month");
      push @$daref, "${mlvl}_${cn}_EnergyTotalMonthGrid:".     sprintf("%.0f", $gct).    " Wh"    if(defined($gct)    && $tf eq "month");                    
      push @$daref, "${mlvl}_${cn}_EnergyRelativeMonthPV:".    sprintf("%.0f", $pcr).    " %"     if(defined($pcr)    && $tf eq "month");  
      push @$daref, "${mlvl}_${cn}_EnergyTotalMonthPV:".       sprintf("%.0f", $pct).    " Wh"    if(defined($pct)    && $tf eq "month");       
      push @$daref, "${mlvl}_${cn}_EnergyRelativeMonthBatt:".  sprintf("%.0f", $bcr).    " %"     if(defined($bcr)    && $bataval && $tf eq "month");         
      push @$daref, "${mlvl}_${cn}_EnergyTotalMonthBatt:".     sprintf("%.0f", $bct).    " Wh"    if(defined($bct)    && $bataval && $tf eq "month");                 
      
      push @$daref, "${ylvl}_${cn}_EnergyRelativeYearGrid:".   sprintf("%.0f", $gcr).    " %"     if(defined($gcr)    && $tf eq "year");   
      push @$daref, "${ylvl}_${cn}_EnergyTotalYearGrid:".      sprintf("%.0f", $gct).    " Wh"    if(defined($gct)    && $tf eq "year");                      
      push @$daref, "${ylvl}_${cn}_EnergyRelativeYearPV:".     sprintf("%.0f", $pcr).    " %"     if(defined($pcr)    && $tf eq "year");   
      push @$daref, "${ylvl}_${cn}_EnergyTotalYearPV:".        sprintf("%.0f", $pct).    " Wh"    if(defined($pct)    && $tf eq "year");  
      push @$daref, "${ylvl}_${cn}_EnergyRelativeYearBatt:".   sprintf("%.0f", $bcr).    " %"     if(defined($bcr)    && $bataval && $tf eq "year");        
      push @$daref, "${ylvl}_${cn}_EnergyTotalYearBatt:".      sprintf("%.0f", $bct).    " Wh"    if(defined($bct)    && $bataval && $tf eq "year");
      
      $i++;
  }
  
return;
}

################################################################
#          Auswertung Daten aus Hilfsroutinen
################################################################
sub extractHelperData {
  my $hash      = shift;
  my $daref     = shift;             # Referenz zum Datenarray
  my $jdata     = shift;             # empfangene JSON-Daten
  my $addon     = shift;             # ein optionales AddOn
  my $tag       = shift;             # Kennzeichen der abgerufenen Daten/ der Abrufroutine
  
  my $name      = $hash->{NAME};
  my $sd;
  
  Log3 ($name, 4, "$name - extracting Helper data ");
  
  my $data = eval{decode_json($jdata)} or do { Log3 ($name, 2, "$name - ERROR - can't decode JSON Data"); 
                                               return;
                                             };

  if(ref $data eq "HASH") {
      while (my ($k,$v) = each %$data) {
          push @$daref, "$tag:$v";
      }
  }
  
return; 
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub sortVersionNum {
  my ($sseq,@versions) = @_;

  my @sorted = map {$_->[0]}
               sort {$a->[1] cmp $b->[1]}
               map {[$_, pack "C*", split /\./x]} @versions;
             
  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./x} @versions;
  
  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }
  
return @sorted;
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
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
      if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: 76_SMAPortal.pm 23105 2020-11-05 22:24:21Z DS_Starter $ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } 
      else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 76_SMAPortal.pm 23105 2020-11-05 22:24:21Z DS_Starter $ im Kopf komplett! vorhanden )
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          ## no critic 'VERSION'                                      
      }
  } 
  else {
      # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

################################################################
#         delete Readings und Hash HELPER-Daten
#         $conspl = providerLevel berücksichtigen
################################################################
sub deleteData {
  my $hash   = shift;
  my $conspl = shift;
  my $name   = $hash->{NAME};
  my @allrds = keys%{$defs{$name}{READINGS}};
 
  my $bl     = "state|lastCycleTime|Counter|loginState|usedUserAgent";         # Blacklist
  
  my $pblvl  = $stpl{plantLogbook}{level};                                     # Logbuch Level
  
  my $ballvl = $stpl{balanceDayData}{level}  ."|".                             # Level von balanceDayData, balanceMonthData, balanceYearData
               $stpl{balanceMonthData}{level}."|".
               $stpl{balanceYearData}{level};
  
  if(!$subs{$name}{forecastData}{doit}) {                                      # wenn forecastData nicht abgerufen werden sollen -> Wetterdaten im HELPER löschen
      my $fclvl = $stpl{forecastData}{level};
      delete $hash->{HELPER}{"${fclvl}_ThisHour_WeatherId"};
      for my $i (1..23) {
          $i = sprintf("%02d",$i);
          delete $hash->{HELPER}{"${fclvl}_NextHour${i}_WeatherId"};
      }
  }
   
  if($conspl) {                                                                # Readings löschen wenn nicht im providerLevel enthalten
      my $pbl = q{};
      for my $prl (keys %{$mandatory{$name}}) {                                # mandatory Provider die abgerufen wurden
          my $lvlm = $mandatory{$name}{$prl}{level};                           # Forum: https://forum.fhem.de/index.php/topic,102112.msg1078990.html#msg1078990
          if ($lvlm) {
              $pbl .= "|^".$lvlm."_";
          }
      }
      
      for my $prl (keys %{$subs{$name}}) {                                     # Provider die abgerufen wurden
          my $lvl;
          if($subs{$name}{$prl}{doit}) {
              $lvl = $subs{$name}{$prl}{level};                                # Forum: https://forum.fhem.de/index.php/topic,102112.msg1078990.html#msg1078990
          }
          
          if ($lvl) {
              $pbl .= "|^".$lvl."_";
          }
      }      
      $bl .= $pbl;                                                             # Blacklist ergänzen

      for my $key(@allrds) {
          delete $defs{$name}{READINGS}{$key} if($key !~ /$bl/x);
          delete $defs{$name}{READINGS}{$key} if($key =~ /^$pblvl/x);          # Logbuchreadings immer löschen
          delete $defs{$name}{READINGS}{$key} if($key =~ /^$ballvl/x);         # balance(Day|Month)Data Readings immer löschen wegen möglicher Relativverschiebung           
      }
      
      return;
  } 

  for my $key(@allrds) {                                                       # alle Readings löschen bis auf Standard-Blacklist
      delete($defs{$name}{READINGS}{$key}) if($key !~ /$bl/x);
  }

return;
}

################################################################
#    erstelle addon als relative oder reale Datumangabe
################################################################
sub createDateAddon {
  my $paref  = shift;
  my $name   = $paref->{name};
  my $bal    = $paref->{bal};
  my $tag    = $paref->{tag};
  my $daref  = $paref->{daref};
  my $addon  = $paref->{addon};
  my $addon1 = $paref->{addon1};

  if(AttrVal($name,"useRelativeNames", 0)) {                              # current-x verwenden statt effektives Datum
      $addon .= $bal;
      my $lv  = $stpl{$tag}{level};
      
      push @$daref, "${lv}_${addon}_Date:$addon1";  
  }
  else {
      $addon .= $addon1;
  }

return $addon;
}

################################################################
#       statistische Counter managen 
#       $name = Name Device
#       $rd   = Name des Zählerreadings
################################################################
sub handleCounter {
  my $name  = shift;
  my $rd    = shift;
    
  my $cstring      = ReadingsVal($name, $rd, "");
  my ($day,$count) = split(":", $cstring);
  my $mday         = (localtime(time))[3];
  if(!$day || $day != $mday) {
      $count = 0;
      $day   = $mday;
      Log3 ($name, 2, qq{$name - reset counter "$rd" to >0< }) if(!$defs{$name}->{HELPER}{$rd});
      $defs{$name}->{HELPER}{$rd} = 1;                              # nur im fork setzen um doppelten Logeintrag zu vermeiden
  }
  $count++;
  $cstring = "$rd:$day:$count";  
  BlockingInformParent("FHEM::SMAPortal::setFromBlocking", [$name, $cstring, "NULL"], 1);

return;
}

###################################################################
#        Werte aus BlockingCall heraus setzen
#   Erwartete Liste:
#   @setl = $name,$setread,$retries,$helper
###################################################################
sub setFromBlocking {
  my $name    = shift;
  my $setread = shift // "NULL";
  my $helper  = shift // "NULL";
  my $hash    = $defs{$name};
  
  if($setread ne "NULL") {
      my @cparts = split ":", $setread, 2;
      readingsSingleUpdate($hash, $cparts[0], $cparts[1], 1);
  }
  
  if($helper ne "NULL") {
      my ($hnam,$k1,$k2,$k3) = split ":", $helper, 4;
      
      if(defined $k3) {
          $hash->{HELPER}{"$hnam"}{"$k1"}{"$k2"} = $k3;
      } 
      elsif (defined $k2) {
          $hash->{HELPER}{"$hnam"}{"$k1"} = $k2;
      } 
      else {
          $hash->{HELPER}{"$hnam"} = $k1;
      }
  }

return 1;
}

################################################################
#        Reading aus BlockingCall heraus löschen
#   Erwartete Liste:
#   @params = $name,$reading
################################################################
sub delReadingFromBlocking {
  my $name    = shift;
  my $reading = shift;
  my $hash    = $defs{$name};

  readingsDelete($hash, $reading);

return 1;
}

################################################################
#   errechnet wieviel Tage ein gegebener Monat eines 
#   bestimmten Jahres hat
#   $m: realer Monat (1..12)
#   $y: reales Jahr  (2020)
################################################################
sub daysInMonth {
  my $m = shift;
  my $y = shift;

  my $dim = $m-2?30+($m*3%7<4):28+!($y%4||$y%400*!($y%100));

return $dim;
}

################################################################
#                   Timestamp korrigieren
################################################################
sub TimeAdjust {
  my ($hash,$t,$tkind) = @_;
  $t =~ s/T/ /x;
  my ($datehour, $rest) = split(/:/x,$t,2);
  my ($year, $month, $day, $hour) = $datehour =~ /(\d+)-(\d\d)-(\d\d)\s+(\d\d)/x;
  
  #  Time::timegm - a UTC version of mktime()
  #  proto: $time = timegm($sec,$min,$hour,$mday,$mon,$year);
  my $epoch = timegm(0,0,$hour,$day,$month-1,$year);
  
  #  proto: ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $isdst = (localtime($epoch))[8];
  
  if(lc($tkind) =~ /unspecified/x) {
      if($isdst) {
          $epoch = $epoch - 7200;
      } 
      else {
          $epoch = $epoch - 3600;
      }
  }
  
  my ($lyear,$lmonth,$lday,$lhour) = (localtime($epoch))[5,4,3,2];
  
  $lyear += 1900;                  # year is 1900 based
  $lmonth++;                       # month number is zero based
  
  if(AttrVal("global","language","EN") eq "DE") {
      return (sprintf("%02d.%02d.%04d %02d:%s", $lday,$lmonth,$lyear,$lhour,$rest));
  } 
  else {
      return (sprintf("%04d-%02d-%02d %02d:%s", $lyear,$lmonth,$lday,$lhour,$rest));
  }
}

###############################################################################
#       Umlaute und ungültige Zeichen für Readingerstellung ersetzen 
###############################################################################
sub replaceJunkSigns { 
  my ($rn) = @_;

  $rn =~ s/ß/ss/gx;
  $rn =~ s/ä/ae/gx;
  $rn =~ s/ö/oe/gx;
  $rn =~ s/ü/ue/gx;
  $rn =~ s/Ä/Ae/gx;
  $rn =~ s/Ö/Oe/gx;
  $rn =~ s/Ü/Ue/gx; 
  $rn = makeReadingName($rn);  
  
return($rn);
}

###############################################################################
#                  Subroutine für Portalgrafik
###############################################################################
sub PortalAsHtml {                                                                      ## no critic 'complexity'
  my ($name,$wlname,$ftui) = @_;
  my $hash                 = $defs{$name};
  my $ret                  = "";
  
  my ($icon,$colorv,$colorc,$maxhours,$hourstyle,$header,$legend,$legend_txt,$legend_style);
  my ($val,$height,$fsize,$html_start,$html_end,$wlalias,$weather,$colorw,$maxVal,$show_night,$type,$kw);
  my ($maxDif,$minDif,$maxCon,$v,$z2,$z3,$z4,$show_diff,$width,$w,$hdrDetail,$hdrAlign);
  my $he;                                                                               # Balkenhöhe
  my (%pv,%is,%t,%we,%di,%co);
  my @pgCDev;
  
  # Kontext des aufrufenden SMAPortalSPG-Devices speichern für Refresh
  $hash->{HELPER}{SPGDEV}    = $wlname;                                                 # Name des aufrufenden SMAPortalSPG-Devices
  $hash->{HELPER}{SPGROOM}   = $FW_room   ? $FW_room   : "";                            # Raum aus dem das SMAPortalSPG-Device die Funktion aufrief
  $hash->{HELPER}{SPGDETAIL} = $FW_detail ? $FW_detail : "";                            # Name des SMAPortalSPG-Devices (wenn Detailansicht)
  
  my $fdo  = $subs{$name}{forecastData}{doit};                                          
  my $fmin = $subs{$name}{forecastData}{level};                                         # LXX Level
  my $fmaj = $subs{$name}{forecastData}{level};
  my $ldlv = $subs{$name}{liveData}{level};
  my $cclv = $subs{$name}{consumerCurrentdata}{level};
  
  my ($pv0,$pv1);
  $pv0  = ReadingsNum($name, "${fmin}_ThisHour_PvMeanPower",   undef) if($fmin);
  $pv1  = ReadingsNum($name, "${fmaj}_NextHour01_PvMeanPower", undef) if($fmaj);
  
  if(!$hash || !defined($defs{$wlname}) || !$fdo || !defined $pv0 || !defined $pv1) {
      $height = AttrNum($wlname, 'beamHeight', 200);   
      $ret   .= "<table class='roomoverview'>";
      $ret   .= "<tr style='height:".$height."px'>";
      $ret   .= "<td>";
      if(!$hash) {                                                                      ## no critic "Cascading"
          $ret .= "Device \"$name\" doesn't exist !";
      } 
      elsif (!defined($defs{$wlname})) {
          $ret .= "Graphic device \"$wlname\" doesn't exist !";
      } 
      elsif (!$fdo) {
          $ret .= qq{The attribute "providerLevel" of device "$name" must contain the level "forecastData" and data must be retrieved !};
      } 
      elsif (!defined $pv0) {
          $ret .= "Awaiting minor level forecast data ...";
      } 
      elsif (!defined $pv1) {
          $ret .= "Awaiting major level forecast data ...";
      }

      $ret .= "</td>";
      $ret .= "</tr>";
      $ret .= "</table>";
      return $ret;
  }

  @pgCDev                  = split(',',AttrVal($wlname,"consumerList",""));             # definierte Verbraucher ermitteln
  ($legend_style, $legend) = split('_',AttrVal($wlname,'consumerLegend','icon_top'));

  $legend = '' if(($legend_style eq 'none') || (!int(@pgCDev)));
  
  # Verbraucherlegende und Steuerung
  if ($legend) {
      for (@pgCDev) {
          my($txt,$im) = split(':',$_);                                                 # $txt ist der Verbrauchername
          my $cmdon   = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name $txt on')\"";
          my $cmdoff  = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name $txt off')\"";
          my $cmdauto = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name $txt auto')\"";
          
          if ($ftui && $ftui eq "ftui") {
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

  # Parameter f. Anzeige extrahieren
  $maxhours   =  AttrNum($wlname, 'hourCount',             24);
  $hourstyle  =  AttrVal($wlname, 'hourStyle',          undef);
  $colorv     =  AttrVal($wlname, 'beamColor',          undef);
  $colorc     =  AttrVal($wlname, 'beamColor2',      '000000');                         # schwarz wenn keine Userauswahl;
  $icon       =  AttrVal($wlname, 'consumerAdviceIcon', undef);
  $html_start =  AttrVal($wlname, 'htmlStart',          undef);                         # beliebige HTML Strings die vor der Grafik ausgegeben werden
  $html_end   =  AttrVal($wlname, 'htmlEnd',            undef);                         # beliebige HTML Strings die nach der Grafik ausgegeben werden

  $type       =  AttrVal($wlname, 'layoutType',          'pv');
  $kw         =  AttrVal($wlname, 'Wh/kWh',              'Wh');

  $height     =  AttrNum($wlname, 'beamHeight',           200);
  $width      =  AttrNum($wlname, 'beamWidth',              6);                         # zu klein ist nicht problematisch
  $w          =  $width*$maxhours;                                                      # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  $fsize      =  AttrNum($wlname, 'spaceSize',             24);
  $maxVal     =  AttrNum($wlname, 'maxPV',                  0);                         # dyn. Anpassung der Balkenhöhe oder statisch ?

  $show_night =  AttrNum($wlname, 'showNight',              0);                         # alle Balken (Spalten) anzeigen ?
  $show_diff  =  AttrVal($wlname, 'showDiff',            'no');                         # zusätzliche Anzeige $di{} in allen Typen
  $weather    =  AttrNum($wlname, 'showWeather',            1);
  $colorw     =  AttrVal($wlname, 'weatherColor',       undef);

  $wlalias    =  AttrVal($wlname, 'alias',            $wlname);
  $header     =  AttrNum($wlname, 'showHeader', 1); 
  $hdrAlign   =  AttrVal($wlname, 'headerAlignment', 'center');                         # ermöglicht per attr die Ausrichtung der Tabelle zu setzen
  $hdrDetail  =  AttrVal($wlname, 'headerDetail',       'all');                         # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten

  # Icon Erstellung, mit @<Farbe> ergänzen falls einfärben
  # Beispiel mit Farbe:  $icon = FW_makeImage('light_light_dim_100.svg@green');
 
  $icon    = FW_makeImage($icon) if (defined($icon));
  my $co4h = ReadingsNum ($name,"${fmin}_Next04Hours_Consumption", 0);
  my $coRe = ReadingsNum ($name,"${fmin}_RestOfDay_Consumption",   0); 
  my $coTo = ReadingsNum ($name,"${fmin}_Tomorrow_Consumption",    0);
  my $coCu = ReadingsNum ($name,"${ldlv}_GridConsumption",         0);

  my $pv4h = ReadingsNum ($name,"${fmin}_Next04Hours_PV",          0);
  my $pvRe = ReadingsNum ($name,"${fmin}_RestOfDay_PV",            0); 
  my $pvTo = ReadingsNum ($name,"${fmin}_Tomorrow_PV",             0);
  my $pvCu = ReadingsNum ($name,"${ldlv}_PV",                      0);

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

  
  # Headerzeile generieren                                                                                                             
  if ($header) {
      my $lang    = AttrVal("global", "language", "EN");
      my $alias   = AttrVal($name,    "alias",    "SMA Sunny Portal");                                      # Linktext als Aliasname oder "SMA Sunny Portal"
      my $dlink   = "<a href=\"/fhem?detail=$name\">$alias</a>";      
      my $lup     = ReadingsTimestamp($name, "${fmin}_ForecastToday_Consumption", "0000-00-00 00:00:00");   # letzter Forecast Update  
      
      my $lupt    = "last update:";  
      my $lblPv4h = "next&nbsp;4h:";
      my $lblPvRe = "today:";
      my $lblPvTo = "tomorrow:";
      my $lblPvCu = "actual";
     
      if(AttrVal("global","language","EN") eq "DE") {                              # Header globales Sprachschema Deutsch
          $lupt    = "Stand:"; 
          $lblPv4h = encode("utf8", "nächste&nbsp;4h:");
          $lblPvRe = "heute:";
          $lblPvTo = "morgen:";
          $lblPvCu = "aktuell";
      }  

      $header  = "<table align=\"$hdrAlign\">"; 
      
      # Header Link + Status + Update Button 
      if($hdrDetail eq "all" || $hdrDetail eq "statusLink") {
          my ($year, $month, $day, $time) = $lup =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x;
          
          if(AttrVal("global","language","EN") eq "DE") {
             $lup = "$day.$month.$year&nbsp;$time"; 
          } 
          else {
             $lup = "$year-$month-$day&nbsp;$time"; 
          }

          my $cmdupdate = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name getData')\"";    # Update Button generieren        

          if ($ftui && $ftui eq "ftui") {
              $cmdupdate = "\"ftui.setFhemStatus('set $name getData')\"";     
          }
          
          my $upstate  = ReadingsVal($name,"state", "undef");
          my $upicon   = "<img src=\"$FW_ME/www/images/default/1px-spacer.png\">";
          
          if ($upstate =~ /ok/ix) {
              $upicon = "<a onClick=$cmdupdate><img src=\"$FW_ME/www/images/default/10px-kreis-gruen.png\"></a>";
          } 
          elsif ($upstate =~ /running/ix) {
              $upicon = "<img src=\"$FW_ME/www/images/default/10px-kreis-gelb.png\"></a>";
          } 
          else {
              $upicon = "<a onClick=$cmdupdate><img src=\"$FW_ME/www/images/default/10px-kreis-rot.png\"></a>";
          }
  
          $header .= "<tr><td colspan=\"3\" align=\"left\"><b>".$dlink."</b></td><td colspan=\"3\" align=\"right\">(".$lupt."&nbsp;".$lup.")&nbsp;".$upicon."</td></tr>";
      }
      
      # Header Information pv 
      if($hdrDetail eq "all" || $hdrDetail eq "pv" || $hdrDetail eq "pvco") {   
          $header .= "<tr>";
          $header .= "<td><b>PV&nbsp;=></b></td>"; 
          $header .= "<td><b>$lblPvCu</b></td> <td align=right>$pvCu</td>" if($subs{$name}{liveData}{doit}); 
          $header .= "<td><b>$lblPv4h</b></td> <td align=right>$pv4h</td>"; 
          $header .= "<td><b>$lblPvRe</b></td> <td align=right>$pvRe</td>"; 
          $header .= "<td><b>$lblPvTo</b></td> <td align=right>$pvTo</td>"; 
          $header .= "</tr>";
      }
      
      # Header Information co 
      if($hdrDetail eq "all" || $hdrDetail eq "co" || $hdrDetail eq "pvco") {
          $header .= "<tr>";
          $header .= "<td><b>CO&nbsp;=></b></td>";
          $header .= "<td><b>$lblPvCu</b></td> <td align=right>$coCu</td>" if($subs{$name}{liveData}{doit});           
          $header .= "<td><b>$lblPv4h</b></td> <td align=right>$co4h</td>"; 
          $header .= "<td><b>$lblPvRe</b></td> <td align=right>$coRe</td>"; 
          $header .= "<td><b>$lblPvTo</b></td> <td align=right>$coTo</td>"; 
          $header .= "</tr>"; 
      }

      $header .= "</table>";     
  }

  # Werte aktuelle Stunde
  $pv{0} = ReadingsNum($name,"${fmin}_ThisHour_PvMeanPower", 0);
  $co{0} = ReadingsNum($name,"${fmin}_ThisHour_Consumption", 0);
  $di{0} = $pv{0} - $co{0}; 
  $is{0} = (ReadingsVal($name,"${fmin}_ThisHour_IsConsumptionRecommended",'no') eq 'yes' ) ? $icon : undef;  
  $we{0} = $hash->{HELPER}{"${fmin}_ThisHour_WeatherId"} if($weather);              # für Wettericons 
  $we{0} = $we{0} // 999;

  if(AttrVal("global","language","EN") eq "DE") {
      (undef,undef,undef,$t{0}) = ReadingsVal($name,"${fmin}_ThisHour_Time",'0') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
  } 
  else {
      (undef,undef,undef,$t{0}) = ReadingsVal($name,"${fmin}_ThisHour_Time",'0') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
  }
  
  $t{0} = int($t{0});                                                        # zum Rechnen Integer ohne führende Null

  ###########################################################
  # get consumer list and display it in portalGraphics 
  for (@pgCDev) {
      my ($itemName, undef) = split(':',$_);
      $itemName =~ s/^\s+|\s+$//gx;                                           #trim it, if blanks were used
      $_        =~ s/^\s+|\s+$//gx;                                           #trim it, if blanks were used
    
      #check if listed device is planned
      if (ReadingsVal($name, "${fmaj}_".$itemName."_Planned", "no") eq "yes") {
          #get start and end hour
          my ($start, $end);                                                   # werden auf Balken Pos 0 - 23 umgerechnet, nicht auf Stunde !!, Pos = 24 -> ungültige Pos = keine Anzeige

          if(AttrVal("global","language","EN") eq "DE") {
              (undef,undef,undef,$start) = ReadingsVal($name,"${fmaj}_".$itemName."_PlannedOpTimeBegin",'00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name,"${fmaj}_".$itemName."_PlannedOpTimeEnd",'00.00.0000 24')   =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
          } 
          else {
              (undef,undef,undef,$start) = ReadingsVal($name,"${fmaj}_".$itemName."_PlannedOpTimeBegin",'0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name,"${fmaj}_".$itemName."_PlannedOpTimeEnd",'0000-00-00 24')   =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
          }

          $start   = int($start);
          $end     = int($end);
          my $flag = 0;                                                 # default kein Tagesverschieber

          #correct the hour for accurate display
          if ($start < $t{0}) {                                         # consumption seems to be tomorrow
              $start = 24-$t{0}+$start;
              $flag  = 1;
          } 
          else { 
              $start -= $t{0};          
          }

          if ($flag) {                                                  # consumption seems to be tomorrow
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

  $maxVal = (!$maxVal) ? $pv{0} : $maxVal;                  # Startwert wenn kein Wert bereits via attr vorgegeben ist
  $maxCon = $co{0};                                         # für Typ co
  $maxDif = $di{0};                                         # für Typ diff
  $minDif = $di{0};                                         # für Typ diff

  for my $i (1..$maxhours-1) {
     $pv{$i} = ReadingsNum($name,"${fmaj}_NextHour".sprintf("%02d",$i)."_PvMeanPower",0);             # Erzeugung
     $co{$i} = ReadingsNum($name,"${fmaj}_NextHour".sprintf("%02d",$i)."_Consumption",0);             # Verbrauch
     $di{$i} = $pv{$i} - $co{$i};

     $maxVal = $pv{$i} if ($pv{$i} > $maxVal); 
     $maxCon = $co{$i} if ($co{$i} > $maxCon);
     $maxDif = $di{$i} if ($di{$i} > $maxDif);
     $minDif = $di{$i} if ($di{$i} < $minDif);

     $is{$i} = (ReadingsVal($name,"${fmaj}_NextHour".sprintf("%02d",$i)."_IsConsumptionRecommended",'no') eq 'yes') ? $icon : undef;
     $we{$i} = $hash->{HELPER}{"${fmaj}_NextHour".sprintf("%02d",$i)."_WeatherId"} if($weather);      # für Wettericons 
     $we{$i} = $we{$i} // 999;

     if(AttrVal("global","language","EN") eq "DE") {
        (undef,undef,undef,$t{$i}) = ReadingsVal($name,"${fmaj}_NextHour".sprintf("%02d",$i)."_Time",'0') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
     } 
     else {
        (undef,undef,undef,$t{$i}) = ReadingsVal($name,"${fmaj}_NextHour".sprintf("%02d",$i)."_Time",'0') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
     }

     $t{$i} = int($t{$i});                                  # keine führende 0
  }

  ######################################
  # Tabellen Ausgabe erzeugen
  
  # Wenn Table class=block alleine steht, zieht es bei manchen Styles die Ausgabe auf 100% Seitenbreite
  # lässt sich durch einbetten in eine zusätzliche Table roomoverview eindämmen
  # Die Tabelle ist recht schmal angelegt, aber nur so lassen sich Umbrüche erzwingen
   
  $ret  = "<html>";
  $ret .= $html_start if (defined($html_start));
  $ret .= "<style>TD.smaportal {text-align: center; padding-left:1px; padding-right:1px; margin:0px;}</style>";
  $ret .= "<table class='roomoverview' width='$w' style='width:".$w."px'><tr class='devTypeTr'></tr>";
  $ret .= "<tr><td class='smaportal'>";
  $ret .= "\n<table class='block'>";                         # das \n erleichtert das Lesen der debug Quelltextausgabe

  if ($header) {                                             # Header ausgeben 
      $ret .= "<tr class='odd'>";
      # mit einem extra <td></td> ein wenig mehr Platz machen, ergibt i.d.R. weniger als ein Zeichen
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$header</td></tr>";
  }

  if ($legend_txt && ($legend eq 'top')) {
      $ret .= "<tr class='odd'>";
      $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$legend_txt</td></tr>";
  }

  if ($weather) {
      $ret .= "<tr class='even'><td class='smaportal'></td>";      # freier Platz am Anfang

      for my $i (0..$maxhours-1) {                                 # keine Anzeige bei Null Ertrag bzw. in der Nacht , Typ pcvo & diff haben aber immer Daten in der Nacht
          if ($pv{$i} || $show_night || ($type eq 'pvco') || ($type eq 'diff')) {
              # FHEM Wetter Icons (weather_xxx) , Skalierung und Farbe durch FHEM Bordmittel
              my $icon_name = weather_icon($we{$i});               # unknown -> FHEM Icon Fragezeichen im Kreis wird als Ersatz Icon ausgegeben
              Log3($name, 3,"$name - unknown SMA Portal weather id: ".$we{$i}.", please inform the maintainer") if($icon_name eq 'unknown');
              
              $icon_name .='@'.$colorw if (defined($colorw));
              $val       = FW_makeImage($icon_name);
      
              $val  ='<b>???<b/>' if ($val eq $icon_name);         # passendes Icon beim User nicht vorhanden ! ( attr web iconPath falsch/prüfen/update ? )
              $ret .= "<td class='smaportal' width='$width' style='margin:1px; vertical-align:middle align:center; padding-bottom:1px;'>$val</td>";
          
          } 
          else {                                                 # Kein Ertrag oder show_night = 0
              $ret .= "<td></td>"; $we{$i} = undef; 
          } 
          # mit $we{$i} = undef kann man unten leicht feststellen ob für diese Spalte bereits ein Icon ausgegeben wurde oder nicht
      }
      
      $ret .= "<td class='smaportal'></td></tr>";                  # freier Platz am Ende der Icon Zeile
  }

  if ($show_diff eq 'top') {                                       # Zusätzliche Zeile Ertrag - Verbrauch
      $ret .= "<tr class='even'><td class='smaportal'></td>";      # freier Platz am Anfang
      
      for my $i (0..$maxhours-1) {
          $val  = formatVal6($di{$i},$kw,$we{$i});
          $val  = ($di{$i} < 0) ?  '<b>'.$val.'<b/>' : '+'.$val;   # negativ Zahlen in Fettschrift 
          $ret .= "<td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td>"; 
      }
      $ret .= "<td class='smaportal'></td></tr>"; # freier Platz am Ende 
  }

  $ret .= "<tr class='even'><td class='smaportal'></td>"; # Neue Zeile mit freiem Platz am Anfang

  for my $i (0..$maxhours-1) {
      # Achtung Falle, Division by Zero möglich, 
      # maxVal kann gerade bei kleineren maxhours Ausgaben in der Nacht leicht auf 0 fallen  
      $height = 200 if (!$height);                                 # Fallback, sollte eigentlich nicht vorkommen, außer der User setzt es auf 0
      $maxVal = 1   if (!$maxVal);
      $maxCon = 1   if (!$maxCon);

      # Der zusätzliche Offset durch $fsize verhindert bei den meisten Skins 
      # dass die Grundlinie der Balken nach unten durchbrochen wird
      if ($type eq 'co') { 
          $he = int(($maxCon-$co{$i})/$maxCon*$height) + $fsize;             # he - freier der Raum über den Balken.
          $z3 = int($height + $fsize - $he);                                 # Resthöhe
      } 
      elsif ($type eq 'pv') {
          $he = int(($maxVal-$pv{$i})/$maxVal*$height) + $fsize;
          $z3 = int($height + $fsize - $he);
      } 
      elsif ($type eq 'pvco') {
          # Berechnung der Zonen
          # he - freier der Raum über den Balken. fsize wird nicht verwendet, da bei diesem Typ keine Zahlen über den Balken stehen 
          # z2 - der Ertrag ggf mit Icon
          # z3 - der Verbrauch , bei zu kleinem Wert wird der Platz komplett Zone 2 zugeschlagen und nicht angezeigt
          # z2 und z3 nach Bedarf tauschen, wenn der Verbrauch größer als der Ertrag ist

          $maxVal = $maxCon if ($maxCon > $maxVal);                          # wer hat den größten Wert ?

          if ($pv{$i} > $co{$i}) {                                           # pv oben , co unten
              $z2 = $pv{$i}; $z3 = $co{$i}; 
          } 
          else {                                                           # tauschen, Verbrauch ist größer als Ertrag
              $z3 = $pv{$i}; $z2 = $co{$i}; 
          }

          $he = int(($maxVal-$z2)/$maxVal*$height);
          $z2 = int(($z2 - $z3)/$maxVal*$height);

          $z3 = int($height - $he - $z2);                                    # was von maxVal noch übrig ist
          
          if ($z3 < int($fsize/2)) {                                         # dünnen Strichbalken vermeiden / ca. halbe Zeichenhöhe
              $z2 += $z3; $z3 = 0; 
          }
      } 
      else {                                                                 # Typ dif
          # Berechnung der Zonen
          # he - freier der Raum über den Balken , Zahl positiver Wert + fsize
          # z2 - positiver Balken inkl Icon
          # z3 - negativer Balken
          # z4 - Zahl negativer Wert + fsize

          my ($px_pos,$px_neg);
          my $maxPV = 0;                                                     # ToDo:  maxPV noch aus Attribut maxPV ableiten

          if ($maxPV) {                                                      # Feste Aufteilung +/- , jeder 50 % bei maxPV = 0
              $px_pos = int($height/2);
              $px_neg = $height - $px_pos;                                   # Rundungsfehler vermeiden
          } 
          else {                                                             # Dynamische hoch/runter Verschiebung der Null-Linie        
              if  ($minDif >= 0 ) {                                          # keine negativen Balken vorhanden, die Positiven bekommen den gesammten Raum
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

          if ($di{$i} >= 0) {                                                # Zone 2 & 3 mit ihren direkten Werten vorbesetzen
              $z2 = $di{$i};
              $z3 = abs($minDif);
          } 
          else {
              $z2 = $maxDif;
              $z3 = abs($di{$i}); # Nur Betrag ohne Vorzeichen
          }
 
          # Alle vorbesetzen Werte umrechnen auf echte Ausgabe px
          $he = (!$px_pos) ? 0 : int(($maxDif-$z2)/$maxDif*$px_pos);           # Teilung durch 0 vermeiden
          $z2 = ($px_pos - $he) ;

          $z4 = (!$px_neg) ? 0 : int((abs($minDif)-$z3)/abs($minDif)*$px_neg); # Teilung durch 0 unbedingt vermeiden
          $z3 = ($px_neg - $z4);

          # Beiden Zonen die Werte ausgeben könnten muß fsize als zusätzlicher Raum zugeschlagen werden !
          $he += $fsize; 
          $z4 += $fsize if ($z3);                                              # komplette Grafik ohne negativ Balken, keine Ausgabe von z3 & z4
      }

      # das style des nächsten TD bestimmt ganz wesentlich das gesammte Design
      # das \n erleichtert das lesen des Seitenquelltext beim debugging
      # vertical-align:bottom damit alle Balken und Ausgaben wirklich auf der gleichen Grundlinie sitzen

      $ret .="<td style='text-align: center; padding-left:1px; padding-right:1px; margin:0px; vertical-align:bottom; padding-top:0px'>\n";

      if (($type eq 'pv') || ($type eq 'co')) {
          $v   = ($type eq 'co') ? $co{$i} : $pv{$i} ; 
          $v   = 0 if (($type eq 'co') && !$pv{$i} && !$show_night);           # auch bei type co die Nacht ggf. unterdrücken
          $val = formatVal6($v,$kw,$we{$i});

          $ret .="<table width='100%' height='100%'>";                         # mit width=100% etwas bessere Füllung der Balken
          $ret .="<tr class='even' style='height:".$he."px'>";
          $ret .="<td class='smaportal' style='vertical-align:bottom'>".$val."</td></tr>";

          if ($v || $show_night) {
              # Balken nur einfärben wenn der User via Attr eine Farbe vorgibt, sonst bestimmt class odd von TR alleine die Farbe
              my $style = "style=\"padding-bottom:0px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style   .= (defined($colorv)) ? " background-color:#$colorv\"" : '"';         # Syntaxhilight 

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

          $ret .="<table width='100%' height='100%'>\n";                      # mit width=100% etwas bessere Füllung der Balken

          if ($he) {                                                          # der Freiraum oben kann beim größten Balken ganz entfallen
              $ret .="<tr class='even' style='height:".$he."px'><td class='smaportal'></td></tr>";
          }

          if ($pv{$i} > $co{$i}) {                                            # wer ist oben, co pder pv ? Wert und Farbe für Zone 2 & 3 vorbesetzen
              $val     = formatVal6($pv{$i},$kw,$we{$i});
              $color1  = $colorv;
              $style1  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style1 .= (defined($color1)) ? " background-color:#$color1\"" : '"';
              if ($z3) {                                                      # die Zuweisung können wir uns sparen wenn Zone 3 nachher eh nicht ausgegeben wird
                  $v       = formatVal6($co{$i},$kw,$we{$i});
                  $color2  = $colorc;
                  $style2  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
                  $style2 .= (defined($color2)) ? " background-color:#$color2\"" : '"';
              } 
          } else {
              $val     = formatVal6($co{$i},$kw,$we{$i});
              $color1  = $colorc;
              $style1  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style1 .= (defined($color1)) ? " background-color:#$color1\"" : '"';
              if ($z3) {
                  $v       = formatVal6($pv{$i},$kw,$we{$i});
                  $color2  = $colorv;
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

         if ($z3) {                                                         # die Zone 3 lassen wir bei zu kleinen Werten auch ganz weg 
             $ret .= "<tr class='odd' style='height:".$z3."px'>";
             $ret .= "<td align='center' class='smaportal' ".$style2.">$v</td></tr>";
         }
      } 
      else {                                                              # Type dif
          my $style  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";

          $ret .="<table width='100%' border='0'>\n";                       # Tipp : das nachfolgende border=0 auf 1 setzen hilft sehr Ausgabefehler zu endecken

          $val = ($di{$i} >= 0) ? formatVal6($di{$i},$kw,$we{$i}) : '';
          $val = '&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;' if ($di{$i} == 0);       # Sonderfall , hier wird die 0 gebraucht !

          if ($val) {
              $ret .="<tr class='even' style='height:".$he."px'>";
              $ret .="<td class='smaportal' style='vertical-align:bottom'>".$val."</td></tr>";
          }

          if ($di{$i} >= 0) {                                               # mit Farbe 1 colorv füllen
              $style .= (defined($colorv)) ? " background-color:#$colorv\"" : '"';
              $z2 = 1 if ($di{$i} == 0);                                    # Sonderfall , 1px dünnen Strich ausgeben
              $ret .= "<tr class='odd' style='height:".$z2."px'>";
              $ret .= "<td align='center' class='smaportal' ".$style.">";
              $ret .= $is{$i} if (defined $is{$i});
              $ret .="</td></tr>";
          } 
          else {                                                            # ohne Farbe
              $z2 = 2 if ($di{$i} == 0);                                    # Sonderfall, hier wird die 0 gebraucht !
              if ($z2 && $val) {                                            # z2 weglassen wenn nicht unbedigt nötig bzw. wenn zuvor he mit val keinen Wert hatte
                  $ret .= "<tr class='even' style='height:".$z2."px'>";
                  $ret .="<td class='smaportal'></td></tr>";
              }
          }
     
          if ($di{$i} < 0) {                                                         # Negativ Balken anzeigen ?
              $style .= (defined($colorc)) ? " background-color:#$colorc\"" : '"';   # mit Farbe 2 colorc füllen
              $ret   .= "<tr class='odd' style='height:".$z3."px'>";
              $ret   .= "<td align='center' class='smaportal' ".$style."></td></tr>";
          } 
          elsif ($z3) {                                                              # ohne Farbe
              $ret .="<tr class='even' style='height:".$z3."px'>";
              $ret .="<td class='smaportal'></td></tr>";
          }

          if ($z4) {                                                                 # kann entfallen wenn auch z3 0 ist
              $val  = ($di{$i} < 0) ? formatVal6($di{$i},$kw,$we{$i}) : '&nbsp;';
              $ret .="<tr class='even' style='height:".$z4."px'>";
              $ret .="<td class='smaportal' style='vertical-align:top'>".$val."</td></tr>";
          }
      }

      if ($show_diff eq 'bottom') {                                        # zusätzliche diff Anzeige
          $val  = formatVal6($di{$i},$kw,$we{$i});
          $val  = ($di{$i} < 0) ?  '<b>'.$val.'<b/>' : '+'.$val;           # Kommentar siehe oben bei show_diff eq top
          $ret .= "<tr class='even'><td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td></tr>"; 
      }

      $ret  .= "<tr class='even'><td class='smaportal' style='vertical-align:bottom; text-align:center;'>";
      $t{$i} = $t{$i}.$hourstyle if(defined($hourstyle));                  # z.B. 10:00 statt 10
      $ret  .= $t{$i}."</td></tr></table></td>";                           # Stundenwerte ohne führende 0
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
###############################################################################
sub formatVal6 {
  my ($v,$kw,$w)  = @_;
  my $n           = '&nbsp;';                               # positive Zahl

  if ($v < 0) {
      $n = '-';                                             # negatives Vorzeichen merken
      $v = abs($v);
  }

  if ($kw eq 'kWh') {                                       # bei Anzeige in kWh muss weniger aufgefüllt werden
      $v  = sprintf('%.1f',($v/1000));
      $v  += 0;                                             # keine 0.0 oder 6.0 etc

      return ($n eq '-') ? ($v*-1) : $v if defined($w) ;

      my $t = $v - int($v);                                 # Nachkommstelle ?

      if (!$t) {                                            # glatte Zahl ohne Nachkommastelle
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

  return ($n eq '-')?($v*-1):$v if defined($w);

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
      '0' => 'weather_sun',                         # Sonne (klar)                                          # vorhanden
      '1' => 'weather_cloudy_light',                # leichte Bewölkung (1/3)                               # vorhanden
      '2' => 'weather_cloudy',                      # mittlere Bewölkung (2/3)                              # vorhanden
      '3' => 'weather_cloudy_heavy',                # starke Bewölkung (3/3)                                # vorhanden
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

######################################################################################################
#      Refresh eines Raumes aus $hash->{HELPER}{SPGROOM}
#      bzw. Longpoll von SMAPortal bzw. eines SMAPortalSPG Devices wenn $hash->{HELPER}{SPGDEV} gefüllt 
#      $hash, $pload (1=Page reload), SMAPortalSPG-Event (1=Event)
######################################################################################################
sub SPGRefresh { 
  my ($hash,$pload,$lpollspg) = @_;
  my $name;
  if (ref $hash ne "HASH") {
      ($name,$pload,$lpollspg) = split ",",$hash;
      $hash = $defs{$name};
  } 
  else {
      $name = $hash->{NAME};
  }
  my $fpr = 0;
  
  # Kontext des SMAPortalSPG-Devices speichern für Refresh
  my $sd = $hash->{HELPER}{SPGDEV}    ? $hash->{HELPER}{SPGDEV}    : "\"n.a.\"";     # Name des aufrufenden SMAPortalSPG-Devices
  my $sr = $hash->{HELPER}{SPGROOM}   ? $hash->{HELPER}{SPGROOM}   : "\"n.a.\"";     # Raum aus dem das SMAPortalSPG-Device die Funktion aufrief
  my $sl = $hash->{HELPER}{SPGDETAIL} ? $hash->{HELPER}{SPGDETAIL} : "\"n.a.\"";     # Name des SMAPortalSPG-Devices (wenn Detailansicht)
  $fpr   = AttrVal($hash->{HELPER}{SPGDEV},"forcePageRefresh",0) if($hash->{HELPER}{SPGDEV});
  Log3($name, 4, "$name - Refresh - caller: $sd, callerroom: $sr, detail: $sl, pload: $pload, forcePageRefresh: $fpr, event_Spgdev: $lpollspg");
  
  # Page-Reload
  if($pload && ($hash->{HELPER}{SPGROOM} && !$hash->{HELPER}{SPGDETAIL} && !$fpr)) {
      # trifft zu wenn in einer Raumansicht
      my @rooms = split(",",$hash->{HELPER}{SPGROOM});
      for (@rooms) {
          my $room = $_;
          { map { FW_directNotify("FILTER=room=$room", "#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") }   ## no critic 'void context';
      }
  } 
  elsif ($pload && (!$hash->{HELPER}{SPGROOM} || $hash->{HELPER}{SPGDETAIL})) {
      # trifft zu bei Detailansicht oder im FLOORPLAN bzw. Dashboard oder wenn Seitenrefresh mit dem 
      # SMAPortalSPG-Attribut "forcePageRefresh" erzwungen wird
      { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") }                            ## no critic 'void context';
  } 
  else {
      if($fpr) {
          { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") }                        ## no critic 'void context';
      }
  }
  
  # parentState des SMAPortalSPG-Device updaten
  my @spgs = devspec2array("TYPE=SMAPortalSPG");
  my $st   = ReadingsVal($name, "state", "initialized");  
  for(@spgs) {   
      if($defs{$_}{PARENT} eq $name) {
          next if(IsDisabled($defs{$_}{NAME}));
          readingsBeginUpdate($defs{$_});
          readingsBulkUpdate($defs{$_},"parentState", $st);
          readingsBulkUpdate($defs{$_},"state", "updated");
          readingsEndUpdate($defs{$_}, 1);
      }
  }
        
return;
}

1;

=pod
=encoding utf8
=item summary    Module for communication with the SMA Sunny Portal
=item summary_DE Modul zur Kommunikation mit dem SMA Sunny Portal

=begin html

<a name="SMAPortal"></a>
<h3>SMAPortal</h3>
<ul>

   With this module it is possible to fetch data from the <a href="https://www.sunnyportal.com">SMA Sunny Portal</a> and switch
   consumers (e.g. bluetooth plug sockets) if any are present.
   At the momentent that are the following data: <br><br>
   <ul>
    <ul>
     <li>Live data (Consumption and PV-Generation) </li>
     <li>Battery data (In/Out) and usage data of consumers </li>
     <li>Various balance data and statistical data (also of the consumers connected to the SMA Sunny Homemanager) </li>
     <li>Weather data delivered from SMA for the facility location </li>
     <li>Forecast data (Consumption and PV-Generation) inclusive suggestion times to switch comsumers on </li>
     <li>the planned times by the Sunny Home Manager to switch consumers on and the current state of consumers (if present) </li>
    </ul> 
   </ul>
   <br>
   
   Graphic data can also be integrated into FHEM Tablet UI with the 
   <a href="https://wiki.fhem.de/wiki/FTUI_Widget_SMAPortalSPG">"SMAPortalSPG Widget"</a>. <br>
   <br>
   
   <b>Preparation </b> <br><br>
    
   <ul>   
    This module use the Perl module JSON which has typically to be installed discrete. <br>
    On Debian linux based systems that can be done by command: <br><br>
    
    <code>sudo apt-get install libjson-perl</code>      <br><br>
    
    Subsequent there are an overview of used Perl modules: <br><br>
    
    POSIX           <br>
    JSON            <br>
    Data::Dumper    <br>                  
    Time::HiRes     <br>
    Time::Local     <br>
    Blocking        (FHEM-Modul) <br>
    GPUtils         (FHEM-Modul) <br>
    FHEM::Meta      (FHEM-Modul) <br>
    LWP::UserAgent  <br>
    HTTP::Cookies   <br>
    MIME::Base64    <br>
    Encode          <br>
    utf8            <br>
    
    <br><br>  
   </ul>
  
   <a name="SMAPortalDefine"></a>
   <b>Definition</b>
   <ul>
    <br>
    A SMAPortal device will be defined by: <br><br>
    
    <ul>
      <b>define &lt;name&gt; SMAPortal</b>
    </ul>
    <br>
   
    After the definition of the device the credentials for the SMA Sunny Portal must be saved with the 
    following command: <br><br>
   
    <ul> 
     <b>set &lt;name&gt; credentials &lt;Username&gt; &lt;Password&gt; </b>
    </ul> 
    <br>

    After a successful login, only the asset master data are retrieved. 
    The attribute <a href="#providerLevel">providerLevel</a> is used to set the data suppliers its data 
    the device should retrieve. If no Sunny Home Manager is installed, the attribute
    <a href="#noHomeManager">noHomeManager</a> must be set. 
   </ul>
   <br><br>   
    
   <a name="SMAPortalSet"></a>
   <b>Set </b>
   <ul>
   <br>
     <ul>
     <a name="createPortalGraphic"></a>
     <li><b> createPortalGraphic &lt;Generation | Consumption | Generation_Consumption | Differential&gt; </b> <br>  
     Creates graphical devices to show the SMA Sunny Portal forecast data in several layouts. 
     The attribute "providerLevel" must contain "forecastData". <br>
     With the <a href="#SMAPortalSPGattr">"attributes of the graphic device"</a> the appearance and coloration of the forecast 
     data in the created graphic device can be adjusted.     
     </ul>   
     </li>
     <br>
     
     <ul>
     <li><b> credentials &lt;username&gt; &lt;password&gt; </b> </li>  
     Set Username / Password used for the login into the SMA Sunny Portal.   
     </ul> 
     <br>
     
     <ul>
     <a name="consumer"></a>
     <li><b> &lt;consumer name&gt; &lt;on | off | auto&gt; </b> <br> 
     Once consumer data are available, the consumer are shown in the Set and can be switched to on, off or the automatic mode (auto)
     that means the consumer are controlled by the Sunny Home Manager.    
     </li>      
     </ul>
     <br>
     
     <ul>
     <a name="getData"></a> 
     <li><b> getData </b> <br> 
     Identical to the "get data" command. Simplifies the use of the attribute "webCmd" in the FHEMWEB.  
     </ul> 
     </li>
   
   </ul>
   <br><br>
   
   <a name="SMAPortalGet"></a>
   <b>Get</b>
   <ul>
    <br>
    
    <ul>
      <a name="data"></a>
      <li><b> data </b> <br> 
      This command fetch the data from the SMA Sunny Portal manually. 
    </ul>
    </li> 
    <br>
    
    <ul>
      <a name="storedCredentials"></a>
      <li><b> storedCredentials </b> <br>  
      The saved credentials are displayed in a popup window.
    </ul>
    </li>
   </ul>  
   <br><br>
   
   <a name="SMAPortalAttr"></a>
   <b>Attributes</b>
   <ul>
     <br>
     <ul>

       <a name="balanceDay"></a>
       <li><b>balanceDay &lt;YYYY-MM-DD&gt; [current current-x &lt;YYYY-MM-DD&gt; &lt;YYYY-MM-DD&gt; ...] </b><br>
       Defines from which days the data provider "balanceDayData" delivers the data.
       In the relative specification <b>current-x</b> is <b>x</b> the number of days that are subtracted from the current day.        
       The days are separated by spaces, current = current day. <br>
       (default: current day) <br><br>
       
        <ul>
         <b>Examples:</b><br>
         attr &lt;name&gt; balanceDay current 2020-08-07 2020-08-06 2020-08-05 <br> 
         attr &lt;name&gt; balanceDay current current-1 current-2              <br>         
        </ul> 
       </li><br>
       
       <a name="balanceMonth"></a>
       <li><b>balanceMonth &lt;YYYY-MM&gt; [current current-x &lt;YYYY-MM&gt; &lt;YYYY-MM&gt; ...] </b><br>
       Defines from which months the data provider "balanceMonthData" delivers the data. 
       In the relative specification <b>current-x</b> is <b>x</b> the number of months subtracted from the current month.
       The month data is separated by spaces, current = current month. <br>
       (default: current month) <br><br>
       
        <ul>
         <b>Examples:</b><br>
         attr &lt;name&gt; balanceMonth current 2019-07 2019-06 2019-05 <br> 
         attr &lt;name&gt; balanceMonth current current-12 current-24   <br>          
        </ul> 
       </li><br>
       
       <a name="balanceYear"></a>
       <li><b>balanceYear &lt;YYYY&gt; [current current-x &lt;YYYY&gt; &lt;YYYY&gt; &lt;YYYY&gt; ...] </b><br>
       Defines from which years the data provider "balanceYearData" delivers the data. 
       In the relative specification <b>current-x</b>, <b>x</b> is the number of years that are subtracted from the current year.
       The years are separated by spaces, current = current year. <br>
       (default: current year) <br><br>
       
        <ul>
         <b>Examples:</b><br>
         attr &lt;name&gt; balanceYear current 2019 2018 2017        <br> 
         attr &lt;name&gt; balanceYear current current-1 current-2   <br>         
        </ul> 
       </li><br>
       
       <a name="cookieDelete"></a>
       <li><b>cookieDelete </b><br>
       Defines the method of cookie management (deletion). <br>
       (default: auto)
       <br>
       
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>auto</b>             </td><td>- Cookie file is managed according to an internal procedure                                     </td></tr>
          <tr><td> <b>afterAttempt</b>     </td><td>- Cookie file is deleted after each failed read attempt                                         </td></tr>
          <tr><td> <b>afterCycle</b>       </td><td>- Cookie file is deleted after each read cycle (covers several attempts)                        </td></tr>
          <tr><td> <b>afterRun</b>         </td><td>- Cookie file is deleted after each pass of a data retrieval                                    </td></tr>
          <tr><td> <b>afterAttempt&Run</b> </td><td>- Cookie file is deleted after each failed read attempt <b>and</b> run through a data retrieval </td></tr>
       </table>
       </ul> 
       
       </li><br>
       
       <a name="cookieLocation"></a>
       <li><b>cookieLocation &lt;Pfad/File&gt; </b><br>
       The path and filename of received Cookies. <br>
       (default: ./log/&lt;name&gt;_cookie.txt)
       <br><br> 
  
        <ul>
         <b>Example:</b><br>
         attr &lt;name&gt; cookieLocation ./log/cookies.txt <br>    
        </ul>        
       </li><br>
       
       <a name="disable"></a>
       <li><b>disable</b><br>
       Deactivate/activate the device. </li><br>

       <a name="interval"></a>
       <li><b>interval &lt;seconds&gt; </b><br>
       Time interval for continuous data retrieval from the aus dem SMA Sunny Portal (default: 300 seconds). <br>
       if the interval is set to "0", no continuous data retrieval is executed and has to be triggered manually by the 
       "get &lt;name&gt; data" command.  <br><br>
              
       <ul>
         <b>Note:</b> 
         The retrieval interval must not be less than 180 seconds. As of previous experiences SMA suffers an interval of  
         120 seconds although the SMA terms and conditions don't permit an automatic data fetch by computer programs.
       </ul>
       </li><br>
       
       <a name="noHomeManager"></a>
       <li><b>noHomeManager</b><br>
       Must be set if no Sunny Home Manager is installed. 
       </li><br>
       
       <a name="plantLogbookApprovalState"></a>
       <li><b>plantLogbookApprovalState</b><br>
       With this attribute the entries are filtered according to their status. <br>
       (default: Any)
       <br>
       
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>Any</b>          </td><td>-  all messages </td></tr>
          <tr><td> <b>NotApproved</b>  </td><td>-  unconfirmed messages </td></tr>
       </table>
       </ul>         
       </li><br>
       
       <a name="plantLogbookTypes"></a>
       <li><b>plantLogbookTypes</b><br>
       This attribute defines the message types of the asset logbook to be selected. 
       A maximum of the latest 25 logbook entries of all set types are displayed. <br>
       (default: Warning,Disturbance,Error) 
       </li><br>
       
       <a name="providerLevel"></a>
       <li><b>providerLevel </b><br>
       The scope of the data to be generated is set. Asset and consumer master data is always retrieved. 
       <br><br>
    
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>liveData</b>            </td><td>- generates readings of the current generation and consumption data </td></tr>
          <tr><td> <b>weatherData</b>         </td><td>- Weather data offered by SMA are retrieved </td></tr>
          <tr><td> <b>forecastData</b>        </td><td>- Forecast data of generation/consumption and consumer planning data are generated (an SMA Home Manager must be available) </td></tr>
          <tr><td> <b>consumerCurrentdata</b> </td><td>- current consumer data are generated </td></tr>
          <tr><td> <b>consumerDayData</b>     </td><td>- consumer data day are generated </td></tr>
          <tr><td> <b>consumerMonthData</b>   </td><td>- consumer data month are generated </td></tr>
          <tr><td> <b>consumerYearData</b>    </td><td>- consumer data year are generated </td></tr>
          <tr><td> <b>plantLogbook</b>        </td><td>- the maximum of 25 most recent entries of the plant logbook are retrieved </td></tr>
          <tr><td> <b>balanceDayData</b>      </td><td>- Statistics data of the day are retrieved (see attribute <a href="#balanceDay">balanceDay</a>) </td></tr>
          <tr><td> <b>balanceMonthData</b>    </td><td>- Statistics data of the month are retrieved (see attribute <a href="#balanceMonth">balanceMonth</a>) </td></tr>
          <tr><td> <b>balanceYearData</b>     </td><td>- Statistical data of the year are retrieved (see attribute <a href="#balanceYear">balanceYear</a>) </td></tr>
          <tr><td> <b>balanceTotalData</b>    </td><td>- Total statistics data are retrieved </td></tr>
       </table>
       </ul>     
       <br>       
       </li><br>
       
       <a name="showPassInLog"></a>
       <li><b>showPassInLog</b><br>
       If set, the used password will be displayed in Logfile output. 
       (default: 0) </li><br>
       
       <a name="userAgent"></a>
       <li><b>userAgent &lt;identifier&gt; </b><br>
       An user agent identifier for identifikation against the SMA Sunny Portal can be specified.
       <br><br> 
  
        <ul>
         <b>Example:</b><br>
         attr &lt;name&gt; userAgent Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:65.0) Gecko/20100101 Firefox/65.0 <br>    
        </ul>           
       </li><br> 
       
       <a name="useRelativeNames"></a>
       <li><b>useRelativeNames </b><br>
       When using relative dates <b>current-x</b> (see balance.* attributes) the created reading name contains
       also the relative instead of the real date. <br>
       (default: real date)       
       </li><br>

       <a name="verbose5Data"></a>
       <li><b>verbose5Data </b><br>
       The attribute value verbose 5 is used to generate very large amounts of data. 
       The verbose 5 outputs of interest can be selected specifically. <br>
       (default: none)
       </li><br>       
   
     </ul>
   </ul>
   <br> 

</ul>


=end html
=begin html_DE

<a name="SMAPortal"></a>
<h3>SMAPortal</h3>
<ul>

   Mit diesem Modul können Daten aus dem <a href="https://www.sunnyportal.com">SMA Sunny Portal</a> abgerufen werden.
   Momentan sind es: <br><br>
   <ul>
    <ul>
     <li>Live-Daten (Verbrauch und PV-Erzeugung) </li>
     <li>verschiedene Bilanzdaten und Statistikdaten (auch der an den SMA Sunny Homemanager angeschlossenen Verbraucher) </li>
     <li>Batteriedaten (In/Out) sowie Nutzungsdaten durch Verbraucher </li>
     <li>Wetter-Daten von SMA für den Anlagenstandort </li>
     <li>Prognosedaten (Verbrauch und PV-Erzeugung) inklusive Verbraucherempfehlung </li>
     <li>die durch den Sunny Home Manager geplanten Schaltzeiten und aktuellen Status von Verbrauchern (sofern vorhanden) </li>
    </ul> 
   </ul>
   <br>
   
   Die Portalgrafik kann ebenfalls in FHEM Tablet UI mit dem 
   <a href="https://wiki.fhem.de/wiki/FTUI_Widget_SMAPortalSPG">"SMAPortalSPG Widget"</a> integriert werden. <br>
   <br>
   
   <b>Vorbereitung </b> <br><br>
    
   <ul>   
    Dieses Modul nutzt das Perl-Modul JSON welches üblicherweise nachinstalliert werden muss. <br>
    Auf Debian-Linux basierenden Systemen kann es installiert werden mit: <br><br>
    
    <code>sudo apt-get install libjson-perl</code>      <br><br>
    
    Überblick über die Perl-Module welche von SMAPortal genutzt werden: <br><br>
    
    POSIX           <br>
    JSON            <br>
    Data::Dumper    <br>                  
    Time::HiRes     <br>
    Time::Local     <br>
    Blocking        (FHEM-Modul) <br>
    GPUtils         (FHEM-Modul) <br>
    FHEM::Meta      (FHEM-Modul) <br>
    LWP::UserAgent  <br>
    HTTP::Cookies   <br>
    MIME::Base64    <br>
    Encode          <br>
    utf8            <br>
    
    <br><br>  
   </ul>
  
   <a name="SMAPortalDefine"></a>
   <b>Definition</b>
   <ul>
    <br>
    Ein SMAPortal-Device wird definiert mit: <br><br>
    
    <ul>
      <b>define &lt;Name&gt; SMAPortal</b>
    </ul>
    <br>
   
    Nach der Definition des Devices müssen die Zugangsparameter für das SMA Sunny Portal gespeichert werden 
    mit dem Befehl: <br><br>
   
    <ul> 
     <b>set &lt;Name&gt; credentials &lt;Username&gt; &lt;Passwort&gt; </b>
    </ul>
    <br>
    
    Nach einem erfolgreichen Login werden nur die Anlagenstammdaten abgerufen. 
    Mit dem Attribut <a href="#providerLevel">providerLevel</a> werden die Datenlieferanten eingestellt, die durch das 
    Device abgerufen werden sollen. Ist kein Sunny Home Manager installiert, muss das Attribut 
    <a href="#noHomeManager">noHomeManager</a> gesetzt werden.
   </ul>
   <br><br>   
    
   <a name="SMAPortalSet"></a>
   <b>Set </b>
   <ul>
   <br>
     <ul>
     <a name="createPortalGraphic"></a>
     <li><b> createPortalGraphic &lt;Generation | Consumption | Generation_Consumption | Differential&gt; </b> <br>  
     Erstellt Devices zur grafischen Anzeige der SMA Sunny Portal Prognosedaten in verschiedenen Layouts. 
     Das Attribut "providerLevel" muss auf den Level "forecastData" enthalten. <br>
     Mit den <a href="#SMAPortalSPGattr">"Attributen des Grafikdevices"</a> können Erscheinungsbild und 
     Farbgebung der Prognosedaten in den erstellten Grafik-Devices angepasst werden.     
     </ul>   
     </li>
     <br>
     
     <ul>
     <a name="credentials"></a> 
     <li><b> credentials &lt;username&gt; &lt;password&gt; </b> <br> 
     Setzt Username / Passwort zum Login in das SMA Sunny Portal.   
     </ul> 
     </li>
     <br>
     
     <ul>
     <a name="getData"></a> 
     <li><b> getData </b> <br> 
     Identisch zum "get data" Befehl. Vereinfacht die Benutzung des Attributs "webCmd" im FHEMWEB.   
     </ul> 
     </li>
     <br>
     
     <ul>
     <a name="Verbrauchername"></a>
     <li><b> &lt;Verbrauchername&gt; &lt;on | off | auto&gt; </b> <br>  
     Es werden die an den SMA Sunny Homemanager angeschlossene Verbraucher (Bluetooth Steckdosen) angeboten sobald sie vom
     Modul erkannt wurden.
     Sobald diese Daten vorliegen, werden die vorhandenen Verbraucher im Set angezeigt und können eingeschaltet, ausgeschaltet
     bzw. auf die Steuerung durch den Sunny Home Manager umgeschaltet werden (auto). 
     </li>     
     </ul>
   
   </ul>
   <br><br>
   
   <a name="SMAPortalGet"></a>
   <b>Get</b>
   <ul>
    <br>
    <ul>
    
      <a name="data"></a>
      <li><b> data </b> <br>  
      Mit diesem Befehl werden die Daten aus dem SMA Sunny Portal manuell abgerufen. 
    </ul>
    </li>
    <br>
    
    <ul>
      <a name="storedCredentials"></a>
      <li><b> storedCredentials </b> <br>  
      Die gespeicherten Anmeldeinformationen (Credentials) werden in einem Popup als Klartext angezeigt.
    </ul>
    </li>

   </ul>  
   <br><br>
   
   <a name="SMAPortalAttr"></a>
   <b>Attribute</b>
   <ul>
     <br>
     <ul>      

       <a name="balanceDay"></a>
       <li><b>balanceDay &lt;YYYY-MM-DD&gt; [current current-x &lt;YYYY-MM-DD&gt; &lt;YYYY-MM-DD&gt; ...] </b><br>
       Legt fest, von welchen Tagen der Datenprovider "balanceDayData" die Daten liefert.
       In der Relativangabe <b>current-x</b> ist <b>x</b> die Anzahl Tage die vom aktuellen Tag subtrahiert werden.        
       Die Tagesangaben werden durch Leerzeichen getrennt, current = aktueller Tag. <br>
       (default: aktueller Tag) <br><br>
       
        <ul>
         <b>Beispiele:</b><br>
         attr &lt;name&gt; balanceDay current 2020-08-07 2020-08-06 2020-08-05 <br> 
         attr &lt;name&gt; balanceDay current current-1 current-2              <br>         
        </ul> 
       </li><br>
       
       <a name="balanceMonth"></a>
       <li><b>balanceMonth &lt;YYYY-MM&gt; [current current-x &lt;YYYY-MM&gt; &lt;YYYY-MM&gt; ...] </b><br>
       Legt fest, von welchen Monaten der Datenprovider "balanceMonthData" die Daten liefert. 
       In der Relativangabe <b>current-x</b> ist <b>x</b> die Anzahl Monate die vom aktuellen Monat subtrahiert werden.
       Die Monatsangaben werden durch Leerzeichen getrennt, current = aktueller Monat. <br>
       (default: aktueller Monat) <br><br>
       
        <ul>
         <b>Beispiele:</b><br>
         attr &lt;name&gt; balanceMonth current 2019-07 2019-06 2019-05 <br> 
         attr &lt;name&gt; balanceMonth current current-12 current-24   <br>          
        </ul> 
       </li><br>
       
       <a name="balanceYear"></a>
       <li><b>balanceYear &lt;YYYY&gt; [current current-x &lt;YYYY&gt; &lt;YYYY&gt; &lt;YYYY&gt; ...] </b><br>
       Legt fest, von welchen Jahren der Datenprovider "balanceYearData" die Daten liefert. 
       In der Relativangabe <b>current-x</b> ist <b>x</b> die Anzahl Jahre die vom aktuellen Jahr subtrahiert werden.
       Die Jahresangaben werden durch Leerzeichen getrennt, current = aktuelles Jahr. <br>
       (default: aktuelles Jahr)  <br><br>
       
        <ul>
         <b>Beispiele:</b><br>
         attr &lt;name&gt; balanceYear current 2019 2018 2017        <br> 
         attr &lt;name&gt; balanceYear current current-1 current-2   <br>         
        </ul> 
       </li><br>
       
       <a name="cookieDelete"></a>
       <li><b>cookieDelete </b><br>
       Legt die Methode der Cookie Verwaltung (Löschung) fest. <br>
       (default: auto)
       <br>
       
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>auto</b>             </td><td>- Cookie File wird nach einem internen Verfahren verwaltet                                             </td></tr>
          <tr><td> <b>afterAttempt</b>     </td><td>- Cookie File wird nach jedem fehlerhaften Leseversuch gelöscht                                        </td></tr>
          <tr><td> <b>afterCycle</b>       </td><td>- Cookie File wird nach jedem Lesezyklus gelöscht (umfasst mehrere Versuche)                           </td></tr>
          <tr><td> <b>afterRun</b>         </td><td>- Cookie File wird nach jedem Durchlauf eines Datenabrufs gelöscht                                     </td></tr>
          <tr><td> <b>afterAttempt&Run</b> </td><td>- Cookie File wird nach jedem fehlerhaften Leseversuch <b>und</b> Durchlauf eines Datenabrufs gelöscht </td></tr>
       </table>
       </ul> 
       
       </li><br> 
       
       <a name="cookieLocation"></a>
       <li><b>cookieLocation &lt;Pfad/File&gt; </b><br>
       Angabe von Pfad und Datei zur Abspeicherung des empfangenen Cookies. <br>
       (default: ./log/&lt;name&gt;_cookie.txt)
       <br><br> 
  
        <ul>
         <b>Beispiel:</b><br>
         attr &lt;name&gt; cookieLocation ./log/cookies.txt <br>    
        </ul>        
       </li><br>
       
       <a name="disable"></a>
       <li><b>disable</b><br>
       Deaktiviert das Device. 
       </li><br>

       <a name="interval"></a>
       <li><b>interval &lt;Sekunden&gt; </b><br>
       Zeitintervall zum kontinuierlichen Datenabruf aus dem SMA Sunny Portal (Default: 300 Sekunden). <br>
       Ist interval explizit auf "0" gesetzt, erfolgt kein automatischer Datenabruf und muss mit "get &lt;name&gt; data" manuell
       erfolgen. <br><br>
       
       <ul>
         <b>Hinweis:</b> 
         Das Abfrageintervall darf nicht kleiner 180 Sekunden sein. Nach bisherigen Erfahrungen toleriert SMA ein 
         Intervall von 180 Sekunden obwohl lt. SMA AGB der automatische Datenabruf untersagt ist.
       </ul>
       </li><br>
       
       <a name="noHomeManager"></a>
       <li><b>noHomeManager</b><br>
       Muss gesetzt werden wenn kein Sunny Home Manager installiert ist. 
       </li><br>
       
       <a name="plantLogbookApprovalState"></a>
       <li><b>plantLogbookApprovalState</b><br>
       Mit diesem Attribut werden die Einträge entsprechend ihres Status gefiltert. <br>
       (default: Any)
       <br>
       
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>Any</b>          </td><td>-  alle Mitteilungen </td></tr>
          <tr><td> <b>NotApproved</b>  </td><td>-  nicht bestätigte Mitteilungen </td></tr>
       </table>
       </ul>         
       </li><br>
       
       <a name="plantLogbookTypes"></a>
       <li><b>plantLogbookTypes</b><br>
       Mit diesem Attribut werden die zu selektierenden Mitteilungstypen des Anlagenlogbuchs festgelegt. 
       Es werden maximal die aktuellsten 25 Logbucheinträge aller eingestellten Typen angezeigt. <br>
       (default: Warning,Disturbance,Error) 
       </li><br>
       
       <a name="providerLevel"></a>
       <li><b>providerLevel </b><br>
       Es wird der Umfang der zu generierenden Daten eingestellt. Anlagen- und Verbraucherstammdaten werden immer abgerufen.
       <br><br>
    
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>liveData</b>            </td><td>-  erzeugt Readings der aktuellen Erzeugungs- und Verbrauchsdaten </td></tr>
          <tr><td> <b>weatherData</b>         </td><td>-  von SMA angebotene Wetterdaten werden abgerufen </td></tr>
          <tr><td> <b>forecastData</b>        </td><td>-  Vorhersagedaten der Erzeugung / Verbrauch und Verbraucherplanungsdaten werden erzeugt (ein SMA Home Manager muss vorhanden sein) </td></tr>
          <tr><td> <b>consumerCurrentdata</b> </td><td>-  aktuelle Verbraucherdaten werden erzeugt </td></tr>
          <tr><td> <b>consumerDayData</b>     </td><td>-  Verbraucherdaten Tag werden erzeugt </td></tr>
          <tr><td> <b>consumerMonthData</b>   </td><td>-  Verbraucherdaten Monat werden erzeugt </td></tr>
          <tr><td> <b>consumerYearData</b>    </td><td>-  Verbraucherdaten Jahr werden erzeugt </td></tr>
          <tr><td> <b>plantLogbook</b>        </td><td>-  die maximal 25 aktuellsten Einträge des Anlagenlogbuchs werden abgerufen </td></tr>
          <tr><td> <b>balanceDayData</b>      </td><td>-  Statistikdaten des Tages werden abgerufen (siehe Attribut <a href="#balanceDay">balanceDay</a>) </td></tr>
          <tr><td> <b>balanceMonthData</b>    </td><td>-  Statistikdaten des Monats werden abgerufen (siehe Attribut <a href="#balanceMonth">balanceMonth</a>) </td></tr>
          <tr><td> <b>balanceYearData</b>     </td><td>-  Statistikdaten des Jahres werden abgerufen (siehe Attribut <a href="#balanceYear">balanceYear</a>) </td></tr>
          <tr><td> <b>balanceTotalData</b>    </td><td>-  Statistikdaten Gesamt werden abgerufen </td></tr>
       </table>
       </ul>     
       <br>       
       </li><br>
       
       <a name="showPassInLog"></a>
       <li><b>showPassInLog</b><br>
       Wenn gesetzt, wird das verwendete Passwort im Logfile angezeigt. <br>
       (default: 0) 
       </li><br>
       
       <a name="userAgent"></a>
       <li><b>userAgent &lt;Kennung&gt; </b><br>
       Es kann die User-Agent-Kennung zur Identifikation gegenüber dem SMA Sunny Portal angegeben werden.
       <br><br> 
  
        <ul>
         <b>Beispiel:</b><br>
         attr &lt;name&gt; userAgent Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:65.0) Gecko/20100101 Firefox/65.0 <br>    
        </ul>   
        
       </li><br> 
       
       <a name="useRelativeNames"></a>
       <li><b>useRelativeNames </b><br>
       Bei Verwendung von relativen Datumangaben <b>current-x</b> (siehe balance.*-Attribute) enthält der erstellte Readingname
       ebenfalls die relative anstatt der realen Datumangabe. <br>
       (default: reale Datumangabe)       
       </li><br>

       <a name="verbose5Data"></a>
       <li><b>verbose5Data </b><br>
       Mit dem Attributwert verbose 5 werden sehr große Datenmengen generiert. 
       Es können gezielt die interessierenden verbose 5 Ausgaben selektiert werden. <br>
       (default: none)
       </li><br>       
   
     </ul>
   </ul>
   <br> 
    
</ul>

=end html_DE

=for :application/json;q=META.json 76_SMAPortal.pm
{
  "abstract": "Module for communication with the SMA Sunny Portal",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Kommunikation mit dem SMA Sunny Portal"
    }
  },
  "keywords": [
    "sma",
    "photovoltaik",
    "electricity",
    "portal",
    "smaportal"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>",
    "Wzut",
    "XGuide",
    null
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
        "JSON": 0,
        "Encode": 0,
        "POSIX": 0,
        "Data::Dumper": 0,
        "Blocking": 0,
        "GPUtils": 0,
        "Time::HiRes": 0,
        "Time::Local": 0,
        "LWP": 0,
        "HTTP::Cookies": 0,
        "MIME::Base64": 0,
        "utf8": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
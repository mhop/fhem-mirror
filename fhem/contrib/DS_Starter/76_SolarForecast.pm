########################################################################################################################
# $Id: 76_SolarForecast.pm 21735 2020-04-20 20:53:24Z DS_Starter $
#########################################################################################################################
#       76_SolarForecast.pm
#
#       (c) 2020-2021 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
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
eval "use JSON;1;" or my $jsonabs = "JSON";               ## no critic 'eval' # Debian: apt-get install libjson-perl

use FHEM::SynoModules::SMUtils qw( evaljson  
                                   moduleVersion
                                   trim
                                 );                       # Hilfsroutinen Modul

use Data::Dumper; 
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
                                 
# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          attr
          AnalyzePerlCommand
          AttrVal
          AttrNum
          data
          defs
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          Debug
          fhemTimeLocal
          FmtDateTime
          FileWrite
          FileRead
          FileDelete
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
  "0.14.0" => "17.03.2021  new getter PVReal, weatherData, consumtion total in currentMeterdev ",
  "0.13.0" => "16.03.2021  changed sub forecastGraphic from Wzut ",
  "0.12.0" => "16.03.2021  switch etoday to etotal ",
  "0.11.0" => "14.03.2021  new attr history_hour, beam1Content, beam2Content, implement sub forecastGraphic from Wzut, ".
                           "rename attr beamColor, beamColor2 , more fixes ",
  "0.10.0" => "13.03.2021  hour shifter in sub _transferMeterValues, lot of fixes ",
  "0.9.0"  => "13.03.2021  more helper hashes Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251 ".
                           "cachefile pvhist is persistent ",
  "0.8.0"  => "07.03.2021  helper hash Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350 ",
  "0.7.0"  => "01.03.2021  add function DbLog_splitFn ",
  "0.6.0"  => "27.01.2021  change calcPVforecast from formula 1 to formula 2 ",
  "0.5.0"  => "25.01.2021  add multistring support, add reset inverterStrings ",
  "0.4.0"  => "24.01.2021  setter moduleDirection, add Area factor to calcPVforecast, add reset pvCorrection ",
  "0.3.0"  => "21.01.2021  add cloud correction, add rain correction, add reset pvHistory, setter writeHistory ",
  "0.2.0"  => "20.01.2021  use SMUtils, JSON, implement getter data,html,pvHistory, correct the 'disable' problem ",
  "0.1.0"  => "09.12.2020  initial Version "
);

# Voreinstellungen

my %hset = (                                                                # Hash der Set-Funktion
  currentForecastDev      => { fn => \&_setcurrentForecastDev     },
  modulePeakString        => { fn => \&_setmodulePeakString       },
  inverterStrings         => { fn => \&_setinverterStrings        },
  currentInverterDev      => { fn => \&_setinverterDevice         },
  currentMeterDev         => { fn => \&_setmeterDevice            },
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
  reset                   => { fn => \&_setreset                  },
  moduleTiltAngle         => { fn => \&_setmoduleTiltAngle        },
  moduleDirection         => { fn => \&_setmoduleDirection        },
  writeHistory            => { fn => \&_setwriteHistory           },
);

my %hget = (                                                                # Hash für Get-Funktion (needcred => 1: Funktion benötigt gesetzte Credentials)
  data         => { fn => \&_getdata,          needcred => 0 },
  html         => { fn => \&_gethtml,          needcred => 0 },
  ftui         => { fn => \&_getftui,          needcred => 0 },
  pvHistory    => { fn => \&_getlistPVHistory, needcred => 0 },
  pvReal       => { fn => \&_getlistPVReal,    needcred => 0 },
  weatherData  => { fn => \&_getlistWeather,   needcred => 0 },
  stringConfig => { fn => \&_getstringConfig,  needcred => 0 },
);

my %hff = (                                                                                           # Flächenfaktoren 
  "0"  => { N => 100, NE => 100, E => 100, SE => 100, S => 100, SW => 100, W => 100, NW => 100 },     # http://www.ing-büro-junge.de/html/photovoltaik.html
  "10" => { N => 90,  NE => 93,  E => 100, SE => 105, S => 107, SW => 105, W => 100, NW => 93  },
  "20" => { N => 80,  NE => 84,  E => 97,  SE => 109, S => 114, SW => 109, W => 97,  NW => 84  },
  "30" => { N => 69,  NE => 76,  E => 94,  SE => 110, S => 116, SW => 110, W => 94,  NW => 76  },
  "40" => { N => 59,  NE => 68,  E => 90,  SE => 109, S => 117, SW => 109, W => 90,  NW => 68  },
  "45" => { N => 55,  NE => 65,  E => 87,  SE => 108, S => 115, SW => 108, W => 87,  NW => 65  },
  "50" => { N => 49,  NE => 62,  E => 85,  SE => 107, S => 113, SW => 107, W => 85,  NW => 62  },
  "60" => { N => 42,  NE => 55,  E => 80,  SE => 102, S => 111, SW => 102, W => 80,  NW => 55  },
  "70" => { N => 37,  NE => 50,  E => 74,  SE => 95,  S => 104, SW => 95,  W => 74,  NW => 50  },
  "80" => { N => 35,  NE => 46,  E => 67,  SE => 86,  S => 95,  SW => 86,  W => 67,  NW => 46  },
  "90" => { N => 33,  NE => 43,  E => 62,  SE => 78,  S => 85,  SW => 78,  W => 62,  NW => 43  },
);

my %weather_ids = (
  # s =>  0 , 0 - 3   DWD -> kein signifikantes Wetter
  # s =>  1 , 45 - 99 DWD -> signifikantes Wetter
  '0'  => { s => '0', icon => 'weather_sun',              txtd => 'sonnig' },
  '1'  => { s => '0', icon => 'weather_cloudy_light',     txtd => 'Bewölkung abnehmend' },
  '2'  => { s => '0', icon => 'weather_cloudy',           txtd => 'Bewölkung unverändert' },
  '3'  => { s => '0', icon => 'weather_cloudy_heavy',     txtd => 'Bewölkung zunehmend' },
  '4'  => { s => '0', icon => 'unknown',                  txtd => 'Sicht durch Rauch oder Asche vermindert' },
  '5'  => { s => '0', icon => 'unknown',                  txtd => 'trockener Dunst (relative Feuchte < 80 %)' },
  '6'  => { s => '0', icon => 'unknown',                  txtd => 'verbreiteter Schwebstaub, nicht vom Wind herangeführt' },
  '7'  => { s => '0', icon => 'unknown',                  txtd => 'Staub oder Sand bzw. Gischt, vom Wind herangeführt' },
  '8'  => { s => '0', icon => 'unknown',                  txtd => 'gut entwickelte Staub- oder Sandwirbel' },
  '9'  => { s => '0', icon => 'unknown',                  txtd => 'Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station' },

  '10' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel' },
  '11' => { s => '0', icon => 'weather_rain_fog',         txtd => 'Nebel mit Regen'                                                       },
  '12' => { s => '0', icon => 'weather_fog',              txtd => 'durchgehender Bodennebel'                                              },
  '13' => { s => '0', icon => 'unknown',                  txtd => 'Wetterleuchten sichtbar, kein Donner gehört'                           },
  '14' => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag im Gesichtskreis, nicht den Boden erreichend'             },
  '15' => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Ferne (> 5 km), aber nicht an der Station'         },
  '16' => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Nähe (< 5 km), aber nicht an der Station'          },
  '17' => { s => '0', icon => 'unknown',                  txtd => 'Gewitter (Donner hörbar), aber kein Niederschlag an der Station'       },
  '18' => { s => '0', icon => 'unknown',                  txtd => 'Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station' },
  '19' => { s => '0', icon => 'unknown',                  txtd => 'Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis'            },

  '20' => { s => '0', icon => 'unknown',                  txtd => 'nach Sprühregen oder Schneegriesel' },
  '21' => { s => '0', icon => 'unknown',                  txtd => 'nach Regen' },
  '22' => { s => '0', icon => 'unknown',                  txtd => 'nach Schnefall' },
  '23' => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeregen oder Eiskörnern' },
  '24' => { s => '0', icon => 'unknown',                  txtd => 'nach gefrierendem Regen' },
  '25' => { s => '0', icon => 'unknown',                  txtd => 'nach Regenschauer' },
  '26' => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeschauer' },
  '27' => { s => '0', icon => 'unknown',                  txtd => 'nach Graupel- oder Hagelschauer' },
  '28' => { s => '0', icon => 'unknown',                  txtd => 'nach Nebel' },
  '29' => { s => '0', icon => 'unknown',                  txtd => 'nach Gewitter' },

  '30' => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität abnehmend' },
  '31' => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, unveränderte Intensität' },
  '32' => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität zunehmend' },
  '33' => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität abnehmend' },
  '34' => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, unveränderte Intensität' },
  '35' => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität zunehmend' },
  '36' => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneefegen, unter Augenhöhe' },
  '37' => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneefegen, unter Augenhöhe' },
  '38' => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneetreiben, über Augenhöhe' },
  '39' => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneetreiben, über Augenhöhe' },

  '40' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in einiger Entfernung' },
  '41' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in Schwaden oder Bänken' },
  '42' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dünner werdend' },
  '43' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dünner werdend' },
  '44' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, unverändert' },
  '45' => { s => '1', icon => 'weather_fog',              txtd => 'Nebel' },
  '46' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dichter werdend' },
  '47' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dichter werdend' },
  '48' => { s => '1', icon => 'weather_fog',              txtd => 'Nebel mit Reifbildung' },
  '49' => { s => '0', icon => 'weather_fog',              txtd => 'Nebel mit Reifansatz, Himmel nicht erkennbar' },

  '50' => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener leichter Sprühregen' },
  '51' => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen' },
  '52' => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Sprühregen' },
  '53' => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen' },
  '54' => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Sprühregen' },
  '55' => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Sprühregen' },
  '56' => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter gefrierender Sprühregen' },
  '57' => { s => '1', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker gefrierender Sprühregen' },
  '58' => { s => '0', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen mit Regen' },
  '59' => { s => '0', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker Sprühregen mit Regen' },

  '60' => { s => '0', icon => 'weather_rain_light',       txtd => 'unterbrochener leichter Regen oder einzelne Regentropfen'                 },
  '61' => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regen'                                                           },
  '62' => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Regen'                                             },
  '63' => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger Regen'                                                            },
  '64' => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Regen'                                             },
  '65' => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Regen'                                                            },
  '66' => { s => '1', icon => 'weather_rain_snow_light',  txtd => 'leichter gefrierender Regen'                                              },
  '67' => { s => '1', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker gefrierender Regen'                                  },
  '68' => { s => '0', icon => 'weather_rain_snow_light',  txtd => 'leichter Schneeregen'                                                     },
  '69' => { s => '0', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker Schneeregen'                                         },

  '70' => { s => '0', icon => 'weather_snow_light',       txtd => 'unterbrochener leichter Schneefall oder einzelne Schneeflocken'           },
  '71' => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneefall'                                                      },
  '72' => { s => '0', icon => 'weather_snow',             txtd => 'unterbrochener mäßiger Schneefall'                                        },
  '73' => { s => '1', icon => 'weather_snow',             txtd => 'mäßiger Schneefall'                                                       },
  '74' => { s => '0', icon => 'weather_snow_heavy',       txtd => 'unterbrochener starker Schneefall'                                        },
  '75' => { s => '1', icon => 'weather_snow_heavy',       txtd => 'starker Schneefall'                                                       },
  '76' => { s => '0', icon => 'weather_frost',            txtd => 'Eisnadeln (Polarschnee)'                                                  },
  '77' => { s => '1', icon => 'weather_frost',            txtd => 'Schneegriesel'                                                            },
  '78' => { s => '0', icon => 'weather_frost',            txtd => 'Schneekristalle'                                                          },
  '79' => { s => '0', icon => 'weather_frost',            txtd => 'Eiskörner (gefrorene Regentropfen)'                                       },

  '80' => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regenschauer'                                                    },
  '81' => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger oder starkerRegenschauer'                                         },
  '82' => { s => '1', icon => 'weather_rain_heavy',       txtd => 'sehr starker Regenschauer'                                                },
  '83' => { s => '0', icon => 'weather_snow',             txtd => 'mäßiger oder starker Schneeregenschauer'                                  },
  '84' => { s => '0', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer'                                                   },
  '85' => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer'                                                   },
  '86' => { s => '1', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Schneeschauer'                                       },
  '87' => { s => '0', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Graupelschauer'                                      },
  '88' => { s => '0', icon => 'unknown',                  txtd => 'leichter Hagelschauer'                                                    },
  '89' => { s => '0', icon => 'unknown',                  txtd => 'mäßiger oder starker Hagelschauer'                                        },

  '90' => { s => '0', icon => 'weather_thunderstorm',     txtd => ''                                                                         },
  '91' => { s => '0', icon => 'weather_storm',            txtd => ''                                                                         },
  '92' => { s => '0', icon => 'weather_thunderstorm',     txtd => ''                                                                         },
  '93' => { s => '0', icon => 'weather_thunderstorm',     txtd => ''                                                                         },
  '94' => { s => '0', icon => 'weather_thunderstorm',     txtd => ''                                                                         },
  '95' => { s => '1', icon => 'weather_thunderstorm',     txtd => 'leichtes oder mäßiges Gewitter ohne Graupel oder Hagel'                   },
  '96' => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter ohne Graupel oder Hagel,Gewitter mit Graupel oder Hagel' },
  '97' => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Regen oder Schnee'                                   },
  '98' => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Sandsturm'                                           },
  '99' => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Graupel oder Hagel'                                  },
);

my @chours      = (5..21);                                                       # Stunden des Tages mit möglichen Korrekturwerten                              
my $defpvme     = 16.52;                                                         # default Wirkungsgrad Solarmodule
my $definve     = 98.3;                                                          # default Wirkungsgrad Wechselrichter
my $kJtokWh     = 0.00027778;                                                    # Umrechnungsfaktor kJ in kWh
my $defmaxvar   = 0.5;                                                           # max. Varianz pro Tagesberechnung Autokorrekturfaktor
my $definterval = 70;                                                            # Standard Abfrageintervall

my $pvhcache    = $attr{global}{modpath}."/FHEM/FhemUtils/PVH_SolarForecast_";   # Filename-Fragment für PV History (wird mit Devicename ergänzt)
my $pvrcache    = $attr{global}{modpath}."/FHEM/FhemUtils/PVR_SolarForecast_";   # Filename-Fragment für PV Real (wird mit Devicename ergänzt)

my $calcmaxd    = 7;                                                             # Anzahl Tage (default) für Durchschnittermittlung zur Vorhersagekorrektur
my @dwdattrmust = qw(Rad1h TTT Neff R101 ww SunUp SunRise SunSet);               # Werte die im Attr forecastProperties des DWD_Opendata Devices mindestens gesetzt sein müssen
my $whistrepeat = 900;                                                           # Wiederholungsintervall Schreiben historische Daten

my $cloudslope  = 0.55;                                                          # Steilheit des Korrekturfaktors bzgl. effektiver Bewölkung, siehe: https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/sonnenstunden
my $cloud_base  = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung 

my $rainslope   = 0.30;                                                          # Steilheit des Korrekturfaktors bzgl. Niederschlag (R101)
my $rain_base   = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung 

my @consdays    = qw(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30); # Auswahl Anzahl Tage für Attr numHistDays  

# Information zu verwendeten internen Datenhashes
# $data{$type}{$name}{pvfc}                                                      # PV forecast Ringspeicher
# $data{$type}{$name}{weather}                                                   # Weather forecast Ringspeicher
# $data{$type}{$name}{pvreal}                                                    # PV real
# $data{$type}{$name}{current}                                                   # current values
# $data{$type}{$name}{pvhist}                                                    # historische Werte pvreal, pvforecast, gridconsumtion                  



################################################################
#               Init Fn
################################################################
sub Initialize {
  my ($hash) = @_;

  my $fwd = join ",", devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized"); 
  my $cda = join ",", @consdays;
  
  $hash->{DefFn}              = \&Define;
  $hash->{UndefFn}            = \&Undef;
  $hash->{GetFn}              = \&Get;
  $hash->{SetFn}              = \&Set;
  $hash->{DeleteFn}           = \&Delete;
  $hash->{FW_summaryFn}       = \&FwFn;
  $hash->{FW_detailFn}        = \&FwFn;
  $hash->{ShutdownFn}         = \&Shutdown;
  $hash->{DbLog_splitFn}      = \&DbLogSplit;
  $hash->{AttrFn}             = \&Attr;
  $hash->{NotifyFn}           = \&Notify;
  $hash->{AttrList}           = "autoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "autoRefreshFW:$fwd ".
                                "beam1Color:colorpicker,RGB ".
                                "beam1Content:forecast,real,consumption ".
                                "beam2Color:colorpicker,RGB ".
                                "beam2Content:forecast,real,consumption ".
                                "beamHeight ".
                                "beamWidth ".
                                # "consumerList ".
                                # "consumerLegend:none,icon_top,icon_bottom,text_top,text_bottom ".
                                # "consumerAdviceIcon ".
                                "disable:1,0 ".
                                "forcePageRefresh:1,0 ".
                                "headerAlignment:center,left,right ".                                       
                                "headerDetail:all,co,pv,pvco,statusLink ".
                                "history_hour:slider,-12,-1,0 ".
                                "hourCount:slider,4,1,24 ".
                                "hourStyle ".
                                "htmlStart ".
                                "htmlEnd ".
                                "interval ".
                                "layoutType:pv,co,pvco,diff ".
                                "maxVariancePerDay ".
                                "maxPV ".
                                "numHistDays:$cda ".
                                "showDiff:no,top,bottom ".
                                "showHeader:1,0 ".
                                "showLink:1,0 ".
                                "showNight:1,0 ".
                                "showWeather:1,0 ".
                                "spaceSize ".                                
                                "Wh/kWh:Wh,kWh ".
                                "weatherColor:colorpicker,RGB ".
                                "weatherColor_night:colorpicker,RGB ".                                
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
  
  return "Error: Perl module ".$jsonabs." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($jsonabs);

  my $name                       = $hash->{NAME};
  my $type                       = $hash->{TYPE};
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden
  
  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                        # Versionsinformationen setzen

  createNotifyDev ($hash);
  
  my $file              = $pvhcache.$name;                                         # Cache File PV History lesen wenn vorhanden
  my $cachename         = "pvhist";
  $params->{file}       = $file;
  $params->{cachename}  = $cachename;
  _readCacheFile ($params);                                                       
  
  $file                 = $pvrcache.$name;                                         # Cache File PV Real lesen wenn vorhanden
  $cachename            = "pvreal";
  $params->{file}       = $file;
  $params->{cachename}  = $cachename;
  _readCacheFile ($params);                                                       
    
  readingsSingleUpdate($hash, "state", "initialized", 1); 

  centralTask   ($hash);                                                                                 # Einstieg in Abfrage 
  InternalTimer (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0); # Einstieg periodisches Schreiben historische Daten
  
return;
}

################################################################
#                   Cachefile lesen
################################################################
sub _readCacheFile {               
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $file      = $paref->{file};
  my $cachename = $paref->{cachename};
  
  my $name      = $hash->{NAME};

  my ($error, @content) = FileRead ($file);                                        
  
  if(!$error) {
      my $json    = join "", @content;
      my $success = evaljson ($hash, $json);                               
      
      if($success) {
           $data{$hash->{TYPE}}{$name}{$cachename} = decode_json ($json);
      }
      else {
          Log3($name, 2, qq{$name - WARNING - The content of file "$file" is not readable and may be corrupt});
      }
  }
      
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
  
  my ($setlist,@fcdevs,@cfs);
  my ($fcd,$ind,$med,$cf) = ("","","","");
    
  return if(IsDisabled($name));
 
  @fcdevs = devspec2array("TYPE=DWD_OpenData");
  $fcd    = join ",", @fcdevs if(@fcdevs);

  for my $h (@chours) {
      push @cfs, "pvCorrectionFactor_".sprintf("%02d",$h); 
  }
  $cf = join " ", @cfs if(@cfs);

  $setlist = "Unknown argument $opt, choose one of ".
             "currentForecastDev:$fcd ".
             "currentInverterDev:textField-long ".
             "currentMeterDev:textField-long ".
             "inverterStrings ".
             "modulePeakString ".
             "moduleTiltAngle ".
             "moduleDirection ".
             "pvCorrectionFactor_Auto:on,off ".
             "reset:currentForecastDev,currentInverterDev,currentMeterDev,inverterStrings,pvCorrection,pvHistory ".
             "writeHistory:noArg ".
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
#                      Setter currentForecastDev
################################################################
sub _setcurrentForecastDev {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no PV forecast device specified};

  if(!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData") {
      return qq{Forecast device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};                      #' :)
  }

  readingsSingleUpdate($hash, "currentForecastDev", $prop, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter currentInverterDev
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
  
  if(!$h->{pv} || !$h->{etotal}) {
      return qq{The syntax of "$opt" isn't right. Please consider the commandref.};
  }  

  delete $hash->{HELPER}{INITETOTAL};
  readingsSingleUpdate($hash, "currentInverterDev", $arg, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter inverterStrings
################################################################
sub _setinverterStrings {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no inverter strings specified};

  readingsSingleUpdate($hash, "inverterStrings", $prop, 1);
  
return qq{REMINDER - After setting or changing "inverterStrings" please check / set all module parameter (e.g. moduleTiltAngle) again !};
}

################################################################
#                      Setter currentMeterDev
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
  
  if(!$h->{gcon} || !$h->{contotal}) {
      return qq{The syntax of "$opt" isn't right. Please consider the commandref.};
  }  

  readingsSingleUpdate($hash, "currentMeterDev", $arg, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter modulePeakString
################################################################
sub _setmodulePeakString {               ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no PV module peak specified};
  
  $arg =~ s/,/./xg;
  
  my ($a,$h) = parseParams ($arg); 
  
  if(!keys %$h) {
      return qq{The provided PV module peak has wrong format};
  }
  
  while (my ($key, $value) = each %$h) {
      if($value !~ /[0-9.]/x) {
          return qq{The module peak of "$key" must be specified by numbers and optionally with decimal places};
      }     
  }
  
  readingsSingleUpdate($hash, "modulePeakString", $arg, 1);
  
  my $ret = createStringConfig ($hash);
  return $ret if($ret);

return;
}

################################################################
#                      Setter moduleTiltAngle
################################################################
sub _setmoduleTiltAngle {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no tilt angle was provided};
  
  my $tilt  = join "|", sort keys %hff;

  my ($a,$h) = parseParams ($arg); 
  
  if(!keys %$h) {
      return qq{The provided tilt angle has wrong format};
  }

  while (my ($key, $value) = each %$h) {
      if($value !~ /^($tilt)$/x) {
          return qq{The tilt angle of "$key" is wrong};
      }     
  }
    
  readingsSingleUpdate($hash, "moduleTiltAngle", $arg, 1);
    
  my $ret = createStringConfig ($hash);
  return $ret if($ret);  

return;
}

################################################################
#                 Setter moduleDirection
################################################################
sub _setmoduleDirection {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no module direction was provided};

  my $dirs  = "N|NE|E|SE|S|SW|W|NW";                                          # mögliche Richtungsangaben
  
  my ($a,$h) = parseParams ($arg); 
  
  if(!keys %$h) {
      return qq{The provided module direction has wrong format};
  }
  
  while (my ($key, $value) = each %$h) {
      if($value !~ /^($dirs)$/x) {
          return qq{The module direction of "$key" is wrong: $value};
      }     
  }

  readingsSingleUpdate($hash, "moduleDirection", $arg, 1);
  
  my $ret = createStringConfig ($hash);
  return $ret if($ret);

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
  
  readingsSingleUpdate($hash, $opt, $prop." (manual)", 1);
  
  my @da;
  my $t      = time;                                                                                # aktuelle Unix-Zeit 
  my $chour  = strftime "%H", localtime($t);                                                        # aktuelle Stunde
  my $fcdev  = ReadingsVal($name, "currentForecastDev", "");                                        # aktuelles Forecast Device
  
  my $params = {
      hash  => $hash,
      name  => $name,
      t       => $t,
      chour   => $chour,
      daref   => \@da
  };
  
  _transferDWDForecastValues ($params);
  
  if(@da) {
      push @da, "state:updated";                                                                   # Abschluß state 
      createReadingsFromArray ($hash, \@da, 1);
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
  
  if($prop eq "off") {
      deleteReadingspec ($hash, "pvCorrectionFactor_.*_autocalc");
  }

return;
}

################################################################
#                      Setter reset
################################################################
sub _setreset {                          ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no source specified for reset};
  
  if($prop eq "pvHistory") {
      my $type = $hash->{TYPE};
      delete $data{$type}{$name}{pvhist};
      delete $hash->{HELPER}{INITETOTAL};
      return;
  }
  
  if($prop eq "pvCorrection") {
      deleteReadingspec   ($hash, "pvCorrectionFactor_.*");
      return;
  }

  readingsDelete($hash, $prop);
  
  if($prop eq "currentMeterDev") {
      readingsDelete($hash, "Current_GridConsumption");
  }
  
  if($prop eq "currentInverterDev") {
      readingsDelete    ($hash, "Current_PV");
      deleteReadingspec ($hash, ".*_PVreal" );
      delete $hash->{HELPER}{INITETOTAL};
  }
  
  createNotifyDev ($hash);

return;
}

################################################################
#                      Setter writeHistory
################################################################
sub _setwriteHistory {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  my $ret = writeCacheToFile ($hash, "pvhist", $pvhcache.$name);     # Cache File für PV History schreiben
  
  writeCacheToFile ($hash, "pvreal", $pvrcache.$name);               # Cache File für PV Real schreiben

return $ret;
}

###############################################################
#                  SolarForecast Get
###############################################################
sub Get {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name = shift @a;
  my $opt  = shift @a;
  my $arg  = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
 
  my $getlist = "Unknown argument $opt, choose one of ".
                "data:noArg ".
                "html:noArg ".
                "pvHistory:noArg ".
                "pvReal:noArg ".
                "stringConfig:noArg ".
                "weatherData:noArg "
                ;
                
  return if(IsDisabled($name));
  
  my $params = {
      hash  => $hash,
      name  => $name,
      opt   => $opt,
      arg   => $arg
  };
  
  if($hget{$opt} && defined &{$hget{$opt}{fn}}) {
      my $ret = q{}; 
      if (!$hash->{CREDENTIALS} && $hget{$opt}{needcred}) {                
          return qq{Credentials of $name are not set."};
      }
      $ret = &{$hget{$opt}{fn}} ($params);
      return $ret;
  }
  
return $getlist;
}

###############################################################
#                       Getter data
###############################################################
sub _getdata {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
return centralTask ($hash);
}

###############################################################
#                       Getter html
###############################################################
sub _gethtml {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
return pageAsHtml ($hash);
}

###############################################################
#                       Getter ftui
#                ohne Eintrag in Get-Liste
###############################################################
sub _getftui {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
return pageAsHtml ($hash,"ftui");
}

###############################################################
#                       Getter listPVHistory
###############################################################
sub _getlistPVHistory {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};
  
  my $ret   = listDataPool ($hash, "pvhist");
                    
return $ret;
}

###############################################################
#                       Getter listPVReal
###############################################################
sub _getlistPVReal {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};
  
  my $ret   = listDataPool ($hash, "pvreal");
                    
return $ret;
}

###############################################################
#                       Getter listWeather
###############################################################
sub _getlistWeather {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};
  
  my $ret   = listDataPool ($hash, "weather");
                    
return $ret;
}

###############################################################
#                       Getter stringConfig
###############################################################
sub _getstringConfig {
  my $paref = shift;
  my $hash  = $paref->{hash};
 
  my $ret = checkStringConfig ($hash);
                    
return $ret;
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
        $do  = 0 if($cmd eq "del");
        $val = ($do == 1 ? "disabled" : "initialized");
        readingsSingleUpdate($hash, "state", $val, 1);
    }
    
    if($aName eq "icon") {
        $_[2] = "consumerAdviceIcon";
    }
    
    if ($cmd eq "set") {
        if ($aName eq "interval") {
            unless ($aVal =~ /^[0-9]+$/x) {return "The value for $aName is not valid. Use only figures 0-9 !";}
            InternalTimer(gettimeofday()+1.0, "FHEM::SolarForecast::centralTask", $hash, 0);
        }  
        
        if ($aName eq "maxVariancePerDay") {
            unless ($aVal =~ /^[0-9.]+$/x) {return "The value for $aName is not valid. Use only numbers with optional decimal places !";}
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
  my $myName   = $myHash->{NAME};                                                         # Name des eigenen Devices
  my $devName  = $dev_hash->{NAME};                                                       # Device welches Events erzeugt hat
 
  return if(IsDisabled($myName) || !$myHash->{NOTIFYDEV}); 
  
  my $events = deviceEvents($dev_hash, 1);  
  return if(!$events);
 
return;
}

###############################################################
#                  DbLog_splitFn
###############################################################
sub DbLogSplit {
  my $event  = shift;
  my $device = shift;
  my ($reading, $value, $unit) = ("","","");

  if($event =~ /\sk?Wh?$/xs) {
      my @parts = split(/\s/x, $event, 3);
      $reading  = $parts[0];
      $reading  =~ tr/://d;
      $value    = $parts[1];
      $unit     = $parts[2];
      
      # Log3 ($device, 1, qq{$device - Split for DbLog done -> Reading: $reading, Value: $value, Unit: $unit});
  }

return ($reading, $value, $unit);
}

################################################################
#                         Shutdown
################################################################
sub Shutdown {  
  my $hash = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  writeCacheToFile ($hash, "pvhist", $pvhcache.$name);               # Cache File für PV History schreiben
  writeCacheToFile ($hash, "pvreal", $pvrcache.$name);               # Cache File für PV Real schreiben
  
return; 
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete 
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg, 
# der ebenfalls alle Geräte löscht und danach das 
# Konfigurationsfile neu einliest. Entsprechend müssen in der 
# Funktion typische Aufräumarbeiten durchgeführt werden wie das 
# saubere Schließen von Verbindungen oder das Entfernen von 
# internen Timern.
################################################################
sub Undef {
 my $hash = shift;
 my $arg  = shift;
 
 RemoveInternalTimer($hash);
    
return;
}

#################################################################
# Wenn ein Gerät in FHEM gelöscht wird, wird zuerst die Funktion 
# X_Undef aufgerufen um offene Verbindungen zu schließen, 
# anschließend wird die Funktion X_Delete aufgerufen. 
# Funktion: Aufräumen von dauerhaften Daten, welche durch das 
# Modul evtl. für dieses Gerät spezifisch erstellt worden sind. 
# Es geht hier also eher darum, alle Spuren sowohl im laufenden 
# FHEM-Prozess, als auch dauerhafte Daten bspw. im physikalischen 
# Gerät zu löschen die mit dieser Gerätedefinition zu tun haben. 
#################################################################
sub Delete {
  my $hash  = shift;
  my $arg   = shift;
  my $name  = $hash->{NAME};
  
  my $file  = $pvhcache.$name;                                      # Cache File PV History löschen
  my $error = FileDelete($file);      

  if ($error) {
      Log3 ($name, 2, qq{$name - ERROR deleting cache file "$file": $error}); 
  }  
  
  $error = qq{};
  $file  = $pvrcache.$name;                                         # Cache File PV Real löschen
  $error = FileDelete($file); 
  
  if ($error) {
      Log3 ($name, 2, qq{$name - ERROR deleting cache file "$file": $error}); 
  }
      
return;
}

################################################################
#                       Zentraler Datenabruf
################################################################
sub centralTask {
  my $hash = shift;
  my $name = $hash->{NAME};                                         # Name des eigenen Devices 
  my $type = $hash->{TYPE};  
  
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

      my $stch = $data{$type}{$name}{strings};                                                     # String Config Hash
      if (!keys %{$stch}) {
          my $ret = createStringConfig ($hash);                                                    # die String Konfiguration erstellen
          if ($ret) {
              readingsSingleUpdate($hash, "state", $ret, 1);
              return;
          }
      }      
      
      my @da;
      my $t     = time;                                                                            # aktuelle Unix-Zeit 
      my $chour = strftime "%H", localtime($t);                                                    # aktuelle Stunde
      my $day   = strftime "%d", localtime($t);                                                    # aktueller Tag
            
      my $params = {
          hash  => $hash,
          name  => $name,
          t     => $t,
          chour => $chour,
          day   => $day,
          daref => \@da
      };
      
      Log3 ($name, 5, "$name - ################################################################");
      Log3 ($name, 5, "$name - ###                New data collection cycle                 ###");
      Log3 ($name, 5, "$name - ################################################################");
      Log3 ($name, 5, "$name - current hour: $chour");
      
      _transferDWDForecastValues ($params);                                                        # Forecast Werte übertragen 
      _transferWeatherValues     ($params);                                                        # Wetterwerte übertragen 
      _transferInverterValues    ($params);                                                        # WR Werte übertragen
      _transferMeterValues       ($params);

      #Log3($name, 1, "$name - PV forecast Hash: ".      Dumper $data{$hash->{TYPE}}{$name}{pvfc});
      #Log3($name, 1, "$name - Weather forecast Hash: ". Dumper $data{$hash->{TYPE}}{$name}{weather});
      #Log3($name, 1, "$name - PV real Hash: ".          Dumper $data{$hash->{TYPE}}{$name}{pvreal});
      #Log3($name, 1, "$name - current values Hash: ".   Dumper $data{$hash->{TYPE}}{$name}{current});
      
      if(@da) {
          createReadingsFromArray ($hash, \@da, 1);
      }
      
      collectSummaries ($hash, $chour, \@da);                                                      # Zusammenfassung nächste 4 Stunden u.a. erstellen
      calcVariance     ($params);                                                                  # Autokorrektur berechnen
      
      readingsSingleUpdate($hash, "state", "updated", 1);                                          # Abschluß state 
  }
  else {
      InternalTimer(gettimeofday()+5, "FHEM::SolarForecast::centralTask", $hash, 0);
  }
  
return;
}

################################################################
#       Erstellen der Stringkonfiguration
#       Stringhash: $data{$type}{$name}{strings}
################################################################
sub createStringConfig {                 ## no critic "not used"
  my $hash = shift;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  delete $data{$type}{$name}{strings};                                                            # Stringhash zurücksetzen
  
  my @istrings = split ",", ReadingsVal ($name, "inverterStrings", "");                           # Stringbezeichner
  
  if(!@istrings) {
      return qq{Define all used strings with command "set $name inverterStrings" first.};
  }
  
  my $tilt     = ReadingsVal ($name, "moduleTiltAngle", "");                                      # Modul Neigungswinkel für jeden Stringbezeichner
  my ($at,$ht) = parseParams ($tilt);
 
  while (my ($key, $value) = each %$ht) {
      if ($key ~~ @istrings) {
          $data{$type}{$name}{strings}{"$key"}{tilt} = $value;
      }
      else {
          return qq{Check "moduleTiltAngle" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
      }
  }
  
  my $peak     = ReadingsVal ($name, "modulePeakString", "");                                    # kWp für jeden Stringbezeichner
  my ($aa,$ha) = parseParams ($peak);
 
  while (my ($key, $value) = each %$ha) {
      if ($key ~~ @istrings) {
          $data{$type}{$name}{strings}{"$key"}{peak} = $value;
      }
      else {
          return qq{Check "modulePeakString" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
      }
  }
  
  my $dir      = ReadingsVal ($name, "moduleDirection", "");                                    # Modul Ausrichtung für jeden Stringbezeichner
  my ($ad,$hd) = parseParams ($dir);
 
  while (my ($key, $value) = each %$hd) {
      if ($key ~~ @istrings) {
          $data{$type}{$name}{strings}{"$key"}{dir} = $value;
      }
      else {
          return qq{Check "moduleDirection" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
      }
  }  
  
  if(!keys %{$data{$type}{$name}{strings}}) {
      return qq{The string configuration is empty.\nPlease check the settings of inverterStrings, modulePeakString, moduleDirection, moduleTiltAngle};
  }
  
  my @sca = keys %{$data{$type}{$name}{strings}};                                                # Gegencheck ob nicht mehr Strings in inverterStrings enthalten sind als eigentlich verwendet
  my @tom;
  for my $sn (@istrings) {
      next if ($sn ~~ @sca);
      push @tom, $sn;      
  }
  if(@tom) {
      return qq{Some Strings are not used. Please delete this string names from "inverterStrings" :}.join ",",@tom;
  }
  
  # Log3 ($name, 2, "$name - string config: ".Dumper $data{$type}{$name}{strings});
   
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
#        Timer für historische Daten schreiben
################################################################
sub periodicWriteCachefiles {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "FHEM::SolarForecast::periodicWriteCachefiles");
  InternalTimer      (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0);
  
  return if(IsDisabled($name));
  
  writeCacheToFile ($hash, "pvhist", $pvhcache.$name);               # Cache File für PV History schreiben
  writeCacheToFile ($hash, "pvreal", $pvrcache.$name);               # Cache File für PV Real schreiben
  
return;
}

################################################################
#       historische Daten in File wegschreiben
################################################################
sub writeCacheToFile {  
  my $hash      = shift;
  my $cachename = shift;
  my $file      = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  return if(!$data{$type}{$name}{$cachename});
  
  my @pvh;
  
  my $json  = encode_json ($data{$type}{$name}{$cachename});
  push @pvh, $json;
  
  my $error = FileWrite($file, @pvh);
  
  if ($error) {
      my $err = qq{ERROR writing cache file "$file": $error};
      Log3 ($name, 2, "$name - $err");
      return $err;          
  }
  else {
      my $lw = gettimeofday(); 
      $hash->{HISTFILE} = "last write time: ".FmtTime($lw)." File: $file" if($cachename eq "pvhist");
  }
   
return; 
}

################################################################
#    Forecast Werte Device (DWD_OpenData) ermitteln und 
#    übertragen
################################################################
sub _transferDWDForecastValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  
  my $fcname = ReadingsVal($name, "currentForecastDev", "");                                    # aktuelles Forecast Device
  return if(!$fcname || !$defs{$fcname});
  
  my ($time_str,$epoche);
  
  my @aneeded = checkdwdattr ($fcname);
  if (@aneeded) {
      Log3($name, 2, qq{$name - ERROR - the attribute "forecastProperties" of device "$fcname" must contain: }.join ",",@aneeded);
  }
  
  # deleteReadingspec ($hash, "NextHour.*");
  
  for my $num (0..47) {      
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);
      last if($fd > 1);

      my $v = ReadingsVal($fcname, "fc${fd}_${fh}_Rad1h", 0);
      
      Log3($name, 5, "$name - collect DWD forecast data: device=$fcname, rad=fc${fd}_${fh}_Rad1h, Val=$v");
      
      if($num == 0) {          
          $time_str = "ThisHour";
          $epoche   = $t;                                                                     # Epoche Zeit
      }
      else {
          $time_str = "NextHour".sprintf "%02d", $num;
          $epoche   = $t + (3600*$num);
      }
      
      my $calcpv = calcPVforecast ($name, $v, $fh);                                           # Vorhersage gewichtet kalkulieren
      $data{$hash->{TYPE}}{$name}{pvfc}{sprintf("%02d",$fh)} = $calcpv;                       # Hilfshash Wert PV forecast Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350          
      
      push @$daref, "${time_str}_PVforecast:".$calcpv." Wh";
      push @$daref, "${time_str}_Time:"      .TimeAdjust ($epoche);                           # Zeit fortschreiben 
      
      $hash->{HELPER}{"fc${fd}_".sprintf("%02d",$fh)."_Rad1h"} = $v." kJ/m2";                 # nur Info: original Vorhersage Strahlungsdaten zur Berechnung Auto-Korrekturfaktor in Helper speichern           
      
      if($fd == 0 && int $calcpv > 0) {                                                       # Vorhersagedaten des aktuellen Tages zum manuellen Vergleich in Reading speichern
          push @$daref, "Today_Hour".sprintf("%02d",$fh)."_PVforecast:$calcpv Wh";         
      }
      
      if($fd == 0) {
          $paref->{calcpv}   = $calcpv;
          $paref->{histname} = "pvfc";
          $paref->{nhour}    = sprintf("%02d",$fh);
          setPVhistory ($paref); 
          delete $paref->{histname};
      }
  }
      
return;
}

################################################################
#    Wetter Werte aus dem angebenen Wetterdevice extrahieren
################################################################
sub _transferWeatherValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  
  my $fcname = ReadingsVal($name, "currentForecastDev", "");                                    # aktuelles Forecast Device
  return if(!$fcname || !$defs{$fcname});
  
  my ($time_str,$epoche);
  
  my $fc0_SunRise = ReadingsVal($fcname, "fc0_SunRise", "00:00");                               # Sonnenaufgang heute    
  my $fc0_SunSet  = ReadingsVal($fcname, "fc0_SunSet",  "00:00");                               # Sonnenuntergang heute  
  my $fc1_SunRise = ReadingsVal($fcname, "fc1_SunRise", "00:00");                               # Sonnenaufgang morgen   
  my $fc1_SunSet  = ReadingsVal($fcname, "fc1_SunSet",  "00:00");                               # Sonnenuntergang morgen 
  
  push @$daref, "Today_SunRise:".   $fc0_SunRise;
  push @$daref, "Today_SunSet:".    $fc0_SunSet;
  push @$daref, "Tomorrow_SunRise:".$fc1_SunRise;
  push @$daref, "Tomorrow_SunSet:". $fc1_SunSet;
  
  my $fc0_SunRise_round = sprintf "%02d", (split ":", $fc0_SunRise)[0];
  my $fc0_SunSet_round  = sprintf "%02d", (split ":", $fc0_SunSet)[0];
  my $fc1_SunRise_round = sprintf "%02d", (split ":", $fc1_SunRise)[0];
  my $fc1_SunSet_round  = sprintf "%02d", (split ":", $fc1_SunSet)[0];
  
  for my $num (0..47) {                      
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);
      last if($fd > 1);
      
      if($num == 0) {          
          $time_str = "ThisHour";
          $epoche   = $t;                                                                     # Epoche Zeit
      }
      else {
          $time_str = "NextHour".sprintf "%02d", $num;
          $epoche   = $t + (3600*$num);
      }

      my $wid   = ReadingsNum($fcname, "fc${fd}_${fh}_ww",  -1);
      my $neff  = ReadingsNum($fcname, "fc${fd}_${fh}_Neff", 0);                              # Effektive Wolkendecke
      my $r101  = ReadingsNum($fcname, "fc${fd}_${fh}_R101", 0);                              # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
      
      my $fhstr = sprintf "%02d", $fh;
      
      if($fd == 0 && ($fhstr lt $fc0_SunRise_round || $fhstr gt $fc0_SunSet_round)) {         # Zeit vor Sonnenaufgang oder nach Sonnenuntergang heute
          $wid += 100;                                                                        # "1" der WeatherID voranstellen wenn Nacht
      }
      elsif ($fd == 1 && ($fhstr lt $fc1_SunRise_round || $fhstr gt $fc1_SunSet_round)) {     # Zeit vor Sonnenaufgang oder nach Sonnenuntergang morgen
          $wid += 100;                                                                        # "1" der WeatherID voranstellen wenn Nacht
      }
      
      my $txt = ReadingsVal($fcname, "fc${fd}_${fh}_wwd", '');

      Log3($name, 5, "$name - collect Weather data: device=$fcname, wid=fc${fd}_${fh}_ww, val=$wid, txt=$txt, cc=$neff, rp=$r101");
      
      $hash->{HELPER}{"${time_str}_WeatherId"}  = $wid;
      $hash->{HELPER}{"${time_str}_WeatherTxt"} = $txt;
      $hash->{HELPER}{"${time_str}_CloudCover"} = $neff;
      $hash->{HELPER}{"${time_str}_RainProb"}   = $r101;
      
      $data{$hash->{TYPE}}{$name}{weather}{sprintf("%02d",$fh)}{id}         = $wid;           # Hilfshash Wert Weather Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251
      $data{$hash->{TYPE}}{$name}{weather}{sprintf("%02d",$fh)}{txt}        = $txt;   
      $data{$hash->{TYPE}}{$name}{weather}{sprintf("%02d",$fh)}{cloudcover} = $neff;
      $data{$hash->{TYPE}}{$name}{weather}{sprintf("%02d",$fh)}{rainprob}   = $r101;
  }
      
return;
}

################################################################
#    Werte Inverter Device ermitteln und übertragen
################################################################
sub _transferInverterValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                    # aktuelle Unix-Zeit
  my $chour = $paref->{chour};
  my $day   = $paref->{day};
  my $daref = $paref->{daref};  

  my $indev  = ReadingsVal($name, "currentInverterDev", "");
  my ($a,$h) = parseParams ($indev);
  $indev     = $a->[0] // "";
  return if(!$indev || !$defs{$indev});
  
  my $tlim = "23";                                                                            # Stunde 23 -> bestimmte Aktionen                  
  my $type = $hash->{TYPE}; 
  
  if($chour =~ /^($tlim)$/x) {
      deleteReadingspec ($hash, "Today_Hour.*_PV.*");
      delete $hash->{HELPER}{INITETOTAL};
  }
  
  my ($pvread,$pvunit) = split ":", $h->{pv};                                                 # Readingname/Unit für aktuelle PV Erzeugung
  my ($edread,$etunit) = split ":", $h->{etotal};                                             # Readingname/Unit für Energie total
  
  return if(!$pvread || !$edread);
  
  Log3($name, 5, "$name - collect Inverter data: device=$indev, pv=$pvread ($pvunit), etotal=$edread ($etunit)");
  
  my $pvuf   = $pvunit =~ /^kW$/xi ? 1000 : 1;
  my $pv     = ReadingsNum ($indev, $pvread, 0) * $pvuf;                                      # aktuelle Erzeugung (W)  
      
  push @$daref, "Current_PV:". $pv." W";                                          
  $data{$type}{$name}{current}{generation} = $pv;                                             # Hilfshash Wert current generation Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251
  
  my $etuf   = $etunit =~ /^kWh$/xi ? 1000 : 1;
  my $etotal = ReadingsNum ($indev, $edread, 0) * $etuf;                                      # Erzeugung total (Wh) 
  
  my $edaypast = 0;
  
  for my $hour (0..int $chour) {                                                              # alle bisherigen Erzeugungen des Tages summieren                                            
      $edaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_PVreal", 0);
  }
  
  my $do = 0;
  if ($edaypast == 0) {                                                                       # Management der Stundenberechnung auf Basis Totalwerte
      if (defined $hash->{HELPER}{INITETOTAL}) {
          $do = 1;
      }
      else {
          $hash->{HELPER}{INITETOTAL} = $etotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITETOTAL}) {
      $hash->{HELPER}{INITETOTAL} = $etotal-$edaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_PVreal", 0);
  }
  else {
      $do = 1;
  }
  
  if ($do) {
      my $ethishour = int ($etotal - ($edaypast + $hash->{HELPER}{INITETOTAL}));
      
      # Log3($name, 1, "$name - etotal: $etotal, edaypast: $edaypast, HELPER: $hash->{HELPER}{INITETOTAL}, ethishour: $ethishour  ");
      
      if($ethishour < 0) {
          $ethishour = 0;
      }
      
      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_PVreal:".$ethishour." Wh";
      $data{$type}{$name}{pvreal}{sprintf("%02d",$nhour)} = $ethishour;                     # Hilfshash Wert PV real Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
      
      $paref->{ethishour} = $ethishour;
      $paref->{nhour}     = sprintf("%02d",$nhour);
      $paref->{histname}  = "pvrl";
      setPVhistory ($paref);
      delete $paref->{histname};
  }
    
return;
}

################################################################
#    Werte Meter Device ermitteln und übertragen
################################################################
sub _transferMeterValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};  

  my $medev  = ReadingsVal($name, "currentMeterDev", "");                                     # aktuelles Meter device
  my ($a,$h) = parseParams ($medev);
  $medev     = $a->[0] // "";
  return if(!$medev || !$defs{$medev});
  
  my $tlim = "23";                                                                            # Stunde 23 -> bestimmte Aktionen                  
  my $type = $hash->{TYPE}; 
  
  if($chour =~ /^($tlim)$/x) {
      deleteReadingspec ($hash, "Today_Hour.*_GridConsumption");
      deleteReadingspec ($hash, "Today_Hour.*_Consumption");                                  # kann später wieder raus !!
      delete $hash->{HELPER}{INITCONTOTAL};
  }
  
  my ($gc,$gcunit) = split ":", $h->{gcon};                                                   # Readingname/Unit für aktuellen Netzbezug
  my ($gt,$ctunit) = split ":", $h->{contotal};                                               # Readingname/Unit für Bezug total
  
  return if(!$gc || !$gt);
  
  Log3($name, 5, "$name - collect Meter data: device=$medev, gcon=$gc ($gcunit), contotal=$gt ($ctunit)");
  
  my $gcuf = $gcunit =~ /^kW$/xi ? 1000 : 1;
  my $co   = ReadingsNum ($medev, $gc, 0) * $gcuf;                                            # aktueller Bezug (W)
    
  push @$daref, "Current_GridConsumption:".$co." W";
  $data{$type}{$name}{current}{consumption} = $co;                                            # Hilfshash Wert current grid consumption Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251
      
  my $ctuf    = $ctunit =~ /^kWh$/xi ? 1000 : 1;
  my $gctotal = ReadingsNum ($medev, $gt, 0) * $ctuf;                                         # Bezug total (Wh)      
   
  my $cdaypast = 0;
  
  for my $hour (0..int $chour) {                                                              # alle bisherigen Erzeugungen des Tages summieren                                            
      $cdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridConsumption", 0);
  }
  
  my $do = 0;
  if ($cdaypast == 0) {                                                                       # Management der Stundenberechnung auf Basis Totalwerte
      if (defined $hash->{HELPER}{INITCONTOTAL}) {
          $do = 1;
      }
      else {
          $hash->{HELPER}{INITCONTOTAL} = $gctotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITCONTOTAL}) {
      $hash->{HELPER}{INITCONTOTAL} = $gctotal-$cdaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridConsumption", 0);
  }
  else {
      $do = 1;
  }
  
  if ($do) {
      my $gctotthishour = int ($gctotal - ($cdaypast + $hash->{HELPER}{INITCONTOTAL}));
      
      # Log3($name, 1, "$name - gctotal: $gctotal, cdaypast: $cdaypast, HELPER: $hash->{HELPER}{INITCONTOTAL}, gctotthishour: $gctotthishour  ");
      
      if($gctotthishour < 0) {
          $gctotthishour = 0;
      }
      
      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_GridConsumption:".$gctotthishour." Wh";
      $data{$type}{$name}{consumption}{sprintf("%02d",$nhour)} = $gctotthishour;                     # Hilfshash Wert Bezug (Wh) Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
      
      $paref->{gctotthishour} = $gctotthishour;
      $paref->{nhour}        = sprintf("%02d",$nhour);
      $paref->{histname}     = "cons";
      setPVhistory ($paref);
      delete $paref->{histname};
  }   
      
return;
}

################################################################
#     Berechnen Forecast Tag / Stunden Verschieber
#     aus aktueller Stunde + lfd. Nummer
################################################################
sub _calcDayHourMove {               
  my $chour = shift;
  my $num   = shift;

  my $fh = $chour + $num; 
  my $fd = int ($fh / 24) ;
  $fh    = $fh - ($fd * 24);  
   
return ($fd,$fh);
}

################################################################
#              FHEMWEB Fn
################################################################
sub FwFn {
  my ($FW_wname, $d, $room, $pageHash) = @_;                       # pageHash is set for summaryFn.
  my $hash = $defs{$d};
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
  my $hash = shift;
  my $d    = $hash->{NAME};
  
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

################################################################
#    Grafik als HTML zurück liefern    (z.B. für Widget)
################################################################
sub pageAsHtml { 
  my $hash = shift;
  my $ftui = shift;
  my $name = $hash->{NAME};
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
  my (%beam1,%is,%t,%we,%di,%beam2);
  
  ##########################################################
  # Kontext des SolarForecast-Devices speichern für Refresh
  $hash->{HELPER}{SPGDEV}    = $name;                                                      # Name des aufrufenden SMAPortalSPG-Devices
  $hash->{HELPER}{SPGROOM}   = $FW_room   ? $FW_room   : "";                               # Raum aus dem das SMAPortalSPG-Device die Funktion aufrief
  $hash->{HELPER}{SPGDETAIL} = $FW_detail ? $FW_detail : "";                               # Name des SMAPortalSPG-Devices (wenn Detailansicht)
  
  my $fcdev  = ReadingsVal ($name, "currentForecastDev", "");                              # aktuelles Forecast Device  
  my $indev  = ReadingsVal ($name, "currentInverterDev", "");                              # aktuelles Inverter Device
  my ($a,$h) = parseParams ($indev);
  $indev     = $a->[0] // "";
  
  my $pv0    = ReadingsNum ($name, "ThisHour_PVforecast", undef);
  
  my $is     = ReadingsVal ($name, "inverterStrings",     undef);                          # String Konfig
  my $peak   = ReadingsVal ($name, "modulePeakString",    undef);                          # String Peak
  my $dir    = ReadingsVal ($name, "moduleDirection",     undef);                          # Modulausrichtung Konfig
  my $ta     = ReadingsVal ($name, "moduleTiltAngle",     undef);                          # Modul Neigungswinkel Konfig
  
  if(!$is || !$fcdev || !$indev || !$peak || !defined $pv0 || !$dir || !$ta) {
      my $link = qq{<a href="/fhem?detail=$name">$name</a>};  
      $height  = AttrNum($name, 'beamHeight', 200);   
      $ret    .= "<table class='roomoverview'>";
      $ret    .= "<tr style='height:".$height."px'>";
      $ret    .= "<td>";
      
      if(!$fcdev) {
          $ret .= qq{Please select a Solar Forecast device with "set $link currentForecastDev"};
      }
      elsif(!$indev) {
          $ret .= qq{Please select an Inverter device with "set $link currentInverterDev"};   
      }
      elsif(!$is) {
          $ret .= qq{Please define all of your used string names with "set $link inverterStrings".};
      }
      elsif(!$peak) {
          $ret .= qq{Please specify the total module peak with "set $link modulePeakString"};   
      }
      elsif(!$dir) {
          $ret .= qq{Please specify the module direction with "set $link moduleDirection"};   
      }
      elsif(!$ta) {
          $ret .= qq{Please specify the module tilt angle with "set $link moduleTiltAngle"};   
      }
      elsif(!defined $pv0) {
          $ret .= qq{Awaiting data from selected Solar Forecast device ...};   
      }
      
      $ret   .= "</td>";
      $ret   .= "</tr>";
      $ret   .= "</table>";
      return $ret;
  }

  my $cclv                    = "L05";
  my @pgCDev                  = split(',',AttrVal($name,"consumerList",""));            # definierte Verbraucher ermitteln
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
  my $offset     =  AttrNum($name, 'history_hour',            0   );

  my $hourstyle  =  AttrVal ($name, 'hourStyle',          undef   );

  my $colorfc    =  AttrVal ($name, 'beam1Color',         '000000');
  my $colorc     =  AttrVal ($name, 'beam2Color',         'C4C4A7');               
  my $beam1cont  =  AttrVal ($name, 'beam1Content',     'forecast');
  my $beam2cont  =  AttrVal ($name, 'beam2Content',     'forecast');  

  my $icon       =  AttrVal ($name, 'consumerAdviceIcon', undef   );
  my $html_start =  AttrVal ($name, 'htmlStart',          undef   );                      # beliebige HTML Strings die vor der Grafik ausgegeben werden
  my $html_end   =  AttrVal ($name, 'htmlEnd',            undef   );                      # beliebige HTML Strings die nach der Grafik ausgegeben werden

  my $lotype       =  AttrVal ($name, 'layoutType',          'pv'   );
  my $kw         =  AttrVal ($name, 'Wh/kWh',              'Wh'   );

  $height        =  AttrNum ($name, 'beamHeight',           200   );
  my $width      =  AttrNum ($name, 'beamWidth',              6   );                      # zu klein ist nicht problematisch
  my $w          =  $width*$maxhours;                                                     # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  my $fsize      =  AttrNum ($name, 'spaceSize',             24   );
  my $maxVal     =  AttrNum ($name, 'maxPV',                  0   );                      # dyn. Anpassung der Balkenhöhe oder statisch ?

  my $show_night =  AttrNum ($name, 'showNight',              0   );                      # alle Balken (Spalten) anzeigen ?
  my $show_diff  =  AttrVal ($name, 'showDiff',            'no'   );                      # zusätzliche Anzeige $di{} in allen Typen
  my $weather    =  AttrNum ($name, 'showWeather',            1   );
  my $colorw     =  AttrVal ($name, 'weatherColor',    'FFFFFF'   );                      # Wetter Icon Farbe
  my $colorwn    =  AttrVal ($name, 'weatherColor_night', $colorw );                      # Wetter Icon Farbe Nacht

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
  
  my $pcfa = ReadingsVal ($name,"pvCorrectionFactor_Auto", "off");

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
      my $autoct  = "automatic correction:";  
      my $lblPv4h = "next&nbsp;4h:";
      my $lblPvRe = "remain today:";
      my $lblPvTo = "tomorrow:";
      my $lblPvCu = "actual";
     
      if(AttrVal("global", "language", "EN") eq "DE") {                                             # Header globales Sprachschema Deutsch
          $lupt    = "Stand:";
          $autoct  = "automatische Korrektur:";          
          $lblPv4h = encode("utf8", "nächste&nbsp;4h:");
          $lblPvRe = "Rest&nbsp;heute:";
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
          
          ## Update-Icon
          ##############
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
          
          ## Autokorrektur-Icon
          ######################
          my $acicon;
          if ($pcfa eq "on") {
              $acicon = "<img src=\"$FW_ME/www/images/default/10px-kreis-gruen.png\">";
          } 
          elsif ($pcfa eq "off") {
              $acicon = "off";
          } 
          elsif ($pcfa =~ /standby/ix) {
              my ($rtime) = $pcfa =~ /for (.*?) hours/x;
              $acicon     = "<img src=\"$FW_ME/www/images/default/10px-kreis-gelb.png\">&nbsp;(Start in ".$rtime." h)";
          } 
          else {
              $acicon = "<img src=\"$FW_ME/www/images/default/10px-kreis-rot.png\">";
          }
          
  
          ## erste Header-Zeilen
          #######################
          $header .= "<tr><td colspan=\"3\" align=\"left\"><b>".$dlink."</b></td><td colspan=\"3\" align=\"left\">".$lupt.  "&nbsp;".$lup."&nbsp;".$upicon."</td></tr>";
          $header .= "<tr><td colspan=\"3\" align=\"left\"><b>          </b></td><td colspan=\"3\" align=\"left\">".$autoct."&nbsp;"              .$acicon."</td></tr>";
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

    my $thishour;

    (undef,undef,undef,$thishour) = ReadingsVal($name, "ThisHour_Time", '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
    (undef,undef,undef,$thishour) = ReadingsVal($name, "ThisHour_Time", '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x if (AttrVal('global', 'language', '') eq 'DE');
    $thishour = int($thishour); # keine führende Null
    $t{0} = $thishour;

    my $val1;
    my $val2;

    if ($offset) {
    $t{0} += $offset;
    $t{0} += 24 if ($t{0} < 0);
    my $t0 = sprintf('%02d', $t{0}+1); # Index liegt eins höher : 10:00 = Index '11'
    $val1  = (exists($data{$hash->{TYPE}}{$name}{pvfc}{$t0}))   ? $data{$hash->{TYPE}}{$name}{pvfc}{$t0}   : 0;
    $val2  = (exists($data{$hash->{TYPE}}{$name}{pvreal}{$t0})) ? $data{$hash->{TYPE}}{$name}{pvreal}{$t0} : 0;
    $we{0} = (exists($data{$hash->{TYPE}}{$name}{weather}{$t0}{id})) ? $data{$hash->{TYPE}}{$name}{weather}{$t0}{id} : -1;
    #$is{0}     = undef;
    }
    else {   
    my $t0 = sprintf('%02d', $t{0}+1);
    $val1  = (exists($data{$hash->{TYPE}}{$name}{pvfc}{$t0}))   ? $data{$hash->{TYPE}}{$name}{pvfc}{$t0}   :  0;
        $val2  = (exists($data{$hash->{TYPE}}{$name}{pvreal}{$t0})) ? $data{$hash->{TYPE}}{$name}{pvreal}{$t0} :  0;
    # ToDo : klären ob ThisHour:weather_Id stimmt in Bezug zu ThisHour_Time
    $we{0} = (exists($hash->{HELPER}{'ThisHour_WeatherId'}))    ? $hash->{HELPER}{"ThisHour_WeatherId"}    : -1;
    #$is{0}   = (ReadingsVal($name,"ThisHour_IsConsumptionRecommended",'no') eq 'yes' ) ? $icon : undef;
    }

    $beam1{0} = ($beam1cont eq 'forecast') ? $val1 : $val2;
    $beam2{0} = ($beam2cont eq 'forecast') ? $val1 : $val2;
    $di{0}    = $beam1{0} - $beam2{0};

    # User Auswahl überschreiben wenn beide Werte die gleiche Basis haben !
    $lotype = 'pv' if ($beam1cont eq $beam2cont);

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

  $maxVal    = !$maxVal ? $beam1{0} : $maxVal;                                                      # Startwert wenn kein Wert bereits via attr vorgegeben ist

  my $maxCon = $beam2{0};                                                                           # für Typ co
  my $maxDif = $di{0};                                                                           # für Typ diff
  my $minDif = $di{0};                                                                           # für Typ diff

    for my $i (1..($maxhours*2)-1) { # doppelte Anzahl berechnen

    my $val1;
    my $val2 = 0;
    my $ii   = sprintf('%02d',$i);

    $t{$i}  = $thishour +$i;
    $t{$i} -= 24 if ($t{$i} > 23);

    if ($offset < 0) {

        $t{$i} += $offset;
        $t{$i} += 24 if ($t{$i} < 0);

        my $jj  = sprintf('%02d',$t{$i});

        if ($i <= abs($offset)) {

        $val1   = (exists($data{$hash->{TYPE}}{$name}{pvfc}{$jj}))   ? $data{$hash->{TYPE}}{$name}{pvfc}{$jj}   : 0;
        $val2   = (exists($data{$hash->{TYPE}}{$name}{pvreal}{$jj})) ? $data{$hash->{TYPE}}{$name}{pvreal}{$jj} : 0;
        $we{$i} = (exists($data{$hash->{TYPE}}{$name}{weather}{$jj}{id})) ? $data{$hash->{TYPE}}{$name}{weather}{$jj}{id} : -1;
        }
        else {
        my $nh  = sprintf('%02d', $i+$offset);
        $val1   = ReadingsNum($name, 'NextHour'.$nh.'_PVforecast',  0);
        # ToDo : klären ob -1 oder nicht !
        #$nh  = sprintf('%02d', $i+$offset-1);
        $we{$i} = (exists($hash->{HELPER}{'NextHour'.$nh.'_WeatherId'})) ?$hash->{HELPER}{'NextHour'.$nh.'_WeatherId'} : -1;
        }
    }
    else {
        $val1   = ReadingsNum($name, 'NextHour'.$ii.'_PVforecast',  0); # Forecast
        $we{$i} = (exists($hash->{HELPER}{'NextHour'.$ii.'_WeatherId'})) ? $hash->{HELPER}{'NextHour'.$ii.'_WeatherId'} : -1; # für Wettericons 
        #$is{$i}   = (ReadingsVal($name,"NextHour".$ii."_IsConsumptionRecommended",'no') eq 'yes') ? $icon : undef;
    }

    $beam1{$i} = ($beam1cont eq 'forecast') ? $val1 :$val2;
    $beam2{$i} = ($beam2cont eq 'forecast') ? $val1 :$val2;

    # sicher stellen das wir keine undefs in der Liste haben !
    $beam1{$i} //= 0;
    $beam2{$i} //= 0;
    $di{$i}      = $beam1{$i} - $beam2{$i};
        $we{$i}    //= -1;

    $maxVal = $beam1{$i} if ($beam1{$i} > $maxVal); 
    $maxCon = $beam2{$i} if ($beam2{$i} > $maxCon);
    $maxDif = $di{$i}    if ($di{$i} > $maxDif);
    $minDif = $di{$i}    if ($di{$i} < $minDif);
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

        my $ii;
    for my $i (0..($maxhours*2)-1) {
        next if (!$show_night  && ($we{$i} > 99) && !$beam1{$i} && !$beam2{$i});
        # Lässt Nachticons aber noch durch wenn es einen Wert gibt , ToDo : klären ob die Nacht richtig gesetzt wurde
        $ii++; # wieviele Stunden haben wir bisher angezeigt ?
        last if ($ii > $maxhours); # vorzeitiger Abbruch

        # FHEM Wetter Icons (weather_xxx) , Skalierung und Farbe durch FHEM Bordmittel
        # ToDo : weather_icon sollte im Fehlerfall Title mit der ID besetzen um in FHEMWEB sofort die ID sehen zu können
        my ($icon_name, $title) = (($we{$i} > 99)) ? weather_icon($we{$i}-100) : weather_icon($we{$i});
        # unknown -> FHEM Icon Fragezeichen im Kreis wird als Ersatz Icon ausgegeben
        Log3($name, 4, "$name - unknown weather id: ".$we{$i}.", please inform the maintainer") if($icon_name eq 'unknown');

        $icon_name .= ($we{$i} < 100 ) ? '@'.$colorw  : '@'.$colorwn;
        $val        = FW_makeImage($icon_name);

        if ($val eq $icon_name) {                                                      # passendes Icon beim User nicht vorhanden ! ( attr web iconPath falsch/prüfen/update ? )
            $val  ='<b>???<b/>';                                                       
            Log3($name, 3, qq{$name - the icon $we{$i} not found. Please check attribute "iconPath" of your FHEMWEB instance and/or update your FHEM software});
        }

        $ret .= "<td title='$title' class='smaportal' width='$width' style='margin:1px; vertical-align:middle align:center; padding-bottom:1px;'>$val</td>";   # title -> Mouse Over Text
        # mit $we{$i} = undef kann man unten leicht feststellen ob für diese Spalte bereits ein Icon ausgegeben wurde oder nicht
        # Todo : ist jetzt nicht so , prüfen da formatVal6 we undef auswertet
    }

    $ret .= "<td class='smaportal'></td></tr>";                                            # freier Platz am Ende der Icon Zeile
    }

    if($show_diff eq 'top') {                                                                  # Zusätzliche Zeile Ertrag - Verbrauch
    $ret .= "<tr class='even'><td class='smaportal'></td>";                                # freier Platz am Anfang
    my $ii;
    for my $i (0..($maxhours*2)-1) {
        # gleiche Bedingung wie oben
        next if (!$show_night  && ($we{$i} > 99) && !$beam1{$i} && !$beam2{$i});
        $ii++; # wieviele Stunden haben wir bisher angezeigt ?
        last if ($ii > $maxhours); # vorzeitiger Abbruch

        $val  = formatVal6($di{$i},$kw,$we{$i});
        $val  = ($di{$i} < 0) ?  '<b>'.$val.'<b/>' : ($val>0) ? '+'.$val : $val; # negative Zahlen in Fettschrift, 0 aber ohne +
        $ret .= "<td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td>"; 
    }
    $ret .= "<td class='smaportal'></td></tr>"; # freier Platz am Ende 
    }

    $ret .= "<tr class='even'><td class='smaportal'></td>";                                    # Neue Zeile mit freiem Platz am Anfang

    my $ii = 0;
    for my $i (0..($maxhours*2)-1) {
    # gleiche Bedingung wie oben
    next if (!$show_night  && ($we{$i} > 99) && !$beam1{$i} && !$beam2{$i});
    $ii++;
    last if ($ii > $maxhours);

    # Achtung Falle, Division by Zero möglich, 
    # maxVal kann gerade bei kleineren maxhours Ausgaben in der Nacht leicht auf 0 fallen  
    $height = 200 if (!$height);                                                           # Fallback, sollte eigentlich nicht vorkommen, außer der User setzt es auf 0
    $maxVal = 1   if (!int $maxVal);
    $maxCon = 1   if (!$maxCon);

    # Der zusätzliche Offset durch $fsize verhindert bei den meisten Skins 
    # dass die Grundlinie der Balken nach unten durchbrochen wird

    if ($lotype eq 'pv') {
        $he = int(($maxVal-$beam1{$i}) / $maxVal*$height) + $fsize;
        $z3 = int($height + $fsize - $he);
    } 

    if ($lotype eq 'pvco') {
        # Berechnung der Zonen
        # he - freier der Raum über den Balken. fsize wird nicht verwendet, da bei diesem Typ keine Zahlen über den Balken stehen 
        # z2 - der Ertrag ggf mit Icon
        # z3 - der Verbrauch , bei zu kleinem Wert wird der Platz komplett Zone 2 zugeschlagen und nicht angezeigt
        # z2 und z3 nach Bedarf tauschen, wenn der Verbrauch größer als der Ertrag ist

        $maxVal = $maxCon if ($maxCon > $maxVal);                                         # wer hat den größten Wert ?

        if ($beam1{$i} > $beam2{$i}) {                                                          # pv oben , co unten
        $z2 = $beam1{$i}; $z3 = $beam2{$i}; 
        } 
        else {                                                                            # tauschen, Verbrauch ist größer als Ertrag
        $z3 = $beam1{$i}; $z2 = $beam2{$i}; 
        }

        $he = int(($maxVal-$z2)/$maxVal*$height);
        $z2 = int(($z2 - $z3)/$maxVal*$height);

        $z3 = int($height - $he - $z2);                                                   # was von maxVal noch übrig ist
          
        if ($z3 < int($fsize/2)) {                                                        # dünnen Strichbalken vermeiden / ca. halbe Zeichenhöhe
        $z2 += $z3; $z3 = 0; 
        }
    }

    if ($lotype eq 'diff') {  # Typ diff
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
        $he = (!$px_pos || !$maxDif) ? 0 : int(($maxDif-$z2)/$maxDif*$px_pos);                        # Teilung durch 0 vermeiden
        $z2 = ($px_pos - $he) ;

        $z4 = (!$px_neg || !$minDif) ? 0 : int((abs($minDif)-$z3)/abs($minDif)*$px_neg);              # Teilung durch 0 unbedingt vermeiden
        $z3 = ($px_neg - $z4);

        # Beiden Zonen die Werte ausgeben könnten muß fsize als zusätzlicher Raum zugeschlagen werden !
        $he += $fsize; 
        $z4 += $fsize if ($z3);                                                           # komplette Grafik ohne negativ Balken, keine Ausgabe von z3 & z4
    }
    
    # das style des nächsten TD bestimmt ganz wesentlich das gesammte Design
    # das \n erleichtert das lesen des Seitenquelltext beim debugging
    # vertical-align:bottom damit alle Balken und Ausgaben wirklich auf der gleichen Grundlinie sitzen

    $ret .="<td style='text-align: center; padding-left:1px; padding-right:1px; margin:0px; vertical-align:bottom; padding-top:0px'>\n";

    if ($lotype eq 'pv') {
        #my $v   = ($lotype eq 'co') ? $beam2{$i} : $beam1{$i} ; 
        #$v   = 0 if (($lotype eq 'co') && !$beam1{$i} && !$show_night);                        # auch bei type co die Nacht ggf. unterdrücken
        $val = formatVal6($beam1{$i},$kw,$we{$i});

        $ret .="<table width='100%' height='100%'>";                                      # mit width=100% etwas bessere Füllung der Balken
        $ret .="<tr class='even' style='height:".$he."px'>";
        $ret .="<td class='smaportal' style='vertical-align:bottom'>".$val."</td></tr>";

        if ($beam1{$i} || $show_night) {                                                     # Balken nur einfärben wenn der User via Attr eine Farbe vorgibt, sonst bestimmt class odd von TR alleine die Farbe
        my $style = "style=\"padding-bottom:0px; vertical-align:top; margin-left:auto; margin-right:auto;";
        $style   .= defined $colorfc ? " background-color:#$colorfc\"" : '"';         # Syntaxhilight 

        $ret .= "<tr class='odd' style='height:".$z3."px;'>";
        $ret .= "<td align='center' class='smaportal' ".$style.">";
              
        my $sicon = 1;                                                    
        $ret .= $is{$i} if (defined ($is{$i}) && $sicon);

        ##################################
        # inject the new icon if defined
        #$ret .= consinject($hash,$i,@pgCDev) if($s);
              
        $ret .= "</td></tr>";
        }
    }
 
    if ($lotype eq 'pvco') { 
        my ($color1, $color2, $style1, $style2, $v);

        $ret .="<table width='100%' height='100%'>\n";                                   # mit width=100% etwas bessere Füllung der Balken

        # der Freiraum oben kann beim größten Balken ganz entfallen
        $ret .="<tr class='even' style='height:".$he."px'><td class='smaportal'></td></tr>" if ($he);

        if($beam1{$i} > $beam2{$i}) {                                                          # wer ist oben, co pder pv ? Wert und Farbe für Zone 2 & 3 vorbesetzen
        $val     = formatVal6($beam1{$i},$kw,$we{$i});
        $color1  = $colorfc;
        $style1  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
        $style1 .= (defined($color1)) ? " background-color:#$color1\"" : '"';
              
        if($z3) {                                                                    # die Zuweisung können wir uns sparen wenn Zone 3 nachher eh nicht ausgegeben wird
            $v       = formatVal6($beam2{$i},$kw,$we{$i});
            $color2  = $colorc;
            $style2  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
            $style2 .= (defined($color2)) ? " background-color:#$color2\"" : '"';
        } 
        } 
        else {
        $val     = formatVal6($beam2{$i},$kw,$we{$i});
        $color1  = $colorc;
        $style1  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
        $style1 .= (defined($color1)) ? " background-color:#$color1\"" : '"';
              
        if($z3) {
            $v       = formatVal6($beam1{$i},$kw,$we{$i});
            $color2  = $colorfc;
            $style2  = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
            $style2 .= (defined($color2)) ? " background-color:#$color2\"" : '"';
        }
        }

        $ret .= "<tr class='odd' style='height:".$z2."px'>";
        $ret .= "<td align='center' class='smaportal' ".$style1.">$val";     
        #$ret .= $is{$i} if (defined $is{$i});
         
        ##################################
        # inject the new icon if defined
        #$ret .= consinject($hash,$i,@pgCDev) if($s);
         
        $ret .= "</td></tr>";

        if ($z3) {                                                                                 # die Zone 3 lassen wir bei zu kleinen Werten auch ganz weg 
        $ret .= "<tr class='odd' style='height:".$z3."px'>";
        $ret .= "<td align='center' class='smaportal' ".$style2.">$v</td></tr>";
        }
    } 

    if ($lotype eq 'diff') {                                                                                       # Type diff
        my $style = "style=\"padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
        $ret .= "<table width='100%' border='0'>\n";                                         # Tipp : das nachfolgende border=0 auf 1 setzen hilft sehr Ausgabefehler zu endecken
        #$val  = ($di{$i} >= 0) ? formatVal6($di{$i},$kw,$we{$i}) : '';

        $val = ($di{$i} > 0) ? formatVal6($di{$i},$kw,$we{$i}) : '';
        $val = '&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;' if ($di{$i} == 0);                         # Sonderfall , hier wird die 0 gebraucht !

        if ($val) {
        $ret .= "<tr class='even' style='height:".$he."px'>";
        $ret .= "<td class='smaportal' style='vertical-align:bottom'>".$val."</td></tr>";
        }

        if ($di{$i} >= 0) {                                                                       # mit Farbe 1 colorfc füllen
        $style .= defined $colorfc ? " background-color:#$colorfc\"" : '"';
        $z2     = 1 if ($di{$i} == 0);                                                       # Sonderfall , 1px dünnen Strich ausgeben
        $ret  .= "<tr class='odd' style='height:".$z2."px'>";
        $ret  .= "<td align='center' class='smaportal' ".$style.">";
        $ret  .= $is{$i} if (defined $is{$i});
        $ret  .= "</td></tr>";
        } 
        else {                                                                                   # ohne Farbe
        $z2 = 2 if ($di{$i} == 0);                                                           # Sonderfall, hier wird die 0 gebraucht !
            if ($z2 && $val) {                                                                   # z2 weglassen wenn nicht unbedigt nötig bzw. wenn zuvor he mit val keinen Wert hatte
            $ret .= "<tr class='even' style='height:".$z2."px'>";
            $ret .= "<td class='smaportal'></td></tr>";
            }
        }
     
        if ($di{$i} < 0) {                                                                        # Negativ Balken anzeigen ?
        $style .= (defined($colorc)) ? " background-color:#$colorc\"" : '"';                 # mit Farbe 2 colorc füllen
        $ret   .= "<tr class='odd' style='height:".$z3."px'>";
        $ret   .= "<td align='center' class='smaportal' ".$style."></td></tr>";
        } 
        elsif ($z3) {                                                                             # ohne Farbe
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
        $val  = ($di{$i} < 0) ?  '<b>'.$val.'<b/>' : ($val>0) ? '+'.$val : $val; # negative Zahlen in Fettschrift, 0 aber ohne +
        $ret .= "<tr class='even'><td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td></tr>"; 
    }

    $ret .= "<tr class='even'><td class='smaportal' style='vertical-align:bottom; text-align:center;'>";
    $t{$i} = $t{$i}.$hourstyle if(defined($hourstyle));# z.B. 10:00 statt 10
    $ret .= (($t{$i} == $thishour) && ($offset < 0)) ? '<a class="changed" style="visibility:visible"><span>'.$t{$i}.'</span></a>' : $t{$i};
    $thishour = 24 if ($t{$i} == $thishour); # nur einmal verwenden !
    $ret .="</td></tr></table></td>";                                                   
    } ## for i


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

  $id    = int $id;
  
  if(defined $weather_ids{$id}) {
      return $weather_ids{$id}{icon}, encode("utf8", $weather_ids{$id}{txtd});
  }
  
return 'unknown','';
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

################################################################
#      benötigte Attribute im DWD Device checken
################################################################
sub checkdwdattr {
  my $dwddev = shift;
  
  my @fcprop = map { trim($_) } split ",", AttrVal($dwddev, "forecastProperties", "pattern");
  
  my @aneeded;
  for my $am (@dwdattrmust) {
      next if($am ~~ @fcprop);
      push @aneeded, $am;
  }
  
return @aneeded;
}

##################################################################################################
#            PV Forecast Rad1h in kWh / Wh
# Berechnung nach Formel 1 aus http://www.ing-büro-junge.de/html/photovoltaik.html:
#
#    * Faktor für Umwandlung kJ in kWh:   0.00027778
#    * Eigene Modulfläche in qm z.B.:     31,04
#    * Wirkungsgrad der Module in % z.B.: 16,52
#    * Wirkungsgrad WR in % z.B.:         98,3
#    * Korrekturwerte wegen Ausrichtung/Verschattung etc.
#
# Die Formel wäre dann: 
# Ertrag in Wh = Rad1h * 0.00027778 * 31,04 qm * 16,52% * 98,3% * 100% * 1000
#
# Berechnung nach Formel 2 aus http://www.ing-büro-junge.de/html/photovoltaik.html:
#
#    * Globalstrahlung:                G =  kJ / m2
#    * Korrektur mit Flächenfaktor f:  Gk = G * f
#    * Globalstrahlung (STC):          1 kW/m2
#    * Peak Leistung String (kWp):     Pnenn = x kW
#    * Performance Ratio:              PR (typisch 0,85 bis 0,9)
#    * weitere Korrekturwerte für Regen, Wolken etc.: Korr
#
#    pv (kWh) = G * f * 0.00027778 (kWh/m2) / 1 kW/m2 * Pnenn (kW) * PR * Korr
#    pv (Wh)  = G * f * 0.00027778 (kWh/m2) / 1 kW/m2 * Pnenn (kW) * PR * Korr * 1000
#
# Die Abhängigkeit der Strahlungsleistung der Sonnenenergie nach Wetterlage und Jahreszeit ist 
# hier beschrieben: 
# https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/sonnenstunden
#
# !!! PV Berechnungsgrundlagen !!!
# https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/ertrag
# http://www.ing-büro-junge.de/html/photovoltaik.html
# 
##################################################################################################
sub calcPVforecast {            
  my $name = shift;
  my $rad  = shift;                                                                             # Nominale Strahlung aus DWD Device
  my $fh   = shift;                                                                             # Stunde des Tages 
  
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $stch = $data{$type}{$name}{strings};                                                      # String Configuration Hash
  my $pr   = 1.0;                                                                               # Performance Ratio (PR)
  
  my @strings = sort keys %{$stch};
  
  my $cloudcover = $hash->{HELPER}{"NextHour".sprintf("%02d",$fh)."_CloudCover"} // 0;          # effektive Wolkendecke
  my $ccf        = 1 - (($cloudcover - $cloud_base) * $cloudslope / 100);                       # Cloud Correction Faktor mit Steilheit und Fußpunkt
  
  my $rainprob   = $hash->{HELPER}{"NextHour".sprintf("%02d",$fh)."_RainProb"} // 0;            # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
  my $rcf        = 1 - (($rainprob - $rain_base) * $rainslope / 100);                           # Rain Correction Faktor mit Steilheit

  my $kw     = AttrVal     ($name, 'Wh/kWh', 'Wh');
  my $hc     = ReadingsNum ($name, "pvCorrectionFactor_".sprintf("%02d",$fh), 1        );       # Korrekturfaktor für die Stunde des Tages
  
  my $pvsum  = 0;  
  
  for my $st (@strings) {                                                                       # für jeden String der Config ..
      my $peak   = $stch->{"$st"}{peak};                                                        # String Peak (kWp)
      my $ta     = $stch->{"$st"}{tilt};                                                        # Neigungswinkel Solarmodule
      my $moddir = $stch->{"$st"}{dir};                                                         # Ausrichtung der Solarmodule
      
      my $af     = $hff{$ta}{$moddir} / 100;                                                    # Flächenfaktor: http://www.ing-büro-junge.de/html/photovoltaik.html
      $hc        = 1 if(1*$hc == 0);
      
      # pv (Wh)  = G * f * 0.00027778 (kWh/m2) / 1 kW/m2 * Pnenn (kW) * PR * Korr * 1000
      my $pv   = sprintf "%.1f", ($rad * $af * $kJtokWh * $peak * $pr * $hc * $ccf * $rcf * 1000);
  
      my $lh = {                                                                                # Log-Hash zur Ausgabe
          "moduleDirection"         => $moddir,
          "modulePeakString"        => $peak,
          "moduleTiltAngle"         => $ta,
          "Area factor"             => $af,
          "Cloudfactor"             => $ccf,
          "Rainfactor"              => $rcf,
          "pvCorrectionFactor"      => $hc,
          "Radiation"               => $rad,
          "Factor kJ to kWh"        => $kJtokWh,
          "PV generation (Wh)"      => $pv
      };  
      
      my $sq;
      for my $idx (sort keys %{$lh}) {
          $sq .= $idx." => ".$lh->{$idx}."\n";             
      }

      Log3($name, 5, "$name - PV forecast calc for hour ".sprintf("%02d",$fh)." string: $st ->\n$sq");
      
      $pvsum += $pv;
  }
  
  if($kw eq "Wh") {
      $pvsum = int $pvsum;
  }
  
  Log3($name, 5, "$name - PV forecast calc for hour ".sprintf("%02d",$fh)." summary: $pvsum");
 
return $pvsum;
}

################################################################
#       Abweichung PVreal / PVforecast berechnen
#       bei eingeschalteter automat. Korrektur
################################################################
sub calcVariance {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};
  
  my $dcauto = ReadingsVal ($name, "pvCorrectionFactor_Auto", "off");                   # nur bei "on" automatische Varianzkalkulation
  if($dcauto =~ /^off/x) {
      Log3($name, 4, "$name - automatic Variance calculation is switched off."); 
      return;      
  }
  
  my $tlim = "00";                                                                      # Stunde 00 -> löschen aller Autocalc Statusreadings des Tages                  
  
  if($chour =~ /^($tlim)$/x) {
      deleteReadingspec ($hash, "pvCorrectionFactor_.*_autocalc");
  }
  
  my $idts = ReadingsTimestamp($name, "currentInverterDev", "");                        # Definitionstimestamp des Inverterdevice
  return if(!$idts);
  $idts    = timestringToTimestamp ($hash, $idts);
  
  my $t = time;                                                                         # aktuelle Unix-Zeit

  if($t - $idts < 86400) {
      my $rmh = sprintf "%.1f", ((86400 - ($t - $idts)) / 3600);
      Log3($name, 4, "$name - Variance calculation in standby. It starts in $rmh hours."); 
      readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", "on (remains in standby for $rmh hours)", 0); 
      return;      
  }
  else {
      readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", "on", 0);
  }

  my $maxvar = AttrVal($name, "maxVariancePerDay", $defmaxvar);                                           # max. Korrekturvarianz

  my @da;
  for my $h (1..23) {
      next if(!$chour || $h >= $chour);
      my $fcval = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVforecast", 0);
      next if(!$fcval);
 
      my $pvval = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVreal", 0);
      next if(!$pvval);
      
      my $cdone = ReadingsVal ($name, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc", "");
      if($cdone eq "done") {
          Log3($name, 5, "$name - pvCorrectionFactor Hour: ".sprintf("%02d",$h). " already calculated");
          next;
      }

      my $oldfac = ReadingsNum ($name, "pvCorrectionFactor_".sprintf("%02d",$h),  1);                     # bisher definierter Korrekturfaktor
      $oldfac    = 1 if(1*$oldfac == 0);
      
      Log3($name, 5, "$name - Hour: ".sprintf("%02d",$h).", Today PVreal: $pvval, PVforecast: $fcval");
      
      $paref->{hour}     = $h;
      my ($pvavg,$fcavg) = calcFromHistory ($paref);                                                      # historische PV / Forecast Vergleichswerte ermitteln
      $pvval             = $pvavg ? ($pvval + $pvavg) / 2 : $pvval;                                       # Ertrag aktuelle Stunde berücksichtigen
      $fcval             = $fcavg ? ($fcval + $fcavg) / 2 : $fcval;                                       # Vorhersage aktuelle Stunde berücksichtigen
      my $factor         = sprintf "%.2f", ($pvval / $fcval);                                             # Faktorberechnung: reale PV / Prognose
      
      if(abs($factor - $oldfac) > $maxvar) {
          $factor = sprintf "%.2f", ($factor > $oldfac ? $oldfac + $maxvar : $oldfac - $maxvar);
          Log3($name, 3, "$name - new limited Variance factor: $factor (old: $oldfac) for hour: $h");
      }
      else {
          Log3($name, 3, "$name - new Variance factor: $factor (old: $oldfac) for hour: $h calculated") if($factor != $oldfac);
      }
      
      push @da, "pvCorrectionFactor_".sprintf("%02d",$h).":".$factor." (automatic)";
      push @da, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc:done";
  }
  
  createReadingsFromArray ($hash, \@da, 1);
      
return;
}

################################################################
#   Berechne Durchschnitte aus Werten der PV History
################################################################
sub calcFromHistory {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $t     = $paref->{t};                                                                # aktuelle Unix-Zeit          
  my $hour  = $paref->{hour};                                                             # Stunde für die der Durchschnitt bestimmt werden soll
  
  $hour     = sprintf("%02d",$hour);
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};  
  my $day   = strftime "%d", localtime($t);                                               # aktueller Tag
  my $pvhh  = $data{$type}{$name}{pvhist};
  
  my $calcd = AttrVal($name, "numHistDays", $calcmaxd);
  
  my @k     = sort {$a<=>$b} keys %{$pvhh};
  my $ile   = $#k;                                                                        # Index letztes Arrayelement
  my ($idx) = grep {$k[$_] eq "$day"} (0..@k-1);                                          # Index des aktuellen Tages
  
  if(defined $idx) {
      my $ei = $idx-1;
      $ei    = $ei < 0 ? $ile : $ei;
      my @efa;
      
      for my $e (0..$calcd) {
          last if($e == $calcd || $k[$ei] == $day);
          unshift @efa, $k[$ei];
          $ei--;
      }
        
      my $anzavg = scalar(@efa);
      
      if($anzavg) {
          Log3 ($name, 4, "$name - PV History -> Day $day has index $idx. Days ($calcd) for calc: ".join " ",@efa); 
      }
      else {                                                                              # vermeide Fehler: Illegal division by zero
          Log3 ($name, 4, "$name - PV History -> Day $day has index $idx. Use only current day for average calc");
          return;
      }
      
      my ($pvrl,$pvfc) = (0,0);
            
      for my $dayfa (@efa) {
          $pvrl += $pvhh->{$dayfa}{$hour}{pvrl} // 0;
          $pvfc += $pvhh->{$dayfa}{$hour}{pvfc} // 0;
      }
      
      my $pvavg = sprintf "%.2f", $pvrl / $anzavg;
      my $fcavg = sprintf "%.2f", $pvfc / $anzavg;
      
      Log3 ($name, 4, "$name - PV History -> average hour ($hour) -> real: $pvavg, forecast: $fcavg");
      
      return ($pvavg,$fcavg);
  }
  
return;
}

################################################################
#   PV und PV Forecast in History-Hash speichern zur 
#   Berechnung des Korrekturfaktors über mehrere Tage
################################################################
sub setPVhistory {               
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $t         = $paref->{t};                                                                    # aktuelle Unix-Zeit
  my $nhour     = $paref->{nhour};
  my $day       = $paref->{day};
  my $histname  = $paref->{histname}      // qq{};
  my $ethishour = $paref->{ethishour}     // 0;
  my $calcpv    = $paref->{calcpv}        // 0;
  my $gthishour = $paref->{gctotthishour} // 0;
  
  my $type = $hash->{TYPE};
  my $val  = q{};
  
  if($histname eq "pvrl") {                                                                       # realer Energieertrag
      $val = $ethishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvrl} = $ethishour;  
      
      my $pvrlsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvrlsum += $data{$type}{$name}{pvhist}{$day}{$k}{pvrl} // 0;
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvrl} = $pvrlsum;      
  }
  
  if($histname eq "pvfc") {                                                                       # prognostizierter Energieertrag
      $val = $calcpv;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvfc} = $calcpv; 

      my $pvfcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvfcsum += $data{$type}{$name}{pvhist}{$day}{$k}{pvfc} // 0;
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvfc} = $pvfcsum;       
  }
  
  if($histname eq "cons") {                                                                       # bezogene Energie
      $val = $gthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gcons} = $gthishour; 

      my $gcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gcsum += $data{$type}{$name}{pvhist}{$day}{$k}{gcons} // 0;
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gcons} = $gcsum;       
  }
  
  Log3 ($name, 5, "$name - set PV History hour: $nhour, hash: $histname, val: $val");
    
return;
}

################################################################
#           liefert aktuelle Einträge des in $htol
#           angegebenen internen Hash
################################################################
sub listDataPool {                 
  my $hash = shift;
  my $htol = shift;  
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  my ($sq,$h);
  
  my $sub = sub { 
      my $day = shift;
      my $ret;          
      for my $key (sort{$a<=>$b} keys %{$h->{$day}}) {
          my $pvrl = $h->{$day}{$key}{pvrl}  // 0;
          my $pvfc = $h->{$day}{$key}{pvfc}  // 0;
          my $cons = $h->{$day}{$key}{gcons} // 0;
          $ret    .= "\n      " if($ret);
          $ret    .= $key." => pvreal: $pvrl, pvforecast: $pvfc, gridcon: $cons";
      }
      return $ret;
  };
  
  if ($htol eq "pvhist") {
      $h = $data{$type}{$name}{pvhist};
      if (!keys %{$h}) {
          return qq{PV cache is empty.};
      }
      for my $idx (reverse sort{$a<=>$b} keys %{$h}) {
          $sq .= $idx." => ".$sub->($idx)."\n";             
      }
  }
  
  if ($htol eq "weather") {
      $h = $data{$hash->{TYPE}}{$name}{weather};
      if (!keys %{$h}) {
          return qq{Weather cache is empty.};
      }
      for my $idx (sort{$a<=>$b} keys %{$h}) {
          $sq .= $idx." => id:         ".$data{$hash->{TYPE}}{$name}{weather}{$idx}{id}.        "\n"; 
          $sq .= "   => txt:        "   .$data{$hash->{TYPE}}{$name}{weather}{$idx}{txt}.       "\n";
          $sq .= "   => cloudcover: "   .$data{$hash->{TYPE}}{$name}{weather}{$idx}{cloudcover}."\n";
          $sq .= "   => rainprob:   "   .$data{$hash->{TYPE}}{$name}{weather}{$idx}{rainprob}.  "\n";
      }
  }
  
  if ($htol eq "pvreal") {
      $h = $data{$type}{$name}{pvreal};
      if (!keys %{$h}) {
          return qq{PV real cache is empty.};
      }
      for my $idx (sort{$a<=>$b} keys %{$h}) {
          $sq .= $idx." => ".$data{$type}{$name}{pvreal}{$idx}."\n";             
      }
  }
      
return $sq;
}

################################################################
#        liefert aktuelle Stringkonfiguration
#        inkl. Vollständigkeitscheck
################################################################
sub checkStringConfig {                 
  my $hash = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $stch = $data{$type}{$name}{strings};
  
  my $sub = sub { 
      my $string = shift;
      my $ret;          
      for my $key (sort keys %{$stch->{"$string"}}) {
          $ret    .= ", " if($ret);
          $ret    .= $key.": ".$stch->{"$string"}{$key};
      }
      return $ret;
  };
        
  if (!keys %{$stch}) {
      return qq{String configuration is empty.};
  }
  
  my $sc;
  my $cf = 0;
  for my $sn (sort keys %{$stch}) {
      my $sp = $sn." => ".$sub->($sn)."\n";
      $cf    = 1 if($sp !~ /dir.*?peak.*?tilt/x);             # Test Vollständigkeit: z.B. Süddach => dir: S, peak: 5.13, tilt: 45
      $sc   .= $sp;
  }
  
  if($cf) {                             
      $sc .= "\n\nOh no &#128577, your string configuration is inconsistent.\nPlease check the settings of modulePeakString, moduleDirection, moduleTiltAngle !";
  }
  else {
      $sc .= "\n\nCongratulations &#128522, your string configuration checked without found errors !";
  }
      
return $sc;
}

################################################################
#               Zusammenfassungen erstellen
################################################################
sub collectSummaries {            
  my $hash  = shift;
  my $chour = shift;                          # aktuelle Stunde
  my $daref = shift;
  
  my $name  = $hash->{NAME};

  my $next4HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $restOfDaySum  = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $tomorrowSum   = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $todaySum      = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  
  my $rdh              = 24 - $chour - 1;                                         # verbleibende Anzahl Stunden am Tag beginnend mit 00 (abzüglich aktuelle Stunde)
  my $thforecast       = ReadingsNum ($name, "ThisHour_PVforecast", 0);
  $next4HoursSum->{PV} = $thforecast;
  $restOfDaySum->{PV}  = $thforecast;
  
  for my $h (1..47) {
      $next4HoursSum->{PV} += ReadingsNum ($name, "NextHour".  (sprintf "%02d", $h)."_PVforecast", 0) if($h <= 3);
      $restOfDaySum->{PV}  += ReadingsNum ($name, "NextHour".  (sprintf "%02d", $h)."_PVforecast", 0) if($h <= $rdh);
      $tomorrowSum->{PV}   += ReadingsNum ($name, "NextHour".  (sprintf "%02d", $h)."_PVforecast", 0) if($h >  $rdh);
      $todaySum->{PV}      += ReadingsNum ($name, "Today_Hour".(sprintf "%02d", $h)."_PVforecast", 0) if($h <= 23);
  }
  
  push @$daref, "Next04Hours_PV:". (int $next4HoursSum->{PV})." Wh";
  push @$daref, "RestOfDay_PV:".   (int $restOfDaySum->{PV}). " Wh";
  push @$daref, "Tomorrow_PV:".    (int $tomorrowSum->{PV}).  " Wh";
  push @$daref, "Today_PV:".       (int $todaySum->{PV}).     " Wh";

  createReadingsFromArray ($hash, $daref, 1);
  
return;
}

################################################################
#  einen Zeitstring YYYY-MM-TT hh:mm:ss in einen Unix 
#  Timestamp umwandeln
################################################################
sub timestringToTimestamp {            
  my $hash    = shift;
  my $tstring = shift;
  my $name    = $hash->{NAME};

  my($y, $mo, $d, $h, $m, $s) = $tstring =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})\s([0-9]{2}):([0-9]{2}):([0-9]{2})/xs;
  return if(!$mo || !$y);
  
  my $timestamp = fhemTimeLocal($s, $m, $h, $d, $mo-1, $y-1900);
  
return $timestamp;
}

################################################################
#                   Readings aus Array erstellen
#       $daref:  Referenz zum Array der zu erstellenden Readings
#                muß Paare <Readingname>:<Wert> enthalten
#       $doevt:  1-Events erstellen, 0-keine Events erstellen
#
# readingsBulkUpdate($hash,$reading,$value,$changed,$timestamp)
#
################################################################
sub createReadingsFromArray {
  my $hash  = shift;
  my $daref = shift;
  my $doevt = shift // 0;  
  
  readingsBeginUpdate($hash);
  
  for my $elem (@$daref) {
      my ($rn,$rval) = split ":", $elem, 2;
      readingsBulkUpdate($hash, $rn, $rval);      
  }

  readingsEndUpdate($hash, $doevt);
  
return;
}

################################################################
#    alle Readings eines Devices oder nur Reading-Regex 
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
      
      my $fcdev = ReadingsVal($name, "currentForecastDev", "");              # Forecast Device
      ($a,$h) = parseParams ($fcdev);
      $fcdev  = $a->[0] // "";      
      
      my $indev = ReadingsVal($name, "currentInverterDev", "");              # Inverter Device
      ($a,$h) = parseParams ($indev);
      $indev  = $a->[0] // "";
      
      my $medev = ReadingsVal($name, "currentMeterDev",    "");              # Meter Device
      
      ($a,$h) = parseParams ($medev);
      $medev  = $a->[0] // "";
      
      push @nd, $fcdev;
      push @nd, $indev;
      push @nd, $medev;
      
      if(@nd) {
          $hash->{NOTIFYDEV} = join ",", @nd;
          readingsSingleUpdate ($hash, ".associatedWith", join(" ",@nd), 0);
      }
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

Das Modul SolarForecast erstellt auf Grundlage der Werte aus generischen Quellendevices eine 
Vorhersage für den solaren Ertrag und weitere Informationen als Grundlage für abhängige Steuerungen. <br>
Die Solargrafik kann ebenfalls in FHEM Tablet UI mit dem 
<a href="https://wiki.fhem.de/wiki/FTUI_Widget_SMAPortalSPG">"SolarForecast Widget"</a> integriert werden. <br><br>

Die solare Vorhersage basiert auf der durch den Deutschen Wetterdienst (DWD) prognostizierten Globalstrahlung am 
Anlagenstandort. Im zugeordneten DWD_OpenData Device ist die passende Wetterstation mit dem Attribut "forecastStation" 
festzulegen um eine Prognose für diesen Standort zu erhalten. <br>
Abhängig von der physikalischen Anlagengestaltung (Ausrichtung, Winkel, Aufteilung in mehrere Strings, u.a.) wird die 
verfügbare Globalstrahlung ganz spezifisch in elektrische Energie umgewandelt. <br>
Ein SolarForecast Device unterstützt einen Wechselrichter mit beliebig vielen angeschlossenen Strings. Weiteren Wechselrichtern
werden weitere SolarForecast Devices zugeordnet.

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
    anlagenspezifische Angaben mit dem entsprechenden set-Kommando vorzunehmen. <br>
    Mit nachfolgenden set-Kommandos werden die Quellendevices und Quellenreadings für maßgebliche Informationen 
    hinterlegt: <br><br>

      <ul>
         <table>  
         <colgroup> <col width=35%> <col width=65%> </colgroup>
            <tr><td> <b>currentForecastDev</b>   </td><td>Device welches Strahlungsdaten liefert          </td></tr>
            <tr><td> <b>currentInverterDev</b>   </td><td>Device welches PV Leistungsdaten liefert        </td></tr>
            <tr><td> <b>currentMeterDev</b>      </td><td>Device welches aktuelle Netzbezugsdaten liefert </td></tr>         
         </table>
      </ul>
      <br>
      
    Um eine Anpassung an die persönliche Anlage zu ermöglichen, können Korrekturfaktoren manuell 
    (set &lt;name&gt; pvCorrectionFactor_XX) bzw. automatisiert (set &lt;name&gt; pvCorrectionFactor_Auto) eingefügt 
    werden.       
 
    <br><br>
  </ul>

  <a name="SolarForecastset"></a>
  <b>Set</b> 
  <ul>
    <ul>
      <a name="currentForecastDev"></a>
      <li><b>currentForecastDev </b> <br> 
      Legt das Device (Typ DWD_OpenData) fest, welches die Daten der solaren Vorhersage liefert. Ist noch kein Device dieses Typs
      vorhanden, muß es manuell definiert werden (siehe <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      Im ausgewählten DWD_OpenData Device müssen mindestens diese Attribute gesetzt sein: <br><br>

      <ul>
         <table>  
         <colgroup> <col width=25%> <col width=75%> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                                                             </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>Rad1h,TTT,Neff,R101,ww,SunUp,SunRise,SunSet                                                   </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                                                             </td></tr>         
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Stationscode der ausgewerteten DWD Station&gt;                                            </td></tr>
            <tr><td>                                </td><td><b>Hinweis:</b> Die ausgewählte forecastStation muß Strahlungswerte (Rad1h Readings) liefern. </td></tr>
         </table>
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="currentInverterDev"></a>
      <li><b>currentInverterDev &lt;Inverter Device Name&gt; pv=&lt;Reading aktuelle PV-Leistung&gt;:&lt;Einheit&gt; etotal=&lt;Reading Summe Energieerzeugung&gt;:&lt;Einheit&gt;  </b> <br> 
      Legt ein beliebiges Device zur Lieferung der aktuellen PV Erzeugungswerte fest. 
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> <b>pv</b>       </td><td>Reading mit aktueller PV-Leistung                                                                                              </td></tr>
          <tr><td> <b>etotal</b>   </td><td>ein stetig aufsteigender Zähler der gesamten erzeugten Energie </td></tr>
          <tr><td> <b>Einheit</b>  </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                                                                            </td></tr>
        </table>
      </ul> 
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentInverterDev STP5000 pv=total_pac:kW etotal=etotal:kWh <br>
        # Device STP5000 liefert PV-Werte. Die aktuell erzeugte Leistung im Reading "total_pac" (kW) und die tägliche Erzeugung im 
          Reading "etotal" (kWh)
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="currentMeterDev"></a>
      <li><b>currentMeterDev &lt;Meter Device Name&gt; gcon=&lt;Reading aktueller Netzbezug&gt;:&lt;Einheit&gt; contotal=&lt;Reading Summe Netzbezug&gt;:&lt;Einheit&gt;</b> <br> 
      Legt ein beliebiges Device zur Messung des Energiebezugs fest.
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>gcon</b>     </td><td>Reading welches die aktuell aus dem Netz bezogene Leistung liefert   </td></tr>
          <tr><td> <b>contotal</b> </td><td>Reading welches die Summe der aus dem Netz bezogenen Energie liefert </td></tr>
          <tr><td> <b>Einheit</b>  </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                         </td></tr>
        </table>
      </ul> 
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentMeterDev SMA_Energymeter gcon=Bezug_Wirkleistung:W contotal=Bezug_Wirkleistung_Zaehler:kWh <br>
        # Device SMA_Energymeter liefert den aktuellen Netzbezug im Reading "Bezug_Wirkleistung" (W) und den totalen Bezug im Reading "Bezug_Wirkleistung_Zaehler" (kWh)
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="inverterStrings"></a>
      <li><b>inverterStrings &lt;Stringname1&gt;[,&lt;Stringname2&gt;,&lt;Stringname3&gt;,...] </b> <br> 
      Bezeichnungen der am Wechselrichter aktiven Strings. Diese Bezeichnungen werden als Schlüssel in den weiteren 
      Settings verwendet. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; inverterStrings Ostdach,Südgarage,S3 <br>
      </ul>    
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="modulePeakString"></a>
      <li><b>modulePeakString &lt;Stringname1&gt;=&lt;Peak&gt; [&lt;Stringname2&gt;=&lt;Peak&gt; &lt;Stringname3&gt;=&lt;Peak&gt; ...] </b> <br> 
      Die Peakleistung des Strings "StringnameX" in kWp. Der Stringname ist ein Schlüsselwert des 
      Readings <b>inverterStrings</b>. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; modulePeakString Ostdach=5.1 Südgarage=2.0 S3=7.2 <br>
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="moduleDirection"></a>
      <li><b>moduleDirection &lt;Stringname1&gt;=&lt;dir&gt; [&lt;Stringname2&gt;=&lt;dir&gt; &lt;Stringname3&gt;=&lt;dir&gt; ...] </b> <br> 
      Ausrichtung &lt;dir&gt; der Solarmodule im String "StringnameX". Der Stringname ist ein Schlüsselwert des 
      Readings <b>inverterStrings</b>. <br>
      Die Richtungsangabe &lt;dir&gt; kann eine der folgenden Werte sein: <br><br>

      <ul>
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>N</b>  </td><td>Nordausrichtung            </td></tr>
            <tr><td> <b>NE</b> </td><td>Nord-Ost Ausrichtung       </td></tr>
            <tr><td> <b>E</b>  </td><td>Ostausrichtung             </td></tr>         
            <tr><td> <b>SE</b> </td><td>Süd-Ost Ausrichtung        </td></tr>
            <tr><td> <b>S</b>  </td><td>Südausrichtung             </td></tr>
            <tr><td> <b>SW</b> </td><td>Süd-West Ausrichtung       </td></tr>
            <tr><td> <b>W</b>  </td><td>Westausrichtung            </td></tr>
            <tr><td> <b>NW</b> </td><td>Nord-West Ausrichtung      </td></tr>
         </table>
      </ul> 
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleDirection Ostdach=E Südgarage=S S3=NW <br>
      </ul>       
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="moduleTiltAngle"></a>
      <li><b>moduleTiltAngle &lt;Stringname1&gt;=&lt;Winkel&gt; [&lt;Stringname2&gt;=&lt;Winkel&gt; &lt;Stringname3&gt;=&lt;Winkel&gt; ...] </b> <br> 
      Neigungswinkel der Solarmodule. Der Stringname ist ein Schlüsselwert des Readings <b>inverterStrings</b>. <br>
      Mögliche Neigungswinkel sind: 0,10,20,30,40,45,50,60,70,80,90 (0 = waagerecht, 90 = senkrecht). <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleTiltAngle Ostdach=40 Südgarage=60 S3=30 <br>
      </ul>
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
    
    <ul>
      <a name="reset"></a>
      <li><b>reset </b> <br> 
       Löscht die aus der Drop-Down Liste gewählte Datenquelle. <br>    
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="writeHistory"></a>
      <li><b>writeHistory </b> <br> 
       Die vom Device gesammelten historischen PV Daten werden in ein File geschrieben. Dieser Vorgang wird per default 
       regelmäßig im Hintergrund ausgeführt. Im Internal "HISTFILE" wird der Filename und der Zeitpunkt der letzten 
       Speicherung dokumentiert. <br>    
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
    
    <ul>
      <a name="pvHistory"></a>
      <li><b>pvHistory </b> <br>  
      Listet die historischen Werte der letzten Tage (max. 31) sortiert nach dem Tagesdatum und der Stunde des jeweiligen 
      Tages auf.
      Dabei sind <b>pvreal</b> der reale PV Ertrag, <b>pvforecast</b> der prognostizierte PV Ertrag und <b>gridcon</b> 
      der Netzbezug der jeweiligen Stunde.
      </li>      
    </ul>
    <br>
    
    <ul>
      <a name="pvReal"></a>
      <li><b>pvReal </b> <br>  
      Listet die ermittelten PV Werte des Ringwertzählers der letzten 24h auf. Die Stundenangaben beziehen sich auf die Stunde 
      des Tages, z.B. Stunde 09 ist die Zeit von 08:00-09:00. 
      </li>      
    </ul>
    <br>
    
    <ul>
      <a name="weatherData"></a>
      <li><b>weatherData </b> <br>  
      Listet die ermittelten Wetterdaten des Ringwertzählers der letzten 24h auf. Die Stundenangaben beziehen sich auf den 
      Beginn der Stunde, z.B. bezieht sich die Angabe 09 auf die Zeit von 09:00-10:00. 
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
          In Verbindung mit "showLink" ein beliebiger Anzeigename.
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
    
       <a name="beam1Color"></a>
       <li><b>beam1Color </b><br>
         Farbauswahl der primären Balken.  
       </li>
       <br>
       
       <a name="beam1Content"></a>
       <li><b>beam1Content </b><br>
         Legt den darzustellenden Inhalt der primären Balken fest.
       
         <ul>   
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>forecast</b>     </td><td>Vorhersage der PV-Erzeugung (default) </td></tr>
            <tr><td> <b>real</b>         </td><td>tatsächliche PV-Erzeugung             </td></tr>
            <tr><td> <b>consumption</b>  </td><td>Energie Bezug aus dem Netz            </td></tr>
         </table>
         </ul>       
       </li>
       <br> 
       
       <a name="beam2Color"></a>
       <li><b>beam2Color </b><br>
         Farbauswahl der sekundären Balken. Die zweite Farbe ist nur sinnvoll für den Anzeigedevice-Typ "pvco" und "diff".
       </li>
       <br>  
       
       <a name="beam2Content"></a>
       <li><b>beam2Content </b><br>
         Legt den darzustellenden Inhalt der sekundären Balken fest. 

         <ul>   
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>forecast</b>     </td><td>Vorhersage der PV-Erzeugung (default) </td></tr>
            <tr><td> <b>real</b>         </td><td>tatsächliche PV-Erzeugung             </td></tr>
            <tr><td> <b>consumption</b>  </td><td>Energie Bezug aus dem Netz            </td></tr>
         </table>
         </ul>         
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
       
       <a name="consumerAdviceIcon"></a>
       <li><b>consumerAdviceIcon </b><br>
         Setzt das Icon zur Darstellung der Zeiten mit Verbraucherempfehlung. 
         Dazu kann ein beliebiges Icon mit Hilfe der Standard "Select Icon"-Funktion (links unten im FHEMWEB) direkt ausgewählt 
         werden. 
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
       
       <a name="hourCount"></a>
       <li><b>hourCount &lt;4...24&gt; </b><br>
         Anzahl der Balken/Stunden. <br>
         (default: 24)
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
       
       <a name="interval"></a>
       <li><b>interval &lt;Sekunden&gt; </b><br>
         Zeitintervall der Datensammlung. <br>
         Ist interval explizit auf "0" gesetzt, erfolgt keine automatische Datensammlung und muss mit "get &lt;name&gt; data" 
         manuell erfolgen. <br>
         (default: 70)
       </li><br>
       
       <a name="layoutType"></a>
       <li><b>layoutType &lt;pv | co | pvco | diff&gt; </b><br>
       Layout der integrierten Grafik. <br>
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
 
       <a name="maxPV"></a>
       <li><b>maxPV &lt;0...val&gt; </b><br>
         Maximaler Ertrag in einer Stunde zur Berechnung der Balkenhöhe. <br>
         (default: 0 -> dynamisch)
       </li>
       <br>
       
       <a name="maxVariancePerDay"></a>
       <li><b>maxVariancePerDay &lt;Zahl&gt; </b><br>
         Maximale Änderungsgröße des PV Vorhersagefaktors (Reading pvCorrectionFactor_XX) pro Tag. <br>
         (default: 0.5)
       </li>
       <br>
       
       <a name="numHistDays"></a>
       <li><b>numHistDays </b><br>
         Anzahl der vergangenen Tage (historische Daten) die zur Autokorrektur der PV Vorhersage verwendet werden sofern
         aktiviert. <br>
         (default: 7)
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

       <a name="weatherColor_night"></a>
       <li><b>weatherColor_night </b><br>
         Farbe der Wetter-Icons für die Nachtstunden.
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

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
          DoTrigger
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
  "0.34.1" => "11.04.2021  further improvement of cloud dependent calculation autocorrection ",
  "0.34.0" => "10.04.2021  only hours with the same cloud cover range are considered for pvCorrection, some fixes ",
  "0.33.0" => "09.04.2021  new setter currentBatteryDev, bugfix in _transferMeterValues ",
  "0.32.0" => "09.04.2021  currentMeterDev can have: gcon=-gfeedin ",
  "0.31.1" => "07.04.2021  write new values to pvhistory, change CO to Current_Consumption in graphic ",
  "0.31.0" => "06.04.2021  extend currentMeterDev by gfeedin, feedtotal ",
  "0.30.0" => "05.04.2021  estimate readings to the minute in sub _calcSummaries, new setter energyH4Trigger ",
  "0.29.0" => "03.04.2021  new setter powerTrigger ",
  "0.28.0" => "03.04.2021  new attributes beam1FontColor, beam2FontColor, rename/new some readings ",
  "0.27.0" => "02.04.2021  additional readings ",
  "0.26.0" => "02.04.2021  rename attr maxPV to maxValBeam, bugfix in _additionalActivities ",
  "0.25.0" => "28.03.2021  changes regarding perlcritic, new getter valCurrent ",
  "0.24.0" => "26.03.2021  the language setting of the system is taken into account in the weather texts ".
                           "rename weatherColor_night to weatherColorNight, history_hour to historyHour ",
  "0.23.0" => "25.03.2021  change attr layoutType, fix calc reading Today_PVforecast ",
  "0.22.0" => "25.03.2021  event management, move DWD values one hour to the future, some more corrections ",
  "0.21.0" => "24.03.2021  event management ",
  "0.20.0" => "23.03.2021  new sub CircularVal, NexthoursVal, some fixes ",
  "0.19.0" => "22.03.2021  new sub HistoryVal, some fixes ",
  "0.18.0" => "21.03.2021  implement sub forecastGraphic from Wzut ",
  "0.17.1" => "21.03.2021  bug fixes, delete Helper->NextHour ",
  "0.17.0" => "20.03.2021  new attr cloudFactorDamping / rainFactorDamping, fixes in Graphic sub ",
  "0.16.0" => "19.03.2021  new getter nextHours, some fixes ",
  "0.15.3" => "19.03.2021  corrected weather consideration for call calcPVforecast ",
  "0.15.2" => "19.03.2021  some bug fixing ",
  "0.15.1" => "18.03.2021  replace ThisHour_ by NextHour00_ ",
  "0.15.0" => "18.03.2021  delete overhanging readings in sub _transferDWDForecastValues ",
  "0.14.0" => "17.03.2021  new getter PVReal, weatherData, consumption total in currentMeterdev ",
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
  currentBatteryDev       => { fn => \&_setbatteryDevice          },
  energyH4Trigger         => { fn => \&_setenergyH4Trigger        },
  powerTrigger            => { fn => \&_setpowerTrigger           },
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
  data          => { fn => \&_getdata,           needcred => 0 },
  html          => { fn => \&_gethtml,           needcred => 0 },
  ftui          => { fn => \&_getftui,           needcred => 0 },
  valCurrent    => { fn => \&_getlistCurrent,    needcred => 0 },
  pvHistory     => { fn => \&_getlistPVHistory,  needcred => 0 },
  pvCircular    => { fn => \&_getlistPVCircular, needcred => 0 },
  nextHours     => { fn => \&_getlistNextHours,  needcred => 0 },
  stringConfig  => { fn => \&_getstringConfig,   needcred => 0 },
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
  '0'   => { s => '0', icon => 'weather_sun',              txtd => 'sonnig',                                                                   txte => 'sunny'                                                                      },
  '1'   => { s => '0', icon => 'weather_cloudy_light',     txtd => 'Bewölkung abnehmend',                                                      txte => 'Cloudiness decreasing'                                                      },
  '2'   => { s => '0', icon => 'weather_cloudy',           txtd => 'Bewölkung unverändert',                                                    txte => 'Cloudiness unchanged'                                                       },
  '3'   => { s => '0', icon => 'weather_cloudy_heavy',     txtd => 'Bewölkung zunehmend',                                                      txte => 'Cloudiness increasing'                                                      },
  '4'   => { s => '0', icon => 'unknown',                  txtd => 'Sicht durch Rauch oder Asche vermindert',                                  txte => 'Visibility reduced by smoke or ash'                                         },
  '5'   => { s => '0', icon => 'unknown',                  txtd => 'trockener Dunst (relative Feuchte < 80 %)',                                txte => 'dry haze (relative humidity < 80 %)'                                        },
  '6'   => { s => '0', icon => 'unknown',                  txtd => 'verbreiteter Schwebstaub, nicht vom Wind herangeführt',                    txte => 'widespread airborne dust, not brought in by the wind'                       },
  '7'   => { s => '0', icon => 'unknown',                  txtd => 'Staub oder Sand bzw. Gischt, vom Wind herangeführt',                       txte => 'Dust or sand or spray, brought in by the wind'                              },
  '8'   => { s => '0', icon => 'unknown',                  txtd => 'gut entwickelte Staub- oder Sandwirbel',                                   txte => 'well-developed dust or sand vortex'                                         },
  '9'   => { s => '0', icon => 'unknown',                  txtd => 'Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station',        txte => 'Dust or sand storm in the visual circle, but not at the station'            },

  '10'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel',                                                                    txte => 'Fog'                                                                        },
  '11'  => { s => '0', icon => 'weather_rain_fog',         txtd => 'Nebel mit Regen',                                                          txte => 'Fog with rain'                                                              },
  '12'  => { s => '0', icon => 'weather_fog',              txtd => 'durchgehender Bodennebel',                                                 txte => 'continuous ground fog'                                                      },
  '13'  => { s => '0', icon => 'unknown',                  txtd => 'Wetterleuchten sichtbar, kein Donner gehört',                              txte => 'Weather light visible, no thunder heard'                                    },
  '14'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag im Gesichtskreis, nicht den Boden erreichend',                txte => 'Precipitation in the visual circle, not reaching the ground'                },
  '15'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Ferne (> 5 km), aber nicht an der Station',            txte => 'Precipitation in the distance (> 5 km), but not at the station'             },
  '16'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Nähe (< 5 km), aber nicht an der Station',             txte => 'Precipitation in the vicinity (< 5 km), but not at the station'             },
  '17'  => { s => '0', icon => 'unknown',                  txtd => 'Gewitter (Donner hörbar), aber kein Niederschlag an der Station',          txte => 'Thunderstorm (thunder audible), but no precipitation at the station'        },
  '18'  => { s => '0', icon => 'unknown',                  txtd => 'Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station',    txte => 'marked gusts in the visual circle, but no precipitation at the station'     },
  '19'  => { s => '0', icon => 'unknown',                  txtd => 'Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis',               txte => 'Trombles (funnel-shaped cloud tubes) in the circle of vision'               },

  '20'  => { s => '0', icon => 'unknown',                  txtd => 'nach Sprühregen oder Schneegriesel',                                       txte => 'after drizzle or snow drizzle'                                              },
  '21'  => { s => '0', icon => 'unknown',                  txtd => 'nach Regen',                                                               txte => 'after rain'                                                                 },
  '22'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schnefall',                                                           txte => 'after snowfall'                                                             },
  '23'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeregen oder Eiskörnern',                                         txte => 'after sleet or ice grains'                                                  },
  '24'  => { s => '0', icon => 'unknown',                  txtd => 'nach gefrierendem Regen',                                                  txte => 'after freezing rain'                                                        },
  '25'  => { s => '0', icon => 'unknown',                  txtd => 'nach Regenschauer',                                                        txte => 'after rain shower'                                                          },
  '26'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeschauer',                                                       txte => 'after snow shower'                                                          },
  '27'  => { s => '0', icon => 'unknown',                  txtd => 'nach Graupel- oder Hagelschauer',                                          txte => 'after sleet or hail showers'                                                },
  '28'  => { s => '0', icon => 'unknown',                  txtd => 'nach Nebel',                                                               txte => 'after fog'                                                                  },
  '29'  => { s => '0', icon => 'unknown',                  txtd => 'nach Gewitter',                                                            txte => 'after thunderstorm'                                                         },

  '30'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität abnehmend',                 txte => 'light or moderate sandstorm, decreasing in intensity'                       },
  '31'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, unveränderte Intensität',                 txte => 'light or moderate sandstorm, unchanged intensity'                           },
  '32'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität zunehmend',                 txte => 'light or moderate sandstorm, increasing in intensity'                       },
  '33'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität abnehmend',                              txte => 'heavy sandstorm, decreasing in intensity'                                   },
  '34'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, unveränderte Intensität',                              txte => 'heavy sandstorm, unchanged intensity'                                       },
  '35'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität zunehmend',                              txte => 'heavy sandstorm, increasing in intensity'                                   },
  '36'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneefegen, unter Augenhöhe',                       txte => 'light or moderate snow sweeping, below eye level'                           },
  '37'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneefegen, unter Augenhöhe',                                     txte => 'heavy snow sweeping, below eye level'                                       },
  '38'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneetreiben, über Augenhöhe',                      txte => 'light or moderate blowing snow, above eye level'                            },
  '39'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneetreiben, über Augenhöhe',                                    txte => 'heavy snow drifting, above eye level'                                       },

  '40'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in einiger Entfernung',                                              txte => 'Fog in some distance'                                                       },
  '41'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in Schwaden oder Bänken',                                            txte => 'Fog in swaths or banks'                                                     },
  '42'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dünner werdend',                                  txte => 'Fog, sky recognizable, thinning'                                            },
  '43'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dünner werdend',                            txte => 'Fog, sky not recognizable, thinning'                                        },
  '44'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, unverändert',                                     txte => 'Fog, sky recognizable, unchanged'                                           },
  '45'  => { s => '1', icon => 'weather_fog',              txtd => 'Nebel',                                                                    txte => 'Fog'                                                                        },
  '46'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dichter werdend',                                 txte => 'Fog, sky recognizable, becoming denser'                                     },
  '47'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dichter werdend',                           txte => 'Fog, sky not visible, becoming denser'                                      },
  '48'  => { s => '1', icon => 'weather_fog',              txtd => 'Nebel mit Reifbildung',                                                    txte => 'Fog with frost formation'                                                   },
  '49'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel mit Reifansatz, Himmel nicht erkennbar',                             txte => 'Fog with frost, sky not visible'                                            },

  '50'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener leichter Sprühregen',                                       txte => 'intermittent light drizzle'                                                 },
  '51'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen',                                                      txte => 'light drizzle'                                                              },
  '52'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Sprühregen',                                        txte => 'intermittent moderate drizzle'                                              },
  '53'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen',                                                      txte => 'light drizzle'                                                              },
  '54'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Sprühregen',                                        txte => 'intermittent heavy drizzle'                                                 },
  '55'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Sprühregen',                                                       txte => 'heavy drizzle'                                                              },
  '56'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter gefrierender Sprühregen',                                         txte => 'light freezing drizzle'                                                     },
  '57'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker gefrierender Sprühregen',                             txte => 'moderate or heavy freezing drizzle'                                         },
  '58'  => { s => '0', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen mit Regen',                                            txte => 'light drizzle with rain'                                                    },
  '59'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker Sprühregen mit Regen',                                txte => 'moderate or heavy drizzle with rain'                                        },

  '60'  => { s => '0', icon => 'weather_rain_light',       txtd => 'unterbrochener leichter Regen oder einzelne Regentropfen',                 txte => 'intermittent light rain or single raindrops'                                },
  '61'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regen',                                                           txte => 'light rain'                                                                 },
  '62'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Regen',                                             txte => 'intermittent moderate rain'                                                 },
  '63'  => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger Regen',                                                            txte => 'moderate rain'                                                              },
  '64'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Regen',                                             txte => 'intermittent heavy rain'                                                    },
  '65'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Regen',                                                            txte => 'heavy rain'                                                                 },
  '66'  => { s => '1', icon => 'weather_rain_snow_light',  txtd => 'leichter gefrierender Regen',                                              txte => 'light freezing rain'                                                        },
  '67'  => { s => '1', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker gefrierender Regen',                                  txte => 'moderate or heavy freezing rain'                                            },
  '68'  => { s => '0', icon => 'weather_rain_snow_light',  txtd => 'leichter Schneeregen',                                                     txte => 'light sleet'                                                                },
  '69'  => { s => '0', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker Schneeregen',                                         txte => 'moderate or heavy sleet'                                                    },

  '70'  => { s => '0', icon => 'weather_snow_light',       txtd => 'unterbrochener leichter Schneefall oder einzelne Schneeflocken',           txte => 'intermittent light snowfall or single snowflakes'                           },
  '71'  => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneefall',                                                      txte => 'light snowfall'                                                             },
  '72'  => { s => '0', icon => 'weather_snow',             txtd => 'unterbrochener mäßiger Schneefall',                                        txte => 'intermittent moderate snowfall'                                             },
  '73'  => { s => '1', icon => 'weather_snow',             txtd => 'mäßiger Schneefall',                                                       txte => 'moderate snowfall'                                                          },
  '74'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'unterbrochener starker Schneefall',                                        txte => 'intermittent heavy snowfall'                                                },
  '75'  => { s => '1', icon => 'weather_snow_heavy',       txtd => 'starker Schneefall',                                                       txte => 'heavy snowfall'                                                             },
  '76'  => { s => '0', icon => 'weather_frost',            txtd => 'Eisnadeln (Polarschnee)',                                                  txte => 'Ice needles (polar snow)'                                                   },
  '77'  => { s => '1', icon => 'weather_frost',            txtd => 'Schneegriesel',                                                            txte => 'Snow drizzle'                                                               },
  '78'  => { s => '0', icon => 'weather_frost',            txtd => 'Schneekristalle',                                                          txte => 'Snow crystals'                                                              },
  '79'  => { s => '0', icon => 'weather_frost',            txtd => 'Eiskörner (gefrorene Regentropfen)',                                       txte => 'Ice grains (frozen raindrops)'                                              },

  '80'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regenschauer',                                                    txte => 'light rain shower'                                                          },
  '81'  => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger oder starkerRegenschauer',                                         txte => 'moderate or heavy rain shower'                                              },
  '82'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'sehr starker Regenschauer',                                                txte => 'very heavy rain shower'                                                     },
  '83'  => { s => '0', icon => 'weather_snow',             txtd => 'mäßiger oder starker Schneeregenschauer',                                  txte => 'moderate or heavy sleet shower'                                             },
  '84'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer',                                                   txte => 'light snow shower'                                                          },
  '85'  => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer',                                                   txte => 'light snow shower'                                                          },
  '86'  => { s => '1', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Schneeschauer',                                       txte => 'moderate or heavy snow shower'                                              },
  '87'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Graupelschauer',                                      txte => 'moderate or heavy sleet shower'                                             },
  '88'  => { s => '0', icon => 'unknown',                  txtd => 'leichter Hagelschauer',                                                    txte => 'light hailstorm'                                                            },
  '89'  => { s => '0', icon => 'unknown',                  txtd => 'mäßiger oder starker Hagelschauer',                                        txte => 'moderate or heavy hailstorm'                                                },

  '90'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '91'  => { s => '0', icon => 'weather_storm',            txtd => '',                                                                         txte => ''                                                                           },
  '92'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '93'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '94'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '95'  => { s => '1', icon => 'weather_thunderstorm',     txtd => 'leichtes oder mäßiges Gewitter ohne Graupel oder Hagel',                   txte => 'light or moderate thunderstorm without sleet or hail'                       },
  '96'  => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter ohne Graupel oder Hagel,Gewitter mit Graupel oder Hagel', txte => 'strong thunderstorm without sleet or hail,thunderstorm with sleet or hail'  },
  '97'  => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Regen oder Schnee',                                   txte => 'heavy thunderstorm with rain or snow'                                       },
  '98'  => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Sandsturm',                                           txte => 'strong thunderstorm with sandstorm'                                         },
  '99'  => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Graupel oder Hagel',                                  txte => 'strong thunderstorm with sleet or hail'                                     },
  '100' => { s => '0', icon => 'weather_night',            txtd => 'sternenklarer Himmel',                                                     txte => 'starry sky'                                                                 },
);

my @chours      = (5..21);                                                       # Stunden des Tages mit möglichen Korrekturwerten                              
my $defpvme     = 16.52;                                                         # default Wirkungsgrad Solarmodule
my $definve     = 98.3;                                                          # default Wirkungsgrad Wechselrichter
my $kJtokWh     = 0.00027778;                                                    # Umrechnungsfaktor kJ in kWh
my $defmaxvar   = 0.5;                                                           # max. Varianz pro Tagesberechnung Autokorrekturfaktor
my $definterval = 70;                                                            # Standard Abfrageintervall
my $defslidenum = 3;                                                             # max. Anzahl der Arrayelemente in Schieberegistern

my $pvhcache    = $attr{global}{modpath}."/FHEM/FhemUtils/PVH_SolarForecast_";   # Filename-Fragment für PV History (wird mit Devicename ergänzt)
my $pvccache    = $attr{global}{modpath}."/FHEM/FhemUtils/PVC_SolarForecast_";   # Filename-Fragment für PV Circular (wird mit Devicename ergänzt)

my $calcmaxd    = 21;                                                            # Anzahl Tage (default) für Durchschnittermittlung zur Vorhersagekorrektur
my @dwdattrmust = qw(Rad1h TTT Neff R101 ww SunUp SunRise SunSet);               # Werte die im Attr forecastProperties des DWD_Opendata Devices mindestens gesetzt sein müssen
my $whistrepeat = 900;                                                           # Wiederholungsintervall Schreiben historische Daten

my $cldampdef   = 45;                                                            # Dämpfung (%) des Korrekturfaktors bzgl. effektiver Bewölkung, siehe: https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/sonnenstunden
my $cloud_base  = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung 

my $rdampdef    = 20;                                                            # Dämpfung (%) des Korrekturfaktors bzgl. Niederschlag (R101)
my $rain_base   = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung 

# Information zu verwendeten internen Datenhashes
# $data{$type}{$name}{circular}                                                  # Ringspeicher
# $data{$type}{$name}{current}                                                   # current values
# $data{$type}{$name}{pvhist}                                                    # historische Werte       
# $data{$type}{$name}{nexthours}                                                 # NextHours Werte


################################################################
#               Init Fn
################################################################
sub Initialize {
  my ($hash) = @_;

  my $fwd = join ",", devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");
  
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
                                "beam1Content:forecast,real,gridconsumption ".
                                "beam1FontColor:colorpicker,RGB ".
                                "beam2Color:colorpicker,RGB ".
                                "beam2Content:forecast,real,gridconsumption ".
                                "beam2FontColor:colorpicker,RGB ".
                                "beamHeight ".
                                "beamWidth ".
                                # "consumerList ".
                                # "consumerLegend:none,icon_top,icon_bottom,text_top,text_bottom ".
                                # "consumerAdviceIcon ".
                                "cloudFactorDamping:slider,0,1,100 ".
                                "disable:1,0 ".
                                "forcePageRefresh:1,0 ".
                                "headerAlignment:center,left,right ".                                       
                                "headerDetail:all,co,pv,pvco,statusLink ".
                                "historyHour:slider,-23,-1,0 ".
                                "hourCount:slider,4,1,24 ".
                                "hourStyle ".
                                "htmlStart ".
                                "htmlEnd ".
                                "interval ".
                                "layoutType:single,double,diff ".
                                "maxVariancePerDay ".
                                "maxValBeam ".
                                "numHistDays:slider,1,1,30 ".
                                "rainFactorDamping:slider,0,1,100 ".
                                "showDiff:no,top,bottom ".
                                "showHeader:1,0 ".
                                "showLink:1,0 ".
                                "showNight:1,0 ".
                                "showWeather:1,0 ".
                                "spaceSize ".                                
                                "Wh/kWh:Wh,kWh ".
                                "weatherColor:colorpicker,RGB ".
                                "weatherColorNight:colorpicker,RGB ".                                
                                $readingFnAttributes;

  $hash->{FW_hideDisplayName} = 1;                     # Forum 88667

  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;                         # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'
 
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

  $file                 = $pvccache.$name;                                         # Cache File PV Circular lesen wenn vorhanden
  $cachename            = "circular";
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
             "currentBatteryDev:textField-long ".
             "currentInverterDev:textField-long ".
             "currentMeterDev:textField-long ".
             "energyH4Trigger:textField-long ".
             "inverterStrings ".
             "modulePeakString ".
             "moduleTiltAngle ".
             "moduleDirection ".
             "powerTrigger:textField-long ".
             "pvCorrectionFactor_Auto:on,off ".
             "reset:currentBatteryDev,currentForecastDev,currentInverterDev,currentMeterDev,energyH4Trigger,inverterStrings,powerTrigger,pvCorrection,pvHistory ".
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
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
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
  
  if(!$h->{gcon} || !$h->{contotal} || !$h->{gfeedin} || !$h->{feedtotal}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  if($h->{gcon} eq "-gfeedin" && $h->{gfeedin} eq "-gcon") {
      return qq{Incorrect input. It is not allowed that the keys gcon and gfeedin refer to each other.};
  }  

  readingsSingleUpdate($hash, "currentMeterDev", $arg, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter currentBatteryDev
################################################################
sub _setbatteryDevice {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  my $badev  = $a->[0] // "";
  
  if(!$badev || !$defs{$badev}) {
      return qq{The device "$badev" doesn't exist!};
  }
  
  if(!$h->{pin} || !$h->{pout}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  if($h->{pin} eq "-pout" && $h->{pout} eq "-pin") {
      return qq{Incorrect input. It is not allowed that the keys pin and pout refer to each other.};
  }  

  readingsSingleUpdate($hash, "currentBatteryDev", $arg, 1);
  createNotifyDev     ($hash);

return;
}

################################################################
#                      Setter powerTrigger
################################################################
sub _setpowerTrigger {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  
  if(!$h) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }
  
  for my $key (keys %{$h}) {
      if($key !~ /^[0-9]+(?:on|off)$/x || $h->{$key} !~ /^[0-9]+$/x) {
          return qq{The key "$key" is invalid. Please consider the commandref.};
      }
  }

  readingsSingleUpdate($hash, "powerTrigger", $arg, 1);

return;
}

################################################################
#                      Setter energyH4Trigger
################################################################
sub _setenergyH4Trigger {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  
  if(!$h) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }
  
  for my $key (keys %{$h}) {
      if($key !~ /^[0-9]+(?:on|off)$/x || $h->{$key} !~ /^[0-9]+$/x) {
          return qq{The key "$key" is invalid. Please consider the commandref.};
      }
  }

  readingsSingleUpdate($hash, "energyH4Trigger", $arg, 1);

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
      if($value !~ /^(?:$tilt)$/x) {
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
      if($value !~ /^(?:$dirs)$/x) {
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
  
  my $cfnum = (split "_", $opt)[1]; 
  deleteReadingspec ($hash, "pvCorrectionFactor_${cfnum}_autocalc");
  
  my @da;
  my $t      = time;                                                                                # aktuelle Unix-Zeit 
  my $chour  = strftime "%H", localtime($t);                                                        # aktuelle Stunde
  
  my $params = {
      hash  => $hash,
      name  => $name,
      t       => $t,
      chour   => $chour,
      daref   => \@da
  };
  
  _transferDWDForecastValues ($params);
  
  if(@da) {
      push @da, "state<>updated";                                                                   # Abschluß state 
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
  
  my $type  = $hash->{TYPE};
  
  if($prop eq "pvHistory") {
      delete $data{$type}{$name}{pvhist};
      delete $hash->{HELPER}{INITETOTAL};
      return;
  }
  
  if($prop eq "pvCorrection") {
      deleteReadingspec ($hash, "pvCorrectionFactor_.*");
      return;
  }
  
  if($prop eq "powerTrigger") {
      deleteReadingspec ($hash, "powerTrigger.*");
      return;
  }
  
  if($prop eq "energyH4Trigger") {
      deleteReadingspec ($hash, "energyH4Trigger.*");
      return;
  }

  readingsDelete($hash, $prop);
  
  if($prop eq "currentMeterDev") {
      readingsDelete($hash, "Current_GridConsumption");
      readingsDelete($hash, "Current_GridFeedIn");
      delete $hash->{HELPER}{INITCONTOTAL};
      delete $hash->{HELPER}{INITFEEDTOTAL};
      delete $data{$type}{$name}{current}{gridconsumption};
      delete $data{$type}{$name}{current}{gridfeedin};
      delete $data{$type}{$name}{current}{consumption};
  }
  
  if($prop eq "currentBatteryDev") {
      readingsDelete($hash, "Current_PowerBatIn");
      readingsDelete($hash, "Current_PowerBatOut");
      delete $data{$type}{$name}{current}{powerbatout};
      delete $data{$type}{$name}{current}{powerbatin};
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
  
  my $ret;
  
  $ret = writeCacheToFile ($hash, "circular", $pvccache.$name);             # Cache File für PV Circular schreiben
  $ret = writeCacheToFile ($hash, "pvhist",   $pvhcache.$name);             # Cache File für PV History schreiben

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
                "nextHours:noArg ".
                "pvCircular:noArg ".
                "pvHistory:noArg ".
                "stringConfig:noArg ".
                "valCurrent:noArg "
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
#                       Getter pvCircular
###############################################################
sub _getlistPVCircular {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};
  
  my $ret   = listDataPool ($hash, "circular");
                    
return $ret;
}

###############################################################
#                       Getter listNextHours
###############################################################
sub _getlistNextHours {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};
  
  my $ret   = listDataPool ($hash, "nexthours");
                    
return $ret;
}

###############################################################
#                       Getter valCurrent
###############################################################
sub _getlistCurrent {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};
  
  my $ret   = listDataPool ($hash, "current");
                    
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
  writeCacheToFile ($hash, "circular", $pvccache.$name);             # Cache File für PV Circular schreiben
  
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
  $file  = $pvccache.$name;                                         # Cache File PV Circular löschen
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
  
  ### nicht mehr benötigte Readings/Daten löschen - kann später wieder raus !!
  for my $i (keys %{$data{$type}{$name}{pvhist}}) {
      delete $data{$type}{$name}{pvhist}{$i}{"00"};
      delete $data{$type}{$name}{pvhist}{$i} if(!$i);               # evtl. vorhandene leere Schlüssel entfernen
  }
  
  deleteReadingspec ($hash, "Today_Hour.*_Consumption");
  deleteReadingspec ($hash, "ThisHour_.*");
  deleteReadingspec ($hash, "Today_PV");
  deleteReadingspec ($hash, "Tomorrow_PV");
  deleteReadingspec ($hash, "Next04Hours_PV");
  deleteReadingspec ($hash, "Next.*HoursPVforecast");
  deleteReadingspec ($hash, "moduleEfficiency");
  deleteReadingspec ($hash, "RestOfDay_PV");
  deleteReadingspec ($hash, "CurrentHourPVforecast");
  deleteReadingspec ($hash, "NextHours_Sum00_PVforecast");

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
      my $t      = time;                                                                           # aktuelle Unix-Zeit 
      my $chour  = strftime "%H", localtime($t);                                                   # aktuelle Stunde
      my $minute = strftime "%M", localtime($t);                                                   # aktuelle Minute
      my $day    = strftime "%d", localtime($t);                                                   # aktueller Tag
            
      my $params = {
          hash   => $hash,
          name   => $name,
          t      => $t,
          minute => $minute,
          chour  => $chour,
          day    => $day,
          state  => "updated",
          daref  => \@da
      };
      
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - ###                New data collection cycle                 ###");
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - current hour of day: ".($chour+1));
      
      _additionalActivities      ($params);                                                        # zusätzliche Events generieren + Sonderaufgaben
      _transferWeatherValues     ($params);                                                        # Wetterwerte übertragen
      _transferDWDForecastValues ($params);                                                        # Forecast Werte übertragen  
      _transferInverterValues    ($params);                                                        # WR Werte übertragen
      _transferMeterValues       ($params);                                                        # Energy Meter auswerten    
      _transferBatteryValues     ($params);                                                        # Batteriewerte einsammeln 
      _evaluateThresholds        ($params);                                                        # Schwellenwerte bewerten und signalisieren
      _calcSummaries             ($params);                                                        # Zusammenfassungen erstellen

      if(@da) {
          createReadingsFromArray ($hash, \@da, 1);
      }
      
      calcVariance ($params);                                                                      # Autokorrektur berechnen
      
      readingsSingleUpdate($hash, "state", $params->{state}, 1);                                   # Abschluß state      
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
  
  writeCacheToFile ($hash, "circular", $pvccache.$name);             # Cache File für PV Circular schreiben
  writeCacheToFile ($hash, "pvhist",   $pvhcache.$name);             # Cache File für PV History schreiben
  
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
      readingsSingleUpdate($hash, "state", "ERROR writing cache file $file - $error", 1);
      return $err;          
  }
  else {
      my $lw = gettimeofday(); 
      $hash->{HISTFILE} = "last write time: ".FmtTime($lw)." File: $file" if($cachename eq "pvhist");
      readingsSingleUpdate($hash, "state", "wrote successfully cachefile $cachename", 1);
  }
   
return; 
}

################################################################
#     Zusätzliche Readings/ Events für Logging generieren und
#     Sonderaufgaben !
################################################################
sub _additionalActivities {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  my $t     = $paref->{t};                                  # Epoche Zeit
  
  my $date  = strftime "%Y-%m-%d", localtime($t);           # aktuelles Datum
  
  my ($ts,$ts1,$pvfc,$pvrl,$gcon);
  
  $ts1  = $date." ".sprintf("%02d",$chour).":00:00";
  
  $pvfc = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_PVforecast", 0); 
  push @$daref, "LastHourPVforecast<>".$pvfc." Wh<>".$ts1;
  
  $pvrl = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_PVreal", 0);
  push @$daref, "LastHourPVreal<>".$pvrl." Wh<>".$ts1;
  
  $gcon = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_GridConsumption", 0);
  push @$daref, "LastHourGridconsumptionReal<>".$gcon." Wh<>".$ts1;
  
  my $tlim = "00";                                                                            # bestimmte Aktionen                    
  if($chour =~ /^($tlim)$/x) {
      if(!exists $hash->{HELPER}{H00DONE}) {
          $date = strftime "%Y-%m-%d", localtime($t-7200);                                    # Vortag (2 h Differenz reichen aus)
          $ts   = $date." 23:59:59";
          
          $pvfc = ReadingsNum($name, "Today_Hour24_PVforecast", 0);  
          push @$daref, "LastHourPVforecast<>".$pvfc."<>".$ts1;
          
          $pvrl = ReadingsNum($name, "Today_Hour24_PVreal", 0);
          push @$daref, "LastHourPVreal<>".$pvrl."<>".$ts1;
          
          $gcon = ReadingsNum($name, "Today_Hour24_GridConsumption", 0);
          push @$daref, "LastHourGridconsumptionReal<>".$gcon."<>".$ts1;
          
          deleteReadingspec ($hash, "Today_Hour.*_Grid.*");
          deleteReadingspec ($hash, "Today_Hour.*_PV.*");
          deleteReadingspec ($hash, "powerTrigger_.*");
          
          delete $hash->{HELPER}{INITETOTAL};
          delete $hash->{HELPER}{INITCONTOTAL};
          delete $hash->{HELPER}{INITFEEDTOTAL};
          $hash->{HELPER}{H00DONE} = 1;
      }
  }
  else {
      delete $hash->{HELPER}{H00DONE};
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
  my $t     = $paref->{t};                                                                     # Epoche Zeit
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  
  my $fcname = ReadingsVal($name, "currentForecastDev", "");                                   # aktuelles Forecast Device
  return if(!$fcname || !$defs{$fcname});
  
  my ($time_str,$epoche);
  my $type = $hash->{TYPE};
  my $uac  = ReadingsVal($name, "pvCorrectionFactor_Auto", "off");                             # Auto- oder manuelle Korrektur
  
  my @aneeded = checkdwdattr ($fcname);
  if (@aneeded) {
      Log3($name, 2, qq{$name - ERROR - the attribute "forecastProperties" of device "$fcname" must contain: }.join ",",@aneeded);
  }
  
  for my $num (0..47) {      
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);
      
      if($fd > 1) {                                                                           # überhängende Werte löschen 
          delete $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)};
          next;
      }
      
      my $fh1 = $fh+1;
      my $fh2 = $fh1 == 24 ? 23 : $fh1;
      my $rad = ReadingsVal($fcname, "fc${fd}_${fh2}_Rad1h", 0);
      
      Log3($name, 5, "$name - collect DWD forecast data: device=$fcname, rad=fc${fd}_${fh2}_Rad1h, Rad1h=$rad");
      
      my $params = {
          hash => $hash,
          name => $name,
          rad  => $rad,
          t    => $t,
          num  => $num,
          uac  => $uac,
          fh   => $fh,
          fd   => $fd
      };
      
      my $calcpv = calcPVforecast ($params);                                                  # Vorhersage gewichtet kalkulieren
                
      $time_str        = "NextHour".sprintf "%02d", $num;
      $epoche          = $t + (3600*$num);                                                      
      my ($ta,$realts) = TimeAdjust ($epoche);
      
      # push @$daref, "CurrentHourPVforecast<>".$calcpv." Wh<>".$realts if($num == 0);
      #push @$daref, "${time_str}_Time<>"      .$ta;
      
      $data{$type}{$name}{nexthours}{$time_str}{pvforecast} = $calcpv;
      $data{$type}{$name}{nexthours}{$time_str}{starttime}  = $ta;
      $data{$type}{$name}{nexthours}{$time_str}{Rad1h}      = $rad;                           # nur Info: original Vorhersage Strahlungsdaten
      
      if($num < 23 && $fh < 24) {                                                             # Ringspeicher PV forecast Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350          
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{pvfc} = $calcpv;
      } 
            
      if($fd == 0 && int $calcpv > 0) {                                                       # Vorhersagedaten des aktuellen Tages zum manuellen Vergleich in Reading speichern
          push @$daref, "Today_Hour".sprintf("%02d",$fh1)."_PVforecast<>$calcpv Wh";             
      }
      
      if($fd == 0 && $fh1) {
          $paref->{calcpv}   = $calcpv;
          $paref->{histname} = "pvfc";
          $paref->{nhour}    = sprintf("%02d",$fh1);
          setPVhistory ($paref); 
          delete $paref->{histname};
      }
  }
  
  push @$daref, ".lastupdateForecastValues<>".$t;                                              # Statusreading letzter DWD update
      
return;
}

################################################################
#    Wetter Werte aus dem angebenen Wetterdevice extrahieren
################################################################
sub _transferWeatherValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                      # Epoche Zeit
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  
  my $fcname = ReadingsVal($name, "currentForecastDev", "");                                    # aktuelles Forecast Device
  return if(!$fcname || !$defs{$fcname});
  
  my $type = $hash->{TYPE};
  my ($time_str);
  
  my $fc0_SunRise = ReadingsVal($fcname, "fc0_SunRise", "00:00");                               # Sonnenaufgang heute    
  my $fc0_SunSet  = ReadingsVal($fcname, "fc0_SunSet",  "00:00");                               # Sonnenuntergang heute  
  my $fc1_SunRise = ReadingsVal($fcname, "fc1_SunRise", "00:00");                               # Sonnenaufgang morgen   
  my $fc1_SunSet  = ReadingsVal($fcname, "fc1_SunSet",  "00:00");                               # Sonnenuntergang morgen 
  
  push @$daref, "Today_SunRise<>".   $fc0_SunRise;
  push @$daref, "Today_SunSet<>".    $fc0_SunSet;
  push @$daref, "Tomorrow_SunRise<>".$fc1_SunRise;
  push @$daref, "Tomorrow_SunSet<>". $fc1_SunSet;
  
  my $fc0_SunRise_round = sprintf "%02d", (split ":", $fc0_SunRise)[0];
  my $fc0_SunSet_round  = sprintf "%02d", (split ":", $fc0_SunSet)[0];
  my $fc1_SunRise_round = sprintf "%02d", (split ":", $fc1_SunRise)[0];
  my $fc1_SunSet_round  = sprintf "%02d", (split ":", $fc1_SunSet)[0];
  
  for my $num (0..46) {                      
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);
      last if($fd > 1);

      my $fh1   = $fh+1;
      my $fh2   = $fh1 == 24 ? 23 : $fh1;
      my $wid   = ReadingsNum($fcname, "fc${fd}_${fh2}_ww",  -1);
      my $neff  = ReadingsNum($fcname, "fc${fd}_${fh2}_Neff", 0);                              # Effektive Wolkendecke
      my $r101  = ReadingsNum($fcname, "fc${fd}_${fh2}_R101", 0);                              # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
      
      my $fhstr = sprintf "%02d", $fh;                                                         # hier kann Tag/Nacht-Grenze verstellt werden
      
      if($fd == 0 && ($fhstr lt $fc0_SunRise_round || $fhstr gt $fc0_SunSet_round)) {          # Zeit vor Sonnenaufgang oder nach Sonnenuntergang heute
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
      }
      elsif ($fd == 1 && ($fhstr lt $fc1_SunRise_round || $fhstr gt $fc1_SunSet_round)) {      # Zeit vor Sonnenaufgang oder nach Sonnenuntergang morgen
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
      }
      
      my $txt = ReadingsVal($fcname, "fc${fd}_${fh2}_wwd", '');

      Log3($name, 5, "$name - collect Weather data: device=$fcname, wid=fc${fd}_${fh1}_ww, val=$wid, txt=$txt, cc=$neff, rp=$r101");
      
      $time_str                                             = "NextHour".sprintf "%02d", $num;         
      $data{$type}{$name}{nexthours}{$time_str}{weatherid}  = $wid;
      $data{$type}{$name}{nexthours}{$time_str}{cloudcover} = $neff;
      $data{$type}{$name}{nexthours}{$time_str}{rainprob}   = $r101;
      
      if($num < 23 && $fh < 24) {                                                              # Ringspeicher Weather Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251        
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{weatherid}  = $wid;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{weathertxt} = $txt;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{wcc}        = $neff;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{wrp}        = $r101;
      }
      
      if($fd == 0 && $fh1) {                                                                   # WeatherId in pvhistory speichern
          $paref->{wid}      = $wid;
          $paref->{histname} = "weatherid";
          $paref->{nhour}    = sprintf("%02d",$fh1);
          setPVhistory ($paref); 
          
          $paref->{wcc}      = $neff;
          $paref->{histname} = "weathercloudcover";
          setPVhistory ($paref);
          
          $paref->{wrp}      = $r101;
          $paref->{histname} = "weatherrainprob";
          setPVhistory ($paref);
          
          delete $paref->{histname};
      }
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
  
  my $type = $hash->{TYPE};
  
  my ($pvread,$pvunit) = split ":", $h->{pv};                                                 # Readingname/Unit für aktuelle PV Erzeugung
  my ($edread,$etunit) = split ":", $h->{etotal};                                             # Readingname/Unit für Energie total
  
  return if(!$pvread || !$edread);
  
  Log3($name, 5, "$name - collect Inverter data: device=$indev, pv=$pvread ($pvunit), etotal=$edread ($etunit)");
  
  my $pvuf   = $pvunit =~ /^kW$/xi ? 1000 : 1;
  my $pv     = ReadingsNum ($indev, $pvread, 0) * $pvuf;                                      # aktuelle Erzeugung (W)  
      
  push @$daref, "Current_PV<>". $pv." W";                                          
  $data{$type}{$name}{current}{generation} = $pv;                                             # Hilfshash Wert current generation Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251
  
  push @{$data{$type}{$name}{current}{genslidereg}}, $pv;                                     # Schieberegister PV Erzeugung
  limitArray ($data{$type}{$name}{current}{genslidereg}, $defslidenum);
  
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
      
      if($ethishour < 0) {
          $ethishour = 0;
      }
      
      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_PVreal<>".$ethishour." Wh";       
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{pvrl} = $ethishour;          # Ringspeicher PV real Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
      
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
  
  my $type = $hash->{TYPE}; 
  
  my ($gc,$gcunit) = split ":", $h->{gcon};                                                   # Readingname/Unit für aktuellen Netzbezug
  my ($gf,$gfunit) = split ":", $h->{gfeedin};                                                # Readingname/Unit für aktuelle Netzeinspeisung
  my ($gt,$ctunit) = split ":", $h->{contotal};                                               # Readingname/Unit für Bezug total
  my ($ft,$ftunit) = split ":", $h->{feedtotal};                                              # Readingname/Unit für Einspeisung total
  
  return if(!$gc || !$gf || !$gt || !$ft);
  
  $gfunit //= $gcunit;
  $gcunit //= $gfunit;
  
  Log3($name, 5, "$name - collect Meter data: device=$medev, gcon=$gc ($gcunit), gfeedin=$gf ($gfunit) ,contotal=$gt ($ctunit), feedtotal=$ft ($ftunit)");
  
  my ($gco,$gfin);
  
  my $gcuf = $gcunit =~ /^kW$/xi ? 1000 : 1;
  my $gfuf = $gfunit =~ /^kW$/xi ? 1000 : 1;
    
  if ($gc ne "-gfeedin") {                                                                    # kein Spezialfall gcon bei neg. gfeedin
      $gco = ReadingsNum ($medev, $gc, 0) * $gcuf;                                            # aktueller Bezug (W)
  }
  else {                                                                                      # Spezialfall: bei negativen gfeedin -> $gco = abs($gf), $gf = 0
      $gfin = ReadingsNum ($medev, $gf, 0) * $gfuf;
      if($gfin <= 0) {
          $gco  = abs($gfin);
          $gfin = 0;
      }
      else {
          $gco = 0;
      }
  }
  
  if ($gf ne "-gcon") {                                                                       # kein Spezialfall gfeedin bei neg. gcon
      $gfin = ReadingsNum ($medev, $gf, 0) * $gfuf;                                           # aktuelle Einspeisung (W)
  }
  else {                                                                                      # Spezialfall: bei negativen gcon -> $gfin = abs($gco), $gco = 0
      $gco = ReadingsNum ($medev, $gc, 0) * $gcuf;                                            # aktueller Bezug (W)
      if($gco <= 0) {
          $gfin = abs($gco);
          $gco  = 0;
      }
      else {
          $gfin = 0;
      }
  }
  
  push @$daref, "Current_GridConsumption<>".(int $gco)." W";
  $data{$type}{$name}{current}{gridconsumption} = int $gco;                                   # Hilfshash Wert current grid consumption Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251  
  
  push @$daref, "Current_GridFeedIn<>".(int $gfin)." W";
  $data{$type}{$name}{current}{gridfeedin} = int $gfin;                                       # Hilfshash Wert current grid Feed in
  
  my $ctuf    = $ctunit =~ /^kWh$/xi ? 1000 : 1;
  my $gctotal = ReadingsNum ($medev, $gt, 0) * $ctuf;                                         # Bezug total (Wh)    

  my $ftuf    = $ftunit =~ /^kWh$/xi ? 1000 : 1;
  my $fitotal = ReadingsNum ($medev, $ft, 0) * $ftuf;                                         # Einspeisung total (Wh)   
   
  my $gcdaypast = 0;
  my $gfdaypast = 0;
  
  for my $hour (0..int $chour) {                                                                     # alle bisherigen Erzeugungen des Tages summieren                                            
      $gcdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridConsumption", 0);
      $gfdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridFeedIn",      0);
  }
  
  my $docon = 0;
  if ($gcdaypast == 0) {                                                                             # Management der Stundenberechnung auf Basis Totalwerte GridConsumtion
      if (defined $hash->{HELPER}{INITCONTOTAL}) {
          $docon = 1;
      }
      else {
          $hash->{HELPER}{INITCONTOTAL} = $gctotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITCONTOTAL}) {
      $hash->{HELPER}{INITCONTOTAL} = $gctotal-$gcdaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridConsumption", 0);
  }
  else {
      $docon = 1;
  }
  
  if ($docon) {
      my $gctotthishour = int ($gctotal - ($gcdaypast + $hash->{HELPER}{INITCONTOTAL}));
      
      if($gctotthishour < 0) {
          $gctotthishour = 0;
      }
      
      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_GridConsumption<>".$gctotthishour." Wh";
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{gcons} = $gctotthishour;                  # Hilfshash Wert Bezug (Wh) Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
      
      $paref->{gctotthishour} = $gctotthishour;
      $paref->{nhour}         = sprintf("%02d",$nhour);
      $paref->{histname}      = "cons";
      setPVhistory ($paref);
      delete $paref->{histname};
  }   
  
  my $dofeed = 0;
  if ($gfdaypast == 0) {                                                                              # Management der Stundenberechnung auf Basis Totalwerte GridFeedIn
      if (defined $hash->{HELPER}{INITFEEDTOTAL}) {
          $dofeed = 1;
      }
      else {
          $hash->{HELPER}{INITFEEDTOTAL} = $fitotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITFEEDTOTAL}) {
      $hash->{HELPER}{INITFEEDTOTAL} = $fitotal-$gfdaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridFeedIn", 0);
  }
  else {
      $dofeed = 1;
  }
  
  if ($dofeed) {
      my $gftotthishour = int ($fitotal - ($gfdaypast + $hash->{HELPER}{INITFEEDTOTAL}));
           
      if($gftotthishour < 0) {
          $gftotthishour = 0;
      }
      
      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_GridFeedIn<>".$gftotthishour." Wh";
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{gfeedin} = $gftotthishour;
      
      $paref->{gftotthishour} = $gftotthishour;
      $paref->{nhour}         = sprintf("%02d",$nhour);
      $paref->{histname}      = "gfeedin";
      setPVhistory ($paref);
      delete $paref->{histname};
  }
      
return;
}

################################################################
#                    Batteriewerte sammeln
################################################################
sub _transferBatteryValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $daref = $paref->{daref};  

  my $badev  = ReadingsVal($name, "currentBatteryDev", "");                                   # aktuelles Meter device für Batteriewerte
  my ($a,$h) = parseParams ($badev);
  $badev     = $a->[0] // "";
  return if(!$badev || !$defs{$badev});
  
  my $type = $hash->{TYPE}; 
  
  my ($pin,$piunit) = split ":", $h->{pin};                                                    # Readingname/Unit für aktuelle Batterieladung
  my ($pou,$pounit) = split ":", $h->{pout};                                                   # Readingname/Unit für aktuelle Batterieentladung
  
  return if(!$pin || !$pou);
  
  $pounit //= $piunit;
  $piunit //= $pounit;
  
  Log3($name, 5, "$name - collect Battery data: device=$badev, pin=$pin ($piunit), pout=$pou ($pounit)");
  
  my ($pbi,$pbo);
  
  my $piuf = $piunit =~ /^kW$/xi ? 1000 : 1;
  my $pouf = $pounit =~ /^kW$/xi ? 1000 : 1;
  
  if ($pin ne "-pout") {                                                                       # kein Spezialfall pin bei neg. pout
      $pbi = ReadingsNum ($badev, $pin, 0) * $piuf;                                            # aktueller Batterieladung (W)
  }
  else {                                                                                       # Spezialfall: bei negativen pout -> $pbi = abs($pbo), $pbo = 0
      $pbo = ReadingsNum ($badev, $pou, 0) * $pouf;                                            # aktuelle Batterieentladung (W)
      if($pbo <= 0) {
          $pbi = abs($pbo);
          $pbo = 0;
      }
      else {
          $pbi = 0;
      }
  }
  
  if ($pou ne "-pin") {                                                                        # kein Spezialfall pout bei neg. pin
      $pbo = ReadingsNum ($badev, $pou, 0) * $pouf;                                            # aktuelle Batterieentladung (W)
  }
  else {                                                                                       # Spezialfall: bei negativen pin -> $pbo = abs($pbi), $pbi = 0
      $pbi = ReadingsNum ($badev, $pin, 0) * $piuf;                                            # aktueller Batterieladung (W)
      if($pbi <= 0) {
          $pbo = abs($pbi);
          $pbi = 0;
      }
      else {
          $pbo = 0;
      }
  }
  
  push @$daref, "Current_PowerBatIn<>".(int $pbi)." W";
  $data{$type}{$name}{current}{powerbatin} = int $pbi;                                        # Hilfshash Wert aktuelle Batterieladung
  
  push @$daref, "Current_PowerBatOut<>".(int $pbo)." W";
  $data{$type}{$name}{current}{powerbatout} = int $pbo;                                       # Hilfshash Wert aktuelle Batterieentladung
        
return;
}

################################################################
#     Schwellenwerte auswerten und signalisieren
################################################################
sub _evaluateThresholds {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $daref = $paref->{daref};
   
  my $pt    = ReadingsVal($name, "powerTrigger", "");
  my $eh4t  = ReadingsVal($name, "energyH4Trigger", "");
  
  if ($pt) {  
      my $aaref = CurrentVal ($hash, "genslidereg", ""); 
      my @aa    = ();
      @aa       = @{$aaref} if (ref $aaref eq "ARRAY");
      
      if (scalar @aa >= $defslidenum) {  
          $paref->{taref}  = \@aa;
          $paref->{tname}  = "powerTrigger";
          $paref->{tholds} = $pt;
          
          __evaluateArray ($paref);
      }
  }
  
  if ($eh4t) {  
      my $aaref = CurrentVal ($hash, "h4fcslidereg", ""); 
      my @aa    = ();
      @aa       = @{$aaref} if (ref $aaref eq "ARRAY");
      
      if (scalar @aa >= $defslidenum) {    
          $paref->{taref}  = \@aa;
          $paref->{tname}  = "energyH4Trigger";
          $paref->{tholds} = $eh4t;
          
          __evaluateArray ($paref);
      }
  }
  
  delete $paref->{taref};
  delete $paref->{tname};
  delete $paref->{tholds};
  
return;
}

################################################################
#     Threshold-Array auswerten und Readings vorbereiten
################################################################
sub __evaluateArray {
  my $paref  = shift;
  my $name   = $paref->{name};
  my $daref  = $paref->{daref};
  my $taref  = $paref->{taref};          # Referenz zum Threshold-Array
  my $tname  = $paref->{tname};          # Thresholdname, z.B. powerTrigger
  my $tholds = $paref->{tholds};         # Triggervorgaben, z.B. aus Reading powerTrigger
      
  my $gen1   = @$taref[0];
  my $gen2   = @$taref[1];
  my $gen3   = @$taref[2];
  
  my ($a,$h) = parseParams ($tholds);
  
  for my $key (keys %{$h}) {
      my ($knum,$cond) = $key =~ /^([0-9]+)(on|off)$/x;
      
      if($cond eq "on" && $gen1 > $h->{$key}) {
          next if($gen2 < $h->{$key});
          next if($gen3 < $h->{$key});             
          push @$daref, "${tname}_${knum}<>on"  if(ReadingsVal($name, "${tname}_${knum}", "off") eq "off");
      }
      
      if($cond eq "off" && $gen1 < $h->{$key}) {
          next if($gen2 > $h->{$key});
          next if($gen3 > $h->{$key});
          push @$daref, "${tname}_${knum}<>off" if(ReadingsVal($name, "${tname}_${knum}", "on") eq "on");
      }
  }
  
return;
}

################################################################
#               Zusammenfassungen erstellen
################################################################
sub _calcSummaries {  
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $daref  = $paref->{daref};
  my $chour  = $paref->{chour};                                                                       # aktuelle Stunde
  my $minute = $paref->{minute};                                                                      # aktuelle Minute
  
  my $type   = $hash->{TYPE};
  $minute    = (int $minute) + 1;                                                                     # Minute Range umsetzen auf 1 bis 60

  my $next1HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $next2HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $next3HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $next4HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $restOfDaySum  = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $tomorrowSum   = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $todaySum      = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  
  my $rdh              = 24 - $chour - 1;                                                             # verbleibende Anzahl Stunden am Tag beginnend mit 00 (abzüglich aktuelle Stunde)
  my $remainminutes    = 60 - $minute;                                                                # verbleibende Minuten der aktuellen Stunde
  
  my $restofhour       = (NexthoursVal($hash, "NextHour00", "pvforecast", 0)) / 60 * $remainminutes;
  
  $next1HoursSum->{PV} = $restofhour;
  $next2HoursSum->{PV} = $restofhour;
  $next3HoursSum->{PV} = $restofhour;
  $next4HoursSum->{PV} = $restofhour;
  $restOfDaySum->{PV}  = $restofhour;
  
  for my $h (1..47) {
      my $pvfc = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), "pvforecast", 0);
         
      if($h == 1) {
          $next1HoursSum->{PV} += $pvfc / 60 * $minute;
      }
      
      if($h <= 2) {
          $next2HoursSum->{PV} += $pvfc                if($h <  2);
          $next2HoursSum->{PV} += $pvfc / 60 * $minute if($h == 2); 
      }
      
      if($h <= 3) {
          $next3HoursSum->{PV} += $pvfc                if($h <  3);
          $next3HoursSum->{PV} += $pvfc / 60 * $minute if($h == 3); 
      }  

      if($h <= 4) {
          $next4HoursSum->{PV} += $pvfc                if($h <  4);
          $next4HoursSum->{PV} += $pvfc / 60 * $minute if($h == 4); 
      }      
      
      $restOfDaySum->{PV}  += $pvfc if($h <= $rdh);
      $tomorrowSum->{PV}   += $pvfc if($h >  $rdh);
  }
  
  for my $th (1..24) {
      $todaySum->{PV}      += ReadingsNum($name, "Today_Hour".sprintf("%02d",$th)."_PVforecast", 0);
  }
  
  push @{$data{$type}{$name}{current}{h4fcslidereg}}, int $next4HoursSum->{PV};                         # Schieberegister 4h Summe Forecast
  limitArray ($data{$type}{$name}{current}{h4fcslidereg}, $defslidenum);
  
  my $gcon    = CurrentVal ($hash, "gridconsumption", 0);                                               # Berechnung aktueller Verbrauch
  my $pvgen   = CurrentVal ($hash, "generation",      0);
  my $gfeedin = CurrentVal ($hash, "gridfeedin",      0);
  my $batin   = CurrentVal ($hash, "powerbatin",      0);                                               # aktuelle Batterieladung
  my $batout  = CurrentVal ($hash, "powerbatout",     0);                                               # aktuelle Batterieentladung
  
  my $consumption                           = $pvgen - $gfeedin + $gcon - $batin + $batout;
  $data{$type}{$name}{current}{consumption} = $consumption;
  
  push @$daref, "Current_Consumption<>".       $consumption.              " W";
  push @$daref, "NextHours_Sum01_PVforecast<>".(int $next1HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum02_PVforecast<>".(int $next2HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum03_PVforecast<>".(int $next3HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum04_PVforecast<>".(int $next4HoursSum->{PV})." Wh";
  push @$daref, "RestOfDayPVforecast<>".       (int $restOfDaySum->{PV}). " Wh";
  push @$daref, "Tomorrow_PVforecast<>".       (int $tomorrowSum->{PV}).  " Wh";
  push @$daref, "Today_PVforecast<>".          (int $todaySum->{PV}).     " Wh";
  
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
  { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }       ## no critic 'Map blocks'
  
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
sub forecastGraphic {                                                                     ## no critic 'complexity'
  my $name = shift;
  my $ftui = shift // "";
  
  my $hash = $defs{$name};
  my $ret  = "";
  
  my ($val,$height);
  my ($z2,$z3,$z4);
  my $he;                                                                                  # Balkenhöhe

  my $hfcg = $data{$hash->{TYPE}}{$name}{html};                                            #(hfcg = hash forecast graphic)

  ##########################################################
  # Kontext des SolarForecast-Devices speichern für Refresh
  $hash->{HELPER}{SPGDEV}    = $name;                                                      # Name des aufrufenden SMAPortalSPG-Devices
  $hash->{HELPER}{SPGROOM}   = $FW_room   ? $FW_room   : "";                               # Raum aus dem das SMAPortalSPG-Device die Funktion aufrief
  $hash->{HELPER}{SPGDETAIL} = $FW_detail ? $FW_detail : "";                               # Name des SMAPortalSPG-Devices (wenn Detailansicht)
  
  my $fcdev  = ReadingsVal ($name, "currentForecastDev", "");                              # aktuelles Forecast Device  
  my $indev  = ReadingsVal ($name, "currentInverterDev", "");                              # aktuelles Inverter Device
  my ($a,$h) = parseParams ($indev);
  $indev     = $a->[0] // "";

  my $pv0    = NexthoursVal ($hash, "NextHour00", "pvforecast", undef);
  my $is     = ReadingsVal  ($name, "inverterStrings",  undef);                            # String Konfig
  my $peak   = ReadingsVal  ($name, "modulePeakString", undef);                            # String Peak
  my $dir    = ReadingsVal  ($name, "moduleDirection",  undef);                            # Modulausrichtung Konfig
  my $ta     = ReadingsVal  ($name, "moduleTiltAngle",  undef);                            # Modul Neigungswinkel Konfig
  
  if(!$is || !$fcdev || !$indev || !$peak || !defined $pv0 || !$dir || !$ta) {
      my $link = qq{<a href="/fhem?detail=$name">$name</a>};  
      $height  = AttrNum($name, 'beamHeight', 200);   
      $ret    .= "<table class='roomoverview'>";
      $ret    .= "<tr style='height:".$height."px'>";
      $ret    .= "<td>";
      
      if(!$fcdev) {                                                                        ## no critic 'Cascading'
          $ret .= qq{Please select a Solar Forecast device with "set $link currentForecastDev"};
      }
      elsif(!$indev) {
          $ret .= qq{Please select an Inverter device with "set $link currentInverterDev"};   
      }
      elsif(!$is) {
          $ret .= qq{Please define all of your used string names with "set $link inverterStrings".};
      }
      elsif(!$peak) {
          $ret .= qq{Please specify the total peak power for every string with "set $link modulePeakString"};   
      }
      elsif(!$dir) {
          $ret .= qq{Please specify the module  direction with "set $link moduleDirection"};   
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
  my $offset     =  AttrNum ($name, 'historyHour',            0   );

  my $hourstyle  =  AttrVal ($name, 'hourStyle',              ''  );

  my $colorfc    =  AttrVal ($name, 'beam1Color',         '000000');
  my $colorc     =  AttrVal ($name, 'beam2Color',         'C4C4A7');
  my $fcolor1    =  AttrVal ($name, 'beam1FontColor',     'C4C4A7');
  my $fcolor2    =  AttrVal ($name, 'beam2FontColor',     '000000');
             
  my $beam1cont  =  AttrVal ($name, 'beam1Content',     'forecast');
  my $beam2cont  =  AttrVal ($name, 'beam2Content',     'forecast'); 

  my $icon       =  AttrVal ($name, 'consumerAdviceIcon', undef   );
  my $html_start =  AttrVal ($name, 'htmlStart',          undef   );                      # beliebige HTML Strings die vor der Grafik ausgegeben werden
  my $html_end   =  AttrVal ($name, 'htmlEnd',            undef   );                      # beliebige HTML Strings die nach der Grafik ausgegeben werden

  my $lotype     =  AttrVal ($name, 'layoutType',       'single'  );
  my $kw         =  AttrVal ($name, 'Wh/kWh',              'Wh'   );

  $height        =  AttrNum ($name, 'beamHeight',           200   );
  my $width      =  AttrNum ($name, 'beamWidth',              6   );                      # zu klein ist nicht problematisch
  my $w          =  $width*$maxhours;                                                     # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  my $fsize      =  AttrNum ($name, 'spaceSize',             24   );
  my $maxVal     =  AttrNum ($name, 'maxValBeam',             0   );                      # dyn. Anpassung der Balkenhöhe oder statisch ?

  my $show_night =  AttrNum ($name, 'showNight',              0   );                      # alle Balken (Spalten) anzeigen ?
  my $show_diff  =  AttrVal ($name, 'showDiff',            'no'   );                      # zusätzliche Anzeige $di{} in allen Typen
  my $weather    =  AttrNum ($name, 'showWeather',            1   );
  my $colorw     =  AttrVal ($name, 'weatherColor',    'FFFFFF'   );                      # Wetter Icon Farbe
  my $colorwn    =  AttrVal ($name, 'weatherColorNight',  $colorw );                      # Wetter Icon Farbe Nacht

  my $wlalias    =  AttrVal ($name, 'alias',              $name   );
  my $header     =  AttrNum ($name, 'showHeader',             1   ); 
  my $hdrAlign   =  AttrVal ($name, 'headerAlignment', 'center'   );                      # ermöglicht per attr die Ausrichtung der Tabelle zu setzen
  my $hdrDetail  =  AttrVal ($name, 'headerDetail',       'all'   );                      # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten

  # Icon Erstellung, mit @<Farbe> ergänzen falls einfärben
  # Beispiel mit Farbe:  $icon = FW_makeImage('light_light_dim_100.svg@green');
 
  $icon    = FW_makeImage($icon) if (defined($icon));
  my $co4h = ReadingsNum ($name,"Next04Hours_Consumption",    0);
  my $coRe = ReadingsNum ($name,"RestOfDay_Consumption",      0); 
  my $coTo = ReadingsNum ($name,"Tomorrow_Consumption",       0);
  my $coCu = ReadingsNum ($name,"Current_Consumption",        0);

  my $pv4h = ReadingsNum ($name,"NextHours_Sum04_PVforecast", 0);
  my $pvRe = ReadingsNum ($name,"RestOfDayPVforecast",        0); 
  my $pvTo = ReadingsNum ($name,"Tomorrow_PVforecast",        0);
  my $pvCu = ReadingsNum ($name,"Current_PV",                 0);
  
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
      my $lang    = AttrVal ("global", "language", "EN"  );
      my $alias   = AttrVal ($name,    "alias",    $name );                                         # Linktext als Aliasname
      
      my $dlink   = "<a href=\"/fhem?detail=$name\">$alias</a>";      
      my $lup     = ReadingsTimestamp($name, ".lastupdateForecastValues", "0000-00-00 00:00:00");   # letzter Forecast Update

      my $lupt    = "last update:";
      my $autoct  = "automatic correction:";  
      my $lblPv4h = "next&nbsp;4h:";
      my $lblPvRe = "remain today:";
      my $lblPvTo = "tomorrow:";
      my $lblPvCu = "actual";
     
      if($lang eq "DE") {                                                                           # Header globales Sprachschema Deutsch
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
          
          $lup = "$year-$month-$day&nbsp;$time";
          if($lang eq "DE") {
             $lup = "$day.$month.$year&nbsp;$time"; 
          }

          my $cmdupdate = "\"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=get $name data')\"";               # Update Button generieren        

          if ($ftui eq "ftui") {
              $cmdupdate = "\"ftui.setFhemStatus('get $name data')\"";     
          }

          my $upstate  = ReadingsVal($name, "state", "");

          ## Update-Icon
          ##############
          my $upicon;
          if ($upstate =~ /updated|successfully/ix) {
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
  my $month;
  my $year;
  my $day_str;
  my $day;

  my $t = NexthoursVal ($hash, "NextHour00", "starttime", AttrVal('global', 'language', '') eq 'DE' ? '00.00.0000 24' : '0000-00-00 24');
  ($year,$month,$day_str,$thishour) = $t =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
  ($day_str,$month,$year,$thishour) = $t =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x if (AttrVal('global', 'language', '') eq 'DE');

  $thishour++;
  
  $hfcg->{0}{time_str} = $thishour;
  $thishour            = int($thishour);                                                              # keine führende Null

  $hfcg->{0}{time}     = $thishour;
  $hfcg->{0}{day_str}  = $day_str;
  $day                 = int($day_str);
  $hfcg->{0}{day}      = $day;
  $hfcg->{0}{mktime}   = fhemTimeLocal(0,0,$thishour,$day,int($month),$year);                         # gleich die Unix Zeit dazu holen

  my $val1 = 0;
  my $val2 = 0;
  my $val3 = 0;
  my $val4 = 0;

  if ($offset) {
      $hfcg->{0}{time} += $offset;

      if ($hfcg->{0}{time} < 0) {
          $hfcg->{0}{time} += 24;
          my $n_day    = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * abs($offset)));       # Achtung : Tageswechsel - day muss jetzt neu berechnet werden !
          $hfcg->{0}{day}     = int($n_day);
          $hfcg->{0}{day_str} = $n_day;
      }

      $hfcg->{0}{time_str} = sprintf('%02d', $hfcg->{0}{time});
      
      $val1 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "pvfc",  0);
      $val2 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "pvrl",  0);
      $val3 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "gcons", 0);

      # $hfcg->{0}{weather} = CircularVal ($hash, $hfcg->{0}{time_str}, "weatherid", undef);
      $hfcg->{0}{weather} = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "weatherid", undef);
  }
  else {
      $val1  = CircularVal ($hash, $hfcg->{0}{time_str}, "pvfc",  0);
      $val2  = CircularVal ($hash, $hfcg->{0}{time_str}, "pvrl",  0);
      $val3  = CircularVal ($hash, $hfcg->{0}{time_str}, "gcons", 0);

      $hfcg->{0}{weather} = CircularVal ($hash, $hfcg->{0}{time_str}, "weatherid", undef);
      #$val4   = (ReadingsVal($name,"ThisHour_IsConsumptionRecommended",'no') eq 'yes' ) ? $icon : undef;
  }

  $hfcg->{0}{time_str} = sprintf('%02d', $hfcg->{0}{time}-1).$hourstyle;
  $hfcg->{0}{beam1}    = ($beam1cont eq 'forecast') ? $val1 : ($beam1cont eq 'real') ? $val2 : ($beam1cont eq 'gridconsumption') ? $val3 : $val4;
  $hfcg->{0}{beam2}    = ($beam2cont eq 'forecast') ? $val1 : ($beam2cont eq 'real') ? $val2 : ($beam2cont eq 'gridconsumption') ? $val3 : $val4;
  $hfcg->{0}{diff}     = $hfcg->{0}{beam1} - $hfcg->{0}{beam2};

  $lotype = 'single' if ($beam1cont eq $beam2cont);                                              # User Auswahl überschreiben wenn beide Werte die gleiche Basis haben !

  ###########################################################
  # get consumer list and display it in portalGraphics
  ###########################################################  
  for (@pgCDev) {
      my ($itemName, undef) = split(':',$_);
      $itemName =~ s/^\s+|\s+$//gx;                                                              # trim it, if blanks were used
      $_        =~ s/^\s+|\s+$//gx;                                                              # trim it, if blanks were used
    
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
          if ($start < $hfcg->{0}{time}) {                                                       # gridconsumption seems to be tomorrow
              $start = 24-$hfcg->{0}{time}+$start;
              $flag  = 1;
          } 
          else { 
              $start -= $hfcg->{0}{time};          
          }

          if ($flag) {                                                                           # gridconsumption seems to be tomorrow
              $end = 24-$hfcg->{0}{time}+$end;
          } 
          else { 
              $end -= $hfcg->{0}{time}; 
          }

          $_ .= ":".$start.":".$end;
      } 
      else { 
          $_ .= ":24:24"; 
      } 
      Log3($name, 4, "$name - Consumer planned data: $_");
  }

  $maxVal    = !$maxVal ? $hfcg->{0}{beam1} : $maxVal;                                                  # Startwert wenn kein Wert bereits via attr vorgegeben ist

  my $maxCon = $hfcg->{0}{beam1};                                                                       
  my $maxDif = $hfcg->{0}{diff};                                                                        # für Typ diff
  my $minDif = $hfcg->{0}{diff};                                                                        # für Typ diff

  for my $i (1..($maxhours*2)-1) {                                                                      # doppelte Anzahl berechnen    my $val1 = 0;
      $val2 = 0;
      $val3 = 0;
      $val4 = 0;

      $hfcg->{$i}{time}  = $hfcg->{0}{time} + $i;

      while ($hfcg->{$i}{time} > 24) {
          $hfcg->{$i}{time} -= 24;                                                                      # wird bis zu 2x durchlaufen
      }

      $hfcg->{$i}{time_str} = sprintf('%02d', $hfcg->{$i}{time});

      my $nh;                                                                                           # next hour

      if ($offset < 0) {
          if ($i <= abs($offset)) {                                                                     # $daystr stimmt nur nach Mitternacht, vor Mitternacht muß $hfcg->{0}{day_str} als Basis verwendet werden !
              my $ds = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * (abs($offset)-$i)));
              
              # Sonderfall Mitternacht
              $ds   = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * (abs($offset)-$i+1))) if ($hfcg->{$i}{time} == 24);
              
              $val1 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "pvfc",  0);
              $val2 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "pvrl",  0); 
              $val3 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "gcons", 0);
              $hfcg->{$i}{weather} = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "weatherid", undef);
          }
          else {
              $nh  = sprintf('%02d', $i+$offset);
          }
      }
      else {
          $nh = sprintf('%02d', $i);
      }

      if (defined($nh)) {
          $val1                = NexthoursVal ($hash, 'NextHour'.$nh, "pvforecast",    0);
          $hfcg->{$i}{weather} = NexthoursVal ($hash, 'NextHour'.$nh, "weatherid", undef);
          #$val4   = (ReadingsVal($name,"NextHour".$ii."_IsConsumptionRecommended",'no') eq 'yes') ? $icon : undef;
      }

      $hfcg->{$i}{time_str} = sprintf('%02d', $hfcg->{$i}{time}-1).$hourstyle;

      $hfcg->{$i}{beam1} = ($beam1cont eq 'forecast') ? $val1 : ($beam1cont eq 'real') ? $val2 : ($beam1cont eq 'gridconsumption') ? $val3 : $val4;
      $hfcg->{$i}{beam2} = ($beam2cont eq 'forecast') ? $val1 : ($beam2cont eq 'real') ? $val2 : ($beam2cont eq 'gridconsumption') ? $val3 : $val4;

      # sicher stellen das wir keine undefs in der Liste haben !
      $hfcg->{$i}{beam1} //= 0;
      $hfcg->{$i}{beam2} //= 0;
      $hfcg->{$i}{diff}    = $hfcg->{$i}{beam1} - $hfcg->{$i}{beam2};

      $maxVal = $hfcg->{$i}{beam1} if ($hfcg->{$i}{beam1} > $maxVal); 
      $maxCon = $hfcg->{$i}{beam2} if ($hfcg->{$i}{beam2} > $maxCon);
      $maxDif = $hfcg->{$i}{diff}  if ($hfcg->{$i}{diff} > $maxDif);
      $minDif = $hfcg->{$i}{diff}  if ($hfcg->{$i}{diff} < $minDif);
  }

  #Log3($hash,3,Dumper($hfcg));
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
      $ret .= "<tr class='even'><td class='smaportal'></td>";                                               # freier Platz am Anfang

      my $ii;
      for my $i (0..($maxhours*2)-1) {

          last if (!exists($hfcg->{$i}{weather}));
          next if (!$show_night  && defined($hfcg->{$i}{weather}) && ($hfcg->{$i}{weather} > 99) && !$hfcg->{$i}{beam1} && !$hfcg->{$i}{beam2});
          # Lässt Nachticons aber noch durch wenn es einen Wert gibt , ToDo : klären ob die Nacht richtig gesetzt wurde
          $ii++;                                                                                            # wieviele Stunden Icons haben wir bisher beechnet  ?
          last if ($ii > $maxhours);

          # ToDo : weather_icon sollte im Fehlerfall Title mit der ID besetzen um in FHEMWEB sofort die ID sehen zu können
          if (exists($hfcg->{$i}{weather}) && defined($hfcg->{$i}{weather})) {
              my ($icon_name, $title) = $hfcg->{$i}{weather} > 100 ? weather_icon($hfcg->{$i}{weather}-100) : weather_icon($hfcg->{$i}{weather});
              Log3($name, 4, "$name - unknown weather id: ".$hfcg->{$i}{weather}.", please inform the maintainer") if($icon_name eq 'unknown');

              $icon_name .= ($hfcg->{$i}{weather} < 100 ) ? '@'.$colorw  : '@'.$colorwn;
              $val        = FW_makeImage($icon_name);

              if ($val eq $icon_name) {                                                          # passendes Icon beim User nicht vorhanden ! ( attr web iconPath falsch/prüfen/update ? )
                  $val  ='<b>???<b/>';                                                       
                  Log3($name, 3, qq{$name - the icon $hfcg->{$i}{weather} not found. Please check attribute "iconPath" of your FHEMWEB instance and/or update your FHEM software});
              }

              $ret .= "<td title='$title' class='smaportal' width='$width' style='margin:1px; vertical-align:middle align:center; padding-bottom:1px;'>$val</td>";   # title -> Mouse Over Text
              # mit $hfcg->{$i}{weather} = undef kann man unten leicht feststellen ob für diese Spalte bereits ein Icon ausgegeben wurde oder nicht
          } 
          else { 
              $ret .= "<td></td>";  
              $hfcg->{$i}{weather} = undef;                                                  # ToDo : prüfen ob noch nötig
          }
      }

      $ret .= "<td class='smaportal'></td></tr>";                                            # freier Platz am Ende der Icon Zeile
  }

  if($show_diff eq 'top') {                                                                  # Zusätzliche Zeile Ertrag - Verbrauch
      $ret .= "<tr class='even'><td class='smaportal'></td>";                                # freier Platz am Anfang
      my $ii;
      for my $i (0..($maxhours*2)-1) {
          # gleiche Bedingung wie oben
          next if (!$show_night  && ($hfcg->{$i}{weather} > 99) && !$hfcg->{$i}{beam1} && !$hfcg->{$i}{beam2});
          $ii++; # wieviele Stunden haben wir bisher angezeigt ?
          last if ($ii > $maxhours); # vorzeitiger Abbruch

          $val  = formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather});
          $val  = ($hfcg->{$i}{diff} < 0) ?  '<b>'.$val.'<b/>' : ($val>0) ? '+'.$val : $val; # negative Zahlen in Fettschrift, 0 aber ohne +
          $ret .= "<td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td>"; 
      }
      $ret .= "<td class='smaportal'></td></tr>"; # freier Platz am Ende 
  }

  $ret .= "<tr class='even'><td class='smaportal'></td>";                                    # Neue Zeile mit freiem Platz am Anfang

  my $ii = 0;
  for my $i (0..($maxhours*2)-1) {
      # gleiche Bedingung wie oben
      next if (!$show_night  && defined($hfcg->{$i}{weather}) && ($hfcg->{$i}{weather} > 99) && !$hfcg->{$i}{beam1} && !$hfcg->{$i}{beam2});
      $ii++;
      last if ($ii > $maxhours);

      # Achtung Falle, Division by Zero möglich, 
      # maxVal kann gerade bei kleineren maxhours Ausgaben in der Nacht leicht auf 0 fallen  
      $height = 200 if (!$height);                                                           # Fallback, sollte eigentlich nicht vorkommen, außer der User setzt es auf 0
      $maxVal = 1   if (!int $maxVal);
      $maxCon = 1   if (!$maxCon);

      # Der zusätzliche Offset durch $fsize verhindert bei den meisten Skins 
      # dass die Grundlinie der Balken nach unten durchbrochen wird

      if ($lotype eq 'single') {
          $he = int(($maxVal-$hfcg->{$i}{beam1}) / $maxVal*$height) + $fsize;
          $z3 = int($height + $fsize - $he);
      } 

      if ($lotype eq 'double') {
          # Berechnung der Zonen
          # he - freier der Raum über den Balken. fsize wird nicht verwendet, da bei diesem Typ keine Zahlen über den Balken stehen 
          # z2 - der Ertrag ggf mit Icon
          # z3 - der Verbrauch , bei zu kleinem Wert wird der Platz komplett Zone 2 zugeschlagen und nicht angezeigt
          # z2 und z3 nach Bedarf tauschen, wenn der Verbrauch größer als der Ertrag ist

          $maxVal = $maxCon if ($maxCon > $maxVal);                                         # wer hat den größten Wert ?

          if ($hfcg->{$i}{beam1} > $hfcg->{$i}{beam2}) {                                    # Beam1 oben , Beam2 unten
              $z2 = $hfcg->{$i}{beam1}; $z3 = $hfcg->{$i}{beam2}; 
          } 
          else {                                                                            # tauschen, Verbrauch ist größer als Ertrag
              $z3 = $hfcg->{$i}{beam1}; $z2 = $hfcg->{$i}{beam2}; 
          }

          $he = int(($maxVal-$z2)/$maxVal*$height);
          $z2 = int(($z2 - $z3)/$maxVal*$height);

          $z3 = int($height - $he - $z2);                                                   # was von maxVal noch übrig ist
              
          if ($z3 < int($fsize/2)) {                                                        # dünnen Strichbalken vermeiden / ca. halbe Zeichenhöhe
              $z2 += $z3; $z3 = 0; 
          }
      }

      if ($lotype eq 'diff') {                                                              # Typ diff
          # Berechnung der Zonen
          # he - freier der Raum über den Balken , Zahl positiver Wert + fsize
          # z2 - positiver Balken inkl Icon
          # z3 - negativer Balken
          # z4 - Zahl negativer Wert + fsize

          my ($px_pos,$px_neg);
          my $maxValBeam = 0;                                                               # ToDo:  maxValBeam noch aus Attribut maxValBeam ableiten

          if ($maxValBeam) {                                                                # Feste Aufteilung +/- , jeder 50 % bei maxValBeam = 0
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

          if ($hfcg->{$i}{diff} >= 0) {                                                   # Zone 2 & 3 mit ihren direkten Werten vorbesetzen
              $z2 = $hfcg->{$i}{diff};
              $z3 = abs($minDif);
          } 
          else {
              $z2 = $maxDif;
              $z3 = abs($hfcg->{$i}{diff});                                               # Nur Betrag ohne Vorzeichen
          }
     
          # Alle vorbesetzen Werte umrechnen auf echte Ausgabe px
          $he = (!$px_pos || !$maxDif) ? 0 : int(($maxDif-$z2)/$maxDif*$px_pos);                        # Teilung durch 0 vermeiden
          $z2 = ($px_pos - $he) ;

          $z4 = (!$px_neg || !$minDif) ? 0 : int((abs($minDif)-$z3)/abs($minDif)*$px_neg);              # Teilung durch 0 unbedingt vermeiden
          $z3 = ($px_neg - $z4);

          # Beiden Zonen die Werte ausgeben könnten muß fsize als zusätzlicher Raum zugeschlagen werden !
          $he += $fsize; 
          $z4 += $fsize if ($z3);                                                                       # komplette Grafik ohne negativ Balken, keine Ausgabe von z3 & z4
      }
        
      # das style des nächsten TD bestimmt ganz wesentlich das gesammte Design
      # das \n erleichtert das lesen des Seitenquelltext beim debugging
      # vertical-align:bottom damit alle Balken und Ausgaben wirklich auf der gleichen Grundlinie sitzen

      $ret .="<td style='text-align: center; padding-left:1px; padding-right:1px; margin:0px; vertical-align:bottom; padding-top:0px'>\n";

      if ($lotype eq 'single') {
          $val = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});

          $ret .="<table width='100%' height='100%'>";                                                  # mit width=100% etwas bessere Füllung der Balken
          $ret .="<tr class='even' style='height:".$he."px'>";
          $ret .="<td class='smaportal' style='vertical-align:bottom; color:#$fcolor1;'>".$val.'</td></tr>';

          if ($hfcg->{$i}{beam1} || $show_night) {                                                      # Balken nur einfärben wenn der User via Attr eine Farbe vorgibt, sonst bestimmt class odd von TR alleine die Farbe
              my $style = "style=\"padding-bottom:0px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style   .= defined $colorfc ? " background-color:#$colorfc\"" : '"';                     # Syntaxhilight 

              $ret .= "<tr class='odd' style='height:".$z3."px;'>";
              $ret .= "<td align='center' class='smaportal' ".$style.">";
                      
              my $sicon = 1;                                                    
              #$ret .= $is{$i} if (defined ($is{$i}) && $sicon);

              ##################################
              # inject the new icon if defined
              #$ret .= consinject($hash,$i,@pgCDev) if($s);
                      
              $ret .= "</td></tr>";
          }
      }
    
      if ($lotype eq 'double') {
          my ($color1, $color2, $style1, $style2, $v);
          my $style =  "style='padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";

          $ret .="<table width='100%' height='100%'>\n";                                                         # mit width=100% etwas bessere Füllung der Balken

          # der Freiraum oben kann beim größten Balken ganz entfallen
          $ret .="<tr class='even' style='height:".$he."px'><td class='smaportal'></td></tr>" if ($he);

          if($hfcg->{$i}{beam1} > $hfcg->{$i}{beam2}) {                                                          # wer ist oben, Beam2 oder Beam1 ? Wert und Farbe für Zone 2 & 3 vorbesetzen
              $val     = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});
              $color1  = $colorfc;
              $style1  = $style." background-color:#$color1; color:#$fcolor1;'";

              if($z3) {                                                                                          # die Zuweisung können wir uns sparen wenn Zone 3 nachher eh nicht ausgegeben wird
                  $v       = formatVal6($hfcg->{$i}{beam2},$kw,$hfcg->{$i}{weather});
                  $color2  = $colorc;
                  $style2  = $style." background-color:#$color2; color:#$fcolor2;'";
              }
          }
          else {
              $val     = formatVal6($hfcg->{$i}{beam2},$kw,$hfcg->{$i}{weather});
              $color1  = $colorc;
              $style1  = $style." background-color:#$color1; color:#$fcolor2;'";
       
              if($z3) {
                  $v       = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});
                  $color2  = $colorfc;
                  $style2  = $style." background-color:#$color2; color:#$fcolor1;'";
              }
          }

          $ret .= "<tr class='odd' style='height:".$z2."px'>";
          $ret .= "<td align='center' class='smaportal' ".$style1.">$val";
             
          ##################################
          # inject the new icon if defined
          #$ret .= consinject($hash,$i,@pgCDev) if($s);
             
          $ret .= "</td></tr>";

          if ($z3) {                                                                                     # die Zone 3 lassen wir bei zu kleinen Werten auch ganz weg 
              $ret .= "<tr class='odd' style='height:".$z3."px'>";
              $ret .= "<td align='center' class='smaportal' ".$style2.">$v</td></tr>";
          }
      }

      if ($lotype eq 'diff') {                                                                          # Type diff
          my $style = "style='padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
          $ret .= "<table width='100%' border='0'>\n";                                                  # Tipp : das nachfolgende border=0 auf 1 setzen hilft sehr Ausgabefehler zu endecken

          $val = ($hfcg->{$i}{diff} > 0) ? formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather}) : '';
          $val = '&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;' if ($hfcg->{$i}{diff} == 0);                         # Sonderfall , hier wird die 0 gebraucht !

          if ($val) {
              $ret .= "<tr class='even' style='height:".$he."px'>";
              $ret .= "<td class='smaportal' style='vertical-align:bottom; color:#$fcolor1;'>".$val."</td></tr>";
          }

          if ($hfcg->{$i}{diff} >= 0) {                                                                 # mit Farbe 1 colorfc füllen
              $style .= " background-color:#$colorfc'";
              $z2     = 1 if ($hfcg->{$i}{diff} == 0);                                                  # Sonderfall , 1px dünnen Strich ausgeben
              $ret  .= "<tr class='odd' style='height:".$z2."px'>";
              $ret  .= "<td align='center' class='smaportal' ".$style.">";
              $ret  .= "</td></tr>";
          } 
          else {                                                                                        # ohne Farbe
              $z2 = 2 if ($hfcg->{$i}{diff} == 0);                                                      # Sonderfall, hier wird die 0 gebraucht !
              if ($z2 && $val) {                                                                        # z2 weglassen wenn nicht unbedigt nötig bzw. wenn zuvor he mit val keinen Wert hatte
                  $ret .= "<tr class='even' style='height:".$z2."px'>";
                  $ret .= "<td class='smaportal'></td></tr>";
              }
          }
        
          if ($hfcg->{$i}{diff} < 0) {                                                                  # Negativ Balken anzeigen ?
              $style .= " background-color:#$colorc'";                                                  # mit Farbe 2 colorc füllen
              $ret   .= "<tr class='odd' style='height:".$z3."px'>";
              $ret   .= "<td align='center' class='smaportal' ".$style."></td></tr>";
          }
          elsif ($z3) {                                                                                 # ohne Farbe
              $ret .= "<tr class='even' style='height:".$z3."px'>";
              $ret .= "<td class='smaportal'></td></tr>";
          }

          if($z4) {                                                                                     # kann entfallen wenn auch z3 0 ist
              $val  = ($hfcg->{$i}{diff} < 0) ? formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather}) : '&nbsp;';
              $ret .= "<tr class='even' style='height:".$z4."px'>";
              $ret .= "<td class='smaportal' style='vertical-align:top'>".$val."</td></tr>";
          }
      }

      if ($show_diff eq 'bottom') {                                                                     # zusätzliche diff Anzeige
          $val  = formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather});
          $val  = ($hfcg->{$i}{diff} < 0) ?  '<b>'.$val.'<b/>' : ($val > 0 ) ? '+'.$val : $val if ($val ne '&nbsp;'); # negative Zahlen in Fettschrift, 0 aber ohne +
          $ret .= "<tr class='even'><td class='smaportal' style='vertical-align:middle; text-align:center;'>$val</td></tr>"; 
      }

      $ret .= "<tr class='even'><td class='smaportal' style='vertical-align:bottom; text-align:center;'>";
      $ret .= (($hfcg->{$i}{time} == $thishour) && ($offset < 0)) ? '<a class="changed" style="visibility:visible"><span>'.$hfcg->{$i}{time_str}.'</span></a>' : $hfcg->{$i}{time_str};
      $thishour = 99 if ($hfcg->{$i}{time} == $thishour);                                               # nur einmal verwenden !
      $ret .="</td></tr></table></td>";                                                   
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

  $id      = int $id;
  my $lang = AttrVal ("global", "language", "EN");
  
  my $txt  = $lang eq "DE" ? "txtd" : "txte";
  
  if(defined $weather_ids{$id}) {
      return $weather_ids{$id}{icon}, encode("utf8", $weather_ids{$id}{$txt});
  }
  
return 'unknown','';
}

################################################################
#                   Timestamp berechnen
################################################################
sub TimeAdjust {
  my $epoch = shift;
  
  my ($lyear,$lmonth,$lday,$lhour) = (localtime($epoch))[5,4,3,2];
  my $ts;
  
  $lyear += 1900;                                                                             # year is 1900 based
  $lmonth++;                                                                                  # month number is zero based
  
  my ($sec,$min,$hour,$day,$mon,$year) = (localtime(time))[0,1,2,3,4,5];                      # Standard f. z.B. Readingstimstamp
  $year += 1900;                                                                            
  $mon++;  
  my $realts = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year,$mon,$day,$hour,$min,$sec);          
  
  if(AttrVal("global","language","EN") eq "DE") {
      $ts = sprintf("%02d.%02d.%04d %02d:%s", $lday,$lmonth,$lyear,$lhour,"00:00");
  } 
  else {
      $ts = sprintf("%04d-%02d-%02d %02d:%s", $lyear,$lmonth,$lday,$lhour,"00:00");
  }
  
return ($ts,$realts);
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
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $rad   = $paref->{rad};               # Nominale Strahlung aus DWD Device
  my $num   = $paref->{num};               # Nexthour 
  my $uac   = $paref->{uac};               # Nutze Autokorrektur (on/off)
  my $t     = $paref->{t};                 # aktueller Unix Timestamp
  my $fh    = $paref->{fh};
  my $fd    = $paref->{fd};
  
  my $type  = $hash->{TYPE};
  my $stch  = $data{$type}{$name}{strings};                                                           # String Configuration Hash
  my $pr    = 1.0;                                                                                    # Performance Ratio (PR)
  
  my $chour      = strftime "%H", localtime($t+($num*3600));                                          # aktuelle Stunde
  my $reld       = $fd == 0 ? "today" : $fd == 1 ? "tomorrow" : "unknown";
  
  my $pvcorr     = ReadingsNum ($name, "pvCorrectionFactor_".sprintf("%02d",$fh+1), 1);               # PV Korrekturfaktor (auto oder manuell)
  my $hc         = $pvcorr;                                                                           # Voreinstellung RAW-Korrekturfaktor 
  my $hcfound    = "use manual correction factor";
  
  my $clouddamp  = AttrVal($name, "cloudFactorDamping", $cldampdef);                                  # prozentuale Berücksichtigung des Bewölkungskorrekturfaktors
  my $raindamp   = AttrVal($name, "rainFactorDamping", $rdampdef);                                    # prozentuale Berücksichtigung des Regenkorrekturfaktors
  my @strings    = sort keys %{$stch};
  
  my $cloudcover = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "cloudcover", 0);            # effektive Wolkendecke nächste Stunde X
  my $ccf        = 1 - ((($cloudcover - $cloud_base)/100) * $clouddamp/100);                          # Cloud Correction Faktor mit Steilheit und Fußpunkt
  my $range      = int ($cloudcover/10);                                                              # Range errechnen
  
  my $rainprob   = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "rainprob", 0);              # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
  my $rcf        = 1 - ((($rainprob - $rain_base)/100) * $raindamp/100);                              # Rain Correction Faktor mit Steilheit

  ## Ermitteln des relevanten Autokorrekturfaktors
  if ($uac eq "on") {                                                                                 # Autokorrektur soll genutzt werden
      $hcfound = "yes";                                                                               # Status ob Autokorrekturfaktor im Wertevorrat gefunden wurde         
      $hc      = CircularAutokorrVal ($hash, sprintf("%02d",$fh+1), $range, undef);                   # Korrekturfaktor der Stunde des Tages der entsprechenden Bewölkungsrange
      if (!defined $hc) {
          $hcfound = "no - use raw correction factor";
          $hc      = $pvcorr;                                                                         # nutze RAW-Korrekturfaktor  
      }
  } 

  my $pvsum  = 0;  
  
  for my $st (@strings) {                                                                             # für jeden String der Config ..
      my $peak   = $stch->{"$st"}{peak};                                                              # String Peak (kWp)
      my $ta     = $stch->{"$st"}{tilt};                                                              # Neigungswinkel Solarmodule
      my $moddir = $stch->{"$st"}{dir};                                                               # Ausrichtung der Solarmodule
      
      my $af     = $hff{$ta}{$moddir} / 100;                                                          # Flächenfaktor: http://www.ing-büro-junge.de/html/photovoltaik.html
      
      my $pv     = sprintf "%.1f", ($rad * $af * $kJtokWh * $peak * $pr * $hc * $ccf * $rcf * 1000);
  
      my $lh = {                                                                                      # Log-Hash zur Ausgabe
          "moduleDirection"          => $moddir,
          "modulePeakString"         => $peak,
          "moduleTiltAngle"          => $ta,
          "Area factor"              => $af,
          "Cloudcover"               => $cloudcover,
          "CloudRange"               => $range,
          "CloudCorrFoundInStore"    => $hcfound,
          "CloudFactorDamping"       => $clouddamp." %",
          "Cloudfactor"              => $ccf,
          "Rainprob"                 => $rainprob,
          "Rainfactor"               => $rcf,
          "RainFactorDamping"        => $raindamp." %",
          "pvCorrectionFactor"       => $hc,
          "Radiation"                => $rad,
          "Factor kJ to kWh"         => $kJtokWh,
          "PV generation"            => $pv." Wh"
      };  
      
      my $sq;
      for my $idx (sort keys %{$lh}) {
          $sq .= $idx." => ".$lh->{$idx}."\n";             
      }

      Log3($name, 4, "$name - PV forecast calc for $reld Hour ".sprintf("%02d",$chour+1)." string: $st ->\n$sq");
      
      $pvsum += $pv;
  }
  
  my $kw = AttrVal ($name, 'Wh/kWh', 'Wh');
  if($kw eq "Wh") {
      $pvsum = int $pvsum;
  }
  
  Log3($name, 4, "$name - PV forecast calc for $reld Hour ".sprintf("%02d",$chour+1)." summary: $pvsum");
 
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
  my $t     = $paref->{t};                                                              # aktuelle Unix-Zeit
  my $chour = $paref->{chour};
  my $day   = $paref->{day};                                                            # aktueller Tag (01,02,03...31)
  
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
  
  $idts = timestringToTimestamp ($hash, $idts);

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
      
      $paref->{hour}             = $h;
      my ($pvavg,$fcavg,$anzavg) = calcFromHistory ($paref);                                              # historische PV / Forecast Vergleichswerte ermitteln
      $anzavg                  //= 0;
      $pvval                     = $pvavg ? ($pvval + $pvavg) / 2 : $pvval;                               # Ertrag aktuelle Stunde berücksichtigen
      $fcval                     = $fcavg ? ($fcval + $fcavg) / 2 : $fcval;                               # Vorhersage aktuelle Stunde berücksichtigen
      
      Log3 ($name, 4, "$name - PV History -> average hour ($h) -> real: $pvval, forecast: $fcval");
      
      my $factor = sprintf "%.2f", ($pvval / $fcval);                                                     # Faktorberechnung: reale PV / Prognose
      if(abs($factor - $oldfac) > $maxvar) {
          $factor = sprintf "%.2f", ($factor > $oldfac ? $oldfac + $maxvar : $oldfac - $maxvar);
          Log3($name, 3, "$name - new limited Variance factor: $factor (old: $oldfac) for hour: $h");
      }
      else {
          Log3($name, 3, "$name - new Variance factor: $factor (old: $oldfac) for hour: $h calculated") if($factor != $oldfac);
      }
      
      push @da, "pvCorrectionFactor_".sprintf("%02d",$h)."<>".$factor." (automatic - old factor: $oldfac, num history days for avg: $anzavg)";
      push @da, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc<>done";
      
      my $chwcc = HistoryVal ($hash, $day, sprintf("%02d",$h), "wcc", undef);                            # Wolkenbedeckung Tag / Stunde
      if(defined $chwcc) {
          my $range = int ($chwcc/10);                                                                   # Range errechnen
          my $type  = $hash->{TYPE};         
          Log3($name, 5, "$name - write correction factor into circular Hash: Factor $factor, Hour $h, Range $chwcc");
          
          $data{$type}{$name}{circular}{sprintf("%02d",$h)}{pvcorrf}{$range} = $factor;                  # Bewölkung Range 0..10 für die jeweilige Stunde als Datenquelle eintragen
      }
      
      $paref->{pvcorrf}  = $factor;
      $paref->{nhour}    = sprintf("%02d",$h);
      $paref->{histname} = "pvcorrfactor";
      setPVhistory ($paref);
      delete $paref->{histname};    
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
  my $hour  = $paref->{hour};                                                             # Stunde des Tages für die der Durchschnitt bestimmt werden soll
  my $day   = $paref->{day};                                                              # aktueller Tag
  
  $hour     = sprintf("%02d",$hour);
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};  
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
          Log3 ($name, 4, "$name - PV History -> Raw Days ($calcd) for calc: ".join " ",@efa); 
      }
      else {                                                                              # vermeide Fehler: Illegal division by zero
          Log3 ($name, 4, "$name - PV History -> Day $day has index $idx. Use only current day for average calc");
          return;
      }
      
      my $chwcc = HistoryVal ($hash, $day, $hour, "wcc", undef);                          # Wolkenbedeckung Heute & abgefragte Stunde
      
      if(!defined $chwcc) {
          Log3 ($name, 4, "$name - Day $day has no cloudiness value set for hour $hour, no past averages can be calculated."); 
          return;
      }
           
      $chwcc = int ($chwcc/10);   
      
      Log3 ($name, 4, "$name - cloudiness range of day/hour $day/$hour is: $chwcc");
      
      $anzavg          = 0;      
      my ($pvrl,$pvfc) = (0,0);
            
      for my $dayfa (@efa) {
          my $histwcc = HistoryVal ($hash, $dayfa, $hour, "wcc", undef);                   # historische Wolkenbedeckung
          
          if(!defined $histwcc) {
              Log3 ($name, 4, "$name - PV History -> Day $dayfa has no cloudiness value set for hour $hour, this history dataset is ignored."); 
              next;
          }  

          $histwcc = int ($histwcc/10);

          if($chwcc == $histwcc) {               
              $pvrl  += HistoryVal ($hash, $dayfa, $hour, "pvrl", 0);
              $pvfc  += HistoryVal ($hash, $dayfa, $hour, "pvfc", 0);
              $anzavg++;
              Log3 ($name, 5, "$name - History Average -> current/historical cloudiness range identical: $chwcc. Day/hour $dayfa/$hour included.");
          }
          else {
              Log3 ($name, 5, "$name - History Average -> current/historical cloudiness range different: $chwcc/$histwcc. Day/hour $dayfa/$hour discarded.");
          }
      }
      
      if(!$anzavg) {
          Log3 ($name, 5, "$name - History Average -> all cloudiness ranges were different/not set -> no historical averages calculated");
          return;
      }
      
      my $pvavg = sprintf "%.2f", $pvrl / $anzavg;
      my $fcavg = sprintf "%.2f", $pvfc / $anzavg;
      
      return ($pvavg,$fcavg,$anzavg);
  }
  
return;
}

################################################################
#   PV und PV Forecast in History-Hash speichern zur 
#   Berechnung des Korrekturfaktors über mehrere Tage
################################################################
sub setPVhistory {               
  my $paref      = shift;
  my $hash       = $paref->{hash};
  my $name       = $paref->{name};
  my $t          = $paref->{t};                                                                   # aktuelle Unix-Zeit
  my $nhour      = $paref->{nhour};
  my $day        = $paref->{day};
  my $histname   = $paref->{histname}      // qq{};
  my $ethishour  = $paref->{ethishour}     // 0;
  my $calcpv     = $paref->{calcpv}        // 0;
  my $gcthishour = $paref->{gctotthishour} // 0;                                                  # Grid Consumption
  my $fithishour = $paref->{gftotthishour} // 0;                                                  # Grid Feed In
  my $wid        = $paref->{wid}           // -1;
  my $wcc        = $paref->{wcc}           // 0;                                                  # Wolkenbedeckung
  my $wrp        = $paref->{wrp}           // 0;                                                  # Wahrscheinlichkeit von Niederschlag
  my $pvcorrf    = $paref->{pvcorrf}       // 1;                                                  # pvCorrectionFactor
  
  my $type = $hash->{TYPE};
  my $val  = q{};

  if($histname eq "pvrl") {                                                                       # realer Energieertrag
      $val = $ethishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvrl} = $ethishour;  
      
      my $pvrlsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvrlsum += HistoryVal ($hash, $day, $k, "pvrl", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvrl} = $pvrlsum;      
  }
  
  if($histname eq "pvfc") {                                                                       # prognostizierter Energieertrag
      $val = $calcpv;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvfc} = $calcpv; 

      my $pvfcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvfcsum += HistoryVal ($hash, $day, $k, "pvfc", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvfc} = $pvfcsum;       
  }
  
  if($histname eq "cons") {                                                                       # bezogene Energie
      $val = $gcthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gcons} = $gcthishour; 

      my $gcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gcsum += HistoryVal ($hash, $day, $k, "gcons", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gcons} = $gcsum;       
  }
  
  if($histname eq "gfeedin") {                                                                    # eingespeiste Energie
      $val = $fithishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gfeedin} = $fithishour; 

      my $gfisum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gfisum += HistoryVal ($hash, $day, $k, "gfeedin", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gfeedin} = $gfisum;       
  }
  
  if($histname eq "weatherid") {                                                                  # Wetter ID
      $val = $wid;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{weatherid} = $wid;   
      $data{$type}{$name}{pvhist}{$day}{99}{weatherid}     = q{};       
  }
  
  if($histname eq "weathercloudcover") {                                                          # Wolkenbedeckung
      $val = $wcc;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wcc} = $wcc;   
      $data{$type}{$name}{pvhist}{$day}{99}{wcc}     = q{};       
  }
  
  if($histname eq "weatherrainprob") {                                                            # Niederschlagswahrscheinlichkeit
      $val = $wrp;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wrp} = $wrp;   
      $data{$type}{$name}{pvhist}{$day}{99}{wrp}     = q{};       
  }
  
  if($histname eq "pvcorrfactor") {                                                               # pvCorrectionFactor
      $val = $pvcorrf;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvcorrf} = $pvcorrf;   
      $data{$type}{$name}{pvhist}{$day}{99}{pvcorrf}     = q{};       
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
          my $pvrl    = HistoryVal ($hash, $day, $key, "pvrl",      "-");
          my $pvfc    = HistoryVal ($hash, $day, $key, "pvfc",      "-");
          my $gcons   = HistoryVal ($hash, $day, $key, "gcons",     "-");
          my $gfeedin = HistoryVal ($hash, $day, $key, "gfeedin",   "-");
          my $wid     = HistoryVal ($hash, $day, $key, "weatherid", "-");
          my $wcc     = HistoryVal ($hash, $day, $key, "wcc",       "-");
          my $wrp     = HistoryVal ($hash, $day, $key, "wrp",       "-");
          my $pvcorrf = HistoryVal ($hash, $day, $key, "pvcorrf",   "-");
          $ret       .= "\n      " if($ret);
          $ret       .= $key." => pvrl: $pvrl, pvfc: $pvfc, gcon: $gcons, gfeedin: $gfeedin, wid: $wid, wcc: $wcc, wrp: $wrp, pvcorrf: $pvcorrf";
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
  
  if ($htol eq "circular") {
      $h = $data{$type}{$name}{circular};
      if (!keys %{$h}) {
          return qq{Circular cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $pvfc    = CircularVal ($hash, $idx, "pvfc",       "-");
          my $pvrl    = CircularVal ($hash, $idx, "pvrl",       "-");
          my $gcons   = CircularVal ($hash, $idx, "gcons",      "-");
          my $gfeedin = CircularVal ($hash, $idx, "gfeedin",    "-");
          my $wid     = CircularVal ($hash, $idx, "weatherid",  "-");
          my $wtxt    = CircularVal ($hash, $idx, "weathertxt", "-");
          my $wccv    = CircularVal ($hash, $idx, "wcc",        "-");
          my $wrprb   = CircularVal ($hash, $idx, "wrp",        "-");
          my $pvcorrf = CircularVal ($hash, $idx, "pvcorrf",    "-");
          
          my $pvcf;
          if(ref $pvcorrf eq "HASH") {
              for my $f (sort {$a<=>$b} keys %{$h->{$idx}{pvcorrf}}) {
                  $pvcf .= " " if($pvcf);
                  $pvcf .= "$f=".$h->{$idx}{pvcorrf}{$f};
              }
          }
          else {
              $pvcf = $pvcorrf;
          }
          
          $sq .= "\n" if($sq);
          $sq .= $idx." => pvfc: $pvfc, pvrl: $pvrl, gcon: $gcons, gfeedin: $gfeedin, wcc: $wccv, wrp: $wrprb, wid: $wid, corr: $pvcf, wtxt: $wtxt";
      }
  }
  
  if ($htol eq "nexthours") {
      $h = $data{$type}{$name}{nexthours};
      if (!keys %{$h}) {
          return qq{NextHours cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $nhts  = NexthoursVal ($hash, $idx, "starttime",  "-");
          my $nhfc  = NexthoursVal ($hash, $idx, "pvforecast", "-");
          my $wid   = NexthoursVal ($hash, $idx, "weatherid",  "-");
          my $neff  = NexthoursVal ($hash, $idx, "cloudcover", "-");
          my $r101  = NexthoursVal ($hash, $idx, "rainprob",   "-");
          my $rad1h = NexthoursVal ($hash, $idx, "Rad1h",      "-");
          $sq      .= "\n" if($sq);
          $sq      .= $idx." => starttime: $nhts, pvforecast: $nhfc, weatherid: $wid, cloudcover: $neff, rainprob: $r101, Rad1h: $rad1h";
      }
  }
  
  if ($htol eq "current") {
      $h = $data{$type}{$name}{current};
      if (!keys %{$h}) {
          return qq{current values cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          if (ref $h->{$idx} ne "ARRAY") {
              $sq .= $idx." => ".$h->{$idx}."\n";  
          }
          else {
             my $aser = join " ",@{$h->{$idx}};
             $sq .= $idx." => ".$aser."\n";               
          }     
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
#  Array auf eine festgelegte Anzahl Elemente beschränken,
#  Das älteste Element wird entfernt
#
#  $href  = Referenz zum Array
#  $limit = die Anzahl Elemente auf die gekürzt werden soll
#           (default 3)
#
################################################################
sub limitArray {
  my $href  = shift;
  my $limit = shift // 3;  
  
  return if(ref $href ne "ARRAY");
  
  while (scalar @{$href} > $limit) {
      shift @{$href};
  }

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
      my ($rn,$rval,$ts) = split "<>", $elem, 3;
      readingsBulkUpdate($hash, $rn, $rval, undef, $ts);      
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
  
  for my $reading ( grep { /$readingspec/x } keys %{$hash->{READINGS}} ) {
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
      my ($afc,$ain,$ame,$h);
      
      my $fcdev = ReadingsVal($name, "currentForecastDev", "");              # Forecast Device
      ($afc,$h) = parseParams ($fcdev);
      $fcdev    = $afc->[0] // "";      
      
      my $indev = ReadingsVal($name, "currentInverterDev", "");              # Inverter Device
      ($ain,$h) = parseParams ($indev);
      $indev    = $ain->[0] // "";
      
      my $medev = ReadingsVal($name, "currentMeterDev",    "");              # Meter Device
      
      ($ame,$h) = parseParams ($medev);
      $medev    = $ame->[0] // "";
      
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

######################################################################
#    Wert des pvhist-Hash zurückliefern
#    Usage:
#    HistoryVal ($hash, $day, $hod, $key, $def)
#
#    $day: Tag des Monats (01,02,...,31)
#    $hod: Stunde des Tages (01,02,...,24,99)
#    $key:    pvrl      - realer PV Ertrag
#             pvfc      - PV Vorhersage
#             gcons     - realer Netzbezug
#             gfeedin   - reale Netzeinspeisung
#             weatherid - Wetter ID
#             wcc       - Grad der Bewölkung
#             wrp       - Niederschlagswahrscheinlichkeit
#             pvcorrf   - PV Autokorrekturfaktor f. Stunde des Tages
#    $def: Defaultwert
#
######################################################################
sub HistoryVal {
  my $hash = shift;
  my $day  = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{pvhist})                    &&
     defined($data{$type}{$name}{pvhist}{$day})              &&
     defined($data{$type}{$name}{pvhist}{$day}{$hod})        &&
     defined($data{$type}{$name}{pvhist}{$day}{$hod}{$key})) {
     return  $data{$type}{$name}{pvhist}{$day}{$hod}{$key};
  }

return $def;
}

################################################################
#    Wert des circular-Hash zurückliefern
#    Achtung: die Werte im circular-Hash haben nicht
#             zwingend eine Beziehung zueinander !!
#
#    Usage:
#    CircularVal ($hash, $hod, $key, $def)
#
#    $hod: Stunde des Tages (01,02,...,24)
#    $key:    pvrl       - realer PV Ertrag
#             pvfc       - PV Vorhersage
#             gcons      - realer Netzbezug
#             gfeedin    - reale Netzeinspeisung
#             weatherid  - DWD Wetter id 
#             weathertxt - DWD Wetter Text
#             wcc        - DWD Wolkendichte
#             wrp        - DWD Regenwahrscheinlichkeit
#             pvcorrf    - PV Autokorrekturfaktoren (HASH)
#    $def: Defaultwert
#
################################################################
sub CircularVal {
  my $hash = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{circular})              &&
     defined($data{$type}{$name}{circular}{$hod})        &&
     defined($data{$type}{$name}{circular}{$hod}{$key})) {
     return  $data{$type}{$name}{circular}{$hod}{$key};
  }

return $def;
}

################################################################
#    Wert des Autokorrekturfaktors für eine bestimmte
#    Bewölkungs-Range aus dem circular-Hash zurückliefern
#    Usage:
#    CircularAutokorrVal ($hash, $hod, $range, $def)
#
#    $hod:    Stunde des Tages (01,02,...,24)
#    $range:  Range Bewölkung (1...10)
#    $def:    Defaultwert
#
################################################################
sub CircularAutokorrVal {
  my $hash  = shift;
  my $hod   = shift;
  my $range = shift;
  my $def   = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{circular})                         &&
     defined($data{$type}{$name}{circular}{$hod})                   &&
     defined($data{$type}{$name}{circular}{$hod}{pvcorrf})          &&
     defined($data{$type}{$name}{circular}{$hod}{pvcorrf}{$range})) {
     return  $data{$type}{$name}{circular}{$hod}{pvcorrf}{$range};
  }

return $def;
}

################################################################
# Wert des nexthours-Hash zurückliefern
# Usage:
# NexthoursVal ($hash, $hod, $key, $def)
#
# $hod: nächste Stunde (NextHour00, NextHour01,...)
# $key: starttime  - Startzeit der abgefragten nächsten Stunde
#       pvforecast - PV Vorhersage
#       weatherid  - DWD Wetter id 
#       cloudcover - DWD Wolkendichte
#       rainprob   - DWD Regenwahrscheinlichkeit
#       Rad1h      - Globalstrahlung (kJ/m2)
# $def: Defaultwert
#
################################################################
sub NexthoursVal {
  my $hash = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{nexthours})              &&
     defined($data{$type}{$name}{nexthours}{$hod})        &&
     defined($data{$type}{$name}{nexthours}{$hod}{$key})) {
     return  $data{$type}{$name}{nexthours}{$hod}{$key};
  }

return $def;
}

################################################################
# Wert des current-Hash zurückliefern
# Usage:
# CurrentVal ($hash, $key, $def)
#
# $key: generation      - aktuelle PV Erzeugung
#       genslidereg     - Schieberegister PV Erzeugung (Array)
#       h4fcslidereg    - Schieberegister 4h PV Forecast (Array)
#       gridconsumption - aktueller Netzbezug
#       powerbatin      - Batterie Ladeleistung
#       powerbatout     - Batterie Entladeleistung
# $def: Defaultwert
#
################################################################
sub CurrentVal {
  my $hash = shift;
  my $key  = shift;
  my $def  = shift;  
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{current})       &&
     defined($data{$type}{$name}{current}{$key})) {
     return  $data{$type}{$name}{current}{$key};
  }

return $def;
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
            <tr><td> <b>currentForecastDev</b>   </td><td>Device welches Wetter- und Strahlungsdaten liefert  </td></tr>
            <tr><td> <b>currentInverterDev</b>   </td><td>Device welches PV Leistungsdaten liefert            </td></tr>
            <tr><td> <b>currentMeterDev</b>      </td><td>Device welches Netz I/O-Daten liefert               </td></tr>
            <tr><td> <b>currentBatteryDev</b>    </td><td>Device welches Batterie Leistungsdaten liefert      </td></tr>            
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
      <a name="currentBatteryDev"></a>
      <li><b>currentBatteryDev &lt;Meter Device Name&gt; pin=&lt;Readingname&gt;:&lt;Einheit&gt; pout=&lt;Readingname&gt;:&lt;Einheit&gt;   </b> <br><br> 
      
      Legt ein beliebiges Device und seine Readings zur Lieferung der Batterie Leistungsdaten fest. 
      Das Modul geht davon aus dass der numerische Wert der Readings immer positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>pin</b>       </td><td>Reading welches die aktuelle Batterieladung liefert       </td></tr>
          <tr><td> <b>pout</b>      </td><td>Reading welches die aktuelle Batterieentladung liefert    </td></tr>
          <tr><td> <b>Einheit</b>   </td><td>die jeweilige Einheit (W,kW)                              </td></tr>
        </table>
      </ul> 
      <br>
      
      <b>Sonderfälle:</b> Sollte das Reading für pin und pout identisch, aber vorzeichenbehaftet sein, 
      können die Schlüssel pin und pout wie folgt definiert werden: <br><br>
      <ul>
        pin=-pout  &nbsp;&nbsp;&nbsp;(ein negativer Wert von pout wird als pin verwendet)  <br>
        pout=-pin  &nbsp;&nbsp;&nbsp;(ein negativer Wert von pin wird als pout verwendet)
      </ul>
      <br>
      
      Die Einheit entfällt in dem jeweiligen Sonderfall. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentBatteryDev BatDummy pin=BatVal:W pout=-pin <br>
        <br>
        # Device BatDummy liefert die aktuelle Batterieladung im Reading "BatVal" (W), die Batterieentladung im gleichen Reading mit negativen Vorzeichen
      </ul>      
      </li>
    </ul>
    <br>
  
    <ul>
      <a name="currentForecastDev"></a>
      <li><b>currentForecastDev </b> <br><br> 
      
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
      <li><b>currentInverterDev &lt;Inverter Device Name&gt; pv=&lt;Readingname&gt;:&lt;Einheit&gt; etotal=&lt;Readingname&gt;:&lt;Einheit&gt;  </b> <br><br>  
      
      Legt ein beliebiges Device und dessen Readings zur Lieferung der aktuellen PV Erzeugungswerte fest. 
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. 
      Die Werte mehrerer Inverterdevices führt man z.B. in einem Dummy Device zusammen und gibt dieses Device mit den 
      entsprechenden Readings an. Die Bedeutung des jeweiligen "Readingname" ist:
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>pv</b>       </td><td>Reading welches die aktuelle PV-Erzeugung liefert                                       </td></tr>
          <tr><td> <b>etotal</b>   </td><td>Reading welches die gesamte erzeugten Energie liefert (ein stetig aufsteigender Zähler) </td></tr>
          <tr><td> <b>Einheit</b>  </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                                     </td></tr>
        </table>
      </ul> 
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentInverterDev STP5000 pv=total_pac:kW etotal=etotal:kWh <br>
        <br>
        # Device STP5000 liefert PV-Werte. Die aktuell erzeugte Leistung im Reading "total_pac" (kW) und die tägliche Erzeugung im 
          Reading "etotal" (kWh)
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="currentMeterDev"></a>
      <li><b>currentMeterDev &lt;Meter Device Name&gt; gcon=&lt;Readingname&gt;:&lt;Einheit&gt; contotal=&lt;Readingname&gt;:&lt;Einheit&gt; gfeedin=&lt;Readingname&gt;:&lt;Einheit&gt; feedtotal=&lt;Readingname&gt;:&lt;Einheit&gt;   </b> <br><br> 
      
      Legt ein beliebiges Device und seine Readings zur Energiemessung fest. 
      Das Modul geht davon aus dass der numerische Wert der Readings immer positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>gcon</b>       </td><td>Reading welches die aktuell aus dem Netz bezogene Leistung liefert       </td></tr>
          <tr><td> <b>contotal</b>   </td><td>Reading welches die Summe der aus dem Netz bezogenen Energie liefert     </td></tr>
          <tr><td> <b>gfeedin</b>    </td><td>Reading welches die aktuell in das Netz eingespeiste Leistung liefert    </td></tr>
          <tr><td> <b>feedtotal</b>  </td><td>Reading welches die Summe der in das Netz eingespeisten Energie liefert  </td></tr>
          <tr><td> <b>Einheit</b>    </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                      </td></tr>
        </table>
      </ul> 
      <br>
      
      <b>Sonderfälle:</b> Sollte das Reading für gcon und gfeedin identisch, aber vorzeichenbehaftet sein, 
      können die Schlüssel gfeedin und gcon wie folgt definiert werden: <br><br>
      <ul>
        gfeedin=-gcon  &nbsp;&nbsp;&nbsp;(ein negativer Wert von gcon wird als gfeedin verwendet)  <br>
        gcon=-gfeedin  &nbsp;&nbsp;&nbsp;(ein negativer Wert von gfeedin wird als gcon verwendet)
      </ul>
      <br>
      
      Die Einheit entfällt in dem jeweiligen Sonderfall. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentMeterDev Meter gcon=Wirkleistung:W contotal=BezWirkZaehler:kWh gfeedin=-gcon feedtotal=EinWirkZaehler:kWh  <br>
        <br>
        # Device Meter liefert den aktuellen Netzbezug im Reading "Wirkleistung" (W), 
          die Summe des Netzbezugs im Reading "BezWirkZaehler" (kWh), die aktuelle Einspeisung in "Wirkleistung" wenn "Wirkleistung" negativ ist,
          die Summe der Einspeisung im Reading "EinWirkZaehler" (kWh)
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="energyH4Trigger"></a>
      <li><b>energyH4Trigger &lt;1on&gt;=&lt;Wert&gt; &lt;1off&gt;=&lt;Wert&gt; [&lt;2on&gt;=&lt;Wert&gt; &lt;2off&gt;=&lt;Wert&gt; ...] </b> <br><br>  
      
      Generiert Trigger bei Über- bzw. Unterschreitung der 4-Stunden PV Vorhersage (NextHours_Sum04_PVforecast). <br>
      Überschreiten die letzten drei Messungen der 4-Stunden PV Vorhersagen eine definierte <b>Xon-Bedingung</b>, wird das Reading 
      <b>energyH4Trigger_X = on</b> erstellt/gesetzt. 
      Unterschreiten die letzten drei Messungen der 4-Stunden PV Vorhersagen eine definierte <b>Xoff-Bedingung</b>, wird das Reading 
      <b>energyH4Trigger_X = off</b> erstellt/gesetzt. <br>
      Es kann eine beliebige Anzahl von Triggerbedingungen angegeben werden. Xon/Xoff-Bedingungen müssen nicht zwingend paarweise
      definiert werden. <br>
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; energyH4Trigger 1on=2000 1off=1700 2on=2500 2off=2000 3off=1500 <br>
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="inverterStrings"></a>
      <li><b>inverterStrings &lt;Stringname1&gt;[,&lt;Stringname2&gt;,&lt;Stringname3&gt;,...] </b> <br><br>  
      
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
      <li><b>modulePeakString &lt;Stringname1&gt;=&lt;Peak&gt; [&lt;Stringname2&gt;=&lt;Peak&gt; &lt;Stringname3&gt;=&lt;Peak&gt; ...] </b> <br><br> 
      
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
      <li><b>moduleDirection &lt;Stringname1&gt;=&lt;dir&gt; [&lt;Stringname2&gt;=&lt;dir&gt; &lt;Stringname3&gt;=&lt;dir&gt; ...] </b> <br><br>  
      
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
      <li><b>moduleTiltAngle &lt;Stringname1&gt;=&lt;Winkel&gt; [&lt;Stringname2&gt;=&lt;Winkel&gt; &lt;Stringname3&gt;=&lt;Winkel&gt; ...] </b> <br><br>  
      
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
      <a name="powerTrigger"></a>
      <li><b>powerTrigger &lt;1on&gt;=&lt;Wert&gt; &lt;1off&gt;=&lt;Wert&gt; [&lt;2on&gt;=&lt;Wert&gt; &lt;2off&gt;=&lt;Wert&gt; ...] </b> <br><br>  
      
      Generiert Trigger bei Über- bzw. Unterschreitung bestimmter PV Erzeugungswerte (Current_PV). <br>
      Überschreiten die letzten drei Messungen der PV Erzeugung eine definierte <b>Xon-Bedingung</b>, wird das Reading 
      <b>powerTrigger_X = on</b> erstellt/gesetzt. 
      Unterschreiten die letzten drei Messungen der PV Erzeugung eine definierte <b>Xoff-Bedingung</b>, wird das Reading 
      <b>powerTrigger_X = off</b> erstellt/gesetzt. <br>
      Es kann eine beliebige Anzahl von Triggerbedingungen angegeben werden. Xon/Xoff-Bedingungen müssen nicht zwingend paarweise
      definiert werden. <br>
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; powerTrigger 1on=1000 1off=500 2on=2000 2off=1000 3on=1600 4off=1100<br>
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="pvCorrectionFactor_Auto"></a>
      <li><b>pvCorrectionFactor_Auto &lt;on | off&gt; </b> <br><br>  
      
      Schaltet die automatische Vorhersagekorrektur ein/aus. <br>
      Ist die Automatik eingeschaltet, wird nach einer Mindestlaufzeit von FHEM bzw. des Moduls von 24 Stunden für jede Stunde 
      ein Korrekturfaktor der Solarvorhersage berechnet und auf die Erwartung des kommenden Tages angewendet.
      Dazu wird die tatsächliche Energierzeugung mit dem vorhergesagten Wert des aktuellen Tages und Stunde verglichen, 
      die Korrekturwerte historischer Tage unter Berücksichtigung der Bewölkung einbezogen und daraus ein neuer Korrekturfaktor 
      abgeleitet. Es werden nur historische Daten mit gleicher Bewölkungsrange einbezogen. <br>
      <b>Die automatische Vorhersagekorrektur ist lernend und benötigt etliche Tage um die Korrekturwerte zu optimieren.
      Nach der Aktivierung sind nicht sofort optimale Vorhersagen zu erwarten !</b> <br>
      (default: off)      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="pvCorrectionFactor_XX"></a>
      <li><b>pvCorrectionFactor_XX &lt;Zahl&gt; </b> <br><br> 
      
      Manueller Korrekturfaktor für die Stunde XX des Tages zur Anpassung der Vorhersage an die individuelle Anlage. <br>
      (default: 1.0)      
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="reset"></a>
      <li><b>reset </b> <br><br> 
       
       Löscht die aus der Drop-Down Liste gewählte Datenquelle bzw. zu der Funktion gehörende Readings. <br>    
      </li>
    </ul>
    <br>
    
    <ul>
      <a name="writeHistory"></a>
      <li><b>writeHistory </b> <br><br> 
       
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
      <a name="nextHours"></a>
      <li><b>nextHours </b> <br>  
      Listet die erwarteten Werte der nächsten Stunden auf.
      </li>      
    </ul>
    <br>
    
    <ul>
      <a name="pvHistory"></a>
      <li><b>pvHistory </b> <br>
      Listet die historischen Werte der letzten Tage (max. 31) sortiert nach dem Tagesdatum und Stunde. 
      Die Stundenangaben beziehen sich auf die jeweilige Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit 
      von 08 - 09 Uhr. <br><br>
      
      <ul>
         <table>  
         <colgroup> <col width=15%> <col width=85%> </colgroup>
            <tr><td> <b>pvfc</b>     </td><td>der prognostizierte PV Ertrag der jeweiligen Stunde                         </td></tr>
            <tr><td> <b>pvrl</b>     </td><td>reale PV Erzeugung der jeweiligen Stunde                                    </td></tr>
            <tr><td> <b>gcon</b>     </td><td>realer Leistungsbezug aus dem Stromnetz der jeweiligen Stunde               </td></tr>
            <tr><td> <b>gfeedin</b>  </td><td>reale Einspeisung in das Stromnetz der jeweiligen Stunde                    </td></tr>
            <tr><td> <b>wid</b>      </td><td>Identifikationsnummer des Wetters in der jeweiligen Stunde                  </td></tr>
            <tr><td> <b>wcc</b>      </td><td>effektive Wolkenbedeckung der jeweiligen Stunde                             </td></tr>
            <tr><td> <b>wrp</b>      </td><td>Wahrscheinlichkeit von Niederschlag > 0,1 mm während der jeweiligen Stunde  </td></tr>
            <tr><td> <b>pvcorrf</b>  </td><td>abgeleiteter Autokorrekturfaktor der jeweiligen Stunde                      </td></tr>
         </table>
      </ul>
      </li>      
    </ul>
    <br>
    
    <ul>
      <a name="pvCircular"></a>
      <li><b>pvCircular </b> <br>
      Listet die vorhandenen Werte im Ringspeicher auf.  
      Die Stundenangaben beziehen sich auf die Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit von 08 - 09 Uhr.      
      Erläuterung der Werte: <br><br>
      
      <ul>
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>pvfc</b>     </td><td>PV Vorhersage für die nächsten 24h ab aktueller Stunde des Tages                                                   </td></tr>
            <tr><td> <b>pvrl</b>     </td><td>reale PV Erzeugung der letzten 24h (Achtung: pvforecast und pvreal beziehen sich nicht auf den gleichen Zeitraum!) </td></tr>
            <tr><td> <b>gcon</b>     </td><td>realer Leistungsbezug aus dem Stromnetz                                                                            </td></tr>
            <tr><td> <b>gfeedin</b>  </td><td>reale Leistungseinspeisung in das Stromnetz                                                                        </td></tr>
            <tr><td> <b>wcc</b>      </td><td>Grad der Wolkenüberdeckung                                                                                         </td></tr>
            <tr><td> <b>wrp</b>      </td><td>Grad der Regenwahrscheinlichkeit                                                                                   </td></tr>
            <tr><td> <b>wid</b>      </td><td>ID des vorhergesagten Wetters                                                                                      </td></tr>
            <tr><td> <b>corr</b>     </td><td>Autokorrekturfaktoren für die Stunde des Tages und der Bewölkungsrange 0..10                                       </td></tr>
            <tr><td> <b>wtxt</b>     </td><td>Beschreibung des vorhergesagten Wetters                                                                            </td></tr>
         </table>
      </ul>
      
      </li>      
    </ul>
    <br>
    
    <ul>
      <a name="stringConfig"></a>
      <li><b>stringConfig </b> <br>
      Zeigt die aktuelle Stringkonfiguration. Dabei wird gleichzeitig eine Plausibilitätsprüfung vorgenommen und das Ergebnis
      sowie eventuelle Anweisungen zur Fehlerbehebung ausgegeben. 
      </li>      
    </ul>
    <br>
    
    <ul>
      <a name="valCurrent"></a>
      <li><b>valCurrent </b> <br>
      Listet die aktuell ermittelten Werte auf.
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
        <li><b>alias </b> <br>
          In Verbindung mit "showLink" ein beliebiger Anzeigename.
        </li>
        <br>  
       
       <a name="autoRefresh"></a>
       <li><b>autoRefresh</b> <br>
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
            <tr><td> <b>forecast</b>        </td><td>Vorhersage der PV-Erzeugung (default) </td></tr>
            <tr><td> <b>real</b>            </td><td>tatsächliche PV-Erzeugung             </td></tr>
            <tr><td> <b>gridconsumption</b> </td><td>Energie Bezug aus dem Netz            </td></tr>
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
            <tr><td> <b>forecast</b>        </td><td>Vorhersage der PV-Erzeugung (default) </td></tr>
            <tr><td> <b>real</b>            </td><td>tatsächliche PV-Erzeugung             </td></tr>
            <tr><td> <b>gridconsumption</b> </td><td>Energie Bezug aus dem Netz            </td></tr>
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
       
       <a name="cloudFactorDamping"></a>
       <li><b>cloudFactorDamping </b><br>
         Prozentuale Berücksichtigung (Dämpfung) des Bewölkungprognosefaktors bei der solaren Vorhersage. <br>
         Größere Werte vermindern, kleinere Werte erhöhen tendenziell den prognostizierten PV Ertrag.<br>
         (default: 45)         
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
       <li><b>headerDetail </b><br>
         Detailiierungsgrad der Kopfzeilen. <br>
         (default: all)
         
         <ul>   
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
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
           <colgroup> <col width=30%> <col width=70%> </colgroup>
           <tr><td> <b>nicht gesetzt</b>  </td><td>nur Stundenangabe ohne Minuten (default)                </td></tr>
           <tr><td> <b>:00</b>            </td><td>Stunden sowie Minuten zweistellig, z.B. 10:00           </td></tr>
           <tr><td> <b>:0</b>             </td><td>Stunden sowie Minuten einstellig, z.B. 8:0              </td></tr>
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
       <li><b>layoutType &lt;single | double | diff&gt; </b><br>
       Layout der integrierten Grafik. <br>
       Der darzustellende Inhalt der Balken wird durch die Attribute <b>beam1Content</b> bzw. <b>beam2Content</b> 
       bestimmt. <br>
       (default: single)  
       <br><br>
       
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>single</b>  </td><td>- zeigt nur den primären Balken an                                                                         </td></tr>
          <tr><td> <b>double</b>  </td><td>- zeigt den primären Balken und den sekundären Balken an                                                                            </td></tr>
          <tr><td> <b>diff</b>    </td><td>- Differenzanzeige. Es gilt:  &lt;Differenz&gt; = &lt;Wert primärer Balken&gt; - &lt;Wert sekundärer Balken&gt;  </td></tr>
       </table>
       </ul>
       </li>
       <br> 
 
       <a name="maxValBeam"></a>
       <li><b>maxValBeam &lt;0...val&gt; </b><br>
         Festlegung des maximalen Betrags des primären Balkens (Stundenwert) zur Berechnung der maximalen Balkenhöhe. 
         Dadurch erfolgt eine Anpassung der zulässigen Gesamthöhe der Grafik. <br>
         Wenn nicht gesetzt oder 0, erfolgt eine dynamische Anpassung. <br>
         (default: 0)
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
         (default: 21)
       </li>
       <br>
       
       <a name="rainFactorDamping"></a>
       <li><b>rainFactorDamping </b><br>
         Prozentuale Berücksichtigung (Dämpfung) des Regenprognosefaktors bei der solaren Vorhersage. <br>
         Größere Werte vermindern, kleinere Werte erhöhen tendenziell den prognostizierten PV Ertrag.<br>
         (default: 20)         
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

       <a name="weatherColorNight"></a>
       <li><b>weatherColorNight </b><br>
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

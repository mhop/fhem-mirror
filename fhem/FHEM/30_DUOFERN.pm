##############################################
# $Id$

package main;

use strict;
use warnings;
use SetExtensions;

my %devices = (
    "40"    => {"name" => "RolloTron Standard"                },
    "41"    => {"name" => "RolloTron Comfort Slave"           },
    "42"    => {"name" => "Rohrmotor-Aktor"                   },
    "43"    => {"name" => "Universalaktor",                   "chans" => ["01", "02"] },
    "46"    => {"name" => "Steckdosenaktor"                   },
    "47"    => {"name" => "Rohrmotor Steuerung",              "format" => "23a"},
    "48"    => {"name" => "Dimmaktor"                         },
    "49"    => {"name" => "Rohrmotor"                         },
    "4B"    => {"name" => "Connect-Aktor"                     },
    "4C"    => {"name" => "Troll Basis"                       },
    "4E"    => {"name" => "SX5",                              "format" => "24a"},
    "61"    => {"name" => "RolloTron Comfort Master"          },
    "62"    => {"name" => "Super Fake Device"                 },
    "65"    => {"name" => "Bewegungsmelder",                  "chans" => ["01"]},
    "69"    => {"name" => "Umweltsensor",                     "format" => "23a", "chans" => ["01"]},
    "70"    => {"name" => "Troll Comfort DuoFern"             },
    "71"    => {"name" => "Troll Comfort DuoFern (Lichtmodus)"},
    "73"    => {"name" => "Raumthermostat"                    },
    "74"    => {"name" => "Wandtaster 6fach 230V",            "chans" => ["01"]},
    "A0"    => {"name" => "Handsender (6 Gruppen-48 Geraete)" },
    "A1"    => {"name" => "Handsender (1 Gruppe-48 Geraete)"  },
    "A2"    => {"name" => "Handsender (6 Gruppen-1 Geraet)"   },
    "A3"    => {"name" => "Handsender (1 Gruppe-1 Geraet)"    },
    "A4"    => {"name" => "Wandtaster"                        },
    "A5"    => {"name" => "Sonnensensor"                      },
    "A7"    => {"name" => "Funksender UP"                     },
    "A8"    => {"name" => "HomeTimer"                         },
    "AA"    => {"name" => "Markisenwaechter"                  },
    "AB"    => {"name" => "Rauchmelder"                       },
    "AD"    => {"name" => "Wandtaster 6fach Bat"              },
    "E0"    => {"name" => "Handzentrale"                      },
);

my %sensorMsg = (
    "0701"    => {"name" => "up",          "chan" => 6, "state" => "Btn01"},
    "0702"    => {"name" => "stop",        "chan" => 6, "state" => "Btn02"},
    "0703"    => {"name" => "down",        "chan" => 6, "state" => "Btn03"},
    "0718"    => {"name" => "stepUp",      "chan" => 6, "state" => "Btn18"},
    "0719"    => {"name" => "stepDown",    "chan" => 6, "state" => "Btn19"},
    "071A"    => {"name" => "pressed",     "chan" => 6, "state" => "Btn1A"},  
    "0713"    => {"name" => "dawn",        "chan" => 5, "state" => "dawn"},
    "0709"    => {"name" => "dusk",        "chan" => 5, "state" => "dusk"},
    "0708"    => {"name" => "startSun",    "chan" => 5, "state" => "on"},
    "070A"    => {"name" => "endSun",      "chan" => 5, "state" => "off"},
    "070D"    => {"name" => "startWind",   "chan" => 5, "state" => "on"},
    "070E"    => {"name" => "endWind",     "chan" => 5, "state" => "off"},
    "0711"    => {"name" => "startRain",   "chan" => 5, "state" => "on"},
    "0712"    => {"name" => "endRain",     "chan" => 5, "state" => "off"},   
    "071C"    => {"name" => "startTemp",   "chan" => 5, "state" => "on"},
    "071D"    => {"name" => "endTemp",     "chan" => 5, "state" => "off"},
    "071E"    => {"name" => "startSmoke",  "chan" => 5, "state" => "on"},
    "071F"    => {"name" => "endSmoke",    "chan" => 5, "state" => "off"},      
    "0720"    => {"name" => "startMotion", "chan" => 5, "state" => "on"},
    "0721"    => {"name" => "endMotion",   "chan" => 5, "state" => "off"},
    "0723"    => {"name" => "closeEnd",    "chan" => 5, "state" => "off"},
    "0724"    => {"name" => "closeStart",  "chan" => 5, "state" => "on"},
    "0E01"    => {"name" => "off",         "chan" => 6, "state" => "Btn01"},
    "0E02"    => {"name" => "off",         "chan" => 6, "state" => "Btn02"},
    "0E03"    => {"name" => "on",          "chan" => 6, "state" => "Btn03"},        
);


my %statusGroups = (
  "21"  => [100,101,102,104,105,106,111,112,113,114,50],
  "22"  => [1,2,3,4,5,6,7,8,9,10],
  "23"  => [102,107,109,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,136,140,141,50],
  "23a" => [102,107,109,115,116,117,118,119,120,121,122,123,124,125,126,127,133,140,141,50],
  "24"  => [102,107,115,116,117,118,119,120,121,122,123,124,125,126,127,140,141,400,402,50],
  "24a" => [102,107,115,123,124,400,402,404,405,406,407,408,409,410,411,50],
  "25"  => [300,301,302,303,304,305,306,307,308,309,310,311,312,313],
  "26"  => [],
  "27"  => [160,161,162,163,164,165,166,167,168,169,170,171],
);


my %statusMapping = (
  "onOff"     => ["off", "on"],
  "upDown"    => ["up", "down"],
  "moving"    => ["stop","stop"],
  "motor"     => ["off", "short(160ms)", "long(480ms)", "individual"],
  "closeT"    => ["off", "30", "60", "90", "120", "150", "180", "210", "240"],
  "openS"     => ["error", "11", "15", "19"], 
  "scale10"   => [10,0],
  "scaleF1"   => [2,80],
  "scaleF2"   => [10,400],
);

     
my %statusIds = (
  1   => {"name" => "level",                                                    "chan" => { "01" => {"position" => 7, "from" => 0, "to" => 6},
                                                                                            "02" => {"position" => 6, "from" => 0, "to" => 6}}},
  2   => {"name" => "timeAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 0, "to" => 0},
                                                                                            "02" => {"position" => 2, "from" => 0, "to" => 0}}},
  3   => {"name" => "duskAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 1, "to" => 1},
                                                                                            "02" => {"position" => 2, "from" => 1, "to" => 1}}},
  4   => {"name" => "dawnAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 6, "to" => 6},
                                                                                            "02" => {"position" => 2, "from" => 6, "to" => 6}}},
  5   => {"name" => "sunAutomatic",         "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 2, "to" => 2},
                                                                                            "02" => {"position" => 2, "from" => 2, "to" => 2}}},
  6   => {"name" => "manualMode",           "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 5, "to" => 5},
                                                                                            "02" => {"position" => 2, "from" => 5, "to" => 5}}},
  7   => {"name" => "modeChange",           "map" => "onOff",                   "chan" => { "01" => {"position" => 7, "from" => 7, "to" => 7},
                                                                                            "02" => {"position" => 6, "from" => 7, "to" => 7}}},
  8   => {"name" => "sunMode",              "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 4, "to" => 4},
                                                                                            "02" => {"position" => 2, "from" => 4, "to" => 4}}},
  9   => {"name" => "stairwellFunction",    "map" => "onOff",                   "chan" => { "01" => {"position" => 4, "from" => 7, "to" => 7},
                                                                                            "02" => {"position" => 0, "from" => 7, "to" => 7}}},
  10  => {"name" => "stairwellTime",        "map" => "scale10",                 "chan" => { "01" => {"position" => 5, "from" => 0, "to" => 14},
                                                                                            "02" => {"position" => 1, "from" => 0, "to" => 14}}},
  50  => {"name" => "moving",               "map" => "moving",                  "chan" => { "01" => {"position" => 0, "from" => 0, "to" => 0},
                                                                                            "02" => {"position" => 0, "from" => 0, "to" => 0}}},    
  100 => {"name" => "sunAutomatic",         "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 2, "to" => 2}}},
  101 => {"name" => "timeAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 0, "to" => 0}}},
  102 => {"name" => "position",             "invert" => 100,                    "chan" => { "01" => {"position" => 7, "from" => 0, "to" => 6}}},
  104 => {"name" => "duskAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 3, "to" => 3}}},
  105 => {"name" => "dawnAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 1, "from" => 3, "to" => 3}}},
  106 => {"name" => "manualMode",           "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 7, "to" => 7}}},
  107 => {"name" => "manualMode",           "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 5, "to" => 5}}},
  109 => {"name" => "runningTime",                                              "chan" => { "01" => {"position" => 6, "from" => 0, "to" => 7}}},
  111 => {"name" => "sunPosition",          "invert" => 100,                    "chan" => { "01" => {"position" => 6, "from" => 0, "to" => 6}}},
  112 => {"name" => "ventilatingPosition",  "invert" => 100,                    "chan" => { "01" => {"position" => 2, "from" => 0, "to" => 6}}},
  113 => {"name" => "ventilatingMode",      "map" => "onOff",                   "chan" => { "01" => {"position" => 2, "from" => 7, "to" => 7}}},
  114 => {"name" => "sunMode",              "map" => "onOff",                   "chan" => { "01" => {"position" => 6, "from" => 7, "to" => 7}}},
  115 => {"name" => "timeAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 0, "to" => 0}}},
  116 => {"name" => "sunAutomatic",         "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 2, "to" => 2}}},
  117 => {"name" => "dawnAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 2, "from" => 1, "to" => 1}}},
  118 => {"name" => "duskAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 1, "to" => 1}}},
  119 => {"name" => "rainAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 7, "to" => 7}}},
  120 => {"name" => "windAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 6, "to" => 6}}},
  121 => {"name" => "sunPosition",          "invert" => 100,                    "chan" => { "01" => {"position" => 5, "from" => 0, "to" => 6}}},
  122 => {"name" => "sunMode",              "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 4, "to" => 4}}},
  123 => {"name" => "ventilatingPosition",  "invert" => 100,                    "chan" => { "01" => {"position" => 4, "from" => 0, "to" => 6}}},
  124 => {"name" => "ventilatingMode",      "map" => "onOff",                   "chan" => { "01" => {"position" => 4, "from" => 7, "to" => 7}}},
  125 => {"name" => "reversal",             "map" => "onOff",                   "chan" => { "01" => {"position" => 7, "from" => 7, "to" => 7}}},
  126 => {"name" => "rainDirection",        "map" => "upDown",                  "chan" => { "01" => {"position" => 2, "from" => 3, "to" => 3}}},
  127 => {"name" => "windDirection",        "map" => "upDown",                  "chan" => { "01" => {"position" => 2, "from" => 2, "to" => 2}}},
  128 => {"name" => "slatRunTime",                                              "chan" => { "01" => {"position" => 0, "from" => 0, "to" => 5}}},
  129 => {"name" => "tiltAfterMoveLevel",   "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 6, "to" => 6}}},
  130 => {"name" => "tiltInVentPos",        "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 7, "to" => 7}}},
  131 => {"name" => "defaultSlatPos",                                           "chan" => { "01" => {"position" => 1, "from" => 0, "to" => 6}}},
  132 => {"name" => "tiltAfterStopDown",    "map" => "onOff",                   "chan" => { "01" => {"position" => 1, "from" => 7, "to" => 7}}},
  133 => {"name" => "motorDeadTime",        "map" => "motor",                   "chan" => { "01" => {"position" => 2, "from" => 4, "to" => 5}}},
  134 => {"name" => "tiltInSunPos",         "map" => "onOff",                   "chan" => { "01" => {"position" => 5, "from" => 7, "to" => 7}}},
  135 => {"name" => "slatPosition",                                             "chan" => { "01" => {"position" => 9, "from" => 0, "to" => 6}}},
  136 => {"name" => "blindsMode",           "map" => "onOff",                   "chan" => { "01" => {"position" => 9, "from" => 7, "to" => 7}}},
  140 => {"name" => "windMode",             "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 3, "to" => 3}}},
  141 => {"name" => "rainMode",             "map" => "onOff",                   "chan" => { "01" => {"position" => 2, "from" => 0, "to" => 0}}},
  160 => {"name" => "temperatureThreshold1","map" => "scaleF1",                 "chan" => { "01" => {"position" => 4, "from" => 0, "to" => 7}}},
  161 => {"name" => "temperatureThreshold2","map" => "scaleF1",                 "chan" => { "01" => {"position" => 5, "from" => 0, "to" => 7}}},
  162 => {"name" => "temperatureThreshold3","map" => "scaleF1",                 "chan" => { "01" => {"position" => 6, "from" => 0, "to" => 7}}},
  163 => {"name" => "temperatureThreshold4","map" => "scaleF1",                 "chan" => { "01" => {"position" => 7, "from" => 0, "to" => 7}}},
  164 => {"name" => "desired-temp",         "map" => "scaleF1",                 "chan" => { "01" => {"position" => 9, "from" => 0, "to" => 7}}},
  165 => {"name" => "measured-temp",        "map" => "scaleF2",                 "chan" => { "01" => {"position" => 1, "from" => 0, "to" => 10}}},
  166 => {"name" => "output",               "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 3, "to" => 3}}},
  167 => {"name" => "manualOverride",       "map" => "onOff",                   "chan" => { "01" => {"position" => 0, "from" => 4, "to" => 4}}},
  168 => {"name" => "actTempLimit",                                             "chan" => { "01" => {"position" => 0, "from" => 5, "to" => 6}}},
  169 => {"name" => "timeAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 2, "from" => 3, "to" => 3}}},
  170 => {"name" => "manualMode",           "map" => "onOff",                   "chan" => { "01" => {"position" => 2, "from" => 4, "to" => 4}}},
  171 => {"name" => "measured-temp2",       "map" => "scaleF2",                 "chan" => { "01" => {"position" => 3, "from" => 0, "to" => 10}}},
  300 => {"name" => "level",                                                    "chan" => { "01" => {"position" => 7, "from" => 0, "to" => 6}}},
  301 => {"name" => "manualMode",           "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 5, "to" => 5}}},
  302 => {"name" => "timeAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 0, "to" => 0}}},
  303 => {"name" => "duskAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 1, "to" => 1}}},
  304 => {"name" => "sunAutomatic",         "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 2, "to" => 2}}},
  305 => {"name" => "sunMode",              "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 4, "to" => 4}}},
  306 => {"name" => "dawnAutomatic",        "map" => "onOff",                   "chan" => { "01" => {"position" => 3, "from" => 6, "to" => 6}}},
  307 => {"name" => "runningTime",                                              "chan" => { "01" => {"position" => 5, "from" => 0, "to" => 7}}},
  308 => {"name" => "intermediateValue",                                        "chan" => { "01" => {"position" => 6, "from" => 0, "to" => 6}}},
  309 => {"name" => "intermediateMode",     "map" => "onOff",                   "chan" => { "01" => {"position" => 6, "from" => 7, "to" => 7}}},
  310 => {"name" => "modeChange",           "map" => "onOff",                   "chan" => { "01" => {"position" => 7, "from" => 7, "to" => 7}}},
  311 => {"name" => "stairwellFunction",    "map" => "onOff",                   "chan" => { "01" => {"position" => 1, "from" => 7, "to" => 7}}},
  312 => {"name" => "stairwellTime",        "map" => "scale10",                 "chan" => { "01" => {"position" => 2, "from" => 0, "to" => 14}}},
  313 => {"name" => "saveIntermediateOnStop","map" => "onOff",                  "chan" => { "01" => {"position" => 3, "from" => 7, "to" => 7}}},
  400 => {"name" => "obstacle",                                                 "chan" => { "01" => {"position" => 2, "from" => 4, "to" => 4}}},
  401 => {"name" => "obstacleDetection",    "map" => "onOff",                   "chan" => { "01" => {"position" => 2, "from" => 5, "to" => 5}}},
  402 => {"name" => "block",                                                    "chan" => { "01" => {"position" => 2, "from" => 6, "to" => 6}}},
  403 => {"name" => "blockDetection",       "map" => "onOff",                   "chan" => { "01" => {"position" => 2, "from" => 7, "to" => 7}}},
  404 => {"name" => "lightCurtain",                                             "chan" => { "01" => {"position" => 0, "from" => 7, "to" => 7}}},
  405 => {"name" => "automaticClosing",     "map" => "closeT",                  "chan" => { "01" => {"position" => 1, "from" => 0, "to" => 3}}},
  406 => {"name" => "openSpeed",            "map" => "openS",                   "chan" => { "01" => {"position" => 1, "from" => 4, "to" => 6}}},
  407 => {"name" => "2000cycleAlarm",       "map" => "onOff",                   "chan" => { "01" => {"position" => 1, "from" => 7, "to" => 7}}},
  408 => {"name" => "wicketDoor",           "map" => "onOff",                   "chan" => { "01" => {"position" => 5, "from" => 7, "to" => 7}}},
  409 => {"name" => "backJump",             "map" => "onOff",                   "chan" => { "01" => {"position" => 9, "from" => 0, "to" => 0}}},
  410 => {"name" => "10minuteAlarm",        "map" => "onOff",                   "chan" => { "01" => {"position" => 9, "from" => 1, "to" => 1}}},
  411 => {"name" => "light",                "map" => "onOff",                   "chan" => { "01" => {"position" => 9, "from" => 2, "to" => 2}}},
  999 => {"name" => "version",                                                  "chan" => { "01" => {"position" => 8, "from" => 0, "to" => 7},
                                                                                            "02" => {"position" => 8, "from" => 0, "to" => 7}}},        
);


my %commands = (                             
  "remotePair"           => {"cmd" => {"noArg"    => "06010000000000000000"}},
  "remoteUnpair"         => {"cmd" => {"noArg"    => "06020000000000000000"}},
  "up"                   => {"cmd" => {"noArg"    => "0701tt00000000000000"}},
  "stop"                 => {"cmd" => {"noArg"    => "07020000000000000000"}},
  "down"                 => {"cmd" => {"noArg"    => "0703tt00000000000000"}},
  "position"             => {"cmd" => {"value"    => "0707ttnn000000000000"}, "invert" => 100},
  "level"                => {"cmd" => {"value"    => "0707ttnn000000000000"}},
  "sunMode"              => {"cmd" => {"on"       => "070801FF000000000000",
                                       "off"      => "070A0100000000000000"}},
  "dusk"                 => {"cmd" => {"noArg"    => "070901FF000000000000"}},
  "reversal"             => {"cmd" => {"noArg"    => "070C0000000000000000"}},
  "modeChange"           => {"cmd" => {"noArg"    => "070C0000000000000000"}},
  "windMode"             => {"cmd" => {"on"       => "070D01FF000000000000",
                                       "off"      => "070E0100000000000000"}},
  "rainMode"             => {"cmd" => {"on"       => "071101FF000000000000",
                                       "off"      => "07120100000000000000"}},
  "dawn"                 => {"cmd" => {"noArg"    => "071301FF000000000000"}},
  "rainDirection"        => {"cmd" => {"down"     => "071400FD000000000000",
                                       "up"       => "071400FE000000000000"}},
  "windDirection"        => {"cmd" => {"down"     => "071500FD000000000000",
                                       "up"       => "071500FE000000000000"}},
  "tempUp"               => {"cmd" => {"noArg"    => "0718tt00000000000000"}}, 
  "tempDown"             => {"cmd" => {"noArg"    => "0719tt00000000000000"}}, 
  "toggle"               => {"cmd" => {"noArg"    => "071A0000000000000000"}},
  "slatPosition"         => {"cmd" => {"value"    => "071B00000000nn000000"}},
  "desired-temp"         => {"cmd" => {"value"    => "0722tt0000wwww000000"}, "min" => -40, "max" => 80, "multi" => 10,  "offset" => 400 },
  "sunAutomatic"         => {"cmd" => {"on"       => "080100FD000000000000",
                                       "off"      => "080100FE000000000000"}},
  "sunPosition"          => {"cmd" => {"value"    => "080100nn000000000000"}, "invert" => 100},
  "ventilatingMode"      => {"cmd" => {"on"       => "080200FD000000000000",
                                       "off"      => "080200FE000000000000"}},
  "ventilatingPosition"  => {"cmd" => {"value"    => "080200nn000000000000"}, "invert" => 100},
  "intermediateMode"     => {"cmd" => {"on"       => "080200FD000000000000",
                                       "off"      => "080200FE000000000000"}},
  "intermediateValue"    => {"cmd" => {"value"    => "080200nn000000000000"}},
  "saveIntermediateOnStop"=>{"cmd" => {"on"       => "080200FB000000000000",
                                       "off"      => "080200FC000000000000"}},
  "runningTime"          => {"cmd" => {"value"    => "0803nn00000000000000"}, "min" => 0, "max" => 150 },
  "timeAutomatic"        => {"cmd" => {"on"       => "080400FD000000000000",
                                       "off"      => "080400FE000000000000"}},
  "duskAutomatic"        => {"cmd" => {"on"       => "080500FD000000000000",
                                       "off"      => "080500FE000000000000"}},                           
  "manualMode"           => {"cmd" => {"on"       => "080600FD000000000000",
                                       "off"      => "080600FE000000000000"}},
  "windAutomatic"        => {"cmd" => {"on"       => "080700FD000000000000",
                                       "off"      => "080700FE000000000000"}},
  "rainAutomatic"        => {"cmd" => {"on"       => "080800FD000000000000",
                                       "off"      => "080800FE000000000000"}},                                                      
  "dawnAutomatic"        => {"cmd" => {"on"       => "080900FD000000000000",
                                       "off"      => "080900FE000000000000"}},
  "tiltInSunPos"         => {"cmd" => {"on"       => "080C00FD000000000000",
                                       "off"      => "080C00FE000000000000"}},                           
  "tiltInVentPos"        => {"cmd" => {"on"       => "080D00FD000000000000",
                                       "off"      => "080D00FE000000000000"}},
  "tiltAfterMoveLevel"   => {"cmd" => {"on"       => "080E00FD000000000000",
                                       "off"      => "080E00FE000000000000"}},
  "tiltAfterStopDown"    => {"cmd" => {"on"       => "080F00FD000000000000",
                                       "off"      => "080F00FE000000000000"}},                           
  "defaultSlatPos"       => {"cmd" => {"value"    => "0810nn00000000000000"}},
  "blindsMode"           => {"cmd" => {"on"       => "081100FD000000000000",
                                       "off"      => "081100FE000000000000"}}, 
  "slatRunTime"          => {"cmd" => {"value"    => "0812nn00000000000000"}, "min" => 0, "max" => 50 },                                                        
  "motorDeadTime"        => {"cmd" => {"off"      => "08130000000000000000",
                                       "short"    => "08130100000000000000",
                                       "long"     => "08130200000000000000"}},
  "stairwellFunction"    => {"cmd" => {"on"       => "081400FD000000000000",
                                       "off"      => "081400FE000000000000"}},
  "stairwellTime"        => {"cmd" => {"value"    => "08140000wwww00000000"}, "min" => 0, "max" => 3200, "multi" => 10},
  "reset"                => {"cmd" => {"settings" => "0815CB00000000000000",
                                       "full"     => "0815CC00000000000000"}},
  "10minuteAlarm"        => {"cmd" => {"on"       => "081700FD000000000000",
                                       "off"      => "081700FE000000000000"}},
  "automaticClosing"     => {"cmd" => {"off"      => "08180000000000000000",
                                       "30"       => "08180001000000000000",
                                       "60"       => "08180002000000000000",
                                       "90"       => "08180003000000000000",
                                       "120"      => "08180004000000000000",
                                       "150"      => "08180005000000000000",
                                       "180"      => "08180006000000000000",
                                       "210"      => "08180007000000000000",
                                       "240"      => "08180008000000000000"}},
  "2000cycleAlarm"       => {"cmd" => {"on"       => "081900FD000000000000",
                                       "off"      => "081900FE000000000000"}},
  "openSpeed"            => {"cmd" => {"11"       => "081A0001000000000000",
                                       "15"       => "081A0002000000000000",
                                       "19"       => "081A0003000000000000"}},
  "backJump"             => {"cmd" => {"on"       => "081B00FD000000000000",
                                       "off"      => "081B00FE000000000000"}},
  "temperatureThreshold1"=> {"cmd" => {"value"    => "081E00000001nn000000"}, "min" => -40, "max" => 80, "multi" => 2,  "offset" => 80 },                           
  "temperatureThreshold2"=> {"cmd" => {"value"    => "081E0000000200nn0000"}, "min" => -40, "max" => 80, "multi" => 2,  "offset" => 80 },
  "temperatureThreshold3"=> {"cmd" => {"value"    => "081E000000040000nn00"}, "min" => -40, "max" => 80, "multi" => 2,  "offset" => 80 },
  "temperatureThreshold4"=> {"cmd" => {"value"    => "081E00000008000000nn"}, "min" => -40, "max" => 80, "multi" => 2,  "offset" => 80 },
  "actTempLimit"         => {"cmd" => {"1"        => "081Ett00001000000000",
                                       "2"        => "081Ett00003000000000",
                                       "3"        => "081Ett00005000000000",
                                       "4"        => "081Ett00007000000000"}},                        
  "on"                   => {"cmd" => {"noArg"    => "0E03tt00000000000000"}},
  "off"                  => {"cmd" => {"noArg"    => "0E02tt00000000000000"}},                                                                                                             
);

my %wCmds = (                             
  "interval"              => {"enable"  => 0x80,    "min"     => 1,     "max"     => 100,   "offset"  => 0,
                              "reg"     => 7,       "byte"    => 0,     "size"    => 1,     "count"   => 1,
                              "mask"    => 0xff,    "shift"   =>0},
  "DCF"                   => {"enable"  => 0x02,    "min"     => 0,     "max"     => 0,     "offset"  => 0,
                              "reg"     => 7,       "byte"    => 1,     "size"    => 1,     "count"   => 1,
                              "mask"    => 0x02,    "shift"   =>0},
  "timezone"              => {"enable"  => 0x00,    "min"     => 0,     "max"     => 23,    "offset"  => 0,
                              "reg"     => 7,       "byte"    => 4,     "size"    => 1,     "count"   => 1,
                              "mask"    => 0xff,    "shift"   =>0},
  "latitude"              => {"enable"  => 0x00,    "min"     => 0,     "max"     => 90,    "offset"  => 0,
                              "reg"     => 7,       "byte"    => 5,     "size"    => 1,     "count"   => 1,
                              "mask"    => 0xff,    "shift"   =>0},
  "longitude"             => {"enable"  => 0x00,    "min"     => -90,   "max"     => 90,    "offset"  => 256,
                              "reg"     => 7,       "byte"    => 7,     "size"    => 1,     "count"   => 1,
                              "mask"    => 0xff,    "shift"   =>0},
  "triggerWind"           => {"enable"  => 0x20,    "min"     => 1,     "max"     => 31,    "offset"  => 0,
                              "reg"     => 6,       "byte"    => 0,     "size"    => 1,     "count"   => 5,
                              "mask"    => 0x7f,    "shift"   =>0},
  "triggerRain"           => {"enable"  => 0x80,    "min"     => 0,     "max"     => 0,     "offset"  => 0,
                              "reg"     => 6,       "byte"    => 0,     "size"    => 1,     "count"   => 1,
                              "mask"    => 0x80,    "shift"   =>0},
  "triggerTemperature"    => {"enable"  => 0x80,    "min"     => -40,   "max"     => 80,    "offset"  => 40,
                              "reg"     => 6,       "byte"    => 5,     "size"    => 1,     "count"   => 5,
                              "mask"    => 0xff,    "shift"   =>0},
  "triggerDawn"           => {"enable"  => 0x10000000,"min"   => 1,     "max"     => 100,   "offset"  => -1,
                              "reg"     => 0,         "byte"  => 0,     "size"    => 4,     "count"   => 5,
                              "mask"    => 0x1000007F,"shift" =>0},
  "triggerDusk"           => {"enable"  => 0x20000000,"min"   => 1,     "max"     => 100,   "offset"  => -1,
                              "reg"     => 0,         "byte"  => 0,     "size"    => 4,     "count"   => 5,
                              "mask"    => 0x201FC000,"shift" => 14},
  "triggerSun"            => {"enable"  => 0x20000000,"min"   => 1,     "max"     => 0x3FFFFFFF,   "offset"  => 0,
                              "reg"     => 3,         "byte"  => 0,     "size"    => 4,     "count"   => 5,
                              "mask"    => 0x3FFFFFC0,"shift" => 0},
  "triggerSunDirection"   => {"enable"  => 0x00,      "min"   => 1,     "max"     => 0xFF,  "offset"  => 0,
                              "reg"     => 3,         "byte"  => 1,     "size"    => 4,     "count"   => 5,
                              "mask"    => 0x000000FF,"shift" => 0},
  "triggerSunHeight"      => {"enable"  => 0x00,      "min"   => 1,     "max"     => 0x1FFF,"offset"  => 0,
                              "reg"     => 3,         "byte"  => 1,     "size"    => 4,     "count"   => 5,
                              "mask"    => 0x00001F80,"shift" => 0},                              
);

my %commandsStatus = (
  "getStatus"       => "0F",
  "getWeather"      => "13",
  "getTime"         => "10",
);

my %setsBasic = (
  "reset:settings,full"                 => "",
  "remotePair:noArg"                    => "",
  "remoteUnpair:noArg"                  => "",   
);

my %setsReset = (
  "reset:settings,full"                 => "",   
);

my %setsPair = (
  "remotePair:noArg"                    => "",
  "remoteUnpair:noArg"                  => "",   
);

my %setsDefaultRollerShutter = (
  "getStatus:noArg"                     => "",
  "up:noArg"                            => "",
  "down:noArg"                          => "",
  "stop:noArg"                          => "",
  "toggle:noArg"                        => "",
  "dusk:noArg"                          => "",
  "dawn:noArg"                          => "",
  "sunMode:on,off"                      => "",
  "position:slider,0,1,100"             => "",
  "sunPosition:slider,0,1,100"          => "",
  "ventilatingPosition:slider,0,1,100"  => "",
  "dawnAutomatic:on,off"                => "",
  "duskAutomatic:on,off"                => "",
  "manualMode:on,off"                   => "",
  "sunAutomatic:on,off"                 => "",
  "timeAutomatic:on,off"                => "",
  "ventilatingMode:on,off"              => "",
);

my %setsRolloTube = (
  "windAutomatic:on,off"                => "",
  "rainAutomatic:on,off"                => "",
  "windDirection:up,down"               => "",
  "rainDirection:up,down"               => "",
  "windMode:on,off"                     => "",
  "rainMode:on,off"                     => "",
  "reversal:on,off"                     => "",
);

my %setsTroll = (
  "windAutomatic:on,off"                => "",
  "rainAutomatic:on,off"                => "",
  "windDirection:up,down"               => "",
  "rainDirection:up,down"               => "",
  "windMode:on,off"                     => "",
  "rainMode:on,off"                     => "",
  "runningTime:slider,0,1,150"          => "",
  "motorDeadTime:off,short,long"        => "",
  "reversal:on,off"                     => "",    
);

my %setsBlinds = (
  "tiltInSunPos:on,off"                => "",
  "tiltInVentPos:on,off"               => "",
  "tiltAfterMoveLevel:on,off"          => "",
  "tiltAfterStopDown:on,off"           => "",
  "defaultSlatPos:slider,0,1,100"      => "",
  "slatRunTime:slider,0,1,50"          => "",
  "slatPosition:slider,0,1,100"        => "",   
);                            

my %setsSwitchActor = (
  "getStatus:noArg"                     => "",
  "dawnAutomatic:on,off"                => "",
  "duskAutomatic:on,off"                => "",
  "manualMode:on,off"                   => "",
  "sunAutomatic:on,off"                 => "",
  "timeAutomatic:on,off"                => "",
  "sunMode:on,off"                      => "",
  "modeChange:on,off"                   => "",
  "stairwellFunction:on,off"            => "",
  "stairwellTime:slider,0,10,3200"      => "",
  "on:noArg"                            => "",
  "off:noArg"                           => "",
  "dusk:noArg"                          => "",
  "dawn:noArg"                          => "",
);

my %setsUmweltsensor = (
  "getStatus:noArg"                     => "",
  "getWeather:noArg"                    => "",
  "getTime:noArg"                       => "",   
);

my %setsUmweltsensor00 = (
  "getWeather:noArg"                    => "",
  "getTime:noArg"                       => "",
  "getConfig:noArg"                     => "",
  "writeConfig:noArg"                   => "",
  "DCF:on,off"                          => "",
  "interval:off,1,2,3,4,5,6,7,8,9,10,15,20,30,40,50,60,70,80,90,100"      => "",
  "latitude"                            => "",
  "longitude"                           => "",
  "timezone"                            => "",
  "time:noArg"                          => "",
  "triggerDawn"                         => "",
  "triggerDusk"                         => "",
  "triggerRain:on,off"                  => "",   
  "triggerSun"                          => "",
  "triggerSunDirection"                 => "",
  "triggerSunHeight"                    => "",
  "triggerTemperature"                  => "",
  "triggerWind"                         => "",  
);

my %setsUmweltsensor01 = (
  "windAutomatic:on,off"                => "",
  "rainAutomatic:on,off"                => "",
  "windDirection:up,down"               => "",
  "rainDirection:up,down"               => "",
  "windMode:on,off"                     => "",
  "rainMode:on,off"                     => "",
  "runningTime:slider,0,1,100"          => "",
  "reversal:on,off"                     => "",   
);

my %setsSX5 = (
  "getStatus:noArg"                     => "",
  "up:noArg"                            => "",
  "down:noArg"                          => "",
  "stop:noArg"                          => "",
  "position:slider,0,1,100"             => "",
  "ventilatingPosition:slider,0,1,100"  => "",
  "manualMode:on,off"                   => "",
  "timeAutomatic:on,off"                => "",
  "ventilatingMode:on,off"              => "",
  "10minuteAlarm:on,off"                => "",
  "automaticClosing:off,30,60,90,120,150,180,210,240" => "",
  "2000cycleAlarm:on,off"               => "",
  "openSpeed:11,15,19"                  => "",
  "backJump:on,off"                     => "",
);

my %setsDimmer = (
  "getStatus:noArg"                     => "",
  "level:slider,0,1,100"                => "",
  "on:noArg"                            => "",
  "off:noArg"                           => "",
  "dawnAutomatic:on,off"                => "",
  "duskAutomatic:on,off"                => "",
  "manualMode:on,off"                   => "",
  "sunAutomatic:on,off"                 => "",
  "timeAutomatic:on,off"                => "",
  "sunMode:on,off"                      => "",
  "modeChange:on,off"                   => "",
  "stairwellFunction:on,off"            => "",
  "stairwellTime:slider,0,10,3200"      => "",
  "runningTime:slider,0,1,255"          => "",
  "intermediateMode:on,off"             => "",
  "intermediateValue:slider,0,1,100"    => "",
  "saveIntermediateOnStop:on,off"       => "",                         
  "dusk:noArg"                          => "",
  "dawn:noArg"                          => "",
);

my $tempSetList = "4.0,4.5,5.0,5.5,6.0,6.5,7.0,7.5,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0,28.5,29.0,29.5,30.0";

my %setsThermostat = (
  "getStatus:noArg"                     => "",
  "tempUp:noArg"                        => "",
  "tempDown:noArg"                      => "",
  "manualMode:on,off"                   => "",
  "timeAutomatic:on,off"                => "",
  "temperatureThreshold1:$tempSetList"  => "",
  "temperatureThreshold2:$tempSetList"  => "",
  "temperatureThreshold3:$tempSetList"  => "",
  "temperatureThreshold4:$tempSetList"  => "",
  "actTempLimit:1,2,3,4"                => "",
  "desired-temp:$tempSetList"           => "",
);
                        
my $duoStatusRequest      = "0DFFnn400000000000000000000000000000yyyyyy01";
my $duoCommand            = "0Dccnnnnnnnnnnnnnnnnnnnn000000zzzzzzyyyyyy00";
my $duoCommand2           = "0Dccnnnnnnnnnnnnnnnnnnnn000000000000yyyyyy01";
my $duoWeatherConfig      = "0D001B400000000000000000000000000000yyyyyy00";
my $duoWeatherWriteConfig = "0DFF1Brrnnnnnnnnnnnnnnnnnnnn00000000yyyyyy00";
my $duoSetTime            = "0D0110800001mmmmmmmmnnnnnn0000000000yyyyyy00";

#####################################
sub
DUOFERN_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^(06|0F).{42}";
  $hash->{SetFn}     = "DUOFERN_Set";
  $hash->{DefFn}     = "DUOFERN_Define";
  $hash->{UndefFn}   = "DUOFERN_Undef";
  $hash->{ParseFn}   = "DUOFERN_Parse";
  $hash->{RenameFn}  = "DUOFERN_Rename";
  $hash->{AttrFn}    = "DUOFERN_Attr";
  $hash->{AttrList}  = "IODev timeout toggleUpDown ignore:1,0 positionInverse:1,0 ". $readingFnAttributes;
  #$hash->{AutoCreate}=
  #      { "DUOFERN" => { GPLOT => "", FILTER => "%NAME" } };
}

###################################
sub
DUOFERN_Set($@)
{
  my ($hash, @a) = @_;
  my @b = @a;
  
  return "set $hash->{NAME} needs at least one parameter" if(@a < 2);

  my $me   = shift @a;
  my $cmd  = shift @a;
  my $arg  = shift @a;
  my $arg2 = shift @a;
  my $code = substr($hash->{CODE},0,6);
  my $name = $hash->{NAME};
    
  my %sets;
  
  %sets = (%setsBasic, %setsDefaultRollerShutter, %setsRolloTube)             if ($hash->{CODE} =~ /^49..../);
  %sets = (%setsBasic, %setsDefaultRollerShutter, %setsTroll, ("blindsMode:on,off"=> "")) if ($hash->{CODE} =~ /^(42|4B|4C|70)..../);
  %sets = (%setsBasic, %setsDefaultRollerShutter, %setsTroll)                 if ($hash->{CODE} =~ /^47..../);
  %sets = (%setsBasic, %setsDefaultRollerShutter)                             if ($hash->{CODE} =~ /^(40|41|61)..../);
  %sets = (%setsReset, %setsUmweltsensor)                                     if ($hash->{CODE} =~ /^69....$/);
  %sets = (%setsUmweltsensor00)                                               if ($hash->{CODE} =~ /^69....00/);  
  %sets = (%setsDefaultRollerShutter, %setsUmweltsensor01, %setsPair)         if ($hash->{CODE} =~ /^69....01/);
  %sets = (%setsSwitchActor, %setsPair)                                       if ($hash->{CODE} =~ /^43....(01|02)/);
  %sets = (%setsReset, "getStatus:noArg"=> "")                                if ($hash->{CODE} =~ /^(43|65|74)....$/);
  %sets = (%setsBasic, %setsSwitchActor)                                      if ($hash->{CODE} =~ /^(46|71)..../);
  %sets = (%setsBasic, %setsSX5)                                              if ($hash->{CODE} =~ /^4E..../);
  %sets = (%setsBasic, %setsDimmer)                                           if ($hash->{CODE} =~ /^48..../);
  %sets = (%setsBasic, %setsThermostat)                                       if ($hash->{CODE} =~ /^73..../);
  %sets = (%setsSwitchActor, %setsPair)                                       if ($hash->{CODE} =~ /^(65|74)....01/);

  my $blindsMode=ReadingsVal($name, "blindsMode", "off");
  %sets = (%sets, %setsBlinds)    if ($blindsMode eq "on");
  
  my $list =  join(" ", sort keys %sets);
   
  if (exists $commandsStatus{$cmd}) { 
    my $buf = $duoStatusRequest;
    $buf =~ s/nn/$commandsStatus{$cmd}/;
    $buf =~ s/yyyyyy/$code/;
    
    IOWrite( $hash, $buf );
    return undef;
    
  } elsif ($cmd eq "clear") { 
    my @cH = ($hash);
    delete $_->{READINGS} foreach (@cH);
    return undef;

  } elsif ($cmd eq "getConfig") { 
    my $buf = $duoWeatherConfig;
    $buf =~ s/yyyyyy/$code/;
    
    IOWrite( $hash, $buf );
    return undef;
    
  } elsif ($cmd eq "writeConfig") { 
    my $buf;
    
    for(my $x=0; $x<8; $x++)  {
      my $regV = ReadingsVal($name, ".reg$x", "00000000000000000000");
      my $reg = sprintf("%02x",$x+0x81);
      $buf= $duoWeatherWriteConfig;
      $buf =~ s/yyyyyy/$code/;
      $buf =~ s/rr/$reg/;
      $buf =~ s/nnnnnnnnnnnnnnnnnnnn/$regV/;
    
      IOWrite( $hash, $buf );
      
    }
    
    delete $hash->{READINGS}{configModified};
    return undef;
  
  } elsif ($cmd eq "time") {
    my $buf = $duoSetTime;
    
    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
    
    $wday = ($wday==0 ? 7 : $wday-1);
    my $m = sprintf("%02d%02d%02d%02d", $year-100, $month+1,$wday, $mday);
    my $n = sprintf("%02d%02d%02d", $hour, $min, $sec);

    $buf =~ s/mmmmmmmm/$m/;
    $buf =~ s/nnnnnn/$n/;
    $buf =~ s/yyyyyy/$code/;
    
    IOWrite( $hash, $buf );
    return undef;   
    
  } elsif (exists $wCmds{$cmd}) { 
    return "This command is not allowed for this device." if ($hash->{CODE} !~ /^69....00/);  

    my $regs;
    my @regsA;
    my @args = @b;
    my $reg;
            
    splice(@args,0,2);
    return "Missing argument" if(@args < 1);
    splice(@args,@args,0,"off","off","off","off");
    
    for(my $x=0; $x<8; $x++)  {
      $regs .= ReadingsVal($name, ".reg$x", "00000000000000000000");  
    } 
    
    if ($cmd eq "triggerSun") {
      foreach (@args)  {
        if ($_ ne "off") {
          my @args2 = split(/:/, $_);
          my $temp = $_;
          return "Missing argument" if(@args2 < 3);
          return "Wrong argument $_" if ($args2[0] !~ m/^\d+$/ || $args2[0] < 1 || $args2[0] > 100);
          return "Wrong argument $_" if ($args2[1] !~ m/^\d+$/ || $args2[1] < 1 || $args2[1] > 30);
          return "Wrong argument $_" if ($args2[2] !~ m/^\d+$/ || $args2[2] < 1 || $args2[2] > 30);
          $_ = (($args2[0]-1)<<12) | (($args2[1]-1)<<19) | (($args2[2]-1)<<24);
          
          if(@args2 > 3) {
            return "Wrong argument $temp" if ($args2[3] !~ m/^[-\d]+$/ || $args2[3] < -5 || $args2[3] > 26);
            $_ |= ((($args2[3]+5)<<7) | 0x40);
          };
        }
      }
    }
    
    if ($cmd eq "triggerSunDirection") {
      for(my $x=0; $x<5; $x++)  {
        if ($args[$x] ne "off") {
          my @args2 = split(/:/, $args[$x]);
          return "Missing argument" if(@args2 < 2);
          return "Wrong argument $args[$x]" if ($args2[0] !~ m/^\d+(\.\d+|)$/ || $args2[0] < 0 || $args2[0] > 315);
          return "Wrong argument $args[$x]" if ($args2[1] !~ m/^\d+$/ || $args2[1] < 45 || $args2[1] > 180);
          $args2[0] = int(($args2[0]+11.25)/22.5);
          $args2[1] = int(($args2[1]+22.5)/45);
          $args2[0] = 15 - ($args2[1]*2) if (($args2[0] + $args2[1]*2) > 15);
          $args[$x] = ($args2[0]+$args2[1]) | (($args2[1])<<4) | 0x80;
        } else {
          my @tSunHeight = map{hex($_)} unpack 'x66A2x8A2x8A2x8A2x8A2', $regs;
          if ($tSunHeight[$x] & 0x18) {
            $args[$x] = 0x81;
          } else {
            $args[$x] = 0x01;
          }
        }
      }
    }
    
    if ($cmd eq "triggerSunHeight") {
      for(my $x=0; $x<5; $x++)  {
        if ($args[$x] ne "off") {
          my @args2 = split(/:/, $args[$x]);
          return "Missing argument" if(@args2 < 2);
          return "Wrong argument1 $args[$x]" if ($args2[0] !~ m/^\d+$/ || $args2[0] < 0 || $args2[0] > 90);
          return "Wrong argument2 $args[$x]" if ($args2[1] !~ m/^\d+$/ || $args2[1] < 20 || $args2[1] > 60);     
          $args2[0] = int(($args2[0]+6.5)/13);
          $args2[1] = int(($args2[1]+13)/26);
          $args2[0] = 7 - ($args2[1]*2) if (($args2[0] + $args2[1]*2) > 7);   
          $args[$x] = (($args2[0]+$args2[1])<<8) | (($args2[1])<<11) | 0x80;
        } else {
          my @tSunDir = map{hex($_)} unpack 'x68A2x8A2x8A2x8A2x8A2', $regs;
          if ($tSunDir[$x] & 0x70) {
            $args[$x] = 0x0180;
          } else {
            $args[$x] = 0x0100;
          }
        }
      }
    }   
      
    for (my $c = 0; $c<$wCmds{$cmd}{count}; $c++) {
      my $pad = 0;
      
      if ($wCmds{$cmd}{size} == 4) {
        $pad = int($c / 2)*2;
        $pad = $c if ($cmd =~ m/^triggerSun.*/);
      };
      my $regStart = ($wCmds{$cmd}{reg} * 10 + $wCmds{$cmd}{byte} + $pad + $c * $wCmds{$cmd}{size} )*2;
      
      $reg = hex(substr($regs, $regStart, $wCmds{$cmd}{size} * 2));
      
      if(($args[$c] =~ m/^[-\d]+$/) && ($args[$c] >=  $wCmds{$cmd}{min}) && ($args[$c] <=  $wCmds{$cmd}{max})) {
        $reg &= ~($wCmds{$cmd}{mask});
        $reg |= $wCmds{$cmd}{enable};
        $reg |= (($args[$c] +  $wCmds{$cmd}{offset})<<$wCmds{$cmd}{shift}) & $wCmds{$cmd}{mask} ;
      
      } elsif (($args[$c] eq "off") && ($wCmds{$cmd}{enable} > 0)) {
        $reg &= ~($wCmds{$cmd}{enable});
        
      } elsif (($args[$c] eq "on") && ($wCmds{$cmd}{min} == 0) && ($wCmds{$cmd}{max} == 0)) {
        $reg |= $wCmds{$cmd}{enable};
        
      } else {
        return "wrong argument ".$args[$c];
        
      }
      
      my $size = $wCmds{$cmd}{size}*2;
      
      substr($regs, $regStart ,$size, sprintf("%0".$size."x",$reg));
      
    }
  
    @regsA = unpack('(A20)*', $regs);
    
    readingsBeginUpdate($hash);
    for(my $x=0; $x<8; $x++)  {
      readingsBulkUpdate($hash, ".reg$x", $regsA[$x], 0);
      #readingsBulkUpdate($hash, "reg$x", $regsA[$x], 0);
    }
    readingsBulkUpdate($hash, "configModified", 1, 0);
    readingsEndUpdate($hash, 1);

    DUOFERN_DecodeWeatherSensorConfig($hash);
    return undef;
      
  } elsif(exists $commands{$cmd}) {
    my $subCmd;
    my $chanNo = "01";
    my $argV = "00";
    my $argW = "0000";
    my $timer ="00";
    my $buf;
    my $command;
    my $positionInverse = AttrVal($name,"positionInverse",0);
    
    if ($cmd eq "remotePair") {
      $buf = $duoCommand2;
    } else {
      $buf = $duoCommand;
    }
    
    $chanNo = $hash->{chanNo} if ($hash->{chanNo});
    
    if(exists $commands{$cmd}{cmd}{noArg}) {
      $timer= "01" if ($arg && ($arg eq "timer"));
      $subCmd = "noArg";
      $argV = "00";
      
    } elsif (exists $commands{$cmd}{cmd}{value}) {
      $timer= "01" if ($arg2 && ($arg2 eq "timer"));
      my $maxArg = (exists $commands{$cmd}{max}     ? $commands{$cmd}{max}    : 100);
      my $minArg = (exists $commands{$cmd}{min}     ? $commands{$cmd}{min}    : 0);
      my $mulArg = (exists $commands{$cmd}{multi}   ? $commands{$cmd}{multi}  : 1);
      my $offArg = (exists $commands{$cmd}{offset}  ? $commands{$cmd}{offset} : 0);
      $maxArg = 255 if (($code =~ m/^48..../) && ($cmd eq "runningTime"));
      return "Missing argument" if (!defined($arg)); 
      return "Wrong argument $arg" if ($arg !~ m/^\d+(\.\d+|)$/ || $arg < $minArg || $arg > $maxArg);	
      $subCmd = "value";
      if((exists $commands{$cmd}{invert}) && ($positionInverse eq "1")) {
        $arg = $commands{$cmd}{invert} - $arg;
      }
      $argV = sprintf "%02x", $arg * $mulArg + $offArg;
      $argW = sprintf "%04x", $arg * $mulArg + $offArg;
                             
    } else {
      return "Missing argument" if (!defined($arg));
      $timer= "01" if ($arg2 && ($arg2 eq "timer")); 
      $subCmd = $arg;
      $argV = "00";
    }
    
    return "Wrong argument $arg" if (!exists $commands{$cmd}{cmd}{$subCmd});
             
    my $position      = ReadingsVal($name, "position", -1);
    my $toggleUpDown  = AttrVal($name, "toggleUpDown", "0");
    my $moving        = ReadingsVal($name, "moving", "stop");
    my $timeAutomatic = ReadingsVal($name, "timeAutomatic", "on");
    my $dawnAutomatic = ReadingsVal($name, "dawnAutomatic", "on");
    my $duskAutomatic = ReadingsVal($name, "duskAutomatic", "on");
    
    if(($positionInverse eq "1")) {
      $position = 100 - $position;
    }
        
    if ($moving ne "stop") {
      if ($cmd =~ m/^(up|down|toggle)$/) {
        $cmd = "stop" if ($toggleUpDown);
      } 
    }
    
    readingsSingleUpdate($hash, "moving", "moving", 1) if (($cmd eq "toggle") && ($position > -1));
    readingsSingleUpdate($hash, "moving", "up", 1)     if (($cmd eq "dawn") && ($dawnAutomatic eq "on") && ($position > 0));
    readingsSingleUpdate($hash, "moving", "down", 1)   if (($cmd eq "dusk") && ($duskAutomatic eq "on") && ($position < 100) && ($position > -1));
    
    if ($timer eq "00" || $timeAutomatic eq "on") {
      readingsSingleUpdate($hash, "moving", "up", 1)   if (($cmd eq "up")   && ($position > 0));
      readingsSingleUpdate($hash, "moving", "down", 1) if (($cmd eq "down") && ($position < 100) && ($position > -1));
    }
     
    if ($cmd eq "position") {
      if ($arg > $position) {
        readingsSingleUpdate($hash, "moving", "down", 1);
      } elsif ($arg < $position) {
        readingsSingleUpdate($hash, "moving", "up", 1);
      } else {
        readingsSingleUpdate($hash, "moving", "stop", 1);
      }
    }
    
    $command = $commands{$cmd}{cmd}{$subCmd};
    
    $buf =~ s/yyyyyy/$code/;
    $buf =~ s/nnnnnnnnnnnnnnnnnnnn/$command/;
    $buf =~ s/nn/$argV/;
    $buf =~ s/tt/$timer/;
    $buf =~ s/wwww/$argW/;
    $buf =~ s/cc/$chanNo/;

    IOWrite( $hash, $buf );
    
    if ($hash->{device}) {
      $hash = $defs{$hash->{device}};
    }
    
    my $ret = "set_".$cmd;
    $ret = $ret." ".$arg if($arg);
    $ret = $ret." ".$arg2 if($arg2);
    
    DoTrigger($name, $ret);
    
    return ("",1);   
  }
  
  return SetExtensions($hash, $list, @b); 
}

#####################################
sub
DUOFERN_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> DUOFERN <code>"
            if(int(@a) < 3 || int(@a) > 5);
  return "Define $a[0]: wrong CODE format: specify a 6 digit hex value"
                if($a[2] !~ m/^[a-f0-9]{6,8}$/i);

  my $code = uc($a[2]);
  $hash->{CODE} = $code;
  my $name = $hash->{NAME};
  
  if(length($code) == 8) {# define a channel
    my $chn = substr($code, 6, 2);
    my $devCode = substr($code, 0, 6);
    
    my $devHash = $modules{DUOFERN}{defptr}{$devCode};
    return "please define a device with code:".$devCode." first" if(!$devHash);

    my $devName = $devHash->{NAME};
    $hash->{device} = $devName;          #readable ref to device name
    $hash->{chanNo} = $chn;              #readable ref to Channel
    $devHash->{"channel_$chn"} = $name;  #reference in device as well
    
  }
  
  $modules{DUOFERN}{defptr}{$code} = $hash;
  
  AssignIoPort($hash);
  
  if (exists $devices{substr($hash->{CODE},0,2)}) {
  	$hash->{SUBTYPE} = $devices{substr($hash->{CODE},0,2)}{name};
  	$hash->{MODEL} = $devices{substr($hash->{CODE},0,2)}{name};
  } else {
  	$hash->{SUBTYPE} = "unknown";
  }
  
  readingsSingleUpdate($hash, "state", "Initialized", 1);
  
 return undef if (AttrVal($name,"ignore",0) != 0);
  
  if ($hash->{CODE} =~ m/^(40|41|42|43|46|47|48|49|4B|4C|4E|61|62|65|69|70|71|73|74)....$/) {
    $hash->{helper}{timeout}{t} = 30;
    InternalTimer(gettimeofday()+$hash->{helper}{timeout}{t}, "DUOFERN_StatusTimeout", $hash, 0);
    $hash->{helper}{timeout}{count} = 2;
  }
    
  
  return undef;
}

#####################################
sub 
DUOFERN_Undef($$) 
{
  my ($hash, $name) = @_;
  my $devName = $hash->{device};
  my $code = $hash->{DEF};
  my $chn = substr($code,6,2);
  if ($chn){# delete a channel
    my $devHash = $defs{$devName};
    delete $devHash->{"channel_$chn"} if ($devName);
  }
  else{# delete a device
    CommandDelete(undef,$hash->{$_}) foreach (grep(/^channel_/,keys %{$hash}));
  }
  delete($modules{CUL_HM}{defptr}{$code});
  return undef;
}

#####################################
sub
DUOFERN_Rename($$$) 
{
  my ($name, $oldName) = @_;
  my $hash = $defs{$name};
  if ($hash->{chanNo}) {# we are channel, inform the device
    my $devHash = $defs{$hash->{device}};
    $devHash->{"channel_".$hash->{chanNo}} = $name;
  
  } else {# we are a device - inform channels if exist
    foreach (grep (/^channel_/, keys%{$hash})){
      my $chnHash = $defs{$hash->{$_}};
      $chnHash->{device} = $name;
    }
  }
  return;
}

#####################################
sub
DUOFERN_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  if($aName eq "timeout") {
    if ($cmd eq "set"){
      return "timeout must be between 0 and 180" if ($aVal !~ m/^\d+$/ || $aVal < 0 || $aVal > 180);
    }
  }  

  return undef;
}

#####################################
sub
DUOFERN_Parse($$)
{
  my ($hash,$msg) = @_;

  my $code = substr($msg,30,6);
  $code = substr($msg,36,6) if ($msg =~ m/81.{42}/);

  return $hash->{NAME} if ($code eq "FFFFFF");
  
  my $def = $modules{DUOFERN}{defptr}{$code};
   
  my $def01;
  my $def02;
  
  if(!$def) {
    DoTrigger("global","UNDEFINED DUOFERN_$code DUOFERN $code");
    $def = $modules{DUOFERN}{defptr}{$code};
    if(!$def) {
      Log3 $hash, 4, "DUOFERN UNDEFINED, code $code";
      return "UNDEFINED DUOFERN_$code DUOFERN $code $msg";
    }
  }
  
  $hash = $def;
  my $name = $hash->{NAME};  
  
  return $name if (AttrVal($name,"ignore",0) != 0);
  
  #Device paired
  if ($msg =~ m/0602.{40}/) {
    readingsSingleUpdate($hash, "state", "paired", 1);
    delete $hash->{READINGS}{unpaired};
    Log3 $hash, 1, "DUOFERN device paired, code $code";
  
  #Device unpaired
  } elsif ($msg =~ m/0603.{40}/) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "unpaired", 1  , 1);
    readingsBulkUpdate($hash, "state", "unpaired"  , 1);
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch
    Log3 $hash, 1, "DUOFERN device unpaired, code $code";
  
  #Status Nachricht Aktor
  } elsif ($msg =~ m/0FFF0F.{38}/) {
    my $format = substr($msg, 6, 2);
    my $ver    = substr($msg, 24, 1).".".substr($msg, 25, 1);
    my $state;   
    my @chHash;
    
    if(exists $devices{substr($code,0,2)}{format}) {
      $format = $devices{substr($code,0,2)}{format};
    }
    
    readingsSingleUpdate($hash, "version", $ver, 0);
    
    RemoveInternalTimer($hash);
    delete $hash->{helper}{timeout};
    
    if(exists $devices{substr($code,0,2)}{chans}) {
      readingsSingleUpdate($hash, "state", "OK", 1);
      foreach my $chan (@{$devices{substr($code,0,2)}{chans}}) {
        my $defChan = $modules{DUOFERN}{defptr}{$code.$chan};
        if(!$defChan) {
          DoTrigger("global","UNDEFINED DUOFERN_$code"."_$chan DUOFERN $code".$chan);
          $defChan = $modules{DUOFERN}{defptr}{$code.$chan};
        }
        push(@chHash,$defChan);
      }     
    } else {
      push(@chHash,$hash);
    }
        
    if(exists $statusGroups{$format}) {
      foreach my $hashA (@chHash){
        my %statusValue;
        my $positionInverse = AttrVal($name,"positionInverse",0);
        
        readingsBeginUpdate($hashA);
        
        foreach my $statusId (@{$statusGroups{$format}}) {
     
          if(exists $statusIds{$statusId}) {
            
            my $chan= (exists $hashA->{chanNo} ? $hashA->{chanNo} : "01");
            
            my $stName  = $statusIds{$statusId}{name};
            my $stPos   = $statusIds{$statusId}{chan}{$chan}{position};    
            my $stFrom  = $statusIds{$statusId}{chan}{$chan}{from};
            my $stTo    = $statusIds{$statusId}{chan}{$chan}{to};
            my $stLen   = $stTo - $stFrom + 1;
            
            my $value = hex(substr($msg, ($stLen > 8 ? 6 : 8) + $stPos*2, ($stLen > 8 ? 4 : 2)));
            $value = ($value >> $stFrom) & ((1<<$stLen) - 1);
            
            if((exists $statusIds{$statusId}{invert}) && ($positionInverse eq "1")) {
              $value = $statusIds{$statusId}{invert} - $value;
            }
            
            if((exists $statusIds{$statusId}{map}) && (exists $statusMapping{$statusIds{$statusId}{map}})) {
              
              if ($statusIds{$statusId}{map} =~ m/scaleF.*/) {
                $value = sprintf("%0.1f",($value - $statusMapping{$statusIds{$statusId}{map}}[1]) / $statusMapping{$statusIds{$statusId}{map}}[0]);
              } elsif ($statusIds{$statusId}{map} =~ m/scale.*/) {
                $value = ($value - $statusMapping{$statusIds{$statusId}{map}}[1]) / $statusMapping{$statusIds{$statusId}{map}}[0];
              } else {
                $value = $statusMapping{$statusIds{$statusId}{map}}[$value];
              }    
            }
            
            $statusValue{$stName} = $value;
            readingsBulkUpdate($hashA, $stName,  $value,     1);
          }
        }
        
        if (defined($statusValue{blindsMode}) && ($statusValue{blindsMode} eq "off")) {
          delete($hash->{READINGS}{tiltInSunPos});
          delete($hash->{READINGS}{tiltInVentPos});
          delete($hash->{READINGS}{tiltAfterMoveLevel});
          delete($hash->{READINGS}{tiltAfterStopDown});
          delete($hash->{READINGS}{defaultSlatPos});
          delete($hash->{READINGS}{slatRunTime});
          delete($hash->{READINGS}{slatPosition});
        }
        
        $state = "x";
        if ($format =~ m/^(21|23|23a|24|24a)/) { 
          $state = $statusValue{position} if defined($statusValue{position});
          if($positionInverse eq "1") {
            $state = "opened"   if ($state eq "100");
            $state = "closed"   if ($state eq "0");
          } else {
            $state = "opened"   if ($state eq "0");
            $state = "closed"   if ($state eq "100");
          }      
        
        } elsif ($format =~ m/^(22|25)/) {  
          $state = $statusValue{level} if defined($statusValue{level});
          $state = "off"   if ($state eq "0");
          $state = "on"    if ($state eq "100");
                     
        } elsif ($format =~ m/^(27)/) {  
          my $temperature1 = "x";
          my $desiredTemp  = "x";
          $temperature1 = $statusValue{"measured-temp"} if defined($statusValue{"measured-temp"});
          $desiredTemp  = $statusValue{"desired-temp"} if defined($statusValue{"desired-temp"});
          $state = "T: $temperature1 desired: $desiredTemp";
                 
        }      
        
        $state = "light curtain"  if (defined($statusValue{"lightCurtain"}) && $statusValue{"lightCurtain"} eq "1");
        $state = "obstacle"       if (defined($statusValue{"obstacle"}) && $statusValue{"obstacle"} eq "1");
        $state = "block"          if (defined($statusValue{"block"}) && $statusValue{"block"} eq "1");
        readingsBulkUpdate($hashA, "state",  $state,     1);
          
        readingsEndUpdate($hashA, 1); # Notify is done by Dispatch 
        DoTrigger($hashA->{NAME}, undef);
      }

    } else {
      Log3 $hash, 3, "DUOFERN unknown msg: $msg";
    }
  
  #Wandtaster, Funksender UP, Handsender, Sensoren      
  } elsif ($msg =~ m/0F..(07|0E).{38}/) {
    my $id = substr($msg, 4, 4);
    
    if (!(exists $sensorMsg{$id})) {
      Log3 $hash, 3, "DUOFERN unknown msg: $msg";
    }
    
    my $chan = substr($msg, $sensorMsg{$id}{chan}*2 + 2 , 2);
    $chan = "01" if ($code =~ m/^(61|70|71)..../);
    
    my @chans;
    if ($sensorMsg{$id}{chan} == 5) {
      my $chanCount = 5;
      $chanCount = 4 if ($code =~ m/^(73)..../);
      for(my $x=0; $x<$chanCount; $x++)  {
        if((0x01<<$x) & hex($chan)) {
          push(@chans, $x+1);
        }  
      }
    } else {
      push(@chans, $chan);
    }
    
    if($code =~ m/^(65|69|74).*/) {
      $def01 = $modules{DUOFERN}{defptr}{$code."00"};
      if(!$def01) {
        DoTrigger("global","UNDEFINED DUOFERN_$code"."_sensor DUOFERN $code"."00");
        $def01 = $modules{DUOFERN}{defptr}{$code."00"};
      }
      $hash = $def01 if ($def01);
    } 
    
    foreach (@chans) {
      $chan = $_;
      if($id =~ m/..(1A|18|19|01|02|03)/) {
          if(($id =~ m/..1A/) || ($id =~ m/0E../) || ($code =~ m/^(A0|A2)..../)) {
              readingsSingleUpdate($hash, "state", $sensorMsg{$id}{state}.".".$chan, 1);
          } else {
              readingsSingleUpdate($hash, "state", $sensorMsg{$id}{state}, 1);
          }
          readingsSingleUpdate($hash, "channel$chan", $sensorMsg{$id}{name}, 1);
      } else {
        if(($code !~ m/^(69|73).*/) || ($id =~ m/..(11|12)/)) {
          $chan="";
        }
        if($code =~ m/^(65|A5|AA|AB)..../) {
          readingsSingleUpdate($hash, "state", $sensorMsg{$id}{state}, 1);
        }
        
        readingsSingleUpdate($hash, "event", $sensorMsg{$id}{name}.$chan, 1);
        DoTrigger($hash->{NAME},$sensorMsg{$id}{name}.$chan);
      }        
    }
  
  #Umweltsensor Wetter
  } elsif ($msg =~ m/0F011322.{36}/) {  
    $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    if(!$def01) {
      DoTrigger("global","UNDEFINED DUOFERN_$code"."_sensor DUOFERN $code"."00");
      $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    }
      
    $hash = $def01;
   
    my $brightnessExp   = (hex(substr($msg,  8, 4)) & 0x0400 ? 1000 : 1);
    my $brightness      = (hex(substr($msg,  8, 4)) & 0x01FF) * $brightnessExp;
    my $sunDirection    =  hex(substr($msg, 14, 2)) * 1.5 ;
    my $sunHeight       =  hex(substr($msg, 16, 2)) - 90 ;
    my $temperature     = ((hex(substr($msg, 18, 4)) & 0x7FFF)-400)/10 ;
    my $isRaining       = (hex(substr($msg, 18, 4)) & 0x8000 ? 1 : 0);
    my $wind            = (hex(substr($msg, 22, 4)) & 0x03FF) / 10;
    
    my $state = "T: ".$temperature;
    $state .= " W: ".$wind;
    $state .= " IR: ".$isRaining;
    $state .= " B: ".$brightness;
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "brightness",     $brightness,     1);
    readingsBulkUpdate($hash, "sunDirection",   $sunDirection,    1);
    readingsBulkUpdate($hash, "sunHeight",      $sunHeight,      1);
    readingsBulkUpdate($hash, "temperature",    $temperature,     1);
    readingsBulkUpdate($hash, "isRaining",      $isRaining,     1);
    readingsBulkUpdate($hash, "state",          $state,     1);
    readingsBulkUpdate($hash, "wind",           $wind,     1);
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch
  
  #Umweltsensor Zeit
  } elsif ($msg =~ m/0FFF1020.{36}/) {
    $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    if(!$def01) {
      DoTrigger("global","UNDEFINED DUOFERN_$code"."_sensor DUOFERN $code"."00");
      $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    }
      
    $hash = $def01;
    
    my $year    = substr($msg, 12, 2);
    my $month   = substr($msg, 14, 2);
    my $day     = substr($msg, 18, 2);
    my $hour    = substr($msg, 20, 2);
    my $minute  = substr($msg, 22, 2);
    my $second  = substr($msg, 24, 2);
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "date",   "20".$year."-".$month."-".$day,     1);
    readingsBulkUpdate($hash, "time",   $hour.":".$minute.":".$second,      1);
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch
  
  #Umweltsensor Konfiguration
  } elsif ($msg =~ m/0FFF1B2[1-8].{36}/) {
    my $reg    = substr($msg, 6, 2)-21;
    my $regVal = substr($msg, 8, 20);
    
    $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    if(!$def01) {
      DoTrigger("global","UNDEFINED DUOFERN_$code"."_sensor DUOFERN $code"."00");
      $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    }
      
    $hash = $def01;
    
    delete $hash->{READINGS}{configModified};
    readingsSingleUpdate($hash, ".reg$reg", "$regVal", 1);
    #readingsSingleUpdate($hash, "reg$reg", "$regVal", 1);
    DUOFERN_DecodeWeatherSensorConfig($hash);
    
  
  #Rauchmelder Batterie
  } elsif ($msg =~ m/0FFF1323.{36}/) {
    my $battery      = (hex(substr($msg,  8, 2)) <= 10 ? "low" : "ok");
    my $batteryLevel =  hex(substr($msg,  8, 2));
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "battery",          $battery,       1);
    readingsBulkUpdate($hash, "batteryLevel",     $batteryLevel,  1);
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch
  
  #ACK, Befehl vom Aktor empfangen
  } elsif ($msg =~ m/810003CC.{36}/) {
    $hash->{helper}{timeout}{t} = AttrVal($hash->{NAME}, "timeout", "60");    
    InternalTimer(gettimeofday()+$hash->{helper}{timeout}{t}, "DUOFERN_StatusTimeout", $hash, 0);
    $hash->{helper}{timeout}{count} = 4;
  
  #NACK, Befehl nicht vom Aktor empfangen
  } elsif ($msg =~ m/810108AA.{36}/) {
    readingsSingleUpdate($hash, "state", "MISSING ACK", 1);
    foreach (grep (/^channel_/, keys%{$hash})){
      my $chnHash = $defs{$hash->{$_}};
      readingsSingleUpdate($chnHash, "state", "MISSING ACK", 1);
    }
    Log3 $hash, 3, "DUOFERN error: $name MISSING ACK";
                   
  } else {
    Log3 $hash, 3, "DUOFERN unknown msg: $msg";
  }
  
  DoTrigger($def01->{NAME}, undef) if ($def01);
  DoTrigger($def02->{NAME}, undef) if ($def02);
  
  return $name;
}

#####################################
sub
DUOFERN_DecodeWeatherSensorConfig($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @regs;
  
  for(my $x=0; $x<8; $x++)  {
    $regs[$x] = ReadingsVal($name, ".reg$x", "00000000000000000000");  
  }
  
  my @tWind = map{hex($_)} unpack '(A2)*', substr($regs[6], 0,10);
  my @tTemp = map{hex($_)} unpack '(A2)*', substr($regs[6], 10,10);
  my @duskDawn = map{hex($_)} unpack '(A8)*', substr($regs[0],0,16).substr($regs[1],0,16).substr($regs[2],0,8);
  my @tDawn;
  my @tDusk;  
  my @tSun = map{hex($_)} unpack 'A8x2A8x2A8x2A8x2A8x2', $regs[3].$regs[4].$regs[5];
  my @tSunDir = map{hex($_)} unpack 'x8A2x8A2x8A2x8A2x8A2', $regs[3].$regs[4].$regs[5];
  my @tSunHeight = map{hex($_)} unpack 'x6A2x8A2x8A2x8A2x8A2', $regs[3].$regs[4].$regs[5];
  
  for(my $x=0; $x<5; $x++){   
    $tWind[$x] = ($tWind[$x] & 0x20 ? ($tWind[$x] & 0x1F) : "off");
    $tTemp[$x] = ($tTemp[$x] & 0x80 ? ($tTemp[$x] & 0x7F)-40 : "off");
    
    $tDawn[$x] = ($duskDawn[$x] & 0x7F) +1;
    $tDusk[$x] = (($duskDawn[$x]>>14) & 0x7F) +1;
    
    $tDawn[$x] = "off" if(!($duskDawn[$x]>>28 & 0x1));
    $tDusk[$x] = "off" if(!($duskDawn[$x]>>28 & 0x2));
    
    if((($tSun[$x])>>28) & 0x2) {
      my @temp;
      push(@temp,((($tSun[$x])>>12) & 0x7F) + 1);
      push(@temp,((($tSun[$x])>>19) & 0x1F) + 1);
      push(@temp,((($tSun[$x])>>24) & 0x1F) + 1);
      if($tSun[$x] & 0x40) {
        push(@temp,((($tSun[$x])>>7) & 0x1F) -5);
      }
      $tSun[$x]=join(":",@temp);
    } else {
      $tSun[$x]="off";
    }
    
    if((($tSunDir[$x])>>4) & 0x07) {
      my @temp;
      push(@temp,(($tSunDir[$x])) & 0x0F);
      push(@temp,(($tSunDir[$x])>>4) & 0x07);
      $temp[0] =($temp[0]-$temp[1]) * 22.5;
      $temp[1] = $temp[1] * 45; 
      $tSunDir[$x]=join(":",@temp);
    } else {
      $tSunDir[$x]="off";
    }
    
    if((($tSunHeight[$x])>>3) & 0x07) {
      my @temp;
      push(@temp,(($tSunHeight[$x])) & 0x07);
      push(@temp,(($tSunHeight[$x])>>3) & 0x03);
      $temp[0] =($temp[0]-$temp[1]) * 13;
      $temp[1] = $temp[1] * 26;
      $tSunHeight[$x]=join(":",@temp);
    } else {
      $tSunHeight[$x]="off";
    }
  }
  
  my $tRain           = (hex(substr($regs[6],  0, 2)) & 0x80 ? "on" : "off");
  my $interval        = (hex(substr($regs[7],  0, 2)) & 0x80 ? (hex(substr($regs[7],  0, 2)) & 0x7F) : "off");
  my $DCF             = (hex(substr($regs[7],  2, 2)) & 0x02 ? "on" : "off");
  my $latitude        =  hex(substr($regs[7], 10, 2));
  my $longitude       =  hex(substr($regs[7], 14, 2));
  my $timezone        =  hex(substr($regs[7],  8, 2));
  
  $latitude -= 256 if($latitude > 127);
  $longitude -= 256 if($longitude > 127);  
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "DCF",                $DCF,     1);
  readingsBulkUpdate($hash, "interval",           $interval,     1);
  readingsBulkUpdate($hash, "latitude",           $latitude,     1);
  readingsBulkUpdate($hash, "longitude",          $longitude,     1);
  readingsBulkUpdate($hash, "timezone",           $timezone,     1);
  readingsBulkUpdate($hash, "triggerRain",        $tRain,     1);
  readingsBulkUpdate($hash, "triggerTemperature", join(" ",@tTemp),     1);
  readingsBulkUpdate($hash, "triggerWind",        join(" ",@tWind),     1);
  readingsBulkUpdate($hash, "triggerDusk",        join(" ",@tDusk),     1);
  readingsBulkUpdate($hash, "triggerDawn",        join(" ",@tDawn),     1);
  readingsBulkUpdate($hash, "triggerSun",         join(" ",@tSun),      1);
  readingsBulkUpdate($hash, "triggerSunDirection",join(" ",@tSunDir),   1);
  readingsBulkUpdate($hash, "triggerSunHeight",   join(" ",@tSunHeight),1);
      
  readingsEndUpdate($hash, 1);
    
}

#####################################
sub
DUOFERN_StatusTimeout($)
{
    my ($hash) = @_;
    my $code = substr($hash->{CODE},0,6);
    my $name = $hash->{NAME};
    
    if ($hash->{helper}{timeout}{count} > 0) {
      my $buf = $duoStatusRequest;
      $buf =~ s/nn/$commandsStatus{getStatus}/;
      $buf =~ s/yyyyyy/$code/;
      
      if ($hash->{helper}{timeout}{cmd}) {
        IOWrite( $hash, $hash->{helper}{timeout}{cmd} );
      } else {
        IOWrite( $hash, $buf );
      }
      
      $hash->{helper}{timeout}{count} -= 1;
      InternalTimer(gettimeofday()+$hash->{helper}{timeout}{t}, "DUOFERN_StatusTimeout", $hash, 0);
      
      Log3 $hash, 3, "DUOFERN no ACK, request Status";
      
    } else {
      readingsSingleUpdate($hash, "state", "MISSING STATUS", 1);
      foreach (grep (/^channel_/, keys%{$hash})){
        my $chnHash = $defs{$hash->{$_}};
        readingsSingleUpdate($chnHash, "state", "MISSING STATUS", 1);
      }
      Log3 $hash, 3, "DUOFERN error: $name MISSING STATUS";
    }
    
    return undef;
}


1;

=pod
=item summary    controls Rademacher DuoFern devices
=item summary_DE steuert Rademacher DuoFern Ger&auml;te
=begin html

<a name="DUOFERN"></a>
<h3>DUOFERN</h3>
<ul>

  Support for DuoFern devices via the <a href="#DUOFERNSTICK">DuoFern USB Stick</a>.<br>
  <br><br>

  <a name="DUOFERN_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DUOFERN &lt;code&gt;</code>
    <br><br>
    &lt;code&gt; specifies the radio code of the DuoFern device<br><br>
    Example:<br>
    <ul>
      <code>define myDuoFern DUOFERN 49ABCD</code><br>
    </ul>
  </ul>
  <br>

  <a name="DUOFERN_set"></a>
  <b>Set</b>
  <ul>
    
    <b>Universal commands (available to most actors):</b><br><br>
    <ul>
    
    <li><b>remotePair</b><br>
        Activates the pairing mode of the actor.<br>
        Some actors accept this command in unpaired mode up to two hours afte power up.
        </li><br>
    <li><b>remoteUnpair</b><br>
        Activates the unpairing mode of the actor.
        </li><br>
    <li><b>getStatus</b><br>
        Sends a status request message to the DuoFern device.
        </li><br>
    <li><b>manualMode [on|off]</b><br>
        Activates the manual mode. If manual mode is active 
        all automatic functions will be ignored.
        </li><br>
    <li><b>timeAutomatic [on|off]</b><br>
        Activates the timer automatic.
        </li><br>
    <li><b>sunAutomatic [on|off]</b><br>
        Activates the sun automatic.
        </li><br>
    <li><b>dawnAutomatic [on|off]</b><br>
        Activates the dawn automatic.
        </li><br>
    <li><b>duskAutomatic [on|off]</b><br>
        Activates the dusk automatic.
        </li><br> 
    <li><b>dusk</b><br>
        Move roller shutter downwards or switch on switch/dimming actor
        if duskAutomatic is activated.
        </li><br>
    <li><b>dawn</b><br>
        Move roller shutter upwards or switch off switch/dimming actor
        if dawnAutomatic is activated.
        </li><br>
    <li><b>sunMode [on|off]</b><br>
        Activates the sun mode. If sun automatic is activated, 
        the roller shutter will move to the sunPosition or a switch/dimming 
        actor will shut off.
        </li><br>
    <li><b>reset [settings|full]</b><br>
        settings: Clear all settings and endpoints of the actor.<br>
        full: Complete reset of the actor including pairs.
        </li><br>
        
    </ul>      
    <b>Roller shutter actor commands:</b><br><br>
    <ul>
        
    <li><b>up [timer]</b><br>
        Move the roller shutter upwards. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>down [timer]</b><br>
        Move the roller shutter downwards. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>stop</b><br>
        Stop motion.
        </li><br>
    <li><b>position &lt;value&gt; [timer]</b><br>
        Set roller shutter to a desired absolut level. If parameter <b>timer</b> is used the 
        command will only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>toggle</b><br>
        Switch the roller shutter through the sequence up/stop/down/stop.
        </li><br>
    <li><b>rainAutomatic [on|off]</b><br>
        Activates the rain automatic.
        </li><br>
    <li><b>windAutomatic [on|off]</b><br>
        Activates the wind automatic.
        </li><br>
    <li><b>sunPosition &lt;value&gt;</b><br>
        Set the sun position.
        </li><br>
    <li><b>ventilatingMode [on|off]</b><br>
        Activates the ventilating mode. If activated, the roller 
        shutter will stop on ventilatingPosition when moving down.
        </li><br>
    <li><b>ventilatingPosition &lt;value&gt;</b><br>
        Set the ventilating position.
        </li><br>
    <li><b>windMode [on|off]</b><br>
        Activates the wind mode. If wind automatic and wind mode is 
        activated, the roller shutter moves in windDirection and ignore any automatic
        or manual command.<br>
        The wind mode ends 15 minutes after last activation automatically.
        </li><br>
    <li><b>windDirection [up|down]</b><br>
        Movemet direction for wind mode.
        </li><br>
    <li><b>rainMode [on|off]</b><br>
        Activates the rain mode. If rain automatic and rain mode is 
        activated, the roller shutter moves in rainDirection and ignore any automatic
        command.<br>
        The rain mode ends 15 minutes after last activation automatically.
        </li><br>
    <li><b>rainDirection [up|down]</b><br>
        Movemet direction for rain mode.
        </li><br>
    <li><b>runningTime &lt;sec&gt;</b><br>
        Set the motor running time.
        </li><br>
    <li><b>motorDeadTime [off|short|long]</b><br>
        Set the motor dead time.
        </li><br>
    <li><b>reversal [on|off]</b><br>
        Reversal of direction of rotation.
        </li><br>
    
    </ul>  
    <b>Switch/dimming actor commands:</b><br><br>
    <ul>
    
    <li><b>on [timer]</b><br>
        Switch on the actor. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>off [timer]</b><br>
        Switch off the actor. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><a href="#setExtensions">set extensions</a> are supported.
        </li><br>
    <li><b>level &lt;value&gt; [timer]</b><br>
        Set actor to a desired absolut level. If parameter <b>timer</b> is used the 
        command will only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>modeChange [on|off]</b><br>
        Inverts the on/off state of a switch actor or change then modus of a dimming actor.
        </li><br>
    <li><b>stairwellFunction [on|off]</b><br>
        Activates the stairwell function of a switch/dimming actor.
        </li><br>    
    <li><b>stairwellTime &lt;sec&gt;</b><br>
        Set the stairwell time.
        </li><br>
        
    </ul>    
    <b>Blind actor commands:</b><br><br>
    <ul>
        
    <li><b>blindsMode [on|off]</b><br>
        Activates the blinds mode.
        </li><br>
    <li><b>slatPosition &lt;value&gt;</b><br>
        Set the slat to a desired absolut level.
        </li><br>   
    <li><b>defaultSlatPos &lt;value&gt;</b><br>
        Set the default slat position.
        </li><br>   
    <li><b>slatRunTime &lt;msec&gt;</b><br>
        Set the slat running time.
        </li><br>   
    <li><b>tiltInSunPos [on|off]</b><br>
        Tilt slat after blind moved to sun position.
        </li><br>
    <li><b>tiltInVentPos [on|off]</b><br>
        Tilt slat after blind moved to ventilation position.
        </li><br>
    <li><b>tiltAfterMoveLevel [on|off]</b><br>
        Tilt slat after blind moved to an absolute position.
        </li><br>
    <li><b>tiltAfterStopDown [on|off]</b><br>
        Tilt slat after stopping blind while moving down.
        </li><br>
    
    </ul>    
    <b>Thermostat commands:</b><br><br>
    <ul>  
    <li><b>desired-temp &lt;temp&gt; [timer]</b><br>
        Set desired temperature. &lt;temp&gt; must be between -40 and 80
        Celsius, and precision is half a degree. If parameter <b>timer</b> 
        is used the command will only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>tempUp [timer]</b><br>
        Increases the desired temperature by half a degree. If parameter <b>timer</b> 
        is used the command will only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>tempDown [timer]</b><br>
        Decrease the desired temperature by half a degree. If parameter <b>timer</b> 
        is used the command will only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>temperatureThreshold[1|2|3|4] &lt;temp&gt;</b><br>
        Set temperature threshold 1 to 4. &lt;temp&gt; must be between -40 and 80
        Celsius, and precision is half a degree.
        </li><br>    
    <li><b>actTempLimit [timer]</b><br>
        Set desired temperature to the selected temperatureThreshold. If parameter 
        <b>timer</b> is used the command will only be executed if timeAutomatic is
        activated.
        </li><br>
        
    </ul>    
    <b>SX5 commands:</b><br><br>
    <ul>  
    
    <li><b>10minuteAlarm [on|off]</b><br>
        Activates the alarm sound of the SX5 when the door is left open for longer than 10 minutes.
        </li><br>
    <li><b>2000cycleAlarm [on|off]</b><br>
        Activates the alarm sounds of the SX5 when the SX5 has run 2000 cycles.
        </li><br>
    <li><b>automaticClosing [off|30|60|90|120|150|180|210|240]</b><br>
        Set the automatic closing time of the SX5 (sec).
        </li><br>
    <li><b>openSpeed [11|15|19]</b><br>
        Set the open speed of the SX5 (cm/sec).
        </li><br>    
    <li><b>backJump [on|off]</b><br>
        If activated the SX5 moves briefly in the respective opposite direction after reaching the end point.
        </li><br>
    <li><b>getConfig</b><br>
        Sends a config request message to the weather sensor.
        </li><br>
    
    </ul>
    <b>Weather sensor commands:</b><br><br> 
    <ul>
        
    <li><b>getConfig</b><br>
        Sends a configuration request message.
        </li><br>
    <li><b>getTime</b><br>
        Sends a time request message.
        </li><br>
    <li><b>getWeather</b><br>
        Sends a weather data request message.
        </li><br>    
    <li><b>writeConfig</b><br>
        Write the configuration back to the weather sensor.
        </li><br> 
    <li><b>DCF [on|off]</b><br>
        Switch the DCF receiver on or off.
        </li><br>
    <li><b>time</b><br>
        Set the current system time to the weather sensor.
        </li><br>    
    <li><b>interval &lt;value&gt;</b><br>
        Set the interval time for automatic transmittion of the weather data.<br>
        &lt;value&gt;: off or 1 to 100 minutes
        </li><br>    
    <li><b>latitude &lt;value&gt;</b><br>
        Set the latitude of the weather sensor position<br>
        &lt;value&gt;: 0 to 90
        </li><br>        
    <li><b>longitude &lt;value&gt;</b><br>
        Set the longitude of the weather sensor position<br>
        &lt;value&gt;: -90 to 90
        </li><br>        
     <li><b>timezone &lt;value&gt;</b><br>
        Set the time zone of the weather sensor<br>
        &lt;value&gt;: 0 to 23
        </li><br>       
     <li><b>triggerDawn &lt;value1&gt; ... [&lt;value5&gt;]</b><br>
        Sets up to 5 trigger values for a dawn event.<br>
        &lt;value[n]&gt;: off or 1 to 100 lux
        </li><br>        
     <li><b>triggerDusk &lt;value1&gt; ... [&lt;value5&gt;]</b><br>
        Sets up to 5 trigger values for a dusk event.<br>
        &lt;value[n]&gt;: off or 1 to 100 Lux
        </li><br>
     <li><b>triggerRain [on|off]</b><br>
        Switch the trigger of the rain event on or off.
        </li><br>
    <li><b>triggerSun &lt;value1&gt;:&lt;sun1&gt;:&lt;shadow1&gt;[:&lt;temperature1&gt;] ... [&lt;value5&gt;:&lt;sun5&gt;:&lt;shadow5&gt;[:&lt;temperature5&gt;]]</b><br>
        Sets up to 5 trigger values for a sun event.<br>
        &lt;value[n]&gt;: off or 1 to 100 kLux<br>
        &lt;sun[n]&gt;: time to detect sun, 1 to 30 minutes<br>
        &lt;shadow[n]&gt;: time to detect shadow, 1 to 30 minutes<br>
        &lt;temperature[n]&gt;: optional minimum temperature, -5 to 26 &deg;C
        </li><br>
     <li><b>triggerSunDirction &lt;startangle1&gt;:&lt;width1&gt; ... [&lt;startangle5&gt;:&lt;width5&gt;]</b><br>
        If enabled, the respective sun event will only be triggered, if sunDirection is in the specified range.<br>
        &lt;startangle[n]&gt;: off or 0 to 292.5 degrees (stepsize 22.5&deg;)<br>
        &lt;width[n]&gt;: 45 to 180 degrees (stepsize 45&deg;)<br>
        </li><br>
     <li><b>triggerSunHeight &lt;startangle1&gt;:&lt;width1&gt; ... [&lt;startangle5&gt;:&lt;width5&gt;]</b><br>
        If enabled, the respective sun event will only be triggered, if sunHeight is in the specified range.<br>
        &lt;startangle[n]&gt;: off or 0 to 65 degrees (stepsize 13&deg;)<br>
        &lt;width[n]&gt;: 26 or 52 degrees<br>
        </li><br>        
     <li><b>triggerTemperature &lt;value1&gt; ... [&lt;value5&gt;]</b><br>
        Sets up to 5 trigger values for a temperature event.<br>
        &lt;value[n]&gt;: off or -40 to 80 &deg;C
        </li><br>
     <li><b>triggerWind &lt;value1&gt; ... [&lt;value5&gt;]</b><br>
        Sets up to 5 trigger values for a wind event.<br>
        &lt;value[n]&gt;: off or 1 to 31 m/s
        </li><br>
      </ul><br>              
  </ul>
  <br>

  <a name="DUOFERN_get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="DUOFERN_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li><br>
    <li><b>timeout &lt;sec&gt;</b><br>
        After sending a command to an actor, the actor must respond with its status within this time. If no status message is received,
        up to two getStatus commands are resend.<br>
        Default 60s.
        </li><br>
    <li><b>toggleUpDown</b><br>
        If attribute is set, a stop command is send instead of the up or down command if the roller shutter is moving.
        </li><br>
    <li><b>positionInverse</b><br>
        If attribute is set, the position value of the roller shutter is inverted.
        </li><br>
  </ul>
  <br>

</ul>

=end html

=cut

##############################################################################
# $Id$
#
#  32_withings.pm
#
#  2019 Markus M.
#  Based on original code by justme1968
#
#  https://forum.fhem.de/index.php/topic,64944.0.html
#
#
##############################################################################
# Release 12 / 2020-02-20


package main;

use strict;
use warnings;
no warnings qw(redefine);

use HttpUtils;

use JSON;

use POSIX qw( strftime );
use Time::Local qw(timelocal);
use Digest::SHA qw(hmac_sha1_base64);

#use Encode qw(encode);
#use LWP::Simple;
#use HTTP::Request;
#use HTTP::Cookies;
use HTTP::Request::Common;
use LWP;
use URI::Escape qw(uri_escape);

use Data::Dumper;

#use Digest::MD5 qw(md5 md5_hex md5_base64);




my %device_types = (  0 => "User related",
                      1 => "Body Scale",
                      2 => "Camera",
                      4 => "Blood Pressure Monitor",
                     16 => "Activity Tracker",
                     32 => "Sleep Monitor",
                     64 => "Thermometer", );

my %device_models = (  1 => { 1 => "Smart Scale", 2 => "Wireless Scale", 3 => "Smart Kid Scale", 4 => "Smart Body Analyzer", 5 => "WiFi Body Scale", 6 => "Cardio Scale", 7 => "Body Scale", },
                       2 => { 21 => "Smart Baby Monitor", 22 => "Home", 23 => "Home v2", },
                       4 => { 41 => "iOS Blood Pressure Monitor", 42 => "Wireless Blood Pressure Monitor", 43 => "BPM", 44 => "BPM Core", },
                      16 => { 51 => "Pulse Ox", 52 => "Activite", 53 => "Activite v2", 54 => "Go", 55 => "Steel HR", },
                      32 => { 60 => "Aura", 61 => "Sleep Sensor", 62 => "Aura v2", 63 => "Sleep", },
                      64 => { 70 => "Thermo", }, );

                      #Firmware files: cdnfw_withings_net
                      #Smart Body Analyzer: /wbs02/wbs02_1521.bin
                      #Cardio Scale: /wbs04/wbs04_1751_2NataR.bin
                      #Blood Pressure Monitor: /wpm02/wpm02_251.bin wpm02/wpm02_421_w1IpDO.bin
                      #Pulse: /wam01/wam01_1761.bin
                      #Go: /wam02/wam02_590.bin
                      #Aura: /wsd01/wsd01_607.bin /wsd01/wsd01_1206_xPN4x8.bin
                      #Aura Mat: /wsm01/wsm01_711.bin /wsm01/wsm01_1231.bin
                      #Sleep: /wsm02/wsm02_1531_fMvB9s.bin
                      #Home: /wbp02/wbp02_168.bin
                      #Activite: /hwa01/hwa01_1070.bin
                      #Thermo: /sct01/sct01_1401_ZVjZyU.bin


my %measure_types = (  1 => { name => "Weight (kg)", reading => "weight", },
                       4 => { name => "Height (meter)", reading => "height", },
                       5 => { name => "Lean Mass (kg)", reading => "fatFreeMass", },
                       6 => { name => "Fat Mass (%)", reading => "fatRatio", },
                       7 => { name => "Lean Mass (%)", reading => "fatFreeRatio", },
                       8 => { name => "Fat Mass (kg)", reading => "fatMassWeight", },
                       9 => { name => "Diastolic Blood Pressure (mmHg)", reading => "diastolicBloodPressure", },
                      10 => { name => "Systolic Blood Pressure (mmHg)", reading => "systolicBloodPressure", },
                      11 => { name => "Heart Rate (bpm)", reading => "heartPulse", }, #vasistas
                      12 => { name => "Temperature (&deg;C)", reading => "temperature", }, #getmeashf
                      13 => { name => "Humidity (%)", reading => "humidity", }, #getmeashf
                      14 => { name => "unknown 14", reading => "unknown14", }, #device? event home - peak sound level? #getmeashf
                      15 => { name => "Noise (dB)", reading => "noise", }, #getmeashf
                      18 => { name => "Weight Objective Speed", reading => "weightObjectiveSpeed", },
                      19 => { name => "Breastfeeding (s)", reading => "breastfeeding", }, #baby
                      20 => { name => "Bottle (ml)", reading => "bottle", }, #baby
                      22 => { name => "BMI", reading => "bmi", }, #user? goals
                      35 => { name => "CO2 (ppm)", reading => "co2", }, #getmeashf
                      36 => { name => "Steps", reading => "steps", dailyreading => "dailySteps", },  #aggregate #vasistas
                      37 => { name => "Elevation (m)", reading => "elevation", dailyreading => "dailyElevation", }, #aggregate #vasistas
                      38 => { name => "Calories (kcal)", reading => "calories", dailyreading => "dailyCalories", }, #aggregate #vasistas
                      39 => { name => "Intensity", reading => "intensity", }, #intraday only #vasistas
                      40 => { name => "Distance (m)", reading => "distance", dailyreading => "dailyDistance", },  #aggregate #measure #vasistas
                      41 => { name => "Descent (m)", reading => "descent", dailyreading => "dailyDescent", }, #descent #aggregate #measure ??sleepreading! #vasistas
                      42 => { name => "Activity Type", reading => "activityType", }, #intraday only 1:walk 2:run #vasistas
                      43 => { name => "Duration (s)", reading => "duration", }, #intraday only #vasistas
                      44 => { name => "Sleep State", reading => "sleepstate", }, #intraday #aura mat #vasistas
                      45 => { name => "unknown 45", reading => "unknown45", },#vasistas
                      46 => { name => "User Event", reading => "userEvent", },#appli type only
                      47 => { name => "Meal Calories (kcal)", reading => "caloriesMeal", },
                      48 => { name => "Active Calories (kcal)", reading => "caloriesActive", dailyreading => "dailyCaloriesActive", }, #day summary
                      49 => { name => "Idle Calories (kcal)", reading => "caloriesPassive", dailyreading => "dailyCaloriesPassive", }, #aggregate
                      50 => { name => "Inactive Duration (s)", reading => "durationInactive", dailyreading => "dailyDurationInactive", }, #day summary pulse 60k-80k #aggregate
                      51 => { name => "Light Activity (s)", reading => "durationLight", dailyreading => "dailyDurationLight", }, #aggregate
                      52 => { name => "Moderate Activity (s)", reading => "durationModerate", dailyreading => "dailyDurationModerate", }, #aggregate
                      53 => { name => "Intense Activity (s)", reading => "durationIntense", dailyreading => "dailyDurationIntense", }, #aggregate
                      54 => { name => "SpO2 (%)", reading => "spo2", },
                      55 => { name => "unknown 55", reading => "unknown55", }, #
                      56 => { name => "Ambient light (lux)", reading => "light", },  # aura device #getmeashf
                      57 => { name => "Respiratory rate", reading => "breathing", }, # aura mat #measure #vasistas
                      58 => { name => "Air Quality (ppm)", reading => "voc", }, # Home Air Quality #getmeashf
                      59 => { name => "unknown 59", reading => "unknown59", }, # activity #vasistas
                      60 => { name => "PIM movement", reading => "movementPIM", }, # aura mat #measure vasistas 20-200 peak 800 #vasistas
                      61 => { name => "Maximum movement", reading => "movementMaximum", }, # aura mat #measure vasistas 10-60 peak 600 #vasistas
                      62 => { name => "unknown 62", reading => "unknown62", }, # aura mat #measure vasistas 20-100 #vasistas
                      63 => { name => "unknown 63", reading => "unknown63", }, # aura mat #measure vasistas 0-90 #vasistas
                      64 => { name => "unknown 64", reading => "unknown64", }, # aura mat #measure vasistas 30-150 #vasistas
                      65 => { name => "unknown 65", reading => "unknown65", }, # aura mat #measure vasistas 500-4000 peak 5000 #vasistas
                      66 => { name => "Pressure", reading => "pressure", }, # aura & sleep mat #measure vasistas 4000-7000 #vasistas
                      67 => { name => "unknown 67", reading => "unknown67", }, # aura mat #measure vasistas 0-100 peak 500 #vasistas
                      68 => { name => "unknown 68", reading => "unknown68", }, # aura mat #measure vasistas 0-800 peak 2000 #vasistas
                      69 => { name => "unknown 69", reading => "unknown69", }, # aura mat #measure vasistas 0-5000 peak 10000 #vasistas
                      70 => { name => "unknown 70", reading => "unknown70", }, #? #vasistas
                      71 => { name => "Body Temperature (&deg;C)", reading => "bodyTemperature", }, #thermo
                      72 => { name => "GPS Speed", reading => "speedGPS", }, #vasistas
                      73 => { name => "Skin Temperature (&deg;C)", reading => "skinTemperature", }, #thermo #vasistas
                      76 => { name => "Muscle Mass (kg)", reading => "muscleMass", }, # cardio scale
                      77 => { name => "Water Mass (kg)", reading => "waterMass", }, # cardio scale
                      78 => { name => "unknown 78", reading => "unknown78", }, # cardio scale
                      79 => { name => "unknown 79", reading => "unknown79", }, # body scale
                      80 => { name => "unknown 80", reading => "unknown80", }, # body scale
                      86 => { name => "unknown 86", reading => "unknown86", }, # body scale
                      87 => { name => "Active Calories (kcal)", reading => "caloriesActive", dailyreading => "dailyCaloriesActive", }, # measures list sleepreading! #vasistas
                      88 => { name => "Bone Mass (kg)", reading => "boneMassWeight", },
                      89 => { name => "unknown 89", reading => "unknown89", }, #vasistas
                      90 => { name => "unknown 90", reading => "unknown90", }, #pulse #vasistas
                      91 => { name => "Pulse Wave Velocity (m/s)", reading => "pulseWave", },
                      93 => { name => "Muscle Mass (%)", reading => "muscleRatio", }, # cardio scale
                      94 => { name => "Bone Mass (%)", reading => "boneRatio", }, # cardio scale
                      95 => { name => "Hydration (%)", reading => "hydration", }, # body water
                      96 => { name => "Horizontal Radius", reading => "radiusHorizontal", }, #vasistas
                      97 => { name => "Altitude", reading => "altitude", }, #vasistas
                      98 => { name => "Latitude", reading => "latitude", },#vasistas
                      99 => { name => "Longitude", reading => "longitude", },#vasistas
                     100 => { name => "Direction", reading => "direction", },#vasistas
                     101 => { name => "Vertical Radius", reading => "radiusVertical", },#vasistas
                     102 => { name => "unknown 102", reading => "unknown102", }, #?
                     103 => { name => "unknown 103", reading => "unknown103", }, #?
                     104 => { name => "unknown 104", reading => "unknown104", }, #?
                     105 => { name => "unknown 105", reading => "unknown105", }, #?
                     106 => { name => "unknown 106", reading => "unknown106", }, #?
                     107 => { name => "unknown 107", reading => "unknown107", }, #?
                     108 => { name => "unknown 108", reading => "unknown108", }, #?
                     109 => { name => "unknown 109", reading => "unknown109", }, #?
                     110 => { name => "unknown 110", reading => "unknown110", }, #?
                     111 => { name => "unknown 111", reading => "unknown111", }, #?
                     112 => { name => "unknown 112", reading => "unknown112", }, #?
                     113 => { name => "unknown 113", reading => "unknown113", }, #?
                     114 => { name => "unknown 114", reading => "unknown114", }, #?
                     115 => { name => "unknown 115", reading => "unknown115", }, #?
                     116 => { name => "unknown 116", reading => "unknown116", }, #?
                     117 => { name => "unknown 117", reading => "unknown117", }, #?
                     118 => { name => "unknown 118", reading => "unknown118", }, #?
                     119 => { name => "unknown 119", reading => "unknown119", }, #?
                     120 => { name => "unknown 120", reading => "unknown120", }, #vasistas
                     121 => { name => "Snoring", reading => "snoring", }, # sleep #vasistas
                     122 => { name => "Lean Mass (%)", reading => "fatFreeRatio", },
                     123 => { name => "unknown 123", reading => "unknown123", },#
                     124 => { name => "unknown 124", reading => "unknown124", },#
                     125 => { name => "unknown 125", reading => "unknown125", },#
                     126 => { name => "unknown 126", reading => "unknown126", },#
                     127 => { name => "unknown 127", reading => "unknown127", },#
                     128 => { name => "unknown 128", reading => "unknown128", },#vasistas
                     129 => { name => "unknown 129", reading => "unknown129", },#vasistas sleep
                     130 => { name => "ECG", reading => "heartECG", },#bpm core
                     131 => { name => "Heart Sounds", reading => "heartSounds", },#bpm core
                     132 => { name => "unknown 132", reading => "unknown132", },#vasistas
                     133 => { name => "unknown 133", reading => "unknown133", },#
                     134 => { name => "unknown 134", reading => "unknown134", },#
                     135 => { name => "unknown 135", reading => "unknown135", },#
                     136 => { name => "unknown 136", reading => "unknown136", },#
                     137 => { name => "unknown 137", reading => "unknown137", },#
                     138 => { name => "unknown 138", reading => "unknown138", },#
                     139 => { name => "unknown 139", reading => "unknown139", },#
                     140 => { name => "unknown 140", reading => "unknown140", },#
                      #-10 => { name => "Speed", reading => "speed", },
                      #-11 => { name => "Pace", reading => "pace", },
                      #-12 => { name => "Altitude", reading => "altitude", },
                      );
                      #swimStrokes / swimLaps / walkState / runState

my %ecg_types = ( 0 => "normal",
                  1 => "signs of atrial fibrillation",
                  2 => "inconclusive", );

my %heart_types = ( -5 => "4 measurements to go",
                    -4 => "3 measurements to go",
                    -3 => "2 measurements to go",
                    -2 => "1 measurement to go",
                     0 => "normal",
                     2 => "unclassified",
                     4 => "inconclusive", );

my %activity_types =   (  0 => "None",
                          1 => "Walking",
                          2 => "Running",
                          3 => "Hiking",
                          4 => "Skating",
                          5 => "BMX",
                          6 => "Cycling",
                          7 => "Swimming",
                          8 => "Surfing",
                          9 => "Kitesurfing",
                         10 => "Windsurfing",
                         11 => "Bodyboard",
                         12 => "Tennis",
                         13 => "Ping Pong",
                         14 => "Squash",
                         15 => "Badminton",
                         16 => "Weights",
                         17 => "Calisthenics",
                         18 => "Elliptical",
                         19 => "Pilates",
                         20 => "Basketball",
                         21 => "Soccer",
                         22 => "Football",
                         23 => "Rugby",
                         24 => "Volleyball",
                         25 => "Water Polo",
                         26 => "Horse Riding",
                         27 => "Golf",
                         28 => "Yoga",
                         29 => "Dancing",
                         30 => "Boxing",
                         31 => "Fencing",
                         32 => "Wrestling",
                         33 => "Martial Arts",
                         34 => "Skiing",
                         35 => "Snowboarding",
                         36 => "Other",
                         37 => "Sleep",
                        127 => "Sleep Debug",
                        128 => "No Activity",
                        187 => "Rowing",
                        188 => "Zumba",
                        190 => "Base",
                        191 => "Baseball",
                        192 => "Handball",
                        193 => "Hockey",
                        194 => "Ice Hockey",
                        195 => "Climbing",
                        196 => "Ice Skating",
                        271 => "Multi Sports",
                        272 => "Multi Sport", );

my %sleep_states = ( -1 => "unknown",
                     0 => "awake",
                     1 => "light",
                     2 => "deep",
                     3 => "rem", );

my %weight_units =      (  1 => { name => "kg (metric)", unit => "kg", },
                           2 => { name => "lb (US imperial)", unit => "lb", },
                           5 => { name => "stlb (UK imperial)", unit => "st", },
                          14 => { name => "stlb (UK imperial)", unit => "st", }, );

my %distance_units =    (  6 => { name => "km", unit => "km", },
                           7 => { name => "miles", unit => "mi", }, );

my %temperature_units = ( 11 => { name => "Celsius", unit => "˚C", },
                          13 => { name => "Fahrenheit", unit => "˚F", }, );

my %height_units =      (  6 => { name => "cm", unit => "cm", },
                           7 => { name => "ft", unit => "ft", }, );

my %aggregate_range = (  1 => "day",
                         2 => "week",
                         3 => "month",
                         4 => "year",
                         5 => "alltime", );

my %event_types = (  10 => { name => "Noise", reading => "alertNoise", threshold => "levelNoise", duration => "durationNoise", unit => 0, },
                     11 => { name => "Motion", reading => "alertMotion", threshold => "levelMotion", duration => "durationMotion", unit => -2, },
                     12 => { name => "Low Temperature", reading => "alertTemperatureLow", threshold => "levelTemperatureLow", duration => "dummy", unit => -2, },
                     13 => { name => "High Temperature", reading => "alertTemperatureHigh", threshold => "levelTemperatureHigh", duration => "dummy", unit => -2, },
                     14 => { name => "Low Humidity", reading => "alertHumidityLow", threshold => "levelHumidityLow", duration => "dummy", unit => -2, },
                     15 => { name => "High Humidity", reading => "alertHumidityHigh", threshold => "levelHumidityHigh", duration => "dummy", unit => -2, },
                     20 => { name => "Disconnection", reading => "alertDisconnection", threshold => "levelDisconnected", duration => "dummy", unit => 0, },
                     );

#
my %timeline_classes = (  'noise_detected' => { name => "Noise", reading => "alertNoise", unit => 0, },
                          'movement_detected' => { name => "Motion", reading => "alertMotion", unit => 0, },
                          'alert_environment' => { name => "Air Quality Alert", reading => "alertEnvironment", unit => 0, },
                          'period_activity' => { name => "Activity Period", reading => "periodActivity", unit => 0, },
                          'period_activity_start' => { name => "Activity Period Start", reading => "periodActivityStart", unit => 0, },
                          'period_activity_cancel' => { name => "Activity Period Cancel", reading => "periodActivityCancel", unit => 0, },
                          'period_offline' => { name => "Offline Period", reading => "periodDisconnection", unit => 0, },
                          'offline' => { name => "Disconnection", reading => "alertDisconnection", unit => 0, },
                          'online' => { name => "Connection", reading => "alertConnection", unit => 0, },
                          'deleted' => { name => "Deleted", reading => "alertDeleted", unit => 0, },
                          'snapshot' => { name => "Snapshot", reading => "alertSnapshot", unit => 0, },
                          );

my %sleep_readings = (  'lightsleepduration' => { name => "Light Sleep", reading => "sleepDurationLight", unit => "s", },
                        'deepsleepduration' => { name => "Deep Sleep", reading => "sleepDurationDeep", unit => "s", },
                        'remsleepduration' => { name => "REM Sleep", reading => "sleepDurationREM", unit => "s", },
                        'wakeupduration' => { name => "Awake In Bed", reading => "sleepDurationAwake", unit => "s", },
                        'wakeupcount' => { name => "Wakeup Count", reading => "wakeupCount", unit => 0, },
                        'durationtosleep' => { name => "Duration To Sleep", reading => "durationToSleep", unit => "s", },
                        'durationtowakeup' => { name => "Duration To Wake Up", reading => "durationToWakeUp", unit => "s", },
                        'manual_sleep_duration' => { name => "Manual Sleep", reading => "sleepDurationManual", unit => "s", },
                        'sleepscore' => { name => "Sleep Score", reading => "sleepScore", unit => 0, },
                        'wsdid' => { name => "wsdid", reading => "wsdid", unit => 0, },
                        'hr_resting' => { name => "Resting HR", reading => "heartrateResting", unit => "bpm", },
                        'hr_min' => { name => "Minimum HR", reading => "heartrateMinimum", unit => "bpm", },
                        'hr_average' => { name => "Average HR", reading => "heartrateAverage", unit => "bpm", },
                        'hr_max' => { name => "Maximum HR", reading => "heartrateMaximum", unit => "bpm", },
                        'rr_min' => { name => "Minimum RR", reading => "breathingMinimum", unit => 0, },
                        'rr_average' => { name => "Average RR", reading => "breathingAverage", unit => 0, },
                        'rr_max' => { name => "Maximum RR", reading => "breathingMaximum", unit => 0, },
                        'snoring' => { name => "Snoring", reading => "snoringDuration", unit => "s", },
                        'snoringepisodecount' => { name => "Snoring Episode Count", reading => "snoringEpisodeCount", unit => 0, },
                        'breathing_event_probability' => { name => "Breathing Event Probability", reading => "breathingEventProbability", unit => 0, },
                        'apnea_algo_version' => { name => "Apnea Algo Version", reading => "apneaAlgoVersion", unit => 0, },

                        # 'manual_distance' => { name => "Manual Distance", reading => "manual_distance", unit => 0, },
                        # 'steps' => { name => "Steps", reading => "steps", unit => 0, },
                        # 'calories' => { name => "Calories", reading => "calories", unit => 0, },
                        # 'metcumul' => { name => "metcumul", reading => "metcumul", unit => 0, },
                        # 'manual_calories' => { name => "Manual Calories", reading => "manual_calories", unit => 0, },
                        # 'intensity' => { name => "Intensity", reading => "intensity", unit => 0, },
                        # 'effduration' => { name => "Effective Duration", reading => "effduration", unit => 0, },
                        # 'distance' => { name => "Distance", reading => "distance", unit => 0, },
                        # 'steps' => { name => "Steps", reading => "steps", unit => 0, },
                        );

my %alarm_sound = (  0 => "Unknown",
                      1 => "Cloud Flakes",
                      2 => "Desert Wave",
                      3 => "Moss Forest",
                      4 => "Morning Smile",
                      5 => "Spotify",
                      6 => "Internet radio", );

my %alarm_song = (  'Unknown' => 0,
                    'Cloud Flakes' => 1,
                    'Desert Wave' => 2,
                    'Moss Forest' => 3,
                    'Morning Smile' => 4,
                    'Spotify' => 5,
                    'Internet radio' => 6, );

my %nap_sound = (  0 => "Unknown",
                      1 => "Celestial Piano (20 min)",
                      2 => "Cotton Cloud (10 min)",
                      3 => "Deep Smile (10 min)",
                      4 => "Sacred Forest (20 min)",
                      5 => "Spotify",
                      6 => "Internet radio", );

my %nap_song = (      "Unknown" => 0,
                      "Celestial Piano (20 min)" => 1,
                      "Cotton Cloud (10 min)" => 2,
                      "Deep Smile (10 min)" => 3,
                      "Sacred Forest (20 min)" => 4,
                      "Spotify" => 5,
                      "Internet radio" => 6, );


my %sleep_sound = (  0 => "Unknown",
                      1 => "Moonlight Waves",
                      2 => "Siren's Whisper",
                      3 => "Celestial Piano",
                      4 => "Cloud Flakes",
                      5 => "Spotify",
                      6 => "Internet radio", );
#
my %sleep_song = (    "Unknown" => 0,
                      "Moonlight Waves" => 1,
                      "Siren's Whisper" => 2,
                      "Celestial Piano" => 3,
                      "Cloud Flakes" => 4,
                      "Spotify" => 5,
                      "Internet radio" => 6, );



sub withings_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "withings_Define";
  $hash->{SetFn}    = "withings_Set";
  $hash->{GetFn}    = "withings_Get";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "withings_Notify";
  $hash->{ReadFn}   = "withings_Read";
  $hash->{UndefFn}  = "withings_Undefine";
  $hash->{DbLog_splitFn}  =   "withings_DbLog_splitFn";
  $hash->{AttrFn}   = "withings_Attr";
  $hash->{AttrList} = "IODev ".
                      "disable:0,1 ".
                      "intervalAlert ".
                      "intervalData ".
                      "intervalDebug ".
                      "intervalProperties ".
                      "intervalDaily ".
                      "callback_url ".
                      "client_id ".
                      "client_secret ".
#                      "nossl:1 ".
                      "IP ".
                      "videoLinkEvents:1 ";

  $hash->{AttrList} .= $readingFnAttributes;

Log3 "withings", 5, "withings: initialize";
}

#####################################

sub withings_Define($$) {
  my ($hash, $def) = @_;
  Log3 "withings", 5, "withings: define ".$def;

  my @a = split("[ \t][ \t]*", $def);

  my $subtype;
  my $name = $a[0];
  if( @a == 3 ) {
    $subtype = "DEVICE";

    my $device = $a[2];

    $hash->{Device} = $device;

    my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;

  } elsif( @a == 5 && $a[2] =~ m/^\D+$/ && $a[3] =~ m/^\d+$/  ) {
    $subtype = "DUMMY";
    my $device = $a[2];
    my $user = $a[3];
    $hash->{Device} = $device;
    $hash->{typeID} = '16';
    $hash->{modelID} = '0';
    $hash->{User} = $user;

    CommandAttr(undef,"$name IODev $a[4]");

  } elsif( @a == 4 && $a[2] =~ m/^\d+$/ && $a[3] =~ m/^[\w:-]+$/i ) {
    $subtype = "USER";

    my $user = $a[2];
    my $key = $a[3];

    my $accesskey = withings_encrypt($key);
    Log3 $name, 3, "$name: encrypt $key to $accesskey" if($key ne $accesskey);
    $hash->{DEF} = "$user $accesskey";

    $hash->{User} = $user;
    $hash->{helper}{Key} = $accesskey;

    my $d = $modules{$hash->{TYPE}}{defptr}{"U$user"};
    return "user $user already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"U$user"} = $hash;

  } elsif( @a == 4  || ($a[2] eq "ACCOUNT" && @a == 5 ) ) {
    $subtype = "ACCOUNT";

    my $user = $a[@a-2];
    my $pass = $a[@a-1];

    my $username = withings_encrypt($user);
    my $password = withings_encrypt($pass);
    Log3 $name, 3, "$name: encrypt $user/$pass to $username/$password" if($user ne $username || $pass ne $password);

    #$hash->{DEF} =~ s/$user/$username/g;
    #$hash->{DEF} =~ s/$pass/$password/g;
    $hash->{DEF} = "$username $password";

    $hash->{Clients} = ":withings:";

    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    $hash->{helper}{appliver} = '4080100';
    #$hash->{helper}{csrf_token} = 'e0a2595a83b85236709e366a8eed30b568df3dde';
  } else {
    return "Usage: define <name> withings ACCOUNT <login> <password>"  if(@a < 3 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype if(defined($subtype));


  #CommandAttr(undef,"$name DbLogExclude .*");


  # my $resolve = inet_aton("scalews.withings.com");
  # if(!defined($resolve))
  # {
  #   $hash->{STATE} = "DNS error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  #   InternalTimer( gettimeofday() + 900, "withings_InitWait", $hash, 0);
  #   return undef;
  # }

  $hash->{STATE} = "Initialized" if( $hash->{SUBTYPE} eq "ACCOUNT" );

  if( $init_done ) {
    withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
    withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    InternalTimer(gettimeofday()+60, "withings_poll", $hash, 0) if( $hash->{SUBTYPE} eq "DUMMY" );

  #connect aura
  my $auraip = $attr{$name}{IP};
  if($auraip){
    $hash->{DeviceName} = $auraip.":7685";

      Log3 $hash, 3, "$name: Opening Aura socket";
    withings_Close($hash) if(DevIo_IsOpen($hash));
    withings_Open($hash);
  }
  }
  else
  {
    InternalTimer(gettimeofday()+15, "withings_InitWait", $hash, 0);
  }

  withings_addExtension($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );

  return undef;
}


sub withings_InitWait($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};

  Log3 $name, 5, "$name: initwait ".$init_done;

  RemoveInternalTimer($hash,"withings_InitWait");

  # my $resolve = inet_aton("scalews.withings.com");
  # if(!defined($resolve))
  # {
  #   $hash->{STATE} = "DNS error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  #   InternalTimer( gettimeofday() + 1800, "withings_InitWait", $hash, 0);
  #   return undef;
  # }

  if( $init_done ) {
    withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
    withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    InternalTimer(gettimeofday()+60, "withings_poll", $hash, 0) if( $hash->{SUBTYPE} eq "DUMMY" );

    #connect aura
    my $auraip = $attr{$name}{IP};
    if($auraip){
      $hash->{DeviceName} = $auraip.":7685";

      Log3 $hash, 3, "$name: Opening Aura socket";
      withings_Close($hash) if(DevIo_IsOpen($hash));
    	withings_Open($hash);
    }
  }
  else
  {
    InternalTimer(gettimeofday()+30, "withings_InitWait", $hash, 0);
  }

  return undef;

}

sub withings_Notify($$) {
  my ($hash,$dev) = @_;
  my $name= $hash->{NAME};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
  Log3 $name, 5, "$name: notify";

  # my $resolve = inet_aton("scalews.withings.com");
  # if(!defined($resolve))
  # {
  #   $hash->{STATE} = "DNS error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  #   InternalTimer( gettimeofday() + 3600, "withings_InitWait", $hash, 0);
  #   return undef;
  # }


  withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
  withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );

  #connect aura
  my $auraip = $attr{$name}{IP};
  if($auraip){
    $hash->{DeviceName} = $auraip.":7685";

    Log3 $hash, 3, "$name: Opening Aura socket";
    withings_Close($hash) if(DevIo_IsOpen($hash));
    withings_Open($hash);
  }

}

sub withings_Open($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};

  return undef if(DevIo_IsOpen($hash));
  my $auraip = AttrVal($name,"IP",undef);
  if($auraip){
    $hash->{DeviceName} = $auraip.":7685";

    Log3 $hash, 2, "$name: Reopening Aura socket";
    DevIo_OpenDev($hash, 0, "withings_Hello", "withings_Callback");
  }
  return undef;
}

sub withings_Hello($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};

  my $data = "000100010100050101010000"; #hello
  withings_Write($hash, $data);

  $data="010100050101110000"; #hello2
  withings_Write($hash, $data);

  $data="0101000a01090a0005090a000100"; #ping
  withings_Write($hash, $data);

  return undef;
}

sub withings_Close($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};

  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
  return undef;
}


sub withings_Read($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};
  my $buf;
  $buf = DevIo_SimpleRead($hash);
  return undef if(!defined($buf));

  Log3 $hash, 4, "$name: Received " . length($buf) . " bytes: ".unpack('H*', $buf) if(length($buf) > 1);

  if(length($buf) > 1) {
    withings_parseAuraData($hash,$buf);
  }

  return undef;
}

sub withings_Write($$) {
  my ($hash,$data) = @_;
  my $name= $hash->{NAME};
  Log3 $hash, 4, "$name: Written " . length($data) . " bytes: ".$data if(length($data) > 1);
  $data = pack('H*', $data);
  DevIo_SimpleWrite($hash,$data,0);
  return undef;
}



sub withings_Callback($) {
  my ($hash, $error) = @_;
	my $name = $hash->{NAME};
  Log3 $name, 2, "$name: error while connecting to Aura: $error" if($error);
  return undef;
}


sub withings_Undefine($$) {
  my ($hash, $arg) = @_;
  Log3 "withings", 5, "withings: undefine";
  RemoveInternalTimer($hash);

  delete( $modules{$hash->{TYPE}}{defptr}{"U$hash->{User}"} ) if( $hash->{SUBTYPE} eq "USER" );
  delete( $modules{$hash->{TYPE}}{defptr}{"D$hash->{Device}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );
  DevIo_CloseDev($hash);

  return undef;
}


sub withings_getToken($) {
  my ($hash) = @_;
  Log3 "withings", 5, "withings: gettoken";


  # my $resolve = inet_aton("auth.withings.com");
  # if(!defined($resolve))
  # {
  #   Log3 "withings", 1, "withings: DNS error on getToken";
  #   return undef;
  # }

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://auth.withings.com/index/service/once?action=get",
    timeout => 10,
    noshutdown => 1,
    data => {action => 'get'},
  });

  #my $URL = 'http://auth.withings.com/index/service/once?action=get';
  #my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  #my $header = HTTP::Request->new(GET => $URL);
  #my $request = HTTP::Request->new('GET', $URL, $header);
  #my $response = $agent->request($request);
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 "withings", 2, "withings: json evaluation error on getToken ".$@;
    return undef;
  }
  Log3 "withings", 1, "withings: getToken json error ".$json->{error} if(defined($json->{error}));

  my $once = $json->{body}{once};
  $hash->{Once} = $once;
  my $hashstring = withings_decrypt($hash->{helper}{username}).':'.md5_hex(withings_decrypt($hash->{helper}{password})).':'.$once;
  $hash->{Hash} = md5_hex($hashstring);
}

sub withings_getSessionKey($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if( $hash->{SUBTYPE} ne "ACCOUNT" );

  return if( $hash->{SessionKey} && $hash->{SessionTimestamp} && gettimeofday() - $hash->{SessionTimestamp} < (60*60*24*7-3600) );

  # my $resolve = inet_aton("account.withings.com");
  # if(!defined($resolve))
  # {
  #   $hash->{SessionTimestamp} = 0;
  #   Log3 $name, 1, "$name: DNS error on getSessionData";
  #   return undef;
  # }

  $hash->{'.https'} = "https" if(!defined($hash->{'.https'}));

  # my $data1;
  # if( !defined($hash->{helper}{appliver}) || !defined($hash->{helper}{csrf_token}) || !defined($hash->{SessionTimestamp}) || gettimeofday() - $hash->{SessionTimestamp} > (30*60) )#!defined($hash->{helper}{appliver}) || !defined($hash->{helper}{csrf_token}))
  # {
  #   my($err0,$data0) = HttpUtils_BlockingGet({
  #     url => $hash->{'.https'}."://account.withings.com/",
  #     timeout => 10,
  #     noshutdown => 1,
  #   });
  #   if($err0 || !defined($data0))
  #   {
  #     Log3 $name, 1, "$name: appliver call failed! ".$err0;
  #     return undef;
  #   }
  #   $data1 = $data0;
  #   $data0 =~ /appliver=([^.*]+)\&/;
  #   $hash->{helper}{appliver} = $1;
  #   if(!defined($hash->{helper}{appliver})) {
  #     Log3 $name, 1, "$name: APPLIVER ERROR ";
  #     $hash->{STATE} = "APPLIVER error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  #     return undef;
  #   }
  #   Log3 $name, 4, "$name: appliver ".$hash->{helper}{appliver};
  # #}
  # 
  # 
  # #if( !defined($hash->{helper}{csrf_token}) )
  # #{
  #   $data1 =~ /csrf_token" value="(.*)"/;
  #   $hash->{helper}{csrf_token} = $1;
  #   
  #   if(!defined($hash->{helper}{csrf_token})) {
  #     Log3 $name, 1, "$name: CSRF ERROR ";
  #     $hash->{STATE} = "CSRF error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  #     return undef;
  #   }
  #   Log3 $name, 4, "$name: csrf_token ".$hash->{helper}{csrf_token};
  #}

    #my $ua = LWP::UserAgent->new;
    #my $request = HTTP::Request->new(POST => $hash->{'.https'}.'://account.withings.com/connectionuser/account_login?appname=my2&appliver='.$hash->{helper}{appliver}.'&r=https%3A%2F%2Fhealthmate.withings.com%2F',[email => withings_decrypt($hash->{helper}{username}), password => withings_decrypt($hash->{helper}{password}), is_admin => '',]);
    #my $get_data = 'use_authy=&is_admin=&email='.uri_escape(withings_decrypt($hash->{helper}{username})).'&password='.uri_escape(withings_decrypt($hash->{helper}{password}));
    #$request->content($get_data);
    #my $response = $ua->request($request);

    # $resolve = inet_aton("account.withings.com");
    # if(!defined($resolve))
    # {
    #   Log3 $name, 1, "$name: DNS error on getSessionKey.";
    #   return undef;
    # }

  my $datahash = {
      url => "https://account.withings.com/connectionwou/account_login?r=https://healthmate.withings.com/",
    timeout => 10,
    noshutdown => 1,
    ignoreredirects => 1,
      data => { email=> withings_decrypt($hash->{helper}{username}), password => withings_decrypt($hash->{helper}{password}), is_admin => 'f', use_2fa => '' },
  };

  my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err || !defined($data) || $data =~ /Authentification failed/ || $data =~ /not a valid/ || $data =~ /credentials do not match/)
  {
    Log3 $name, 1, "$name: LOGIN ERROR ";
    $hash->{STATE} = "Login error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
    return undef;
  }
  else
  {
    if ($datahash->{httpheader} =~ /session_key=(.*?);/)
    {
      $hash->{SessionKey} = $1;
      $hash->{SessionTimestamp} = (gettimeofday())[0] if( $hash->{SessionKey} );
      $hash->{STATE} = "Connected" if( $hash->{SessionKey} );
      $hash->{STATE} = "Session error" if( !$hash->{SessionKey} );
      Log3 $name, 4, "$name: sessionkey ".$hash->{SessionKey};
    }
    else
    {
      $hash->{STATE} = "Cookie error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
      Log3 $name, 1, "$name: COOKIE ERROR ";
      $hash->{helper}{appliver} = '4080100';
      #$hash->{helper}{csrf_token} = '9855c478';
      return undef;
    }
  }

  if( !$hash->{AccountID} || length($hash->{AccountID} < 2 ) ) {

    ($err,$data) = HttpUtils_BlockingGet({
      url => $hash->{'.https'}."://scalews.withings.com/cgi-bin/account",
      timeout => 10,
      noshutdown => 1,
      data => {sessionid => $hash->{SessionKey}, appname => 'hmw', appliver=> $hash->{helper}{appliver}, apppfm => 'web', action => 'get', enrich => 't'},
    });
    return undef if(!defined($data));

    if( $data =~ m/^{.*}$/ )
    {
      my $json = eval { JSON->new->utf8(0)->decode($data) };
      if($@)
      {
        Log3 $name, 2, "$name: json evaluation error on getSessionKey ".$@;
        return undef;
      }
      Log3 $name, 1, "withings: getSessionKey json error ".$json->{error} if(defined($json->{error}));

      foreach my $account (@{$json->{body}{account}}) {
          next if( !defined($account->{id}) );
          if($account->{email} eq withings_decrypt($hash->{helper}{username}))
          {
            $hash->{AccountID} = $account->{id};
          }
          else
          {
            Log3 $name, 4, "$name: account email: ".$account->{email};
          }
      }
      Log3 $name, 4, "$name: accountid ".$hash->{AccountID};
    }
    else
    {
      $hash->{STATE} = "Account error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
      Log3 $name, 1, "$name: ACCOUNT ERROR ";
      return undef;
    }
  }

}


sub withings_connect($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: connect";

  $hash->{'.https'} = "https";
  $hash->{'.https'} = "http" if( AttrVal($name, "nossl", 0) );

  withings_getSessionKey( $hash );

  return undef; #no more autocreate on start

  foreach my $d (keys %defs) {
    next if(!defined($defs{$d}));
    next if($defs{$d}{TYPE} ne "autocreate");
    return undef if(IsDisabled($defs{$d}{NAME}));
  }

  my $autocreated = 0;

  my $users = withings_getUsers($hash);
  foreach my $user (@{$users}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"U$user->{id}"}) ) {
      my $d = $modules{$hash->{TYPE}}{defptr}{"U$user->{id}"};
      Log3 $name, 2, "$name: user '$user->{id}' already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );
      next;
    }
    next if($user->{usertype} ne "1" || $user->{status} ne "0");

    my $id = $user->{id};
    my $devname = "withings_U". $id;
    my $publickey = withings_encrypt($user->{publickey});
    my $define= "$devname withings $id $publickey";

    Log3 $name, 2, "$name: create new device '$devname' for user '$id'";

    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$user->{shortname});
      #$cmdret= CommandAttr(undef,"$devname room WithingsTest");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      #$cmdret= CommandAttr(undef,"$devname disable 1");
      #$cmdret= CommandAttr(undef,"$devname verbose 5");

      $autocreated++;
    }
  }


  my $devices = withings_getDevices($hash);
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"D$device->{deviceid}"}) ) {
      my $d = $modules{$hash->{TYPE}}{defptr}{"D$device->{deviceid}"};
      $d->{association} = $device->{association} if($device->{association});

      #get user from association
      if(defined($device->{deviceproperties})){
        $d->{User} = $device->{deviceproperties}{linkuserid} if(defined($device->{deviceproperties}{linkuserid}));
        $d->{color} = $device->{deviceproperties}{product_color} if(defined($device->{deviceproperties}{product_color}));
      }
      
      Log3 $name, 2, "$name: device '$device->{deviceid}' already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );
      next;
    }


    my $detail = $device->{deviceproperties};
    next if( !defined($detail->{id}) );

    my $id = $detail->{id};
    my $devname = "withings_D". $id;
    my $define= "$devname withings $id";

    Log3 $name, 2, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$device_types{$detail->{type}}) if( defined($device_types{$detail->{type}}) );
      $cmdret= CommandAttr(undef,"$devname alias ".$device_models{$detail->{type}}->{$detail->{model}}) if( defined($device_models{$detail->{type}}) && defined($device_models{$detail->{type}}->{$detail->{model}}) );
      #$cmdret= CommandAttr(undef,"$devname room WithingsTest");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      #$cmdret= CommandAttr(undef,"$devname disable 1");
      #$cmdret= CommandAttr(undef,"$devname verbose 5");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );
}


sub withings_autocreate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: autocreate";

  $hash->{'.https'} = "https";
  $hash->{'.https'} = "http" if( AttrVal($name, "nossl", 0) );


  withings_getSessionKey( $hash );

  my $autocreated = 0;

  my $users = withings_getUsers($hash);
  foreach my $user (@{$users}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"U$user->{id}"}) ) {
      my $d = $modules{$hash->{TYPE}}{defptr}{"U$user->{id}"};
      Log3 $name, 2, "$name: user '$user->{id}' already defined as $d->{NAME}";
      next;
    }
    next if($user->{usertype} ne "1" || $user->{status} ne "0");

    my $id = $user->{id};
    my $devname = "withings_U". $id;
    my $publickey = withings_encrypt($user->{publickey});
    my $define= "$devname withings $id $publickey";

    Log3 $name, 2, "$name: create new device '$devname' for user '$id'";

    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$user->{shortname});
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname room Withings");

      $autocreated++;
    }
  }


  my $devices = withings_getDevices($hash);
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"D$device->{deviceid}"}) ) {
      my $d = $modules{$hash->{TYPE}}{defptr}{"D$device->{deviceid}"};
      $d->{association} = $device->{association} if($device->{association});

      #get user from association
      if(defined($device->{deviceproperties})){
        $d->{User} = $device->{deviceproperties}{linkuserid} if(defined($device->{deviceproperties}{linkuserid}));
        $d->{color} = $device->{deviceproperties}{product_color} if(defined($device->{deviceproperties}{product_color}));
      }

      Log3 $name, 2, "$name: device '$device->{deviceid}' already defined as $d->{NAME}";
      next;
    }


    my $detail = $device->{deviceproperties};
    next if( !defined($detail->{id}) );

    my $id = $detail->{id};
    my $devname = "withings_D". $id;
    my $define= "$devname withings $id";

    Log3 $name, 2, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$device_types{$detail->{type}}) if( defined($device_types{$detail->{type}}) );
      $cmdret= CommandAttr(undef,"$devname alias ".$device_models{$detail->{type}}->{$detail->{model}}) if( defined($device_models{$detail->{type}}) && defined($device_models{$detail->{type}}->{$detail->{model}}) );
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname room Withings");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );
}



sub withings_initDevice($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: initdevice ".$hash->{Device};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 2, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  $hash->{'.https'} = "https";
  $hash->{'.https'} = "http" if( AttrVal($hash->{NAME}, "nossl", 0) );

  my $device = withings_getDeviceDetail( $hash );

  $hash->{DeviceType} = "UNKNOWN";

  $hash->{sn} = $device->{sn};
  $hash->{fw} = $device->{fw};
  $hash->{created} = $device->{created};
  $hash->{location} = $device->{latitude}.",".$device->{longitude} if(defined($device->{latitude}));
  $hash->{DeviceType} = $device->{type};
  $hash->{DeviceType} = $device_types{$device->{type}} if( defined($device->{type}) && defined($device_types{$device->{type}}) );
  $hash->{model} = $device->{model};
  $hash->{model} = $device_models{$device->{type}}->{$device->{model}}
                   if( defined($device->{type}) && defined($device->{model}) && defined($device_models{$device->{type}}) && defined($device_models{$device->{type}}->{$device->{model}}) );
  $hash->{modelID} = $device->{model};
  $hash->{typeID} = $device->{type};
  $hash->{lastsessiondate} = $device->{lastsessiondate} if( defined($device->{lastsessiondate}) );
  $hash->{lastweighindate} = $device->{lastweighindate} if( defined($device->{lastweighindate}) );


  if((defined($hash->{typeID}) && $hash->{typeID} == 16) or (defined($hash->{typeID}) && $hash->{typeID} == 32 && defined($hash->{modelID}) && $hash->{modelID} != 60))
  {
    my $devicelink = withings_getDeviceLink( $hash );
    if(defined($devicelink) && defined($devicelink->{linkuserid}))
    {
      $hash->{User} = $devicelink->{linkuserid};
      my $userhash = $modules{$hash->{TYPE}}{defptr}{"U".$devicelink->{linkuserid}};
      if(defined($userhash)){
        $hash->{UserDevice} = $userhash;
        if(defined($hash->{typeID}) && $hash->{typeID} == 16){
          $userhash->{Tracker} = $hash->{Device};
        } elsif(defined($hash->{typeID}) && $hash->{typeID} == 32 && defined($hash->{modelID}) && $hash->{modelID} != 60) {
          $userhash->{Sleep} = $hash->{Device};
        }
      }
    }
  }


  if( !defined( $attr{$name}{stateFormat} ) ) {
    $attr{$name}{stateFormat} = "batteryPercent %";

    $attr{$name}{stateFormat} = "co2 ppm" if( $device->{model} == 4 );
    $attr{$name}{stateFormat} = "voc ppm" if( $device->{model} == 22 );
    $attr{$name}{stateFormat} = "light lux" if( $device->{model} == 60 );
    $attr{$name}{stateFormat} = "lastWeighinDate" if( $hash->{typeID} == 32 && $device->{model} >= 61 );
  }

  withings_readAuraAlarm($hash) if( defined(AttrVal($name,"IP",undef)) && defined($device->{model}) && $device->{model} == 60 && defined($device->{type}) && $device->{type} == 32 );

  InternalTimer(gettimeofday()+60, "withings_poll", $hash, 0);
}


sub withings_initUser($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: inituser ".$hash->{User};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 2, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  $hash->{'.https'} = "https";
  $hash->{'.https'} = "http" if( AttrVal($hash->{NAME}, "nossl", 0) );

  my $user = withings_getUserDetail( $hash );

  $hash->{shortName} = $user->{shortname};
  $hash->{gender} = ($user->{gender}==0)?"male":"female" if( defined($user->{gender}) );
  $hash->{userName} = ($user->{firstname}?$user->{firstname}:"") ." ". ($user->{lastname}?$user->{lastname}:"");
  $hash->{birthdate} = strftime("%Y-%m-%d", localtime($user->{birthdate})) if( defined($user->{birthdate}) );
  $hash->{age} = sprintf("%.1f",((int(time()) - int($user->{birthdate}))/(60*60*24*365.24225))) if( defined($user->{birthdate}) );
  $hash->{created} = $user->{created};
  $hash->{modified} = $user->{modified};

  $attr{$name}{stateFormat} = "weight kg" if( !defined( $attr{$name}{stateFormat} ) );

  InternalTimer(gettimeofday()+60, "withings_poll", $hash, 0);
  withings_AuthRefresh($hash) if(defined(ReadingsVal($name,".refresh_token",undef)));

}



sub withings_getUsers($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: getusers";

  withings_getSessionKey($hash);

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://scalews.withings.com/cgi-bin/account",
    timeout => 10,
    noshutdown => 1,
    data => {sessionid => $hash->{SessionKey}, accountid => $hash->{AccountID} , recurse_use => '1', recurse_devtype => '1', listmask => '5', allusers => 't' , appname => 'hmw', appliver=> $hash->{helper}{appliver}, apppfm => 'web', action => 'getuserslist'},
  });

  #my $ua = LWP::UserAgent->new;
  #my $request = HTTP::Request->new(POST => $hash->{'.https'}.'://healthmate.withings.com/index/service/account');
  #my $get_data = 'sessionid='.$hash->{SessionKey}.'&accountid='.$hash->{AccountID}.'&recurse_use=1&recurse_devtype=1&listmask=5&allusers=t&appname=my2&appliver='.$hash->{helper}{appliver}.'&apppfm=web&action=getuserslist';
  #$request->content($get_data);
  #my $response = $ua->request($request);
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getUsers ".$@;
    return undef;
  }
  Log3 $name, 1, "withings: getUsers json error ".$json->{error} if(defined($json->{error}));

  my @users = ();
  foreach my $user (@{$json->{body}{users}}) {
    next if( !defined($user->{id}) );

    push( @users, $user );
  }

  return \@users;
}



sub withings_getDevices($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: getdevices";

  withings_getSessionKey($hash);

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://scalews.withings.com/cgi-bin/association",
    timeout => 10,
    noshutdown => 1,
    data => {sessionid => $hash->{SessionKey}, accountid => $hash->{AccountID} , type => '-1', enrich => 't' , appname => 'hmw', appliver=> $hash->{helper}{appliver}, apppfm => 'web', action => 'getbyaccountid'},
  });

  #my $ua = LWP::UserAgent->new;
  #my $request = HTTP::Request->new(POST => $hash->{'.https'}.'://scalews.withings.com/cgi-bin/association');
  #my $get_data = 'sessionid='.$hash->{SessionKey}.'&accountid='.$hash->{AccountID}.'&type=-1&enrich=t&appname=my2&appliver='.$hash->{helper}{appliver}.'&apppfm=web&action=getbyaccountid';
  #$request->content($get_data);
  #my $response = $ua->request($request);
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getDevices ".$@;
    return undef;
  }
  Log3 $name, 1, "withings: getDevices json error ".$json->{error} if(defined($json->{error}));
  Log3 $name, 5, "$name: getdevices ".Dumper($json);

  my @devices = ();
  foreach my $association (@{$json->{body}{associations}}) {
    next if( !defined($association->{deviceid}) );
    push( @devices, $association );
  }
  return \@devices;
}




sub withings_getDeviceDetail($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: getdevicedetail ".$hash->{Device};

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://scalews.withings.com/cgi-bin/device",
    timeout => 10,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid => $hash->{Device} , appname => 'hmw', appliver=> $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getproperties'},
  });

  #Log3 $name, 5, "$name: getdevicedetaildata ".Dumper($data);
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getDeviceDetail ".$@;
    return undef;
  }
  Log3 $name, 1, "$name: getDeviceDetail json error ".$json->{error} if(defined($json->{error}));

  if($json)
  {
    my $device = $json->{body};
    $hash->{sn} = $device->{sn};
    $hash->{fw} = $device->{fw};
    $hash->{created} = $device->{created};
    $hash->{location} = $device->{latitude}.",".$device->{longitude} if(defined($device->{latitude}));
    $hash->{DeviceType} = $device->{type};
    $hash->{DeviceType} = $device_types{$device->{type}} if( defined($device->{type}) && defined($device_types{$device->{type}}) );
    $hash->{model} = $device->{model};
    $hash->{model} = $device_models{$device->{type}}->{$device->{model}}
                     if( defined($device->{type}) && defined($device->{model}) && defined($device_models{$device->{type}}) && defined($device_models{$device->{type}}->{$device->{model}}) );
    $hash->{modelID} = $device->{model};
    $hash->{typeID} = $device->{type};
    $hash->{lastsessiondate} = $device->{lastsessiondate} if( defined($device->{lastsessiondate}) );
    $hash->{lastweighindate} = $device->{lastweighindate} if( defined($device->{lastweighindate}) );
  }

  return $json->{body};
}


sub withings_getDeviceLink($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: getdevicelink ".$hash->{Device};

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://scalews.withings.com/cgi-bin/association",
    timeout => 10,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, appname => 'hmw', appliver=> $hash->{IODev}->{helper}{appliver}, enrich => 't', action => 'getbyaccountid'},
  });

  #my $ua = LWP::UserAgent->new;
  #my $request = HTTP::Request->new(POST => $hash->{'.https'}.'://healthmate.withings.com/index/service/v2/link');
  #my $get_data = 'sessionid='.$hash->{IODev}->{SessionKey}.'&deviceid='.$hash->{Device}.'&appname=my2&appliver='.$hash->{IODev}->{helper}{appliver}.'&apppfm=web&action=get';
  #$request->content($get_data);
  #my $response = $ua->request($request);
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getDeviceLink ".$@;
    return undef;
  }
  Log3 $name, 1, "withings: getDeviceLink json error ".$json->{error} if(defined($json->{error}));

  foreach my $association (@{$json->{body}{associations}}) {
    next if( !defined($association->{deviceid}) );
    next if( $association->{deviceid} ne $hash->{Device} );
    return $association->{deviceproperties};
  }

  return undef;
}





sub withings_getDeviceProperties($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: getdeviceproperties ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/device",
    timeout => 30,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getproperties'},
      hash => $hash,
      type => 'deviceProperties',
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollProperties", $seconds, 0 );

  return undef;




}

sub withings_getDeviceReadingsGeneric($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getdevicereadings ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(24*60*60));
  $enddate = $now if ($enddate > $now);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 30,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, meastype => '12,13,14,15,35,56,58,74,75', startdate => int($lastupdate), enddate => int($enddate), devicetype => '16', appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getmeashf'},
      hash => $hash,
      type => 'deviceReadingsGeneric',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollData", $seconds, 0 );

  return undef;

}



sub withings_getDeviceEventsBaby($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getbabyevents ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);


  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/index/service/event",
    timeout => 30,
    noshutdown => 1,
    data => {activated => '0', action => 'get', sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, type => '10,11,12,13,14,15,20', begindate => int($lastupdate)},
      hash => $hash,
      type => 'deviceReadingsBaby',
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollData", $seconds, 0 );

  return undef;


}



sub withings_getDeviceAlertsHome($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: gethomealerts ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastAlert", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/timeline",
    timeout => 30,
    noshutdown => 1,
    data => {type => '1', callctx => 'foreground', action => 'getbydeviceid', appname => 'HomeMonitor', apppfm => 'ios', appliver => '20000', sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, lastupdate => int($lastupdate) },
      hash => $hash,
      type => 'deviceAlertsHome',
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollAlert", $seconds, 0 );

  return undef;


}


sub withings_getDeviceAlertsBaby($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getbabyevents ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastAlert", ($now-120*60) );
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/index/service/event",
    timeout => 30,
    noshutdown => 1,
    data => {activated => '1', action => 'get', sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, type => '10,11,12,13,14,15,20', begindate => int($lastupdate)},
      hash => $hash,
      type => 'deviceAlertsBaby',
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollAlert", $seconds, 0 );

  return undef;


}

sub withings_getVideoLink($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getbabyvideo ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://babyws.withings.net/cgi-bin/presence",
    timeout => 10,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid => $hash->{Device} , action => 'get'},
  });
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getVideoLink ".$@;
    return undef;
  }
  Log3 $name, 1, "withings: getVideoLink json error ".$json->{error} if(defined($json->{error}));

  if(defined($json->{body}{device}))
  {
    $hash->{videolink_ext} = "http://fpdownload.adobe.com/strobe/FlashMediaPlayback_101.swf?streamType=live&autoPlay=true&playButtonOverlay=false&src=rtmp://".$json->{body}{device}{proxy_ip}.":".$json->{body}{device}{proxy_port}."/".$json->{body}{device}{kp_hash}."/";
    $hash->{videolink_int} = "http://fpdownload.adobe.com/strobe/FlashMediaPlayback_101.swf?streamType=live&autoPlay=true&playButtonOverlay=false&src=rtmp://".$json->{body}{device}{private_ip}.":".$json->{body}{device}{proxy_port}."/".$json->{body}{device}{kd_hash}."/";
  }
  return $json;

}

sub withings_getS3Credentials($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return undef if( !defined($hash->{Device}) );

  return undef if( $hash->{sts_expiretime} && $hash->{sts_expiretime} > time - 3600 ); # min 1h

  return undef if( !defined($hash->{IODev}) );
  Log3 $name, 4, "$name: gets3credentials ".$hash->{Device};

  withings_getSessionKey( $hash->{IODev} );

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://scalews.withings.com/cgi-bin/v2/device",
    timeout => 10,
    noshutdown => 1,
    data => {callctx => 'foreground', action => 'getsts', deviceid => $hash->{Device}, appname => 'HomeMonitor', apppfm => 'ios' , appliver => '20000', sessionid => $hash->{IODev}->{SessionKey}},
  });
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getS3Credentials ".$@;
    return undef;
  }
  Log3 $name, 1, "withings: getS3Credentials json error ".$json->{error} if(defined($json->{error}));

  if(defined($json->{body}{sts}))
  {
    $hash->{sts_region} = $json->{body}{sts}{region};
    $hash->{sts_sessiontoken} = $json->{body}{sts}{sessiontoken};
    $hash->{sts_accesskeyid} = $json->{body}{sts}{accesskeyid};
    $hash->{sts_expiretime} = $json->{body}{sts}{expiretime};
    $hash->{sts_secretaccesskey} = $json->{body}{sts}{secretaccesskey};
    $hash->{sts_buckets} = (@{$json->{body}{sts}{buckets}}).join(",");
  }

  return $json;

}

sub withings_signS3Link($$$;$) {
  my ($hash,$url,$sign,$bucket) = @_;
  my $name = $hash->{NAME};

  withings_getS3Credentials($hash);

  my $signing = "GET\n\n\n";
  $signing .= $hash->{sts_expiretime}."\n";
  $signing .= "x-amz-security-token:".$hash->{sts_sessiontoken}."\n";
  $signing .= $sign;

  my $signature = hmac_sha1_base64($signing, $hash->{sts_secretaccesskey})."=";

  $url .= "?AWSAccessKeyId=".uri_escape($hash->{sts_accesskeyid});
  $url .= "&Expires=".$hash->{sts_expiretime};
  $url .= "&x-amz-security-token=".uri_escape($hash->{sts_sessiontoken});
  $url .= "&Signature=".uri_escape($signature);

  return $url;
}

sub withings_getUserDetail($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getuserdetails ".$hash->{User};
  return undef if( !defined($hash->{User}) );

  return undef if( $hash->{SUBTYPE} ne "USER" );

  return undef if( !defined($hash->{IODev}));
  withings_getSessionKey( $hash->{IODev} );

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://scalews.withings.com/index/service/user",
    timeout => 10,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid => $hash->{User} , appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getbyuserid'},
  });

  return undef if(!defined($data));
  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getUserDetail ".$@;
    return undef;
  }
  Log3 $name, 1, "withings: getUserDetail json error ".$json->{error} if(defined($json->{error}));

  return $json->{body}{users}[0];
}



sub withings_poll($;$) {
  my ($hash,$force) = @_;
  $force = 0 if(!defined($force));
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "withings_poll");

  return undef if(IsDisabled($name));


  #my $resolve = inet_aton("scalews.withings.com");
  #if(!defined($resolve))
  #{
  #  $hash->{STATE} = "DNS error" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  #  InternalTimer( gettimeofday() + 3600, "withings_poll", $hash, 0);
  #  return undef;
  #}



  my ($now) = int(time());

  if( $hash->{SUBTYPE} eq "DEVICE" ) {
    my $intervalData = AttrVal($name,"intervalData",900);
    my $intervalDebug = AttrVal($name,"intervalDebug",AttrVal($name,"intervalData",900));
    my $intervalProperties = AttrVal($name,"intervalProperties",AttrVal($name,"intervalData",900));
    my $lastData = ReadingsVal( $name, ".pollData", 0 );
    my $lastDebug = ReadingsVal( $name, ".pollDebug", 0 );
    my $lastProperties = ReadingsVal( $name, ".pollProperties", 0 );

    if(defined($hash->{modelID}) && $hash->{modelID} eq '4') {
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getDeviceReadingsGeneric($hash) if($force || $lastData <= ($now - $intervalData));
    }
    elsif(defined($hash->{modelID}) && $hash->{modelID} eq '21') {
      my $intervalAlert = AttrVal($name,"intervalAlert",120);
      my $lastAlert = ReadingsVal( $name, ".pollAlert", 0 );
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getDeviceEventsBaby($hash) if($force || $lastData <= ($now - $intervalData));
      #withings_getDeviceAlertsBaby($hash) if($force || $lastAlert <= ($now - $intervalAlert));
    }
    elsif(defined($hash->{modelID}) && $hash->{modelID} eq '22') {
      my $intervalAlert = AttrVal($name,"intervalAlert",120);
      my $lastAlert = ReadingsVal( $name, ".pollAlert", 0 );
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getDeviceReadingsGeneric($hash) if($force || $lastData <= ($now - $intervalData));
      withings_getDeviceAlertsHome($hash) if($force || $lastAlert <= ($now - $intervalAlert));
    }
    elsif(defined($hash->{typeID}) && $hash->{typeID} eq '16') {
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getUserReadingsActivity($hash) if($force || $lastData <= ($now - $intervalData));
    }
    elsif(defined($hash->{modelID}) && $hash->{modelID} eq '60') {
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getDeviceReadingsGeneric($hash) if($force || $lastData <= ($now - $intervalData));
    }
    elsif(defined($hash->{modelID}) && ($hash->{modelID} eq '61' || $hash->{modelID} eq '62' || $hash->{modelID} eq '63')) {
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getUserReadingsSleep($hash) if($force || $lastData <= ($now - $intervalData));
      withings_getUserReadingsSleepDebug($hash) if($force || $lastDebug <= ($now - $intervalDebug));
      #if(defined($hash->{modelID}) && ($hash->{modelID} eq '63')){
      #  withings_getDeviceReadingsGeneric($hash) if($force || $lastData <= ($now - $intervalData));
      #}
    }
    else
    {
      withings_getDeviceProperties($hash) if($force || $lastProperties <= ($now - $intervalProperties));
      withings_getDeviceReadingsGeneric($hash) if($force || $lastData <= ($now - $intervalData));
    }
  } elsif( $hash->{SUBTYPE} eq "DUMMY" ) {
    my $intervalData = AttrVal($name,"intervalData",900);
    my $lastData = ReadingsVal( $name, ".pollData", 0 );
    if($hash->{typeID} eq '16') {
      withings_getUserReadingsActivity($hash) if($force || $lastData <= ($now - $intervalData));
    }
  } elsif( $hash->{SUBTYPE} eq "USER" ) {

    my $intervalData = AttrVal($name,"intervalData",900);
    my $intervalDaily = AttrVal($name,"intervalDaily",(6*60*60));
    my $lastData = ReadingsVal( $name, ".pollData", 0 );
    my $lastDaily = ReadingsVal( $name, ".pollDaily", 0 );

    withings_getUserReadingsCommon($hash) if($force || $lastData <= ($now - $intervalData));
    withings_getUserReadingsDaily($hash) if($force || $lastDaily <= ($now - $intervalDaily));
  }

  InternalTimer(gettimeofday()+60, "withings_poll", $hash, 0);
}





sub withings_getUserReadingsDaily($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getuserdailystats ".$hash->{User} if(defined($hash->{User}));

  return undef if( !defined($hash->{User}) );
  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastAggregate", ($now-21*24*60*60) );#$hash->{created} );#
  my $enddate = ($lastupdate+(14*24*60*60));
  $enddate = $now if ($enddate > $now);

  my $startdateymd = strftime("%Y-%m-%d", localtime($lastupdate));
  my $enddateymd = strftime("%Y-%m-%d", localtime($enddate));

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/aggregate",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey},  userid=> $hash->{User}, range => '1', meastype => '36,37,38,40,41,49,50,51,52,53,87', startdateymd => $startdateymd, enddateymd => $enddateymd, appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getbyuserid'},
      hash => $hash,
      type => 'userDailyAggregate',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  $lastupdate = ReadingsVal( $name, ".lastActivity", ($now-21*24*60*60) );#$hash->{created} );
  $enddate = ($lastupdate+(14*24*60*60));
  $enddate = $now if ($enddate > $now);

  $startdateymd = strftime("%Y-%m-%d", localtime($lastupdate));
  $enddateymd = strftime("%Y-%m-%d", localtime($enddate));

  HttpUtils_NonblockingGet({ #sleep daily data?
    url => "https://scalews.withings.com/cgi-bin/v2/activity",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey},  userid=> $hash->{User}, subcategory => '37', startdateymd => $startdateymd, enddateymd => $enddateymd, appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getbyuserid'},
      hash => $hash,
      type => 'userDailyActivity',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollDaily", $seconds, 0 );

  return undef;


}



sub withings_getUserReadingsCommon($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getuserreadings ".$hash->{User} if(defined($hash->{User}));

  return undef if( !defined($hash->{User}) );
  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-100*24*60*60) );#$hash->{created} );#
  my $enddate = ($lastupdate+(100*24*60*60));
  $enddate = $now if ($enddate > $now);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/measure",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, category => '1', userid=> $hash->{User}, offset => '0', limit => '400', startdate => int($lastupdate), enddate => int($enddate), appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getmeas'},
      hash => $hash,
      type => 'userReadingsCommon',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollData", $seconds, 0 );

  return undef;


}




sub withings_getUserReadingsSleep($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getsleepreadings ".$hash->{User} if(defined($hash->{User}));

  return undef if( !defined($hash->{User}) );
  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(24*60*60));
  $enddate = $now if ($enddate > $now);
  #    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '43,44,11,57,59,60,61,62,63,64,65,66,67,68,69,70', startdate => int($lastupdate), enddate => int($enddate), devicetype => '32', appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},

#https://scalews.withings.com/cgi-bin/v2/measure?meastype=11,39,41,43,44,57,60,61,62,63,64,65,66,67,68,69,87,121&action=getvasistas&userid=2530001&vasistas_category=bed&startdate=1543273200&enddate=1543359599&appname=hmw&apppfm=web&appliver=f692c27
#https://scalews.withings.com/cgi-bin/v2/measure?meastype=11,43,73,89&action=getvasistas&userid=8087167&vasistas_category=hr&startdate=1543014000&enddate=1543100399&appname=hmw&apppfm=web&appliver=1e23b12
#https://scalews.withings.com/cgi-bin/v2/measure?meastype=36,37,39,40,41,42,43,44,59,70,87,90,120&action=getvasistas&userid=8087167&vasistas_category=tracker&startdate=1543014000&enddate=1543100399&appname=hmw&apppfm=web&appliver=1e23b12
#https://scalews.withings.com/cgi-bin/v2/measure?meastype=38,45,72,96,97,98,99,100,101&action=getvasistas&userid=2530001&devicetype=128&startdate=1543273200&enddate=1543359599&appname=hmw&apppfm=web&appliver=f692c27
#
#https://scalews.withings.com/cgi-bin/v2/measure?meastype=11,36,37,38,39,40,41,42,43,44,45,57,59,60,61,62,63,64,65,66,67,68,69,70,72,73,87,89,90,96,97,98,99,100,101,120,121&action=getvasistas&userid=2530001&devicetype=128&startdate=1543273200&enddate=1543359599&appname=hmw&apppfm=web&appliver=f692c27
#https://scalews.withings.com/cgi-bin/v2/measure?meastype=11,36,37,38,39,40,41,42,43,44,45,57,59,60,61,62,63,64,65,66,67,68,69,70,72,73,87,89,90,96,97,98,99,100,101,120,121&action=getvasistas&userid=2530001&devicetype=16&startdate=1543273200&enddate=1543359599&appname=hmw&apppfm=web&appliver=f692c27
# 16 - 36,37,39,40,41,42,87,90,120
# 32 - 11,43,44,57,60,61,62,63,64,65,66,67,68,69,121,129
# ?? -


  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '11,39,41,43,44,57,59,87,121,129', startdate => int($lastupdate), enddate => int($enddate), devicetype => '32', appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},
      hash => $hash,
      type => 'userReadingsSleep',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollData", $seconds, 0 );

  return undef;

}


sub withings_getUserReadingsSleepDebug($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: getsleepreadingsdebug ".$hash->{User} if(defined($hash->{User}));

  return undef if( !defined($hash->{User}) );
  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastDebug", ($now-7*24*60*60) );#$hash->{created} );
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(24*60*60));
  $enddate = $now if ($enddate > $now);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '60,61,62,63,64,65,66,67,68,69,70', startdate => int($lastupdate), enddate => int($enddate), devicetype => '32', appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},
      hash => $hash,
      type => 'userReadingsSleepDebug',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollDebug", $seconds, 0 );

  return undef;

}



sub withings_getUserReadingsActivity($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: getactivityreadings ".$hash->{User} if(defined($hash->{User}));

  return undef if( !defined($hash->{User}) );
  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(24*60*60));
  $enddate = $now if ($enddate > $now);

 Log3 $name, 5, "$name: getactivityreadings ".$lastupdate." to ".$enddate;

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '36,37,38,39,40,41,42,43,44,59,70,87,90,120,128,132', startdate => int($lastupdate), enddate => int($enddate), devicetype => '16', appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},
      hash => $hash,
      type => 'userReadingsActivity',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollData", $seconds, 0 );

  return undef;


}



sub withings_parseProperties($$) {
  my ($hash,$json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: parsedevice";

  #parse
  my $detail = $json->{body};

  readingsBeginUpdate($hash);

  if( defined($detail->{batterylvl}) and $detail->{batterylvl} > 0 and $detail->{type} ne '32' and $detail->{model} ne '22') {
    readingsBulkUpdate( $hash, "batteryPercent", $detail->{batterylvl}, 1 );
    readingsBulkUpdate( $hash, "batteryState", ($detail->{batterylvl}>20?"ok":"low"), 1 );
  }
  readingsBulkUpdate( $hash, "lastWeighinDate", FmtDateTime($detail->{lastweighindate}), 1 ) if( defined($detail->{lastweighindate}) and $detail->{lastweighindate} > 0  and $detail->{model} ne '60' );
  readingsBulkUpdate( $hash, "lastSessionDate", FmtDateTime($detail->{lastsessiondate}), 1 ) if( defined($detail->{lastsessiondate}) );
  $hash->{lastsessiondate} = $detail->{lastsessiondate} if( defined($detail->{lastsessiondate}) );

  readingsEndUpdate($hash,1);

}

sub withings_parseMeasureGroups($$) {
  my ($hash, $json) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 5, "$name: parsemeasuregroups";
  my ($now) = int(time);
  my $lastupdate = ReadingsVal( $name, ".lastData", 0 );# ($now-21*24*60*60)
  my $newlastupdate = $lastupdate;

    $hash->{status} = $json->{status};
    if( $hash->{status} == 0 ) {
      my $i = 0;

      foreach my $measuregrp ( sort { $a->{date} <=> $b->{date} } @{$json->{body}{measuregrps}}) {
        if( $measuregrp->{date} < $newlastupdate )
        {
          Log3 $name, 4, "$name: old measuregroup skipped: ".FmtDateTime($measuregrp->{date});
          next;
        }

        $newlastupdate = $measuregrp->{date};

        foreach my $measure (@{$measuregrp->{measures}}) {
          my $reading = $measure_types{$measure->{type}}->{reading};
          if( !defined($reading) ) {
            Log3 $name, 1, "$name: unknown measure type: $measure->{type} ".Dumper($measure);
            next;
          }

          #fix for duplicate pulseWave value
          $reading = "pulseWaveRaw" if($measure->{type} == 91 && $measuregrp->{attrib} == 0);

          my $value = $measure->{value} * 10 ** $measure->{unit};

          if($reading eq "heartECG")
          {
            my $rawvalue = $value;
            $value = $ecg_types{$value};
            if( !defined($value) ) {
              Log3 $name, 1, "$name: unknown ECG type: $rawvalue";
              $value = $rawvalue;
            }
          }
          if($reading eq "heartSounds")
          {
            my $rawvalue = $value;
            $value = $heart_types{$value};
            if( !defined($value) ) {
              Log3 $name, 1, "$name: unknown heartSound type: $rawvalue";
              $value = $rawvalue;
            }
          }

          readingsBeginUpdate($hash);
          $hash->{".updateTimestamp"} = FmtDateTime($measuregrp->{date});
          readingsBulkUpdate( $hash, $reading, $value, 1 );
          $hash->{CHANGETIME}[0] = FmtDateTime($measuregrp->{date});
          readingsEndUpdate($hash,1);
          $i++;
        }
      }


      if($newlastupdate == $lastupdate and $i == 0)
      {
        my $user = withings_getUserDetail( $hash );
        $hash->{modified} = $user->{modified};

        $newlastupdate = $json->{requestedenddate} if($json->{requestedenddate});
        $newlastupdate = $user->{modified} if($user->{modified} and $user->{modified} < $newlastupdate);
      }
      $newlastupdate = $now if($newlastupdate > $now);
      if($newlastupdate < $lastupdate-1)
      {
        Log3 $name, 2, "$name: Measuregroups gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate-1).") ".$i if($i>0);
        withings_getDeviceProperties($hash) if($i>0);
        $newlastupdate = $lastupdate-1;
      }

     $hash->{LAST_DATA} = FmtDateTime( $newlastupdate );
     $newlastupdate = int(time) if($newlastupdate > (time+3600));
     readingsSingleUpdate( $hash, ".lastData", $newlastupdate+1, 0 );


     delete $hash->{CHANGETIME};
     Log3 $name, (($i>0)?3:4), "$name: got ".$i.' entries from MeasureGroups (latest: '.FmtDateTime($newlastupdate).')';

    }

}

sub withings_parseMeasurements($$) {
  my ($hash, $json) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 4, "$name: parsemeasurements";
  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", 0 );#($now-21*24*60*60)
  my $newlastupdate = $lastupdate;
  my $i = 0;

  if( $json )
  {
    $hash->{status} = $json->{status};

    my @readings = ();
    if( $hash->{status} == 0 )
    {

      foreach my $series ( @{$json->{body}{series}}) {
        my $reading = $measure_types{$series->{type}}->{reading};
        if( !defined($reading) ) {
          Log3 $name, 1, "$name: unknown measure type: $series->{type} ".Dumper($series);
          next;
        }

        foreach my $measure (@{$series->{data}}) {

          my $value = $measure->{value};
          push(@readings, [$measure->{date}, $reading, $value]);
        }
      }

      if( @readings ) {
        $i = 0;
        foreach my $reading (sort { $a->[0] <=> $b->[0] } @readings) {
          if( $reading->[0] < $newlastupdate )
          {
            Log3 $name, 5, "$name: old measurement skipped: ".FmtDateTime($reading->[0])." ".$reading->[1];
            next;
          }
          $newlastupdate = $reading->[0];

          readingsBeginUpdate($hash);
          $hash->{".updateTimestamp"} = FmtDateTime($reading->[0]);
          readingsBulkUpdate( $hash, $reading->[1], $reading->[2], 1 );
          $hash->{CHANGETIME}[0] = FmtDateTime($reading->[0]);;
          readingsEndUpdate($hash,1);
          $i++;
        }



      }

      if($newlastupdate == $lastupdate and $i == 0)
      {
        my $device = withings_getDeviceDetail( $hash );
        $newlastupdate = $json->{requestedenddate} if($json->{requestedenddate});
        $newlastupdate = $device->{lastsessiondate} if($device->{lastsessiondate} and $device->{lastsessiondate} < $newlastupdate);
        $newlastupdate = $device->{lastweighindate} if($device->{lastweighindate} and $device->{lastweighindate} < $newlastupdate);

      }
      $newlastupdate = $now if($newlastupdate > $now);
      if($newlastupdate < $lastupdate-1)
      {
        Log3 $name, 2, "$name: Measurements gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate-1).") ".$i if($i>0);
        withings_getDeviceProperties($hash) if($i>0);
        $newlastupdate = $lastupdate-1;
      }

      $hash->{LAST_DATA} = FmtDateTime( $newlastupdate );
      $newlastupdate = int(time) if($newlastupdate > (time+3600));
      readingsSingleUpdate( $hash, ".lastData", $newlastupdate+1, 0 );


      delete $hash->{CHANGETIME};
      Log3 $name, (($i>0)?3:4), "$name: got ".$i.' entries from Measurements (latest: '.FmtDateTime($newlastupdate).')';


    }
  }



}



sub withings_parseAggregate($$) {
  my ($hash, $json) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 5, "$name: parseaggregate";

  #return undef;
  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastAggregate", 0 );#($now-21*24*60*60)
  my $newlastupdate = $lastupdate;
  my $i = 0;
  my $unfinished;

  if( $json )
  {
    $hash->{status} = $json->{status};

    my @readings = ();
    if( $hash->{status} == 0 )
    {

      if(defined($json->{body}{series}))
      {

        my $series = $json->{body}->{series};

        foreach my $serieskey ( keys %$series)
        {


            if(defined($series->{$serieskey}))
            {
              my $typestring = substr($serieskey, -2);
              my $serieshash = $json->{body}->{series}{$serieskey};
              next if(ref($serieshash) ne "HASH");

              foreach my $daykey ( keys %$serieshash)
              {
                my $dayhash = $json->{body}->{series}{$serieskey}{$daykey};
                next if(ref($dayhash) ne "HASH");

                if(!$dayhash->{complete})
                {
                  $unfinished = 1;
                  next;
                }

                my ($year,$mon,$day) = split(/[\s-]+/, $daykey);
                my $timestamp = timelocal(0,0,18,$day,$mon-1,$year-1900);
                #my $timestamp = $dayhash->{midnight};
                my $reading = $measure_types{$typestring}->{dailyreading};
                if( !defined($reading) ) {
                  Log3 $name, 1, "$name: unknown aggregate measure type: $typestring";
                  next;
                }
                my $value = $dayhash->{sum};

                push(@readings, [$timestamp, $reading, $value]);
              }
            }
         }
       }

      if( @readings )
      {
        $i = 0;
        foreach my $reading (sort { $a->[0] <=> $b->[0] } @readings)
        {
          if( $reading->[0] < $newlastupdate )
          {
            Log3 $name, 5, "$name: old aggregate skipped: ".FmtDateTime($reading->[0])." ".$reading->[1];
            next;
          }

          $newlastupdate = $reading->[0];

          readingsBeginUpdate($hash);
          $hash->{".updateTimestamp"} = FmtDateTime($reading->[0]);
          readingsBulkUpdate( $hash, $reading->[1], $reading->[2], 1 );
          $hash->{CHANGETIME}[0] = FmtDateTime($reading->[0]);
          readingsEndUpdate($hash,1);
          $i++;
        }

      }


      if($newlastupdate == $lastupdate and $i == 0)
      {
        $newlastupdate = $lastupdate - 1; #$json->{requestedenddate} if($json->{requestedenddate});
      }
      $newlastupdate = $now if($newlastupdate > $now);
      if($newlastupdate < $lastupdate-1)
      {
        Log3 $name, 2, "$name: Aggregate gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate-1).") ".$i if($i>0);
        withings_getDeviceProperties($hash) if($i>0);
        $newlastupdate = $lastupdate-1;
      }

      readingsSingleUpdate( $hash, ".lastAggregate", $newlastupdate+1, 0 );
      #$hash->{LAST_DATA} = FmtDateTime( $newlastupdate );


      delete $hash->{CHANGETIME};
      Log3 $name, (($i>0)?3:4), "$name: got ".$i.' entries from Aggregate (latest: '.FmtDateTime($newlastupdate).')';


    }
  }



}


sub withings_parseActivity($$) {
  my ($hash, $json) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 5, "$name: parseactivity";

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastActivity", 0);#($now-21*24*60*60);
  my $newlastupdate = $lastupdate;
  my $i = 0;
  my $unfinished;

  if( $json )
  {
    $hash->{status} = $json->{status};

    my @readings = ();
    if( $hash->{status} == 0 )
    {

      foreach my $series ( @{$json->{body}{series}})
      {
        if($series->{completed} ne '1')
        {
          $unfinished = 1;
          next;
        }

        my $duration = 0;
        foreach my $dataset ( keys (%{$series->{data}}))
        {
          if(!defined($sleep_readings{$dataset}->{reading}))
          {
            Log3 $name, 2, "$name: unknown activity/sleep reading $dataset";
            next;
          }

          my ($year,$mon,$day) = split(/[\s-]+/, $series->{date});
          my $timestamp = timelocal(0,0,6,$day,$mon-1,$year-1900);
          my $reading = $sleep_readings{$dataset}->{reading};
          my $value = $series->{data}{$dataset};

          next if($reading eq "heartrateResting" && $value == 0);

          push(@readings, [$timestamp, $reading, $value]);

          if($reading eq "sleepDurationLight" || $reading eq "sleepDurationDeep" || $reading eq "sleepDurationREM" || $reading eq "sleepDurationManual"){
            $duration += $value;
          }

        }

        my ($year,$mon,$day) = split(/[\s-]+/, $series->{date});
        my $timestamp = timelocal(0,0,6,$day,$mon-1,$year-1900);
        push(@readings, [$timestamp, "sleepDurationTotal", $duration]);

        if(defined($series->{sleep_score})){
          if(defined($series->{sleep_score}{score})){
            push(@readings, [$timestamp, "sleepScore", $series->{sleep_score}{score}]);
          }
        }

        push(@readings, [$timestamp, "snoringEnabled", $series->{snoring_enabled}]) if(defined($series->{snoring_enabled}));
        push(@readings, [$timestamp, "sleepBlanksFilled", $series->{blank_vasistas_filled}]) if(defined($series->{blank_vasistas_filled}));
     }


      if( @readings ) {
        $i = 0;
        foreach my $reading (sort { $a->[0] <=> $b->[0] } @readings) {
          if( $reading->[0] < $newlastupdate )
          {
            Log3 $name, 4, "$name: old activity skipped: ".FmtDateTime($reading->[0])." ".$reading->[1];
            next;
          }

          $newlastupdate = $reading->[0];

          readingsBeginUpdate($hash);
          $hash->{".updateTimestamp"} = FmtDateTime($reading->[0]);
          readingsBulkUpdate( $hash, $reading->[1], $reading->[2], 1 );
          $hash->{CHANGETIME}[0] = FmtDateTime($reading->[0]);
          readingsEndUpdate($hash,1);
          $i++;
        }

      }

      if($newlastupdate == $lastupdate and $i == 0)
      {
        $newlastupdate = $lastupdate - 1; #$json->{requestedenddate} if($json->{requestedenddate});
      }
      $newlastupdate = $now if($newlastupdate > $now);
      if($newlastupdate < $lastupdate-1)
      {
        Log3 $name, 2, "$name: Activity gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate).") .$i if($i>0)";
        withings_getDeviceProperties($hash) if($i>0);
        $newlastupdate = $lastupdate-1;
      }

      $newlastupdate = $newlastupdate+(24*60*60) if($lastupdate == $newlastupdate && ($newlastupdate+(24*60*60)) < time());
      readingsSingleUpdate( $hash, ".lastActivity", $newlastupdate, 0 );
      #$hash->{LAST_DATA} = FmtDateTime( $newlastupdate );


      delete $hash->{CHANGETIME};
      Log3 $name, (($i>0)?3:4), "$name: got ".$i.' entries from Activity (latest: '.FmtDateTime($newlastupdate).')';


    }
  }



}


sub withings_parseWorkouts($$) {
  my ($hash, $json) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 1, "$name: parseworkouts\n".Dumper($json);

return undef;
}




sub withings_parseVasistas($$;$) {
  my ($hash, $json, $datatype) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 5, "$name: parsevasistas";

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", 0 );#($now-21*24*60*60)
  $lastupdate = ReadingsVal( $name, ".lastDebug", 0 ) if($datatype =~ /Debug/);#($now-21*24*60*60)

  if( $json ) {
    $hash->{status} = $json->{status};
    if( $hash->{status} == 0 ) {
    my @readings = ();
    my $i = 0;
    my $j;
    my $k;
    my $readingsdate;
    my $newlastupdate = $lastupdate;

    my $iscurrent = 0;

    foreach my $series ( @{$json->{body}{series}}) {
      $j=0;
      my @types= (@{$series->{types}});
      my @dates= (@{$series->{dates}});
      my @values= (@{$series->{vasistas}});

      foreach $readingsdate (@dates) {
        my @readingsvalue = (@{$values[$j++]});
        if($readingsdate <= $lastupdate)
        {
          Log3 $name, 5, "$name: old vasistas skipped: ".FmtDateTime($readingsdate);
          next;
        }

        $k=0;
        foreach my $readingstype (@types) {

          my $updatetime = FmtDateTime($readingsdate);
          my $updatevalue = $readingsvalue[$k++];
          my $updatetype = $measure_types{$readingstype}->{reading};
          if( !defined($updatetype) ) {
            Log3 $name, 1, "$name: unknown measure type: $readingstype";
            next;
          }
          if(($updatetype eq "breathing") and ($updatevalue > 90)) {
            Log3 $name, 2, "$name: Implausible Aura reading ".$updatetime.'  '.$updatetype.': '.$updatevalue;
            $newlastupdate = $readingsdate if($readingsdate > $newlastupdate);
            next;
          }
          if($updatetype eq "duration")
          {
            Log3 $name, 4, "$name: Duration skipped ".$updatetime.'  '.$updatetype.': '.$updatevalue if($updatevalue > 90);
            $newlastupdate = $readingsdate if($readingsdate > $newlastupdate);
            next;
          }
          if($updatetype eq "pressure") {
            $updatevalue = $updatevalue * 0.01;
            Log3 $name, 5, "$name: Aura reading calculated ".$updatetime.'  '.$updatetype.': '.$updatevalue;
          }
          if($updatetype eq "sleepstate")
          {
            my $rawvalue = $updatevalue;
            $updatevalue = $sleep_states{$updatevalue};
            if( !defined($updatevalue) ) {
              Log3 $name, 1, "$name: unknown sleep state: $rawvalue";
              $updatevalue = $rawvalue;
            }
          }
          if($updatetype eq "activityType")
          {
            my $rawvalue = $updatevalue;
            $updatevalue = $activity_types{$updatevalue};
            if( !defined($updatevalue) ) {
              Log3 $name, 1, "$name: unknown activity type: $rawvalue";
              $updatevalue = $rawvalue;
            }
          }
          readingsBeginUpdate($hash);
          $hash->{".updateTimestamp"} = FmtDateTime($readingsdate);
          readingsBulkUpdate( $hash, $updatetype, $updatevalue, 1 );
          $hash->{CHANGETIME}[0] = FmtDateTime($readingsdate);
          readingsEndUpdate($hash,1);

          if($updatetype ne "unknown") {
            $newlastupdate = $readingsdate if($readingsdate > $newlastupdate);
            $i++;
          }
#start in-bed detection
          if($hash->{modelID} eq "61" && $datatype =~ /Sleep/ && $iscurrent == 0){
            if($i>40 && $readingsdate > time()-3600){
              $iscurrent = 1;
              #Log3 $name, 1, "$name: in-bed: ".FmtDateTime($readingsdate) if($i>0);
              readingsBeginUpdate($hash);
              $hash->{".updateTimestamp"} = FmtDateTime($readingsdate);
              readingsBulkUpdate( $hash, "in_bed", 1, 1 );
              $hash->{CHANGETIME}[0] = FmtDateTime($readingsdate);
              readingsEndUpdate($hash,1);
            }
          }
#end in-bed detection
        }
      }
    }
    if($newlastupdate == $lastupdate and $i == 0)
    {
      my $device = withings_getDeviceDetail( $hash );
      $newlastupdate = $json->{requestedenddate} if($json->{requestedenddate});
      $newlastupdate = $device->{lastsessiondate} if($device->{lastsessiondate} and $device->{lastsessiondate} < $newlastupdate);
      $newlastupdate = $device->{lastweighindate} if($device->{lastweighindate} and $device->{lastweighindate} < $newlastupdate);

      #start in-bed detection
      if($hash->{modelID} eq "61" && $datatype =~ /Sleep/ && $iscurrent == 0){
        if($device->{lastweighindate} > (time()-1800)){
          readingsSingleUpdate( $hash, "in_bed", 1, 1 );
        } else {
          readingsSingleUpdate( $hash, "in_bed", 0, 1 );
        }
      }
      #end in-bed detection
    }
    $newlastupdate = $now if($newlastupdate > $now);
    if($newlastupdate < ($lastupdate-1))
    {
      Log3 $name, 2, "$name: Vasistas gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate-1).") ".$i if($i>0);
      withings_getDeviceProperties($hash) if($i>0);
      $newlastupdate = $lastupdate;
    }

    my ($seconds) = gettimeofday();

    $hash->{LAST_DATA} = FmtDateTime( $newlastupdate );
    $newlastupdate = int(time) if($newlastupdate > (time+3600));

   if($datatype =~ /Debug/)
   {
     readingsSingleUpdate( $hash, ".lastDebug", $newlastupdate, 0 );
   } else {
     readingsSingleUpdate( $hash, ".lastData", $newlastupdate, 0 );
   }

    Log3 $name, (($i>0)?3:4), "$name: got ".$i.' entries from Vasistas (latest: '.FmtDateTime($newlastupdate).')';

    }
  }


}


sub withings_parseTimeline($$) {
  my ($hash, $json) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 5, "$name: parsemetimeline ";

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastAlert", 0 );#($now-21*24*60*60)
  my $newlastupdate = $lastupdate;

    $hash->{status} = $json->{status};
    if( $hash->{status} == 0 )
    {
      my $i = 0;

      foreach my $event ( sort { $a->{epoch} <=> $b->{epoch} } @{$json->{body}{timeline}}) {
        if( $event->{epoch} < $newlastupdate )
        {
          Log3 $name, 5, "$name: old timeline event skipped: ".FmtDateTime($event->{epoch})." $event->{class}";
          next;
        }
        $newlastupdate = $event->{epoch};
        if($event->{class} eq 'period_activity' or $event->{class} eq 'period_activity_start' or $event->{class} eq 'period_activity_cancel' or $event->{class} eq 'period_offline')
        {
          next;
        }
        elsif($event->{class} eq 'deleted')
        {
          Log3 $name, 5, "withings: event " . FmtDateTime($event->{epoch})." Event was deleted";
          next;
        }
        elsif($event->{class} ne 'noise_detected' && $event->{class} ne 'movement_detected' && $event->{class} ne 'alert_environment' && $event->{class} ne 'offline' && $event->{class} ne 'online' && $event->{class} ne 'snapshot')
        {
          Log3 $name, 2, "withings: alert class unknown " . $event->{class};
          next;
        }


        my $reading = $timeline_classes{$event->{class}}->{reading};
        my $value = "alert";
        $value = $event->{data}->{value} * 10 ** $timeline_classes{$event->{class}}->{unit} if(defined($event->{class}) && defined($event->{data}) && defined($event->{data}->{value}) && defined($timeline_classes{$event->{class}}) && defined($timeline_classes{$event->{class}}->{unit}));

        if( !defined($reading) ) {
          Log3 $name, 2, "$name: unknown event type: $event->{class}";
          next;
        }
        else
        {
          readingsBeginUpdate($hash);
          $hash->{".updateTimestamp"} = FmtDateTime($event->{epoch});
          readingsBulkUpdate( $hash, $reading, $value, 1 );
          $hash->{CHANGETIME}[0] = FmtDateTime($event->{epoch});
          readingsEndUpdate($hash,1);
          $i++;
        }
        if(AttrVal($name,"videoLinkEvents",0) eq "1")
        {
          my $pathlist = $event->{data}->{path_list}[0];
          my $eventurl = withings_signS3Link($hash,$pathlist->{url},$pathlist->{sign});
          DoTrigger($name, "alerturl: ".$eventurl);
        }
      }

      if($newlastupdate == $lastupdate and $i == 0)
      {
        my $device = withings_getDeviceDetail( $hash );
        $newlastupdate = $json->{requestedenddate} if(defined($json->{requestedenddate}));
        $newlastupdate = $device->{lastsessiondate} if($device->{lastsessiondate} and $device->{lastsessiondate} < $newlastupdate);
        $newlastupdate = $device->{lastweighindate} if($device->{lastweighindate} and $device->{lastweighindate} < $newlastupdate);

      }
      $newlastupdate = $now if($newlastupdate > $now);
      if($newlastupdate < $lastupdate-1)
      {
        Log3 $name, 2, "$name: Timeline gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate-1).") ".$i if($i>0);
        withings_getDeviceProperties($hash) if($i>0);
        $newlastupdate = $lastupdate-1;
      }

     readingsSingleUpdate( $hash, ".lastAlert", $newlastupdate+1, 0 );
     #$hash->{LAST_DATA} = FmtDateTime( $lastupdate );


     delete $hash->{CHANGETIME};
     Log3 $name, (($i>0)?3:4), "$name: got ".$i.' entries from Timeline (latest: '.FmtDateTime($newlastupdate).')';

    }

}


sub withings_parseEvents($$) {
  my ($hash, $json) = @_;
  my $name = $hash->{NAME};
  #parse
  Log3 $name, 5, "$name: parseevents";
  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", 0 );#($now-21*24*60*60)
  my $lastalertupdate = ReadingsVal( $name, ".lastAlert", 0 );#($now-21*24*60*60)
  my $newlastupdate = $lastupdate;

    $hash->{status} = $json->{status};
    if( $hash->{status} == 0 ) {
      my $i = 0;
      foreach my $event ( sort { $a->{date} <=> $b->{date} } @{$json->{body}{events}}) {
        if( $event->{date} < $newlastupdate )
        {
          Log3 $name, 5, "$name: old event skipped: ".FmtDateTime($event->{date})." $event->{type}";
          next;
        }
        next if( $event->{deviceid} ne $hash->{Device} );
        $newlastupdate = $event->{date};

        readingsBeginUpdate($hash);
        $hash->{".updateTimestamp"} = FmtDateTime($event->{date});
        my $changeindex = 0;

        #Log3 $name, 5, "withings: event " . FmtDateTime($event->{date})." ".$event->{type}." ".$event->{activated}."/".$event->{measure}{value};

        my $reading = $event_types{$event->{type}}->{reading};
        my $value = "notice";
        if($event->{activated})
        {
          $lastalertupdate = $event->{date};
          $value = "alert";
        }

        if( !defined($reading) ) {
          Log3 $name, 2, "$name: unknown event type: $event->{type}";
          next;
        }
        else
        {
          readingsBulkUpdate( $hash, $reading, $value, 1 );
          $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($event->{date});
        }

        if(defined($event->{duration}) and $event->{duration} ne "0")
        {
          my $durationreading = $event_types{$event->{type}}->{duration};
          my $durationvalue = $event->{duration};

          readingsBulkUpdate( $hash, $durationreading, $durationvalue, 0 );
          $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($event->{date});

        }

        if($event->{type} ne "20" and $event->{activated})
        {
          my $thresholdreading = $event_types{$event->{type}}->{threshold};
          my $thresholdvalue = $event->{threshold}->{value} * 10 ** $event_types{$event->{type}}->{unit};

          readingsBulkUpdate( $hash, $thresholdreading, $thresholdvalue, 0 );
          $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($event->{date});
        }


        readingsEndUpdate($hash,1);
        $i++;
      }

      if($newlastupdate == $lastupdate and $i == 0)
      {
        my $device = withings_getDeviceDetail( $hash );
        $newlastupdate = $json->{requestedenddate} if($json->{requestedenddate});
        $newlastupdate = $device->{lastsessiondate} if($device->{lastsessiondate} and $device->{lastsessiondate} < $newlastupdate);
        $newlastupdate = $device->{lastweighindate} if($device->{lastweighindate} and $device->{lastweighindate} < $newlastupdate);

      }
      $newlastupdate = $now if($newlastupdate > $now);
      if($newlastupdate < $lastupdate-1)
      {
        Log3 $name, 2, "$name: Events gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate-1).") ".$i if($i>0);
        withings_getDeviceProperties($hash) if($i>0);
        $newlastupdate = $lastupdate-1;
      }

      $hash->{LAST_DATA} = FmtDateTime( $newlastupdate );
      $newlastupdate = int(time) if($newlastupdate > (time+3600));
      $lastalertupdate = int(time) if($lastalertupdate > (time+3600));

      readingsBeginUpdate($hash);
      readingsBulkUpdate( $hash, ".lastAlert", $lastalertupdate, 0 );
      readingsBulkUpdate( $hash, ".lastData", $newlastupdate+1, 0 );
      readingsEndUpdate($hash,0);



      delete $hash->{CHANGETIME};
      Log3 $name, (($i>0)?3:4), "$name: got ".$i.' entries from Events (latest: '.FmtDateTime($newlastupdate).')';

      }

}


sub withings_Get($$@) {
  my ($hash, $name, $cmd) = @_;

  my $list;
  if( $hash->{SUBTYPE} eq "USER" ) {
    $list = "update:noArg updateAll:noArg showKey:noArg";
    $list .= " showSubscriptions:noArg" if($hash->{helper}{OAuthKey});
    if( $cmd eq "updateAll" ) {
      withings_poll($hash,2);
      return undef;
    }
    elsif( $cmd eq "update" ) {
      withings_poll($hash,1);
      return undef;
    }
    if( $cmd eq 'showKey' )
    {
      my $key = $hash->{helper}{Key};
      return 'no key set' if( !$key || $key eq "" || $key eq "crypt:" );
      $key = withings_decrypt( $key );
      return "key: $key";
    }
    return withings_AuthList($hash) if($cmd eq "showSubscriptions");

  } elsif( $hash->{SUBTYPE} eq "DEVICE" || $hash->{SUBTYPE} eq "DUMMY" ) {
    $list = "update:noArg updateAll:noArg";
    $list .= " videoLink:noArg" if(defined($hash->{modelID}) && $hash->{modelID} eq '21');
    $list .= " videoCredentials:noArg" if(defined($hash->{modelID}) && $hash->{modelID} eq '22');
    $list .= " settings:noArg" if(defined($hash->{modelID}) && $hash->{modelID} eq '60' && AttrVal($name,"IP",undef));


    if( $cmd eq "videoCredentials" ) {
      my $credentials = withings_getS3Credentials($hash);
      return undef;
    }
    elsif( $cmd eq "videoLink" ) {
      my $ret = "Flash Player Links:\n";
      my $videolinkdata = withings_getVideoLink($hash);
      if(defined($videolinkdata->{body}{device}))
      {
        #$hash->{videolink_ext} = "http://fpdownload.adobe.com/strobe/FlashMediaPlayback_101.swf?streamType=live&autoPlay=true&playButtonOverlay=false&src=rtmp://".$videolinkdata->{body}{device}{proxy_ip}.":".$videolinkdata->{body}{device}{proxy_port}."/".$videolinkdata->{body}{device}{kp_hash}."/";
        #$hash->{videolink_int} = "http://fpdownload.adobe.com/strobe/FlashMediaPlayback_101.swf?streamType=live&autoPlay=true&playButtonOverlay=false&src=rtmp://".$videolinkdata->{body}{device}{private_ip}.":".$videolinkdata->{body}{device}{proxy_port}."/".$videolinkdata->{body}{device}{kd_hash}."/";
        $ret .= " <a href='".$hash->{videolink_ext}."'>Play video from internet (Flash)</a>\n";
        $ret .= " <a href='".$hash->{videolink_int}."'>Play video from local network (Flash)</a>\n";
      }
      else
      {
        $ret .= " no links available";
      }
      return $ret;
    }
    elsif( $cmd eq "updateAll" ) {
      withings_poll($hash,2);
      return undef;
    }
    elsif( $cmd eq "update" ) {
      withings_poll($hash,1);
      return undef;
    }
    elsif( $cmd eq "settings" ) {
      withings_readAuraAlarm($hash);
      return undef;
    }
  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    $list = "users:noArg devices:noArg showAccount:noArg";

    if( $cmd eq "users" ) {
      my $users = withings_getUsers($hash);
      my $ret;
      foreach my $user (@{$users}) {
        $ret .= "$user->{id}\t\[$user->{shortname}\]\t$user->{publickey}   \t$user->{usertype}/$user->{status}\t$user->{firstname} $user->{lastname}\n";
      }

      $ret = "id\tshort\tpublickey\tusertype/status\tname\n" . $ret if( $ret );;
      $ret = "no users found" if( !$ret );
      return $ret;
    }
    if( $cmd eq "devices" ) {
      my $devices = withings_getDevices($hash);
      my $ret;
      foreach my $device (@{$devices}) {
       my $detail = $device->{deviceproperties};
        $ret .= "$detail->{id}\t$device_types{$detail->{type}}\t$detail->{batterylvl}\t$detail->{sn}\n";
      }

      $ret = "id\ttype\t\tbattery\tSN\n" . $ret if( $ret );;
      $ret = "no devices found" if( !$ret );
      return $ret;
    }
    if( $cmd eq 'showAccount' )
    {
      my $username = $hash->{helper}{username};
      my $password = $hash->{helper}{password};

      return 'no username set' if( !$username );
      return 'no password set' if( !$password );

      $username = withings_decrypt( $username );
      $password = withings_decrypt( $password );

      return "username: $username\npassword: $password";
    }

  }

  return "Unknown argument $cmd, choose one of $list";
}

sub withings_Set($$@) {
  my ( $hash, $name, $cmd, @arg ) = @_;

  my $list="";
  if( $hash->{SUBTYPE} eq "DEVICE" and defined($hash->{modelID}) && $hash->{modelID} eq "60" && AttrVal($name,"IP",undef))
  {
    $list = " on:noArg off:noArg reset:noArg rgb:colorpicker,RGB";
    $list .= " nap:noArg sleep:noArg alarm:noArg";
    $list .= " stop:noArg snooze:noArg";
    $list .= " nap_volume:slider,0,1,100 nap_brightness:slider,0,1,100";
    $list .= " sleep_volume:slider,0,1,100 sleep_brightness:slider,0,1,100";
    $list .= " clock_state:on,off clock_brightness:slider,0,1,100";
    $list .= " flashMat";
    $list .= " sensors:on,off";
    $list .= " rawCmd";
    $list .= " reconnect:noArg";
    if (defined($hash->{helper}{ALARMSCOUNT})&&($hash->{helper}{ALARMSCOUNT}>0))
    {
        for(my $i=1;$i<=$hash->{helper}{ALARMSCOUNT};$i++)
        {
          $list .= " alarm".$i."_time alarm".$i."_volume:slider,0,1,100 alarm".$i."_brightness:slider,0,1,100";
          $list .= " alarm".$i."_state:on,off alarm".$i."_wdays";
          $list .= " alarm".$i."_smartwake:slider,0,1,60";
        }
    }


    if ( $cmd eq 'reconnect' )
    {
      withings_Close($hash) if(DevIo_IsOpen($hash));
      withings_Open($hash);
      return undef;
    }
    elsif ( $cmd eq 'rgb' )
    {
      return withings_setAuraAlarm($hash,$cmd,join( "", @arg ));
    }
    if ( lc $cmd eq 'on' or lc $cmd eq 'off' or lc $cmd eq 'reset' )
    {
      return withings_setAuraAlarm($hash,$cmd);
    }
    elsif ( lc $cmd eq 'nap' or lc $cmd eq 'sleep' or lc $cmd eq 'alarm' or lc $cmd eq 'stop' or lc $cmd eq 'snooze' )
    {
      return withings_setAuraAlarm($hash,$cmd);
    }
    elsif ( lc $cmd eq 'rawcmd')
    {
      return withings_setAuraDebug($hash,join( "", @arg ));
    }
    #elsif( index( $cmd, "alarm" ) != -1 )
    #{
    #  my $alarmno = int( substr( $cmd, 5 ) ) + 0;
    #  return( withings_parseAlarm( $hash, $alarmno, @arg ) );
    #}
    elsif ( lc $cmd =~ /^alarm/ or lc $cmd =~ /^nap/ or lc $cmd =~ /^sleep/ or lc $cmd =~ /^clock/ or lc $cmd eq 'smartwake' )
    {
      readingsSingleUpdate( $hash, $cmd, join( ",", @arg ), 1 );
      return withings_setAuraAlarm($hash,$cmd,join( ":", @arg ));
    }
    elsif ( lc $cmd eq "flashmat" )
    {
      return withings_setAuraAlarm($hash,$cmd,join( ":", @arg ));
    }
    elsif ( lc $cmd eq "sensors" )
    {
      return withings_setAuraAlarm($hash,$cmd,join( ":", @arg ));
    }
    return "Unknown argument $cmd, choose one of $list";
  } elsif($hash->{SUBTYPE} eq "ACCOUNT") {
    $list = "autocreate:noArg";
    $list .= " authorize:noArg" if(AttrVal($name,"client_id",undef));
    return withings_AuthApp($hash,join( "", @arg )) if($cmd eq "authorize");
    return withings_autocreate($hash) if($cmd eq "autocreate");
    return "Unknown argument $cmd, choose one of $list";
  } elsif($hash->{SUBTYPE} eq "USER" && defined(ReadingsVal($name,".refresh_token",undef))) {
    $list = "login:noArg";
    $list .= " subscribe:noArg unsubscribe:noArg" if(defined($hash->{helper}{OAuthKey}));

    return withings_AuthRefresh($hash) if($cmd eq "login");
    return withings_AuthUnsubscribe($hash) if($cmd eq "unsubscribe");
    return withings_AuthSubscribe($hash) if($cmd eq "subscribe");
    return "Unknown argument $cmd, choose one of $list";
  } else {
    return "Unknown argument $cmd, choose one of $list";
  }
}


sub withings_readAuraAlarm($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: readAuraAlarm";

  withings_Open($hash) if(!DevIo_IsOpen($hash));


  my $data = "000100010100050101010000"; #hello
  withings_Write($hash, $data);

  $data="010100050101110000"; #hello2
  withings_Write($hash, $data);

  $data="0101000a01090a0005090a000100"; #ping
  withings_Write($hash, $data);


  $data="010100050109100000"; #sensordata clock
  withings_Write($hash, $data);
  $data="0101000b0109060006090800020300"; #sleepdata
  withings_Write($hash, $data);
  $data="0101000b0109060006090800020200"; #napdata
  withings_Write($hash, $data);

  $data="010100050109100000"; #sensordata clock
  withings_Write($hash, $data);



  #$data="0101000b0109090006090800020400"; #unknown4+?
  #withings_Write($hash, $data);
  #$data="0101000b0109090006090800020300"; #unknown3+?
  #withings_Write($hash, $data);
  # $data="0101000b0109090006090800020200"; #unknown2+?
  # withings_Write($hash, $data);
  #$data="0101000b0109090006090800020100"; #unknown1+?
  #withings_Write($hash, $data);
  #
  # $data="0101000e0109060009091700050400000000"; #unknown4?
  # withings_Write($hash, $data);
  # $data="0101000e0109060009091700050300000000"; #unknown3?
  # withings_Write($hash, $data);
  # $data="0101000e0109060009091700050200000000"; #unknown2?
  # withings_Write($hash, $data);
  #$data="0101000e0109060009091700050100000000"; #unknown1?
  #withings_Write($hash, $data);

  $data="010100050101250000"; #new alarmdata
  withings_Write($hash, $data);

  $data="0101000501012a0000"; #global alarm
  withings_Write($hash, $data);

  #$data="010100050109070000"; #getstate
  #withings_Write($hash, $data);


  #$data="0101000501091a0000"; #otherstate?
  #withings_Write($hash, $data);

  #$data="010100050101240000"; #unknown valid
  #withings_Write($hash, $data);

  #$data="0101000501090d0000"; #unknown experiment
  #withings_Write($hash, $data);
  #$data="0101000501010d0000"; #unknown experiment
  #withings_Write($hash, $data);


  $data = "000100010100050101010000"; #hello
  withings_Write($hash, $data);
  $data="010100050101110000"; #hello2
  withings_Write($hash, $data);
  $data="0101000a01090a0005090a000100"; #ping
  withings_Write($hash, $data);
  $data="010100050101250000"; #new alarmdata
  withings_Write($hash, $data);
  $data="0101000a01090a0005090a000100"; #ping
  withings_Write($hash, $data);
  $data="010100050101250000"; #new alarmdata
  withings_Write($hash, $data);
  $data="010100050101250000"; #new alarmdata
  withings_Write($hash, $data);

  #$data="0101000b0109060006090800020000"; #unknown
  #withings_Write($hash, $data);
  # #0101000f010100000a011000060906fffffffe
  #$data="0101000b0109060006090800020100"; #unknown
  #withings_Write($hash, $data);
  # #0101000d01090600080906000432320101
  #$data="0101000b0109060006090800020400"; #unknown
  #withings_Write($hash, $data);
  # #0101000f010100000a011000060906fffffffe

  #$data="010100050109010000"; #getstate
  #withings_Write($hash, $data);

  return undef;
}

sub withings_parseAuraData($$) {
  my ($hash,$data) = @_;
  my $name = $hash->{NAME};

  $data = unpack('H*', $data);

  Log3 $name, 5, "$name: parseAuraData $data";

  if(
     $data eq "010100050109030000" || #alarm/nap/sleep answer
     $data eq "010100050109040000" || #stop answer
     $data eq "010100050109050000" || #settings1 answer
     $data eq "0101000501090a0000" || #settings2/ping answer
     $data eq "0101000501090d0000" || #light answer
     $data eq "0101000501090f0000" || #clock/sensors answer
     $data eq "010100050109110000" || #snooze answer
     $data eq "0101000b0101110006011800020000" || #init
     $data eq "0101000f010100000a011000060125fffffffe" || #hello
     $data eq "0101000f010100000a01100006090afffffffe" || #hello
     $data eq "") {
    #set/ping/init return
    return undef;
  }
  elsif($data =~ /0101004a01010100450101/){
    #init info
    return undef;
  }
  elsif($data =~ /x0101000f010100000a01100006/){
    #unknown return
    return undef;
  }
  elsif($data =~ /01010010010910000b090d/) { #sensor & clock data
    Log3 $name, 4, "$name: sensor data ".$data;
    $data = pack('H*', $data);
    my $clockdisplay = ord(substr($data,13,1));
    my $clockbrightness = ord(substr($data,14,1));
    my $sensors = (ord(substr($data,19,1))==0)?"on":"off";
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "clock_state", ($clockdisplay ? "on":"off"), 1 );
    readingsBulkUpdate( $hash, "clock_brightness", $clockbrightness, 1 );
    readingsBulkUpdate( $hash, "sensors", $sensors, 1 );
    readingsBulkUpdate( $hash, "tests15", ord(substr($data,15,1)), 1 );
    readingsBulkUpdate( $hash, "tests16", ord(substr($data,16,1)), 1 );
    readingsBulkUpdate( $hash, "tests17", ord(substr($data,17,1)), 1 );
    readingsBulkUpdate( $hash, "tests18", ord(substr($data,18,1)), 1 );
    readingsEndUpdate($hash,1);
  }
  elsif($data =~ /0101000a01091a/) { #device alarm active 0101000a01091a000509190001>01<
    Log3 $name, 4, "$name: sensor data ".$data;
    $data = pack('H*', $data);
    my $globalalarm = ord(substr($data,13,1));
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "alarms", ($globalalarm ? "active":"deactivated"), 1 );
    readingsBulkUpdate( $hash, "testg12", ord(substr($data,12,1)), 1 );
    readingsBulkUpdate( $hash, "testg11", ord(substr($data,11,1)), 1 );
    readingsEndUpdate($hash,1);
  }
  elsif($data =~ /0101001701090700120907/) { #alarm state
    Log3 $name, 4, "$name: alarm state ".$data;
    $data = pack('H*', $data);
    my $devicestate = ord(substr($data,18,1));
    my $alarmtype = ord(substr($data,13,1));
    my $lightstate = ord(substr($data,26,1));

    readingsBulkUpdate( $hash, "testa14", ord(substr($data,14,1)), 1 );
    readingsBulkUpdate( $hash, "testa15", ord(substr($data,15,1)), 1 );
    readingsBulkUpdate( $hash, "testa16", ord(substr($data,16,1)), 1 );
    readingsBulkUpdate( $hash, "testa17", ord(substr($data,17,1)), 1 );
    readingsBulkUpdate( $hash, "testa19", ord(substr($data,19,1)), 1 );
    readingsBulkUpdate( $hash, "testa20", ord(substr($data,20,1)), 1 );
    readingsBulkUpdate( $hash, "testa21", ord(substr($data,21,1)), 1 );
    readingsBulkUpdate( $hash, "testa22", ord(substr($data,22,1)), 1 );
    readingsBulkUpdate( $hash, "testa23", ord(substr($data,23,1)), 1 );
    readingsBulkUpdate( $hash, "testa24", ord(substr($data,24,1)), 1 );
    readingsBulkUpdate( $hash, "testa25", ord(substr($data,25,1)), 1 );

    if($devicestate eq 0)
    {
      readingsSingleUpdate( $hash, "state", "off", 1 );
    }
    elsif($devicestate eq 2)
    {
      readingsSingleUpdate( $hash, "state", "snoozed", 1 );
    }
    elsif($devicestate eq 1)
    {
      readingsSingleUpdate( $hash, "state", "sleep", 1 ) if($alarmtype eq 1);
      readingsSingleUpdate( $hash, "state", "alarm", 1 ) if($alarmtype eq 2);
      readingsSingleUpdate( $hash, "state", "nap", 1 ) if($alarmtype eq 3);
    }

    #if($lightstate eq 1){
    #  readingsSingleUpdate( $hash, "power", "off", 1 );
    #} else {
    #  readingsSingleUpdate( $hash, "power", "on", 1 );
    #}
  }
  elsif($data =~ /0101000d01090600080906/) { #sleep/nap data
    $data = pack('H*', $data);
    if(ord(substr($data,15,1)) == 3){
      Log3 $name, 4, "$name: sleep data ".unpack('H*', $data);
      my $sleepvolume = ord(substr($data,13,1));
      my $sleepbrightness = ord(substr($data,14,1));
      my $sleepsong = ord(substr($data,16,1));
      readingsBeginUpdate($hash);
      readingsBulkUpdate( $hash, "sleep_volume", $sleepvolume, 1 );
      readingsBulkUpdate( $hash, "sleep_brightness", $sleepbrightness, 1 );
      readingsBulkUpdate( $hash, "sleep_sound", $sleep_sound{$sleepsong}, 1 );
      readingsEndUpdate($hash,1);
    }
    elsif(ord(substr($data,15,1)) == 2){
      Log3 $name, 4, "$name: nap data ".unpack('H*', $data);
      my $napvolume = ord(substr($data,13,1));
      my $napbrightness = ord(substr($data,14,1));
      my $napsong = ord(substr($data,16,1));
      readingsBeginUpdate($hash);
      readingsBulkUpdate( $hash, "nap_volume", $napvolume, 1 );
      readingsBulkUpdate( $hash, "nap_brightness", $napbrightness, 1 );
      readingsBulkUpdate( $hash, "nap_sound", $nap_sound{$napsong}, 1 );
      readingsEndUpdate($hash,1);
    }
    else {
      Log3 $name, 1, "$name: unknown sleep/nap data ".unpack('H*', $data);
    }
  }
  #01010056010125005105120007081e3e0000000509160004010232340916000402023337091600050303313239091600120410383738353039343838303
  #010100270101250022051200070800be000000140916000401023235091600040202333809160003030131
  elsif($data =~ /010100..01012500/) {
    Log3 $name, 4, "$name: alarm data ".$data;
    $data = pack('H*', $data);
  my $datalength = ord(substr($data,2,1))*256 + ord(substr($data,3,1));
  Log3 $name, 5, "$name: alarmdata ($datalength)".unpack('H*', $data);

  my $base = 9;
  readingsBeginUpdate($hash);
  my $alarmcounter = 1;

  my @dataarray = split("05120007",unpack('H*', $data));

  while(defined($dataarray[$alarmcounter]))
  {
    my @alarmparts = split("091600",$dataarray[$alarmcounter]);#seriously, withings?
    my $timedatehex = pack('H*', $alarmparts[0]);

    my $alarmhour = ord(substr($timedatehex,0,1));
    my $alarmminute = ord(substr($timedatehex,1,1));
    my $alarmdays = ord(substr($timedatehex,2,1));
    my $alarmstate = (ord(substr($timedatehex,2,1)) > 128) ? "on" : "off";
    my $alarmperiod = ord(substr($timedatehex,6,1));

    my $alarmvolume = 0;
    my $alarmbrightness = 0;
    my $alarmsong = 0;

    for(my $i=1;$i<=3;$i++) #whoever did this must have been high as fuck!
    {
      my $hexdata = pack('H*', $alarmparts[$i]);
      my $datatype = ord(substr($hexdata,1,1)); #order is not consistent
      my $datalength = ord(substr($hexdata,2,1));
      if($datatype == 1)
      {
        $alarmvolume = ord(substr($hexdata,3,1))-48; #value as ascii characters
        $alarmvolume = $alarmvolume*10 + ord(substr($hexdata,4,1))-48 if($datalength>1);
        $alarmvolume = $alarmvolume*10 + ord(substr($hexdata,5,1))-48 if($datalength>2);
      }
      elsif($datatype == 2)
      {
        $alarmbrightness = ord(substr($hexdata,3,1))-48; #same for other values - wtf?
        $alarmbrightness = $alarmbrightness*10 + ord(substr($hexdata,4,1))-48 if($datalength>1);
        $alarmbrightness = $alarmbrightness*10 + ord(substr($hexdata,5,1))-48 if($datalength>2);
      }
      elsif($datatype == 3)
      {
        $alarmsong = ord(substr($hexdata,3,1))-48;
      }
      else{
        Log3 $name, 2, "$name: unknown alarm data type: $datatype";
      }

    }

    readingsBulkUpdate( $hash, "alarm".$alarmcounter."_time", sprintf( "%02d:%02d:%02d",$alarmhour,$alarmminute,0), 1 );
    readingsBulkUpdate( $hash, "alarm".$alarmcounter."_wdays", withings_int2Weekdays($alarmdays), 1 );
    readingsBulkUpdate( $hash, "alarm".$alarmcounter."_volume", $alarmvolume, 1 );
    readingsBulkUpdate( $hash, "alarm".$alarmcounter."_brightness", $alarmbrightness, 1 );
    readingsBulkUpdate( $hash, "alarm".$alarmcounter."_smartwake", $alarmperiod, 1 );
    readingsBulkUpdate( $hash, "alarm".$alarmcounter."_state", $alarmstate, 1 );
    readingsBulkUpdate( $hash, "alarm".$alarmcounter."_sound", $alarm_sound{$alarmsong}, 1 );

    Log3 $name, 4, "$name: alarm $alarmstate $alarmhour:$alarmminute ($alarmperiod) on ".withings_int2Weekdays($alarmdays)." light:$alarmbrightness vol:$alarmvolume  [$base]";

    $hash->{helper}{ALARMSCOUNT} = $alarmcounter;
    $alarmcounter++;

  }
    readingsEndUpdate($hash,1);

  for(my $i=$alarmcounter;$i<10;$i++)
  {
    fhem( "deletereading $name alarm".$i."_.*" );
  }

  }
  else {
    Log3 $name, 2, "$name: unknown aura data $data";
  }



  return undef;

}

sub withings_setAuraAlarm($$;$) {
  my ($hash, $setting, $value) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: setAuraAlarm ".$setting;

  withings_Open($hash) if(!DevIo_IsOpen($hash));

  #my $data = "000100010100050101010000"; #hello
  #  withings_Write($hash, $data);
  #$data="010100050101110000"; #hello2
  #  withings_Write($hash, $data);
  #$data="0101000a01090a0005090a000100"; #ping
  #  withings_Write($hash, $data);

  my $data="010100050109070000"; #getstate

  if($setting eq "on")
  {
    $data="0101000a01090d0005090c000101"; #on
  }
  elsif($setting eq "off")
  {
    $data="0101000a01090d0005090c000100"; #off
  }
  elsif($setting eq "reset")
  {
    #$data="0101000f01090d000a09140006000000000000"; #reset
    $data="0101000f01090d000a09140006000000000000"; #reset
    readingsSingleUpdate( $hash, "rgb", "000000", 1 );
  }
  elsif($setting eq "rgb")
  {
    if(defined($value) && length($value) == 6 && $value =~ /^[0-9a-fA-F]+/) {
      my $r = lc(substr( $value,0,2 ));
      my $g = lc(substr( $value,2,2 ));
      my $b = lc(substr( $value,4,2 ));
      $data="0101001401090d000f09140006".$r."00".$g."00".$b;#."00090C000101";
      readingsSingleUpdate( $hash, "rgb", lc($value), 1 );
    } else {
      $data="0101000f01090d000a09140006000000000000";
      readingsSingleUpdate( $hash, "rgb", "000000", 1 );
    }
  }
  elsif($setting eq "nap")
  {
    $data="0101000b0109030006090800020200"; #nap
  }
  elsif($setting eq "sleep")
  {
    $data="0101000b0109030006090800020300"; #sleep
  }
  elsif($setting eq "alarm")
  {
    $data="0101000b0109030006090800020400"; #alarm
  }
  elsif($setting eq "stop")
  {
    $data="010100050109040000"; #stop
  }
  elsif($setting eq "snooze")
  {
    $data="010100050109110000"; #snooze
  }
  elsif($setting =~ /^alarm/)
  {
    my $alarmno = int( substr( $setting,5,1 ) ) + 0;

    my $volume = ReadingsVal( $name, "alarm".$alarmno."_volume", 60);
    my $volumestring = "";

    if($volume > 99)
    {
      $volumestring = "050103" . sprintf("%.2x",substr($volume,0,1)+48) . sprintf("%.2x",substr($volume,1,1)+48) . sprintf("%.2x",substr($volume,2,1)+48);
    }
    elsif($volume > 9)
    {
      $volumestring = "040102" . sprintf("%.2x",substr($volume,0,1)+48) . sprintf("%.2x",substr($volume,1,1)+48);
    }
    else
    {
      $volumestring = "030101" . sprintf("%.2x",$volume+48);
    }

    my $brightness = ReadingsVal( $name, "alarm".$alarmno."_brightness", 60);
    my $brightnessstring = "";

    if($brightness > 99)
    {
      $brightnessstring = "050203" . sprintf("%.2x",substr($brightness,0,1)+48) . sprintf("%.2x",substr($brightness,1,1)+48) . sprintf("%.2x",substr($brightness,2,1)+48);;
    }
    elsif($brightness > 9)
    {
      $brightnessstring = "040202" . sprintf("%.2x",substr($brightness,0,1)+48) . sprintf("%.2x",substr($brightness,1,1)+48);
    }
    else
    {
      $brightnessstring = "030201" . sprintf("%.2x",$brightness+48);
    }

    $data = "05120007";
    my @timestr = split(":",ReadingsVal( $name, "alarm".$alarmno."_time", "07:00" ));
    $data .= sprintf("%.2x%.2x",$timestr[0],$timestr[1]);
    my $alarmint = withings_weekdays2Int(ReadingsVal( $name, "alarm".$alarmno."_wdays", "all"));
    $alarmint += 128 if(ReadingsVal( $name, "alarm".$alarmno."_state", "on") eq "on");
    $data .= sprintf("%.2x",$alarmint);
    $data .= "000000";
    $data .= sprintf("%.2x",ReadingsVal( $name, "alarm".$alarmno."_smartwake", 10));
    $data .= "091600";
    $data .= $volumestring;
    $data .= "091600";
    $data .= $brightnessstring;
    $data .= "091600030301";
    my $alarmsong = $alarm_song{ReadingsVal( $name, "alarm".$alarmno."_sound", 1)};
    $alarmsong = 1 if(!defined($alarmsong) || $alarmsong==0);
    $data .= sprintf("%.2x",$alarmsong+48);

    my $datalen = length($data)/2;

    $data = "010100".sprintf("%.2x",$datalen+10)."01012900".sprintf("%.2x",$datalen+5)."01260001".sprintf("%.2x",$alarmno).$data;

    #if($setting =~ /volume/i or $setting =~ /brightness/i or $setting =~ /song/i )
    #{
    #  $data = "0101000d010905000809060004";
    #  $data .= sprintf("%.2x",ReadingsVal( $name, "alarm".$alarmno."_volume", 60));
    #  $data .= sprintf("%.2x",ReadingsVal( $name, "alarm".$alarmno."_brightness", 60));
    #  $data .= "04";
    #  $data .= sprintf("%.2x",$alarm_song{ReadingsVal( $name, "alarm".$alarmno."_sound", 1)});
    #}
    #else
    #{
    #  $data = "0101001101011b000c09040008";
    #  my @timestr = split(":",ReadingsVal( $name, "alarm".$alarmno."_time", "07:00" ));
    #  $data .= sprintf("%.2x%.2x",$timestr[0],$timestr[1]);
    #  my $alarmint = withings_weekdays2Int(ReadingsVal( $name, "alarm".$alarmno."_wdays", "all"));
    #  $alarmint += 128 if(ReadingsVal( $name, "alarm".$alarmno."_state", "on") eq "on");
    #  $data .= sprintf("%.2x",$alarmint);
    #  $data .= "6565d2";
    #  $data .= sprintf("%.2x",(ReadingsVal( $name, "alarm".$alarmno."_state", "on") eq "on" ? 1 : 0));
    #  $data .= sprintf("%.2x",ReadingsVal( $name, "alarm".$alarmno."_smartwake", 10));
    #}
    Log3 $name, 5, "$name: set alarm ".$data;

  }
  elsif($setting =~ /^nap/)
  {
    $data = "0101000d010905000809060004";
    $data .= sprintf("%.2x",ReadingsVal( $name, "nap_volume", 25));
    $data .= sprintf("%.2x",ReadingsVal( $name, "nap_brightness", 25));
    $data .= "02";
    $data .= sprintf("%.2x",$nap_song{ReadingsVal( $name, "nap_sound", "Unknown")eq"Unknown"?"Celestial Piano (20 min)":ReadingsVal( $name, "nap_sound", "Celestial Piano (20 min)")});
  }
  elsif($setting =~ /^sleep/)
  {
    $data = "0101000d010905000809060004";
    $data .= sprintf("%.2x",ReadingsVal( $name, "sleep_volume", 25));
    $data .= sprintf("%.2x",ReadingsVal( $name, "sleep_brightness", 10));
    $data .= "03";
    $data .= sprintf("%.2x",$sleep_song{ReadingsVal( $name, "sleep_sound", "Unknown")eq"Unknown"?"Moonlight Waves":ReadingsVal( $name, "sleep_sound", "Moonlight Waves")});
  }
  elsif($setting =~ /^clock/)
  {
    $data = "0101000b01090f0006090d0002";
    $data .= (ReadingsVal( $name, "clock_state", 1) ? "01":"00");
    $data .= sprintf("%.2x",ReadingsVal( $name, "clock_brightness", 40));
  }

  elsif($setting =~ /^flashMat/)
  {
    $data = "0101003201090c002d0413001211";
    $data .= unpack('H*', $value);
    $data .= "080a0013000000000000000000004e200000000000ffff";
  }

  elsif($setting =~ /^sensors/)
  {
    $data = "0101000a01090f0005080b000100";
    $data = "0101000a01090f0005080b000101" if($value eq "off");
  }

  Log3 $name, 5, "$name: Write Aura socket: ".$data;

  withings_Write($hash, $data);

  $data="0101000a01090a0005090a000100"; #ping
  withings_Write($hash, $data);

  #withings_Close($hash) if(DevIo_IsOpen($hash));

  return undef;

}

sub withings_setAuraDebug($$;$) {
  my ($hash, $value) = @_;
  my $name = $hash->{NAME};

  withings_Open($hash) if(!DevIo_IsOpen($hash));

  #my $data = "000100010100050101010000"; #hello
  #  withings_Write($hash, $data);
  #$data="010100050101110000"; #hello2
  #  withings_Write($hash, $data);
  #$data="0101000a01090a0005090a000100"; #ping
  #  withings_Write($hash, $data);

  my $data=$value; #debug
  Log3 $name, 2, "$name: Write Aura socket debug ".$data;
  Log3 $name, 5, "$name: Write Aura socket debug ".pack('H*', $data);

  withings_Write($hash, $data);

  #$data="0101000a01090a0005090a000100"; #ping
  #withings_Write($hash, $data);

  #withings_Close($hash) if(DevIo_IsOpen($hash));

  return undef;

}

sub withings_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef if(!defined($defs{$name}));

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "intervalData" or $attrName eq "intervalAlert" or $attrName eq "intervalProperties" or $attrName eq "intervalDebug");
  $attrVal = 300 if($attrName eq "intervalData" && $attrVal < 300 );
  $attrVal = 300 if($attrName eq "intervalDebug" && $attrVal < 300 );
  $attrVal = 120 if($attrName eq "intervalAlert" && $attrVal < 120 );
  $attrVal = 1800 if($attrName eq "intervalProperties" && $attrVal < 1800 );

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
      withings_poll($hash,0);
      withings_AuthRefresh($hash) if(defined(ReadingsVal($name,".refresh_token",undef)));
    }
  }
  elsif( $attrName eq "nossl" ) {
  my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      $hash->{'.https'} = "http";
    } else {
      $hash->{'.https'} = "https";
    }
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

##########################

sub withings_Dispatch($$$) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: dispatch ".$param->{type};

  my $urldata = Dumper($param->{data});
  $urldata =~ s/\$VAR1 = \{\n//g;
  $urldata =~ s/\};//g;
  $urldata =~ s/,\n/&/g;
  $urldata =~ s/ => /=/g;
  $urldata =~ s/'//g;
  $urldata =~ s/ //g;

  Log3 $name, 5, "$name: dispatch ".$param->{url}."?".$urldata;


  if( $err )
  {
    Log3 $name, 1, "$name: http request failed: type $param->{type} - $err";
  }
  elsif( $data )
  {

    $data =~ s/\n//g;
    if( $data !~ /{.*}/ or $data =~ /</)
    {
      Log3 $name, 1, "$name: invalid json detected: " . $param->{type} . " >>".substr( $data, 0, 64 )."<<" if($data ne "[]");
      return undef;
    }

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    if($@)
    {
      Log3 $name, 2, "$name: json evaluation error on dispatch type ".$param->{type}." ".$@;
      return undef;
    }
    Log3 $name, 1, "$name: Dispatch ".$param->{type}." json error ".$json->{error} if(defined($json->{error}));

    Log3 $name, 5, "$name: json returned: ".Dumper($json);

    if(defined($param->{enddate}))
    {
      $json->{requestedenddate} = $param->{enddate};
    }

    if( $param->{type} eq 'deviceReadingsGeneric' ) {
      withings_parseMeasurements($hash, $json);
    } elsif( $param->{type} eq 'userReadingsSleep' ||  $param->{type} eq 'userReadingsSleepDebug' ||  $param->{type} eq 'userReadingsActivity' ) {
      withings_parseVasistas($hash, $json, $param->{type});
    } elsif( $param->{type} eq 'deviceReadingsBaby' || $param->{type} eq 'deviceAlertsBaby' ) {
      withings_parseEvents($hash, $json);
    } elsif( $param->{type} eq 'deviceAlertsHome' ) {
      withings_parseTimeline($hash, $json);
    } elsif( $param->{type} eq 'userReadingsCommon' ) {
      withings_parseMeasureGroups($hash, $json);
    } elsif( $param->{type} eq 'userDailyAggregate' ) {
      withings_parseAggregate($hash, $json);
    } elsif( $param->{type} eq 'userDailyActivity' ) {
      withings_parseActivity($hash, $json);
    } elsif( $param->{type} eq 'userDailyWorkouts' ) {
      withings_parseWorkouts($hash, $json);
    } elsif( $param->{type} eq 'deviceProperties' ) {
      withings_parseProperties($hash, $json);
    }
  }
}



sub withings_encrypt($) {
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /crypt:/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }
  return "crypt:" if(!$encoded);
  return 'crypt:'.$encoded;
}

sub withings_decrypt($) {
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if( $encoded !~ /crypt:/ );
  return "" if($encoded eq "crypt:");
  
  $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}


#########################
sub withings_addExtension($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #withings_removeExtension() ;
  my $url = "/withings";
  delete $data{FWEXT}{$url} if($data{FWEXT}{$url});

  Log3 $name, 2, "Enabling Withings webcall for $name";
  $data{FWEXT}{$url}{deviceName} = $name;
  $data{FWEXT}{$url}{FUNC}       = "withings_Webcall";
  $data{FWEXT}{$url}{LINK}       = "withings";

  $modules{"withings"}{defptr}{"webcall"} = $hash;

}

#########################
sub withings_removeExtension($) {
  my ($hash) = @_;

  my $url  = "/withings";
  my $name = $data{FWEXT}{$url}{deviceName};
  $name = $hash->{NAME} if(!defined($name));
  Log3 $name, 2, "Disabling Withings webcall for $name ";
  delete $data{FWEXT}{$url};
  delete $modules{"livetracking"}{defptr}{"webcall"};
}

#########################
sub withings_Webcall() {
  my ($request) = @_;

  Log3 "withings", 4, "Withings webcall: ".$request;

  my $hash = $modules{"withings"}{defptr}{"webcall"};

  if(!defined($hash)){
    Log3 "withings", 1, "Withings webcall hash not defined!";
    return ( "text/plain; charset=utf-8",
        "undefined" );
  }
  my $name = $hash->{NAME};

  if($request =~ /state=connect/){
    $request =~ /code=(.*?)(&|$)/;
    my $code = $1 || undef;
    Log3 "withings", 2, "Withings webcall code ".$code;
    withings_AuthApp($hash,$code);
    return ( "text/plain; charset=utf-8",
        "You can close this window now." );
  }
  if($request =~ /userid=/){
    $request =~ /userid=(.*?)(&|$)/;
    my $userid = $1 || undef;
    if(!defined($userid)){
      Log3 "withings", 1, "Withings webcall userid missing ".$request;
      return ( "text/plain; charset=utf-8",
          "1" );
    }
    my $userhash = $modules{$hash->{TYPE}}{defptr}{"U$userid"};
    if(!defined($userhash)){
      Log3 "withings", 1, "Withings webcall user missing ".$request;
      return ( "text/plain; charset=utf-8",
          "1" );
    }
    InternalTimer(gettimeofday()+2, "withings_poll", $userhash, 0);

    return ( "text/plain; charset=utf-8",
        "0" );
  } else {
    Log3 "withings", 1, "Withings webcall w/o user: ".$request;
  }
  return ( "text/plain; charset=utf-8",
      "1" );

  return undef;
}

sub withings_AuthApp($;$) {
  my ($hash,$code) = @_;
  my $name = $hash->{NAME};


  # https://account.withings.com/oauth2/token [grant_type=authorization_code...]
  # grant_type=authorization_code&client_id=[STRING]&client_secret=[STRING]&code=[STRING]&redirect_uri=[STRING]

  my $cid = AttrVal($name,'client_id','');
  my $cb = AttrVal($name,'callback_url','');

  my $url = "https://account.withings.com/oauth2_user/authorize2?response_type=code&client_id=".$cid."&scope=user.info,user.metrics,user.activity&state=connect&redirect_uri=".$cb;
  return $url if(!defined($code) || $code eq "");

  my $cs = AttrVal($name,'client_secret','');

  Log3 "withings", 2, "Withings auth call ".$code;

  my $datahash = {
    url => "https://account.withings.com/oauth2/token",
    method => "POST",
    timeout => 10,
    noshutdown => 1,
    data => { grant_type => 'authorization_code', client_id => $cid, client_secret => $cs, code => $code, redirect_uri => $cb },
  };

  my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err || !defined($data) || $data =~ /Authentification failed/ || $data =~ /not a valid/ || $data =~ /credentials do not match/)
  {
    Log3 $name, 1, "$name: LOGIN ERROR: ".Dumper($err);
    return undef;
  }
  #Log3 $name, 1, "$name: LOGIN SUCCESS ".Dumper($data);

  my $json = eval { JSON::decode_json($data) };
  if($@)
  {
    Log3 $name, 1, "$name: LOGIN JSON ERROR: $data";
    return undef;
  }
  if(defined($json->{errors})){
    Log3 $name, 2, "$name: LOGIN RETURN ERROR: $data";
    return undef;
  }

  Log3 $name, 4, "$name: LOGIN SUCCESS: $data";

  my $user = $json->{userid} || "NOUSER";
  my $userhash = $modules{$hash->{TYPE}}{defptr}{"U$user"};
  if(!defined($userhash)){
    Log3 $name, 2, "$name: LOGIN USER ERROR: $data";
    return undef;
  }
  #readingsSingleUpdate( $hash, "access_token", $json->{access_token}, 1 ) if(defined($json->{access_token}));
  $userhash->{helper}{OAuthKey} = $json->{access_token} if(defined($json->{access_token}));
  #readingsSingleUpdate( $hash, "expires_in", $json->{expires_in}, 1 ) if(defined($json->{expires_in}));
  $userhash->{helper}{OAuthValid} = (int(time)+$json->{expires_in}) if(defined($json->{expires_in}));
  readingsSingleUpdate( $userhash, ".refresh_token", $json->{refresh_token}, 1 ) if(defined($json->{refresh_token}));

  InternalTimer(gettimeofday()+$json->{expires_in}-60, "withings_AuthRefresh", $userhash, 0);


  #https://wbsapi.withings.net/notify?action=subscribe&access_token=a639e912dfc31a02cc01ea4f38de7fa4a1464c2e&callbackurl=http://fhem:remote@gu9mohkaxqdgpix5.myfritz.net/fhem/withings&appli=1&comment=fhem

  return undef;
}


sub withings_AuthRefresh($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $cid = AttrVal($hash->{IODev}->{NAME},'client_id','');
  my $cs = AttrVal($hash->{IODev}->{NAME},'client_secret','');
  my $ref = ReadingsVal($name,'.refresh_token','');

  my $datahash = {
    url => "https://account.withings.com/oauth2/token",
    method => "POST",
    timeout => 10,
    noshutdown => 1,
    data => { grant_type => 'refresh_token', client_id => $cid, client_secret => $cs, refresh_token => $ref },
  };


  my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err || !defined($data) || $data =~ /Authentification failed/ || $data =~ /not a valid/)
  {
    Log3 $name, 1, "$name: REFRESH ERROR $err";
    return undef;
  }

  my $json = eval { JSON::decode_json($data) };
  if($@)
  {
    Log3 $name, 1, "$name: REFRESH JSON ERROR: $data";
    return undef;
  }
  if(defined($json->{errors})){
    Log3 $name, 2, "$name: REFRESH RETURN ERROR: $data";
    return undef;
  }

  Log3 $name, 4, "$name: REFRESH SUCCESS: $data";

  #readingsSingleUpdate( $hash, "access_token", $json->{access_token}, 1 ) if(defined($json->{access_token}));
  $hash->{helper}{OAuthKey} = $json->{access_token} if(defined($json->{access_token}));
  #readingsSingleUpdate( $hash, "expires_in", $json->{expires_in}, 1 ) if(defined($json->{expires_in}));
  $hash->{helper}{OAuthValid} = (int(time)+$json->{expires_in}) if(defined($json->{expires_in}));
  readingsSingleUpdate( $hash, ".refresh_token", $json->{refresh_token}, 1 ) if(defined($json->{refresh_token}));

  InternalTimer(gettimeofday()+$json->{expires_in}-60, "withings_AuthRefresh", $hash, 0);

  #https://wbsapi.withings.net/notify?action=subscribe&access_token=a639e912dfc31a02cc01ea4f38de7fa4a1464c2e&callbackurl=http://fhem:remote@gu9mohkaxqdgpix5.myfritz.net/fhem/withings&appli=1&comment=fhem

  return undef;
}

sub withings_AuthList($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $acc = $hash->{helper}{OAuthKey};

  my $datahash = {
    url => "https://wbsapi.withings.net/notify",
    method => "GET",
    timeout => 10,
    noshutdown => 1,
    data => { action => 'list', access_token => $acc },
  };


  my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err || !defined($data) || $data =~ /Authentification failed/ || $data =~ /not a valid/)
  {
    Log3 $name, 1, "$name: LIST ERROR $err";
    return undef;
  }

  my $json = eval { JSON::decode_json($data) };
  if($@)
  {
    Log3 $name, 1, "$name: LIST JSON ERROR: $data";
    return undef;
  }
  if(defined($json->{errors})){
    Log3 $name, 2, "$name: LIST RETURN ERROR: $data";
    return undef;
  }

  my $ret = "";
  foreach my $profile (@{$json->{body}{profiles}}) {
    next if( !defined($profile->{appli}) );
    $ret .= $profile->{appli};
    $ret .= "\t";
    $ret .= $profile->{comment};
    $ret .= "\t";
    $ret .= $profile->{callbackurl};
    $ret .= "\n";
  }
  return "No subscriptions found!" if($ret eq "");
  return $ret;

}

sub withings_AuthUnsubscribe($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $acc = $hash->{helper}{OAuthKey};
  my $cb = AttrVal($hash->{IODev}->{NAME},'callback_url','');

  my @applis = ("1", "4", "16", "44", "46");
  foreach my $appli (@applis) {

    my $datahash = {
      url => "https://wbsapi.withings.net/notify",
      method => "GET",
      timeout => 10,
      noshutdown => 1,
      data => { action => 'revoke', access_token => $acc, callbackurl => $cb, appli => $appli },
    };


    my($err,$data) = HttpUtils_BlockingGet($datahash);

    if ($err || !defined($data) || $data =~ /Authentification failed/ || $data =~ /not a valid/)
    {
      Log3 $name, 1, "$name: REVOKE ERROR $err";
      #return undef;
    }

    my $json = eval { JSON::decode_json($data) };
    if($@)
    {
      Log3 $name, 1, "$name: REVOKE JSON ERROR: $data";
      #return undef;
    }
    if(defined($json->{error})){
      Log3 $name, 2, "$name: REVOKE RETURN ERROR: $data";
      #return undef;
    }

    next if($json->{status} == 0);
    Log3 $name, 1, "$name: REVOKE PROBLEM: $data";

  }


  return undef;
}

sub withings_AuthSubscribe($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $acc = $hash->{helper}{OAuthKey};
  my $cb = AttrVal($hash->{IODev}->{NAME},'callback_url','');
  my @applis = ("1", "4", "16", "44", "46");

  my $ret = "Please open the following URLs in your browser to subscribe:\n\n";
  foreach my $appli (@applis) {

    $ret.='https://wbsapi.withings.net/notify?action=subscribe&access_token='.$acc.'&appli='.$appli.'&comment=FHEM&callbackurl='.$cb;
    $ret .= "\n";
    next;

    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(GET => 'https://wbsapi.withings.net/notify?action=subscribe&access_token='.$acc.'&appli='.$appli.'&comment=FHEM&callbackurl='.$cb);
    my $response = $ua->request($request);
    Log3 $name, 2, "$name: SUBSCRIBE ".Dumper($response->content);

    next;

    my $datahash = {
      url => "https://wbsapi.withings.net/notify",
      method => "GET",
      timeout => 10,
      data => { action => 'subscribe', access_token => $acc, appli => $appli, comment => 'FHEM', callbackurl => $cb },
    };

    my($err,$data) = HttpUtils_BlockingGet($datahash);

    #Log3 $name, 1, "$name: SUBSCRIBE ".Dumper($datahash);

    if ($err || !defined($data) || $data =~ /Authentification failed/ || $data =~ /not a valid/)
    {
      Log3 $name, 1, "$name: SUBSCRIBE ERROR $err";
      return undef;
    }

    my $json = eval { JSON::decode_json($data) };
    if($@)
    {
      Log3 $name, 1, "$name: SUBSCRIBE JSON ERROR: $data";
      return undef;
    }
    if(defined($json->{error})){
      Log3 $name, 2, "$name: SUBSCRIBE RETURN ERROR: $data";
      return undef;
    }

    #next if($json->{status} == 0);
    Log3 $name, 2, "$name: SUBSCRIBE SUCCESS: $data";

  }
  return $ret;

  return undef;
}


##########################
sub withings_DbLog_splitFn($) {
  my ($event) = @_;
  my ($reading, $value, $unit) = "";

  Log3 ("dbsplit", 5, "withings dbsplit event ".$event);

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value = $parts[1];


  if($event =~ m/heartPulse/)
  {
    $reading = 'heartPulse';
    $unit = 'bpm';
  }
  elsif($event =~ m/pulseWaveRaw/)
  {
    $reading = 'pulseWaveRaw';
    $unit = 'm/s';
  }
  elsif($event =~ m/pulseWave/)
  {
    $reading = 'pulseWave';
    $unit = 'm/s';
  }
  elsif($event =~ m/dailyDescent/)
  {
    $reading = 'dailyDescent';
    $unit = 'm';
  }
  elsif($event =~ m/dailyDistance/)
  {
    $reading = 'dailyDistance';
    $unit = 'm';
  }
  elsif($event =~ m/dailyElevation/)
  {
    $reading = 'dailyElevation';
    $unit = 'm';
  }
  elsif($event =~ m/dailySteps/)
  {
    $reading = 'dailySteps';
    $unit = 'steps';
  }
  elsif($event =~ m/steps/)
  {
    $reading = 'steps';
    $unit = 'steps';
  }
  elsif($event =~ m/temperature/)
  {
    $reading = 'temperature';
    $unit = '°C';
  }
  elsif($event =~ m/bodyTemperature/)
  {
    $reading = 'bodyTemperature';
    $unit = '°C';
  }
  elsif($event =~ m/skinTemperature/)
  {
    $reading = 'skinTemperature';
    $unit = '°C';
  }
  elsif($event =~ m/humidity/)
  {
    $reading = 'humidity';
    $unit = '%';
  }
  elsif($event =~ m/systolicBloodPressure/)
  {
    $reading = 'systolicBloodPressure';
    $unit = 'mmHg';
  }
  elsif($event =~ m/diastolicBloodPressure/)
  {
    $reading = 'diastolicBloodPressure';
    $unit = 'mmHg';
  }
  elsif($event =~ m/spo2/)
  {
    $reading = 'spo2';
    $unit = '%';
  }
  elsif($event =~ m/breathingEventProbability/)
  {
    $reading = 'breathingEventProbability';
    $unit = '%';
  }
  elsif($event =~ m/boneMassWeight/)
  {
    $reading = 'boneMassWeight';
    $unit = 'kg';
  }
  elsif($event =~ m/fatFreeMass/)
  {
    $reading = 'fatFreeMass';
    $unit = 'kg';
  }
  elsif($event =~ m/fatMassWeight/)
  {
    $reading = 'fatMassWeight';
    $unit = 'kg';
  }
  elsif($event =~ m/weight/)
  {
    $reading = 'weight';
    $unit = 'kg';
  }
  elsif($event =~ m/muscleRatio/)
  {
    $reading = 'muscleRatio';
    $unit = '%';
  }
  elsif($event =~ m/boneRatio/)
  {
    $reading = 'boneRatio';
    $unit = '%';
  }
  elsif($event =~ m/fatRatio/)
  {
    $reading = 'fatRatio';
    $unit = '%';
  }
  elsif($event =~ m/hydration/)
  {
    $reading = 'hydration';
    $unit = '%';
  }
  elsif($event =~ m/waterMass/)
  {
    $reading = 'waterMass';
    $unit = 'kg';
  }
  elsif($event =~ m/dailyCaloriesPassive/)
  {
    $reading = 'dailyCaloriesPassive';
    $unit = 'kcal';
  }
  elsif($event =~ m/dailyCaloriesActive/)
  {
    $reading = 'dailyCaloriesActive';
    $unit = 'kcal';
  }
  elsif($event =~ m/calories/)
  {
    $reading = 'calories';
    $unit = 'kcal';
  }
  elsif($event =~ m/co2/)
  {
    $reading = 'co2';
    $unit = 'ppm';
  }
  elsif($event =~ m/voc/)
  {
    $reading = 'voc';
    $unit = 'ppm';
  }
  elsif($event =~ m/light/)
  {
    $reading = 'light';
    $unit = 'lux';
  }
  elsif($event =~ m/batteryPercent/)
  {
    $reading = 'batteryPercent';
    $unit = '%';
  }
  elsif($event =~ m/durationTo/)
  {
    $value = $parts[1];
    $unit = 's';
  }
  elsif($event =~ m/Duration/)
  {
    $value = $parts[1];
    $unit = 's';
  }
  elsif($event =~ m/heartrate/)
  {
    $value = $parts[1];
    $unit = 'bpm';
  }
  elsif($event =~ m/pressure/)
  {
    $value = $parts[1];
    $unit = 'mmHg';
  }
  else
  {
    $value = $parts[1];
    $value = $value." ".$parts[2] if(defined($parts[2]));
  }
  #Log3 ("dbsplit", 5, "withings dbsplit output ".$reading." / ".$value." / ".$unit);

  return ($reading, $value, $unit);
}

sub withings_int2Weekdays( $ ) {
    my ($wdayint) = @_;
    my $wdayargs = '';
    my $weekdays = '';

    $wdayint -= 128 if($wdayint >= 128);

    if($wdayint >= 64)
    {
      $wdayargs.="Sa";
      $wdayint-=64;
    }
    if($wdayint >= 32)
    {
      $wdayargs.="Fr";
      $wdayint-=32;
    }
    if($wdayint >= 16)
    {
      $wdayargs.="Th";
      $wdayint-=16;
    }
    if($wdayint >= 8)
    {
      $wdayargs.="We";
      $wdayint-=8;
    }
    if($wdayint >= 4)
    {
      $wdayargs.="Tu";
      $wdayint-=4;
    }
    if($wdayint >= 2)
    {
      $wdayargs.="Mo";
      $wdayint-=2;
    }
    if($wdayint >= 1)
    {
      $wdayargs.="Su";
      $wdayint-=1;
    }

    if(index($wdayargs,"Mo") != -1)
    {
      $weekdays.='Mo,';
    }
    if(index($wdayargs,"Tu") != -1)
    {
      $weekdays.='Tu,';
    }
    if(index($wdayargs,"We") != -1)
    {
      $weekdays.='We,';
    }
    if(index($wdayargs,"Th") != -1)
    {
      $weekdays.='Th,';
    }
    if(index($wdayargs,"Fr") != -1)
    {
      $weekdays.='Fr,';
    }
    if(index($wdayargs,"Sa") != -1)
    {
      $weekdays.='Sa,';
    }
    if(index($wdayargs,"Su") != -1)
    {
      $weekdays.='Su,';
    }
    if($weekdays eq "Mo,Tu,We,Th,Fr,Sa,Su,")
    {
        $weekdays="all";
    }
    if($weekdays eq "")
    {
        $weekdays="none";
    }
    $weekdays=~ s/,$//;
    return $weekdays;
}

sub withings_weekdays2Int( $ ) {
    my ($wdayargs) = @_;
    my $weekdays = 0;
    if(index($wdayargs,"Mo") != -1 || index($wdayargs,"1") != -1)
    {
        $weekdays+=2;
    }
    if(index($wdayargs,"Tu") != -1 || index($wdayargs,"Di") != -1 || index($wdayargs,"2") != -1)
    {
      $weekdays+=4;
    }
    if(index($wdayargs,"We") != -1 || index($wdayargs,"Mi") != -1 || index($wdayargs,"3") != -1)
    {
      $weekdays+=8;
    }
    if(index($wdayargs,"Th") != -1 || index($wdayargs,"Do") != -1 || index($wdayargs,"4") != -1)
    {
      $weekdays+=16;
    }
    if(index($wdayargs,"Fr") != -1 || index($wdayargs,"5") != -1)
    {
      $weekdays+=32;
    }
    if(index($wdayargs,"Sa") != -1 || index($wdayargs,"6") != -1)
    {
      $weekdays+=64;
    }
    if(index($wdayargs,"Su") != -1 || index($wdayargs,"So") != -1 || index($wdayargs,"0") != -1)
    {
      $weekdays+=1;
    }
    if(index($wdayargs,"all") != -1 || index($wdayargs,"daily") != -1 || index($wdayargs,"7") != -1)
    {
        $weekdays=127;
    }
    if(index($wdayargs,"none") != -1 || index($wdayargs,"once") != -1)
    {
        $weekdays=0;
    }
    return $weekdays;
}

1;

=pod
=item device
=item summary Withings health data for users and devices
=begin html

<a name="withings"></a>
<h3>withings</h3>
<ul>
  FHEM module for Withings devices.<br><br>

  Notes:
  <ul>
    <li>JSON and Digest::SHA have to be installed on the FHEM host.</li>
  </ul><br>

  <a name="withings_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; withings ACCOUNT &lt;login@email&gt; &lt;password&gt;</code><br>
    <code>define &lt;name&gt; withings &lt;device&gt;</code><br>
    <br>

    Defines a withings device.<br><br>
    If a withings device of the account type is created all fhem devices for users and devices are automaticaly created.
    <br>

    Examples:
    <ul>
      <code>define withings withings ACCOUNT abc@test.com myPassword</code><br>
    </ul>
  </ul><br>

  <a name="withings_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>height</li>
    <li>weight</li>
    <li>fatFreeMass</li>
    <li>muscleRatio</li>
    <li>fatMassWeight</li>
    <li>fatRatio</li>
    <li>boneMassWeight</li>
    <li>boneRatio</li>
    <li>hydration</li>

    <li>diastolicBloodPressure</li>
    <li>systolicBloodPressure</li>
    <li>heartPulse</li>
    <li>heartECG</li>
    <li>heartSounds</li>
    <li>pulseWave</li>
    <li>spo2</li>

    <li>bodyTemperature</li>
    <li>skinTemperature</li>
    <li>temperature</li>

    <li>dailySteps</li>
    <li>dailyDistance</li>
    <li>dailyElevation</li>
    <li>dailyDescent</li>
    <li>dailyDurationLight</li>
    <li>dailyDurationModerate</li>
    <li>dailyDurationIntense</li>
    <li>dailyCaloriesActive</li>
    <li>dailyCaloriesPassive</li>

    <li>sleepDurationAwake</li>
    <li>sleepDurationLight</li>
    <li>sleepDurationDeep</li>
    <li>sleepDurationREM</li>
    <li>sleepDurationTotal</li>
    <li>wakeupCount</li>
    <li>snoringDuration</li>
    <li>snoringEpisodeCount</li>
    <li>sleepScore</li>

    <li>co2</li>
    <li>temperature</li>
    <li>light</li>
    <li>noise</li>
    <li>voc</li>
    <li>batteryState</li>
    <li>batteryPercent</li>
  </ul><br>

  <a name="withings_Get"></a>
  <b>Get</b>
  <ul>
    <li>update<br>
      trigger an update</li>
  </ul><br>

  <a name="withings_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval*<br>
      the interval in seconds used to check for new values.<br>
       - intervalData: main user/device readings<br>
       - intervalDebug: debugging/inofficial readings<br>
       - intervalDaily: daily summarized activity data<br>
       - intervalProperties: device properties<br>
       - intervalAlert: camera alerts<br>
    </li>
    <li>disable<br>
      1 -> stop polling</li>
  </ul>
</ul>

=end html
=cut

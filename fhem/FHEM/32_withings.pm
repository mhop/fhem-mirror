##############################################################################
# $Id$
#
#  32_withings.pm
#
#  2018 Markus M.
#  Based on original code by justme1968
#
#  https://forum.fhem.de/index.php/topic,64944.0.html
#
#
##############################################################################
# Release 08 / 2018-09-28

package main;

use strict;
use warnings;

use HttpUtils;

use JSON;

use POSIX qw( strftime );
use Time::Local qw(timelocal);
use Digest::SHA qw(hmac_sha1_base64);

#use Encode qw(encode);
#use LWP::Simple;
#use HTTP::Request;
#use HTTP::Cookies;
#use URI::Escape qw(uri_escape);

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
                       2 => { 21 => "Smart Baby Monitor", 22 => "Home", 22 => "Home v2", },
                       4 => { 41 => "iOS Blood Pressure Monitor", 42 => "Wireless Blood Pressure Monitor", 43 => "BPM", 44 => "BPM+", },
                      16 => { 51 => "Pulse Ox", 52 => "Activite", 53 => "Activite v2", 54 => "Go", 55 => "Steel HR", },
                      32 => { 60 => "Aura", 61 => "Sleep Sensor", 62 => "Sleep Mat", 63 => "Sleep", },
                      64 => { 70 => "Thermo", }, );

                      #Firmware files: cdnfw_withings_net
                      #Smart Body Analyzer: /wbs02/wbs02_1521.bin
                      #Blood Pressure Monitor: /wpm02/wpm02_251.bin
                      #Pulse: /wam01/wam01_1761.bin
                      #Aura: /wsd01/wsd01_607.bin
                      #Aura Mat: /wsm01/wsm01_711.bin
                      #Home: /wbp02/wbp02_168.bin
                      #Activite: /hwa01/hwa01_1070.bin

my %measure_types = (  1 => { name => "Weight (kg)", reading => "weight", },
                       4 => { name => "Height (meter)", reading => "height", },
                       5 => { name => "Lean Mass (kg)", reading => "fatFreeMass", },
                       6 => { name => "Fat Mass (%)", reading => "fatRatio", },
                       7 => { name => "Lean Mass (%)", reading => "fatFreeRatio", },
                       8 => { name => "Fat Mass (kg)", reading => "fatMassWeight", },
                       9 => { name => "Diastolic Blood Pressure (mmHg)", reading => "diastolicBloodPressure", },
                      10 => { name => "Systolic Blood Pressure (mmHg)", reading => "systolicBloodPressure", },
                      11 => { name => "Heart Rate (bpm)", reading => "heartPulse", },
                      12 => { name => "Temperature (&deg;C)", reading => "temperature", },
                      13 => { name => "Humidity (%)", reading => "humidity", },
                      14 => { name => "unknown 14", reading => "unknown14", }, #device? event home - peak sound level?
                      15 => { name => "Noise (dB)", reading => "noise", },
                      18 => { name => "Weight Objective Speed", reading => "weightObjectiveSpeed", },
                      19 => { name => "Breastfeeding (s)", reading => "breastfeeding", }, #baby
                      20 => { name => "Bottle (ml)", reading => "bottle", }, #baby
                      22 => { name => "BMI", reading => "bmi", }, #user? goals
                      35 => { name => "CO2 (ppm)", reading => "co2", },
                      36 => { name => "Steps", reading => "steps", dailyreading => "dailySteps", },  #aggregate
                      37 => { name => "Elevation (m)", reading => "elevation", dailyreading => "dailyElevation", }, #aggregate
                      38 => { name => "Active Calories (kcal)", reading => "calories", dailyreading => "dailyCalories", }, #aggregate
                      39 => { name => "Intensity", reading => "intensity", }, #intraday only
                      40 => { name => "Distance (m)", reading => "distance", dailyreading => "dailyDistance", },  #aggregate #measure
                      41 => { name => "Descent (m)", reading => "descent", dailyreading => "dailyDescent", }, #descent #aggregate #measure ??sleepreading!
                      42 => { name => "Activity Type", reading => "activityType", }, #intraday only 1:walk 2:run
                      43 => { name => "Duration (s)", reading => "duration", }, #intraday only
                      44 => { name => "Sleep State", reading => "sleepstate", }, #intraday #aura mat
                      47 => { name => "MyFitnessPal Calories (kcal)", reading => "caloriesMFP", },
                      48 => { name => "Active Calories (kcal)", reading => "caloriesActive", dailyreading => "dailyCaloriesActive", }, #day summary
                      49 => { name => "Idle Calories (kcal)", reading => "caloriesPassive", dailyreading => "dailyCaloriesPassive", }, #aggregate
                      50 => { name => "unknown 50", reading => "unknown50", dailyreading => "dailyUnknown50", }, #day summary pulse 60k-80k #aggregate
                      51 => { name => "Light Activity (s)", reading => "durationLight", dailyreading => "dailyDurationLight", }, #aggregate
                      52 => { name => "Moderate Activity (s)", reading => "durationModerate", dailyreading => "dailyDurationModerate", }, #aggregate
                      53 => { name => "Intense Activity (s)", reading => "durationIntense", dailyreading => "dailyDurationIntense", }, #aggregate
                      54 => { name => "SpO2 (%)", reading => "spo2", },
                      56 => { name => "Ambient light (lux)", reading => "light", },  # aura device
                      57 => { name => "Respiratory rate", reading => "breathing", }, # aura mat #measure vasistas
                      58 => { name => "Air Quality (ppm)", reading => "voc", }, # Home Air Quality
                      59 => { name => "unknown 59", reading => "unknown59", }, #
                      60 => { name => "unknown 60", reading => "unknown60", }, # aura mat #measure vasistas 20-200 peak 800
                      61 => { name => "unknown 61", reading => "unknown61", }, # aura mat #measure vasistas 10-60 peak 600
                      62 => { name => "unknown 62", reading => "unknown62", }, # aura mat #measure vasistas 20-100
                      63 => { name => "unknown 63", reading => "unknown63", }, # aura mat #measure vasistas 0-100
                      64 => { name => "unknown 64", reading => "unknown64", }, # aura mat #measure vasistas 800-1300
                      65 => { name => "unknown 65", reading => "unknown65", }, # aura mat #measure vasistas 3000-4500 peak 5000
                      66 => { name => "unknown 66", reading => "unknown66", }, # aura mat #measure vasistas 4000-7000
                      67 => { name => "unknown 67", reading => "unknown67", }, # aura mat #measure vasistas 0-500 peak 1500
                      68 => { name => "unknown 68", reading => "unknown68", }, # aura mat #measure vasistas 0-1500
                      69 => { name => "unknown 69", reading => "unknown69", }, # aura mat #measure vasistas 0-6000 peak 10000
                      70 => { name => "unknown 70", reading => "unknown70", }, #?
                      71 => { name => "Body Temperature (&deg;C)", reading => "bodyTemperature", }, #thermo
                      73 => { name => "Skin Temperature (&deg;C)", reading => "skinTemperature", }, #thermo
                      76 => { name => "Muscle Mass (kg)", reading => "muscleMass", }, # cardio scale
                      77 => { name => "Water Mass (kg)", reading => "waterMass", }, # cardio scale
                      78 => { name => "unknown 78", reading => "unknown78", }, # cardio scale
                      79 => { name => "unknown 79", reading => "unknown79", }, # body scale
                      80 => { name => "unknown 80", reading => "unknown80", }, # body scale
                      86 => { name => "unknown 86", reading => "unknown86", }, # body scale
                      87 => { name => "Active Calories (kcal)", reading => "caloriesActive", dailyreading => "dailyCaloriesActive", }, # measures list sleepreading!
                      88 => { name => "Bone Mass (kg)", reading => "boneMassWeight", },
                      89 => { name => "unknown 89", reading => "unknown89", },
                      90 => { name => "unknown 90", reading => "unknown90", }, #pulse
                      91 => { name => "Pulse Wave Velocity (m/s)", reading => "pulseWave", }, # new weight
                      93 => { name => "Muscle Mass (%)", reading => "muscleRatio", }, # cardio scale
                      94 => { name => "Bone Mass (%)", reading => "boneRatio", }, # cardio scale
                      95 => { name => "Hydration (%)", reading => "hydration", }, # body water
                     122 => { name => "Pulse Transit Time (ms)", reading => "pulseTransitTime", },
                      #-10 => { name => "Speed", reading => "speed", },
                      #-11 => { name => "Pace", reading => "pace", },
                      #-12 => { name => "Altitude", reading => "altitude", },
                      );

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
                         24 => "Vollyball",
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

my %sleep_state = (  0 => "awake",
                     1 => "light sleep",
                     2 => "deep sleep",
                     3 => "REM sleep", );

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
                        'sleepscore' => { name => "Sleep Score", reading => "sleepScore", unit => 0, },
                        'wsdid' => { name => "wsdid", reading => "wsdid", unit => 0, },
                        'hr_resting' => { name => "Resting HR", reading => "heartrateResting", unit => "bpm", },
                        'hr_min' => { name => "Minimum HR", reading => "heartrateMinimum", unit => "bpm", },
                        'hr_average' => { name => "Average HR", reading => "heartrateAverage", unit => "bpm", },
                        'hr_max' => { name => "Maximum HR", reading => "heartrateMaximum", unit => "bpm", },
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
                      4 => "Sacred Forest (20 min)", );


my %sleep_sound = (  0 => "Unknown",
                      1 => "Moonlight Waves",
                      2 => "Siren's Whisper",
                      3 => "Celestial Piano",
                      4 => "Cloud Flakes",
                      5 => "Spotify",
                      6 => "Internet radio", );


sub withings_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "withings_Define";
  $hash->{SetFn}    = "withings_Set";
  $hash->{GetFn}    = "withings_Get";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "withings_Notify";
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
                      "nossl:1 ".
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
    #$hash->{Key} = $accesskey; #not needed

    my $d = $modules{$hash->{TYPE}}{defptr}{"U$user"};
    return "device $user already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

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
    $hash->{helper}{appliver} = '9855c478';
    $hash->{helper}{csrf_token} = '9855c478';
  } else {
    return "Usage: define <name> withings ACCOUNT <login> <password>"  if(@a < 3 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype if(defined($subtype));


  #CommandAttr(undef,"$name DbLogExclude .*");


  my $resolve = inet_aton("scalews.withings.com");
  if(!defined($resolve))
  {
    $hash->{STATE} = "DNS error";
    InternalTimer( gettimeofday() + 900, "withings_InitWait", $hash, 0);
    return undef;
  }

  $hash->{STATE} = "Initialized" if( $hash->{SUBTYPE} eq "ACCOUNT" );

  if( $init_done ) {
    withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
    withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    InternalTimer(gettimeofday()+60, "withings_poll", $hash, 0) if( $hash->{SUBTYPE} eq "DUMMY" );
  }
  else
  {
    InternalTimer(gettimeofday()+15, "withings_InitWait", $hash, 0);
  }


  return undef;
}


sub withings_InitWait($) {
  my ($hash) = @_;
  Log3 "withings", 5, "withings: initwait ".$init_done;

  RemoveInternalTimer($hash);

  my $resolve = inet_aton("scalews.withings.com");
  if(!defined($resolve))
  {
    $hash->{STATE} = "DNS error";
    InternalTimer( gettimeofday() + 1800, "withings_InitWait", $hash, 0);
    return undef;
  }

  if( $init_done ) {
    withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
    withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    InternalTimer(gettimeofday()+60, "withings_poll", $hash, 0) if( $hash->{SUBTYPE} eq "DUMMY" );
  }
  else
  {
    InternalTimer(gettimeofday()+30, "withings_InitWait", $hash, 0);
  }

  return undef;

}

sub withings_Notify($$) {
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
  Log3 "withings", 5, "withings: notify";

  my $resolve = inet_aton("scalews.withings.com");
  if(!defined($resolve))
  {
    $hash->{STATE} = "DNS error";
    InternalTimer( gettimeofday() + 3600, "withings_InitWait", $hash, 0);
    return undef;
  }


  withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
  withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
}


sub withings_Undefine($$) {
  my ($hash, $arg) = @_;
  Log3 "withings", 5, "withings: undefine";
  RemoveInternalTimer($hash);

  delete( $modules{$hash->{TYPE}}{defptr}{"U$hash->{User}"} ) if( $hash->{SUBTYPE} eq "USER" );
  delete( $modules{$hash->{TYPE}}{defptr}{"D$hash->{Device}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );

  return undef;
}


sub withings_getToken($) {
  my ($hash) = @_;
  Log3 "withings", 5, "withings: gettoken";


  my $resolve = inet_aton("auth.withings.com");
  if(!defined($resolve))
  {
    Log3 "withings", 1, "withings: DNS error on getToken";
    return undef;
  }

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

  my $resolve = inet_aton("account.withings.com");
  if(!defined($resolve))
  {
    $hash->{SessionTimestamp} = 0;
    Log3 $name, 1, "$name: DNS error on getSessionData";
    return undef;
  }

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
  #     $hash->{STATE} = "APPLIVER error";
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
  #     $hash->{STATE} = "CSRF error";
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
      url => $hash->{'.https'}."://account.withings.com/connectionwou/account_login?r=https://healthmate.withings.com/",
    timeout => 10,
    noshutdown => 1,
    ignoreredirects => 1,
      data => { email=> withings_decrypt($hash->{helper}{username}), password => withings_decrypt($hash->{helper}{password}), is_admin => 'f' },
  };

  my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err || !defined($data) || $data =~ /Authentification failed/ || $data =~ /not a valid/)
  {
    Log3 $name, 1, "$name: LOGIN ERROR ";
    $hash->{STATE} = "Login error";
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
      $hash->{STATE} = "Cookie error";
      Log3 $name, 1, "$name: COOKIE ERROR ";
      $hash->{helper}{appliver} = '9855c478';
      $hash->{helper}{csrf_token} = '9855c478';
      return undef;
    }
  }

  if( !$hash->{AccountID} || length($hash->{AccountID} < 2 ) ) {

    ($err,$data) = HttpUtils_BlockingGet({
      url => $hash->{'.https'}."://scalews.withings.com/cgi-bin/account",
      timeout => 10,
      noshutdown => 1,
      data => {sessionid => $hash->{SessionKey}, appname => 'my2', appliver=> $hash->{helper}{appliver}, apppfm => 'web', action => 'get', enrich => 't'},
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
      $hash->{STATE} = "Account error";
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
      Log3 $name, 2, "$name: user '$user->{id}' already defined";
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
      
      Log3 $name, 2, "$name: device '$device->{deviceid}' already defined";
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
      Log3 $name, 2, "$name: user '$user->{id}' already defined";
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

      Log3 $name, 2, "$name: device '$device->{deviceid}' already defined";
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
      $hash->{UserDevice} = $modules{$hash->{TYPE}}{defptr}{"U".$devicelink->{linkuserid}} if defined($modules{$hash->{TYPE}}{defptr}{"U".$devicelink->{linkuserid}});
    }
  }


  if( !defined( $attr{$name}{stateFormat} ) ) {
    $attr{$name}{stateFormat} = "batteryPercent %";

    $attr{$name}{stateFormat} = "co2 ppm" if( $device->{model} == 4 );
    $attr{$name}{stateFormat} = "voc ppm" if( $device->{model} == 22 );
    $attr{$name}{stateFormat} = "light lux" if( $device->{model} == 60 );
    $attr{$name}{stateFormat} = "lastWeighinDate" if( $device->{model} == 61 );
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
    data => {sessionid => $hash->{SessionKey}, accountid => $hash->{AccountID} , recurse_use => '1', recurse_devtype => '1', listmask => '5', allusers => 't' , appname => 'my2', appliver=> $hash->{helper}{appliver}, apppfm => 'web', action => 'getuserslist'},
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
    data => {sessionid => $hash->{SessionKey}, accountid => $hash->{AccountID} , type => '-1', enrich => 't' , appname => 'my2', appliver=> $hash->{helper}{appliver}, apppfm => 'web', action => 'getbyaccountid'},
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
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid => $hash->{Device} , appname => 'my2', appliver=> $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getproperties'},
  });

  #Log3 $name, 5, "$name: getdevicedetaildata ".Dumper($data);
  return undef if(!defined($data));

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: json evaluation error on getDeviceDetail ".$@;
    return undef;
  }
  Log3 $name, 1, "withings: getDeviceDetail json error ".$json->{error} if(defined($json->{error}));

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
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getproperties'},
      hash => $hash,
      type => 'deviceProperties',
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollProperties", $seconds, 0 );

  return undef;




}

sub withings_getDeviceReadingsScale($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: getscalereadings ".$hash->{Device};
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
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, meastype => '12,35', startdate => int($lastupdate), enddate => int($enddate), devicetype => '16', appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getmeashf'},
      hash => $hash,
      type => 'deviceReadingsScale',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollData", $seconds, 0 );

  return undef;

}


sub withings_getDeviceReadingsBedside($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: getaurareadings ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(8*60*60));
  $enddate = $now if ($enddate > $now);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 30,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, meastype => '12,13,14,15,56', startdate => int($lastupdate), enddate => int($enddate), devicetype => '16', appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getmeashf'},
      hash => $hash,
      type => 'deviceReadingsBedside',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollData", $seconds, 0 );

  return undef;

}


sub withings_getDeviceReadingsHome($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: gethomereadings ".$hash->{Device};
  return undef if( !defined($hash->{Device}) );

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(8*60*60));
  $enddate = $now if ($enddate > $now);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 30,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, deviceid=> $hash->{Device}, meastype => '12,13,14,15,58', startdate => int($lastupdate), enddate => int($enddate), devicetype => '16', appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getmeashf'},
      hash => $hash,
      type => 'deviceReadingsHome',
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
  Log3 $name, 5, "$name: getbabyevents ".$hash->{Device};
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
  Log3 $name, 5, "$name: gethomealerts ".$hash->{Device};
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
  Log3 $name, 5, "$name: getbabyevents ".$hash->{Device};
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
  Log3 $name, 5, "$name: getbabyvideo ".$hash->{Device};
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
  Log3 $name, 5, "$name: gets3credentials ".$hash->{Device};

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
  Log3 $name, 5, "$name: getuserdetails ".$hash->{User};
  return undef if( !defined($hash->{User}) );

  return undef if( $hash->{SUBTYPE} ne "USER" );

  return undef if( !defined($hash->{IODev}));
  withings_getSessionKey( $hash->{IODev} );

  my ($err,$data) = HttpUtils_BlockingGet({
    url => $hash->{'.https'}."://scalews.withings.com/index/service/user",
    timeout => 10,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid => $hash->{User} , appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getbyuserid'},
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

  RemoveInternalTimer($hash);

  return undef if(IsDisabled($name));


  #my $resolve = inet_aton("scalews.withings.com");
  #if(!defined($resolve))
  #{
  #  $hash->{STATE} = "DNS error";
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
      withings_getDeviceReadingsScale($hash) if($force || $lastData <= ($now - $intervalData));
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
      withings_getDeviceReadingsHome($hash) if($force || $lastData <= ($now - $intervalData));
      withings_getDeviceAlertsHome($hash) if($force || $lastAlert <= ($now - $intervalAlert));
    }
    elsif(defined($hash->{typeID}) && $hash->{typeID} eq '16') {
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getUserReadingsActivity($hash) if($force || $lastData <= ($now - $intervalData));
    }
    elsif(defined($hash->{modelID}) && $hash->{modelID} eq '60') {
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getDeviceReadingsBedside($hash) if($force || $lastData <= ($now - $intervalData));
    }
    elsif(defined($hash->{modelID}) && ($hash->{modelID} eq '61' || $hash->{modelID} eq '62' || $hash->{modelID} eq '63')) {
      withings_getDeviceProperties($hash) if($force > 1 || $lastProperties <= ($now - $intervalProperties));
      withings_getUserReadingsSleep($hash) if($force || $lastData <= ($now - $intervalData));
      withings_getUserReadingsSleepDebug($hash) if($force || $lastDebug <= ($now - $intervalDebug));
    }
    else
    {
      withings_getDeviceProperties($hash) if($force || $lastProperties <= ($now - $intervalProperties));
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
  Log3 $name, 5, "$name: getuserdailystats ".$hash->{User};

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
    data => {sessionid => $hash->{IODev}->{SessionKey},  userid=> $hash->{User}, range => '1', meastype => '36,37,38,40,41,49,50,51,52,53,87', startdateymd => $startdateymd, enddateymd => $enddateymd, appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getbyuserid'},
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

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/activity",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey},  userid=> $hash->{User}, subcategory => '37', startdateymd => $startdateymd, enddateymd => $enddateymd, appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getbyuserid'},
      hash => $hash,
      type => 'userDailyActivity',
      enddate => int($enddate),
      callback => \&withings_Dispatch,
  });

#  HttpUtils_NonblockingGet({
#    url => "https://scalews.withings.com/cgi-bin/v2/activity",
#    timeout => 60,
#    noshutdown => 1,
#    data => {sessionid => $hash->{IODev}->{SessionKey},  userid=> $hash->{User}, startdateymd => $startdateymd, enddateymd => $enddateymd, appname => 'hmw', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getbyuserid'},
#      hash => $hash,
#      type => 'userDailyActivity',
#      enddate => int($enddate),
#      callback => \&withings_Dispatch,
#  });

  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
  readingsSingleUpdate( $hash, ".pollDaily", $seconds, 0 );

  return undef;


}



sub withings_getUserReadingsCommon($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: getuserreadings ".$hash->{User};

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
    data => {sessionid => $hash->{IODev}->{SessionKey}, category => '1',  userid=> $hash->{User}, offset => '0', limit => '400', startdate => int($lastupdate), enddate => int($enddate), appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getmeas'},
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
  Log3 $name, 5, "$name: getsleepreadings ".$hash->{User};

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(8*60*60));
  $enddate = $now if ($enddate > $now);
  #    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '43,44,11,57,59,60,61,62,63,64,65,66,67,68,69,70', startdate => int($lastupdate), enddate => int($enddate), devicetype => '32', appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '11,39,41,43,44,57,59,87', startdate => int($lastupdate), enddate => int($enddate), devicetype => '32', appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},
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
  Log3 $name, 5, "$name: getsleepreadingsdebug ".$hash->{User};

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastDebug", ($now-7*24*60*60) );#$hash->{created} );
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(8*60*60));
  $enddate = $now if ($enddate > $now);

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '60,61,62,63,64,65,66,67,68,69,70', startdate => int($lastupdate), enddate => int($enddate), devicetype => '32', appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},
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

  Log3 $name, 5, "$name: getactivityreadings ".$hash->{User};

  return undef if( !defined($hash->{IODev}) );
  withings_getSessionKey( $hash->{IODev} );

  my ($now) = time;
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-7*24*60*60) );#$hash->{created} );#
  $lastupdate = $hash->{lastsessiondate} if(defined($hash->{lastsessiondate}) and $hash->{lastsessiondate} < $lastupdate);
  my $enddate = ($lastupdate+(8*60*60));
  $enddate = $now if ($enddate > $now);

 Log3 $name, 5, "$name: getactivityreadings ".$lastupdate." to ".$enddate;

  HttpUtils_NonblockingGet({
    url => "https://scalews.withings.com/cgi-bin/v2/measure",
    timeout => 60,
    noshutdown => 1,
    data => {sessionid => $hash->{IODev}->{SessionKey}, userid=> $hash->{User}, meastype => '36,37,38,39,40,41,42,43,44,59,70,87,90', startdate => int($lastupdate), enddate => int($enddate), devicetype => '16', appname => 'my2', appliver => $hash->{IODev}->{helper}{appliver}, apppfm => 'web', action => 'getvasistas'},
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
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-21*24*60*60) );
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
            Log3 $name, 1, "$name: unknown measure type: $measure->{type}";
            next;
          }

          my $value = $measure->{value} * 10 ** $measure->{unit};

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
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-21*24*60*60) );
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
          Log3 $name, 1, "$name: unknown measure type: $series->{type}";
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
  my $lastupdate = ReadingsVal( $name, ".lastAggregate", ($now-21*24*60*60) );
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
                  Log3 $name, 1, "$name: unknown measure type: $typestring";
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
  my $lastupdate = ReadingsVal( $name, ".lastActivity", ($now-21*24*60*60) );
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

        foreach my $dataset ( keys (%{$series->{data}}))
        {
          if(!defined($sleep_readings{$dataset}->{reading}))
          {
            Log3 $name, 2, "$name: unknown sleep reading $dataset";
            next;
          }

          my ($year,$mon,$day) = split(/[\s-]+/, $series->{date});
          my $timestamp = timelocal(0,0,6,$day,$mon-1,$year-1900);
          my $reading = $sleep_readings{$dataset}->{reading};
          my $value = $series->{data}{$dataset};

          push(@readings, [$timestamp, $reading, $value]);
        }

     }


      if( @readings ) {
        $i = 0;
        foreach my $reading (sort { $a->[0] <=> $b->[0] } @readings) {
          if( $reading->[0] < $newlastupdate )
          {
            Log3 $name, 5, "$name: old activity skipped: ".FmtDateTime($reading->[0])." ".$reading->[1];
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
        Log3 $name, 2, "$name: Activity gap error! (latest: ".FmtDateTime($newlastupdate)." < ".FmtDateTime($lastupdate-1).") .$i if($i>0)";
        withings_getDeviceProperties($hash) if($i>0);
        $newlastupdate = $lastupdate-1;
      }

      readingsSingleUpdate( $hash, ".lastActivity", $newlastupdate+1, 0 );
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
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-21*24*60*60) );
  $lastupdate = ReadingsVal( $name, ".lastDebug", ($now-21*24*60*60) ) if($datatype =~ /Debug/);

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
          if($updatetype eq "activityType")
          {
            my $activity = $updatevalue;
            $updatevalue = $activity_types{$updatevalue};
            if( !defined($updatevalue) ) {
              Log3 $name, 1, "$name: unknown activity type: $activity";
              $updatevalue = $activity;
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
          if($iscurrent == 0 && $datatype =~ /Sleep/){
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
      if($datatype =~ /Sleep/ && $iscurrent == 0){
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
  my $lastupdate = ReadingsVal( $name, ".lastAlert", ($now-21*24*60*60) );
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
  my $lastupdate = ReadingsVal( $name, ".lastData", ($now-21*24*60*60) );
  my $lastalertupdate = ReadingsVal( $name, ".lastAlert", ($now-21*24*60*60) );
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
    $list = "update:noArg updateAll:noArg";

    if( $cmd eq "updateAll" ) {
      withings_poll($hash,2);
      return undef;
    }
    elsif( $cmd eq "update" ) {
      withings_poll($hash,1);
      return undef;
    }
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
    $list = " nap:noArg sleep:noArg alarm:noArg";
    $list .= " stop:noArg snooze:noArg";
    $list .= " nap_volume:slider,0,1,100 nap_brightness:slider,0,1,100";
    $list .= " sleep_volume:slider,0,1,100 sleep_brightness:slider,0,1,100";
    $list .= " clock_state:on,off clock_brightness:slider,0,1,100";
    $list .= " flashMat";
    $list .= " sensors:on,off";
    $list .= " rawCmd";
    if (defined($hash->{helper}{ALARMSCOUNT})&&($hash->{helper}{ALARMSCOUNT}>0))
    {
        for(my $i=1;$i<=$hash->{helper}{ALARMSCOUNT};$i++)
        {
          $list .= " alarm".$i."_time alarm".$i."_volume:slider,0,1,100 alarm".$i."_brightness:slider,0,1,100";
          $list .= " alarm".$i."_state:on,off alarm".$i."_wdays";
          $list .= " alarm".$i."_smartwake:slider,0,1,60";
        }
    }


    if ( lc $cmd eq 'nap' or lc $cmd eq 'sleep' or lc $cmd eq 'alarm' or lc $cmd eq 'stop' or lc $cmd eq 'snooze' )
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
    return withings_autocreate($hash) if($cmd eq "autocreate");
    return "Unknown argument $cmd, choose one of $list";
  } else {
    return "Unknown argument $cmd, choose one of $list";
  }
}


sub withings_readAuraAlarm($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: readauraalarm";

  my $auraip = AttrVal($name,"IP",undef);
  return if(!$auraip);

  my $socket = new IO::Socket::INET (
    PeerHost => $auraip,
    PeerPort => '7685',
    Proto => 'tcp',
    Timeout => 5,
  ) or die "ERROR in Socket Creation : $!\n";
  return if(!$socket);
  $socket->autoflush(1);

  my $data = "000100010100050101010000"; #hello
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data,1024);
  $socket->flush();

  $data="010100050101110000"; #hello2
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data, 1024);
  $socket->flush();


  $data="0101000a01090a0005090a000100"; #ping
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data, 1024);
  $socket->flush();

  $data="010100050101250000"; #new alarmdata
  $socket->send(pack('H*', $data));
  $socket->flush();

  $socket->recv($data, 1024);
  $socket->flush();



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


  for(my $i=$alarmcounter;$i<10;$i++)
  {
    fhem( "deletereading $name alarm".$i."_.*" );
  }

  $data="010100050109100000"; #sensordata
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data, 1024);
  $socket->flush();
  my $sensors = (ord(substr($data,19,1))==0)?"on":"off";
  readingsBulkUpdate( $hash, "sensors", $sensors, 1 );



  $data="0101000b0109060006090800020300"; #sleepdata
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data, 1024);
  $socket->flush();

  #Log3 $name, 4, "$name: sleepdata ".unpack('H*', $data);

  my $sleepvolume = ord(substr($data,13,1));
  my $sleepbrightness = ord(substr($data,14,1));
  my $sleepsong = ord(substr($data,16,1));
  readingsBulkUpdate( $hash, "sleep_volume", $sleepvolume, 1 );
  readingsBulkUpdate( $hash, "sleep_brightness", $sleepbrightness, 1 );
  readingsBulkUpdate( $hash, "sleep_sound", $sleep_sound{$sleepsong}, 1 );


  $data="0101000b0109060006090800020200"; #napdata
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data, 1024);
  $socket->flush();

  #Log3 $name, 4, "$name: napdata ".unpack('H*', $data);

  my $napvolume = ord(substr($data,13,1));
  my $napbrightness = ord(substr($data,14,1));
  my $napsong = ord(substr($data,16,1));
  readingsBulkUpdate( $hash, "nap_volume", $napvolume, 1 );
  readingsBulkUpdate( $hash, "nap_brightness", $napbrightness, 1 );
  readingsBulkUpdate( $hash, "nap_sound", $nap_sound{$napsong}, 1 );

  $data="010100050109100000"; #clock
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data, 1024);
  $socket->flush();

  my $clockdisplay = ord(substr($data,13,1));
  my $clockbrightness = ord(substr($data,14,1));
  readingsBulkUpdate( $hash, "clock_state", ($clockdisplay ? "on":"off"), 1 );
  readingsBulkUpdate( $hash, "clock_brightness", $clockbrightness, 1 );

  #Log3 $name, 4, "$name: clock ".unpack('H*', $data);



  $data="010100050109070000"; #state
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data, 1024);
  $socket->flush();

  #Log3 $name, 4, "$name: state ".unpack('H*', $data);

  my $devicestate = ord(substr($data,18,1));
  my $alarmtype = ord(substr($data,13,1));

  if($devicestate eq 0)
  {
    readingsBulkUpdate( $hash, "state", "off", 1 );
  }
  elsif($devicestate eq 2)
  {
    readingsBulkUpdate( $hash, "state", "snoozed", 1 );
  }
  elsif($devicestate eq 1)
  {
    readingsBulkUpdate( $hash, "state", "sleep", 1 ) if($alarmtype eq 1);
    readingsBulkUpdate( $hash, "state", "alarm", 1 ) if($alarmtype eq 2);
    readingsBulkUpdate( $hash, "state", "nap", 1 ) if($alarmtype eq 3);
  }

  readingsEndUpdate($hash,1);


  $socket->close();
  return;

}

sub withings_setAuraAlarm($$;$) {
  my ($hash, $setting, $value) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: setaura ".$setting;

  my $auraip = AttrVal($name,"IP",undef);
  return if(!$auraip);

  my $socket = new IO::Socket::INET (
    PeerHost => $auraip,
    PeerPort => '7685',
    Proto => 'tcp',
    Timeout => 5,
  ) or die "ERROR in Socket Creation : $!\n";
  return if(!$socket);
  $socket->autoflush(1);

  my $data = "000100010100050101010000"; #hello
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data,1024);
  $socket->flush();

  $data="010100050101110000"; #hello2
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data,1024);
  $socket->flush();

  $data="0101000a01090a0005090a000100"; #ping
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data,1024);
  $socket->flush();

  $data="010100050109070000"; #getstate

  if($setting eq "nap")
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
    $data .= sprintf("%.2x",ReadingsVal( $name, "nap_sound", 1)==0?1:ReadingsVal( $name, "nap_sound", 1));
  }
  elsif($setting =~ /^sleep/)
  {
    $data = "0101000d010905000809060004";
    $data .= sprintf("%.2x",ReadingsVal( $name, "sleep_volume", 25));
    $data .= sprintf("%.2x",ReadingsVal( $name, "sleep_brightness", 10));
    $data .= "03";
    $data .= sprintf("%.2x",ReadingsVal( $name, "sleep_sound", 1)==0?1:ReadingsVal( $name, "sleep_sound", 1));
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

  Log3 $name, 3, "$name: writesocket ".$data;



  $socket->send(pack('H*', $data));
  $socket->flush();

  $socket->recv($data, 1024);
  $socket->flush();

  Log3 $name, 4, "$name: readsocket ".unpack('H*', $data);

  $socket->close();
  return;

}

sub withings_setAuraDebug($$;$) {
  my ($hash, $value) = @_;
  my $name = $hash->{NAME};

  my $auraip = AttrVal($name,"IP",undef);
  return if(!$auraip);

  my $socket = new IO::Socket::INET (
    PeerHost => $auraip,
    PeerPort => '7685',
    Proto => 'tcp',
    Timeout => 5,
  ) or die "ERROR in Socket Creation : $!\n";
  return if(!$socket);
  $socket->autoflush(1);

  my $data = "000100010100050101010000"; #hello
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data,1024);
  $socket->flush();

  $data="010100050101110000"; #hello2
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data,1024);
  $socket->flush();

  $data="0101000a01090a0005090a000100"; #ping
  $socket->send(pack('H*', $data));
  $socket->flush();
  $socket->recv($data,1024);
  $socket->flush();

  $data=$value; #debug
  Log3 $name, 5, "$name: writesocket ".$data;
  Log3 $name, 5, "$name: writesocket ".pack('H*', $data);

  $socket->send(pack('H*', $data));
  $socket->flush();
  $data="";
  $socket->recv($data, 1024);
  $socket->flush();

  Log3 $name, 5, "$name: readsocket ".$data;
  Log3 $name, 5, "$name: readsocket ".unpack('H*', $data);

  $socket->close();
  return;

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

    if( $param->{type} eq 'deviceReadingsScale' || $param->{type} eq 'deviceReadingsBedside' || $param->{type} eq 'deviceReadingsHome' ) {
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



sub withings_encrypt($)
{
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /crypt:/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'.$encoded;
}

sub withings_decrypt($)
{
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if( $encoded !~ /crypt:/ );
  
  $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
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
    $unit = '˚C';
  }
  elsif($event =~ m/bodyTemperature/)
  {
    $reading = 'bodyTemperature';
    $unit = '˚C';
  }
  elsif($event =~ m/skinTemperature/)
  {
    $reading = 'skinTemperature';
    $unit = '˚C';
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
    <li>wakeupCount</li>

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
    <li>interval<br>
      the interval in seconds used to check for new values.</li>
    <li>disable<br>
      1 -> stop polling</li>
  </ul>
</ul>

=end html
=cut

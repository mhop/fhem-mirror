##############################################
# $Id$
# See ZWDongle.pm for inspiration
package main;

use strict;
use warnings;
use SetExtensions;
use Compress::Zlib;

sub ZWave_Parse($$@);
sub ZWave_Set($@);
sub ZWave_Get($@);
sub ZWave_Cmd($$@);
sub ZWave_ParseMeter($$);
sub ZWave_ParseScene($);
sub ZWave_SetClasses($$$$);
sub ZWave_getParse($$$);

use vars qw(%zw_func_id);
use vars qw(%zw_type6);

my %zwave_id2class;
my %zwave_class = (
  NO_OPERATION             => { id => '00', },
  BASIC                    => { id => '20',
    set   => { basicValue  => "01%02x", },
    get   => { basicStatus => "02",     }, 
    parse => { "..200.(.*)"=> '"basicReport:$1"',}, },
  CONTROLLER_REPLICATION   => { id => '21', },
  APPLICATION_STATUS       => { id => '22', },
  ZIP_SERVICES             => { id => '23', },
  ZIP_SERVER               => { id => '24', },
  SWITCH_BINARY            => { id => '25',
    set   => { off         => "0100",
               on          => "01FF",
               reportOn    => "03FF",
               reportOff   => "0300",     },
    get   => { swbStatus   => "02",       },
    parse => { "03250300"  => "state:off",
               "032503ff"  => "state:on",  }, } ,
  SWITCH_MULTILEVEL        => { id => '26', 
    set   => { off         => "0100",
               on          => "01FF",
               dim         => "01%02x", 
               reportOn    => "03FF",
               reportOff   => "0300",     },
    get   => { swmStatus   => "02",     }, 
    #03260363 reported in http://forum.fhem.de/index.php?t=rview&th=10216
    parse => { "032603(.*)"=> '($1 eq "00" ? "state:off" : 
                               ($1 eq "ff" ? "state:on" : 
                                             "state:dim ".hex($1)))',}, },
  SWITCH_ALL               => { id => '27',
    set   => { swaIncludeNone  => "0100",
               swaIncludeOff   => "0101",
               swaIncludeOn    => "0102",
               swaIncludeOnOff => "01ff",
               swaOn           => "04",
               swaOff          => "05", },
    get   => { swaInclude      => "02", },
    parse => { "03270300"      => "swa:none",
               "03270301"      => "swa:off",
               "03270302"      => "swa:on",
               "032703ff"      => "swa:on off", }, },
  SWITCH_TOGGLE_BINARY     => { id => '28', },
  SWITCH_TOGGLE_MULTILEVEL => { id => '29', },
  CHIMNEY_FAN              => { id => '2a', },
  SCENE_ACTIVATION         => { id => '2b',
    set   => { sceneActivate => "01%02x%02x",}, 
    parse => { "042b01(..)(..)"  => '"scene_$1:$2"',
               "042b01(..)ff" => 'ZWave_ParseScene($1)',}, },
  SCENE_ACTUATOR_CONF      => { id => '2c',
    set   => { sceneConfig => "01%02x%02x80%02x",},
    get   => { sceneConfig => "02%02x",          },
    parse => { "052c03(..)(..)(..)"   => '"scene_$1:level $2 duration $3"',}, },
  SCENE_CONTROLLER_CONF    => { id => '2d',   
    set   => { sceneConfig => "01%02x%02x%02x",},
    get   => { sceneConfig => "02%02x",          },
    parse => { "052d03(..)(..)(..)"   => '"group_$1:scene $2 duration $3"',}, },
  ZIP_CLIENT               => { id => '2e', },
  ZIP_ADV_SERVICES         => { id => '2f', },
  SENSOR_BINARY            => { id => '30', 
    get   => { sbStatus    => "02",       },
    parse => { "03300300"  => "state:closed",
               "033003ff"  => "state:open", 
               "043003(..)0c" => '"motion:$1"',  #Philio PHI_PSP01, PSM02-1
               "043003(..)08" => '"tamper:$1"',  #Philio PHI_PSP01, PSM02-1
               "043003000a"   => "state:closed", #Philio PSM02-1
               "043003ff0a"   => "state:open",   #Philio PSM02-1
               },},
  SENSOR_MULTILEVEL        => { id => '31', 
    get   => { smStatus    => "04" },
    parse => { "..3105(..)(..)(.*)" => 'ZWave_ParseMultilevel($1,$2,$3)'},},
  METER                    => { id => '32',
    get   => { meter       => "01" },
    parse => { "..3202(.*)"=> 'ZWave_ParseMeter($hash, $1)' }, },
  ZIP_ADV_SERVER           => { id => '33', },
  ZIP_ADV_CLIENT           => { id => '34', },
  METER_PULSE              => { id => '35', },
  HRV_STATUS               => { id => '37', 
    get   => { hrvStatus    => "01%02x",
               hrvStatusSupported => "03",},
    parse => { "0637020042(....)" =>
                   'sprintf("outdoorTemperature: %0.1f C", s2Hex($1)/100)',
               "0637020142(....)" =>
                   'sprintf("supplyAirTemperature: %0.1f C", s2Hex($1)/100)',
               "0637020242(....)" =>
                   'sprintf("exhaustAirTemperature: %0.1f C", s2Hex($1)/100)',
               "0637020342(....)" =>
                   'sprintf("dischargeAirTemperature: %0.1f C",s2Hex($1)/100)',
               "0637020442(....)" =>
                   'sprintf("indoorTemperature: %0.1f C", s2Hex($1)/100)',
               "0537020501(..)" =>
                   'sprintf("indoorHumidity: %s %%", hex($1))',
               "0537020601(..)" =>
                   'sprintf("remainingFilterLife: %s %%", hex($1))',
               "033704(..)" =>
                   'sprintf("supportedStatus: %s", ZWave_HrvStatus($1))',
            },},
  THERMOSTAT_HEATING       => { id => '38', },
  HRV_CONTROL              => { id => '39', 
    set   => { bypassOff => "0400",
               bypassOn  => "04FF",
               ventilationRate => "07%02x", },
    get   => { bypass          => "05", 
                ventilationRate => "08", },  
    parse => { "033906(..)"=> '($1 eq "00" ? "bypass:off" : '.
                              '($1 eq "ff" ? "bypass:on"  : '.
                                            '"bypass:dim ".hex($1)))',
               "033909(..)"=> 'sprintf("ventilationRate: %s",hex($1))', },},
  METER_TBL_CONFIG         => { id => '3c', },
  METER_TBL_MONITOR        => { id => '3d', },
  METER_TBL_PUSH           => { id => '3e', },
  THERMOSTAT_MODE          => { id => '40',
    set   => { tmOff       => "0100",
               tmHeating   => "0101",
               tmCooling   => "010b",
               tmManual    => "011f", },
    get   => { thermostatMode => "02", },
    parse => { "03400300"  => "state:off",
               "0340030b"  => "state:cooling",
               "03400301"  => "state:heating",
               "0340031f"  => "state:manual",  }, } ,
  THERMOSTAT_OPERATING_STATE=>{ id => '42', },
  THERMOSTAT_SETPOINT      => { id => '43',
    set   => { setpointHeating => "010101%02x",
               setpointCooling => "010201%02x"},
    get   => { setpoint => "02" },
    parse => { "064303(..)(..)(....)" => 'sprintf("temperature:%0.1f %s %s", '.
                 'hex($3)/(10**int(hex($2)/32)), '.
                 'hex($2)&8 ? "F":"C", $1==1 ? "heating":"cooling")' }, },
  THERMOSTAT_FAN_MODE      => { id => '44', },
  THERMOSTAT_FAN_STATE     => { id => '45', },
  CLIMATE_CONTROL_SCHEDULE => { id => '46',
    get   => { ccsOverride  => "07", },
    parse => { "0446080079" => "ccsOverride:no, frost protection",
               "044608007a" => "ccsOverride:no, energy saving",
               "044608007f" => "ccsOverride:no, unused",
               "0446080179" => "ccsOverride:temporary, frost protection",
               "044608017a" => "ccsOverride:temporary, energy saving",
               "044608017f" => "ccsOverride:temporary, unused",
               "0446080279" => "ccsOverride:permanent, frost protection",
               "044608027a" => "ccsOverride:permanent, energy saving",
               "044608027f" => "ccsOverride:permanent, unused", }, },
  THERMOSTAT_SETBACK       => { id => '47', },
  DOOR_LOCK_LOGGING        => { id => '4c', },
  SCHEDULE_ENTRY_LOCK      => { id => '4e', },
  BASIC_WINDOW_COVERING    => { id => '50',
    set   => { coveringClose  => "0140",
               coveringOpen   => "0100",
               coveringStop   => "02" , },  },
  MTP_WINDOW_COVERING      => { id => '51', },
  CRC_16_ENCAP             => { id => '56', },
  MULTI_CHANNEL            => { id => '60',  # Version 2, aka MULTI_INSTANCE
    get   => { mcEndpoints => "07",     # Endpoints
               mcCapability=> "09%02x"},
    parse => { "^046008(..)(..)" => '"mcEndpoints:total ".hex($2).'.
                                 '(hex($1)&0x80 ? ", dynamic":"").'.
                                 '(hex($1)&0x40 ? ", identical":", different")',
               "^..600a(.*)"=> 'ZWave_mcCapability($hash, $1)' }, },
  DOOR_LOCK                => { id => '62', },
  USER_CODE                => { id => '63', },
  CONFIGURATION            => { id => '70', 
    set   => { configDefault=>"04%02x80",
               configByte  => "04%02x01%02x",
               configWord  => "04%02x02%04x",
               configLong  => "04%02x04%08x", },
    get   => { config      => "05%02x", },
    parse => { "^..70..(..)..(.*)" => 'ZWave_configParse($hash,$1,$2)'} },

  ALARM                    => { id => '71', 
    get   => { alarm       => "04%02x", },
    parse => { "..7105(..)(..)" => '"alarm_type_$1:level $2"',}, },
  MANUFACTURER_SPECIFIC    => { id => '72',
    get   => { model       => "04", },
    parse => { "087205(....)(....)(....)" => 'ZWave_mfsParse($1,$2,$3,0)',
               "087205(....)(....)(.{4})" => 'ZWave_mfsParse($1,$2,$3,1)',
               "087205(....)(.{4})(.{4})" => '"modelId:$1-$2-$3"', }},
  POWERLEVEL               => { id => '73', },
  PROTECTION               => { id => '75',
    set   => { protectionOff => "0100",
               protectionSeq => "0101",
               protectionOn  => "0102", },
    get   => { protection    => "02", },
    parse => { "03750300"      => "protection:off",
               "03750301"      => "protection:seq",
               "03750302"      => "protection:on", }, },
  LOCK                     => { id => '76', },
  NODE_NAMING              => { id => '77', },
  FIRMWARE_UPDATE_MD       => { id => '7a', },
  GROUPING_NAME            => { id => '7b', },
  REMOTE_ASSOCIATION_ACTIVATE=>{id => '7c', },
  REMOTE_ASSOCIATION       => { id => '7d', },
  BATTERY                  => { id => '80',
    get   => { battery     => "02" },
    parse => { "038003(..)"=> '"battery:".($1 eq "ff" ? "low":hex($1)." %")'},},
  CLOCK                    => { id => '81',
    parse => { "028105"=> "clock:get" }, },
  HAIL                     => { id => '82', },
  WAKE_UP                  => { id => '84', 
    set   => { wakeupInterval => "04%06x%02x",
               wakeupNoMoreInformation => "08", },
    get   => { wakeupInterval => "05", 
               wakeupIntervalCapabilities => "09", },
    parse => { "028407"    => 'wakeup:notification',
               "..8406(......)(..)" =>
                '"wakeupReport:interval ".hex($1)." target ".hex($2)',
               "..840a(......)(......)(......)(......)" =>
                '"wakeupIntervalCapabilitiesReport:min ".hex($1).'.
                         '" max ".hex($2)." default ".hex($3)." step ".hex($4)'
             }, },
  ASSOCIATION              => { id => '85', 
    set   => { associationAdd => "01%02x%02x*",
               associationDel => "04%02x%02x*", },
    get   => { association => "02%02x",      },
    parse => { "..8503(..)(..)..(.*)" => '"assocGroup_$1:Max $2 Nodes $3"',}, },
  VERSION                  => { id => '86',
    get   => { version      => "11",
               versionClass => "13%02x", },
    parse => { "078612(..)(..)(..)(..)(..)" =>
    'sprintf("version:Lib %d Prot %d.%d App %d.%d",'.
        'hex($1),hex($2),hex($3),hex($4),hex($5))', 
               "048614(..)(..)"             => '"versionClass_$1:$2"', }, },
  INDICATOR                => { id => '87',
    set   => { indicatorOff    => "0100",
               indicatorOn     => "01FF",
               indicatorDim    => "01%02x", },
    get   => { indicatorStatus => "02",     }, 
    parse => { "038703(..)"    => '($1 eq "00" ? "indState:off" : 
                               ($1 eq "ff" ? "indState:on" : 
                                             "indState:dim ".hex($1)))',}, },
  PROPRIETARY              => { id => '88', },
  LANGUAGE                 => { id => '89', },
  TIME                     => { id => '8a', },
  TIME_PARAMETERS          => { id => '8b', },
  GEOGRAPHIC_LOCATION      => { id => '8c', },
  COMPOSITE                => { id => '8d', },
  MULTI_CHANNEL_ASSOCIATION=> { id => '8e', }, # aka MULTI_INSTANCE_ASSOCIATION
  MULTI_CMD                => { id => '8f', }, # Handled in Parse
  ENERGY_PRODUCTION        => { id => '90', },
  MANUFACTURER_PROPRIETARY => { id => '91', }, # see also zwave_deviceSpecial
  SCREEN_MD                => { id => '92', },
  SCREEN_ATTRIBUTES        => { id => '93', },
  SIMPLE_AV_CONTROL        => { id => '94', },
  AV_CONTENT_DIRECTORY_MD  => { id => '95', },
  AV_RENDERER_STATUS       => { id => '96', },
  AV_CONTENT_SEARCH_MD     => { id => '97', },
  SECURITY                 => { id => '98', },
  AV_TAGGING_MD            => { id => '99', },
  IP_CONFIGURATION         => { id => '9a', },
  ASSOCIATION_COMMAND_CONFIGURATION
                           => { id => '9b', },
  SENSOR_ALARM             => { id => '9c',
    get   => { alarm       => "01%02x", },
    parse => { "..9c02(..)(..)(..)(....)" =>
                '"alarm_type_$2:level $3 node $1 seconds ".hex($4)',}, },  
  SILENCE_ALARM            => { id => '9d', },
  SENSOR_CONFIGURATION     => { id => '9e', },
  MARK                     => { id => 'ef', },
  NON_INTEROPERABLE        => { id => 'f0', },
);

my %zwave_cmdArgs = (
  set => {
    dim          => "slider,0,1,99",
    indicatorDim => "slider,0,1,99",
  },
  get => {
  },
  parse => {
  }
);

my %zwave_modelConfig;
my %zwave_modelIdAlias = ( "010f-0301-1001" => "Fibaro_FGRM222",
                           "013c-0001-0003" => "Philio_PAN04" );

# Patching certain devices.
my %zwave_deviceSpecial = (
   Fibaro_FGRM222 => {
     MANUFACTURER_PROPRIETARY => {
      set   => { positionSlat=>"010f26010100%02x", 
                 positionBlinds=>"010f260102%02x00",},
      get   => { position=>"010f2602020000", },
      parse => { "010f260303(..)(..)" =>'sprintf("position:Blinds %d Slat %d",'.
                                            'hex($1),hex($2))' } } },
   Philio_PAN04 => {
     METER => {
      get   => { meter       => "01",
                 meterWatt   => "0110",       #Watt
                 meterVoltage=> "0120",       #Voltage
                 meterAmpere => "0128"  } } } #Ampere
);

sub
ZWave_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = ".*";
  $hash->{SetFn}     = "ZWave_Set";
  $hash->{GetFn}     = "ZWave_Get";
  $hash->{DefFn}     = "ZWave_Define";
  $hash->{UndefFn}   = "ZWave_Undef";
  $hash->{ParseFn}   = "ZWave_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
    "ignore:1,0 dummy:1,0 showtime:1,0 classes $readingFnAttributes";
  map { $zwave_id2class{lc($zwave_class{$_}{id})} = $_ } keys %zwave_class;

  $hash->{FW_detailFn} = "ZWave_fhemwebFn";
}


#############################
sub
ZWave_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name   = shift @a;
  my $type = shift(@a); # always ZWave

  my $u = "wrong syntax for $name: define <name> ZWave homeId id [classes]";
  return $u if(int(@a) < 2 || int(@a) > 3);

  my $homeId = lc(shift @a);
  my $id     = shift @a;

  return "define $name: wrong homeId ($homeId): need an 8 digit hex value"
                   if( ($homeId !~ m/^[a-f0-9]{8}$/i) );
  return "define $name: wrong id ($id): need a number"
                   if( ($id !~ m/^\d+$/i) );

  $id = sprintf("%0*x", ($id > 255 ? 4 : 2), $id);
  $hash->{homeId} = $homeId;
  $hash->{id}     = $id;

  $modules{ZWave}{defptr}{"$homeId $id"} = $hash;
  AssignIoPort($hash);  # FIXME: should take homeId into account

  if(@a) {
    ZWave_SetClasses($homeId, $id, undef, $a[0]);

    if($attr{$name}{classes} =~ m/ASSOCIATION/) {
      my $iodev = $hash->{IODev};
      my $homeReading = ReadingsVal($iodev->{NAME}, "homeId", "") if($iodev);
      my $ctrlId = $1 if($homeReading && $homeReading =~ m/CtrlNodeId:(..)/);

      if($ctrlId) {
        Log3 $name, 1, "Adding the controller $ctrlId to association group 1";
        IOWrite($hash, "00", "130a04850101${ctrlId}05");

      } else {
        Log3 $name, 1, "Cannot associate $name, missing controller id";
      }
    }
  }
  return undef;
}

###################################
sub
ZWave_Cmd($$@)
{
  my ($type, $hash, @a) = @_;
  return "no $type argument specified" if(int(@a) < 2);
  my $name = shift(@a);
  my $cmd  = shift(@a);


  # Collect the commands from the distinct classes
  my %cmdList;
  my $classes = AttrVal($name, "classes", "");
  foreach my $cl (split(" ", $classes)) {
    my $ptr = ZWave_getHash($hash, $cl, $type);
    next if(!$ptr);

    foreach my $k (keys %{$ptr}) {
      if(!$cmdList{$k}) {
        $cmdList{$k}{fmt} = $ptr->{$k};
        $cmdList{$k}{id}  = $zwave_class{$cl}{id};
      }
    }
  }

  if(!$cmdList{$cmd}) {
    my @list;
    foreach my $cmd (sort keys %cmdList) {
      if($zwave_cmdArgs{$type}{$cmd}) {
        push @list, "$cmd:$zwave_cmdArgs{$type}{$cmd}";
      } elsif($cmdList{$cmd}{fmt} !~ m/%/) {
        push @list, "$cmd:noArg";
      } else {
        push @list, $cmd;
      }
    }
    my $list = join(" ",@list);

    if($type eq "set") {
      unshift @a, $name, $cmd;
      return SetExtensions($hash, $list, @a);
    } else {
      return "Unknown argument $cmd, choose one of $list";
    }

  }

  Log3 $name, 2, "ZWave $type $name $cmd";

  ################################
  # ZW_SEND_DATA,nodeId,CMD,ACK|AUTO_ROUTE
  my $id = $hash->{id};
  my $cmdFmt = $cmdList{$cmd}{fmt};
  my $cmdId  = $cmdList{$cmd}{id};

  my $nArg = 0;
  if($cmdFmt =~ m/%/) {
    my @ca = split("%", $cmdFmt);
    $nArg = int(@ca)-1;
  }
  my $parTxt = ($nArg == 0 ? "no parameter" : 
               ($nArg == 1 ? "one parameter" : 
                             "$nArg parameters"));
  if($cmdFmt =~ m/^(.*)\*$/) {
    $cmdFmt = $1;
    return "$type $cmd needs at least $parTxt" if($nArg > int(@a));
    $cmdFmt .= ("%02x" x (int(@a)-$nArg));

  } else {
    return "$type $cmd needs $parTxt" if($nArg != int(@a));
  }

  if($cmd =~ m/^config/) {
    my ($err, $cmd) = ZWave_configCheckParam($hash, $type, $cmd, $cmdFmt, @a);
    return $err if($err);
    $cmdFmt = $cmd;
  } else {
    $cmdFmt = sprintf($cmdFmt, @a) if($nArg);
  }

  my ($baseClasses, $baseHash) = ($classes, $hash);
  if($id =~ m/(..)(..)/) {  # Multi-Channel, encapsulate
    my ($baseId,$ch) = ($1, $2);
    $id = $baseId;
    $cmdFmt = "0d01$ch$cmdId$cmdFmt";
    $cmdId = "60";  # MULTI_CHANNEL
    $baseHash = $modules{ZWave}{defptr}{"$hash->{homeId} $baseId"};
    $baseClasses = AttrVal($baseHash->{NAME}, "classes", "");
  }

  my $len = sprintf("%02x", length($cmdFmt)/2+1);

  my $data = "13$id$len$cmdId${cmdFmt}05"; # 13==SEND_DATA
  if($baseClasses =~ m/WAKE_UP/) {
    if(!$baseHash->{WakeUp}) {
      my @arr = ();
      $baseHash->{WakeUp} = \@arr;
    }
    my $awake = ($baseHash->{lastMsgTimestamp} &&
                  time() - $baseHash->{lastMsgTimestamp} < 2);

    if($awake && @{$baseHash->{WakeUp}} == 0) {
      push @{$baseHash->{WakeUp}}, ""; # Block the next

    } else {
      push @{$baseHash->{WakeUp}}, $data;
      return ($type eq "get" && AttrVal($name,"verbose",3) > 2 ? 
                  "Scheduled for sending after WAKEUP" : undef);
    }
  }
  IOWrite($hash, "00", $data);

  my $val;
  if($type eq "get") {
    no strict "refs";
    my $iohash = $hash->{IODev};
    my $fn = $modules{$iohash->{TYPE}}{ReadAnswerFn};
    my ($err, $data) = &{$fn}($iohash, $cmd, "^000400$id") if($fn);
    use strict "refs";

    return $err if($err);
    $val = ($data ? ZWave_Parse($iohash, $data, $type) : "no data returned");

  } else {
    $cmd .= " ".join(" ", @a) if(@a);

  }

  readingsSingleUpdate($hash, "state", $cmd, 1) if($type eq "set");
  return $val;
}

sub ZWave_Set($@) { return ZWave_Cmd("set", shift, @_); }
sub ZWave_Get($@) { return ZWave_Cmd("get", shift, @_); }

# returns supported Parameters by hrvStatus
sub
ZWave_HrvStatus($)
{
  my ($p) = @_;
  $p = hex($p);

  my @hrv_status = ( "outdoorTemperature", "supplyAirTemperature",
                     "exhaustAirTemperature", "dischargeAirTemperature",
                     "indoorTemperature", "indoorHumidity",
                     "remainingFilterLife" );
  my @l; 
  for(my $i=0; $i < 7; $i++) {
    push @l, "$i = $hrv_status[$i]" if($p & (1<<$i));
  }
  return join("\n", @l);
}

sub
ZWave_ParseMeter($$)
{
  my ($hash,$val) = @_;
  return if($val !~ m/^(..)(..)(.*)$/);
  my ($v1, $v2, $v3) = (hex($1) & 0x1f, hex($2), $3);
  my @prectab = (1,10,100,1000,10000,100000,1000000, 10000000);
  my $prec  = $prectab[($v2 >> 5) & 0x7];
  my $scale = ($v2 >> 3) & 0x3;
  my $size  = ($v2 >> 0) & 0x7;
  my @txt = ("undef", "energy", "gas", "water");
  my $txt = ($v1 > $#txt ? "undef" : $txt[$v1]);
  my %unit = (energy => ["kWh", "kVAh", "W", "pulseCount"],
              gas   => ["m3",  "feet3", "undef", "pulseCount"],
              water => ["m3",  "feet3", "USgallons", "pulseCount"]);
  my $unit = $txt eq "undef" ? "undef" : $unit{$txt}[$scale];
  $txt = "power" if ($unit eq "W");
  $v3 = hex(substr($v3, 0, 2*$size))/$prec;

  my $modelId = ReadingsVal($hash->{NAME}, "modelId", "");
  $modelId = $zwave_modelIdAlias{$modelId} if($zwave_modelIdAlias{$modelId});
  if($modelId eq "Philio_PAN04") {
    if($prec==100 && $scale==1 && $size==2) { $unit="A"; $txt="current" }
    if($prec== 10 && $scale==0 && $size==2) { $unit="V"; $txt="voltage" }
  }

  return "$txt:$v3 $unit";
}

sub
ZWave_ParseMultilevel($$$)
{
  my ($type,$fl,$arg) = @_; 
  my %ml_tbl = (
   '01' => { n => 'temperature',          st => ['C', 'F'] },
   '02' => { n => 'generalPurpose',       st => ['%', ''] },
   '03' => { n => 'luminance',            st => ['%', 'Lux'] },
   '04' => { n => 'power',                st => ['W', 'Btu/h'] },
   '05' => { n => 'humidity',             st => ['%'] },
   '06' => { n => 'velocity',             st => ['m/s', 'mph'] },
   '07' => { n => 'direction',            st => [] },
   '08' => { n => 'atmosphericPressure',  st => ['kPa', 'inchHg'] },
   '09' => { n => 'barometricPressure',   st => ['kPa', 'inchHg'] },
   '0a' => { n => 'solarRadiation',       st => ['W/m2'] },
   '0b' => { n => 'dewpoint',             st => ['C', 'F'] },
   '0c' => { n => 'rain',                 st => ['mm/h', 'in/h'] },
   '0d' => { n => 'tideLevel',            st => ['m', 'feet'] },
   '0e' => { n => 'weight',               st => ['kg', 'pound'] },
   '0f' => { n => 'voltage',              st => ['V', 'mV'] },
   '10' => { n => 'current',              st => ['A', 'mA'] },
   '11' => { n => 'CO2-level',            st => ['ppm']},
   '12' => { n => 'airFlow',              st => ['m3/h', 'cfm'] },
   '13' => { n => 'tankCapacity',         st => ['l', 'cbm', 'usgal'] },
   '14' => { n => 'distance',             st => ['m', 'cm', 'feet'] },
   '15' => { n => 'anglePosition',        st => ['%', 'relN', 'relS'] },
  );

  my $pr = (hex($fl)>>5)&0x07; # precision
  my $sc = (hex($fl)>>3)&0x03; # scale
  my $bc = (hex($fl)>>0)&0x07; # bytecount
  $arg = substr($arg, 0, 2*$bc);
  my $msb = (hex($arg)>>8*$bc-1); # most significant bit  ( 0 = pos, 1 = neg )
  my $val = $msb ? -( 2 ** (8 * $bc) - hex($arg) ) : hex($arg); # 2's complement   
  my $ml = $ml_tbl{$type};
  return "UNKNOWN multilevel type: $type fl: $fl arg: $arg" if(!$ml);
  return sprintf("%s:%.*f %s", $ml->{n}, $pr, $val/(10**$pr),
       int(@{$ml->{st}}) > $sc ? $ml->{st}->[$sc] : "");
}

sub
ZWave_SetClasses($$$$)
{
  my ($homeId, $id, $type6, $classes) = @_;

  my $def = $modules{ZWave}{defptr}{"$homeId $id"};
  if(!$def) {
    $type6 = $zw_type6{$type6} if($type6 && $zw_type6{$type6});
    $id = hex($id);
    return "UNDEFINED ZWave_${type6}_$id ZWave $homeId $id $classes"
  }

  my @classes;
  for my $classId (grep /../, split(/(..)/, lc($classes))) {
    push @classes, $zwave_id2class{lc($classId)} ? 
        $zwave_id2class{lc($classId)} : "UNKNOWN_".lc($classId);
  }
  my $name = $def->{NAME};
  $attr{$name}{classes} = join(" ", @classes) if(@classes);
  $def->{DEF} = "$homeId ".hex($id);
  return "";
}

sub
ZWave_ParseScene($)
{
  my ($p)=@_;
  my @arg = ("unknown", "on", "off", 
             "dim up start", "dim down start", "dim up end", "dim down end");
  return sprintf("sceneEvent%s:%s", int(hex($p)/10), $arg[hex($p)%10]);
} 


sub
ZWave_mcCapability($$)
{
  my ($hash, $caps) = @_;

  my $name = $hash->{NAME};
  my $iodev = $hash->{IODev};
  return "Missing IODev for $name" if(!$iodev);

  my $homeId = $iodev->{homeId};
  my @l = grep /../, split(/(..)/, lc($caps));
  my $chid = shift(@l);
  my $id = $hash->{id};

  my @classes;
  for my $classId (@l) {
    push @classes, $zwave_id2class{lc($classId)} ? 
        $zwave_id2class{lc($classId)} : "UNKNOWN_".uc($classId);
  }
  return "mcCapability_$chid:no classes" if(!@classes);

  if(!$modules{ZWave}{defptr}{"$homeId $id$chid"}) {
    my $lid = hex("$id$chid");
    my $lcaps = substr($caps, 2);
    $id = hex($id);
    DoTrigger("global",
              "UNDEFINED ZWave_$classes[0]_$id.$chid ZWave $homeId $lid $caps",
              1);
  }

  return "mcCapability_$chid:".join(" ", @classes);
}

sub
ZWave_mfsParse($$$$)
{
  my ($mf, $prod, $id, $config) = @_;
  my $xml = $attr{global}{modpath}.
            "/FHEM/lib/openzwave_manufacturer_specific.xml";
  ($mf, $prod, $id) = (lc($mf), lc($prod), lc($id)); # Just to make it sure
  if(open(FH, $xml)) {
    my ($lastMf, $mName, $ret) = ("","");
    while(my $l = <FH>) {
      if($l =~ m/<Manufacturer.*id="([^"]*)".*name="([^"]*)"/) {
        $lastMf = lc($1);
        $mName = $2;
        next;
      }

      if($l =~ m/<Product type="([^"]*)".*id="([^"]*)".*name="([^"]*)"/) {
        if($mf eq $lastMf && $prod eq lc($1) && $id eq lc($2)) {
          if($config) {
            $ret = "modelConfig:$1" if($l =~ m/config="([^"]*)"/);
            return $ret;
          } else {
            $ret = "model:$mName $3";
          }
          last;
        }
      }
    }
    close(FH);
    return $ret if($ret);

  } else {
    Log 1, "can't open $xml: $!";

  }
  return sprintf("model:0x%s 0x%s 0x%s", $mf, $prod, $id);
}

sub
ZWave_cleanString($$)
{
  my ($c, $postfix) = @_;
  $c =~ s/[^A-Z]+(.)/uc($1)/gei;
  $c =~ s/[^A-Z]//i;
  my $shortened=0;
  while(length($c) > 32) {     # might be endless loop
    $c =~ s/[A-Z][^A-Z]*$//;
    $shortened++;
  }
  $c .= $postfix if($shortened);
  return ($c, $shortened);;
}

###################################
# Poor mans XML-Parser
sub
ZWave_configParseModel($)
{
  my ($cfg) = @_;
  Log 3, "ZWave reading config for $cfg";
  my $fn = $attr{global}{modpath}."/FHEM/lib/openzwave_deviceconfig.xml.gz";
  my $gz = gzopen($fn, "rb");
  if(!$gz) {
    Log 3, "Can't open $fn: $!";
    return;
  }

  my ($line, $class, %hash, $cmdName);
  while($gz->gzreadline($line)) {       # Search the "file" entry
    last if($line =~ m/^<Product sourceFile="$cfg">$/);
  }

  while($gz->gzreadline($line)) {
    last if($line =~ m+^</Product>+);
    $class = $1 if($line =~ m/^<CommandClass.*id="([^"]*)"/);
    next if(!$class || $class ne "112");
    if($line =~ m/^<Value /) {
      my %h;
      $h{type}  = $1 if($line =~ m/type="([^"]*)"/i);
      $h{genre} = $1 if($line =~ m/genre="([^"]*)"/i); # config, user
      $h{label} = $1 if($line =~ m/label="([^"]*)"/i);
      $h{min}   = $1 if($line =~ m/min="([^"]*)"/i);
      $h{max}   = $1 if($line =~ m/max="([^"]*)"/i);
      $h{value} = $1 if($line =~ m/value="([^"]*)"/i);
      $h{index} = $1 if($line =~ m/index="([^"]*)"/i); # 1, 2, etc
      $h{read_only}  = $1 if($line =~ m/read_only="([^"]*)"/i); # true,false
      $h{write_only} = $1 if($line =~ m/write_only="([^"]*)"/i); # true,false
      my ($cmd,$shortened) = ZWave_cleanString($h{label}, $h{index});
      $cmdName = "config$cmd";
      $h{Help} = "";
      $h{Help} .= "Full text for $cmdName is $h{label}<br>" if($shortened);
      $hash{$cmdName} = \%h;
    }
    $hash{$cmdName}{Help} .= "$1<br>" if($line =~ m+^<Help>(.*)</Help>$+);
    if($line =~ m/^<Item/) {
      my $label = $1 if($line =~ m/label="([^"]*)"/i);
      my $value = $1 if($line =~ m/value="([^"]*)"/i);
      my ($item, $shortened) = ZWave_cleanString($label, $value);
      $hash{$cmdName}{Item}{$item} = $value;
      $hash{$cmdName}{Help} .= "Full text for $item is $label<br>"
        if($shortened);
    }
  }
  $gz->gzclose();

  my %mc = (set=>{}, get=>{}, config=>{});
  foreach my $cmd (keys %hash) {
    my $h = $hash{$cmd};
    my $arg = ($h->{type} eq "button" ? "a" : "a%b");
    $mc{set}{$cmd} = $arg if(!$h->{read_only} || $h->{read_only} ne "true");
    $mc{get}{$cmd} ="noArg" if(!$h->{write_only} || $h->{write_only} ne "true");
    $mc{config}{$cmd} = $h;
    $zwave_cmdArgs{set}{$cmd} = join(",", keys %{$h->{Item}}) if($h->{Item});
    $zwave_cmdArgs{set}{$cmd} = "noArg" if($h->{type} eq "button");
    $zwave_cmdArgs{get}{$cmd} = "noArg";
  }

  $zwave_modelConfig{$cfg} = \%mc;
}

###################################
sub
ZWave_configGetHash($)
{
  my ($hash) = @_;
  return undef if(!$hash);
  my $mc = ReadingsVal($hash->{NAME}, "modelConfig", "");
  ZWave_configParseModel($mc) if($mc && !$zwave_modelConfig{$mc});
  return $zwave_modelConfig{$mc};
}

sub
ZWave_configCheckParam($$$$@)
{
  my ($hash, $type, $cmd, $fmt, @arg) = @_;
  my $mc = ZWave_configGetHash($hash);
  return ("", sprintf($fmt, @arg)) if(!$mc);
  my $h = $mc->{config}{$cmd};
  return ("", sprintf($fmt, @arg)) if(!$h);

  return ("", sprintf("05%02x", $h->{index})) if($type eq "get");

  my $t = $h->{type};
  if($t eq "list") {
    my $v = $h->{Item}{$arg[0]};
    return ("Unknown parameter $arg[0] for $cmd, use one of ".
                join(",", keys %{$h->{Item}}), "") if(!defined($v));
    return ("", sprintf("04%02x01%02x", $h->{index}, $v));
  }
  if($t eq "button") {
    return ("", sprintf("04%02x01%02x", $h->{index}, $h->{value}));
  }

  return ("Parameter is not decimal", "") if($arg[0] !~ m/^[0-9]+$/);
  if($t eq "short") {
    return ("", sprintf("04%02x02%04x", $h->{index}, $arg[0]));
  }
  if($t eq "byte") {
    return ("", sprintf("04%02x01%02x", $h->{index}, $arg[0]));
  }
  return ("", sprintf("04%02x01%02x", $h->{index}, $arg[0]));
}

sub
ZWave_configParse($$$)
{
  my ($hash, $cmdId, $val) = @_;
  $val = hex($val);
  $cmdId = hex($cmdId);

  my $mc = ZWave_configGetHash($hash);
  return "config_$cmdId:$val" if(!$mc);
  my $h = $mc->{config};
  foreach my $cmd (keys %{$h}) {
    if($h->{$cmd}{index} == $cmdId) {
      my $hi = $h->{$cmd}{Item};
      if($hi) {
        foreach my $item (keys %{$hi}) {
          return "$cmd:$item" if($hi->{$item} == $val);
        }
      }
      return "$cmd:$val";
    }
  }
  return "config_$cmdId:$val";
}

sub
ZWave_getHash($$$)
{
  my ($hash, $cl, $type) = @_;

  my $ptr = $zwave_class{$cl}{$type}
      if($zwave_class{$cl} && $zwave_class{$cl}{$type});

  if($cl eq "CONFIGURATION" && $type ne "parse") {
    my $mc = ZWave_configGetHash($hash);
    if($mc) {
      my $mcp = $mc->{$type};
      my %nptr = ();
      map({$nptr{$_} = $ptr->{$_}} keys %{$ptr});
      map({$nptr{$_} = $mcp->{$_}} keys %{$mcp});
      $ptr = \%nptr;
    }
  }

  my $modelId = ReadingsVal($hash->{NAME}, "modelId", "");
  $modelId = $zwave_modelIdAlias{$modelId} if($zwave_modelIdAlias{$modelId});
  my $p = $zwave_deviceSpecial{$modelId};
  $ptr = $p->{$cl}{$type} if($p && $p->{$cl} && $p->{$cl}{$type});

  return $ptr;
}

###################################
# 0004000a03250300 (sensor binary off for id 11)
# { ZWave_Parse($defs{zd}, "0004000c028407", "") }
sub
ZWave_Parse($$@)
{
  my ($iodev, $msg, $srcCmd) = @_;
  my $homeId = $iodev->{homeId};
  my $ioName = $iodev->{NAME};
  if(!$homeId) {
    Log3 $ioName, 1, "ERROR: $ioName homeId is not set!"
        if(!$iodev->{errReported});
    $iodev->{errReported} = 1;
    return "";
  }
  if($msg =~ m/^01(..)(..*)/) { # 01==ANSWER
    my ($cmd, $arg) = ($1, $2);
    $cmd = $zw_func_id{$cmd} if($zw_func_id{$cmd});
    if($cmd eq "ZW_SEND_DATA") {
      Log3 $ioName, 2, "ERROR: cannot SEND_DATA: $arg" if($arg != 1);
      return "";
    }
    Log3 $ioName, 4, "$ioName: unhandled ANSWER: $cmd $arg";
    return "";
  }

  if($msg !~ m/^00(..)(..)(..)(.*)/) { # 00=REQUEST
    Log3 $ioName, 4, "$ioName: UNKNOWN msg $msg";
    return "";
  }

  my ($cmd, $callbackid, $id, $arg) = ($1, $2, $3, $4);
  $cmd = $zw_func_id{$cmd} if($zw_func_id{$cmd});

  #####################################
  # Controller commands
  my $evt;

  Log3 $ioName, 4, "$ioName CMD:$cmd ID:$id ARG:$arg";
  if($cmd eq 'ZW_ADD_NODE_TO_NETWORK' ||
     $cmd eq 'ZW_REMOVE_NODE_FROM_NETWORK') {
    my @vals = ("learnReady", "nodeFound", "slave",
                "controller", "", "done", "failed");
    $evt = ($id eq "00" || hex($id)>@vals+1) ? "unknownArg" : $vals[hex($id)-1];
    if($evt eq "slave" &&
       $arg =~ m/(..)....(..)..(.*)$/) {
      my ($id,$type6,$classes) = ($1, $2, $3);
      return ZWave_SetClasses($homeId, $id, $type6, $classes)
        if($cmd eq 'ZW_ADD_NODE_TO_NETWORK');
    }

  } elsif($cmd eq "ZW_APPLICATION_UPDATE" && $arg =~ m/....(..)..(.*)$/) {
    my ($type6,$classes) = ($1, $2);
    my $ret = ZWave_SetClasses($homeId, $id, $type6, $classes);

    my $hash = $modules{ZWave}{defptr}{"$homeId $id"};
    if($hash && $hash->{WakeUp} && @{$hash->{WakeUp}}) { # Always the base hash
      foreach my $wuCmd (@{$hash->{WakeUp}}) {
        IOWrite($hash, "00", $wuCmd);
        Log3 $hash, 4, "Sending stored command: $wuCmd";
      }
      @{$hash->{WakeUp}}=();
    }
 
    if(!$ret) {
      readingsSingleUpdate($hash, "CMD", $cmd, 1); # forum:20884
      return $hash->{NAME};
    }
    return $ret;

  } elsif($cmd eq "ZW_SEND_DATA") {
    if ($id eq "00") {
      ZWave_HandleSendStack($iodev);
      Log3 $ioName, 4,
        "$ioName OK: SEND_DATA returned $id - TRANSMIT_COMPLETE_OK";
    } else {
      my %err = { "01" => "NO_ACK",   "02" => "FAIL",
                  "03" => "NOT_IDLE", "04" => "NOROUTE" };
      my $msg = $err{$id} ? "TRANSMIT_COMPLETE_".$err{$id} : "UNKOWN_ERROR";
      Log3 $ioName, 2, "$ioName ERROR: SEND_DATA returned $id - $msg";
    }
    return "";

  } elsif($cmd eq "ZW_REQUEST_NODE_NEIGHBOR_UPDATE") {
    if ($id eq "21") {
      $evt = 'started';
    } elsif ($id eq "22") {
      $evt = 'done';
    } elsif ($id eq "23") {
      $evt = 'failed';
    } else {
      $evt = 'unknown'; # should never happen
    }

  }

  if($evt) {
    return "$cmd $evt" if($srcCmd);
    DoTrigger($ioName, "$cmd $evt");
    Log3 $ioName, 4, "$ioName $cmd $evt";
    return "";
  }


  ######################################
  # device messages
  if($cmd ne "APPLICATION_COMMAND_HANDLER") {
    Log3 $ioName, 4, "$ioName unhandled command $cmd";
    return "" 
  }


  my $baseHash;
  if($arg =~ /^..600d(..)(..)(.*)/) { # MULTI_CHANNEL CMD_ENCAP
    $baseHash = $modules{ZWave}{defptr}{"$homeId $id"};
    $id = "$id$1";
    $arg = sprintf("%02x$3", length($3)/2);
  }
  my $hash = $modules{ZWave}{defptr}{"$homeId $id"};
  $baseHash = $hash if(!$baseHash);


  if(!$hash) {
    $id = hex($id);
    Log3 $ioName, 3, "Unknown ZWave device $homeId $id, please define it";
    return "";
  }


  my $name = $hash->{NAME};
  my @event;
  my @args = ($arg); # MULTI_CMD handling

  while(@args) {
    $arg = shift(@args);

    return if($arg !~ m/^..(..)/);
    my $class = $1;

    my $className = $zwave_id2class{lc($class)} ?
                  $zwave_id2class{lc($class)} : "UNKNOWN_".uc($class);
    if($className eq "MULTI_CMD") {
       my ($ncmd, $off) = (0, 4);
       while(length($arg) > $off*2) {
         my $l = hex(substr($arg, $off*2, 2))+1;
         push @args, substr($arg, $off*2, $l*2);
         $off += $l;
       }
       next;
    }

    my $ptr = ZWave_getHash($hash, $className, "parse");
    if(!$ptr) {
      Log3 $hash, 4, "$name: Unknown message ($className $arg)";
      next;
    }

    foreach my $k (keys %{$ptr}) {
      if($arg =~ m/$k/) {
        my $val = $ptr->{$k};
        $val = eval $val if(index($val, '$') >= 0);
        push @event, $val;
      }
    }
    Log3 $hash, 4, "$name: $className $arg generated no event"
        if(!@event);
  }

  my $wu = $baseHash->{WakeUp};
  if($arg =~ m/028407/ && $wu && @{$wu}) {
    foreach my $wuCmd (@{$wu}) {
      IOWrite($hash, "00", $wuCmd);
      Log3 $hash, 4, "Sending stored command: $wuCmd";
    }
    @{$baseHash->{WakeUp}}=();
    #send a final wakeupNoMoreInformation
    my $nodeId = $baseHash->{id};
    IOWrite($hash, "00", "13${nodeId}02840805");
    Log3 $hash, 4, "Sending wakeupNoMoreInformation to node: $nodeId";
  }
  $baseHash->{lastMsgTimestamp} = time();

  return "" if(!@event);

  readingsBeginUpdate($hash);
  for(my $i = 0; $i < int(@event); $i++) {
    next if($event[$i] eq "");
    my ($vn, $vv) = split(":", $event[$i], 2);
    readingsBulkUpdate($hash, $vn, $vv);
    readingsBulkUpdate($hash, "reportedState", $vv)
        if($vn eq "state");     # different from set
  }
  readingsEndUpdate($hash, 1);

  return join("\n", @event) if($srcCmd);
  return $name;
}

#####################################
sub
ZWave_Undef($$)
{
  my ($hash, $arg) = @_;
  my $homeId = $hash->{homeId};
  my $id = $hash->{id};
  delete $modules{ZWave}{defptr}{"$homeId $id"};
  return undef;
}

#####################################
# Show the help from the device.xml, if the correct entry is selected
sub
ZWave_helpFn($$)
{
  my ($d,$cmd) = @_;
  my $mc = ZWave_configGetHash($defs{$d});
  return "" if(!$mc);
  my $h = $mc->{config}{$cmd};
  return "" if(!$h || !$h->{Help});
  return "Help for $cmd:<br>".$h->{Help};
}

sub
ZWave_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  return
  '<div id="ZWHelp" class="makeTable help"></div>'.
  '<script type="text/javascript">'.
   "var d='$d';" . <<'JSEND'
    $(document).ready(function() {
      $("div#ZWHelp").insertBefore("div.makeTable.wide:first"); // Move
      $("select.set,select.get").each(function(){
        $(this).get(0).setValueFn = function(val) {
          $("div#ZWHelp").html(val);
        }
        $(this).change(function(){
          FW_queryValue('{ZWave_helpFn("'+d+'","'+$(this).val()+'")}',
                        $(this).get(0));
        });
      });
    });
  </script>
JSEND
}

#####################################
# 2-byte signed hex
sub
s2Hex($)
{
  my ($p) = @_;
  $p = hex($p);
  return ($p > 32767 ? -(65536-$p) : $p);
}

1;

=pod
=begin html

<a name="ZWave"></a>
<h3>ZWave</h3>
<ul>
  This module is used to control ZWave devices via FHEM, see <a
  href="http://www.z-wave.com">www.z-wave.com</a> on details for this device family.
  This module is a client of the <a href="#ZWDongle">ZWDongle</a> module, which
  is directly attached to the controller via USB or TCP/IP.
  <br><br>
  <a name="ZWavedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ZWave &lt;homeId&gt; &lt;id&gt; [classes]</code>
  <br>
  <br>
  &lt;homeId&gt; is the homeId of the controller node, and id is the id of the
  slave node in the network of this controller.<br>
  classes is a hex-list of ZWave device classes. This argument is usually
  specified by autocreate when creating a device. If you wish to manually
  create a device, use the classes attribute instead, see below for details.
  Defining a ZWave device the first time is usually done by autocreate.
  <br>
  Example:
  <ul>
    <code>define lamp ZWave 00ce2074 9</code><br>
    <code>attr lamp classes SWITCH_BINARY BASIC MANUFACTURER_SPECIFIC VERSION
      SWITCH_ALL ASSOCIATION METER CONFIGURATION ALARM</code><br>
  </ul>
  </ul>
  <br>

  Note: the sets/gets/generated events of a gven node depend on the classes
  supported by this node. If a node supports 3 classes, then the union of
  these sets/gets/events will be available for this node.<br>
  Commands for battery operated nodes will be queues internally, and sent when
  the node sends a message. Answer to get commands appear then as events, the
  corresponding readings will be updated.
  <br><br>

  <a name="ZWaveset"></a>
  <b>Set</b>
  <ul>
  <br>
  <b>Note</b>: devices with on/off functionality support the <a
      href="#setExtensions"> set extensions</a>.

  <br><br><b>Class ASSOCIATION</b>
  <li>associationAdd groupId nodeId ...<br>
  Add the specified list of nodeIds to the assotion group groupId.<br> Note:
  upon creating a fhem-device for the first time fhem will automatically add
  the controller to the first association group of the node corresponding to
  the fhem device, i.e it issues a "set name associationAdd 1
  controllerNodeId"</li>

  <li>associationDel groupId nodeId ...<br>
  Remove the specified list of nodeIds from the assotion group groupId.</li>

  <br><br><b>Class BASIC</b>
  <li>basicValue value<br>
    Send value (0-255) to this device. The interpretation is device dependent,
    e.g. for a SWITCH_BINARY device 0 is off and anything else is on.</li>

  <br><br><b>Class CONFIGURATION</b>
  <li>configByte cfgAddress 8bitValue<br>
      configWord cfgAddress 16bitValue<br>
      configLong cfgAddress 32bitValue<br>
    Send a configuration value for the parameter cfgAddress. cfgAddress and
    value is node specific.<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config commands are available.</li>
  <li>configDefault cfgAddress<br>
    Reset the configuration parameter for the cfgAddress parameter to its
    default value.  See the device documentation to determine this value.</li>

  <br><br><b>Class INDICATOR</b>
  <li>indicatorOn<br>
    switch the indicator on</li>
  <li>indicatorOff<br>
    switch the indicator off</li>
  <li>indicatorDim value<br>
    takes values from 1 to 99.
    If the indicator does not support dimming. It is interpreted as on.</li>

  <br><br><b>Class MANUFACTURER_PROPRIETARY</b>
  <li>positionBlinds<br>
    drive blinds to position %</li>
  <li>positionSlat<br>
    drive slat to position %</li>

  <br><br><b>Class PROTECTION</b>
  <li>protectionOff<br>
    device is unprotected</li>
  <li>protectionOn<br>
    device is protected</li>
  <li>protectionSeq<br>
    device can be operated, if a certain sequence is keyed.</li>

  <br><br><b>Class SWITCH_ALL</b>
  <li>swaIncludeNone<br>
    the device does not react to swaOn and swaOff commands</li>
  <li>swaIncludeOff<br>
    the device reacts to the swaOff command
    but does not react to the swaOn command</li>
  <li>swaIncludeOn<br>
    the device reacts to the swaOn command
    but does not react to the swaOff command</li>
  <li>swaIncludeOnOff<br>
    the device reacts to the swaOn and swaOff commands</li>
  <li>swaOn<br>
    sends the all on command to the device</li>
  <li>swaOff<br>
    sends the all off command to the device.</li>

  <br><br><b>Class SWITCH_BINARY</b>
  <li>on<br>
    switch the device on</li>
  <li>off<br>
    switch the device off</li>
  <li>reportOn,reportOff<br>
    activate/deactivate the reporting of device state changes to the
    association group.</li>

  <br><br><b>Class SWITCH_MULTILEVEL</b>
  <li>on, off, reportOn, reportOff<br>
    the same as for SWITCH_BINARY.</li>
  <li>dim value<br>
    dim to the requested value (0..100)</li>

	
  <br><br><b>Class SCENE_ACTIVATION</b>
  <li>sceneConfig<br>
    activate settings for a specific scene.
	Parameters are: sceneId, dimmingDuration (00..ff)
    </li>
	
	
  <br><br><b>Class SCENE_ACTUATOR_CONF</b>
  <li>sceneConfig<br>
    set configuration for a specific scene.
	Parameters are: sceneId, dimmingDuration, finalValue (00..ff)
    </li>
	
  <br><br><b>Class SCENE_CONTROLLER_CONF</b>
  <li>groupConfig<br>
    set configuration for a specific scene.
	Parameters are: groupId, sceneId, dimmingDuration.
    </li>	
	
  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>tmOff</li>
  <li>tmCooling</li>
  <li>tmHeating</li>
  <li>tmManual<br>
    set the thermostat mode to off, cooling, heating or manual.
    </li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>setpointHeating value<br>
    set the thermostat to heat to the given value.
    The value is a whole number and read as celsius.
  </li>
  <li>setpointCooling value<br>
    set the thermostat to heat to the given value.
    The value is a whole number and read as celsius.
  </li>

  <br><br><b>Class WAKE_UP</b>
  <li>wakeupInterval value<br>
    Set the wakeup interval of battery operated devices to the given value in
    seconds. Upon wakeup the device sends a wakeup notification.</li>
  <li>wakeupNoMoreInformation<br>
    put a battery driven device into sleep mode. </li>

  </ul>
  <br>

  <a name="ZWaveget"></a>
  <b>Get</b>
  <ul>

  <br><br><b>Class ALARM</b>
  <li>alarm alarmId<br>
    return the value for alarmId. The value is device specific.
    </li>

  <br><br><b>Class ASSOCIATION</b>
  <li>association groupId<br>
    return the list of nodeIds in the association group groupId in the form:<br>
    assocGroup_X:Max Y, Nodes id,id...
    </li>

  <br><b>Class BASIC</b>
  <li>basicStatus<br>
    return the status of the node as basicReport:XY. The value (XY) depends on
    the node, e.g a SWITCH_BINARY device report 00 for off and FF (255) for on.
    </li>

  <br><br><b>Class BATTERY</b>
  <li>battery<br>
    return the charge of the battery in %, as battery:value % or battery:low
    </li>

  <br><br><b>Class CONFIGURATION</b>
  <li>config cfgAddress<br>
    return the value of the configuration parameter cfgAddress. The value is
    device specific.<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config commands are available.
    </li>

  <br><br><b>HRV_STATUS</b>
  <li>hrvStatus<br>
    report the current status (temperature, etc)
    </li>
  <li>hrvStatusSupported<br>
    report the supported status fields as a bitfield.
    </li>

  <br><br><b>Class INDICATOR</b>
  <li>indicatorStatus<br>
    return the indicator status of the node, as indState:on, indState:off or
    indState:dim value.
    </li>
  
  <br><br><b>Class MANUFACTURER_PROPRIETARY</b>
  <li>position<br>
    Fibaro FGRM-222: return the blinds position and slat angle.
    </li>

  <br><br><b>Class MANUFACTURER_SPECIFIC</b>
  <li>model<br>
    return the manufacturer specific id (16bit),
    the product type (16bit)
    and the product specific id (16bit).<br>
    Note: if the openzwave xml files are installed, then return the name of the
    manufacturer and of the product. This call is also necessary to decode more
    model specific configuration commands and parameters.
    </li>

  <br><br><b>Class METER</b>
  <li>meter<br>
    request the meter report.
    </li>
  <li>meterWatt<br>
    request the power report (Philio PHI_PAN04 only)
    </li>
  <li>meterVoltage<br>
    request the voltage report (Philio PHI_PAN04 only)
    </li>
  <li>meterAmpere<br>
    request the current report (Philio PHI_PAN04 only)
    </li>

  <br><br><b>Class MULTI_CHANNEL</b>
  <li>mcEndpoints<br>
    return the list of endpoints available, e.g.:<br>
    mcEndpoints: total 2, identical
    </li>
  <li>mcCapability chid<br>
    return the classes supported by the endpoint/channel chid. If the channel
    does not exists, create a FHEM node for it. Example:<br>
    mcCapability_02:SWITCH_BINARY<br>
    <b>Note:</b> This is the best way to create the secondary nodes of a
    MULTI_CHANNEL device. The device is only created for channel 2 or greater.
    </li>

  <br><br><b>Class PROTECTION</b>
  <li>protection<br>
    returns the protection state. It can be on, off or seq.</li>

  <br><br><b>Class SENSOR_ALARM</b>
  <li>alarm alarmType<br>
    return the nodes alarm status of the requested alarmType. 00 = GENERIC,
    01 = SMOKE, 02 = CO, 03 = CO2, 04 = HEAT, 05 = WATER, ff = returns the
    nodes first supported alarm type.    
    </li>

  <br><br><b>Class SENSOR_BINARY</b>
  <li>sbStatus<br>
    return the status of the node, as state:open or state:closed.
    </li>

  <br><br><b>Class SENSOR_MULTILEVEL</b>
  <li>smStatus<br>
    request data from the node (temperature/humidity/etc)
    </li>

  <br><br><b>Class SWITCH_ALL</b>
  <li>swaInclude<br>
    return the switch-all mode of the node.
    </li>

  <br><br><b>Class SWITCH_BINARY</b>
  <li>swbStatus<br>
    return the status of the node, as state:on or state:off.
    </li>

  <br><br><b>Class SWITCH_MULTILEVEL</b>
  <li>swmStatus<br>
    return the status of the node, as state:on, state:off or state:dim value.
    </li>
	
  <br><br><b>Class SCENE_ACTUATOR_CONF</b>
  <li>sceneConfig<br>
    returns the settings for a given scene. Parameter is sceneId
    </li>

  <br><br><b>Class SCENE_CONTROLLER_CONF</b>
  <li>groupConfig<br>
    returns the settings for a given group. Parameter is groupId
    </li>
	

  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>thermostatMode<br>
    request the mode
    </li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>setpoint<br>
    request the setpoint
    </li>

  <br><br><b>Class CLIMATE_CONTROL_SCHEDULE</b>
  <li>ccsOverride<br>
    request the climate control schedule override report
    </li>

  <br><br><b>Class VERSION</b>
  <li>version<br>
    return the version information of this node in the form:<br>
    Lib A Prot x.y App a.b
    </li>
  <li>versionClass classId<br>
     return the supported command version for the requested class
  </li>

  <br><br><b>Class WAKE_UP</b>
  <li>wakeupInterval<br>
    return the wakeup interval in seconds, in the form<br>
    wakeupReport:interval seconds target id
    </li>
  <li>wakeupIntervalCapabilities (only versionClass 2)<br>
    return the wake up interval capabilities in seconds, in the form<br>
    wakeupIntervalCapabilitiesReport:min seconds max seconds default seconds
    step seconds
  </li>


   <br><br><b>Class BASIC_WINDOW_COVERING</b>
  <li>coveringClose<br>
    Starts closing the window cover. Moving stops if blinds are fully colsed or
    a coveringStop command was issued. 
    </li>
  <li>coveringOpen<br>
    Starts opening the window cover.  Moving stops if blinds are fully open or
    a coveringStop command was issued. 
    </li>
  <li>coveringStop<br>
    Stop moving the window cover. Blinds are partially open (closed).
  </li>


  </ul>
  <br>

  <a name="ZWaveattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#classes">classes</a>
      This attribute is needed by the ZWave module, as the list of the possible
      set/get commands depends on it. It contains a space separated list of
      class names (capital letters).
      </li>
  </ul>
  <br>

  <a name="ZWaveevents"></a>
  <b>Generated events:</b>
  <ul>

  <br><br><b>Class ALARM</b>
  <li>alarm_type_X:level Y</li>

  <br><br><b>Class ASSOCIATION</b>
  <li>assocGroup_X:Max Y Nodes A,B,...</li>

  <br><b>Class BASIC</b>
  <li>basicReport:XY</li>

  <br><br><b>Class BATTERY</b>
  <li>battery:chargelevel %</li>

  <br><br><b>Class CLOCK</b>
  <li>clock:get</li>

  <br><br><b>Class CONFIGURATION</b>
  <li>config_X:Y<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config messages are available.</li>

  <br><br><b>Class HRV_STATUS</b>
  <li>outdoorTemperature: %0.1f C</li>
  <li>supplyAirTemperature: %0.1f C</li>
  <li>exhaustAirTemperature: %0.1f C</li>
  <li>dischargeAirTemperature: %0.1f C</li>
  <li>indoorTemperature: %0.1f C</li>
  <li>indoorHumidity: %s %</li>
  <li>remainingFilterLife: %s %</li>
  <li>supportedStatus: <list of supported stati></li>

  <br><br><b>Class INDICATOR</b>
  <li>indState:[on|off|dim value]</li>

  <br><br><b>Class MANUFACTURER_PROPRIETARY</b>
  <li>position:Blinds [%] Slat [%]</li>
  
  <br><br><b>Class MANUFACTURER_SPECIFIC</b>
  <li>modelId:hexValue hexValue hexValue</li>
  <li>model:manufacturerName productName</li>
  <li>modelConfig:configLocation</li>

  <br><br><b>Class METER</b>
  <li>energy:val [kWh|kVAh|pulseCount]</li>
  <li>gas:val [m3|feet3|pulseCount]</li>
  <li>water:val [m3|feet3|USgallons|pulseCount]</li>
  <li>power:val W</li>

  <br><br><b>Class MULTI_CHANNEL</b>
  <li>endpoints:total X $dynamic $identical</li>
  <li>mcCapability_X:class1 class2 ...</li>

  <br><br><b>Class PROTECTION</b>
  <li>protection:[on|off|seq]</li>

  <br><br><b>Class SENSOR_ALARM</b>
  <li>alarm_type_X:level Y node $nodeID seconds $seconds</li>

  <br><br><b>Class SENSOR_BINARY</b>
  <li>state:open</li>
  <li>state:closed</li>
  <li>motion:00|ff</li>
  <li>tamper:00|ff   </li>


  <br><br><b>Class SENSOR_MULTILEVEL</b>
  <li>temperature $val [C|F]</li>
  <li>generalPurpose $val %</li>
  <li>luminance $val [%|Lux]</li>
  <li>power $val [W|Btu/h]</li>
  <li>humidity $val %</li>
  <li>velocity $val [m/s|mph]</li>
  <li>direction $val</li>
  <li>atmosphericPressure $val [kPa|inchHg]</li>
  <li>barometricPressure $val [kPa|inchHg]</li>
  <li>solarRadiation $val W/m2</li>
  <li>dewpoint $val [C|F]</li>
  <li>rain $val [mm/h|in/h]</li>
  <li>tideLevel $val [m|feet]</li>
  <li>weight $val [kg|pound]</li>
  <li>voltage $val [V|mV]</li>
  <li>current $val [A|mA]</li>
  <li>CO2-level $val ppm</li>
  <li>airFlow $val [m3/h|cfm]</li>
  <li>tankCapacity $val [l|cbm|usgal]</li>
  <li>distance $val [m|cm|feet]</li>
  <li>anglePosition $val [%|relN|relS]</li>

  <br><br><b>Class SWITCH_ALL</b>
  <li>swa:[none|on|off|on off]</li>

  <br><br><b>Class SWITCH_BINARY</b>
  <li>state:on</li>
  <li>state:off</li>

  <br><br><b>Class SWITCH_MULTILEVEL</b>
  <li>state:on</li>
  <li>state:off</li>
  <li>state:dim value</li>
    
  <br><br><b>Class SCENE_ACTIVATION</b>
  <li>scene_Id:level finalValue</li>
    
  <br><br><b>Class SCENE_ACTUATOR_CONF</b>
  <li>scene_Id:level dimmingDuration finalValue</li>
  
  <br><br><b>Class SCENE_CONTROLLER_CONF</b>
  <li>group_Id:scene dimmingDuration</li>
 
 
  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>off</li>
  <li>cooling</li>
  <li>heating</li>
  <li>manual</li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>temperature:$temp [C|F] [heating|cooling]</li>

  <br><br><b>Class CLIMATE_CONTROL_SCHEDULE</b>
  <li>ccsOverride:[no|temporary|permanent], [frost protection|energy saving|unused]</li>

  <br><br><b>Class VERSION</b>
  <li>version:Lib A Prot x.y App a.b</li>
  <li>versionClass_$classId:$version</li>

  <br><br><b>Class WAKE_UP</b>
  <li>wakeup:notification</li>
  <li>wakeupReport:interval:X target:Y</li>
  <li>wakeupIntervalCapabilitiesReport:min W max X default Y step Z</li>

  </ul>
</ul>

=end html
=cut

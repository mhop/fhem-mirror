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
sub ZWave_SetClasses($$$$);

use vars qw(%zw_func_id);
use vars qw(%zw_type6);

my %zwave_id2class;
my %zwave_class = (
  NO_OPERATION             => { id => '00' },
  BASIC                    => { id => '20',
    set   => { basicValue  => "01%02x",
               basicSet    => "01%02x"  }, # Alias, Forum #38200
    get   => { basicStatus => "02",     }, 
    parse => { "..2001(.*)"=> '"basicSet:$1"', # Forum #36980
               "..2002"    => "basicGet:request", # sent by the remote
               "..2003(.*)"=> '"basicReport:$1"' }},
  CONTROLLER_REPLICATION   => { id => '21' },
  APPLICATION_STATUS       => { id => '22' },
  ZIP_SERVICES             => { id => '23' },
  ZIP_SERVER               => { id => '24' },
  SWITCH_BINARY            => { id => '25',
    set   => { off         => "0100",
               on          => "01FF" },
    get   => { swbStatus   => "02",       },
    parse => { "03250300"  => "state:off",
               "032503ff"  => "state:on", 
               "03250100"  => "state:setOff",
               "032501ff"  => "state:setOn"  } } ,
  SWITCH_MULTILEVEL        => { id => '26', 
    set   => { off         => "0100",
               on          => "01FF",
               dim         => "01%02x",
               stop        => "05" },
    get   => { swmStatus   => "02",     }, 
    parse => { "032603(.*)"=> '($1 eq "00" ? "state:off" : 
                               ($1 eq "ff" ? "state:on" : 
                                             "state:dim ".hex($1)))',
               "..260420"  => "state:swmBeginUp",
               "..260460"  => "state:swmBeginDown",
               "..2605"    => "state:swmEnd" } },
  SWITCH_ALL               => { id => '27',
    set   => { swaIncludeNone  => "0100",
               swaIncludeOff   => "0101",
               swaIncludeOn    => "0102",
               swaIncludeOnOff => "01ff",
               swaOn           => "04",
               swaOff          => "05" },
    get   => { swaInclude      => "02" },
    parse => { "03270300"      => "swa:none",
               "03270301"      => "swa:off",
               "03270302"      => "swa:on",
               "032703ff"      => "swa:on off" } },
  SWITCH_TOGGLE_BINARY     => { id => '28' },
  SWITCH_TOGGLE_MULTILEVEL => { id => '29' },
  CHIMNEY_FAN              => { id => '2a' },
  SCENE_ACTIVATION         => { id => '2b',
    set   => { sceneActivate => "01%02x%02x" }, 
    parse => { "042b01(..)(..)"  => '"scene_$1:$2"',
               "042b01(..)ff" => 'ZWave_sceneParse($1)'} },
  SCENE_ACTUATOR_CONF      => { id => '2c',
    set   => { sceneConfig => "01%02x%02x80%02x" },
    get   => { sceneConfig => "02%02x",          },
    parse => { "052c03(..)(..)(..)"   => '"scene_$1:level $2 duration $3"' } },
  SCENE_CONTROLLER_CONF    => { id => '2d',   
    set   => { sceneConfig => "01%02x%02x%02x" },
    get   => { sceneConfig => "02%02x",          },
    parse => { "052d03(..)(..)(..)"   => '"group_$1:scene $2 duration $3"' } },
  ZIP_CLIENT               => { id => '2e' },
  ZIP_ADV_SERVICES         => { id => '2f' },
  SENSOR_BINARY            => { id => '30', 
    get   => { sbStatus    => "02",       },
    parse => { "03300300"  => "state:closed",
               "033003ff"  => "state:open",
               "043003(..)(..)"=> 'ZWave_sensorbinaryV2Parse($1,$2)' } },
  SENSOR_MULTILEVEL        => { id => '31', 
    get   => { smStatus    => "04" },
    parse => { "..3105(..)(..)(.*)" => 'ZWave_multilevelParse($1,$2,$3)'} },
  METER                    => { id => '32',
    set   => { meterReset => "05" },
    get   => { meter       => 'Zwave_meterGet("%s")',
               meterSupported => "03" },
    parse => { "..3202(.*)" => 'ZWave_meterParse($hash, $1)',
               "..3204(.*)" => 'ZWave_meterSupportedParse($hash, $1)' } },
  COLOR_CONTROL            => { id => '33',
    get   => { ccCapabilityGet  => '01', # no more args
               ccStatus    => '03', # no more args
             },
    set   => { # Forum #36050
               rgb         => '050a0000010002%02x03%02x04%02x',
               wcrgb       => '050a00%02x01%02x02%02x03%02x04%02x' },
    parse => { "043302(.*)"=> 'ccCapabilityGetResponse:$1',
               "043304(.*)"=> 'ccStatusResponse:$1' } },
  ZIP_ADV_CLIENT           => { id => '34' },
  METER_PULSE              => { id => '35' },
  BASIC_TARIFF_INFO        => { id => '36' },
  HRV_STATUS               => { id => '37', 
    get   => { hrvStatus   => "01%02x",
               hrvStatusSupported => "03" },
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
            } },
  THERMOSTAT_HEATING       => { id => '38' },
  HRV_CONTROL              => { id => '39', 
    set   => { bypassOff => "0400",
               bypassOn  => "04FF",
               ventilationRate => "07%02x" },
    get   => { bypass          => "05", 
                ventilationRate => "08" },  
    parse => { "033906(..)"=> '($1 eq "00" ? "bypass:off" : '.
                              '($1 eq "ff" ? "bypass:on"  : '.
                                            '"bypass:dim ".hex($1)))',
               "033909(..)"=> 'sprintf("ventilationRate: %s",hex($1))' } },
  DCP_CONFIG               => { id => '3a' },
  DCP_MONITOR              => { id => '3b' },
  METER_TBL_CONFIG         => { id => '3c' },
  METER_TBL_MONITOR        => { id => '3d' },
  METER_TBL_PUSH           => { id => '3e' },
  PREPAYMENT               => { id => '3f' },
  THERMOSTAT_MODE          => { id => '40',
    set   => { tmOff       => "0100",
               tmHeating   => "0101",
               tmCooling   => "010b",
               tmManual    => "011f" },
    get   => { thermostatMode => "02" },
    parse => { "03400300"  => "state:off",
               "0340030b"  => "state:cooling",
               "03400301"  => "state:heating",
               "0340031f"  => "state:manual",
               "03400100"  => "state:setTmOff",
               "03400101"  => "state:setTmHeating",
               "0340010b"  => "state:setTmCooling",
               "0340011f"  => "state:setTmManual",
               } } ,
  PREPAYMENT_ENCAPSULATION => { id => '41' },
  THERMOSTAT_OPERATING_STATE=>{ id => '42' },
  THERMOSTAT_SETPOINT      => { id => '43',
    set   => { setpointHeating => "010101%02x",
               setpointCooling => "010201%02x"},
    get   => { setpoint => "02" },
    parse => { "064303(..)(..)(....)" => 'sprintf("setpointTemp:%0.1f %s %s", '.
                 'hex($3)/(10**int(hex($2)/32)), '.
                 'hex($2)&8 ? "F":"C", $1==1 ? "heating":"cooling")' } },
  THERMOSTAT_FAN_MODE      => { id => '44' },
  THERMOSTAT_FAN_STATE     => { id => '45' },
  CLIMATE_CONTROL_SCHEDULE => { id => '46',
    set   => { ccs                => 'ZWave_ccsSet("%s")' },
    get   => { ccs                => 'ZWave_ccsGet("%s")',
               ccsChanged         => "04",
               ccsOverride        => "07" },
    parse => { "..46(..)(.*)" => 'ZWave_ccsParse($1,$2)' }},
  THERMOSTAT_SETBACK       => { id => '47' },
  RATE_TBL_CONFIG          => { id => '48' },
  RATE_TBL_MONITOR         => { id => '49' },
  TARIFF_CONFIG            => { id => '4a' },
  TARIFF_TBL_MONITOR       => { id => '4b' },
  DOOR_LOCK_LOGGING        => { id => '4c' },
  NETWORK_MANAGEMANT_BASIC => { id => '4d' },
  SCHEDULE_ENTRY_LOCK      => { id => '4e' },
  ZI_6LOWPAN               => { id => '4f' },
  BASIC_WINDOW_COVERING    => { id => '50',
    set   => { coveringClose => "0140",
               coveringOpen => "0100",
               coveringStop => "02"  },
   parse => { "03500140"   => "covering:close",
              "03500100"   => "covering:open",
              "03500200"   => "covering:stop",
              "03500240"   => "covering:stop" } },
  MTP_WINDOW_COVERING      => { id => '51' },
  NETWORK_MANAGEMENT_PROXY => { id => '52' },
  NETWORK_SCHEDULE         => { id => '53' },
  NETWORK_MANAGEMENT_PRIMARY=>{ id => '54' },
  TRANSPORT_SERVICE        => { id => '55' },
  CRC_16_ENCAP             => { id => '56' }, # Parse is handled in the code
  APPLICATION_CAPABILITY   => { id => '57' },
  ZIP_ND                   => { id => '58' },
  ASSOCIATION_GRP_INFO     => { id => '59' },
  DEVICE_RESET_LOCALLY     => { id => '5a',
    parse => { "025a01"    => "deviceResetLocally:yes" } },
  CENTRAL_SCENE            => { id => '5b',
    parse => { "055b03..00(..)" => '"cSceneSet:".hex($1)',
               "055b03..02(..)" => '"cSceneDim:".hex($1)',
               "055b03..01(..)" => '"cSceneDimEnd:".hex($1)'}  },
  IP_ASSOCIATION           => { id => '5c' },
  ANTITHEFT                => { id => '5d' },
  ZWAVEPLUS_INFO           => { id => '5e',
    get   => { zwavePlusInfo=>"01"},
    parse => { "095e02(..)(..)(..)(....)(....)"
                                => 'ZWave_plusInfoParse($1,$2,$3,$4,$5)'} },
  ZIP_GATEWAY              => { id => '5f' },
  MULTI_CHANNEL            => { id => '60',  # Version 2, aka MULTI_INSTANCE
    get   => { mcEndpoints => "07",
               mcCapability=> "09%02x"},
    parse => { "^046008(..)(..)" => '"mcEndpoints:total ".hex($2).'.
                                 '(hex($1)&0x80 ? ", dynamic":"").'.
                                 '(hex($1)&0x40 ? ", identical":", different")',
               "^..600a(.*)"=> 'ZWave_mcCapability($hash, $1)' } },
  ZIP_PORTAL               => { id => '61' },
  DOOR_LOCK                => { id => '62' },
  USER_CODE                => { id => '63',
    set   => { userCode => 'ZWave_userCodeSet("%s")' },
    get   => { userCode => "02%02x" },
    parse => { "^..6303(..)(..)(.*)" =>
                'sprintf("userCode:id %d status %d code %s", $1, $2, $3)' }
    },
  APPLIANCE                => { id => '64' },
  DMX                      => { id => '65' },
  BARRIER_OPERATOR         => { id => '66' },
  CONFIGURATION            => { id => '70', 
    set   => { configDefault=>"04%02x80",
               configByte  => "04%02x01%02x",
               configWord  => "04%02x02%04x",
               configLong  => "04%02x04%08x" },
    get   => { config      => "05%02x" },
    parse => { "^..70..(..)(..)(.*)" => 'ZWave_configParse($hash,$1,$2,$3)'} },
  ALARM                    => { id => '71', 
    get   => { alarm       => "04%02x" },
    parse => { "..7105(..)(..)(.*)" => 'ZWave_alarmParse($1,$2,$3)'} },
  MANUFACTURER_SPECIFIC    => { id => '72',
    get   => { model       => "04" },
    parse => { "087205(....)(....)(....)" =>'ZWave_mfsParse($hash,$1,$2,$3,0)',
               "087205(....)(....)(.{4})" =>'ZWave_mfsParse($hash,$1,$2,$3,1)',
               "087205(....)(.{4})(.{4})" =>'ZWave_mfsParse($hash,$1,$2,$3,2)'},
    init  => { ORDER=>49, CMD => '"get $NAME model"' } },
  POWERLEVEL               => { id => '73',
    set   => { powerlevel     => "01%02x%02x",
               powerlevelTest => "04%02x%02x%04x" },
    get   => { powerlevel     => "02",
               powerlevelTest => "05" },
    parse => { "047303(..)(..)" => 
                   '"powerlvl:current ".hex($1)." remain ".hex($2)',
               "067306(..)(..)(....)" =>
                   '"powerlvlTest:node ".hex($1)." status ".hex($2).
                    " frameAck ".hex($3)',} },
  PROTECTION               => { id => '75',
    set   => { protectionOff => "0100",
               protectionSeq => "0101",
               protectionOn  => "0102",
               protectionBytes  => "01%02x%02x" },
    get   => { protection    => "02" },
    parse => { "03750300"    => "protection:off",
               "03750301"    => "protection:seq",
               "03750302"    => "protection:on",
               "047503(..)(..)"  => 'ZWave_protectionParse($1, $2)'} },
  LOCK                     => { id => '76' },
  NODE_NAMING              => { id => '77',
    set   => { name     => '(undef, "0100".unpack("H*", "%s"))',
               location => '(undef, "0400".unpack("H*", "%s"))' },
    get   => { name     => '02',
               location => '05' },
    parse => { '..770300(.*)' => '"name:".pack("H*", $1)',
               '..770600(.*)' => '"location:".pack("H*", $1)' } },
  FIRMWARE_UPDATE_MD       => { id => '7a' },
  GROUPING_NAME            => { id => '7b' },
  REMOTE_ASSOCIATION_ACTIVATE=>{id => '7c' },
  REMOTE_ASSOCIATION       => { id => '7d' },
  BATTERY                  => { id => '80',
    get   => { battery     => "02" },
    parse => { "038003(..)"=> '"battery:".($1 eq "ff" ? "low":hex($1)." %")'} },
  CLOCK                    => { id => '81',
    get   => { clock           => "05" },
    set   => { clock           => 'ZWave_clockSet()' },
    parse => { "028105"        => "clock:get",
               "048106(..)(..)"=> 'ZWave_clockParse($1,$2)' }},
  HAIL                     => { id => '82',
    parse => { "028201"    => "hail:01"}},
  WAKE_UP                  => { id => '84', 
    set   => { wakeupInterval => "04%06x%02x",
               wakeupNoMoreInformation => "08" },
    get   => { wakeupInterval => "05", 
               wakeupIntervalCapabilities => "09" },
    parse => { "028407"    => 'wakeup:notification',
               "..8406(......)(..)" =>
                         '"wakeupReport:interval ".hex($1)." target ".hex($2)',
               "..840a(......)(......)(......)(......)" =>
                         '"wakeupIntervalCapabilitiesReport:min ".hex($1).'.
                         '" max ".hex($2)." default ".hex($3)." step ".hex($4)'
             } },
  ASSOCIATION              => { id => '85', 
    set   => { associationAdd => "01%02x%02x*",
               associationDel => "04%02x%02x*" },
    get   => { association => "02%02x",      },
    parse => { "..8503(..)(..)..(.*)" => '"assocGroup_$1:Max $2 Nodes $3"'},
    init  => { ORDER=>10, CMD=> '"set $NAME associationAdd 1 $CTRLID"' } },
  VERSION                  => { id => '86',
    get   => { version      => "11",
               versionClass => "13%02x" },
    parse => { "078612(..........)" => 'sprintf("version:Lib %d Prot '.
                '%d.%d App %d.%d", unpack("C*",pack("H*","$1")))',
               "098612(..............)" => 'sprintf("version:Lib %d Prot '.
                 '%d.%d App %d.%d HW %d FWCounter %d",'.
                 'unpack("C*",pack("H*","$1")))',
               "0b8612(..................)" => 'sprintf("version:Lib %d Prot '.
                 '%d.%d App %d.%d HW %d FWCounter %d FW %d.%d",'.
                 'unpack("C*",pack("H*","$1")))',
               "048614(..)(..)"             => '"versionClass_$1:$2"' } },
  INDICATOR                => { id => '87',
    set   => { indicatorOff    => "0100",
               indicatorOn     => "01FF",
               indicatorDim    => "01%02x" },
    get   => { indicatorStatus => "02",     }, 
    parse => { "038703(..)"    => '($1 eq "00" ? "indState:off" : 
                               ($1 eq "ff" ? "indState:on" : 
                                             "indState:dim ".hex($1)))'} },
  PROPRIETARY              => { id => '88' },
  LANGUAGE                 => { id => '89' },
  TIME                     => { id => '8a' },
  TIME_PARAMETERS          => { id => '8b' },
  GEOGRAPHIC_LOCATION      => { id => '8c' },
  COMPOSITE                => { id => '8d' },
  MULTI_CHANNEL_ASSOCIATION=> { id => '8e',    # aka MULTI_INSTANCE_ASSOCIATION
    set   => { mcaAdd      => "01%02x%02x*",
               mcaDel      => "04%02x*" },
    get   => { mca         => "02%02x",
               mcaGroupings=> "05" },
    parse => { "..8e03(..)(..)(.*)"
                           => '"mca_$1:max:$2 param:$3"',
               "..8e06(.*)"=> '"mcaSupportedGroupings:".hex($1)' } },
                                
  MULTI_CMD                => { id => '8f' }, # Handled in Parse
  ENERGY_PRODUCTION        => { id => '90' },
  MANUFACTURER_PROPRIETARY => { id => '91' }, # see also zwave_deviceSpecial
  SCREEN_MD                => { id => '92' },
  SCREEN_ATTRIBUTES        => { id => '93' },
  SIMPLE_AV_CONTROL        => { id => '94' },
  AV_CONTENT_DIRECTORY_MD  => { id => '95' },
  AV_RENDERER_STATUS       => { id => '96' },
  AV_CONTENT_SEARCH_MD     => { id => '97' },
  SECURITY                 => { id => '98',
    set   => { "secKey"    => '(undef, "06%s")',
               "secScheme" => "0400",
               "secNonce"  => "40" },
    get   => { "secSupported" => "02" },
    parse => { "..9803(.*)" => '"secSupported:$1"',
               "..9805(.*)" => 'ZWave_secureInit($hash, $1)', # secScheme
               "..9880(.*)" => 'ZWave_secureInit($hash, $1)' } },
  AV_TAGGING_MD            => { id => '99' },
  IP_CONFIGURATION         => { id => '9a' },
  ASSOCIATION_COMMAND_CONFIGURATION
                           => { id => '9b' },
  SENSOR_ALARM             => { id => '9c',
    get   => { alarm       => "01%02x" },
    parse => { "..9c02(..)(..)(..)(....)" =>
                '"alarm_type_$2:level $3 node $1 seconds ".hex($4)'} },  
  SILENCE_ALARM            => { id => '9d' },
  SENSOR_CONFIGURATION     => { id => '9e' },
  MARK                     => { id => 'ef' },
  NON_INTEROPERABLE        => { id => 'f0' },
);

my %zwave_cmdArgs = (
  set => {
    dim          => "slider,0,1,99",
    indicatorDim => "slider,0,1,99",
    rgb          => "colorpicker,RGB",
  },
  get => {
  },
  parse => {
  }
);

my %zwave_modelConfig;
my %zwave_modelIdAlias = ( "010f-0301-1001" => "Fibaro_FGRM222",
                           "0115-0100-0102" => "ZME_KFOB" );

# Patching certain devices.
use vars qw(%zwave_deviceSpecial);
%zwave_deviceSpecial = (
   Fibaro_FGRM222 => {
     MANUFACTURER_PROPRIETARY => {
      set   => { positionSlat=>"010f26010100%02x", 
                 positionBlinds=>"010f260102%02x00"},
      get   => { position=>"010f2602020000", },
      parse => { "0891010f260303(..)(..)" =>
                  'sprintf("position:Blinds %d Slat %d",hex($1),hex($2))',
                 "0891010f260302(..)00" =>'"position:".hex($1)' } } },
   ZME_KFOB => {
     ZWAVEPLUS_INFO => {
      # Example only. ORDER must be >= 50
      init => { ORDER=>50, CMD => '"get $NAME zwavePlusInfo"' } } }
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

  if(@a) {      # Autocreate: set the classes, execute the init calls
    $hash->{lastMsgTimestamp} = time(); # device is awake.
    ZWave_SetClasses($homeId, $id, undef, $a[0]);
  }
  return undef;
}

sub
ZWave_initFromModelfile($$)
{
  my ($name, $ctrlId) = @_;
  my @res;
  my $cfg = ReadingsVal($name, "modelConfig", "");
  return @res if(!$cfg);
  ZWave_configParseModel($cfg) if(!$zwave_modelConfig{$cfg});
  my $mc = $zwave_modelConfig{$cfg};
  return @res if(!$mc);
  for my $grp (keys %{$mc->{group}}) {
    next if($grp eq '1');
    next if($mc->{group}{$grp} !~ m/auto="true"/);
    push @res, "set $name associationAdd $grp $ctrlId";
  }
  return @res;
}

sub
ZWave_doExecInits($)
{
  my ($param) = @_;
  my $cmdArr = $param->{cmdArr};

  my $cmd = shift @{$cmdArr};
  my $ret = AnalyzeCommand(undef, $cmd);
  Log 1, "ZWAVE INIT: $cmd: $ret" if ($ret);

  push(@{$cmdArr}, ZWave_initFromModelfile($1, $param->{ctrlId}))
                if($cmd =~ m/^get (.*) model$/);

  InternalTimer(gettimeofday()+0.5, "ZWave_doExecInits", $param, 0)
    if(@{$cmdArr});
}

sub
ZWave_execInits($$)
{
  my ($hash, $min) = @_;  # min = 50 for model-specific stuff
  my @clList = split(" ", $attr{$hash->{NAME}}{classes});
  my (@initList, %seen);

  foreach my $cl (@clList) {
    next if($seen{$cl});
    $seen{$cl} = 1;
    my $ptr = ZWave_getHash($hash, $cl, "init");
    push @initList, $ptr if($ptr && $ptr->{ORDER} >= $min);
  }

  my $NAME = $hash->{NAME};
  my $iodev = $hash->{IODev};
  my $homeReading = ReadingsVal($iodev->{NAME}, "homeId", "") if($iodev);
  my $CTRLID = $1 if($homeReading && $homeReading =~ m/CtrlNodeId:(..)/);

  my @cmd;
  foreach my $i (sort { $a->{ORDER}<=>$b->{ORDER} } @initList) {
    push @cmd, eval $i->{CMD};
  }

  InternalTimer(gettimeofday()+0.5, "ZWave_doExecInits",
        { cmdArr=>\@cmd, ctrlId=>$CTRLID }, 0) if(@cmd);
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

  my $id = $hash->{id};
  my $isMc = ($id =~ m/(....)/);
  if($type eq "set" && !$isMc) {
    $cmdList{neighborUpdate}{fmt} = "48$id";
    $cmdList{neighborUpdate}{id} = "";
  }

  if($type eq "set" && $cmd eq "rgb") {
     if($a[0] && $a[0] =~ m/^[0-9A-F]+$/i && $a[0] =~ /^(..)(..)(..)$/) {
       @a = (hex($1), hex($2), hex($3));
     } else {
       return "set rgb: a 6-digit hex number is required";
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

  ################################
  # ZW_SEND_DATA,nodeId,CMD,ACK|AUTO_ROUTE
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

  } elsif($cmdFmt =~ m/%s/) {   # vararg for functions
    $nArg = 0 if(!@a);
    @a = (join(" ", @a));

  } else {
    return "$type $cmd needs $parTxt" if($nArg != int(@a));
  }

  if($cmdFmt !~ m/%s/ && $cmd !~ m/^config/) {
    for(my $i1 = 0; $i1<int(@a); $i1++) {
      return "Error: $a[$i1] is not a decimal number"
        if($a[$i1] !~ m/^[-\d]+$/);
    }
  }

  if($cmd =~ m/^config/) {
    my ($err, $cmd) = ZWave_configCheckParam($hash, $type, $cmd, $cmdFmt, @a);
    return $err if($err);
    $cmdFmt = $cmd;
  } else {
    $cmdFmt = sprintf($cmdFmt, @a) if($nArg);
    my ($err, $ncmd) = eval($cmdFmt) if($cmdFmt !~ m/^\d/);
    return $err if($err);
    $cmdFmt = $ncmd if(defined($ncmd));
  }

  Log3 $name, 2, "ZWave $type $name $cmd";

  my ($baseClasses, $baseHash) = ($classes, $hash);
  if($id =~ m/(..)(..)/) {  # Multi-Channel, encapsulate
    my ($baseId,$ch) = ($1, $2);
    $id = $baseId;
    $cmdFmt = "0d01$ch$cmdId$cmdFmt";
    $cmdId = "60";  # MULTI_CHANNEL
    $baseHash = $modules{ZWave}{defptr}{"$hash->{homeId} $baseId"};
    $baseClasses = AttrVal($baseHash->{NAME}, "classes", "");
  }


  my $data;
  if($cmd eq "neighborUpdate") {
    $data = $cmdFmt;

  } else {
    my $len = sprintf("%02x", length($cmdFmt)/2+1);
    $data = "13$id$len$cmdId${cmdFmt}05"; # 13==SEND_DATA, 05=AUTO_ROUTE+ACK

  }

  if($baseClasses =~ m/WAKE_UP/) {
    if(!$baseHash->{WakeUp}) {
      my @arr = ();
      $baseHash->{WakeUp} = \@arr;
    }
    my $awake = ($baseHash->{lastMsgTimestamp} &&
                  time() - $baseHash->{lastMsgTimestamp} < 3);

    if(!$awake) {
      push @{$baseHash->{WakeUp}}, $data.$id;
      return (AttrVal($name,"verbose",3) > 2 ?
                  "Scheduled for sending after WAKEUP" : undef);
    }

  } else {
    $data .= $id; # callback=>id

  }
  IOWrite($hash, "00", $data);

  my $val;
  if($type eq "get") {
    no strict "refs";
    my $iohash = $hash->{IODev};
    my $fn = $modules{$iohash->{TYPE}}{ReadAnswerFn};
    my ($err, $data) = &{$fn}($iohash, $cmd, "^000400${id}..$cmdId") if($fn);
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

my %zwm_unit = (
  energy=> ["kWh", "kVAh", "W", "pulseCount", "V", "A", "PowerFactor"],
  gas   => ["m3", "feet3", "undef", "pulseCount"],
  water => ["m3", "feet3", "USgallons", "pulseCount"]
);

sub
ZWave_meterParse($$)
{
  my ($hash,$val) = @_;
  return if($val !~ m/^(..)(..)(.*)$/);
  my ($v1, $v2, $v3) = (hex($1), hex($2), $3);
  
  my $name = $hash->{NAME};

  # rate_type currently not used / not reported
  my $rate_type = ($v1 >> 5) & 0x3;
  my @rate_type_text =("undef","consumed", "produced");
  my $rate_type_text = ($rate_type > $#rate_type_text ? 
                        "undef" : $rate_type_text[$rate_type]);

  my $meter_type = ($v1 & 0x1f);
  my @meter_type_text =("undef", "energy", "gas", "water", "undef");
  my $meter_type_text = ($meter_type > $#meter_type_text ? 
                        "undef" : $meter_type_text[$meter_type]); 
    
  my $precision = ($v2 >>5) & 0x7;
  # no definition for text or numbers, used as -> (10 ** hex($precision))

  # V3 use 3 bit, in V2 there are only 2 bit available
  # V3 use bit 7 of first byte as bit 3 of scale
  my $scale = ($v2 >> 3) & 0x3;
  $scale |= (($v1 & 0x80) >> 5);
  
  my $unit_text = ($meter_type_text eq "undef" ? 
                        "undef" : $zwm_unit{$meter_type_text}[$scale]);
  
  my $size = $v2 & 0x7; 

  $meter_type_text = "power" if ($unit_text eq "W");
  $meter_type_text = "voltage" if ($unit_text eq "V");
  $meter_type_text = "current" if ($unit_text eq "A");
  
  my $mv = hex(substr($v3, 0, 2*$size));
  $mv = $mv / (10 ** $precision);
  $mv -= (2 ** ($size*8)) if $mv >= (2 ** ($size*8-1));
  $v3 = substr($v3, 2*$size, length($v3)-(2*$size));

  if (length($v3) < 4) { # V1 report
    return "$meter_type_text: $mv $unit_text";  

  } else { # V2 or greater report
    my $delta_time = hex(substr($v3, 0, 4));
    $v3 = substr($v3, 4, length($v3)-4);
    
    if ($delta_time == 0) { # no previous meter value
      return "$meter_type_text: $mv $unit_text";

    } else { # previous meter value present
      my $pmv = hex(substr($v3, 0, 2*$size));
      $pmv = $pmv / (10 ** $precision);
      $pmv -= (2 ** ($size*8)) if $pmv >= (2 ** ($size*8-1));

      if ($delta_time == 65535) {
        $delta_time = "unknown";
      } else {
        $delta_time .= " s";
      };
      return "$meter_type_text: $mv $unit_text previous: $pmv delta_time: ".
                "$delta_time"; # V2 report
    };
  };
}


sub
Zwave_meterGet($)
{
  my ($scale) = @_;
   
  if ($scale eq "%s") { # no parameter specified, use V1 get without scale
    return("", "01");
  };
  
  if (($scale < 0) || ($scale > 6)) {
    return("argument must be one of: 0 to 6","");
  } else {
    $scale = $scale << 3;
    #~ Log 1, "cmd" .sprintf('01%02x', $scale);
    return("",sprintf('01%02x', $scale));
  };

}


sub
ZWave_meterSupportedParse($$)
{
  my ($hash,$val) = @_;
  return if($val !~ m/^(..)(..)$/);
  my ($v1, $v2) = (hex($1), hex($2));
  
  my $name = $hash->{NAME};
  
  my $meter_reset = $v1 & 0x80;
  my $meter_reset_text = $meter_reset ? "yes" : "no";

  my $meter_type = ($v1 & 0x1f);
  my @meter_type_text =("undef", "energy", "gas", "water", "undef");
  my $meter_type_text = ($meter_type > $#meter_type_text ? 
                            "undef" : $meter_type_text[$meter_type]); 
 
  my $scale = $v2 & 0x7f;
  my $unit_text="";
 
  for (my $i=0; $i <= 6; $i++) {
    if ($scale & 2**$i) {
        $unit_text .= ", " if (length($unit_text)>0);
        $unit_text .= $i.":".$zwm_unit{$meter_type_text}[$i];
    };
  };
  
  return "meterSupported: type: $meter_type_text scales: $unit_text resetable:".
            " $meter_reset_text";
}

sub
ZWave_multilevelParse($$$)
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
  $attr{$name}{classes} = join(" ", @classes)
        if(@classes && !$attr{$name}{classes});
  $def->{DEF} = "$homeId ".hex($id);
  return "";
}

sub
ZWave_sceneParse($)
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
ZWave_mfsAddClasses($$)
{
  my ($hash, $cfgFile) = @_;
  my $name = $hash->{NAME};
  my $attr = $attr{$name}{classes};
  return if(!$cfgFile || !$attr);
  my $changed;

  ZWave_configParseModel($cfgFile);
  my $ci = $zwave_modelConfig{$cfgFile}{classInfo};
  foreach my $id (keys %{$ci}) {
    my $v = $ci->{$id};
    if($v =~ m/setasreport="true"/ || $v =~ m/action="add"/) {
      $id = sprintf("%02x", $id);
      my $cn = $zwave_id2class{$id};
      next if($attr =~ m/$cn/);
      $attr .= " $cn";
      $changed = 1;
    }
  }
  return if(!$changed);
  addStructChange("attr", $name, "$name classes $attr");
  $attr{$name}{classes} = $attr;
}

sub
ZWave_mfsParse($$$$$)
{
  my ($hash, $mf, $prod, $id, $config) = @_;

  if($config == 2) {
    setReadingsVal($hash, "modelId", "$mf-$prod-$id", TimeNow());
    ZWave_execInits($hash, 50);
    return "modelId:$mf-$prod-$id";
  }

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
            $ret = "modelConfig:".(($l =~ m/config="([^"]*)"/) ? $1:"unknown");
            ZWave_mfsAddClasses($hash, $1);
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

my @zwave_wd = ("none","mon","tue","wed","thu","fri","sat","sun");

sub
ZWave_ccsSet($)
{
  my ($spec) = @_;
  my @arg = split(/[ ,]/, $spec);
  my $usage = "wrong arg, need: <weekday> HH:MM relTemp HH:MM relTemp ...";

  return ($usage,"") if(@arg < 3 || int(@arg) > 19 || (int(@arg)-1)%2 != 0);
  my $wds = shift(@arg);
  my $ret;
  map { $ret=sprintf("%02x",$_) if($zwave_wd[$_] eq $wds) }(1..int($#zwave_wd));
  return ("Unknown weekday $wds, use one of ".join(" ", @zwave_wd), "")
    if(!defined($ret));
  for(my $i=0; $i<@arg; $i+=2) {
    return ($usage, "") if($arg[$i] !~ m/^(\d+):(\d\d)$/);
    $ret .= sprintf("%02x%02x", $1, $2);
    return ($usage, "") if($arg[$i+1] !~ m/^([-.\d]+)$/ || $1 < -12 || $1 > 12);
    $ret .= sprintf("%02x", $1 < 0 ? (255+$1*10) : ($1*10));
  }
  for(my $i=@arg; $i<18; $i+=2) {
    $ret .= "00007f";
  }
  return ("", "01$ret");
}

sub
ZWave_ccsGet($)
{
  my ($wds, $wdn) = @_;
  $wds = "" if($wds eq "%s");  # No parameter specified
  map { $wdn = $_ if($zwave_wd[$_] eq $wds) } (1..int($#zwave_wd));
  return ("Unknown weekday $wds, use one of ".join(" ", @zwave_wd), "")
    if(!$wdn);
  return ("", sprintf("02%02x", $wdn));
}

sub
ZWave_ccsParse($$)
{
  my ($t, $p) = @_;

  return "ccsChanged:$p" if($t == "05");

  if($t == "08" && $p =~ m/^(..)(..)$/) {
    my $ret = ($1 eq "00" ? "no" : ($1 eq "01" ? "temporary" : "permanent"));
    $ret .= ", ". ($2 eq "79" ? "frost protection" : 
                  ($2 eq "7a" ? "energy saving" : "unused"));
    return "ccsOverride:$ret";
  }

  if($t == "03") {
    $p =~ /^(..)(.*$)/;
    my $n = "ccs_".$zwave_wd[hex($1)];
    $p = $2;
    my @v;
    while($p =~ m/^(..)(..)(..)(.*)$/) {
      last if($3 eq "7f"); # unused
      $p = $4;
      my $t = hex($3);
      $t = ($t == 0x7a ? "energySave" : $t >= 0x80 ? -(255-$t)/10 : $t/10);
      push @v, sprintf("%02d:%02d %0.1f", hex($1), hex($2), $t);
    }
    return "$n:".(@v ? join(" ",@v) : "N/A");
  }

  return "ccs: UNKNOWN $t$p";
}

sub
ZWave_userCodeSet($)
{
  my ($spec) = @_;
  my @arg = split(" ", $spec);
  return ("wrong arg, need: id status usercode","") 
                        if(@arg != 3 || $spec !~ m/^[A-F0-9 ]*$/i);
  return ("", sprintf("01%02x%02x%s", $arg[0],$arg[1],$arg[2]));
}

sub
ZWave_clockAdjust($)
{
  my $d = shift;
  return $d if($d !~ m/^13(..)048104....05$/);
  my ($err, $nd) = ZWave_clockSet();
  return "13${1}0481${nd}05";
}

sub
ZWave_clockSet()
{
  my @l = localtime();
  return ("", sprintf("04%02x%02x", ($l[6]<<5)|$l[2], $l[1]));
}

sub
ZWave_clockParse($$)
{
  my ($p1,$p2) = @_;
  $p1 = hex($p1); $p2 = hex($p2);
  return sprintf("clock:%s %02d:%02d", $zwave_wd[$p1>>5], $p1 & 0x1f, $p2);
}

sub
ZWave_cleanString($$)
{
  my ($c, $postfix) = @_;
  my $shortened = 0;

  $c =~ s/^[0-9.]+ //g;
  $c =~ s/Don.t/Dont/g; # Bugfix
  if($c =~ m/^(.+)\.(.+)$/ && $2 !~ m/^[ \d]+$/) { # delete second sentence
    $c = $1; $shortened++;
  }
  $c =~ s/[^A-Z0-9]+/ /ig;
  $c =~ s/ *$//g;
  $c =~ s/ (.)/uc($1)/gei;
  while(length($c) > 32 && $shortened < 999) {
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

  my ($line, $class, %hash, $cmdName, %classInfo, %group);
  while($gz->gzreadline($line)) {       # Search the "file" entry
    last if($line =~ m/^\s*<Product.*sourceFile="$cfg"/);
  }

  while($gz->gzreadline($line)) {
    last if($line =~ m+^\s*</Product>+);
    if($line =~ m/^\s*<CommandClass.*id="([^"]*)"(.*)$/) {
      $class = $1;
      $classInfo{$class} = $2;
    }
    $group{$1} = $line if($line =~ m/^\s*<Group.*index="([^"]*)".*$/);
    next if(!$class || $class ne "112");
    if($line =~ m/^\s*<Value /) {
      my %h;
      $h{type}  = $1 if($line =~ m/type="([^"]*)"/i);
      $h{size}  = $1 if($line =~ m/size="([^"]*)"/i);
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

    $hash{$cmdName}{Help} .= "$1<br>" if($line =~ m+^\s*<Help>(.*)</Help>$+);
    if($line =~ m/^\s*<Item/) {
      my $label = $1 if($line =~ m/label="([^"]*)"/i);
      my $value = $1 if($line =~ m/value="([^"]*)"/i);
      my ($item, $shortened) = ZWave_cleanString($label, $value);
      $hash{$cmdName}{Item}{$item} = $value;
      $hash{$cmdName}{Help} .= "Full text for $item is $label<br>"
        if($shortened);
    }
  }
  $gz->gzclose();

  my %mc = (set=>{}, get=>{}, config=>{},classInfo=>\%classInfo,group=>\%group);
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
    my $len = ($v > 65535 ? 8 : ($v > 255 ? 4 : 2));
    return ("", sprintf("04%02x%02d%0*x", $h->{index}, $len/2, $len, $v));
  }
  if($t eq "button") {
    return ("", sprintf("04%02x01%02x", $h->{index}, $h->{value}));
  }

  return ("Parameter is not decimal", "") if($arg[0] !~ m/^[0-9]+$/);

  if($h->{size}) { # override type by size
    $t = ($h->{size} eq "1" ? "byte" : ($h->{size} eq "2" ? "short" : "int"));
  }

  my $len = ($t eq "int" ? 8 : ($t eq "short" ? 4 : 2));
  return ("", sprintf("04%02x%02x%0*x", $h->{index}, $len/2, $len, $arg[0]));
}

my %zwave_alarmType = (
  "01"=>"Smoke",
  "02"=>"CO",
  "03"=>"CO2",
  "04"=>"Heat",
  "05"=>"Water",
  "06"=>"AccessControl",
  "07"=>"HomeSecurity",
  "08"=>"PowerManagement",
  "09"=>"System",
  "0a"=>"Emergency",
  "0b"=>"Clock",
  "0c"=>"Appliance",
  "0d"=>"HomeHealth"
);

my %zwave_alarmEvent = (
  "0101"=>"detected",
  "0102"=>"detected, Unknown Location",
  "0103"=>"Alarm Test",
  "0201"=>"detected",
  "0202"=>"detected, Unknown Location",
  "0301"=>"detected",
  "0302"=>"detected, Unknown Location",
  "0401"=>"Overheat detected",
  "0402"=>"Overheat detected, Unknown Location",
  "0403"=>"Rapid Temperature Rise",
  "0404"=>"Rapid Temperature Rise, Unknown Location",
  "0405"=>"Underheat detected",
  "0406"=>"Underheat detected, Unknown Location",
  "0501"=>"Leak detected",
  "0502"=>"Leak detected, Unknown Location",
  "0503"=>"Level Dropped",
  "0504"=>"Level Dropped, Unknown Location",
  "0505"=>"Replace Filter",
  "0601"=>"Manual Lock Operation",
  "0602"=>"Manual Unlock Operation",
  "0603"=>"RF Lock Operation",
  "0604"=>"RF Unlock Operation",
  "0605"=>"Keypad Lock Operation",
  "0606"=>"Keypad Unlock Operation",
  "0607"=>"Manual Not Fully Locked Operation",
  "0608"=>"RF Not Fully Locked Operation",
  "0609"=>"Auto Lock Locked Operation",
  "060a"=>"Auto Lock Not Fully Operation",
  "060b"=>"Lock Jammed",
  "060c"=>"All user codes deleted",
  "060d"=>"Single user code deleted",
  "060e"=>"New user code added",
  "060f"=>"New user code not added due to duplicate code",
  "0610"=>"Keypad temporary disabled",
  "0611"=>"Keypad busy",
  "0612"=>"New Program code Entered - Unique code for lock configuration",
  "0613"=>"Manually Enter user Access code exceeds code limit",
  "0614"=>"Unlock By RF with invalid user code",
  "0615"=>"Locked by RF with invalid user codes",
  "0616"=>"Window/Door is open",
  "0617"=>"Window/Door is closed",
  "0640"=>"Barrier performing Initialization process",
  "0641"=>"Barrier operation (Open / Close) force has been exceeded.",
  "0642"=>"Barrier motor has exceeded manufacturer's operational time limit",
  "0643"=>"Barrier operation has exceeded physical mechanical limits.",
  "0644"=>"Barrier unable to perform requested operation due to UL requirements.",
  "0645"=>"Barrier Unattended operation has been disabled per UL requirements.",
  "0646"=>"Barrier failed to perform Requested operation, device malfunction",
  "0647"=>"Barrier Vacation Mode",
  "0648"=>"Barrier Safety Beam Obstacle",
  "0649"=>"Barrier Sensor Not Detected / Supervisory Error",
  "064a"=>"Barrier Sensor Low Battery Warning",
  "064b"=>"Barrier detected short in Wall Station wires",
  "064c"=>"Barrier associated with non-Z-wave remote control.",
  "0700"=>"Previous Events cleared",
  "0701"=>"Intrusion",
  "0702"=>"Intrusion, Unknown Location",
  "0703"=>"Tampering, product covering removed",
  "0704"=>"Tampering, Invalid Code",
  "0705"=>"Glass Breakage",
  "0706"=>"Glass Breakage, Unknown Location",
  "0707"=>"Motion Detection",
  "0708"=>"Motion Detection, Unknown Location",
  "0800"=>"Previous Events cleared",
  "0801"=>"Power has been applied",
  "0802"=>"AC mains disconnected",
  "0803"=>"AC mains re-connected",
  "0804"=>"Surge Detection",
  "0805"=>"Voltage Drop/Drift",
  "0806"=>"Over-current detected",
  "0807"=>"Over-voltage detected",
  "0808"=>"Over-load detected",
  "0809"=>"Load error",
  "080a"=>"Replace battery soon",
  "080b"=>"Replace battery now",
  "080c"=>"Battery is charging",
  "080d"=>"Battery is fully charged",
  "080e"=>"Charge battery soon",
  "080f"=>"Charge battery now!",
  "0901"=>"hardware failure",
  "0902"=>"software failure",
  "0903"=>"hardware failure with OEM proprietary failure code",
  "0904"=>"software failure with OEM proprietary failure code",
  "0a01"=>"Contact Police",
  "0a02"=>"Contact Fire Service",
  "0a03"=>"Contact Medical Service",
  "0b01"=>"Wake Up Alert",
  "0b02"=>"Timer Ended",
  "0b03"=>"Time remaining",
  "0c01"=>"Program started",
  "0c02"=>"Program in progress",
  "0c03"=>"Program completed",
  "0c04"=>"Replace main filter",
  "0c05"=>"Failure to set target temperature",
  "0c06"=>"Supplying water",
  "0c07"=>"Water supply failure",
  "0c08"=>"Boiling",
  "0c09"=>"Boiling failure",
  "0c0a"=>"Washing",
  "0c0b"=>"Washing failure",
  "0c0c"=>"Rinsing",
  "0c0d"=>"Rinsing failure",
  "0c0e"=>"Draining",
  "0c0f"=>"Draining failure",
  "0c10"=>"Spinning",
  "0c11"=>"Spinning failure",
  "0c12"=>"Drying",
  "0c13"=>"Drying failure",
  "0c14"=>"Fan failure",
  "0c15"=>"Compressor failure",
  "0d00"=>"Previous Events cleared",
  "0d01"=>"Leaving Bed",
  "0d02"=>"Sitting on bed",
  "0d03"=>"Lying on bed",
  "0d04"=>"Posture changed",
  "0d05"=>"Sitting on edge of bed",
  "0d06"=>"Volatile Organic Compound level"
);

sub
ZWave_alarmParse($$$)
{
  my ($t,$l,$r) = @_;

  if($t=="00" && $r && $r =~ m/^..(..)(..)/) { # Forum #35178
    $l = $1; $t = $2;
  }

  if(!$r || $r !~ m/......(..)(.*)/ || !$zwave_alarmType{$t}) { # V1 or unknown
    return "alarm_type_$t:level $l";
  }
  my ($e, $v4, $s) = ($1, $2, "alarm:$zwave_alarmType{$t}: ");

  if($l eq "00") {
    $s .= "Event cleared: ";
    $e = $1 if($v4 && $v4 =~ m/..(..)../);
  }

  $s .= ($zwave_alarmEvent{"$t$e"} ?
         $zwave_alarmEvent{"$t$e"} : "unknown event $e");
  $s .= ", arg $v4" if($v4 && $l ne "00");
  return $s;
}

sub
ZWave_protectionParse($$)
{
  my ($lp, $rp) = @_;
  my $lpt = "Local: ". ($lp eq "00" ? "unprotected" :
                       ($lp eq "01" ? "by sequence" : "No operation possible"));
  my $rpt = "RF: ".    ($rp eq "00" ? "unprotected" :
                       ($rp eq "01" ? "No control"  : "No response"));
  return "protection:$lpt $rpt";
}

sub
ZWave_configParse($$$$)
{
  my ($hash, $cmdId, $size, $val) = @_;
  $val = substr($val, 0, 2*$size);
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

my %zwave_roleType = (
  "00"=>"CentralStaticController",
  "01"=>"SubStaticController",
  "02"=>"PortableController",
  "03"=>"PortableReportingController",
  "04"=>"PortableSlave",
  "05"=>"AlwaysOnSlave",
  "06"=>"SleepingReportingSlave",
  "07"=>"SleepingListeningSlave"
);

my %zwave_nodeType = (
  "00"=>"Z-Wave+Node",
  "01"=>"Z-Wave+IpRouter",
  "02"=>"Z-Wave+IpGateway",
  "03"=>"Z-Wave+IpClientAndIpNode",
  "04"=>"Z-Wave+IpClientAndZwaveNode"
);

sub 
ZWave_plusInfoParse($$$$$)
{
  my ($version, $roleType, $nodeType, $installerIconType, $userIconType) = @_;
  return "zwavePlusInfo: " .
    "version:" . $version . 
    " role:" .
      ($zwave_roleType{"$roleType"} ? $zwave_roleType{"$roleType"} :"unknown") .
    " node:" .
      ($zwave_nodeType{"$nodeType"} ? $zwave_nodeType{"$nodeType"} :"unknown") .
    " installerIcon:". $installerIconType . 
    " userIcon:". $userIconType;
}

my %zwave_sensorBinaryTypeV2 = (
  	"00"=>"unknown",
	"01"=>"generalPurpose",
	"02"=>"smoke",
	"03"=>"CO",
	"04"=>"CO2",
	"05"=>"heat",
	"06"=>"water",
	"07"=>"freeze",
	"08"=>"tamper",
	"09"=>"aux",
	"0a"=>"doorWindow",
	"0b"=>"tilt",
	"0c"=>"motion",
	"0d"=>"glassBreak"
);

sub
ZWave_sensorbinaryV2Parse($$)
{
  my ($value, $sensorType) = @_;
  return ($zwave_sensorBinaryTypeV2{"$sensorType"} ? 
          $zwave_sensorBinaryTypeV2{"$sensorType"} :"unknown") . 
          ":".$value;
}

sub
ZWave_secureInit(@)
{
  my ($hash, $param) = @_;
  my $iodev = $hash->{IODev};
  my $name = $hash->{NAME};

  $hash->{secStatus} = 0 if(!$hash->{secStatus});
  my $status = ++$hash->{secStatus};

  my @stTxt = ( "secScheme", "secKey", "secNonce", "done");
  my $stTxt = ($status > int(@stTxt) ? "ERR" : $stTxt[$status-1]);
  Log3 $iodev, 4, "*** $hash->{NAME}: secureInit status $status/$stTxt";

  if($status == 1) {
    ZWave_Set($hash, $name, "secScheme");
    return ""; # not evaluated

  } elsif($status == 2) {
    Log3 $iodev, 4, "secScheme report: $param";
    my $key = AttrVal($iodev->{NAME}, "networkKey", "");
    ZWave_Set($hash, $name, ("secKey", $key));
    return undef;       # No Event/Reading

  } elsif($status == 3) {
    #IOWrite($hash, "secKey ACK", "");
    ZWave_Set($hash, $name, "secNonce");
    return undef;       # No Event/Reading

  } else {
    Log3 $iodev, 4, "secNonce report: $param";
    delete $iodev->{secInitName};
    delete $hash->{secStatus};
    return ZWave_execInits($hash, 0);
  }
}


sub
ZWave_getHash($$$)
{
  my ($hash, $cl, $type) = @_;
  my $ptr; # must be standalone, as there is a $ptr in the calling fn.
  $ptr = $zwave_class{$cl}{$type}
      if($zwave_class{$cl} && $zwave_class{$cl}{$type});

  if($cl eq "CONFIGURATION" && $type ne "parse") {
    my $mc = ZWave_configGetHash($hash);
    if($mc) {
      my $mcp = $mc->{$type};
      if($mcp) {
        my %nptr = ();
        map({$nptr{$_} = $ptr->{$_}} keys %{$ptr});
        map({$nptr{$_} = $mcp->{$_}} keys %{$mcp});
        $ptr = \%nptr;
      }
    }
  }

  my $modelId = ReadingsVal($hash->{NAME}, "modelId", "");
  $modelId = $zwave_modelIdAlias{$modelId} if($zwave_modelIdAlias{$modelId});
  my $p = $zwave_deviceSpecial{$modelId};
  if($p && $p->{$cl}) {
    $ptr = $p->{$cl}{$type} if($p->{$cl}{$type});

    my $add = $p->{$cl}{$type."_ADD"};
    $ptr = {} if($add && !$ptr);
    map { $ptr->{$_} = $add->{$_} } keys %{$add} if($add);
  }

  return $ptr;
}

sub
ZWave_sendWakeup($)
{
  my ($hash) = @_;

  my $wu = $hash->{WakeUp};
  if($wu && @{$wu}) {
    foreach my $wuCmd (@{$wu}) {
      IOWrite($hash, "00", ZWave_clockAdjust($wuCmd));
      Log3 $hash, 4, "Sending stored command: $wuCmd";
    }
    @{$hash->{WakeUp}}=();
    #send a final wakeupNoMoreInformation
    my $nodeId = $hash->{id};
    Log3 $hash, 4, "Sending wakeupNoMoreInformation to node: $nodeId";
    IOWrite($hash, "00", "13${nodeId}02840805");

  } else { # Wait for commands via notify
    InternalTimer(gettimeofday()+0.1, sub($) {
      my $nodeId = $hash->{id};
      IOWrite($hash, "00", "13${nodeId}02840805");
    }, $hash, 0);
  }
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
      my $si = $iodev->{secInitName};
      ZWave_secureInit($defs{$si}) # No extra response for set networkKey
        if($si && $defs{$si} && $defs{$si}{secStatus} &&
           $defs{$si}{secStatus} == 2);
      return "";
    }
    if($cmd eq "SERIAL_API_SET_TIMEOUTS" && $arg =~ m/(..)(..)/) {
      Log3 $ioName, 2, "SERIAL_API_SET_TIMEOUTS: ACK:$1 BYTES:$2";
      return "";
    }
    Log3 $ioName, 4, "$ioName unhandled ANSWER: $cmd $arg";
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
                "controller", "protocolDone", "done", "failed");
    $evt = ($id eq "00" || hex($id)>@vals+1) ? "unknownArg" : $vals[hex($id)-1];
    if($evt eq "slave" &&
       $arg =~ m/(..)....(..)..(.*)$/) {
      my ($id,$type6,$classes) = ($1, $2, $3);
      return ZWave_SetClasses($homeId, $id, $type6, $classes)
        if($cmd eq 'ZW_ADD_NODE_TO_NETWORK');
    }

    if($evt eq "protocolDone" && $arg =~ m/(..)../) {# done comes at addNode off
      delete $iodev->{secInitName};
      my $dh = $modules{ZWave}{defptr}{"$homeId $1"};
      return "" if(!$dh);

      $dh->{lastMsgTimestamp} = time();

      if($iodev->{addSecure}) {
        my $classes = AttrVal($dh->{NAME}, "classes", "");
        if($classes =~ m/SECURITY/) {
          my $key = AttrVal($ioName, "networkKey", "");
          if($key) {
            $iodev->{secInitName} = $dh->{NAME};
            return ZWave_secureInit($dh);
          } else {
            Log3 $ioName, 2, "No secure inclusion as $ioName has no networkKey";
          }
        }
      }
      return ZWave_execInits($dh, 0);
    }


  } elsif($cmd eq "ZW_APPLICATION_UPDATE" && $arg =~ m/....(..)..(.*)$/) {
    my ($type6,$classes) = ($1, $2);
    my $ret = ZWave_SetClasses($homeId, $id, $type6, $classes);

    my $hash = $modules{ZWave}{defptr}{"$homeId $id"};
    if($hash) {
      ZWave_sendWakeup($hash) if($hash);
      $hash->{lastMsgTimestamp} = time();
      if(!$ret) {
        readingsSingleUpdate($hash, "CMD", $cmd, 1); # forum:20884
        return $hash->{NAME};
      }
    }
    return $ret;

  } elsif($cmd eq "ZW_SEND_DATA") {
    my $hash = $modules{ZWave}{defptr}{"$homeId $callbackid"};
    my %msg = ('00'=>'OK', '01'=>'NO_ACK', '02'=>'FAIL',
               '03'=>'NOT_IDLE', '04'=>'NOROUTE' );
    my $msg = ($msg{$id} ? $msg{$id} : "UNKNOWN_ERROR");
    if ($id eq "00") {
      Log3 $ioName, 4, "$ioName transmit $msg for $callbackid";
      readingsSingleUpdate($hash, "transmit", $msg, 0) if($hash);
      return "";

    } else {
      Log3 $ioName, 2, "$ioName transmit $msg for $callbackid";
      return "" if(!$hash);
      readingsSingleUpdate($hash, "state", "TRANSMIT_$msg", 1);
      readingsSingleUpdate($hash, "transmit", $msg, 1);
      return $hash->{NAME};
    }

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

  if($arg =~ m/^(..)(..)(.*)/ && $2 eq "c6") { # Danfoss Living Strangeness
    Log3 $ioName, 4, "Class mod for Danfoss ($2)";
    $arg = sprintf("%s%02x%s", $1, hex($2) & 0x7f, $3);
  }

  if($arg =~ /^..5601(.*)..../) { # CRC_16_ENCAP: Unwrap encapsulated command
    #Log3 $ioName, 4, "CRC FIX, MSG: ($1)"; # see Forum #23494
    $arg = sprintf("%02x$1", length($1)/2);
  }

  my ($baseHash, $baseId, $ep) = ("",$id,"");
  if($arg =~ /^..6006(..)(.*)/) { # MULTI_CHANNEL CMD_ENCAP, V1, Forum #36126
    $ep = $1;
    $baseHash = $modules{ZWave}{defptr}{"$homeId $id"};
    $id = "$id$ep";
    $arg = sprintf("%02x$2", length($2)/2);
  }
  if($arg =~ /^..600d(..)(..)(.*)/) { # MULTI_CHANNEL CMD_ENCAP, V2
    $ep = ($1 ne "00" ? $1 : $2);
    $baseHash = $modules{ZWave}{defptr}{"$homeId $id"};
    $id = "$id$ep";
    $arg = sprintf("%02x$3", length($3)/2);
  }
  my $hash = $modules{ZWave}{defptr}{"$homeId $id"};
  $baseHash = $hash if(!$baseHash);


  if(!$hash) {
    $id=hex($id); $baseId=hex($baseId); $ep=hex($ep);
    # $ep eq "0": Msg from a device known to the ZWDongle, but not to FHEM.
    my $nn = "ZWave_Node_$baseId".($ep eq "0" ? "" : ".$ep");
    my $ret = "UNDEFINED $nn ZWave $homeId $id";
    Log3 $ioName, 3, "$ret, please define it";
    DoTrigger("global", $ret);
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
      push @event, "UNPARSED:$className $arg";
      next;
    }

    my $matched = 0;
    foreach my $k (keys %{$ptr}) {
      if($arg =~ m/^$k/) {
        my $val = $ptr->{$k};
        $val = eval $val if(index($val, '$') >= 0);
        push @event, $val if(defined($val));
        $matched++;
      }
    }
    push @event, "UNPARSED:$className $arg" if(!$matched);
  }

  ZWave_sendWakeup($baseHash) if($arg =~ m/^028407/);
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
  <li>basicValue value<br>
    Alias for basicValue, to make mapping from the incoming events easier.
    </li><br>

  <br><br><b>Class BASIC_WINDOW_COVERING</b>
  <li>coveringClose<br>
    Starts closing the window cover. Moving stops if blinds are fully closed or
    a coveringStop command was issued. 
    </li>
  <li>coveringOpen<br>
    Starts opening the window cover.  Moving stops if blinds are fully open or
    a coveringStop command was issued. 
    </li>
  <li>coveringStop<br>
    Stop moving the window cover. Blinds are partially open (closed).
  </li>

  <br><br><b>Class CLIMATE_CONTROL_SCHEDULE</b>
  <li>ccs [mon|tue|wed|thu|fri|sat|sun] HH:MM tempDiff HH:MM tempDiff ...<br>
    set the climate control schedule for the given day.<br>
    Up to 9 pairs of HH:MM tempDiff may be specified.<br>
    HH:MM must occur in increasing order.
    tempDiff is relative to the setpoint temperature, and may be between -12
    and 12, with one decimal point, measured in Kelvin (or Centigrade).
    </li>

  <br><br><b>Class CLOCK</b>
  <li>clock<br>
    set the clock to the current date/time (no argument required)
    </li>

  <br><br><b>Class COLOR_CONTROL</b>
  <li>rgb<br>
    Set the color of the device as a 6 digit RGB Value (RRGGBB), each color is
    specified with a value from 00 to ff.</li>
  <li>wcrgb<br>
    Used for sending warm white, cold white, red, green and blue values
    to device. Values must be decimal (0 - 255) and separated by blanks.
    <ul>
      set &lt;name&gt; wcrgb 0 255 0 0 0 (setting full cold white)<br>
    </ul>
    </li>
	
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
    Fibaro FGRM-222 only: drive blinds to position %</li>
  <li>positionSlat<br>
    Fibaro FGRM-222 only: drive slat to position %</li>

  <br><br><b>Class METER</b>
  <li>meterReset<br>
    Reset all accumulated meter values.<br>
    Note: see meterSupported command and its output to detect if resetting the
    value is supported by the device.<br>
    The command will reset ALL accumulated values, it is not possible to
    choose a single value.</li>
  
  <br><br><b>Class MULTI_CHANNEL_ASSOCIATION</b>
  <li>mcaAdd groupId node1 node2 ... 0 node1 endPoint1 node2 endPoint2 ...<br>
    Add a list of node or node:endpoint associations. The latter can be used to
    create channels on remotes. E.g. to configure the button 1,2,... on the
    zwave.me remote, use:
    <ul>
      set remote mcaAdd 2 0 1 2<br>
      set remote mcaAdd 3 0 1 3<br>
      ....
    </ul>
    For each button a separate FHEM device will be generated.
    </li>
  <li>mcaDel groupId node1 node2 ... 0 node1 endPoint1 node2 endPoint2 ...<br>
    delete node or node:endpoint associations.
    Special cases: just specifying the groupId will delete everything for this
    groupId. Specifying 0 for groupid will delete all associations.
    </li>

  <br><br><b>Class NODE_NAMING</b>
  <li>name NAME<br>
    Store NAME in the EEPROM. Note: only ASCII is supported.</li>
  <li>location LOCATION<br>
    Store LOCATION in the EEPROM. Note: only ASCII is supported.</li>

  <br><br><b>Class POWERLEVEL</b>
  <li>Class is only used in an installation or test situation</li>
  <li>powerlevel level timeout/s<br>
    set powerlevel to level [0-9] for timeout/s [1-255].<br>
    level 0=normal, level 1=-1dBm, .., level 9=-9dBm.</li>
  <li>powerlevelTest nodeId level frames <br>
    send number of frames [1-65535] to nodeId with level [0-9].</li>
  
  <br><br><b>Class PROTECTION</b>
  <li>protectionOff<br>
    device is unprotected</li>
  <li>protectionOn<br>
    device is protected</li>
  <li>protectionSeq<br>
    device can be operated, if a certain sequence is keyed.</li>
  <li>protectionBytes LocalProtectionByte RFProtectionByte<br>
    for commandclass PROTECTION V2 - see devicemanual for supported protectionmodes</li>

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

  <br><br><b>Class SWITCH_MULTILEVEL</b>
  <li>on, off<br>
    the same as for SWITCH_BINARY.</li>
  <li>dim value<br>
    dim/jump to the requested value (0..100)</li>
  <li>stop<br>
    stop dimming/operation</li>

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

  <br><br><b>Class USER_CODE</b>
  <li>userCode id status code</br>
    set code and status for the id n. n ist starting at 1, status is 0 for
    available (deleted) and 1 for set (occupied). code is a hexadecimal string.
    </li>

  <br><br><b>Class WAKE_UP</b>
  <li>wakeupInterval value nodeId<br>
    Set the wakeup interval of battery operated devices to the given value in
    seconds. Upon wakeup the device sends a wakeup notification to nodeId.</li>
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

  <br><br><b>Class CLIMATE_CONTROL_SCHEDULE</b>
  <li>ccsOverride<br>
    request the climate control schedule override report
    </li>
  <li>ccs [mon|tue|wed|thu|fri|sat|sun]<br>
    request the climate control schedule for the given day.
    </li>

  <br><br><b>Class CLOCK</b>
  <li>clock<br>
    request the clock data
    </li>

  <br><br><b>Class CONFIGURATION</b>
  <li>config cfgAddress<br>
    return the value of the configuration parameter cfgAddress. The value is
    device specific.<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config commands are available.
    </li>

  <br><br><b>Class HRV_STATUS</b>
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
    Fibaro FGRM-222 only: return the blinds position and slat angle.
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
  <li>meter scale<br>
    return the meter report for the requested scale.<br>
    Note: protocol V1 does not support the scale parameter, the parameter will
    be ignored and the default scale will be returned.<br>
    For protocol V2 and higher, scale is supported and depends on the type of
    the meter (energy, gas or water).<br>
    The device may not support all scales, see the meterSupported command and
    its output. If the scale parameter is omitted, the default unit will be
    reported.<br>
    Example: For an electric meter, meter 0 will report energy in kWh,
    meter 2 will report power in W and meter 6 will report current in A
    (if these scales are supported).<br>
    </li>
  <li>meterSupported<br>
    request the type of the meter, the supported scales and the capability to
    reset the accumulated value.<br>
    Note: The output contains the decimal numbers of the supported scales that
    can be used as parameter for the meter command.
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

  <br><br><b>Class MULTI_CHANNEL_ASSOCIATION</b>
  <li>mca groupid<br>
    return the associations for the groupid. for the syntax of the returned
    data see the mcaAdd command above.
    </li>

  <br><br><b>Class NODE_NAMING</b>
  <li>name<br>
    Get the name from the EEPROM. Note: only ASCII is supported.</li>
  <li>location<br>
    Get the location from the EEPROM. Note: only ASCII is supported.</li>
  
  <br><br><b>Class POWERLEVEL</b>
  <li>powerlevel<br>
    Get the current powerlevel and remaining time in this level.</li>
  <li>powerlevelTest<br>
    Get the result of last powerlevelTest.</li>

  <br><br><b>Class PROTECTION</b>
  <li>protection<br>
    returns the protection state. It can be on, off or seq.</li>

  <br><br><b>Class SCENE_ACTUATOR_CONF</b>
  <li>sceneConfig<br>
    returns the settings for a given scene. Parameter is sceneId
    </li>

  <br><br><b>Class SCENE_CONTROLLER_CONF</b>
  <li>groupConfig<br>
    returns the settings for a given group. Parameter is groupId
    </li>

  <br><br><b>Class SENSOR_ALARM</b>
  <li>alarm alarmType<br>
    return the nodes alarm status of the requested alarmType. 00 = GENERIC,
    01 = SMOKE, 02 = CO, 03 = CO2, 04 = HEAT, 05 = WATER, ff = returns the
    nodes first supported alarm type.    
    </li>

  <br><br><b>Class SENSOR_BINARY</b>
  <li>sbStatus<br>
    return the status of the node.
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
	
  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>thermostatMode<br>
    request the mode
    </li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>setpoint<br>
    request the setpoint
    </li>

  <br><br><b>Class USER_CODE</b>
  <li>userCode n</br>
    request status and code for the id n
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
  <li>wakeupIntervalCapabilities (V2 only)<br>
    return the wake up interval capabilities in seconds, in the form<br>
    wakeupIntervalCapabilitiesReport:min seconds max seconds default seconds
    step seconds
  </li>

  <br><br><b>Class ZWAVEPLUS_INFO</b>
  <li>zwavePlusInfo<br>
    request the zwavePlusInfo
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

  <br><b>Class ALARM</b>
  <li>Devices with class version 1 support: alarm_type_X:level Y</li>
  <li>For higher class versions more detailed events with 100+ different
      strings in the form alarm:<string> are generated.</li>

  <br><br><b>Class ASSOCIATION</b>
  <li>assocGroup_X:Max Y Nodes A,B,...</li>

  <br><br><b>Class BASIC</b>
  <li>basicReport:XY</li>
  <li>state:basicGet</li>
  <li>state:basicSet XY</li>

  <br><br><b>Class BASIC_WINDOW_COVERING</b>
  <li>covering:[open:close:stop]</li>

  <br><br><b>Class BATTERY</b>
  <li>battery:chargelevel %</li>

  <br><br><b>Class CENTRAL_SCENE</b>
  <li>cSceneSet:X</li>
  <li>cSceneDim:X</li>
  <li>cSceneDimEnd:X</li>

  <br><br><b>Class CLIMATE_CONTROL_SCHEDULE</b>
  <li>ccsOverride:[no|temporary|permanent],
                  [frost protection|energy saving|unused]</li>
  <li>ccsChanged:<number></li>
  <li>ccs_[mon|tue|wed|thu|fri|sat|sun]:HH:MM temp HH:MM temp...</li>

  <br><br><b>Class CLOCK</b>
  <li>clock:get</li>
  <li>clock:[mon|tue|wed|thu|fri|sat|sun] HH:MM</li>

  <br><br><b>Class CONFIGURATION</b>
  <li>config_X:Y<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config messages are available.</li>
  
  <br><br><b>Class DEVICE_RESET_LOCALLY</b>
  <li>deviceResetLocally:yes<br></li>

  <br><br><b>Class HAIL</b>
  <li>hail:01<br></li>

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
  <li>Fibaro FGRM-222 with ReportsType Fibar CC only:</li>
  <li>position:Blinds [%] Slat [%]<br>
    (VenetianBlindMode)</li>
  <li>position:[%]<br>
    (RollerBlindMode)</li>
  
  <br><br><b>Class MANUFACTURER_SPECIFIC</b>
  <li>modelId:hexValue hexValue hexValue</li>
  <li>model:manufacturerName productName</li>
  <li>modelConfig:configLocation</li>

  <br><br><b>Class METER</b>
  <li>energy:val [kWh|kVAh|pulseCount|powerFactor]</li>
  <li>gas:val [m3|feet3|pulseCount]</li>
  <li>water:val [m3|feet3|USgallons|pulseCount]</li>
  <li>power:val W</li>
  <li>voltage:val V</li>
  <li>current:val A</li>
  <li>meterSupported:type:[meter_type] scales:[list of supported scales]
    resetable:[yes|no]</li>

  <br><br><b>Class MULTI_CHANNEL</b>
  <li>endpoints:total X $dynamic $identical</li>
  <li>mcCapability_X:class1 class2 ...</li>

  <br><br><b>Class NODE_NAMING</b>
  <li>name:NAME</li>
  <li>location:LOCATION</li>

  <br><br><b>Class POWERLEVEL</b>
  <li>powerlvl:current x remain y<br>
    NOTE: "current 0 remain 0" means normal mode without timeout</li>
  <li>powerlvlTest:node x status y frameAck z<br>
    NOTE: status 0=failed, 1=success (at least one ACK), 2=in progress</li>
  
  <br><br><b>Class PROTECTION</b>
  <li>protection:[on|off|seq]</li>

  <br><br><b>Class SCENE_ACTIVATION</b>
  <li>scene_Id:level finalValue</li>
    
  <br><br><b>Class SCENE_ACTUATOR_CONF</b>
  <li>scene_Id:level dimmingDuration finalValue</li>
  
  <br><br><b>Class SCENE_CONTROLLER_CONF</b>
  <li>group_Id:scene dimmingDuration</li>
 
 
  <br><br><b>Class SENSOR_ALARM</b>
  <li>alarm_type_X:level Y node $nodeID seconds $seconds</li> 

  <br><br><b>Class SENSOR_BINARY</b>
  <li>SENSORY_BINARY V1:</li>
  <li>state:open</li>
  <li>state:closed</li>
  <li>SENSORY_BINARY V2:</li>
  <li>unknown:[00|ff]</li>
  <li>generalPurpose:[00|ff]</li>
  <li>smoke:[00|ff]</li>
  <li>CO:[00|ff]</li>
  <li>CO2:[00|ff]</li>
  <li>heat:[00|ff]</li>
  <li>water:[00|ff]</li>
  <li>freeze:[00|ff]</li>
  <li>tamper:[00|ff]</li>
  <li>aux:[00|ff]</li>
  <li>doorWindow:[00|ff]</li>
  <li>tilt:[00|ff]</li>
  <li>motion:[00|ff]</li>
  <li>glassBreak:[00|ff]</li>

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
  <li>state:setOn</li>
  <li>state:setOff</li>

  <br><br><b>Class SWITCH_MULTILEVEL</b>
  <li>state:on</li>
  <li>state:off</li>
  <li>state:dim value</li>
  <li>state:swmBeginUp</li>
  <li>state:swmBeginDown</li>
  <li>state:swmEnd</li>
    
  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>off</li>
  <li>cooling</li>
  <li>heating</li>
  <li>manual</li>
  <li>setTmOff</li>
  <li>setTmHeating</li>
  <li>setTmCooling</li>
  <li>setTmManual</li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>setpointTemp:$temp [C|F] [heating|cooling]</li>

  <br><br><b>Class USER_CODE</b>
  <li>userCode:id x status y code z</li>

  <br><br><b>Class VERSION</b>
  <li>V1:</li>
  <li>version:Lib A Prot x.y App a.b</li>
  <li>V2:</li>
  <li>version:Lib A Prot x.y App a.b HW B FWCounter C FW c.d</li>
  <li>V1 and V2:</li>
  <li>versionClass_$classId:$version</li>

  <br><br><b>Class WAKE_UP</b>
  <li>wakeup:notification</li>
  <li>wakeupReport:interval:X target:Y</li>
  <li>wakeupIntervalCapabilitiesReport:min W max X default Y step Z</li>
  
  <br><br><b>Class ZWAVEPLUS_INFO</b>
  <li>zwavePlusInfo:version: V role: W node: X installerIcon: Y userIcon: Z</li>

  </ul>
</ul>

=end html
=cut

##############################################
# $Id$
# See ZWDongle.pm for inspiration
package main;

use strict;
use warnings;
use SetExtensions;
use Compress::Zlib;
use Time::HiRes qw( gettimeofday );
use HttpUtils;
use ZWLib;

sub ZWave_Cmd($$@);
sub ZWave_Get($@);
sub ZWave_Parse($$@);
sub ZWave_Set($@);
sub ZWave_SetClasses($$$$);
sub ZWave_addToSendStack($$$);
sub ZWave_secStart($);
sub ZWave_secEnd($);
sub ZWave_configParseModel($;$);
sub ZWave_callbackId($);
sub ZWave_setEndpoints($);

our ($FW_ME,$FW_tp,$FW_ss);
our %zwave_id2class;

my %zwave_class = (
  NO_OPERATION             => { id => '00' }, # lowlevel
  ZWAVE                    => { id => '01',   # lowlevel
    set   => { zwaveAssignId => "03%02x%08x" },
    parse => { "..0101(....)..(..)..(.*)" =>
                              '"zwaveNIF:baseClass:$2 flags:$1 classes:$3"',
               "..0103(..)(........)" =>
                              '"zwaveAssignId:homeId:$2 nodeIdHex:$1"',
               "..0104(.*)"=> '"zwaveFindNodesInRange:$1"',
               "..0105"    => '"zwaveGetNodesInRange:noarg"',
               "..0106(.*)"=> '"zwaveNodeRangeInfo:$1"',
               "..0107(.*)"=> '"zwaveCommandComplete:$1"',
               "..010801"  => '"zwaveTransferPresentation"',
               "..010c(.*)"=> '"zwaveAssignRoute:$1"'
               }},
  BASIC                    => { id => '20', # V1, V2
    set   => { basicValue  => "01%02x",     # V1, V2
               basicSet    => "01%02x"  },  # Alias, Forum #38200
    get   => { basicStatus => "02",     },  # V1, V2
    parse => { "..2001(.*)"=> '"basicSet:".hex($1)', # Forum #36980
               "..2002"    => "basicGet:request", # sent by the remote
               "032003(..)"=> '"basicReport:".hex($1)', # V1
               "052003(..)(..)(..)" => 'ZWave_BASIC_03_report($1,$2,$3)',
               }},
  CONTROLLER_REPLICATION   => { id => '21' },
  APPLICATION_STATUS       => { id => '22', # V1
    parse => { "..2201(..)(..)" =>
                  'ZWave_APPLICATION_STATUS_01_Report($hash, $1, $2)',  # V1
               "03220200" => "applicationStatus:cmdRejected",           # V1
               }},
  ZIP_SERVICES             => { id => '23' },
  ZIP_SERVER               => { id => '24' },
  SWITCH_BINARY            => { id => '25',
    set   => { off         => "0100",
               on          => "01FF" },
    get   => { swbStatus   => "02",       },
    parse => { "..250300"  => "state:off",
               "..2503ff"  => "state:on",
               "052503(..)(..)(..)" => 'sprintf("swbStatus:%s target %s '.
                          'duration %s", hex($1), hex($2), ZWave_duration($3))',
               "03250100"  => "state:setOff",
               "032501ff"  => "state:setOn"  } } ,
  SWITCH_MULTILEVEL        => { id => '26',
    set   => { off         => "0100",
               on          => "01FF",
               dim         => "01%02x",
               dimWithDuration => "01%02x%02x",
               stop        => "05" },
    get   => { swmStatus   => "02",     },
    parse => { "032603(.*)"=> '($1 eq "00" ? "state:off" :
                               ($1 eq "ff" ? "state:on" :
                                             "state:dim ".hex($1)))',
               "..260100.."=> "state:setOff",
               "..2601ff.."=> "state:setOn",
               "..260420"  => "state:swmBeginUp",
               "..260460"  => "state:swmBeginDown",
               "..2604(..)(..)(..)(..)"  => 'ZWave_swmParse($1,$2,$3,$4)',
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
    parse => { "042b01(..)(..)"  => '"scene_".hex($1).":".hex($2)',
               "042b01(..)ff" => 'ZWave_sceneParse($1)'} },
  SCENE_ACTUATOR_CONF      => { id => '2c',
    set   => { sceneConfig => "01%02x%02x80%02x" },
    get   => { sceneConfig => "02%02x"           },
    parse => { "052c03(..)(..)(..)"   =>
                '"scene_".hex($1).":level ".hex($2)."duration ".hex($3)' } },
  SCENE_CONTROLLER_CONF    => { id => '2d',
    set   => { sceneConfig => "01%02x%02x%02x" },
    get   => { sceneConfig => "02%02x"          },
    parse => { "052d03(..)(..)(..)"   =>
                '"group_".hex($1).":scene ".hex($2)."duration ".hex($3)' } },
  ZIP_CLIENT               => { id => '2e' },
  ZIP_ADV_SERVICES         => { id => '2f' },
  SENSOR_BINARY            => { id => '30',
    get   => { sbStatus    => "02"        },
    parse => { "03300300"  => "state:closed",
               "033003ff"  => "state:open",
               "043003(..)(..)"=> 'ZWave_sensorbinaryV2Parse($1,$2)' } },
  SENSOR_MULTILEVEL        => { id => '31',
    get   => { smStatus    => "04" },
    parse => { "..3105(..)(..)(.*)" => 'ZWave_multilevelParse($1,$2,$3)'} },
  METER                    => { id => '32',
    set   => { meterReset  => "05" },
    get   => { meter       => 'ZWave_meterGet("%s")',
               meterSupported => "03" },
    parse => { "..3202(.*)"=> 'ZWave_meterParse($hash, $1)',
               "..3204(.*)"=> 'ZWave_meterSupportedParse($hash, $1)' } },
  COLOR_CONTROL            => { id => '33',
    get   => { ccCapability=> '01', # no more args
               ccStatus    => '03%02x' },
    set   => { # Forum #36050
               rgb         => '05050000010002%02x03%02x04%02x', # Forum #44014
               wcrgb       => '050500%02x01%02x02%02x03%02x04%02x' },
    parse => { "043302(..)(..)"=> 'ZWave_ccCapability($1,$2)',
               "043304(..)(.*)"=> '"ccStatus_".hex($1).":".hex($2)' } },
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
               tmCooling   => "0102",
               tmAuto      => "0103",
               tmFan       => "0106",
               tmEnergySaveHeating => "010b",
               tmFullPower => "010f",
               tmManual    => "011f" },
    get   => { thermostatMode => "02" },
    parse => { "0.400300"  => "thermostatMode:off",
               "0.400301"  => "thermostatMode:heating",
               "0.400302"  => "thermostatMode:cooling",
               "0.400303"  => "thermostatMode:auto",
               "0.400306"  => "thermostatMode:fanOnly",
               "0.40030b"  => "thermostatMode:energySaveHeating",
               "0.40030f"  => "thermostatMode:fullPower",
               "0.40031f"  => "thermostatMode:manual",
               "0.400100"  => "thermostatMode:setTmOff",
               "0.400101"  => "thermostatMode:setTmHeating",
               "0.400103"  => "thermostatMode:auto",
               "0.40010b"  => "thermostatMode:setTmEnergySaveHeating",
               "0.40011f"  => "thermostatMode:setTmManual",
               } } ,
  PREPAYMENT_ENCAPSULATION => { id => '41' },
  THERMOSTAT_OPERATING_STATE=>{ id => '42' ,
    get   => { thermostatOperatingState   => "02" },
    parse => { "03420300" => "thermostatOperatingState:idle",
               "03420301" => "thermostatOperatingState:heating",
               "03420302" => "thermostatOperatingState:cooling",
               "03420303" => "thermostatOperatingState:fanOnly",
               "03420304" => "thermostatOperatingState:pendingHeat",
               "03420305" => "thermostatOperatingState:pendingCool",
               "03420306" => "thermostatOperatingState:ventEconomizer",
               "03420307" => "thermostatOperatingState:auxHeating",
               "03420308" => "thermostatOperatingState:2ndStageHeating",
               "03420309" => "thermostatOperatingState:2ndStageCooling",
               "0342030a" => "thermostatOperatingState:2ndStageAuxHeat",
               "0342030b" => "thermostatOperatingState:3rdStageAuxHeat",
               } },
  THERMOSTAT_SETPOINT      => { id => '43',
    set   => { setpointHeating => "010101%02x",
               setpointCooling => "010201%02x",
               thermostatSetpointSet
                  => 'ZWave_thermostatSetpointSet($hash, "%s")',
               "desired-temp"  => # alias
                  => 'ZWave_thermostatSetpointSet($hash, "%s")'},
    get   => { setpoint => 'ZWave_thermostatSetpointGet("%s")',
               thermostatSetpointSupported => '04' },
    parse => {  "..4303(.*)" => 'ZWave_thermostatSetpointParse($hash, $1)',
                "..4305(.*)" =>
                        'ZWave_thermostatSetpointSupportedParse($hash, $1)' } },
  THERMOSTAT_FAN_MODE      => { id => '44',
    set   => { fanAutoLow    => "0100",
               fanLow        => "0101",
               fanAutoHigh   => "0102",
               fanHigh       => "0103",
               fanAutoMedium => "0104",
               fanMedium     => "0105" },
    get   => { fanMode => "02" },
    parse => { "03440300"  => "fanMode:fanAutoLow",
               "03440301"  => "fanMode:fanLow",
               "03440302"  => "fanMode:fanAutoHigh",
               "03440303"  => "fanMode:fanHigh",
               "03440304"  => "fanMode:fanAutoMedium",
               "03440305"  => "fanMode:fanMedium"
               } } ,
  THERMOSTAT_FAN_STATE     => { id => '45',
    get   => { fanState => "02" },
    parse => { "03450300"  => "fanState:off",
               "03450301"  => "fanState:low",
               "03450302"  => "fanState:high",
               "03450303"  => "fanState:medium",
               "03450304"  => "fanState:circulation",
               "03450305"  => "fanState:humidityCirc",
               "03450306"  => "fanState:rightLeftCirc",
               "03450307"  => "fanState:upDownCirc",
               "03450308"  => "fanState:quietCirc"
               } } ,
  CLIMATE_CONTROL_SCHEDULE => { id => '46',
    set   => { ccs                => 'ZWave_ccsSet("%s")' ,
               ccsOverride        => 'ZWave_ccsSetOverride("%s")'},
    get   => { ccs                => 'ZWave_ccsGet("%s")',
               ccsAll             => 'ZWave_ccsAllGet($hash)',
               ccsChanged         => "04",
               ccsOverride        => "07" },
    parse => { "..46(..)(.*)" => 'ZWave_ccsParse($1,$2)' }},
  THERMOSTAT_SETBACK       => { id => '47' },
  RATE_TBL_CONFIG          => { id => '48' },
  RATE_TBL_MONITOR         => { id => '49' },
  TARIFF_CONFIG            => { id => '4a' },
  TARIFF_TBL_MONITOR       => { id => '4b' },
  DOOR_LOCK_LOGGING        => { id => '4c',
    get   =>  { doorLockLoggingRecordsSupported   => '01',
                doorLockLoggingRecord             => '03%02x' },
    parse => { "034c02(.*)" => '"doorLockLoggingRecordsSupported:".hex($val)',
               "..4c04(.*)" => 'ZWave_doorLLRParse($hash, $1)'} },
  NETWORK_MANAGEMANT_BASIC => { id => '4d' },
  SCHEDULE_ENTRY_LOCK      => { id => '4e', # V1, V2, V3
    get   =>  { scheduleEntryLockTypeSupported  => '09',
                scheduleEntryLockWeekDay        => "04%02x%02x",
                scheduleEntryLockYearDay        => "07%02x%02x",
                scheduleEntryLockDailyRepeating => "0e%02x%02x",
                scheduleEntryLockTimeOffset     => '0b'
              },
    set   =>  { scheduleEntryLockSet =>
                  'ZWave_scheduleEntryLockSet($hash, "%s")',
                scheduleEntryLockAllSet =>
                  'ZWave_scheduleEntryLockAllSet($hash, "%s")',
                scheduleEntryLockWeekDaySet =>
                  'ZWave_scheduleEntryLockWeekDaySet($hash, "%s")',
                scheduleEntryLockYearDaySet =>
                  'ZWave_scheduleEntryLockYearDaySet($hash, "%s")',
                scheduleEntryLockTimeOffsetSet =>
                  'ZWave_scheduleEntryLockTimeOffsetSet($hash, "%s")',
                scheduleEntryLockYearDailyRepeatingSet =>
                  'ZWave_scheduleEntryLockDailyRepeatingSet($hash, "%s")'
              },
    parse =>  { "..4e0a(.*)" =>
                  'ZWave_scheduleEntryLockTypeSupportedParse($hash, $1)',
                "..4e05(.{14})" =>
                  'ZWave_scheduleEntryLockWeekDayParse($hash, $1)',
                "..4e08(.{24})" =>
                  'ZWave_scheduleEntryLockYearDayParse($hash, $1)',
                "..4e0c(.{6})" =>
                  'ZWave_scheduleEntryLockTimeOffsetParse($hash, $1)',
                "..4e0f(.{14})" =>
                  'ZWave_scheduleEntryLockDailyRepeatingParse($hash, $1)'
              }},
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
  NETWORK_SCHEDULE         => { id => '53', # V1, Schedule
    get   => {  scheduleSupported => "01",
                schedule          => "04%02x",
                scheduleState     => "08"},
    set   => {  scheduleRemove    => "06%02x",
                schedule          => 'ZWave_scheduleSet($hash, "%s")',
                scheduleState     => "07%02x%02x"},
    parse => { "..5302(.*)" => 'ZWave_scheduleSupportedParse($hash, $1)',
               "..5305(.*)" => 'ZWave_scheduleParse($hash, $1)',
               "..5309(.*)" => 'ZWave_scheduleStateParse($hash, $1)' } },
  NETWORK_MANAGEMENT_PRIMARY=>{ id => '54' },
  TRANSPORT_SERVICE        => { id => '55' },
  CRC_16_ENCAP             => { id => '56' }, # Parse is handled in the code
  APPLICATION_CAPABILITY   => { id => '57' },
  ZIP_ND                   => { id => '58' },
  ASSOCIATION_GRP_INFO     => { id => '59',
    get   => { associationGroupName => "01%02x",
               associationGroupCmdList => "0500%02x" },
    parse => { "..5902(..)(.*)"=> '"assocGroupName_".hex($1).":".pack("H*",$2)',
               "..5906(..)..(.*)"=> 'ZWave_assocGroupCmdList($1,$2)' } },
  DEVICE_RESET_LOCALLY     => { id => '5a',
    parse => { "025a01"    => "deviceResetLocally:yes" } },
  CENTRAL_SCENE            => { id => '5b',
    parse => { "055b03...0(..)" => '"cSceneSet:".hex($1)',
               "055b03...1(..)" => '"cSceneDimEnd:".hex($1)',
               "055b03...2(..)" => '"cSceneDim:".hex($1)',
               "055b03...3(..)" => '"cSceneDouble:".hex($1)',
               "055b03...([4-6])(..)" => '"cSceneMultiple_".
                                                (hex($1)-1).":".hex($2)'}  },
  IP_ASSOCIATION           => { id => '5c' },
  ANTITHEFT                => { id => '5d' },
  ZWAVEPLUS_INFO           => { id => '5e',
    get   => { zwavePlusInfo=>"01"},
    parse => { "095e02(..)(..)(..)(....)(....)"
                                => 'ZWave_plusInfoParse($1,$2,$3,$4,$5)'} },
  ZIP_GATEWAY              => { id => '5f' },
  MULTI_CHANNEL            => { id => '60',  # Version 2, aka MULTI_INSTANCE
    set   => { mcCreateAll => 'ZWave_mcCreateAll($hash,"")' },
    get   => { mcEndpoints => "07",
               mcCapability=> "09%02x"},
    parse => { "^0[45]6008(..)(..)" => '"mcEndpoints:total ".hex($2).'.
                                 '(hex($1)&0x80 ? ", dynamic":"").'.
                                 '(hex($1)&0x40 ? ", identical":", different")',
               "^..600a(.*)"=> 'ZWave_mcCapability($hash, $1)' },
    init  => { ORDER=>49, CMD => '"set $NAME mcCreateAll"' } },
  ZIP_PORTAL               => { id => '61' },
  DOOR_LOCK                => { id => '62', # V2
    set   => { doorLockOperation   => 'ZWave_DoorLockOperationSet($hash, "%s")',
               doorLockConfiguration =>
                  'ZWave_DoorLockConfigSet($hash, "%s")' },
    get   => { doorLockOperation      => '02',
               doorLockConfiguration  => '05'},
    parse => { "..6203(.*)" => 'ZWave_DoorLockOperationReport($hash, $1)',
               "..6206(.*)" => 'ZWave_DoorLockConfigReport($hash, $1)'} },
  USER_CODE                => { id => '63',
    set   => { userCode => 'ZWave_userCodeSet("%s")' },
    get   => { userCode => "02%02x" ,
               userCodeUsersNumber => "04"},
    parse => { "..6303(..)(..)(.*)" =>
                'sprintf("userCode:id %d status %d code %s", $1, $2, $3)' ,
              "..6305(..)" => '"userCodeUsersNumber:".hex($1)'}
    },
  APPLIANCE                => { id => '64' },
  DMX                      => { id => '65' },
  BARRIER_OPERATOR         => { id => '66',
    set   => { barrierClose=> "0100",
               barrierOpen => "01ff" },
    get   => { barrierState=> "02" },
    parse => { "..6603(..)"=> '($1 eq "00" ? "barrierState:closed" :
                               ($1 eq "fc" ? "barrierState:closing" :
                               ($1 eq "fd" ? "barrierState:stopped" :
                               ($1 eq "fe" ? "barrierState:opening" :
                               ($1 eq "ff" ? "barrierState:open" :
                                             "barrierState:".hex($1))))))'} },
  NETWORK_MANAGEMENT_INSTALL=> { id => '67' },
  ZIP_NAMING               => { id => '68' },
  MAILBOX                  => { id => '69' },
  WINDOW_COVERING          => { id => '6a' },
  IRRIGATION               => { id => '6b' },
  SUPERVISION              => { id => '6c' },
  ENTRY_CONTROL            => { id => '6f' },
  CONFIGURATION            => { id => '70',
    set   => { configDefault=>"04%02x80",
               configByte  => "04%02x01%02x",
               configWord  => "04%02x02%04x",
               configLong  => "04%02x04%08x" },
    get   => { config      => "05%02x",
               configAll   => 'ZWave_configAllGet($hash)' },
    parse => { "^..70..(..)(..)(.*)" => 'ZWave_configParse($hash,$1,$2,$3)'} },
  ALARM                    => { id => '71',
    set   => {
      alarmnotification   => 'ZWave_ALARM_06_Set("%s")',    # >=V2
      },
    get   => {
      alarmEventSupported => 'ZWave_ALARM_01_Get("%s")',    # >=V3
      alarm               => 'ZWave_ALARM_04_Get(1, "%s")', # >=V1
      alarmWithType       => 'ZWave_ALARM_04_Get(2, "%s")', # >=V2
      alarmWithTypeEvent  => 'ZWave_ALARM_04_Get(3, "%s")', # >=V3
      alarmTypeSupported  => "07",                          # >=V2
      },
    parse => {
      "..7102(.*)"          => 'ZWave_ALARM_02_Report($1)', # >=V3
      "..7105(..)(..)(.*)"  =>
                'ZWave_ALARM_05_Report($hash, $1, $2, $3)', # >=V1
      "..7108(.*)"          => 'ZWave_ALARM_08_Report($1)', # >=V2
      },
    },
  MANUFACTURER_SPECIFIC    => { id => '72',
    get   => { model       => "04" },
    parse => { "0[8a]7205(....)(....)(....)(.*)"
                          => 'ZWave_mfsParse($hash,$1,$2,$3,0)',
               "0[8a]7205(....)(....)(.{4})(.*)"
                          => 'ZWave_mfsParse($hash,$1,$2,$3,1)',
               "0[8a]7205(....)(.{4})(.{4})(.*)"
                          => 'ZWave_mfsParse($hash,$1,$2,$3,2)' },
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
    parse => { "0.8003(..)"=> '"battery:".($1 eq "ff" ? "low":hex($1)." %")'} },
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
    parse => { "..8404(.*)"=> '"cmdSet:wakeupInterval $1"',
               "..8405"    => 'cmdGet:wakeupInterval',
               "..8406(......)(..)" =>
                        '"wakeupReport:interval ".hex($1)." target ".hex($2)',
               "..8407"    => 'wakeup:notification',
               "..8408"    => 'cmdSet:wakeupNoMoreInformation',
               "..8409"    => 'cmdGet:wakeupIntervalCapabilities',
               "..840a(......)(......)(......)(......)" =>
                        '"wakeupIntervalCapabilitiesReport:min ".hex($1).'.
                        '" max ".hex($2)." default ".hex($3)." step ".hex($4)'},
    init  => { ORDER=>11, CMD => '"set $NAME wakeupInterval 86400 $CTRLID"' } },
  ASSOCIATION              => { id => '85',
    set   => { associationAdd => "01%02x%02x*",
               associationDel => "04%02x%02x*" },
    get   => { association          => "02%02x",
               associationGroups    => "05",
               associationAll       => 'ZWave_associationAllGet($hash,"")' },
    parse => { "..8503(..)(..)..(.*)" => 'ZWave_assocGroup($homeId,$1,$2,$3)',
               "..8506(..)"           => '"assocGroups:".hex($1)' },
    init  => { ORDER=>10, CMD=> '"set $NAME associationAdd 1 $CTRLID"' } },
  VERSION                  => { id => '86',
    get   => { version      => "11",
               versionClass => 'ZWave_versionClassGet($hash, "%s")',
               versionClassAll => 'ZWave_versionClassAllGet($hash)'},
    parse => { "028611"             => "cmdGet:version",
               "078612(..........)" => 'sprintf("version:Lib %d Prot '.
                '%d.%02d App %d.%d", unpack("C*",pack("H*","$1")))',
               "098612(..............)" => 'sprintf("version:Lib %d Prot '.
                 '%d.%02d App %d.%d HW %d FWCounter %d",'.
                 'unpack("C*",pack("H*","$1")))',
               "0b8612(..................)" => 'sprintf("version:Lib %d Prot '.
                 '%d.%02d App %d.%d HW %d FWCounter %d FW %d.%d",'.
                 'unpack("C*",pack("H*","$1")))',
               "048614(..)(..)"     => '"versionClass_".hex($1).":".hex($2)' },
   init  => { ORDER=> 1, CMD => '"get $NAME versionClassAll"' } },
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
  TIME                     => { id => '8a' ,
    set   => { timeOffset   => 'ZWave_timeOffsetSet($hash, "%s")' },
    get   => { time         => "01",
               date         => "03",
               timeOffset   => "06" },
    parse => { "..8a04(.*)" => 'ZWave_dateReport($hash,$1)',
               "..8a02(.*)" => 'ZWave_timeReport($hash,$1)',
               "..8a07(.*)" => 'ZWave_timeOffsetReport($hash,$1)'} },
  TIME_PARAMETERS          => { id => '8b',
    set   => { timeParameters => 'ZWave_timeParametersSet($hash, "%s")'},
    get   => { timeParameters => "02"},
    parse => { "..8b02"      => 'timeParametersGet',
               "..8b03(.*)"  => 'ZWave_timeParametersReport($hash, $1)' } },
  GEOGRAPHIC_LOCATION      => { id => '8c' },
  COMPOSITE                => { id => '8d' },
  MULTI_CHANNEL_ASSOCIATION=> { id => '8e',    # aka MULTI_INSTANCE_ASSOCIATION
    set   => { mcaAdd      => "01%02x%02x*",
               mcaDel      => "04%02x*" },
    get   => { mca         => "02%02x",
               mcaGroupings=> "05",
               mcaAll      => 'ZWave_mcaAllGet($hash,"")' },
    parse => { "..8e03(..)(..)..(.*)" => 'ZWave_mcaReport($homeId,$1,$2,$3)',
               "..8e06(.*)"=> '"mcaGroups:".hex($1)' } },

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
    set   => { "secSupportedReport" => 'ZWave_sec($hash, "02")', },
    parse => { "..9803(.*)"=> 'ZWave_secSupported($hash, $1)',
               "..9840"    => 'ZWave_secNonceRequestReceived($hash)',
               "..9880(.*)"=> 'ZWave_secNonceReceived($hash, $1)',
               "..9881(.*)"=> 'ZWave_secDecrypt($hash, $1, 0)',
               "..98c1(.*)"=> 'ZWave_secDecrypt($hash, $1, 1)' } },
  AV_TAGGING_MD            => { id => '99' },
  IP_CONFIGURATION         => { id => '9a' },
  ASSOCIATION_COMMAND_CONFIGURATION
                           => { id => '9b' },
  SENSOR_ALARM             => { id => '9c',
    get   => { alarm       => "01%02x" },
    parse => { "..9c02(..)(..)(..)(....)" =>
      '"alarm_type_$2:level ".hex($3)." node ".hex($1)." seconds ".hex($4)'} },
  SILENCE_ALARM            => { id => '9d' },
  SENSOR_CONFIGURATION     => { id => '9e' },
  SECURITY_S2              => { id => '9f' },
  MARK                     => { id => 'ef' },
  NON_INTEROPERABLE        => { id => 'f0' },
);

my %zwave_classVersion = (
  dimWithDuration             => { min => 2 },
  meterReset                  => { min => 2 },
  meterSupported              => { min => 2 },
  wakeupIntervalCapabilities  => { min => 2 },
  alarmTypeSupported          => { min => 2 },
  alarmnotification           => { min => 2 },
  alarmWithType               => { min => 2 },
  alarmWithTypeEvent          => { min => 3 },
  alarmEventSupported         => { min => 3 },
  tmEnergySaveHeating         => { min => 2 },
  tmFullPower                 => { min => 3 },
  tmManual                    => { min => 3 },
);

my %zwave_cmdArgs = (
  set => {
    dim          => "slider,0,1,99",
    indicatorDim => "slider,0,1,99",
    rgb          => "colorpicker,RGB",
    configRGBLedColorForTesting => "colorpicker,RGB", # Aeon SmartSwitch 6
  },
  get => {
  },
  parse => {
  }
);

use vars qw(%zwave_parseHook);
#my %zwave_parseHook; # nodeId:regexp => fn, used by assocRequest
my %zwave_modelConfig;
my %zwave_modelIdAlias = ( "0175-0004-000a" => "devolo_Siren",
                           "010f-0301-1001" => "Fibaro_FGRM222",
                           "010f-0302-1000" => "Fibaro_FGRM222", # FGR 222
                           "010f-0203-1000" => "Fibaro_FGS223",
                           "0108-0004-000a" => "Philio_PSE02", # DLink DCH-Z510
                           "013c-0004-000a" => "Philio_PSE02", # Zipato Siren
                           "0115-0100-0102" => "ZME_KFOB" );

# Patching certain devices.
our %zwave_deviceSpecial;
%zwave_deviceSpecial = (
   devolo_Siren => {
     ALARM => {
      set => { alarmSmokeOn    =>"050000000001010000",
               alarmEmergencyOn=>"050000000007010000",
               alarmFireOn     =>"05000000000a020000",
               alarmAmbulanceOn=>"05000000000a030000",
               alarmPoliceOn   =>"05000000000a010000",
               alarmSilentOn   =>"05000000000afe0000",
               alarmDoorchimeOn=>"050000000006160000",
               alarmArmOn      =>"050000000006030000",
               alarmDisarmOn   =>"050000000006040000",
               alarmBeepOn     =>"05000000000a050000" } } },

   Fibaro_FGRM222 => {
     MANUFACTURER_PROPRIETARY => {
      set   => { positionSlat=>"010f26010100%02x",
                 positionBlinds=>"010f260102%02x00"},
      get   => { position=>"010f2602020000", },
      parse => { "0891010f260303(..)(..)" =>
                  'sprintf("position:Blind %d Slat %d",hex($1),hex($2))',
                 "0891010f260302(..)00" =>'"position:".hex($1)' } } },

   Fibaro_FGS223 => {
     ASSOCIATION => {
       init => {ORDER=>50, CMD => '"set $NAME associationDel 1 $CTRLID"'} },
     MULTI_CHANNEL_ASSOCIATION => {
       init => {ORDER=>51, CMD => '"set $NAME mcaAdd 1 0 $CTRLID 1"'} } },

   Philio_PSE02 => {
     ALARM => {
      set => { alarmEmergencyOn=>"050000000007010000",
               alarmFireOn     =>"05000000000a020000",
               alarmAmbulanceOn=>"05000000000a030000",
               alarmPoliceOn   =>"05000000000a010000",
               alarmDoorchimeOn=>"050000000006160000",
               alarmBeepOn     =>"05000000000a050000" } } },

   ZME_KFOB => {
     ZWAVEPLUS_INFO => {
      # Example only. ORDER must be >= 50
      init => { ORDER=>50, CMD => '"get $NAME zwavePlusInfo"' } } }
);

my $zwave_cryptRijndael = 0;
my $zwave_lastHashSent;
my (%zwave_link, %zwave_img);
my $zwave_activeHelpSites = "alliance,pepper"; # pepper alive again (aka zobie)
my $zwave_allHelpSites = "alliance,pepper";

# standard definitions for regular expression
# naming scheme: p<number of returned groups>_name
my $p1_m = "([0-5][0-9])"; # mm 00-59
my $p2_hm = "([01][0-9]|2[0-3]):([0-5][0-9])"; # hh:mm
my $p3_hms = "([01][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])"; # hh:mm:ss
my $p1_b = "(25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])"; # byte:0-255, 1-3 digits
my $p1_wd = "(mon|tue|wed|thu|fri|sat|sun)"; # 3 letter weekday
# ymd: yyyy-mm-dd, yyyy 4 digits, mm 2 digits 01-12, dd 2 digits 01-31
my $p3_ymd = "([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])";

sub
ZWave_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = "^[0-9A-Fa-f]+\$";
  $hash->{SetFn}     = "ZWave_Set";
  $hash->{GetFn}     = "ZWave_Get";
  $hash->{DefFn}     = "ZWave_Define";
  $hash->{UndefFn}   = "ZWave_Undef";
  $hash->{AttrFn}    = "ZWave_Attr";
  $hash->{ParseFn}   = "ZWave_Parse";
  no warnings 'qw';
  my @attrList = qw(
    IODev
    WNMI_delay
    classes
    disable:0,1
    disabledForIntervals
    do_not_notify:noArg
    dummy:noArg
    eventForRaw
    extendedAlarmReadings:0,1,2
    ignore:noArg
    ignoreDupMsg:noArg
    neighborListPos
    noExplorerFrames:noArg
    noWakeupForApplicationUpdate:noArg
    secure_classes
    showtime:noArg
    vclasses
    useMultiCmd:noArg
    useCRC16:noArg
    zwaveRoute
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;

  map { $zwave_id2class{lc($zwave_class{$_}{id})} = $_ } keys %zwave_class;

  $hash->{FW_detailFn} = "ZWave_fhemwebFn";
  $hash->{FW_deviceOverview} = 1;

  eval { require Crypt::Rijndael; };
  if($@) {
    Log 3, "ZWave: cannot load Crypt::Rijndael, SECURITY class disabled";
  } else {
    $zwave_cryptRijndael = 1;
  }

  ################
  # Read in the pepper/alliance translation table
  for my $n (split(",", $zwave_allHelpSites)) {
    my $fn = $attr{global}{modpath}."/FHEM/lib/zwave_${n}links.csv.gz";
    my $gz = gzopen($fn, "rb");
    if($gz) {
      my $line;
      while($gz->gzreadline($line)) {
        chomp($line);
        my @a = split(",",$line);
        $zwave_link{$n}{lc($a[0])} = $a[1];
        $zwave_img{$n}{lc($a[0])} = $a[2];
      }
      $gz->gzclose();
    } else {
      Log 3, "Can't open $fn: $!";
    }
  }

  # Create cache directory
  my $fn = $attr{global}{modpath}."/www/deviceimages";
  if(! -d $fn) { mkdir($fn) || Log 3, "Can't create $fn"; }
  $fn .= "/zwave";
  if(! -d $fn) { mkdir($fn) || Log 3, "Can't create $fn"; }

}


#############################
my $zw_init_ordered;

sub
ZWave_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = shift @a;
  my $type = shift @a; # always ZWave

  my $u = "wrong syntax for $name: define <name> ZWave homeId id [classes]";
  return $u if(int(@a) < 2 || int(@a) > 3);

  my $homeId = lc(shift @a);
  my $id     = shift @a;

  return "define $name: wrong homeId ($homeId): need an 8 digit hex value"
                   if( ($homeId !~ m/^[a-f0-9]{8}$/i) );
  return "define $name: wrong id ($id): need a number"
                   if( ($id !~ m/^\d+$/i) );

  $hash->{ZWaveSubDevice} = ($id > 255 ? "yes" : "no");
  $id = sprintf("%0*x", ($id > 255 ? 4 : 2), $id);
  $hash->{homeId} = $homeId;
  $hash->{nodeIdHex} = $id;

  $modules{ZWave}{defptr}{"$homeId $id"} = $hash;
  my $proposed;
  if($init_done) { # Use the right device while inclusion is running
    for my $p (devspec2array("TYPE=ZWDongle|ZWCUL|FHEM2FHEM")) {
      $proposed = $p if($defs{$p}{homeId} && $defs{$p}{homeId} eq $homeId);
    }
  }
  AssignIoPort($hash, $proposed);
  $hash->{".vclasses"} = {};

  if(@a) {      # Autocreate: set the classes, execute the init calls
    asyncOutput($hash->{IODev}{addCL}, "created $name") if($hash->{IODev});
    ZWave_SetClasses($homeId, $id, undef, $a[0]);
  }

  if($init_done) {
    ZWave_setEndpoints($hash);
  } else {
   if(!$zw_init_ordered) {
     $zw_init_ordered = 1;
     InternalTimer(1, "ZWave_setEndpoints", $hash, 0);
   }
  }

  return undef;
}

sub
ZWave_setEndpoints($)
{
  my $mp = $modules{ZWave}{defptr};
  for my $k (sort keys %{$mp}) {
    my $h = $mp->{$k};
    delete($h->{endpointParent});
    delete($h->{endpointChildren});
  }
  for my $k (sort keys %{$mp}) {
    my $h = $mp->{$k};
    next if($h->{nodeIdHex} !~ m/(..)(..)/);
    my ($root, $lid) = ($1, $2);
    my $rd = $mp->{$h->{homeId}." ".$root};
    $h->{endpointParent} = ($rd ? $rd->{NAME} : "unknown");
    $h->{".vclasses"} = ($rd ? $rd->{".vclasses"} : {} );
    if($rd) {
      if($rd->{endpointChildren}) {
        $rd->{endpointChildren} .= ",".$h->{NAME};
      } else {
        $rd->{endpointChildren} = $h->{NAME};
      }
    }
  }
}

sub
ZWave_initFromModelfile($$$)
{
  my ($name, $ctrlId, $cfg) = @_;
  my @res;
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
ZWave_execInits($$;$)
{
  my ($hash, $min, $cfg) = @_;  # min = 50 for model-specific stuff
  my $cl = $attr{$hash->{NAME}}{classes};
  return "" if(!$cl);
  my @clList = split(" ", $cl);
  my (@initList, %seen);

  foreach my $cl (@clList) {
    next if($seen{$cl});
    $seen{$cl} = 1;
    my $ptr = ZWave_getHash($hash, $cl, "init");
    $ptr->{CC} = $cl if($ptr);
    push @initList, $ptr if($ptr && $ptr->{ORDER} >= $min);
  }

  my $NAME = $hash->{NAME};
  my $iodev = $hash->{IODev};
  my $homeReading = ReadingsVal($iodev->{NAME}, "homeId", "") if($iodev);
  my $CTRLID=hex($1) if($homeReading && $homeReading =~ m/CtrlNodeIdHex:(..)/);

  my @cmd;
  foreach my $i (sort { $a->{ORDER}<=>$b->{ORDER} } @initList) {
    my $version = $hash->{".vclasses"}{$i->{CC}};
    push @cmd, eval $i->{CMD} if(!defined($version) || $version > 0);
  }

  push @cmd, ZWave_initFromModelfile($hash->{NAME}, $CTRLID, $cfg)
    if($cfg); # model specific init, called from "get model"

  foreach my $cmd (@cmd) {
    my $ret = AnalyzeCommand(undef, $cmd);
    Log 1, "ZWAVE INIT: $cmd: $ret" if ($ret);
  }
  return "";
}


sub
ZWave_neighborList($)
{
  my ($hash) = @_;
  my $id = $hash->{nodeIdHex};

  # GET_ROUTING_TABLE_LINE, no dead links, include routing neighbors
  IOWrite($hash, "", "0080${id}0100");

  no strict "refs";
  my $iohash = $hash->{IODev};
  my $fn = $modules{$iohash->{TYPE}}{ReadAnswerFn};
  my ($err, $data) = &{$fn}($iohash, "neighborList", "^0180") if($fn);
  use strict "refs";

  return $err if($err);
  $data =~ s/^0180//;
  $data = zwlib_parseNeighborList($iohash, $data);
  readingsSingleUpdate($hash, "neighborList", $data, 1) if($hash);
  return $data;
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

  my $id = $hash->{nodeIdHex};
  if($id !~ m/(....)/) { # not multiChannel
    if($type eq "set") {
      $cmdList{neighborUpdate} = { fmt=>"48$id",     id=>"", ctrlCmd=>1 };
      $cmdList{returnRouteAdd} = { fmt=>"46$id%02x", id=>"", ctrlCmd=>1 };
      $cmdList{returnRouteDel} = { fmt=>"47$id",     id=>"", ctrlCmd=>1 };
      my $iohash = $hash->{IODev};
      if($iohash && ReadingsVal($iohash->{NAME}, "sucNodeId","no") ne "no") {
        $cmdList{sucRouteAdd} = { fmt=>"51$id", id=>"", ctrlCmd=>1 };
        $cmdList{sucRouteDel} = { fmt=>"55$id", id=>"", ctrlCmd=>1 };
      }
    }
    $cmdList{neighborList}{fmt} = "x" if($type eq "get"); # Add meta command
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
    my $mc = ReadingsVal($hash->{NAME}, "modelConfig", "");
    foreach my $lcmd (sort keys %cmdList) {
      if($mc && $zwave_cmdArgs{$type}{"$mc$lcmd"}) {
        push @list, "$lcmd:".$zwave_cmdArgs{$type}{"$mc$lcmd"};

      } elsif($zwave_cmdArgs{$type}{$lcmd}) {
        push @list, "$lcmd:$zwave_cmdArgs{$type}{$lcmd}";

      } elsif($cmdList{$lcmd}{fmt} !~ m/%/) {
        push @list, "$lcmd:noArg";

      } else {
        push @list, $lcmd;

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
  SetExtensionsCancel($hash) if($type eq "set");

  return "" if(IsDisabled($name));

  return ZWave_neighborList($hash) if($cmd eq "neighborList");

  ################################
  # ZW_SEND_DATA,nodeId,CMD,ACK|AUTO_ROUTE
  my $cmdFmt = $cmdList{$cmd}{fmt};
  my $cmdId  = $cmdList{$cmd}{id};
  # 0x05=AUTO_ROUTE+ACK, 0x20: ExplorerFrames

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

  if($cmd =~ m/^config/ && $cmd ne "configAll") {
    my ($err, $lcmd) =
        ZWave_configCheckParam($hash, $type, $cmd, $cmdFmt, @a);
    return $err if($err);
    $cmdFmt = $lcmd;

  } else {
    $cmdFmt = sprintf($cmdFmt, @a) if($nArg);
    $@ = undef;
    my ($err, $ncmd) = eval($cmdFmt) if($cmdFmt !~ m/^\d/);
    return $err if($err);
    return $@ if($@);
    $cmdFmt = $ncmd if(defined($ncmd));
    return "" if($ncmd && $ncmd eq "EMPTY"); # configAll
  }

  Log3 $name, 3, "ZWave $type $name $cmd ".join(" ", @a);

  my ($baseClasses, $baseHash) = ($classes, $hash);
  delete($hash->{lastChannelUsed});
  if($id =~ m/(..)(..)/) {  # Multi-Channel, encapsulate
    my ($baseId,$ch) = ($1, $2);
    $id = $baseId;
    $cmdFmt = "0d00$ch$cmdId$cmdFmt";
    $cmdId = "60";  # MULTI_CHANNEL
    $baseHash = $modules{ZWave}{defptr}{"$hash->{homeId} $baseId"};
    $baseClasses = AttrVal($baseHash->{NAME}, "classes", "");
    $baseHash->{lastChannelUsed} = $name;
  }

  my $data;
  if(!$cmdId) {
    $data = $cmdFmt;
    $data .= ZWave_callbackId($baseHash);

  } else {
    my $len = sprintf("%02x", length($cmdFmt)/2+1);
    my $cmdEf  = (AttrVal($name, "noExplorerFrames", 0) == 0 ? "25" : "05");
    $data = "13$id$len$cmdId${cmdFmt}$cmdEf"; # 13==SEND_DATA
    $data .= ZWave_callbackId($baseHash);
  }

  if($type eq "get" && $hash->{CL} && !ZWave_isWakeUp($hash)) {
    if(!$hash->{asyncGet}) {            # Wait for the result for frontend cmd
      my $tHash = { hash=>$hash, CL=>$hash->{CL}, re=>"^000400${id}..$cmdId"};
      $hash->{asyncGet} = $tHash;
      InternalTimer(gettimeofday()+4, sub {
        asyncOutput($tHash->{CL}, "Timeout reading answer for $cmd");
        delete($hash->{asyncGet});
      }, $tHash, 0);
    }
  }

  if ($data =~ m/(......)(....)(.*)(....)/) {
    my $cc_cmd=$2;
    my $payload=$3;

    #check message here for needed encryption (SECURITY)
    if(ZWave_secIsSecureClass($hash, $cc_cmd)) {
      ZWave_secStart($hash);
      # message stored in hash, will be processed when nonce arrives
      my $cmd2 = "$type $name $cmd";
      $cmd2 .= " ".join(" ", @a) if(@a);
      ZWave_secPutMsg($hash, $cc_cmd . $payload, $cmd2);
      ZWave_secAddToSendStack($baseHash, '9840');
      return;
    }
  }

  my $r = ZWave_addToSendStack($baseHash, $type, $data);
  return (AttrVal($name,"verbose",3) > 2 ? $r : undef) if($r);

  if($type ne "get") {
    if(!$cmdId) {
      ZWave_processSendStack($baseHash, "next");
    }
    $cmd .= " ".join(" ", @a) if(@a);
    my $iohash = $hash->{IODev};
    my $withSet = ($iohash->{showSetInState} && !$cmdList{$cmd}{ctrlCmd});
    readingsSingleUpdate($hash, "state", $withSet ? "set_$cmd" : $cmd, 1);

  }

  return undef;
}

sub
ZWave_SCmd($$@)
{
  my ($type, $hash, @a) = @_;
  if($hash->{secInProgress} && !(@a < 2 || $a[1] eq "?")) {
    my %h = ( T => $type, A => \@a );
    push @{$hash->{secStack}}, \%h;
    return ($type eq "get" ?
            "Secure operation in progress, executing in background" : "");
  }
  return ZWave_Cmd($type, $hash, @a);
}


sub ZWave_Set($@) { return ZWave_SCmd("set", shift, @_); }
sub ZWave_Get($@) { return ZWave_SCmd("get", shift, @_); }

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
ZWave_ccCapability($$)
{
  my ($l,$h) = @_;
  my @names = ("WarmWhite","ColdWhite","Red","Green",
               "Blue","Amber","Cyan","Purple","Indexed");
  my $x = hex($l)+256*hex($h);
  my @ret = "ccCapability:";
  for(my $i=0; $i<int(@names); $i++) {
    push @ret,$names[$i] if($x & (1<<$i));
  }
  return join(" ",@ret);
}

sub
ZWave_scheduleEntryLockSet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  return ("wrong format, see commandref", "")
    if($arg !~ m/([0-2]?[0-9]?[0-9]) ((en|dis)abled)/);
  return ("User Identifier: only 0-255 allowed", "") if (($1<0) || ($1>255));

  my $rt = sprintf("01%02x%02x", $1, ($2 eq "enabled") ? "01" : "02");
  return ("",$rt);

}

sub
ZWave_scheduleEntryLockAllSet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  return ("wrong format, see commandref", "")
    if($arg !~ m/((en|dis)abled)/);

  my $rt = sprintf("02%02x", ($1 eq "enabled") ? "01" : "02");
  return ("",$rt);

}

sub
ZWave_scheduleEntryLockWeekDayParse ($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(..)(..)(..)(..)(..)/);

  my $userId          = sprintf("userID: %d", hex($1));
  my $scheduleSlotId  = sprintf("slotID: %d", hex($2));

  # Attention! scheduleEntryLock use different definition of weekday!
  my @dow = ("sun","mon","tue","wed","thu","fri","sat");
  my $dayOfWeek       = (hex($3) < 7) ? $dow[hex($3)] : "invalid";


  my $start           = sprintf("%02d:%02d", hex($4), hex($5));
  my $end             = sprintf("%02d:%02d", hex($6), hex($7));

  my $rt1 = sprintf ("weekDaySchedule_%d:", hex($1));
  $rt1 .= "$userId $scheduleSlotId $dayOfWeek $start $end";
  return ($rt1);
}

sub
ZWave_scheduleEntryLockWeekDaySet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if($arg !~
    m/([01]) $p1_b $p1_b $p1_wd $p2_hm $p2_hm/) {
    return ("wrong format, see commandref", "");
  }

  if (($2>255) || ($3>255)) {
    return ("values our of range, see commandref", "");
  }

  # Attention! scheduleEntryLock use different definition of weekday!
  my @dow = ("sun","mon","tue","wed","thu","fri","sat");

  my $wd;
  map { $wd=sprintf("%02x",$_) if($dow[$_] eq $4) }(0..int($#dow));
  return ("Unknown weekday $4, use one of ".join(" ", @dow), "")
    if(!defined($wd));

  my $rt = sprintf("03%02x%02x%02x%02x%02x%02x%02x%02x",
                    $1,$2,$3,$wd,$5,$6,$7,$8);

  return ("",$rt);
}

sub
ZWave_scheduleEntryLockDailyRepeatingParse ($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(..)(..)(..)(..)(..)/);

  my $userID        = sprintf ("userID: %d", hex($1));
  my $scheduleID    = sprintf ("slotID: %d", hex($2));

  # bit field for week day: b7 reserved, b6 sat, b5 fri, ..., b0 sun
  my $w = hex($3);
  #my $wd = sprintf("weekDaySchedule: %07b ", $w);
  my $wd = "weekDaySchedule: ";
  my $nu = "...";
  $wd .= (($w & 0x02) == 0x02) ? "mon" : $nu;
  $wd .= (($w & 0x04) == 0x04) ? "tue" : $nu;
  $wd .= (($w & 0x08) == 0x08) ? "wed" : $nu;
  $wd .= (($w & 0x10) == 0x10) ? "thu" : $nu;
  $wd .= (($w & 0x20) == 0x20) ? "fri" : $nu;
  $wd .= (($w & 0x40) == 0x40) ? "sat" : $nu;
  $wd .= (($w & 0x01) == 0x01) ? "sun" : $nu;

  my $start     = sprintf("Start: %02d:%02d"    , hex($4), hex($5));
  my $duration  = sprintf("Duration: %02d:%02d" , hex($6), hex($7));

  my $rt1 = sprintf ("scheduleEntryLockDailyRepeating_%d:", hex($1));
  $rt1 .= "$userID $scheduleID $wd $start $duration";
  return ($rt1);
}

sub
ZWave_scheduleEntryLockDailyRepeatingSet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if($arg !~
    m/([01]) $p1_b $p1_b ((?:[\.a-zA-Z]{3}){1,7}) $p2_hm $p2_hm/) {
    return ("wrong format, see commandref", "");
  }

  my $rt1 = sprintf("%02x%02x%02x", $1, $2, $3);
  my $rt2 = sprintf("%02x%02x%02x%02x", $5, $6, $7, $8);

  my $w = $4;
  my $wd = 0x00;
  $wd |= 0x02 if ($w =~ /mon/i);
  $wd |= 0x04 if ($w =~ /tue/i);
  $wd |= 0x08 if ($w =~ /wed/i);
  $wd |= 0x10 if ($w =~ /thu/i);
  $wd |= 0x20 if ($w =~ /fri/i);
  $wd |= 0x40 if ($w =~ /sat/i);
  $wd |= 0x01 if ($w =~ /sun/i);

  my $rt = sprintf("10$rt1%02x$rt2", $wd);
  return ("",$rt);
}

sub
ZWave_scheduleEntryLockYearDayParse ($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)/);

  my $userID        = sprintf ("userID: %d", hex($1));
  my $scheduleID    = sprintf ("slotID: %d", hex($2));
  my $startdate     = sprintf ("start: %4d-%02d-%02d %02d:%02d",
                        2000+hex($3),hex($4),hex($5),hex($6),hex($7));
  my $enddate       = sprintf ("end: %4d-%02d-%02d %02d:%02d",
                        2000+hex($8),hex($9),hex($10),hex($11),hex($12));

  my $rt1 = sprintf ("yearDaySchedule_%d:", hex($1));
  $rt1 .= "$userID $scheduleID $startdate $enddate";
  return ($rt1);
}

sub
ZWave_scheduleEntryLockYearDaySet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if($arg !~
    m/([01]) $p1_b $p1_b $p3_ymd $p2_hm $p3_ymd $p2_hm/) {
    return ("wrong format, see commandref", "");
  }

  my $sy = $4-2000;
  my $ey = $9-2000;
  if (($sy < 0) || ($sy > 255) || ($ey < 0) || ($ey > 255)) {
    Log3 $name, 1, "$name: year out of range";
    return ("wrong value for year, only 2000-2255 allowed","");
  }; # no sanity check of date (e.g. 2016-02-31 will pass)

  my $rt = sprintf("06%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                    $1, $2, $3, $sy, $5, $6, $7, $8, $ey, $10, $11, $12, $13);
  return ("",$rt);
}

sub
ZWave_scheduleEntryLockTimeOffsetParse ($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(..)/);

  my $sTZO  = ((hex($1) & 0x80) == 0x80) ? '-' : '+';
  my $TZO   = sprintf("TZO: %s%02d:%02d", $sTZO, (hex($1) & 0x7f), hex($2));

  my $sDST  = ((hex($3) & 0x80) == 0x80) ? '-' : '+';
  my $DST   = sprintf("DST: %s%02d", $sDST, (hex($3) & 0x7f));

  my $rt1 = "scheduleEntryLockTimeOffset: $TZO $DST";
  return ($rt1);
}

sub
ZWave_scheduleEntryLockTimeOffsetSet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if($arg !~ m/([\+\-])$p2_hm ([\+\-])$p1_b/) {
    return ("wrong format, see commandref", "");
  }

  my $hTZO = $2 | (($1 eq '-') ? 0x80 : 0x00);
  my $mTZO = $3;
  my $mDST = $5 | (($4 eq '-') ? 0x80 : 0x00);

  my $rt = sprintf("0d%02x%02x%02x", $hTZO, $mTZO, $mDST);

  return ("",$rt);
}

sub
ZWave_scheduleEntryLockTypeSupportedParse ($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(.*)/);

  my $numWDslots = sprintf ("WeekDaySlots: %d", hex($1));
  my $numYDslots = sprintf ("YearDaySlots: %d", hex($2));

  # only for V3
  my $numDailySlots = '';
  $numDailySlots = sprintf (" DailyRepeatingSlots: %d", hex($3)) if ($3);

  my $rt1 = "scheduleEntryLockEntryTypeSupported:"
            ." $numWDslots $numYDslots$numDailySlots";
  return ($rt1);
}

sub
ZWave_thermostatSetpointGet($)
{
  my ($type) = @_;

  $type  = (($type eq "%s") ? "1" : $type);
  return ("wrong format, only 1-15 allowed","")
    if ($type !~ m/^(1[0-5]?|[0]?[1-9])$/);
  return("",sprintf('02%02x', $type & 0x0f));
}

sub
ZWave_thermostatSetpointSet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  my $p1_temp   = "([\+\-]?(?:(?:[0-9]+(?:\.[0-9]*)?)|(?:\.[0-9]+)))";
  my $p1_scale  = "([cC|fF])";
  my $p1_type   = "(1[0-5]?|[0]?[1-9])";
  my $p1_prec   = "([0-7])";
  my $p1_size   = "([124])";

  if($arg !~
    m/$p1_temp+ ?$p1_scale?+ ?$p1_type?+ ?$p1_prec?+ ?$p1_size?+/) {
    return ("wrong format, see commandref", "");
  }

  my $temp  = $1;
  my $scale = (defined $2) ? $2 : "c";          # default to c = celsius
  $scale    = (lc($scale) eq "f") ? 1 : 0;
  my $type  = ((defined $3) ? $3 : 1) & 0x0f;   # default to 1 = heating
  my $prec  = ((defined $4) ? $4 : 1) & 0x07;   # default to 1 decimal
  my $size  = ((defined $5) ? $5 : 2) & 0x07;   # default to 2 byte size

  my $sp = int($temp * (10 ** $prec));
  my $max = (2 ** (8*$size-1)) - 1;
  my $min = -1 * (2 ** (8*$size-1));

  if (($sp > $max) || ($sp < $min)) {
    my $rt = sprintf("temperature value out of range for given "
                      ."size and precision [%0.*f, %0.*f]",
                      $prec, $min/(10**$prec), $prec, $max/(10**$prec));
    return ($rt, "");
  }

  $sp   = ($sp < 0) ? $sp + 2**(8*$size) : $sp;
  $sp   = sprintf("%0*x", 2*$size, $sp);
  $type = sprintf("%02x", $type);
  my $precScaleSize = sprintf("%02x", ($size | ($scale<<3) | ($prec<<5)));
  my $rt = "01$type$precScaleSize$sp";

  return ("",$rt);
}

sub
ZWave_thermostatSetpointParse ($$)
{
  my ($hash, $val) = @_;
  my $name = $hash->{NAME};

  return if($val !~ m/^(..)(..)(.*)/);

  my @setpointtype =  ( # definition from V3
                        "notSupported",
                        "heating",
                        "cooling",
                        "notSupported1",
                        "notSupported2",
                        "notSupported3",
                        "notSupported4",
                        "furnance",
                        "dryAir",
                        "moistAir",
                        "autoChangeover",
                        "energySaveHeating",
                        "energySaveCooling",
                        "awayHeating",
                        "awayCooling",
                        "fullPower"
                      );
  my $type  = $setpointtype[(hex($1) & 0x0f)];
  my $prec  = (hex($2) & 0xe0)>>5;
  my $scale = (((hex($2) & 0x18)>>3) == 1) ? "F": "C";
  my $size  = (hex($2) & 0x07);

  if (length($3) != $size*2) {
    Log3 $name, 1, "$name: THERMOSTAT_SETPOINT_REPORT "
                        ."wrong number of bytes received";
    return;
  }
  my $sp = hex($3);
  $sp -= (2 ** ($size*8)) if $sp >= (2 ** ($size*8-1));
  $sp = $sp / (10 ** $prec);

  # output temperature with variable decimals as reported (according to $prec)
  my $rt = sprintf("setpointTemp:%0.*f %s %s", $prec, $sp, $scale, $type);

  return ($rt);
}

sub
ZWave_thermostatSetpointSupportedParse ($$)
{
  # only defined for version >= V3
  my ($hash, $val) = @_;
  my $name = $hash->{NAME};

  return if($val !~ m/^(.*)/);

  my $n = length($val)/2;
  my @supportedType =  ( # definition from V3
                        "none",                   # 0x00
                        "heating",                # 0x01
                        "cooling",                # 0x02
                        "furnance",               # 0x07 !type 3 to 6 left out!
                        "dryAir",                 # 0x08
                        "moistAir",               # 0x09
                        "autoChangeover",         # 0x0a
                        "energySaveHeating",      # 0x0b
                        "energySaveCooling",      # 0x0c
                        "awayHeating",            # 0x0d
                        "awayCooling",            # 0x0e
                        "fullPower"               # 0x0f
                      );
  my $numTypes = @supportedType;
  my $delimeter = '';
  my $rt = "thermostatSetpointSupported:";

  for (my $i=0; $i<$n; $i++) {
    # loop over all supplied bytes
    my $supported = hex(substr($val, $i*2, 2));
    for (my $j=$i*8; $j<$i*8+8; $j++) {
      # loop over all bits
      last if $j >= $numTypes;
      if ($supported & (2 ** ($j-$i*8))) {
        $rt .= sprintf("$delimeter$supportedType[$j]");
        $delimeter = " ";
      }
    }
  }

  return ($rt);
}

sub
ZWave_scheduleSupportedParse ($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(..)(.*)(..)/);
  my $numSupported = sprintf("num: %d", hex($1));
  my $sTimeSupport = sprintf("startTimeSupport: %06b", (hex($2) & 0x3f));
  my $fbSupport = sprintf("fallbackSupport: %1b", (hex($2) & 0x40));
  my $sEnaDis = sprintf("enableDisableSupport: %1b", (hex($2) & 0x80));
  my $numSupportedCC = sprintf("numCCs: %d", hex($3));

  my $OverrideTypes = sprintf("overrideTypes: %07b", (hex($5) & 0x7f));
  my $overrideSupport = sprintf("overrideSupport: %1b", (hex($5) & 0x80));

  my $supportedCCs = "";
  if (hex($3)>0) {
    $val = $4;
    for (my $i=0;$i<hex($3); $i++) {
      $val =~ m/(..)(..)(.*)/;
      my $supportedCC = sprintf ("CC_%d: %d CCname_%d: %s",
        $i+1, hex($1), $i+1, $zwave_id2class{lc($1)});
      my $supportedCCmask = sprintf (" CCmask_%d: %02b",
        $i+1, (hex($2) & 0x03));
      $supportedCCs .= " " if $i >0;
      $supportedCCs .= $supportedCC . $supportedCCmask;
      $val = $3;
    }

  }
  my $rt1 = "scheduleEntryLockScheduleSupported:"
    ."$numSupported $sTimeSupport $fbSupport "
    ."$sEnaDis $numSupportedCC $OverrideTypes $overrideSupport";
  my $rt2 = "scheduleEntryLockScheduleSupportedCC:$supportedCCs";
  return ($rt1, $rt2);
}

sub
ZWave_scheduleStateSet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  return ("wrong format, see commandref", "") if($arg !~ m/(.*?) (.*?)/);
  my $rt = sprintf("07%02x%02x", $1, $2);
  return ("",$rt);
}

sub
ZWave_scheduleSet ($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if($arg !~
       # 1     2     3      4    5    6     7     8    9    10    11   12
     m/(.*?) (.*?) (....)-(..)-(..) (.*?) (.*?) (..):(..) (.*?) (.*?) (.*)/) {
    return ("wrong format, see commandref", "");
  }

  my $ID            = sprintf("%02x", $1);
  my $uID           = sprintf("%02x", $2);
  my $sYear         = sprintf("%02x", $3 - 2000);
  my $sMonth        = sprintf("%02x", $4 & 0x0f);
  my $sDay          = sprintf("%02x", $5 & 0x1f);
  my $sWDay         = sprintf("%02x", $6 & 0x7f);
  my $durationType  = ($7<<5) & 0xe0;
  my $sHour         = sprintf("%02x", (($8 & 0x1f) | $durationType));
  my $sMinute       = sprintf("%02x", $9 & 0x3f);
  my $duration      = sprintf("%04x", $10);
  my $numReports    = sprintf("%02x", $11);

  my $cmdgroup ="";
  my @param;
  if (length($12)>0) { # cmd(s) given
    @param = split (" ", $12);
    Log3 $name, 1, "$name: param: $#param $12";
    for (my $i=0; $i<=$#param; $i++) {
      $cmdgroup .= sprintf("%02x%s", length($param[$i])/2, $param[$i]);
    }
  }
  my $numCmd        = sprintf("%02x", $#param+1);

  my $rt = "03" .$ID .$uID .$sYear .$sMonth .$sDay .$sWDay;
  $rt .= $sHour .$sMinute .$duration .$numReports .$numCmd .$cmdgroup;

  #~ Log3 $name, 1, "$name: $rt";
  return ("",$rt);

}

sub
ZWave_scheduleParse($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(..)(..)(..)(..)(..)(..)(....)(..)(..)(..)(.*)/);

  my $scheduleID    = sprintf ("ID: %d", hex($1));
  my $userID        = sprintf ("userID: %d", hex($2));
  my $startYear     = sprintf ("sYear: %d", 2000 + hex($3));
  my $startMonth    = sprintf ("sMonth: %d", (hex($4) & 0x0f));
  my $activeID      = sprintf ("activeID: %d", (hex($4) & 0xf0)>>4);
  my $startDay      = sprintf ("sDay: %d", (hex($5) & 0x1f));
  my $sWeekDay      = sprintf ("sWeekDay: %d", (hex($6) & 0x7f));
  my $startHour     = sprintf ("sHour: %d", (hex($7) & 0x1f));
  my $durationType  = sprintf ("durationType: %d", (hex($7) & 0x1f)>>5);
  my $startMinute   = sprintf ("sMinute: %d", (hex($8) & 0x3f));
  my $duration      = sprintf ("duration: %d", hex($9));
  my $numReports    = sprintf ("numReportsToFollow: %d", hex($10));
  my $numCmds       = sprintf ("numCmds: %d", hex ($11));
  my $cmdlen        = sprintf ("cmdLen: %d", hex($12));
  my $cmd           = sprintf ("cmd: %s", $13);

  my $rt1 = sprintf ("schedule_%d:", hex($1));
  $rt1 .= "$scheduleID $userID $startYear $startMonth $activeID ".
    "$startDay $sWeekDay $startHour $durationType $startMinute ".
    "$duration $numReports $numCmds $cmdlen $cmd";
  return ($rt1);
}

sub
ZWave_scheduleStateParse($$)
{
  my ($hash, $val) = @_;
  return if($val !~ m/^(..)(..)(..)(..)/);

  my $numSupportedIDs = sprintf ("numIDs: %d", hex($1));
  my $override = sprintf ("overried: %b", (hex($2) & 0x01));
  my $numReports = sprintf ("numReportsToFollow: %d", (hex($2) & 0xfe)>>1);
  my $ID1 = sprintf ("ID1: %d", (hex($3) & 0x0f));
  my $ID2 = sprintf ("ID2: %d", (hex($3) & 0xf0)>>4);
  my $ID3 = sprintf ("ID3: %d", (hex($4) & 0x0f));
  my $IDN = sprintf ("IDn: %d", (hex($4) & 0xf0)>>4);

  my $rt1 .= "scheduleState:$numSupportedIDs $override $numReports ".
    "$ID1 $ID2 $ID3 $IDN";
  return ($rt1);
}

sub
ZWave_assocGroupCmdList($$)
{
  my ($grp, $txt) = @_;
  $txt =~ s/(..)(..)/
            ($zwave_id2class{$1} ? $zwave_id2class{$1}:"UNKNOWN_$1").":$2 "/ge;
  return "assocGroupCmdList_".hex($grp).":$txt";
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
    }
  }
}

sub
ZWave_meterGet($)
{
  my ($scale) = @_;

  if ($scale eq "%s") { # no parameter specified, use V1 get without scale
    return("", "01");
  };

  if (($scale < 0) || ($scale > 6)) {
    return("argument must be one of: 0 to 6","");
  } else {
    $scale = $scale << 3;
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
ZWave_versionClassGet($$)
{
  my ($hash, $class) = @_;

  delete $zwave_parseHook{"$hash->{nodeIdHex}:..8614"} if ($hash->{CL});
  return("", sprintf('13%02x', $class))
        if($class =~ m/^\d+$/);
  return("", sprintf('13%02x', hex($zwave_class{$class}{id})))
        if($zwave_class{$class});
  return ("versionClass needs a class as parameter", "") if($class eq "%s");
  return ("Unknown class $class", "");
}

sub
ZWave_versionClassAllGet($@)
{
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  if(!$data) { # called by the user
    delete($hash->{CL});
    my %h = map { $_=>1 } split(" ", AttrVal($name, "classes", ""));
    foreach my $c (sort keys %h) {
      next if($c eq "MARK");
      ZWave_Get($hash, $name, "versionClass", $c);
    }
    $zwave_parseHook{"$hash->{nodeIdHex}:..8614"} = \&ZWave_versionClassAllGet;
    return(ZWave_WibMsg($hash).", check the vclasses attribute", "EMPTY");
  }
  $zwave_parseHook{"$hash->{nodeIdHex}:..8614"} = \&ZWave_versionClassAllGet;

  my %h = map { $_=>1 } split(" ", AttrVal($name, "vclasses", ""));
  return 0 if($data !~ m/^048614(..)(..)$/i); # ??
  if($zwave_id2class{lc($1)}) {
    $h{$zwave_id2class{lc($1)}.":".hex($2)} = 1;
    $hash->{".vclasses"}{$zwave_id2class{lc($1)}} = hex($2);
    $attr{$name}{vclasses} = join(" ", sort keys %h);
  }
  return !$hash->{asyncGet}; # "veto" for parseHook/getAll
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
   '16' => { n => 'rotation',             st => ['rpm', 'Hz'] },
   '17' => { n => 'waterTemperature',     st => ['C', 'F'] },
   '18' => { n => 'soilTemperature',      st => ['C', 'F'] },
   '19' => { n => 'seismicIntensity',     st => ['mercalli', 'EU macroseismic',
                                                 'liedu', 'shindo'] },
   '1a' => { n => 'seismicMagnitude',     st => ['local', 'moment',
                                                 'surface wave', 'body wave'] },
   '1b' => { n => 'ultraviolet',          st => ['UV'] },
   '1c' => { n => 'electricalResistivity',st => ['ohm'] },
   '1d' => { n => 'electricalConductivity',st => ['siemens/m'] },
   '1e' => { n => 'loudness',             st => ['dB', 'dBA'] },
   '1f' => { n => 'moisture',             st => ['%', 'content', 'k ohms',
                                                 'water activity'] },
   '20' => { n => 'frequency',            st => ['Hz', 'kHz'] },
   '21' => { n => 'time',                 st => ['seconds'] },
   '22' => { n => 'targetTemperature',    st => ['C', 'F'] },
   '23' => { n => 'particulateMatter',    st => ['mol/m3', 'micro-g/m3'] },
   '24' => { n => 'formaldehydeLevel',    st => ['mol/m3'] },
   '25' => { n => 'radonConcentration',   st => ['bq/m3', 'pCi/L'] },
   '26' => { n => 'methaneDensity',       st => ['mol/m3'] },
   '27' => { n => 'volatileOrganicCompound',st => ['mol/m3'] },
   '28' => { n => 'carbonMonoxide',       st => ['mol/m3'] },
   '29' => { n => 'soilHumidity',         st => ['%'] },
   '2a' => { n => 'soilReactivity',       st => ['pH'] },
   '2b' => { n => 'soilSalinity',         st => ['mol/m3'] },
   '2c' => { n => 'heartRate',            st => ['Bpm'] },
   '2d' => { n => 'bloodPressure',        st => ['Systolic mmHg',
                                                 'Diastolic mmHg'] },
   '2e' => { n => 'muscleMass',           st => ['Kg'] },
   '2f' => { n => 'fatMass',              st => ['Kg'] },
   '30' => { n => 'boneMass',             st => ['Kg'] },
   '31' => { n => 'totalBodyWater',       st => ['Kg'] },
   '32' => { n => 'basicMetabolicRate',   st => ['J'] },
   '33' => { n => 'bodyMassIndex',        st => ['BMI'] },
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
ZWave_timeParametersReport($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  if($arg !~ m/(....)(..)(..)(..)(..)(..)/) {
    Log3 $name,1,"$name: timeParametersReport with wrong format received: $arg";
    return;
  }
  return
    sprintf("timeParameters:date: %04d-%02d-%02d time(UTC): %02d:%02d:%02d",
    hex($1), hex($2), hex($3), hex($4), (hex$5), hex($6));
}

sub
ZWave_timeParametersSet($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  return ("wrong format, see commandref", "")
                        if($arg !~ m/(....)-(..)-(..) (..):(..):(..)/);
  my $rt = sprintf("%04x%02x%02x%02x%02x%02x", $1, $2, $3, $4, $5, $6);
  return ("", sprintf("01%s", $rt));
}

sub
ZWave_dateReport($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  if ($arg !~ m/(....)(..)(..)/) {
    Log3 $name, 1, "$name: dateReport with wrong format received: $arg";
    return;
  }
  return (sprintf("date:%04d-%02d-%02d", hex($1), hex($2), hex($3)));
}

sub
ZWave_timeReport($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  if ($arg !~ m/(..)(..)(..)/) {
    Log3 $name, 1, "$name: timeReport with wrong format received: $arg";
    return;
  }
  return (sprintf("time:%02d:%02d:%02d RTC: %s",
    (hex($1) & 0x1f), hex($2), hex($3),
    (hex($1) & 0x80) ? "failed" : "working"));
}

sub
ZWave_timeOffsetReport($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  if ($arg !~ m/(..)(..)(..)(..)(..)(..)(..)(..)(..)/) {
    Log3 $name, 1, "$name: timeOffsetReport with wrong format received: $arg";
    return;
  }
  my $hourTZO = hex($1) & 0x7f;
  my $signTZO = hex($1) & 0x80;
  my $minuteTZO = hex($2);
  my $minuteOffsetDST = hex($3) & 0x7f;
  my $signOffsetDST = hex($3) & 0x80;
  my $monthStartDST = hex($4);
  my $dayStartDST = hex($5);
  my $hourStartDST = hex($6);
  my $monthEndDST = hex($7);
  my $dayEndDST = hex($8);
  my $hourEndDST = hex($9);

  my $UTCoffset = "UTC-Offset: ";
  $UTCoffset .= ($signTZO ? "-" : "+");
  $UTCoffset .= sprintf ("%02d:%02d", $hourTZO, $minuteTZO);

  my $DSToffset = "DST-Offset(minutes): ";
  $DSToffset .= ($signOffsetDST ? "-" : "+");
  $DSToffset .= sprintf ("%02d", $minuteOffsetDST);

  my $startDST = "DST-Start: ";
  $startDST .= sprintf ("%02d-%02d_%02d:00",
    $monthStartDST, $dayStartDST, $hourStartDST);
  my $endDST = "DST-End: ";
  $endDST .= sprintf ("%02d-%02d_%02d:00",
    $monthEndDST, $dayEndDST, $hourEndDST);

  return (sprintf("timeOffset:$UTCoffset $DSToffset $startDST $endDST"));
}

sub
ZWave_timeOffsetSet($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  if($arg !~
          m/([+-])(..):(..) ([+-])(..) (..)-(..)_(..):00 (..)-(..)_(..):00/) {
    return ("wrong format $arg, see commandref", "");
  }

  my $signTZO = $1;
  my $hourTZO = $2;
  my $minuteTZO = $3;
  my $signOffsetDST = $4;
  my $minuteOffsetDST = $5;
  my $monthStartDST = $6;
  my $dayStartDST = $7;
  my $hourStartDST = $8;
  my $monthEndDST = $9;
  my $dayEndDST = $10;
  my $hourEndDST = $11;

  my $rt = sprintf("%02x%02x",
    ($hourTZO | ($signTZO eq "-" ? 0x01 : 0x00)), $minuteTZO);
  $rt .= sprintf("%02x",
    ($minuteOffsetDST | ($signOffsetDST eq "-" ? 0x01 : 0x00)));
  $rt .= sprintf("%02x%02x%02x",
    $monthStartDST, $dayStartDST, $hourStartDST);
  $rt .= sprintf("%02x%02x%02x", $monthEndDST, $dayEndDST, $hourEndDST);

  return ("", sprintf("05%s", $rt));
}

sub
ZWave_DoorLockOperationReport($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  if ($arg !~ m/(..)(..)(..)(..)(..)/) {
    Log3 $name, 1, "$name: doorLockOperationReport with wrong ".
                    "format received: $arg";
    return;
  }
  my $DLM  = hex($1); # DoorLockMode
  my $DLHM = hex($2); # DoorLockHandleModes
  my $DC   = hex($3); # DoorCondition
  my $DLTM = hex($4); # DoorLockTimeoutMinutes
  my $DLTS = hex($5); # DoorLockTimeoutSeconds

  my $DLMtext = "mode: ";
  if ($DLM == 0xff) {
    $DLMtext .= "secured";
  } elsif ($DLM == 0xfe) {
    $DLMtext .= "lockStateUnknown";
  }
  else {
    $DLMtext .= "unsecured";
    $DLMtext .= (($DLM & 0x10) ? "_inside" :"");
    $DLMtext .= (($DLM & 0x20) ? "_outside" :"");
    $DLMtext .= (($DLM & 0x01) ? "_withTimeout" :"");
  };

  my $odlhm = sprintf ("outsideHandles: %04b",  ($DLHM & 0xf0)>>4);
  my $idlhm = sprintf ("insideHandles: %04b",   ($DLHM & 0x0f));

  my $dc_door  = "door: "  . (($DC & 0x01) ? "closed"    : "open");
  my $dc_bolt  = "bolt: "  . (($DC & 0x02) ? "unlocked"  : "locked");
  my $dc_latch = "latch: " . (($DC & 0x04) ? "closed"    : "open");

  my $to = "timeoutSeconds: ";
  if (($DLTM == 0xfe) && ($DLTS == 0xfe)) {
    $to .= 'not_supported';
  } else {
    $to .= sprintf ("%d", ($DLTM * 60 + $DLTS));
  }

  return "doorLockOperation:$DLMtext $odlhm $idlhm $dc_door ".
          "$dc_bolt $dc_latch $to";
}

sub
ZWave_DoorLockConfigReport($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  if ($arg !~ m/(..)(..)(..)(..)/) {
    Log3 $name, 1, "$name: doorLockOperationReport with wrong ".
                    "format received: $arg";
    return;
  }
  my $OpMode  = $1; # OperationMode
  my $DLHS    = hex($2); # DoorLockHandleStates
  my $DLTM    = hex($3); # DoorLockTimeoutMinutes
  my $DLTS    = hex($4); # DoorLockTimeoutSeconds

  my $ot = "mode: ";
  if ($OpMode eq '01') {
    $ot .= "constant";
  } elsif ($OpMode eq '02') {
    $ot .= "timed";
  } else {
    $ot .= "unknown";
  }

  my $odlhs = sprintf ("outsideHandles: %04b",  ($DLHS & 0xf0)>>4);
  my $idlhs = sprintf ("insideHandles: %04b",  ($DLHS & 0x0f));

  my $to = "timeoutSeconds: ";
  if (($DLTM == 0xfe) && ($DLTS == 0xfe)) {
    $to .= 'not_supported';
  } else {
    $to .= sprintf ("%d", ($DLTM * 60 + $DLTS));
  }

  return "doorLockConfiguration: $ot $odlhs $idlhs $to";
}

sub
ZWave_DoorLockOperationSet($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  my $rt;
  $rt = ($arg eq 'open')  ? "00" :
        ($arg eq 'close') ? "FF" :
        ($arg eq "00")    ? "00" :
        ($arg eq "01")    ? "01" :
        ($arg eq "10")    ? "10" :
        ($arg eq "11")    ? "11" :
        ($arg eq "20")    ? "20" :
        ($arg eq "21")    ? "21" :
        ($arg eq "FF")    ? "FF" : "";

  return ("DoorLockOperationSet: wrong parameter, see commandref")
    if ($rt eq "");

  return ("", "01".$rt);
}

sub
ZWave_DoorLockConfigSet($$)
{
  # 0x62 V1, V2
  # userinput: operationType, ohandles, ihandles, seconds_dez
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if ($arg !~ m/\b(.+)\b \b([01]{4})\b \b([01]{4})\b \b([0-9]+)$/) {
    #~ Log3 $name, 1, "$name: doorLockConfigurationSet wrong ".
                    #~ "format, see commandref: $arg";
    return ("doorLockConfigurationSet: wrong format, see commandref","");
  }

  my $oT;
  if (lc($1) eq "constant") {
    $oT = 1;
  } elsif (lc($1) eq "timed") {
    $oT = 2;
  } else {
    return ("wrong operationType: only [constant|timed] is allowed","");
  }

  my $handles = ((oct("0b".$2))<<4 | oct("0b".$3));

  if (($4 < 1) || ($4) > 15239) { # max. 253 * 60 + 59 seconds
    return ("doorLockConfigurationSet: 1-15238 seconds allowed","");
  }

  return ("", sprintf("04%02x%02x%02x%02x",
    $oT,$handles, int($4 / 60) ,($4 % 60)));
}

sub
ZWave_SetClasses($$$$)
{
  my ($homeId, $id, $type6, $classes) = @_;

  my $def = $modules{ZWave}{defptr}{"$homeId $id"};
  if(!$def) {
    $type6 = $zw_type6{$type6} if($type6 && $zw_type6{lc($type6)});
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
ZWave_swmParse($$$$)
{
  my ($fl, $sl, $dur, $step)=@_;
  my $fl1 = (hex($fl) & 0x18)>>3;
  my $fl2 = (hex($fl) & 0xc0)>>6;
  $fl = ($fl1==0 ? "Increment": $fl1==1 ? "Decrement" : "")." ".
        ($fl2==0 ? "Up":  $fl1==1 ? "Down" : "");
  return sprintf("state:swm %s Start: %d Duration: %d Step: %d",
        $fl, hex($sl), hex($dur), hex($step));
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
  #Caps:= channelId,genericDeviceClass,specificDeviceClass,Class1,Class2,...

  my $name = $hash->{NAME};
  my $iodev = $hash->{IODev};
  return "Missing IODev for $name" if(!$iodev);

  my $homeId = $iodev->{homeId};
  my @l = grep /../, split(/(..)/, lc($caps));
  my $chid = sprintf("%02x", hex(shift(@l)) & 0x7f); # Forum #50176
  my $id = $hash->{nodeIdHex};

  my @classes;
  my $type6  = shift(@l);
  $type6 = $zw_type6{$type6} if($type6 && $zw_type6{lc($type6)});
  my $specificClass = shift(@l);
  for my $classId (@l) {
    push @classes, $zwave_id2class{lc($classId)} ?
        $zwave_id2class{lc($classId)} : "UNKNOWN_".uc($classId);
  }
  return "mcCapability_$chid:no classes" if(!@classes);

  if($chid ne "00" && !$modules{ZWave}{defptr}{"$homeId $id$chid"}) {
    my $lid = hex("$id$chid");
    my $lcaps = substr($caps, 6);
    $id = hex($id);
    DoTrigger("global",
      "UNDEFINED ZWave_${type6}_$id.$chid ZWave $homeId $lid $lcaps", 1);
  }

  return "mcCapability_$chid:".join(" ", @classes);
}

sub
ZWave_mcCreateAll($$)
{
  my ($hash, $data) = @_;
  if(!$data) { # called by the user
    $zwave_parseHook{"$hash->{nodeIdHex}:0[45]6008...."} = \&ZWave_mcCreateAll;
    ZWave_Get($hash, $hash->{NAME}, "mcEndpoints");
    return("", "EMPTY");
  }
  $data =~ m/^0[45]6008(..)(..)/; # 4 vs. 5: Forum #50895
  my $nGrp = hex($2);
  for(my $c = 1; $c <= $nGrp; $c++) {
    ZWave_Get($hash, $hash->{NAME}, "mcCapability", $c);
  }
  return undef;
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
    if($v =~ m/action="add"/) {
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

      if($l =~ m/<Product type\s*=\s*"([^"]*)".*id\s*=\s*"([^"]*)".*name\s*=\s*"([^"]*)"/) {
        if($mf eq $lastMf && $prod eq lc($1) && $id eq lc($2)) {
          if($config) {
            $ret = (($l =~ m/config\s*=\s*"([^"]*)"/) ? $1 : "unknown");
            ZWave_mfsAddClasses($hash, $1);
            # execInits needs the modelId
            setReadingsVal($hash, "modelId", "$mf-$prod-$id", TimeNow());
            ZWave_execInits($hash, 50, $ret);
            return "modelConfig:$ret";
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
ZWave_doorLLRParse($$)
{
  my ($hash, $val) = @_;
  my $result;
  my $name = $hash->{NAME};
  my @eventTypeHash = ( 'none',                                    #not defined
     'Lock Command: Keypad access code verified lock command',     #evtT  1
     'Unlock Command: Keypad access code verified unlock command', #evtT  2
     'Lock Command: Keypad lock button pressed',                   #evtT  3
     'Unlock command: Keypad unlock button pressed',               #evtT  4
     'Lock Command: Keypad access code out of schedule',           #evtT  5
     'Unlock Command: Keypad access code out of schedule',         #evtT  6
     'Keypad illegal access code entered',                         #evtT  7
     'Key or latch operation locked (manual)',                     #evtT  8
     'Key or latch operation unlocked (manual)',                   #evtT  9
     'Auto lock operation',                                        #evtT 10
     'Auto unlock operation',                                      #evtT 11
     'Lock Command: Z-Wave access code verified',                  #evtT 12
     'Unlock Command: Z-Wave access code verified',                #evtT 13
     'Lock Command: Z-Wave (no code)',                             #evtT 14
     'Unlock Command: Z-Wave (no code)',                           #evtT 15
     'Lock Command: Z-Wave access code out of schedule',           #evtT 16
     'Unlock Command Z-Wave access code out of schedule',          #evtT 17
     'Z-Wave illegal access code entered',                         #evtT 18
     'Key or latch operation locked (manual)',                     #evtT 19
     'Key or latch operation unlocked (manual)',                   #evtT 20
     'Lock secured',                                               #evtT 21
     'Lock unsecured',                                             #evtT 22
     'User code added',                                            #evtT 23
     'User code deleted',                                          #evtT 24
     'All user codes deleted',                                     #evtT 25
     'Master code changed',                                        #evtT 26
     'User code changed',                                          #evtT 27
     'Lock reset',                                                 #evtT 28
     'Configuration changed',                                      #evtT 29
     'Low battery',                                                #evtT 30
     'New Battery installed',                                      #evtT 31
    );
  #              |- $recordNumber
  #              |   |- $timestampYear
  #              |   |     |- $timestampMonth
  #              |   |     |   |- $timestampDay
  #              |   |     |   |   |- $recordStatusTimestampHour
  #              |   |     |   |   |   |- $timestampMinute
  #              |   |     |   |   |   |   |- $timestampSecond
  #              |   |     |   |   |   |   |   |- $eventType
  #              |   |     |   |   |   |   |   |   |- $userIdentifier
  #              |   |     |   |   |   |   |   |   |   |- $userCodeLength
  #              20  07e1  07  1f  34  28  2b  08  00  00
  if( $val =~ /^(..)(....)(..)(..)(..)(..)(..)(..)(..)(..)/ ) {
    my $recordNumber   = hex($1);
    my $timestampYear  = hex($2);
    my $timestampMonth = hex($3);
    my $timestampDay   = hex($4);
    my $recordStatusTimestampHour = sprintf( "%b", hex($5) );
    my $recordStatus = substr $recordStatusTimestampHour, 0, 1;
    $recordStatus = oct( "0b$recordStatus" );
    my $timestampHour = substr $recordStatusTimestampHour, 1, 5;
    $timestampHour = oct( "0b$timestampHour" );
    my $timestampMinute = hex($6);
    my $timestampSecond = hex($7);
    my $eventTypeNumber = hex($8);
    my $userIdentifier  = hex($9);
    my $userCodeLength  = hex($10);

    my $timestamp = sprintf ("%4d-%02d-%02d %02d:%02d:%02d", 
        $timestampYear,$timestampMonth,$timestampDay,$timestampHour,
        $timestampMinute,$timestampSecond);

    $result = "doorLockLoggingRecord:".
        "recordNr: $recordNumber ".
        "recordStatus: $recordStatus ".
        "eventType: $eventTypeHash[$eventTypeNumber] ".
        "userIdentifier: $userIdentifier ".
        "userCodeLength: $userCodeLength ".
        "timestamp: $timestamp";
  }

  #                                                        |- $userCode
  #              20  07e1  07  1f  34  28  2b  08  00  00  3132333435
  if( $val =~ /^(..)(....)(..)(..)(..)(..)(..)(..)(..)(..)(.+)/ ) {
    my $userCode = "recieved but not saved.";
    $result .= " USER_CODE: $userCode";
  }
  
  if( $result ne '' ) {
    return $result;
  } else {
    return "doorLockLoggingRecord:$val";
  }
}

my @zwave_wd = ("none","mon","tue","wed","thu","fri","sat","sun");

sub
ZWave_ccsSet($)
{
  my ($spec) = @_;
  my @arg = split(/[ ,]/, $spec);
  my $usage = "wrong arg, need: <weekday> HH:MM relTemp HH:MM relTemp ...";

  return ($usage,"") if(@arg < 1 || int(@arg) > 19 || (int(@arg)-1)%2 != 0);
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
ZWave_ccsSetOverride($)
{
  my ($arg) = @_;
  
  my $override_type;
  my $override_state;
  my $err = "wrong arguments, see commandref for details";
  
  if ($arg =~ m/(no|temporary|permanent) (.*)/) {
      $override_type = (lc($1) eq "no" ? 0 : (lc($1) eq "temporary" ? 1 : 2));
    my $state = $2;
    if ($state =~ m/(frost|energy)/) {
      $override_state = (lc($state) eq "frost" ? 0x79 : 0x7a);
    } elsif ($state =~ m/[-+]?[0-9]*\.?[0-9]+/) {
        $state *= 10;
        $state = 120 if ($state > 120);
        $state = -128 if ($state < -128);
        $state += 256 if ($state < 0);
        $override_state = $state;
    } else {
      return($err, "");
    }
    return ("", sprintf("06%02x%02x", $override_type, $override_state));
  }
  return($err, "");
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
ZWave_ccsAllGet ($)
{
  my ($hash) = @_;
  foreach my $idx (1..int($#zwave_wd)) {
    ZWave_Get($hash, $hash->{NAME}, "ccs", $zwave_wd[$idx]);
  }
  return (ZWave_WibMsg($hash),"EMPTY");
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
ZWave_clockAdjust($$)
{
  my ($hash, $d) = @_;
  return $d if($d !~ m/^13(..)048104....$/);
  my ($err, $nd) = ZWave_clockSet();
  my $cmdEf = (AttrVal($hash->{NAME},"noExplorerFrames",0) == 0 ? "25" : "05");
  return "13${1}0481${nd}${cmdEf}${1}";
}

sub
ZWave_clockSet()
{
  my @l = localtime();
  return ("", sprintf("04%02x%02x", (($l[6] ? $l[6]:7)<<5)|$l[2], $l[1]));
}

sub
ZWave_clockParse($$)
{
  my ($p1,$p2) = @_;
  $p1 = hex($p1); $p2 = hex($p2);
  return sprintf("clock:%s %02d:%02d", $zwave_wd[$p1>>5], $p1 & 0x1f, $p2);
}

sub
ZWave_cleanString($$$)
{
  my ($c, $postfix, $isValue) = @_;
  my $shortened = 0;

  $c =~ s/^[0-9.]+ //g if(!$isValue);
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
ZWave_configParseModel($;$)
{
  my ($cfg, $my) = @_;
  return if(!$my && ZWave_configParseModel($cfg, 1));

  my $fn = $attr{global}{modpath}."/FHEM/lib/".($my ? "fhem_":"open").
                                "zwave_deviceconfig.xml.gz";
  my $gz = gzopen($fn, "rb");
  if(!$gz) {
    Log 3, "Can't open $fn: $!" if(!$my);
    return 0;
  }

  my ($ret, $line, $class, %hash, $cmdName, %classInfo, %group, $origName);
  while($gz->gzreadline($line)) {       # Search the "file" entry
    if($line =~ m/^\s*<Product.*sourceFile="$cfg"/) {
      $ret = 1;
      last;
    }
  }

  my $partial="";
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
      my ($cmd,$shortened) = ZWave_cleanString($h{label}, $h{index}, 0);
      $origName = "config$cmd";
      $cmdName = $origName;
      my $index = 1;
      while($hash{$cmdName}) {
        $cmdName = $origName."_".(++$index);
      }
      $h{Help} = "";
      $h{Help} .= "Full text for $cmdName is: $h{label}<br>"
        if($shortened || $origName ne $cmdName);
      $hash{$cmdName} = \%h;
    }

    if($line =~ m,<Help>, && $line !~ m,</Help>,) { # Multiline Help
      $partial = $line;
      next;
    }
    if($partial) {
      if($line =~ m,</Help>,) {
        $line = $partial.$line;
        $line =~ s/[\r\n]//gs;
        $partial = "";
      } else {
        $partial .= $line;
        next;
      }
    }
    $hash{$cmdName}{Help} .= "$1<br>" if($line =~ m+<Help>(.*)</Help>+s);

    if($line =~ m/^\s*<Item/) {
      my $label = $1 if($line =~ m/label="([^"]*)"/i);
      my $value = $1 if($line =~ m/value="([^"]*)"/i);
      my ($item, $shortened) = ZWave_cleanString($label, $value, 1);
      $hash{$cmdName}{Item}{$item} = $value;
      $hash{$cmdName}{type} = "list";   # Forum #42604
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
    my $caName = "$cfg$cmd";
    $zwave_cmdArgs{set}{$caName} = join(",", keys %{$h->{Item}}) if($h->{Item});
    $zwave_cmdArgs{set}{$caName} = "noArg" if($h->{type} eq "button");
    $zwave_cmdArgs{get}{$caName} = "noArg";
  }

  $zwave_modelConfig{$cfg} = \%mc;
  Log 3, "ZWave got config for $cfg from $fn" if($ret);
  return $ret;
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

  if($cmd eq "configRGBLedColorForTesting") {
    return ("6 digit hext number needed","") if($arg[0] !~ m/^[0-9a-f]{6}$/i);
    return ("", sprintf("04%02x03%s", $h->{index}, $arg[0]));
  }

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

  return ("Parameter is not decimal", "") if($arg[0] !~ m/^-?[0-9]+$/);

  if($h->{size}) { # override type by size
    $t = ($h->{size} eq "1" ? "byte" : ($h->{size} eq "2" ? "short" : "int"));
  }

  my $len = ($t eq "int" ? 8 : ($t eq "short" ? 4 : 2));
  $arg[0] += 2**($len==8 ? 32 : ($len==4 ? 16 : 8)) if($arg[0] < 0); #F:41709
  return ("", sprintf("04%02x%02x%0*x", $h->{index}, $len/2, $len, $arg[0]));
}

##############################################
### START: 0x20 BASIC
sub
ZWave_BASIC_03_report ($$$)
{ # 0x2003 BASIC_REPORT V2
  my ($value, $target, $duration) = @_;;
  my $time = hex($duration);

  if (($time > 0x7F) && ($time <= 0xFD)) {
    $time = (hex($duration) - 0x7F) * 60;
  };
  $time .=  " seconds";
  $time  =  "unknown" if (hex($duration) == 0xFE);
  $time  =  "255"     if (hex($duration) == 0xFF);
  
  my $rt = "basicReport:".hex($value)
          ." target: ".hex($target)
          ." duration: ".$time;
          
  return $rt;
}

##############################################
### START: 0x21 APPLICATION_STATUS
sub
ZWave_APPLICATION_STATUS_01_Report($$$)
{ # 0x2101 ApplicationStatus ApplicationBusyReport >= V1
  my ($hash, $st, $wTime) = @_;
  my $name = $hash->{NAME};

  my $status = hex($st);
  my $rt .= $status==0 ? "tryAgainLater " :
            $status==1 ? "tryAgainInWaitTimeSeconds " :
            $status==2 ? "RequestQueued " : "unknownStatusCode ";
  $rt .= sprintf("waitTime: %d", hex($wTime));
  return ("applicationBusy:$rt");
}

##############################################
### START: 0x71 ALARM (NOTIFICATION)
### Renamed from ALARM to NOTIFICATION in V3 specification,
### for backward compatibility the name ALARM will be used
### regardless of the version of the class.

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

my %zwave_alarmEvent = ( # no comma allowed in strings
  "0101"=>"detected",
  "0102"=>"detected - Unknown Location",
  "0103"=>"Alarm Test",
  "0201"=>"detected",
  "0202"=>"detected - Unknown Location",
  "0301"=>"detected",
  "0302"=>"detected - Unknown Location",
  "0401"=>"Overheat detected",
  "0402"=>"Overheat detected - Unknown Location",
  "0403"=>"Rapid Temperature Rise",
  "0404"=>"Rapid Temperature Rise - Unknown Location",
  "0405"=>"Underheat detected",
  "0406"=>"Underheat detected - Unknown Location",
  "0501"=>"Leak detected",
  "0502"=>"Leak detected - Unknown Location",
  "0503"=>"Level Dropped",
  "0504"=>"Level Dropped - Unknown Location",
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
  "0702"=>"Intrusion - Unknown Location",
  "0703"=>"Tampering - product covering removed",
  "0704"=>"Tampering - Invalid Code",
  "0705"=>"Glass Breakage",
  "0706"=>"Glass Breakage - Unknown Location",
  "0707"=>"Motion Detection",
  "0708"=>"Motion Detection - Unknown Location",
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
ZWave_ALARM_01_Get($) {
  # 0x7101 Alarm/Notification EventSupportedGet >= V3
  # alarmEventSupported
  
  my ($arg) = @_;
  
  foreach my $t (keys %zwave_alarmType) {
    if (lc($zwave_alarmType{$t}) eq lc($arg)) {
      return ("", "01".$t);
    }
  }
  return ("unknown notification type entered, see commandref", "");
}

sub
ZWave_ALARM_02_Report($) {
  # 0x7102 Alarm/Notification EventSupportedReport >= V3
  # additional flagname "Appliance" in V4
  
  my ($arg) = @_;

  if($arg !~ m/(..)(..)(.*)/) {
  return ("wrong format received");
  }
  
  my $t = $1;
  my $rt = "alarmEventSupported_";
  $rt .= ($zwave_alarmType{$t}) ? $zwave_alarmType{$t}.":" :
                                  hex($t)."_unknown:";
  my $numBitMasks = $2 & 0x1f;
  #my $res         = ($2 & 0xe0) >> 5; # reserved field

  my $e = "";
  my $val = $3;
  my $delimeter = "";
  
  for (my $i=0; $i<$numBitMasks; $i++) {
    my $supported = hex(substr($val, $i*2, 2));
    for (my $j=$i*8; $j<$i*8+8; $j++) {
      if ($supported & (2 ** ($j-$i*8))) {
        $e = sprintf("%s%02x", $t, $j);
        $rt .= $delimeter;
        $rt .= "(" . $j . ") ";
        if (!$zwave_alarmEvent{$e}) {
          $rt .= "unknown event";
        } else {
          $rt .= $zwave_alarmEvent{$e};
        }
        $delimeter = ", ";
      }
    }
  } 
  return $rt; 
}

sub
ZWave_ALARM_04_Get($$)
{
  # 0x7104 Alarm/Notification alarmGet >= V1
  # alarm (V1), alarmWithType (V2), alarmWithTypeEvent (>=V3)
  
  my ($v, $arg) = @_;
  my $rt = "04";

  if ($v == 1) {
    if($arg !~ m/^$p1_b$/) {
      return ("wrong format, see commandref", "");
    }
    $rt .= sprintf("%02x", $1);
    return ("",$rt);
  } elsif ($v == 2) {
    if($arg !~ m/(.*)/) {
      return ("wrong format, see commandref", "");
    }
    foreach my $t (keys %zwave_alarmType) {
      if (lc($zwave_alarmType{$t}) eq lc($1)) {
        $rt .= sprintf("00%s", $t);
        return ("", $rt);
      }
    }
  } elsif ($v >= 3) { # V3=V4
    if($arg !~ m/(.*) $p1_b/) {
      return ("wrong format, see commandref", "");
    }
    foreach my $t (keys %zwave_alarmType) {
      if (lc($zwave_alarmType{$t}) eq lc($1)) {
        $rt .= sprintf("00%s%02x", $t, $2);
        return ("", $rt);
      }
    }
  }
}

sub
ZWave_ALARM_05_Report($$$$)
{
  # 0x7105 Alarm/Notification Report >= V1
  # additional parameter in V2 and V3
  
  my ($hash, $t, $l, $r) = @_;
  my $name = $hash->{NAME};

  my $rt0 = "";
  my $rt1 = "";
  my $at = "";
  my $level = "";
  my $eventname = "";
  my $ar = AttrVal($name, "extendedAlarmReadings",0);

  if (!$r) { #V1 Answer
    $at = $zwave_alarmType{$t} ? $zwave_alarmType{$t} :
                                 sprintf("%d_unknown", hex($t));
    $rt0 = "alarm_type_$t:level $l";
    $rt1 = "alarm_$at:level $l";
  } elsif ($r =~ m/(..)(..)(..)(..)(..)(.*)/) {
    my ($zid, $ns, $t2, $e, $prop, $opt) = ($1, $2, $3, $4, $5, $6);
      
    if ($e ne "00") {
      if (($t ne "00") && ($l eq "00")) {
        $level = "Event cleared: ";
      }
    } else {
      $level = "Event cleared: ";
      my $len = hex($prop & 0x1f);
      if (($len >= 1) && ($opt =~ m/(..)(.*)/)) {
        $e = $1;
      }
    }
    $eventname = $zwave_alarmEvent{"$t2$e"} ? $zwave_alarmEvent{"$t2$e"}
                                : sprintf("unknown event %d", hex($e));
    $at = $zwave_alarmType{$t2} ? $zwave_alarmType{$t2} :
                                  sprintf("%d_unknown", hex($t2));
    my $nst = ($ns eq "ff") ? "notificationIsOn" : "notificationIsOff";
    my $o = ($opt && ($e ne "00")) ? ", arg $prop$opt" : "";
    
    $rt0 = "alarm:$at: $level$eventname$o";
    $rt1 = "alarm_$at:$level$eventname$o, $nst";
  }
  
  if ($ar == 0) {
    return ($rt0);
  } elsif ($ar == 1) {
    return ($rt1);
  } elsif ($ar == 2) {
    return ($rt0, $rt1);
  }
}

sub
ZWave_ALARM_06_Set($) {
  # 0x7106 Alarm/Notification alarmSet (>=V2)
  # alarmnotification
  
  my ($arg) = @_;
  
  if($arg !~ m/^(.*) (on|off)$/i) {
      return ("wrong format, see commandref", "");
  }
  my $status = (lc($2) eq "on") ? "FF" : "00";
  foreach my $t (keys %zwave_alarmType) {
    if (lc($zwave_alarmType{$t}) eq lc($1)) {
      return ("", "06".$t.$status);
    }
  }
  return ("alarm/notification type not defined","");
}

sub
ZWave_ALARM_08_Report($) {
  # 0x7108 Alarm/Notification TypeSupportedReport >= V2
  # additional flagname "Appliance" in V4
 
  my ($arg) = @_;
 
  if($arg !~ m/(..)(.*)/) {
  return ("wrong format received");
  }
  
  my $numBitMasks = $1 & 0x1f;
  #my $res         = ($1 & 0x60) >> 5; # reserved field
  my $alarm_v1    = $1 & 0x80; # 0:standard types, 1:V1 non-standard 
  
  if ($alarm_v1) {
    return ("alarmTypeSupported:non-standard V1 Alarm Types used");
  } else {
    my $rt = "alarmTypeSupported:";
    my $t = "";
    my $val = $2;
    my $delimeter = "";
    
    for (my $i=0; $i<$numBitMasks; $i++) {
      my $supported = hex(substr($val, $i*2, 2));
      for (my $j=$i*8; $j<$i*8+8; $j++) {
        if ($supported & (2 ** ($j-$i*8))) {
          $t = sprintf("%02x", $j);
          $rt .= sprintf("$delimeter$zwave_alarmType{$t}");
          $delimeter = " ";
        }
      }
    }
    return $rt;
  }
}

### END: 0x71 ALARM/NOTIFICATION
##############################################

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

sub
ZWave_WibMsg($)
{
  my ($hash) = @_;
  return ZWave_isWakeUp($hash) ? 
                "Scheduled get requests for sending after WAKEUP" :
                "working in the background";
}

sub
ZWave_configAllGet($)
{
  my ($hash) = @_;
  my $mc = ZWave_configGetHash($hash);
  return ("configAll: no model specific configs found", undef)
        if(!$mc || !$mc->{config});
  delete($hash->{CL});
  foreach my $c (sort keys %{$mc->{get}}) {
    ZWave_Get($hash, $hash->{NAME}, $c);
  }
  return (ZWave_WibMsg($hash),"EMPTY");
}

sub
ZWave_associationAllGet($$)
{
  my ($hash, $data) = @_;

  if(!$data) { # called by the user
    $zwave_parseHook{"$hash->{nodeIdHex}:..85"} = \&ZWave_associationAllGet;
    delete($hash->{CL});
    ZWave_Get($hash, $hash->{NAME}, "associationGroups");
    return(ZWave_WibMsg($hash), "EMPTY");
  }

  my $nGrp = ($data =~ m/..8506(..)/ ? hex($1) :
                ReadingsVal($hash->{NAME}, "assocGroups", 0));
  my $grp = 0;
  $grp = hex($1) if($data =~ m/..8503(..)/);
  return if($grp >= $nGrp);
  $zwave_parseHook{"$hash->{nodeIdHex}:..85"} = \&ZWave_associationAllGet;
  ZWave_Get($hash, $hash->{NAME}, "association", $grp+1);
  return;
}

sub
ZWave_mcaAllGet($$)
{
  my ($hash, $data) = @_;

  if(!$data) { # called by the user
    $zwave_parseHook{"$hash->{nodeIdHex}:..8e"} = \&ZWave_mcaAllGet;
    delete($hash->{CL});
    ZWave_Get($hash, $hash->{NAME}, "mcaGroupings");
    return(ZWave_WibMsg($hash), "EMPTY");
  }

  my $nGrp = ($data =~ m/..8e06(..)/ ? hex($1) :
                ReadingsVal($hash->{NAME}, "mcaGroups", 0));
  my $grp = 0;
  $grp = hex($1) if($data =~ m/..8e03(..)/);
  return if($grp >= $nGrp);
  $zwave_parseHook{"$hash->{nodeIdHex}:..8e"} = \&ZWave_mcaAllGet;
  ZWave_Get($hash, $hash->{NAME}, "mca", $grp+1);
  return;
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
          ":".($value eq "00" ? "off" : ($value eq "ff" ? "on" : hex($value)));
}

sub
ZWave_assocGroup($$$$)
{
  my ($homeId, $gId, $max, $nodes) = @_;
  my %list = map { $defs{$_}{nodeIdHex} => $_ }
             grep { $defs{$_}{homeId} && 
                    $defs{$_}{nodeIdHex} &&
                    $defs{$_}{homeId} eq $homeId }
             keys %defs;
  $nodes = join(" ",
           map { $list{$_} ? $list{$_} : "UNKNOWN_".hex($_); }
           ($nodes =~ m/../g));
  return sprintf("assocGroup_%d:Max %d Nodes %s", hex($gId),hex($max), $nodes);
}

sub
ZWave_mcaReport($$$$)
{
  my ($homeId, $gId, $max, $arg) = @_;
  my %list = map { $defs{$_}{nodeIdHex} => $_ }
             grep { $defs{$_}{homeId} && 
                    $defs{$_}{nodeIdHex} &&
                    $defs{$_}{homeId} eq $homeId }
             keys %defs;

  my ($ret, $step) = ("", 1);
  my @arg = ($arg =~ m/../g);
  for(my $idx = 0; $idx < @arg; $idx += $step) {
    my $a = $arg[$idx];
    if($step == 1 && $a eq "00") {
      $step = 2;
      $idx--;
      next;
    }
    my $n = ($list{$a} ? $list{$a} : sprintf("UNKNOWN_%d", hex($a)));
    $ret .= " ".($step == 1 ? $n : ($n.":".hex($arg[$idx+1])));
  }
  return sprintf("mca_%d:Max %d %s",
                hex($gId), hex($max), ($ret ? "Nodes$ret" : ""));
}


sub
ZWave_CRC16($)
{
  my ($msg) = @_;
  my $buf = pack 'H*', $msg;
  my $len = length($buf);

  my $poly = 0x1021;  #CRC-CCITT (CRC-16) x16 + x12 + x5 + 1
  my $crc16 = 0x1D0F; #Startvalue

  for(my $i=0; $i<$len; $i++) {
    my $byte = ord(substr($buf, $i, 1));
    $byte = $byte * 0x100;        # expand to 16 Bit
    for(0..7) {
      if(($byte & 0x8000) ^ ($crc16 & 0x8000)) { # if Hi-bits are different
        $crc16 <<= 1;
        $crc16 ^= $poly;
      } else {
        $crc16 <<= 1;
      }
      $crc16 &= 0xFFFF;
      $byte <<= 1;
      $byte &= 0xFFFF;
    }
  }
  return sprintf "%04x", $crc16;
}

##############################################
#  SECURITY (start)
##############################################

sub
ZWave_secIncludeStart($$)
{
  my ($hash, $iodev) = @_;
  my $name = $hash->{NAME};
  my $ioName = $iodev->{NAME};

  readingsSingleUpdate($hash, "SECURITY",
                          "INITIALIZING (starting secure inclusion)", 0);
  my $classes = AttrVal($name, "classes", "");
  if($classes =~ m/SECURITY/) {
    if ($zwave_cryptRijndael == 1) {
      my $key = AttrVal($ioName, "networkKey", "");
      if($key) {
        $iodev->{secInitName} = $name;
        Log3 $ioName, 2, "ZWAVE Starting secure init for $name";

        #~ ZWave_secIncludeStart($dh);
        #~ return "";

        # starting secure inclusion by setting the scheme
        $zwave_parseHook{"$hash->{nodeIdHex}:..9805"} = \&ZWave_secSchemeReport;
        ZWave_secAddToSendStack($hash, "980400"); # only scheme "00" is defined

        return 1;
      } else {
        Log3 $ioName,1,"No secure inclusion as $ioName has no networkKey";
        readingsSingleUpdate($hash, "SECURITY",
                                'DISABLED (Networkkey not found)', 0);
        Log3 $name, 1, "$name: SECURITY disabled, ".
          "networkkey not found";
      }
    } else {
      readingsSingleUpdate($hash, "SECURITY",
                        'DISABLED (Module Crypt::Rijndael not found)', 0);
      Log3 $name, 1, "$name: SECURITY disabled, module ".
        "Crypt::Rijndael not found";
    }
  } else {
    readingsSingleUpdate($hash, "SECURITY",
                        'DISABLED (SECURITY not supported by device)', 0);
    Log3 $name, 1, "$name: secure inclusion failed, ".
      "SECURITY disabled, device does not support SECURITY command class";
  }
  return 0;
}

sub
ZWave_secSchemeReport($$) # only called by zwave_parseHook during Include
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if ($arg =~ m/..9805(..)/) { # 03980500 is expected
    if ($1 == 0) { # supported SECURITY-Scheme, prepare for setting networkkey
      $zwave_parseHook{"$hash->{nodeIdHex}:..9880"} = \&ZWave_secNetworkkeySet;
      ZWave_secAddToSendStack($hash, '9840');
      #ZWave_Cmd("set", $hash, $name, "secNonceReport");
    } else {
      Log3 $name, 1, "$name: Unsupported SECURITY-Scheme received: $1"
                          .", please report";
    }
  } else {
    Log3 $name, 1, "$name: Unknown SECURITY-SchemeReport received: $arg";
  }
  return 1; # "veto" for parseHook
}

sub
ZWave_secNetworkkeySet($$) # only called by zwave_parseHook during Include
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $iodev = $hash->{IODev};

  my $r_nonce_hex;
  if ($arg =~ m/..9880(................)/) {
    $r_nonce_hex = $1;
  } else {
    Log3 $name, 1, "$name: Unknown SECURITY-NonceReport received: $arg";
  }

  my $key_hex = AttrVal($iodev->{NAME}, "networkKey", "");
  my $mynonce_hex = substr (ZWave_secCreateNonce($hash), 2, 16);
  my $cryptedNetworkKeyMsg = ZWave_secNetworkkeyEncode($r_nonce_hex,
      $mynonce_hex, $key_hex, $hash->{nodeIdHex});

  $zwave_parseHook{"$hash->{nodeIdHex}:..9807"} = \&ZWave_secNetWorkKeyVerify;
  ZWave_secAddToSendStack($hash, '98'.$cryptedNetworkKeyMsg);

  readingsSingleUpdate($hash, "SECURITY", 'INITIALIZING (Networkkey sent)',0);
  Log3 $name, 5, "$name: SECURITY initializing, networkkey sent";

  # start timer here to check state if networkkey was not verified
  $hash->{networkkeyTimer} = { hash => $hash };
  InternalTimer(gettimeofday()+25, "ZWave_secTestNetworkkeyVerify",
                    $hash->{networkkeyTimer}, 0);
  return 1; # "veto" for parseHook
}

sub
ZWave_secNetWorkKeyVerify ($$) # only called by zwave_parseHook during Include
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $iodev = $hash->{IODev};

  if (!ZWave_secIsEnabled($hash)) {
    return 1;
  }

  RemoveInternalTimer($hash->{networkkeyTimer});
  delete $hash->{networkkeyTimer};
  readingsSingleUpdate($hash, "SECURITY", 'ENABLED', 0);
  Log3 $name, 3, "$name: SECURITY enabled, networkkey was verified";

  $zwave_parseHook{"$hash->{nodeIdHex}:..9803"} = \&ZWave_secIncludeFinished;
  ZWave_Cmd("set", $hash, $name, ("secSupportedReport"));
  return 1; # "veto" for parseHook
}

sub
ZWave_secIncludeFinished($$) # only called by zwave_parseHook during Include
{
  my ($hash, $arg) = @_;
  my $iodev = $hash->{IODev};
  my $name = $hash->{NAME};

  if ($arg =~ m/..9803(.*)/) {
    ZWave_secSupported($hash, $1);
  } else {
    Log3 $name, 2, "$name: unknown answer for secSupported received";
  }

  if ($iodev->{secInitName}) {
    # Secure inclusion is finished, remove readings and execute "normal" init
    delete $iodev->{secInitName};
    ZWave_execInits($hash, 0);
  }
  return 1; # "veto" for parseHook -> secSupported to be called before execInits
}

sub
ZWave_secTestNetworkkeyVerify ($)
{
  my ($p) = @_;
  my $hash = $p->{hash};
  my $name = $hash->{NAME};
  my $sec_status = ReadingsVal($name, "SECURITY", undef);

  delete $hash->{networkkeyTimer};
  if ($sec_status !~ m/ENABLED/) {
    readingsSingleUpdate($hash, "SECURITY",
        'DISABLED (networkkey not verified and timer expired)', 0);
    Log3 $name, 1, "$name: SECURITY disabled, networkkey was not verified ".
      "and timer expired";
  }
}

sub
ZWave_secAddToSendStack($$)
{
  my ($hash, $cmd) = @_;
  my $name = $hash->{NAME};

  my $id = $hash->{nodeIdHex};
  my $len = sprintf("%02x", (length($cmd)-2)/2+1);
  my $cmdEf  = (AttrVal($name, "noExplorerFrames", 0) == 0 ? "25" : "05");
  my $data = "13$id$len$cmd$cmdEf" . ZWave_callbackId($hash);
  ZWave_addToSendStack($hash, "set", $data);
}

sub
ZWave_secStart($)
{
  my ($hash) = @_;
  my $dt = gettimeofday();

  $hash = $defs{$hash->{endpointParent}} if($hash->{endpointParent});
  $hash->{secTime} = $dt;
  $hash->{secTimer} = { hash => $hash };
  InternalTimer($dt+7, "ZWave_secUnlock", $hash->{secTimer}, 0);

  return if($hash->{secInProgress});
  $hash->{secInProgress} = 1;
  my @empty;
  $hash->{secStack} = \@empty;
}

sub
ZWave_secUnlock($)
{
  my ($p) = @_;
  my $hash= $p->{hash};
  my $dt = gettimeofday();
  if (($hash->{secInProgress}) && ($dt > ($hash->{secTime} + 6))) {
    Log3 $hash->{NAME}, 3, "$hash->{NAME}: secStart older than "
      ."6 seconds detected, secUnlock will call Zwave_secEnd";
    ZWave_secEnd($hash);
  }
}

sub
ZWave_secEnd($)
{
  my ($hash) = @_;
  return if(!$hash->{secInProgress});

  RemoveInternalTimer($hash->{secTimer});
  my $secStack = $hash->{secStack};
  delete $hash->{secInProgress};
  delete $hash->{secStack};
  delete $hash->{secTimer};
  foreach my $cmd (@{$secStack}) {
    ZWave_SCmd($cmd->{T}, $hash, @{$cmd->{A}});
  }
}

sub
ZWave_secIsSecureClass($$)
{
  my ($hash, $cc_cmd) = @_;
  my $name = $hash->{NAME};

  if ($cc_cmd =~m/(..)(..)/) {
    my ($cc, $cmd) = ($1, $2);
    my $cc_name = $zwave_id2class{lc($cc)};
    my $sec_classes = AttrVal($hash->{endpointParent} ?
                        $hash->{endpointParent} : $name, "secure_classes", "");

    if (($sec_classes =~ m/$cc_name/) && ($cc_name ne 'SECURITY')){
      Log3 $name, 5, "$name: $cc_name is a secured class!";
      return 1;
    }

    # some SECURITY commands need to be encrypted allways
    if ($cc eq '98') {
      if ($cmd eq '02' || # SupportedGet
          $cmd eq '06' || # NetworkKeySet
          $cmd eq '08' ){ # SchemeInherit
        Log3 $name, 5, "$name: Security commands will be encrypted!";
        return 1;
        }
    }
    # these SECURITY commands should not be encrypted
    # SchemeGet = 0x04, NonceGet = 0x40, NonceReport = 0x80
    # MessageEncap = 0x81 is already encrypted
    # MessageEncapNonceGet = 0xc1 is already encrypted
  }
  return 0;
}

sub
ZWave_secSupported($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $id = $hash->{nodeIdHex};

  if (!ZWave_secIsEnabled($hash)) {
    return;
  };

  Log3 $name, 5, "$name: Secured Classes Supported: $arg";

  if ($arg =~ m/(..)(.*)/) {
    if ($1 ne '00') {
      Log3 $name, 1, "$name: Multi part message report for secure classes ".
        "can not be handled!";
    }
    my @sec_classes;
    my $sec_classes = $2;
    for my $sec_classId (grep /../, split(/(..)/, lc($sec_classes))) {
      push @sec_classes, $zwave_id2class{lc($sec_classId)} ?
        $zwave_id2class{lc($sec_classId)} : "UNKNOWN_".lc($sec_classId);
    }
    $attr{$name}{secure_classes} = join(" ", @sec_classes)
      if (@sec_classes);
  }

  # Add new secure_classes to classes if not already present
  # Needed for classes that are only supported with SECURITY
  if ($attr{$name}{secure_classes} && $attr{$name}{classes}) {
    my $classes        = $attr{$name}{classes};
    my $secure_classes = $attr{$name}{secure_classes};
    my $c1;
    my $c2;
    my $s1;
    my $s2;
    my $classname;

    if ($classes =~ m/(.*)(MARK)(.*)/) {
      ($c1, $c2) = ($1, $2 . $3);
    } else {
      ($c1, $c2) = ($classes, "");
    }

    if ($secure_classes =~ m/(.*)(MARK)(.*)/) {
      ($s1, $s2) = ($1, $2 . $3);
    } else {
      ($s1, $s2) = ($secure_classes, "");
    }

    foreach $classname (split(" ", $s1)) {
      if ($c1 !~ m/\b$classname\b/) {
        $c1 = join (" ", $c1, $classname);
      }
    }

    foreach $classname (split(" ", $s2)) {
      if ($c2 !~ m/\b$classname\b/) {
        $c2 = join (" ", $c2, $classname);
      }
    }

    $classes = join (" ", $c1, $c2);
    $classes =~ s/ +/ /gs;
    $attr{$name}{classes} = $classes;
  }
}

sub
ZWave_secNonceReceived($$)
{
  my ($hash, $r_nonce_hex) = @_;
  my $iodev = $hash->{IODev};
  my $name = $hash->{NAME};

  if (!ZWave_secIsEnabled($hash))
  {
    return;
  }

  # if nonce is received, we should have stored a message for encryption
  my $getSecMsg = ZWave_secGetMsg($hash);
  my @secArr = split / /, $getSecMsg, 4;
  my $secMsg = $secArr[0];
  my $type   = $secArr[1];
  my $cmd    = $secArr[3];

  if (!$secMsg) {
    Log3 $name, 1, "$name: Error, nonce reveived but no stored command for ".
      "encryption found";
    return undef;
  }

  my $enc = ZWave_secEncrypt($hash, $r_nonce_hex, $secMsg);
  ZWave_secAddToSendStack($hash, '98'.$enc);
  if ($type eq "set" && $cmd && $cmd !~ m/^config.*request$/) {
    readingsSingleUpdate($hash, "state", $cmd, 1);
    Log3 $name, 5, "$name: type=$type, cmd=$cmd ($getSecMsg)";
    ZWave_secEnd($hash) if ($type eq "set");
  }
  return undef;
}

sub
ZWave_secPutMsg ($$$)
{
  my ($hash, $s, $cmd) = @_;
  my $name = $hash->{NAME};

  $hash = $defs{$hash->{endpointParent}} if($hash->{endpointParent});
  if (!$hash->{secMsg}) {
    my @arr = ();
    $hash->{secMsg} = \@arr;
  }
  push @{$hash->{secMsg}}, $s . " ". $cmd;
  Log3 $name, 5, "$name SECURITY: $s stored for encryption";
}

sub
ZWave_secGetMsg ($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $secMsg = $hash->{secMsg};
  if ($secMsg && @{$secMsg}) {
    my $ret = shift(@{$secMsg});
    if ($ret) {
      Log3 $name, 5, "$name SECURITY: $ret retrieved for encryption";
      return $ret;
    }
  }
  Log3 $name, 1, "$name: no stored commands in Internal secMsg found";
  return "";
}

sub
ZWave_secNonceRequestReceived ($)
{
  my ($hash) = @_;
  if (!ZWave_secIsEnabled($hash)) {
    return;
  }
  ZWave_secStart($hash);
  ZWave_secAddToSendStack($hash, '98'.ZWave_secCreateNonce($hash));
}

sub
ZWave_secIsEnabled ($)
{
  my ($hash) = @_;
  my $secStatus = ReadingsVal($hash->{NAME}, "SECURITY", "DISABLED");
  if ($secStatus =~ m/DISABLED/) {
    Log3 $hash->{NAME}, 1, "$hash->{NAME} SECURITY $secStatus (command dropped)";
    return (0);
  }
  return (1);
}

sub
ZWave_sec ($$)
{
  my ($hash, $arg) = @_;
  return (ZWave_secIsEnabled($hash) ? ("", $arg) : ("",'00'));
}

sub
ZWave_secCreateNonce($)
{
  my ($hash) = @_;
  if (ZWave_secIsEnabled($hash)) {
    my $nonce;
    my $nonce_id;
    my $n=0;

    $hash->{secNonce} = {} if (!$hash->{secNonce});
    foreach my $id (sort keys %{$hash->{secNonce}}) {
      $n++;
    }
    
    my $time = gettimeofday();
    if ($n>50) { #clean up only if more than 50 nonce are active
      foreach my $id (sort keys %{$hash->{secNonce}}) {
        my $dt = $time - $hash->{secNonce}{$id}{timeStamp};
        if ($dt > 10) {
          Log3 $hash->{NAME}, 3, "$hash->{NAME}: SECURITY: nonce "
            .$hash->{secNonce}{$id}{nonce} ."is too old ("
            .sprintf("%d seconds", $dt)
            .") and is removed from list";
          delete($hash->{secNonce}{$id});
          $n--;
        }
      }
    }
    if ($n >10) {
      Log3 $hash->{NAME}, 2, "$hash->{NAME}: SECURITY: multiple nonce warning, "
                          ."there are $n nonce active";
    }
    
    $n=0;
    do {
      $nonce = ZWave_secGetNonce();
      $nonce_id = substr($nonce, 0, 2);
      $n++;
    } until ((!$hash->{secNonce}{$nonce_id}) || $n>512);
    
    if ($n >512) {
      Log3 $hash->{NAME}, 1, "$hash->{NAME}: SECURITY: could not generate "
                              ."unique nonce, ignoring request!";
      return ('00');       
    }

    my $id = substr($nonce, 0 ,2);
  
    $hash->{secNonce} = {} if (!$hash->{secNonce});
  
    $hash->{secNonce}{$id}{nonce} = $nonce;
    $hash->{secNonce}{$id}{timeStamp} = gettimeofday();
  
    return ('80'.$nonce);
  } else {
    return ('00');
  }
}

sub
ZWave_secRetrieveNonce($$)
{
  my ($hash, $s_nonce_id_hex) = @_;
  my $s_nonce_hex;
  my $n=0;
 
  return undef if (!$hash->{secNonce});
  
  # remove old (>10 seconds) entries BEFORE trying to retrieve nonce
  my $time = gettimeofday();
  foreach my $id (sort keys %{$hash->{secNonce}}) {
    $n++;
    my $dt = $time - $hash->{secNonce}{$id}{timeStamp};
    if ($dt > 10) {
      Log3 $hash->{NAME}, 5, "$hash->{NAME}: SECURITY: nonce "
          .$hash->{secNonce}{$id}{nonce} ."is too old ("
          .sprintf("%d seconds", $dt)
          .") and is removed from list";
      delete($hash->{secNonce}{$id});
      $n--;
    }
  }
  if ($n >1) {
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: SECURITY: multiple nonce warning, "
                          ."there are $n nonce active";
  }
  
  if ($hash->{secNonce}{$s_nonce_id_hex}) {
      $s_nonce_hex = $hash->{secNonce}{$s_nonce_id_hex}{nonce};
      delete($hash->{secNonce}{$s_nonce_id_hex});
      return $s_nonce_hex;
  } else {
    return undef;
  }
}

sub
ZWave_secGetNonce()
{
  my $nonce='';
  for (my $i = 0; $i <8; $i++) {
    $nonce .= sprintf "%02x",int(rand(256));
  }
  return $nonce;
}

sub
ZWave_secEncrypt($$$)
{
  my ($hash, $r_nonce_hex, $plain) = @_;
  my $name = $hash->{NAME};
  my $iodev = $hash->{IODev};
  my $id = $hash->{nodeIdHex};

  my $init_enc_key     = pack 'H*', 'a' x 32;
  my $init_auth_key    = pack 'H*', '5' x 32;

  my $s_nonce_hex = ZWave_secGetNonce();
  my $iv = pack 'H*', $s_nonce_hex . $r_nonce_hex;
  my $key = pack 'H*', AttrVal($iodev->{NAME}, "networkKey", "");
  my $enc_key  = ZWave_secEncryptECB($key, $init_enc_key);
  my $auth_key = ZWave_secEncryptECB($key, $init_auth_key);

  my $seq = '00'; # Sequencebyte -> need to be calculated for longer messages
  my $msg_hex = $seq . $plain;
  my $out_hex = ZWave_secEncryptOFB ($enc_key, $iv, $msg_hex);

  my $auth_msg_hex = '8101';
  $auth_msg_hex   .= sprintf "%02x", hex($hash->{nodeIdHex});
  $auth_msg_hex   .= sprintf "%02x", (length ($out_hex))/2;
  $auth_msg_hex   .= $out_hex;

  Log3 $name, 5, "$name: secEncrypt plain:$msg_hex enc:$out_hex";

  my $auth_code_hex = ZWave_secGenerateAuth($auth_key, $iv, $auth_msg_hex);
  my $enc_msg_hex = '81' . $s_nonce_hex . $out_hex . substr($r_nonce_hex, 0, 2)
    . $auth_code_hex;
  return $enc_msg_hex;
}

sub
ZWave_secDecrypt($$$)
{
  my ($hash, $data, $newnonce) = @_;
  my $name = $hash->{NAME};
  my $iodev = $hash->{IODev};

  if (!ZWave_secIsEnabled($hash)) {
    return;
  }

  my $init_enc_key     = pack 'H*', 'a' x 32;
  my $init_auth_key    = pack 'H*', '5' x 32;

  my $key = pack 'H*', AttrVal($iodev->{NAME}, "networkKey", "");
  my $enc_key  = ZWave_secEncryptECB($key, $init_enc_key);
  my $auth_key = ZWave_secEncryptECB($key, $init_auth_key);

  # encrypted message format:
  # data=  bcb328fe5d924a402b2901fc2699cc3bcacd30e0
  # bcb328fe5d924a40 = 8 byte r_nonce
  # 2b2901           = encrypted message, variable length
  # fc               = s_nonce-Id (= first byte of s_nonce)
  # 2699cc3bcacd30e0 = 8 byte authentification code
  if ($data !~ m/^(................)(.*)(..)(................)$/) {
    Log3 $name, 1, "$name: Error, wrong format of encrypted msg";
    ZWave_secEnd($hash);
    return "";
  }
  my ($r_nonce_hex, $msg_hex, $s_nonce_id_hex, $auth_code_hex) = ($1, $2, $3, $4);
  my $s_nonce_hex = ZWave_secRetrieveNonce($hash, $s_nonce_id_hex);
  if (!$s_nonce_hex) {
    Log3 $name, 1, "$name: Error, no send_nonce to decrypt message available";
    ZWave_secEnd($hash);
    return "";
  }
  Log3 $name, 5, "$name: secDecrypt: send_nonce $s_nonce_hex with "
                        ."nonce_id $s_nonce_id_hex retrieved";

  my $iv = pack 'H*', $r_nonce_hex . $s_nonce_hex;
  my $out_hex = ZWave_secEncryptOFB ($enc_key, $iv, $msg_hex);

  Log3 $name, 5, "$name: secDecrypt: decrypted cmd $out_hex";

  # decoding sequence information
  # bit 76       reseved
  # bit   5      second frame (0x20)
  # bit    4     sequenced (0x10)
  # bit     3210 sequenceCounter (0x0f)
  my $seq = hex(substr ($out_hex, 0,2));
  my $sequenced = (($seq & 0x10) ? 1 : 0);
  my $secondFrame = (($seq & 0x20) ? 1 : 0);
  my $sequenceCounter = sprintf "%02x", ($seq & 0x0f);

  Log3 $name, 5, "$name: secDecrypt: Sequencebyte $seq, sequenced ".
    "$sequenced, secondFrame $secondFrame, sequenceCounter $sequenceCounter";

  # Rebuild message for authentification check
  # 81280103 '81' . <from-id> . <to-id> . <len> . <encrMsg>
  my $my_msg_hex = ($newnonce ? 'c1' : '81');
  $my_msg_hex .= sprintf "%02x", hex($hash->{nodeIdHex});
  $my_msg_hex .= '01';
  $my_msg_hex .= sprintf "%02x", (length ($msg_hex))/2;
  $my_msg_hex .= $msg_hex;

  my $my_auth_code_hex = ZWave_secGenerateAuth($auth_key, $iv, $my_msg_hex);
  Log3 $name, 5, "$name: secDecrypt: calculated Authentication code ".
    "$my_auth_code_hex";

  $out_hex = substr($out_hex, 2,length($out_hex)-2);

  if ($auth_code_hex eq $my_auth_code_hex) {
    if ($sequenced && !$secondFrame){ # first frame of sequence message
      ZWave_secStoreFirstFrame($hash, $sequenceCounter, $out_hex);
    } else { # not first frame or not sequenced
      if ($sequenced && $secondFrame){
        my $firstFrame = ZWave_secRetrieveFirstFrame ($hash, $sequenceCounter);
        if ($firstFrame) {
          $out_hex = $firstFrame . $out_hex;
        } else {
        Log3 $name, 1, "$name: secDecrypt: first frame of message (sequence ".
          "$sequenceCounter) for decryption not found!";
        }
      }
      my $decryptedCmd = '000400';
      $decryptedCmd .= sprintf "%02x", hex($hash->{nodeIdHex});
      $decryptedCmd .= sprintf "%02x", (length ($out_hex))/2;
      $decryptedCmd .= $out_hex;

      Log3 $name, 5, "$name: secDecrypt: parsing $decryptedCmd";
      ZWave_Parse($iodev, $decryptedCmd, undef);
      ZWave_secEnd($hash);
    }
  } else {
    Log3 $name, 1, "$name: secDecrypt: Authentification code not verified, "
      ."command $out_hex will be dropped!";
    if ($sequenced && $secondFrame){
      ZWave_secRetrieveFirstFrame ($hash, $sequenceCounter);
    }
    ZWave_secEnd($hash);
  }

  if ($newnonce == 1) {
    ZWave_secAddToSendStack($hash, '98'.ZWave_secCreateNonce($hash));
    #ZWave_Cmd("set", $hash, $hash->{NAME}, "secNonce");
  }

  return "";
}

sub
ZWave_secStoreFirstFrame ($$$) {
  my ($hash, $seqcnt, $framedata) = @_;
  my $framename = "Frame_$seqcnt";
  $hash->{$framename} = $framedata;
}

sub
ZWave_secRetrieveFirstFrame ($$) {
  my ($hash, $seqcnt) = @_;
  my $framename = "Frame_$seqcnt";
  if ($hash->{$framename}) {
    my $ret = $hash->{$framename};
    if ($ret) {
      $hash->{$framename} = undef;
      return $ret;
    }
  }
  Log3 $hash->{NAME}, 1, "$hash->{NAME}: first frame of message (sequence ".
    "$seqcnt) for decryption not found!";
  return undef;
}

sub
ZWave_secEncryptECB ($$)
{
  my ($key, $iv) = @_;
  # $key and $iv as 'packed' hex-strings
  my $cipher_ecb = Crypt::Rijndael->new ($key, Crypt::Rijndael::MODE_ECB() );
  return $cipher_ecb->encrypt($iv);
}

sub
ZWave_secEncryptOFB ($$$)
{
  my ($key, $iv, $in_hex) = @_;
  # $key and $iv as 'packed' hex-strings, $in_hex as hex-string
  my $cipher_ofb = Crypt::Rijndael->new($key,
                      Crypt::Rijndael::MODE_OFB() );
  $cipher_ofb->set_iv($iv);

  # make sure that the blocksize is 16 bytes / 32 characters
  my $in_len = length($in_hex);
  if ($in_len % 32) {
    $in_hex .= '0' x (32 - ($in_len % 32));
  }
  my $out_hex = unpack 'H*', $cipher_ofb->encrypt(pack 'H*', $in_hex);
  return (substr ($out_hex, 0, $in_len));
}

sub
ZWave_secGenerateAuth ($$$)
{
  my ($key, $iv, $msg_hex) = @_;

  my $cipher_ecb = Crypt::Rijndael->new ($key, Crypt::Rijndael::MODE_ECB() );
  my $enc_iv = ZWave_secEncryptECB($key, $iv);

  # make sure that the blocksize is 16 bytes / 32 characters
  my $msg_len = length($msg_hex);
  if ($msg_len % 32) {
    $msg_hex .= '0' x (32 - ($msg_len % 32));
  }

  my $temp=0;
  my $buff=0;
  my $buff_hex="";
  # xOR first block with encrypted iv
  # encrypt the result, repeat for all blocks using encrypted output
  # as input for xOR of next block
  for (my $i = 0; $i < (length($msg_hex)/32); $i++) {
    $buff_hex = substr($msg_hex, $i*32, 32);
    $buff = pack 'H*', $buff_hex;
    $temp = $buff ^ $enc_iv;
    $enc_iv = $cipher_ecb->encrypt($temp);
  };
  # only 8 byte used for message authentification code
  return unpack 'H16', $enc_iv;
}

sub
ZWave_secNetworkkeyEncode ($$$$)
{
  my ($nonce_hex, $mynonce_hex, $key_plain_hex, $id_hex) = @_;
  #my $name ="ZWave_secNetworkkeySet";

  # The NetworkKeySet command message will be encrcpted and authentificated
  # with temporary keys that are created with the networkkey and default
  # keys for encryption and authentification as given below.
  my $init_enc_key     = pack 'H*', 'a' x 32;
  my $init_auth_key    = pack 'H*', '5' x 32;
  my $key_zero         = pack 'H*', '0' x 32;
  my $nonce            = pack 'H*', $nonce_hex;
  my $mynonce          = pack 'H*', $mynonce_hex;

  my $enc_key  = ZWave_secEncryptECB($key_zero, $init_enc_key);
  my $auth_key = ZWave_secEncryptECB($key_zero, $init_auth_key);

  my $iv = pack 'H*', $mynonce_hex . $nonce_hex;

  # build 'plain-text' message to be encrypted
  # 0x00 = sequence byte -> only one frame
  # 0x98 = Security Class
  # 0x06 = NetworkKeySet
  $key_plain_hex = '009806'.$key_plain_hex;
  my $out_hex = ZWave_secEncryptOFB($enc_key, $iv, $key_plain_hex);

  ############ MAC generation ############################
  # build message for encryption
  # command, source-id, target-id
  # 0x81="Security_Message_Encapsulation" 0x01=Souce-ID (Controller = 0x01)
  my $in_hex = '8101' . $id_hex;
  $in_hex .= sprintf "%02x", length($out_hex)/2; # length of command
  $in_hex .= $out_hex; # encrypted network key

  my $auth_hex = ZWave_secGenerateAuth ($auth_key, $iv, $in_hex);

  # build encrypted message
  # Command Class will be added during sending -> do not prepend
  # 0x81 = Security_Message_Encapsulation
  $out_hex = '81' . $mynonce_hex . $out_hex . substr($nonce_hex, 0, 2) .
    $auth_hex;

  return $out_hex;
}

##############################################
#  SECURITY (end)
##############################################

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

  my $version = $hash->{".vclasses"}{$cl};
  if(defined($version) && ($type eq "get" || $type eq "set")) {
    my %h;
    if($version > 0) {
      map {
        my $zv = $zwave_classVersion{$_};
        if(!$zv || ((!$zv->{min} || $zv->{min} <= $version) &&
                    (!$zv->{max} || $zv->{max} >= $version))) {
          $h{$_} = $ptr->{$_};
        }
      } keys %{$ptr};
    }
    $ptr = \%h;
  }

  return $ptr;
}

my $zwave_cbid = 0;
my %zwave_cbid2dev;
sub
ZWave_callbackId($)
{
  my ($p) = @_;
  if(ref($p) eq "HASH") {
    $zwave_cbid =  0 if($zwave_cbid == 255);
    $zwave_cbid2dev{++$zwave_cbid} = $p;
    return sprintf("%02x", $zwave_cbid);
  }
  return $zwave_cbid2dev{hex($p)};
}

sub
ZWave_wakeupTimer($$)
{
  my ($hash, $direct) = @_;
  my $now = gettimeofday();
  my $wnmi_delay = AttrVal($hash->{NAME}, "WNMI_delay", 2);

  if(!$hash->{wakeupAlive}) {
    $hash->{wakeupAlive} = 1;
    $hash->{lastMsgSent} = $now;
    InternalTimer($now+0.1, "ZWave_wakeupTimer", $hash, 0);

  } elsif(!$direct && $now - $hash->{lastMsgSent} > $wnmi_delay) {
    if(!$hash->{SendStack}) {
      my $nodeId = $hash->{nodeIdHex};
      my $cmdEf  = (AttrVal($hash->{NAME},"noExplorerFrames",0)==0 ? "25":"05");
      # wakeupNoMoreInformation
      IOWrite($hash,
              $hash->{homeId}.($hash->{route} ? ",".$hash->{route} : ""),
              "0013${nodeId}028408${cmdEf}".ZWave_callbackId($hash));
      $hash->{lastMsgSent} = $now;
    }
    delete $hash->{wakeupAlive};

  } else {
    return if($direct);
    InternalTimer($now+0.1, "ZWave_wakeupTimer", $hash, 0);

  }
}

sub
ZWave_isWakeUp($)
{
  my ($h) = @_;
  $h->{isWakeUp} = (index(AttrVal($h->{NAME}, "classes", ""), "WAKE_UP") >= 0)
    if(!defined($h->{isWakeUp}));
  return $h->{isWakeUp};
}

sub
ZWave_addCRC16($)
{
  my ($msg) = @_;
  return $msg if($msg !~ m/13(..)(..)(.*)(....)$/);
  my ($tgt, $olen, $omsg, $sfx) = ($1, $2, $3, $4);
  $msg = sprintf("13%s%02x5601%s%s%s", $tgt, length($omsg)/2+4,
                 $omsg, uc(ZWave_CRC16("5601$omsg")), $sfx);
  return $msg;
}

# stack contains type:hexcode
# type is: set / sentset, get / sentget / sentackget
# sentset will be discarded after ack, sentget needs ack (->sentackget) then msg
# next discards either state.
# acktpye: retry, next, ack or msg
sub
ZWave_processSendStack($$;$)
{
  my ($hash,$ackType, $omsg) = @_;

  delete($hash->{delayedProcessing});
  my $ss = $hash->{SendStack};
  if(!$ss) {
    readingsSingleUpdate($hash, "timeToAck", 
                      sprintf("%0.3f", gettimeofday()-$hash->{lastMsgSent}), 0)
      if($ackType eq "ack" && $hash->{lastMsgSent});
    return;
  }
  #Log 1, "pSS: $hash->{NAME}, $ackType $ss->[0]".($omsg ? "  omsg:$omsg" : "");

  if ($ackType eq "next") {
    if($ss->[0] =~ m/^sent(.*?):13....98(.*)$/) { # only for security commands
      my $secMsg = $hash->{secMsg};
      if ($secMsg && @{$secMsg}) {
        Log3 $hash->{NAME}, 1, "$hash->{NAME}: NO_ACK received during secured "
          ."command: $secMsg->[0], command will be removed from security stack";
        shift(@{$secMsg});
        ZWave_secEnd($hash);
      }
    }
  }

  if($ackType eq "retry") {
    $ss->[0] =~ m/^(.*)(set|get):(.*)$/;
    $ss->[0] = "$2:$3";
    return;
  }

  my $now = gettimeofday();
  if($ss->[0] =~ m/^sent(.*?):(.*)(..)$/) {
    my ($stype,$smsg, $cbid) = ($1,$2,$3);
    if($ackType eq "ack") {
      if($cbid ne $omsg) {
        Log 4, "ZWave: wrong callbackid $omsg received, expecting $cbid";
        return;
      }
      readingsSingleUpdate($hash, "timeToAck", 
                        sprintf("%0.3f", $now-$hash->{lastMsgSent}), 0)
        if($hash->{lastMsgSent});
      if($stype eq "get") {
        $ss->[0] = "sentackget:$smsg$cbid";
        return;
      }

    } elsif($stype eq "ackget" && $ackType eq "msg") {# compare answer class
      $smsg = "13xxxx$1" if($smsg =~ /^......600d....(.*)/);
      my $cs = substr($smsg, 6, 2);
      my $cg = substr($omsg, 2, 2);
      return if($cs ne $cg);
    }

    shift @{$ss};
    $hash->{cmdsPending} = int(@{$ss});
    RemoveInternalTimer($hash) if(!ZWave_isWakeUp($hash));
  }

  if(@{$ss} == 0) {
    delete $hash->{SendStack};
    return;
  }

  $ss->[0] =~ m/^([^:]*?):(.*)$/;
  my ($type, $msg) = ($1, $2);

  my $iomsg = $hash->{useCRC16} ? ZWave_addCRC16($msg) : $msg;
  IOWrite($hash,
          $hash->{homeId}.($hash->{route}?",".$hash->{route}:""),
          "00$iomsg");
  $ss->[0] = "sent$type:$msg";

  $hash->{lastMsgSent} = $now;
  $zwave_lastHashSent = $hash;

  if(!ZWave_isWakeUp($hash)) {
    InternalTimer($hash->{lastMsgSent}+5, sub { # zme generates NO_ACK after 4s
      Log 2, "ZWave: No ACK from $hash->{NAME} after 5s for $ss->[0]";
      ZWave_processSendStack($hash, "next");
    }, $hash, 0);
  }
}

# packs multiple gets into a MULTI_CMD-get, may reorder
sub
ZWave_packSendStack($)
{
  my ($hash) = @_;

  my (@ns, @ms, $sfx, $cmd, $id);
  my $ncmd = 0;
  for my $se (@{$hash->{SendStack}}) {
    if($se =~ m/^get:13(..)(...*)(....)$/) {
      ($id, $cmd, $sfx) = ($1, $2, $3);
      if($cmd =~ m/^..8f01(..)(.*)/i) { # already Multi-cmd
        $ncmd += $1; $cmd = $2;
      } else {
        $ncmd++;
      }
      push(@ms, $cmd);
    } else {
      push(@ns, $se);
    }
  }
  return if($ncmd < 2 || @ms < 2);

  $cmd = join("", @ms);
  push @ns, sprintf("get:13$id%02x8f01%02x%s%s",
                     length($cmd)/2+3, $ncmd, $cmd, $sfx);
  $hash->{SendStack} = \@ns;
  $hash->{cmdsPending} = int(@ns);
}

sub
ZWave_addToSendStack($$$)
{
  my ($hash, $type, $cmd) = @_;
  if(!$hash->{SendStack}) {
    my @empty;
    $hash->{SendStack} = \@empty;
  }
  my $ss = $hash->{SendStack};
  push @{$ss}, "$type:$cmd";
  $hash->{cmdsPending} = int(@{$ss});
  #Log 1, "aTSS: $hash->{NAME}, $type, $cmd / L:".int(@{$ss});

  if(ZWave_isWakeUp($hash)) {
    # SECURITY XXX
    if($cmd =~ m/^......988[01].*/) {
      Log3 $hash->{NAME}, 5, "$hash->{NAME}: Sendstack bypassed for $cmd";
    } else {
      if($hash->{useMultiCmd}) {
        ZWave_packSendStack($hash);
        if($hash->{INTRIGGER}) { # Allow repacking of multiple gets on WUN
          if(!$hash->{delayedProcessing}) {
            $hash->{delayedProcessing} = 1;
            InternalTimer(1, sub(){ZWave_processSendStack($hash, "next");}, 0);
          }
          return;
        }
      }
      return "Scheduled for sending after WAKEUP" if(!$hash->{wakeupAlive});
    }

  } else { # clear commands without 0113 and 0013
    my $now = gettimeofday();
    if(@{$ss} > 1 && $now-$hash->{lastMsgSent} > 5) {
      Log3 $hash, 2,
        "ERROR: $hash->{NAME}: cleaning commands without ack after 5s";
      delete $hash->{SendStack};
      $hash->{cmdsPending} = 0;
      return ZWave_addToSendStack($hash, $type, $cmd);
    }
  }
  ZWave_processSendStack($hash, "next") if(@{$ss} == 1);
  return undef;
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

  if($msg =~ m/^01(..)(..*)/) { # 01==ANSWER from the ZWDongle
    my ($cmd, $arg) = ($1, $2);
    $cmd = $zw_func_id{$cmd} if($zw_func_id{$cmd});
    if($cmd eq "ZW_SEND_DATA") { # 011301: data was sent.
      if($arg != 1) {
        if($zwave_lastHashSent) {
          my $hash = $zwave_lastHashSent;
          readingsSingleUpdate($hash, "SEND_DATA", "failed:$arg", 1);
          $arg = "transmit queue overflow" if($arg == 0);
          Log3 $ioName, 2, "ERROR: cannot SEND_DATA to $hash->{NAME}: $arg";
          ZWave_processSendStack($hash, "retry");

        } else {
          Log3 $ioName, 2, "ERROR: cannot SEND_DATA: $arg (unknown device)";
        }
      }
      return "";
    }
    if($cmd eq "SERIAL_API_SET_TIMEOUTS" && $arg =~ m/(..)(..)/) {
      Log3 $ioName, 2, "SERIAL_API_SET_TIMEOUTS: ACK:$1 BYTES:$2";
      return "";
    }
    if($cmd eq "ZW_REMOVE_FAILED_NODE_ID" ||
       $cmd eq "ZW_REPLACE_FAILED_NODE") {
      my $retval;
           if($arg eq "00") { $retval = 'failedNodeRemoveStarted';
      } elsif($arg eq "02") { $retval = 'notPrimaryController';
      } elsif($arg eq "04") { $retval = 'noCallbackFunction';
      } elsif($arg eq "08") { $retval = 'failedNodeNotFound';
      } elsif($arg eq "10") { $retval = 'failedNodeRemoveProcessBusy';
      } elsif($arg eq "20") { $retval = 'failedNodeRemoveFail';
      } else                { $retval = 'unknown_'.$arg; # should never happen
      }
      DoTrigger($ioName, "$cmd $retval");
      return "";
    }

    if($cmd eq "ZW_REQUEST_NETWORK_UPDATE") {
      my $retval;
           if($arg eq "00") { $retval = 'selfOrNoSUC';
      } elsif($arg eq "01") { $retval = 'started';
      } else                { $retval = 'unknown_'.$arg; # should never happen
      }
      DoTrigger($ioName, "$cmd $retval");
      return "";
    }

    if($cmd eq "ZW_ASSIGN_SUC_RETURN_ROUTE" ||
       $cmd eq "ZW_DELETE_SUC_RETURN_ROUTE" ||
       $cmd eq "ZW_ASSIGN_RETURN_ROUTE" ||
       $cmd eq "ZW_DELETE_RETURN_ROUTE" ||
       $cmd eq "ZW_SEND_SUC_ID")  {
      my $retval;
           if($arg eq "00") { $retval = 'alreadyActive';
      } elsif($arg eq "01") { $retval = 'started';
      } else                { $retval = 'unknown_'.$arg; # should never happen
      }
      DoTrigger($ioName, "$cmd $retval");
      return "";
    }

    if($cmd eq "ZW_SET_SUC_NODE_ID") {
      my $retval;
           if($arg eq "00") { $retval = 'failed';
      } elsif($arg eq "01") { $retval = 'ok';
      } else                { $retval = 'unknown_'.$arg; # should never happen
      }
      DoTrigger($ioName, "$cmd $retval");
      return "";
    }

    if($cmd eq "ZW_SET_PRIORITY_ROUTE" && $arg =~ m/(..)(..)/) {
      DoTrigger($ioName, "$cmd node $1 result $2");
      return "";
    }

    foreach my $h (keys %zwave_parseHook) {
      if("$cmd:$arg" =~ m/$h/) {
        my $fn = $zwave_parseHook{$h};
        delete $zwave_parseHook{$h};
        $fn->($arg);
        return "";
      }
    }

    Log3 $ioName, 4, "$ioName unhandled ANSWER: $cmd $arg";
    return "";
  }

  if($msg =~ m/^00(..)(..*)/) { # 00==REQUEST from the ZWDongle
    my ($cmd, $arg) = ($1, $2);
    $cmd = $zw_func_id{$cmd} if($zw_func_id{$cmd});
    if($cmd eq "ZW_SET_DEFAULT") {
      my $retval;
           if($arg eq "01") { $retval = 'done';
      } else                { $retval = 'unknown_'.$arg; # should never happen
      }
      DoTrigger($ioName, "$cmd $retval");
      return "";
    }
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

  my $rawMsg = "CMD:$cmd ID:$id ARG:$arg"; # No fmt change, Forum #49165
  Log3 $ioName, 4, $rawMsg ." CB:$callbackid";
  my $hash = ZWave_callbackId($callbackid);

  if($cmd eq 'ZW_ADD_NODE_TO_NETWORK' ||
     $cmd eq 'ZW_REMOVE_NODE_FROM_NETWORK') {
    my @vals = ("learnReady", "nodeFound", "slave",
                "controller", "protocolDone", "done", "failed");
    $evt = ($id eq "00" || hex($id)>@vals+1) ? "unknownArg" : $vals[hex($id)-1];
    if(($evt eq "slave" || $evt eq "controller") &&
       $arg =~ m/(..)....(..)..(.*)$/) {
      my ($id,$type6,$classes) = ($1, $2, $3);
      return ZWave_SetClasses($homeId, $id, $type6, $classes)
        if($cmd eq 'ZW_ADD_NODE_TO_NETWORK');
    }

    if($evt eq "protocolDone" && $arg =~ m/(..)../) {
      my $dh = $modules{ZWave}{defptr}{"$homeId $1"};
      return "" if(!$dh);

      my $addSecure = $iodev->{addSecure};      # addNode off deletes it

      AnalyzeCommand(undef, "set $ioName addNode off")
        if($cmd eq 'ZW_ADD_NODE_TO_NETWORK');

      ZWave_wakeupTimer($dh, 1) if(ZWave_isWakeUp($dh));

      return "" if($addSecure && ZWave_secIncludeStart($dh, $iodev) == 1);
      return ZWave_execInits($dh, 0);
    }

    # addNode off generates ZW_ADD_NODE_TO_NETWORK:done sometimes (#51411)
    if($evt eq "failed" && $cmd eq 'ZW_ADD_NODE_TO_NETWORK') {
      asyncOutput($iodev->{addCL}, "addNode failed");
      AnalyzeCommand(undef, "set $ioName addNode off")
    }

  } elsif($cmd eq "ZW_APPLICATION_UPDATE") {
    if($arg =~ m/....(..)..(.*)$/) {
      my ($type6,$classes) = ($1, $2);
      my $ret = ZWave_SetClasses($homeId, $id, $type6, $classes);

      $hash = $modules{ZWave}{defptr}{"$homeId $id"};
      if($hash) {
        if(!AttrVal($hash->{NAME}, "noWakeupForApplicationUpdate", 0)) { # 50090
          if(ZWave_isWakeUp($hash)) {
            ZWave_wakeupTimer($hash, 1);
            ZWave_processSendStack($hash, "next");
          }
        }

        if(!$ret) {
          readingsSingleUpdate($hash, "CMD", $cmd, 1); # forum:20884
          return $hash->{NAME};
        }
      } else {
        InternalTimer(1, sub(){  # execInits for createNode
          $hash = $modules{ZWave}{defptr}{"$homeId $id"};
          ZWave_execInits($hash, 0) if($hash);
        }, 0);
      }
      return $ret;

    } elsif($callbackid eq "10") {
      $evt = 'sucId '.hex($id);
      DoTrigger($ioName, "$cmd $evt");
      Log3 $ioName, 4, "$ioName $cmd $evt";
      return "";

    } elsif($callbackid eq "20") {
      $evt = 'deleteDone '.hex($id);
      DoTrigger($ioName, "$cmd $evt");
      Log3 $ioName, 4, "$ioName $cmd $evt";
      return "";

    } elsif($callbackid eq "40") {
      $evt = 'addDone '.hex($id);
      DoTrigger($ioName, "$cmd $evt");
      Log3 $ioName, 4, "$ioName $cmd $evt";
      return "";

    } elsif($callbackid eq "81") {
      Log3 $ioName, 2, "ZW_REQUEST_NODE_INFO failed ".hex($id);
      return "";

    } else {
      Log3 $ioName, 2, "ZW_APPLICATION_UPDATE unknown $callbackid";
      return "";

    }

  } elsif($cmd eq "ZW_SEND_DATA") { # 0013cb00....
    my %msg = ('00'=>'OK', '01'=>'NO_ACK', '02'=>'FAIL',
               '03'=>'NOT_IDLE', '04'=>'NOROUTE' );
    my $lmsg = ($msg{$id} ? $msg{$id} : "UNKNOWN_ERROR");

    Log3 $ioName, ($id eq "00" ? 4 : 2),
        "$ioName transmit $lmsg for CB $callbackid, target ".
        ($hash ? $hash->{NAME} : "unknown");
    if($id eq "00") {
      my $name="";
      if($hash) {
        ZWave_processSendStack($hash, "ack", $callbackid);
        readingsSingleUpdate($hash, "transmit", $lmsg, 0);
        if($iodev->{showSetInState}) {
          my $lCU = $hash->{lastChannelUsed};
          my $lname = $lCU ? $lCU : $hash->{NAME};
          my $state = ReadingsVal($lname, "state", "");
          if($state =~ m/^set_(.*)$/) {
            readingsSingleUpdate($defs{$lname}, "state", $1, 1);
            $name = $lname;
          }
        }
      }
      delete($hash->{lastChannelUsed});
      return $name;

    } else { # Wait for the retry timer to remove this cmd from the stack.
      return "" if(!$hash);
      #readingsSingleUpdate($hash, "state", "TRANSMIT_$lmsg", 1); #Forum #57781
      readingsSingleUpdate($hash, "transmit", $lmsg, 1);
      return $hash->{NAME};
    }

  } elsif($cmd eq "ZW_SET_LEARN_MODE") {
         if($id eq "01") { $evt = 'started';
    } elsif($id eq "06") { $evt = 'done'; # $arg = new NodeId
    } elsif($id eq "07") { $evt = 'failed';
    } elsif($id eq "80") { $evt = 'deleted';
    } else               { $evt = 'unknown'; # should never happen
    }

  } elsif($cmd eq "ZW_REQUEST_NODE_NEIGHBOR_UPDATE") {
         if($id eq "21") { $evt = 'started';
    } elsif($id eq "22") { $evt = 'done';
    } elsif($id eq "23") { $evt = 'failed';
    } else               { $evt = 'unknown'; # should never happen
    }
    if($hash) {
      readingsSingleUpdate($hash, "neighborUpdate", $evt, 1);
      return $hash->{NAME};
    }

  } elsif($cmd eq "ZW_REMOVE_FAILED_NODE_ID") {
         if($id eq "00") { $evt = 'nodeOk';
    } elsif($id eq "01") { $evt = 'failedNodeRemoved';
    } elsif($id eq "02") { $evt = 'failedNodeNotRemoved';
    } else               { $evt = 'unknown_'.$id; # should never happen
    }

  } elsif($cmd eq "ZW_REPLACE_FAILED_NODE") {
         if($id eq "00") { $evt = 'nodeOk';
    } elsif($id eq "03") { $evt = 'failedNodeReplace';
    } elsif($id eq "04") { $evt = 'failedNodeReplaceDone';
    } elsif($id eq "05") { $evt = 'failedNodeRemoveFailed';
    } else               { $evt = 'unknown_'.$id; # should never happen
    }

  } elsif($cmd eq "ZW_ASSIGN_SUC_RETURN_ROUTE" ||
          $cmd eq "ZW_DELETE_SUC_RETURN_ROUTE" ||
          $cmd eq "ZW_ASSIGN_RETURN_ROUTE" ||
          $cmd eq "ZW_DELETE_RETURN_ROUTE" ||
          $cmd eq "ZW_SEND_SUC_ID")  {
         if($id eq "00") { $evt = 'transmitOk';
    } elsif($id eq "01") { $evt = 'transmitNoAck';
    } elsif($id eq "02") { $evt = 'transmitFail';
    } elsif($id eq "03") { $evt = 'transmitFailNotIdle';
    } elsif($id eq "04") { $evt = 'transmitNoRoute';
    } else               { $evt = 'unknown_'.$id; # should never happen
    }

  } elsif($cmd eq "ZW_REQUEST_NETWORK_UPDATE")  {
         if($id eq "00") { $evt = 'done';
    } elsif($id eq "01") { $evt = 'abort';
    } elsif($id eq "02") { $evt = 'wait';
    } elsif($id eq "03") { $evt = 'disabled';
    } elsif($id eq "04") { $evt = 'overflow';
    } else               { $evt = 'unknown_'.$id; # should never happen
    }

  } elsif($cmd eq "ZW_SET_SUC_NODE_ID") {
         if($id eq "05") { $evt = 'callbackSucceeded';
    } elsif($id eq "06") { $evt = 'callbackFailed';
    } else               { $evt = 'unknown_'.$id; # do not know
    }

  } elsif($cmd eq "ZW_CONTROLLER_CHANGE" ||
          $cmd eq "ZW_CREATE_NEW_PRIMARY") {
    my @vals = ("learnReady", "nodeFound", "slave","controller", "protocolDone",
                "done", "failed");                # slave should never happen
    $evt = ($id eq "00" || hex($id)>@vals+1) ? "unknownArg" : $vals[hex($id)-1];
    if($cmd eq "ZW_CREATE_NEW_PRIMARY" && $evt eq "protocolDone") {
      AnalyzeCommand(undef, "set $ioName createNewPrimary stop");
    }
    if($cmd eq "ZW_CONTROLLER_CHANGE" && $evt eq "protocolDone") {
      AnalyzeCommand(undef, "set $ioName addNode off");
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

  if($arg =~ m/^(..)(.*)/) {
    my $l1 = hex($1);
    my $l2 = length($2)/2;
    if($l1 > $l2) {
      Log3 $ioName, $2, "Packet with short length ($arg)";
      return "";
    }
    $arg = substr($arg, 0, ($l1+1)*2) if($l1 < $l2); #79659
  }

  if($arg =~ m/^(..)(..)(.*)/ && $2 eq "c6") { # Danfoss Living Strangeness
    Log3 $ioName, 4, "Class mod for Danfoss ($2)";
    $arg = sprintf("%s%02x%s", $1, hex($2) & 0x7f, $3);
  }

  if($arg =~ /^..5601(.*)(....)/) { # CRC_16_ENCAP: Unwrap encapsulated command
    #Log3 $ioName, 4, "CRC FIX, MSG: ($1)"; # see Forum #23494
    my $crc16 = ZWave_CRC16("5601".$1);
    if (lc($2) eq lc($crc16)) {
      $arg = sprintf("%02x$1", length($1)/2);
    } else {
      Log3 $ioName, 4, "$ioName CRC_16 checksum mismatch, received $2," .
       " calculated $crc16";
      return "";
    }
  }

  my ($baseHash, $baseId, $ep) = ("",$id,"");
  if($arg =~ /^..6006(..)(.*)/) { # MULTI_CHANNEL CMD_ENCAP, V1, Forum #36126
    $ep = $1;
    $baseHash = $modules{ZWave}{defptr}{"$homeId $id"};
    $id = "$id$ep";
    $arg = sprintf("%02x$2", length($2)/2);
  }
  if($arg =~ /^..600d(..)(..)(.*)/) { # MULTI_CHANNEL CMD_ENCAP, V2
    $ep = sprintf("%02x", hex($1 ne "00" ? $1 : $2) & 0x7f); # Forum #50176
    if($ep ne "00") {
      $baseHash = $modules{ZWave}{defptr}{"$homeId $id"};
      $id = "$id$ep";
    }
    $arg = sprintf("%02x$3", length($3)/2);
  }
  $hash = $modules{ZWave}{defptr}{"$homeId $id"};
  $baseHash = $hash if(!$baseHash);


  if(!$hash) {
    if(!$baseHash) {
      Log3 $ioName, 4, "ZWave: unknown message $msg for ID $id";
      return "";
    }
    # autocreate the device when pressing the remote button (Forum #43261)
    $id=hex($id); $baseId=hex($baseId); $ep=hex($ep);
    my $nn = "ZWave_Node_$baseId".($ep eq "0" ? "" : ".$ep");
    my $ret = "UNDEFINED $nn ZWave $homeId $id";
    Log3 $ioName, 3, "$ret, please define it. Triggered by $msg.";
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

    my $hookVeto = 0;
    foreach my $h (keys %zwave_parseHook) {
      if("$id:$arg" =~ m/$h/) {
        my $fn = $zwave_parseHook{$h};
        delete $zwave_parseHook{$h};
        $hookVeto++ if($fn->($hash, $arg));
      }
    }

    if(!$hookVeto) {
      my $matched = 0;
      foreach my $k (keys %{$ptr}) {
        if($arg =~ m/^$k/) {
          my $val = $ptr->{$k};
          my @val = ($val);
          @val = eval $val if(index($val, '$') >= 0);
          push @event, @val if(defined($val[0]));
          $matched++;
        }
      }
      push @event, "UNPARSED:$className $arg" if(!$matched);
    }
  }

  if($arg =~ m/^028407/) { # wakeup:notification (WUN)
    if($hash->{ignoreDupMsg} && $hash->{wakeupAlive}) { # Ignore 2nd WUN
      Log3 $name, 3, "$name: ignore duplicate WUN";
      return ""
    }
    ZWave_wakeupTimer($baseHash, 1);
    ZWave_processSendStack($baseHash, "next");

  } else {
    if($hash->{ignoreDupMsg} && $callbackid ne "00") {
      my $hp = hex($callbackid);
      if($zwave_cbid2dev{$hp}) {
        delete $zwave_cbid2dev{$hp};
      } else {
        Log3 $name, 3, "$name: ignore duplicate answer $event[0]";
        return "";
      }
    }
    ZWave_processSendStack($baseHash, "msg", $arg)
      if(!ZWave_isWakeUp($hash) || $hash->{wakeupAlive});

  }

  return "" if(!@event);

  readingsBeginUpdate($hash);
  for(my $i = 0; $i < int(@event); $i++) {
    next if($event[$i] eq "");
    my ($vn, $vv) = split(":", $event[$i], 2);
    readingsBulkUpdate($hash, $vn, $vv);
    readingsBulkUpdate($hash, "reportedState", $vv)
        if($vn eq "state");     # different from set
  }
  readingsBulkUpdate($hash, "rawMsg", $rawMsg)
        if(AttrVal($name, "eventForRaw", undef));
  readingsEndUpdate($hash, 1);

  if($hash->{asyncGet} && $msg =~ m/$hash->{asyncGet}{re}/) {
    RemoveInternalTimer($hash->{asyncGet});
    asyncOutput($hash->{asyncGet}{CL}, join("\n", @event));
    delete($hash->{asyncGet});
  }
  return join("\n", @event) if($srcCmd);
  return $name;
}


#####################################
sub
ZWave_Undef($$)
{
  my ($hash, $arg) = @_;
  my $homeId = $hash->{homeId};
  my $id = $hash->{nodeIdHex};
  delete $modules{ZWave}{defptr}{"$homeId $id"};
  return undef;
}

#####################################
sub
ZWave_computeRoute($;$)
{
  my ($spec,$attrVal) = @_;
  for my $dev (devspec2array($spec)) {
    my $av = AttrVal($dev, "zwaveRoute", $attrVal);
    next if(!$av);

    my @h;
    for my $r (split(" ", $av)) {
      if(!$defs{$r} || $defs{$r}{TYPE} ne "ZWave") {
        my $msg = "zwaveRoute: $r is not a ZWave device";
        Log 1, $msg;
        return $msg;
      }
      push(@h, $defs{$r}{nodeIdHex});
    }
    $defs{$dev}{route} = join("",@h);
  }
  return undef;
}

sub
ZWave_Attr(@)
{
  my ($type, $devName, $attrName, $param) = @_;
  my $hash = $defs{$devName};

  if($attrName eq "zwaveRoute") {
    if($type eq "del") {
      delete $hash->{route};
      return undef;
    }
    return ZWave_computeRoute($devName, $param) if($init_done);
    InternalTimer(1, "ZWave_computeRoute", "TYPE=ZWave", 0);
    return undef;

  } elsif($attrName eq "ignoreDupMsg") {
    if($type eq "del") {
      delete $hash->{ignoreDupMsg};
    } else {
      $hash->{ignoreDupMsg} = (defined($param) ? $param : 1);
    }
    return undef;

  } elsif($attrName eq "vclasses") {
    if($type eq "del") {
      $hash->{".vclasses"} = {};
      return undef;
    }
    my %h = map { split(":", $_) } split(" ", $param);
    $hash->{".vclasses"} = \%h;
    return undef;

  } elsif($attrName eq "useMultiCmd") {
    if($type eq "del") {
      delete $hash->{useMultiCmd};
      return undef;
    }
    my $a = ($attr{$devName} ? $attr{$devName}{classes} : "");
    return "useMultiCmd: unsupported device, see help ZWave for details"
        if(!$a || !($a =~ m/MULTI_CMD/ && $a =~ m/WAKE_UP/));
    $hash->{useMultiCmd} = 1;
    return undef;

  } elsif($attrName eq "useCRC16") {
    if($type eq "del") {
      delete $hash->{useCRC16};
      return undef;
    }
    my $a = ($attr{$devName} ? $attr{$devName}{classes} : "");
    return "useCRC16: unsupported device, see help ZWave for details"
        if(!$a || $a !~ m/CRC_16_ENCAP/ ||
           ReadingsVal($devName, "SECURITY", "") eq "ENABLED");
    $hash->{useCRC16} = 1;
    return undef;
  }

  return undef;
}

sub
ZWave_duration($)
{
  my ($duration) = @_;
  my $time = hex($duration);
  $time = ($time - 0x7f) * 60 if($time>0x7f && $time<=0xfd);
  return (lc($duration) eq "fe" ? "unknown" : "$time seconds");
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
  $cmd .= " (numeric code $h->{index})" if(defined($h->{index}));
  my $ret = "Help for $cmd:<br>".$h->{Help};

  my $hi = $h->{Item};
  $ret .= "Possible values: ".
          join(", ", map {"$_ ($hi->{$_})"} sort keys %{$hi})."<br>"
    if($hi);
  return $ret;
}

sub
ZWave_getPic($$)
{
  my ($iodev, $model) = @_;
  
  my $hs = AttrVal($iodev, "helpSites", $zwave_allHelpSites);
  for my $n (split(",", $hs)) {
    my $img = $zwave_img{$n}{$model};
    next if(!$img);
    my $fn = $attr{global}{modpath}."/www/deviceimages/zwave/$img";
    if(!-f $fn) {      # Cache the picture
      my $url = $n eq "alliance" ? 
        "http://products.z-wavealliance.org/ProductImages/Index?productName=":
        "http://fhem.de/deviceimages/zwave/";
      Log 3, "ZWave: downloading $url/$img for $model";
      my $data = GetFileFromURL("$url/$img");
      if($data && open(FH,">$fn")) {
        binmode(FH);
        print FH $data;
        close(FH)
      }
    }
    return "$FW_ME/deviceimages/zwave/$img";
  }
  return "";
}

sub
ZWave_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $pl = ""; # Pepper link and image
  my $model = ReadingsVal($d, "modelId", "");
  return '' if (!$model);

  my $iodev = $defs{$d}{IODev}{NAME};
  my $hs = AttrVal($iodev, "helpSites", $zwave_activeHelpSites);
  for my $n (split(",", $hs)) {
    my $link = $zwave_link{$n}{$model};
    next if(!$link);
    $pl .= "<div class='detLink ZWPepper'>";
    my $url = ($n eq "alliance" ?
              "http://products.z-wavealliance.org/products/" :
              "http://devel.pepper1.net/zwavedb/device/");
    $pl .= "<a target='_blank' href='$url/$link'>Details in $n DB</a>";
    $pl .= "</div>";
  }

  my $img = ZWave_getPic($iodev, $model);
  if($img && !$FW_ss) {
    $pl .= "<div class='img'".($FW_tp?"":" style='float:right'").">";
    $pl .= "<img style='max-width:96;max-height:96px;' src='$img'>";
    $pl .= "</div>";
  }

  return
  "<div id='ZWHelp' class='makeTable help'></div>$pl".
  '<script type="text/javascript">'.
   "var d='$d', FW_tp='$FW_tp';" . <<'JSEND'
    $(document).ready(function() {
      $("div#ZWHelp").insertBefore("div.makeTable.internals"); // Move
      $("div.detLink.ZWPepper").insertAfter("div.detLink.devSpecHelp");
      if(FW_tp) $("div.img.ZWPepper").appendTo("div#menu");
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
=item summary    devices communicating via the ZWave protocol
=item summary_DE Anbindung von ZWave Ger&auml;ten
=begin html

<a name="ZWave"></a>
<h3>ZWave</h3>
<ul>
  This module is used to control ZWave devices via FHEM, see <a
  href="http://www.z-wave.com">www.z-wave.com</a> for details for this device
  family. The full specification of ZWave command classes can be found here:
  <a href="http://zwavepublic.com/specifications" 
  title="website with the full specification of ZWave command classes">
  http://zwavepublic.com/specifications</a>.
  This module is a client of the <a href="#ZWDongle">ZWDongle</a>
  module, which is directly attached to the controller via USB or TCP/IP.  To
  use the SECURITY features, the Crypt-Rijndael perl module is needed.
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

  Note: the sets/gets/generated events of a given node depend on the classes
  supported by this node. If a node supports 3 classes, then the union of
  these sets/gets/events will be available for this node.<br>
  Commands for battery operated nodes will be queued internally, and sent when
  the node sends a message. Answers to get commands appear then as events, the
  corresponding readings will be updated.
  <br><br>

  <a name="ZWaveset"></a>
  <b>Set</b>
  <ul>
  <br>
  <b>Notes</b>:
  <ul>
    <li>devices with on/off functionality support the <a
      href="#setExtensions"> set extensions</a>.</li>
    <li>A set command does not automatically update the corresponding reading,
      you have to execute a get for this purpose. This can be automatically
      done via a notify, although this is not recommended in all cases.</li>
  </ul>

  <br><br><b>All</b>
  <li>neighborUpdate<br>
    Requests controller to update its routing table which is based on
    slave's neighbor list. The update may take significant time to complete.
    With the event "done" or "failed" ZWDongle will notify the end of the
    update process.  To read node's neighbor list see neighborList get
    below.</li>

  <li>returnRouteAdd &lt;decimal nodeId&gt;<br>
    Assign up to 4 static return routes to the routing/enhanced slave to
    allow direct communication to &lt;decimal nodeId&gt;. (experts only)</li>

  <li>returnRouteDel<br>
    Delete all static return routes. (experts only)</li>

  <li>sucRouteAdd<br>
    Inform the routing/enhanced slave of the presence of a SUC/SIS. Assign
    up to 4 static return routes to SUC/SIS.</li>

  <li>sucRouteDel<br>
    Delete static return routes to SUC/SIS node.</li>

<br><br><b>Class ALARM</b>
  <li>alarmnotification &lt;alarmType&gt; (on|off)<br>
    Enable (on) or disable (off) the sending of unsolicited reports for
    the alarm type &lt;alarmType&gt;. A list of supported alarm types of the
    device can be obtained with the alarmTypeSupported command. The
    name of the alarm type is case insensitive. Sending of an unsolicited
    notification only works for associated nodes, broadcasting is not
    allowed, so associations have to be set up. This command is
    specified in version 2.</li>
  <li> Note:<br>
    The name of the class ALARM was renamed to NOTIFICATION in
    version 3 of the Zwave specification. Due to backward compatibility
    reasons the class will be always referenced as ALARM in FHEM,
    regardless of the version.</li>

  <br><br><b>Class ASSOCIATION</b>
  <li>associationAdd groupId nodeId ...<br>
  Add the specified list of nodeIds to the association group groupId.<br> Note:
  upon creating a FHEM-device for the first time FHEM will automatically add
  the controller to the first association group of the node corresponding to
  the FHEM device, i.e it issues a "set name associationAdd 1
  controllerNodeId"</li>
  <li>associationDel groupId nodeId ...<br>
  Remove the specified list of nodeIds from the association group groupId.</li>

  <br><br><b>Class BASIC</b>
  <li>basicValue value<br>
    Send value (0-255) to this device. The interpretation is device dependent,
    e.g. for a SWITCH_BINARY device 0 is off and anything else is on.</li>
  <li>basicValue value<br>
    Alias for basicValue, to make mapping from the incoming events easier.
    </li>

  <br><br><b>Class BARRIER_OPERATOR</b>
  <li>barrierClose<br>
    start closing the barrier.</li>
  <li>barrierOpen<br>
    start opening the barrier.
    </li>

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
    and 12, with one decimal point, measured in Kelvin (or Centigrade).<br>
    If only a weekday is specified without any time and tempDiff, then the
    complete schedule for the specified day is removed and marked as unused.
    </li>
  <li>ccsOverride (no|temporary|permanent) (frost|energy|$tempOffset) <br>
    set the override state<br>
    no: switch the override off<br>
    temporary: override the current schedule only<br>
    permanent: override all schedules<br>
    frost/energy: set override mode to frost protection or energy saving<br>
    $tempOffset: the temperature setback (offset to setpoint) in 1/10 degrees
    range from -12.8 to 12.0, values will be limited to this range.
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
    value are node specific.<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config commands are available.</li>
  <li>configDefault cfgAddress<br>
    Reset the configuration parameter for the cfgAddress parameter to its
    default value.  See the device documentation to determine this value.</li>

  <br><br><b>Class DOOR_LOCK, V2</b>
  <li>doorLockOperation DOOR_LOCK_MODE<br>
    Set the operation mode of the door lock.<br>
    DOOR_LOCK_MODE:<br>
    open = Door unsecured<br>
    close = Door secured<br>
    00 = Door unsecured<br>
    01 = Door unsecured with timeout<br>
    10 = Door unsecured for inside door handles<br>
    11 = Door unsecured for inside door handles with timeout<br>
    20 = Door unsecured for outside door handles<br>
    21 = Door unsecured for outside door handles with timeout<br>
    FF = Door secured<br>
    Note: open/close can be used as an alias for 00/FF.
    </li>
  <li>doorLockConfiguration operationType outsidehandles
      insidehandles timeoutSeconds<br>
    Set the configuration for the door lock.<br>
    operationType: [constant|timed]<br>
    outsidehandle/insidehandle: 4-bit binary field for handle 1-4,
      bit=0:handle disabled, bit=1:handle enabled, highest bit is for
      handle 4, lowest bit for handle 1. Example 0110 0001
      = outside handles 3 and 2 are active, inside handle 1 is active<br>
    timeoutSeconds: time out for timed operation (in seconds) [1-15239].
    </li>

  <br><br><b>Class INDICATOR</b>
  <li>indicatorOn<br>
    switch the indicator on</li>
  <li>indicatorOff<br>
    switch the indicator off</li>
  <li>indicatorDim value<br>
    takes values from 1 to 99.
    If the indicator does not support dimming, it is interpreted as on.</li>

  <br><br><b>Class MANUFACTURER_PROPRIETARY</b>
   <br>Fibaro FGR(M)-222 only:
  <li>positionBlinds<br>
    drive blinds to position %</li>
  <li>positionSlat<br>
    drive slat to position %</li>
   <br>D-Link DCH-Z510, Philio PSE02, Zipato Indoor Siren only:<br>
   switch alarm on with selected sound (to stop use: set &lt;device&gt; off)
  <li>alarmEmergencyOn</li>
  <li>alarmFireOn</li>
  <li>alarmAmbulanceOn</li>
  <li>alarmPoliceOn</li>
  <li>alarmDoorchimeOn</li>
  <li>alarmBeepOn</li>


  <br><br><b>Class METER</b>
  <li>meterReset<br>
    Reset all accumulated meter values.<br>
    Note: see meterSupported command and its output to detect if resetting the
    value is supported by the device.<br>
    The command will reset ALL accumulated values, it is not possible to
    choose a single value.</li>

  <br><br><b>Class MULTI_CHANNEL</b>
  <li>mcCreateAll<br>
    Create a FHEM device for all channels. This command is executed after
    inclusion of a new device.
    </li>

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
    groupId. Specifying 0 for groupId will delete all associations.
    </li>

  <br><br><b>Class NETWORK_SCHEDULE (SCHEDULE), V1</b>
  <li>schedule ID USER_ID YEAR-MONTH-DAY WDAY ACTIVE_ID DURATION_TYPE
    HOUR:MINUTE DURATION NUM_REPORTS CMD ... CMD<br>
    Set a schedule for a user. Due to lack of documentation,
      details for some parameters are not available. Command Class is
      used together with class USER_CODE.<br>
      <ul>
        ID: id of schedule, refer to maximum number of supported schedules
          reported by the scheduleSupported command.<br>
        USER_ID: id of user, starting from 1 up to the number of supported
        users, refer also to the USER_CODE class description.<br>
        YEAR-MONTH-DAY: start of schedule in the format yyyy-mm-dd.<br>
        WDAY: weekday, 1=Monday, 7=Sunday.<br>
        ACTIVE_ID: unknown parameter.<br>
        DURATION_TYPE: unknown parameter.<br>
        HOUR:MINUTE: start of schedule in the format hh:mm.<br>
        DURATION: unknown parameter.<br>
        NUM_REPORTS: number of reports to follow, must be 0.<br>
        CMD: command(s) (as hexcode sequence) that the schedule executes,
          see report of scheduleSupported command for supported command
          class and mask. A list of space separated commands can be
          specified.<br>
      </ul>
      </li>
  <li>scheduleRemove ID<br>
    Remove the schedule with the id ID</li>
  <li>scheduleState ID STATE<br>
    Set the STATE of the schedule with the id ID. Description for
      parameter STATE is not available.</li>

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
    for commandclass PROTECTION V2 - see devicemanual for supported
    protectionmodes</li>

  <br><br><b>Class SCENE_ACTIVATION</b>
  <li>sceneConfig<br>
    activate settings for a specific scene.
    Parameters are: sceneId, dimmingDuration (0..255)
    </li>

  <br><br><b>Class SCENE_ACTUATOR_CONF</b>
  <li>sceneConfig<br>
    set configuration for a specific scene.
    Parameters are: sceneId, dimmingDuration, finalValue (0..255)
    </li>

  <br><br><b>Class SCENE_CONTROLLER_CONF</b>
  <li>groupConfig<br>
    set configuration for a specific scene.
    Parameters are: groupId, sceneId, dimmingDuration.
    </li>

  <br><br><b>Class SCHEDULE_ENTRY_LOCK, V1, V2, V3</b>
  <li>scheduleEntryLockSet USER_ID ENABLED<br>
    enables or disables schedules for a specified user ID (V1)<br>
      <ul>
      USER_ID: id of user, starting from 1 up to the number of supported
      users, refer also to the USER_CODE class description.<br>
      ENABLED: 0=disabled, 1=enabled<br>
      </ul>
    </li>
  <li>scheduleEntryLockAllSet ENABLED<br>
    enables or disables schedules for all users (V1)<br>
      <ul>
      ENABLED: 0=disabled, 1=enabled<br>
      </ul>
    </li>
  <li>scheduleEntryLockWeekDaySet ACTION USER_ID SCHEDULE_ID WEEKDAY
      STARTTIME ENDTIME<br>
    erase or set a week day schedule for a specified user ID (V1)<br>
      <ul>
      ACTION: 0=erase schedule slot, 1=modify the schedule slot for the
      user<br>
      USER_ID: id of user, starting from 1 up to the number of supported
      users, refer also to the USER_CODE class description.<br>
      SCHEDULE_ID: schedule slot id (from 1 up to number of supported
                    schedule slots)<br>
      WEEKDAY: day of week, choose one of:
                    "sun","mon","tue","wed","thu","fri","sat"<br>
      STARTTIME: time of schedule start, in the format HH:MM
                    (leading 0 is mandatory)<br>
      ENDTIME: time of schedule end in the format HH:MM
                    (leading 0 is mandatory)<br>
      </ul>
    </li>
  <li>scheduleEntryLockYearDaySet ACTION USER_ID SCHEDULE_ID
        STARTDATE STARTTIME ENDDATE ENDTIME<br>
    erase or set a year day schedule for a specified user ID (V1)<br>
      <ul>
      ACTION: 0=erase schedule slot, 1=modify the schedule slot for the
      user<br>
      USER_ID: id of user, starting from 1 up to the number of supported
      users, refer also to the USER_CODE class description.<br>
      SCHEDULE_ID: schedule slot id (from 1 up to number of supported
                    schedule slots)<br>
      STARTDATE: date of schedule start in the format YYYY-MM-DD<br>
      STARTTIME: time of schedule start in the format HH:MM
                    (leading 0 is mandatory)<br>
      ENDDATE: date of schedule end in the format YYYY-MM-DD<br>
      ENDTIME: time of schedule end in the format HH:MM
                    (leading 0 is mandatory)<br>
      </ul>
    </li>
  <li>scheduleEntryLockTimeOffsetSet TZO DST<br>
    set the TZO and DST (V2)<br>
      <ul>
      TZO: current local time zone offset in the format (+|-)HH:MM
          (sign and leading 0 is mandatory)<br>
      DST: daylight saving time offset in the format (+|-)[[m]m]m
          (sign is mandatory, minutes: 0 to 127, 1-3 digits)<br>
      </ul>
    </li>
  <li>scheduleEntryLockDailyRepeatingSet ACTION USER_ID SCHEDULE_ID
        WEEKDAYS STARTTIME DURATION<br>
    set a daily repeating schedule for the specified user (V3)<br>
      <ul>
      ACTION: 0=erase schedule slot, 1=modify the schedule slot for the
      user<br>
      USER_ID: id of user, starting from 1 up to the number of supported
      users, refer also to the USER_CODE class description.<br>
      SCHEDULE_ID: schedule slot id (from 1 up to number of supported
                    schedule slots)<br>
      WEEKDAYS: concatenated string of weekdays (choose from:
                    "sun","mon","tue","wed","thu","fri","sat");
                    e.g. "montuewedfri" or "satsun", unused days can be
                    specified as "..."<br>
      STARTTIME: time of schedule start in the format HH:MM
                    (leading 0 is mandatory)<br>
      DURATION: duration of schedule in the format HH:MM
                    (leading 0 is mandatory)<br>
      </ul>
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
  <li>dimWithDuration value duration<br>
    dim to the requested value (0..100) in duration time.  If duration is
    less than 128, then it is interpreted as seconds, if it is between 128 and
    254, then as duration-128 minutes. Note: this command works only with
    devices supporting version 2 of the SWITCH_MULTILEVEL class, which you can
    verify with get versionClassAll</li>
  <li>stop<br>
    stop dimming/operation</li>

  <br><br><b>Class THERMOSTAT_FAN_MODE</b>
  <li>fanAutoLow</li>
  <li>fanLow</li>
  <li>fanAutoMedium</li>
  <li>fanMedium</li>
  <li>fanAutoHigh</li>
  <li>fanHigh<br>
    set the fan mode.</li>

  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>tmOff</li>
  <li>tmHeating</li>
  <li>tmCooling</li>
  <li>tmAuto</li>
  <li>tmFan</li>
  <li>V2:</li>
  <li>tmEnergySaveHeating</li>
  <li>V3:</li>
  <li>tmFullPower</li>
  <li>tmManual<br>
    set the thermostat mode.</li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>setpointHeating value<br>
    set the thermostat to heat to the given value.
    The value is an integer and read as celsius.<br>
    See thermostatSetpointSet for a more enhanced method.
  </li>
  <li>setpointCooling value<br>
    set the thermostat to cool down to the given value.
    The value is an integer and read as celsius.<br>
    See thermostatSetpointSet for a more enhanced method.
  </li>
  <li>thermostatSetpointSet TEMP [SCALE [TYPE [PREC [SIZE]]]]<br>
    set the setpoint of the thermostat to the given value.<br>
      <ul>
      TEMP: setpoint temperature value, by default the value is used
              with 1 decimal, see PREC<br>
      SCALE: (optional) scale of temperature; [cC]=celsius,
            [fF]=fahrenheit, defaults to celsius<br>
      TYPE: (optional) setpoint type; [1, 15], defaults to 1=heating<br>
        <ul>
        1=heating,
        2=cooling,
        7=furnance,
        8=dryAir,
        9=moistAir,
        10=autoChangeover,
        11=energySaveHeating,
        12=energySaveCooling,
        13=awayHeating,
        14=awayCooling,
        15=fullPower
        </ul>
      PREC: (optional) number of decimals to be used, [1-7], defaults
            to 1<br>
      SIZE: (optional) number of bytes used, [1, 2, 4], defaults to 2<br>
      Note: optional parameters can be ommitted and are used with there
            default values. If you need or want to specify an optional
            parameter, ALL parameters in front of this parameter need
            to be also specified!<br>
      Note: the number of decimals (defined by PREC) and the number of
      bytes (defined by SIZE) used for the setpoint influence the usable
      range for the temperature. Some device do not support all possible
      values/combinations for PREC/SIZE.<br>
        <ul>
        1 byte: 0 decimals [-128, 127], 1 decimal [-12.8, 12.7], ...<br>
        2 byte: 0 decimals [-32768, 32767], 1 decimal [-3276.8, 3276.7],
          ...<br>
        4 byte: 0 decimals [-2147483648, 2147483647], ...<br>
        </ul>
      </ul>
    </li>
  <li>desired-temp value<br>
    same as thermostatSetpoint, used to make life easier for helper-modules
    </li>

  <br><br><b>Class TIME, V2</b>
  <li>timeOffset TZO DST_Offset DST_START DST_END<br>
    Set the time offset for the internal clock of the device.<br>
    TZO: Offset of time zone to UTC in format [+|-]hh:mm.<br>
    DST_OFFSET: Offset for daylight saving time (DST) in minutes
      in the format [+|-]mm.<br>
    DST_START / DST_END: Start and end of daylight saving time in the
      format MM-DD_HH:00.<br>
    Note: Sign for both offsets must be specified!<br>
    Note: Minutes for DST_START and DST_END must be specified as "00"!
    </li>

  <br><br><b>Class TIME_PARAMETERS, V1</b>
  <li>timeParametersGet<br>
    The device request time parameters. Right now the user should define a
    notify with a "set timeParameters" command.
    </li>
  <li>timeParameters DATE TIME<br>
    Set the time (UTC) to the internal clock of the device.<br>
    DATE: Date in format YYYY-MM-DD.<br>
    TIME: Time (UTC) in the format hh:mm:ss.<br>
    Note: Time zone offset to UTC must be set with command class TIME.
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
  <br><br><b>All</b>
  <li>neighborList<br>
    returns the list of neighbors.  Provides insights to actual network
    topology.  List includes dead links and non-routing neighbors.
    Since this information is stored in the dongle, the information will be
    returned directly even for WAKE_UP devices.</li>

  <br><br><b>Class ALARM</b>
  <li>alarm &lt;alarmId&gt;<br>
    return the value for the (decimal) alarmId. The value is device
    specific. This command is specified in version 1 and should only
    be used with old devices that only support version 1.</li>
  <li>alarmWithType &lt;alarmType&gt;<br>
    return the event for the specified alarm type. This command is
    specified in version 2.
    </li>
  <li>alarmWithTypeEvent &lt;alarmType&gt; &lt;eventnumber&gt;<br>
    return the event details for the specified alarm type and
    eventnumber. This command is specified in version 3. The eventnumber
    is specific for each alarm type, a list of the supported
    eventnumbers can be obtained by the "alarmEventSupported" command,
    refer also to the documentation of the device.
    </li>
  <li>alarmTypeSupported<br>
    Returns a list of the supported alarm types of the device which are
    used as parameters in the "alarmWithType" and "alarmWithTypeEvent"
    commands. This command is specified in version 2.</li>  
  <li>alarmEventSupported &lt;alarmType&gt;<br>
    Returns a list of the supported events for the specified alarm type.
    The number of the events can be used as parameter in the
    "alarmWithTypeEvent" command. This command is specified in
    version 3.</li>  

  <br><br><b>Class ASSOCIATION</b>
  <li>association groupId<br>
    return the list of nodeIds in the association group groupId in the form:<br>
    assocGroup_X:Max Y, Nodes id,id...
    </li>
  <li>associationGroups<br>
    return the number of association groups<br>
    </li>
  <li>associationAll<br>
    request association info for all possible groups.</li>

  <br><br><b>Class ASSOCIATION_GRP_INFO</b>
  <li>associationGroupName groupId<br>
    return the name of association groups
    </li>
  <li>associationGroupCmdList groupId<br>
    return Command Classes and Commands that will be sent to associated
    devices in this group<br>
    </li>

  <br><br><b>Class BARRIER_OPERATOR</b>
  <li>barrierState<br>
    request state of the barrier.
    </li>

  <br><br><b>Class BASIC</b>
  <li>basicStatus<br>
    return the status of the node as basicReport:XY. The value (XY) depends on
    the node, e.g. a SWITCH_BINARY device reports 00 for off and FF (255) for on.
    Devices with version 2 (or greater) can return two additional values, the
    'target value' and 'duration'. The 'duration' is reported in seconds, 
    as "unknown duration" (value 0xFE = 253) or as "255 (reserved value)" 
    (value 0xFF = 255).
    </li>

  <br><br><b>Class BATTERY</b>
  <li>battery<br>
    return the charge of the battery in %, as battery:value % or battery:low
    </li>
    </li>

  <br><br><b>CLASS DOOR_LOCK_LOGGING, V1 (deprecated)</b>
  <li>doorLockLoggingRecordsSupported<br>
    Gives back the number of records that can be stored by the device.
    </li>
  <li>doorLockLoggingRecord n<br>
    Requests and reports the logging record number n.<br>
    You will get a reading with the requested record number, the record status,
    the event type, user identifier, user's code length and the timestamp of
    the event in the form of yyyy-mm-dd hh:mm:ss. Although the request does
    report the user code, the user typed in, it is dropped for security
    reasons, so it does not get logged in clear text.<br>
    If the report could not get parsed correctly, it does report the raw
    message.<br>
    The event types can be looked up in the "Software Design Specification -
    Z-Wave Application Command Class Specification" at page 150 from SIGMA
    DESIGNS in the version of 2017-07-10.</li>

  <br><br><b>Class CLIMATE_CONTROL_SCHEDULE</b>
  <li>ccsOverride<br>
    request the climate control schedule override report
    </li>
  <li>ccs [mon|tue|wed|thu|fri|sat|sun]<br>
    request the climate control schedule for the given day.
    </li>
  <li>ccsAll<br>
    request the climate control schedule for all days. (runs in background)
    </li>

  <br><br><b>Class CLOCK</b>
  <li>clock<br>
    request the clock data
    </li>

  <br><br><b>Class COLOR_CONTROL</b>
  <li>ccCapability<br>
    return capabilities.</li>
  <li>ccStatus channelId<br>
    return status of channel ChannelId.
    </li>

  <br><br><b>Class CONFIGURATION</b>
  <li>config cfgAddress<br>
    return the value of the configuration parameter cfgAddress. The value is
    device specific.<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config commands are available.
    </li>
  <li>configAll<br>
    If the model of a device is set, and configuration descriptions are
    available from the database for this device, then request the value of all
    known configuration parameters.</li>

  <br><br><b>Class DOOR_LOCK, V2</b>
  <li>doorLockConfiguration<br>
    Request the configuration report from the door lock.
    </li>
  <li>doorLockOperation<br>
    Request the operconfiguration report from the door lock.
    </li>

  <br><br><b>Class HRV_STATUS</b>
  <li>hrvStatus<br>
    report the current status (temperature, etc.)
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
    Note: protocol V1 does not support the scale parameter, the parameter
    will be ignored and the default scale will be returned.<br>
    For protocol V2 and higher, scale is supported and depends on the
    type of the meter (energy, gas or water).<br>
    The device may not support all scales, see the meterSupported
    command and its output. If the scale parameter is omitted, the
    default unit will be reported.<br>
    Example: For an electric meter, meter 0 will report energy in kWh,
    meter 2 will report power in W and meter 6 will report current in A
    (if these scales are supported).<br>
    </li>
  <li>meterSupported<br>
    request the type of the meter, the supported scales and the
    capability to reset the accumulated value.<br>
    Note: The output contains the decimal numbers of the supported
    scales that can be used as parameter for the meter command.
    </li>

  <br><br><b>Class MULTI_CHANNEL</b>
  <li>mcEndpoints<br>
    return the list of endpoints available, e.g.:<br>
    mcEndpoints: total 2, identical
    </li>
  <li>mcCapability chid<br>
    return the classes supported by the endpoint/channel chid. If the channel
    does not exist, create a FHEM node for it. Example:<br>
    mcCapability_02:SWITCH_BINARY<br>
    <b>Note:</b> This is the best way to create the secondary nodes of a
    MULTI_CHANNEL device. The device is only created for channel 2 or greater.
    </li>

  <br><br><b>Class MULTI_CHANNEL_ASSOCIATION</b>
  <li>mca groupid<br>
    return the associations for the groupid. for the syntax of the returned
    data see the mcaAdd command above.</li>
  <li>mcaAll<br>
    request association info for all possible groupids.
    </li>

  <br><br><b>Class NETWORK_SCHEDULE (SCHEDULE), V1</b>
  <li>scheduleSupported<br>
    Request the supported features, e.g. number of supported schedules.
      Due to the lack of documentation, details for some fields in the
      report are not available.</li>
  <li>schedule ID<br>
    Request the details for the schedule with the id ID. Due to the
      lack of documentation, details for some fields in the report are
      not available.</li>
  <li>scheduleState<br>
    Request the details for the schedule state. Due to the lack of
      documentation, details for some fields in the report are not
      available.</li>

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

  <br><br><b>Class SCHEDULE_ENTRY_LOCK, V1, V2, V3</b>
  <li>scheduleEntryLockTypeSupported<br>
    returns the number of available slots for week day and year day
      schedules (V1), in V3 the number of available slots for the daily
      repeating schedule is reported additionally
    </li>
  <li>scheduleEntryLockWeekDay USER_ID SCHEDULE_ID<br>
    returns the specified week day schedule for the specified user
      (day of week, start time, end time) (V1)<br>
      <ul>
      USER_ID: id of user, starting from 1 up to the number of supported
      users, refer also to the USER_CODE class description.<br>
      SCHEDULE_ID: schedule slot id (from 1 up to number of supported
                    schedule slots)<br>
      </ul>
    </li>
  <li>scheduleEntryLockYearDay USER_ID SCHEDULE_ID<br>
    returns the specified year day schedule for the specified user
      (start date, start time, end date, end time) (V1)<br>
      <ul>
      USER_ID: id of user, starting from 1 up to the number of supported
      users, refer also to the USER_CODE class description.<br>
      SCHEDULE_ID: schedule slot id (from 1 up to number of supported
                    schedule slots)<br>
      </ul>
    </li>
  <li>scheduleEntryLockDailyRepeating USER_ID SCHEDULE_ID<br>
    returns the specified daily schedule for the specified user
      (weekdays, start date, duration) (V3)<br>
      <ul>
      USER_ID: id of user, starting from 1 up to the number of supported
      users, refer also to the USER_CODE class description.<br>
      SCHEDULE_ID: schedule slot id (from 1 up to number of supported
                    schedule slots)<br>
      </ul>
    </li>
  <li>scheduleEntryLockTimeOffset<br>
    returns the time zone offset TZO and the daylight saving time
    offset (V2)
    </li>

  <br><br><b>Class SECURITY</b>
  <li>secSupportedReport<br>
    (internaly used to) request the command classes that are supported
    with SECURITY
    </li>
  <li>Notes:<br>
    This class needs the installation of the perl module Crypt::Rijndael and
    a defined networkkey in the attributes of the ZWDongle device<br>
    Currently a secure inclusion can only be started from the command input
    with "set &lt;ZWDongle_device_name&gt; addNode [onSec|onNwSec]"<br>
    These commands are only described here for completeness of the
    documentation, but are not intended for manual usage. These commands
    will be removed from the interface in future version.</li>

  <br><br><b>Class SENSOR_ALARM</b>
  <li>alarm alarmType<br>
    return the nodes alarm status of the requested alarmType. 00 = GENERIC,
    01 = SMOKE, 02 = CO, 03 = CO2, 04 = HEAT, 05 = WATER, 255 = returns the
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

  <br><br><b>Class THERMOSTAT_FAN_MODE</b>
  <li>fanMode<br>
    request the mode
    </li>

  <br><br><b>Class THERMOSTAT_FAN_STATE</b>
  <li>fanMode<br>
    request the state
    </li>

  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>thermostatMode<br>
    request the mode
    </li>
    
  <br><br><b>Class THERMOSTAT_OPERATING_STATE</b>
  <li>thermostatOperatingState<br>
    request the operating state
    </li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>setpoint [TYPE]<br>
    request the setpoint<br>
      TYPE: (optional) setpoint type; [1, 15], defaults to 1=heating<br>
        <ul>
        1=heating,
        2=cooling,
        7=furnance,
        8=dryAir,
        9=moistAir,
        10=autoChangeover,
        11=energySaveHeating,
        12=energySaveCooling,
        13=awayHeating,
        14=awayCooling,
        15=fullPower
        </ul>
    </li>
  <li>thermostatSetpointSupported<br>
    requests the list of supported setpoint types
    </li>

  <br><br><b>Class TIME, V2</b>
  <li>time<br>
    Request the (local) time from the internal clock of the device.
    </li>
  <li>date<br>
    Request the (local) date from the internal clock of the device.
    </li>
  <li>timeOffset<br>
    Request the report for the time offset and DST settings from the
      internal clock of the device.
    </li>

  <br><br><b>Class TIME_PARAMETERS, V1</b>
  <li>time<br>
    Request the date and time (UTC) from the internal clock of the device.
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
  <li>versionClass classId or className<br>
     return the supported command version for the requested class
    </li>
  <li>versionClassAll<br>
    executes "get devicename versionClass class" for each class from the
    classes attribute in the background without generating events, and sets the
    vclasses attribute at the end.
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
    <li><a name="WNMI_delay">WNMI_delay</a><br>
      This attribute sets the time delay between the last message sent to an
      WakeUp device and the sending of the WNMI Message
      (WakeUpNoMoreInformation) that will set the device to sleep mode.  Value
      is in seconds, subseconds my be specified. Values outside of 0.2-5.0 are
      probably harmful.
      </li>
    <li><a name="classes">classes</a><br>
      This attribute is needed by the ZWave module, as the list of the possible
      set/get commands depends on it. It contains a space separated list of
      class names (capital letters).
      </li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a name="eventForRaw">eventForRaw</a><br>
      Generate an an additional event for the RAW message.  Can be used if
      someone fears that critical notifies won't work, if FHEM changes the event
      text after an update.  </li>
    <li><a name="extendedAlarmReadings">extendedAlarmReadings</a><br>
      Some devices support more than one alarm type, this attribute
      selects which type of reading is used for the reports of the ALARM
      (or NOTIFICATION) class:<br>
      A value of "0" selects a combined, single reading ("alarm") for
      all alarm types of the device. Subsequent reports of different
      alarm types will overwrite each other. This is the default setting
      and the former behavior.<br>
      A value of "1" selects separate alarm readings for each alarm type
      of the device. The readings are named "alarm_&lt;alarmtype&gt;.
      This can also be selected if only one alarmtype is supported by
      the device. This reading also contains the status of the
      alarm notification. For compatibility reasons this is currently
      not supported with the combined reading.<br>
      A value of "2" selects both of the above and creates the combined and
      the seperate readings at the same time, this should only be used
      if really needed as duplicate events are generated.
      </li>

    <li><a href="#ignore">ignore</a></li>
    <li><a name="ignoreDupMsg">ignoreDupMsg</a><br>
      Experimental: if set (to 1), ignore duplicate wakeup messages, or
      multiple responses to a single get due to missing lowlevel ACK.
      </li>
    <li><a href="#neighborListPos">neighborListPos</a></li>
    <li><a name="noExplorerFrames">noExplorerFrames</a><br>
      turn off the use of Explorer Frames
      </li>

    <li><a name="noWakeupForApplicationUpdate">noWakeupForApplicationUpdate</a>
        <br>
      some devices (notable the Aeotec Multisensor 6) are only awake after an
      APPLICATION UPDATE telegram for a very short time. If this attribute is
      set (recommended for the Aeotec Multisensor 6), the WakeUp-Stack is not
      processed after receiving such a message.
      </li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="secure_classes">secure_classes</a><br>
      This attribute is the result of the "set DEVICE secSupportedReport"
      command. It contains a space seperated list of the the command classes
      that are supported with SECURITY.
      </li>
    <li><a href="#showtime">showtime</a></li>
    <li><a name="vclasses">vclasses</a><br>
      This is the result of the "get DEVICE versionClassAll" command, and
      contains the version information for each of the supported classes.
      </li>

    <li><a name="useCRC16">useCRC16</a><br>
      Experimental: if a device supports CRC_16_ENCAP, then add CRC16 to the
      command. Note: this is not available to SECURITY ENABLED devices, as
      security has its own CRC.
      </li>

    <li><a name="useMultiCmd">useMultiCmd</a><br>
      Experimental: if a device supports MULTI_CMD and WAKE_UP, then pack
      multiple get messages on the SendStack into a single MULTI_CMD to save
      radio transmissions.
      </li>

    <li><a name="zwaveRoute">zwaveRoute</a><br>
      space separated list of (ZWave) device names. They will be used in the
      given order to route messages from the controller to this device. Specify
      them in the order from the controller to the device. Do not specify the
      controller and the device itself, only the routers inbetween. Used only
      if the IODev is a ZWCUL device. </li>

  </ul>
  <br>

  <a name="ZWaveevents"></a>
  <b>Generated events:</b>
  <ul>

  <br><b>neighborUpdate</b>
  <li>ZW_REQUEST_NODE_NEIGHBOR_UPDATE [started|done|failed]</li>

  <br><b>returnRouteAdd</b>
  <li>ZW_ASSIGN_RETURN_ROUTE [started|alreadyActive|transmitOk|
                                  transmitNoAck|transmitFail|transmitNotIdle|
                                  transmitNoRoute]</li>

  <br><b>returnRouteDel</b>
  <li>ZW_DELETE_RETURN_ROUTE [started|alreadyActive|transmitOk|
                                  transmitNoAck|transmitFail|transmitNotIdle|
                                  transmitNoRoute]</li>

  <br><b>sucRouteAdd</b>
  <li>ZW_ASSIGN_SUC_RETURN_ROUTE [started|alreadyActive|transmitOk|
                                  transmitNoAck|transmitFail|transmitNotIdle|
                                  transmitNoRoute]</li>

  <br><b>sucRouteDel</b>
  <li>ZW_DELETE_SUC_RETURN_ROUTE [started|alreadyActive|transmitOk|
                                  transmitNoAck|transmitFail|transmitNotIdle|
                                  transmitNoRoute]</li>

  <br><b>Class ALARM</b>
  <li>Note:<br>
    Depending on the setting of the attribute "extendedAlarmReadings"
    the generated events differ slightly. With a value of "0" or "2" a
    combined reading for all alarm types of the device with the name
    "alarm" will be used. With a value of "1" or "2" separate readings
    for each supported alarm type will be generated with names
    "alarm_&lt;alarmType&gt;.</li>
  <li>Devices with class version 1 support: alarm_type_X:level Y</li>
  <li>For higher class versions more detailed events with 100+ different
    strings in the form alarm:&lt;string&gt;
    (or alarm_&lt;alarmType&gt;:&lt;string&gt;) are generated.<br>
    For the combined reading, the name of the alarm type is part of
    the reading event, for separate readings it is part of the
    reading name.<br>
    If a cleared event can be identified, the string "Event cleared:"
    is reported before the event details.<br>
    The seperate readings also contain the status of the
    alarm / notification. For compatibility reasons this is currently
    not supported with the combined reading. </li>

  <br><b>Class APPLICATION_STATUS</b>
  <li>applicationStatus: [cmdRejected]</li>
  <li>applicationBusy: [tryAgainLater|tryAgainInWaitTimeSeconds|
    RequestQueued|unknownStatusCode] $waitTime</li>

  <br><br><b>Class ASSOCIATION</b>
  <li>assocGroup_X:Max Y Nodes A,B,...</li>
  <li>assocGroups:X</li>

  <br><br><b>Class ASSOCIATION_GRP_INFO</b>
  <li>assocGroupName_X:name</li>
  <li>assocGroupCmdList_X:Class1:Cmd1 Class2:Cmd ...</li>

  <br><br><b>Class BARRIER_OPERATOR</b>
  <li>barrierState:[ closed | [%] | closing | stopped | opening | open ]</li>

  <br><br><b>Class BASIC</b>
  <li>basicReport:X (for version 1), basicReport:X target y duration z 
    (for version 2 or greater)</li>
  <li>basicGet:request</li>
  <li>basicSet:X</li>

  <br><br><b>Class BASIC_WINDOW_COVERING</b>
  <li>covering:[open|close|stop]</li>

  <br><br><b>Class BATTERY</b>
  <li>battery:chargelevel %</li>

  <br><br><b>Class CENTRAL_SCENE</b>
  <li>cSceneSet:X</li>
  <li>cSceneDim:X</li>
  <li>cSceneDimEnd:X</li>
  <li>cSceneDouble:X</li>
  <li>cSceneMultiple_N:X<br>where N is 3, 4 or 5 (multiple presses)</li>

  <br><br><b>Class CLIMATE_CONTROL_SCHEDULE</b>
  <li>ccsOverride:[no|temporary|permanent],
                  [frost protection|energy saving|unused]</li>
  <li>ccsChanged:&lt;number&gt;</li>
  <li>ccs_[mon|tue|wed|thu|fri|sat|sun]:HH:MM temp HH:MM temp...</li>

  <br><br><b>Class CLOCK</b>
  <li>clock:get</li>
  <li>clock:[mon|tue|wed|thu|fri|sat|sun] HH:MM</li>

  <br><br><b>Class COLOR_CONTROL</b>
  <li>ccCapability:XY</li>
  <li>ccStatus_X:Y</li>

  <br><br><b>Class CONFIGURATION</b>
  <li>config_X:Y<br>
    Note: if the model is set (see MANUFACTURER_SPECIFIC get), then more
    specific config messages are available.</li>

  <br><br><b>Class DEVICE_RESET_LOCALLY</b>
  <li>deviceResetLocally:yes<br></li>

  <br><br><b>Class DOOR_LOCK, V2</b>
  <li>doorLockConfiguration:  mode: [constant|timed] outsideHandles:
    $outside_mode(4 bit field) insideHandles: $inside_mode(4 bit field)
    timeoutSeconds: [not_supported|$seconds]</li>
  <li>doorLockOperation: mode: $mode outsideHandles:
    $outside_mode(4 bit field) insideHandles: $inside_mode(4 bit field)
    door: [open|closed] bolt: [locked|unlocked] latch: [open|closed]
    timeoutSeconds: [not_supported|$time]<br>
    $mode = [unsecured|unsecured_withTimeout|unsecured_inside|
      unsecured_inside_withTimeout|unsecured_outside|
      unsecured_outside_withTimeout|secured</li>

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
  <li>supportedStatus: &lt;list of supported stati&gt;</li>

  <br><br><b>Class INDICATOR</b>
  <li>indState:[on|off|dim value]</li>

  <br><br><b>Class MANUFACTURER_PROPRIETARY</b>
  <li>Fibaro FGRM-222 with ReportsType Fibar CC only:</li>
  <li>position:Blind [%] Slat [%]<br>
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

  <br><br><b>Class NETWORK_SCHEDULE (SCHEDULE), V1</b>
  <li>schedule_&lt;id&gt;: ID: $schedule_id userID: $user_id sYear:
    $starting_year sMonth: $starting_month activeID: $active_id
    sDay: $starting_day sWeekDay: $starting_weekday sHour:
    $starting_hour durationType: $duration_type sMinute:
    $starting_minute duration: $duration numReportsToFollow:
    $number_of_reports_to_follow numCmds: $number_of_commands
    cmdLen: $length_of_command cmd: $commandsequence(hex)</li>
  <li>scheduleSupported: num: $number_of_supported_schedules
    startTimeSupport: $start_time_support(6 bit field) fallbackSupport:
    $fallback_support enableDisableSupport: $ena_dis_support
    numCCs: $number_of_supported_command_classes
    overrideTypes: $override_types(7 bit field) overrideSupport:
    $override_support</li>
  <li>scheduleSupportedCC: CC_&lt;x&gt;: $number_of_command_class
    CCname_&lt;x&gt;: $name_of_command_class]CCmask_&lt;x&gt;:
    $mask_for_command(2 bit)</li>

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

  <br><br><b>Class SCHEDULE_ENTRY_LOCK</b>
  <li>scheduleEntryLockEntryTypeSupported:WeekDaySlots: $value
        YearDaySlots: $value</li>
  <li>weekDaySchedule_$userId:userID: $value slotID: $value $weekday
        $starthour:$startminute $endhour:$endminute</li>
  <li>yearDaySchedule_$userId:userID: $value slotID: $value
        start: $year-$month-$day $hour:$minute
        end: $year-$month-$day $hour:$minute</li>
  <li>scheduleEntryLockDailyRepeating_$userId:userID: $value $weekdays
        $hour:$minute $durationhour:$durationminute<br>
        Note: $weekdays is a concatenated string with weekdaynames
        ("sun","mon","tue","wed","thu","fri","sat") where inactive
        weekdays are represented by "...", e.g. montue...wedfri</li>
  <li>scheduleEntryLockTimeOffset:TZO: $sign$hour:$minute DST: 
        $sign$minutes</li>

  <br><br><b>Class SECURITY</b>
  <li>none<br>
  Note: the class security should work transparent to the sytem and is not
  intended to generate events</li>

  <br><br><b>Class SENSOR_ALARM</b>
  <li>alarm_type_X:level Y node $nodeID seconds $seconds</li>

  <br><br><b>Class SENSOR_BINARY</b>
  <li>SENSORY_BINARY V1:</li>
  <li>state:open</li>
  <li>state:closed</li>
  <li>SENSORY_BINARY V2:</li>
  <li>unknown:[off|on]</li>
  <li>generalPurpose:[off|on]</li>
  <li>smoke:[off|on]</li>
  <li>CO:[off|on]</li>
  <li>CO2:[off|on]</li>
  <li>heat:[off|on]</li>
  <li>water:[off|on]</li>
  <li>freeze:[off|on]</li>
  <li>tamper:[off|on]</li>
  <li>aux:[off|on]</li>
  <li>doorWindow:[off|on]</li>
  <li>tilt:[off|on]</li>
  <li>motion:[off|on]</li>
  <li>glassBreak:[off|on]</li>

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
  <li>rotation $val [rpm|Hz]</li>
  <li>waterTemperature $val [C|F]</li>
  <li>soilTemperature $val [C|F]</li>
  <li>seismicIntensity $val [mercalli|EU macroseismic|liedu|shindo]</li>
  <li>seismicMagnitude $val [local|moment|surface wave|body wave]</li>
  <li>ultraviolet $val [UV]</li>
  <li>electricalResistivity $val [ohm]</li>
  <li>electricalConductivity $val [siemens/m]</li>
  <li>loudness $val [dB|dBA]</li>
  <li>moisture $val [%|content|k ohms|water activity]</li>
  <li>frequency $val [Hz|kHz]</li>
  <li>time $val [seconds]</li>
  <li>targetTemperature $val [C|F]</li>
  <li>particulateMatter $val [mol/m3|micro-g/m3]</li>
  <li>formaldehydeLevel $val [mol/m3]</li>
  <li>radonConcentration $val [bq/m3|pCi/L]</li>
  <li>methaneDensity $val [mol/m3]</li>
  <li>volatileOrganicCompound $val [mol/m3]</li>
  <li>carbonMonoxide $val [mol/m3]</li>
  <li>soilHumidity $val [%]</li>
  <li>soilReactivity $val [pH]</li>
  <li>soilSalinity $val [mol/m3]</li>
  <li>heartRate $val [Bpm]</li>
  <li>bloodPressure $val [Systolic mmHg|Diastolic mmHg]</li>
  <li>muscleMass $val [Kg]</li>
  <li>fatMass $val [Kg]</li>
  <li>boneMass $val [Kg]</li>
  <li>totalBodyWater $val [Kg]</li>
  <li>basicMetabolicRate $val [J]</li>
  <li>bodyMassIndex $val [BMI]</li>


  <br><br><b>Class SWITCH_ALL</b>
  <li>swa:[ none | on | off | on off ]</li>

  <br><br><b>Class SWITCH_BINARY</b>
  <li>state:on</li>
  <li>state:off</li>
  <li>state:setOn</li>
  <li>state:setOff</li>

  <br><br><b>Class SWITCH_MULTILEVEL</b>
  <li>state:on</li>
  <li>state:off</li>
  <li>state:setOn</li>
  <li>state:setOff</li>
  <li>state:dim value</li>
  <li>state:swmBeginUp</li>
  <li>state:swmBeginDown</li>
  <li>state:swm [ Decrement | Increment ] [ Up | Down ]
                Start: $sl Duration: $dur Step: $step</li>
  <li>state:swmEnd</li>

  <br><br><b>Class THERMOSTAT_FAN_MODE</b>
  <li>fanMode:[ fanAutoLow | fanLow | fanAutoHigh | fanHigh | fanAutoMedium |
                fanMedium ]
      </li>

  <br><br><b>Class THERMOSTAT_FAN_STATE</b>
  <li>fanState:[ off | low | high | medium | circulation | humidityCirc | 
                fanrightLeftCirc | upDownCirc | quietCirc ]</li>

  <br><br><b>Class THERMOSTAT_MODE</b>
  <li>thermostatMode:[ off | cooling | heating | fanOnly | auto | 
                       energySaveHeating | manual | setTmOff | setTmHeating | 
                       setTmEnergySaveHeating | setTmManual ]</li>
  
  <br><br><b>Class THERMOSTAT_OPERATING_STATE</b>
  <li>thermostatOperatingState:[ idle | heating | cooling | fanOnly |
        pendingHeat | pendingCooling | ventEconomizer | auxHeating |
        2ndStageHeating | 2ndStageCooling | 2ndStageAuxHeat |
        3rdStageAuxHeat ]</li>

  <br><br><b>Class THERMOSTAT_SETPOINT</b>
  <li>setpointTemp:$temp $scale $type<br>
    <ul>
    $temp: setpoint temperature with number of decimals as reported
            by the device<br>
    $scale: [C|F]; C=Celsius scale, F=Fahrenheit scale<br>
    $type: setpoint type, one of:<br>
      <ul>
        heating,
        cooling,
        furnance,
        dryAir,
        moistAir,
        autoChangeover,
        energySaveHeating,
        energySaveCooling,
        awayHeating,
        awayCooling,
        fullPower
      </ul>
    </ul>
    </li>

  <br><br><b>Class TIME, V2</b>
  <li>time:$time RTC: [failed|working]</li>
  <li>date:$date</li>
  <li>timeOffset: UTC-Offset: $utco DST-Offset(minutes): $dsto DST-Start:
      $start DST-End: $end</li>

  <br><br><b>Class TIME_PARAMETERS, V1</b>
  <li>timeParameters: date: $date time(UTC): $time</li>

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

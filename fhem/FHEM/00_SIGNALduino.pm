# $Id$
# v3.5.4 - https://github.com/RFD-FHEM/RFFHEM/tree/master
# The module is inspired by the FHEMduino project and modified in serval ways for processing the incoming messages
# see http://www.fhemwiki.de/wiki/SIGNALDuino
# It was modified also to provide support for raw message handling which can be send from the SIGNALduino
# The purpos is to use it as addition to the SIGNALduino which runs on an arduno nano or arduino uno.
# It routes Messages serval Modules which are already integrated in FHEM. But there are also modules which comes with it.
#
# 2014-2015  S.Butzek, N.Butzek
# 2016-2019  S.Butzek, Ralf9
# 2019-2023  S.Butzek, HomeAutoUser, elektron-bbs


package main;
use strict;
use warnings;
use Storable qw(dclone); 
#use version 0.77; our $VERSION = version->declare('v3.5.4');

my $missingModulSIGNALduino = ' ';

use DevIo;
require "99_Utils.pm" if (!defined $modules{"Utils"} || !exists $modules{"Utils"}{"LOADED"} ); ## no critic
use Carp;
no warnings 'portable';

eval {use Data::Dumper qw(Dumper);1};

use constant HAS_JSON      => defined  eval { require JSON; JSON->import; };

eval {use Scalar::Util qw(looks_like_number);1};
eval {use Time::HiRes qw(gettimeofday);1} ;
eval {use FHEM::Core::Timer::Helper;1 } ;

use lib::SD_Protocols;
use List::Util qw(first);

#$| = 1;    #Puffern abschalten, Hilfreich fuer PEARL WARNINGS Search

#use Math::Round qw();


use constant {
  SDUINO_VERSION                  => '3.5.4',  # Datum wird automatisch bei jedem pull request aktualisiert
  SDUINO_INIT_WAIT_XQ             => 1.5,     # wait disable device
  SDUINO_INIT_WAIT                => 2,
  SDUINO_INIT_MAXRETRY            => 3,
  SDUINO_CMD_TIMEOUT              => 10,
  SDUINO_KEEPALIVE_TIMEOUT        => 60,
  SDUINO_KEEPALIVE_MAXRETRY       => 3,
  SDUINO_WRITEQUEUE_NEXT          => 0.3,
  SDUINO_WRITEQUEUE_TIMEOUT       => 2,

  SDUINO_DISPATCH_VERBOSE         => 5,       # default 5
  SDUINO_MC_DISPATCH_VERBOSE      => 5,       # wenn kleiner 5, z.B. 3 dann wird vor dem dispatch mit loglevel 3 die ID und rmsg ausgegeben
  SDUINO_MC_DISPATCH_LOG_ID       => '12.1',  # die o.g. Ausgabe erfolgt nur wenn der Wert mit der ID uebereinstimmt
  SDUINO_PARSE_DEFAULT_LENGHT_MIN => 8,
  SDUINO_GET_CONFIGQUERY_DELAY    => 0.75     # delay for cmd to no overwrite a working cmd
};


#sub SIGNALduino_Attr(@);
#sub SIGNALduino_HandleWriteQueue($);
#sub SIGNALduino_Parse($$$$@);
#sub SIGNALduino_Read($);
#sub SIGNALduino_Ready($);
#sub SIGNALduino_Write($$$);
#sub SIGNALduino_SimpleWrite(@);
#sub SIGNALduino_LoadProtocolHash($);
#sub SIGNALduino_Log3($$$);

#my $debug=0;

our %modules;
our %defs;

my %gets = (  # NameOFCommand =>  StyleMod for Fhemweb, SubToCall if get is executed, String to send to uC, sub called with response, regex to verify response,
  '?'                 =>  ['', \&SIGNALduino_Get_FhemWebList ],
  'version'           =>  ['noArg', \&SIGNALduino_Get_Command, "V", \&SIGNALduino_CheckVersionResp, 'V\s.*SIGNAL(?:duino|ESP|STM).*(?:\s\d\d:\d\d:\d\d)' ],
  'freeram'           =>  ['noArg', \&SIGNALduino_Get_Command, "R", \&SIGNALduino_GetResponseUpdateReading, '^[0-9]+' ] ,
  'uptime'            =>  ['noArg', \&SIGNALduino_Get_Command, "t", \&SIGNALduino_CheckUptimeResponse, '^[0-9]+' ],
  'cmds'              =>  ['noArg', \&SIGNALduino_Get_Command, "?", \&SIGNALduino_CheckCmdsResponse, '.*' ],
  'ping'              =>  ['noArg', \&SIGNALduino_Get_Command, "P", \&SIGNALduino_GetResponseUpdateReading, '^OK$' ],
  'config'            =>  ['noArg', \&SIGNALduino_Get_Command, "CG", \&SIGNALduino_GetResponseUpdateReading, '^MS.*MU.*MC.*' ],
  'ccconf'            =>  ['noArg', \&SIGNALduino_Get_Command, "C0DnF", \&SIGNALduino_CheckccConfResponse, 'C0Dn11=[A-F0-9a-f]+'],
  'ccreg'             =>  ['textFieldNL', \&SIGNALduino_Get_Command_CCReg,"C", \&SIGNALduino_CheckCcregResponse, '^(?:C[A-Fa-f0-9]{2}\s=\s[0-9A-Fa-f]+$|ccreg 00:)'],
  'ccpatable'         =>  ['noArg', \&SIGNALduino_Get_Command, "C3E", \&SIGNALduino_CheckccPatableResponse, '^C3E\s=\s.*'],
  'rawmsg'            =>  ['textFieldNL', \&SIGNALduino_Get_RawMsg ],
  'availableFirmware' =>  ['noArg', \&SIGNALduino_Get_availableFirmware ]
);


my %patable = (
  '433' =>
  {
    '-30_dBm'  => '12',
    '-20_dBm'  => '0E',
    '-15_dBm'  => '1D',
    '-10_dBm'  => '34',
    '-5_dBm'   => '68',
    '0_dBm'    => '60',
    '5_dBm'    => '84',
    '7_dBm'    => 'C8',
    '10_dBm'   => 'C0',
  },
  '868' =>
  {
    '-30_dBm'  => '03',
    '-20_dBm'  => '0F',
    '-15_dBm'  => '1E',
    '-10_dBm'  => '27',
    '-5_dBm'   => '67',
    '0_dBm'    => '50',
    '5_dBm'    => '81',
    '7_dBm'    => 'CB',
    '10_dBm'   => 'C2',
  },
);
my @ampllist = (24, 27, 30, 33, 36, 38, 40, 42);    # rAmpl(dB)

my %sets = (
  #Command name             [FhemWeb Argument type, code to run]
  '?'                   =>  ['', \&SIGNALduino_Set_FhemWebList ],
  'raw'                 =>  ['textFieldNL',\&SIGNALduino_Set_raw ],
  'flash'               =>  ['textFieldNL', \&SIGNALduino_Set_flash ],
  'reset'               =>  ['noArg', \&SIGNALduino_Set_reset ],
  'close'               =>  ['noArg', \&SIGNALduino_Set_close ],
  'enableMessagetype'   =>  ['syncedMS,unsyncedMU,manchesterMC', \&SIGNALduino_Set_MessageType ],
  'disableMessagetype'  =>  ['syncedMS,unsyncedMU,manchesterMC', \&SIGNALduino_Set_MessageType ],
  'sendMsg'             =>  ['textFieldNL',\&SIGNALduino_Set_sendMsg ],
  'cc1101_bWidth'       =>  ['58,68,81,102,116,135,162,203,232,270,325,406,464,541,650,812', \&SIGNALduino_Set_bWidth ],
  'cc1101_dataRate'     =>  ['textFieldNL', \&cc1101::SetDataRate ],
  'cc1101_deviatn'      =>  ['textFieldNL', \&cc1101::SetDeviatn ],
  'cc1101_freq'         =>  ['textFieldNL', \&cc1101::SetFreq ],
  'cc1101_patable'      =>  ['-30_dBm,-20_dBm,-15_dBm,-10_dBm,-5_dBm,0_dBm,5_dBm,7_dBm,10_dBm', \&cc1101::SetPatable ],
  'cc1101_rAmpl'        =>  ['24,27,30,33,36,38,40,42',  \&cc1101::setrAmpl ],
  'cc1101_reg'          =>  ['textFieldNL', \&cc1101::SetRegisters ],
  'cc1101_reg_user'     =>  ['noArg', \&cc1101::SetRegistersUser ],
  'cc1101_sens'         =>  ['4,8,12,16', \&cc1101::SetSens ],
  'LaCrossePairForSec'  =>  ['textFieldNL', \&SIGNALduino_Set_LaCrossePairForSec ],
);

## Supported config CC1101 ##
my @modformat = ('2-FSK','GFSK','-','ASK/OOK','4-FSK','-','-','MSK');
my @syncmod = ( 'No preamble/sync','15/16 sync word bits detected','16/16 sync word bits detected','30/32 sync word bits detected',
                'No preamble/sync, carrier-sense above threshold, carrier-sense above threshold', '15/16 + carrier-sense above threshold',
                '16/16 + carrier-sense above threshold', '30/32 + carrier-sense above threshold'
              );

my %cc1101_register = (   # for get ccreg 99 and set cc1101_reg
  '00' => 'IOCFG2   - 0x0D',      # ! the values with spaces for output get ccreg 99 !
  '01' => 'IOCFG1   - 0x2E',
  '02' => 'IOCFG0   - 0x2D',
  '03' => 'FIFOTHR  - 0x47',
  '04' => 'SYNC1    - 0xD3',
  '05' => 'SYNC0    - 0x91',
  '06' => 'PKTLEN   - 0x3D',
  '07' => 'PKTCTRL1 - 0x04',
  '08' => 'PKTCTRL0 - 0x32',
  '09' => 'ADDR     - 0x00',
  '0A' => 'CHANNR   - 0x00',
  '0B' => 'FSCTRL1  - 0x06',
  '0C' => 'FSCTRL0  - 0x00',
  '0D' => 'FREQ2    - 0x10',
  '0E' => 'FREQ1    - 0xB0',
  '0F' => 'FREQ0    - 0x71',
  '10' => 'MDMCFG4  - 0x57',
  '11' => 'MDMCFG3  - 0xC4',
  '12' => 'MDMCFG2  - 0x30',
  '13' => 'MDMCFG1  - 0x23',
  '14' => 'MDMCFG0  - 0xB9',
  '15' => 'DEVIATN  - 0x00',
  '16' => 'MCSM2    - 0x07',
  '17' => 'MCSM1    - 0x00',
  '18' => 'MCSM0    - 0x18',
  '19' => 'FOCCFG   - 0x14',
  '1A' => 'BSCFG    - 0x6C',
  '1B' => 'AGCCTRL2 - 0x07',
  '1C' => 'AGCCTRL1 - 0x00',
  '1D' => 'AGCCTRL0 - 0x91',
  '1E' => 'WOREVT1  - 0x87',
  '1F' => 'WOREVT0  - 0x6B',
  '20' => 'WORCTRL  - 0xF8',
  '21' => 'FREND1   - 0xB6',
  '22' => 'FREND0   - 0x11',
  '23' => 'FSCAL3   - 0xE9',
  '24' => 'FSCAL2   - 0x2A',
  '25' => 'FSCAL1   - 0x00',
  '26' => 'FSCAL0   - 0x1F',
  '27' => 'RCCTRL1  - 0x41',
  '28' => 'RCCTRL0  - 0x00',
  '29' => 'FSTEST   - N/A ',
  '2A' => 'PTEST    - N/A ',
  '2B' => 'AGCTEST  - N/A ',
  '2C' => 'TEST2    - N/A ',
  '2D' => 'TEST1    - N/A ',
  '2E' => 'TEST0    - N/A ',
);

## Supported Clients per default
my $clientsSIGNALduino = ':CUL_EM:'
            .'CUL_FHTTK:'
            .'CUL_TCM97001:'
            .'CUL_TX:'
            .'CUL_WS:'
            .'Dooya:'
            .'FHT:'
            .'FLAMINGO:'
            .'FS10:'
            .'FS20:'
            .' :'         # Zeilenumbruch
            .'Fernotron:'
            .'Hideki:'
            .'IT:'
            .'KOPP_FC:'
            .'LaCrosse:'
            .'OREGON:'
            .'PCA301:'
            .'RFXX10REC:'
            .'Revolt:'
            .'SD_AS:'
            .'SD_Rojaflex:'
            .' :'         # Zeilenumbruch
            .'SD_BELL:'
            .'SD_GT:'
            .'SD_Keeloq:'
            .'SD_RSL:'
            .'SD_UT:'
            .'SD_WS07:'
            .'SD_WS09:'
            .'SD_WS:'
            .'SD_WS_Maverick:'
            .'SOMFY:'
            .' :'         # Zeilenumbruch
            .'Siro:'
            .'SIGNALduino_un:'
          ;

## default regex match List for dispatching message to logical modules, can be updated during runtime because it is referenced
my %matchListSIGNALduino = (
      '1:IT'                => '^i......',
      '2:CUL_TCM97001'      => '^s[A-Fa-f0-9]+',
      '3:SD_RSL'            => '^P1#[A-Fa-f0-9]{8}',
      '5:CUL_TX'            => '^TX..........',                       # Need TX to avoid FHTTK
      '6:SD_AS'             => '^P2#[A-Fa-f0-9]{7,8}',                # Arduino based Sensors, should not be default
      '4:OREGON'            => '^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*',
      '7:Hideki'            => '^P12#75[A-F0-9]+',
      '9:CUL_FHTTK'         => '^T[A-F0-9]{8}',
      '10:SD_WS07'          => '^P7#[A-Fa-f0-9]{6}[AFaf][A-Fa-f0-9]{2,3}',
      '11:SD_WS09'          => '^P9#F[A-Fa-f0-9]+',
      '12:SD_WS'            => '^W\d+x{0,1}#.*',
      '13:RFXX10REC'        => '^(20|29)[A-Fa-f0-9]+',
      '14:Dooya'            => '^P16#[A-Fa-f0-9]+',
      '15:SOMFY'            => '^Ys[0-9A-F]+',
      '16:SD_WS_Maverick'   => '^P47#[A-Fa-f0-9]+',
      '17:SD_UT'            => '^P(?:14|20|24|26|29|30|34|46|56|68|69|76|78|81|83|86|90|91|91.1|92|93|95|97|99|104|105|114|118|121)#.*', # universal - more devices with different protocols
      '18:FLAMINGO'         => '^P13\.?1?#[A-Fa-f0-9]+',              # Flamingo Smoke
      '19:CUL_WS'           => '^K[A-Fa-f0-9]{5,}',
      '20:Revolt'           => '^r[A-Fa-f0-9]{22}',
      '21:FS10'             => '^P61#[A-F0-9]+',
      '22:Siro'             => '^P72#[A-Fa-f0-9]+',
      '23:FHT'              => '^81..(04|09|0d)..(0909a001|83098301|c409c401)..',
      '24:FS20'             => '^81..(04|0c)..0101a001',
      '25:CUL_EM'           => '^E0.................',
      '26:Fernotron'        => '^P82#.*',
      '27:SD_BELL'          => '^P(?:15|32|41|42|57|79|96|98|112)#.*',
      '28:SD_Keeloq'        => '^P(?:87|88)#.*',
      '29:SD_GT'            => '^P49#[A-Fa-f0-9]+',
      '30:LaCrosse'         => '^(\\S+\\s+9 |OK\\sWS\\s)',
      '31:KOPP_FC'          => '^kr\w{18,}',
      '32:PCA301'           => '^\\S+\\s+24',
      '33:SD_Rojaflex'      => '^P109#[A-Fa-f0-9]+',
      'X:SIGNALduino_un'    => '^[u]\d+#.*',
);

my %symbol_map = (one => 1 , zero =>0 ,sync => '', float=> 'F', 'start' => '');

## rfmode for attrib & supported rfmodes
my @rfmode;
my $Protocols = new lib::SD_Protocols();

############################# package main
sub SIGNALduino_Initialize {
  my ($hash) = @_;

  my $dev = '';
  $dev = ',1' if (index(SDUINO_VERSION, 'dev') >= 0);

  my $error = $Protocols->LoadHash(qq[$attr{global}{modpath}/FHEM/lib/SD_ProtocolData.pm]); 
  if (defined($error)) {
    Log3 'SIGNALduino', 1, qq[Error loading Protocol Hash. Module is in inoperable mode error message:($error)];
  } else {
    $hash->{protocolObject} = $Protocols;
    @rfmode = ('SlowRF');
    push @rfmode, map { $Protocols->checkProperty($_, 'rfmode') } $Protocols->getKeys('rfmode');    
    @rfmode = sort @rfmode;
    Log3 'SIGNALduino', 4, qq[SIGNALduino_Initialize: rfmode list: @rfmode];
  }

  $hash->{DefFn}          = \&SIGNALduino_Define;
  $hash->{UndefFn}        = \&SIGNALduino_Undef;


# Provider
  $hash->{ReadFn}  = \&SIGNALduino_Read;
  $hash->{WriteFn} = \&SIGNALduino_Write;
  $hash->{ReadyFn} = \&SIGNALduino_Ready;

# Normal devices
  $hash->{FingerprintFn}  = \&SIGNALduino_FingerprintFn;
  $hash->{GetFn}          = \&SIGNALduino_Get;
  $hash->{SetFn}          = \&SIGNALduino_Set;
  $hash->{AttrFn}         = \&SIGNALduino_Attr;
  $hash->{AttrList}       =
            'Clients MatchList do_not_notify:1,0 dummy:1,0'
            .' WS09_CRCAUS:0,1,2'
            .' addvaltrigger'
            .' blacklist_IDs'
            .' cc1101_frequency'
            .' cc1101_reg_user'
            ." debug:0$dev"
            ." development:0$dev"
            .' doubleMsgCheck_IDs'
            .' eventlogging:0,1'
            .' flashCommand'
            .' hardware:ESP32,ESP32cc1101,ESP8266,ESP8266cc1101,MAPLEMINI_F103CB,MAPLEMINI_F103CBcc1101,nano328,nanoCC1101,miniculCC1101,promini,radinoCC1101'
            .' hexFile'
            .' initCommands'
            .' longids'
            .' maxMuMsgRepeat'
            .' minsecs'
            .' noMsgVerbose:0,1,2,3,4,5'
            .' rawmsgEvent:1,0'
            .' rfmode:'.join(',', @rfmode)
            .' suppressDeviceRawmsg:1,0'
            .' updateChannelFW:stable,testing'
            .' whitelist_IDs'
            ." $readingFnAttributes";

  $hash->{ShutdownFn}         = 'SIGNALduino_Shutdown';
  $hash->{FW_detailFn}        = 'SIGNALduino_FW_Detail';
  $hash->{FW_deviceOverview}  = 1;

  $hash->{msIdList} = ();
  $hash->{muIdList} = ();
  $hash->{mcIdList} = ();
  $hash->{mnIdList} = ();

  #our $attr;

}

#
# Predeclare Variables from other modules may be loaded later from fhem
#
our $FW_wname;
our $FW_ME;
our $FW_CSRF;
our $FW_detail;



############################# package main, test exists
sub SIGNALduino_FingerprintFn {
  my ($name, $msg) = @_;

  # Das FingerprintFn() darf nur im physikalischen oder logischem Modul aktiv sein.
  # Wenn FingerprintFn in beiden aktiv ist, funktioniert der Dispatch nicht richtig.
  # Da FingerprintFn bei den LaCrosse Modulen verwendet wird, darf es im 00_Signalduino Modul nicht aktiv sein.
  return if (substr($msg,0,2) eq 'OK');

  # Store only the "relevant" part, as the Signalduino won't compute the checksum
  #$msg = substr($msg, 8) if($msg =~ m/^81/ && length($msg) > 8);
  return ('', $msg);
}


############################# package main
sub SIGNALduino_Define {
  my ($hash, $def) = @_;
  my @a =split m{\s+}xms, $def;

  if(@a != 3) {
    my $msg = 'Define, wrong syntax: define <name> SIGNALduino {none | devicename[\@baudrate] | devicename\@directio | hostname:port}';
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);
  my $name = $a[0];

  if (!exists &round)
  {
    Log3 $name, 1, "$name: Define, Signalduino can't be activated (sub round not found). Please update Fhem via update command";
    return ;
  }

  my $dev = $a[2];
  #Debug "dev: $dev" if ($debug);
  #my $hardware=AttrVal($name,'hardware','nano');
  #Debug "hardware: $hardware" if ($debug);

  if($dev eq 'none') {
    Log3 $name, 1, "$name: Define, device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
  }  elsif ($dev !~ m/\@/) { 
    if ( ($dev =~ m~^(?:/[^/ ]*)+?$~xms || $dev =~ m~^COM\d$~xms) )  # bei einer IP oder hostname wird kein \@57600 angehaengt
    {
      $dev .= '@57600' 
    } elsif ($dev !~ /@\d+$/ && ($dev !~ /^
      (?: (?:[a-z0-9-]+(?:\.[a-z]{2,6})?)*|(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}
          (?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9]))
      : (?:6553[0-5]|655[0-2]\d|65[0-4]\d{2}|6[0-4]\d{3}|[1-5]\d{4}|[1-9]\d{0,3})$/xmsi) ) { 
      my $msg = 'Define, wrong hostname/port syntax: define <name> SIGNALduino {none | devicename[\@baudrate] | devicename\@directio | hostname:port}';
      Log3 undef, 2, $msg;
      return $msg;
    }
  }
  
  #$hash->{CMDS} = '';
  $hash->{Clients}    = $clientsSIGNALduino;
  $hash->{MatchList}  = \%matchListSIGNALduino;
  $hash->{DeviceName} = $dev;
  $hash->{logMethod}  = \&main::Log3;

  my $ret=undef;
  $hash->{protocolObject} = dclone($Protocols);
  $hash->{protocolObject}->registerLogCallback(SIGNALduino_createLogCallback($hash));
    
  FHEM::Core::Timer::Helper::addTimer($name, time(), \&SIGNALduino_IdList,"sduino_IdList:$name",0 );
  #InternalTimer(gettimeofday(), \&SIGNALduino_IdList,"sduino_IdList:$name",0);       # verzoegern bis alle Attribute eingelesen sind
  
  if($dev ne 'none') {
    $ret = DevIo_OpenDev($hash, 0, \&SIGNALduino_DoInit, \&SIGNALduino_Connect);
  } else {
  $hash->{DevState} = 'initialized';
    readingsSingleUpdate($hash, 'state', 'opened', 1);
  }

  $hash->{DMSG}             = 'nothing';
  $hash->{LASTDMSG}         = 'nothing';
  $hash->{LASTDMSGID}       = 'nothing';
  $hash->{TIME}             = time();
  $hash->{versionmodul}     = SDUINO_VERSION;
  $hash->{versionProtocols} = $hash->{protocolObject}->getProtocolVersion();

  if (!defined($hash->{versionProtocols})) {
    Log3 $name, 1, qq[$name: Error loading Protocol Hash! SIGNALduino is in inoperable mode!];
    return ;
  }

  return $ret;
}

############################# package main
sub SIGNALduino_Connect {
  my ($hash, $err) = @_;

  # damit wird die err-msg nur einmal ausgegeben
  if (!defined($hash->{disConnFlag}) && $err) {
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: Connect, ${err}");
    $hash->{disConnFlag} = 1;
  }
}

############################# package main
sub SIGNALduino_Undef {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        $hash->{logMethod}->($name, $lev, "$name: Undef, deleting port for $d");
        delete $defs{$d}{IODev};
      }
  }

  SIGNALduino_Shutdown($hash);

  DevIo_CloseDev($hash);
  FHEM::Core::Timer::Helper::removeTimer($name); 
  return ;
}

############################# package main
sub SIGNALduino_Shutdown {
  my ($hash) = @_;
  #DevIo_SimpleWrite($hash, "XQ\n",2);
  SIGNALduino_SimpleWrite($hash, 'XQ');   # Switch reception off, it may hang up the SIGNALduino
  return ;
}

############################# package main
sub SIGNALduino_avrdude {
  my $name = shift;
  my $hash = $defs{$name};

  if (defined($hash->{helper}{stty_pid}))
  {
    waitpid( $hash->{helper}{stty_pid}, 0 );
    delete ( $hash->{helper}{stty_pid});
  }

  readingsSingleUpdate($hash,'state','FIRMWARE UPDATE running',1);
  $hash->{helper}{avrdudelogs} .= "$name closed\n";
  my $logFile = AttrVal('global', 'logdir', './log/') . "$hash->{TYPE}-Flash.log";

  if (-e $logFile) {
    unlink $logFile;
  }

  $hash->{helper}{avrdudecmd} =~ s/\Q[LOGFILE]\E/$logFile/g;
  local $SIG{CHLD} = 'DEFAULT';
  delete($hash->{FLASH_RESULT}) if (exists($hash->{FLASH_RESULT}));

  qx($hash->{helper}{avrdudecmd});

  if ($? != 0 )
  {
    readingsSingleUpdate($hash,'state','FIRMWARE UPDATE with error',1);    # processed in tests
    $hash->{logMethod}->($name ,3, "$name: avrdude, ERROR: avrdude exited with error $?");
    if (defined $FW_wname)
    {
      FW_directNotify("FILTER=$name", "FHEMWEB:$FW_wname", "FW_okDialog('ERROR: avrdude exited with error, for details see last flashlog.')", '');
    }
    $hash->{FLASH_RESULT}='ERROR: avrdude exited with error';              # processed in tests
  } else {
    $hash->{logMethod}->($name ,3, "$name: avrdude, Firmware update was successfull");
    readingsSingleUpdate($hash,'state','FIRMWARE UPDATE successfull',1);   # processed in tests
  }

  local $/=undef;
  if (-e $logFile) {
    open FILE, $logFile;
    $hash->{helper}{avrdudelogs} .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
    $hash->{helper}{avrdudelogs} .= <FILE>;
    $hash->{helper}{avrdudelogs} .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
    close FILE;
  } else {
    $hash->{helper}{avrdudelogs} .= "WARNING: avrdude created no log file\n\n";
    readingsSingleUpdate($hash,'state','FIRMWARE UPDATE with error',1);
    $hash->{FLASH_RESULT}= 'WARNING: avrdude created no log file';         # processed in tests
  }

  DevIo_OpenDev($hash, 0, \&SIGNALduino_DoInit, \&SIGNALduino_Connect);
  $hash->{helper}{avrdudelogs} .= "$name reopen started\n";
  return $hash->{FLASH_RESULT};
}

############################# package main
sub SIGNALduino_PrepareFlash {
  my ($hash,$hexFile) = @_;

  my $name=$hash->{NAME};
  my $hardware=AttrVal($name,'hardware','');
  my ($port,undef) = split('@', $hash->{DeviceName});
  my $baudrate= 57600;
  my $log = '';
  my $avrdudefound=0;
  my $tool_name = 'avrdude';
  my $path_separator = ':';
  if ($^O eq 'MSWin32') {
    $tool_name .= '.exe';
    $path_separator = ';';
  }
  for my $path ( split /$path_separator/, $ENV{PATH} ) {
    if ( -f "$path/$tool_name" && -x _ ) {
      $avrdudefound=1;
      last;
    }
  }
  $hash->{logMethod}->($name, 5, "$name: PrepareFlash, avrdude found = $avrdudefound");
  return 'avrdude is not installed. Please provide avrdude tool example: sudo apt-get install avrdude' if($avrdudefound == 0);

  $log .= "flashing Arduino $name\n";
  $log .= "hex file: $hexFile\n";
  $log .= "port: $port\n";

  # prepare default Flashcommand
  my $defaultflashCommand = ($hardware eq 'radinoCC1101' 
    ? 'avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]' 
    : 'avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]');

  # get User defined Flashcommand
  my $flashCommand = AttrVal($name,'flashCommand',$defaultflashCommand);

  if ($defaultflashCommand eq $flashCommand)  {
    $hash->{logMethod}->($name, 5, "$name: PrepareFlash, standard flashCommand is used to flash.");
  } else {
    $hash->{logMethod}->($name, 3, "$name: PrepareFlash, custom flashCommand is manual defined! $flashCommand");
  }

  DevIo_CloseDev($hash);
  if ($hardware eq 'radinoCC1101' && $^O eq 'linux') {
    $hash->{logMethod}->($name, 3, "$name: PrepareFlash, forcing special reset for $hardware on $port");
    # Mit dem Linux-Kommando 'stty' die Port-Einstellungen setzen
    use IPC::Open3;

    my($chld_out, $chld_in, $chld_err);
    use Symbol 'gensym';
    $chld_err = gensym;
    my $pid;
    eval {
      $pid = open3($chld_in,$chld_out, $chld_err,  "stty -F $port ospeed 1200 ispeed 1200");
      close($chld_in);  # give end of file to kid, or feed him
    };
    if ($@) {
      $hash->{helper}{stty_output}=$@;
    } else {
      my @outlines = <$chld_out>;              # read till EOF
      my @errlines = <$chld_err>;              # XXX: block potential if massive
      $hash->{helper}{stty_pid}=$pid;
      $hash->{helper}{stty_output} = join(' ',@outlines).join(' ',@errlines);
    }
    $port =~ s/usb-Unknown_radino/usb-In-Circuit_radino/g;
    $hash->{logMethod}->($name ,3, "$name: PrepareFlash, changed usb port to \"$port\" for avrdude flashcommand compatible with radino");
  }
  $hash->{helper}{avrdudecmd} = $flashCommand;
  $hash->{helper}{avrdudecmd}=~ s/\Q[PORT]\E/$port/g;
  $hash->{helper}{avrdudecmd} =~ s/\Q[HEXFILE]\E/$hexFile/g;
  if ($hardware =~ '^nano' && $^O eq 'linux') {
    $hash->{logMethod}->($name ,5, "$name: PrepareFlash, try additional flash with baudrate 115200 for optiboot");
    $hash->{helper}{avrdudecmd} = $hash->{helper}{avrdudecmd}." || ". $hash->{helper}{avrdudecmd};
    $hash->{helper}{avrdudecmd} =~ s/\Q[BAUDRATE]\E/$baudrate/;
    $baudrate=115200;
  }
  $hash->{helper}{avrdudecmd} =~ s/\Q[BAUDRATE]\E/$baudrate/;
  $log .= "command: $hash->{helper}{avrdudecmd}\n\n";
  FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + 1,\&SIGNALduino_avrdude,$name);
  $hash->{helper}{avrdudelogs} = $log;
  return ;
}

#$hash,$name,'sendmsg','P17;R6#'.substr($arg,2)
############################# package main, test exists
sub SIGNALduino_RemoveLaCrossePair {
  my $hash = shift;
  delete($hash->{LaCrossePair});
  $hash->{logMethod}->($hash->{NAME}, 4, "$hash->{NAME}: Set_LaCrossePairForSec, time expired, LaCrosse autocreate deactivate");
}

############################# package main, test exists
sub SIGNALduino_Set($$@) {
  my ($hash,$name, @a) = @_;

  return "\"set SIGNALduino\" needs at least one parameter" if(@a < 1);

  if (!InternalVal($name,'cc1101_available',0) && $a[0] =~ /^cc1101/) {
    return 'This command is only available with a cc1101 receiver';
  }
  if (!exists($sets{$a[0]})) {
    return "Unknown argument $a[0], choose one of supported commands";
  }
  my $rcode=undef;
  if ( ( (exists($hash->{DevState}) && $hash->{DevState} eq 'initialized') || $a[0] eq '?' || $a[0] eq 'reset'|| $a[0] eq 'flash') && ref @{$sets{$a[0]}}[1] eq 'CODE') { #Todo uninitalized value
    $rcode= @{$sets{$a[0]}}[1]->($hash,@a);
  } elsif ($hash->{DevState} ne 'initialized') {
    $rcode= "$name is not active, may firmware is not supported, please flash or reset";
  }

  return $rcode; # We will exit here, and give an output only, $rcode has some value
}

############################# package main
sub SIGNALduino_Set_FhemWebList {
  my ($hash, @a) = @_;
  my @cList = sort map { "$_:@{$sets{$_}}[0]" } grep {
    ($_ ne '?' &&
      (
        ( IsDummy($hash->{NAME}) && $_ =~ m/^(?:close|reset|LaCrossePairForSec)/ ) ||
        ($_ =~ m/^LaCrossePairForSec/ && ReadingsVal($hash->{NAME},'cc1101_config_ext','') =~ '2-FSK') ||       
        ( (InternalVal($hash->{NAME},'cc1101_available',0 ) || (!InternalVal($hash->{NAME},'cc1101_available',0) && $_ !~ /^cc/ )) && $_ !~ m/^LaCrossePairForSec/) &&
        ( !IsDummy($hash->{NAME}) && (defined(DevIo_IsOpen($hash)) || $_ =~ m/^(?:flash|reset)/)  )
      )
    )
  }  keys %sets;
  map {
    my $set_key=$_;
    my ($index) = grep { $cList[$_] =~ /^$set_key:/ } (0 .. $#cList-1);
    $cList[$index] = "$set_key:".$hash->{additionalSets}{$set_key}  if (defined($index));
  } keys %{$hash->{additionalSets}};
  return "Unknown argument $a[0], choose one of " . join(' ', @cList);
}

############################# package main
sub SIGNALduino_Set_raw {
  my ($hash, @a) = @_;
  $hash->{logMethod}->($hash->{NAME}, 4, "$hash->{NAME}: Set_raw, ".join(' ',@a));
  SIGNALduino_AddSendQueue($hash,$a[1]);
  if ($a[1] =~ m/^C[D|E]R/) { # enable/disable data reduction
    SIGNALduino_Get_Command($hash,'config');
  }
  return ;
}

############################# package main
 sub SIGNALduino_Set_flash {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  return "Please define your hardware! (attr $name hardware <model of your receiver>) " if (AttrVal($name,'hardware','') eq '');

  my @args = @a[1..$#a];
  return 'ERROR: argument failed! flash [hexFile|url]' if (!$args[0]);

  my %http_param = (
    timeout    => 5,
    hash       => $hash,                                                     # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
    method     => 'GET',                                                     # Lesen von Inhalten
    header     => "User-Agent: perl_fhem\r\nAccept: application/json",       # Den Header gemaess abzufragender Daten aendern
  );

  my $hexFile = '';
  if( ( exists $hash->{additionalSets}{flash} ) && ( grep $args[0] eq $_ , split(',',$hash->{additionalSets}{flash}) ) )
  {
    $hash->{logMethod}->($hash, 3, "$name: Set_flash, $args[0] try to fetch github assets for tag $args[0]");
    my $ghurl = "https://api.github.com/repos/RFD-FHEM/SIGNALDuino/releases/tags/$args[0]";
    $hash->{logMethod}->($hash, 3, "$name: Set_flash, $args[0] try to fetch release $ghurl");

    $http_param{url}        = $ghurl;
    $http_param{callback}   = \&SIGNALduino_githubParseHttpResponse;  # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
    $http_param{command}    = 'getReleaseByTag';
    HttpUtils_NonblockingGet(\%http_param);                         # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    return;
  } elsif ($args[0] =~ m/^https?:\/\// ) {
    $http_param{url}        = $args[0];
    $http_param{callback}   = \&SIGNALduino_ParseHttpResponse;        # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
    $http_param{command}    = 'flash';
    HttpUtils_NonblockingGet(\%http_param);
    return;
  } else {
    $hexFile = $args[0];
  }
  $hash->{logMethod}->($name, 3, "$name: Set_flash, filename $hexFile provided, trying to flash");

  # Only for Arduino , not for ESP
  my $hardware = AttrVal($name,'hardware','');
  if ($hardware =~ m/(?:nano|mini|radino)/)
  {
    return SIGNALduino_PrepareFlash($hash,$hexFile);
  } else {
    if (defined $FW_wname)
    {
      FW_directNotify("FILTER=$name", "#FHEMWEB:$FW_wname", "FW_okDialog('<u>ERROR:</u><br>Sorry, flashing your $hardware is currently not supported.<br>The file is only downloaded in /opt/fhem/FHEM/firmware.')", '');
    }
    return "Sorry, Flashing your $hardware via Module is currently not supported.";    # processed in tests
  }
}

############################# package main
sub SIGNALduino_Set_reset
{
  my $hash = shift;
  delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
  return SIGNALduino_ResetDevice($hash);
}

############################# package main
sub SIGNALduino_Attr_rfmode {
  my $hash = shift // carp 'must be called with hash of iodevice as first param';
  my $aVal = shift // return;

  if ( (InternalVal($hash->{NAME},"cc1101_available",0) == 0) && (!IsDummy($hash->{NAME})) ) {
    return 'ERROR: This attribute is only available for a receiver with CC1101.';
  }

  ## DevState waitInit is on first start after FHEM restart | initialized is after cc1101 available
  if ( ($hash->{DevState} eq 'initialized') && (InternalVal($hash->{NAME},"cc1101_available",0) == 1) ) {
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: Set_rfmode, set to $aVal on DevState $hash->{DevState} (please check activated protocols via 'Display protocollist')");

    my $rfmode;
    if ($aVal ne 'SlowRF') {
      if ( scalar( @{$hash->{mnIdList}} ) >= 1 ) {
        MNIDLIST:
        for my $id (@{$hash->{mnIdList}}) {
          $rfmode=$hash->{protocolObject}->checkProperty($id,'rfmode',-1);

          if ($rfmode eq $aVal) {
            $hash->{logMethod}->($hash->{NAME}, 4, qq[$hash->{NAME}: Set_rfmode, rfmode found on ID=$id]);
            my $register=$hash->{protocolObject}->checkProperty($id,'register', -1);

            if ($register != -1) {
              $hash->{logMethod}->($hash->{NAME}, 5, qq[$hash->{NAME}: Set_rfmode, register settings exist on ID=$id ]);

              for my $i (0...scalar(@{$register})-1) {
                $hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: Set_rfmode, write value " . @{$register}[$i]);
                my $argcmd = sprintf("W%02X%s",hex(substr(@{$register}[$i],0,2)) + 2,substr(@{$register}[$i],2,2));
                main::SIGNALduino_AddSendQueue($hash,$argcmd);
              }
              main::SIGNALduino_WriteInit($hash);
              last MNIDLIST;  # found $rfmode, exit loop
            } else {
              $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: Set_rfmode, set to $aVal (ID $id, no register entry found in protocols)");
            }
          }
        };
        ## rfmode is always set if it is available / if the set supported is not available, it is always unequal
        if ($rfmode ne $aVal) {
          $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: Set_rfmode, set to $aVal rfmode value not found in protocols");
          return 'ERROR: protocol '.$aVal.' is not activated in \'Display protocollist\'';
        };
      } else {
        $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Set_rfmode, no MN protocols in 'Display protocollist' activated]);
        return 'ERROR: no MN protocols activated in \'Display protocollist\'';
      }
    } else {
      SIGNALduino_AddSendQueue($hash,'e');
      $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: Set_rfmode, set to $aVal (ASK/OOK mode load default register settings from uC)");
    }
  }

  return;
}

############################# package main
sub SIGNALduino_Set_sendMsg {
  my ($hash, @a) = @_;
  $hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: Set_sendMsg, msg=$a[1]");
  return "Error: $hash->{NAME} does not exists" if (!IsDevice($hash->{NAME}));
  # Split args in serval variables
  my ($protocol,$data,$repeats,$clock,$frequency,$datalength,$dataishex);
  my $n=0;
  for my $s (split '#', $a[1]) {
    my $c = substr($s,0,1);
    if ($n == 0 ) {  #  protocol
      $protocol = substr($s,1);
    } elsif ($n == 1) { # Data
      $data = $s;
      if   ( substr($s,0,2) eq '0x' ) { $dataishex=1; $data=substr($data,2); }
        else { $dataishex=0; }

    } else {
      if ($c eq 'R') { $repeats = substr($s,1);  }
        elsif ($c eq 'C') { $clock = substr($s,1);   }
        elsif ($c eq 'F' && InternalVal($hash->{NAME},'cc1101_available',0)) { $frequency = substr($s,1);  }
        elsif ($c eq 'L') { $datalength = substr($s,1);   }
    }
    $n++;
  };
  return "$hash->{NAME}: sendmsg, unknown protocol: $protocol" if (!$hash->{protocolObject}->protocolExists($protocol));

  $repeats //= 1 ;
  if (InternalVal($hash->{NAME},'cc1101_available',0))
  {
    my $f=$hash->{protocolObject}->getProperty($protocol,'frequency');
    if ( defined $f ) {
      $frequency = q[F=].$hash->{protocolObject}->getProperty($protocol,'frequency'). q[;]
    }
  }
  $frequency //= q{};
  my %signalHash;
  my %patternHash;
  my $pattern='';
  my $cnt=0;

  my $sendData;
  ## modulation ASK/OOK - MC
  if (defined($hash->{protocolObject}->getProperty($protocol,'format')) && $hash->{protocolObject}->getProperty($protocol,'format') eq 'manchester')
  {
    $clock += $_ for( @{$hash->{protocolObject}->getProperty($protocol,'clockrange')} );
    $clock = round($clock/2,0);

    my $intro;
    my $outro;

    $intro = $hash->{protocolObject}->checkProperty($protocol,'msgIntro','');
    $outro = sprintf('%s',$hash->{protocolObject}->checkProperty($protocol,'msgOutro',''));

    if ($intro ne '' || $outro ne '')
    {
      $intro = qq[SC;R=$repeats;] . $intro;
      $repeats = 0;
    }

    $sendData = $intro . 'SM;' . ($repeats > 0 ? "R=$repeats;" : '') . "C=$clock;D=$data;" . $outro . $frequency; # SM;R=2;C=400;D=AFAFAF;
    $hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: Set_sendMsg, Preparing manchester protocol=$protocol, repeats=$repeats, clock=$clock data=$data");

  ## modulation xFSK
  } elsif (defined($hash->{protocolObject}->getProperty($protocol,'register')) && defined($hash->{protocolObject}->getProperty($protocol,'rfmode'))) {
    $hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: Set_sendMsg, Preparing ".$hash->{protocolObject}->getProperty($protocol,'rfmode')." protocol=$protocol, repeats=$repeats,data=$data");
    $sendData = 'SN;' . ($repeats > 0 ? "R=$repeats;" : '') . "D=$data;" # SN;R=1;D=08C11484498ABCDE;
  ## modulation ASK/OOK - MS MU
  } else {
    if ($protocol == 3 || substr($data,0,2) eq 'is') {
      if (substr($data,0,2) eq 'is') {
        $data = substr($data,2);   # is am Anfang entfernen
      }
      $data = $hash->{protocolObject}->ConvITV1_tristateToBit($data);
      $hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: Set_sendMsg, IT V1 convertet tristate to bits=$data");
    }
    if (!defined $clock ) {
      $hash->{ITClock} = 250 if (!defined $hash->{ITClock} );   # Todo: Klaeren wo ITClock verwendet wird und ob wir diesen Teil nicht auf Protokoll 3,4 und 17 minimieren
      $clock= $hash->{protocolObject}->checkProperty($protocol,'clockabs',0) > 1 
        ? $hash->{protocolObject}->getProperty($protocol,'clockabs')
        : $hash->{ITClock};
    }

    if ($dataishex == 1)
    {
      # convert hex to bits
      my $hlen = length($data);
      my $blen = $hlen * 4;
      $data = unpack("B$blen", pack("H$hlen", $data));
    }
    $hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: Set_sendMsg, Preparing rawsend command for protocol=$protocol, repeats=$repeats, clock=$clock bits=$data");

    for my $item (qw(preSync sync start one zero float pause end universal))
    {
      my $value = $hash->{protocolObject}->getProperty($protocol,$item);
      next if (!defined $value );

      for my $p ( @{$value} )
      {
        if (!exists($patternHash{$p}))
        {
          $patternHash{$p}=$cnt;
          $pattern.='P'.$patternHash{$p}.'='. int($p*$clock) .';';
          $cnt++;
        }
        $signalHash{$item}.=$patternHash{$p};
      }
    }
    my @bits = split('', $data);

    my %bitconv = (1=>'one', 0=>'zero', 'D'=> 'float', 'F'=> 'float', 'P'=> 'pause', 'U'=> 'universal');
    my $SignalData='D=';

    $SignalData.=$signalHash{preSync} if (exists($signalHash{preSync}));
    $SignalData.=$signalHash{sync} if (exists($signalHash{sync}));
    $SignalData.=$signalHash{start} if (exists($signalHash{start}));
    foreach my $bit (@bits)
    {
      next if (!exists($bitconv{$bit}));
      $SignalData.=$signalHash{$bitconv{$bit}}; ## Add the signal to our data string
    }
    $SignalData.=$signalHash{end} if (exists($signalHash{end}));
    $sendData = "SR;R=$repeats;$pattern$SignalData;$frequency";
  }
  SIGNALduino_AddSendQueue($hash,$sendData);
  $hash->{logMethod}->($hash->{NAME}, 4, "$hash->{NAME}: Set_sendMsg, sending : $sendData");
}

############################# package main
sub SIGNALduino_Set_close {
  my $hash = shift;
  $hash->{DevState} = 'closed';
  return SIGNALduino_CloseDevice($hash);
}

############################# package main
sub SIGNALduino_Set_MessageType {
  my ($hash, @a) = @_;
  my $argm;
  if ($a[0] =~ /^enable/) {
    $argm = 'CE' . substr($a[1],-1,1);
  } else {
    $argm = 'CD' . substr($a[1],-1,1);
  }
  SIGNALduino_AddSendQueue($hash,$argm);
  SIGNALduino_Get_Command($hash,'config');
  $hash->{logMethod}->($hash->{NAME}, 4, "$hash->{NAME}: Set_MessageType, $a[0] $a[1] $argm");
}

############################# package main
sub SIGNALduino_Set_bWidth {
  my ($hash, @a) = @_;

  if (exists($hash->{ucCmd}->{cmd}) && $hash->{ucCmd}->{cmd} eq 'set_bWidth' && $a[0] =~ /^C10\s=\s([A-Fa-f0-9]{2})$/ )
  {
    my ($ob,$bw) = cc1101::CalcbWidthReg($hash,$1,$hash->{ucCmd}->{arg});
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: Set_bWidth, bWidth: Setting MDMCFG4 (10) to $ob = $bw KHz");
    # Toddo setRegisters verwenden
    main::SIGNALduino_AddSendQueue($hash,"W12$ob");
    main::SIGNALduino_WriteInit($hash);
    return ("Setting MDMCFG4 (10) to $ob = $bw KHz" ,undef);
  } else {
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: Set_bWidth, Request register 10");
    # Get Register 10
    cc1101::GetRegister($hash,10);

    $hash->{ucCmd}->{cmd}         = 'set_bWidth';
    $hash->{ucCmd}->{arg}         = $a[1];                                  # Zielbandbreite
    $hash->{ucCmd}->{responseSub} = \&SIGNALduino_Set_bWidth;               # Callback auf sich selbst setzen
    $hash->{ucCmd}->{asyncOut}    = $hash->{CL} if (defined($hash->{CL}));
    $hash->{ucCmd}->{timenow}     = time();
    #return 'Register 10 requested';
    return ;
  }
}

############################# package main
# LaCrosse sensor is comfortable to put on (own way from 36_LaCrosse.pm)
sub SIGNALduino_Set_LaCrossePairForSec {
  my ($hash, @a) = @_;

  #              set NAME           a[0]       a[1]             a[2]
  return "Usage: set $hash->{NAME} $a[0] <seconds_active> [ignore_battery]" if(!$a[0] || $a[1] !~ m/^\d+$/xms || (defined $a[2] && $a[2] ne 'ignore_battery') );
  $hash->{LaCrossePair} = 2;  # LaCrosse autoCreateState: 0 = autoreate not defined | 1 = autocreate defined | 2 = autocreate active
  $hash->{logMethod}->($hash->{NAME}, 4, "$hash->{NAME}: Set_LaCrossePairForSec, LaCrosse autocreate active for $a[1] seconds");
  
  FHEM::Core::Timer::Helper::addTimer($hash->{NAME},gettimeofday()+$a[1], \&SIGNALduino_RemoveLaCrossePair, $hash, 0);

  return ;
}

############################# package main, test exists
sub SIGNALduino_Get($@) {
  my ($hash,$name, @a) = @_;
  #my $type = $hash->{TYPE};

  return "\"get SIGNALduino\" needs at least one parameter" if(@a < 1);

  if (!InternalVal($name,'cc1101_available',0) && $a[0] =~ /^cc/) {
    return 'This command is only available with a cc1101 receiver';
  }
  if (!exists($gets{$a[0]})) {
    return "Unknown argument $a[0], choose one of supported commands";
  }
  my $rcode=undef;
  if (exists($hash->{ucCmd}) && $a[0] ne '?' ) {
    SIGNALduino_Get_delayed("SIGNALduino_Get_delayed:$name:".join(':',@a));
  } elsif ( ($hash->{DevState} eq 'initialized' || $a[0] eq '?' || $a[0] eq 'availableFirmware') && ref @{$gets{$a[0]}}[1] eq 'CODE') { #
    $rcode= @{$gets{$a[0]}}[1]->($hash,@a);
  } elsif ($hash->{DevState} ne 'initialized') {
    $rcode= "$name is not active, may firmware is not supported, please flash or reset";
  }

  return $rcode;    # We will exit here, and give an output only, $rcode has some value
}

############################# package main, test exists
#SIGNALduino_Get_Callback($name, $callbackFn, @args);
sub SIGNALduino_Get_Callback {
  my ($name, $callbackFn, $arg) = @_;

  my @a = split (' ',$arg);
  return "\"get _Get_Callback\" needs at least two parameters" if(@a < 2);
  return "\"$name\" is not a definition of type SIGNALduino" if (!IsDevice($name, 'SIGNALduino'));

  my $hash = $defs{$name};
  my $rcode = SIGNALduino_Get($hash,$name,@a);

  if (!defined($rcode))
  {
    $hash->{ucCmd}->{responseSub}=$callbackFn;
    delete($hash->{ucCmd}->{asyncOut});
  }

  return $rcode;    # We will exit here, and give an output only, $rcode has some value
}

############################# package main
sub SIGNALduino_Get_FhemWebList {
  my ($hash, @a) = @_;
  my @cList = sort map { "$_:@{$gets{$_}}[0]" } grep {
    ($_ ne '?' &&
      (
        (IsDummy($hash->{NAME}) && $_ =~ m/^(?:availableFirmware|raw)/) ||
        ( InternalVal($hash->{NAME},'cc1101_available',0) || (!InternalVal($hash->{NAME},'cc1101_available',0) && $_ !~ /^cc/)) &&
        ( !IsDummy($hash->{NAME}) && (defined(DevIo_IsOpen($hash))  ||  $_ =~ m/^(?:availableFirmware|raw)/  ))
      )
    )
  }  keys %gets;
  return "Unknown argument $a[0], choose one of " . join(' ', @cList);
}

############################# package main
sub SIGNALduino_Get_availableFirmware {
  my ($hash, @a) = @_;

  if ( !HAS_JSON )
  {
    $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: get $a[0] failed. Please install Perl module JSON. Example: sudo apt-get install libjson-perl");
    return "$a[0]: \n\nFetching from github is not possible. Please install JSON. Example:<br><code>sudo apt-get install libjson-perl</code>";
  }

  my $channel=AttrVal($hash->{NAME},'updateChannelFW','stable');
  my $hardware=AttrVal($hash->{NAME},'hardware',undef);

  my ($validHw) = $modules{$hash->{TYPE}}{AttrList} =~ /.*hardware:(.*?)\s/;
  $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: found availableFirmware for $validHw");

  if (!defined($hardware) || $validHw !~ /$hardware(?:,|$)/ )
  {
    $hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: get $a[0] failed. Please set attribute hardware first");
    return "$a[0]: \n\n$hash->{NAME}: get $a[0] failed. Please choose one of $validHw attribute hardware";
  }
  SIGNALduino_querygithubreleases($hash);
  return "$a[0]: \n\nFetching $channel firmware versions for $hardware from github\n";
}

############################# package main
sub SIGNALduino_Get_Command {
  my ($hash, @a) = @_;
  my $name=$hash->{NAME};
  return 'Unsupported command for the microcontroller' if (!exists(${$gets{$a[0]}}[2]));
  $hash->{logMethod}->($name, 5, "$name: Get_Command $a[0] executed");
  SIGNALduino_AddSendQueue($hash, @{$gets{$a[0]}}[2] . (exists($a[1]) ? "$a[1]" : ''));
  $hash->{ucCmd}->{cmd}=$a[0];
  $hash->{ucCmd}->{responseSub}=$gets{$a[0]}[3];
  $hash->{ucCmd}->{asyncOut}=$hash->{CL}  if (defined($hash->{CL}));
  $hash->{ucCmd}->{timenow}=time();
  return ;
}

############################# package main
sub SIGNALduino_Get_Command_CCReg {
  my ($hash, @a) = @_;
  return 'not enough number of arguments' if $#a < 1;
  return 'Wrong command provided' if $a[0] ne 'ccreg';
  my $name=$hash->{NAME};
  if (exists($cc1101_register{uc($a[1])}) || $a[1] eq '99' || $a[1] =~ /^3[0-9a-dA-D]$/ ) {
    return SIGNALduino_Get_Command(@_);
  } else {
    return "unknown Register $a[1], please choose a valid cc1101 register";
  }
}

############################# package main
sub SIGNALduino_Get_RawMsg {
  my ($hash, @a) = @_;
  return "\"get raw\" needs at least a parameter" if (@a < 2);
  if ($a[1] =~ /^M[CcSUN];.+/)
  {
    $a[1]="\002$a[1]\003";    ## Add start end end marker if not already there
    $hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: msg adding start and endmarker to message");
  }

  if ($a[1] =~ /\002M\w;.+;\003$/)
  {
    $hash->{logMethod}->( $hash->{NAME}, 4, "$hash->{NAME}: get rawmsg: $a[1]");
    my $cnt = SIGNALduino_Parse($hash, $hash, $hash->{NAME}, $a[1]);
    if (defined $cnt) {
      return "Parse raw msg, number of messages passed to modules: $cnt";
    } else {
      return "Parse raw msg, no suitable protocol recognized.";
    }
  } else {
    return 'This command is not supported via get rawmsg.';
  }
}

############################# package main, test exists
sub SIGNALduino_GetResponseUpdateReading {
  return ($_[1],1);
}

############################# package main
sub SIGNALduino_Get_delayed {
  my(undef,$name,@cmds) = split(':', shift);
  my $hash = $defs{$name};
  
  if ( exists($hash->{ucCmd}) && !exists($hash->{ucCmd}->{timenow}) ) {
    $hash->{ucCmd}->{timenow}=time();
    Log3 ($hash->{NAME}, 5, "$name: Get_delayed, timenow was missing, set ".$hash->{ucCmd}->{timenow}); 
  }
    
  if (exists($hash->{ucCmd})  && $hash->{ucCmd}->{timenow}+10 > time() ) {
    $hash->{logMethod}->($hash->{NAME}, 5, "$name: Get_delayed, ".join(' ',@cmds).' delayed');
    FHEM::Core::Timer::Helper::addTimer($name,main::gettimeofday() + main::SDUINO_GET_CONFIGQUERY_DELAY, \&SIGNALduino_Get_delayed, "SIGNALduino_Get_delayed:$name:".join(' ',@cmds), 0);
  } else {
    delete($hash->{ucCmd}); 
    $hash->{logMethod}->($hash->{NAME}, 5, "$name: Get_delayed, ".join(' ',@cmds).' executed');
    FHEM::Core::Timer::Helper::removeTimer($name,\&SIGNALduino_Get_delayed,"SIGNALduino_Get_delayed:$name:".join(' ',@cmds));
    

        
    SIGNALduino_Get($hash,$name,$cmds[0]);
  }
}

############################# package main, test exists
sub SIGNALduino_CheckUptimeResponse {
  my $msg = sprintf("%d %02d:%02d:%02d", $_[1]/86400, ($_[1]%86400)/3600, ($_[1]%3600)/60, $_[1]%60);
  #readingsSingleUpdate($_[0], $_[0]->{ucCmd}->{cmd}, $msg, 0);
  return ($msg,0);
}

############################# package main, test exists
sub SIGNALduino_CheckCmdsResponse {
  my $hash = shift;
  my $msg = shift;
  my $name=$hash->{NAME};

  $msg =~ s/$name cmds =>//g;
  $msg =~ s/.*Use one of//g;

  return ($msg,0);
}

############################# package main, test exists
sub SIGNALduino_CheckccConfResponse {
  my (undef,$str) = split('=', $_[1]);
  my $var;

  # https://github.com/RFD-FHEM/RFFHEM/issues/1015 | value can arise due to an incorrect transmission from serial
  # $str = "216%E857C43023B900070018146C040091";
  return ('invalid value from uC. Only hexadecimal values are allowed. Please query again.',undef) if($str !~ /^[A-F0-9a-f]+$/);

  my %r = ( '0D'=>1,'0E'=>1,'0F'=>1,'10'=>1,'11'=>1,'12'=>1,'1B'=>1,'1D'=>1, '15'=>1);
  foreach my $a (sort keys %r) {
    $var = substr($str,(hex($a)-13)*2, 2);
    $r{$a} = hex($var);
  }
  my $msg = sprintf("Freq: %.3f MHz, Bandwidth: %d kHz, rAmpl: %d dB, sens: %d dB, DataRate: %.2f kBaud",
    26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                 #Freq       | Register 0x0D,0x0E,0x0F
    26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),    #Bw         | Register 0x10
    $ampllist[$r{"1B"}&7],                                           #rAmpl      | Register 0x1B
    4+4*($r{"1D"}&3),                                                #Sens       | Register 0x1D
    (((256+$r{"11"})*(2**($r{"10"} & 15 )))*26000000/(2**28) / 1000) #DataRate   | Register 0x10,0x11
  );

  my $msg2 = sprintf("Modulation: %s",
    $modformat[$r{"12"}>>4],                                        #Modulation | Register 0x12
  );

  if ($msg2 !~ /Modulation:\sASK\/OOK/) {
    $msg2 .= ", Syncmod: ".$syncmod[($r{"12"})&7];                                                    #Syncmod    | Register 0x12
    $msg2 .= ", Deviation: ".round((8+($r{"15"}&7))*(2**(($r{"15"}>>4)&7)) *26000/(2**17),2) .' kHz'; #Deviation  | Register 0x15
  }

  readingsBeginUpdate($_[0]);
  readingsBulkUpdate($_[0], 'cc1101_config', $msg);
  readingsBulkUpdate($_[0], 'cc1101_config_ext', $msg2);
  readingsEndUpdate($_[0], 1);

  return ($msg.', '.$msg2,undef);
}

############################# package main, test exists
sub SIGNALduino_CheckccPatableResponse {
  my $hash = shift;
  my $msg = shift;
  my $name=$hash->{NAME};

  my $CC1101Frequency=AttrVal($name,'cc1101_frequency',433);
  $CC1101Frequency = 433 if ($CC1101Frequency >= 433 && $CC1101Frequency <= 435);
  $CC1101Frequency = 868 if ($CC1101Frequency >= 863 && $CC1101Frequency <= 870);
  my $dBn = substr($msg,9,2);
  $hash->{logMethod}->($name, 3, "$name: CheckCcpatableResponse, patable: $dBn");
  foreach my $dB (keys %{ $patable{$CC1101Frequency} }) {
    if ($dBn eq $patable{$CC1101Frequency}{$dB}) {
      $hash->{logMethod}->($name, 5, "$name: CheckCcpatableResponse, patable: $dB");
      $msg .= " => $dB";
      last;
    }
  }
  readingsSingleUpdate($hash, 'cc1101_patable', $msg,1);
  return ($msg,undef);
}

############################# package main, test exists
sub SIGNALduino_CheckCcregResponse {
  my $hash = shift;
  my $msg = shift;
  my $name=$hash->{NAME};
  $hash->{logMethod}->($name, 5, "$name: CheckCcregResponse, msg $msg");
  if ($msg =~ /^ccreg/) {
    my $msg1 = $msg;
    $msg =~ s/\s\s/\n/g;
    $msg = "\nConfiguration register overview:\n---------------------------------------------------------\n" . $msg;
    $msg.= "\n\nConfiguration register detail:\n---------------------------------------------------------\nadd.  name       def.   cur.\n";
    $msg1 =~ s/ccreg\s\d0:\s//g;
    $msg1 =~ s/\s\s/ /g;
    my @ccreg = split(/\s/,$msg1);
    my $reg_idx = 0;
    foreach my $key (sort keys %cc1101_register) {
      $msg.= '0x'.$key.'  '.$cc1101_register{$key}. ' - 0x'.$ccreg[$reg_idx]."\n";
      $reg_idx++;
    }
  } else {
    $msg =~ /^C([A-Fa-f0-9]{2}) = ([A-Fa-f0-9]{2})$/;
    my $reg = $1;
    my $val = $2;
    if ( $reg =~ /^3[0-9a-dA-D]$/ ) { # Status register
      $msg = "\nStatus register detail:\n---------------------------\nadd.  name             cur.\n";
      $msg .= "0x$reg  $cc1101::cc1101_status_register{$reg} - 0x$val";
      if ( $reg eq '31' && exists $cc1101::cc1101_version{$val}) { # VERSION – Chip ID
        $msg .= " Chip $cc1101::cc1101_version{$val}";
      }
    } else { # Configuration Register
      $msg = "\nConfiguration register detail:\n------------------------------\nadd.  name       def.   cur.\n";
      $msg .= "0x$reg  $cc1101_register{$reg} - 0x$val";
    }
    $msg .= "\n";
  }
  return ("\n".$msg,undef);
}


############################# package main
### Unused ??? ### in use
sub SIGNALduino_CheckSendRawResponse {
  my $hash = shift;
  my $msg = shift;

  if ($msg =~ /^S[RCMN];/ )
  {
    my $name=$hash->{NAME};
    # zu testen der sendeQueue, kann wenn es funktioniert auf verbose 5
    $hash->{logMethod}->($name, 4, "$name: CheckSendrawResponse, sendraw answer: $msg");
    delete($hash->{ucCmd});
    if ($msg =~ /D=[A-Za-z0-9]+;/ )
    {
      FHEM::Core::Timer::Helper::removeTimer($name,\&SIGNALduino_HandleWriteQueue,"HandleWriteQueue:$name");
      SIGNALduino_HandleWriteQueue("x:$name"); # Todo #823 on github
    } else {
      FHEM::Core::Timer::Helper::addTimer($name,scalar gettimeofday() , \&SIGNALduino_HandleWriteQueue, "HandleWriteQueue:$name") if (scalar @{$hash->{QUEUE}} > 0 && InternalVal($name,'sendworking',0) == 0);
      
    }
  }
  return (undef);
}

############################# package main
sub SIGNALduino_ResetDevice {
  my $hash = shift;
  my $name = $hash->{NAME};

  if (!defined($hash->{helper}{resetInProgress})) {
    my $hardware = AttrVal($name,'hardware','');
    $hash->{logMethod}->($name, 3, "$name: ResetDevice, $hardware");

    if (IsDummy($name)) { # for dummy device
      $hash->{DevState} = 'initialized';
      readingsSingleUpdate($hash, 'state', 'opened', 1);
      return ;
    }

    DevIo_CloseDev($hash);
    if ($hardware eq 'radinoCC1101' && $^O eq 'linux') {
      # The reset is triggered when the Micro's virtual (CDC) serial / COM port is opened at 1200 baud and then closed.
      # When this happens, the processor will reset, breaking the USB connection to the computer (meaning that the virtual serial / COM port will disappear).
      # After the processor resets, the bootloader starts, remaining active for about 8 seconds.
      # The bootloader can also be initiated by pressing the reset button on the Micro.
      # Note that when the board first powers up, it will jump straight to the user sketch, if present, rather than initiating the bootloader.
      my ($dev, $baudrate) = split("@", $hash->{DeviceName});
      $hash->{logMethod}->($name, 3, "$name: ResetDevice, forcing special reset for $hardware on $dev");
      # Mit dem Linux-Kommando 'stty' die Port-Einstellungen setzen
      system("stty -F $dev ospeed 1200 ispeed 1200");
      $hash->{helper}{resetInProgress}=1;
      FHEM::Core::Timer::Helper::addTimer($name,gettimeofday()+10,\&SIGNALduino_ResetDevice,$hash);
      
      $hash->{logMethod}->($name, 3, "$name: ResetDevice, reopen delayed for 10 second");
      return ;
    }
  } else {
    delete($hash->{helper}{resetInProgress});
  }
  DevIo_OpenDev($hash, 0, \&SIGNALduino_DoInit, \&SIGNALduino_Connect);
  return ;
}

############################# package main
sub SIGNALduino_CloseDevice {
  my ($hash) = @_;

  $hash->{logMethod}->($hash->{NAME}, 2, "$hash->{NAME}: CloseDevice, closed");
  FHEM::Core::Timer::Helper::removeTimer($hash->{NAME});
  DevIo_CloseDev($hash);
  readingsSingleUpdate($hash, 'state', 'closed', 1);

  return ;
}

############################# package main
sub SIGNALduino_DoInit {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my ($ver, $try) = ('', 0);
  #Dirty hack to allow initialisation of DirectIO Device for some debugging and tesing

  delete($hash->{disConnFlag}) if defined($hash->{disConnFlag});

  FHEM::Core::Timer::Helper::removeTimer($name,\&SIGNALduino_HandleWriteQueue,"HandleWriteQueue:$name");
  @{$hash->{QUEUE}} = ();
  $hash->{sendworking} = 0;

  if (($hash->{DEF} !~ m/\@directio/) and ($hash->{DEF} !~ m/none/) )
  {
    $hash->{logMethod}->($hash, 1, "$name: DoInit, ".$hash->{DEF});
    $hash->{initretry} = 0;
    FHEM::Core::Timer::Helper::removeTimer($name,undef,$hash); # What timer should be removed here is not clear

    #SIGNALduino_SimpleWrite($hash, 'XQ'); # Disable receiver
    
    FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + SDUINO_INIT_WAIT_XQ, \&SIGNALduino_SimpleWrite_XQ, $hash, 0);
    FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + SDUINO_INIT_WAIT, \&SIGNALduino_StartInit, $hash, 0);
  }
  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  return;
}


############################# package main
# Disable receiver
sub SIGNALduino_SimpleWrite_XQ {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{logMethod}->($hash, 3, "$name: SimpleWrite_XQ, disable receiver (XQ)");
  SIGNALduino_SimpleWrite($hash, 'XQ');
  #DevIo_SimpleWrite($hash, "XQ\n",2);
}

############################# package main, test exists
sub SIGNALduino_StartInit {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  $hash->{version} = undef;

  $hash->{logMethod}->($name,3 , "$name: StartInit, get version, retry = " . $hash->{initretry});
  if ($hash->{initretry} >= SDUINO_INIT_MAXRETRY) {
    $hash->{DevState} = 'INACTIVE';
    # einmaliger reset, wenn danach immer noch 'init retry count reached', dann SIGNALduino_CloseDevice()
    if (!defined($hash->{initResetFlag})) {
      $hash->{logMethod}->($name,2 , "$name: StartInit, retry count reached. Reset");
      $hash->{initResetFlag} = 1;
      SIGNALduino_ResetDevice($hash);
    } else {
      $hash->{logMethod}->($name,2 , "$name: StartInit, init retry count reached. Closed");
      SIGNALduino_CloseDevice($hash);
    }
    return;
  }
  else {
    $hash->{ucCmd}->{cmd} = 'version';
    $hash->{ucCmd}->{responseSub} = \&SIGNALduino_CheckVersionResp;
    $hash->{ucCmd}->{timenow} = time();
    SIGNALduino_SimpleWrite($hash, 'V');
    #DevIo_SimpleWrite($hash, "V\n",2);
    $hash->{DevState} = 'waitInit';
    FHEM::Core::Timer::Helper::removeTimer($name);
    FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_CMD_TIMEOUT, \&SIGNALduino_CheckVersionResp, $hash, 0);
  }
}

############################# package main, test exists
sub SIGNALduino_CheckVersionResp {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};

  ### ToDo, manchmal kommen Mu Nachrichten in $msg und somit ist keine Version feststellbar !!!
  if (defined($msg)) {
    $hash->{logMethod}->($hash, 5, "$name: CheckVersionResp, called with $msg");
    if ($msg =~ m/($gets{$hash->{ucCmd}->{cmd}}[4])/ ) {
       $hash->{version} = $1;
    } else {
      delete $hash->{version};
    }
  } else {
    $hash->{logMethod}->($hash, 5, "$name: CheckVersionResp, called without msg");
    # Aufruf durch Timeout!
    $msg='undef';
    delete($hash->{ucCmd});
  }

  if (!defined($hash->{version}) ) {
    $msg = "$name: CheckVersionResp, Not an SIGNALduino device, got for V: $msg";
    $hash->{logMethod}->($hash, 1, $msg);
    readingsSingleUpdate($hash, 'state', 'no SIGNALduino found', 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
    $hash->{initretry} ++;
    SIGNALduino_StartInit($hash);
  } elsif($hash->{version} =~ m/^V 3\.1\./) {
    $msg = "$name: CheckVersionResp, Version of your arduino is not compatible, please flash new firmware. (device closed) Got for V: $msg";
    readingsSingleUpdate($hash, 'state', 'unsupported firmware found', 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
    $hash->{logMethod}->($hash, 1, $msg);
    $hash->{DevState} = 'INACTIVE';
    SIGNALduino_CloseDevice($hash);
  } else {
    if (exists($hash->{DevState}) && $hash->{DevState} eq 'waitInit') {
      FHEM::Core::Timer::Helper::removeTimer($name);
    }

    readingsSingleUpdate($hash, 'state', 'opened', 1);
    $hash->{logMethod}->($name, 2, "$name: CheckVersionResp, initialized " . SDUINO_VERSION);
    delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
    SIGNALduino_SimpleWrite($hash, 'XE'); # Enable receiver
    $hash->{logMethod}->($hash, 3, "$name: CheckVersionResp, enable receiver (XE) ");
    delete($hash->{initretry});
    # initialize keepalive
    $hash->{keepalive}{ok}    = 0;
    $hash->{keepalive}{retry} = 0;
    FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, \&SIGNALduino_KeepAlive, $hash, 0);
    if ($hash->{version} =~ m/cc1101/) {
      $hash->{cc1101_available} = 1;
      $hash->{logMethod}->($name, 5, "$name: CheckVersionResp, cc1101 available");
      SIGNALduino_Get($hash, $name,'ccconf');
      SIGNALduino_Get($hash, $name,'ccpatable');
    } else {
      # connect device without cc1101 to port where a device with cc1101 was previously connected (example DEF with /dev/ttyUSB0@57600) #
      $hash->{logMethod}->($hash, 5, "$name: CheckVersionResp, delete old READINGS from cc1101 device");
      if ( exists($hash->{cc1101_available}) ) {
        delete($hash->{cc1101_available});
      };

      for my $readingName  ( qw(cc1101_config cc1101_config_ext cc1101_patable) ) {
        readingsDelete($hash,$readingName);
      }
    }
    $hash->{DevState} = 'initialized';
    $msg = $hash->{version};
  }
  return ($msg,undef);
}


############################# package main, test exists
# Todo: SUB kann entfernt werden
sub SIGNALduino_CheckCmdResp {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $msg = undef;
  my $ver;

  if ($hash->{version}) {
    $ver = $hash->{version};
    if ($ver !~ m/SIGNAL(duino|ESP)/) {
      $msg = "$name: CheckCmdResp, Not an SIGNALduino device, setting attribute dummy=1 got for V:  $ver";
      $hash->{logMethod}->($hash, 1, $msg);
      readingsSingleUpdate($hash, 'state', 'no SIGNALduino found', 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
      $hash->{DevState} = 'INACTIVE';
      SIGNALduino_CloseDevice($hash);
    }
    elsif($ver =~ m/^V 3\.1\./) {
      $msg = "$name: CheckCmdResp, Version of your arduino is not compatible, pleas flash new firmware. (device closed) Got for V:  $ver";
      readingsSingleUpdate($hash, 'state', 'unsupported firmware found', 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
      $hash->{logMethod}->($hash, 1, $msg);
      $hash->{DevState} = 'INACTIVE';
      SIGNALduino_CloseDevice($hash);
    }
    else {
      readingsSingleUpdate($hash, 'state', 'opened', 1);
      $hash->{logMethod}->($name, 2, "$name: CheckCmdResp, initialized " . SDUINO_VERSION);
      $hash->{DevState} = 'initialized';
      delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
      SIGNALduino_SimpleWrite($hash, 'XE'); # Enable receiver
      $hash->{logMethod}->($hash, 3, "$name: CheckCmdResp, enable receiver (XE) ");
      delete($hash->{initretry});
      # initialize keepalive
      $hash->{keepalive}{ok}    = 0;
      $hash->{keepalive}{retry} = 0;
      FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, \&SIGNALduino_KeepAlive, $hash, 0);
      $hash->{cc1101_available} = 1  if ($ver =~ m/cc1101/);
    }
  }
  else {
    delete($hash->{ucCmd});
    $hash->{initretry} ++;
    #InternalTimer(gettimeofday()+1, 'SIGNALduino_StartInit', $hash, 0);
    SIGNALduino_StartInit($hash);
  }
}


############################# package main
# Check if the 1% limit is reached and trigger notifies
sub SIGNALduino_XmitLimitCheck {
  my ($hash,$fn) = @_;

  return if ($fn !~ m/^(is|S[RCM]).*/);

  my $now = time();

  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).
    my $name = $hash->{NAME};
    $hash->{logMethod}->($name, 2, "$name: XmitLimitCheck, TRANSMIT LIMIT EXCEEDED");
    DoTrigger($name, 'TRANSMIT LIMIT EXCEEDED');
  } else {
    push(@b, $now);
  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

############################# package main
## API to logical modules: Provide as Hash of IO Device, type of function ; command to call ; message to send
sub SIGNALduino_Write {
  my $hash  = shift // carp 'must be called with hash of iodevice as first param';
  my $fn  = shift // 'RAW';
  my $msg = shift // return;
  my $name = $hash->{NAME};

  if ($fn eq '') {
    $fn='RAW' ;
  } elsif($fn eq '04') {
    my $id;
    my $sum;
    $fn='sendMsg';
    if (substr($msg,0,6) eq '010101') {             # FS20
      $msg = substr($msg,6);
      $id   = 74;
      $sum  = 6;
    } elsif(substr($msg,0,6) eq '020183') {         # FHT
    $msg = substr($msg,6,4) . substr($msg,10);
      $id   = 73;
      $sum  = 12;
    }
    $msg = $hash->{protocolObject}->PreparingSend_FS20_FHT($id, $sum, $msg);
  } elsif($fn eq 'k') {   # KOPP_FC   (one part outsourcing in SD_Protocols.pm, main part here due to loop and set hash values)
    $hash->{logMethod}->($name, 4, "$name: Write, cmd $fn sending KOPP_FC");
    $fn='raw';

    my $Keycode = substr($msg,1,2);
    my $TransCode1 = substr($msg,3,4);
    my $TransCode2 = substr($msg,7,2);

    ### The device to be sent stores something in own hash. Search for names to access them ###
    #### The variant with devspec2array does not require any adjustment in the original Kopp module. ####

    my @Liste = devspec2array("TYPE=KOPP_FC:FILTER=TRANSMITTERCODE1=$TransCode1:FILTER=TRANSMITTERCODE2=$TransCode2:FILTER=KEYCODE=$Keycode");
    my $KOPPname = $Liste[0];

    if (scalar @Liste != 1) {
      $hash->{logMethod}->($name, 4, "$name: Write, PreparingSend KOPP_FC found ". scalar @Liste ." device\'s with same DEF (SIGNALduino used $KOPPname)");
    } else {
      $hash->{logMethod}->($name, 5, "$name: Write, PreparingSend KOPP_FC found device with name $KOPPname");
    }

    ## Internals blkctr initialize if not available
    if (!exists($defs{$KOPPname}->{blkctr})) {
      $defs{$KOPPname}->{blkctr} = 0;
      $hash->{logMethod}->($name, 5, "$name: Write, PreparingSend KOPP_FC set Internals blkctr on device $KOPPname to 0");
    }

    $msg = $hash->{protocolObject}->PreparingSend_KOPP_FC(sprintf("%02x",$defs{$KOPPname}->{blkctr}),$Keycode,$TransCode1,$TransCode2);

    if (!defined $msg) {
      return;
    };

    $defs{$KOPPname}->{blkctr}++;                        # Internals blkctr increases with each send
    $hash->{logMethod}->($name, 5, "$name: Write, PreparingSend KOPP_FC set Internals blkctr on device $KOPPname to ".$defs{$KOPPname}->{blkctr});
  }
  $hash->{logMethod}->($name, 5, "$name: Write, sending via Set $fn $msg");

  SIGNALduino_Set($hash,$name,$fn,$msg);
}

############################# package main
sub SIGNALduino_AddSendQueue {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  push(@{$hash->{QUEUE}}, $msg);

  #SIGNALduino_Log3 $hash , 5, Dumper($hash->{QUEUE});

  $hash->{logMethod}->($hash, 5,"$name: AddSendQueue, " . $hash->{NAME} . ": $msg (" . @{$hash->{QUEUE}} . ')');
  FHEM::Core::Timer::Helper::addTimer($name,scalar gettimeofday(), \&SIGNALduino_HandleWriteQueue, "HandleWriteQueue:$name") if (scalar @{$hash->{QUEUE}} == 1 && InternalVal($name,'sendworking',0) == 0);
}

############################# package main, test exists
sub SIGNALduino_SendFromQueue {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  $hash->{logMethod}->($name, 4, "$name: SendFromQueue, called");
  if($msg ne '') {
    SIGNALduino_XmitLimitCheck($hash,$msg);
    #DevIo_SimpleWrite($hash, $msg . "\n", 2);
    $hash->{sendworking} = 1;
    SIGNALduino_SimpleWrite($hash,$msg);
    if ($msg =~ m/^S[RCMN];/) {
        $hash->{ucCmd}->{cmd} = 'sendraw';
        $hash->{ucCmd}->{timenow} = time();
        $hash->{ucCmd}->{responseSub} = \&SIGNALduino_CheckSendRawResponse;
        $hash->{logMethod}->($name, 4, "$name: SendFromQueue, msg=$msg");   # zu testen der Queue, kann wenn es funktioniert auskommentiert werden
    } elsif ($msg =~ "^e") {                                                # Werkseinstellungen
      SIGNALduino_Get($hash,$name,'ccconf');
      SIGNALduino_Get($hash,$name,'ccpatable');

      ## set rfmode to default from uC
      my $rfmode = AttrVal($name, 'rfmode', undef);
      CommandAttr($hash,"$name rfmode SlowRF") if (defined $rfmode && $rfmode ne 'SlowRF');  # option with save question mark

    } elsif ($msg =~ "^W(?:0F|10|11|1D|12|17|1F)") {                        # SetFreq, setrAmpl, Set_bWidth, SetDeviatn, SetSens
      SIGNALduino_Get($hash,$name,'ccconf');
    } elsif ($msg =~ "^x") {                                                # patable
      SIGNALduino_Get($hash,$name,'ccpatable'); 
    }
#    elsif ($msg eq 'C99') {
#       $hash->{ucCmd}->{cmd} = 'ccregAll';
#       $hash->{ucCmd}->{responseSub} = \&SIGNALduino_CheckCcregResponse;
#
#    }
  }

  ##############
  # Write the next buffer not earlier than 0.23 seconds
  # else it will be sent too early by the SIGNALduino, resulting in a collision, or may the last command is not finished

  if (defined($hash->{ucCmd}->{cmd}) && $hash->{ucCmd}->{cmd} eq 'sendraw') {
     FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_WRITEQUEUE_TIMEOUT, \&SIGNALduino_HandleWriteQueue, "HandleWriteQueue:$name");
  } else {
     FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_WRITEQUEUE_NEXT, \&SIGNALduino_HandleWriteQueue, "HandleWriteQueue:$name");
  }
}

############################# package main
sub SIGNALduino_HandleWriteQueue {
  my($param) = @_;
  my(undef,$name) = split(':', $param);
  my $hash = $defs{$name};

  #my @arr = @{$hash->{QUEUE}};

  $hash->{logMethod}->($name, 4, "$name: HandleWriteQueue, called");
  $hash->{sendworking} = 0;       # es wurde gesendet

  if (exists($hash->{ucCmd}) && exists($hash->{ucCmd}->{cmd}) && $hash->{ucCmd}->{cmd} eq 'sendraw') {
    $hash->{logMethod}->($name, 4, "$name: HandleWriteQueue, sendraw no answer (timeout)");
    delete($hash->{ucCmd});
  }

  if(exists($hash->{QUEUE}) && @{$hash->{QUEUE}}) {
    my $msg= shift(@{$hash->{QUEUE}});

    if($msg eq '') {
      SIGNALduino_HandleWriteQueue("x:$name");
    } else {
      SIGNALduino_SendFromQueue($hash, $msg);
    }
  } else {
     $hash->{logMethod}->($name, 4, "$name: HandleWriteQueue, nothing to send, stopping timer");
     FHEM::Core::Timer::Helper::removeTimer($name, \&SIGNALduino_HandleWriteQueue , "HandleWriteQueue:$name");
  }
}

############################# package main, test exists
# called from the global loop, when the select for hash->{FD} reports data
sub SIGNALduino_Read {
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return '' if(!defined($buf));
  my $name = $hash->{NAME};
  my $debug = AttrVal($name,'debug',0);

  my $SIGNALduinodata = $hash->{PARTIAL};
  $hash->{logMethod}->($name, 5, "$name: Read, RAW: $SIGNALduinodata/$buf") if ($debug);
  $SIGNALduinodata .= $buf;

  while($SIGNALduinodata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$SIGNALduinodata) = split("\n", $SIGNALduinodata, 2);
    $rmsg =~ s/\r//;

    if ($rmsg =~ m/^\002(M(s|u|o);.*;)\003/) {
      $rmsg =~ s/^\002//;                         # \002 am Anfang entfernen
      my @msg_parts = split(';',$rmsg);
      my $m0;
      my $mnr0;
      my $m1;
      my $mL;
      my $mH;
      my $part = '';
      my $partD;
      $hash->{logMethod}->($name, 5, "$name: Read, RAW rmsg: $rmsg");

      foreach my $msgPart (@msg_parts) {
        next if ($msgPart eq '');
        $m0 = substr($msgPart,0,1);
        $mnr0 = ord($m0);
        $m1 = substr($msgPart,1);
        if ($m0 eq 'M') {
          $part .= 'M' . uc($m1) . ';';
        }
        elsif ($mnr0 > 127) {
          $part .= 'P' . sprintf("%u", ($mnr0 & 7)) . '=';
          if (length($m1) == 2) {
            $mL = ord(substr($m1,0,1)) & 127;        # Pattern low
            $mH = ord(substr($m1,1,1)) & 127;        # Pattern high
            if (($mnr0 & 0b00100000) != 0) {         # Vorzeichen  0b00100000 = 32
              $part .= '-';
            }
            if ($mnr0 & 0b00010000) {                # Bit 7 von Pattern low
              $mL += 128;
            }
            $part .= ($mH * 256) + $mL;
          }
          $part .= ';';
        }
        elsif (($m0 eq 'D' || $m0 eq 'd') && length($m1) > 0) {
          my @arrayD = split(//, $m1);
          $part .= 'D=';
          $partD = '';
          foreach my $D (@arrayD) {
            $mH = ord($D) >> 4;
            $mL = ord($D) & 7;
            $partD .= "$mH$mL";
          }
          #SIGNALduino_Log3 $name, 3, "$name: Read, msg READredu1$m0: $partD";
          if ($m0 eq 'd') {
            $partD =~ s/.$//;    # letzte Ziffer entfernen wenn Anzahl der Ziffern ungerade
          }
          $partD =~ s/^8//;            # 8 am Anfang entfernen
          #SIGNALduino_Log3 $name, 3, "$name: Read, msg READredu2$m0: $partD";
          $part = $part . $partD . ';';
        }
        elsif (($m0 eq 'C' || $m0 eq 'S') && length($m1) == 1) {
          $part .= "$m0" . "P=$m1;";
        }
        elsif ($m0 eq 'o' || $m0 eq 'm') {
          $part .= "$m0$m1;";
        }
        elsif ($m1 =~ m/^[0-9A-Z]{1,2}$/) {        # bei 1 oder 2 Hex Ziffern nach Dez wandeln
          $part .= "$m0=" . hex($m1) . ';';
        }
        elsif ($m0 =~m/[0-9a-zA-Z]/) {
          $part .= "$m0";
          if ($m1 ne '') {
            $part .= "=$m1";
          }
          $part .= ';';
        }
      }
      $hash->{logMethod}->($name, 4, "$name: Read, msg READredu: $part");
      $rmsg = "\002$part\003";
    }
    else {
      $hash->{logMethod}->($name, 4, "$name: Read, msg: $rmsg");
    }

    if ( $rmsg && !SIGNALduino_Parse($hash, $hash, $name, $rmsg) && exists($hash->{ucCmd}) && defined($hash->{ucCmd}->{cmd}))
    {
      my $regexp = exists($gets{$hash->{ucCmd}->{cmd}}) && exists($gets{$hash->{ucCmd}->{cmd}}[4]) ? $gets{$hash->{ucCmd}->{cmd}}[4] : ".*";
      if (exists($hash->{ucCmd}->{responseSub}) && ref $hash->{ucCmd}->{responseSub} eq 'CODE') {
        $hash->{logMethod}->($name, 5, "$name: Read, msg: regexp=$regexp cmd=$hash->{ucCmd}->{cmd} msg=$rmsg");
        my $returnMessage ;
        my $event;
        if (!exists($gets{$hash->{ucCmd}->{cmd}}) || !exists($gets{$hash->{ucCmd}->{cmd}}[4]) || $rmsg =~ /$regexp/)
        {
          ($returnMessage,$event) = $hash->{ucCmd}->{responseSub}->($hash,$rmsg) ;
          readingsSingleUpdate($hash, $hash->{ucCmd}->{cmd}, $returnMessage, $event) if (defined($returnMessage) && defined($event));
          if (exists($hash->{ucCmd}->{asyncOut})) {
            $hash->{logMethod}->($name, 5, "$name: Read, try asyncOutput of message $returnMessage");
            my $ao = undef;
            $ao = asyncOutput( $hash->{ucCmd}->{asyncOut}, $hash->{ucCmd}->{cmd}.': ' . $returnMessage ) if (defined($returnMessage));
            $hash->{logMethod}->($name, 5, "$name: Read, asyncOutput failed $ao") if (defined($ao));
          }
          if ( exists $hash->{ucCmd} && defined $hash->{ucCmd}->{cmd} &&  $hash->{ucCmd}->{cmd} ne "sendraw" ) {
            delete $hash->{ucCmd} ;
          }
        }

        if (exists($hash->{keepalive})) {
          $hash->{keepalive}{ok}    = 1;
          $hash->{keepalive}{retry} = 0;
        }
      } else {
        $hash->{logMethod}->($name, 4, "$name: Read, msg: Received answer ($rmsg) for ". $hash->{ucCmd}->{cmd}." does not match $regexp / coderef");
      }
    }
  }
  $hash->{PARTIAL} = $SIGNALduinodata;
}

############################# package main
sub SIGNALduino_KeepAlive{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if ($hash->{DevState} eq 'disconnected');

  #SIGNALduino_Log3 $name,4 , "$name: KeepAliveOk, " . $hash->{keepalive}{ok};
  if (!$hash->{keepalive}{ok}) {
    delete($hash->{ucCmd});
    if ($hash->{keepalive}{retry} >= SDUINO_KEEPALIVE_MAXRETRY) {
      $hash->{logMethod}->($name,3 , "$name: KeepAlive, not ok, retry count reached. Reset");
      $hash->{DevState} = 'INACTIVE';
      SIGNALduino_ResetDevice($hash);
      return;
    }
    else {
      my $logLevel = 3;
      $hash->{keepalive}{retry} ++;
      if ($hash->{keepalive}{retry} == 1) {
        $logLevel = 4;
      }
      $hash->{logMethod}->($name, $logLevel, "$name: KeepAlive, not ok, retry = " . $hash->{keepalive}{retry} . ' -> get ping');
      $hash->{ucCmd}->{cmd} = 'ping';
      $hash->{ucCmd}->{timenow} = time();
      $hash->{ucCmd}->{responseSub} = \&SIGNALduino_GetResponseUpdateReading;
      SIGNALduino_AddSendQueue($hash, 'P');
    }
  }
  else {
    $hash->{logMethod}->($name,4 , "$name: KeepAlive, ok, retry = " . $hash->{keepalive}{retry});
  }
  $hash->{keepalive}{ok} = 0;

  FHEM::Core::Timer::Helper::addTimer($name, gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, \&SIGNALduino_KeepAlive, $hash);
}


### Helper Subs >>>

############################# package main
## Parses a HTTP Response for example for flash via http download
sub SIGNALduino_ParseHttpResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if($err ne '')                                              # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
  {
    $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, error while requesting ".$param->{url}." - $err");                  # Eintrag fuers Log
  }
  elsif($param->{code} eq '200' && $data ne '')               # wenn die Abfrage erfolgreich war ($data enthaelt die Ergebnisdaten des HTTP Aufrufes)
    {
      $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, url ".$param->{url}.' returned: '.length($data).' bytes Data');   # Eintrag fuers Log

      if ($param->{command} eq 'flash')
      {
        my $filename;

        if ($param->{httpheader} =~ /Content-Disposition: attachment;.?filename=\"?([-+.\w]+)?\"?/)
        {
          $filename = $1;
        } else {  # Filename via path if not specifyied via Content-Disposition
          $param->{path} =~ /\/([-+.\w]+)$/;    #(?:[^\/][\d\w\.]+)+$   \/([-+.\w]+)$         
          $filename = $1;
        }
        $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, Downloaded $filename firmware from ".$param->{host});
        $hash->{logMethod}->($name, 5, "$name: ParseHttpResponse, Header = ".$param->{httpheader});

        $filename = 'FHEM/firmware/' . $filename;
        open(my $file, '>', $filename) or die $!;
        print $file $data;
        close $file;

        # Den Flash Befehl mit der soebene heruntergeladenen Datei ausfuehren
        #SIGNALduino_Log3 $name, 3, "$name: ParseHttpResponse, calling set ".$param->{command}." $filename";        # Eintrag fuers Log

        my $set_return = SIGNALduino_Set($hash,$name,$param->{command},$filename); # $hash->{SetFn}
        if (defined($set_return))
        {
          $hash->{logMethod}->($name ,3, "$name: ParseHttpResponse, Error while flashing: $set_return");
        }
      }
    } else {
      $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, undefined error while requesting ".$param->{url}." - $err - code=".$param->{code});   # Eintrag fuers Log
    }
}

############################# package main
sub SIGNALduino_splitMsg {
  my $txt = shift;
  my $delim = shift;
  my @msg_parts = split(/$delim/,$txt);

  return @msg_parts;
}

############################# package main
# $value  - $set <= $tolerance
sub SIGNALduino_inTol {
  #Debug "sduino abs \($_[0] - $_[1]\) <= $_[2] ";
  return (abs($_[0]-$_[1])<=$_[2]);
}


############################# package main
# =item SIGNALduino_FillPatternLookupTable()
#
# Retruns 1 on success or 0 if symbol was not found

sub SIGNALduino_FillPatternLookupTable {
  my ($hash,$symbol,$representation,$patternList,$rawData,$patternLookupHash,$endPatternLookupHash,$rtext) = @_;
  my $pstr=undef;
  if (($pstr=SIGNALduino_PatternExists($hash, $symbol,$patternList,$rawData)) >=0) {
    ${$rtext} = $pstr;
    $patternLookupHash->{$pstr}=${$representation};    ## Append to lookuptable
    chop $pstr;
    $endPatternLookupHash->{$pstr} = ${$representation} if (!exists($endPatternLookupHash->{$pstr})); ## Append shortened string to lookuptable
    return 1;
  } else {
    ${$rtext} = '';
    return 0;
  }
}


############################# package main
#=item SIGNALduino_PatternExists()
# This functons, needs reference to $hash, @array of values to search and %patternList where to find the matches.
#
# Will return -1 if pattern is not found or a string, containing the indexes which are in tolerance and have the smallest gap to what we searched
# =cut

# 01232323242423       while ($message =~ /$pstr/g) { $count++ }

sub SIGNALduino_PatternExists {
  my ($hash,$search,$patternList,$data) = @_;
  #my %patternList=$arg3;
  #Debug 'plist: '.Dumper($patternList) if($debug);
  #Debug 'searchlist: '.Dumper($search) if($debug);

  my $debug = AttrVal($hash->{NAME},'debug',0);
  my $i=0;
  my @indexer;
  my @sumlist;
  my %plist=();

  for my $searchpattern (@{$search})    # z.B. [1, -4]
  {
    next if (exists $plist{$searchpattern});

    # Calculate tolernace for search
    #my $tol=abs(abs($searchpattern)>=2 ?$searchpattern*0.3:$searchpattern*1.5);
    my $tol=abs(abs($searchpattern)>3 ? abs($searchpattern)>16 ? $searchpattern*0.18 : $searchpattern*0.3 : 1);  #tol is minimum 1 or higer, depending on our searched pulselengh

    Debug "tol: looking for ($searchpattern +- $tol)" if($debug);

    my %pattern_gap ; #= {};
    # Find and store the gap of every pattern, which is in tolerance
    %pattern_gap = map { $_ => abs($patternList->{$_}-$searchpattern) } grep { abs($patternList->{$_}-$searchpattern) <= $tol} (keys %$patternList);
    if (scalar keys %pattern_gap > 0)
    {
      Debug "index => gap in tol (+- $tol) of pulse ($searchpattern) : ".Dumper(\%pattern_gap) if($debug);
      # Extract fist pattern, which is nearst to our searched value
      my @closestidx = (sort {$pattern_gap{$a} <=> $pattern_gap{$b}} keys %pattern_gap);

      $plist{$searchpattern} = 1;
      push @indexer, $searchpattern; 
      push @sumlist, [@closestidx];  
    } else {
      # search is not found, return -1
      return -1;
    }
    $i++;
  }

  sub cartesian_product { ## no critic
    use List::Util qw(reduce);
    reduce {
      [ map {
        my $item = $_;
        map [ @$_, $item ], @$a
      } @$b ]
    } [[]], @_
  }
  my @res = cartesian_product @sumlist;
  Debug qq[sumlists is: ].Dumper @sumlist if($debug);
  Debug qq[res is: ].Dumper $res[0] if($debug);
  Debug qq[indexer is: ].Dumper \@indexer if($debug);

  OUTERLOOP:
  for my $i (0..$#{$res[0]})
  {

    ## Check if we have same patternindex for different values and skip this invalid ones
    my %count;  
    for (@{$res[0][$i]}) 
    { 
      $count{$_}++; 
      next OUTERLOOP if ($count{$_} > 1)
    };
    
    # Create a mapping table to exchange the values later on
    for (my $x=0;$x <= $#indexer;$x++)
    {
      $plist{$indexer[$x]}  = $res[0][$i][$x]; 
    }
    Debug qq[plist is for this check ].Dumper(\%plist) if($debug);

    # Create our searchstring with our mapping table
    my @patternVariant= @{$search};
    for my $v (@patternVariant)
    {
      #Debug qq[value before is: $v ] if($debug);
      $v = $plist{$v};
      #Debug qq[after: $v ] if($debug);
    }
    Debug qq[patternVariant is ].Dumper(\@patternVariant) if($debug);
    my $search_pattern = join '', @patternVariant;

    (index ($$data, $search_pattern) > -1) ? return $search_pattern : next;
  }

  return -1;
}

############################# package main
#SIGNALduino_MatchSignalPattern{$hash,@array, %hash, @array, $scalar}; not used >v3.1.3
sub SIGNALduino_MatchSignalPattern($\@\%\@$){
  my ( $hash, $signalpattern,  $patternList,  $data_array, $idx) = @_;
    my $name = $hash->{NAME};
  #print Dumper($patternList);
  #print Dumper($idx);
  #Debug Dumper($signalpattern) if ($debug);
  my $tol='0.2';   # Tolerance factor
  my $found=0;
  my $debug = AttrVal($hash->{NAME},'debug',0);

  foreach ( @{$signalpattern} )
  {
    #Debug " $idx check: ".$patternList->{$data_array->[$idx]}." == ".$_;
    Debug "$name: idx: $idx check: abs(". $patternList->{$data_array->[$idx]}.' - '.$_.') > '. ceil(abs($patternList->{$data_array->[$idx]}*$tol)) if ($debug);

    #print "\n";;
    #if ($patternList->{$data_array->[$idx]} ne $_ )
    ### Nachkommastelle von ceil!!!
    if (!defined( $patternList->{$data_array->[$idx]})){
      Debug "$name: Error index ($idx) does not exist!!" if ($debug);

      return -1;
    }
    if (abs($patternList->{$data_array->[$idx]} - $_)  > ceil(abs($patternList->{$data_array->[$idx]}*$tol)))
    {
      return -1;    ## Pattern does not match, return -1 = not matched
    }
    $found=1;
    $idx++;
  }
  if ($found)
  {
    return $idx;    ## Return new Index Position
  }
}

############################# package main
sub SIGNALduino_Split_Message {
  my $rmsg = shift;
  my $name = shift;
  my %patternList;
  my $clockidx;
  my $syncidx;
  my $rawData;
  my $clockabs;
  my $mcbitnum;
  my $rssi;

  my @msg_parts = SIGNALduino_splitMsg($rmsg,';');      ## Split message parts by ';'
  my %ret;
  my $debug = AttrVal($name,'debug',0);

  foreach (@msg_parts)
  {
    #Debug "$name: checking msg part:( $_ )" if ($debug);

    #if ($_ =~ m/^MS/ or $_ =~ m/^MC/ or $_ =~ m/^Mc/ or $_ =~ m/^MU/)  #### Synced Message start
    if ($_ =~ m/^M./)
    {
      $ret{messagetype} = $_;
    }
    elsif ($_ =~ m/^P\d=-?\d{2,}/ or $_ =~ m/^[SL][LH]=-?\d{2,}/) #### Extract Pattern List from array
    {
       $_ =~ s/^P+//;
       $_ =~ s/^P\d//;
       my @pattern = split(/=/,$_);

       $patternList{$pattern[0]} = $pattern[1];
       Debug "$name: extracted  pattern @pattern \n" if ($debug);
    }
    elsif($_ =~ m/D=\d+/ or $_ =~ m/^D=[A-F0-9]+/)                #### Message from array
    {
      $_ =~ s/D=//;
      $rawData = $_ ;
      Debug "$name: extracted  data $rawData\n" if ($debug);
      $ret{rawData} = $rawData;
    }
    elsif($_ =~ m/^SP=([0-9])$/)                                     #### Sync Pulse Index
    {
      Debug "$name: extracted  syncidx $1\n" if ($debug);
      #return undef if (!defined($patternList{$syncidx}));
      $ret{syncidx} = $1;
    }
    elsif($_ =~ m/^CP=([0-9])$/)                                     #### Clock Pulse Index
    {
      Debug "$name: extracted  clockidx $1\n" if ($debug);;
      $ret{clockidx} = $1;
    }
    elsif($_ =~ m/^L=\d/)                                         #### MC bit length
    {
      (undef, $mcbitnum) = split(/=/,$_);
      Debug "$name: extracted  number of $mcbitnum bits\n" if ($debug);;
      $ret{mcbitnum} = $mcbitnum;
    }
    elsif($_ =~ m/^C=\d+/)                                        #### Message from array
    {
      $_ =~ s/C=//;
      $clockabs = $_ ;
      Debug "$name: extracted absolute clock $clockabs \n" if ($debug);
      $ret{clockabs} = $clockabs;
    }
    elsif($_ =~ m/^R=\d+/)                                        #### RSSI
    {
      $_ =~ s/R=//;
      $rssi = $_ ;
      Debug "$name: extracted RSSI $rssi \n" if ($debug);
      $ret{rssi} = $rssi;
    }  else {
      Debug "$name: unknown Message part $_" if ($debug);;
    }
    #print "$_\n";
  }
  $ret{pattern} = {%patternList};
  return %ret;
}

############################# package main, test exists
# Function which dispatches a message if needed.
sub SIGNALduno_Dispatch {
  my ($hash, $rmsg, $dmsg, $rssi, $id) = @_;
  my $name = $hash->{NAME};

  if (!defined($dmsg))
  {
    $hash->{logMethod}->($name, 5, "$name: Dispatch, dmsg is undef. Skipping dispatch call");
    return;
  }

  #SIGNALduino_Log3 $name, 5, "$name: Dispatch, DMSG: $dmsg";

  my $DMSGgleich = 1;
  if ($dmsg eq $hash->{LASTDMSG}) {
    $hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, test gleich");
  } else {
    if ( defined $hash->{DoubleMsgIDs}{$id} ) {
      $DMSGgleich = 0;
      $hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, test ungleich");
    } else {
      $hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, test ungleich: disabled");
    }
    $hash->{LASTDMSG} = $dmsg;
    $hash->{LASTDMSGID} = $id;
  }

  if ($DMSGgleich) {
    #Dispatch if dispatchequals is provided in protocol definition or only if $dmsg is different from last $dmsg, or if 2 seconds are between transmits
    if (  ( $hash->{protocolObject}->checkProperty($id,'dispatchequals','false') eq 'true') 
        || ($hash->{DMSG} ne $dmsg) 
        || ($hash->{TIME}+2 < time() )  )
    {
      $hash->{MSGCNT}++;
      $hash->{TIME} = time();
      $hash->{DMSG} = $dmsg;
      #my $event = 0;
      if (substr(ucfirst($dmsg),0,1) eq 'U') { # u oder U
        #$event = 1;
        DoTrigger($name, 'DMSG ' . $dmsg);
        return if (substr($dmsg,0,1) eq 'U'); # Fuer $dmsg die mit U anfangen ist kein Dispatch notwendig, da es dafuer kein Modul gibt klein u wird dagegen dispatcht
      }
      #readingsSingleUpdate($hash, 'state', $hash->{READINGS}{state}{VAL}, $event);

      $hash->{RAWMSG} = $rmsg;
      my %addvals = (
        DMSG => $dmsg,
        Protocol_ID => $id
      );
      if (AttrVal($name,'suppressDeviceRawmsg',0) == 0) {
        $addvals{RAWMSG} = $rmsg
      }
      if(defined($rssi)) {
        $hash->{RSSI} = $rssi;
        $addvals{RSSI} = $rssi;
        $rssi .= ' dB,'
      }
      else {
        $rssi = '';
      }
      $dmsg = lc($dmsg) if ($id eq '74' or $id eq '74.1');    # 10_FS20.pm accepted only lower case hex
      $hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, $rssi dispatch");
      Dispatch($hash, $dmsg, \%addvals);  ## Dispatch to other Modules

    } else {
      $hash->{logMethod}->($name, 4, "$name: Dispatch, $dmsg, Dropped due to short time or equal msg");
    }
  }
}

############################# package main  todo: move to lib::SD_Protocols
# param #1 is name of definition
# param #2 is protocol id
# param #3 is dispatched message to check against
#
# returns 1 if message matches modulematch + development attribute/whitelistIDs
# returns 0 if message does not match modulematch
# return -1 if message is not activated via whitelistIDs but has developID=m flag
sub SIGNALduino_moduleMatch {
  my $name = shift // carp q[arg name must be provided];
  my $id = shift;
  my $dmsg = shift;
  my $debug = AttrVal($name,'debug',0);
  my $hash = $defs{$name} // carp q[$name does not exist];
  my $modMatchRegex=$hash->{protocolObject}->checkProperty($id,'modulematch',undef);

  if (!defined($modMatchRegex) || $dmsg =~ m/$modMatchRegex/) {
    Debug "$name: modmatch passed for: $dmsg" if ($debug);
    my $developID = $hash->{protocolObject}->checkProperty($id,'developId','');
    my $IDsNoDispatch = ',' . InternalVal($name,'IDsNoDispatch','') . ',';
    if ($IDsNoDispatch ne ',,' && index($IDsNoDispatch, ",$id,") >= 0) {  # kein dispatch wenn die Id im Internal IDsNoDispatch steht
      Log3 $name, 3, "$name: moduleMatch, ID=$id skipped dispatch (developId=m). To use, please add $id to the attr whitelist_IDs";
      return -1;
    }
    return 1; #   return 1 da modulematch gefunden wurde
  }
  return 0;
}

############################# package main, test exists
# calculated RSSI and RSSI value and RSSI string (-77,'RSSI = -77')
sub SIGNALduino_calcRSSI {
  my $rssi = shift // return ;
  my $rssiStr = '';
  $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
  $rssiStr = "RSSI = $rssi";
  return ($rssi,$rssiStr);
}




=item SIGNALduino_Parse_MS

This sub parses a MS rawdata string and dispatches it if a protocol matched the cirteria.

Input:  $iohash, $rawMessage 

Output: { Number of times dispatch was called, 0 if dispatch isn't called }

=cut
############################# package main

sub SIGNALduino_Parse_MS {
  my $hash = shift // return;    #return if no hash  is provided
  my $rmsg = shift // return;    #return if no rmsg is provided

  if ($rmsg !~ /^MS;(?:P[0-7]=-?\d+;){3,8}D=[0-7]+;(?:[CS]P=[0-7];){2}((?:R=\d+;)|(?:O;)?|(?:m=?[0-9];)|(?:[sbeECA=0-9]+;))*$/){   
    $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MS, faulty msg: $rmsg]);
    return ; # Abort here if not successfull
  }

  # Extract Data from rmsg:
  my %msg_parts = SIGNALduino_Split_Message($rmsg, $hash->{NAME});

  # Verify if extracted hash has the correct values:
  my $clockidx = _limit_to_number($msg_parts{clockidx}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MS, faulty clock: $msg_parts{clockidx}]) // return ;
  my $syncidx  = _limit_to_number($msg_parts{syncidx})  // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MS, faulty sync: $msg_parts{syncidx}]) // return ;
  my $rawData  = _limit_to_number($msg_parts{rawData})  // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MS, faulty rawData D=: $msg_parts{rawData}]) // return ;
  my $rssi;
  my $rssiStr= '';
  if ( defined $msg_parts{rssi} ){
     $rssi = _limit_to_number($msg_parts{rssi}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MS, faulty rssi R=: $msg_parts{rssi}]) // return ;
    ($rssi,$rssiStr) = SIGNALduino_calcRSSI($rssi);
  };
  my $messagetype=$msg_parts{messagetype};
  my $name = $hash->{NAME};

  my %patternList;

  #Debug 'Message splitted:';
  #Debug Dumper(\@msg_parts);

  my $debug = AttrVal($hash->{NAME},'debug',0);

  if (defined($clockidx) and defined($syncidx))
  {
    ## Make a lookup table for our pattern index ids
    #Debug 'List of pattern:';
    my $clockabs= $msg_parts{pattern}{$msg_parts{clockidx}};
    return if ($clockabs == 0);
    $patternList{$_} = round($msg_parts{pattern}{$_}/$clockabs,1) for keys %{$msg_parts{pattern}};

    #Debug Dumper(\%patternList);

    #my $syncfact = $patternList{$syncidx}/$patternList{$clockidx};
    #$syncfact=$patternList{$syncidx};
    #Debug 'SF=$syncfact';
    #### Convert rawData in Message
    my $signal_length = length($rawData);        # Length of data array

    ## Iterate over the data_array and find zero, one, float and sync bits with the signalpattern
    ## Find matching protocols
    my $message_dispatched=0;

    IDLOOP:
    foreach my $id (@{$hash->{msIdList}}) {

      Debug qq[Testing against protocol id $id -> ].$hash->{protocolObject}->getProperty($id,'name')  if ($debug);

      # Check Clock if is it in range
      if ($hash->{protocolObject}->checkProperty($id,'clockabs',0) > 0) {
        if (!SIGNALduino_inTol($hash->{protocolObject}->getProperty($id,'clockabs'),$clockabs,$clockabs*0.30)) {
          Debug qq[protocClock=].$hash->{protocolObject}->getProperty($id,'clockabs').qq[, msgClock=$clockabs is not in tol=].$clockabs*0.30 if ($debug);
          next;
        } elsif ($debug) {
          Debug qq[protocClock=].$hash->{protocolObject}->getProperty($id,'clockabs').qq[, msgClock=$clockabs is in tol="] . $clockabs*0.30;
        }
      }

      Debug 'Searching in patternList: '.Dumper(\%patternList) if($debug);

      my %patternLookupHash=();
      my %endPatternLookupHash=();
      my $signal_width= @{$hash->{protocolObject}->getProperty($id,'one')};
      my $return_text;
      my $message_start;
      foreach my $key (qw(sync one zero float) ) {
        next if (!defined($hash->{protocolObject}->getProperty($id,$key)));

        if (!SIGNALduino_FillPatternLookupTable($hash,\@{$hash->{protocolObject}->getProperty($id,$key)},\$symbol_map{$key},\%patternList,\$rawData,\%patternLookupHash,\%endPatternLookupHash,\$return_text))
        {
          Debug sprintf("%s pattern not found",$key) if ($debug);
          next IDLOOP if ($key ne 'float') ;
        }

        if ($key eq 'sync')
        {
          $message_start =index($rawData,$return_text)+length($return_text);
          my $bit_length = ($signal_length-$message_start) / $signal_width;
          if ($hash->{protocolObject}->checkProperty($id,'length_min',-1) > $bit_length) {
            Debug "bit_length=$bit_length to short" if ($debug);
            next IDLOOP;
          }
          Debug "expecting $bit_length bits in signal" if ($debug);
          %endPatternLookupHash=();
        }
        Debug sprintf("Found matched %s with indexes: (%s)",$key,$return_text) if ($debug);
      }
      next if (scalar keys %patternLookupHash == 0);  # Keine Eingträge im patternLookupHash

      $hash->{logMethod}->($name, 4, qq[$name: Parse_MS, Matched MS protocol id $id -> ].$hash->{protocolObject}->getProperty($id,'name'));
      my @bit_msg;              # array to store decoded signal bits
      $hash->{logMethod}->($name, 5, qq[$name: Parse_MS, Starting demodulation at Position $message_start]);
      for (my $i=$message_start;$i<length($rawData);$i+=$signal_width)
      {
        my $sigStr= substr($rawData,$i,$signal_width);
        #SIGNALduino_Log3 $name, 5, "$name: Parse_MS, demodulating $sigStr";
        #Debug $patternLookupHash{substr($rawData,$i,$signal_width)}; ## Get $signal_width number of chars from raw data string
        if (exists $patternLookupHash{$sigStr}) { ## Add the bits to our bit array
          push(@bit_msg,$patternLookupHash{$sigStr}) if ($patternLookupHash{$sigStr} ne '');
        } elsif (defined($hash->{protocolObject}->getProperty($id,'reconstructBit'))) {
          if (length($sigStr) == $signal_width) {     # ist $sigStr zu lang?
            chop($sigStr);
          }
          if (exists($endPatternLookupHash{$sigStr})) {
            push(@bit_msg,$endPatternLookupHash{$sigStr});
            $hash->{logMethod}->($name, 4, "$name: Parse_MS, last part pair=$sigStr reconstructed, last bit=$endPatternLookupHash{$sigStr}");
          }
          else {
            $hash->{logMethod}->($name, 5, "$name: Parse_MS, can't reconstruct last part pair=$sigStr");
          }
          last;
        } else {
          $hash->{logMethod}->($name, 5, "$name: Parse_MS, Found wrong signalpattern $sigStr, catched ".scalar @bit_msg.' bits, aborting demodulation');
          last;
        }
      }

      Debug "$name: decoded message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);

      #Check converted message against lengths
      my ($rcode, $rtxt) = $hash->{protocolObject}->LengthInRange($id,scalar @bit_msg);
      if (!$rcode)
      {
        Debug "$name: decoded $rtxt" if ($debug);
        next;
      }
      my $padwith = $hash->{protocolObject}->checkProperty($id,'paddingbits',4);

      my $i=0;
      while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
      {
        push(@bit_msg,'0');
        $i++;
      }
      Debug "$name padded $i bits to bit_msg array" if ($debug);

      if ($i == 0) {
        $hash->{logMethod}->($name, 5, "$name: Parse_MS, dispatching bits: @bit_msg");
      } else {
        $hash->{logMethod}->($name, 5, "$name: Parse_MS, dispatching bits: @bit_msg with $i Paddingbits 0");
      }

      my $evalcheck = ($hash->{protocolObject}->checkProperty($id,'developId','') =~ 'p') ? 1 : undef;

      ($rcode,my @retvalue) = SIGNALduino_callsub($hash->{protocolObject},'postDemodulation',$hash->{protocolObject}->checkProperty($id,'postDemodulation',undef),$evalcheck,$name,@bit_msg);
      next if ($rcode < 1 );
      #SIGNALduino_Log3 $name, 5, "$name: Parse_MS, postdemodulation value @retvalue";

      @bit_msg = @retvalue;
      undef(@retvalue); undef($rcode);

      my $dmsg = lib::SD_Protocols::binStr2hexStr(join '', @bit_msg);
      my $postamble = $hash->{protocolObject}->checkProperty($id,'postamble','');
      $dmsg = $hash->{protocolObject}->checkProperty($id,'preamble','').qq[$dmsg$postamble];
      
      #my ($rcode,@retvalue) = SIGNALduino_callsub('preDispatchfunc',$ProtocolListSIGNALduino{$id}{preDispatchfunc},$name,$dmsg);
      #next if (!$rcode);
      #$dmsg = @retvalue;
      #undef(@retvalue); undef($rcode);

      if ( SIGNALduino_moduleMatch($name,$id,$dmsg) == 1)
      {
        $message_dispatched++;
        $hash->{logMethod}->($name, 4, "$name: Parse_MS, Decoded matched MS protocol id $id dmsg $dmsg length " . scalar @bit_msg . " $rssiStr");
        SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
      }
    }

    return 0 if (!$message_dispatched);
    return $message_dispatched;
  }
}

############################# package main
## //Todo: check list as reference
# // Todo: Make this sub robust and use it
sub SIGNALduino_padbits(\@$) {
  my $i=@{$_[0]} % $_[1];
  while (@{$_[0]} % $_[1] > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
  {
    push(@{$_[0]},'0');
  }
  return " padded $i bits to bit_msg array";
}

=item SIGNALduino_Parse_MU

This sub parses a MU rawdata string and dispatches it if a protocol matched the cirteria.

Input:  $iohash, $rawMessage 

Output: { Number of times dispatch was called, 0 if dispatch isn't called }

=cut

############################# package main, test exists
sub SIGNALduino_Parse_MU {
  my $hash = shift // return;    #return if no hash  is provided
  my $rmsg = shift // return;    #return if no rmsg is provided
  
  if ($rmsg !~ /^(?=.*D=\d+)(?:MU;(?:P[0-7]=-?[0-9]{1,5};){2,8}((?:D=\d{2,};)|(?:CP=\d;)|(?:R=\d+;)?|(?:O;)?|(?:e;)?|(?:p;)?|(?:w=\d;)?)*)$/){
    $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MU, faulty msg: $rmsg]);
    return ; # Abort here if not successfull
  }

  # Extract Data from rmsg:
  my %msg_parts = SIGNALduino_Split_Message($rmsg, $hash->{NAME});

  # Verify if extracted hash has the correct values:
  my $clockidx = _limit_to_number($msg_parts{clockidx}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MU, faulty clock: $rmsg]) // return ;
  my $rawData  = _limit_to_number($msg_parts{rawData})  // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MU, faulty rawData D=: $msg_parts{rawData}]) // return ;
  my $rssi;
  my $rssiStr= '';
  if ( defined $msg_parts{rssi} ){
     $rssi = _limit_to_number($msg_parts{rssi}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MU, faulty rssi R=: $msg_parts{rssi}]) // return ;
    ($rssi,$rssiStr) = SIGNALduino_calcRSSI($rssi);
  };
  my $messagetype=$msg_parts{messagetype};
  my $name = $hash->{NAME};


  my $protocolid;
  my %patternListRaw;
  my $message_dispatched=0;
  my $debug = AttrVal($hash->{NAME},'debug',0);

  Debug "$name: processing unsynced message\n" if ($debug);

  my $clockabs = 1;  #Clock will be fetched from protocol if possible
  $patternListRaw{$_} = $msg_parts{pattern}{$_} for keys %{$msg_parts{pattern}};

  if (defined($clockidx))
  {
    ## Make a lookup table for our pattern index ids
    #Debug 'List of pattern:';    #Debug Dumper(\%patternList);

    ## Find matching protocols

    IDLOOP:
    for my $id (@{$hash->{muIdList}}) {
      $clockabs= $hash->{protocolObject}->getProperty($id,'clockabs');
      my %patternList;
      $rawData=$msg_parts{rawData};
      if (defined($hash->{protocolObject}->getProperty($id,'filterfunc')))
      {
        my $method =$hash->{protocolObject}->getProperty($id,'filterfunc');
          if (!exists &$method)
        {
          $hash->{logMethod}->($name, 5, "$name: Parse_MU, Error: Unknown filtermethod=$method. Please define it in file $0");
          next;
        } else {
          $hash->{logMethod}->($name, 5, "$name: Parse_MU, for MU protocol id $id, applying filterfunc $method");

          no strict "refs"; 
          (my $count_changes,$rawData,my %patternListRaw_tmp) = $method->($name,$id,$rawData,%patternListRaw);
          use strict "refs";

          %patternList = map { $_ => round($patternListRaw_tmp{$_}/$clockabs,1) } keys %patternListRaw_tmp;
        }
      } else {
        %patternList = map { $_ => round($patternListRaw{$_}/$clockabs,1) } keys %patternListRaw;
      }

      Debug qq[Testing against protocol id $id -> ]. $hash->{protocolObject}->getProperty($id,'name')  if ($debug);
      Debug qq[Searching in patternList: ].Dumper(\%patternList) if($debug);

      my $startStr=''; # Default match if there is no start pattern available
      my $message_start=0 ;
      my $startLogStr='';

      if (defined($hash->{protocolObject}->getProperty($id,'start'))  && ref($hash->{protocolObject}->getProperty($id,'start')) eq 'ARRAY') # wenn start definiert ist, dann startStr ermitteln und in rawData suchen und in der rawData alles bis zum startStr abschneiden
      {
        Debug 'msgStartLst: '.Dumper(\@{$hash->{protocolObject}->getProperty($id,'start')}) if ($debug);

        if ( ($startStr=SIGNALduino_PatternExists($hash,\@{$hash->{protocolObject}->getProperty($id,'start')},\%patternList,\$rawData)) eq -1)
        {
          $hash->{logMethod}->($name, 5, qq[$name: Parse_MU, start pattern for MU protocol id $id -> ].$hash->{protocolObject}->getProperty($id,'name'). qq[ not found, aborting]);
          next;
        }
        Debug "startStr is: $startStr" if ($debug);
        $message_start = index($rawData, $startStr);
        if ( $message_start == -1)
        {
          Debug "startStr $startStr not found." if ($debug);
          next;
        } else {
          $rawData = substr($rawData, $message_start);
          $startLogStr = "StartStr: $startStr first found at $message_start";
          Debug "rawData = $rawData" if ($debug);
          Debug "startStr $startStr found. Message starts at $message_start" if ($debug);
          #SIGNALduino_Log3 $name, 5, "$name: Parse_MU, substr: $rawData"; # todo: entfernen
        }
      }

      my %patternLookupHash=();
      my %endPatternLookupHash=();
      my $pstr='';
      my $zeroRegex ='';
      my $oneRegex ='';
      my $floatRegex ='';
      my $return_text='';
      my $signalRegex='(?:';

      for my $key (qw(one zero float) ) {
        next if (!defined($hash->{protocolObject}->getProperty($id,$key)));
        if (!SIGNALduino_FillPatternLookupTable($hash,\@{$hash->{protocolObject}->getProperty($id,$key)},\$symbol_map{$key},\%patternList,\$rawData,\%patternLookupHash,\%endPatternLookupHash,\$return_text))
        {
          Debug sprintf("%s pattern not found",$key) if ($debug);
          next IDLOOP if ($key ne "float");
        }
        Debug sprintf("Found matched %s with indexes: (%s)",$key,$return_text) if ($debug);
        if ($key eq "one")
        {
           $signalRegex .= $return_text;
        }
        else {
          $signalRegex .= "|$return_text" if($return_text);
        }
      }
      $signalRegex .= ')';

      $hash->{logMethod}->($name, 4, qq[$name: Parse_MU, Fingerprint for MU protocol id $id -> ].$hash->{protocolObject}->getProperty($id,'name').q[ matches, trying to demodulate]);

      my $signal_width= @{$hash->{protocolObject}->getProperty($id,'one')};
      my $length_min = $hash->{protocolObject}->getProperty($id,'length_min');
      my $length_max = $hash->{protocolObject}->checkProperty($id,'length_max','');

      $signalRegex .= qq[{$length_min,}];

      if (defined($hash->{protocolObject}->getProperty($id,'reconstructBit'))) {
        $signalRegex .= '(?:' . join('|',keys %endPatternLookupHash) . ')?';
      }
      Debug "signalRegex is $signalRegex " if ($debug);

      my $nrRestart=0;
      my $nrDispatch=0;
      my $regex="(?:$startStr)($signalRegex)";

      while ( $rawData =~ m/$regex/g)   {
        my $length_str='';
        $nrRestart++;
        $hash->{logMethod}->($name, 5, qq{$name: Parse_MU, part is $1 starts at position $-[0] and ends at }.pos $rawData);

        my @pairs = unpack "(a$signal_width)*", $1;

        if ($length_max && scalar @pairs > $length_max) # ist die Nachricht zu lang?
        {
          $hash->{logMethod}->($name, 5, "$name: Parse_MU, $nrRestart. skip demodulation (length ".scalar @pairs." is to long) at Pos $-[0] regex ($regex)");
          next;
        }

        if ($nrRestart == 1) {
          $hash->{logMethod}->($name, 5, qq[$name: Parse_MU, Starting demodulation ($startLogStr regex: $regex Pos $message_start) length_min_max ($length_min..$length_max) length=].scalar @pairs);
        } else {
          $hash->{logMethod}->($name, 5, qq{$name: Parse_MU, $nrRestart. try demodulation$length_str at Pos $-[0]});
        }

        my @bit_msg=();     # array to store decoded signal bits

        for my $sigStr (@pairs)
        {
          if (exists $patternLookupHash{$sigStr}) {
            push(@bit_msg,$patternLookupHash{$sigStr})  ## Add the bits to our bit array
          } elsif (defined($hash->{protocolObject}->getProperty($id,'reconstructBit')) && exists($endPatternLookupHash{$sigStr})) {
            my $lastbit = $endPatternLookupHash{$sigStr};
            push(@bit_msg,$lastbit);
            $hash->{logMethod}->($name, 4, "$name: Parse_MU, last part pair=$sigStr reconstructed, bit=$lastbit");
          }
        }

        Debug "$name: demodulated message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);

        my $evalcheck = ($hash->{protocolObject}->checkProperty($id,'developId','') =~ 'p') ? 1 : undef;
        my ($rcode,@retvalue) = SIGNALduino_callsub($hash->{protocolObject},'postDemodulation',$hash->{protocolObject}->checkProperty($id,'postDemodulation',undef),$evalcheck,$name,@bit_msg);

        next if ($rcode < 1 );
        @bit_msg = @retvalue;
        undef(@retvalue); undef($rcode);

        my $dispmode='hex';
        $dispmode='bin' if ($hash->{protocolObject}->checkProperty($id,'dispatchBin',0) == 1 );

        my $padwith = $hash->{protocolObject}->checkProperty($id,'paddingbits',4);
        while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
        {
          push(@bit_msg,'0');
          Debug "$name: padding 0 bit to bit_msg array" if ($debug);
        }
        my $dmsg = join ('', @bit_msg);
        my $bit_length=scalar @bit_msg;
        @bit_msg=(); # clear bit_msg array

        $dmsg = lib::SD_Protocols::binStr2hexStr($dmsg) if ($hash->{protocolObject}->checkProperty($id,'dispatchBin',0) == 0 );

        $dmsg =~ s/^0+//   if (  $hash->{protocolObject}->checkProperty($id,'remove_zero',0) );

        $dmsg=sprintf("%s%s%s",$hash->{protocolObject}->checkProperty($id,'preamble',''),$dmsg,$hash->{protocolObject}->checkProperty($id,'postamble',''));
        $hash->{logMethod}->($name, 5, "$name: Parse_MU, dispatching $dispmode: $dmsg");

        if ( SIGNALduino_moduleMatch($name,$id,$dmsg) == 1)
        {
          $nrDispatch++;
          $hash->{logMethod}->($name, 4, "$name: Parse_MU, Decoded matched MU protocol id $id dmsg $dmsg length $bit_length dispatch($nrDispatch/". AttrVal($name,'maxMuMsgRepeat', 4) . ") $rssiStr");
          SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
          if ( $nrDispatch == AttrVal($name,'maxMuMsgRepeat', 4))
          {
            last;
          }
        }
      }
      $hash->{logMethod}->($name, 5, "$name: Parse_MU, $nrRestart. try, regex ($regex) did not match") if ($nrRestart == 0);
      $message_dispatched=$message_dispatched+$nrDispatch;
    }
    return $message_dispatched;
  }
}

=item SIGNALduino_Parse_MC

This sub parses a MC rawdata string and dispatches it if a protocol matched the cirteria.

Input:  $iohash, $rawMessage 

Output: { Number of times dispatch was called, 0 if dispatch isn't called }

=cut

############################# package main, test exists
sub SIGNALduino_Parse_MC {
  my $hash = shift // return;    #return if no hash  is provided
  my $rmsg = shift // return;    #return if no rmsg is provided
  
  if ($rmsg !~ /^M[cC];LL=-\d+;LH=\d+;SL=-\d+;SH=\d+;D=[0-9A-F]+;C=\d+;L=\d+;(?:R=\d+;)?$/){
    $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MC, faulty msg: $rmsg]);
    return ; # Abort here if not successfull
  }

  # Extract Data from rmsg:
  my %msg_parts = SIGNALduino_Split_Message($rmsg, $hash->{NAME});

  # Verify if extracted hash has the correct values:
  my $clock    = _limit_to_number($msg_parts{clockabs}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MC, faulty clock: $msg_parts{clockabs}]) // return ;
  my $mcbitnum = _limit_to_number($msg_parts{mcbitnum}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MC, faulty mcbitnum: $msg_parts{mcbitnum}]) // return ;
  my $rawData  = _limit_to_hex($msg_parts{rawData})     // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MC, faulty rawData D=: $msg_parts{rawData}]) // return ;
  my $rssi;
  my $rssiStr= '';
  if ( defined $msg_parts{rssi} ){
     $rssi = _limit_to_number($msg_parts{rssi}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MC, faulty rssi R=: $msg_parts{rssi}]) // return ;
    ($rssi,$rssiStr) = SIGNALduino_calcRSSI($rssi);
  };
  my $messagetype=$msg_parts{messagetype};
  my $name = $hash->{NAME};

  
  my $bitData;
  my $dmsg;
  my $message_dispatched=0;
  my $debug = AttrVal($hash->{NAME},'debug',0);


  Debug "$name: processing manchester messag len:".length($rawData) if ($debug);

  my $hlen = length($rawData);
  my $blen;
  #if (defined($mcbitnum)) {
  # $blen = $mcbitnum;
  #} else {
    $blen = $hlen * 4;
  #}

  my $rawDataInverted;
  ($rawDataInverted = $rawData) =~ tr/0123456789ABCDEF/FEDCBA9876543210/;   # Some Manchester Data is inverted

  for my $id (@{$hash->{mcIdList}}) {

    #next if ($blen < $ProtocolListSIGNALduino{$id}{length_min} || $blen > $ProtocolListSIGNALduino{$id}{length_max});
    #if ( $clock >$ProtocolListSIGNALduino{$id}{clockrange}[0] and $clock <$ProtocolListSIGNALduino{$id}{clockrange}[1]);
    my @clockrange = @{$hash->{protocolObject}->getProperty($id,'clockrange')};
    if ( $clock > $clockrange[0] && $clock < $clockrange[1] && length($rawData)*4 >= $hash->{protocolObject}->getProperty($id,'length_min') )
    {
      Debug "clock and min length matched"  if ($debug);

      (defined $rssi ) ?  $hash->{logMethod}->($name, 4, qq[$name: Parse_MC, Found manchester protocol id $id clock $clock $rssiStr -> ].$hash->{protocolObject}->getProperty($id,'name'))
                 :  $hash->{logMethod}->($name, 4, qq[$name: Parse_MC, Found manchester protocol id $id clock $clock -> ].$hash->{protocolObject}->getProperty($id,'name'));

      my $polarityInvert = ( $hash->{protocolObject}->checkProperty($id,'polarity','') eq 'invert' ) ? 1 : 0;
      Debug "$name: polarityInvert=$polarityInvert" if ($debug); 
      if (  $messagetype eq 'Mc' 
          || ( defined $hash->{version}  && substr $hash->{version},0,6 eq 'V 3.2.')   )
      {
        $polarityInvert = $polarityInvert ^ 1;
      }

      $bitData = ($polarityInvert == 1 )
                ? unpack("B$blen", pack("H$hlen", $rawDataInverted))
                : unpack("B$blen", pack("H$hlen", $rawData));

      Debug "$name: extracted data $bitData (bin)\n" if ($debug); ## Convert Message from hex to bits
        $hash->{logMethod}->($name, 5, "$name: Parse_MC, extracted data $bitData (bin)");

        my $method = $hash->{protocolObject}->getProperty($id,'method');
        if (!exists &$method || !defined &{ $method })
      {
        $hash->{logMethod}->($name, 5, "$name: Parse_MC, Error: Unknown function=$method. Please define it in file SD_ProtocolData.pm");
      } else {
        $mcbitnum = length($bitData) if ($mcbitnum > length($bitData));
        my ($rcode,$res) = $method->($hash->{protocolObject},$name,$bitData,$id,$mcbitnum);
        if ($rcode != -1) {
          $dmsg = sprintf('%s%s',$hash->{protocolObject}->checkProperty($id,'preamble',''),$res);
          my $modulematch = $hash->{protocolObject}->checkProperty($id,'modulematch',undef);

          if (!defined $modulematch || $dmsg =~ m/$modulematch/) {

            if (substr($hash->{protocolObject}->checkProperty($id,'developId',' '),0,1) eq 'm') {

              my $devid = "m$id";
              my $develop = lc(AttrVal($name,'development',''));
              if ($develop !~ m/$devid/) {    # kein dispatch wenn die Id nicht im Attribut development steht
                $hash->{logMethod}->($name, 3, qq[$name: Parse_MC, ID=$devid skipped dispatch (developId=m). To use, please add m$id to the attr development]);
                next;
              }
            }
            if ( SDUINO_MC_DISPATCH_VERBOSE < 5 
                 && (SDUINO_MC_DISPATCH_LOG_ID eq '' || SDUINO_MC_DISPATCH_LOG_ID eq $id) )
            {
              defined($rssi)  ? $hash->{logMethod}->($name, SDUINO_MC_DISPATCH_VERBOSE, qq[$name: Parse_MC, $id, $rmsg $rssiStr])
                      :  $hash->{logMethod}->($name, SDUINO_MC_DISPATCH_VERBOSE, qq[$name: Parse_MC, $id, $rmsg]);
            }
            SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
            $message_dispatched=1;
          }
        } else {
          $res='undef' if (!defined($res));
          $hash->{logMethod}->($name, 5, qq[$name: Parse_MC, protocol does not match return from method: ($res)]) ;
        }
      }
    }
  }
  return 0 if (!$message_dispatched);
  return 1;
}

############################# package main, test exists
sub SIGNALduino_Parse_MN {

  my $hash = shift // return;   #return if no hash  is provided
  my $rmsg = shift // return;   #return if no rmsg is provided
 
  if ($rmsg !~ /^MN;D=[0-9A-F]+;(?:R=[0-9]+;)?$/){
    $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MN, faulty msg: $rmsg]);
    return ; # Abort here if not successfull
  }

  # Extract Data from rmsg:
  my %msg_parts = SIGNALduino_Split_Message($rmsg, $hash->{NAME});

  # Verify if extracted hash has the correct values:
  my $rawData  = _limit_to_hex($msg_parts{rawData})     // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MN, faulty rawData D=: $msg_parts{rawData}]) //  return ;
  my $rssi;
  my $rssiStr= '';
  if ( defined $msg_parts{rssi} ){
     $rssi = _limit_to_number($msg_parts{rssi}) // $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: Parse_MN, faulty rssi R=: $msg_parts{rssi}]) //  return ;
    ($rssi,$rssiStr) = SIGNALduino_calcRSSI($rssi);
  };
  my $messagetype=$msg_parts{messagetype};
  my $name = $hash->{NAME};

  my $dmsg;

  my $match;
  my $modulation;
  my $message_dispatched=0;

  mnIDLoop:
  for my $id (@{$hash->{mnIdList}}) {
    my $rfmode = $hash->{protocolObject}->getProperty($id,'rfmode');
    if (!defined $rfmode) {
      $hash->{logMethod}->($name, 5, qq[$name: Parse_MN, Error! id $id has no rfmode. Please define it in file SD_ProtocolData.pm]);
      next mnIDLoop;
    }

    my ($rcode, $rtxt) = $hash->{protocolObject}->LengthInRange($id,length($rawData)); # Check message length
    if (!$rcode) {
      $hash->{logMethod}->($name, 4, qq[$name: Parse_MN, Error! id $id msg=$rawData, $rtxt]);
      next mnIDLoop;
    }

    $match = $hash->{protocolObject}->checkProperty($id,'regexMatch',undef);
    $modulation = $hash->{protocolObject}->checkProperty($id,'modulation',undef);
    if ( defined($match) && $rawData =~ m/$match/x ) {
      $hash->{logMethod}->($name, 4, qq[$name: Parse_MN, Found $modulation Protocol id $id -> ].$hash->{protocolObject}->getProperty($id,'name').qq[ with match $match]);
    } elsif (!defined($match) ) {
      $hash->{logMethod}->($name, 4, qq[$name: Parse_MN, Found $modulation Protocol id $id -> ].$hash->{protocolObject}->getProperty($id,'name'));
    } else {
      $hash->{logMethod}->($name, 4, qq[$name: Parse_MN, $modulation Protocol id $id ].$hash->{protocolObject}->getProperty($id,'name').qq[ msg $rawData not match $match]);
      next mnIDLoop;
    }

    my $method = $hash->{protocolObject}->getProperty($id,'method',undef);
    my @methodReturn = defined $method ? $method->($hash->{protocolObject},$rawData) : ($rawData);
    if ($#methodReturn != 0) {
      my $vl = $methodReturn[1] =~ /missing\smodule/xms ? 1 : 4;
      $hash->{logMethod}->($name, $vl, qq{$name: Parse_MN, Error! method $methodReturn[1]});
      next mnIDLoop;
    }
    $dmsg = sprintf('%s%s',$hash->{protocolObject}->checkProperty($id,'preamble',''),$methodReturn[0]);
    $hash->{logMethod}->($name, 5, qq[$name: Parse_MN, Decoded matched MN Protocol id $id dmsg=$dmsg $rssiStr]);
    SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
    $message_dispatched++;
    
  }
  return $message_dispatched;
}

############################# package main
sub SIGNALduino_Parse($$$$@) {
  my ($hash, $iohash, $name, $rmsg, $initstr) = @_;

  #print Dumper(\%ProtocolListSIGNALduino);

  if (!($rmsg=~ s/^\002(M.;.*;)\003/$1/))   # Check if a Data Message arrived and if it's complete  (start & end control char are received)
  {                                         # cut off start end end character from message for further processing they are not needed
    $hash->{logMethod}->($name, AttrVal($name,'noMsgVerbose',5), "$name: Parse, noMsg: $rmsg");
    return ;
  }

  if (defined($hash->{keepalive})) {
    $hash->{keepalive}{ok}    = 1;
    $hash->{keepalive}{retry} = 0;
  }

  my $debug = AttrVal($iohash->{NAME},'debug',0);

  Debug "$name: incoming message: ($rmsg)\n" if ($debug);

  if (AttrVal($name, 'rawmsgEvent', 0)) {
    DoTrigger($name, 'RAWMSG ' . $rmsg);
  }

  my $dispatched;
 
  # Message Synced type   -> MS
  my $mType = uc substr $rmsg,0,2 ;

  if (@{$hash->{msIdList}} && $mType eq  'MS' )
  {
    $dispatched= SIGNALduino_Parse_MS($hash, $rmsg);
  }
  # Message unsynced type   -> MU
  elsif (@{$hash->{muIdList}} && $mType eq  'MU')
  {
    $dispatched=  SIGNALduino_Parse_MU($hash, $rmsg);
  }
  # Manchester encoded Data   -> MC
    elsif (@{$hash->{mcIdList}} && $mType eq  'MC')
  {
    $dispatched=  SIGNALduino_Parse_MC($hash, $rmsg);
  }
  # Message xFSK   -> MN
    elsif (@{$hash->{mnIdList}} && $mType eq  'MN') 
  {
    $dispatched=  SIGNALduino_Parse_MN($hash, $rmsg);
  }
   else {
    Debug "$name: unknown Messageformat, aborting\n" if ($debug);
    return ;
  }

  if ( AttrVal($hash->{NAME},'verbose','0') > 4 && !$dispatched)
  {
    my $notdisplist;
    my @lines;
    if (defined($hash->{unknownmessages}))
    {
      $notdisplist=$hash->{unknownmessages};
      @lines = split ('#', $notdisplist);   # or whatever
    }
    push(@lines,FmtDateTime(time()).'-'.$rmsg);
    shift(@lines)if (scalar @lines >25);
    $notdisplist = join('#',@lines);

    $hash->{unknownmessages}=$notdisplist;
    return ;
    #Todo  compare Sync/Clock fact and length of D= if equal, then it's the same protocol!
  }
  return $dispatched;

}


############################# package main
sub SIGNALduino_Ready {
  my ($hash) = @_;

  if ($hash->{STATE} eq 'disconnected') {
    $hash->{DevState} = 'disconnected';
    return DevIo_OpenDev($hash, 1, \&SIGNALduino_DoInit, \&SIGNALduino_Connect)
  }

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

############################# package main
sub SIGNALduino_WriteInit {
  my ($hash) = @_;

  # todo: ist dies so ausreichend, damit die Aenderungen uebernommen werden?
  SIGNALduino_AddSendQueue($hash,'WS36');   # SIDLE, Exit RX / TX, turn off frequency synthesizer
  SIGNALduino_AddSendQueue($hash,'WS34');   # SRX, Enable RX. Perform calibration first if coming from IDLE and MCSM0.FS_AUTOCAL=1.
}

############################# package main
sub SIGNALduino_SimpleWrite(@) {
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);
  if($hash->{TYPE} eq 'SIGNALduino_RFR') {
    # Prefix $msg with RRBBU and return the corresponding SIGNALduino hash.
    ($hash, $msg) = SIGNALduino_RFR_AddPrefix($hash, $msg);
  }

  my $name = $hash->{NAME};
  $hash->{logMethod}->($name, 5, "$name: SimpleWrite, $msg");

  $msg .= "\n" unless($nonl);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

############################# package main
sub SIGNALduino_Attr(@) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $debug = AttrVal($name,'debug',0);

  $aVal= '' if (!defined($aVal));
  $hash->{logMethod}->($name, 4, "$name: Attr, Calling sub with args: $cmd $aName = $aVal");

  ## Change Clients
  if( $aName eq 'Clients' ) {
    $hash->{Clients} = $aVal;
    $hash->{Clients} = $clientsSIGNALduino if( !$hash->{Clients}) ;     ## Set defaults
    return 'Setting defaults';
  }
  ## Change MatchList
  elsif( $aName eq 'MatchList' ) {
    my $match_list;
    if( $cmd eq 'set' ) {
      $match_list = eval $aVal; ## Allow evaluation of hash object from "attr" string f.e. { '34:MYMODULE' => '^u99#.{9}' } 
      if( $@ ) {
        $hash->{logMethod}->($name, 2, $name .": Attr, $aVal: ". $@);
      }
    }

    if( ref($match_list) eq 'HASH' ) {
      $hash->{MatchList} = { %matchListSIGNALduino , %$match_list };          ## Allow incremental addition of an entry to existing hash list
    } else {
      $hash->{MatchList} = \%matchListSIGNALduino;                      ## Set defaults
      $hash->{logMethod}->($name, 2, $name .": Attr, $aVal: not a HASH using defaults") if( $aVal );
    }
  }
  ## Change verbose
  elsif ($aName eq 'verbose') {
    $hash->{logMethod}->($name, 3, "$name: Attr, setting Verbose to: " . $aVal);
    $hash->{unknownmessages}='' if $aVal <4;
  }
  ## Change debug
  elsif ($aName eq 'debug')
  {
    $debug = $aVal;
    $hash->{logMethod}->($name, 3, "$name: Attr, setting debug to: " . $debug);
  }
  ## Change whitelist_IDs
  elsif ($aName eq 'whitelist_IDs')
  {
    if ($init_done) {   # beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
      SIGNALduino_IdList("x:$name",$aVal);
    }
  }
  ## Change blacklist_IDs
  elsif ($aName eq 'blacklist_IDs')
  {
    if ($init_done) {   # beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
      SIGNALduino_IdList("x:$name",undef,$aVal);
    }
  }
  ## Change development
  elsif ($aName eq 'development')
  {
    if ($init_done) {   # beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
      SIGNALduino_IdList("x:$name",undef,undef,$aVal);
    }
  }
  ## Change doubleMsgCheck_IDs
  elsif ($aName eq 'doubleMsgCheck_IDs')
  {
    if (defined($aVal)) {
      if (length($aVal)>0) {
        if (substr($aVal,0 ,1) eq '#') {
          $hash->{logMethod}->($name, 3, "$name: Attr, doubleMsgCheck_IDs disabled: $aVal");
          delete $hash->{DoubleMsgIDs};
        }
        else {
          $hash->{logMethod}->($name, 3, "$name: Attr, doubleMsgCheck_IDs enabled: $aVal");
          my %DoubleMsgiD = map { $_ => 1 } split(',', $aVal);
          $hash->{DoubleMsgIDs} = \%DoubleMsgiD;
          #print Dumper $hash->{DoubleMsgIDs};
        }
      }
      else {
        $hash->{logMethod}->($name, 3, "$name: Attr, delete doubleMsgCheck_IDs");
        delete $hash->{DoubleMsgIDs};
      }
    }
  }
  ## Change hardware
  elsif ($aName eq 'hardware')      # to set flashCommand if hardware def or change
  {
    if ($cmd eq 'del') {            # to delete flashCommand if hardware delete
      if (exists $attr{$name}{flashCommand}) { delete $attr{$name}{flashCommand};}
    }
  }
  ## Change eventlogging
  elsif ($aName eq 'eventlogging')  # enable / disable eventlogging
  {
    if ($cmd eq 'set' && $aVal == 1) {
      $hash->{logMethod} = \&::SIGNALduino_Log3;
      Log3 $name, 3, "$name: Attr, Enable eventlogging";
    } else {
      $hash->{logMethod} = \&::Log3;
      Log3 $name, 3, "$name: Attr, Disable eventlogging";
    }
  }
  ## Change userReadings
  elsif ($aName eq 'userReadings')  # look reserved cc1101 readings
  {
    return "Note, please use other userReadings names.\nReserved names from $name are: cc1101_config, cc1101_config_ext, cc1101_patable"
      if ($aVal =~ /cc1101_(?:config(?:_ext)?|patable)(?:\s|{)/);
  }
  ## Change cc1101_reg_user
  elsif ($aName eq 'cc1101_reg_user' && $cmd eq 'set') # set default register
  {
    return 'ERROR: This attribute is only available for a receiver with CC1101.' if ( ($init_done == 1) && (InternalVal($hash->{NAME},"cc1101_available",0) == 0) );
    $aVal = $aVal.',' if ($aVal !~ /,$/gx);
    return 'ERROR: Your attribute value is wrong!' if ( $aVal !~ /^([0-2]{1}[0-9a-fA-F]{3},)+$/gx);
  }
  ## Change rfmode
  elsif ($aName eq 'rfmode')          # change receive mode
  {
    if( $cmd eq 'set' ) {
      if (!first { $_ eq $aVal } @rfmode) {
        $hash->{logMethod}->($name, 1, "$name: Attr, $aName $aVal is not supported");
        return 'ERROR: The rfmode is not supported';
      }
      if ($init_done) {
        my $ret = main::SIGNALduino_Attr_rfmode($hash,$aVal);
        if (defined $ret) {
          return $ret;
        } else {
          $hash->{logMethod}->($name, 3, "$name: Attr, $aName switched to $aVal");
        }
      }
    }
  }
  return ;
}

############################# package main
sub SIGNALduino_FW_Detail($@) {
  my ($FW_wname, $name, $room, $pageHash) = @_;

  my $hash = $defs{$name};
  my @dspec=devspec2array("DEF=.*fakelog");
  my $lfn = $dspec[0];
  my $fn=$defs{$name}->{TYPE}."-Flash.log";

  my $ret = "<div class='makeTable wide'><span>Information menu</span>
<table class='block wide' id='SIGNALduinoInfoMenue' nm='$hash->{NAME}' class='block wide'>
<tr class='even'>";

  if (-s AttrVal('global', 'logdir', './log/') .$fn)
  {
    my $flashlogurl="$FW_ME/FileLog_logWrapper?dev=$lfn&type=text&file=$fn";

    $ret .= "<td>";
    $ret .= "<a href=\"$flashlogurl\">Last Flashlog<\/a>";
    $ret .= "</td>";
    #return $ret;
  }

  my $protocolURL="$FW_ME/FileLog_logWrapper?dev=$lfn&type=text&file=$fn";

  $ret.="<td><a href='#showProtocolList' id='showProtocolList'>Display protocollist</a></td>";
  $ret .= '</tr></table></div>

<script>
$( "#showProtocolList" ).click(function(e) {
  e.preventDefault();
  FW_cmd(FW_root+\'?cmd={SIGNALduino_FW_getProtocolList("'.$FW_detail.'")}&XHR=1\', function(data){SD_plistWindow(data)});

});

function SD_plistWindow(txt)
{
  var div = $("<div id=\"SD_protocolDialog\">");
  $(div).html(txt);
  $("body").append(div);
  var oldPos = $("body").scrollTop();
  var btxtStable = "";
  var btxtBlack = "";
  if ($("#SD_protoCaption").text().substr(0,1) != "d") {
        btxtStable = "stable";
  }
  if ($("#SD_protoCaption").text().substr(-1) == ".") {
    btxtBlack = " except blacklist";
  }

  $(div).dialog({
    dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:true,
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    title: "Protocollist Overview",
    buttons: [
      {text:"select all " + btxtStable + btxtBlack, click:function(){
      $("#SD_protocolDialog table td input:checkbox").prop(\'checked\', true);

      $("input[name=SDnotCheck]").each( function () {
        $(this).prop(\'checked\',false);
      });
      }},
      {text:"deselect all", click:function(e){
           $("#SD_protocolDialog table td input:checkbox").prop(\'checked\', false);
      }},
      {text:"save to whitelist and close", click:function(){
        var allVals = [];
      $("#SD_protocolDialog table td input:checkbox:checked").each(function() {
          allVals.push($(this).val());
      })
          FW_cmd(FW_root+ \'?XHR=1&cmd={SIGNALduino_FW_saveWhitelist("'.$name.'","\'+String(allVals)+\'")}\');
          $(this).dialog("close");
          $(div).remove();
          location.reload();
      }},
      {text:"close", click:function(){
        $(this).dialog("close");
        $(div).remove();
        location.reload();
      }}]
  });
}

</script>';
  return $ret;
}

############################# package main
sub SIGNALduino_FW_saveWhitelist {
  my $name = shift;
  my $wl_attr = shift;
  my $hash = $defs{$name};

  if (!IsDevice($name)) {
    Log3 undef, 3, "$name: FW_saveWhitelist, is not a valid definition, operation aborted.";
    return;
  }

  if ($wl_attr eq '') {   # da ein Attribut nicht leer sein kann, kommt ein Komma rein
    $wl_attr = ',';
  }
  elsif ($wl_attr !~ /\d+(?:,\d.?\d?)*$/ ) {
    Log3 $name, 3, "$name: FW_saveWhitelist, attr whitelist_IDs can not be updated";
    return;
  }
  else {
    $wl_attr =~ s/,$//;   # Komma am Ende entfernen
  }
  CommandAttr($hash,"$name whitelist_IDs $wl_attr");
  Log3 $name, 3, "$name: FW_saveWhitelist, $wl_attr";
  SIGNALduino_IdList("x:$name", $wl_attr);
}

############################# package main      - test is missing
sub SIGNALduino_IdList($@) {
  my ($param, $aVal, $blacklist, $develop0) = @_;
  my (undef,$name) = split(':', $param);

  return if (!defined $name || !IsDevice($name));
  my $hash = $defs{$name};

  my @msIdList = ();
  my @muIdList = ();
  my @mcIdList = ();
  my @mnIdList = ();
  my @skippedDevId = ();
  my @skippedBlackId = ();
  my @skippedWhiteId = ();
  my @devModulId = ();
  my %WhitelistIDs;
  my %BlacklistIDs;
  my $wflag = 0;            # whitelist flag, 0=disabled

  delete ($hash->{IDsNoDispatch}) if (defined($hash->{IDsNoDispatch}));

  if (!defined($aVal)) {
    $aVal = AttrVal($name,'whitelist_IDs','');
  }

  my ($develop,$devFlag) = SIGNALduino_getAttrDevelopment($name, $develop0);  # $devFlag = 1 -> alle developIDs y aktivieren
  $hash->{logMethod}->($name, 3, "$name: IdList, development version active, development attribute = $develop") if ($devFlag == 1);

  if ($aVal eq '' || substr($aVal,0 ,1) eq '#') {           # whitelist nicht aktiv
    ($devFlag == 1) 
      ? $hash->{logMethod}->($name, 3, "$name: IdList, attr whitelist disabled or not defined (all IDs are enabled, except blacklisted): $aVal")
      : $hash->{logMethod}->($name, 3, "$name: IdList, attr whitelist disabled or not defined (all IDs are enabled, except blacklisted and instable IDs): $aVal");
  } else {
    %WhitelistIDs = map {$_ => undef} split(',', $aVal);    # whitelist in Hash wandeln
    #my $w = join ',' => map "$_" => keys %WhitelistIDs;
    $hash->{logMethod}->($name, 3, "$name: IdList, attr whitelist: $aVal");
    $wflag = 1;
  }
  #SIGNALduino_Log3 $name, 3, "$name IdList: attr whitelistIds=$aVal" if ($aVal);

  if ($wflag == 0) {                      # whitelist not aktive
    if (!defined($blacklist)) {
      $blacklist = AttrVal($name,'blacklist_IDs','');
    }
    if (length($blacklist) > 0) {             # Blacklist in Hash wandeln
      $hash->{logMethod}->($name, 3, "$name: IdList, attr blacklistIds=$blacklist");
      %BlacklistIDs = map { $_ => 1 } split(',', $blacklist);
      #my $w = join ', ' => map "$_" => keys %BlacklistIDs;
      #SIGNALduino_Log3 $name, 3, "$name IdList, Attr blacklist $w";
    }
  }
  for my $id ($hash->{protocolObject}->getKeys())
  {
    if ($wflag == 1)                      # whitelist active
    {
      if (!exists($WhitelistIDs{$id}))    # Id wurde in der whitelist nicht gefunden
      {
        push (@skippedWhiteId, $id);
        next;
      }
    }
    else {                                # whitelist not active
      if (exists($BlacklistIDs{$id})) {
        #SIGNALduino_Log3 $name, 3, "$name: IdList, skip Blacklist ID $id";
        push (@skippedBlackId, $id);
        next;
      }

      # wenn es keine developId gibt, dann die folgenden Abfragen ueberspringen
      if (defined $hash->{protocolObject}->getProperty($id,'developId'))
      {
        if ($hash->{protocolObject}->getProperty($id,'developId') eq 'm') {
          if ($develop !~ m/m$id/) {  # ist nur zur Abwaertskompatibilitaet und kann in einer der naechsten Versionen entfernt werden
            push (@devModulId, $id);
            if ($devFlag == 0) {
              push (@skippedDevId, $id);
              next;
            }
          }
        }
        elsif ($hash->{protocolObject}->getProperty($id,'developId') eq 'p') {
          $hash->{logMethod}->($name, 5, "$name: IdList, ID=$id skipped (developId=p), caution, protocol can cause crashes, use only if advised to do");
          next;
        }
        elsif ($devFlag == 0 && $hash->{protocolObject}->getProperty($id,'developId') eq 'y' && $develop !~ m/y$id/) {
          #SIGNALduino_Log3 $name, 3, "$name: IdList, ID=$id skipped (developId=y)";
          push (@skippedDevId, $id);
          next;
        }
      }
    }

    if (defined($hash->{protocolObject}->getProperty($id,'format')) && $hash->{protocolObject}->getProperty($id,'format') eq 'manchester')
    {
      push (@mcIdList, $id);
    }
    elsif (defined $hash->{protocolObject}->getProperty($id,'modulation'))
    {
      push (@mnIdList, $id);
    }
    elsif (defined $hash->{protocolObject}->getProperty($id,'sync'))
    {
      push (@msIdList, $id);
    }
    elsif (defined $hash->{protocolObject}->getProperty($id,'clockabs'))
    {
      # $ProtocolListSIGNALduino{$id}{length_min} = SDUINO_PARSE_DEFAULT_LENGHT_MIN if (!exists($ProtocolListSIGNALduino{$id}{length_min}));
      push (@muIdList, $id);
    }
  }

  @msIdList = sort {$a <=> $b} @msIdList;
  @muIdList = sort {$a <=> $b} @muIdList;
  @mcIdList = sort {$a <=> $b} @mcIdList;
  @mnIdList = sort {$a <=> $b} @mnIdList;
  @skippedDevId = sort {$a <=> $b} @skippedDevId;
  @skippedBlackId = sort {$a <=> $b} @skippedBlackId;
  @skippedWhiteId = sort {$a <=> $b} @skippedWhiteId;

  @devModulId = sort {$a <=> $b} @devModulId;

  $hash->{logMethod}->($name, 3, "$name: IdList, MS @msIdList");
  $hash->{logMethod}->($name, 3, "$name: IdList, MU @muIdList");
  $hash->{logMethod}->($name, 3, "$name: IdList, MC @mcIdList");
  $hash->{logMethod}->($name, 3, "$name: IdList, MN @mnIdList");  # ToDo: nur wenn Internal cc1101_available 1 ???
  $hash->{logMethod}->($name, 5, "$name: IdList, not whitelisted skipped = @skippedWhiteId") if (scalar @skippedWhiteId > 0);
  $hash->{logMethod}->($name, 4, "$name: IdList, blacklistId skipped = @skippedBlackId") if (scalar @skippedBlackId > 0);
  $hash->{logMethod}->($name, 4, "$name: IdList, development skipped = @skippedDevId") if (scalar @skippedDevId > 0);
  if (scalar @devModulId > 0)
  {
    $hash->{logMethod}->($name, 3, "$name: IdList, development protocol is active (to activate dispatch to not finshed logical module, enable desired protocol via whitelistIDs) = @devModulId");
    $hash->{IDsNoDispatch} = join(',', @devModulId);
  }

  $hash->{msIdList} = \@msIdList;
  $hash->{muIdList} = \@muIdList;
  $hash->{mcIdList} = \@mcIdList;
  $hash->{mnIdList} = \@mnIdList;
}

############################# package main, test exists
sub SIGNALduino_getAttrDevelopment {
  my $name = shift;
  my $develop = shift;
  my $devFlag = 0;
  if (index(SDUINO_VERSION, 'dev') >= 0) {                                                      # development version
    $develop = AttrVal($name,'development', 0) if (!defined($develop));
    $devFlag = 1 if ($develop eq '1' || (substr($develop,0,1) eq 'y' && $develop !~ m/^y\d/));  # Entwicklerversion, y ist nur zur Abwaertskompatibilitaet und kann in einer der naechsten Versionen entfernt werden
  } else {
    $develop = '0';
    Log3 $name, 3, "$name: getAttrDevelopment, IdList ### Attribute development is in this version ignored ###";
  }
  return ($develop,$devFlag);
}

############################# package main, test exists
sub SIGNALduino_callsub {
  my $obj=shift; #comatibility thing
  my $funcname =shift // carp 'to less arguments,functionname is required';;
  my $method = shift // undef;
  my $evalFirst = shift // undef;
  my $name = shift // carp 'to less arguments, name is required';

  my @args = @_;

  my $hash = $defs{$name};
  if ( defined $method && defined &$method )
  {
    if (defined($evalFirst) && $evalFirst)
    {
      eval( $method->($obj,$name, @args));
      if($@) {
        $hash->{logMethod}->($name, 5, "$name: callsub, Error: $funcname, has an error and will not be executed: $@ please report at github.");
        return (0,undef);
      }
    }
    #my $subname = @{[eval {&$method}, $@ =~ /.*/]};
    $hash->{logMethod}->($hash, 5, "$name: callsub, applying $funcname, value before: @args"); # method $subname"

    my ($rcode, @returnvalues) = $method->($obj,$name, @args) ;

    if (@returnvalues && defined($returnvalues[0])) {
      $hash->{logMethod}->($name, 5, "$name: callsub, rcode=$rcode, modified value after $funcname: @returnvalues");
    } else {
      $hash->{logMethod}->($name, 5, "$name: callsub, rcode=$rcode, after calling $funcname");
    }
    return ($rcode, @returnvalues);
  } elsif (defined $method ) {
    $hash->{logMethod}->($name, 5, "$name: callsub, Error: Unknown method $funcname pease report at github");
    return (0,undef);
  }
  return (1,@args);
}



# - - - - - - - - - - - -
#=item SIGNALduino_filterMC()
#This functons, will act as a filter function. It will decode MU data via Manchester encoding
#
# Will return  $count of ???,  modified $rawData , modified %patternListRaw,
# =cut
############################# package main
sub SIGNALduino_filterMC($$$%) {
  ## Warema Implementierung : Todo variabel gestalten
  my ($name,$id,$rawData,%patternListRaw) = @_;
  my $hash=$defs{$name};
  my $debug = AttrVal($name,'debug',0);

  my ($ht, $hasbit, $value) = 0;
  $value=1 if (!$debug);
  my @bitData;
  my @sigData = split '',$rawData;
  my $clockabs;

  foreach my $pulse (@sigData)
  {
    next if (!defined($patternListRaw{$pulse}));
    #SIGNALduino_Log3 $name, 4, "$name: pulese: ".$patternListRaw{$pulse};
    $clockabs = $hash->{protocolObject}->getProperty($id,'clockabs');

    if (SIGNALduino_inTol($clockabs,abs($patternListRaw{$pulse}),$clockabs*0.5))
    {
      # Short
      $hasbit=$ht;
      $ht = $ht ^ 0b00000001;
      $value='S' if($debug);
      #SIGNALduino_Log3 $name, 4, "$name: filter S ";
    } elsif ( SIGNALduino_inTol($clockabs*2,abs($patternListRaw{$pulse}),$clockabs*0.5)) {
      # Long
      $hasbit=1;
      $ht=1;
      $value='L' if($debug);
      #SIGNALduino_Log3 $name, 4, "$name: filter L ";
    } elsif ( SIGNALduino_inTol($hash->{protocolObject}->getProperty($id,'syncabs')+(2*$clockabs),abs($patternListRaw{$pulse}),$clockabs*0.5))  {
      $hasbit=1;
      $ht=1;
      $value='L' if($debug);
      #SIGNALduino_Log3 $name, 4, "$name: sync L ";
    } else {
      # No Manchester Data
      $ht=0;
      $hasbit=0;
      #SIGNALduino_Log3 $name, 4, "$name: filter n ";
    }

    if ($hasbit && $value) {
      $value = lc($value) if($debug && $patternListRaw{$pulse} < 0);
      my $bit=$patternListRaw{$pulse} > 0 ? 1 : 0;
      #SIGNALduino_Log3 $name, 5, "$name: adding value: ".$bit;

      push @bitData, $bit ;
    }
  }

  my %patternListRawFilter;
  $patternListRawFilter{0} = 0;
  $patternListRawFilter{1} = $clockabs;

  #SIGNALduino_Log3 $name, 5, "$name: filterbits: ".@bitData;
  $rawData = join '', @bitData;
  return (undef ,$rawData, %patternListRawFilter);
}


# - - - - - - - - - - - -
#=item SIGNALduino_filterSign()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
#
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut
############################# package main
sub SIGNALduino_filterSign($$$%) {
  my ($name,$id,$rawData,%patternListRaw) = @_;
  my $debug = AttrVal($name,'debug',0);

  my %buckets;
  # Remove Sign
  %patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sign from all

  my $intol=0;
  my $cnt=0;

  # compress pattern hash
  foreach my $key (keys %patternListRaw) {

    #print 'chk:'.$patternListRaw{$key};
    #print "\n";

    $intol=0;
    foreach my $b_key (keys %buckets){
      #print 'with:'.$buckets{$b_key};
      #print "\n";

      # $value  - $set <= $tolerance
      if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.25))
      {
        #print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
        $cnt++;
        eval "\$rawData =~ tr/$key/$b_key/";

        #if ($key == $msg_parts{clockidx})
        #{
        #   $msg_pats{syncidx} = $buckets{$key};
        # }
        # elsif ($key == $msg_parts{syncidx})
        # {
        #   $msg_pats{syncidx} = $buckets{$key};
        # }

        $buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
        #print"\t recalc to ". $buckets{$b_key}."\n";

        delete ($patternListRaw{$key});  # deletes the compressed entry
        $intol=1;
        last;
      }
    }
    if ($intol == 0) {
      $buckets{$key}=abs($patternListRaw{$key});
    }
  }

  return ($cnt,$rawData, %patternListRaw);
  #print 'rdata: '.$msg_parts{rawData}."\n";

  #print Dumper (%buckets);
  #print Dumper (%msg_parts);

  #modify msg_parts pattern hash
  #$patternListRaw = \%buckets;
}


# - - - - - - - - - - - -
#=item SIGNALduino_compPattern()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
#
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut
############################# package main
sub SIGNALduino_compPattern($$$%) {
  my ($name,$id,$rawData,%patternListRaw) = @_;
  my $debug = AttrVal($name,'debug',0);

  my %buckets;
  # Remove Sign
  #%patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sing from all

  my $intol=0;
  my $cnt=0;

  # compress pattern hash
  foreach my $key (keys %patternListRaw) {

    #print 'chk:'.$patternListRaw{$key};
    #print "\n";

    $intol=0;
    foreach my $b_key (keys %buckets){
      #print 'with:'.$buckets{$b_key};
      #print "\n";

      # $value  - $set <= $tolerance
      if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.4))
      {
        #print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
        $cnt++;
        eval "\$rawData =~ tr/$key/$b_key/";

        #if ($key == $msg_parts{clockidx})
        #{
        #   $msg_pats{syncidx} = $buckets{$key};
        # }
        # elsif ($key == $msg_parts{syncidx})
        # {
        #   $msg_pats{syncidx} = $buckets{$key};
        # }

        $buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
        #print"\t recalc to ". $buckets{$b_key}."\n";

        delete ($patternListRaw{$key});  # deletes the compressed entry
        $intol=1;
        last;
      }
    }
    if ($intol == 0) {
      $buckets{$key}=$patternListRaw{$key};
    }
  }

  return ($cnt,$rawData, %patternListRaw);
  #print 'rdata: '.$msg_parts{rawData}."\n";

  #print Dumper (%buckets);
  #print Dumper (%msg_parts);

  #modify msg_parts pattern hash
  #$patternListRaw = \%buckets;
}


############################# package main
# the new Log with integrated loglevel checking
sub SIGNALduino_Log3 {
  my ($dev, $loglevel, $text) = @_;
  my $name =$dev;
  $name= $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");

  my $textEventlogging = $text;

  ### DoTrigger for eventlogging event
  #DoTrigger($dev,"$name $loglevel: $text");
  #2020-07-14_12:47:01 sduino_USB_SB_Test sduino_USB_SB_Test 4: sduino_USB_SB_Test: HandleWriteQueue, called

  #DoTrigger($dev,"$loglevel: $text");
  #2020-07-14_12:47:01 sduino_USB_SB_Test 4: sduino_USB_SB_Test: HandleWriteQueue, called

  ### $text may not be changed for return value
  if ($textEventlogging =~ /^$dev:\s/) {
    my $textCut = length($dev)+2;                            # length receivername and ': "
    $textEventlogging = substr($textEventlogging,$textCut);  # cut $textCut from $textEventlogging
  }

  ### DoTrigger for eventlogging event with adapted structure
  DoTrigger($dev,"$loglevel: $textEventlogging");
  #2020-07-16_12:40:07 sduino_USB_SB_Test 4: HandleWriteQueue, called

  ### return for normal logfile | unchangeable
  #2020.07.16 11:35:40.676 4: sduino_USB_SB_Test: HandleWriteQueue, called
  return Log3($name,$loglevel,$text);
}


############################# package main
# Helper to get a reference of the protocolList Hash
# ?? ToDo - wird diese Sub noch beoetigt ???
sub SIGNALduino_getProtocolList() {
  #return \%ProtocolListSIGNALduino
}

############################# package main
# Helper to create a individual callback per definition which can receive log output from perl modules
sub SIGNALduino_createLogCallback {
  my $hash = shift // return ;
  (ref $hash ne 'HASH') // return ;

  return sub  {
    my $message = shift // carp 'message must be provided';
    my $level = shift // 0;

    $hash->{logMethod}->($hash->{NAME}, $level,qq[$hash->{NAME}: $message]);
  };
};


############################# package main
sub SIGNALduino_FW_getProtocolList {
  my $name = shift;

  my $hash = $defs{$name};
  my $ret;
  my $devText = '';
  my $blackTxt = '';
  my %BlacklistIDs;
  my @IdList = ();
  my $comment;
  my $knownFreqs;

  my $blacklist = AttrVal($name,'blacklist_IDs','');
  if (length($blacklist) > 0) {                                     # Blacklist in Hash wandeln
    #SIGNALduino_Log3 $name, 5, "$name getProtocolList: attr blacklistIds=$blacklist";
    %BlacklistIDs = map { $_ => 1 } split(',', $blacklist);;
  }

  my $whitelist = AttrVal($name,'whitelist_IDs','#');
  if (AttrVal($name,'blacklist_IDs','') ne '') {                    # wenn es eine blacklist gibt, dann '.' an die Ueberschrift anhaengen
    $blackTxt = '.';
  }

  my ($develop,$devFlag) = SIGNALduino_getAttrDevelopment($name);   # $devFlag = 1 -> alle developIDs y aktivieren
  $devText = 'development version - ' if ($devFlag == 1);

  my %activeIdHash;
  @activeIdHash{@{$hash->{msIdList}}, @{$hash->{muIdList}}, @{$hash->{mcIdList}}, @{$hash->{mnIdList}}} = (undef);
  #SIGNALduino_Log3 $name,4, "$name IdList: $mIdList";

  my %IDsNoDispatch;
  if (defined($hash->{IDsNoDispatch})) {
    %IDsNoDispatch = map { $_ => 1 } split(',', $hash->{IDsNoDispatch});
    #SIGNALduino_Log3 $name,4, "$name IdList IDsNoDispatch=" . join ', ' => map "$_" => keys %IDsNoDispatch;
  }

  for my $id ($hash->{protocolObject}->getKeys())
  {
    push (@IdList, $id);
  }
  @IdList = sort { $a <=> $b } @IdList;

  $ret = "<table class=\"block wide internals wrapcolumns\">";

  $ret .="<caption id=\"SD_protoCaption\">$devText";
  if (substr($whitelist,0,1) ne '#') {
    $ret .="whitelist active$blackTxt</caption>";
  }
  else {
    $ret .="whitelist not active (save activate it)$blackTxt</caption>";
  }
  $ret .= "<thead style=\"text-align:center\"><td>act.</td><td>dev</td><td>ID</td><td>Msg Type</td><td>modulname</td><td>protocolname</td> <td># comment</td></thead>";
  $ret .="<tbody>";
  my $oddeven="odd";
  my $checked;
  my $checkAll;

  foreach my $id (@IdList)
  {
    my $msgtype = '';
    my $chkbox;

    if (defined $hash->{protocolObject}->getProperty($id,'format') && $hash->{protocolObject}->getProperty($id,'format') eq 'manchester')
    {
      $msgtype = 'MC';
    }
    elsif (defined $hash->{protocolObject}->getProperty($id,'modulation'))
    {
      $msgtype = 'MN';
    }
    elsif (defined $hash->{protocolObject}->getProperty($id,'sync'))
    {
      $msgtype = 'MS';
    }
    elsif (defined $hash->{protocolObject}->getProperty($id,'clockabs'))
    {
      $msgtype = 'MU';
    }

    $checked='';

    if (substr($whitelist,0,1) ne '#') {  # whitelist aktiv, dann ermitteln welche ids bei select all nicht checked sein sollen
      $checkAll = 'SDcheck';
      if (exists($BlacklistIDs{$id})) {
        $checkAll = 'SDnotCheck';
      }
      elsif (defined $hash->{protocolObject}->getProperty($id,'developId')) {
        if ($devFlag == 1 && $hash->{protocolObject}->getProperty($id,'developId') eq 'p') {
          $checkAll = 'SDnotCheck';
        }
        elsif ($devFlag == 0 && $hash->{protocolObject}->getProperty($id,'developId') eq 'y' && $develop !~ m/y$id/) {
          $checkAll = 'SDnotCheck';
        }
        elsif ($devFlag == 0 && $hash->{protocolObject}->getProperty($id,'developId') eq 'm') {
          $checkAll = 'SDnotCheck';
        }
      }
    }
    else {
      $checkAll = 'SDnotCheck';
    }

    if (exists($activeIdHash{$id}))
    {
      $checked='checked';
      if (substr($whitelist,0,1) eq '#') {  # whitelist nicht aktiv, dann entspricht select all dem $activeIdHash
        $checkAll = 'SDcheck';
      }
    }

    if ($devFlag == 0 && defined $hash->{protocolObject}->getProperty($id,'developId') && $hash->{protocolObject}->getProperty($id,'developId') eq 'p') {
      $chkbox="<div> </div>";
    }
    else {
      $chkbox=sprintf("<INPUT type=\"checkbox\" name=\"%s\" value=\"%s\" %s/>", $checkAll, $id, $checked);
    }

    $comment = $hash->{protocolObject}->checkProperty($id,'comment','');
    if (exists($IDsNoDispatch{$id})) {
      $comment .= ' (dispatch is only with a active whitelist possible)';
    }

    $knownFreqs = $hash->{protocolObject}->checkProperty($id,'knownFreqs','');

    if ($msgtype eq 'MN') {   # xFSK
      $comment .= ' (Mod. ' . $hash->{protocolObject}->checkProperty($id,'modulation','') . ', DataRate=' . $hash->{protocolObject}->checkProperty($id,'datarate','') . ', Sync Word=' . $hash->{protocolObject}->checkProperty($id,'sync','');
      if (length($knownFreqs) > 2) {
        $comment .= ', Freq. ' . $knownFreqs . 'MHz';
      }
      $comment .= ')';
    }

    $ret .= sprintf("<tr class=\"%s\"><td>%s</td><td><div>%s</div></td><td><div>%3s</div></td><td><div>%s</div></td><td><div>%s</div></td><td><div>%s</div></td><td><div>%s</div></td></tr>",$oddeven,$chkbox,$hash->{protocolObject}->checkProperty($id,'developId',''),$id,$msgtype,$hash->{protocolObject}->checkProperty($id,'clientmodule',''),$hash->{protocolObject}->checkProperty($id,'name',''),$comment);
    $oddeven= $oddeven eq "odd" ? "even" : "odd" ;

    $ret .= "\n";
  }
  $ret .= "</tbody></table>";
  return $ret;
}

############################# package main
sub SIGNALduino_querygithubreleases {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $param = {
                url        => 'https://api.github.com/repos/RFD-FHEM/SIGNALDuino/releases',
                timeout    => 5,
                hash       => $hash,                                                    # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                method     => 'GET',                                                    # Lesen von Inhalten
                header     => "User-Agent: perl_fhem\r\nAccept: application/json",      # Den Header gemaess abzufragender Daten aendern
                callback   =>  \&SIGNALduino_githubParseHttpResponse,                   # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
                command    => "queryReleases"
              };

  HttpUtils_NonblockingGet($param);                                                     # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
}

############################# package main
#return -10 = hardeware attribute is not set
sub SIGNALduino_githubParseHttpResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $hardware=AttrVal($name,'hardware',undef);

  if($err ne '')                                                                                                        # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
  {
    Log3 $name, 3, "$name: githubParseHttpResponse, error while requesting ".$param->{url}." - $err (command: $param->{command}";   # Eintrag fuers Log
    #readingsSingleUpdate($hash, 'fullResponse', 'ERROR');                                                              # Readings erzeugen
  }
  elsif($data ne '' && defined($hardware))                                                                              # wenn die Abfrage erfolgreich war ($data enthaelt die Ergebnisdaten des HTTP Aufrufes)
  {

    my $json_array = decode_json($data);
    #print  Dumper($json_array);
    if ($param->{command} eq 'queryReleases') {
      #Log3 $name, 3, "$name: githubParseHttpResponse, url ".$param->{url}." returned: $data";                          # Eintrag fuers Log

      my $releaselist='';
      if (ref($json_array) eq "ARRAY") {
        foreach my $item( @$json_array ) {
          next if (AttrVal($name,'updateChannelFW','stable') eq 'stable' && $item->{prerelease});

          #Debug ' item = '.Dumper($item);

          foreach my $asset (@{$item->{assets}})
          {
            next if ($asset->{name} !~ m/$hardware/i);
            $releaselist.=$item->{tag_name}.',' ;
            last;
          }
        }
      }

      $releaselist =~ s/,$//;
      $hash->{additionalSets}{flash} = $releaselist;
    } elsif ($param->{command} eq 'getReleaseByTag' && defined($hardware)) {
      #Debug ' json response = '.Dumper($json_array);

      my @fwfiles;
      foreach my $asset (@{$json_array->{assets}})
      {
        my %fileinfo;
        if ( $asset->{name} =~ m/$hardware/i)
        {
          $fileinfo{filename} = $asset->{name};
          $fileinfo{dlurl} = $asset->{browser_download_url};
          $fileinfo{create_date} = $asset->{created_at};
          #Debug ' firmwarefiles = '.Dumper(@fwfiles);
          push @fwfiles, \%fileinfo;

          my $set_return = SIGNALduino_Set($hash,$name,'flash',$asset->{browser_download_url}); # $hash->{SetFn
          if(defined($set_return))
          {
            $hash->{logMethod}->($name, 3, "$name: githubParseHttpResponse, Error while trying to download firmware: $set_return");
          }
          last;
        }
      }

    }
  } elsif (!defined($hardware))  {
    $hash->{logMethod}->($name, 5, "$name: githubParseHttpResponse, hardware is not defined");
  }
  # wenn
  # Damit ist die Abfrage zuende.
  # Evtl. einen InternalTimer neu schedulen
  if (defined $FW_wname)
  {
     FW_directNotify("FILTER=$name", "#FHEMWEB:$FW_wname", "location.reload('true')", '');
  }
  return 0;
}



############################# package main, candidate for fhem core utility lib
sub _limit_to_number {
  my $number = shift // return;
  return $number if ($number =~ /^[0-9]+$/);
  return ;
}


############################# package main, candidate for fhem core utility lib
sub _limit_to_hex {
  my $hex = shift // return;
  return $hex if ($hex =~ /^[0-9A-F]+$/i);
  return;
}


################################################
########## Section & functions cc1101 ##########
package cc1101;

our %cc1101_status_register = ( # for get ccreg 30-3D status registers
  '30' => 'PARTNUM       ',
  '31' => 'VERSION       ',
  '32' => 'FREQEST       ',
  '33' => 'LQI           ',
  '34' => 'RSSI          ',
  '35' => 'MARCSTATE     ',
  '36' => 'WORTIME1      ',
  '37' => 'WORTIME0      ',
  '38' => 'PKTSTATUS     ',
  '39' => 'VCO_VC_DAC    ',
  '3A' => 'TXBYTES       ',
  '3B' => 'RXBYTES       ',
  '3C' => 'RCCTRL1_STATUS',
  '3D' => 'RCCTRL0_STATUS',
);

our %cc1101_version = ( # Status register 0x31 (0xF1): VERSION – Chip ID
  '03' => 'CC1100',
  '04' => 'CC1101',
  '14' => 'CC1101',
  '05' => 'CC1100E',
  '07' => 'CC110L',
  '17' => 'CC110L',
  '08' => 'CC113L',
  '18' => 'CC113L',
  '15' => 'CC115L',
);

############################# package cc1101
#### for set function to change the patable for 433 or 868 Mhz supported
#### 433.05–434.79 MHz, 863–870 MHz
sub SetPatable {
  my ($hash,@a) = @_;
  my $paFreq = main::AttrVal($hash->{NAME},'cc1101_frequency','433');
  $paFreq = 433 if ($paFreq >= 433 && $paFreq <= 435);
  $paFreq = 868 if ($paFreq >= 863 && $paFreq <= 870);
  if ( exists($patable{$paFreq}) )
  {
    my $pa = "x" . $patable{$paFreq}{$a[1]};
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetPatable, Setting patable $paFreq $a[1] $pa");
    main::SIGNALduino_AddSendQueue($hash,$pa);
    main::SIGNALduino_WriteInit($hash);
    return ;
  } else {
    return "$hash->{NAME}: Frequency $paFreq MHz not supported (supported frequency ranges: 433.05-434.79 MHz, 863.00-870.00 MHz).";
  }
}

############################# package cc1101
sub SetRegisters  {
  my ($hash, @a) = @_;

  ## check for four hex digits
  my @nonHex = grep (!/^[0-9A-Fa-f]{4}$/,@a[1..$#a]) ;
  return "$hash->{NAME} ERROR: wrong parameter value @nonHex, only hexadecimal ​​four digits allowed" if (@nonHex);

  ## check allowed register position
  my (@wrongRegisters) = grep { !exists($cc1101_register{uc(substr($_,0,2))}) } @a[1..$#a] ;
  return "$hash->{NAME} ERROR: unknown register position ".substr($wrongRegisters[0],0,2) if (@wrongRegisters);

  $hash->{logMethod}->($hash->{NAME}, 4, "$hash->{NAME}: SetRegisters, cc1101_reg @a[1..$#a]");
  my @tmpSendQueue=();
  foreach my $argcmd (@a[1..$#a]) {
    $argcmd = sprintf("W%02X%s",hex(substr($argcmd,0,2)) + 2,substr($argcmd,2,2));
    main::SIGNALduino_AddSendQueue($hash,$argcmd);
  }
  main::SIGNALduino_WriteInit($hash);
  return ;
}

############################# package cc1101
sub SetRegistersUser  {
  my ($hash) = @_;

  my $cc1101User = main::AttrVal($hash->{NAME}, 'cc1101_reg_user', undef);

  ## look, user defined self default register values via attribute
  if (defined $cc1101User) {
    $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetRegistersUser, write CC1101 defaults from attribute");
    $cc1101User = '0815,'.$cc1101User; # for SetRegisters, value for register starts on pos 1 in array
    cc1101::SetRegisters($hash, split(',', $cc1101User) );
  }
  return ;
}

############################# package cc1101
sub SetDataRate  {
  my ($hash, @a) = @_;
  my $arg = $a[1];

  if (exists($hash->{ucCmd}->{cmd}) && $hash->{ucCmd}->{cmd} eq 'set_dataRate' && $a[0] =~ /^C10\s=\s([A-Fa-f0-9]{2})$/) {
    my ($ob1,$ob2) = cc1101::CalcDataRate($hash,$1,$hash->{ucCmd}->{arg});
    main::SIGNALduino_AddSendQueue($hash,"W12$ob1");
    main::SIGNALduino_AddSendQueue($hash,"W13$ob2");
    main::SIGNALduino_WriteInit($hash);
    return ("Setting MDMCFG4..MDMCFG3 to $ob1 $ob2 = $hash->{ucCmd}->{arg} kHz" ,undef);
  } else {
    if ($arg !~ m/\d/) { return qq[$hash->{NAME}: ERROR, unsupported DataRate value]; }
    if ($arg > 1621.83) { $arg = 1621.83; }     # max 1621.83      kBaud DataRate
    if ($arg < 0.0247955) { $arg = 0.0247955; } # min    0.0247955 kBaud DataRate

    cc1101::GetRegister($hash,10);              # Get Register 10

    $hash->{ucCmd}->{cmd}         = 'set_dataRate';
    $hash->{ucCmd}->{arg}         = $arg;                                   # ZielDataRate
    $hash->{ucCmd}->{responseSub} = \&cc1101::SetDataRate;                  # Callback auf sich selbst setzen
    $hash->{ucCmd}->{asyncOut}    = $hash->{CL} if (defined($hash->{CL}));
    $hash->{ucCmd}->{timenow}     = time();
  }
  return ;
}

############################# package cc1101
sub CalcDataRate {
  # register 0x10 3:0 & register 0x11 7:0
  my ($hash, $ob10, $dr) = @_;
  $ob10 = hex($ob10) & 0xf0;

  my $DRATE_E = ($dr*1000) * (2**20) / 26000000;
  $DRATE_E = log($DRATE_E) / log(2);
  $DRATE_E = int($DRATE_E);

  my $DRATE_M = (($dr*1000) * (2**28) / (26000000 * (2**$DRATE_E))) - 256;
  my $DRATE_Mr = main::round($DRATE_M,0);
  $DRATE_M = int($DRATE_M);

  my $datarate0 = ( ((256+$DRATE_M)*(2**($DRATE_E & 15 )))*26000000/(2**28) / 1000);
  my $DRATE_M1 = $DRATE_M + 1;
  my $DRATE_E1 = $DRATE_E;

  if ($DRATE_M1 == 256) {
    $DRATE_M1 = 0;
    $DRATE_E1++;
  }

  my $datarate1 = ( ((256+$DRATE_M1)*(2**($DRATE_E1 & 15 )))*26000000/(2**28) / 1000);

  if ($DRATE_Mr != $DRATE_M) {
    $DRATE_M = $DRATE_M1;
    $DRATE_E = $DRATE_E1;
  }

  my $ob11 = sprintf("%02x",$DRATE_M);
  $ob10 = sprintf("%02x", $ob10+$DRATE_E);

  $hash->{logMethod}->($hash->{NAME}, 5, qq[$hash->{NAME}: CalcDataRate, DataRate $hash->{ucCmd}->{arg} kHz step from $datarate0 to $datarate1 kHz]);
  $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: CalcDataRate, DataRate MDMCFG4..MDMCFG3 to $ob10 $ob11 = $hash->{ucCmd}->{arg} kHz]);

  return ($ob10,$ob11);
}

############################# package cc1101
sub SetDeviatn {
  my ($hash, @a) = @_;
  my $arg = $a[1];

  if ($arg !~ m/\d/) { return qq[$hash->{NAME}: ERROR, unsupported Deviation value]; }
  if ($arg > 380.859375) { $arg = 380.859375; }   # max 380.859375 kHz Deviation
  if ($arg < 1.586914) { $arg = 1.586914; }       # min   1.586914 kHz Deviation

  my $deviatn_val;
  my $bits;
  my $devlast = 0;
  my $bitlast = 0;

  CalcDeviatn:
  for (my $DEVIATION_E=0; $DEVIATION_E<8; $DEVIATION_E++) {
    for (my $DEVIATION_M=0; $DEVIATION_M<8; $DEVIATION_M++) {
      $deviatn_val = (8+$DEVIATION_M)*(2**$DEVIATION_E) *26000/(2**17);
      $bits = $DEVIATION_M + ($DEVIATION_E << 4);
      if ($arg > $deviatn_val) {
        $devlast = $deviatn_val;
        $bitlast = $bits;
      } else {
        if (($deviatn_val - $arg) < ($arg - $devlast)) {
          $devlast = $deviatn_val;
          $bitlast = $bits;
        }
        last CalcDeviatn;
      }
    }
  }

  my $reg15 = sprintf("%02x",$bitlast);
  my $deviatn_str =  sprintf("% 5.2f",$devlast);
  $hash->{logMethod}->($hash->{NAME}, 3, qq[$hash->{NAME}: SetDeviatn, Setting DEVIATN (15) to $reg15 = $deviatn_str kHz]);

  main::SIGNALduino_AddSendQueue($hash,"W17$reg15");
  main::SIGNALduino_WriteInit($hash);

  return;
}

############################# package cc1101
sub SetFreq  {
  my ($hash, @a) = @_;

  my $arg = $a[1];
  if (!defined($arg)) {
    $arg = main::AttrVal($hash->{NAME},'cc1101_frequency', 433.92);
  }
  my $f = $arg/26*65536;
  my $f2 = sprintf("%02x", $f / 65536);
  my $f1 = sprintf("%02x", int($f % 65536) / 256);
  my $f0 = sprintf("%02x", $f % 256);
  $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
  $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetFreq, Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz");
  main::SIGNALduino_AddSendQueue($hash,"W0F$f2");
  main::SIGNALduino_AddSendQueue($hash,"W10$f1");
  main::SIGNALduino_AddSendQueue($hash,"W11$f0");
  main::SIGNALduino_WriteInit($hash);
  return ;
}

############################# package cc1101
sub setrAmpl  {
  my ($hash, @a) = @_;
  return "$hash->{NAME}: A numerical value between 24 and 42 is expected." if($a[1] !~ m/^\d+$/ || $a[1] < 24 ||$a[1] > 42);
  my $v;
  for($v = 0; $v < @ampllist; $v++) {
    last if($ampllist[$v] > $a[1]);
  }
  $v = sprintf("%02d", $v-1);
  my $w = $ampllist[$v];
  $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: setrAmpl, Setting AGCCTRL2 (1B) to $v / $w dB");
  main::SIGNALduino_AddSendQueue($hash,"W1D$v");
  main::SIGNALduino_WriteInit($hash);
  return ;
}

############################# package cc1101
sub GetRegister {
  my ($hash, $reg) = @_;
  main::SIGNALduino_AddSendQueue($hash,'C'.$reg);
  return ;
}

############################# package cc1101
sub CalcbWidthReg {
  my ($hash, $reg10, $bWith) = @_;
  # Beispiel Rückmeldung, mit Ergebnis von Register 10: C10 = 57
  my $ob = hex($reg10) & 0x0f;
  my ($bits, $bw) = (0,0);
  OUTERLOOP:
  for (my $e = 0; $e < 4; $e++) {
    for (my $m = 0; $m < 4; $m++) {
      $bits = ($e<<6)+($m<<4);
      $bw  = int(26000/(8 * (4+$m) * (1 << $e))); # KHz
      last OUTERLOOP if($bWith >= $bw);
    }
  }
  $ob = sprintf("%02x", $ob+$bits);

  return ($ob,$bw);
}

############################# package cc1101
sub SetSens {
  my ($hash, @a) = @_;

  # Todo: Abfrage in Grep auf Array ändern
  return 'a numerical value between 4 and 16 is expected' if($a[1] !~ m/^\d+$/ || $a[1] < 4 || $a[1] > 16);
  my $w = int($a[1]/4)*4;
  my $v = sprintf("9%d",$a[1]/4-1);
  $hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: SetSens, Setting AGCCTRL0 (1D) to $v / $w dB");
  main::SIGNALduino_AddSendQueue($hash,"W1F$v");
  main::SIGNALduino_WriteInit($hash);
  return ;
}

################################################################################################
1;

=pod
=encoding utf8
=item summary    supports the same low-cost receiver for digital signals
=item summary_DE Unterstuetzt den gleichnamigen Low-Cost Empfaenger fuer digitale Signale
=begin html

<a name="SIGNALduino"></a>
<h3>SIGNALduino</h3>

<table>
  <tr><td>
  The SIGNALduino ia based on an idea from mdorenka published at <a href="http://forum.fhem.de/index.php/topic,17196.0.html">FHEM Forum</a>.<br>
  With the opensource firmware (see this <a href="https://github.com/RFD-FHEM/SIGNALduino">link</a>) it is capable to receive and send different protocols over different medias.
  <br><br>
  The following device support is currently available:<br><br>
  Wireless switches<br>
  <ul>
    <li>ITv1 & ITv3/Elro and other brands using pt2263 or arctech protocol--> uses IT.pm<br>In the ITv1 protocol is used to sent a default ITclock from 250 and it may be necessary in the IT-Modul to define the attribute ITclock
    </li>
    <li>ELV FS10 -> 10_FS10</li>
    <li>ELV FS20 -> 10_FS20</li>
  </ul>
  Temperature / humidity sensors
  <ul>
    <li>CTW600, WH1080  -> 14_SD_WS09 </li>
    <li>ELV WS-2000, La Crosse WS-7000 -> 14_CUL_WS</li>
    <li>Eurochon EAS 800z -> 14_SD_WS07</li>
    <li>FreeTec Aussenmodul NC-7344 -> 14_SD_WS07</li>
    <li>Hama TS33C, Bresser Thermo/Hygro Sensor -> 14_Hideki</li>
    <li>La Crosse WS-7035, WS-7053, WS-7054 -> 14_CUL_TX</li>
    <li>Oregon Scientific v2 and v3 Sensors  -> 41_OREGON.pm</li>
    <li>PEARL NC7159, LogiLink WS0002,GT-WT-02,AURIOL,TCM97001, TCM27 and many more -> 14_CUL_TCM97001 </li>
    <li>Temperatur / humidity sensors suppored -> 14_SD_WS07</li>
    <li>technoline WS 6750 and TX70DTH -> 14_SD_WS07</li>
  </ul>
  <br>
  It is possible to attach more than one device in order to get better reception, fhem will filter out duplicate messages. See more at the <a href="#global">global</a> section with attribute dupTimeout<br><br>
  Note: this module require the Device::SerialPort or Win32::SerialPort module. It can currently only attatched via USB.
  </td>
  </tr>
</table>
<br>


<a name="SIGNALduinodefine"></a>
<b>Define</b>
<ul><code>define &lt;name&gt; SIGNALduino &lt;device&gt; </code></ul>
USB-connected devices (SIGNALduino):<br>
<ul>
  <li>
    &lt;device&gt; specifies the serial port to communicate with the SIGNALduino. The name of the serial-device depends on your distribution, under linux the cdc_acm kernel module is responsible, and usually a /dev/ttyACM0 or /dev/ttyUSB0 device will be created. If your distribution does not have a cdc_acm module, you can force usbserial to handle the SIGNALduino by the following command:
    <ul>
      <li>modprobe usbserial</li>
      <li>vendor=0x03eb</li>
      <li>product=0x204b</li>
    </ul>
    In this case the device is most probably /dev/ttyUSB0.<br><br>
    You can also specify a baudrate if the device name contains the @ character, e.g.: /dev/ttyACM0@57600<br><br>This is also the default baudrate.<br>
    It is recommended to specify the device via a name which does not change:<br>
    e.g. via by-id devicename: /dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@57600<br>
    If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the perl module Device::SerialPort is not needed, and fhem opens the device with simple file io. This might work if the operating system uses sane defaults for the serial parameters, e.g. some Linux distributions and OSX.<br><br>
  </li>
</ul>


<a name="SIGNALduinointernals"></a>
<b>Internals</b>
<ul>
  <li><b>IDsNoDispatch</b>: Here are protocols entryls listed by their numeric id for which not communication to a logical module is enabled. To enable, look at the menu option <a href="#SIGNALduinoDetail">Display protocollist</a>.</li>
  <li><b>LASTDMSGID</b>: This shows the last dispatched Protocol ID.</li>
  <li><b>NR_CMD_LAST_H</b>: Number of messages sent within the last hour.</li>
  <li><b>RAWMSG</b>: last received RAWMSG</li>
  <li><b>cc1101_available</b>: If a CC1101 was detected, this internal is displayed with the value 1.</li>
  <li><b>version</b>: This shows the version of the SIGNALduino microcontroller.</li>
  <li><b>versionProtocols</b>: This shows the version of SIGNALduino protocol file.</li>
  <li><b>versionmodule</b>: This shows the version of the SIGNALduino FHEM module itself.</li>
</ul><br>


<a name="SIGNALduinoset"></a>
<b>Set</b>
<ul>
  <li>LaCrossePairForSec</li>
  (Only with CC1101 receiver)<br>
  Enable autocreate of new LaCrosse sensors for x seconds. If ignore_battery is not given only sensors sending the 'new battery' flag will be created.<br><br>
  <li>cc1101_bWidth / cc1101_dataRate / cc1101_deviatn / cc1101_freq / cc1101_patable / cc1101_rAmpl / cc1101_reg / cc1101_sens<br>
    (Only with CC1101 receiver)<br>
    Set the sduino frequency / bandwidth / PA table / receiver-amplitude / sensitivity<br>

    Use it with care, it may destroy your hardware and it even may be
    illegal to do so. Note: The parameters used for RFR transmission are
    not affected.<br>
    <ul>
      <a name="cc1101_bWidth"></a>
      <li><code>cc1101_bWidth</code> can be set to values between 58 kHz and 812 kHz. Large values are susceptible to interference, but make possible to receive inaccurately calibrated transmitters. It affects tranmission too. Default is 325 kHz.
      </li>
      <a name="cc1101_dataRate"></a>
      <li><code>cc1101_dataRate</code> , can be set to values ​​between 0.0247955 kBaud and 1621.83 kBaud.
      </li>
      <a name="cc1101_deviatn"></a>
      <li><code>cc1101_deviatn</code> , can be set to values ​​between 1.586914 kHz and 380.859375 kHz.
      </li>
      <a name="cc1101_freq"></a>
      <li><code>cc1101_freq</code> sets both the reception and transmission frequency. Note: Although the CC1101 can be set to frequencies between 315 and 915 MHz, the antenna interface and the antenna is tuned for exactly one frequency. Default is 433.920 MHz (or 868.350 MHz). If not set, frequency from <code>cc1101_frequency</code> will be used.
      </li>
      <a name="cc1101_patable"></a>
      <li><code>cc1101_patable</code> change the PA table (power amplification for RF sending)
      </li>
      <a name="cc1101_rAmpl"></a>
      <li><code>cc1101_rAmpl</code> is receiver amplification, with values between 24 and 42 dB. Bigger values allow reception of weak signals. Default is 42.
      </li>
      <a name="cc1101_reg"></a>
      <li><code>cc1101_reg</code> You can set multiple registers at one. Specify the register with its two digit hex code followed by the register value separate multiple registers via space.
      </li>
      <a name="cc1101_sens"></a>
      <li><code>cc1101_sens</code> is the decision boundary between the on and off values, and it is 4, 8, 12 or 16 dB.  Smaller values allow reception of less clear signals. Default is 4 dB.
      </li>
    </ul>
  </li><br>
  <a name="close"></a>
  <li>close<br>
    Closes the connection to the device.
  </li><br>
  <a name="disableMessagetype"></a>
  <li>disableMessagetype<br>
    Allows you to disable the message processing for
    <ul>
      <li>messages with sync (syncedMS)</li>
      <li>messages without a sync pulse (unsyncedMU)</li>
      <li>manchester encoded messages (manchesterMC)</li>
    </ul>
    The new state will be saved into the eeprom of your arduino.
  </li><br>
  <a name="enableMessagetype"></a>
  <li>enableMessagetype<br>
    Allows you to enable the message processing for
    <ul>
      <li>messages with sync (syncedMS)</li>
      <li>messages without a sync pulse (unsyncedMU)</li>
      <li>manchester encoded messages (manchesterMC)</li>
    </ul>
    The new state will be saved into the eeprom of your arduino.
  </li><br>
  <a name="flash"></a>
  <li>flash [hexFile|url]<br>
    The SIGNALduino needs the right firmware to be able to receive and deliver the sensor data to fhem. In addition to the way using the arduino IDE to flash the firmware into the SIGNALduino this provides a way to flash it directly from FHEM. You can specify a file on your fhem server or specify a url from which the firmware is downloaded.<br><br>
    There are some requirements:
    <ul>
      <li>avrdude must be installed on the host<br> On a Raspberry PI this can be done with: sudo apt-get install avrdude</li>
      <li>the hardware attribute must be set if using any other hardware as an Arduino nano<br> This attribute defines the command, that gets sent to avrdude to flash the uC.</li>
      <li>If you encounter a problem, look into the logfile</li>
    </ul><br>
    Example:
    <ul>
      <li>flash via Version Name: Versions are provided via get availableFirmware</li>
      <li>flash via hexFile: <code>set sduino flash ./FHEM/firmware/SIGNALduino_mega2560.hex</code></li>
      <li>flash via url for Nano with CC1101: <code>set sduino flash https://github.com/RFD-FHEM/SIGNALDuino/releases/download/3.3.1-RC7/SIGNALDuino_nanocc1101.hex</code></li>
    </ul><br>
    <i><u>note model radino:</u></i>
    <ul>
      <li>Sometimes there can be problems flashing radino on Linux. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Here in the wiki under point "radino & Linux" is a patch!</a>
      </li>
      <li>If the Radino is defined in this way <code>/dev/ttyACM0</code>, the flashing of the firmware should be done automatically. If this fails, the boot loader must be activated manually:
      </li>
      <li>To activate the bootloader of the radino there are 2 variants.
        <ul>
          <li>1) modules that contain a BSL-button:
            <ul>
              <li>apply supply voltage</li>
              <li>press & hold BSL- and RESET-Button</li>
              <li>release RESET-button, release BSL-button</li>
              <li>(repeat these steps if your radino doesn't enter bootloader mode right away.)</li>
            </ul>
          </li>
          <li>2) force bootloader:
            <ul>
              <li>pressing reset button twice</li>
            </ul>
          </li>
        </ul>
        In bootloader mode, the radino gets a different USB ID. This must be entered in the "flashCommand" attribute.<br>
        If the bootloader is enabled, it signals with a flashing LED. Then you have 8 seconds to flash.
      </li>
    </ul>
  </li><br>

  <a name="raw"></a>
  <li>raw<br>
    Issue a SIGNALduino firmware command, without waiting data returned by
    the SIGNALduino. See the SIGNALduino firmware code  for details on SIGNALduino
    commands. With this line, you can send almost any signal via a transmitter connected

    To send some raw data look at these examples:
    P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional)<br>
    <br>Example 1: <code>set sduino raw SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=0302030;</code>  sends the data in raw mode 3 times repeated
    <br>Example 2: <code>set sduino raw SM;R=3;P0=500;C=250;D=A4F7FDDE;</code>  sends the data manchester encoded with a clock of 250uS
    <br>Example 3: <code>set sduino raw SC;R=3;SR;P0=5000;SM;P0=500;C=250;D=A4F7FDDE;</code>  sends a combined message of raw and manchester encoded repeated 3 times
    <br>Example 4: <code>set sduino raw SN;R=3;D=9A46036AC8D3923EAEB470AB;</code>  sends a xFSK message of raw and repeated 3 times
    <ul><br>
      <b>note: The wrong use of the upcoming options can lead to malfunctions of the SIGNALduino!</b><br><br>
      <li>CER -> turn on data compression (config: Mred=1)</li>
      <li>CDR -> disable data compression (config: Mred=0)</li><br>

      <u>Register commands for a CC1101</u>
      <li>e -> default settings</li>
      <li>x -> returns the ccpatable</li>
      <li>C -> reads a value from the CC1101 register<br>
        <ul>example: <code>set sduino raw C04</code> reads the value from register address 0x04</ul>
      </li>
      <li>W -> writes a value to the EEPROM and the CC1101 register <u>(note: The EEPROM address has an offset of 2)</u><br>
        <ul>example 1: <code>set sduino raw W041D</code> write 1D to register 0x02</ul>
        <ul>example 2: <code>set sduino raw W041D#W0604</code> write 1D to register 0x02 and write 04 to register 0x04</ul>
      </li>
      <br>
      <u>other commands from uC</u>
      <li>? -> returns the available commands</li>
      <li>P -> sends a PING</li>
      <li>R -> returns the free RAM</li>
      <li>V -> returns the version</li>
      <li>s -> returns the status</li>
      <li>t -> returns the uptime</li>
    </ul><br>
  </li>

  <a name="reset"></a>
  <li>reset<br>
    This will do a reset of the usb port and normaly causes to reset the uC connected.
  </li><br>

  <a name="sendMsg"></a>
  <li>sendMsg<br>
    This command will create the needed instructions for sending raw data via the signalduino. Insteaf of specifying the signaldata by your own you specify
    a protocol and the bits you want to send. The command will generate the needed command, that the signalduino will send this.
    It is also supported to specify the data in hex. prepend 0x in front of the data part.
    <br><br>
    Please note, that this command will work only for MU or MS protocols. You can't transmit manchester data this way.
    <br><br>
    Input args are:
    <p>
      <ul>
        <li>P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional)
          <br>Example binarydata: <code>set sduino sendMsg P0#0101#R3#C500</code>
          <br>Will generate the raw send command for the message 0101 with protocol 0 and instruct the arduino to send this three times and the clock is 500.
          <br>SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=03020302;
        </li>
      </ul><br>
      <ul>
        <li>P<protocol id>#0xhexdata#R<num of repeats>#C<optional clock>    (#C is optional)
          <br>Example 0xhexdata: <code>set sduino sendMsg P29#0xF7E#R4</code>
          <br>Generates the raw send command with the hex message F7E with protocl id 29 . The message will be send four times.
          <br>SR;R=4;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=01212121213421212121212134;
        </li>
      </ul><br>
      <ul>
        <li>P<protocol id>#0xhexdata#R<num of repeats>#C<optional taktrate>#F<optional frequency>    (#C #F is optional)
          <br>Example 0xhexdata: <code>set sduino sendMsg P36#0xF7#R6#Fxxxxxxxxxx</code> (xxxxxxxxxx = register from CC1101)
          <br>Generates the raw send command with the hex message F7 with protocl id 36 . The message will be send six times.
          <br>SR;R=6;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=012323232324232323;F= (register from CC1101);
        </li>
      </ul>
    </p>
  </li>
</ul>


<a name="SIGNALduinoget"></a>
<b>Get</b>
<ul>
  <a name="availableFirmware"></a>
  <li>availableFirmware<br>
    Retrieves available firmware versions from github and displays them in set flash command.
  </li><br>
  <a name="ccconf"></a>
  <li>ccconf<br>
    Read some CUL radio-chip (cc1101) registers (frequency, bandwidth, etc.),
    and display them in human readable form.<br>
    Only with cc1101 receiver.
  </li><br>
  <a name="ccpatable"></a>
  <li>ccpatable<br>
    read cc1101 PA table (power amplification for RF sending)<br>
    Only with cc1101 receiver.
  </li><br>
  <a name="ccreg"></a>
  <li>ccreg<br>
    read cc1101 registers (99 reads all cc1101 registers)<br>
    Only with cc1101 receiver.
  </li><br>
  <a name="close"></a>
  <li>close<br>
    Close the connection to the SIGNALduino.
  </li><br>
  <a name="cmds"></a>
  <li>cmds<br>
    Depending on the firmware installed, SIGNALduinos have a different set of
    possible commands. Please refer to the sourcecode of the firmware of your
    SIGNALduino to interpret the response of this command. See also the raw-command.
  </li><br>
  <a name="config"></a>
  <li>config<br>
    Displays the configuration of the SIGNALduino protocol category. | example: <code>MS=1;MU=1;MC=1;Mred=0</code>
  </li><br>
  <a name="freeram"></a>
  <li>freeram<br>
    Displays the free RAM.
  </li><br>
  <a name="ping"></a>
  <li>ping<br>
    Check the communication with the SIGNALduino.
  </li><br>
  <a name="rawmsg"></a>
  <li>rawmsg<br>
    Processes messages (MS, MC, MU, ...) as if they were received by the SIGNALduino. The get raw command does not send any commands to the microcontroller!<br><br>
    For example, this message would:
    <code>MS;P0=-7871;P2=-1960;P3=578;P4=-3954;D=030323232323434343434323232323234343434323234343234343234343232323432323232323232343234;CP=3;SP=0;R=0;m=0;</code><br>
    after executing the command several times, create a sensor SD_WS_33_TH_1.
  </li><br>
  <a name="uptime"></a>
  <li>uptime<br>
    Displays information how long the SIGNALduino is running. A FHEM reboot resets the timer.
  </li><br>
  <a name="version"></a>
  <li>version<br>
    return the SIGNALduino firmware version
  </li><br>
</ul>


<a name="SIGNALduinoattr"></a>
<b>Attributes</b>
<ul>
  <li><a href="#addvaltrigger">addvaltrigger</a><br>
    Create triggers for additional device values. Right now these are RSSI, RAWMSG, DMSG and ID.
  </li><br>
  <a name="blacklist_IDs"></a>
  <li>blacklist_IDs<br>
    The blacklist works only if a whitelist not exist.
  </li><br>
  <a name="cc1101_frequency"></a>
  <li>cc1101_frequency<br>
    Specify the frequency of your SIGNALduino. Default is 433 Mhz.<br>
    Since the PA table values are frequency-dependent,the specified frequency will be used.
  </li><br>
  <a name="cc1101_reg_user"></a>
  <li>cc1101_reg_user<br>
    Storage space for individual register configurations or values. One or more values ​​can be saved.<br>
    <u>note:</u> The value consists of the register address followed by the value. Multiple values ​​are separated by commas. example: 04D3,0591
  </li><br>
  <a name="debug"></a>
  <li>debug<br>
    This will bring the module in a very verbose debug output. Usefull to find new signals and verify if the demodulation works correctly.
  </li><br>
  <a name="development"></a>
  <li>development<br>
    The development attribute is only available in development version of this Module for backwart compatibility. Use the whitelistIDs Attribute instead. Setting this attribute to 1 will enable all protocols which are flagged with developID=Y.
    <br>
    To check which protocols are flagged, open via FHEM webinterface in the section "Information menu" the option "Display protocollist". Look at the column "dev" where the flags are noted.
    <br><br>
  </li>
  <li><a href="#do_not_notify">do_not_notify</a></li><br>
  <a name="doubleMsgCheck_IDs"></a>
  <li>doubleMsgCheck_IDs<br>
    This attribute allows it, to specify protocols which must be received two equal messages to call dispatch to the modules.<br>
    You can specify multiple IDs wih a colon : 0,3,7,12<br>
  </li><br>
  <li><a href="#attrdummy">dummy</a></li><br>
  <a name="eventlogging"></a>
  <li>eventlogging<br>
    With this attribute you can control if every logmessage is also provided as event. This allows to generate event for every log messages.
    Set this to 0 and logmessages are only saved to the global fhem logfile if the loglevel is higher or equal to the verbose attribute.
    Set this to 1 and every logmessages is also dispatched as event. This allows you to log the events in a seperate logfile.
  </li><br>
  <a name="flashCommand"></a>
  <li>flashCommand<br>
    This is the command, that is executed to performa the firmware flash. Do not edit, if you don't know what you are doing.<br>
    If the attribute not defined, it uses the default settings. <b>If the user defines the attribute manually, the system uses the specifications!</b><br>
    <ul>
      <li>default for nano, nanoCC1101, miniculCC1101, promini: <code>avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
      <li>default for radinoCC1101: <code>avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
    </ul>
    It contains some place-holders that automatically get filled with the according values:<br>
    <ul>
      <li>[BAUDRATE]<br>
        is the speed (e.g. 57600)
      </li>
      <li>[PORT]<br>
        is the port the Signalduino is connectd to (e.g. /dev/ttyUSB0) and will be used from the defenition
      </li>
      <li>[HEXFILE]<br>
        is the .hex file that shall get flashed. There are three options (applied in this order):<br>
        - passed in set flash as first argument<br>
        - taken from the hexFile attribute<br>
        - the default value defined in the module<br>
      </li>
      <li>[LOGFILE]<br>
        The logfile that collects information about the flash process. It gets displayed in FHEM after finishing the flash process
      </li>
    </ul><br>
    <u><i>note:</u></i> ! Sometimes there can be problems flashing radino on Linux. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Here in the wiki under the point "radino & Linux" is a patch!</a>
  </li><br>
  <a name="SIGNALDuino_hardware"></a>
  <li>hardware<br>
    Currently, there are serval hardware options with different receiver options available.
    The simple single wire option,  consists of a single wire connected receiver and a single wire connected transmitter which are connected over a single digital port with the microcontroller. The receiver only sends data and the transmitter receives only from the microcontroller.
    The other option consists of the cc1101 (sub 1 GHZ) chip, which can transmit and receiver. It's a transceiver which is connected via spi.
    ESP8266 hardware type, currently doesn't support flashing out of the modu and needs at leat 1 MB of flash.
    <ul>
      <li>ESP32: ESP32 with simple single wire receiver</li>
      <li>ESP32cc1101: ESP32 with CC1101 (spi connected) receiver</li>
      <li>ESP8266: ESP8266 with simple single wire receiver</li>
      <li>ESP8266cc1101: ESP8266 with CC1101 (spi connected) receiver</li>
      <li>MAPLEMINI_F103CB: MapleMini F103CB (STM32 family) with simple single wire receiver</li>
      <li>MAPLEMINI_F103CBcc1101: MapleMini F103CB (STM32 family) with CC1101 (spi connected) receiver</li>
      <li>miniculCC1101: Arduino pro Mini with CC110x (spi connected) receiver and cables as a minicul</li>
      <li>nano: Arduino Nano 328 with simple single wired receiver</li>
      <li>nanoCC1101: Arduino Nano 328 with CC110x (spi connected) receiver</li>
      <li>promini: Arduino Pro Mini 328 with simple single receiver </li>
      <li>radinoCC1101: Arduino compatible radino with cc1101 (spi connected) receiver</li>
    </ul>
  </li><br>
  <a name="longids"></a>
  <li>longids<br>
    Comma separated list of device-types for SIGNALduino that should be handled using long IDs. This additional ID allows it to differentiate some weather sensors, if they are sending on the same channel. Therfor a random generated id is added. If you choose to use longids, then you'll have to define a different device after battery change.<br>
    Default is to not to use long IDs for all devices.
    <br><br>
    Examples:<PRE>
      # Do not use any long IDs for any devices:
      attr sduino longids 0
      # Use any long IDs for all devices (this is default):
      attr sduino longids 1
      # Use longids for BTHR918N devices.
      # Will generate devices names like BTHR918N_f3.
      attr sduino longids BTHR918N
    </PRE>
  </li>
  <a name="maxMuMsgRepeat"></a>
  <li>maxMuMsgRepeat<br>
    MU signals can contain multiple repeats of the same message. The results are all send to a logical module. You can limit the number of scanned repetitions. Defaukt is 4, so after found 4 repeats, the demoduation is aborted.
  </li><br>
  <a name="minsecs"></a>
  <li>minsecs<br>
    This is a very special attribute. It is provided to other modules. minsecs should act like a threshold. All logic must be done in the logical module.
    If specified, then supported modules will discard new messages if minsecs isn't past.
  </li><br>
  <a name="noMsgVerbose"></a>
  <li>noMsgVerbose<br>
    With this attribute you can control the logging of debug messages from the io device.
    If set to 3, this messages are logged if global verbose is set to 3 or higher.
  </li><br>
  <a name="rawmsgEvent"></a>
  <li>rawmsgEvent<br>
    When set to "1" received raw messages triggers events
  </li><br>
  <a name="rfmode"></a>
  <li>rfmode<br>
    Configures the RF transceiver of the SIGNALduino (CC1101). The available arguments:
    <ul>
      <li>Avantek<br>
        Modulation 2-FSK, Datarate=50.087 kbps, Sync Word=0869, FIFO-THR=8 Byte, Frequency 433.3 MHz
        <ul><small>Example: AVANTEK Wireless Digital Door Bell</small></ul>
      </li>
      <li>Bresser_5in1<br>
        Modulation 2-FSK, Datarate=8.23 kbps, Sync Word=2DD4, Packet Length=26 Byte, Frequency 868.3 MHz
        <ul><small>Example: BRESSER 5-in-1 weather center, BRESSER rain gauge, Fody E42, Fody E43</small></ul>
      </li>
      <li>Bresser_6in1<br>
        modulation 2-FSK, Datarate=8.23 kbps, Sync Word=2DD4, FIFO-THR=20 Byte, frequency 868.3 MHz
      </li>
      <li>Bresser_7in1<br>
        modulation 2-FSK, Datarate=8.23 kbps, Sync Word=2DD4, Packet Length=22 Byte, frequency 868.3 MHz
      </li>
      <li>Fine_Offset_WH51_434<br>
        Modulation 2-FSK, Datarate=17.26 kbps, Sync Word=2DD4, Packet Length=14 Byte, Frequency 433.92 MHz
        <ul><small>Example: Soil moisture sensor Fine Offset WH51, ECOWITT WH51, MISOL/1, Froggit DP100</small></ul>
      </li>
      <li>Fine_Offset_WH51_868<br>
        Modulation 2-FSK, Datarate=17.26 kbps, Sync Word=2DD4, Packet Length=14 Byte, Frequency 868.35 MHz
        <ul><small>Example: Soil moisture sensor Fine Offset WH51, ECOWITT WH51, MISOL/1, Froggit DP100</small></ul>
      </li>
      <li>Fine_Offset_WH57_434<br>
        Modulation 2-FSK, Datarate=17.26 kbps, Sync Word=2DD4, Packet Length=9 Byte, Frequency 433.92 MHz
        <ul><small>Example: Thunder and lightning sensor Fine Offset WH57, Froggit DP60, Ambient Weather WH31L</small></ul>
      </li>
      <li>Fine_Offset_WH57_868<br>
        Modulation 2-FSK, Datarate=17.26 kbps, Sync Word=2DD4, Packet Length= Byte, Frequency 868.35 MHz
        <ul><small>Example: Thunder and lightning sensor Fine Offset WH57, Froggit DP60, Ambient Weather WH31L</small></ul>
      </li>
      <li>KOPP_FC<br>
        modulation GFSK, Datarate=4.7855 kbps, Sync Word=AA54, frequency 868.3MHz
      </li>
      <li>Lacrosse_mode1<br>
        modulation 2-FSK, Datarate=17.25769 kbps, Sync Word=2DD4, frequency 868.3MHz<br>
        <ul><small>example: TX25-IT, TX27-IT, TX29-IT, TX29DTH-IT, TX37, 30.3143.IT, 30.3144.IT</small></ul>
      </li>
      <li>Lacrosse_mode2<br>
        modulation 2-FSK, Datarate=9.579 kbps, Sync Word=2DD4, frequency 868.3MHz<br>
        <ul><small>example: TX35TH-IT, TX35DTH-IT, TX38-IT, 30.3155WD, 30.3156WD</small></ul>
      </li>
      <li>PCA301<br>
        modulation 2-FSK, Datarate=6.62041 kbps, Sync Word=2DD4, frequency 868.950 MHz
      </li>
      <li>Rojaflex<br>
        modulation GFSK, Datarate=9.99 kbps, Sync Word=D391D391, frequency 433.920 MHz
      </li>
      <li>SlowRF<br>
        modulation ASK/OOK, <b>loads the standard setting from the uC</b>
      </li>
    </ul>
  </li><br>
  <a name="suppressDeviceRawmsg"></a>
  <li>suppressDeviceRawmsg<br>
    When set to 1, the internal "RAWMSG" will not be updated with the received messages
  </li><br>
  <a name="updateChannelFW"></a>
  <li>updateChannelFW<br>
    The module can search for new firmware versions (<a href="https://github.com/RFD-FHEM/SIGNALDuino/releases">SIGNALDuino</a> and <a href="https://github.com/RFD-FHEM/SIGNALESP/releases">SIGNALESP</a>). Depending on your choice, only stable versions are displayed or also prereleases are available for flash. The option testing does also provide the stable ones.
    <ul>
      <li>stable: only versions marked as stable are available. These releases are provided very infrequently</li>
      <li>testing: These versions needs some verifications and are provided in shorter intervals</li>
    </ul>
    <br>Reload the available Firmware via get availableFirmware manually.
  </li><br>
  <a name="whitelist_IDs"></a>
  <li>whitelist_IDs<br>
    This attribute allows it, to specify whichs protocos are considured from this module. Protocols which are not considured, will not generate logmessages or events. They are then completly ignored. This makes it possible to lower ressource usage and give some better clearnes in the logs. You can specify multiple whitelistIDs wih a colon : 0,3,7,12<br> With a # at the beginnging whitelistIDs can be deactivated.
    <br>
    Not using this attribute or deactivate it, will process all stable protocol entrys. Protocols which are under development, must be activated explicit via this Attribute.
  </li><br>
  <a name="WS09_CRCAUS"></a>
  <li>WS09_CRCAUS<br>
    <ul>
      <li>0: CRC-Check WH1080 CRC = 0  on, default</li>
      <li>2: CRC = 49 (x031) WH1080, set OK</li>
    </ul>
  </li><br>
  <a name="MatchList"></a>
  <li>MatchList<br>
  This attribute adds additional items to the module matchlist. Items has to be described in a PERL Hash format:
  <ul>
    <li>Format: { 'number:module' => 'protocol-pattern' , 'nextNumber:nextModule' => 'protocol-pattern' , ... }</li>
    <li>Example: { '34:MyModule' => '^u98#.{8}' , '35:MyModule2' => '^u99#.{10}' }</li>
  </ul>
  </li><br>
</ul>


<a name="SIGNALduinoDetail"></a>
<b>Information menu</b>
<ul>
  <a name="Display protocollist"></a>
  <li>Display protocollist<br>
    Shows the current implemented protocols from the SIGNALduino and to what logical FHEM Modul data is sent.<br>
    Additional there is an checkbox symbol, which shows you if a protocol will be processed. This changes the Attribute whitlistIDs for you in the background. The attributes whitelistIDs and blacklistIDs affects this state.
    Protocols which are flagged in the row <code>dev</code>, are under development
    <ul>
      <li>If a row is flagged via 'm', then the logical module which provides you with an interface is still under development. Per default, these protocols will not send data to logcial module. To allow communication to a logical module you have to enable the protocol.
      </li>
      <li>If a row is flagged via 'p', then this protocol entry is reserved or in early development state.</li>
      <li>If a row is flalged via 'y' then this protocol isn't fully tested or reviewed.</li>
    </ul>
    <br>
    If you are using blacklistIDs, then you also can not activate them via the button, delete the attribute blacklistIDs if you want to control enabled protocols via this menu.
  </li><br>
</ul>

=end html
=begin html_DE

<a name="SIGNALduino"></a>
<h3>SIGNALduino</h3>

<table>
  <tr><td>
  Der <a href="https://wiki.fhem.de/wiki/SIGNALduino">SIGNALduino</a> ist basierend auf einer Idee von "mdorenka" und ver&ouml;ffentlicht im <a href="http://forum.fhem.de/index.php/topic,17196.0.html">FHEM Forum</a>.<br>
  Mit der OpenSource-Firmware (<a href="https://github.com/RFD-FHEM/SIGNALduino">SIGNALDuino</a> und <a href="https://github.com/RFD-FHEM/SIGNALESP/releases">SIGNALESP</a>) ist dieser f&auml;hig zum Empfangen und Senden verschiedener Protokolle auf 433 und 868 Mhz.
  <br><br>
  Folgende Ger&auml;te werden zur Zeit unterst&uuml;tzt:
  <br><br>
  Funk-Schalter<br>
  <ul>
    <li>ITv1 & ITv3/Elro und andere Marken mit dem pt2263-Chip oder welche das arctech Protokoll nutzen --> IT.pm<br> Das ITv1 Protokoll benutzt einen Standard ITclock von 250 und es kann vorkommen, das in dem IT-Modul das Attribut "ITclock" zu setzen ist.
    </li>
    <li>ELV FS10 -> 10_FS10
    </li>
    <li>ELV FS20 -> 10_FS20
    </li>
  </ul>
  Temperatur-, Luftfeuchtigkeits-, Luftdruck-, Helligkeits-, Regen- und Windsensoren
  <ul>
    <li>CTW600, WH1080 -> 14_SD_WS09.pm</li>
    <li>ELV WS-2000, La Crosse WS-7000 -> 14_CUL_WS</li>
    <li>Eurochon EAS 800z -> 14_SD_WS07.pm</li>
    <li>FreeTec Aussenmodul NC-7344 -> 14_SD_WS07.pm</li>
    <li>Hama TS33C, Bresser Thermo/Hygro Sensoren -> 14_Hideki.pm</li>
    <li>La Crosse WS-7035, WS-7053, WS-7054 -> 14_CUL_TX</li>
    <li>Oregon Scientific v2 und v3 Sensoren  -> 41_OREGON.pm</li>
    <li>PEARL NC7159, LogiLink WS0002,GT-WT-02,AURIOL,TCM97001, TCM27 und viele anderen -> 14_CUL_TCM97001.pm</li>
    <li>Temperatur / Feuchtigkeits Sensoren unterst&uuml;tzt -> 14_SD_WS07.pm</li>
    <li>technoline WS 6750 und TX70DTH -> 14_SD_WS07.pm</li>
  </ul>
  <br>
  Es ist m&ouml;glich, mehr als ein Ger&auml;t anzuschließen, um beispielsweise besseren Empfang zu erhalten. FHEM wird doppelte Nachrichten herausfiltern.
  Mehr dazu im dem <a href="#global">global</a> Abschnitt unter dem Attribut dupTimeout<br><br>
  Hinweis: Dieses Modul erfordert das Device::SerialPort oder Win32::SerialPort
  Modul. Es kann derzeit nur &uuml;ber USB angeschlossen werden.
  </td>
  </tr>
</table>
<br>


<a name="SIGNALduinodefine"></a>
<b>Define</b>
<ul><code>define &lt;name&gt; SIGNALduino &lt;device&gt; </code></ul>
USB-connected devices (SIGNALduino):<br>
<ul>
  <li> &lt;device&gt; spezifiziert den seriellen Port f&uuml;r die Kommunikation mit dem SIGNALduino.
    Der Name des seriellen Ger&auml;ts h&auml;ngt von Ihrer  Distribution ab. In Linux ist das <code>cdc_acm</code> Kernel_Modul daf&uuml;r verantwortlich und es wird ein <code>/dev/ttyACM0</code> oder <code>/dev/ttyUSB0</code> Ger&auml;t angelegt. Wenn deine Distribution kein <code>cdc_acm</code> Module besitzt, kannst du usbserial nutzen um den SIGNALduino zu betreiben mit folgenden Kommandos:
    <ul>
      <li>modprobe usbserial</li>
      <li>vendor=0x03eb</li>
      <li>product=0x204b</li>
    </ul>
    In diesem Fall ist das Ger&auml;t h&ouml;chstwahrscheinlich <code>/dev/ttyUSB0</code>.<br><br>

    Sie k&ouml;nnen auch eine Baudrate angeben, wenn der Ger&auml;tename das @ enth&auml;lt, Beispiel: <code>/dev/ttyACM0@57600</code><br>Dies ist auch die Standard-Baudrate.<br><br>
    Es wird empfohlen, das Ger&auml;t &uuml;ber einen Namen anzugeben, der sich nicht &auml;ndert. Beispiel via by-id devicename: <code>/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@57600</code><br>
    Wenn die Baudrate "directio" (Bsp: <code>/dev/ttyACM0@directio</code>), dann benutzt das Perl Modul nicht Device::SerialPort und FHEM &ouml;ffnet das Ger&auml;t mit einem file io. Dies kann funktionieren, wenn das Betriebssystem die Standardwerte f&uuml;r die seriellen Parameter verwendet. Bsp: einige Linux Distributionen und
    OSX.<br><br>
  </li>
</ul>


<a name="SIGNALduinointernals"></a>
<b>Internals</b>
<ul>
  <li>
    <b>IDsNoDispatch</b>: Hier werden Protokolleintr&auml;ge mit ihrer numerischen ID aufgelistet, f&uuml;r welche keine Weitergabe von Daten an logische Module aktiviert wurde. Um die Weitergabe zu aktivieren, kann die Men&uuml;option <a href="#SIGNALduinoDetail">Display protocollist</a> verwendet werden.
  </li>
  <li>
    <b>LASTDMSGID</b>: Hier wird die zuletzt dispatchte Protocol ID angezeigt.
  </li>
  <li>
    <b>NR_CMD_LAST_H</b>: Anzahl der gesendeten Nachrichten innerhalb der letzten Stunde.
  </li>
  <li>
    <b>RAWMSG</b>: zuletzt empfangene RAWMSG
  </li>
  <li>
    <b>cc1101_available</b>: Wenn ein CC1101 erkannt wurde, so wird dieses Internal angezeigt mit dem Wert 1.
  </li>
  <li>
    <b>version</b>: Hier wird die Version des SIGNALduino microcontrollers angezeigt.
  </li>
  <li>
    <b>versionProtocols</b>: Hier wird die Version der SIGNALduino Protokolldatei angezeigt.
  </li>
  <li>
    <b>versionmodule</b>: Hier wird die Version des SIGNALduino FHEM Modules selbst angezeigt.
  </li>
</ul><br>


<a name="SIGNALduinoset"></a>
<b>Set</b>
<ul>
  <li>LaCrossePairForSec</li>
  (NUR bei Verwendung eines cc110x Funk-Moduls)<br>
  Aktivieren Sie die automatische Erstellung neuer LaCrosse-Sensoren für "x" Sekunden. Wenn ignore_battery nicht angegeben wird, werden nur Sensoren erstellt, die das Flag 'Neue Batterie' senden.<br><br>
  <li>
    cc1101_bWidth / cc1101_dataRate / cc1101_deviatn / cc1101_freq / cc1101_patable / cc1101_rAmpl / cc1101_reg / cc1101_sens <br>
    (NUR bei Verwendung eines cc110x Funk-Moduls)<br><br>
    Stellt die SIGNALduino-Frequenz / Bandbreite / PA-Tabelle / Empf&auml;nger-Amplitude / Empfindlichkeit ein.<br>
    Verwenden Sie es mit Vorsicht. Es kann Ihre Hardware zerst&ouml;ren und es kann sogar illegal sein, dies zu tun.<br>
    Hinweis: Die f&uuml;r die RFR-&Uuml;bertragung verwendeten Parameter sind nicht betroffen.<br>
  </li>
  <ul>
    <a name="cc1101_bWidth"></a>
    <li><code>cc1101_bWidth</code> , kann auf Werte zwischen 58 kHz und 812 kHz eingestellt werden. Große Werte sind st&ouml;ranf&auml;llig, erm&ouml;glichen jedoch den Empfang von ungenau kalibrierten Sendern. Es wirkt sich auch auf die &Uuml;bertragung aus. Standard ist 325 kHz.
    </li>
    <a name="cc1101_dataRate"></a>
    <li><code>cc1101_dataRate</code> , kann auf Werte zwischen 0.0247955 kBaud und 1621.83 kBaud eingestellt werden.
    </li>
    <a name="cc1101_deviatn"></a>
    <li><code>cc1101_deviatn</code> , kann auf Werte zwischen 1.586914 kHz und 380.859375 kHz eingestellt werden.
    </li>
    <a name="cc1101_freq"></a>
    <li><code>cc1101_freq</code> , legt sowohl die Empfangsfrequenz als auch die &Uuml;bertragungsfrequenz fest.<br>
      Hinweis: Obwohl der CC1101 auf Frequenzen zwischen 315 und 915 MHz eingestellt werden kann, ist die Antennenschnittstelle und die Antenne auf genau eine Frequenz abgestimmt. Standard ist 433.920 MHz (oder 868.350 MHz). Wenn keine Frequenz angegeben wird, dann wird die Frequenz aus dem Attribut <code>cc1101_frequency</code> geholt.
    </li>
    <a name="cc1101_patable"></a>
    <li><code>cc1101_patable</code> , &Auml;nderung der PA-Tabelle (Leistungsverst&auml;rkung f&uuml;r HF-Senden)
    </li>
    <a name="cc1101_rAmpl"></a>
    <li><code>cc1101_rAmpl</code> , ist die Empf&auml;ngerverst&auml;rkung mit Werten zwischen 24 und 42 dB. Gr&ouml;ßere Werte erlauben den Empfang schwacher Signale. Der Standardwert ist 42.
    </li>
    <a name="cc1101_reg"></a>
    <li><code>cc1101_reg</code> Es k&ouml;nnen mehrere Register auf einmal gesetzt werden. Das Register wird &uuml;ber seinen zweistelligen Hexadezimalwert angegeben, gefolgt von einem zweistelligen Wert. Mehrere Register werden via Leerzeichen getrennt angegeben
    </li>
    <a name="cc1101_sens"></a>
    <li><code>cc1101_sens</code> , ist die Entscheidungsgrenze zwischen den Ein- und Aus-Werten und betr&auml;gt 4, 8, 12 oder 16 dB. Kleinere Werte erlauben den Empfang von weniger klaren Signalen. Standard ist 4 dB.
    </li>
  </ul>
  <br>
  <a name="close"></a>
  <li>close<br>
    Beendet die Verbindung zum Ger&auml;t.
  </li><br>
  <a name="disableMessagetype"></a>
  <li>
    disableMessagetype<br>
    Erm&ouml;glicht das Deaktivieren der Nachrichtenverarbeitung f&uuml;r
    <ul>
      <li>Nachrichten mit sync (syncedMS)</li>
      <li>Nachrichten ohne einen sync pulse (unsyncedMU)</li>
      <li>Manchester codierte Nachrichten (manchesterMC)</li>
    </ul>
    Der neue Status wird in den eeprom vom Arduino geschrieben.
  </li><br>
  <a name="enableMessagetype"></a>
  <li>enableMessagetype<br>
    Erm&ouml;glicht die Aktivierung der Nachrichtenverarbeitung f&uuml;r
    <ul>
      <li>Nachrichten mit sync (syncedMS)</li>
      <li>Nachrichten ohne einen sync pulse (unsyncedMU)</li>
      <li>Manchester codierte Nachrichten (manchesterMC)</li>
    </ul>
    Der neue Status wird in den eeprom vom Arduino geschrieben.
  </li><br>
  <a name="flash"></a>
  <li>
    flash [hexFile|url]<br>
    Der SIGNALduino ben&ouml;tigt die richtige Firmware, um die Sensordaten zu empfangen und zu liefern. Unter Verwendung der Arduino IDE zum Flashen der Firmware in den SIGNALduino bietet dies eine M&ouml;glichkeit, ihn direkt von FHEM aus zu flashen. Sie k&ouml;nnen eine Datei auf Ihrem fhem-Server angeben oder eine URL angeben, von der die Firmware heruntergeladen wird.<br><br>
    Es gibt einige Anforderungen:
    <ul>
      <li><code>avrdude</code> muss auf dem Host installiert sein. Auf einem Raspberry PI kann dies getan werden mit: <code>sudo apt-get install avrdude</code>
      </li>
      <li>Das Hardware-Attribut muss festgelegt werden, wenn eine andere Hardware als Arduino Nano verwendet wird. Dieses Attribut definiert den Befehl, der an avrdude gesendet wird, um den uC zu flashen.
      </li>
      <li>Bei Problem mit dem Flashen, k&ouml;nnen im Logfile interessante Informationen zu finden sein.
      </li>
    </ul><br>
    Beispiele:
    <ul>
      <li>flash mittels Versionsnummer: Versionen k&ouml;nnen mit get availableFirmware abgerufen werden</li>
      <li>flash via hexFile: <code>set sduino flash ./FHEM/firmware/SIGNALduino_mega2560.hex</code></li>
      <li>flash via url f&uuml;r einen Nano mit CC1101: <code>set sduino flash https://github.com/RFD-FHEM/SIGNALDuino/releases/download/3.3.1-RC7/SIGNALDuino_nanocc1101.hex</code></li>
    </ul><br>
    <i><u>Hinweise Modell radino:</u></i>
    <ul>
      <li>Teilweise kann es beim flashen vom radino unter Linux Probleme geben. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Hier im Wiki unter dem Punkt "radino & Linux" gibt es einen Patch!</a></li>
      <li>Wenn der Radino in dieser Art <code>/dev/ttyACM0</code> definiert wurde, sollte das Flashen der Firmware automatisch erfolgen. Wenn das nicht gelingt, muss der Bootloader manuell aktiviert werden:</li>
      <li>Um den Bootloader vom radino manuell zu aktivieren gibt es 2 Varianten.
        <ul>
          <li> 1) Module welche einen BSL-Button besitzen:
            <ul>
              <li>Spannung anlegen</li>
              <li>druecke & halte BSL- und RESET-Button</li>
              <li>RESET-Button loslassen und danach den BSL-Button loslassen</li>
              <li>(Wiederholen Sie diese Schritte, wenn Ihr radino nicht sofort in den Bootloader-Modus wechselt.)</li>
            </ul>
          </li>
          <li> 2) Bootloader erzwingen:
            <ul>
              <li>durch zweimaliges druecken der Reset-Taste</li>
            </ul>
          </li>
        </ul>
        Im Bootloader-Modus erh&auml;lt der radino eine andere USB ID. Diese muss im Attribut "flashCommand" eingetragen werden.<br>
        Wenn der Bootloader aktiviert ist, signalisiert er das mit dem Blinken einer LED. Dann hat man ca. 8 Sekunden Zeit zum flashen.
      </li>
    </ul>
  </li><br>

  <a name="raw"></a>
  <li>raw<br>
    Geben Sie einen SIGNALduino-Firmware-Befehl aus, ohne auf die vom SIGNALduino zur&uuml;ckgegebenen Daten zu warten. Ausf&uuml;hrliche Informationen zu SIGNALduino-Befehlen finden Sie im SIGNALduino-Firmware-Code. Mit dieser Linie k&ouml;nnen Sie fast jedes Signal &uuml;ber einen angeschlossenen Sender senden.<br>
    Um einige Rohdaten zu senden, schauen Sie sich diese Beispiele an: P#binarydata#R#C (#C is optional)<br><br>

    Beispiel 1: <code>set sduino raw SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=0302030;</code> , sendet die Daten im Raw-Modus dreimal wiederholt<br>
    Beispiel 2: <code>set sduino raw SM;R=3;P0=500;C=250;D=A4F7FDDE;</code> , sendet die Daten Manchester codiert mit einem clock von 250&micro;S<br>
    Beispiel 3: <code>set sduino raw SC;R=3;SR;P0=5000;SM;P0=500;C=250;D=A4F7FDDE;</code> , sendet eine kombinierte Nachricht von Raw und Manchester codiert 3 mal wiederholt<br>
    Beispiel 4: <code>set sduino raw SN;R=3;D=9A46036AC8D3923EAEB470AB;</code> , sendet die xFSK - Daten dreimal wiederholt<br>
    <br>

    <ul>
      <b>Hinweis: Die falsche Benutzung der kommenden Optionen kann zu Fehlfunktionen des SIGNALduinos f&uuml;hren!</b><br><br>
      <li>CER -> Einschalten der Datenkomprimierung (config: Mred=1)</li>
      <li>CDR -> Abschalten der Datenkomprimierung (config: Mred=0)</li><br>
      <u>Register Befehle bei einem CC1101</u>
      <li>e -> Werkseinstellungen</li>
      <li>x -> gibt die ccpatable zur&uuml;ck</li>
      <li>C -> liest einen Wert aus dem CC1101 Register<br>
        <ul>Beispiel: <code>set sduino raw C04</code> liest den Wert aus der Registeradresse 0x04</ul>
      </li>
      <li>W -> schreibt einen Wert ins EEPROM und ins CC1101 Register <u>(Hinweis: Die EEPROM Adresse hat einen Offset von 2)</u><br>
        <ul>Beispiel 1: <code>set sduino raw W041D</code> schreibt 1D ins Register 0x02</ul>
        <ul>Beispiel 2: <code>set sduino raw W041D#W0604</code> schreibt 1D ins Register 0x02 und 04 ins Register 0x04</ul>
      </li>
      <br>
      <u>andere Befehle des uC</u>
      <li>? -> gibt die verf&uuml;gbaren Kommandos zur&uuml;ck</li>
      <li>P -> sendet ein PING</li>
      <li>R -> gibt den freien RAM zur&uuml;ck</li>
      <li>V -> gibt die Version  zur&uuml;ck</li>
      <li>s -> gibt den Status zur&uuml;ck</li>
      <li>t -> gibt die Uptime zur&uuml;ck</li>
    </ul><br>
  </li>

  <a name="reset"></a>
  <li>reset<br>
    &Ouml;ffnet die Verbindung zum Ger&auml;t neu und initialisiert es.
  </li><br>

  <a name="sendMsg"></a>
  <li>sendMsg<br>
    Dieser Befehl erstellt die erforderlichen Anweisungen zum Senden von Rohdaten &uuml;ber den SIGNALduino. Sie k&ouml;nnen die Signaldaten wie Protokoll und die Bits angeben, die Sie senden m&ouml;chten.<br>
    Alternativ ist es auch moeglich, die zu sendenden Daten in hexadezimaler Form zu uebergeben. Dazu muss ein 0x vor den Datenteil geschrieben werden.
    <br><br>
    Bitte beachte, dieses Kommando funktioniert nur fuer MU oder MS Protokolle nach dieser Vorgehensweise:
    <br><br>
    Argumente sind:
    <p>
      <ul>
        <li>P<protocol id>#binarydata#R<anzahl der wiederholungen>#C<optional taktrate>   (#C is optional)
          <br>Beispiel binarydata: <code>set sduino sendMsg P0#0101#R3#C500</code>
          <br>Dieser Befehl erzeugt ein Sendekommando fuer die Bitfolge 0101 anhand der protocol id 0. Als Takt wird 500 verwendet.
          <br>SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=03020302;<br>
        </li>
      </ul><br>
      <ul>
        <li>P<protocol id>#0xhexdata#R<anzahl der wiederholungen>#C<optional taktrate>    (#C is optional)
          <br>Beispiel 0xhexdata: <code>set sduino sendMsg P29#0xF7E#R4</code>
          <br>Dieser Befehl erzeugt ein Sendekommando fuer die Hexfolge F7E anhand der protocol id 29. Die Nachricht soll 4x gesendet werden.
          <br>SR;R=4;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=01212121213421212121212134;
        </li>
      </ul><br>
      <ul>
        <li>P<protocol id>#0xhexdata#R<anzahl der wiederholungen>#C<optional taktrate>#F<optional Frequenz>    (#C #F is optional)
          <br>Beispiel 0xhexdata: <code>set sduino sendMsg P36#0xF7#R6#Fxxxxxxxxxx</code> (xxxxxxxxxx = Registerwert des CC1101)
          <br>Dieser Befehl erzeugt ein Sendekommando fuer die Hexfolge F7 anhand der protocol id 36. Die Nachricht soll 6x gesendet werden mit der angegebenen Frequenz.
          <br>SR;R=6;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=012323232324232323;F= (Registerwert des CC1101);
        </li>
      </ul>
    </p>
  </li>
</ul>
<br>


<a name="SIGNALduinoget"></a>
<b>Get</b>
<ul>
  <a name="availableFirmware"></a>
  <li>availableFirmware<br>
    Ruft die verf&uuml;gbaren Firmware-Versionen von Github ab und macht diese im <code>set flash</code> Befehl ausw&auml;hlbar.
  </li><br>
  <a name="ccconf"></a>
  <li>ccconf<br>
    Liest s&auml;mtliche radio-chip (cc1101) Register (Frequenz, Bandbreite, etc.) aus und zeigt die aktuelle Konfiguration an.<br>
    (NUR bei Verwendung eines cc1101 Empf&auml;nger)
  </li><br>
  <a name="ccpatable"></a>
  <li>ccpatable<br>
    Liest die cc1101 PA Tabelle aus (power amplification for RF sending).<br>
    (NUR bei Verwendung eines cc1101 Empf&auml;nger)
  </li><br>
  <a name="ccreg"></a>
  <li>ccreg<br>
    Liest das cc1101 Register aus (99 liest alle aus).<br>
    (NUR bei Verwendung eines cc1101 Empf&auml;nger)
  </li><br>
  <a name="close"></a>
  <li>close<br>
    Beendet die Verbindung zum SIGNALduino.
  </li><br>
  <a name="cmds"></a>
  <li>cmds<br>
    Abh&auml;ngig von der installierten Firmware besitzt der SIGNALduino verschiedene Befehle. Bitte beachten Sie den Quellcode der Firmware Ihres SIGNALduino, um die Antwort dieses Befehls zu interpretieren.
  </li><br>
  <a name="config"></a>
  <li>config<br>
    Zeigt Ihnen die aktuelle Konfiguration der SIGNALduino Protokollkathegorie an. | Bsp: <code>MS=1;MU=1;MC=1;Mred=0</code>
  </li><br>
  <a name="freeram"></a>
  <li>freeram<br>
    Zeigt den freien RAM an.
  </li><br>
  <a name="ping"></a>
  <li>ping<br>
    Pr&uuml;ft die Kommunikation mit dem SIGNALduino.
  </li><br>
  <a name="rawmsg"></a>
  <li>rawmsg<br>
    Verarbeitet Nachrichten (MS, MC, MU, ...), als ob sie vom SIGNALduino empfangen wurden. Der Befehl "get raw" übergibt keine Kommandos an den verbundenen Microcontroller!<br><br>
    Beispielsweise würde diese Nachricht:<br>
    <code>MS;P0=-7871;P2=-1960;P3=578;P4=-3954;D=030323232323434343434323232323234343434323234343234343234343232323432323232323232343234;CP=3;SP=0;R=0;m=0;</code><br>
    nach mehrmaligem Ausführen des Befehles einen Sensor SD_WS_33_TH_1 anlegen.
  </li><br>
  <a name="uptime"></a>
  <li>uptime<br>
    Zeigt Ihnen die Information an, wie lange der SIGNALduino l&auml;uft. Ein FHEM Neustart setzt den Timer zur&uuml;ck.
  </li><br>
  <a name="version"></a>
  <li>version<br>
    Zeigt Ihnen die Information an, welche aktuell genutzte Software Sie mit dem SIGNALduino verwenden.
  </li><br>
</ul>


<a name="SIGNALduinoattr"></a>
<b>Attributes</b>
<ul>
  <a name="addvaltrigger"></a>
  <li>addvaltrigger<br>
    Generiert Trigger f&uuml;r zus&auml;tzliche Werte. Momentan werden DMSG, ID, RAWMSG und RSSI unterst&uuml;zt.
  </li><br>
  <a name="blacklist_IDs"></a>
  <li>blacklist_IDs<br>
    Dies ist eine durch Komma getrennte Liste. Die Blacklist funktioniert nur, wenn keine Whitelist existiert! Hier kann man ID´s eintragen welche man nicht ausgewertet haben m&ouml;chte.
  </li><br>
  <a name="cc1101_frequency"></a>
  <li>cc1101_frequency<br>
    Legt die Frequenz des SIGNALduino fest. Standard is 433 Mhz.<br>
    Da die Werte für PA Werte Frequenzabhängig sind, wird für das Setzen der Register die hier hinterlegte Frequenz verwendet.
  </li><br>
  <a name="cc1101_reg_user"></a>
  <li>cc1101_reg_user<br>
    Speicherplatz für individuelle Registerkonfigurationen bzw. Werte. Es k&ouml;nnen einzelne oder mehrere Werte gespeichert werden.<br>
    <u>Hinweis:</u> Der Wert ist bestehend aus der Registeradresse gefolgt vom Wert. Mehrere Werte werden mit Komma getrennt. Beispiel: 04D3,0591
  </li><br>
  <a name="debug"></a>
  <li>debug<br>
    Dies bringt das Modul in eine sehr ausf&uuml;hrliche Debug-Ausgabe im Logfile. Somit lassen sich neue Signale finden und Signale &uuml;berpr&uuml;fen, ob die Demodulation korrekt funktioniert.
  </li><br>
  <a name="development"></a>
  <li>development<br>
    Das development Attribut ist nur in den Entwicklungsversionen des FHEM Modules aus Gr&uuml;den der Abw&auml;rtskompatibilit&auml;t vorhanden. Bei Setzen des Attributes auf "1" werden alle Protokolle aktiviert, welche mittels developID=y markiert sind.
    <br>
    Wird das Attribut auf 1 gesetzt, so werden alle in Protokolle die mit dem developID Flag "y" markiert sind aktiviert. Die Flags (Spalte dev) k&ouml;nnen &uuml;ber das Webfrontend im Abschnitt "Information menu" mittels "Display protocollist" eingesehen werden.
  </li><br>
  <li><a href="#do_not_notify">do_not_notify</a></li><br>
  <a name="doubleMsgCheck_IDs"></a>
  <li>doubleMsgCheck_IDs<br>
    Dieses Attribut erlaubt es, Protokolle anzugeben, die zwei gleiche Nachrichten enthalten m&uuml;ssen, um diese an die Module zu &uuml;bergeben. Sie k&ouml;nnen mehrere IDs mit einem Komma angeben: 0,3,7,12
  </li><br>
  <li><a href="#dummy">dummy</a></li><br>
  <a name="eventlogging"></a>
  <li>eventlogging<br>
    Mit diesem Attribut k&ouml;nnen Sie steuern, ob jede Logmeldung auch als Ereignis bereitgestellt wird. Dies erm&ouml;glicht das Erzeugen eines Ereignisses fuer jede Protokollnachricht.
    Setze dies auf 0 und Logmeldungen werden nur in der globalen Fhem-Logdatei gespeichert, wenn der Loglevel h&ouml;her oder gleich dem Verbose-Attribut ist.
    Setze dies auf 1 und jede Logmeldung wird auch als Ereignis versendet. Dadurch k&ouml;nnen Sie die Ereignisse in einer separaten Protokolldatei protokollieren.
  </li><br>
  <a name="flashCommand"></a>
  <li>flashCommand<br>
    Dies ist der Befehl, der ausgef&uuml;hrt wird, um den Firmware-Flash auszuf&uuml;hren. Nutzen Sie dies nicht, wenn Sie nicht wissen, was Sie tun!<br>
    Wurde das Attribut nicht definiert, so verwendet es die Standardeinstellungen.<br><b>Sobald der User das Attribut manuell definiert, nutzt das System diese Vorgaben!</b><br>
    <ul>
      <li>Standard nano, nanoCC1101, miniculCC1101, promini:<br><code>avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
      <li>Standard radinoCC1101:<br><code>avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
    </ul>
    Es enth&auml;lt einige Platzhalter, die automatisch mit den entsprechenden Werten gef&uuml;llt werden:
    <ul>
      <li>[BAUDRATE]<br>
        Ist die Schrittgeschwindigkeit. (z.Bsp: 57600)
      </li>
      <li>[PORT]<br>
        Ist der Port, an dem der SIGNALduino angeschlossen ist (z.Bsp: /dev/ttyUSB0) und wird von der Definition verwendet.
      </li>
      <li>[HEXFILE]<br>
        Ist die .hex-Datei, die geflasht werden soll. Es gibt drei Optionen (angewendet in dieser Reihenfolge):<br>
        <ul>
          <li>in <code>set SIGNALduino flash</code> als erstes Argument &uuml;bergeben</li>
          <li>aus dem Hardware-Attribut genommen</li>
          <li>der im Modul definierte Standardwert</li>
        </ul>
      </li>
      <li>[LOGFILE]<br>
        Die Logdatei, die Informationen &uuml;ber den Flash-Prozess sammelt. Es wird nach Abschluss des Flash-Prozesses in FHEM angezeigt
      </li>
    </ul><br>
    <u><i>Hinweis:</u></i> ! Teilweise kann es beim Flashen vom radino unter Linux Probleme geben. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Hier im Wiki unter dem Punkt "radino & Linux" gibt es einen Patch!</a>
  </li><br>
  <a name="SIGNALDuino_hardware"></a>
  <li>hardware<br>
    Derzeit m&ouml;gliche Hardware Varianten mit verschiedenen Empfänger Optionen.
    Die einfache Variante besteht aus einem Empf&auml;nger und einen Sender, die über je eine einzige digitale Signalleitung Datem mit dem Microcontroller austauschen. Der Empf&auml;nger sendet dabei und der Sender empf&auml;ngt dabei ausschließlich.
    Weiterhin existiert der den sogenannten cc1101 (sub 1 GHZ) Chip, welche empfangen und senden kann. Dieser wird über die SPI Verbindung angebunden.
    ESP8266 Hardware Typen, unterstützen derzeit kein flashen aus dem Modul und ben&ouml;tigen mindestens 1 MB Flash Speicher.
    <ul>
      <li>ESP32: ESP32 f&uuml;r einfachen eindraht Empf&auml;nger</li>
      <li>ESP32cc1101: ESP32 mit einem CC110x-Empf&auml;nger (SPI Verbindung)</li>
      <li>ESP8266: ESP8266 f&uuml;r einfachen eindraht Empf&auml;nger</li>
      <li>ESP8266cc1101: ESP8266 mit einem CC110x-Empf&auml;nger (SPI Verbindung)</li>
      <li>MAPLEMINI_F103CB: MapleMini F103CB (STM32) f&uuml;r einfachen eindraht Empf&auml;nger</li>
      <li>MAPLEMINI_F103CBcc1101: MapleMini F103CB (STM32) mit einem CC110x-Empf&auml;nger (SPI Verbindung)</li>
      <li>miniculCC1101: Arduino pro Mini mit einem CC110x-Empf&auml;nger (SPI Verbindung) entsprechend dem minicul verkabelt</li>
      <li>nano: Arduino Nano 328 f&uuml;r einfachen eindraht Empf&auml;nger</li>
      <li>nanoCC1101: Arduino Nano f&uuml;r einen CC110x-Empf&auml;nger (SPI Verbindung)</li>
      <li>promini: Arduino Pro Mini 328 f&uuml;r einfachen eindraht Empf&auml;nger</li>
      <li>radinoCC1101: Ein Arduino kompatibler Radino mit CC110x-Empfänger (SPI Verbindung)</li>
    </ul><br>
    Notwendig f&uuml;r den Befehl <code>flash</code>. Hier sollten Sie angeben, welche Hardware Sie mit dem usbport verbunden haben. Andernfalls kann es zu Fehlfunktionen des Ger&auml;ts kommen. Wichtig ist auch das Attribut <code>updateChannelFW</code><br>
  </li><br>
  <a name="longids"></a>
  <li>longids<br>
    Durch Komma getrennte Liste von Device-Typen f&uuml;r Empfang von langen IDs mit dem SIGNALduino. Diese zus&auml;tzliche ID erlaubt es Wettersensoren, welche auf dem gleichen Kanal senden zu unterscheiden. Hierzu wird eine zuf&auml;llig generierte ID hinzugef&uuml;gt. Wenn Sie longids verwenden, dann wird in den meisten F&auml;llen nach einem Batteriewechsel ein neuer Sensor angelegt. Standardm&auml;ßig werden keine langen IDs verwendet.<br>
    Folgende Module verwenden diese Funktionalit&auml;t: 14_Hideki, 41_OREGON, 14_CUL_TCM97001, 14_SD_WS07.<br>
    Beispiele:<PRE>
      # Keine langen IDs verwenden (Default Einstellung):
      attr sduino longids 0
      # Immer lange IDs verwenden:
      attr sduino longids 1
      # Verwende lange IDs f&uuml;r SD_WS07 Devices.
      # Device Namen sehen z.B. so aus: SD_WS07_TH_3.
      attr sduino longids SD_WS07
    </PRE>
  </li>
  <a name="maxMuMsgRepeat"></a>
  <li>maxMuMsgRepeat<br>
    In MU Signalen k&ouml;nnen mehrere Wiederholungen stecken. Diese werden einzeln ausgewertet und an ein logisches Modul uebergeben. Mit diesem Attribut kann angepasst werden, wie viele Wiederholungen gesucht werden. Standard ist 4.
  </li><br>
  <a name="minsecs"></a>
  <li>minsecs<br>
    Es wird von anderen Modulen bereitgestellt. Minsecs sollte wie eine Schwelle wirken. Wenn angegeben, werden unterst&uuml;tzte Module neue Nachrichten verworfen, wenn minsecs nicht vergangen sind.
  </li><br>
  <a name="noMsgVerbose"></a>
  <li>noMsgVerbose<br>
    Mit diesem Attribut k&ouml;nnen Sie die Protokollierung von Debug-Nachrichten vom io-Ger&auml;t steuern. Wenn dieser Wert auf 3 festgelegt ist, werden diese Nachrichten protokolliert, wenn der globale Verbose auf 3 oder h&ouml;her eingestellt ist.
  </li><br>
  <a name="rawmsgEvent"></a>
  <li>rawmsgEvent<br>
    Bei der Einstellung "1", l&ouml;sen empfangene Rohnachrichten Ereignisse aus.
  </li><br>
  <a name="rfmode"></a>
  <li>rfmode<br>
    Konfiguriert den RF Transceiver des SIGNALduino (CC1101). Verf&uuml;gbare Argumente sind:
    <ul>
      <li>Avantek<br>
        Modulation 2-FSK, Datenrate=50.087 kbps, Sync Word=0869, FIFO-THR=8 Byte, Frequenz 433.3 MHz
        <ul><small>Example: AVANTEK Funk-Türklingel</small></ul>
      </li>
      <li>Bresser_5in1<br>
        Modulation 2-FSK, Datenrate=8.23 kbps, Sync Word=2DD4, Packet Length=26 Byte, Frequenz 868.3 MHz
        <ul><small>Beispiel: BRESSER 5-in-1 Wetter Center, BRESSER Profi Regenmesser, Fody E42, Fody E43</small></ul>
      </li>
      <li>Bresser_6in1<br>
        Modulation 2-FSK, Datenrate=8.23 kbps, Sync Word=2DD4, FIFO-THR=20 Byte, Frequenz 868.3 MHz
      </li>
      <li>Bresser_7in1<br>
        Modulation 2-FSK, Datenrate=8.23 kbps, Sync Word=2DD4, Packet Length=22 Byte, Frequenz 868.3 MHz
      </li>
      <li>Fine_Offset_WH51_434<br>
        Modulation 2-FSK, Datenrate=17.26 kbps, Sync Word=2DD4, Packet Length=14 Byte, Frequenz 433.92 MHz
        <ul><small>Beispiel: Bodenfeuchtesensor Fine Offset WH51, ECOWITT WH51, MISOL/1, Froggit DP100</small></ul>
      </li>
      <li>Fine_Offset_WH51_868<br>
        Modulation 2-FSK, Datenrate=17.26 kbps, Sync Word=2DD4, Packet Length=14 Byte, Frequenz 868.35 MHz
        <ul><small>Beispiel: Bodenfeuchtesensor Fine Offset WH51, ECOWITT WH51, MISOL/1, Froggit DP100</small></ul>
      </li>
      <li>Fine_Offset_WH57_434<br>
        Modulation 2-FSK, Datenrate=17.26 kbps, Sync Word=2DD4, Packet Length=9 Byte, Frequenz 433.92 MHz
        <ul><small>Beispiel: Gewittersensor Fine Offset WH57, Froggit DP60, Ambient Weather WH31L</small></ul>
      </li>
      <li>Fine_Offset_WH57_868<br>
        Modulation 2-FSK, Datenrate=17.26 kbps, Sync Word=2DD4, Packet Length=9 Byte, Frequenz 868.35 MHz
        <ul><small>Beispiel: Gewittersensor Fine Offset WH57, Froggit DP60, Ambient Weather WH31L</small></ul>
      </li>
      <li>KOPP_FC<br>
        Modulation GFSK, Datenrate=4.7855 kbps, Sync Word=AA54, Frequenz 868.3MHz
      </li>
      <li>Lacrosse_mode1<br>
        Modulation 2-FSK, Datenrate=17.25769 kbps, Sync Word=2DD4, Frequenz 868.3MHz<br>
        <ul><small>Beispiel: TX25-IT, TX27-IT, TX29-IT, TX29DTH-IT, TX37, 30.3143.IT, 30.3144.IT</small></ul>
      </li>
      <li>Lacrosse_mode2<br>
        Modulation 2-FSK, Datenrate=9.579 kbps, Sync Word=2DD4, Frequenz 868.3MHz<br>
        <ul><small>Beispiel: TX35TH-IT, TX35DTH-IT, TX38-IT, 30.3155WD, 30.3156WD</small></ul>
      </li>
      <li>PCA301<br>
        Modulation 2-FSK, Datenrate=6.62041 kbps, Sync Word=2DD4, Frequenz 868.950 MHz
      </li>
      <li>Rojaflex<br>
        Modulation GFSK, Datenrate=9.99 kbps, Sync Word=D391D391, Frequenz 433.920 MHz
      </li>
      <li>SlowRF<br>
        Modulation ASK/OOK, <b>l&auml;d die Standard Einstellung vom uC</b>
      </li>
    </ul>
  </li><br>
  <a name="suppressDeviceRawmsg"></a>
  <li>suppressDeviceRawmsg<br>
    Bei der Einstellung "1" wird das interne "RAWMSG" nicht mit den empfangenen Nachrichten aktualisiert.
  </li><br>
  <a name="updateChannelFW"></a>
  <li>updateChannelFW<br>
    Das Modul sucht nach Verf&uuml;gbaren Firmware Versionen (<a href="https://github.com/RFD-FHEM/SIGNALDuino/releases">GitHub</a>) und bietet diese via dem Befehl <code>flash</code> zum Flashen an. Mit dem Attribut kann festgelegt werden, ob nur stabile Versionen ("Latest Release") angezeigt werden oder auch Vorabversionen ("Pre-release") einer neuen Firmware.<br>
    Die Option testing inkludiert auch die stabilen Versionen.
    <ul>
      <li>stable: Als stabil getestete Versionen, erscheint nur sehr selten</li>
      <li>testing: Neue Versionen, welche noch getestet werden muss</li>
    </ul>
    <br>Die Liste der verf&uuml;gbaren Versionen muss manuell mittels <code>get availableFirmware</code> neu geladen werden.
  </li><br>
  Notwendig f&uuml;r den Befehl <code>flash</code>. Hier sollten Sie angeben, welche Hardware Sie mit dem USB-Port verbunden haben. Andernfalls kann es zu Fehlfunktionen des Ger&auml;ts kommen. <br><br>
  <a name="whitelist_IDs"></a>
  <li>whitelist_IDs<br>
    Dieses Attribut erlaubt es, festzulegen, welche Protokolle von diesem Modul aus verwendet werden. Protokolle, die nicht beachtet werden, erzeugen keine Logmeldungen oder Ereignisse. Sie werden dann vollst&auml;ndig ignoriert. Dies erm&ouml;glicht es, die Ressourcennutzung zu reduzieren und bessere Klarheit in den Protokollen zu erzielen. Sie k&ouml;nnen mehrere WhitelistIDs mit einem Komma angeben: 0,3,7,12. Mit einer # am Anfang k&ouml;nnen WhitelistIDs deaktiviert werden.
    <br>
    Wird dieses Attribut nicht verwrndet oder deaktiviert, werden alle stabilen Protokolleintr&auml;ge verarbeitet. Protokolleintr&auml;ge, welche sich noch in Entwicklung befinden m&uuml;ssen explizit &uuml;ber dieses Attribut aktiviert werden.
  </li><br>
  <a name="WS09_CRCAUS"></a>
  <li>WS09_CRCAUS<br>
    <ul>
      <li>0: CRC-Check WH1080 CRC = 0 on, Standard</li>
      <li>2: CRC = 49 (x031) WH1080, set OK</li>
    </ul>
  </li><br>
   <a name="MatchList"></a>
  <li>MatchList<br>
    Dieses Attribut erm&oumlglicht es die Modul Match Tabelle um weitere Eintr&aumlge zu erweitern. Dazu m&uumlssen die weiteren Eintr&aumlge im PERL Hash format angegeben werden:
    <ul>
      <li>Format: { 'Nummer:Modul' => 'Protokoll-Pattern' , 'N&aumlchsteNummer:N&aumlchstesModul' => 'Protokoll-Pattern' , ... }</li>
      <li>Beispiel: { '34:MyModule' => '^u98#.{8}' , '35:MyModule2' => '^u99#.{10}' }</li>
    </ul>
  </li><br>
</ul>


<a name="SIGNALduinoDetail"></a>
<b>Information menu</b>
<ul>
  <a name="Display protocollist"></a>
  <li>Display protocollist<br>
    Zeigt Ihnen die aktuell implementierten Protokolle des SIGNALduino an und an welches logische FHEM Modul Sie &uuml;bergeben werden.<br>
    Außerdem wird mit checkbox Symbolen angezeigt ob ein Protokoll verarbeitet wird. Durch Klick auf das Symbol, wird im Hintergrund das Attribut whitlelistIDs angepasst. Die Attribute whitelistIDs und blacklistIDs beeinflussen den dargestellten Status.
    Protokolle die in der Spalte <code>dev</code> markiert sind, befinden sich in Entwicklung.
    <ul>
      <li>Wemm eine Zeile mit 'm' markiert ist, befindet sich das logische Modul, welches eine Schnittstelle bereitstellt in Entwicklung. Im Standard &uuml;bergeben diese Protokolle keine Daten an logische Module. Um die Kommunikation zu erm&ouml;glichenm muss der Protokolleintrag aktiviert werden.</li>
      <li>Wemm eine Zeile mit 'p' markiert ist, wurde der Protokolleintrag reserviert oder befindet sich in einem fr&uuml;hen Entwicklungsstadium.</li>
      <li>Wemm eine Zeile mit 'y' markiert ist, wurde das Protkokoll noch nicht ausgiebig getestet und &uuml;berpr&uuml;ft.</li>
    </ul>
    <br>
    Protokolle, welche in dem blacklistIDs Attribut eingetragen sind, k&ouml;nnen nicht &uuml;ber das Men&uuml; aktiviert werden. Dazu bitte das Attribut blacklistIDs entfernen.
  </li><br>
</ul>


=end html_DE
=for :application/json;q=META.json 00_SIGNALduino.pm
{
  "abstract": "supports the same low-cost receiver for digital signals",
  "author": [
    "Sidey <>",
    "homeautouser",
    "elektron-bbs",
    "ralf9"
  ],
  "x_fhem_maintainer": [
    "Sidey",
    "homeautouser",
    "elektron-bbs"
  ],
  "x_fhem_maintainer_github": [
    "Sidey",
    "homeautouser",
    "elektron-bbs"
  ],
  "description": "This module interprets digitals signals provided from the signalduino hardware device and provides it to logical modules",
  "dynamic_config": 1,
  "keywords": [
    "fhem-sonstige-systeme",
    "fhem-hausautomations-systeme",
    "fhem-mod",
    "signalduino"
  ],
  "license": [
    "GPL_2"
  ],
  "meta-spec": {
    "url": "https://metacpan.org/pod/CPAN::Meta::Spec",
    "version": 2
  },
  "name": "FHEM::SIGNALduino",
  "prereqs": {
    "runtime": {
      "requires": {
        "HttpUtils": 0,
        "perl": 5.018,
        "IPC::Open3": "0",
        "Symbol": "0",
        "constant": "0",
        "lib::SD_Protocols": "0",
        "strict": "0",
        "warnings": "0",
        "Time::HiRes": "0",
        "JSON": "0",
        "Storable": "0"
      },
      "recommends": {
        "Data::Dumper": "0"
      },
      "suggests": {
        "Scalar::Util": "0"
      }
    },
    "develop": {
      "requires": {
        "IPC::Open3": "0",
        "Symbol": "0",
        "constant": "0",
        "lib::SD_Protocols": "0",
        "strict": "0",
        "warnings": "0",
        "Data::Dumper": "0",
        "Time::HiRes": "0",
        "FHEM::Core::Timer::Helper": "0",
        "JSON": "0"
      },
      "suggests": {
        "Scalar::Util": "0"
      }
    }
  },
  "release_status": "stable",
  "resources": {
    "bugtracker": {
      "web": "https://github.com/RFD-FHEM/RFFHEM/issues/"
    },
    "repository": {
      "x_master": {
        "type": "git",
        "url": "https://github.com/RFD-FHEM/RFFHEM.git",
        "web": "https://github.com/RFD-FHEM/RFFHEM/tree/master"
      },
      "type": "svn",
      "url": "https://svn.fhem.de/fhem",
      "web": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/00_SIGNALduino.pm",
      "x_branch": "trunk",
      "x_filepath": "fhem/FHEM/",
      "x_raw": "https://svn.fhem.de/trac/export/latest/trunk/fhem/FHEM/00_SIGNALduino.pm",
      "x_dev": {
        "type": "git",
        "url": "https://github.com/RFD-FHEM/RFFHEM.git",
        "web": "https://github.com/RFD-FHEM/RFFHEM/tree/master",
        "x_branch": "master",
        "x_filepath": "FHEM/",
        "x_raw": "https://raw.githubusercontent.com/RFD-FHEM/RFFHEM/master/FHEM/00_SIGNALduino.pm"
      }
    },
    "x_commandref": {
      "web": "https://commandref.fhem.de/#SIGNALduino"
    },
    "x_support_community": {
      "board": "Sonstige Systeme",
      "boardId": "29",
      "cat": "FHEM - Hausautomations-Systeme",
      "description": "Sonstige Hausautomations-Systeme",
      "forum": "FHEM Forum",
      "rss": "https://forum.fhem.de/index.php?action=.xml;type=rss;board=29",
      "title": "FHEM Forum: Sonstige Systeme",
      "web": "https://forum.fhem.de/index.php/board,29.0.html"
    },
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SIGNALduino"
    }
  },
  "version": "v3.5.4"
}
=end :application/json;q=META.json
=cut

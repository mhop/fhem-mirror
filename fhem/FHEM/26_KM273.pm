# $Id$
########################################################################################################################
#
#     26_KM273.pm
#     Creates the possibility to access the Buderus Logaterm WPS Heatpump over CAN bus
#
#     Author                     : mike3436
#     Contributions              : 
#     e-mail                     : mike3436(AT)online(PUNKT)de
#     Fhem Forum                 : http://forum.fhem.de/index.php/topic,47508.0.html
#     Fhem Wiki                  : 
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#     fhem.cfg: define <devicename> KM273 <CAN-Device>
#
#     Example:
#     define myKM273 KM273 /dev/ttyACM0@115200
#     attr myKM273 room Heizung
#
#
#     Example for group display and log files:
#
#     define Temperaturen readingsGroup myKM273:<%temp_temperature>,<AussenTemp.>,GT2_TEMP myKM273:<%sani_buffer_temp_all>,<HeisswasserTemp.>,GT3_TEMP
#     attr Temperaturen room Heizung
#     attr Temperaturen valueStyle style="text-align:right"
#
#     define Temperaturen1 readingsGroup myKM273:<%sani_return_temp>,<SoleEin>,GT10_TEMP myKM273:<%sani_supply_temp>,<SoleAus>,GT11_TEMP
#     attr Temperaturen1 room Heizung
#     attr Temperaturen1 valueStyle style="text-align:right"
#     
#     define Temperaturen2 readingsGroup myKM273:<%sani_supply_temp>,<WaermetraegerAus>,GT8_TEMP myKM273:<%sani_return_temp>,<WaermetraegerEin>,GT9_TEMP myKM273:<%sani_buffer_temp_all>,<Heizgastemperatur>,GT6_TEMP
#     attr Temperaturen2 room Heizung
#     attr Temperaturen2 valueStyle style="text-align:right"
#     
#     define FileLog_myKM273 FileLog ./log/myKM273-%Y-%m.log myKM273
#     attr FileLog_myKM273 logtype text
#     attr FileLog_myKM273 room Heizung
#     
#     define FileLog_myKM273_Temperaturen FileLog ./log/myKM273_Temperaturen-%Y-%m.log myKM273:(GT1_TEMP|GT2_TEMP|GT3_TEMP|GT6_TEMP|GT8_TEMP|GT9_TEMP|GT10_TEMP|GT11_TEMP).*
#     attr FileLog_myKM273_Temperaturen logtype text
#     attr FileLog_myKM273_Temperaturen room Heizung
#
#     define FileLog_myKM273_Pumpen FileLog ./log/myKM273_Pumpen-%Y-%m.log myKM273:(HW_PUMP*).*
#     attr FileLog_myKM273_Pumpen logtype text
#     attr FileLog_myKM273_Pumpen room Heizung
#
########################################################################################################################
#                                               CHANGELOG
#
#     Version   Date        Programmer          Subroutine                      Description of Change
#       0001    28.08.2015  mike3436            All                             Initial Release, try to read all temperature valuse
#       0002    08.12.2015  mike3436            KM273_Set                       implement write access
#       0003    29.12.2015  mike3436            CAN_Read, CAN_Write             implement abstract functions to use other CAN Adapters, later
#       0004    18.01.2016  mike3436            KM273_elements                  set all values equal to the KM200 access read=1
#       0005    23.01.2016  mike3436            KM273_Set,KM273_Get             implement t15 timeformat to get/set PUMP_DHW_PROGRAM's START and STOP TIME
#       0006    24.01.2016  mike3436            KM273_gets,KM273_elements       change weekdays _FRI -> _5FRI to correct the sort order
#       0007    01.02.2016  mike3436            KM273_Get,KM273_GetNextValue    KM273_Get corrected, KM273_GetNextValue do nothing if attr doNotPoll=1
#       0008    30.05.2016  mike3436            KM273_ReadElementList           complete element list is read from heatpump, default list is only used for deliver the 'read' flag
#       0009    31.05.2016  mike3436            KM273_ReadElementList           if expected readCounter isn't reached on second read, and read data has identical length, try to analyse
#       0010    31.05.2016  mike3436            KM273_ReadElementList           bugfix if expected readCounter isn't reached by read data; delete lists on module reload
#       0011    01.06.2016  mike3436            KM273_ReadElementList           negative min values corrected: value interpretation has to be as signed int64, XDHW_TIME+XDHW_STOP_TEMP added to KM273_gets
#       0012    02.06.2016  mike3436            KM273_ReadElementList           byte nibbles in extid turned
#       0013    07.01.2017  mike3436            KM273_gets                      HOLIDAY params added for get/set, cyclic read for some alarms and requests activated in KM273_elements_default
#       0014    22.03.2017  mike3436            KM273_getsAdd                   add variables for 2nd heating circuit if Attribut HeatCircuit2Active is set to 1
#       0015    26.05.2017  mike3436            KM273_Get                       no parameter in module view
#       0015    26.05.2017  mike3436            KM273_Set                       allowed list or range selectable in module view
#       0015    29.05.2017  mike3436            attr AddToGetSet                additional variables can be added to KM273_gets
#       0015    29.05.2017  mike3436            attr AddToReadings              additional variables can be added to KM273_ReadElementList
#       0015    05.06.2017  mike3436            KM273_Notify                    rebuild GetSet and Readings list on Attribut changes

package main;
use strict;
use warnings;
use Time::HiRes qw( time sleep );

my %KM273_getsBase = (
    'XDHW_STOP_TEMP' => '',
    'XDHW_TIME' => '',
    'DHW_CALCULATED_SETPOINT_TEMP' => '',
    'DHW_TIMEPROGRAM' => '',
    'ROOM_TIMEPROGRAM' => '',
    'ROOM_PROGRAM_MODE' => '',
    'ROOM_PROGRAM_1_5FRI' => '',
    'ROOM_PROGRAM_1_1MON' => '',
    'ROOM_PROGRAM_1_6SAT' => '',
    'ROOM_PROGRAM_1_7SUN' => '',
    'ROOM_PROGRAM_1_4THU' => '',
    'ROOM_PROGRAM_1_2TUE' => '',
    'ROOM_PROGRAM_1_3WED' => '',
    'ROOM_PROGRAM_2_5FRI' => '',
    'ROOM_PROGRAM_2_1MON' => '',
    'ROOM_PROGRAM_2_6SAT' => '',
    'ROOM_PROGRAM_2_7SUN' => '',
    'ROOM_PROGRAM_2_4THU' => '',
    'ROOM_PROGRAM_2_2TUE' => '',
    'ROOM_PROGRAM_2_3WED' => '',
    'DHW_PROGRAM_1_5FRI' => '',
    'DHW_PROGRAM_1_1MON' => '',
    'DHW_PROGRAM_1_6SAT' => '',
    'DHW_PROGRAM_1_7SUN' => '',
    'DHW_PROGRAM_1_4THU' => '',
    'DHW_PROGRAM_1_2TUE' => '',
    'DHW_PROGRAM_1_3WED' => '',
    'DHW_PROGRAM_2_5FRI' => '',
    'DHW_PROGRAM_2_1MON' => '',
    'DHW_PROGRAM_2_6SAT' => '',
    'DHW_PROGRAM_2_7SUN' => '',
    'DHW_PROGRAM_2_4THU' => '',
    'DHW_PROGRAM_2_2TUE' => '',
    'DHW_PROGRAM_2_3WED' => '',
    'DHW_PROGRAM_MODE' => '',
    'HEATING_SEASON_MODE' => '',
    'PUMP_DHW_PROGRAM1_START_TIME' => '',
    'PUMP_DHW_PROGRAM1_STOP_TIME' => '',
    'PUMP_DHW_PROGRAM2_START_TIME' => '',
    'PUMP_DHW_PROGRAM2_STOP_TIME' => '',
    'PUMP_DHW_PROGRAM3_START_TIME' => '',
    'PUMP_DHW_PROGRAM3_STOP_TIME' => '',
    'PUMP_DHW_PROGRAM4_START_TIME' => '',
    'PUMP_DHW_PROGRAM4_STOP_TIME' => '',
    'HOLIDAY_ACTIVE' => '',
    'HOLIDAY_START_DAY' => '',
    'HOLIDAY_START_MONTH' => '',
    'HOLIDAY_START_YEAR' => '',
    'HOLIDAY_STOP_DAY' => '',
    'HOLIDAY_STOP_MONTH' => '',
    'HOLIDAY_STOP_YEAR' => ''
   );

my %KM273_getsAddHC2 = (
    'MV_E12_EEPROM_ROOM_PROGRAM_MODE'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM'         => '',
    'MV_E12_EEPROM_TIME_PROGRAM_5FRI'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM_5FRI_2'  => '',
    'MV_E12_EEPROM_TIME_PROGRAM_1MON'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM_1MON_2'  => '',
    'MV_E12_EEPROM_TIME_PROGRAM_6SAT'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM_6SAT_2'  => '',
    'MV_E12_EEPROM_TIME_PROGRAM_7SUN'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM_7SUN_2'  => '',
    'MV_E12_EEPROM_TIME_PROGRAM_4THU'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM_4THU_2'  => '',
    'MV_E12_EEPROM_TIME_PROGRAM_2TUE'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM_2TUE_2'  => '',
    'MV_E12_EEPROM_TIME_PROGRAM_3WED'    => '',
    'MV_E12_EEPROM_TIME_PROGRAM_3WED_2'  => ''
    );

#   Der Abruf der nachfolgenden Tabelle könnte auch online erfolgen
#   Die Tabelle enthält aber auch ein manuell ermitteltes 'format' sowie eine spalte 'read' zum Setzen einer zyklischen Leseanforderung
# 
#   R01FD7FE0 0
#   T09FD7FE0 7 0001298A06FD02
#   T01FD3FE0 8 00004E2000000000              << Anforderung vorbereiten, 20000 Bytes (0x00004E20) ab Offset 0
#   R01FDBFE0 0                               << Liste anfordern
#   T09FDBFE0 8 0000814A53C66A08
#   T09FDBFE0 8 0200000000000000
#   T09FDBFE0 8 001E414343455353 ..ACCESS
#   T09FDBFE0 8 4F524945535F434F ORIES_CO
#   T09FDBFE0 8 4E4E45435445445F NNECTED_
#   T09FDBFE0 8 4249544D41534B00 BITMASK.
#   T09FDBFE0 8 000161E1E1FC6600
#   T09FDBFE0 8 2300000005000000
#   T09FDBFE0 8 000D414343455353 ..ACCESS
#   T09FDBFE0 8 5F4C4556454C0000 _LEVEL..
#   T09FDBFE0 8 02A1137CB3EB0B26
#   T09FDBFE0 8 000000F000000001
#   ...
#   T01FD3FE0 8 00004E2000004E20              << nächste Anforderung vorbereiten, 20000 Bytes ab Offset 20000 (0x00004E20)
#   R01FDBFE0 0                               << Liste anfordern
#   ...
#   T01FD3FE0 8 00004E2000009C40              << nächste Anforderung vorbereiten, 20000 Bytes ab Offset 40000 (0x00009C40)
#   ...
#   T01FD3FE0 8 00004E200000EA60              << nächste Anforderung vorbereiten, 20000 Bytes ab Offset 60000 (0x0000EA60)
#   ...
#   T09FDFFE0 4 9434D9B6                      << Listenende
#
#   Alle Informationen der Tabelle habe ich nicht interpretieren können, 
#   aber wohl die für mich interessantesten:
#   Eine konstanter Header von 21 Byte, 1Byte Textlänge gefolgt vom mit 0 
#   abgeschlossenen Text:
#
#   Index ????????????? GrenzwUP GrenzwLO Textlänge Text                                                                          Text encoded
#   0000 814A53C66A0802 00000000 00000000 1E 4143434553534F524945535F434F4E4E45435445445F4249544D41534B00                         ACCESSORIES_CONNECTED_BITMASK
#   0001 61E1E1FC660023 00000005 00000000 0D 4143434553535F4C4556454C00                                                           ACCESS_LEVEL
#   0002 A1137CB3EB0B26 000000F0 00000001 20 4143434553535F4C4556454C5F54494D454F55545F44454C41595F54494D4500                     ACCESS_LEVEL_TIMEOUT_DELAY_TIME
#   0003 007B1307040471 00000000 00000000 11 4144444954494F4E414C5F414C41524D00                                                   ADDITIONAL_ALARM
#   0004 004E2529500481 00000000 00000000 13 4144444954494F4E414C5F414C41524D5F3200                                               ADDITIONAL_ALARM_2
#   0005 00392219C60482 00000000 00000000 13 4144444954494F4E414C5F414C41524D5F3300                                               ADDITIONAL_ALARM_3
#   ...
#   0A28 03B11E70550000 00000000 00000000 28 54494D45525F434F4D50524553534F525F53544152545F44454C41595F41545F4341534341444500     TIMER_COMPRESSOR_START_DELAY_AT_CASCADE
#
#   Die Lese-CAN-Id rtr ergibt sich aus : 0x04003FE0 | (Index << 14)
#   Die Antwort CAN-Id  ergibt sich aus : 0x0C003FE0 | (Index << 14)
#
#

my %KM273_elements_default = 
(
    '0C003FE0' => { 'rtr' => '04003FE0' , 'idx' =>    0 , 'extid' => '814A53C66A0802' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ACCESSORIES_CONNECTED_BITMASK' },
    '0C007FE0' => { 'rtr' => '04007FE0' , 'idx' =>    1 , 'extid' => '61E1E1FC660023' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ACCESS_LEVEL' },
    '0C00BFE0' => { 'rtr' => '0400BFE0' , 'idx' =>    2 , 'extid' => 'A1137CB3EB0B26' , 'max' =>      240 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ACCESS_LEVEL_TIMEOUT_DELAY_TIME' },
    '0C00FFE0' => { 'rtr' => '0400FFE0' , 'idx' =>    3 , 'extid' => '007B1307040471' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM' },
    '0C013FE0' => { 'rtr' => '04013FE0' , 'idx' =>    4 , 'extid' => '004E2529500481' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM_2' },
    '0C017FE0' => { 'rtr' => '04017FE0' , 'idx' =>    5 , 'extid' => '00392219C60482' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM_3' },
    '0C01BFE0' => { 'rtr' => '0401BFE0' , 'idx' =>    6 , 'extid' => '00A7468C650483' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM_4' },
    '0C01FFE0' => { 'rtr' => '0401FFE0' , 'idx' =>    7 , 'extid' => '0071C5013102EF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALLOW' },
    '0C023FE0' => { 'rtr' => '04023FE0' , 'idx' =>    8 , 'extid' => '004D59464306BC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALLOW_XDHW' },
    '0C027FE0' => { 'rtr' => '04027FE0' , 'idx' =>    9 , 'extid' => '00259EEF360272' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCKED' },
    '0C02BFE0' => { 'rtr' => '0402BFE0' , 'idx' =>   10 , 'extid' => '006D634F6402E8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2' },
    '0C02FFE0' => { 'rtr' => '0402FFE0' , 'idx' =>   11 , 'extid' => 'E555E4E11002E9' , 'max' =>       40 , 'min' =>      -30 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2_TEMP' },
    '0C033FE0' => { 'rtr' => '04033FE0' , 'idx' =>   12 , 'extid' => 'E23123FC9F02EA' , 'max' =>      180 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2_TIME' },
    '0C03BFE0' => { 'rtr' => '0403BFE0' , 'idx' =>   14 , 'extid' => 'E5B8B81B2E02EB' , 'max' =>       20 , 'min' =>      -26 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_TIME_CONTROL_TEMPERATURE_LIMIT' },
    '0C03FFE0' => { 'rtr' => '0403FFE0' , 'idx' =>   15 , 'extid' => 'E1C80ADF0D069E' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_1' },
    '0C043FE0' => { 'rtr' => '04043FE0' , 'idx' =>   16 , 'extid' => 'E151038EB706A1' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_2' },
    '0C047FE0' => { 'rtr' => '04047FE0' , 'idx' =>   17 , 'extid' => 'E12604BE2106A2' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_3' },
    '0C04BFE0' => { 'rtr' => '0404BFE0' , 'idx' =>   18 , 'extid' => 'E1B8602B8206BD' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_4' },
    '0C04FFE0' => { 'rtr' => '0404FFE0' , 'idx' =>   19 , 'extid' => '4A9EDFA5490CBA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CURRENT_EFFECT_LIMITATION' },
    '0C057FE0' => { 'rtr' => '04057FE0' , 'idx' =>   21 , 'extid' => 'E1A12688970225' , 'max' =>      240 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_DELAY_TIME' },
    '0C05BFE0' => { 'rtr' => '0405BFE0' , 'idx' =>   22 , 'extid' => 'C02D7CE3A909E9' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_DHW_ACKNOWLEDGED' },
    '0C05FFE0' => { 'rtr' => '0405FFE0' , 'idx' =>   23 , 'extid' => 'EDD21CF87202EE' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_DHW_HYSTERESIS' },
    '0C063FE0' => { 'rtr' => '04063FE0' , 'idx' =>   24 , 'extid' => 'E5311E7EC202ED' , 'max' =>       10 , 'min' =>      -10 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_DHW_TEMP_CHANGE' },
    '0C067FE0' => { 'rtr' => '04067FE0' , 'idx' =>   25 , 'extid' => 'EAE9C03814036E' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EFFECT_LIMITATION_COMPRESSOR' },
    '0C06FFE0' => { 'rtr' => '0406FFE0' , 'idx' =>   27 , 'extid' => 'EAB88C0518036B' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EFFECT_LIMITATION_DHW' },
    '0C077FE0' => { 'rtr' => '04077FE0' , 'idx' =>   29 , 'extid' => 'EA0F167017036F' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EFFECT_LIMITATION_NO_COMPRESSOR' },
    '0C07FFE0' => { 'rtr' => '0407FFE0' , 'idx' =>   31 , 'extid' => '217E7826980226' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_ELECTRIC_COUNT' },
    '0C083FE0' => { 'rtr' => '04083FE0' , 'idx' =>   32 , 'extid' => '2AB28E7F270424' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_1' },
    '0C08BFE0' => { 'rtr' => '0408BFE0' , 'idx' =>   34 , 'extid' => '2A2B872E9D0425' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_2' },
    '0C093FE0' => { 'rtr' => '04093FE0' , 'idx' =>   36 , 'extid' => '2A5C801E0B0426' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_3' },
    '0C09BFE0' => { 'rtr' => '0409BFE0' , 'idx' =>   38 , 'extid' => '2AC2E48BA80427' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_4' },
    '0C0A3FE0' => { 'rtr' => '040A3FE0' , 'idx' =>   40 , 'extid' => '2A7E1A6660069D' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_1' },
    '0C0ABFE0' => { 'rtr' => '040ABFE0' , 'idx' =>   42 , 'extid' => '2AE71337DA069F' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_2' },
    '0C0B3FE0' => { 'rtr' => '040B3FE0' , 'idx' =>   44 , 'extid' => '2A9014074C06C1' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_3' },
    '0C0BBFE0' => { 'rtr' => '040BBFE0' , 'idx' =>   46 , 'extid' => '2A0E7092EF06A0' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_4' },
    '0C0C3FE0' => { 'rtr' => '040C3FE0' , 'idx' =>   48 , 'extid' => 'C0AB5157E30366' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_LIMITATION' },
    '0C0C7FE0' => { 'rtr' => '040C7FE0' , 'idx' =>   49 , 'extid' => 'E21D07AE5B0758' , 'max' =>      600 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_LIMITATION_TIME' },
    '0C0CFFE0' => { 'rtr' => '040CFFE0' , 'idx' =>   51 , 'extid' => 'E20696EC690364' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_RAMP_DOWN_TIME' },
    '0C0D7FE0' => { 'rtr' => '040D7FE0' , 'idx' =>   53 , 'extid' => 'E2E5F030A80363' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_RAMP_UP_TIME' },
    '0C0DFFE0' => { 'rtr' => '040DFFE0' , 'idx' =>   55 , 'extid' => 'E90DD98AE80365' , 'max' =>      100 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_SIZE' },
    '0C0E3FE0' => { 'rtr' => '040E3FE0' , 'idx' =>   56 , 'extid' => '00CC181667030A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCKED' },
    '0C0E7FE0' => { 'rtr' => '040E7FE0' , 'idx' =>   57 , 'extid' => 'C011831BA40304' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E21_EXT_1' },
    '0C0EBFE0' => { 'rtr' => '040EBFE0' , 'idx' =>   58 , 'extid' => 'C0888A4A1E048C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E21_EXT_2' },
    '0C0EFFE0' => { 'rtr' => '040EFFE0' , 'idx' =>   59 , 'extid' => 'C0206B01390B4E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E22_EXT_1' },
    '0C0F3FE0' => { 'rtr' => '040F3FE0' , 'idx' =>   60 , 'extid' => 'C0B96250830B4D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E22_EXT_2' },
    '0C0F7FE0' => { 'rtr' => '040F7FE0' , 'idx' =>   61 , 'extid' => '0E0794AB25026F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_GTf_AVERAGE' },
    '0C0FFFE0' => { 'rtr' => '040FFFE0' , 'idx' =>   63 , 'extid' => '0E2D19B8A50270' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_GTf_AVERAGE_OLD' },
    '0C107FE0' => { 'rtr' => '04107FE0' , 'idx' =>   65 , 'extid' => 'E2B490501D0367' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_DEFROST_DELAY_TIME' },
    '0C10FFE0' => { 'rtr' => '0410FFE0' , 'idx' =>   67 , 'extid' => 'E95D82721503B1' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T1_MAX' },
    '0C113FE0' => { 'rtr' => '04113FE0' , 'idx' =>   68 , 'extid' => 'E9870C05F30912' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T1_START' },
    '0C117FE0' => { 'rtr' => '04117FE0' , 'idx' =>   69 , 'extid' => 'E9509210640911' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T8_MAX' },
    '0C11BFE0' => { 'rtr' => '0411BFE0' , 'idx' =>   70 , 'extid' => 'E91294402003B0' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T8_START' },
    '0C11FFE0' => { 'rtr' => '0411FFE0' , 'idx' =>   71 , 'extid' => '01E185D8D10C92' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN' },
    '0C123FE0' => { 'rtr' => '04123FE0' , 'idx' =>   72 , 'extid' => '807FA9F59B0C83' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E21_EXT_1' },
    '0C127FE0' => { 'rtr' => '04127FE0' , 'idx' =>   73 , 'extid' => '80E6A0A4210C8C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E21_EXT_2' },
    '0C12BFE0' => { 'rtr' => '0412BFE0' , 'idx' =>   74 , 'extid' => '804E41EF060C84' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E22_EXT_1' },
    '0C12FFE0' => { 'rtr' => '0412FFE0' , 'idx' =>   75 , 'extid' => '80D748BEBC0C85' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E22_EXT_2' },
    '0C133FE0' => { 'rtr' => '04133FE0' , 'idx' =>   76 , 'extid' => '00D8B508CB0C93' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN' },
    '0C137FE0' => { 'rtr' => '04137FE0' , 'idx' =>   77 , 'extid' => '8011C1E2650C87' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E21_EXT_1' },
    '0C13BFE0' => { 'rtr' => '0413BFE0' , 'idx' =>   78 , 'extid' => '8088C8B3DF0C8A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E21_EXT_2' },
    '0C13FFE0' => { 'rtr' => '0413FFE0' , 'idx' =>   79 , 'extid' => '802029F8F80C88' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E22_EXT_1' },
    '0C143FE0' => { 'rtr' => '04143FE0' , 'idx' =>   80 , 'extid' => '80B920A9420C89' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E22_EXT_2' },
    '0C147FE0' => { 'rtr' => '04147FE0' , 'idx' =>   81 , 'extid' => 'A9B293795F0CDA' , 'max' =>       90 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E21_EXT_1' },
    '0C14BFE0' => { 'rtr' => '0414BFE0' , 'idx' =>   82 , 'extid' => 'A92B9A28E50CD2' , 'max' =>       90 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E21_EXT_2' },
    '0C14FFE0' => { 'rtr' => '0414FFE0' , 'idx' =>   83 , 'extid' => '89837B63C20CD0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E22_EXT_1' },
    '0C153FE0' => { 'rtr' => '04153FE0' , 'idx' =>   84 , 'extid' => '891A7232780CD1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E22_EXT_2' },
    '0C157FE0' => { 'rtr' => '04157FE0' , 'idx' =>   85 , 'extid' => '093AFAB92E0CD3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_EXTERN' },
    '0C15BFE0' => { 'rtr' => '0415BFE0' , 'idx' =>   86 , 'extid' => '01BD93F23E0C7E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN' },
    '0C15FFE0' => { 'rtr' => '0415FFE0' , 'idx' =>   87 , 'extid' => 'A1E12D84300C7A' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E21_EXT_1' },
    '0C163FE0' => { 'rtr' => '04163FE0' , 'idx' =>   88 , 'extid' => 'A17824D58A0C7D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E21_EXT_2' },
    '0C167FE0' => { 'rtr' => '04167FE0' , 'idx' =>   89 , 'extid' => 'A1D0C59EAD0C7B' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E22_EXT_1' },
    '0C16BFE0' => { 'rtr' => '0416BFE0' , 'idx' =>   90 , 'extid' => 'A149CCCF170C7C' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E22_EXT_2' },
    '0C16FFE0' => { 'rtr' => '0416FFE0' , 'idx' =>   91 , 'extid' => '002E38E20103B8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_NEUTRALZONE_DECREASE' },
    '0C173FE0' => { 'rtr' => '04173FE0' , 'idx' =>   92 , 'extid' => '00B73AA32A03B7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_NEUTRALZONE_INCREASE' },
    '0C177FE0' => { 'rtr' => '04177FE0' , 'idx' =>   93 , 'extid' => '0202BF02BA0368' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_NEUTRALZONE_SIGNAL' },
    '0C17FFE0' => { 'rtr' => '0417FFE0' , 'idx' =>   95 , 'extid' => '0EE200FF460ACF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONE_STEP_START' },
    '0C187FE0' => { 'rtr' => '04187FE0' , 'idx' =>   97 , 'extid' => '0EC7626E190AD0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONE_STEP_STOP' },
    '0C18FFE0' => { 'rtr' => '0418FFE0' , 'idx' =>   99 , 'extid' => '006C61DE390475' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONLY' },
    '0C193FE0' => { 'rtr' => '04193FE0' , 'idx' =>  100 , 'extid' => 'E1E1264564035D' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONLY_RAMP_TIME' },
    '0C197FE0' => { 'rtr' => '04197FE0' , 'idx' =>  101 , 'extid' => '0092C1864A035F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONLY_SIGNAL_RAMP_UP' },
    '0C19BFE0' => { 'rtr' => '0419BFE0' , 'idx' =>  102 , 'extid' => 'EADBF44D0603DA' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_D' },
    '0C1A3FE0' => { 'rtr' => '041A3FE0' , 'idx' =>  104 , 'extid' => 'EAA54531BB0371' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_I' },
    '0C1ABFE0' => { 'rtr' => '041ABFE0' , 'idx' =>  106 , 'extid' => 'E69CEDCFAD0568' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_MAX' },
    '0C1B3FE0' => { 'rtr' => '041B3FE0' , 'idx' =>  108 , 'extid' => 'E6A0E0F0F40569' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_MIN' },
    '0C1BBFE0' => { 'rtr' => '041BBFE0' , 'idx' =>  110 , 'extid' => 'EAC12E997B0370' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_P' },
    '0C1C3FE0' => { 'rtr' => '041C3FE0' , 'idx' =>  112 , 'extid' => '00AE75211705AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_ALLOW' },
    '0C1C7FE0' => { 'rtr' => '041C7FE0' , 'idx' =>  113 , 'extid' => 'E28C6BDACD0567' , 'max' =>     1200 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_DELAY_TIME' },
    '0C1CFFE0' => { 'rtr' => '041CFFE0' , 'idx' =>  115 , 'extid' => 'E1CBBD4F6E0690' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_MODE' },
    '0C1D3FE0' => { 'rtr' => '041D3FE0' , 'idx' =>  116 , 'extid' => 'E10C545F0B05B0' , 'max' =>       30 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_RAMP_DOWN_TIME' },
    '0C1D7FE0' => { 'rtr' => '041D7FE0' , 'idx' =>  117 , 'extid' => 'E12F4A191405AF' , 'max' =>       30 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_RAMP_UP_TIME' },
    '0C1DBFE0' => { 'rtr' => '041DBFE0' , 'idx' =>  118 , 'extid' => 'C2823936FB02F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_FRI' },
    '0C1E3FE0' => { 'rtr' => '041E3FE0' , 'idx' =>  120 , 'extid' => 'C2EF6420A502F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_MON' },
    '0C1EBFE0' => { 'rtr' => '041EBFE0' , 'idx' =>  122 , 'extid' => 'C29A3D7A2B02F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_SAT' },
    '0C1F3FE0' => { 'rtr' => '041F3FE0' , 'idx' =>  124 , 'extid' => 'C249F1540402F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_SUN' },
    '0C1FBFE0' => { 'rtr' => '041FBFE0' , 'idx' =>  126 , 'extid' => 'C239B7E77102F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_THU' },
    '0C203FE0' => { 'rtr' => '04203FE0' , 'idx' =>  128 , 'extid' => 'C2DB6C9B0902F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_TUE' },
    '0C20BFE0' => { 'rtr' => '0420BFE0' , 'idx' =>  130 , 'extid' => 'C2E4EF079702F5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_WED' },
    '0C213FE0' => { 'rtr' => '04213FE0' , 'idx' =>  132 , 'extid' => '000E7D2BD10275' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_RAMP_DECREASE' },
    '0C217FE0' => { 'rtr' => '04217FE0' , 'idx' =>  133 , 'extid' => '00977F6AFA0274' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_RAMP_INCREASE' },
    '0C21BFE0' => { 'rtr' => '0421BFE0' , 'idx' =>  134 , 'extid' => '0062413F450276' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_RAMP_INCREASE_DHW' },
    '0C21FFE0' => { 'rtr' => '0421FFE0' , 'idx' =>  135 , 'extid' => '00C45C8B2900EF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_REQUEST' },
    '0C223FE0' => { 'rtr' => '04223FE0' , 'idx' =>  136 , 'extid' => '0AB062530C036C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL' },
    '0C22BFE0' => { 'rtr' => '0422BFE0' , 'idx' =>  138 , 'extid' => '0A9F59CAF40362' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_FASTKONDENSERING' },
    '0C233FE0' => { 'rtr' => '04233FE0' , 'idx' =>  140 , 'extid' => '0AC60AD71C0369' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_LIMITATION' },
    '0C23BFE0' => { 'rtr' => '0423BFE0' , 'idx' =>  142 , 'extid' => '0A9B74327B0361' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_NORMAL' },
    '0C243FE0' => { 'rtr' => '04243FE0' , 'idx' =>  144 , 'extid' => '0A38B75244035E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_ONLY' },
    '0C24BFE0' => { 'rtr' => '0424BFE0' , 'idx' =>  146 , 'extid' => '0A361A0A65036A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_PID' },
    '0C253FE0' => { 'rtr' => '04253FE0' , 'idx' =>  148 , 'extid' => '0A77FFC89205E1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_POOL' },
    '0C25BFE0' => { 'rtr' => '0425BFE0' , 'idx' =>  150 , 'extid' => 'E03EA16AD70781' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TIMEPROGRAM' },
    '0C25FFE0' => { 'rtr' => '0425FFE0' , 'idx' =>  151 , 'extid' => 'C0292D044B063D' , 'max' => 83886080 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TIMER_EVU_ECONOMY_MODE' },
    '0C263FE0' => { 'rtr' => '04263FE0' , 'idx' =>  152 , 'extid' => '0055F40C3F0271' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TIME_CONTROL_BLOCK' },
    '0C267FE0' => { 'rtr' => '04267FE0' , 'idx' =>  153 , 'extid' => 'EA4E687ACB036D' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TOTAL_EFFECT_PATRON' },
    '0C26FFE0' => { 'rtr' => '0426FFE0' , 'idx' =>  155 , 'extid' => 'C09241BB5C02EC' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_USER_BLOCKED' },
    '0C273FE0' => { 'rtr' => '04273FE0' , 'idx' =>  156 , 'extid' => 'C04081661B00F1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_USER_ONLY' },
    '0C277FE0' => { 'rtr' => '04277FE0' , 'idx' =>  157 , 'extid' => 'C0467902B40360' , 'max' =>167772160 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_USE_NEUTRALZONE_REGULATOR' },
    '0C27BFE0' => { 'rtr' => '0427BFE0' , 'idx' =>  158 , 'extid' => '000445723003B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_ALLOW' },
    '0C27FFE0' => { 'rtr' => '0427FFE0' , 'idx' =>  159 , 'extid' => 'E11214DDA003B6' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_CLOSE_TIME' },
    '0C283FE0' => { 'rtr' => '04283FE0' , 'idx' =>  160 , 'extid' => 'E156B1386603C1' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_DELAY_TIME' },
    '0C287FE0' => { 'rtr' => '04287FE0' , 'idx' =>  161 , 'extid' => '0AEA24380D0558' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_MEASUREMENT' },
    '0C28FFE0' => { 'rtr' => '0428FFE0' , 'idx' =>  163 , 'extid' => 'E1F95E6C7603B5' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_OPEN_TIME' },
    '0C293FE0' => { 'rtr' => '04293FE0' , 'idx' =>  164 , 'extid' => 'E27C7972AA03B4' , 'max' =>     1200 , 'min' =>       60 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_RUNNING_TIME' },
    '0C29BFE0' => { 'rtr' => '0429BFE0' , 'idx' =>  166 , 'extid' => '22C710E3E906C4' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_SIGNAL' },
    '0C2A3FE0' => { 'rtr' => '042A3FE0' , 'idx' =>  168 , 'extid' => '8178B456B506BE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_BOOT_COUNT' },
    '0C2A7FE0' => { 'rtr' => '042A7FE0' , 'idx' =>  169 , 'extid' => '003F8061CD02AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED' },
    '0C2ABFE0' => { 'rtr' => '042ABFE0' , 'idx' =>  170 , 'extid' => '00F0CCC5A90428' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_2' },
    '0C2AFFE0' => { 'rtr' => '042AFFE0' , 'idx' =>  171 , 'extid' => '0087CBF53F0429' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_3' },
    '0C2B3FE0' => { 'rtr' => '042B3FE0' , 'idx' =>  172 , 'extid' => '0019AF609C042A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_4' },
    '0C2B7FE0' => { 'rtr' => '042B7FE0' , 'idx' =>  173 , 'extid' => '814669B75C063C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_BITMASK' },
    '0C2BBFE0' => { 'rtr' => '042BBFE0' , 'idx' =>  174 , 'extid' => '127C8850DE02AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION' },
    '0C2C3FE0' => { 'rtr' => '042C3FE0' , 'idx' =>  176 , 'extid' => '12C0FDC709042B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION_2' },
    '0C2CBFE0' => { 'rtr' => '042CBFE0' , 'idx' =>  178 , 'extid' => '12B7FAF79F042C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION_3' },
    '0C2D3FE0' => { 'rtr' => '042D3FE0' , 'idx' =>  180 , 'extid' => '12299E623C042D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION_4' },
    '0C2DBFE0' => { 'rtr' => '042DBFE0' , 'idx' =>  182 , 'extid' => '00210FED0F0024' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB9012_CONNECTED' },
    '0C2DFFE0' => { 'rtr' => '042DFFE0' , 'idx' =>  183 , 'extid' => '12BCCD3B430025' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB9012_VERSION' },
    '0C2E7FE0' => { 'rtr' => '042E7FE0' , 'idx' =>  185 , 'extid' => 'EAA75D6F5600BC' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ALARM_MODE_DELAY_TIME' },
    '0C2EFFE0' => { 'rtr' => '042EFFE0' , 'idx' =>  187 , 'extid' => '0079BAA67B00BB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ALARM_MODE_REQUEST' },
    '0C2F3FE0' => { 'rtr' => '042F3FE0' , 'idx' =>  188 , 'extid' => '01C8CB95950D6D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BACKWARDS_COMPABILITY_DUMMY' },
    '0C2F7FE0' => { 'rtr' => '042F7FE0' , 'idx' =>  189 , 'extid' => '452053AEAB082C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BIVALENCE_POINT' },
    '0C2FBFE0' => { 'rtr' => '042FBFE0' , 'idx' =>  190 , 'extid' => 'C0F9D977AE0027' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_BLOCKED' },
    '0C2FFFE0' => { 'rtr' => '042FFFE0' , 'idx' =>  191 , 'extid' => 'C2C2CD4F410028' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_BLOCK_START_TIME' },
    '0C307FE0' => { 'rtr' => '04307FE0' , 'idx' =>  193 , 'extid' => 'C2D6B5878C0029' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_BLOCK_STOP_TIME' },
    '0C30FFE0' => { 'rtr' => '0430FFE0' , 'idx' =>  195 , 'extid' => 'E10306B5220026' , 'max' =>       10 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_DELAY_TIME' },
    '0C313FE0' => { 'rtr' => '04313FE0' , 'idx' =>  196 , 'extid' => 'E2FE5D4E50002A' , 'max' =>     3600 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_INTERVAL' },
    '0C31BFE0' => { 'rtr' => '0431BFE0' , 'idx' =>  198 , 'extid' => 'A1D20884C30B9F' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DELTA_DHW' },
    '0C31FFE0' => { 'rtr' => '0431FFE0' , 'idx' =>  199 , 'extid' => 'A12A7C97D20BA1' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DELTA_HEATING' },
    '0C323FE0' => { 'rtr' => '04323FE0' , 'idx' =>  200 , 'extid' => '816686E05C0BB3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DHW_MEAN_VALUE' },
    '0C327FE0' => { 'rtr' => '04327FE0' , 'idx' =>  201 , 'extid' => '81929827B90BC8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DHW_MEAN_VALUE_CASCADE' },
    '0C32BFE0' => { 'rtr' => '0432BFE0' , 'idx' =>  202 , 'extid' => '002A5577090BD0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_GET_MEAN_VALUE' },
    '0C32FFE0' => { 'rtr' => '0432FFE0' , 'idx' =>  203 , 'extid' => '81E75046470BB4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_HEATING_MEAN_VALUE' },
    '0C333FE0' => { 'rtr' => '04333FE0' , 'idx' =>  204 , 'extid' => '81DFD38A800BC9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_HEATING_MEAN_VALUE_CASCADE' },
    '0C337FE0' => { 'rtr' => '04337FE0' , 'idx' =>  205 , 'extid' => 'A1D15B54A10BA3' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_IDLE_SPEED' },
    '0C33BFE0' => { 'rtr' => '0433BFE0' , 'idx' =>  206 , 'extid' => '0E78469DDB0BC2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_PID_CALCULATED_MEASUREMENT' },
    '0C343FE0' => { 'rtr' => '04343FE0' , 'idx' =>  208 , 'extid' => '0EEF76AB9E0BC0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_PID_SETPOINT' },
    '0C34BFE0' => { 'rtr' => '0434BFE0' , 'idx' =>  210 , 'extid' => '0177EF6F200BBC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_SIGNAL' },
    '0C34FFE0' => { 'rtr' => '0434FFE0' , 'idx' =>  211 , 'extid' => 'A1238E3ECC0CAE' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_USER_SET_PERCENT' },
    '0C353FE0' => { 'rtr' => '04353FE0' , 'idx' =>  212 , 'extid' => 'A1AE69A1180BB8' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DELTA_DHW' },
    '0C357FE0' => { 'rtr' => '04357FE0' , 'idx' =>  213 , 'extid' => 'A1C0FA4AB00BB9' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DELTA_HEATING' },
    '0C35BFE0' => { 'rtr' => '0435BFE0' , 'idx' =>  214 , 'extid' => '81C5D066F50BBE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DHW_MEAN_VALUE' },
    '0C35FFE0' => { 'rtr' => '0435FFE0' , 'idx' =>  215 , 'extid' => '81210C0A7A0BCA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DHW_MEAN_VALUE_CASCADE' },
    '0C363FE0' => { 'rtr' => '04363FE0' , 'idx' =>  216 , 'extid' => '008903F1A00BD1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_GET_MEAN_VALUE' },
    '0C367FE0' => { 'rtr' => '04367FE0' , 'idx' =>  217 , 'extid' => '8191B57F7A0BBF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_HEATING_MEAN_VALUE' },
    '0C36BFE0' => { 'rtr' => '0436BFE0' , 'idx' =>  218 , 'extid' => '81CCFBB3F30BCB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_HEATING_MEAN_VALUE_CASCADE' },
    '0C36FFE0' => { 'rtr' => '0436FFE0' , 'idx' =>  219 , 'extid' => 'A1C0263ED80BBA' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_IDLE_SPEED' },
    '0C373FE0' => { 'rtr' => '04373FE0' , 'idx' =>  220 , 'extid' => '0E6B6EA4A80BC3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_PID_CALCULATED_MEASUREMENT' },
    '0C37BFE0' => { 'rtr' => '0437BFE0' , 'idx' =>  222 , 'extid' => '0EBCECF01A0BC1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_PID_SETPOINT' },
    '0C383FE0' => { 'rtr' => '04383FE0' , 'idx' =>  224 , 'extid' => '01EE0D09210BBD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_SIGNAL' },
    '0C387FE0' => { 'rtr' => '04387FE0' , 'idx' =>  225 , 'extid' => 'A15890BC2F0CB0' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_USER_SET_PERCENT' },
    '0C38BFE0' => { 'rtr' => '0438BFE0' , 'idx' =>  226 , 'extid' => '00BA9D50780AC8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E74_G1_DIGITAL' },
    '0C38FFE0' => { 'rtr' => '0438FFE0' , 'idx' =>  227 , 'extid' => 'A11E2049670C98' , 'max' =>       20 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_DELTA_DHW_AT_LOW_T12' },
    '0C393FE0' => { 'rtr' => '04393FE0' , 'idx' =>  228 , 'extid' => 'EA70F2D7870BAA' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_D' },
    '0C39BFE0' => { 'rtr' => '0439BFE0' , 'idx' =>  230 , 'extid' => 'EA0E43AB3A0BA8' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_I' },
    '0C3A3FE0' => { 'rtr' => '043A3FE0' , 'idx' =>  232 , 'extid' => 'EEAEAFB7FB0BAC' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_MAX' },
    '0C3ABFE0' => { 'rtr' => '043ABFE0' , 'idx' =>  234 , 'extid' => 'AE92A288A20BAE' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_MIN' },
    '0C3B3FE0' => { 'rtr' => '043B3FE0' , 'idx' =>  236 , 'extid' => 'EA6A2803FA0BA6' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_P' },
    '0C3BBFE0' => { 'rtr' => '043BBFE0' , 'idx' =>  238 , 'extid' => 'A96F5A7BEB0BB2' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_VOLTAGE_AT_0' },
    '0C3BFFE0' => { 'rtr' => '043BFFE0' , 'idx' =>  239 , 'extid' => 'A9C3D9935E0BB0' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_VOLTAGE_AT_100' },
    '0C3C3FE0' => { 'rtr' => '043C3FE0' , 'idx' =>  240 , 'extid' => '008A02C3120B8F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_BASECARD_E21_RESTART_DETECTED' },
    '0C3C7FE0' => { 'rtr' => '043C7FE0' , 'idx' =>  241 , 'extid' => '0060841E700B90' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_BASECARD_E22_RESTART_DETECTED' },
    '0C3CBFE0' => { 'rtr' => '043CBFE0' , 'idx' =>  242 , 'extid' => '014C6EDFE60B72' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_FAILED_SENDINGS' },
    '0C3CFFE0' => { 'rtr' => '043CFFE0' , 'idx' =>  243 , 'extid' => '01F7194E700D57' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_SEND_SEC_ROOMSENSOR_STATUS' },
    '0C3D3FE0' => { 'rtr' => '043D3FE0' , 'idx' =>  244 , 'extid' => '01F31C60B8046B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSORS_CONNECTED_COUNT' },
    '0C3D7FE0' => { 'rtr' => '043D7FE0' , 'idx' =>  245 , 'extid' => '0018D2D12D00B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_ALARM' },
    '0C3DBFE0' => { 'rtr' => '043DBFE0' , 'idx' =>  246 , 'extid' => '0065D3A29B0484' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_ALARM_2' },
    '0C3DFFE0' => { 'rtr' => '043DFFE0' , 'idx' =>  247 , 'extid' => '000E6864FD0476' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_BLOCKED' },
    '0C3E3FE0' => { 'rtr' => '043E3FE0' , 'idx' =>  248 , 'extid' => '005FE0363D0A2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_BLOCKED_2' },
    '0C3E7FE0' => { 'rtr' => '043E7FE0' , 'idx' =>  249 , 'extid' => '162F92312F0A7A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS' },
    '0C3EFFE0' => { 'rtr' => '043EFFE0' , 'idx' =>  251 , 'extid' => '16F7EF15210A7B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS_2' },
    '0C3F7FE0' => { 'rtr' => '043F7FE0' , 'idx' =>  253 , 'extid' => '16654560AA0A7C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS_FILTERED' },
    '0C3FFFE0' => { 'rtr' => '043FFFE0' , 'idx' =>  255 , 'extid' => '16AD77529A0A7D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS_FILTERED_2' },
    '0C407FE0' => { 'rtr' => '04407FE0' , 'idx' =>  257 , 'extid' => 'C1980C123400B0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_FREQUENCY_MAX' },
    '0C40BFE0' => { 'rtr' => '0440BFE0' , 'idx' =>  258 , 'extid' => 'C1A4012D6D00B1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_FREQUENCY_MIN' },
    '0C40FFE0' => { 'rtr' => '0440FFE0' , 'idx' =>  259 , 'extid' => 'C1C61B2E0400AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_T1_SETPOINT_MAX' },
    '0C413FE0' => { 'rtr' => '04413FE0' , 'idx' =>  260 , 'extid' => 'C1FA16115D00AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_T1_SETPOINT_MIN' },
    '0C417FE0' => { 'rtr' => '04417FE0' , 'idx' =>  261 , 'extid' => '01A00CFA280252' , 'max' =>      230 , 'min' =>      400 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_DHW_REQUEST' },
    '0C41BFE0' => { 'rtr' => '0441BFE0' , 'idx' =>  262 , 'extid' => '00F55C2F800303' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCKED' },
    '0C41FFE0' => { 'rtr' => '0441FFE0' , 'idx' =>  263 , 'extid' => 'C092971E2F0309' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E21_EXT_1' },
    '0C423FE0' => { 'rtr' => '04423FE0' , 'idx' =>  264 , 'extid' => 'C00B9E4F95048B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E21_EXT_2' },
    '0C427FE0' => { 'rtr' => '04427FE0' , 'idx' =>  265 , 'extid' => 'C0A37F04B20B4B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E22_EXT_1' },
    '0C42BFE0' => { 'rtr' => '0442BFE0' , 'idx' =>  266 , 'extid' => 'C03A7655080B4C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E22_EXT_2' },
    '0C42FFE0' => { 'rtr' => '0442FFE0' , 'idx' =>  267 , 'extid' => '00DC949B720B29' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCKED' },
    '0C433FE0' => { 'rtr' => '04433FE0' , 'idx' =>  268 , 'extid' => 'C0210333EC0B75' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E21_EXT_1' },
    '0C437FE0' => { 'rtr' => '04437FE0' , 'idx' =>  269 , 'extid' => 'C0B80A62560B76' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E21_EXT_2' },
    '0C43BFE0' => { 'rtr' => '0443BFE0' , 'idx' =>  270 , 'extid' => 'C010EB29710B77' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E22_EXT_1' },
    '0C43FFE0' => { 'rtr' => '0443FFE0' , 'idx' =>  271 , 'extid' => 'C089E278CB0B78' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E22_EXT_2' },
    '0C443FE0' => { 'rtr' => '04443FE0' , 'idx' =>  272 , 'extid' => '00BA167A090B8E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_RESTART_HANDLING_TRIGGED' },
    '0C447FE0' => { 'rtr' => '04447FE0' , 'idx' =>  273 , 'extid' => '01E2A43EA50251' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_HEATING_REQUEST' },
    '0C44BFE0' => { 'rtr' => '0444BFE0' , 'idx' =>  274 , 'extid' => 'E18ABA5E9100B4' , 'max' =>       90 , 'min' =>       24 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_MAX_FREQUENCY' },
    '0C44FFE0' => { 'rtr' => '0444FFE0' , 'idx' =>  275 , 'extid' => 'E1BA260302017A' , 'max' =>      120 , 'min' =>       24 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_MAX_FREQUENCY_DEV' },
    '0C453FE0' => { 'rtr' => '04453FE0' , 'idx' =>  276 , 'extid' => 'E1CAF526E700B5' , 'max' =>       86 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_MIN_FREQUENCY' },
    '0C457FE0' => { 'rtr' => '04457FE0' , 'idx' =>  277 , 'extid' => '00205AC16100B6' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_QUICKSTART' },
    '0C45BFE0' => { 'rtr' => '0445BFE0' , 'idx' =>  278 , 'extid' => '014AF08A5700AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_REAL_FREQUENCY' },
    '0C45FFE0' => { 'rtr' => '0445FFE0' , 'idx' =>  279 , 'extid' => 'E16A8A67F000AD' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_RESTART_TIME' },
    '0C463FE0' => { 'rtr' => '04463FE0' , 'idx' =>  280 , 'extid' => 'C1BCC2391E0A63' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE' },
    '0C467FE0' => { 'rtr' => '04467FE0' , 'idx' =>  281 , 'extid' => 'C13F6909F10A64' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_2' },
    '0C46BFE0' => { 'rtr' => '0446BFE0' , 'idx' =>  282 , 'extid' => 'C1EF785A580B15' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_2_DISPLAY_VALUE' },
    '0C46FFE0' => { 'rtr' => '0446FFE0' , 'idx' =>  283 , 'extid' => 'C1565C20C20B14' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_DISPLAY_VALUE' },
    '0C473FE0' => { 'rtr' => '04473FE0' , 'idx' =>  284 , 'extid' => '8178F2D1C80A78' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_INDEX' },
    '0C477FE0' => { 'rtr' => '04477FE0' , 'idx' =>  285 , 'extid' => '8146DAC5120A79' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_INDEX_2' },
    '0C47BFE0' => { 'rtr' => '0447BFE0' , 'idx' =>  286 , 'extid' => 'E95C34D4210A75' , 'max' =>      170 , 'min' =>       60 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_LW' },
    '0C47FFE0' => { 'rtr' => '0447FFE0' , 'idx' =>  287 , 'extid' => 'E9B90C5DFE0A76' , 'max' =>      170 , 'min' =>       60 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_LW_2' },
    '0C483FE0' => { 'rtr' => '04483FE0' , 'idx' =>  288 , 'extid' => '00F334C27F00B7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START' },
    '0C487FE0' => { 'rtr' => '04487FE0' , 'idx' =>  289 , 'extid' => 'E10A600FE900B9' , 'max' =>       80 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STARTUP_FREQUENCY' },
    '0C48BFE0' => { 'rtr' => '0448BFE0' , 'idx' =>  290 , 'extid' => 'E1A47B5B1C00B8' , 'max' =>       10 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STARTUP_TIME' },
    '0C48FFE0' => { 'rtr' => '0448FFE0' , 'idx' =>  291 , 'extid' => '0069E037750692' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_2' },
    '0C493FE0' => { 'rtr' => '04493FE0' , 'idx' =>  292 , 'extid' => 'E2E5F581E50346' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_DELAY_TIME' },
    '0C49BFE0' => { 'rtr' => '0449BFE0' , 'idx' =>  294 , 'extid' => '01CFDE450B00B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STATE' },
    '0C49FFE0' => { 'rtr' => '0449FFE0' , 'idx' =>  295 , 'extid' => '01516FA1EE0664' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STATE_2' },
    '0C4A3FE0' => { 'rtr' => '044A3FE0' , 'idx' =>  296 , 'extid' => 'E1C7DC4A5D0857' , 'max' =>        2 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_TYPE' },
    '0C4A7FE0' => { 'rtr' => '044A7FE0' , 'idx' =>  297 , 'extid' => 'E12D314EAF0858' , 'max' =>        2 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_TYPE_2' },
    '0C4ABFE0' => { 'rtr' => '044ABFE0' , 'idx' =>  298 , 'extid' => 'C06BA159820867' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_USE_START_DELAY_TIME' },
    '0C4AFFE0' => { 'rtr' => '044AFFE0' , 'idx' =>  299 , 'extid' => 'C183AEA732025B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'CONFIGURATION' },
    '0C4B3FE0' => { 'rtr' => '044B3FE0' , 'idx' =>  300 , 'extid' => 'E1AD68C52C0672' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CONFIGURATION_BUDERUS' },
    '0C4B7FE0' => { 'rtr' => '044B7FE0' , 'idx' =>  301 , 'extid' => 'E168431B5E00BA' , 'max' =>       30 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COOLING_FAN_STOP_DELAY_TIME' },
    '0C4BBFE0' => { 'rtr' => '044BBFE0' , 'idx' =>  302 , 'extid' => '826C36377C0B7F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COUNTRY' },
    '0C4C3FE0' => { 'rtr' => '044C3FE0' , 'idx' =>  304 , 'extid' => '82DE2C76BC0B0A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CPU_BOOT_COUNTER' },
    '0C4CBFE0' => { 'rtr' => '044CBFE0' , 'idx' =>  306 , 'extid' => 'E5778117E50240' , 'max' =>       20 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'CRANKCASE_HEATER_BLOCK_TEMP' },
    '0C4CFFE0' => { 'rtr' => '044CFFE0' , 'idx' =>  307 , 'extid' => '214D9712D5035B' , 'max' =>        7 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CURRENT_M_VALVE' },
    '0C4D3FE0' => { 'rtr' => '044D3FE0' , 'idx' =>  308 , 'extid' => '0132AD5D97002B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_DAY' },
    '0C4D7FE0' => { 'rtr' => '044D7FE0' , 'idx' =>  309 , 'extid' => '016D8A0DD9002C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_DAY_OF_WEEK' },
    '0C4DBFE0' => { 'rtr' => '044DBFE0' , 'idx' =>  310 , 'extid' => '01D5C3A951002D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_HOUR' },
    '0C4DFFE0' => { 'rtr' => '044DFFE0' , 'idx' =>  311 , 'extid' => '01767669D7002E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_MIN' },
    '0C4E3FE0' => { 'rtr' => '044E3FE0' , 'idx' =>  312 , 'extid' => '013875E083002F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_MONTH' },
    '0C4E7FE0' => { 'rtr' => '044E7FE0' , 'idx' =>  313 , 'extid' => '01B2CAD41C0030' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_SEC' },
    '0C4EBFE0' => { 'rtr' => '044EBFE0' , 'idx' =>  314 , 'extid' => '011E5FCB280031' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_YEAR' },
    '0C4EFFE0' => { 'rtr' => '044EFFE0' , 'idx' =>  315 , 'extid' => 'E1478EE36601EB' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_0_DELTA_TEMPERATURE' },
    '0C4F3FE0' => { 'rtr' => '044F3FE0' , 'idx' =>  316 , 'extid' => 'E1BE893A89067B' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_0_DELTA_TEMPERATURE_2' },
    '0C4F7FE0' => { 'rtr' => '044F7FE0' , 'idx' =>  317 , 'extid' => '00594AFA3802D1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BATTERY' },
    '0C4FBFE0' => { 'rtr' => '044FBFE0' , 'idx' =>  318 , 'extid' => '00FEDAFC570671' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BATTERY_2' },
    '0C4FFFE0' => { 'rtr' => '044FFFE0' , 'idx' =>  319 , 'extid' => 'E1DB78084F01F6' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_DELAY_TIME' },
    '0C503FE0' => { 'rtr' => '04503FE0' , 'idx' =>  320 , 'extid' => 'E1CD1702640686' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_DELAY_TIME_2' },
    '0C507FE0' => { 'rtr' => '04507FE0' , 'idx' =>  321 , 'extid' => '0028AC53CD02D2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE' },
    '0C50BFE0' => { 'rtr' => '0450BFE0' , 'idx' =>  322 , 'extid' => '00381B83050678' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE_2' },
    '0C50FFE0' => { 'rtr' => '0450FFE0' , 'idx' =>  323 , 'extid' => '00E31CF38F0A84' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE_2_CLOSING_DOWN' },
    '0C513FE0' => { 'rtr' => '04513FE0' , 'idx' =>  324 , 'extid' => '00A95A4B5A0A83' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE_CLOSING_DOWN' },
    '0C517FE0' => { 'rtr' => '04517FE0' , 'idx' =>  325 , 'extid' => 'E2E90063A40A86' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_4_WAY_VALVE_2_SWITCH' },
    '0C51FFE0' => { 'rtr' => '0451FFE0' , 'idx' =>  327 , 'extid' => 'E285CADF680A7F' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_4_WAY_VALVE_SWITCH' },
    '0C527FE0' => { 'rtr' => '04527FE0' , 'idx' =>  329 , 'extid' => 'E2364CF4D30A85' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_COMPRESSOR_2_START' },
    '0C52FFE0' => { 'rtr' => '0452FFE0' , 'idx' =>  331 , 'extid' => 'E2534223110A80' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_COMPRESSOR_START' },
    '0C537FE0' => { 'rtr' => '04537FE0' , 'idx' =>  333 , 'extid' => '0EA7DC84360254' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_T12_T11' },
    '0C53FFE0' => { 'rtr' => '0453FFE0' , 'idx' =>  335 , 'extid' => '0ED7E473740687' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_T12_T11_2' },
    '0C547FE0' => { 'rtr' => '04547FE0' , 'idx' =>  337 , 'extid' => 'EE68A7B8090255' , 'max' =>      300 , 'min' =>       10 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TEMPERATURE' },
    '0C54FFE0' => { 'rtr' => '0454FFE0' , 'idx' =>  339 , 'extid' => 'EEA055EAB4067C' , 'max' =>      300 , 'min' =>       10 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TEMPERATURE_2' },
    '0C557FE0' => { 'rtr' => '04557FE0' , 'idx' =>  341 , 'extid' => 'E2FF8EAB6D01E5' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIME' },
    '0C55FFE0' => { 'rtr' => '0455FFE0' , 'idx' =>  343 , 'extid' => 'E2257A92E00688' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIME_2' },
    '0C567FE0' => { 'rtr' => '04567FE0' , 'idx' =>  345 , 'extid' => '00A5BB73C4027E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN' },
    '0C56BFE0' => { 'rtr' => '0456BFE0' , 'idx' =>  346 , 'extid' => '00D2B795930670' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_2' },
    '0C56FFE0' => { 'rtr' => '0456FFE0' , 'idx' =>  347 , 'extid' => '016189FB34027F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_COUNTER' },
    '0C573FE0' => { 'rtr' => '04573FE0' , 'idx' =>  348 , 'extid' => '012568BB0E0680' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_COUNTER_2' },
    '0C577FE0' => { 'rtr' => '04577FE0' , 'idx' =>  349 , 'extid' => 'E11D66580701FC' , 'max' =>        8 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_INTERVAL_COUNTER' },
    '0C57BFE0' => { 'rtr' => '0457BFE0' , 'idx' =>  350 , 'extid' => 'E19EDC50830682' , 'max' =>        8 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_INTERVAL_COUNTER_2' },
    '0C57FFE0' => { 'rtr' => '0457FFE0' , 'idx' =>  351 , 'extid' => 'E50E01998A01FF' , 'max' =>        0 , 'min' =>      -40 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TEMPERATURE_LIMIT' },
    '0C583FE0' => { 'rtr' => '04583FE0' , 'idx' =>  352 , 'extid' => 'E5FC9257C40683' , 'max' =>        0 , 'min' =>      -40 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TEMPERATURE_LIMIT_2' },
    '0C587FE0' => { 'rtr' => '04587FE0' , 'idx' =>  353 , 'extid' => 'E17B401DDE01FE' , 'max' =>       15 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIME' },
    '0C58BFE0' => { 'rtr' => '0458BFE0' , 'idx' =>  354 , 'extid' => 'E1C890FDEC0681' , 'max' =>       15 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIME_2' },
    '0C58FFE0' => { 'rtr' => '0458FFE0' , 'idx' =>  355 , 'extid' => 'EE72EB12CC01F0' , 'max' =>      400 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_GT11_STOP' },
    '0C597FE0' => { 'rtr' => '04597FE0' , 'idx' =>  357 , 'extid' => 'EE20DB99050685' , 'max' =>      400 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_GT11_STOP_2' },
    '0C59FFE0' => { 'rtr' => '0459FFE0' , 'idx' =>  359 , 'extid' => '203642ECD7027D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MANUAL_START' },
    '0C5A3FE0' => { 'rtr' => '045A3FE0' , 'idx' =>  360 , 'extid' => '20D3E8C92D0689' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MANUAL_START_2' },
    '0C5A7FE0' => { 'rtr' => '045A7FE0' , 'idx' =>  361 , 'extid' => 'A14A30D6610C77' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS' },
    '0C5ABFE0' => { 'rtr' => '045ABFE0' , 'idx' =>  362 , 'extid' => 'A1A77B65D30C78' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS_2' },
    '0C5AFFE0' => { 'rtr' => '045AFFE0' , 'idx' =>  363 , 'extid' => 'E1F3A5E00E01F1' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIME' },
    '0C5B3FE0' => { 'rtr' => '045B3FE0' , 'idx' =>  364 , 'extid' => 'E18AA43EB70684' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIME_2' },
    '0C5B7FE0' => { 'rtr' => '045B7FE0' , 'idx' =>  365 , 'extid' => 'E151AA9F3D01ED' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS10_DELTA_TEMPERATURE' },
    '0C5BBFE0' => { 'rtr' => '045BBFE0' , 'idx' =>  366 , 'extid' => 'E1BE759525067E' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS10_DELTA_TEMPERATURE_2' },
    '0C5BFFE0' => { 'rtr' => '045BFFE0' , 'idx' =>  367 , 'extid' => 'E1FE03D2F702CF' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS20_DELTA_TEMPERATURE' },
    '0C5C3FE0' => { 'rtr' => '045C3FE0' , 'idx' =>  368 , 'extid' => 'E1870D3865067F' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS20_DELTA_TEMPERATURE_2' },
    '0C5C7FE0' => { 'rtr' => '045C7FE0' , 'idx' =>  369 , 'extid' => 'E53A13971A027C' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_OUT_START_TEMPERATURE' },
    '0C5CBFE0' => { 'rtr' => '045CBFE0' , 'idx' =>  370 , 'extid' => 'E56A6BC4CB068A' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_OUT_START_TEMPERATURE_2' },
    '0C5CFFE0' => { 'rtr' => '045CFFE0' , 'idx' =>  371 , 'extid' => 'E12B1071C201E9' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_PLUS10_DELTA_TEMPERATURE' },
    '0C5D3FE0' => { 'rtr' => '045D3FE0' , 'idx' =>  372 , 'extid' => 'E16AE3DD92067D' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_PLUS10_DELTA_TEMPERATURE_2' },
    '0C5D7FE0' => { 'rtr' => '045D7FE0' , 'idx' =>  373 , 'extid' => 'E2E83A284101F5' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_QUIT_DELAY_TIME' },
    '0C5DFFE0' => { 'rtr' => '045DFFE0' , 'idx' =>  375 , 'extid' => 'E268FA3C60068B' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_QUIT_DELAY_TIME_2' },
    '0C5E7FE0' => { 'rtr' => '045E7FE0' , 'idx' =>  377 , 'extid' => '01B2F3810902D0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_REQUEST' },
    '0C5EBFE0' => { 'rtr' => '045EBFE0' , 'idx' =>  378 , 'extid' => '01FF50B8E8068C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_REQUEST_2' },
    '0C5EFFE0' => { 'rtr' => '045EFFE0' , 'idx' =>  379 , 'extid' => '0062329BE402B4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_BLOCKED' },
    '0C5F3FE0' => { 'rtr' => '045F3FE0' , 'idx' =>  380 , 'extid' => 'C0016372BE05C1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_BLOCK_SWITCH_TO_HEATING' },
    '0C5F7FE0' => { 'rtr' => '045F7FE0' , 'idx' =>  381 , 'extid' => '020E51A0000CA7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_E21_T3_START_TEMP_SEC_PER_TENTH_ADJ' },
    '0C5FFFE0' => { 'rtr' => '045FFFE0' , 'idx' =>  383 , 'extid' => '02554611150CA8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_E22_T3_START_TEMP_SEC_PER_TENTH_ADJ' },
    '0C607FE0' => { 'rtr' => '04607FE0' , 'idx' =>  385 , 'extid' => 'EE5991A93A02B8' , 'max' =>      700 , 'min' =>      400 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_CALCULATED_SETPOINT_TEMP' },
    '0C60FFE0' => { 'rtr' => '0460FFE0' , 'idx' =>  387 , 'extid' => 'EE38A21E6702B9' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_CALCULATED_SETPOINT_TEMP_OFFSET' },
    '0C617FE0' => { 'rtr' => '04617FE0' , 'idx' =>  389 , 'extid' => 'A109D86C650CA6' , 'max' =>       24 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_T3_DHW_LOADING_INTERVAL' },
    '0C61BFE0' => { 'rtr' => '0461BFE0' , 'idx' =>  390 , 'extid' => '8E27406FC50CA4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_T3_START_TEMP_MIN_VALUE' },
    '0C623FE0' => { 'rtr' => '04623FE0' , 'idx' =>  392 , 'extid' => 'C1EE64B5700106' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_FREQUENCY_MAX' },
    '0C627FE0' => { 'rtr' => '04627FE0' , 'idx' =>  393 , 'extid' => 'C1D2698A290107' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_FREQUENCY_MIN' },
    '0C62BFE0' => { 'rtr' => '0462BFE0' , 'idx' =>  394 , 'extid' => 'C50188E15E0104' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_GT8_MAX' },
    '0C62FFE0' => { 'rtr' => '0462FFE0' , 'idx' =>  395 , 'extid' => 'C53D85DE070105' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_GT8_MIN' },
    '0C633FE0' => { 'rtr' => '04633FE0' , 'idx' =>  396 , 'extid' => 'C165168E69010A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_FREQUENCY_MAX' },
    '0C637FE0' => { 'rtr' => '04637FE0' , 'idx' =>  397 , 'extid' => 'C1591BB130010B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_FREQUENCY_MIN' },
    '0C63BFE0' => { 'rtr' => '0463BFE0' , 'idx' =>  398 , 'extid' => 'C5D1D8285F0108' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_GT2_MAX' },
    '0C63FFE0' => { 'rtr' => '0463FFE0' , 'idx' =>  399 , 'extid' => 'C5EDD517060109' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_GT2_MIN' },
    '0C643FE0' => { 'rtr' => '04643FE0' , 'idx' =>  400 , 'extid' => '40A21CB6040B17' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP' },
    '0C647FE0' => { 'rtr' => '04647FE0' , 'idx' =>  401 , 'extid' => 'E10BD3703C0B1B' , 'max' =>       10 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    '0C64BFE0' => { 'rtr' => '0464BFE0' , 'idx' =>  402 , 'extid' => 'E96A54E9FD0B1A' , 'max' =>      100 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP_DIFF' },
    '0C64FFE0' => { 'rtr' => '0464FFE0' , 'idx' =>  403 , 'extid' => '56F99731110B21' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP_SAVED_GT3' },
    '0C657FE0' => { 'rtr' => '04657FE0' , 'idx' =>  405 , 'extid' => '4011889BC70B18' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP' },
    '0C65BFE0' => { 'rtr' => '0465BFE0' , 'idx' =>  406 , 'extid' => 'E150C4C1290B1C' , 'max' =>       10 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    '0C65FFE0' => { 'rtr' => '0465FFE0' , 'idx' =>  407 , 'extid' => 'E9A34BE1420B19' , 'max' =>      100 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP_DIFF' },
    '0C663FE0' => { 'rtr' => '04663FE0' , 'idx' =>  408 , 'extid' => '56A3F60E710B22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP_SAVED_GT3' },
    '0C66BFE0' => { 'rtr' => '0466BFE0' , 'idx' =>  410 , 'extid' => '00D3E359CF030B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCKED' },
    '0C66FFE0' => { 'rtr' => '0466FFE0' , 'idx' =>  411 , 'extid' => 'C084B462440305' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E21_EXT_1' },
    '0C673FE0' => { 'rtr' => '04673FE0' , 'idx' =>  412 , 'extid' => 'C01DBD33FE0B56' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E21_EXT_2' },
    '0C677FE0' => { 'rtr' => '04677FE0' , 'idx' =>  413 , 'extid' => 'C0B55C78D9048D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E22_EXT_1' },
    '0C67BFE0' => { 'rtr' => '0467BFE0' , 'idx' =>  414 , 'extid' => 'C02C5529630B55' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E22_EXT_2' },
    '0C67FFE0' => { 'rtr' => '0467FFE0' , 'idx' =>  415 , 'extid' => 'EEB4A6964D02B6' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_MAX_TEMP' },
    '0C687FE0' => { 'rtr' => '04687FE0' , 'idx' =>  417 , 'extid' => 'EEE896B17B0654' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_START_MAX_TEMP_2' },
    '0C68FFE0' => { 'rtr' => '0468FFE0' , 'idx' =>  419 , 'extid' => '0EFA512A7A00FD' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP' },
    '0C697FE0' => { 'rtr' => '04697FE0' , 'idx' =>  421 , 'extid' => '0EBA46A01F066C' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_START_TEMP_2' },
    '0C69FFE0' => { 'rtr' => '0469FFE0' , 'idx' =>  423 , 'extid' => 'EE70936AA500FF' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_COMFORT' },
    '0C6A7FE0' => { 'rtr' => '046A7FE0' , 'idx' =>  425 , 'extid' => 'EECA3AB29D0658' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_COMFORT_2' },
    '0C6AFFE0' => { 'rtr' => '046AFFE0' , 'idx' =>  427 , 'extid' => 'EE681E964800FE' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_ECONOMY' },
    '0C6B7FE0' => { 'rtr' => '046B7FE0' , 'idx' =>  429 , 'extid' => 'EE95E199860659' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_ECONOMY_2' },
    '0C6BFFE0' => { 'rtr' => '046BFFE0' , 'idx' =>  431 , 'extid' => '0E9E09BB7B0CD8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_STOP_MIN_TEMP' },
    '0C6C7FE0' => { 'rtr' => '046C7FE0' , 'idx' =>  433 , 'extid' => '0E245556D40CD9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_STOP_MIN_TEMP_2' },
    '0C6CFFE0' => { 'rtr' => '046CFFE0' , 'idx' =>  435 , 'extid' => '0E5A602AB80100' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_STOP_TEMP' },
    '0C6D7FE0' => { 'rtr' => '046D7FE0' , 'idx' =>  437 , 'extid' => '0E438AB5E2066E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_STOP_TEMP_2' },
    '0C6DFFE0' => { 'rtr' => '046DFFE0' , 'idx' =>  439 , 'extid' => 'EEA69DB26402B7' , 'max' =>      640 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_MAX_TEMP' },
    '0C6E7FE0' => { 'rtr' => '046E7FE0' , 'idx' =>  441 , 'extid' => 'EE90D3D87A0655' , 'max' =>      640 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT8_STOP_MAX_TEMP_2' },
    '0C6EFFE0' => { 'rtr' => '046EFFE0' , 'idx' =>  443 , 'extid' => '0E7941ADFC0101' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP' },
    '0C6F7FE0' => { 'rtr' => '046F7FE0' , 'idx' =>  445 , 'extid' => '0EA4430A41066D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT8_STOP_TEMP_2' },
    '0C6FFFE0' => { 'rtr' => '046FFFE0' , 'idx' =>  447 , 'extid' => 'EE5DE6FA5D0103' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_COMFORT' },
    '0C707FE0' => { 'rtr' => '04707FE0' , 'idx' =>  449 , 'extid' => 'EEE6506719065A' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_COMFORT_2' },
    '0C70FFE0' => { 'rtr' => '0470FFE0' , 'idx' =>  451 , 'extid' => 'EE456B06B00102' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_ECONOMY' },
    '0C717FE0' => { 'rtr' => '04717FE0' , 'idx' =>  453 , 'extid' => 'EEB98B4C02065B' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_ECONOMY_2' },
    '0C71FFE0' => { 'rtr' => '0471FFE0' , 'idx' =>  455 , 'extid' => 'EEB8CF723C0A60' , 'max' =>      800 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT9_STOP_TEMP' },
    '0C727FE0' => { 'rtr' => '04727FE0' , 'idx' =>  457 , 'extid' => 'EE79D5D3C40A5F' , 'max' =>      800 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT9_STOP_TEMP_2' },
    '0C72FFE0' => { 'rtr' => '0472FFE0' , 'idx' =>  459 , 'extid' => 'E1A0277040010D' , 'max' =>       60 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_MAX_TIME' },
    '0C733FE0' => { 'rtr' => '04733FE0' , 'idx' =>  460 , 'extid' => 'C2A3F5F02802C3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_5FRI' },
    '0C73BFE0' => { 'rtr' => '0473BFE0' , 'idx' =>  462 , 'extid' => 'C2CEA8E67602BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_1MON' },
    '0C743FE0' => { 'rtr' => '04743FE0' , 'idx' =>  464 , 'extid' => 'C2BBF1BCF802C4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_6SAT' },
    '0C74BFE0' => { 'rtr' => '0474BFE0' , 'idx' =>  466 , 'extid' => 'C2683D92D702C5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_7SUN' },
    '0C753FE0' => { 'rtr' => '04753FE0' , 'idx' =>  468 , 'extid' => 'C2187B21A202C2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_4THU' },
    '0C75BFE0' => { 'rtr' => '0475BFE0' , 'idx' =>  470 , 'extid' => 'C2FAA05DDA02C0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_2TUE' },
    '0C763FE0' => { 'rtr' => '04763FE0' , 'idx' =>  472 , 'extid' => 'C2C523C14402C1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_3WED' },
    '0C76BFE0' => { 'rtr' => '0476BFE0' , 'idx' =>  474 , 'extid' => 'C2E4558AF802CA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_5FRI' },
    '0C773FE0' => { 'rtr' => '04773FE0' , 'idx' =>  476 , 'extid' => 'C289089CA602C6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_1MON' },
    '0C77BFE0' => { 'rtr' => '0477BFE0' , 'idx' =>  478 , 'extid' => 'C2FC51C62802CC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_6SAT' },
    '0C783FE0' => { 'rtr' => '04783FE0' , 'idx' =>  480 , 'extid' => 'C22F9DE80702CB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_7SUN' },
    '0C78BFE0' => { 'rtr' => '0478BFE0' , 'idx' =>  482 , 'extid' => 'C25FDB5B7202C9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_4THU' },
    '0C793FE0' => { 'rtr' => '04793FE0' , 'idx' =>  484 , 'extid' => 'C2BD00270A02C7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_2TUE' },
    '0C79BFE0' => { 'rtr' => '0479BFE0' , 'idx' =>  486 , 'extid' => 'C28283BB9402C8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_3WED' },
    '0C7A3FE0' => { 'rtr' => '047A3FE0' , 'idx' =>  488 , 'extid' => 'E1CAB0771C0952' , 'max' =>        2 , 'min' =>        0 , 'format' => 'dp2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_MODE' },
    '0C7A7FE0' => { 'rtr' => '047A7FE0' , 'idx' =>  489 , 'extid' => 'E14502BDB103E4' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_PROTECTIVE_ANODE_INSTALLED' },
    '0C7ABFE0' => { 'rtr' => '047ABFE0' , 'idx' =>  490 , 'extid' => '0083F0FFFB00FC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'DHW_REQUEST' },
    '0C7AFFE0' => { 'rtr' => '047AFFE0' , 'idx' =>  491 , 'extid' => '006E6756EF0663' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'DHW_REQUEST_2' },
    '0C7B3FE0' => { 'rtr' => '047B3FE0' , 'idx' =>  492 , 'extid' => 'C0F8FDE3EC010C' , 'max' => 83886080 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_STATE_ECONOMY' },
    '0C7B7FE0' => { 'rtr' => '047B7FE0' , 'idx' =>  493 , 'extid' => '00DF862F0B02B5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_TIMECONTROLLED' },
    '0C7BBFE0' => { 'rtr' => '047BBFE0' , 'idx' =>  494 , 'extid' => 'E10B0EFC9F0780' , 'max' =>        2 , 'min' =>        0 , 'format' => 'dp1' , 'read' => 1 , 'text' => 'DHW_TIMEPROGRAM' },
    '0C7BFFE0' => { 'rtr' => '047BFFE0' , 'idx' =>  495 , 'extid' => 'C060DF8D6C0656' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_USER_ENABLED' },
    '0C7C3FE0' => { 'rtr' => '047C3FE0' , 'idx' =>  496 , 'extid' => 'C0EE6CB90D0657' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_USER_ENABLED_2' },
    '0C7C7FE0' => { 'rtr' => '047C7FE0' , 'idx' =>  497 , 'extid' => '066BDDE50F0CEC' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_USER_SET_START_TEMP' },
    '0C7CFFE0' => { 'rtr' => '047CFFE0' , 'idx' =>  499 , 'extid' => '06E3D563010CED' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_USER_SET_START_TEMP_2' },
    '0C7D7FE0' => { 'rtr' => '047D7FE0' , 'idx' =>  501 , 'extid' => 'E11FB861C80032' , 'max' =>      100 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'DISPLAY_BACKLIGHT_INTENSITY' },
    '0C7DBFE0' => { 'rtr' => '047DBFE0' , 'idx' =>  502 , 'extid' => '213284225B0BD5' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DISPLAY_CONTRAST' },
    '0C7DFFE0' => { 'rtr' => '047DFFE0' , 'idx' =>  503 , 'extid' => '801BC8CB5E0184' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DISPLAY_TESTED' },
    '0C7E3FE0' => { 'rtr' => '047E3FE0' , 'idx' =>  504 , 'extid' => '017422CA550038' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DRIFTTILLSTAND' },
    '0C7E7FE0' => { 'rtr' => '047E7FE0' , 'idx' =>  505 , 'extid' => '0E114D85F103DD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DRYOUT_SETPOINT_TEMP' },
    '0C7EFFE0' => { 'rtr' => '047EFFE0' , 'idx' =>  507 , 'extid' => 'C00E5D8D3A0439' , 'max' =>117440512 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DST_ENABLED' },
    '0C7F3FE0' => { 'rtr' => '047F3FE0' , 'idx' =>  508 , 'extid' => '8123C57A880039' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DST_OFFSET' },
    '0C7F7FE0' => { 'rtr' => '047F7FE0' , 'idx' =>  509 , 'extid' => '80C27DB0080A10' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E31_T2_CONNECTED' },
    '0C7FBFE0' => { 'rtr' => '047FBFE0' , 'idx' =>  510 , 'extid' => '6D853E880D0882' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E31_T32_KORRIGERING_GLOBAL' },
    '0C7FFFE0' => { 'rtr' => '047FFFE0' , 'idx' =>  511 , 'extid' => 'C0DAAC0DE90753' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T71_ACKNOWLEDGED' },
    '0C803FE0' => { 'rtr' => '04803FE0' , 'idx' =>  512 , 'extid' => '80D820198007EF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T71_CONNECTED' },
    '0C807FE0' => { 'rtr' => '04807FE0' , 'idx' =>  513 , 'extid' => 'ED87F7528D04B0' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E71_T71_KORRIGERING' },
    '0C80BFE0' => { 'rtr' => '0480BFE0' , 'idx' =>  514 , 'extid' => '00560E1A0804B1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T71_STATUS' },
    '0C80FFE0' => { 'rtr' => '0480FFE0' , 'idx' =>  515 , 'extid' => '0E2DD1622104B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E71_T71_TEMP' },
    '0C817FE0' => { 'rtr' => '04817FE0' , 'idx' =>  517 , 'extid' => 'ED3A3D3E4304B8' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T72_KORRIGERING' },
    '0C81BFE0' => { 'rtr' => '0481BFE0' , 'idx' =>  518 , 'extid' => '00D8811DEB04B9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T72_STATUS' },
    '0C81FFE0' => { 'rtr' => '0481FFE0' , 'idx' =>  519 , 'extid' => '0EAB45108F04BA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E71_T72_TEMP' },
    '0C827FE0' => { 'rtr' => '04827FE0' , 'idx' =>  521 , 'extid' => 'C0302AD08B07D4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T71_ACKNOWLEDGED' },
    '0C82BFE0' => { 'rtr' => '0482BFE0' , 'idx' =>  522 , 'extid' => '80C95D73F907F0' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T71_CONNECTED' },
    '0C82FFE0' => { 'rtr' => '0482FFE0' , 'idx' =>  523 , 'extid' => 'EDD46D090907D5' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E72_T71_KORRIGERING' },
    '0C833FE0' => { 'rtr' => '04833FE0' , 'idx' =>  524 , 'extid' => '002190C8F807D6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T71_STATUS' },
    '0C837FE0' => { 'rtr' => '04837FE0' , 'idx' =>  525 , 'extid' => '0EC6E6D92207D7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E72_T71_TEMP' },
    '0C83FFE0' => { 'rtr' => '0483FFE0' , 'idx' =>  527 , 'extid' => 'ED69A765C707D8' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E72_T72_KORRIGERING' },
    '0C843FE0' => { 'rtr' => '04843FE0' , 'idx' =>  528 , 'extid' => '00AF1FCF1B07D9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T72_STATUS' },
    '0C847FE0' => { 'rtr' => '04847FE0' , 'idx' =>  529 , 'extid' => '0E4072AB8C07DA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E72_T72_TEMP' },
    '0C84FFE0' => { 'rtr' => '0484FFE0' , 'idx' =>  531 , 'extid' => '84245EE1CB0A5C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E81_T81_CONNECTED' },
    '0C853FE0' => { 'rtr' => '04853FE0' , 'idx' =>  532 , 'extid' => '8216949C7F0C49' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EEPROM_HEATING_SEASON_START_DELAY_TIME' },
    '0C85BFE0' => { 'rtr' => '0485BFE0' , 'idx' =>  534 , 'extid' => '8253CCD6040C44' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EEPROM_NEUTRALZON_M_VALVE_LIMIT_TIME' },
    '0C863FE0' => { 'rtr' => '04863FE0' , 'idx' =>  536 , 'extid' => 'A1495778540CAA' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELECTRICAL_CONNECTION_400V' },
    '0C867FE0' => { 'rtr' => '04867FE0' , 'idx' =>  537 , 'extid' => '81A2A7F6370CB5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELECTRICAL_MODE' },
    '0C86BFE0' => { 'rtr' => '0486BFE0' , 'idx' =>  538 , 'extid' => '80D5D68B790CB6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELECTRICAL_MODE_SELECTED' },
    '0C86FFE0' => { 'rtr' => '0486FFE0' , 'idx' =>  539 , 'extid' => '00A5F331C0004A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELSKAP_MAX' },
    '0C873FE0' => { 'rtr' => '04873FE0' , 'idx' =>  540 , 'extid' => 'EEA593EA5F004B' , 'max' =>      900 , 'min' =>      300 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ELSKAP_MAX_TEMP' },
    '0C87BFE0' => { 'rtr' => '0487BFE0' , 'idx' =>  542 , 'extid' => '0E3F05D925004C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ELSKAP_TEMP' },
    '0C883FE0' => { 'rtr' => '04883FE0' , 'idx' =>  544 , 'extid' => '00950E43610273' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'EL_DHW_REQUEST' },
    '0C887FE0' => { 'rtr' => '04887FE0' , 'idx' =>  545 , 'extid' => '40425EFE1F0A4A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E21_EXT_1' },
    '0C88BFE0' => { 'rtr' => '0488BFE0' , 'idx' =>  546 , 'extid' => '40DB57AFA50A4B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E21_EXT_2' },
    '0C88FFE0' => { 'rtr' => '0488FFE0' , 'idx' =>  547 , 'extid' => '4073B6E4820B50' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E22_EXT_1' },
    '0C893FE0' => { 'rtr' => '04893FE0' , 'idx' =>  548 , 'extid' => '40EABFB5380B4F' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E22_EXT_2' },
    '0C897FE0' => { 'rtr' => '04897FE0' , 'idx' =>  549 , 'extid' => 'E10DD5DA4F02D9' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_ACKNOWLEDGE_TIME' },
    '0C89BFE0' => { 'rtr' => '0489BFE0' , 'idx' =>  550 , 'extid' => 'E1D2F3149A02D8' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_AFTER_DHW' },
    '0C89FFE0' => { 'rtr' => '0489FFE0' , 'idx' =>  551 , 'extid' => '0E3557D0C70C6F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP' },
    '0C8A7FE0' => { 'rtr' => '048A7FE0' , 'idx' =>  553 , 'extid' => '8E30CDBEE80C70' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_20' },
    '0C8AFFE0' => { 'rtr' => '048AFFE0' , 'idx' =>  555 , 'extid' => '8ED3939ECE0C9A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_10' },
    '0C8B7FE0' => { 'rtr' => '048B7FE0' , 'idx' =>  557 , 'extid' => '8EA3F96A410C99' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_15' },
    '0C8BFFE0' => { 'rtr' => '048BFFE0' , 'idx' =>  559 , 'extid' => '8EF8BECD0D0C6D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_20' },
    '0C8C7FE0' => { 'rtr' => '048C7FE0' , 'idx' =>  561 , 'extid' => '8E4D6D81680C6C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_5' },
    '0C8CFFE0' => { 'rtr' => '048CFFE0' , 'idx' =>  563 , 'extid' => '00301E92E30C71' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_STOP' },
    '0C8D3FE0' => { 'rtr' => '048D3FE0' , 'idx' =>  564 , 'extid' => '80ED3D05F40C6E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_STOP_FUNCTION_ACTIVE' },
    '0C8D7FE0' => { 'rtr' => '048D7FE0' , 'idx' =>  565 , 'extid' => 'A195D2E6790C95' , 'max' =>       70 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_MAX_OUTDOOR_TEMP' },
    '0C8DBFE0' => { 'rtr' => '048DBFE0' , 'idx' =>  566 , 'extid' => 'E5D1CEC0E902D4' , 'max' =>       10 , 'min' =>      -20 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_MAX_TEMPERATURE' },
    '0C8DFFE0' => { 'rtr' => '048DFFE0' , 'idx' =>  567 , 'extid' => 'E5CB75C22002DA' , 'max' =>        0 , 'min' =>      -40 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_MIN_OUTDOOR_TEMPERATURE' },
    '0C8E3FE0' => { 'rtr' => '048E3FE0' , 'idx' =>  568 , 'extid' => '013E83F56902D6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP' },
    '0C8E7FE0' => { 'rtr' => '048E7FE0' , 'idx' =>  569 , 'extid' => '01CDC5EA1A0693' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_2' },
    '0C8EBFE0' => { 'rtr' => '048EBFE0' , 'idx' =>  570 , 'extid' => '00FCA08D740C97' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_STOP_HIGH_OUTDOOR_TEMP' },
    '0C8EFFE0' => { 'rtr' => '048EFFE0' , 'idx' =>  571 , 'extid' => 'C0648EA3B3064E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_HOT_GAS_FUNCTION_ACTIVE' },
    '0C8F3FE0' => { 'rtr' => '048F3FE0' , 'idx' =>  572 , 'extid' => '002854632603A7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_OUTDOOR' },
    '0C8F7FE0' => { 'rtr' => '048F7FE0' , 'idx' =>  573 , 'extid' => 'C0694D6ACE064F' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_OUTDOOR_FUNCTION_ACTIVE' },
    '0C8FBFE0' => { 'rtr' => '048FBFE0' , 'idx' =>  574 , 'extid' => 'E1CB5E3E8F02D7' , 'max' =>      150 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_TEMPERATURE' },
    '0C8FFFE0' => { 'rtr' => '048FFFE0' , 'idx' =>  575 , 'extid' => '01AC34897F02D5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_VV' },
    '0C903FE0' => { 'rtr' => '04903FE0' , 'idx' =>  576 , 'extid' => '0188EEF06D067A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_VV_2' },
    '0C907FE0' => { 'rtr' => '04907FE0' , 'idx' =>  577 , 'extid' => 'C05D9CC10C0302' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E21_EXT_1' },
    '0C90BFE0' => { 'rtr' => '0490BFE0' , 'idx' =>  578 , 'extid' => 'C0C49590B60B45' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E21_EXT_2' },
    '0C90FFE0' => { 'rtr' => '0490FFE0' , 'idx' =>  579 , 'extid' => 'C06C74DB910B46' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E22_EXT_1' },
    '0C913FE0' => { 'rtr' => '04913FE0' , 'idx' =>  580 , 'extid' => 'C0F57D8A2B0488' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E22_EXT_2' },
    '0C917FE0' => { 'rtr' => '04917FE0' , 'idx' =>  581 , 'extid' => '00271682D90308' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVE' },
    '0C91BFE0' => { 'rtr' => '0491BFE0' , 'idx' =>  582 , 'extid' => 'C0058268240489' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E21_EXT_1' },
    '0C91FFE0' => { 'rtr' => '0491FFE0' , 'idx' =>  583 , 'extid' => 'C09C8B399E048A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E21_EXT_2' },
    '0C923FE0' => { 'rtr' => '04923FE0' , 'idx' =>  584 , 'extid' => 'C0346A72B90B47' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E22_EXT_1' },
    '0C927FE0' => { 'rtr' => '04927FE0' , 'idx' =>  585 , 'extid' => 'C0AD6323030B48' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E22_EXT_2' },
    '0C92BFE0' => { 'rtr' => '0492BFE0' , 'idx' =>  586 , 'extid' => '00A999853A0487' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVE' },
    '0C92FFE0' => { 'rtr' => '0492FFE0' , 'idx' =>  587 , 'extid' => 'C084A70D030B02' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E21_EXT_1' },
    '0C933FE0' => { 'rtr' => '04933FE0' , 'idx' =>  588 , 'extid' => 'C01DAE5CB90B03' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E21_EXT_2' },
    '0C937FE0' => { 'rtr' => '04937FE0' , 'idx' =>  589 , 'extid' => 'C0B54F179E0B49' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E22_EXT_1' },
    '0C93BFE0' => { 'rtr' => '0493BFE0' , 'idx' =>  590 , 'extid' => 'C02C4646240B4A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E22_EXT_2' },
    '0C93FFE0' => { 'rtr' => '0493FFE0' , 'idx' =>  591 , 'extid' => '00653385A40B04' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVE' },
    '0C943FE0' => { 'rtr' => '04943FE0' , 'idx' =>  592 , 'extid' => 'C146FF6AC202AA' , 'max' =>        7 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_DAY' },
    '0C947FE0' => { 'rtr' => '04947FE0' , 'idx' =>  593 , 'extid' => '02AC9077580B80' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_IOB6126_BITMASK' },
    '0C94FFE0' => { 'rtr' => '0494FFE0' , 'idx' =>  595 , 'extid' => '006C26255200BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_REQUEST' },
    '0C953FE0' => { 'rtr' => '04953FE0' , 'idx' =>  596 , 'extid' => '016A215A3200BE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_STATE' },
    '0C957FE0' => { 'rtr' => '04957FE0' , 'idx' =>  597 , 'extid' => 'E1D13CD71600C0' , 'max' =>       23 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_TIME' },
    '0C95BFE0' => { 'rtr' => '0495BFE0' , 'idx' =>  598 , 'extid' => '80959153780B98' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXTERN_HEAT_SOURCE_E71_EXT_INPUT_INV' },
    '0C95FFE0' => { 'rtr' => '0495FFE0' , 'idx' =>  599 , 'extid' => '8084EC39010B9A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXTERN_HEAT_SOURCE_E72_EXT_INPUT_INV' },
    '0C963FE0' => { 'rtr' => '04963FE0' , 'idx' =>  600 , 'extid' => '00464AC29A0D59' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_BOOL_ONE' },
    '0C967FE0' => { 'rtr' => '04967FE0' , 'idx' =>  601 , 'extid' => '004AEC4FCE0D58' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_BOOL_ZERO' },
    '0C96BFE0' => { 'rtr' => '0496BFE0' , 'idx' =>  602 , 'extid' => '01AA9DB4190D5B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_CHAR_ONE' },
    '0C96FFE0' => { 'rtr' => '0496FFE0' , 'idx' =>  603 , 'extid' => '013EB14A220D5A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_CHAR_ZERO' },
    '0C973FE0' => { 'rtr' => '04973FE0' , 'idx' =>  604 , 'extid' => 'EAD40AB6D00913' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FK_PID_D' },
    '0C97BFE0' => { 'rtr' => '0497BFE0' , 'idx' =>  606 , 'extid' => 'EAAABBCA6D0914' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'FK_PID_I' },
    '0C983FE0' => { 'rtr' => '04983FE0' , 'idx' =>  608 , 'extid' => 'EACED062AD0915' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'FK_PID_P' },
    '0C98BFE0' => { 'rtr' => '0498BFE0' , 'idx' =>  610 , 'extid' => 'E1ACF52887004F' , 'max' =>       80 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGARD_COMPRESSOR_FREQUENCY' },
    '0C98FFE0' => { 'rtr' => '0498FFE0' , 'idx' =>  611 , 'extid' => '005BB7B5B3004D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGUARD' },
    '0C993FE0' => { 'rtr' => '04993FE0' , 'idx' =>  612 , 'extid' => 'E17CA36100004E' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGUARD_DELAY_TIME' },
    '0C997FE0' => { 'rtr' => '04997FE0' , 'idx' =>  613 , 'extid' => 'EE2A751B620050' , 'max' =>      300 , 'min' =>       20 , 'format' => 'tem' , 'read' => 0 , 'text' => 'FREEZEGUARD_START_TEMPERATURE' },
    '0C99FFE0' => { 'rtr' => '0499FFE0' , 'idx' =>  615 , 'extid' => 'EEDEC69BAF0051' , 'max' =>      500 , 'min' =>       70 , 'format' => 'tem' , 'read' => 0 , 'text' => 'FREEZEGUARD_STOP_TEMPERATURE' },
    '0C9A7FE0' => { 'rtr' => '049A7FE0' , 'idx' =>  617 , 'extid' => '0EE4FE05AE0056' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GRADMIN' },
    '0C9AFFE0' => { 'rtr' => '049AFFE0' , 'idx' =>  619 , 'extid' => 'E2C09D3F760057' , 'max' =>      120 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GRADMIN_MAX' },
    '0C9B7FE0' => { 'rtr' => '049B7FE0' , 'idx' =>  621 , 'extid' => 'EDD48ABC8A0412' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_2_KORRIGERING' },
    '0C9BBFE0' => { 'rtr' => '049BBFE0' , 'idx' =>  622 , 'extid' => 'EE3BE8C5140847' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_2_LR_TEMP' },
    '0C9C3FE0' => { 'rtr' => '049C3FE0' , 'idx' =>  624 , 'extid' => '00F444E6260413' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_2_STATUS' },
    '0C9C7FE0' => { 'rtr' => '049C7FE0' , 'idx' =>  625 , 'extid' => '0EA262CCDE0414' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_2_TEMP' },
    '0C9CFFE0' => { 'rtr' => '049CFFE0' , 'idx' =>  627 , 'extid' => 'E15551778D046C' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_GT11_MAX_DELTA_DELAY_AFTER_SWITCH_TIME' },
    '0C9D3FE0' => { 'rtr' => '049D3FE0' , 'idx' =>  628 , 'extid' => 'E1BEDA2A7806C6' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_GT11_MAX_DELTA_DELAY_TIME' },
    '0C9D7FE0' => { 'rtr' => '049D7FE0' , 'idx' =>  629 , 'extid' => 'E5DFF9C1DC06C5' , 'max' =>       30 , 'min' =>        1 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_GT11_MAX_DELTA_TEMP' },
    '0C9DBFE0' => { 'rtr' => '049DBFE0' , 'idx' =>  630 , 'extid' => 'ED5E390C4F005B' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_KORRIGERING' },
    '0C9DFFE0' => { 'rtr' => '049DFFE0' , 'idx' =>  631 , 'extid' => 'EE5634821C022B' , 'max' =>      300 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_LAG_KOND_TEMP' },
    '0C9E7FE0' => { 'rtr' => '049E7FE0' , 'idx' =>  633 , 'extid' => 'E1B939C0DD016E' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_LR_ANTAL_VARNINGAR' },
    '0C9EBFE0' => { 'rtr' => '049EBFE0' , 'idx' =>  634 , 'extid' => 'E93FEC9550016D' , 'max' =>      100 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_LR_HYSTERES' },
    '0C9EFFE0' => { 'rtr' => '049EFFE0' , 'idx' =>  635 , 'extid' => 'EEB663A78100EC' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_LR_TEMP' },
    '0C9F7FE0' => { 'rtr' => '049F7FE0' , 'idx' =>  637 , 'extid' => '00772B8639005C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_STATUS' },
    '0C9FBFE0' => { 'rtr' => '049FBFE0' , 'idx' =>  638 , 'extid' => '0E2139C16F005D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_TEMP' },
    '0CA03FE0' => { 'rtr' => '04A03FE0' , 'idx' =>  640 , 'extid' => 'ED6D7167620415' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_2_KORRIGERING' },
    '0CA07FE0' => { 'rtr' => '04A07FE0' , 'idx' =>  641 , 'extid' => 'EE62215A590848' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_2_LF_TEMP' },
    '0CA0FFE0' => { 'rtr' => '04A0FFE0' , 'idx' =>  643 , 'extid' => '001B868D180416' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT11_2_STATUS' },
    '0CA13FE0' => { 'rtr' => '04A13FE0' , 'idx' =>  644 , 'extid' => '0E6EC8CC400417' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_2_TEMP' },
    '0CA1BFE0' => { 'rtr' => '04A1BFE0' , 'idx' =>  646 , 'extid' => 'ED83AFD5CA005E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_KORRIGERING' },
    '0CA1FFE0' => { 'rtr' => '04A1FFE0' , 'idx' =>  647 , 'extid' => 'E1B8074529016F' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT11_LF_ANTAL_VARNINGAR' },
    '0CA23FE0' => { 'rtr' => '04A23FE0' , 'idx' =>  648 , 'extid' => 'E9CC3F6D47016C' , 'max' =>      100 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT11_LF_HYSTERES' },
    '0CA27FE0' => { 'rtr' => '04A27FE0' , 'idx' =>  649 , 'extid' => 'EE395FF34F00ED' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT11_LF_TEMP' },
    '0CA2FFE0' => { 'rtr' => '04A2FFE0' , 'idx' =>  651 , 'extid' => '00BB8186A7005F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT11_STATUS' },
    '0CA33FE0' => { 'rtr' => '04A33FE0' , 'idx' =>  652 , 'extid' => '0EEA6512CA0060' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT11_TEMP' },
    '0CA3BFE0' => { 'rtr' => '04A3BFE0' , 'idx' =>  654 , 'extid' => 'ED7C0C0D1B0418' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT12_2_KORRIGERING' },
    '0CA3FFE0' => { 'rtr' => '04A3FFE0' , 'idx' =>  655 , 'extid' => '00F0B1361B0419' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT12_2_STATUS' },
    '0CA43FE0' => { 'rtr' => '04A43FE0' , 'idx' =>  656 , 'extid' => '0EE047CBA3041A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT12_2_TEMP' },
    '0CA4BFE0' => { 'rtr' => '04A4BFE0' , 'idx' =>  658 , 'extid' => 'ED3E65B904028B' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT12_KORRIGERING' },
    '0CA4FFE0' => { 'rtr' => '04A4FFE0' , 'idx' =>  659 , 'extid' => '00350E8144028C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT12_STATUS' },
    '0CA53FE0' => { 'rtr' => '04A53FE0' , 'idx' =>  660 , 'extid' => '0E6CF16064024B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT12_TEMP' },
    '0CA5BFE0' => { 'rtr' => '04A5BFE0' , 'idx' =>  662 , 'extid' => 'ED362187850058' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT1_KORRIGERING' },
    '0CA5FFE0' => { 'rtr' => '04A5FFE0' , 'idx' =>  663 , 'extid' => '201692AD510059' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT1_STATUS' },
    '0CA63FE0' => { 'rtr' => '04A63FE0' , 'idx' =>  664 , 'extid' => '0EF807E249005A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT1_TEMP' },
    '0CA6BFE0' => { 'rtr' => '04A6BFE0' , 'idx' =>  666 , 'extid' => '0E222CD0390CBE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT2_ATTENUATED_TEMP' },
    '0CA73FE0' => { 'rtr' => '04A73FE0' , 'idx' =>  668 , 'extid' => 'AA88FB658F0CBF' , 'max' =>      480 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT2_ATTENUATION' },
    '0CA7BFE0' => { 'rtr' => '04A7BFE0' , 'idx' =>  670 , 'extid' => 'ED8BEBEB4B0061' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT2_KORRIGERING' },
    '0CA7FFE0' => { 'rtr' => '04A7FFE0' , 'idx' =>  671 , 'extid' => '00981DAAB20062' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT2_STATUS' },
    '0CA83FE0' => { 'rtr' => '04A83FE0' , 'idx' =>  672 , 'extid' => '0E7E9390E70063' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT2_TEMP' },
    '0CA8BFE0' => { 'rtr' => '04A8BFE0' , 'idx' =>  674 , 'extid' => '0E288433280D13' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT2_TEMP_ROUND_OFFED' },
    '0CA93FE0' => { 'rtr' => '04A93FE0' , 'idx' =>  676 , 'extid' => '80B4702C470064' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_ANSLUTEN' },
    '0CA97FE0' => { 'rtr' => '04A97FE0' , 'idx' =>  677 , 'extid' => 'ED567D32CE0065' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT3_KORRIGERING' },
    '0CA9BFE0' => { 'rtr' => '04A9BFE0' , 'idx' =>  678 , 'extid' => 'C016D09D1D0066' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_KVITTERAD' },
    '0CA9FFE0' => { 'rtr' => '04A9FFE0' , 'idx' =>  679 , 'extid' => '00AF4D85D70239' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_KVITTERA_MANUELLT' },
    '0CAA3FE0' => { 'rtr' => '04AA3FE0' , 'idx' =>  680 , 'extid' => '0054B7AA2C0067' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_STATUS' },
    '0CAA7FE0' => { 'rtr' => '04AA7FE0' , 'idx' =>  681 , 'extid' => '0EB5CF43420068' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT3_TEMP' },
    '0CAAFFE0' => { 'rtr' => '04AAFFE0' , 'idx' =>  683 , 'extid' => '6D4BE87068049E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT41_KORRIGERING_GLOBAL' },
    '0CAB3FE0' => { 'rtr' => '04AB3FE0' , 'idx' =>  684 , 'extid' => '0EAB0EFFDF049D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT41_TEMP_GLOBAL' },
    '0CABBFE0' => { 'rtr' => '04ABBFE0' , 'idx' =>  686 , 'extid' => 'C01592B05F0752' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_ACKNOWLEDGED_GLOBAL' },
    '0CABFFE0' => { 'rtr' => '04ABFFE0' , 'idx' =>  687 , 'extid' => '0E67FFA7580D12' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_ATTENUATED_TEMP_GLOBAL' },
    '0CAC7FE0' => { 'rtr' => '04AC7FE0' , 'idx' =>  689 , 'extid' => 'AA6BB86D6D0D11' , 'max' =>      480 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_ATTENUATION_GLOBAL' },
    '0CACFFE0' => { 'rtr' => '04ACFFE0' , 'idx' =>  691 , 'extid' => '6D05059B31049F' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_KORRIGERING_GLOBAL' },
    '0CAD3FE0' => { 'rtr' => '04AD3FE0' , 'idx' =>  692 , 'extid' => '0E6BB7954904A0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_TEMP_GLOBAL' },
    '0CADBFE0' => { 'rtr' => '04ADBFE0' , 'idx' =>  694 , 'extid' => '81B96E5C000069' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'GT5_ANSLUTEN' },
    '0CADFFE0' => { 'rtr' => '04ADFFE0' , 'idx' =>  695 , 'extid' => '0E02BEAC720CC2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT5_ATTENUATED_TEMP' },
    '0CAE7FE0' => { 'rtr' => '04AE7FE0' , 'idx' =>  697 , 'extid' => 'AAF58863D70CC1' , 'max' =>      480 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_ATTENUATION' },
    '0CAEFFE0' => { 'rtr' => '04AEFFE0' , 'idx' =>  699 , 'extid' => 'EDF698ED13006A' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT5_KORRIGERING' },
    '0CAF3FE0' => { 'rtr' => '04AF3FE0' , 'idx' =>  700 , 'extid' => 'C0FE65575E006B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_KVITTERAD' },
    '0CAF7FE0' => { 'rtr' => '04AF7FE0' , 'idx' =>  701 , 'extid' => '0092D8A3AB006C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_STATUS' },
    '0CAFBFE0' => { 'rtr' => '04AFBFE0' , 'idx' =>  702 , 'extid' => '0E6396A05F006D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT5_TEMP' },
    '0CB03FE0' => { 'rtr' => '04B03FE0' , 'idx' =>  704 , 'extid' => '0EC9AA394C0D1B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_TEMP_ROUND_OFFED' },
    '0CB0BFE0' => { 'rtr' => '04B0BFE0' , 'idx' =>  706 , 'extid' => 'E1378E0B14085D' , 'max' =>      150 , 'min' =>       50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_2_HG_TEMP' },
    '0CB0FFE0' => { 'rtr' => '04B0FFE0' , 'idx' =>  707 , 'extid' => 'ED04F4BEE4041C' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_2_KORRIGERING' },
    '0CB13FE0' => { 'rtr' => '04B13FE0' , 'idx' =>  708 , 'extid' => '0017008409041B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT6_2_STATUS' },
    '0CB17FE0' => { 'rtr' => '04B17FE0' , 'idx' =>  709 , 'extid' => '0EC91EEEAF041D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_2_TEMP' },
    '0CB1FFE0' => { 'rtr' => '04B1FFE0' , 'idx' =>  711 , 'extid' => 'E1365E2D32022D' , 'max' =>      150 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT6_HG_TEMP' },
    '0CB23FE0' => { 'rtr' => '04B23FE0' , 'idx' =>  712 , 'extid' => 'ED4B5281DD006E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_KORRIGERING' },
    '0CB27FE0' => { 'rtr' => '04B27FE0' , 'idx' =>  713 , 'extid' => '001C57A448006F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT6_STATUS' },
    '0CB2BFE0' => { 'rtr' => '04B2BFE0' , 'idx' =>  714 , 'extid' => '0EE502D2F10070' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT6_TEMP' },
    '0CB33FE0' => { 'rtr' => '04B33FE0' , 'idx' =>  716 , 'extid' => 'EDBD0F650C0C74' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT7_2_KORRIGERING' },
    '0CB37FE0' => { 'rtr' => '04B37FE0' , 'idx' =>  717 , 'extid' => '00F8C2EF370C75' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT7_2_STATUS' },
    '0CB3BFE0' => { 'rtr' => '04B3BFE0' , 'idx' =>  718 , 'extid' => '0E05B4EE310C76' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT7_2_TEMP' },
    '0CB43FE0' => { 'rtr' => '04B43FE0' , 'idx' =>  720 , 'extid' => 'ED96C458580C68' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT7_KORRIGERING' },
    '0CB47FE0' => { 'rtr' => '04B47FE0' , 'idx' =>  721 , 'extid' => '00D0FDA4D60C67' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT7_STATUS' },
    '0CB4BFE0' => { 'rtr' => '04B4BFE0' , 'idx' =>  722 , 'extid' => '0E2E5E01540C66' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT7_TEMP' },
    '0CB53FE0' => { 'rtr' => '04B53FE0' , 'idx' =>  724 , 'extid' => 'ED2DF92A8A04A7' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT81_KORRIGERING' },
    '0CB57FE0' => { 'rtr' => '04B57FE0' , 'idx' =>  725 , 'extid' => 'C49092AD3504AF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT81_KVITTERAD' },
    '0CB5BFE0' => { 'rtr' => '04B5BFE0' , 'idx' =>  726 , 'extid' => '00172230FC04AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT81_STATUS' },
    '0CB5FFE0' => { 'rtr' => '04B5FFE0' , 'idx' =>  727 , 'extid' => '0E7FFD571904A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT81_TEMP' },
    '0CB67FE0' => { 'rtr' => '04B67FE0' , 'idx' =>  729 , 'extid' => 'ED9033464404A8' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT82_KORRIGERING' },
    '0CB6BFE0' => { 'rtr' => '04B6BFE0' , 'idx' =>  730 , 'extid' => '0099AD371F04A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT82_STATUS' },
    '0CB6FFE0' => { 'rtr' => '04B6FFE0' , 'idx' =>  731 , 'extid' => '0EF96925B704A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT82_TEMP' },
    '0CB77FE0' => { 'rtr' => '04B77FE0' , 'idx' =>  733 , 'extid' => 'EEAEA4F3B7085B' , 'max' =>      800 , 'min' =>      500 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_2_HF_TEMP' },
    '0CB7FFE0' => { 'rtr' => '04B7FFE0' , 'idx' =>  735 , 'extid' => 'EDB712C9F1085C' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_2_HIGH_GT9_RESTART_HYSTERESIS' },
    '0CB83FE0' => { 'rtr' => '04B83FE0' , 'idx' =>  736 , 'extid' => 'EDE987A691041E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_2_KORRIGERING' },
    '0CB87FE0' => { 'rtr' => '04B87FE0' , 'idx' =>  737 , 'extid' => '0009C9B4BA041F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_2_STATUS' },
    '0CB8BFE0' => { 'rtr' => '04B8BFE0' , 'idx' =>  738 , 'extid' => '0EDC94FC9D0420' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_2_TEMP' },
    '0CB93FE0' => { 'rtr' => '04B93FE0' , 'idx' =>  740 , 'extid' => 'E197B1FD5406C7' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_GT9_MAX_DELTA_DELAY_AFTER_SWITCH_TIME' },
    '0CB97FE0' => { 'rtr' => '04B97FE0' , 'idx' =>  741 , 'extid' => 'E1EB94F64500F9' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_GT9_MAX_DELTA_DELAY_TIME' },
    '0CB9BFE0' => { 'rtr' => '04B9BFE0' , 'idx' =>  742 , 'extid' => 'E5CBE851D000F8' , 'max' =>       30 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_GT9_MAX_DELTA_TEMP' },
    '0CB9FFE0' => { 'rtr' => '04B9FFE0' , 'idx' =>  743 , 'extid' => '005FA258650185' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_HF_ELK' },
    '0CBA3FE0' => { 'rtr' => '04BA3FE0' , 'idx' =>  744 , 'extid' => 'EDD8570F800186' , 'max' =>       95 , 'min' =>       45 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT8_HF_ELK_TEMP' },
    '0CBA7FE0' => { 'rtr' => '04BA7FE0' , 'idx' =>  745 , 'extid' => 'EE35C0250500EE' , 'max' =>      800 , 'min' =>      500 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT8_HF_TEMP' },
    '0CBAFFE0' => { 'rtr' => '04BAFFE0' , 'idx' =>  747 , 'extid' => 'ED41A459C705B5' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_HIGH_GT9_RESTART_HYSTERESIS' },
    '0CBB3FE0' => { 'rtr' => '04BB3FE0' , 'idx' =>  748 , 'extid' => 'E143F89A3A084F' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_HIGH_MAX_WARNING_COUNT' },
    '0CBB7FE0' => { 'rtr' => '04BB7FE0' , 'idx' =>  749 , 'extid' => 'EDB1B48D6D0071' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_KORRIGERING' },
    '0CBBBFE0' => { 'rtr' => '04BBBFE0' , 'idx' =>  750 , 'extid' => '0009DDB67A0072' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_STATUS' },
    '0CBBFFE0' => { 'rtr' => '04BBFFE0' , 'idx' =>  751 , 'extid' => '0EDF08B3810073' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT8_TEMP' },
    '0CBC7FE0' => { 'rtr' => '04BC7FE0' , 'idx' =>  753 , 'extid' => 'ED507C7D790421' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT9_2_KORRIGERING' },
    '0CBCBFE0' => { 'rtr' => '04BCBFE0' , 'idx' =>  754 , 'extid' => '00E60BDF840422' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT9_2_STATUS' },
    '0CBCFFE0' => { 'rtr' => '04BCFFE0' , 'idx' =>  755 , 'extid' => '0E103EFC030423' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT9_2_TEMP' },
    '0CBD7FE0' => { 'rtr' => '04BD7FE0' , 'idx' =>  757 , 'extid' => 'ED6C2254E80074' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT9_KORRIGERING' },
    '0CBDBFE0' => { 'rtr' => '04BDBFE0' , 'idx' =>  758 , 'extid' => '00C577B6E40075' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT9_STATUS' },
    '0CBDFFE0' => { 'rtr' => '04BDFFE0' , 'idx' =>  759 , 'extid' => '0E145460240076' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT9_TEMP' },
    '0CBE7FE0' => { 'rtr' => '04BE7FE0' , 'idx' =>  761 , 'extid' => '0A71ACC137026B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF' },
    '0CBEFFE0' => { 'rtr' => '04BEFFE0' , 'idx' =>  763 , 'extid' => '0AC849215A05F1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_2' },
    '0CBF7FE0' => { 'rtr' => '04BF7FE0' , 'idx' =>  765 , 'extid' => 'EE882E18670249' , 'max' =>      300 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_CONST' },
    '0CBFFFE0' => { 'rtr' => '04BFFFE0' , 'idx' =>  767 , 'extid' => 'EE8DFDEFFC05F2' , 'max' =>      300 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_CONST_2' },
    '0CC07FE0' => { 'rtr' => '04C07FE0' , 'idx' =>  769 , 'extid' => 'EA9E9BF7D90247' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MAX' },
    '0CC0FFE0' => { 'rtr' => '04C0FFE0' , 'idx' =>  771 , 'extid' => 'EAC70E859605F3' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MAX_2' },
    '0CC17FE0' => { 'rtr' => '04C17FE0' , 'idx' =>  773 , 'extid' => 'EAA296C8800248' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MIN' },
    '0CC1FFE0' => { 'rtr' => '04C1FFE0' , 'idx' =>  775 , 'extid' => 'EA1A1172BB05F4' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MIN_2' },
    '0CC27FE0' => { 'rtr' => '04C27FE0' , 'idx' =>  777 , 'extid' => '0E4A9862F40287' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_ADDITIONAL_SETPOINT' },
    '0CC2FFE0' => { 'rtr' => '04C2FFE0' , 'idx' =>  779 , 'extid' => 'E990138EC60227' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_ADDITIONAL_SETPOINT_OFFSET' },
    '0CC33FE0' => { 'rtr' => '04C33FE0' , 'idx' =>  780 , 'extid' => 'E14DC699890281' , 'max' =>       20 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TEMP' },
    '0CC37FE0' => { 'rtr' => '04C37FE0' , 'idx' =>  781 , 'extid' => 'E12901840601F9' , 'max' =>       60 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TIME' },
    '0CC3BFE0' => { 'rtr' => '04C3BFE0' , 'idx' =>  782 , 'extid' => '2AFEFEB21203E1' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CIRCUIT_PID_ISPOINT_GLOBAL' },
    '0CC43FE0' => { 'rtr' => '04C43FE0' , 'idx' =>  784 , 'extid' => '2A0F3EA5A403E0' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CIRCUIT_PID_SETPOINT_GLOBAL' },
    '0CC4BFE0' => { 'rtr' => '04C4BFE0' , 'idx' =>  786 , 'extid' => '00ECE8B73C0B5F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_CHECK_SETTING' },
    '0CC4FFE0' => { 'rtr' => '04C4FFE0' , 'idx' =>  787 , 'extid' => '6E7F1B6889034B' , 'max' =>     1080 , 'min' =>       10 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_LEFT_Y_GLOBAL' },
    '0CC57FE0' => { 'rtr' => '04C57FE0' , 'idx' =>  789 , 'extid' => 'EE47EC0AC300D4' , 'max' =>     1080 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_LEFT_Y_LOCAL' },
    '0CC5FFE0' => { 'rtr' => '04C5FFE0' , 'idx' =>  791 , 'extid' => '6EB4805109034C' , 'max' =>     1000 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_MAX_GLOBAL' },
    '0CC67FE0' => { 'rtr' => '04C67FE0' , 'idx' =>  793 , 'extid' => 'EEBD660673026D' , 'max' =>     1000 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_MAX_LOCAL' },
    '0CC6FFE0' => { 'rtr' => '04C6FFE0' , 'idx' =>  795 , 'extid' => '6EB58CCBBD034D' , 'max' =>      800 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_MIN_GLOBAL' },
    '0CC77FE0' => { 'rtr' => '04C77FE0' , 'idx' =>  797 , 'extid' => 'EE6A8DB432026C' , 'max' =>      800 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_MIN_LOCAL' },
    '0CC7FFE0' => { 'rtr' => '04C7FFE0' , 'idx' =>  799 , 'extid' => 'E1EBE5792000D2' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_MYCKET_PROCENT' },
    '0CC83FE0' => { 'rtr' => '04C83FE0' , 'idx' =>  800 , 'extid' => 'E1E29D0E3F00D3' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_NORMAL_PROCENT' },
    '0CC87FE0' => { 'rtr' => '04C87FE0' , 'idx' =>  801 , 'extid' => '219D8A4A0703CF' , 'max' =>       12 , 'min' =>        9 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_NO_OF_POINTS' },
    '0CC8BFE0' => { 'rtr' => '04C8BFE0' , 'idx' =>  802 , 'extid' => 'EE4ACBA689063E' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_PARALLEL_OFFSET' },
    '0CC93FE0' => { 'rtr' => '04C93FE0' , 'idx' =>  804 , 'extid' => '6E596997C7064D' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_PARALLEL_OFFSET_GLOBAL' },
    '0CC9BFE0' => { 'rtr' => '04C9BFE0' , 'idx' =>  806 , 'extid' => 'EEA73672D1069A' , 'max' =>     -100 , 'min' =>     -350 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_RIGHT_X_LOCAL' },
    '0CCA3FE0' => { 'rtr' => '04CA3FE0' , 'idx' =>  808 , 'extid' => '4E40E8C327034E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_RIGHT_Y_GLOBAL' },
    '0CCABFE0' => { 'rtr' => '04CABFE0' , 'idx' =>  810 , 'extid' => 'CE0141796500D1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_RIGHT_Y_LOCAL' },
    '0CCB3FE0' => { 'rtr' => '04CB3FE0' , 'idx' =>  812 , 'extid' => '0EA674B3CA00CB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_VALUE' },
    '0CCBBFE0' => { 'rtr' => '04CBBFE0' , 'idx' =>  814 , 'extid' => 'E5F9FA82E300D5' , 'max' =>       15 , 'min' =>      -10 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_VH_LIMIT' },
    '0CCBFFE0' => { 'rtr' => '04CBFFE0' , 'idx' =>  815 , 'extid' => '6E696808400359' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y10_GLOBAL' },
    '0CCC7FE0' => { 'rtr' => '04CC7FE0' , 'idx' =>  817 , 'extid' => 'EE5843861C00DF' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y10_LOCAL' },
    '0CCCFFE0' => { 'rtr' => '04CCFFE0' , 'idx' =>  819 , 'extid' => '6EA5C208DE0358' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y11_GLOBAL' },
    '0CCD7FE0' => { 'rtr' => '04CD7FE0' , 'idx' =>  821 , 'extid' => 'EEFE348DA800E0' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y11_LOCAL' },
    '0CCDFFE0' => { 'rtr' => '04CDFFE0' , 'idx' =>  823 , 'extid' => '6E2B4D0F3D0357' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y12_GLOBAL' },
    '0CCE7FE0' => { 'rtr' => '04CE7FE0' , 'idx' =>  825 , 'extid' => 'EECFDC973500E1' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y12_LOCAL' },
    '0CCEFFE0' => { 'rtr' => '04CEFFE0' , 'idx' =>  827 , 'extid' => '6ECBFA50D1035A' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y1_GLOBAL' },
    '0CCF7FE0' => { 'rtr' => '04CF7FE0' , 'idx' =>  829 , 'extid' => 'EEAD6A653F00D6' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y1_LOCAL' },
    '0CCFFFE0' => { 'rtr' => '04CFFFE0' , 'idx' =>  831 , 'extid' => '6E457557320356' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y2_GLOBAL' },
    '0CD07FE0' => { 'rtr' => '04D07FE0' , 'idx' =>  833 , 'extid' => 'EE9C827FA200D7' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y2_LOCAL' },
    '0CD0FFE0' => { 'rtr' => '04D0FFE0' , 'idx' =>  835 , 'extid' => '6E89DF57AC0355' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y3_GLOBAL' },
    '0CD17FE0' => { 'rtr' => '04D17FE0' , 'idx' =>  837 , 'extid' => 'EE3AF5741600D8' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y3_LOCAL' },
    '0CD1FFE0' => { 'rtr' => '04D1FFE0' , 'idx' =>  839 , 'extid' => '6E831A5EB50354' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y4_GLOBAL' },
    '0CD27FE0' => { 'rtr' => '04D27FE0' , 'idx' =>  841 , 'extid' => 'EEFF524A9800D9' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y4_LOCAL' },
    '0CD2FFE0' => { 'rtr' => '04D2FFE0' , 'idx' =>  843 , 'extid' => '6E4FB05E2B0353' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y5_GLOBAL' },
    '0CD37FE0' => { 'rtr' => '04D37FE0' , 'idx' =>  845 , 'extid' => 'EE5925412C00DA' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y5_LOCAL' },
    '0CD3FFE0' => { 'rtr' => '04D3FFE0' , 'idx' =>  847 , 'extid' => '6EC13F59C80352' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y6_GLOBAL' },
    '0CD47FE0' => { 'rtr' => '04D47FE0' , 'idx' =>  849 , 'extid' => 'EE68CD5BB100DB' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y6_LOCAL' },
    '0CD4FFE0' => { 'rtr' => '04D4FFE0' , 'idx' =>  851 , 'extid' => '6E0D9559560351' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y7_GLOBAL' },
    '0CD57FE0' => { 'rtr' => '04D57FE0' , 'idx' =>  853 , 'extid' => 'EECEBA500500DC' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y7_LOCAL' },
    '0CD5FFE0' => { 'rtr' => '04D5FFE0' , 'idx' =>  855 , 'extid' => '6ED4B54BFA0350' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y8_GLOBAL' },
    '0CD67FE0' => { 'rtr' => '04D67FE0' , 'idx' =>  857 , 'extid' => 'EE38F220EC00DD' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y8_LOCAL' },
    '0CD6FFE0' => { 'rtr' => '04D6FFE0' , 'idx' =>  859 , 'extid' => '6E181F4B64034F' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y9_GLOBAL' },
    '0CD77FE0' => { 'rtr' => '04D77FE0' , 'idx' =>  861 , 'extid' => 'EE9E852B5800DE' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y9_LOCAL' },
    '0CD7FFE0' => { 'rtr' => '04D7FFE0' , 'idx' =>  863 , 'extid' => '00431BEF9C030C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCKED' },
    '0CD83FE0' => { 'rtr' => '04D83FE0' , 'idx' =>  864 , 'extid' => 'C0E4AEF76C0B52' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E21_EXT_1' },
    '0CD87FE0' => { 'rtr' => '04D87FE0' , 'idx' =>  865 , 'extid' => 'C07DA7A6D6048E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E21_EXT_2' },
    '0CD8BFE0' => { 'rtr' => '04D8BFE0' , 'idx' =>  866 , 'extid' => 'C0D546EDF10306' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E22_EXT_1' },
    '0CD8FFE0' => { 'rtr' => '04D8FFE0' , 'idx' =>  867 , 'extid' => 'C04C4FBC4B0B51' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E22_EXT_2' },
    '0CD93FE0' => { 'rtr' => '04D93FE0' , 'idx' =>  868 , 'extid' => 'EEF07561AC07E4' , 'max' =>      650 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_FIXED_TEMPERATURE' },
    '0CD9BFE0' => { 'rtr' => '04D9BFE0' , 'idx' =>  870 , 'extid' => 'E1D769501C00CC' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_MAX_TIME' },
    '0CD9FFE0' => { 'rtr' => '04D9FFE0' , 'idx' =>  871 , 'extid' => 'EA55C0014400CD' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REGULATOR_I' },
    '0CDA7FE0' => { 'rtr' => '04DA7FE0' , 'idx' =>  873 , 'extid' => 'EA31ABA98400CE' , 'max' =>      200 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REGULATOR_P' },
    '0CDAFFE0' => { 'rtr' => '04DAFFE0' , 'idx' =>  875 , 'extid' => '00CAE035FA00C8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HEATING_REQUEST' },
    '0CDB3FE0' => { 'rtr' => '04DB3FE0' , 'idx' =>  876 , 'extid' => '000CCD051004BC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HEATING_REQUEST_2' },
    '0CDB7FE0' => { 'rtr' => '04DB7FE0' , 'idx' =>  877 , 'extid' => 'E12D76FBC90331' , 'max' =>       15 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REQUEST_BLOCK_AFTER_START_TIME' },
    '0CDBBFE0' => { 'rtr' => '04DBBFE0' , 'idx' =>  878 , 'extid' => 'E23409A4FD00C9' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REQUEST_BLOCK_TIME' },
    '0CDC3FE0' => { 'rtr' => '04DC3FE0' , 'idx' =>  880 , 'extid' => '002280F33400F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HEATING_SEASON_ACTIVE' },
    '0CDC7FE0' => { 'rtr' => '04DC7FE0' , 'idx' =>  881 , 'extid' => 'E1E3B281D900F7' , 'max' =>       35 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_DELAYED_TEMP' },
    '0CDCBFE0' => { 'rtr' => '04DCBFE0' , 'idx' =>  882 , 'extid' => 'E1C800448B00F5' , 'max' =>       17 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_IMMEDIATE_TEMP' },
    '0CDCFFE0' => { 'rtr' => '04DCFFE0' , 'idx' =>  883 , 'extid' => 'E1882248C90440' , 'max' =>        2 , 'min' =>        0 , 'format' => 'dp2' , 'read' => 1 , 'text' => 'HEATING_SEASON_MODE' },
    '0CDD3FE0' => { 'rtr' => '04DD3FE0' , 'idx' =>  884 , 'extid' => 'E1FF34393100F6' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_START_DELAY_TIME' },
    '0CDD7FE0' => { 'rtr' => '04DD7FE0' , 'idx' =>  885 , 'extid' => 'E17EE5BF2402F1' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_STOP_DELAY_TIME' },
    '0CDDBFE0' => { 'rtr' => '04DDBFE0' , 'idx' =>  886 , 'extid' => '0E7900A31300CA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SETPOINT' },
    '0CDE3FE0' => { 'rtr' => '04DE3FE0' , 'idx' =>  888 , 'extid' => '0E7B5ED0CD00CF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_START' },
    '0CDEBFE0' => { 'rtr' => '04DEBFE0' , 'idx' =>  890 , 'extid' => '0E4CAA026D0631' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_START_2' },
    '0CDF3FE0' => { 'rtr' => '04DF3FE0' , 'idx' =>  892 , 'extid' => '01FBBDF9BE026E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_STATUS_BLOCK' },
    '0CDF7FE0' => { 'rtr' => '04DF7FE0' , 'idx' =>  893 , 'extid' => '0E901C5F1A00D0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_STOP' },
    '0CDFFFE0' => { 'rtr' => '04DFFFE0' , 'idx' =>  895 , 'extid' => '0EFFD424460632' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_STOP_2' },
    '0CE07FE0' => { 'rtr' => '04E07FE0' , 'idx' =>  897 , 'extid' => '40D1B9506D05DF' , 'max' =>150994944 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SYSTEM_TYPE_GLOBAL' },
    '0CE0BFE0' => { 'rtr' => '04E0BFE0' , 'idx' =>  898 , 'extid' => 'C034BEA42B05DE' , 'max' =>150994944 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SYSTEM_TYPE_LOCAL' },
    '0CE0FFE0' => { 'rtr' => '04E0FFE0' , 'idx' =>  899 , 'extid' => 'C053404CD405C5' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_USE_EXTERNAL_SETPOINT' },
    '0CE13FE0' => { 'rtr' => '04E13FE0' , 'idx' =>  900 , 'extid' => 'C06AA2528F0263' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_ACTIVE' },
    '0CE17FE0' => { 'rtr' => '04E17FE0' , 'idx' =>  901 , 'extid' => '4080AA43F00861' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_ACTIVE_GLOBAL' },
    '0CE1BFE0' => { 'rtr' => '04E1BFE0' , 'idx' =>  902 , 'extid' => 'C00ED82215028E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_DHW' },
    '0CE1FFE0' => { 'rtr' => '04E1FFE0' , 'idx' =>  903 , 'extid' => '2093D1EC64024A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_REQUEST' },
    '0CE23FE0' => { 'rtr' => '04E23FE0' , 'idx' =>  904 , 'extid' => 'E1C4E03DB0075E' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_START_DAY' },
    '0CE27FE0' => { 'rtr' => '04E27FE0' , 'idx' =>  905 , 'extid' => '61A8A44EDB0266' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_START_DAY_GLOBAL' },
    '0CE2BFE0' => { 'rtr' => '04E2BFE0' , 'idx' =>  906 , 'extid' => 'E1AF02C5F30265' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_START_MONTH' },
    '0CE2FFE0' => { 'rtr' => '04E2FFE0' , 'idx' =>  907 , 'extid' => '619AB55EF6075F' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_START_MONTH_GLOBAL' },
    '0CE33FE0' => { 'rtr' => '04E33FE0' , 'idx' =>  908 , 'extid' => 'E1BBA333230264' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_START_YEAR' },
    '0CE37FE0' => { 'rtr' => '04E37FE0' , 'idx' =>  909 , 'extid' => '616081D1590760' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_START_YEAR_GLOBAL' },
    '0CE3BFE0' => { 'rtr' => '04E3BFE0' , 'idx' =>  910 , 'extid' => 'E167BEED150267' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_STOP_DAY' },
    '0CE3FFE0' => { 'rtr' => '04E3FFE0' , 'idx' =>  911 , 'extid' => '6177F4697C0761' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_STOP_DAY_GLOBAL' },
    '0CE43FE0' => { 'rtr' => '04E43FE0' , 'idx' =>  912 , 'extid' => 'E1FAA1FCD50268' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_STOP_MONTH' },
    '0CE47FE0' => { 'rtr' => '04E47FE0' , 'idx' =>  913 , 'extid' => '61DEF91EE30762' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_STOP_MONTH_GLOBAL' },
    '0CE4BFE0' => { 'rtr' => '04E4BFE0' , 'idx' =>  914 , 'extid' => 'E11DBC3A940269' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_STOP_YEAR' },
    '0CE4FFE0' => { 'rtr' => '04E4FFE0' , 'idx' =>  915 , 'extid' => '6128ECB7350763' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_STOP_YEAR_GLOBAL' },
    '0CE53FE0' => { 'rtr' => '04E53FE0' , 'idx' =>  916 , 'extid' => 'E9B0A0966D0B13' , 'max' =>      250 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOTGAS_HIGHEST_DIFF' },
    '0CE57FE0' => { 'rtr' => '04E57FE0' , 'idx' =>  917 , 'extid' => 'E693E59C200B11' , 'max' =>      250 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOTGAS_LOWEST_DIFF' },
    '0CE5FFE0' => { 'rtr' => '04E5FFE0' , 'idx' =>  919 , 'extid' => 'E176B325DC0AD8' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HP_STOPS_UNTIL_ALARM' },
    '0CE63FE0' => { 'rtr' => '04E63FE0' , 'idx' =>  920 , 'extid' => 'E1D2A42A030AE8' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HP_STOPS_UNTIL_ALARM_2' },
    '0CE67FE0' => { 'rtr' => '04E67FE0' , 'idx' =>  921 , 'extid' => 'E1E69DB72F0ADC' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIME' },
    '0CE6BFE0' => { 'rtr' => '04E6BFE0' , 'idx' =>  922 , 'extid' => 'E1F334FA3B0AE9' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIME_2' },
    '0CE6FFE0' => { 'rtr' => '04E6FFE0' , 'idx' =>  923 , 'extid' => 'E1C80D3B990ADA' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_TIME_WINDOW' },
    '0CE73FE0' => { 'rtr' => '04E73FE0' , 'idx' =>  924 , 'extid' => 'E1A5A5129E0AEA' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_TIME_WINDOW_2' },
    '0CE77FE0' => { 'rtr' => '04E77FE0' , 'idx' =>  925 , 'extid' => '02D4592AAF0D3C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HUMIDITY_BOARD_0_10V_GLOBAL' },
    '0CE7FFE0' => { 'rtr' => '04E7FFE0' , 'idx' =>  927 , 'extid' => '00F65C47DF024E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_4_WAY_VALVE' },
    '0CE83FE0' => { 'rtr' => '04E83FE0' , 'idx' =>  928 , 'extid' => '005A35F95B03F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_4_WAY_VALVE_2' },
    '0CE87FE0' => { 'rtr' => '04E87FE0' , 'idx' =>  929 , 'extid' => '00F09C9DD3024C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_ADDITIONAL_ALARM' },
    '0CE8BFE0' => { 'rtr' => '04E8BFE0' , 'idx' =>  930 , 'extid' => '00F4F8900E02F0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_DHW' },
    '0CE8FFE0' => { 'rtr' => '04E8FFE0' , 'idx' =>  931 , 'extid' => '00D9A53A1003AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_RELAY_1' },
    '0CE93FE0' => { 'rtr' => '04E93FE0' , 'idx' =>  932 , 'extid' => '0040AC6BAA03AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_RELAY_2' },
    '0CE97FE0' => { 'rtr' => '04E97FE0' , 'idx' =>  933 , 'extid' => '0037AB5B3C03AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_RELAY_3' },
    '0CE9BFE0' => { 'rtr' => '04E9BFE0' , 'idx' =>  934 , 'extid' => '001B7A8E8103B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_START' },
    '0CE9FFE0' => { 'rtr' => '04E9FFE0' , 'idx' =>  935 , 'extid' => '007DF794DF03AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_TRIAC_1' },
    '0CEA3FE0' => { 'rtr' => '04EA3FE0' , 'idx' =>  936 , 'extid' => '00E4FEC56503AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_TRIAC_2' },
    '0CEA7FE0' => { 'rtr' => '04EA7FE0' , 'idx' =>  937 , 'extid' => '0093F9F5F303AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_TRIAC_3' },
    '0CEABFE0' => { 'rtr' => '04EABFE0' , 'idx' =>  938 , 'extid' => '00A5DAF23603BA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_VALVE_CLOSE' },
    '0CEAFFE0' => { 'rtr' => '04EAFFE0' , 'idx' =>  939 , 'extid' => '00192E4CBB03B9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_VALVE_OPEN' },
    '0CEB3FE0' => { 'rtr' => '04EB3FE0' , 'idx' =>  940 , 'extid' => '0076AEF2D4007A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_BUZZER' },
    '0CEB7FE0' => { 'rtr' => '04EB7FE0' , 'idx' =>  941 , 'extid' => '013A27FDA9009A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR' },
    '0CEBBFE0' => { 'rtr' => '04EBBFE0' , 'idx' =>  942 , 'extid' => '0108E4B1C203F1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_2' },
    '0CEBFFE0' => { 'rtr' => '04EBFFE0' , 'idx' =>  943 , 'extid' => '008BC64CB30093' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_CAN_COMMUNICATION' },
    '0CEC3FE0' => { 'rtr' => '04EC3FE0' , 'idx' =>  944 , 'extid' => '00C00179FB0094' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_COMMUNICATION_ERR' },
    '0CEC7FE0' => { 'rtr' => '04EC7FE0' , 'idx' =>  945 , 'extid' => '0AD66D197B0095' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_CURRENT' },
    '0CECFFE0' => { 'rtr' => '04ECFFE0' , 'idx' =>  947 , 'extid' => '01CB63A5C50096' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_FREERUN' },
    '0CED3FE0' => { 'rtr' => '04ED3FE0' , 'idx' =>  948 , 'extid' => '0251F45BA50097' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_NAK' },
    '0CEDBFE0' => { 'rtr' => '04EDBFE0' , 'idx' =>  950 , 'extid' => '013905FA110098' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_TARGET_FREQ' },
    '0CEDFFE0' => { 'rtr' => '04EDFFE0' , 'idx' =>  951 , 'extid' => '0E7173A5E40099' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_TEMP' },
    '0CEE7FE0' => { 'rtr' => '04EE7FE0' , 'idx' =>  953 , 'extid' => '020706CEB7009B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_VOLTAGE' },
    '0CEEFFE0' => { 'rtr' => '04EEFFE0' , 'idx' =>  955 , 'extid' => '0199F3A0A7009C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_WORKING_FREQ' },
    '0CEF3FE0' => { 'rtr' => '04EF3FE0' , 'idx' =>  956 , 'extid' => '0018FBFE2E030F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CONTACTOR_1' },
    '0CEF7FE0' => { 'rtr' => '04EF7FE0' , 'idx' =>  957 , 'extid' => '0081F2AF940310' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CONTACTOR_2' },
    '0CEFBFE0' => { 'rtr' => '04EFBFE0' , 'idx' =>  958 , 'extid' => '0057227F59009D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COOLING_FAN' },
    '0CEFFFE0' => { 'rtr' => '04EFFFE0' , 'idx' =>  959 , 'extid' => '006E3208CB024F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CRANKCASE_HEATER' },
    '0CF03FE0' => { 'rtr' => '04F03FE0' , 'idx' =>  960 , 'extid' => '0092F8EA6103F2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CRANKCASE_HEATER_2' },
    '0CF07FE0' => { 'rtr' => '04F07FE0' , 'idx' =>  961 , 'extid' => '0E63FC6C33090E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E11_T11_TEMP' },
    '0CF0FFE0' => { 'rtr' => '04F0FFE0' , 'idx' =>  963 , 'extid' => '006DE32336007F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_1' },
    '0CF13FE0' => { 'rtr' => '04F13FE0' , 'idx' =>  964 , 'extid' => '80888802E30B61' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_1_INV' },
    '0CF17FE0' => { 'rtr' => '04F17FE0' , 'idx' =>  965 , 'extid' => '00F4EA728C02A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_2' },
    '0CF1BFE0' => { 'rtr' => '04F1BFE0' , 'idx' =>  966 , 'extid' => '80CF2878330B62' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_2_INV' },
    '0CF1FFE0' => { 'rtr' => '04F1FFE0' , 'idx' =>  967 , 'extid' => '005C0B39AB0B5C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_1' },
    '0CF23FE0' => { 'rtr' => '04F23FE0' , 'idx' =>  968 , 'extid' => '80116A64E20B63' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_1_INV' },
    '0CF27FE0' => { 'rtr' => '04F27FE0' , 'idx' =>  969 , 'extid' => '00C50268110B5B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_2' },
    '0CF2BFE0' => { 'rtr' => '04F2BFE0' , 'idx' =>  970 , 'extid' => '8056CA1E320B64' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_2_INV' },
    '0CF2FFE0' => { 'rtr' => '04F2FFE0' , 'idx' =>  971 , 'extid' => '0EAC0FC4DB0833' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E31_T31_TEMP' },
    '0CF37FE0' => { 'rtr' => '04F37FE0' , 'idx' =>  973 , 'extid' => '0E2A9BB6750825' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E31_T32_TEMP' },
    '0CF3FFE0' => { 'rtr' => '04F3FFE0' , 'idx' =>  975 , 'extid' => '009C840C64099B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E71_EXT' },
    '0CF43FE0' => { 'rtr' => '04F43FE0' , 'idx' =>  976 , 'extid' => '0EE899934A04B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E71_T71_TEMP' },
    '0CF4BFE0' => { 'rtr' => '04F4BFE0' , 'idx' =>  978 , 'extid' => '0E6E0DE1E404BB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E71_T72_TEMP' },
    '0CF53FE0' => { 'rtr' => '04F53FE0' , 'idx' =>  980 , 'extid' => '00DB2476B4099C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E72_EXT' },
    '0CF57FE0' => { 'rtr' => '04F57FE0' , 'idx' =>  981 , 'extid' => '0E03AE284907CC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E72_T71_TEMP' },
    '0CF5FFE0' => { 'rtr' => '04F5FFE0' , 'idx' =>  983 , 'extid' => '0E853A5AE707CD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E72_T72_TEMP' },
    '0CF67FE0' => { 'rtr' => '04F67FE0' , 'idx' =>  985 , 'extid' => '008007F2B7007E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK' },
    '0CF6BFE0' => { 'rtr' => '04F6BFE0' , 'idx' =>  986 , 'extid' => '004C1A29AC03F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK_2' },
    '0CF6FFE0' => { 'rtr' => '04F6FFE0' , 'idx' =>  987 , 'extid' => '003B1D193A03F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK_3' },
    '0CF73FE0' => { 'rtr' => '04F73FE0' , 'idx' =>  988 , 'extid' => '00A5798C9903F5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK_4' },
    '0CF77FE0' => { 'rtr' => '04F77FE0' , 'idx' =>  989 , 'extid' => '007BB4CEB60A0E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_EL_VVB_ALARM' },
    '0CF7BFE0' => { 'rtr' => '04F7BFE0' , 'idx' =>  990 , 'extid' => '0A50F7942F0486' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_EXTERNAL_SETPOINT' },
    '0CF83FE0' => { 'rtr' => '04F83FE0' , 'idx' =>  992 , 'extid' => '0A51533D230B70' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_EXTERNAL_SETPOINT_2' },
    '0CF8BFE0' => { 'rtr' => '04F8BFE0' , 'idx' =>  994 , 'extid' => 'E11E2E44E30661' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_ANALOG' },
    '0CF8FFE0' => { 'rtr' => '04F8FFE0' , 'idx' =>  995 , 'extid' => 'E1B0CF396C0662' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_ANALOG_2' },
    '0CF93FE0' => { 'rtr' => '04F93FE0' , 'idx' =>  996 , 'extid' => '0025FF8E2A024D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_DIGITAL' },
    '0CF97FE0' => { 'rtr' => '04F97FE0' , 'idx' =>  997 , 'extid' => '00D146451403F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_DIGITAL_2' },
    '0CF9BFE0' => { 'rtr' => '04F9BFE0' , 'idx' =>  998 , 'extid' => '02B14826A20080' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT1' },
    '0CFA3FE0' => { 'rtr' => '04FA3FE0' , 'idx' => 1000 , 'extid' => '02CCB255C3008E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT10' },
    '0CFABFE0' => { 'rtr' => '04FABFE0' , 'idx' => 1002 , 'extid' => '024FFBEFA00405' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT10_2' },
    '0CFB3FE0' => { 'rtr' => '04FB3FE0' , 'idx' => 1004 , 'extid' => '0E9310C7C2008F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT10_TEMP' },
    '0CFBBFE0' => { 'rtr' => '04FBBFE0' , 'idx' => 1006 , 'extid' => '0E48E1732B0406' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT10_TEMP_2' },
    '0CFC3FE0' => { 'rtr' => '04FC3FE0' , 'idx' => 1008 , 'extid' => '02BBB565550090' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT11' },
    '0CFCBFE0' => { 'rtr' => '04FCBFE0' , 'idx' => 1010 , 'extid' => '024E3985970407' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT11_2' },
    '0CFD3FE0' => { 'rtr' => '04FD3FE0' , 'idx' => 1012 , 'extid' => '0E584C14670091' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT11_TEMP' },
    '0CFDBFE0' => { 'rtr' => '04FDBFE0' , 'idx' => 1014 , 'extid' => '0E844B73B50408' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT11_TEMP_2' },
    '0CFE3FE0' => { 'rtr' => '04FE3FE0' , 'idx' => 1016 , 'extid' => '0222BC34EF028A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT12' },
    '0CFEBFE0' => { 'rtr' => '04FEBFE0' , 'idx' => 1018 , 'extid' => '024C7F3BCE0409' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT12_2' },
    '0CFF3FE0' => { 'rtr' => '04FF3FE0' , 'idx' => 1020 , 'extid' => '0EDED866C9025A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT12_TEMP' },
    '0CFFBFE0' => { 'rtr' => '04FFBFE0' , 'idx' => 1022 , 'extid' => '0E0AC47456040A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT12_TEMP_2' },
    '0D003FE0' => { 'rtr' => '05003FE0' , 'idx' => 1024 , 'extid' => '0E6C0A67F00081' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT1_TEMP' },
    '0D00BFE0' => { 'rtr' => '0500BFE0' , 'idx' => 1026 , 'extid' => '02284177180082' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT2' },
    '0D013FE0' => { 'rtr' => '05013FE0' , 'idx' => 1028 , 'extid' => '0EEA9E155E0083' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT2_TEMP' },
    '0D01BFE0' => { 'rtr' => '0501BFE0' , 'idx' => 1030 , 'extid' => '025F46478E0084' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT3' },
    '0D023FE0' => { 'rtr' => '05023FE0' , 'idx' => 1032 , 'extid' => '0E21C2C6FB0085' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT3_TEMP' },
    '0D02BFE0' => { 'rtr' => '0502BFE0' , 'idx' => 1034 , 'extid' => '0290D9F8CF0499' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_GLOBAL' },
    '0D033FE0' => { 'rtr' => '05033FE0' , 'idx' => 1036 , 'extid' => '0E57D567400502' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_1' },
    '0D03BFE0' => { 'rtr' => '0503BFE0' , 'idx' => 1038 , 'extid' => '0ECEDC36FA0503' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_2' },
    '0D043FE0' => { 'rtr' => '05043FE0' , 'idx' => 1040 , 'extid' => '0EB9DB066C0504' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_3' },
    '0D04BFE0' => { 'rtr' => '0504BFE0' , 'idx' => 1042 , 'extid' => '0E27BF93CF0505' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_4' },
    '0D053FE0' => { 'rtr' => '05053FE0' , 'idx' => 1044 , 'extid' => '0E50B8A3590506' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_5' },
    '0D05BFE0' => { 'rtr' => '0505BFE0' , 'idx' => 1046 , 'extid' => '0EC9B1F2E30507' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_6' },
    '0D063FE0' => { 'rtr' => '05063FE0' , 'idx' => 1048 , 'extid' => '0EBEB6C2750508' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_7' },
    '0D06BFE0' => { 'rtr' => '0506BFE0' , 'idx' => 1050 , 'extid' => '0E20816508049B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_GLOBAL' },
    '0D073FE0' => { 'rtr' => '05073FE0' , 'idx' => 1052 , 'extid' => '021493F635049A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT45_GLOBAL' },
    '0D07BFE0' => { 'rtr' => '0507BFE0' , 'idx' => 1054 , 'extid' => '0EE0380F9E049C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT45_TEMP_GLOBAL' },
    '0D083FE0' => { 'rtr' => '05083FE0' , 'idx' => 1056 , 'extid' => '02B625E2BB0086' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT5' },
    '0D08BFE0' => { 'rtr' => '0508BFE0' , 'idx' => 1058 , 'extid' => '0EF79B25E60087' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT5_TEMP' },
    '0D093FE0' => { 'rtr' => '05093FE0' , 'idx' => 1060 , 'extid' => '022F2CB3010088' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT6' },
    '0D09BFE0' => { 'rtr' => '0509BFE0' , 'idx' => 1062 , 'extid' => '02FF5EFEBF040B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT6_2' },
    '0D0A3FE0' => { 'rtr' => '050A3FE0' , 'idx' => 1064 , 'extid' => '0E710F57480089' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT6_TEMP' },
    '0D0ABFE0' => { 'rtr' => '050ABFE0' , 'idx' => 1066 , 'extid' => '0E798272B1040C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT6_TEMP_2' },
    '0D0B3FE0' => { 'rtr' => '050B3FE0' , 'idx' => 1068 , 'extid' => '02582B83970C69' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT7' },
    '0D0BBFE0' => { 'rtr' => '050BBFE0' , 'idx' => 1070 , 'extid' => '02FE9C94880C72' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT7_2' },
    '0D0C3FE0' => { 'rtr' => '050C3FE0' , 'idx' => 1072 , 'extid' => '0EBA5384ED0C6A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT7_TEMP' },
    '0D0CBFE0' => { 'rtr' => '050CBFE0' , 'idx' => 1074 , 'extid' => '0EB528722F0C73' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT7_TEMP_2' },
    '0D0D3FE0' => { 'rtr' => '050D3FE0' , 'idx' => 1076 , 'extid' => '02C8949E06008A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT8' },
    '0D0DBFE0' => { 'rtr' => '050DBFE0' , 'idx' => 1078 , 'extid' => '026A77DE1C04AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT81' },
    '0D0E3FE0' => { 'rtr' => '050E3FE0' , 'idx' => 1080 , 'extid' => '0ECDD451B404AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT81_TEMP' },
    '0D0EBFE0' => { 'rtr' => '050EBFE0' , 'idx' => 1082 , 'extid' => '02F37E8FA604AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT82' },
    '0D0F3FE0' => { 'rtr' => '050F3FE0' , 'idx' => 1084 , 'extid' => '0E4B40231A04AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT82_TEMP' },
    '0D0FBFE0' => { 'rtr' => '050FBFE0' , 'idx' => 1086 , 'extid' => '02F5C0D3B5040D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT8_2' },
    '0D103FE0' => { 'rtr' => '05103FE0' , 'idx' => 1088 , 'extid' => '0E4B053638008B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT8_TEMP' },
    '0D10BFE0' => { 'rtr' => '0510BFE0' , 'idx' => 1090 , 'extid' => '0E6C086083040E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT8_TEMP_2' },
    '0D113FE0' => { 'rtr' => '05113FE0' , 'idx' => 1092 , 'extid' => '02BF93AE90008C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT9' },
    '0D11BFE0' => { 'rtr' => '0511BFE0' , 'idx' => 1094 , 'extid' => '02F402B982040F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT9_2' },
    '0D123FE0' => { 'rtr' => '05123FE0' , 'idx' => 1096 , 'extid' => '0E8059E59D008D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT9_TEMP' },
    '0D12BFE0' => { 'rtr' => '0512BFE0' , 'idx' => 1098 , 'extid' => '0EA0A2601D0410' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT9_TEMP_2' },
    '0D133FE0' => { 'rtr' => '05133FE0' , 'idx' => 1100 , 'extid' => '001A6BB1B70250' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HEATING_CABLE' },
    '0D137FE0' => { 'rtr' => '05137FE0' , 'idx' => 1101 , 'extid' => '00A3CFA3EA0411' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HEATING_CABLE_2' },
    '0D13BFE0' => { 'rtr' => '0513BFE0' , 'idx' => 1102 , 'extid' => '00CC502EFA0092' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HP' },
    '0D13FFE0' => { 'rtr' => '0513FFE0' , 'idx' => 1103 , 'extid' => '0086A8CA4C03F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HP_2' },
    '0D143FE0' => { 'rtr' => '05143FE0' , 'idx' => 1104 , 'extid' => '023BC26E370D39' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HUMIDITY' },
    '0D14BFE0' => { 'rtr' => '0514BFE0' , 'idx' => 1106 , 'extid' => '028E20D54D0D3A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HUMIDITY_2' },
    '0D153FE0' => { 'rtr' => '05153FE0' , 'idx' => 1108 , 'extid' => '02F927E5DB0D3B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HUMIDITY_3' },
    '0D15BFE0' => { 'rtr' => '0515BFE0' , 'idx' => 1110 , 'extid' => '0260EDE3E00C9D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_AI_1' },
    '0D163FE0' => { 'rtr' => '05163FE0' , 'idx' => 1112 , 'extid' => '02678027F90C9E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_AI_5' },
    '0D16BFE0' => { 'rtr' => '0516BFE0' , 'idx' => 1114 , 'extid' => '00DFC719DF0865' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_DO10' },
    '0D16FFE0' => { 'rtr' => '0516FFE0' , 'idx' => 1115 , 'extid' => '0031C978F30866' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_DO12' },
    '0D173FE0' => { 'rtr' => '05173FE0' , 'idx' => 1116 , 'extid' => '00D140D41E0CD7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_DO8' },
    '0D177FE0' => { 'rtr' => '05177FE0' , 'idx' => 1117 , 'extid' => '001F7C0F440D38' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB_B_DO5' },
    '0D17BFE0' => { 'rtr' => '0517BFE0' , 'idx' => 1118 , 'extid' => '00A83CEBFE009E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_LP' },
    '0D17FFE0' => { 'rtr' => '0517FFE0' , 'idx' => 1119 , 'extid' => '0009CA5D1B03F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_LP_2' },
    '0D183FE0' => { 'rtr' => '05183FE0' , 'idx' => 1120 , 'extid' => '00A04716A3009F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB1' },
    '0D187FE0' => { 'rtr' => '05187FE0' , 'idx' => 1121 , 'extid' => '00C5D3F8D803FA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB1_2' },
    '0D18BFE0' => { 'rtr' => '0518BFE0' , 'idx' => 1122 , 'extid' => '00394E471900A0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB2' },
    '0D18FFE0' => { 'rtr' => '0518FFE0' , 'idx' => 1123 , 'extid' => '00C795468103FB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB2_2' },
    '0D193FE0' => { 'rtr' => '05193FE0' , 'idx' => 1124 , 'extid' => '004EE167F30C45' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_EXT_1' },
    '0D197FE0' => { 'rtr' => '05197FE0' , 'idx' => 1125 , 'extid' => '00584D02290C4C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_MV_E12_PUMP_G1_DIGITAL' },
    '0D19BFE0' => { 'rtr' => '0519BFE0' , 'idx' => 1126 , 'extid' => '024C365E680C16' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_T1' },
    '0D1A3FE0' => { 'rtr' => '051A3FE0' , 'idx' => 1128 , 'extid' => '003E61EE070C4A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_VALVE_CLOSE' },
    '0D1A7FE0' => { 'rtr' => '051A7FE0' , 'idx' => 1129 , 'extid' => '00C6F0CD7B0C4B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_VALVE_OPEN' },
    '0D1ABFE0' => { 'rtr' => '051ABFE0' , 'idx' => 1130 , 'extid' => '027941CCB0007B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PGU_L1' },
    '0D1B3FE0' => { 'rtr' => '051B3FE0' , 'idx' => 1132 , 'extid' => '02E0489D0A007C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PGU_L2' },
    '0D1BBFE0' => { 'rtr' => '051BBFE0' , 'idx' => 1134 , 'extid' => '02974FAD9C007D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PGU_L3' },
    '0D1C3FE0' => { 'rtr' => '051C3FE0' , 'idx' => 1136 , 'extid' => '006E175E7705BE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PHASE_DETECTOR' },
    '0D1C7FE0' => { 'rtr' => '051C7FE0' , 'idx' => 1137 , 'extid' => '005880FF310956' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PHASE_DETECTOR_2' },
    '0D1CBFE0' => { 'rtr' => '051CBFE0' , 'idx' => 1138 , 'extid' => '00E44C966C05AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_EXT_1' },
    '0D1CFFE0' => { 'rtr' => '051CFFE0' , 'idx' => 1139 , 'extid' => '217A829F8F05AC' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_VALVE' },
    '0D1D3FE0' => { 'rtr' => '051D3FE0' , 'idx' => 1140 , 'extid' => '00CCEB2A1205AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_VALVE_CLOSE' },
    '0D1D7FE0' => { 'rtr' => '051D7FE0' , 'idx' => 1141 , 'extid' => '002E34962805AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_VALVE_OPEN' },
    '0D1DBFE0' => { 'rtr' => '051DBFE0' , 'idx' => 1142 , 'extid' => '00FD57CF6C05B7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PROTECTIVE_ANODE' },
    '0D1DFFE0' => { 'rtr' => '051DFFE0' , 'idx' => 1143 , 'extid' => '00BBFDBAA602FD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_DHW_DIGITAL' },
    '0D1E3FE0' => { 'rtr' => '051E3FE0' , 'idx' => 1144 , 'extid' => '0078C9526005B1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_E71_G71_DIGITAL' },
    '0D1E7FE0' => { 'rtr' => '051E7FE0' , 'idx' => 1145 , 'extid' => '00C5033EAE07CE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_E72_G71_DIGITAL' },
    '0D1EBFE0' => { 'rtr' => '051EBFE0' , 'idx' => 1146 , 'extid' => '004617B8D502A7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G1_DIGITAL' },
    '0D1EFFE0' => { 'rtr' => '051EFFE0' , 'idx' => 1147 , 'extid' => '217EFB651D02FF' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G2_ANALOG' },
    '0D1F3FE0' => { 'rtr' => '051F3FE0' , 'idx' => 1148 , 'extid' => '21769985D40BBB' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PUMP_G2_ANALOG_2' },
    '0D1F7FE0' => { 'rtr' => '051F7FE0' , 'idx' => 1149 , 'extid' => '007F9A841000A1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G2_DIGITAL' },
    '0D1FBFE0' => { 'rtr' => '051FBFE0' , 'idx' => 1150 , 'extid' => '00143A281603FC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PUMP_G2_DIGITAL_2' },
    '0D1FFFE0' => { 'rtr' => '051FFFE0' , 'idx' => 1151 , 'extid' => '01B25165830300' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G3_ANALOG' },
    '0D203FE0' => { 'rtr' => '05203FE0' , 'idx' => 1152 , 'extid' => '0068E1905300A2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G3_DIGITAL' },
    '0D207FE0' => { 'rtr' => '05207FE0' , 'idx' => 1153 , 'extid' => '00D5B4F7D603FD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PUMP_G3_DIGITAL_2' },
    '0D20BFE0' => { 'rtr' => '0520BFE0' , 'idx' => 1154 , 'extid' => '6169F65B800244' , 'max' =>       30 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_INTERVALL' },
    '0D20FFE0' => { 'rtr' => '0520FFE0' , 'idx' => 1155 , 'extid' => '018A73E4350168' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_MODE' },
    '0D213FE0' => { 'rtr' => '05213FE0' , 'idx' => 1156 , 'extid' => '0289452993016B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_OFF_TIME' },
    '0D21BFE0' => { 'rtr' => '0521BFE0' , 'idx' => 1158 , 'extid' => '02B1838E70016A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_ON_TIME' },
    '0D223FE0' => { 'rtr' => '05223FE0' , 'idx' => 1160 , 'extid' => '0664DD577800A3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_GT5' },
    '0D22BFE0' => { 'rtr' => '0522BFE0' , 'idx' => 1162 , 'extid' => '02EAE3D63905B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_GT5_GLOBAL' },
    '0D233FE0' => { 'rtr' => '05233FE0' , 'idx' => 1164 , 'extid' => '01BB7F1B9900A4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_LED_MODE' },
    '0D237FE0' => { 'rtr' => '05237FE0' , 'idx' => 1165 , 'extid' => '02EE3778D900A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_POT' },
    '0D23FFE0' => { 'rtr' => '0523FFE0' , 'idx' => 1167 , 'extid' => '021D45302105B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_POT_GLOBAL' },
    '0D247FE0' => { 'rtr' => '05247FE0' , 'idx' => 1169 , 'extid' => '0E5F7D58E80242' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_ROOM_TEMP' },
    '0D24FFE0' => { 'rtr' => '0524FFE0' , 'idx' => 1171 , 'extid' => '0EA370F2E60570' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_ROOM_TEMP_GLOBAL' },
    '0D257FE0' => { 'rtr' => '05257FE0' , 'idx' => 1173 , 'extid' => '0063479E31065F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_SUMMARY_ALARM' },
    '0D25BFE0' => { 'rtr' => '0525BFE0' , 'idx' => 1174 , 'extid' => '00A8BC3F9F00A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_SYSTEM_ON' },
    '0D25FFE0' => { 'rtr' => '0525FFE0' , 'idx' => 1175 , 'extid' => '00D3CF541200A7' , 'max' => 50331648 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_VXV' },
    '0D263FE0' => { 'rtr' => '05263FE0' , 'idx' => 1176 , 'extid' => '00A0DF341503FE' , 'max' => 50331648 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_VXV_2' },
    '0D267FE0' => { 'rtr' => '05267FE0' , 'idx' => 1177 , 'extid' => '01C34AAE520916' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ICONS_IOB6126_EXTERN_BITMASK' },
    '0D26BFE0' => { 'rtr' => '0526BFE0' , 'idx' => 1178 , 'extid' => '000EC773520D0B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'INIT_MV_STATUS_DONE' },
    '0D26FFE0' => { 'rtr' => '0526FFE0' , 'idx' => 1179 , 'extid' => '814D48DDB806C0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_BOOT_COUNT' },
    '0D273FE0' => { 'rtr' => '05273FE0' , 'idx' => 1180 , 'extid' => '01267BEB2A02AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED' },
    '0D277FE0' => { 'rtr' => '05277FE0' , 'idx' => 1181 , 'extid' => '01EC9ED3470448' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_2' },
    '0D27BFE0' => { 'rtr' => '0527BFE0' , 'idx' => 1182 , 'extid' => '019B99E3D10449' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_3' },
    '0D27FFE0' => { 'rtr' => '0527FFE0' , 'idx' => 1183 , 'extid' => '0105FD7672044B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_4' },
    '0D283FE0' => { 'rtr' => '05283FE0' , 'idx' => 1184 , 'extid' => '0172FA46E4044A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_5' },
    '0D287FE0' => { 'rtr' => '05287FE0' , 'idx' => 1185 , 'extid' => '01EBF3175E044C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_6' },
    '0D28BFE0' => { 'rtr' => '0528BFE0' , 'idx' => 1186 , 'extid' => '019CF427C8044D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_7' },
    '0D28FFE0' => { 'rtr' => '0528FFE0' , 'idx' => 1187 , 'extid' => '1212C74ED502AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION' },
    '0D297FE0' => { 'rtr' => '05297FE0' , 'idx' => 1189 , 'extid' => '12D9064DEE0442' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_2' },
    '0D29FFE0' => { 'rtr' => '0529FFE0' , 'idx' => 1191 , 'extid' => '12AE017D780443' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_3' },
    '0D2A7FE0' => { 'rtr' => '052A7FE0' , 'idx' => 1193 , 'extid' => '123065E8DB0444' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_4' },
    '0D2AFFE0' => { 'rtr' => '052AFFE0' , 'idx' => 1195 , 'extid' => '124762D84D0445' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_5' },
    '0D2B7FE0' => { 'rtr' => '052B7FE0' , 'idx' => 1197 , 'extid' => '12DE6B89F70446' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_6' },
    '0D2BFFE0' => { 'rtr' => '052BFFE0' , 'idx' => 1199 , 'extid' => '12A96CB9610447' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_7' },
    '0D2C7FE0' => { 'rtr' => '052C7FE0' , 'idx' => 1201 , 'extid' => '128C4247A708E4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_GLOBAL' },
    '0D2CFFE0' => { 'rtr' => '052CFFE0' , 'idx' => 1203 , 'extid' => '016D07017505D8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_MAIN_COOLING_CONNECTED' },
    '0D2D3FE0' => { 'rtr' => '052D3FE0' , 'idx' => 1204 , 'extid' => '122B16C99D05D9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_MAIN_COOLING_VERSION' },
    '0D2DBFE0' => { 'rtr' => '052DBFE0' , 'idx' => 1206 , 'extid' => '01F905031502E4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_POOL_CONNECTED' },
    '0D2DFFE0' => { 'rtr' => '052DFFE0' , 'idx' => 1207 , 'extid' => '1214C98A4702E5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_POOL_VERSION' },
    '0D2E7FE0' => { 'rtr' => '052E7FE0' , 'idx' => 1209 , 'extid' => '010CA1C11D0AC9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SOLAR_CONNECTED' },
    '0D2EBFE0' => { 'rtr' => '052EBFE0' , 'idx' => 1210 , 'extid' => '12C3AB84680ACA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SOLAR_VERSION' },
    '0D2F3FE0' => { 'rtr' => '052F3FE0' , 'idx' => 1212 , 'extid' => '01232004980803' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SUB_COOLING_CONNECTED' },
    '0D2F7FE0' => { 'rtr' => '052F7FE0' , 'idx' => 1213 , 'extid' => '1274C8946A0804' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SUB_COOLING_VERSION' },
    '0D2FFFE0' => { 'rtr' => '052FFFE0' , 'idx' => 1215 , 'extid' => '0180BBBABC02E6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_CONNECTED' },
    '0D303FE0' => { 'rtr' => '05303FE0' , 'idx' => 1216 , 'extid' => '01D7E9397907CF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_CONNECTED_2' },
    '0D307FE0' => { 'rtr' => '05307FE0' , 'idx' => 1217 , 'extid' => '12C8D95C1B02E7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_VERSION' },
    '0D30FFE0' => { 'rtr' => '0530FFE0' , 'idx' => 1219 , 'extid' => '127FC61C7807D0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_VERSION_2' },
    '0D317FE0' => { 'rtr' => '05317FE0' , 'idx' => 1221 , 'extid' => '013094A8A503FF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_CONNECTED' },
    '0D31BFE0' => { 'rtr' => '0531BFE0' , 'idx' => 1222 , 'extid' => '01BF5051060403' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_CONNECTED_2' },
    '0D31FFE0' => { 'rtr' => '0531FFE0' , 'idx' => 1223 , 'extid' => '124D8856C20400' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_VERSION' },
    '0D327FE0' => { 'rtr' => '05327FE0' , 'idx' => 1225 , 'extid' => '12CFE90E610404' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_VERSION_2' },
    '0D32FFE0' => { 'rtr' => '0532FFE0' , 'idx' => 1227 , 'extid' => '01F020CB6D02AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_HEAT_CONNECTED' },
    '0D333FE0' => { 'rtr' => '05333FE0' , 'idx' => 1228 , 'extid' => '0168C8FC160B74' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_HEAT_CONNECTED_2' },
    '0D337FE0' => { 'rtr' => '05337FE0' , 'idx' => 1229 , 'extid' => '1299651BCA042E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_HEAT_VERSION' },
    '0D33FFE0' => { 'rtr' => '0533FFE0' , 'idx' => 1231 , 'extid' => '0113477C900BD6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_CONNECTED' },
    '0D343FE0' => { 'rtr' => '05343FE0' , 'idx' => 1232 , 'extid' => '019CDFA6AE0BD7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_CONNECTED_2' },
    '0D347FE0' => { 'rtr' => '05347FE0' , 'idx' => 1233 , 'extid' => '12FEAC864C0BD8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_VERSION' },
    '0D34FFE0' => { 'rtr' => '0534FFE0' , 'idx' => 1235 , 'extid' => '12EC3ADA540BD9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_VERSION_2' },
    '0D357FE0' => { 'rtr' => '05357FE0' , 'idx' => 1237 , 'extid' => '81AE30D1F906BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_BOOT_COUNT' },
    '0D35BFE0' => { 'rtr' => '0535BFE0' , 'idx' => 1238 , 'extid' => '81812E7C260639' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_CONNECTED_BITMASK' },
    '0D35FFE0' => { 'rtr' => '0535FFE0' , 'idx' => 1239 , 'extid' => 'A19E82E3A00CC8' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_DO8_G6_OR_SUMMARY_ALARM' },
    '0D363FE0' => { 'rtr' => '05363FE0' , 'idx' => 1240 , 'extid' => '01DF7DAE6102A8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_CONNECTED' },
    '0D367FE0' => { 'rtr' => '05367FE0' , 'idx' => 1241 , 'extid' => '01F9A509900401' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_CONNECTED_2' },
    '0D36BFE0' => { 'rtr' => '0536BFE0' , 'idx' => 1242 , 'extid' => '01783DD8E70BCC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_CONNECTED' },
    '0D36FFE0' => { 'rtr' => '0536FFE0' , 'idx' => 1243 , 'extid' => '012D1A45140BCD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_CONNECTED_2' },
    '0D373FE0' => { 'rtr' => '05373FE0' , 'idx' => 1244 , 'extid' => '01002542290D02' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_CONNECTED' },
    '0D377FE0' => { 'rtr' => '05377FE0' , 'idx' => 1245 , 'extid' => '0168B9BD960D03' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_CONNECTED_2' },
    '0D37BFE0' => { 'rtr' => '0537BFE0' , 'idx' => 1246 , 'extid' => '1283CBAC440D04' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_VERSION' },
    '0D383FE0' => { 'rtr' => '05383FE0' , 'idx' => 1248 , 'extid' => '12FF58E4ED0D05' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_VERSION_2' },
    '0D38BFE0' => { 'rtr' => '0538BFE0' , 'idx' => 1250 , 'extid' => '120A248A970BCE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_VERSION' },
    '0D393FE0' => { 'rtr' => '05393FE0' , 'idx' => 1252 , 'extid' => '1287407E230BCF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_VERSION_2' },
    '0D39BFE0' => { 'rtr' => '0539BFE0' , 'idx' => 1254 , 'extid' => '01720E94C40ACC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_CONNECTED' },
    '0D39FFE0' => { 'rtr' => '0539FFE0' , 'idx' => 1255 , 'extid' => '01ECD935FD0AEB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_CONNECTED_2' },
    '0D3A3FE0' => { 'rtr' => '053A3FE0' , 'idx' => 1256 , 'extid' => '12EB3DE1FA0ACD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_VERSION' },
    '0D3ABFE0' => { 'rtr' => '053ABFE0' , 'idx' => 1258 , 'extid' => '128D7332000AEC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_VERSION_2' },
    '0D3B3FE0' => { 'rtr' => '053B3FE0' , 'idx' => 1260 , 'extid' => '125882C4E602A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_VERSION' },
    '0D3BBFE0' => { 'rtr' => '053BBFE0' , 'idx' => 1262 , 'extid' => '12200008A50402' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_VERSION_2' },
    '0D3C3FE0' => { 'rtr' => '053C3FE0' , 'idx' => 1264 , 'extid' => '00B0CF9E6D0B8C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_REBOOT' },
    '0D3C7FE0' => { 'rtr' => '053C7FE0' , 'idx' => 1265 , 'extid' => '012516229700AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOBX10_CONNECTED' },
    '0D3CBFE0' => { 'rtr' => '053CBFE0' , 'idx' => 1266 , 'extid' => '1282BF1AFF00AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOBX10_VERSION' },
    '0D3D3FE0' => { 'rtr' => '053D3FE0' , 'idx' => 1268 , 'extid' => '11602326BB0C65' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_AW_LIGHT_COMP_CONNECTED' },
    '0D3D7FE0' => { 'rtr' => '053D7FE0' , 'idx' => 1269 , 'extid' => '120FA10E7B0C6B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_AW_LIGHT_COMP_VERSION' },
    '0D3DFFE0' => { 'rtr' => '053DFFE0' , 'idx' => 1271 , 'extid' => '01797ED2370D1E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION' },
    '0D3E3FE0' => { 'rtr' => '053E3FE0' , 'idx' => 1272 , 'extid' => '014CF768560D1F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_2' },
    '0D3E7FE0' => { 'rtr' => '053E7FE0' , 'idx' => 1273 , 'extid' => '013BF058C00D20' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_3' },
    '0D3EBFE0' => { 'rtr' => '053EBFE0' , 'idx' => 1274 , 'extid' => '01A594CD630D21' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_4' },
    '0D3EFFE0' => { 'rtr' => '053EFFE0' , 'idx' => 1275 , 'extid' => '01D293FDF50D22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_5' },
    '0D3F3FE0' => { 'rtr' => '053F3FE0' , 'idx' => 1276 , 'extid' => '014B9AAC4F0D23' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_6' },
    '0D3F7FE0' => { 'rtr' => '053F7FE0' , 'idx' => 1277 , 'extid' => '013C9D9CD90D24' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_7' },
    '0D3FBFE0' => { 'rtr' => '053FBFE0' , 'idx' => 1278 , 'extid' => '01F7D26D5F0D25' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION' },
    '0D3FFFE0' => { 'rtr' => '053FFFE0' , 'idx' => 1279 , 'extid' => '01BA0DA9480D26' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_2' },
    '0D403FE0' => { 'rtr' => '05403FE0' , 'idx' => 1280 , 'extid' => '01CD0A99DE0D27' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_3' },
    '0D407FE0' => { 'rtr' => '05407FE0' , 'idx' => 1281 , 'extid' => '01536E0C7D0D28' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_4' },
    '0D40BFE0' => { 'rtr' => '0540BFE0' , 'idx' => 1282 , 'extid' => '0124693CEB0D29' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_5' },
    '0D40FFE0' => { 'rtr' => '0540FFE0' , 'idx' => 1283 , 'extid' => '01BD606D510D2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_6' },
    '0D413FE0' => { 'rtr' => '05413FE0' , 'idx' => 1284 , 'extid' => '01CA675DC70D2B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_7' },
    '0D417FE0' => { 'rtr' => '05417FE0' , 'idx' => 1285 , 'extid' => '01B1D7F6620D2C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION' },
    '0D41BFE0' => { 'rtr' => '0541BFE0' , 'idx' => 1286 , 'extid' => '01B738ED3F0D2D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_2' },
    '0D41FFE0' => { 'rtr' => '0541FFE0' , 'idx' => 1287 , 'extid' => '01C03FDDA90D2E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_3' },
    '0D423FE0' => { 'rtr' => '05423FE0' , 'idx' => 1288 , 'extid' => '015E5B480A0D2F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_4' },
    '0D427FE0' => { 'rtr' => '05427FE0' , 'idx' => 1289 , 'extid' => '01295C789C0D30' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_5' },
    '0D42BFE0' => { 'rtr' => '0542BFE0' , 'idx' => 1290 , 'extid' => '01B05529260D31' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_6' },
    '0D42FFE0' => { 'rtr' => '0542FFE0' , 'idx' => 1291 , 'extid' => '01C75219B00D32' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_7' },
    '0D433FE0' => { 'rtr' => '05433FE0' , 'idx' => 1292 , 'extid' => '019FE4CB990D48' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_2_CONNECTED' },
    '0D437FE0' => { 'rtr' => '05437FE0' , 'idx' => 1293 , 'extid' => '015E6A14590D49' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_3_CONNECTED' },
    '0D43BFE0' => { 'rtr' => '0543BFE0' , 'idx' => 1294 , 'extid' => '01762ABE240D47' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_CONNECTED' },
    '0D43FFE0' => { 'rtr' => '0543FFE0' , 'idx' => 1295 , 'extid' => '816A19F20A0D51' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_CONNECTED_BITMASK' },
    '0D443FE0' => { 'rtr' => '05443FE0' , 'idx' => 1296 , 'extid' => '016F2C72870D3D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_GENERATION' },
    '0D447FE0' => { 'rtr' => '05447FE0' , 'idx' => 1297 , 'extid' => '017EE473540D3E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_GENERATION_2' },
    '0D44BFE0' => { 'rtr' => '0544BFE0' , 'idx' => 1298 , 'extid' => '0109E343C20D3F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_GENERATION_3' },
    '0D44FFE0' => { 'rtr' => '0544FFE0' , 'idx' => 1299 , 'extid' => '01F65069B80D43' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_REVISION' },
    '0D453FE0' => { 'rtr' => '05453FE0' , 'idx' => 1300 , 'extid' => '01AC5F09F80D44' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_REVISION_2' },
    '0D457FE0' => { 'rtr' => '05457FE0' , 'idx' => 1301 , 'extid' => '01DB58396E0D45' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_REVISION_3' },
    '0D45BFE0' => { 'rtr' => '0545BFE0' , 'idx' => 1302 , 'extid' => '01E8A217230D40' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_VERSION' },
    '0D45FFE0' => { 'rtr' => '0545FFE0' , 'idx' => 1303 , 'extid' => '01895718E00D41' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_VERSION_2' },
    '0D463FE0' => { 'rtr' => '05463FE0' , 'idx' => 1304 , 'extid' => '01FE5028760D42' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_VERSION_3' },
    '0D467FE0' => { 'rtr' => '05467FE0' , 'idx' => 1305 , 'extid' => '01C29C0E9E0B6D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_CONNECTED' },
    '0D46BFE0' => { 'rtr' => '0546BFE0' , 'idx' => 1306 , 'extid' => '01442C9EA50D36' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_GENERATION' },
    '0D46FFE0' => { 'rtr' => '0546FFE0' , 'idx' => 1307 , 'extid' => '014B5EE4440D37' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_REVISION' },
    '0D473FE0' => { 'rtr' => '05473FE0' , 'idx' => 1308 , 'extid' => '025BDDF7D30B6E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_VERSION' },
    '0D47BFE0' => { 'rtr' => '0547BFE0' , 'idx' => 1310 , 'extid' => '0134DBC34B0D33' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_POOL_GENERATION' },
    '0D47FFE0' => { 'rtr' => '0547FFE0' , 'idx' => 1311 , 'extid' => '0130484EC10D34' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_POOL_REVISION' },
    '0D483FE0' => { 'rtr' => '05483FE0' , 'idx' => 1312 , 'extid' => '01FC5CDC190D35' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_POOL_VERSION' },
    '0D487FE0' => { 'rtr' => '05487FE0' , 'idx' => 1313 , 'extid' => '8312E8EDF90171' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LANGUAGE' },
    '0D497FE0' => { 'rtr' => '05497FE0' , 'idx' => 1317 , 'extid' => '82466A831A017F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'LANGUAGE_ISO639_1' },
    '0D49FFE0' => { 'rtr' => '0549FFE0' , 'idx' => 1319 , 'extid' => 'E2A569B174085E' , 'max' =>     1200 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_2_ALARM_DELAY' },
    '0D4A7FE0' => { 'rtr' => '054A7FE0' , 'idx' => 1321 , 'extid' => 'E2EBD0344400BD' , 'max' =>     1200 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_ALARM_DELAY' },
    '0D4AFFE0' => { 'rtr' => '054AFFE0' , 'idx' => 1323 , 'extid' => 'E1385ECE850AD2' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOPS_UNTIL_ALARM' },
    '0D4B3FE0' => { 'rtr' => '054B3FE0' , 'idx' => 1324 , 'extid' => 'E18E05B9030AE5' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOPS_UNTIL_ALARM_2' },
    '0D4B7FE0' => { 'rtr' => '054B7FE0' , 'idx' => 1325 , 'extid' => 'E132ACFBA80AD6' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIME' },
    '0D4BBFE0' => { 'rtr' => '054BBFE0' , 'idx' => 1326 , 'extid' => 'E1F89C2D3D0AE6' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIME_2' },
    '0D4BFFE0' => { 'rtr' => '054BFFE0' , 'idx' => 1327 , 'extid' => 'E12165367B0AD4' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_TIME_WINDOW' },
    '0D4C3FE0' => { 'rtr' => '054C3FE0' , 'idx' => 1328 , 'extid' => 'E1B75C16250AE7' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_TIME_WINDOW_2' },
    '0D4C7FE0' => { 'rtr' => '054C7FE0' , 'idx' => 1329 , 'extid' => '4067368D550077' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP' },
    '0D4CBFE0' => { 'rtr' => '054CBFE0' , 'idx' => 1330 , 'extid' => '006E7A13440597' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_CLOSE_GLOBAL' },
    '0D4CFFE0' => { 'rtr' => '054CFFE0' , 'idx' => 1331 , 'extid' => '0031D6749C097A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_D_VALVE_GLOBAL' },
    '0D4D3FE0' => { 'rtr' => '054D3FE0' , 'idx' => 1332 , 'extid' => '0099C0DA3F097D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_G2_GLOBAL' },
    '0D4D7FE0' => { 'rtr' => '054D7FE0' , 'idx' => 1333 , 'extid' => '005FAFD3B803DF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_G4_GLOBAL' },
    '0D4DBFE0' => { 'rtr' => '054DBFE0' , 'idx' => 1334 , 'extid' => '004F6DEF9C03DE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_OPEN_GLOBAL' },
    '0D4DFFE0' => { 'rtr' => '054DFFE0' , 'idx' => 1335 , 'extid' => '610B8C00CC097E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_SIGNAL_GLOBAL' },
    '0D4E3FE0' => { 'rtr' => '054E3FE0' , 'idx' => 1336 , 'extid' => '0076ED86F70079' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_TILLSKOTT' },
    '0D4E7FE0' => { 'rtr' => '054E7FE0' , 'idx' => 1337 , 'extid' => '61E1BE4FF50078' , 'max' =>      240 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_TIME' },
    '0D4EBFE0' => { 'rtr' => '054EBFE0' , 'idx' => 1338 , 'extid' => '817C7B65DC063A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MIXED_CIRCUITS_CONNECTED_BITMASK' },
    '0D4EFFE0' => { 'rtr' => '054EFFE0' , 'idx' => 1339 , 'extid' => '013968EBBC0D0C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXED_CIRCUITS_SETPOINT_INIT_DONE_BITMASK' },
    '0D4F3FE0' => { 'rtr' => '054F3FE0' , 'idx' => 1340 , 'extid' => '01780DCC6B0D0D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXED_CIRCUITS_VALVEMODE_INIT_DONE_BITMASK' },
    '0D4F7FE0' => { 'rtr' => '054F7FE0' , 'idx' => 1341 , 'extid' => '61C1C41C8903D2' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_CLOSE_TIME_GLOBAL' },
    '0D4FBFE0' => { 'rtr' => '054FBFE0' , 'idx' => 1342 , 'extid' => '62C20AB7B303D6' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_DEFROST_DELAY_TIME_GLOBAL' },
    '0D503FE0' => { 'rtr' => '05503FE0' , 'idx' => 1344 , 'extid' => '00A6F57CB0050A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_1' },
    '0D507FE0' => { 'rtr' => '05507FE0' , 'idx' => 1345 , 'extid' => '003FFC2D0A050B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_2' },
    '0D50BFE0' => { 'rtr' => '0550BFE0' , 'idx' => 1346 , 'extid' => '0048FB1D9C050C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_3' },
    '0D50FFE0' => { 'rtr' => '0550FFE0' , 'idx' => 1347 , 'extid' => '00D69F883F050D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_4' },
    '0D513FE0' => { 'rtr' => '05513FE0' , 'idx' => 1348 , 'extid' => '00A198B8A9050E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_5' },
    '0D517FE0' => { 'rtr' => '05517FE0' , 'idx' => 1349 , 'extid' => '003891E913050F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_6' },
    '0D51BFE0' => { 'rtr' => '0551BFE0' , 'idx' => 1350 , 'extid' => '004F96D9850510' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_7' },
    '0D51FFE0' => { 'rtr' => '0551FFE0' , 'idx' => 1351 , 'extid' => '00DA4773D70509' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_GLOBAL' },
    '0D523FE0' => { 'rtr' => '05523FE0' , 'idx' => 1352 , 'extid' => '0043129BF80998' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_PRI_COOLING' },
    '0D527FE0' => { 'rtr' => '05527FE0' , 'idx' => 1353 , 'extid' => '008AACEDF60999' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_SEC_COOLING' },
    '0D52BFE0' => { 'rtr' => '0552BFE0' , 'idx' => 1354 , 'extid' => '69CB20868303D8' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MAX_LIMIT_HEATING_SYSTEM' },
    '0D52FFE0' => { 'rtr' => '0552FFE0' , 'idx' => 1355 , 'extid' => '6102B0EEB70277' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_1' },
    '0D533FE0' => { 'rtr' => '05533FE0' , 'idx' => 1356 , 'extid' => '619BB9BF0D07BA' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_2' },
    '0D537FE0' => { 'rtr' => '05537FE0' , 'idx' => 1357 , 'extid' => '61ECBE8F9B07B8' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_3' },
    '0D53BFE0' => { 'rtr' => '0553BFE0' , 'idx' => 1358 , 'extid' => '6172DA1A3807B9' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_4' },
    '0D53FFE0' => { 'rtr' => '0553FFE0' , 'idx' => 1359 , 'extid' => '6105DD2AAE07BB' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_5' },
    '0D543FE0' => { 'rtr' => '05543FE0' , 'idx' => 1360 , 'extid' => '619CD47B1407BC' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_6' },
    '0D547FE0' => { 'rtr' => '05547FE0' , 'idx' => 1361 , 'extid' => '61EBD34B8207BD' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_7' },
    '0D54BFE0' => { 'rtr' => '0554BFE0' , 'idx' => 1362 , 'extid' => '61C314B02E07C0' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_GLOBAL' },
    '0D54FFE0' => { 'rtr' => '0554FFE0' , 'idx' => 1363 , 'extid' => '6905D4FB4E03D1' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NEUTRALZONE_GLOBAL' },
    '0D553FE0' => { 'rtr' => '05553FE0' , 'idx' => 1364 , 'extid' => '40F2A2575003D4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NEUTRALZONE_LIMITATION_GLOBAL' },
    '0D557FE0' => { 'rtr' => '05557FE0' , 'idx' => 1365 , 'extid' => '6247D78DCF03D5' , 'max' =>      600 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NEUTRALZONE_LIMITATION_TIME_GLOBAL' },
    '0D55FFE0' => { 'rtr' => '0555FFE0' , 'idx' => 1367 , 'extid' => '0E4783BF260527' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_1' },
    '0D567FE0' => { 'rtr' => '05567FE0' , 'idx' => 1369 , 'extid' => '0EDE8AEE9C0528' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_2' },
    '0D56FFE0' => { 'rtr' => '0556FFE0' , 'idx' => 1371 , 'extid' => '0EA98DDE0A0529' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_3' },
    '0D577FE0' => { 'rtr' => '05577FE0' , 'idx' => 1373 , 'extid' => '0E37E94BA9052A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_4' },
    '0D57FFE0' => { 'rtr' => '0557FFE0' , 'idx' => 1375 , 'extid' => '0E40EE7B3F052B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_5' },
    '0D587FE0' => { 'rtr' => '05587FE0' , 'idx' => 1377 , 'extid' => '0ED9E72A85052C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_6' },
    '0D58FFE0' => { 'rtr' => '0558FFE0' , 'idx' => 1379 , 'extid' => '0EAEE01A13052D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_7' },
    '0D597FE0' => { 'rtr' => '05597FE0' , 'idx' => 1381 , 'extid' => '0E8DACF5C20520' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_1' },
    '0D59FFE0' => { 'rtr' => '0559FFE0' , 'idx' => 1383 , 'extid' => '0E14A5A4780521' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_2' },
    '0D5A7FE0' => { 'rtr' => '055A7FE0' , 'idx' => 1385 , 'extid' => '0E63A294EE0522' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_3' },
    '0D5AFFE0' => { 'rtr' => '055AFFE0' , 'idx' => 1387 , 'extid' => '0EFDC6014D0523' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_4' },
    '0D5B7FE0' => { 'rtr' => '055B7FE0' , 'idx' => 1389 , 'extid' => '0E8AC131DB0524' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_5' },
    '0D5BFFE0' => { 'rtr' => '055BFFE0' , 'idx' => 1391 , 'extid' => '0E13C860610525' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_6' },
    '0D5C7FE0' => { 'rtr' => '055C7FE0' , 'idx' => 1393 , 'extid' => '0E64CF50F70526' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_7' },
    '0D5CFFE0' => { 'rtr' => '055CFFE0' , 'idx' => 1395 , 'extid' => '61A09F089403D3' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_OPEN_TIME_GLOBAL' },
    '0D5D3FE0' => { 'rtr' => '055D3FE0' , 'idx' => 1396 , 'extid' => '6A5544F20C0372' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_D' },
    '0D5DBFE0' => { 'rtr' => '055DBFE0' , 'idx' => 1398 , 'extid' => '6A2BF58EB103D9' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_I' },
    '0D5E3FE0' => { 'rtr' => '055E3FE0' , 'idx' => 1400 , 'extid' => '623DDC078A0563' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_MAX' },
    '0D5EBFE0' => { 'rtr' => '055EBFE0' , 'idx' => 1402 , 'extid' => '6201D138D30564' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_MIN' },
    '0D5F3FE0' => { 'rtr' => '055F3FE0' , 'idx' => 1404 , 'extid' => '6A4F9E267103DB' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_P' },
    '0D5FBFE0' => { 'rtr' => '055FBFE0' , 'idx' => 1406 , 'extid' => '0089CE456B04E6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_1' },
    '0D5FFFE0' => { 'rtr' => '055FFFE0' , 'idx' => 1407 , 'extid' => '0010C714D104E7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_2' },
    '0D603FE0' => { 'rtr' => '05603FE0' , 'idx' => 1408 , 'extid' => '0067C0244704E8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_3' },
    '0D607FE0' => { 'rtr' => '05607FE0' , 'idx' => 1409 , 'extid' => '00F9A4B1E404E9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_4' },
    '0D60BFE0' => { 'rtr' => '0560BFE0' , 'idx' => 1410 , 'extid' => '008EA3817204EA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_5' },
    '0D60FFE0' => { 'rtr' => '0560FFE0' , 'idx' => 1411 , 'extid' => '0017AAD0C804EB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_6' },
    '0D613FE0' => { 'rtr' => '05613FE0' , 'idx' => 1412 , 'extid' => '0060ADE05E0832' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_7' },
    '0D617FE0' => { 'rtr' => '05617FE0' , 'idx' => 1413 , 'extid' => '009363B8A804D2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_GLOBAL' },
    '0D61BFE0' => { 'rtr' => '0561BFE0' , 'idx' => 1414 , 'extid' => '009755FDE304EC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G71' },
    '0D61FFE0' => { 'rtr' => '0561FFE0' , 'idx' => 1415 , 'extid' => '62E77AF67003D0' , 'max' =>     6000 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_RUNNING_TIME_GLOBAL' },
    '0D627FE0' => { 'rtr' => '05627FE0' , 'idx' => 1417 , 'extid' => '6940EDBD6F03D7' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_START_LIMIT_HEATING_SYSTEM' },
    '0D62BFE0' => { 'rtr' => '0562BFE0' , 'idx' => 1418 , 'extid' => '01B8440D7D03E2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_TIMECONTROLLED_GLOBAL' },
    '0D62FFE0' => { 'rtr' => '0562FFE0' , 'idx' => 1419 , 'extid' => '40DB0290DD03DC' , 'max' =>167772160 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_USE_NEUTRALZONE_REGULATOR' },
    '0D633FE0' => { 'rtr' => '05633FE0' , 'idx' => 1420 , 'extid' => '0061D87A3804ED' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_1' },
    '0D637FE0' => { 'rtr' => '05637FE0' , 'idx' => 1421 , 'extid' => '00F8D12B8204EE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_2' },
    '0D63BFE0' => { 'rtr' => '0563BFE0' , 'idx' => 1422 , 'extid' => '008FD61B1404EF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_3' },
    '0D63FFE0' => { 'rtr' => '0563FFE0' , 'idx' => 1423 , 'extid' => '0011B28EB704F0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_4' },
    '0D643FE0' => { 'rtr' => '05643FE0' , 'idx' => 1424 , 'extid' => '0066B5BE2104F1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_5' },
    '0D647FE0' => { 'rtr' => '05647FE0' , 'idx' => 1425 , 'extid' => '00FFBCEF9B04F2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_6' },
    '0D64BFE0' => { 'rtr' => '0564BFE0' , 'idx' => 1426 , 'extid' => '0088BBDF0D04F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_7' },
    '0D64FFE0' => { 'rtr' => '0564FFE0' , 'idx' => 1427 , 'extid' => '40CA94436204D4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_GLOBAL' },
    '0D653FE0' => { 'rtr' => '05653FE0' , 'idx' => 1428 , 'extid' => '000F5947F204F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_1' },
    '0D657FE0' => { 'rtr' => '05657FE0' , 'idx' => 1429 , 'extid' => '009650164804F5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_2' },
    '0D65BFE0' => { 'rtr' => '0565BFE0' , 'idx' => 1430 , 'extid' => '00E15726DE04F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_3' },
    '0D65FFE0' => { 'rtr' => '0565FFE0' , 'idx' => 1431 , 'extid' => '007F33B37D04F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_4' },
    '0D663FE0' => { 'rtr' => '05663FE0' , 'idx' => 1432 , 'extid' => '00083483EB04F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_5' },
    '0D667FE0' => { 'rtr' => '05667FE0' , 'idx' => 1433 , 'extid' => '00913DD25104F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_6' },
    '0D66BFE0' => { 'rtr' => '0566BFE0' , 'idx' => 1434 , 'extid' => '00E63AE2C704FA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_7' },
    '0D66FFE0' => { 'rtr' => '0566FFE0' , 'idx' => 1435 , 'extid' => '4070F9A4FA04D3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_GLOBAL' },
    '0D673FE0' => { 'rtr' => '05673FE0' , 'idx' => 1436 , 'extid' => '02C050B2090A35' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_CONDENSATIONGUARD_ACTIVE_BITMASK' },
    '0D67BFE0' => { 'rtr' => '0567BFE0' , 'idx' => 1438 , 'extid' => '007CD550870A33' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_CONDENSATIONGUARD_ACTIVE_GLOBAL' },
    '0D67FFE0' => { 'rtr' => '0567FFE0' , 'idx' => 1439 , 'extid' => '01689569980D63' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_CONDENSATIONGUARD_ALERT_ACTIVE_BITMASK' },
    '0D683FE0' => { 'rtr' => '05683FE0' , 'idx' => 1440 , 'extid' => '218161509F0965' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_1' },
    '0D687FE0' => { 'rtr' => '05687FE0' , 'idx' => 1441 , 'extid' => '21186801250966' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_2' },
    '0D68BFE0' => { 'rtr' => '0568BFE0' , 'idx' => 1442 , 'extid' => '216F6F31B30967' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_3' },
    '0D68FFE0' => { 'rtr' => '0568FFE0' , 'idx' => 1443 , 'extid' => '21F10BA4100968' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_4' },
    '0D693FE0' => { 'rtr' => '05693FE0' , 'idx' => 1444 , 'extid' => '21860C94860969' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_5' },
    '0D697FE0' => { 'rtr' => '05697FE0' , 'idx' => 1445 , 'extid' => '211F05C53C096A' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_6' },
    '0D69BFE0' => { 'rtr' => '0569BFE0' , 'idx' => 1446 , 'extid' => '216802F5AA096B' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_7' },
    '0D69FFE0' => { 'rtr' => '0569FFE0' , 'idx' => 1447 , 'extid' => '2153ED79CD0880' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_GLOBAL' },
    '0D6A3FE0' => { 'rtr' => '056A3FE0' , 'idx' => 1448 , 'extid' => '2138510F0B0881' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_PRI_COOLING' },
    '0D6A7FE0' => { 'rtr' => '056A7FE0' , 'idx' => 1449 , 'extid' => '21F1EF79050908' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_SEC_COOLING' },
    '0D6ABFE0' => { 'rtr' => '056ABFE0' , 'idx' => 1450 , 'extid' => '007650B81B07FA' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_ACTIVE' },
    '0D6AFFE0' => { 'rtr' => '056AFFE0' , 'idx' => 1451 , 'extid' => '61711891FF076B' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DELAY_HEATING_GLOBAL' },
    '0D6B3FE0' => { 'rtr' => '056B3FE0' , 'idx' => 1452 , 'extid' => '0EF5C134D5095D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_1' },
    '0D6BBFE0' => { 'rtr' => '056BBFE0' , 'idx' => 1454 , 'extid' => '0E6CC8656F095E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_2' },
    '0D6C3FE0' => { 'rtr' => '056C3FE0' , 'idx' => 1456 , 'extid' => '0E1BCF55F9095F' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_3' },
    '0D6CBFE0' => { 'rtr' => '056CBFE0' , 'idx' => 1458 , 'extid' => '0E85ABC05A0960' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_4' },
    '0D6D3FE0' => { 'rtr' => '056D3FE0' , 'idx' => 1460 , 'extid' => '0EF2ACF0CC0961' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_5' },
    '0D6DBFE0' => { 'rtr' => '056DBFE0' , 'idx' => 1462 , 'extid' => '0E6BA5A1760962' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_6' },
    '0D6E3FE0' => { 'rtr' => '056E3FE0' , 'idx' => 1464 , 'extid' => '0E1CA291E00963' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_7' },
    '0D6EBFE0' => { 'rtr' => '056EBFE0' , 'idx' => 1466 , 'extid' => '0E67C1B8E30836' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_GLOBAL' },
    '0D6F3FE0' => { 'rtr' => '056F3FE0' , 'idx' => 1468 , 'extid' => '0E022C5B7E087D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_PRI_COOLING' },
    '0D6FBFE0' => { 'rtr' => '056FBFE0' , 'idx' => 1470 , 'extid' => '0ECB922D700907' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_SEC_COOLING' },
    '0D703FE0' => { 'rtr' => '05703FE0' , 'idx' => 1472 , 'extid' => '6E5E88AC2D0772' , 'max' =>      350 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEW_POINT_SENSOR_SETPOINT_MIN_GLOBAL' },
    '0D70BFE0' => { 'rtr' => '0570BFE0' , 'idx' => 1474 , 'extid' => '009DF805BE0852' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_E31_G2' },
    '0D70FFE0' => { 'rtr' => '0570FFE0' , 'idx' => 1475 , 'extid' => '61FBAE166E09BB' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_FLOWSENSOR_TYPE_GLOBAL' },
    '0D713FE0' => { 'rtr' => '05713FE0' , 'idx' => 1476 , 'extid' => '00552EF6290A56' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_FREEZEGUARD_ACTIVE_GLOBAL' },
    '0D717FE0' => { 'rtr' => '05717FE0' , 'idx' => 1477 , 'extid' => '65DB20760F0805' , 'max' =>       10 , 'min' =>      -10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_FREEZEGUARD_START' },
    '0D71BFE0' => { 'rtr' => '0571BFE0' , 'idx' => 1478 , 'extid' => '69DBC26B46076C' , 'max' =>      100 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_GT45_INFLUENCE_GLOBAL' },
    '0D71FFE0' => { 'rtr' => '0571FFE0' , 'idx' => 1479 , 'extid' => '6D60AF3BB20769' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_INCREASE_ROOM_SETPOINT_GLOBAL' },
    '0D723FE0' => { 'rtr' => '05723FE0' , 'idx' => 1480 , 'extid' => '6186FE4CED09BA' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_MAIN_FLOWSENSOR_TYPE' },
    '0D727FE0' => { 'rtr' => '05727FE0' , 'idx' => 1481 , 'extid' => '65D1F5A6C8076D' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_OUTDOOR_TEMPERATURE_LIMIT_GLOBAL' },
    '0D72BFE0' => { 'rtr' => '0572BFE0' , 'idx' => 1482 , 'extid' => '611BB16DB208F5' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_ROOMSENSOR_TYPE_GLOBAL' },
    '0D72FFE0' => { 'rtr' => '0572FFE0' , 'idx' => 1483 , 'extid' => '6E2D12B8C8076E' , 'max' =>      350 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_SETPOINT_MIN_GLOBAL' },
    '0D737FE0' => { 'rtr' => '05737FE0' , 'idx' => 1485 , 'extid' => '61511EA1E709BC' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_SUB_FLOWSENSOR_TYPE' },
    '0D73BFE0' => { 'rtr' => '0573BFE0' , 'idx' => 1486 , 'extid' => '025903E14F0D5D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_1' },
    '0D743FE0' => { 'rtr' => '05743FE0' , 'idx' => 1488 , 'extid' => '02C00AB0F50D46' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_2' },
    '0D74BFE0' => { 'rtr' => '0574BFE0' , 'idx' => 1490 , 'extid' => '02B70D80630D5E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_3' },
    '0D753FE0' => { 'rtr' => '05753FE0' , 'idx' => 1492 , 'extid' => '02296915C00D5F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_4' },
    '0D75BFE0' => { 'rtr' => '0575BFE0' , 'idx' => 1494 , 'extid' => '025E6E25560D60' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_5' },
    '0D763FE0' => { 'rtr' => '05763FE0' , 'idx' => 1496 , 'extid' => '02C76774EC0D61' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_6' },
    '0D76BFE0' => { 'rtr' => '0576BFE0' , 'idx' => 1498 , 'extid' => '02B060447A0D62' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_7' },
    '0D773FE0' => { 'rtr' => '05773FE0' , 'idx' => 1500 , 'extid' => '0E7D647F32087F' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_GLOBAL' },
    '0D77BFE0' => { 'rtr' => '0577BFE0' , 'idx' => 1502 , 'extid' => '0E32BDBE78087E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_PRI_COOLING' },
    '0D783FE0' => { 'rtr' => '05783FE0' , 'idx' => 1504 , 'extid' => '0EFB03C8760906' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_SEC_COOLING' },
    '0D78BFE0' => { 'rtr' => '0578BFE0' , 'idx' => 1506 , 'extid' => '6DFD36A8B60768' , 'max' =>      100 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_UNDER_SWING_ZONE_GLOBAL' },
    '0D78FFE0' => { 'rtr' => '0578FFE0' , 'idx' => 1507 , 'extid' => '407FD9E02508FA' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_WHEN_HEATING_SEASONG_GLOBAL' },
    '0D793FE0' => { 'rtr' => '05793FE0' , 'idx' => 1508 , 'extid' => '40C6817A80076A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DEW_POINT_SENSOR_ACTIVATED_GLOBAL' },
    '0D797FE0' => { 'rtr' => '05797FE0' , 'idx' => 1509 , 'extid' => 'C2A0367B6D09ED' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DEW_POINT_SENSOR_ALARM_BITMASK' },
    '0D79FFE0' => { 'rtr' => '0579FFE0' , 'idx' => 1511 , 'extid' => '00AA92E1180766' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DEW_POINT_SENSOR_ALARM_GLOBAL' },
    '0D7A3FE0' => { 'rtr' => '057A3FE0' , 'idx' => 1512 , 'extid' => '40680276A408FD' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DISABLE_COOLING_GLOBAL' },
    '0D7A7FE0' => { 'rtr' => '057A7FE0' , 'idx' => 1513 , 'extid' => '00CC30D1200862' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DOWNLOADING_VARIABLES' },
    '0D7ABFE0' => { 'rtr' => '057ABFE0' , 'idx' => 1514 , 'extid' => '00E2FAA7BB0B8D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DOWNLOADING_VARIABLES_FOR_MIXING_VALVE' },
    '0D7AFFE0' => { 'rtr' => '057AFFE0' , 'idx' => 1515 , 'extid' => '0EAFA14C17090B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E11_T11_SETPOINT' },
    '0D7B7FE0' => { 'rtr' => '057B7FE0' , 'idx' => 1517 , 'extid' => '0177C0211D0C60' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_CAN_ROOM_SENOR_CONNECTED' },
    '0D7BBFE0' => { 'rtr' => '057BBFE0' , 'idx' => 1518 , 'extid' => '0E4F6ABDDC0C5F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_CAN_ROOM_SENSOR_GT45' },
    '0D7C3FE0' => { 'rtr' => '057C3FE0' , 'idx' => 1520 , 'extid' => 'C0B786FD240C61' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_DISPLAY_ROOM_SENSOR_ACKNOW' },
    '0D7C7FE0' => { 'rtr' => '057C7FE0' , 'idx' => 1521 , 'extid' => '069DCD5C2E0C46' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_E1x_T1_ALARM' },
    '0D7CFFE0' => { 'rtr' => '057CFFE0' , 'idx' => 1523 , 'extid' => '8689CD82BB0C59' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ATTENUATION_FACTOR' },
    '0D7D7FE0' => { 'rtr' => '057D7FE0' , 'idx' => 1525 , 'extid' => '86F8BC4DFA0C56' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_CHECK_DISPLAY_SYSTEM_ON' },
    '0D7DFFE0' => { 'rtr' => '057DFFE0' , 'idx' => 1527 , 'extid' => '869AF0D7A60C4F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_COUPLINGDIFFERENS_ROOM' },
    '0D7E7FE0' => { 'rtr' => '057E7FE0' , 'idx' => 1529 , 'extid' => '82C990BD440C1D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_D_VALUE' },
    '0D7EFFE0' => { 'rtr' => '057EFFE0' , 'idx' => 1531 , 'extid' => '80E8533D5B0C37' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ENABLE_HEATING_BLOCK_BY_EXT' },
    '0D7F3FE0' => { 'rtr' => '057F3FE0' , 'idx' => 1532 , 'extid' => '80C27420B00C3D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ENABLE_HIGH_PROTECTION_HS_BY_EXT' },
    '0D7F7FE0' => { 'rtr' => '057F7FE0' , 'idx' => 1533 , 'extid' => '86A11C4ED20C4E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ERASE_EEPROM_NEXT_STARTUP' },
    '0D7FFFE0' => { 'rtr' => '057FFFE0' , 'idx' => 1535 , 'extid' => '86C5C2A2160C06' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_EXTERNAL_TEMP_VALUE' },
    '0D807FE0' => { 'rtr' => '05807FE0' , 'idx' => 1537 , 'extid' => '81BF243E930C35' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_FREEZEGARD_START_DELAY_TIME' },
    '0D80BFE0' => { 'rtr' => '0580BFE0' , 'idx' => 1538 , 'extid' => '86B5B459E50BFE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_FREEZEGARD_START_TEMPERATURE' },
    '0D813FE0' => { 'rtr' => '05813FE0' , 'idx' => 1540 , 'extid' => '86A060B9E90BF9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_FREEZEGARD_STOP_TEMPERATURE' },
    '0D81BFE0' => { 'rtr' => '0581BFE0' , 'idx' => 1542 , 'extid' => '81244D29E40C58' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_COOLING_MODE' },
    '0D81FFE0' => { 'rtr' => '0581FFE0' , 'idx' => 1543 , 'extid' => '862F7ED68C0C2C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_LEFT_Y' },
    '0D827FE0' => { 'rtr' => '05827FE0' , 'idx' => 1545 , 'extid' => '86C58027CC0BF3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_PARALLEL_OFFSET' },
    '0D82FFE0' => { 'rtr' => '0582FFE0' , 'idx' => 1547 , 'extid' => '86191719180C02' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_RIGHT_Y' },
    '0D837FE0' => { 'rtr' => '05837FE0' , 'idx' => 1549 , 'extid' => '86B2BED34E0C20' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y1' },
    '0D83FFE0' => { 'rtr' => '0583FFE0' , 'idx' => 1551 , 'extid' => '86650D0D650C29' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y10' },
    '0D847FE0' => { 'rtr' => '05847FE0' , 'idx' => 1553 , 'extid' => '86120A3DF30C2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y11' },
    '0D84FFE0' => { 'rtr' => '0584FFE0' , 'idx' => 1555 , 'extid' => '868B036C490C2B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y12' },
    '0D857FE0' => { 'rtr' => '05857FE0' , 'idx' => 1557 , 'extid' => '862BB782F40C21' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y2' },
    '0D85FFE0' => { 'rtr' => '0585FFE0' , 'idx' => 1559 , 'extid' => '865CB0B2620C22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y3' },
    '0D867FE0' => { 'rtr' => '05867FE0' , 'idx' => 1561 , 'extid' => '86C2D427C10C23' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y4' },
    '0D86FFE0' => { 'rtr' => '0586FFE0' , 'idx' => 1563 , 'extid' => '86B5D317570C24' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y5' },
    '0D877FE0' => { 'rtr' => '05877FE0' , 'idx' => 1565 , 'extid' => '862CDA46ED0C25' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y6' },
    '0D87FFE0' => { 'rtr' => '0587FFE0' , 'idx' => 1567 , 'extid' => '865BDD767B0C26' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y7' },
    '0D887FE0' => { 'rtr' => '05887FE0' , 'idx' => 1569 , 'extid' => '86CB626BEA0C27' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y8' },
    '0D88FFE0' => { 'rtr' => '0588FFE0' , 'idx' => 1571 , 'extid' => '86BC655B7C0C28' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y9' },
    '0D897FE0' => { 'rtr' => '05897FE0' , 'idx' => 1573 , 'extid' => '864805DCA40C47' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_DELAYED_TEMP' },
    '0D89FFE0' => { 'rtr' => '0589FFE0' , 'idx' => 1575 , 'extid' => '86474BC5CE0C15' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_IMMEDIATE_TEMP' },
    '0D8A7FE0' => { 'rtr' => '058A7FE0' , 'idx' => 1577 , 'extid' => '867C4AD5D90C48' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_MODE' },
    '0D8AFFE0' => { 'rtr' => '058AFFE0' , 'idx' => 1579 , 'extid' => '86E885BE8C0C17' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_START_DELAY_TIME' },
    '0D8B7FE0' => { 'rtr' => '058B7FE0' , 'idx' => 1581 , 'extid' => '8678DC41BA0C18' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_STOP_DELAY_TIME' },
    '0D8BFFE0' => { 'rtr' => '058BFFE0' , 'idx' => 1583 , 'extid' => '80F0DBEA330C36' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SYSTEM_TYPE' },
    '0D8C3FE0' => { 'rtr' => '058C3FE0' , 'idx' => 1584 , 'extid' => '808577AF980C08' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_ACTIVE' },
    '0D8C7FE0' => { 'rtr' => '058C7FE0' , 'idx' => 1585 , 'extid' => '862CF8F3400C0A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HOLIDAY_LEVEL_TEMPERATURE' },
    '0D8CFFE0' => { 'rtr' => '058CFFE0' , 'idx' => 1587 , 'extid' => '018A2231010C3A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_START_DAY' },
    '0D8D3FE0' => { 'rtr' => '058D3FE0' , 'idx' => 1588 , 'extid' => '815B6A58E30C39' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_START_MONTH' },
    '0D8D7FE0' => { 'rtr' => '058D7FE0' , 'idx' => 1589 , 'extid' => '81078B72350C1F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_START_YEAR' },
    '0D8DBFE0' => { 'rtr' => '058DBFE0' , 'idx' => 1590 , 'extid' => '81A13108F70C3F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_STOP_DAY' },
    '0D8DFFE0' => { 'rtr' => '058DFFE0' , 'idx' => 1591 , 'extid' => '814689BDC30C3C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_STOP_MONTH' },
    '0D8E3FE0' => { 'rtr' => '058E3FE0' , 'idx' => 1592 , 'extid' => '81537E36250C3B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_STOP_YEAR' },
    '0D8E7FE0' => { 'rtr' => '058E7FE0' , 'idx' => 1593 , 'extid' => '8659A00D9D0C50' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INCREASE_ROOM_SETPOINT' },
    '0D8EFFE0' => { 'rtr' => '058EFFE0' , 'idx' => 1595 , 'extid' => '80A999A8C60C51' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_AI1' },
    '0D8F3FE0' => { 'rtr' => '058F3FE0' , 'idx' => 1596 , 'extid' => '803090F97C0C52' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_AI2' },
    '0D8F7FE0' => { 'rtr' => '058F7FE0' , 'idx' => 1597 , 'extid' => '80AEF46CDF0C53' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_AI5' },
    '0D8FBFE0' => { 'rtr' => '058FBFE0' , 'idx' => 1598 , 'extid' => '800030FE3F0C07' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_EXT_INPUT' },
    '0D8FFFE0' => { 'rtr' => '058FFFE0' , 'idx' => 1599 , 'extid' => '82A847DC840C1C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_I_VALUE' },
    '0D907FE0' => { 'rtr' => '05907FE0' , 'idx' => 1601 , 'extid' => '06D3E57E9A0C54' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_MAX_AI1' },
    '0D90FFE0' => { 'rtr' => '0590FFE0' , 'idx' => 1603 , 'extid' => '86F4C266F40BFC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_MAX_TEMPERAURE_GT41' },
    '0D917FE0' => { 'rtr' => '05917FE0' , 'idx' => 1605 , 'extid' => '86D0169ED50C55' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_MIN_AI1' },
    '0D91FFE0' => { 'rtr' => '0591FFE0' , 'idx' => 1607 , 'extid' => '8653F6E68D0BFD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_MIN_TEMPERAURE_GT41' },
    '0D927FE0' => { 'rtr' => '05927FE0' , 'idx' => 1609 , 'extid' => '8218113CB40BF4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_M_VALVE_DEFROST_DELAY' },
    '0D92FFE0' => { 'rtr' => '0592FFE0' , 'idx' => 1611 , 'extid' => '86B74895190C4D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_M_VALVE_LIMIT_TIME' },
    '0D937FE0' => { 'rtr' => '05937FE0' , 'idx' => 1613 , 'extid' => '82BFB011F10BFF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_M_VALVE_RUNNING_TIME' },
    '0D93FFE0' => { 'rtr' => '0593FFE0' , 'idx' => 1615 , 'extid' => '866A025FE00BF6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZONE_CONTROLLED' },
    '0D947FE0' => { 'rtr' => '05947FE0' , 'idx' => 1617 , 'extid' => '8613D517D20C2F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_M_VALVE_LIMIT' },
    '0D94FFE0' => { 'rtr' => '0594FFE0' , 'idx' => 1619 , 'extid' => '86D072F0BC0C30' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_M_VALVE_LIMIT_TIME' },
    '0D957FE0' => { 'rtr' => '05957FE0' , 'idx' => 1621 , 'extid' => '8628B63CE30C34' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_RAMP_DOWN_TIME' },
    '0D95FFE0' => { 'rtr' => '0595FFE0' , 'idx' => 1623 , 'extid' => '865CC0C9210C33' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_RAMP_UP_TIME' },
    '0D967FE0' => { 'rtr' => '05967FE0' , 'idx' => 1625 , 'extid' => '86ED0C7B6A0C2E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_SIZE' },
    '0D96FFE0' => { 'rtr' => '0596FFE0' , 'idx' => 1627 , 'extid' => '86286882970C32' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_TEMP_DECREASE_M_VALVE' },
    '0D977FE0' => { 'rtr' => '05977FE0' , 'idx' => 1629 , 'extid' => '8643F9DEE30C31' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_TEMP_NO_INCREASE_M_VALVE' },
    '0D97FFE0' => { 'rtr' => '0597FFE0' , 'idx' => 1631 , 'extid' => '80620D2E210C0D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PARTY_MODE_ENABLE' },
    '0D983FE0' => { 'rtr' => '05983FE0' , 'idx' => 1632 , 'extid' => '862EBCC1F90C14' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PID_AIRSYSTEM_ACTIVE' },
    '0D98BFE0' => { 'rtr' => '0598BFE0' , 'idx' => 1634 , 'extid' => '828E5E20310C19' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PID_MAX_VALUE' },
    '0D993FE0' => { 'rtr' => '05993FE0' , 'idx' => 1636 , 'extid' => '8259B592700C1A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PID_MIN_VALUE' },
    '0D99BFE0' => { 'rtr' => '0599BFE0' , 'idx' => 1638 , 'extid' => '825A0105990C1B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_P_VALUE' },
    '0D9A3FE0' => { 'rtr' => '059A3FE0' , 'idx' => 1640 , 'extid' => '8117E506360C2D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ROOMSENSOR_INFLUENCE_FACTOR' },
    '0D9A7FE0' => { 'rtr' => '059A7FE0' , 'idx' => 1641 , 'extid' => '814A526F5B0BF5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'rp2' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_ROOM_PROGRAM_MODE' },
    '0D9ABFE0' => { 'rtr' => '059ABFE0' , 'idx' => 1642 , 'extid' => '8635FFD7B20C03' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ROOM_SENSOR_ACTIVE' },
    '0D9B3FE0' => { 'rtr' => '059B3FE0' , 'idx' => 1644 , 'extid' => '858E6674D50C38' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_T1_KORRIGERING' },
    '0D9B7FE0' => { 'rtr' => '059B7FE0' , 'idx' => 1645 , 'extid' => '854EDF1E430C3E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_T5_KORRIGERING' },
    '0D9BBFE0' => { 'rtr' => '059BBFE0' , 'idx' => 1646 , 'extid' => '86D947DA820C0B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_T5_SETPOINT' },
    '0D9C3FE0' => { 'rtr' => '059C3FE0' , 'idx' => 1648 , 'extid' => '86C7DACCE10C0E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TEMP_TIMECONTROLLED' },
    '0D9CBFE0' => { 'rtr' => '059CBFE0' , 'idx' => 1650 , 'extid' => '814713BEA40BDA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'rp1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM' },
    '0D9CFFE0' => { 'rtr' => '059CFFE0' , 'idx' => 1651 , 'extid' => '82C52E3F910BE2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_5FRI' },
    '0D9D7FE0' => { 'rtr' => '059D7FE0' , 'idx' => 1653 , 'extid' => '826A1151AC0BEA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_5FRI_2' },
    '0D9DFFE0' => { 'rtr' => '059DFFE0' , 'idx' => 1655 , 'extid' => '82A87329CF0BDD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_1MON' },
    '0D9E7FE0' => { 'rtr' => '059E7FE0' , 'idx' => 1657 , 'extid' => '82BAFDF97A0BEB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_1MON_2' },
    '0D9EFFE0' => { 'rtr' => '059EFFE0' , 'idx' => 1659 , 'extid' => '82DD2A73410BE3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_6SAT' },
    '0D9F7FE0' => { 'rtr' => '059F7FE0' , 'idx' => 1661 , 'extid' => '829443810C0BEC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_6SAT_2' },
    '0D9FFFE0' => { 'rtr' => '059FFFE0' , 'idx' => 1663 , 'extid' => '820EE65D6E0BE4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_7SUN' },
    '0DA07FE0' => { 'rtr' => '05A07FE0' , 'idx' => 1665 , 'extid' => '825A8967620BED' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_7SUN_2' },
    '0DA0FFE0' => { 'rtr' => '05A0FFE0' , 'idx' => 1667 , 'extid' => '827EA0EE1B0BE1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_4THU' },
    '0DA17FE0' => { 'rtr' => '05A17FE0' , 'idx' => 1669 , 'extid' => '825AA978A10BEE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_4THU_2' },
    '0DA1FFE0' => { 'rtr' => '05A1FFE0' , 'idx' => 1671 , 'extid' => '829C7B92630BDF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_2TUE' },
    '0DA27FE0' => { 'rtr' => '05A27FE0' , 'idx' => 1673 , 'extid' => '82E4FC54930BEF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_2TUE_2' },
    '0DA2FFE0' => { 'rtr' => '05A2FFE0' , 'idx' => 1675 , 'extid' => '82A3F80EFD0BE0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_3WED' },
    '0DA37FE0' => { 'rtr' => '05A37FE0' , 'idx' => 1677 , 'extid' => '82F28713EB0BF0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_3WED_2' },
    '0DA3FFE0' => { 'rtr' => '05A3FFE0' , 'idx' => 1679 , 'extid' => '864E663EA20BF1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_UI_BRAND' },
    '0DA47FE0' => { 'rtr' => '05A47FE0' , 'idx' => 1681 , 'extid' => '86145F89880C13' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_VALVE_AO_0_10V_ACTIVE' },
    '0DA4FFE0' => { 'rtr' => '05A4FFE0' , 'idx' => 1683 , 'extid' => '00B485612A0C9C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EXT_FUNCTION_TRIGGED' },
    '0DA53FE0' => { 'rtr' => '05A53FE0' , 'idx' => 1684 , 'extid' => '0694427BED0BFA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_FREEZEGUARD_ACTIVE' },
    '0DA5BFE0' => { 'rtr' => '05A5BFE0' , 'idx' => 1686 , 'extid' => '06A32DAD1C0BF2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_GT41_TEMP_SETPOINT' },
    '0DA63FE0' => { 'rtr' => '05A63FE0' , 'idx' => 1688 , 'extid' => '06A7558A6D0C57' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_GT5_DAMPING_FACTOR' },
    '0DA6BFE0' => { 'rtr' => '05A6BFE0' , 'idx' => 1690 , 'extid' => '068C603C020BDB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_HEATING_CURVE_NUMBER_OF_POINTS' },
    '0DA73FE0' => { 'rtr' => '05A73FE0' , 'idx' => 1692 , 'extid' => '00930B5D460C12' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_HEATING_SEASON_ACTIVE' },
    '0DA77FE0' => { 'rtr' => '05A77FE0' , 'idx' => 1693 , 'extid' => '00D1E8971A0BF8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_HIGHTEMP_HEATINGSYSTEM_ACTIVE' },
    '0DA7BFE0' => { 'rtr' => '05A7BFE0' , 'idx' => 1694 , 'extid' => '80C95FF0260C09' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_INTERNAL_HOLIDAY_ACTIVE' },
    '0DA7FFE0' => { 'rtr' => '05A7FFE0' , 'idx' => 1695 , 'extid' => '014E8C7DA50C0C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_INTERNAL_TIMECONTROLLED_ACTIVE' },
    '0DA83FE0' => { 'rtr' => '05A83FE0' , 'idx' => 1696 , 'extid' => '00BAEA25FC0C11' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_MAN_OP_G1' },
    '0DA87FE0' => { 'rtr' => '05A87FE0' , 'idx' => 1697 , 'extid' => '00C09E410C0C41' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_MAN_OP_VALVE_CLOSE' },
    '0DA8BFE0' => { 'rtr' => '05A8BFE0' , 'idx' => 1698 , 'extid' => '00ED44B0E30C40' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_MAN_OP_VALVE_OPEN' },
    '0DA8FFE0' => { 'rtr' => '05A8FFE0' , 'idx' => 1699 , 'extid' => '02ABF1A7610C00' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_PID_ISPOINT' },
    '0DA97FE0' => { 'rtr' => '05A97FE0' , 'idx' => 1701 , 'extid' => '028447AFD90C01' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_PID_SETPOINT' },
    '0DA9FFE0' => { 'rtr' => '05A9FFE0' , 'idx' => 1703 , 'extid' => '067BF2077E0BFB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_ROOMSENSOR_INFLUENCE' },
    '0DAA7FE0' => { 'rtr' => '05AA7FE0' , 'idx' => 1705 , 'extid' => '06DFBD330E0C05' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_ROOM_SENSOR_ACKNOW' },
    '0DAAFFE0' => { 'rtr' => '05AAFFE0' , 'idx' => 1707 , 'extid' => '064914CE5A0C0F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_ROOM_SETPOINT_TEMP_ACTIVE' },
    '0DAB7FE0' => { 'rtr' => '05AB7FE0' , 'idx' => 1709 , 'extid' => '00F7957AEF0BF7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_T1_ALARM' },
    '0DABBFE0' => { 'rtr' => '05ABBFE0' , 'idx' => 1710 , 'extid' => '06D2EA70FD0C1E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_T1_TEMP' },
    '0DAC3FE0' => { 'rtr' => '05AC3FE0' , 'idx' => 1712 , 'extid' => '069E4CB8C50C10' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_T5_ATTENUATIONED_TEMP' },
    '0DACBFE0' => { 'rtr' => '05ACBFE0' , 'idx' => 1714 , 'extid' => '0E497B32EB0C62' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'MV_E12_T5_TEMP' },
    '0DAD3FE0' => { 'rtr' => '05AD3FE0' , 'idx' => 1716 , 'extid' => '0662DE4E250C04' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_T5_TEMP_ACTIVE' },
    '0DADBFE0' => { 'rtr' => '05ADBFE0' , 'idx' => 1718 , 'extid' => '062A58E9AC0D56' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_T5_TEMP_ACTIVE_TO_DISPLAY' },
    '0DAE3FE0' => { 'rtr' => '05AE3FE0' , 'idx' => 1720 , 'extid' => '02E74CBABE0BE7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_FRI' },
    '0DAEBFE0' => { 'rtr' => '05AEBFE0' , 'idx' => 1722 , 'extid' => '028A11ACE00BDC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_MON' },
    '0DAF3FE0' => { 'rtr' => '05AF3FE0' , 'idx' => 1724 , 'extid' => '02FF48F66E0BE8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_SAT' },
    '0DAFBFE0' => { 'rtr' => '05AFBFE0' , 'idx' => 1726 , 'extid' => '022C84D8410BE9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_SUN' },
    '0DB03FE0' => { 'rtr' => '05B03FE0' , 'idx' => 1728 , 'extid' => '025CC26B340BE6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_THU' },
    '0DB0BFE0' => { 'rtr' => '05B0BFE0' , 'idx' => 1730 , 'extid' => '02BE19174C0BDE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_TUE' },
    '0DB13FE0' => { 'rtr' => '05B13FE0' , 'idx' => 1732 , 'extid' => '02819A8BD20BE5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_WED' },
    '0DB1BFE0' => { 'rtr' => '05B1BFE0' , 'idx' => 1734 , 'extid' => '063752F5180C43' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_VALVE_PID_ISPOINT' },
    '0DB23FE0' => { 'rtr' => '05B23FE0' , 'idx' => 1736 , 'extid' => '06AD02C5130C42' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_VALVE_PID_SETPOINT' },
    '0DB2BFE0' => { 'rtr' => '05B2BFE0' , 'idx' => 1738 , 'extid' => '0031A154580853' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_Q2_PRI_COOLING' },
    '0DB2FFE0' => { 'rtr' => '05B2FFE0' , 'idx' => 1739 , 'extid' => '00F81F2256091E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_Q2_SEC_COOLING' },
    '0DB33FE0' => { 'rtr' => '05B33FE0' , 'idx' => 1740 , 'extid' => '00CCBC30870767' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E31_T2_SENSOR_ALARM_GLOBAL' },
    '0DB37FE0' => { 'rtr' => '05B37FE0' , 'idx' => 1741 , 'extid' => '0A5F4B44470834' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_T31_SETPOINT' },
    '0DB3FFE0' => { 'rtr' => '05B3FFE0' , 'idx' => 1743 , 'extid' => '40C4A80D1E09E8' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_T32_ACKNOWLEDGED' },
    '0DB43FE0' => { 'rtr' => '05B43FE0' , 'idx' => 1744 , 'extid' => '40CE6501E30A32' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_CONDENSATIONGUARD_BY_EXT_GLOBAL' },
    '0DB47FE0' => { 'rtr' => '05B47FE0' , 'idx' => 1745 , 'extid' => '40B74C1B5108FB' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_COOLING_BLOCK_BY_EXT_GLOBAL' },
    '0DB4BFE0' => { 'rtr' => '05B4BFE0' , 'idx' => 1746 , 'extid' => '406C8F3A590578' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_HEATING_BLOCK_BY_EXT_GLOBAL' },
    '0DB4FFE0' => { 'rtr' => '05B4FFE0' , 'idx' => 1747 , 'extid' => '409AF7088B0A31' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_HIGH_PROTECTION_HS_BY_EXT_GLOBAL' },
    '0DB53FE0' => { 'rtr' => '05B53FE0' , 'idx' => 1748 , 'extid' => '00F33E82C3091F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_EX1_Q2_GLOBAL' },
    '0DB57FE0' => { 'rtr' => '05B57FE0' , 'idx' => 1749 , 'extid' => '014BD1F74D0A1A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_Ex_T1_ALARM_BITMASK' },
    '0DB5BFE0' => { 'rtr' => '05B5BFE0' , 'idx' => 1750 , 'extid' => '004328FEDD0A19' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_Ex_T1_ALARM_GLOBAL' },
    '0DB5FFE0' => { 'rtr' => '05B5FFE0' , 'idx' => 1751 , 'extid' => '01CEDE82B50A26' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_FREEZEGUARD_ACTIVE_BITMASK' },
    '0DB63FE0' => { 'rtr' => '05B63FE0' , 'idx' => 1752 , 'extid' => '00296DDE8F0A27' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_FREEZEGUARD_ACTIVE_GLOBAL' },
    '0DB67FE0' => { 'rtr' => '05B67FE0' , 'idx' => 1753 , 'extid' => '010C752B060A36' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HIGHTEMP_HS_ACTIVE_BITMASK' },
    '0DB6BFE0' => { 'rtr' => '05B6BFE0' , 'idx' => 1754 , 'extid' => '00553BCA330A34' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HIGHTEMP_HS_ACTIVE_GLOBAL' },
    '0DB6FFE0' => { 'rtr' => '05B6FFE0' , 'idx' => 1755 , 'extid' => '014A8CAE040D0E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HIGHTEMP_HS_ALERT_ACTIVE_BITMASK' },
    '0DB73FE0' => { 'rtr' => '05B73FE0' , 'idx' => 1756 , 'extid' => '011D09D77D0A59' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HOLIDAY_ACTIVE_BITMASK' },
    '0DB77FE0' => { 'rtr' => '05B77FE0' , 'idx' => 1757 , 'extid' => '0028CCEDE80A5A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HOLIDAY_ACTIVE_GLOBAL' },
    '0DB7BFE0' => { 'rtr' => '05B7BFE0' , 'idx' => 1758 , 'extid' => '015BDD52580D08' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ICONS_TIMEPROGRAM_ACTIVE_BITMASK' },
    '0DB7FFE0' => { 'rtr' => '05B7FFE0' , 'idx' => 1759 , 'extid' => '0095F7B1470D09' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ICONS_TIMEPROGRAM_ACTIVE_GLOBAL' },
    '0DB83FE0' => { 'rtr' => '05B83FE0' , 'idx' => 1760 , 'extid' => '00300FAB940B96' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_INVERT_EXT_INPUT_GLOBAL' },
    '0DB87FE0' => { 'rtr' => '05B87FE0' , 'idx' => 1761 , 'extid' => '0A7A3C917204D8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_1' },
    '0DB8FFE0' => { 'rtr' => '05B8FFE0' , 'idx' => 1763 , 'extid' => '0AE335C0C804D9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_2' },
    '0DB97FE0' => { 'rtr' => '05B97FE0' , 'idx' => 1765 , 'extid' => '0A9432F05E04DA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_3' },
    '0DB9FFE0' => { 'rtr' => '05B9FFE0' , 'idx' => 1767 , 'extid' => '0A0A5665FD04DB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_4' },
    '0DBA7FE0' => { 'rtr' => '05BA7FE0' , 'idx' => 1769 , 'extid' => '0A7D51556B04DC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_5' },
    '0DBAFFE0' => { 'rtr' => '05BAFFE0' , 'idx' => 1771 , 'extid' => '0AE45804D104DD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_6' },
    '0DBB7FE0' => { 'rtr' => '05BB7FE0' , 'idx' => 1773 , 'extid' => '0A935F34470830' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_7' },
    '0DBBFFE0' => { 'rtr' => '05BBFFE0' , 'idx' => 1775 , 'extid' => '6ADE74765504D6' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_GLOBAL' },
    '0DBC7FE0' => { 'rtr' => '05BC7FE0' , 'idx' => 1777 , 'extid' => '0AFDAB16F504DE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_PRI_COOLING' },
    '0DBCFFE0' => { 'rtr' => '05BCFFE0' , 'idx' => 1779 , 'extid' => '0A341560FB0909' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_SEC_COOLING' },
    '0DBD7FE0' => { 'rtr' => '05BD7FE0' , 'idx' => 1781 , 'extid' => '0AE10F410D04DF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_1' },
    '0DBDFFE0' => { 'rtr' => '05BDFFE0' , 'idx' => 1783 , 'extid' => '0A780610B704E0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_2' },
    '0DBE7FE0' => { 'rtr' => '05BE7FE0' , 'idx' => 1785 , 'extid' => '0A0F01202104E1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_3' },
    '0DBEFFE0' => { 'rtr' => '05BEFFE0' , 'idx' => 1787 , 'extid' => '0A9165B58204E2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_4' },
    '0DBF7FE0' => { 'rtr' => '05BF7FE0' , 'idx' => 1789 , 'extid' => '0AE662851404E3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_5' },
    '0DBFFFE0' => { 'rtr' => '05BFFFE0' , 'idx' => 1791 , 'extid' => '0A7F6BD4AE04E4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_6' },
    '0DC07FE0' => { 'rtr' => '05C07FE0' , 'idx' => 1793 , 'extid' => '0A086CE4380831' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_7' },
    '0DC0FFE0' => { 'rtr' => '05C0FFE0' , 'idx' => 1795 , 'extid' => '0A373AB0CA04D5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_GLOBAL' },
    '0DC17FE0' => { 'rtr' => '05C17FE0' , 'idx' => 1797 , 'extid' => '0A0863FF8104E5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_PRI_COOLING' },
    '0DC1FFE0' => { 'rtr' => '05C1FFE0' , 'idx' => 1799 , 'extid' => '0AC1DD898F090A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_SEC_COOLING' },
    '0DC27FE0' => { 'rtr' => '05C27FE0' , 'idx' => 1801 , 'extid' => '026BEA40690870' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ROOMSENSOR_KNOB_ALARM_BITMASK' },
    '0DC2FFE0' => { 'rtr' => '05C2FFE0' , 'idx' => 1803 , 'extid' => '00171A69A80871' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ROOMSENSOR_KNOB_ALARM_GLOBAL' },
    '0DC33FE0' => { 'rtr' => '05C33FE0' , 'idx' => 1804 , 'extid' => '0E587BBBF90512' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_1' },
    '0DC3BFE0' => { 'rtr' => '05C3BFE0' , 'idx' => 1806 , 'extid' => '0EC172EA430513' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_2' },
    '0DC43FE0' => { 'rtr' => '05C43FE0' , 'idx' => 1808 , 'extid' => '0EB675DAD50514' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_3' },
    '0DC4BFE0' => { 'rtr' => '05C4BFE0' , 'idx' => 1810 , 'extid' => '0E28114F760515' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_4' },
    '0DC53FE0' => { 'rtr' => '05C53FE0' , 'idx' => 1812 , 'extid' => '0E5F167FE00516' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_5' },
    '0DC5BFE0' => { 'rtr' => '05C5BFE0' , 'idx' => 1814 , 'extid' => '0EC61F2E5A0517' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_6' },
    '0DC63FE0' => { 'rtr' => '05C63FE0' , 'idx' => 1816 , 'extid' => '0EB1181ECC0518' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_7' },
    '0DC6BFE0' => { 'rtr' => '05C6BFE0' , 'idx' => 1818 , 'extid' => '0E05AA65E90511' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_GLOBAL' },
    '0DC73FE0' => { 'rtr' => '05C73FE0' , 'idx' => 1820 , 'extid' => '0E8FEB0F7F090F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_PRI_COOLING' },
    '0DC7BFE0' => { 'rtr' => '05C7BFE0' , 'idx' => 1822 , 'extid' => '0E465579710910' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_SEC_COOLING' },
    '0DC83FE0' => { 'rtr' => '05C83FE0' , 'idx' => 1824 , 'extid' => '8222C8523A0A22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 5 , 'text' => 'MV_T5_ACKNOWLEDGED_BITMASK' },
    '0DC8BFE0' => { 'rtr' => '05C8BFE0' , 'idx' => 1826 , 'extid' => '0EEAC3175104FB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 5 , 'text' => 'MV_T5_ACTUAL_1' },
    '0DC93FE0' => { 'rtr' => '05C93FE0' , 'idx' => 1828 , 'extid' => '0EC3E07A4A0D14' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_1_ROUND_OFFED' },
    '0DC9BFE0' => { 'rtr' => '05C9BFE0' , 'idx' => 1830 , 'extid' => '0E73CA46EB04FC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_2' },
    '0DCA3FE0' => { 'rtr' => '05CA3FE0' , 'idx' => 1832 , 'extid' => '0E7E2A16840D15' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_2_ROUND_OFFED' },
    '0DCABFE0' => { 'rtr' => '05CABFE0' , 'idx' => 1834 , 'extid' => '0E04CD767D04FD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_3' },
    '0DCB3FE0' => { 'rtr' => '05CB3FE0' , 'idx' => 1836 , 'extid' => '0EA3BCCF010D16' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_3_ROUND_OFFED' },
    '0DCBBFE0' => { 'rtr' => '05CBBFE0' , 'idx' => 1838 , 'extid' => '0E9AA9E3DE04FE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_4' },
    '0DCC3FE0' => { 'rtr' => '05CC3FE0' , 'idx' => 1840 , 'extid' => '0EDECFC9590D17' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_4_ROUND_OFFED' },
    '0DCCBFE0' => { 'rtr' => '05CCBFE0' , 'idx' => 1842 , 'extid' => '0EEDAED34804FF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_5' },
    '0DCD3FE0' => { 'rtr' => '05CD3FE0' , 'idx' => 1844 , 'extid' => '0E035910DC0D18' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_5_ROUND_OFFED' },
    '0DCDBFE0' => { 'rtr' => '05CDBFE0' , 'idx' => 1846 , 'extid' => '0E74A782F20500' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_6' },
    '0DCE3FE0' => { 'rtr' => '05CE3FE0' , 'idx' => 1848 , 'extid' => '0EBE937C120D19' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_6_ROUND_OFFED' },
    '0DCEBFE0' => { 'rtr' => '05CEBFE0' , 'idx' => 1850 , 'extid' => '0E03A0B2640501' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_7' },
    '0DCF3FE0' => { 'rtr' => '05CF3FE0' , 'idx' => 1852 , 'extid' => '0E6305A5970D1A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_7_ROUND_OFFED' },
    '0DCFBFE0' => { 'rtr' => '05CFBFE0' , 'idx' => 1854 , 'extid' => '0E5FFE749104D7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_GLOBAL' },
    '0DD03FE0' => { 'rtr' => '05D03FE0' , 'idx' => 1856 , 'extid' => '0E850DA7390835' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_PRI_COOLING' },
    '0DD0BFE0' => { 'rtr' => '05D0BFE0' , 'idx' => 1858 , 'extid' => '0E4CB3D137090C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_SEC_COOLING' },
    '0DD13FE0' => { 'rtr' => '05D13FE0' , 'idx' => 1860 , 'extid' => '0E345582290D66' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_1' },
    '0DD1BFE0' => { 'rtr' => '05D1BFE0' , 'idx' => 1862 , 'extid' => '0EAD5CD3930D67' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_2' },
    '0DD23FE0' => { 'rtr' => '05D23FE0' , 'idx' => 1864 , 'extid' => '0EDA5BE3050D68' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_3' },
    '0DD2BFE0' => { 'rtr' => '05D2BFE0' , 'idx' => 1866 , 'extid' => '0E443F76A60D69' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_4' },
    '0DD33FE0' => { 'rtr' => '05D33FE0' , 'idx' => 1868 , 'extid' => '0E333846300D6A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_5' },
    '0DD3BFE0' => { 'rtr' => '05D3BFE0' , 'idx' => 1870 , 'extid' => '0EAA31178A0D6B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_6' },
    '0DD43FE0' => { 'rtr' => '05D43FE0' , 'idx' => 1872 , 'extid' => '0EDD36271C0D6C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_7' },
    '0DD4BFE0' => { 'rtr' => '05D4BFE0' , 'idx' => 1874 , 'extid' => '0EF282A04A0D64' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_PRI_COOLING' },
    '0DD53FE0' => { 'rtr' => '05D53FE0' , 'idx' => 1876 , 'extid' => '0E3B3CD6440D65' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_SEC_COOLING' },
    '0DD5BFE0' => { 'rtr' => '05D5BFE0' , 'idx' => 1878 , 'extid' => '82F9B521CB0A23' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_CONNECTED_BITMASK' },
    '0DD63FE0' => { 'rtr' => '05D63FE0' , 'idx' => 1880 , 'extid' => '0E5B7D80860519' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_1' },
    '0DD6BFE0' => { 'rtr' => '05D6BFE0' , 'idx' => 1882 , 'extid' => '0EC274D13C051A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_2' },
    '0DD73FE0' => { 'rtr' => '05D73FE0' , 'idx' => 1884 , 'extid' => '0EB573E1AA051B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_3' },
    '0DD7BFE0' => { 'rtr' => '05D7BFE0' , 'idx' => 1886 , 'extid' => '0E2B177409051C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_4' },
    '0DD83FE0' => { 'rtr' => '05D83FE0' , 'idx' => 1888 , 'extid' => '0E5C10449F051D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_5' },
    '0DD8BFE0' => { 'rtr' => '05D8BFE0' , 'idx' => 1890 , 'extid' => '0EC5191525051E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_6' },
    '0DD93FE0' => { 'rtr' => '05D93FE0' , 'idx' => 1892 , 'extid' => '0EB21E25B3051F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_7' },
    '0DD9BFE0' => { 'rtr' => '05D9BFE0' , 'idx' => 1894 , 'extid' => '0EFDDE46C00D6E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_1' },
    '0DDA3FE0' => { 'rtr' => '05DA3FE0' , 'idx' => 1896 , 'extid' => '0E64D7177A0D74' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_2' },
    '0DDABFE0' => { 'rtr' => '05DABFE0' , 'idx' => 1898 , 'extid' => '0E13D027EC0D73' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_3' },
    '0DDB3FE0' => { 'rtr' => '05DB3FE0' , 'idx' => 1900 , 'extid' => '0E8DB4B24F0D72' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_4' },
    '0DDBBFE0' => { 'rtr' => '05DBBFE0' , 'idx' => 1902 , 'extid' => '0EFAB382D90D71' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_5' },
    '0DDC3FE0' => { 'rtr' => '05DC3FE0' , 'idx' => 1904 , 'extid' => '0E63BAD3630D70' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_6' },
    '0DDCBFE0' => { 'rtr' => '05DCBFE0' , 'idx' => 1906 , 'extid' => '0E14BDE3F50D6F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_7' },
    '0DDD3FE0' => { 'rtr' => '05DD3FE0' , 'idx' => 1908 , 'extid' => '0ED154A6430D77' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_GLOBAL' },
    '0DDDBFE0' => { 'rtr' => '05DDBFE0' , 'idx' => 1910 , 'extid' => '0E8B8A97610D75' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_PRI_COOLING' },
    '0DDE3FE0' => { 'rtr' => '05DE3FE0' , 'idx' => 1912 , 'extid' => '0E4234E16F0D76' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_SEC_COOLING' },
    '0DDEBFE0' => { 'rtr' => '05DEBFE0' , 'idx' => 1914 , 'extid' => '0ED34A9C7F0855' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_PRI_COOLING' },
    '0DDF3FE0' => { 'rtr' => '05DF3FE0' , 'idx' => 1916 , 'extid' => '0E1AF4EA71090D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_SEC_COOLING' },
    '0DDFBFE0' => { 'rtr' => '05DFBFE0' , 'idx' => 1918 , 'extid' => '021DD1D0B408F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_1' },
    '0DE03FE0' => { 'rtr' => '05E03FE0' , 'idx' => 1920 , 'extid' => '0284D8810E08F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_2' },
    '0DE0BFE0' => { 'rtr' => '05E0BFE0' , 'idx' => 1922 , 'extid' => '02F3DFB1980989' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_3' },
    '0DE13FE0' => { 'rtr' => '05E13FE0' , 'idx' => 1924 , 'extid' => '026DBB243B08F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_4' },
    '0DE1BFE0' => { 'rtr' => '05E1BFE0' , 'idx' => 1926 , 'extid' => '021ABC14AD098A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_5' },
    '0DE23FE0' => { 'rtr' => '05E23FE0' , 'idx' => 1928 , 'extid' => '0283B54517098B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_6' },
    '0DE2BFE0' => { 'rtr' => '05E2BFE0' , 'idx' => 1930 , 'extid' => '02F4B27581098C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_7' },
    '0DE33FE0' => { 'rtr' => '05E33FE0' , 'idx' => 1932 , 'extid' => '02100FEAE50854' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_GLOBAL' },
    '0DE3BFE0' => { 'rtr' => '05E3BFE0' , 'idx' => 1934 , 'extid' => '0217273D8C08F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_PRI_COOLING' },
    '0DE43FE0' => { 'rtr' => '05E43FE0' , 'idx' => 1936 , 'extid' => '02DE994B820905' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_SEC_COOLING' },
    '0DE4BFE0' => { 'rtr' => '05E4BFE0' , 'idx' => 1938 , 'extid' => '406AE0502C08BD' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_1' },
    '0DE4FFE0' => { 'rtr' => '05E4FFE0' , 'idx' => 1939 , 'extid' => '40F3E9019608BE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_2' },
    '0DE53FE0' => { 'rtr' => '05E53FE0' , 'idx' => 1940 , 'extid' => '4084EE310008BF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_3' },
    '0DE57FE0' => { 'rtr' => '05E57FE0' , 'idx' => 1941 , 'extid' => '401A8AA4A308C0' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_4' },
    '0DE5BFE0' => { 'rtr' => '05E5BFE0' , 'idx' => 1942 , 'extid' => '406D8D943508C1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_5' },
    '0DE5FFE0' => { 'rtr' => '05E5FFE0' , 'idx' => 1943 , 'extid' => '40F484C58F08C2' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PARTY_MODE_CIRCUIT_6' },
    '0DE63FE0' => { 'rtr' => '05E63FE0' , 'idx' => 1944 , 'extid' => '408383F51908C3' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_7' },
    '0DE67FE0' => { 'rtr' => '05E67FE0' , 'idx' => 1945 , 'extid' => '40133CE88808C4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_8' },
    '0DE6BFE0' => { 'rtr' => '05E6BFE0' , 'idx' => 1946 , 'extid' => '0059F750990920' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_GLOBAL' },
    '0DE6FFE0' => { 'rtr' => '05E6FFE0' , 'idx' => 1947 , 'extid' => '616A0C202C08CF' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_TIME' },
    '0DE73FE0' => { 'rtr' => '05E73FE0' , 'idx' => 1948 , 'extid' => 'C091347AF3003A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_ACTIVATED' },
    '0DE77FE0' => { 'rtr' => '05E77FE0' , 'idx' => 1949 , 'extid' => '00BB8F91DB00C1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CONNECTED' },
    '0DE7BFE0' => { 'rtr' => '05E7BFE0' , 'idx' => 1950 , 'extid' => 'ED6CE96123003C' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CORRECTION_L1_A' },
    '0DE7FFE0' => { 'rtr' => '05E7FFE0' , 'idx' => 1951 , 'extid' => 'ED6EAFDF7A003D' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CORRECTION_L2_A' },
    '0DE83FE0' => { 'rtr' => '05E83FE0' , 'idx' => 1952 , 'extid' => 'ED6F6DB54D003E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CORRECTION_L3_A' },
    '0DE87FE0' => { 'rtr' => '05E87FE0' , 'idx' => 1953 , 'extid' => 'E92776E2860043' , 'max' =>       10 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CURRENT_MARGIN' },
    '0DE8BFE0' => { 'rtr' => '05E8BFE0' , 'idx' => 1954 , 'extid' => '0A9F3BFEB9003F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_L1_A' },
    '0DE93FE0' => { 'rtr' => '05E93FE0' , 'idx' => 1956 , 'extid' => '0A9D7D40E00040' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_L2_A' },
    '0DE9BFE0' => { 'rtr' => '05E9BFE0' , 'idx' => 1958 , 'extid' => '0A9CBF2AD70041' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_L3_A' },
    '0DEA3FE0' => { 'rtr' => '05EA3FE0' , 'idx' => 1960 , 'extid' => 'E1D4B3F692003B' , 'max' =>       50 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_MAIN_FUSE' },
    '0DEA7FE0' => { 'rtr' => '05EA7FE0' , 'idx' => 1961 , 'extid' => 'E23E5BFE060044' , 'max' =>      600 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_RECONNECTION_TIME' },
    '0DEAFFE0' => { 'rtr' => '05EAFFE0' , 'idx' => 1963 , 'extid' => 'E2943A16910042' , 'max' =>      400 , 'min' =>      230 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_SUPPLY_VOLTAGE' },
    '0DEB7FE0' => { 'rtr' => '05EB7FE0' , 'idx' => 1965 , 'extid' => '002D1E85D10045' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED' },
    '0DEBBFE0' => { 'rtr' => '05EBBFE0' , 'idx' => 1966 , 'extid' => '00733F9A0E0046' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_PHASE1' },
    '0DEBFFE0' => { 'rtr' => '05EBFFE0' , 'idx' => 1967 , 'extid' => '00EA36CBB40047' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_PHASE2' },
    '0DEC3FE0' => { 'rtr' => '05EC3FE0' , 'idx' => 1968 , 'extid' => '009D31FB220048' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_PHASE3' },
    '0DEC7FE0' => { 'rtr' => '05EC7FE0' , 'idx' => 1969 , 'extid' => 'E25CA4C19F0049' , 'max' =>      300 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_TIME' },
    '0DECFFE0' => { 'rtr' => '05ECFFE0' , 'idx' => 1971 , 'extid' => '12C6A967E500C2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_VERSION' },
    '0DED7FE0' => { 'rtr' => '05ED7FE0' , 'idx' => 1973 , 'extid' => 'C0CBCCD18A0957' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PHASE_DETECTOR_ACKNOWLEDGED' },
    '0DEDBFE0' => { 'rtr' => '05EDBFE0' , 'idx' => 1974 , 'extid' => 'C084955BAB0958' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PHASE_DETECTOR_ACKNOWLEDGED_2' },
    '0DEDFFE0' => { 'rtr' => '05EDFFE0' , 'idx' => 1975 , 'extid' => 'C0DC2828E804BE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_ACTIVE' },
    '0DEE3FE0' => { 'rtr' => '05EE3FE0' , 'idx' => 1976 , 'extid' => 'C08C59297F0A02' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_BLOCKED_BY_EXT' },
    '0DEE7FE0' => { 'rtr' => '05EE7FE0' , 'idx' => 1977 , 'extid' => 'E18194411004C1' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_CONST' },
    '0DEEBFE0' => { 'rtr' => '05EEBFE0' , 'idx' => 1978 , 'extid' => 'E1FF34E027068D' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_CONST_2' },
    '0DEEFFE0' => { 'rtr' => '05EEFFE0' , 'idx' => 1979 , 'extid' => 'ED3DDCC31204BF' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MAX' },
    '0DEF3FE0' => { 'rtr' => '05EF3FE0' , 'idx' => 1980 , 'extid' => 'EDCEB4DCE1068E' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MAX_2' },
    '0DEF7FE0' => { 'rtr' => '05EF7FE0' , 'idx' => 1981 , 'extid' => 'ED01D1FC4B04C0' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MIN' },
    '0DEFBFE0' => { 'rtr' => '05EFBFE0' , 'idx' => 1982 , 'extid' => 'ED13AB2BCC068F' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MIN_2' },
    '0DEFFFE0' => { 'rtr' => '05EFFFE0' , 'idx' => 1983 , 'extid' => '00510392C90A03' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_EXTERN_BLOCKED' },
    '0DF03FE0' => { 'rtr' => '05F03FE0' , 'idx' => 1984 , 'extid' => '80D0ADB7850B9C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_EXT_INPUT_INV' },
    '0DF07FE0' => { 'rtr' => '05F07FE0' , 'idx' => 1985 , 'extid' => 'EA30756EF404C3' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_D' },
    '0DF0FFE0' => { 'rtr' => '05F0FFE0' , 'idx' => 1987 , 'extid' => 'EA4EC4124904C4' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_I' },
    '0DF17FE0' => { 'rtr' => '05F17FE0' , 'idx' => 1989 , 'extid' => 'E61800D661054D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_MAX' },
    '0DF1FFE0' => { 'rtr' => '05F1FFE0' , 'idx' => 1991 , 'extid' => 'E6240DE938054E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_MIN' },
    '0DF27FE0' => { 'rtr' => '05F27FE0' , 'idx' => 1993 , 'extid' => 'EA2AAFBA8904C5' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_P' },
    '0DF2FFE0' => { 'rtr' => '05F2FFE0' , 'idx' => 1995 , 'extid' => '0040B192E504C2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_REQUEST' },
    '0DF33FE0' => { 'rtr' => '05F33FE0' , 'idx' => 1996 , 'extid' => '008925B7940679' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_REQUEST_2' },
    '0DF37FE0' => { 'rtr' => '05F37FE0' , 'idx' => 1997 , 'extid' => 'EE4914843A04BD' , 'max' =>      400 , 'min' =>       40 , 'format' => 'tem' , 'read' => 0 , 'text' => 'POOL_SETPOINT_TEMP' },
    '0DF3FFE0' => { 'rtr' => '05F3FFE0' , 'idx' => 1999 , 'extid' => 'E161A234AF0A24' , 'max' =>      240 , 'min' =>       15 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_START_DELAY_TIME' },
    '0DF43FE0' => { 'rtr' => '05F43FE0' , 'idx' => 2000 , 'extid' => '0E178B819A0D1C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'POOL_START_TEMP' },
    '0DF4BFE0' => { 'rtr' => '05F4BFE0' , 'idx' => 2002 , 'extid' => '063848EA380D1D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_STOP_TEMP' },
    '0DF53FE0' => { 'rtr' => '05F53FE0' , 'idx' => 2004 , 'extid' => 'C07A64C1EC0827' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_USE_COMPRESSOR_1' },
    '0DF57FE0' => { 'rtr' => '05F57FE0' , 'idx' => 2005 , 'extid' => 'C0E36D90560826' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_USE_COMPRESSOR_2' },
    '0DF5BFE0' => { 'rtr' => '05F5BFE0' , 'idx' => 2006 , 'extid' => 'E114ED4791054F' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_VALVE_DELAY_AFTER_DEFROST' },
    '0DF5FFE0' => { 'rtr' => '05F5FFE0' , 'idx' => 2007 , 'extid' => 'EA2ACC5E79075D' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_VALVE_POSITION' },
    '0DF67FE0' => { 'rtr' => '05F67FE0' , 'idx' => 2009 , 'extid' => 'E210798BA3054C' , 'max' =>     6000 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_VALVE_RUNNING_TIME' },
    '0DF6FFE0' => { 'rtr' => '05F6FFE0' , 'idx' => 2011 , 'extid' => '019A57F78D089A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POPUP_WINDOW_DELAY' },
    '0DF73FE0' => { 'rtr' => '05F73FE0' , 'idx' => 2012 , 'extid' => '0144B7AB4C01CA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PROGRAM_GENERATION' },
    '0DF77FE0' => { 'rtr' => '05F77FE0' , 'idx' => 2013 , 'extid' => '011A75548400C3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PROGRAM_REVISION' },
    '0DF7BFE0' => { 'rtr' => '05F7BFE0' , 'idx' => 2014 , 'extid' => '02AE6D0DE200C4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PROGRAM_VERSION' },
    '0DF83FE0' => { 'rtr' => '05F83FE0' , 'idx' => 2016 , 'extid' => 'C0A53F3F7D02FE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PUMP_DHW_ACTIVE' },
    '0DF87FE0' => { 'rtr' => '05F87FE0' , 'idx' => 2017 , 'extid' => 'E193B840CB0774' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM1_START_TIME' },
    '0DF8BFE0' => { 'rtr' => '05F8BFE0' , 'idx' => 2018 , 'extid' => 'E17DBA37BD0775' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM1_STOP_TIME' },
    '0DF8FFE0' => { 'rtr' => '05F8FFE0' , 'idx' => 2019 , 'extid' => 'E1E426923B0776' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM2_START_TIME' },
    '0DF93FE0' => { 'rtr' => '05F93FE0' , 'idx' => 2020 , 'extid' => 'E1E45851BC0777' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM2_STOP_TIME' },
    '0DF97FE0' => { 'rtr' => '05F97FE0' , 'idx' => 2021 , 'extid' => 'E17F83DE540778' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM3_START_TIME' },
    '0DF9BFE0' => { 'rtr' => '05F9BFE0' , 'idx' => 2022 , 'extid' => 'E125D68E7C0779' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM3_STOP_TIME' },
    '0DF9FFE0' => { 'rtr' => '05F9FFE0' , 'idx' => 2023 , 'extid' => 'E10B1B37DB077A' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM4_START_TIME' },
    '0DFA3FE0' => { 'rtr' => '05FA3FE0' , 'idx' => 2024 , 'extid' => 'E10CED9BFF077B' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM4_STOP_TIME' },
    '0DFA7FE0' => { 'rtr' => '05FA7FE0' , 'idx' => 2025 , 'extid' => 'C05AF5405A09A2' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_BLOCKED_BY_EXT' },
    '0DFABFE0' => { 'rtr' => '05FABFE0' , 'idx' => 2026 , 'extid' => 'E1612C0C7E066A' , 'max' =>       20 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_START_DIFF' },
    '0DFAFFE0' => { 'rtr' => '05FAFFE0' , 'idx' => 2027 , 'extid' => 'C0B3960C7E0669' , 'max' => 33554432 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_START_MODE' },
    '0DFB3FE0' => { 'rtr' => '05FB3FE0' , 'idx' => 2028 , 'extid' => 'E12F0FCE1F066B' , 'max' =>       90 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_START_TEMP' },
    '0DFB7FE0' => { 'rtr' => '05FB7FE0' , 'idx' => 2029 , 'extid' => 'C0F55C0D9009A3' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_BLOCKED_BY_EXT' },
    '0DFBBFE0' => { 'rtr' => '05FBBFE0' , 'idx' => 2030 , 'extid' => 'E148E4B88C07D2' , 'max' =>       20 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_START_DIFF' },
    '0DFBFFE0' => { 'rtr' => '05FBFFE0' , 'idx' => 2031 , 'extid' => 'C09A5EB88C07D1' , 'max' => 33554432 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_START_MODE' },
    '0DFC3FE0' => { 'rtr' => '05FC3FE0' , 'idx' => 2032 , 'extid' => 'E106C77AED07D3' , 'max' =>       90 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_START_TEMP' },
    '0DFC7FE0' => { 'rtr' => '05FC7FE0' , 'idx' => 2033 , 'extid' => 'C0AD220E5C0341' , 'max' =>134217728 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G1_CONTINUAL' },
    '0DFCBFE0' => { 'rtr' => '05FCBFE0' , 'idx' => 2034 , 'extid' => 'C034C0685D02FA' , 'max' =>134217728 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_CONTINUAL' },
    '0DFCFFE0' => { 'rtr' => '05FCFFE0' , 'idx' => 2035 , 'extid' => 'E1C0D22EBB02FC' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_LOW_TEMPERATURE' },
    '0DFD3FE0' => { 'rtr' => '05FD3FE0' , 'idx' => 2036 , 'extid' => 'E195C275E60565' , 'max' =>       99 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_MAX_TEMPERATURE' },
    '0DFD7FE0' => { 'rtr' => '05FD7FE0' , 'idx' => 2037 , 'extid' => 'C0C820AFFD0981' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_ACTIVE_IN_COOLING' },
    '0DFDBFE0' => { 'rtr' => '05FDBFE0' , 'idx' => 2038 , 'extid' => 'C0F54EB79D02FB' , 'max' =>134217728 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_CONTINUAL' },
    '0DFDFFE0' => { 'rtr' => '05FDFFE0' , 'idx' => 2039 , 'extid' => 'C04997E841030D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E21_EXT_1' },
    '0DFE3FE0' => { 'rtr' => '05FE3FE0' , 'idx' => 2040 , 'extid' => 'C0D09EB9FB0490' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E21_EXT_2' },
    '0DFE7FE0' => { 'rtr' => '05FE7FE0' , 'idx' => 2041 , 'extid' => 'C0787FF2DC0B58' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E22_EXT_1' },
    '0DFEBFE0' => { 'rtr' => '05FEBFE0' , 'idx' => 2042 , 'extid' => 'C0E176A3660B57' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E22_EXT_2' },
    '0DFEFFE0' => { 'rtr' => '05FEFFE0' , 'idx' => 2043 , 'extid' => '0088C4B29B0301' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVE' },
    '0DFF3FE0' => { 'rtr' => '05FF3FE0' , 'idx' => 2044 , 'extid' => 'C06FE120A603ED' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E21_EXT_1' },
    '0DFF7FE0' => { 'rtr' => '05FF7FE0' , 'idx' => 2045 , 'extid' => 'C0F6E8711C0491' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E21_EXT_2' },
    '0DFFBFE0' => { 'rtr' => '05FFBFE0' , 'idx' => 2046 , 'extid' => 'C05E093A3B0B59' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E22_EXT_1' },
    '0DFFFFE0' => { 'rtr' => '05FFFFE0' , 'idx' => 2047 , 'extid' => 'C0C7006B810B5A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E22_EXT_2' },
    '0E003FE0' => { 'rtr' => '06003FE0' , 'idx' => 2048 , 'extid' => '00E7008FF203EC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVE' },
    '0E007FE0' => { 'rtr' => '06007FE0' , 'idx' => 2049 , 'extid' => 'E10F14FDE50052' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MAX_HASTIGHET' },
    '0E00BFE0' => { 'rtr' => '0600BFE0' , 'idx' => 2050 , 'extid' => 'C1AA37C2AE0053' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MAX_SPEED_AT_COMPRESSOR_FREQUENCY' },
    '0E00FFE0' => { 'rtr' => '0600FFE0' , 'idx' => 2051 , 'extid' => 'C14F5B85930054' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MIN_HASTIGHET' },
    '0E013FE0' => { 'rtr' => '06013FE0' , 'idx' => 2052 , 'extid' => 'C1810D090C0055' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MIN_SPEED_AT_COMPRESSOR_FREQUENCY' },
    '0E017FE0' => { 'rtr' => '06017FE0' , 'idx' => 2053 , 'extid' => '00BC04CC910170' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'REMOTE_GET_DISPLAY' },
    '0E01BFE0' => { 'rtr' => '0601BFE0' , 'idx' => 2054 , 'extid' => '401844310700E2' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_LARMHISTORY' },
    '0E01FFE0' => { 'rtr' => '0601FFE0' , 'idx' => 2055 , 'extid' => '40E7A15E1F0B0F' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_LARMINFO' },
    '0E023FE0' => { 'rtr' => '06023FE0' , 'idx' => 2056 , 'extid' => '407ECEAB5B00E3' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_LARMLOG' },
    '0E027FE0' => { 'rtr' => '06027FE0' , 'idx' => 2057 , 'extid' => '40ACCAC30100E4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_SYSVAR' },
    '0E02BFE0' => { 'rtr' => '0602BFE0' , 'idx' => 2058 , 'extid' => '0005DE7D17035C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESTART_ADDITIONAL_TIMER_BLOCKED' },
    '0E02FFE0' => { 'rtr' => '0602FFE0' , 'idx' => 2059 , 'extid' => '00C84276310169' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RIGGKORNING' },
    '0E033FE0' => { 'rtr' => '06033FE0' , 'idx' => 2060 , 'extid' => '00C5942E8000E7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_BLOCK' },
    '0E037FE0' => { 'rtr' => '06037FE0' , 'idx' => 2061 , 'extid' => 'C0F28707F00243' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_BUZZER_BLOCKED' },
    '0E03BFE0' => { 'rtr' => '0603BFE0' , 'idx' => 2062 , 'extid' => 'E1E543D41F00EB' , 'max' =>        6 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_DIAL_RANGE' },
    '0E03FFE0' => { 'rtr' => '0603FFE0' , 'idx' => 2063 , 'extid' => '6107058A0B03CD' , 'max' =>        6 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_DIAL_RANGE_GLOBAL' },
    '0E043FE0' => { 'rtr' => '06043FE0' , 'idx' => 2064 , 'extid' => 'EE3FBC687F0580' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E21_EXT_1' },
    '0E04BFE0' => { 'rtr' => '0604BFE0' , 'idx' => 2066 , 'extid' => 'EEA6B539C50581' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E21_EXT_2' },
    '0E053FE0' => { 'rtr' => '06053FE0' , 'idx' => 2068 , 'extid' => 'EE0E5472E20B54' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E22_EXT_1' },
    '0E05BFE0' => { 'rtr' => '0605BFE0' , 'idx' => 2070 , 'extid' => 'EE975D23580B53' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E22_EXT_2' },
    '0E063FE0' => { 'rtr' => '06063FE0' , 'idx' => 2072 , 'extid' => '6E3FCBFD6C03CE' , 'max' =>      350 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_GLOBAL' },
    '0E06BFE0' => { 'rtr' => '0606BFE0' , 'idx' => 2074 , 'extid' => '003F4C64300307' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_1' },
    '0E06FFE0' => { 'rtr' => '0606FFE0' , 'idx' => 2075 , 'extid' => '00A645358A0582' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_2' },
    '0E073FE0' => { 'rtr' => '06073FE0' , 'idx' => 2076 , 'extid' => '00D142051C0B5D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_3' },
    '0E077FE0' => { 'rtr' => '06077FE0' , 'idx' => 2077 , 'extid' => '004F2690BF0B5E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_4' },
    '0E07BFE0' => { 'rtr' => '0607BFE0' , 'idx' => 2078 , 'extid' => 'EE68497B9C0782' , 'max' =>      350 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ROOM_HOLIDAY_SETPOINT_BASE_TEMP' },
    '0E083FE0' => { 'rtr' => '06083FE0' , 'idx' => 2080 , 'extid' => '6E0332AF180783' , 'max' =>      350 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_HOLIDAY_SETPOINT_BASE_TEMP_GLOBAL' },
    '0E08BFE0' => { 'rtr' => '0608BFE0' , 'idx' => 2082 , 'extid' => '0E70AF9DB500E9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_INFLUENCE' },
    '0E093FE0' => { 'rtr' => '06093FE0' , 'idx' => 2084 , 'extid' => 'E935C24AA700EA' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_INFLUENCE_CONST' },
    '0E097FE0' => { 'rtr' => '06097FE0' , 'idx' => 2085 , 'extid' => '699921DC4403CC' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_INFLUENCE_CONST_GLOBAL' },
    '0E09BFE0' => { 'rtr' => '0609BFE0' , 'idx' => 2086 , 'extid' => '406435D2B50CEF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_LED_ALLOWED' },
    '0E09FFE0' => { 'rtr' => '0609FFE0' , 'idx' => 2087 , 'extid' => 'C04D975754077C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_LED_BLOCKED' },
    '0E0A3FE0' => { 'rtr' => '060A3FE0' , 'idx' => 2088 , 'extid' => 'C2F7E587150294' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_5FRI' },
    '0E0ABFE0' => { 'rtr' => '060ABFE0' , 'idx' => 2090 , 'extid' => 'C29AB8914B028F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_1MON' },
    '0E0B3FE0' => { 'rtr' => '060B3FE0' , 'idx' => 2092 , 'extid' => 'C2EFE1CBC50296' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_6SAT' },
    '0E0BBFE0' => { 'rtr' => '060BBFE0' , 'idx' => 2094 , 'extid' => 'C23C2DE5EA0298' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_7SUN' },
    '0E0C3FE0' => { 'rtr' => '060C3FE0' , 'idx' => 2096 , 'extid' => 'C24C6B569F0293' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_4THU' },
    '0E0CBFE0' => { 'rtr' => '060CBFE0' , 'idx' => 2098 , 'extid' => 'C2AEB02AE70290' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_2TUE' },
    '0E0D3FE0' => { 'rtr' => '060D3FE0' , 'idx' => 2100 , 'extid' => 'C29133B6790291' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_3WED' },
    '0E0DBFE0' => { 'rtr' => '060DBFE0' , 'idx' => 2102 , 'extid' => 'C2B045FDC50295' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_5FRI' },
    '0E0E3FE0' => { 'rtr' => '060E3FE0' , 'idx' => 2104 , 'extid' => 'C2DD18EB9B0299' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_1MON' },
    '0E0EBFE0' => { 'rtr' => '060EBFE0' , 'idx' => 2106 , 'extid' => 'C2A841B1150297' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_6SAT' },
    '0E0F3FE0' => { 'rtr' => '060F3FE0' , 'idx' => 2108 , 'extid' => 'C27B8D9F3A029C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_7SUN' },
    '0E0FBFE0' => { 'rtr' => '060FBFE0' , 'idx' => 2110 , 'extid' => 'C20BCB2C4F029B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_4THU' },
    '0E103FE0' => { 'rtr' => '06103FE0' , 'idx' => 2112 , 'extid' => 'C2E9105037029A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_2TUE' },
    '0E10BFE0' => { 'rtr' => '0610BFE0' , 'idx' => 2114 , 'extid' => 'C2D693CCA90292' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_3WED' },
    '0E113FE0' => { 'rtr' => '06113FE0' , 'idx' => 2116 , 'extid' => '42363DB8840611' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_FRI_GLOBAL' },
    '0E11BFE0' => { 'rtr' => '0611BFE0' , 'idx' => 2118 , 'extid' => 'E1049063EA0464' , 'max' =>        3 , 'min' =>        0 , 'format' => 'rp2' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_MODE' },
    '0E11FFE0' => { 'rtr' => '0611FFE0' , 'idx' => 2119 , 'extid' => '61961A9F6C07C5' , 'max' =>        3 , 'min' =>        0 , 'format' => 'rp2' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_MODE_GLOBAL' },
    '0E123FE0' => { 'rtr' => '06123FE0' , 'idx' => 2120 , 'extid' => '429997EF4C0614' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_MON_GLOBAL' },
    '0E12BFE0' => { 'rtr' => '0612BFE0' , 'idx' => 2122 , 'extid' => '428549A8660612' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_SAT_GLOBAL' },
    '0E133FE0' => { 'rtr' => '06133FE0' , 'idx' => 2124 , 'extid' => '42991E96F80613' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_SUN_GLOBAL' },
    '0E13BFE0' => { 'rtr' => '0613BFE0' , 'idx' => 2126 , 'extid' => '42079C05DA0617' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_THU_GLOBAL' },
    '0E143FE0' => { 'rtr' => '06143FE0' , 'idx' => 2128 , 'extid' => '4226A891D70615' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_TUE_GLOBAL' },
    '0E14BFE0' => { 'rtr' => '0614BFE0' , 'idx' => 2130 , 'extid' => '42ADF5683B0616' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_WED_GLOBAL' },
    '0E153FE0' => { 'rtr' => '06153FE0' , 'idx' => 2132 , 'extid' => '80863E34500CC4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_SENSOR_SHOW_OUTDOOR_TEMP' },
    '0E157FE0' => { 'rtr' => '06157FE0' , 'idx' => 2133 , 'extid' => 'EE6446CFDB00E8' , 'max' =>      350 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ROOM_SETPOINT_BASE_TEMP' },
    '0E15FFE0' => { 'rtr' => '0615FFE0' , 'idx' => 2135 , 'extid' => '6ECB439DE5046E' , 'max' =>      350 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_SETPOINT_BASE_TEMP_GLOBAL' },
    '0E167FE0' => { 'rtr' => '06167FE0' , 'idx' => 2137 , 'extid' => '0ED933E0190188' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_SETPOINT_OFFSET' },
    '0E16FFE0' => { 'rtr' => '0616FFE0' , 'idx' => 2139 , 'extid' => '0EB8115D5C0470' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_SETPOINT_OFFSET_GLOBAL' },
    '0E177FE0' => { 'rtr' => '06177FE0' , 'idx' => 2141 , 'extid' => '0EF53B34510189' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ROOM_SETPOINT_TEMP' },
    '0E17FFE0' => { 'rtr' => '0617FFE0' , 'idx' => 2143 , 'extid' => '0087BA736D026A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_TIMECONTROLLED' },
    '0E183FE0' => { 'rtr' => '06183FE0' , 'idx' => 2144 , 'extid' => 'E14AFE95E8029D' , 'max' =>        6 , 'min' =>        0 , 'format' => 'rp1' , 'read' => 1 , 'text' => 'ROOM_TIMEPROGRAM' },
    '0E187FE0' => { 'rtr' => '06187FE0' , 'idx' => 2145 , 'extid' => 'EE8DE6431B046A' , 'max' =>      300 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_TIMEPROGRAMMED_SETPOINT_BASE_TEMP' },
    '0E18FFE0' => { 'rtr' => '0618FFE0' , 'idx' => 2147 , 'extid' => '6EB57C47E9046F' , 'max' =>      300 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_TIMEPROGRAMMED_SETPOINT_BASE_TEMP_GLOBAL' },
    '0E197FE0' => { 'rtr' => '06197FE0' , 'idx' => 2149 , 'extid' => '619F8792630618' , 'max' =>        6 , 'min' =>        0 , 'format' => 'rp1' , 'read' => 0 , 'text' => 'ROOM_TIMEPROGRAM_GLOBAL' },
    '0E19BFE0' => { 'rtr' => '0619BFE0' , 'idx' => 2150 , 'extid' => '01032AAD1F00E5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED' },
    '0E19FFE0' => { 'rtr' => '0619FFE0' , 'idx' => 2151 , 'extid' => '01D110D005044E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_2' },
    '0E1A3FE0' => { 'rtr' => '061A3FE0' , 'idx' => 2152 , 'extid' => '01A617E093044F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_3' },
    '0E1A7FE0' => { 'rtr' => '061A7FE0' , 'idx' => 2153 , 'extid' => '01387375300450' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_4' },
    '0E1ABFE0' => { 'rtr' => '061ABFE0' , 'idx' => 2154 , 'extid' => '014F7445A60451' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_5' },
    '0E1AFFE0' => { 'rtr' => '061AFFE0' , 'idx' => 2155 , 'extid' => '01D67D141C0452' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_6' },
    '0E1B3FE0' => { 'rtr' => '061B3FE0' , 'idx' => 2156 , 'extid' => '01A17A248A0453' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_7' },
    '0E1B7FE0' => { 'rtr' => '061B7FE0' , 'idx' => 2157 , 'extid' => '0131C5391B0454' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_8' },
    '0E1BBFE0' => { 'rtr' => '061BBFE0' , 'idx' => 2158 , 'extid' => '81D5BA54CD063B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_BITMASK' },
    '0E1BFFE0' => { 'rtr' => '061BFFE0' , 'idx' => 2159 , 'extid' => '014C1EDDDA056F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_GLOBAL' },
    '0E1C3FE0' => { 'rtr' => '061C3FE0' , 'idx' => 2160 , 'extid' => '01DE529BB00CDC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION' },
    '0E1C7FE0' => { 'rtr' => '061C7FE0' , 'idx' => 2161 , 'extid' => '01373538C20CDE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_2' },
    '0E1CBFE0' => { 'rtr' => '061CBFE0' , 'idx' => 2162 , 'extid' => '01403208540CE0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_3' },
    '0E1CFFE0' => { 'rtr' => '061CFFE0' , 'idx' => 2163 , 'extid' => '01DE569DF70CE2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_4' },
    '0E1D3FE0' => { 'rtr' => '061D3FE0' , 'idx' => 2164 , 'extid' => '01A951AD610CE4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_5' },
    '0E1D7FE0' => { 'rtr' => '061D7FE0' , 'idx' => 2165 , 'extid' => '013058FCDB0CE6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_6' },
    '0E1DBFE0' => { 'rtr' => '061DBFE0' , 'idx' => 2166 , 'extid' => '01475FCC4D0CE9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_7' },
    '0E1DFFE0' => { 'rtr' => '061DFFE0' , 'idx' => 2167 , 'extid' => '01D7E0D1DC0CEB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_8' },
    '0E1E3FE0' => { 'rtr' => '061E3FE0' , 'idx' => 2168 , 'extid' => '019CE0CE7A0CDD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION' },
    '0E1E7FE0' => { 'rtr' => '061E7FE0' , 'idx' => 2169 , 'extid' => '011D21E0CF0CDF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_2' },
    '0E1EBFE0' => { 'rtr' => '061EBFE0' , 'idx' => 2170 , 'extid' => '016A26D0590CE1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_3' },
    '0E1EFFE0' => { 'rtr' => '061EFFE0' , 'idx' => 2171 , 'extid' => '01F44245FA0CE3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_4' },
    '0E1F3FE0' => { 'rtr' => '061F3FE0' , 'idx' => 2172 , 'extid' => '018345756C0CE5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_5' },
    '0E1F7FE0' => { 'rtr' => '061F7FE0' , 'idx' => 2173 , 'extid' => '011A4C24D60CE7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_6' },
    '0E1FBFE0' => { 'rtr' => '061FBFE0' , 'idx' => 2174 , 'extid' => '016D4B14400CE8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_7' },
    '0E1FFFE0' => { 'rtr' => '061FFFE0' , 'idx' => 2175 , 'extid' => '01FDF409D10CEA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_8' },
    '0E203FE0' => { 'rtr' => '06203FE0' , 'idx' => 2176 , 'extid' => '00556417180C63' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_SUPPORTS_NEW_MESSAGES' },
    '0E207FE0' => { 'rtr' => '06207FE0' , 'idx' => 2177 , 'extid' => '01D97B1C4D0D0A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_SUPPORTS_NEW_MESSAGES_BITMASK' },
    '0E20BFE0' => { 'rtr' => '0620BFE0' , 'idx' => 2178 , 'extid' => '01D3619DF80C64' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_SYSTEM_STATUS' },
    '0E20FFE0' => { 'rtr' => '0620FFE0' , 'idx' => 2179 , 'extid' => '01E825273200E6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION' },
    '0E213FE0' => { 'rtr' => '06213FE0' , 'idx' => 2180 , 'extid' => '01FC570BDB0455' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_2' },
    '0E217FE0' => { 'rtr' => '06217FE0' , 'idx' => 2181 , 'extid' => '018B503B4D0456' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_3' },
    '0E21BFE0' => { 'rtr' => '0621BFE0' , 'idx' => 2182 , 'extid' => '011534AEEE0457' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_4' },
    '0E21FFE0' => { 'rtr' => '0621FFE0' , 'idx' => 2183 , 'extid' => '0162339E780458' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_5' },
    '0E223FE0' => { 'rtr' => '06223FE0' , 'idx' => 2184 , 'extid' => '01FB3ACFC20459' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_6' },
    '0E227FE0' => { 'rtr' => '06227FE0' , 'idx' => 2185 , 'extid' => '018C3DFF54045A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_7' },
    '0E22BFE0' => { 'rtr' => '0622BFE0' , 'idx' => 2186 , 'extid' => '011C82E2C5045B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_8' },
    '0E22FFE0' => { 'rtr' => '0622FFE0' , 'idx' => 2187 , 'extid' => 'C06BA627980538' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_ACTIVATED' },
    '0E233FE0' => { 'rtr' => '06233FE0' , 'idx' => 2188 , 'extid' => '02FC92B4A40665' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_COOLING_STEP_COUNT' },
    '0E23BFE0' => { 'rtr' => '0623BFE0' , 'idx' => 2190 , 'extid' => 'C13D579DFB0668' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_CURRENT_HOUR' },
    '0E23FFE0' => { 'rtr' => '0623FFE0' , 'idx' => 2191 , 'extid' => 'C21039876A053F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_CURRENT_PROGRAM_STEP' },
    '0E247FE0' => { 'rtr' => '06247FE0' , 'idx' => 2193 , 'extid' => 'E1A4D2CE57053E' , 'max' =>       20 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_DAYS_AT_MAX_TEMPERATURE' },
    '0E24BFE0' => { 'rtr' => '0624BFE0' , 'idx' => 2194 , 'extid' => 'E1872A8838053C' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_DAYS_PER_COOLING_STEP' },
    '0E24FFE0' => { 'rtr' => '0624FFE0' , 'idx' => 2195 , 'extid' => 'E11DC6A468053B' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_DAYS_PER_HEATING_STEP' },
    '0E253FE0' => { 'rtr' => '06253FE0' , 'idx' => 2196 , 'extid' => '029800BDF00666' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_HEATING_STEP_COUNT' },
    '0E25BFE0' => { 'rtr' => '0625BFE0' , 'idx' => 2198 , 'extid' => 'E17317C0720A89' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_HEAT_SOURCE' },
    '0E25FFE0' => { 'rtr' => '0625FFE0' , 'idx' => 2199 , 'extid' => 'C036C36C230764' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_INCOMPLETE' },
    '0E263FE0' => { 'rtr' => '06263FE0' , 'idx' => 2200 , 'extid' => 'EE85AEC727053D' , 'max' =>      600 , 'min' =>      250 , 'format' => 'tem' , 'read' => 0 , 'text' => 'SCREED_DRYING_MAX_TEMPERATURE' },
    '0E26BFE0' => { 'rtr' => '0626BFE0' , 'idx' => 2202 , 'extid' => '020761939A0649' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_PROGRAM_STEP_COUNT' },
    '0E273FE0' => { 'rtr' => '06273FE0' , 'idx' => 2204 , 'extid' => '0CF05D8A3C0537' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_REQUEST' },
    '0E277FE0' => { 'rtr' => '06277FE0' , 'idx' => 2205 , 'extid' => '0E7542150E0536' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'SCREED_DRYING_SETPOINT_TEMP' },
    '0E27FFE0' => { 'rtr' => '0627FFE0' , 'idx' => 2207 , 'extid' => 'E980506DE3053A' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_TEMPERATURE_STEP_COOLING' },
    '0E283FE0' => { 'rtr' => '06283FE0' , 'idx' => 2208 , 'extid' => 'E90951DB6E0539' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_TEMPERATURE_STEP_HEATING' },
    '0E287FE0' => { 'rtr' => '06287FE0' , 'idx' => 2209 , 'extid' => '00970D250700A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREENSAVER_ACTIVE' },
    '0E28BFE0' => { 'rtr' => '0628BFE0' , 'idx' => 2210 , 'extid' => 'E1F3115A2800A8' , 'max' =>      240 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREENSAVER_DELAY_TIME' },
    '0E28FFE0' => { 'rtr' => '0628FFE0' , 'idx' => 2211 , 'extid' => 'ED0EEADA7F0AB9' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T1_CORRECTION' },
    '0E293FE0' => { 'rtr' => '06293FE0' , 'idx' => 2212 , 'extid' => '0EAC7E06AF0AB2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T1_DISPLAY_TEMP' },
    '0E29BFE0' => { 'rtr' => '0629BFE0' , 'idx' => 2214 , 'extid' => '009F37E8480AB3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T1_STATUS' },
    '0E29FFE0' => { 'rtr' => '0629FFE0' , 'idx' => 2215 , 'extid' => '0E4ABFEB090AB4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T1_TEMP' },
    '0E2A7FE0' => { 'rtr' => '062A7FE0' , 'idx' => 2217 , 'extid' => 'EDE2D144E00AB5' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T3_CORRECTION' },
    '0E2ABFE0' => { 'rtr' => '062ABFE0' , 'idx' => 2218 , 'extid' => '0E4D10C2020AB6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T3_DISPLAY_TEMP' },
    '0E2B3FE0' => { 'rtr' => '062B3FE0' , 'idx' => 2220 , 'extid' => '00DD12EF350AB7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T3_STATUS' },
    '0E2B7FE0' => { 'rtr' => '062B7FE0' , 'idx' => 2221 , 'extid' => '0E07774A020AB8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T3_TEMP' },
    '0E2BFFE0' => { 'rtr' => '062BFFE0' , 'idx' => 2223 , 'extid' => 'EDE1D77F9F0AAE' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T7_CORRECTION' },
    '0E2C3FE0' => { 'rtr' => '062C3FE0' , 'idx' => 2224 , 'extid' => '0E54BC4D190AAF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T7_DISPLAY_TEMP' },
    '0E2CBFE0' => { 'rtr' => '062CBFE0' , 'idx' => 2226 , 'extid' => '005958E1CF0AB0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T7_STATUS' },
    '0E2CFFE0' => { 'rtr' => '062CFFE0' , 'idx' => 2227 , 'extid' => '0E9CE608140AB1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T7_TEMP' },
    '0E2D7FE0' => { 'rtr' => '062D7FE0' , 'idx' => 2229 , 'extid' => 'C048543205094C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SETUP_COMPLETED' },
    '0E2DBFE0' => { 'rtr' => '062DBFE0' , 'idx' => 2230 , 'extid' => 'C029E15D980AFE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_ACTIVATED' },
    '0E2DFFE0' => { 'rtr' => '062DFFE0' , 'idx' => 2231 , 'extid' => '00F055A4120A8E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_ACTIVE' },
    '0E2E3FE0' => { 'rtr' => '062E3FE0' , 'idx' => 2232 , 'extid' => '006BE7E0830A95' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_DHW_BLOCK' },
    '0E2E7FE0' => { 'rtr' => '062E7FE0' , 'idx' => 2233 , 'extid' => 'E977D8E0F20A8F' , 'max' =>      200 , 'min' =>       70 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_DIFF_START_TEMP' },
    '0E2EBFE0' => { 'rtr' => '062EBFE0' , 'idx' => 2234 , 'extid' => 'E9DBA757A70A90' , 'max' =>      200 , 'min' =>       35 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_DIFF_STOP_TEMP' },
    '0E2EFFE0' => { 'rtr' => '062EFFE0' , 'idx' => 2235 , 'extid' => '0057AFD8D50A97' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_FREEZEGUARD_ACTIVE' },
    '0E2F3FE0' => { 'rtr' => '062F3FE0' , 'idx' => 2236 , 'extid' => 'E9AEA686120A98' , 'max' =>      100 , 'min' =>       40 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_FREEZEGUARD_START_TEMP' },
    '0E2F7FE0' => { 'rtr' => '062F7FE0' , 'idx' => 2237 , 'extid' => 'E9739B6B4E0A99' , 'max' =>      100 , 'min' =>       40 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_FREEZEGUARD_STOP_TEMP' },
    '0E2FBFE0' => { 'rtr' => '062FBFE0' , 'idx' => 2238 , 'extid' => 'C014177C850A91' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_PIPE_FUNCTION' },
    '0E2FFFE0' => { 'rtr' => '062FFFE0' , 'idx' => 2239 , 'extid' => 'EAA1EA86E90A96' , 'max' =>      610 , 'min' =>       90 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_PRIO_DHW_BLOCK_TEMP' },
    '0E307FE0' => { 'rtr' => '06307FE0' , 'idx' => 2241 , 'extid' => 'C01D7E5FC10A9A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_SOUTHEUROPE' },
    '0E30BFE0' => { 'rtr' => '0630BFE0' , 'idx' => 2242 , 'extid' => '00C060CDDB0AF0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_HIGH' },
    '0E30FFE0' => { 'rtr' => '0630FFE0' , 'idx' => 2243 , 'extid' => '00992F192F0AEF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_LOW' },
    '0E313FE0' => { 'rtr' => '06313FE0' , 'idx' => 2244 , 'extid' => 'E1F032413D0A92' , 'max' =>      140 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_MAX_TEMP' },
    '0E317FE0' => { 'rtr' => '06317FE0' , 'idx' => 2245 , 'extid' => 'E11652EEDC0A93' , 'max' =>       80 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_MIN_TEMP' },
    '0E31BFE0' => { 'rtr' => '0631BFE0' , 'idx' => 2246 , 'extid' => '0016392EC60B07' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T7_HIGH' },
    '0E31FFE0' => { 'rtr' => '0631FFE0' , 'idx' => 2247 , 'extid' => 'E1FD2C317A0A94' , 'max' =>       90 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T7_MAX_TEMP' },
    '0E323FE0' => { 'rtr' => '06323FE0' , 'idx' => 2248 , 'extid' => 'E12CB8BDE70A9B' , 'max' =>       10 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T7_RESTART_DIFF' },
    '0E327FE0' => { 'rtr' => '06327FE0' , 'idx' => 2249 , 'extid' => '839188B45602A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_DHW' },
    '0E337FE0' => { 'rtr' => '06337FE0' , 'idx' => 2253 , 'extid' => '8394C01E2B0694' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_DHW_2' },
    '0E347FE0' => { 'rtr' => '06347FE0' , 'idx' => 2257 , 'extid' => '8350DFEBB5029E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_HEATING' },
    '0E357FE0' => { 'rtr' => '06357FE0' , 'idx' => 2261 , 'extid' => '831A4733360699' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_HEATING_2' },
    '0E367FE0' => { 'rtr' => '06367FE0' , 'idx' => 2265 , 'extid' => '83E6D0E31F0180' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_HZ_DHW' },
    '0E377FE0' => { 'rtr' => '06377FE0' , 'idx' => 2269 , 'extid' => '836333F7F40181' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_HZ_HEATING' },
    '0E387FE0' => { 'rtr' => '06387FE0' , 'idx' => 2273 , 'extid' => '8377DED05706A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_POOL' },
    '0E397FE0' => { 'rtr' => '06397FE0' , 'idx' => 2277 , 'extid' => '83C7046C7D06A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_POOL_2' },
    '0E3A7FE0' => { 'rtr' => '063A7FE0' , 'idx' => 2281 , 'extid' => '409AFF32BE05BB' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_RESET' },
    '0E3ABFE0' => { 'rtr' => '063ABFE0' , 'idx' => 2282 , 'extid' => '831852F1E30257' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_START_DHW' },
    '0E3BBFE0' => { 'rtr' => '063BBFE0' , 'idx' => 2286 , 'extid' => '830BC478130697' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_DHW_2' },
    '0E3CBFE0' => { 'rtr' => '063CBFE0' , 'idx' => 2290 , 'extid' => '83E3910C270256' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_START_HEATING' },
    '0E3DBFE0' => { 'rtr' => '063DBFE0' , 'idx' => 2294 , 'extid' => '83675E1F3B0695' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_HEATING_2' },
    '0E3EBFE0' => { 'rtr' => '063EBFE0' , 'idx' => 2298 , 'extid' => '83CC5C4D1106A7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_POOL' },
    '0E3FBFE0' => { 'rtr' => '063FBFE0' , 'idx' => 2302 , 'extid' => '83EF99D08506A8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_POOL_2' },
    '0E40BFE0' => { 'rtr' => '0640BFE0' , 'idx' => 2306 , 'extid' => '83FAB432F80311' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTACTOR_1' },
    '0E41BFE0' => { 'rtr' => '0641BFE0' , 'idx' => 2310 , 'extid' => '8363BD63420312' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTACTOR_2' },
    '0E42BFE0' => { 'rtr' => '0642BFE0' , 'idx' => 2314 , 'extid' => '406512BBC205BC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTACTOR_RESET' },
    '0E42FFE0' => { 'rtr' => '0642FFE0' , 'idx' => 2315 , 'extid' => '83AB5B0DA5030E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTROL' },
    '0E43FFE0' => { 'rtr' => '0643FFE0' , 'idx' => 2319 , 'extid' => '405591EFAF07C9' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTROL_RESET' },
    '0E443FE0' => { 'rtr' => '06443FE0' , 'idx' => 2320 , 'extid' => '8302AE12AC0034' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 1 , 'text' => 'STATS_ELECTR_ADD_DHW' },
    '0E453FE0' => { 'rtr' => '06453FE0' , 'idx' => 2324 , 'extid' => '83CE297D7E0033' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 1 , 'text' => 'STATS_ELECTR_ADD_HEATING' },
    '0E463FE0' => { 'rtr' => '06463FE0' , 'idx' => 2328 , 'extid' => '832A25EDF306A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 0 , 'text' => 'STATS_ELECTR_ADD_POOL' },
    '0E473FE0' => { 'rtr' => '06473FE0' , 'idx' => 2332 , 'extid' => '404B19AE7205B9' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ELECTR_ADD_RESET' },
    '0E477FE0' => { 'rtr' => '06477FE0' , 'idx' => 2333 , 'extid' => '80F63E80420B2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ENERGY_HIDE_MENU' },
    '0E47BFE0' => { 'rtr' => '0647BFE0' , 'idx' => 2334 , 'extid' => '935B8C70A60A6A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 1 , 'text' => 'STATS_ENERGY_OUTPUT' },
    '0E48BFE0' => { 'rtr' => '0648BFE0' , 'idx' => 2338 , 'extid' => '935F68951C0A6B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 1 , 'text' => 'STATS_ENERGY_OUTPUT_DHW' },
    '0E49BFE0' => { 'rtr' => '0649BFE0' , 'idx' => 2342 , 'extid' => '93BF5B63600A69' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 1 , 'text' => 'STATS_ENERGY_OUTPUT_HEATING' },
    '0E4ABFE0' => { 'rtr' => '064ABFE0' , 'idx' => 2346 , 'extid' => '93E11998F80A6F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 0 , 'text' => 'STATS_ENERGY_OUTPUT_POOL' },
    '0E4BBFE0' => { 'rtr' => '064BBFE0' , 'idx' => 2350 , 'extid' => '8347EABD6A02A0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_OP_DHW' },
    '0E4CBFE0' => { 'rtr' => '064CBFE0' , 'idx' => 2354 , 'extid' => '83DD88E9E7029F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_OP_HEATING' },
    '0E4DBFE0' => { 'rtr' => '064DBFE0' , 'idx' => 2358 , 'extid' => '4090D0258705BA' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_OP_RESET' },
    '0E4DFFE0' => { 'rtr' => '064DFFE0' , 'idx' => 2359 , 'extid' => '40ACAF056B0224' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_RESET' },
    '0E4E3FE0' => { 'rtr' => '064E3FE0' , 'idx' => 2360 , 'extid' => '81DCC8D51E0178' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_AVERAGE_HZ_DHW' },
    '0E4E7FE0' => { 'rtr' => '064E7FE0' , 'idx' => 2361 , 'extid' => '81BF7E48580179' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_AVERAGE_HZ_HEATING' },
    '0E4EBFE0' => { 'rtr' => '064EBFE0' , 'idx' => 2362 , 'extid' => '838B1C7E4002A2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_DHW' },
    '0E4FBFE0' => { 'rtr' => '064FBFE0' , 'idx' => 2366 , 'extid' => '83F3E99AC6069C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_DHW_2' },
    '0E50BFE0' => { 'rtr' => '0650BFE0' , 'idx' => 2370 , 'extid' => '8351DA460402A1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HEATING' },
    '0E51BFE0' => { 'rtr' => '0651BFE0' , 'idx' => 2374 , 'extid' => '834FFE729F069B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HEATING_2' },
    '0E52BFE0' => { 'rtr' => '0652BFE0' , 'idx' => 2378 , 'extid' => '83380C545E0183' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HZ_DHW' },
    '0E53BFE0' => { 'rtr' => '0653BFE0' , 'idx' => 2382 , 'extid' => '83CC6C55F90182' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HZ_HEATING' },
    '0E54BFE0' => { 'rtr' => '0654BFE0' , 'idx' => 2386 , 'extid' => '8379ACDC8506AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HZ_POOL' },
    '0E55BFE0' => { 'rtr' => '0655BFE0' , 'idx' => 2390 , 'extid' => '838310F1CC06AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_POOL' },
    '0E56BFE0' => { 'rtr' => '0656BFE0' , 'idx' => 2394 , 'extid' => '8319D8DB3C06AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_POOL_2' },
    '0E57BFE0' => { 'rtr' => '0657BFE0' , 'idx' => 2398 , 'extid' => '40FDD6B6530214' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_RESET' },
    '0E57FFE0' => { 'rtr' => '0657FFE0' , 'idx' => 2399 , 'extid' => '834DEBB04A0259' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_DHW' },
    '0E58FFE0' => { 'rtr' => '0658FFE0' , 'idx' => 2403 , 'extid' => '8375DA5B0C0698' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_DHW_2' },
    '0E59FFE0' => { 'rtr' => '0659FFE0' , 'idx' => 2407 , 'extid' => '838CAC0DD50258' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_HEATING' },
    '0E5AFFE0' => { 'rtr' => '065AFFE0' , 'idx' => 2411 , 'extid' => '8336D3C3AF0696' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_HEATING_2' },
    '0E5BFFE0' => { 'rtr' => '065BFFE0' , 'idx' => 2415 , 'extid' => '836303EF1C06AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_POOL' },
    '0E5CFFE0' => { 'rtr' => '065CFFE0' , 'idx' => 2419 , 'extid' => '8362EFC35306AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_POOL_2' },
    '0E5DFFE0' => { 'rtr' => '065DFFE0' , 'idx' => 2423 , 'extid' => '407BE577990218' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_RESET' },
    '0E5E3FE0' => { 'rtr' => '065E3FE0' , 'idx' => 2424 , 'extid' => '83C820ADEC05BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_CONTACTOR_1' },
    '0E5F3FE0' => { 'rtr' => '065F3FE0' , 'idx' => 2428 , 'extid' => '835129FC5605C0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_CONTACTOR_2' },
    '0E603FE0' => { 'rtr' => '06603FE0' , 'idx' => 2432 , 'extid' => '4091DC9A5905BD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_CONTACTOR_RESET' },
    '0E607FE0' => { 'rtr' => '06607FE0' , 'idx' => 2433 , 'extid' => '83183AD8BA0036' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_DHW' },
    '0E617FE0' => { 'rtr' => '06617FE0' , 'idx' => 2437 , 'extid' => '83CF2CD0CF0035' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_HEATING' },
    '0E627FE0' => { 'rtr' => '06627FE0' , 'idx' => 2441 , 'extid' => '83DEEBCC6806AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_POOL' },
    '0E637FE0' => { 'rtr' => '06637FE0' , 'idx' => 2445 , 'extid' => '402C302A9F0037' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_RESET' },
    '0E63BFE0' => { 'rtr' => '0663BFE0' , 'idx' => 2446 , 'extid' => '8320D4D38602A4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_OP_DHW' },
    '0E64BFE0' => { 'rtr' => '0664BFE0' , 'idx' => 2450 , 'extid' => '83917B1ECB02A3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_OP_HEATING' },
    '0E65BFE0' => { 'rtr' => '0665BFE0' , 'idx' => 2454 , 'extid' => '40C811B206021D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_OP_RESET' },
    '0E65FFE0' => { 'rtr' => '0665FFE0' , 'idx' => 2455 , 'extid' => '404F8B25F00223' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_RESET' },
    '0E663FE0' => { 'rtr' => '06663FE0' , 'idx' => 2456 , 'extid' => 'C0D802DC890660' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'SUMMARY_ALARM_MODE' },
    '0E667FE0' => { 'rtr' => '06667FE0' , 'idx' => 2457 , 'extid' => '033DC6687E0A67' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TEMP' },
    '0E677FE0' => { 'rtr' => '06677FE0' , 'idx' => 2461 , 'extid' => '016A5399A300F0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_DRIFTTILLSTAND' },
    '0E67BFE0' => { 'rtr' => '0667BFE0' , 'idx' => 2462 , 'extid' => 'E182EE781F00F2' , 'max' =>      180 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_RAMP_TID' },
    '0E67FFE0' => { 'rtr' => '0667FFE0' , 'idx' => 2463 , 'extid' => '0A68B7289B00F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_UTSIGNAL_UT' },
    '0E687FE0' => { 'rtr' => '06687FE0' , 'idx' => 2465 , 'extid' => '81798B64B6027B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'UI_BRAND' },
    '0E68BFE0' => { 'rtr' => '0668BFE0' , 'idx' => 2466 , 'extid' => '4021FE28EF0759' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'USER_CONFIRMATION' },
    '0E68FFE0' => { 'rtr' => '0668FFE0' , 'idx' => 2467 , 'extid' => '0150FBFC2B075A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'USER_CONFIRMATION_OBJECT' },
    '0E693FE0' => { 'rtr' => '06693FE0' , 'idx' => 2468 , 'extid' => 'E959EE228700FA' , 'max' =>      200 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'VS_DIREKTSTART_GRANS' },
    '0E697FE0' => { 'rtr' => '06697FE0' , 'idx' => 2469 , 'extid' => 'E92746DA7B00FB' , 'max' =>      200 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'VS_DIREKTSTOPP_GRANS' },
    '0E69BFE0' => { 'rtr' => '0669BFE0' , 'idx' => 2470 , 'extid' => '0090432FBD0187' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_COMPRESSOR_REQUEST' },
    '0E69FFE0' => { 'rtr' => '0669FFE0' , 'idx' => 2471 , 'extid' => '004E977F0B0677' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_COMPRESSOR_REQUEST_2' },
    '0E6A3FE0' => { 'rtr' => '066A3FE0' , 'idx' => 2472 , 'extid' => '01A9D5A48A0253' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_REQUEST' },
    '0E6A7FE0' => { 'rtr' => '066A7FE0' , 'idx' => 2473 , 'extid' => 'EE1597E1AD010E' , 'max' =>      650 , 'min' =>      500 , 'format' => 'tem' , 'read' => 1 , 'text' => 'XDHW_STOP_TEMP' },
    '0E6AFFE0' => { 'rtr' => '066AFFE0' , 'idx' => 2475 , 'extid' => 'E1263DCA71010F' , 'max' =>       48 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_TIME' },
    '0E6B3FE0' => { 'rtr' => '066B3FE0' , 'idx' => 2476 , 'extid' => 'E17B4289E402CD' , 'max' =>        8 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_DAY' },
    '0E6B7FE0' => { 'rtr' => '066B7FE0' , 'idx' => 2477 , 'extid' => 'C9939E5AB602BD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_DURATION_TIME' },
    '0E6BBFE0' => { 'rtr' => '066BBFE0' , 'idx' => 2478 , 'extid' => '00BBD71E5202BE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_FAILED' },
    '0E6BFFE0' => { 'rtr' => '066BFFE0' , 'idx' => 2479 , 'extid' => '80C54B781C0CA2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_HAS_FINISHED' },
    '0E6C3FE0' => { 'rtr' => '066C3FE0' , 'idx' => 2480 , 'extid' => 'E11C86660302BB' , 'max' =>       23 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_HOUR' },
    '0E6C7FE0' => { 'rtr' => '066C7FE0' , 'idx' => 2481 , 'extid' => 'E922E7AC5902BC' , 'max' =>       50 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_MAX_TIME' },
    '0E6CBFE0' => { 'rtr' => '066CBFE0' , 'idx' => 2482 , 'extid' => '004BD827AD02BA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_REQUEST' },
    '0E6CFFE0' => { 'rtr' => '066CFFE0' , 'idx' => 2483 , 'extid' => '813A7FAA280CA1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_SAVED_DAY' },
    '0E6D3FE0' => { 'rtr' => '066D3FE0' , 'idx' => 2484 , 'extid' => 'EEBBE3635F033A' , 'max' =>      700 , 'min' =>      480 , 'format' => 'tem' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_STOP_TEMP' },
    '0E6DBFE0' => { 'rtr' => '066DBFE0' , 'idx' => 2486 , 'extid' => 'E137C21E8D0343' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_WEEK' },
    '0E6DFFE0' => { 'rtr' => '066DFFE0' , 'idx' => 2487 , 'extid' => '03A8D5BC550000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_WARM_KEEPING_TIMER' },
    '0E6E3FE0' => { 'rtr' => '066E3FE0' , 'idx' => 2488 , 'extid' => '030C2923470000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'VV_MAX_TIMER' },
    '0E6E7FE0' => { 'rtr' => '066E7FE0' , 'idx' => 2489 , 'extid' => '037043A3350000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_TIMER' },
    '0E6EBFE0' => { 'rtr' => '066EBFE0' , 'idx' => 2490 , 'extid' => '03DF2E585D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'VV_RAD_TIMER' },
    '0E6EFFE0' => { 'rtr' => '066EFFE0' , 'idx' => 2491 , 'extid' => '039F4458E90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RAD_MAX_TIMER' },
    '0E6F3FE0' => { 'rtr' => '066F3FE0' , 'idx' => 2492 , 'extid' => '03D904A13A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RAD_BEHOV_BLOCKERING_TIMER' },
    '0E6F7FE0' => { 'rtr' => '066F7FE0' , 'idx' => 2493 , 'extid' => '03F977D30A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEGREE_MINUTE_SAMPLE_TIMER' },
    '0E6FBFE0' => { 'rtr' => '066FBFE0' , 'idx' => 2494 , 'extid' => '030646EB560000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_START_DELAY_TIMER' },
    '0E6FFFE0' => { 'rtr' => '066FFFE0' , 'idx' => 2495 , 'extid' => '03571B7C340000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGUARD_DELAY_TIMER' },
    '0E703FE0' => { 'rtr' => '06703FE0' , 'idx' => 2496 , 'extid' => '03D5E7D7960000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_RAMP_TIMER' },
    '0E707FE0' => { 'rtr' => '06707FE0' , 'idx' => 2497 , 'extid' => '0343C2F8410000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STARTUP_TIMER' },
    '0E70BFE0' => { 'rtr' => '0670BFE0' , 'idx' => 2498 , 'extid' => '03B6D656E60000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_TIMER' },
    '0E70FFE0' => { 'rtr' => '0670FFE0' , 'idx' => 2499 , 'extid' => '0387E23C230000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_DELAY_TIMER' },
    '0E713FE0' => { 'rtr' => '06713FE0' , 'idx' => 2500 , 'extid' => '03A36256D30000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_TIMER' },
    '0E717FE0' => { 'rtr' => '06717FE0' , 'idx' => 2501 , 'extid' => '03CB658F620000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TEMP_LIMIT_TIMER' },
    '0E71BFE0' => { 'rtr' => '0671BFE0' , 'idx' => 2502 , 'extid' => '035B7EC57A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G1_OPTIMIZED_TIMER' },
    '0E71FFE0' => { 'rtr' => '0671FFE0' , 'idx' => 2503 , 'extid' => '03AE8860720000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_TEMP_BLOCK_TIMER' },
    '0E723FE0' => { 'rtr' => '06723FE0' , 'idx' => 2504 , 'extid' => '03E496D6400000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_TEMP_BLOCK_TIMER_2' },
    '0E727FE0' => { 'rtr' => '06727FE0' , 'idx' => 2505 , 'extid' => '036B1ADE3B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_STOP_DELAY_TIMER' },
    '0E72BFE0' => { 'rtr' => '0672BFE0' , 'idx' => 2506 , 'extid' => '03D5C876FB0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ALARM_MODE_DELAY_TIMER' },
    '0E72FFE0' => { 'rtr' => '0672FFE0' , 'idx' => 2507 , 'extid' => '03693E03EE0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LARMSUMMER_DELAY_TIMER' },
    '0E733FE0' => { 'rtr' => '06733FE0' , 'idx' => 2508 , 'extid' => '038A0048B20000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LARMSUMMER_INTERVAL_TIMER' },
    '0E737FE0' => { 'rtr' => '06737FE0' , 'idx' => 2509 , 'extid' => '03AF0414140000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREENSAVER_TIMER' },
    '0E73BFE0' => { 'rtr' => '0673BFE0' , 'idx' => 2510 , 'extid' => '03DF5074270000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'QUICKMENU_TIMER' },
    '0E73FFE0' => { 'rtr' => '0673FFE0' , 'idx' => 2511 , 'extid' => '03DBDCE0BD0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COOLING_FAN_STOP_DELAY_TIMER' },
    '0E743FE0' => { 'rtr' => '06743FE0' , 'idx' => 2512 , 'extid' => '039E84DA850000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_START_TIMER' },
    '0E747FE0' => { 'rtr' => '06747FE0' , 'idx' => 2513 , 'extid' => '0334A501230000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_LARM_DELAY_TIMER' },
    '0E74BFE0' => { 'rtr' => '0674BFE0' , 'idx' => 2514 , 'extid' => '03EB7658B80000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_2_LARM_DELAY_TIMER' },
    '0E74FFE0' => { 'rtr' => '0674FFE0' , 'idx' => 2515 , 'extid' => '03B02C57B20000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIMER' },
    '0E753FE0' => { 'rtr' => '06753FE0' , 'idx' => 2516 , 'extid' => '0397D1BAA50000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIMER_2' },
    '0E757FE0' => { 'rtr' => '06757FE0' , 'idx' => 2517 , 'extid' => '039655D95C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MIN_BREAK_TIMER' },
    '0E75BFE0' => { 'rtr' => '0675BFE0' , 'idx' => 2518 , 'extid' => '035D2CEC990000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MIN_BREAK_TIMER_2' },
    '0E75FFE0' => { 'rtr' => '0675FFE0' , 'idx' => 2519 , 'extid' => '039BB8F62B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_TIMER' },
    '0E763FE0' => { 'rtr' => '06763FE0' , 'idx' => 2520 , 'extid' => '039683331C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_TIMER_2' },
    '0E767FE0' => { 'rtr' => '06767FE0' , 'idx' => 2521 , 'extid' => '033677609B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIMER' },
    '0E76BFE0' => { 'rtr' => '0676BFE0' , 'idx' => 2522 , 'extid' => '036B2A061A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIMER_2' },
    '0E76FFE0' => { 'rtr' => '0676FFE0' , 'idx' => 2523 , 'extid' => '03649B4C1B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIMER' },
    '0E773FE0' => { 'rtr' => '06773FE0' , 'idx' => 2524 , 'extid' => '036271A05E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIMER_2' },
    '0E777FE0' => { 'rtr' => '06777FE0' , 'idx' => 2525 , 'extid' => '03BE2D7BE40000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TIMER' },
    '0E77BFE0' => { 'rtr' => '0677BFE0' , 'idx' => 2526 , 'extid' => '0349E822950000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TIMER_2' },
    '0E77FFE0' => { 'rtr' => '0677FFE0' , 'idx' => 2527 , 'extid' => '0337E6727C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2_TIMER' },
    '0E783FE0' => { 'rtr' => '06783FE0' , 'idx' => 2528 , 'extid' => '03AFA2968B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'NEUTRALZONE_LIMITATION_TIMER' },
    '0E787FE0' => { 'rtr' => '06787FE0' , 'idx' => 2529 , 'extid' => '0395A0A18D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERNAL_HEAT_VALVE_DELAY_TIMER' },
    '0E78BFE0' => { 'rtr' => '0678BFE0' , 'idx' => 2530 , 'extid' => '038BEED8DC0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_DELAY_TIMER' },
    '0E78FFE0' => { 'rtr' => '0678FFE0' , 'idx' => 2531 , 'extid' => '03A8432FE00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_2_DELAY_TIMER' },
    '0E793FE0' => { 'rtr' => '06793FE0' , 'idx' => 2532 , 'extid' => '0335BCDBBA0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_DELAY_AFTER_SWITCH_TIMER' },
    '0E797FE0' => { 'rtr' => '06797FE0' , 'idx' => 2533 , 'extid' => '0306E9C7690000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_2_DELAY_AFTER_SWITCH_TIMER' },
    '0E79BFE0' => { 'rtr' => '0679BFE0' , 'idx' => 2534 , 'extid' => '03FB40F9E30000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_DELAY_TIMER' },
    '0E79FFE0' => { 'rtr' => '0679FFE0' , 'idx' => 2535 , 'extid' => '03BCF4652C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_2_DELAY_TIMER' },
    '0E7A3FE0' => { 'rtr' => '067A3FE0' , 'idx' => 2536 , 'extid' => '03C36360E10000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_DELAY_AFTER_SWITCH_TIMER' },
    '0E7A7FE0' => { 'rtr' => '067A7FE0' , 'idx' => 2537 , 'extid' => '030315DF2D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_2_DELAY_AFTER_SWITCH_TIMER' },
    '0E7ABFE0' => { 'rtr' => '067ABFE0' , 'idx' => 2538 , 'extid' => '0334D523DC0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_DEFROST_DELAY_TIMER' },
    '0E7AFFE0' => { 'rtr' => '067AFFE0' , 'idx' => 2539 , 'extid' => '035F6232A00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_ADDITIONALHEAT_DELAY_TIMER' },
    '0E7B3FE0' => { 'rtr' => '067B3FE0' , 'idx' => 2540 , 'extid' => '03BAFFC53E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_HEATING_START_DELAY_AT_CASCADE' },
    '0E7B7FE0' => { 'rtr' => '067B7FE0' , 'idx' => 2541 , 'extid' => '0326475C6E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_HEATING_STOP_DELAY_AT_CASCADE' },
    '0E7BBFE0' => { 'rtr' => '067BBFE0' , 'idx' => 2542 , 'extid' => '030DC217150000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_TIMER' },
    '0E7BFFE0' => { 'rtr' => '067BFFE0' , 'idx' => 2543 , 'extid' => '033E0114990000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_TIMER_2' },
    '0E7C3FE0' => { 'rtr' => '067C3FE0' , 'idx' => 2544 , 'extid' => '0325EB8EE00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_DELAY_TIMER_2' },
    '0E7C7FE0' => { 'rtr' => '067C7FE0' , 'idx' => 2545 , 'extid' => '0338E9DA6F0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_AFTER_VV_TIMER' },
    '0E7CBFE0' => { 'rtr' => '067CBFE0' , 'idx' => 2546 , 'extid' => '0390716E0C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_AFTER_HG_TIMER' },
    '0E7CFFE0' => { 'rtr' => '067CFFE0' , 'idx' => 2547 , 'extid' => '03987556E00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_2_BLOCK_AFTER_VV_TIMER' },
    '0E7D3FE0' => { 'rtr' => '067D3FE0' , 'idx' => 2548 , 'extid' => '0330EDE2830000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_2_BLOCK_AFTER_HG_TIMER' },
    '0E7D7FE0' => { 'rtr' => '067D7FE0' , 'idx' => 2549 , 'extid' => '03CA2A2BBF0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_OUTDOOR_ACKNOWLEDGE_TIMER' },
    '0E7DBFE0' => { 'rtr' => '067DBFE0' , 'idx' => 2550 , 'extid' => '0312F33CA10000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_2_BLOCK_AFTER_GT2_LOW_TIMER' },
    '0E7DFFE0' => { 'rtr' => '067DFFE0' , 'idx' => 2551 , 'extid' => '0365D5BF960000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_TIMER' },
    '0E7E3FE0' => { 'rtr' => '067E3FE0' , 'idx' => 2552 , 'extid' => '03D54804B70000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'D_VALVE_STARTUP_TIMER' },
    '0E7E7FE0' => { 'rtr' => '067E7FE0' , 'idx' => 2553 , 'extid' => '03116FC3180000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_START_DELAY_TIMER' },
    '0E7EBFE0' => { 'rtr' => '067EBFE0' , 'idx' => 2554 , 'extid' => '03B6B0774B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SYNCH_VALVE_TIMER' },
    '0E7EFFE0' => { 'rtr' => '067EFFE0' , 'idx' => 2555 , 'extid' => '033A5C6DEE0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_PROTECTIVE_ANODE_ALERT_DELAY_TIMER' },
    '0E7F3FE0' => { 'rtr' => '067F3FE0' , 'idx' => 2556 , 'extid' => '033F942D3B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_COMPRESSOR_START' },
    '0E7F7FE0' => { 'rtr' => '067F7FE0' , 'idx' => 2557 , 'extid' => '030D1952910000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_4_WAY_VALVE_SWITCH' },
    '0E7FBFE0' => { 'rtr' => '067FBFE0' , 'idx' => 2558 , 'extid' => '03BE9F792A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_COMPRESSOR_2_START' },
    '0E7FFFE0' => { 'rtr' => '067FFFE0' , 'idx' => 2559 , 'extid' => '03BF774E1E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_4_WAY_VALVE_2_SWITCH' },
    '0E803FE0' => { 'rtr' => '06803FE0' , 'idx' => 2560 , 'extid' => '038D0B511C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_PIPE_DELAY' },
    '0E807FE0' => { 'rtr' => '06807FE0' , 'idx' => 2561 , 'extid' => '03C32CCD200000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_PIPE_EXERCISE' },
    '0E80BFE0' => { 'rtr' => '0680BFE0' , 'idx' => 2562 , 'extid' => '03ACEF37B90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_HIGH' },
    '0E80FFE0' => { 'rtr' => '0680FFE0' , 'idx' => 2563 , 'extid' => '031040967B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_LOW' },
    '0E813FE0' => { 'rtr' => '06813FE0' , 'idx' => 2564 , 'extid' => '038F5858740000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIMER' },
    '0E817FE0' => { 'rtr' => '06817FE0' , 'idx' => 2565 , 'extid' => '03FC507FBB0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIMER' },
    '0E81BFE0' => { 'rtr' => '0681BFE0' , 'idx' => 2566 , 'extid' => '039ACEE8880000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIMER_2' },
    '0E81FFE0' => { 'rtr' => '0681FFE0' , 'idx' => 2567 , 'extid' => '0373A6E56A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIMER_2' },
    '0E823FE0' => { 'rtr' => '06823FE0' , 'idx' => 2568 , 'extid' => '03E47EE9760000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_G2_AFTER_XDHW' },
    '0E827FE0' => { 'rtr' => '06827FE0' , 'idx' => 2569 , 'extid' => '03327B78640000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_DELAY_BEFORE_SHORT_CIRCUIT' },
    '0E82BFE0' => { 'rtr' => '0682BFE0' , 'idx' => 2570 , 'extid' => '03CD930CA60000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_CONTROLLED_RISE' },
    '0E82FFE0' => { 'rtr' => '0682FFE0' , 'idx' => 2571 , 'extid' => '035396F6D10000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_G2_ADJUST_TIMER' },
    '0E833FE0' => { 'rtr' => '06833FE0' , 'idx' => 2572 , 'extid' => '03BEA3936D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E21_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    '0E837FE0' => { 'rtr' => '06837FE0' , 'idx' => 2573 , 'extid' => '03E5B422780000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E22_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    '0E83BFE0' => { 'rtr' => '0683BFE0' , 'idx' => 2574 , 'extid' => '03688E73320000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_ACCESS_LEVEL' },
    '0E83FFE0' => { 'rtr' => '0683FFE0' , 'idx' => 2575 , 'extid' => '0374902F9F0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E21_G2_TEMPORARY_STOP' },
    '0E843FE0' => { 'rtr' => '06843FE0' , 'idx' => 2576 , 'extid' => '03D7C6A9360000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E22_G2_TEMPORARY_STOP' },
    '0E847FE0' => { 'rtr' => '06847FE0' , 'idx' => 2577 , 'extid' => '03DF94AC2C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_COMMUNICATION_BAD_CANBUS_REBOOT_DELAY' },
    '0E84BFE0' => { 'rtr' => '0684BFE0' , 'idx' => 2578 , 'extid' => '039CA89DB30000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E21_G2_MEAN_VALUE_SAMPLE_TIME' },
    '0E84FFE0' => { 'rtr' => '0684FFE0' , 'idx' => 2579 , 'extid' => '032F3CB0700000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E22_G2_MEAN_VALUE_SAMPLE_TIME' },
    '0E853FE0' => { 'rtr' => '06853FE0' , 'idx' => 2580 , 'extid' => '03CB4C454D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E21_G2_INIT' },
    '0E857FE0' => { 'rtr' => '06857FE0' , 'idx' => 2581 , 'extid' => '03F2C179880000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E22_G2_INIT' },
    '0E85BFE0' => { 'rtr' => '0685BFE0' , 'idx' => 2582 , 'extid' => '037AFAC7930000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_FREEZEGUARD' },
    '0E85FFE0' => { 'rtr' => '0685FFE0' , 'idx' => 2583 , 'extid' => '039C488E6B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_CALIBRATE_PID' },
    '0E863FE0' => { 'rtr' => '06863FE0' , 'idx' => 2584 , 'extid' => '036B3D4C400000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_PID_SV41' },
    '0E867FE0' => { 'rtr' => '06867FE0' , 'idx' => 2585 , 'extid' => '03C3827F2F0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_M_VALVE_DEFROST' },
    '0E86BFE0' => { 'rtr' => '0686BFE0' , 'idx' => 2586 , 'extid' => '0330D709630000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_INIT_SV41' },
    '0E86FFE0' => { 'rtr' => '0686FFE0' , 'idx' => 2587 , 'extid' => '037A9EF9C90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E21_M_VALVE_DEFROST' },
    '0E873FE0' => { 'rtr' => '06873FE0' , 'idx' => 2588 , 'extid' => '0340EE87130000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_M_VALVE_LIMITATION' },
    '0E877FE0' => { 'rtr' => '06877FE0' , 'idx' => 2589 , 'extid' => '032CD2DBA80000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_M_VALVE_PULS_PAUS' },
    '0E87BFE0' => { 'rtr' => '0687BFE0' , 'idx' => 2590 , 'extid' => '036A78F2900000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_STARTUP_DELAY' },
    '0E87FFE0' => { 'rtr' => '0687FFE0' , 'idx' => 2591 , 'extid' => '03F5E34A180000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_HEATING_SEASON_STOP_DELAY' },
    '0E883FE0' => { 'rtr' => '06883FE0' , 'idx' => 2592 , 'extid' => '03F8766ABC0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_HEATING_SEASON_START_DELAY' },
    '0E887FE0' => { 'rtr' => '06887FE0' , 'idx' => 2593 , 'extid' => '035375085C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_ATTENUATION' },
    '0E88BFE0' => { 'rtr' => '0688BFE0' , 'idx' => 2594 , 'extid' => '031077F8550000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_DEFROST' },
    '0E88FFE0' => { 'rtr' => '0688FFE0' , 'idx' => 2595 , 'extid' => '03EB5A5D180000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS_2' },
    '0E893FE0' => { 'rtr' => '06893FE0' , 'idx' => 2596 , 'extid' => '03D093BCC60000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS' },
    '0E897FE0' => { 'rtr' => '06897FE0' , 'idx' => 2597 , 'extid' => '03C894A2500000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E21_T3_START_TEMP_ADJ' },
    '0E89BFE0' => { 'rtr' => '0689BFE0' , 'idx' => 2598 , 'extid' => '036BC224F90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E22_T3_START_TEMP_ADJ' },
    '0E89FFE0' => { 'rtr' => '0689FFE0' , 'idx' => 2599 , 'extid' => '0327DE5EF70000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SYSTEM_INIT' },
    '0E8A3FE0' => { 'rtr' => '068A3FE0' , 'idx' => 2600 , 'extid' => '03B11E70550000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_COMPRESSOR_START_DELAY_AT_CASCADE' },
);

my %KM273_format = (
    'int' => { factor => 1      , unit => ''    },
    't15' => { factor => 1      , unit => ''    },
    'tem' => { factor => 0.1    , unit => '°C'  },
    'pw2' => { factor => 0.01   , unit => 'kW'  },
    'pw3' => { factor => 0.001  , unit => 'kW'  },
    'sw1' => { factor => 1      , unit => ''    },
    'sw2' => { factor => 1      , unit => ''    },
    'rp1' => { factor => 1      , unit => ''    , 'select' => [ '0:HP_Optimized', '1:Program_1', '2:Program_2', '3:Family', '4:Morning', '5:Evening', '6:Seniors' ] },
    'rp2' => { factor => 1      , unit => ''    , 'select' => [ '0:Automatic', '1:Normal', '2:Exception', '3:HeatingOff' ] },
    'dp1' => { factor => 1      , unit => ''    , 'select' => [ '0:Always_On', '1:Program_1', '2:Program_2' ] },
    'dp2' => { factor => 1      , unit => ''    , 'select' => [ '0:Automatic', '1:Always_On', '2:Always_Off' ] },
);

my %KM273_gets = ();
my %KM273_history = ();
my @KM273_readingsRTR = ();
my %KM273_writingsTXD = ();
my %KM273_elements = ();

my %KM273_ReadElementListStatus = ( done => 0, wait => 0, readCounter => 0, readIndex => 0, readIndexLast => 0, writeIndex => 0, KM200active => 0, KM200wait => 0, readData => "");
my %KM273_ReadElementListElements = ();

sub KM273_ClearElementLists($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: KM273_ClearElementLists";
  
  %KM273_history = ();
  @KM273_readingsRTR = ();
  %KM273_writingsTXD = ();
  %KM273_elements = ();
  %KM273_ReadElementListStatus = ( done => 0, wait => 0, readCounter => 0, readIndex => 0, readIndexLast => 0, writeIndex => 0, KM200active => 0, KM200wait => 0, readData => "");
  %KM273_ReadElementListElements = ();
}

sub KM273_ReadElementList($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: KM273_ReadElementList entry readCounter=$KM273_ReadElementListStatus{readCounter} readIndex=$KM273_ReadElementListStatus{readIndex}";
  
  if (($KM273_ReadElementListStatus{readCounter} == 0) && ($KM273_ReadElementListStatus{KM200wait} == 0))
  {
    Log3 $name, 3, "$name: KM273_ReadElementList send R01FD7FE00";
    CAN_Write($hash,"R01FD7FE00");
    $KM273_ReadElementListStatus{KM200wait} = 20;
  }
  elsif ($KM273_ReadElementListStatus{KM200wait} > 0)
  {
    $KM273_ReadElementListStatus{KM200wait} -= 1 if ($KM273_ReadElementListStatus{KM200wait} > 0);
    if ($KM273_ReadElementListStatus{KM200wait} <= 0)
    {
      $KM273_ReadElementListStatus{KM200active} = 0;
      $KM273_ReadElementListStatus{readIndex} = 0;
      $KM273_ReadElementListStatus{writeIndex} = 0;
      $KM273_ReadElementListStatus{readData} = "";
    }
    Log3 $name, 3, "$name: KM273_ReadElementList KM200active=$KM273_ReadElementListStatus{KM200active} KM200wait=$KM273_ReadElementListStatus{KM200wait} readIndex=$KM273_ReadElementListStatus{readIndex}";
  }
  elsif ($KM273_ReadElementListStatus{writeIndex} <= $KM273_ReadElementListStatus{readIndex})
  {
    my $sendTel = sprintf("T01FD3FE08%08x%08x",4096,$KM273_ReadElementListStatus{writeIndex});
    $KM273_ReadElementListStatus{writeIndex} += 4096;
    $KM273_ReadElementListStatus{wait} = 20;
    Log3 $name, 3, "$name: KM273_ReadElementList send $sendTel";
    CAN_Write($hash,$sendTel);
    Log3 $name, 3, "$name: KM273_ReadElementList send R01FDBFE00";
    CAN_Write($hash,"R01FDBFE00");
  }
  elsif (--$KM273_ReadElementListStatus{wait} <= 0)
  {
    $KM273_ReadElementListStatus{readIndexLast} = $KM273_ReadElementListStatus{readIndex};
    $KM273_ReadElementListStatus{readIndex} = 0;
    $KM273_ReadElementListStatus{writeIndex} = 0;
    $KM273_ReadElementListStatus{readData} = "";
  }

  my $count = 1;
  while ($count > 0)
  {
    CAN_ReadBuffer($hash);
    $count = 0;
    
    my ($dir,$canId,$len1,$value1);
    $dir = 'R';
    while (($dir eq 'T') || ($dir eq 'R'))
    {
      ($dir,$canId,$len1,$value1) = CAN_Read($hash);
      $dir = '_' if (!defined($dir));
      if ($dir eq 'T')
      {
        if (hex $canId == 0x09FDBFE0)
        {
          if ($len1 <= 8)
          {
            $KM273_ReadElementListStatus{readIndex} += $len1;
            $value1 <<= 8*(8-$len1) if ($len1 < 8);
            $KM273_ReadElementListStatus{readData} .= pack("NN",$value1>>32,$value1&0xffffffff);
          }
          
          if (($KM273_ReadElementListStatus{readIndexLast} > 0) && ($KM273_ReadElementListStatus{readIndexLast} == $KM273_ReadElementListStatus{readIndex}))
          {
            #wenn readCounter auch beim 2. Lesen nicht erreicht wird, und gelesene Datenmenge gleich ist, dann readCounter = readIndex
            Log3 $name, 3, "$name: KM273_ReadElementList readCounter $KM273_ReadElementListStatus{readCounter} changed to $KM273_ReadElementListStatus{readIndex}";
            $KM273_ReadElementListStatus{readCounter} = $KM273_ReadElementListStatus{readIndex};
          }
          if (($KM273_ReadElementListStatus{readCounter} > 0) && ($KM273_ReadElementListStatus{readIndex} >= $KM273_ReadElementListStatus{readCounter}))
          {
            $KM273_ReadElementListStatus{done} = 1;
            Log3 $name, 3, "$name: KM273_ReadElementList done, readCounter=$KM273_ReadElementListStatus{readCounter} readIndex=$KM273_ReadElementListStatus{readIndex}";

            %KM273_ReadElementListElements = ();
            my $i1 = 0;
            my $imax = $KM273_ReadElementListStatus{readIndex};
            my $idLast = -1;
            while ($i1<$imax)
            {
              if ($imax-$i1 > 18)
              {
                my ($idx,$extid,$max2,$min2,$len2) = unpack("nH14NNc",substr($KM273_ReadElementListStatus{readData},$i1,18));
                $min2 = unpack 'l*', pack 'L*', $min2; # unsigned long to signed long
                $max2 = unpack 'l*', pack 'L*', $max2;
                if (($idx > $idLast) && ($len2 > 1) && ($len2 < 100))
                {
                  my $element2 = substr($KM273_ReadElementListStatus{readData},$i1+18,$len2-1);
                  $i1 += 18+$len2;
                  $KM273_ReadElementListElements{$element2} = {'idx' => $idx, 'extid' => $extid, 'max' => $max2, 'min' => $min2 };
                  Log3 $name, 3, "$name: KM273_ReadElementList done, idx=$idx extid=$extid max=$max2 min=$min2 element=$element2";
                }
                else
                {
                  Log3 $name, 3, "$name: KM273_ReadElementList error, idx=$idx extid=$extid max=$max2 min=$min2 len=$len2";
                  $KM273_ReadElementListStatus{done} = 0;
                  $KM273_ReadElementListStatus{KM200active} = 1;
                  $KM273_ReadElementListStatus{KM200wait} = 20;
                  $imax = 0;
                }
              }
              else {$i1+=18;}
            }
          }
          $count++;
        }
        elsif (hex $canId == 0x09FD7FE0)
        {
          my $readCounter = ($value1 >> 24); # + 10; #+10=Test
          $KM273_ReadElementListStatus{readCounter} = $readCounter;
          Log3 $name, 3, "$name: KM273_ReadElementList read T09FD7FE0 len=$len1 value=$value1 readCounter=$readCounter";
        }
        elsif (hex $canId == 0x01FD3FE0)
        {
          my $dataLen = $value1 >> 32;
          my $dataStart = $value1 & 0xffffffff;
          Log3 $name, 3, "$name: KM273_ReadElementList KM200 read canId=$canId len=$len1 dataStart=$dataStart dataLen=$dataLen";
          $KM273_ReadElementListStatus{KM200active} = 1;
          $KM273_ReadElementListStatus{KM200wait} = 20;
        }
      }
      elsif ($dir eq 'R')
      {
        if ((hex $canId == 0x01FD7FE0) || (hex $canId == 0x01FDBFE0))
        {
          Log3 $name, 3, "$name: KM273_ReadElementList KM200 read canId=$canId";
          $KM273_ReadElementListStatus{KM200active} = 1;
          $KM273_ReadElementListStatus{KM200wait} = 20;
        }
      }
    }
  }
  
  return undef;
}

sub KM273_UpdateElements($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: KM273_UpdateElements";
    
    my %AddToReadings = ();
    my @AddToReadingsKey = ();
    push @AddToReadingsKey, split(' ',($attr{$name}{AddToReadings})) if (defined($attr{$name}{AddToReadings}));
    push @AddToReadingsKey, split(' ',($attr{$name}{AddToGetSet})) if (defined($attr{$name}{AddToGetSet}));
    foreach my $elem (@AddToReadingsKey) { $AddToReadings{$elem} = '';}

    %KM273_elements = ();
    foreach my $element (keys %KM273_elements_default)
    {
        my $text = $KM273_elements_default{$element}{text};
        my $read = $KM273_elements_default{$element}{read};
        my $elem1 = $KM273_ReadElementListElements{$text};
        $read = 1 if (defined($AddToReadings{$text}));
        if (defined($AddToReadings{$text})) { Log3 $name, 3, "$name: KM273_UpdateElements AddToReadings $text"; };
        if ((!defined $elem1) && (($read == 1) || (($read == 2) && defined($attr{$name}{HeatCircuit2Active}) && ($attr{$name}{HeatCircuit2Active} == 1))))
        {
          my @days = ("1MON","2TUE","3WED","4THU","5FRI","6SAT","7SUN");
          foreach my $day (@days)
          {
            my $pos = index $text, $day;
            if ($pos > 0)
            {
              my $text1 = (substr $text, 0, $pos) . (substr $text, $pos+1);
              $elem1 = $KM273_ReadElementListElements{$text1};
              Log3 $name, 3, "$name: KM273_UpdateElements change $text1 to $text" if (defined $elem1);
              last;
            }
            
          }
        }
        if (defined $elem1)
        {
          my $idx = $elem1->{idx};
          my $rtr = sprintf("%08X",0x04003FE0 | ($idx << 14));
          my $txd = sprintf("%08X",0x0C003FE0 | ($idx << 14));
          my $format = $KM273_elements_default{$element}{format};
          $KM273_elements{$txd} = { 'rtr' => $rtr, 'idx' => $idx, 'extid' => $elem1->{extid}, 'max' => $elem1->{max}, 'min' => $elem1->{min}, 'format' => $format, 'read' => $read, 'text' => $text};
        }
        else
        {
          Log3 $name, 3, "$name: KM273_UpdateElements $text not found" if ($read != 0)
        }
    }
    return undef;
}

sub KM273_CreateElementList($)
{
    #just for simulation, if reading of element list from heatpump 
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: KM273_CreateElementList";
    %KM273_ReadElementListElements = ();
    foreach my $key (keys %KM273_elements_default)
    {
      my $text = $KM273_elements_default{$key}{text};
      my $idx = $KM273_elements_default{$key}{idx};
      my $extid = $KM273_elements_default{$key}{extid};
      my $max = $KM273_elements_default{$key}{max};
      my $min = $KM273_elements_default{$key}{min};
      $KM273_ReadElementListElements{$text} = {'idx' => $idx, 'extid' => $extid, 'max' => $max, 'min' => $min };
    }
    $KM273_ReadElementListStatus{done} = 1;
}

sub KM273_CreatePollingList($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: KM273_CreatePollingList";

    @KM273_readingsRTR = ();
    foreach my $element (keys %KM273_elements)
    {
        push @KM273_readingsRTR, $KM273_elements{$element}{rtr} if $KM273_elements{$element}{read} == 1;
        push @KM273_readingsRTR, $KM273_elements{$element}{rtr} if ($KM273_elements{$element}{read} == 2) && defined($attr{$name}{HeatCircuit2Active}) && ($attr{$name}{HeatCircuit2Active} == 1);
    }
    foreach my $val (@KM273_readingsRTR)
    {
        Log3 $name, 3, "$name: KM273_CreatePollingList rtr $val";
    }
    $hash->{pollingIndex} = 0;

    my @getElements = (keys %KM273_getsBase);
    push @getElements, (keys %KM273_getsAddHC2) if (defined($attr{$name}{HeatCircuit2Active}) && ($attr{$name}{HeatCircuit2Active} == 1));
    push @getElements, split(' ',($attr{$name}{AddToGetSet})) if (defined($attr{$name}{AddToGetSet}));
    %KM273_gets = ();
    foreach my $elem (@getElements) { $KM273_gets{$elem} = '';}

    %KM273_writingsTXD = ();
    foreach my $element (keys %KM273_elements)
    {
        foreach my $get (@getElements)
        {
            $KM273_writingsTXD{$get} = $KM273_elements{$element} if $KM273_elements{$element}{text} eq $get;
        }
    }
    foreach my $val (keys %KM273_writingsTXD)
    {
        Log3 $name, 3, "$name: KM273_CreatePollingList txd $val $KM273_writingsTXD{$val}{rtr}";
    }

    return undef;
}

sub KM273_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{DefFn}      = 'KM273_Define';
    $hash->{UndefFn}    = 'KM273_Undef';
    $hash->{SetFn}      = 'KM273_Set';
    $hash->{GetFn}      = 'KM273_Get';
    $hash->{AttrFn}     = 'KM273_Attr';
    $hash->{ReadFn}     = 'KM273_Read';
    $hash->{ReadyFn}    = 'KM273_Ready';
    $hash->{NotifyFn}   = 'KM273_Notify';
    $hash->{ShutdownFn} = 'KM273_Shutdown';

   $hash->{AttrList}    = "do_not_notify:1,0 " .
                          "loglevel:0,1,2,3,4,5,6 " .
                          "IntervalDynVal " .
                          "PollingTimeout " .
                          "ConsoleMessage " .
                          "DoNotPoll " .
                          "ReadBackDelay " .
                          "HeatCircuit2Active " .
                          "AddToGetSet " .
                          "AddToReadings " .
                          $readingFnAttributes;
}

sub KM273_Define($$)
{
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: KM273_Define";

    $hash->{VERSION} = "0015";
    
    my @param = split('[ \t]+', $def);

    if(int(@param) < 3) {
        return "too few parameters: define <name> KM273 <device>";
    }

    DevIo_CloseDev($hash);
    my $dev = $param[2];
    
    $hash->{NOTIFYDEV} = "global";

    KM273_ClearElementLists($hash);
    
    if($dev eq "none") {
      Log3 $name, 1, "$name: KM273_Define: KM273 device is none, commands will be echoed only";
      KM273_CreateElementList($hash);
      KM273_UpdateElements($hash);
      KM273_CreatePollingList($hash);
      return undef;
    }

    $hash->{DeviceName} = $dev;
    my $ret = DevIo_OpenDev($hash, 0, "CAN_DoInit");
    return $ret;

    return undef;
}

sub KM273_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; # own name / hash

	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash, 1);

  Log3 $ownName, 3, "$ownName: KM273_Notify ".join(',',@{$events});
	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$|^ATTR /, @{$events}))
	{
    if ($KM273_ReadElementListStatus{done})
    {
      RemoveInternalTimer($own_hash);
      KM273_UpdateElements($own_hash);
      KM273_CreatePollingList($own_hash);
      InternalTimer(gettimeofday()+10, "KM273_GetReadings", $own_hash, 0);
    }
	}
}

sub KM273_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: KM273_Undef";

  RemoveInternalTimer($hash);
  CAN_Close($hash);
  return undef;
}

sub KM273_Shutdown($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: KM273_Shutdown";

  RemoveInternalTimer($hash);
  CAN_Close($hash);
  return undef;
}

sub KM273_Get($@)
{
    my ($hash, @param) = @_;

    return '"get KM273" needs at least one argument' if (int(@param) < 2);

    my $name = shift @param;
    my $opt = shift @param;
    if(!defined($KM273_gets{$opt})) {
        my @cList = keys %KM273_gets;
        #push @cList, keys %KM273_getsAdd if defined($attr{$name}{HeatCircuit2Active}) && ($attr{$name}{HeatCircuit2Active} == 1);
        #push @cList, split(' ',($attr{$name}{AddToGetSet})) if (defined($attr{$name}{AddToGetSet}));
        return "Unknown argument $opt, choose one of " . join(":noArg ", @cList) . ":noArg";
    }

    if (defined($KM273_writingsTXD{$opt})) {
        my $canId = $KM273_writingsTXD{$opt}{rtr};
        my $txdata = "R" . $canId . "0";
        my $canIdIn = sprintf("%08X",hex $canId | 0x08000000);
        my $time = time();
        delete $KM273_history{$canIdIn} if (exists($KM273_history{$canIdIn}));
        CAN_Write($hash, $txdata);
        select(undef, undef, undef, 0.05);
        KM273_Read($hash);
        return "data not received within 50ms for $opt RTR=$canId canId=$canIdIn" if (!exists($KM273_history{$canIdIn}));
        return $KM273_history{$canIdIn}{formatedValue};
    }
    
    return "canId not defined for $opt";
}

sub KM273_Set($@)
{
    my ($hash, @param) = @_;

    return '"set KM273" needs at least one argument' if (int(@param) < 2);

    my $name = shift @param;
    my $opt = shift @param;
    my $value = join(" ", @param);

    if(!defined($KM273_gets{$opt}) && !defined($KM273_writingsTXD{$opt})) {
        my @cList = keys %KM273_gets;
        #push @cList, keys %KM273_getsAdd if defined($attr{$name}{HeatCircuit2Active}) && ($attr{$name}{HeatCircuit2Active} == 1);
        #push @cList, split(' ',($attr{$name}{AddToGetSet})) if (defined($attr{$name}{AddToGetSet}));
        if (!defined($attr{$name}{FormatSetParameter}) || ($attr{$name}{FormatSetParameter} == 1))
        {
          for my $cElem ( @cList )
          {
            if (defined($KM273_writingsTXD{$cElem}))
            {
              my $range = "";
              my $format = $KM273_writingsTXD{$cElem}{format};
              my $max = $KM273_writingsTXD{$cElem}{max};
              my $min = $KM273_writingsTXD{$cElem}{min};
              if ($max >= 16777216)
              {
                $max /= 16777216;
                $min /= 16777216;
              }
              if ($max <= $min)
              {
                if (!($format eq "sw1" || $format eq "sw2"))
                {
                  $range = ":noArg";
                }
              }
              elsif (defined($KM273_format{$format}))
              {
                if(defined($KM273_format{$format}{'select'}))
                {
                  my @select = @{$KM273_format{$format}{'select'}};
                  $range = ":" . join(",", @select);
                }
                else
                {
                  my $factor = $KM273_format{$format}{factor};
                  if($factor != 1)
                  {
                    $max *= $factor;
                    $min *= $factor;
                    $range = ":slider,$min,$factor,$max,1";
                  }
                  else
                  {
                    if (($max - $min) <= 10)
                    {
                      $range = ":".$min;
                      for my $idx ($min+1 .. $max) {$range .= ",".$idx}
                    }
                    elsif ($format ne "t15")
                    {
                      $range = ":slider,$min,$factor,$max";
                    }
                  }
                }
              }
              else
              {
              }
              $cElem .= $range;
            }
            else
            {
              $cElem .= ":noArg";
            }
            #Log3 $name, 5, "KM273_Set $opt $cElem";
          }
        }
        return "Unknown argument $opt, choose one of " . join(" ", @cList);
    }

    if (defined($KM273_writingsTXD{$opt})) {
        my $canId = $KM273_writingsTXD{$opt}{rtr};
        my $min = $KM273_writingsTXD{$opt}{min};
        my $max = $KM273_writingsTXD{$opt}{max};
        my $format = $KM273_writingsTXD{$opt}{format};
        my $factor = 1;
        my $value1 = $value * $factor;

        if ($format eq "sw1" || $format eq "sw2")
        {
            $value = lc $value;
            my @values = split(' ',$value);
            return "1: format for timespan : xx:xx on xx:xx off" if ($#values != 3 || $values[1] != 'on' || $values[3] != 'off' );
            my @timeOn = split(':',$values[0]);
            my @timeOff = split(':',$values[2]);
            return "2: format for timespan : xx:xx on xx:xx off" if ($#timeOn != 1 || $#timeOff != 1);
            my $timerOn = int ((int $timeOn[0] * 60 + int $timeOn[1]) / 30);
            my $timerOff = int ((int $timeOff[0] * 60 + int $timeOff[1]) / 30);
            return "on timer has to be between 0:00 and 23:30" if ($timerOn < 0 || $timerOn > 47);
            return "off timer has to be between 0:00 and 24:00" if ($timerOff < 0 || $timerOff > 48);
            return "on timer has to be smaller or equal off timer" if ($timerOn > $timerOff);
            $value1 = $timerOff + 256 * $timerOn;
            $value1 = $value1 | 0x4000 if ($format eq "sw2");
        }
        elsif ($format eq "t15")
        {
            my @time = split(':',$value);
            return "1: format for time xx:xx" if ($#time != 1);
            my $timer = int ((int $time[0] * 60 + int $time[1]) / 15);
            return "time has to be between 0:00 and 24:00" if ($timer < 0 || $timer > 96);
            $value1 = $timer;
        }
        elsif (defined $KM273_format{$format})
        {
            if (defined $KM273_format{$format}{'select'})
            {
                $value1 = -1;
                my @list = @{$KM273_format{$format}{'select'}};
                foreach my $elem (@list)
                {
                    my $idx = index $elem, $value;
                    if ($idx >= 0)
                    {
                        $value1 = int $elem;
                        last;
                    }
                }
                return "select one of " . join(' ',@list) if ($value1 < 0);
            }
            else
            {
                $factor = $KM273_format{$format}{factor};
                $value1 = int ($value / $factor + 0.5);
            }
        }
        if ($max > $min)
        {
            if ($value1 > $max)
            {
                my $limit = $max / $factor;
                return "value exceed the maximum limit of $limit";
            }
            if ($value1 < $min)
            {
                my $limit = $min / $factor;
                return "value exceed the minimum limit of $limit";
            }
        }
        my $data = sprintf ("%04X",$value1);
        my $txdata = "T" . $canId . "2" . $data;
        CAN_Write($hash, $txdata);
        Log3 $name, 3, "$name: KM273_Set CAN_Write $txdata";
    }

    #$hash->{STATE} = $KM273_gets{$opt} = $value;
    #return "$opt set to $value. Try to get it.";
}


sub KM273_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  if($cmd eq "set") {
    if($attr_name eq "formal") {
      if($attr_value !~ /^yes|no$/) {
        my $err = "Invalid argument $attr_value to $attr_name. Must be yes or no.";
        Log3 $name, 3, "KM273: ".$err;
        return $err;
      }
    }
    elsif(($attr_name eq "AddToReadings") || ($attr_name eq "AddToGetSet")) {
      Log3 $name, 3, "$name: KM273_Attr $attr_name $attr_value";
      if (!defined($KM273_ReadElementListElements{GT1_TEMP}))
      {
        Log3 $name, 3, "$name: KM273_Attr ReadElementListElements not ready for verify attribute";
        return undef;
      }
      my @valuesIn = split(" ", $attr_value);
      foreach my $valueIn (@valuesIn)
      {
        return "Unknown attr $attr_name value=$valueIn" if (!defined($KM273_ReadElementListElements{$valueIn}));
      }
    } else {
       # return "Unknown attr $attr_name";
    }
  }
  return undef;
}

sub KM273_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: KM273_Read";

    if (!$KM273_ReadElementListStatus{done})
    {
      KM273_ReadElementList($hash);
      if ($KM273_ReadElementListStatus{done})
      {
        KM273_UpdateElements($hash);
        KM273_CreatePollingList($hash);
        InternalTimer(gettimeofday()+10, "KM273_GetReadings", $hash, 0);
      }
      
      return undef;
    }

    CAN_ReadBuffer($hash);
    
    my ($dir,$canId,$len1,$value1,$value);
    $dir = 'R';
    while (($dir eq 'T') || ($dir eq 'R'))
    {
        ($dir,$canId,$len1,$value1) = CAN_Read($hash);
        $dir = '0' if (!defined($dir));
        if ($dir eq 'T')
        {
            my $time = time();
            $value1 = $value1 - 65536 if $len1 == 2 && $value1 > 32767;
            my $value = $value1;
            my $readingName1 = $canId;
            $readingName1 = $KM273_elements{$canId}{text} if (exists $KM273_elements{$canId});
            if (exists $KM273_elements{$canId})
            {
                my $format = $KM273_elements{$canId}{format};
                if ($format eq "sw1" || $format eq "sw2")
                {
                    my $timerOn = (($value1 >> 8) & 0x3F);
                    my $timerOff = $value1 & 0x3F;
                    if (($timerOn  & 1) == 1) { $timerOn  = sprintf("%02d:30",$timerOn >>1); } else { $timerOn  = sprintf("%02d:00",$timerOn >>1); }
                    if (($timerOff & 1) == 1) { $timerOff = sprintf("%02d:30",$timerOff>>1); } else { $timerOff = sprintf("%02d:00",$timerOff>>1); }
                    $value = $timerOn . " on " . $timerOff . " off";
                    $value = sprintf("%s %X",$value,$value1) if ($format ne "sw2") && (($value1 & 0xC0C0) != 0);
                }
                elsif ($format eq "t15")
                {
                    $value = sprintf("%02d:%02d",$value1 >> 2, ($value1 & 0x3) * 15);
                }
                elsif (defined $KM273_format{$format})
                {
                    if (defined $KM273_format{$format}{'select'})
                    {
                        #Log3 $name, 3, "$name: KM273_Read: format=$format value=$value";
                        my @list = @{$KM273_format{$format}{'select'}};
                        foreach my $elem (@list)
                        {
                            my $idx = index $elem, $value;
                            #Log3 $name, 3, "$name: KM273_Read: format=$format value=$value elem=$elem idx=$idx";
                            if ($idx >= 0)
                            {
                                $value = $elem;
                                last;
                            }
                        }
                    }
                    else
                    {
                        $value = $value1 * $KM273_format{$format}{factor};
                    }
                }
            }
            else
            {
                my $canIdHex = hex $canId;
                my $canIdBas = $canIdHex & 0x3fff;
                my $canIdIdx = ($canIdHex >> 14) & 0x0fff;
                my $canIdHigh = $canIdHex >> 26;
                #$readingName1 = $canIdBas . '.' . $canIdIdx . '.' . $canIdHigh;
            }
            $value = 'DEAD' if ($value1 == -8531);
            if ($readingName1 eq 'DATE_SEC') { next; }
            Log3 $name, 5, "$name: KM273RAW $readingName1 $value";

            if (exists $KM273_history{$canId})
            {
                if (($KM273_history{$canId}{value} != $value1) || ($KM273_history{$canId}{time}+600 <= $time))
                {
                    if (($value1 == 0) || ($value1 == 1) || ($KM273_history{$canId}{time}+60 <= $time))
                    {
                        $KM273_history{$canId} = { 'value' => $value1, 'time' => $time, 'formatedValue' => $value };
                        readingsSingleUpdate($hash, $readingName1, $value, 1);
                    }
                }
            }
            else
            {
                $KM273_history{$canId} = { 'value' => $value1, 'time' => $time, 'formatedValue' => $value};
                readingsSingleUpdate($hash, $readingName1, $value, 1);
            }
        }
    }
    #readingsEndUpdate($hash, 1);

    KM273_GetNextValue($hash);

    return undef;
}

#####################################
sub KM273_GetNextValue($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 4, "$name: KM273_GetNextValue";
    
    return undef if defined($attr{$name}{DoNotPoll}) && ($attr{$name}{DoNotPoll} == 1);

    my $index = $hash->{pollingIndex};
    if ($index < @KM273_readingsRTR)
    {
        my $canId = $KM273_readingsRTR[$index];
        CAN_Write($hash, "R".$canId."0");
        Log3 $name, 5, "$name: KM273_GetNextValue $index Id $canId";
        $hash->{pollingIndex}++;
    }
}

#####################################
sub KM273_GetReadings($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 4, "$name: KM273_GetReadings";

    ### Stop the current timer
    RemoveInternalTimer($hash);

    if ($hash->{pollingIndex} < 0)
    {

    }

    if($hash->{STATE} eq "opened")
    {
        $hash->{pollingIndex} = 0;
        KM273_GetNextValue($hash);
    }

    InternalTimer(gettimeofday()+60, "KM273_GetReadings", $hash, 0);
}

#####################################
sub KM273_Ready($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: KM273_Ready";

  return DevIo_OpenDev($hash, 1, "CAN_DoInit") if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}


#####################################
sub CAN_Write($$)
{
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: CAN_Write $data";

    DevIo_SimpleWrite($hash, $data."\r", 0);

    return undef;
}

my @CAN_BufferIn = ();

#####################################
sub CAN_ReadBuffer($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: CAN_ReadBuffer";

    my $buf = DevIo_SimpleRead($hash);
    return undef if(!defined($buf));

    my @values = split('\r',$buf);

    my $C1 = substr($values[0],0,1);
    my $C1IsNum = (($C1 ge '0') && ($C1 le '9')) || (($C1 ge 'A') && ($C1 le 'F'));

    if ($C1IsNum)
    {
        my $last .= shift @values;
        $CAN_BufferIn[$#CAN_BufferIn] .= $last if ($#CAN_BufferIn >= 0);
    }

    push @CAN_BufferIn, @values;

    return undef;
}

#####################################
sub CAN_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: CAN_Read";

    while (@CAN_BufferIn > 0)
    {
        my ($id,$len,$data);
        my $recv = shift @CAN_BufferIn;
        my $dir = substr($recv,0,1);

        Log3 $name, 5, "$name: CAN_Read recv $recv";

        if (($dir eq 'T') || ($dir eq 'R'))
        {
            if (length $recv >= 10)
            {
                ($dir,$id,$len,$data) = unpack "A1A8A1A*", $recv;
                $len = hex $len;
                if (length $data >= 2 * $len)
                {
                    $len = hex $len;
                    $data = hex substr($data,0,2*$len);
                    Log3 $name, 4, "$name: CAN_Read recv $dir $id $len $data";
                    return ($dir,$id,$len,$data);
                }
            }
            if (scalar @CAN_BufferIn == 0)
            {
                push @CAN_BufferIn, $recv;
                return undef;
            }
        }
        elsif (($dir eq 't') || ($dir eq 'r'))
        {
            if (length $recv >= 5)
            {
                ($dir,$id,$len,$data) = unpack "A1A3A1A*", $recv;
                $len = hex $len;
                if (length $data >= 2 * $len)
                {
                    $len = hex $len;
                    $data = hex substr($data,0,2*$len);
                    Log3 $name, 4, "$name: CAN_Read recv $dir $id $len $data";
                    return ($dir,$id,$len,$data) ;
                }
            }
            if (scalar @CAN_BufferIn == 0)
            {
                push @CAN_BufferIn, $recv;
                return undef;
            }
        }

        if ($dir eq 'Z')
        {
            Log3 $name, 5, "$name: CAN_Read recv Z";
        }
        elsif ($recv ne '') 
        {
            Log3 $name, 3, "$name: CAN_Read unknown data '$recv'";
        }
    }
    return undef;
}

#####################################
sub CAN_Close($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: CAN_Close";

    DevIo_SimpleWrite($hash, "C\rC\rC\r", 0);
    DevIo_CloseDev($hash);
    return undef;
}

#####################################
sub CAN_DoInit($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: CAN_DoInit";

    DevIo_DoSimpleRead($hash);
    DevIo_SimpleWrite($hash, "C\rS4\rO\r", 0);
    return undef;
}

1;

=pod
=item summary    commumication modul for buderus logatherm wps heat pump
=item summary_DE Kommunicationsmodul fuer Buderus Logatherm Waermepumpe
=begin html

<a name="KM273"></a>
<h3>KM273</h3>
<ul>
    <i>KM273</i> implements the can bus communication with the buderus logatherm wps heat pump<br>
    The software expect an SLCAN compatible module like USBtin
    <br><br>
    <a name="KM273define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; KM273 &lt;device&gt;</code>
        <br><br>
        Example: <code>define myKM273 KM273 /dev/ttyACM0@115200</code>
        <br><br>
    </ul>
    <br>

    <a name="KM273set"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        Example:<br>
        <code>set myKM273 DHW_TIMEPROGRAM 1</code><br>
        <code>set myKM273 DHW_TIMEPROGRAM Always_On</code><br>
        <br>
        You can <i>set</i> any value to any of the following options.
        <br><br>
        Options:
        <ul>
              <li><i>DHW_CALCULATED_SETPOINT_TEMP</i><br>
                  preset hot water temperature</li>
              <li><i>DHW_TIMEPROGRAM</i><br>
                  select: '0' or 'Always_On', '1' or 'Program_1', '2' or 'Program_2'</li>
              <li><i>DHW_PROGRAM_MODE</i><br>
                  select: '0' or 'Automatic', '1' or 'Always_On', '2' or 'Always_Off'</li>
              <li><i>HEATING_SEASON_MODE</i><br>
                  select: '0' or 'Automatic', '1' or 'Always_On', '2' or 'Always_Off'</li>
              <li><i>DHW_PROGRAM_1_1MON .. ROOM_PROGRAM_1_7SUN</i><br>
                  value: 06:00 on 21:00 off </li>
              <li><i>DHW_PROGRAM_2_1MON .. ROOM_PROGRAM_2_7SUN</i><br>
                  value: 06:00 on 21:00 off </li>
              <li><i>PUMP_DHW_PROGRAM1_START_TIME .. PUMP_DHW_PROGRAM4_STOP_TIME</i><br>
                  dayly program for switching on and off the hot water circulation pump<br>
                  you can set 4 time ranges where the pump should be switched on
                  value: xx:xx</li>
              <li><i>ROOM_TIMEPROGRAM</i><br>
                  time program for circuit 1<br>
                  select: '0' or 'HP_Optimized', '1' or 'Program_1', '2' or 'Program_2', '3' or 'Family', '4' or 'Morning', '5' or 'Evening', '6' or 'Seniors'</li>
              <li><i>ROOM_PROGRAM_MODE</i><br>
                  room program for circuit 1<br>
                  select: '0' or 'Automatic', '1' or 'Normal', '2' or 'Exception', '3' or 'HeatingOff'</li>
              <li><i>ROOM_PROGRAM_1_1MON .. ROOM_PROGRAM_1_7SUN</i><br>
                  times of Program_1 for circuit 1<br>
                  value: 06:00 on 21:00 off </li>
              <li><i>ROOM_PROGRAM_2_1MON .. ROOM_PROGRAM_2_7SUN</i><br>
                  times of Program_2 for circuit 1<br>
                  value: 06:00 on 21:00 off </li>
              <li><i>MV_E12_EEPROM_TIME_PROGRAM</i><br>
                  time program for circuit 2<br>
                  select: '0' or 'HP_Optimized', '1' or 'Program_1', '2' or 'Program_2', '3' or 'Family', '4' or 'Morning', '5' or 'Evening', '6' or 'Seniors'</li>
              <li><i>MV_E12_EEPROM_ROOM_PROGRAM_MODE</i><br>
                  room program for circuit 2<br>
                  select: '0' or 'Automatic', '1' or 'Normal', '2' or 'Exception', '3' or 'HeatingOff'</li>
              <li><i>MV_E12_EEPROM_TIME_PROGRAM_1_1MON .. MV_E12_EEPROM_TIME_PROGRAM_1_7SUN</i><br>
                  times of Program_1 for circuit 2<br>
                  value: 06:00 on 21:00 off </li>
              <li><i>MV_E12_EEPROM_TIME_PROGRAM_2_1MON .. MV_E12_EEPROM_TIME_PROGRAM_2_7SUN</i><br>
                  times of Program_2 for circuit 2<br>
                  value: 06:00 on 21:00 off </li>
              <li><i>XDHW_STOP_TEMP</i><br>
                  extra hot water temperature</li>
              <li><i>XDHW_TIME</i><br>
                  hours for extra hot water</li>
        </ul>
    </ul>
    <br>

    <a name="KM273get"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        You can <i>get</i> the value of any of the options described in
        <a href="#KM273set">paragraph "Set" above</a>. See
        <a href="http://fhem.de/commandref.html#get">commandref#get</a> for more info about
        the get command.
    </ul>
    <br>

    <a name="KM273attr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about
        the attr command.
        <br><br>
        Attributes:
        <ul>
            <li><i>DoNotPoll</i> 0|1<br>
                When you set DoNotPoll to "1", the module is only listening to the telegrams on CAN bus. Default is "0".<br>
            </li>
            <li><i>HeatCircuit2Active</i> 0|1<br>
                When you set HeatCircuit2Active to "1", the module read and set also the values for the second heating circuit E12. Default is "0".<br>
            </li>
            <li><i>AddToReadings</i> List of Variables<br>
              additional variables, which are not polled by the module can by added here<br>
              Example: attr myKM273 AddToReadings GT3_STATUS GT5_STATUS GT5_ANSLUTEN<br>
            </li>
            <li><i>AddToGetSet</i> List of Variables<br>
              additional variables, which are not in get/set list definded by the module can by added here<br>
              Example: attr myKM273 AddToGetSet ACCESS_LEVEL GT3_KORRIGERING GT5_KVITTERAD<br>
            </li>
        </ul>
    </ul>
</ul>

=end html

=cutt
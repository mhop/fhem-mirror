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
#       0016    07.06.2017  mike3436            KM273_Set                       message on range exceeded corrected, some code review
#       0016    27.08.2017  mike3436            KM273_Set                       add RAW command to send CAN messages
#       0016    27.08.2017  mike3436            KM273_ReadElementList           on error read element list again after short delay
#       0016    08.01.2018  mike3436            attr ListenOnly                 like DoNotPoll=1 but also table won't be read from heatpump
#       0017    21.01.2018  mike3436            KM273_StoreElementList          function stores element list in json format
#       0017    21.01.2018  mike3436            KM273_LoadElementList           function read external element list from json format, executed on Attribut ListenOnly=1
#       0017    08.05.2018  mike3436            KM273_LoadElementList           JSON library load by 'require' instead 'use' for more compatibility

package main;
use strict;
use warnings;
use Time::HiRes qw( time sleep );

my @KM273_getsBase = (
    'XDHW_STOP_TEMP',
    'XDHW_TIME',
    'DHW_CALCULATED_SETPOINT_TEMP',
    'DHW_TIMEPROGRAM',
    'ROOM_TIMEPROGRAM',
    'ROOM_PROGRAM_MODE',
    'ROOM_PROGRAM_1_5FRI',
    'ROOM_PROGRAM_1_1MON',
    'ROOM_PROGRAM_1_6SAT',
    'ROOM_PROGRAM_1_7SUN',
    'ROOM_PROGRAM_1_4THU',
    'ROOM_PROGRAM_1_2TUE',
    'ROOM_PROGRAM_1_3WED',
    'ROOM_PROGRAM_2_5FRI',
    'ROOM_PROGRAM_2_1MON',
    'ROOM_PROGRAM_2_6SAT',
    'ROOM_PROGRAM_2_7SUN',
    'ROOM_PROGRAM_2_4THU',
    'ROOM_PROGRAM_2_2TUE',
    'ROOM_PROGRAM_2_3WED',
    'DHW_PROGRAM_1_5FRI',
    'DHW_PROGRAM_1_1MON',
    'DHW_PROGRAM_1_6SAT',
    'DHW_PROGRAM_1_7SUN',
    'DHW_PROGRAM_1_4THU',
    'DHW_PROGRAM_1_2TUE',
    'DHW_PROGRAM_1_3WED',
    'DHW_PROGRAM_2_5FRI',
    'DHW_PROGRAM_2_1MON',
    'DHW_PROGRAM_2_6SAT',
    'DHW_PROGRAM_2_7SUN',
    'DHW_PROGRAM_2_4THU',
    'DHW_PROGRAM_2_2TUE',
    'DHW_PROGRAM_2_3WED',
    'DHW_PROGRAM_MODE',
    'HEATING_SEASON_MODE',
    'PUMP_DHW_PROGRAM1_START_TIME',
    'PUMP_DHW_PROGRAM1_STOP_TIME',
    'PUMP_DHW_PROGRAM2_START_TIME',
    'PUMP_DHW_PROGRAM2_STOP_TIME',
    'PUMP_DHW_PROGRAM3_START_TIME',
    'PUMP_DHW_PROGRAM3_STOP_TIME',
    'PUMP_DHW_PROGRAM4_START_TIME',
    'PUMP_DHW_PROGRAM4_STOP_TIME',
    'HOLIDAY_ACTIVE',
    'HOLIDAY_START_DAY',
    'HOLIDAY_START_MONTH',
    'HOLIDAY_START_YEAR',
    'HOLIDAY_STOP_DAY',
    'HOLIDAY_STOP_MONTH',
    'HOLIDAY_STOP_YEAR'
   );

my @KM273_getsAddHC2 = (
    'MV_E12_EEPROM_ROOM_PROGRAM_MODE',
    'MV_E12_EEPROM_TIME_PROGRAM',
    'MV_E12_EEPROM_TIME_PROGRAM_5FRI',
    'MV_E12_EEPROM_TIME_PROGRAM_5FRI_2',
    'MV_E12_EEPROM_TIME_PROGRAM_1MON',
    'MV_E12_EEPROM_TIME_PROGRAM_1MON_2',
    'MV_E12_EEPROM_TIME_PROGRAM_6SAT',
    'MV_E12_EEPROM_TIME_PROGRAM_6SAT_2',
    'MV_E12_EEPROM_TIME_PROGRAM_7SUN',
    'MV_E12_EEPROM_TIME_PROGRAM_7SUN_2',
    'MV_E12_EEPROM_TIME_PROGRAM_4THU',
    'MV_E12_EEPROM_TIME_PROGRAM_4THU_2',
    'MV_E12_EEPROM_TIME_PROGRAM_2TUE',
    'MV_E12_EEPROM_TIME_PROGRAM_2TUE_2',
    'MV_E12_EEPROM_TIME_PROGRAM_3WED',
    'MV_E12_EEPROM_TIME_PROGRAM_3WED_2'
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

my @KM273_elements_default = 
(
    { 'idx' =>    0 , 'extid' => '814A53C66A0802' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ACCESSORIES_CONNECTED_BITMASK' },
    { 'idx' =>    1 , 'extid' => '61E1E1FC660023' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ACCESS_LEVEL' },
    { 'idx' =>    2 , 'extid' => 'A1137CB3EB0B26' , 'max' =>      240 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ACCESS_LEVEL_TIMEOUT_DELAY_TIME' },
    { 'idx' =>    3 , 'extid' => '007B1307040471' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM' },
    { 'idx' =>    4 , 'extid' => '004E2529500481' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM_2' },
    { 'idx' =>    5 , 'extid' => '00392219C60482' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM_3' },
    { 'idx' =>    6 , 'extid' => '00A7468C650483' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALARM_4' },
    { 'idx' =>    7 , 'extid' => '0071C5013102EF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALLOW' },
    { 'idx' =>    8 , 'extid' => '004D59464306BC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ALLOW_XDHW' },
    { 'idx' =>    9 , 'extid' => '00259EEF360272' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCKED' },
    { 'idx' =>   10 , 'extid' => '006D634F6402E8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2' },
    { 'idx' =>   11 , 'extid' => 'E555E4E11002E9' , 'max' =>       40 , 'min' =>      -30 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2_TEMP' },
    { 'idx' =>   12 , 'extid' => 'E23123FC9F02EA' , 'max' =>      180 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2_TIME' },
    { 'idx' =>   14 , 'extid' => 'E5B8B81B2E02EB' , 'max' =>       20 , 'min' =>      -26 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_TIME_CONTROL_TEMPERATURE_LIMIT' },
    { 'idx' =>   15 , 'extid' => 'E1C80ADF0D069E' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_1' },
    { 'idx' =>   16 , 'extid' => 'E151038EB706A1' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_2' },
    { 'idx' =>   17 , 'extid' => 'E12604BE2106A2' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_3' },
    { 'idx' =>   18 , 'extid' => 'E1B8602B8206BD' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CONNECTED_COMPRESSOR_4' },
    { 'idx' =>   19 , 'extid' => '4A9EDFA5490CBA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_CURRENT_EFFECT_LIMITATION' },
    { 'idx' =>   21 , 'extid' => 'E1A12688970225' , 'max' =>      240 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_DELAY_TIME' },
    { 'idx' =>   22 , 'extid' => 'C02D7CE3A909E9' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_DHW_ACKNOWLEDGED' },
    { 'idx' =>   23 , 'extid' => 'EDD21CF87202EE' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_DHW_HYSTERESIS' },
    { 'idx' =>   24 , 'extid' => 'E5311E7EC202ED' , 'max' =>       10 , 'min' =>      -10 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_DHW_TEMP_CHANGE' },
    { 'idx' =>   25 , 'extid' => 'EAE9C03814036E' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EFFECT_LIMITATION_COMPRESSOR' },
    { 'idx' =>   27 , 'extid' => 'EAB88C0518036B' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EFFECT_LIMITATION_DHW' },
    { 'idx' =>   29 , 'extid' => 'EA0F167017036F' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EFFECT_LIMITATION_NO_COMPRESSOR' },
    { 'idx' =>   31 , 'extid' => '217E7826980226' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_ELECTRIC_COUNT' },
    { 'idx' =>   32 , 'extid' => '2AB28E7F270424' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_1' },
    { 'idx' =>   34 , 'extid' => '2A2B872E9D0425' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_2' },
    { 'idx' =>   36 , 'extid' => '2A5C801E0B0426' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_3' },
    { 'idx' =>   38 , 'extid' => '2AC2E48BA80427' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_4' },
    { 'idx' =>   40 , 'extid' => '2A7E1A6660069D' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_1' },
    { 'idx' =>   42 , 'extid' => '2AE71337DA069F' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_2' },
    { 'idx' =>   44 , 'extid' => '2A9014074C06C1' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_3' },
    { 'idx' =>   46 , 'extid' => '2A0E7092EF06A0' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ELECTRIC_SIGNAL_OUT_4' },
    { 'idx' =>   48 , 'extid' => 'C0AB5157E30366' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_LIMITATION' },
    { 'idx' =>   49 , 'extid' => 'E21D07AE5B0758' , 'max' =>      600 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_LIMITATION_TIME' },
    { 'idx' =>   51 , 'extid' => 'E20696EC690364' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_RAMP_DOWN_TIME' },
    { 'idx' =>   53 , 'extid' => 'E2E5F030A80363' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_RAMP_UP_TIME' },
    { 'idx' =>   55 , 'extid' => 'E90DD98AE80365' , 'max' =>      100 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EL_NEUTRALZONE_SIZE' },
    { 'idx' =>   56 , 'extid' => '00CC181667030A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCKED' },
    { 'idx' =>   57 , 'extid' => 'C011831BA40304' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E21_EXT_1' },
    { 'idx' =>   58 , 'extid' => 'C0888A4A1E048C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E21_EXT_2' },
    { 'idx' =>   59 , 'extid' => 'C0206B01390B4E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E22_EXT_1' },
    { 'idx' =>   60 , 'extid' => 'C0B96250830B4D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERN_BLOCK_BY_E22_EXT_2' },
    { 'idx' =>   61 , 'extid' => '0E0794AB25026F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_GTf_AVERAGE' },
    { 'idx' =>   63 , 'extid' => '0E2D19B8A50270' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_GTf_AVERAGE_OLD' },
    { 'idx' =>   65 , 'extid' => 'E2B490501D0367' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_DEFROST_DELAY_TIME' },
    { 'idx' =>   67 , 'extid' => 'E95D82721503B1' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T1_MAX' },
    { 'idx' =>   68 , 'extid' => 'E9870C05F30912' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T1_START' },
    { 'idx' =>   69 , 'extid' => 'E9509210640911' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T8_MAX' },
    { 'idx' =>   70 , 'extid' => 'E91294402003B0' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_T8_START' },
    { 'idx' =>   71 , 'extid' => '01E185D8D10C92' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN' },
    { 'idx' =>   72 , 'extid' => '807FA9F59B0C83' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E21_EXT_1' },
    { 'idx' =>   73 , 'extid' => '80E6A0A4210C8C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E21_EXT_2' },
    { 'idx' =>   74 , 'extid' => '804E41EF060C84' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E22_EXT_1' },
    { 'idx' =>   75 , 'extid' => '80D748BEBC0C85' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_100_EXTERN_BY_E22_EXT_2' },
    { 'idx' =>   76 , 'extid' => '00D8B508CB0C93' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN' },
    { 'idx' =>   77 , 'extid' => '8011C1E2650C87' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E21_EXT_1' },
    { 'idx' =>   78 , 'extid' => '8088C8B3DF0C8A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E21_EXT_2' },
    { 'idx' =>   79 , 'extid' => '802029F8F80C88' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E22_EXT_1' },
    { 'idx' =>   80 , 'extid' => '80B920A9420C89' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_50_EXTERN_BY_E22_EXT_2' },
    { 'idx' =>   81 , 'extid' => 'A9B293795F0CDA' , 'max' =>       90 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E21_EXT_1' },
    { 'idx' =>   82 , 'extid' => 'A92B9A28E50CD2' , 'max' =>       90 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E21_EXT_2' },
    { 'idx' =>   83 , 'extid' => '89837B63C20CD0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E22_EXT_1' },
    { 'idx' =>   84 , 'extid' => '891A7232780CD1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_BY_E22_EXT_2' },
    { 'idx' =>   85 , 'extid' => '093AFAB92E0CD3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_KW_EXTERN' },
    { 'idx' =>   86 , 'extid' => '01BD93F23E0C7E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN' },
    { 'idx' =>   87 , 'extid' => 'A1E12D84300C7A' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E21_EXT_1' },
    { 'idx' =>   88 , 'extid' => 'A17824D58A0C7D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E21_EXT_2' },
    { 'idx' =>   89 , 'extid' => 'A1D0C59EAD0C7B' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E22_EXT_1' },
    { 'idx' =>   90 , 'extid' => 'A149CCCF170C7C' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMIT_PERCENT_EXTERN_BY_E22_EXT_2' },
    { 'idx' =>   91 , 'extid' => '002E38E20103B8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_NEUTRALZONE_DECREASE' },
    { 'idx' =>   92 , 'extid' => '00B73AA32A03B7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_NEUTRALZONE_INCREASE' },
    { 'idx' =>   93 , 'extid' => '0202BF02BA0368' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_NEUTRALZONE_SIGNAL' },
    { 'idx' =>   95 , 'extid' => '0EE200FF460ACF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONE_STEP_START' },
    { 'idx' =>   97 , 'extid' => '0EC7626E190AD0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONE_STEP_STOP' },
    { 'idx' =>   99 , 'extid' => '006C61DE390475' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONLY' },
    { 'idx' =>  100 , 'extid' => 'E1E1264564035D' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONLY_RAMP_TIME' },
    { 'idx' =>  101 , 'extid' => '0092C1864A035F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_ONLY_SIGNAL_RAMP_UP' },
    { 'idx' =>  102 , 'extid' => 'EADBF44D0603DA' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_D' },
    { 'idx' =>  104 , 'extid' => 'EAA54531BB0371' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_I' },
    { 'idx' =>  106 , 'extid' => 'E69CEDCFAD0568' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_MAX' },
    { 'idx' =>  108 , 'extid' => 'E6A0E0F0F40569' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_MIN' },
    { 'idx' =>  110 , 'extid' => 'EAC12E997B0370' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PID_P' },
    { 'idx' =>  112 , 'extid' => '00AE75211705AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_ALLOW' },
    { 'idx' =>  113 , 'extid' => 'E28C6BDACD0567' , 'max' =>     1200 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_DELAY_TIME' },
    { 'idx' =>  115 , 'extid' => 'E1CBBD4F6E0690' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_MODE' },
    { 'idx' =>  116 , 'extid' => 'E10C545F0B05B0' , 'max' =>       30 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_RAMP_DOWN_TIME' },
    { 'idx' =>  117 , 'extid' => 'E12F4A191405AF' , 'max' =>       30 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_POOL_RAMP_UP_TIME' },
    { 'idx' =>  118 , 'extid' => 'C2823936FB02F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_FRI' },
    { 'idx' =>  120 , 'extid' => 'C2EF6420A502F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_MON' },
    { 'idx' =>  122 , 'extid' => 'C29A3D7A2B02F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_SAT' },
    { 'idx' =>  124 , 'extid' => 'C249F1540402F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_SUN' },
    { 'idx' =>  126 , 'extid' => 'C239B7E77102F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_THU' },
    { 'idx' =>  128 , 'extid' => 'C2DB6C9B0902F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_TUE' },
    { 'idx' =>  130 , 'extid' => 'C2E4EF079702F5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_PROGRAM_1_WED' },
    { 'idx' =>  132 , 'extid' => '000E7D2BD10275' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_RAMP_DECREASE' },
    { 'idx' =>  133 , 'extid' => '00977F6AFA0274' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_RAMP_INCREASE' },
    { 'idx' =>  134 , 'extid' => '0062413F450276' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_RAMP_INCREASE_DHW' },
    { 'idx' =>  135 , 'extid' => '00C45C8B2900EF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ADDITIONAL_REQUEST' },
    { 'idx' =>  136 , 'extid' => '0AB062530C036C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL' },
    { 'idx' =>  138 , 'extid' => '0A9F59CAF40362' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_FASTKONDENSERING' },
    { 'idx' =>  140 , 'extid' => '0AC60AD71C0369' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_LIMITATION' },
    { 'idx' =>  142 , 'extid' => '0A9B74327B0361' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_NORMAL' },
    { 'idx' =>  144 , 'extid' => '0A38B75244035E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_ONLY' },
    { 'idx' =>  146 , 'extid' => '0A361A0A65036A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_PID' },
    { 'idx' =>  148 , 'extid' => '0A77FFC89205E1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SIGNAL_POOL' },
    { 'idx' =>  150 , 'extid' => 'E03EA16AD70781' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TIMEPROGRAM' },
    { 'idx' =>  151 , 'extid' => 'C0292D044B063D' , 'max' => 83886080 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TIMER_EVU_ECONOMY_MODE' },
    { 'idx' =>  152 , 'extid' => '0055F40C3F0271' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TIME_CONTROL_BLOCK' },
    { 'idx' =>  153 , 'extid' => 'EA4E687ACB036D' , 'max' =>      135 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TOTAL_EFFECT_PATRON' },
    { 'idx' =>  155 , 'extid' => 'C09241BB5C02EC' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_USER_BLOCKED' },
    { 'idx' =>  156 , 'extid' => 'C04081661B00F1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_USER_ONLY' },
    { 'idx' =>  157 , 'extid' => 'C0467902B40360' , 'max' =>167772160 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_USE_NEUTRALZONE_REGULATOR' },
    { 'idx' =>  158 , 'extid' => '000445723003B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_ALLOW' },
    { 'idx' =>  159 , 'extid' => 'E11214DDA003B6' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_CLOSE_TIME' },
    { 'idx' =>  160 , 'extid' => 'E156B1386603C1' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_DELAY_TIME' },
    { 'idx' =>  161 , 'extid' => '0AEA24380D0558' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_MEASUREMENT' },
    { 'idx' =>  163 , 'extid' => 'E1F95E6C7603B5' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_OPEN_TIME' },
    { 'idx' =>  164 , 'extid' => 'E27C7972AA03B4' , 'max' =>     1200 , 'min' =>       60 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_RUNNING_TIME' },
    { 'idx' =>  166 , 'extid' => '22C710E3E906C4' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_VALVE_SIGNAL' },
    { 'idx' =>  168 , 'extid' => '8178B456B506BE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_BOOT_COUNT' },
    { 'idx' =>  169 , 'extid' => '003F8061CD02AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED' },
    { 'idx' =>  170 , 'extid' => '00F0CCC5A90428' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_2' },
    { 'idx' =>  171 , 'extid' => '0087CBF53F0429' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_3' },
    { 'idx' =>  172 , 'extid' => '0019AF609C042A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_4' },
    { 'idx' =>  173 , 'extid' => '814669B75C063C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_CONNECTED_BITMASK' },
    { 'idx' =>  174 , 'extid' => '127C8850DE02AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION' },
    { 'idx' =>  176 , 'extid' => '12C0FDC709042B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION_2' },
    { 'idx' =>  178 , 'extid' => '12B7FAF79F042C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION_3' },
    { 'idx' =>  180 , 'extid' => '12299E623C042D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB0016_VERSION_4' },
    { 'idx' =>  182 , 'extid' => '00210FED0F0024' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB9012_CONNECTED' },
    { 'idx' =>  183 , 'extid' => '12BCCD3B430025' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'AHB9012_VERSION' },
    { 'idx' =>  185 , 'extid' => 'EAA75D6F5600BC' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ALARM_MODE_DELAY_TIME' },
    { 'idx' =>  187 , 'extid' => '0079BAA67B00BB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'ALARM_MODE_REQUEST' },
    { 'idx' =>  188 , 'extid' => '01C8CB95950D6D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BACKWARDS_COMPABILITY_DUMMY' },
    { 'idx' =>  189 , 'extid' => '452053AEAB082C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BIVALENCE_POINT' },
    { 'idx' =>  190 , 'extid' => 'C0F9D977AE0027' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_BLOCKED' },
    { 'idx' =>  191 , 'extid' => 'C2C2CD4F410028' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_BLOCK_START_TIME' },
    { 'idx' =>  193 , 'extid' => 'C2D6B5878C0029' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_BLOCK_STOP_TIME' },
    { 'idx' =>  195 , 'extid' => 'E10306B5220026' , 'max' =>       10 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_DELAY_TIME' },
    { 'idx' =>  196 , 'extid' => 'E2FE5D4E50002A' , 'max' =>     3600 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'BUZZER_INTERVAL' },
    { 'idx' =>  198 , 'extid' => 'A1D20884C30B9F' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DELTA_DHW' },
    { 'idx' =>  199 , 'extid' => 'A12A7C97D20BA1' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DELTA_HEATING' },
    { 'idx' =>  200 , 'extid' => '816686E05C0BB3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DHW_MEAN_VALUE' },
    { 'idx' =>  201 , 'extid' => '81929827B90BC8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_DHW_MEAN_VALUE_CASCADE' },
    { 'idx' =>  202 , 'extid' => '002A5577090BD0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_GET_MEAN_VALUE' },
    { 'idx' =>  203 , 'extid' => '81E75046470BB4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_HEATING_MEAN_VALUE' },
    { 'idx' =>  204 , 'extid' => '81DFD38A800BC9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_HEATING_MEAN_VALUE_CASCADE' },
    { 'idx' =>  205 , 'extid' => 'A1D15B54A10BA3' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_IDLE_SPEED' },
    { 'idx' =>  206 , 'extid' => '0E78469DDB0BC2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_PID_CALCULATED_MEASUREMENT' },
    { 'idx' =>  208 , 'extid' => '0EEF76AB9E0BC0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_PID_SETPOINT' },
    { 'idx' =>  210 , 'extid' => '0177EF6F200BBC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_SIGNAL' },
    { 'idx' =>  211 , 'extid' => 'A1238E3ECC0CAE' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E21_G2_USER_SET_PERCENT' },
    { 'idx' =>  212 , 'extid' => 'A1AE69A1180BB8' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DELTA_DHW' },
    { 'idx' =>  213 , 'extid' => 'A1C0FA4AB00BB9' , 'max' =>       15 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DELTA_HEATING' },
    { 'idx' =>  214 , 'extid' => '81C5D066F50BBE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DHW_MEAN_VALUE' },
    { 'idx' =>  215 , 'extid' => '81210C0A7A0BCA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_DHW_MEAN_VALUE_CASCADE' },
    { 'idx' =>  216 , 'extid' => '008903F1A00BD1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_GET_MEAN_VALUE' },
    { 'idx' =>  217 , 'extid' => '8191B57F7A0BBF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_HEATING_MEAN_VALUE' },
    { 'idx' =>  218 , 'extid' => '81CCFBB3F30BCB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_HEATING_MEAN_VALUE_CASCADE' },
    { 'idx' =>  219 , 'extid' => 'A1C0263ED80BBA' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_IDLE_SPEED' },
    { 'idx' =>  220 , 'extid' => '0E6B6EA4A80BC3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_PID_CALCULATED_MEASUREMENT' },
    { 'idx' =>  222 , 'extid' => '0EBCECF01A0BC1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_PID_SETPOINT' },
    { 'idx' =>  224 , 'extid' => '01EE0D09210BBD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_SIGNAL' },
    { 'idx' =>  225 , 'extid' => 'A15890BC2F0CB0' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E22_G2_USER_SET_PERCENT' },
    { 'idx' =>  226 , 'extid' => '00BA9D50780AC8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_E74_G1_DIGITAL' },
    { 'idx' =>  227 , 'extid' => 'A11E2049670C98' , 'max' =>       20 , 'min' =>        3 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_DELTA_DHW_AT_LOW_T12' },
    { 'idx' =>  228 , 'extid' => 'EA70F2D7870BAA' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_D' },
    { 'idx' =>  230 , 'extid' => 'EA0E43AB3A0BA8' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_I' },
    { 'idx' =>  232 , 'extid' => 'EEAEAFB7FB0BAC' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_MAX' },
    { 'idx' =>  234 , 'extid' => 'AE92A288A20BAE' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_MIN' },
    { 'idx' =>  236 , 'extid' => 'EA6A2803FA0BA6' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_PID_P' },
    { 'idx' =>  238 , 'extid' => 'A96F5A7BEB0BB2' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_VOLTAGE_AT_0' },
    { 'idx' =>  239 , 'extid' => 'A9C3D9935E0BB0' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CIRCULATION_G2_VOLTAGE_AT_100' },
    { 'idx' =>  240 , 'extid' => '008A02C3120B8F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_BASECARD_E21_RESTART_DETECTED' },
    { 'idx' =>  241 , 'extid' => '0060841E700B90' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_BASECARD_E22_RESTART_DETECTED' },
    { 'idx' =>  242 , 'extid' => '014C6EDFE60B72' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_FAILED_SENDINGS' },
    { 'idx' =>  243 , 'extid' => '01F7194E700D57' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMMUNICATION_SEND_SEC_ROOMSENSOR_STATUS' },
    { 'idx' =>  244 , 'extid' => '01F31C60B8046B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSORS_CONNECTED_COUNT' },
    { 'idx' =>  245 , 'extid' => '0018D2D12D00B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_ALARM' },
    { 'idx' =>  246 , 'extid' => '0065D3A29B0484' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_ALARM_2' },
    { 'idx' =>  247 , 'extid' => '000E6864FD0476' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_BLOCKED' },
    { 'idx' =>  248 , 'extid' => '005FE0363D0A2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_BLOCKED_2' },
    { 'idx' =>  249 , 'extid' => '162F92312F0A7A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS' },
    { 'idx' =>  251 , 'extid' => '16F7EF15210A7B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS_2' },
    { 'idx' =>  253 , 'extid' => '16654560AA0A7C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS_FILTERED' },
    { 'idx' =>  255 , 'extid' => '16AD77529A0A7D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_CALC_HOTGAS_FILTERED_2' },
    { 'idx' =>  257 , 'extid' => 'C1980C123400B0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_FREQUENCY_MAX' },
    { 'idx' =>  258 , 'extid' => 'C1A4012D6D00B1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_FREQUENCY_MIN' },
    { 'idx' =>  259 , 'extid' => 'C1C61B2E0400AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_T1_SETPOINT_MAX' },
    { 'idx' =>  260 , 'extid' => 'C1FA16115D00AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_COP_T1_SETPOINT_MIN' },
    { 'idx' =>  261 , 'extid' => '01A00CFA280252' , 'max' =>      230 , 'min' =>      400 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_DHW_REQUEST' },
    { 'idx' =>  262 , 'extid' => '00F55C2F800303' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCKED' },
    { 'idx' =>  263 , 'extid' => 'C092971E2F0309' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E21_EXT_1' },
    { 'idx' =>  264 , 'extid' => 'C00B9E4F95048B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E21_EXT_2' },
    { 'idx' =>  265 , 'extid' => 'C0A37F04B20B4B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E22_EXT_1' },
    { 'idx' =>  266 , 'extid' => 'C03A7655080B4C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E21_EXTERN_BLOCK_BY_E22_EXT_2' },
    { 'idx' =>  267 , 'extid' => '00DC949B720B29' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCKED' },
    { 'idx' =>  268 , 'extid' => 'C0210333EC0B75' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E21_EXT_1' },
    { 'idx' =>  269 , 'extid' => 'C0B80A62560B76' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E21_EXT_2' },
    { 'idx' =>  270 , 'extid' => 'C010EB29710B77' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E22_EXT_1' },
    { 'idx' =>  271 , 'extid' => 'C089E278CB0B78' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_EXTERN_BLOCK_BY_E22_EXT_2' },
    { 'idx' =>  272 , 'extid' => '00BA167A090B8E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_E22_RESTART_HANDLING_TRIGGED' },
    { 'idx' =>  273 , 'extid' => '01E2A43EA50251' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'COMPRESSOR_HEATING_REQUEST' },
    { 'idx' =>  274 , 'extid' => 'E18ABA5E9100B4' , 'max' =>       90 , 'min' =>       24 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_MAX_FREQUENCY' },
    { 'idx' =>  275 , 'extid' => 'E1BA260302017A' , 'max' =>      120 , 'min' =>       24 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_MAX_FREQUENCY_DEV' },
    { 'idx' =>  276 , 'extid' => 'E1CAF526E700B5' , 'max' =>       86 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_MIN_FREQUENCY' },
    { 'idx' =>  277 , 'extid' => '00205AC16100B6' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_QUICKSTART' },
    { 'idx' =>  278 , 'extid' => '014AF08A5700AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_REAL_FREQUENCY' },
    { 'idx' =>  279 , 'extid' => 'E16A8A67F000AD' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_RESTART_TIME' },
    { 'idx' =>  280 , 'extid' => 'C1BCC2391E0A63' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE' },
    { 'idx' =>  281 , 'extid' => 'C13F6909F10A64' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_2' },
    { 'idx' =>  282 , 'extid' => 'C1EF785A580B15' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_2_DISPLAY_VALUE' },
    { 'idx' =>  283 , 'extid' => 'C1565C20C20B14' , 'max' =>       13 , 'min' =>        7 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_DISPLAY_VALUE' },
    { 'idx' =>  284 , 'extid' => '8178F2D1C80A78' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_INDEX' },
    { 'idx' =>  285 , 'extid' => '8146DAC5120A79' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_INDEX_2' },
    { 'idx' =>  286 , 'extid' => 'E95C34D4210A75' , 'max' =>      170 , 'min' =>       60 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_LW' },
    { 'idx' =>  287 , 'extid' => 'E9B90C5DFE0A76' , 'max' =>      170 , 'min' =>       60 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_SIZE_LW_2' },
    { 'idx' =>  288 , 'extid' => '00F334C27F00B7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START' },
    { 'idx' =>  289 , 'extid' => 'E10A600FE900B9' , 'max' =>       80 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STARTUP_FREQUENCY' },
    { 'idx' =>  290 , 'extid' => 'E1A47B5B1C00B8' , 'max' =>       10 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STARTUP_TIME' },
    { 'idx' =>  291 , 'extid' => '0069E037750692' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_2' },
    { 'idx' =>  292 , 'extid' => 'E2E5F581E50346' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_DELAY_TIME' },
    { 'idx' =>  294 , 'extid' => '01CFDE450B00B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STATE' },
    { 'idx' =>  295 , 'extid' => '01516FA1EE0664' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STATE_2' },
    { 'idx' =>  296 , 'extid' => 'E1C7DC4A5D0857' , 'max' =>        2 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_TYPE' },
    { 'idx' =>  297 , 'extid' => 'E12D314EAF0858' , 'max' =>        2 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_TYPE_2' },
    { 'idx' =>  298 , 'extid' => 'C06BA159820867' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_USE_START_DELAY_TIME' },
    { 'idx' =>  299 , 'extid' => 'C183AEA732025B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'CONFIGURATION' },
    { 'idx' =>  300 , 'extid' => 'E1AD68C52C0672' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CONFIGURATION_BUDERUS' },
    { 'idx' =>  301 , 'extid' => 'E168431B5E00BA' , 'max' =>       30 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COOLING_FAN_STOP_DELAY_TIME' },
    { 'idx' =>  302 , 'extid' => '826C36377C0B7F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COUNTRY' },
    { 'idx' =>  304 , 'extid' => '82DE2C76BC0B0A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CPU_BOOT_COUNTER' },
    { 'idx' =>  306 , 'extid' => 'E5778117E50240' , 'max' =>       20 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'CRANKCASE_HEATER_BLOCK_TEMP' },
    { 'idx' =>  307 , 'extid' => '214D9712D5035B' , 'max' =>        7 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'CURRENT_M_VALVE' },
    { 'idx' =>  308 , 'extid' => '0132AD5D97002B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_DAY' },
    { 'idx' =>  309 , 'extid' => '016D8A0DD9002C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_DAY_OF_WEEK' },
    { 'idx' =>  310 , 'extid' => '01D5C3A951002D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_HOUR' },
    { 'idx' =>  311 , 'extid' => '01767669D7002E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_MIN' },
    { 'idx' =>  312 , 'extid' => '013875E083002F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_MONTH' },
    { 'idx' =>  313 , 'extid' => '01B2CAD41C0030' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_SEC' },
    { 'idx' =>  314 , 'extid' => '011E5FCB280031' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DATE_YEAR' },
    { 'idx' =>  315 , 'extid' => 'E1478EE36601EB' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_0_DELTA_TEMPERATURE' },
    { 'idx' =>  316 , 'extid' => 'E1BE893A89067B' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_0_DELTA_TEMPERATURE_2' },
    { 'idx' =>  317 , 'extid' => '00594AFA3802D1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BATTERY' },
    { 'idx' =>  318 , 'extid' => '00FEDAFC570671' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BATTERY_2' },
    { 'idx' =>  319 , 'extid' => 'E1DB78084F01F6' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_DELAY_TIME' },
    { 'idx' =>  320 , 'extid' => 'E1CD1702640686' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_DELAY_TIME_2' },
    { 'idx' =>  321 , 'extid' => '0028AC53CD02D2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE' },
    { 'idx' =>  322 , 'extid' => '00381B83050678' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE_2' },
    { 'idx' =>  323 , 'extid' => '00E31CF38F0A84' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE_2_CLOSING_DOWN' },
    { 'idx' =>  324 , 'extid' => '00A95A4B5A0A83' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_CYCLE_CLOSING_DOWN' },
    { 'idx' =>  325 , 'extid' => 'E2E90063A40A86' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_4_WAY_VALVE_2_SWITCH' },
    { 'idx' =>  327 , 'extid' => 'E285CADF680A7F' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_4_WAY_VALVE_SWITCH' },
    { 'idx' =>  329 , 'extid' => 'E2364CF4D30A85' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_COMPRESSOR_2_START' },
    { 'idx' =>  331 , 'extid' => 'E2534223110A80' , 'max' =>      900 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELAY_COMPRESSOR_START' },
    { 'idx' =>  333 , 'extid' => '0EA7DC84360254' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_T12_T11' },
    { 'idx' =>  335 , 'extid' => '0ED7E473740687' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_T12_T11_2' },
    { 'idx' =>  337 , 'extid' => 'EE68A7B8090255' , 'max' =>      300 , 'min' =>       10 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TEMPERATURE' },
    { 'idx' =>  339 , 'extid' => 'EEA055EAB4067C' , 'max' =>      300 , 'min' =>       10 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TEMPERATURE_2' },
    { 'idx' =>  341 , 'extid' => 'E2FF8EAB6D01E5' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIME' },
    { 'idx' =>  343 , 'extid' => 'E2257A92E00688' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIME_2' },
    { 'idx' =>  345 , 'extid' => '00A5BB73C4027E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN' },
    { 'idx' =>  346 , 'extid' => '00D2B795930670' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_2' },
    { 'idx' =>  347 , 'extid' => '016189FB34027F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_COUNTER' },
    { 'idx' =>  348 , 'extid' => '012568BB0E0680' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_COUNTER_2' },
    { 'idx' =>  349 , 'extid' => 'E11D66580701FC' , 'max' =>        8 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_INTERVAL_COUNTER' },
    { 'idx' =>  350 , 'extid' => 'E19EDC50830682' , 'max' =>        8 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_INTERVAL_COUNTER_2' },
    { 'idx' =>  351 , 'extid' => 'E50E01998A01FF' , 'max' =>        0 , 'min' =>      -40 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TEMPERATURE_LIMIT' },
    { 'idx' =>  352 , 'extid' => 'E5FC9257C40683' , 'max' =>        0 , 'min' =>      -40 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TEMPERATURE_LIMIT_2' },
    { 'idx' =>  353 , 'extid' => 'E17B401DDE01FE' , 'max' =>       15 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIME' },
    { 'idx' =>  354 , 'extid' => 'E1C890FDEC0681' , 'max' =>       15 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIME_2' },
    { 'idx' =>  355 , 'extid' => 'EE72EB12CC01F0' , 'max' =>      400 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_GT11_STOP' },
    { 'idx' =>  357 , 'extid' => 'EE20DB99050685' , 'max' =>      400 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_GT11_STOP_2' },
    { 'idx' =>  359 , 'extid' => '203642ECD7027D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MANUAL_START' },
    { 'idx' =>  360 , 'extid' => '20D3E8C92D0689' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MANUAL_START_2' },
    { 'idx' =>  361 , 'extid' => 'A14A30D6610C77' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS' },
    { 'idx' =>  362 , 'extid' => 'A1A77B65D30C78' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS_2' },
    { 'idx' =>  363 , 'extid' => 'E1F3A5E00E01F1' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIME' },
    { 'idx' =>  364 , 'extid' => 'E18AA43EB70684' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIME_2' },
    { 'idx' =>  365 , 'extid' => 'E151AA9F3D01ED' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS10_DELTA_TEMPERATURE' },
    { 'idx' =>  366 , 'extid' => 'E1BE759525067E' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS10_DELTA_TEMPERATURE_2' },
    { 'idx' =>  367 , 'extid' => 'E1FE03D2F702CF' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS20_DELTA_TEMPERATURE' },
    { 'idx' =>  368 , 'extid' => 'E1870D3865067F' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MINUS20_DELTA_TEMPERATURE_2' },
    { 'idx' =>  369 , 'extid' => 'E53A13971A027C' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_OUT_START_TEMPERATURE' },
    { 'idx' =>  370 , 'extid' => 'E56A6BC4CB068A' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_OUT_START_TEMPERATURE_2' },
    { 'idx' =>  371 , 'extid' => 'E12B1071C201E9' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_PLUS10_DELTA_TEMPERATURE' },
    { 'idx' =>  372 , 'extid' => 'E16AE3DD92067D' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_PLUS10_DELTA_TEMPERATURE_2' },
    { 'idx' =>  373 , 'extid' => 'E2E83A284101F5' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_QUIT_DELAY_TIME' },
    { 'idx' =>  375 , 'extid' => 'E268FA3C60068B' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_QUIT_DELAY_TIME_2' },
    { 'idx' =>  377 , 'extid' => '01B2F3810902D0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_REQUEST' },
    { 'idx' =>  378 , 'extid' => '01FF50B8E8068C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_REQUEST_2' },
    { 'idx' =>  379 , 'extid' => '0062329BE402B4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_BLOCKED' },
    { 'idx' =>  380 , 'extid' => 'C0016372BE05C1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_BLOCK_SWITCH_TO_HEATING' },
    { 'idx' =>  381 , 'extid' => '020E51A0000CA7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_E21_T3_START_TEMP_SEC_PER_TENTH_ADJ' },
    { 'idx' =>  383 , 'extid' => '02554611150CA8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_E22_T3_START_TEMP_SEC_PER_TENTH_ADJ' },
    { 'idx' =>  385 , 'extid' => 'EE5991A93A02B8' , 'max' =>      700 , 'min' =>      400 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_CALCULATED_SETPOINT_TEMP' },
    { 'idx' =>  387 , 'extid' => 'EE38A21E6702B9' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_CALCULATED_SETPOINT_TEMP_OFFSET' },
    { 'idx' =>  389 , 'extid' => 'A109D86C650CA6' , 'max' =>       24 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_T3_DHW_LOADING_INTERVAL' },
    { 'idx' =>  390 , 'extid' => '8E27406FC50CA4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_CALCULATED_T3_START_TEMP_MIN_VALUE' },
    { 'idx' =>  392 , 'extid' => 'C1EE64B5700106' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_FREQUENCY_MAX' },
    { 'idx' =>  393 , 'extid' => 'C1D2698A290107' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_FREQUENCY_MIN' },
    { 'idx' =>  394 , 'extid' => 'C50188E15E0104' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_GT8_MAX' },
    { 'idx' =>  395 , 'extid' => 'C53D85DE070105' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_GT8DIFF_GT8_MIN' },
    { 'idx' =>  396 , 'extid' => 'C165168E69010A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_FREQUENCY_MAX' },
    { 'idx' =>  397 , 'extid' => 'C1591BB130010B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_FREQUENCY_MIN' },
    { 'idx' =>  398 , 'extid' => 'C5D1D8285F0108' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_GT2_MAX' },
    { 'idx' =>  399 , 'extid' => 'C5EDD517060109' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_COMPRESSOR_HEATING_GT2_MIN' },
    { 'idx' =>  400 , 'extid' => '40A21CB6040B17' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP' },
    { 'idx' =>  401 , 'extid' => 'E10BD3703C0B1B' , 'max' =>       10 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    { 'idx' =>  402 , 'extid' => 'E96A54E9FD0B1A' , 'max' =>      100 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP_DIFF' },
    { 'idx' =>  403 , 'extid' => '56F99731110B21' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E21_COMPRESSOR_TEMPORARY_STOP_SAVED_GT3' },
    { 'idx' =>  405 , 'extid' => '4011889BC70B18' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP' },
    { 'idx' =>  406 , 'extid' => 'E150C4C1290B1C' , 'max' =>       10 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    { 'idx' =>  407 , 'extid' => 'E9A34BE1420B19' , 'max' =>      100 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP_DIFF' },
    { 'idx' =>  408 , 'extid' => '56A3F60E710B22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_E22_COMPRESSOR_TEMPORARY_STOP_SAVED_GT3' },
    { 'idx' =>  410 , 'extid' => '00D3E359CF030B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCKED' },
    { 'idx' =>  411 , 'extid' => 'C084B462440305' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E21_EXT_1' },
    { 'idx' =>  412 , 'extid' => 'C01DBD33FE0B56' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E21_EXT_2' },
    { 'idx' =>  413 , 'extid' => 'C0B55C78D9048D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E22_EXT_1' },
    { 'idx' =>  414 , 'extid' => 'C02C5529630B55' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_EXTERN_BLOCK_BY_E22_EXT_2' },
    { 'idx' =>  415 , 'extid' => 'EEB4A6964D02B6' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_MAX_TEMP' },
    { 'idx' =>  417 , 'extid' => 'EEE896B17B0654' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_START_MAX_TEMP_2' },
    { 'idx' =>  419 , 'extid' => '0EFA512A7A00FD' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP' },
    { 'idx' =>  421 , 'extid' => '0EBA46A01F066C' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_START_TEMP_2' },
    { 'idx' =>  423 , 'extid' => 'EE70936AA500FF' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_COMFORT' },
    { 'idx' =>  425 , 'extid' => 'EECA3AB29D0658' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_COMFORT_2' },
    { 'idx' =>  427 , 'extid' => 'EE681E964800FE' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_ECONOMY' },
    { 'idx' =>  429 , 'extid' => 'EE95E199860659' , 'max' =>      560 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_START_TEMP_ECONOMY_2' },
    { 'idx' =>  431 , 'extid' => '0E9E09BB7B0CD8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_STOP_MIN_TEMP' },
    { 'idx' =>  433 , 'extid' => '0E245556D40CD9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_STOP_MIN_TEMP_2' },
    { 'idx' =>  435 , 'extid' => '0E5A602AB80100' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT3_STOP_TEMP' },
    { 'idx' =>  437 , 'extid' => '0E438AB5E2066E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT3_STOP_TEMP_2' },
    { 'idx' =>  439 , 'extid' => 'EEA69DB26402B7' , 'max' =>      640 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_MAX_TEMP' },
    { 'idx' =>  441 , 'extid' => 'EE90D3D87A0655' , 'max' =>      640 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT8_STOP_MAX_TEMP_2' },
    { 'idx' =>  443 , 'extid' => '0E7941ADFC0101' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP' },
    { 'idx' =>  445 , 'extid' => '0EA4430A41066D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT8_STOP_TEMP_2' },
    { 'idx' =>  447 , 'extid' => 'EE5DE6FA5D0103' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_COMFORT' },
    { 'idx' =>  449 , 'extid' => 'EEE6506719065A' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_COMFORT_2' },
    { 'idx' =>  451 , 'extid' => 'EE456B06B00102' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_ECONOMY' },
    { 'idx' =>  453 , 'extid' => 'EEB98B4C02065B' , 'max' =>      640 , 'min' =>      210 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT8_STOP_TEMP_ECONOMY_2' },
    { 'idx' =>  455 , 'extid' => 'EEB8CF723C0A60' , 'max' =>      800 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_GT9_STOP_TEMP' },
    { 'idx' =>  457 , 'extid' => 'EE79D5D3C40A5F' , 'max' =>      800 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_GT9_STOP_TEMP_2' },
    { 'idx' =>  459 , 'extid' => 'E1A0277040010D' , 'max' =>       60 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_MAX_TIME' },
    { 'idx' =>  460 , 'extid' => 'C2A3F5F02802C3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_5FRI' },
    { 'idx' =>  462 , 'extid' => 'C2CEA8E67602BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_1MON' },
    { 'idx' =>  464 , 'extid' => 'C2BBF1BCF802C4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_6SAT' },
    { 'idx' =>  466 , 'extid' => 'C2683D92D702C5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_7SUN' },
    { 'idx' =>  468 , 'extid' => 'C2187B21A202C2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_4THU' },
    { 'idx' =>  470 , 'extid' => 'C2FAA05DDA02C0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_2TUE' },
    { 'idx' =>  472 , 'extid' => 'C2C523C14402C1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_1_3WED' },
    { 'idx' =>  474 , 'extid' => 'C2E4558AF802CA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_5FRI' },
    { 'idx' =>  476 , 'extid' => 'C289089CA602C6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_1MON' },
    { 'idx' =>  478 , 'extid' => 'C2FC51C62802CC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_6SAT' },
    { 'idx' =>  480 , 'extid' => 'C22F9DE80702CB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_7SUN' },
    { 'idx' =>  482 , 'extid' => 'C25FDB5B7202C9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_4THU' },
    { 'idx' =>  484 , 'extid' => 'C2BD00270A02C7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_2TUE' },
    { 'idx' =>  486 , 'extid' => 'C28283BB9402C8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_2_3WED' },
    { 'idx' =>  488 , 'extid' => 'E1CAB0771C0952' , 'max' =>        2 , 'min' =>        0 , 'format' => 'dp2' , 'read' => 1 , 'text' => 'DHW_PROGRAM_MODE' },
    { 'idx' =>  489 , 'extid' => 'E14502BDB103E4' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_PROTECTIVE_ANODE_INSTALLED' },
    { 'idx' =>  490 , 'extid' => '0083F0FFFB00FC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'DHW_REQUEST' },
    { 'idx' =>  491 , 'extid' => '006E6756EF0663' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'DHW_REQUEST_2' },
    { 'idx' =>  492 , 'extid' => 'C0F8FDE3EC010C' , 'max' => 83886080 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_STATE_ECONOMY' },
    { 'idx' =>  493 , 'extid' => '00DF862F0B02B5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_TIMECONTROLLED' },
    { 'idx' =>  494 , 'extid' => 'E10B0EFC9F0780' , 'max' =>        2 , 'min' =>        0 , 'format' => 'dp1' , 'read' => 1 , 'text' => 'DHW_TIMEPROGRAM' },
    { 'idx' =>  495 , 'extid' => 'C060DF8D6C0656' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_USER_ENABLED' },
    { 'idx' =>  496 , 'extid' => 'C0EE6CB90D0657' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_USER_ENABLED_2' },
    { 'idx' =>  497 , 'extid' => '066BDDE50F0CEC' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DHW_USER_SET_START_TEMP' },
    { 'idx' =>  499 , 'extid' => '06E3D563010CED' , 'max' =>      790 , 'min' =>      200 , 'format' => 'tem' , 'read' => 0 , 'text' => 'DHW_USER_SET_START_TEMP_2' },
    { 'idx' =>  501 , 'extid' => 'E11FB861C80032' , 'max' =>      100 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'DISPLAY_BACKLIGHT_INTENSITY' },
    { 'idx' =>  502 , 'extid' => '213284225B0BD5' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DISPLAY_CONTRAST' },
    { 'idx' =>  503 , 'extid' => '801BC8CB5E0184' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DISPLAY_TESTED' },
    { 'idx' =>  504 , 'extid' => '017422CA550038' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DRIFTTILLSTAND' },
    { 'idx' =>  505 , 'extid' => '0E114D85F103DD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'DRYOUT_SETPOINT_TEMP' },
    { 'idx' =>  507 , 'extid' => 'C00E5D8D3A0439' , 'max' =>117440512 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DST_ENABLED' },
    { 'idx' =>  508 , 'extid' => '8123C57A880039' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DST_OFFSET' },
    { 'idx' =>  509 , 'extid' => '80C27DB0080A10' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E31_T2_CONNECTED' },
    { 'idx' =>  510 , 'extid' => '6D853E880D0882' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E31_T32_KORRIGERING_GLOBAL' },
    { 'idx' =>  511 , 'extid' => 'C0DAAC0DE90753' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T71_ACKNOWLEDGED' },
    { 'idx' =>  512 , 'extid' => '80D820198007EF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T71_CONNECTED' },
    { 'idx' =>  513 , 'extid' => 'ED87F7528D04B0' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E71_T71_KORRIGERING' },
    { 'idx' =>  514 , 'extid' => '00560E1A0804B1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T71_STATUS' },
    { 'idx' =>  515 , 'extid' => '0E2DD1622104B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E71_T71_TEMP' },
    { 'idx' =>  517 , 'extid' => 'ED3A3D3E4304B8' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T72_KORRIGERING' },
    { 'idx' =>  518 , 'extid' => '00D8811DEB04B9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E71_T72_STATUS' },
    { 'idx' =>  519 , 'extid' => '0EAB45108F04BA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E71_T72_TEMP' },
    { 'idx' =>  521 , 'extid' => 'C0302AD08B07D4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T71_ACKNOWLEDGED' },
    { 'idx' =>  522 , 'extid' => '80C95D73F907F0' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T71_CONNECTED' },
    { 'idx' =>  523 , 'extid' => 'EDD46D090907D5' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E72_T71_KORRIGERING' },
    { 'idx' =>  524 , 'extid' => '002190C8F807D6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T71_STATUS' },
    { 'idx' =>  525 , 'extid' => '0EC6E6D92207D7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E72_T71_TEMP' },
    { 'idx' =>  527 , 'extid' => 'ED69A765C707D8' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'E72_T72_KORRIGERING' },
    { 'idx' =>  528 , 'extid' => '00AF1FCF1B07D9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E72_T72_STATUS' },
    { 'idx' =>  529 , 'extid' => '0E4072AB8C07DA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'E72_T72_TEMP' },
    { 'idx' =>  531 , 'extid' => '84245EE1CB0A5C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'E81_T81_CONNECTED' },
    { 'idx' =>  532 , 'extid' => '8216949C7F0C49' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EEPROM_HEATING_SEASON_START_DELAY_TIME' },
    { 'idx' =>  534 , 'extid' => '8253CCD6040C44' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EEPROM_NEUTRALZON_M_VALVE_LIMIT_TIME' },
    { 'idx' =>  536 , 'extid' => 'A1495778540CAA' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELECTRICAL_CONNECTION_400V' },
    { 'idx' =>  537 , 'extid' => '81A2A7F6370CB5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELECTRICAL_MODE' },
    { 'idx' =>  538 , 'extid' => '80D5D68B790CB6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELECTRICAL_MODE_SELECTED' },
    { 'idx' =>  539 , 'extid' => '00A5F331C0004A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ELSKAP_MAX' },
    { 'idx' =>  540 , 'extid' => 'EEA593EA5F004B' , 'max' =>      900 , 'min' =>      300 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ELSKAP_MAX_TEMP' },
    { 'idx' =>  542 , 'extid' => '0E3F05D925004C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ELSKAP_TEMP' },
    { 'idx' =>  544 , 'extid' => '00950E43610273' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'EL_DHW_REQUEST' },
    { 'idx' =>  545 , 'extid' => '40425EFE1F0A4A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E21_EXT_1' },
    { 'idx' =>  546 , 'extid' => '40DB57AFA50A4B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E21_EXT_2' },
    { 'idx' =>  547 , 'extid' => '4073B6E4820B50' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E22_EXT_1' },
    { 'idx' =>  548 , 'extid' => '40EABFB5380B4F' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENABLE_HIGH_PROTECTION_HS_BY_E22_EXT_2' },
    { 'idx' =>  549 , 'extid' => 'E10DD5DA4F02D9' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_ACKNOWLEDGE_TIME' },
    { 'idx' =>  550 , 'extid' => 'E1D2F3149A02D8' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_AFTER_DHW' },
    { 'idx' =>  551 , 'extid' => '0E3557D0C70C6F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP' },
    { 'idx' =>  553 , 'extid' => '8E30CDBEE80C70' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_20' },
    { 'idx' =>  555 , 'extid' => '8ED3939ECE0C9A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_10' },
    { 'idx' =>  557 , 'extid' => '8EA3F96A410C99' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_15' },
    { 'idx' =>  559 , 'extid' => '8EF8BECD0D0C6D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_20' },
    { 'idx' =>  561 , 'extid' => '8E4D6D81680C6C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_MAX_TEMP_AT_MINUS_5' },
    { 'idx' =>  563 , 'extid' => '00301E92E30C71' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_STOP' },
    { 'idx' =>  564 , 'extid' => '80ED3D05F40C6E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_CURVE_STOP_FUNCTION_ACTIVE' },
    { 'idx' =>  565 , 'extid' => 'A195D2E6790C95' , 'max' =>       70 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_MAX_OUTDOOR_TEMP' },
    { 'idx' =>  566 , 'extid' => 'E5D1CEC0E902D4' , 'max' =>       10 , 'min' =>      -20 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_MAX_TEMPERATURE' },
    { 'idx' =>  567 , 'extid' => 'E5CB75C22002DA' , 'max' =>        0 , 'min' =>      -40 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_MIN_OUTDOOR_TEMPERATURE' },
    { 'idx' =>  568 , 'extid' => '013E83F56902D6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP' },
    { 'idx' =>  569 , 'extid' => '01CDC5EA1A0693' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_2' },
    { 'idx' =>  570 , 'extid' => '00FCA08D740C97' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ENVELOPE_STOP_HIGH_OUTDOOR_TEMP' },
    { 'idx' =>  571 , 'extid' => 'C0648EA3B3064E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_HOT_GAS_FUNCTION_ACTIVE' },
    { 'idx' =>  572 , 'extid' => '002854632603A7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_OUTDOOR' },
    { 'idx' =>  573 , 'extid' => 'C0694D6ACE064F' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_OUTDOOR_FUNCTION_ACTIVE' },
    { 'idx' =>  574 , 'extid' => 'E1CB5E3E8F02D7' , 'max' =>      150 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_TEMPERATURE' },
    { 'idx' =>  575 , 'extid' => '01AC34897F02D5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_VV' },
    { 'idx' =>  576 , 'extid' => '0188EEF06D067A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_STOP_VV_2' },
    { 'idx' =>  577 , 'extid' => 'C05D9CC10C0302' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E21_EXT_1' },
    { 'idx' =>  578 , 'extid' => 'C0C49590B60B45' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E21_EXT_2' },
    { 'idx' =>  579 , 'extid' => 'C06C74DB910B46' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E22_EXT_1' },
    { 'idx' =>  580 , 'extid' => 'C0F57D8A2B0488' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVATED_BY_E22_EXT_2' },
    { 'idx' =>  581 , 'extid' => '00271682D90308' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_1_ACTIVE' },
    { 'idx' =>  582 , 'extid' => 'C0058268240489' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E21_EXT_1' },
    { 'idx' =>  583 , 'extid' => 'C09C8B399E048A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E21_EXT_2' },
    { 'idx' =>  584 , 'extid' => 'C0346A72B90B47' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E22_EXT_1' },
    { 'idx' =>  585 , 'extid' => 'C0AD6323030B48' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVATED_BY_E22_EXT_2' },
    { 'idx' =>  586 , 'extid' => '00A999853A0487' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_2_ACTIVE' },
    { 'idx' =>  587 , 'extid' => 'C084A70D030B02' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E21_EXT_1' },
    { 'idx' =>  588 , 'extid' => 'C01DAE5CB90B03' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E21_EXT_2' },
    { 'idx' =>  589 , 'extid' => 'C0B54F179E0B49' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E22_EXT_1' },
    { 'idx' =>  590 , 'extid' => 'C02C4646240B4A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVATED_BY_E22_EXT_2' },
    { 'idx' =>  591 , 'extid' => '00653385A40B04' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EVU_3_ACTIVE' },
    { 'idx' =>  592 , 'extid' => 'C146FF6AC202AA' , 'max' =>        7 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_DAY' },
    { 'idx' =>  593 , 'extid' => '02AC9077580B80' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_IOB6126_BITMASK' },
    { 'idx' =>  595 , 'extid' => '006C26255200BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_REQUEST' },
    { 'idx' =>  596 , 'extid' => '016A215A3200BE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_STATE' },
    { 'idx' =>  597 , 'extid' => 'E1D13CD71600C0' , 'max' =>       23 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_TIME' },
    { 'idx' =>  598 , 'extid' => '80959153780B98' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXTERN_HEAT_SOURCE_E71_EXT_INPUT_INV' },
    { 'idx' =>  599 , 'extid' => '8084EC39010B9A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXTERN_HEAT_SOURCE_E72_EXT_INPUT_INV' },
    { 'idx' =>  600 , 'extid' => '00464AC29A0D59' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_BOOL_ONE' },
    { 'idx' =>  601 , 'extid' => '004AEC4FCE0D58' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_BOOL_ZERO' },
    { 'idx' =>  602 , 'extid' => '01AA9DB4190D5B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_CHAR_ONE' },
    { 'idx' =>  603 , 'extid' => '013EB14A220D5A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FAKE_VARIABLE_CHAR_ZERO' },
    { 'idx' =>  604 , 'extid' => 'EAD40AB6D00913' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FK_PID_D' },
    { 'idx' =>  606 , 'extid' => 'EAAABBCA6D0914' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'FK_PID_I' },
    { 'idx' =>  608 , 'extid' => 'EACED062AD0915' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'FK_PID_P' },
    { 'idx' =>  610 , 'extid' => 'E1ACF52887004F' , 'max' =>       80 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGARD_COMPRESSOR_FREQUENCY' },
    { 'idx' =>  611 , 'extid' => '005BB7B5B3004D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGUARD' },
    { 'idx' =>  612 , 'extid' => 'E17CA36100004E' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGUARD_DELAY_TIME' },
    { 'idx' =>  613 , 'extid' => 'EE2A751B620050' , 'max' =>      300 , 'min' =>       20 , 'format' => 'tem' , 'read' => 0 , 'text' => 'FREEZEGUARD_START_TEMPERATURE' },
    { 'idx' =>  615 , 'extid' => 'EEDEC69BAF0051' , 'max' =>      500 , 'min' =>       70 , 'format' => 'tem' , 'read' => 0 , 'text' => 'FREEZEGUARD_STOP_TEMPERATURE' },
    { 'idx' =>  617 , 'extid' => '0EE4FE05AE0056' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GRADMIN' },
    { 'idx' =>  619 , 'extid' => 'E2C09D3F760057' , 'max' =>      120 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GRADMIN_MAX' },
    { 'idx' =>  621 , 'extid' => 'EDD48ABC8A0412' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_2_KORRIGERING' },
    { 'idx' =>  622 , 'extid' => 'EE3BE8C5140847' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_2_LR_TEMP' },
    { 'idx' =>  624 , 'extid' => '00F444E6260413' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_2_STATUS' },
    { 'idx' =>  625 , 'extid' => '0EA262CCDE0414' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_2_TEMP' },
    { 'idx' =>  627 , 'extid' => 'E15551778D046C' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_GT11_MAX_DELTA_DELAY_AFTER_SWITCH_TIME' },
    { 'idx' =>  628 , 'extid' => 'E1BEDA2A7806C6' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_GT11_MAX_DELTA_DELAY_TIME' },
    { 'idx' =>  629 , 'extid' => 'E5DFF9C1DC06C5' , 'max' =>       30 , 'min' =>        1 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_GT11_MAX_DELTA_TEMP' },
    { 'idx' =>  630 , 'extid' => 'ED5E390C4F005B' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT10_KORRIGERING' },
    { 'idx' =>  631 , 'extid' => 'EE5634821C022B' , 'max' =>      300 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_LAG_KOND_TEMP' },
    { 'idx' =>  633 , 'extid' => 'E1B939C0DD016E' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_LR_ANTAL_VARNINGAR' },
    { 'idx' =>  634 , 'extid' => 'E93FEC9550016D' , 'max' =>      100 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_LR_HYSTERES' },
    { 'idx' =>  635 , 'extid' => 'EEB663A78100EC' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_LR_TEMP' },
    { 'idx' =>  637 , 'extid' => '00772B8639005C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT10_STATUS' },
    { 'idx' =>  638 , 'extid' => '0E2139C16F005D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT10_TEMP' },
    { 'idx' =>  640 , 'extid' => 'ED6D7167620415' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_2_KORRIGERING' },
    { 'idx' =>  641 , 'extid' => 'EE62215A590848' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_2_LF_TEMP' },
    { 'idx' =>  643 , 'extid' => '001B868D180416' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT11_2_STATUS' },
    { 'idx' =>  644 , 'extid' => '0E6EC8CC400417' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_2_TEMP' },
    { 'idx' =>  646 , 'extid' => 'ED83AFD5CA005E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT11_KORRIGERING' },
    { 'idx' =>  647 , 'extid' => 'E1B8074529016F' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT11_LF_ANTAL_VARNINGAR' },
    { 'idx' =>  648 , 'extid' => 'E9CC3F6D47016C' , 'max' =>      100 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT11_LF_HYSTERES' },
    { 'idx' =>  649 , 'extid' => 'EE395FF34F00ED' , 'max' =>      200 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT11_LF_TEMP' },
    { 'idx' =>  651 , 'extid' => '00BB8186A7005F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT11_STATUS' },
    { 'idx' =>  652 , 'extid' => '0EEA6512CA0060' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT11_TEMP' },
    { 'idx' =>  654 , 'extid' => 'ED7C0C0D1B0418' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT12_2_KORRIGERING' },
    { 'idx' =>  655 , 'extid' => '00F0B1361B0419' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT12_2_STATUS' },
    { 'idx' =>  656 , 'extid' => '0EE047CBA3041A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT12_2_TEMP' },
    { 'idx' =>  658 , 'extid' => 'ED3E65B904028B' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT12_KORRIGERING' },
    { 'idx' =>  659 , 'extid' => '00350E8144028C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT12_STATUS' },
    { 'idx' =>  660 , 'extid' => '0E6CF16064024B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT12_TEMP' },
    { 'idx' =>  662 , 'extid' => 'ED362187850058' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT1_KORRIGERING' },
    { 'idx' =>  663 , 'extid' => '201692AD510059' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT1_STATUS' },
    { 'idx' =>  664 , 'extid' => '0EF807E249005A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT1_TEMP' },
    { 'idx' =>  666 , 'extid' => '0E222CD0390CBE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT2_ATTENUATED_TEMP' },
    { 'idx' =>  668 , 'extid' => 'AA88FB658F0CBF' , 'max' =>      480 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT2_ATTENUATION' },
    { 'idx' =>  670 , 'extid' => 'ED8BEBEB4B0061' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT2_KORRIGERING' },
    { 'idx' =>  671 , 'extid' => '00981DAAB20062' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT2_STATUS' },
    { 'idx' =>  672 , 'extid' => '0E7E9390E70063' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT2_TEMP' },
    { 'idx' =>  674 , 'extid' => '0E288433280D13' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT2_TEMP_ROUND_OFFED' },
    { 'idx' =>  676 , 'extid' => '80B4702C470064' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_ANSLUTEN' },
    { 'idx' =>  677 , 'extid' => 'ED567D32CE0065' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT3_KORRIGERING' },
    { 'idx' =>  678 , 'extid' => 'C016D09D1D0066' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_KVITTERAD' },
    { 'idx' =>  679 , 'extid' => '00AF4D85D70239' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_KVITTERA_MANUELLT' },
    { 'idx' =>  680 , 'extid' => '0054B7AA2C0067' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT3_STATUS' },
    { 'idx' =>  681 , 'extid' => '0EB5CF43420068' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT3_TEMP' },
    { 'idx' =>  683 , 'extid' => '6D4BE87068049E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT41_KORRIGERING_GLOBAL' },
    { 'idx' =>  684 , 'extid' => '0EAB0EFFDF049D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT41_TEMP_GLOBAL' },
    { 'idx' =>  686 , 'extid' => 'C01592B05F0752' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_ACKNOWLEDGED_GLOBAL' },
    { 'idx' =>  687 , 'extid' => '0E67FFA7580D12' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_ATTENUATED_TEMP_GLOBAL' },
    { 'idx' =>  689 , 'extid' => 'AA6BB86D6D0D11' , 'max' =>      480 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_ATTENUATION_GLOBAL' },
    { 'idx' =>  691 , 'extid' => '6D05059B31049F' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_KORRIGERING_GLOBAL' },
    { 'idx' =>  692 , 'extid' => '0E6BB7954904A0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT45_TEMP_GLOBAL' },
    { 'idx' =>  694 , 'extid' => '81B96E5C000069' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'GT5_ANSLUTEN' },
    { 'idx' =>  695 , 'extid' => '0E02BEAC720CC2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT5_ATTENUATED_TEMP' },
    { 'idx' =>  697 , 'extid' => 'AAF58863D70CC1' , 'max' =>      480 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_ATTENUATION' },
    { 'idx' =>  699 , 'extid' => 'EDF698ED13006A' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT5_KORRIGERING' },
    { 'idx' =>  700 , 'extid' => 'C0FE65575E006B' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_KVITTERAD' },
    { 'idx' =>  701 , 'extid' => '0092D8A3AB006C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_STATUS' },
    { 'idx' =>  702 , 'extid' => '0E6396A05F006D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT5_TEMP' },
    { 'idx' =>  704 , 'extid' => '0EC9AA394C0D1B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT5_TEMP_ROUND_OFFED' },
    { 'idx' =>  706 , 'extid' => 'E1378E0B14085D' , 'max' =>      150 , 'min' =>       50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_2_HG_TEMP' },
    { 'idx' =>  707 , 'extid' => 'ED04F4BEE4041C' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_2_KORRIGERING' },
    { 'idx' =>  708 , 'extid' => '0017008409041B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT6_2_STATUS' },
    { 'idx' =>  709 , 'extid' => '0EC91EEEAF041D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_2_TEMP' },
    { 'idx' =>  711 , 'extid' => 'E1365E2D32022D' , 'max' =>      150 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT6_HG_TEMP' },
    { 'idx' =>  712 , 'extid' => 'ED4B5281DD006E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT6_KORRIGERING' },
    { 'idx' =>  713 , 'extid' => '001C57A448006F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT6_STATUS' },
    { 'idx' =>  714 , 'extid' => '0EE502D2F10070' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT6_TEMP' },
    { 'idx' =>  716 , 'extid' => 'EDBD0F650C0C74' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT7_2_KORRIGERING' },
    { 'idx' =>  717 , 'extid' => '00F8C2EF370C75' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT7_2_STATUS' },
    { 'idx' =>  718 , 'extid' => '0E05B4EE310C76' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT7_2_TEMP' },
    { 'idx' =>  720 , 'extid' => 'ED96C458580C68' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT7_KORRIGERING' },
    { 'idx' =>  721 , 'extid' => '00D0FDA4D60C67' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT7_STATUS' },
    { 'idx' =>  722 , 'extid' => '0E2E5E01540C66' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT7_TEMP' },
    { 'idx' =>  724 , 'extid' => 'ED2DF92A8A04A7' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT81_KORRIGERING' },
    { 'idx' =>  725 , 'extid' => 'C49092AD3504AF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT81_KVITTERAD' },
    { 'idx' =>  726 , 'extid' => '00172230FC04AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT81_STATUS' },
    { 'idx' =>  727 , 'extid' => '0E7FFD571904A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT81_TEMP' },
    { 'idx' =>  729 , 'extid' => 'ED9033464404A8' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT82_KORRIGERING' },
    { 'idx' =>  730 , 'extid' => '0099AD371F04A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT82_STATUS' },
    { 'idx' =>  731 , 'extid' => '0EF96925B704A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT82_TEMP' },
    { 'idx' =>  733 , 'extid' => 'EEAEA4F3B7085B' , 'max' =>      800 , 'min' =>      500 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_2_HF_TEMP' },
    { 'idx' =>  735 , 'extid' => 'EDB712C9F1085C' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_2_HIGH_GT9_RESTART_HYSTERESIS' },
    { 'idx' =>  736 , 'extid' => 'EDE987A691041E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_2_KORRIGERING' },
    { 'idx' =>  737 , 'extid' => '0009C9B4BA041F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_2_STATUS' },
    { 'idx' =>  738 , 'extid' => '0EDC94FC9D0420' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_2_TEMP' },
    { 'idx' =>  740 , 'extid' => 'E197B1FD5406C7' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_GT9_MAX_DELTA_DELAY_AFTER_SWITCH_TIME' },
    { 'idx' =>  741 , 'extid' => 'E1EB94F64500F9' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_GT9_MAX_DELTA_DELAY_TIME' },
    { 'idx' =>  742 , 'extid' => 'E5CBE851D000F8' , 'max' =>       30 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_GT9_MAX_DELTA_TEMP' },
    { 'idx' =>  743 , 'extid' => '005FA258650185' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_HF_ELK' },
    { 'idx' =>  744 , 'extid' => 'EDD8570F800186' , 'max' =>       95 , 'min' =>       45 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT8_HF_ELK_TEMP' },
    { 'idx' =>  745 , 'extid' => 'EE35C0250500EE' , 'max' =>      800 , 'min' =>      500 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT8_HF_TEMP' },
    { 'idx' =>  747 , 'extid' => 'ED41A459C705B5' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_HIGH_GT9_RESTART_HYSTERESIS' },
    { 'idx' =>  748 , 'extid' => 'E143F89A3A084F' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_HIGH_MAX_WARNING_COUNT' },
    { 'idx' =>  749 , 'extid' => 'EDB1B48D6D0071' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT8_KORRIGERING' },
    { 'idx' =>  750 , 'extid' => '0009DDB67A0072' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT8_STATUS' },
    { 'idx' =>  751 , 'extid' => '0EDF08B3810073' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT8_TEMP' },
    { 'idx' =>  753 , 'extid' => 'ED507C7D790421' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT9_2_KORRIGERING' },
    { 'idx' =>  754 , 'extid' => '00E60BDF840422' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT9_2_STATUS' },
    { 'idx' =>  755 , 'extid' => '0E103EFC030423' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT9_2_TEMP' },
    { 'idx' =>  757 , 'extid' => 'ED6C2254E80074' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'tem' , 'read' => 0 , 'text' => 'GT9_KORRIGERING' },
    { 'idx' =>  758 , 'extid' => '00C577B6E40075' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'GT9_STATUS' },
    { 'idx' =>  759 , 'extid' => '0E145460240076' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'GT9_TEMP' },
    { 'idx' =>  761 , 'extid' => '0A71ACC137026B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF' },
    { 'idx' =>  763 , 'extid' => '0AC849215A05F1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_2' },
    { 'idx' =>  765 , 'extid' => 'EE882E18670249' , 'max' =>      300 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_CONST' },
    { 'idx' =>  767 , 'extid' => 'EE8DFDEFFC05F2' , 'max' =>      300 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_CONST_2' },
    { 'idx' =>  769 , 'extid' => 'EA9E9BF7D90247' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MAX' },
    { 'idx' =>  771 , 'extid' => 'EAC70E859605F3' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MAX_2' },
    { 'idx' =>  773 , 'extid' => 'EAA296C8800248' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MIN' },
    { 'idx' =>  775 , 'extid' => 'EA1A1172BB05F4' , 'max' =>      300 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_1A_DIFF_MIN_2' },
    { 'idx' =>  777 , 'extid' => '0E4A9862F40287' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_ADDITIONAL_SETPOINT' },
    { 'idx' =>  779 , 'extid' => 'E990138EC60227' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_ADDITIONAL_SETPOINT_OFFSET' },
    { 'idx' =>  780 , 'extid' => 'E14DC699890281' , 'max' =>       20 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TEMP' },
    { 'idx' =>  781 , 'extid' => 'E12901840601F9' , 'max' =>       60 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TIME' },
    { 'idx' =>  782 , 'extid' => '2AFEFEB21203E1' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CIRCUIT_PID_ISPOINT_GLOBAL' },
    { 'idx' =>  784 , 'extid' => '2A0F3EA5A403E0' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CIRCUIT_PID_SETPOINT_GLOBAL' },
    { 'idx' =>  786 , 'extid' => '00ECE8B73C0B5F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_CHECK_SETTING' },
    { 'idx' =>  787 , 'extid' => '6E7F1B6889034B' , 'max' =>     1080 , 'min' =>       10 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_LEFT_Y_GLOBAL' },
    { 'idx' =>  789 , 'extid' => 'EE47EC0AC300D4' , 'max' =>     1080 , 'min' =>       10 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_LEFT_Y_LOCAL' },
    { 'idx' =>  791 , 'extid' => '6EB4805109034C' , 'max' =>     1000 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_MAX_GLOBAL' },
    { 'idx' =>  793 , 'extid' => 'EEBD660673026D' , 'max' =>     1000 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_MAX_LOCAL' },
    { 'idx' =>  795 , 'extid' => '6EB58CCBBD034D' , 'max' =>      800 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_MIN_GLOBAL' },
    { 'idx' =>  797 , 'extid' => 'EE6A8DB432026C' , 'max' =>      800 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_MIN_LOCAL' },
    { 'idx' =>  799 , 'extid' => 'E1EBE5792000D2' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_MYCKET_PROCENT' },
    { 'idx' =>  800 , 'extid' => 'E1E29D0E3F00D3' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_NORMAL_PROCENT' },
    { 'idx' =>  801 , 'extid' => '219D8A4A0703CF' , 'max' =>       12 , 'min' =>        9 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_NO_OF_POINTS' },
    { 'idx' =>  802 , 'extid' => 'EE4ACBA689063E' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_PARALLEL_OFFSET' },
    { 'idx' =>  804 , 'extid' => '6E596997C7064D' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_PARALLEL_OFFSET_GLOBAL' },
    { 'idx' =>  806 , 'extid' => 'EEA73672D1069A' , 'max' =>     -100 , 'min' =>     -350 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_RIGHT_X_LOCAL' },
    { 'idx' =>  808 , 'extid' => '4E40E8C327034E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_RIGHT_Y_GLOBAL' },
    { 'idx' =>  810 , 'extid' => 'CE0141796500D1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'HEATING_CURVE_RIGHT_Y_LOCAL' },
    { 'idx' =>  812 , 'extid' => '0EA674B3CA00CB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_VALUE' },
    { 'idx' =>  814 , 'extid' => 'E5F9FA82E300D5' , 'max' =>       15 , 'min' =>      -10 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CURVE_VH_LIMIT' },
    { 'idx' =>  815 , 'extid' => '6E696808400359' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y10_GLOBAL' },
    { 'idx' =>  817 , 'extid' => 'EE5843861C00DF' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y10_LOCAL' },
    { 'idx' =>  819 , 'extid' => '6EA5C208DE0358' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y11_GLOBAL' },
    { 'idx' =>  821 , 'extid' => 'EEFE348DA800E0' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y11_LOCAL' },
    { 'idx' =>  823 , 'extid' => '6E2B4D0F3D0357' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y12_GLOBAL' },
    { 'idx' =>  825 , 'extid' => 'EECFDC973500E1' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y12_LOCAL' },
    { 'idx' =>  827 , 'extid' => '6ECBFA50D1035A' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y1_GLOBAL' },
    { 'idx' =>  829 , 'extid' => 'EEAD6A653F00D6' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y1_LOCAL' },
    { 'idx' =>  831 , 'extid' => '6E457557320356' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y2_GLOBAL' },
    { 'idx' =>  833 , 'extid' => 'EE9C827FA200D7' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y2_LOCAL' },
    { 'idx' =>  835 , 'extid' => '6E89DF57AC0355' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y3_GLOBAL' },
    { 'idx' =>  837 , 'extid' => 'EE3AF5741600D8' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y3_LOCAL' },
    { 'idx' =>  839 , 'extid' => '6E831A5EB50354' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y4_GLOBAL' },
    { 'idx' =>  841 , 'extid' => 'EEFF524A9800D9' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y4_LOCAL' },
    { 'idx' =>  843 , 'extid' => '6E4FB05E2B0353' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y5_GLOBAL' },
    { 'idx' =>  845 , 'extid' => 'EE5925412C00DA' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y5_LOCAL' },
    { 'idx' =>  847 , 'extid' => '6EC13F59C80352' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y6_GLOBAL' },
    { 'idx' =>  849 , 'extid' => 'EE68CD5BB100DB' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y6_LOCAL' },
    { 'idx' =>  851 , 'extid' => '6E0D9559560351' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y7_GLOBAL' },
    { 'idx' =>  853 , 'extid' => 'EECEBA500500DC' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y7_LOCAL' },
    { 'idx' =>  855 , 'extid' => '6ED4B54BFA0350' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y8_GLOBAL' },
    { 'idx' =>  857 , 'extid' => 'EE38F220EC00DD' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y8_LOCAL' },
    { 'idx' =>  859 , 'extid' => '6E181F4B64034F' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y9_GLOBAL' },
    { 'idx' =>  861 , 'extid' => 'EE9E852B5800DE' , 'max' =>      100 , 'min' =>     -100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_CURVE_Y9_LOCAL' },
    { 'idx' =>  863 , 'extid' => '00431BEF9C030C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCKED' },
    { 'idx' =>  864 , 'extid' => 'C0E4AEF76C0B52' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E21_EXT_1' },
    { 'idx' =>  865 , 'extid' => 'C07DA7A6D6048E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E21_EXT_2' },
    { 'idx' =>  866 , 'extid' => 'C0D546EDF10306' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E22_EXT_1' },
    { 'idx' =>  867 , 'extid' => 'C04C4FBC4B0B51' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_EXTERN_BLOCK_BY_E22_EXT_2' },
    { 'idx' =>  868 , 'extid' => 'EEF07561AC07E4' , 'max' =>      650 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HEATING_FIXED_TEMPERATURE' },
    { 'idx' =>  870 , 'extid' => 'E1D769501C00CC' , 'max' =>      120 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_MAX_TIME' },
    { 'idx' =>  871 , 'extid' => 'EA55C0014400CD' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REGULATOR_I' },
    { 'idx' =>  873 , 'extid' => 'EA31ABA98400CE' , 'max' =>      200 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REGULATOR_P' },
    { 'idx' =>  875 , 'extid' => '00CAE035FA00C8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HEATING_REQUEST' },
    { 'idx' =>  876 , 'extid' => '000CCD051004BC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HEATING_REQUEST_2' },
    { 'idx' =>  877 , 'extid' => 'E12D76FBC90331' , 'max' =>       15 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REQUEST_BLOCK_AFTER_START_TIME' },
    { 'idx' =>  878 , 'extid' => 'E23409A4FD00C9' , 'max' =>      600 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_REQUEST_BLOCK_TIME' },
    { 'idx' =>  880 , 'extid' => '002280F33400F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HEATING_SEASON_ACTIVE' },
    { 'idx' =>  881 , 'extid' => 'E1E3B281D900F7' , 'max' =>       35 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_DELAYED_TEMP' },
    { 'idx' =>  882 , 'extid' => 'E1C800448B00F5' , 'max' =>       17 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_IMMEDIATE_TEMP' },
    { 'idx' =>  883 , 'extid' => 'E1882248C90440' , 'max' =>        2 , 'min' =>        0 , 'format' => 'dp2' , 'read' => 1 , 'text' => 'HEATING_SEASON_MODE' },
    { 'idx' =>  884 , 'extid' => 'E1FF34393100F6' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_START_DELAY_TIME' },
    { 'idx' =>  885 , 'extid' => 'E17EE5BF2402F1' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_STOP_DELAY_TIME' },
    { 'idx' =>  886 , 'extid' => '0E7900A31300CA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SETPOINT' },
    { 'idx' =>  888 , 'extid' => '0E7B5ED0CD00CF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_START' },
    { 'idx' =>  890 , 'extid' => '0E4CAA026D0631' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_START_2' },
    { 'idx' =>  892 , 'extid' => '01FBBDF9BE026E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_STATUS_BLOCK' },
    { 'idx' =>  893 , 'extid' => '0E901C5F1A00D0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_STOP' },
    { 'idx' =>  895 , 'extid' => '0EFFD424460632' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_STOP_2' },
    { 'idx' =>  897 , 'extid' => '40D1B9506D05DF' , 'max' =>150994944 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SYSTEM_TYPE_GLOBAL' },
    { 'idx' =>  898 , 'extid' => 'C034BEA42B05DE' , 'max' =>150994944 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SYSTEM_TYPE_LOCAL' },
    { 'idx' =>  899 , 'extid' => 'C053404CD405C5' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_USE_EXTERNAL_SETPOINT' },
    { 'idx' =>  900 , 'extid' => 'C06AA2528F0263' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_ACTIVE' },
    { 'idx' =>  901 , 'extid' => '4080AA43F00861' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_ACTIVE_GLOBAL' },
    { 'idx' =>  902 , 'extid' => 'C00ED82215028E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_DHW' },
    { 'idx' =>  903 , 'extid' => '2093D1EC64024A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_REQUEST' },
    { 'idx' =>  904 , 'extid' => 'E1C4E03DB0075E' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_START_DAY' },
    { 'idx' =>  905 , 'extid' => '61A8A44EDB0266' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_START_DAY_GLOBAL' },
    { 'idx' =>  906 , 'extid' => 'E1AF02C5F30265' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_START_MONTH' },
    { 'idx' =>  907 , 'extid' => '619AB55EF6075F' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_START_MONTH_GLOBAL' },
    { 'idx' =>  908 , 'extid' => 'E1BBA333230264' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_START_YEAR' },
    { 'idx' =>  909 , 'extid' => '616081D1590760' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_START_YEAR_GLOBAL' },
    { 'idx' =>  910 , 'extid' => 'E167BEED150267' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_STOP_DAY' },
    { 'idx' =>  911 , 'extid' => '6177F4697C0761' , 'max' =>       31 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_STOP_DAY_GLOBAL' },
    { 'idx' =>  912 , 'extid' => 'E1FAA1FCD50268' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_STOP_MONTH' },
    { 'idx' =>  913 , 'extid' => '61DEF91EE30762' , 'max' =>       12 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_STOP_MONTH_GLOBAL' },
    { 'idx' =>  914 , 'extid' => 'E11DBC3A940269' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HOLIDAY_STOP_YEAR' },
    { 'idx' =>  915 , 'extid' => '6128ECB7350763' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOLIDAY_STOP_YEAR_GLOBAL' },
    { 'idx' =>  916 , 'extid' => 'E9B0A0966D0B13' , 'max' =>      250 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOTGAS_HIGHEST_DIFF' },
    { 'idx' =>  917 , 'extid' => 'E693E59C200B11' , 'max' =>      250 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HOTGAS_LOWEST_DIFF' },
    { 'idx' =>  919 , 'extid' => 'E176B325DC0AD8' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HP_STOPS_UNTIL_ALARM' },
    { 'idx' =>  920 , 'extid' => 'E1D2A42A030AE8' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HP_STOPS_UNTIL_ALARM_2' },
    { 'idx' =>  921 , 'extid' => 'E1E69DB72F0ADC' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIME' },
    { 'idx' =>  922 , 'extid' => 'E1F334FA3B0AE9' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIME_2' },
    { 'idx' =>  923 , 'extid' => 'E1C80D3B990ADA' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_TIME_WINDOW' },
    { 'idx' =>  924 , 'extid' => 'E1A5A5129E0AEA' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_TIME_WINDOW_2' },
    { 'idx' =>  925 , 'extid' => '02D4592AAF0D3C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HUMIDITY_BOARD_0_10V_GLOBAL' },
    { 'idx' =>  927 , 'extid' => '00F65C47DF024E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_4_WAY_VALVE' },
    { 'idx' =>  928 , 'extid' => '005A35F95B03F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_4_WAY_VALVE_2' },
    { 'idx' =>  929 , 'extid' => '00F09C9DD3024C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_ADDITIONAL_ALARM' },
    { 'idx' =>  930 , 'extid' => '00F4F8900E02F0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_DHW' },
    { 'idx' =>  931 , 'extid' => '00D9A53A1003AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_RELAY_1' },
    { 'idx' =>  932 , 'extid' => '0040AC6BAA03AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_RELAY_2' },
    { 'idx' =>  933 , 'extid' => '0037AB5B3C03AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_RELAY_3' },
    { 'idx' =>  934 , 'extid' => '001B7A8E8103B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_START' },
    { 'idx' =>  935 , 'extid' => '007DF794DF03AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_TRIAC_1' },
    { 'idx' =>  936 , 'extid' => '00E4FEC56503AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_TRIAC_2' },
    { 'idx' =>  937 , 'extid' => '0093F9F5F303AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_TRIAC_3' },
    { 'idx' =>  938 , 'extid' => '00A5DAF23603BA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_VALVE_CLOSE' },
    { 'idx' =>  939 , 'extid' => '00192E4CBB03B9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ADDITIONAL_VALVE_OPEN' },
    { 'idx' =>  940 , 'extid' => '0076AEF2D4007A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_BUZZER' },
    { 'idx' =>  941 , 'extid' => '013A27FDA9009A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR' },
    { 'idx' =>  942 , 'extid' => '0108E4B1C203F1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_2' },
    { 'idx' =>  943 , 'extid' => '008BC64CB30093' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_CAN_COMMUNICATION' },
    { 'idx' =>  944 , 'extid' => '00C00179FB0094' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_COMMUNICATION_ERR' },
    { 'idx' =>  945 , 'extid' => '0AD66D197B0095' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_CURRENT' },
    { 'idx' =>  947 , 'extid' => '01CB63A5C50096' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_FREERUN' },
    { 'idx' =>  948 , 'extid' => '0251F45BA50097' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_NAK' },
    { 'idx' =>  950 , 'extid' => '013905FA110098' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_TARGET_FREQ' },
    { 'idx' =>  951 , 'extid' => '0E7173A5E40099' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_TEMP' },
    { 'idx' =>  953 , 'extid' => '020706CEB7009B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_VOLTAGE' },
    { 'idx' =>  955 , 'extid' => '0199F3A0A7009C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COMPRESSOR_WORKING_FREQ' },
    { 'idx' =>  956 , 'extid' => '0018FBFE2E030F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CONTACTOR_1' },
    { 'idx' =>  957 , 'extid' => '0081F2AF940310' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CONTACTOR_2' },
    { 'idx' =>  958 , 'extid' => '0057227F59009D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_COOLING_FAN' },
    { 'idx' =>  959 , 'extid' => '006E3208CB024F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CRANKCASE_HEATER' },
    { 'idx' =>  960 , 'extid' => '0092F8EA6103F2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_CRANKCASE_HEATER_2' },
    { 'idx' =>  961 , 'extid' => '0E63FC6C33090E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E11_T11_TEMP' },
    { 'idx' =>  963 , 'extid' => '006DE32336007F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_1' },
    { 'idx' =>  964 , 'extid' => '80888802E30B61' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_1_INV' },
    { 'idx' =>  965 , 'extid' => '00F4EA728C02A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_2' },
    { 'idx' =>  966 , 'extid' => '80CF2878330B62' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E21_EXT_2_INV' },
    { 'idx' =>  967 , 'extid' => '005C0B39AB0B5C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_1' },
    { 'idx' =>  968 , 'extid' => '80116A64E20B63' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_1_INV' },
    { 'idx' =>  969 , 'extid' => '00C50268110B5B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_2' },
    { 'idx' =>  970 , 'extid' => '8056CA1E320B64' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E22_EXT_2_INV' },
    { 'idx' =>  971 , 'extid' => '0EAC0FC4DB0833' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E31_T31_TEMP' },
    { 'idx' =>  973 , 'extid' => '0E2A9BB6750825' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E31_T32_TEMP' },
    { 'idx' =>  975 , 'extid' => '009C840C64099B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E71_EXT' },
    { 'idx' =>  976 , 'extid' => '0EE899934A04B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E71_T71_TEMP' },
    { 'idx' =>  978 , 'extid' => '0E6E0DE1E404BB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E71_T72_TEMP' },
    { 'idx' =>  980 , 'extid' => '00DB2476B4099C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E72_EXT' },
    { 'idx' =>  981 , 'extid' => '0E03AE284907CC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_E72_T71_TEMP' },
    { 'idx' =>  983 , 'extid' => '0E853A5AE707CD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_E72_T72_TEMP' },
    { 'idx' =>  985 , 'extid' => '008007F2B7007E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK' },
    { 'idx' =>  986 , 'extid' => '004C1A29AC03F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK_2' },
    { 'idx' =>  987 , 'extid' => '003B1D193A03F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK_3' },
    { 'idx' =>  988 , 'extid' => '00A5798C9903F5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ELK_4' },
    { 'idx' =>  989 , 'extid' => '007BB4CEB60A0E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_EL_VVB_ALARM' },
    { 'idx' =>  990 , 'extid' => '0A50F7942F0486' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_EXTERNAL_SETPOINT' },
    { 'idx' =>  992 , 'extid' => '0A51533D230B70' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_EXTERNAL_SETPOINT_2' },
    { 'idx' =>  994 , 'extid' => 'E11E2E44E30661' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_ANALOG' },
    { 'idx' =>  995 , 'extid' => 'E1B0CF396C0662' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_ANALOG_2' },
    { 'idx' =>  996 , 'extid' => '0025FF8E2A024D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_DIGITAL' },
    { 'idx' =>  997 , 'extid' => '00D146451403F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_FAN_DIGITAL_2' },
    { 'idx' =>  998 , 'extid' => '02B14826A20080' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT1' },
    { 'idx' => 1000 , 'extid' => '02CCB255C3008E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT10' },
    { 'idx' => 1002 , 'extid' => '024FFBEFA00405' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT10_2' },
    { 'idx' => 1004 , 'extid' => '0E9310C7C2008F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT10_TEMP' },
    { 'idx' => 1006 , 'extid' => '0E48E1732B0406' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT10_TEMP_2' },
    { 'idx' => 1008 , 'extid' => '02BBB565550090' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT11' },
    { 'idx' => 1010 , 'extid' => '024E3985970407' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT11_2' },
    { 'idx' => 1012 , 'extid' => '0E584C14670091' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT11_TEMP' },
    { 'idx' => 1014 , 'extid' => '0E844B73B50408' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT11_TEMP_2' },
    { 'idx' => 1016 , 'extid' => '0222BC34EF028A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT12' },
    { 'idx' => 1018 , 'extid' => '024C7F3BCE0409' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT12_2' },
    { 'idx' => 1020 , 'extid' => '0EDED866C9025A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT12_TEMP' },
    { 'idx' => 1022 , 'extid' => '0E0AC47456040A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT12_TEMP_2' },
    { 'idx' => 1024 , 'extid' => '0E6C0A67F00081' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT1_TEMP' },
    { 'idx' => 1026 , 'extid' => '02284177180082' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT2' },
    { 'idx' => 1028 , 'extid' => '0EEA9E155E0083' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT2_TEMP' },
    { 'idx' => 1030 , 'extid' => '025F46478E0084' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT3' },
    { 'idx' => 1032 , 'extid' => '0E21C2C6FB0085' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT3_TEMP' },
    { 'idx' => 1034 , 'extid' => '0290D9F8CF0499' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_GLOBAL' },
    { 'idx' => 1036 , 'extid' => '0E57D567400502' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_1' },
    { 'idx' => 1038 , 'extid' => '0ECEDC36FA0503' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_2' },
    { 'idx' => 1040 , 'extid' => '0EB9DB066C0504' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_3' },
    { 'idx' => 1042 , 'extid' => '0E27BF93CF0505' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_4' },
    { 'idx' => 1044 , 'extid' => '0E50B8A3590506' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_5' },
    { 'idx' => 1046 , 'extid' => '0EC9B1F2E30507' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_6' },
    { 'idx' => 1048 , 'extid' => '0EBEB6C2750508' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_7' },
    { 'idx' => 1050 , 'extid' => '0E20816508049B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT41_TEMP_GLOBAL' },
    { 'idx' => 1052 , 'extid' => '021493F635049A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT45_GLOBAL' },
    { 'idx' => 1054 , 'extid' => '0EE0380F9E049C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT45_TEMP_GLOBAL' },
    { 'idx' => 1056 , 'extid' => '02B625E2BB0086' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT5' },
    { 'idx' => 1058 , 'extid' => '0EF79B25E60087' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT5_TEMP' },
    { 'idx' => 1060 , 'extid' => '022F2CB3010088' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT6' },
    { 'idx' => 1062 , 'extid' => '02FF5EFEBF040B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT6_2' },
    { 'idx' => 1064 , 'extid' => '0E710F57480089' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT6_TEMP' },
    { 'idx' => 1066 , 'extid' => '0E798272B1040C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT6_TEMP_2' },
    { 'idx' => 1068 , 'extid' => '02582B83970C69' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT7' },
    { 'idx' => 1070 , 'extid' => '02FE9C94880C72' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT7_2' },
    { 'idx' => 1072 , 'extid' => '0EBA5384ED0C6A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT7_TEMP' },
    { 'idx' => 1074 , 'extid' => '0EB528722F0C73' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT7_TEMP_2' },
    { 'idx' => 1076 , 'extid' => '02C8949E06008A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT8' },
    { 'idx' => 1078 , 'extid' => '026A77DE1C04AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT81' },
    { 'idx' => 1080 , 'extid' => '0ECDD451B404AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT81_TEMP' },
    { 'idx' => 1082 , 'extid' => '02F37E8FA604AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT82' },
    { 'idx' => 1084 , 'extid' => '0E4B40231A04AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT82_TEMP' },
    { 'idx' => 1086 , 'extid' => '02F5C0D3B5040D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT8_2' },
    { 'idx' => 1088 , 'extid' => '0E4B053638008B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT8_TEMP' },
    { 'idx' => 1090 , 'extid' => '0E6C086083040E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT8_TEMP_2' },
    { 'idx' => 1092 , 'extid' => '02BF93AE90008C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT9' },
    { 'idx' => 1094 , 'extid' => '02F402B982040F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_GT9_2' },
    { 'idx' => 1096 , 'extid' => '0E8059E59D008D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT9_TEMP' },
    { 'idx' => 1098 , 'extid' => '0EA0A2601D0410' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_GT9_TEMP_2' },
    { 'idx' => 1100 , 'extid' => '001A6BB1B70250' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HEATING_CABLE' },
    { 'idx' => 1101 , 'extid' => '00A3CFA3EA0411' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HEATING_CABLE_2' },
    { 'idx' => 1102 , 'extid' => '00CC502EFA0092' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HP' },
    { 'idx' => 1103 , 'extid' => '0086A8CA4C03F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HP_2' },
    { 'idx' => 1104 , 'extid' => '023BC26E370D39' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HUMIDITY' },
    { 'idx' => 1106 , 'extid' => '028E20D54D0D3A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HUMIDITY_2' },
    { 'idx' => 1108 , 'extid' => '02F927E5DB0D3B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_HUMIDITY_3' },
    { 'idx' => 1110 , 'extid' => '0260EDE3E00C9D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_AI_1' },
    { 'idx' => 1112 , 'extid' => '02678027F90C9E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_AI_5' },
    { 'idx' => 1114 , 'extid' => '00DFC719DF0865' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_DO10' },
    { 'idx' => 1115 , 'extid' => '0031C978F30866' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_DO12' },
    { 'idx' => 1116 , 'extid' => '00D140D41E0CD7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB91119_DO8' },
    { 'idx' => 1117 , 'extid' => '001F7C0F440D38' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_IOB_B_DO5' },
    { 'idx' => 1118 , 'extid' => '00A83CEBFE009E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_LP' },
    { 'idx' => 1119 , 'extid' => '0009CA5D1B03F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_LP_2' },
    { 'idx' => 1120 , 'extid' => '00A04716A3009F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB1' },
    { 'idx' => 1121 , 'extid' => '00C5D3F8D803FA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB1_2' },
    { 'idx' => 1122 , 'extid' => '00394E471900A0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB2' },
    { 'idx' => 1123 , 'extid' => '00C795468103FB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MB2_2' },
    { 'idx' => 1124 , 'extid' => '004EE167F30C45' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_EXT_1' },
    { 'idx' => 1125 , 'extid' => '00584D02290C4C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_MV_E12_PUMP_G1_DIGITAL' },
    { 'idx' => 1126 , 'extid' => '024C365E680C16' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_T1' },
    { 'idx' => 1128 , 'extid' => '003E61EE070C4A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_VALVE_CLOSE' },
    { 'idx' => 1129 , 'extid' => '00C6F0CD7B0C4B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_MV_E12_VALVE_OPEN' },
    { 'idx' => 1130 , 'extid' => '027941CCB0007B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PGU_L1' },
    { 'idx' => 1132 , 'extid' => '02E0489D0A007C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PGU_L2' },
    { 'idx' => 1134 , 'extid' => '02974FAD9C007D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PGU_L3' },
    { 'idx' => 1136 , 'extid' => '006E175E7705BE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PHASE_DETECTOR' },
    { 'idx' => 1137 , 'extid' => '005880FF310956' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PHASE_DETECTOR_2' },
    { 'idx' => 1138 , 'extid' => '00E44C966C05AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_EXT_1' },
    { 'idx' => 1139 , 'extid' => '217A829F8F05AC' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_VALVE' },
    { 'idx' => 1140 , 'extid' => '00CCEB2A1205AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_VALVE_CLOSE' },
    { 'idx' => 1141 , 'extid' => '002E34962805AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_POOL_VALVE_OPEN' },
    { 'idx' => 1142 , 'extid' => '00FD57CF6C05B7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PROTECTIVE_ANODE' },
    { 'idx' => 1143 , 'extid' => '00BBFDBAA602FD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_DHW_DIGITAL' },
    { 'idx' => 1144 , 'extid' => '0078C9526005B1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_E71_G71_DIGITAL' },
    { 'idx' => 1145 , 'extid' => '00C5033EAE07CE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_E72_G71_DIGITAL' },
    { 'idx' => 1146 , 'extid' => '004617B8D502A7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G1_DIGITAL' },
    { 'idx' => 1147 , 'extid' => '217EFB651D02FF' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G2_ANALOG' },
    { 'idx' => 1148 , 'extid' => '21769985D40BBB' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PUMP_G2_ANALOG_2' },
    { 'idx' => 1149 , 'extid' => '007F9A841000A1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G2_DIGITAL' },
    { 'idx' => 1150 , 'extid' => '00143A281603FC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PUMP_G2_DIGITAL_2' },
    { 'idx' => 1151 , 'extid' => '01B25165830300' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G3_ANALOG' },
    { 'idx' => 1152 , 'extid' => '0068E1905300A2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_PUMP_G3_DIGITAL' },
    { 'idx' => 1153 , 'extid' => '00D5B4F7D603FD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_PUMP_G3_DIGITAL_2' },
    { 'idx' => 1154 , 'extid' => '6169F65B800244' , 'max' =>       30 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_INTERVALL' },
    { 'idx' => 1155 , 'extid' => '018A73E4350168' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_MODE' },
    { 'idx' => 1156 , 'extid' => '0289452993016B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_OFF_TIME' },
    { 'idx' => 1158 , 'extid' => '02B1838E70016A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_BUZZER_ON_TIME' },
    { 'idx' => 1160 , 'extid' => '0664DD577800A3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_GT5' },
    { 'idx' => 1162 , 'extid' => '02EAE3D63905B3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_GT5_GLOBAL' },
    { 'idx' => 1164 , 'extid' => '01BB7F1B9900A4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_LED_MODE' },
    { 'idx' => 1165 , 'extid' => '02EE3778D900A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_POT' },
    { 'idx' => 1167 , 'extid' => '021D45302105B2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_ROOM_POT_GLOBAL' },
    { 'idx' => 1169 , 'extid' => '0E5F7D58E80242' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_ROOM_TEMP' },
    { 'idx' => 1171 , 'extid' => '0EA370F2E60570' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'HW_ROOM_TEMP_GLOBAL' },
    { 'idx' => 1173 , 'extid' => '0063479E31065F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'HW_SUMMARY_ALARM' },
    { 'idx' => 1174 , 'extid' => '00A8BC3F9F00A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_SYSTEM_ON' },
    { 'idx' => 1175 , 'extid' => '00D3CF541200A7' , 'max' => 50331648 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_VXV' },
    { 'idx' => 1176 , 'extid' => '00A0DF341503FE' , 'max' => 50331648 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HW_VXV_2' },
    { 'idx' => 1177 , 'extid' => '01C34AAE520916' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ICONS_IOB6126_EXTERN_BITMASK' },
    { 'idx' => 1178 , 'extid' => '000EC773520D0B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'INIT_MV_STATUS_DONE' },
    { 'idx' => 1179 , 'extid' => '814D48DDB806C0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_BOOT_COUNT' },
    { 'idx' => 1180 , 'extid' => '01267BEB2A02AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED' },
    { 'idx' => 1181 , 'extid' => '01EC9ED3470448' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_2' },
    { 'idx' => 1182 , 'extid' => '019B99E3D10449' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_3' },
    { 'idx' => 1183 , 'extid' => '0105FD7672044B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_4' },
    { 'idx' => 1184 , 'extid' => '0172FA46E4044A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_5' },
    { 'idx' => 1185 , 'extid' => '01EBF3175E044C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_6' },
    { 'idx' => 1186 , 'extid' => '019CF427C8044D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_CONNECTED_7' },
    { 'idx' => 1187 , 'extid' => '1212C74ED502AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION' },
    { 'idx' => 1189 , 'extid' => '12D9064DEE0442' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_2' },
    { 'idx' => 1191 , 'extid' => '12AE017D780443' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_3' },
    { 'idx' => 1193 , 'extid' => '123065E8DB0444' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_4' },
    { 'idx' => 1195 , 'extid' => '124762D84D0445' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_5' },
    { 'idx' => 1197 , 'extid' => '12DE6B89F70446' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_6' },
    { 'idx' => 1199 , 'extid' => '12A96CB9610447' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_7' },
    { 'idx' => 1201 , 'extid' => '128C4247A708E4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_EXTERN_HEAT_VERSION_GLOBAL' },
    { 'idx' => 1203 , 'extid' => '016D07017505D8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_MAIN_COOLING_CONNECTED' },
    { 'idx' => 1204 , 'extid' => '122B16C99D05D9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_MAIN_COOLING_VERSION' },
    { 'idx' => 1206 , 'extid' => '01F905031502E4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_POOL_CONNECTED' },
    { 'idx' => 1207 , 'extid' => '1214C98A4702E5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_POOL_VERSION' },
    { 'idx' => 1209 , 'extid' => '010CA1C11D0AC9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SOLAR_CONNECTED' },
    { 'idx' => 1210 , 'extid' => '12C3AB84680ACA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SOLAR_VERSION' },
    { 'idx' => 1212 , 'extid' => '01232004980803' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SUB_COOLING_CONNECTED' },
    { 'idx' => 1213 , 'extid' => '1274C8946A0804' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_SUB_COOLING_VERSION' },
    { 'idx' => 1215 , 'extid' => '0180BBBABC02E6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_CONNECTED' },
    { 'idx' => 1216 , 'extid' => '01D7E9397907CF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_CONNECTED_2' },
    { 'idx' => 1217 , 'extid' => '12C8D95C1B02E7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_VERSION' },
    { 'idx' => 1219 , 'extid' => '127FC61C7807D0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB6126_WOOD_HEATING_VERSION_2' },
    { 'idx' => 1221 , 'extid' => '013094A8A503FF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_CONNECTED' },
    { 'idx' => 1222 , 'extid' => '01BF5051060403' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_CONNECTED_2' },
    { 'idx' => 1223 , 'extid' => '124D8856C20400' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_VERSION' },
    { 'idx' => 1225 , 'extid' => '12CFE90E610404' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_COMP_VERSION_2' },
    { 'idx' => 1227 , 'extid' => '01F020CB6D02AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_HEAT_CONNECTED' },
    { 'idx' => 1228 , 'extid' => '0168C8FC160B74' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_HEAT_CONNECTED_2' },
    { 'idx' => 1229 , 'extid' => '1299651BCA042E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_HEAT_VERSION' },
    { 'idx' => 1231 , 'extid' => '0113477C900BD6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_CONNECTED' },
    { 'idx' => 1232 , 'extid' => '019CDFA6AE0BD7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_CONNECTED_2' },
    { 'idx' => 1233 , 'extid' => '12FEAC864C0BD8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_VERSION' },
    { 'idx' => 1235 , 'extid' => '12EC3ADA540BD9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_AW_LIGHT_HEAT_VERSION_2' },
    { 'idx' => 1237 , 'extid' => '81AE30D1F906BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_BOOT_COUNT' },
    { 'idx' => 1238 , 'extid' => '81812E7C260639' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_CONNECTED_BITMASK' },
    { 'idx' => 1239 , 'extid' => 'A19E82E3A00CC8' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_DO8_G6_OR_SUMMARY_ALARM' },
    { 'idx' => 1240 , 'extid' => '01DF7DAE6102A8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_CONNECTED' },
    { 'idx' => 1241 , 'extid' => '01F9A509900401' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_CONNECTED_2' },
    { 'idx' => 1242 , 'extid' => '01783DD8E70BCC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_CONNECTED' },
    { 'idx' => 1243 , 'extid' => '012D1A45140BCD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_CONNECTED_2' },
    { 'idx' => 1244 , 'extid' => '01002542290D02' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_CONNECTED' },
    { 'idx' => 1245 , 'extid' => '0168B9BD960D03' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_CONNECTED_2' },
    { 'idx' => 1246 , 'extid' => '1283CBAC440D04' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_VERSION' },
    { 'idx' => 1248 , 'extid' => '12FF58E4ED0D05' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_HA_VERSION_2' },
    { 'idx' => 1250 , 'extid' => '120A248A970BCE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_VERSION' },
    { 'idx' => 1252 , 'extid' => '1287407E230BCF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_DACH_LIGHT_VERSION_2' },
    { 'idx' => 1254 , 'extid' => '01720E94C40ACC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_CONNECTED' },
    { 'idx' => 1255 , 'extid' => '01ECD935FD0AEB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_CONNECTED_2' },
    { 'idx' => 1256 , 'extid' => '12EB3DE1FA0ACD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_VERSION' },
    { 'idx' => 1258 , 'extid' => '128D7332000AEC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_LIGHT_VERSION_2' },
    { 'idx' => 1260 , 'extid' => '125882C4E602A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_VERSION' },
    { 'idx' => 1262 , 'extid' => '12200008A50402' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_LW_VERSION_2' },
    { 'idx' => 1264 , 'extid' => '00B0CF9E6D0B8C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB91119_REBOOT' },
    { 'idx' => 1265 , 'extid' => '012516229700AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOBX10_CONNECTED' },
    { 'idx' => 1266 , 'extid' => '1282BF1AFF00AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOBX10_VERSION' },
    { 'idx' => 1268 , 'extid' => '11602326BB0C65' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_AW_LIGHT_COMP_CONNECTED' },
    { 'idx' => 1269 , 'extid' => '120FA10E7B0C6B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_AW_LIGHT_COMP_VERSION' },
    { 'idx' => 1271 , 'extid' => '01797ED2370D1E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION' },
    { 'idx' => 1272 , 'extid' => '014CF768560D1F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_2' },
    { 'idx' => 1273 , 'extid' => '013BF058C00D20' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_3' },
    { 'idx' => 1274 , 'extid' => '01A594CD630D21' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_4' },
    { 'idx' => 1275 , 'extid' => '01D293FDF50D22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_5' },
    { 'idx' => 1276 , 'extid' => '014B9AAC4F0D23' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_6' },
    { 'idx' => 1277 , 'extid' => '013C9D9CD90D24' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_GENERATION_7' },
    { 'idx' => 1278 , 'extid' => '01F7D26D5F0D25' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION' },
    { 'idx' => 1279 , 'extid' => '01BA0DA9480D26' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_2' },
    { 'idx' => 1280 , 'extid' => '01CD0A99DE0D27' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_3' },
    { 'idx' => 1281 , 'extid' => '01536E0C7D0D28' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_4' },
    { 'idx' => 1282 , 'extid' => '0124693CEB0D29' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_5' },
    { 'idx' => 1283 , 'extid' => '01BD606D510D2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_6' },
    { 'idx' => 1284 , 'extid' => '01CA675DC70D2B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_REVISION_7' },
    { 'idx' => 1285 , 'extid' => '01B1D7F6620D2C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION' },
    { 'idx' => 1286 , 'extid' => '01B738ED3F0D2D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_2' },
    { 'idx' => 1287 , 'extid' => '01C03FDDA90D2E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_3' },
    { 'idx' => 1288 , 'extid' => '015E5B480A0D2F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_4' },
    { 'idx' => 1289 , 'extid' => '01295C789C0D30' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_5' },
    { 'idx' => 1290 , 'extid' => '01B05529260D31' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_6' },
    { 'idx' => 1291 , 'extid' => '01C75219B00D32' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_EXTERN_HEAT_VERSION_7' },
    { 'idx' => 1292 , 'extid' => '019FE4CB990D48' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_2_CONNECTED' },
    { 'idx' => 1293 , 'extid' => '015E6A14590D49' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_3_CONNECTED' },
    { 'idx' => 1294 , 'extid' => '01762ABE240D47' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_CONNECTED' },
    { 'idx' => 1295 , 'extid' => '816A19F20A0D51' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_CONNECTED_BITMASK' },
    { 'idx' => 1296 , 'extid' => '016F2C72870D3D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_GENERATION' },
    { 'idx' => 1297 , 'extid' => '017EE473540D3E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_GENERATION_2' },
    { 'idx' => 1298 , 'extid' => '0109E343C20D3F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_GENERATION_3' },
    { 'idx' => 1299 , 'extid' => '01F65069B80D43' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_REVISION' },
    { 'idx' => 1300 , 'extid' => '01AC5F09F80D44' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_REVISION_2' },
    { 'idx' => 1301 , 'extid' => '01DB58396E0D45' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_REVISION_3' },
    { 'idx' => 1302 , 'extid' => '01E8A217230D40' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_VERSION' },
    { 'idx' => 1303 , 'extid' => '01895718E00D41' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_VERSION_2' },
    { 'idx' => 1304 , 'extid' => '01FE5028760D42' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_HUMIDITY_VERSION_3' },
    { 'idx' => 1305 , 'extid' => '01C29C0E9E0B6D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_CONNECTED' },
    { 'idx' => 1306 , 'extid' => '01442C9EA50D36' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_GENERATION' },
    { 'idx' => 1307 , 'extid' => '014B5EE4440D37' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_REVISION' },
    { 'idx' => 1308 , 'extid' => '025BDDF7D30B6E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_OIL_VERSION' },
    { 'idx' => 1310 , 'extid' => '0134DBC34B0D33' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_POOL_GENERATION' },
    { 'idx' => 1311 , 'extid' => '0130484EC10D34' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_POOL_REVISION' },
    { 'idx' => 1312 , 'extid' => '01FC5CDC190D35' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'IOB_B_POOL_VERSION' },
    { 'idx' => 1313 , 'extid' => '8312E8EDF90171' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LANGUAGE' },
    { 'idx' => 1317 , 'extid' => '82466A831A017F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'LANGUAGE_ISO639_1' },
    { 'idx' => 1319 , 'extid' => 'E2A569B174085E' , 'max' =>     1200 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_2_ALARM_DELAY' },
    { 'idx' => 1321 , 'extid' => 'E2EBD0344400BD' , 'max' =>     1200 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_ALARM_DELAY' },
    { 'idx' => 1323 , 'extid' => 'E1385ECE850AD2' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOPS_UNTIL_ALARM' },
    { 'idx' => 1324 , 'extid' => 'E18E05B9030AE5' , 'max' =>        5 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOPS_UNTIL_ALARM_2' },
    { 'idx' => 1325 , 'extid' => 'E132ACFBA80AD6' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIME' },
    { 'idx' => 1326 , 'extid' => 'E1F89C2D3D0AE6' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIME_2' },
    { 'idx' => 1327 , 'extid' => 'E12165367B0AD4' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_TIME_WINDOW' },
    { 'idx' => 1328 , 'extid' => 'E1B75C16250AE7' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_TIME_WINDOW_2' },
    { 'idx' => 1329 , 'extid' => '4067368D550077' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP' },
    { 'idx' => 1330 , 'extid' => '006E7A13440597' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_CLOSE_GLOBAL' },
    { 'idx' => 1331 , 'extid' => '0031D6749C097A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_D_VALVE_GLOBAL' },
    { 'idx' => 1332 , 'extid' => '0099C0DA3F097D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_G2_GLOBAL' },
    { 'idx' => 1333 , 'extid' => '005FAFD3B803DF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_G4_GLOBAL' },
    { 'idx' => 1334 , 'extid' => '004F6DEF9C03DE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_OPEN_GLOBAL' },
    { 'idx' => 1335 , 'extid' => '610B8C00CC097E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_MIXING_VALVE_SIGNAL_GLOBAL' },
    { 'idx' => 1336 , 'extid' => '0076ED86F70079' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_TILLSKOTT' },
    { 'idx' => 1337 , 'extid' => '61E1BE4FF50078' , 'max' =>      240 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MAN_OP_TIME' },
    { 'idx' => 1338 , 'extid' => '817C7B65DC063A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MIXED_CIRCUITS_CONNECTED_BITMASK' },
    { 'idx' => 1339 , 'extid' => '013968EBBC0D0C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXED_CIRCUITS_SETPOINT_INIT_DONE_BITMASK' },
    { 'idx' => 1340 , 'extid' => '01780DCC6B0D0D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXED_CIRCUITS_VALVEMODE_INIT_DONE_BITMASK' },
    { 'idx' => 1341 , 'extid' => '61C1C41C8903D2' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_CLOSE_TIME_GLOBAL' },
    { 'idx' => 1342 , 'extid' => '62C20AB7B303D6' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_DEFROST_DELAY_TIME_GLOBAL' },
    { 'idx' => 1344 , 'extid' => '00A6F57CB0050A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_1' },
    { 'idx' => 1345 , 'extid' => '003FFC2D0A050B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_2' },
    { 'idx' => 1346 , 'extid' => '0048FB1D9C050C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_3' },
    { 'idx' => 1347 , 'extid' => '00D69F883F050D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_4' },
    { 'idx' => 1348 , 'extid' => '00A198B8A9050E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_5' },
    { 'idx' => 1349 , 'extid' => '003891E913050F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_6' },
    { 'idx' => 1350 , 'extid' => '004F96D9850510' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_7' },
    { 'idx' => 1351 , 'extid' => '00DA4773D70509' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_GLOBAL' },
    { 'idx' => 1352 , 'extid' => '0043129BF80998' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_PRI_COOLING' },
    { 'idx' => 1353 , 'extid' => '008AACEDF60999' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_EXT_INPUT_SEC_COOLING' },
    { 'idx' => 1354 , 'extid' => '69CB20868303D8' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MAX_LIMIT_HEATING_SYSTEM' },
    { 'idx' => 1355 , 'extid' => '6102B0EEB70277' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_1' },
    { 'idx' => 1356 , 'extid' => '619BB9BF0D07BA' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_2' },
    { 'idx' => 1357 , 'extid' => '61ECBE8F9B07B8' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_3' },
    { 'idx' => 1358 , 'extid' => '6172DA1A3807B9' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_4' },
    { 'idx' => 1359 , 'extid' => '6105DD2AAE07BB' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_5' },
    { 'idx' => 1360 , 'extid' => '619CD47B1407BC' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_6' },
    { 'idx' => 1361 , 'extid' => '61EBD34B8207BD' , 'max' =>        3 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_7' },
    { 'idx' => 1362 , 'extid' => '61C314B02E07C0' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_MODE_GLOBAL' },
    { 'idx' => 1363 , 'extid' => '6905D4FB4E03D1' , 'max' =>      100 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NEUTRALZONE_GLOBAL' },
    { 'idx' => 1364 , 'extid' => '40F2A2575003D4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NEUTRALZONE_LIMITATION_GLOBAL' },
    { 'idx' => 1365 , 'extid' => '6247D78DCF03D5' , 'max' =>      600 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NEUTRALZONE_LIMITATION_TIME_GLOBAL' },
    { 'idx' => 1367 , 'extid' => '0E4783BF260527' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_1' },
    { 'idx' => 1369 , 'extid' => '0EDE8AEE9C0528' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_2' },
    { 'idx' => 1371 , 'extid' => '0EA98DDE0A0529' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_3' },
    { 'idx' => 1373 , 'extid' => '0E37E94BA9052A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_4' },
    { 'idx' => 1375 , 'extid' => '0E40EE7B3F052B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_5' },
    { 'idx' => 1377 , 'extid' => '0ED9E72A85052C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_6' },
    { 'idx' => 1379 , 'extid' => '0EAEE01A13052D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_CLOSE_7' },
    { 'idx' => 1381 , 'extid' => '0E8DACF5C20520' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_1' },
    { 'idx' => 1383 , 'extid' => '0E14A5A4780521' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_2' },
    { 'idx' => 1385 , 'extid' => '0E63A294EE0522' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_3' },
    { 'idx' => 1387 , 'extid' => '0EFDC6014D0523' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_4' },
    { 'idx' => 1389 , 'extid' => '0E8AC131DB0524' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_5' },
    { 'idx' => 1391 , 'extid' => '0E13C860610525' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_6' },
    { 'idx' => 1393 , 'extid' => '0E64CF50F70526' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_NZ_OPEN_7' },
    { 'idx' => 1395 , 'extid' => '61A09F089403D3' , 'max' =>       60 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_OPEN_TIME_GLOBAL' },
    { 'idx' => 1396 , 'extid' => '6A5544F20C0372' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_D' },
    { 'idx' => 1398 , 'extid' => '6A2BF58EB103D9' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_I' },
    { 'idx' => 1400 , 'extid' => '623DDC078A0563' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_MAX' },
    { 'idx' => 1402 , 'extid' => '6201D138D30564' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_MIN' },
    { 'idx' => 1404 , 'extid' => '6A4F9E267103DB' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PID_P' },
    { 'idx' => 1406 , 'extid' => '0089CE456B04E6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_1' },
    { 'idx' => 1407 , 'extid' => '0010C714D104E7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_2' },
    { 'idx' => 1408 , 'extid' => '0067C0244704E8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_3' },
    { 'idx' => 1409 , 'extid' => '00F9A4B1E404E9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_4' },
    { 'idx' => 1410 , 'extid' => '008EA3817204EA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_5' },
    { 'idx' => 1411 , 'extid' => '0017AAD0C804EB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_6' },
    { 'idx' => 1412 , 'extid' => '0060ADE05E0832' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_7' },
    { 'idx' => 1413 , 'extid' => '009363B8A804D2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G41_GLOBAL' },
    { 'idx' => 1414 , 'extid' => '009755FDE304EC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_PUMP_G71' },
    { 'idx' => 1415 , 'extid' => '62E77AF67003D0' , 'max' =>     6000 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_RUNNING_TIME_GLOBAL' },
    { 'idx' => 1417 , 'extid' => '6940EDBD6F03D7' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_START_LIMIT_HEATING_SYSTEM' },
    { 'idx' => 1418 , 'extid' => '01B8440D7D03E2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_TIMECONTROLLED_GLOBAL' },
    { 'idx' => 1419 , 'extid' => '40DB0290DD03DC' , 'max' =>167772160 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_USE_NEUTRALZONE_REGULATOR' },
    { 'idx' => 1420 , 'extid' => '0061D87A3804ED' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_1' },
    { 'idx' => 1421 , 'extid' => '00F8D12B8204EE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_2' },
    { 'idx' => 1422 , 'extid' => '008FD61B1404EF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_3' },
    { 'idx' => 1423 , 'extid' => '0011B28EB704F0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_4' },
    { 'idx' => 1424 , 'extid' => '0066B5BE2104F1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_5' },
    { 'idx' => 1425 , 'extid' => '00FFBCEF9B04F2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_6' },
    { 'idx' => 1426 , 'extid' => '0088BBDF0D04F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_7' },
    { 'idx' => 1427 , 'extid' => '40CA94436204D4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVECLOSE_GLOBAL' },
    { 'idx' => 1428 , 'extid' => '000F5947F204F4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_1' },
    { 'idx' => 1429 , 'extid' => '009650164804F5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_2' },
    { 'idx' => 1430 , 'extid' => '00E15726DE04F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_3' },
    { 'idx' => 1431 , 'extid' => '007F33B37D04F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_4' },
    { 'idx' => 1432 , 'extid' => '00083483EB04F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_5' },
    { 'idx' => 1433 , 'extid' => '00913DD25104F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_6' },
    { 'idx' => 1434 , 'extid' => '00E63AE2C704FA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_7' },
    { 'idx' => 1435 , 'extid' => '4070F9A4FA04D3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MIXING_VALVE_VALVEOPEN_GLOBAL' },
    { 'idx' => 1436 , 'extid' => '02C050B2090A35' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_CONDENSATIONGUARD_ACTIVE_BITMASK' },
    { 'idx' => 1438 , 'extid' => '007CD550870A33' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_CONDENSATIONGUARD_ACTIVE_GLOBAL' },
    { 'idx' => 1439 , 'extid' => '01689569980D63' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_CONDENSATIONGUARD_ALERT_ACTIVE_BITMASK' },
    { 'idx' => 1440 , 'extid' => '218161509F0965' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_1' },
    { 'idx' => 1441 , 'extid' => '21186801250966' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_2' },
    { 'idx' => 1442 , 'extid' => '216F6F31B30967' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_3' },
    { 'idx' => 1443 , 'extid' => '21F10BA4100968' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_4' },
    { 'idx' => 1444 , 'extid' => '21860C94860969' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_5' },
    { 'idx' => 1445 , 'extid' => '211F05C53C096A' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_6' },
    { 'idx' => 1446 , 'extid' => '216802F5AA096B' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_7' },
    { 'idx' => 1447 , 'extid' => '2153ED79CD0880' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_GLOBAL' },
    { 'idx' => 1448 , 'extid' => '2138510F0B0881' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_PRI_COOLING' },
    { 'idx' => 1449 , 'extid' => '21F1EF79050908' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_10V_RELATIVE_HUMIDITY_SEC_COOLING' },
    { 'idx' => 1450 , 'extid' => '007650B81B07FA' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_ACTIVE' },
    { 'idx' => 1451 , 'extid' => '61711891FF076B' , 'max' =>       48 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DELAY_HEATING_GLOBAL' },
    { 'idx' => 1452 , 'extid' => '0EF5C134D5095D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_1' },
    { 'idx' => 1454 , 'extid' => '0E6CC8656F095E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_2' },
    { 'idx' => 1456 , 'extid' => '0E1BCF55F9095F' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_3' },
    { 'idx' => 1458 , 'extid' => '0E85ABC05A0960' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_4' },
    { 'idx' => 1460 , 'extid' => '0EF2ACF0CC0961' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_5' },
    { 'idx' => 1462 , 'extid' => '0E6BA5A1760962' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_6' },
    { 'idx' => 1464 , 'extid' => '0E1CA291E00963' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_7' },
    { 'idx' => 1466 , 'extid' => '0E67C1B8E30836' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_GLOBAL' },
    { 'idx' => 1468 , 'extid' => '0E022C5B7E087D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_PRI_COOLING' },
    { 'idx' => 1470 , 'extid' => '0ECB922D700907' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEWPOINT_SENSOR_SEC_COOLING' },
    { 'idx' => 1472 , 'extid' => '6E5E88AC2D0772' , 'max' =>      350 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_DEW_POINT_SENSOR_SETPOINT_MIN_GLOBAL' },
    { 'idx' => 1474 , 'extid' => '009DF805BE0852' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_E31_G2' },
    { 'idx' => 1475 , 'extid' => '61FBAE166E09BB' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_FLOWSENSOR_TYPE_GLOBAL' },
    { 'idx' => 1476 , 'extid' => '00552EF6290A56' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_FREEZEGUARD_ACTIVE_GLOBAL' },
    { 'idx' => 1477 , 'extid' => '65DB20760F0805' , 'max' =>       10 , 'min' =>      -10 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_FREEZEGUARD_START' },
    { 'idx' => 1478 , 'extid' => '69DBC26B46076C' , 'max' =>      100 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_GT45_INFLUENCE_GLOBAL' },
    { 'idx' => 1479 , 'extid' => '6D60AF3BB20769' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_INCREASE_ROOM_SETPOINT_GLOBAL' },
    { 'idx' => 1480 , 'extid' => '6186FE4CED09BA' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_MAIN_FLOWSENSOR_TYPE' },
    { 'idx' => 1481 , 'extid' => '65D1F5A6C8076D' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_OUTDOOR_TEMPERATURE_LIMIT_GLOBAL' },
    { 'idx' => 1482 , 'extid' => '611BB16DB208F5' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_ROOMSENSOR_TYPE_GLOBAL' },
    { 'idx' => 1483 , 'extid' => '6E2D12B8C8076E' , 'max' =>      350 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_SETPOINT_MIN_GLOBAL' },
    { 'idx' => 1485 , 'extid' => '61511EA1E709BC' , 'max' =>        1 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_SUB_FLOWSENSOR_TYPE' },
    { 'idx' => 1486 , 'extid' => '025903E14F0D5D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_1' },
    { 'idx' => 1488 , 'extid' => '02C00AB0F50D46' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_2' },
    { 'idx' => 1490 , 'extid' => '02B70D80630D5E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_3' },
    { 'idx' => 1492 , 'extid' => '02296915C00D5F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_4' },
    { 'idx' => 1494 , 'extid' => '025E6E25560D60' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_5' },
    { 'idx' => 1496 , 'extid' => '02C76774EC0D61' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_6' },
    { 'idx' => 1498 , 'extid' => '02B060447A0D62' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_7' },
    { 'idx' => 1500 , 'extid' => '0E7D647F32087F' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_GLOBAL' },
    { 'idx' => 1502 , 'extid' => '0E32BDBE78087E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_PRI_COOLING' },
    { 'idx' => 1504 , 'extid' => '0EFB03C8760906' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_T5_10V_SEC_COOLING' },
    { 'idx' => 1506 , 'extid' => '6DFD36A8B60768' , 'max' =>      100 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_UNDER_SWING_ZONE_GLOBAL' },
    { 'idx' => 1507 , 'extid' => '407FD9E02508FA' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_COOLING_WHEN_HEATING_SEASONG_GLOBAL' },
    { 'idx' => 1508 , 'extid' => '40C6817A80076A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DEW_POINT_SENSOR_ACTIVATED_GLOBAL' },
    { 'idx' => 1509 , 'extid' => 'C2A0367B6D09ED' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DEW_POINT_SENSOR_ALARM_BITMASK' },
    { 'idx' => 1511 , 'extid' => '00AA92E1180766' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DEW_POINT_SENSOR_ALARM_GLOBAL' },
    { 'idx' => 1512 , 'extid' => '40680276A408FD' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DISABLE_COOLING_GLOBAL' },
    { 'idx' => 1513 , 'extid' => '00CC30D1200862' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DOWNLOADING_VARIABLES' },
    { 'idx' => 1514 , 'extid' => '00E2FAA7BB0B8D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_DOWNLOADING_VARIABLES_FOR_MIXING_VALVE' },
    { 'idx' => 1515 , 'extid' => '0EAFA14C17090B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E11_T11_SETPOINT' },
    { 'idx' => 1517 , 'extid' => '0177C0211D0C60' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_CAN_ROOM_SENOR_CONNECTED' },
    { 'idx' => 1518 , 'extid' => '0E4F6ABDDC0C5F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_CAN_ROOM_SENSOR_GT45' },
    { 'idx' => 1520 , 'extid' => 'C0B786FD240C61' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_DISPLAY_ROOM_SENSOR_ACKNOW' },
    { 'idx' => 1521 , 'extid' => '069DCD5C2E0C46' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_E1x_T1_ALARM' },
    { 'idx' => 1523 , 'extid' => '8689CD82BB0C59' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ATTENUATION_FACTOR' },
    { 'idx' => 1525 , 'extid' => '86F8BC4DFA0C56' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_CHECK_DISPLAY_SYSTEM_ON' },
    { 'idx' => 1527 , 'extid' => '869AF0D7A60C4F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_COUPLINGDIFFERENS_ROOM' },
    { 'idx' => 1529 , 'extid' => '82C990BD440C1D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_D_VALUE' },
    { 'idx' => 1531 , 'extid' => '80E8533D5B0C37' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ENABLE_HEATING_BLOCK_BY_EXT' },
    { 'idx' => 1532 , 'extid' => '80C27420B00C3D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ENABLE_HIGH_PROTECTION_HS_BY_EXT' },
    { 'idx' => 1533 , 'extid' => '86A11C4ED20C4E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ERASE_EEPROM_NEXT_STARTUP' },
    { 'idx' => 1535 , 'extid' => '86C5C2A2160C06' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_EXTERNAL_TEMP_VALUE' },
    { 'idx' => 1537 , 'extid' => '81BF243E930C35' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_FREEZEGARD_START_DELAY_TIME' },
    { 'idx' => 1538 , 'extid' => '86B5B459E50BFE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_FREEZEGARD_START_TEMPERATURE' },
    { 'idx' => 1540 , 'extid' => '86A060B9E90BF9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_FREEZEGARD_STOP_TEMPERATURE' },
    { 'idx' => 1542 , 'extid' => '81244D29E40C58' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_COOLING_MODE' },
    { 'idx' => 1543 , 'extid' => '862F7ED68C0C2C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_LEFT_Y' },
    { 'idx' => 1545 , 'extid' => '86C58027CC0BF3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_PARALLEL_OFFSET' },
    { 'idx' => 1547 , 'extid' => '86191719180C02' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_RIGHT_Y' },
    { 'idx' => 1549 , 'extid' => '86B2BED34E0C20' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y1' },
    { 'idx' => 1551 , 'extid' => '86650D0D650C29' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y10' },
    { 'idx' => 1553 , 'extid' => '86120A3DF30C2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y11' },
    { 'idx' => 1555 , 'extid' => '868B036C490C2B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y12' },
    { 'idx' => 1557 , 'extid' => '862BB782F40C21' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y2' },
    { 'idx' => 1559 , 'extid' => '865CB0B2620C22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y3' },
    { 'idx' => 1561 , 'extid' => '86C2D427C10C23' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y4' },
    { 'idx' => 1563 , 'extid' => '86B5D317570C24' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y5' },
    { 'idx' => 1565 , 'extid' => '862CDA46ED0C25' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y6' },
    { 'idx' => 1567 , 'extid' => '865BDD767B0C26' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y7' },
    { 'idx' => 1569 , 'extid' => '86CB626BEA0C27' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y8' },
    { 'idx' => 1571 , 'extid' => '86BC655B7C0C28' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_CURVE_Y9' },
    { 'idx' => 1573 , 'extid' => '864805DCA40C47' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_DELAYED_TEMP' },
    { 'idx' => 1575 , 'extid' => '86474BC5CE0C15' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_IMMEDIATE_TEMP' },
    { 'idx' => 1577 , 'extid' => '867C4AD5D90C48' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_MODE' },
    { 'idx' => 1579 , 'extid' => '86E885BE8C0C17' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_START_DELAY_TIME' },
    { 'idx' => 1581 , 'extid' => '8678DC41BA0C18' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SEASON_STOP_DELAY_TIME' },
    { 'idx' => 1583 , 'extid' => '80F0DBEA330C36' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HEATING_SYSTEM_TYPE' },
    { 'idx' => 1584 , 'extid' => '808577AF980C08' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_ACTIVE' },
    { 'idx' => 1585 , 'extid' => '862CF8F3400C0A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_HOLIDAY_LEVEL_TEMPERATURE' },
    { 'idx' => 1587 , 'extid' => '018A2231010C3A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_START_DAY' },
    { 'idx' => 1588 , 'extid' => '815B6A58E30C39' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_START_MONTH' },
    { 'idx' => 1589 , 'extid' => '81078B72350C1F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_START_YEAR' },
    { 'idx' => 1590 , 'extid' => '81A13108F70C3F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_STOP_DAY' },
    { 'idx' => 1591 , 'extid' => '814689BDC30C3C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_STOP_MONTH' },
    { 'idx' => 1592 , 'extid' => '81537E36250C3B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_HOLIDAY_STOP_YEAR' },
    { 'idx' => 1593 , 'extid' => '8659A00D9D0C50' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INCREASE_ROOM_SETPOINT' },
    { 'idx' => 1595 , 'extid' => '80A999A8C60C51' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_AI1' },
    { 'idx' => 1596 , 'extid' => '803090F97C0C52' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_AI2' },
    { 'idx' => 1597 , 'extid' => '80AEF46CDF0C53' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_AI5' },
    { 'idx' => 1598 , 'extid' => '800030FE3F0C07' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_INVERT_EXT_INPUT' },
    { 'idx' => 1599 , 'extid' => '82A847DC840C1C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_I_VALUE' },
    { 'idx' => 1601 , 'extid' => '06D3E57E9A0C54' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_MAX_AI1' },
    { 'idx' => 1603 , 'extid' => '86F4C266F40BFC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_MAX_TEMPERAURE_GT41' },
    { 'idx' => 1605 , 'extid' => '86D0169ED50C55' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_MIN_AI1' },
    { 'idx' => 1607 , 'extid' => '8653F6E68D0BFD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_MIN_TEMPERAURE_GT41' },
    { 'idx' => 1609 , 'extid' => '8218113CB40BF4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_M_VALVE_DEFROST_DELAY' },
    { 'idx' => 1611 , 'extid' => '86B74895190C4D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_M_VALVE_LIMIT_TIME' },
    { 'idx' => 1613 , 'extid' => '82BFB011F10BFF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_M_VALVE_RUNNING_TIME' },
    { 'idx' => 1615 , 'extid' => '866A025FE00BF6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZONE_CONTROLLED' },
    { 'idx' => 1617 , 'extid' => '8613D517D20C2F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_M_VALVE_LIMIT' },
    { 'idx' => 1619 , 'extid' => '86D072F0BC0C30' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_M_VALVE_LIMIT_TIME' },
    { 'idx' => 1621 , 'extid' => '8628B63CE30C34' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_RAMP_DOWN_TIME' },
    { 'idx' => 1623 , 'extid' => '865CC0C9210C33' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_RAMP_UP_TIME' },
    { 'idx' => 1625 , 'extid' => '86ED0C7B6A0C2E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_SIZE' },
    { 'idx' => 1627 , 'extid' => '86286882970C32' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_TEMP_DECREASE_M_VALVE' },
    { 'idx' => 1629 , 'extid' => '8643F9DEE30C31' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_NEUTRALZON_TEMP_NO_INCREASE_M_VALVE' },
    { 'idx' => 1631 , 'extid' => '80620D2E210C0D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PARTY_MODE_ENABLE' },
    { 'idx' => 1632 , 'extid' => '862EBCC1F90C14' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PID_AIRSYSTEM_ACTIVE' },
    { 'idx' => 1634 , 'extid' => '828E5E20310C19' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PID_MAX_VALUE' },
    { 'idx' => 1636 , 'extid' => '8259B592700C1A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_PID_MIN_VALUE' },
    { 'idx' => 1638 , 'extid' => '825A0105990C1B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_P_VALUE' },
    { 'idx' => 1640 , 'extid' => '8117E506360C2D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ROOMSENSOR_INFLUENCE_FACTOR' },
    { 'idx' => 1641 , 'extid' => '814A526F5B0BF5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'rp2' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_ROOM_PROGRAM_MODE' },
    { 'idx' => 1642 , 'extid' => '8635FFD7B20C03' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_ROOM_SENSOR_ACTIVE' },
    { 'idx' => 1644 , 'extid' => '858E6674D50C38' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_T1_KORRIGERING' },
    { 'idx' => 1645 , 'extid' => '854EDF1E430C3E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_T5_KORRIGERING' },
    { 'idx' => 1646 , 'extid' => '86D947DA820C0B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_T5_SETPOINT' },
    { 'idx' => 1648 , 'extid' => '86C7DACCE10C0E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TEMP_TIMECONTROLLED' },
    { 'idx' => 1650 , 'extid' => '814713BEA40BDA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'rp1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM' },
    { 'idx' => 1651 , 'extid' => '82C52E3F910BE2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_5FRI' },
    { 'idx' => 1653 , 'extid' => '826A1151AC0BEA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_5FRI_2' },
    { 'idx' => 1655 , 'extid' => '82A87329CF0BDD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_1MON' },
    { 'idx' => 1657 , 'extid' => '82BAFDF97A0BEB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_1MON_2' },
    { 'idx' => 1659 , 'extid' => '82DD2A73410BE3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_6SAT' },
    { 'idx' => 1661 , 'extid' => '829443810C0BEC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_6SAT_2' },
    { 'idx' => 1663 , 'extid' => '820EE65D6E0BE4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_7SUN' },
    { 'idx' => 1665 , 'extid' => '825A8967620BED' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_7SUN_2' },
    { 'idx' => 1667 , 'extid' => '827EA0EE1B0BE1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_4THU' },
    { 'idx' => 1669 , 'extid' => '825AA978A10BEE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_4THU_2' },
    { 'idx' => 1671 , 'extid' => '829C7B92630BDF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_2TUE' },
    { 'idx' => 1673 , 'extid' => '82E4FC54930BEF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_2TUE_2' },
    { 'idx' => 1675 , 'extid' => '82A3F80EFD0BE0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_3WED' },
    { 'idx' => 1677 , 'extid' => '82F28713EB0BF0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 2 , 'text' => 'MV_E12_EEPROM_TIME_PROGRAM_3WED_2' },
    { 'idx' => 1679 , 'extid' => '864E663EA20BF1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_UI_BRAND' },
    { 'idx' => 1681 , 'extid' => '86145F89880C13' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EEPROM_VALVE_AO_0_10V_ACTIVE' },
    { 'idx' => 1683 , 'extid' => '00B485612A0C9C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_EXT_FUNCTION_TRIGGED' },
    { 'idx' => 1684 , 'extid' => '0694427BED0BFA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_FREEZEGUARD_ACTIVE' },
    { 'idx' => 1686 , 'extid' => '06A32DAD1C0BF2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_GT41_TEMP_SETPOINT' },
    { 'idx' => 1688 , 'extid' => '06A7558A6D0C57' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_GT5_DAMPING_FACTOR' },
    { 'idx' => 1690 , 'extid' => '068C603C020BDB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_HEATING_CURVE_NUMBER_OF_POINTS' },
    { 'idx' => 1692 , 'extid' => '00930B5D460C12' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_HEATING_SEASON_ACTIVE' },
    { 'idx' => 1693 , 'extid' => '00D1E8971A0BF8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_HIGHTEMP_HEATINGSYSTEM_ACTIVE' },
    { 'idx' => 1694 , 'extid' => '80C95FF0260C09' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_INTERNAL_HOLIDAY_ACTIVE' },
    { 'idx' => 1695 , 'extid' => '014E8C7DA50C0C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_INTERNAL_TIMECONTROLLED_ACTIVE' },
    { 'idx' => 1696 , 'extid' => '00BAEA25FC0C11' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_MAN_OP_G1' },
    { 'idx' => 1697 , 'extid' => '00C09E410C0C41' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_MAN_OP_VALVE_CLOSE' },
    { 'idx' => 1698 , 'extid' => '00ED44B0E30C40' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_MAN_OP_VALVE_OPEN' },
    { 'idx' => 1699 , 'extid' => '02ABF1A7610C00' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_PID_ISPOINT' },
    { 'idx' => 1701 , 'extid' => '028447AFD90C01' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_PID_SETPOINT' },
    { 'idx' => 1703 , 'extid' => '067BF2077E0BFB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_ROOMSENSOR_INFLUENCE' },
    { 'idx' => 1705 , 'extid' => '06DFBD330E0C05' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_ROOM_SENSOR_ACKNOW' },
    { 'idx' => 1707 , 'extid' => '064914CE5A0C0F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_ROOM_SETPOINT_TEMP_ACTIVE' },
    { 'idx' => 1709 , 'extid' => '00F7957AEF0BF7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_T1_ALARM' },
    { 'idx' => 1710 , 'extid' => '06D2EA70FD0C1E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_T1_TEMP' },
    { 'idx' => 1712 , 'extid' => '069E4CB8C50C10' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E12_T5_ATTENUATIONED_TEMP' },
    { 'idx' => 1714 , 'extid' => '0E497B32EB0C62' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'MV_E12_T5_TEMP' },
    { 'idx' => 1716 , 'extid' => '0662DE4E250C04' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_T5_TEMP_ACTIVE' },
    { 'idx' => 1718 , 'extid' => '062A58E9AC0D56' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_T5_TEMP_ACTIVE_TO_DISPLAY' },
    { 'idx' => 1720 , 'extid' => '02E74CBABE0BE7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_FRI' },
    { 'idx' => 1722 , 'extid' => '028A11ACE00BDC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_MON' },
    { 'idx' => 1724 , 'extid' => '02FF48F66E0BE8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_SAT' },
    { 'idx' => 1726 , 'extid' => '022C84D8410BE9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_SUN' },
    { 'idx' => 1728 , 'extid' => '025CC26B340BE6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_THU' },
    { 'idx' => 1730 , 'extid' => '02BE19174C0BDE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_TUE' },
    { 'idx' => 1732 , 'extid' => '02819A8BD20BE5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_TIME_PROGRAM_WED' },
    { 'idx' => 1734 , 'extid' => '063752F5180C43' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_VALVE_PID_ISPOINT' },
    { 'idx' => 1736 , 'extid' => '06AD02C5130C42' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E12_VALVE_PID_SETPOINT' },
    { 'idx' => 1738 , 'extid' => '0031A154580853' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_Q2_PRI_COOLING' },
    { 'idx' => 1739 , 'extid' => '00F81F2256091E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_Q2_SEC_COOLING' },
    { 'idx' => 1740 , 'extid' => '00CCBC30870767' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'MV_E31_T2_SENSOR_ALARM_GLOBAL' },
    { 'idx' => 1741 , 'extid' => '0A5F4B44470834' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_T31_SETPOINT' },
    { 'idx' => 1743 , 'extid' => '40C4A80D1E09E8' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_E31_T32_ACKNOWLEDGED' },
    { 'idx' => 1744 , 'extid' => '40CE6501E30A32' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_CONDENSATIONGUARD_BY_EXT_GLOBAL' },
    { 'idx' => 1745 , 'extid' => '40B74C1B5108FB' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_COOLING_BLOCK_BY_EXT_GLOBAL' },
    { 'idx' => 1746 , 'extid' => '406C8F3A590578' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_HEATING_BLOCK_BY_EXT_GLOBAL' },
    { 'idx' => 1747 , 'extid' => '409AF7088B0A31' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ENABLE_HIGH_PROTECTION_HS_BY_EXT_GLOBAL' },
    { 'idx' => 1748 , 'extid' => '00F33E82C3091F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_EX1_Q2_GLOBAL' },
    { 'idx' => 1749 , 'extid' => '014BD1F74D0A1A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_Ex_T1_ALARM_BITMASK' },
    { 'idx' => 1750 , 'extid' => '004328FEDD0A19' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_Ex_T1_ALARM_GLOBAL' },
    { 'idx' => 1751 , 'extid' => '01CEDE82B50A26' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_FREEZEGUARD_ACTIVE_BITMASK' },
    { 'idx' => 1752 , 'extid' => '00296DDE8F0A27' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_FREEZEGUARD_ACTIVE_GLOBAL' },
    { 'idx' => 1753 , 'extid' => '010C752B060A36' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HIGHTEMP_HS_ACTIVE_BITMASK' },
    { 'idx' => 1754 , 'extid' => '00553BCA330A34' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HIGHTEMP_HS_ACTIVE_GLOBAL' },
    { 'idx' => 1755 , 'extid' => '014A8CAE040D0E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HIGHTEMP_HS_ALERT_ACTIVE_BITMASK' },
    { 'idx' => 1756 , 'extid' => '011D09D77D0A59' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HOLIDAY_ACTIVE_BITMASK' },
    { 'idx' => 1757 , 'extid' => '0028CCEDE80A5A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_HOLIDAY_ACTIVE_GLOBAL' },
    { 'idx' => 1758 , 'extid' => '015BDD52580D08' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ICONS_TIMEPROGRAM_ACTIVE_BITMASK' },
    { 'idx' => 1759 , 'extid' => '0095F7B1470D09' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ICONS_TIMEPROGRAM_ACTIVE_GLOBAL' },
    { 'idx' => 1760 , 'extid' => '00300FAB940B96' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_INVERT_EXT_INPUT_GLOBAL' },
    { 'idx' => 1761 , 'extid' => '0A7A3C917204D8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_1' },
    { 'idx' => 1763 , 'extid' => '0AE335C0C804D9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_2' },
    { 'idx' => 1765 , 'extid' => '0A9432F05E04DA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_3' },
    { 'idx' => 1767 , 'extid' => '0A0A5665FD04DB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_4' },
    { 'idx' => 1769 , 'extid' => '0A7D51556B04DC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_5' },
    { 'idx' => 1771 , 'extid' => '0AE45804D104DD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_6' },
    { 'idx' => 1773 , 'extid' => '0A935F34470830' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_7' },
    { 'idx' => 1775 , 'extid' => '6ADE74765504D6' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_GLOBAL' },
    { 'idx' => 1777 , 'extid' => '0AFDAB16F504DE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_PRI_COOLING' },
    { 'idx' => 1779 , 'extid' => '0A341560FB0909' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_ACTUAL_SEC_COOLING' },
    { 'idx' => 1781 , 'extid' => '0AE10F410D04DF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_1' },
    { 'idx' => 1783 , 'extid' => '0A780610B704E0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_2' },
    { 'idx' => 1785 , 'extid' => '0A0F01202104E1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_3' },
    { 'idx' => 1787 , 'extid' => '0A9165B58204E2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_4' },
    { 'idx' => 1789 , 'extid' => '0AE662851404E3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_5' },
    { 'idx' => 1791 , 'extid' => '0A7F6BD4AE04E4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_6' },
    { 'idx' => 1793 , 'extid' => '0A086CE4380831' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_7' },
    { 'idx' => 1795 , 'extid' => '0A373AB0CA04D5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_GLOBAL' },
    { 'idx' => 1797 , 'extid' => '0A0863FF8104E5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_PRI_COOLING' },
    { 'idx' => 1799 , 'extid' => '0AC1DD898F090A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_PID_SETPOINT_SEC_COOLING' },
    { 'idx' => 1801 , 'extid' => '026BEA40690870' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ROOMSENSOR_KNOB_ALARM_BITMASK' },
    { 'idx' => 1803 , 'extid' => '00171A69A80871' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_ROOMSENSOR_KNOB_ALARM_GLOBAL' },
    { 'idx' => 1804 , 'extid' => '0E587BBBF90512' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_1' },
    { 'idx' => 1806 , 'extid' => '0EC172EA430513' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_2' },
    { 'idx' => 1808 , 'extid' => '0EB675DAD50514' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_3' },
    { 'idx' => 1810 , 'extid' => '0E28114F760515' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_4' },
    { 'idx' => 1812 , 'extid' => '0E5F167FE00516' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_5' },
    { 'idx' => 1814 , 'extid' => '0EC61F2E5A0517' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_6' },
    { 'idx' => 1816 , 'extid' => '0EB1181ECC0518' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_7' },
    { 'idx' => 1818 , 'extid' => '0E05AA65E90511' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_GLOBAL' },
    { 'idx' => 1820 , 'extid' => '0E8FEB0F7F090F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_PRI_COOLING' },
    { 'idx' => 1822 , 'extid' => '0E465579710910' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T1_SETPOINT_SEC_COOLING' },
    { 'idx' => 1824 , 'extid' => '8222C8523A0A22' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 5 , 'text' => 'MV_T5_ACKNOWLEDGED_BITMASK' },
    { 'idx' => 1826 , 'extid' => '0EEAC3175104FB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 5 , 'text' => 'MV_T5_ACTUAL_1' },
    { 'idx' => 1828 , 'extid' => '0EC3E07A4A0D14' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_1_ROUND_OFFED' },
    { 'idx' => 1830 , 'extid' => '0E73CA46EB04FC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_2' },
    { 'idx' => 1832 , 'extid' => '0E7E2A16840D15' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_2_ROUND_OFFED' },
    { 'idx' => 1834 , 'extid' => '0E04CD767D04FD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_3' },
    { 'idx' => 1836 , 'extid' => '0EA3BCCF010D16' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_3_ROUND_OFFED' },
    { 'idx' => 1838 , 'extid' => '0E9AA9E3DE04FE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_4' },
    { 'idx' => 1840 , 'extid' => '0EDECFC9590D17' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_4_ROUND_OFFED' },
    { 'idx' => 1842 , 'extid' => '0EEDAED34804FF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_5' },
    { 'idx' => 1844 , 'extid' => '0E035910DC0D18' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_5_ROUND_OFFED' },
    { 'idx' => 1846 , 'extid' => '0E74A782F20500' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_6' },
    { 'idx' => 1848 , 'extid' => '0EBE937C120D19' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_6_ROUND_OFFED' },
    { 'idx' => 1850 , 'extid' => '0E03A0B2640501' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_7' },
    { 'idx' => 1852 , 'extid' => '0E6305A5970D1A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_7_ROUND_OFFED' },
    { 'idx' => 1854 , 'extid' => '0E5FFE749104D7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_GLOBAL' },
    { 'idx' => 1856 , 'extid' => '0E850DA7390835' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_PRI_COOLING' },
    { 'idx' => 1858 , 'extid' => '0E4CB3D137090C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ACTUAL_SEC_COOLING' },
    { 'idx' => 1860 , 'extid' => '0E345582290D66' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_1' },
    { 'idx' => 1862 , 'extid' => '0EAD5CD3930D67' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_2' },
    { 'idx' => 1864 , 'extid' => '0EDA5BE3050D68' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_3' },
    { 'idx' => 1866 , 'extid' => '0E443F76A60D69' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_4' },
    { 'idx' => 1868 , 'extid' => '0E333846300D6A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_5' },
    { 'idx' => 1870 , 'extid' => '0EAA31178A0D6B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_6' },
    { 'idx' => 1872 , 'extid' => '0EDD36271C0D6C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_7' },
    { 'idx' => 1874 , 'extid' => '0EF282A04A0D64' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_PRI_COOLING' },
    { 'idx' => 1876 , 'extid' => '0E3B3CD6440D65' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_ATTENUATED_SEC_COOLING' },
    { 'idx' => 1878 , 'extid' => '82F9B521CB0A23' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_CONNECTED_BITMASK' },
    { 'idx' => 1880 , 'extid' => '0E5B7D80860519' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_1' },
    { 'idx' => 1882 , 'extid' => '0EC274D13C051A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_2' },
    { 'idx' => 1884 , 'extid' => '0EB573E1AA051B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_3' },
    { 'idx' => 1886 , 'extid' => '0E2B177409051C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_4' },
    { 'idx' => 1888 , 'extid' => '0E5C10449F051D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_5' },
    { 'idx' => 1890 , 'extid' => '0EC5191525051E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_6' },
    { 'idx' => 1892 , 'extid' => '0EB21E25B3051F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_7' },
    { 'idx' => 1894 , 'extid' => '0EFDDE46C00D6E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_1' },
    { 'idx' => 1896 , 'extid' => '0E64D7177A0D74' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_2' },
    { 'idx' => 1898 , 'extid' => '0E13D027EC0D73' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_3' },
    { 'idx' => 1900 , 'extid' => '0E8DB4B24F0D72' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_4' },
    { 'idx' => 1902 , 'extid' => '0EFAB382D90D71' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_5' },
    { 'idx' => 1904 , 'extid' => '0E63BAD3630D70' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_6' },
    { 'idx' => 1906 , 'extid' => '0E14BDE3F50D6F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_7' },
    { 'idx' => 1908 , 'extid' => '0ED154A6430D77' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_GLOBAL' },
    { 'idx' => 1910 , 'extid' => '0E8B8A97610D75' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_PRI_COOLING' },
    { 'idx' => 1912 , 'extid' => '0E4234E16F0D76' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_ACTUAL_SEC_COOLING' },
    { 'idx' => 1914 , 'extid' => '0ED34A9C7F0855' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_PRI_COOLING' },
    { 'idx' => 1916 , 'extid' => '0E1AF4EA71090D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_T5_SETPOINT_SEC_COOLING' },
    { 'idx' => 1918 , 'extid' => '021DD1D0B408F7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_1' },
    { 'idx' => 1920 , 'extid' => '0284D8810E08F8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_2' },
    { 'idx' => 1922 , 'extid' => '02F3DFB1980989' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_3' },
    { 'idx' => 1924 , 'extid' => '026DBB243B08F9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_4' },
    { 'idx' => 1926 , 'extid' => '021ABC14AD098A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_5' },
    { 'idx' => 1928 , 'extid' => '0283B54517098B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_6' },
    { 'idx' => 1930 , 'extid' => '02F4B27581098C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_7' },
    { 'idx' => 1932 , 'extid' => '02100FEAE50854' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_GLOBAL' },
    { 'idx' => 1934 , 'extid' => '0217273D8C08F6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_PRI_COOLING' },
    { 'idx' => 1936 , 'extid' => '02DE994B820905' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'MV_TIMER_HEATING_COOLING_DELAY_SEC_COOLING' },
    { 'idx' => 1938 , 'extid' => '406AE0502C08BD' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_1' },
    { 'idx' => 1939 , 'extid' => '40F3E9019608BE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_2' },
    { 'idx' => 1940 , 'extid' => '4084EE310008BF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_3' },
    { 'idx' => 1941 , 'extid' => '401A8AA4A308C0' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_4' },
    { 'idx' => 1942 , 'extid' => '406D8D943508C1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_5' },
    { 'idx' => 1943 , 'extid' => '40F484C58F08C2' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PARTY_MODE_CIRCUIT_6' },
    { 'idx' => 1944 , 'extid' => '408383F51908C3' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_7' },
    { 'idx' => 1945 , 'extid' => '40133CE88808C4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_8' },
    { 'idx' => 1946 , 'extid' => '0059F750990920' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_CIRCUIT_GLOBAL' },
    { 'idx' => 1947 , 'extid' => '616A0C202C08CF' , 'max' =>       99 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_TIME' },
    { 'idx' => 1948 , 'extid' => 'C091347AF3003A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_ACTIVATED' },
    { 'idx' => 1949 , 'extid' => '00BB8F91DB00C1' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CONNECTED' },
    { 'idx' => 1950 , 'extid' => 'ED6CE96123003C' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CORRECTION_L1_A' },
    { 'idx' => 1951 , 'extid' => 'ED6EAFDF7A003D' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CORRECTION_L2_A' },
    { 'idx' => 1952 , 'extid' => 'ED6F6DB54D003E' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CORRECTION_L3_A' },
    { 'idx' => 1953 , 'extid' => 'E92776E2860043' , 'max' =>       10 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_CURRENT_MARGIN' },
    { 'idx' => 1954 , 'extid' => '0A9F3BFEB9003F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_L1_A' },
    { 'idx' => 1956 , 'extid' => '0A9D7D40E00040' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_L2_A' },
    { 'idx' => 1958 , 'extid' => '0A9CBF2AD70041' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_L3_A' },
    { 'idx' => 1960 , 'extid' => 'E1D4B3F692003B' , 'max' =>       50 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_MAIN_FUSE' },
    { 'idx' => 1961 , 'extid' => 'E23E5BFE060044' , 'max' =>      600 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_RECONNECTION_TIME' },
    { 'idx' => 1963 , 'extid' => 'E2943A16910042' , 'max' =>      400 , 'min' =>      230 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_SUPPLY_VOLTAGE' },
    { 'idx' => 1965 , 'extid' => '002D1E85D10045' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED' },
    { 'idx' => 1966 , 'extid' => '00733F9A0E0046' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_PHASE1' },
    { 'idx' => 1967 , 'extid' => '00EA36CBB40047' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_PHASE2' },
    { 'idx' => 1968 , 'extid' => '009D31FB220048' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_PHASE3' },
    { 'idx' => 1969 , 'extid' => 'E25CA4C19F0049' , 'max' =>      300 , 'min' =>        5 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_TRIGGERED_TIME' },
    { 'idx' => 1971 , 'extid' => '12C6A967E500C2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PGU_VERSION' },
    { 'idx' => 1973 , 'extid' => 'C0CBCCD18A0957' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PHASE_DETECTOR_ACKNOWLEDGED' },
    { 'idx' => 1974 , 'extid' => 'C084955BAB0958' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PHASE_DETECTOR_ACKNOWLEDGED_2' },
    { 'idx' => 1975 , 'extid' => 'C0DC2828E804BE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_ACTIVE' },
    { 'idx' => 1976 , 'extid' => 'C08C59297F0A02' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_BLOCKED_BY_EXT' },
    { 'idx' => 1977 , 'extid' => 'E18194411004C1' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_CONST' },
    { 'idx' => 1978 , 'extid' => 'E1FF34E027068D' , 'max' =>       20 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_CONST_2' },
    { 'idx' => 1979 , 'extid' => 'ED3DDCC31204BF' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MAX' },
    { 'idx' => 1980 , 'extid' => 'EDCEB4DCE1068E' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MAX_2' },
    { 'idx' => 1981 , 'extid' => 'ED01D1FC4B04C0' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MIN' },
    { 'idx' => 1982 , 'extid' => 'ED13AB2BCC068F' , 'max' =>       50 , 'min' =>        2 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_DIFF_MIN_2' },
    { 'idx' => 1983 , 'extid' => '00510392C90A03' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_EXTERN_BLOCKED' },
    { 'idx' => 1984 , 'extid' => '80D0ADB7850B9C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_EXT_INPUT_INV' },
    { 'idx' => 1985 , 'extid' => 'EA30756EF404C3' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_D' },
    { 'idx' => 1987 , 'extid' => 'EA4EC4124904C4' , 'max' =>     6000 , 'min' =>       50 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_I' },
    { 'idx' => 1989 , 'extid' => 'E61800D661054D' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_MAX' },
    { 'idx' => 1991 , 'extid' => 'E6240DE938054E' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_MIN' },
    { 'idx' => 1993 , 'extid' => 'EA2AAFBA8904C5' , 'max' =>      300 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_PID_P' },
    { 'idx' => 1995 , 'extid' => '0040B192E504C2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_REQUEST' },
    { 'idx' => 1996 , 'extid' => '008925B7940679' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_REQUEST_2' },
    { 'idx' => 1997 , 'extid' => 'EE4914843A04BD' , 'max' =>      400 , 'min' =>       40 , 'format' => 'tem' , 'read' => 0 , 'text' => 'POOL_SETPOINT_TEMP' },
    { 'idx' => 1999 , 'extid' => 'E161A234AF0A24' , 'max' =>      240 , 'min' =>       15 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_START_DELAY_TIME' },
    { 'idx' => 2000 , 'extid' => '0E178B819A0D1C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'POOL_START_TEMP' },
    { 'idx' => 2002 , 'extid' => '063848EA380D1D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_STOP_TEMP' },
    { 'idx' => 2004 , 'extid' => 'C07A64C1EC0827' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_USE_COMPRESSOR_1' },
    { 'idx' => 2005 , 'extid' => 'C0E36D90560826' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_USE_COMPRESSOR_2' },
    { 'idx' => 2006 , 'extid' => 'E114ED4791054F' , 'max' =>       60 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_VALVE_DELAY_AFTER_DEFROST' },
    { 'idx' => 2007 , 'extid' => 'EA2ACC5E79075D' , 'max' =>     1000 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_VALVE_POSITION' },
    { 'idx' => 2009 , 'extid' => 'E210798BA3054C' , 'max' =>     6000 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_VALVE_RUNNING_TIME' },
    { 'idx' => 2011 , 'extid' => '019A57F78D089A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POPUP_WINDOW_DELAY' },
    { 'idx' => 2012 , 'extid' => '0144B7AB4C01CA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PROGRAM_GENERATION' },
    { 'idx' => 2013 , 'extid' => '011A75548400C3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PROGRAM_REVISION' },
    { 'idx' => 2014 , 'extid' => '02AE6D0DE200C4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PROGRAM_VERSION' },
    { 'idx' => 2016 , 'extid' => 'C0A53F3F7D02FE' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'PUMP_DHW_ACTIVE' },
    { 'idx' => 2017 , 'extid' => 'E193B840CB0774' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM1_START_TIME' },
    { 'idx' => 2018 , 'extid' => 'E17DBA37BD0775' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM1_STOP_TIME' },
    { 'idx' => 2019 , 'extid' => 'E1E426923B0776' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM2_START_TIME' },
    { 'idx' => 2020 , 'extid' => 'E1E45851BC0777' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM2_STOP_TIME' },
    { 'idx' => 2021 , 'extid' => 'E17F83DE540778' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM3_START_TIME' },
    { 'idx' => 2022 , 'extid' => 'E125D68E7C0779' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM3_STOP_TIME' },
    { 'idx' => 2023 , 'extid' => 'E10B1B37DB077A' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM4_START_TIME' },
    { 'idx' => 2024 , 'extid' => 'E10CED9BFF077B' , 'max' =>       96 , 'min' =>        0 , 'format' => 't15' , 'read' => 1 , 'text' => 'PUMP_DHW_PROGRAM4_STOP_TIME' },
    { 'idx' => 2025 , 'extid' => 'C05AF5405A09A2' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_BLOCKED_BY_EXT' },
    { 'idx' => 2026 , 'extid' => 'E1612C0C7E066A' , 'max' =>       20 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_START_DIFF' },
    { 'idx' => 2027 , 'extid' => 'C0B3960C7E0669' , 'max' => 33554432 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_START_MODE' },
    { 'idx' => 2028 , 'extid' => 'E12F0FCE1F066B' , 'max' =>       90 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E71_G71_START_TEMP' },
    { 'idx' => 2029 , 'extid' => 'C0F55C0D9009A3' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_BLOCKED_BY_EXT' },
    { 'idx' => 2030 , 'extid' => 'E148E4B88C07D2' , 'max' =>       20 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_START_DIFF' },
    { 'idx' => 2031 , 'extid' => 'C09A5EB88C07D1' , 'max' => 33554432 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_START_MODE' },
    { 'idx' => 2032 , 'extid' => 'E106C77AED07D3' , 'max' =>       90 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_E72_G71_START_TEMP' },
    { 'idx' => 2033 , 'extid' => 'C0AD220E5C0341' , 'max' =>134217728 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G1_CONTINUAL' },
    { 'idx' => 2034 , 'extid' => 'C034C0685D02FA' , 'max' =>134217728 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_CONTINUAL' },
    { 'idx' => 2035 , 'extid' => 'E1C0D22EBB02FC' , 'max' =>       35 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_LOW_TEMPERATURE' },
    { 'idx' => 2036 , 'extid' => 'E195C275E60565' , 'max' =>       99 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_MAX_TEMPERATURE' },
    { 'idx' => 2037 , 'extid' => 'C0C820AFFD0981' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_ACTIVE_IN_COOLING' },
    { 'idx' => 2038 , 'extid' => 'C0F54EB79D02FB' , 'max' =>134217728 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_CONTINUAL' },
    { 'idx' => 2039 , 'extid' => 'C04997E841030D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E21_EXT_1' },
    { 'idx' => 2040 , 'extid' => 'C0D09EB9FB0490' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E21_EXT_2' },
    { 'idx' => 2041 , 'extid' => 'C0787FF2DC0B58' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E22_EXT_1' },
    { 'idx' => 2042 , 'extid' => 'C0E176A3660B57' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVATED_BY_E22_EXT_2' },
    { 'idx' => 2043 , 'extid' => '0088C4B29B0301' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_EXTERN_ACTIVE' },
    { 'idx' => 2044 , 'extid' => 'C06FE120A603ED' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E21_EXT_1' },
    { 'idx' => 2045 , 'extid' => 'C0F6E8711C0491' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E21_EXT_2' },
    { 'idx' => 2046 , 'extid' => 'C05E093A3B0B59' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E22_EXT_1' },
    { 'idx' => 2047 , 'extid' => 'C0C7006B810B5A' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVATED_BY_E22_EXT_2' },
    { 'idx' => 2048 , 'extid' => '00E7008FF203EC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_LOW_PRESSURE_HEAT_CARRIER_ACTIVE' },
    { 'idx' => 2049 , 'extid' => 'E10F14FDE50052' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MAX_HASTIGHET' },
    { 'idx' => 2050 , 'extid' => 'C1AA37C2AE0053' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MAX_SPEED_AT_COMPRESSOR_FREQUENCY' },
    { 'idx' => 2051 , 'extid' => 'C14F5B85930054' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MIN_HASTIGHET' },
    { 'idx' => 2052 , 'extid' => 'C1810D090C0055' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G3_MIN_SPEED_AT_COMPRESSOR_FREQUENCY' },
    { 'idx' => 2053 , 'extid' => '00BC04CC910170' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'REMOTE_GET_DISPLAY' },
    { 'idx' => 2054 , 'extid' => '401844310700E2' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_LARMHISTORY' },
    { 'idx' => 2055 , 'extid' => '40E7A15E1F0B0F' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_LARMINFO' },
    { 'idx' => 2056 , 'extid' => '407ECEAB5B00E3' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_LARMLOG' },
    { 'idx' => 2057 , 'extid' => '40ACCAC30100E4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESET_SYSVAR' },
    { 'idx' => 2058 , 'extid' => '0005DE7D17035C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RESTART_ADDITIONAL_TIMER_BLOCKED' },
    { 'idx' => 2059 , 'extid' => '00C84276310169' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RIGGKORNING' },
    { 'idx' => 2060 , 'extid' => '00C5942E8000E7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_BLOCK' },
    { 'idx' => 2061 , 'extid' => 'C0F28707F00243' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_BUZZER_BLOCKED' },
    { 'idx' => 2062 , 'extid' => 'E1E543D41F00EB' , 'max' =>        6 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_DIAL_RANGE' },
    { 'idx' => 2063 , 'extid' => '6107058A0B03CD' , 'max' =>        6 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_DIAL_RANGE_GLOBAL' },
    { 'idx' => 2064 , 'extid' => 'EE3FBC687F0580' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E21_EXT_1' },
    { 'idx' => 2066 , 'extid' => 'EEA6B539C50581' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E21_EXT_2' },
    { 'idx' => 2068 , 'extid' => 'EE0E5472E20B54' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E22_EXT_1' },
    { 'idx' => 2070 , 'extid' => 'EE975D23580B53' , 'max' =>      350 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_BY_E22_EXT_2' },
    { 'idx' => 2072 , 'extid' => '6E3FCBFD6C03CE' , 'max' =>      350 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_SETPOINT_TEMP_GLOBAL' },
    { 'idx' => 2074 , 'extid' => '003F4C64300307' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_1' },
    { 'idx' => 2075 , 'extid' => '00A645358A0582' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_2' },
    { 'idx' => 2076 , 'extid' => '00D142051C0B5D' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_3' },
    { 'idx' => 2077 , 'extid' => '004F2690BF0B5E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_EXTERN_TEMPERATURE_ACTIVE_4' },
    { 'idx' => 2078 , 'extid' => 'EE68497B9C0782' , 'max' =>      350 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ROOM_HOLIDAY_SETPOINT_BASE_TEMP' },
    { 'idx' => 2080 , 'extid' => '6E0332AF180783' , 'max' =>      350 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_HOLIDAY_SETPOINT_BASE_TEMP_GLOBAL' },
    { 'idx' => 2082 , 'extid' => '0E70AF9DB500E9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_INFLUENCE' },
    { 'idx' => 2084 , 'extid' => 'E935C24AA700EA' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_INFLUENCE_CONST' },
    { 'idx' => 2085 , 'extid' => '699921DC4403CC' , 'max' =>      100 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_INFLUENCE_CONST_GLOBAL' },
    { 'idx' => 2086 , 'extid' => '406435D2B50CEF' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_LED_ALLOWED' },
    { 'idx' => 2087 , 'extid' => 'C04D975754077C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_LED_BLOCKED' },
    { 'idx' => 2088 , 'extid' => 'C2F7E587150294' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_5FRI' },
    { 'idx' => 2090 , 'extid' => 'C29AB8914B028F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_1MON' },
    { 'idx' => 2092 , 'extid' => 'C2EFE1CBC50296' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_6SAT' },
    { 'idx' => 2094 , 'extid' => 'C23C2DE5EA0298' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_7SUN' },
    { 'idx' => 2096 , 'extid' => 'C24C6B569F0293' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_4THU' },
    { 'idx' => 2098 , 'extid' => 'C2AEB02AE70290' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_2TUE' },
    { 'idx' => 2100 , 'extid' => 'C29133B6790291' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_1_3WED' },
    { 'idx' => 2102 , 'extid' => 'C2B045FDC50295' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_5FRI' },
    { 'idx' => 2104 , 'extid' => 'C2DD18EB9B0299' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_1MON' },
    { 'idx' => 2106 , 'extid' => 'C2A841B1150297' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_6SAT' },
    { 'idx' => 2108 , 'extid' => 'C27B8D9F3A029C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_7SUN' },
    { 'idx' => 2110 , 'extid' => 'C20BCB2C4F029B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_4THU' },
    { 'idx' => 2112 , 'extid' => 'C2E9105037029A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_2TUE' },
    { 'idx' => 2114 , 'extid' => 'C2D693CCA90292' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_2_3WED' },
    { 'idx' => 2116 , 'extid' => '42363DB8840611' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_FRI_GLOBAL' },
    { 'idx' => 2118 , 'extid' => 'E1049063EA0464' , 'max' =>        3 , 'min' =>        0 , 'format' => 'rp2' , 'read' => 1 , 'text' => 'ROOM_PROGRAM_MODE' },
    { 'idx' => 2119 , 'extid' => '61961A9F6C07C5' , 'max' =>        3 , 'min' =>        0 , 'format' => 'rp2' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_MODE_GLOBAL' },
    { 'idx' => 2120 , 'extid' => '429997EF4C0614' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_MON_GLOBAL' },
    { 'idx' => 2122 , 'extid' => '428549A8660612' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_SAT_GLOBAL' },
    { 'idx' => 2124 , 'extid' => '42991E96F80613' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_SUN_GLOBAL' },
    { 'idx' => 2126 , 'extid' => '42079C05DA0617' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_THU_GLOBAL' },
    { 'idx' => 2128 , 'extid' => '4226A891D70615' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_TUE_GLOBAL' },
    { 'idx' => 2130 , 'extid' => '42ADF5683B0616' , 'max' =>        0 , 'min' =>        0 , 'format' => 'sw1' , 'read' => 0 , 'text' => 'ROOM_PROGRAM_WED_GLOBAL' },
    { 'idx' => 2132 , 'extid' => '80863E34500CC4' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_SENSOR_SHOW_OUTDOOR_TEMP' },
    { 'idx' => 2133 , 'extid' => 'EE6446CFDB00E8' , 'max' =>      350 , 'min' =>      100 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ROOM_SETPOINT_BASE_TEMP' },
    { 'idx' => 2135 , 'extid' => '6ECB439DE5046E' , 'max' =>      350 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_SETPOINT_BASE_TEMP_GLOBAL' },
    { 'idx' => 2137 , 'extid' => '0ED933E0190188' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_SETPOINT_OFFSET' },
    { 'idx' => 2139 , 'extid' => '0EB8115D5C0470' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_SETPOINT_OFFSET_GLOBAL' },
    { 'idx' => 2141 , 'extid' => '0EF53B34510189' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'ROOM_SETPOINT_TEMP' },
    { 'idx' => 2143 , 'extid' => '0087BA736D026A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ROOM_TIMECONTROLLED' },
    { 'idx' => 2144 , 'extid' => 'E14AFE95E8029D' , 'max' =>        6 , 'min' =>        0 , 'format' => 'rp1' , 'read' => 1 , 'text' => 'ROOM_TIMEPROGRAM' },
    { 'idx' => 2145 , 'extid' => 'EE8DE6431B046A' , 'max' =>      300 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_TIMEPROGRAMMED_SETPOINT_BASE_TEMP' },
    { 'idx' => 2147 , 'extid' => '6EB57C47E9046F' , 'max' =>      300 , 'min' =>      100 , 'format' => 'tem' , 'read' => 0 , 'text' => 'ROOM_TIMEPROGRAMMED_SETPOINT_BASE_TEMP_GLOBAL' },
    { 'idx' => 2149 , 'extid' => '619F8792630618' , 'max' =>        6 , 'min' =>        0 , 'format' => 'rp1' , 'read' => 0 , 'text' => 'ROOM_TIMEPROGRAM_GLOBAL' },
    { 'idx' => 2150 , 'extid' => '01032AAD1F00E5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED' },
    { 'idx' => 2151 , 'extid' => '01D110D005044E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_2' },
    { 'idx' => 2152 , 'extid' => '01A617E093044F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_3' },
    { 'idx' => 2153 , 'extid' => '01387375300450' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_4' },
    { 'idx' => 2154 , 'extid' => '014F7445A60451' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_5' },
    { 'idx' => 2155 , 'extid' => '01D67D141C0452' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_6' },
    { 'idx' => 2156 , 'extid' => '01A17A248A0453' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_7' },
    { 'idx' => 2157 , 'extid' => '0131C5391B0454' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_8' },
    { 'idx' => 2158 , 'extid' => '81D5BA54CD063B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_BITMASK' },
    { 'idx' => 2159 , 'extid' => '014C1EDDDA056F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_CONNECTED_GLOBAL' },
    { 'idx' => 2160 , 'extid' => '01DE529BB00CDC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION' },
    { 'idx' => 2161 , 'extid' => '01373538C20CDE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_2' },
    { 'idx' => 2162 , 'extid' => '01403208540CE0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_3' },
    { 'idx' => 2163 , 'extid' => '01DE569DF70CE2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_4' },
    { 'idx' => 2164 , 'extid' => '01A951AD610CE4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_5' },
    { 'idx' => 2165 , 'extid' => '013058FCDB0CE6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_6' },
    { 'idx' => 2166 , 'extid' => '01475FCC4D0CE9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_7' },
    { 'idx' => 2167 , 'extid' => '01D7E0D1DC0CEB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_GENERATION_8' },
    { 'idx' => 2168 , 'extid' => '019CE0CE7A0CDD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION' },
    { 'idx' => 2169 , 'extid' => '011D21E0CF0CDF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_2' },
    { 'idx' => 2170 , 'extid' => '016A26D0590CE1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_3' },
    { 'idx' => 2171 , 'extid' => '01F44245FA0CE3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_4' },
    { 'idx' => 2172 , 'extid' => '018345756C0CE5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_5' },
    { 'idx' => 2173 , 'extid' => '011A4C24D60CE7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_6' },
    { 'idx' => 2174 , 'extid' => '016D4B14400CE8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_7' },
    { 'idx' => 2175 , 'extid' => '01FDF409D10CEA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_REVISION_8' },
    { 'idx' => 2176 , 'extid' => '00556417180C63' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_SUPPORTS_NEW_MESSAGES' },
    { 'idx' => 2177 , 'extid' => '01D97B1C4D0D0A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_SUPPORTS_NEW_MESSAGES_BITMASK' },
    { 'idx' => 2178 , 'extid' => '01D3619DF80C64' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_SYSTEM_STATUS' },
    { 'idx' => 2179 , 'extid' => '01E825273200E6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION' },
    { 'idx' => 2180 , 'extid' => '01FC570BDB0455' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_2' },
    { 'idx' => 2181 , 'extid' => '018B503B4D0456' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_3' },
    { 'idx' => 2182 , 'extid' => '011534AEEE0457' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_4' },
    { 'idx' => 2183 , 'extid' => '0162339E780458' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_5' },
    { 'idx' => 2184 , 'extid' => '01FB3ACFC20459' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_6' },
    { 'idx' => 2185 , 'extid' => '018C3DFF54045A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_7' },
    { 'idx' => 2186 , 'extid' => '011C82E2C5045B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RTU800B_VERSION_8' },
    { 'idx' => 2187 , 'extid' => 'C06BA627980538' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_ACTIVATED' },
    { 'idx' => 2188 , 'extid' => '02FC92B4A40665' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_COOLING_STEP_COUNT' },
    { 'idx' => 2190 , 'extid' => 'C13D579DFB0668' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_CURRENT_HOUR' },
    { 'idx' => 2191 , 'extid' => 'C21039876A053F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_CURRENT_PROGRAM_STEP' },
    { 'idx' => 2193 , 'extid' => 'E1A4D2CE57053E' , 'max' =>       20 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_DAYS_AT_MAX_TEMPERATURE' },
    { 'idx' => 2194 , 'extid' => 'E1872A8838053C' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_DAYS_PER_COOLING_STEP' },
    { 'idx' => 2195 , 'extid' => 'E11DC6A468053B' , 'max' =>        5 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_DAYS_PER_HEATING_STEP' },
    { 'idx' => 2196 , 'extid' => '029800BDF00666' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_HEATING_STEP_COUNT' },
    { 'idx' => 2198 , 'extid' => 'E17317C0720A89' , 'max' =>        2 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_HEAT_SOURCE' },
    { 'idx' => 2199 , 'extid' => 'C036C36C230764' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_INCOMPLETE' },
    { 'idx' => 2200 , 'extid' => 'EE85AEC727053D' , 'max' =>      600 , 'min' =>      250 , 'format' => 'tem' , 'read' => 0 , 'text' => 'SCREED_DRYING_MAX_TEMPERATURE' },
    { 'idx' => 2202 , 'extid' => '020761939A0649' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_PROGRAM_STEP_COUNT' },
    { 'idx' => 2204 , 'extid' => '0CF05D8A3C0537' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_REQUEST' },
    { 'idx' => 2205 , 'extid' => '0E7542150E0536' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 0 , 'text' => 'SCREED_DRYING_SETPOINT_TEMP' },
    { 'idx' => 2207 , 'extid' => 'E980506DE3053A' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_TEMPERATURE_STEP_COOLING' },
    { 'idx' => 2208 , 'extid' => 'E90951DB6E0539' , 'max' =>      100 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_TEMPERATURE_STEP_HEATING' },
    { 'idx' => 2209 , 'extid' => '00970D250700A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREENSAVER_ACTIVE' },
    { 'idx' => 2210 , 'extid' => 'E1F3115A2800A8' , 'max' =>      240 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREENSAVER_DELAY_TIME' },
    { 'idx' => 2211 , 'extid' => 'ED0EEADA7F0AB9' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T1_CORRECTION' },
    { 'idx' => 2212 , 'extid' => '0EAC7E06AF0AB2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T1_DISPLAY_TEMP' },
    { 'idx' => 2214 , 'extid' => '009F37E8480AB3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T1_STATUS' },
    { 'idx' => 2215 , 'extid' => '0E4ABFEB090AB4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T1_TEMP' },
    { 'idx' => 2217 , 'extid' => 'EDE2D144E00AB5' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T3_CORRECTION' },
    { 'idx' => 2218 , 'extid' => '0E4D10C2020AB6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T3_DISPLAY_TEMP' },
    { 'idx' => 2220 , 'extid' => '00DD12EF350AB7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T3_STATUS' },
    { 'idx' => 2221 , 'extid' => '0E07774A020AB8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T3_TEMP' },
    { 'idx' => 2223 , 'extid' => 'EDE1D77F9F0AAE' , 'max' =>       50 , 'min' =>      -50 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T7_CORRECTION' },
    { 'idx' => 2224 , 'extid' => '0E54BC4D190AAF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T7_DISPLAY_TEMP' },
    { 'idx' => 2226 , 'extid' => '005958E1CF0AB0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SENSORS_E74_T7_STATUS' },
    { 'idx' => 2227 , 'extid' => '0E9CE608140AB1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'tem' , 'read' => 1 , 'text' => 'SENSORS_E74_T7_TEMP' },
    { 'idx' => 2229 , 'extid' => 'C048543205094C' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SETUP_COMPLETED' },
    { 'idx' => 2230 , 'extid' => 'C029E15D980AFE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_ACTIVATED' },
    { 'idx' => 2231 , 'extid' => '00F055A4120A8E' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_ACTIVE' },
    { 'idx' => 2232 , 'extid' => '006BE7E0830A95' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_DHW_BLOCK' },
    { 'idx' => 2233 , 'extid' => 'E977D8E0F20A8F' , 'max' =>      200 , 'min' =>       70 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_DIFF_START_TEMP' },
    { 'idx' => 2234 , 'extid' => 'E9DBA757A70A90' , 'max' =>      200 , 'min' =>       35 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_DIFF_STOP_TEMP' },
    { 'idx' => 2235 , 'extid' => '0057AFD8D50A97' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_FREEZEGUARD_ACTIVE' },
    { 'idx' => 2236 , 'extid' => 'E9AEA686120A98' , 'max' =>      100 , 'min' =>       40 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_FREEZEGUARD_START_TEMP' },
    { 'idx' => 2237 , 'extid' => 'E9739B6B4E0A99' , 'max' =>      100 , 'min' =>       40 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_FREEZEGUARD_STOP_TEMP' },
    { 'idx' => 2238 , 'extid' => 'C014177C850A91' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_PIPE_FUNCTION' },
    { 'idx' => 2239 , 'extid' => 'EAA1EA86E90A96' , 'max' =>      610 , 'min' =>       90 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_PRIO_DHW_BLOCK_TEMP' },
    { 'idx' => 2241 , 'extid' => 'C01D7E5FC10A9A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_SOUTHEUROPE' },
    { 'idx' => 2242 , 'extid' => '00C060CDDB0AF0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_HIGH' },
    { 'idx' => 2243 , 'extid' => '00992F192F0AEF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_LOW' },
    { 'idx' => 2244 , 'extid' => 'E1F032413D0A92' , 'max' =>      140 , 'min' =>      100 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_MAX_TEMP' },
    { 'idx' => 2245 , 'extid' => 'E11652EEDC0A93' , 'max' =>       80 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T1_MIN_TEMP' },
    { 'idx' => 2246 , 'extid' => '0016392EC60B07' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T7_HIGH' },
    { 'idx' => 2247 , 'extid' => 'E1FD2C317A0A94' , 'max' =>       90 , 'min' =>       20 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T7_MAX_TEMP' },
    { 'idx' => 2248 , 'extid' => 'E12CB8BDE70A9B' , 'max' =>       10 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'SOLAR_T7_RESTART_DIFF' },
    { 'idx' => 2249 , 'extid' => '839188B45602A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_DHW' },
    { 'idx' => 2253 , 'extid' => '8394C01E2B0694' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_DHW_2' },
    { 'idx' => 2257 , 'extid' => '8350DFEBB5029E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_HEATING' },
    { 'idx' => 2261 , 'extid' => '831A4733360699' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_HEATING_2' },
    { 'idx' => 2265 , 'extid' => '83E6D0E31F0180' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm2' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_HZ_DHW' },
    { 'idx' => 2269 , 'extid' => '836333F7F40181' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm2' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_HZ_HEATING' },
    { 'idx' => 2273 , 'extid' => '8377DED05706A5' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_POOL' },
    { 'idx' => 2277 , 'extid' => '83C7046C7D06A6' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_POOL_2' },
    { 'idx' => 2281 , 'extid' => '409AFF32BE05BB' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_RESET' },
    { 'idx' => 2282 , 'extid' => '831852F1E30257' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_START_DHW' },
    { 'idx' => 2286 , 'extid' => '830BC478130697' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_DHW_2' },
    { 'idx' => 2290 , 'extid' => '83E3910C270256' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_COMPRESSOR_START_HEATING' },
    { 'idx' => 2294 , 'extid' => '83675E1F3B0695' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_HEATING_2' },
    { 'idx' => 2298 , 'extid' => '83CC5C4D1106A7' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_POOL' },
    { 'idx' => 2302 , 'extid' => '83EF99D08506A8' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_COMPRESSOR_START_POOL_2' },
    { 'idx' => 2306 , 'extid' => '83FAB432F80311' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTACTOR_1' },
    { 'idx' => 2310 , 'extid' => '8363BD63420312' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTACTOR_2' },
    { 'idx' => 2314 , 'extid' => '406512BBC205BC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTACTOR_RESET' },
    { 'idx' => 2315 , 'extid' => '83AB5B0DA5030E' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTROL' },
    { 'idx' => 2319 , 'extid' => '405591EFAF07C9' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_CONTROL_RESET' },
    { 'idx' => 2320 , 'extid' => '8302AE12AC0034' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 1 , 'text' => 'STATS_ELECTR_ADD_DHW' },
    { 'idx' => 2324 , 'extid' => '83CE297D7E0033' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 1 , 'text' => 'STATS_ELECTR_ADD_HEATING' },
    { 'idx' => 2328 , 'extid' => '832A25EDF306A9' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 0 , 'text' => 'STATS_ELECTR_ADD_POOL' },
    { 'idx' => 2332 , 'extid' => '404B19AE7205B9' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ELECTR_ADD_RESET' },
    { 'idx' => 2333 , 'extid' => '80F63E80420B2A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ENERGY_HIDE_MENU' },
    { 'idx' => 2334 , 'extid' => '935B8C70A60A6A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 1 , 'text' => 'STATS_ENERGY_OUTPUT' },
    { 'idx' => 2338 , 'extid' => '935F68951C0A6B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 1 , 'text' => 'STATS_ENERGY_OUTPUT_DHW' },
    { 'idx' => 2342 , 'extid' => '93BF5B63600A69' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 1 , 'text' => 'STATS_ENERGY_OUTPUT_HEATING' },
    { 'idx' => 2346 , 'extid' => '93E11998F80A6F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw2' , 'read' => 0 , 'text' => 'STATS_ENERGY_OUTPUT_POOL' },
    { 'idx' => 2350 , 'extid' => '8347EABD6A02A0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_OP_DHW' },
    { 'idx' => 2354 , 'extid' => '83DD88E9E7029F' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'STATS_OP_HEATING' },
    { 'idx' => 2358 , 'extid' => '4090D0258705BA' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_OP_RESET' },
    { 'idx' => 2359 , 'extid' => '40ACAF056B0224' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_RESET' },
    { 'idx' => 2360 , 'extid' => '81DCC8D51E0178' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_AVERAGE_HZ_DHW' },
    { 'idx' => 2361 , 'extid' => '81BF7E48580179' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_AVERAGE_HZ_HEATING' },
    { 'idx' => 2362 , 'extid' => '838B1C7E4002A2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_DHW' },
    { 'idx' => 2366 , 'extid' => '83F3E99AC6069C' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_DHW_2' },
    { 'idx' => 2370 , 'extid' => '8351DA460402A1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HEATING' },
    { 'idx' => 2374 , 'extid' => '834FFE729F069B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm1' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HEATING_2' },
    { 'idx' => 2378 , 'extid' => '83380C545E0183' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm2' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HZ_DHW' },
    { 'idx' => 2382 , 'extid' => '83CC6C55F90182' , 'max' =>        0 , 'min' =>        0 , 'format' => 'hm2' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HZ_HEATING' },
    { 'idx' => 2386 , 'extid' => '8379ACDC8506AA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_HZ_POOL' },
    { 'idx' => 2390 , 'extid' => '838310F1CC06AE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_POOL' },
    { 'idx' => 2394 , 'extid' => '8319D8DB3C06AF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_POOL_2' },
    { 'idx' => 2398 , 'extid' => '40FDD6B6530214' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_RESET' },
    { 'idx' => 2399 , 'extid' => '834DEBB04A0259' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_DHW' },
    { 'idx' => 2403 , 'extid' => '8375DA5B0C0698' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_DHW_2' },
    { 'idx' => 2407 , 'extid' => '838CAC0DD50258' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_HEATING' },
    { 'idx' => 2411 , 'extid' => '8336D3C3AF0696' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_HEATING_2' },
    { 'idx' => 2415 , 'extid' => '836303EF1C06AB' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_POOL' },
    { 'idx' => 2419 , 'extid' => '8362EFC35306AC' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_POOL_2' },
    { 'idx' => 2423 , 'extid' => '407BE577990218' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_COMPRESSOR_START_RESET' },
    { 'idx' => 2424 , 'extid' => '83C820ADEC05BF' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_CONTACTOR_1' },
    { 'idx' => 2428 , 'extid' => '835129FC5605C0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_CONTACTOR_2' },
    { 'idx' => 2432 , 'extid' => '4091DC9A5905BD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_CONTACTOR_RESET' },
    { 'idx' => 2433 , 'extid' => '83183AD8BA0036' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_DHW' },
    { 'idx' => 2437 , 'extid' => '83CF2CD0CF0035' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_HEATING' },
    { 'idx' => 2441 , 'extid' => '83DEEBCC6806AD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'pw3' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_POOL' },
    { 'idx' => 2445 , 'extid' => '402C302A9F0037' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_ELECTR_ADD_RESET' },
    { 'idx' => 2446 , 'extid' => '8320D4D38602A4' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_OP_DHW' },
    { 'idx' => 2450 , 'extid' => '83917B1ECB02A3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_OP_HEATING' },
    { 'idx' => 2454 , 'extid' => '40C811B206021D' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_OP_RESET' },
    { 'idx' => 2455 , 'extid' => '404F8B25F00223' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'STATS_ST_RESET' },
    { 'idx' => 2456 , 'extid' => 'C0D802DC890660' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'SUMMARY_ALARM_MODE' },
    { 'idx' => 2457 , 'extid' => '033DC6687E0A67' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TEMP' },
    { 'idx' => 2461 , 'extid' => '016A5399A300F0' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_DRIFTTILLSTAND' },
    { 'idx' => 2462 , 'extid' => 'E182EE781F00F2' , 'max' =>      180 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_RAMP_TID' },
    { 'idx' => 2463 , 'extid' => '0A68B7289B00F3' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_UTSIGNAL_UT' },
    { 'idx' => 2465 , 'extid' => '81798B64B6027B' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'UI_BRAND' },
    { 'idx' => 2466 , 'extid' => '4021FE28EF0759' , 'max' => 16777216 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'USER_CONFIRMATION' },
    { 'idx' => 2467 , 'extid' => '0150FBFC2B075A' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'USER_CONFIRMATION_OBJECT' },
    { 'idx' => 2468 , 'extid' => 'E959EE228700FA' , 'max' =>      200 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'VS_DIREKTSTART_GRANS' },
    { 'idx' => 2469 , 'extid' => 'E92746DA7B00FB' , 'max' =>      200 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'VS_DIREKTSTOPP_GRANS' },
    { 'idx' => 2470 , 'extid' => '0090432FBD0187' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_COMPRESSOR_REQUEST' },
    { 'idx' => 2471 , 'extid' => '004E977F0B0677' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_COMPRESSOR_REQUEST_2' },
    { 'idx' => 2472 , 'extid' => '01A9D5A48A0253' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_REQUEST' },
    { 'idx' => 2473 , 'extid' => 'EE1597E1AD010E' , 'max' =>      650 , 'min' =>      500 , 'format' => 'tem' , 'read' => 1 , 'text' => 'XDHW_STOP_TEMP' },
    { 'idx' => 2475 , 'extid' => 'E1263DCA71010F' , 'max' =>       48 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_TIME' },
    { 'idx' => 2476 , 'extid' => 'E17B4289E402CD' , 'max' =>        8 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_DAY' },
    { 'idx' => 2477 , 'extid' => 'C9939E5AB602BD' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_DURATION_TIME' },
    { 'idx' => 2478 , 'extid' => '00BBD71E5202BE' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_FAILED' },
    { 'idx' => 2479 , 'extid' => '80C54B781C0CA2' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_HAS_FINISHED' },
    { 'idx' => 2480 , 'extid' => 'E11C86660302BB' , 'max' =>       23 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_HOUR' },
    { 'idx' => 2481 , 'extid' => 'E922E7AC5902BC' , 'max' =>       50 , 'min' =>       10 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_MAX_TIME' },
    { 'idx' => 2482 , 'extid' => '004BD827AD02BA' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_REQUEST' },
    { 'idx' => 2483 , 'extid' => '813A7FAA280CA1' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_SAVED_DAY' },
    { 'idx' => 2484 , 'extid' => 'EEBBE3635F033A' , 'max' =>      700 , 'min' =>      480 , 'format' => 'tem' , 'read' => 1 , 'text' => 'XDHW_WEEKPROGRAM_STOP_TEMP' },
    { 'idx' => 2486 , 'extid' => 'E137C21E8D0343' , 'max' =>        4 , 'min' =>        1 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_WEEK' },
    { 'idx' => 2487 , 'extid' => '03A8D5BC550000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_WEEKPROGRAM_WARM_KEEPING_TIMER' },
    { 'idx' => 2488 , 'extid' => '030C2923470000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'VV_MAX_TIMER' },
    { 'idx' => 2489 , 'extid' => '037043A3350000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'XDHW_TIMER' },
    { 'idx' => 2490 , 'extid' => '03DF2E585D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'VV_RAD_TIMER' },
    { 'idx' => 2491 , 'extid' => '039F4458E90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RAD_MAX_TIMER' },
    { 'idx' => 2492 , 'extid' => '03D904A13A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'RAD_BEHOV_BLOCKERING_TIMER' },
    { 'idx' => 2493 , 'extid' => '03F977D30A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEGREE_MINUTE_SAMPLE_TIMER' },
    { 'idx' => 2494 , 'extid' => '030646EB560000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_START_DELAY_TIMER' },
    { 'idx' => 2495 , 'extid' => '03571B7C340000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'FREEZEGUARD_DELAY_TIMER' },
    { 'idx' => 2496 , 'extid' => '03D5E7D7960000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_RAMP_TIMER' },
    { 'idx' => 2497 , 'extid' => '0343C2F8410000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_STARTUP_TIMER' },
    { 'idx' => 2498 , 'extid' => '03B6D656E60000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_TIMER' },
    { 'idx' => 2499 , 'extid' => '0387E23C230000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_DELAY_TIMER' },
    { 'idx' => 2500 , 'extid' => '03A36256D30000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'EXERCISE_TIMER' },
    { 'idx' => 2501 , 'extid' => '03CB658F620000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_TEMP_LIMIT_TIMER' },
    { 'idx' => 2502 , 'extid' => '035B7EC57A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G1_OPTIMIZED_TIMER' },
    { 'idx' => 2503 , 'extid' => '03AE8860720000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_TEMP_BLOCK_TIMER' },
    { 'idx' => 2504 , 'extid' => '03E496D6400000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PUMP_G2_TEMP_BLOCK_TIMER_2' },
    { 'idx' => 2505 , 'extid' => '036B1ADE3B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_SEASON_STOP_DELAY_TIMER' },
    { 'idx' => 2506 , 'extid' => '03D5C876FB0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ALARM_MODE_DELAY_TIMER' },
    { 'idx' => 2507 , 'extid' => '03693E03EE0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LARMSUMMER_DELAY_TIMER' },
    { 'idx' => 2508 , 'extid' => '038A0048B20000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LARMSUMMER_INTERVAL_TIMER' },
    { 'idx' => 2509 , 'extid' => '03AF0414140000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREENSAVER_TIMER' },
    { 'idx' => 2510 , 'extid' => '03DF5074270000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'QUICKMENU_TIMER' },
    { 'idx' => 2511 , 'extid' => '03DBDCE0BD0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COOLING_FAN_STOP_DELAY_TIMER' },
    { 'idx' => 2512 , 'extid' => '039E84DA850000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TILLSKOTT_START_TIMER' },
    { 'idx' => 2513 , 'extid' => '0334A501230000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_LARM_DELAY_TIMER' },
    { 'idx' => 2514 , 'extid' => '03EB7658B80000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_2_LARM_DELAY_TIMER' },
    { 'idx' => 2515 , 'extid' => '03B02C57B20000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIMER' },
    { 'idx' => 2516 , 'extid' => '0397D1BAA50000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MAX_TIMER_2' },
    { 'idx' => 2517 , 'extid' => '039655D95C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MIN_BREAK_TIMER' },
    { 'idx' => 2518 , 'extid' => '035D2CEC990000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_MIN_BREAK_TIMER_2' },
    { 'idx' => 2519 , 'extid' => '039BB8F62B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_TIMER' },
    { 'idx' => 2520 , 'extid' => '039683331C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_BLOCK_TIMER_2' },
    { 'idx' => 2521 , 'extid' => '033677609B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIMER' },
    { 'idx' => 2522 , 'extid' => '036B2A061A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_FAN_TIMER_2' },
    { 'idx' => 2523 , 'extid' => '03649B4C1B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIMER' },
    { 'idx' => 2524 , 'extid' => '036271A05E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DEFROST_DELTA_TIMER_2' },
    { 'idx' => 2525 , 'extid' => '03BE2D7BE40000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TIMER' },
    { 'idx' => 2526 , 'extid' => '0349E822950000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HEATING_CABLE_TIMER_2' },
    { 'idx' => 2527 , 'extid' => '0337E6727C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_BLOCK_HIGH_T2_TIMER' },
    { 'idx' => 2528 , 'extid' => '03AFA2968B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'NEUTRALZONE_LIMITATION_TIMER' },
    { 'idx' => 2529 , 'extid' => '0395A0A18D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_EXTERNAL_HEAT_VALVE_DELAY_TIMER' },
    { 'idx' => 2530 , 'extid' => '038BEED8DC0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_DELAY_TIMER' },
    { 'idx' => 2531 , 'extid' => '03A8432FE00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_2_DELAY_TIMER' },
    { 'idx' => 2532 , 'extid' => '0335BCDBBA0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_DELAY_AFTER_SWITCH_TIMER' },
    { 'idx' => 2533 , 'extid' => '0306E9C7690000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T8_T9_2_DELAY_AFTER_SWITCH_TIMER' },
    { 'idx' => 2534 , 'extid' => '03FB40F9E30000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_DELAY_TIMER' },
    { 'idx' => 2535 , 'extid' => '03BCF4652C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_2_DELAY_TIMER' },
    { 'idx' => 2536 , 'extid' => '03C36360E10000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_DELAY_AFTER_SWITCH_TIMER' },
    { 'idx' => 2537 , 'extid' => '030315DF2D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'T10_T11_2_DELAY_AFTER_SWITCH_TIMER' },
    { 'idx' => 2538 , 'extid' => '0334D523DC0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_LIMITATION_DEFROST_DELAY_TIMER' },
    { 'idx' => 2539 , 'extid' => '035F6232A00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_ADDITIONALHEAT_DELAY_TIMER' },
    { 'idx' => 2540 , 'extid' => '03BAFFC53E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_HEATING_START_DELAY_AT_CASCADE' },
    { 'idx' => 2541 , 'extid' => '0326475C6E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_HEATING_STOP_DELAY_AT_CASCADE' },
    { 'idx' => 2542 , 'extid' => '030DC217150000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'SCREED_DRYING_TIMER' },
    { 'idx' => 2543 , 'extid' => '033E0114990000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_TIMER_2' },
    { 'idx' => 2544 , 'extid' => '0325EB8EE00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'COMPRESSOR_START_DELAY_TIMER_2' },
    { 'idx' => 2545 , 'extid' => '0338E9DA6F0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_AFTER_VV_TIMER' },
    { 'idx' => 2546 , 'extid' => '0390716E0C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_AFTER_HG_TIMER' },
    { 'idx' => 2547 , 'extid' => '03987556E00000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_2_BLOCK_AFTER_VV_TIMER' },
    { 'idx' => 2548 , 'extid' => '0330EDE2830000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_2_BLOCK_AFTER_HG_TIMER' },
    { 'idx' => 2549 , 'extid' => '03CA2A2BBF0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_BLOCK_OUTDOOR_ACKNOWLEDGE_TIMER' },
    { 'idx' => 2550 , 'extid' => '0312F33CA10000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ENVELOPE_2_BLOCK_AFTER_GT2_LOW_TIMER' },
    { 'idx' => 2551 , 'extid' => '0365D5BF960000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'PARTY_MODE_TIMER' },
    { 'idx' => 2552 , 'extid' => '03D54804B70000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'D_VALVE_STARTUP_TIMER' },
    { 'idx' => 2553 , 'extid' => '03116FC3180000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'POOL_START_DELAY_TIMER' },
    { 'idx' => 2554 , 'extid' => '03B6B0774B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'ADDITIONAL_SYNCH_VALVE_TIMER' },
    { 'idx' => 2555 , 'extid' => '033A5C6DEE0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'DHW_PROTECTIVE_ANODE_ALERT_DELAY_TIMER' },
    { 'idx' => 2556 , 'extid' => '033F942D3B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_COMPRESSOR_START' },
    { 'idx' => 2557 , 'extid' => '030D1952910000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_4_WAY_VALVE_SWITCH' },
    { 'idx' => 2558 , 'extid' => '03BE9F792A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_COMPRESSOR_2_START' },
    { 'idx' => 2559 , 'extid' => '03BF774E1E0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_DELAY_4_WAY_VALVE_2_SWITCH' },
    { 'idx' => 2560 , 'extid' => '038D0B511C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_PIPE_DELAY' },
    { 'idx' => 2561 , 'extid' => '03C32CCD200000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_PIPE_EXERCISE' },
    { 'idx' => 2562 , 'extid' => '03ACEF37B90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_HIGH' },
    { 'idx' => 2563 , 'extid' => '031040967B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_LOW' },
    { 'idx' => 2564 , 'extid' => '038F5858740000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIMER' },
    { 'idx' => 2565 , 'extid' => '03FC507FBB0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIMER' },
    { 'idx' => 2566 , 'extid' => '039ACEE8880000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'LP_STOP_MAX_TIMER_2' },
    { 'idx' => 2567 , 'extid' => '0373A6E56A0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'HP_STOP_MAX_TIMER_2' },
    { 'idx' => 2568 , 'extid' => '03E47EE9760000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_G2_AFTER_XDHW' },
    { 'idx' => 2569 , 'extid' => '03327B78640000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_DELAY_BEFORE_SHORT_CIRCUIT' },
    { 'idx' => 2570 , 'extid' => '03CD930CA60000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SOLAR_T1_CONTROLLED_RISE' },
    { 'idx' => 2571 , 'extid' => '035396F6D10000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_G2_ADJUST_TIMER' },
    { 'idx' => 2572 , 'extid' => '03BEA3936D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E21_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    { 'idx' => 2573 , 'extid' => '03E5B422780000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E22_COMPRESSOR_TEMPORARY_STOP_DELAY' },
    { 'idx' => 2574 , 'extid' => '03688E73320000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_ACCESS_LEVEL' },
    { 'idx' => 2575 , 'extid' => '0374902F9F0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E21_G2_TEMPORARY_STOP' },
    { 'idx' => 2576 , 'extid' => '03D7C6A9360000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E22_G2_TEMPORARY_STOP' },
    { 'idx' => 2577 , 'extid' => '03DF94AC2C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_COMMUNICATION_BAD_CANBUS_REBOOT_DELAY' },
    { 'idx' => 2578 , 'extid' => '039CA89DB30000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E21_G2_MEAN_VALUE_SAMPLE_TIME' },
    { 'idx' => 2579 , 'extid' => '032F3CB0700000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E22_G2_MEAN_VALUE_SAMPLE_TIME' },
    { 'idx' => 2580 , 'extid' => '03CB4C454D0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E21_G2_INIT' },
    { 'idx' => 2581 , 'extid' => '03F2C179880000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_CIRCULATION_E22_G2_INIT' },
    { 'idx' => 2582 , 'extid' => '037AFAC7930000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_FREEZEGUARD' },
    { 'idx' => 2583 , 'extid' => '039C488E6B0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_CALIBRATE_PID' },
    { 'idx' => 2584 , 'extid' => '036B3D4C400000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_PID_SV41' },
    { 'idx' => 2585 , 'extid' => '03C3827F2F0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_M_VALVE_DEFROST' },
    { 'idx' => 2586 , 'extid' => '0330D709630000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_INIT_SV41' },
    { 'idx' => 2587 , 'extid' => '037A9EF9C90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E21_M_VALVE_DEFROST' },
    { 'idx' => 2588 , 'extid' => '0340EE87130000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_M_VALVE_LIMITATION' },
    { 'idx' => 2589 , 'extid' => '032CD2DBA80000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_M_VALVE_PULS_PAUS' },
    { 'idx' => 2590 , 'extid' => '036A78F2900000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_STARTUP_DELAY' },
    { 'idx' => 2591 , 'extid' => '03F5E34A180000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_HEATING_SEASON_STOP_DELAY' },
    { 'idx' => 2592 , 'extid' => '03F8766ABC0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_HEATING_SEASON_START_DELAY' },
    { 'idx' => 2593 , 'extid' => '035375085C0000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_ATTENUATION' },
    { 'idx' => 2594 , 'extid' => '031077F8550000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_MV_E12_DEFROST' },
    { 'idx' => 2595 , 'extid' => '03EB5A5D180000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS_2' },
    { 'idx' => 2596 , 'extid' => '03D093BCC60000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DEFROST_MAX_RUNNING_TIME_BETWEEN_DEFROSTS' },
    { 'idx' => 2597 , 'extid' => '03C894A2500000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E21_T3_START_TEMP_ADJ' },
    { 'idx' => 2598 , 'extid' => '036BC224F90000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_DHW_E22_T3_START_TEMP_ADJ' },
    { 'idx' => 2599 , 'extid' => '0327DE5EF70000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_SYSTEM_INIT' },
    { 'idx' => 2600 , 'extid' => '03B11E70550000' , 'max' =>        0 , 'min' =>        0 , 'format' => 'int' , 'read' => 0 , 'text' => 'TIMER_COMPRESSOR_START_DELAY_AT_CASCADE' }
);

my %KM273_format = (
    'int' => { factor => 1      , unit => ''    },
    't15' => { factor => 1      , unit => ''    },
    'hm1' => { factor => 1      , unit => 's'   },
    'hm2' => { factor => 10     , unit => 's'   },
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
my @KM273_readingsRTRAll = ();
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
  @KM273_readingsRTRAll = ();
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
          if (!$KM273_ReadElementListStatus{KM200active} && ($KM273_ReadElementListStatus{readCounter} > 0) && ($KM273_ReadElementListStatus{readIndex} >= $KM273_ReadElementListStatus{readCounter}))
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
    
    my @AddToReadingsKeys = split(' ',($attr{$name}{AddToReadings})) if (defined($attr{$name}{AddToReadings}));
    push @AddToReadingsKeys, split(' ',($attr{$name}{AddToGetSet})) if (defined($attr{$name}{AddToGetSet}));
    my $AddToReadingsRegex = join('|',@AddToReadingsKeys);

    %KM273_elements = ();
    foreach my $elementRef (@KM273_elements_default)
    {
        my $text = $elementRef->{text};
        my $read = $elementRef->{read};
        my $elem1 = $KM273_ReadElementListElements{$text};
        if ( $text =~ /$AddToReadingsRegex/ )
        {
          $read = 1;
          Log3 $name, 3, "$name: KM273_UpdateElements AddToReadings $text";
        }
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
          my $format = $elementRef->{format};
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
    foreach my $elementRef (@KM273_elements_default)
    {
      my $text = $elementRef->{text};
      my $idx = $elementRef->{idx};
      my $extid = $elementRef->{extid};
      my $max = $elementRef->{max};
      my $min = $elementRef->{min};
      $KM273_ReadElementListElements{$text} = {'idx' => $idx, 'extid' => $extid, 'max' => $max, 'min' => $min };
    }
    $KM273_ReadElementListStatus{done} = 1;
}

sub KM273_StoreElementList($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: KM273_StoreElementList";
    
    return "No statefile specified" if(!$attr{global}{statefile});
    my $elementListFile=$attr{global}{statefile}; 
    $elementListFile=~ s/fhem.save/KM273ElementList.json/g;  #saving to statefile path
    
    eval {
    require utf8;
    require Encode;
    require JSON;
    };
    if ($@) {
      Log3 $name, 1, "$name: KM273_StoreElementList: json/utf8 library missing: $@";
      return undef;
    }
    
    my $fh;
    if (!open($fh, '>', $elementListFile)) {
      Log3 $name, 3, "$name: KM273_StoreElementList: Cannot open $elementListFile: $!";
      return "Cannot open $elementListFile: $!";
    }

    print $fh "{\n";
    my $first = 1;
    foreach (sort keys(%KM273_elements))
    {
      print $fh ",\n" if (!$first);
      print $fh '"' . $_ .'":' . JSON->new->utf8->encode($KM273_elements{$_});
      $first = 0;
    }
    print $fh "\n}";
    
    close $fh;
    
    Log3 $name, 3, "$name: KM273_StoreElementList: json file $elementListFile has been stored";
  
    return "json file $elementListFile has been stored";
}

sub KM273_LoadElementList($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: KM273_LoadElementList";

    return "No statefile specified" if(!$attr{global}{statefile});
    my $elementListFile=$attr{global}{statefile}; 
    $elementListFile=~ s/fhem.save/KM273ElementList.json/g;  #saving to statefile path

    eval {
    require utf8;
    require Encode;
    require JSON;
    };
    if ($@) {
      Log3 $name, 1, "$name: KM273_LoadElementList: json/utf8 library missing: $@";
      return undef;
    }

    my $fh;
    if(!open($fh, '<', $elementListFile)) {
      Log3 $name, 3, "$name: KM273_LoadElementList: Cannot open $elementListFile: $!";
      return "Cannot open $elementListFile: $!";
    }

    my $content = '';
    {
        local $/;
        $content = <$fh>;
    }
    close $fh;

    eval { %KM273_elements = %{ JSON->new->utf8->decode($content) }; };
    if ($@) {
      Log3 $name, 1, "$name: KM273_LoadElementList: json file $elementListFile is faulty: $@!";
      return undef;
    }

    Log3 $name, 3, "$name: KM273_LoadElementList: json file $elementListFile has been loaded";

    $KM273_ReadElementListStatus{done} = 1;
    return undef;
}

sub KM273_CreatePollingList($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: KM273_CreatePollingList";

    @KM273_readingsRTR = ();
    @KM273_readingsRTRAll = ();
    foreach my $element (sort keys %KM273_elements)
    {
        push @KM273_readingsRTRAll, $KM273_elements{$element}{rtr} if defined $KM273_elements{$element}{rtr};
        if (defined $KM273_elements{$element}{read})
        {
          push @KM273_readingsRTR, $KM273_elements{$element}{rtr} if $KM273_elements{$element}{read} == 1;
          push @KM273_readingsRTR, $KM273_elements{$element}{rtr} if ($KM273_elements{$element}{read} == 2) && defined($attr{$name}{HeatCircuit2Active}) && ($attr{$name}{HeatCircuit2Active} == 1);
        }
    }
    foreach my $val (@KM273_readingsRTR)
    {
        Log3 $name, 3, "$name: KM273_CreatePollingList rtr $val";
    }
    $hash->{pollingIndex} = 0;

    my @getElements = @KM273_getsBase;
    push @getElements, @KM273_getsAddHC2 if (defined($attr{$name}{HeatCircuit2Active}) && ($attr{$name}{HeatCircuit2Active} == 1));
    push @getElements, split(' ',($attr{$name}{AddToGetSet})) if (defined($attr{$name}{AddToGetSet}));
    %KM273_gets = map {$_ => ''} @getElements;

    %KM273_writingsTXD = ();
    foreach my $element (keys %KM273_elements)
    {
        $KM273_writingsTXD{$KM273_elements{$element}{text}} = $KM273_elements{$element} if (defined($KM273_gets{$KM273_elements{$element}{text}}));
    }
    foreach my $element (keys %KM273_gets)
    {
        delete $KM273_gets{$element} if !defined $KM273_writingsTXD{$element};
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
                          "ListenOnly " .
                          "LoadElementList " .
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
    Log3 $name, 3, "$name: KM273_Define";

    $hash->{VERSION} = "0017";
    
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
      return undef;
    }
    
    $hash->{DeviceName} = $dev;
    InternalTimer(gettimeofday()+10, "KM273_InitInterface", $hash, 0);

    return undef;
}

sub KM273_InitInterface($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: KM273_InitInterface";
    
    return undef if (!defined($hash->{DeviceName})) || ($hash->{DeviceName} eq 'none');

    RemoveInternalTimer($hash);
    
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
	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$|AddToGetSet|AddToReadings|HeatCircuit2Active/, @{$events}))
	{
    if (defined($attr{$ownName}{LoadElementList}) && ($attr{$ownName}{LoadElementList} == 1))
    {
        RemoveInternalTimer($own_hash);
        KM273_LoadElementList($own_hash);
        KM273_CreatePollingList($own_hash);
        KM273_InitInterface($own_hash);
        InternalTimer(gettimeofday()+10, "KM273_GetReadings", $own_hash, 0);
        return undef;
    }
    if (defined($attr{$ownName}{ListenOnly}) && ($attr{$ownName}{ListenOnly} == 1))
    {
      KM273_LoadElementList($own_hash);
      return undef;
    }
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
    
    if ($opt eq 'ReadAll')
    {
      $hash->{readAllIndex} = 0;
      return undef;
    }

    if ($opt eq 'StoreElementList')
    {
      return KM273_StoreElementList($hash);
    }

    if ($opt eq 'RAW')
    {
      my $cmd = substr($value,0,1);
      my $len = length $value;
      if ($cmd eq 'R')
      {
        $value = uc $value;
        return "RAW format read Riiiiiiii0" if (($len != 10) || (substr($value,9,1) ne '0') || (substr($value,1) !~ /[0-9A-F]+/));
      }
      elsif ($cmd eq 'T')
      {
        $value = uc $value;
        my $len = hex substr($value,9,1);
        return "RAW format write TiiiiiiiiLvdd..." if ((length $value != 10+2*$len) || ($len<1) || ($len>8) || (substr($value,1) !~ /[0-9A-F]+/));
      }
      elsif (($len != 1) || ($cmd !~ /[VvNF]/))
      {
        return "RAW format read Riiiiiiii0, write TiiiiiiiiLvv...";
      }
      CAN_Write($hash,$value);
      return undef;
    }

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
                my $limit = $max * $factor;
                return "value $value exceed the maximum limit of $limit";
            }
            if ($value1 < $min)
            {
                my $limit = $min * $factor;
                return "value $value exceed the minimum limit of $limit";
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

    if (!$KM273_ReadElementListStatus{done} && !(defined($attr{$name}{ListenOnly}) && ($attr{$name}{ListenOnly} == 1)))
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
    
    my $recvCnt = 0;
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
            $value1 = $value1 - 2147483648 if $len1 == 4 && $value1 > 2147483647;
            my $value = $value1;
            my $readingName1 = $canId;
            $readingName1 = $KM273_elements{$canId}{text} if (exists $KM273_elements{$canId});
            if (exists $KM273_elements{$canId})
            {
                $recvCnt++;
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
                elsif (($format eq "hm1") || ($format eq "hm2"))
                {
                    my $s = $value1 * $KM273_format{$format}{factor};
                    my $m = $s / 60; $s = $s % 60;
                    my $h = $m /  60; $m %= 60;
                    $value = sprintf "%d:%02d", $h, $m;
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

            if (defined($hash->{readAllIndex}) && ($hash->{readAllIndex} < @KM273_readingsRTRAll))
            {
                if (defined($KM273_elements{$canId}))
                {
                    my $valueOld = $KM273_elements{$canId}{value};
                    if (defined($valueOld))
                    {
                        if ($valueOld != $value1)
                        {
                            Log3 $name, 1, "$name ReadAll $readingName1 valueOld=$valueOld valueNew=$value1";
                            $KM273_elements{$canId}{value} = $value1;
                        }
                    }
                    else
                    {
                      Log3 $name, 1, "$name ReadAll $readingName1 value=$value1";
                      $KM273_elements{$canId}{value} = $value1;
                    }
                }
            }
            elsif (exists $KM273_history{$canId})
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

    KM273_GetNextValue($hash) if ($recvCnt > 0);

    return undef;
}

#####################################
sub KM273_GetNextValue($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 4, "$name: KM273_GetNextValue";
    
    if (defined($hash->{readAllIndex}))
    {
      my $index = $hash->{readAllIndex};
      if ($index < @KM273_readingsRTRAll)
      {
          my $canId = $KM273_readingsRTRAll[$index];
          CAN_Write($hash, "R".$canId."0");
          Log3 $name, 5, "$name: KM273_GetNextValue $index Id $canId";
          $hash->{readAllIndex}++;
          return undef;
      }
    }

    return undef if defined($attr{$name}{DoNotPoll}) && ($attr{$name}{DoNotPoll} == 1);
    return undef if defined($attr{$name}{ListenOnly}) && ($attr{$name}{ListenOnly} == 1);

    my $index = $hash->{pollingIndex};
    if ($index < @KM273_readingsRTR)
    {
        my $canId = $KM273_readingsRTR[$index];
        CAN_Write($hash, "R".$canId."0");
        Log3 $name, 5, "$name: KM273_GetNextValue $index Id $canId";
        $hash->{pollingIndex}++;
        return undef;
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
    Log3 $name, 4, "$name: CAN_Write $data";

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
                    my $data = hex substr($data,0,2*$len);
                    my $log = (hex $id == 0x09FDBFE0) ? 5 : 4;
                    Log3 $name, $log, "$name: CAN_Read recv $dir $id $len $data";
                    return ($dir,$id,$len,$data);
                }
                elsif ($dir eq 'R')
                {
                    $len = hex $len;
                    $data = '';
                    Log3 $name, 4, "$name: CAN_Read recv $dir $id $len";
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
                    my $data = hex substr($data,0,2*$len);
                    Log3 $name, 4, "$name: CAN_Read recv $dir $id $len $data";
                    return ($dir,$id,$len,$data) ;
                }
                elsif ($dir eq 'r')
                {
                    $len = hex $len;
                    $data = '';
                    Log3 $name, 4, "$name: CAN_Read recv $dir $id $len";
                    return ($dir,$id,$len,$data);
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
            Log3 $name, 4, "$name: CAN_Read recv Z";
        }
        elsif ($dir eq 'V')
        {
            $hash->{VERSION_USBTinHW} = (hex substr($recv,1,2)) . '.' . (hex substr($recv,3,2));
            Log3 $name, 4, "$name: CAN_Read recv Hardware Version $recv";
        }
        elsif ($dir eq 'v')
        {
            $hash->{VERSION_USBTinSW} = (hex substr($recv,1,2)) . '.' . (hex substr($recv,3,2));
            Log3 $name, 4, "$name: CAN_Read recv Software Version $recv";
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
    DevIo_SimpleWrite($hash, "C\rC\rV\rV\rv\rS4\rO\r", 0);
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
                  preset for hot water temperature</li>
              <li><i>DHW_TIMEPROGRAM</i><br>
                  select: '0' or 'Always_On', '1' or 'Program_1', '2' or 'Program_2'</li>
              <li><i>DHW_PROGRAM_MODE</i><br>
                  select: '0' or 'Automatic', '1' or 'Always_On', '2' or 'Always_Off'</li>
              <li><i>DHW_PROGRAM_1_1MON .. ROOM_PROGRAM_1_7SUN</i><br>
                  value: 06:00 on 21:00 off </li>
              <li><i>DHW_PROGRAM_2_1MON .. ROOM_PROGRAM_2_7SUN</i><br>
                  value: 06:00 on 21:00 off </li>
              <li><i>PUMP_DHW_PROGRAM1_START_TIME .. PUMP_DHW_PROGRAM4_STOP_TIME</i><br>
                  dayly program for switching on and off the hot water circulation pump<br>
                  you can set 4 time ranges where the pump should be switched on
                  value: xx:xx</li>
              <li><i>HEATING_SEASON_MODE</i><br>
                  select: '0' or 'Automatic', '1' or 'Always_On', '2' or 'Always_Off'</li>
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
        <br>
        Special Options:
        <ul>
              <li><i>ReadAll</i><br>
                  read once all 2000..2600 paramater of the heatpump<br>
                  the values will be logged into standard fhem log<br>
                  on second read, only the changed values are logged
              </li>    
              <li><i>RAW</i><br>
                  Send CAN RAW message in USBTin/SLCAN format: read Riiiiiiii0, write TiiiiiiiiLvv...
              </li>
              <li><i>StoreElementList</i><br>
                  The parameter table read from heatpump is stored to file ./log/KM237ElementList.json
              </li>
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
                When you set DoNotPoll to "1", the module is only listening to the telegrams on CAN bus. The Parameter table is still read from heatpump! Default is "0".<br>
            </li>
            <li><i>ListenOnly</i> 0|1<br>
                When you set ListenOnly to "1", the module is only listening to the telegrams on CAN bus. Also the Parameter table isn't read from heatpump. Default is "0".<br>
            </li>
            <li><i>LoadElementList</i> 0|1<br>
                When you set LoadElementList to "1", the module load the Parameter table from file ./log/KM237ElementList.json. The Parameter table isn't read from heatpump, then. Default is "0".<br>
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
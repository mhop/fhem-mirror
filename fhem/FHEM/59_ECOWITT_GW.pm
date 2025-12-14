##############################################
# $Id$
#
# Provides support for the Ecowitt weatherstation LAN/WLAN Gateway
# Gw1000/WH2650/GW2000
#
# based on the original work by sepo83 and LukeSky007, https://forum.fhem.de/index.php?topic=124794.0
# original filename 50_GW1000_TCP.pm
# officially added to FHEM, see https://forum.fhem.de/index.php?topic=124794

package main;

use strict;
use warnings;

use DevIo;
use Time::HiRes qw(gettimeofday time);
use Time::Local;
use List::Util 'sum';
use Data::Dump qw(dump);
use Readonly;

################################################################################################################
# API from https://osswww.ecowitt.net/uploads/20220407/WN1900%20ECOWITT,1100%20WH2680,2650%20telenet%20v1.6.4.pdf
# GW1000,1100 WH2680,2650 telenet v1.6.4.pdf, page 7 - 9
# online API doc: https://doc.ecowitt.net/web/#/apiv3en?page_id=1

my %ECOWITT_cmdMap = (
    CMD_WRITE_SSID               => 0x11,        # ToDo # send SSID and Password to WIFI module
    CMD_BROADCAST                => 0x12,        # ToDo # UDP cast for device echo，answer back data size is 2 Bytes
    CMD_READ_ECOWITT             => 0x1E,        # ToDo # read aw.net setting
    CMD_WRITE_ECOWITT            => 0x1F,        # ToDo # write back awt.net setting
    CMD_READ_WUNDERGROUND        => 0x20,        # ToDo # read Wunderground setting
    CMD_WRITE_WUNDERGROUND       => 0x21,        # ToDo # write back Wunderground setting
    CMD_READ_WOW                 => 0x22,        # ToDo # read WeatherObservationsWebsite setting
    CMD_WRITE_WOW                => 0x23,        # ToDo # write back WeatherObservationsWebsite setting
    CMD_READ_WEATHERCLOUD        => 0x24,        # ToDo # read Weathercloud setting
    CMD_WRITE_WEATHERCLOUD       => 0x25,        # ToDo # write back Weathercloud setting
    CMD_READ_STATION_MAC         => 0x26,        # read MAC address
    CMD_READ_CUSTOMIZED          => 0x2A,        # ToDo # read Customized sever setting
    CMD_WRITE_CUSTOMIZED         => 0x2B,        # ToDo #  write back Customized sever setting
    CMD_WRITE_UPDATE             => 0x43,        # ToDo # firmware upgrade
    CMD_READ_FIRMWARE_VERSION    => 0x50,        # OK   # read current firmware version number
    CMD_READ_USR_PATH            => 0x51,        # ToDo
    CMD_WRITE_USR_PATH           => 0x52,        # ToDo
    CMD_ECOWITT_LIVEDATA         => 0x27,        # OK   # read current data，reply data size is 2bytes. only valid for ECOWITT, WH2650 and wn1900
    CMD_GET_SOILHUMIAD           => 0x28,        # ToDo # read Soilmoisture Sensor calibration parameters
    CMD_SET_SOILHUMIAD           => 0x29,        # ToDo # write back Soilmoisture Sensor calibration parameters
    CMD_GET_MulCH_OFFSET         => 0x2C,        # ToDo # read multi channel sensor offset value
    CMD_SET_MulCH_OFFSET         => 0x2D,        # ToDo # write back multi channel sensor OFFSET value
    CMD_GET_PM25_OFFSET          => 0x2E,        # ToDo # read PM2.5OFFSET calibration data
    CMD_SET_PM25_OFFSET          => 0x2F,        # ToDo # writeback PM2.5OFFSET calibration data
    CMD_READ_SSSS                => 0x30,        # OK   # read system info
    CMD_WRITE_SSSS               => 0x31,        # ToDo # write back system info
    CMD_READ_RAINDATA            => 0x34,        # read rain data
    CMD_WRITE_RAINDATA           => 0x35,        # ToDo # write back rain data
    CMD_READ_GAIN                => 0x36,        # ToDo # read rain gain
    CMD_WRITE_GAIN               => 0x37,        # ToDo # write back rain gain
    CMD_READ_CALIBRATION         => 0x38,        # ToDo # read sensor set offset calibration value
    CMD_WRITE_CALIBRATION        => 0x39,        # ToDo # write back sensor set offset value
    CMD_READ_SENSOR_ID           => 0x3A,        # read Sensors ID
    CMD_WRITE_SENSOR_ID          => 0x3B,        # ToDo # write back Sensors ID
    CMD_READ_SENSOR_ID_NEW       => 0x3C,        # this is reserved for newly added sensor
    CMD_WRITE_REBOOT             => 0x40,        # system restart
    CMD_WRITE_RESET              => 0x41,        # ToDo # reset to default
    CMD_READ_CUSTOMIZED_PATH     => 0x51,        # ToDo
    CMD_WRITE_CUSTOMIZED_PATH    => 0x52,        # ToDo
    CMD_GET_CO2_OFFSET           => 0x53,        # ToDo # CO2 OFFSET
    CMD_SET_CO2_OFFSET           => 0x54,        # ToDo # CO2 OFFSET
    CMD_READ_RSTRAIN_TIME        => 0x57,        # OK   # read rain and piezo rain data and reset setting
    CMD_WRITE_RSTRAIN_TIME       => 0x58,        # ToDo # write rain and piezo rain data and reset setting
);
my %ECOWITT_cmdMap_reversed = reverse %ECOWITT_cmdMap;

# GW1000,1100 WH2680,2650 telenet v1.6.4.pdf, page 7 - 9
my %ECOWITT_Items = (
    0x01 => {name => "Temperature_Indoor",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x02 => {name => "Temperature_Outdoor",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x03 => {name => "Dew_point",                       size => 2, isSigned => 0, factor => 1, unit => "°C"},
    0x04 => {name => "Wind_chill",                      size => 2, isSigned => 0, factor => 1, unit => "°C"},
    0x05 => {name => "Heat_index",                      size => 2, isSigned => 0, factor => 1, unit => "°C"},
    0x06 => {name => "Humidity_Indoor",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x07 => {name => "Humidity_Outdoor",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x08 => {name => "Barometric_Absolutely",           size => 2, isSigned => 0, factor => 0.1, unit => "hpa"},
    0x09 => {name => "Barometric_Relative",             size => 2, isSigned => 0, factor => 0.1, unit => "hpa"},
    0x0A => {name => "Wind_Direction",                  size => 2, isSigned => 0, factor => 1, unit => "°"},
    0x0B => {name => "Wind_Speed ",                     size => 2, isSigned => 0, factor => 0.1, unit => "m/s"},
    0x0C => {name => "Wind_Speed_Gust",                 size => 2, isSigned => 0, factor => 0.1, unit => "m/s"},
    0x0D => {name => "Rain_Event",                      size => 2, isSigned => 0, factor => 1, unit => "mm"},
    0x0E => {name => "Rain_Rate",                       size => 2, isSigned => 0, factor => 1, unit => "mm/h"},
    0x0F => {name => "Rain_Hour ",                      size => 2, isSigned => 0, factor => 1, unit => "mm"},
    0x10 => {name => "Rain_Day",                        size => 2, isSigned => 0, factor => 1, unit => "mm"},
    0x11 => {name => "Rain_Week",                       size => 2, isSigned => 0, factor => 1, unit => "mm"},
    0x12 => {name => "Rain_Month",                      size => 4, isSigned => 0, factor => 1, unit => "mm"},
    0x13 => {name => "Rain_Year",                       size => 4, isSigned => 0, factor => 1, unit => "mm"},
    0x14 => {name => "Rain_Totals",                     size => 4, isSigned => 0, factor => 1, unit => "mm"},
    0x15 => {name => "Light",                           size => 4, isSigned => 0, factor => 1, unit => "lux"},
    0x16 => {name => "UV",                              size => 2, isSigned => 0, factor => 1, unit => "uW/m²"},
    0x17 => {name => "UVI",                             size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x18 => {name => "Date_and_time",                   size => 6, isSigned => 0, factor => 1, unit => "-"},
    0x19 => {name => "Wind_Day_max",                    size => 2, isSigned => 0, factor => 0.1, unit => "m/s"},
    0x1A => {name => "Temperature_CH1",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x1B => {name => "Temperature_CH2",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x1C => {name => "Temperature_CH3",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x1D => {name => "Temperature_CH4",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x1E => {name => "Temperature_CH5",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x1F => {name => "Temperature_CH6",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x20 => {name => "Temperature_CH7",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x21 => {name => "Temperature_CH8",                 size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x22 => {name => "Humidity_CH1",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x23 => {name => "Humidity_CH2",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x24 => {name => "Humidity_CH3",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x25 => {name => "Humidity_CH4",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x26 => {name => "Humidity_CH5",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x27 => {name => "Humidity_CH6",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x28 => {name => "Humidity_CH7",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x29 => {name => "Humidity_CH8",                    size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x2A => {name => "PM2.5_Air_Quality_Sensor",        size => 2, isSigned => 0, factor => 1, unit => "μg/m³"},
    0x2B => {name => "Soil_Temperature_1",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x2C => {name => "Soil_Moisture_1",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x2D => {name => "Soil_Temperature_2",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x2E => {name => "Soil_Moisture_2",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x2F => {name => "Soil_Temperature_3",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x30 => {name => "Soil_Moisture_3",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x31 => {name => "Soil_Temperature_4",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x32 => {name => "Soil_Moisture_4",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x33 => {name => "Soil_Temperature_5",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x34 => {name => "Soil_Moisture_5",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x35 => {name => "Soil_Temperature_6",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x36 => {name => "Soil_Moisture_6",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x37 => {name => "Soil_Temperature_7",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x38 => {name => "Soil_Moisture_7",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x39 => {name => "Soil_Temperature_8",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x3A => {name => "Soil_Moisture_8",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x3B => {name => "Soil_Temperature_9",              size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x3C => {name => "Soil_Moisture_9",                 size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x3D => {name => "Soil_Temperature_10",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x3E => {name => "Soil_Moisture_10",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x3F => {name => "Soil_Temperature_11",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x40 => {name => "Soil_Moisture_11",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x41 => {name => "Soil_Temperature_12",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x42 => {name => "Soil_Moisture_12",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x43 => {name => "Soil_Temperature_13",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x44 => {name => "Soil_Moisture_13",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x45 => {name => "Soil_Temperature_14",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x46 => {name => "Soil_Moisture_14",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x47 => {name => "Soil_Temperature_15",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x48 => {name => "Soil_Moisture_15",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x49 => {name => "Soil_Temperature_16",             size => 2, isSigned => 1, factor => 0.1, unit => "°C"},
    0x4A => {name => "Soil_Moisture_16",                size => 1, isSigned => 0, factor => 1, unit => "%"},
    0x4C => {name => "All_sensor_lowbatt",              size => 16, isSigned => 0, factor => 1, unit => "-"},
    0x4D => {name => "pm25_24HAVG1",                    size => 2, isSigned => 0, factor => 1, unit => "-"},
    0x4E => {name => "pm25_24HAVG2",                    size => 2, isSigned => 0, factor => 1, unit => "-"},
    0x4F => {name => "pm25_24HAVG3",                    size => 2, isSigned => 0, factor => 1, unit => "-"},
    0x50 => {name => "pm25_24HAVG4",                    size => 2, isSigned => 0, factor => 1, unit => "-"},
    0x51 => {name => "PM2.5_Air_Quality_Sensor_2",      size => 2, isSigned => 0, factor => 1, unit => "-"},
    0x52 => {name => "PM2.5_Air_Quality_Sensor_3",      size => 2, isSigned => 0, factor => 1, unit => "-"},
    0x53 => {name => "PM2.5_Air_Quality_Sensor_4",      size => 2, isSigned => 0, factor => 1, unit => "-"},
    0x58 => {name => "Leak_ch1",                        size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x59 => {name => "Leak_ch2",                        size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x5A => {name => "Leak_ch3",                        size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x5B => {name => "Leak_ch4",                        size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x60 => {name => "lightning_distance",              size => 1, isSigned => 0, factor => 1, unit => "km"},
    0x61 => {name => "lightning_happened_time",         size => 4, isSigned => 0, factor => 1, unit => "time"},
    0x62 => {name => "lightning_counter_for_the_day",   size => 4, isSigned => 0, factor => 1, unit => "-"},
    
    0x63 => {name => "TF_USR_Temperature_1",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x64 => {name => "TF_USR_Temperature_2",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x65 => {name => "TF_USR_Temperature_3",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x66 => {name => "TF_USR_Temperature_4",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x67 => {name => "TF_USR_Temperature_5",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x68 => {name => "TF_USR_Temperature_6",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x69 => {name => "TF_USR_Temperature_7",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x6A => {name => "TF_USR_Temperature_8",            size => 4, isSigned => 0, factor => 1, unit => "°C"},
    0x6C => {name => "Heap_Free",                       size => 4, isSigned => 0, factor => 1, unit => "-"},
    
    0x72 => {name => "Leaf_Wetness_1",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x73 => {name => "Leaf_Wetness_2",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x74 => {name => "Leaf_Wetness_3",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x75 => {name => "Leaf_Wetness_4",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x76 => {name => "Leaf_Wetness_5",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x77 => {name => "Leaf_Wetness_6",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x78 => {name => "Leaf_Wetness_7",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x79 => {name => "Leaf_Wetness_8",                  size => 1, isSigned => 0, factor => 1, unit => "-"},
    
    #added in API version 1.6.4
    0x7A => {name => "Rain_Priority",                   size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x7B => {name => "Radiation_Compensation",          size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x7C => {name => "Unknown_0x7C",                    size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x7D => {name => "Unknown_0x7D",                    size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x7E => {name => "Unknown_0x7E",                    size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x7F => {name => "Unknown_0x7F",                    size => 1, isSigned => 0, factor => 1, unit => "-"},
    0x80 => {name => "Piezo_Rain_Rate",                 size => 2, isSigned => 0, factor => 0.1, unit => "mm"},
    0x81 => {name => "Piezo_Rain_Event",                size => 2, isSigned => 0, factor => 0.1, unit => "mm"},
    0x82 => {name => "Piezo_Rain_Hourly",               size => 2, isSigned => 0, factor => 0.1, unit => "mm"},
    0x83 => {name => "Piezo_Rain_Daily",                size => 4, isSigned => 0, factor => 0.1, unit => "mm"},
    0x84 => {name => "Piezo_Rain_Weekly",               size => 4, isSigned => 0, factor => 0.1, unit => "mm"},
    0x85 => {name => "Piezo_Rain_Monthly",              size => 4, isSigned => 0, factor => 0.1, unit => "mm"},
    0x86 => {name => "Piezo_Rain_Yearly",               size => 4, isSigned => 0, factor => 0.1, unit => "mm"},
    0x87 => {name => "Piezo_Gain10",                    size => 20, isSigned => 0, factor => 1, unit => "-"},
    0x88 => {name => "Piezo_RainTime_Reset",            size => 3, isSigned => 0, factor => 1, unit => "-"},
);

my %ECOWITT_SensorID = (
    0x00 => {name => "WH65",                size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x01 => {name => "WH68",                size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x02 => {name => "WH80",                size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.02 },
    0x03 => {name => "WH40",                size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x04 => {name => "WH25",                size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x05 => {name => "WH26",                size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x06 => {name => "WH31_1",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x07 => {name => "WH31_2",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x08 => {name => "WH31_3",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x09 => {name => "WH31_4",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x0A => {name => "WH31_5",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x0B => {name => "WH31_6",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x0C => {name => "WH31_7",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x0D => {name => "WH31_8",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x0E => {name => "WH51_1",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x0F => {name => "WH51_2",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x10 => {name => "WH51_3",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x11 => {name => "WH51_4",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x12 => {name => "WH51_5",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x13 => {name => "WH51_6",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x14 => {name => "WH51_7",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x15 => {name => "WH51_8",              size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.1 },
    0x16 => {name => "WH41_1",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x17 => {name => "WH41_2",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x18 => {name => "WH41_3",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x19 => {name => "WH41_4",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x1A => {name => "WH57",                size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x1B => {name => "WH55_1",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x1C => {name => "WH55_2",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x1D => {name => "WH55_3",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x1E => {name => "WH55_4",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x1F => {name => "WH34_1",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x20 => {name => "WH34_2",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x21 => {name => "WH34_3",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x22 => {name => "WH34_4",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x23 => {name => "WH34_5",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x24 => {name => "WH34_6",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x25 => {name => "WH34_7",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x26 => {name => "WH34_8",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x27 => {name => "WH45",                size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x28 => {name => "WH35_1",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x29 => {name => "WH35_2",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x2A => {name => "WH35_3",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x2B => {name => "WH35_4",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x2C => {name => "WH35_5",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x2D => {name => "WH35_6",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x2E => {name => "WH35_7",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x2F => {name => "WH35_8",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
    0x30 => {name => "WS90",                size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.02 },
    0x31 => {name => "WS90a",               size => 4, isSigned => 1, batteryType => 1, Battery_Scaling => 0.02 },
    0x6c => {name => "WS906c",              size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 },
),
;

Readonly::Scalar my $ECOWITT_GW_STATE_NONE             => 0;
Readonly::Scalar my $ECOWITT_GW_STATE_STARTINIT        => 1;
Readonly::Scalar my $ECOWITT_GW_STATE_QUERY_APP        => 2;
Readonly::Scalar my $ECOWITT_GW_STATE_IDLE             => 4;
Readonly::Scalar my $ECOWITT_GW_STATE_UPDATE           => 3;
Readonly::Scalar my $ECOWITT_GW_STATE_RUNNING          => 99;
Readonly::Scalar my $ECOWITT_GW_STATE_UNSUPPORTED_FW   => 299;
Readonly::Scalar my $ECOWITT_GW_CMD_TIMEOUT            => 1;
Readonly::Scalar my $ECOWITT_GW_CMD_RETRY_CNT          => 3;
Readonly::Scalar my $ECOWITT_GW_UPD_INTERVAL           => 60;

my @ECOWITT_header = (0xff, 0xff);
my @ECOWITT_cmdPipe = (0, 0, 0 );

sub ECOWITT_GW_Initialize {
    my $hash = shift// return;

    $hash->{DefFn}      = \&ECOWITT_GW_Define;
    $hash->{UndefFn}    = \&ECOWITT_GW_Undef;
    $hash->{SetFn}      = \&ECOWITT_GW_Set;
    $hash->{AttrFn}     = \&ECOWITT_GW_Attr;
    $hash->{ReadFn}     = \&ECOWITT_GW_Read;
    $hash->{ReadyFn}    = \&ECOWITT_GW_Ready;
    $hash->{WriteFn}    = \&ECOWITT_GW_Write;
    $hash->{ShutdownFn} = \&ECOWITT_GW_Shutdown;
    #TODO fill AttrList from %attributeMap
    my %attributeMap = (
        connectTimeout => 'connectTimeout:30,60,120 ',
        updateInterval => 'updateInterval:15,30,60,120 ',
        #disableCommand =>  'disableCommand':'CMD_READ_FIRMWARE_VERSION',
    );
    $hash->{AttrList} =
        join(' ', values %attributeMap). " "   #add attributes from %attributeMap
        . $readingFnAttributes;
    return;
}

sub ECOWITT_GW_Define {
    my $hash = shift;
    my $def = shift // return;

    my @param = split m{\s+}xms, $def;

    if (int(@param) < 3) {
        return 'too few parameters: define <name> ECOWITT_GW <IP> [<Port>]';
    }

    $hash->{name}  = $param[0];
    $hash->{I_ECOWITT_IP} = $param[2] // return 'no device given';
    $hash->{I_ECOWITT_Port} = $param[3] // '45000';

    # first argument is the hostname or IP address of the device (e.g. "192.168.1.120")
    my $dev = $hash->{I_ECOWITT_IP};

    # add port to the device  
    $dev .= ":$hash->{I_ECOWITT_Port}" if $dev !~ m{:\d+$}x;

    # set the IP/Port for DevIo
    $hash->{DeviceName} = $dev;
    
    #check input parameters
    return ECOWITT_GW_Start($hash) if $init_done;

    InternalTimer(time+60, \&ECOWITT_GW_Start, $hash );
    return;
}

sub ECOWITT_GW_Undef {
    my $hash    = shift // return;
    my $name    = shift // return;
    my $noclose = shift;

    RemoveInternalTimer($hash, \&ECOWITT_GW_GetUpdate);

    if (!$noclose) {
        my $oldFD = $hash->{FD};
        DevIo_CloseDev($hash);
        Log3($hash, 3, "${name} device closed") if defined $oldFD && $oldFD && !defined $hash->{FD};
    }
    $hash->{DevState} = $ECOWITT_GW_STATE_NONE;
    $hash->{XmitOpen} = 0;
    
    return;
}


sub ECOWITT_GW_Set {
    my ( $hash, $name, $cmd, @arr ) = @_;

    return '"set" needs at least one parameter' if !defined $cmd;

    my %sets = (
        open         => 'noArg',
        close        => 'noArg',
        reopen       => 'noArg',
        restart      => 'noArg',
        test         => 'noArg',
    );

    return "Unknown argument ${cmd}, choose one of " .
        join(" ",map {"$_" . ($sets{$_} ? ":$sets{$_}" : "")} keys %sets)
      if $cmd eq '?';

    return ECOWITT_GW_Reopen($hash)         if $cmd eq 'reopen';
    return ECOWITT_GW_InitConnection($hash) if $cmd eq 'open';
    return ECOWITT_GW_Restart($hash)        if $cmd eq 'restart';
    return ECOWITT_GW_TestCmd($hash)        if $cmd eq 'test';

    if ($cmd eq 'close') {
        ECOWITT_GW_Undef($hash, $name);
        readingsSingleUpdate($hash, 'state', 'closed', 1);
        $hash->{XmitOpen} = 0;
        return;
    }

    return "Unknown argument ${cmd}, choose one of " .
        join(" ",map {"$_" . ($sets{$_} ? ":$sets{$_}" : "")} keys %sets);
}

sub ECOWITT_GW_Attr {
    my ($cmd, $name, $aName, $aVal) = @_;
    my $hash = $defs{$name} // return;

    #Log3($hash, 5, "ECOWITT_GW ${name} Attr ${cmd} ${aName} ".(($aVal)?$aVal:""));

    if ($aName eq 'verbose') {
        if ($hash->{keepAlive}) {
            if ($cmd eq 'set') {
                $attr{$hash->{keepAlive}->{NAME}}{$aName} = $aVal;
            } else {
                delete $attr{$hash->{keepAlive}->{NAME}}{$aName};
            }
        }
    }
    return;
}

sub ECOWITT_GW_Start {
    my $hash = shift // return;
    my $name = $hash->{NAME} // return; # own name / hash

    return if IsDisabled($name); # Return without any further action if the module is disabled

    if (!defined AttrVal($name,'devStateIcon',AttrVal($name,'stateFormat',undef))) {
        my $cmnd = '{ECOWITT_GW_devStateIcon($name)}';
        CommandAttr (undef, "$name devStateIcon $cmnd");
    }

    #start cyclic update of ECOWITT
    ECOWITT_GW_InitConnection($hash);
    ECOWITT_GW_GetUpdate($hash);
    return;
}

sub ECOWITT_GW_GetUpdate {
    my $hash = shift // return;
    my $name = $hash->{NAME} // return;
    my $cmdNext = '';

    if (!defined $hash->{UpdateCmd}) {
        $hash->{DevState} = $ECOWITT_GW_STATE_IDLE;
        $hash->{UpdateCmd} = 0;
        # start new timer.
        return InternalTimer(gettimeofday() + AttrVal($name, 'updateInterval', $ECOWITT_GW_UPD_INTERVAL), \&ECOWITT_GW_GetUpdate, $hash);
    }

    if ($hash->{UpdateCmd} == 0) {
        @ECOWITT_cmdPipe = ( $ECOWITT_cmdMap{CMD_READ_SENSOR_ID_NEW}, $ECOWITT_cmdMap{CMD_ECOWITT_LIVEDATA}, $ECOWITT_cmdMap{CMD_READ_RSTRAIN_TIME});
        Log3($name, 5, dump(@ECOWITT_cmdPipe));
        $hash->{DevState} = $ECOWITT_GW_STATE_UPDATE;
        $hash->{UpdateCmd} = $ECOWITT_cmdMap{CMD_READ_SENSOR_ID_NEW};

        $cmdNext = shift @ECOWITT_cmdPipe;
                    Log3  ($hash, 5, "cmdNext:".$cmdNext ." " . dump(@ECOWITT_cmdPipe));
        return ECOWITT_GW_send_frame($hash, $cmdNext, 0);
    }

    if ($hash->{UpdateCmd} == $ECOWITT_cmdMap{CMD_READ_SENSOR_ID_NEW}) {
        $hash->{UpdateCmd} = $ECOWITT_cmdMap{CMD_ECOWITT_LIVEDATA};
        $cmdNext = shift @ECOWITT_cmdPipe;
        Log3($hash, 5, "cmdNext:$cmdNext " . dump(@ECOWITT_cmdPipe));
        return ECOWITT_GW_send_frame($hash, $cmdNext, 0);
    }

    if ($hash->{UpdateCmd} == $ECOWITT_cmdMap{CMD_ECOWITT_LIVEDATA}) {
        $hash->{UpdateCmd} = $ECOWITT_cmdMap{CMD_READ_RSTRAIN_TIME};

        $cmdNext = shift @ECOWITT_cmdPipe;
        Log3($hash, 5, "cmdNext:$cmdNext " . dump(@ECOWITT_cmdPipe));
        ECOWITT_GW_send_frame($hash, $cmdNext, 0);
        $hash->{UpdateCmd} = '08154711';
        return;
    }

    $hash->{DevState} = $ECOWITT_GW_STATE_IDLE;
    $hash->{UpdateCmd} = 0;
    # start new timer.
    InternalTimer(gettimeofday() + AttrVal($name, 'updateInterval', $ECOWITT_GW_UPD_INTERVAL), \&ECOWITT_GW_GetUpdate, $hash);
    return;
}

sub ECOWITT_GW_TestCmd {
    my $hash = shift // return;
    my $name = $hash->{NAME};

    Log3($name, 5, 'ECOWITT_GW_TestCmd() Start.');
    my $testCmd = $ECOWITT_cmdMap{CMD_GET_MulCH_OFFSET};
    my @data = 0; #( 0x04, 0x04 );
    
    return if $hash->{DevState} != $ECOWITT_GW_STATE_IDLE;

    RemoveInternalTimer($hash, \&ECOWITT_GW_GetUpdate);
    
    $hash->{DevState} = $ECOWITT_GW_STATE_QUERY_APP;

    # data to send to a server
    my @packet;
    push(@packet, @ECOWITT_header);
    push(@packet, $testCmd);
    push(@packet, 0x03);
    push(@packet, sum(@packet) - sum(@ECOWITT_header));

    my $req = pack('C*', @packet);

    #my $sendtime = scalar(gettimeofday());
    DevIo_SimpleWrite($hash, $req, 0);
    Log3($hash, 2, "ECOWITT_GW_TestCmd (".length($req)."): ".unpack("H*", $req));
    return;
}

sub ECOWITT_GW_Connect {
    my $hash = shift // return;
    my $err  = shift;

#    if (defined(AttrVal($name, "dummy", undef))) {
#        ECOWITT_GW_Dummy($hash);
#        return;
#    }
    return if !$err;

    my $retry = '';
    if(defined($hash->{NEXT_OPEN})) {
        $retry = ", retrying in " . sprintf("%.2f", ($hash->{NEXT_OPEN} - time())) . 's';
    }
    Log3($hash, 3, "ECOWITT_GW $hash->{NAME}: ${err}$retry");
    if (!defined($hash->{NEXT_OPEN})) {
        Log3($hash, 0, "DevIO giving up on ${err}, retrying anyway");
        ECOWITT_GW_Reopen($hash);
    }
    return;
}

sub ECOWITT_GW_Ready {
    my $hash = shift // return;
    my $name = $hash->{NAME};
    my $state = ReadingsVal($name, 'state', 'unknown');

    Log3($hash, 4, "ECOWITT_GW ${name} ready: ${state}");

    if ((!$hash->{'.lgwHash'}) && $state eq 'disconnected') {
        # don't immediately reconnect when we just disconnected, delay
        # for 5s because remote closed the connection on us
        if (defined $hash->{LastOpen} &&
            $hash->{LastOpen} + 5 >= gettimeofday()) {
                Log3($name, 5, 'ECOWITT_GW_Ready() End_1.');
            return 0;
        }
        Log3($name, 5, 'ECOWITT_GW_Ready() End_2.');
        return ECOWITT_GW_Reopen($hash, 1);
    }
    Log3($name, 5, 'ECOWITT_GW_Ready() End.');
    return 0;
}

sub ECOWITT_GW_Reopen {
    my $hash    = shift // return;
    my $noclose = shift;
    $hash = $hash->{'.lgwHash'} if ($hash->{'.lgwHash'});
    my $name = $hash->{NAME};

    Log3($name, 4, "ECOWITT_GW ${name} Reopen");

    ECOWITT_GW_Undef($hash, $name, $noclose);
    return DevIo_OpenDev($hash, 1, 'ECOWITT_GW_DoInit', \&ECOWITT_GW_Connect);
}

sub ECOWITT_GW_Restart {
    my $hash    = shift // return;

    RemoveInternalTimer($hash, \&ECOWITT_GW_GetUpdate);
    
    $hash->{DevState} = $ECOWITT_GW_STATE_QUERY_APP;
    ECOWITT_GW_send_frame($hash, $ECOWITT_cmdMap{CMD_WRITE_REBOOT}, 0);
    return;
}

sub ECOWITT_GW_DoInit {
    my $hash = shift // return;
    my $name = $hash->{NAME};

    $hash->{CNT} = 0x00;
    delete($hash->{DEVCNT});
    delete($hash->{Helper});
    delete($hash->{owner});
    $hash->{DevState} = $ECOWITT_GW_STATE_NONE;
    $hash->{XmitOpen} = 0;
    $hash->{LastOpen} = gettimeofday();

    $hash->{Helper}{Log}{IDs} = [ split m{,}xms, AttrVal($name, 'logIDs', '') ];
    $hash->{Helper}{Log}{Resolve} = 1;

    RemoveInternalTimer($hash);
    $hash->{StartInitCmd} = 0;
    InternalTimer(gettimeofday()+1, \&ECOWITT_GW_StartInit, $hash, 0);

    return;
}

sub ECOWITT_GW_StartInit {
    my $hash = shift // return;
    my $name = $hash->{NAME};

    Log3($hash, 4, "ECOWITT_GW ${name} StartInit");
    my @cmdPipe = { 0, 0, 0, 0 };
    my $cmdNext = '';
    RemoveInternalTimer($hash);

    if ($hash->{StartInitCmd} == 0) {
        @ECOWITT_cmdPipe = ($ECOWITT_cmdMap{CMD_READ_SSSS}, $ECOWITT_cmdMap{CMD_READ_STATION_MAC}, $ECOWITT_cmdMap{CMD_READ_FIRMWARE_VERSION}, 0 );

        $hash->{StartInitCmd} = $ECOWITT_cmdMap{CMD_READ_SSSS};
        $hash->{DevState} = $ECOWITT_GW_STATE_STARTINIT;
        $cmdNext = shift @ECOWITT_cmdPipe;
        Log3 ($hash, 5, "cmdNext:$cmdNext, ". dump(@ECOWITT_cmdPipe));
        ECOWITT_GW_send_frame($hash, $cmdNext, 0);
    } elsif ($hash->{StartInitCmd} == $ECOWITT_cmdMap{CMD_READ_SSSS}) {
        Log3  ($hash, 5, "cmdPipe: " . dump(@ECOWITT_cmdPipe));
        $hash->{StartInitCmd} = "$ECOWITT_cmdMap{CMD_READ_STATION_MAC}";
        $cmdNext = shift @ECOWITT_cmdPipe;
        Log3  ($hash, 5, "cmdNext:$cmdNext, " . dump(@ECOWITT_cmdPipe));
        ECOWITT_GW_send_frame($hash, $cmdNext, 0);
    } elsif($hash->{StartInitCmd} == $ECOWITT_cmdMap{CMD_READ_STATION_MAC}) {
        Log3  ($hash, 5, "cmdPipe: " . dump(@ECOWITT_cmdPipe));
        $hash->{StartInitCmd} = $ECOWITT_cmdMap{CMD_READ_FIRMWARE_VERSION};
        $cmdNext = shift @ECOWITT_cmdPipe;
        Log3  ($hash, 5, "cmdNext:".$cmdNext);
        Log3  ($hash, 5, dump(@ECOWITT_cmdPipe));
        ECOWITT_GW_send_frame($hash, $cmdNext, 0);
    } else {
        $hash->{DevState} = $ECOWITT_GW_STATE_QUERY_APP;
        $hash->{UpdateCmd} = "0";
        ECOWITT_GW_GetUpdate($hash);
    }
    return;
}


sub ECOWITT_GW_InitConnection {
    my $hash = shift // return;
    my $name = $hash->{NAME};

    if (defined(AttrVal($name, 'dummy', undef))) {
        Log3($name, 5, 'ECOWITT_GW_InitConnection() End_1.');
        return;
    }

    if (!$init_done) {
        InternalTimer(gettimeofday()+15, \&ECOWITT_GW_InitConnection, $hash, 0);
        return;
    }

    DevIo_OpenDev($hash, 0, "ECOWITT_GW_DoInit", \&ECOWITT_GW_Connect);
    return;
}

sub ECOWITT_GW_Shutdown {
    my $hash = shift // return;
    DevIo_CloseDev($hash);
    return;
}

# ECOWITT_GW_send_frame() buils the packet to send : header+cmd+lenght+data+CRC
sub ECOWITT_GW_send_frame {
    my ($hash, $cmd, $size, @data) = @_;
    my $name = $hash->{NAME} // return;

    Log3 $hash, 5, "ECOWITT_GW_send_frame start. cmd: $cmd";

    # data to send to a server
    my @packet;
    push(@packet, @ECOWITT_header);
    push(@packet, $cmd);
    push(@packet, scalar(@data) + 3);
    push(@packet, @data);
    push(@packet, sum(@packet) - sum(@ECOWITT_header));
    
    my $req = pack('C*', @packet);

    DevIo_SimpleWrite($hash, $req, 0);
    Log3($hash, 4, "ECOWITT_GW_send_frame write raw (".length($req)."): ".unpack("H*", $req));
    return;
}

sub ECOWITT_GW_CheckCmdResp {
    my $hash = shift // return;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);

    #The data we wait for might have already been received but never
    #read from the FD. Do a last check now and process new data.
    if ( defined $hash->{FD} ) {
        my $rin = '';
        vec($rin, $hash->{FD}, 1) = 1;
        my $n = select($rin, undef, undef, 0);
        if ($n > 0) {
            Log3($hash, 5, "ECOWITT_GW ${name} ECOWITT_GW_CheckCmdResp: FD is readable, this might be the data we are looking for!");
            #We will be back very soon!
            InternalTimer(gettimeofday()+0, \&ECOWITT_GW_CheckCmdResp, $hash, 0);
            ECOWITT_GW_Read($hash);
            return;
        }
    }

    if ($hash->{DevState} != $ECOWITT_GW_STATE_RUNNING) {
        if ((!defined($hash->{Helper}{AckPending}{$hash->{CNT}}{frame})) ||
            (defined($hash->{Helper}{AckPending}{$hash->{CNT}}{resend}) &&
            $hash->{Helper}{AckPending}{$hash->{CNT}}{resend} >= $ECOWITT_GW_CMD_RETRY_CNT)) {
            Log3($hash, 1, "ECOWITT_GW ${name} did not respond after all, reopening");
            ECOWITT_GW_Reopen($hash);
        } else {
            $hash->{Helper}{AckPending}{$hash->{CNT}}{resend}++;
            Log3($hash, 1, "ECOWITT_GW ${name} did not respond for the " .
                $hash->{Helper}{AckPending}{$hash->{CNT}}{resend} .
                ". time, resending");
            # ECOWITT_GW_send_frame($hash, pack("H*", $hash->{Helper}{AckPending}{$hash->{CNT}}{frame}));
            InternalTimer(gettimeofday()+$ECOWITT_GW_CMD_TIMEOUT, \&ECOWITT_GW_CheckCmdResp, $hash, 0);
        }
    }
    return;
}

sub ECOWITT_GW_Read {
    my $hash = shift // return;
    my $name = $hash->{NAME};
    my $recvtime = gettimeofday();

    my $buf = DevIo_SimpleRead($hash);
    return '' if !defined $buf;

    my $err = '';

    Log3($hash, 5, "ECOWITT_GW ${name} read raw (".length($buf)."): ".ECOWITT_GW_hexDump($buf));

    my $p = pack("H*", $hash->{PARTIAL}) . $buf;
    $hash->{PARTIAL} .= unpack("H*", $buf);

    my $response_string = $p;
    my @response = unpack('(C)*', $response_string);
    Log3 $name, 4, "ECOWITT_GW <$hash->{name}>: received response: " . unpack('H*', $response_string) . " (@response)";

    # unpack response
    my @response_header = (shift(@response), shift(@response));
    my $response_cmd = shift(@response);
    my $response_size = 0;
    my $sizeOfsize = 0;
    if ($response_cmd == $ECOWITT_cmdMap{CMD_BROADCAST} ||
        $response_cmd == $ECOWITT_cmdMap{CMD_ECOWITT_LIVEDATA} ||
        $response_cmd == $ECOWITT_cmdMap{CMD_READ_SENSOR_ID_NEW} ||
        $response_cmd == $ECOWITT_cmdMap{CMD_READ_RSTRAIN_TIME} ) {
        # size is 2 byte
        $response_size = shift(@response) * 256 + shift(@response);
        $sizeOfsize = 2;
    } else {
        # size is 1 byte
        $response_size = shift(@response);
        $sizeOfsize = 1;
    }
    
    my $response_cs = pop(@response);
    my @response_data = @response;
    
    $err = sprintf("HEADER: 0x%x 0x%x; CMD: 0x%x; SIZE: $response_size; CHECKSUM: $response_cs; DATA: @response_data", $response_header[0], $response_header[1], $response_cmd);
    Log3($name, 4, "ECOWITT_GW <$hash->{name}>: $err");
    
    #check fixed header = 0xffff
    if ($response_header[0] != 0xff || $response_header[1] != 0xff) {
        $err = sprintf("ERROR: fixed header is 0x%x 0x%x ! (Should be '0xff 0xff')", $response_header[0], $response_header[1]);
        Log3  $name,1, "ECOWITT_GW <$hash->{name}>: $err";
        return;
    }
    
    #check size (SIZE: 1 byte, packet size，counted from CMD till CHECKSUM)
    ## REMARK some packages have size/2
    my $size_calc = scalar(@response_data) + 2 + $sizeOfsize;
    if ($response_size != $size_calc) {
        $err = sprintf("ERROR: response size is not equal to size reported in response (reported: $response_size; actual: $size_calc)");
        Log3($name, 1, "ECOWITT_GW <$hash->{name}>: $err");
        return;
    }
    
    ECOWITT_GW_updateData( $hash, $response_cmd, @response_data);

    my $unprocessed;

    if (defined($unprocessed)) { #Beta-User: useless question, or?
        $hash->{PARTIAL} = unpack("H*", $unprocessed);
    } else {
        $hash->{PARTIAL} = '';
    }
    return;
}

### aux functions
sub ECOWITT_GW_hexDump {
    my ($buf) = @_;

    my @retval;
    my @array = unpack("C*", $buf);
    for (my $i = 0; $i < scalar(@array); $i++) {
        push (@retval, sprintf('%02x', $array[$i]));
    }
    return "[" . join(" ", @retval) . "]";
}

# example: $value = ECOWITT_GW_toInt(4, \@data);
# this creates an integer return value from 4 bytes in the @data array
# the @data array is shifted by 4 bytes
sub ECOWITT_GW_toInt {
    my $size = shift;
    my $dataref = shift;
    my $result = 0;
    #my $msg= "$size byte(s): ";
    for (my $i = 0; $i < $size; $i++) {
        $result *= 256;
        my $byte = shift(@$dataref);
        #$msg .= "$byte ";
        $result += $byte;
    }   
    #$msg .= " = $result";
    #Log3("toInt", 5, "ECOWITT_GW: $msg"); 
    return $result;
}

# The API doc says it is UTC time but actually it is local time.
# We therefore use gmtime() instead of localtime() in order to NOT adjust to localtime
sub ECOWITT_GW_FmtDateTime {
  my @t = gmtime(shift);
  return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
      $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}


# method to analyze the returned data and set the corresponding readings
sub ECOWITT_GW_updateData {
    my ($hash, $cmd, @data) = @_;
    my $name = $hash->{name} // return;

    my $msg = sprintf("Received %s (0x%x). Unpacking data...",  $ECOWITT_cmdMap_reversed{$cmd}, $cmd);
    Log3($name, 5, "ECOWITT_GW: $msg"); 
    
    ### process returned data for CMD_READ_STATION_MAC ######
    if ($cmd == $ECOWITT_cmdMap{CMD_READ_STATION_MAC}) 
    {
        readingsSingleUpdate($hash, "Station_MAC", sprintf("%x %x %x %x %x %x", @data), 1 );
    }
    ### process returned data for CMD_WRITE_REBOOT ######
    elsif ($cmd == $ECOWITT_cmdMap{CMD_WRITE_REBOOT}) {
        my $resetQuit = shift @data;
        $msg = sprintf("%s returns (0x%x)",$ECOWITT_cmdMap_reversed{$cmd}, $resetQuit);
        Log3 $name, 4, "ECOWITT_GW: $msg";

        InternalTimer(gettimeofday() + AttrVal($name, 'commandTimeout', $ECOWITT_GW_CMD_TIMEOUT), \&ECOWITT_GW_InitConnection, $hash, 0);
    }
    elsif ($cmd == $ECOWITT_cmdMap{CMD_READ_FIRMWARE_VERSION}) {
        shift @data;
        my $x = join '', map {chr} @data;
        readingsSingleUpdate($hash, 'Firmware_Version', sprintf("%s" , $x), 1 );
    }
    elsif ($cmd == $ECOWITT_cmdMap{CMD_READ_SSSS}) {

        readingsBeginUpdate($hash);

        my $readingsName = 'SensorReceiveFrequency';
        my $valueItem = shift @data;
        my $itemvals = { 0 => 433, 1 => 868, 2 => 915, 3 => 920};
        my $rfFrequency = $itemvals->{$valueItem} // "unknown value $valueItem";
        readingsBulkUpdate($hash, $readingsName, $rfFrequency);

        $readingsName = 'SensorType';
        $valueItem = shift @data;
        $itemvals = { 0 => 'WH24', 1 => 'WH65'};
        my $sensorType = $itemvals->{$valueItem} // "unknown value $valueItem";
        readingsBulkUpdate($hash, $readingsName, $sensorType);
        
        # this is the time of execution of the read system parameter comand CMD_READ_SSSS
        $readingsName = 'Time';
        my $Time = ECOWITT_GW_toInt(4, \@data);
        # we do not expose that value
        #readingsBulkUpdate($hash, $readingsName, $Time);

        # this is probably the index in the gateway's internal list of timezones
        $valueItem = shift @data;
        $readingsName = 'TimeZoneIndex';
        # we do not expose that value
        #readingsBulkUpdate($hash, $readingsName, $valueItem);

        # My tests resulted in values that could not be interpreted:
        # If auto timezone is off, the value is 3. If auto timezone is on, the value is 1 in winter.
        $readingsName = 'DST_status';
        $valueItem = shift @data;
        $itemvals = { 0 => 'OFF', 1 => 'ON'}; # todo: seems to be reserved, okay winter, re-check in summer
        my $dstStatus = $itemvals->{$valueItem} // "unknown value $valueItem";
        # we do not expose that value
        readingsBulkUpdate($hash, $readingsName, $dstStatus);

        readingsEndUpdate($hash, 1);
    }
    elsif ($cmd == $ECOWITT_cmdMap{CMD_READ_SENSOR_ID_NEW}) {
        # $msg = sprintf("updateData() $cmd(%s)",   $cmd);
        # Log3 $name, 5, $msg;
    
        readingsBeginUpdate($hash);

        my $dataLength = @data;
        my $item = shift(@data);
        # $msg = sprintf("updateData() cmd: (%s) item: %x  Length:%s",   $cmd, $item, $dataLength);
        # Log3 $name, 5, $msg;
        while ($dataLength > 0)
        {
            if (!exists $ECOWITT_SensorID{$item} ) {
                # the SensorID is not in the hash of known sensors
                # we therefore add a dummy entry
                my $hex = sprintf("%02x", $item);
                $ECOWITT_SensorID{$item} = {name => "unknown_$hex", size => 4, isSigned => 1, batteryType => 0, Battery_Scaling => 0 };
                Log3 $name, 5, "ECOWITT_GW: unknown SensorID 0x$hex encountered.";
            };
            my $value = ECOWITT_GW_toInt($ECOWITT_SensorID{$item}{size}, \@data);
            if ( $ECOWITT_SensorID{$item}{isSigned}) {
                if    ($ECOWITT_SensorID{$item}{size} == 1) {$value = unpack('c', pack('C', $value));}
                elsif ($ECOWITT_SensorID{$item}{size} == 2) {$value = unpack('s', pack('S', $value));}
                elsif ($ECOWITT_SensorID{$item}{size} == 4) {$value = unpack('q', pack('Q', $value));}
                else
                {
                $msg = sprintf("ERROR: Received %s (0x%02x) but don't know how to convert value of size %d to signed integer. Skipping...", $ECOWITT_SensorID{$item}{name}, $item, $ECOWITT_SensorID{$item}{size});
                Log3 $name, 1, "ECOWITT_GW: $msg";
                }
            }
            my $batteryValue = shift @data;
            my $receiveValue = shift @data;
            if ($value != 0xFFFFFFFF && $value != 0xFFFFFFFE) {
                if ($ECOWITT_SensorID{$item}{batteryType} == 1) {
                    $msg = sprintf("battery: %x", $batteryValue);
                    #$batteryValue = unpack('c', pack('C', $batteryValue));
                    $msg = sprintf("%s unpacked: %s", $msg , $batteryValue);
                    if (($ECOWITT_SensorID{$item}{Battery_Scaling} == 0.1) && ($batteryValue == 0x1F))                 {
                        $batteryValue = '0.0';
                    } else {
                        $batteryValue *= $ECOWITT_SensorID{$item}{Battery_Scaling};
                    }
                    $msg = sprintf("%s scaled: %s", $msg , $batteryValue);
                    Log3 $name, 5, "ECOWITT_GW: $msg";
                }
                $msg = sprintf("Received %s (0x%02x) = %08.0x bat:%2.1f  recv:0x%x",  $ECOWITT_SensorID{$item}{name}, $item, $value, $batteryValue, $receiveValue);
                Log3 $name, 4, "ECOWITT_GW: $msg";
                readingsBulkUpdateIfChanged($hash, $ECOWITT_SensorID{$item}{name} . "_ID", sprintf("%x", $value) );
                readingsBulkUpdateIfChanged($hash, $ECOWITT_SensorID{$item}{name} . "_Battery", sprintf("%2.1f", $batteryValue) );
                readingsBulkUpdateIfChanged($hash, $ECOWITT_SensorID{$item}{name} . "_Signal", sprintf("%d", $receiveValue) );
            } elsif ($value != 0xFFFFFFFF) {
                $msg = sprintf("Received %s (0x%02x) never seen.", $ECOWITT_SensorID{$item}{name}, $item);
                Log3 $name, 5, "ECOWITT_GW: $msg";
            } elsif ($value != 0xFFFFFFFE) {
                $msg = sprintf("Received %s (0x%02x) disabled.",  $ECOWITT_SensorID{$item}{name}, $item);
                Log3 $name, 5, "ECOWITT_GW: $msg";
            }
            $dataLength = @data;
            $item = shift @data;
        }
        readingsEndUpdate($hash, 1);
    }
    elsif ($cmd == $ECOWITT_cmdMap{CMD_ECOWITT_LIVEDATA}) {
        readingsBeginUpdate($hash);
        my $lightning_happened_time_changed = 0;
        while (my $item = shift(@data))
        {
            if (exists $ECOWITT_Items{$item}) {
                my $value = ECOWITT_GW_toInt($ECOWITT_Items{$item}{size}, \@data);
                my $unit = "";
                if ( $ECOWITT_Items{$item}{isSigned}) {
                    if    ($ECOWITT_Items{$item}{size} == 1) {$value = unpack('c', pack('C', $value));}
                    elsif ($ECOWITT_Items{$item}{size} == 2) {$value = unpack('s', pack('S', $value));}
                    elsif ($ECOWITT_Items{$item}{size} == 4) {$value = unpack('q', pack('Q', $value));}
                    else {
                        $msg = sprintf("ERROR: Received %s (0x%x) but don't know how to convert value of size %d to signed integer. Skipping...", $ECOWITT_Items{$item}{name}, $item, $ECOWITT_Items{$item}{size});
                        Log3($name, 1, "ECOWITT_GW: $msg");
                    }
                }
                my $formatString = "%2.1f";
                if ($item != 0x17) {
                    $value *= $ECOWITT_Items{$item}{factor};
                } else {
                    $formatString = "%2d";
                }
                if ($ECOWITT_Items{$item}{unit} ne "-") {
                    $unit = "[" . $ECOWITT_Items{$item}{unit} . "]";
                    # convert Unix timestamp to human-readable time
                    # for reading 0x61 = lightning_happened_time this is actually UTC and not local time (verified)
                    if($ECOWITT_Items{$item}{unit} eq "time") {
                        $value = FmtDateTime($value);
                        $formatString = "%s";
                    }
                }

                # special treatment for lightning strikes
                # 0x61 = lightning_happened_time 
                # check for change of lightning_happened_time
                # We use the item index instead of the name because reading name might change someday.
                if(($item == 0x61) && (ReadingsVal($name, $ECOWITT_Items{$item}{name}, $value) ne $value)) { 
                    $lightning_happened_time_changed = 1;
                }

                $msg = sprintf("Received %s (0x%x) = " . $formatString . " %s", $ECOWITT_Items{$item}{name}, $item, $value, $unit);
                Log3 $name, 4, "ECOWITT_GW: $msg";
                readingsBulkUpdateIfChanged($hash, $ECOWITT_Items{$item}{name}, sprintf( $formatString, $value) );
            } else {
                readingsBulkUpdateIfChanged($hash, "Error_unknown ECOWITT_Item", "0x$item");
            }

        }
        # We read back the lightning_distance reading 0x60 after all readings have been updated.
        # This ensures that the current distance is written to the synthetic lightning_strike reading 
        # if the lightning_distance is received after the lightning_happened_time.
        # We use the item index instead of the name because reading name might change someday.
        # 0x60 = lightning_distance
        # The lightning_strike reading has the actual time of the lightning as timestamp (assuming that the
        # sensors sends lightning data immediately after the lightning has stroken). This is for plotting
        # lightning distances over time.
        if($lightning_happened_time_changed) {
            readingsBulkUpdate($hash, "lightning_strike", ReadingsVal($name, $ECOWITT_Items{0x60}{name}, 0.0));
        }

        readingsEndUpdate($hash, 1);

    }
    elsif ($cmd == $ECOWITT_cmdMap{CMD_READ_RSTRAIN_TIME}) {

        readingsBeginUpdate($hash);
        while (my $item = shift(@data)) {

            if (exists $ECOWITT_Items{$item}) {
                my $value = 0;
                my $unit = "";
                $value = ECOWITT_GW_toInt($ECOWITT_Items{$item}{size}, \@data);
                if ( $ECOWITT_Items{$item}{isSigned}) {
                    if    ($ECOWITT_Items{$item}{size} == 1) {$value = unpack('c', pack('C', $value));}
                    elsif ($ECOWITT_Items{$item}{size} == 2) {$value = unpack('s', pack('S', $value));}
                    elsif ($ECOWITT_Items{$item}{size} == 4) {$value = unpack('q', pack('Q', $value));}
                    else {
                    $msg = sprintf("ERROR: Received %s (0x%x) but don't know how to convert value of size %d to signed integer. Skipping...", $ECOWITT_Items{$item}{name}, $item, $ECOWITT_Items{$item}{size});
                    Log3 $name, 1, "ECOWITT_GW: $msg";
                    }
                }

                $value *= $ECOWITT_Items{$item}{factor};
                if ($ECOWITT_Items{$item}{unit} ne "-") {
                    $unit = "[" . $ECOWITT_Items{$item}{unit} . "]";
                }
                if (!(($item == 0x87) || ($item == 0x88))){
                    $msg = sprintf("Received %s (0x%x) = %2.1f %s",  $ECOWITT_Items{$item}{name}, $item, $value, $unit);
                    Log3 $name, 4, "ECOWITT_GW: $msg";
                    readingsBulkUpdateIfChanged($hash, $ECOWITT_Items{$item}{name}, sprintf("%2.1f", $value) );
                } elsif ($item == 0x88) {
                    $msg = sprintf("Received %s (0x%x) = 0x%08x",  $ECOWITT_Items{$item}{name}, $item, $value);
                    Log3 $name, 4, "ECOWITT_GW: $msg";

                    my $hourmask   = 0b00000000_00011111_00000000_00000000;
                    my $daymask    = 0b00000000_00000000_00000001_00000000;
                    my $monthmask  = 0b00000000_00000000_00000000_00001111;

                    my $resethour  = ($value & $hourmask) >> (16);
                    my $resetday   = ($value & $daymask ) >> (8);
                    my $resetmonth = ($value & $monthmask);

                    # Debug(sprintf("value: 0x%08x resethour: 0x%08x  resetday: 0x%08x  resetmonth: 0x%08x",$value , $resethour, ($resetday ), ($resetmonth) ));
                    my @resDay = ("Son", "Mon");
                    my @resMonth = ( "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez");

                    readingsBulkUpdateIfChanged($hash, $ECOWITT_Items{$item}{name} . "_hour", sprintf("%02d", $resethour) );
                    readingsBulkUpdateIfChanged($hash, $ECOWITT_Items{$item}{name} . "_day",  $resDay[$resetday] );
                    readingsBulkUpdateIfChanged($hash, $ECOWITT_Items{$item}{name} . "_month", $resMonth[$resetmonth] );
                }
            } else {
                $msg = sprintf("ECOWITT_Items (0x%x) is unknown. Skipping complete package!", $item);
                Log3($name, 1, "ECOWITT_GW: $msg");
            }
        }
        readingsEndUpdate($hash, 1);
    }
    else {
        Log3 $name, 1, "ECOWITT_GW: Unknown data received. Skipping!";
    }
    if ($hash->{DevState} == $ECOWITT_GW_STATE_STARTINIT) {
        ECOWITT_GW_StartInit($hash);
    } elsif ($hash->{DevState} == $ECOWITT_GW_STATE_UPDATE) {
        ECOWITT_GW_GetUpdate($hash);
    }
    return 1;
}

sub ECOWITT_GW_devStateIcon {
  my $devname = shift // return;
  my $conicon = shift // "lan_rs485";
 
  return if !defined $defs{$devname};
  my $alivecolor = "${conicon}\@red";
  $alivecolor = "${conicon}\@green" if ReadingsVal($devname, 'state', 'disconnected') eq 'opened';
  my $ret = '<div style="text-align:right">';
  $ret .= FW_makeImage($alivecolor,'lan_rs485');
  $ret .= ' ';
  $ret .= FW_makeImage('weather_barometric_pressure','weather_barometric_pressure');
  $ret .= ' ';
  $ret .= ReadingsVal($devname,'Barometric_Relative',0);
  $ret .= ' ';
  $ret .= FW_makeImage('humidity','humidity');
  $ret .= ReadingsVal($devname,'Humidity_Outdoor',0);
  $ret .= '%rH ';
  $ret .= FW_makeImage('temp_temperature','temp_temperature');
  $ret .= ReadingsVal($devname,'Temperature_Outdoor',0);
  $ret .='°C ';
  my $dir = 225-ReadingsVal($devname,'Wind_Direction',0);
  my $dirIcon = FW_makeImage('weather_directions2','ws_N_kl');
  $dirIcon =~ s{var.--myRot.}{${dir}deg}x;
  $ret .= $dirIcon;
  $ret .='</div>';
  return $ret;
}

1;

__END__
=pod
=item summary    support for the EcoWitt API on various (W)LAN Gateways
=item summary_DE Anbindung f&uuml;r die EcoWitt API diverser (W)LAN Gateways
=begin html

<a id="ECOWITT_GW"></a>
<h3>ECOWITT_GW</h3>
<ul>
  ECOWITT_GW provides support for the EcoWitt API on various (Wireless) LAN Gateways. Tested with  GW1000, WH2650 and GW2000.<br>
  <br>

  <a id="ECOWITT_GW-define"></a>
  <b>Define</b>
  <ul>
      <code>define &lt;name&gt; ECOWITT_GW &lt;device&gt;</code><br>
      <br>
      The &lt;device&gt;-parameter specifies the IP address or hostname
          of the gateway, optionally followed by : and the port number
          API-port (default when not specified: 45000).<br>
    <br>
    Example for an ecoWitt LAN Gateway at <code>192.168.42.23:45000</code>:<br>
       <ul><code>define myGW ECOWITT_GW 192.168.42.23</code><br>&nbsp;
    </ul>
  </ul>
  <a id="ECOWITT_GW-set"></a>
  <p><b>Set</b></p>
  <ul>
    <a id="ECOWITT_GW-set-open"></a><li><i>open</i><br><ul>Open the connection to the (W)LAN Gateway.</ul></li>
    <a id="ECOWITT_GW-set-close"></a><li><i>close</i><br><ul>Close the connection to the (W)LAN Gateway.</ul></li>
    <a id="ECOWITT_GW-set-reopen"></a><li><i>reopen</i><br><ul>Reopen the connection to the (W)LAN Gateway.</ul></li>
    <a id="ECOWITT_GW-set-restart"></a><li><i>restart</i><br><ul>initiates a system reboot on the connected (W)LAN Gateway.</ul></li>
  </ul>
  <br>
  <a id="ECOWITT_GW-attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li><a id="ECOWITT_GW-attr-updateInterval"></a>
    <dt><code><b>updateInterval</b></code></dt>
    Time in seconds when the next Update request is made.
        Default: 60</li>
    <li><a id="ECOWITT_GW-attr-connectTimeout"></a>
    <dt><code><b>connectTimeout</b></code></dt>
    Timeout in seconds for a connection to the (W)LAN Gateway
        if no response in connectTimeout seconds an repeated Connection request
        is initiated (3 x times).<br>
        Default: 15</li>
  </ul>
</ul>

=end html

=begin html_DE

<a id="ECOWITT_GW"></a>
<h3>ECOWITT_GW</h3>
<ul>
  Das Modul ECOWITT_GW bietet Unterst&uuml;tzung zum Auslesen eines EcoWitt (W)LAN Gateway &uuml;ber die EcoWitt API. Erm&ouml;glicht das lokale Auslesen der angeschlossenen EcoWitt-Sensoren.<br>

  <br>

  <a id="ECOWITT_GW-define"></a>
  <p><b>Define</b></p>
  <ul>
    <li><code>define &lt;name&gt; ECOWITT_GW &lt;device&gt;</code><br><br>
        Der &lt;device&gt;-Parameter gibt die IP-Adresse oder den Hostnamen
        des Gateways an, optional gefolgt von : und der Portnummer des
        API-port (Standardwert, wenn nicht angegeben: 45000).
    </li>
    <br>
    Beispiel: Ein EcoWitt (W)LAN Gateway auf IP Adresse <code>192.168.42.23:45000</code>:<br>
        <ul><code>define myGW ECOWITT_GW 192.168.42.23</code><br>&nbsp;
    </ul>
  </ul>
  <a id="ECOWITT_GW-set"></a>
  <p><b>Set</b></p>
  <ul>
    <a id="ECOWITT_GW-set-open"></a><li><i>open</i><br><ul>&Ouml;ffnet die Verbindung zum (W)LAN Gateway.</ul></li>
    <a id="ECOWITT_GW-set-close"></a><li><i>close</i><br><ul>Schlie&szlig;t die Verbindung zum (W)LAN Gateway.</ul></li>
    <a id="ECOWITT_GW-set-reopen"></a><li><i>reopen</i><br><ul>Schli&szlig;t und &ouml;ffnet die Verbindung zum (W)LAN Gateway.</ul></li>
    <a id="ECOWITT_GW-set-restart"></a><li><i>restart</i><br><ul>l&ouml;st einen System Neustart am verbundenen (W)LAN Gateway aus.</ul></li>
  </ul>
  <a id="ECOWITT_GW-get"></a>
  <!--
  <p><b>Get</b></p>
  <ul>
    <a id="ECOWITT_GW-get-assignIDs"></a>
    <li><i>assignIDs</i><br><ul>Gibt die aktuell diesem IO-Ger&auml;t zugeordneten ecoWitt-Ger&auml;te zur&uuml;ck.</ul></li>
  </ul>
  -->
  <br>
  <a id="ECOWITT_GW-attr"></a>
  <p><b>Attribute</b></p>
  <ul>
    <li><a id="ECOWITT_GW-attr-updateInterval"></a>
    <dt><code><b>updateInterval</b></code></dt>
    setzt die Zeit in Sekunden, bis die nächste Update-Anfrage gestellt wird.
        Standardwert: 60</li>
    <li><a id="ECOWITT_GW-attr-connectTimeout"></a>
    <dt><code><b>connectTimeout</b></code></dt>
    setzt die Wartezeit in Sekunden für eine Verbindung zum (W)LAN Gateway -
        wenn keine Antwort in <i>connectTimeout</i> Sekunden wird eine wiederholte Verbindungsanfrage
        initiiert (3 x mal).<br>
        Standardwert: 15</li>
  </ul>
</ul>

=end html_DE

=cut

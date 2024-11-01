﻿##############################################
# $Id$$$
#
#  72_XiaomiDevice.pm
#
#  2020 Markus Moises < vorname at nachname . de >
#
#  This module connects to Xiaomi Smart Home WiFi devices
#  Currently supported: Air Purifiers, Robot Vacuums, Smart Fans, Humidifiers, Lamps, Rice Cooker, Power Plugs
#
#  https://forum.fhem.de/index.php/topic,73052.0.html
#
##############################################################################
#
# define <name> XiaomiDevice <ip> [<token>]
#
##############################################################################

package main;

use strict;
use warnings;
no warnings qw(redefine);

use Time::Local;
use POSIX qw( strftime );
use Data::Dumper; #debugging

#use JSON;
#use Digest::MD5 qw(md5);
#use Crypt::CBC;
#use Crypt::Rijndael_PP;
#use Crypt::Cipher::AES;
#use Crypt::ECB;

use SetExtensions;


##############################################################################

# my %device_types = (  '00c4' => "Air Purifier",
#                       '033b' => "Air Purifier 2",
#                       '0327' => "Smart Lamp",
#                       '02f2' => "Robot Vacuum",
#                       '0317' => "Robot Vacuum",
#                       '034c' => "Robot Vacuum",
#                       '034d' => "Robot Vacuum",
#                       '046c' => "Robot Vacuum",
#                       '0757' => "Robot Vacuum",
#                       '0404' => "UV Humidifier",
#                       '031e' => "Smart Fan" , );

my %vacuum_states = ( '0' => "Unknown",
                      '1' => "Starting up",
                      '2' => "Sleeping",
                      '3' => "Waiting",
                      '4' => "Remote control",
                      '5' => "Cleaning",
                      '6' => "Returning to base",
                      '7' => "Manual mode",
                      '8' => "Charging",
                      '9' => "Charging problem",
                     '10' => "Paused",
                     '11' => "Spot cleaning",
                     '12' => "Malfunction",
                     '13' => "Shutting down",
                     '14' => "Software update" ,
                     '15' => "Docking" ,
                     '16' => "Goto" ,
                     '17' => "Zoned Clean" ,
                     '18' => "Segment Clean" ,
                     '100' => "Fully Charged" ,
                     '101' => "Device offline" , );


my %vacuum_errors = ( '0' => "None",
                      '1' => "Laser sensor fault",
                      '2' => "Collision sensor fault",
                      '3' => "Wheel floating",
                      '4' => "Cliff sensor fault",
                      '5' => "Main brush blocked",
                      '6' => "Side brush blocked",
                      '7' => "Wheel blocked",
                      '8' => "Device stuck",
                      '9' => "Dust bin missing",
                     '10' => "Filter blocked",
                     '11' => "Magnetic field detected",
                     '12' => "Low battery",
                     '13' => "Charging problem",
                     '14' => "Battery failure",
                     '15' => "Wall sensor fault",
                     '16' => "Uneven surface",
                     '17' => "Side brush failure",
                     '18' => "Suction fan failure",
                     '19' => "Unpowered charging station",
                     '20' => "Unknown",
                     '21' => "Laser pressure sensor problem",
                     '22' => "Charge sensor problem",
                     '23' => "Docking problem",
                     '24' => "Exclusion zone",
                    '254' => "Bin full",
                    '255' => "Internal error" , );


my %vacuum_waterbox = ( '200' => 'off',
                        '201' => 'low',
                        '202' => 'medium',
                        '203' => 'high',
                        '204' => 'auto',
                      );


my %cooker_menus = ( '0000' => "None",
                     '0001' => "Cooking",
                     '0002' => "Quick cooking",
                     '0003' => "Rice porridge",
                     '0004' => "Heat preservation",
                     '0100' => "Personal settings" , );


my %cooker_stages = ( '00' => "Idle",
                      '01' => "Preheating",
                      '02' => "Water-absorbing",
                      '03' => "Boiling",
                      '04' => "Gelantinizing",
                      '05' => "Braising" , );





sub XiaomiDevice_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{DefFn}        = "XiaomiDevice_Define";
  $hash->{UndefFn}      = "XiaomiDevice_Undefine";
  $hash->{SetFn}        = "XiaomiDevice_Set";
  $hash->{GetFn}        = "XiaomiDevice_Get";
  $hash->{ReadFn}       = "XiaomiDevice_Read";
  $hash->{WriteFn}      = "XiaomiDevice_Write";
  $hash->{DbLog_splitFn}= "XiaomiDevice_DbLog_splitFn";
  $hash->{AttrFn}       = "XiaomiDevice_Attr";
  $hash->{AttrList}     = "subType:AirPurifier,AirPurifier3H,Humidifier,EvpHumidifier,HumidifierMJJSQ,VacuumCleaner,SmartFan,SmartFan1X,SmartFan1C,SmartFanFA1,TowerFanP9,SmartLamp,EyeCare,WaterPurifier,Camera,RiceCooker,PowerPlug intervalData intervalSettings preset disable:0,1 zone_names point_names map_names segment_names ".
                          $readingFnAttributes;

}

sub XiaomiDevice_Define($$$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my ($found, $dummy);


  return "syntax: define <name> XiaomiDevice <ip> [<token>]" if(int(@a) != 3 && int(@a) != 4 );
  my $name = $hash->{NAME};

  my $req = eval
  {
    require JSON;
    JSON->import();
    require Digest::MD5;
    Digest::MD5->import();
    require Crypt::CBC;
    Crypt::CBC->import();
    1;
  };
  if(!$req)
  {
    $hash->{STATE} = "JSON, Digest::MD5, Crypt::CBC and either Crypt::Cipher::AES or Crypt::Rijndael_PP are required!";
    $attr{$name}{disable} = "1";
    return undef;
  } else {
    use JSON;
    use Digest::MD5 qw(md5);
    use Crypt::CBC;
  }

  my $req3 = eval
  {
    require Crypt::Cipher::AES;
    Crypt::Cipher::AES->import();
    1;
  };
  if(!$req3)
  {
    Log3 $name, 4, "$name: Crypt::Cipher::AES not found";
    #$hash->{STATE} = "Crypt::Cipher::AES not found";
  } elsif(!defined($hash->{helper}{crypt}) || $hash->{helper}{crypt} ne "Rijndael") {
    $hash->{helper}{crypt} = "AES";
  }

  my $req2 = eval
  {
    require Crypt::Rijndael_PP;
    Crypt::Rijndael_PP->import();
    $Crypt::Rijndael_PP::DEFAULT_KEYSIZE = 128;
    1;
  };
  if(!$req2)
  {
    Log3 $name, 4, "$name: Crypt::Rijndael_PP not found";
    #$hash->{STATE} = "Crypt::Rijndael_PP not found";
  } elsif(!defined($hash->{helper}{crypt}) || $hash->{helper}{crypt} ne "AES") {
    $hash->{helper}{crypt} = "Rijndael";
  }



  if(!$hash->{helper}{crypt})
  {
    Log3 $name, 1, "$name: Crypt::Cipher::AES or Crypt::Rijndael_PP is required!";
    $hash->{STATE} = "Crypt::Cipher::AES or Crypt::Rijndael_PP is required!";
    $attr{$name}{disable} = "1";
    return undef;
  } else {
    Log3 $name, 3, "$name: initialized, using ".$hash->{helper}{crypt};
  }

  $hash->{helper}{ip} = $a[2];
  $hash->{helper}{port} = '54321';

  delete($hash->{helper}{packet}) if(defined($hash->{helper}{packet}));
  $hash->{helper}{packetid} = 1;

  $hash->{helper}{delay} = 60;

  $a[3] = '' if(!defined($a[3]));
  if(length($a[3]) == 32) {
    $hash->{helper}{token} = $a[3];
  } elsif(length($a[3]) == 96) {

    my $req3 = eval
    {
      require Crypt::ECB;
      Crypt::ECB->import();
      1;
    };
    if(!$req3)
    {
      Log3 $name, 2, "$name: Crypt::ECB not found while attempting to use an encrypted token";
      $hash->{STATE} = "Crypt::ECB not found";
      $attr{$name}{disable} = "1";
      return undef;
    }

    my $key = pack("H*","00000000000000000000000000000000");
    my $crypt = Crypt::ECB->new;
    $crypt->padding(0);
    if($hash->{helper}{crypt} ne "Rijndael"){
      Log3 $name, 3, "$name: token decryption using Crypt::Cipher::AES";
      $crypt->cipher('Crypt::Cipher::AES');
    } else {
      Log3 $name, 3, "$name: token decryption using Crypt::Rijndael_PP";
      $crypt->cipher('Crypt::Rijndael_PP');
      $Crypt::Rijndael_PP::DEFAULT_KEYSIZE = 128;
    }
    $crypt->key($key);
    my $e = eval { $key = $crypt->decrypt_hex(substr($a[3],64,32)) };
    if($@)
    {
      Log3 $name, 1, "$name: token key decryption failed\n".$@;
      $hash->{STATE} = "Encryption cipher error";
      $attr{$name}{disable} = "1";
      return undef;
    }
    $key = ($key ^ pack('h*','01010101010101010101010101010101'));
    $crypt->key($key);
    $e = eval { $hash->{helper}{token} = $crypt->decrypt_hex(substr($a[3],0,64)) };
    if($@)
    {
      Log3 $name, 1, "$name: token decryption failed\n".$@;
      $hash->{STATE} = "Encryption cipher error";
      $attr{$name}{disable} = "1";
      return undef;
    }
    if(length($hash->{helper}{token}) == 32) {
      Log3 $name, 2, "$name: encrypted token was decrypted\n".$a[3]." > ".$hash->{helper}{token};
      $hash->{DEF} = $a[2]." ".$hash->{helper}{token};
    } else {
      Log3 $name, 2, "$name: token decryption failed\n".$a[3]." > ".$hash->{helper}{token};
      $hash->{STATE} = "Token decryption failed";
      $attr{$name}{disable} = "1";
    }
  } elsif(length($a[3]) == 16) {
    $hash->{helper}{token} = unpack('H*', $a[3]);
    if(length($hash->{helper}{token}) == 32) {
      Log3 $name, 2, "$name: packed token was unpacked\n".$a[3]." > ".$hash->{helper}{token};
      $hash->{DEF} = $a[2]." ".$hash->{helper}{token};
    } else {
      Log3 $name, 2, "$name: token unpacking failed\n".$a[3]." > ".$hash->{helper}{token};
      $hash->{STATE} = "Token unpacking failed";
      $attr{$name}{disable} = "1";
    }
  } else {
    Log3 $name, 2, "$name: no or incorrect token defined!";
  }

  #$hash->{helper}{token} = $a[3] if(defined($a[3]));
  $attr{$name}{subType} = "VacuumCleaner" if( defined($attr{$name}) && !defined($attr{$name}{subType}) );
  $attr{$name}{stateFormat} = "pm25 µg/m³ / speed rpm / mode" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "pm25 µg/m³ / speed rpm / mode" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "state" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "VacuumCleaner" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "state" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Humidifier" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "power" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EvpHumidifier" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "power" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "mode level%" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "mode level%" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "mode level%" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "mode level%" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "mode level%" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "state" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "power" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "power" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "WaterPurifier" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "power" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Camera" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "method" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "RiceCooker" && !defined($attr{$name}{stateFormat}));
  $attr{$name}{stateFormat} = "power" if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "PowerPlug" && !defined($attr{$name}{stateFormat}));

  XiaomiDevice_ReadZones($hash) if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "VacuumCleaner");

  InternalTimer( gettimeofday() + 10, "XiaomiDevice_Init", $hash);

  return undef;
}

sub XiaomiDevice_Undefine($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  XiaomiDevice_disconnect($hash);
  #RemoveInternalTimer($hash);
  return undef;
}



#####################################
sub XiaomiDevice_Get($@) {
  my ($hash, @a) = @_;
  my $command = $a[1];
  my $parameter = $a[2] if(defined($a[2]));
  my $name = $hash->{NAME};



  my $usage = "Unknown argument $command, choose one of data:noArg settings:noArg device_info:noArg";
  $usage .= " wifi_stats:noArg" if(!defined($hash->{model}) || $hash->{model} ne "zhimi.fan.za4");
  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "VacuumCleaner"){
    $usage = "Unknown argument $command, choose one of data:noArg settings:noArg clean_summary:noArg timer_clean:noArg timer_dnd:noArg log_status:noArg serial_number:noArg wifi_stats:noArg device_info:noArg timezone:noArg";
    $usage .= " map sound:noArg" if(!defined($hash->{model}) || $hash->{model} ne "roborock.vacuum.c1");
  }

  return $usage if $command eq '?';

  if(IsDisabled($name)) {
    return "XiaomiDevice $name is disabled. Aborting...";
  }

  if($command eq 'data')
  {
    XiaomiDevice_GetUpdate($hash);
  }
  elsif($command eq 'settings')
  {
    XiaomiDevice_GetSettings($hash);
  }
  elsif($command eq 'clean_summary')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_clean_summary";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_clean_summary","params":[""]}' );
    return undef;
  }
  elsif($command eq 'clean_record')
  {
    return undef if(!defined($hash->{helper}{dev}));
    return "You have to enter a cleanID" if(!defined($parameter));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_clean_record";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_clean_record","params":['.$parameter.']}' );
    return undef;
  }
  elsif($command eq 'sound')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_current_sound";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_current_sound","params":[""]}' );
    return undef;
  }
  elsif($command eq 'timer_clean')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_timer";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_timer","params":[""]}' );
    return undef;
  }
  elsif($command eq 'timer_dnd')
  {
    XiaomiDevice_GetDnd($hash);
    return undef;
  }
  elsif($command eq 'log_status')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_log_upload_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_log_upload_status","params":[""]}' );
    return undef;
  }
  elsif($command eq 'map')
  {
    return undef if(!defined($hash->{helper}{dev}));
    return "You have to enter a cleanID" if(!defined($parameter));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_map_v1";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_map_v1","params":['.$parameter.']}' );
    return undef;
  }
  elsif($command eq 'serial_number')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_serial_number";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_serial_number","params":[""]}' );
    return undef;
  }
  elsif($command eq 'wifi_stats')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "wifi_stats";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"miIO.wifi_assoc_state","params":[""]}' );
    return undef;
  }
  elsif($command eq 'device_info')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "device_info";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"miIO.info","params":[""]}' );
    return undef;
  }
  elsif($command eq 'timezone')
  {
    return undef if(!defined($hash->{helper}{dev}));
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_timezone";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_timezone","params":[""]}' );
    return undef;
  }
  else
  {
    return $usage;
  }


  return undef;
}

#Methods={
# GetProp:"get_prop",
# GetStatus:"get_status",
# GetMap:"get_map", id
# GetMapAndroid:"get_map_v1", id
# GetMapV2:"get_map_v2", id
# GetCustomMode:"get_custom_mode",
# SetCustomMode:"set_custom_mode",
# GetCleanSummary:"get_clean_summary",
# GetCleanRecord:"get_clean_record", id
# GetCleanRecordMap:"get_clean_record_map", id
# GetCleanRecordMapV2:"get_clean_record_map_v2", id
# GetSupplies:"get_consumable",
# GetTimer:"get_timer",
# SetTimer:"set_timer",
# DelTimer:"del_timer",
# UpdTimer:"upd_timer",
# GetDndTimer:"get_dnd_timer#",
# SetDndTimer:"set_dnd_timer", hh,mm,hh,mm
# CloseDndTimer:"close_dnd_timer",
# AppStart:"app_start",
# AppPause:"app_pause",
# AppSpot:"app_spot",
# AppCharge:"app_charge",
# AppRemoteControlMove:"app_rc_move",
# AppRemoteControlStart:"app_rc_start",
# AppRemoteControlEnd:"app_rc_end",
# ResetSupplies:"reset_consumable",
# TimerStart:"start_clean",
# GetSerialNumber:"get_serial_number",
# FindMe:"find_me",
# EnableLogUpload:"enable_log_upload",
# GetLogUploadStatus:"get_log_upload_status",
# SetSoundPackage:"dnld_install_sound", #   sid,ID default,0
#    url  md5  sid  https://awsbj0.fds.api.xiaomi.com/app/voice-pkg/package/english.pkg
#    {"voice_id":"3","voice_title":"English","voice_sub_title":"Default English Voice","bg_pic":"https:\/\/awsbj0.fds.api.xiaomi.com\/app\/voice-pkg\/pic\/eng_ch.png","voice_pkg_url":"...english.pkg","voice_pkg_md5":"c60ea75cc41e422ade9c82de29b78c36","voice_pre_listen":"https:\/\/awsbj0.fds.api.xiaomi.com\/app\/voice-pkg\/pre_listen\/pre_listen_eng.wav","voice_pri":"13"
# GetSoundPackageProgress:"get_sound_progress",
# GetCurrentSoundPackage:"get_current_sound"},
# LogLevel={None:0,BlackBox:1,Pickup:2,Full:4},
# GetMapRetry="retry",
# SmartHomeApi={
# GetMapUrl:"/home/getmapfileurl",
# CheckVersion:"/home/checkversion",
# DeviceStatus:"/home/device_list"},
#
# start_clean // "enable_push", "0";"enable_timer", "1";"enable_timer_off", "0");"enable_timer_on", "1";"identify", ID;"off_method", BuildConfig.FLAVOR);
# "off_param", "off";"off_time", ?,?;"on_method", "start_clean";"on_param", "on";"on_time", ?,?;
# upd_timer ID // on/off
# del_timer ID
#
#{"method":"get_prop","params":["power","fw_ver","bright","ct","pdo_status","pdo_wt","pdo_bt","kid_mode","lan_ctrl","skey_act","skey_scene_id"]}
#{"method":"cron_get","params":[0]}
#
#S=n.STORAGE_KEY="@RockroboVacuum_Clean_v2"+d.deviceId+":key"
#
#Methods={GetProp:"get_prop",GetStatus:"get_status",GetMap:"get_map",GetMapAndroid:"get_map_v1",GetMapV2:"get_map_v2",GetCustomMode:"get_custom_mode",SetCustomMode:"set_custom_mode",GetCleanSummary:"get_clean_summary",GetCleanRecord:"get_clean_record",GetCleanRecordMap:"get_clean_record_map",GetCleanRecordMapV2:"get_clean_record_map_v2",GetSupplies:"get_consumable",
#GetTimer:"get_timer",SetTimer:"set_timer",DelTimer:"del_timer",UpdTimer:"upd_timer",GetDndTimer:"get_dnd_timer",SetDndTimer:"set_dnd_timer",CloseDndTimer:"close_dnd_timer",AppStart:"app_start",AppPause:"app_pause",AppSpot:"app_spot",AppCharge:"app_charge",AppRemoteControlMove:"app_rc_move",AppRemoteControlStart:"app_rc_start",AppRemoteControlEnd:"app_rc_end",
#ResetSupplies:"reset_consumable",TimerStart:"start_clean",GetSerialNumber:"get_serial_number",FindMe:"find_me",EnableLogUpload:"enable_log_upload",GetLogUploadStatus:"get_log_upload_status",SetSoundPackage:"dnld_install_sound",GetSoundPackageProgress:"get_sound_progress",GetCurrentSoundPackage:"get_current_sound",GetTimezone:"get_timezone",SetTimezone:"set_timezone"},
#_.LogLevel={None:0,BlackBox:1,Pickup:2,Full:4},_.GetMapRetry="retry",_.SmartHomeApi={GetMapUrl:"/home/getmapfileurl",CheckVersion:"/home/checkversion",DeviceStatus:"/home/device_list"},_.CleanMode={38:a.localization_strings_Common_Protocol_0,60:a.localization_strings_Common_Protocol_1,77:a.localization_strings_Common_Protocol_2,90:a.localization_strings_Common_Protocol_3}});
#
#zone {"from":"4","id":1164,"method":"app_zoned_clean","params":[[19500,22700,21750,24250,3],[23150,26050,25150,27500,3],[23650,22950,25150,26250,3],[21700,23000,23750,24150,3],[23700,23050,25200,24200,3]]}
#goto {"from":"4","id":1293,"method":"app_goto_target","params":[21500,25250]}
#save_map
#new status {"id":927,"method":"get_prop","params":["get_status"]}
#{"id":8103,"method":"get_log_upload_status"}
#{"id":8034,"method":"start_edit_map"}
#{"id":8054,"method":"save_map","params":[[1,26353,26920,27314,26042],[0,25375,26490,25884,26490,25884,25860,25375,25860]]}


#####################################
sub XiaomiDevice_Set($$@) {
  #my ( $hash, $name, $cmd, @arg ) = @_;
  my ($hash, $name, @aa) = @_;
  my ($cmd, @arg) = @aa;


  return "XiaomiDevice $name is disabled. Aborting..." if(IsDisabled($name) && $cmd ne '?');


  my $list = "reconnect:noArg wifi_setup";
  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier"){
    $list  .=  " on:noArg off:noArg mode:auto,idle,silent,favorite favorite:slider,0,1,16 preset:noArg save:noArg restore:noArg buzzer:on,off led:bright,dim,off turbo:on,off child_lock:on,off sleep_time sleep_auto:close,single";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H"){
    $list  .=  " on:noArg off:noArg mode:auto,fan,silent,favorite favorite:slider,0,1,14 level:slider,0,1,3 buzzer:on,off led:bright,dim,off child_lock:on,off";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Humidifier"){
    $list  .=  " on:noArg off:noArg mode:idle,silent,medium,high buzzer:on,off led:bright,dim,off child_lock:on,off limit_hum:slider,30,1,80";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EvpHumidifier"){
    $list  .=  " on:noArg off:noArg mode:silent,medium,high,auto buzzer:on,off dry:on,off led:bright,dim,off child_lock:on,off limit_hum:slider,30,1,80";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ"){
    $list  .=  " on:noArg off:noArg mode:silent,medium,high,auto buzzer:on,off led:on,off limit_hum:slider,30,1,80";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan"){
    $list  .=  " on:noArg off:noArg timed_off mode:straight,natural level:slider,0,1,100 angle:30,60,90,120 angle_enable:on,off move:left,right buzzer:on,off led:bright,dim,off child_lock:on,off";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X"){
    $list  .=  " on:noArg off:noArg timed_off mode:straight,natural level:slider,0,1,100 angle:30,60,90,120,140 angle_enable:on,off move:left,right buzzer:on,off led:on,off child_lock:on,off";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C"){
    $list  .=  " on:noArg off:noArg timed_off mode:straight,sleep level:slider,0,1,3 angle_enable:on,off buzzer:on,off led:on,off child_lock:on,off";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1"){
    $list  .=  " on:noArg off:noArg timed_off:0,1,2,3,4,5,6,7,8 mode:straight,natural level:slider,0,1,100 angle:30,60,90,120 angle_enable:on,off tilt:30,60,90 tilt_enable:on,off oscillate_enable:on,off move:left,right,up,down,center,middle,reset buzzer:on,off led:on,off child_lock:on,off";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9"){
    $list  .=  " on:noArg off:noArg timed_off mode:straight,natural,sleep level:slider,0,1,100 angle:30,60,90,120,150 angle_enable:on,off move:left,right buzzer:on,off led:on,off child_lock:on,off";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp"){
    $list .= " on:noArg off:noArg toggle:noArg brightness:slider,0,1,100 timed_off save:noArg";
    $list .= " ct:slider,2700,190,6500" if(defined(ReadingsVal($name,"ct",undef)));
    $list .= " cct:slider,1,1,100" if(defined(ReadingsVal($name,"cct",undef)));
    $list .= " sat:slider,0,1,100" if(defined(ReadingsVal($name,"sat",undef)));
    $list .= " hue:slider,0,1,359" if(defined(ReadingsVal($name,"hue",undef)));
    $list .= " rgb:slider,0,1,16777215" if(defined(ReadingsVal($name,"rgb",undef)));
    $list .= " kid_mode:0,1" if(defined(ReadingsVal($name,"kid_mode",undef)));
    #$list .= " hsv" if(defined(ReadingsVal($name,"hue",undef)));
    #$list .= " snm" if(defined(ReadingsVal($name,"snm",undef)));
    #$list .= " dv" if(defined(ReadingsVal($name,"dv",undef)));
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare"){
    $list .= " on:noArg off:noArg toggle:noArg brightness:slider,0,1,100 timed_off";
    $list .= " eyecare:on,off" if(defined(ReadingsVal($name,"eyecare",undef)));
    $list .= " ambstatus:on,off" if(defined(ReadingsVal($name,"ambstatus",undef)));
    $list .= " notifystatus:on,off" if(defined(ReadingsVal($name,"notifystatus",undef)));
    $list .= " ambvalue:slider,0,1,100" if(defined(ReadingsVal($name,"ambvalue",undef)));
    $list .= " bls:on,off" if(defined(ReadingsVal($name,"bls",undef)));
    #$list .= " scene_num" if(defined(ReadingsVal($name,"scene_num",undef)));
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "WaterPurifier"){
    $list .= " on:noArg off:noArg";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Camera"){
    $list .= " on:noArg off:noArg";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "RiceCooker"){
    $list .= " stop:noArg nowarn:noArg ack:noArg";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "PowerPlug"){
    $list .= " on:noArg off:noArg";
    $list .=  " power_mode:green,normal";
    $list .=  " wifi_led:on,off";
    $list .=  " rt_power:on,off";
    $list .=  " usb_power:on,off";
    $list .=  " power_price";
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "VacuumCleaner"){
    $list  .=  ' start:noArg stop:noArg pause:noArg spot:noArg charge:noArg locate:noArg dnd_enabled:on,off dnd_start dnd_end move remotecontrol:start,stop,forward,left,right reset_consumable:filter,mainbrush,sidebrush,sensors timezone volume:slider,0,1,100 volume_test:noArg';
    $list  .=  ' carpet_mode:on,off';
    $list  .=  ' sleep:noArg wakeup:noArg';

    $list  .=  ' fan_power:slider,1,1,100' if(!defined($hash->{model}) || $hash->{model} eq "rockrobo.vacuum.v1");
    $list  .=  ' cleaning_mode:off,quiet,balanced,turbo,max';
    $list  .=  ',mop' if(!defined($hash->{model}) || ($hash->{model} ne "rockrobo.vacuum.v1" && $hash->{model} ne "rockrobo.vacuum.c1" && $hash->{model} ne "rockrobo.vacuum.m1s"));
    $list  .=  ',auto' if(!defined($hash->{model}) || ($hash->{model} eq "roborock.vacuum.s5e" || $hash->{model} eq "roborock.vacuum.s6" || $hash->{model} eq "roborock.vacuum.t6"));

    if(!defined($hash->{model}) || $hash->{model} ne "roborock.vacuum.c1") {
      if(defined($hash->{helper}{zone_names})) {
        $list  .=  ' zone:'.$hash->{helper}{zone_names}.' resume:noArg';
      } else {
        $list  .=  ' zone resume:noArg';
      }
      if(defined($hash->{helper}{point_names})) {
        $list  .=  ' goto:'.$hash->{helper}{point_names};
      } else {
        $list  .=  ' goto';
      }
    }
    if(!defined($hash->{model}) || ($hash->{model} ne "rockrobo.vacuum.v1" && $hash->{model} ne "rockrobo.vacuum.c1")) { #roborock.vacuum.s5
      if(defined($hash->{helper}{map_names})) {
        $list  .=  ' save_map:reset,'.$hash->{helper}{map_names}.' start_edit_map:noArg end_edit_map:noArg reset_map:noArg use_new_map:noArg use_old_map:noArg get_persist_map:noArg get_fresh_map:noArg';
      } else {
        $list  .=  ' save_map start_edit_map:noArg end_edit_map:noArg reset_map:noArg use_new_map:noArg use_old_map:noArg get_persist_map:noArg get_fresh_map:noArg';
      }
      if(defined(ReadingsVal($name,"lab_status",undef))) {
        $list  .=  ' lab_status:yes,no';
      }
    }
    if(!defined($hash->{model}) || ($hash->{model} ne "roborock.vacuum.v1" && $hash->{model} ne "rockrobo.vacuum.c1")) { #roborock.vacuum.m1s roborock.vacuum.s5e roborock.vacuum.s6 roborock.vacuum.t6
      if(defined($hash->{helper}{segment_names})) {
        $list  .=  ' segment:'.$hash->{helper}{segment_names}.' segment_stop:noArg segment_resume:noArg';
      } else {
        $list  .=  ' segment segment_stop:noArg segment_resume:noArg';
      }
    }
    if(!defined($hash->{model}) || ($hash->{model} eq "roborock.vacuum.s5e")) {
      $list  .=  ' water_box_mode:off,low,medium,high,auto';
    }



    if (defined($hash->{helper}{timers})&&($hash->{helper}{timers}>0))
    {
        for(my $i=1;$i<=$hash->{helper}{timers};$i++)
        {
          $list .= " timer".$i.":on,off,delete";
          $list .= " timer".$i."_time";
          $list .= " timer".$i."_days";
          $list .= " timer".$i."_program:start_clean";
          $list .= " timer".$i."_power:slider,1,1,100";
        }
    }
    $list  .=  " timer";
  }
  else{
    $list  .=  " subType_not_set:noArg";
  }

  if ($cmd eq 'reconnect')
  {
    return XiaomiDevice_connect($hash);
  }
  if ($cmd eq 'preset')
  {
    my @preset = split(" ", AttrVal($name, "preset", "mode auto"));
    $cmd = shift @preset;
    @arg = @preset;
    Log3 $name, 3, "$name: changed preset to $cmd ".join(" ", @arg);
  }
  elsif ($cmd eq 'restore')
  {
    my @preset = split(" ", ReadingsVal($name, "mode_on", "auto"));
    $cmd = "mode";
    @arg = @preset;
    Log3 $name, 3, "$name: restored to $cmd ".join(" ", @arg);
  }
  elsif ($cmd eq 'save')
  {
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp"){
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = 'set_light';

      my $transition = $arg[1];
      $transition = 30 if(!defined($transition) || int($transition < 30));
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_default","params":[""]}' );
      return undef;
    }
    readingsSingleUpdate( $hash, "mode_saved", (ReadingsVal($name,"mode","auto").((ReadingsVal($name,"mode","-") eq "favorite") ? (" ".ReadingsVal($name,"favorite","0")) : "")), 1 );
    return undef;
  }

  if ($cmd eq 'json')
  {
    return undef if(!defined($hash->{helper}{dev}));

    my $json = join(" ", @arg);
    $json =~ /"id":(.*),"method/;
    my $packetid = $1;
    $hash->{helper}{packet}{$packetid} = "json_command";
    Log3 $name, 0, "$name: sending raw json request\n".$json;

    return XiaomiDevice_WriteJSON($hash, $json );
  }

  if ($cmd eq 'remotecontrol')
  {
    if($arg[0] eq "start")
    {
      $hash->{helper}{rc_seq} = 1;
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
        $hash->{helper}{packet}{$packetid} = "app_rc_start";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_rc_start","params":[""]}' );
      return undef;
    }
    elsif($arg[0] eq "stop")
    {
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "app_rc_end";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_rc_end","params":[1]}' );
      $hash->{helper}{rc_seq} = 0;
      return undef;
    }
    elsif($arg[0] eq "forward")
    {
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "app_rc_forward";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_rc_forward","params":[10]}' );
      $hash->{helper}{rc_seq} = 0;
      return undef;
    }
    elsif($arg[0] eq "left")
    {
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "app_rc_left";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_rc_left","params":[10]}' );
      $hash->{helper}{rc_seq} = 0;
      return undef;
    }
    elsif($arg[0] eq "right")
    {
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "app_rc_right";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_rc_right","params":[10]}' );
      $hash->{helper}{rc_seq} = 0;
      return undef;
    }
  }
  elsif ($cmd eq 'move')
  {
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan")
    {
      return "Usage: move [left/right]" if(!defined($arg[0]));
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "move";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_move","params":["'.$arg[0].'"]}' );
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      return "Usage: move [left/right]" if(!defined($arg[0]));
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "move";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"m_roll","params":["'.$arg[0].'"]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      return "Usage: move [left/right/up/down/center/middle/reset]" if(!defined($arg[0]));
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "move";
      if($arg[0] eq 'left' || $arg[0] eq 'right'){
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 5, "piid": 6, "value": "'.$arg[0].'"}]}' );
      }
      elsif($arg[0] eq 'up' || $arg[0] eq 'down'){
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 5, "piid": 7, "value": "'.$arg[0].'"}]}' );
      }
      elsif($arg[0] eq 'center'){
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 5, "piid": 4, "value": true}]}' );
      }
      elsif($arg[0] eq 'middle'){
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 5, "piid": 5, "value": true}]}' );
      }
      else{
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 5, "piid": 9, "value": true}]}' );
      }
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      return "Usage: move [left/right]" if(!defined($arg[0]));
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "move";
      my $cmd_set = $arg[0] eq 'left' ? '2' : $arg[0] eq 'right' ? '2' :'0';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 2, "piid": 10, "value": '.$cmd_set.'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    return "Usage: move [direction -100..100] [velocity 0..100] [time ms]" if(!defined($arg[0]) || !defined($arg[1]));
    if($hash->{helper}{rc_seq} == 0) {
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "app_rc_start";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_rc_start","params":[""]}' );
      $hash->{helper}{rc_seq} = 1;
    }
    my $degrees = int($arg[0]); # -3.1 .. 3.1
    my $velocity = int($arg[1]); # 0 .. 0.2999
    my $time = 1000;
    $time = int($arg[2]) if defined($arg[2]); # 0 .. 10000?
    $degrees = $degrees /-100 * 3.1;
    $degrees = -3.1 if($degrees<-3.1);
    $degrees = 3.1 if($degrees>3.1);
    $velocity = $velocity /100 * 0.2999;
    $time = 0 if($time<0);
    $time = 10000 if($time>10000);
    $degrees = sprintf( "%.17f", $degrees);
    $velocity = sprintf( "%.4f", $velocity);
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_rc_move";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_rc_move","params":[{"duration":'.$time.',"seqnum":'.$hash->{helper}{rc_seq}.',"omega":'.$degrees.',"velocity":'.$velocity.'}]}' );
    $hash->{helper}{rc_seq} = $hash->{helper}{rc_seq}+1;
    return undef;
  }

  if ($cmd eq 'start')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_start";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_start","params":[""]}' );
  }
  elsif ($cmd eq 'stop')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_stop";
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "RiceCooker") {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_func","params":["end02"]}' );
    } else {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_stop","params":[""]}' );
    }
  }
  elsif ($cmd eq 'spot')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_spot";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_spot","params":[""]}' );
  }
  elsif ($cmd eq 'zone')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_zoned_clean";
    my $zone = "[".join("],[", @arg)."]";
    $zone = $hash->{helper}{zones}{$arg[0]} if(defined($hash->{helper}{zones}) && defined($hash->{helper}{zones}{$arg[0]}));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_zoned_clean","params":['.$zone.']}' );
  }
  elsif ($cmd eq 'resume')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_zoned_clean";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"resume_zoned_clean","params":[""]}' );
  }
  elsif ($cmd eq 'goto')
  {
    $arg[0] = $hash->{helper}{points}{$arg[0]} if(defined($hash->{helper}{points}) && defined($hash->{helper}{points}{$arg[0]}));
    $arg[0] =~ s/\[//g;
    $arg[0] =~ s/\]//g;
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_goto_target";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_goto_target","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'pause')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_pause";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_pause","params":[""]}' );
  }
  elsif ($cmd eq 'charge')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_stop";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_stop","params":[""]}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_charge";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_charge","params":[""]}' );
  }
  elsif ($cmd eq 'locate')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "find_me";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"find_me","params":[""]}' );
  }
  elsif ($cmd eq 'cleaning_mode')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_custom_mode";
    if($hash->{model} ne "rockrobo.vacuum.v1") {
      $arg[0] = ($arg[0] eq "off") ? "0" : ($arg[0] eq "quiet") ? "101" : ($arg[0] eq "balanced") ? "102" : ($arg[0] eq "turbo") ? "103" : ($arg[0] eq "max") ? "104" : ($arg[0] eq "mop") ? "105" : ($arg[0] eq "auto") ? "106" : "102";
    } else {
      $arg[0] = ($arg[0] eq "off") ? "0" : ($arg[0] eq "quiet") ? "38" : ($arg[0] eq "balanced") ? "60" : ($arg[0] eq "turbo") ? "77" : ($arg[0] eq "max") ? "90" : ($arg[0] eq "mop") ? "1" : "60";
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_custom_mode","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'fan_power')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_custom_mode";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_custom_mode","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'water_box_mode')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_water_box_custom_mode";
    my $waterboxmode = ($arg[0] eq 'off') ? '200' : ($arg[0] eq 'low') ? '201' : ($arg[0] eq 'medium') ? '202' : ($arg[0] eq 'high') ? '203' : '204';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_water_box_custom_mode","params":['.$waterboxmode.']}' );
  }
  elsif ($cmd eq 'dnd_enabled')
  {
    if($arg[0] eq "on")
    {
      my @timestart = split(":",ReadingsVal( $name, "dnd_start", "22:00" ));
      my @timeend = split(":",ReadingsVal( $name, "dnd_end", "08:00" ));
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
        $hash->{helper}{packet}{$packetid} = "set_dnd_timer";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_dnd_timer","params":['.int($timestart[0]).','.int($timestart[1]).','.int($timeend[0]).','.int($timeend[1]).']}' );
    } else {
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
        $hash->{helper}{packet}{$packetid} = "close_dnd_timer";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"close_dnd_timer","params":[""]}' );
    }
  }
  elsif ($cmd eq 'dnd_start')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_dnd_timer";
    my @timestart = split(":",$arg[0]);
    my @timeend = split(":",ReadingsVal( $name, "dnd_end", "08:00" ));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_dnd_timer","params":['.int($timestart[0]).','.int($timestart[1]).','.int($timeend[0]).','.int($timeend[1]).']}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "close_dnd_timer";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"close_dnd_timer","params":[""]}' ) if(ReadingsVal( $name, "dnd_enabled", "off" ) eq "off");
  }
  elsif ($cmd eq 'dnd_end')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_dnd_timer";
    my @timeend = split(":",$arg[0]);
    my @timestart = split(":",ReadingsVal( $name, "dnd_start", "22:00" ));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_dnd_timer","params":['.int($timestart[0]).','.int($timestart[1]).','.int($timeend[0]).','.int($timeend[1]).']}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "close_dnd_timer";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"close_dnd_timer","params":[""]}' ) if(ReadingsVal( $name, "dnd_enabled", "off" ) eq "off");
  }
  elsif ($cmd eq 'reset_consumable')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "reset_consumable";
    $arg[0] = ($arg[0] eq "filter") ? "filter_work_time" : ($arg[0] eq "sidebrush") ? "side_brush_work_time" : ($arg[0] eq "mainbrush") ? "main_brush_work_time" : "sensor_dirty_time";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"reset_consumable","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'carpet_mode')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_carpet_mode";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_carpet_mode","params":[{"enable":'.(($arg[0] eq "on")?'1':'0').',"current_integral":'.ReadingsVal($name,"carpet_integral","450").',"current_high":'.ReadingsVal($name,"carpet_high","500").',"current_low":'.ReadingsVal($name,"carpet_low","400").',"stall_time":'.ReadingsVal($name,"carpet_stall_time","10").'}]}' );
  }
  elsif ($cmd eq 'volume')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "change_sound_volume";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"change_sound_volume","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'volume_test')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "test_sound_volume";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"test_sound_volume","params":[]}' );
  }
  elsif ($cmd eq 'wakeup')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_wakeup_robot";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_wakeup_robot","params":[]}' );
  }
  elsif ($cmd eq 'sleep')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "app_sleep";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_sleep","params":[]}' );
  }
  elsif ($cmd eq 'save_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "save_map";
    my $map = "[".join("],[", @arg)."]";
    $map = $hash->{helper}{maps}{$arg[0]} if(defined($hash->{helper}{maps}) && defined($hash->{helper}{maps}{$arg[0]}));
    $map = "" if($arg[0] eq "reset");
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"save_map","params":['.$map.']}' );
  }
  elsif ($cmd eq 'start_edit_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "start_edit_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"start_edit_map","params":[]}' );
  }
  elsif ($cmd eq 'end_edit_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "end_edit_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"end_edit_map","params":[]}' );
  }
  elsif ($cmd eq 'reset_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "reset_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"reset_map","params":[]}' );
  }
  elsif ($cmd eq 'use_new_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "use_new_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"use_new_map","params":[]}' );
  }
  elsif ($cmd eq 'use_old_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "use_old_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"use_old_map","params":[]}' );
  }
  elsif ($cmd eq 'get_persist_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_persist_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_persist_map","params":[]}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_persist_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_persist_map_v1","params":[]}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_persist_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_persist_map_v2","params":[]}' );
  }
  elsif ($cmd eq 'get_fresh_map')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_fresh_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_fresh_map","params":[]}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_fresh_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_fresh_map_v1","params":[]}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_fresh_map";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_fresh_map_v2","params":[]}' );
  }
  elsif ($cmd eq 'lab_status')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "lab_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_lab_status","params":['.(($arg[0] eq "yes")?'1':'0').']}' );
  }
  elsif ($cmd eq 'segment')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "clean_segment";
    my $segment = join(",", @arg);
    $segment = $hash->{helper}{segments}{$arg[0]} if(defined($hash->{helper}{segments}) && defined($hash->{helper}{segments}{$arg[0]}));

    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_segment_clean","params":['.$segment.']}' );
  }
  elsif ($cmd eq 'segment_stop')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "clean_segment_stop";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"stop_segment_clean","params":[]}' );
  }
  elsif ($cmd eq 'segment_resume')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "clean_segment_resume";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"resume_segment_clean","params":[]}' );
  }
  elsif ($cmd eq 'timezone')
  {
    my $timezone = join(" ", @arg);
    $timezone = "Europe/Berlin" if(!defined($timezone));
    $timezone =~ s/\//\\\//g;

    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_timezone";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_timezone","params":["'.$timezone.'"]}' );
  }
  elsif ( $cmd =~ /^timer/ )
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_timer";
    my $timerno = 0;
    $timerno = int( substr( $cmd, 5, 1 ) ) + 0 if($cmd ne "timer");
    if($cmd =~ /_time/)
    {
      my @time = split(":",$arg[0]);
      my $daysstring = ReadingsVal($name, "timer".$timerno."_days","all" );
      my $program = ReadingsVal($name, "timer".$timerno."_program","start_clean" );
      my $power = ReadingsVal($name, "timer".$timerno."_power","77" );
      my @singledate = split(" ", $daysstring);
      if(defined($singledate[0]) && defined($singledate[1]) && int($singledate[0])>0 && int($singledate[1])>0)
      {
        $daysstring = $singledate[0]." ".$singledate[1]." *";
      }
      elsif($daysstring ne "all")
      {
        my @days = ();
        push( @days, "0" ) if($daysstring =~ /Su/);
        push( @days, "1" ) if($daysstring =~ /Mo/);
        push( @days, "2" ) if($daysstring =~ /Tu/);
        push( @days, "3" ) if($daysstring =~ /We/);
        push( @days, "4" ) if($daysstring =~ /Th/);
        push( @days, "5" ) if($daysstring =~ /Fr/);
        push( @days, "6" ) if($daysstring =~ /Sa/);
        $daysstring = "* * ".join(",", @days);
      }
      else
      {
        $daysstring = "* * *";
      }
      $hash->{helper}{packet}{$packetid} = "set_timer";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_timer","params":[["'.int($hash->{helper}{"timer".$timerno}).'",["'.$time[1].' '.$time[0].' '.$daysstring.'",["'.$program.'",'.$power.']]]]}' );
    }
    elsif($cmd =~ /_days/)
    {
      my @time = split(":",ReadingsVal($name, "timer".$timerno."_time","12:00" ));
      my $daysstring = join(" ", @arg);
      my $program = ReadingsVal($name, "timer".$timerno."_program","start_clean" );
      my $power = ReadingsVal($name, "timer".$timerno."_power","77" );
      my @singledate = split(" ", $daysstring);
      if(defined($singledate[0]) && defined($singledate[1]) && int($singledate[0])>0 && int($singledate[1])>0)
      {
        $daysstring = $singledate[0]." ".$singledate[1]." *";
      }
      elsif($daysstring ne "all")
      {
        my @days = ();
        push( @days, "0" ) if($daysstring =~ /Su/);
        push( @days, "1" ) if($daysstring =~ /Mo/);
        push( @days, "2" ) if($daysstring =~ /Tu/);
        push( @days, "3" ) if($daysstring =~ /We/);
        push( @days, "4" ) if($daysstring =~ /Th/);
        push( @days, "5" ) if($daysstring =~ /Fr/);
        push( @days, "6" ) if($daysstring =~ /Sa/);
        $daysstring = "* * ".join(",", @days);
      }
      else
      {
        $daysstring = "* * *";
      }
      $hash->{helper}{packet}{$packetid} = "set_timer";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_timer","params":[["'.int($hash->{helper}{"timer".$timerno}).'",["'.$time[1].' '.$time[0].' '.$daysstring.'",["'.$program.'",'.$power.']]]]}' );
    }
    elsif($cmd =~ /_program/)
    {
      my @time = split(":",ReadingsVal($name, "timer".$timerno."_time","12:00" ));
      my $daysstring = ReadingsVal($name, "timer".$timerno."_days","all" );
      my $program = $arg[0];
      my $power = ReadingsVal($name, "timer".$timerno."_power","77" );
      my @singledate = split(" ", $daysstring);
      if(defined($singledate[0]) && defined($singledate[1]) && int($singledate[0])>0 && int($singledate[1])>0)
      {
        $daysstring = $singledate[0]." ".$singledate[1]." *";
      }
      elsif($daysstring ne "all")
      {
        my @days = ();
        push( @days, "0" ) if($daysstring =~ /Su/);
        push( @days, "1" ) if($daysstring =~ /Mo/);
        push( @days, "2" ) if($daysstring =~ /Tu/);
        push( @days, "3" ) if($daysstring =~ /We/);
        push( @days, "4" ) if($daysstring =~ /Th/);
        push( @days, "5" ) if($daysstring =~ /Fr/);
        push( @days, "6" ) if($daysstring =~ /Sa/);
        $daysstring = "* * ".join(",", @days);
      }
      else
      {
        $daysstring = "* * *";
      }
      $hash->{helper}{packet}{$packetid} = "set_timer";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_timer","params":[["'.int($hash->{helper}{"timer".$timerno}).'",["'.$time[1].' '.$time[0].' '.$daysstring.'",["'.$program.'",'.$power.']]]]}' );
    }
    elsif($cmd =~ /_power/)
    {
      my @time = split(":",ReadingsVal($name, "timer".$timerno."_time","12:00" ));
      my $daysstring = ReadingsVal($name, "timer".$timerno."_days","all" );
      my $program = ReadingsVal($name, "timer".$timerno."_program","start_clean" );
      my $power = $arg[0];
      my @singledate = split(" ", $daysstring);
      if(defined($singledate[0]) && defined($singledate[1]) && int($singledate[0])>0 && int($singledate[1])>0)
      {
        $daysstring = $singledate[0]." ".$singledate[1]." *";
      }
      elsif($daysstring ne "all")
      {
        my @days = ();
        push( @days, "0" ) if($daysstring =~ /Su/);
        push( @days, "1" ) if($daysstring =~ /Mo/);
        push( @days, "2" ) if($daysstring =~ /Tu/);
        push( @days, "3" ) if($daysstring =~ /We/);
        push( @days, "4" ) if($daysstring =~ /Th/);
        push( @days, "5" ) if($daysstring =~ /Fr/);
        push( @days, "6" ) if($daysstring =~ /Sa/);
        $daysstring = "* * ".join(",", @days);
      }
      else
      {
        $daysstring = "* * *";
      }
      $hash->{helper}{packet}{$packetid} = "set_timer";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_timer","params":[["'.int($hash->{helper}{"timer".$timerno}).'",["'.$time[1].' '.$time[0].' '.$daysstring.'",["'.$program.'",'.$power.']]]]}' );
    }
    elsif($timerno > 0)
    {
      if($arg[0] eq "delete")
      {
        $hash->{helper}{packet}{$packetid} = "del_timer";
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"del_timer","params":["'.int($hash->{helper}{"timer".$timerno}).'"]}' );
      } else {
        $hash->{helper}{packet}{$packetid} = "upd_timer";
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"upd_timer","params":["'.int($hash->{helper}{"timer".$timerno}).'","'.$arg[0].'"]}' );
      }
    }
    elsif($cmd eq "timer")
    {
      my @time = split(":",$arg[0]);
      my $daysstring = "all";
      $daysstring = $arg[1] if(defined($arg[1]));
      $daysstring .= " ".$arg[2] if(defined($arg[2]));
      $daysstring .= " ".$arg[3] if(defined($arg[3]));
      $daysstring .= " ".$arg[4] if(defined($arg[4]));
      $daysstring .= " ".$arg[5] if(defined($arg[5]));
      $daysstring .= " ".$arg[6] if(defined($arg[6]));
      $daysstring .= " ".$arg[7] if(defined($arg[7]));

      my @singledate = split(" ", $daysstring);
      if(defined($singledate[0]) && defined($singledate[1]) && int($singledate[0])>0 && int($singledate[1])>0)
      {
        $daysstring = $singledate[0]." ".$singledate[1]." *";
      }
      elsif($daysstring ne "all")
      {
        my @days = ();
        push( @days, "0" ) if($daysstring =~ /Su/);
        push( @days, "1" ) if($daysstring =~ /Mo/);
        push( @days, "2" ) if($daysstring =~ /Tu/);
        push( @days, "3" ) if($daysstring =~ /We/);
        push( @days, "4" ) if($daysstring =~ /Th/);
        push( @days, "5" ) if($daysstring =~ /Fr/);
        push( @days, "6" ) if($daysstring =~ /Sa/);
        $daysstring = "* * ".join(",", @days);
      }
      else
      {
        $daysstring = "* * *";
      }
      $hash->{helper}{packet}{$packetid} = "set_timer";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_timer","params":[["'.int(gettimeofday()).'000",["'.$time[1].' '.$time[0].' '.$daysstring.'",["start_clean",""]]]]}' );
    }
  }
  elsif ($cmd eq 'on' || $cmd eq 'off')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = ($cmd eq 'on') ? 'power_on' : 'power_off';

    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp")
    {
      my $transition = $arg[0];
      $transition = 10 if(!defined($transition));
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_power","params":["'.$cmd.'","smooth",'.$transition.']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
    {
      my $cmd_set = $cmd eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 2, "value": '.$cmd_set.'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"Set_OnOff","params":['.($cmd eq "on" ? '1' : '0').']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_power","params":['.($cmd eq "on" ? 'true' : 'false').']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
    {
      my $cmd_set = $cmd eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 1, "value": '.$cmd_set.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_set = $cmd eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 1, "value": '.$cmd_set.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      my $cmd_set = $cmd eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 1, "value": '.$cmd_set.'}]}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_power","params":["'.$cmd.'"]}' );
    InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
  }
  elsif ($cmd eq 'toggle')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_toggle';

    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"toggle","params":[""]}' );
    #InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetUpdate", $hash);
  }
  elsif ($cmd eq 'brightness')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_light';

    my $transition = $arg[1];
    $transition = 30 if(!defined($transition) || int($transition < 30));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_bright","params":['.$arg[0].',"smooth",'.$transition.']}' );
  }
  elsif ($cmd eq 'ct')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_light';

    my $transition = $arg[1];
    $transition = 30 if(!defined($transition) || int($transition < 30));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_ct_abx","params":['.$arg[0].',"smooth",'.$transition.']}' );
  }
  elsif ($cmd eq 'sat')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_light';

    my $transition = $arg[1];
    $transition = 30 if(!defined($transition) || int($transition < 30));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_hsv","params":['.ReadingsVal($name,"hue",0).','.$arg[0].',"smooth",'.$transition.']}' );
  }
  elsif ($cmd eq 'hue')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_light';

    my $transition = $arg[1];
    $transition = 30 if(!defined($transition) || int($transition < 30));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_hsv","params":['.$arg[0].','.ReadingsVal($name,"sat",100).',"smooth",'.$transition.']}' );
  }
  elsif ($cmd eq 'cct')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_light';

    my $transition = $arg[1];
    $transition = 30 if(!defined($transition) || int($transition < 30));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_cct","params":['.$arg[0].',"smooth",'.$transition.']}' );
  }
  elsif ($cmd eq 'rgb')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_light';

    my $transition = $arg[1];
    $transition = 30 if(!defined($transition) || int($transition < 30));
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_rgb","params":['.$arg[0].',"smooth",'.$transition.']}' );
  }
  elsif ($cmd eq 'eyecare')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'set_light';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_eyecare","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'ambstatus')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'set_light';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"enable_amb","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'notifystatus')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'set_light';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_notifyuser","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'ambvalue')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'set_light';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_amb_bright","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'bls')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'set_light';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"enable_bl","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'scene_num')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'set_light';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_user_scene","params":['.$arg[0].']}' );
  }

  elsif ($cmd eq 'limit_hum')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = 'set_limit_hum';

    my $limit_hum = $arg[0];
    $limit_hum = 50 if(!defined($limit_hum) || int($limit_hum < 30) || int($limit_hum > 80));

    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"Set_HumiValue","params":['.$limit_hum.']}' );
      return undef;
    }

    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_limit_hum","params":['.$limit_hum.']}' );
  }
  elsif ($cmd eq 'mode')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan")
    {
      my $level = ReadingsVal($name, "level", 25);
      $level = $arg[1] if(defined($arg[1]));
      $level = 1 if($level < 1);
      my $mode = ($arg[0] eq "natural")?"natural":"speed";
      $hash->{helper}{packet}{$packetid} = 'mode_'.$mode;
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_'.$mode.'_level","params":['.$level.']}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      my $mode = ($arg[0] eq "natural")?"natural":"speed";
      $hash->{helper}{packet}{$packetid} = 'mode_'.$mode;
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_mode","params":["'.(($arg[0] eq "natural")?'nature':'normal').'"]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
      return undef;
    }


    $hash->{helper}{packet}{$packetid} = ($arg[0] eq 'idle') ? 'mode_idle' : ($arg[0] eq 'auto') ? 'mode_auto' : ($arg[0] eq 'silent') ? 'mode_silent' : ($arg[0] eq 'medium') ? 'mode_medium' : ($arg[0] eq 'high') ? 'mode_high' : 'mode_favorite';

    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
    {
      my $cmd_set = $arg[0] eq 'auto' ? '0' : $arg[0] eq 'silent' ? '1' : $arg[0] eq 'favorite' ? '2' : '3';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 2, "piid": 5, "value": '.$cmd_set.'}]}' );
      return undef;
    }

    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Humidifier")
    {
      if($arg[0] eq "idle"){
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_power","params":["off"]}' );
        InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
        return undef;
      }
    }

    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
    {
      my $cmd_set = $arg[0] eq 'silent' ? '1' : $arg[0] eq 'medium' ? '2' : $arg[0] eq 'high' ? '3' : '4';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"Set_HumidifierGears","params":['.$cmd_set.']}' );
      return undef;
    }

    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
    {
      my $cmd_set = $arg[0] eq 'straight' ? '0' : '1';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 2, "piid": 7, "value": '.$cmd_set.'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_set = $arg[0] eq 'straight' ? '1' : '0';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 2, "piid": 7, "value": '.$cmd_set.'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      my $cmd_set = $arg[0] eq 'straight' ? '0' : $arg[0] eq 'natural' ? '1' :'2';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "mode", "siid": 2, "piid": 4, "value": '.$cmd_set.'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }

    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_mode","params":["'.$arg[0].'"]}' );
    if($arg[0] eq "favorite" && defined($arg[1])) {
      my $level = int($arg[1]);
      $level = 0 if($level < 0);
      $level = 16 if($level > 16);
      $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
        $hash->{helper}{packet}{$packetid} = "set_level_favorite";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_level_favorite","params":['.$arg[1].']}' );
    }
    InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
  }
  elsif ($cmd eq 'dry')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = ($arg[0] eq "on") ? "dry_on" : "dry_off";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_dry","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'favorite')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
    {
      my $cmd_value = $arg[0];
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "favorite_level", "siid": 10, "piid": 10, "value": '.$cmd_value.'}]}' );
      InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash);
      return undef;
    }
    $arg[1] = 0 if !defined($arg[1]);
    my $level = int($arg[1]);
    $level = 0 if($level < 0);
    $level = 16 if($level > 16);
    $hash->{helper}{packet}{$packetid} = "set_level_favorite";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_level_favorite","params":['.$arg[0].']}' );
    InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
  }
  elsif ($cmd eq 'angle')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_angle";
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_angle","params":['.$arg[0].']}' );
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "angle", "siid": 2, "piid": 5, "value": '.$arg[0].'}]}' );
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "angle", "siid": 2, "piid": 6, "value": '.$arg[0].'}]}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_angle","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'angle_enable')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_angle_enable";
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_roll","params":['.($arg[0] eq "on" ? "true" : "false").']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "angle_enable", "siid": 2, "piid": 3, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "angle_enable", "siid": 2, "piid": 3, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "angle_enable", "siid": 2, "piid": 5, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_angle_enable","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'tilt')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_tilt";
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "tilt", "siid": 2, "piid": 6, "value": '.$arg[0].'}]}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_tilt","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'tilt_enable')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_tilt_enable";
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "tilt_enable", "siid": 2, "piid": 4, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_tilt_enable","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'oscillate_enable')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_oscillate_enable";
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "oscillate_enable", "siid": 5, "piid": 8, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_oscillate_enable","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'level')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_level";
    if(int($arg[0])<1)
    {
      if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 2, "value": false}]}' );
      }
      elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_power","params":[false]}' );
      }
      elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 1, "value": false}]}' );
      }
      elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 1, "value": false}]}' );
      }
      elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "power", "siid": 2, "piid": 1, "value": false}]}' );
      }
      else
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_power","params":["off"]}' );
      }
    } else {
      if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
      {
        my $cmd_value = $arg[0];
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "level", "siid": 2, "piid": 4, "value": '.$cmd_value.'}]}' );
        InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash);
        return undef;
      }
      elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_speed","params":['.$arg[0].']}' );
      }
      elsif (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
      {
        my $cmd_value = $arg[0] eq 'low' ? '1' : $arg[0] eq 'medium' ? '2' : $arg[0] eq 'high' ? '3' : $arg[0];
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "fan_level", "siid": 2, "piid": 2, "value": '.$cmd_value.'}]}' );
        return undef;
      }
      elsif (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "level", "siid": 5, "piid": 10, "value": '.$arg[0].'}]}' );
        return undef;
      }
      elsif (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
      {
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "level", "siid": 2, "piid": 11, "value": '.$arg[0].'}]}' );
        return undef;
      }
      else {
        my $mode = (ReadingsVal($name, "mode", "natural") eq "natural")?"natural":"speed";
        XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_'.$mode.'_level","params":['.$arg[0].']}' );
      }
    }
    InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSpeed", $hash);
  }
  elsif ($cmd eq 'timed_off')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_poweroff_time";

    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"start_cf","params":[0,2,"'.($arg[0]*1000).',7,0,0"]}' );
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"delay_off","params":['.$arg[0].']}' );
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_t_off","params":['.$arg[0].']}' );
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "timed_off", "siid": 2, "piid": 10, "value": '.$arg[0].'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "timed_off", "siid": 5, "piid": 2, "value": '.$arg[0].'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "timed_off", "siid": 2, "piid": 8, "value": '.$arg[0].'}]}' );
      InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_poweroff_time","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'buzzer')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = ($arg[0] eq "on") ? 'buzzer_on' : 'buzzer_off';

    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "buzzer", "siid": 5, "piid": 1, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"SetTipSound_Status","params":['.($arg[0] eq "off" ? '0' : '1' ).']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_sound","params":['.($arg[0] eq "off" ? 'false' : 'true' ).']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "buzzer", "siid": 2, "piid": 11, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "buzzer", "siid": 2, "piid": 11, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "buzzer", "siid": 2, "piid": 7, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if(defined($hash->{model}) && $hash->{model} eq "zhimi.fan.za4")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_buzzer","params":['.($arg[0] eq "off" ? '0' : '2' ).']}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_buzzer","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'led')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = ($arg[0] eq "on") ? 'led_on' : ($arg[0] eq "bright") ? 'led_bright' : ($arg[0] eq "dim") ? 'led_dim' : 'led_off';

    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
    {
      my $cmd_value = $arg[0] eq 'on' ? '0' : $arg[0] eq 'bright' ? '0' : $arg[0] eq 'dim' ? '1' : '2';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "led_brightness", "siid": 6, "piid": 1, "value": '.$cmd_value.'}]}' );
      #InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EvpHumidifier")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_led_b","params":["'.($arg[0] eq "bright" ? '0' : $arg[0] eq "dim" ? '1' : '2' ).'"]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"SetLedState","params":['.($arg[0] eq "off" ? '0' : '1' ).']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_light","params":['.($arg[0] eq "off" ? 'false' : 'true' ).']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
    {
      my $cmd_value = $arg[0] eq 'on' ? 'true' : $arg[0] eq 'bright' ? 'true' : $arg[0] eq 'dim' ? 'false' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "led_brightness", "siid": 2, "piid": 12, "value": '.$cmd_value.'}]}' );
      #InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_value = $arg[0] eq 'on' ? '1' : $arg[0] eq 'bright' ? '1' : $arg[0] eq 'dim' ? '0' : '0';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "led_brightness", "siid": 2, "piid": 10, "value": '.$cmd_value.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      my $cmd_value = $arg[0] eq 'on' ? 'true' : $arg[0] eq 'bright' ? 'true' : $arg[0] eq 'dim' ? 'false' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "led_brightness", "siid": 2, "piid": 9, "value": '.$cmd_value.'}]}' );
      #InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetSettings", $hash);
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_led_b","params":['.($arg[0] eq "bright" ? '0' : $arg[0] eq "dim" ? '1' : '2' ).']}' );
  }

  elsif ($cmd eq 'turbo')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = ($arg[0] eq "on") ? 'turbo_on' : 'turbo_off';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_app_extra","params":['.($arg[0] eq "on" ? '1' : '0').']}' );
  }
  elsif ($cmd eq 'child_lock')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = ($arg[0] eq "on") ? 'child_lock_on' : 'child_lock_off';

    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "child_lock", "siid": 7, "piid": 1, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"s_lock","params":['.($arg[0] eq "off" ? 'false' : 'true' ).']}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "child_lock", "siid": 3, "piid": 1, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "child_lock", "siid": 6, "piid": 1, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    if (defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
    {
      my $cmd_boolean = $arg[0] eq 'on' ? 'true' : 'false';
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_properties","params":[{"did": "child_lock", "siid": 3, "piid": 1, "value": '.$cmd_boolean.'}]}' );
      return undef;
    }
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_child_lock","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'kid_mode')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'setting';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_ps","params":["cfg_kidmode","'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'lan_ctrl')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'setting';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_ps","params":["cfg_lan_ctrl","'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'sleep_time')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "set_sleep_time";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_sleep_time","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'sleep_auto')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = ($arg[0] eq "single") ? 'sleep_single' : 'sleep_close';
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_act_sleep","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'wifi_setup')
  {
    return "WiFi configuration requires SSID and PASSWD as parameters, UID is required in initial setup for MiHome app use.\nset devicename wifi_setup <SSID> <PASSWD> [<UID>]" if(!defined($arg[0]) || !defined($arg[1]));

    my @t = localtime(time);
    my $gmt_offset_in_seconds = timegm(@t) - timelocal(@t);

    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;

    $hash->{helper}{packet}{$packetid} = 'wifi_setup';
    if(defined($arg[2]))
    {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"miIO.config_router","params":{"tz":"Europe\/Berlin","ssid":"'.$arg[0].'","uid":'.$arg[2].',"gmt_offset":'.$gmt_offset_in_seconds.',"passwd":"'.$arg[1].'"}}' );
      return "WiFi configuration initialized for MiHome app use.\n\nSSID: ".$arg[0]."\nPassword: ".$arg[1]."\nXiaomi User ID: ".$arg[2];
    } else {
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"miIO.config_router","params":{"tz":"Europe\/Berlin","ssid":"'.$arg[0].'","gmt_offset":'.$gmt_offset_in_seconds.',"passwd":"'.$arg[1].'"}}' );
      return "WiFi configuration updated.\n\nSSID: ".$arg[0]."\nPassword: ".$arg[1];
    }
  }
  elsif ($cmd eq 'nowarn')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "nowarn";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_func","params":["nowarn"]}' );
  }
  elsif ($cmd eq 'ack')
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "ack";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_func","params":["ack"]}' );
  }
  elsif ($cmd eq 'power_mode')#green,normal
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "power_mode";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_power_mode","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'power_price')#1..999
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "power_price";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_power_price","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'wifi_led')#on,off
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "wifi_led";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_wifi_led","params":["'.$arg[0].'"]}' );
  }
  elsif ($cmd eq 'rt_power')#on,off
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "rt_power";
    $arg[0] = ($arg[0] eq "on") ? 1 : 0;
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"set_rt_power","params":['.$arg[0].']}' );
  }
  elsif ($cmd eq 'usb_power')#on,off
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "usb_power";
    $arg[0] = ($arg[0] eq "on") ? "set_usb_on" : "set_usb_off";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"'.$arg[0].'","params":[]}' );
  }
  else
  {
    #return SetExtensions($hash, $list, $name, @aa) if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Test");
    return "Unknown argument $cmd, choose one of $list";
  }
  return undef;
}


sub XiaomiDevice_Init($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(IsDisabled($name)) {
    Log3 ($name, 2, "XiaomiDevice $name is disabled, initialization cancelled.");
    return undef;
  }

  $attr{$name}{subType} = "VacuumCleaner" if( defined($attr{$name}) && !defined($attr{$name}{subType}) );

  XiaomiDevice_connect($hash);


  return undef;
}


sub XiaomiDevice_ReadZones($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!defined($attr{$name}) || !defined($attr{$name}{subType}) || $attr{$name}{subType} ne "VacuumCleaner") {
    delete $hash->{helper}{zones};
    delete $hash->{helper}{zone_names};
    delete $hash->{helper}{points};
    delete $hash->{helper}{point_names};
    delete $hash->{helper}{maps};
    delete $hash->{helper}{map_names};
    delete $hash->{helper}{segments};
    delete $hash->{helper}{segment_names};
    return undef;
  }

  if(defined($attr{$name}) && defined($attr{$name}{zone_names})) {
    my @definitionnames;
    my @definitions = split(" ",$attr{$name}{zone_names});
    foreach my $singledefinition (@definitions) {
      my @definitionparts = split(":",$singledefinition);
      push(@definitionnames,$definitionparts[0]);
      $hash->{helper}{zones}{$definitionparts[0]} = $definitionparts[1];
    }
    $hash->{helper}{zone_names} = join(',',@definitionnames);
  } else {
    delete $hash->{helper}{zones};
    delete $hash->{helper}{zone_names};
  }

  if(defined($attr{$name}) && defined($attr{$name}{point_names})) {
    my @definitionnames;
    my @definitions = split(" ",$attr{$name}{point_names});
    foreach my $singledefinition (@definitions) {
      my @definitionparts = split(":",$singledefinition);
      push(@definitionnames,$definitionparts[0]);
      $hash->{helper}{points}{$definitionparts[0]} = $definitionparts[1];
    }
    $hash->{helper}{point_names} = join(',',@definitionnames);
  } else {
    delete $hash->{helper}{points};
    delete $hash->{helper}{point_names};
  }

  if(defined($attr{$name}) && defined($attr{$name}{map_names})) {
    my @definitionnames;
    my @definitions = split(" ",$attr{$name}{map_names});
    foreach my $singledefinition (@definitions) {
      my @definitionparts = split(":",$singledefinition);
      push(@definitionnames,$definitionparts[0]);
      $hash->{helper}{maps}{$definitionparts[0]} = $definitionparts[1];
    }
    $hash->{helper}{map_names} = join(',',@definitionnames);
  } else {
    delete $hash->{helper}{maps};
    delete $hash->{helper}{map_names};
  }

  if(defined($attr{$name}) && defined($attr{$name}{segment_names})) {
    my @definitionnames;
    my @definitions = split(" ",$attr{$name}{segment_names});
    foreach my $singledefinition (@definitions) {
      my @definitionparts = split(":",$singledefinition);
      push(@definitionnames,$definitionparts[0]);
      $hash->{helper}{segments}{$definitionparts[0]} = $definitionparts[1];
    }
    $hash->{helper}{segment_names} = join(',',@definitionnames);
  } else {
    delete $hash->{helper}{segments};
    delete $hash->{helper}{segment_names};
  }

  return undef;
}



#####################################
sub XiaomiDevice_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "XiaomiDevice_GetUpdate");
  my $timerinterval = AttrVal($name,"intervalData",300);
  if(defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "VacuumCleaner")
  {
    my $currentstate = ReadingsVal($name,"state","-");
    if($currentstate eq "Cleaning" || $currentstate eq "Spot cleaning" || $currentstate eq "Zoned Clean" || $currentstate eq "Segment Clean" || $currentstate eq "Goto")
    {
      $timerinterval = 90 if($timerinterval > 90);
    }
    elsif($currentstate eq "Returning to base")
    {
      $timerinterval = 120 if($timerinterval > 120);
    }
    elsif($currentstate eq "Remote control" || $currentstate eq "Manual mode")
    {
      $timerinterval = 240 if($timerinterval > 240);
    }
  }
  InternalTimer( gettimeofday() + $timerinterval, "XiaomiDevice_GetUpdate", $hash);

  return undef if(!defined($hash->{helper}{dev}));

  my $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "VacuumCleaner")
  {
    $hash->{helper}{packet}{$packetid} = "get_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["get_status"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier")
  {
    $hash->{helper}{packet}{$packetid} = "air_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","motor1_speed","temp_dec","humidity","aqi","average_aqi","favorite_level","use_time","purify_volume","filter1_life","f1_hour_used","f1_hour","button_pressed","motor2_speed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
  {
    $hash->{helper}{packet}{$packetid} = "air_data_3H";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 2}, {"did": "level", "siid": 2, "piid": 4}, {"did": "mode", "siid": 2, "piid": 5}, {"did": "humidity", "siid": 3, "piid": 7}, {"did": "temperature", "siid": 3, "piid": 8}, {"did": "aqi", "siid": 3, "piid": 6}, {"did": "filter_life_remaining", "siid": 4, "piid": 3}, {"did": "purify_volume", "siid": 13, "piid": 1}, {"did": "filter_hours_used", "siid": 4, "piid": 5},  {"did": "favorite_level", "siid": 10, "piid": 10}, {"did": "favorite_rpm", "siid": 10, "piid": 7},{"did": "motor_speed", "siid": 10, "piid": 8}, {"did": "use_time", "siid": 12, "piid": 1},{"did": "average_aqi", "siid": 13, "piid": 2}]}');
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Humidifier")
  {
    $hash->{helper}{packet}{$packetid} = "hum_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","temp_dec","humidity","trans_level","speed","depth","temperature","use_time","button_pressed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EvpHumidifier")
  {
    $hash->{helper}{packet}{$packetid} = "hum_data_evp";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","humidity","speed","depth","temperature","use_time"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
  {
    $hash->{helper}{packet}{$packetid} = "hum_data_mjjsq";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["Humidifier_Gear","Humidity_Value","HumiSet_Value","Led_State","OnOff_State","TemperatureValue","TipSound_State","waterstatus","watertankstatus"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["angle","angle_enable","power","bat_charge","battery","speed_level","natural_level","buzzer","led_b","poweroff_time","ac_power","child_lock","temp_dec","humidity","speed","button_pressed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data_1x";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","speed","roll_enable","roll_angle","time_off","light","beep_sound","child_lock"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data_1C";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 2, "piid": 2}, {"did": "mode", "siid": 2, "piid": 7}, {"did": "led", "siid": 2, "piid": 12}, {"did": "buzzer", "siid": 2, "piid": 11}, {"did": "angle_enable", "siid": 2, "piid": 3}, {"did": "child_lock", "siid": 3, "piid": 1}, {"did": "timed_off", "siid": 2, "piid": 10}]}');
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data_FA1";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 5, "piid": 10}, {"did": "mode", "siid": 2, "piid": 7}, {"did": "led", "siid": 2, "piid": 10}, {"did": "buzzer", "siid": 2, "piid": 11}, {"did": "angle_enable", "siid": 2, "piid": 3}, {"did": "tilt_enable", "siid": 2, "piid": 4}, {"did": "child_lock", "siid": 6, "piid": 1}, {"did": "timed_off", "siid": 5, "piid": 2}, {"did": "angle", "siid": 2, "piid": 5}, {"did": "tilt", "siid": 2, "piid": 6}]}');
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data_P9";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 2, "piid": 11}, {"did": "mode", "siid": 2, "piid": 4}, {"did": "led", "siid": 2, "piid": 12}, {"did": "buzzer", "siid": 2, "piid": 7}, {"did": "angle_enable", "siid": 2, "piid": 5}, {"did": "child_lock", "siid": 3, "piid": 1}, {"did": "timed_off", "siid": 2, "piid": 8}, {"did": "angle", "siid": 2, "piid": 6}]}');
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp")
  {
    $hash->{helper}{packet}{$packetid} = "lamp_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","bright","cct","snm","dv","ct","color_mode","delayoff","flowing","flow_params","name","rgb","hue","sat","ambstatus","ambvalue","eyecare","bls","dvalue","kid_mode","skey_act","skey_scene_id","lan_ctrl"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare")
  {
    $hash->{helper}{packet}{$packetid} = "lamp_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","bright","scene_num","notifystatus","ambstatus","ambvalue","eyecare","bls","dvalue"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "WaterPurifier")
  {
    $hash->{helper}{packet}{$packetid} = "water_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","tds_out","filter1_life","filter1_state","filter_life","filter_state","life","state","level","volume","filter","usage","temperature","uv_life","uv_state","elecval_state","button_pressed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Camera")
  {
    $hash->{helper}{packet}{$packetid} = "camera_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_power","params":[]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "RiceCooker")
  {
    $hash->{helper}{packet}{$packetid} = "ricecooker_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["func", "menu", "stage", "temp", "t_func", "t_precook", "t_cook", "setting", "delay", "version","button_pressed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "PowerPlug")
  {
    $hash->{helper}{packet}{$packetid} = "powerplug_data";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power", "temperature", "current", "mode", "power_consume_rate", "wifi_led", "power_price", "voltage", "power_factor", "elec_leakage", "usb_power", "load_power", "usb_on"]}' );
    $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packet}{$packetid} = "powerplug_power";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_power","params":[]}' );
    $hash->{helper}{packetid} = $packetid+1;
  }
  return undef;
}

#####################################
sub XiaomiDevice_GetSettings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "XiaomiDevice_GetSettings");
  InternalTimer( gettimeofday() + AttrVal($name,"intervalSettings",3600), "XiaomiDevice_GetSettings", $hash);

  return undef if(!defined($hash->{helper}{dev}));

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "air_settings";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["buzzer","led_b","child_lock","app_extra","act_sleep","sleep_time","volume","rfid_product_id","rfid_tag"]}' );
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "air_settings_3H";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "led", "siid": 6, "piid": 6},{"did": "buzzer", "siid": 5, "piid": 1}, {"did": "buzzer_volume", "siid": 5, "piid": 2},{"did": "led_brightness", "siid": 6, "piid": 1},{"did": "child_lock", "siid": 7, "piid": 1}, {"did": "app_extra", "siid": 15, "piid": 1}, {"did": "filter_rfid_product_id", "siid": 14, "piid": 3}, {"did": "filter_rfid_tag", "siid": 14, "piid": 1}]}');
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Humidifier")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "hum_settings";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["buzzer","led_b","child_lock","limit_hum","dry"]}' );
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EvpHumidifier")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "hum_settings_evp";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["buzzer","led","child_lock","limit_hum","dry"]}' );
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "hum_settings_mjjsq";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["HumiSet_Value","Led_State","TipSound_State"]}' );
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "fan_data";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["angle","angle_enable","power","bat_charge","battery","speed_level","natural_level","buzzer","led_b","poweroff_time","ac_power","child_lock","temp_dec","humidity","speed","button_pressed"]}' );
  }
  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "fan_data_1x";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","speed","roll_enable","roll_angle","time_off","light","beep_sound","child_lock"]}' );
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "fan_data_1C";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 2, "piid": 2}, {"did": "mode", "siid": 2, "piid": 7}, {"did": "led", "siid": 2, "piid": 12}, {"did": "buzzer", "siid": 2, "piid": 11}, {"did": "angle_enable", "siid": 2, "piid": 3}, {"did": "child_lock", "siid": 3, "piid": 1}, {"did": "timed_off", "siid": 2, "piid": 10}]}');
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "fan_data_FA1";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 5, "piid": 10}, {"did": "mode", "siid": 2, "piid": 7}, {"did": "led", "siid": 2, "piid": 10}, {"did": "buzzer", "siid": 2, "piid": 11}, {"did": "angle_enable", "siid": 2, "piid": 3}, {"did": "tilt_enable", "siid": 2, "piid": 4}, {"did": "child_lock", "siid": 6, "piid": 1}, {"did": "timed_off", "siid": 5, "piid": 2}, {"did": "angle", "siid": 2, "piid": 5}, {"did": "tilt", "siid": 2, "piid": 6}]}');
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "fan_data_P9";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 2, "piid": 11}, {"did": "mode", "siid": 2, "piid": 4}, {"did": "led", "siid": 2, "piid": 12}, {"did": "buzzer", "siid": 2, "piid": 7}, {"did": "angle_enable", "siid": 2, "piid": 5}, {"did": "child_lock", "siid": 3, "piid": 1}, {"did": "timed_off", "siid": 2, "piid": 8}, {"did": "angle", "siid": 2, "piid": 6}]}');
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "lamp_data";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","bright","cct","snm","dv","ct","color_mode","delayoff","flowing","flow_params","name","rgb","hue","sat","ambstatus","ambvalue","eyecare","bls","dvalue","kid_mode","skey_act","skey_scene_id","lan_ctrl"]}' );
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "lamp_data";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","bright","scene_num","notifystatus","ambstatus","ambvalue","eyecare","bls","dvalue"]}' );
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "WaterPurifier")
  {
    return undef;
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Camera")
  {
    return undef;
  }

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "RiceCooker")
  {
    return undef;
  }
  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "PowerPlug")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "powerplug_data";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power", "temperature", "current", "mode", "power_consume_rate", "wifi_led", "power_price", "voltage", "power_factor", "elec_leakage", "usb_power", "load_power", "usb_on"]}' );
  }


  my $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_consumable";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_consumable","params":[""]}' );
  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_clean_summary";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_clean_summary","params":[""]}' );
  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_dnd_timer";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_dnd_timer","params":[""]}' );
  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_timer";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_timer","params":[""]}' );

  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_sound_volume";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_sound_volume","params":[""]}' );

  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_carpet_mode";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_carpet_mode","params":[""]}' );

  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_fw_features";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_fw_features","params":[""]}' );

  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "app_get_locale";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"app_get_locale","params":[""]}' );

  return undef;
}


#####################################
sub XiaomiDevice_GetDeviceDetails($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "XiaomiDevice_GetDeviceDetails");
  InternalTimer( gettimeofday() + 3600*24, "XiaomiDevice_GetDeviceDetails", $hash);

  return undef if(!defined($hash->{helper}{dev}));

  return undef if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan");


  my $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "device_info";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"miIO.info","params":[""]}' );

  return undef if(defined($hash->{model}) && $hash->{model} eq "zhimi.fan.za4");

  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "wifi_stats";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"miIO.wifi_assoc_state","params":[""]}' );

  return undef if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} ne "VacuumCleaner");
  return undef if(!defined($hash->{model}));

  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_serial_number";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_serial_number","params":[""]}' );

  $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_timezone";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_timezone","params":[""]}' );

  return undef;
}

#####################################
sub XiaomiDevice_GetSpeed($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if(!defined($hash->{helper}{dev}));

  my $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;

  if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "VacuumCleaner")
  {
    $hash->{helper}{packet}{$packetid} = "get_custom_mode";
    return XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_custom_mode","params":[""]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier")
  {
    $hash->{helper}{packet}{$packetid} = "air_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","motor1_speed","favorite_level","motor2_speed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "AirPurifier3H")
  {
    $hash->{helper}{packet}{$packetid} = "air_status_3H";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 2},{"did": "mode", "siid": 2, "piid": 5},{"did": "motor_speed", "siid": 10, "piid": 8},{"did": "favorite_level", "siid": 10, "piid": 10}]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "Humidifier")
  {
    $hash->{helper}{packet}{$packetid} = "hum_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","limit_hum"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EvpHumidifier")
  {
    $hash->{helper}{packet}{$packetid} = "hum_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","limit_hum"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "HumidifierMJJSQ")
  {
    $hash->{helper}{packet}{$packetid} = "hum_status_mjjsq";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["OnOff_State","Humidifier_Gear","HumiSet_Value"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan")
  {
    $hash->{helper}{packet}{$packetid} = "fan_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","speed_level","natural_level","speed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1X")
  {
    $hash->{helper}{packet}{$packetid} = "fan_status_1x";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","mode","speed"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFan1C")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data_1C";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 2, "piid": 2}, {"did": "mode", "siid": 2, "piid": 7}, {"did": "led", "siid": 2, "piid": 12}, {"did": "buzzer", "siid": 2, "piid": 11}, {"did": "angle_enable", "siid": 2, "piid": 3}, {"did": "child_lock", "siid": 3, "piid": 1}, {"did": "timed_off", "siid": 2, "piid": 10}]}');
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartFanFA1")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data_FA1";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 5, "piid": 10}, {"did": "mode", "siid": 2, "piid": 7}, {"did": "led", "siid": 2, "piid": 10}, {"did": "buzzer", "siid": 2, "piid": 11}, {"did": "angle_enable", "siid": 2, "piid": 3}, {"did": "tilt_enable", "siid": 2, "piid": 4}, {"did": "child_lock", "siid": 6, "piid": 1}, {"did": "timed_off", "siid": 5, "piid": 2}, {"did": "angle", "siid": 2, "piid": 5}, {"did": "tilt", "siid": 2, "piid": 6}]}');
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "TowerFanP9")
  {
    $hash->{helper}{packet}{$packetid} = "fan_data_P9";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_properties","params":[{"did": "power", "siid": 2, "piid": 1}, {"did": "level", "siid": 2, "piid": 11}, {"did": "mode", "siid": 2, "piid": 4}, {"did": "led", "siid": 2, "piid": 12}, {"did": "buzzer", "siid": 2, "piid": 7}, {"did": "angle_enable", "siid": 2, "piid": 5}, {"did": "child_lock", "siid": 3, "piid": 1}, {"did": "timed_off", "siid": 2, "piid": 8}, {"did": "angle", "siid": 2, "piid": 6}]}');
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp")
  {
    $hash->{helper}{packet}{$packetid} = "lamp_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","bright","cct","snm","dv","ct","rgb","hue","sat","ambstatus","ambvalue","eyecare","bls","dvalue"]}' );
  }
  elsif( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare")
  {
    $hash->{helper}{packet}{$packetid} = "lamp_status";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_prop","params":["power","bright","scene_num","notifystatus","ambstatus","ambvalue","eyecare","bls","dvalue"]}' );
  }
  return undef;
}


#####################################
sub XiaomiDevice_GetDnd($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if(!defined($hash->{helper}{dev}));
  my $packetid = $hash->{helper}{packetid};
  $hash->{helper}{packetid} = $packetid+1;
  $hash->{helper}{packet}{$packetid} = "get_dnd_timer";
  XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_dnd_timer","params":[""]}' );
  return undef;
}


#####################################
sub XiaomiDevice_WriteJSON($$)
{
  my ($hash,$json)  = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: write $json (".length($json).")";

  if(IsDisabled($name)) {
    Log3 ($name, 3, "XiaomiDevice $name is disabled, communication cancelled.");
    return undef;
  }

  #if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "SmartLamp")
  #{
  #  $json =~ /"id":(.*),"method"/;
  #  my $msgid = $1;
  #  my $msgtype = $hash->{helper}{packet}{$msgid};
  #  Log3 $name, 2, "$name: Message type for ID $msgid is $msgtype >";
  #}

  XiaomiDevice_initSend($hash) if(!defined($hash->{helper}{last_read}) || $hash->{helper}{last_read} < (int(time())-180) );


  my $key = Digest::MD5::md5(pack('H*', $hash->{helper}{token}));
  my $iv = Digest::MD5::md5($key.pack('H*', $hash->{helper}{token}));
  my $cbc;

  if($hash->{helper}{crypt} ne "Rijndael"){
    $cbc = Crypt::CBC->new(-key => $key, -cipher => 'Crypt::Cipher::AES',-iv => $iv, -literal_key => 1, -header => "none", -keysize => 16 );
  } else {
    $Crypt::Rijndael_PP::DEFAULT_KEYSIZE = 128;
    $cbc = Crypt::CBC->new(-key => $key, -cipher => 'Crypt::Rijndael_PP',-iv => $iv, -literal_key => 1, -header => "none", -keysize => 16 );
  }
  my $crypt = $cbc->encrypt_hex($json);
  $crypt = pack('H*', $crypt);

  if(!defined($hash->{helper}) || !defined($hash->{helper}{sequence}) || !defined($hash->{helper}{dev}) || !defined($hash->{helper}{id}) || !defined($hash->{helper}{token}) )
  {
    RemoveInternalTimer($hash);
    Log3 ($name, 1, "$name: internal error, values missing");
    $hash->{helper}{delay} += 300;
    InternalTimer( gettimeofday() + $hash->{helper}{delay}, "XiaomiDevice_connect", $hash);
    return undef;
  }
  my $sequence = sprintf("%.8x", ( int(time) - $hash->{helper}{sequence} ));
  my $length = sprintf("%.4x",length($crypt)+32);
  my $package = "2131".$length."00000000".$hash->{helper}{dev}.$hash->{helper}{id}.$sequence.$hash->{helper}{token}.unpack('H*', $crypt);
  my $checksum = unpack('H*', Digest::MD5::md5(pack('H*',$package)));
  $package = "2131".$length."00000000".$hash->{helper}{dev}.$hash->{helper}{id}.$sequence.$checksum.unpack('H*', $crypt);

  Log3 $name, 5, "$name: send ".$package;

  my $data = pack('H*', $package);
  XiaomiDevice_Write($hash,$data);

  return undef;
}



#####################################
sub XiaomiDevice_ParseJSON($$)
{
  my ($hash,$jsonstring)  = @_;
  my $name = $hash->{NAME};

  Log3 $name, 2, "$name: invalid JSON: $jsonstring" if( $jsonstring !~ m/^{.*}/ );
  return undef if( $jsonstring !~ m/^{.*}/ );
  $jsonstring =~ s/,,/,/g;
  $jsonstring =~ tr/a-zA-ZÄÖÜäöüß0-9.,\+\*\#\@\!\&\_\-\:\"\'\[\{\]\}\/\\//cd;
  my $json = eval { JSON::decode_json($jsonstring) };
  if($@)
  {
    Log3 $name, 2, "$name: invalid json evaluation: $jsonstring";
    return undef;
  }

  Log3 $name, 5, "$name: parse id ".$json->{id}."\n".Dumper($json);

  my $msgid = $json->{id};
  my $msgtype = $hash->{helper}{packet}{$msgid};

  if(defined($msgtype) && $msgtype eq "json_command"){
    delete $hash->{helper}{packet}{$msgid};
  }
  elsif($msgid>5){ #keep last 3 in case of duplicate replies
    delete $hash->{helper}{packet}{$msgid-5};
    delete $hash->{helper}{packet}{$msgid-4};
    delete $hash->{helper}{packet}{$msgid-3};
  }

  if(!defined($msgtype))
  {
    Log3 $name, 2, "$name: Message type for ID $msgid not found";
    Log3 $name, 4, "$name: ".Dumper($json);
    return undef;
  }

  if($msgtype eq "json_command")
  {
    Log3 $name, 0, "$name: result for json request w/ id ".$msgid.", return is \n".Dumper($json);;
    return undef;
  }

  Log3 $name, 4, "$name: parse id ".$json->{id}." / ".$msgtype;

  Log3 $name, 4, "$name: msg ref is ".ref($json->{result});

  if(defined($json->{error}) && defined($json->{error}{message}))
  {
    readingsSingleUpdate( $hash, "error", $json->{error}{message}, 1 );
  }
  else
  {
    readingsSingleUpdate( $hash, "error", "none", 1 );
  }

  if(!$msgtype)
  {
    Log3 $name, 2, "$name: Message type for ID ".$json->{id}." not found";
    Log3 $name, 4, "$name: ".Dumper($json);
    return undef;
  }

  return undef if($msgtype eq "app_rc_move");
  return undef if($msgtype eq "app_rc_forward");
  return undef if($msgtype eq "app_rc_left");
  return undef if($msgtype eq "app_rc_right");
  return undef if($msgtype eq "find_me");
  return undef if($msgtype eq "move");
  return undef if($msgtype eq "test_sound_volume");
  return undef if($msgtype eq "app_wakeup_robot");
  return undef if($msgtype eq "app_sleep");
  return undef if($msgtype eq "save_map");
  return undef if($msgtype eq "start_edit_map");
  return undef if($msgtype eq "end_edit_map");
  return undef if($msgtype eq "reset_map");
  return undef if($msgtype eq "use_new_map");
  return undef if($msgtype eq "use_old_map");
  return undef if($msgtype eq "get_persist_map");
  return undef if($msgtype eq "get_fresh_map");
  return undef if($msgtype eq "lab_status");
  return undef if($msgtype eq "clean_segment");
  return undef if($msgtype eq "clean_segment_stop");
  return undef if($msgtype eq "clean_segment_resume");

  if($msgtype eq "air_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    my $stateval = $json->{result}[1];
    $stateval .= (" ".$json->{result}[7]) if($stateval eq "favorite" && defined($json->{result}[7]));
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "speed", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "temperature", ($json->{result}[3]/10), 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "humidity", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "pm25", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
    readingsBulkUpdate( $hash, "pm25_average", $json->{result}[6], 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "favorite", $json->{result}[7], 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "usage", sprintf( "%.1f", $json->{result}[8]/3600), 1 ) if(defined($json->{result}[8]));
    readingsBulkUpdate( $hash, "filter_volume", $json->{result}[9], 1 ) if(defined($json->{result}[9]));
    readingsBulkUpdate( $hash, "filter", $json->{result}[10], 1 ) if(defined($json->{result}[10]));
    readingsBulkUpdate( $hash, "filter_used", $json->{result}[11], 1 ) if(defined($json->{result}[11]));
    readingsBulkUpdate( $hash, "filter_life", $json->{result}[12], 1 ) if(defined($json->{result}[12]));
    readingsBulkUpdate( $hash, "button_pressed", $json->{result}[13], 1 ) if(defined($json->{result}[13]));
    readingsBulkUpdate( $hash, "speed2", $json->{result}[14], 1 ) if(defined($json->{result}[14]));
    readingsBulkUpdate( $hash, "state", $stateval, 1 ) if(defined($stateval));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "air_settings")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "buzzer", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "led", ($json->{result}[1] eq "0" ? 'bright' : $json->{result}[1] eq "1" ? 'dim' : 'off' ), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "child_lock", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "turbo", ($json->{result}[3] eq "0" ? 'off' : 'on'), 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "sleep_auto", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "sleep_time", $json->{result}[6], 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "filter_volume", $json->{result}[7], 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "rfid_product_id", $json->{result}[8], 1 ) if(defined($json->{result}[8]));
    readingsBulkUpdate( $hash, "rfid_tag", $json->{result}[9], 1 ) if(defined($json->{result}[9]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "air_data_3H")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", (($json->{result}[0]{value} eq "false" || $json->{result}[0]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[0]{value}));
    readingsBulkUpdate( $hash, "level", $json->{result}[1]{value}, 1 ) if(defined($json->{result}[1]{value}));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[2]{value} eq "0" ? 'auto' : $json->{result}[2]{value} eq "1" ? 'silent' : $json->{result}[2]{value} eq "2" ? 'favorite' : 'fan'), 1 ) if(defined($json->{result}[2]{value}));
    readingsBulkUpdate( $hash, "humidity", $json->{result}[3]{value}, 1 ) if(defined($json->{result}[3]{value}));
    readingsBulkUpdate( $hash, "temperature", $json->{result}[4]{value}, 1 ) if(defined($json->{result}[4]{value}));
    readingsBulkUpdate( $hash, "pm25", $json->{result}[5]{value}, 1 ) if(defined($json->{result}[5]{value}));
    readingsBulkUpdate( $hash, "filter_life", $json->{result}[6]{value}, 1 ) if(defined($json->{result}[6]{value}));
    readingsBulkUpdate( $hash, "filter_volume", $json->{result}[7]{value}, 1 ) if(defined($json->{result}[7]{value}));
    readingsBulkUpdate( $hash, "filter_used", $json->{result}[8]{value}, 1 ) if(defined($json->{result}[8]{value}));
    readingsBulkUpdate( $hash, "favorite", $json->{result}[9]{value}, 1 ) if(defined($json->{result}[9]{value}));
    readingsBulkUpdate( $hash, "favorite_rpm", $json->{result}[10]{value}, 1 ) if(defined($json->{result}[10]{value}));
    readingsBulkUpdate( $hash, "speed", $json->{result}[11]{value}, 1 ) if(defined($json->{result}[11]{value}));
    readingsBulkUpdate( $hash, "usage", sprintf( "%.1f", $json->{result}[12]{value}/3600), 1 ) if(defined($json->{result}[12]{value}));
    readingsBulkUpdate( $hash, "pm25_average", $json->{result}[13]{value}, 1 ) if(defined($json->{result}[13]{value}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "air_settings_3H" )
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    #readingsBulkUpdate( $hash, "led_state", $json->{result}[0]{value} eq "false" ? 'off' : 'on', 1 ) if(defined($json->{result}[0]{value}));
    readingsBulkUpdate( $hash, "buzzer", $json->{result}[1]{value} eq "false" ? 'off' : 'on', 1 ) if(defined($json->{result}[1]{value}));
    readingsBulkUpdate( $hash, "buzzer_volume", $json->{result}[2]{value}, 1 ) if(defined($json->{result}[2]{value}));
    readingsBulkUpdate( $hash, "led", ($json->{result}[3]{value} eq "0" ? 'bright' : $json->{result}[3]{value} eq "1" ? 'dim' : 'off' ), 1 ) if(defined($json->{result}[3]{value}));
    readingsBulkUpdate( $hash, "child_lock", $json->{result}[4]{value} eq "false" ? 'off' : 'on', 1 ) if(defined($json->{result}[4]{value}));
    readingsBulkUpdate( $hash, "app_extra", $json->{result}[5]{value}, 1 ) if(defined($json->{result}[5]{value}));
    readingsBulkUpdate( $hash, "filter_rfid_product_id", $json->{result}[6]{value}, 1 ) if(defined($json->{result}[6]{value}));
    readingsBulkUpdate( $hash, "filter_rfid_tag", $json->{result}[7]{value}, 1 ) if(defined($json->{result}[7]{value}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if ($msgtype eq "air_status_3H")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", (($json->{result}[0]{value} eq "false" || $json->{result}[0]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[0]{value}));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[1]{value} eq "0" ? 'auto' : $json->{result}[1]{value} eq "1" ? 'silent' : $json->{result}[1]{value} eq "2" ? 'favorite' : 'fan'), 1 ) if(defined($json->{result}[1]{value}));
    readingsBulkUpdate( $hash, "speed", $json->{result}[2]{value}, 1 ) if(defined($json->{result}[2]{value}));
    readingsBulkUpdate( $hash, "favorite", $json->{result}[3]{value}, 1 ) if(defined($json->{result}[3]{value}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "air_status")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    my $stateval = $json->{result}[1];
    $stateval .= (" ".$json->{result}[3]) if($stateval eq "favorite" && defined($json->{result}[3]));
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "speed", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "favorite", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "speed2", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "state", $stateval, 1 ) if(defined($stateval));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "hum_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[0] eq "off") ? "idle" : $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "temperature", ($json->{result}[2]/10), 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "humidity", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "trans_level", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "speed", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
    readingsBulkUpdate( $hash, "depth", (int($json->{result}[6]/125*100)), 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "temperature", $json->{result}[7], 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "usage", sprintf( "%.1f", $json->{result}[8]/3600), 1 ) if(defined($json->{result}[8]));
    readingsBulkUpdate( $hash, "button_pressed", $json->{result}[9], 1 ) if(defined($json->{result}[9]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "hum_data_evp")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[1] eq "off") ? "idle" : $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "humidity", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "speed", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "depth", (int($json->{result}[4]/125*100)), 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "temperature", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
    readingsBulkUpdate( $hash, "usage", sprintf( "%.1f", $json->{result}[6]/3600), 1 ) if(defined($json->{result}[6]));
    #readingsBulkUpdate( $hash, "state", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "hum_data_mjjsq")
  {
    # "Humidifier_Gear","Humidity_Value","HumiSet_Value","Led_State","OnOff_State","TemperatureValue","TipSound_State","waterstatus","watertankstatus"
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "mode", ($json->{result}[0] == 1 ? 'silent' : ($json->{result}[0] == 2) ? 'medium' : ($json->{result}[0] == 2) ? 'high' : 'auto' ), 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "humidity", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "limit_hum", ($json->{result}[2]), 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "led", ($json->{result}[3] == 1 ? 'on' : 'off' ), 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "power", ($json->{result}[4] == 1 ? 'on' : 'off' ), 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "temperature", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
    readingsBulkUpdate( $hash, "buzzer", ($json->{result}[6] == 1 ? 'on' : 'off' ), 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "water", ($json->{result}[7] == 1 ? 'ok' : 'low' ), 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "tank", ($json->{result}[8] == 1 ? 'installed' : 'detached' ), 1 ) if(defined($json->{result}[8]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "hum_settings")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "buzzer", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "led", ($json->{result}[1] eq "0" ? 'bright' : $json->{result}[1] eq "1" ? 'dim' : 'off' ), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "child_lock", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "limit_hum", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "dry", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "hum_settings_evp")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "buzzer", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "led", ($json->{result}[1] == 0 ? 'bright' : $json->{result}[1] == 1 ? 'dim' : 'off' ), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "child_lock", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "limit_hum", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "dry", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "hum_settings_mjjsq")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "limit_hum", ($json->{result}[0]), 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "led", ($json->{result}[1] == 1 ? 'on' : 'off' ), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "buzzer", ($json->{result}[2] == 1 ? 'on' : 'off' ), 1 ) if(defined($json->{result}[2]));
    readingsEndUpdate($hash,1);
    return undef;
  }

  if($msgtype eq "hum_status")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[0] eq "off") ? "idle" : $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "limit_hum", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsEndUpdate($hash,1);
    return undef;
  }

  if($msgtype eq "hum_status_mjjsq")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", ($json->{result}[0] == 1 ? 'on' : 'off' ), 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[1] == 1 ? 'silent' : ($json->{result}[1] == 2) ? 'medium' : ($json->{result}[1] == 2) ? 'high' : 'auto' ), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "limit_hum", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsEndUpdate($hash,1);
    return undef;
  }

  if($msgtype eq "lamp_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare"){
      readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
      readingsBulkUpdate( $hash, "brightness_on", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
      readingsBulkUpdate( $hash, "brightness", ($json->{result}[0] eq "off") ? "0" : $json->{result}[1], 1 ) if(defined($json->{result}[1]));
      readingsBulkUpdate( $hash, "scene_num", $json->{result}[2], 1 ) if(defined($json->{result}[2]) && $json->{result}[2] ne "");
      readingsBulkUpdate( $hash, "notifystatus", $json->{result}[3], 1 ) if(defined($json->{result}[3]) && $json->{result}[3] ne "");
      readingsBulkUpdate( $hash, "ambstatus", $json->{result}[4], 1 ) if(defined($json->{result}[4]) && $json->{result}[4] ne "");
      readingsBulkUpdate( $hash, "ambvalue", $json->{result}[5], 1 ) if(defined($json->{result}[5]) && $json->{result}[5] ne "");
      readingsBulkUpdate( $hash, "eyecare", $json->{result}[6], 1 ) if(defined($json->{result}[6]) && $json->{result}[6] ne "");
      readingsBulkUpdate( $hash, "bls", $json->{result}[7], 1 ) if(defined($json->{result}[7]) && $json->{result}[7] ne "");
      readingsBulkUpdate( $hash, "dvalue", $json->{result}[8], 1 ) if(defined($json->{result}[8]) && $json->{result}[8] ne "");
    } else {
      readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
      readingsBulkUpdate( $hash, "brightness_on", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
      readingsBulkUpdate( $hash, "brightness", ($json->{result}[0] eq "off") ? "0" : $json->{result}[1], 1 ) if(defined($json->{result}[1]));
      readingsBulkUpdate( $hash, "cct", $json->{result}[2], 1 ) if(defined($json->{result}[2]) && $json->{result}[2] ne "");
      readingsBulkUpdate( $hash, "snm", $json->{result}[3], 1 ) if(defined($json->{result}[3]) && $json->{result}[3] ne "");
      readingsBulkUpdate( $hash, "dv", $json->{result}[4], 1 ) if(defined($json->{result}[4]) && $json->{result}[4] ne "");
      readingsBulkUpdate( $hash, "ct", $json->{result}[5], 1 ) if(defined($json->{result}[5]) && $json->{result}[5] ne "");
      readingsBulkUpdate( $hash, "color_mode", $json->{result}[6], 1 ) if(defined($json->{result}[6]) && $json->{result}[6] ne "");
      readingsBulkUpdate( $hash, "poweroff_time", $json->{result}[7], 1 ) if(defined($json->{result}[7]) && $json->{result}[7] ne "");
      readingsBulkUpdate( $hash, "flowing", $json->{result}[8], 1 ) if(defined($json->{result}[8]) && $json->{result}[8] ne "");
      readingsBulkUpdate( $hash, "flow_params", $json->{result}[9], 1 ) if(defined($json->{result}[9]) && $json->{result}[9] ne "");
      readingsBulkUpdate( $hash, "name", $json->{result}[10], 1 ) if(defined($json->{result}[10]) && $json->{result}[10] ne "");
      readingsBulkUpdate( $hash, "rgb", $json->{result}[11], 1 ) if(defined($json->{result}[11]) && $json->{result}[11] ne "");
      readingsBulkUpdate( $hash, "hue", $json->{result}[12], 1 ) if(defined($json->{result}[12]) && $json->{result}[12] ne "");
      readingsBulkUpdate( $hash, "sat", $json->{result}[13], 1 ) if(defined($json->{result}[13]) && $json->{result}[13] ne "");
      readingsBulkUpdate( $hash, "ambstatus", $json->{result}[14], 1 ) if(defined($json->{result}[14]) && $json->{result}[14] ne "");
      readingsBulkUpdate( $hash, "ambvalue", $json->{result}[15], 1 ) if(defined($json->{result}[15]) && $json->{result}[15] ne "");
      readingsBulkUpdate( $hash, "eyecare", $json->{result}[16], 1 ) if(defined($json->{result}[16]) && $json->{result}[16] ne "");
      readingsBulkUpdate( $hash, "bls", $json->{result}[17], 1 ) if(defined($json->{result}[17]) && $json->{result}[17] ne "");
      readingsBulkUpdate( $hash, "dvalue", $json->{result}[18], 1 ) if(defined($json->{result}[18]) && $json->{result}[18] ne "");
      readingsBulkUpdate( $hash, "kid_mode", $json->{result}[19], 1 ) if(defined($json->{result}[19]) && $json->{result}[19] ne "");
      readingsBulkUpdate( $hash, "skey_act", $json->{result}[20], 1 ) if(defined($json->{result}[20]) && $json->{result}[20] ne "");
      readingsBulkUpdate( $hash, "skey_scene_id", $json->{result}[21], 1 ) if(defined($json->{result}[21]) && $json->{result}[21] ne "");
      readingsBulkUpdate( $hash, "lan_ctrl", $json->{result}[22], 1 ) if(defined($json->{result}[22]) && $json->{result}[22] ne "");
    }
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "lamp_status")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    if( defined($attr{$name}) && defined($attr{$name}{subType}) && $attr{$name}{subType} eq "EyeCare"){
      readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
      readingsBulkUpdate( $hash, "brightness", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
      readingsBulkUpdate( $hash, "scene_num", $json->{result}[2], 1 ) if(defined($json->{result}[2]) && $json->{result}[2] ne "");
      readingsBulkUpdate( $hash, "notifystatus", $json->{result}[3], 1 ) if(defined($json->{result}[3]) && $json->{result}[3] ne "");
      readingsBulkUpdate( $hash, "ambstatus", $json->{result}[4], 1 ) if(defined($json->{result}[4]) && $json->{result}[4] ne "");
      readingsBulkUpdate( $hash, "ambvalue", $json->{result}[5], 1 ) if(defined($json->{result}[5]) && $json->{result}[5] ne "");
      readingsBulkUpdate( $hash, "eyecare", $json->{result}[6], 1 ) if(defined($json->{result}[6]) && $json->{result}[6] ne "");
      readingsBulkUpdate( $hash, "bls", $json->{result}[7], 1 ) if(defined($json->{result}[7]) && $json->{result}[7] ne "");
      readingsBulkUpdate( $hash, "dvalue", $json->{result}[8], 1 ) if(defined($json->{result}[8]) && $json->{result}[8] ne "");
    } else {
      readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
      readingsBulkUpdate( $hash, "brightness", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
      readingsBulkUpdate( $hash, "cct", $json->{result}[2], 1 ) if(defined($json->{result}[2]) && $json->{result}[2] ne "");
      readingsBulkUpdate( $hash, "snm", $json->{result}[3], 1 ) if(defined($json->{result}[3]) && $json->{result}[3] ne "");
      readingsBulkUpdate( $hash, "dv", $json->{result}[4], 1 ) if(defined($json->{result}[4]) && $json->{result}[4] ne "");
      readingsBulkUpdate( $hash, "ct", $json->{result}[5], 1 ) if(defined($json->{result}[5]) && $json->{result}[5] ne "");
      readingsBulkUpdate( $hash, "rgb", $json->{result}[6], 1 ) if(defined($json->{result}[6]) && $json->{result}[6] ne "");
      readingsBulkUpdate( $hash, "hue", $json->{result}[7], 1 ) if(defined($json->{result}[7]) && $json->{result}[7] ne "");
      readingsBulkUpdate( $hash, "sat", $json->{result}[8], 1 ) if(defined($json->{result}[8]) && $json->{result}[8] ne "");
      readingsBulkUpdate( $hash, "ambstatus", $json->{result}[9], 1 ) if(defined($json->{result}[9]) && $json->{result}[9] ne "");
      readingsBulkUpdate( $hash, "ambvalue", $json->{result}[10], 1 ) if(defined($json->{result}[10]) && $json->{result}[10] ne "");
      readingsBulkUpdate( $hash, "eyecare", $json->{result}[11], 1 ) if(defined($json->{result}[11]) && $json->{result}[11] ne "");
      readingsBulkUpdate( $hash, "bls", $json->{result}[12], 1 ) if(defined($json->{result}[12]) && $json->{result}[12] ne "");
      readingsBulkUpdate( $hash, "dvalue", $json->{result}[13], 1 ) if(defined($json->{result}[13]) && $json->{result}[13] ne "");
    }
    readingsEndUpdate($hash,1);
    return undef;
  }

  #"power","bright","ct","color_mode","delayoff","flowing","flow_params","name"
  if($msgtype eq "fan_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    #"angle","angle_enable","power","bat_charge","battery","speed_level","natural_level","buzzer","led_b","poweroff_time","ac_power","child_lock","temp_dec","humidity"
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "angle", (int($json->{result}[0])==118)?"120":$json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "angle_enable", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "power", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "charging", $json->{result}[3], 1 ) if(defined($json->{result}[3]) && $json->{result}[3] ne "null");
    readingsBulkUpdate( $hash, "batteryPercent", $json->{result}[4], 1 ) if(defined($json->{result}[4]) && $json->{result}[4] ne "null");
    readingsBulkUpdate( $hash, "batteryState", int($json->{result}[4])<20 ? "low" : "ok", 1 ) if(defined($json->{result}[4]) && $json->{result}[4] ne "null");
    my $fanspeed = 0;
    $fanspeed = $json->{result}[5] if(defined($json->{result}[5]));
    $fanspeed = $json->{result}[6] if(defined($json->{result}[6]) && int($json->{result}[6])>0);
    readingsBulkUpdate( $hash, "level_on", $fanspeed, 1 ) if(defined($json->{result}[6]));
    $fanspeed = 0 if($json->{result}[2] eq "off");
    readingsBulkUpdate( $hash, "level", $fanspeed, 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "mode", (int($json->{result}[6])>0)?"natural":"straight", 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "buzzer", ($json->{result}[7] eq "0" ? "off" : $json->{result}[7] eq "2" ? "on" : $json->{result}[7]), 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "led", ($json->{result}[8] eq "0" ? 'bright' : $json->{result}[1] eq "1" ? 'dim' : 'off' ), 1 ) if(defined($json->{result}[8]));
    readingsBulkUpdate( $hash, "poweroff_time", $json->{result}[9], 1 ) if(defined($json->{result}[9]));
    readingsBulkUpdate( $hash, "ac_power", $json->{result}[10], 1 ) if(defined($json->{result}[10]));
    readingsBulkUpdate( $hash, "child_lock", $json->{result}[11], 1 ) if(defined($json->{result}[11]));
    readingsBulkUpdate( $hash, "temperature", $json->{result}[12]/10, 1 ) if(defined($json->{result}[12]) && $json->{result}[12] ne "null");
    readingsBulkUpdate( $hash, "humidity", $json->{result}[13], 1 ) if(defined($json->{result}[13]) && $json->{result}[13] ne "null");
    readingsBulkUpdate( $hash, "speed", (($json->{result}[2] eq "off")?"0":$json->{result}[14]), 1 ) if(defined($json->{result}[14]));
    readingsBulkUpdate( $hash, "button_pressed", $json->{result}[15], 1 ) if(defined($json->{result}[15]) && $json->{result}[15] ne "null");
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "fan_data_1x")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    #"power","mode","speed","roll_enable","roll_angle","time_off","light","beep_sound","child_lock"
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", ((lc $json->{result}[0] eq "false" || $json->{result}[0] eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[1] eq "normal" ? 'straight' : 'natural'), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "level", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "angle_enable", ((lc $json->{result}[3] eq "false" || $json->{result}[3] eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "angle", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "poweroff_time", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
    readingsBulkUpdate( $hash, "led", ((lc $json->{result}[6] eq "false" || $json->{result}[6] eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "buzzer", ((lc $json->{result}[7] eq "false" || $json->{result}[7] eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "child_lock", ((lc $json->{result}[8] eq "false" || $json->{result}[8] eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[8]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if ($msgtype eq "fan_data_1C")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", (($json->{result}[0]{value} eq "false" || $json->{result}[0]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[0]{value}));
    readingsBulkUpdate( $hash, "level", ($json->{result}[1]{value} eq "0" ? '0' : $json->{result}[1]{value} eq "1" ? '1' : $json->{result}[1]{value} eq "2" ? '2' : '3'), 1 ) if(defined($json->{result}[1]{value}));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[2]{value} eq "0" ? 'straight' : $json->{result}[2]{value} eq "1" ? 'sleep' : 'auto'), 1 ) if(defined($json->{result}[2]{value}));
    readingsBulkUpdate( $hash, "led", (($json->{result}[3]{value} eq "false" || $json->{result}[3]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[3]{value}));
    readingsBulkUpdate( $hash, "buzzer", (($json->{result}[4]{value} eq "false" || $json->{result}[4]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[4]{value}));
    readingsBulkUpdate( $hash, "angle_enable", (($json->{result}[5]{value} eq "false" || $json->{result}[5]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[5]{value}));
    readingsBulkUpdate( $hash, "child_lock", (($json->{result}[6]{value} eq "false" || $json->{result}[6]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[6]{value}));
    readingsBulkUpdate( $hash, "timed_off", $json->{result}[7]{value}, 1 ) if(defined($json->{result}[7]{value}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if ($msgtype eq "fan_data_FA1")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", (($json->{result}[0]{value} eq "false" || $json->{result}[0]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[0]{value}));
    readingsBulkUpdate( $hash, "level", (($json->{result}[0]{value} eq "false" || $json->{result}[0]{value} eq "0") ? '0' : $json->{result}[1]{value}), 1 ) if(defined($json->{result}[1]{value}));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[2]{value} eq "0" ? 'straight' : $json->{result}[2]{value} eq "1" ? 'sleep' : 'auto'), 1 ) if(defined($json->{result}[2]{value}));
    readingsBulkUpdate( $hash, "led", (($json->{result}[3]{value} eq "false" || $json->{result}[3]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[3]{value}));
    readingsBulkUpdate( $hash, "buzzer", (($json->{result}[4]{value} eq "false" || $json->{result}[4]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[4]{value}));
    readingsBulkUpdate( $hash, "angle_enable", (($json->{result}[5]{value} eq "false" || $json->{result}[5]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[5]{value}));
    readingsBulkUpdate( $hash, "tilt_enable", (($json->{result}[6]{value} eq "false" || $json->{result}[6]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[6]{value}));
    readingsBulkUpdate( $hash, "child_lock", (($json->{result}[7]{value} eq "false" || $json->{result}[7]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[7]{value}));
    readingsBulkUpdate( $hash, "timed_off", $json->{result}[8]{value}, 1 ) if(defined($json->{result}[8]{value}));
    readingsBulkUpdate( $hash, "angle", $json->{result}[9]{value}, 1 ) if(defined($json->{result}[9]{value}));
    readingsBulkUpdate( $hash, "tilt", $json->{result}[10]{value}, 1 ) if(defined($json->{result}[10]{value}));
    readingsBulkUpdate( $hash, "oscillate_enable", (($json->{result}[5]{value} eq "false" || $json->{result}[5]{value} eq "0" || $json->{result}[6]{value} eq "false" || $json->{result}[6]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[5]{value}) && defined($json->{result}[6]{value}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if ($msgtype eq "fan_data_P9")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", (($json->{result}[0]{value} eq "false" || $json->{result}[0]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[0]{value}));
    readingsBulkUpdate( $hash, "level", $json->{result}[1]{value}, 1 ) if(defined($json->{result}[1]{value}));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[2]{value} eq "0" ? 'straight' : $json->{result}[2]{value} eq "1" ? 'natural' : 'sleep'), 1 ) if(defined($json->{result}[2]{value}));
    readingsBulkUpdate( $hash, "led", (($json->{result}[3]{value} eq "false" || $json->{result}[3]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[3]{value}));
    readingsBulkUpdate( $hash, "buzzer", (($json->{result}[4]{value} eq "false" || $json->{result}[4]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[4]{value}));
    readingsBulkUpdate( $hash, "angle_enable", (($json->{result}[5]{value} eq "false" || $json->{result}[5]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[5]{value}));
    readingsBulkUpdate( $hash, "child_lock", (($json->{result}[6]{value} eq "false" || $json->{result}[6]{value} eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[6]{value}));
    readingsBulkUpdate( $hash, "timed_off", $json->{result}[7]{value}, 1 ) if(defined($json->{result}[7]{value}));
    readingsBulkUpdate( $hash, "angle", $json->{result}[8]{value}, 1 ) if(defined($json->{result}[8]{value}));
    readingsEndUpdate($hash,1);
    return undef;
  }


  if($msgtype eq "fan_status")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    my $fanspeed = 0;
    $fanspeed = $json->{result}[1] if(defined($json->{result}[1]));
    $fanspeed = $json->{result}[2] if(defined($json->{result}[2]) && int($json->{result}[2])>0);
    readingsBulkUpdate( $hash, "level_on", $fanspeed, 1 ) if(defined($json->{result}[2]));
    $fanspeed = 0 if($json->{result}[0] eq "off");
    readingsBulkUpdate( $hash, "level", $fanspeed, 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "mode", (int($json->{result}[2])>0)?"natural":"straight", 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "speed", (($json->{result}[0] eq "off")?"0":$json->{result}[3]), 1 ) if(defined($json->{result}[3]));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "fan_status_1x")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", (($json->{result}[0] eq "false" || $json->{result}[0] eq "0") ? 'off' : 'on'), 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", ($json->{result}[1] eq "normal" ? 'straight' : 'natural'), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "level", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsEndUpdate($hash,1);
    return undef;
  }

  if($msgtype eq "water_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "mode", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "tds", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "filter1_life", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "filter1_state", ($json->{result}[4]), 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "filter_life", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
    readingsBulkUpdate( $hash, "filter_state", $json->{result}[6], 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "life", $json->{result}[7], 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "state", $json->{result}[8], 1 ) if(defined($json->{result}[8]));
    readingsBulkUpdate( $hash, "level", $json->{result}[9], 1 ) if(defined($json->{result}[9]));
    readingsBulkUpdate( $hash, "water_volume", $json->{result}[10], 1 ) if(defined($json->{result}[10]));
    readingsBulkUpdate( $hash, "filter", $json->{result}[11], 1 ) if(defined($json->{result}[11]));
    readingsBulkUpdate( $hash, "usage", $json->{result}[12], 1 ) if(defined($json->{result}[12]));
    readingsBulkUpdate( $hash, "temperature", $json->{result}[13], 1 ) if(defined($json->{result}[13]));
    readingsBulkUpdate( $hash, "uv_life", $json->{result}[14], 1 ) if(defined($json->{result}[14]));
    readingsBulkUpdate( $hash, "uv_state", $json->{result}[15], 1 ) if(defined($json->{result}[15]));
    readingsBulkUpdate( $hash, "elecval_state", $json->{result}[16], 1 ) if(defined($json->{result}[16]));
    readingsBulkUpdate( $hash, "button_pressed", $json->{result}[17], 1 ) if(defined($json->{result}[17]));
    readingsEndUpdate($hash,1);
    return undef;
  }

  if($msgtype eq "camera_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsEndUpdate($hash,1);
    return undef;
  }

  if($msgtype eq "ricecooker_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "func", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "menu", $cooker_menus{$json->{result}[1]}, 1 ) if(defined($json->{result}[1]));
    #readingsBulkUpdate( $hash, "menu", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "stage", $cooker_stages{substr($json->{result}[1],0,2)}, 1 ) if(defined($json->{result}[2]));
    #readingsBulkUpdate( $hash, "stage", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsBulkUpdate( $hash, "temp", unpack('H*', substr($json->{result}[3],-2)), 1 ) if(defined($json->{result}[3]));
    #readingsBulkUpdate( $hash, "temp", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
    readingsBulkUpdate( $hash, "t_func", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
    readingsBulkUpdate( $hash, "t_precook", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
    readingsBulkUpdate( $hash, "t_cook", $json->{result}[6], 1 ) if(defined($json->{result}[6]));
    readingsBulkUpdate( $hash, "setting", $json->{result}[7], 1 ) if(defined($json->{result}[7]));
    readingsBulkUpdate( $hash, "delay", $json->{result}[8], 1 ) if(defined($json->{result}[8]));
    readingsBulkUpdate( $hash, "version", $json->{result}[9], 1 ) if(defined($json->{result}[9]));
    readingsBulkUpdate( $hash, "button_pressed", $json->{result}[10], 1 ) if(defined($json->{result}[10]));
    readingsEndUpdate($hash,1);
    return undef;
  }

  if($msgtype eq "powerplug_data")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    if(ref($json->{result}[0]) eq "HASH"){
      readingsBeginUpdate($hash);
      readingsBulkUpdate( $hash, "power", $json->{result}[0]{power}, 1 ) if(defined($json->{result}[0]{power}));
      readingsBulkUpdate( $hash, "temperature", $json->{result}[0]{temperature}, 1 ) if(defined($json->{result}[0]{temperature}));
      readingsBulkUpdate( $hash, "current", $json->{result}[0]{current}, 1 ) if(defined($json->{result}[0]{current}));
      readingsBulkUpdate( $hash, "power_mode", $json->{result}[0]{mode}, 1 ) if(defined($json->{result}[0]{mode}));
      readingsBulkUpdate( $hash, "power_consume_rate", $json->{result}[0]{power_consume_rate}, 1 ) if(defined($json->{result}[0]{power_consume_rate}));
      readingsBulkUpdate( $hash, "wifi_led", $json->{result}[0]{wifi_led}, 1 ) if(defined($json->{result}[0]{wifi_led}));
      readingsBulkUpdate( $hash, "power_price", $json->{result}[0]{power_price}, 1 ) if(defined($json->{result}[0]{power_price}));
      readingsBulkUpdate( $hash, "voltage", $json->{result}[0]{voltage}, 1 ) if(defined($json->{result}[0]{voltage}));
      readingsBulkUpdate( $hash, "power_factor", $json->{result}[0]{power_factor}, 1 ) if(defined($json->{result}[0]{power_factor}));
      readingsBulkUpdate( $hash, "elec_leakage", $json->{result}[0]{elec_leakage}, 1 ) if(defined($json->{result}[0]{elec_leakage}));
      readingsBulkUpdate( $hash, "usb_power", $json->{result}[0]{usb_power}, 1 ) if(defined($json->{result}[0]{usb_power}));
      readingsBulkUpdate( $hash, "load_power", $json->{result}[0]{load_power}, 1 ) if(defined($json->{result}[0]{load_power}));
      readingsBulkUpdate( $hash, "usb_power", ($json->{result}[0]{usb_on} eq "0" ? 'off' : 'on' ), 1 ) if(defined($json->{result}[0]{usb_on}));
      #readingsBulkUpdate( $hash, "setting", (($json->{result}[0]{setting} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{setting}));
      readingsEndUpdate($hash,1);
    } else {
      readingsBeginUpdate($hash);
      readingsBulkUpdate( $hash, "power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
      readingsBulkUpdate( $hash, "temperature", $json->{result}[1], 1 ) if(defined($json->{result}[1]));
      readingsBulkUpdate( $hash, "current", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
      readingsBulkUpdate( $hash, "power_mode", $json->{result}[3], 1 ) if(defined($json->{result}[3]));
      readingsBulkUpdate( $hash, "power_consume_rate", $json->{result}[4], 1 ) if(defined($json->{result}[4]));
      readingsBulkUpdate( $hash, "wifi_led", $json->{result}[5], 1 ) if(defined($json->{result}[5]));
      readingsBulkUpdate( $hash, "power_price", $json->{result}[6], 1 ) if(defined($json->{result}[6]));
      readingsBulkUpdate( $hash, "voltage", $json->{result}[7], 1 ) if(defined($json->{result}[7]));
      readingsBulkUpdate( $hash, "power_factor", $json->{result}[8], 1 ) if(defined($json->{result}[8]));
      readingsBulkUpdate( $hash, "elec_leakage", $json->{result}[9], 1 ) if(defined($json->{result}[9]));
      readingsBulkUpdate( $hash, "usb_power", $json->{result}[10], 1 ) if(defined($json->{result}[10]));
      readingsBulkUpdate( $hash, "load_power", $json->{result}[11], 1 ) if(defined($json->{result}[11]));
      readingsBulkUpdate( $hash, "usb_power", ($json->{result}[12] eq "0" ? 'off' : 'on' ), 1 ) if(defined($json->{result}[12]));
      readingsEndUpdate($hash,1);
    }
    return undef;
  }

  if($msgtype eq "powerplug_power")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsSingleUpdate( $hash, "load_power", sprintf( "%.2f" ,int($json->{result}[0])/100), 1 ) if(defined($json->{result}[0]));
    return undef;
  }

    #{ "result": [ { "msg_ver": 3, "msg_seq": 4, "state": 8, "battery": 100, "clean_time": 3, "clean_area": 0, "error_code": 0, "map_present": 0, "in_cleaning": 0, "fan_power": 10, "dnd_enabled": 1 } ], "id": 1201 }
    #{"id":8493504,"result":[{"msg_ver":2,"msg_seq":13,"state":8,"battery":100,"clean_time":338,"clean_area":2520000,"error_code":0,"map_present":1,"in_cleaning":0,"in_returning":0,"in_fresh_state":1,"lab_status":1,"fan_power":60,"dnd_enabled":0}]}
  if($msgtype eq "get_status")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    return undef if(ref($json->{result}[0]) ne "HASH");

    if (defined($json->{result}[0]{events})) {
      readingsSingleUpdate( $hash, "event", $json->{result}[0]{events}[0], 1 ) if(defined($json->{result}[0]{events}[0]));
    }

    my $laststate = ReadingsVal($name, "state","-");
    if(($laststate ne "Docked" && $laststate ne "Charging") && defined($json->{result}[0]{state}) && $json->{result}[0]{state} eq "8")
    {
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "get_clean_summary";
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_clean_summary","params":[""]}' );
    }
    readingsBeginUpdate($hash);
    #readingsBulkUpdate( $hash, "msg_ver", $json->{result}[0]{msg_seq}, 1 ) if(defined($json->{result}[0]{battery}));
    #readingsBulkUpdate( $hash, "msg_seq", $json->{result}[0]{msg_seq}, 1 ) if(defined($json->{result}[0]{msg_seq}));
    if(defined($json->{result}[0]{error_code}) && $json->{result}[0]{error_code} ne "0")
    {
      readingsBulkUpdate( $hash, "state", "Error", 1 );
    } elsif(defined($json->{result}[0]{state}) && defined($json->{result}[0]{battery}) && $json->{result}[0]{battery} eq "100" && $json->{result}[0]{state} eq "8")
    {
      readingsBulkUpdate( $hash, "state", "Docked", 1 );
    } elsif(defined($json->{result}[0]{state})) {
      readingsBulkUpdate( $hash, "state", $vacuum_states{$json->{result}[0]{state}}, 1 );
    }
    readingsBulkUpdate( $hash, "batteryPercent", $json->{result}[0]{battery}, 1 ) if(defined($json->{result}[0]{battery}));
    readingsBulkUpdate( $hash, "batteryState", int($json->{result}[0]{battery})<20 ? "low" : "ok", 1 ) if(defined($json->{result}[0]{battery}));
    readingsBulkUpdate( $hash, "last_clean_time", sprintf( "%.2f" ,int($json->{result}[0]{clean_time})/3600), 1) if(defined($json->{result}[0]{clean_time}));#sprintf( "%.1f", int($json->{result}[0]{clean_time})/3600), 1 );
    readingsBulkUpdate( $hash, "last_clean_area", sprintf( "%.2f" ,int($json->{result}[0]{clean_area})/1000000), 1 ) if(defined($json->{result}[0]{clean_area}));
    readingsBulkUpdate( $hash, "error_code", $vacuum_errors{$json->{result}[0]{error_code}}, 1 ) if(defined($json->{result}[0]{error_code}));
    readingsBulkUpdate( $hash, "map_present", (($json->{result}[0]{map_present} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{map_present}));
    readingsBulkUpdate( $hash, "in_cleaning", (($json->{result}[0]{in_cleaning} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{in_cleaning})); #not working or used for something else
    readingsBulkUpdate( $hash, "in_returning", (($json->{result}[0]{in_returning} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{in_returning}));
    readingsBulkUpdate( $hash, "in_fresh_state", (($json->{result}[0]{in_fresh_state} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{in_fresh_state}));
    readingsBulkUpdate( $hash, "lab_status", (($json->{result}[0]{lab_status} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{lab_status}));
    readingsBulkUpdate( $hash, "fan_power", $json->{result}[0]{fan_power}, 1 ) if(defined($json->{result}[0]{fan_power}));
    readingsBulkUpdate( $hash, "dnd", (($json->{result}[0]{dnd_enabled} ne "0")?"on":"off"), 1 ) if(defined($json->{result}[0]{dnd_enabled}));
    if(defined($json->{result}[0]{fan_power}) && int($json->{result}[0]{fan_power}) > 100) {
      my $cleaning_int = int($json->{result}[0]{fan_power});
      my $cleaningmode = ($cleaning_int <= 0) ? "off" : ($cleaning_int == 101) ? "quiet" : ($cleaning_int == 102) ? "balanced" : ($cleaning_int == 103) ? "turbo" : ($cleaning_int == 104) ? "max" : ($cleaning_int == 105) ? "mop" : ($cleaning_int == 106) ? "auto" : "unknown";
      readingsBulkUpdate( $hash, "cleaning_mode", $cleaningmode, 1 );
    } elsif(defined($json->{result}[0]{fan_power})) {
      my $cleaning_int = int($json->{result}[0]{fan_power});
      my $cleaningmode = ($cleaning_int <= 0) ? "off" : ($cleaning_int > 89) ? "max" : ($cleaning_int > 74) ? "turbo" : ($cleaning_int > 40) ? "balanced" : ($cleaning_int > 10) ? "quiet" : "mop";
      readingsBulkUpdate( $hash, "cleaning_mode", $cleaningmode, 1 );
    }
    readingsBulkUpdate( $hash, "water_box_carriage_status", (($json->{result}[0]{water_box_carriage_status} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{water_box_carriage_status}));
    readingsBulkUpdate( $hash, "water_box_status", (($json->{result}[0]{water_box_status} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{water_box_status}));
    readingsBulkUpdate( $hash, "water_box_mode", $vacuum_waterbox{$json->{result}[0]{water_box_mode}}, 1) if(defined($json->{result}[0]{water_box_mode}));
    readingsBulkUpdate( $hash, "mop_forbidden_enable", (($json->{result}[0]{mop_forbidden_enable} ne "0")?"yes":"no"), 1 ) if(defined($json->{result}[0]{mop_forbidden_enable}));
    readingsBulkUpdate( $hash, "lock_status", (($json->{result}[0]{lock_status} ne "0")?"on":"off"), 1 ) if(defined($json->{result}[0]{lock_status}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "get_consumable")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    return undef if(ref($json->{result}[0]) ne "HASH");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "consumables_filter", int(( ( (150*3600) - int($json->{result}[0]{filter_work_time}) )/(150*3600)) *100), 1 ) if(defined($json->{result}[0]{filter_work_time}));#sprintf( "%.1f", int($json->{result}[0]{filter_work_time})/3600), 1 );
    readingsBulkUpdate( $hash, "consumables_side_brush", int(( ( (200*3600) - int($json->{result}[0]{side_brush_work_time}) )/(200*3600)) *100), 1 ) if(defined($json->{result}[0]{side_brush_work_time}));#sprintf( "%.1f", int($json->{result}[0]{side_brush_work_time})/3600), 1 );
    readingsBulkUpdate( $hash, "consumables_main_brush", int(( ( (300*3600) - int($json->{result}[0]{main_brush_work_time}) )/(300*3600)) *100), 1 ) if(defined($json->{result}[0]{main_brush_work_time}));#sprintf( "%.1f", int($json->{result}[0]{main_brush_work_time})/3600), 1 );
    readingsBulkUpdate( $hash, "consumables_sensors", int(( ( (30*3600) - int($json->{result}[0]{sensor_dirty_time}) )/(30*3600)) *100), 1 ) if(defined($json->{result}[0]{sensor_dirty_time}));#sprintf( "%.1f", int($json->{result}[0]{sensor_dirty_time})/3600), 1 );
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "get_sound_volume")
  {
    return undef if(!defined($json->{result}));
    readingsSingleUpdate( $hash, "volume", "100", 1) if(($json->{result} eq "unknown_method") || (ref($json->{result}) ne "ARRAY" && $json->{result} eq "0"));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsSingleUpdate( $hash, "volume", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    return undef;
  }
  if($msgtype eq "get_carpet_mode")
  {
    return undef if(!defined($json->{result}));
    readingsSingleUpdate( $hash, "carpet_mode", "off", 1) if(($json->{result} eq "unknown_method") || (ref($json->{result}) ne "ARRAY" && $json->{result} eq "0"));
    return undef if(ref($json->{result}) ne "ARRAY");
    return undef if(ref($json->{result}[0]) ne "HASH");
    readingsSingleUpdate( $hash, "carpet_mode", ($json->{result}[0]{enable} eq "0" ? "off" : "on"), 1 ) if(defined($json->{result}[0]{enable}));
    readingsSingleUpdate( $hash, "carpet_high", $json->{result}[0]{current_high}, 1 ) if(defined($json->{result}[0]{current_high}));
    readingsSingleUpdate( $hash, "carpet_low", $json->{result}[0]{current_low}, 1 ) if(defined($json->{result}[0]{current_low}));
    readingsSingleUpdate( $hash, "carpet_stall_time", $json->{result}[0]{stall_time}, 1 ) if(defined($json->{result}[0]{stall_time}));
    readingsSingleUpdate( $hash, "carpet_integral", $json->{result}[0]{current_integral}, 1 ) if(defined($json->{result}[0]{current_integral}));
    return undef;
  }
  if($msgtype eq "app_get_locale")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    return undef if(ref($json->{result}[0]) ne "HASH");
    readingsSingleUpdate( $hash, "app_logserver", $json->{result}[0]{logserver}, 1 ) if(defined($json->{result}[0]{logserver}));
    readingsSingleUpdate( $hash, "app_wifiplan", $json->{result}[0]{wifiplan}, 1 ) if(defined($json->{result}[0]{wifiplan}) && $json->{result}[0]{wifiplan} ne "");
    readingsSingleUpdate( $hash, "app_timezone", $json->{result}[0]{timezone}, 1 ) if(defined($json->{result}[0]{timezone}));
    readingsSingleUpdate( $hash, "app_bom", $json->{result}[0]{bom}, 1 ) if(defined($json->{result}[0]{bom}));
    readingsSingleUpdate( $hash, "app_language", $json->{result}[0]{language}, 1 ) if(defined($json->{result}[0]{language}));
    readingsSingleUpdate( $hash, "app_name", $json->{result}[0]{name}, 1 ) if(defined($json->{result}[0]{name}));
    readingsSingleUpdate( $hash, "app_location", $json->{result}[0]{location}, 1 ) if(defined($json->{result}[0]{location}));
    return undef;
  }
  if($msgtype eq "get_fw_features")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    my $featurestring = "";
    $featurestring = $json->{result}[0] if(defined($json->{result}[0]));
    my $i = 1;
    while(defined($json->{result}[$i])){
      $featurestring .= ",";
      $featurestring .= $json->{result}[$i];
      $i++;
    }
    readingsSingleUpdate( $hash, "device_fw_features", $featurestring, 1 );
    return undef;
  }
  if($msgtype eq "get_custom_mode")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsSingleUpdate( $hash, "fan_power", $json->{result}[0], 1 ) if(defined($json->{result}[0]));
    if(defined($json->{result}[0]) && int($json->{result}[0]) > 100) {
      my $cleaning_int = int($json->{result}[0]);
      my $cleaningmode = ($cleaning_int <= 0) ? "off" : ($cleaning_int == 101) ? "quiet" : ($cleaning_int == 102) ? "balanced" : ($cleaning_int == 103) ? "turbo" : ($cleaning_int == 104) ? "max" : ($cleaning_int == 105) ? "mop" : ($cleaning_int == 106) ? "auto" : "unknown";
      readingsSingleUpdate( $hash, "cleaning_mode", $cleaningmode, 1 );
    } elsif(defined($json->{result}[0])) {
      my $cleaning_int = int($json->{result}[0]);
      my $cleaningmode = ($cleaning_int <= 0) ? "off" : ($cleaning_int > 89) ? "max" : ($cleaning_int > 74) ? "turbo" : ($cleaning_int > 40) ? "balanced" : ($cleaning_int > 10) ? "quiet" : "mop";
      readingsSingleUpdate( $hash, "cleaning_mode", $cleaningmode, 1 );
    }
    return undef;
  }
  if($msgtype eq "get_clean_summary")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "total_clean_time", sprintf("%.2f",int($json->{result}[0])/3600), 1 ) if(defined($json->{result}[0]));
    readingsBulkUpdate( $hash, "total_clean_area", sprintf( "%.2f" ,int($json->{result}[1])/1000000), 1 ) if(defined($json->{result}[1]));
    readingsBulkUpdate( $hash, "total_cleans", $json->{result}[2], 1 ) if(defined($json->{result}[2]));
    readingsEndUpdate($hash,1);


    my $i = 0;
    foreach my $cleanrecord (@{$json->{result}[3]}) {
      next if($i > 9);
      my $packetid = $hash->{helper}{packetid};
      $hash->{helper}{packetid} = $packetid+1;
      $hash->{helper}{packet}{$packetid} = "get_clean_record".$i;
      $hash->{helper}{day}{$packetid} = $cleanrecord;
      $hash->{helper}{history}{$packetid} = $i++;
      XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_clean_record","params":['.$cleanrecord.']}' );
    }

    $hash->{helper}{historydays} = $i;
    $hash->{helper}{cleanrecord} = 0;

    if($i == 0)
    {
      while($i < 10)
      {
        fhem( "deletereading $name history_".$i ) if(defined(ReadingsVal($name,"history_".$i,undef)));
        $i++;
      }
    }


    return undef;
  }

  if($msgtype =~ /get_clean_record/)
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");

    my $daynumber = substr($msgtype, -1);
    my $day = $hash->{helper}{day}{$msgid};
    my $history = $hash->{helper}{history}{$msgid};
    delete $hash->{helper}{day}{$msgid};
    delete $hash->{helper}{history}{$msgid};

    readingsBeginUpdate($hash);

    my $recordnumber = $hash->{helper}{cleanrecord};

    foreach my $cleanrecord (@{$json->{result}}) {
      my @cleanrecord = @{$cleanrecord};
      $recordnumber = $hash->{helper}{cleanrecord};
      #Log3 $name, 2, "$name: $history $day $daynumber \n".Dumper($cleanrecord);
      readingsBulkUpdate( $hash, "last_timestamp", $cleanrecord[0], 1 ) if($recordnumber == 0 && defined($json->{result}[0]));
      readingsBulkUpdate( $hash, "history_".$recordnumber, FmtDateTime($cleanrecord[0]).": ".sprintf( "%.2f" ,int($cleanrecord[3])/1000000)."m² in ".sprintf("%.2f",int($cleanrecord[2])/3600)."h, ".(($cleanrecord[5] eq "0")?"not finished":"finished cleaning"), 1 ) if($recordnumber < 10 && defined($json->{result}[0]));
      $hash->{helper}{cleanrecord}++;
    }
    readingsEndUpdate($hash,1);

    if($daynumber == $hash->{helper}{historydays}-1)
    {
      $recordnumber = $hash->{helper}{cleanrecord};
      while($recordnumber < 10)
      {
        fhem( "deletereading $name history_".$recordnumber ) if(defined(ReadingsVal($name,"history_".$recordnumber,undef)));
        $recordnumber++;
      }
    }

    return undef;
  }

  if($msgtype eq "get_timer")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    $hash->{helper}{timers} = 0;
    my $i=1;
    foreach my $timerelement (@{$json->{result}}) {
      next if($i>9);
      $hash->{helper}{timers} = $i;
      my @timerstring = @{$timerelement};

      my $timestamp = $timerstring[0];
      my $timerstate = $timerstring[1];
      my $timercron = $timerstring[2][0];
      my $timerprogram = $timerstring[2][1][0] if(defined($timerstring[2][1][0]));
      my $timerpower = $timerstring[2][1][1] if(defined($timerstring[2][1][1]));
      $hash->{helper}{"timer".$i} = $timestamp if(defined($timestamp));
      $hash->{helper}{"timer".$i."_cron"} = $timercron if(defined($timercron));
      readingsBeginUpdate($hash);
      #readingsBulkUpdate( $hash, "timer".$i."_created", FmtDateTime(int($timestamp/1000)), 1 ) if(defined($timestamp));
      readingsBulkUpdate( $hash, "timer".$i, $timerstate, 1 ) if(defined($timerstate));
      my @timestring = split(" ",$timercron);
      readingsBulkUpdate( $hash, "timer".$i."_time", sprintf("%02d",$timestring[1]).":".sprintf("%02d",$timestring[0]), 1 ) if(defined($timestring[1]));

      if(defined($timestring[3]) && $timestring[2] ne "*")
      {
        readingsBulkUpdate( $hash, "timer".$i."_days", sprintf("%02d",$timestring[2])." ".sprintf("%02d",$timestring[3]), 1 );
      }
      elsif(defined($timestring[4]) && $timestring[4] ne "*")
      {
        if($timestring[4] eq "0,1,2,3,4,5,6")
        {
          readingsBulkUpdate( $hash, "timer".$i."_days", "all", 1 );
        }
        else
        {
          my @days = ();
          push( @days, "Mo" ) if($timestring[4] =~ /1/);
          push( @days, "Tu" ) if($timestring[4] =~ /2/);
          push( @days, "We" ) if($timestring[4] =~ /3/);
          push( @days, "Th" ) if($timestring[4] =~ /4/);
          push( @days, "Fr" ) if($timestring[4] =~ /5/);
          push( @days, "Sa" ) if($timestring[4] =~ /6/);
          push( @days, "Su" ) if($timestring[4] =~ /0/);
          readingsBulkUpdate( $hash, "timer".$i."_days", join(",", @days), 1 );
        }
      }
      elsif(defined($timestring[4]) && $timestring[4] eq "*")
      {
        readingsBulkUpdate( $hash, "timer".$i."_days", "all", 1 );
      }
      else
      {
        fhem( "deletereading $name timer".$i."_days" );# if(defined($timestring[4]) && $timestring[4] eq "*");
      }

	  if(defined($timerprogram))
	  {
        readingsBulkUpdate( $hash, "timer".$i."_program", $timerprogram, 1 );
	  }
      else
      {
        fhem( "deletereading $name timer".$i."_program" );
      }

	  if(defined($timerpower))
	  {
        readingsBulkUpdate( $hash, "timer".$i."_power", $timerpower, 1 );
	  }
      else
      {
        fhem( "deletereading $name timer".$i."_power" );
      }

      readingsEndUpdate($hash,1);
      $i++;
    }
    for(;$i<10;$i++)
    {
      fhem( "deletereading $name timer".$i.".*" );
    }
    return undef;
  }
  if($msgtype eq "get_dnd_timer")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "dnd_enabled", (($json->{result}[0]{enabled} ne "0")?"on":"off"), 1 ) if(defined($json->{result}[0]{enabled}));
    readingsBulkUpdate( $hash, "dnd_start", sprintf("%02d",$json->{result}[0]{start_hour}).":".sprintf("%02d",$json->{result}[0]{start_minute}), 1 ) if(defined($json->{result}[0]{start_hour}) && defined($json->{result}[0]{start_minute}));
    readingsBulkUpdate( $hash, "dnd_end", sprintf("%02d",$json->{result}[0]{end_hour}).":".sprintf("%02d",$json->{result}[0]{end_minute}), 1 ) if(defined($json->{result}[0]{end_hour}) && defined($json->{result}[0]{end_minute}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "get_log_upload_status")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    return undef if(ref($json->{result}[0]) ne "HASH");
    readingsSingleUpdate( $hash, "log_upload_status", $json->{result}[0]{log_upload_status}, 1 ) if(defined($json->{result}[0]{log_upload_status}));
    return undef;
  }

  if($msgtype eq "get_serial_number")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    return readingsSingleUpdate( $hash, "serial_number", $json->{result}[0], 1 ) if(defined($json->{result}[0]) && ref($json->{result}[0]) eq "");
    readingsSingleUpdate( $hash, "serial_number", $json->{result}[0]{serial_number}, 1 ) if(defined($json->{result}[0]{serial_number}));
    return undef;
  }
  if($msgtype eq "wifi_stats")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "HASH");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "wifi_state", lc($json->{result}{state}), 1 ) if(defined($json->{result}{state}));
    readingsBulkUpdate( $hash, "wifi_auth_fail_count", $json->{result}{auth_fail_count}, 1 ) if(defined($json->{result}{auth_fail_count}));
    readingsBulkUpdate( $hash, "wifi_dhcp_fail_count", $json->{result}{dhcp_fail_count}, 1 ) if(defined($json->{result}{dhcp_fail_count}));
    readingsBulkUpdate( $hash, "wifi_conn_fail_count", $json->{result}{conn_fail_count}, 1 ) if(defined($json->{result}{conn_fail_count}));
    readingsBulkUpdate( $hash, "wifi_conn_success_count", $json->{result}{conn_success_count}, 1 ) if(defined($json->{result}{conn_success_count}));
    readingsBulkUpdate( $hash, "wifi_conn_success_count", $json->{result}{conn_succes_count}, 1 ) if(defined($json->{result}{conn_succes_count}));
    readingsEndUpdate($hash,1);
    return undef;
  }
  if($msgtype eq "device_info")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "HASH");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "device_uptime", sprintf("%.2f",int($json->{result}{life})/3600), 1 ) if(defined($json->{result}{life}));
    readingsBulkUpdate( $hash, "device_firmware", $json->{result}{fw_ver}, 1 ) if(defined($json->{result}{fw_ver}));
    readingsBulkUpdate( $hash, "wifi_rssi", $json->{result}{ap}{rssi}, 1 ) if(defined($json->{result}{ap}{rssi}));
    readingsEndUpdate($hash,1);
    $hash->{model} = $json->{result}{model} if(defined($json->{result}{model}));
    $hash->{mac} = $json->{result}{mac} if(defined($json->{result}{mac}));
    $hash->{token} = $json->{result}{token} if(defined($json->{result}{token}));
    $hash->{wifi_firmware} = $json->{result}{wifi_fw_ver} if(defined($json->{result}{wifi_fw_ver}));
    $hash->{mcu_firmware} = $json->{result}{mcu_fw_ver} if(defined($json->{result}{mcu_fw_ver}));
    $hash->{hardware} = $json->{result}{hw_ver} if(defined($json->{result}{hw_ver}));
    return undef;
  }
  if($msgtype eq "get_current_sound")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    return readingsSingleUpdate( $hash, "current_sound", $json->{result}[0], 1 ) if(defined($json->{result}[0]) && ref($json->{result}[0]) eq "");
    return undef if(ref($json->{result}[0]) ne "HASH");
    readingsSingleUpdate( $hash, "current_sound", ($json->{result}[0]{sid_in_use} eq "3" ? "english" : "chinese"), 1 ) if(defined($json->{result}[0]{sid_in_use}));
    return undef;
  }
  if($msgtype eq "get_timezone")
  {
    return undef if(!defined($json->{result}));
    return undef if(ref($json->{result}) ne "ARRAY");
    return readingsSingleUpdate( $hash, "timezone", $json->{result}[0], 1 ) if(defined($json->{result}[0]) && ref($json->{result}[0]) eq "");
    readingsSingleUpdate( $hash, "timezone", $json->{result}[0]{olson}, 1 ) if(defined($json->{result}[0]) && ref($json->{result}[0]) eq "HASH" && defined($json->{result}[0]{olson}));
    return undef;
  }

  Log3 $name, 5, "$name: parse result for ".$json->{id}." is ".$json->{result} if($json->{result});

  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetSpeed", $hash) if($msgtype eq "set_level");
  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_light");
  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_toggle");
  InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "power_on" || $msgtype eq "power_off");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_poweroff_time");

  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "app_start" || $msgtype eq "app_spot"  || $msgtype eq "app_zoned_clean" || $msgtype eq "resume_zoned_clean");
  return InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "app_stop" || $msgtype eq "app_pause" || $msgtype eq "app_goto_target");
  return InternalTimer( gettimeofday() + 60, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "app_charge");

  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "app_rc_start");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "app_rc_end");

  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_angle");
  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_angle_enable");

  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_tilt");
  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_tilt_enable");

  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_oscillate_enable");

  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetSettings", $hash) if($msgtype eq "set_limit_hum");

  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "nowarn" || $msgtype eq "ack");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "power_mode" || $msgtype eq "power_price" || $msgtype eq "wifi_led" || $msgtype eq "usb_power" || $msgtype eq "rt_power");


  return readingsSingleUpdate( $hash, "power", "off", 1 ) if($msgtype eq "power_off");
  return readingsSingleUpdate( $hash, "power", "on", 1 ) if($msgtype eq "power_on");
  return readingsSingleUpdate( $hash, "mode", "natural", 1 ) if($msgtype eq "mode_natural");
  return readingsSingleUpdate( $hash, "mode", "straight", 1 ) if($msgtype eq "mode_speed");
  return readingsSingleUpdate( $hash, "mode", "idle", 1 ) if($msgtype eq "mode_idle");
  return readingsSingleUpdate( $hash, "mode", "auto", 1 ) if($msgtype eq "mode_auto");
  return readingsSingleUpdate( $hash, "mode", "sleep", 1 ) if($msgtype eq "mode_sleep");
  return readingsSingleUpdate( $hash, "mode", "favorite", 1 ) if($msgtype eq "mode_favorite");
  return readingsSingleUpdate( $hash, "mode", "silent", 1 ) if($msgtype eq "mode_silent");
  return readingsSingleUpdate( $hash, "mode", "medium", 1 ) if($msgtype eq "mode_medium");
  return readingsSingleUpdate( $hash, "mode", "high", 1 ) if($msgtype eq "mode_high");
  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetSpeed", $hash) if($msgtype eq "set_level_favorite" || $msgtype eq "set_custom_mode");
  return readingsSingleUpdate( $hash, "buzzer", "off", 1 ) if($msgtype eq "buzzer_off");
  return readingsSingleUpdate( $hash, "buzzer", "on", 1 ) if($msgtype eq "buzzer_on");
  return readingsSingleUpdate( $hash, "led", "on", 1 ) if($msgtype eq "led_on");
  return readingsSingleUpdate( $hash, "led", "bright", 1 ) if($msgtype eq "led_bright");
  return readingsSingleUpdate( $hash, "led", "dim", 1 ) if($msgtype eq "led_dim");
  return readingsSingleUpdate( $hash, "led", "off", 1 ) if($msgtype eq "led_off");
  return readingsSingleUpdate( $hash, "turbo", "off", 1 ) if($msgtype eq "turbo_off");
  return readingsSingleUpdate( $hash, "turbo", "on", 1 ) if($msgtype eq "turbo_on");
  return readingsSingleUpdate( $hash, "child_lock", "off", 1 ) if($msgtype eq "child_lock_off");
  return readingsSingleUpdate( $hash, "child_lock", "on", 1 ) if($msgtype eq "child_lock_on");
  return readingsSingleUpdate( $hash, "dry", "off", 1 ) if($msgtype eq "dry_off");
  return readingsSingleUpdate( $hash, "dry", "on", 1 ) if($msgtype eq "dry_on");
  return InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetSettings", $hash) if($msgtype eq "set_sleep_time");
  return readingsSingleUpdate( $hash, "sleep_auto", "close", 1 ) if($msgtype eq "sleep_close");
  return readingsSingleUpdate( $hash, "sleep_auto", "single", 1 ) if($msgtype eq "sleep_single");
  InternalTimer( gettimeofday() + 2, "XiaomiDevice_GetDnd", $hash) if($msgtype eq "set_dnd_timer");
  return InternalTimer( gettimeofday() + 30, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_dnd_timer");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetSettings", $hash) if($msgtype eq "set_timer" || $msgtype eq "upd_timer" || $msgtype eq "del_timer");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetSettings", $hash) if($msgtype eq "reset_consumable");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetSettings", $hash) if($msgtype eq "change_sound_volume");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetSettings", $hash) if($msgtype eq "set_carpet_mode");
  return InternalTimer( gettimeofday() + 30, "XiaomiDevice_GetUpdate", $hash) if($msgtype eq "set_dnd_timer");
  return InternalTimer( gettimeofday() + 5, "XiaomiDevice_GetSettings", $hash) if($msgtype eq "set_water_box_custom_mode");


  if($msgtype eq "wifi_setup")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "stop_diag_mode";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"miIO.stop_diag_mode","params":""}' );
    return undef;
  }
  return InternalTimer( gettimeofday() + 30, "XiaomiDevice_connect", $hash) if($msgtype eq "stop_diag_mode");

  if($msgtype eq "set_timezone")
  {
    my $packetid = $hash->{helper}{packetid};
    $hash->{helper}{packetid} = $packetid+1;
    $hash->{helper}{packet}{$packetid} = "get_timezone";
    XiaomiDevice_WriteJSON($hash, '{"id":'.$packetid.',"method":"get_timezone","params":""}' );
    return undef;
  }


  Log3 $name, 3, "$name: type ".$msgtype." not implemented\n".Dumper($json);


  return undef;
}

#####################################
sub XiaomiDevice_connect($)
{
    my $hash = shift;
    my $name = $hash->{NAME};

    XiaomiDevice_disconnect($hash);

    Log3 $name, 2, "$name: connecting";

    my $sock = IO::Socket::INET-> new (
        PeerHost => $hash->{helper}{ip},
        PeerPort => $hash->{helper}{port},
        Blocking => 0,
        Proto => 'udp',
        Broadcast => 1,
        Timeout => 2);

    if ($sock)
    {
        Log3 $name, 3, "$name: initialized";

        $hash->{helper}{ConnectionState} = "initialized";


        $hash->{FD} = $sock->fileno();
        $hash->{CD} = $sock;

        $selectlist{$name} = $hash;

        XiaomiDevice_initSend($hash);

        InternalTimer( gettimeofday() + 4, "XiaomiDevice_GetDeviceDetails", $hash);
        InternalTimer( gettimeofday() + 7, "XiaomiDevice_GetSettings", $hash);
        InternalTimer( gettimeofday() + 10, "XiaomiDevice_GetUpdate", $hash);
    }
    else
    {
        Log3 $name, 1, "$name: connect to device failed";
        readingsSingleUpdate($hash, "state", "disconnected", 1) if($hash->{helper}{ConnectionState} ne "disconnected");
        $hash->{helper}{ConnectionState} = "disconnected";
        $hash->{helper}{delay} += 600;
        InternalTimer( gettimeofday() + $hash->{helper}{delay}, "XiaomiDevice_connect", $hash);
    }

    return undef;
}

#####################################

sub XiaomiDevice_disconnect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  #delete($hash->{helper}{dev});
  #delete($hash->{helper}{id});

  Log3 $name, 3, "$name: disconnecting";
  $hash->{helper}{ConnectionState} = "disconnected";

  return if (!$hash->{CD});

  close($hash->{CD});
  delete($hash->{CD});

  return undef;
}
#####################################
sub XiaomiDevice_initSend($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: initSend";

  #InternalTimer(gettimeofday() + 10, "XiaomiDevice_connectFail", $hash);

  my $data = "21310020FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
  XiaomiDevice_Write($hash,pack('H*', $data));
  return undef;
}
#####################################
sub XiaomiDevice_connectFail($)
{
  my ($hash)  = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "XiaomiDevice_connectFail");

  Log3 $name, 3, "$name: connection timeout";
  readingsSingleUpdate($hash, "state", "disconnected", 1) if($hash->{helper}{ConnectionState} ne "disconnected");
  $hash->{helper}{ConnectionState} = "disconnected";
  $hash->{helper}{delay} += 120;
  InternalTimer( gettimeofday() + $hash->{helper}{delay}, "XiaomiDevice_connect", $hash);

  return undef;
}
#####################################

sub XiaomiDevice_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $data = "";
  my $socket = $hash->{CD};
  return undef if(!defined($socket));
  my $ret = $socket->recv($data,1024);


  if (!defined($ret) || length($ret) <= 0)
  {
    Log3 $name, 2, "$name: Read error";
    XiaomiDevice_disconnect($hash);
    InternalTimer(gettimeofday() + 30, "XiaomiDevice_connect", $hash);
    return undef;
  }

  if(length($data) < 32)
  {
    Log3 $name, 2, "short read length\n".unpack('H*', $data);
    return undef;
  }


  $hash->{helper}{last_read} = int(time());

  $data = unpack('H*', $data);
  my $len = substr($data,4,4);
  $len = sprintf("%d", hex($len));

  Log3 $hash, 5, "$name < ".$data." ($len)";


  my $seq = substr($data,24,8);
  $seq = sprintf("%d", hex($seq));
  $hash->{helper}{sequence} = int(time)-$seq;
  #Log3 $name, 4, "$name - recv seq ".$seq."/".int(time);


  my $dev = substr($data,16,4);
  my $id = substr($data,20,4);
  $hash->{helper}{dev} = $dev;
  $hash->{helper}{id} = $id;
  #$hash->{device_type} = $device_types{$dev};
  #$hash->{device_type} = "unknown" if(!defined($device_types{$dev}));


  if($len == 32) # token return
  {
    my $token = substr($data,-32,32);
    if(($token eq "00000000000000000000000000000000" || $token eq "ffffffffffffffffffffffffffffffff") && !defined($hash->{helper}{token}))
    {
      Log3 $name, 1, "$name: Token could not be retrieved automatically from already cloud-connected device!";
      $attr{$name}{disable} = "1";
      return undef;
    }
    Log3 $name, 3, "$name: received token: ".$token if(!defined($hash->{helper}{token}));;
    RemoveInternalTimer($hash, "XiaomiDevice_connectFail");
    $hash->{helper}{delay} = 60;

    if(!defined($hash->{helper}{token})){
      $hash->{helper}{token} = $token;
      $hash->{DEF} = $hash->{DEF}." ".$hash->{helper}{token};
    }

    return undef;
  }
  elsif($len >= 64)
  {
    $data = substr($data,64);
  }
  else{
    $data = substr($data,-$len);
  }

  if(length($data)%16 != 0)
  {
    Log3 $name, 3, "$name: decrypt length mismatch ".(length($data)%16)." ".$data;
    return undef;
  }

  if ($hash->{helper}{ConnectionState} ne "connected")
  {
    $hash->{helper}{ConnectionState} = "connected";
    readingsSingleUpdate($hash, "state", "connected", 1) if(ReadingsVal($name, "state", "") eq "disconnected");
  }

  RemoveInternalTimer($hash, "XiaomiDevice_connectFail");
  $hash->{helper}{delay} = 60;

  my $key = Digest::MD5::md5(pack('H*', $hash->{helper}{token}));
  my $iv = Digest::MD5::md5($key.pack('H*', $hash->{helper}{token}));
  my $cbc;

  if($hash->{helper}{crypt} ne "Rijndael"){
    $cbc = Crypt::CBC->new(-key => $key, -cipher => 'Crypt::Cipher::AES',-iv => $iv, -literal_key => 1, -header => "none", -keysize => 16 );
  } else {
    $Crypt::Rijndael_PP::DEFAULT_KEYSIZE = 128;
    $cbc = Crypt::CBC->new(-key => $key, -cipher => 'Crypt::Rijndael_PP',-iv => $iv, -literal_key => 1, -header => "none", -keysize => 16 );
  }
  my $return = 00000000000000000000000000000000;
  if(length($data)%32 == 0)
  {
    $return = $cbc->decrypt_hex($data);
  }

  Log3 $name, 5, "$name: decrypted \n".$return;
  if( length($data) == 48 && $return !~ m/^{.*}/ )
  {
    Log3 $name, 3, "$name: Internet access is blocked, no device info available";
    $hash->{mac} = "LOCALNETWORK" if(!defined($hash->{mac}));
    $hash->{model} = "rockrobo.vacuum" if(!defined($hash->{model}));
    return undef;
  }
  XiaomiDevice_ParseJSON($hash,$return);
  return undef;
}


sub XiaomiDevice_Write($$)
{
  my ($hash,$msg)  = @_;
  my $name = $hash->{NAME};

  unless($hash->{CD})
  {
    Log3 $name, 3, "$name: socket not connected";
    XiaomiDevice_connect($hash);
    return undef;
  }

  my $sock = $hash->{CD};
  if(!$sock){
    Log3 $hash, 2, "$name: socket error";
    return undef;
  }
  if(!($sock->send($msg)))
  {
    # Send failed
    Log3 $hash, 2, "$name Send FAILED";
    readingsSingleUpdate($hash, "state", "disconnected", 1) if($hash->{helper}{ConnectionState} ne "disconnected");
    $hash->{helper}{ConnectionState} = "disconnected";
  }
  else
  {
    # Send successful
    Log3 $hash, 5, "$name Send SUCCESS";
    if(length($msg) > 40){
      my $currentstate = ReadingsVal($name,"state","-");
      if(lc($currentstate) =~ /clean/ || lc($currentstate) =~ /goto/){
        InternalTimer(gettimeofday() + 150, "XiaomiDevice_connectFail", $hash);
        #Log3 $hash, 5, "$name: cleaning, higher timeout";
      } else {
        InternalTimer(gettimeofday() + 45, "XiaomiDevice_connectFail", $hash);
      }
    }
  }
  Log3 $hash, 5, "$name > ".unpack('H*',$msg);


  return undef;
}
#####################################


sub XiaomiDevice_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef if(!defined($defs{$name}));
  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "intervalData" || $attrName eq "intervalSettings");
  $attrVal = 10 if($attrName eq "intervalData" && $attrVal < 10 );
  $attrVal = 60 if($attrName eq "intervalSettings" && $attrVal < 60 );

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      RemoveInternalTimer($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      XiaomiDevice_Init($hash);
    }
    return undef;
  }

  if($attrName eq "zone_names" || $attrName eq "point_names" || $attrName eq "map_names" || $attrName eq "segment_names") {
    my $hash = $defs{$name};
    InternalTimer( gettimeofday() + 2, "XiaomiDevice_ReadZones", $hash);
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return undef;
}

sub XiaomiDevice_DbLog_splitFn($) {
  my ($event) = @_;
  my ($reading, $value, $unit) = "";

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value = $parts[1];

  $unit = "";
  $unit = "%" if($reading eq "filter");
  $unit = "%" if($reading =~ /humidity/);
  $unit = "µg/m³" if($reading =~ /pm25/);
  $unit = "rpm" if($reading =~ /speed/);
  $unit = "˚C" if($reading =~ /temperature/);
  $unit = "h" if($reading =~ /usage/);
  $unit = "h" if($reading =~ /_life/);
  $unit = "h" if($reading =~ /_used/);
  $unit = "m³" if($reading eq "filter_volume");
  $unit = "l" if($reading eq "water_volume");
  $unit = "%" if($reading =~ /depth/);
  $unit = "%" if($reading =~ /batteryPercent/);
  $unit = "%" if($reading =~ /fan_power/);
  $unit = "h" if($reading =~ /clean_time/);
  $unit = "m²" if($reading =~ /clean_area/);
  $unit = "%" if($reading =~ /consumables_/);
  $unit = "W" if($reading eq "load_power");


  Log3 "dbsplit", 5, "xiaomi dbsplit: ".$event."  $reading: $value $unit" if(defined($value));
  Log3 "dbsplit", 5, "xiaomi dbsplit: ".$event."  $reading" if(!defined($value));

  return ($reading, $value, $unit);
}

1;

=pod
=item device
=item summary Connect to Xiaomi Smart home devices with WiFi control
=begin html

<a name="XiaomiDevice"></a>
<h3>XiaomiDevice</h3>
<ul>
  This modul connects to the Xiaomi Vacuums, Air Purifiers, Humidifiers, Fans and a few other devices.<br/><br/>
  <u>Required Perl Libraries:</u><br/>
  Via the package manager, install <i>libjson-perl, libdigest-md5-perl, libcrypt-cbc-perl, libcrypt-ecb-perl</i><br/>
  Via CPAN install Crypt::Cipher::AES <u>or</u> Crypt::Rijndael_PP
  <br/><br/>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; XiaomiDevice &lt;ip&gt; [&lt;token&gt;] </code>
    <br>
    Example: <code>define vacuum XiaomiDevice 192.168.178.123 12345678901234567890123456789012</code><br>
    Example: <code>define airpurifier XiaomiDevice 192.168.178.123</code>
    <br>&nbsp;
    <li><code>ip</code>
      <br>
      Local IP of the device
    </li><br>
    <li><code>token</code>
      <br>
      Token of the device (mandatory for VacuumCleaner)
    </li><br>
  </ul>
  <br>
  <b>Get</b>
   <ul>
   <li><code>data</code>
   <br>
   Manually trigger data update
   </li><br>
   <li><code>settings</code>
   <br>
   Manually read settings
   </li><br>
   <li><code>clean_summary</code>
   <br>
   Manually read clean summary data
   </li><br>
  </ul>
  <br>
  <b>Set</b>
  <ul>
  <li><code>reconnect</code>
  <br>
  Reconnect the device
  </li><br>
  <li><code>wifi_setup </code>&lt;ssid&gt; &lt;password&gt; &lt;uid&gt;
  <br>
  WiFi setup: SSID, PASSWORD and Xiaomi User ID are needed for MiHome use
  </li><br>
  <li><code>start</code> <i>(VacuumCleaner)</i>
  <br>
  Start cleaning
  </li><br>
   <li><code>spot</code> <i>(VacuumCleaner)</i>
   <br>
   Start spot cleaning
   </li><br>
  <li><code>zone</code> pointA1,pointA2,pointA3,pointA4,count [pointB1,pointB2,pointB3,pointB4,count]<i>(VacuumCleaner)</i>
  <br>
  Start zone cleaning (enter points for one or more valid zones)
  </li><br>
   <li><code>pause</code> <i>(VacuumCleaner)</i>
   <br>
   Pause cleaning
   </li><br>
   <li><code>resume</code> <i>(VacuumCleaner)</i>
   <br>
   Resume zoned cleaning when paused
   </li><br>
   <li><code>stop</code> <i>(VacuumCleaner)</i>
   <br>
   Stop cleaning
   </li><br>
   <li><code>charge</code> <i>(VacuumCleaner)</i>
   <br>
   Return to dock
   </li><br>
   <li><code>goto</code> pointX,pointY <i>(VacuumCleaner)</i>
   <br>
   Go to point X/Y (needs to be valid on the map)
   </li><br>
   <li><code>save_map</code> ?,pointX,pointY <i>(VacuumCleaner)</i>
   <br>
   Save exclusion lines/zones (needs to be valid on the map)  <br>e.g.: 1,26353,26920,27314,26042 0,25375,26490,25884,26490,25884,25860,25375,25860
   </li><br>
   <li><code>start_edit_map</code> <i>(VacuumCleaner)</i>
   <br>
   Start editing the map
   </li><br>
   <li><code>locate</code> <i>(VacuumCleaner)</i>
   <br>
   Locate the vacuum cleaner
   </li><br>
   <li><code>fan_power</code> [1..100] <i>(VacuumCleaner)</i>
   <br>
   Set suction power. (Quiet=38, Balanced=60, Turbo=77, Full Speed=90)
   </li><br>
   <li><code>remotecontrol </code> start/stop <i>(VacuumCleaner)</i>
   <br>
   Start or stop remote control mode
   </li><br>
   <li><code>move</code> direction velocity [time]   or   left/right <i>(VacuumCleaner/Fan)</i>
   <br>
   Move the vacuum in remotecontrol mode<br>
     direction: -100..100<br>
     velocity: 0..100<br>
     time: time in ms (default=1000)
   </li><br>
   <li><code>reset_consumable</code> filter/mainbrush/sidebrush/sensors <i>(VacuumCleaner)</i>
   <br>
   Reset the consumables
   </li><br>
   <li><code>timer</code> hh:mm days  <i>(VacuumCleaner)</i>
   <br>
   Set a new timer
   </li><br>
   <li><code>timerN</code> on/off/delete  <i>(VacuumCleaner)</i>
   <br>
   Enable, disable or delete an existing timer
   </li><br>
   <li><code>timerN_time</code> hh:mm  <i>(VacuumCleaner)</i>
   <br>
   Change the time for an existing timer
   </li><br>
   <li><code>timerN_days</code> days  <i>(VacuumCleaner)</i>
   <br>
   Change the days for an existing timer
   </li><br>
   <li><code>dnd_enabled</code> <i>(VacuumCleaner)</i>
   <br>
   Enable/disable DND mode
   </li><br>
   <li><code>dnd_start</code> hh:mm <i>(VacuumCleaner)</i>
   <br>
   Set DND start time
   </li><br>
   <li><code>dnd_end</code> hh:mm <i>(VacuumCleaner)</i>
   <br>
   Set DND end time
   </li><br>
   <li><code>on / off</code> <i>(AirPurifier/Humidifier/Fan)</i>
   <br>
   Turn the device on or off
   </li><br>
   <li><code>mode</code> <i>(AirPurifier/Humidifier/Fan)</i>
   <br>
   Set the device mode<br>
   AirPurifier: auto,silent,favorite<br>
   Humidifier: silent,medium,high,auto<br>
   Fan: straight,natural,sleep<br>
   </li><br>
   <li><code>favorite</code> <i>(AirPurifier)</i>
   <br>
   Set the speed for favorite mode (0..16)
   </li><br>
   <li><code>preset</code> <i>(AirPurifier)</i>
   <br>
   Set a preset from attribute preset ('mode auto')
   </li><br>
   <li><code>buzzer</code> <i>(AirPurifier/Humidifier/Fan)</i>
   <br>
   Set the buzzer (on,off)
   </li><br>
   <li><code>led</code> <i>(AirPurifier/Humidifier/Fan)</i>
   <br>
   Set the LED (on,bright,dim,off)
   </li><br>
   <li><code>child_lock</code> <i>(AirPurifier/Humidifier/Fan)</i>
   <br>
   Set the child lock (on,off)
   </li><br>
   <li><code>turbo</code> <i>(AirPurifier)</i>
   <br>
   Set the turbo mode (on,off)
   </li><br>
   <li><code>limit_hum</code> <i>(Humidifier)</i>
   <br>
   Set the target humidity (30..90%) for mode "auto"
   </li><br>
   <li><code>dry</code> <i>(Humidifier)</i>
   <br>
   Set the dry mode (on,off)
   </li><br>
  </ul>
  <br>
  <b>Readings</b>
    <ul>
    <li><code>state</code>
    <br>
    Current state<br/>
    </li><br>
    <li><code>fan_power</code> <i>(VacuumCleaner)</i>
    <br>
    Fan power in %<br/>
    </li><br>
    <li><code>error_code</code> <i>(VacuumCleaner)</i>
    <br>
    Error code<br/>
    </li><br>
    <li><code>event</code> <i>(VacuumCleaner)</i>
    <br>
    Last event (e.g., bin_full)<br/>
    </li><br>
    <li><code>consumables_X</code> <i>(VacuumCleaner)</i>
    <br>
    Consumables time remaining in %<br/>
    </li><br>
    <li><code>dnd</code> <i>(VacuumCleaner)</i>
    <br>
    Current DND mode state<br/>
    </li><br>
    <li><code>X_clean_area</code> <i>(VacuumCleaner)</i>
    <br>
    Area cleaned in m²<br/>
    </li><br>
    <li><code>X_clean_time</code> <i>(VacuumCleaner)</i>
    <br>
    Time cleaned in h<br/>
    </li><br>
    <li><code>total_cleans</code> <i>(VacuumCleaner)</i>
    <br>
    Total number of cleaning cycles<br/>
    </li><br>
    <li><code>serial_number</code> <i>(VacuumCleaner)</i>
    <br>
    Serial number of the vacuum<br/>
    </li><br>
    <li><code>timerN_X</code> <i>(VacuumCleaner)</i>
    <br>
    Timer details<br/>
    </li><br>
    <li><code>pm25</code> <i>(AirPurifier)</i>
    <br>
    PM2.5 value in µg/m³<br/>
    </li><br>
    <li><code>pm25_average</code> <i>(AirPurifier)</i>
    <br>
    Average PM2.5 value in µg/m³<br/>
    </li><br>
    <li><code>temperature</code> <i>(AirPurifier/Humidifier/Fan)</i>
    <br>
    Temperature in ˚C<br/>
    </li><br>
    <li><code>humidity</code> <i>(AirPurifier/Humidifier/Fan)</i>
    <br>
    Humidity in %<br/>
    </li><br>
    <li><code>speed</code> <i>(AirPurifier/Humidifier/Fan)</i>
    <br>
    Fan speed in rpm<br/>
    </li><br>
    <li><code>usage</code> <i>(AirPurifier)</i>
    <br>
    Usage time in h<br/>
    </li><br>
    <li><code>filter_volume</code> <i>(AirPurifier)</i>
    <br>
    Total air volume in m³<br/>
    </li><br>
    <li><code>filter</code> <i>(AirPurifier)</i>
    <br>
    Filter life in %<br/>
    </li><br>
    <li><code>load_power</code> <i>(PowerPlug)</i>
    <br>
    Power consumption in W<br/>
    </li><br>
	<li><code>limit_hum</code> <i>(Humidifier)</i>
    <br>
    Upper humidity limit for mode "auto"<br/>
    </li><br>
	<li><code>dry</code> <i>(Humidifier)</i>
    <br>
    Current Drymode state<br/>
    </li><br>
	<li><code>depth</code> <i>(Humidifier)</i>
    <br>
    Current %-level in watertank<br/>
    </li><br>
   </ul>
  <br>
   <b>Attributes</b>
   <ul>
   <li><code>subType</code>
     <br>
     VacuumCleaner / AirPurifier / AirPurifier3H / SmartFan / SmartFan1X / SmartFan1C / SmartFanFA1 / TowerFanP9 / Humidifier / EvpHumidifier / HumidifierMJJSQ / RiceCooker / PowerPlug / SmartLamp
   </li><br>
   <li><code>disable</code>
      <br>
      Disables the module
   </li><br>
   <li><code>intervalData</code>
      <br>
      Interval for data update (min 10 sec)
   </li><br>
   <li><code>intervalSettings</code>
      <br>
      Interval for settings update (min 60 sec)
   </li><br>
   <li><code>preset</code>  <i>(AirPurifier)</i>
      <br>
      Custom preset for dynamic mode changes (defaults to 'mode auto')
   </li><br>
   <li><code>point_names</code> point1:[X,Y] point2:[X,Y] <i>(VacuumCleaner)</i>
      <br>
      Custom named presets for points
   </li><br>
   <li><code>zone_names</code> combinedzone:[X1,Y1,X2,Y2,times],[X1,Y1,X2,Y2,times] zone:[X1,Y1,X2,Y2,times] <i>(VacuumCleaner)</i>
      <br>
      Custom named presets for cleaning zones
   </li><br>
   <li><code>map_names</code> line_and_area:[1,X1,Y1,X2,Y2],[0,X1,Y1,X2,Y2,X3,Y3,X4,Y4] <i>(VacuumCleaner)</i>
      <br>
      Custom named presets for exclusion maps
   </li><br>
  </ul>
</ul>

=end html
=cut

##############################################################################
# $Id$
#
#  38_netatmo.pm
#
#  2018 Markus Moises < vorname at nachname . de >
#
#  Based on original code by justme1968
#
#  https://forum.fhem.de/index.php/topic,53500.0.html
#
#
##############################################################################
# Release 20 / 2018-09-09

package main;

use strict;
use warnings;

use Encode qw(encode_utf8 decode_utf8);
use JSON;
use Math::Trig;

use HttpUtils;

use Data::Dumper; #debugging

use MIME::Base64;

use vars qw($FW_ME);
use vars qw($FW_CSRF);

my %health_index = (  0 => "healthy",
                      1 => "fine",
                      2 => "fair",
                      3 => "poor",
                      4 => "unhealthy",
                      5 => "unknown", );

sub
netatmo_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "netatmo_Define";
  $hash->{NotifyFn} = "netatmo_Notify";
  $hash->{UndefFn}  = "netatmo_Undefine";
  $hash->{SetFn}    = "netatmo_Set";
  $hash->{GetFn}    = "netatmo_Get";
  $hash->{DbLog_splitFn}    =   "netatmo_DbLog_splitFn";
  $hash->{AttrFn}   = "netatmo_Attr";
  $hash->{AttrList} = "IODev ".
                      "disable:0,1 ".
                      "interval ".
                      "videoquality:poor,low,medium,high ".
                      "ignored_device_ids ".
                      "setpoint_duration ".
                      "webhookURL webhookPoll:0,1 ".
                      "addresslimit ".
                      "serverAPI ";
  $hash->{AttrList} .= $readingFnAttributes;
}

#####################################

sub
netatmo_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  my $name = $a[0];
  $hash->{status} = "initialized";
  $hash->{helper}{last_status_store} = 0;

  my $subtype;
  if($a[2] eq "WEBHOOK") {
    $subtype = "WEBHOOK";
    my $d = $modules{$hash->{TYPE}}{defptr}{"WEBHOOK"};
    return "Netatmo webkook already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"WEBHOOK"} = $hash;

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "webhook", "initialized" );
    readingsEndUpdate( $hash, 1 );

    my $account = $modules{$hash->{TYPE}}{defptr}{"account"};
    $hash->{IODev} = $account;
    $attr{$name}{IODev} = $account->{NAME} if( !defined($attr{$name}{IODev}) && $account);
  }
  elsif( @a == 3 ) {
    $subtype = "DEVICE";

    my $device = $a[2];

    $hash->{Device} = $device;

    $hash->{openRequests} = 0;

    $hash->{helper}{INTERVAL} = 60*15 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;

  }
  elsif( ($a[2] eq "PUBLIC" && @a > 3 ) )
  {
    $hash->{openRequests} = 0;

    Log3 $name, 5, "$name: pub ".Dumper(@a);

    if( $a[3] && $a[3] =~ m/[\da-f]{2}(:[\da-f]{2}){5}/ )
    {

      my $device = $a[3];
      $hash->{Device} = $device;

      if( $a[4] && $a[4] =~ m/[\da-f]{2}(:[\da-f]{2}){5}/ )
      {

        $subtype = "MODULE";

        my $module = "";
        my $readings = "";

        my @a = splice( @a, 4 );
        while( @a ) {
          $module .= " " if( $module );
          $module .= shift( @a );

          $readings .= " " if( $readings );
          $readings .=  shift( @a );
        }

        $hash->{Module} = $module;
        $hash->{dataTypes} = $readings if($readings);
        $hash->{dataTypes} = "Temperature,CO2,Humidity,Noise,Pressure,Rain,WindStrength,WindAngle,GustStrength,GustAngle,Sp_Temperature,BoilerOn,BoilerOff" if( !$readings );


        my $d = $modules{$hash->{TYPE}}{defptr}{"M$module"};
        return "module $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

        $modules{$hash->{TYPE}}{defptr}{"M$module"} = $hash;

        my $state_format;
        if( $readings =~ m/temperature/ ) {
          $state_format .= " " if( $state_format );
          $state_format .= "T: temperature";
        }
        if( $readings =~ m/humidity/ ) {
          $state_format .= " " if( $state_format );
          $state_format .= "H: humidity";
        }
        $attr{$name}{stateFormat} = $state_format if( !defined($attr{$name}{stateFormat}) && defined($state_format) && defined($name) );
        $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}) && defined($name));
        $attr{$name}{devStateIcon} = ".*:no-icon" if( !defined($attr{$name}{devStateIcon}) && defined($name));


      }

      $subtype = "DEVICE";

      my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
      return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

      $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;

      delete( $hash->{LAST_POLL} );


    }
    else
    {

      my ($lat, $lon, $rad);
      if($a[3] =~ m/,/){

        Log3 $name, 5, "$name: latlng 2 ".$a[3];
        my @latlon = split( ',', $a[3] );
        $lat = $latlon[0];
        $lon = $latlon[1];
        $rad = $a[4];
      }
      else {

        $lat = $a[3];
        $lon = $a[4];
        $rad = $a[5];
      }

      $rad = 0.02 if( !$rad );

      $hash->{Lat} = $lat;
      $hash->{Lon} = $lon;
      $hash->{Rad} = $rad;

      $subtype = "PUBLIC";
      $modules{$hash->{TYPE}}{defptr}{$hash->{Lat}.$hash->{Lon}.$hash->{Rad}} = $hash;

      my $account = $modules{$hash->{TYPE}}{defptr}{"account"};
      $hash->{IODev} = $account;
      $attr{$name}{IODev} = $account->{NAME} if( !defined($attr{$name}{IODev}) && $account);


    }

    $hash->{helper}{INTERVAL} = 60*30 if( !$hash->{helper}{INTERVAL} );
    $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}) && defined($name));
    $attr{$name}{devStateIcon} = ".*:no-icon" if( !defined($attr{$name}{devStateIcon}) && defined($name));

  } elsif( ($a[2] eq "MODULE" && @a == 5 ) ) {
    $subtype = "MODULE";

    my $device = $a[@a-2];
    my $module = $a[@a-1];

    $hash->{Device} = $device;
    $hash->{Module} = $module;

    $hash->{openRequests} = 0;

    $hash->{helper}{INTERVAL} = 60*15 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"M$module"};
    return "module $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"M$module"} = $hash;

  } elsif( ($a[2] eq "FORECAST" && @a == 4 ) ) {
    $subtype = "FORECAST";

    my $device = $a[3];

    $hash->{Station} = $device;

    $hash->{openRequests} = 0;

    $hash->{helper}{INTERVAL} = 60*60 if( !$hash->{helper}{INTERVAL} );
    $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}) && defined($name));
    $attr{$name}{devStateIcon} = ".*:no-icon" if( !defined($attr{$name}{devStateIcon}) && defined($name));
    $attr{$name}{'event-on-change-reading'} = ".*" if( !defined($attr{$name}{'event-on-change-reading'}) && defined($name));

    my $d = $modules{$hash->{TYPE}}{defptr}{"F$device"};
    return "forecast $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"F$device"} = $hash;

    my $account = $modules{$hash->{TYPE}}{defptr}{"account"};
    $hash->{IODev} = $account;
    $attr{$name}{IODev} = $account->{NAME} if( !defined($attr{$name}{IODev}) && $account);


  } elsif( ($a[2] eq "RELAY" && @a == 4 ) ) {
    $subtype = "RELAY";

    my $device = $a[3];

    $hash->{Relay} = $device;

    $hash->{openRequests} = 0;

    $hash->{helper}{INTERVAL} = 60*30 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"R$device"};
    return "relay $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"R$device"} = $hash;

  } elsif( ($a[2] eq "THERMOSTAT" && @a == 5 ) ) {
    $subtype = "THERMOSTAT";

    my $device = $a[@a-2];
    my $module = $a[@a-1];

    $hash->{Relay} = $device;
    $hash->{Thermostat} = $module;

    $hash->{openRequests} = 0;
    $hash->{dataTypes} = "Temperature,Sp_Temperature,BoilerOn,BoilerOff";
    $hash->{helper}{INTERVAL} = 60*30 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"T$module"};
    return "thermostat $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"T$module"} = $hash;

  } elsif( ($a[2] eq "HEATINGHOME" && @a == 4 ) ) {
    $subtype = "HEATINGHOME";

    my $home = $a[@a-1];

    $hash->{Home} = $home;

    $hash->{openRequests} = 0;
    #$hash->{dataTypes} = "Temperature,Sp_Temperature,BoilerOn,BoilerOff";
    $hash->{helper}{INTERVAL} = 60*30 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"E$home"};
    return "heating home $home already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"E$home"} = $hash;

  } elsif( ($a[2] eq "HEATINGROOM" && @a == 5 ) ) {
    $subtype = "HEATINGROOM";

    my $room = $a[@a-1];
    my $home = $a[@a-2];

    $hash->{Home} = $home;
    $hash->{Room} = $room;

    $hash->{openRequests} = 0;
    $hash->{dataTypes} = "Temperature,Sp_Temperature,heating_power_request,BoilerOn,BoilerOff";
    $hash->{helper}{INTERVAL} = 60*30 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"O$room"};
    return "heating room $room already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"O$room"} = $hash;

  } elsif( ($a[2] eq "HOME" && @a == 4 ) ) {
    $subtype = "HOME";

    my $home = $a[@a-1];

    $hash->{Home} = $home;

    $hash->{helper}{INTERVAL} = 60*15 if( !$hash->{helper}{INTERVAL} );

    $attr{$name}{videoquality} = "medium" if( !defined($attr{$name}{videoquality}) && defined($name));

    my $d = $modules{$hash->{TYPE}}{defptr}{"H$home"};
    return "home $home already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"H$home"} = $hash;

  } elsif( ($a[2] eq "PERSON" && @a == 5 ) ) {
    $subtype = "PERSON";

    my $home = $a[@a-2];
    my $person = $a[@a-1];

    $hash->{Home} = $home;
    $hash->{Person} = $person;

    $hash->{helper}{INTERVAL} = 60*15 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"P$person"};
    return "person $person already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"P$person"} = $hash;

  } elsif( ($a[2] eq "CAMERA" && @a == 5 ) ) {
    $subtype = "CAMERA";

    my $home = $a[@a-2];
    my $camera = $a[@a-1];

    $hash->{Home} = $home;
    $hash->{Camera} = $camera;

    $hash->{helper}{INTERVAL} = 60*15 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"C$camera"};
    return "camera $camera already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"C$camera"} = $hash;

  } elsif( ($a[2] eq "TAG" && @a == 5 ) ) {
    $subtype = "TAG";

    my $camera = $a[@a-2];
    my $tag = $a[@a-1];

    $hash->{Tag} = $tag;
    $hash->{Camera} = $camera;

    #$hash->{helper}{INTERVAL} = 60*15 if( !$hash->{helper}{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"G$tag"};
    return "tag $tag already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"G$tag"} = $hash;

  } elsif( @a == 6  || ($a[2] eq "ACCOUNT" && @a == 7 ) ) {
    $subtype = "ACCOUNT";
    $hash->{network} = "ok";

    delete($hash->{access_token});
    delete($hash->{access_token_app});
    delete($hash->{refresh_token});
    delete($hash->{refresh_token_app});
    delete($hash->{expires_at});
    delete($hash->{expires_at_app});
    delete($hash->{csrf_token});

    my $user = $a[@a-4];
    my $pass = $a[@a-3];
    my $username = netatmo_encrypt($user);
    my $password = netatmo_encrypt($pass);
    Log3 $name, 2, "$name: encrypt $user/$pass to $username/$password" if($user ne $username || $pass ne $password);

    my $client_id = $a[@a-2];
    my $client_secret = $a[@a-1];

    #$hash->{DEF} =~ s/$user/$username/g;
    #$hash->{DEF} =~ s/$pass/$password/g;
    $hash->{DEF} = "ACCOUNT $username $password $client_id $client_secret";

    $hash->{Clients} = ":netatmo:";

    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    $hash->{helper}{client_id} = $client_id;
    $hash->{helper}{client_secret} = $client_secret;

    $hash->{helper}{INTERVAL} = 60*60 if( !$hash->{helper}{INTERVAL} );
    $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}) && defined($name));

    $modules{$hash->{TYPE}}{defptr}{"account"} = $hash;

    $hash->{helper}{apiserver} = AttrVal($name, "serverAPI", "api.netatmo.com");

  } else {
    return "Usage: define <name> netatmo device\
       define <name> netatmo userid publickey\
       define <name> netatmo PUBLIC latitude longitude [radius]\
       define <name> netatmo [ACCOUNT] username password"  if(@a < 3 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;

  $hash->{STATE} = "Initialized" if( $hash->{SUBTYPE} eq "ACCOUNT" );

  $hash->{NOTIFYDEV} = "global";

  if(IsDisabled($name) || !defined($name)) {
    RemoveInternalTimer($hash);
    $hash->{STATE} = "Disabled";
    return undef;
  }

  if( $init_done ) {
    netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "PUBLIC" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "FORECAST" );
    netatmo_initHome($hash) if( $hash->{SUBTYPE} eq "HOME" );
    netatmo_pingCamera($hash) if( $hash->{SUBTYPE} eq "CAMERA" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "RELAY" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "THERMOSTAT" );
    netatmo_initHeatingHome($hash) if( $hash->{SUBTYPE} eq "HEATINGHOME" );
    #netatmo_initHeatingRoom($hash) if( $hash->{SUBTYPE} eq "HEATINGROOM" );
    netatmo_addExtension($hash) if( $hash->{SUBTYPE} eq "WEBHOOK" );

  }
  else
  {
    InternalTimer(gettimeofday()+120, "netatmo_InitWait", $hash);
  }

  return undef;
}

sub netatmo_InitWait($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 "netatmo", 5, "netatmo: initwait ".$init_done;

  RemoveInternalTimer($hash);


  if( $init_done ) {
    netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "PUBLIC" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "FORECAST" );
    netatmo_initHome($hash) if( $hash->{SUBTYPE} eq "HOME" );
    netatmo_pingCamera($hash) if( $hash->{SUBTYPE} eq "CAMERA" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "RELAY" );
    netatmo_poll($hash) if( $hash->{SUBTYPE} eq "THERMOSTAT" );
    netatmo_initHeatingHome($hash) if( $hash->{SUBTYPE} eq "HEATINGHOME" );
    #netatmo_initHeatingRoom($hash) if( $hash->{SUBTYPE} eq "HEATINGROOM" );
    netatmo_addExtension($hash) if( $hash->{SUBTYPE} eq "WEBHOOK" );

  }
  else
  {
    InternalTimer(gettimeofday()+120, "netatmo_InitWait", $hash);
  }

  return undef;

}

sub
netatmo_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  RemoveInternalTimer($hash);

  if(IsDisabled($name) || !defined($name)) {
    RemoveInternalTimer($hash);
    $hash->{STATE} = "Disabled";
    return undef;
  }

  netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "PUBLIC" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "FORECAST" );
  netatmo_initHome($hash) if( $hash->{SUBTYPE} eq "HOME" );
  netatmo_pingCamera($hash) if( $hash->{SUBTYPE} eq "CAMERA" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "RELAY" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "THERMOSTAT" );
  netatmo_initHeatingHome($hash) if( $hash->{SUBTYPE} eq "HEATINGHOME" );
  #netatmo_initHeatingRoom($hash) if( $hash->{SUBTYPE} eq "HEATINGROOM" );
  netatmo_addExtension($hash) if( $hash->{SUBTYPE} eq "WEBHOOK" );


  return undef;
}

sub
netatmo_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  delete( $modules{$hash->{TYPE}}{defptr}{"D$hash->{Device}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );
  delete( $modules{$hash->{TYPE}}{defptr}{"M$hash->{Module}"} ) if( $hash->{SUBTYPE} eq "MODULE" );
  delete( $modules{$hash->{TYPE}}{defptr}{$hash->{Lat}.$hash->{Lon}.$hash->{Rad}} ) if( $hash->{SUBTYPE} eq "PUBLIC" );
  delete( $modules{$hash->{TYPE}}{defptr}{"F$hash->{Station}"} ) if( $hash->{SUBTYPE} eq "FORECAST" );
  delete( $modules{$hash->{TYPE}}{defptr}{"H$hash->{Home}"} ) if( $hash->{SUBTYPE} eq "HOME" );
  delete( $modules{$hash->{TYPE}}{defptr}{"C$hash->{Camera}"} ) if( $hash->{SUBTYPE} eq "CAMERA" );
  delete( $modules{$hash->{TYPE}}{defptr}{"P$hash->{Person}"} ) if( $hash->{SUBTYPE} eq "PERSON" );
  delete( $modules{$hash->{TYPE}}{defptr}{"R$hash->{Relay}"} ) if( $hash->{SUBTYPE} eq "RELAY" );
  delete( $modules{$hash->{TYPE}}{defptr}{"T$hash->{Thermostat}"} ) if( $hash->{SUBTYPE} eq "THERMOSTAT" );
  delete( $modules{$hash->{TYPE}}{defptr}{"E$hash->{Home}"} ) if( $hash->{SUBTYPE} eq "HEATINGHOME" );
  delete( $modules{$hash->{TYPE}}{defptr}{"O$hash->{Room}"} ) if( $hash->{SUBTYPE} eq "HEATINGROOM" );
  netatmo_removeExtension($hash) if( $hash->{SUBTYPE} eq "WEBHOOK" );

  return undef;
}

sub
netatmo_Set($$@)
{
  my ($hash, $name, $cmd, @parameters) = @_;

  $hash->{SUBTYPE} = "unknown" if(!defined($hash->{SUBTYPE}));
  my $list = "";
  $list = "autocreate:noArg autocreate_homes:noArg autocreate_thermostats:noArg autocreate_homecoachs:noArg" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  #$list .= " unban:noArg" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  $list = "home:noArg away:noArg" if ($hash->{SUBTYPE} eq "PERSON");
  $list = "empty:noArg notify_movements:never,empty,always notify_unknowns:empty,always notify_animals:true,false record_animals:true,false record_movements:never,empty,always record_alarms:never,empty,always presence_record_humans:ignore,record,record_and_notify presence_record_vehicles:ignore,record,record_and_notify presence_record_animals:ignore,record,record_and_notify presence_record_movements:ignore,record,record_and_notify presence_record_alarms:ignore,record,record_and_notify gone_after presence_enable_notify_from_to:empty,always presence_notify_from presence_notify_to smart_notifs:on,off" if ($hash->{SUBTYPE} eq "HOME");
  $list = "enable disable irmode:auto,always,never led_on_live:on,off mirror:off,on audio:on,off" if ($hash->{SUBTYPE} eq "CAMERA");
  $list = "enable disable light_mode:auto,on,off floodlight intensity:slider,0,1,100 night_always:true,false night_person:true,false night_vehicle:true,false night_animal:true,false night_movement:true,false" if ($hash->{SUBTYPE} eq "CAMERA" && defined($hash->{model}) && $hash->{model} eq "NOC");
  $list = "calibrate:noArg" if ($hash->{SUBTYPE} eq "TAG");
  if ($hash->{SUBTYPE} eq "THERMOSTAT" || $hash->{SUBTYPE} eq "HEATINGROOM")
  {
    $list = "setpoint_mode:off,hg,away,program,manual,max setpoint_temp:5.0,5.5,6.0,6.5,7.0,7.5,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0,28.5,29.0,29.5,30.0";
    $list = "setpoint_mode:off,hg,away,program,manual,max program:".$hash->{schedulenames}." setpoint_temp:5.0,5.5,6.0,6.5,7.0,7.5,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0,28.5,29.0,29.5,30.0" if(defined($hash->{schedulenames}));
  }
  $list = "clear:noArg webhook:add,drop" if ($hash->{SUBTYPE} eq "WEBHOOK");

  return undef if( $list eq "" );

  if( $cmd eq "autocreate" ) {
    return netatmo_autocreate($hash, 1 );
    return undef;
  }
  elsif( $cmd eq "autocreate_homes" ) {
    return netatmo_autocreatehome($hash, 1 );
    return undef;
  }
  elsif( $cmd eq "autocreate_thermostats" ) {
    return netatmo_autocreatethermostat($hash, 1 );
    return undef;
  }
  elsif( $cmd eq "autocreate_homecoachs" ) {
    return netatmo_autocreatehomecoach($hash, 1 );
    return undef;
  }
  elsif( $cmd eq "home" ) {
    return netatmo_setPresence($hash, "home");
    return undef;
  }
  elsif( $cmd eq "away" ) {
    return netatmo_setPresence($hash, "away");
    return undef;
  }
  elsif( $cmd eq "empty" ) {
    return netatmo_setPresence($hash, "empty");
    return undef;
  }
  elsif( $cmd =~ /^notify_/ || $cmd =~ /^record_/ || $cmd =~ /^presence_/  || $cmd eq "gone_after"  || $cmd eq "smart_notifs" ) {
    return netatmo_setNotifications($hash, $cmd, $parameters[0]);
    return undef;
  }
  elsif( $cmd eq "enable" ) {
    my $pin = $parameters[0];
    $pin = "0000" if(!defined($pin) || length($pin) != 4);
    return netatmo_setCamera($hash, "on", $pin);
    return undef;
  }
  elsif( $cmd eq "disable" ) {
    my $pin = $parameters[0];
    $pin = "0000" if(!defined($pin) || length($pin) != 4);
    $hash->{pin} = $pin;
    return netatmo_setCamera($hash, "off", $pin);
    return undef;
  }
  elsif( $cmd eq "irmode" || $cmd eq "led_on_live" || $cmd eq "mirror" || $cmd eq "audio" ) {
    my $setting = $parameters[0];
    return "You have to define a value" if(!defined($setting) || $setting eq "");
    readingsSingleUpdate($hash, $cmd, $setting, 1);
    return netatmo_setCameraSetting($hash, $cmd, $setting);
    return undef;
  }
  elsif( $cmd eq "light_mode" ) {
    my $setting = $parameters[0];
    return "You have to define a value" if(!defined($setting) || $setting eq "");
    return netatmo_setFloodlight($hash, $setting);
    return undef;
  }
  elsif( $cmd eq "floodlight" ) {
    my $setting = $parameters[0];
    $setting = 100 if(!defined($setting) || $setting eq "");
    $setting = int($setting);
    return netatmo_setIntensity($hash, $setting);
    return undef;
  }
  elsif( $cmd eq "intensity" || $cmd eq "night_always" || $cmd eq "night_person" || $cmd eq "night_vehicle" || $cmd eq "night_animal" || $cmd eq "night_movement" ) {
    my $setting = $parameters[0];
    return "You have to define a value" if(!defined($setting) || $setting eq "");
    readingsSingleUpdate($hash, $cmd, $setting, 1);
    return netatmo_setPresenceConfig($hash, $setting);
    return undef;
  }
  elsif( $cmd eq "calibrate" ) {
    return netatmo_setTagCalibration($hash, $cmd);
    return undef;
  }
  elsif( $cmd eq "setpoint_mode" ) {
    my $setting = $parameters[0];
    my $duration = $parameters[1];
    return "You have to define a mode" if(!defined($setting) || $setting eq "");
    return netatmo_setRoomMode($hash,$setting,$duration) if($hash->{SUBTYPE} eq "HEATINGROOM");
    return netatmo_setThermostatMode($hash,$setting,$duration);
    return undef;
  }
  elsif( $cmd eq "setpoint_temp" ) {
    my $setting = $parameters[0];
    my $duration = $parameters[1];
    return "You have to define a temperature" if(!defined($setting) || $setting eq "");
    return netatmo_setRoomTemp($hash,$setting,$duration) if($hash->{SUBTYPE} eq "HEATINGROOM");
    return netatmo_setThermostatTemp($hash,$setting,$duration);
    return undef;
  }
  elsif( $cmd eq "program" ) {
    my $setting = $parameters[0];
    return "You have to define a program" if(!defined($setting) || $setting eq "");
    return netatmo_setThermostatProgram($hash,$setting);
    return undef;
  }
  elsif( $cmd eq "clear" ) {
    delete $hash->{READINGS};
    return undef;
  }
  elsif( $cmd eq "webhook" ) {
    if($parameters[0] eq "drop")
    {
      netatmo_dropWebhook($hash);
    } else {
      netatmo_registerWebhook($hash);
    }
    return undef;
  }
  if( $cmd eq 'unban' )# unban:noArg
  {
    return netatmo_Unban($hash); 
  }


  return "Unknown argument $cmd, choose one of $list";
}

sub
netatmo_getToken($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return Log3 $name, 1, "$name: No client id was found! (getToken)" if(!defined($hash->{helper}{client_id}));
  return Log3 $name, 1, "$name: No client secret was found! (getToken)" if(!defined($hash->{helper}{client_secret}));
  return Log3 $name, 1, "$name: No username was found! (getToken)" if(!defined($hash->{helper}{username}));
  return Log3 $name, 1, "$name: No password was found! (getToken)" if(!defined($hash->{helper}{password}));

  my($err,$data) = HttpUtils_BlockingGet({
    url => "https://".$hash->{helper}{apiserver}."/oauth2/token",
    timeout => 5,
    noshutdown => 1,
    data => {grant_type => 'password', client_id => $hash->{helper}{client_id},  client_secret=> $hash->{helper}{client_secret}, username => netatmo_decrypt($hash->{helper}{username}), password => netatmo_decrypt($hash->{helper}{password}), scope => 'read_station read_thermostat write_thermostat read_camera write_camera access_camera read_presence write_presence access_presence read_homecoach'},
  });

  netatmo_dispatch( {hash=>$hash,type=>'token'},$err,$data );
}


sub
netatmo_getAppToken($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return Log3 $name, 1, "$name: No username was found! (getAppToken)" if(!defined($hash->{helper}{username}));
  return Log3 $name, 1, "$name: No password was found! (getAppToken)" if(!defined($hash->{helper}{password}));

  #my $auth = "QXV0aG9yaXphdGlvbjogQmFzaWMgYm1GZlkyeHBaVzUwWDJsdmMxOTNaV3hqYjIxbE9qaGhZalU0TkdRMk1tTmhNbUUzTjJVek4yTmpZelppTW1NM1pUUm1Namxs";
  my $auth = "QXV0aG9yaXphdGlvbjogQmFzaWMgYm1GZlkyeHBaVzUwWDJsdmN6bzFObU5qTmpSaU56azBOak5oT1RrMU9HSTNOREF4TkRjeVpEbGxNREUxT0E9PQ==";
  $auth = decode_base64($auth);

  my($err,$data) = HttpUtils_BlockingGet({
    url => "https://app.netatmo.net/oauth2/token",
    method => "POST",
    timeout => 5,
    noshutdown => 1,
    header => "$auth",
    data => {app_identifier=>'com.netatmo.camera', grant_type => 'password', password => netatmo_decrypt($hash->{helper}{password}), scope => 'write_camera read_camera access_camera read_presence write_presence access_presence read_station', username => netatmo_decrypt($hash->{helper}{username})},
  });


  netatmo_dispatch( {hash=>$hash,type=>'apptoken'},$err,$data );
}

sub
netatmo_refreshToken($;$)
{
  my ($hash,$nonblocking) = @_;
  my $name = $hash->{NAME};

  if( defined($hash->{access_token}) && defined($hash->{expires_at}) ) {
    my ($seconds) = gettimeofday();
    return undef if( $seconds < $hash->{expires_at} - 300 );
  }

  Log3 $name, 3, "$name: refreshing token";
  
  my $resolve = inet_aton($hash->{helper}{apiserver});
  if(!defined($resolve))
  {
    $hash->{STATE} = "DNS error";
    $hash->{network} = "dns" if($hash->{SUBTYPE} eq "ACCOUNT");
    delete($hash->{access_token});
    delete($hash->{access_token_app});
    InternalTimer( gettimeofday() + 1800, "netatmo_refreshTokenTimer", $hash);
    Log3 $name, 1, "$name: DNS error, cannot resolve ".$hash->{helper}{apiserver};
    return undef;
  } else {
    $hash->{network} = "ok";
  }

  if( !$hash->{refresh_token} ) {
    netatmo_getToken($hash);
    return undef;
  }



  if( $nonblocking ) {
    HttpUtils_NonblockingGet({
      url => "https://".$hash->{helper}{apiserver}."/oauth2/token",
      timeout => 20,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', client_id => $hash->{helper}{client_id},  client_secret=> $hash->{helper}{client_secret}, refresh_token => $hash->{refresh_token}},
        hash => $hash,
        type => 'token',
        callback => \&netatmo_dispatch,
    });
  } else {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://".$hash->{helper}{apiserver}."/oauth2/token",
      timeout => 5,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', client_id => $hash->{helper}{client_id},  client_secret=> $hash->{helper}{client_secret}, refresh_token => $hash->{refresh_token}},
    });

    netatmo_dispatch( {hash=>$hash,type=>'token'},$err,$data );
  }
}

sub
netatmo_refreshAppToken($;$)
{
  my ($hash,$nonblocking) = @_;
  my $name = $hash->{NAME};

  if($hash->{network} eq "dns")
  {
    Log3 $name, 2, "$name: app token dns error, update postponed!";
    InternalTimer( gettimeofday() + 600, "netatmo_refreshAppTokenTimer", $hash);
    return undef;
  }

  if( defined($hash->{access_token_app}) && defined($hash->{expires_at_app}) ) {
    my ($seconds) = gettimeofday();
    return undef if( $seconds < $hash->{expires_at_app} - 300 );
  } elsif( !defined($hash->{refresh_token_app}) ) {
    Log3 $name, 2, "$name: missing app refresh token!";
    netatmo_getAppToken($hash);
    return undef;
  }

  delete($hash->{csrf_token});
  Log3 $name, 3, "$name: refreshing app token";

  my $auth = "QXV0aG9yaXphdGlvbjogQmFzaWMgYm1GZlkyeHBaVzUwWDJsdmN6bzFObU5qTmpSaU56azBOak5oT1RrMU9HSTNOREF4TkRjeVpEbGxNREUxT0E9PQ==";
  $auth = decode_base64($auth);

  if( $nonblocking ) {
    HttpUtils_NonblockingGet({
      url => "https://app.netatmo.net/oauth2/token",
      timeout => 20,
      noshutdown => 1,
      header => "$auth",
      data => {grant_type => 'refresh_token', refresh_token => $hash->{refresh_token_app}},
      hash => $hash,
      type => 'apptoken',
      callback => \&netatmo_dispatch,
    });
  } else {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://app.netatmo.net/oauth2/token",
      timeout => 5,
      noshutdown => 1,
      header => "$auth",
      data => {grant_type => 'refresh_token', refresh_token => $hash->{refresh_token_app}},
    });

    netatmo_dispatch( {hash=>$hash,type=>'apptoken'},$err,$data );
  }
}

sub
netatmo_refreshTokenTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if(!defined($name))
  {
    Log3 "netatmo", 1, "error ".Dumper($hash);
    return undef;
  }

  Log3 $name, 5, "$name: refreshing token (timer)";

  netatmo_refreshToken($hash, 1);
}

sub
netatmo_refreshAppTokenTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: refreshing app token (timer)";

  netatmo_refreshAppToken($hash, 1);
}

sub
netatmo_checkConnection($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if($hash->{network} eq "ok");

  Log3 $name, 3, "$name: refreshing connection information";


  HttpUtils_NonblockingGet({
    url => "https://".$hash->{helper}{apiserver}."/api/readtimeline",
    timeout => 5,
    hash => $hash,
    callback => \&netatmo_parseConnection,
  });
  return undef;
}

sub
netatmo_parseConnection($$$)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    Log3 $name, 1, "$name: connection check failed: $err";

    if($err =~ /refused/ ){
      RemoveInternalTimer($hash);
      $hash->{status} = "banned";
      $hash->{network} = "banned";
    }
    elsif($err =~ /Bad hostname/ || $err =~ /gethostbyname/){
      $hash->{status} = "timeout";
      $hash->{network} = "dns";
    }
    elsif($err =~ /timed out/){
      $hash->{status} = "timeout";
      $hash->{network} = "timeout";
    }
    elsif($err =~ /Can't connect/){
      $hash->{status} = "timeout";
      $hash->{network} = "disconnected";
    }
    
    return undef;
  } elsif( $data ) {
      $data =~ s/\n//g;
      if( $data !~ m/^{.*}$/ ) {
        Log3 $name, 2, "$name: invalid json on connection check";
        return undef;
      }
      my $json = eval { JSON->new->utf8(0)->decode($data) };
      if($@)
      {
        Log3 $name, 2, "$name: invalid json evaluation on connection check ".$@;
        return undef;
      }
      $hash->{network} = "ok" if($json->{status} eq "ok");
    }
  return undef;
}

sub
netatmo_connect($)
{
  my ($hash) = @_;

  netatmo_getToken($hash);
  #netatmo_getAppToken($hash);

  InternalTimer(gettimeofday()+90, "netatmo_poll", $hash);

}

sub
netatmo_Unban($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  HttpUtils_NonblockingGet({
    url => "https://dev.netatmo.com/",
    timeout => 20,
    noshutdown => 1,
    hash => $hash,
    type => 'unban',
    callback => \&netatmo_parseUnban,
  });

  return undef;

}

sub
netatmo_parseUnban($$$)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  
  #Log3 $name, 1, "$name unban\n".Dumper($param->{httpheader});

  $data =~ /csrf_value: "(.*)"/;
  my $csrf_token = $1;

  # https://auth.netatmo.com/en-US/access/login?next_url=https://dev.netatmo.com/dev/myaccount
  Log3 $name, 1, "$name unban ".$csrf_token;

  HttpUtils_NonblockingGet({
    url => "https://auth.netatmo.com/en-US/access/login?next_url=https://dev.netatmo.com/dev/myaccount",
    timeout => 5,
    hash => $hash,
    ignoreredirects => 1,
    type => 'unban',
    header => "Cookie: netatmocomci_csrf_cookie_na=".$csrf_token."; netatmocomlocale=en-US",
    data => {ci_csrf_netatmo => $csrf_token, mail => netatmo_decrypt($hash->{helper}{username}), pass => netatmo_decrypt($hash->{helper}{password}), log_submit => 'Log+in', stay_logged => 'accept'},
    callback => \&netatmo_parseUnban2,
  });
    

  return undef;
}

sub
netatmo_parseUnban2($$$)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  
  Log3 $name, 1, "$name header\n".Dumper($param->{httpheader});
  my $header1 = $param->{httpheader};
  my $header2 = $param->{httpheader};
  my $header3 = $param->{httpheader};
  
  $header1 =~ s/=deleted/x=deleted/g;
  $header2 =~ s/=deleted/x=deleted/g;
  $header3 =~ s/=deleted/x=deleted/g;
  
  $header1 =~ /Set-Cookie: netatmocomci_csrf_cookie_na=(.*); expires/;
  my $csrf_token = $1;
  $hash->{helper}{csrf_token} = $csrf_token;

  $header2 =~ /Set-Cookie: netatmocomaccess_token=(.*); path/;
  my $accesstoken = $1;
  $accesstoken =~ s/%7C/|/g;
  $hash->{helper}{access_token} = $accesstoken;

  $header3 =~ /Set-Cookie: netatmocomrefresh_token=(.*); expires/;
  my $refreshtoken = $1;
  $hash->{helper}{refresh_token} = $refreshtoken;

  Log3 $name, 1, "$name csrftoken ".$csrf_token;
  Log3 $name, 1, "$name accesstoken ".$accesstoken;
  Log3 $name, 1, "$name refreshtoken ".$refreshtoken;

  my $json = '{"application_id":"'.$hash->{helper}{client_id}.'"}';

  HttpUtils_NonblockingGet({
    url => "https://dev.netatmo.com/api/unbanapp",
    timeout => 5,
    hash => $hash,
    type => 'unban',
    header => "Referer: https://dev.netatmo.com/dev/myaccount\r\nAuthorization: Bearer ".$accesstoken."\r\nContent-Type: application/json;charset=utf-8\r\nCookie: netatmocomci_csrf_cookie_na=".$csrf_token."; netatmocomlocale=en-US; netatmocomacces_token=".$accesstoken,
    data => $json,
    callback => \&netatmo_parseUnban3,
  });
    

  return undef;
}

sub
netatmo_parseUnban3($$$)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  
  Log3 $name, 1, "$name header\n".Dumper($param->{httpheader});
  Log3 $name, 1, "$name data\n".Dumper($data);
  Log3 $name, 1, "$name err\n".Dumper($err);

  return undef;
}

sub
netatmo_initDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  if(IsDisabled($name) || !defined($name)) {
    RemoveInternalTimer($hash);
    $hash->{STATE} = "Disabled";
    return undef;
  }

  my $device;
  if( $hash->{Module} ) {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Module} );
  } else {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Device} );
  }
  $hash->{stationName} = encode_utf8($device->{station_name}) if( $device->{station_name} );
  $hash->{moduleName} = encode_utf8($device->{module_name}) if( $device->{module_name} );
  $hash->{name} = encode_utf8($device->{name}) if( $device->{name} );

  $hash->{model} = $device->{type} if(defined($device->{type}));
  $hash->{firmware} = $device->{firmware} if(defined($device->{firmware}));

  $hash->{co2_calibrating} = $device->{co2_calibrating} if(defined($device->{co2_calibrating}));
  $hash->{last_upgrade} = FmtDateTime($device->{last_upgrade}) if(defined($device->{last_upgrade}));
  $hash->{date_setup} = FmtDateTime($device->{date_setup}) if(defined($device->{date_setup}));
  $hash->{last_setup} = FmtDateTime($device->{last_setup}) if(defined($device->{last_setup}));
  $hash->{last_status_store} = FmtDateTime($device->{last_status_store}) if(defined($device->{last_status_store}));
  $hash->{helper}{last_status_store} = $device->{last_status_store} if(defined($device->{last_status_store}) && $device->{last_status_store} > $hash->{helper}{last_status_store});
  $hash->{last_message} = FmtDateTime($device->{last_message}) if(defined($device->{last_message}));
  $hash->{last_seen} = FmtDateTime($device->{last_seen}) if(defined($device->{last_seen}));
  $hash->{wifi_status} = $device->{wifi_status} if(defined($device->{wifi_status}));
  $hash->{rf_status} = $device->{rf_status} if(defined($device->{rf_status}));
  #$hash->{battery_percent} = $device->{battery_percent} if(defined($device->{battery_percent}));
  #$hash->{battery_vp} = $device->{battery_vp} if(defined($device->{battery_vp}));

  if( $device->{place} ) {
    $hash->{country} = $device->{place}{country};
    $hash->{bssid} = $device->{place}{bssid} if(defined($device->{place}{bssid}));
    $hash->{altitude} = $device->{place}{altitude} if(defined($device->{place}{altitude}));
    $hash->{city} = encode_utf8($device->{place}{geoip_city}) if(defined($device->{place}{geoip_city}));
    $hash->{city} = encode_utf8($device->{place}{city}) if(defined($device->{place}{city}));;
    $hash->{location} = $device->{place}{location}[1] .",". $device->{place}{location}[0];
  }

  readingsSingleUpdate($hash, "batteryState", ($device->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($device->{battery_percent}));
  readingsSingleUpdate($hash, "batteryPercent", $device->{battery_percent}, 1) if(defined($device->{battery_percent}));
  readingsSingleUpdate($hash, "batteryVoltage", $device->{battery_vp}/1000, 1) if(defined($device->{battery_vp}));

  my $state_format;
  if( $device->{data_type} ) {

    my $newdatatypes = "";
    my @reading_names = ();
    foreach my $type (@{$device->{data_type}}) {
      $newdatatypes = "" if ( !defined($newdatatypes) );
      $newdatatypes .= "," if ( $newdatatypes );
      $type = "WindStrength,WindAngle,GustStrength,GustAngle" if($type eq "Wind");
      $newdatatypes .= $type;

      push @reading_names, lc($type);

      if( $type eq "Temperature" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "T: temperature";
      } elsif( $type eq "Humidity" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "H: humidity";
      }
    }
    if($newdatatypes ne "")
    {
      delete($hash->{dataTypes});
      $hash->{dataTypes} = $newdatatypes;
    }

    $hash->{helper}{readingNames} = \@reading_names;
  }

  $attr{$name}{stateFormat} = $state_format if( !defined($attr{$name}{stateFormat}) && defined($state_format) && defined($name) );

  if(IsDisabled($name) || !defined($name)) {
    RemoveInternalTimer($hash);
    $hash->{STATE} = "Disabled";
    return undef;
  }

  InternalTimer(gettimeofday()+90, "netatmo_poll", $hash);

}

sub
netatmo_getDevices($;$)
{
  my ($hash,$blocking) = @_;
  my $name = $hash->{NAME};

  netatmo_refreshToken($hash, defined($hash->{access_token}));
  Log3 $name, 3, "$name getDevices (devicelist)";

  return Log3 $name, 1, "$name: No access token was found! (getDevices)" if(!defined($hash->{access_token}));
  
  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/getstationsdata",
      timeout => 5,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'devicelist'},$err,$data );


    return $hash->{helper}{devices};
  } else {
    HttpUtils_NonblockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/getstationsdata",
      timeout => 20,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
      hash => $hash,
      type => 'devicelist',
      callback => \&netatmo_dispatch,
    });


  }
}
sub
netatmo_getHomes($;$)
{
  my ($hash,$blocking) = @_;
  my $name = $hash->{NAME};

  netatmo_refreshToken($hash, defined($hash->{access_token}));
  Log3 $name, 3, "$name getHomes (homelist)";

  return Log3 $name, 1, "$name: No access token was found! (getHomes)" if(!defined($hash->{access_token}));

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/gethomedata",
      timeout => 5,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'homelist'},$err,$data );

    return $hash->{helper}{homes};
  } else {
    HttpUtils_NonblockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/gethomedata",
      timeout => 20,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
      hash => $hash,
      type => 'homelist',
      callback => \&netatmo_dispatch,
    });
  }
}
sub
netatmo_getThermostats($;$)
{
  my ($hash,$blocking) = @_;
  my $name = $hash->{NAME};

  netatmo_refreshToken($hash, defined($hash->{access_token}));
  Log3 $name, 3, "$name getThermostats (thermostatlist)";

  return Log3 $name, 1, "$name: No access token was found! (getThermostats)" if(!defined($hash->{access_token}));

#      url => "https://".$hash->{helper}{apiserver}."/api/getthermostatsdata",
  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/gethomesdata",
      timeout => 5,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'thermostatlist'},$err,$data );


    return $hash->{helper}{thermostats};
  } else {
    HttpUtils_NonblockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/gethomesdata",
      timeout => 20,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
      hash => $hash,
      type => 'thermostatlist',
      callback => \&netatmo_dispatch,
    });


  }
}

sub
netatmo_getHomecoachs($;$)
{
  my ($hash,$blocking) = @_;
  my $name = $hash->{NAME};

  netatmo_refreshToken($hash, defined($hash->{access_token}));
  Log3 $name, 3, "$name getHomecoachs (homecoachlist)";

  return Log3 $name, 1, "$name: No access token was found! (getHomecoachs)" if(!defined($hash->{access_token}));

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/gethomecoachsdata",
      timeout => 5,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'homecoachlist'},$err,$data );


    return $hash->{helper}{homecoachs};
  } else {
    HttpUtils_NonblockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/gethomecoachsdata",
      timeout => 20,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
      hash => $hash,
      type => 'homecoachlist',
      callback => \&netatmo_dispatch,
    });


  }
}

sub
netatmo_pingCamera($;$)
{
  my ($hash,$blocking) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash, defined($iohash->{access_token}));

  return Log3 $name, 1, "$name: No access token was found! (pingCamera)" if(!defined($iohash->{access_token}));

  my $pingurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($pingurl));

  Log3 $name, 3, "$name pingCamera (cameraping)";

  $pingurl .= "/command/ping";

  Log3 $name, 5, "$name pingCamera ".$pingurl;

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => $pingurl,
      timeout => 10,
      sslargs => { SSL_hostname => '', },
      data => { access_token => $iohash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'cameraping'},$err,$data );


    return undef;
  } else {
    HttpUtils_NonblockingGet({
      url => $pingurl,
      timeout => 10,
      sslargs => { SSL_hostname => '', },
      data => { access_token => $iohash->{access_token}, },
      hash => $hash,
      type => 'cameraping',
      callback => \&netatmo_dispatch,
    });


  }
}

sub
netatmo_getCameraVideo($$;$)
{
  my ($hash,$videoid,$local) = @_;
  my $name = $hash->{NAME};

  $local = ($local eq "video_local" ? "_local" : "");

  #my $iohash = $hash->{IODev};
  #netatmo_refreshToken($iohash, defined($iohash->{access_token}));

  my $commandurl = ReadingsVal( $name, "local_url", undef);
  if(!defined($commandurl)) {
    ReadingsVal( $name, "vpn_url", undef );
  } else {
    $local = "";
  }

  return undef if(!defined($commandurl));

  my $quality = AttrVal($name,"videoquality","medium");

  $commandurl .= "/vod/".$videoid."/files/".$quality."/index".$local.".m3u8";

  Log3 $name, 3, "$name getCameraVideo ".$commandurl;

    # HttpUtils_BlockingGet({
    #   url => $cmdurl,
    #   noshutdown => 1,
    #   data => { access_token => $iohash->{access_token}, },
    #   hash => $hash,
    #   type => 'cameravideo',
    #   callback => \&netatmo_dispatch,
    # });
    return $commandurl;

}


sub
netatmo_getCameraLive($;$)
{
  my ($hash,$local) = @_;
  my $name = $hash->{NAME};

  $local = ($local eq "live_local" ? "_local" : "");

  #my $iohash = $hash->{IODev};
  #netatmo_refreshToken($iohash, defined($iohash->{access_token}));

  my $commandurl = ReadingsVal( $name, "local_url", undef);
  if(!defined($commandurl)) {
    ReadingsVal( $name, "vpn_url", undef );
  } else {
    $local = "";
  }

  return undef if(!defined($commandurl));

  my $quality = AttrVal($name,"videoquality","medium");

  $commandurl .= "/live/files/".$quality."/index".$local.".m3u8";

  Log3 $name, 3, "$name getCameraLive ".$commandurl;

    # HttpUtils_BlockingGet({
    #   url => $cmdurl,
    #   noshutdown => 1,
    #   data => { access_token => $iohash->{access_token}, },
    #   hash => $hash,
    #   type => 'cameravideo',
    #   callback => \&netatmo_dispatch,
    # });
    return $commandurl;

}

sub
netatmo_getCameraTimelapse($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #my $iohash = $hash->{IODev};
  #netatmo_refreshToken($iohash, defined($iohash->{access_token}));

  my $cmdurl = ReadingsVal( $name, "local_url", undef );

  return undef if(!defined($cmdurl));

  $cmdurl .= "/command/dl/timelapse";

  Log3 $name, 3, "$name getCameraTimelapse ".$cmdurl;

    # HttpUtils_BlockingGet({
    #   url => $cmdurl,
    #   noshutdown => 1,
    #   data => { access_token => $iohash->{access_token}, },
    #   hash => $hash,
    #   type => 'cameravideo',
    #   callback => \&netatmo_dispatch,
    # });
    return $cmdurl;

}


sub
netatmo_getCameraSnapshot($;$)
{
  my ($hash,$local) = @_;
  my $name = $hash->{NAME};

  #my $iohash = $hash->{IODev};
  #netatmo_refreshToken($iohash, defined($iohash->{access_token}));

  my $commandurl = ReadingsVal( $name, "local_url", ReadingsVal( $name, "vpn_url", undef ) );
  return undef if(!defined($commandurl));

  $commandurl .= "/live/snapshot_720.jpg";

  Log3 $name, 3, "$name getCameraSnapshot ".$commandurl;

    # HttpUtils_BlockingGet({
    #   url => $cmdurl,
    #   noshutdown => 1,
    #   data => { access_token => $iohash->{access_token}, },
    #   hash => $hash,
    #   type => 'cameravideo',
    #   callback => \&netatmo_dispatch,
    # });
    return $commandurl;

}

sub
netatmo_getEvents($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash, defined($iohash->{access_token}));

  Log3 $name, 3, "$name getEvents (homeevents)";

  return Log3 $name, 1, "$name: No access token was found! (getEvents)" if(!defined($iohash->{access_token}));

  HttpUtils_NonblockingGet({
    url => "https://".$iohash->{helper}{apiserver}."/api/getnextevents",
    timeout => 20,
    noshutdown => 1,
    data => { access_token => $iohash->{access_token}, home_id => $hash->{Home}, event_id => $hash->{lastevent}, },
    hash => $hash,
    type => 'homeevents',
    callback => \&netatmo_dispatch,
  });
}

sub
netatmo_getPublicDevices($$;$$$$)
{
  my ($hash,$blocking,$lat1,$lon1,$lat2,$lon2) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  $iohash = $hash if( !defined($iohash) );
  #Log3 $name, 5, "$name getPublicDevices $lat1,$lon1,$lat2,$lon2";

  if( !defined($lon1) ) {
    my $s = $lat1;
    $s = 0.025 if ( !defined($s) );
    my $lat = AttrVal("global","latitude", 50.112);
    my $lon = AttrVal("global","longitude", 8.686);

    $lat1 = $lat + $s;
    $lon1 = $lon + $s;
    $lat2 = $lat - $s;
    $lon2 = $lon - $s;
  } elsif( !defined($lon2) ) {
    my $lat = $lat1;
    my $lon = $lon1;
    my $s = $lat2;
    $s = 0.025 if ( !defined($s) );

    $lat1 = $lat + $s;
    $lon1 = $lon + $s;
    $lat2 = $lat - $s;
    $lon2 = $lon - $s;
  }

  my $lat_ne = ($lat1 > $lat2) ? $lat1 : $lat2;
  my $lon_ne = ($lon1 > $lon2) ? $lon1 : $lon2;
  my $lat_sw = ($lat1 > $lat2) ? $lat2 : $lat1;
  my $lon_sw = ($lon1 > $lon2) ? $lon2 : $lon1;

  Log3 $name, 3, "$name getPublicDevices ($lat_ne,$lon_ne / $lat_sw,$lon_sw)";

  netatmo_refreshToken($iohash, defined($iohash->{access_token}));

  return Log3 $name, 1, "$name: No access token was found! (getPublicDevices)" if(!defined($iohash->{access_token}));

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://".$iohash->{helper}{apiserver}."/api/getpublicdata",
      timeout => 5,
      noshutdown => 1,
      data => { access_token => $iohash->{access_token}, lat_ne => $lat_ne, lon_ne => $lon_ne, lat_sw => $lat_sw, lon_sw => $lon_sw },
    });

      return netatmo_dispatch( {hash=>$hash,type=>'publicdata'},$err,$data );
  } else {
    HttpUtils_NonblockingGet({
      url => "https://".$iohash->{helper}{apiserver}."/api/getpublicdata",
      timeout => 20,
      noshutdown => 1,
      data => { access_token => $iohash->{access_token}, lat_ne => $lat_ne, lon_ne => $lon_ne, lat_sw => $lat_sw, lon_sw => $lon_sw, filter => 'true' },
      hash => $hash,
      type => 'publicdata',
      callback => \&netatmo_dispatch,
    });
  }
}

sub
netatmo_getAddress($$$$)
{
  my ($hash,$blocking,$lat,$lon) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  $iohash = $hash if( !defined($iohash) );

  Log3 $name, 5, "$name getAddress ($lat,$lon)";

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lon",
      noshutdown => 1,
    });

      return netatmo_dispatch( {hash=>$hash,type=>'address'},$err,$data );
  } else {
    HttpUtils_NonblockingGet({
      url => "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lon",
      noshutdown => 1,
      hash => $hash,
      type => 'address',
      callback => \&netatmo_dispatch,
    });
  }
}
sub
netatmo_getLatLong($$$)
{
  my ($hash,$blocking,$addr) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  $iohash = $hash if( !defined($iohash) );

  Log3 $name, 5, "$name getLatLong ($addr)";

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://maps.googleapis.com/maps/api/geocode/json?address=germany+$addr",
      noshutdown => 1,
    });

      return netatmo_dispatch( {hash=>$hash,type=>'latlng'},$err,$data );
  } else {
    HttpUtils_NonblockingGet({
      url => "https://maps.googleapis.com/maps/api/geocode/json?address=germany+$addr",
      noshutdown => 1,
      hash => $hash,
      type => 'latlng',
      callback => \&netatmo_dispatch,
    });
  }
}

sub
netatmo_getDeviceDetail($$)
{
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  Log3 $name, 5, "$name getDeviceDetail ($id)";

  netatmo_getDevices($hash,1) if( !$hash->{helper}{devices} );
  netatmo_getHomecoachs($hash,1) if( !$hash->{helper}{homecoachs} );

  foreach my $device (@{$hash->{helper}{devices}}) {
    return $device if( $device->{_id} eq $id );
  }
  foreach my $device (@{$hash->{helper}{homecoachs}}) {
    return $device if( $device->{_id} eq $id );
  }

  return undef;
}
sub
netatmo_requestDeviceReadings($@)
{
  my ($hash,$id,$type,$module) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  Log3 $name, 5, "$name: requestDeviceReadings ($id ".(!$type?"-":$type)." ".(!$module?"-":$module).")";

  my $iohash = $hash->{IODev};
  $type = $hash->{dataTypes} if( !$type );
  $type = "Temperature,CO2,Humidity,Noise,Pressure,health_idx" if( !$type && $hash->{SUBTYPE} eq "DEVICE" );
  $type = "Temperature,CO2,Humidity,Noise,Pressure,Rain,WindStrength,WindAngle,GustStrength,GustAngle,Sp_Temperature,BoilerOn,BoilerOff,health_idx" if( !$type );
  $type = "WindAngle,WindStrength,GustStrength,GustAngle" if ($type eq "Wind");

  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (requestDeviceReadings)" if(!defined($iohash->{access_token}));

  my %data = (access_token => $iohash->{access_token}, device_id => $id, scale => "max", type => $type);
  $data{"module_id"} = $module if( $module );

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  $data{"date_begin"} = $lastupdate if( defined($lastupdate) );

  Log3 $name, 3, "$name: requestDeviceReadings ($type)";

  HttpUtils_NonblockingGet({
    url => "https://".$iohash->{helper}{apiserver}."/api/getmeasure",
    timeout => 20,
    noshutdown => 1,
    data => \%data,
    hash => $hash,
    type => 'getmeasure',
    requested => $type,
    callback => \&netatmo_dispatch,
  });
}

sub
netatmo_initHome($@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (initHome)" if(!defined($iohash->{access_token}));

  my %data = (access_token => $iohash->{access_token}, home_id => $hash->{Home});

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );

  Log3 $name, 3, "$name initHome (gethomedata)";

#    url => "https://".$iohash->{helper}{apiserver}."/api/gethomedata",
#    data => \%data,
  HttpUtils_NonblockingGet({
    url => "https://app.netatmo.net/api/gethomesdata",
    timeout => 20,
    noshutdown => 1,
    header => "Content-Type: application/json\r\nAuthorization: Bearer ".$iohash->{access_token_app},
    hash => $hash,
    type => 'gethomedata',
    callback => \&netatmo_dispatch,
  });

  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "netatmo_poll", $hash);
  $hash->{helper}{NEXT_POLL} = int(gettimeofday())+$hash->{helper}{INTERVAL};
}

sub
netatmo_requestHomeReadings($@)
{
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );
  return undef if(!defined($iohash->{access_token}));
  netatmo_refreshAppToken( $iohash, defined($iohash->{access_token_app}) );
  return undef if(!defined($iohash->{access_token_app}));

  my %data = (access_token => $iohash->{access_token}, home_id => $id, size => 50);

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  #$data{"size"} = 1;#$lastupdate if( defined($lastupdate) );
  Log3 $name, 3, "$name requestHomeReadings (gethomedata)";

#    url => "https://".$iohash->{helper}{apiserver}."/api/gethomedata",
#    data => \%data,
  HttpUtils_NonblockingGet({
    url => "https://app.netatmo.net/api/gethomesdata",
    timeout => 20,
    noshutdown => 1,
    header => "Content-Type: application/json\r\nAuthorization: Bearer ".$iohash->{access_token_app},
    hash => $hash,
    type => 'gethomedata',
    callback => \&netatmo_dispatch,
  });
}

sub
netatmo_requestThermostatReadings($@)
{
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  Log3 $name, 3, "$name: requestThermostatReadings ($id)";

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (requestThermostatReadings)" if(!defined($iohash->{access_token}));

  my %data = (access_token => $iohash->{access_token}, device_id => $id);

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  #$data{"size"} = 1;#$lastupdate if( defined($lastupdate) );

  HttpUtils_NonblockingGet({
    url => "https://".$iohash->{helper}{apiserver}."/api/getthermostatsdata",
    timeout => 20,
    noshutdown => 1,
    data => \%data,
    hash => $hash,
    type => 'getthermostatsdata',
    callback => \&netatmo_dispatch,
  });
}

sub
netatmo_initHeatingHome($@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );
  netatmo_refreshAppToken( $iohash, defined($iohash->{access_token_app}) );

  return Log3 $name, 1, "$name: No access token was found! (initHeatingHome)" if(!defined($iohash->{access_token}));
  return Log3 $name, 1, "$name: No app access token was found! (initHeatingHome)" if(!defined($iohash->{access_token_app}));

  my %data = (app_type => 'app_thermostat', home_id => $hash->{Home});

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  #$data{"size"} = 1;#$lastupdate if( defined($lastupdate) );

  Log3 $name, 3, "$name initHeatingHome (gethomedata)";

#    url => "https://".$iohash->{helper}{apiserver}."/api/gethomedata",
#    data => \%data,
  HttpUtils_NonblockingGet({
    url => "https://app.netatmo.net/api/gethomesdata",
    timeout => 20,
    noshutdown => 1,
    header => "Content-Type: application/json\r\nAuthorization: Bearer ".$iohash->{access_token_app},
    data => \%data,
    hash => $hash,
    type => 'gethomedata',
    callback => \&netatmo_dispatch,
  });

  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "netatmo_poll", $hash);
  $hash->{helper}{NEXT_POLL} = int(gettimeofday())+$hash->{helper}{INTERVAL};
}


sub 
netatmo_pollHeatingHome($@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No app access token was found! (pollHeatingHome)" if(!defined($iohash->{access_token_app}));

  my %data = (home_id => $hash->{Home});

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  #$data{"size"} = 1;#$lastupdate if( defined($lastupdate) );
  my $json = encode_json( { home_id => $hash->{Home} } );

  $json =~s/\"true\"/true/g;
  $json =~s/\"false\"/false/g;

  Log3 $name, 3, "$name pollHeatingHome (getheatinghomedata)";

#    url => "https://".$iohash->{helper}{apiserver}."/api/gethomedata",
#    data => \%data,
  HttpUtils_NonblockingGet({
    url => "https://my.netatmo.com/syncapi/v1/gethomestatus",
    timeout => 20,
    noshutdown => 1,
    header => "Content-Type: application/json;charset=utf-8\r\nAuthorization: Bearer ".$iohash->{access_token},
    data => $json,
    hash => $hash,
    type => 'getheatinghomedata',
    callback => \&netatmo_dispatch,
  });

  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "netatmo_poll", $hash);
  $hash->{helper}{NEXT_POLL} = int(gettimeofday())+$hash->{helper}{INTERVAL};

  return undef;
}

sub 
netatmo_pollHeatingRoom($@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshAppToken( $iohash, defined($iohash->{access_token_app}) );

  return Log3 $name, 1, "$name: No app access token was found! (pollHeatingRoom)" if(!defined($iohash->{access_token_app}));

  $hash->{openRequests} = 0 if ( !defined(  $hash->{openRequests}) );
  Log3 $name, 4, "$name: pollHeatingRoom types [".$hash->{dataTypes} . "] for room [".$hash->{Room}."]" if(defined($hash->{dataTypes}));

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  $lastupdate = (time-7*24*60*60) if(!$lastupdate);
  $lastupdate += 10;
  $hash->{openRequests} += 1;

  my $now = int(time);
  my $json = encode_json( { home_id => $hash->{Home},
                            room_id => $hash->{Room},
                            scale => "max",
                            type => $hash->{dataTypes},
                            date_begin => "$lastupdate",
                            date_end => "$now",
                            real_time => "true" } );

  $json =~s/\"true\"/true/g;
  $json =~s/\"false\"/false/g;

  Log3 $name, 3, "$name pollHeatingRoom (getheatinghomedata)";

#    url => "https://".$iohash->{helper}{apiserver}."/api/gethomedata",
#    data => \%data,
  HttpUtils_NonblockingGet({
    url => "https://app.netatmo.net/api/getroommeasure",
    timeout => 20,
    noshutdown => 1,
    header => "Content-Type: application/json\r\nAuthorization: Bearer ".$iohash->{access_token_app},
    data => $json,
    hash => $hash,
    requested => $hash->{dataTypes},
    type => 'getmeasure',
    callback => \&netatmo_dispatch,
  });

  InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "netatmo_poll", $hash);
  $hash->{helper}{NEXT_POLL} = int(gettimeofday())+$hash->{helper}{INTERVAL};

  return undef;
}

sub
netatmo_setRoomMode($$;$)
{
  my ($hash,$set,$duration) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (setRoomMode)" if(!defined($iohash->{access_token}));

  my $json = encode_json( { home_id => $hash->{Home},
                            room_id => $hash->{Room},
                            mode => "$set" } );


  if(defined($duration) || $set eq "max")
  {
    $duration = AttrVal($name,"setpoint_duration",60) if(!defined($duration));
    my $endpoint = time + (60 * $duration);
    my $json = encode_json( { home_id => $hash->{Home},
                              room_id => $hash->{Room},
                              mode => "$set",
                              endtime => $endpoint } );
  }

  $json =~s/\"true\"/true/g;
  $json =~s/\"false\"/false/g;


  Log3 $name, 3, "$name: setRoomMode ($set)";

  HttpUtils_NonblockingGet({
      url => "https://".$iohash->{helper}{apiserver}."/syncapi/v1/setthermpoint",
      timeout => 20,
      noshutdown => 1,
      header => "Content-Type: application/json\r\nAuthorization: Bearer ".$iohash->{access_token},
      data => $json,
      hash => $hash,
      type => 'setroom',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setRoomTemp($$;$)
{
  my ($hash,$set,$duration) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (setRoomTemp)" if(!defined($iohash->{access_token}));

  $duration = AttrVal($name,"setpoint_duration",60) if(!defined($duration));
  my $endpoint = time + (60 * $duration);

  my $json = encode_json( { home_id => $hash->{Home},
                            room_id => $hash->{Room},
                            mode => "manual",
                            endtime => $endpoint,
                            temp => $set } );

  Log3 $name, 3, "$name: setRoomTemp ($set)";

  HttpUtils_NonblockingGet({
      url => "https://".$iohash->{helper}{apiserver}."/syncapi/v1/setthermpoint",
      timeout => 20,
      noshutdown => 1,
      header => "Content-Type: application/json\r\nAuthorization: Bearer ".$iohash->{access_token},
      data => $json,
      hash => $hash,
      type => 'setroom',
      callback => \&netatmo_dispatch,
    });


}


sub
netatmo_requestPersonReadings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );
  return undef if( !defined($hash->{Home}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (requestPersonReadings)" if(!defined($iohash->{access_token}));

  Log3 $name, 3, "$name: requestPersonReadings (getpersondata)";
  
  my %data = (access_token => $iohash->{access_token}, home_id => $hash->{Home}, person_id => $hash->{Person}, offset => '20');

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );

  HttpUtils_NonblockingGet({
    url => "https://".$iohash->{helper}{apiserver}."/api/getlasteventof",
    timeout => 20,
    noshutdown => 1,
    data => \%data,
    hash => $hash,
    type => 'getpersondata',
    callback => \&netatmo_dispatch,
  });
}

sub
netatmo_setPresence($$)
{
  my ($hash,$status) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshAppToken($iohash, defined($iohash->{access_token_app}));

  return Log3 $name, 1, "$name: No access token was found! (setPresence)" if(!defined($iohash->{access_token_app}));

  my $personid = $hash->{Person};

  my $urlstatus = $status;
  my $json;

  if($status eq "home")
  {
    $json = '{"home_id":"'.$hash->{Home}.'","person_ids":["'.$hash->{Person}.'"]}';
  }
  elsif($status eq "away")
  {
    $json = '{"home_id":"'.$hash->{Home}.'","person_id":"'.$hash->{Person}.'"}';
  }
  elsif($status eq "empty")
  {
    $json = '{"home_id":"'.$hash->{Home}.'"}';
    $urlstatus = "away";
  }

  Log3 $name, 5, "$name: setPresence ($status)";


  HttpUtils_NonblockingGet({
    url => "https://app.netatmo.net/api/setpersons".$urlstatus,
    timeout => 20,
    noshutdown => 1,
    method => "POST",
    header => "Content-Type: application/json\r\nAuthorization: Bearer ".$iohash->{access_token_app},
    data => $json,
    hash => $hash,
    type => 'setpersonsstatus_'.$status,
    callback => \&netatmo_dispatch,
  });


}


sub
netatmo_setNotifications($$$)
{
  my ($hash,$setting,$value) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshAppToken($iohash, defined($iohash->{access_token_app}));

  return Log3 $name, 1, "$name: No access token was found! (setNotifications)" if(!defined($iohash->{access_token_app}));

  if( !defined($iohash->{csrf_token}) )
  {
    my($err0,$data0) = HttpUtils_BlockingGet({
      url => "https://auth.netatmo.com/access/checklogin",
      timeout => 10,
      noshutdown => 1,
    });
    if($err0 || !defined($data0))
    {
      Log3 $name, 1, "$name: csrf call failed! ".$err0;
      return undef;
    }
    $data0 =~ /ci_csrf_netatmo" value="(.*)"/;
    my $tmptoken = $1;
    $iohash->{csrf_token} = $tmptoken;
    if(!defined($iohash->{csrf_token})) {
      Log3 $name, 1, "$name: CSRF ERROR ";
      return undef;
    }
    Log3 $name, 4, "$name: csrf_token ".$iohash->{csrf_token};
  }  
  
  my $homeid = $hash->{Home};

  my %data;
  
  if($setting eq "presence_notify_from" || $setting eq "presence_notify_to" || $setting eq "gone_after")
  {
    my @timevalue = split(":",$value);
    if(defined($timevalue[1]))
    {
      $value = int($timevalue[0])*3600 + int($timevalue[1])*60;
    }
    else
    {
      $value *= 60;
    }
    $value = 0 if($value < 0);
    $value = 86400 if($value > 86400 && $setting ne "gone_after");
  }
  elsif($setting eq "smart_notifs")
  {
    $value = (($value eq "on") ? "true" : "false");
  }

  if($setting eq "presence_enable_notify_from_to" || $setting =~ /^presence_record_/ || $setting =~ /^presence_notify_/ )
  {
    %data = (home_id => $homeid, 'presence_settings['.$setting.']' => $value, ci_csrf_netatmo => $iohash->{csrf_token});
  }
  else
  {
    %data = (home_id => $homeid, $setting => $value, ci_csrf_netatmo => $iohash->{csrf_token});
  }

  Log3 $name, 5, "$name: setNotifications ($setting $value)";


  HttpUtils_NonblockingGet({
    url => "https://app.netatmo.net/api/updatehome",
    timeout => 20,
    noshutdown => 1,
    method => "POST",
    header => "Content-Type: application/x-www-form-urlencoded; charset=UTF-8\r\nAuthorization: Bearer ".$iohash->{access_token_app},
    data => \%data,
    hash => $hash,
    type => 'sethomesettings',
    callback => \&netatmo_dispatch,
  });


}


sub
netatmo_setCamera($$$)
{
  my ($hash,$status,$pin) = @_;
  my $name = $hash->{NAME};

  my $commandurl = ReadingsVal( $name, "local_url", ReadingsVal( $name, "vpn_url", undef ) );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/changestatus?status=$status&pin=$pin";

  Log3 $name, 3, "$name: setCamera ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      timeout => 20,
      noshutdown => 1,
      verify_hostname => 0,
      hash => $hash,
      type => 'camerastatus',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setCameraSetting($$$)
{
  my ($hash,$setting,$newvalue) = @_;
  my $name = $hash->{NAME};

  #netatmo_pingCamera( $hash );

  my $commandurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/changesetting?$setting=$newvalue";

  Log3 $name, 3, "$name: setCameraSetting ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      timeout => 20,
      noshutdown => 1,
      verify_hostname => 0,
      hash => $hash,
      type => 'camerastatus',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setFloodlight($$)
{
  my ($hash,$setting) = @_;
  my $name = $hash->{NAME};

  #netatmo_pingCamera( $hash );

  my $commandurl = ReadingsVal( $name, "local_url", ReadingsVal( $name, "vpn_url", undef ) );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/floodlight_set_config?config=%7B%22mode%22:%22$setting%22%7D";

  Log3 $name, 3, "$name: setFloodlight ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      timeout => 20,
      noshutdown => 1,
      verify_hostname => 0,
      hash => $hash,
      type => 'camerastatus',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setIntensity($$)
{
  my ($hash,$setting) = @_;
  my $name = $hash->{NAME};

  #netatmo_pingCamera( $hash );


  my $commandurl = ReadingsVal( $name, "local_url", ReadingsVal( $name, "vpn_url", undef ) );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/floodlight_interactive_config?intensity=$setting";

  Log3 $name, 3, "$name: setIntensity ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      timeout => 20,
      noshutdown => 1,
      verify_hostname => 0,
      hash => $hash,
      type => 'camerastatus',
      callback => \&netatmo_dispatch,
    });


}


sub
netatmo_setPresenceConfig($$)
{
  my ($hash,$setting) = @_;
  my $name = $hash->{NAME};

  #netatmo_pingCamera( $hash );


  my $commandurl = ReadingsVal( $name, "local_url", ReadingsVal( $name, "vpn_url", undef ) );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/floodlight_set_config?config=%7B%22intensity%22:".ReadingsVal( $name, "intensity", 50 ).",%22night%22:%7B%22always%22:".ReadingsVal( $name, "night_always", "false" ).",%22animal%22:".ReadingsVal( $name, "night_animal", "false" ).",%22movement%22:".ReadingsVal( $name, "night_movement", "false" ).",%22person%22:".ReadingsVal( $name, "night_person", "true" ).",%22vehicle%22:".ReadingsVal( $name, "night_vehicle", "false" )."%7D%7D";

  Log3 $name, 3, "$name: setPresenceConfig ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      timeout => 20,
      noshutdown => 1,
      verify_hostname => 0,
      hash => $hash,
      type => 'camerastatus',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_getPresenceConfig($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #netatmo_pingCamera( $hash );


  my $commandurl = ReadingsVal( $name, "local_url", ReadingsVal( $name, "vpn_url", undef ) );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/floodlight_get_config";

  Log3 $name, 3, "$name: getPresenceConfig ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      timeout => 20,
      noshutdown => 1,
      verify_hostname => 0,
      hash => $hash,
      type => 'cameraconfig',
      callback => \&netatmo_dispatch,
    });


}


sub
netatmo_setTagCalibration($$)
{
  my ($hash,$setting) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{Camera}) );

  my $camerahash = $modules{$hash->{TYPE}}{defptr}{"C$hash->{Camera}"};
  return undef if( !defined($camerahash));

  #netatmo_pingCamera( $hash );


  my $commandurl = ReadingsVal( $camerahash->{NAME}, "local_url", ReadingsVal( $camerahash->{NAME}, "vpn_url", undef ) );

  return undef if(!defined($commandurl));

  $commandurl .= "/command/dtg_cal?id=".$hash->{Tag};

  Log3 $name, 3, "$name: setTagCalibration ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      timeout => 20,
      noshutdown => 1,
      verify_hostname => 0,
      hash => $hash,
      type => 'tagstatus',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setThermostatMode($$;$)
{
  my ($hash,$set,$duration) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (setThermostatMode)" if(!defined($iohash->{access_token}));

  my %data;
  %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, setpoint_mode => $set);

  if(defined($duration) || $set eq "max")
  {
    $duration = AttrVal($name,"setpoint_duration",60) if(!defined($duration));
    my $endpoint = time + (60 * $duration);
    %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, setpoint_mode => $set, setpoint_endtime => $endpoint);
  }


  Log3 $name, 3, "$name: setThermostatMode ($set)";

  HttpUtils_NonblockingGet({
      url => "https://".$iohash->{helper}{apiserver}."/api/setthermpoint",
      timeout => 20,
      noshutdown => 1,
      data => \%data,
      hash => $hash,
      type => 'setthermostat',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setThermostatTemp($$;$$)
{
  my ($hash,$set,$duration) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (setThermostatTemp)" if(!defined($iohash->{access_token}));

  $duration = AttrVal($name,"setpoint_duration",60) if(!defined($duration));
  my $endpoint = time + (60 * $duration);

  my %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, setpoint_mode => 'manual', setpoint_temp => $set, setpoint_endtime => $endpoint);

  Log3 $name, 3, "$name: setThermostatTemp ($set)";

  HttpUtils_NonblockingGet({
      url => "https://".$iohash->{helper}{apiserver}."/api/setthermpoint",
      timeout => 20,
      noshutdown => 1,
      data => \%data,
      hash => $hash,
      type => 'setthermostat',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setThermostatProgram($$)
{
  my ($hash,$set) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash, defined($iohash->{access_token}) );

  return Log3 $name, 1, "$name: No access token was found! (setThermostatProgram)" if(!defined($iohash->{access_token}));

  my $schedule_id = 0;
  foreach my $scheduledata ( @{$hash->{schedules}})
  {
    $schedule_id = @{$scheduledata}[1] if($set eq @{$scheduledata}[0]);
  }

  my %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, schedule_id => $schedule_id);

  Log3 $name, 3, "$name: setThermostatProgram ($set / $schedule_id)";

  HttpUtils_NonblockingGet({
      url => "https://".$iohash->{helper}{apiserver}."/api/switchschedule",
      timeout => 20,
      noshutdown => 1,
      data => \%data,
      hash => $hash,
      type => 'setthermostat',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_poll($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};


  if(IsDisabled($name) || !defined($name)) {
    RemoveInternalTimer($hash);
    $hash->{STATE} = "Disabled";
    return undef;
  }

  # my $resolve = inet_aton($hash->{helper}{apiserver});
  # if(!defined($resolve))
  # {
  #   Log3 $name, 1, "$name: DNS error on poll";
  #   InternalTimer( gettimeofday() + 1800, "netatmo_poll", $hash);
  #   return undef;
  # }
  $hash->{helper}{INTERVAL} = 3600 if(!defined($hash->{helper}{INTERVAL}));
  
  
  if(defined($hash->{status}) && ($hash->{status} =~ /usage/ || $hash->{status} =~ /too_many_connections/)) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}+1800, "netatmo_poll", $hash);
    Log3 $name, 1, "$name: API usage limit reached";
    $hash->{status} = "postponed update";
    readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
    return undef;
  }

  $hash->{status} = "ok";

  if( $hash->{SUBTYPE} eq "ACCOUNT" &&  defined($hash->{network}) &&  $hash->{network} eq "timeout" ) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+300, "netatmo_poll", $hash);
    $hash->{status} = "recovering timeout";
    netatmo_checkConnection($hash);
    readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
    return undef;
  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" &&  defined($hash->{network}) &&  $hash->{network} ne "ok" ) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+600, "netatmo_poll", $hash);
    $hash->{status} = "recovering network";
    netatmo_checkConnection($hash);
    readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
    Log3 $name, 5, "$name: ACCOUNT network error: ".$hash->{network};
    return undef;
  } elsif( $hash->{SUBTYPE} ne "ACCOUNT" &&  defined($hash->{IODev}->{network}) && $hash->{IODev}->{network} ne "ok" ) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+150, "netatmo_poll", $hash);
    $hash->{status} = "delayed update";
    #netatmo_checkConnection($hash->{IODev});
    readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
    Log3 $name, 5, "$name: DEVICE network error: ".$hash->{IODev}->{network};
    return undef;
  }


  Log3 $name, 3, "$name: poll ($hash->{SUBTYPE})";


  if( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    netatmo_pollGlobal($hash);
    netatmo_pollGlobalHealth($hash);
  } elsif( $hash->{SUBTYPE} eq "DEVICE" ) {
    netatmo_pollDevice($hash);
  } elsif( $hash->{SUBTYPE} eq "MODULE" ) {
    netatmo_pollDevice($hash);
  } elsif( $hash->{SUBTYPE} eq "PUBLIC" ) {
    netatmo_pollDevice($hash);
  } elsif( $hash->{SUBTYPE} eq "FORECAST" ) {
    netatmo_pollForecast($hash);
  } elsif( $hash->{SUBTYPE} eq "HOME" ) {
    netatmo_pollHome($hash);
  } elsif( $hash->{SUBTYPE} eq "CAMERA" ) {
    netatmo_pingCamera($hash);
  } elsif( $hash->{SUBTYPE} eq "RELAY" ) {
    netatmo_pollRelay($hash);
  } elsif( $hash->{SUBTYPE} eq "THERMOSTAT" ) {
    netatmo_pollThermostat($hash);
  } elsif( $hash->{SUBTYPE} eq "HEATINGHOME" ) {
    netatmo_pollHeatingHome($hash);
  } elsif( $hash->{SUBTYPE} eq "HEATINGROOM" ) {
    netatmo_pollHeatingRoom($hash);
  } elsif( $hash->{SUBTYPE} eq "PERSON" ) {
    netatmo_pollPerson($hash);
  } else {
    Log3 $name, 1, "$name: unknown netatmo type $hash->{SUBTYPE} on poll";
    return undef;
  }

  if( defined($hash->{helper}{update_count}) && $hash->{helper}{update_count} > 1024 ) {
    InternalTimer(gettimeofday()+30, "netatmo_poll", $hash);
  } else {
    $hash->{helper}{NEXT_POLL} = int(gettimeofday())+$hash->{helper}{INTERVAL};
    InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "netatmo_poll", $hash);
  }
}

sub
netatmo_dispatch($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if(!defined($param->{hash})){
    Log3 "netatmo", 2, "netatmo: ".$param->{type}."dispatch fail (hash missing)";
    return undef;
  }
  if(!defined($hash->{NAME})){
    Log3 "netatmo", 2, "netatmo: ".$param->{type}."dispatch fail (name missing)";
    return undef;
  }

  Log3 $name, 4, "$name: dispatch ($param->{type})";

  $hash->{openRequests} -= 1 if( $param->{type} eq 'getmeasure' );

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
    if($err =~ /refused/ ){
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+3600, "netatmo_poll", $hash);
      Log3 $name, 1, "$name: Possible IP Ban by Netatmo servers, try to change your IP and increase your request interval";
      $hash->{status} = "banned";
      $hash->{network} = "banned" if($hash->{SUBTYPE} eq "ACCOUNT");
    }
    elsif($err =~ /Invalid access token/){
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+300, "netatmo_poll", $hash);
      $hash->{status} = "token";
      $hash->{expires_at} = int(gettimeofday()) if($hash->{SUBTYPE} eq "ACCOUNT");
      $hash->{IODev}->{expires_at} = int(gettimeofday()) if($hash->{SUBTYPE} ne "ACCOUNT");
    }
    elsif($err =~ /Bad hostname/ || $err =~ /gethostbyname/){
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+600, "netatmo_poll", $hash);
      $hash->{status} = "timeout";
      $hash->{network} = "dns" if($hash->{SUBTYPE} eq "ACCOUNT");
    }
    elsif($err =~ /timed out/){
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+300, "netatmo_poll", $hash);
      $hash->{status} = "timeout";
      $hash->{network} = "timeout" if($hash->{SUBTYPE} eq "ACCOUNT");
    }
    elsif($err =~ /Can't connect/){
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+300, "netatmo_poll", $hash);
      $hash->{status} = "timeout";
      $hash->{network} = "disconnected" if($hash->{SUBTYPE} eq "ACCOUNT");
      #CommandDeleteReading( undef, "$hash->{NAME} vpn_url" ) if($hash->{SUBTYPE} eq "CAMERA");
    }
    readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
    return undef;
  } elsif( $data ) {
    $data =~ s/\n//g;
    if( $data !~ m/^{.*}$/ ) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+300, "netatmo_poll", $hash);
      Log3 $name, 2, "$name: invalid json detected";
      Log3 $name, 5, "$name: $data";
      $hash->{status} = "error";
      $hash->{network} = "ok" if($hash->{SUBTYPE} eq "ACCOUNT");
      $hash->{IODev}->{network} = "ok" if($hash->{SUBTYPE} ne "ACCOUNT");
      readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
      return undef;
    }

    $hash->{network} = "ok" if($hash->{SUBTYPE} eq "ACCOUNT");
    $hash->{IODev}->{network} = "ok" if($hash->{SUBTYPE} ne "ACCOUNT");

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    if($@)
    {
      Log3 $name, 2, "$name: invalid json evaluation on dispatch type ".$param->{type}." ".$@;
      return undef;
    }

    Log3 "unknown", 2, "unknown (no name) ".Dumper($hash) if(!defined($name));
    Log3 $name, 4, "$name: dispatch return: ".$param->{type};
    Log3 $name, 5, Dumper($json);

    if( $json->{error} ) {
      if(ref($json->{error}) ne "HASH") {
        $hash->{STATE} = "LOGIN FAILED" if($hash->{SUBTYPE} eq "ACCOUNT");
        $hash->{status} = $json->{error};
        Log3 $name, 2, "$name: json message error: ".$json->{error};
        readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
        return undef;
      }

      $hash->{status} = $json->{error}{message} if(defined($json->{error}{message}));
      InternalTimer(gettimeofday()+1800, "netatmo_poll", $hash, 0) if($hash->{status} =~ /usage/ || $hash->{status} =~ /too_many_connections/);
      readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
      return undef if($hash->{status} =~ /usage/ || $hash->{status} =~ /too_many_connections/);
    }
    

    if( $param->{type} eq 'token' ) {
      netatmo_parseToken($hash,$json);
    } elsif( $param->{type} eq 'apptoken' ) {
      netatmo_parseAppToken($hash,$json);
    } elsif( $param->{type} eq 'devicelist' ) {
      netatmo_parseDeviceList($hash,$json);
    } elsif( $param->{type} eq 'stationsdata' ) {
      netatmo_parseGlobal($hash,$json);
    } elsif( $param->{type} eq 'forecastdata' ) {
      netatmo_parseForecast($hash,$json);
    } elsif( $param->{type} eq 'getmeasure' ) {
      netatmo_parseReadings($hash,$json,$param->{requested});
    } elsif( $param->{type} eq 'homelist' ) {
      netatmo_parseHomeList($hash,$json);
    } elsif( $param->{type} eq 'gethomedata' ) {
      netatmo_parseHomeReadings($hash,$json);
    } elsif( $param->{type} eq 'cameraping' ) {
      netatmo_parseCameraPing($hash,$json);
    } elsif( $param->{type} eq 'camerastatus' ) {
      netatmo_parseCameraStatus($hash,$json);
    } elsif( $param->{type} eq 'cameraconfig' ) {
      netatmo_parseCameraConfig($hash,$json);
    } elsif( $param->{type} eq 'tagstatus' ) {
      netatmo_parseTagStatus($hash,$json);
    } elsif( $param->{type} eq 'cameravideo' ) {
      netatmo_parseCameraVideo($hash,$json);
    } elsif( $param->{type} =~ /setpersonsstatus_/ ) {
      netatmo_parsePersonsStatus($hash,$json,$param->{type});
    } elsif( $param->{type} eq 'homecoachlist' ) {
      netatmo_parseHomecoachList($hash,$json);
    } elsif( $param->{type} eq 'thermostatlist' ) {
      netatmo_parseThermostatList($hash,$json);
    } elsif( $param->{type} eq 'getthermostatsdata' ) {
      netatmo_parseThermostatReadings($hash,$json);
    } elsif( $param->{type} eq 'setthermostat' ) {
      netatmo_parseThermostatStatus($hash,$json);
    } elsif( $param->{type} eq 'getheatinghomedata' ) {
      netatmo_parseHeatingHomeStatus($hash,$json);
    } elsif( $param->{type} eq 'getpersondata' ) {
      netatmo_parsePersonReadings($hash,$json);
    } elsif( $param->{type} eq 'publicdata' ) {
      return netatmo_parsePublic($hash,$json);
    } elsif( $param->{type} eq 'address' ) {
      return netatmo_parseAddress($hash,$json);
    } elsif( $param->{type} eq 'latlng' ) {
      return netatmo_parseLatLng($hash,$json);
    } elsif( $param->{type} eq 'addwebhook' ) {
      return netatmo_webhookStatus($hash,$json,"added");
    } elsif( $param->{type} eq 'dropwebhook' ) {
      return netatmo_webhookStatus($hash,$json,"dropped");
    } elsif( $param->{type} eq 'sethomesettings' ) {
      return netatmo_refreshHomeSettings($hash);
    } else {
      Log3 $name, 1, "$name: unknown '$param->{type}' ".Dumper($json);
    }
  }
}


sub
netatmo_parsePersonsStatus($$$)
{
  my ($hash, $json, $param) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: parsePersonsStatus ($param)\n".Dumper($json);

  return if(!defined($json->{status}) || $json->{status} ne "ok");

  if($hash->{SUBTYPE} eq "PERSON")
  {
    if($param =~ /away/)
    {
      readingsSingleUpdate( $hash, "status", "away", 1 );
    }
    else{
      readingsSingleUpdate( $hash, "status", "home", 1 );
    }
  }
  elsif($hash->{SUBTYPE} eq "HOME")
  {
    readingsSingleUpdate( $hash, "event", "Everyone left", 1 );
  }


}

sub
netatmo_autocreate($;$)
{
  my($hash,$force) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{devices} ) {
    netatmo_getDevices($hash,1);
    return undef if( !$force );
  }

  if( !$force ) {
    foreach my $d (keys %defs) {
      next if(!defined($defs{$d}));
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(IsDisabled($defs{$d}{NAME}));
    }
  }

  my $autocreated = 0;

  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"D$device->{_id}"}) ) {
      Log3 $name, 4, "$name: device '$device->{_id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"M$device->{_id}"}) ) {
      Log3 $name, 4, "$name: module '$device->{_id}' already defined";
      next;
    }
    if(AttrVal($name,"ignored_device_ids","") =~ /$device->{_id}/) {
      Log3 $name, 4, "$name: '$device->{_id}' ignored for autocreate";
      next;
    }

    my $id = $device->{_id};
    my $devname = "netatmo_D". $id;
    $devname =~ s/:/_/g;
    my $define= "$devname netatmo $id";
    if( $device->{main_device} ) {
      $devname = "netatmo_M". $id;
      $devname =~ s/:/_/g;
      $define= "$devname netatmo MODULE $device->{main_device} $id";
    }

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($device->{module_name})) if( defined($device->{module_name}) );
      $cmdret= CommandAttr(undef,"$devname room netatmo");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname devStateIcon .*:no-icon");
      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );

  return "created $autocreated devices";
}

sub
netatmo_autocreatehome($;$)
{
  my($hash,$force) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{homes} ) {
    return undef if( !$force );
    netatmo_getHomes($hash,1);
  }

  if( !$force ) {
    foreach my $d (keys %defs) {
      next if(!defined($defs{$d}));
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(IsDisabled($defs{$d}{NAME}));
    }
  }

  my $autocreated = 0;
  my $homes = $hash->{helper}{homes};
  foreach my $home (@{$homes}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"H$home->{id}"}) ) {
      Log3 $name, 4, "$name: home '$home->{id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"P$home->{id}"}) ) {
      Log3 $name, 4, "$name: person '$home->{id}' already defined";
      next;
    }
    foreach my $module (@{$home->{modules}}) {
      if( defined($modules{$hash->{TYPE}}{defptr}{"G$module->{id}"}) ) {
        Log3 $name, 4, "$name: tag '$module->{id}' already defined";
        next;
      }
      my $tagid = $module->{id};
      my $tagdevname = "netatmo_G". $tagid;
      $tagdevname =~ s/:/_/g;

      my $tagdefine= "$tagdevname netatmo TAG $home->{id} $tagid";
      Log3 $name, 3, "$name: create new tag '$tagdevname' for camera '$home->{id}'";
      my $tagcmdret= CommandDefine(undef,$tagdefine);

      if($tagcmdret) {
        Log3 $name, 1, "$name: Autocreate: An error occurred while creating tag for id '$tagid': $tagcmdret";
      } else {
        $tagcmdret= CommandAttr(undef,"$tagdevname alias ".encode_utf8($module->{name})) if( defined($module->{name}) );
        $tagcmdret= CommandAttr(undef,"$tagdevname devStateIcon .*:no-icon");
        $tagcmdret= CommandAttr(undef,"$tagdevname room netatmo");
        $tagcmdret= CommandAttr(undef,"$tagdevname stateFormat status");
        $tagcmdret= CommandAttr(undef,"$tagdevname IODev $name");

        $autocreated++;
      }
      
      
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"C$home->{id}"}) ) {
      Log3 $name, 4, "$name: camera '$home->{id}' already defined";
      next;
    }
    if(AttrVal($name,"ignored_device_ids","") =~ /$home->{id}/) {
      Log3 $name, 4, "$name: '$home->{id}' ignored for autocreate";
      next;
    }

    my $id = $home->{id};
    my $devname = "netatmo_H". $id;
    $devname =~ s/-/_/g;
    my $define= "$devname netatmo HOME $id";
    if( $home->{sd_status} ) {
      $devname = "netatmo_C". $id;
      $devname =~ s/:/_/g;
      $devname =~ s/-/_/g;
      $define= "$devname netatmo CAMERA $home->{home} $id";
    }
    elsif( $home->{face} ) {
      next if(!defined($home->{pseudo})); #ignore unassigned faces
      Log3 $name, 5, "$name: create new home/person '$devname' for home '$home->{home}'".Dumper($home);

      $devname = "netatmo_P". $id;
      $devname =~ s/-/_/g;
      $define= "$devname netatmo PERSON $home->{home} $id";
    }
    $home->{home} = "?" if(!defined($home->{home}));
    Log3 $name, 3, "$name: create new home/person '$devname' for home '$home->{home}'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating home for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias Unknown") if( defined($home->{face}) );
      $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($home->{pseudo})) if( defined($home->{pseudo}) );
      $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($home->{name})) if( defined($home->{name}) );
      $cmdret= CommandAttr(undef,"$devname devStateIcon .*:no-icon");
      $cmdret= CommandAttr(undef,"$devname room netatmo");
      $cmdret= CommandAttr(undef,"$devname stateFormat status");
      $cmdret= CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );

  return "created $autocreated devices";
}

sub
netatmo_autocreatethermostat($;$)
{
  my($hash,$force) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{thermostats} ) {
    netatmo_getThermostats($hash,1);
    return undef if( !$force );
  }

  if( !$force ) {
    foreach my $d (keys %defs) {
      next if(!defined($defs{$d}));
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(IsDisabled($defs{$d}{NAME}));
    }
  }

  my $autocreated = 0;

  my $devices = $hash->{helper}{thermostats};
  
  #Log3 $name, 1, "$name: autocreating ".Dumper($devices);

  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"R$device->{id}"}) ) {
      Log3 $name, 4, "$name: relay '$device->{id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"T$device->{id}"}) ) {
      Log3 $name, 4, "$name: thermostat '$device->{id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"E$device->{id}"}) ) {
      Log3 $name, 4, "$name: heating home '$device->{id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"O$device->{id}"}) ) {
      Log3 $name, 4, "$name: heating room '$device->{id}' already defined";
      next;
    }
    if(AttrVal($name,"ignored_device_ids","") =~ /$device->{id}/) {
      Log3 $name, 4, "$name: '$device->{id}' ignored for autocreate";
      next;
    }

    my $id = $device->{id};
    my $devname = "netatmo_R". $id;
    $devname =~ s/:/_/g;
    my $define= "$devname netatmo RELAY $id";
    if( $device->{type} eq "Home" ) {
      next;
      $devname = "netatmo_E". $id;
      $devname =~ s/:/_/g;
      $define= "$devname netatmo HEATINGHOME $id";
    }
    elsif( $device->{type} eq "Room" ) {
      next;
      $devname = "netatmo_O". $id;
      $devname =~ s/:/_/g;
      $define= "$devname netatmo HEATINGROOM $device->{Home} $id";
    }
    elsif( $device->{main_device} ) {
      $devname = "netatmo_T". $id;
      $devname =~ s/:/_/g;
      $define= "$devname netatmo THERMOSTAT $device->{main_device} $id";
    }

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($device->{name})) if( defined($device->{name}) );
      #$cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($device->{module_name})) if( defined($device->{module_name}) );
      $cmdret= CommandAttr(undef,"$devname room netatmo");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname devStateIcon .*:no-icon");
      $cmdret= CommandAttr(undef,"$devname stateFormat setpoint|temperature") if( $device->{main_device} );
      $cmdret= CommandAttr(undef,"$devname stateFormat active") if( !$device->{main_device} );
      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );

  return "created $autocreated devices";
}

sub
netatmo_autocreatehomecoach($;$)
{
  my($hash,$force) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{homecoachs} ) {
    netatmo_getHomecoachs($hash,1);
    return undef if( !$force );
  }

  if( !$force ) {
    foreach my $d (keys %defs) {
      next if(!defined($defs{$d}));
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(IsDisabled($defs{$d}{NAME}));
    }
  }

  my $autocreated = 0;

  my $devices = $hash->{helper}{homecoachs};
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"D$device->{_id}"}) ) {
      Log3 $name, 4, "$name: homecoach '$device->{_id}' already defined";
      next;
    }
    if(AttrVal($name,"ignored_device_ids","") =~ /$device->{_id}/) {
      Log3 $name, 4, "$name: '$device->{_id}' ignored for autocreate";
      next;
    }

    my $id = $device->{_id};
    my $devname = "netatmo_D". $id;
    $devname =~ s/:/_/g;
    my $define= "$devname netatmo $id";

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($device->{name})) if( defined($device->{name}) );
      $cmdret= CommandAttr(undef,"$devname room netatmo");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname devStateIcon .*:no-icon");
      $cmdret= CommandAttr(undef,"$devname stateFormat health_idx");
      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );

  return "created $autocreated devices";
}

sub
netatmo_parseToken($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  my $had_token = $hash->{access_token};

  $hash->{access_token} = $json->{access_token};
  $hash->{refresh_token} = $json->{refresh_token};

  if( $hash->{access_token} ) {
    $hash->{STATE} = "Connected";
    $hash->{network} = "ok";

    $hash->{expires_at} = int(gettimeofday());
    $hash->{expires_at} += int($json->{expires_in}*0.8);

    netatmo_getDevices($hash) if( !$had_token );

    InternalTimer($hash->{expires_at}, "netatmo_refreshTokenTimer", $hash);
  } else {
    $hash->{expires_at} = int(gettimeofday());
    $hash->{STATE} = "Error" if( !$hash->{access_token} );
    Log3 $name, 1, "$name: token error ".Dumper($json);
    InternalTimer(gettimeofday()+600, "netatmo_refreshTokenTimer", $hash);
  }
}

sub
netatmo_parseAppToken($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  $hash->{access_token_app} = $json->{access_token};
  $hash->{refresh_token_app} = $json->{refresh_token};

  if( $hash->{access_token_app} ) {

    $hash->{expires_at_app} = int(gettimeofday());
    $hash->{expires_at_app} += int($json->{expires_in}*0.8);

     InternalTimer($hash->{expires_at_app}, "netatmo_refreshAppTokenTimer", $hash);
   } else {
     $hash->{expires_at_app} = int(gettimeofday());
     $hash->{STATE} = "Error" if( !$hash->{access_token_app} );
     Log3 $name, 1, "$name: app token error ".Dumper($json);
     InternalTimer(gettimeofday()+600, "netatmo_refreshAppTokenTimer", $hash);
   }
}

sub
netatmo_parseDeviceList($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parsedevicelist ";

  #my $do_autocreate = 1;
  #$do_autocreate = 0 if( !defined($hash->{helper}{devices}) ); #autocreate

  my @devices = ();
  foreach my $device (@{$json->{body}{devices}}) {
    push( @devices, $device );


    foreach my $module (@{$device->{modules}}) {
      $module->{main_device} = $device->{_id};
      push( @devices, $module );


    }
  }

  $hash->{helper}{devices} = \@devices;

  #netatmo_autocreate($hash) if( $do_autocreate );
}

sub
netatmo_parseHomeList($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  #my $do_autocreate = 1;
  #$do_autocreate = 0 if( !defined($hash->{helper}{homes}) ); #autocreate

  Log3 $name, 5, "$name: parsehomelist";

  my @homes = ();
  foreach my $home (@{$json->{body}{homes}}) {
    push( @homes, $home ) if(defined($home->{cameras}) && @{$home->{cameras}});
    foreach my $camera (@{$home->{cameras}}) {
      $camera->{home} = $home->{id};
      push( @homes, $camera ) if(defined($camera->{status}));
    }
    foreach my $person (@{$home->{persons}}) {
      $person->{home} = $home->{id};
      push( @homes, $person ) if(defined($person->{face}));
    }
  }

  $hash->{helper}{homes} = \@homes;

  #netatmo_autocreatehome($hash) if( $do_autocreate );
}

sub
netatmo_parseThermostatList($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parsethermostatlist ";

  #my $do_autocreate = 1;
  #$do_autocreate = 0 if( !defined($hash->{helper}{devices}) ); #autocreate

  my @devices = ();
  foreach my $home (@{$json->{body}{homes}}) {
    
    next if(!defined($home->{devices}) || !@{$home->{devices}});
    $home->{type} = "Home";
    $home->{firmware} = "-";
    push( @devices, $home );
    
    foreach my $room (@{$home->{rooms}}) {
      next if(!defined($room->{modules}) || !@{$room->{modules}});

      $room->{Home} = $home->{id};
      $room->{type} = "Room";
      $room->{firmware} = "-";
      push( @devices, $room );

    }

    foreach my $device (@{$home->{devices}}) {
    push( @devices, $device );


    foreach my $module (@{$device->{modules}}) {

        $module->{main_device} = $device->{id};
      push( @devices, $module );


    }
  }
  }

  $hash->{helper}{thermostats} = \@devices;

  #netatmo_autocreate($hash) if( $do_autocreate );
}


sub
netatmo_parseHomecoachList($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parsehomecoachlist ";

  #my $do_autocreate = 1;
  #$do_autocreate = 0 if( !defined($hash->{helper}{devices}) ); #autocreate

  my @devices = ();
  foreach my $device (@{$json->{body}{devices}}) {
    push( @devices, $device );

    foreach my $module (@{$device->{modules}}) {
      $module->{main_device} = $device->{_id};
      push( @devices, $module );
    }
  }

  $hash->{helper}{homecoachs} = \@devices;

  #netatmo_autocreate($hash) if( $do_autocreate );
}

sub
netatmo_updateReadings($$)
{
  my($hash, $readings) = @_;
  my $name = $hash->{NAME};

  my ($seconds) = gettimeofday();

  my $latest = 0;
  if( $readings && @{$readings} ) {
    my $i = 0;
    foreach my $reading (sort { $a->[0] <=> $b->[0] } @{$readings}) {
      if(!defined($reading->[0]) || !defined($reading->[1]) || !defined($reading->[2]))
      {
        Log3 $name, 1, "$name: invalid readings set: ".Dumper($reading);
        next;
      }
      readingsBeginUpdate($hash);
      $hash->{".updateTimestamp"} = FmtDateTime($reading->[0]);
      readingsBulkUpdate( $hash, $reading->[1], $reading->[2] );
      $hash->{CHANGETIME}[0] = FmtDateTime($reading->[0]);
      readingsEndUpdate($hash,1);
      $latest = $reading->[0] if( $reading->[0] > $latest );
    }
    readingsSingleUpdate( $hash, ".lastupdate", $seconds, 0 );

    Log3 $name, 4, "$name: updatereadings";

  }

  return ($seconds,$latest);
}
sub
netatmo_parseReadings($$;$)
{
  my($hash, $json, $requested) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parsereadings ".$requested;

  my $reading_names = $hash->{helper}{readingNames};
  if( $requested ) {
    my @readings = split( ',', $requested );
    $reading_names = \@readings;
  }

  if( $json ) {
    $hash->{status} = $json->{status} if($json->{status});
    $hash->{status} = $json->{error}{message} if( $json->{error} );

    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );

    my @r = ();
    my $readings = \@r;
    $readings = $hash->{readings} if( defined($hash->{readings}) );

    my ($time,$step_time,$last_time) = 0;

    if( $hash->{status} eq "ok" ) 
    {

      if(scalar(@{$json->{body}}) == 0)
      {
        $hash->{status} = "no data";
        readingsSingleUpdate( $hash, "active", "dead", 1 ) if($hash->{helper}{last_status_store} > 0 && $hash->{helper}{last_status_store} < (int(time) - 7200) );
      }

      foreach my $values ( @{$json->{body}}) {
        $time = $values->{beg_time};
        $step_time = $values->{step_time};

        foreach my $value (@{$values->{value}}) {
          my $i = 0;
          foreach my $reading (@{$value}) {

            #my $rname = $hash->{helper}{readingNames}[$i++];
            my $rname = lc($reading_names->[$i++]);

            if( !defined($reading) )
            {
              $reading = "undefined";#next;
            }
            if(lc($requested) =~ /wind/ && ($rname eq "temperature" || $rname eq "humidity"))
            {
              Log3 $name, 3, "$name netatmo - wind sensor $rname reading: $reading ($time)";
              next;# if($reading == 0);
            }


            if($reading ne "undefined" && (($rname eq "noise" && int($reading) > 150) || ($rname eq "temperature" && int($reading) > 60) || ($rname eq "humidity" && int($reading) > 100) || ($rname eq "pressure" && int($reading) < 500)))
            {
              Log3 $name, 1, "$name netatmo - invalid reading: $rname: ".Dumper($reading)." \n    ".Dumper($reading_names);
             next;
            }

            if($reading ne "undefined" && $rname eq "health_idx"){
              $reading = $health_index{$reading};
            }

            if($reading ne "undefined" && $rname =~ /temperature/){
              $reading = sprintf( "%.1f", $reading);
            }

            # if($reading ne "undefined" && $rname eq "rain" && $reading > 0)
            # {
            #   my $rain_sum = ReadingsVal($name,"rain_sum",0);
            #   $rain_sum += $reading;
            #   readingsSingleUpdate($hash,"rain_sum",$rain_sum,1);
            #   Log3 $name, 2, $name.": summed rain ".$reading." (to ".$rain_sum.")";
            # }


            push(@{$readings}, [$time, $rname, $reading]) if($reading ne "undefined");
            
          }
          $last_time = $time if(defined($time));

          $time += $step_time if( $step_time );

        }
        $hash->{helper}{last_status_store} = $last_time if($last_time > $hash->{helper}{last_status_store});
      }

      if( $hash->{openRequests} > 1 ) {
        $hash->{readings} = $readings;
      } else {
        my ($seconds,undef) = netatmo_updateReadings( $hash, $readings );
        $hash->{LAST_POLL} = FmtDateTime( $seconds );
        delete $hash->{readings};
#        readingsSingleUpdate($hash, ".lastupdate", $last_time, 0);
      }
    
      
      if(defined(AttrVal($name, "interval", undef))){
        $hash->{helper}{NEXT_POLL} = int(gettimeofday())+$hash->{helper}{INTERVAL};
        RemoveInternalTimer($hash, "netatmo_poll");
        InternalTimer($hash->{helper}{NEXT_POLL}, "netatmo_poll", $hash);
        Log3 $name, 3, "$name: next fixed interval update for device ($requested) at ".FmtDateTime($hash->{helper}{NEXT_POLL});
      } elsif(defined($last_time) && int($last_time) > 0 && defined($step_time)) {
        my $nextdata = $last_time + 2*$step_time + 10 + int(rand(20));
        
        if($hash->{SUBTYPE} eq "MODULE")
        {
          my $devicehash = $modules{$hash->{TYPE}}{defptr}{"D$hash->{Device}"};
          if(defined($devicehash) && defined($devicehash->{helper}{NEXT_POLL}))
          {
            $nextdata = ($devicehash->{helper}{NEXT_POLL} + 10 + int(rand(20)) ) if($devicehash->{helper}{NEXT_POLL} >= gettimeofday()+150);
            if($nextdata >= (gettimeofday()+155))
            {
              RemoveInternalTimer($hash, "netatmo_poll");
              InternalTimer($nextdata, "netatmo_poll", $hash);
              $hash->{helper}{NEXT_POLL} = $nextdata;
              Log3 $name, 3, "$name: next dynamic update from device ($requested) at ".FmtDateTime($nextdata);
            } else {
              $nextdata += $step_time;
              if($nextdata >= (gettimeofday()+155))
              {
                RemoveInternalTimer($hash, "netatmo_poll");
                InternalTimer($nextdata, "netatmo_poll", $hash);
                $hash->{helper}{NEXT_POLL} = $nextdata;
                Log3 $name, 3, "$name: next extended dynamic update from device ($requested) at ".FmtDateTime($nextdata);
              } else {
              Log3 $name, 2, "$name: invalid time for dynamic update from device ($requested): ".FmtDateTime($nextdata);
            }
          }
        }
        }
        elsif($nextdata >= (gettimeofday()+280))
        {
          $nextdata = $nextdata + 10 + int(rand(20));
          RemoveInternalTimer($hash, "netatmo_poll");
          InternalTimer($nextdata, "netatmo_poll", $hash);
          $hash->{helper}{NEXT_POLL} = $nextdata;
          Log3 $name, 3, "$name: next dynamic update ($requested) at ".FmtDateTime($nextdata);
        } else {
          $nextdata += $step_time;
          if($nextdata >= (gettimeofday()+280))
          {
            RemoveInternalTimer($hash, "netatmo_poll");
            InternalTimer($nextdata, "netatmo_poll", $hash);
            $hash->{helper}{NEXT_POLL} = $nextdata;
            Log3 $name, 3, "$name: next extended dynamic update ($requested) at ".FmtDateTime($nextdata);
          } else {
          Log3 $name, 2, "$name: invalid time for dynamic update ($requested): ".FmtDateTime($nextdata);
          }
        }
      } elsif(defined($last_time) && int($last_time) > 0) {
        my $nextdata = int($last_time)+(12*60);
        $nextdata = int(gettimeofday()+280) if($nextdata <= (gettimeofday()+280));
        RemoveInternalTimer($hash, "netatmo_poll");
        InternalTimer($nextdata, "netatmo_poll", $hash);
        $hash->{helper}{NEXT_POLL} = $nextdata;
        Log3 $name, 3, "$name: next predictive update for device ($requested) at ".FmtDateTime($nextdata);
      } else {
        $hash->{helper}{NEXT_POLL} = int(gettimeofday())+(12*60);
        RemoveInternalTimer($hash, "netatmo_poll");
        InternalTimer($hash->{helper}{NEXT_POLL}, "netatmo_poll", $hash);
        Log3 $name, 3, "$name: next fixed update for device ($requested) at ".FmtDateTime($hash->{helper}{NEXT_POLL});
      }
    }
  }
  else
  {
    $hash->{status} = "error";
  }

  if($hash->{helper}{last_status_store} > 0 && $hash->{helper}{last_status_store} < (int(time) - $hash->{helper}{INTERVAL} - 7200) ) {
    readingsSingleUpdate( $hash, "active", "dead", 1 );    
  } else {
    readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");
  }

}


sub
netatmo_parseGlobal($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseGlobal";

  if( $json )
  {
    Log3 $name, 5, "$name: ".Dumper($json);

    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );
    my @r = ();
    my $readings = \@r;
    $readings = $hash->{readings} if( defined($hash->{readings}) );
    if( $hash->{status} eq "ok" )
    {
      $hash->{STATE} = "Connected";
      foreach my $devicedata ( @{$json->{body}{devices}})
      {

        #Log3 $name, 5, "$name: device " . "D$devicedata->{_id} " .Dumper($devicedata);

        my $device = $modules{$hash->{TYPE}}{defptr}{"D$devicedata->{_id}"};
        next if (!defined($device));

        #Log3 $name, 4, "$name: device " . "D$devicedata->{_id} found";

        if(defined($devicedata->{dashboard_data}{AbsolutePressure}) && $devicedata->{dashboard_data}{AbsolutePressure} ne $devicedata->{dashboard_data}{Pressure})
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsBulkUpdate( $device, "pressure_abs", $devicedata->{dashboard_data}{AbsolutePressure}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{pressure_trend}))
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsBulkUpdate( $device, "pressure_trend", $devicedata->{dashboard_data}{pressure_trend}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{temp_trend}))
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsBulkUpdate( $device, "temp_trend", $devicedata->{dashboard_data}{temp_trend}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{max_temp}) && $devicedata->{type} ne "NAModule2")
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{date_max_temp});
          readingsBulkUpdate( $device, "temp_max", $devicedata->{dashboard_data}{max_temp}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{date_max_temp});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{min_temp}) && $devicedata->{type} ne "NAModule2")
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{date_min_temp});
          readingsBulkUpdate( $device, "temp_min", $devicedata->{dashboard_data}{min_temp}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{date_min_temp});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{sum_rain_1}))
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsBulkUpdate( $device, "rain_hour", $devicedata->{dashboard_data}{sum_rain_1}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{sum_rain_24}))
        {
          #my $rain_day = ReadingsVal($device->{NAME},"rain_day",0);
          # if($devicedata->{dashboard_data}{sum_rain_24} < $rain_day)
          # {
          #   my $rain_total = ReadingsVal($device->{NAME},"rain_total",0);
          #   $rain_total += $rain_day;
          #   readingsSingleUpdate($device,"rain_total",$rain_total,1);
          #   Log3 $name, 1, $device->{NAME}.": added rain ".$rain_day." (to ".$rain_total.")";
          # }
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsBulkUpdate( $device, "rain_day", $devicedata->{dashboard_data}{sum_rain_24}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{time_utc});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{max_wind_str}))
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{date_max_wind_str});
          readingsBulkUpdate( $device, "windstrength_max", $devicedata->{dashboard_data}{max_wind_str}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{date_max_wind_str});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{max_wind_angle}))
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{date_max_wind_str});
          readingsBulkUpdate( $device, "windangle_max", $devicedata->{dashboard_data}{max_wind_angle}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{date_max_wind_str});
          readingsEndUpdate($device,1);
        }
        if(defined($devicedata->{dashboard_data}{health_idx}) && $devicedata->{type} ne "NHC")
        {
          readingsBeginUpdate($device);
          $device->{".updateTimestamp"} = FmtDateTime($devicedata->{dashboard_data}{health_idx});
          readingsBulkUpdate( $device, "health_idx", $devicedata->{dashboard_data}{health_idx}, 1 );
          $device->{CHANGETIME}[0] = FmtDateTime($devicedata->{dashboard_data}{health_idx});
          readingsEndUpdate($device,1);
        }

        $device->{co2_calibrating} = $devicedata->{co2_calibrating} if(defined($devicedata->{co2_calibrating}));
        $device->{last_status_store} = FmtDateTime($devicedata->{last_status_store}) if(defined($devicedata->{last_status_store}));
        $device->{helper}{last_status_store} = $devicedata->{last_status_store} if(defined($devicedata->{last_status_store}) && $devicedata->{last_status_store} > $device->{helper}{last_status_store});
        $device->{last_message} = FmtDateTime($devicedata->{last_message}) if(defined($devicedata->{last_message}));
        $device->{last_seen} = FmtDateTime($devicedata->{last_seen}) if(defined($devicedata->{last_seen}));
        $device->{wifi_status} = $devicedata->{wifi_status} if(defined($devicedata->{wifi_status}));
        $device->{rf_status} = $devicedata->{rf_status} if(defined($devicedata->{rf_status}));
        #$device->{battery_percent} = $devicedata->{battery_percent} if(defined($devicedata->{battery_percent}));
        #$device->{battery_vp} = $devicedata->{battery_vp} if(defined($devicedata->{battery_vp}));

        readingsSingleUpdate($device, "batteryState", ($devicedata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($devicedata->{battery_percent}));
        readingsSingleUpdate($device, "batteryPercent", $devicedata->{battery_percent}, 1) if(defined($devicedata->{battery_percent}));
        readingsSingleUpdate($device, "batteryVoltage", $devicedata->{battery_vp}/1000, 1) if(defined($devicedata->{battery_vp}));

        if(defined($devicedata->{modules}))
        {
          foreach my $moduledata ( @{$devicedata->{modules}})
          {

            #Log3 $name, 5, "$name: module "."M$moduledata->{_id} ".Dumper($moduledata);

            my $module = $modules{$hash->{TYPE}}{defptr}{"M$moduledata->{_id}"};
            next if (!defined($module));


            if(defined($moduledata->{dashboard_data}{AbsolutePressure}))
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsBulkUpdate( $module, "pressure_abs", $moduledata->{dashboard_data}{AbsolutePressure}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{pressure_trend}))
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsBulkUpdate( $module, "pressure_trend", $moduledata->{dashboard_data}{pressure_trend}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{temp_trend}))
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsBulkUpdate( $module, "temp_trend", $moduledata->{dashboard_data}{temp_trend}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{max_temp}) && $moduledata->{type} ne "NAModule2")
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{date_max_temp});
              readingsBulkUpdate( $module, "temp_max", $moduledata->{dashboard_data}{max_temp}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{date_max_temp});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{min_temp}) && $moduledata->{type} ne "NAModule2")
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{date_min_temp});
              readingsBulkUpdate( $module, "temp_min", $moduledata->{dashboard_data}{min_temp}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{date_min_temp});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{sum_rain_1}))
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsBulkUpdate( $module, "rain_hour", $moduledata->{dashboard_data}{sum_rain_1}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{sum_rain_24}))
            {
              my $rain_day = ReadingsVal($module->{NAME},"rain_day",0);
              if($moduledata->{dashboard_data}{sum_rain_24} < $rain_day)
              {
                my $rain_total = ReadingsVal($module->{NAME},"rain_total",0);
                $rain_total += $rain_day;
                readingsSingleUpdate($module,"rain_total",$rain_total,1);
                Log3 $name, 1, $module->{NAME}.":_added rain ".$rain_day." (to ".$rain_total.")";
              }
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsBulkUpdate( $module, "rain_day", $moduledata->{dashboard_data}{sum_rain_24}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{time_utc});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{max_wind_str}))
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{date_max_wind_str});
              readingsBulkUpdate( $module, "windstrength_max", $moduledata->{dashboard_data}{max_wind_str}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{date_max_wind_str});
              readingsEndUpdate($module,1);
            }
            if(defined($moduledata->{dashboard_data}{max_wind_angle}))
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{dashboard_data}{date_max_wind_str});
              readingsBulkUpdate( $module, "windangle_max", $moduledata->{dashboard_data}{max_wind_angle}, 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{dashboard_data}{date_max_wind_str});
              readingsEndUpdate($module,1);
            }

            $module->{co2_calibrating} = $moduledata->{co2_calibrating} if(defined($moduledata->{co2_calibrating}));
            $module->{last_status_store} = FmtDateTime($moduledata->{last_status_store}) if(defined($moduledata->{last_status_store}));
            $module->{helper}{last_status_store} = $moduledata->{last_status_store} if(defined($moduledata->{last_status_store}) && $moduledata->{last_status_store} > $module->{helper}{last_status_store});
            $module->{last_message} = FmtDateTime($moduledata->{last_message}) if(defined($moduledata->{last_message}));
            $module->{last_seen} = FmtDateTime($moduledata->{last_seen}) if(defined($moduledata->{last_seen}));
            $module->{wifi_status} = $moduledata->{wifi_status} if(defined($moduledata->{wifi_status}));
            $module->{rf_status} = $moduledata->{rf_status} if(defined($moduledata->{rf_status}));
            #$module->{battery_percent} = $moduledata->{battery_percent} if(defined($moduledata->{battery_percent}));
            #$module->{battery_vp} = $moduledata->{battery_vp} if(defined($moduledata->{battery_vp}));

            readingsSingleUpdate($module, "batteryState", ($moduledata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($moduledata->{battery_percent}));
            readingsSingleUpdate($module, "batteryPercent", $moduledata->{battery_percent}, 1) if(defined($moduledata->{battery_percent}));
            readingsSingleUpdate($module, "batteryVoltage", $moduledata->{battery_vp}/1000, 1) if(defined($moduledata->{battery_vp}));


          }#foreach module
        }#defined modules
      }#foreach devices

    }#ok
  }#json
  else
  {
    $hash->{status} = "error";
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

return undef;

}


sub
netatmo_parseForecast($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseForecast";

  if( $json )
  {
    Log3 $name, 5, "$name: ".Dumper($json);

    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );

    if( $hash->{status} eq "ok" )
    {
      #$hash->{STATE} = "Connected";
      
      my $datatime = time;
      my $forecasttime = time;
      
      $hash->{stationname} = encode_utf8($json->{body}{stationname}) if(defined($json->{body}{stationname}));
      $hash->{city} = encode_utf8($json->{body}{cityname}) if(defined($json->{body}{cityname}));
      
      if(defined($json->{body}{current_temp_time}))
      {
        $hash->{time_data} = FmtDateTime($json->{body}{current_temp_time});
        $datatime = $json->{body}{current_temp_time};
      } 
      if(defined($json->{body}{time_current_symbol}))
      {
        $hash->{time_forecast} = FmtDateTime($json->{body}{time_current_symbol});
        $forecasttime = $json->{body}{time_current_symbol};
      } 

      return undef if($datatime <= $lastupdate);
      readingsSingleUpdate($hash, ".lastupdate", $datatime, 0);

      if($json->{body}{airqdata})
      {
        if(defined($json->{body}{airqdata}{data}))
        {
          #CommandDeleteReading( undef, "$hash->{NAME} air_.*" );
          foreach my $airdata ( @{$json->{body}{airqdata}{data}})
          {
            my $timestamp = $airdata->{beg_time};
            foreach my $airvalue ( @{$airdata->{value}})
            {
              readingsBeginUpdate($hash);
              $hash->{".updateTimestamp"} = FmtDateTime($timestamp);
              readingsBulkUpdate( $hash, "air_".@{$airvalue}[1], @{$airvalue}[0], 1 );
              $hash->{CHANGETIME}[0] = FmtDateTime($timestamp);
              readingsEndUpdate($hash,1);
              next if(!defined(@{$airvalue}[2]));
              readingsBeginUpdate($hash);
              $hash->{".updateTimestamp"} = FmtDateTime($timestamp);
              readingsBulkUpdate( $hash, "air_".@{$airvalue}[1]."_message", @{$airvalue}[2], 1 );
              $hash->{CHANGETIME}[0] = FmtDateTime($timestamp);
              readingsEndUpdate($hash,1);  
            }
          }
        }
      }#airqdata
      
      if(defined($json->{body}{current_windgust}))
      {
        readingsBeginUpdate($hash);
        $hash->{".updateTimestamp"} = FmtDateTime($datatime);
        readingsBulkUpdate( $hash, "windgust", $json->{body}{current_windgust}, 1 );
        $hash->{CHANGETIME}[0] = FmtDateTime($datatime);
        readingsEndUpdate($hash,1);
      }
      if(defined($json->{body}{current_windstrength}))
      {
        readingsBeginUpdate($hash);
        $hash->{".updateTimestamp"} = FmtDateTime($datatime);
        readingsBulkUpdate( $hash, "windstrength", $json->{body}{current_windstrength}, 1 );
        $hash->{CHANGETIME}[0] = FmtDateTime($datatime);
        readingsEndUpdate($hash,1);
      }
      if(defined($json->{body}{current_temp}))
      {
        readingsBeginUpdate($hash);
        $hash->{".updateTimestamp"} = FmtDateTime($datatime);
        readingsBulkUpdate( $hash, "temperature", $json->{body}{current_temp}, 1 );
        $hash->{CHANGETIME}[0] = FmtDateTime($datatime);
        readingsEndUpdate($hash,1);
      }
      if(defined($json->{body}{current_symbol}))
      {
        readingsBeginUpdate($hash);
        $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
        readingsBulkUpdate( $hash, "symbol", $json->{body}{current_symbol}, 1 );
        $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
        readingsEndUpdate($hash,1);
      }
      
      if(defined($json->{body}{forecastDays}))
      {
        my $i = 0;
        foreach my $forecastdata ( @{$json->{body}{forecastDays}})
        {

          next if(ref($forecastdata) ne "HASH");

          if(defined($forecastdata->{rain}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_rain", $forecastdata->{rain}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{max_temp}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_temp_max", $forecastdata->{max_temp}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{min_temp}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_temp_min", $forecastdata->{min_temp}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{windangle}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_windangle", $forecastdata->{windangle}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{wind_direction}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_wind_direction", $forecastdata->{wind_direction}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{windgust}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_windgust", $forecastdata->{windgust}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{sun}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_sun", $forecastdata->{sun}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{uv}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_uv", $forecastdata->{uv}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{sunset}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_sunset", FmtDateTime($forecastdata->{sunset}), 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{sunrise}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_sunrise", FmtDateTime($forecastdata->{sunrise}), 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{day_locale}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_day", encode_utf8($forecastdata->{day_locale}), 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{weather_symbol_day}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_symbol_day", $forecastdata->{weather_symbol_day}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          if(defined($forecastdata->{weather_symbol_night}))
          {
            readingsBeginUpdate($hash);
            $hash->{".updateTimestamp"} = FmtDateTime($forecasttime);
            readingsBulkUpdate( $hash, "fc".$i."_symbol_night", $forecastdata->{weather_symbol_night}, 1 );
            $hash->{CHANGETIME}[0] = FmtDateTime($forecasttime);
            readingsEndUpdate($hash,1);
          }
          
          $i++;
        }#foreach forecast
      }#defined forecastdays

    }#ok
  }#json
  else
  {
    $hash->{status} = "error";
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

return undef;

}

sub
netatmo_parseHomeReadings($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseHomeReadings";

  if( $json ) {

    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = "ok";
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );
    my @r = ();
    my $readings = \@r;
    $readings = $hash->{readings} if( defined($hash->{readings}) );
    if( $hash->{status} eq "ok" )
    {
      #$hash->{STATE} = "Connected";
      return undef if(!defined($json->{body}{homes}));
      foreach my $homedata ( @{$json->{body}{homes}})
      {
        next if($homedata->{id} ne $hash->{Home});

        readingsSingleUpdate($hash, "name", encode_utf8($homedata->{name}), 1) if(defined($homedata->{name}));

        readingsSingleUpdate($hash, "presence_record_humans", $homedata->{presence_record_humans}, 1) if(defined($homedata->{presence_record_humans}));
        readingsSingleUpdate($hash, "presence_record_vehicles", $homedata->{presence_record_vehicles}, 1) if(defined($homedata->{presence_record_vehicles}));
        readingsSingleUpdate($hash, "presence_record_animals", $homedata->{presence_record_animals}, 1) if(defined($homedata->{presence_record_animals}));
        readingsSingleUpdate($hash, "presence_record_movements", $homedata->{presence_record_movements}, 1) if(defined($homedata->{presence_record_movements}));
        readingsSingleUpdate($hash, "presence_record_alarms", $homedata->{presence_record_alarms}, 1) if(defined($homedata->{presence_record_alarms}));

        readingsSingleUpdate($hash, "gone_after", sprintf("%02d",(int($homedata->{gone_after}/60)/60)).":".sprintf("%02d",(int($homedata->{gone_after}/60)%60)), 1) if(defined($homedata->{gone_after}));
        readingsSingleUpdate($hash, "smart_notifs", ($homedata->{smart_notifs} eq "1")?"on":"off", 1) if(defined($homedata->{smart_notifs}));

        readingsSingleUpdate($hash, "presence_enable_notify_from_to", $homedata->{presence_enable_notify_from_to}, 1) if(defined($homedata->{presence_enable_notify_from_to}));
        readingsSingleUpdate($hash, "presence_notify_from", sprintf("%02d",(int($homedata->{presence_notify_from}/60)/60)).":".sprintf("%02d",(int($homedata->{presence_notify_from}/60)%60)), 1) if(defined($homedata->{presence_notify_from}));
        readingsSingleUpdate($hash, "presence_notify_to", sprintf("%02d",(int($homedata->{presence_notify_to}/60)/60)).":".sprintf("%02d",(int($homedata->{presence_notify_to}/60)%60)), 1) if(defined($homedata->{presence_notify_to}));

        readingsSingleUpdate($hash, "notify_unknowns", $homedata->{notify_unknowns}, 1) if(defined($homedata->{notify_unknowns}));
        readingsSingleUpdate($hash, "notify_movements", $homedata->{notify_movements}, 1) if(defined($homedata->{notify_movements}));
        readingsSingleUpdate($hash, "notify_animals", ($homedata->{notify_animals} eq "1")?"true":"false", 1) if(defined($homedata->{notify_animals}));
        readingsSingleUpdate($hash, "record_animals", ($homedata->{record_animals} eq "1")?"true":"false", 1) if(defined($homedata->{record_animals}));
        readingsSingleUpdate($hash, "record_alarms", $homedata->{record_alarms}, 1) if(defined($homedata->{record_alarms}));
        readingsSingleUpdate($hash, "record_movements", $homedata->{record_movements}, 1) if(defined($homedata->{record_movements}));


        if( $homedata->{place} ) {
          $hash->{country} = encode_utf8($homedata->{place}{country}) if(defined($homedata->{place}{country}));
          $hash->{bssid} = $homedata->{place}{bssid} if(defined($homedata->{place}{bssid}));
          $hash->{altitude} = $homedata->{place}{altitude} if(defined($homedata->{place}{altitude}));
          $hash->{city} = encode_utf8($homedata->{place}{geoip_city}) if(defined($homedata->{place}{geoip_city}));
          $hash->{city} = encode_utf8($homedata->{place}{city}) if(defined($homedata->{place}{city}));;
          $hash->{location} = $homedata->{place}{location}[1] .",". $homedata->{place}{location}[0] if(defined($homedata->{place}{location}));
          $hash->{timezone} = encode_utf8($homedata->{place}{timezone}) if(defined($homedata->{place}{timezone}));
        }

        if(defined($homedata->{persons}))
        {
          foreach my $persondata ( @{$homedata->{persons}})
          {

            my $person = $modules{$hash->{TYPE}}{defptr}{"P$persondata->{id}"};
            next if (!defined($person));

            readingsSingleUpdate($person, "pseudo", encode_utf8($persondata->{pseudo}), 1) if(defined($persondata->{pseudo}));
            readingsSingleUpdate($person, "last_seen", FmtDateTime($persondata->{last_seen}), 1) if(defined($persondata->{last_seen}));
            readingsSingleUpdate($person, "out_of_sight", $persondata->{out_of_sight}, 1) if(defined($persondata->{out_of_sight}));
            readingsSingleUpdate($person, "status", (($persondata->{out_of_sight} eq "0") ? "home" : "away"), 1) if(defined($persondata->{out_of_sight}));
            #$person->{STATE} = ($persondata->{out_of_sight} eq "0") ? "home" : "away";
            readingsSingleUpdate($person, "face_id", $persondata->{face}{id}, 0) if(defined($persondata->{face}{id}));
            readingsSingleUpdate($person, "face_key", $persondata->{face}{key}, 0) if(defined($persondata->{face}{key}));
            readingsSingleUpdate($person, "face_version", $persondata->{face}{version}, 1) if(defined($persondata->{face}{version}));

          }
        }

        if(defined($homedata->{cameras}))
        {
          foreach my $cameradata ( @{$homedata->{cameras}})
          {

            my $camera = $modules{$hash->{TYPE}}{defptr}{"C$cameradata->{id}"};
            next if (!defined($camera));

            readingsSingleUpdate($camera, "name", encode_utf8($cameradata->{name}), 1) if(defined($cameradata->{name}));
            readingsSingleUpdate($camera, "status", $cameradata->{status}, 1) if(defined($cameradata->{status}));
            #$camera->{STATE} = ($cameradata->{status} eq "on") ? "online" : "offline";
            readingsSingleUpdate($camera, "sd_status", $cameradata->{sd_status}, 0) if(defined($cameradata->{sd_status}));
            readingsSingleUpdate($camera, "alim_status", $cameradata->{alim_status}, 0) if(defined($cameradata->{alim_status}));
            readingsSingleUpdate($camera, "is_local", $cameradata->{is_local}, 1) if(defined($cameradata->{is_local}));
            readingsSingleUpdate($camera, "vpn_url", $cameradata->{vpn_url}, 1) if(defined($cameradata->{vpn_url}));
            CommandDeleteReading( undef, "$camera->{NAME} vpn_url" ) if(!defined($cameradata->{vpn_url}));
            CommandDeleteReading( undef, "$camera->{NAME} local_url" ) if(!defined($cameradata->{vpn_url}));

            readingsSingleUpdate($camera, "light_mode", $cameradata->{light_mode_status}, 1) if(defined($cameradata->{light_mode_status}));
            readingsSingleUpdate($camera, "timelapse_available", $cameradata->{timelapse_available}, 0) if(defined($cameradata->{timelapse_available}));
            delete($camera->{pin}) if($cameradata->{status} eq "on");
            
            $camera->{model} = $cameradata->{type} if(defined($cameradata->{type}));
            $camera->{firmware} = $cameradata->{firmware} if(defined($cameradata->{firmware}));

            
            foreach my $tagdata ( @{$cameradata->{modules}})
            {
              my $tag = $modules{$hash->{TYPE}}{defptr}{"G$tagdata->{id}"};
              next if (!defined($tag));

              readingsSingleUpdate($tag, "name", encode_utf8($tagdata->{name}), 1) if(defined($tagdata->{name}));
              readingsSingleUpdate($tag, "status", $tagdata->{status}, 1) if(defined($tagdata->{status}));
              readingsSingleUpdate($tag, "category", $tagdata->{category}, 1) if(defined($tagdata->{category}));

              $tag->{model} = $tagdata->{type};
              $tag->{last_activity} = FmtDateTime($tagdata->{last_activity}) if(defined($tagdata->{last_activity}));
              $tag->{last_seen} = FmtDateTime($tagdata->{last_seen}) if(defined($tagdata->{last_seen}));
              $tag->{rf} = $tagdata->{rf};
              $tag->{notify_rule} = $tagdata->{notify_rule};
              $tag->{notify_rule} = $tagdata->{notify_rule};

              readingsSingleUpdate($tag, "batteryState", ($tagdata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($tagdata->{battery_percent}));
              readingsSingleUpdate($tag, "batteryPercent", $tagdata->{battery_percent}, 1) if(defined($tagdata->{battery_percent}));
              readingsSingleUpdate($tag, "batteryVoltage", $tagdata->{battery_vp}/1000, 1) if(defined($tagdata->{battery_vp}));

            }            
            
          }
        }

        if(defined($homedata->{events}))
        {
          my @eventslist = @{$homedata->{events}};
          my $eventdata;
          while ($eventdata = pop( @eventslist ))
          {



            $eventdata->{time} = time() if(!defined($eventdata->{time}));
            next if($eventdata->{time} <= $lastupdate);
            readingsSingleUpdate($hash, ".lastupdate", $eventdata->{time}, 0);

            Log3 $name, 4, "$name: new event: ".FmtDateTime($eventdata->{time});

            if(defined($eventdata->{event_list}))
            {
              my @singleeventslist = @{$eventdata->{event_list}};
              my $singleeventdata;
              while ($singleeventdata = pop( @singleeventslist ))
                {
                  if(defined($singleeventdata->{message}))
                  {
                    my $eventmessage = $singleeventdata->{message};
                    $eventmessage = "-" if(!defined($singleeventdata->{message}));
                    $eventmessage =~ s/<\/b>//g;
                    $eventmessage =~ s/<b>//g;
                    readingsBeginUpdate($hash);
                    $hash->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                    readingsBulkUpdate( $hash, "event", encode_utf8($eventmessage), 1 );
                    $hash->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                    readingsEndUpdate($hash,1);
                  }

                  if(defined($singleeventdata->{snapshot}{key}))
                  {
                    readingsBeginUpdate($hash);
                    $hash->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                    readingsBulkUpdate( $hash, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$singleeventdata->{snapshot}{id}."&key=".$singleeventdata->{snapshot}{key}, 1 );
                    $hash->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                    readingsEndUpdate($hash,1);
                  }

                }
            }
            else
            {
            my $eventmessage = $eventdata->{message};
              $eventmessage = "-" if(!defined($eventdata->{message}));
              $eventmessage =~ s/<\/b>//g;
              $eventmessage =~ s/<b>//g;


              if(defined($eventdata->{message}))
              {
                readingsBeginUpdate($hash);
                $hash->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $hash, "event", encode_utf8($eventmessage), 1 );
                $hash->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($hash,1);
              }

              if(defined($eventdata->{snapshot}))
              {
                readingsBeginUpdate($hash);
                $hash->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $hash, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$eventdata->{snapshot}{id}."&key=".$eventdata->{snapshot}{key}, 1 );
                $hash->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($hash,1);
              }
            }
            my $camera = $modules{$hash->{TYPE}}{defptr}{"C$eventdata->{camera_id}"};
            my $tag = $modules{$hash->{TYPE}}{defptr}{"G$eventdata->{module_id}"} if(defined($eventdata->{module_id}));
            my $person = $modules{$hash->{TYPE}}{defptr}{"P$eventdata->{person_id}"} if(defined($eventdata->{person_id}));
            if (defined($camera))
            {

              my $lastupdate = ReadingsVal( $camera->{NAME}, ".lastupdate", 0 );
              next if($eventdata->{time} <= $lastupdate);
              readingsSingleUpdate($camera, ".lastupdate", $eventdata->{time}, 0);

              if(defined($eventdata->{event_list}))
              {
                my @singleeventslist = @{$eventdata->{event_list}};
                my $singleeventdata;
                while ($singleeventdata = pop( @singleeventslist ))
                {
                    if(defined($singleeventdata->{message}))
                    {
                      my $cameraname = ReadingsVal( $camera->{NAME}, "name", "Welcome" );
                      my $eventmessage = $singleeventdata->{message};
                      $eventmessage =~ s/<b>//g;
                      $eventmessage =~ s/<\/b>//g;
                      $eventmessage =~ s/$cameraname: //g;
                      $eventmessage =~ s/$cameraname /Camera /g;
                      readingsBeginUpdate($camera);
                      $camera->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                      readingsBulkUpdate( $camera, "event", encode_utf8($eventmessage), 1 );
                      $camera->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                      readingsEndUpdate($camera,1);
                    }
                    if(defined($singleeventdata->{time}))
                    {
                      readingsBeginUpdate($camera);
                      $camera->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                      readingsBulkUpdate( $camera, "event_time", FmtDateTime($singleeventdata->{time}), 1 );
                      $camera->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                      readingsEndUpdate($camera,1);
                    }
                    if(defined($singleeventdata->{type}))
                    {
                      readingsBeginUpdate($camera);
                      $camera->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                      readingsBulkUpdate( $camera, "event_type", $singleeventdata->{type}, 1 );
                      $camera->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                      readingsEndUpdate($camera,1);
                    }
                    if(defined($singleeventdata->{id}))
                    {
                      readingsBeginUpdate($camera);
                      $camera->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                      readingsBulkUpdate( $camera, "event_id", $singleeventdata->{id}, 1 );
                      $camera->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                      readingsEndUpdate($camera,1);
                    }

                    if(defined($singleeventdata->{snapshot}{filename}))
                    {
                      readingsBeginUpdate($camera);
                      $camera->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                      readingsBulkUpdate( $camera, "filename", $singleeventdata->{snapshot}{filename}, 1 );
                      $camera->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                      readingsEndUpdate($camera,1);
                    }
                    
                    if(defined($singleeventdata->{snapshot}{key}))
                    {
                      readingsBeginUpdate($camera);
                      $camera->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                      readingsBulkUpdate( $camera, "snapshot", $singleeventdata->{snapshot}{id}."|".$singleeventdata->{snapshot}{key}, 1 );
                      $camera->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                      readingsEndUpdate($camera,1);
                    }
                    if(defined($singleeventdata->{snapshot}{key}))
                    {
                      readingsBeginUpdate($camera);
                      $camera->{".updateTimestamp"} = FmtDateTime($singleeventdata->{time});
                      readingsBulkUpdate( $camera, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$singleeventdata->{snapshot}{id}."&key=".$singleeventdata->{snapshot}{key}, 1 );
                      $camera->{CHANGETIME}[0] = FmtDateTime($singleeventdata->{time});
                      readingsEndUpdate($camera,1);
                    }

                  }
              }
              else
              {
              if(defined($eventdata->{message}))
              {
                my $cameraname = ReadingsVal( $camera->{NAME}, "name", "Welcome" );
                  my $eventmessage = $eventdata->{message};
                  $eventmessage =~ s/<b>//g;
                  $eventmessage =~ s/<\/b>//g;
                $eventmessage =~ s/$cameraname: //g;
                $eventmessage =~ s/$cameraname /Camera /g;
                readingsBeginUpdate($camera);
                $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $camera, "event", encode_utf8($eventmessage), 1 );
                $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($camera,1);
              }

                if(defined($eventdata->{time}))
                {
                  readingsBeginUpdate($camera);
                  $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $camera, "event_time", FmtDateTime($eventdata->{time}), 1 );
                  $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($camera,1);
                }

                if(defined($eventdata->{type}))
                {
                  readingsBeginUpdate($camera);
                  $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $camera, "event_type", $eventdata->{type}, 1 );
                  $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($camera,1);
                }

                if(defined($eventdata->{id}))
                {
                  readingsBeginUpdate($camera);
                  $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $camera, "event_id", $eventdata->{id}, 1 );
                  $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($camera,1);
                }

                if(defined($person))
                {
                  readingsBeginUpdate($camera);
                  $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $camera, "person_seen", ReadingsVal($person->{NAME},"pseudo","Unknown"), 1 );
                  $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($camera,1);
                }

                if(defined($eventdata->{snapshot}))
                {
                  readingsBeginUpdate($camera);
                  $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $camera, "snapshot", $eventdata->{snapshot}{id}."|".$eventdata->{snapshot}{key}, 1 );
                  $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($camera,1);
                }


                if(defined($eventdata->{snapshot}))
                {
                  readingsBeginUpdate($camera);
                  $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $camera, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$eventdata->{snapshot}{id}."&key=".$eventdata->{snapshot}{key}, 1 );
                  $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($camera,1);
                }
              }
              
              if(defined($eventdata->{video_status}))
              {
                readingsBeginUpdate($camera);
                $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $camera, "video_status", $eventdata->{video_status}, 1 );
                $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($camera,1);
              }

              if(defined($eventdata->{video_id}))
              {
                readingsBeginUpdate($camera);
                $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $camera, "video_id", $eventdata->{video_id}, 1 );
                $camera->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($camera,1);
              }

            }

            if (defined($tag))
            {

              my $lastupdate = ReadingsVal( $tag->{NAME}, ".lastupdate", 0 );
              next if($eventdata->{time} <= $lastupdate);
              readingsSingleUpdate($tag, ".lastupdate", $eventdata->{time}, 0);

              if(defined($eventdata->{message}))
              {
                my $tagname = ReadingsVal( $tag->{NAME}, "name", "Tag" );
                my $eventmessage = $eventdata->{message};
                $eventmessage =~ s/<b>//g;
                $eventmessage =~ s/<\/b>//g;
                $eventmessage =~ s/ by $tagname//g;
                $eventmessage =~ s/$tagname /Tag /g;
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "event", encode_utf8($eventmessage), 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }

              if(defined($eventdata->{time}))
              {
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "event_time", FmtDateTime($eventdata->{time}), 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }

              if(defined($eventdata->{type}))
              {
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "event_type", $eventdata->{type}, 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }

              if(defined($eventdata->{id}))
              {
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "event_id", $eventdata->{id}, 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }

              if(defined($eventdata->{snapshot}))
              {
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "snapshot", $eventdata->{snapshot}{id}."|".$eventdata->{snapshot}{key}, 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }

              if(defined($eventdata->{video_status}))
              {
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "video_status", $eventdata->{video_status}, 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }

              if(defined($eventdata->{video_id}))
              {
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "video_id", $eventdata->{video_id}, 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }

              if(defined($eventdata->{snapshot}))
              {
                readingsBeginUpdate($tag);
                $tag->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $tag, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$eventdata->{snapshot}{id}."&key=".$eventdata->{snapshot}{key}, 1 );
                $tag->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($tag,1);
              }
            }

            if (defined($person))
            {
              my $lastupdate = ReadingsVal( $person->{NAME}, ".lastupdate", 0 );
              next if($eventdata->{time} <= $lastupdate);
              readingsSingleUpdate($person, ".lastupdate", $eventdata->{time}, 0);

              readingsSingleUpdate($person, "last_seen", FmtDateTime($eventdata->{time}), 1) if(defined($eventdata->{time}));
              readingsSingleUpdate($person, "last_arrival", FmtDateTime($eventdata->{time}), 1) if(defined($eventdata->{time}) && defined($eventdata->{is_arrival}) && $eventdata->{is_arrival} eq "1");

              if(defined($camera))
              {
                readingsBeginUpdate($person);
                $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $person, "camera", ReadingsVal($camera->{NAME},"name","Unknown"), 1 );
                $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($person,1);
              }

              if(defined($eventdata->{id}))
              {
                readingsBeginUpdate($person);
                $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $person, "event_id", $eventdata->{id}, 1 );
                $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($person,1);
              }

              if(defined($eventdata->{video_status}))
              {
                readingsBeginUpdate($person);
                $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $person, "video_status", $eventdata->{video_status}, 1 );
                $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($person,1);
              }

              if(defined($eventdata->{video_id}))
              {
                readingsBeginUpdate($person);
                $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $person, "video_id", $eventdata->{video_id}, 1 );
                $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($person,1);
              }

              if(defined($eventdata->{snapshot}))
              {
                readingsBeginUpdate($person);
                $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $person, "snapshot", $eventdata->{snapshot}{id}."|".$eventdata->{snapshot}{key}, 1 );
                $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($person,1);
              }

              if(defined($eventdata->{snapshot}))
              {
                readingsBeginUpdate($person);
                $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $person, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$eventdata->{snapshot}{id}."&key=".$eventdata->{snapshot}{key}, 1 );
                $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                readingsEndUpdate($person,1);
              }
            }

          }
        }


        my $time = $homedata->{time_server};


      }


    }
  }
  else
  {
    $hash->{status} = "error";
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");


}


sub 
netatmo_refreshHomeSettings($)
{
  my($hash) = @_;
  my $name = $hash->{NAME};
  
  InternalTimer(gettimeofday()+5, "netatmo_poll", $hash);
  
  return undef;
}


sub
netatmo_parseCameraPing($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseCameraPing";

  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );

    readingsSingleUpdate($hash, "local_url", $json->{local_url}, 1) if(defined($json->{local_url}));
    CommandDeleteReading( undef, "$hash->{NAME} local_url" ) if(!defined($json->{local_url}));

  }
  else
  {
    $hash->{status} = "error";
    if(ReadingsVal( $name, "status", "ok" ) eq "disconnected"){
      $hash->{status} = "disconnected";
      RemoveInternalTimer($hash);
  }
}
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if(defined($hash->{status}) && $hash->{status} ne "no data");

}

sub
netatmo_parseCameraStatus($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseCameraStatus";
  my $home = $modules{$hash->{TYPE}}{defptr}{"H$hash->{Home}"};

  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = "ok";
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    InternalTimer( gettimeofday() + 10, "netatmo_pollHome", $home) if($hash->{status} eq "ok" );
  }
  else{
    netatmo_pollHome($home) if($home->{status} !~ /usage/ &&  $home->{status} !~ /too_many_connections/ && $home->{status} !~ /postponed/);
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

}

sub
netatmo_parseCameraConfig($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseCameraConfig";
  my $home = $modules{$hash->{TYPE}}{defptr}{"H$hash->{Home}"};

  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = "ok";
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    return undef if($hash->{status} ne "ok");
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "intensity", $json->{intensity}, 1 ) if( $json->{intensity} );
    readingsBulkUpdate( $hash, "light_mode", $json->{mode}, 1 ) if( $json->{mode} );
    readingsBulkUpdate( $hash, "night_always", ($json->{night}{always}?"true":"false"), 1 ) if( $json->{night} );
    readingsBulkUpdate( $hash, "night_person", ($json->{night}{person}?"true":"false"), 1 ) if( $json->{night} );
    readingsBulkUpdate( $hash, "night_vehicle", ($json->{night}{vehicle}?"true":"false"), 1 ) if( $json->{night} );
    readingsBulkUpdate( $hash, "night_animal", ($json->{night}{animal}?"true":"false"), 1 ) if( $json->{night} );
    readingsBulkUpdate( $hash, "night_movement", ($json->{night}{movement}?"true":"false"), 1 ) if( $json->{night} );
    readingsEndUpdate( $hash, 1);

    InternalTimer( gettimeofday() + 10, "netatmo_pollHome", $home) if($hash->{status} eq "ok" );
  }
  else{
    netatmo_pollHome($home) if($home->{status} !~ /usage/  && $home->{status} !~ /too_many_connections/ && $home->{status} !~ /postponed/);
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

}


sub
netatmo_parseTagStatus($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseTagStatus";

  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    readingsSingleUpdate($hash, "status", "calibrating", 1) if($hash->{status} eq "ok");
  }
  else
  {
    $hash->{status} = "error";
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

}


sub
netatmo_parseCameraVideo($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseCameraVideo";

  if( $json ) {

    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    return undef if($hash->{status} ne "ok");

    return undef if($hash->{status} ne "ok");
    
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );

    readingsSingleUpdate($hash, "local_url", $json->{local_url}, 1) if(defined($json->{local_url}));

  }
  else
  {
    $hash->{status} = "error";
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

}

sub
netatmo_parsePersonReadings($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};



    Log3 $name, 4, "$name: parsePersonReadings";

    if( $json ) {
      Log3 $name, 5, "$name: ".Dumper($json);

      $hash->{status} = $json->{status};
      $hash->{status} = $json->{error}{message} if( $json->{error} );
      
      my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );

      if( $hash->{status} eq "ok" )
      {
        #$hash->{STATE} = "Connected";

          if(defined($json->{body}{events_list}))
          {
            my @eventslist = @{$json->{body}{events_list}};
            my $eventdata;
            while ($eventdata = pop( @eventslist ))
            {

              next if(!defined($eventdata->{person_id}));
              next if($eventdata->{time} <= $lastupdate);
              next if($eventdata->{person_id} ne $hash->{Person});


              $eventdata->{time} = time() if(!defined($eventdata->{time}));
              readingsSingleUpdate($hash, ".lastupdate", $eventdata->{time}, 0);

              Log3 $name, 4, "$name: new event: ".FmtDateTime($eventdata->{time});


              my $camera = $modules{$hash->{TYPE}}{defptr}{"C$eventdata->{camera_id}"};
              my $person = $modules{$hash->{TYPE}}{defptr}{"P$eventdata->{person_id}"} if(defined($eventdata->{person_id}));

              if (defined($person))
              {
                readingsSingleUpdate($person, "last_seen", FmtDateTime($eventdata->{time}), 1) if(defined($eventdata->{time}));
                readingsSingleUpdate($person, "last_arrival", FmtDateTime($eventdata->{time}), 1) if(defined($eventdata->{time}) && defined($eventdata->{is_arrival}) && $eventdata->{is_arrival} eq "1");

                if(defined($camera))
                {
                  readingsBeginUpdate($person);
                  $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $person, "camera", ReadingsVal($camera->{NAME},"name","Unknown"), 1 );
                  $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($person,1);
                }

                if(defined($eventdata->{id}))
                {
                  readingsBeginUpdate($person);
                  $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $person, "event_id", $eventdata->{id}, 1 );
                  $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($person,1);
                }

                if(defined($eventdata->{video_status}))
                {
                  readingsBeginUpdate($person);
                  $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $person, "video_status", $eventdata->{video_status}, 1 );
                  $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($person,1);
                }

                if(defined($eventdata->{video_id}))
                {
                  readingsBeginUpdate($person);
                  $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $person, "video_id", $eventdata->{video_id}, 1 );
                  $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($person,1);
                }

                if(defined($eventdata->{snapshot}))
                {
                  readingsBeginUpdate($person);
                  $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $person, "snapshot", $eventdata->{snapshot}{id}."|".$eventdata->{snapshot}{key}, 1 );
                  $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($person,1);
                }

                if(defined($eventdata->{snapshot}))
                {
                  readingsBeginUpdate($person);
                  $person->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                  readingsBulkUpdate( $person, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$eventdata->{snapshot}{id}."&key=".$eventdata->{snapshot}{key}, 1 );
                  $person->{CHANGETIME}[0] = FmtDateTime($eventdata->{time});
                  readingsEndUpdate($person,1);
                }
              }

            }
          }


      }
    }
    else
    {
      $hash->{status} = "error";
    }
    readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");


}


sub
netatmo_parseThermostatReadings($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseThermostatReadings";

  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );
    my @r = ();
    my $readings = \@r;
    $readings = $hash->{readings} if( defined($hash->{readings}) );
    if( $hash->{status} eq "ok" )
    {

      foreach my $devicedata ( @{$json->{body}{devices}})
      {
        my $hash = $modules{$hash->{TYPE}}{defptr}{"R$devicedata->{_id}"};
        next if (!defined($hash));
        next if($devicedata->{_id} ne $hash->{Relay});
        #$hash->{STATE} = "Connected";

        readingsSingleUpdate($hash, "name", encode_utf8($devicedata->{station_name}), 1) if(defined($devicedata->{station_name}));

        $hash->{stationName} = encode_utf8($devicedata->{station_name}) if( $devicedata->{station_name} );
        $hash->{moduleName} = encode_utf8($devicedata->{module_name}) if( $devicedata->{module_name} );

        $hash->{model} = $devicedata->{type} if(defined($devicedata->{type}));
        $hash->{firmware} = $devicedata->{firmware} if(defined($devicedata->{firmware}));

        $hash->{last_upgrade} = FmtDateTime($devicedata->{last_upgrade}) if(defined($devicedata->{last_upgrade}));
        $hash->{date_setup} = FmtDateTime($devicedata->{date_setup}) if(defined($devicedata->{date_setup}));
        $hash->{last_setup} = FmtDateTime($devicedata->{last_setup}) if(defined($devicedata->{last_setup}));
        $hash->{last_status_store} = FmtDateTime($devicedata->{last_status_store}) if(defined($devicedata->{last_status_store}));
        $hash->{helper}{last_status_store} = $devicedata->{last_status_store} if(defined($devicedata->{last_status_store}) && $devicedata->{last_status_store} > $hash->{helper}{last_status_store});
        $hash->{last_message} = FmtDateTime($devicedata->{last_message}) if(defined($devicedata->{last_message}));
        $hash->{last_seen} = FmtDateTime($devicedata->{last_seen}) if(defined($devicedata->{last_seen}));
        $hash->{last_plug_seen} = FmtDateTime($devicedata->{last_plug_seen}) if(defined($devicedata->{last_plug_seen}));
        $hash->{last_therm_seen} = FmtDateTime($devicedata->{last_therm_seen}) if(defined($devicedata->{last_therm_seen}));
        $hash->{wifi_status} = $devicedata->{wifi_status} if(defined($devicedata->{wifi_status}));
        $hash->{rf_status} = $devicedata->{rf_status} if(defined($devicedata->{rf_status}));
        #$hash->{battery_percent} = $devicedata->{battery_percent} if(defined($devicedata->{battery_percent}));
        #$hash->{battery_vp} = $devicedata->{battery_vp} if(defined($devicedata->{battery_vp}));
        $hash->{therm_orientation} = $devicedata->{therm_orientation} if(defined($devicedata->{therm_orientation}));
        $hash->{therm_relay_cmd} = $devicedata->{therm_relay_cmd} if(defined($devicedata->{therm_relay_cmd}));
        $hash->{udp_conn} = $devicedata->{udp_conn} if(defined($devicedata->{udp_conn}));
        $hash->{plug_connected_boiler} = $devicedata->{plug_connected_boiler} if(defined($devicedata->{plug_connected_boiler}));
        $hash->{syncing} = $devicedata->{syncing} if(defined($devicedata->{syncing}));

        $hash->{room} = $devicedata->{room} if(defined($devicedata->{room}));

        if( $devicedata->{place} ) {
          $hash->{country} = encode_utf8($devicedata->{place}{country});
          $hash->{bssid} = $devicedata->{place}{bssid} if(defined($devicedata->{place}{bssid}));
          $hash->{altitude} = $devicedata->{place}{altitude} if(defined($devicedata->{place}{altitude}));
          $hash->{city} = encode_utf8($devicedata->{place}{geoip_city}) if(defined($devicedata->{place}{geoip_city}));
          $hash->{city} = encode_utf8($devicedata->{place}{city}) if(defined($devicedata->{place}{city}));;
          $hash->{location} = $devicedata->{place}{location}[1] .",". $devicedata->{place}{location}[0];
          $hash->{timezone} = encode_utf8($devicedata->{place}{timezone});
        }

        readingsSingleUpdate($hash, "batteryState", ($devicedata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($devicedata->{battery_percent}));
        readingsSingleUpdate($hash, "batteryPercent", $devicedata->{battery_percent}, 1) if(defined($devicedata->{battery_percent}));
        readingsSingleUpdate($hash, "batteryVoltage", $devicedata->{battery_vp}/1000, 1) if(defined($devicedata->{battery_vp}));


        if(defined($devicedata->{modules}))
        {
          foreach my $moduledata ( @{$devicedata->{modules}})
          {
            my $module = $modules{$hash->{TYPE}}{defptr}{"T$moduledata->{_id}"};
            next if (!defined($module));

            $module->{stationName} = encode_utf8($moduledata->{station_name}) if( $moduledata->{station_name} );
            $module->{moduleName} = encode_utf8($moduledata->{module_name}) if( $moduledata->{module_name} );

            $module->{model} = $moduledata->{type} if(defined($moduledata->{type}));
            $module->{firmware} = $moduledata->{firmware} if(defined($moduledata->{firmware}));

            $module->{last_upgrade} = FmtDateTime($moduledata->{last_upgrade}) if(defined($moduledata->{last_upgrade}));
            $module->{date_setup} = FmtDateTime($moduledata->{date_setup}) if(defined($moduledata->{date_setup}));
            $module->{last_setup} = FmtDateTime($moduledata->{last_setup}) if(defined($moduledata->{last_setup}));
            $module->{last_status_store} = FmtDateTime($moduledata->{last_status_store}) if(defined($moduledata->{last_status_store}));
            $module->{helper}{last_status_store} = $moduledata->{last_status_store} if(defined($moduledata->{last_status_store}) && $moduledata->{last_status_store} > $module->{helper}{last_status_store});
            $module->{last_message} = FmtDateTime($moduledata->{last_message}) if(defined($moduledata->{last_message}));
            $module->{last_seen} = FmtDateTime($moduledata->{last_seen}) if(defined($moduledata->{last_seen}));
            $module->{last_plug_seen} = FmtDateTime($moduledata->{last_plug_seen}) if(defined($moduledata->{last_plug_seen}));
            $module->{last_therm_seen} = FmtDateTime($moduledata->{last_therm_seen}) if(defined($moduledata->{last_therm_seen}));
            $module->{wifi_status} = $moduledata->{wifi_status} if(defined($moduledata->{wifi_status}));
            $module->{rf_status} = $moduledata->{rf_status} if(defined($moduledata->{rf_status}));
            #$module->{battery_percent} = $moduledata->{battery_percent} if(defined($moduledata->{battery_percent}));
            #$module->{battery_vp} = $moduledata->{battery_vp} if(defined($moduledata->{battery_vp}));
            $module->{therm_orientation} = $moduledata->{therm_orientation} if(defined($moduledata->{therm_orientation}));
            #$module->{therm_relay_cmd} = $moduledata->{therm_relay_cmd} if(defined($moduledata->{therm_relay_cmd}));
            $module->{udp_conn} = $moduledata->{udp_conn} if(defined($moduledata->{udp_conn}));
            $module->{plug_connected_boiler} = $moduledata->{plug_connected_boiler} if(defined($moduledata->{plug_connected_boiler}));
            $module->{syncing} = $moduledata->{syncing} if(defined($moduledata->{syncing}));

            $module->{room} = $moduledata->{room} if(defined($moduledata->{room}));

            if( $moduledata->{place} ) {
              $module->{country} = $moduledata->{place}{country};
              $module->{bssid} = $moduledata->{place}{bssid} if(defined($moduledata->{place}{bssid}));
              $module->{altitude} = $moduledata->{place}{altitude} if(defined($moduledata->{place}{altitude}));
              $module->{city} = encode_utf8($moduledata->{place}{geoip_city}) if(defined($moduledata->{place}{geoip_city}));
              $module->{city} = encode_utf8($moduledata->{place}{city}) if(defined($moduledata->{place}{city}));;
              $module->{location} = $moduledata->{place}{location}[1] .",". $moduledata->{place}{location}[0];
              $module->{timezone} = encode_utf8($moduledata->{place}{timezone});
            }

            readingsSingleUpdate($module, "batteryState", ($moduledata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($moduledata->{battery_percent}));
            readingsSingleUpdate($module, "batteryPercent", $moduledata->{battery_percent}, 1) if(defined($moduledata->{battery_percent}));
            readingsSingleUpdate($module, "batteryVoltage", $moduledata->{battery_vp}/1000, 1) if(defined($moduledata->{battery_vp}));
            #readingsSingleUpdate($module, "name", encode_utf8($moduledata->{module_name}), 1) if(defined($moduledata->{module_name}));

            my $setmode = "manual";

            if(defined($moduledata->{setpoint}))
            {
              readingsSingleUpdate($module, "setpoint_mode", $moduledata->{setpoint}{setpoint_mode}, 1) if(defined($moduledata->{setpoint}{setpoint_mode}));
              readingsSingleUpdate($module, "setpoint_endtime", FmtDateTime($moduledata->{setpoint}{setpoint_endtime}), 1) if(defined($moduledata->{setpoint}{setpoint_endtime}));
              CommandDeleteReading( undef, "$module->{NAME} setpoint_endtime" ) if(!defined($moduledata->{setpoint}{setpoint_endtime}));
              $setmode = $moduledata->{setpoint}{setpoint_mode} if(defined($moduledata->{setpoint}{setpoint_mode}));
            }
            readingsSingleUpdate($module, "therm_relay_cmd", $moduledata->{therm_relay_cmd}, 1) if(defined($moduledata->{therm_relay_cmd}));


            if(defined($moduledata->{measured}{setpoint_temp}))
            {
              readingsBeginUpdate($module);
              $module->{".updateTimestamp"} = FmtDateTime($moduledata->{measured}{time});
              readingsBulkUpdate( $module, "setpoint_temp", sprintf( "%.1f", $moduledata->{measured}{setpoint_temp}), 1 );
              $module->{CHANGETIME}[0] = FmtDateTime($moduledata->{measured}{time});
              readingsEndUpdate($module,1);
              $setmode = sprintf( "%.1f", $moduledata->{measured}{setpoint_temp}) if($setmode ne "max" && $setmode ne "off");
            }

            readingsSingleUpdate($module, "setpoint", $setmode, 1);


            my @s = ();
            my $schedules = \@s;
            my @schedulelist;
            foreach my $scheduledata ( @{$moduledata->{therm_program_list}})
            {
              my $program = encode_utf8($scheduledata->{name});
              $program =~ s/ /_/g;
              push(@{$schedules}, [$program, $scheduledata->{program_id}]);
              push(@schedulelist, $program);

              if(defined($scheduledata->{selected}))
              {
                readingsSingleUpdate($module, "program", $program, 1);
              }
            }
            $module->{schedules} = $schedules;
            $module->{schedulenames} = join(',', @schedulelist);

          }
        }


        #my $time = $devicedata->{time_server};

      }


    }
  }
  else
  {
    $hash->{status} = "error";
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");


}

sub
netatmo_parseThermostatStatus($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseThermostatStatus";
  my $thermostat = $modules{$hash->{TYPE}}{defptr}{"T$hash->{Thermostat}"};

  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    InternalTimer( gettimeofday() + 10, "netatmo_pollRelay", $thermostat) if($hash->{status} eq "ok");
  } else {
    netatmo_pollRelay($thermostat) if($thermostat->{status} !~ /usage/ && $thermostat->{status} !~ /too_many_connections/ && $thermostat->{status} !~ /postponed/);;
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

}

sub 
netatmo_parseHeatingHomeStatus($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseHeatingHomeStatus";
  my $thermostat = $modules{$hash->{TYPE}}{defptr}{"E$hash->{Home}"};

  Log3 $name, 5, "$name: parseHeatingHomeStatus ".Dumper($json);

  return undef;
}

sub
netatmo_parsePublic($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: parsepublic ".Dumper($json);

  if( $json ) {
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    if( $hash->{status} eq "ok" ) {
      if( $hash->{Lat} && $hash->{Lon} )
      {
        my $found = 0;
        my @readings = ();
        my @readings_temperature = ();
        my @readings_humidity = ();
        my @readings_pressure = ();
        my @readings_rain = ();
        my @readings_rain_1 = ();
        my @readings_rain_24 = ();
        my @readings_wind_angle = ();
        my @readings_wind_strength = ();
        my @readings_gust_angle = ();
        my @readings_gust_strength = ();
        my @timestamps_temperature = ();
        my @timestamps_pressure = ();
        my @timestamps_rain = ();
        my @timestamps_wind = ();
        my @readings_altitude = ();
        my @readings_latitude = ();
        my @readings_longitude = ();
        my $devices = $json->{body};
        if( ref($devices) eq "ARRAY" ) {
          foreach my $device (@{$devices}) {
            $found++;
            #next if( $device->{_id} ne $hash->{Device} );
            next if( ref($device->{measures}) ne "HASH" );

            if(defined($device->{place}))
            {
              push(@readings_altitude, $device->{place}{altitude}) if(defined($device->{place}{altitude}));
              push(@readings_latitude, $device->{place}{location}[1]) if(defined($device->{place}{location}));
              push(@readings_longitude, $device->{place}{location}[0]) if(defined($device->{place}{location}));
            }

            foreach my $module ( keys %{$device->{measures}}) {
              #next if( ref($device->{measures}->{$module}->{res}) ne "HASH" );

              if(defined($device->{measures}->{$module}->{rain_live}))
              {
                push(@readings_rain, $device->{measures}->{$module}->{rain_live});
                push(@readings_rain_1, $device->{measures}->{$module}->{rain_60min});
                push(@readings_rain_24, $device->{measures}->{$module}->{rain_24h});
                push(@timestamps_rain, $device->{measures}->{$module}->{rain_timeutc});
                next;
              }
              if(defined($device->{measures}->{$module}->{wind_strength}))
              {
                push(@readings_wind_angle, $device->{measures}->{$module}->{wind_angle});
                push(@readings_wind_strength, $device->{measures}->{$module}->{wind_strength});
                push(@readings_gust_angle, $device->{measures}->{$module}->{gust_angle});
                push(@readings_gust_strength, $device->{measures}->{$module}->{gust_strength});
                push(@timestamps_wind, $device->{measures}->{$module}->{wind_timeutc});
                next;
              }
              foreach my $timestamp ( keys %{$device->{measures}->{$module}->{res}} ) {
                #next if( $hash->{LAST_POLL} && $timestamp <= $hash->{LAST_POLL} );
                my $i = 0;
                foreach my $value ( @{$device->{measures}->{$module}->{res}->{$timestamp}} ) {
                  my $type = $device->{measures}->{$module}->{type}[$i];
                  ++$i;
                  if(lc($type) eq "pressure")
                  {
                    push(@timestamps_pressure, $timestamp);
                    push(@readings_pressure, $value);
                    next;
                  }
                  else
                  {
                    push(@timestamps_temperature, $timestamp) if(lc($type) eq "temperature");
                    push(@readings_temperature, $value) if(lc($type) eq "temperature");
                    push(@readings_humidity, $value) if(lc($type) eq "humidity");
                    next;
                  }

                }
              }
            }

            #$found = 1;
            #last;
          }
        }

        @readings_temperature = sort {$a <=> $b} @readings_temperature;
        @readings_humidity = sort {$a <=> $b} @readings_humidity;
        @readings_pressure = sort {$a <=> $b} @readings_pressure;
        @readings_rain = sort {$a <=> $b} @readings_rain;
        @readings_rain_1 = sort {$a <=> $b} @readings_rain_1;
        @readings_rain_24 = sort {$a <=> $b} @readings_rain_24;
        @readings_wind_angle = sort {$a <=> $b} @readings_wind_angle;
        @readings_wind_strength = sort {$a <=> $b} @readings_wind_strength;
        @readings_gust_angle = sort {$a <=> $b} @readings_gust_angle;
        @readings_gust_strength = sort {$a <=> $b} @readings_gust_strength;
        @timestamps_temperature = sort {$a <=> $b} @timestamps_temperature;
        @timestamps_pressure = sort {$a <=> $b} @timestamps_pressure;
        @timestamps_rain = sort {$a <=> $b} @timestamps_rain;
        @timestamps_wind = sort {$a <=> $b} @timestamps_wind;
        @readings_altitude = sort {$a <=> $b} @readings_altitude;
        @readings_latitude = sort {$a <=> $b} @readings_latitude;
        @readings_longitude = sort {$a <=> $b} @readings_longitude;

        if(scalar(@readings_temperature) > 4) 
        {
          for (my $i=0;$i<scalar(@readings_temperature)/10;$i++)
          {
            pop @readings_temperature;
            pop @readings_humidity;
            pop @timestamps_temperature;
            shift @readings_temperature;
            shift @readings_humidity;
            shift @timestamps_temperature;
          }
        }
        if(scalar(@readings_pressure) > 4) 
        {
          for (my $i=0;$i<scalar(@readings_pressure)/10;$i++)
          {
            pop @readings_pressure;
            pop @timestamps_pressure;
            shift @readings_pressure;
            shift @timestamps_pressure;
          }
        }
        if(scalar(@readings_rain) > 4) 
        {
          for (my $i=0;$i<scalar(@readings_rain)/20;$i++)
          {
            pop @readings_rain;
            pop @readings_rain_1;
            pop @readings_rain_24;
            pop @timestamps_rain;
            shift @readings_rain;
            shift @readings_rain_1;
            shift @readings_rain_24;
            shift @timestamps_rain;
          }
        }
        if(scalar(@readings_wind_strength) > 4) 
        {
          for (my $i=0;$i<scalar(@readings_wind_strength)/25;$i++)
          {
            pop @readings_wind_strength;
            pop @readings_gust_strength;
            pop @timestamps_wind;
            shift @readings_wind_strength;
            shift @readings_gust_strength;
            shift @timestamps_wind;
          }
        }
        if(scalar(@readings_pressure) > 4) 
        {
          for (my $i=0;$i<scalar(@readings_pressure)/20;$i++)
          {
            pop @readings_altitude;
            pop @readings_latitude;
            pop @readings_longitude;
            shift @readings_altitude;
            shift @readings_latitude;
            shift @readings_longitude;
          }
        }

        my $avg_temperature = 0;
        my $min_temperature = 100;
        my $max_temperature = -100;
        foreach my $val (@readings_temperature)
        {
          $avg_temperature += $val / scalar(@readings_temperature);
          $min_temperature = $val if($val < $min_temperature);
          $max_temperature = $val if($val > $max_temperature);
        }
        my $avg_humidity = 0;
        my $min_humidity = 100;
        my $max_humidity = -100;
        foreach my $val (@readings_humidity)
        {
          $avg_humidity += $val / scalar(@readings_humidity);
          $min_humidity = $val if($val < $min_humidity);
          $max_humidity = $val if($val > $max_humidity);
        }
        my $avgtime_temperature = 0;
        foreach my $val (@timestamps_temperature)
        {
          $avgtime_temperature += $val / scalar(@timestamps_temperature);
        }
        my $avg_pressure = 0;
        my $min_pressure = 2000;
        my $max_pressure = -2000;
        foreach my $val (@readings_pressure)
        {
          $avg_pressure += $val / scalar(@readings_pressure);
          $min_pressure = $val if($val < $min_pressure);
          $max_pressure = $val if($val > $max_pressure);
        }
        my $avgtime_pressure = 0;
        foreach my $val (@timestamps_pressure)
        {
          $avgtime_pressure += $val / scalar(@timestamps_pressure);
        }
        my $avg_rain = 0;
        my $min_rain = 1000;
        my $max_rain = -1000;
        foreach my $val (@readings_rain)
        {
          $avg_rain += $val / scalar(@readings_rain);
          $min_rain = $val if($val < $min_rain);
          $max_rain = $val if($val > $max_rain);
        }
        my $avg_rain_1 = 0;
        my $min_rain_1 = 1000;
        my $max_rain_1 = -1000;
        foreach my $val (@readings_rain_1)
        {
          $avg_rain_1 += $val / scalar(@readings_rain_1);
          $min_rain_1 = $val if($val < $min_rain_1);
          $max_rain_1 = $val if($val > $max_rain_1);
        }
        my $avg_rain_24 = 0;
        my $min_rain_24 = 1000;
        my $max_rain_24 = -1000;
        foreach my $val (@readings_rain_24)
        {
          $avg_rain_24 += $val / scalar(@readings_rain_24);
          $min_rain_24 = $val if($val < $min_rain_24);
          $max_rain_24 = $val if($val > $max_rain_24);
        }
        my $avgtime_rain = 0;
        foreach my $val (@timestamps_rain)
        {
          $avgtime_rain += $val / scalar(@timestamps_rain);
        }

        my $avg_wind = 0;
        my $min_wind = 100;
        my $max_wind = -100;
        foreach my $val (@readings_wind_strength)
        {
          $avg_wind += $val / scalar(@readings_wind_strength);
          $min_wind = $val if($val < $min_wind);
          $max_wind = $val if($val > $max_wind);
        }
        my $avg_gust = 0;
        my $min_gust = 100;
        my $max_gust = -100;
        foreach my $val (@readings_gust_strength)
        {
          $avg_gust += $val / scalar(@readings_gust_strength);
          $min_gust = $val if($val < $min_gust);
          $max_gust = $val if($val > $max_gust);
        }
        my $angle_wind_x = 0;
        my $angle_wind_y = 0;
        foreach my $val (@readings_wind_angle)
        {
          next if($val == -1);
          Log3 $name, 5, "$name: wind angle ".$val;
          $angle_wind_x += cos($val);
          $angle_wind_y += sin($val);
        }
        my $angle_wind = atan2($angle_wind_x,$angle_wind_y);
        $angle_wind = ($angle_wind >= 0 ? $angle_wind : (2* pi + $angle_wind)) * 180/ pi;
        Log3 $name, 4, "$name: wind angle avg ".$angle_wind;
        my $angle_gust_x = 0;
        my $angle_gust_y = 0;
        foreach my $val (@readings_gust_angle)
        {
          next if($val == -1);
          Log3 $name, 5, "$name: gust angle ".$val;
          $angle_gust_x += cos($val);
          $angle_gust_y += sin($val);
        }
        my $angle_gust = atan2($angle_gust_x,$angle_gust_y);
        $angle_gust = ($angle_gust >= 0 ? $angle_gust : (2* pi + $angle_gust)) * 180/ pi;
        Log3 $name, 4, "$name: gust angle avg ".$angle_gust;
        my $avgtime_wind = 0;
        foreach my $val (@timestamps_wind)
        {
          $avgtime_wind += $val / scalar(@timestamps_wind);
        }

        my $avg_altitude = 0;
        my $min_altitude = 10000;
        my $max_altitude = -10000;
        foreach my $val (@readings_altitude)
        {
          $avg_altitude += $val / scalar(@readings_altitude);
          $min_altitude = $val if($val < $min_altitude);
          $max_altitude = $val if($val > $max_altitude);
        }
        my $avg_latitude = 0;
        foreach my $val (@readings_latitude)
        {
          $avg_latitude += $val / scalar(@readings_latitude);
        }
        my $avg_longitude = 0;
        foreach my $val (@readings_longitude)
        {
          $avg_longitude += $val / scalar(@readings_longitude);
        }

        $avg_temperature = sprintf( "%.2f", $avg_temperature );
        $avg_humidity = sprintf( "%.2f", $avg_humidity );
        $avg_pressure = sprintf( "%.2f", $avg_pressure );
        $avg_rain = sprintf( "%.2f", $avg_rain );
        $avg_rain_1 = sprintf( "%.2f", $avg_rain_1 );
        $avg_rain_24 = sprintf( "%.2f", $avg_rain_24 );
        $avg_wind = sprintf( "%.1f", $avg_wind );
        $avg_gust = sprintf( "%.1f", $avg_gust );
        $angle_wind = sprintf( "%i", $angle_wind );
        $angle_gust = sprintf( "%i", $angle_gust );
        $avgtime_temperature = sprintf( "%i", $avgtime_temperature );
        $avgtime_pressure = sprintf( "%i", $avgtime_pressure );
        $avgtime_rain = sprintf( "%i", $avgtime_rain );
        $avgtime_wind = sprintf( "%i", $avgtime_wind );
        $avg_altitude = sprintf( "%.2f", $avg_altitude );
        $avg_latitude = sprintf( "%.8f", $avg_latitude );
        $avg_longitude = sprintf( "%.8f", $avg_longitude );

        if(scalar(@readings_temperature) > 0)
        {
          push(@readings, [$avgtime_temperature, 'temperature', $avg_temperature]);
          push(@readings, [$avgtime_temperature, 'temperature_min', $min_temperature]);
          push(@readings, [$avgtime_temperature, 'temperature_max', $max_temperature]);
          push(@readings, [$avgtime_temperature, 'humidity', $avg_humidity]);
          push(@readings, [$avgtime_temperature, 'humidity_min', $min_humidity]);
          push(@readings, [$avgtime_temperature, 'humidity_max', $max_humidity]);
        }
        if(scalar(@readings_pressure) > 0)
        {
          push(@readings, [$avgtime_pressure, 'pressure', $avg_pressure]);
          push(@readings, [$avgtime_pressure, 'pressure_min', $min_pressure]);
          push(@readings, [$avgtime_pressure, 'pressure_max', $max_pressure]);
        }
        if(scalar(@readings_rain) > 0)
        {
          push(@readings, [$avgtime_rain, 'rain', $avg_rain]);
          push(@readings, [$avgtime_rain, 'rain_min', $min_rain]);
          push(@readings, [$avgtime_rain, 'rain_max', $max_rain]);
          push(@readings, [$avgtime_rain, 'rain_hour', $avg_rain_1]);
          push(@readings, [$avgtime_rain, 'rain_hour_min', $min_rain_1]);
          push(@readings, [$avgtime_rain, 'rain_hour_max', $max_rain_1]);
          push(@readings, [$avgtime_rain, 'rain_day', $avg_rain_24]);
          push(@readings, [$avgtime_rain, 'rain_day_min', $min_rain_24]);
          push(@readings, [$avgtime_rain, 'rain_day_max', $max_rain_24]);
        }
        if(scalar(@readings_wind_strength) > 0)
        {
          push(@readings, [$avgtime_wind, 'wind', $avg_wind]);
          push(@readings, [$avgtime_wind, 'wind_min', $min_wind]);
          push(@readings, [$avgtime_wind, 'wind_max', $max_wind]);
          push(@readings, [$avgtime_wind, 'gust', $avg_gust]);
          push(@readings, [$avgtime_wind, 'gust_min', $min_gust]);
          push(@readings, [$avgtime_wind, 'gust_max', $max_gust]);
          push(@readings, [$avgtime_wind, 'wind_angle', $angle_wind]);
          push(@readings, [$avgtime_wind, 'gust_angle', $angle_gust]);
        }
        if(scalar(@readings_altitude) > 0)
        {
          $hash->{altitude} = $avg_altitude;
          $hash->{location} = $avg_latitude.",".$avg_longitude;
        }
        $hash->{stations_indoor} = scalar(@readings_pressure);
        $hash->{stations_outdoor} = scalar(@readings_temperature);
        $hash->{stations_rain} = scalar(@readings_rain);
        $hash->{stations_wind} = scalar(@readings_wind_strength);

        my (undef,$latest) = netatmo_updateReadings( $hash, \@readings );
        $hash->{LAST_POLL} = FmtDateTime( $latest ) if( @readings );

        #$hash->{STATE} = "Error: device not found" if( !$found );
      } else {
        return $json->{body};
      }
    } #else {
      #return $hash->{status};
    #}
  }
  else
  {
    $hash->{status} = "error";
  }
  readingsSingleUpdate( $hash, "active", $hash->{status}, 1 ) if($hash->{status} ne "no data");

}

sub
netatmo_parseAddress($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseAddress";
  
  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    if( $hash->{status} eq "OK" ) {
      if( $json->{results} ) {
        return $json->{results}->[0]->{formatted_address};
      }
    } else {
      return $hash->{status};
    }
  }
}

sub
netatmo_parseLatLng($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseLatLng";
  
  if( $json ) {
    Log3 $name, 5, "$name: ".Dumper($json);
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    if( $hash->{status} eq "OK" ) {
      if( $json->{results} ) {
        return $json->{results}->[0]->{geometry}->{bounds};
      }
    } else {
      return $hash->{status};
    }
  }
}

sub
netatmo_pollDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{openRequests} = 0 if ( !defined(  $hash->{openRequests}) );

  if( $hash->{Module} )
  {
    my @types = split( ' ', $hash->{dataTypes} ) if(defined($hash->{dataTypes}));
    Log3 $name, 4, "$name: pollDevice types [".$hash->{dataTypes} . "] for modules [".$hash->{Module}."]" if(defined($hash->{dataTypes}));

    my $lastupdate = ReadingsVal( $hash->{NAME}, ".lastupdate", undef );
    $lastupdate = (time-7*24*60*60) if(!$lastupdate and !$hash->{model});
    $hash->{openRequests} += int(@types);
    $hash->{openRequests} += 1 if(int(@types)==0);
    
    readingsSingleUpdate($hash, ".lastupdate", $lastupdate, 0) if(int(@types)>0);
    
    foreach my $module (split( ' ', $hash->{Module} ) ) {
      my $type = shift(@types) if( $module and @types);
      netatmo_requestDeviceReadings( $hash, $hash->{Device}, $type, ($module ne $hash->{Device})?$module:undef );# if($type);
    }
  }
  elsif( defined($hash->{Lat}) )
  {
    #$hash->{openRequests} += 1;
    netatmo_getPublicDevices($hash, 0, $hash->{Lat}, $hash->{Lon}, $hash->{Rad} );
  } elsif( $hash->{Device} ) {
    $hash->{openRequests} += 1;
    netatmo_requestDeviceReadings( $hash, $hash->{Device} );
  }
}

sub
netatmo_pollThermostat($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{openRequests} = 0 if ( !defined(  $hash->{openRequests}) );

  if( $hash->{Thermostat} )
  {
    Log3 $name, 4, "$name: pollThermostat types [".$hash->{dataTypes} . "] for thermostat [".$hash->{Thermostat}."]" if(defined($hash->{dataTypes}));
    my $lastupdate = ReadingsVal( $hash->{NAME}, ".lastupdate", undef );
    $lastupdate = (time-7*24*60*60) if(!$lastupdate and !$hash->{model});
    $hash->{openRequests} += 1;
    my $type = $hash->{dataTypes};

    readingsSingleUpdate($hash, ".lastupdate", $lastupdate, 0) if($type);
    netatmo_requestDeviceReadings( $hash, $hash->{Relay}, $type, $hash->{Thermostat} );# if($type);
  }
  elsif( $hash->{Relay} )
  {
    $hash->{openRequests} += 1;
    netatmo_requestDeviceReadings( $hash, $hash->{Relay} );
  }
}

sub
netatmo_pollGlobal($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  netatmo_refreshToken($hash, defined($hash->{access_token}));
  return undef if(!defined($hash->{access_token}));

  Log3 $name, 4, "$name: pollGlobal";

  HttpUtils_NonblockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/getstationsdata",
      timeout => 20,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
      hash => $hash,
      type => 'stationsdata',
      callback => \&netatmo_dispatch,
    });

  return undef;
}

sub
netatmo_pollGlobalHealth($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  netatmo_refreshToken($hash, defined($hash->{access_token}));
  return undef if(!defined($hash->{access_token}));

  Log3 $name, 4, "$name: pollGlobalHealth";

  HttpUtils_NonblockingGet({
      url => "https://".$hash->{helper}{apiserver}."/api/gethomecoachsdata",
      timeout => 20,
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
      hash => $hash,
      type => 'stationsdata',
      callback => \&netatmo_dispatch,
    });

  return undef;
}

sub
netatmo_pollForecast($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!defined($hash->{Station}))
  {
    Log3 $name, 1, "$name: device missing the definition! please redefine it.";
    
    return undef;  
  }
  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshAppToken($iohash, defined($iohash->{access_token_app}));
  return undef if(!defined($iohash->{access_token_app}));
  
  if(!defined($iohash->{access_token_app}))
  {
    Log3 $name, 1, "$name: pollForecast - missing app token!";
    return undef;
  }

  Log3 $name, 4, "$name: pollForecast (forecastdata)";

  HttpUtils_NonblockingGet({
      url => "https://app.netatmo.net/api/simplifiedfuturemeasure",
      timeout => 20,
      noshutdown => 1,
      data => { device_id => $hash->{Station}, },
      header => "Authorization: Bearer ".$iohash->{access_token_app},
      hash => $hash,
      type => 'forecastdata',
      callback => \&netatmo_dispatch,
    });

  return undef;
}

sub
netatmo_pollHome($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: pollHome (".$hash->{Home}.")";

  if( $hash->{Home} ) {
    
    return undef if($hash->{status} =~ /usage/ || $hash->{status} =~ /too_many_connections/ || $hash->{status} =~ /postponed/);
    
    my $lastupdate = ReadingsVal( $hash->{NAME}, ".lastupdate", undef );
    $lastupdate = (time-7*24*60*60) if(!$lastupdate);
    
    readingsSingleUpdate($hash, ".lastupdate", $lastupdate, 0);
    netatmo_requestHomeReadings( $hash, $hash->{Home} );
  }
}

sub
netatmo_pollRelay($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: pollRelay (".$hash->{Relay}.")";

  if( $hash->{Relay} ) {
    return undef if(defined($hash->{status}) && ($hash->{status} =~ /usage/ || $hash->{status} =~ /too_many_connections/ || $hash->{status} =~ /postponed/));

    my $lastupdate = ReadingsVal( $hash->{NAME}, ".lastupdate", undef );
    $lastupdate = (time-7*24*60*60) if(!$lastupdate);
    readingsSingleUpdate($hash, ".lastupdate", $lastupdate, 0);
    netatmo_requestThermostatReadings( $hash, $hash->{Relay} );
  }
}



sub
netatmo_pollPerson($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: pollPerson";

  return undef if(defined($hash->{status}) && ($hash->{status} =~ /usage/ || $hash->{status} =~ /too_many_connections/ || $hash->{status} =~ /postponed/));

  if( $hash->{Home} ) {
    my $lastupdate = ReadingsVal( $hash->{NAME}, ".lastupdate", undef );
    $lastupdate = (time-7*24*60*60) if(!$lastupdate);
    readingsSingleUpdate($hash, ".lastupdate", $lastupdate, 0);
    netatmo_requestPersonReadings( $hash );
  }
}


sub
netatmo_Get($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";
  if( $hash->{SUBTYPE} eq "DEVICE"
      || $hash->{SUBTYPE} eq "MODULE"
      || $hash->{SUBTYPE} eq "PUBLIC"
      || $hash->{SUBTYPE} eq "FORECAST"
      || $hash->{SUBTYPE} eq "HOME"
      || $hash->{SUBTYPE} eq "CAMERA"
      || $hash->{SUBTYPE} eq "PERSON"
      || $hash->{SUBTYPE} eq "RELAY"
      || $hash->{SUBTYPE} eq "THERMOSTAT"
      || $hash->{SUBTYPE} eq "HEATINGHOME"
      || $hash->{SUBTYPE} eq "HEATINGROOM" ) {
    $list = "update:noArg";

    $list = " ping:noArg video video_local live live_local snapshot" if($hash->{SUBTYPE} eq "CAMERA");
    $list .= " config:noArg timelapse:noArg" if($hash->{SUBTYPE} eq "CAMERA" && defined($hash->{model}) && $hash->{model} eq "NOC");
    #$list .= " weathericon" if($hash->{SUBTYPE} eq "FORECAST");

    if( $cmd eq "weathericon" ) {
      return "no weather code was passed" if($args[0] eq "");
      return netatmo_weatherIcon();
    }

    if( $cmd eq "ping" ) {
      netatmo_pingCamera($hash);
      return undef;
    }

    if( $cmd eq "video" || $cmd eq "video_local" ) {
      return "no video_id was passed" if(!defined($args[0]) || $args[0] eq "");
      return netatmo_getCameraVideo($hash,$args[0],$cmd);
    }
    elsif( $cmd eq "live" || $cmd eq "live_local" ) {
      return netatmo_getCameraLive($hash,$cmd);
    }
    elsif($cmd eq "timelapse") {
      return netatmo_getCameraTimelapse($hash);
    }
    elsif( $cmd eq "snapshot" ) {
      return netatmo_getCameraSnapshot($hash);
    }
    elsif( $cmd eq "config" ) {
      return netatmo_getPresenceConfig($hash);
    }


    if( $cmd eq "updateAll" ) {
      $cmd = "update";
      CommandDeleteReading( undef, "$name .*" );
    }

    if( $cmd eq "update" ) {
      netatmo_poll($hash);
      return undef;
    }
  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    $list = "update:noArg devices:noArg homes:noArg thermostats:noArg homecoachs:noArg public showAccount:noArg";

    if( $cmd eq "update" ) {
      netatmo_poll($hash);
      return undef;
    }

    if( $cmd eq 'showAccount' )
    {
      my $username = $hash->{helper}{username};
      my $password = $hash->{helper}{password};

      return 'no username set' if( !$username );
      return 'no password set' if( !$password );

      $username = netatmo_decrypt( $username );
      $password = netatmo_decrypt( $password );

      return "username: $username\npassword: $password";
    }

    if( $cmd eq "devices" ) {
      my $devices = netatmo_getDevices($hash,1);
      my $ret;
      foreach my $device (@{$devices}) {
        $ret .= "\n" if( $ret );
        $ret .= "$device->{_id}\t$device->{firmware}\t$device->{type}\t".($device->{type} !~ /Module/ ? "\t" : "")."$device->{module_name}";
      }

      $ret = "id\t\t\tfw\ttype\t\tname\n" . $ret if( $ret );
      $ret = "no devices found" if( !$ret );
      return $ret;
    } elsif( $cmd eq "homes" ) {
        my $homes = netatmo_getHomes($hash,1);
        Log3 $name, 5, "$name: homes ".Dumper($homes);

        my $ret;
        foreach my $home (@{$homes}) {
          $ret .= "\n" if( $ret );
          $ret .= "$home->{id} \t\tHome\t".encode_utf8($home->{name}) if(defined($home->{cameras}) && @{$home->{cameras}});;
          if(defined($home->{status}))
          {
            $ret .= "$home->{id} \t\t\tCamera\t".encode_utf8($home->{name});
            foreach my $tag (@{$home->{modules}}) {
              $ret .= "\n$tag->{id} \t\t\tTag\t".encode_utf8($tag->{name}) if(defined($tag->{name}));
            }
          }
          $ret .= "$home->{id} \tPerson\t".encode_utf8($home->{pseudo}) if(defined($home->{pseudo}));
          $ret .= "$home->{id} \tPerson\t(Unknown)" if(defined($home->{face}) && !defined($home->{pseudo}));
        }

        $ret = "id\t\t\t\t\ttype\tname\n" . $ret if( $ret );
        $ret = "no homes found" if( !$ret );
        return $ret;
      } elsif( $cmd eq "thermostats" ) {
          my $thermostats = netatmo_getThermostats($hash,1);
          Log3 $name, 5, "$name: thermostats ".Dumper($thermostats);

          my $ret;
          foreach my $thermostat (@{$thermostats}) {
            $ret .= "\n" if( $ret );
            $ret .= "$thermostat->{id}\t$thermostat->{firmware}\t$thermostat->{type}\t ".$thermostat->{name};
          }

          $ret = "id\t\t\tfw\ttype\t name\n" . $ret if( $ret );
          $ret = "no thermostats found" if( !$ret );
          return $ret;
    } elsif( $cmd eq "homecoachs" ) {
      my $homecoachs = netatmo_getHomecoachs($hash,1);
      Log3 $name, 5, "$name: homecoachs ".Dumper($homecoachs);

      my $ret;
      foreach my $homecoach (@{$homecoachs}) {
        $ret .= "\n" if( $ret );
        $ret .= "$homecoach->{_id}\t$homecoach->{firmware}\t$homecoach->{type}\t$homecoach->{name}";
      }

      $ret = "id\t\t\tfw\ttype\t name\n" . $ret if( $ret );
      $ret = "no homecoachs found" if( !$ret );
      return $ret;
    } elsif( $cmd eq "public" ) {
      my $station = '';
      my $addr = '';
      $station = shift @args if( $args[0] && $args[0] =~ m/[\da-f]{2}(:[\da-f]{2}){5}/ );

      if( @args && defined($args[0]) && ( $args[0] =~ m/^\d{5}$/
                        || $args[0] =~ m/^a:/ ) ) {
        $addr = shift @args;
        $addr = substr($addr,2) if( $addr =~ m/^a:/ );

        my $bounds =  netatmo_getLatLong( $hash,1,$addr );
        $args[0] = $bounds->{northeast}->{lat};
        $args[1] = $bounds->{northeast}->{lng};
        $args[2] = $bounds->{southwest}->{lat};
        $args[3] = $bounds->{southwest}->{lng};
      } elsif(defined($args[0]) && $args[0] =~ m/,/) {
        my @latlon1 = split( ',', $args[0] );
        if($args[1] !~ m/,/){
          $args[3] = undef;
          $args[2] = $args[1];
        } else {
          my @latlon2 = split( ',', $args[1] );
          $args[3] = $latlon2[1];
          $args[2] = $latlon2[0];
        }
        $args[1] = $latlon1[1];
        $args[0] = $latlon1[0];
      }

      my $devices = netatmo_getPublicDevices($hash, 1, $args[0], $args[1], $args[2], $args[3] );
      my $ret;
      my $addresscount = 0;
      if( ref($devices) eq "ARRAY" ) {
        my $csrftoken = (defined($FW_CSRF) ? $FW_CSRF : "&nocsrf");
        foreach my $device (@{$devices}) {
          next if(!defined($device->{_id}));
          next if( $station && $station ne $device->{_id} );
          my $idname = $device->{_id};
          $idname =~ s/:/_/g;
          next if(AttrVal("netatmo_D".$idname, "IODev", undef));
          next if(AttrVal("netatmo_D".$device->{_id}, "IODev", undef));
          next if(defined($modules{$hash->{TYPE}}{defptr}{"D$idname"}));
          next if(defined($modules{$hash->{TYPE}}{defptr}{"D$device->{_id}"}));

          $ret .= "\n" if( $ret );
          $ret .= sprintf( "%s<a href=\"https://www.google.com/maps/@%.8f,%.8f,19z\" target=\"gmaps\"> %.6f,%.6f %i m</a>", $device->{_id},
                                                 $device->{place}->{location}->[1], $device->{place}->{location}->[0],
                                                 $device->{place}->{location}->[1], $device->{place}->{location}->[0],
                                                 $device->{place}->{altitude} );
          #$ret .= "\t";
          $addr = '';
          $addr .= netatmo_getAddress( $hash, 1, $device->{place}->{location}->[1], $device->{place}->{location}->[0] ) if($addresscount++ < AttrVal($name,"addresslimit",10));
          $addr .= " (address limit reached, " if($addresscount == AttrVal($name,"addresslimit",10)+2);
          $addr .= "  change attribute addresslimit to see more) " if($addresscount == AttrVal($name,"addresslimit",10)+3);
          next if( ref($device->{measures}) ne "HASH" );

          my $ext;
          my $got_temp;
          my $got_press;

          foreach my $module ( sort keys %{$device->{measures}}) {
            next if( ref($device->{measures}->{$module}->{res}) ne "HASH" );

            $ext .= "$module ";
            $ext .= join(',', @{$device->{measures}->{$module}->{type}});
            $ext .= " ";

            foreach my $timestamp ( keys %{$device->{measures}->{$module}->{res}} ) {
              my $i = 0;
              foreach my $value ( @{$device->{measures}->{$module}->{res}->{$timestamp}} ) {
                my $type = $device->{measures}->{$module}->{type}[$i];

                if( $type eq "temperature" ) {
                  $ret .= "\t";
                  $ret .= " " if(int($value)<10);
                  $ret .= sprintf( "%.1f \xc2\xb0C", $value );
                  $got_temp = 1;
                } elsif( $type eq "humidity" ) {
                  $ret .= "\t";
                  $ret .= " " if(int($value)<10);
                  $value = 99 if(int($value)>99);
                  $ret .= sprintf( "%i %%", $value );
                } elsif( $type eq "pressure" ) {
                  $ret .= "\t\t" if( !$got_temp );
                  $ret .= "\t";
                  $ret .= " " if(int($value)<1000);
                  $ret .= sprintf( "%i hPa", $value );
                  $got_press = 1;
                } elsif( $type eq "rain" ) {
                  $ret .= "\t" if( !$got_temp );
                  $ret .= "\t\t" if( !$got_press );
                  #$ret .= "\t";
                  $ret .= "   ";
                  $ret .= " " if(int($value)<10);
                  $ret .= sprintf( "%i mm", $value );
                }
                else
                {
                  Log3 $name, 2, "$name: unknown type ".$type;
                }

              ++$i;
              }

              last;
            }
          }
          my $got_rain = 0;
          foreach my $module ( keys %{$device->{measures}}) {
            my $value = $device->{measures}->{$module}->{rain_24h};
            if( defined($value) ) {
              $got_rain = 1;

              $ext .= "$module ";
              $ext .= "rain";
              $ext .= " ";

              if( defined($value) )
              {
                $ret .= "\t\t\t   " if( !$got_press );
                $ret .= "\t   ";
                $ret .= " " if(int($value)<10);
                $value = 99 if(int($value)>99);
                $ret .= sprintf( "%.1f mm", $value );
              }
            }
          }
          $ret .= "\t\t" if( !$got_rain );

          my $got_wind = 0;
          foreach my $module ( keys %{$device->{measures}}) {
            my $value = $device->{measures}->{$module}->{gust_strength};
            if( defined($value) ) {
              $got_wind = 1;

              $ext .= "$module ";
              $ext .= "windstrength,windangle,guststrength,gustangle";
              $ext .= " ";

              if( defined($value) )
              {
                $ret .= "   ";
                $ret .= " " if(int($value)<10);
                $value = 99 if(int($value)>99);
                $ret .= sprintf( "%i km/h", $value );
              }
            }
          }
          $ret .= "\t" if( !$got_wind );

          $ret .= "\t $addr" if(defined($addr));

          #$ret .= "\n\tdefine netatmo_P$device->{_id} netatmo PUBLIC $device->{_id} $ext" if( $station );
          my $definelink = "<a href=\"#\" onclick=\"javascript:window.open((\'".$FW_ME."?cmd=define netatmo_D".$idname." net+++atmo PUBLIC ".$device->{_id}." ".$ext.$csrftoken."\').replace('+++',''), 'definewindow');\">=&gt; </a>";
          $ret =~ s/$device->{_id}/$definelink/;
        }
      } else {
        $ret = $devices if( !ref($devices) );
      }

      $ret = "    latitude,longitude  alt\ttemp\thum\tpressure\t  rain\t\twind\t address\n" . $ret if( $ret );
      $ret = "no devices found" if( !$ret );
      return $ret;
    }
  }

  return "Unknown argument $cmd, choose one of $list";
}


#########################
sub 
netatmo_addExtension($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #netatmo_removeExtension() ;
  my $url = "/netatmo";
  delete $data{FWEXT}{$url} if($data{FWEXT}{$url});

  Log3 $name, 1, "Starting Netatmo webhook for $name";
  $data{FWEXT}{$url}{deviceName} = $name;
  $data{FWEXT}{$url}{FUNC}       = "netatmo_Webhook";
  $data{FWEXT}{$url}{LINK}       = "netatmo";
  
  netatmo_registerWebhook($hash);
}

#########################
sub 
netatmo_removeExtension($) {
  my ($hash) = @_;

  netatmo_dropWebhook($hash);
  
  my $url  = "/netatmo";
  my $name = $data{FWEXT}{$url}{deviceName};
  Log3 $name, 3, "Stopping Netatmo webhook for $name";
  delete $data{FWEXT}{$url};
}

sub
netatmo_registerWebhook($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );
  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash, defined($iohash->{access_token}));
  return undef if(!defined($iohash->{access_token}));

  Log3 $name, 3, "Registering Netatmo webhook";

  my $webhookurl = AttrVal($name,"webhookURL",undef);
  return undef if(!defined($webhookurl));
  
  HttpUtils_NonblockingGet({
    url => "https://".$iohash->{helper}{apiserver}."/api/addwebhook",
    timeout => 20,
    noshutdown => 1,
    data => { access_token => $iohash->{access_token}, url => $webhookurl, app_type => 'app_security', },
    hash => $hash,
    type => 'addwebhook',
    callback => \&netatmo_dispatch,
  });

}

sub
netatmo_dropWebhook($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );
  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash, defined($iohash->{access_token}));
  return undef if(!defined($iohash->{access_token}));

  Log3 $name, 3, "Dropping Netatmo webhook";
  
  HttpUtils_NonblockingGet({
    url => "https://".$iohash->{helper}{apiserver}."/api/dropwebhook",
    timeout => 20,
    noshutdown => 1,
    data => { access_token => $iohash->{access_token}, app_type => 'app_security', },
    hash => $hash,
    type => 'dropwebhook',
    callback => \&netatmo_dispatch,
  });

}

sub
netatmo_webhookStatus($$$)
{
  my($hash, $json, $hookstate) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: webhookStatus ($hookstate)";

  if( $json ) {
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    $hookstate = "error" if( $json->{error} );
    readingsSingleUpdate($hash, "webhook", $hookstate, 1);
  }
  else
  {
    $hash->{status} = "error";
    readingsSingleUpdate($hash, "webhook", "error", 1);
  }
  return ( "text/plain; charset=utf-8",
      "JSON" );
}

sub netatmo_Webhook() {
  my ($request) = @_;
  my $hash = $modules{"netatmo"}{defptr}{"WEBHOOK"};
  if(!defined($hash)){
    Log3 "netatmo", 1, "Netatmo webhook hash not defined!";
    return ( "text/plain; charset=utf-8",
        "HASH" );
  }
  my $name = $hash->{NAME};

  
  my ($link,$data);
  
  if ( $request =~ m,^(\/[^/]+?)(?:\&|\?|\/\?|\/)(.*)?$, ) {
    $link = $1;
    $data  = $2;
  } else {
    Log3 "netatmo", 1, "Netatmo webhook no data received!";
    return ( "text/plain; charset=utf-8",
        "NO" );
  }

  Log3 $name, 5, "Netatmo webhook JSON:\n".$data;

  my $json = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
  {
    Log3 $name, 2, "$name: invalid json evaluation for webhook ".$@;
    return undef;
  }

  readingsBeginUpdate($hash);
  
  if(defined($json->{message})){
    my $eventmessage = $json->{message};
    $eventmessage =~ s/<\/b>//g;
    $eventmessage =~ s/<\/b>//g;
    readingsBulkUpdate( $hash, "state", $eventmessage );
  }
  readingsBulkUpdate( $hash, "event_type", $json->{event_type} ) if(defined($json->{event_type}));
  readingsBulkUpdate( $hash, "camera_id", $json->{camera_id} ) if(defined($json->{camera_id}));
  readingsBulkUpdate( $hash, "module_id", $json->{module_id} ) if(defined($json->{module_id}));
  readingsBulkUpdate( $hash, "person_id", $json->{persons}[0]{id} ) if(defined($json->{persons}[0]{id}));
  if(defined($json->{snapshot_id})) {
    readingsBulkUpdate( $hash, "snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$json->{snapshot_id}."&key=".$json->{snapshot_key}, 1 );
  }
  elsif(defined($json->{persons}[0]{face_id})) {
    readingsBulkUpdate( $hash, "snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$json->{persons}[0]{face_id}."&key=".$json->{persons}[0]{face_key}, 1 );
  }
  readingsEndUpdate( $hash, 1 );

  if(AttrVal($name,"webhookPoll","0") eq "1" && defined($json->{home_id}))
  {
    my $home = $modules{$hash->{TYPE}}{defptr}{"H$json->{home_id}"};
    netatmo_poll($home) if($home->{status} !~ /usage/ && $home->{status} !~ /too_many_connections/ && $home->{status} !~ /postponed/);;
  }



  return ( "text/plain; charset=utf-8",
      "{\"status\":\"ok\"}" );
}

sub netatmo_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval" || $attrName eq "setpoint_duration");
  $attrVal = 15 if($attrName eq "setpoint_duration" && $attrVal < 15 && $attrVal != 0);
  return undef if(!defined($defs{$name}));

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $attrVal = 60*5 if($hash->{SUBTYPE} ne "HOME" && $attrVal < 60*5 && $attrVal != 0);

    #\$attrVal = 2700 if(($attrVal < 2700 && ($hash->{SUBTYPE} eq "ACCOUNT" || $hash->{SUBTYPE} eq "FORECAST");
    $hash->{helper}{INTERVAL} = $attrVal if($attrVal);
    $hash->{helper}{INTERVAL} = 60*30 if( !$hash->{helper}{INTERVAL} );
  } elsif( $attrName eq "setpoint_duration" ) {
      my $hash = $defs{$name};
      #$hash->{SETPOINT_DURATION} = $attrVal;
      #$hash->{SETPOINT_DURATION} = 60 if( !$hash->{SETPOINT_DURATION} );
  } elsif( $attrName eq "serverAPI" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "" ) {
      $hash->{helper}{apiserver} = $attrVal;
    } else {
      $hash->{helper}{apiserver} = "api.netatmo.com";
    }
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
      netatmo_poll($hash);
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


sub netatmo_encrypt($)
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

sub netatmo_decrypt($)
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
sub netatmo_DbLog_splitFn($)
{
  my ($event) = @_;
  my ($reading, $value, $unit) = "";

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value = $parts[1];

  if($event =~ m/T: / && $event =~ m/H: /)
  {
    return undef; #dewpoint workaround - no logging
  }
  elsif($event =~ m/symbol/ || $event =~ m/message/)
  {
    $unit = ''; #symbols & text
  }
  elsif($event =~ m/trend/)
  {
    $unit = ''; #trends
  }
  elsif($event =~ m/date/ || $event =~ m/sunrise/ || $event =~ m/sunset/)
  {
    $unit = ''; #dates
  }
  elsif($event =~ m/temp/ || $event =~ m/dewpoint/)
  {
    $unit = "˚C";
  }
  elsif($event =~ m/humidity/)
  {
    $unit = '%';
  }
  elsif($event =~ m/pressure/)
  {
    $unit = 'mbar';
  }
  elsif($event =~ m/co2/)
  {
    $unit = 'ppm';
  }
  elsif($event =~ m/noise/)
  {
    $unit = 'dB';
  }
  elsif($event =~ m/rain/)
  {
    $unit = 'mm';
  }
  elsif($event =~ m/angle/ || $event =~ m/direction/)
  {
    $unit = "deg";
  }
  elsif($event =~ m/strength/ || $event =~ m/gust/)
  {
    $unit = 'km/h';
  }
  elsif($event =~ m/boilero/)
  {
    $unit = 'sec';
  }
  elsif($event =~ m/percent/)
  {
    $unit = '%';
  }
  elsif($event =~ m/sun/)
  {
    $unit = 'h';
  }
  elsif($event =~ m/air_/)
  {
    $unit = "ug/m3";
  }
  elsif($event =~ m/batteryPercent/)
  {
    $unit = "%";
  }
  elsif($event =~ m/batteryVoltage/)
  {
    $unit = "V";
  }
  else
  {
    $value = $parts[1];
    $value = $value." ".$parts[2] if(defined($parts[2]));
  }
  return ($reading, $value, $unit);
}


sub netatmo_weatherIcon()
{
  my $svgheader = '<?xml version="1.0" encoding="utf-8"?><!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"><svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" viewBox="0 0 500 500" enable-background="new 0 0 500 500" xml:space="preserve">';
  
  my $svgcontent = '<path id="smallcloud" opacity="1.0" fill="#000000" d="M162.8,46.7c-7.4-5.8-16.5-9.5-26.5-9.5C128.8,14.8,108.1,0,84.3,0h-1.6';
  $svgcontent .= '		c-1.1,0-2.2,0-3.3,0.1C71.4,0.7,62,3.1,58,6.9V6.6c0,0.1-0.2,0.2-0.3,0.3c-12.2,6.9-21.2,18-25.4,32.3C13.2,45.1-0.1,62.1-0.1,82.8';
  $svgcontent .= '		c0,25.5,20.7,46.2,46.2,46.2h88.6c25.5,0,45.6-20.8,45.6-46.2c0-5.3-0.5-10.6-2.7-15.9C173.5,56.2,171.8,52.7,162.8,46.7z';
  $svgcontent .= '		 M134.7,104H46.1c-11.7,0-20.7-9.6-20.7-21.2c0-10.6,8-19.6,18.6-20.7l8-1.1c2.1,0,2.7-0.5,2.7-2.7l1.1-7.4';
  $svgcontent .= '		c1.6-14.8,13.8-26,28.6-26c15.4,0,27.6,11.1,29.2,26l1.1,8.5c0.5,1.6,1.6,2.6,3.2,2.6h17c11.1,0,20.7,9.6,20.7,20.7';
  $svgcontent .= '		C155.3,94.4,145.8,104,134.7,104z"/>';
  
  my $svgfooter = '</svg>';
     
  return $svgheader . $svgcontent . $svgfooter;
}


1;

=pod
=item device
=item summary Netatmo weather stations, thermostats and cameras connected via the official API
=begin html

<a name="netatmo"></a>
<h3>netatmo</h3>
<ul>
  FHEM module for netatmo weather stations, thermostats and cameras.<br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
    <li>You need to create an app <u><a href="https://dev.netatmo.com/dev/createanapp">here</a></u> to get your <i>client_id / client_secret</i>.<br />Request the full access scope including cameras and thermostats.</li>
  </ul><br>

  <a name="netatmo_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; netatmo [ACCOUNT] &lt;username&gt; &lt;password&gt; &lt;client_id&gt; &lt;client_secret&gt;</code><br>
    <code>define &lt;name&gt; netatmo &lt;device&gt;</code><br>
    <br>

    Defines a netatmo device.<br><br>
    If a netatmo device of the account type is created all fhem devices for the netatmo devices are automaticaly created
    (if autocreate is not disabled).
    <br>

    Examples:
    <ul>
      <code>define netatmo netatmo ACCOUNT abc@test.com myPassword 2134123412399119d4123134 AkqcOIHqrasfdaLKcYgZasd987123asd</code><br>
      <code>define netatmo netatmo 2f:13:2b:93:12:31</code><br>
      <code>define netatmo netatmo MODULE  2f:13:2b:93:12:31 f1:32:b9:31:23:11</code><br>
      <code>define netatmo netatmo HOME 1234567890abcdef12345678</code><br>
      <code>define netatmo netatmo CAMERA 1234567890abcdef12345678 70:ee:12:34:56:78</code><br>
      <code>define netatmo netatmo PERSON 1234567890abcdef12345678 01234567-89ab-cdef-0123-456789abcdef</code><br>
    </ul>
  </ul><br>

  <a name="netatmo_Webhook"></a>
  <b>Webhook</b><br>
  <ul>
    <code>define netatmo netatmo WEBHOOK</code><br><br>
    Set your URL in attribute webhookURL, events from cameras will be received insantly
  </ul><br>

  <a name="netatmo_Readings"></a>
  <b>Readings</b>
  <ul>
  </ul><br>

  <a name="netatmo_Set"></a>
  <b>Set</b>
  <ul>
    <li>autocreate<br>
      Create fhem devices for all netatmo weather devices.</li>
    <li>autocreate_homes<br>
      Create fhem devices for all netatmo homes, cameras and persons.</li>
    <li>autocreate_thermostats<br>
      Create fhem devices for all netatmo relays and thermostats.</li>
    <li>autocreate_homecoachs<br>
      Create fhem devices for all netatmo homecoachs.</li>
  </ul><br>

  <a name="netatmo_Get"></a>
  <b>Get</b><br />
  ACCOUNT
  <ul>
    <li>devices<br>
      list the netatmo weather devices for this account</li>
    <li>home<br>
      list the netatmo home devices for this account</li>
    <li>update<br>
      trigger a global update for dashboard data</li>
    <li>public [&lt;address&gt;] &lt;args&gt;<br>
      no arguments -> get all public stations in a radius of 0.025&deg; around global fhem latitude/longitude<br>
      &lt;rad&gt; -> get all public stations in a radius of &lt;rad&gt;&deg; around global fhem latitude/longitude<br>
      &lt;lat&gt; &lt;lon&gt; [&lt;rad&gt;] -> get all public stations in a radius of 0.025&deg; or &lt;rad&gt;&deg; around &lt;lat&gt;/&lt;lon&gt;<br>
      &lt;lat1&gt; &lt;lon1&gt; &lt;lat2&gt; &lt;lon2&gt; -> get all public stations in the area of &lt;lat1&gt; &lt;lon2&gt; &lt;lat2&gt; &lt;lon2&gt;<br>
      if &lt;address&gt; is given then list stations in the area of this address. can be given as 5 digit german postal code or a: followed by a textual address. all spaces have to be replaced by a +.<br>
      &lt;lat&gt; &lt;lon&gt; values can also be entered as a single coordinates parameter &lt;lat&gt;,&lt;lon&gt;<br></li>
  </ul><br>
  DEVICE/MODULE
  <ul>
    <li>update<br>
      update the device readings</li>
    <li>updateAll<br>
      update the device readings after deleting all current readings</li>
  </ul><br>
  HOME
  <ul>
    <li>update<br>
      update the home events and all camera and person readings</li>
  </ul><br>
  CAMERA
  <ul>
    <li>ping<br>
      ping the camera and get the local command url</li>
    <li>live/_local<br>
      get the playlist for live video (internet or local network)</li>
    <li>video/_local &lt;video_id&gt;<br>
      get the playlist for a video id (internet or local network)</li>
  </ul><br>
  PRESENCE
  <ul>
    <li>config<br>
      read the camera config</li>
    <li>timelapse<br>
      get the link for a timelapse video (local network)</li>
  </ul><br>
  PERSON
  <ul>
    <li>update<br>
      n/a</li>
  </ul><br>

  <a name="netatmo_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
      the interval in seconds used to check for new values.</li>
    <li>disable<br>
      1 -> stop polling</li>
    <li>addresslimit<br>
      maximum number of addresses to resolve in public station searches (ACCOUNT - default: 10)</li>
    <li>setpoint_duration<br>
      setpoint duration in minutes (THERMOSTAT - default: 60)</li>
    <li>videoquality<br>
      video quality for playlists (HOME - default: medium)</li>
    <li>webhookURL<br>
      webhook URL - can include basic auth and ports: http://user:pass@your.url:8080/fhem/netatmo (WEBHOOK)</li>
    <li>webhookPoll<br>
      poll home after event from webhook (WEBHOOK - default: 0)</li>
    <li>ignored_device_ids<br>
      ids of devices/persons ignored on autocrate (ACCOUNT - comma separated)</li>
  </ul>
</ul>

=end html
=cut

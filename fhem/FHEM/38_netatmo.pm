##############################################################################
# $Id$
#
#  38_netatmo.pm
#
#  2016 Markus M.
#  Based on original code by justme1968
#
#  https://forum.fhem.de/index.php/topic,53500.0.html
#
#
##############################################################################
# Release 04

package main;

use strict;
use warnings;

use Encode qw(encode_utf8 decode_utf8);
use JSON;

use HttpUtils;

use Data::Dumper; #debugging

use MIME::Base64;


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
                      "disable:1 ".
                      "interval ".
                      "videoquality:poor,low,medium,high ".
                      "ignored_device_ids ".
                      "setpoint_duration ".
                      "addresslimit ";
  $hash->{AttrList} .= $readingFnAttributes;
}

#####################################

sub
netatmo_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  my $name = $a[0];

  my $subtype;
  if( @a == 3 ) {
    $subtype = "DEVICE";

    my $device = $a[2];

    $hash->{Device} = $device;

    $hash->{openRequests} = 0;
    $hash->{lastError} = undef;

    $hash->{INTERVAL} = 60*15 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;

  }
  elsif( ($a[2] eq "PUBLIC" && @a > 3 ) )
  {
    $hash->{openRequests} = 0;
    $hash->{lastError} = undef;

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
        $attr{$name}{stateFormat} = $state_format if( !defined($attr{$name}{stateFormat}) && defined($state_format) );
        $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}));
        $attr{$name}{devStateIcon} = ".*:no-icon" if( !defined($attr{$name}{devStateIcon}));
        #$attr{$name}{'event-on-change-reading'} = ".*" if( !defined($attr{$name}{'event-on-change-reading'}));


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

        Log3 $name, 5, "$name: latlng 2 ";
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

    $hash->{INTERVAL} = 60*30 if( !$hash->{INTERVAL} );
    $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}));
    $attr{$name}{devStateIcon} = ".*:no-icon" if( !defined($attr{$name}{devStateIcon}));
    #$attr{$name}{'event-on-change-reading'} = ".*" if( !defined($attr{$name}{'event-on-change-reading'}));

  } elsif( ($a[2] eq "MODULE" && @a == 5 ) ) {
    $subtype = "MODULE";

    my $device = $a[@a-2];
    my $module = $a[@a-1];

    $hash->{Device} = $device;
    $hash->{Module} = $module;

    $hash->{openRequests} = 0;
    $hash->{lastError} = undef;

    $hash->{INTERVAL} = 60*15 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"M$module"};
    return "module $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"M$module"} = $hash;

  } elsif( ($a[2] eq "FORECAST" && @a == 4 ) ) {
    $subtype = "FORECAST";

    my $device = $a[3];

    $hash->{Station} = $device;

    $hash->{openRequests} = 0;
    $hash->{lastError} = undef;

    $hash->{INTERVAL} = 60*60 if( !$hash->{INTERVAL} );
    $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}));
    $attr{$name}{devStateIcon} = ".*:no-icon" if( !defined($attr{$name}{devStateIcon}));
    $attr{$name}{'event-on-change-reading'} = ".*" if( !defined($attr{$name}{'event-on-change-reading'}));

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
    $hash->{lastError} = undef;

    $hash->{INTERVAL} = 60*30 if( !$hash->{INTERVAL} );

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
    $hash->{lastError} = undef;
    $hash->{dataTypes} = "Temperature,Sp_Temperature,BoilerOn,BoilerOff";
    $hash->{INTERVAL} = 60*30 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"T$module"};
    return "thermostat $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"T$module"} = $hash;

  } elsif( ($a[2] eq "HOME" && @a == 4 ) ) {
    $subtype = "HOME";

    my $home = $a[@a-1];

    $hash->{Home} = $home;

    $hash->{lastError} = undef;

    $hash->{INTERVAL} = 60*15 if( !$hash->{INTERVAL} );

    $attr{$name}{videoquality} = "medium" if( !defined($attr{$name}{videoquality}));

    my $d = $modules{$hash->{TYPE}}{defptr}{"H$home"};
    return "home $home already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"H$home"} = $hash;

  } elsif( ($a[2] eq "PERSON" && @a == 5 ) ) {
    $subtype = "PERSON";

    my $home = $a[@a-2];
    my $person = $a[@a-1];

    $hash->{Home} = $home;
    $hash->{Person} = $person;

    $hash->{INTERVAL} = 60*15 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"P$person"};
    return "person $person already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"P$person"} = $hash;

  } elsif( ($a[2] eq "CAMERA" && @a == 5 ) ) {
    $subtype = "CAMERA";

    my $home = $a[@a-2];
    my $camera = $a[@a-1];

    $hash->{Home} = $home;
    $hash->{Camera} = $camera;

    $hash->{lastError} = undef;

    $hash->{INTERVAL} = 60*15 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"C$camera"};
    return "camera $camera already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"C$camera"} = $hash;

  } elsif( ($a[2] eq "TAG" && @a == 5 ) ) {
    $subtype = "TAG";

    my $camera = $a[@a-2];
    my $tag = $a[@a-1];

    $hash->{Tag} = $tag;
    $hash->{Camera} = $camera;

    $hash->{lastError} = undef;

    #$hash->{INTERVAL} = 60*15 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"G$tag"};
    return "tag $tag already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"G$tag"} = $hash;

  } elsif( @a == 6  || ($a[2] eq "ACCOUNT" && @a == 7 ) ) {
    $subtype = "ACCOUNT";

    my $user = $a[@a-4];
    my $pass = $a[@a-3];
    my $username = netatmo_encrypt($user);
    my $password = netatmo_encrypt($pass);
    Log3 $name, 2, "$name: encrypt $user/$pass to $username/$password";

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

    $hash->{lastError} = undef;

    $hash->{INTERVAL} = 60*60 if( !$hash->{INTERVAL} );
    $attr{$name}{room} = "netatmo" if( !defined($attr{$name}{room}));

    $modules{$hash->{TYPE}}{defptr}{"account"} = $hash;


  } else {
    return "Usage: define <name> netatmo device\
       define <name> netatmo userid publickey\
       define <name> netatmo PUBLIC latitude longitude [radius]\
       define <name> netatmo [ACCOUNT] username password"  if(@a < 3 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;

  $hash->{STATE} = "Initialized";

  $hash->{NOTIFYDEV} = "global";

  # my $resolve = inet_aton("api.netatmo.com");
  # if(!defined($resolve))
  # {
  #   $hash->{STATE} = "DNS error";
  #   InternalTimer( gettimeofday() + 600, "netatmo_InitWait", $hash, 0);
  #   return undef;
  # }

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

  }
  else
  {
    InternalTimer(gettimeofday()+15, "netatmo_InitWait", $hash, 0);
  }

  return undef;
}

sub netatmo_InitWait($) {
  my ($hash) = @_;
  Log3 "netatmo", 5, "netatmo: initwait ".$init_done;

  RemoveInternalTimer($hash);

  # my $resolve = inet_aton("api.netatmo.com");
  # if(!defined($resolve))
  # {
  #   $hash->{STATE} = "DNS error";
  #   InternalTimer( gettimeofday() + 3600, "netatmo_InitWait", $hash, 0);
  #   return undef;
  # }

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
  }
  else
  {
    InternalTimer(gettimeofday()+30, "netatmo_InitWait", $hash, 0);
  }

  return undef;

}

sub
netatmo_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  RemoveInternalTimer($hash);

  # my $resolve = inet_aton("api.netatmo.com");
  # if(!defined($resolve))
  # {
  #   $hash->{STATE} = "DNS error";
  #   InternalTimer( gettimeofday() + 3600, "netatmo_InitWait", $hash, 0);
  #   return undef;
  # }

  netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "PUBLIC" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "FORECAST" );
  netatmo_initHome($hash) if( $hash->{SUBTYPE} eq "HOME" );
  netatmo_pingCamera($hash) if( $hash->{SUBTYPE} eq "CAMERA" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "RELAY" );
  netatmo_poll($hash) if( $hash->{SUBTYPE} eq "THERMOSTAT" );

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

  return undef;
}

sub
netatmo_Set($$@)
{
  my ($hash, $name, $cmd, @parameters) = @_;


  my $list = "";
  $list = "autocreate:noArg autocreate_homes:noArg autocreate_thermostats:noArg" if( $hash->{SUBTYPE} eq "ACCOUNT" );
  $list = "home:noArg away:noArg" if ($hash->{SUBTYPE} eq "PERSON");
  $list = "empty:noArg" if ($hash->{SUBTYPE} eq "HOME");
  $list = "enable disable irmode:auto,always,never led_on_live:on,off mirror:off,on audio:on,off" if ($hash->{SUBTYPE} eq "CAMERA");
  $list = "calibrate:noArg" if ($hash->{SUBTYPE} eq "TAG");
  if ($hash->{SUBTYPE} eq "THERMOSTAT")
  {
    $list = "setpoint_mode:off,hg,away,program,manual,max setpoint_temp:5.0,5.5,6.0,6.5,7.0,7.5,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0,28.5,29.0,29.5,30.0";
    $list = "setpoint_mode:off,hg,away,program,manual,max program:".$hash->{schedulenames}." setpoint_temp:5.0,5.5,6.0,6.5,7.0,7.5,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0,28.5,29.0,29.5,30.0" if(defined($hash->{schedulenames}));
  }

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
    return netatmo_setCameraSetting($hash, $cmd, $setting);
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
    return netatmo_setThermostatMode($hash,$setting,$duration);
    return undef;
  }
  elsif( $cmd eq "setpoint_temp" ) {
    my $setting = $parameters[0];
    my $duration = $parameters[1];
    return "You have to define a temperature" if(!defined($setting) || $setting eq "");
    return netatmo_setThermostatTemp($hash,$setting,$duration);
    return undef;
  }
  elsif( $cmd eq "program" ) {
    my $setting = $parameters[0];
    return "You have to define a program" if(!defined($setting) || $setting eq "");
    return netatmo_setThermostatProgram($hash,$setting);
    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
netatmo_getToken($)
{
  my ($hash) = @_;

  my($err,$data) = HttpUtils_BlockingGet({
    url => "https://api.netatmo.com/oauth2/token",
    timeout => 10,
    noshutdown => 1,
    data => {grant_type => 'password', client_id => $hash->{helper}{client_id},  client_secret=> $hash->{helper}{client_secret}, username => netatmo_decrypt($hash->{helper}{username}), password => netatmo_decrypt($hash->{helper}{password}), scope => 'read_station read_thermostat write_thermostat read_camera access_camera'},
  });

  netatmo_dispatch( {hash=>$hash,type=>'token'},$err,$data );
}


sub
netatmo_getAppToken($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $auth = "QXV0aG9yaXphdGlvbjogQmFzaWMgYm1GZlkyeHBaVzUwWDJsdmN6bzFObU5qTmpSaU56azBOak5oT1RrMU9HSTNOREF4TkRjeVpEbGxNREUxT0E9PQ==";
  $auth = decode_base64($auth);

  my($err,$data) = HttpUtils_BlockingGet({
    url => "https://app.netatmo.net/oauth2/token",
    method => "POST",
    timeout => 10,
    noshutdown => 1,
    header => "$auth",
    data => {app_identifier=>'com.netatmo.netatmo', grant_type => 'password', username => netatmo_decrypt($hash->{helper}{username}), password => netatmo_decrypt($hash->{helper}{password})},
  });


  netatmo_dispatch( {hash=>$hash,type=>'apptoken'},$err,$data );
}

sub
netatmo_refreshToken($;$)
{
  my ($hash,$nonblocking) = @_;

  if( !$hash->{access_token} ) {
    netatmo_getToken($hash);
    return undef;
  } elsif( !$nonblocking && defined($hash->{expires_at}) ) {
    my ($seconds) = gettimeofday();
    return undef if( $seconds < $hash->{expires_at} - 300 );
  }

  if( $nonblocking ) {
    HttpUtils_NonblockingGet({
      url => "https://api.netatmo.com/oauth2/token",
      timeout => 10,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', client_id => $hash->{helper}{client_id},  client_secret=> $hash->{helper}{client_secret}, refresh_token => $hash->{refresh_token}},
        hash => $hash,
        type => 'token',
        callback => \&netatmo_dispatch,
    });
  } else {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://api.netatmo.com/oauth2/token",
      timeout => 10,
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

  if( !$hash->{access_token_app} ) {
    Log3 $name, 2, "$name: missing app token!";

    netatmo_getAppToken($hash);
    return undef;
  } elsif( !$nonblocking && defined($hash->{expires_at_app}) ) {
    my ($seconds) = gettimeofday();
    return undef if( $seconds < $hash->{expires_at_app} - 300 );
  }

  my $auth = "QXV0aG9yaXphdGlvbjogQmFzaWMgYm1GZlkyeHBaVzUwWDJsdmN6bzFObU5qTmpSaU56azBOak5oT1RrMU9HSTNOREF4TkRjeVpEbGxNREUxT0E9PQ==";
  $auth = decode_base64($auth);

  if( $nonblocking ) {
    HttpUtils_NonblockingGet({
      url => "https://app.netatmo.net/oauth2/token",
      timeout => 10,
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
      timeout => 10,
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

  Log3 $name, 5, "$name: refreshing token";

  netatmo_refreshToken($hash, 1);
}

sub
netatmo_refreshAppTokenTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: refreshing app token";

  netatmo_refreshAppToken($hash, 1);
}

sub
netatmo_connect($)
{
  my ($hash) = @_;

  netatmo_getToken($hash);
  #netatmo_getAppToken($hash);

  InternalTimer(gettimeofday()+60, "netatmo_poll", $hash, 0);

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

  my $device;
  if( $hash->{Module} ) {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Module} );
  } else {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Device} );
  }
  $hash->{stationName} = encode_utf8($device->{station_name}) if( $device->{station_name} );
  $hash->{moduleName} = encode_utf8($device->{module_name}) if( $device->{module_name} );

  $hash->{model} = $device->{type};
  $hash->{firmware} = $device->{firmware};

  $hash->{co2_calibrating} = $device->{co2_calibrating} if(defined($device->{co2_calibrating}));
  $hash->{last_upgrade} = FmtDateTime($device->{last_upgrade}) if(defined($device->{last_upgrade}));
  $hash->{date_setup} = FmtDateTime($device->{date_setup}) if(defined($device->{date_setup}));
  $hash->{last_setup} = FmtDateTime($device->{last_setup}) if(defined($device->{last_setup}));
  $hash->{last_status_store} = FmtDateTime($device->{last_status_store}) if(defined($device->{last_status_store}));
  $hash->{last_message} = FmtDateTime($device->{last_message}) if(defined($device->{last_message}));
  $hash->{last_seen} = FmtDateTime($device->{last_seen}) if(defined($device->{last_seen}));
  $hash->{wifi_status} = $device->{wifi_status} if(defined($device->{wifi_status}));
  $hash->{rf_status} = $device->{rf_status} if(defined($device->{rf_status}));
  #$hash->{battery_percent} = $device->{battery_percent} if(defined($device->{battery_percent}));
  $hash->{battery_vp} = $device->{battery_vp} if(defined($device->{battery_vp}));

  if( $device->{place} ) {
    $hash->{country} = $device->{place}{country};
    $hash->{bssid} = $device->{place}{bssid} if(defined($device->{place}{bssid}));
    $hash->{altitude} = $device->{place}{altitude};
    $hash->{city} = encode_utf8($device->{place}{geoip_city}) if(defined($device->{place}{geoip_city}));
    $hash->{city} = encode_utf8($device->{place}{city}) if(defined($device->{place}{city}));;
    $hash->{location} = $device->{place}{location}[1] .",". $device->{place}{location}[0];
  }

  readingsSingleUpdate($hash, "battery", ($device->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($device->{battery_percent}));
  readingsSingleUpdate($hash, "battery_percent", $device->{battery_percent}, 1) if(defined($device->{battery_percent}));

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

  $attr{$name}{stateFormat} = $state_format if( !defined($attr{$name}{stateFormat}) && defined($state_format) );

  return undef if(AttrVal($name,"disable",0) eq "1");

  InternalTimer(gettimeofday()+60, "netatmo_poll", $hash, 0);
  #netatmo_poll($hash);

}

sub
netatmo_getDevices($;$)
{
  my ($hash,$blocking) = @_;

  netatmo_refreshToken($hash);

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://api.netatmo.com/api/getstationsdata",
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'devicelist'},$err,$data );


    return $hash->{helper}{devices};
  } else {
    HttpUtils_NonblockingGet({
      url => "https://api.netatmo.com/api/getstationsdata",
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

  netatmo_refreshToken($hash);

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://api.netatmo.com/api/gethomedata",
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'homelist'},$err,$data );

    return $hash->{helper}{homes};
  } else {
    HttpUtils_NonblockingGet({
      url => "https://api.netatmo.com/api/gethomedata",
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

  netatmo_refreshToken($hash);

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://api.netatmo.com/api/getthermostatsdata",
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'thermostatlist'},$err,$data );


    return $hash->{helper}{thermostats};
  } else {
    HttpUtils_NonblockingGet({
      url => "https://api.netatmo.com/api/getthermostatsdata",
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, },
      hash => $hash,
      type => 'thermostatlist',
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
  netatmo_refreshToken($iohash);

  my $pingurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($pingurl));

  $pingurl .= "/command/ping";

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => $pingurl,
      noshutdown => 1,
      data => { access_token => $iohash->{access_token}, },
    });
    netatmo_dispatch( {hash=>$hash,type=>'cameraping'},$err,$data );


    return undef;
  } else {
    HttpUtils_NonblockingGet({
      url => $pingurl,
      noshutdown => 1,
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

  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash);

  my $cmdurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($cmdurl));

  my $quality = AttrVal($name,"videoquality","medium");

  $cmdurl .= "/vod/".$videoid."/files/".$quality."/index".$local.".m3u8";

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
netatmo_getCameraLive($;$)
{
  my ($hash,$local) = @_;
  my $name = $hash->{NAME};

  $local = ($local eq "video_local" ? "_local" : "");

  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash);

  my $cmdurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($cmdurl));

  my $quality = AttrVal($name,"videoquality","medium");

  $cmdurl .= "/live/files/".$quality."/index".$local.".m3u8";

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

  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash);

  my $cmdurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($cmdurl));

  $cmdurl .= "/live/snapshot_720.jpg";

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
netatmo_getEvents($)
{
  my ($hash) = @_;

  my $iohash = $hash->{IODev};
  netatmo_refreshToken($iohash);

  HttpUtils_NonblockingGet({
    url => "https://api.netatmo.com/api/getnextevents",
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
  #Log3 $name, 5, "$name getpublicdata_in: $lat1,$lon1,$lat2,$lon2";

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

  Log3 $name, 4, "$name getpublicdata: $lat_ne,$lon_ne / $lat_sw,$lon_sw";

  netatmo_refreshToken($iohash);

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "https://api.netatmo.com/api/getpublicdata",
      noshutdown => 1,
      data => { access_token => $iohash->{access_token}, lat_ne => $lat_ne, lon_ne => $lon_ne, lat_sw => $lat_sw, lon_sw => $lon_sw },
    });

      return netatmo_dispatch( {hash=>$hash,type=>'publicdata'},$err,$data );
  } else {
    HttpUtils_NonblockingGet({
      url => "https://api.netatmo.com/api/getpublicdata",
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

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  netatmo_getDevices($hash,1) if( !$hash->{helper}{devices} );

  foreach my $device (@{$hash->{helper}{devices}}) {
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

  my $iohash = $hash->{IODev};
  $type = $hash->{dataTypes} if( !$type );
  $type = "Temperature,CO2,Humidity,Noise,Pressure,Rain,WindStrength,WindAngle,GustStrength,GustAngle,Sp_Temperature,BoilerOn,BoilerOff" if( !$type );
  $type = "WindAngle,WindStrength,GustStrength,GustAngle" if ($type eq "Wind");
  netatmo_refreshToken( $iohash );

  my %data = (access_token => $iohash->{access_token}, device_id => $id, scale => "max", type => $type);
  $data{"module_id"} = $module if( $module );

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  $data{"date_begin"} = $lastupdate if( defined($lastupdate) );

  Log3 $name, 4, "$name: request readings type: " . $type;

  HttpUtils_NonblockingGet({
    url => "https://api.netatmo.com/api/getmeasure",
    timeout => 10,
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
  netatmo_refreshToken( $iohash );

  my %data = (access_token => $iohash->{access_token}, home_id => $hash->{Home});

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  #$data{"size"} = 1;#$lastupdate if( defined($lastupdate) );

  HttpUtils_NonblockingGet({
    url => "https://api.netatmo.com/api/gethomedata",
    timeout => 10,
    noshutdown => 1,
    data => \%data,
    hash => $hash,
    type => 'gethomedata',
    callback => \&netatmo_dispatch,
  });

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "netatmo_poll", $hash, 0);

}

sub
netatmo_requestHomeReadings($@)
{
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash );

  my %data = (access_token => $iohash->{access_token}, home_id => $id, size => 50);

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  #$data{"size"} = 1;#$lastupdate if( defined($lastupdate) );

  HttpUtils_NonblockingGet({
    url => "https://api.netatmo.com/api/gethomedata",
    timeout => 10,
    noshutdown => 1,
    data => \%data,
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

  Log3 $name, 4, "$name: reqthermreadings ".$id;

  my $iohash = $hash->{IODev};
  netatmo_refreshToken( $iohash );

  my %data = (access_token => $iohash->{access_token}, device_id => $id);

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  #$data{"size"} = 1;#$lastupdate if( defined($lastupdate) );

  HttpUtils_NonblockingGet({
    url => "https://api.netatmo.com/api/getthermostatsdata",
    timeout => 10,
    noshutdown => 1,
    data => \%data,
    hash => $hash,
    type => 'getthermostatsdata',
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
  netatmo_refreshToken( $iohash );

  my %data = (access_token => $iohash->{access_token}, home_id => $hash->{Home}, person_id => $hash->{Person}, offset => '20');

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );

  HttpUtils_NonblockingGet({
    url => "https://api.netatmo.com/api/getlasteventof",
    timeout => 10,
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
  netatmo_refreshAppToken( $iohash );

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

  Log3 $name, 5, "$name: setpersons ".$urlstatus;


  HttpUtils_NonblockingGet({
    url => "https://app.netatmo.net/api/setpersons".$urlstatus,
    timeout => 10,
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
netatmo_setCamera($$$)
{
  my ($hash,$status,$pin) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_refreshAppToken( $iohash );


  my $commandurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/changestatus?status=$status&pin=$pin";

  Log3 $name, 4, "$name: setcam ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      noshutdown => 1,
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

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  #netatmo_pingCamera( $hash );


  my $commandurl = ReadingsVal( $name, "vpn_url", undef );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/changesetting?$setting=$newvalue";

  Log3 $name, 5, "$name: setcamsetting ".$commandurl;

  HttpUtils_NonblockingGet({
      url => $commandurl,
      noshutdown => 1,
      hash => $hash,
      type => 'camerastatus',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setTagCalibration($$)
{
  my ($hash,$setting) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );
  return undef if( !defined($hash->{Camera}) );

  my $iohash = $hash->{IODev};
  my $camerahash = $modules{$hash->{TYPE}}{defptr}{"C$hash->{Camera}"};

  return undef if( !defined($camerahash));

  #netatmo_pingCamera( $hash );


  my $commandurl = ReadingsVal( $camerahash->{NAME}, "vpn_url", undef );
  return undef if(!defined($commandurl));

  $commandurl .= "/command/dtg_cal?id=".$hash->{Tag};

  Log3 $name, 5, "$name: calibrating";

  HttpUtils_NonblockingGet({
      url => $commandurl,
      noshutdown => 1,
      hash => $hash,
      type => 'tagstatus',
      callback => \&netatmo_dispatch,
    });


}

sub
netatmo_setThermostatMode($$;$$)
{
  my ($hash,$set,$duration) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  netatmo_getToken( $iohash );

  my %data;
  %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, setpoint_mode => $set);

  if(defined($duration) || $set eq "max")
  {
    $duration = AttrVal($name,"setpoint_duration",60) if(!defined($duration));
    my $endpoint = time + (60 * $duration);
    %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, setpoint_mode => $set, setpoint_endtime => $endpoint);
  }


  Log3 $name, 4, "$name: setmode ".$set;

  HttpUtils_NonblockingGet({
      url => 'https://api.netatmo.com/api/setthermpoint',
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
  netatmo_getToken( $iohash );

  $duration = AttrVal($name,"setpoint_duration",60) if(!defined($duration));
  my $endpoint = time + (60 * $duration);

  my %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, setpoint_mode => 'manual', setpoint_temp => $set, setpoint_endtime => $endpoint);

  Log3 $name, 4, "$name: settemp ".$set;

  HttpUtils_NonblockingGet({
      url => 'https://api.netatmo.com/api/setthermpoint',
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
  netatmo_getToken( $iohash );

  my $schedule_id = 0;
  foreach my $scheduledata ( @{$hash->{schedules}})
  {
    $schedule_id = @{$scheduledata}[1] if($set eq @{$scheduledata}[0]);
  }

  my %data = (access_token => $iohash->{access_token}, device_id => $hash->{Relay}, module_id => $hash->{Thermostat}, schedule_id => $schedule_id);

  Log3 $name, 5, "$name: setprogram $set ($schedule_id)";

  HttpUtils_NonblockingGet({
      url => 'https://api.netatmo.com/api/switchschedule',
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


  return undef if(AttrVal($name,"disable",0) eq "1");

  # my $resolve = inet_aton("api.netatmo.com");
  # if(!defined($resolve))
  # {
  #   Log3 $name, 1, "$name: DNS error on poll";
  #   InternalTimer( gettimeofday() + 1800, "netatmo_poll", $hash, 0);
  #   return undef;
  # }

  Log3 $name, 4, "$name: poll $hash->{SUBTYPE} ";


  if( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    netatmo_pollGlobal($hash);
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
  } elsif( $hash->{SUBTYPE} eq "PERSON" ) {
    netatmo_pollPerson($hash);
  } else {
    return undef;
  }

  if( defined($hash->{helper}{update_count}) && $hash->{helper}{update_count} > 1024 ) {
    InternalTimer(gettimeofday()+30, "netatmo_poll", $hash, 0);
  } else {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "netatmo_poll", $hash, 0);
  }
}

sub
netatmo_dispatch($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: dispatch $param->{type}";

  $hash->{openRequests} -= 1 if( $param->{type} eq 'getmeasure' );

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
  } elsif( $data ) {

    $data =~ s/\n//g;
    if( $data !~ m/^{.*}$/ ) {
      Log3 $name, 2, "$name: invalid json detected: \n$data";
      $hash->{status} = "error";
      return undef;
    }

    my $json;
    $json = JSON->new->utf8(0)->decode($data);

    Log3 "unknown", 4, "unknown ".Dumper($hash) if(!defined($name));
    Log3 $name, 4, "$name: dispatch return: ".$param->{type};
    Log3 $name, 6, Dumper($json);

    if( $json->{error} ) {
      $hash->{lastError} = $json->{error};
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
    } elsif( $param->{type} eq 'tagstatus' ) {
      netatmo_parseTagStatus($hash,$json);
    } elsif( $param->{type} eq 'cameravideo' ) {
      netatmo_parseCameraVideo($hash,$json);
    } elsif( $param->{type} =~ /setpersonsstatus_/ ) {
      netatmo_parsePersonsStatus($hash,$json,$param->{type});
    } elsif( $param->{type} eq 'thermostatlist' ) {
      netatmo_parseThermostatList($hash,$json);
    } elsif( $param->{type} eq 'getthermostatsdata' ) {
      netatmo_parseThermostatReadings($hash,$json);
    } elsif( $param->{type} eq 'setthermostat' ) {
      netatmo_parseThermostatStatus($hash,$json);
    } elsif( $param->{type} eq 'getpersondata' ) {
      netatmo_parsePersonReadings($hash,$json);
    } elsif( $param->{type} eq 'publicdata' ) {
      return netatmo_parsePublic($hash,$json);
    } elsif( $param->{type} eq 'address' ) {
      return netatmo_parseAddress($hash,$json);
    } elsif( $param->{type} eq 'latlng' ) {
      return netatmo_parseLatLng($hash,$json);
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

  #Log3 $name, 1, "$name: set '$param' ".Dumper($json);

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
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
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
      $cmdret= CommandAttr(undef,"$devname event-on-change-reading .*");
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
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
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
        $tagcmdret= CommandAttr(undef,"$tagdevname event-on-change-reading .*");

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
      $cmdret= CommandAttr(undef,"$devname event-on-change-reading .*");

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
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
    }
  }

  my $autocreated = 0;

  my $devices = $hash->{helper}{thermostats};
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"R$device->{_id}"}) ) {
      Log3 $name, 4, "$name: relay '$device->{_id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"T$device->{_id}"}) ) {
      Log3 $name, 4, "$name: thermostat '$device->{_id}' already defined";
      next;
    }
    if(AttrVal($name,"ignored_device_ids","") =~ /$device->{_id}/) {
      Log3 $name, 4, "$name: '$device->{_id}' ignored for autocreate";
      next;
    }

    my $id = $device->{_id};
    my $devname = "netatmo_R". $id;
    $devname =~ s/:/_/g;
    my $define= "$devname netatmo RELAY $id";
    if( $device->{main_device} ) {
      $devname = "netatmo_T". $id;
      $devname =~ s/:/_/g;
      $define= "$devname netatmo THERMOSTAT $device->{main_device} $id";
    }

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($device->{station_name})) if( defined($device->{station_name}) );
      $cmdret= CommandAttr(undef,"$devname alias ".encode_utf8($device->{module_name})) if( defined($device->{module_name}) );
      $cmdret= CommandAttr(undef,"$devname room netatmo");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname devStateIcon .*:no-icon");
      $cmdret= CommandAttr(undef,"$devname event-on-change-reading .*");
      $cmdret= CommandAttr(undef,"$devname stateFormat setpoint|temperature");
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

  my $had_token = $hash->{access_token};

  $hash->{access_token} = $json->{access_token};
  $hash->{refresh_token} = $json->{refresh_token};

  if( $hash->{access_token} ) {
    $hash->{STATE} = "Connected";

    ($hash->{expires_at}) = gettimeofday();
    $hash->{expires_at} += $json->{expires_in};

    netatmo_getDevices($hash) if( !$had_token );

    InternalTimer(gettimeofday()+$json->{expires_in}*3/4, "netatmo_refreshTokenTimer", $hash, 0);
  } else {
    $hash->{STATE} = "Error" if( !$hash->{access_token} );
    InternalTimer(gettimeofday()+60, "netatmo_refreshTokenTimer", $hash, 0);
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

    ($hash->{expires_at_app}) = gettimeofday();
    $hash->{expires_at_app} += $json->{expires_in};

     InternalTimer(gettimeofday()+$json->{expires_in}*3/4, "netatmo_refreshAppTokenTimer", $hash, 0);
   } else {
     $hash->{STATE} = "Error" if( !$hash->{access_token_app} );
     Log3 $name, 1, "$name: app token error ".Dumper($json);
     InternalTimer(gettimeofday()+60, "netatmo_refreshAppTokenTimer", $hash, 0);
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
    push( @homes, $home );
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
  foreach my $device (@{$json->{body}{devices}}) {
    push( @devices, $device );


    foreach my $module (@{$device->{modules}}) {
      $module->{main_device} = $device->{_id};
      push( @devices, $module );


    }
  }

  $hash->{helper}{thermostats} = \@devices;

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
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );
    my @r = ();
    my $readings = \@r;
    $readings = $hash->{readings} if( defined($hash->{readings}) );
    if( $hash->{status} eq "ok" ) {

      if(scalar(@{$json->{body}}) == 0)
      {
        $hash->{status} = "no data";
      }

      foreach my $values ( @{$json->{body}}) {
        my $time = $values->{beg_time};
        my $step_time = $values->{step_time};

        foreach my $value (@{$values->{value}}) {
          my $i = 0;
          foreach my $reading (@{$value}) {

            #my $rname = $hash->{helper}{readingNames}[$i++];
            my $rname = lc($reading_names->[$i++]);

            if( !defined($reading) )
            {
              next;
            }
            if(lc($requested) =~ /wind/ && ($rname eq "temperature" || $rname eq "humidity"))
            {
              next;# if($reading == 0);
              #Log3 $name, 1, "$name netatmo - wind sensor $rname reading: $reading ($time)";
            }


            if(($rname eq "noise" && $reading > 150) || ($rname eq "temperature" && $reading > 60) || ($rname eq "humidity" && $reading > 100) || ($rname eq "pressure" && $reading < 500))
            {
              Log3 $name, 1, "$name netatmo - invalid reading: $rname: ".Dumper($reading)." \n    ".Dumper($reading_names);
             next;
            }


            push(@{$readings}, [$time, $rname, $reading]);
          }

          $time += $step_time if( $step_time );
        }
      }

      if( $hash->{openRequests} > 1 ) {
        $hash->{readings} = $readings;
      } else {
        my ($seconds,undef) = netatmo_updateReadings( $hash, $readings );
        $hash->{LAST_POLL} = FmtDateTime( $seconds );
        delete $hash->{readings};
      }
    }
  }
  else
  {
    $hash->{status} = "error";
  }
}


sub
netatmo_parseGlobal($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseglobal";

  if( $json )
  {
    Log3 $name, 6, "$name: parseglobaldata".Dumper($json);

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

        Log3 $name, 6, "$name: device " . "D$devicedata->{_id} " .Dumper($devicedata);

        my $device = $modules{$hash->{TYPE}}{defptr}{"D$devicedata->{_id}"};
        next if (!defined($device));

        #Log3 $name, 4, "$name: device " . "D$devicedata->{_id} found";

        if(defined($devicedata->{dashboard_data}{AbsolutePressure}))
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

        $device->{co2_calibrating} = $devicedata->{co2_calibrating} if(defined($devicedata->{co2_calibrating}));
        $device->{last_status_store} = FmtDateTime($devicedata->{last_status_store}) if(defined($devicedata->{last_status_store}));
        $device->{last_message} = FmtDateTime($devicedata->{last_message}) if(defined($devicedata->{last_message}));
        $device->{last_seen} = FmtDateTime($devicedata->{last_seen}) if(defined($devicedata->{last_seen}));
        $device->{wifi_status} = $devicedata->{wifi_status} if(defined($devicedata->{wifi_status}));
        $device->{rf_status} = $devicedata->{rf_status} if(defined($devicedata->{rf_status}));
        #$device->{battery_percent} = $devicedata->{battery_percent} if(defined($devicedata->{battery_percent}));
        $device->{battery_vp} = $devicedata->{battery_vp} if(defined($devicedata->{battery_vp}));

        readingsSingleUpdate($device, "battery", ($devicedata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($devicedata->{battery_percent}));
        readingsSingleUpdate($device, "battery_percent", $devicedata->{battery_percent}, 1) if(defined($devicedata->{battery_percent}));

        if(defined($devicedata->{modules}))
        {
          foreach my $moduledata ( @{$devicedata->{modules}})
          {

            Log3 $name, 6, "$name: module "."M$moduledata->{_id} ".Dumper($moduledata);

            my $module = $modules{$hash->{TYPE}}{defptr}{"M$moduledata->{_id}"};
            next if (!defined($module));

            #Log3 $name, 1, "$name: module "."M$moduledata->{_id} found";


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
            $module->{last_message} = FmtDateTime($moduledata->{last_message}) if(defined($moduledata->{last_message}));
            $module->{last_seen} = FmtDateTime($moduledata->{last_seen}) if(defined($moduledata->{last_seen}));
            $module->{wifi_status} = $moduledata->{wifi_status} if(defined($moduledata->{wifi_status}));
            $module->{rf_status} = $moduledata->{rf_status} if(defined($moduledata->{rf_status}));
            #$module->{battery_percent} = $moduledata->{battery_percent} if(defined($moduledata->{battery_percent}));
            $module->{battery_vp} = $moduledata->{battery_vp} if(defined($moduledata->{battery_vp}));

            readingsSingleUpdate($module, "battery", ($moduledata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($moduledata->{battery_percent}));
            readingsSingleUpdate($module, "battery_percent", $moduledata->{battery_percent}, 1) if(defined($moduledata->{battery_percent}));


          }#foreach module
        }#defined modules
      }#foreach devices

    }#ok
  }#json
  else
  {
    $hash->{status} = "error";
  }

return undef;

}


sub
netatmo_parseForecast($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parseforecast";

  if( $json )
  {
    Log3 $name, 5, "$name: parseforecastdata".Dumper($json);

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
            readingsBulkUpdate( $hash, "fc".$i."_day", $forecastdata->{day_locale}, 1 );
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

return undef;

}

sub
netatmo_parseHomeReadings($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parsehomereadings";

  if( $json ) {

    $hash->{status} = $json->{status};
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

        if( $homedata->{place} ) {
          $hash->{country} = $homedata->{place}{country} if(defined($homedata->{place}{country}));
          $hash->{bssid} = $homedata->{place}{bssid} if(defined($homedata->{place}{bssid}));
          $hash->{altitude} = $homedata->{place}{altitude} if(defined($homedata->{place}{altitude}));
          $hash->{city} = encode_utf8($homedata->{place}{geoip_city}) if(defined($homedata->{place}{geoip_city}));
          $hash->{city} = encode_utf8($homedata->{place}{city}) if(defined($homedata->{place}{city}));;
          $hash->{location} = $homedata->{place}{location}[1] .",". $homedata->{place}{location}[0] if(defined($homedata->{place}{location}));
          $hash->{timezone} = $homedata->{place}{timezone} if(defined($homedata->{place}{timezone}));
        }

        if(defined($homedata->{persons}))
        {
          foreach my $persondata ( @{$homedata->{persons}})
          {
            #Log3 $name, 1, "$name: person: ".Dumper($persondata);

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
            #Log3 $name, 1, "$name: camera: ".Dumper($cameradata);

            my $camera = $modules{$hash->{TYPE}}{defptr}{"C$cameradata->{id}"};
            next if (!defined($camera));

            readingsSingleUpdate($camera, "name", encode_utf8($cameradata->{name}), 1) if(defined($cameradata->{name}));
            readingsSingleUpdate($camera, "status", $cameradata->{status}, 1) if(defined($cameradata->{status}));
            #$camera->{STATE} = ($cameradata->{status} eq "on") ? "online" : "offline";
            readingsSingleUpdate($camera, "sd_status", $cameradata->{sd_status}, 0) if(defined($cameradata->{sd_status}));
            readingsSingleUpdate($camera, "alim_status", $cameradata->{alim_status}, 0) if(defined($cameradata->{alim_status}));
            readingsSingleUpdate($camera, "is_local", $cameradata->{is_local}, 1) if(defined($cameradata->{is_local}));
            readingsSingleUpdate($camera, "vpn_url", $cameradata->{vpn_url}, 1) if(defined($cameradata->{vpn_url}));
            $camera->{pin} = undef if($cameradata->{status} eq "on");
            
            foreach my $tagdata ( @{$cameradata->{modules}})
            {
              my $tag = $modules{$hash->{TYPE}}{defptr}{"G$tagdata->{id}"};
              next if (!defined($tag));

              readingsSingleUpdate($tag, "name", encode_utf8($tagdata->{name}), 1) if(defined($tagdata->{name}));
              readingsSingleUpdate($tag, "status", $tagdata->{status}, 1) if(defined($tagdata->{status}));
              readingsSingleUpdate($tag, "category", $tagdata->{category}, 1) if(defined($tagdata->{category}));

              $tag->{model} = $tagdata->{type};
              $tag->{last_activity} = FmtDateTime($tagdata->{last_activity}) if(defined($tagdata->{last_activity}));
              $tag->{rf} = $tagdata->{rf};

              readingsSingleUpdate($tag, "battery", ($tagdata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($tagdata->{battery_percent}));
              readingsSingleUpdate($tag, "battery_percent", $tagdata->{battery_percent}, 1) if(defined($tagdata->{battery_percent}));

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

            my $eventmessage = $eventdata->{message};
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

            my $camera = $modules{$hash->{TYPE}}{defptr}{"C$eventdata->{camera_id}"};
            my $tag = $modules{$hash->{TYPE}}{defptr}{"G$eventdata->{module_id}"} if(defined($eventdata->{module_id}));
            my $person = $modules{$hash->{TYPE}}{defptr}{"P$eventdata->{person_id}"} if(defined($eventdata->{person_id}));
            if (defined($camera))
            {

              my $lastupdate = ReadingsVal( $camera->{NAME}, ".lastupdate", 0 );
              next if($eventdata->{time} <= $lastupdate);
              readingsSingleUpdate($camera, ".lastupdate", $eventdata->{time}, 0);

              if(defined($eventdata->{message}))
              {
                my $cameraname = ReadingsVal( $camera->{NAME}, "name", "Welcome" );
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

              if(defined($eventdata->{snapshot}))
              {
                readingsBeginUpdate($camera);
                $camera->{".updateTimestamp"} = FmtDateTime($eventdata->{time});
                readingsBulkUpdate( $camera, "last_snapshot", "https://api.netatmo.com/api/getcamerapicture?image_id=".$eventdata->{snapshot}{id}."&key=".$eventdata->{snapshot}{key}, 1 );
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


        Log3 $name, 5, "$name: home readings: ".Dumper($homedata);

        my $time = $homedata->{time_server};


      }


    }
    else
    {
      $hash->{STATE} = "Error";
    }
  }
  else
  {
    $hash->{status} = "error";
  }


}

sub
netatmo_parseCameraPing($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: pingcamera ";

  if( $json ) {

    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );

    readingsSingleUpdate($hash, "local_url", $json->{local_url}, 1) if(defined($json->{local_url}));

  }
  else
  {
    $hash->{status} = "error";
  }
}

sub
netatmo_parseCameraStatus($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: setcamerastatus ";
  my $home = $modules{$hash->{TYPE}}{defptr}{"H$hash->{Home}"};

  if( $json ) {

    $hash->{status} = $json->{error}{message} if( $json->{error} );
    InternalTimer( gettimeofday() + 10, "netatmo_pollHome", $home, 0);
  }
  else{
    netatmo_pollHome($home);
  }
}


sub
netatmo_parseTagStatus($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: tagstatus ";

  if( $json ) {
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    readingsSingleUpdate($hash, "status", "calibrating", 1);
  }
  else
  {
    $hash->{status} = "error";
  }
}


sub
netatmo_parseCameraVideo($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};


  if( $json ) {

    Log3 $name, 6, "$name: camera video: ".Dumper($json);

    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );

    readingsSingleUpdate($hash, "local_url", $json->{local_url}, 1) if(defined($json->{local_url}));

  }
  else
  {
    $hash->{status} = "error";
  }
}

sub
netatmo_parsePersonReadings($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};



    Log3 $name, 4, "$name: parsepersonreadings";

    if( $json ) {

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
      else
      {
        $hash->{STATE} = "Error";
      }
    }
    else
    {
      $hash->{status} = "error";
    }


}


sub
netatmo_parseThermostatReadings($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  #Log3 $name, 4, "$name: parsethermostatreadings ".Dumper($json);

  if( $json ) {

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
        $hash->{STATE} = "Connected";

        readingsSingleUpdate($hash, "name", encode_utf8($devicedata->{station_name}), 1) if(defined($devicedata->{station_name}));

        $hash->{stationName} = encode_utf8($devicedata->{station_name}) if( $devicedata->{station_name} );
        $hash->{moduleName} = encode_utf8($devicedata->{module_name}) if( $devicedata->{module_name} );

        $hash->{model} = $devicedata->{type};
        $hash->{firmware} = $devicedata->{firmware};

        $hash->{last_upgrade} = FmtDateTime($devicedata->{last_upgrade}) if(defined($devicedata->{last_upgrade}));
        $hash->{date_setup} = FmtDateTime($devicedata->{date_setup}) if(defined($devicedata->{date_setup}));
        $hash->{last_setup} = FmtDateTime($devicedata->{last_setup}) if(defined($devicedata->{last_setup}));
        $hash->{last_status_store} = FmtDateTime($devicedata->{last_status_store}) if(defined($devicedata->{last_status_store}));
        $hash->{last_message} = FmtDateTime($devicedata->{last_message}) if(defined($devicedata->{last_message}));
        $hash->{last_seen} = FmtDateTime($devicedata->{last_seen}) if(defined($devicedata->{last_seen}));
        $hash->{last_plug_seen} = FmtDateTime($devicedata->{last_plug_seen}) if(defined($devicedata->{last_plug_seen}));
        $hash->{last_therm_seen} = FmtDateTime($devicedata->{last_therm_seen}) if(defined($devicedata->{last_therm_seen}));
        $hash->{wifi_status} = $devicedata->{wifi_status} if(defined($devicedata->{wifi_status}));
        $hash->{rf_status} = $devicedata->{rf_status} if(defined($devicedata->{rf_status}));
        #$hash->{battery_percent} = $devicedata->{battery_percent} if(defined($devicedata->{battery_percent}));
        $hash->{battery_vp} = $devicedata->{battery_vp} if(defined($devicedata->{battery_vp}));
        $hash->{therm_orientation} = $devicedata->{therm_orientation} if(defined($devicedata->{therm_orientation}));
        $hash->{therm_relay_cmd} = $devicedata->{therm_relay_cmd} if(defined($devicedata->{therm_relay_cmd}));
        $hash->{udp_conn} = $devicedata->{udp_conn} if(defined($devicedata->{udp_conn}));
        $hash->{plug_connected_boiler} = $devicedata->{plug_connected_boiler} if(defined($devicedata->{plug_connected_boiler}));
        $hash->{syncing} = $devicedata->{syncing} if(defined($devicedata->{syncing}));

        if( $devicedata->{place} ) {
          $hash->{country} = $devicedata->{place}{country};
          $hash->{bssid} = $devicedata->{place}{bssid} if(defined($devicedata->{place}{bssid}));
          $hash->{altitude} = $devicedata->{place}{altitude} if(defined($devicedata->{place}{altitude}));
          $hash->{city} = encode_utf8($devicedata->{place}{geoip_city}) if(defined($devicedata->{place}{geoip_city}));
          $hash->{city} = encode_utf8($devicedata->{place}{city}) if(defined($devicedata->{place}{city}));;
          $hash->{location} = $devicedata->{place}{location}[1] .",". $devicedata->{place}{location}[0];
          $hash->{timezone} = $devicedata->{place}{timezone};
        }

        readingsSingleUpdate($hash, "battery", ($devicedata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($devicedata->{battery_percent}));
        readingsSingleUpdate($hash, "battery_percent", $devicedata->{battery_percent}, 1) if(defined($devicedata->{battery_percent}));


        if(defined($devicedata->{modules}))
        {
          foreach my $moduledata ( @{$devicedata->{modules}})
          {
            my $module = $modules{$hash->{TYPE}}{defptr}{"T$moduledata->{_id}"};
            next if (!defined($module));

            $module->{stationName} = encode_utf8($moduledata->{station_name}) if( $moduledata->{station_name} );
            $module->{moduleName} = encode_utf8($moduledata->{module_name}) if( $moduledata->{module_name} );

            $module->{model} = $moduledata->{type};
            $module->{firmware} = $moduledata->{firmware};

            $module->{last_upgrade} = FmtDateTime($moduledata->{last_upgrade}) if(defined($moduledata->{last_upgrade}));
            $module->{date_setup} = FmtDateTime($moduledata->{date_setup}) if(defined($moduledata->{date_setup}));
            $module->{last_setup} = FmtDateTime($moduledata->{last_setup}) if(defined($moduledata->{last_setup}));
            $module->{last_status_store} = FmtDateTime($moduledata->{last_status_store}) if(defined($moduledata->{last_status_store}));
            $module->{last_message} = FmtDateTime($moduledata->{last_message}) if(defined($moduledata->{last_message}));
            $module->{last_seen} = FmtDateTime($moduledata->{last_seen}) if(defined($moduledata->{last_seen}));
            $module->{last_plug_seen} = FmtDateTime($moduledata->{last_plug_seen}) if(defined($moduledata->{last_plug_seen}));
            $module->{last_therm_seen} = FmtDateTime($moduledata->{last_therm_seen}) if(defined($moduledata->{last_therm_seen}));
            $module->{wifi_status} = $moduledata->{wifi_status} if(defined($moduledata->{wifi_status}));
            $module->{rf_status} = $moduledata->{rf_status} if(defined($moduledata->{rf_status}));
            #$module->{battery_percent} = $moduledata->{battery_percent} if(defined($moduledata->{battery_percent}));
            $module->{battery_vp} = $moduledata->{battery_vp} if(defined($moduledata->{battery_vp}));
            $module->{therm_orientation} = $moduledata->{therm_orientation} if(defined($moduledata->{therm_orientation}));
            #$module->{therm_relay_cmd} = $moduledata->{therm_relay_cmd} if(defined($moduledata->{therm_relay_cmd}));
            $module->{udp_conn} = $moduledata->{udp_conn} if(defined($moduledata->{udp_conn}));
            $module->{plug_connected_boiler} = $moduledata->{plug_connected_boiler} if(defined($moduledata->{plug_connected_boiler}));
            $module->{syncing} = $moduledata->{syncing} if(defined($moduledata->{syncing}));

            if( $moduledata->{place} ) {
              $module->{country} = $moduledata->{place}{country};
              $module->{bssid} = $moduledata->{place}{bssid} if(defined($moduledata->{place}{bssid}));
              $module->{altitude} = $moduledata->{place}{altitude} if(defined($moduledata->{place}{altitude}));
              $module->{city} = encode_utf8($moduledata->{place}{geoip_city}) if(defined($moduledata->{place}{geoip_city}));
              $module->{city} = encode_utf8($moduledata->{place}{city}) if(defined($moduledata->{place}{city}));;
              $module->{location} = $moduledata->{place}{location}[1] .",". $moduledata->{place}{location}[0];
              $module->{timezone} = $moduledata->{place}{timezone};
            }

            readingsSingleUpdate($module, "battery", ($moduledata->{battery_percent} > 20) ? "ok" : "low", 1) if(defined($moduledata->{battery_percent}));
            readingsSingleUpdate($module, "battery_percent", $moduledata->{battery_percent}, 1) if(defined($moduledata->{battery_percent}));
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
              readingsBulkUpdate( $module, "setpoint_temp", $moduledata->{measured}{setpoint_temp}, 1 );
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



        Log3 $name, 6, "$name: thermostat readings: ".Dumper($devicedata);

        #my $time = $devicedata->{time_server};

      }


    }
    else
    {
      $hash->{STATE} = "Error";
    }
  }
  else
  {
    $hash->{status} = "error";
  }


}

sub
netatmo_parseThermostatStatus($$;$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: setthermostat ";
  my $thermostat = $modules{$hash->{TYPE}}{defptr}{"T$hash->{Thermostat}"};

  if( $json ) {

    $hash->{status} = $json->{error}{message} if( $json->{error} );
    InternalTimer( gettimeofday() + 15, "netatmo_pollRelay", $thermostat, 0);
  }
  else{
    netatmo_pollRelay($thermostat);
  }
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
        my @timestamps_temperature = ();
        my @timestamps_pressure = ();
        my @timestamps_rain = ();
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
        @timestamps_temperature = sort {$a <=> $b} @timestamps_temperature;
        @timestamps_pressure = sort {$a <=> $b} @timestamps_pressure;
        @timestamps_rain = sort {$a <=> $b} @timestamps_rain;
        @readings_altitude = sort {$a <=> $b} @readings_altitude;
        @readings_latitude = sort {$a <=> $b} @readings_latitude;
        @readings_longitude = sort {$a <=> $b} @readings_longitude;

        for (my $i=0;$i<scalar(@readings_temperature)/10;$i++)
        {
          pop @readings_temperature;
          pop @readings_humidity;
          pop @timestamps_temperature;
          shift @readings_temperature;
          shift @readings_humidity;
          shift @timestamps_temperature;
        }
        for (my $i=0;$i<scalar(@readings_pressure)/10;$i++)
        {
          pop @readings_pressure;
          pop @timestamps_pressure;
          shift @readings_pressure;
          shift @timestamps_pressure;
        }
        for (my $i=0;$i<scalar(@readings_rain)/10;$i++)
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
        for (my $i=0;$i<2;$i++)
        {
          pop @readings_altitude;
          pop @readings_latitude;
          pop @readings_longitude;
          shift @readings_altitude;
          shift @readings_latitude;
          shift @readings_longitude;
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
        my $max_humidity = 0;
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
        my $max_pressure = 0;
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
        my $max_rain = -10;
        foreach my $val (@readings_rain)
        {
          $avg_rain += $val / scalar(@readings_rain);
          $min_rain = $val if($val < $min_rain);
          $max_rain = $val if($val > $max_rain);
        }
        my $avg_rain_1 = 0;
        my $min_rain_1 = 1000;
        my $max_rain_1 = -10;
        foreach my $val (@readings_rain_1)
        {
          $avg_rain_1 += $val / scalar(@readings_rain_1);
          $min_rain_1 = $val if($val < $min_rain_1);
          $max_rain_1 = $val if($val > $max_rain_1);
        }
        my $avg_rain_24 = 0;
        my $min_rain_24 = 1000;
        my $max_rain_24 = -10;
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

        my $avg_altitude = 0;
        my $min_altitude = 10000;
        my $max_altitude = -1000;
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
        $avgtime_temperature = sprintf( "%i", $avgtime_temperature );
        $avgtime_pressure = sprintf( "%i", $avgtime_pressure );
        $avgtime_rain = sprintf( "%i", $avgtime_rain );
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
        if(scalar(@readings_altitude) > 0)
        {
          $hash->{altitude} = $avg_altitude;
          $hash->{location} = $avg_latitude.",".$avg_longitude;
        }
        $hash->{stations_indoor} = scalar(@readings_pressure);
        $hash->{stations_outdoor} = scalar(@readings_temperature);
        $hash->{stations_rain} = scalar(@readings_rain);

        my (undef,$latest) = netatmo_updateReadings( $hash, \@readings );
        $hash->{LAST_POLL} = FmtDateTime( $latest ) if( @readings );

        #$hash->{STATE} = "Error: device not found" if( !$found );
      } else {
        return $json->{body};
      }
    } else {
      return $hash->{status};
    }
  }
  else
  {
    $hash->{status} = "error";
  }
}

sub
netatmo_parseAddress($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  if( $json ) {
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

  if( $json ) {
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
    Log3 $name, 4, "$name: polling types [".$hash->{dataTypes} . "] for modules [".$hash->{Module}."]" if(defined($hash->{dataTypes}));

    my $lastupdate = ReadingsVal( $hash->{NAME}, ".lastupdate", undef );
    $lastupdate = (time-7*24*60*60) if(!$lastupdate and !$hash->{model});
    $hash->{openRequests} += int(@types);
    $hash->{openRequests} += 1 if(int(@types)==0);
    foreach my $module (split( ' ', $hash->{Module} ) ) {
      my $type;
      $type = shift(@types) if( $module and @types);

      readingsSingleUpdate($hash, ".lastupdate", $lastupdate, 0) if($type);
      netatmo_requestDeviceReadings( $hash, $hash->{Device}, $type, $module ne $hash->{Device}?$module:undef );# if($type);
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
    Log3 $name, 4, "$name: polling types [".$hash->{dataTypes} . "] for thermostat [".$hash->{Thermostat}."]" if(defined($hash->{dataTypes}));
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

  netatmo_refreshToken($hash);

  HttpUtils_NonblockingGet({
      url => "https://api.netatmo.com/api/getstationsdata",
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
  my $iohash = $hash->{IODev};
  netatmo_refreshAppToken($iohash);
  
  if(!defined($iohash->{access_token_app}))
  {
    Log3 $name, 1, "$name: pollForecast - missing app token!";
    return undef;
  }

  HttpUtils_NonblockingGet({
      url => "https://api.netatmo.com/api/simplifiedfuturemeasure",
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

  if( $hash->{Home} ) {
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
  Log3 $name, 5, "$name: pollrelay ".$hash->{Relay};

  if( $hash->{Relay} ) {
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
      || $hash->{SUBTYPE} eq "THERMOSTAT" ) {
    $list = "update:noArg";

    $list = " ping:noArg video video_local live live_local snapshot" if($hash->{SUBTYPE} eq "CAMERA");
    #$list .= " weathericon" if($hash->{SUBTYPE} eq "FORECAST");

    if( $cmd eq "weathericon" ) {
      return "no weathr code was passed" if($args[0] eq "");
      return netatmo_weatherIcon();
    }

    if( $cmd eq "ping" ) {
      netatmo_pingCamera($hash);
      return undef;
    }

    if( $cmd eq "video" || $cmd eq "video_local" ) {
      return "no video_id was passed" if($args[0] eq "");
      return netatmo_getCameraVideo($hash,$args[0],$cmd);
    }
    elsif( $cmd eq "live" || $cmd eq "live_local" ) {
      return netatmo_getCameraLive($hash,$cmd);
    }
    elsif( $cmd eq "snapshot" ) {
      return netatmo_getCameraSnapshot($hash);
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
    $list = "update:noArg devices:noArg homes:noArg thermostats:noArg public showAccount:noArg";

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
          $ret .= "$home->{id} \t\tHome\t".encode_utf8($home->{name}) if(defined($home->{cameras}));
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
            $ret .= "$thermostat->{_id}\t$thermostat->{firmware}\t$thermostat->{type}\t ".(defined($thermostat->{module_name}) ? $thermostat->{module_name} : $thermostat->{station_name});
          }

          $ret = "id\t\t\tfw\ttype\t name\n" . $ret if( $ret );
          $ret = "no thermostats found" if( !$ret );
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
      } elsif($args[0] =~ m/,/) {
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
        foreach my $device (@{$devices}) {
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
          my $definelink = "<a href=\"#\" onclick=\"javascript:window.open((\'/fhem?cmd=define netatmo_D".$idname." netatmo+++PUBLIC ".$device->{_id}." ".$ext."\').replace('+++',' '), 'definewindow');\">=&gt; </a>";
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

sub netatmo_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval" || $attrName eq "setpoint_duration");
  $attrVal = 15 if($attrName eq "setpoint_duration" && $attrVal < 15 && $attrVal != 0);

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $attrVal = 60*5 if($hash->{SUBTYPE} ne "HOME" && $attrVal < 60*5 && $attrVal != 0);

    #\$attrVal = 2700 if(($attrVal < 2700 && ($hash->{SUBTYPE} eq "ACCOUNT" || $hash->{SUBTYPE} eq "FORECAST");
    $hash->{INTERVAL} = $attrVal if($attrVal);
    $hash->{INTERVAL} = 60*30 if( !$hash->{INTERVAL} );
  } elsif( $attrName eq "setpoint_duration" ) {
      my $hash = $defs{$name};
      #$hash->{SETPOINT_DURATION} = $attrVal;
      #$hash->{SETPOINT_DURATION} = 60 if( !$hash->{SETPOINT_DURATION} );
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
    <li>videoquality<br>
      video quality for playlists (HOME - default: medium)</li>
  </ul>
</ul>

=end html
=cut

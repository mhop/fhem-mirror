# $Id$
################################################################
#
#  Copyright notice
#
#  (c) 2015 mike3436 (mike3436@online.de)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################ 
# $Id: 26_tahoma.pm
#
# 2014-08-01 V 0100 first Version using XML Interface
# 2015-08-16 V 0200 communication to server changes from xml to json
# 2015-08-16 V 0201 some standard requests after login which are not neccessary disabled (so the actual requests are not equal to flow of iphone app)
# 2016-02-14 V 0202 bugs forcing some startup warning messages fixed
# 2016-02-20 V 0203 perl exception while parsing json string captured
# 2016-02-24 V 0204 commands open,close,my,stop and setClosure added
# 2016-04-24 V 0205 commands taken from setup
# 2016-06-16 V 0206 updateDevices called for devices created before setup has been read
# 2016-11-15 V 0207 BLOCKING=0 can be used, all calls asynchron, attribut levelInvert inverts RollerShutter position
# 2016-11-29 V 0208 HttpUtils used instead of LWP::UserAgent, BLOCKING=0 set as default, umlaut can be used in Tahoma names
# 2016-12-15 V 0209 perl warnings during startup and login eliminated
# 2017-01-08 V 0210 tahoma_cancelExecutions: cancel command added
# 2017-01-10 V 0211 tahoma_getStates: read all states based on table {setup}{devices}[n]{definition}{states}
# 2017-01-24 V 0212 tahoma_getStates: read all states recovered
# 2017-01-24 V 0212 start scene with launchActionGroup so cancel is working on scenes now
# 2017-01-24 V 0212 Attribut interval used to disable or enable refreshAllstates
# 2017-01-24 V 0212 Setup changes recognized for reading places
# 2017-03-23 V 0213 username and password stored encrypted
# 2017-05-07 V 0214 encryption can be disabled by new attribut cryptLoginData
# 2017-05-07 V 0214 correct parameters of setClosureAndLinearSpeed caused syntax error
# 2017-07-01 V 0215 creation of fid and device names for first autocreate extended
# 2017-07-08 V 0215 login delay increased automatically up to 160s if login failed
# 2017-07-08 V 0215 default set commands on devices without commands deleted
# 2017-10-08 V 0216 group definition added

package main;

use strict;
use warnings;

use utf8;
use Encode qw(decode_utf8);
use JSON;
#use Data::Dumper;
use Time::HiRes qw(time);

use HttpUtils;

sub tahoma_parseGetSetupPlaces($$);
sub tahoma_UserAgent_NonblockingGet($);
sub tahoma_encode_utf8($);

my $hash_;

sub tahoma_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "tahoma_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "tahoma_Notify";
  $hash->{UndefFn}  = "tahoma_Undefine";
  $hash->{SetFn}    = "tahoma_Set";
  $hash->{GetFn}    = "tahoma_Get";
  $hash->{AttrFn}   = "tahoma_Attr";
  $hash->{AttrList} = "IODev ".
                      "blocking ".
                      "debug:1 ".
                      "disable:1 ".
                      "interval ".
                      "logfile ".
                      "url ".
                      "placeClasses ".
                      "levelInvert ".
                      "cryptLoginData ".
                      "userAgent ";
  $hash->{AttrList} .= $readingFnAttributes;
}

#####################################

sub tahoma_fhemIdFromDevice($)
{
  my @device = split "/", shift;
  $device[-1] =~ s/\W/_/g;
  return $device[-1] if (@device <= 4);
  $device[-2] =~ s/\W/_/g;
  return $device[-2].'_'.$device[-1] if (@device <= 5);;
  $device[-3] =~ s/\W/_/g;
  return $device[-3].'_'.$device[-2].'_'.$device[-1];
}

sub tahoma_fhemIdFromOid($)
{
  my @oid = split "-", shift;
  $oid[0] =~ s/\W/_/g;
  return $oid[0];
}

my $groupId = 123001;
sub tahoma_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  my $ModuleVersion = "0216";
  
  my $subtype;
  my $name = $a[0];
  if( $a[2] eq "DEVICE" && @a == 4 ) {
    $subtype = "DEVICE";

    my $device = $a[3];
    my $fid = tahoma_fhemIdFromDevice($device);

    $hash->{device} = $device;
    $hash->{fid} = $fid;

    $hash->{INTERVAL} = 0;

    my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"$fid"} = $hash;

  } elsif( $a[2] eq "PLACE" && @a == 4 ) {
    $subtype = "PLACE";

    my $oid = $a[@a-1];
    my $fid = tahoma_fhemIdFromOid($oid);

    $hash->{oid} = $oid;
    $hash->{fid} = $fid;

    $hash->{INTERVAL} = 0;

    my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
    return "place oid $oid already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"$fid"} = $hash;

  } elsif( $a[2] eq "GROUP" && @a == 4 ) {
    $subtype = "GROUP";

    my $oid = $a[@a-1];
    my $fid = 'group' . "$groupId";
    $groupId++;

    $hash->{oid} = $oid;
    $hash->{fid} = $fid;

    $hash->{INTERVAL} = 0;

    my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
    return "group oid $oid already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"$fid"} = $hash;

  } elsif( $a[2] eq "SCENE" && @a == 4 ) {
    $subtype = "SCENE";

    my $oid = $a[@a-1];
    my $fid = tahoma_fhemIdFromOid($oid);

    $hash->{oid} = $oid;
    $hash->{fid} = $fid;

    $hash->{INTERVAL} = 0;

    my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
    return "scene oid $oid already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"$fid"} = $hash;

  } elsif( $a[2] eq "ACCOUNT" && @a == 5 ) {
    $subtype = "ACCOUNT";

    my $username = $a[@a-2];
    my $password = $a[@a-1];
    
    $hash->{Clients} = ":tahoma:";

    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    $hash->{BLOCKING} = 0;
    $hash->{INTERVAL} = 0;
    $hash->{VERSION} = $ModuleVersion;

  } else {
    return "Usage: define <name> tahoma device\
       define <name> tahoma ACCOUNT username password\
       define <name> tahoma DEVICE id\
       define <name> tahoma SCENE oid username password\
       define <name> tahoma PLACE oid"  if(@a < 4 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;

  $hash->{STATE} = "Initialized";

  if( $init_done ) {
    tahoma_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "PLACE" );
    tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "GROUP" );
    tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "SCENE" );
  }

  return undef;
}

sub tahoma_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  if( $hash->{SUBTYPE} eq "ACCOUNT" )
  {
    my $name = $hash->{NAME};
    my $username = $hash->{helper}{username};
    my $password = $hash->{helper}{password};
    if ((defined $attr{$name}{cryptLoginData}) && (not $attr{$name}{cryptLoginData}))
    {
      $username = tahoma_decrypt($username);
      $password = tahoma_decrypt($password);
    }
    else
    {
      $username = tahoma_encrypt($username);
      $password = tahoma_encrypt($password);
    }
    $hash->{DEF} = "$hash->{SUBTYPE} $username $password";
  }
  
  tahoma_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
  tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "PLACE" );
  tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "GROUP" );
  tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "SCENE" );
}

sub tahoma_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{fid}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );
  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{fid}"} ) if( $hash->{SUBTYPE} eq "PLACE" );
  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{fid}"} ) if( $hash->{SUBTYPE} eq "GROUP" );
  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{fid}"} ) if( $hash->{SUBTYPE} eq "SCENE" );

  return undef;
}

sub tahoma_login($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: tahoma_login";

  $hash->{logged_in} = undef;
  $hash->{startup_run} = undef;
  $hash->{startup_done} = undef;
  $hash->{url} = "https://www.tahomalink.com/enduser-mobile-web/externalAPI/json/";
  $hash->{url} = $attr{$name}{url} if (defined $attr{$name}{url});
  $hash->{userAgent} = "TaHoma/7980 CFNetwork/758.5.3 Darwin/15.6.0";
  $hash->{userAgent} = $attr{$name}{userAgent} if (defined $attr{$name}{userAgent});
  $hash->{timeout} = 10;
  $hash->{HTTPCookies} = undef;
  $hash->{loginRetryTimer} = 5 if (!defined $hash->{loginRetryTimer});
  $hash->{loginRetryTimer} *= 2 if ($hash->{loginRetryTimer} < 160);
  
  Log3 $name, 2, "$name: login start";
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'login',
    data => {'userId' => tahoma_decrypt($hash->{helper}{username}) , 'userPassword'  => tahoma_decrypt($hash->{helper}{password})},
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}
  
my @startup_pages = ( 'getEndUser',
                      'getSetup',
                      'getActionGroups',
                      #'/../../enduserAPI/setup/interactiveNotifications',
                      #'/../../enduserAPI/setup/interactiveNotifications/history',
                      #'getCalendarDayList',
                      #'getCalendarRuleList',
                      #'/../../enduserAPI/conditionGroups',
                      #'getScheduledExecutions',
                      #'getHistory',
                      #'getSetupTriggers',
                      #'getUserPreferences',
                      #'getSetupOptions',
                      #'getAvailableProtocolsType',
                      #'getActiveProtocolsType',
                      #'getSetupQuota?quotaId=smsCredit',
                      #'getSetupDawnAndDuskTimes',
                      '../../enduserAPI/setup/gateways',
                      #'../../enduserAPI/setup/gateways',
                      #'../../enduserAPI/setup/subscribe/notification/apple/com.somfy.iPhoneTaHoma',
                      #'../../enduserAPI/setup/subscribe/notification/devices/tahoma',
                      #'/../../enduserAPI/setup/subscribe/notification/apple/com.somfy.iPhoneTaHoma',
                      #'../../enduserAPI/setup/subscribe/notification/devices/tahoma',
                      'getCurrentExecutions',
                      'refreshAllStates' );

sub tahoma_startup($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_startup";

  return if (!$hash->{logged_in});
  return if ($hash->{startup_done});
  
  if (!defined($hash->{startup_run}))
  {
    $hash->{startup_run} = 0;
  }
  else
  {
    $hash->{startup_run}++;
    if ($hash->{startup_run} >= scalar @startup_pages)
    {
      $hash->{startup_done} = 1;
      return;
    }
  }

  my $page = $startup_pages[$hash->{startup_run}];
  my $subpage = "";
  $subpage = '?gatewayId='.$hash->{gatewayId} if (substr($page, -13) eq 'ProtocolsType');
  $subpage = '?quotaId=smsCredit' if ($page eq 'getSetupQuota');
  $subpage = '/'.$hash->{gatewayId}.'/version' if (substr($page, -8) eq 'gateways');

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => $page,
    subpage => $subpage,
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}

sub tahoma_refreshAllStates($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_refreshAllStates";

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'refreshAllStates',
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}

sub tahoma_getEvents($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_getEvents";

  return if(!$hash->{logged_in} && !$hash->{startup_done});

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'getEvents',
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}

sub tahoma_readStatusTimer($)
{
  my $timestart = time;
  my $timeinfo = "tahoma_readStatusTimer";
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  
  my ($seconds) = gettimeofday();
  $hash->{refreshStateTimer} = $seconds + 10 if ( (!defined($hash->{refreshStateTimer})) || (!$hash->{logged_in}) );
  
  if( $hash->{request_active} ) {
      Log3 $name, 3, "$name: request active";
    if( ($timestart - $hash->{request_time}) > 10)
    {
      Log3 $name, 2, "$name: timeout, close ua";
      $hash->{socket} = undef;
      $hash->{request_active} = 0;
      $hash->{logged_in} = 0;
      $hash->{startup_done} = 0;
    }
  }
  elsif( !$hash->{logged_in} ) {
    tahoma_login($hash) if (!(defined $hash->{loginRetryTimer}) || !(defined $hash->{request_time}) || (($timestart - $hash->{request_time}) >= $hash->{loginRetryTimer}));
    $timeinfo = "tahoma_login";
  }
  elsif( !$hash->{startup_done} ) {
    tahoma_startup($hash);
    $timeinfo = "tahoma_startup";
    if ( $hash->{startup_done} ) {
      tahoma_getStates($hash) ;
      $hash->{refreshStateTimer} = $seconds + $hash->{INTERVAL};
      $timeinfo = "tahoma_getStates";
    }
  }
  elsif( ($seconds < $hash->{refreshStateTimer}) || ($hash->{INTERVAL} <= 0) )
  {
    Log3 $name, 4, "$name: refreshing event";
    tahoma_getEvents($hash);
    $timeinfo = "tahoma_getEvents";
  }
  else
  {
    Log3 $name, 4, "$name: refreshing state";
    tahoma_refreshAllStates($hash);
    tahoma_getStates($hash);
    $hash->{refreshStateTimer} = $seconds + $hash->{INTERVAL};
    $timeinfo = "tahoma_refreshAllStates tahoma_getStates";
  }

  my $timedelta = time -$timestart;
  if ($timedelta > 0.5)
  {
    $timedelta *= 1000;
    Log3 $name, 3, "$name: $timeinfo took $timedelta ms"
  }

  InternalTimer(gettimeofday()+2, "tahoma_readStatusTimer", $hash, 0);
}

sub tahoma_connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: tahoma_connect";

  RemoveInternalTimer($hash);
  tahoma_login($hash);

  my ($seconds) = gettimeofday();
  $hash->{refreshStateTimer} = $seconds + 10;
  tahoma_readStatusTimer($hash);
}

sub tahoma_initDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $subtype = $hash->{SUBTYPE};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  my $device;
  if( defined($hash->{device}) ) {
    $device = tahoma_getDeviceDetail( $hash, $hash->{device} );
    #Log3 $name, 4, Dumper($device);
  } elsif( defined($hash->{oid}) ) {
    $device = tahoma_getDeviceDetail( $hash, $hash->{oid} );
    #Log3 $name, 4, Dumper($device);
  }

  if( defined($device) && ($subtype eq 'DEVICE') ) {
    Log3 $name, 4, "$name: I/O device is label=".$device->{label};
    $hash->{inType} = $device->{type};
    $hash->{inLabel} = $device->{label};
    $hash->{inControllable} = $device->{controllableName};
    $hash->{inPlaceOID} = $device->{placeOID};
    $hash->{inClass} = $device->{uiClass};
    $device->{levelInvert} = $attr{$hash->{NAME}}{levelInvert} if (defined $attr{$hash->{NAME}}{levelInvert});
  }
  elsif( defined($device) && ($subtype eq 'PLACE') ) {
    Log3 $name, 4, "$name: I/O device is label=".$device->{label};
    $hash->{inType} = $device->{type};
    $hash->{inLabel} = $device->{label};
    $hash->{inOID} = $device->{oid};
    $hash->{inClass} = 'RollerShutter';
    $hash->{inClass} = $attr{$hash->{NAME}}{placeClasses} if (defined $attr{$hash->{NAME}}{placeClasses});
  }
  elsif( defined($device) && ($subtype eq 'SCENE') ) {
    Log3 $name, 4, "$name: I/O device is label=".$device->{label};
    $hash->{inLabel} = $device->{label};
    $hash->{inOID} = $device->{oid};
  }
  elsif($subtype eq 'GROUP' ) {
    $hash->{inType} = '';
    $hash->{inLabel} = '';
    $hash->{inLabel} = $attr{$hash->{NAME}}{alias} if (defined $attr{$hash->{NAME}}{alias});
    $hash->{inOID} = '';
    $hash->{inClass} = '';
  }
  else
  {
    my $device=$hash->{device};
    $device ||= 'undefined';
    $subtype ||= 'undefined';
    Log3 $name, 3, "$name: unknown device=$device, subtype=$subtype";
  }
}

sub tahoma_updateDevices($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "$name: tahoma_updateDevices";

  return undef if( !$hash->{helper}{devices} ) ;
  
  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  foreach my $module (keys %{$modules{$hash->{TYPE}}{defptr}}) {
    my $def = $modules{$hash->{TYPE}}{defptr}{"$module"};
    my $subtype = $def->{SUBTYPE};
    if (defined($def->{oid}) && !defined($def->{inType}))
    {
      Log3 $name, 3, "$name: updateDevices oid=$def->{oid}";
      my $device = tahoma_getDeviceDetail( $hash, $def->{oid} );
      if( defined($device) && ($subtype eq 'PLACE') ) {
        Log3 $name, 4, "$name: I/O device is label=".$device->{label};
        $def->{inType} = $device->{type};
        $def->{inLabel} = $device->{label};
        $def->{inOID} = $device->{oid};
        $def->{inClass} = 'RollerShutter';
        $def->{inClass} = $attr{$def->{NAME}}{placeClasses} if (defined $attr{$def->{NAME}}{placeClasses});
      }
      elsif( defined($device) && ($subtype eq 'SCENE') ) {
        Log3 $name, 4, "$name: I/O device is label=".$device->{label};
        $def->{inLabel} = $device->{label};
        $def->{inOID} = $device->{oid};
      }
    }
    elsif (defined($def->{device}) && !defined($def->{inType}))
    {
      Log3 $name, 3, "$name: updateDevices device=$def->{device}";
      my $device = tahoma_getDeviceDetail( $hash, $def->{device} );
      if( defined($device) && ($subtype eq 'DEVICE') ) {
        Log3 $name, 4, "$name: I/O device is label=".$device->{label};
        $def->{inType} = $device->{type};
        $def->{inLabel} = $device->{label};
        $def->{inControllable} = $device->{controllableName};
        $def->{inPlaceOID} = $device->{placeOID};
        $def->{inClass} = $device->{uiClass};
        $device->{levelInvert} = $attr{$def->{NAME}}{levelInvert} if (defined $attr{$def->{NAME}}{levelInvert});
      }
    }
  }

  return undef;
}

sub tahoma_getDevices($$)
{
  my ($hash,$nonblocking) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_getDevices";

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'getSetup',
    callback => \&tahoma_dispatch,
    nonblocking => $nonblocking,
  });

  return $hash->{helper}{devices};
}

sub tahoma_getDeviceDetail($$)
{
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_getDeviceDetails $id";

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  foreach my $device (@{$hash->{helper}{devices}}) {
    return $device if( defined($device->{deviceURL}) && ($device->{deviceURL} eq $id)  );
    return $device if( defined($device->{oid}) && ($device->{oid} eq $id) );
  }

  Log3 $name, 4, "$name: getDeviceDetails $id not found";
  
  return undef;
}

sub tahoma_getStates($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_getStates";

  my $data = '[';
  
  foreach my $device (@{$hash->{helper}{devices}}) {
    if( defined($device->{deviceURL}) && defined($device->{states}) )
    {
      $data .= ',' if (substr($data, -1) eq '}');
      $data .= '{"deviceURL":"'.$device->{deviceURL}.'","states":[';
      foreach my $state (@{$device->{states}}) {
        $data .= ',' if (substr($data, -1) eq '}');
        $data .= '{"name":"' . $state->{name} . '"}';
      }
      $data .= ']}';
    }
  }
  
  $data .= ']';

  Log3 $name, 5, "$name: tahoma_getStates data=".$data;
  
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'getStates',
    data => tahoma_encode_utf8($data),
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
  
}

sub tahoma_getDeviceList($$$$);
sub tahoma_getDeviceList($$$$)
{
  my ($hash,$oid,$placeClasses,$deviceList) = @_;
  #print "tahoma_getDeviceList oid=$oid devices=".scalar @{$deviceList}."\n";
  
  my @classes = split(' ',$placeClasses);
  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    if ( defined($device->{deviceURL}) && defined($device->{placeOID}) && defined($device->{uiClass}) ) {
      if (( grep { $_ eq $device->{uiClass}} @classes ) && ($device->{placeOID} eq $oid)) {
        push ( @{$deviceList}, { device => $device->{deviceURL}, class => $device->{uiClass}, levelInvert => $device->{levelInvert} } ) ;
        #print "tahoma_getDeviceList url=$device->{deviceURL} devices=".scalar @{$deviceList}."\n";
      }
    } elsif ( defined($device->{oid}) && defined($device->{subPlaces}) ) {
      if ($device->{oid} eq $oid)
      {
        foreach my $place (@{$device->{subPlaces}}) {
          tahoma_getDeviceList($hash,$place->{oid},$placeClasses,$deviceList);
        }
      }
    }
  }
}

sub tahoma_getGroupList($$$)
{
  my ($hash,$oid,$deviceList) = @_;
  #print "tahoma_getGroupList oid=$oid devices=".scalar @{$deviceList}."\n";

  my @groupDevices = split(',',$oid);
  foreach my $module (@groupDevices) {
    if (defined($defs{$module}) && defined($defs{$module}{device}) && defined($defs{$module}{inClass})) {
      push ( @{$deviceList}, { device => $defs{$module}{device}, class => $defs{$module}{inClass}, levelInvert => $attr{$module}{levelInvert} } ) ;
    }
  }
}

sub tahoma_checkCommand($$$$)
{
  my ($hash,$device,$command,$value) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_checkCommand";
  if (($command eq 'setClosure') && (defined ($device->{levelInvert})))
  {
    $value = 100 - $value if ($device->{levelInvert} && ($value >= 0) && ($value <= 100));
  }
  if (($command eq 'setClosure') && ($value == 100) && (index($hash->{COMMANDS}," close:") > 0))
  {
    $command = 'close';
    $value = '';
  }
  if (($command eq 'setClosure') && ($value == 0) && (index($hash->{COMMANDS}," open:") > 0))
  {
    $command = 'open';
    $value = '';
  }
  return ($command,$value);
}

sub tahoma_applyRequest($$$)
{
  my ($hash,$command,$value) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_applyRequest";

  if ( !defined($hash->{IODev}) || !(defined($hash->{device}) || defined($hash->{oid})) || !defined($hash->{inLabel}) || !defined($hash->{inClass}) ) {
    Log3 $name, 3, "$name: tahoma_applyRequest failed - define error";
    return;
  }
  
  my @devices = ();
  if ( defined($hash->{device}) ) {
    push ( @devices, { device => $hash->{device}, class => $hash->{inClass}, commands => $hash->{COMMANDS}, levelInvert => $attr{$hash->{NAME}}{levelInvert} } );
  } elsif ($hash->{SUBTYPE} eq 'GROUP') {
    tahoma_getGroupList($hash->{IODev},$hash->{oid},\@devices);
  } else {
    tahoma_getDeviceList($hash->{IODev},$hash->{oid},$hash->{inClass},\@devices);
  }

  Log3 $name, 4, "$name: tahoma_applyRequest devices=".scalar @devices;
  foreach my $dev (@devices) {
    Log3 $name, 4, "$name: tahoma_applyRequest devices=$dev->{device} class=$dev->{class}";
  }
  
  return if (scalar @devices < 1);

  my $data = '';
  $value = '' if (!defined($value));
  my $commandChecked = $command;
  my $valueChecked = $value;
  foreach my $device (@devices) {
    ($commandChecked, $valueChecked) = tahoma_checkCommand($hash,$device,$command,$value);
    if (defined($commandChecked) && defined($valueChecked))
    {
      $data .= ',' if substr($data, -1) eq '}';
      $data .= '{"deviceURL":"'.$device->{device}.'",';
      $data .= '"commands":[{"name":"'.$commandChecked.'","parameters":['.$valueChecked.']}]}';
    }
  }
  return if (length $data < 20);
  
  my $dataHead = '{"label":"' . $hash->{inLabel};
  if ($commandChecked eq 'setClosure') {
    $dataHead .= ' - Positionieren auf '.$valueChecked.' % - iPhone","actions":[';
  } elsif ($commandChecked eq 'close') {
    $dataHead .= ' - Schliessen - iPhone","actions":[';
  } elsif ($commandChecked eq 'open') {
    $dataHead .= ' - Oeffnen - iPhone","actions":[';
  } elsif ($commandChecked eq 'setClosureAndLinearSpeed') {                                         #neu fuer setClosureAndLinearSpeed
    $dataHead .= ' - Positionieren auf '.(split(',',$valueChecked))[0].' % - iPhone","actions":[';  #neu fuer setClosureAndLinearSpeed
  } else {
    $dataHead .= " - $commandChecked $valueChecked".' - iPhone","actions":[';
  }
  $data = $dataHead . $data . ']}';

  Log3 $name, 3, "$name: tahoma_applyRequest data=".$data;
  
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'apply',
    data => tahoma_encode_utf8($data),
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}

sub tahoma_scheduleActionGroup($$)
{
  my ($hash,$delay) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_scheduleActionGroup";

  if ( !defined($hash->{IODev}) || !defined($hash->{oid}) ) {
    Log3 $name, 3, "$name: tahoma_scheduleActionGroup failed - define error";
    return;
  }

  $delay = 0 if(!defined($delay));
  
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'scheduleActionGroup',
    subpage => '?oid='.$hash->{oid}.'&delay='.$delay,
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}

sub tahoma_launchActionGroup($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_launchActionGroup";

  if ( !defined($hash->{IODev}) || !defined($hash->{oid}) ) {
    Log3 $name, 3, "$name: tahoma_launchActionGroup failed - define error";
    return;
  }

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'launchActionGroup',
    subpage => '?oid='.$hash->{oid},
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}

sub tahoma_cancelExecutions($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_cancelExecutions";

  my $subpage = '';
  if (defined($hash->{IODev}))
  {
    if (defined($hash->{inExecId}) && (length $hash->{inExecId} > 20))
    {
      $subpage = '?execId='.$hash->{inExecId};
    }
    elsif (defined($hash->{inTriggerId}) && (length $hash->{inTriggerId} > 20))
    {
      $subpage = '?triggerId='.$hash->{inTriggerId};
    }
    else
    {
      Log3 $name, 3, "$name: tahoma_cancelExecutions failed - no valid execId or triggerId found";
      return;
    }
  }
  Log3 $name, 3, "$name: tahoma_cancelExecutions subpage=$subpage";

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'cancelExecutions',
    subpage => $subpage,
    callback => \&tahoma_dispatch,
    nonblocking => 1,
  });
}

sub tahoma_dispatch($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $hashIn = $hash;
  
  $hash = $hash->{IODev} if (defined($hash->{IODev}));
  
  $hash->{request_active} = 0;
  
  if( $err ) {
    Log3 $name, 2, "$name: tahoma_dispatch http request failed: $err";
    $hash->{logged_in} = 0;
    return;
  }
  
  if( $data ) {
    tahoma_GetCookies($hash,$param->{httpheader}) if (!$hash->{logged_in});
    
    $data =~ tr/\r\n//d;
    $data =~ s/\h+/ /g;
    $data =~ s/\\\//\//g;

    Log3 $name, (length $data > 120)?4:5, "$name: tahoma_dispatch data=".decode_utf8($data);

    # perl exception while parsing json string captured
    my $json = {};
    eval { $json = JSON->new->utf8(0)->decode($data); };
    if ($@) {
      Log3 $name, 3, "$name: tahoma_dispatch json string is faulty";
      $hash->{lastError} = 'json string is faulty';
      $hash->{logged_in} = 0;
      return;
    }
    
    if( (ref $json ne 'ARRAY') && ($json->{errorResponse}) ) {
      $hash->{lastError} = $json->{errorResponse}{message};
      $hash->{logged_in} = 0;
      Log3 $name, 3, "$name: tahoma_dispatch error: $hash->{lastError}";
      return;
    }

    if( (ref $json ne 'ARRAY') && ($json->{error}) ) {
      $hash->{lastError} = $json->{error};
      $hash->{logged_in} = 0;
      Log3 $name, 3, "$name: tahoma_dispatch error: $hash->{lastError}";
      return;
    }

    if( $param->{page} eq 'getEvents' ) {
      tahoma_parseGetEvents($hash,$json);
    } elsif( $param->{page} eq 'apply' ) {
      tahoma_parseApplyRequest($hashIn,$json);
    } elsif( $param->{page} eq 'getSetup' ) {
      tahoma_parseGetSetup($hash,$json);
    } elsif( $param->{page} eq 'refreshAllStates' ) {
      tahoma_parseRefreshAllStates($hash,$json);
    } elsif( $param->{page} eq 'getStates' ) {
      tahoma_parseGetStates($hash,$json);
    } elsif( $param->{page} eq 'login' ) {
      tahoma_parseLogin($hash,$json);
    } elsif( $param->{page} eq 'getActionGroups' ) {
      tahoma_parseGetActionGroups($hash,$json);
    } elsif( $param->{page} eq '../../enduserAPI/setup/gateways' ) {
      tahoma_parseEnduserAPISetupGateways($hash,$json);
    } elsif( $param->{page} eq 'getCurrentExecutions' ) {
      tahoma_parseGetCurrentExecutions($hash,$json);
    } elsif( $param->{page} eq 'scheduleActionGroup' ) {
      tahoma_parseScheduleActionGroup($hashIn,$json);
    } elsif( $param->{page} eq 'launchActionGroup' ) {
      tahoma_parseLaunchActionGroup($hashIn,$json);
    } elsif( $param->{page} eq 'cancelExecutions' ) {
      tahoma_parseCancelExecutions($hash,$json);
    }
  }
}

sub tahoma_autocreate($)
{
  my($hash) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{devices} ) {
    tahoma_getDevices($hash,1);
    return undef;
  }

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
  }
  
  Log3 $name, 2, "$name: tahoma_autocreate begin";

  my $autocreated = 0;

  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    my ($id, $fid, $devname, $define);
    if ($device->{deviceURL}) {
      $id = $device->{deviceURL};
      $fid = tahoma_fhemIdFromDevice($id);
      $devname = "tahoma_". $fid;
      $define = "$devname tahoma DEVICE $id";
      if( defined($modules{$hash->{TYPE}}{defptr}{"$fid"}) ) {
        Log3 $name, 4, "$name: device '$fid' already defined";
        next;
      }
    } elsif ( $device->{oid} ) {
      $id = $device->{oid};
      my $fid = tahoma_fhemIdFromOid($id);
      $devname = "tahoma_". $fid;
      $define = "$devname tahoma PLACE $id" if (!defined $device->{actions});
      $define = "$devname tahoma SCENE $id" if (defined $device->{actions});
      if( defined($modules{$hash->{TYPE}}{defptr}{"$fid"}) ) {
        Log3 $name, 4, "$name: device '$fid' already defined";
        next;
      }
    }

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias room ".$device->{label}) if( defined($device->{label}) && defined($device->{oid}) && !defined($device->{actions}) );
      $cmdret= CommandAttr(undef,"$devname alias scene ".$device->{label}) if( defined($device->{label}) && defined($device->{oid}) && defined($device->{actions}) );
      $cmdret= CommandAttr(undef,"$devname alias $device->{uiClass} ".$device->{label}) if( defined($device->{label}) && defined($device->{states}) );
      $cmdret= CommandAttr(undef,"$devname room tahoma");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname webCmd dim") if( defined($device->{uiClass}) && ($device->{uiClass} eq "RollerShutter") );

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );
  Log3 $name, 2, "$name: tahoma_autocreate end, new=$autocreated";
}

sub tahoma_defineCommands($)
{
  my($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_defineCommands";
  
  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    my ($id, $fid, $devname, $define);
    if ($device->{deviceURL}) {
      $id = $device->{deviceURL};
      $fid = tahoma_fhemIdFromDevice($id);
      $devname = "tahoma_". $fid;
      $define = "$devname tahoma DEVICE $id";
      my $commandlist = "";
      if( defined $device->{definition}{commands}[0]{commandName} ) {
        $commandlist = "dim:slider,0,1,100 cancel:noArg";
        foreach my $command (@{$device->{definition}{commands}}) {
          $commandlist .= " " . $command->{commandName};
          $commandlist .= ":noArg" if ($command->{nparams} == 0);
        }
      }
      if( defined($modules{$hash->{TYPE}}{defptr}{"$fid"}) ) {
        $modules{$hash->{TYPE}}{defptr}{"$fid"}{COMMANDS} = $commandlist;
        Log3 $name, 4, "$name: tahoma_defineCommands fid=$fid commandlist=$commandlist";
      }
    }
  }
}

sub tahoma_parseLogin($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseLogin";
  if (defined $json->{errorResponse}) {
    $hash->{logged_in} = 0;
    $hash->{STATE} = $json->{errorResponse}{message};
  } else {
    $hash->{inVersion} = $json->{version};
    $hash->{logged_in} = 1;
    $hash->{loginRetryTimer} = 5,
  }
  Log3 $name, 2, "$name: login end, logged_in=".$hash->{logged_in};
}

sub tahoma_parseGetEvents($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: tahoma_parseGetEvent";

  $hash->{refresh_event} = $json;

  if( $hash->{logged_in} ) {
    $hash->{STATE} = "Connected";
  } else {
    $hash->{STATE} = "Disconnected";
  }

  if( ref $json eq 'ARRAY' ) {
    #print Dumper($json);
    foreach my $devices ( @{$json} ) {
      if( defined($devices->{deviceURL}) ) {
        #print "\nDevice=$devices->{deviceURL} found\n";
        my $id = $devices->{deviceURL};
        my $fid = tahoma_fhemIdFromDevice($id);
        my $devname = "tahoma_". $fid;
        my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
        if( defined($d) )# && $d->{NAME} eq $devname )
        {
          #print "\nDevice=$devices->{deviceURL} updated\n";
          readingsBeginUpdate($d);
          foreach my $state (@{$devices->{deviceStates}}) {
            #print "$devname $state->{name} = $state->{value}\n";
            next if (!defined($state->{name}) || !defined($state->{value}));
            if ($state->{name} eq "core:ClosureState") {
              $state->{value} = 100 - $state->{value} if ($attr{$d->{NAME}}{levelInvert});
              readingsBulkUpdate($d, "state", "dim".$state->{value});
            } elsif ($state->{name} eq "core:OpenClosedState") {
              readingsBulkUpdate($d, "devicestate", $state->{value});
            }
            readingsBulkUpdate($d, (split(":",$state->{name}))[-1], $state->{value});
          }
          my ($seconds) = gettimeofday();
          readingsBulkUpdate( $d, ".lastupdate", $seconds, 0 );
          readingsEndUpdate($d,1);
        }
      }
      elsif( defined($devices->{name}) && (defined($devices->{execId}) || defined($devices->{triggerId})) )
      {
        foreach my $module (keys %{$modules{$hash->{TYPE}}{defptr}})
        {
          my $def = $modules{$hash->{TYPE}}{defptr}{"$module"};
          if (defined($def->{inExecId}) && ($def->{inExecId} eq $devices->{execId}))
          {
            if ($devices->{name} eq 'ExecutionStateChangedEvent')
            {
              $def->{inExecState} = $devices->{newState};
              $def->{inExecId} = 'finished' if ($devices->{newState} == 4);
              $def->{inExecId} = 'canceled' if ($devices->{newState} == 5);
            }
          }
          elsif (defined($def->{inTriggerId}) && ($def->{inTriggerId} eq $devices->{triggerId}))
          {
            $def->{inTriggerState} = $devices->{name};
            $def->{inTriggerId} = 'finished' if ($devices->{name} eq '4');
            $def->{inTriggerId} = 'canceled' if ($devices->{name} eq '5');
          }
        }
      }
    }
  }
  
}

sub tahoma_parseApplyRequest($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseApplyRequest";
  $hash->{inExecState} = 0;
  if (defined($json->{execId})) {
    $hash->{inExecId} = $json->{execId};
  } else {
    $hash->{inExecId} = "undefined";
  }
  if (defined($json->{events}) && defined($hash->{IODev}))
  {
    tahoma_parseGetEvents($hash->{IODev},$json->{events})
  }
}

sub tahoma_parseGetSetup($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  
  $hash->{gatewayId} = $json->{setup}{gateways}[0]{gatewayId};

  my @devices = ();
  foreach my $device (@{$json->{setup}{devices}}) {
    Log3 $name, 4, "$name: tahoma_parseGetSetup device = $device->{label}";
    push( @devices, $device );
  }
  
  $hash->{helper}{devices} = \@devices;

  if ($json->{setup}{rootPlace}) {
    my $places = $json->{setup}{rootPlace};
    #Log3 $name, 4, "$name: tahoma_parseGetSetup places= " . Dumper($places);
    tahoma_parseGetSetupPlaces($hash, $places);
  }

  tahoma_autocreate($hash);
  tahoma_updateDevices($hash);
  tahoma_defineCommands($hash);
}

sub tahoma_parseGetSetupPlaces($$)
{
  my($hash, $places) = @_;
  my $name = $hash->{NAME};
  #Log3 $name, 4, "$name: tahoma_parseGetSetupPlaces " . Dumper($places);

  my $devices = $hash->{helper}{devices};
  
  if (ref $places eq 'ARRAY') {
    #Log3 $name, 4, "$name: tahoma_parseGetSetupPlaces isArray";
    foreach my $place (@{$places}) {
      push( @{$devices}, $place );
      my $placesNext = $place->{subPlaces};
      tahoma_parseGetSetupPlaces($hash, $placesNext ) if ($placesNext);
    }
  }
  else {
    #Log3 $name, 4, "$name: tahoma_parseGetSetupPlaces isScalar";
    push( @{$devices}, $places );
    my $placesNext = $places->{subPlaces};
    tahoma_parseGetSetupPlaces($hash, $placesNext) if ($placesNext);
  }

}

sub tahoma_parseGetActionGroups($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseGetActionGroups";
  
  my $devices = $hash->{helper}{devices};
  foreach my $action (@{$json->{actionGroups}}) {
    push( @{$devices}, $action );
  }
  tahoma_autocreate($hash);
  tahoma_updateDevices($hash);
  tahoma_defineCommands($hash);
}

sub tahoma_parseRefreshAllStates($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseRefreshAllStates";
}

sub tahoma_parseGetStates($$)
{
  my($hash, $states) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseGetStates";

  if( defined($states->{devices}) ) {
    foreach my $devices ( @{$states->{devices}} ) {
      if( defined($devices->{deviceURL}) ) {
        my $id = $devices->{deviceURL};
        my $fid = tahoma_fhemIdFromDevice($id);
        my $devname = "tahoma_". $fid;
        my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
        if( defined($d) )# && $d->{NAME} eq $devname )
        {
          readingsBeginUpdate($d);
          foreach my $state (@{$devices->{states}}) {
            next if (!defined($state->{name}) || !defined($state->{value}));
            if ($state->{name} eq "core:ClosureState") {
              $state->{value} = 100 - $state->{value} if ($attr{$d->{NAME}}{levelInvert});
              readingsBulkUpdate($d, "state", "dim".$state->{value});
            } elsif ($state->{name} eq "core:OpenClosedState") {
              readingsBulkUpdate($d, "devicestate", $state->{value});
            }
            readingsBulkUpdate($d, (split(":",$state->{name}))[-1], $state->{value});
          }
          my ($seconds) = gettimeofday();
          readingsBulkUpdate( $d, ".lastupdate", $seconds, 0 );
          readingsEndUpdate($d,1);
        }
      }
    }
  }
}

sub tahoma_parseEnduserAPISetupGateways($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseEnduserAPISetupGateways";
  
  eval { $hash->{inGateway} = $json->{result}; };
  eval { $hash->{inGateway} = $json->[0]{gatewayId}; };
}

sub tahoma_parseGetCurrentExecutions($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseGetCurrentExecutions";
}

sub tahoma_parseScheduleActionGroup($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseScheduleActionGroup";
  if (defined $json->{actionGroup})
  {
    $hash->{inTriggerState} = 0;
    if (defined($json->{actionGroup}[0]{triggerId})) {
      $hash->{inTriggerId} = $json->{actionGroup}[0]{triggerId};
    } else {
      $hash->{inTriggerId} = "undefined";
    }
  }
  if (defined($json->{events}) && defined($hash->{IODev}))
  {
    tahoma_parseGetEvents($hash->{IODev},$json->{events})
  }
}

sub tahoma_parseLaunchActionGroup($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseLaunchActionGroup";
  if (defined $json->{actionGroup})
  {
    $hash->{inExecState} = 0;
    if (defined($json->{actionGroup}[0]{execId})) {
      $hash->{inExecId} = $json->{actionGroup}[0]{execId};
    } else {
      $hash->{inExecId} = "undefined";
    }
  }
  if (defined($json->{events}) && defined($hash->{IODev}))
  {
    tahoma_parseGetEvents($hash->{IODev},$json->{events})
  }
}

sub tahoma_parseCancelExecutions($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseCancelExecutions";
}

sub tahoma_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list;
  if( $hash->{SUBTYPE} eq "DEVICE" ) {
    $list = "updateAll:noArg";

    if( $cmd eq "updateAll" ) {
      my ($seconds) = gettimeofday();
      $hash->{refreshStateTimer} = $seconds;
      return undef;
    }

  } elsif( $hash->{SUBTYPE} eq "SCENE"
      || $hash->{SUBTYPE} eq "GROUP" 
      || $hash->{SUBTYPE} eq "PLACE" ) {
    $list = "";

  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    $list = "devices:noArg reset:noArg";

    if( $cmd eq "devices" ) {
      my $devices = tahoma_getDevices($hash,0);
      my $ret;
      foreach my $device (@{$devices}) {
        $ret .= "$device->{deviceURL}\t".$device->{label}."\t$device->{uiClass}\t$device->{controllable}\t\n" if ($device->{deviceURL});
        $ret .= "$device->{oid}\t".$device->{label}."\n" if ($device->{oid});
      }

      $ret = "id\t\t\t\tname\t\t\tuiClass\t\tcontrollable\n" . $ret if( $ret );
      $ret = "no devices found" if( !$ret );
      return $ret;
    }
    elsif( $cmd eq "reset" ) {
      HttpUtils_Close($hash);
      $hash->{logged_in} = undef;
      $hash->{loginRetryTimer} = undef;
      return "connection closed";
    }
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub tahoma_Set($$@)
{
  my ($hash, $name, $cmd, $val) = @_;
  #Log3 $name, 3, "$name: tahoma_Set $cmd $val $hash->{SUBTYPE} $hash->{COMMANDS}";

  my $list = "";
  if( $hash->{SUBTYPE} eq "DEVICE" ||
      $hash->{SUBTYPE} eq "GROUP" ||
      $hash->{SUBTYPE} eq "PLACE" ) {
    $list = "dim:slider,0,1,100 setClosure open:noArg close:noArg my:noArg stop:noArg cancel:noArg";
    $list = $hash->{COMMANDS} if (defined $hash->{COMMANDS});

    if( $cmd eq "cancel" ) {
      tahoma_cancelExecutions($hash);
      return undef;
    }

    $cmd = "setClosure" if( $cmd eq "dim" );
    
    my @commands = split(" ",$list);
    foreach my $command (@commands)
    {
      if( $cmd eq (split(":",$command))[0])
      {
        tahoma_applyRequest($hash,$cmd,$val);
        return undef;
      }
    }
  }
  
  if( $hash->{SUBTYPE} eq "SCENE") {
    $list = "start:noArg startAt cancel:noArg";

    if( $cmd eq "start" ) {
      tahoma_launchActionGroup($hash);
      return undef;
    }
    
    if( $cmd eq "startAt" ) {
      tahoma_scheduleActionGroup($hash,$val);
      return undef;
    }
    
    if( $cmd eq "cancel" ) {
      tahoma_cancelExecutions($hash);
      return undef;
    }
  }

  if( $hash->{SUBTYPE} eq "ACCOUNT") {
    $list = "cancel:noArg";

    if( $cmd eq "cancel" ) {
      tahoma_cancelExecutions($hash);
      return undef;
    }
  }
    
  return "Unknown argument $cmd, choose one of $list";
}

sub tahoma_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $attrVal = int($attrVal);
    $attrVal = 60*5 if ($attrVal < 60*5 && $attrVal != 0);
    $hash->{INTERVAL} = $attrVal;
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
    }
  } elsif( $attrName eq "blocking" ) {
    my $hash = $defs{$name};
    $hash->{BLOCKING} = $attrVal;
  } elsif( $attrName eq "placeClasses" ) {
    my $hash = $defs{$name};
    $hash->{inClass} = $attrVal if $hash->{SUBTYPE} eq "PLACE";
  }
  elsif ( $attrName eq "levelInvert" ) {
    my $hash = $defs{$name};
    my $device = tahoma_getDeviceDetail( $hash, $hash->{device} );
    $device->{levelInvert} = $attrVal if (defined $device);
  }
  
  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

sub tahoma_UserAgent_NonblockingGet($)
{
	my ($param) = @_;
  my ($hash) = $param->{hash};
  $hash = $hash->{IODev} if (defined ($hash->{IODev}));

  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: tahoma_UserAgent_NonblockingGet page=$param->{page}";

  #"User-Agent":"TaHoma/7980 CFNetwork/758.5.3 Darwin/15.6.0","Proxy-Connection":"keep-alive","Accept":"*/*","Connection":"keep-alive","Content-Length":"49","Accept-Encoding":"gzip, deflate","Content-Type":"application/x-www-form-urlencoded","Accept-Language":"de-de","Host":"www.tahomalink.com"
  $param->{header} = {'User-Agent' => $hash->{userAgent} }; #, 'Accept-Language' => "de-de", 'Accept-Encoding' => "gzip, deflate"};
  $param->{header}{Cookie} = $hash->{HTTPCookies} if ($hash->{HTTPCookies});
  $param->{compress} = 1;
  $param->{keepalive} = 1;
  if (index($hash->{url},'file:') == 0)
  {
    $param->{url} = $hash->{url} . $param->{page} . '.json';
    my $find = "../";
    $find = quotemeta $find; # escape regex metachars if present
    $param->{url} =~ s/$find//g;
  }
  else
  {
    $param->{url} = $hash->{url} . $param->{page};
    $param->{url} .= $param->{subpage} if ($param->{subpage});
  }
  
  $hash->{request_active} = 1;
  $hash->{request_time} = time;
  
  if ($param->{blocking})
  {
    my($err,$data) = HttpUtils_BlockingGet($param);
  	$param->{callback}($param, $err, $data, length $data) if($param->{callback});
  }
  else
  {
    my($err,$data) = HttpUtils_NonblockingGet($param);
  }
  
}

sub tahoma_encode_utf8($)
{
  my ($text) = @_;
  $text =~ s/Ã„/Ae/g;
  $text =~ s/Ã–/Oe/g;
  $text =~ s/Ãœ/Ue/g;
  $text =~ s/Ã¤/ae/g;
  $text =~ s/Ã¶/oe/g;
  $text =~ s/Ã¼/ue/g;
  $text =~ s/ÃŸ/ss/g;
  return $text;
}

sub tahoma_GetCookies($$)
{
    my ($hash, $header) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "$name: tahoma_GetCookies looking for Cookies in header";
    foreach my $cookie ($header =~ m/set-cookie: ?(.*)/gi) {
        Log3 $name, 5, "$name: Set-Cookie: $cookie";
        $cookie =~ /([^,; ]+)=([^,; ]+)[;, ]*(.*)/;
        Log3 $name, 4, "$name: Cookie: $1 Wert $2 Rest $3";
        $hash->{HTTPCookieHash}{$1}{Value} = $2;
        $hash->{HTTPCookieHash}{$1}{Options} = ($3 ? $3 : "");
    }
    $hash->{HTTPCookies} = join ("; ", map ($_ . "=".$hash->{HTTPCookieHash}{$_}{Value}, 
                                        sort keys %{$hash->{HTTPCookieHash}}));
    
}

sub tahoma_encrypt($)
{
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /^crypt:(.*)/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'. $encoded;
}

sub tahoma_decrypt($)
{
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if not ( $encoded =~ /^crypt:(.*)/ );
  
  $encoded = $1 if( $encoded =~ /^crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }
  
  return $decoded;
}

1;

=pod
=item summary    commumication modul for io-homecontrol&reg gateway TaHoma&reg
=item summary_DE Kommunicationsmodul f&uuml;er io-homecontrol&reg Gateway TaHoma&reg
=begin html

<a name="tahoma"></a>
<h3>tahoma</h3>
<ul>
  The module realizes the communication with io-homecontrol&reg; Devices e.g. from Somfy&reg; or Velux&reg;<br>
  A registered TaHoma&reg; Connect gateway from Overkiz&reg; sold by Somfy&reg; which is continously connected to the internet is necessary for the module.<br>
  <br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
    <li>on problems refer also the fhem forum <a href="https://forum.fhem.de/index.php/topic,28045.0.html">IO-Homecontrol Devices &uuml;ber Tahoma Box einbinden</a></li>
  </ul><br>

  <a name="tahoma_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; tahoma ACCOUNT &lt;username&gt; &lt;password&gt;</code><br>
    <code>define &lt;name&gt; tahoma DEVICE &lt;DeviceURL&gt;</code><br>
    <code>define &lt;name&gt; tahoma PLACE &lt;oid&gt;</code><br>
    <code>define &lt;name&gt; tahoma SCENE &lt;oid&gt;</code><br>
    <code>define &lt;name&gt; tahoma GROUP &lt;tahoma_device1&gt;,&lt;tahoma_device2&gt;,&lt;tahoma_device3&gt;</code><br>
    <br>
    <br>
    A definition is only necessary for a tahoma device:<br>
    <code>define &lt;name&gt; tahoma ACCOUNT &lt;username&gt; &lt;password&gt;</code><br>
    <b>If a tahoma device of the type ACCOUNT is created, all other devices acessable by the tahoma gateway are automaticaly created!</b><br>
    If the account is valid, the setup will be read from the server.<br>
    All registrated devices are automatically created with name tahoma_12345 (device number 12345 is used from setup)<br>
    All defined rooms will be are automatically created.<br>
    Also all defined scenes will be automatically created.<br>
    Groups of devices can be manually added to send out one group command for all attached devices<br>
    <br>
    <br>
    <b>global Attributes for ACCOUNT:</b>
    <ul>
      If autocreate is disabled, no devices, places and scenes will be created automatically:<br>
      <code>attr autocreate disable</code><br>
    </ul>
    <br>
    <b>local Attributes for ACCOUNT:</b>
    <ul>
      Normally, the web commands will be send asynchron, and this can be forced to wait of the result by blocking=1<br>
      <code>attr tahoma1 blocking 1</code><br>
    </ul>
    <ul>
      Normally, the login data is stored encrypted after the first start, but this functionality can be disabled by cryptLoginData=0<br>
      <code>attr tahoma1 cryptLoginData 0</code><br>
    </ul>
    <br>
    <b>local Attributes for DEVICE:</b>
    <ul>
      If the closure value 0..100 should be 100..0, the level can be inverted:<br>
      <code>attr tahoma_23234545 levelInvert 1</code><br>
    </ul>
    <br>
    <b>local Attributes for PLACE:</b>
    <ul>
      The commands in a room will only affect the devices in the room with inClass=RollerShutter.<br>
      This can be extend or changed by setting the placeClasses attribut:<br>
      <code>attr tahoma_abc12345 placeClasses RollerShutter ExteriorScreen Window</code><br>
    </ul>
    <br>
    <b>Examples:</b>
    <ul>
      <code>define tahoma1 tahoma ACCOUNT abc@test.com myPassword</code><br>
      <code>attr tahoma1 blocking 0</code><br>
      <code>attr tahoma1 room tahoma</code><br>
      <br>
      <br>Automatic created device e.g.:<br>
      <code>define tahoma_23234545 tahoma DEVICE io://0234-5678-9012/23234545</code><br>
      <code>attr tahoma_23234545 IODev tahoma1</code><br>
      <code>attr tahoma_23234545 alias RollerShutter Badezimmer</code><br>
      <code>attr tahoma_23234545 room tahoma</code><br>
      <code>attr tahoma_23234545 webCmd dim</code><br>
      <br>
      <br>Automatic created place e.g.:<br>
      <code>define tahoma_abc12345 tahoma PLACE abc12345-0a23-0b45-0c67-d5e6f7a1b2c3</code><br>
      <code>attr tahoma_abc12345 IODev tahoma1</code><br>
      <code>attr tahoma_abc12345 alias room Wohnzimmer</code><br>
      <code>attr tahoma_abc12345 room tahoma</code><br>
      <br>
      <br>Automatic created scene e.g.:<br>
      <code>define tahoma_4ef30a23 tahoma SCENE 4ef30a23-0b45-0c67-d5e6-f7a1b2c32e3f</code><br>
      <code>attr tahoma_4ef30a23 IODev tahoma1</code><br>
      <code>attr tahoma_4ef30a23 alias scene Rolladen S&uuml;dfenster zu</code><br>
      <code>attr tahoma_4ef30a23 room tahoma</code><br>
      <br>
      <br>manual created group e.g.:<br>
      <code>define tahoma_group1 tahoma GROUP tahoma_23234545,tahoma_23234546,tahoma_23234547</code><br>
      <code>attr tahoma_group1 IODev tahoma1</code><br>
      <code>attr tahoma_group1 alias Gruppe Rolladen Westen</code><br>
      <code>attr tahoma_group1 room tahoma</code><br>
    </ul>
  </ul><br>
</ul>

=end html
=cut

###############################################################################
# $Id$
###############################################################################
#
# A module to control LaMetric.
#
# Based on version 1, written 2017 by
#   Matthias Kleine <info at haus-automatisierung.com>
#
# Also see API documentation:
# https://developer.lametric.com/
# http://lametric-documentation.readthedocs.io/en/latest/reference-docs/device-notifications.html

#TODO
#- implement key pinning to improve security for self-signed certificate
#- rtype replace of special characters that device cannot display:
#   0x00A0 -> " " space
#   0x202F -> " " space
#   0x00B2 -> "2" m2
#   0x00B3 -> "3" m3
#   0x0025 -> "%"
#   0x00B0 -> "°"
#- msgSchema (überlappende Parameter wie priority)
#-mehrere metric/chart/goal/msg frames des gleichen typs (derzeit gehen per msg nur 1x zusätzlich metric,chart,goal) -> reihenfolge?

package main;

use Data::Dumper;
use JSON qw(decode_json encode_json);
use Time::HiRes qw(gettimeofday time);
use Time::Local;
use IO::Socket::SSL;

use Encode;
use HttpUtils;
use SetExtensions;
use Unit;
use utf8;
use FHEM::Meta;

my %LaMetric2_sounds = (
    notifications => [
        'bicycle',      'car',           'cash',          'cat',
        'dog',          'dog2',          'energy',        'knock-knock',
        'letter_email', 'lose1',         'lose2',         'negative1',
        'negative2',    'negative3',     'negative4',     'negative5',
        'notification', 'notification2', 'notification3', 'notification4',
        'open_door',    'positive1',     'positive2',     'positive3',
        'positive4',    'positive5',     'positive6',     'statistic',
        'thunder',      'water1',        'water2',        'win',
        'win2',         'wind',          'wind_short'
    ],
    alarms => [
        'alarm1', 'alarm2', 'alarm3', 'alarm4',  'alarm5',  'alarm6',
        'alarm7', 'alarm8', 'alarm9', 'alarm10', 'alarm11', 'alarm12',
        'alarm13'
    ],
);

my %LaMetric2_sets = (
    msg            => '',
    chart          => '',
    goal           => '',
    metric         => '',
    app            => '',
    on             => ':noArg',
    off            => ':noArg',
    toggle         => ':noArg',
    power          => ':on,off',
    volume         => ':slider,0,1,100',
    volumeUp       => ':noArg',
    volumeDown     => ':noArg',
    mute           => ':on,off',
    muteT          => ':noArg',
    brightness     => ':slider,1,1,100',
    brightnessMode => ':auto,manual',
    bluetooth      => ':on,off',
    inputUp        => ':noArg',
    inputDown      => ':noArg',
    statusRequest  => ':noArg',
    screensaver    => ':off,when_dark,time_based',
);

my %LaMetric2_setsHidden = (
    msgCancel   => 1,
    input       => 1,
    refresh     => 1,
    channelUp   => 1,
    channelDown => 1,
    play        => 1,
    pause       => 1,
    stop        => 1,
);

my %LaMetric2_metrictype_icons = (

    # # length / Länge
    # 0 => {
    #     lm_icon => '', # nothing found :-(
    # },

    # mass / Masse
    1 => {
        lm_icon => 'i2721',
    },

    # time / Zeit
    2 => {
        lm_icon => 'i1820',
    },

    # electric current / elektrische Stromstärke
    3 => {
        lm_icon => 'a21256',
    },

    # absolute temperature / absolute Temperatur
    4 => {
        lm_icon => 'i2355',
    },

    # amount of substance / Stoffmenge
    5 => {
        lm_icon => 'i9027',
    },

    # luminous intensity / Lichtstärke
    6 => {
        lm_icon => 'a3711',
    },

    # energy / Energie
    7 => {
        lm_icon => 'a23725',
    },

    # frequency / Frequenz
    8 => {
        lm_icon => 'a14428',
    },

    # power / Leistung
    9 => {
        lm_icon => 'a21256',
    },

    # pressure / Druck
    10 => {
        lm_icon => 'i2356',
    },

    # absolute pressure / absoluter Druck
    11 => {
        lm_icon => 'i20768',
    },

    # air pressure / Luftdruck
    12 => {
        lm_icon => 'i2644',
    },

    # electric voltage / elektrische Spannung
    13 => {
        lm_icon => 'a15124',
    },

    # plane angular / ebener Winkel
    14 => {
        lm_icon => 'i8974',
    },

    # speed / Geschwindigkeit
    15 => {
        lm_icon => 'a21688',
    },

    # illumination intensity / Beleuchtungsstärke
    16 => {
        lm_icon => 'a24894',
    },

    # luminous flux / Lichtstrom
    17 => {
        lm_icon => 'a7876',
    },

    # volume / Volumen
    18 => {
        lm_icon => 'a3401',
    },

    # logarithmic level / Logarithmische Größe
    19 => {
        lm_icon => 'i12247',
    },

    # electric charge / elektrische Ladung
    20 => {
        lm_icon => 'a24125',
    },

    # electric capacity / elektrische Kapazität
    21 => {
        lm_icon => 'i389',
    },

    # electric resistance / elektrischer Widerstand
    22 => {
        lm_icon => 'i21860',
    },

    # surface area / Flächeninhalt
    23 => {
        lm_icon => 'a17519',
    },

    # currency / Währung
    24 => {
        lm_icon => 'i23003',
    },

    # numbering / Zahlen
    25 => {
        lm_icon => 'i9027',
    },
);

#------------------------------------------------------------------------------
sub LaMetric2_Initialize($$) {
    my ($hash) = @_;

    $hash->{DefFn}   = "LaMetric2_Define";
    $hash->{UndefFn} = "LaMetric2_Undefine";
    $hash->{SetFn}   = "LaMetric2_Set";

    my $notifications =
      join( ',', @{ $LaMetric2_sounds{notifications} } );
    my $alarms = join( ',', @{ $LaMetric2_sounds{alarms} } );

    $hash->{AttrList} =
        'disable:0,1 disabledForIntervals do_not_notify:0,1 model '
      . 'defaultOnStatus:always,illumination defaultScreensaverEndTime:00:00,00:15,00:30,00:45,01:00,01:15,01:30,01:45,02:00,02:15,02:30,02:45,03:00,03:15,03:30,03:45,04:00,04:15,04:30,04:45,05:00,05:15,05:30,05:45,06:00,06:15,06:30,06:45,07:00,07:15,07:30,07:45,08:00,08:15,08:30,08:45,09:00,09:15,09:30,09:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45 defaultScreensaverStartTime:00:00,00:15,00:30,00:45,01:00,01:15,01:30,01:45,02:00,02:15,02:30,02:45,03:00,03:15,03:30,03:45,04:00,04:15,04:30,04:45,05:00,05:15,05:30,05:45,06:00,06:15,06:30,06:45,07:00,07:15,07:30,07:45,08:00,08:15,08:30,08:45,09:00,09:15,09:30,09:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45 defaultVolume:slider,1,1,100 https:1,0 '
      . "notificationIcon:none,i8919,a11893,i22392,a12764 notificationIconType:none,info,alert notificationLifetime notificationPriority:info,warning,critical notificationSound:off,$notifications,$alarms "
      . "notificationChartIconType:none,info,alert notificationChartLifetime notificationChartPriority:info,warning,critical notificationChartSound:off,$notifications,$alarms "
      . "notificationGoalIcon:none,a11460 notificationGoalIconType:none,info,alert notificationGoalLifetime notificationGoalPriority:info,warning,critical notificationGoalSound:off,$notifications,$alarms notificationGoalStart notificationGoalEnd notificationGoalUnit "
      . "notificationMetricIcon:none,i9559 notificationMetricIconType:none,info,alert notificationMetricLang:en,de notificationMetricLifetime notificationMetricPriority:info,warning,critical notificationMetricSound:off,$notifications,$alarms notificationMetricUnit "
      . $readingFnAttributes;

    #$hash->{parseParams} = 1; # not possible due to legacy msg command schema
    $hash->{'.msgParams'} = { parseParams => 1, };

    return FHEM::Meta::Load( __FILE__, $hash );
}

#------------------------------------------------------------------------------
sub LaMetric2_Define($$) {
    my ( $hash, $def ) = @_;

    my @args = split( "[ \t]+", $def );

    return
"Invalid number of arguments: define <name> LaMetric2 <ip> <apikey> [<port>] [<interval>]"
      if ( int(@args) < 2 );

    my ( $name, $type, $host, $apikey, $port, $interval ) = @args;

    if ( defined($host) && defined($apikey) ) {

        return "$apikey does not seem to be a valid key"
          if ( $apikey !~ /^([a-f0-9]{64})$/ );

        # Initialize the device
        return $@ unless ( FHEM::Meta::SetInternals($hash) );

        $hash->{HOST}       = $host;
        $hash->{".API_KEY"} = $apikey;
        $hash->{INTERVAL} =
          $interval && looks_like_number($interval) ? $interval : 60;
        $hash->{PORT} = $port && looks_like_number($port) ? $port : 4343;

        # set default settings on first define
        if ( $init_done && !defined( $hash->{OLDDEF} ) ) {

            # presets for FHEMWEB
            $attr{$name}{cmdIcon} =
'play:rc_PLAY channelDown:rc_PREVIOUS channelUp:rc_NEXT stop:rc_STOP muteT:rc_MUTE inputUp:rc_RIGHT inputDown:rc_LEFT';
            $attr{$name}{devStateIcon} =
'on:rc_GREEN@green:off off:rc_STOP:on absent:rc_RED playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play muted:rc_MUTE@green:muteT fast-rewind:rc_REW@green:play fast-forward:rc_FF@green:play interrupted:rc_PAUSE@yellow:play';
            $attr{$name}{icon}        = 'time_statistic';
            $attr{$name}{stateFormat} = 'stateAV';
            $attr{$name}{webCmd} =
'volume:muteT:channelDown:play:stop:channelUp:inputDown:input:inputUp';

            # set those to make it easier for users to see the
            # default values. However, deleting those will
            # still use the same defaults in the code below.
            $attr{$name}{defaultOnStatus}             = "illumination";
            $attr{$name}{defaultScreensaverEndTime}   = "06:00";
            $attr{$name}{defaultScreensaverStartTime} = "00:00";
            $attr{$name}{defaultVolume}               = "50";
            $attr{$name}{https}                       = 1;

            $attr{$name}{notificationIcon}     = 'i8919';
            $attr{$name}{notificationIconType} = 'info';
            $attr{$name}{notificationLifetime} = '120';
            $attr{$name}{notificationPriority} = 'info';

            $attr{$name}{notificationGoalIcon}     = 'a11460';
            $attr{$name}{notificationGoalIconType} = 'info';
            $attr{$name}{notificationGoalLifetime} = '120';
            $attr{$name}{notificationGoalPriority} = 'info';
            $attr{$name}{notificationGoalStart}    = 0;
            $attr{$name}{notificationGoalEnd}      = 100;
            $attr{$name}{notificationGoalUnit}     = '%';

            $attr{$name}{notificationMetricIcon}     = 'i9559';
            $attr{$name}{notificationMetricIconType} = 'info';
            $attr{$name}{notificationMetricLang}     = 'en';
            $attr{$name}{notificationMetricLifetime} = '120';
            $attr{$name}{notificationMetricPriority} = 'info';
        }

        # start Validation Timer
        RemoveInternalTimer( $hash, 'LaMetric2_CheckState' );
        InternalTimer( gettimeofday() + 2, 'LaMetric2_CheckState', $hash, 0 );

        return undef;
    }
    else {
        return "IP or ApiKey missing";
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_Undefine($$) {
    my ( $hash, $name ) = @_;

    RemoveInternalTimer($hash);

    return undef;
}

#------------------------------------------------------------------------------
sub LaMetric2_Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;
    my ( $a, $h ) = parseParams( join " ", @args );

    if (   !defined( $LaMetric2_sets{$cmd} )
        && !defined( $LaMetric2_setsHidden{$cmd} ) )
    {
        my $usage =
            "Unknown argument "
          . $cmd
          . ", choose one of "
          . join( " ", map "$_$LaMetric2_sets{$_}", sort keys %LaMetric2_sets );

        $usage .=
          " msgCancel:" . join( ',', sort keys %{ $hash->{helper}{cancelIDs} } )
          if ( defined( $hash->{helper}{cancelIDs} )
            && keys %{ $hash->{helper}{cancelIDs} } > 0 );

        $usage .= " input:,";
        $usage .= encode_utf8(
            join( ',',
                map $hash->{helper}{inputs}{$_}{name},
                sort keys %{ $hash->{helper}{inputs} } )
          )
          if ( defined( $hash->{helper}{inputs} )
            && keys %{ $hash->{helper}{inputs} } > 0 );

        $usage .= " play:noArg stop:noArg channelUp:noArg channelDown:noArg"
          if ( defined( $hash->{helper}{apps}{'com.lametric.radio'} )
            && keys %{ $hash->{helper}{apps}{'com.lametric.radio'} } > 0 );

        return $usage;
    }

    return "Unable to set $cmd: Device is unreachable"
      if ( ReadingsVal( $name, 'presence', 'absent' ) eq 'absent'
        && lc($cmd) ne 'refresh'
        && lc($cmd) ne 'statusrequest' );

    return "Unable to set $cmd: Device is disabled"
      if ( IsDisabled($name) );

    return LaMetric2_SetOnOff( $hash, $cmd, @args )
      if ( $cmd eq 'on'
        || $cmd eq 'off'
        || $cmd eq 'toggle'
        || $cmd eq 'power' );
    return LaMetric2_SetScreensaver( $hash, @args )
      if ( $cmd eq 'screensaver' );
    return LaMetric2_SetVolume( $hash, $cmd, @args )
      if ( $cmd eq 'volume'
        || lc($cmd) eq 'volumeup'
        || lc($cmd) eq 'volumedown' );
    return LaMetric2_SetMute( $hash, @args )
      if ( $cmd eq 'mute'
        || lc($cmd) eq 'mutet' );
    return LaMetric2_SetBrightness( $hash, @args )
      if ( $cmd eq 'brightness' || lc($cmd) eq 'brightnessmode' );
    return LaMetric2_SetBluetooth( $hash, @args ) if ( $cmd eq 'bluetooth' );
    return LaMetric2_SetApp( $hash, $cmd, $h, @$a )
      if ( $cmd eq 'app'
        || lc($cmd) eq 'channelup'
        || lc($cmd) eq 'channeldown'
        || $cmd eq 'input'
        || lc($cmd) eq 'inputup'
        || lc($cmd) eq 'inputdown'
        || $cmd eq 'play'
        || $cmd eq 'pause'
        || $cmd eq 'stop' );
    return LaMetric2_CheckState( $hash, @args )
      if ( $cmd eq 'refresh' || lc($cmd) eq 'statusrequest' );

    return LaMetric2_SetCancelMessage( $hash, @args )
      if ( lc($cmd) eq 'msgcancel' );

    if ( $cmd eq 'msg' ) {

        # use new flexible msg command
        return LaMetric2_SetNotification( $hash, $a, $h )
          if ( join( " ", @args ) !~ m/^(".*"|'.*').*$/
            || ( defined($h) && keys %{$h} > 0 ) );

        # backwards compatibility for old-style msg command
        # of LaMetric2 v1 module
        return LaMetric2_SetMessage( $hash, @args );
    }
    elsif ( $cmd eq 'chart' ) {
        $h->{chart} = join( " ", @$a ) unless ( defined( $h->{chart} ) );
        return LaMetric2_SetNotification( $hash, undef, $h );
    }
    elsif ( $cmd eq 'goal' ) {
        $h->{goal} = join( " ", @$a ) unless ( defined( $h->{goal} ) );
        $h->{goalstart} = $h->{start} if ( defined( $h->{start} ) );
        $h->{goalend}   = $h->{end}   if ( defined( $h->{end} ) );
        $h->{goalunit}  = $h->{unit}  if ( defined( $h->{unit} ) );
        $h->{goaltype}  = $h->{type}  if ( defined( $h->{type} ) );
        return LaMetric2_SetNotification( $hash, undef, $h );
    }
    elsif ( $cmd eq 'metric' ) {
        $h->{metric} = join( " ", @$a ) unless ( defined( $h->{metric} ) );
        $h->{metricold}  = $h->{old}  if ( defined( $h->{old} ) );
        $h->{metricunit} = $h->{unit} if ( defined( $h->{unit} ) );
        $h->{metrictype} = $h->{type} if ( defined( $h->{type} ) );
        $h->{metriclang} = $h->{lang} if ( defined( $h->{lang} ) );
        $h->{metriclong} = 1
          if ( defined( $h->{txt} ) || defined( $h->{long} ) );
        return LaMetric2_SetNotification( $hash, undef, $h );
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_SendCommand {
    my ( $hash, $service, $httpMethod, $data, $info ) = @_;

    my $apiKey = $hash->{".API_KEY"};
    my $name   = $hash->{NAME};
    my $host   = $hash->{HOST};
    my $port   = $hash->{PORT};
    my $apiVersion;
    my $httpNoShutdown = ( defined( $attr{$name}{"http-noshutdown"} )
          && $attr{$name}{"http-noshutdown"} eq "0" ) ? 0 : 1;
    my $timeout = 5;
    my $http_proto;

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_SendCommand()";

    # API version was included to service
    if ( $service =~ /^v\d+\// ) {
        $apiVersion = "";
    }

    # dev options currently only via API v1
    elsif ( $service =~ /^dev\// ) {
        $apiVersion = "v1/";
    }

    # module internal pre-defined version
    else {
        $apiVersion = "v2/";
    }

    $data = ( defined($data) ) ? $data : "";

    my $https = AttrVal( $name, "https", 1 );
    if ($https) {
        $http_proto = "https";
        $port = 4343 if ( $port == 8080 );
    }
    else {
        $http_proto = "http";
        $port = 8080 if ( $port == 4343 );
    }
    $hash->{PORT} = $port;

    my %header = (
        Agent            => 'FHEM-LaMetric2/' . $hash->{VERSION},
        'User-Agent'     => 'FHEM-LaMetric2/' . $hash->{VERSION},
        Accept           => 'application/json;charset=UTF-8',
        'Accept-Charset' => 'UTF-8',
        'Cache-Control'  => 'no-cache',
    );

    if ( defined( $info->{token} ) ) {
        $header{'X-Access-Token'} = $info->{token};
    }
    else {
        $header{'Authorization'} =
          'Basic ' . encode_base64( 'dev:' . $apiKey, "" );
    }

    my $url =
        $http_proto . "://"
      . $host . ":"
      . $port . "/api/"
      . $apiVersion
      . $service;

    $httpMethod = "GET"
      if ( $httpMethod eq "" );

    # Append data to URL if method is GET
    if ( $httpMethod eq "GET" ) {
        $url .= "?" . $data;
        $data = undef;
    }
    elsif ( $httpMethod eq "POST" || $httpMethod eq "PUT" ) {
        $header{'Content-Type'} = 'application/json;charset=UTF-8';
    }

    # send request
    Log3 $name, 5,
        "LaMetric2 $name: "
      . $httpMethod . " "
      . urlDecode($url)
      . " (DATA: "
      . $data
      . " (noshutdown="
      . $httpNoShutdown . ")";

    HttpUtils_NonblockingGet(
        {
            method      => $httpMethod,
            url         => $url,
            timeout     => $timeout,
            noshutdown  => $httpNoShutdown,
            data        => $data,
            info        => $info,
            hash        => $hash,
            service     => $service,
            header      => \%header,
            callback    => \&LaMetric2_ReceiveCommand,
            httpversion => "1.1",
            loglevel    => AttrVal( $name, "httpLoglevel", 4 ),
            sslargs     => {
                SSL_verify_mode => 0,
            },
        }
    );

    return;
}

#------------------------------------------------------------------------------
sub LaMetric2_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    my $method  = $param->{method};
    my $service = $param->{service};
    my $info    = $param->{info};
    my $code    = $param->{code};
    my $result  = ();

    Log3 $name, 5,
"LaMetric2 $name: called function LaMetric2_ReceiveCommand() for service '$service':"
      . "\n\nERROR: $err\n"
      . "HTTP RESPONSE HEADER:\n"
      . $param->{httpheader}
      . "\n\nHTTP RESPONSE BODY:\n"
      . $data;

    my $state = ReadingsVal( $name, "state", "initialized" );
    my $power = ReadingsVal( $name, "power", "off" );

    readingsBeginUpdate($hash);

    # service not reachable
    if ($err) {
        readingsBulkUpdateIfChanged( $hash, "presence", "absent" );
        $state = "absent";
        $power = "off";
    }
    elsif ($data) {
        readingsBulkUpdateIfChanged( $hash, "presence", "present" );

        $result = "success";

        if ( $code >= 200 && $code < 300 ) {

            # set response data as reading if verbose level is >3
            $result = encode_utf8($data)
              if ( $method ne "GET" && AttrVal( $name, "verbose", 3 ) > 3 );

            my $response = decode_json( encode_utf8($data) );

            # React on device return data
            #

            if ( $service eq "device/notifications" && $method eq "POST" ) {
                my $cancelID = $info->{cancelID};
                $hash->{helper}{cancelIDs}{$cancelID} = $response->{success}{id}
                  if ($cancelID);
            }
            elsif ( $service eq "device/notifications" && $method eq "GET" ) {
                my $cancelIDs            = {};
                my $notificationIDs      = {};
                my $oldestTimestamp      = time;
                my $oldestNotificationID = "";
                my $oldestCancelID       = "";

                # Get a hash of all IDs and their infos in the response
                foreach my $notification ( @{$response} ) {
                    my ( $year, $mon, $mday, $hour, $min, $sec ) =
                      split( /[\s-:T]+/, $notification->{created} );
                    my $time =
                      timelocal( $sec, $min, $hour, $mday, $mon - 1, $year );

                    $notificationIDs->{ $notification->{id} } = {
                        time => $time,
                        text => $notification->{model}{frames}[0]{text},
                        icon => $notification->{model}{frames}[0]{icon},
                    };
                }

                # Filter local cancelIDs by only keeping
                # the ones that still exist on the lametric device
                foreach my $key ( keys %{ $hash->{helper}{cancelIDs} } ) {
                    my $value = $hash->{helper}{cancelIDs}{$key};

                    if ( exists $notificationIDs->{$value} ) {
                        $cancelIDs->{$key} = $value;

                        # Determinate oldest notification for auto-cycling
                        $timestamp = $notificationIDs->{$value}{time};

                        if ( $timestamp < $oldestTimestamp ) {
                            $oldestCancelID       = $key;
                            $oldestNotificationID = $value;
                            $oldestTimestamp      = $timestamp;
                        }
                    }
                }

                $hash->{helper}{cancelIDs} = $cancelIDs;

                # Update was triggered by LaMetric2_SetCancelMessage?
                # Send DELETE request if notification still exists on device
                my $cancelID = $info->{cancelID};
                if (   exists $info->{cancelID}
                    && exists $hash->{helper}{cancelIDs}{$cancelID} )
                {
                    $notificationID = $hash->{helper}{cancelIDs}{$cancelID};
                    delete $hash->{helper}{cancelIDs}{$cancelID};

                    LaMetric2_SendCommand( $hash,
                        "device/notifications/$notificationID", "DELETE" );
                }

                # Update was triggered by LaMetric2_CycleMessage?
                # -> Remove oldest (currently displayed) message and post
                #    it again at the end of the queue
                if ( exists $info->{caller}
                    && $info->{caller} eq "CycleMessage" )
                {
                    delete $hash->{helper}{cancelIDs}{$oldestCancelID};
                    LaMetric2_SendCommand( $hash,
                        "device/notifications/$oldestNotificationID",
                        "DELETE" );
                    LaMetric2_SetMessage( $hash,
"'$notificationIDs->{$oldestNotificationID}{icon}' '$notificationIDs->{$oldestNotificationID}{text}' '' '' '$oldestCancelID'"
                    );
                }
            }
            elsif ( $service eq "device/display" && $method eq "PUT" ) {

                # screensaver time was updated but final
                # mode should not be time_based
                return LaMetric2_SetScreensaver( $hash, $info->{caller} )
                  if ( defined( $info->{caller} ) );
            }

            # API version >= 2.1.0
            elsif ( $service eq "device/apps" && $method eq "GET" ) {
                $hash->{helper}{apps} = $response;
                delete $hash->{helper}{inputs}
                  if ( defined( $hash->{helper}{inputs} ) );

                foreach my $app ( sort keys %{$response} ) {

                    # widgets
                    foreach
                      my $widgetId ( sort keys %{ $response->{$app}{widgets} } )
                    {
                        my $inputName;

                        if ( $response->{$app}{widgets}{$widgetId}{settings}
                            {_title} )
                        {
                            $inputName .=
                              $response->{$app}{widgets}{$widgetId}{settings}
                              {_title};
                        }
                        else {
                            $inputName .= $response->{$app}{title};
                        }
                        $inputName =~ s/\s/_/g;

                        my $i          = 1;
                        my $inputName2 = lc($inputName);
                        while (
                            defined( $hash->{helper}{inputs}{$inputName2} ) )
                        {
                            $i++;
                            $inputName2 = lc( $inputName . "_" . $i );
                        }
                        $inputName .= "_" . $i if ( $i > 1 );

                        my $vendorId;
                        my $appId;

                        if ( $response->{$app}{package} =~ /^(.+)\.([^.]+)$/ ) {
                            $vendorId = $1;
                            $appId    = $2;
                        }

                        $hash->{helper}{inputs}{ lc($inputName) } = (
                            {
                                'name'       => $inputName,
                                'package_id' => $response->{$app}{package},
                                'vendor_id'  => $vendorId,
                                'app_id'     => $appId,
                                'widget_id'  => $widgetId,
                            }
                        );
                    }
                }
            }
            elsif ( $service =~ /^device\/apps\/.+\/widgets\/.+\/actions/ ) {

            }

            # Update readings
            #

            # If we received a response to a write command,
            # make that data available
            if ( $method ne "GET" && $method ne "DELETE" ) {
                my $endpoint = $response->{success}->{path};
                $endpoint =~ s/^(.*[\\\/])//;
                $response->{$endpoint} = $response->{success}{data};
            }
            elsif ( $service eq "device/display" ) {
                $response->{display} = $response;
            }

            if ( $service eq "device" ) {
                readingsBulkUpdateIfChanged( $hash, "deviceName",
                    $response->{name} );
                readingsBulkUpdateIfChanged( $hash, "deviceSerialNumber",
                    $response->{serial_number} );
                readingsBulkUpdateIfChanged( $hash, "deviceOsVersion",
                    $response->{os_version} );
                readingsBulkUpdateIfChanged( $hash, "deviceMode",
                    $response->{mode} );

                # write model to INTERNAL and attribute
                # to accomodate FHEM device use statistics
                $hash->{MODEL} = $response->{model};
                $attr{$name}{model} = $response->{model};

                # Trigger update of additional readings
                LaMetric2_SendCommand( $hash, "device/apps",    "GET", "" );
                LaMetric2_SendCommand( $hash, "device/display", "GET", "" );
            }

            if ( ref($response) eq "HASH" ) {

                if ( defined( $response->{audio} ) ) {

                    # audio is muted
                    if ( $response->{audio}{volume} == 0 ) {
                        readingsBulkUpdateIfChanged( $hash, "mute", "on" );

                        my $currVolume = ReadingsVal( $name, "volume", 50 );
                        $hash->{helper}{lastVolume} = $currVolume
                          if ( $currVolume > 0 );
                    }

                    # audio is not muted
                    else {
                        readingsBulkUpdateIfChanged( $hash, "mute", "off" );
                        delete $hash->{helper}{lastVolume}
                          if ( defined( $hash->{helper}{lastVolume} ) );
                    }

                    readingsBulkUpdateIfChanged( $hash, "volume",
                        $response->{audio}{volume} );
                }

                if ( defined( $response->{bluetooth} ) ) {
                    if ( $response->{bluetooth}{active} == 1 ) {
                        readingsBulkUpdateIfChanged( $hash, "bluetooth", "on" );
                    }
                    else {
                        readingsBulkUpdateIfChanged( $hash, "bluetooth",
                            "off" );
                    }

                    readingsBulkUpdateIfChanged( $hash, "bluetoothAvailable",
                        $response->{bluetooth}{available} );
                    readingsBulkUpdateIfChanged( $hash, "bluetoothName",
                        $response->{bluetooth}{name} );
                    readingsBulkUpdateIfChanged( $hash, "bluetoothDiscoverable",
                        $response->{bluetooth}{discoverable} );
                    readingsBulkUpdateIfChanged( $hash, "bluetoothPairable",
                        $response->{bluetooth}{pairable} );
                    readingsBulkUpdateIfChanged( $hash, "bluetoothAddress",
                        $response->{bluetooth}{address} );
                }

                if ( defined( $response->{display} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "brightness",
                        $response->{display}{brightness} );
                    readingsBulkUpdateIfChanged( $hash, "brightnessMode",
                        $response->{display}{brightness_mode} );

                    $state = "on";
                    $power = "on";

                    # only API version >= 2.1.0
                    if ( defined( $response->{display}{screensaver} ) ) {
                        my $screensaver = "off";

                        if ( $response->{display}{screensaver}{enabled} == 1 ) {
                            foreach (
                                keys
                                %{ $response->{display}{screensaver}{modes} } )
                            {
                                if ( $response->{display}{screensaver}{modes}
                                    {$_}{enabled} == 1 )
                                {
                                    $screensaver = $_;
                                    last;
                                }
                            }
                        }
                        my $screensaverStartTime = LaMetric2_gmtime_str2local(
                            $response->{display}{screensaver}{modes}{time_based}
                              {start_time} );
                        my $screensaverEndTime = LaMetric2_gmtime_str2local(
                            $response->{display}{screensaver}{modes}{time_based}
                              {end_time} );

                        readingsBulkUpdateIfChanged( $hash, "screensaver",
                            $screensaver );
                        readingsBulkUpdateIfChanged( $hash,
                            "screensaverStartTime", $screensaverStartTime );
                        readingsBulkUpdateIfChanged( $hash,
                            "screensaverEndTime", $screensaverEndTime );

                        if (
                            $screensaver eq "time_based"
                            && LaMetric2_IsDuringTimeframe(
                                $screensaverStartTime, $screensaverEndTime
                            )
                          )
                        {
                            $state = "off";
                            $power = "off";
                        }
                    }
                }

                if ( defined( $response->{wifi} ) ) {
                    readingsBulkUpdateIfChanged( $hash, "wifiActive",
                        $response->{wifi}{active} );
                    readingsBulkUpdateIfChanged( $hash, "wifiAddress",
                        $response->{wifi}{address} );
                    readingsBulkUpdateIfChanged( $hash, "wifiAvailable",
                        $response->{wifi}{available} );
                    readingsBulkUpdateIfChanged( $hash, "wifiEncryption",
                        $response->{wifi}{encryption} );
                    readingsBulkUpdateIfChanged( $hash, "wifiEssid",
                        $response->{wifi}{essid} );
                    readingsBulkUpdateIfChanged( $hash, "wifiIp",
                        $response->{wifi}{ip} );
                    readingsBulkUpdateIfChanged( $hash, "wifiMode",
                        $response->{wifi}{mode} );
                    readingsBulkUpdateIfChanged( $hash, "wifiNetmask",
                        $response->{wifi}{netmask} );

                    # Always trigger notification to allow
                    # plotting of this value
                    readingsBulkUpdate( $hash, "wifiStrength",
                        $response->{wifi}{strength} );
                }
            }

        }
        else {
            $result = "Server error " . $code . ": " . encode_utf8($data);
        }

        # Do not show read-only commands in readings
        if ( $method ne "GET" || $result ne "success" ) {
            readingsBulkUpdate( $hash, "lastCommand",
                $service . " (" . $method . ")" );
            readingsBulkUpdate( $hash, "lastCommandResult", $result );
        }
    }

    readingsBulkUpdateIfChanged( $hash, "power", $power );
    readingsBulkUpdateIfChanged( $hash, "state", $state );
    readingsBulkUpdateIfChanged( $hash, "stateAV",
        LaMetric2_GetStateAV($hash) );

    readingsEndUpdate( $hash, 1 );

    return;
}

#------------------------------------------------------------------------------
sub LaMetric2_CheckState($;$) {
    my ( $hash, $update ) = @_;

    my $name = $hash->{NAME};

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_CheckState()";

    RemoveInternalTimer( $hash, 'LaMetric2_CheckState' );

    if ( AttrVal( $name, "disable", 0 ) == 1 ) {

        # Retry in INTERVAL*5 seconds
        InternalTimer( gettimeofday() + ( $hash->{INTERVAL} * 5 ),
            'LaMetric2_CheckState', $hash, 0 );

        return;
    }
    else {
        # only get specific fields and exclude those we query sequentially
        LaMetric2_SendCommand( $hash, "device", "GET",
"fields=name,serial_number,os_version,mode,model,audio,bluetooth,wifi"
        );

        InternalTimer( gettimeofday() + $hash->{INTERVAL},
            'LaMetric2_CheckState', $hash, 0 );
    }

    return;
}

#------------------------------------------------------------------------------
sub LaMetric2_CycleMessage {
    my $hash  = shift;
    my $name  = $hash->{NAME};
    my $info  = {};
    my $count = keys %{ $hash->{helper}{cancelIDs} };

    $info->{caller} = "CycleMessage";

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_CycleMessage()";

    if ( $count >= 2 ) {
        InternalTimer( gettimeofday() + 5, "LaMetric2_CycleMessage", $hash, 0 );

        # Update notification queue first to see which is the
        # oldest notification. Callback will send the real cycle
        LaMetric2_SendCommand( $hash, "device/notifications", "GET", undef,
            $info );
    }

    return;
}

#------------------------------------------------------------------------------
sub LaMetric2_SetBrightness {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my %values = ();

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_SetBrightness()";

    my ($brightness) = @_;

    if ($brightness) {
        my %body = ( brightness_mode => $brightness );

        if ( looks_like_number($brightness) ) {
            $body{brightness}      = $brightness;
            $body{brightness_mode} = "manual";
        }

        LaMetric2_SendCommand( $hash, "device/display", "PUT",
            encode_json( \%body ) );

        return;
    }
    else {
        # There was a problem with the arguments
        return "Syntax: set $name brightness 1-100|auto|manual";
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_SetScreensaver {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my $info   = {};
    my %values = ();

    Log3 $name, 5,
      "LaMetric2 $name: called function LaMetric2_SetScreensaver()";

    my ( $screensaver, $startTime, $endTime ) = @_;

    if ( $screensaver eq "time_based" || ( $startTime && $endTime ) ) {
        my $sT =
          ReadingsVal( $name, "screensaverStartTime",
            AttrVal( $name, "defaultScreensaverStartTime", "00:00:00" ) );
        my $eT =
          ReadingsVal( $name, "screensaverEndTime",
            AttrVal( $name, "defaultScreensaverEndTime", "00:06:00" ) );

        if ( $startTime && $endTime ) {
            $startTime .= ":00" if ( $startTime =~ /^\d{2}:\d{2}$/ );
            $endTime   .= ":00" if ( $endTime =~ /^\d{2}:\d{2}$/ );
            $sT = $startTime;
            $eT = $endTime;
        }

        my %body = (
            screensaver => {
                enabled     => 1,
                mode        => 'time_based',
                mode_params => {
                    enabled    => 1,
                    start_time => LaMetric2_localtime_str2gm($sT),
                    end_time   => LaMetric2_localtime_str2gm($eT),
                },
            },
        );

        $info->{caller} = $screensaver if ( $screensaver ne "time_based" );

        LaMetric2_SendCommand( $hash, "device/display", "PUT",
            encode_json( \%body ), $info );
    }
    elsif ( $screensaver eq "off" || $screensaver ne "time_based" ) {
        my %body = (
            screensaver => {
                enabled => 0,
            },
        );

        if ( $screensaver ne "off" ) {
            $body{screensaver}{enabled}           = 1;
            $body{screensaver}{mode}              = $screensaver;
            $body{screensaver}{mode}{mode_params} = (
                {
                    enabled => 1,
                }
            );
        }

        LaMetric2_SendCommand( $hash, "device/display", "PUT",
            encode_json( \%body ), $info );
    }
    else {
        return
"Syntax: set $name screensaver off|when_dark|time_based [startTime] [endTime]";
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_SetBluetooth {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my %values = ();

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_SetBluetooth()";

    my ($bluetooth) = @_;

    if ( $bluetooth eq "on" || $bluetooth eq "off" ) {
        my %body = ( active => 0 );

        if ( $bluetooth eq "on" ) {
            $body{active} = 1;
        }

        LaMetric2_SendCommand( $hash, "device/bluetooth", "PUT",
            encode_json( \%body ) );

        return;
    }
    else {
        # There was a problem with the arguments
        return "Syntax: set $name bluetooth on|off ['new name']";
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_SetOnOff {
    my $hash = shift;
    my $cmd  = shift;
    my $name = $hash->{NAME};

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_SetOnOff() $cmd";

    my $body;
    my ($power) = @_;
    $cmd = $power if ($power);
    my $currPower = ReadingsVal( $name, "power", "on" );

    if ( $cmd eq "toggle" ) {
        $cmd = "on"  if ( $currPower eq "off" );
        $cmd = "off" if ( $currPower eq "on" );
    }

    if ( $cmd eq "off" ) {
        my $currScreensaverStartTime =
          ReadingsVal( $name, "screensaverStartTime", undef );
        my $currScreensaverEndTime =
          ReadingsVal( $name, "screensaverEndTime", undef );

        if (   defined($currScreensaverStartTime)
            && defined($currScreensaverEndTime)
            && $currScreensaverStartTime ne "00:00:00"
            && $currScreensaverEndTime ne "23:59:59" )
        {
            $hash->{helper}{lastScreensaverStartTime} =
              $currScreensaverStartTime;
            $hash->{helper}{lastScreensaverEndTime} = $currScreensaverEndTime;
        }

        return LaMetric2_SetScreensaver( $hash, "time_based", "00:00:00",
            "23:59:59" );
    }
    elsif ( $cmd eq "on" ) {
        my $screensaver = "when_dark";
        my $onStatus = AttrVal( $name, "defaultOnStatus", "illumination" );
        $screensaver = "off" if ( $onStatus eq "always" );

        my $ret = LaMetric2_SetScreensaver(
            $hash,
            $screensaver,
            defined( $hash->{helper}{lastScreensaverStartTime} )
            ? $hash->{helper}{lastScreensaverStartTime}
            : AttrVal( $name, "defaultScreensaverStartTime", "00:00:00" ),
            defined( $hash->{helper}{lastScreensaverEndTime} )
            ? $hash->{helper}{lastScreensaverEndTime}
            : AttrVal( $name, "defaultScreensaverEndTime", "06:00:00" )
        );

        delete $hash->{helper}{lastScreensaverStartTime}
          if ( defined( $hash->{helper}{lastScreensaverStartTime} ) );
        delete $hash->{helper}{lastScreensaverEndTime}
          if ( defined( $hash->{helper}{lastScreensaverEndTime} ) );

        return $ret;
    }
    else {
        # There was a problem with the arguments
        return "Syntax: set $name power on|off|toggle";
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_SetVolume {
    my $hash = shift;
    my $cmd  = shift;
    my $name = $hash->{NAME};

    Log3 $name, 5,
      "LaMetric2 $name: called function LaMetric2_SetVolume() $cmd";

    my %body       = ();
    my ($volume)   = @_;
    my $currVolume = ReadingsVal( $name, "volume", 0 );

    if ( looks_like_number($volume) ) {
        $body{volume} = $volume;
    }
    elsif ( lc($cmd) eq "volumeup" ) {
        $currVolume   = $currVolume + 10;
        $currVolume   = 100 if ( $currVolume > 100 );
        $body{volume} = $currVolume;
    }
    elsif ( lc($cmd) eq "volumedown" ) {
        $currVolume   = $currVolume - 10;
        $currVolume   = 0 if ( $currVolume < 0 );
        $body{volume} = $currVolume;
    }
    else {
        # There was a problem with the arguments
        return "Syntax: set $name volume 1-100";
    }

    LaMetric2_SendCommand( $hash, "device/audio", "PUT",
        encode_json( \%body ) );
}

#------------------------------------------------------------------------------
sub LaMetric2_SetMute {
    my $hash = shift;
    my $name = $hash->{NAME};

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_SetMute()";

    my ($mute) = @_;

    my %body = ();
    my $volume = ReadingsVal( $name, "volume", 0 );
    if ( $mute eq "on" || ( $mute eq "" && $volume != 0 ) ) {
        $body{volume} = "0";
    }
    elsif ( $mute eq "off" || ( $mute eq "" && $volume == 0 ) ) {
        $volume =
            $hash->{helper}{lastVolume}
          ? $hash->{helper}{lastVolume}
          : AttrVal( $name, "defaultVolume", 50 );
        $body{volume} = $volume;
    }
    else {
        # There was a problem with the arguments
        return "Syntax: set $name [mute|muteT] [on|off]";
    }

    LaMetric2_SendCommand( $hash, "device/audio", "PUT",
        encode_json( \%body ) );
}

#------------------------------------------------------------------------------
sub LaMetric2_SetApp {
    my $hash    = shift;
    my $cmd     = shift;
    my $h       = shift;
    my $package = decode_utf8(shift);
    my $action  = shift;
    my $name    = $hash->{NAME};

    # inject action for Radio app
    if ( lc($cmd) eq "channeldown" ) {
        $cmd     = "app";
        $package = "com.lametric.radio";
        $action  = "radio.prev";
    }
    elsif ( lc($cmd) eq "channelup" ) {
        $cmd     = "app";
        $package = "com.lametric.radio";
        $action  = "radio.next";
    }
    elsif ( lc($cmd) eq "play" ) {
        $cmd     = "app";
        $package = "com.lametric.radio";
        $action  = "radio.play";
    }
    elsif ( lc($cmd) eq "stop" || lc($cmd) eq "pause" ) {
        $cmd     = "app";
        $package = "com.lametric.radio";
        $action  = "radio.stop";
    }

    Log3 $name, 5,
        "LaMetric2 $name: called function LaMetric2_SetApp() "
      . $cmd . " / "
      . $package;

    if ( lc($cmd) eq "inputup" ) {
        LaMetric2_SendCommand( $hash, "device/apps/next", "PUT", "" );
    }
    elsif ( lc($cmd) eq "inputdown" ) {
        LaMetric2_SendCommand( $hash, "device/apps/prev", "PUT", "" );
    }
    elsif ( ( $cmd eq "app" || $cmd eq "input" )
        && $package )
    {

        my $packageId;
        my $widgetId;
        my $vendorId;
        my $appId;
        my $actionId;

        # user gave widget display name as package name
        if ( defined( $hash->{helper}{inputs}{ lc($package) } ) ) {
            $packageId = $hash->{helper}{inputs}{ lc($package) }{package_id};
            $widgetId  = $hash->{helper}{inputs}{ lc($package) }{widget_id};
            $vendorId  = $hash->{helper}{inputs}{ lc($package) }{vendor_id};
            $appId     = $hash->{helper}{inputs}{ lc($package) }{app_id};
        }
        else {
            # user gave packageId as package name
            if ( defined( $hash->{helper}{apps}{$package} ) ) {
                $packageId = $package;
            }

            # find packageId
            else {
                foreach my $id ( keys %{ $hash->{helper}{apps} } ) {
                    if ( $hash->{helper}{apps}{$id}{package} =~ /\.$package$/ )
                    {
                        $packageId = $hash->{helper}{apps}{$id}{package};
                        last;
                    }
                }
            }

            # if we now know the packageId, find widgetId
            if ($packageId) {
                my %widgetlist = ();
                foreach my $id (
                    keys %{ $hash->{helper}{apps}{$packageId}{widgets} } )
                {
                    $widgetlist{ $hash->{helper}{apps}{$packageId}{widgets}{$id}
                          {index} } = $id;
                }

                # best guess for widgetId:
                # use ID with lowest index
                my @widgets = sort keys %widgetlist;
                $widgetId = $widgetlist{ $widgets[0] };
            }

            # user gave widgetId as package name
            unless ($widgetId) {
                foreach my $id ( keys %{ $hash->{helper}{inputs} } ) {
                    if ( $hash->{helper}{inputs}{$id}{widget_id} eq $id ) {
                        $packageId =
                          $hash->{helper}{inputs}{$id}{package_id};
                        $widgetId =
                          $hash->{helper}{inputs}{$id}{widget_id};
                        last;
                    }
                }
            }
        }

        # only continue if widget exists
        unless ( $packageId && $widgetId ) {
            return "Unable to find widget for $package";
        }

        # get vendor and app ID
        if ( $packageId && ( !$vendorId || !$appId ) ) {
            if ( $packageId =~ /^(.+)\.([^.]+)$/ ) {
                $vendorId = $1;
                $appId    = $2;
            }
        }

        # user wants to push data to a non-public indicator app
        if (
               $action
            && ( $action eq "push" || $action eq $appId . ".push" )
            && !defined( $hash->{helper}{apps}{$packageId}{actions}{$action} )
            && !defined(
                $hash->{helper}{apps}{$packageId}{actions}
                  { $appId . "." . $action }
            )
          )
        {

            # Ready to send to app
            if ( defined( $h->{model} ) && defined( $h->{model}{frames} ) ) {
                return "Missing app token"
                  unless ( defined( $h->{token} ) );

                return "Missing frame data"
                  unless ( ref( $h->{model}{frames} ) eq "ARRAY" );

                my %body = ();
                my $info;
                $info->{token} = $h->{token};
                $body{frames} = $h->{model}{frames};

                LaMetric2_SendCommand(
                    $hash,
                    "dev/widget/update/$packageId/"
                      . $hash->{helper}{apps}{$packageId}{version_code}
                      . ( $h->{channels} ? "?channels=" . $h->{channels} : "" ),
                    "POST",
                    encode_json( \%body ),
                    $info
                );
            }

            # first parse it using msg setter
            else {
                $h->{app} = $packageId;
                return LaMetric2_SetNotification( $hash, \@_, $h );
            }
        }

        # user gave action parameter for public app
        elsif ($action) {

            # find actionId
            if (
                defined( $hash->{helper}{apps}{$packageId}{actions}{$action} ) )
            {
                $actionId = $action;
            }
            elsif (
                defined(
                    $hash->{helper}{apps}{$packageId}{actions}
                      { $appId . "." . $action }
                )
              )
            {
                $actionId = $appId . "." . $action;
            }

            return "Unknown action $action" unless ($actionId);

            my %body = ( id => $actionId );
            $body{params} = $h if ($h);

            LaMetric2_SendCommand( $hash,
                "device/apps/$packageId/widgets/$widgetId/actions",
                "POST", encode_json( \%body ) );
        }

        # user wants to switch to widget
        else {
            LaMetric2_SendCommand( $hash,
                "device/apps/$packageId/widgets/$widgetId/activate",
                "PUT", "" );
        }
    }
    else {
        # There was a problem with the arguments
        return
"Syntax: set $name $cmd <app_name> [<action> [param1=value param2=value ...] ]";
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_SetMessage {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my %values = ();
    my $info   = {};

    Log3 $name, 5, "LaMetric2 $name: called function LaMetric2_SetMessage()";

    #Split parameters
    my $param = join( " ", @_ );
    my $argc = 0;

    if ( $param =~
/(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*$/s
      )
    {
        $argc = 5;
    }
    elsif (
        $param =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*$/s )
    {
        $argc = 4;
    }
    elsif ( $param =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*$/s ) {
        $argc = 3;
    }
    elsif ( $param =~ /(".*"|'.*')\s*(".*"|'.*')\s*$/s ) {
        $argc = 2;
    }
    elsif ( $param =~ /(".*"|'.*')\s*$/s ) {
        $argc = 1;
    }

    Log3 $name, 4, "LaMetric2 $name: Found $argc argument(s)";

    if ( $argc == 1 ) {
        $values{message} = $1;
        Log3 $name, 4, "LaMetric2 $name: message = $values{message}";
    }
    else {
        $values{icon}    = $1 if ( $argc >= 1 );
        $values{message} = $2 if ( $argc >= 2 );
        $values{sound}   = $3 if ( $argc >= 3 );
        $values{repeat}  = $4 if ( $argc >= 4 );
        $values{cycles}  = $5 if ( $argc >= 5 );
    }

    #Remove quotation marks
    if ( $values{icon} =~ /^['"](.*)['"]$/s ) {
        $values{icon} = $1;
    }
    if ( $values{message} =~ /^['"](.*)['"]$/s ) {
        $values{message} = $1;
    }
    if ( $values{sound} =~ /^['"](.*)['"]$/s ) {
        $values{sound} = $1;
    }
    if ( $values{repeat} =~ /^['"](.*)['"]$/s ) {
        $values{repeat} = $1;
    }
    if ( $values{cycles} =~ /^['"](.*)['"]$/s ) {
        $values{cycles} = $1;
    }

    # inject to new function
    return LaMetric2_SetNotification( $hash, undef, \%values );
}

#------------------------------------------------------------------------------
sub LaMetric2_SetNotification {
    my ( $hash, $a, $h ) = @_;
    my $name   = $hash->{NAME};
    my %values = ();
    my $info   = {};

    Log3 $name, 5,
      "LaMetric2 $name: called function LaMetric2_SetNotification()";

    # Set defaults for object
    $notificationType = "msg";
    $values{icontype} =
        $h->{icontype}
      ? $h->{icontype}
      : AttrVal( $name, "notificationIconType", "info" );
    $values{icontype} = "none" if ( $values{title} && $values{title} ne "" );
    $values{lifetime} =
        $h->{lifetime}
      ? $h->{lifetime}
      : AttrVal( $name, "notificationLifetime", 120 );
    $values{priority} =
        $h->{priority}
      ? $h->{priority}
      : AttrVal( $name, "notificationPriority", "info" );

    # Set defaults for model
    $values{sound} =
        $h->{sound}
      ? $h->{sound}
      : AttrVal( $name, "notificationSound", "" );
    $values{sound} = ""
      if ( $values{sound} eq "none" || $values{sound} eq "off" );
    $values{repeat} =
        $h->{repeat}
      ? $h->{repeat}
      : 1;
    $values{cycles} =
      defined( $h->{cycles} )
      ? $h->{cycles}
      : 1;

    # Set defaults for frames
    $values{icon} =
      $h->{icon} ? $h->{icon} : AttrVal( $name, "notificationIcon", "i8919" );
    $values{icon} = "" if ( $values{icon} eq "none" );

    # special text frame at the beginning
    $values{title} = $h->{title} ? $h->{title} : "";

    # text frame(s)
    $values{message} =
      $h->{message} ? $h->{message}
      : (
        $h->{msg} ? $h->{msg}
        : ( $h->{text} ? $h->{text} : join ' ', @$a )
      );
    $values{message} = "" if ( $values{message} eq "none" );

    # chart frame
    if ( $h->{chart} ) {
        my $str = $h->{chart};
        $str =~ s/[^\d,.]//g;
        foreach ( split( /,/, $str ) ) {
            push @{ $values{chart}{chartData} }, round( $_, 0 );
        }

        # take object+model defaults for this frame type
        # if there is no text frame in this notification
        unless ( defined( $values{message} ) && $values{message} ne "" ) {
            $notificationType = "chart";

            $values{icontype} =
                $h->{icontype}
              ? $h->{icontype}
              : AttrVal( $name, "notificationChartIconType",
                $values{icontype} );
            $values{icontype} = "none"
              if ( $values{title}
                && $values{title} ne ""
                && !$h->{forceicontype} );

            $values{lifetime} =
                $h->{lifetime}
              ? $h->{lifetime}
              : AttrVal( $name, "notificationChartLifetime",
                $values{lifetime} );

            $values{priority} =
                $h->{priority}
              ? $h->{priority}
              : AttrVal( $name, "notificationChartPriority",
                $values{priority} );

            $values{sound} =
                $h->{sound}
              ? $h->{sound}
              : AttrVal( $name, "notificationChartSound", $values{sound} );
            $values{sound} = ""
              if ( $values{sound} eq "none" || $values{sound} eq "off" );
        }
    }

    # goal frame
    if ( defined( $h->{goal} ) ) {
        $h->{goal} = ( $h->{goal} =~ /(-?\d+(\.\d+)?)/ ? $1 : "" );

        if ( looks_like_number( $h->{goal} ) ) {

            # goaltype
            if ( $h->{goaltype} ) {
                my $descr = readingsDesc( "", $h->{goaltype} );

                if ($descr) {
                    my $ref_base = $descr->{ref_base};

                    # Use icon from goaltype DB if none was explicitly given
                    $h->{goalicon} =
                      $LaMetric2_goaltype_icons{$ref_base}{lm_icon}
                      if (
                        !defined( $h->{goalicon} )
                        && defined(
                            $LaMetric2_goaltype_icons{$ref_base}{lm_icon}
                        )
                      );

                    # Format number with Unit.pm
                    my ( $txt, $txt_long, $value, $value_num, $unit ) =
                      formatValue( "", $h->{goaltype}, $h->{goal}, $descr,
                        undef, undef, "en" );

                    $h->{goal} = $value_num ? $value_num : $value;
                    $h->{goalunit} = $unit unless ( defined( $h->{goalunit} ) );
                }
            }

            # Construct request
            $values{goal} = (
                {
                    icon => $h->{goalicon} ? $h->{goalicon}
                    : (
                        defined( $values{message} )
                          && $values{message} ne "" ? ""
                        : AttrVal( $name, "notificationGoalIcon", "a11460" )
                    ),
                    goalData => {
                        start => round(
                            $h->{goalstart} ? $h->{goalstart}
                            : AttrVal( $name, "notificationGoalStart", 0 ),
                            0
                        ),
                        current => round( $h->{goal}, 0 ),
                        end     => round(
                            $h->{goalend} ? $h->{goalend}
                            : AttrVal( $name, "notificationGoalEnd", 100 ),
                            0
                        ),
                        unit => trim(
                            (
                                $h->{goalunit} ? $h->{goalunit}
                                : AttrVal( $name, "notificationGoalUnit", '%' )
                            )
                        )
                    }
                }
            );

            $values{goal}{start} = $h->{goal}
              if ( $h->{goal} < $values{goal}{start} );
            $values{goal}{end} = $h->{goal}
              if ( $h->{goal} > $values{goal}{end} );

            $values{goal}{icon} = '' if ( $values{goal}{icon} eq 'none' );

            # take object+model defaults for this frame type
            # if there is no text frame in this notification
            unless ( defined( $values{message} ) && $values{message} ne "" ) {
                $notificationType = "goal";

                $values{icontype} =
                    $h->{icontype}
                  ? $h->{icontype}
                  : AttrVal( $name, "notificationGoalIconType",
                    $values{icontype} );
                $values{icontype} = "none"
                  if ( $values{title}
                    && $values{title} ne ""
                    && !$h->{forceicontype} );

                $values{lifetime} =
                    $h->{lifetime}
                  ? $h->{lifetime}
                  : AttrVal( $name, "notificationGoalLifetime",
                    $values{lifetime} );

                $values{priority} =
                    $h->{priority}
                  ? $h->{priority}
                  : AttrVal( $name, "notificationGoalPriority",
                    $values{priority} );

                $values{sound} =
                    $h->{sound}
                  ? $h->{sound}
                  : AttrVal( $name, "notificationGoalSound", $values{sound} );
                $values{sound} = ""
                  if ( $values{sound} eq "none"
                    || $values{sound} eq "off" );
            }
        }
    }

    # metric frame
    if ( defined( $h->{metric} ) ) {
        my $metric = $h->{metric};
        my $metricold =
          defined( $h->{metricold} )
          ? ( $h->{metricold} =~ /(-?\d+(\.\d+)?)/ ? $1 : undef )
          : undef;
        $metric = ( $metric =~ /(-?\d+(\.\d+)?)/ ? $1 : "" );

        if ( looks_like_number($metric) ) {
            my $icon = "";
            if ( defined($metricold) ) {
                if ( $metric < $metricold ) {
                    $icon = "i124";
                }
                elsif ( $metric > $metricold ) {
                    $icon = "i120";
                }
                else {
                    $icon = "i401";
                }
            }

            # metrictype
            if ( $h->{metrictype} ) {
                my $descr = readingsDesc( "", $h->{metrictype} );

                if ($descr) {
                    my $ref_base = $descr->{ref_base};

                    # Use icon from metrictype DB if none was explicitly given
                    $h->{metricicon} =
                      $LaMetric2_metrictype_icons{$ref_base}{lm_icon}
                      if (
                        !defined( $h->{metricicon} )
                        && defined(
                            $LaMetric2_metrictype_icons{$ref_base}{lm_icon}
                        )
                      );

                    # Format number with Unit.pm
                    my $lang = lc(
                          $h->{metriclang}
                        ? $h->{metriclang}
                        : AttrVal(
                            $name,
                            "notificationMetricLang",
                            AttrVal( "global", "language", "en" )
                        )
                    );
                    my ( $txt, $txt_long, $value, $value_num, $unit ) =
                      formatValue( "", $h->{metrictype}, $metric, $descr,
                        undef, undef, $lang );

                    if ( defined( $h->{metricunit} ) ) {
                        $h->{metric} = $value_num ? $value_num : $value;
                    }
                    else {
                     #FIXME special characters need to be removed to enable this
                     # $h->{metric} = $h->{metriclong} ? $txt_long : $txt;
                        $h->{metric} =
                            $h->{metriclong}
                          ? $txt_long
                          : ( $value_num ? $value_num : $value ) . " " . $unit;
                    }
                }
            }

            # Construct request
            $values{metric} = (
                {
                    icon => $h->{metricicon} ? $h->{metricicon}
                    : (
                        defined( $values{message} )
                          && $values{message} ne "" ? ""
                        : (
                            defined($metricold) ? $icon
                            : AttrVal(
                                $name, "notificationMetricIcon", "i9559"
                            )
                        )
                    ),
                    text => $h->{metric},
                }
            );

            $values{metric}{icon} = ""
              if ( $values{metric}{icon} eq "none" );

            # take object+model defaults for this frame type
            # if there is no text frame in this notification
            unless ( defined( $values{message} ) && $values{message} ne "" ) {
                $notificationType = "metric";

                $values{icontype} =
                    $h->{icontype}
                  ? $h->{icontype}
                  : AttrVal( $name, "notificationMetricIconType",
                    $values{icontype} );
                $values{icontype} = "none"
                  if ( $values{title}
                    && $values{title} ne ""
                    && !$h->{forceicontype} );

                $values{lifetime} =
                    $h->{lifetime}
                  ? $h->{lifetime}
                  : AttrVal( $name, "notificationMetricLifetime",
                    $values{lifetime} );

                $values{priority} =
                    $h->{priority}
                  ? $h->{priority}
                  : AttrVal( $name, "notificationMetricPriority",
                    $values{priority} );

                $values{sound} =
                    $h->{sound}
                  ? $h->{sound}
                  : AttrVal( $name, "notificationMetricSound", $values{sound} );
                $values{sound} = ""
                  if ( $values{sound} eq "none"
                    || $values{sound} eq "off" );
            }
        }
    }

    # Push to private/shared indicator app
    if ( defined( $h->{app} ) ) {
        $notificationType = "app";
        $values{priority} = "";
        $values{icontype} = "";
        $values{lifetime} = "";
        $values{sound}    = "";
    }

    return
"Usage: $name msg <text> [ option1=<value> option2='<value with space>' ... ]"
      unless ( $values{title} ne ""
        || ( defined( $values{message} ) && $values{message} ne "" )
        || ( defined( $values{icon} )    && $values{icon} ne "" )
        || defined( $values{chart} )
        || defined( $values{goal} )
        || defined( $values{metric} ) );

    # If a cancelID was provided, send a "sticky" notification
    if ( !looks_like_number( $values{cycles} ) || $values{cycles} == 0 ) {
        $info->{cancelID} = $values{cycles};
        $values{cycles} = 0;

        # start Validation Timer
        RemoveInternalTimer( $hash, "LaMetric2_CycleMessage" );
        InternalTimer( gettimeofday() + 5, "LaMetric2_CycleMessage", $hash, 0 );
    }

    # Building notification
    #

    my %notification = (
        priority  => $values{priority},
        icon_type => $values{icontype},
        lifetime  => round( $values{lifetime} * 1000, 0 ),
        model     => {
            cycles => $values{cycles},
        },
    );

    readingsBeginUpdate($hash);

    readingsBulkUpdate( $hash, "lastNotificationType",     $notificationType );
    readingsBulkUpdate( $hash, "lastNotificationPriority", $values{priority} );
    readingsBulkUpdate( $hash, "lastNotificationIconType", $values{icontype} );
    readingsBulkUpdate( $hash, "lastNotificationLifetime", $values{lifetime} );

    my $sound;
    if ( $values{sound} ne "" ) {
        my @sFields = split /:/, $values{sound};
        my $soundId;
        my $soundCat;

        if ( defined( $sFields[1] ) ) {
            $soundId  = $sFields[1];
            $soundCat = $sFields[0];
        }
        else {
            $soundId = $sFields[0];
            foreach my $cat ( keys %LaMetric2_sounds ) {
                $soundCat = $cat
                  if ( grep ( /^$soundId$/, @{ $LaMetric2_sounds{$cat} } ) );
            }
        }

        if ( $soundId && $soundCat ) {
            $notification{model}{sound} = {
                category => $soundCat,
                id       => $soundId,
                repeat   => $values{repeat},
            };
            readingsBulkUpdate( $hash, "lastNotificationSound",
                "$soundCat:$soundId" );
        }
    }
    else {
        readingsBulkUpdate( $hash, "lastNotificationSound", "off" );
    }

    my $index = 0;

    if ( $values{title} ne "" ) {
        push @{ $notification{model}{frames} },
          (
            {
                icon  => $values{icon},
                text  => $values{title},
                index => $index++,
            }
          );
        readingsBulkUpdate( $hash, "lastNotificationTitle", $values{title} );
    }
    else {
        readingsBulkUpdate( $hash, "lastNotificationTitle", "" );
    }

    if ( defined( $values{message} ) ) {

        # empty frame
        if ( $values{message} eq "" ) {
            push @{ $notification{model}{frames} },
              (
                {
                    icon  => $values{icon},
                    text  => "",
                    index => $index++,
                }
              )

              # only if there is no other
              # non-text frame afterwards
              if ( !defined( $values{metric} )
                && !defined( $values{chart} )
                && !defined( $values{goal} ) );
        }

        # regular frames
        else {
            foreach my $line ( split /\\n/, $values{message} ) {
                $line = trim($line);
                next if ( !$line || $line eq "" );

                my $ico = $values{icon};

                if ( $notification{model}{frames} ) {
                    $ico = "" unless ( $h->{forceicon} || $line eq "" );

                    #TODO define icon inline per frame.
                    # Must be compatible with FHEM-msg command
                }

                push @{ $notification{model}{frames} },
                  (
                    {
                        icon  => $ico,
                        text  => decode_utf8($line),
                        index => $index++,
                    }
                  );
            }
        }
        readingsBulkUpdate( $hash, "lastMessage", $values{message} );
    }

    if ( $values{metric} ) {
        $values{metric}{index} = $index++;
        push @{ $notification{model}{frames} }, $values{metric};
        readingsBulkUpdate( $hash, "lastMetric", $values{metric}{text} );
    }

    if ( $values{goal} ) {
        $values{goal}{index} = $index++;
        if ( $notification{model}{frames} ) {
            $values{goal}{icon} = "" unless ( $h->{goalicon} );
        }
        push @{ $notification{model}{frames} }, $values{goal};
        readingsBulkUpdate( $hash, "lastGoal",
                $values{goal}{goalData}{current} . " "
              . $values{goal}{goalData}{unit} );
    }

    if ( $values{chart} ) {
        $values{chart}{index} = $index++;
        push @{ $notification{model}{frames} }, $values{chart};
        readingsBulkUpdate( $hash, "lastChart",
            join( ',', @{ $values{chart}{chartData} } ) );
    }

    readingsEndUpdate( $hash, 1 );

    # push frames to private/shared indicator app
    if ( defined( $h->{app} ) ) {
        $notification{package}  = $h->{app};
        $notification{token}    = $h->{token} if ( defined( $h->{token} ) );
        $notification{channels} = $h->{channels}
          if ( defined( $h->{channels} ) );
        return LaMetric2_SetApp( $hash, "app", \%notification, $h->{app},
            "push" );
    }

    # send frames as notification
    else {
        LaMetric2_SendCommand( $hash, "device/notifications", "POST",
            encode_json( \%notification ), $info );
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_SetCancelMessage {
    my $hash = shift;
    my $name = $hash->{NAME};
    my $info = {};
    my $notificationID;

    my ($cancelID) = @_;

    # Remove quotation marks
    if ( $cancelID =~ /^['"](.*)['"]$/s ) {
        $cancelID = $1;
    }

    $info->{cancelID} = $cancelID;

    Log3 $name, 5,
      "LaMetric2 $name: called function LaMetric2_SetCancelMessage()";

    # Update notification queue first to see if the notification still exists.
    # Callback will send the real DELETE request
    LaMetric2_SendCommand( $hash, "device/notifications", "GET", undef, $info );

    return;
}

#------------------------------------------------------------------------------
sub LaMetric2_GetStateAV($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, "presence", "absent" ) eq "absent" ) {
        return "absent";
    }
    elsif ( ReadingsVal( $name, "mute", "off" ) eq "on" ) {
        return "muted";
    }
    elsif ( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        return "off";
    }
    elsif ( ReadingsVal( $name, "playStatus", "stopped" ) ne "stopped" ) {
        return ReadingsVal( $name, "playStatus", "stopped" );
    }
    else {
        return ReadingsVal( $name, "power", "off" );
    }
}

#------------------------------------------------------------------------------
sub LaMetric2_gmtime_str2local($) {
    my ($str) = @_;
    my @a = split( /:/, $str );
    $a[2] = 0 unless ( $a[2] );

    return strftime( '%H:%M:%S',
        localtime( timegm( $a[2], $a[1], $a[0], 1, 0, 0 ) ) );
}

#------------------------------------------------------------------------------
sub LaMetric2_localtime_str2gm($) {
    my ($str) = @_;
    my @a = split( /:/, $str );
    $a[2] = 0 unless ( $a[2] );

    return strftime( '%H:%M:%S',
        gmtime( timelocal( $a[2], $a[1], $a[0], 1, 0, 0 ) ) );
}

#------------------------------------------------------------------------------
sub LaMetric2_IsDuringTimeframe($$;$) {
    my ( $start, $end, $currTime ) = @_;
    my @aStart = split( /:/, $start );
    $aStart[2] = 0 unless ( $aStart[2] );
    my @aEnd = split( /:/, $end );
    $aEnd[2] = 0 unless ( $aEnd[2] );

    my $currTimestamp = time;
    my ( $secs, $mins, $hours, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime($currTimestamp);

    my $startTimestamp =
      timelocal( $aStart[2], $aStart[1], $aStart[0], $mday, $mon, $year );

    my $endTimestamp =
      timelocal( $aEnd[2], $aEnd[1], $aEnd[0], $mday, $mon, $year );

    # if endTime is before start time
    if ( $endTimestamp < $startTimestamp ) {

        # end is tomorrow
        if ( $currTimestamp >= $endTimestamp ) {
            $endTimestamp = $endTimestamp + ( 60 * 60 * 24 );
        }

        # start was yesterday
        elsif ( $currTimestamp < $startTimestamp ) {
            $startTimestamp = $startTimestamp - ( 60 * 60 * 24 );
        }
    }

    if (   $currTimestamp < $endTimestamp
        && $currTimestamp >= $startTimestamp )
    {
        return 1;
    }

    return 0;
}

1;

###############################################################################

=pod
=item device
=item summary Controls for LaMetric Time devices via API
=item summary_DE Steuert LaMetric Time Ger&auml;te &uuml;ber die offizielle Schnittstelle
=begin html

<a name="LaMetric2" id="LaMetric2"></a>
<h3>
  LaMetric2
</h3>
<ul>
  LaMetric is a smart clock with retro design. It may be used to display different information and can receive notifications.<br>
  A a developer account is required to use this module.<br>
  Visit <a href="https://developer.lametric.com/">developer.lametric.com</a>for further information.<br>
  <br>
  <br>
  <a name="LaMetric2Define" id="LaMetric2Define"></a><b>Define</b>
  <ul>
    <code>define &lt;name&gt; LaMetric2 &lt;ip&gt; &lt;apikey&gt; [&lt;port&gt;]</code><br>
    <br>
    Please <a href="https://developer.lametric.com/">create an account</a>to receive the API key.<br>
    You will find the api key in the account menu <i>My Devices</i><br>
    <br>
    The attribute port is optional. Port 4343 will be used by default and connection will be encrypted.<br>
    Examples:
    <ul>
      <code>define lametric LaMetric2 192.168.2.31 a20205cb7eace9c979c27fd55413296b8ac9dafbfb5dae2022a1dc6b77fe9d2d</code>
    </ul>
    <ul>
      <code>define lametric LaMetric2 192.168.2.31 a20205cb7eace9c979c27fd55413296b8ac9dafbfb5dae2022a1dc6b77fe9d2d 4343</code>
    </ul>
    <ul>
      <code>define lametric LaMetric2 192.168.2.31 a20205cb7eace9c979c27fd55413296b8ac9dafbfb5dae2022a1dc6b77fe9d2d 8080</code>
    </ul>
  </ul><br>
  <a name="LaMetric2Set" id="LaMetric2Set"></a><b>Set</b>
  <ul>
    <b>msg</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; msg &lt;text&gt; [&lt;option1&gt;=&lt;value&gt; &lt;option2&gt;="&lt;value with space in it&gt;" ...]</code><br>
      <br>
      The following options may be used to adjust message content and notification behavior:<br>
      <br>
      <code><b>message</b>&nbsp;&nbsp;&nbsp;</code>- type: text - Your message text. Using this option takes precedence; non-option text content will be discarded.<br>
      <code><b>title</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code>- type: text - This text will be the first part of the notification. It will normally replace the first frame defined as 'icontype' if 'forceicontype' was not explicitly set.<br>
      <code><b>icon</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code>- type: text - Icon for the message frame. Icon can be defined as ID or in binary format. Icon ID looks like &lt;prefix&gt;XXX, where &lt;prefix&gt; is “i” (for static icon) or “a” (for animation). XXX is the number of the icon and can be found at <a href="https://developer.lametric.com/icons">developer.lametric.com/icons</a><br>
      <code><b>icontype</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code>- type: text - Represents the nature of notification. Defaults to 'info'. +++ [none] no notification icon will be shown. +++ [info] “i” icon will be displayed prior to the notification. Means that notification contains information, no need to take actions on it. +++ [alert] “!!!” icon will be displayed prior to the notification. Use it when you want the user to pay attention to that notification as it indicates that something bad happened and user must take immediate action.<br>
      <code><b>forceicontype</b>&nbsp;&nbsp;&nbsp;&nbsp;</code>- type: boolean - Will display the icontype before the title frame. Otherwise the title will be the first frame. Defaults to 0.<br>
      <code><b>lifetime</b>&nbsp;</code>- type: text - The time notification lives in queue to be displayed in seconds. If notification stayed in queue for longer than lifetime seconds – it will not be displayed. Defaults to 120.<br>
      <code><b>priority</b>&nbsp;&nbsp;</code>- type: info,warning,critical - Priority of the message +++ [info] This priority means that notification will be displayed on the same “level” as all other notifications on the device that come from apps (for example facebook app). This notification will not be shown when screensaver is active. By default message is sent with “info” priority. This level of notification should be used for notifications like news, weather, temperature, etc. +++ [warning] Notifications with this priority will interrupt ones sent with lower priority (“info”). Should be used to notify the user about something important but not critical. For example, events like “someone is coming home” should use this priority when sending notifications from smart home. +++ [critical] The most important notifications. Interrupts notification with priority info or warning and is displayed even if screensaver is active. Use with care as these notifications can pop in the middle of the night. Must be used only for really important notifications like notifications from smoke detectors, water leak sensors, etc. Use it for events that require human interaction immediately.<br>
      <code><b>sound</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code>- type: text - Name of the sound to play. See attribute notificationSound for full list.<br>
      <code><b>repeat</b>&nbsp;&nbsp;&nbsp;&nbsp;</code>- type: integer - Defines the number of times sound must be played. If set to 0 sound will be played until notification is dismissed. Defaults to 1.<br>
      <code><b>cycles</b>&nbsp;</code>- type: integer - The number of times message should be displayed. If cycles is set to 0, notification will stay on the screen until user dismisses it manually at the device.<br>
If cycles is set to a text string, a sticky notification is created that may also be dismissed using 'set msgCancel' command (find its description below). By default it is set to 1.<br>
      <br>
      <code><b>chart</b>&nbsp;</code>- type: integer-array - Adds a frame to display a chart. Must contain a comma separated list of numbers.<br>
      <br>
      <code><b>goal</b>&nbsp;</code>- type: float - Add a goal frame to display the status within a measuring scale.<br>
      <code><b>goal*</b>&nbsp;</code>- type: n/a - All other options described for the goal-setter can be used here by adding the prefix 'goal' to it.<br>
      <br>
      <code><b>metric</b>&nbsp;</code>- type: float - The number to be shown.<br>
      <code><b>metric*</b>&nbsp;</code>- type: n/a - All other options described for the metric-setter can be used here by adding the prefix 'metric' to it.<br>
      <br>
      <code><b>app</b>&nbsp;</code>- type: text - app_name to push this message to that particular app. Requires matching token parameter (see below).<br>
      <code><b>token</b>&nbsp;</code>- type: text - Private access token to be used when pushing data to an app. Can be retrieved from <a href="https://developer.lametric.com/applications/list">developer.lametric.com/applications/app/&lt;app_number&gt;</a> of the corresponding app.<br>
      <br>
      Examples:
      <ul>
        <code>set lametric msg My first LaMetric message.</code><br>
        <code>set lametric msg My second LaMetric message.\nThis time with two text frames.</code><br>
        <code>set lametric msg Message with own frame icon. icon=i334</code><br>
        <code>set lametric msg "Another LaMetric message in double quotes."</code><br>
        <code>set lametric msg 'Another LaMetric message in single quotes.'</code><br>
        <code>set lametric msg message="LaMetric message using explicit option for text content." This part of the text will be ignored.</code><br>
        <code>set lametric msg This is a message with a title. title="This is a subject"</code><br>
        <code>set lametric msg title="This is a subject, too!" This is another message with a title set at the beginning of the command.</code><br>
        <br>
        <code>set lametric msg chart=1,2,3,4,5,7 title='Some Data'</code><br>
        <br>
        <code>set lametric msg goal=97.8765 title='Goal to 100%'</code><br>
        <code>set lametric msg goal=45.886 goalend=50 title='Goal to 50%'</code><br>
        <code>set lametric msg goal=45.886 goalend=50 goaltype=m title='Goal to 50 meters' using FHEM RType auto format and symbol</code><br>
        <code>set lametric msg goal=45.886 goalend=50 goalunit=m title='Goal to 50 meters' using manual unit symbol and format</code><br>
        <br>
        <code>set lametric msg metric=21.87 title='Temperature' without unit</code><br>
        <code>set lametric msg metric=21.87 metrictype=c title='Temperature' using FHEM RType auto format and symbol</code><br>
        <code>set lametric msg metric=21.87 metricunit='°C' title='Temperature' using manual unit symbol and format</code><br>
        <br>
        <code>set lametric msg app=MyPrivateFHEMapp token=ASDFGHJKL23456789 Show this message to my app.</code><br>
        <code>set lametric msg app=MyPrivateFHEMapp token=ASDFGHJKL23456789 icon=i334 Show this message to my app and use my icon.</code><br>
        <code>set lametric msg app=MyPrivateFHEMapp token=ASDFGHJKL23456789 Show this message to my app.\nThis is a second frame.</code><br>
        <code>set lametric msg app=MyPrivateFHEMapp token=ASDFGHJKL23456789 title="This is the head frame" This text goes to the 2nd frame.</code><br>
      </ul><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>msgCancel</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; msgCancel '&lt;cancelID&gt;'</code><br>
      <br>
      <br>
      <ul>
        <code>set LaMetric21 msgCancel 'cancelID'</code><br>
      </ul><br>
      <br>
      Note: Setter will only appear when a notification was sent using the cycles parameter like cycles=&lt;cancelID&gt; while candelID may be any custom string you would like to use for cancellation afterwards.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>chart</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; chart &lt;1,2,3,4,5,6&gt; [&lt;option1&gt;=&lt;value&gt; &lt;option2&gt;="&lt;value with space in it&gt;" ...]</code><br>
      <br>
      Any option from the msg-setter can be used to modify the chart notification.<br>
      <br>
      Examples:
      <ul>
        <code>set lametric chart 1,2,3,4,5,7 title='Some Data'</code><br>
      </ul>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>goal</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; goal &lt;number&gt; [&lt;option1&gt;=&lt;value&gt; &lt;option2&gt;="&lt;value with space in it&gt;" ...]</code><br>
      <br>
      In addition to any option from the msg-setter, the following options may be used to further adjust a goal notification:<br>
      <br>
      <code><b>start</b>&nbsp;</code>- type: text - The beginning of the measuring scale. Defaults to '0'.<br>
      <code><b>end</b>&nbsp;</code>- type: text - The end of the measuring scale. Defaults to '100'.<br>
      <code><b>unit</b>&nbsp;</code>- type: text - The unit value to be displayed after the number. Defaults to '%'.<br>
      <code><b>type</b>&nbsp;</code>- type: text - Defines this number as a FHEM readings type (RType). Can be either a reading name or an actual RType (e.g. 'c', 'f', 'temperature' or 'temperaturef' will result in '°C' resp. '°F'). The number will be automatically re-formatted based on <a href="https://en.wikipedia.org/wiki/SI">SI definition</a>. An appropriate frame icon will be set. It may be explicitly overwritten by using the respective option in the message.<br>
      <br>
      Examples:
      <ul>
        <code>set lametric goal 97.8765 title='Goal to 100%'</code><br>
        <code>set lametric goal 45.886 end=50 title='Goal to 50%'</code><br>
        <code>set lametric goal 45.886 end=50 type=m title='Goal to 50 meters' using FHEM RType auto format and symbol</code><br>
        <code>set lametric goal 45.886 end=50 unit=m title='Goal to 50 meters' using manual unit symbol and format</code><br>
      </ul><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>metric</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; metric &lt;number&gt; [&lt;option1&gt;=&lt;value&gt; &lt;option2&gt;="&lt;value with space in it&gt;" ...]</code><br>
      <br>
      In addition to any option from the msg-setter, the following options may be used to further adjust a metric notification:<br>
      <br>
      <code><b>old</b>&nbsp;</code>- type: text - when set to the old number, a frame icon for higher, lower, or equal will be set automatically.<br>
      <code><b>unit</b>&nbsp;</code>- type: text - The unit value to be displayed after the number. Defaults to ''.<br>
      <code><b>type</b>&nbsp;</code>- type: text - Defines this number as a FHEM readings type (RType). Can be either a reading name or an actual RType (e.g. 'c', 'f', 'temperature' or 'temperaturef' will result in 'xx.x °C' resp. 'xx.x °F'). The number will be automatically re-formatted based on <a href="https://en.wikipedia.org/wiki/SI">SI definition</a>. The correct unit symbol as well as and an appropriate frame icon will be set. They may be explicitly overwritten by using the respective other options in the message.<br>
      <code><b>lang</b>&nbsp;</code>- type: text - The base language to be used when 'type' is evaluating the number. Defaults to 'en'.<br>
      <code><b>long</b>&nbsp;</code>- type: boolean - When set and used together with 'type', the unit name will be added in text format instead of using the unit symbol. Defaults to '0'.<br>
      <br>
      Examples:
      <ul>
        <code>set lametric metric 21.87 title='Temperature' without unit</code><br>
        <br>
        <code>set lametric metric 21.87 type=c title='Temperature' using FHEM RType auto format and symbol</code><br>
        <code>set lametric metric 21.87 type=temperature title='Temperature' using FHEM RType auto format and symbol</code><br>
        <code>set lametric metric 21.87 unit='°C' title='Temperature' using manual unit symbol and format</code><br>
        <br>
        <code>set lametric metric 81.76 type=f title='Temperature' using FHEM RType auto format and symbol</code><br>
        <code>set lametric metric 81.76 type=temperaturef title='Temperature' using FHEM RType auto format and symbol</code><br>
        <code>set lametric metric 81.76 unit='°F' title='Temperature' using manual unit symbol and format</code><br>
      </ul><br>
    </ul>
  </ul><br>
  <ul>
    <b>app</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; app &lt;app_name&gt; &lt;action_id&gt; [param1=value param2=value]</code><br>
      <br>
      Some apps can be controlled by specific actions. Those can be controlled by pre-defined actions and might have optional or mandatory parameters as well.
      <br>
      Examples:
      <ul>
        <code>set lametric app clock alarm enabled=true time=10:00:00 wake_with_radio=false</code><br>
        <code>set lametric app clock alarm enabled=false</code><br>
        <br>
        <code>set lametric app clock clockface icon='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAOklEQVQYlWNUVFBgwAeYcEncv//gP04FMEmsCmCSiooKjHAFMEF0SRQTsEnCFcAE0SUZGBgYGAl5EwA+6RhuHb9bggAAAABJRU5ErkJggg=='</code><br>
        <br>
        <code>set lametric app stopwatch start</code><br>
        <code>set lametric app stopwatch pause</code><br>
        <code>set lametric app stopwatch reset</code><br>
        <br>
        <code>set lametric app countdown configure duration=1800 start_now=true</code><br>
        <code>set lametric app countdown start</code><br>
        <code>set lametric app countdown pause</code><br>
        <code>set lametric app countdown reset</code><br>
      </ul><br>
      <br><br>
      To send data to a private/shared app, use 'push' as action_id. It will require the access token as parameter so that the device will accept data for that particular app:<br>
      <br>
      <code><b>token</b>&nbsp;</code>- type: text - Private access token to be used when pushing data to an app. Can be retrieved from <a href="https://developer.lametric.com/applications/list">developer.lametric.com/applications/app/&lt;app_number&gt;</a> of the corresponding app.<br>
      <br>
      Examples:
      <ul>
        <code>set lametric app MyPrivateFHEMapp push token=ASDFGHJKL23456789 Show this message to my app.</code><br>
        <code>set lametric app MyPrivateFHEMapp push token=ASDFGHJKL23456789 icon=i334 Show this message to my app and use my icon.</code><br>
        <code>set lametric app MyPrivateFHEMapp push token=ASDFGHJKL23456789 Show this message to my app.\nThis is a second frame.</code><br>
        <code>set lametric app MyPrivateFHEMapp push token=ASDFGHJKL23456789 title="This is the head frame" This text goes to the 2nd frame.</code><br>
      </ul><br>
      <br>
      If you have configured channels for your app and would like to address a specific one, you may add the parameter 'channels' accordingly:
      <ul>
        <code>set lametric app MyPrivateFHEMapp push token=ASDFGHJKL23456789 channels=ch1,ch3 Show this message in 2 of 3 channels in my app.</code><br>
      </ul>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>play</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; play</code><br>
      <br>
      Will switch to the Radio app and start playback.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>stop</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; stop</code><br>
      <br>
      Will stop Radio playback.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>channelDown</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; channelDown</code><br>
      <br>
      When the Radio app is active, it will switch to the previous radio station.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>channelUp</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; channelUp</code><br>
      <br>
      When the Radio app is active, it will switch to the next radio station.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>bluetooth</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; bluetooth &lt;on|off&gt;</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>brightness</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; brightness &lt;1-100&gt;</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>brightnessMode</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; brightness &lt;auto|manual&gt;</code>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>input</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; input &lt;input_name&gt;</code><br>
      <br>
      Will switch to a specific app. &lt;input_name&gt; may either be a display name, app ID or package ID.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>inputDown</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; inputDown</code><br>
      <br>
      Will switch to the previous app.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>inputUp</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; inputUp</code><br>
      <br>
      Will switch to the next app.
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>mute</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; mute &lt;on|off&gt;</code>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>muteT</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; muteT</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>on</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; on</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>off</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; off</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>power</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; power &lt;on|off&gt;</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>screensaver</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; screensaver &lt;off|when_dark|time_based&gt; [&lt;begin hh:mm or hh:mm:ss&gt; &lt;end hh:mm or hh:mm:ss&gt;]</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>statusRequest</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; statusRequest</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>toggle</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; toggle</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>volume</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; volume &lt;0-100&gt;</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>volumeDown</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; volumeDown</code><br>
    </ul>
  </ul><br>
  <br>
  <ul>
    <b>volumeUp</b>
    <ul>
      <code>set &lt;LaMetric2_device&gt; volumeUp</code><br>
    </ul>
  </ul><br>
</ul>
<p>
  <br>
  <br>
</p><a name="LaMetric2Get" id="LaMetric2Get"></a>
<p>
  <b>Get</b>
</p>
<ul>
  <li>N/A
  </li>
</ul>
<p>
  <br>
</p><a name="LaMetric2Attr" id="LaMetric2Attr"></a>
<p>
  <b>Attributes</b>
</p>
<ul>
  <li>
    <a name="LaMetric2AttrdefaultOnStatus" id="LaMetric2AttrdefaultOnStatus"></a><code>defaultOnStatus</code><br>
    When the device is turned on, this will be the screensaver status to put it in to. Defaults to 'illumination'.
  </li>
  <li>
    <a name="LaMetric2AttrdefaultScreensaverStartTime" id="LaMetric2AttrdefaultScreensaverStartTime"></a><code>defaultScreensaverStartTime</code><br>
    When FHEM was rebooted, it will not know the last status of the device before the screensaver was enabled. This will be the fallback value for 'start'. Defaults to '00:00'.
  </li>
  <li>
    <a name="LaMetric2AttrdefaultScreensaverEndTime" id="LaMetric2AttrdefaultScreensaverEndTime"></a><code>defaultScreensaverEndTime</code><br>
    When FHEM was rebooted, it will not know the last status of the device before the screensaver was enabled. This will be the fallback value for 'start'. Defaults to '06:00'.
  </li>
  <li>
    <a name="LaMetric2AttrdefaultVolume" id="LaMetric2AttrdefaultVolume"></a><code>defaultVolume</code><br>
    When FHEM was rebooted, it will not know the last status of the device before volume was muted. This will be the fallback value. Defaults to '50'.
  </li>
  <li>
    <a name="LaMetric2Attrhttps" id="LaMetric2Attrhttps"></a><code>https</code><br>
    Set this to 0 to disable encrypted connectivity and enforce unsecure connection via port 8080. When a port was set explicitly when defining the device, this attribute controls explicit enable/disable of encryption.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationIcon" id="LaMetric2AttrnotificationIcon"></a><code>notificationIcon</code><br>
    Fallback value for icon when sending text notifications.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationIconType" id="LaMetric2AttrnotificationIconType"></a><code>notificationIconType</code><br>
    Fallback value for icontype when sending text notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationLifetime" id="LaMetric2AttrnotificationLifetime"></a><code>notificationLifetime</code><br>
    Fallback value for lifetype when sending text notifications. Defaults to '120'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationPriority" id="LaMetric2AttrnotificationPriority"></a><code>notificationPriority</code><br>
    Fallback value for priority when sending text notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationSound" id="LaMetric2AttrnotificationSound"></a><code>notificationSound</code><br>
    Fallback value for sound when sending text notifications. Defaults to 'off'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationChartIconType" id="LaMetric2AttrnotificationChartIconType"></a><code>notificationChartIconType</code><br>
    Fallback value for icontype when sending chart notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationChartLifetime" id="LaMetric2AttrnotificationChartLifetime"></a><code>notificationChartLifetime</code><br>
    Fallback value for lifetype when sending chart notifications. Defaults to '120'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationChartPriority" id="LaMetric2AttrnotificationChartPriority"></a><code>notificationChartPriority</code><br>
    Fallback value for priority when sending chart notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationChartSound" id="LaMetric2AttrnotificationChartSound"></a><code>notificationChartSound</code><br>
    Fallback value for sound when sending text notifications. Defaults to 'off'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalIcon" id="LaMetric2AttrnotificationGoalIcon"></a><code>notificationGoalIcon</code><br>
    Fallback value for icon when sending goal notifications.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalIconType" id="LaMetric2AttrnotificationGoalIconType"></a><code>notificationGoalIconType</code><br>
    Fallback value for icontype when sending goal notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalLifetime" id="LaMetric2AttrnotificationGoalLifetime"></a><code>notificationGoalLifetime</code><br>
    Fallback value for lifetime when sending goal notifications. Defaults to '120'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalPriority" id="LaMetric2AttrnotificationGoalPriority"></a><code>notificationGoalPriority</code><br>
    Fallback value for priority when sending goal notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalSound" id="LaMetric2AttrnotificationGoalSound"></a><code>notificationGoalSound</code><br>
    Fallback value for sound when sending goal notifications. Defaults to 'off'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalStart" id="LaMetric2AttrnotificationGoalStart"></a><code>notificationGoalStart</code><br>
    Fallback value for measuring scale start when sending goal notifications. Defaults to '0'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalEnd" id="LaMetric2AttrnotificationGoalEnd"></a><code>notificationGoalEnd</code><br>
    Fallback value for measuring scale end when sending goal notifications. Defaults to '100'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationGoalUnit" id="LaMetric2AttrnotificationGoalUnit"></a><code>notificationGoalUnit</code><br>
    Fallback value for unit when sending goal notifications. Defaults to '%'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationMetricIcon" id="LaMetric2AttrnotificationMetricIcon"></a><code>notificationMetricIcon</code><br>
    Fallback value for icon when sending metric notifications.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationMetricIconType" id="LaMetric2AttrnotificationMetricIconType"></a><code>notificationMetricIconType</code><br>
    Fallback value for icontype when sending metric notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationMetricLang" id="LaMetric2AttrnotificationMetricLang"></a><code>notificationMetricLang</code><br>
    Default language when evaluating metric notifications. Defaults to 'en'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationMetricLifetime" id="LaMetric2AttrnotificationMetricLifetime"></a><code>notificationMetricLifetime</code><br>
    Fallback value for lifetime when sending metric notifications. Defaults to '120'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationMetricPriority" id="LaMetric2AttrnotificationMetricPriority"></a><code>notificationMetricPriority</code><br>
    Fallback value for priority when sending metric notifications. Defaults to 'info'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationMetricSound" id="LaMetric2AttrnotificationMetricSound"></a><code>notificationMetricSound</code><br>
    Fallback value for sound when sending metric notifications. Defaults to 'off'.
  </li>
  <li>
    <a name="LaMetric2AttrnotificationMetricUnit" id="LaMetric2AttrnotificationMetricUnit"></a><code>notificationMetricUnit</code><br>
    Fallback value for unit when sending metric notifications. Defaults to ''.
  </li>
</ul>
<p>
  <br>
</p><a name="LaMetric2Events" id="LaMetric2Events"></a>
<p>
  <b>Generated events:</b>
</p>
<ul>
  <li>N/A
  </li>
</ul>

=end html
=begin html_DE

<a name="LaMetric2"></a>
<h3>LaMetric2</h3>
<ul>
Leider keine deutsche Dokumentation vorhanden. Die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#LaMetric2">LaMetric2</a> 
</ul>

=end html_DE

=for :application/json;q=META.json 70_LaMetric2.pm
{
  "version": "v2.3.2",
  "release_status": "stable",
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ],
  "resources": {
    "license": [
      "https://fhem.de/#License"
    ],
    "homepage": "https://fhem.de/",
    "bugtracker": {
      "web": "https://forum.fhem.de/index.php/board,53.0.html",
      "x_web_title": "Multimedia"
    },
    "repository": {
      "type": "svn",
      "url": "https://svn.fhem.de/fhem/",
      "x_branch_master": "trunk",
      "x_branch_dev": "trunk",
      "web": "https://svn.fhem.de/"
    }
  }
}
=end :application/json;q=META.json

=cut

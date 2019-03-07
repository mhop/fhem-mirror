###############################################################################
# $Id$
package main;
use strict;
use warnings;
use Data::Dumper;
use Time::Local;
use Encode qw(encode_utf8 decode_utf8);

use HttpUtils;
use FHEM::Meta;

# initialize ##################################################################
sub ENIGMA2_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "ENIGMA2_Initialize: Entering";

    $hash->{DefFn}       = "ENIGMA2_Define";
    $hash->{UndefFn}     = "ENIGMA2_Undefine";
    $hash->{SetFn}       = "ENIGMA2_Set";
    $hash->{GetFn}       = "ENIGMA2_Get";
    $hash->{parseParams} = 1;

    $hash->{AttrList} =
"disable:1,0 disabledForIntervals do_not_notify:1,0 https:0,1 http-method:GET,POST http-noshutdown:1,0 disable:0,1 bouquet-tv bouquet-radio timeout remotecontrol:standard,advanced,keyboard remotecontrolChannel:LEFT_RIGHT,CHANNELDOWN_CHANNELUP lightMode:0,1 ignoreState:0,1 macaddr:textField model wakeupCmd:textField WOL_useUdpBroadcast WOL_port WOL_mode:EW,UDP,BOTH "
      . $readingFnAttributes;

    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM500_DM800_SVG} =
      "ENIGMA2_RClayout_DM800_SVG";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM500_DM800} =
      "ENIGMA2_RClayout_DM800";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM8000_DM800se_SVG} =
      "ENIGMA2_RClayout_DM8000_SVG";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM8000_DM800se} =
      "ENIGMA2_RClayout_DM8000";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_RC10_SVG} =
      "ENIGMA2_RClayout_RC10_SVG";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_RC10} = "ENIGMA2_RClayout_RC10";
    $data{RC_layout}{ENIGMA2_VUplus_Duo2_SVG} =
      "ENIGMA2_RClayout_VUplusDuo2_SVG";
    $data{RC_layout}{ENIGMA2_VUplus_Duo2} = "ENIGMA2_RClayout_VUplusDuo2";
    $data{RC_makenotify}{ENIGMA2}         = "ENIGMA2_RCmakenotify";

    # 98_powerMap.pm support
    $hash->{powerMap} = {
        model   => 'modelid',    # fallback to attribute
        modelid => {
            'SOLO_SE' => {
                rname_E => 'energy',
                rname_P => 'consumption',
                map     => {
                    stateAV => {
                        absent => 0.5,
                        off    => 12,
                        '*'    => 13,
                    },
                },
            },
        },
    };

    return FHEM::Meta::Load( __FILE__, $hash );
}

# regular Fn ##################################################################
sub ENIGMA2_Define($$) {
    my ( $hash, $a, $h ) = @_;
    my $name = shift @$a;
    my $type = shift @$a;

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Define()";

    eval { require XML::Simple; };
    return "Please install Perl XML::Simple to use module ENIGMA2"
      if ($@);

    if ( int(@$a) < 1 ) {
        my $msg =
            "Wrong syntax: "
          . "define <name> ENIGMA2 <ip-or-hostname> [[[[<port>] [<poll-interval>]] [<http-user]] [<http-password>]]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{URL} = shift @$a;

    # use port 80 if not defined
    my $port = shift @$a || 80;
    return "Port parameter needs to be of type integer"
      unless ( $port =~ /^\d+$/ );

    # use interval of 45sec if not defined
    my $interval = shift @$a || 45;
    return "Interval parameter needs to be of type integer"
      unless ( $interval =~ /^\d+$/ );
    $hash->{INTERVAL} = $interval;

    # Initialize the device
    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    my $http_user   = shift @$a;
    my $http_passwd = shift @$a;
    $hash->{URL} = "$http_user:$http_passwd@" . $hash->{URL}
      if ( $hash->{URL} !~ /^https?:\/\//
        && $hash->{URL} !~ /^\w+(:\w+)?\@/
        && $http_user
        && $http_passwd );
    $hash->{URL} = "$http_user@" . $hash->{URL}
      if ( $hash->{URL} !~ /^https?:\/\//
        && $hash->{URL} !~ /^\w+(:\w+)?\@/
        && $http_user
        && !$http_passwd );
    $hash->{URL} = "http://" . $hash->{URL}
      unless ( $hash->{URL} =~ /^https?:\/\// || $port eq "443" );
    $hash->{URL} = "https://" . $hash->{URL}
      if ( $hash->{URL} !~ /^https?:\/\// && $port eq "443" );
    $hash->{URL} .= ":$port"
      unless ( $hash->{URL} =~ /:\d+$/ || $port eq "80" || $port eq "443" );
    $hash->{URL} .= "/" unless ( $hash->{URL} =~ /\/$/ );

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {

        # use http-method POST for FritzBox environment as GET does not seem to
        # work properly. Might restrict use to newer
        # ENIGMA2 Webif versions or use of OWIF only.
        if ( exists $ENV{CONFIG_PRODUKT_NAME}
            && defined $ENV{CONFIG_PRODUKT_NAME} )
        {
            $attr{$name}{"http-method"} = 'POST';
        }

        # default method is GET and should be compatible to most
        # ENIGMA2 Webif versions
        else {
            $attr{$name}{"http-method"} = 'GET';
        }
        $attr{$name}{webCmd} = 'channel:input';
        $attr{$name}{devStateIcon} =
          'on:rc_GREEN:off off:rc_YELLOW:on absent:rc_STOP:on';
        $attr{$name}{icon} = 'dreambox';
    }

    # start the status update timer
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "ENIGMA2_GetStatus", $hash, 1 );

    return undef;
}

sub ENIGMA2_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Undefine()";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return undef;
}

sub ENIGMA2_Set($@);

sub ENIGMA2_Set($@) {
    my ( $hash, $a, $h ) = @_;

    # a is not an array --> make an array out of $a and $h
    $a = [ $a, $h ]
      if ( ref($a) ne 'ARRAY' );

    my $name        = shift @$a;
    my $set         = shift @$a;
    my $state       = ReadingsVal( $name, "state", "absent" );
    my $presence    = ReadingsVal( $name, "presence", "absent" );
    my $input       = ReadingsVal( $name, "input", "" );
    my $channel     = ReadingsVal( $name, "channel", "" );
    my $channels    = "";
    my $ignoreState = AttrVal( $name, "ignoreState", 0 );

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Set()";

    return "No Argument given" unless ( defined($set) );

    # depending on current FHEMWEB instance's allowedCommands,
    # restrict set commands if there is "set-user" in it
    my $adminMode         = 1;
    my $FWallowedCommands = 0;
    $FWallowedCommands = AttrVal( $FW_wname, "allowedCommands", 0 )
      if ( defined($FW_wname) );
    if ( $FWallowedCommands && $FWallowedCommands =~ m/\bset-user\b/ ) {
        $adminMode = 0;
        return "Forbidden command: set " . $set
          if ( lc($set) eq "statusrequest"
            || lc($set) eq "reboot"
            || lc($set) eq "restartgui"
            || lc($set) eq "shutdown" );
    }

    # load channel list
    if (
           defined($input)
        && defined($channel)
        && $input ne ""
        && $channel ne ""
        && (   !defined( $hash->{helper}{bouquet}{$input} )
            || !defined( $hash->{helper}{bouquet}{$input}{$channel} ) )
      )
    {
        $channels .= $channel . ",";
    }

    if (   $input ne ""
        && defined( $hash->{helper}{channels}{$input} )
        && ref( $hash->{helper}{channels}{$input} ) eq "ARRAY" )
    {
        $channels .= join( ',', @{ $hash->{helper}{channels}{$input} } );
    }

    # create inputList reading for frontends
    readingsSingleUpdate( $hash, "inputList", "tv,radio", 1 )
      if ( ReadingsVal( $name, "inputList", "-" ) ne "tv,radio" );

    # create channelList reading for frontends
    readingsSingleUpdate( $hash, "channelList", $channels, 1 )
      if ( ReadingsVal( $name, "channelList", "-" ) ne $channels );

    my $usage =
        "Unknown argument "
      . $set
      . ", choose one of toggle:noArg on:noArg off:noArg volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg msg remoteControl channelUp:noArg channelDown:noArg play:noArg pause:noArg stop:noArg record:noArg showText downmix:on,off channel:"
      . $channels;
    $usage .= " mute:-,on,off"
      if ( ReadingsVal( $name, "mute", "-" ) eq "-" );
    $usage .= " mute:on,off"
      if ( ReadingsVal( $name, "mute", "-" ) ne "-" );
    $usage .= " input:-,tv,radio"
      if ( $input eq "-" );
    $usage .= " input:tv,radio"
      if ( $input ne "-" );

    if ($adminMode) {
        $usage .= " reboot:noArg";
        $usage .= " restartGui:noArg";
        $usage .= " shutdown:noArg";
        $usage .= " statusRequest:noArg";
    }

    my $cmd = '';
    my $result;

    # statusRequest
    if ( lc($set) eq "statusrequest" ) {
        Log3 $name, 3, "ENIGMA2 set $name " . $set;

        if ( $state ne "absent" ) {
            Log3 $name, 4,
              "ENIGMA2 $name: Clearing cache for bouquet and channels";
            $hash->{helper}{bouquet}  = undef;
            $hash->{helper}{channels} = undef;
        }

        ENIGMA2_GetStatus($hash);
    }

    # toggle
    elsif ( lc($set) eq "toggle" ) {
        if ( $state ne "on" ) {
            return ENIGMA2_Set( $hash, $name, "on" );
        }
        else {
            return ENIGMA2_Set( $hash, $name, "off" );
        }
    }

    # shutdown
    elsif ( lc($set) eq "shutdown" ) {
        return "Recordings running"
          if ( ReadingsVal( $name, "recordings", "0" ) ne "0" );

        Log3 $name, 3, "ENIGMA2 set $name " . $set;

        if ( $state ne "absent" || $ignoreState ne "0" ) {
            $cmd = "newstate=1";
            $result =
              ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "shutdown" );
        }
        else {
            return "Device needs to be ON to be set to standby mode.";
        }
    }

    # reboot
    elsif ( lc($set) eq "reboot" ) {
        return "Recordings running"
          if ( ReadingsVal( $name, "recordings", "0" ) ne "0" );

        Log3 $name, 3, "ENIGMA2 set $name " . $set;

        if ( $state ne "absent" || $ignoreState ne "0" ) {
            $cmd = "newstate=2";
            $result =
              ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "reboot" );
        }
        else {
            return "Device needs to be reachable to be rebooted.";
        }
    }

    # restartGui
    elsif ( lc($set) eq "restartgui" ) {
        return "Recordings running"
          if ( ReadingsVal( $name, "recordings", "0" ) ne "0" );

        Log3 $name, 3, "ENIGMA2 set $name " . $set;

        if ( $state eq "on" || $ignoreState ne "0" ) {
            $cmd = "newstate=3";
            $result =
              ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "restartGui" );
        }
        else {
            return "Device needs to be ON to restart the GUI.";
        }
    }

    # on
    elsif ( lc($set) eq "on" ) {
        if ( $state eq "absent" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $set . " (wakeup)";
            my $wakeupCmd = AttrVal( $name, "wakeupCmd", "" );
            my $macAddr =
              AttrVal( $name, "macaddr", ReadingsVal( $name, "lanmac", "" ) );

            if ( $wakeupCmd ne "" ) {
                $wakeupCmd =~ s/\$DEVICE/$name/g;
                $wakeupCmd =~ s/\$MACADDR/$macAddr/g;

                if ( $wakeupCmd =~ s/^[ \t]*\{|\}[ \t]*$//g ) {
                    Log3 $name, 4,
                      "ENIGMA2 executing wake-up command (Perl): $wakeupCmd";
                    $result = eval $wakeupCmd;
                }
                else {
                    Log3 $name, 4,
                      "ENIGMA2 executing wake-up command (fhem): $wakeupCmd";
                    $result = fhem $wakeupCmd;
                }
            }
            elsif ( $macAddr ne "" && $macAddr ne "-" ) {
                $result = ENIGMA2_wake( $name, $macAddr );
                return "wake-up command sent to MAC $macAddr";
            }
            else {
                return "Device MAC address unknown. "
                  . "Please turn on the device manually once or set attribute macaddr.";
            }
        }
        else {
            Log3 $name, 3, "ENIGMA2 set $name " . $set;

            $cmd = "newstate=4";
            $result = ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "on" );
        }
    }

    # off
    elsif ( lc($set) eq "off" ) {
        if ( $state ne "absent" || $ignoreState ne "0" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $set;
            $cmd = "newstate=5";
            $result = ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "off" );
        }
        else {
            return "Device needs to be reachable to be set to standby mode.";
        }
    }

    # downmix
    elsif ( lc($set) eq "downmix" ) {
        return "No argument given" if ( !defined( $a->[0] ) );

        Log3 $name, 3, "ENIGMA2 set $name " . $set . " " . $a->[0];

        if ( $state eq "on" || $ignoreState ne "0" ) {
            if (   lc( $a->[0] ) eq "true"
                || lc( $a->[0] ) eq "1"
                || lc( $a->[0] ) eq "on" )
            {
                $cmd = "enable=true";
            }
            elsif (lc( $a->[0] ) eq "false"
                || lc( $a->[0] ) eq "0"
                || lc( $a->[0] ) eq "off" )
            {
                $cmd = "enable=false";
            }
            else {
                return "Argument needs to be one of true,1,on,false,0,off";
            }
            $result = ENIGMA2_SendCommand( $hash, "downmix", $cmd );
        }
        else {
            return "Device needs to be ON to change downmix.";
        }
    }

    # volume
    elsif ( lc($set) eq "volume" ) {
        return "No argument given" if ( !defined( $a->[0] ) );

        Log3 $name, 3, "ENIGMA2 set $name " . $set . " " . $a->[0];

        if ( $state eq "on" || $ignoreState ne "0" ) {
            if ( $a->[0] =~ m/^\d+$/ && $a->[0] >= 0 && $a->[0] <= 100 ) {
                $cmd = "set=set" . $a->[0];
            }
            else {
                return "Argument does not seem to be a "
                  . "valid integer between 0 and 100";
            }
            $result = ENIGMA2_SendCommand( $hash, "vol", $cmd );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # volumeUp/volumeDown
    elsif ( lc($set) =~ /^(volumeup|volumedown)$/ ) {
        if ( $state eq "on" || $ignoreState ne "0" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $set;

            if ( lc($set) eq "volumeup" ) {
                $cmd = "set=up";
            }
            else {
                $cmd = "set=down";
            }
            $result = ENIGMA2_SendCommand( $hash, "vol", $cmd );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # mute
    elsif ( lc($set) eq "mute" || lc($set) eq "mutet" ) {
        if ( $state eq "on" || $ignoreState ne "0" ) {
            if ( defined( $a->[0] ) ) {
                Log3 $name, 3, "ENIGMA2 set $name " . $set . " " . $a->[0];
            }
            else {
                Log3 $name, 3, "ENIGMA2 set $name " . $set;
            }

            if ( !defined( $a->[0] ) || $a->[0] eq "toggle" ) {
                $cmd = "set=mute";
            }
            elsif ( lc( $a->[0] ) eq "off" ) {
                if ( ReadingsVal( $name, "mute", "" ) ne "off" ) {
                    $cmd = "set=mute";
                }
            }
            elsif ( lc( $a->[0] ) eq "on" ) {
                if ( ReadingsVal( $name, "mute", "" ) ne "on" ) {
                    $cmd = "set=mute";
                }
            }
            else {
                return "Unknown argument " . $a->[0];
            }
            $result = ENIGMA2_SendCommand( $hash, "vol", $cmd )
              if ( $cmd ne "" );
        }
        else {
            return "Device needs to be ON to mute/unmute audio.";
        }
    }

    # msg
    elsif ( lc($set) eq "msg" ) {
        if ( $state ne "absent" || $ignoreState ne "0" ) {
            my $type;
            my $type2;
            my $timeout;
            my $timeout2;

            $type2 = shift @$a
              if ( $a->[0] =~ m/^(yesno|info|message|attention)$/i );
            $timeout2 = shift @$a
              if ( $a->[0] =~ m/^(\d+(.\d+)?)$/i );

            if ( ref($h) eq "HASH" && keys %$h ) {
                $type    = defined( $h->{type} )    ? $h->{type}    : $type2;
                $timeout = defined( $h->{timeout} ) ? $h->{timeout} : $timeout2;
            }
            else {
                $type    = $type2;
                $timeout = $timeout2;
            }

            return "No type argument given, "
              . "choose one of yesno info message attention"
              unless ( defined($type) );

            return "No timeout argument given"
              unless ( defined($timeout) );

            return "Timeout $timeout"
              . " is not a valid integer between 0 and 49680"
              unless ( $timeout =~ m/^\d+$/
                && $timeout >= 0
                && $timeout <= 49680 );

            return "No message text given"
              unless ( scalar @$a > 0 );

            my $text = urlEncode( join( " ", @$a ) );

            Log3 $name, 3, "ENIGMA2 set $name $set $type $timeout $text";

            if ( lc($type) eq "yesno" ) {
                $cmd = "type=0&timeout=" . $timeout . "&text=" . $text;
            }
            elsif ( lc($type) eq "info" ) {
                $cmd = "type=1&timeout=" . $timeout . "&text=" . $text;
            }
            elsif ( lc($type) eq "message" ) {
                $cmd = "type=2&timeout=" . $timeout . "&text=" . $text;
            }
            elsif ( lc($type) eq "attention" ) {
                $cmd = "type=3&timeout=" . $timeout . "&text=" . $text;
            }
            else {
                return "Unknown type " . $type
                  . ", choose one of yesno info message attention ";
            }
            $result = ENIGMA2_SendCommand( $hash, "message", $cmd );
        }
        else {
            return "Device needs to be reachable to send a message to screen.";
        }
    }

    # remoteControl
    elsif ( lc($set) eq "remotecontrol" ) {
        if ( $state ne "absent" || $ignoreState ne "0" ) {

            Log3 $name, 3, "ENIGMA2 set $name " . $set . " " . $a->[0]
              if !defined( $a->[1] );
            Log3 $name, 3,
              "ENIGMA2 set $name " . $set . " " . $a->[0] . " " . $a->[1]
              if defined( $a->[1] );

            my $commandKeys = join(
                " ",
                keys %{
                    ENIGMA2_GetRemotecontrolCommand("GetRemotecontrolCommands")
                }
            );
            if ( !defined( $a->[0] ) ) {
                return "No argument given, choose one of " . $commandKeys;
            }

            my $request = ENIGMA2_GetRemotecontrolCommand( uc( $a->[0] ) );
            $request = $a->[0]
              if ( $request eq "" && $a->[0] =~ /^\d+$/ );

            if ( uc( $a->[0] ) eq "POWER" ) {
                return ENIGMA2_Set( $hash, $name, "toggle" );
            }
            elsif ( uc( $a->[0] ) eq "MUTE" ) {
                return ENIGMA2_Set( $hash, $name, "mute" );
            }
            elsif ( $request ne "" ) {
                $cmd = "command=" . $request;
                $cmd .= "&rcu=" . AttrVal( $name, "remotecontrol", "" )
                  if ( AttrVal( $name, "remotecontrol", "" ) ne "" );
                $cmd .= "&type=long"
                  if ( defined( $a->[1] ) && lc( $a->[1] ) eq "long" );
            }
            else {
                return
                    "Unknown argument "
                  . $a->[0]
                  . ", choose one of "
                  . $commandKeys;
            }

            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be reachable to be controlled remotely.";
        }
    }

    # channel
    elsif ( lc($set) eq "channel" ) {

        return "No argument given, "
          . "choose one of channel channelNumber servicereference "
          if ( !defined( $a->[0] ) );

        if (   defined( $a->[0] )
            && $presence eq "present"
            && $state ne "on" )
        {
            Log3 $name, 4, "ENIGMA2 $name: indirect switching request to ON";
            ENIGMA2_Set( $hash, $name, "on" );
        }

        Log3 $name, 3, "ENIGMA2 set $name " . $set . " " . $a->[0];

        if ( $state eq "on" || $ignoreState ne "0" ) {
            my $cname = $a->[0];
            if ( defined( $hash->{helper}{bouquet}{$input}{$cname}{sRef} ) ) {
                $result = ENIGMA2_SendCommand(
                    $hash, "zap",
                    "sRef="
                      . urlEncode(
                        $hash->{helper}{bouquet}{$input}{$cname}{sRef}
                      )
                );
            }
            elsif ( $cname =~ m/^(\d+):(.*):$/ ) {
                $result =
                  ENIGMA2_SendCommand( $hash, "zap",
                    "sRef=" . urlEncode($cname) );
            }
            elsif ( $cname =~ m/^\d+$/ && $cname > 0 && $cname < 10000 ) {
                for ( split( //, $a->[0] ) ) {
                    $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand($cname);
                    $result =
                      ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
                }
                $result = ENIGMA2_SendCommand( $hash, "remotecontrol",
                    "command=" . ENIGMA2_GetRemotecontrolCommand("OK") );
            }
            elsif ( m/^\d+$/ && ( $cname <= 0 || $cname >= 10000 ) ) {
                return "Numeric channel addressing '" . $cname
                  . "' needs to be a number between 1 and 9999.";
            }
            else {
                return
                    "'"
                  . $cname
                  . "' does not seem to be a valid channel. Known channels: "
                  . $channels;
            }
        }
        else {
            return
              "Device needs to be present to switch to a specific channel.";
        }
    }

    # channelUp/channelDown
    elsif ( lc($set) =~ /^(channelup|channeldown)$/ ) {
        Log3 $name, 3, "ENIGMA2 set $name " . $set;

        if ( $state eq "on" || $ignoreState ne "0" ) {
            if ( lc($set) eq "channelup" ) {
                $cmd =
                  "command="
                  . ENIGMA2_GetRemotecontrolCommand(
                    AttrVal( $name, 'remotecontrolChannel', 'LEFT_RIGHT' ) eq
                      'CHANNELDOWN_CHANNELUP' ? 'CHANNELUP' : 'RIGHT' );
            }
            else {
                $cmd =
                  "command="
                  . ENIGMA2_GetRemotecontrolCommand(
                    AttrVal( $name, 'remotecontrolChannel', 'LEFT_RIGHT' ) eq
                      'CHANNELDOWN_CHANNELUP' ? 'CHANNELDOWN' : 'LEFT' );
            }
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be ON to switch channel.";
        }
    }

    # input
    elsif ( lc($set) eq "input" ) {

        return "No argument given, choose one of tv radio "
          if ( !defined( $a->[0] ) );

        if (   defined( $a->[0] )
            && $presence eq "present"
            && $state ne "on" )
        {
            Log3 $name, 4, "ENIGMA2 $name: indirect switching request to ON";
            ENIGMA2_Set( $hash, $name, "on" );
        }

        Log3 $name, 3, "ENIGMA2 set $name " . $set . " " . $a->[0];

        if ( $state eq "on" || $ignoreState ne "0" ) {
            if ( lc( $a->[0] ) eq "tv" ) {
                $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("TV");
            }
            elsif ( lc( $a->[0] ) eq "radio" ) {
                $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("RADIO");
            }
            else {
                return
                    "Argument "
                  . $a->[0]
                  . " is not valid, please choose one from tv radio ";
            }
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be present to switch input.";
        }
    }

    # play / pause
    elsif ( lc($set) =~ /^(play|pause)$/ ) {
        if ( $state eq "on" || $ignoreState ne "0" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $set;

            $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("PLAYPAUSE");
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be ON to play or pause video.";
        }
    }

    # stop
    elsif ( lc($set) eq "stop" ) {
        if ( $state eq "on" || $ignoreState ne "0" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $set;

            $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("STOP");
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be ON to stop video.";
        }
    }

    # record
    elsif ( lc($set) eq "record" ) {
        if ( $state eq "on" || $ignoreState ne "0" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $set;
            $result = ENIGMA2_SendCommand( $hash, "recordnow" );
        }
        else {
            return "Device needs to be ON to start instant recording.";
        }
    }

    # showText
    elsif ( lc($set) eq "showtext" ) {
        if ( $state ne "absent" || $ignoreState ne "0" ) {
            return "No argument given, choose one of messagetext "
              unless (@$a);

            $cmd = "type=1&timeout=8&text=" . urlEncode( join( " ", @$a ) );
            Log3 $name, 3, "ENIGMA2 set $name $set";
            $result = ENIGMA2_SendCommand( $hash, "message", $cmd );
        }
        else {
            return "Device needs to be reachable to send a message to screen.";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return undef;
}

sub ENIGMA2_Get($@) {
    my ( $hash, $a, $h ) = @_;
    my $name = shift @$a;
    my $what;

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Get()";

    return "argument is missing" if ( int(@$a) < 1 );

    $what = shift @$a;

    if ( $what =~
/^(power|input|volume|mute|channel|currentMedia|currentTitle|nextTitle|providername|servicevideosize)$/
      )
    {
        if ( ReadingsVal( $name, $what, "" ) ne "" ) {
            return ReadingsVal( $name, $what, "" );
        }
        else {
            return "no such reading: $what";
        }
    }

    # streamUrl
    elsif ( $what eq "streamUrl" ) {
        my $device = "etc";
        $device = "phone" if ( defined $a->[0] );
        return
            $hash->{URL}
          . "/web/stream.m3u?ref="
          . urlEncode( ReadingsVal( $name, "servicereference", "-" ) )
          . "&device=$device";
    }

    else {
        return "Unknown argument $what, "
          . "choose one of power:noArg input:noArg volume:noArg mute:noArg channel:noArg currentMedia:noArg currentTitle:noArg nextTitle:noArg providername:noArg servicevideosize:noArg streamUrl:,mobile ";
    }

    return undef;
}

# module Fn ####################################################################
sub ENIGMA2_SendCommand($$;$$) {
    my ( $hash, $service, $cmd, $type ) = @_;
    my $name            = $hash->{NAME};
    my $http_method     = AttrVal( $name, "http-method", "GET" );
    my $http_noshutdown = AttrVal( $name, "http-noshutdown", "1" );
    my $timeout;
    $cmd = ( defined($cmd) ) ? $cmd : "";

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_SendCommand()";

    my $https = AttrVal( $name, "https", undef );
    $hash->{URL} =~ s/^http:/https:/
      if ($https);
    $hash->{URL} =~ s/^https:/http:/
      if ( defined($https) && $https == 0 );

    my $response;
    my $return;

    if ( !defined($cmd) || $cmd eq "" ) {
        Log3 $name, 4, "ENIGMA2 $name: REQ $service";
    }
    else {
        $cmd = "?" . $cmd . "&"
          if ( $http_method eq "GET" || $http_method eq "" );
        Log3 $name, 4, "ENIGMA2 $name: REQ $service/" . urlDecode($cmd);
    }

    $timeout = AttrVal( $name, "timeout", "3" );
    unless ( $timeout =~ /^\d+$/ ) {
        Log3 $name, 3, "ENIGMA2 $name: wrong format in attribute 'timeout'";
        $timeout = 3;
    }

    my $URL = $hash->{URL} . "web/" . $service;
    $URL .= $cmd if ( $http_method eq "GET" || $http_method eq "" );

    # send request via HTTP-GET method
    if ( $http_method eq "GET" || $http_method eq "" || $cmd eq "" ) {
        Log3 $name, 5,
            "ENIGMA2 $name: GET "
          . urlDecode($URL)
          . " (noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url         => $URL,
                timeout     => $timeout,
                noshutdown  => $http_noshutdown,
                data        => undef,
                hash        => $hash,
                service     => $service,
                cmd         => $cmd,
                type        => $type,
                callback    => \&ENIGMA2_ReceiveCommand,
                httpversion => "1.1",
                loglevel    => AttrVal( $name, "httpLoglevel", 4 ),
                header      => {
                    Agent            => 'FHEM-ENIGMA2/1.0.0',
                    'User-Agent'     => 'FHEM-ENIGMA2/1.0.0',
                    Accept           => 'text/xml;charset=UTF-8',
                    'Accept-Charset' => 'UTF-8',
                },
                sslargs => {
                    SSL_verify_mode => 0,
                },
            }
        );

    }

    # send request via HTTP-POST method
    elsif ( $http_method eq "POST" ) {
        Log3 $name, 5,
            "ENIGMA2 $name: GET "
          . $URL
          . " (POST DATA: "
          . urlDecode($cmd)
          . ", noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url         => $URL,
                timeout     => $timeout,
                noshutdown  => $http_noshutdown,
                data        => $cmd,
                hash        => $hash,
                service     => $service,
                cmd         => $cmd,
                type        => $type,
                callback    => \&ENIGMA2_ReceiveCommand,
                httpversion => "1.1",
                loglevel    => AttrVal( $name, "httpLoglevel", 4 ),
                header      => {
                    Agent            => 'FHEM-ENIGMA2/1.0.0',
                    'User-Agent'     => 'FHEM-ENIGMA2/1.0.0',
                    Accept           => 'text/xml;charset=UTF-8',
                    'Accept-Charset' => 'UTF-8',
                },
                sslargs => {
                    SSL_verify_mode => 0,
                },
            }
        );
    }

    # other HTTP methods are not supported
    else {
        Log3 $name, 1,
            "ENIGMA2 $name: ERROR: HTTP method "
          . $http_method
          . " is not supported.";
    }

    return;
}

sub ENIGMA2_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash     = $param->{hash};
    my $name     = $hash->{NAME};
    my $service  = $param->{service};
    my $cmd      = $param->{cmd};
    my $state    = ReadingsVal( $name, "state", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $type     = ( $param->{type} ) ? $param->{type} : "";
    my $return;

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_ReceiveCommand()";

    readingsBeginUpdate($hash);

    # device not reachable
    if ($err) {

        # powerstate
        if ( $service eq "powerstate" ) {
            $state = "absent";

            if ( !defined($cmd) || $cmd eq "" ) {
                Log3 $name, 4, "ENIGMA2 $name: RCV TIMEOUT $service";
            }
            else {
                Log3 $name, 4,
                  "ENIGMA2 $name: RCV TIMEOUT $service/" . urlDecode($cmd);
            }

            $presence = "absent";
            readingsBulkUpdateIfChanged( $hash, "presence", $presence );
        }

    }

    # data received
    elsif ($data) {
        $presence = "present";
        readingsBulkUpdateIfChanged( $hash, "presence", $presence );

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "ENIGMA2 $name: RCV $service";
        }
        else {
            Log3 $name, 4, "ENIGMA2 $name: RCV $service/" . urlDecode($cmd);
        }

        if ( $data ne "" ) {
            if ( $data =~ /^<\?xml/ && $data !~ /<\/html>/ ) {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5, "ENIGMA2 $name: RES $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "ENIGMA2 $name: RES $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                my $parser = XML::Simple->new(
                    NormaliseSpace => 2,
                    KeepRoot       => 0,
                    ForceArray     => 0,
                    SuppressEmpty  => 1,
                    KeyAttr        => {}
                );

                eval
                  '$return = $parser->XMLin( Encode::encode_utf8($data) ); 1';
                if ($@) {

                    if ( !defined($cmd) || $cmd eq "" ) {
                        Log3 $name, 5,
                            "ENIGMA2 $name: "
                          . "RES ERROR $service - unable to parse malformed XML: $@\n"
                          . $data;
                    }
                    else {
                        Log3 $name, 5,
                            "ENIGMA2 $name: RES ERROR $service/"
                          . urlDecode($cmd)
                          . " - unable to parse malformed XML: $@\n"
                          . $data;

                    }

                    return undef;
                }

                undef $parser;
            }
            else {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5,
                      "ENIGMA2 $name: RES ERROR $service - not in XML format\n"
                      . $data;
                }
                else {
                    Log3 $name, 5,
                        "ENIGMA2 $name: RES ERROR $service/"
                      . urlDecode($cmd)
                      . " - not in XML format\n"
                      . $data;
                }

                return undef;
            }
        }

        $return = Encode::encode_utf8($data)
          if ( $return && ref($return) ne "HASH" );

        #######################
        # process return data
        #

        # powerstate
        if ( $service eq "powerstate" ) {
            if ( defined($return)
                && ref($return) eq "HASH" )
            {

                # Cache bouquet information - get favorite bouquet
                # if not available from helper
                if (
                    !defined($type)
                    || (   $type ne "shutdown"
                        && $type ne "reboot"
                        && $type ne "restartGui"
                        && $type ne "off" )
                  )
                {
                    foreach my $input ( "tv", "radio" ) {
                        if (   !defined( $hash->{helper}{bouquet}{$input} )
                            || !defined( $hash->{helper}{channels}{$input} ) )
                        {
                            my $service_uri =
'1:7:2:0:0:0:0:0:0:0:(type == 2)FROM BOUQUET "bouquets.'
                              . $input
                              . '" ORDER BY bouquet';

                            # trigger cache update
                            if (
                                AttrVal( $name, "bouquet-" . $input, "" ) ne
                                "" )
                            {
                                ENIGMA2_SendCommand(
                                    $hash,
                                    "getservices",
                                    "sRef="
                                      . urlEncode(
                                        AttrVal(
                                            $name, "bouquet-" . $input, ""
                                        )
                                      ),
                                    "services-" . $input
                                );
                            }

                            # set attributes first
                            else {
                                ENIGMA2_SendCommand(
                                    $hash, "getservices",
                                    "sRef=" . urlEncode($service_uri),
                                    "defBouquet-" . $input
                                );
                            }
                        }
                    }
                }

                if (   $type eq "shutdown"
                    || $type eq "reboot"
                    || $type eq "restartGui"
                    || $type eq "off"
                    || ( $return->{e2instandby} eq "true" && $type ne "on" ) )
                {
                    $state = "off";

                    # Keep updating some information during standby
                    if ( !AttrVal( $name, "lightMode", 0 ) ) {

                        ENIGMA2_SendCommand( $hash, "timerlist" );

                        # Read Boxinfo every 15 minutes only
                        if (
                            !defined( $hash->{helper}{lastFullUpdate} )
                            || ( defined( $hash->{helper}{lastFullUpdate} )
                                && $hash->{helper}{lastFullUpdate} +
                                900 le time() )
                          )
                        {
                            ENIGMA2_SendCommand( $hash, "about" );

                            # Update state
                            $hash->{helper}{lastFullUpdate} = time();
                        }
                    }
                }
                else {
                    $state = "on";

                    # Read Boxinfo every 15 minutes only
                    if (
                        !defined( $hash->{helper}{lastFullUpdate} )
                        || ( defined( $hash->{helper}{lastFullUpdate} )
                            && $hash->{helper}{lastFullUpdate} + 900 le time() )
                      )
                    {
                        ENIGMA2_SendCommand( $hash, "about" );

                        # Update state
                        $hash->{helper}{lastFullUpdate} = time();
                    }

                    # get current states
                    ENIGMA2_SendCommand( $hash, "getcurrent" );
                    ENIGMA2_SendCommand( $hash, "timerlist" )
                      if ( !AttrVal( $name, "lightMode", 0 ) );
                    ENIGMA2_SendCommand( $hash, "vol" )
                      if ( !AttrVal( $name, "lightMode", 0 ) );
                    ENIGMA2_SendCommand( $hash, "signal" )
                      if ( !AttrVal( $name, "lightMode", 0 ) );
                }
            }
            elsif ( $state ne "undefined" ) {
                Log3 $name, 2,
                  "ENIGMA2 $name: ERROR: Undefined state of device";

                $state = "undefined";
            }
        }

        # update attributes for bouquet names
        elsif ( $service eq "getservices"
            && ( $type eq "defBouquet-tv" || $type eq "defBouquet-radio" ) )
        {
            my $input = ( $type eq "defBouquet-tv" ) ? "tv" : "radio";

            # set FHEM device attribute if not available
            #  multiple
            if (   ref($return) eq "HASH"
                && defined( $return->{e2service} )
                && ref( $return->{e2service} ) eq "ARRAY"
                && defined( $return->{e2service}[0]{e2servicereference} )
                && $return->{e2service}[0]{e2servicereference} ne "" )
            {
                Log3 $name, 3,
                    "ENIGMA2 $name: Adding attribute bouquet-"
                  . $input . " = "
                  . $return->{e2service}[0]{e2servicereference};

                $attr{$name}{ "bouquet-" . $input } =
                  $return->{e2service}[0]{e2servicereference};
            }

            #  single
            elsif (ref($return) eq "HASH"
                && defined( $return->{e2service}{e2servicereference} )
                && $return->{e2service}{e2servicereference} ne "" )
            {
                Log3 $name, 3,
                    "ENIGMA2 $name: Adding attribute bouquet-"
                  . $input . " = "
                  . $return->{e2service}{e2servicereference};

                $attr{$name}{ "bouquet-" . $input } =
                  $return->{e2service}{e2servicereference};
            }
            elsif ( AttrVal( $name, "bouquet-" . $input, "" ) eq "" ) {
                Log3 $name, 3,
                    "ENIGMA2 $name: ERROR: Unable to read any "
                  . $input
                  . " bouquets from device";
            }

            # trigger cache update
            ENIGMA2_SendCommand(
                $hash,
                "getservices",
                "sRef="
                  . urlEncode( AttrVal( $name, "bouquet-" . $input, "" ) ),
                "services-" . $input
            ) if ( AttrVal( $name, "bouquet-" . $input, "" ) ne "" );
        }

        # update cache of tv and radio channels
        elsif ( $service eq "getservices"
            && ( $type eq "services-tv" || $type eq "services-radio" ) )
        {
            my $input = ( $type eq "services-tv" ) ? "tv" : "radio";

            # Read channels
            if ( ref($return) eq "HASH"
                && defined( $return->{e2service} ) )
            {
                # multiple
                if (   ref( $return->{e2service} ) eq "ARRAY"
                    && defined( $return->{e2service}[0]{e2servicename} )
                    && $return->{e2service}[0]{e2servicename} ne ""
                    && defined( $return->{e2service}[0]{e2servicereference} )
                    && $return->{e2service}[0]{e2servicereference} ne "" )
                {
                    my $i = 0;

                    foreach my $key ( keys @{ $return->{e2service} } ) {
                        my $channel =
                          $return->{e2service}[$key]{e2servicename};
                        $channel =~ s/\s/_/g;

                        # ignore markers
                        if ( $return->{e2service}[$key]{e2servicereference} =~
                            /^1:64:/ )
                        {
                            Log3 $name, 4,
                              "ENIGMA2 $name: Ignoring marker "
                              . $return->{e2service}[$key]{e2servicename};
                            next;
                        }

                        if ( $channel ne "" ) {
                            $hash->{helper}{bouquet}{$input}{$channel} =
                              { 'sRef' =>
                                  $return->{e2service}[$key]{e2servicereference}
                              };

                            $hash->{helper}{channels}{$input}[$i] =
                              $channel;
                        }

                        $i++;
                    }

                    Log3 $name, 4,
                        "ENIGMA2 $name: Cached favorite "
                      . $input
                      . " channels: "
                      . join( ', ', @{ $hash->{helper}{channels}{$input} } );
                }

                # single
                elsif (defined( $return->{e2service}{e2servicename} )
                    && $return->{e2service}{e2servicename} ne ""
                    && defined( $return->{e2service}{e2servicereference} )
                    && $return->{e2service}{e2servicereference} ne "" )
                {
                    # ignore markers
                    if ( $return->{e2service}{e2servicereference} =~ /^1:64:/ )
                    {
                        Log3 $name, 4,
                          "ENIGMA2 $name: Ignoring marker "
                          . $return->{e2service}{e2servicename};
                    }
                    else {
                        my $channel = $return->{e2service}{e2servicename};
                        $channel =~ s/\s/_/g;

                        if ( $channel ne "" ) {
                            $hash->{helper}{bouquet}{$input}{$channel} =
                              { 'sRef' =>
                                  $return->{e2service}{e2servicereference} };

                            $hash->{helper}{channels}{$input}[0] =
                              $channel;

                            Log3 $name, 4,
                                "ENIGMA2 $name: Cached favorite "
                              . $input
                              . " channels: "
                              . $hash->{helper}{channels}{$input}[0];
                        }
                    }

                }
                else {
                    Log3 $name, 4,
                        "ENIGMA2 $name: ERROR: bouquet-"
                      . $input
                      . " seems to be empty.";
                }
            }
            elsif ( $input eq "radio" ) {
                Log3 $name, 4,
                    "ENIGMA2 $name: ERROR: Unable to read "
                  . $input
                  . " bouquet '"
                  . AttrVal( $name, "bouquet-" . $input, "" )
                  . "' from device";
            }
            else {
                Log3 $name, 3,
                    "ENIGMA2 $name: ERROR: Unable to read "
                  . $input
                  . " bouquet '"
                  . AttrVal( $name, "bouquet-" . $input, "" )
                  . "' from device";
            }
        }

        # boxinfo
        elsif ( $service eq "about" ) {
            my $reading;
            my $e2reading;
            if ( ref($return) eq "HASH" ) {

                # General readings
                foreach my $reading (
                    "enigmaversion", "imageversion",
                    "webifversion",  "fpversion",
                    "lanmac",        "model",
                  )
                {
                    $e2reading = "e2" . $reading;

                    if ( defined( $return->{e2about}{$e2reading} ) ) {
                        if (   $return->{e2about}{$e2reading} eq "False"
                            || $return->{e2about}{$e2reading} eq "True" )
                        {
                            readingsBulkUpdateIfChanged( $hash, $reading,
                                lc( $return->{e2about}{$e2reading} ) );
                        }
                        else {
                            readingsBulkUpdateIfChanged( $hash, $reading,
                                $return->{e2about}{$e2reading} );
                        }

                        # model
                        if ( $reading eq "model"
                            && ReadingsVal( $name, "model", "" ) ne "" )
                        {
                            my $model = ReadingsVal( $name, "model", "" );
                            $model =~ s/\s/_/g;
                            $hash->{modelid} = uc($model);
                            $attr{$name}{model} = uc($model);
                        }
                    }

                    else {
                        readingsBulkUpdateIfChanged( $hash, $reading, "-" );
                    }
                }

                # HDD
                if ( defined( $return->{e2about}{e2hddinfo} ) ) {

                    # multiple
                    if ( ref( $return->{e2about}{e2hddinfo} ) eq "ARRAY" ) {
                        Log3 $name, 5, "ENIGMA2 $name: multiple HDDs detected";

                        my $i        = 0;
                        my $arr_size = @{ $return->{e2about}{e2hddinfo} };

                        while ( $i < $arr_size ) {
                            my $counter     = $i + 1;
                            my $readingname = "hdd" . $counter . "_model";
                            readingsBulkUpdateIfChanged( $hash, $readingname,
                                $return->{e2about}{e2hddinfo}[$i]{model} );

                            $readingname = "hdd" . $counter . "_capacity";
                            my @value =
                              split( / /,
                                $return->{e2about}{e2hddinfo}[$i]{capacity} );
                            if (@value) {
                                if ( $value[0] =~ /^\d+(?:\.\d+)?$/ ) {
                                    $value[0] = round( $value[0] * 1024, 1 )
                                      if ( $value[1] && $value[1] =~ /TB/i );
                                    $value[0] = round( $value[0] / 1024, 1 )
                                      if ( $value[1] && $value[1] =~ /MB/i );
                                    $value[0] =
                                      round( $value[0] / 1024 / 1024, 1 )
                                      if ( $value[1] && $value[1] =~ /KB/i );
                                }
                                readingsBulkUpdateIfChanged( $hash,
                                    $readingname, $value[0] );
                            }

                            $readingname = "hdd" . $counter . "_free";
                            @value =
                              split( / /,
                                $return->{e2about}{e2hddinfo}[$i]{free} );
                            if (@value) {
                                if ( $value[0] =~ /^\d+(?:\.\d+)?$/ ) {
                                    $value[0] = round( $value[0] * 1024, 1 )
                                      if ( $value[1] && $value[1] =~ /TB/i );
                                    $value[0] = round( $value[0] / 1024, 1 )
                                      if ( $value[1] && $value[1] =~ /MB/i );
                                    $value[0] =
                                      round( $value[0] / 1024 / 1024, 1 )
                                      if ( $value[1] && $value[1] =~ /KB/i );
                                }
                                readingsBulkUpdateIfChanged( $hash,
                                    $readingname, $value[0] );
                            }

                            $i++;
                        }
                    }

                    #  single
                    elsif ( ref( $return->{e2about}{e2hddinfo} ) eq "HASH" ) {
                        Log3 $name, 5, "ENIGMA2 $name: single HDD detected";

                        my $readingname = "hdd1_model";
                        readingsBulkUpdateIfChanged( $hash, $readingname,
                            $return->{e2about}{e2hddinfo}{model} );

                        $readingname = "hdd1_capacity";
                        my @value =
                          split( / /, $return->{e2about}{e2hddinfo}{capacity} );
                        if (@value) {
                            if ( $value[0] =~ /^\d+(?:\.\d+)?$/ ) {
                                $value[0] = round( $value[0] * 1024, 1 )
                                  if ( $value[1] && $value[1] =~ /TB/i );
                                $value[0] = round( $value[0] / 1024, 1 )
                                  if ( $value[1] && $value[1] =~ /MB/i );
                                $value[0] = round( $value[0] / 1024 / 1024, 1 )
                                  if ( $value[1] && $value[1] =~ /KB/i );
                            }
                            readingsBulkUpdateIfChanged( $hash,
                                $readingname, $value[0] );
                        }

                        $readingname = "hdd1_free";
                        @value =
                          split( / /, $return->{e2about}{e2hddinfo}{free} );
                        if (@value) {
                            if ( $value[0] =~ /^\d+(?:\.\d+)?$/ ) {
                                $value[0] = round( $value[0] * 1024, 1 )
                                  if ( $value[1] && $value[1] =~ /TB/i );
                                $value[0] = round( $value[0] / 1024, 1 )
                                  if ( $value[1] && $value[1] =~ /MB/i );
                                $value[0] = round( $value[0] / 1024 / 1024, 1 )
                                  if ( $value[1] && $value[1] =~ /KB/i );
                            }
                            readingsBulkUpdateIfChanged( $hash,
                                $readingname, $value[0] );
                        }
                    }
                    else {
                        Log3 $name, 5,
                          "ENIGMA2 $name: no HDD seems to be installed";
                    }
                }

                # Tuner
                if ( defined( $return->{e2about}{e2tunerinfo}{e2nim} ) ) {

                    # multiple
                    if (
                        ref( $return->{e2about}{e2tunerinfo}{e2nim} ) eq
                        "ARRAY" )
                    {
                        Log3 $name, 5,
                          "ENIGMA2 $name: multi-tuner configuration detected";

                        foreach my $tuner (
                            @{ $return->{e2about}{e2tunerinfo}{e2nim} } )
                        {
                            my $tuner_name = lc( $tuner->{name} );
                            $tuner_name =~ s/\s/_/g;
                            $tuner_name = "tuner_$tuner_name"
                              if ( $tuner_name !~ /^[Tt]uner_/ );
                            $tuner_name =~ s/[^A-Za-z\/\d_\.-]//g;

                            readingsBulkUpdateIfChanged( $hash, $tuner_name,
                                $tuner->{type} );
                        }
                    }

                    #  single
                    elsif (
                        ref( $return->{e2about}{e2tunerinfo}{e2nim} ) eq
                        "HASH" )
                    {
                        Log3 $name, 5,
                          "ENIGMA2 $name: single-tuner configuration detected";

                        my $tuner_name =
                          lc( $return->{e2about}{e2tunerinfo}{e2nim}{name} );

                        $tuner_name =~ s/\s/_/g;
                        $tuner_name = "tuner_$tuner_name"
                          if ( $tuner_name !~ /^[Tt]uner_/ );
                        $tuner_name =~ s/[^A-Za-z\/\d_\.-]//g;

                        readingsBulkUpdateIfChanged( $hash, $tuner_name,
                            $return->{e2about}{e2tunerinfo}{e2nim}{type} );
                    }
                    else {
                        Log3 $name, 5,
                          "ENIGMA2 $name: no tuner could be detected";
                    }
                }
            }
            else {
                Log3 $name, 2,
                  "ENIGMA2 $name: "
                  . "ERROR: boxinfo could not be read - /about sent malformed response";
            }
        }

        # currsrvinfo
        elsif ( $service eq "getcurrent" ) {
            my $reading;
            my $e2reading;
            if ( ref($return) eq "HASH" ) {

                # Service readings
                foreach my $reading (
                    "servicereference", "servicename",
                    "providername",     "servicevideosize",
                    "videowidth",       "videoheight",
                    "iswidescreen",     "apid",
                    "vpid",             "pcrpid",
                    "pmtpid",           "txtpid",
                    "tsid",             "onid",
                    "sid"
                  )
                {
                    $e2reading = "e2" . $reading;

                    if (   defined( $return->{e2service}{$e2reading} )
                        && lc( $return->{e2service}{$e2reading} ) ne "n/a"
                        && lc( $return->{e2service}{$e2reading} ) ne "n/axn/a"
                        && lc( $return->{e2service}{$e2reading} ) ne "0x0" )
                    {
                        if (   $return->{e2service}{$e2reading} eq "False"
                            || $return->{e2service}{$e2reading} eq "True" )
                        {
                            Log3 $name, 5,
                              "ENIGMA2 $name: "
                              . "transforming value of $reading to lower case";

                            $return->{e2service}{$e2reading} =
                              lc( $return->{e2service}{$e2reading} );
                        }

                        if ( ReadingsVal( $name, $reading, "" ) ne
                            $return->{e2service}{$e2reading} )
                        {
                            readingsBulkUpdate( $hash, $reading,
                                $return->{e2service}{$e2reading} );

                            # channel
                            if ( $reading eq "servicename" ) {
                                my $val = $return->{e2service}{$e2reading};
                                $val =~ s/\s/_/g;
                                readingsBulkUpdate( $hash, "channel", $val );
                            }

                            # currentMedia
                            readingsBulkUpdate( $hash, "currentMedia",
                                $return->{e2service}{$e2reading} )
                              if $reading eq "servicereference";
                        }

                        # input
                        if ( $reading eq "servicereference" ) {
                            my @servicetype =
                              split( /:/, $return->{e2service}{$e2reading} );

                            if (   defined( $servicetype[2] )
                                && $servicetype[2] ne "2"
                                && $servicetype[2] ne "10" )
                            {
                                Log3 $name, 5,
                                  "ENIGMA2 $name: "
                                  . "detected servicereference type: tv";
                                readingsBulkUpdate( $hash, "input", "tv" )
                                  if (
                                    ReadingsVal( $name, "input", "" ) ne "tv" );

                            }
                            elsif (
                                defined( $servicetype[2] )
                                && (   $servicetype[2] eq "2"
                                    || $servicetype[2] eq "10" )
                              )
                            {
                                Log3 $name, 5,
                                  "ENIGMA2 $name: "
                                  . "detected servicereference type: radio";
                                readingsBulkUpdateIfChanged( $hash, "input",
                                    "radio" );
                            }
                            else {
                                Log3 $name, 2,
                                  "ENIGMA2 $name: "
                                  . "ERROR: servicereference type could not be detected (neither 'tv' nor 'radio')";
                            }
                        }
                    }
                    else {
                        Log3 $name, 5,
                          "ENIGMA2 $name: "
                          . "received no value for reading $reading";

                        if ( ReadingsVal( $name, $reading, "" ) ne "-" ) {
                            readingsBulkUpdate( $hash, $reading, "-" );

                            # channel
                            readingsBulkUpdate( $hash, "channel", "-" )
                              if $reading eq "servicename";

                            # currentMedia
                            readingsBulkUpdate( $hash, "currentMedia", "-" )
                              if $reading eq "servicereference";
                        }
                    }
                }

                # Event readings
                #
                if ( defined( $return->{e2eventlist} ) ) {
                    my $eventNow;
                    my $eventNext;

                    if ( ref( $return->{e2eventlist}{e2event} ) eq "ARRAY" ) {
                        Log3 $name, 5,
                          "ENIGMA2 $name: detected multiple event details";

                        $eventNow  = $return->{e2eventlist}{e2event}[0];
                        $eventNext = $return->{e2eventlist}{e2event}[1]
                          if ( defined( $return->{e2eventlist}{e2event}[1] ) );
                    }
                    else {
                        Log3 $name, 5,
                          "ENIGMA2 $name: detected single event details";
                        $eventNow = $return->{e2eventlist}{e2event};
                    }

                    foreach my $reading (
                        "eventstart",       "eventduration",
                        "eventremaining",   "eventcurrenttime",
                        "eventdescription", "eventdescriptionextended",
                        "eventtitle",       "eventname",
                      )
                    {
                        $e2reading = "e2" . $reading;

                        # current event
                        if (   defined( $eventNow->{$e2reading} )
                            && lc( $eventNow->{$e2reading} ) ne "n/a"
                            && $eventNow->{$e2reading} ne "0"
                            && $eventNow->{$e2reading} ne "" )
                        {
                            Log3 $name, 5,
                              "ENIGMA2 $name: "
                              . "detected valid reading $e2reading for current event";

                            if ( ReadingsVal( $name, $reading, "" ) ne
                                $eventNow->{$e2reading} )
                            {
                                readingsBulkUpdate( $hash, $reading,
                                    $eventNow->{$e2reading} );

                                # currentTitle
                                readingsBulkUpdate( $hash, "currentTitle",
                                    $eventNow->{$e2reading} )
                                  if $reading eq "eventtitle";
                            }
                        }
                        else {
                            Log3 $name, 5,
                              "ENIGMA2 $name: "
                              . "no valid reading $e2reading found for current event";

                            if ( ReadingsVal( $name, $reading, "" ) ne "-" ) {
                                readingsBulkUpdate( $hash, $reading, "-" );

                                # currentTitle
                                readingsBulkUpdate( $hash, "currentTitle", "-" )
                                  if $reading eq "eventtitle";
                            }
                        }

                        # next event
                        my $readingN = $reading . "_next";
                        if (   defined( $eventNext->{$e2reading} )
                            && lc( $eventNext->{$e2reading} ) ne "n/a"
                            && $eventNext->{$e2reading} ne "0"
                            && $eventNext->{$e2reading} ne "" )
                        {
                            Log3 $name, 5,
                              "ENIGMA2 $name: "
                              . "detected valid reading $e2reading for next event";

                            if ( ReadingsVal( $name, $readingN, "" ) ne
                                $eventNext->{$e2reading} )
                            {
                                readingsBulkUpdate( $hash, $readingN,
                                    $eventNext->{$e2reading} );

                                # nextTitle
                                readingsBulkUpdate( $hash, "nextTitle",
                                    $eventNext->{$e2reading} )
                                  if $readingN eq "eventtitle_next";
                            }
                        }
                        else {
                            Log3 $name, 5,
                              "ENIGMA2 $name: "
                              . "no valid reading $e2reading found for next event";

                            if ( ReadingsVal( $name, $readingN, "" ) ne "-" ) {
                                readingsBulkUpdate( $hash, $readingN, "-" );

                                # nextTitle
                                readingsBulkUpdate( $hash, "nextTitle", "-" )
                                  if $readingN eq "eventtitle_next";
                            }
                        }
                    }

                    # convert date+time into human readable formats
                    foreach my $readingO (
                        "eventstart",    "eventcurrenttime",
                        "eventduration", "eventremaining"
                      )
                    {
                        $reading   = $readingO . "_hr";
                        $e2reading = "e2" . $readingO;

                        # current event
                        if (   defined( $eventNow->{$e2reading} )
                            && $eventNow->{$e2reading} ne "0"
                            && $eventNow->{$e2reading} ne "" )
                        {
                            my $timestring;
                            if (   $readingO eq "eventduration"
                                || $readingO eq "eventremaining" )
                            {
                                my @t = localtime( $eventNow->{$e2reading} );
                                $timestring = sprintf( "%02d:%02d:%02d",
                                    $t[2] - 1,
                                    $t[1], $t[0] );
                            }
                            else {
                                $timestring = substr(
                                    FmtDateTime( $eventNow->{$e2reading} ),
                                    11 );
                            }

                            readingsBulkUpdateIfChanged( $hash, $reading,
                                $timestring );
                        }
                        else {
                            readingsBulkUpdateIfChanged( $hash, $reading, "-" );
                        }

                        # next event
                        $reading = $readingO . "_next_hr";
                        if (   defined( $eventNext->{$e2reading} )
                            && $eventNext->{$e2reading} ne "0"
                            && $eventNext->{$e2reading} ne "" )
                        {
                            my $timestring;
                            if (   $readingO eq "eventduration"
                                || $readingO eq "eventremaining" )
                            {
                                my @t = localtime( $eventNext->{$e2reading} );
                                $timestring = sprintf( "%02d:%02d:%02d",
                                    $t[2] - 1,
                                    $t[1], $t[0] );
                            }
                            else {
                                $timestring = substr(
                                    FmtDateTime( $eventNext->{$e2reading} ),
                                    11 );
                            }

                            readingsBulkUpdateIfChanged( $hash, $reading,
                                $timestring );
                        }
                        else {
                            readingsBulkUpdateIfChanged( $hash, $reading, "-" );
                        }
                    }
                }
            }
            else {
                Log3 $name, 2,
                  "ENIGMA2 $name: "
                  . "ERROR: current service info could not be read - /getcurrent sent malformed response";
            }

        }

        # timerlist
        elsif ( $service eq "timerlist" ) {
            my $activeRecordings = 0;
            my %recordings;

            my $recordingsNext_time       = "0";
            my $recordingsNext_time_hr    = "-";
            my $recordingsNext_counter    = "0";
            my $recordingsNext_counter_hr = "-";
            my $recordingsNextServicename = "-";
            my $recordingsNextName        = "-";

            my $recordingsError    = 0;
            my $recordingsFinished = 0;

            if ( ref($return) eq "HASH" ) {
                if ( ref( $return->{e2timer} ) eq "HASH" ) {
                    Log3 $name, 5,
                      "ENIGMA2 $name: detected single event in timerlist";

                    # queued recording
                    if (
                           defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "0"
                        && ( !defined( $return->{e2timer}{e2disabled} )
                            || $return->{e2timer}{e2disabled} eq "0" )
                        && defined( $return->{e2timer}{e2eit} )
                        && defined( $return->{e2timer}{e2servicename} )
                        && defined( $return->{e2timer}{e2name} )
                      )
                    {

                        my $timeleft =
                          $return->{e2timer}{e2startprepare} - time();

                        # only add if starttime is smaller
                        if (   $recordingsNext_time eq "0"
                            || $timeleft < $recordingsNext_time - time() )
                        {
                            my @t =
                              localtime( $return->{e2timer}{e2startprepare} );

                            $recordingsNext_time =
                              $return->{e2timer}{e2startprepare};
                            $recordingsNext_time_hr =
                              sprintf( "%02d:%02d:%02d", $t[2], $t[1], $t[0] );
                            $recordingsNext_counter = int( $timeleft + 0.5 );
                            $recordingsNextServicename =
                              $return->{e2timer}{e2servicename};
                            $recordingsNextName = $return->{e2timer}{e2name};

                            # human readable
                            my @t2 = localtime($timeleft);
                            $recordingsNext_counter_hr =
                              sprintf( "%02d:%02d:%02d",
                                $t2[2] - 1,
                                $t2[1], $t2[0] );
                        }
                    }

                    # failed recording
                    if ( defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "1" )
                    {
                        $recordingsError++;
                    }

                    # active recording
                    if (   defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "2"
                        && defined( $return->{e2timer}{e2servicename} )
                        && defined( $return->{e2timer}{e2name} ) )
                    {
                        $activeRecordings++;
                        $recordings{$activeRecordings}{servicename} =
                          $return->{e2timer}{e2servicename};
                        $recordings{$activeRecordings}{name} =
                          $return->{e2timer}{e2name};
                    }

                    # finished recording
                    if ( defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "3" )
                    {
                        $recordingsFinished++;
                    }
                }
                elsif ( ref( $return->{e2timer} ) eq "ARRAY" ) {

                    Log3 $name, 5,
                      "ENIGMA2 $name: detected multiple events in timerlist";

                    my $i        = 0;
                    my $arr_size = @{ $return->{e2timer} };

                    while ( $i < $arr_size ) {

                        # queued recording
                        if (
                               defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "0"
                            && ( !defined( $return->{e2timer}[$i]{e2disabled} )
                                || $return->{e2timer}[$i]{e2disabled} eq "0" )
                            && defined( $return->{e2timer}[$i]{e2eit} )
                            && defined( $return->{e2timer}[$i]{e2servicename} )
                            && defined( $return->{e2timer}[$i]{e2name} )
                          )
                        {

                            my $timeleft =
                              $return->{e2timer}[$i]{e2startprepare} - time();

                            # only add if starttime is smaller
                            if (   $recordingsNext_time eq "0"
                                || $timeleft < $recordingsNext_time - time() )
                            {
                                my @t =
                                  localtime(
                                    $return->{e2timer}[$i]{e2startprepare} );

                                $recordingsNext_time =
                                  $return->{e2timer}[$i]{e2startprepare};
                                $recordingsNext_time_hr =
                                  sprintf( "%02d:%02d:%02d",
                                    $t[2], $t[1], $t[0] );
                                $recordingsNext_counter = $timeleft;
                                $recordingsNextServicename =
                                  $return->{e2timer}[$i]{e2servicename};
                                $recordingsNextName =
                                  $return->{e2timer}[$i]{e2name};

                                # human readable
                                my @t2 = localtime($timeleft);
                                $recordingsNext_counter_hr =
                                  sprintf( "%02d:%02d:%02d",
                                    $t2[2] - 1,
                                    $t2[1], $t2[0] );
                            }
                        }

                        # failed recording
                        if ( defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "1" )
                        {
                            $recordingsError++;
                        }

                        # active recording
                        if (   defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "2"
                            && defined( $return->{e2timer}[$i]{e2servicename} )
                            && defined( $return->{e2timer}[$i]{e2name} ) )
                        {
                            $activeRecordings++;
                            $recordings{$activeRecordings}{servicename} =
                              $return->{e2timer}[$i]{e2servicename};
                            $recordings{$activeRecordings}{name} =
                              $return->{e2timer}[$i]{e2name};
                        }

                        # finished recording
                        if ( defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "3" )
                        {
                            $recordingsFinished++;
                        }

                        $i++;
                    }
                }
            }
            else {
                Log3 $name, 5, "ENIGMA2 $name: timerlist seems to be empty";
            }

            my $recordingsElementsCount = scalar( keys %recordings );
            my $readingname;

            readingsBulkUpdateIfChanged( $hash, "recordings",
                $recordingsElementsCount );

            my $ri = 0;
            if ( $recordingsElementsCount > 0 ) {

                while ( $ri < $recordingsElementsCount ) {
                    $ri++;

                    $readingname = "recordings" . $ri . "_servicename";
                    readingsBulkUpdateIfChanged( $hash, $readingname, $2 )
                      if ( $recordings{$ri}{servicename} =~
m/^(\s*[\[\(\{].*[\]\)\}]\s*)?([\s\w\(\)_-]+)(\s*[\[\(\{].*[\]\)\}]\s*)?$/
                      );

                    $readingname = "recordings" . $ri . "_name";
                    readingsBulkUpdateIfChanged( $hash, $readingname, $2 )
                      if ( $recordings{$ri}{name} =~
m/^(\s*[\[\(\{].*[\]\)\}]\s*)?([\s\w\(\)_-]+)(\s*[\[\(\{].*[\]\)\}]\s*)?$/
                      );
                }
            }

            # clear inactive recordingsX_* readings
            foreach my $recReading (
                grep { /^recordings\d+_.*/ }
                keys %{ $defs{$name}{READINGS} }
              )
            {
                next
                  if ( $recReading =~ m/^recordings(\d+).*/ && $1 <= $ri );

                Log3 $name, 5,
                  "ENIGMA2 $name: old reading $recReading was deleted";

                # trigger event before deleting this reading to notify GUI
                readingsBulkUpdateIfChanged( $hash, $recReading, "" );
                delete( $defs{$name}{READINGS}{$recReading} );
            }

            readingsBulkUpdateIfChanged( $hash, "recordings_next",
                $recordingsNext_time );
            readingsBulkUpdateIfChanged( $hash, "recordings_next_hr",
                $recordingsNext_time_hr );
            readingsBulkUpdateIfChanged( $hash, "recordings_next_counter",
                $recordingsNext_counter );
            readingsBulkUpdateIfChanged( $hash,
                "recordings_next_counter_hr", $recordingsNext_counter_hr );
            readingsBulkUpdateIfChanged( $hash,
                "recordings_next_servicename", $recordingsNextServicename );
            readingsBulkUpdateIfChanged( $hash, "recordings_next_name",
                $recordingsNextName );
            readingsBulkUpdateIfChanged( $hash, "recordings_error",
                $recordingsError );
            readingsBulkUpdateIfChanged( $hash, "recordings_finished",
                $recordingsFinished );
        }

        # volume
        elsif ( $service eq "vol" ) {
            if ( ref($return) eq "HASH" && defined( $return->{e2current} ) ) {
                readingsBulkUpdateIfChanged( $hash, "volume",
                    $return->{e2current} );
            }
            else {
                Log3 $name, 5,
                  "ENIGMA2 $name: ERROR: no volume could be extracted";
            }

            if ( ref($return) eq "HASH" && defined( $return->{e2ismuted} ) ) {
                my $muteState = "on";
                $muteState = "off"
                  if ( lc( $return->{e2ismuted} ) eq "false" );
                readingsBulkUpdateIfChanged( $hash, "mute", $muteState );
            }
            else {
                Log3 $name, 5,
                  "ENIGMA2 $name: ERROR: no mute state could be extracted";
            }
        }

        # signal
        elsif ( $service eq "signal" ) {
            my $reading;
            my $e2reading;
            if ( ref($return) eq "HASH"
                && defined( $return->{e2snrdb} ) )
            {
                foreach my $reading ( "snrdb", "snr", "ber", "acg", ) {
                    $e2reading = "e2" . $reading;

                    if ( defined( $return->{$e2reading} )
                        && lc( $return->{$e2reading} ) ne "n/a" )
                    {
                        my @value = split( / /, $return->{$e2reading} );
                        if ( defined( $value[1] ) || $reading eq "ber" ) {
                            readingsBulkUpdate( $hash, $reading, $value[0] );
                        }
                        else {
                            readingsBulkUpdate( $hash, $reading, "0" );
                        }
                    }
                    else {
                        readingsBulkUpdate( $hash, $reading, "0" );
                    }
                }
            }
            else {
                Log3 $name, 5,
                  "ENIGMA2 $name: ERROR: no signal information could be found";
            }
        }

        # all other command results
        else {
            ENIGMA2_GetStatus( $hash, 1 );
        }
    }

    # Set reading for power
    #
    my $readingPower = "off";
    $readingPower = "on"
      if ( $state eq "on" );
    readingsBulkUpdateIfChanged( $hash, "power", $readingPower );

    # Set reading for state
    #
    readingsBulkUpdateIfChanged( $hash, "state", $state );

    # Set reading for stateAV
    my $stateAV = ENIGMA2_GetStateAV($hash);
    readingsBulkUpdateIfChanged( $hash, "stateAV", $stateAV );

    # Set ENIGMA2 online-only readings to "-" in case box is in
    # offline or in standby mode
    if (   $state eq "off"
        || $state eq "absent"
        || $state eq "undefined" )
    {
        foreach my $reading (
            'servicename',           'providername',
            'servicereference',      'videowidth',
            'videoheight',           'servicevideosize',
            'apid',                  'vpid',
            'pcrpid',                'pmtpid',
            'txtpid',                'tsid',
            'onid',                  'sid',
            'iswidescreen',          'mute',
            'channel',               'currentTitle',
            'nextTitle',             'currentMedia',
            'eventcurrenttime',      'eventcurrenttime_hr',
            'eventdescription',      'eventdescriptionextended',
            'eventduration',         'eventduration_hr',
            'eventremaining',        'eventremaining_hr',
            'eventstart',            'eventstart_hr',
            'eventtitle',            'eventname',
            'eventcurrenttime_next', 'eventcurrenttime_next_hr',
            'eventdescription_next', 'eventdescriptionextended_next',
            'eventduration_next',    'eventduration_next_hr',
            'eventremaining_next',   'eventremaining_next_hr',
            'eventstart_next',       'eventstart_next_hr',
            'eventtitle_next',       'eventname_next',
          )
        {
            readingsBulkUpdateIfChanged( $hash, $reading, "-" );
        }

        # special handling for signal values
        foreach my $reading ( 'acg', 'ber', 'snr', 'snrdb', ) {
            readingsBulkUpdateIfChanged( $hash, $reading, "0" );
        }
    }

    # Set ENIGMA2 online+standby readings to "-" in case box is in
    # offline mode
    if ( $state eq "absent" || $state eq "undefined" ) {
        readingsBulkUpdateIfChanged( $hash, "input", "-" );
    }

    readingsEndUpdate( $hash, 1 );

    undef $return;
    return;
}

sub ENIGMA2_GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_GetStatus()";

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "ENIGMA2_GetStatus", $hash, 0 );

    return
      if ( AttrVal( $name, "disable", 0 ) == 1 );

    if ( !$update ) {
        ENIGMA2_SendCommand( $hash, "powerstate" );
    }
    else {
        ENIGMA2_SendCommand( $hash, "getcurrent" );
    }

    return;
}

sub ENIGMA2_GetStateAV($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, "presence", "absent" ) eq "absent" ) {
        return "absent";
    }
    elsif ( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        return "off";
    }
    elsif ( ReadingsVal( $name, "mute", "off" ) eq "on" ) {
        return "muted";
    }
    elsif ( ReadingsVal( $name, "playStatus", "stopped" ) ne "stopped" ) {
        return ReadingsVal( $name, "playStatus", "stopped" );
    }
    else {
        return ReadingsVal( $name, "power", "off" );
    }
}

sub ENIGMA2_GetRemotecontrolCommand($) {
    my ($command) = @_;
    my $commands = {
        'RESERVED'       => 0,
        'ESC'            => 1,
        '1'              => 2,
        '2'              => 3,
        '3'              => 4,
        '4'              => 5,
        '5'              => 6,
        '6'              => 7,
        '7'              => 8,
        '8'              => 9,
        '9'              => 10,
        '0'              => 11,
        'MINUS'          => 12,
        'EQUAL'          => 13,
        'BACKSPACE'      => 14,
        'TAB'            => 15,
        'Q'              => 16,
        'W'              => 17,
        'E'              => 18,
        'R'              => 19,
        'T'              => 20,
        'Y'              => 21,
        'U'              => 22,
        'I'              => 23,
        'O'              => 24,
        'P'              => 25,
        'LEFTBRACE'      => 26,
        'RIGHTBRACE'     => 27,
        'ENTER'          => 28,
        'LEFTCTRL'       => 29,
        'A'              => 30,
        'S'              => 31,
        'D'              => 32,
        'F'              => 33,
        'G'              => 34,
        'H'              => 35,
        'J'              => 36,
        'K'              => 37,
        'L'              => 38,
        'SEMICOLON'      => 39,
        'APOSTROPHE'     => 40,
        'GRAVE'          => 41,
        'LEFTSHIFT'      => 42,
        'BACKSLASH'      => 43,
        'Z'              => 44,
        'X'              => 45,
        'C'              => 46,
        'V'              => 47,
        'B'              => 48,
        'N'              => 49,
        'M'              => 50,
        'COMMA'          => 51,
        'DOT'            => 52,
        'SLASH'          => 53,
        'RIGHTSHIFT'     => 54,
        'KPASTERISK'     => 55,
        'LEFTALT'        => 56,
        'SPACE'          => 57,
        'CAPSLOCK'       => 58,
        'F1'             => 59,
        'F2'             => 60,
        'F3'             => 61,
        'F4'             => 62,
        'F5'             => 63,
        'F6'             => 64,
        'F7'             => 65,
        'F8'             => 66,
        'F9'             => 67,
        'F10'            => 68,
        'NUMLOCK'        => 69,
        'SCROLLLOCK'     => 70,
        'KP7'            => 71,
        'KP8'            => 72,
        'KP9'            => 73,
        'KPMINUS'        => 74,
        'KP4'            => 75,
        'KP5'            => 76,
        'KP6'            => 77,
        'KPPLUS'         => 78,
        'KP1'            => 79,
        'KP2'            => 80,
        'KP3'            => 81,
        'KP0'            => 82,
        'KPDOT'          => 83,
        '103RD'          => 84,
        'F13'            => 85,
        '102ND'          => 86,
        'F11'            => 87,
        'F12'            => 88,
        'F14'            => 89,
        'F15'            => 90,
        'F16'            => 91,
        'F17'            => 92,
        'F18'            => 93,
        'F19'            => 94,
        'F20'            => 95,
        'KPENTER'        => 96,
        'RIGHTCTRL'      => 97,
        'KPSLASH'        => 98,
        'SYSRQ'          => 99,
        'RIGHTALT'       => 100,
        'LINEFEED'       => 101,
        'HOME'           => 102,
        'UP'             => 103,
        'PAGEUP'         => 104,
        'LEFT'           => 105,
        'RIGHT'          => 106,
        'END'            => 107,
        'DOWN'           => 108,
        'PAGEDOWN'       => 109,
        'INSERT'         => 110,
        'DELETE'         => 111,
        'MACRO'          => 112,
        'MUTE'           => 113,
        'VOLUMEDOWN'     => 114,
        'VOLDOWN'        => 114,
        'VOLUMEUP'       => 115,
        'VOLUP'          => 115,
        'POWER'          => 116,
        'KPEQUAL'        => 117,
        'KPPLUSMINUS'    => 118,
        'PAUSE'          => 119,
        'F21'            => 120,
        'F22'            => 121,
        'F23'            => 122,
        'F24'            => 123,
        'KPCOMMA'        => 124,
        'LEFTMETA'       => 125,
        'RIGHTMETA'      => 126,
        'COMPOSE'        => 127,
        'STOP'           => 128,
        'AGAIN'          => 129,
        'PROPS'          => 130,
        'UNDO'           => 131,
        'FRONT'          => 132,
        'COPY'           => 133,
        'OPEN'           => 134,
        'PASTE'          => 135,
        'FIND'           => 136,
        'CUT'            => 137,
        'HELP'           => 138,
        'MENU'           => 139,
        'CALC'           => 140,
        'SETUP'          => 141,
        'SLEEP'          => 142,
        'WAKEUP'         => 143,
        'FILE'           => 144,
        'SENDFILE'       => 145,
        'DELETEFILE'     => 146,
        'XFER'           => 147,
        'PROG1'          => 148,
        'PROG2'          => 149,
        'WWW'            => 150,
        'MSDOS'          => 151,
        'COFFEE'         => 152,
        'DIRECTION'      => 153,
        'CYCLEWINDOWS'   => 154,
        'MAIL'           => 155,
        'BOOKMARKS'      => 156,
        'COMPUTER'       => 157,
        'BACK'           => 158,
        'FORWARD'        => 159,
        'CLOSECD'        => 160,
        'EJECTCD'        => 161,
        'EJECTCLOSECD'   => 162,
        'NEXTSONG'       => 163,
        'PLAYPAUSE'      => 164,
        'PREVIOUSSONG'   => 165,
        'STOPCD'         => 166,
        'RECORD'         => 167,
        'REWIND'         => 168,
        'PHONE'          => 169,
        'ISO'            => 170,
        'CONFIG'         => 171,
        'HOMEPAGE'       => 172,
        'REFRESH'        => 173,
        'EXIT'           => 174,
        'MOVE'           => 175,
        'EDIT'           => 176,
        'SCROLLUP'       => 177,
        'SCROLLDOWN'     => 178,
        'KPLEFTPAREN'    => 179,
        'KPRIGHTPAREN'   => 180,
        'INTL1'          => 181,
        'INTL2'          => 182,
        'INTL3'          => 183,
        'INTL4'          => 184,
        'INTL5'          => 185,
        'INTL6'          => 186,
        'INTL7'          => 187,
        'INTL8'          => 188,
        'INTL9'          => 189,
        'LANG1'          => 190,
        'LANG2'          => 191,
        'LANG3'          => 192,
        'LANG4'          => 193,
        'LANG5'          => 194,
        'LANG6'          => 195,
        'LANG7'          => 196,
        'LANG8'          => 197,
        'LANG9'          => 198,
        'PLAYCD'         => 200,
        'PAUSECD'        => 201,
        'PROG3'          => 202,
        'PROG4'          => 203,
        'SUSPEND'        => 205,
        'CLOSE'          => 206,
        'PLAY'           => 207,
        'FASTFORWARD'    => 208,
        'BASSBOOST'      => 209,
        'PRINT'          => 210,
        'HP'             => 211,
        'CAMERA'         => 212,
        'SOUND'          => 213,
        'QUESTION'       => 214,
        'EMAIL'          => 215,
        'CHAT'           => 216,
        'SEARCH'         => 217,
        'CONNECT'        => 218,
        'FINANCE'        => 219,
        'SPORT'          => 220,
        'SHOP'           => 221,
        'ALTERASE'       => 222,
        'CANCEL'         => 223,
        'BRIGHTNESSDOWN' => 224,
        'BRIGHTNESSUP'   => 225,
        'MEDIA'          => 226,
        'UNKNOWN'        => 240,
        'BTN_0'          => 256,
        'BTN_1'          => 257,
        'OK'             => 352,
        'SELECT'         => 353,
        'GOTO'           => 354,
        'CLEAR'          => 355,
        'POWER2'         => 356,
        'OPTION'         => 357,
        'INFO'           => 358,
        'TIME'           => 359,
        'VENDOR'         => 360,
        'ARCHIVE'        => 361,
        'PROGRAM'        => 362,
        'CHANNEL'        => 363,
        'FAVORITES'      => 364,
        'EPG'            => 365,
        'PVR'            => 366,
        'MHP'            => 367,
        'LANGUAGE'       => 368,
        'TITLE'          => 369,
        'SUBTITLE'       => 370,
        'ANGLE'          => 371,
        'ZOOM'           => 372,
        'MODE'           => 373,
        'KEYBOARD'       => 374,
        'SCREEN'         => 375,
        'PC'             => 376,
        'TV'             => 377,
        'TV2'            => 378,
        'VCR'            => 379,
        'VCR2'           => 380,
        'SAT'            => 381,
        'SAT2'           => 382,
        'CD'             => 383,
        'TAPE'           => 384,
        'RADIO'          => 385,
        'TUNER'          => 386,
        'PLAYER'         => 387,
        'TEXT'           => 388,
        'DVD'            => 389,
        'AUX'            => 390,
        'MP3'            => 391,
        'AUDIO'          => 392,
        'VIDEO'          => 393,
        'DIRECTORY'      => 394,
        'LIST'           => 395,
        'MEMO'           => 396,
        'CALENDAR'       => 397,
        'RED'            => 398,
        'GREEN'          => 399,
        'YELLOW'         => 400,
        'BLUE'           => 401,
        'CHANNELUP'      => 402,
        'CHANUP'         => 402,
        'CHANNELDOWN'    => 403,
        'CHANDOWN'       => 403,
        'FIRST'          => 404,
        'LAST'           => 405,
        'AB'             => 406,
        'NEXT'           => 407,
        'RESTART'        => 408,
        'SLOW'           => 409,
        'SHUFFLE'        => 410,
        'BREAK'          => 411,
        'PREVIOUS'       => 412,
        'DIGITS'         => 413,
        'TEEN'           => 414,
        'TWEN'           => 415,
        'DEL_EOL'        => 448,
        'DEL_EOS'        => 449,
        'INS_LINE'       => 450,
        'DEL_LINE'       => 451,
        'ASCII'          => 510,
        'MAX'            => 511
    };

    if ( defined( $commands->{$command} ) ) {
        return $commands->{$command};
    }
    elsif ( $command eq "GetRemotecontrolCommands" ) {
        return $commands;
    }
    else {
        return "";
    }
}

sub ENIGMA2_wake ($$) {
    if ( !$modules{WOL}{LOADED}
        && -f "$attr{global}{modpath}/FHEM/98_WOL.pm" )
    {
        my $ret = CommandReload( undef, "98_WOL" );
        return $ret if ($ret);
    }
    elsif ( !-f "$attr{global}{modpath}/FHEM/98_WOL.pm" ) {
        return "Missing module: $attr{global}{modpath}/FHEM/98_WOL.pm";
    }

    my ( $name, $mac ) = @_;
    my $hash = $defs{$name};
    my $host =
      AttrVal( $name, "WOL_useUdpBroadcast",
        AttrVal( $name, "useUdpBroadcast", "255.255.255.255" ) );
    my $port = AttrVal( $name, "WOL_port", "9" );
    my $mode = lc( AttrVal( $name, "WOL_mode", "UDP" ) );

    Log3 $name, 4,
      "ENIGMA2 $name: Waking up by sending Wake-On-Lan magic package to "
      . $mac;

    if ( $mode eq "both" || $mode eq "ew" ) {
        WOL_by_ew( $hash, $mac );
    }
    if ( $mode eq "both" || $mode eq "udp" ) {
        WOL_by_udp( $hash, $mac, $host, $port );
    }
}

sub ENIGMA2_RCmakenotify($$) {
    my ( $nam, $ndev ) = @_;
    my $nname = "notify_$nam";

    fhem( "define $nname notify $nam set $ndev remoteControl " . '$EVENT', 1 );
    Log3 undef, 2, "[remotecontrol:ENIGMA2] Notify created: $nname";
    return "Notify created by ENIGMA2: $nname";
}

sub ENIGMA2_RClayout_DM800_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";
    $row[6] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[7] = "VOLUMEUP:rc_VOLPLUS.svg,MUTE:rc_MUTE.svg,CHANNELUP:rc_UP.svg";
    $row[8] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,EXIT:rc_EXIT.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[9] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[10] = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[11] = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[12] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[13] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[14] =
        "RED:rc_REWred.svg,GREEN:rc_PLAYgreen.svg,"
      . "YELLOW:rc_PAUSEyellow.svg,BLUE:rc_FFblue.svg";
    $row[15] =
        "TV:rc_TVstop.svg,RADIO:rc_RADIOred.svg,"
      . "TEXT:rc_TEXT.svg,HELP:rc_HELP.svg";

    $row[16] = "attr rc_iconpath icons/remotecontrol";
    $row[17] = "attr rc_iconprefix black_btn_";
    return @row;
}

sub ENIGMA2_RClayout_DM800() {
    my @row;

    $row[0] = ":blank,:blank,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";
    $row[6] = ":blank,:blank,:blank";

    $row[7] = "VOLUMEUP:VOLUP,MUTE,CHANNELUP:CHUP2";
    $row[8] = "VOLUMEDOWN:VOLDOWN,EXIT,CHANNELDOWN:CHDOWN2";
    $row[9] = ":blank,:blank,:blank";

    $row[10] = "INFO,UP,MENU";
    $row[11] = "LEFT,OK,RIGHT";
    $row[12] = "AUDIO,DOWN,VIDEO";
    $row[13] = ":blank,:blank,:blank";

    $row[14] = "RED:REWINDred,GREEN:PLAYgreen,YELLOW:PAUSEyellow,BLUE:FFblue";
    $row[15] = "TV:TVstop,RADIO:RADIOred,TEXT,HELP";

    $row[16] = "attr rc_iconpath icons/remotecontrol";
    $row[17] = "attr rc_iconprefix black_btn_";
    return @row;
}

sub ENIGMA2_RClayout_DM8000_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";
    $row[6] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[7] = "VOLUMEUP:rc_VOLPLUS.svg,MUTE:rc_MUTE.svg,CHANNELUP:rc_UP.svg";
    $row[8] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,EXIT:rc_EXIT.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[9] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[10] = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[11] = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[12] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[13] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[14] =
        "RED:rc_RED.svg,GREEN:rc_GREEN.svg,"
      . "YELLOW:rc_YELLOW.svg,BLUE:rc_BLUE.svg";
    $row[15] =
        "REWIND:rc_REW.svg,PLAY:rc_PLAY.svg,"
      . "STOP:rc_STOP.svg,FASTFORWARD:rc_FF.svg";
    $row[16] =
      "TV:rc_TV.svg,RADIO:rc_RADIO.svg,TEXT:rc_TEXT.svg,RECORD:rc_REC.svg";

    $row[17] = "attr rc_iconpath icons/remotecontrol";
    $row[18] = "attr rc_iconprefix black_btn_";
    return @row;
}

sub ENIGMA2_RClayout_DM8000() {
    my @row;

    $row[0] = ":blank,:blank,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";
    $row[6] = ":blank,:blank,:blank";

    $row[7] = "VOLUMEUP:VOLUP,MUTE,CHANNELUP:CHUP2";
    $row[8] = "VOLUMEDOWN:VOLDOWN,EXIT,CHANNELDOWN:CHDOWN2";
    $row[9] = ":blank,:blank,:blank";

    $row[10] = "INFO,UP,MENU";
    $row[11] = "LEFT,OK,RIGHT";
    $row[12] = "AUDIO,DOWN,VIDEO";
    $row[13] = ":blank,:blank,:blank";

    $row[14] = "RED,GREEN,YELLOW,BLUE";
    $row[15] = "REWIND,PLAY,STOP,FASTFORWARD:FF";
    $row[16] = "TV,RADIO,TEXT,RECORD:REC";

    $row[17] = "attr rc_iconpath icons/remotecontrol";
    $row[18] = "attr rc_iconprefix black_btn_";
    return @row;
}

sub ENIGMA2_RClayout_RC10_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";
    $row[6] =
      "RED:rc_RED.svg,GREEN:rc_GREEN.svg,YELLOW:rc_YELLOW.svg,BLUE:rc_BLUE.svg";
    $row[7] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[8]  = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[9]  = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[10] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[11] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[12] = "VOLUMEUP:rc_VOLPLUS.svg,:rc_BLANK.svg,CHANNELUP:rc_UP.svg";
    $row[13] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,MUTE:rc_MUTE.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[14] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[15] =
        "REWIND:rc_REW.svg,PLAY:rc_PLAY.svg,"
      . "STOP:rc_STOP.svg,FASTFORWARD:rc_FF.svg";
    $row[16] =
      "TV:rc_TV.svg,RADIO:rc_RADIO.svg,TEXT:rc_TEXT.svg,RECORD:rc_REC.svg";

    $row[17] = "attr rc_iconpath icons";
    $row[18] = "attr rc_iconprefix rc_";
    return @row;
}

sub ENIGMA2_RClayout_RC10() {
    my @row;

    $row[0] = ":blank,:blank,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";
    $row[6] = "RED,GREEN,YELLOW,BLUE";
    $row[7] = ":blank,:blank,:blank";

    $row[8]  = "INFO,UP,MENU";
    $row[9]  = "LEFT,OK,RIGHT";
    $row[10] = "AUDIO,DOWN,VIDEO";
    $row[11] = ":blank,EXIT,:blank";

    $row[12] = "VOLUMEUP:VOLUP,:blank,CHANNELUP:CHUP2";
    $row[13] = "VOLUMEDOWN:VOLDOWN,MUTE,CHANNELDOWN:CHDOWN2";
    $row[14] = ":blank,:blank,:blank";

    $row[15] = "REWIND,PLAY,STOP,FASTFORWARD:FF";
    $row[16] = "TV,RADIO,TEXT,RECORD:REC";

    $row[17] = "attr rc_iconpath icons/remotecontrol";
    $row[18] = "attr rc_iconprefix black_btn_";
    return @row;
}

sub ENIGMA2_RClayout_VUplusDuo2_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,MUTE:rc_MUTE.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "REWIND:rc_REW.svg,PLAY:rc_PLAY.svg,FASTFORWARD:rc_FF.svg";
    $row[3] = "RECORD:rc_REC.svg,STOP:rc_STOP.svg,VIDEO:rc_VIDEO.svg";
    $row[4] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[5] = "TV:rc_TV.svg,AUDIO:rc_AUDIO.svg,RADIO:rc_RADIO.svg";
    $row[6] = "TEXT:rc_TEXT.svg,HELP:rc_HELP.svg,AV:rc_AV.svg";
    $row[7] = "INFO:rc_EPG.svg,MENU:rc_MENU.svg,EXIT:rc_EXIT.svg";
    $row[8] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[9]  = "VOLUMEUP:rc_VOLPLUS.svg,UP:rc_UP.svg,CHANNELUP:rc_PLUS.svg";
    $row[10] = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[11] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,DOWN:rc_DOWN.svg,CHANNELDOWN:rc_MINUS.svg";

    $row[12] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[13] =
      "RED:rc_RED.svg,GREEN:rc_GREEN.svg,YELLOW:rc_YELLOW.svg,BLUE:rc_BLUE.svg";
    $row[14] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[15] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[16] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[17] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";

    $row[18] = "attr rc_iconpath icons";
    $row[19] = "attr rc_iconprefix rc_";
    return @row;
}

sub ENIGMA2_RClayout_VUplusDuo2() {
    my @row;

    $row[0] = ":blank,MUTE,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "REWIND,PLAY,FASTFORWARD:FF";
    $row[3] = "RECORD:REC,STOP,VIDEO";
    $row[4] = ":blank,:blank,:blank";

    $row[5] = "TV,AUDIO,RADIO:RADIO";
    $row[6] = "TEXT,HELP,AV";
    $row[7] = "INFO,MENU,EXIT";
    $row[8] = ":blank,:blank,:blank";

    $row[9]  = "VOLUMEUP:VOLUP,UP,CHANNELUP:CHUP2";
    $row[10] = "LEFT,OK,RIGHT";
    $row[11] = "VOLUMEDOWN:VOLDOWN,DOWN,CHANNELDOWN:CHDOWN2";

    $row[12] = ":blank,:blank,:blank";

    $row[13] = "RED,GREEN,YELLOW,BLUE";
    $row[14] = "1,2,3";
    $row[15] = "4,5,6";
    $row[16] = "7,8,9";
    $row[17] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";

    $row[18] = "attr rc_iconpath icons/remotecontrol";
    $row[19] = "attr rc_iconprefix black_btn_";
    return @row;
}

1;

=pod
=item device
=item summary control for ENIGMA2 based receivers via network connection
=item summary_DE Steuerung von ENIGMA2 basierte Receiver &uuml;ber das Netzwerk
=begin html

    <p>
      <a name="ENIGMA2" id="ENIGMA2"></a>
    </p>
    <h3>
      ENIGMA2
    </h3>
    <ul>
      <a name="ENIGMA2define" id="ENIGMA2define"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; ENIGMA2 &lt;ip-address-or-hostname&gt; [[[[&lt;port&gt;] [&lt;poll-interval&gt;]] [&lt;http-user&gt;]] [&lt;http-password&gt;]]</code><br>
        <br>
        This module controls ENIGMA2 based devices like Dreambox or VUplus receiver via network connection.<br>
        <br>
        Defining an ENIGMA2 device will schedule an internal task (interval can be set with optional parameter &lt;poll-interval&gt; in seconds, if not set, the value is 45 seconds), which periodically reads the status of the device and triggers notify/filelog commands.<br>
        <br>
        Example:<br>
        <ul>
          <code>define SATReceiver ENIGMA2 192.168.0.10<br>
          <br>
          # With custom port<br>
          define SATReceiver ENIGMA2 192.168.0.10 8080<br>
          <br>
          # With custom interval of 20 seconds<br>
          define SATReceiver ENIGMA2 192.168.0.10 80 20<br>
          <br>
          # With HTTP user credentials<br>
          define SATReceiver ENIGMA2 192.168.0.10 80 20 root secret</code>
        </ul>
      </ul><br>
      <br>
      <a name="ENIGMA2set" id="ENIGMA2set"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined.<br>
        <ul>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device and send a WoL magic package if needed
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off
          </li>
          <li>
            <b>shutdown</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in deepstandby mode
          </li>
          <li>
            <b>reboot</b> &nbsp;&nbsp;-&nbsp;&nbsp;reboots the device
          </li>
          <li>
            <b>restartGui</b> &nbsp;&nbsp;-&nbsp;&nbsp;restarts the GUI / ENIGMA2 process
          </li>
          <li>
            <b>channel</b> channel,0...999,sRef &nbsp;&nbsp;-&nbsp;&nbsp; zap to specific channel or service reference
          </li>
          <li>
            <b>channelUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to next channel
          </li>
          <li>
            <b>channelDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to previous channel
          </li>
          <li>
            <b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage
          </li>
          <li>
            <b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level
          </li>
          <li>
            <b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level
          </li>
          <li>
            <b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute
          </li>
          <li>
            <b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; starts/resumes playback
          </li>
          <li>
            <b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pauses current playback or enables timeshift
          </li>
          <li>
            <b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stops current playback
          </li>
          <li>
            <b>record</b> &nbsp;&nbsp;-&nbsp;&nbsp; starts recording of current channel
          </li>
          <li>
            <b>input</b> tv,radio &nbsp;&nbsp;-&nbsp;&nbsp; switches between tv and radio mode
          </li>
          <li>
            <b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device
          </li>
          <li>
            <b>remoteControl</b> UP,DOWN,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands; see 'remoteControl ?' for full command list<br />
            Note: You may add the word "long" after the command to simulate a long key press.
          </li>
          <li>
            <b>showText</b> text &nbsp;&nbsp;-&nbsp;&nbsp; sends info message to screen to be displayed for 8 seconds
          </li>
          <li>
            <b>msg</b> yesno,info... &nbsp;&nbsp;-&nbsp;&nbsp; allows more complex messages as showText, see commands as listed below
          </li>
        </ul>
        <ul>
            <u>Note:</u> If you would like to restrict access to admin set-commands (-> statusRequest, reboot, restartGui, shutdown) you may set your FHEMWEB instance's attribute allowedCommands like 'set,set-user'.
            The string 'set-user' will ensure only non-admin set-commands can be executed when accessing FHEM using this FHEMWEB instance.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Messaging</u><br>
        <br>
        <ul>
          showText has predefined settings. If you would like to send more individual messages to your TV screen, the function msg can be used. For this application the following commands are available:<br>
          <br>
          <u>Type Selection:</u><br>
          <ul>
            <code>msg yesno<br>
            msg info<br>
            msg message<br>
            msg attention<br></code>
          </ul><br>
          <br>
          The following parameter are essentially needed after type specification:
          <ul>
            <code>msg &lt;TYPE&gt; &lt;TIMEOUT&gt; &lt;YOUR MESSAGETEXT&gt;<br></code>
          </ul>
        </ul>
      </ul><br>
      <br>
      <a name="ENIGMA2get" id="ENIGMA2get"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <br>
        <ul>
          <code>channel<br>
          currentMedia<br>
          currentTitle<br>
          mute<br>
          nextTitle<br>
          power<br>
          providername<br>
          servicevideosize<br>
          input<br>
          streamUrl<br>
          volume<br></code>
        </ul>
      </ul><br>
      <br>
      <a name="ENIGMA2attr" id="ENIGMA2attr"></a> <b>Attributes</b><br>
      <ul>
        <ul>
          <li>
            <b>bouquet-tv</b> - service reference address where the favorite television bouquet can be found (initially set automatically during define)
          </li>
          <li>
            <b>bouquet-radio</b> - service reference address where the favorite radio bouquet can be found (initially set automatically during define)
          </li>
          <li>
            <b>disable</b> - Disable polling (true/false)
          </li>
          <li>
            <b>http-method</b> - HTTP access method to be used; e.g. a FritzBox might need to use POST instead of GET (GET/POST)
          </li>
          <li>
            <b>http-noshutdown</b> - Set FHEM-internal HttpUtils connection close behaviour (defaults=1)
          </li>
          <li>
            <b>https</b> - Access box via secure HTTP (true/false)
          </li>
          <li>
            <b>ignoreState</b> - Do not check for available device before sending commands to it (true/false)
          </li>
          <li>
            <b>lightMode</b> - reduces regular queries (resulting in less functionality), e.g. for low performance devices. (true/false)
          </li>
          <li>
            <b>macaddr</b> - manually set specific MAC address for device; overwrites value from reading "lanmac". (true/false)
          </li>
          <li>
            <b>remotecontrol</b> - Explicitly set specific remote control unit format. This will only be considered for set-command <strong>remoteControl</strong> as of now.
          </li>
          <li>
            <b>remotecontrolChannel</b> - Switch between remote control commands used for set-commands <strong>channelUp</strong> and <strong>channelDown</strong>.
          </li>
          <li>
            <b>timeout</b> - Set different polling timeout in seconds (default=6)
          </li>
          <li>
            <b>wakeupCmd</b> - Set a command to be executed when turning on an absent device. Can be an FHEM command or Perl command in {}. Available variables: ENIGMA2 device name -> $DEVICE, ENIGMA2 device MAC address -> $MACADDR  (default=Wake-on-LAN)
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generated Readings/Events:</b><br>
      <ul>
        <ul>
          <li>
            <b>acg</b> - Shows Automatic Gain Control value in percent; reflects overall signal quality strength
          </li>
          <li>
            <b>apid</b> - Shows the audio process ID for current channel
          </li>
          <li>
            <b>ber</b> - Shows Bit Error Rate for current channel
          </li>
          <li>
            <b>channel</b> - Shows the service name of current channel or media file name; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>currentMedia</b> - The service reference ID of current channel; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>currentTitle</b> - Shows the title of the running event; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>enigmaversion</b> - Shows the installed version of ENIGMA2
          </li>
          <li>
            <b>eventcurrenttime</b> - Shows the current time of running event as UNIX timestamp
          </li>
          <li>
            <b>eventcurrenttime_hr</b> - Shows the current time of running event in human-readable format
          </li>
          <li>
            <b>eventcurrenttime_next</b> - Shows the current time of next event as UNIX timestamp
          </li>
          <li>
            <b>eventcurrenttime_next_hr</b> - Shows the current time of next event in human-readable format
          </li>
          <li>
            <b>eventdescription</b> - Shows the description of running event
          </li>
          <li>
            <b>eventdescriptionextended</b> - Shows the extended description of running event
          </li>
          <li>
            <b>eventdescriptionextended_next</b> - Shows the extended description of next event
          </li>
          <li>
            <b>eventdescription_next</b> - Shows the description of next event
          </li>
          <li>
            <b>evenduration</b> - Shows the total duration time of running event in seconds
          </li>
          <li>
            <b>evenduration_hr</b> - Shows the total duration time of running event in human-readable format
          </li>
          <li>
            <b>evenduration_next</b> - Shows the total duration time of next event in seconds
          </li>
          <li>
            <b>evenduration_next_hr</b> - Shows the total duration time of next event in human-readable format
          </li>
          <li>
            <b>eventname</b> - Shows the name of running event
          </li>
          <li>
            <b>eventname_next</b> - Shows the name of next event
          </li>
          <li>
            <b>eventremaining</b> - Shows the remaining duration time of running event in seconds
          </li>
          <li>
            <b>eventremaining_hr</b> - Shows the remaining duration time of running event in human-readable format
          </li>
          <li>
            <b>eventremaining_next</b> - Shows the remaining duration time of next event in seconds
          </li>
          <li>
            <b>eventremaining_next_hr</b> - Shows the remaining duration time of next event in human-readable format
          </li>
          <li>
            <b>eventstart</b> - Shows the starting time of running event as UNIX timestamp
          </li>
          <li>
            <b>eventstart_hr</b> - Shows the starting time of running event in human readable format
          </li>
          <li>
            <b>eventstart_next</b> - Shows the starting time of next event as UNIX timestamp
          </li>
          <li>
            <b>eventstart_next_hr</b> - Shows the starting time of next event in human readable format
          </li>
          <li>
            <b>eventtitle</b> - Shows the title of the running event
          </li>
          <li>
            <b>eventtitle_next</b> - Shows the title of the next event
          </li>
          <li>
            <b>fpversion</b> - Shows the firmware version for the front processor
          </li>
          <li>
            <b>hddX_capacity</b> - Shows the total capacity of the installed hard drive in GB
          </li>
          <li>
            <b>hddX_free</b> - Shows the free capacity of the installed hard drive in GB
          </li>
          <li>
            <b>hddX_model</b> - Shows hardware details for the installed hard drive
          </li>
          <li>
            <b>imageversion</b> - Shows the version for the installed software image
          </li>
          <li>
            <b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>iswidescreen</b> - Indicates widescreen format - 0=off 1=on
          </li>
          <li>
            <b>lanmac</b> - Shows the device MAC address
          </li>
          <li>
            <b>model</b> - Shows details about the device hardware
          </li>
          <li>
            <b>mute</b> - Reports the mute status of the device (can be "on" or "off")
          </li>
          <li>
            <b>nextTitle</b> - Shows the title of the next event; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>onid</b> - The ON ID
          </li>
          <li>
            <b>pcrpid</b> - The PCR process ID
          </li>
          <li>
            <b>pmtpid</b> - The PMT process ID
          </li>
          <li>
            <b>power</b> - Reports the power status of the device (can be "on" or "off")
          </li>
          <li>
            <b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is basically limited to turn it on again. This will only work if the device supports Wake-On-LAN packages, otherwise command "on" will have no effect.
          </li>
          <li>
            <b>providername</b> - Service provider of current channel
          </li>
          <li>
            <b>recordings</b> - Number of active recordings
          </li>
          <li>
            <b>recordingsX_name</b> - name of active recording no. X
          </li>
          <li>
            <b>recordingsX_servicename</b> - servicename of active recording no. X
          </li>
          <li>
            <b>recordings_next</b> - Shows the time of next recording as UNIX timestamp
          </li>
          <li>
            <b>recordings_next_hr</b> - Shows the time of next recording as human-readable format
          </li>
          <li>
            <b>recordings_next_counter</b> - Shows the time until next recording starts in seconds
          </li>
          <li>
            <b>recordings_next_counter_hr</b> - Shows the time until next recording starts human-readable format
          </li>
          <li>
            <b>recordings_next_name</b> - name of next recording
          </li>
          <li>
            <b>recordings_next_servicename</b> - servicename of next recording
          </li>
          <li>
            <b>recordings_error</b> - counter for failed recordings in timerlist
          </li>
          <li>
            <b>recordings_finished</b> - counter for finished recordings in timerlist
          </li>
          <li>
            <b>servicename</b> - Name for current channel
          </li>
          <li>
            <b>servicereference</b> - The service reference ID of current channel
          </li>
          <li>
            <b>servicevideosize</b> - Video resolution for current channel
          </li>
          <li>
            <b>sid</b> - The S-ID
          </li>
          <li>
            <b>snr</b> - Shows Signal to Noise for current channel in percent
          </li>
          <li>
            <b>snrdb</b> - Shows Signal to Noise in dB
          </li>
          <li>
            <b>state</b> - Reports current power state and an absence of the device (can be "on", "off" or "absent")
          </li>
          <li>
            <b>tsid</b> - The TS ID
          </li>
          <li>
            <b>tuner_X</b> - Details about the used tuner hardware
          </li>
          <li>
            <b>txtpid</b> - The TXT process ID
          </li>
          <li>
            <b>videoheight</b> - Height of the video resolution for current channel
          </li>
          <li>
            <b>videowidth</b> - Width of the video resolution for current channel
          </li>
          <li>
            <b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)
          </li>
          <li>
            <b>vpid</b> - The Video process ID
          </li>
          <li>
            <b>webifversion</b> - Type and version of the used web interface
          </li>
        </ul>
      </ul>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="ENIGMA2" id="ENIGMA2"></a>
    </p>
    <h3>
      ENIGMA2
    </h3>
    <ul>
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </ul>
    <ul>
      <a href='http://fhem.de/commandref.html#ENIGMA2'>ENIGMA2</a>
    </ul>

=end html_DE

=cut

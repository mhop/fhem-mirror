###############################################################################
# $Id$
package main;
use strict;
use warnings;
use Data::Dumper;
use Symbol qw<qualify_to_ref>;
use File::Path;
use File::stat;
use File::Temp;
use File::Copy;

# initialize ##################################################################
sub ONKYO_AVR_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "ONKYO_AVR_Initialize: Entering";

    require "$attr{global}{modpath}/FHEM/DevIo.pm";
    require "$attr{global}{modpath}/FHEM/ONKYOdb.pm";

    $hash->{DefFn}       = "ONKYO_AVR_Define";
    $hash->{UndefFn}     = "ONKYO_AVR_Undefine";
    $hash->{SetFn}       = "ONKYO_AVR_Set";
    $hash->{GetFn}       = "ONKYO_AVR_Get";
    $hash->{ReadFn}      = "ONKYO_AVR_Read";
    $hash->{WriteFn}     = "ONKYO_AVR_Write";
    $hash->{ReadyFn}     = "ONKYO_AVR_Ready";
    $hash->{NotifyFn}    = "ONKYO_AVR_Notify";
    $hash->{ShutdownFn}  = "ONKYO_AVR_Shutdown";
    $hash->{parseParams} = 1;

    no warnings 'qw';
    my @attrList = qw(
      do_not_notify:1,0
      disabledForIntervals
      volumeSteps:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
      volumeMax:slider,0,1,100
      inputs
      disable:0,1
      model
      wakeupCmd:textField
      connectionCheck:off,30,45,60,75,90,105,120
      timeout:1,2,3,4,5
    );
    use warnings 'qw';
    $hash->{AttrList} = join( " ", @attrList ) . " " . $readingFnAttributes;

    $data{RC_layout}{ONKYO_AVR_SVG} = "ONKYO_AVR_RClayout_SVG";
    $data{RC_layout}{ONKYO_AVR}     = "ONKYO_AVR_RClayout";
    $data{RC_makenotify}{ONKYO_AVR} = "ONKYO_AVR_RCmakenotify";

    # 98_powerMap.pm support
    $hash->{powerMap} = {
        model => {
            'TX-NR626' => {
                rname_E => 'energy',
                rname_P => 'consumption',
                map     => {
                    stateAV => {
                        absent => 0,
                        off    => 0,
                        muted  => 85,
                        '*'    => 140,
                    },
                },
            },
        },
    };
}

# regular Fn ##################################################################
sub ONKYO_AVR_Define($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name  = $hash->{NAME};
    my $infix = "ONKYO_AVR";

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Define()";

    eval { require XML::Simple; };
    return "Please install Perl XML::Simple to use module ONKYO_AVR"
      if ($@);

    if ( int(@$a) < 3 ) {
        my $msg =
"Wrong syntax: define <name> ONKYO_AVR { <ip-or-hostname[:port]> | <devicename[\@baudrate]> } [<protocol-version>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );

    $hash->{Clients} = ":ONKYO_AVR_ZONE:";
    $hash->{TIMEOUT} = AttrVal( $name, "timeout", "3" );

    # used zone to control
    $hash->{ZONE}        = "1";
    $hash->{INPUT}       = "";
    $hash->{SCREENLAYER} = "0";

    # protocol version
    $hash->{PROTOCOLVERSION} = @$a[3] || 2013;
    if ( !( $hash->{PROTOCOLVERSION} =~ /^(2013|pre2013)$/ ) ) {
        return "Invalid protocol, choose one of 2013 pre2013";
    }

    if (
        $hash->{PROTOCOLVERSION} eq "pre2013"
        && ( !exists( $attr{$name}{model} )
            || $attr{$name}{model} ne $hash->{PROTOCOLVERSION} )
      )
    {
        $attr{$name}{model} = $hash->{PROTOCOLVERSION};
    }

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        fhem 'attr ' . $name . ' stateFormat stateAV';
        fhem 'attr ' . $name
          . ' cmdIcon muteT:rc_MUTE previous:rc_PREVIOUS next:rc_NEXT play:rc_PLAY pause:rc_PAUSE stop:rc_STOP shuffleT:rc_SHUFFLE repeatT:rc_REPEAT';
        fhem 'attr ' . $name . ' webCmd volume:muteT:input:previous:next';
        fhem 'attr ' . $name
          . ' devStateIcon on:rc_GREEN@green:off off:rc_STOP:on absent:rc_RED playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play muted:rc_MUTE@green:muteT fast-rewind:rc_REW@green:play fast-forward:rc_FF@green:play interrupted:rc_PAUSE@yellow:play';
    }
    $hash->{helper}{receiver}{device}{zonelist}{zone}{1}{name}  = "Main";
    $hash->{helper}{receiver}{device}{zonelist}{zone}{1}{value} = "1";
    $modules{ONKYO_AVR_ZONE}{defptr}{$name}{1}                  = $hash;

    $hash->{DeviceName} = @$a[2];

    if ( ONKYO_AVR_addExtension( $name, "ONKYO_AVR_CGI", $infix ) ) {
        $hash->{fhem}{infix} = $infix;
    }

    # connect using serial connection (old blocking style)
    if (   $hash->{DeviceName} =~ m/^UNIX:(SEQPACKET|STREAM):(.*)$/
        || $hash->{DeviceName} =~ m/^FHEM:DEVIO:(.*)(:(.*))/ )
    {
        my $ret = DevIo_OpenDev( $hash, 0, "ONKYO_AVR_DevInit" );
        return $ret;
    }

    # connect using TCP connection (non-blocking style)
    else {
        # add missing port if required
        $hash->{DeviceName} = $hash->{DeviceName} . ":60128"
          if ( $hash->{DeviceName} !~ m/^(.+):([0-9]+)$/ );

        DevIo_OpenDev(
            $hash, 0,
            "ONKYO_AVR_DevInit",
            sub() {
                my ( $hash, $err ) = @_;
                Log3 $name, 4, "ONKYO_AVR $name: $err" if ($err);
            }
        );
    }

    return undef;
}

sub ONKYO_AVR_Undefine($$) {
    my ( $hash, $name ) = @_;

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Undefine()";

    if ( defined( $hash->{fhem}{infix} ) ) {
        ONKYO_AVR_removeExtension( $hash->{fhem}{infix} );
    }

    RemoveInternalTimer($hash);

    foreach my $d ( sort keys %defs ) {
        if (   defined( $defs{$d} )
            && defined( $defs{$d}{IODev} )
            && $defs{$d}{IODev} == $hash )
        {
            my $lev = ( $reread_active ? 4 : 2 );
            Log3 $name, $lev, "deleting port for $d";
            delete $defs{$d}{IODev};
        }
    }

    DevIo_CloseDev($hash);
    return undef;
}

sub ONKYO_AVR_Set($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name     = $hash->{NAME};
    my $zone     = $hash->{ZONE};
    my $state    = ReadingsVal( $name, "power", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $return;
    my $reading;
    my $inputs_txt   = "";
    my $channels_txt = "";
    my @implicit_cmds;
    my $implicit_txt = "";

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Set()";

    return "Argument is missing" if ( int(@$a) < 1 );

    # Input alias handling
    if ( defined( $attr{$name}{inputs} ) && $attr{$name}{inputs} ne "" ) {
        my @inputs = split( ':', $attr{$name}{inputs} );

        if (@inputs) {
            foreach (@inputs) {
                if (m/[^,\s]+(,[^,\s]+)+/) {
                    my @input_names = split( ',', $_ );
                    $inputs_txt .= $input_names[1] . ",";
                    $input_names[1] =~ s/\s/_/g;
                    $hash->{helper}{receiver}{input_aliases}{ $input_names[0] }
                      = $input_names[1];
                    $hash->{helper}{receiver}{input_names}{ $input_names[1] } =
                      $input_names[0];
                }
                else {
                    $inputs_txt .= $_ . ",";
                }
            }
        }

        $inputs_txt =~ s/\s/_/g;
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # if we could read the actual available inputs from the receiver, use them
    elsif (defined( $hash->{helper}{receiver} )
        && ref( $hash->{helper}{receiver} ) eq "HASH"
        && defined( $hash->{helper}{receiver}{device}{selectorlist}{count} )
        && $hash->{helper}{receiver}{device}{selectorlist}{count} > 0 )
    {

        foreach my $input (
            @{ $hash->{helper}{receiver}{device}{selectorlist}{selector} } )
        {
            if (   $input->{value} eq "1"
                && $input->{zone} ne "00"
                && $input->{id} ne "80" )
            {
                my $id   = $input->{id};
                my $name = trim( $input->{name} );
                $inputs_txt .= $name . ",";
            }
        }

        $inputs_txt =~ s/\s/_/g;
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # use general list of possible inputs
    else {
        # Find out valid inputs
        my $inputs =
          ONKYOdb::ONKYO_GetRemotecontrolValue( $zone,
            ONKYOdb::ONKYO_GetRemotecontrolCommand( $zone, "input" ) );

        foreach my $input ( sort keys %{$inputs} ) {
            $inputs_txt .= $input . ","
              if ( !( $input =~ /^(07|08|09|up|down|query)$/ ) );
        }
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # list of network channels/services
    my $channels_src = "internal";
    if (   defined( $hash->{helper}{receiver} )
        && ref( $hash->{helper}{receiver} ) eq "HASH"
        && defined( $hash->{helper}{receiver}{device}{netservicelist}{count} )
        && $hash->{helper}{receiver}{device}{netservicelist}{count} > 0 )
    {

        foreach my $id (
            sort keys
            %{ $hash->{helper}{receiver}{device}{netservicelist}{netservice} } )
        {
            if (
                defined(
                    $hash->{helper}{receiver}{device}{netservicelist}
                      {netservice}{$id}{value}
                )
                && $hash->{helper}{receiver}{device}{netservicelist}
                {netservice}{$id}{value} eq "1"
              )
            {
                $channels_txt .=
                  trim( $hash->{helper}{receiver}{device}{netservicelist}
                      {netservice}{$id}{name} )
                  . ",";
            }
        }

        $channels_txt =~ s/\s/_/g;
        $channels_txt = substr( $channels_txt, 0, -1 );
        $channels_src = "receiver";
    }

    # use general list of possible channels
    else {
        # Find out valid channels
        my $channels =
          ONKYOdb::ONKYO_GetRemotecontrolValue( "1",
            ONKYOdb::ONKYO_GetRemotecontrolCommand( "1", "net-service" ) );

        foreach my $channel ( sort keys %{$channels} ) {
            $channels_txt .= $channel . ","
              if ( !( $channel =~ /^(up|down|query)$/ ) );
        }
        $channels_txt = substr( $channels_txt, 0, -1 );
    }

    # for each reading, check if there is a known command for it
    # and allow to set values if there are any available
    if ( defined( $hash->{READINGS} ) ) {

        foreach my $reading ( keys %{ $hash->{READINGS} } ) {
            my $cmd_raw =
              ONKYOdb::ONKYO_GetRemotecontrolCommand( $zone, $reading );
            my @readingExceptions = (
                "volume", "input", "mute", "sleep", "center-temporary-level",
                "subwoofer-temporary-level", "balance", "preset",
            );

            if ( $cmd_raw && !( grep $_ eq $reading, @readingExceptions ) ) {
                my $cmd_details =
                  ONKYOdb::ONKYO_GetRemotecontrolCommandDetails( $zone,
                    $cmd_raw );

                my $value_list = "";
                my $debuglist;
                foreach my $value ( keys %{ $cmd_details->{values} } ) {
                    next
                      if ( $value eq "QSTN" );

                    if ( defined( $cmd_details->{values}{$value}{name} ) ) {
                        $value_list .= "," if ( $value_list ne "" );

                        $value_list .= $cmd_details->{values}{$value}{name}
                          if (
                            ref( $cmd_details->{values}{$value}{name} ) eq "" );

                        $value_list .= $cmd_details->{values}{$value}{name}[0]
                          if (
                            ref( $cmd_details->{values}{$value}{name} ) eq
                            "ARRAY" );
                    }
                }

                if ( $value_list ne "" ) {
                    push @implicit_cmds, $reading;
                    $implicit_txt .= " $reading:$value_list";
                }
            }

            # tone-*
            elsif ( $reading =~ /^tone.*-([a-zA-Z]+)$/ ) {
                $implicit_txt .= " $reading:slider,-10,1,10";
            }

            # center-temporary-level
            elsif ( $reading eq "center-temporary-level" ) {
                $implicit_txt .= " $reading:slider,-12,1,12";
            }

            # subwoofer*-temporary-level
            elsif ( $reading =~ /^subwoofer.*-temporary-level$/ ) {
                $implicit_txt .= " $reading:slider,-15,1,12";
            }
        }
    }

    my $preset_txt = "";
    if ( defined( $hash->{helper}{receiver}{preset} ) ) {

        foreach my $id (
            sort
            keys %{ $hash->{helper}{receiver}{preset} }
          )
        {
            my $presetName =
              $hash->{helper}{receiver}{preset}{$id};
            next if ( !$presetName || $presetName eq "" );

            $preset_txt = "preset:" if ( $preset_txt eq "" );
            $preset_txt .= ","
              if ( $preset_txt eq "preset:"
                && ReadingsVal( $name, "preset", "-" ) eq "" );

            $presetName =~ s/\s/_/g;
            $preset_txt .= $presetName . ",";
        }
    }
    $preset_txt = substr( $preset_txt, 0, -1 ) if ( $preset_txt ne "" );

    if ( $preset_txt eq "" ) {
        $preset_txt = "preset:";
        $preset_txt .= "," if ( ReadingsVal( $name, "preset", "-" ) eq "" );
        $preset_txt .=
"1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40";
    }

    my $shuffle_txt = "shuffle:";
    $shuffle_txt .= "," if ( ReadingsVal( $name, "shuffle", "-" ) eq "-" );
    $shuffle_txt .= "off,on,on-album,on-folder";

    my $repeat_txt = "repeat:";
    $repeat_txt .= "," if ( ReadingsVal( $name, "repeat", "-" ) eq "-" );
    $repeat_txt .= "off,all,all-folder,one";

    my $usage =
        "Unknown argument '"
      . @$a[1]
      . "', choose one of toggle:noArg on:noArg off:noArg volume:slider,0,1,100 volumeDown:noArg volumeUp:noArg mute:off,on muteT:noArg play:noArg pause:noArg stop:noArg previous:noArg next:noArg shuffleT:noArg repeatT:noArg remoteControl:play,pause,repeat,stop,top,down,up,right,delete,display,ff,left,mode,return,rew,select,setup,0,1,2,3,4,5,6,7,8,9,prev,next,shuffle,menu channelDown:noArg channelUp:noArg inputDown:noArg inputUp:noArg internet-radio-preset:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40 input:"
      . $inputs_txt;
    $usage .= " channel:$channels_txt";
    $usage .= " presetDown:noArg presetUp:noArg $preset_txt";
    $usage .= " $shuffle_txt";
    $usage .= " $repeat_txt";
    $usage .= $implicit_txt if ( $implicit_txt ne "" );
    $usage .= " sleep:off,5,10,15,30,60,90";

    if ( ReadingsVal( $name, "currentTrackPosition", "--:--" ) ne "--:--" ) {
        $usage .= " currentTrackPosition";
    }

    my $cmd = '';

    return "Device is offline and cannot be controlled at that stage."
      if ( $presence eq "absent"
        && lc( @$a[1] ) ne "on"
        && lc( @$a[1] ) ne "?"
        && lc( @$a[1] ) ne "help" );

    readingsBeginUpdate($hash);

    # create inputList reading for frontends
    readingsBulkUpdate( $hash, "inputList", $inputs_txt )
      if ( ReadingsVal( $name, "inputList", "-" ) ne $inputs_txt );

    # create channelList reading for frontends
    readingsBulkUpdate( $hash, "channelList", $channels_txt )
      if (
        (
            $channels_src eq "internal"
            && ReadingsVal( $name, "channelList", "-" ) eq "-"
        )
        || ( $channels_src eq "receiver"
            && ReadingsVal( $name, "channelList", "-" ) ne $channels_txt )
      );

    # channel
    if ( lc( @$a[1] ) eq "channel" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "Syntax: CHANNELNAME [USERNAME PASSWORD]";
        }
        else {
            if ( $state eq "off" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
                my $ret = fhem "sleep 5;set $name channel " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( $hash->{INPUT} ne "2B" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "input", "2B" );
                my $ret = fhem "sleep 1;set $name channel " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( ReadingsVal( $name, "channel", "" ) ne @$a[2]
                || ( defined( @$a[3] ) && defined( @$a[4] ) ) )
            {

                my $servicename = "";
                my $channelname = @$a[2];

                if (
                       defined( $hash->{helper}{receiver} )
                    && ref( $hash->{helper}{receiver} ) eq "HASH"
                    && defined(
                        $hash->{helper}{receiver}{device}{netservicelist}{count}
                    )
                    && $hash->{helper}{receiver}{device}{netservicelist}{count}
                    > 0
                  )
                {

                    $channelname =~ s/_/ /g;

                    foreach my $id (
                        sort keys %{
                            $hash->{helper}{receiver}{device}{netservicelist}
                              {netservice}
                        }
                      )
                    {
                        if (
                            defined(
                                $hash->{helper}{receiver}{device}
                                  {netservicelist}{netservice}{$id}{value}
                            )
                            && $hash->{helper}{receiver}{device}
                            {netservicelist}{netservice}{$id}{value} eq "1"
                            && $hash->{helper}{receiver}{device}
                            {netservicelist}{netservice}{$id}{name} eq
                            $channelname
                          )
                        {
                            $servicename .= uc($id);
                            last;
                        }
                    }
                }
                else {
                    my $channels = ONKYOdb::ONKYO_GetRemotecontrolValue(
                        "1",
                        ONKYOdb::ONKYO_GetRemotecontrolCommand(
                            "1", "net-service"
                        )
                    );

                    $servicename = $channels->{$channelname}
                      if ( defined( $channels->{$channelname} ) );
                }

                Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

                $servicename = uc($channelname)
                  if ( $servicename eq "" );

                $servicename .= "0"          if ( !defined( @$a[3] ) );
                $servicename .= "1" . @$a[3] if ( defined( @$a[3] ) );
                $servicename .= @$a[4]       if ( defined( @$a[4] ) );

                $return =
                  ONKYO_AVR_SendCommand( $hash, "net-service", $servicename );
            }
        }
    }

    # channelDown
    elsif ( lc( @$a[1] ) eq "channeldown" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name channelDown";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "2B" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "input", "2B" );
            my $ret = fhem "sleep 1;set $name channelDown";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "chdn" );
        }
    }

    # channelUp
    elsif ( lc( @$a[1] ) eq "channelup" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name channelUp";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "2B" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "input", "2B" );
            my $ret = fhem "sleep 1;set $name channelUp";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "chup" );
        }
    }

    # currentTrackPosition
    elsif ( lc( @$a[1] ) eq "currenttrackposition" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {

            if ( @$a[2] !~ /^[0-9][0-9]:[0-5][0-9]$/ ) {
                $return =
                  "Time needs to have format mm:ss and between 00:00 and 99:59";
            }
            else {
                $return =
                  ONKYO_AVR_SendCommand( $hash, "net-usb-time-seek", @$a[2] );
            }
        }
    }

    # internet-radio-preset
    elsif ( lc( @$a[1] ) eq "internet-radio-preset" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            if ( $state eq "off" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
                my $ret = fhem "sleep 5;set $name " . @$a[1] . " " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( $hash->{INPUT} ne "2B" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "input", "2B" );
                my $ret = fhem "sleep 5;set $name " . @$a[1] . " " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( @$a[2] =~ /^\d*$/ ) {
                Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];
                $return = ONKYO_AVR_SendCommand(
                    $hash,
                    lc( @$a[1] ),
                    ONKYO_AVR_dec2hex( @$a[2] )
                );
            }
            else {
                $return = "Invalid argument format";
            }
        }
    }

    # preset
    elsif ( lc( @$a[1] ) eq "preset" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            if ( $state eq "off" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
                my $ret = fhem "sleep 5;set $name preset " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( $hash->{INPUT} ne "24" && $hash->{INPUT} ne "25" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "input", "24" );
                my $ret = fhem "sleep 1;set $name preset " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( lc( @$a[2] ) eq "up" ) {
                Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];
                $return = ONKYO_AVR_SendCommand( $hash, lc( @$a[1] ), "UP" );
            }
            elsif ( lc( @$a[2] ) eq "down" ) {
                Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];
                $return =
                  ONKYO_AVR_SendCommand( $hash, lc( @$a[1] ), "DOWN" );
            }
            elsif ( @$a[2] =~ /^\d*$/ ) {
                Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];
                $return = ONKYO_AVR_SendCommand(
                    $hash,
                    lc( @$a[1] ),
                    ONKYO_AVR_dec2hex( @$a[2] )
                );
            }
            elsif ( defined( $hash->{helper}{receiver}{preset} ) ) {

                foreach
                  my $id ( sort keys %{ $hash->{helper}{receiver}{preset} } )
                {
                    my $presetName =
                      $hash->{helper}{receiver}{preset}{$id};
                    next if ( !$presetName || $presetName eq "" );

                    $presetName =~ s/\s/_/g;

                    if ( $presetName eq @$a[2] ) {
                        Log3 $name, 3,
                          "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

                        $return =
                          ONKYO_AVR_SendCommand( $hash, lc( @$a[1] ), uc($id) );

                        last;
                    }
                }
            }
        }
    }

    # presetDown
    elsif ( lc( @$a[1] ) eq "presetdown" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name presetDown";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "24" && $hash->{INPUT} ne "25" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "input", "24" );
            my $ret = fhem "sleep 1;set $name presetDown";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
            $return = ONKYO_AVR_SendCommand( $hash, "preset", "down" );
        }
    }

    # presetUp
    elsif ( lc( @$a[1] ) eq "presetup" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name presetUp";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "24" && $hash->{INPUT} ne "25" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "input", "24" );
            my $ret = fhem "sleep 1;set $name presetUp";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
            $return = ONKYO_AVR_SendCommand( $hash, "preset", "up" );
        }
    }

    # tone-*
    elsif ( lc( @$a[1] ) =~ /^(tone.*)-(bass|treble)$/ ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            if ( $state eq "off" ) {
                $return =
"Device power is turned off, this function is unavailable at that stage.";
            }
            elsif ( lc( @$a[2] ) eq "up" ) {
                my $setVal = "";
                $setVal = "B" if ( $2 eq "bass" );
                $setVal = "T" if ( $2 eq "treble" );
                $return =
                  ONKYO_AVR_SendCommand( $hash, lc($1), $setVal . "UP" );
            }
            elsif ( lc( @$a[2] ) eq "down" ) {
                my $setVal = "";
                $setVal = "B" if ( $2 eq "bass" );
                $setVal = "T" if ( $2 eq "treble" );
                $return =
                  ONKYO_AVR_SendCommand( $hash, lc($1), $setVal . "DOWN" );
            }
            elsif ( @$a[2] =~ /^-*\d+$/ ) {
                my $setVal = "";
                $setVal = "B" if ( $2 eq "bass" );
                $setVal = "T" if ( $2 eq "treble" );
                $setVal .= "+" if ( @$a[2] > 0 );
                $setVal .= "-" if ( @$a[2] < 0 );

                my $setVal2 = @$a[2];
                $setVal2 = substr( $setVal2, 1 ) if ( $setVal2 < 0 );
                $setVal2 = ONKYO_AVR_dec2hex($setVal2);
                $setVal2 = substr( $setVal2, 1 ) if ( $setVal2 ne "00" );

                $return =
                  ONKYO_AVR_SendCommand( $hash, lc($1), $setVal . $setVal2 );
            }
        }
    }

    # center-temporary-level
    # subwoofer-temporary-level
    elsif (lc( @$a[1] ) eq "center-temporary-level"
        || lc( @$a[1] ) eq "subwoofer-temporary-level" )
    {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            if ( $state eq "off" ) {
                $return =
"Device power is turned off, this function is unavailable at that stage.";
            }
            elsif ( lc( @$a[2] ) eq "up" ) {
                $return = ONKYO_AVR_SendCommand( $hash, lc($1), "UP" );
            }
            elsif ( lc( @$a[2] ) eq "down" ) {
                $return = ONKYO_AVR_SendCommand( $hash, lc($1), "DOWN" );
            }
            elsif ( @$a[2] =~ /^-*\d+$/ ) {
                my $setVal = "";
                $setVal = "+" if ( @$a[2] > 0 );
                $setVal = "-" if ( @$a[2] < 0 );

                my $setVal2 = @$a[2];
                $setVal2 = substr( $setVal2, 1 ) if ( $setVal2 < 0 );
                $setVal2 = ONKYO_AVR_dec2hex($setVal2);
                $setVal2 = substr( $setVal2, 1 ) if ( $setVal2 ne "00" );

                $return = ONKYO_AVR_SendCommand(
                    $hash,
                    lc( @$a[1] ),
                    $setVal . $setVal2
                );
            }
        }
    }

    # toggle
    elsif ( lc( @$a[1] ) eq "toggle" ) {
        if ( $state eq "off" ) {
            $return = fhem "set $name on";
        }
        else {
            $return = fhem "set $name off";
        }
    }

    # on
    elsif ( lc( @$a[1] ) eq "on" ) {
        if ( $presence eq "absent" ) {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " (wakeup)";
            my $wakeupCmd = AttrVal( $name, "wakeupCmd", "" );

            if ( $wakeupCmd ne "" ) {
                $wakeupCmd =~ s/\$DEVICE/$name/g;

                if ( $wakeupCmd =~ s/^[ \t]*\{|\}[ \t]*$//g ) {
                    Log3 $name, 4,
                      "ONKYO_AVR executing wake-up command (Perl): $wakeupCmd";
                    $return = eval $wakeupCmd;
                }
                else {
                    Log3 $name, 4,
                      "ONKYO_AVR executing wake-up command (fhem): $wakeupCmd";
                    $return = fhem $wakeupCmd;
                }
            }
            else {
                $return =
                  "Device is offline and cannot be controlled at that stage.";
                $return .=
"\nYou may enable network-standby to allow a permanent connection to the device by the following command:\nget $name remoteControl network-standby on"
                  if ( ReadingsVal( $name, "network-standby", "off" ) ne "on" );
            }
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
            $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );

            # don't wait for receiver to confirm power on
            #

            readingsBeginUpdate($hash);

            # power
            readingsBulkUpdate( $hash, "power", "on" )
              if ( ReadingsVal( $name, "power", "-" ) ne "on" );

            # stateAV
            my $stateAV = ONKYO_AVR_GetStateAV($hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            readingsEndUpdate( $hash, 1 );
        }
    }

    # off
    elsif ( lc( @$a[1] ) eq "off" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
        $return = ONKYO_AVR_SendCommand( $hash, "power", "off" );
    }

    # remoteControl
    elsif ( lc( @$a[1] ) eq "remotecontrol" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given, choose one of minutes off";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

            if (   lc( @$a[2] ) eq "play"
                || lc( @$a[2] ) eq "pause"
                || lc( @$a[2] ) eq "repeat"
                || lc( @$a[2] ) eq "stop"
                || lc( @$a[2] ) eq "top"
                || lc( @$a[2] ) eq "down"
                || lc( @$a[2] ) eq "up"
                || lc( @$a[2] ) eq "right"
                || lc( @$a[2] ) eq "delete"
                || lc( @$a[2] ) eq "display"
                || lc( @$a[2] ) eq "ff"
                || lc( @$a[2] ) eq "left"
                || lc( @$a[2] ) eq "mode"
                || lc( @$a[2] ) eq "return"
                || lc( @$a[2] ) eq "rew"
                || lc( @$a[2] ) eq "select"
                || lc( @$a[2] ) eq "setup"
                || lc( @$a[2] ) eq "0"
                || lc( @$a[2] ) eq "1"
                || lc( @$a[2] ) eq "2"
                || lc( @$a[2] ) eq "3"
                || lc( @$a[2] ) eq "4"
                || lc( @$a[2] ) eq "5"
                || lc( @$a[2] ) eq "6"
                || lc( @$a[2] ) eq "7"
                || lc( @$a[2] ) eq "8"
                || lc( @$a[2] ) eq "9" )
            {
                $return =
                  ONKYO_AVR_SendCommand( $hash, "net-usb", lc( @$a[2] ) );
            }
            elsif ( lc( @$a[2] ) eq "prev" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "trdown" );
            }
            elsif ( lc( @$a[2] ) eq "next" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "trup" );
            }
            elsif ( lc( @$a[2] ) eq "shuffle" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "random" );
            }
            elsif ( lc( @$a[2] ) eq "menu" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "men" );
            }
            else {
                $return = "Unsupported remoteControl command: " . @$a[2];
            }

        }
    }

    # play
    elsif ( lc( @$a[1] ) eq "play" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "play" );
        }
    }

    # pause
    elsif ( lc( @$a[1] ) eq "pause" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "pause" );
        }
    }

    # stop
    elsif ( lc( @$a[1] ) eq "stop" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "stop" );
        }
    }

    # shuffle
    elsif ( lc( @$a[1] ) eq "shuffle" || lc( @$a[1] ) eq "shufflet" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "random" );
        }
    }

    # repeat
    elsif ( lc( @$a[1] ) eq "repeat" || lc( @$a[1] ) eq "repeatt" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "repeat" );
        }
    }

    # previous
    elsif ( lc( @$a[1] ) eq "previous" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "trdown" );
        }
    }

    # next
    elsif ( lc( @$a[1] ) eq "next" ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, "net-usb", "trup" );
        }
    }

    # sleep
    elsif ( lc( @$a[1] ) eq "sleep" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given, choose one of minutes off";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

            if ( @$a[2] eq "off" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "sleep", "off" );
            }
            elsif ( @$a[2] =~ m/^\d+$/ && @$a[2] > 0 && @$a[2] <= 90 ) {
                $return =
                  ONKYO_AVR_SendCommand( $hash, "sleep",
                    ONKYO_AVR_dec2hex( @$a[2] ) );
            }
            else {
                $return =
"Argument does not seem to be a valid integer between 0 and 90";
            }
        }
    }

    # mute
    elsif ( lc( @$a[1] ) eq "mute" || lc( @$a[1] ) eq "mutet" ) {
        if ( defined( @$a[2] ) ) {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
        }

        if ( $state eq "on" ) {
            if ( !defined( @$a[2] ) || @$a[2] eq "toggle" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "mute", "toggle" );
            }
            elsif ( lc( @$a[2] ) eq "off" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "mute", "off" );
            }
            elsif ( lc( @$a[2] ) eq "on" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "mute", "on" );
            }
            else {
                $return = "Argument does not seem to be one of on off toogle";
            }
        }
        else {
            $return = "Device needs to be ON to mute/unmute audio.";
        }
    }

    # volume
    elsif ( lc( @$a[1] ) eq "volume" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            my $volm = AttrVal( $name, "volumeMax", 0 );
            @$a[2] = $volm if ( $volm && @$a[2] > $volm );
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

            if ( $state eq "on" ) {
                if ( @$a[2] =~ m/^\d+$/ && @$a[2] >= 0 && @$a[2] <= 100 ) {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "volume",
                        ONKYO_AVR_dec2hex( @$a[2] ) );
                }
                else {
                    $return =
"Argument does not seem to be a valid integer between 0 and 100";
                }
            }
            else {
                $return = "Device needs to be ON to adjust volume.";
            }
        }
    }

    # volumeUp/volumeDown
    elsif ( lc( @$a[1] ) =~ /^(volumeup|volumedown)$/ ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
        my $volumeSteps = AttrVal( $name, "volumeSteps", "1" );
        my $volume = ReadingsVal( $name, "volume", "0" );

        if ( $state eq "on" ) {
            if ( lc( @$a[1] ) eq "volumeup" ) {
                if ( $volumeSteps > 1 ) {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "volume",
                        ONKYO_AVR_dec2hex( $volume + $volumeSteps ) );
                }
                else {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "volume", "level-up" );
                }
            }
            else {
                if ( $volumeSteps > 1 ) {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "volume",
                        ONKYO_AVR_dec2hex( $volume - $volumeSteps ) );
                }
                else {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "volume", "level-down" );
                }
            }
        }
        else {
            $return = "Device needs to be ON to adjust volume.";
        }
    }

    # input
    elsif ( lc( @$a[1] ) eq "input" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No input given";
        }
        else {
            if ( $state eq "off" ) {
                $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
                $return .= fhem "sleep 2;set $name input " . @$a[2];
            }
            else {
                Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];
                $return = ONKYO_AVR_SendCommand( $hash, "input", @$a[2] );
            }
        }
    }

    # inputUp
    elsif ( lc( @$a[1] ) eq "inputup" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            $return .= fhem "sleep 2;set $name inputUp";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
            $return = ONKYO_AVR_SendCommand( $hash, "input", "up" );
        }
    }

    # inputDown
    elsif ( lc( @$a[1] ) eq "inputdown" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_SendCommand( $hash, "power", "on" );
            $return .= fhem "sleep 2;set $name inputDown";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1];
            $return = ONKYO_AVR_SendCommand( $hash, "input", "down" );
        }
    }

    # implicit commands through available readings
    elsif ( grep $_ eq @$a[1], @implicit_cmds ) {
        Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            $return = ONKYO_AVR_SendCommand( $hash, @$a[1], @$a[2] );
        }
    }

    # return usage hint
    else {
        $return = $usage;
    }

    readingsEndUpdate( $hash, 1 );

    # return result
    return $return;
}

sub ONKYO_AVR_Get($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name             = $hash->{NAME};
    my $zone             = $hash->{ZONE};
    my $state            = ReadingsVal( $name, "power", "off" );
    my $presence         = ReadingsVal( $name, "presence", "absent" );
    my $commands         = ONKYOdb::ONKYO_GetRemotecontrolCommand($zone);
    my $commands_details = ONKYOdb::ONKYO_GetRemotecontrolCommandDetails($zone);
    my $return;

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Get()";

    return "Argument is missing" if ( int(@$a) < 1 );

    # readings
    return $hash->{READINGS}{ @$a[1] }{VAL}
      if ( defined( $hash->{READINGS}{ @$a[1] } ) );

    return "Device is offline and cannot be controlled at that stage."
      if ( $presence eq "absent" );

    # createZone
    if ( lc( @$a[1] ) eq "createzone" ) {

        if ( !defined( @$a[2] ) ) {
            $return = "Syntax: ZONE ID or NAME";
        }
        else {
            $return =
                fhem "define "
              . $name . "_"
              . @$a[2]
              . " ONKYO_AVR_ZONE "
              . @$a[2];
            $return = $name . "_" . @$a[2] . " created"
              if ( !$return || $return eq "" );
        }
    }

    # statusRequest
    elsif ( lc( @$a[1] ) eq "statusrequest" ) {
        Log3 $name, 3, "ONKYO_AVR get $name " . @$a[1];

        ONKYO_AVR_SendCommand( $hash, "power",                     "query" );
        ONKYO_AVR_SendCommand( $hash, "input",                     "query" );
        ONKYO_AVR_SendCommand( $hash, "mute",                      "query" );
        ONKYO_AVR_SendCommand( $hash, "volume",                    "query" );
        ONKYO_AVR_SendCommand( $hash, "sleep",                     "query" );
        ONKYO_AVR_SendCommand( $hash, "audio-information",         "query" );
        ONKYO_AVR_SendCommand( $hash, "video-information",         "query" );
        ONKYO_AVR_SendCommand( $hash, "listening-mode",            "query" );
        ONKYO_AVR_SendCommand( $hash, "video-picture-mode",        "query" );
        ONKYO_AVR_SendCommand( $hash, "phase-matching-bass",       "query" );
        ONKYO_AVR_SendCommand( $hash, "center-temporary-level",    "query" );
        ONKYO_AVR_SendCommand( $hash, "subwoofer-temporary-level", "query" );
        fhem
"sleep 1 quiet;get $name remoteControl net-receiver-information query quiet";
    }

    # remoteControl
    elsif ( lc( @$a[1] ) eq "remotecontrol" ) {

        # Output help for commands
        if ( !defined( @$a[2] ) || @$a[2] eq "help" || @$a[2] eq "?" ) {

            my $valid_commands =
                "Usage: <command> <value>\n\nValid commands in zone$zone:\n\n\n"
              . "COMMAND\t\t\tDESCRIPTION\n\n";

            # For each valid command
            foreach my $command ( sort keys %{$commands} ) {
                my $command_raw = $commands->{$command};

                # add command including description if found
                if ( defined( $commands_details->{$command_raw}{description} ) )
                {
                    $valid_commands .=
                        $command
                      . "\t\t\t"
                      . $commands_details->{$command_raw}{description} . "\n";
                }

                # add command only
                else {
                    $valid_commands .= $command . "\n";
                }
            }

            $valid_commands .=
"\nTry '&lt;command&gt; help' to find out well known values.\n\n\n";

            $return = $valid_commands;
        }
        else {
            # Reading values for command from HASH table
            my $values =
              ONKYOdb::ONKYO_GetRemotecontrolValue( $zone,
                $commands->{ @$a[2] } );

            @$a[3] = "query"
              if ( !defined( @$a[3] ) && defined( $values->{query} ) );

            # Output help for values
            if ( !defined( @$a[3] ) || @$a[3] eq "help" || @$a[3] eq "?" ) {

                # Get all details for command
                my $command_details =
                  ONKYOdb::ONKYO_GetRemotecontrolCommandDetails( $zone,
                    $commands->{ @$a[2] } );

                my $valid_values =
                    "Usage: "
                  . @$a[2]
                  . " <value>\n\nWell known values:\n\n\n"
                  . "VALUE\t\t\tDESCRIPTION\n\n";

                # For each valid value
                foreach my $value ( sort keys %{$values} ) {

                    # add value including description if found
                    if ( defined( $command_details->{description} ) ) {
                        $valid_values .=
                            $value
                          . "\t\t\t"
                          . $command_details->{description} . "\n";
                    }

                    # add value only
                    else {
                        $valid_values .= $value . "\n";
                    }
                }

                $valid_values .= "\n\n\n";

                $return = $valid_values;
            }

            # normal processing
            else {
                Log3 $name, 3,
                  "ONKYO_AVR get $name " . @$a[1] . " " . @$a[2] . " " . @$a[3]
                  if ( !@$a[4] || @$a[4] ne "quiet" );

                ONKYO_AVR_SendCommand( $hash, @$a[2], @$a[3] );
                $return = "Sent command: " . @$a[2] . " " . @$a[3]
                  if ( !@$a[4] || @$a[4] ne "quiet" );
            }
        }
    }

    else {
        $return =
          "Unknown argument " . @$a[1] . ", choose one of statusRequest:noArg";

        # createZone
        my $zones = "";
        if ( defined( $hash->{helper}{receiver}{device}{zonelist}{zone} ) ) {
            foreach my $zoneID (
                keys %{ $hash->{helper}{receiver}{device}{zonelist}{zone} } )
            {
                next
                  if (
                    !defined(
                        $hash->{helper}{receiver}{device}{zonelist}{zone}
                          {$zoneID}{value}
                    )
                    || $hash->{helper}{receiver}{device}{zonelist}{zone}
                    {$zoneID}{value} ne "1"
                    || $zoneID eq "1"
                  );
                $zones .= "," if ( $zones ne "" );
                $zones .= $zoneID;
            }
        }
        $return .= " createZone:$zones" if ( $zones ne "" );
        $return .= " createZone:2,3,4"  if ( $zones eq "" );

        # remoteControl
        $return .= " remoteControl:";
        foreach my $command ( sort keys %{$commands} ) {
            $return .= "," . $command;
        }
    }

    return $return;
}

sub ONKYO_AVR_Read($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $state        = ReadingsVal( $name, "power", "off" );
    my $zone         = 0;
    my $definedZones = scalar keys %{ $modules{ONKYO_AVR_ZONE}{defptr}{$name} };

    # read from serial device
    my $buf = DevIo_SimpleRead($hash);
    return "" if ( !defined($buf) );

    $buf = $hash->{PARTIAL} . $buf;

    # reset connectionCheck timer
    my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
    RemoveInternalTimer($hash);
    if ( $checkInterval ne "off" ) {
        my $next = gettimeofday() + $checkInterval;
        $hash->{helper}{nextConnectionCheck} = $next;
        InternalTimer( $next, "ONKYO_AVR_connectionCheck", $hash, 0 );
    }

    Log3 $name, 5, "ONKYO_AVR $name: raw " . ONKYO_AVR_hexdump($buf);

    my $lastchr = substr( $buf, -1, 1 );
    if ( $lastchr ne "\n" ) {
        $hash->{PARTIAL} = $buf;
        Log3( $hash, 5, "ONKYO_AVR_Read: partial command received" );
        return;
    }
    else {
        $hash->{PARTIAL} = "";
    }

    my $length = length $buf;
    return unless ( $length >= 16 );

    my ( $magic, $header_size, $data_size, $version, $res1, $res2, $res3 ) =
      unpack 'a4 N N C4', $buf;

    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected magic: expected 'ISCP', got '$magic'"
      and return
      unless ( $magic eq 'ISCP' );

    Log3 $name, 5,
"ONKYO_AVR $name: unusual packet length: $length < $header_size + $data_size"
      and return
      unless ( $length >= $header_size + $data_size );

    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected version: expected '0x01', got '0x%02x' "
      . $version
      and return
      unless ( $version == 0x01 );

    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected header size: expected '0x10', got '0x%02x' "
      . $header_size
      and return
      unless ( $header_size == 0x10 );

    substr $buf, 0, $header_size, '';

    my $value_raw = substr $buf, 0, $data_size, '';
    my $sd = substr $value_raw, 0, 2, '';
    $value_raw =~ s/([\032\r\n]|[\032\r]|[\r\n]|[\r])+$//;

    Log3 $name, 5,
      "ONKYO_AVR $name: Unexpected start/destination: expected '!1', got '$sd'"
      and return
      unless ( $sd eq '!1' );

    my $cmd_raw;
    my $cmd;
    my $value = "";

    # conversion based on zone
    foreach my $zoneID ( keys %{ $modules{ONKYO_AVR_ZONE}{defptr}{$name} } ) {
        next
          if (
            defined(
                $hash->{helper}{receiver}{device}{zonelist}{zone}{$zoneID}
                  {value}
            )
            && $hash->{helper}{receiver}{device}{zonelist}{zone}{$zoneID}{value}
            ne "1"
          );

        my $commandDB = ONKYOdb::ONKYO_GetRemotecontrolCommandDetails($zoneID);

        foreach my $key ( keys %{$commandDB} ) {
            if ( $value_raw =~ s/^$key(.*)// ) {
                $cmd_raw   = $key;
                $cmd       = $commandDB->{$cmd_raw}{name};
                $value_raw = $1;

                # Decode input through device information
                if (   $cmd eq "input"
                    && defined( $hash->{helper}{receiver} )
                    && ref( $hash->{helper}{receiver} ) eq "HASH"
                    && defined( $hash->{helper}{receiver}{input}{$value_raw} ) )
                {
                    $value = $hash->{helper}{receiver}{input}{$value_raw};
                    Log3 $name, 5,
"ONKYO_AVR $name: con $cmd($cmd_raw$value_raw): return zone$zoneID value '$value_raw' converted through device information to '"
                      . $value . "'";
                }

                # Decode through HASH table
                elsif (
                    defined(
                        $commandDB->{$cmd_raw}{values}{"$value_raw"}{name}
                    )
                  )
                {
                    if (
                        ref(
                            $commandDB->{$cmd_raw}{values}{"$value_raw"}{name}
                        ) eq "ARRAY"
                      )
                    {
                        $value =
                          $commandDB->{$cmd_raw}{values}{"$value_raw"}{name}[0];
                        Log3 $name, 5,
"ONKYO_AVR $name: con $cmd($cmd_raw$value_raw): return zone$zoneID value '$value_raw' converted through ARRAY from HASH table to '"
                          . $value . "'";
                    }
                    else {
                        $value =
                          $commandDB->{$cmd_raw}{values}{"$value_raw"}{name};
                        Log3 $name, 5,
"ONKYO_AVR $name: con $cmd($cmd_raw$value_raw): return zone$zoneID value '$value_raw' converted through VALUE from HASH table to '"
                          . $value . "'";
                    }
                }

                # return as decimal
                elsif ($value_raw =~ m/^[0-9A-Fa-f][0-9A-Fa-f]$/
                    && $cmd_raw =~
/^(MVL|ZVL|VL3|VL4|SLP|PRS|PRZ|PR3|PR4|PRM|PTS|NPR|NPZ|NP3|NP4)$/
                  )
                {
                    $value = ONKYO_AVR_hex2dec($value_raw);
                    Log3 $name, 5,
"ONKYO_AVR $name: con $cmd($cmd_raw$value_raw): return zone$zoneID value '$value_raw' converted from HEX to DEC '$value'";
                }

                # just return the original return value if there is
                # no decoding function
                elsif ( lc($value_raw) ne "n/a" ) {
                    $value = $value_raw;
                    Log3 $name, 5,
"ONKYO_AVR $name: con $cmd($cmd_raw$value_raw): unconverted return of zone$zoneID value '$value'";
                }

                # end here if we got N/A result (few exceptions)
                elsif ($cmd ne "audio-information"
                    && $cmd ne "video-information" )
                {
                    $value = $value_raw;
                    Log3 $name, 4,
"ONKYO_AVR $name: con $cmd($cmd_raw$value_raw): device sent: zone$zoneID command unavailable";
                    return;
                }

                last;
            }
        }

        if ($cmd_raw) {
            $zone = $zoneID;
            last;
        }
    }

    if ( !$cmd_raw ) {
        $cmd_raw = substr( $value_raw, 0, 3 );
        $value_raw =~ s/^...//;
        $cmd   = "_" . $cmd_raw;
        $value = $value_raw;

        Log3 $name, 4,
"ONKYO_AVR $name: con $cmd($cmd_raw$value_raw): FAIL: Don't know how to convert, not in ONKYOdb or zone may not be defined: $cmd_raw$value_raw";

        return if ( !$cmd_raw || $cmd_raw eq "" );
    }

    if ( $zone > 1 ) {
        Log3 $hash, 5, "ONKYO_AVR $name dispatch: this is for zone$zone";
        my $zoneDispatch;
        $zoneDispatch->{INPUT_RAW} = $value_raw if ( $cmd eq "input" );
        $zoneDispatch->{zone}      = $zone;
        $zoneDispatch->{$cmd}      = $value;
        Dispatch( $hash, $zoneDispatch, undef );
        return;
    }

    # Parsing for zone1 (main)
    #

    Log3 $name, 4, "ONKYO_AVR $name: rcv $cmd = $value"
      if ( $cmd ne "net-usb-jacket-art" && $cmd ne "net-usb-time-info" );

    $hash->{INPUT} = $value_raw if ( $cmd eq "input" );

    my $zoneDispatch;

    # Update readings
    readingsBeginUpdate($hash);

    if ( $cmd eq "audio-information" ) {

        my @audio_split = split( /,/, $value );
        if ( scalar(@audio_split) >= 6 ) {

            readingsBulkUpdate( $hash, "audin_src", $audio_split[0] )
              if ( ReadingsVal( $name, "audin_src", "-" ) ne $audio_split[0] );

            readingsBulkUpdate( $hash, "audin_enc", $audio_split[1] )
              if ( ReadingsVal( $name, "audin_enc", "-" ) ne $audio_split[1] );

            my ($audin_srate) = split( /[:\s]+/, $audio_split[2], 2 ) || "";
            readingsBulkUpdate( $hash, "audin_srate", $audin_srate )
              if ( ReadingsVal( $name, "audin_srate", "-" ) ne $audin_srate );

            my ($audin_ch) = split( /[:\s]+/, $audio_split[3], 2 ) || "";
            readingsBulkUpdate( $hash, "audin_ch", $audin_ch )
              if ( ReadingsVal( $name, "audin_ch", "-" ) ne $audin_ch );

            readingsBulkUpdate( $hash, "audout_mode", $audio_split[4] )
              if (
                ReadingsVal( $name, "audout_mode", "-" ) ne $audio_split[4] );

            my ($audout_ch) = split( /[:\s]+/, $audio_split[5], 2 ) || "";
            readingsBulkUpdate( $hash, "audout_ch", $audout_ch )
              if ( ReadingsVal( $name, "audout_ch", "-" ) ne $audout_ch );

        }
        else {
            foreach (
                "audin_src", "audin_enc", "audin_srate",
                "audin_ch",  "audout_ch", "audout_mode",
              )
            {
                readingsBulkUpdate( $hash, $_, "" )
                  if ( ReadingsVal( $name, $_, "-" ) ne "" );
            }
        }
    }

    elsif ( $cmd eq "video-information" ) {
        my @video_split = split( /,/, $value );
        if ( scalar(@video_split) >= 8 ) {

            # Video-in resolution
            my @vidin_res_string = split( / +/, $video_split[1] );
            my $vidin_res;
            if (   defined( $vidin_res_string[0] )
                && defined( $vidin_res_string[2] )
                && defined( $vidin_res_string[3] )
                && uc( $vidin_res_string[0] ) ne "UNKNOWN"
                && uc( $vidin_res_string[2] ) ne "UNKNOWN"
                && uc( $vidin_res_string[3] ) ne "UNKNOWN" )
            {
                $vidin_res =
                    $vidin_res_string[0] . "x"
                  . $vidin_res_string[2]
                  . $vidin_res_string[3];
            }
            else {
                $vidin_res = "";
            }

            # Video-out resolution
            my @vidout_res_string = split( / +/, $video_split[5] );
            my $vidout_res;
            if (   defined( $vidout_res_string[0] )
                && defined( $vidout_res_string[2] )
                && defined( $vidout_res_string[3] )
                && uc( $vidout_res_string[0] ) ne "UNKNOWN"
                && uc( $vidout_res_string[2] ) ne "UNKNOWN"
                && uc( $vidout_res_string[3] ) ne "UNKNOWN" )
            {
                $vidout_res =
                    $vidout_res_string[0] . "x"
                  . $vidout_res_string[2]
                  . $vidout_res_string[3];
            }
            else {
                $vidout_res = "";
            }

            # Video-in color depth
            my ($vidin_cdepth) =
              split( /[:\s]+/, $video_split[3], 2 ) || "";

            # Video-out color depth
            my ($vidout_cdepth) =
              split( /[:\s]+/, $video_split[7], 2 ) || "";

            readingsBulkUpdate( $hash, "vidin_src", $video_split[0] )
              if ( ReadingsVal( $name, "vidin_src", "-" ) ne $video_split[0] );

            readingsBulkUpdate( $hash, "vidin_res", $vidin_res )
              if ( ReadingsVal( $name, "vidin_res", "-" ) ne $vidin_res );

            readingsBulkUpdate( $hash, "vidin_cspace", $video_split[2] )
              if (
                ReadingsVal( $name, "vidin_cspace", "-" ) ne $video_split[2] );

            readingsBulkUpdate( $hash, "vidin_cdepth", $vidin_cdepth )
              if ( ReadingsVal( $name, "vidin_cdepth", "-" ) ne $vidin_cdepth );

            readingsBulkUpdate( $hash, "vidout_dst", $video_split[4] )
              if ( ReadingsVal( $name, "vidout_dst", "-" ) ne $video_split[4] );

            readingsBulkUpdate( $hash, "vidout_res", $vidout_res )
              if ( ReadingsVal( $name, "vidout_res", "-" ) ne $vidout_res );

            readingsBulkUpdate( $hash, "vidout_cspace", $video_split[6] )
              if (
                ReadingsVal( $name, "vidout_cspace", "-" ) ne $video_split[6] );

            readingsBulkUpdate( $hash, "vidout_cdepth", $vidout_cdepth )
              if (
                ReadingsVal( $name, "vidout_cdepth", "-" ) ne $vidout_cdepth );

            readingsBulkUpdate( $hash, "vidout_mode", $video_split[8] )
              if ( defined( $video_split[8] )
                && ReadingsVal( $name, "vidout_mode", "-" ) ne $video_split[8]
              );

        }
        else {
            foreach (
                "vidin_src",     "vidin_res",     "vidin_cspace",
                "vidin_cdepth",  "vidout_dst",    "vidout_res",
                "vidout_cspace", "vidout_cdepth", "vidout_mode",
              )
            {
                readingsBulkUpdate( $hash, $_, "" )
                  if ( ReadingsVal( $name, $_, "-" ) ne "" );
            }
        }
    }

    elsif ( $cmd eq "net-receiver-information" ) {

        if ( $value =~ /^<\?xml/ ) {

            no strict;
            my $xml_parser = XML::Simple->new(
                NormaliseSpace => 0,
                KeepRoot       => 0,
                ForceArray     => [ "zone", "netservice", "preset", "control" ],
                SuppressEmpty  => 0,
                KeyAttr        => {
                    zone       => "id",
                    netservice => "id",
                    preset     => "id",
                    control    => "id",
                },
            );
            delete $hash->{helper}{receiver};
            eval { $hash->{helper}{receiver} = $xml_parser->XMLin($value); };
            use strict;

            # Safe input names
            my $inputs;
            foreach my $input (
                @{ $hash->{helper}{receiver}{device}{selectorlist}{selector} } )
            {
                if (   $input->{value} eq "1"
                    && $input->{zone} ne "00"
                    && $input->{id} ne "80" )
                {
                    my $id   = uc( $input->{id} );
                    my $name = trim( $input->{name} );
                    $name =~ s/\s/_/g;
                    $hash->{helper}{receiver}{input}{$id} = $name;
                    $inputs .= $name . ":";
                }
            }
            if ( !defined( $attr{$name}{inputs} ) ) {
                $inputs = substr( $inputs, 0, -1 );
                $attr{$name}{inputs} = $inputs;
            }

            # Safe preset names
            my $presets;
            foreach my $id (
                keys %{ $hash->{helper}{receiver}{device}{presetlist}{preset} }
              )
            {
                my $name = trim(
                    $hash->{helper}{receiver}{device}{presetlist}{preset}{$id}
                      {name} );
                next if ( !$name || $name eq "" );

                $name =~ s/\s/_/g;
                $hash->{helper}{receiver}{preset}{$id} = $name;
            }

            # Zones
            my $reading = "zones";
            if ( defined( $hash->{helper}{receiver}{device}{zonelist}{zone} ) )
            {
                my $zones = "0";

                foreach my $zoneID (

                    keys %{ $hash->{helper}{receiver}{device}{zonelist}{zone} }
                  )
                {
                    next
                      if ( $hash->{helper}{receiver}{device}{zonelist}{zone}
                        {$zoneID}{value} ne "1" );
                    $zones++;
                }
                readingsBulkUpdate( $hash, $reading, $zones )
                  if ( ReadingsVal( $name, $reading, "" ) ne $zones );
            }

            # Brand
            $reading = "brand";
            if (
                defined( $hash->{helper}{receiver}{device}{$reading} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{$reading} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{$reading} );
            }

            # Model
            $reading = "model";
            if (
                defined( $hash->{helper}{receiver}{device}{$reading} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{$reading} )
              )
            {
                if ( !exists( $attr{$name}{model} )
                    || $attr{$name}{model} ne
                    $hash->{helper}{receiver}{device}{$reading} )
                {
                    $attr{$name}{model} =
                      $hash->{helper}{receiver}{device}{$reading};
                }
            }

            # Firmware version
            $reading = "firmwareversion";
            if (
                defined( $hash->{helper}{receiver}{device}{$reading} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{$reading} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{$reading} );
            }

            # device_id
            $reading = "deviceid";
            if (
                defined( $hash->{helper}{receiver}{device}{id} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{id} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{id} );
            }

            # device_year
            $reading = "deviceyear";
            if (
                defined( $hash->{helper}{receiver}{device}{year} )
                && ( !defined( $hash->{READINGS}{$reading}{VAL} )
                    || $hash->{READINGS}{$reading}{VAL} ne
                    $hash->{helper}{receiver}{device}{year} )
              )
            {
                readingsBulkUpdate( $hash, $reading,
                    $hash->{helper}{receiver}{device}{year} );
            }
        }

        # Input alias handling
        #
        if ( defined( $attr{$name}{inputs} ) ) {
            my @inputs = split( ':', $attr{$name}{inputs} );

            if (@inputs) {
                foreach (@inputs) {
                    if (m/[^,\s]+(,[^,\s]+)+/) {
                        my @input_names = split( ',', $_ );

                        $input_names[1] =~ s/\s/_/g;
                        $hash->{helper}{receiver}{input_aliases}
                          { $input_names[0] } = $input_names[1];
                        $hash->{helper}{receiver}{input_names}
                          { $input_names[1] } = $input_names[0];
                    }
                }
            }
        }

        ONKYO_AVR_SendCommand( $hash, "input", "query" );
    }

    elsif ( $cmd eq "net-usb-device-status" ) {
        if ( $value =~ /^(.)(.)(.)$/ ) {

            # network-connection
            my $netConnStatus = "none";
            $netConnStatus = "ethernet" if ( $1 eq "E" );
            $netConnStatus = "wireless" if ( $1 eq "W" );

            readingsBulkUpdate( $hash, "networkConnection", $netConnStatus )
              if ( ReadingsVal( $name, "networkConnection", "-" ) ne
                $netConnStatus );

            # usbFront
            my $usbFront = "none";
            $usbFront = "iOS"        if ( $2 eq "i" );
            $usbFront = "Memory_NAS" if ( $2 eq "M" );
            $usbFront = "wireless"   if ( $2 eq "W" );
            $usbFront = "bluetooth"  if ( $2 eq "B" );
            $usbFront = "GoogleUSB"  if ( $2 eq "G" );
            $usbFront = "disabled"   if ( $2 eq "x" );

            readingsBulkUpdate( $hash, "USB_Front", $usbFront )
              if ( ReadingsVal( $name, "USB_Front", "-" ) ne $usbFront );

            # usbRear
            my $usbRear = "none";
            $usbRear = "iOS"        if ( $3 eq "i" );
            $usbRear = "Memory_NAS" if ( $3 eq "M" );
            $usbRear = "wireless"   if ( $3 eq "W" );
            $usbRear = "bluetooth"  if ( $3 eq "B" );
            $usbRear = "GoogleUSB"  if ( $3 eq "G" );
            $usbRear = "disabled"   if ( $3 eq "x" );

            readingsBulkUpdate( $hash, "USB_Rear", $usbRear )
              if ( ReadingsVal( $name, "USB_Rear", "-" ) ne $usbRear );

        }
    }

    elsif ($cmd eq "net-usb-jacket-art"
        && $value ne "on"
        && $value ne "off" )
    {
        if ( $value =~ /^([012])([012])(.*)$/ ) {
            my $type = "bmp";
            $type = "jpg"  if ( $1 eq "1" );
            $type = "link" if ( $1 eq "2" );

            $hash->{helper}{cover}{$type}{parts} = "1" if ( "$2" eq "0" );
            $hash->{helper}{cover}{$type}{parts}++ if ( "$2" ne "0" );
            $hash->{helper}{cover}{$type}{data} = "" if ( "$2" eq "0" );
            $hash->{helper}{cover}{$type}{data} .= "$3"
              if ( "$2" eq "0" || $hash->{helper}{cover}{$type}{data} ne "" );

            Log3 $name, 4, "ONKYO_AVR $name: rcv $cmd($type) in progress, part "
              . $hash->{helper}{cover}{$type}{parts};

            # complete album art received
            if (   $2 eq "2"
                && $type eq "link"
                && $hash->{helper}{cover}{$type}{data} ne "" )
            {
                $hash->{helper}{currentCover} =
                  $hash->{helper}{cover}{$type}{data};

                readingsBulkUpdate( $hash, "currentAlbumArtURI", "" );
                readingsBulkUpdate( $hash, "currentAlbumArtURL",
                    $hash->{helper}{currentCover} );

                $zoneDispatch->{currentAlbumArtURI} = "";
                $zoneDispatch->{currentAlbumArtURL} =
                  $hash->{helper}{currentCover};
            }
            elsif ($2 eq "2"
                && $type ne "link"
                && $hash->{helper}{cover}{$type}{data} ne "" )
            {
                my $AlbumArtName = $name . "_CurrentAlbumArt." . $type;
                my $AlbumArtURI = AttrVal( "global", "modpath", "." )
                  . "/www/images/default/ONKYO_AVR/$AlbumArtName";
                my $AlbumArtURL = "?/ONKYO_AVR/cover/$AlbumArtName";

                mkpath( AttrVal( "global", "modpath", "." )
                      . '/www/images/default/ONKYO_AVR/' );
                ONKYO_AVR_WriteFile( $AlbumArtURI,
                    ONKYO_AVR_hex2image( $hash->{helper}{cover}{$type}{data} )
                );

                Log3 $name, 4,
                    "ONKYO_AVR $name: rcv $cmd($type) completed in "
                  . $hash->{helper}{cover}{$type}{parts}
                  . " parts. Saved to $AlbumArtURI";

                delete $hash->{helper}{cover}{$type}{data};
                $hash->{helper}{currentCover} = $AlbumArtURI;

                readingsBulkUpdate( $hash, "currentAlbumArtURI", $AlbumArtURI );
                readingsBulkUpdate( $hash, "currentAlbumArtURL", $AlbumArtURL );

                $zoneDispatch->{currentAlbumArtURI} = $AlbumArtURI;
                $zoneDispatch->{currentAlbumArtURL} = $AlbumArtURL;
            }
        }
        else {
            Log3 $name, 4,
              "ONKYO_AVR $name: received cover art tile could not be decoded: "
              . $value;
        }
    }

    # currentTrackPosition
    # currentTrackDuration
    elsif ( $cmd eq "net-usb-time-info" ) {
        my @times = split( /\//, $value );

        if (
            gettimeofday() - time_str2num(
                ReadingsTimestamp(
                    $name, "currentTrackPosition", "1970-01-01 01:00:00"
                )
            ) >= 5
          )
        {
            readingsBulkUpdate( $hash, "currentTrackPosition", $times[0] )
              if ( ReadingsVal( $name, "currentTrackPosition", "-" ) ne
                $times[0] );
            $zoneDispatch->{currentTrackPosition} = $times[0];
        }

        if ( ReadingsVal( $name, "currentTrackDuration", "-" ) ne $times[1] ) {
            readingsBulkUpdate( $hash, "currentTrackDuration", $times[1] );
            $zoneDispatch->{currentTrackDuration} = $times[1];
        }
    }

    # currentArtist
    elsif ( $cmd eq "net-usb-artist-name-info" ) {
        readingsBulkUpdate( $hash, "currentArtist", $value )
          if ( ReadingsVal( $name, "currentArtist", "-" ) ne $value );

        $zoneDispatch->{currentArtist} = $value;
    }

    # currentAlbum
    elsif ( $cmd eq "net-usb-album-name-info" ) {
        readingsBulkUpdate( $hash, "currentAlbum", $value )
          if ( ReadingsVal( $name, "currentAlbum", "-" ) ne $value );

        $zoneDispatch->{currentAlbum} = $value;
    }

    # currentTitle
    elsif ( $cmd eq "net-usb-title-name" ) {
        readingsBulkUpdate( $hash, "currentTitle", $value )
          if ( ReadingsVal( $name, "currentTitle", "-" ) ne $value );

        $zoneDispatch->{currentTitle} = $value;
    }

    elsif ( $cmd eq "net-usb-list-title-info" ) {

        if ( $value =~ /^(..)(.)(.)(....)(....)(..)(..)(..)(..)(..)(.*)$/ ) {

            # channel
            my $channel = $1 || "00";
            my $channelUc = uc($channel);
            $hash->{CHANNEL} = $channel;
            $channel = lc($channel);
            my $channelname = "";

            # Get all details for command
            my $command_details =
              ONKYOdb::ONKYO_GetRemotecontrolCommandDetails( "1",
                ONKYOdb::ONKYO_GetRemotecontrolCommand( "1", "net-service" ) );

            # we know the channel name from receiver info
            if (
                   defined( $hash->{helper}{receiver} )
                && ref( $hash->{helper}{receiver} ) eq "HASH"
                && defined(
                    $hash->{helper}{receiver}{device}{netservicelist}
                      {netservice}{$channel}{name}
                )
              )
            {
                $channelname =
                  $hash->{helper}{receiver}{device}{netservicelist}
                  {netservice}{$channel}{name};
                $channelname =~ s/\s/_/g;
            }

            # we know the channel name from ONKYOdb
            elsif ( defined( $command_details->{values}{$channelUc} ) ) {
                if (
                    ref( $command_details->{values}{$channelUc}{name} ) eq
                    "ARRAY" )
                {
                    $channelname =
                      $command_details->{values}{$channelUc}{name}[0];
                }
                else {
                    $channelname = $command_details->{values}{$channelUc}{name};
                }
            }

            # some specials for net-usb-list-title-info
            elsif ( $channel =~ /^f./ ) {
                $channelname = "USB_Front"      if $channel eq "f0";
                $channelname = "USB_Rear"       if $channel eq "f1";
                $channelname = "Internet_Radio" if $channel eq "f2";
                $channelname = ""               if $channel eq "f3";
            }

            # we don't know the channel name, sorry
            else {
                Log3 $name, 4,
"ONKYO_AVR $name: net-usb-list-title-info: received unknown channel ID $channel";
                $channelname = $channel;
            }

            if ( ReadingsVal( $name, "channel", "-" ) ne $channelname ) {
                my $currentAlbumArtURI = AttrVal( "global", "modpath", "." )
                  . "/FHEM/lib/UPnP/sonos_empty.jpg";
                my $currentAlbumArtURL = "?/ONKYO_AVR/cover/empty.jpg";

                readingsBulkUpdate( $hash, "channel",      $channelname );
                readingsBulkUpdate( $hash, "currentAlbum", "" )
                  if ( ReadingsVal( $name, "currentAlbum", "-" ) ne "" );
                readingsBulkUpdate( $hash, "currentAlbumArtURI",
                    $currentAlbumArtURI )
                  if ( ReadingsVal( $name, "currentAlbumArtURI", "-" ) ne
                    $currentAlbumArtURI );
                readingsBulkUpdate( $hash, "currentAlbumArtURL",
                    $currentAlbumArtURL )
                  if ( ReadingsVal( $name, "currentAlbumArtURL", "-" ) ne
                    $currentAlbumArtURL );
                readingsBulkUpdate( $hash, "currentArtist", "" )
                  if ( ReadingsVal( $name, "currentArtist", "-" ) ne "" );
                readingsBulkUpdate( $hash, "currentTitle", "" )
                  if ( ReadingsVal( $name, "currentTitle", "-" ) ne "" );
                readingsBulkUpdate( $hash, "currentTrackPosition", "--:--" )
                  if ( ReadingsVal( $name, "currentTrackPosition", "-" ) ne
                    "--:--" );
                readingsBulkUpdate( $hash, "currentTrackDuration", "--:--" )
                  if ( ReadingsVal( $name, "currentTrackDuration", "-" ) ne
                    "--:--" );

                $zoneDispatch->{CHANNEL_RAW}          = $hash->{CHANNEL};
                $zoneDispatch->{channel}              = $channelname;
                $zoneDispatch->{currentAlbum}         = "";
                $zoneDispatch->{currentAlbumArtURI}   = $currentAlbumArtURI;
                $zoneDispatch->{currentAlbumArtURL}   = $currentAlbumArtURL;
                $zoneDispatch->{currentArtist}        = "";
                $zoneDispatch->{currentTitle}         = "";
                $zoneDispatch->{currentTrackPosition} = "--:--";
                $zoneDispatch->{currentTrackDuration} = "--:--";
            }

            # screenType
            my $screenType = $2 || "0";
            my $uiTypes = {
                '0' => 'List',
                '1' => 'Menu',
                '2' => 'Playback',
                '3' => 'Popup',
                '4' => 'Keyboard',
                '5' => 'Menu List',
            };
            my $uiType = $uiTypes->{$screenType};
            readingsBulkUpdate( $hash, "screenType", $screenType )
              if ( ReadingsVal( $name, "screenType", "-" ) ne $screenType );

            # screenLayerInfo
            my $screenLayerInfo = $3 || "0";
            my $layerInfos = {
                '0' => 'NET TOP',
                '1' => 'Service Top,DLNA/USB/iPod',
                '2' => 'under 2nd Layer',
            };
            my $layerInfo = $layerInfos->{$screenLayerInfo};
            $hash->{SCREENLAYER} = $screenLayerInfo;
            readingsBulkUpdate( $hash, "screenLayerInfo", $screenLayerInfo )
              if ( readingsBulkUpdate( $hash, "screenLayerInfo", "" ) ne
                $screenLayerInfo );

            # screenListPos
            my $screenListPos = $4 || "0000";
            foreach my $line (
                keys %{ $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list} } )
            {
                $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}{$line}{listpos} =
                  0;
            }

            $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}{$screenListPos}
              {listpos} = 1
              if ( $screenListPos ne "-" );

            readingsBulkUpdate( $hash, "screenListPos", $screenListPos )
              if ( readingsBulkUpdate( $hash, "screenListPos", "" ) ne
                $screenListPos );

            # screenItemCnt
            my $screenItemCnt = $5 || "0000";
            readingsBulkUpdate( $hash, "screenItemCnt", $screenItemCnt )
              if (
                ReadingsVal( $name, "screenItemCnt", "-" ) ne $screenItemCnt );

            # screenLayer
            my $screenLayer = $6 || "00";
            readingsBulkUpdate( $hash, "screenLayer", $screenLayer )
              if ( ReadingsVal( $name, "screenLayer", "-" ) ne $screenLayer );

            # my $reserved = $7;

            my $screenIconLeft = $8 || "00";
            my $iconsLeft = {
                '00' => 'Internet Radio',
                '01' => 'Server',
                '02' => 'USB',
                '03' => 'iPod',
                '04' => 'DLNA',
                '05' => 'WiFi',
                '06' => 'Favorite',
                '10' => 'Account(Spotify)',
                '11' => 'Album(Spotify)',
                '12' => 'Playlist(Spotify)',
                '13' => 'Playlist-C(Spotify)',
                '14' => 'Starred(Spotify)',
                '15' => 'What\'s New(Spotify)',
                '16' => 'Track(Spotify)',
                '17' => 'Artist(Spotify)',
                '18' => 'Play(Spotify)',
                '19' => 'Search(Spotify)',
                '1A' => 'Folder(Spotify)',
                'FF' => 'None'
            };
            my $iconLeft = $iconsLeft->{$screenIconLeft};
            readingsBulkUpdate( $hash, "screenIconLeft", $screenIconLeft )
              if ( ReadingsVal( $name, "screenIconLeft", "-" ) ne
                $screenIconLeft );

            my $screenIconRight = $9 || "00";
            my $iconsRight = {
                '00' => 'DLNA',
                '01' => 'Favorite',
                '02' => 'vTuner',
                '03' => 'SiriusXM',
                '04' => 'Pandora',
                '05' => 'Rhapsody',
                '06' => 'Last.fm',
                '07' => 'Napster',
                '08' => 'Slacker',
                '09' => 'Mediafly',
                '0A' => 'Spotify',
                '0B' => 'AUPEO!',
                '0C' => 'radiko',
                '0D' => 'e-onkyo',
                '0E' => 'TuneIn Radio',
                '0F' => 'MP3tunes',
                '10' => 'Simfy',
                '11' => 'Home Media',
                'FF' => 'None'
            };
            my $iconRight = $iconsRight->{$screenIconRight};
            readingsBulkUpdate( $hash, "screenIconRight", $screenIconRight )
              if ( ReadingsVal( $name, "screenIconRight", "-" ) ne
                $screenIconRight );

            # screenStatus
            my $screenStatus = $10 || "00";
            my $statusInfos = {
                '00' => '',
                '01' => 'Connecting',
                '02' => 'Acquiring License',
                '03' => 'Buffering',
                '04' => 'Cannot Play',
                '05' => 'Searching',
                '06' => 'Profile update',
                '07' => 'Operation disabled',
                '08' => 'Server Start-up',
                '09' => 'Song rated as Favorite',
                '0A' => 'Song banned from station',
                '0B' => 'Authentication Failed',
                '0C' => 'Spotify Paused(max 1 device)',
                '0D' => 'Track Not Available',
                '0E' => 'Cannot Skip'
            };
            my $statusInfo = $statusInfos->{$screenStatus};
            if ( defined( $statusInfos->{$screenStatus} ) ) {
                readingsBulkUpdate( $hash, "screenStatus",
                    $statusInfos->{$screenStatus} )
                  if ( ReadingsVal( $name, "screenStatus", "-" ) ne
                    $statusInfos->{$screenStatus} );
            }
            else {
                readingsBulkUpdate( $hash, "screenStatus", $screenStatus )
                  if ( ReadingsVal( $name, "screenStatus", "-" ) ne
                    $screenStatus );
            }

            # screenTitle
            my $screenTitle = $11 || "";
            $screenTitle = "" if ( $screenTitle eq "NE" );
            readingsBulkUpdate( $hash, "screenTitle", $screenTitle )
              if ( ReadingsVal( $name, "screenTitle", "-" ) ne $screenTitle );

        }
    }

    elsif ( $cmd eq "net-usb-menu-status" ) {
        if ( $value =~ /^(.)(..)(..)(.)(.)(..)$/ ) {
            my $menuState = $1;
        }
    }

    # screen/list
    elsif ( $cmd eq "net-usb-list-info" ) {
        if ( $value =~ /^(.)(.)(.)(.*)/ ) {

            my $item;
            if ( $2 eq "-" ) {
                $item = $2;
            }
            elsif ( $2 < 10 ) {
                $item = "000" . $2;
            }
            elsif ( $2 < 100 ) {
                $item = "00" . $2;
            }
            elsif ( $2 < 1000 ) {
                $item = "0" . $2;
            }

            my $properties;
            if ( $1 ne "C" ) {
                $properties = {
                    '-' => 'no',
                    '0' => 'Playing',
                    'A' => 'Artist',
                    'B' => 'Album',
                    'F' => 'Folder',
                    'M' => 'Music',
                    'P' => 'Playlist',
                    'S' => 'Search',
                    'a' => 'Account',
                    'b' => 'Playlist-C',
                    'c' => 'Starred',
                    'd' => 'Unstarred',
                    'e' => 'What\'s New'
                };
            }

            # line item details
            if ( $1 eq "A" || $1 eq "U" ) {
                $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}{$item}{property}
                  = $3;
                $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}{$item}{data} =
                  $4;
                $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}{$item}{curser} =
                  0
                  if (
                    !defined(
                        $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}
                          {$item}{curser}
                    )
                  );

                # screenItemType
                readingsBulkUpdate( $hash, "screenItemT" . $item, $3 )
                  if ( ReadingsVal( $name, "screenItemT" . $item, "-" ) ne $3 );

                # screenItemContent
                readingsBulkUpdate( $hash, "screenItemC" . $item, $4 )
                  if ( ReadingsVal( $name, "screenItemC" . $item, "-" ) ne $4 );

            }

            # curser information
            else {
                foreach my $item (
                    keys %{ $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list} } )
                {
                    $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}{$item}{curser}
                      = 0;
                }

                $hash->{SCREEN}{ $hash->{SCREENLAYER} }{list}{$item}{curser} = 1
                  if ( $item ne "-" );

                readingsBulkUpdate( $hash, "screenCurser", $2 )
                  if ( ReadingsVal( $name, "screenCurser", "" ) ne $2 );
            }

        }
        else {
            Log3 $name, 4,
              "ONKYO_AVR $name: screen/list: ERROR - unable to parse: "
              . $value;
        }
    }

    # screen/list XML
    elsif ( $cmd eq "net-usb-list-info-xml" ) {
        if ( $value =~ /^(.)(....)(.)(.)(..)(.*)/ ) {
            Log3 $name, 4, "ONKYO_AVR $name: rcv $cmd($1) unknown type"
              and return
              if ( $1 ne "X" );

            Log3 $name, 4, "ONKYO_AVR $name: rcv $cmd($1) in progress";

            my $uiTypes = {
                '0' => 'List',
                '1' => 'Menu',
                '2' => 'Playback',
                '3' => 'Popup',
                '4' => 'Keyboard',
                '5' => 'Menu List',
            };
            my $uiType = $uiTypes->{$4};

            $hash->{helper}{listinfo}{$3}{$2} = $6;
        }
        else {
            Log3 $name, 4,
              "ONKYO_AVR $name: net-usb-list-info-xml could not be parsed: "
              . $value;
        }
    }

    elsif ( $cmd eq "net-usb-play-status" ) {
        if ( $value =~ /^(.)(.)(.)$/ ) {
            my $status;

            # playStatus
            $status = "stopped";
            $status = "playing"
              if ( $1 eq "P" );
            $status = "paused"
              if ( $1 eq "p" );
            $status = "fast-forward"
              if ( $1 eq "F" );
            $status = "fast-rewind"
              if ( $1 eq "R" );
            $status = "interrupted"
              if ( $1 eq "E" );

            readingsBulkUpdate( $hash, "playStatus", $status )
              if ( ReadingsVal( $name, "playStatus", "-" ) ne $status );

            $zoneDispatch->{playStatus} = $status;

            # stateAV
            my $stateAV = ONKYO_AVR_GetStateAV($hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            if ( $status eq "stopped" ) {

                my $currentAlbumArtURI = AttrVal( "global", "modpath", "." )
                  . "/FHEM/lib/UPnP/sonos_empty.jpg";
                my $currentAlbumArtURL = "?/ONKYO_AVR/cover/empty.jpg";

                readingsBulkUpdate( $hash, "currentAlbum", "" )
                  if ( ReadingsVal( $name, "currentAlbum", "-" ) ne "" );
                readingsBulkUpdate( $hash, "currentAlbumArtURI",
                    $currentAlbumArtURI )
                  if ( ReadingsVal( $name, "currentAlbumArtURI", "-" ) ne
                    $currentAlbumArtURI );
                readingsBulkUpdate( $hash, "currentAlbumArtURL",
                    $currentAlbumArtURL )
                  if ( ReadingsVal( $name, "currentAlbumArtURL", "-" ) ne
                    $currentAlbumArtURL );
                readingsBulkUpdate( $hash, "currentArtist", "" )
                  if ( ReadingsVal( $name, "currentArtist", "-" ) ne "" );
                readingsBulkUpdate( $hash, "currentTitle", "" )
                  if ( ReadingsVal( $name, "currentTitle", "-" ) ne "" );
                readingsBulkUpdate( $hash, "currentTrackPosition", "--:--" )
                  if ( ReadingsVal( $name, "currentTrackPosition", "-" ) ne
                    "--:--" );
                readingsBulkUpdate( $hash, "currentTrackDuration", "--:--" )
                  if ( ReadingsVal( $name, "currentTrackDuration", "-" ) ne
                    "--:--" );

                $zoneDispatch->{currentAlbum}         = "";
                $zoneDispatch->{currentAlbumArtURI}   = $currentAlbumArtURI;
                $zoneDispatch->{currentAlbumArtURL}   = $currentAlbumArtURL;
                $zoneDispatch->{currentArtist}        = "";
                $zoneDispatch->{currentTitle}         = "";
                $zoneDispatch->{currentTrackPosition} = "--:--";
                $zoneDispatch->{currentTrackDuration} = "--:--";

            }

            # repeat
            $status = "-";
            $status = "off"
              if ( $2 eq "-" );
            $status = "all"
              if ( $2 eq "R" );
            $status = "all-folder"
              if ( $2 eq "F" );
            $status = "one"
              if ( $2 eq "1" );

            readingsBulkUpdate( $hash, "repeat", $status )
              if ( ReadingsVal( $name, "repeat", "-" ) ne $status );
            $zoneDispatch->{repeat} = $status;

            # shuffle
            $status = "-";
            $status = "off"
              if ( $2 eq "-" );
            $status = "on"
              if ( $3 eq "S" );
            $status = "on-album"
              if ( $3 eq "A" );
            $status = "on-folder"
              if ( $3 eq "F" );

            readingsBulkUpdate( $hash, "shuffle", $status )
              if ( ReadingsVal( $name, "shuffle", "-" ) ne $status );
            $zoneDispatch->{shuffle} = $status;

        }
    }

    elsif ( $cmd =~ /^net-usb/ && $value ne "on" && $value ne "off" ) {
    }

    elsif ( $cmd =~ /^net-keyboard/ ) {
    }

    # net-popup-*
    elsif ( $cmd eq "net-popup-message" ) {
        if ( $value =~
            /^(B|T|L)(.*[a-z])([A-Z].*[a-z.!?])(0|1|2)([A-Z].*[a-z])$/ )
        {
            readingsBulkUpdate( $hash, "net-popup-type", "top" )
              if ( $1 eq "T" );
            readingsBulkUpdate( $hash, "net-popup-type", "bottom" )
              if ( $1 eq "B" );
            readingsBulkUpdate( $hash, "net-popup-type", "list" )
              if ( $1 eq "L" );
            readingsBulkUpdate( $hash, "net-popup-title",           $2 );
            readingsBulkUpdate( $hash, "net-popup-text",            $3 );
            readingsBulkUpdate( $hash, "net-popup-button-position", "hidden" )
              if ( $4 eq "0" || $4 eq "" );
            readingsBulkUpdate( $hash, "net-popup-button-position", $4 )
              if ( $4 ne "0" && $4 ne "" );
            readingsBulkUpdate( $hash, "net-popup-button1-text", $5 );

            $zoneDispatch->{"net-popup-type"} =
              ReadingsVal( $name, "net-popup-type", "" );
            $zoneDispatch->{"net-popup-title"} = $2;
            $zoneDispatch->{"net-popup-text"}  = $3;
            $zoneDispatch->{"net-popup-button-position"} =
              ReadingsVal( $name, "net-popup-button-position", "" );
            $zoneDispatch->{"net-popup-button1-text"} = $5;
        }
        else {
            Log3 $name, 4,
              "ONKYO_AVR $name: Could not decompile net-popup-message: $value";
        }
    }

    # tone-*
    elsif ( $cmd =~ /^tone-/ ) {
        if ( $value =~ /^B(..)T(..)$/ ) {
            my $bass         = $1;
            my $treble       = $2;
            my $bassName     = $cmd . "-bass";
            my $trebleName   = $cmd . "-treble";
            my $prefixBass   = "";
            my $prefixTreble = "";

            # tone-*-bass
            $prefixBass = "-" if ( $bass =~ /^\-.*/ );
            $bass = substr( $bass, 1 ) if ( $bass =~ /^[\+|\-].*/ );
            $bass = $prefixBass . ONKYO_AVR_hex2dec($bass);
            readingsBulkUpdate( $hash, $bassName, $bass )
              if ( ReadingsVal( $name, $bassName, "-" ) ne $bass );

            # tone-*-treble
            $prefixTreble = "-" if ( $treble =~ /^\-.*/ );
            $treble = substr( $treble, 1 ) if ( $treble =~ /^[\+|\-].*/ );
            $treble = $prefixTreble . ONKYO_AVR_hex2dec($treble);
            readingsBulkUpdate( $hash, $trebleName, $treble )
              if ( ReadingsVal( $name, $trebleName, "-" ) ne $treble );
        }

        # tone-subwoofer
        elsif ( $value =~ /^B(..)$/ ) {
            my $bass   = $1;
            my $prefix = "";

            $prefix = "-" if ( $bass =~ /^\-.*/ );
            $bass = substr( $bass, 1 ) if ( $bass =~ /^[\+|\-].*/ );
            $bass = $prefix . ONKYO_AVR_hex2dec($bass);
            readingsBulkUpdate( $hash, $cmd, $bass )
              if ( ReadingsVal( $name, $cmd, "-" ) ne $bass );
        }
    }

    else {
        if ( $cmd eq "input" ) {

            # Input alias handling
            if ( defined( $hash->{helper}{receiver}{input_aliases}{$value} ) ) {
                Log3 $name, 4,
                  "ONKYO_AVR $name: Input aliasing '$value' to '"
                  . $hash->{helper}{receiver}{input_aliases}{$value} . "'";
                $value = $hash->{helper}{receiver}{input_aliases}{$value};
            }
        }

        # subwoofer-temporary-level
        # center-temporary-level
        elsif ($cmd eq "subwoofer-temporary-level"
            || $cmd eq "center-temporary-level" )
        {
            my $prefix = "";
            $prefix = "-" if ( $value =~ /^\-.*/ );
            $value = substr( $value, 1 ) if ( $value =~ /^[\+|\-].*/ );

            $value = $prefix . ONKYO_AVR_hex2dec($value);
        }

        # preset
        elsif ( $cmd eq "preset" ) {

            if ( defined( $hash->{helper}{receiver}{preset} ) ) {

                foreach
                  my $id ( sort keys %{ $hash->{helper}{receiver}{preset} } )
                {
                    my $presetName =
                      $hash->{helper}{receiver}{preset}{$id};
                    next if ( !$presetName || $presetName eq "" );

                    $presetName =~ s/\s/_/g;

                    if ( $id eq $value ) {
                        $value = $presetName;
                        last;
                    }
                }
            }

            $value = "" if ( $value eq "0" );
            $zoneDispatch->{preset} = $value;
        }

        readingsBulkUpdate( $hash, $cmd, $value )
          if ( ReadingsVal( $name, $cmd, "-" ) ne $value );

        # stateAV
        my $stateAV = ONKYO_AVR_GetStateAV($hash);
        readingsBulkUpdate( $hash, "stateAV", $stateAV )
          if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );
    }

    readingsEndUpdate( $hash, 1 );

    if ( $zoneDispatch && $definedZones > 1 ) {
        Log3 $name, 5,
"ONKYO_AVR $name: Forwarding information from main zone1 to slave zones";
        Dispatch( $hash, $zoneDispatch, undef );
    }

    return;
}

sub ONKYO_AVR_Write($$) {
    my ( $hash, $cmd ) = @_;
    my $name = $hash->{NAME};
    my $str = ONKYO_AVR_Pack( $cmd, $hash->{PROTOCOLVERSION} );

    Log3 $name, 1,
"ONKYO_AVR $name: $hash->{DeviceName} snd ERROR - could not transcode $cmd to HEX command"
      and return
      if ( !$str );

   #    Log3 $name, 5,
   #      "ONKYO_AVR $name: $hash->{DeviceName} snd " . ONKYO_AVR_hexdump($str);
    Log3 $name, 5, "ONKYO_AVR $name: $hash->{DeviceName} snd $str";

    DevIo_SimpleWrite( $hash, "$str", 0 );

    # do connection check latest after TIMEOUT
    my $next = gettimeofday() + $hash->{TIMEOUT};
    if ( !defined( $hash->{helper}{nextConnectionCheck} )
        || $hash->{helper}{nextConnectionCheck} > $next )
    {
        $hash->{helper}{nextConnectionCheck} = $next;
        RemoveInternalTimer($hash);
        InternalTimer( $next, "ONKYO_AVR_connectionCheck", $hash, 0 );
    }
}

sub ONKYO_AVR_Ready($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, "state", "disconnected" ) eq "disconnected" ) {

        DevIo_OpenDev(
            $hash, 1, undef,
            sub() {
                my ( $hash, $err ) = @_;
                Log3 $name, 4, "ONKYO_AVR $name: $err" if ($err);
            }
        );

        return;
    }

    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags );
    if ($po) {
        ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
    }
    return ( $InBytes && $InBytes > 0 );
}

sub ONKYO_AVR_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name         = $hash->{NAME};
    my $devName      = $dev->{NAME};
    my $definedZones = scalar keys %{ $modules{ONKYO_AVR_ZONE}{defptr}{$name} };
    my $presence     = ReadingsVal( $name, "presence", "-" );

    return
      if ( !$dev->{CHANGED} );    # Some previous notify deleted the array.

    # work on global events related to us
    if ( $devName eq "global" ) {
        foreach my $change ( @{ $dev->{CHANGED} } ) {
            if (   $change !~ /^(\w+)\s(\w+)\s?(\w*)\s?(.*)$/
                || $2 ne $name )
            {
                return;
            }

            # DEFINED
            # MODIFIED
            elsif ( $1 eq "DEFINED" || $1 eq "MODIFIED" ) {
                Log3 $hash, 5,
                    "ONKYO_AVR "
                  . $name
                  . ": processing my global event $1: $3 -> $4";

                if ( lc( ReadingsVal( $name, "state", "?" ) ) eq "opened" ) {
                    DoTrigger( $name, "CONNECTED" );
                }
                else {
                    DoTrigger( $name, "DISCONNECTED" );
                }
            }

            # unknown event
            else {
                Log3 $hash, 5,
                    "ONKYO_AVR "
                  . $name
                  . ": WONT BE processing my global event $1: $3 -> $4";
            }
        }

        return;
    }

    # do nothing for any other device
    elsif ( $devName ne $name ) {
        return;
    }

    readingsBeginUpdate($hash);

    foreach my $change ( @{ $dev->{CHANGED} } ) {

        # DISCONNECTED
        if ( $change eq "DISCONNECTED" ) {
            Log3 $hash, 5, "ONKYO_AVR " . $name . ": processing change $change";

            # disable connectionCheck and wait
            # until DevIo reopened the connection
            RemoveInternalTimer($hash);

            readingsBulkUpdate( $hash, "presence", "absent" )
              if ( $presence ne "absent" );

            readingsBulkUpdate( $hash, "power", "off" )
              if ( ReadingsVal( $name, "power", "on" ) ne "off" );

            # stateAV
            my $stateAV = ONKYO_AVR_GetStateAV($hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            # send to slaves
            if ( $definedZones > 1 ) {
                Log3 $name, 5,
                  "ONKYO_AVR $name: Dispatching state change to slaves";
                Dispatch(
                    $hash,
                    {
                        "presence" => "absent",
                        "power"    => "off",
                    },
                    undef
                );
            }
        }

        # CONNECTED
        elsif ( $change eq "CONNECTED" ) {
            Log3 $hash, 5, "ONKYO_AVR " . $name . ": processing change $change";

            readingsBulkUpdate( $hash, "presence", "present" )
              if ( $presence ne "present" );

            # stateAV
            my $stateAV = ONKYO_AVR_GetStateAV($hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            ONKYO_AVR_SendCommand( $hash, "power",                  "query" );
            ONKYO_AVR_SendCommand( $hash, "network-standby",        "query" );
            ONKYO_AVR_SendCommand( $hash, "input",                  "query" );
            ONKYO_AVR_SendCommand( $hash, "mute",                   "query" );
            ONKYO_AVR_SendCommand( $hash, "volume",                 "query" );
            ONKYO_AVR_SendCommand( $hash, "sleep",                  "query" );
            ONKYO_AVR_SendCommand( $hash, "audio-information",      "query" );
            ONKYO_AVR_SendCommand( $hash, "video-information",      "query" );
            ONKYO_AVR_SendCommand( $hash, "listening-mode",         "query" );
            ONKYO_AVR_SendCommand( $hash, "video-picture-mode",     "query" );
            ONKYO_AVR_SendCommand( $hash, "phase-matching-bass",    "query" );
            ONKYO_AVR_SendCommand( $hash, "center-temporary-level", "query" );
            ONKYO_AVR_SendCommand( $hash, "subwoofer-temporary-level",
                "query" );
            fhem
"sleep 1 quiet;get $name remoteControl net-receiver-information query quiet";

            # send to slaves
            if ( $definedZones > 1 ) {
                Log3 $name, 5,
                  "ONKYO_AVR $name: Dispatching state change to slaves";
                Dispatch(
                    $hash,
                    {
                        "presence" => "present",
                    },
                    undef
                );
            }

        }
    }

    readingsEndUpdate( $hash, 1 );
}

sub ONKYO_AVR_Shutdown($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_Shutdown()";

    DevIo_CloseDev($hash);
    return undef;
}

# module Fn ####################################################################
sub ONKYO_AVR_DevInit($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( lc( ReadingsVal( $name, "state", "?" ) ) eq "opened" ) {
        DoTrigger( $name, "CONNECTED" );
    }
    else {
        DoTrigger( $name, "DISCONNECTED" );
    }
}

sub ONKYO_AVR_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "?/$link";

    return 0
      if ( defined( $data{FWEXT}{$url} )
        && $data{FWEXT}{$url}{deviceName} ne $name );

    Log3 $name, 2,
      "ONKYO_AVR $name: Registering ONKYO_AVR for webhook URI $url ...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;

    return 1;
}

sub ONKYO_AVR_removeExtension($) {
    my ($link) = @_;

    my $url  = "?/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2,
      "ONKYO_AVR $name: Unregistering ONKYO_AVR for webhook URI $url...";
    delete $data{FWEXT}{$url};
}

sub ONKYO_AVR_CGI() {
    my ($request) = @_;

    # data received
    if ( $request =~ m,^\?\/ONKYO_AVR\/cover\/(.+)\.(.+)$, ) {

        Log3 undef, 5, "ONKYO_AVR: sending cover $1.$2";

        if ( $1 eq "empty" && $2 eq "jpg" ) {
            FW_serveSpecial( 'sonos_empty', 'jpg',
                AttrVal( "global", "modpath", "." ) . '/FHEM/lib/UPnP', 1 );
        }
        else {
            FW_serveSpecial(
                $1,
                $2,
                AttrVal( "global", "modpath", "." )
                  . '/www/images/default/ONKYO_AVR',
                1
            );
        }

        return ( undef, undef );
    }

    # no data received
    else {
        Log3 undef, 5, "ONKYO_AVR: received malformed request\n$request";
    }

    return ( "text/plain; charset=utf-8", "Call failure: " . $request );
}

sub ONKYO_AVR_SendCommand($$$) {
    my ( $hash, $cmd, $value ) = @_;
    my $name = $hash->{NAME};
    my $zone = $hash->{ZONE};

    Log3 $name, 5, "ONKYO_AVR $name: called function ONKYO_AVR_SendCommand()";

    # Input alias handling
    if ( $cmd eq "input" ) {

        # Resolve input alias to correct name
        if ( defined( $hash->{helper}{receiver}{input_names}{$value} ) ) {
            $value = $hash->{helper}{receiver}{input_names}{$value};
        }

        # Resolve device specific input alias
        $value =~ s/_/ /g;
        if (
            defined(
                $hash->{helper}{receiver}{device}{selectorlist}{selector}
            )
            && ref( $hash->{helper}{receiver}{device}{selectorlist}{selector} )
            eq "ARRAY"
          )
        {

            foreach my $input (
                @{ $hash->{helper}{receiver}{device}{selectorlist}{selector} } )
            {
                if (   $input->{value} eq "1"
                    && $input->{zone} ne "00"
                    && $input->{id} ne "80"
                    && $value eq trim( $input->{name} ) )
                {
                    $value = uc( $input->{id} );
                    last;
                }
            }
        }

    }

    # Resolve command and value to ISCP raw command
    my $cmd_raw = ONKYOdb::ONKYO_GetRemotecontrolCommand( $zone, $cmd );
    my $value_raw =
      ONKYOdb::ONKYO_GetRemotecontrolValue( $zone, $cmd_raw, $value );

    if ( !defined($cmd_raw) ) {
        Log3 $name, 4,
"ONKYO_AVR $name: command '$cmd$value' is an unregistered command within zone$zone, be careful! Will be handled as raw command";
        $cmd_raw   = $cmd;
        $value_raw = $value;
    }
    elsif ( !defined($value_raw) ) {
        Log3 $name, 4,
"ONKYO_AVR $name: $cmd - Warning, value '$value' not found in HASH table, will be sent to receiver 'as is'";
        $value_raw = $value;
    }

    Log3 $name, 4, "ONKYO_AVR $name: snd $cmd -> $value ($cmd_raw$value_raw)";

    if ( $cmd_raw ne "" && $value_raw ne "" ) {
        ONKYO_AVR_Write( $hash, $cmd_raw . $value_raw );
    }

    return;
}

sub ONKYO_AVR_connectionCheck ($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $verbose = AttrVal( $name, "verbose", "" );

    RemoveInternalTimer($hash);

    $hash->{STATE} = "opened";    # assume we have an open connection
    $attr{$name}{verbose} = 0 if ( $verbose eq "" || $verbose < 4 );

    my $connState =
      DevIo_Expect( $hash,
        ONKYO_AVR_Pack( "PWRQSTN", $hash->{PROTOCOLVERSION} ),
        $hash->{TIMEOUT} );

    # successful connection
    if ( defined($connState) ) {

        # reset connectionCheck timer
        my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
        if ( $checkInterval ne "off" ) {
            my $next = gettimeofday() + $checkInterval;
            $hash->{helper}{nextConnectionCheck} = $next;
            InternalTimer( $next, "ONKYO_AVR_connectionCheck", $hash, 0 );
        }
    }

    $attr{$name}{verbose} = $verbose if ( $verbose ne "" );
    delete $attr{$name}{verbose} if ( $verbose eq "" );
}

sub ONKYO_AVR_WriteFile($$) {
    my ( $fileName, $data ) = @_;

    open IMGFILE, '>' . $fileName;
    binmode IMGFILE;
    print IMGFILE $data;
    close IMGFILE;
}

sub ONKYO_AVR_Pack($;$) {
    my ( $d, $protocol ) = @_;

    # ------------------
    # < 2013 (produced by TX-NR515)
    # ------------------
    #
    # EXAMPLE REQUEST FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 5057 5251 5354 4e0d                !1PWRQSTN.
    #
    # EXAMPLE REPLY FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 5057 5230 311a 0d0a                !1PWR01...
    #

    # ------------------
    # 2013+ (produced by TX-NR626)
    # ------------------
    #
    # EXAMPLE REQUEST FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000b 0100 0000 ISCP............
    # 2131 5057 5251 5354 4e0d 0a             !1PWRQSTN..
    #
    # EXAMPLE REPLY FOR PWRQSTN
    # 4953 4350 0000 0010 0000 000a 0100 0000 ISCP............
    # 2131 5057 5230 311a 0d0a                !1PWR01...
    #

    # add start character and destination unit type 1=receiver
    $d = '!1' . $d;

    # If protocol is defined as pre-2013 use EOF code for older models
    if ( defined($protocol) && $protocol eq "pre2013" ) {

        # <CR> = 0x0d
        $d .= "\r";
    }

    # otherwise use EOF code for newer models
    else {

        # <CR><LF> = 0x0d0a
        $d .= "\r\n";
    }

    pack( "a* N N N a*", 'ISCP', 0x10, ( length $d ), 0x01000000, $d );
}

sub ONKYO_AVR_hexdump {
    my $s = shift;
    my $r = unpack 'H*', $s;
    $s =~ s/[^ -~]/./g;
    $r . ' ' . $s;
}

sub ONKYO_AVR_hex2dec($) {
    my ($hex) = @_;
    return unpack( 's', pack 's', hex($hex) );
}

sub ONKYO_AVR_hex2image($) {
    my ($hex) = @_;
    return pack( "H*", $hex );
}

sub ONKYO_AVR_dec2hex($) {
    my ($dec) = @_;
    my $hex = uc( sprintf( "%x", $dec ) );

    return "0" . $hex if ( length($hex) eq 1 );
    return $hex;
}

sub ONKYO_AVR_GetStateAV($) {
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
    elsif ( $hash->{INPUT} eq "2B"
        && ReadingsVal( $name, "playStatus", "stopped" ) ne "stopped" )
    {
        return ReadingsVal( $name, "playStatus", "stopped" );
    }
    else {
        return ReadingsVal( $name, "power", "off" );
    }
}

sub ONKYO_AVR_RCmakenotify($$) {
    my ( $name, $ndev ) = @_;
    my $nname = "notify_$name";

    fhem( "define $nname notify $name set $ndev remoteControl " . '$EVENT', 1 );
    Log3 undef, 2, "[remotecontrol:ONKYO_AVR] Notify created: $nname";
    return "Notify created by ONKYO_AVR: $nname";
}

sub ONKYO_AVR_RClayout_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,power toggle:rc_POWER.svg";

    $row[1] =
"volume level-up:rc_VOLUP.svg,mute toggle:rc_MUTE.svg,preset up:rc_UP.svg";
    $row[2] =
"volume level-down:rc_VOLDOWN.svg,sleep:time_timer.svg,preset down:rc_DOWN.svg";

    $row[3] = ":rc_BLANK.svg,tuning up:rc_UP.svg,:rc_BLANK.svg";
    $row[4] = "left:rc_LEFT.svg,enter:rc_OK.svg,right:rc_RIGHT.svg";
    $row[5] =
"input usb:rc_USB.svg,tuning down:rc_DOWN.svg,input dlna:rc_MEDIAMENU.svg";

    $row[6] = "input tv-cd:rc_TV.svg,input fm:rc_RADIO.svg,input pc:it_pc.svg";

    $row[7] = "attr rc_iconpath icons/remotecontrol";
    $row[8] = "attr rc_iconprefix black_btn_";
    return @row;
}

sub ONKYO_AVR_RClayout() {
    my @row;

    $row[0] =
      "hdmi-output 01:HDMI_main,hdmi-output 02:HDMI_sub,power toggle:POWEROFF";

    $row[1] = "volume level-up:VOLUP,mute toggle:MUTE,preset up:UP";
    $row[2] = "volume level-down:VOLDOWN,sleep:SLEEP,preset down:DOWN";

    $row[3] = ":blank,tuning up:UP,:blank";
    $row[4] = "left:LEFT,enter:OK,right:RIGHT";
    $row[5] = "input usb:SOURCE,tuning down:DOWN,input dlna:DLNA";

    $row[6] = "input tv-cd:TV,input fm:FMRADIO,input pc:PC";

    $row[7] = "attr rc_iconpath icons/remotecontrol";
    $row[8] = "attr rc_iconprefix black_btn_";
    return @row;
}

1;

=pod
=item device
=item summary control for ONKYO AV receivers via network or serial connection
=item summary_DE Steuerung von ONKYO AV Receiver per Netzwerk oder seriell
=begin html

    <p>
      <a name="ONKYO_AVR" id="ONKYO_AVR"></a>
    </p>
    <h3>
      ONKYO_AVR
    </h3>
    <ul>
      <a name="ONKYO_AVRdefine" id="ONKYO_AVRdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; ONKYO_AVR &lt;ip-address-or-hostname[:PORT]&gt; [&lt;protocol-version&gt;]</code><br>
        <code>define &lt;name&gt; ONKYO_AVR &lt;devicename[@baudrate]&gt; [&lt;protocol-version&gt;]</code><br>
        <br>
        This module controls ONKYO A/V receivers in real-time via network connection.<br>
        Some newer Pioneer A/V models seem to run ONKYO's ISCP protocol as well and therefore should be fully supported by this module.<br>
        Use <a href="#ONKYO_AVR_ZONE">ONKYO_AVR_ZONE</a> to control slave zones.<br>
        <br>
        Instead of IP address or hostname you may set a serial connection format for direct connectivity.<br>
        <br>
        <br>
        Example:<br>
        <ul>
          <code>
          define avr ONKYO_AVR 192.168.0.10<br>
          <br>
          # With explicit port<br>
          define avr ONKYO_AVR 192.168.0.10:60128<br>
          <br>
          # With explicit protocol version 2013 and later<br>
          define avr ONKYO_AVR 192.168.0.10 2013<br>
          <br>
          # With protocol version prior 2013<br>
          define avr ONKYO_AVR 192.168.0.10 pre2013
          <br>
          # With protocol version prior 2013 and serial connection<br>
          define avr ONKYO_AVR /dev/ttyUSB1@9600 pre2013
          </code>
        </ul>
      </ul><br>
      <br>

      <a name="ONKYO_AVRset" id="ONKYO_AVRset"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <ul>
          <li>
            <b>channel</b> &nbsp;&nbsp;-&nbsp;&nbsp; set active network service (e.g. Spotify)
          </li>
          <li>
            <b>currentTrackPosition</b> &nbsp;&nbsp;-&nbsp;&nbsp; seek to specific time for current track
          </li>
          <li>
            <b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between inputs
          </li>
          <li>
            <b>inputDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches one input down
          </li>
          <li>
            <b>inputUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches one input up
          </li>
          <li>
            <b>mute</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute
          </li>
          <li>
            <b>muteT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle mute state
          </li>
          <li>
            <b>next</b> &nbsp;&nbsp;-&nbsp;&nbsp; skip track
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode
          </li>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device
          </li>
          <li>
            <b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pause current playback
          </li>
          <li>
            <b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; start playback
          </li>
          <li>
            <b>power</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; set power mode
          </li>
          <li>
            <b>preset</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between presets
          </li>
          <li>
            <b>presetDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches one preset down
          </li>
          <li>
            <b>presetUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches one preset up
          </li>
          <li>
            <b>previous</b> &nbsp;&nbsp;-&nbsp;&nbsp; back to previous track
          </li>
          <li>
            <b>remoteControl</b> Send specific remoteControl command to device
          </li>
          <li>
            <b>repeat</b> off,all,all-folder,one &nbsp;&nbsp;-&nbsp;&nbsp; set repeat setting
          </li>
          <li>
            <b>repeatT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle repeat state
          </li>
          <li>
            <b>shuffle</b> off,on,on-album,on-folder &nbsp;&nbsp;-&nbsp;&nbsp; set shuffle setting
          </li>
          <li>
            <b>shuffleT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle shuffle state
          </li>
          <li>
            <b>sleep</b> 1..90,off &nbsp;&nbsp;-&nbsp;&nbsp; sets auto-turnoff after X minutes
          </li>
          <li>
            <b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stop current playback
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off
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
        </ul>
        <ul>
        <br>
        Other set commands may appear dynamically based on previously used "get avr remoteControl"-commands and resulting readings.<br>
        See "get avr remoteControl &lt;Set-name&gt; help" to get more information about possible readings and set values.
        </ul>
      </ul><br>
      <br>

      <a name="ONKYO_AVRget" id="ONKYO_AVRget"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <br>
        <ul>
          <li>
            <b>createZone</b> &nbsp;&nbsp;-&nbsp;&nbsp; creates a separate <a href="#ONKYO_AVR_ZONE">ONKYO_AVR_ZONE</a> device for available zones of the device
          </li>
          <li>
            <b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; sends advanced remote control commands based on current zone; you may use "get avr remoteControl &lt;Get-command&gt; help" to see details about possible values and resulting readings. In Case the device does not support the command, just nothing happens as normally the device does not send any response. In case the command is temporarily not available you may see according feedback from the log file using attribute verbose=4.
          </li>
          <li>
            <b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; clears cached settings and re-reads device XML configurations
          </li>
        </ul>
      </ul><br>
      <br>

      <a name="ONKYO_AVRattr" id="ONKYO_AVRattr"></a> <b>Attributes</b>
      <ul>
        <ul>
          <li>
            <b>connectionCheck</b> &nbsp;&nbsp;1..120,off&nbsp;&nbsp; Pings the device every X seconds to verify connection status. Defaults to 60 seconds.
          </li>
          <li>
            <b>inputs</b> &nbsp;&nbsp;-&nbsp;&nbsp; List of inputs, auto-generated after first connection to the device. Inputs may be deleted or re-ordered as required. To rename an input, one needs to put a comma behind the current name and enter the new name.
          </li>
          <li>
            <b>model</b> &nbsp;&nbsp;-&nbsp;&nbsp; Contains the model name of the device. Cannot not be changed manually as it is going to be overwritten be the module.
          </li>
          <li>
            <b>volumeSteps</b> &nbsp;&nbsp;-&nbsp;&nbsp; When using set commands volumeUp or volumeDown, the volume will be increased or decreased by these steps. Defaults to 1.
          </li>
          <li>
            <b>volumeMax</b> &nbsp;&nbsp;1...100&nbsp;&nbsp; When set, any volume higher than this is going to be replaced by this value.
          </li>
          <li>
            <b>wakeupCmd</b> &nbsp;&nbsp;-&nbsp;&nbsp; In case the device is unreachable and one is sending set command "on", this FHEM command will be executed before the actual "on" command is sent. E.g. may be used to turn on a switch before the device becomes available via network.
          </li>
        </ul>
      </ul><br>
      <br>

      <b>Generated Readings/Events:</b><br>
      <ul>
        <li>
          <b>audin_*</b> - Shows technical details about current audio input
        </li>
        <li>
          <b>brand</b> - Shows brand name of the device manufacturer
        </li>
        <li>
          <b>channel</b> - Shows current network service name when (e.g. streaming services like Spotify); part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentAlbum</b> - Shows current Album information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentArtist</b> - Shows current Artist information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentMedia</b> - currently no in use
        </li>
        <li>
          <b>currentTitle</b> - Shows current Title information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentTrack*</b> - Shows current track timer information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>deviceid</b> - Shows device name as set in device settings
        </li>
        <li>
          <b>deviceyear</b> - Shows model device year
        </li>
        <li>
          <b>firmwareversion</b> - Shows current firmware version
        </li>
        <li>
          <b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>mute</b> - Reports the mute status of the device (can be "on" or "off")
        </li>
        <li>
          <b>playStatus</b> - Shows current network service playback status; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>power</b> - Reports the power status of the device (can be "on" or "off")
        </li>
        <li>
          <b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is not possible.
        </li>
        <li>
          <b>repeat</b> - Shows current network service repeat status; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>screen*</b> - Experimental: Gives some information about text that is being shown via on-screen menu
        </li>
        <li>
          <b>shuffle</b> - Shows current network service shuffle status; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>sleep</b> - Reports current sleep state (can be "off" or shows timer in minutes)
        </li>
        <li>
          <b>state</b> - Reports current network connection status to the device
        </li>
        <li>
          <b>stateAV</b> - Zone status from user perspective combining readings presence, power, mute and playStatus to a useful overall status.
        </li>
        <li>
          <b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)
        </li>
        <li>
          <b>vidin_*</b> - Shows technical details about current video input before image processing
        </li>
        <li>
          <b>vidout_*</b> - Shows technical details about current video output after image processing
        </li>
        <li>
          <b>zones</b> - Shows total available zones of device
        </li>
      </ul>
        <br>
        Using remoteControl get-command might result in creating new readings in case the device sends any data.<br>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="ONKYO_AVR" id="ONKYO_AVR"></a>
    </p>
    <h3>
      ONKYO_AVR
    </h3>
    <ul>
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </ul>
    <ul>
      <a href='http://fhem.de/commandref.html#ONKYO_AVR'>ONKYO_AVR</a>
    </ul>

=end html_DE

=cut

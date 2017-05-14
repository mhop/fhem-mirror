###############################################################################
# $Id$
package main;

use strict;
use warnings;
use Data::Dumper;
use Symbol qw<qualify_to_ref>;

# initialize ##################################################################
sub ONKYO_AVR_ZONE_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "ONKYO_AVR_ZONE_Initialize: Entering";

    require "$attr{global}{modpath}/FHEM/ONKYOdb.pm";

    $hash->{DefFn}   = "ONKYO_AVR_ZONE_Define";
    $hash->{UndefFn} = "ONKYO_AVR_ZONE_Undefine";
    $hash->{SetFn}   = "ONKYO_AVR_ZONE_Set";
    $hash->{GetFn}   = "ONKYO_AVR_ZONE_Get";
    $hash->{ParseFn} = "ONKYO_AVR_ZONE_Parse";

    $hash->{Match} = ".+";

    $hash->{AttrList} =
        "IODev disable:0,1 disabledForIntervals do_not_notify:1,0 "
      . "volumeSteps:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 inputs wakeupCmd:textField "
      . $readingFnAttributes;

    $data{RC_layout}{ONKYO_AVR_ZONE_SVG} = "ONKYO_AVR_ZONE_RClayout_SVG";
    $data{RC_layout}{ONKYO_AVR_ZONE}     = "ONKYO_AVR_ZONE_RClayout";
    $data{RC_makenotify}{ONKYO_AVR_ZONE} = "ONKYO_AVR_ZONE_RCmakenotify";

    # 98_powerMap.pm support
    $hash->{powerMap} = {
        rname_E => 'energy',
        rname_P => 'consumption',
        map     => {
            stateAV => {
                off   => 0,
                muted => 10,
                '*'   => 20,
            },
        },
    };

    $hash->{parseParams} = 1;
}

# regular Fn ##################################################################
sub ONKYO_AVR_ZONE_Define($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5,
      "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Define()";

    if ( int(@$a) < 2 ) {
        my $msg = "Wrong syntax: define <name> ONKYO_AVR_ZONE [<zone>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    AssignIoPort($hash);

    my $IOhash = $hash->{IODev};
    my $IOname = $IOhash->{NAME};
    my $zone;

    if ( !defined( @$a[2] ) ) {
        $zone = "2";
    }
    elsif ( @$a[2] =~ /^[2-4]$/ ) {
        $zone = @$a[2];
    }
    else {
        return @$a[2] . " is not a valid Zone number";
    }

    if ( defined( $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone} ) ) {
        return "Zone already defined in "
          . $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone}{NAME};
    }
    elsif ( !defined($IOhash) ) {
        return "No matching I/O device found, "
          . "please define a ONKYO_AVR device first";
    }
    elsif ( !defined( $IOhash->{TYPE} ) || !defined( $IOhash->{NAME} ) ) {
        return "IODev does not seem to be existing";
    }
    elsif ( $IOhash->{TYPE} ne "ONKYO_AVR" ) {
        return "IODev is not of type ONKYO_AVR";
    }
    else {
        $hash->{ZONE} = $zone;
    }

    $hash->{INPUT} = "";
    $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone} = $hash;

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        fhem 'attr ' . $name . ' stateFormat stateAV';
        fhem 'attr ' . $name
          . ' cmdIcon muteT:rc_MUTE previous:rc_PREVIOUS next:rc_NEXT play:rc_PLAY pause:rc_PAUSE stop:rc_STOP shuffleT:rc_SHUFFLE repeatT:rc_REPEAT';
        fhem 'attr ' . $name . ' webCmd volume:muteT:input:previous:next';
        fhem 'attr ' . $name
          . ' devStateIcon on:rc_GREEN@green:off off:rc_STOP:on absent:rc_RED playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play muted:rc_MUTE@green:muteT fast-rewind:rc_REW@green:play fast-forward:rc_FF@green:play interrupted:rc_PAUSE@yellow:play';
        fhem 'attr ' . $name . ' inputs ' . AttrVal( $IOname, "inputs", "" )
          if ( AttrVal( $IOname, "inputs", "" ) ne "" );
        fhem 'attr ' . $name . ' room ' . AttrVal( $IOname, "room", "" )
          if ( AttrVal( $IOname, "room", "" ) ne "" );
        fhem 'attr ' . $name . ' group ' . AttrVal( $IOname, "group", "" )
          if ( AttrVal( $IOname, "group", "" ) ne "" );
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
                    $hash->{helper}{receiver}{input_aliases}{ $input_names[0] }
                      = $input_names[1];
                    $hash->{helper}{receiver}{input_names}{ $input_names[1] } =
                      $input_names[0];
                }
            }
        }
    }

    ONKYO_AVR_ZONE_SendCommand( $hash, "power",  "query" );
    ONKYO_AVR_ZONE_SendCommand( $hash, "input",  "query" );
    ONKYO_AVR_ZONE_SendCommand( $hash, "mute",   "query" );
    ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "query" );

    return undef;
}

sub ONKYO_AVR_ZONE_Undefine($$) {
    my ( $hash, $name ) = @_;
    my $zone   = $hash->{ZONE};
    my $IOhash = $hash->{IODev};
    my $IOname = $IOhash->{NAME};

    Log3 $name, 5,
      "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Undefine()";

    delete $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone}
      if ( defined( $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone} ) );

    # Disconnect from device
    DevIo_CloseDev($hash);

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return undef;
}

sub ONKYO_AVR_ZONE_Set($$$) {
    my ( $hash, $a, $h ) = @_;
    my $IOhash   = $hash->{IODev};
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

    Log3 $name, 5, "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Set()";

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
    elsif (defined( $IOhash->{helper}{receiver} )
        && ref( $IOhash->{helper}{receiver} ) eq "HASH"
        && defined( $IOhash->{helper}{receiver}{device}{selectorlist}{count} )
        && $IOhash->{helper}{receiver}{device}{selectorlist}{count} > 0 )
    {

        foreach my $input (
            @{ $IOhash->{helper}{receiver}{device}{selectorlist}{selector} } )
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
        && defined( $IOhash->{helper}{receiver}{device}{netservicelist}{count} )
        && $IOhash->{helper}{receiver}{device}{netservicelist}{count} > 0 )
    {

        foreach my $id (
            sort keys
            %{ $IOhash->{helper}{receiver}{device}{netservicelist}{netservice} }
          )
        {
            if (
                defined(
                    $IOhash->{helper}{receiver}{device}{netservicelist}
                      {netservice}{$id}{value}
                )
                && $IOhash->{helper}{receiver}{device}{netservicelist}
                {netservice}{$id}{value} eq "1"
              )
            {
                $channels_txt .=
                  trim( $IOhash->{helper}{receiver}{device}{netservicelist}
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

            # balance
            elsif ( $reading eq "balance" ) {
                $implicit_txt .= " $reading:slider,-10,1,10";
            }
        }
    }

    my $preset_txt = "";
    if ( defined( $IOhash->{helper}{receiver}{preset} ) ) {

        foreach my $id (
            sort
            keys %{ $IOhash->{helper}{receiver}{preset} }
          )
        {
            my $presetName =
              $IOhash->{helper}{receiver}{preset}{$id};
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

    if ( ReadingsVal( $name, "currentTrackPosition", "--:--" ) ne "--:--" ) {
        $usage .= " currentTrackPosition";
    }

    my $cmd = '';

    return "Device is offline and cannot be controlled at that stage."
      if ( $presence eq "absent" && lc( @$a[1] ) ne "on" );

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
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
                my $ret = fhem "sleep 5;set $name channel " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( $hash->{INPUT} ne "2B" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "2B" );
                my $ret = fhem "sleep 1;set $name channel " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( ReadingsVal( $name, "channel", "" ) ne @$a[2]
                || ( defined( @$a[3] ) && defined( @$a[4] ) ) )
            {

                my $servicename = "";
                my $channelname = @$a[2];

                if (
                       defined( $IOhash->{helper}{receiver} )
                    && ref( $IOhash->{helper}{receiver} ) eq "HASH"
                    && defined(
                        $IOhash->{helper}{receiver}{device}{netservicelist}
                          {count}
                    )
                    && $IOhash->{helper}{receiver}{device}{netservicelist}
                    {count} > 0
                  )
                {

                    $channelname =~ s/_/ /g;

                    foreach my $id (
                        sort keys %{
                            $IOhash->{helper}{receiver}{device}{netservicelist}
                              {netservice}
                        }
                      )
                    {
                        if (
                            defined(
                                $IOhash->{helper}{receiver}{device}
                                  {netservicelist}{netservice}{$id}{value}
                            )
                            && $IOhash->{helper}{receiver}{device}
                            {netservicelist}{netservice}{$id}{value} eq "1"
                            && $IOhash->{helper}{receiver}{device}
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

                Log3 $name, 3,
                  "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

                $servicename = uc($channelname)
                  if ( $servicename eq "" );

                $servicename .= "0"          if ( !defined( @$a[3] ) );
                $servicename .= "1" . @$a[3] if ( defined( @$a[3] ) );
                $servicename .= @$a[4]       if ( defined( @$a[4] ) );
                Debug "net-service $servicename";
                $return =
                  ONKYO_AVR_SendCommand( $IOhash, "net-service", $servicename );
            }
        }
    }

    # channelDown
    elsif ( lc( @$a[1] ) eq "channeldown" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name channelDown";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "2B" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "2B" );
            my $ret = fhem "sleep 1;set $name channelDown";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "chdn" );
        }
    }

    # channelUp
    elsif ( lc( @$a[1] ) eq "channelup" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name channelUp";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "2B" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "2B" );
            my $ret = fhem "sleep 1;set $name channelUp";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "chup" );
        }
    }

    # currentTrackPosition
    elsif ( lc( @$a[1] ) eq "currenttrackposition" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

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
                  ONKYO_AVR_SendCommand( $IOhash, "net-usb-time-seek", @$a[2] );
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
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
                my $ret = fhem "sleep 5;set $name " . @$a[1] . " " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( $hash->{INPUT} ne "2B" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "2B" );
                my $ret = fhem "sleep 5;set $name " . @$a[1] . " " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( @$a[2] =~ /^\d*$/ ) {
                Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];
                $return = ONKYO_AVR_ZONE_SendCommand(
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
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
                my $ret = fhem "sleep 5;set $name preset " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( $hash->{INPUT} ne "24" && $hash->{INPUT} ne "25" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "24" );
                my $ret = fhem "sleep 1;set $name preset " . @$a[2];
                $return .= $ret if ($ret);
            }
            elsif ( lc( @$a[2] ) eq "up" ) {
                Log3 $name, 3,
                  "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, lc( @$a[1] ), "UP" );
            }
            elsif ( lc( @$a[2] ) eq "down" ) {
                Log3 $name, 3,
                  "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, lc( @$a[1] ), "DOWN" );
            }
            elsif ( @$a[2] =~ /^\d*$/ ) {
                Log3 $name, 3,
                  "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];
                $return = ONKYO_AVR_ZONE_SendCommand(
                    $hash,
                    lc( @$a[1] ),
                    ONKYO_AVR_dec2hex( @$a[2] )
                );
            }
            elsif ( defined( $IOhash->{helper}{receiver}{preset} ) ) {

                foreach
                  my $id ( sort keys %{ $IOhash->{helper}{receiver}{preset} } )
                {
                    my $presetName =
                      $IOhash->{helper}{receiver}{preset}{$id};
                    next if ( !$presetName || $presetName eq "" );

                    $presetName =~ s/\s/_/g;

                    if ( $presetName eq @$a[2] ) {
                        Log3 $name, 3,
                          "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

                        $return =
                          ONKYO_AVR_ZONE_SendCommand( $hash, lc( @$a[1] ),
                            uc($id) );

                        last;
                    }
                }
            }
        }
    }

    # presetDown
    elsif ( lc( @$a[1] ) eq "presetdown" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name presetDown";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "24" && $hash->{INPUT} ne "25" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "24" );
            my $ret = fhem "sleep 1;set $name presetDown";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "preset", "down" );
        }
    }

    # presetUp
    elsif ( lc( @$a[1] ) eq "presetup" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 5;set $name presetUp";
            $return .= $ret if ($ret);
        }
        elsif ( $hash->{INPUT} ne "24" && $hash->{INPUT} ne "25" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "24" );
            my $ret = fhem "sleep 1;set $name presetUp";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "preset", "up" );
        }
    }

    # tone-*
    elsif ( lc( @$a[1] ) =~ /^(tone.*)-(bass|treble)$/ ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

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
                  ONKYO_AVR_ZONE_SendCommand( $hash, lc($1), $setVal . "UP" );
            }
            elsif ( lc( @$a[2] ) eq "down" ) {
                my $setVal = "";
                $setVal = "B" if ( $2 eq "bass" );
                $setVal = "T" if ( $2 eq "treble" );
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, lc($1), $setVal . "DOWN" );
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
                  ONKYO_AVR_ZONE_SendCommand( $hash, lc($1),
                    $setVal . $setVal2 );
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
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " (wakeup)";
            my $wakeupCmd = AttrVal( $name, "wakeupCmd", "" );

            if ( $wakeupCmd ne "" ) {
                $wakeupCmd =~ s/\$DEVICE/$name/g;

                if ( $wakeupCmd =~ s/^[ \t]*\{|\}[ \t]*$//g ) {
                    Log3 $name, 4,
"ONKYO_AVR_ZONE executing wake-up command (Perl): $wakeupCmd";
                    $return = eval $wakeupCmd;
                }
                else {
                    Log3 $name, 4,
"ONKYO_AVR_ZONE executing wake-up command (fhem): $wakeupCmd";
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
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );

            # don't wait for receiver to confirm power on
            #

            readingsBeginUpdate($hash);

            # power
            readingsBulkUpdate( $hash, "power", "on" )
              if ( ReadingsVal( $name, "power", "-" ) ne "on" );

            # stateAV
            my $stateAV = ONKYO_AVR_ZONE_GetStateAV($hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            readingsEndUpdate( $hash, 1 );
        }
    }

    # off
    elsif ( lc( @$a[1] ) eq "off" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
        $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "off" );
    }

    # remoteControl
    elsif ( lc( @$a[1] ) eq "remotecontrol" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given, choose one of minutes off";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

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
                  ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z",
                    lc( @$a[2] ) );
            }
            elsif ( lc( @$a[2] ) eq "prev" ) {
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "trdown" );
            }
            elsif ( lc( @$a[2] ) eq "next" ) {
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "trup" );
            }
            elsif ( lc( @$a[2] ) eq "shuffle" ) {
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "random" );
            }
            elsif ( lc( @$a[2] ) eq "menu" ) {
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "men" );
            }
            else {
                $return = "Unsupported remoteControl command: " . @$a[2];
            }

        }
    }

    # play
    elsif ( lc( @$a[1] ) eq "play" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "play" );
        }
    }

    # pause
    elsif ( lc( @$a[1] ) eq "pause" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "pause" );
        }
    }

    # stop
    elsif ( lc( @$a[1] ) eq "stop" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "stop" );
        }
    }

    # shuffle
    elsif ( lc( @$a[1] ) eq "shuffle" || lc( @$a[1] ) eq "shufflet" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return =
              ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "random" );
        }
    }

    # repeat
    elsif ( lc( @$a[1] ) eq "repeat" || lc( @$a[1] ) eq "repeatt" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return =
              ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "repeat" );
        }
    }

    # previous
    elsif ( lc( @$a[1] ) eq "previous" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return =
              ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "trdown" );
        }
    }

    # next
    elsif ( lc( @$a[1] ) eq "next" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "trup" );
        }
    }

    # mute
    elsif ( lc( @$a[1] ) eq "mute" || lc( @$a[1] ) eq "mutet" ) {
        if ( defined( @$a[2] ) ) {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
        }

        if ( $state eq "on" ) {
            if ( !defined( @$a[2] ) || @$a[2] eq "toggle" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "mute", "toggle" );
            }
            elsif ( lc( @$a[2] ) eq "off" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "mute", "off" );
            }
            elsif ( lc( @$a[2] ) eq "on" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "mute", "on" );
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
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

            if ( $state eq "on" ) {
                if ( @$a[2] =~ m/^\d+$/ && @$a[2] >= 0 && @$a[2] <= 100 ) {
                    $return =
                      ONKYO_AVR_ZONE_SendCommand( $hash, "volume",
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
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
        my $volumeSteps = AttrVal( $name, "volumeSteps", "1" );
        my $volume = ReadingsVal( $name, "volume", "0" );

        if ( $state eq "on" ) {
            if ( lc( @$a[1] ) eq "volumeup" ) {
                if ( $volumeSteps > 1 ) {
                    $return =
                      ONKYO_AVR_ZONE_SendCommand( $hash, "volume",
                        ONKYO_AVR_dec2hex( $volume + $volumeSteps ) );
                }
                else {
                    $return =
                      ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "level-up" );
                }
            }
            else {
                if ( $volumeSteps > 1 ) {
                    $return =
                      ONKYO_AVR_ZONE_SendCommand( $hash, "volume",
                        ONKYO_AVR_dec2hex( $volume - $volumeSteps ) );
                }
                else {
                    $return =
                      ONKYO_AVR_ZONE_SendCommand( $hash, "volume",
                        "level-down" );
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
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
                my $ret = fhem "sleep 2;set $name input " . @$a[2];
                $return .= $ret if ($ret);
            }
            else {
                Log3 $name, 3,
                  "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", @$a[2] );
            }
        }
    }

    # inputUp
    elsif ( lc( @$a[1] ) eq "inputup" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 2;set $name inputUp";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "up" );
        }
    }

    # inputDown
    elsif ( lc( @$a[1] ) eq "inputdown" ) {
        if ( $state eq "off" ) {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
            my $ret = fhem "sleep 2;set $name inputDown";
            $return .= $ret if ($ret);
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", "down" );
        }
    }

    # implicit commands through available readings
    elsif ( grep $_ eq lc( @$a[1] ), @implicit_cmds ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, @$a[1], @$a[2] );
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

sub ONKYO_AVR_ZONE_Get($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name             = $hash->{NAME};
    my $zone             = $hash->{ZONE};
    my $IOhash           = $hash->{IODev};
    my $IOname           = $IOhash->{NAME};
    my $state            = ReadingsVal( $name, "power", "off" );
    my $presence         = ReadingsVal( $name, "presence", "absent" );
    my $commands         = ONKYOdb::ONKYO_GetRemotecontrolCommand($zone);
    my $commands_details = ONKYOdb::ONKYO_GetRemotecontrolCommandDetails($zone);
    my $return;

    Log3 $name, 5, "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Get()";

    return "Argument is missing" if ( int(@$a) < 1 );

    # readings
    return $hash->{READINGS}{ @$a[1] }{VAL}
      if ( defined( $hash->{READINGS}{ @$a[1] } ) );

    return "Device is offline and cannot be controlled at that stage."
      if ( $presence eq "absent" );

    # statusRequest
    if ( lc( @$a[1] ) eq "statusrequest" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE get $name " . @$a[1];

        ONKYO_AVR_ZONE_SendCommand( $hash, "power",  "query" );
        ONKYO_AVR_ZONE_SendCommand( $hash, "input",  "query" );
        ONKYO_AVR_ZONE_SendCommand( $hash, "mute",   "query" );
        ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "query" );
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
                    "ONKYO_AVR_ZONE get $name "
                  . @$a[1] . " "
                  . @$a[2] . " "
                  . @$a[3]
                  if ( !@$a[4] || @$a[4] ne "quiet" );

                ONKYO_AVR_ZONE_SendCommand( $hash, @$a[2], @$a[3] );
                $return = "Sent command: " . @$a[2] . " " . @$a[3]
                  if ( !@$a[4] || @$a[4] ne "quiet" );
            }
        }
    }

    else {
        $return =
          "Unknown argument " . @$a[1] . ", choose one of statusRequest:noArg";

        # remoteControl
        $return .= " remoteControl:";
        foreach my $command ( sort keys %{$commands} ) {
            $return .= "," . $command;
        }
    }

    return $return;
}

sub ONKYO_AVR_ZONE_Parse($$) {
    my ( $IOhash, $msg ) = @_;
    my @matches;
    my $IOname = $IOhash->{NAME};
    my $zone = $msg->{zone} || "";

    delete $msg->{zone} if ( defined( $msg->{zone} ) );

    Log3 $IOname, 5,
      "ONKYO_AVR $IOname: called function ONKYO_AVR_ZONE_Parse()";

    foreach my $d ( keys %defs ) {
        my $hash  = $defs{$d};
        my $name  = $hash->{NAME};
        my $state = ReadingsVal( $name, "power", "off" );

        if (   $hash->{TYPE} eq "ONKYO_AVR_ZONE"
            && $hash->{IODev} eq $IOhash
            && ( $zone eq "" || $hash->{ZONE} eq $zone ) )
        {
            push @matches, $d;

            # Update readings
            readingsBeginUpdate($hash);

            foreach my $cmd ( keys %{$msg} ) {
                my $value = $msg->{$cmd};

                $hash->{INPUT}   = $value and next if ( $cmd eq "INPUT_RAW" );
                $hash->{CHANNEL} = $value and next if ( $cmd eq "CHANNEL_RAW" );

                Log3 $name, 4, "ONKYO_AVR_ZONE $name: rcv $cmd = $value";

                # presence
                if ( $cmd eq "presence" && $value eq "present" ) {
                    ONKYO_AVR_ZONE_SendCommand( $hash, "power",  "query" );
                    ONKYO_AVR_ZONE_SendCommand( $hash, "input",  "query" );
                    ONKYO_AVR_ZONE_SendCommand( $hash, "mute",   "query" );
                    ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "query" );
                }

                # input
                elsif ( $cmd eq "input" ) {

                    # Input alias handling
                    if (
                        defined(
                            $hash->{helper}{receiver}{input_aliases}{$value}
                        )
                      )
                    {
                        Log3 $name, 4,
                            "ONKYO_AVR_AVR $name: Input aliasing '$value' to '"
                          . $hash->{helper}{receiver}{input_aliases}{$value}
                          . "'";
                        $value =
                          $hash->{helper}{receiver}{input_aliases}{$value};
                    }

                }

                # power
                elsif ( $cmd eq "power" ) {
                    readingsBulkUpdate( $hash, "presence", "present" )
                      if ( ReadingsVal( $name, "presence", "-" ) ne "present" );
                }

                # balance
                elsif ( $cmd eq "balance" ) {
                    my $prefix = "";
                    $prefix = "-" if ( $value =~ /^\-.*/ );
                    $value = substr( $value, 1 ) if ( $value =~ /^[\+|\-].*/ );

                    $value = $prefix . ONKYO_AVR_hex2dec($value);
                }

                # preset
                elsif ( $cmd eq "preset" ) {

                    if ( defined( $IOhash->{helper}{receiver}{preset} ) ) {

                        foreach my $id (
                            sort keys %{ $IOhash->{helper}{receiver}{preset} } )
                        {
                            my $presetName =
                              $IOhash->{helper}{receiver}{preset}{$id};
                            next if ( !$presetName || $presetName eq "" );

                            $presetName =~ s/\s/_/g;

                            if ( $id eq ONKYO_AVR_dec2hex($value) ) {
                                $value = $presetName;
                                last;
                            }
                        }
                    }

                    $value = "" if ( $value eq "0" );
                }

                # tone
                if ( $cmd =~ /^tone/ ) {
                    if ( $value =~ /^B(..)T(..)$/ ) {
                        my $bass         = $1;
                        my $treble       = $2;
                        my $bassName     = $cmd . "-bass";
                        my $trebleName   = $cmd . "-treble";
                        my $prefixBass   = "";
                        my $prefixTreble = "";

                        # tone-bass
                        $prefixBass = "-" if ( $bass =~ /^\-.*/ );
                        $bass = substr( $bass, 1 ) if ( $bass =~ /^[\+|\-].*/ );
                        $bass = $prefixBass . ONKYO_AVR_hex2dec($bass);
                        readingsBulkUpdate( $hash, $bassName, $bass )
                          if ( ReadingsVal( $name, $bassName, "-" ) ne $bass );

                        # tone-treble
                        $prefixTreble = "-" if ( $treble =~ /^\-.*/ );
                        $treble = substr( $treble, 1 )
                          if ( $treble =~ /^[\+|\-].*/ );
                        $treble = $prefixTreble . ONKYO_AVR_hex2dec($treble);
                        readingsBulkUpdate( $hash, $trebleName, $treble )
                          if (
                            ReadingsVal( $name, $trebleName, "-" ) ne $treble );
                    }
                }

                # all other commands
                else {
                    readingsBulkUpdate( $hash, $cmd, $value )
                      if ( ReadingsVal( $name, $cmd, "-" ) ne $value
                        || $cmd =~ /^currentAlbumArt.*/ );
                }
            }

            # stateAV
            my $stateAV = ONKYO_AVR_ZONE_GetStateAV($hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            readingsEndUpdate( $hash, 1 );
            last;
        }
    }
    return @matches if (@matches);
    return "UNDEFINED ONKYO_AVR_ZONE";
}

# module Fn ####################################################################
sub ONKYO_AVR_ZONE_SendCommand($$$) {
    my ( $hash, $cmd, $value ) = @_;
    my $IOhash = $hash->{IODev};
    my $name   = $hash->{NAME};
    my $zone   = $hash->{ZONE};

    Log3 $name, 5,
      "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_SendCommand()";

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
                $IOhash->{helper}{receiver}{device}{selectorlist}{selector}
            )
            && ref(
                $IOhash->{helper}{receiver}{device}{selectorlist}{selector} )
            eq "ARRAY"
          )
        {

            foreach my $input (
                @{ $IOhash->{helper}{receiver}{device}{selectorlist}{selector} }
              )
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
"ONKYO_AVR_ZONE $name: command '$cmd$value' is an unregistered command within zone$zone, be careful! Will be handled as raw command";
        $cmd_raw   = $cmd;
        $value_raw = $value;
    }
    elsif ( !defined($value_raw) ) {
        Log3 $name, 4,
"ONKYO_AVR_ZONE $name: $cmd - Warning, value '$value' not found in HASH table, will be sent to receiver 'as is'";
        $value_raw = $value;
    }

    Log3 $name, 4,
      "ONKYO_AVR_ZONE $name: snd $cmd -> $value ($cmd_raw$value_raw)";

    if ( $cmd_raw ne "" && $value_raw ne "" ) {
        IOWrite( $hash, $cmd_raw . $value_raw );
    }

    return;
}

sub ONKYO_AVR_ZONE_GetStateAV($) {
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

sub ONKYO_AVR_ZONE_RCmakenotify($$) {
    my ( $name, $ndev ) = @_;
    my $nname = "notify_$name";

    fhem( "define $nname notify $name set $ndev remoteControl " . '$EVENT', 1 );
    Log3 undef, 2, "[remotecontrol:ONKYO_AVR_ZONE] Notify created: $nname";
    return "Notify created by ONKYO_AVR_ZONE: $nname";
}

sub ONKYO_AVR_ZONE_RClayout_SVG() {
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

sub ONKYO_AVR_ZONE_RClayout() {
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
=item summary supplement module for ONKYO_AVR representing zones
=item summary_DE erg&auml;nzendes Modul f&uuml;r ONKYO_AVR, um Zonen zu repr&auml;sentieren
=begin html

    <p>
      <a name="ONKYO_AVR_ZONE" id="ONKYO_AVR_ZONE"></a>
    </p>
    <h3>
      ONKYO_AVR_ZONE
    </h3>
    <ul>
      <a name="ONKYO_AVR_ZONEdefine" id="ONKYO_AVR_ZONEdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; ONKYO_AVR_ZONE [&lt;zone-id&gt;]</code><br>
        <br>
        This is a supplement module for <a href="#ONKYO_AVR">ONKYO_AVR</a> representing zones.<br>
        <br>
        Example:<br>
        <ul>
          <code>
          define avr ONKYO_AVR_ZONE<br>
          <br>
          # For zone2<br>
          define avr ONKYO_AVR_ZONE 2<br>
          <br>
          # For zone3<br>
          define avr ONKYO_AVR_ZONE 3<br>
          <br>
          # For zone4<br>
          define avr ONKYO_AVR_ZONE 4
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
        </ul>
      </ul><br>
      <br>

      <a name="ONKYO_AVRattr" id="ONKYO_AVRattr"></a> <b>Attributes</b>
      <ul>
        <ul>
          <li>
            <b>inputs</b> &nbsp;&nbsp;-&nbsp;&nbsp; List of inputs, auto-generated after first connection to the device. Inputs may be deleted or re-ordered as required. To rename an input, one needs to put a comma behind the current name and enter the new name.
          </li>
          <li>
            <b>volumeSteps</b> &nbsp;&nbsp;-&nbsp;&nbsp; When using set commands volumeUp or volumeDown, the volume will be increased or decreased by these steps. Defaults to 1.
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
          <b>shuffle</b> - Shows current network service shuffle status; part of FHEM-4-AV-Devices compatibility
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
      </ul>
        <br>
        Using remoteControl get-command might result in creating new readings in case the device sends any data.<br>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="ONKYO_AVR_ZONE" id="ONKYO_AVR_ZONE"></a>
    </p>
    <h3>
      ONKYO_AVR_ZONE
    </h3>
    <ul>
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </ul>
    <ul>
      <a href='http://fhem.de/commandref.html#ONKYO_AVR_ZONE'>ONKYO_AVR_ZONE</a>
    </ul>

=end html_DE

=cut

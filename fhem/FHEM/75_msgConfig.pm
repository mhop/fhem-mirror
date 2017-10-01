###############################################################################
# $Id$
package main;
use strict;
use warnings;
use Data::Dumper;

# initialize ##################################################################
sub msgConfig_Initialize($) {
    my ($hash) = @_;
    my $TYPE = "msgConfig";

    require "$attr{global}{modpath}/FHEM/msgSchema.pm";

    $hash->{DefFn}    = $TYPE . "_Define";
    $hash->{SetFn}    = $TYPE . "_Set";
    $hash->{GetFn}    = $TYPE . "_Get";
    $hash->{UndefFn}  = $TYPE . "_Undefine";
    $hash->{NotifyFn} = $TYPE . "_Notify";

    # add attributes for configuration
    no warnings 'qw';
    my @attrList = qw(
      msgCmdAudio
      msgCmdAudioShort
      msgCmdAudioShortPrio
      msgCmdLight
      msgCmdLightHigh
      msgCmdLightLow
      msgCmdMail
      msgCmdMailHigh
      msgCmdMailLow
      msgCmdPush
      msgCmdPushHigh
      msgCmdPushLow
      msgCmdScreen
      msgCmdScreenHigh
      msgCmdScreenLow
      msgFwPrioAbsentAudio:-2,-1,0,1,2
      msgFwPrioAbsentLight:-2,-1,0,1,2
      msgFwPrioAbsentScreen:-2,-1,0,1,2
      msgFwPrioEmergencyAudio:-2,-1,0,1,2
      msgFwPrioEmergencyLight:-2,-1,0,1,2
      msgFwPrioEmergencyPush:-2,-1,0,1,2
      msgFwPrioEmergencyScreen:-2,-1,0,1,2
      msgFwPrioGoneAudio:-2,-1,0,1,2
      msgFwPrioGoneLight:-2,-1,0,1,2
      msgFwPrioGoneScreen:-2,-1,0,1,2
      msgLocationDevs
      msgParamsAudio
      msgParamsAudioShort
      msgParamsAudioShortPrio
      msgParamsLight
      msgParamsLightHigh
      msgParamsLightLow
      msgParamsMail
      msgParamsMailHigh
      msgParamsMailLow
      msgParamsPush
      msgParamsPushHigh
      msgParamsPushLow
      msgParamsScreen
      msgParamsScreenHigh
      msgParamsScreenLow
      msgParamsText
      msgParamsTextHigh
      msgParamsTextLow
      msgPriorityAudio:-2,-1,0,1,2
      msgPriorityLight:-2,-1,0,1,2
      msgPriorityMail:-2,-1,0,1,2
      msgPriorityPush:-2,-1,0,1,2
      msgPriorityScreen:-2,-1,0,1,2
      msgPriorityText:-2,-1,0,1,2
      msgRcv:1,0
      msgResidentsDev
      msgSwitcherDev
      msgThPrioHigh:-2,-1,0,1,2
      msgThPrioNormal:-2,-1,0,1,2
      msgThPrioAudioEmergency:-2,-1,0,1,2
      msgThPrioAudioHigh:-2,-1,0,1,2
      msgThPrioTextEmergency:-2,-1,0,1,2
      msgThPrioTextNormal:-2,-1,0,1,2
      msgThPrioGwEmergency:-2,-1,0,1,2
      msgTitleAudio
      msgTitleAudioShort
      msgTitleAudioShortPrio
      msgTitleLight
      msgTitleLightHigh
      msgTitleLightLow
      msgTitleMail
      msgTitleMailHigh
      msgTitleMailLow
      msgTitlePush
      msgTitlePushHigh
      msgTitlePushLow
      msgTitleScreen
      msgTitleScreenHigh
      msgTitleScreenLow
      msgTitleText
      msgTitleTextHigh
      msgTitleTextLow
      msgTitleShrtAudio
      msgTitleShrtAudioShort
      msgTitleShrtAudioShortPrio
      msgTitleShrtLight
      msgTitleShrtLightHigh
      msgTitleShrtLightLow
      msgTitleShrtMail
      msgTitleShrtMailHigh
      msgTitleShrtMailLow
      msgTitleShrtPush
      msgTitleShrtPushHigh
      msgTitleShrtPushLow
      msgTitleShrtScreen
      msgTitleShrtScreenHigh
      msgTitleShrtScreenLow
      msgTitleShrtText
      msgTitleShrtTextHigh
      msgTitleShrtTextLow
    );
    use warnings 'qw';
    $hash->{AttrList} = join( " ", @attrList ) . " " . $readingFnAttributes;

    # add global attributes
    foreach (
        "msgContactAudio",
        "msgContactMail",
        "msgContactPush",
        "msgContactScreen",
        "msgContactLight",
        "msgParams",
        "msgPriority",
        "msgRecipient",
        "msgRecipientAudio",
        "msgRecipientMail",
        "msgRecipientPush",
        "msgRecipientScreen",
        "msgRecipientText",
        "msgRecipientLight",
        "msgTitle",
        "msgTitleShrt",
        "msgType:text,push,mail,screen,light,audio,queue",
      )
    {
        addToAttrList($_);
    }
}

# regular Fn ##################################################################
sub msgConfig_Define($$) {
    my ( $hash, $def ) = @_;
    my $TYPE = $hash->{TYPE};

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> $TYPE"
      if ( int(@a) < 2 );
    my $name = $a[0];

    return "Global configuration device already defined: "
      . $modules{$TYPE}{defptr}{NAME}
      if ( defined( $modules{$TYPE}{defptr} ) );

    # create global unique device definition
    $modules{$TYPE}{defptr} = $hash;

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        my $group   = AttrVal( "global", "group",   "Global" );
        my $room    = AttrVal( "global", "room",    "" );
        my $verbose = AttrVal( "global", "verbose", 3 );

        $attr{$name}{group}   = $group;
        $attr{$name}{verbose} = $verbose;
        $attr{$name}{room}    = $room if ( $room ne "" );
        $attr{$name}{comment} = "FHEM Global Configuration for command 'msg'";
        $attr{$name}{stateFormat} = "fhemMsgState";
        $attr{$name}{msgType}     = "text";

        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "fhemMsgState", "initialized" );
        readingsEndUpdate( $hash, 1 );
    }

    $hash->{NOTIFYDEV} = "TYPE=(Jabber|TelegramBot|yowsup)";

    return undef;
}

sub msgConfig_Undefine($$) {
    my ( $hash, $name ) = @_;
    my $TYPE = $hash->{TYPE};

    # release global unique device definition
    delete $modules{$TYPE}{defptr};

    return undef;
}

sub msgConfig_Set($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $TYPE = $hash->{TYPE};
    shift @a;
    my $what = shift @a;

    Log3 $name, 5, "$TYPE $name: called function $TYPE" . "_Set()";

    my @msgTypes = ( "audio", "light", "mail", "push", "screen", "queue" );

    # cleanReadings
    if ( lc($what) eq "cleanreadings" ) {
        my $device = defined( $a[0] ) ? $a[0] : ".*";

        return fhem( "deletereading $device fhemMsg.*", 1 );
    }

    # addLocation
    elsif ( lc($what) eq "addlocation" ) {
        my $location = join( " ", @a );
        my $group = AttrVal( $name, "group", $TYPE );
        my $room  = AttrVal( $name, "room",  "" );
        my $return = "";

        return "Missing argument 'location'"
          if ( $location eq "" );

        my $device = "msgRoom_" . $location;
        $device =~ s/[\s\t-]+/_/g;

        return "Device $device is already existing but not a dummy device"
          if ( IsDevice($device)
            && GetType($device) ne "dummy" );

        if ( !IsDevice($device) ) {
            $return = fhem( "define $device dummy", 1 );
            $return .= "Device $device was created"
              if ( $return eq "" );
        }
        else {
            $return = "Existing dummy device $device was updated";
        }

        $attr{$device}{group} = $group if ( !defined( $attr{$device}{group} ) );
        $attr{$device}{room} = $room
          if ( !defined( $attr{$device}{room} ) && $room ne "" );
        $attr{$device}{comment} = "Auto-created by $name"
          if ( !defined( $attr{$device}{comment} ) );
        $attr{$device}{userattr} .= " msgLocationName"
          if ( defined( $attr{$device}{userattr} )
            && $attr{$device}{userattr} !~
m/^msgLocationName$|^msgLocationName\s|\smsgLocationName\s|\smsgLocationName$/
          );
        $attr{$device}{userattr} = "msgLocationName"
          if ( !defined( $attr{$device}{userattr} ) );
        $attr{$device}{msgLocationName} = $location;
        fhem("set $device $location");

        $attr{$name}{msgLocationDevs} .= "," . $device
          if ( defined( $attr{$name}{msgLocationDevs} )
            && $attr{$name}{msgLocationDevs} !~
            /^$device\$|^$device,|,$device,|,$device$/ );
        $attr{$name}{msgLocationDevs} = $device
          if ( !defined( $attr{$name}{msgLocationDevs} ) );

        return $return;
    }

    # createSwitcherDev
    elsif ( lc($what) eq "createswitcherdev" ) {
        my $device = AttrVal( $name,   "msgSwitcherDev", "HouseAnn" );
        my $state  = AttrVal( $device, "state",          "???" );
        my $return = "";

        my $lang = "en";
        $lang = $a[0]
          if ( defined( $a[0] ) && $a[0] eq "de" );

        return "Device $device is already existing but not a dummy device"
          if ( IsDevice($device)
            && GetType($device) ne "dummy" );

        if ( !IsDevice($device) ) {
            $return = fhem( "define $device dummy", 1 );
            $return .= "Device $device was created"
              if ( $return eq "" );
        }
        else {
            $return = "Existing dummy device $device was updated";
        }

        if ( $lang eq "de" ) {
            $attr{$device}{alias} = "Durchsagen";
            $attr{$device}{eventMap} =
              "active:aktiv long:lang short:kurz visual:visuell off:aus";
            $attr{$device}{room} = "Haus"
              if ( !defined( $attr{$device}{room} ) );
            $attr{$device}{setList} = "state:lang,kurz,visuell,aus";
        }
        else {
            $attr{$device}{alias} = "Announcements";
            $attr{$device}{room}  = "House"
              if ( !defined( $attr{$device}{room} ) );
            $attr{$device}{setList} = "state:long,short,visual,off";
            delete $attr{$device}{eventMap}
              if ( defined( $attr{$device}{eventMap} ) );
        }
        $attr{$device}{comment} = "Auto-created by $name"
          if ( !defined( $attr{$device}{comment} )
            || $attr{$device}{comment} ne "Auto-created by $name" );
        $attr{$device}{devStateIcon} =
'aktiv:general_an@90EE90 active:general_an@90EE90 lang:general_an@green:off long:general_an@green:off  aus:general_aus@red:long off:general_aus@red:long kurz:general_an@orange:long short:general_an@orange:long visuell:general_an@orange:long visual:general_an@orange:long';
        $attr{$device}{"event-on-change-reading"} = "state"
          if ( !defined( $attr{$device}{"event-on-change-reading"} ) );
        $attr{$device}{group} = "Automation"
          if ( !defined( $attr{$device}{group} ) );
        $attr{$device}{icon}   = "audio_volume_mid";
        $attr{$device}{webCmd} = "state";
        fhem("set $device long") if ( $state eq "???" );

        $return .=
          "\nAttribute msgSwitcherDev at device $name was changed to $device"
          if ( defined( $attr{$name}{msgSwitcherDev} ) );
        $return .= "\nAdded attribute msgSwitcherDev to device $name"
          if ( !defined( $attr{$name}{msgSwitcherDev} ) );
        $attr{$name}{msgSwitcherDev} = $device;

        return $return;
    }

    # createResidentsDev
    elsif ( lc($what) eq "createresidentsdev" ) {
        my $device = AttrVal( $name, "msgResidentsDev", "rgr_Residents" );
        my $return = "";

        my $lang = defined( $a[0] ) ? uc( $a[0] ) : "EN";

        return
"Device $device is already existing but not a RESIDENTS or ROOMMATE device"
          if ( IsDevice($device)
            && !IsDevice( $device, "RESIDENTS|ROOMMATE" ) );

        if ( !IsDevice($device) ) {
            $return = fhem( "define $device RESIDENTS", 1 );
            $return .= "RESIDENTS device $device was created."
              if ( $return eq "" );
        }
        else {
            $return =
              "Existing " . GetType($device) . " device $device was updated.";
        }

        my $txt = fhem("attr $device rgr_lang $lang")
          unless ( $lang eq "EN" );
        $return .= $txt if ($txt);

        $attr{$device}{comment} = "Auto-created by $name"
          if ( !defined( $attr{$device}{comment} )
            || $attr{$device}{comment} ne "Auto-created by $name" );

        $return .=
"\nIf you would like this device to act as an overall presence device for ALL msg commands, please adjust attribute msgResidentsDev at device $name to $device."
          if ( defined( $attr{$name}{msgResidentsDev} )
            && $attr{$name}{msgResidentsDev} ne $device );
        $return .=
"\nNext, set a device's msgResidentsDev attribute to '$device' (think of using 'userattr' to add 'msgResidentsDev' to the list of available attributes). \nIf you would like '$device' to act as an overall presence device for ALL msg commands, sett attribute msgResidentsDev at device $name to $device."
          if ( !defined( $attr{$name}{msgResidentsDev} ) );

        return $return;
    }

    else {
        return
"Unknown argument $what, choose one of cleanReadings addLocation createSwitcherDev:de,en createResidentsDev:de,en";
    }

    return undef;
}

sub msgConfig_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $TYPE = $hash->{TYPE};
    shift @a;
    my $what = shift @a;

    Log3 $name, 5, "$TYPE $name: called function $TYPE" . "_Get()";

    my @msgTypes = ( "audio", "light", "mail", "push", "screen" );

    # routeCmd
    if ( lc($what) eq "routecmd" ) {
        my $return = "";
        my $msgTypesReq =
          defined( $a[0] ) ? lc( $a[0] ) : join( ',', @msgTypes );
        my $devicesReq      = defined( $a[1] ) ? $a[1] : $name;
        my $cmdSchema       = msgSchema::get();
        my $UserDeviceTypes = "";

        foreach my $msgType ( split( /,/, $msgTypesReq ) ) {

            # Check device
            if ( $devicesReq ne "" ) {
                foreach my $device ( split( /,/, $devicesReq ) ) {
                    if ( IsDevice($device) ) {
                        $UserDeviceTypes .= "," . GetType($device)
                          if ( $UserDeviceTypes ne ""
                            && $msgType ne "mail"
                            && $device ne $name );
                        $UserDeviceTypes = GetType($device)
                          if ( $UserDeviceTypes eq ""
                            && $msgType ne "mail"
                            && $device ne $name );
                        $UserDeviceTypes .= ",fhemMsgMail"
                          if ( $UserDeviceTypes ne ""
                            && $msgType eq "mail"
                            && $device ne $name );
                        $UserDeviceTypes = "fhemMsgMail"
                          if ( $UserDeviceTypes eq ""
                            && $msgType eq "mail"
                            && $device ne $name );

                        my $typeUc = ucfirst($msgType);

                        my @priorities;
                        @priorities = ( "Normal", "ShortPrio", "Short" )
                          if ( $msgType eq "audio" );
                        @priorities = ( "Normal", "High", "Low" )
                          if ( $msgType ne "audio" );

                        my $output = 0;
                        foreach my $prio (@priorities) {
                            my $priorityCat = "";
                            $priorityCat = $prio if ( $prio ne "Normal" );

                            my $cmd = MSG_FindAttrVal( $device,
                                "msgCmd$typeUc$priorityCat", $typeUc, "" );

                            next
                              if ( $cmd eq ""
                                && $device eq $name
                                && $output == 0 );
                            $return .=
                              uc($msgType)
                              . ": USER DEFINED COMMANDS WITH PRECEDENCE\n-------------------------------------------------------------------------------\n\n"
                              if ( $output == 0 );
                            $return .=
                              "  $device (DEVICE TYPE: "
                              . GetType($device) . ")\n"
                              if ( $output == 0 );
                            $output = 1 if ( $output == 0 );

                            $return .= "    Priority $prio:\n      $cmd\n"
                              if ( $cmd ne "" );
                            $return .=
                              "    Priority $prio:\n      [DEFAULT COMMAND]\n"
                              if ( $cmd eq "" );
                        }

                        $return .= "\n" if ( $return ne "" );
                    }
                }

                $return .= "\n" if ( $return ne "" );
            }

            # Default commands
            if ( defined( $cmdSchema->{$msgType} ) ) {

                my $deviceTypes = $devicesReq;
                $deviceTypes = join( ',', keys %{ $cmdSchema->{$msgType} } )
                  if ( $deviceTypes eq "" || $devicesReq eq $name );
                $deviceTypes = $UserDeviceTypes
                  if ( $UserDeviceTypes ne "" );

                my $outout = 0;
                foreach my $deviceType ( split( /,/, $deviceTypes ) ) {

                    if ( defined( $cmdSchema->{$msgType}{$deviceType} ) ) {
                        $return .=
                          uc($msgType)
                          . ": DEFAULT COMMANDS\n-------------------------------------------------------------------------------\n\n"
                          if ( $outout == 0 );
                        $outout = 1;
                        $return .= "  $deviceType\n";

                        my @priorities;
                        @priorities = ( "Normal", "ShortPrio", "Short" )
                          if ( $msgType eq "audio" );
                        @priorities = ( "Normal", "High", "Low" )
                          if ( $msgType ne "audio" );

                        foreach my $prio (@priorities) {
                            $return .=
                                "    Priority $prio:\n      "
                              . $cmdSchema->{$msgType}{$deviceType}{$prio}
                              . "\n";

                            if (
                                defined(
                                    $cmdSchema->{$msgType}{$deviceType}
                                      {defaultValues}{$prio}
                                )
                              )
                            {
                                $return .= "      Default Values:\n";

                                foreach my $key (
                                    keys %{
                                        $cmdSchema->{$msgType}{$deviceType}
                                          {defaultValues}{$prio}
                                    }
                                  )
                                {
                                    if ( $cmdSchema->{$msgType}{$deviceType}
                                        {defaultValues}{$prio}{$key} ne "" )
                                    {
                                        $return .=
                                          "        $key = "
                                          . $cmdSchema->{$msgType}{$deviceType}
                                          {defaultValues}{$prio}{$key} . "\n";
                                    }
                                    else {
                                        $return .= "        $key = [EMPTY]\n";
                                    }
                                }

                            }
                        }

                        $return .= "\n" if ( $return ne "" );
                    }

                }
            }
            else {
                $return .= "Unknown messaging type '$msgType'\n"
                  if ( $msgType ne "text" );
                $return .=
"Messaging type 'text' does not have dedicated routing commands. This is a wrapper type to dynamically distinguish between push and mail.\n"
                  if ( $msgType eq "text" );
            }

            $return .= "\n" if ( $return ne "" );
        }

        $return =
"Non-existing device or unknown module messaging schema definition: $devicesReq"
          if ( $return eq "" );
        return $return;
    }

    else {
        return
"Unknown argument $what, choose one of routeCmd:,audio,light,mail,push,screen,queue";
    }

    return undef;
}

sub msgConfig_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name    = $hash->{NAME};
    my $TYPE    = GetType($name);
    my $devName = $dev->{NAME};
    my $devType = GetType($devName);

    return ""
      if ( IsDisabled($name)
        or IsDisabled($devName)
        or !AttrVal( $devName, "msgRcv", AttrVal( $name, "msgRcv", "1" ) ) );

    Log3 $name, 5, "$TYPE $name: called function $TYPE" . "_Notify()";

    my @events = @{ deviceEvents( $dev, 1 ) };

    return "" unless (@events);

    foreach my $event (@events) {
        next
          unless (
            $event =~ m/^(msgText|queryData|((?:OTR)?Last)Message|message)/ );
        my ( $sender, $msg );

        # TelegramBot
        if ( $devType eq "TelegramBot" ) {
            if ( $1 eq "msgText" ) {
                $sender = ReadingsVal( $devName, "msgPeerId", undef );
                $msg    = ReadingsVal( $devName, "msgText",   undef );
            }
            elsif ( $1 eq "queryData" ) {
                $sender = ReadingsVal( $devName, "queryPeerId", undef );
                $msg    = ReadingsVal( $devName, "queryData",   undef );
            }
        }

        # Jabber
        elsif ( $devType eq "Jabber" ) {
            ($sender) =
              ( ReadingsVal( $devName, $2 . "SenderJID", undef ) =~ m/[^\/]/g );
            $msg = ReadingsVal( $devName, $2 . "Message", undef );
        }

        # yowsup
        elsif ( $devType eq "yowsup" ) {
            $sender  = $devName;
            $devName = $modules{yowsup}{defptr}{yowsup}->{NAME};
            $msg     = ReadingsVal( $devName, "message", undef );
        }

        next unless ( $msg && $msg ne "" );

        unless ( $sender && $sender ne "" ) {
            Log3 $name, 4, "msg: "
              . "ERROR: Routing ERROR - Unable to retrieve sender reference from $devName";
            next;
        }

        my $delivered = 0;

        foreach my $t ( "push", "screen" ) {
            my @contacts = devspec2array(
                "msgContact" . ucfirst($t) . "=.*$devName:[@#]*$sender.*" );

            if (@contacts) {
                foreach (@contacts) {
                    next unless ( IsDevice($_) );

                    Log3 $_, 4,
                      "msg $_: " . "Received $t message from $devName: $msg";

                    $delivered = 1;
                    my $recipient = $defs{$_};

                    readingsBeginUpdate($recipient);
                    readingsBulkUpdate( $recipient,
                        "fhemMsgRcv" . ucfirst($t), $msg );
                    readingsBulkUpdate( $recipient,
                        "fhemMsgRcv" . ucfirst($t) . "Gw", $devName );
                    readingsEndUpdate( $recipient, 1 );
                }
            }

            last if ($delivered);
        }

        unless ($delivered) {
            Log3 $name, 4, "msg: "
              . "ERROR: Missing reference in msgContact attribute to $sender for received $t message from $devName";
        }

    }

    return "";
}

# module Fn ####################################################################
sub MSG_FindAttrVal($$$$) {
    my ( $d, $n, $msgType, $default ) = @_;
    $msgType = "" unless ($msgType);
    $msgType = ucfirst($msgType);
    $n .= $msgType if ( $n =~ /^msg(Contact)$/ );

    my $g = (
        (
            defined( $modules{msgConfig}{defptr} )
              && $n !~ /^(verbose|msgContact.*)$/
        )
        ? $modules{msgConfig}{defptr}{NAME}
        : ""
    );

    return

      # look for direct
      AttrVal(
        $d, $n,

        # look for indirect
        AttrVal(
            AttrVal( $d, "msgRecipient$msgType", "" ),
            $n,

            # look for indirect, type-independent
            AttrVal(
                AttrVal( $d, "msgRecipient", "" ),
                $n,

                # look for global direct
                AttrVal(
                    $g, $n,

                    # look for global indirect
                    AttrVal(
                        AttrVal( $g, "msgRecipient$msgType", "" ),
                        $n,

                        # look for global indirect, type-independent
                        AttrVal(
                            AttrVal( $g, "msgRecipient", "" ),
                            $n,

                            # default
                            $default
                        )
                    )
                )
            )
        )
      );
}

sub msgConfig_FindReadingsVal($$$$) {
    my ( $d, $n, $msgType, $default ) = @_;
    $msgType = ucfirst($msgType) if ($msgType);

    return

      # look for direct
      ReadingsVal(
        $d, $n,

        # look for indirect
        ReadingsVal(
            AttrVal( $d, "msgRecipient$msgType", "" ),
            $n,

            # look for indirect, type-independent
            ReadingsVal(
                AttrVal( $d, "msgRecipient", "" ),
                $n,

                # default
                $default
            )
        )
      );
}

sub msgConfig_QueueAdd(@) {
    my (
        $msgA,          $params,   $datetime,  $msgID,
        $minorID,       $type,     $recipient, $subRecipient,
        $termRecipient, $priority, $title,     $msg
    ) = @_;

    my $name = $modules{msgConfig}{defptr}{NAME};

    return 0 if ( $defs{$name}{queue}{$recipient}{"$msgID.$minorID"} );

    $defs{$name}{queue}{$recipient}{"$msgID.$minorID"} = {
        msgOrig           => $msgA,
        msgOrigParams     => $params,
        datetime          => $datetime,
        majorId           => $msgID,
        minorId           => $minorID,
        type              => $type,
        recipient         => $recipient,
        subRecipient      => $subRecipient,
        terminalRecipient => $termRecipient,
        priority          => $priority,
        title             => $title,
        message           => $msg,
    };

    delete $defs{$name}{queue}{$recipient}{"$msgID.$minorID"}{msgOrigParams}
      {msgQID};

    readingsSingleUpdate(
        $defs{$name},
        "Q_" . $recipient,
        scalar keys %{ $defs{$name}{queue}{$recipient} }, 1
    );

    return 1;
}

sub msgConfig_QueueReleaseMsgId($$) {
    my ( $recipient, $msgID ) = @_;

    my $name = $modules{msgConfig}{defptr}{NAME};

    return 0
      unless ( $defs{$name}{queue}
        && $defs{$name}{queue}{$recipient}
        && $defs{$name}{queue}{$recipient}{$msgID} );

    delete $defs{$name}{queue}{$recipient}{$msgID};
    my $c = scalar keys %{ $defs{$name}{queue}{$recipient} };
    delete $defs{$name}{queue}{$recipient} unless ($c);

    readingsSingleUpdate( $defs{$name}, "Q_" . $recipient, $c, 1 );

    return 1;
}

1;

=pod
=item helper
=item summary global settings and tools for FHEM command <a href="#MSG">msg</a>
=item summary_DE globale Einstellungen und Tools f&uml;r das FHEM Kommando <a href="#MSG">msg</a>
=begin html

    <p>
      <a name="msgConfig" id="msgConfig"></a>
    </p>
    <h3>
      msgConfig
    </h3>
    <ul>
      Provides global settings and tools for FHEM command <a href="#MSG">msg</a>.<br>
      A device named globalMsg will be created automatically when using msg-command for the first time and no msgConfig device could be found.<br>
      The device name can be renamed and reconfigured afterwards if desired.<br>
      <br>
      <a name="msgConfigdefine" id="msgConfigdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; msgConfig</code><br>
      </ul><br>
      <br>
      <a name="msgConfigset" id="msgConfigset"></a> <b>Set</b>
      <ul>
        <ul>
          <li>
            <b>addLocation</b> &nbsp;&nbsp;<Location Name>&nbsp;&nbsp;<br>
            Conveniently creates a Dummy device based on the given location name. It will be pre-configured to be used together with location-based routing when using the msg-command. The dummy device will be added to attribute msgLocationDevs automatically. Afterwards additional configuration is required by adding msgContact* or msgRecipient* attributes for gateway devices placed at this specific location.
          </li>
          <li>
            <b>cleanReadings</b> &nbsp;&nbsp;[<device and/or regex>]&nbsp;&nbsp;<br>
            Easy way to cleanup all fhemMsg readings. A parameter is optional and can be a concrete device name or mixed together with regex. This command is an alias for "deletereading <device and/or regex> fhemMsg.*".
          </li>
          <li>
            <b>createResidentsDev</b> &nbsp;&nbsp;<de|en>&nbsp;&nbsp;<br>
            Creates a new device named rgr_Residents of type <a href="#RESIDENTS">RESIDENTS</a>. It will be pre-configured based on the given language. In case rgr_Residents exists it will be updated based on the given language (basically only a language change). Afterwards next configuration steps will be displayed to use RESIDENTS together with presence-based routing of the msg-command.<br>
This next step is basically to set attribute msgResidentsDevice to refer to this RESIDENTS device either globally or for any other specific FHEM device (most likely you do NOT want to have this attribute set globally as otherwise this will affect ALL devices and therefore ALL msg-commands in your automations).<br>
            Note that use of RESIDENTS only makes sense together with ROOMMATE and or GUEST devices which still need to be created manually. See <a href="#RESIDENTSset">RESIDENTS Set commands</a> addRoommate and addGuest respectively.
          </li>
          <li>
            <b>createSwitcherDev</b> &nbsp;&nbsp;<de|en>&nbsp;&nbsp;<br>
            Creates a pre-configured Dummy device named HouseAnn and updates globalMsg attribute msgSwitcherDev to refer to it.
          </li>
        </ul>
      </ul>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="msgConfig" id="msgConfig"></a>
    </p>
    <h3>
      msgConfig
    </h3>
    <ul>
      Stellt globale Einstellungen und Tools f&uuml;r das FHEM Kommando <a href="#MSG">msg</a> bereit.<br>
      Ein Device mit dem Namen globalMsg wird automatisch bei der ersten Benutzung des msg Kommandos angelegt, sofern kein msgConfig Device gefunden wurde.<br>
      Der Device Name kann anschlie&szlig;end beliebig umbenannt und umkonfiguriert werden.<br>
      <br>
      <a name="msgConfigdefine" id="msgConfigdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; msgConfig</code><br>
      </ul><br>
      <br>
      <a name="msgConfigset" id="msgConfigset"></a> <b>Set</b>
      <ul>
        <ul>
          <li>
            <b>addLocation</b> &nbsp;&nbsp;<Name der Lokation>&nbsp;&nbsp;<br>
            Erstellt auf einfache Weise ein Dummy Device basierend auf dem &uuml;bergebenen Lokationsnamen. Es wird for die lokations-basierte Verwendung mit dem msg-Kommando vorkonfiguriert. Das Dummy Device wird automatisch zum Attribut msgLocationDevs hinzugef&uuml;gt. Anschlie&szlig;end ist eine weitere Konfiguration &uuml;ber die Attribute msgContact* oder msgRecipient* notwendig, die auf entsprechende Gateway Devices verweisen, die an dieser Lokation stehen.
          </li>
        </ul>
      </ul>
    </ul>

=end html_DE

=cut

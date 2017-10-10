###############################################################################
# $Id$
#
#TODO
# - be able to use type "default" to let read from attr
# - forceType/forceDevice in user parameters
# - implement default messages in RESIDENTS using msg command
# - queue message until recipient is available again (e.g. when absent)
#   also see https://forum.fhem.de/index.php/topic,69683.0.html
#   - new msgType "queue"
#   - escalation to type "queue" when n/a
#   - automatically trigger to release queue messages by arriving at home
#     (ROOMMATE)
# - allow some other ? to only reach people when they are at home
# - if ROOMMATE is asleep, queue message for next day
#   (usefull escalate for screen with PostMe?)
# - delivery options as attributes (like ! or ? to gateways, devices or types)
# - all messages should be queued and then delivered so a timer may come back
#   and check the gateway device for successful delivery
# - fix readings: store texts with \x{0000} notation
# - end user documentation / commandref !!
#
package main;
use strict;
use warnings;
use Data::Dumper;
use Time::HiRes qw(time);
use utf8;

# initialize ##################################################################
sub MSG_Initialize($$) {
    my %hash = (
        Fn => "CommandMsg",
        Hlp =>
"[<type>] [<\@device>|<e-mail address>] [<priority>] [|<title>|] <message-text>",
    );
    $cmds{msg} = \%hash;

    require "$attr{global}{modpath}/FHEM/msgSchema.pm";
}

# regular Fn ##################################################################
sub CommandMsg($$;$$);
sub CommandMsg($$;$$) {
    my ( $cl, $msg, $testMode ) = @_;
    my $return = "";

    if ( $featurelevel >= 5.7 ) {
        my %dummy;
        my ( $err, @a ) = ReplaceSetMagic( \%dummy, 0, ($msg) );
        $msg = join( " ", @a )
          unless ($err);
    }

    # find existing msgConfig device or create a new instance
    my $globalDevName = "globalMsg";
    if ( defined( $modules{msgConfig}{defptr} ) ) {
        $globalDevName = $modules{msgConfig}{defptr}{NAME};
    }
    else {
        fhem "define $globalDevName msgConfig";
        $return .=
          "Global configuration device $globalDevName was created.\n\n";
    }

    if ( $msg eq "" || $msg =~ /^\?[\s\t ]*$/ || $msg eq "help" ) {
        return $return
          . "Usage: msg [<type>] [<\@device>|<e-mail address>] [<priority>] [|<title>|] <message>";
    }

    # default settings
    my $cmdSchema = msgSchema::get();
    my $settings  = {
        audio => {
            typeEscalation => {
                gwUnavailable  => 'text',
                emergency      => 'text',
                residentGone   => 'text',
                residentAbsent => 'text',
            },
        },

        light => {
            typeEscalation => {
                gwUnavailable  => 'audio',
                emergency      => 'audio',
                residentGone   => 'audio',
                residentAbsent => 'audio',
            },
        },

        push => {
            typeEscalation => {
                gwUnavailable => 'mail',
                emergency     => 'mail',
            },
        },

        screen => {
            typeEscalation => {
                gwUnavailable  => 'light',
                emergency      => 'light',
                residentGone   => 'light',
                residentAbsent => 'light',
            },
        },

    };

    ################################################################
    ### extract message details
    ###

    my ( $msgA, $params ) = parseParams($msg, "[^\\S\\n]", " ");

    # only use output from parseParams when
    # parameters where found
    if ( ref($params) eq "HASH" && keys %$params ) {
        if ( scalar @$msgA > 0 ) {
            $msg = join( " ", @$msgA );
        }
        else {
            $msg = "";
        }
    }

    if ( defined( $params->{msgText} ) ) {
        Log3 $globalDevName, 5,
          "msg: Adding message text from given user parameters";
        $msg .= " " unless ( $msg eq "" );
        $msg .= $params->{msgText};
        delete $params->{msgText};
    }

    return $return
      . "Usage: msg [<type>] [<\@device>|<e-mail address>] [<priority>] [|<title>|] <message>"
      if ( $msg =~ m/^[\s\t\n ]*$/ );

    Log3 $globalDevName, 5, "msg: Extracted user parameters\n" . Dumper($params)
      if ( ref($params) eq "HASH" && keys %$params );

    my $types       = "";
    my $recipients  = "";
    my $priority    = "";
    my $title       = "-";
    my $priorityCat = "";

    # check for message types
    if ( $params->{msgType} ) {
        Log3 $globalDevName, 5, "msg: given types=$params->{msgType}";
        $types = $params->{msgType};
        $types =~ s/[\s\t ]+//g;
        delete $params->{msgType};
    }
    elsif ( $msg =~
s/^[\s\t ]*([a-z,]*!?(screen|light|audio|text|push|mail|queue)[\w,!?&|]*)[\s\t ]+//i
      )
    {
        Log3 $globalDevName, 5, "msg: found types=$1"
          unless ( defined($testMode) && $testMode eq "1" );
        $types = $1;
    }

    # programatic exception:
    # e.g. recipients were given automatically from empty readings
    if (
        $msg =~ m/^[\s\t ]*([!]?(([A-Za-z0-9%+._-])*@([,\-:|]+)))[\s\t ]+/
        || (   $params->{msgRcpt}
            && $params->{msgRcpt} =~
            m/^[\s\t ]*([!]?(([A-Za-z0-9%+._-])*@([,\-:|]+)))[\s\t ]+/ )
      )
    {
        Log3 $globalDevName, 4,
            "msg: message won't be sent - recipient '$1' contains special"
          . " characters like ',-:|' or behind the @ character is simply"
          . " emptiness. This might be okay, e.g. if you are using something"
          . " like a reading from RESIDENTS/ROOMMATE/GUEST to address present"
          . " or absent residents and this list is simply empty at this time."
          . " ($msg)";
        return;
    }

    # check for given recipients
    if ( $params->{msgRcpt} ) {
        Log3 $globalDevName, 5, "msg: given recipient=$params->{msgRcpt}";
        $recipients = $params->{msgRcpt};
        $recipients =~ s/[\s\t ]+//g;
        delete $params->{msgRcpt};
    }
    elsif ( $msg =~
s/^[\s\t ]*([!]?(([A-Za-z0-9%+._-])*@([%+a-z0-9A-Z.-]+))[\w,@.!?|:]*)[\s\t ]+//
      )
    {
        Log3 $globalDevName, 5, "msg: found recipient=$1"
          unless ( defined($testMode) && $testMode eq "1" );
        $recipients = $1;
    }

    # check for given priority
    if ( defined( $params->{msgPrio} ) ) {
        Log3 $globalDevName, 5, "msg: given priority=$params->{msgPrio}";
        $priority = $params->{msgPrio};
        $priority =~ s/[\s\t ]+//g;
        delete $params->{msgPrio};
    }
    elsif ( $msg =~ s/^[\s\t ]*([-+]{0,1}\d+[\.\d]*)[\s\t ]*// ) {
        Log3 $globalDevName, 5, "msg: found priority=$1"
          unless ( defined($testMode) && $testMode eq "1" );

        $priority = $1;
    }
    $priority = int($priority) if ( $priority =~ /^[-+]{0,1}\d+\.\d*$/ );
    return "Invalid priority $priority: Needs to be an integer value"
      unless ( $priority eq "" || $priority =~ /^[-+]{0,1}\d+$/ );

    # check for given message title
    if ( defined( $params->{msgTitle} ) ) {
        Log3 $globalDevName, 5, "msg: given title=$params->{msgTitle}";
        $title = $params->{msgTitle};
        $title =~ s/^[\s\t ]*\|(.*?)\|[\s\t ]*/$1/;
        delete $params->{msgTitle};
    }
    elsif ( $msg =~ s/^[\s\t ]*\|(.*?)\|[\s\t ]*// ) {
        Log3 $globalDevName, 5, "msg: found title=$1"
          unless ( defined($testMode) && $testMode eq "1" );

        $title = $1;
    }

    # check for user parameters (DEPRECATED / legacy compatibility only)
    if ( $msg =~ s/[\s\t ]*O(\[\{.*\}\])[\s\t ]*$// ) {

        Log3 $globalDevName, 5, "msg: found options=$1"
          unless ( defined($testMode) && $testMode eq "1" );

        # Use JSON module if possible
        eval {
            require JSON;
            import JSON qw( decode_json );
        };
        if ($@) {
            Log3 $globalDevName, 3,
              "msg: Error loading Perl::JSON. "
              . "Please switch to new syntax to use user parameters";
        }
        else {
            Log3 $globalDevName, 4,
              "msg: Please switch to new syntax to use user parameters";
            my $o;
            eval '$o = decode_json( Encode::encode_utf8($1) ); 1';
            if ($@) {
                Log3 $globalDevName, 5,
                  "msg: Error decoding JSON for user parameters: $@";
            }
            elsif ( ref($o) eq "ARRAY" ) {

                for my $item (@$o) {
                    next unless ( ref($item) eq "HASH" );
                    for my $key ( keys(%$item) ) {
                        next if ( ref( $item->{$key} ) );
                        my $val = $item->{$key};
                        $params->{$key} = $item->{$key}
                          unless ( $params->{$key} );
                    }
                }

                Log3 $globalDevName, 5,
                  "msg: Decoded user parameters\n" . Dumper($params)
                  if ($params);
            }
        }
    }

    $types = "default"
      if ( $types eq "" );
    my $msgSent   = 0;
    my $forwarded = "";
    my %sentTypesPerDevice;
    my $sentCounter    = 0;
    my $msgID          = time();
    my $msgDateTime    = TimeNow();
    my $isTypeOr       = 1;
    my $isRecipientOr  = 1;
    my $hasTypeOr      = 0;
    my $hasRecipientOr = 0;
    my $softFail       = 0;
    $recipients = "\@" . $globalDevName if ( $recipients eq "" );

    ################################################################
    ### recipient loop
    ###

    my @recipientsOr = split( /\|/, $recipients );
    Log3 $globalDevName, 6,
      "msg: recipientOr total is " . scalar( grep { defined $_ } @recipientsOr )
      unless ( defined($testMode) && $testMode eq "1" );

    for (
        my $iRecipOr = 0 ;
        $iRecipOr < scalar( grep { defined $_ } @recipientsOr ) ;
        $iRecipOr++
      )
    {
        Log3 $globalDevName, 6,
          "msg: "
          . "running loop recipientsOr for recipient(s) $recipientsOr[$iRecipOr]"
          unless ( defined($testMode) && $testMode eq "1" );
        my $loopReturn1 = "";

        $hasRecipientOr = 1
          if ( scalar( grep { defined $_ } @recipientsOr ) > 1 );

        my @recipient = split( /,/, $recipientsOr[$iRecipOr] );
        foreach my $device (@recipient) {
            Log3 $globalDevName, 6, "msg: running loop for device $device"
              unless ( defined($testMode) && $testMode eq "1" );
            my $loopReturn2 = "";

            ################################################################
            ### type loop
            ###

            my @typesOr = split( /\|/, $types );
            Log3 $globalDevName, 6,
              "msg: typeOr total is " . scalar( grep { defined $_ } @typesOr )
              unless ( defined($testMode) && $testMode eq "1" );

            for (
                my $iTypesOr = 0 ;
                $iTypesOr < scalar( grep { defined $_ } @typesOr ) ;
                $iTypesOr++
              )
            {
                Log3 $globalDevName, 6,
                  "msg: running loop typeOr for type(s) $typesOr[$iTypesOr]"
                  unless ( defined($testMode) && $testMode eq "1" );
                my $loopReturn3 = "";

                $hasTypeOr = 1
                  if ( scalar( grep { defined $_ } @typesOr ) > 1 );

                my @type = split( /,/, lc( $typesOr[$iTypesOr] ) );
                for (
                    my $i = 0 ;
                    $i < scalar( grep { defined $_ } @type ) ;
                    $i++
                  )
                {
                    Log3 $globalDevName, 6,
                      "msg: running loop for type $type[$i]"
                      unless ( defined($testMode) && $testMode eq "1" );
                    last unless ( defined( $type[$i] ) );

                    # check for correct type
                    my @msgCmds = (
                        "screen", "light", "audio", "text",
                        "push",   "mail",  "queue", "default"
                    );
                    unless ( grep { $type[$i] =~ /^$_/i } @msgCmds ) {
                        $loopReturn3 .= "Unknown message type $type[$i]\n";
                        next;
                    }

                    ###
                    ### /type loop
                    ################################################################

                    my @unavailabilityIndicators = (
                        "0",            "false",
                        "absent",       "disappeared",
                        "unauthorized", "unavailable",
                        "unreachable",  "disconnected"
                    );

                    my $logDevice;
                    $logDevice = $globalDevName;
                    $logDevice = $device
                      if (
                        MSG_FindAttrVal( $device, "verbose", undef, undef ) );

                    my $msgSentDev  = 0;
                    my $gatewayDevs = "";
                    my $forceDevice = 0;
                    my $forceQueue  = 0;

                    # for device type
                    my $deviceType = "device";
                    if ( $device =~
                        m/^(([A-Za-z0-9%+._-])+@+([%+a-z0-9A-Z.-]*))$/ )
                    {
                        $gatewayDevs = $1;
                        $deviceType  = "email";
                    }
                    elsif ( $device =~
                        m/^@?([A-Za-z\d_\.\-\/]+)([^A-Za-z\d_\.\-\/]+)[\s\t ]*$/
                      )
                    {
                        $device = $1;

                        foreach ( split( /(\S)/, $2 ) ) {
                            $forceDevice = 1 if ( $_ eq "!" );
                            $softFail    = 1 if ( $_ eq "?" );
                            $forceQueue  = 1 if ( $_ eq "&" );
                        }

                        Log3 $logDevice, 5,
"msg $device: forceDevice=$forceDevice (from device contact)"
                          if ($forceDevice);
                        Log3 $logDevice, 5,
"msg $device: softFail=$softFail (from device contact)"
                          if ($softFail);
                        Log3 $logDevice, 5,
"msg $device: forceQueue=$forceQueue (from device contact)"
                          if ($forceQueue);
                    }
                    elsif ( $device =~ /^@(.*)/ ) {
                        $device = $1;
                    }

                    # sub-recipient
                    my $subRecipient  = "";
                    my $termRecipient = "";
                    if ( $device =~
m/^@?([A-Za-z0-9._]+):([A-Za-z0-9._\-\/@+]*):?([A-Za-z0-9._\-\/@+]*)$/
                      )
                    {
                        $device        = $1;
                        $subRecipient  = $2;
                        $termRecipient = $3;
                    }

                    # FATAL ERROR: device does not exist
                    if ( !IsDevice($device)
                        && $deviceType eq "device" )
                    {
                        $loopReturn3 .= "Device $device does not exist\n"
                          unless ($softFail);
                        unless ( defined($testMode) && $testMode eq "1" ) {
                            Log3 $logDevice, 2,
                              "msg $device: Device does not exist"
                              unless ($softFail);
                            Log3 $logDevice, 5,
                              "msg $device: Device does not exist"
                              if ($softFail);
                        }

                        my $regex1 =
                          "\\s*!?@?" . $device . "[,|]";    # at the beginning
                        my $regex2 = "[,|]!?@?" . $device . "\\s*"; # at the end
                        my $regex3 =
                          ",!?@?" . $device . ",";    # in the middle with comma
                        my $regex4 =
                            "[\|,]!?@?"
                          . $device
                          . "[\|,]";    # in the middle with pipe and/or comma

                        $recipients =~ s/^$regex1//gi;
                        $recipients =~ s/$regex2$/|/gi;
                        $recipients =~ s/$regex3/,/gi;
                        $recipients =~ s/$regex4/|/gi;

                        next;
                    }

                    # Find custom types for devices
                    if ( $type[$i] eq "default" ) {
                        delete $typesOr[$iTypesOr]
                          if ( $typesOr[$iTypesOr] eq "default" );
                        delete $type[$i];
                        Log3 $logDevice, 5,
                          "msg $device: msgType lookup for $device:";

                        my @t = split(
                            m/\|/,
                            MSG_FindAttrVal(
                                $device, "msgType", undef, "text"
                            )
                        );
                        $hasTypeOr = 1
                          if ( scalar( grep { defined $_ } @t ) > 1 );

                        foreach (@t) {
                            Log3 $logDevice, 5,
                              "msg $device:    Adding to \@typesOr: $_";

                            push @typesOr, $_;

                            foreach ( split( /,/, lc($_) ) ) {
                                Log3 $logDevice, 5,
                                  "msg $device:       Adding to \@type: $_";
                                push @type, $_;
                            }
                        }
                    }

                    my $forceType = 0;
                    if ( $type[$i] =~
                        m/^([A-Za-z\d_\.\-\/]+)([^A-Za-z\d_\.\-\/]+)[\s\t ]*$/ )
                    {
                        $type[$i] = $1;

                        foreach ( split( /(\S)/, $2 ) ) {
                            $forceType  = 1 if ( $_ eq "!" );
                            $softFail   = 1 if ( $_ eq "?" );
                            $forceQueue = 1 if ( $_ eq "&" );
                        }

                        Log3 $logDevice, 5,
                          "msg $device: forceType=$forceType (from type)"
                          if ($forceType);
                        Log3 $logDevice, 5,
                          "msg $device: softFail=$softFail (from type)"
                          if ($softFail);
                        Log3 $logDevice, 5,
                          "msg $device: forceQueue=$forceQueue (from type)"
                          if ($forceQueue);
                    }

                    # next type loop if device is an email address
                    # and this is not the mail type loop run
                    if (   $deviceType eq "email"
                        && $type[$i] ne "mail"
                        && $type[$i] ne "text" )
                    {
                        Log3 $logDevice, 5,
                            "msg $device: "
                          . "Skipping loop for device type 'email' with unmatched message type '"
                          . $type[$i] . "'";
                        next;
                    }

                    my $typeUc      = ucfirst( $type[$i] );
                    my $catchall    = 0;
                    my $useLocation = 0;

                    ################################################################
                    ### get target information from device location
                    ###

                    # search for location references
                    my @locationDevs;
                    @locationDevs = split(
                        /,/,
                        MSG_FindAttrVal(
                            $device, "msgLocationDevs", $typeUc, ""
                        )
                    );

                    if ( $deviceType eq "device" ) {

                        # get device location
                        my $deviceLocation =
                          msgConfig_FindReadingsVal( $device, "location",
                            $typeUc, "" );

                        my $locationDev = "";
                        if ( $deviceLocation ne "" && $deviceType eq "device" )
                        {

                            # lookup matching location
                            foreach (@locationDevs) {

                                if ( $featurelevel >= 5.7 ) {
                                    my %dummy;
                                    my ( $err, @a ) =
                                      ReplaceSetMagic( \%dummy, 0, ($_) );
                                    $_ = join( " ", @a )
                                      unless ($err);
                                }

                                my $lName =
                                  AttrVal( $_, "msgLocationName", "" );
                                if ( $lName ne "" && $lName eq $deviceLocation )
                                {
                                    $locationDev = $_;
                                    last;
                                }
                            }

                            if ( $featurelevel >= 5.7 ) {
                                my %dummy;
                                my ( $err, @a ) =
                                  ReplaceSetMagic( \%dummy, 0, ($locationDev) );
                                $locationDev = join( " ", @a )
                                  unless ($err);
                            }

                            # look for gateway device
                            $gatewayDevs =
                              MSG_FindAttrVal( $locationDev, "msgContact",
                                $typeUc, "" );

                            # at least one of the location gateways needs to
                            # be available. Otherwise we fall back to
                            # non-location contacts
                            if ( $gatewayDevs ne "" ) {

                                if ( $featurelevel >= 5.7 ) {
                                    my %dummy;
                                    my ( $err, @a ) =
                                      ReplaceSetMagic( \%dummy, 0,
                                        ($gatewayDevs) );
                                    $gatewayDevs = join( " ", @a )
                                      unless ($err);
                                }

                                foreach
                                  my $gatewayDevOr ( split /\|/, $gatewayDevs )
                                {

                                    foreach my $gatewayDev ( split /,/,
                                        $gatewayDevOr )
                                    {
                                        my $tmpSubRecipient;
                                        if ( $gatewayDev =~ /:(.*)/ ) {
                                            $tmpSubRecipient = $1;
                                        }

                                        if (   $type[$i] ne "mail"
                                            && !IsDevice($gatewayDev)
                                            && $deviceType eq "device" )
                                        {
                                            $useLocation = 2
                                              if ( $useLocation == 0 );
                                        }
                                        elsif ( $type[$i] ne "mail"
                                            && IsDisabled($gatewayDev) )
                                        {
                                            $useLocation = 2
                                              if ( $useLocation == 0 );
                                        }
                                        elsif (
                                            $type[$i] ne "mail"
                                            && (
                                                (
                                                    grep {
                                                        ReadingsVal(
                                                            $gatewayDev,
                                                            "presence",
                                                            "present"
                                                          ) eq $_
                                                    } @unavailabilityIndicators
                                                )

                                                || (
                                                    grep {
                                                        ReadingsVal(
                                                            $gatewayDev,
                                                            "state",
                                                            "present"
                                                          ) eq $_
                                                    } @unavailabilityIndicators
                                                )

                                                || (
                                                    defined(
                                                        $defs{$gatewayDev}
                                                    )
                                                    && defined(
                                                        $defs{$gatewayDev}
                                                          {STATE}
                                                    )
                                                    && (
                                                        grep {
                                                            $defs{$gatewayDev}
                                                              {STATE} eq $_
                                                        } @unavailabilityIndicators
                                                    )
                                                )

                                                || ReadingsVal(
                                                    $gatewayDev, "available",
                                                    "yes"
                                                ) =~ m/^(0|no|false)$/i

                                                || ReadingsVal(
                                                    $gatewayDev, "reachable",
                                                    "yes"
                                                ) =~ m/^(0|no|false)$/i
                                            )
                                          )
                                        {
                                            $useLocation = 2
                                              if ( $useLocation == 0 );
                                        }
                                        else {
                                            $useLocation = 1;
                                        }

                                    }

                                }

                                # use gatewayDevs from location only
                                # if it has been confirmed to be available
                                if ( $useLocation == 1 ) {
                                    Log3 $logDevice, 4, "msg $device: "
                                      . "Matching location definition found";
                                }
                                else {
                                    $gatewayDevs = "";
                                }
                            }
                        }
                    }

                    ################################################################
                    ### given device name is already a gateway device itself
                    ###

                    my $deviceType2 = GetType($device);

                    if (
                           $gatewayDevs eq ""
                        && $deviceType eq "device"
                        && $deviceType2 ne ""
                        && (
                            (
                                $type[$i] eq "audio" && defined(
                                    $cmdSchema->{ $type[$i] }{$deviceType2}
                                )
                            )
                            || (
                                $type[$i] eq "light"
                                && defined(
                                    $cmdSchema->{ $type[$i] }{$deviceType2}
                                )
                            )
                            || (
                                $type[$i] eq "push"
                                && defined(
                                    $cmdSchema->{ $type[$i] }{$deviceType2}
                                )
                            )
                            || (
                                $type[$i] eq "screen"
                                && defined(
                                    $cmdSchema->{ $type[$i] }{$deviceType2}
                                )
                            )
                            || (
                                $type[$i] eq "queue"
                                && defined(
                                    $cmdSchema->{ $type[$i] }{$deviceType2}
                                )
                            )
                        )
                      )
                    {
                        Log3 $logDevice, 4,
                            "msg $device: Recipient type $deviceType2 "
                          . "is a gateway device itself for message type "
                          . $type[$i]
                          . ". Still checking for any delegates ..."
                          unless ( defined($testMode) && $testMode eq "1" );

                        $gatewayDevs =
                          MSG_FindAttrVal( $device, "msgContact", $typeUc,
                            $device );
                    }

                    ################################################################
                    ### get target information from device
                    ###

                    elsif ( $deviceType eq "device" && $gatewayDevs eq "" ) {

                        # look for gateway device
                        $gatewayDevs =
                          MSG_FindAttrVal( $device, "msgContact", $typeUc, "" );

                        # fallback/catchall
                        if ( $gatewayDevs eq "" ) {
                            $catchall = 1
                              if ( $device ne $globalDevName );

                            Log3 $logDevice, 6,
                              "msg $device:			(No $typeUc contact defined, "
                              . "trying global instead)"
                              if ( $catchall == 1 );

                            $gatewayDevs =
                              MSG_FindAttrVal( $globalDevName, "msgContact",
                                $typeUc, "" );
                        }
                    }

                    # Find priority if none was explicitly specified
                    my $loopPriority = $priority;
                    $loopPriority =
                      MSG_FindAttrVal( $device, "msgPriority$typeUc", $typeUc,
                        MSG_FindAttrVal( $device, "msgPriority", $typeUc, 0 ) )
                      if ( $priority eq "" );

                    # check for available routes
                    #
                    my %routes;
                    $routes{screen} = 0;
                    $routes{light}  = 0;
                    $routes{audio}  = 0;
                    $routes{text}   = 0;
                    $routes{push}   = 0;
                    $routes{mail}   = 0;
                    $routes{queue}  = 1;

                    if (
                        !defined($testMode)
                        || (   $testMode ne "1"
                            && $testMode ne "2" )
                      )
                    {
                        Log3 $logDevice, 5,
                          "msg $device: Checking for available routes "
                          . "(triggered by type $type[$i])";

                        $routes{screen} = 1
                          if (
                            $deviceType eq "device"
                            && CommandMsg( "screen",
                                "screen \@$device $priority Routing Test", 1 )
                            eq "ROUTE_AVAILABLE"
                          );

                        $routes{light} = 1
                          if (
                            $deviceType eq "device"
                            && CommandMsg( "light",
                                "light \@$device $priority Routing Test", 1 )
                            eq "ROUTE_AVAILABLE"
                          );

                        $routes{audio} = 1
                          if (
                            $deviceType eq "device"
                            && CommandMsg( "audio",
                                "audio \@$device $priority Routing Test", 1 )
                            eq "ROUTE_AVAILABLE"
                          );

                        if (
                            $deviceType eq "device"
                            && CommandMsg( "push",
                                "push \@$device $priority Routing Test", 1 ) eq
                            "ROUTE_AVAILABLE"
                          )
                        {
                            $routes{push} = 1;
                            $routes{text} = 1;
                        }

                        if (
                            CommandMsg( "mail",
                                "mail \@$device $priority Routing Test", 1 ) eq
                            "ROUTE_AVAILABLE"
                          )
                        {
                            $routes{mail} = 1;
                            $routes{text} = 1;
                        }

                        $routes{mail} = 1
                          if ( $deviceType eq "email" );

                        Log3 $logDevice, 4,
                            "msg $device: Available routes: screen="
                          . $routes{screen}
                          . " light="
                          . $routes{light}
                          . " audio="
                          . $routes{audio}
                          . " text="
                          . $routes{text}
                          . " push="
                          . $routes{push}
                          . " mail="
                          . $routes{mail};
                    }

                    ##################################################
                    ### dynamic routing for text (->push, ->mail)
                    ###
                    if ( $type[$i] eq "text" ) {

                        # user selected emergency priority text threshold
                        my $prioThresTextEmg =
                          MSG_FindAttrVal( $device, "msgThPrioTextEmergency",
                            $typeUc, 2 );

                        # user selected low priority text threshold
                        my $prioThresTextNormal =
                          MSG_FindAttrVal( $device, "msgThPrioTextNormal",
                            $typeUc, -2 );

                        # Decide push and/or e-mail destination based
                        # on priorities
                        if (   $loopPriority >= $prioThresTextEmg
                            && $routes{push} == 1
                            && $routes{mail} == 1 )
                        {
                            Log3 $logDevice, 4,
                              "msg $device: "
                              . "Text routing decision: push+mail(1)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push+mail";
                            push @type, "push"
                              unless grep { "push" eq $_ } @type;
                            push @type, "mail"
                              unless grep { "mail" eq $_ } @type;
                        }
                        elsif ($loopPriority >= $prioThresTextEmg
                            && $routes{push} == 1
                            && $routes{mail} == 0 )
                        {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: push(2)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push";
                            push @type, "push"
                              unless grep { "push" eq $_ } @type;
                        }
                        elsif ($loopPriority >= $prioThresTextEmg
                            && $routes{push} == 0
                            && $routes{mail} == 1 )
                        {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: mail(3)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>mail";
                            push @type, "mail"
                              unless grep { "mail" eq $_ } @type;
                        }
                        elsif ($loopPriority >= $prioThresTextNormal
                            && $routes{push} == 1 )
                        {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: push(4)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push";
                            push @type, "push"
                              unless grep { "push" eq $_ } @type;
                        }
                        elsif ($loopPriority >= $prioThresTextNormal
                            && $routes{mail} == 1 )
                        {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: mail(5)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>mail";
                            push @type, "mail"
                              unless grep { "mail" eq $_ } @type;
                        }
                        elsif ( $routes{mail} == 1 ) {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: mail(6)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>mail";
                            push @type, "mail"
                              unless grep { "mail" eq $_ } @type;
                        }
                        elsif ( $routes{push} == 1 ) {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: push(7)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push";
                            push @type, "push"
                              unless grep { "push" eq $_ } @type;
                        }

                        # FATAL ERROR: routing decision failed
                        else {
                            Log3 $logDevice, 4,
                                "msg $device: "
                              . "Text routing FAILED - priority=$loopPriority push="
                              . $routes{push}
                              . " mail="
                              . $routes{mail};

                            $loopReturn3 .=
                              "ERROR: Could not find any Push or Mail contact "
                              . "for device $device - set attributes: msgContactPush "
                              . "| msgContactMail | msgContactText | msgRecipientPush "
                              . "| msgRecipientMail | msgRecipientText | msgRecipient\n";
                        }

                        next;
                    }

                    # FATAL ERROR: we could not find any targets for
                    # user specified device...
                    if (   $gatewayDevs eq ""
                        && $device ne $globalDevName )
                    {
                        $loopReturn3 .=
                            "ERROR: Could not find any $typeUc contact "
                          . "for device $device - set attributes: msgContact$typeUc | msgRecipient$typeUc | msgRecipient\n"
                          unless ( $type[$i] eq "queue" );
                    }

                    # FATAL ERROR: we could not find any targets at all
                    elsif ( $gatewayDevs eq "" ) {
                        $loopReturn3 .=
                          "ERROR: Could not find any general $typeUc contact. "
                          . "Please specify a destination device or set attributes in general msg configuration device $globalDevName : msgContact$typeUc | msgRecipient$typeUc | msgRecipient\n"
                          unless ( $type[$i] eq "queue" );
                    }

                    # user selected audio-visual announcement state
                    my $annState = ReadingsVal(
                        MSG_FindAttrVal(
                            $device, "msgSwitcherDev", $typeUc, ""
                        ),
                        "state", "long"
                    );

                    # user selected emergency priority audio threshold
                    my $prioThresAudioEmg =
                      MSG_FindAttrVal( $device, "msgThPrioAudioEmergency",
                        $typeUc, 2 );

                    # user selected high priority audio threshold
                    my $prioThresAudioHigh =
                      MSG_FindAttrVal( $device, "msgThPrioAudioHigh", $typeUc,
                        1 );

                    # user selected high priority threshold
                    my $prioThresHigh =
                      MSG_FindAttrVal( $device, "msgThPrioHigh", $typeUc, 2 );

                    # user selected normal priority threshold
                    my $prioThresNormal =
                      MSG_FindAttrVal( $device, "msgThPrioNormal", $typeUc, 0 );

                    if ( $type[$i] eq "audio" ) {
                        if (   $annState eq "long"
                            || $forceType == 1
                            || $forceDevice == 1
                            || $loopPriority >= $prioThresAudioEmg )
                        {
                            $priorityCat = "";
                        }
                        elsif ( $loopPriority >= $prioThresAudioHigh ) {
                            $priorityCat = "ShortPrio";
                        }
                        else {
                            $priorityCat = "Short";
                        }
                    }
                    else {
                        if ( $loopPriority >= $prioThresHigh ) {
                            $priorityCat = "High";
                        }
                        elsif ( $loopPriority >= $prioThresNormal ) {
                            $priorityCat = "";
                        }
                        else {
                            $priorityCat = "Low";
                        }
                    }

                    # get resident presence information
                    #
                    my $residentDevState    = "";
                    my $residentDevPresence = "";

                    # device
                    if ( ReadingsVal( $device, "presence", "-" ) ne "-" ) {
                        $residentDevState = ReadingsVal( $device, "state", "" );
                        $residentDevPresence =
                          ReadingsVal( $device, "presence", "" );
                    }

                    # device indirect
                    if (
                        (
                               $residentDevState eq ""
                            || $residentDevPresence eq ""
                        )
                        && ReadingsVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "presence", "" )
                          if ( $residentDevPresence eq "" );
                    }

                    # device indirect general
                    if (
                        (
                               $residentDevState eq ""
                            || $residentDevPresence eq ""
                        )
                        && ReadingsVal( AttrVal( $device, "msgRecipient", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal( AttrVal( $device, "msgRecipient", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal( AttrVal( $device, "msgRecipient", "" ),
                            "presence", "" )
                          if ( $residentDevPresence eq "" );
                    }

                    # device explicit
                    if (
                        (
                               $residentDevState eq ""
                            || $residentDevPresence eq ""
                        )
                        && ReadingsVal(
                            AttrVal( $device, "msgResidentsDev", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal(
                            AttrVal( $device, "msgResidentsDev", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal(
                            AttrVal( $device, "msgResidentsDev", "" ),
                            "presence", "" )
                          if ( $residentDevPresence eq "" );
                    }

                    # global indirect
                    if (
                        (
                               $residentDevState eq ""
                            || $residentDevPresence eq ""
                        )
                        && ReadingsVal(
                            AttrVal(
                                $globalDevName, "msgRecipient$typeUc", ""
                            ),
                            "presence",
                            "-"
                        ) ne "-"
                      )
                    {
                        $residentDevState = ReadingsVal(
                            AttrVal(
                                $globalDevName, "msgRecipient$typeUc", ""
                            ),
                            "state", ""
                        ) if ( $residentDevState eq "" );
                        $residentDevPresence = ReadingsVal(
                            AttrVal(
                                $globalDevName, "msgRecipient$typeUc", ""
                            ),
                            "presence",
                            ""
                        ) if ( $residentDevPresence eq "" );
                    }

                    # global indirect general
                    if (
                        (
                               $residentDevState eq ""
                            || $residentDevPresence eq ""
                        )
                        && ReadingsVal(
                            AttrVal( $globalDevName, "msgRecipient", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal(
                            AttrVal( $globalDevName, "msgRecipient", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal(
                            AttrVal( $globalDevName, "msgRecipient", "" ),
                            "presence", "" )
                          if ( $residentDevPresence eq "" );
                    }

                    # global explicit
                    if (
                        (
                               $residentDevState eq ""
                            || $residentDevPresence eq ""
                        )
                        && ReadingsVal(
                            AttrVal( $globalDevName, "msgResidentsDev", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal(
                            AttrVal( $globalDevName, "msgResidentsDev", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal(
                            AttrVal( $globalDevName, "msgResidentsDev", "" ),
                            "presence", "" )
                          if ( $residentDevPresence eq "" );
                    }

                    ################################################################
                    ### Send message
                    ###

                    my $queued = 0;

                    # user selected emergency priority text threshold
                    my $prioThresGwEmg =
                      MSG_FindAttrVal( $device, "msgThPrioGwEmergency",
                        $typeUc, 2 );

                    if ( $featurelevel >= 5.7 ) {
                        my %dummy;
                        my ( $err, @a ) =
                          ReplaceSetMagic( \%dummy, 0, ($gatewayDevs) );
                        $gatewayDevs = join( " ", @a )
                          unless ($err);
                    }

                    my %gatewaysStatus;
                    $gatewayDevs = $globalDevName if ( $type[$i] eq "queue" );

                    foreach my $gatewayDevOr ( split /\|/, $gatewayDevs ) {
                        foreach my $gatewayDev ( split /,/, $gatewayDevOr ) {

                            if ( $gatewayDev =~
m/^@?([A-Za-z0-9._]+):([A-Za-z0-9._\-\/@+]*):?([A-Za-z0-9._\-\/@+]*)$/
                              )
                            {
                                $gatewayDev    = $1;
                                $subRecipient  = $2 if ( $subRecipient eq "" );
                                $termRecipient = $3 if ( $termRecipient eq "" );
                            }

                            my $logMsg =
                                "msg $device: "
                              . "Trying to send message via gateway $gatewayDev";
                            $logMsg .= " to recipient $subRecipient"
                              if ( $subRecipient ne "" );
                            $logMsg .= ", terminal device $termRecipient"
                              if ( $termRecipient ne "" );
                            Log3 $logDevice, 5, $logMsg
                              unless ( defined($testMode) && $testMode eq "1" );

                            ##############
                           # check for gateway availability and set route status
                           #

                            my $routeStatus = "OK";
                            if ( $type[$i] eq "queue" ) {
                                $routeStatus = "OK_QUEUE";
                            }

                            elsif ($type[$i] ne "mail"
                                && !IsDevice($gatewayDev)
                                && $deviceType eq "device" )
                            {
                                $routeStatus = "UNDEFINED";
                            }

                            elsif ( $type[$i] ne "mail"
                                && IsDisabled($gatewayDev) )
                            {
                                $routeStatus = "DISABLED";
                            }

                            elsif (
                                $type[$i] ne "mail"
                                && (
                                    (
                                        grep {
                                            ReadingsVal( $gatewayDev,
                                                "presence", "present" ) eq $_
                                        } @unavailabilityIndicators
                                    )

                                    || (
                                        grep {
                                            ReadingsVal( $gatewayDev, "state",
                                                "present" ) eq $_
                                        } @unavailabilityIndicators
                                    )

                                    || (
                                           IsDevice($gatewayDev)
                                        && defined( $defs{$gatewayDev}{STATE} )
                                        && (
                                            grep {
                                                $defs{$gatewayDev}{STATE} eq $_
                                            } @unavailabilityIndicators
                                        )
                                    )

                                    || ReadingsVal( $gatewayDev, "available",
                                        "yes" ) =~ m/^(0|no|false)$/i

                                    || ReadingsVal( $gatewayDev, "reachable",
                                        "yes" ) =~ m/^(0|no|false)$/i
                                )
                              )
                            {
                                $routeStatus = "UNAVAILABLE";
                            }

                            elsif (
                                $type[$i] ne "mail"
                                && (
                                    ReadingsVal( $gatewayDev, "presence",
                                        "present" ) =~
m/^(0|false|absent|disappeared|unauthorized|disconnected|unreachable)$/i
                                    || ReadingsVal( $gatewayDev, "state",
                                        "present" ) =~
m/^(absent|disappeared|unauthorized|disconnected|unreachable)$/i
                                    || (   IsDevice($gatewayDev)
                                        && defined( $defs{$gatewayDev}{STATE} )
                                        && $defs{$gatewayDev}{STATE} =~
m/^(absent|disappeared|unauthorized|disconnected|unreachable)$/i
                                    )
                                    || ReadingsVal( $gatewayDev, "available",
                                        "yes" ) =~ m/^(0|no|off|false)$/i
                                    || ReadingsVal( $gatewayDev, "reachable",
                                        "yes" ) =~ m/^(0|no|off|false)$/i
                                )
                              )
                            {
                                $routeStatus = "UNAVAILABLE";
                            }

                            elsif ( $type[$i] eq "screen"
                                && ReadingsVal( $gatewayDev, "power", "on" ) =~
                                m/^(0|off)$/i )
                            {
                                $routeStatus = "OFF";
                            }

                            elsif ($type[$i] eq "audio"
                                && $annState ne "long"
                                && $annState ne "short" )
                            {
                                $routeStatus = "USER_DISABLED";
                            }

                            elsif ( $type[$i] eq "light" && $annState eq "off" )
                            {
                                $routeStatus = "USER_DISABLED";
                            }

                            elsif ($type[$i] ne "push"
                                && $type[$i] ne "mail"
                                && $residentDevPresence eq "absent" )
                            {
                                $routeStatus = "USER_ABSENT";
                            }

                            elsif ($type[$i] ne "push"
                                && $type[$i] ne "mail"
                                && $residentDevState eq "asleep" )
                            {
                                $routeStatus = "USER_ASLEEP";
                            }

                            # enforce by user request
                            if (
                                (
                                       $routeStatus eq "USER_DISABLED"
                                    || $routeStatus eq "USER_ABSENT"
                                    || $routeStatus eq "USER_ASLEEP"
                                )
                                && ( $forceType == 1 || $forceDevice == 1 )
                              )
                            {
                                $routeStatus = "OK_ENFORCED";
                            }

                            # enforce by priority
                            if (
                                (
                                       $routeStatus eq "USER_DISABLED"
                                    || $routeStatus eq "USER_ABSENT"
                                    || $routeStatus eq "USER_ASLEEP"
                                )
                                && $loopPriority >= $prioThresGwEmg
                              )
                            {
                                $routeStatus = "OK_EMERGENCY";
                            }

                            # add location status
                            if ( $useLocation == 2 ) {
                                $routeStatus .= "+LOCATION-UNAVAILABLE";
                            }
                            elsif ( $useLocation == 1 ) {
                                $routeStatus .= "+LOCATION";
                            }

                            # # add to queue
                            # if (
                            #     (
                            #            $routeStatus eq "USER_DISABLED"
                            #         || $routeStatus eq "USER_ABSENT"
                            #         || $routeStatus eq "USER_ASLEEP"
                            #     )
                            #     && $routeStatus !~ /^OK/
                            #     && !$softFail
                            #   )
                            # {
                            #     $routeStatus .= "+QUEUE";
                            # }

                            my $gatewayType =
                              $type[$i] eq "mail"
                              ? "fhemMsgMail"
                              : GetType( $gatewayDev, "UNDEFINED" );

                            my $defTitle = "";
                            $defTitle =
                              $cmdSchema->{ $type[$i] }{$gatewayType}
                              {defaultValues}{$priorityCat}{TITLE}
                              if (
                                defined(
                                    $cmdSchema->{ $type[$i] }{$gatewayType}
                                      {defaultValues}{$priorityCat}{TITLE}
                                )
                                && $priorityCat ne ""
                              );
                            $defTitle =
                              $cmdSchema->{ $type[$i] }{$gatewayType}
                              {defaultValues}{Normal}{TITLE}
                              if (
                                defined(
                                    $cmdSchema->{ $type[$i] }{$gatewayType}
                                      {defaultValues}{Normal}{TITLE}
                                )
                                && $priorityCat eq ""
                              );

                            Log3 $logDevice, 5,
                              "msg $device: "
                              . "Determined default title: $defTitle"
                              unless ( defined($testMode) && $testMode eq "1" );

                            # use title from device, global or internal default
                            my $loopTitle = $title;
                            $loopTitle = MSG_FindAttrVal(
                                $device,
                                "msgTitle$typeUc$priorityCat",
                                $typeUc,
                                MSG_FindAttrVal(
                                    $device,
                                    "msgTitle$typeUc",
                                    $typeUc,
                                    MSG_FindAttrVal(
                                        $device, "msgTitle",
                                        $typeUc, $defTitle
                                    )
                                )
                            ) if ( $title eq "-" );

                            $loopTitle = ""
                              if ( $loopTitle eq "none"
                                || $loopTitle eq "-" );

                            my $loopMsg = $msg;
                            if ( $catchall == 1 && $type[$i] ne "queue" ) {
                                $loopTitle = "Fw: $loopTitle"
                                  if ( $loopTitle ne ""
                                    && $type[$i] !~ /^(audio|screen)$/ );
                                $loopMsg = "Forwarded Message: $loopMsg"
                                  if ( $loopTitle eq "" );
                                if ( $type[$i] eq "mail" ) {
                                    $loopMsg .=
                                        "\n\n-- \nMail catched "
                                      . "from device $device";
                                }
                                elsif ( $type[$i] !~ /^(audio|screen)$/ ) {
                                    $loopMsg .=
                                      " ### (Catched from device $device)";
                                }
                            }

                            my $loopMsgShrt =
                              defined( $params->{msgTextShrt} )
                              ? $params->{msgTextShrt}
                              : $msg;

                            # correct message format
                            #

                            # Remove Sonos Speak commands
                            $loopMsg =~ s/(\s*\|\w+\|\s*)/\\n\\n/gi
                              if ( $type[$i] ne "audio" );
                            $loopMsgShrt =~ s/(\s*\|\w+\|\s*)/\\n\\n/gi
                              if ( $type[$i] ne "audio" );

                            # Replace new line with HTML break
                            # for e-mails
                            $loopMsg =~ s/\n/<br \/>\n/gi
                              if ( $type[$i] eq "mail" );
                            $loopMsgShrt =~ s/\n/<br \/>\n/gi
                              if ( $type[$i] eq "mail" );

                           # use command from device, global or internal default
                            my $defCmd = "";
                            $defCmd =
                              $cmdSchema->{ $type[$i] }{$gatewayType}
                              {$priorityCat}
                              if (
                                defined(
                                    $cmdSchema->{ $type[$i] }{$gatewayType}
                                      {$priorityCat}
                                )
                                && $priorityCat ne ""
                              );
                            $defCmd =
                              $cmdSchema->{ $type[$i] }{$gatewayType}{Normal}
                              if (
                                defined(
                                    $cmdSchema->{ $type[$i] }{$gatewayType}
                                      {Normal}
                                )
                                && $priorityCat eq ""
                              );
                            my $cmd =

                              # gateway device
                              AttrVal(
                                $gatewayDev, "msgCmd$typeUc$priorityCat",

                                MSG_FindAttrVal(
                                    $device, "msgCmd$typeUc$priorityCat",
                                    $typeUc, $defCmd
                                )
                              );

                            if ( $cmd eq "" && $type[$i] ne "queue" ) {
                                Log3 $logDevice, 4,
                                  "$gatewayDev: Unknown command schema "
                                  . "for gateway device type $gatewayType. Use manual definition by userattr msgCmd*"
                                  unless ( defined($testMode)
                                    && $testMode eq "1" );
                                $loopReturn3 .=
                                    "$gatewayDev: Unknown command schema "
                                  . "for gateway device type $gatewayType. Use manual definition by userattr msgCmd*\n";
                                next;
                            }

                            # ReplaceSetMagic
                            #
                            my $replaceError;
                            if ( $featurelevel >= 5.7 ) {
                                my %dummy;
                                my ( $err, @a );

                                # TITLE
                                ( $err, @a ) =
                                  ReplaceSetMagic( \%dummy, 0, ($loopTitle) );
                                $replaceError .=
                                  "ReplaceSetMagic failed for TITLE: $err\n"
                                  if ($err);
                                $loopTitle = join( " ", @a )
                                  unless ($err);

                                # RECIPIENT
                                if ( $subRecipient ne "" ) {
                                    ( $err, @a ) =
                                      ReplaceSetMagic( \%dummy, 0,
                                        ($subRecipient) );
                                    $replaceError .=
                                        "ReplaceSetMagic failed "
                                      . "for RECIPIENT: $err\n"
                                      if ($err);
                                    $subRecipient = join( " ", @a )
                                      unless ($err);
                                }

                                # TERMINAL
                                if ( $termRecipient ne "" ) {
                                    ( $err, @a ) =
                                      ReplaceSetMagic( \%dummy, 0,
                                        ($termRecipient) );
                                    $replaceError .=
                                        "ReplaceSetMagic failed "
                                      . "for TERMINAL: $err\n"
                                      if ($err);
                                    $termRecipient = join( " ", @a )
                                      unless ($err);
                                }
                            }

                            $cmd =~ s/%PRIORITY%/$loopPriority/gi;
                            $cmd =~ s/%PRIOCAT%/$priorityCat/gi;
                            $cmd =~ s/%MSG%/$loopMsg/gi;
                            $cmd =~ s/%MSGSHRT%/$loopMsgShrt/gi;
                            $cmd =~ s/%MSGID%/$msgID.$sentCounter/gi;
                            $cmd =~ s/%TITLE%/$loopTitle/gi;

                            my $loopTitleShrt =
                              defined( $params->{msgTitleShrt} )
                              ? $params->{msgTitleShrt}
                              : MSG_FindAttrVal(
                                $device,
                                "msgTitleShrt$typeUc$priorityCat",
                                $typeUc,
                                MSG_FindAttrVal(
                                    $device,
                                    "msgTitleShrt$typeUc",
                                    $typeUc,
                                    MSG_FindAttrVal(
                                        $device, "msgTitleShrt",
                                        $typeUc, $loopTitle
                                    )
                                )
                              );

                            $loopTitleShrt =
                              substr( $loopTitleShrt, 0, 37 ) . "..."
                              if ( length($loopTitleShrt) > 40 );
                            $cmd =~ s/%TITLESHRT%/$loopTitleShrt/gi;
                            $loopTitleShrt =~ s/ /_/;
                            $cmd =~ s/%TITLESHRT2%/$loopTitleShrt/gi;
                            $loopTitleShrt =~ s/^([\s\t ]*\w+).*/$1/g;
                            $loopTitleShrt =
                              substr( $loopTitleShrt, 0, 17 ) . "..."
                              if ( length($loopTitleShrt) > 20 );
                            $cmd =~ s/%TITLESHRT3%/$loopTitleShrt/gi;

                            my $deviceName = AttrVal(
                                $device,
                                AttrVal(
                                    $device,
                                    "rg_realname",
                                    AttrVal( $device, "rr_realname", "group" )
                                ),
                                AttrVal( $device, "alias", $device )
                            );
                            my $deviceName2 = $deviceName;
                            $deviceName2 =~ s/ /_/;

                            $cmd =~ s/%SOURCE%/$device/gi;
                            $cmd =~ s/%SRCALIAS%/$deviceName/gi;
                            $cmd =~ s/%SRCALIAS2%/$deviceName2/gi;

                            my $gatewayDevName = AttrVal(
                                $gatewayDev,
                                AttrVal(
                                    $gatewayDev,
                                    "rg_realname",
                                    AttrVal(
                                        $gatewayDev, "rr_realname", "group"
                                    )
                                ),
                                AttrVal( $gatewayDev, "alias", $gatewayDev )
                            );
                            my $gatewayDevName2 = $gatewayDevName;
                            $gatewayDevName2 =~ s/ /_/;

                            $cmd =~ s/%DEVICE%/$gatewayDev/gi;
                            $cmd =~ s/%DEVALIAS%/$gatewayDevName/gi;
                            $cmd =~ s/%DEVALIAS2%/$gatewayDevName2/gi;

                            my $loopMsgDateTime = $msgDateTime;
                            $loopMsgDateTime .= ".$sentCounter"
                              if ($sentCounter);
                            my $loopMsgDateTime2 = $loopMsgDateTime;
                            $loopMsgDateTime2 =~ s/ /_/;

                            $cmd =~ s/%MSGDATETIME%/$loopMsgDateTime/gi;
                            $cmd =~ s/%MSGDATETIME2%/$loopMsgDateTime2/gi;

                            my $subRecipientName =
                              $subRecipient eq ""
                              ? ""
                              : AttrVal(
                                $subRecipient,
                                AttrVal(
                                    $subRecipient,
                                    "rg_realname",
                                    AttrVal(
                                        $subRecipient, "rr_realname",
                                        "group"
                                    )
                                ),
                                AttrVal(
                                    $subRecipient, "alias", $subRecipient
                                )
                              );
                            my $subRecipientName2 = $subRecipientName;
                            $subRecipientName2 =~ s/ /_/;

                            $cmd =~ s/%RECIPIENT%/$subRecipient/gi
                              if ( $subRecipient ne "" );
                            $cmd =~ s/%RCPTNAME%/$subRecipientName/gi
                              if ( $subRecipientName ne "" );
                            $cmd =~ s/%RCPTNAME2%/$subRecipientName2/gi
                              if ( $subRecipientName2 ne "" );
                            $cmd =~ s/%TERMINAL%/$termRecipient/gi
                              if ( $termRecipient ne "" );

                            my $paramsA;

                            unless ( defined($testMode) && $testMode eq "1" ) {

                                # user parameters from message
                                if ( ref($params) eq "HASH" ) {
                                    for my $key ( keys %$params ) {
                                        next if ( ref( $params->{$key} ) );
                                        my $val = $params->{$key};
                                        $cmd =~ s/%$key%/$val/gi;
                                        $cmd =~ s/\$$key/$val/g;
                                        Log3 $logDevice, 5,
                                          "msg $device: User parameters: "
                                          . "replacing %$key% and \$$key by '$val'";
                                    }
                                }

                                # user parameters from attributes
                                my $paramsAttr1 =
                                  AttrVal( $gatewayDev,
                                    "msgParams$typeUc$priorityCat", undef );
                                my $paramsAttr2 =
                                  AttrVal( $gatewayDev, "msgParams$typeUc",
                                    undef );
                                my $paramsAttr3 =
                                  AttrVal( $gatewayDev, "msgParams", undef );
                                my $paramsAttr4 =
                                  MSG_FindAttrVal( $device,
                                    "msgParams$typeUc$priorityCat",
                                    $typeUc, undef );
                                my $paramsAttr5 =
                                  MSG_FindAttrVal( $device, "msgParams$typeUc",
                                    $typeUc, undef );
                                my $paramsAttr6 =
                                  MSG_FindAttrVal( $device, "msgParams",
                                    $typeUc, undef );

                                foreach (
                                    $paramsAttr1, $paramsAttr2, $paramsAttr3,
                                    $paramsAttr4, $paramsAttr5, $paramsAttr6
                                  )
                                {
                                    next unless ($_);
                                    if (   $_ =~ m/^{.*}$/s
                                        && $_ =~ m/=>/
                                        && $_ !~ m/\$/ )
                                    {
                                        my $av = eval $_;
                                        if ($@) {
                                            Log3 $logDevice, 3,
                                              "msg $device: "
                                              . "ERROR while reading attribute msgParams";
                                        }
                                        else {
                                            $paramsA = $av;
                                        }
                                    }
                                    else {
                                        my ( $a, $h ) = parseParams($_);
                                        $paramsA = $h;
                                    }

                                    next unless ref($paramsA) eq "HASH";

                                    if ( ref($paramsA) eq "HASH" ) {
                                        for my $key ( keys %$paramsA ) {
                                            next if ( ref( $params->{$key} ) );
                                            my $val = $paramsA->{$key};
                                            $cmd =~ s/%$key%/$val/gi;
                                            $cmd =~ s/\$$key/$val/g;
                                            Log3 $logDevice, 5,
                                              "msg $device: "
                                              . "msgParams: replacing %$key% and \$$key by '$val'";
                                        }
                                    }
                                }

                                # user parameters from command schema hash
                                if (
                                    $priorityCat ne ""
                                    && defined(
                                        $cmdSchema->{ $type[$i] }{$gatewayType}
                                          {defaultValues}{$priorityCat}
                                    )
                                  )
                                {

                                    for my $item (
                                        $cmdSchema->{ $type[$i] }{$gatewayType}
                                        {defaultValues}{$priorityCat} )
                                    {
                                        for my $key ( keys(%$item) ) {
                                            my $val = $item->{$key};
                                            $cmd =~ s/%$key%/$val/gi;
                                            $cmd =~ s/\$$key/$val/g;
                                            Log3 $logDevice, 5,
                                              "msg $device: "
                                              . "msgSchema: replacing %$key% and \$$key by '$val'";
                                        }
                                    }

                                }
                                elsif (
                                    $priorityCat eq ""
                                    && defined(
                                        $cmdSchema->{ $type[$i] }{$gatewayType}
                                          {defaultValues}{Normal}
                                    )
                                  )
                                {

                                    for my $item (
                                        $cmdSchema->{ $type[$i] }{$gatewayType}
                                        {defaultValues}{Normal} )
                                    {
                                        for my $key ( keys(%$item) ) {
                                            my $val = $item->{$key};
                                            $cmd =~ s/%$key%/$val/gi;
                                            $cmd =~ s/\$$key/$val/g;
                                            Log3 $logDevice, 5,
                                              "msg $device: "
                                              . "msgSchema: replacing %$key% and \$$key by '$val'";
                                        }
                                    }

                                }

                            }

                            $sentCounter++;

                            if ( $routeStatus =~ /^OK\w*/ ) {

                                my $error = 0;

                                unless ( defined($testMode)
                                    && $testMode eq "1" )
                                {

                                    # ReplaceSetMagic
                                    #
                                    if ( $featurelevel >= 5.7
                                        && !$replaceError )
                                    {
                                        my %dummy;
                                        my ( $err, @a ) =
                                          ReplaceSetMagic( \%dummy, 0, ($cmd) );
                                        $replaceError .=
                                            "ReplaceSetMagic failed for CMD: "
                                          . "$err\n"
                                          if ($err);
                                        $cmd = join( " ", @a )
                                          unless ($err);
                                    }

                                    # add user parameters
                                    # if gateway supports parseParams
                                    my $gatewayDevType = GetType($gatewayDev);
                                    if (
                                           $gatewayDevType
                                        && ref($params) eq "HASH"
                                        && ( $modules{$gatewayDevType}
                                            ->{parseParams}
                                            || $modules{$gatewayDevType}
                                            ->{msgParams}{parseParams}
                                            || $modules{$gatewayDevType}
                                            ->{'.msgParams'}{parseParams} )
                                      )
                                    {
                                        Log3 $logDevice, 5,
                                          "msg $device: "
                                          . "parseParams support: Handing over user parameters to other device";

                                        my ( $a, $h ) = parseParams($cmd);

                                        keys %$params;
                                        while ( ( my $key, my $value ) =
                                            each %$params )
                                        {
                                            # Compatibility to legacy schema:
                                            # lowercase after _
                                            my $s = $gatewayDevType
                                              . "[\_\/-]([A-Z0-9_-]+)";
                                            $key =~ s/^$s$/\L$1/;

                                            # remove gateway TYPE when
                                            # used as prefix
                                            $s = $gatewayDevType . "[_\/-]";
                                            $key =~ s/^$s//;
                                            $cmd .= " $key='$value'"
                                              if ( !defined( $h->{$key} )
                                                || $h->{$key} =~
                                                m/^[\s\t\n ]*$/ );
                                        }

                                        keys %$paramsA;
                                        while ( ( my $key, my $value ) =
                                            each %$paramsA )
                                        {
                                            # Compatibility to legacy schema:
                                            # lowercase after _
                                            my $s = $gatewayDevType
                                              . "[\_\/-]([A-Z0-9_-]+)";
                                            $key =~ s/^$s$/\L$1/;

                                            # remove gateway TYPE when
                                            # used as prefix
                                            $s = $gatewayDevType . "[_\/-]";
                                            $key =~ s/^$s//;
                                            $cmd .= " $key='$value'"
                                              if ( !defined( $h->{$key} )
                                                || $h->{$key} =~
                                                m/^[\s\t\n ]*$/ );
                                        }

                                    }

                                    # excplicitly queue message
                                    if ( $routeStatus eq "OK_QUEUE" ) {
                                        $queued = msgConfig_QueueAdd(
                                            $msgA,          $params,
                                            $msgDateTime,   $msgID,
                                            $sentCounter,   $type[$i],
                                            $device,        $subRecipient,
                                            $termRecipient, $priority,
                                            $loopTitle,     $loopMsg
                                        ) ? 1 : 0;
                                    }

                                    # run command
                                    elsif ($replaceError) {
                                        $error = 2;
                                        $loopReturn3 .= $replaceError;
                                    }
                                    elsif ( $cmd =~ /^\s*\{.*\}\s*$/ ) {
                                        Log3 $logDevice, 5,
                                          "msg $device: "
                                          . "$type[$i] route command (Perl): $cmd";
                                        eval $cmd;
                                        unless ( !$@ || $@ =~ m/^[\s\t\n ]*$/ )
                                        {
                                            $error = 1;
                                            $loopReturn3 .= "$gatewayDev: $@\n";
                                        }
                                    }
                                    else {
                                        Log3 $logDevice, 5,
                                          "msg $device: "
                                          . "$type[$i] route command (fhem): $cmd";
                                        my $ret = fhem $cmd, 1;
                                        unless ( !$ret
                                            || $ret =~ m/^[\s\t\n ]*$/ )
                                        {
                                            $error = 1;
                                            $loopReturn3 .=
                                              "$gatewayDev: $ret\n";
                                        }
                                    }

                                    $routeStatus = "ERROR"
                                      if ( $error == 1 );
                                    $routeStatus = "ERROR_EVAL"
                                      if ( $error == 2 );

                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "RECIPIENT=$subRecipient "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority($priorityCat) "
                                      . "TITLE='$loopTitle' "
                                      . "MSG='$loopMsg'"
                                      if ( $priorityCat ne ""
                                        && $subRecipient ne "" );
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "RECIPIENT=$subRecipient "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' "
                                      . "MSG='$loopMsg'"
                                      if ( $priorityCat eq ""
                                        && $subRecipient ne "" );
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority($priorityCat) "
                                      . "TITLE='$loopTitle' "
                                      . "MSG='$loopMsg'"
                                      if ( $priorityCat ne ""
                                        && $subRecipient eq "" );
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' "
                                      . "MSG='$loopMsg'"
                                      if ( $priorityCat eq ""
                                        && $subRecipient eq "" );

                                }

                                $msgSent    = 1 if ( $error == 0 );
                                $msgSentDev = 1 if ( $error == 0 );

                                if ( $subRecipient ne "" ) {
                                    $gatewaysStatus{"$gatewayDev:$subRecipient"}
                                      = $routeStatus
                                      if ( $globalDevName ne $gatewayDev );
                                    $gatewaysStatus{"$device:$subRecipient"} =
                                      $routeStatus
                                      if ( $globalDevName eq $gatewayDev );
                                }
                                else {
                                    $gatewaysStatus{$gatewayDev} = $routeStatus
                                      if ( $globalDevName ne $gatewayDev );
                                    $gatewaysStatus{$device} = $routeStatus
                                      if ( $globalDevName eq $gatewayDev );
                                }
                            }

                            elsif ( $routeStatus =~ /\+QUEUE/ || $forceQueue ) {
                                unless ( defined($testMode)
                                    && $testMode eq "1" )
                                {
                                    if ( !( grep { "queue" eq $_ } @type ) ) {
                                        $queued = msgConfig_QueueAdd(
                                            $msgA,          $params,
                                            $msgDateTime,   $msgID,
                                            $sentCounter,   $type[$i],
                                            $device,        $subRecipient,
                                            $termRecipient, $priority,
                                            $loopTitle,     $loopMsg
                                        ) ? 1 : 0;
                                    }

                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "RECIPIENT=$subRecipient "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' '$loopMsg'"
                                      if ( $subRecipient ne "" );
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' '$loopMsg'"
                                      if ( $subRecipient eq "" );
                                }

                                $msgSent    = 3 if ( $msgSent != 1 );
                                $msgSentDev = 3 if ( $msgSentDev != 1 );

                                $gatewaysStatus{$gatewayDev} = $routeStatus
                                  if ( $globalDevName ne $gatewayDev );
                                $gatewaysStatus{$device} = $routeStatus
                                  if ( $globalDevName eq $gatewayDev );
                            }

                            elsif ($routeStatus eq "UNAVAILABLE"
                                || $routeStatus eq "UNDEFINED" )
                            {
                                unless ( defined($testMode)
                                    && $testMode eq "1" )
                                {
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "RECIPIENT=$subRecipient "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' '$loopMsg'"
                                      if ( $subRecipient ne "" );
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' '$loopMsg'"
                                      if ( $subRecipient eq "" );
                                }

                                $gatewaysStatus{$gatewayDev} = $routeStatus
                                  if ( $globalDevName ne $gatewayDev );
                                $gatewaysStatus{$device} = $routeStatus
                                  if ( $globalDevName eq $gatewayDev );
                            }

                            else {
                                unless ( defined($testMode)
                                    && $testMode eq "1" )
                                {
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "RECIPIENT=$subRecipient "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' '$loopMsg'"
                                      if ( $subRecipient ne "" );
                                    Log3 $logDevice, 3,
                                        "msg $device: "
                                      . "ID=$msgID.$sentCounter "
                                      . "TYPE=$type[$i] "
                                      . "ROUTE=$gatewayDev "
                                      . "STATUS=$routeStatus "
                                      . "PRIORITY=$loopPriority "
                                      . "TITLE='$loopTitle' '$loopMsg'"
                                      if ( $subRecipient eq "" );
                                }

                                $msgSent    = 2 if ( $msgSent != 1 );
                                $msgSentDev = 2 if ( $msgSentDev != 1 );

                                $gatewaysStatus{$gatewayDev} = $routeStatus
                                  if ( $globalDevName ne $gatewayDev );
                                $gatewaysStatus{$device} = $routeStatus
                                  if ( $globalDevName eq $gatewayDev );
                            }

                        }

                        last if ( $msgSentDev == 1 || $msgSentDev == 3 );
                    }

                    #####################
                    # return if we are in routing target test mode
                    #
                    if ( defined($testMode) && $testMode eq "1" ) {
                        Log3 $logDevice, 5,
                          "msg $device:		"
                          . "$type[$i] route check result: ROUTE_AVAILABLE"
                          if ( $loopReturn3 eq "" );
                        Log3 $logDevice, 5,
                          "msg $device:		"
                          . "$type[$i] route check result: ROUTE_UNAVAILABLE"
                          if ( $loopReturn3 ne "" );
                        return "ROUTE_AVAILABLE"   if ( $loopReturn3 eq "" );
                        return "ROUTE_UNAVAILABLE" if ( $loopReturn3 ne "" );
                    }

                    if ( $catchall == 0 ) {
                        if ( !defined( $sentTypesPerDevice{$device} ) ) {
                            $sentTypesPerDevice{$device} = "";
                        }
                        else {
                            $sentTypesPerDevice{$device} .= " ";
                        }

                        $sentTypesPerDevice{$device} .=
                          $type[$i] . ":" . $msgSentDev;
                    }
                    else {
                        if ( !defined( $sentTypesPerDevice{$device} ) ) {
                            $sentTypesPerDevice{$globalDevName} = "";
                        }
                        else {
                            $sentTypesPerDevice{$globalDevName} .= " ";
                        }

                        $sentTypesPerDevice{$globalDevName} .=
                          $type[$i] . ":" . $msgSentDev;
                    }

                    # update device readings
                    my $readingsDev = $defs{$device};
                    $readingsDev = $defs{$globalDevName}
                      if ( $catchall == 1 || $deviceType eq "email" );
                    readingsBeginUpdate($readingsDev);

                    readingsBulkUpdate( $readingsDev, "fhemMsg" . $typeUc,
                        $msg );
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "Title", $title );
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "Prio",
                        $loopPriority );

                    my $gwStates = "-";

                    keys %gatewaysStatus;
                    while ( ( my $gwName, my $gwState ) = each %gatewaysStatus )
                    {
                        $gwStates = "" if $gwStates eq "-";
                        $gwStates .= " " if $gwStates ne "-";
                        $gwStates .= "$gwName:$gwState";
                    }
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "Gw", $gwStates );
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "State", $msgSentDev );

                    # suppress errors when there are still alternatives
                    if (   $hasTypeOr == 1
                        && $isTypeOr < scalar( grep { defined $_ } @typesOr ) )
                    {
                        $loopReturn3 = "";
                    }

                    ################################################################
                    ### Implicit forwards based on priority or presence
                    ###

                    # Skip if typeOr is defined
                    # and this is not the last type entry
                    if (   $msgSentDev != 3
                        && $msgSentDev != 1
                        && $hasTypeOr == 1
                        && $isTypeOr < scalar( grep { defined $_ } @typesOr ) )
                    {
                        Log3 $logDevice, 4,
                          "msg $device: "
                          . "Skipping implicit forward due to typesOr definition";

                        # remove recipient from list to avoid
                        # other interaction when using recipientOr in parallel
                        if (   $hasRecipientOr == 1
                            && $isRecipientOr <
                            scalar( grep { defined $_ } @recipientsOr ) )
                        {
                            my $regex1 =
                              "\\s*!?@?" . $device . "[,|]";  # at the beginning
                            my $regex2 =
                              "[,|]!?@?" . $device . "\\s*";    # at the end
                            my $regex3 =
                                ",!?@?"
                              . $device
                              . ",";    # in the middle with comma
                            my $regex4 =
                                "[\|,]!?@?"
                              . $device
                              . "[\|,]";  # in the middle with pipe and/or comma

                            $recipients =~ s/^$regex1//;
                            $recipients =~ s/$regex2$/|/gi;
                            $recipients =~ s/$regex3/,/gi;
                            $recipients =~ s/$regex4/|/gi;
                        }

                    }

                    # Skip if recipientOr is defined
                    # and this is not the last device entry
                    if (   $msgSentDev != 3
                        && $msgSentDev != 1
                        && $hasRecipientOr == 1
                        && $isRecipientOr <
                        scalar( grep { defined $_ } @recipientsOr ) )
                    {
                        Log3 $logDevice, 4,
                          "msg $device: "
                          . "Skipping implicit forward due to recipientOr definition";
                    }

                    # Skip if softFail
                    elsif ( $msgSentDev != 3 && $msgSentDev != 1 && $softFail )
                    {
                        Log3 $logDevice, 4,
                          "msg $device: Skipping implicit forward";
                        $loopReturn3 = "";
                    }

                    # priority forward thresholds
                    #

                    ### emergency
                    my $msgFwPrioEmergency =
                      MSG_FindAttrVal( $device, "msgFwPrioEmergency$typeUc",
                        $typeUc, 2 );

                    ### absent
                    my $msgFwPrioAbsent =
                      MSG_FindAttrVal( $device, "msgFwPrioAbsent$typeUc",
                        $typeUc, 0 );

                    ### gone
                    my $msgFwPrioGone =
                      MSG_FindAttrVal( $device, "msgFwPrioGone$typeUc",
                        $typeUc, 1 );

                    my $fw_gwUnavailable =
                      defined(
                        $settings->{ $type[$i] }{typeEscalation}{gwUnavailable}
                      )
                      ? $settings->{ $type[$i] }{typeEscalation}{gwUnavailable}
                      : "";
                    my $fw_emergency =
                      defined(
                        $settings->{ $type[$i] }{typeEscalation}{emergency} )
                      ? $settings->{ $type[$i] }{typeEscalation}{emergency}
                      : "";
                    my $fw_residentAbsent =
                      defined(
                        $settings->{ $type[$i] }{typeEscalation}{residentAbsent}
                      )
                      ? $settings->{ $type[$i] }{typeEscalation}{residentAbsent}
                      : "";
                    my $fw_residentGone =
                      defined(
                        $settings->{ $type[$i] }{typeEscalation}{residentGone} )
                      ? $settings->{ $type[$i] }{typeEscalation}{residentGone}
                      : "";

                    # Forward message
                    # if no gateway device for this type was available
                    if (   $msgSentDev == 0
                        && $fw_gwUnavailable ne ""
                        && !( grep { $fw_gwUnavailable eq $_ } @type )
                        && $routes{$fw_gwUnavailable} == 1 )
                    {
                        Log3 $logDevice, 4,
                            "msg $device: "
                          . "Implicit forwards: No $type[$i] gateway device available for recipient $device ($gatewayDevs). Trying alternative message type "
                          . $fw_gwUnavailable;

                        push @type, $fw_gwUnavailable;
                        $forwarded .= "," if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_gwUnavailable;
                    }

                    # Forward message
                    # if emergency priority
                    if (   $loopPriority >= $msgFwPrioEmergency
                        && $fw_emergency ne ""
                        && !( grep { $fw_emergency eq $_ } @type )
                        && $routes{$fw_emergency} == 1 )
                    {
                        Log3 $logDevice, 4,
                            "msg $device: "
                          . "Implicit forwards: Escalating high priority $type[$i] message via "
                          . $fw_emergency;

                        push @type, $fw_emergency;
                        $forwarded .= "," if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_emergency;
                    }

                    # Forward message
                    # if high priority and residents are
                    # constantly not at home
                    if (   $residentDevPresence eq "absent"
                        && $loopPriority >= $msgFwPrioGone
                        && $fw_residentGone ne ""
                        && !( grep { $fw_residentGone eq $_ } @type )
                        && $routes{$fw_residentGone} == 1 )
                    {
                        Log3 $logDevice, 4,
                            "msg $device: "
                          . "Implicit forwards: Escalating high priority $type[$i] message via "
                          . $fw_residentGone;

                        push @type, $fw_residentGone;
                        $forwarded .= "," if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_residentGone;
                    }

                    # Forward message
                    # if priority is normal or higher and residents
                    # are not at home but nearby
                    if (  !$forceQueue
                        && $residentDevState eq "absent"
                        && $loopPriority >= $msgFwPrioAbsent
                        && $fw_residentAbsent ne ""
                        && !( grep { $fw_residentAbsent eq $_ } @type )
                        && $routes{$fw_residentAbsent} == 1 )
                    {
                        Log3 $logDevice, 4,
                            "msg $device: "
                          . "Implicit forwards: Escalating $type[$i] message via "
                          . $fw_residentAbsent
                          . " due to absence";

                        push @type, $fw_residentAbsent;
                        $forwarded .= "," if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_residentAbsent;
                    }

                }

                $loopReturn2 .= $loopReturn3 unless ($softFail);
                last if ( $msgSent == 1 );

                $isTypeOr++;
            }

            $loopReturn1 .= $loopReturn2;
        }

        $return .= $loopReturn1;
        last if ( $msgSent == 1 );

        $isRecipientOr++;
    }

    # finalize device readings
    keys %sentTypesPerDevice;
    while ( ( my $device, my $types ) = each %sentTypesPerDevice ) {
        $device = $globalDevName
          if ( $device =~ /^(([A-Za-z0-9%+._-])+@+([%+a-z0-9A-Z.-]*))$/ );

        readingsBulkUpdate( $defs{$device}, "fhemMsgStateTypes", $types )
          if ( $forwarded eq "" );
        readingsBulkUpdate( $defs{$device}, "fhemMsgStateTypes",
            $types . " forwards:" . $forwarded )
          if ( $forwarded ne "" );
        readingsBulkUpdate( $defs{$device}, "fhemMsgState", $msgSent );
        readingsEndUpdate( $defs{$device}, 1 );
    }

    $return .= "However, message was still sent to some recipients!"
      if ( $msgSent == 1 && $return ne "" );

    $return .=
      "FATAL ERROR: Message NOT sent. No gateway device was available."
      if ( !$softFail && $msgSent == 2 );

    return $return;
}

1;

=pod
=item command
=item summary dynamic routing of messages to FHEM devices and modules
=item summary_DE dynamisches Routing f&uuml;r Nachrichten an FHEM Ger&auml;te und Module
=begin html

<a name="MSG"></a>
<h3>msg</h3>
<ul>
  <code>msg [&lt;type&gt;] [&lt;@device&gt;|&lt;e-mail address&gt;] [&lt;priority&gt;] [|&lt;title&gt;|] &lt;message&gt;</code>
  <br>
  <br>
  No documentation here yet, sorry.<br>
  <a href="http://forum.fhem.de/index.php/topic,39983.0.html">FHEM Forum</a>
</ul>

=end html
=begin html_DE

<a name="MSG"></a>
<h3>msg</h3>
<ul>
  <code>msg [&lt;type&gt;] [&lt;@device&gt;|&lt;e-mail address&gt;] [&lt;priority&gt;] [|&lt;title&gt;|] &lt;message&gt;</code>
  <br>
  <br>
  Bisher keine Dokumentation hier, sorry.<br>
  <a href="http://forum.fhem.de/index.php/topic,39983.0.html">FHEM Forum</a>
</ul>


=end html_DE
=cut

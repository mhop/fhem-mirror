# $Id$
##############################################################################
#
#     99_msg.pm
#     Dynamic message and notification routing for FHEM
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Version: 1.0.0
#
# Major Version History:
#
# - 1.0.0 - 2015-09-23
# -- First release
#
##############################################################################

package main;
use strict;
use warnings;
use Time::HiRes qw(time);

sub CommandMsg($$;$$);

########################################
sub msg_Initialize($$) {
    my %hash = (
        Fn => "CommandMsg",
        Hlp =>
"[<type>] [<\@device>|<e-mail address>] [<priority>] [|<title>|] <message>",
    );
    $cmds{msg} = \%hash;

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
      msgFwPrioAbsentAudio
      msgFwPrioAbsentLight
      msgFwPrioAbsentScreen
      msgFwPrioEmergencyAudio
      msgFwPrioEmergencyLight
      msgFwPrioEmergencyPush
      msgFwPrioEmergencyScreen
      msgFwPrioGoneAudio
      msgFwPrioGoneLight
      msgFwPrioGoneScreen
      msgLocationDevs
      msgPriorityAudio:-2,-1,0,1,2
      msgPriorityLight:-2,-1,0,1,2
      msgPriorityMail:-2,-1,0,1,2
      msgPriorityPush:-2,-1,0,1,2
      msgPriorityScreen:-2,-1,0,1,2
      msgPriorityText:-2,-1,0,1,2
      msgResidentsDev
      msgSwitcherDev
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

    );
    use warnings 'qw';
    $modules{Global}{AttrList} .= " " . join( " ", @attrList );

    # add global attributes
    foreach (
        "msgContactAudio",    "msgContactMail",   "msgContactPush",
        "msgContactScreen",   "msgContactLight",  "msgRecipient",
        "msgRecipientAudio",  "msgRecipientMail", "msgRecipientPush",
        "msgRecipientScreen", "msgRecipientText", "msgRecipientLight",
      )
    {
        addToAttrList($_);
    }
}

########################################
sub CommandMsg($$;$$) {
    my ( $cl, $msg, $testMode ) = @_;
    my $return = "";

    if ( $msg eq "" || $msg =~ /^\?[\s\t]*$/ || $msg eq "help" ) {
        return
"Usage: msg [<type>] [<\@device>|<e-mail address>] [<priority>] [|<title>|] <message>";
    }

    # default commands
    my %defaults;

    $defaults{audio}{Normal}    = "set \$DEVICE Speak 40 de |\$TITLE| \$MSG";
    $defaults{audio}{ShortPrio} = "set \$DEVICE Speak 30 de |\$TITLE| Achtung!";
    $defaults{audio}{Short}     = "set \$DEVICE Speak 30 de |\$TITLE|";

    $defaults{light}{Normal} =
"{my \$state=ReadingsVal(\"\$DEVICE\",\"state\",\"off\"); fhem \"set \$DEVICE blink 2 1\"; fhem \"sleep 4;set \$DEVICE:FILTER=state!=\$state \$state\"}";
    $defaults{light}{High} =
"{my \$state=ReadingsVal(\"\$DEVICE\",\"state\",\"off\"); fhem \"set \$DEVICE blink 10 1\"; fhem \"sleep 20;set \$DEVICE:FILTER=state!=\$state \$state\"}";
    $defaults{light}{Low} = "set \$DEVICE alert select";

    $defaults{mail}{Normal} =
"{system(\"echo '\$MSG' | /usr/bin/mail -s '\$TITLE' -t '\$RECIPIENT'\")}";
    $defaults{mail}{High} =
"{system(\"/bin/echo '\$MSG' | /usr/bin/mail -s '\$TITLE' -t '\$RECIPIENT' -a 'MIME-Version: 1.0' -a 'Content-Type: text/html; charset=UTF-8' -a 'X-Priority: 1 (Highest)' -a 'X-MSMail-Priority: High' -a 'Importance: high'\")}";
    $defaults{mail}{Low} =
"{system(\"/bin/echo '\$MSG' | /usr/bin/mail -s '\$TITLE' -t '\$RECIPIENT' -a 'MIME-Version: 1.0' -a 'Content-Type: text/html; charset=UTF-8' -a 'X-Priority: 5 (Lowest)' -a 'X-MSMail-Priority: Low' -a 'Importance: low'\")}";

    $defaults{push}{Normal} =
      "set \$DEVICE msg '\$TITLE' '\$MSG' '' \$PRIORITY ''";
    $defaults{push}{High} =
      "set \$DEVICE msg '\$TITLE' '\$MSG' '' \$PRIORITY '' 120 600";
    $defaults{push}{Low} =
      "set \$DEVICE msg '\$TITLE' '\$MSG' '' \$PRIORITY ''";

    $defaults{screen}{Normal} = "set \$DEVICE msg info 8 \$MSG";
    $defaults{screen}{High}   = "set \$DEVICE msg attention 12 \$MSG";
    $defaults{screen}{Low}    = "set \$DEVICE msg message 8 \$MSG";

    # default forwards
    my %forwards;
    $forwards{screen}{gwUnavailable} = "light";
    $forwards{light}{gwUnavailable}  = "audio";
    $forwards{audio}{gwUnavailable}  = "text";
    $forwards{push}{gwUnavailable}   = "mail";

    $forwards{screen}{emergency} = "light";
    $forwards{light}{emergency}  = "audio";
    $forwards{audio}{emergency}  = "text";
    $forwards{push}{emergency}   = "mail";

    $forwards{screen}{highPrio}{residentGone} = "light";
    $forwards{light}{highPrio}{residentGone}  = "audio";
    $forwards{audio}{highPrio}{residentGone}  = "text";

    $forwards{screen}{highPrio}{residentAbsent} = "light";
    $forwards{light}{highPrio}{residentAbsent}  = "audio";
    $forwards{audio}{highPrio}{residentAbsent}  = "text";

    ################################################################
    ### extract message details
    ###

    my $types      = "";
    my $recipients = "";
    my $priority   = "";
    my $title      = "";

    my $priorityCat = "";

    # check for message types
    if ( $msg =~
s/^[\s\t]*([a-z,]*!?(screen|light|audio|text|push|mail)[a-z,!|]*)[\s\t]+//
      )
    {
        $types = $1;
    }

    # check for given recipients
    if ( $msg =~
s/^[\s\t]*([!]?(([A-Za-z0-9%+._-])*@([%+a-z0-9A-Z.-]+))[\w,@.!|]*)[\s\t]+//
      )
    {
        $recipients = $1;
    }

    # check for given priority
    if ( $msg =~ s/^[\s\t]*([-+]{0,1}\d+[.\d]*)[\s\t]*// ) {
        $priority = $1;
    }

    # check for given message title
    if ( $msg =~
s/^[\s\t]*\|([\w\süöäß^°!"§$%&\/\\()<>=?´`"+\[\]#*@€]+)\|[\s\t]+//
      )
    {
        $title = $1;
    }

    ################################################################
    ### command queue
    ###

    $types = "text"
      if ( $types eq "" );
    my $messageSent = 0;
    my $forwarded   = "";
    my %sentTypesPerDevice;
    my $sentCounter    = 0;
    my $messageID      = time();
    my $isTypeOr       = 1;
    my $isRecipientOr  = 1;
    my $hasTypeOr      = 0;
    my $hasRecipientOr = 0;
    $recipients = "\@global" if ( $recipients eq "" );

    my @typesOr = split( /\|/, $types );
    $hasTypeOr = 1 if ( scalar( grep { defined $_ } @typesOr ) > 1 );
    Log3 "global", 5,
      "msg: typeOr total is " . scalar( grep { defined $_ } @typesOr )
      if ( $testMode ne "1" );

    for (
        my $iTypesOr = 0 ;
        $iTypesOr < scalar( grep { defined $_ } @typesOr ) ;
        $iTypesOr++
      )
    {
        Log3 "global", 5,
          "msg: start typeOr loop for type(s) $typesOr[$iTypesOr]"
          if ( $testMode ne "1" );

        my @type = split( /,/, $typesOr[$iTypesOr] );
        for ( my $i = 0 ; $i < scalar( grep { defined $_ } @type ) ; $i++ ) {
            Log3 "global", 5, "msg: running loop for type $type[$i]"
              if ( $testMode ne "1" );
            last if ( !defined( $type[$i] ) );

            my $forceType = 0;
            if ( $type[$i] =~ s/^!(.*)// ) {
                $type[$i] = $1;
                $forceType = 1;
            }

            # check for correct type
            my @msgCmds =
              ( "screen", "light", "audio", "text", "push", "mail" );
            if ( !( $type[$i] ~~ @msgCmds ) ) {
                $return .= "Unknown message type $type[$i]\n";
                next;
            }

            ################################################################
            ### recipient loop
            ###

            my @recipientsOr = split( /\|/, $recipients );
            $hasRecipientOr = 1
              if ( scalar( grep { defined $_ } @recipientsOr ) > 1 );
            Log3 "global", 5,
              "msg: recipientOr total is "
              . scalar( grep { defined $_ } @recipientsOr )
              if ( $testMode ne "1" );

            for (
                my $iRecipOr = 0 ;
                $iRecipOr < scalar( grep { defined $_ } @recipientsOr ) ;
                $iRecipOr++
              )
            {
                Log3 "global", 5,
"msg: start recipientsOr loop for recipient(s) $recipientsOr[$iRecipOr]"
                  if ( $testMode ne "1" );

                my @recipient = split( /,/, $recipientsOr[$iRecipOr] );
                foreach my $device (@recipient) {

                    Log3 "global", 5, "msg: running loop for device $device"
                      if ( $testMode ne "1" );

                    my $messageSentDev = 0;
                    my $gatewayDevs    = "";
                    my $forceDevice    = 0;

                    # for device type
                    my $deviceType = "device";
                    if ( $device =~
                        /^(([A-Za-z0-9%+._-])+[@]+([%+a-z0-9A-Z.-]*))$/ )
                    {
                        $gatewayDevs = $1;
                        $deviceType  = "email";
                    }
                    elsif ( $device =~ s/^!@?(.*)// ) {
                        $device      = $1;
                        $forceDevice = 1;
                    }
                    elsif ( $device =~ s/^@(.*)// ) {
                        $device = $1;
                    }

                    # FATAL ERROR: device does not exist
                    if ( !defined( $defs{$device} )
                        && $deviceType eq "device" )
                    {
                        $return .= "Device $device does not exist\n";
                        Log3 "global", 5, "msg $device: Device does not exist"
                          if ( $testMode ne "1" );

                        my $regex1 =
                          "\s*!?@?" . $device . "[,|]";    # at the beginning
                        my $regex2 = "[,|]!?@?" . $device . "\s*";  # at the end
                        my $regex3 =
                          ",!?@?" . $device . ",";    # in the middle with comma
                        my $regex4 =
                            "[\|,]!?@?"
                          . $device
                          . "[\|,]";    # in the middle with pipe and/or comma

                        $recipients =~ s/^$regex1//;
                        $recipients =~ s/$regex2$/|/g;
                        $recipients =~ s/$regex3/,/g;
                        $recipients =~ s/$regex4/|/g;

                        next;
                    }

                    my $typeUc      = ucfirst( $type[$i] );
                    my $catchall    = 0;
                    my $useLocation = 0;

                    my $logDevice;
                    $logDevice = "global";
                    $logDevice = $device
                      if (
                        # look for direct
                        AttrVal(
                            $device, "verbose",

                            #look for indirect
                            AttrVal(
                                AttrVal( $device, "msgRecipient$typeUc", "" ),
                                "verbose",

                                #look for indirect general
                                AttrVal(
                                    AttrVal( $device, "msgRecipient", "" ),
                                    "verbose",

                                    # no verbose found
                                    ""
                                )
                            )
                        ) ne ""
                      );

                    ################################################################
                    ### get target information from device location
                    ###

                    # search for location references
                    my @locationDevs;
                    @locationDevs = split(
                        /,/,

                        # look for direct
                        AttrVal(
                            $device, "msgLocationDevs",

                            #look for indirect
                            AttrVal(
                                AttrVal( $device, "msgRecipient$typeUc", "" ),
                                "msgLocationDevs",

                                # look for indirect general
                                AttrVal(
                                    AttrVal( $device, "msgRecipient", "" ),
                                    "msgLocationDevs",

                                    # look for global direct
                                    AttrVal(
                                        "global", "msgLocationDevs",

                                        #look for global indirect
                                        AttrVal(
                                            AttrVal(
                                                "global",
                                                "msgRecipient$typeUc", ""
                                            ),
                                            "msgLocationDevs",

                                            # look for global indirect general
                                            AttrVal(
                                                AttrVal(
                                                    "global", "msgRecipient",
                                                    ""
                                                ),
                                                "msgLocationDevs",

                                                # no locations defined
                                                ""
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    );

                    if ( $deviceType eq "device" ) {

                        # get device location
                        my $deviceLocation =

                          # look for direct
                          ReadingsVal(
                            $device, "location",

                            # look for indirect
                            ReadingsVal(
                                AttrVal( $device, "msgRecipient$typeUc", "" ),
                                "location",

                                # look for indirect general
                                ReadingsVal(
                                    AttrVal( $device, "msgRecipient", "" ),
                                    "location",

                                    # no location found
                                    ""
                                )
                            )
                          );

                        my $locationDev = "";
                        if ( $deviceLocation ne "" ) {

                            # lookup matching location
                            foreach (@locationDevs) {
                                my $lName =
                                  AttrVal( $_, "msgLocationName", "" );
                                if ( $lName ne "" && $lName eq $deviceLocation )
                                {
                                    $locationDev = $_;
                                    last;
                                }
                            }

                            # look for gateway device
                            $gatewayDevs =

                              # look for direct
                              AttrVal(
                                $locationDev, "msgContact$typeUc",

                                # look for indirect
                                AttrVal(
                                    AttrVal(
                                        $locationDev, "msgRecipient$typeUc",
                                        ""
                                    ),
                                    "msgContact$typeUc",

                                    # look for indirect general
                                    AttrVal(
                                        AttrVal(
                                            $locationDev, "msgRecipient",
                                            ""
                                        ),
                                        "msgContact$typeUc",

                                        # no contact found
                                        ""
                                    )
                                )
                              );

                            # at least one of the location gateways needs to
                            # be available. Otherwise we fall back to
                            # non-location contacts
                            if ( $gatewayDevs ne "" ) {

                                foreach
                                  my $gatewayDevOr ( split /\|/, $gatewayDevs )
                                {

                                    foreach my $gatewayDev ( split /,/,
                                        $gatewayDevOr )
                                    {

                                        if (   $type[$i] ne "mail"
                                            && !defined( $defs{$gatewayDev} )
                                            && $deviceType eq "device" )
                                        {
                                            $useLocation = 2
                                              if ( $useLocation == 0 );
                                        }
                                        elsif (
                                            $type[$i] ne "mail"
                                            && AttrVal( $gatewayDev, "disable",
                                                "0" ) eq "1"
                                          )
                                        {
                                            $useLocation = 2
                                              if ( $useLocation == 0 );
                                        }
                                        elsif (
                                            $type[$i] ne "mail"
                                            && (
                                                AttrVal(
                                                    $gatewayDev, "disable",
                                                    "0"
                                                ) eq "1"
                                                || ReadingsVal(
                                                    $gatewayDev, "power",
                                                    "on"
                                                ) eq "off"
                                                || ReadingsVal(
                                                    $gatewayDev, "presence",
                                                    "present"
                                                ) eq "absent"
                                                || ReadingsVal(
                                                    $gatewayDev, "presence",
                                                    "appeared"
                                                ) eq "disappeared"
                                                || ReadingsVal(
                                                    $gatewayDev, "state",
                                                    "present"
                                                ) eq "absent"
                                                || ReadingsVal(
                                                    $gatewayDev, "state",
                                                    "connected"
                                                ) eq "unauthorized"
                                                || ReadingsVal(
                                                    $gatewayDev, "state",
                                                    "connected"
                                                ) eq "disconnected"
                                                || ReadingsVal(
                                                    $gatewayDev, "state",
                                                    "reachable"
                                                ) eq "unreachable"
                                                || ReadingsVal(
                                                    $gatewayDev, "available",
                                                    "1"
                                                ) eq "0"
                                                || ReadingsVal(
                                                    $gatewayDev, "available",
                                                    "yes"
                                                ) eq "no"
                                                || ReadingsVal(
                                                    $gatewayDev, "reachable",
                                                    "1"
                                                ) eq "0"
                                                || ReadingsVal(
                                                    $gatewayDev, "reachable",
                                                    "yes"
                                                ) eq "no"
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
                                    Log3 $logDevice, 4,
"msg $device: Matching location definition found.";
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

                    if (
                           $gatewayDevs eq ""
                        && defined( $defs{$device} )
                        && (
                            $type[$i] eq "screen"
                            && (   $defs{$device}{TYPE} eq "ENIGMA2"
                                || $defs{$device}{TYPE} eq "STV" )

                            || (   $type[$i] eq "light"
                                && $defs{$device}{TYPE} eq "HUEDevice" )

                            || (
                                $type[$i] eq "audio"
                                && (
                                       $defs{$device}{TYPE} eq "SONOSPLAYER"
                                    || $defs{$device}{TYPE} eq "SB_PLAYER"
                                    || $defs{$device}{TYPE} eq "Text2Speech"
                                    || ( $defs{$device}{TYPE} eq "CUL_HM"
                                        && AttrVal( $device, "model", "" ) eq
                                        "HM-OU-CFM-PI" )
                                )
                            )

                            || (
                                $type[$i] eq "push"
                                && (   $defs{$device}{TYPE} eq "PushNotifier"
                                    || $defs{$device}{TYPE} eq "Pushalot"
                                    || $defs{$device}{TYPE} eq "Pushbullet"
                                    || $defs{$device}{TYPE} eq "Pushover"
                                    || $defs{$device}{TYPE} eq "yowsup"
                                    || $defs{$device}{TYPE} eq "Jabber" )
                            )
                        )
                      )
                    {
                        Log3 $logDevice, 4,
"msg $device: This recipient seems to be a gateway device itself. Still checking for any delegates ...";

                        $gatewayDevs =

                          # look for direct
                          AttrVal(
                            $device,
                            "msgContact$typeUc",

                            # look for indirect
                            AttrVal(
                                AttrVal( $device, "msgRecipient$typeUc", "" ),
                                "msgContact$typeUc",

                                # look for indirect general
                                AttrVal(
                                    AttrVal( $device, "msgRecipient", "" ),
                                    "msgContact$typeUc",

                                    # self
                                    $device
                                )
                            )
                          );

                    }

                    ################################################################
                    ### get target information from device
                    ###

                    elsif ( $deviceType eq "device" && $gatewayDevs eq "" ) {

                        # look for gateway device
                        $gatewayDevs =

                          # look for direct
                          AttrVal(
                            $device, "msgContact$typeUc",

                            #look for indirect
                            AttrVal(
                                AttrVal( $device, "msgRecipient$typeUc", "" ),
                                "msgContact$typeUc",

                                #look for indirect general
                                AttrVal(
                                    AttrVal( $device, "msgRecipient", "" ),
                                    "msgContact$typeUc",

                                    # no contact found
                                    ""
                                )
                            )
                          );

                        # fallback/catchall
                        if ( $gatewayDevs eq "" ) {
                            $catchall = 1
                              if ( $device ne "global" );

                            Log3 $logDevice, 5,
"msg $device:			(No $typeUc contact defined, trying global instead)"
                              if ( $catchall == 1 );

                            $gatewayDevs =

                              # look for direct
                              AttrVal(
                                "global", "msgContact$typeUc",

                                #look for indirect
                                AttrVal(
                                    AttrVal(
                                        "global", "msgRecipient$typeUc", ""
                                    ),
                                    "msgContact$typeUc",

                                    #look for indirect general
                                    AttrVal(
                                        AttrVal( "global", "msgRecipient", "" ),
                                        "msgContact$typeUc",

                                        # no contact found
                                        ""
                                    )
                                )
                              );
                        }
                    }

                    # Find priority if none was explicitly specified
                    my $loopPriority = $priority;
                    $loopPriority =

                      # look for direct
                      AttrVal(
                        $device, "msgPriority$typeUc",

                        #look for indirect
                        AttrVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "msgPriority$typeUc",

                            #look for indirect general
                            AttrVal(
                                AttrVal( $device, "msgRecipient", "" ),
                                "msgPriority$typeUc",

                                # look for global direct
                                AttrVal(
                                    "global", "msgPriority$typeUc",

                                    #look for global indirect
                                    AttrVal(
                                        AttrVal(
                                            "global", "msgRecipient$typeUc",
                                            ""
                                        ),
                                        "msgPriority$typeUc",

                                        #look for global indirect general
                                        AttrVal(
                                            AttrVal(
                                                "global", "msgRecipient",
                                                ""
                                            ),
                                            "msgPriority$typeUc",

                                            # default
                                            0
                                        )
                                    )
                                )
                            )
                        )
                      ) if ( !$priority );

                    # check for available routes
                    #
                    my %routes;
                    $routes{screen} = 0;
                    $routes{light}  = 0;
                    $routes{audio}  = 0;
                    $routes{text}   = 0;
                    $routes{push}   = 0;
                    $routes{mail}   = 0;

                    if (
                        !defined($testMode)
                        || (   $testMode ne "1"
                            && $testMode ne "2" )
                      )
                    {
                        Log3 $logDevice, 5,
"msg $device: Checking for available routes (triggered by type $type[$i])";

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

                     # Decide push and/or e-mail destination based on priorities
                        if (   $loopPriority >= 2
                            && $routes{push} == 1
                            && $routes{mail} == 1 )
                        {
                            Log3 $logDevice, 4,
"msg $device: Text routing decision: push+mail(1)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push+mail";
                            push @type, "push" if !( "push" ~~ @type );
                            push @type, "mail" if !( "mail" ~~ @type );
                        }
                        elsif ($loopPriority >= 2
                            && $routes{push} == 1
                            && $routes{mail} == 0 )
                        {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: push(2)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push";
                            push @type, "push" if !( "push" ~~ @type );
                        }
                        elsif ($loopPriority >= 2
                            && $routes{push} == 0
                            && $routes{mail} == 1 )
                        {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: mail(3)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>mail";
                            push @type, "mail" if !( "mail" ~~ @type );
                        }
                        elsif ( $loopPriority >= -2 && $routes{push} == 1 ) {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: push(4)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push";
                            push @type, "push" if !( "push" ~~ @type );
                        }
                        elsif ( $loopPriority >= -2 && $routes{mail} == 1 ) {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: mail(5)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>mail";
                            push @type, "mail" if !( "mail" ~~ @type );
                        }
                        elsif ( $routes{mail} == 1 ) {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: mail(6)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>mail";
                            push @type, "mail" if !( "mail" ~~ @type );
                        }
                        elsif ( $routes{push} == 1 ) {
                            Log3 $logDevice, 4,
                              "msg $device: Text routing decision: push(7)";
                            $forwarded .= ","
                              if ( $forwarded ne "" );
                            $forwarded .= "text>push";
                            push @type, "push" if !( "push" ~~ @type );
                        }

                        # FATAL ERROR: routing decision failed
                        else {
                            Log3 $logDevice, 4,
"msg $device: Text routing FAILED - priority=$loopPriority push="
                              . $routes{push}
                              . " mail="
                              . $routes{mail};

                            $return .=
"ERROR: Could not find any Push or Mail contact for device $device - set attributes: msgContactPush | msgContactMail | msgContactText | msgRecipientPush | msgRecipientMail | msgRecipientText | msgRecipient\n";
                        }

                        next;
                    }

                    # FATAL ERROR: we could not find any targets for
                    # user specified device...
                    if (   $gatewayDevs eq ""
                        && $device ne "global" )
                    {
                        $return .=
"ERROR: Could not find any $typeUc contact for device $device - set attributes: msgContact$typeUc | msgRecipient$typeUc | msgRecipient\n";
                    }

                    # FATAL ERROR: we could not find any targets at all
                    elsif ( $gatewayDevs eq "" ) {
                        $return .=
"ERROR: No global $typeUc contact defined. Please specify a destination device or set global attributes: msgContact$typeUc | msgRecipient$typeUc | msgRecipient\n";
                    }

                    #####################
                    # return if we are in routing target test mode
                    #
                    if ( defined($testMode) && $testMode eq "1" ) {
                        Log3 $logDevice, 5,
"msg $device:		$type[$i] route check result: ROUTE_AVAILABLE"
                          if ( $return eq "" );
                        Log3 $logDevice, 5,
"msg $device:		$type[$i] route check result: ROUTE_UNAVAILABLE"
                          if ( $return ne "" );
                        return "ROUTE_AVAILABLE"   if ( $return eq "" );
                        return "ROUTE_UNAVAILABLE" if ( $return ne "" );
                    }

                    # user selected announcement state
                    my $annState = ReadingsVal(

                        # look for direct
                        AttrVal(
                            $device, "msgSwitcherDev",

                            #look for indirect audio
                            AttrVal(
                                AttrVal( $device, "msgRecipient$typeUc", "" ),
                                "msgSwitcherDev",

                                #look for indirect general
                                AttrVal(
                                    AttrVal( $device, "msgRecipient", "" ),
                                    "msgSwitcherDev",

                                    # look for global direct
                                    AttrVal(
                                        "global", "msgSwitcherDev",

                                        #look for global indirect audio
                                        AttrVal(
                                            AttrVal(
                                                "global",
                                                "msgRecipient$typeUc", ""
                                            ),
                                            "msgSwitcherDev",

                                            #look for global indirect general
                                            AttrVal(
                                                AttrVal(
                                                    "global", "msgRecipient",
                                                    ""
                                                ),
                                                "msgSwitcherDev",

                                                # default
                                                ""
                                            )
                                        )
                                    )
                                )
                            )
                        ),
                        "state",
                        "long"
                    );

                    if ( $type[$i] eq "audio" ) {
                        if (   $annState eq "long"
                            || $forceType == 1
                            || $forceDevice == 1
                            || $loopPriority >= 2 )
                        {
                            $priorityCat = "";
                        }
                        elsif ( $loopPriority >= 1 ) {
                            $priorityCat = "ShortPrio";
                        }
                        else {
                            $priorityCat = "Short";
                        }
                    }
                    else {
                        if ( $loopPriority >= 2 ) {
                            $priorityCat = "High";
                        }
                        elsif ( $loopPriority >= 0 ) {
                            $priorityCat = "";
                        }
                        else {
                            $priorityCat = "Low";
                        }
                    }

                    my $defTitle = "System Message";
                    $defTitle = "Announcement" if ( $type[$i] eq "audio" );
                    $defTitle = "Announcement" if ( $type[$i] eq "light" );
                    $defTitle = "Info"         if ( $type[$i] eq "screen" );

                    # use title from device, global or internal default
                    my $loopTitle;
                    $loopTitle = $title if ( $title ne "" );
                    $loopTitle =

                      # look for direct high
                      AttrVal(
                        $device, "msgTitle$typeUc$priorityCat",

                        # look for indirect high
                        AttrVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "msgTitle$typeUc$priorityCat",

                            #look for indirect general high
                            AttrVal(
                                AttrVal( $device, "msgRecipient", "" ),
                                "msgTitle$typeUc$priorityCat",

                                # look for global direct high
                                AttrVal(
                                    "global", "msgTitle$typeUc$priorityCat",

                                    # look for global indirect high
                                    AttrVal(
                                        AttrVal(
                                            "global", "msgRecipient$typeUc",
                                            ""
                                        ),
                                        "msgTitle$typeUc$priorityCat",

                                        #look for global indirect general high
                                        AttrVal(
                                            AttrVal(
                                                "global", "msgRecipient",
                                                ""
                                            ),
                                            "msgTitle$typeUc$priorityCat",

                                            # default
                                            $defTitle
                                        )
                                    )
                                )
                            )
                        )
                      ) if ( $title eq "" );

                    my $loopMsg = $msg;
                    if ( $catchall == 1 ) {
                        $loopTitle = "Fw: $loopTitle";
                        if ( $type[$i] eq "mail" ) {
                            $loopMsg .=
"\n\n-- \nMail forwarded from device $device due to catchall";
                        }
                        else {
                            $loopMsg .= " ### (from device $device)";
                        }
                    }

                    # correct message format
                    #
                    $loopMsg =~ s/((|(\d+)| )\|\w+\|( |))/\n\n/g
                      if ( $type[$i] ne "audio" ); # Remove Sonos Speak commands

                    if ( $type[$i] eq "mail" && $priorityCat ne "" ) {
                        $loopTitle = "[$priorityCat] $loopTitle";
                        $loopMsg =~ s/\n/<br \/>/g;
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
                            AttrVal( "global", "msgRecipient$typeUc", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal(
                            AttrVal( "global", "msgRecipient$typeUc", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal(
                            AttrVal( "global", "msgRecipient$typeUc", "" ),
                            "presence", "" )
                          if ( $residentDevPresence eq "" );
                    }

                    # global indirect general
                    if (
                        (
                               $residentDevState eq ""
                            || $residentDevPresence eq ""
                        )
                        && ReadingsVal( AttrVal( "global", "msgRecipient", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal( AttrVal( "global", "msgRecipient", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal( AttrVal( "global", "msgRecipient", "" ),
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
                            AttrVal( "global", "msgResidentsDev", "" ),
                            "presence", "-" ) ne "-"
                      )
                    {
                        $residentDevState =
                          ReadingsVal(
                            AttrVal( "global", "msgResidentsDev", "" ),
                            "state", "" )
                          if ( $residentDevState eq "" );
                        $residentDevPresence =
                          ReadingsVal(
                            AttrVal( "global", "msgResidentsDev", "" ),
                            "presence", "" )
                          if ( $residentDevPresence eq "" );
                    }

                    ################################################################
                    ### Send message
                    ###

                    my %gatewaysStatus;

                    foreach my $gatewayDevOr ( split /\|/, $gatewayDevs ) {
                        foreach my $gatewayDev ( split /,/, $gatewayDevOr ) {
                            Log3 $logDevice, 5,
"msg $device: Trying to send message via gateway $gatewayDev";

                            # restricted priority scope for Pushover
                            if (   $type[$i] eq "push"
                                && $defs{$gatewayDev}{TYPE} eq "Pushover" )
                            {
                                $loopPriority = 2
                                  if ( $loopPriority > 2 );
                                $loopPriority = -2
                                  if ( $loopPriority < -2 );
                            }

                            ##############
                           # check for gateway availability and set route status
                           #

                            my $routeStatus = "OK";
                            if (   $type[$i] ne "mail"
                                && !defined( $defs{$gatewayDev} )
                                && $deviceType eq "device" )
                            {
                                $routeStatus = "UNDEFINED";
                            }
                            elsif ( $type[$i] ne "mail"
                                && AttrVal( $gatewayDev, "disable", "0" ) eq
                                "1" )
                            {
                                $routeStatus = "DISABLED";
                            }
                            elsif (
                                $type[$i] ne "mail"
                                && (
                                    AttrVal( $gatewayDev, "disable", "0" ) eq
                                    "1"
                                    || ReadingsVal( $gatewayDev, "power", "on" )
                                    eq "off"
                                    || ReadingsVal( $gatewayDev, "presence",
                                        "present" ) eq "absent"
                                    || ReadingsVal( $gatewayDev, "presence",
                                        "appeared" ) eq "disappeared"
                                    || ReadingsVal( $gatewayDev, "state",
                                        "present" ) eq "absent"
                                    || ReadingsVal( $gatewayDev, "state",
                                        "reachable" ) eq "unreachable"
                                    || ReadingsVal(
                                        $gatewayDev, "reachable", "1"
                                    ) eq "0"
                                    || ReadingsVal( $gatewayDev, "reachable",
                                        "yes" ) eq "no"
                                )
                              )
                            {
                                $routeStatus = "UNAVAILABLE";
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

                            # enforce by user request
                            if (
                                (
                                       $routeStatus eq "USER_DISABLED"
                                    || $routeStatus eq "USER_ABSENT"
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
                                )
                                && $loopPriority >= 2
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

                           # use command from device, global or internal default
                            my $defCmd;
                            $defCmd = $defaults{ $type[$i] }{$priorityCat}
                              if ( $priorityCat ne "" );
                            $defCmd = $defaults{ $type[$i] }{Normal}
                              if ( $priorityCat eq "" );
                            my $cmd =

                              # gateway device
                              AttrVal(
                                $gatewayDev, "msgCmd$typeUc$priorityCat",

                                # look for direct
                                AttrVal(
                                    $device, "msgCmd$typeUc$priorityCat",

                                    # look for indirect
                                    AttrVal(
                                        AttrVal(
                                            $device, "msgRecipient$typeUc",
                                            ""
                                        ),
                                        "msgCmd$typeUc$priorityCat",

                                        #look for indirect general
                                        AttrVal(
                                            AttrVal(
                                                $device, "msgRecipient", ""
                                            ),
                                            "msgCmd$typeUc$priorityCat",

                                            # look for global direct
                                            AttrVal(
                                                "global",
                                                "msgCmd$typeUc$priorityCat",

                                                # look for global indirect
                                                AttrVal(
                                                    AttrVal(
                                                        "global",
                                                        "msgRecipient$typeUc",
                                                        ""
                                                    ),
                                                    "msgCmd$typeUc$priorityCat",

                                               #look for global indirect general
                                                    AttrVal(
                                                        AttrVal(
                                                            "global",
                                                            "msgRecipient",
                                                            ""
                                                        ),
"msgCmd$typeUc$priorityCat",

                                                        # internal
                                                        $defCmd
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                              );

                            $cmd =~ s/\$RECIPIENT/$gatewayDev/g;
                            $cmd =~ s/\$DEVICE/$gatewayDev/g;
                            $cmd =~ s/\$PRIORITY/$loopPriority/g;
                            $cmd =~ s/\$TITLE/$loopTitle/g;
                            $cmd =~ s/\$MSG/$loopMsg/g;

                            $sentCounter++;

                            if ( $routeStatus =~ /^OK\w*/ ) {

                                Log3 $logDevice, 3,
"msg $device: ID=$messageID.$sentCounter TYPE=$type[$i] ROUTE=$gatewayDev STATUS=$routeStatus PRIORITY=$loopPriority($priorityCat) TITLE='$loopTitle' MSG='$msg'"
                                  if ( $priorityCat ne "" );
                                Log3 $logDevice, 3,
"msg $device: ID=$messageID.$sentCounter TYPE=$type[$i] ROUTE=$gatewayDev STATUS=$routeStatus PRIORITY=$loopPriority TITLE='$loopTitle' MSG='$msg'"
                                  if ( $priorityCat eq "" );

                                # run command
                                if ( $cmd =~ s/^[ \t]*\{|\}[ \t]*$//g ) {
                                    $cmd =~ s/@\w+/\\$&/g;
                                    Log3 $logDevice, 5,
"msg $device: $type[$i] route command (Perl): $cmd";
                                    eval $cmd;
                                }
                                else {
                                    Log3 $logDevice, 5,
"msg $device: $type[$i] route command (fhem): $cmd";
                                    fhem $cmd;
                                }

                                $messageSent                 = 1;
                                $messageSentDev              = 1;
                                $gatewaysStatus{$gatewayDev} = $routeStatus;
                            }
                            elsif ($routeStatus eq "UNAVAILABLE"
                                || $routeStatus eq "UNDEFINED" )
                            {
                                Log3 $logDevice, 3,
"msg $device: ID=$messageID.$sentCounter TYPE=$type[$i] ROUTE=$gatewayDev STATUS=$routeStatus PRIORITY=$loopPriority TITLE='$loopTitle' '$msg'";
                                $gatewaysStatus{$gatewayDev} = $routeStatus;
                            }
                            else {
                                Log3 $logDevice, 3,
"msg $device: ID=$messageID.$sentCounter TYPE=$type[$i] ROUTE=$gatewayDev STATUS=$routeStatus PRIORITY=$loopPriority TITLE='$loopTitle' '$msg'";
                                $messageSent    = 2 if ( $messageSent != 1 );
                                $messageSentDev = 2 if ( $messageSentDev != 1 );
                                $gatewaysStatus{$gatewayDev} = $routeStatus;
                            }

                        }

                        last if ( $messageSentDev == 1 );
                    }

                    if ( $catchall == 0 ) {
                        if ( !defined( $sentTypesPerDevice{$device} ) ) {
                            $sentTypesPerDevice{$device} = "";
                        }
                        else {
                            $sentTypesPerDevice{$device} .= " ";
                        }

                        $sentTypesPerDevice{$device} .=
                          $type[$i] . ":" . $messageSentDev;
                    }
                    else {
                        if ( !defined( $sentTypesPerDevice{$device} ) ) {
                            $sentTypesPerDevice{"global"} = "";
                        }
                        else {
                            $sentTypesPerDevice{"global"} .= " ";
                        }

                        $sentTypesPerDevice{"global"} .=
                          $type[$i] . ":" . $messageSentDev;
                    }

                    # update device readings
                    my $readingsDev = $defs{$device};
                    $readingsDev = $defs{"global"} if ( $catchall == 1 );
                    readingsBeginUpdate($readingsDev);

                    readingsBulkUpdate( $readingsDev, "fhemMsg" . $typeUc,
                        $loopMsg );
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "Title", $loopTitle );
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "Prio",
                        $loopPriority );

                    my $gwStates = "";

                    while ( ( my $gwName, my $gwState ) = each %gatewaysStatus )
                    {
                        $gwStates .= " " if $gwStates ne "";
                        $gwStates .= "$gwName:$gwState";
                    }
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "Gw", $gwStates );
                    readingsBulkUpdate( $readingsDev,
                        "fhemMsg" . $typeUc . "State",
                        $messageSentDev );

                    ################################################################
                    ### Implicit forwards based on priority or presence
                    ###

                    # no implicit escalations for type mail
                    next if ( $type[$i] eq "mail" );

                    # Skip if typeOr is defined
                    # and this is not the last type entry
                    # TODO: bei mehreren gleichzeitigen Typen (and-Definition)?
                    if (   $messageSentDev != 1
                        && $hasTypeOr == 1
                        && $isTypeOr < scalar( grep { defined $_ } @typesOr ) )
                    {
                        Log3 $logDevice, 4,
"msg $device: Skipping implicit forward due to typesOr definition";

                        # remove recipient from list to avoid
                        # other interaction when using recipientOr in parallel
                        if (   $hasRecipientOr == 1
                            && $isRecipientOr <
                            scalar( grep { defined $_ } @recipientsOr ) )
                        {
                            my $regex1 =
                              "\s*!?@?" . $device . "[,|]";   # at the beginning
                            my $regex2 =
                              "[,|]!?@?" . $device . "\s*";    # at the end
                            my $regex3 =
                                ",!?@?"
                              . $device
                              . ",";    # in the middle with comma
                            my $regex4 =
                                "[\|,]!?@?"
                              . $device
                              . "[\|,]";  # in the middle with pipe and/or comma

                            $recipients =~ s/^$regex1//;
                            $recipients =~ s/$regex2$/|/g;
                            $recipients =~ s/$regex3/,/g;
                            $recipients =~ s/$regex4/|/g;
                        }

                        next;
                    }

                    # Skip if recipientOr is defined
                    # and this is not the last device entry
                    # TODO: bei mehreren gleichzeitigen Empfängern
                    #       (and-Definition)?
                    if (   $messageSentDev != 1
                        && $hasRecipientOr == 1
                        && $isRecipientOr <
                        scalar( grep { defined $_ } @recipientsOr ) )
                    {
                        Log3 $logDevice, 4,
"msg $device: Skipping implicit forward due to recipientOr definition";

                        next;
                    }

                    # priority forward thresholds
                    #

                    ### emergency
                    my $msgFwPrioEmergency =

                      # look for direct
                      AttrVal(
                        $device, "msgFwPrioEmergency$typeUc",

                        #look for indirect
                        AttrVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "msgFwPrioEmergency$typeUc",

                            #look for indirect general
                            AttrVal(
                                AttrVal( $device, "msgRecipient", "" ),
                                "msgFwPrioEmergency$typeUc",

                                # default
                                2
                            )
                        )
                      );

                    ### absent
                    my $msgFwPrioAbsent =

                      # look for direct
                      AttrVal(
                        $device, "msgFwPrioAbsent$typeUc",

                        #look for indirect
                        AttrVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "msgFwPrioAbsent$typeUc",

                            #look for indirect general
                            AttrVal(
                                AttrVal( $device, "msgRecipient", "" ),
                                "msgFwPrioAbsent$typeUc",

                                # default
                                0
                            )
                        )
                      );

                    ### gone
                    my $msgFwPrioGone =

                      # look for direct
                      AttrVal(
                        $device, "msgFwPrioGone$typeUc",

                        #look for indirect
                        AttrVal(
                            AttrVal( $device, "msgRecipient$typeUc", "" ),
                            "msgFwPrioGone$typeUc",

                            #look for indirect general
                            AttrVal(
                                AttrVal( $device, "msgRecipient", "" ),
                                "msgFwPrioGone$typeUc",

                                # default
                                1
                            )
                        )
                      );

                    Log3 $logDevice, 5,
"msg $device: Implicit forwards: recipient presence=$residentDevPresence state=$residentDevState"
                      if ( $residentDevPresence ne ""
                        || $residentDevState ne "" );

                    my $fw_gwUnavailable =
                      $forwards{ $type[$i] }{gwUnavailable};
                    my $fw_emergency = $forwards{ $type[$i] }{emergency};
                    my $fw_residentAbsent =
                      $forwards{ $type[$i] }{highPrio}{residentAbsent};
                    my $fw_residentGone =
                      $forwards{ $type[$i] }{highPrio}{residentGone};

                    # Forward message
                    # if no gateway device for this type was available
                    if (   $messageSentDev == 0
                        && defined($fw_gwUnavailable)
                        && !( $fw_gwUnavailable ~~ @type )
                        && $routes{$fw_gwUnavailable} == 1 )
                    {
                        Log3 $logDevice, 4,
"msg $device: Implicit forwards: No $type[$i] gateway device available for recipient $device ($gatewayDevs). Trying alternative message type "
                          . $fw_gwUnavailable;

                        push @type, $fw_gwUnavailable;
                        $forwarded .= "," . $type[$i] . ">" . $fw_gwUnavailable
                          if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_gwUnavailable
                          if ( $forwarded eq "" );
                    }

                    # Forward message
                    # if emergency priority
                    if (   $loopPriority >= $msgFwPrioEmergency
                        && defined($fw_emergency)
                        && !( $fw_emergency ~~ @type )
                        && $routes{$fw_emergency} == 1 )
                    {
                        Log3 $logDevice, 4,
"msg $device: Implicit forwards: Escalating high priority $type[$i] message via "
                          . $fw_emergency;

                        push @type, $fw_emergency;
                        $forwarded .= "," . $type[$i] . ">" . $fw_emergency
                          if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_emergency
                          if ( $forwarded eq "" );
                    }

                    # Forward message
                    # if high priority and residents are constantly not at home
                    if (   $residentDevPresence eq "absent"
                        && $loopPriority >= $msgFwPrioGone
                        && defined($fw_residentGone)
                        && !( $fw_residentGone ~~ @type )
                        && $routes{$fw_residentGone} == 1 )
                    {
                        Log3 $logDevice, 4,
"msg $device: Implicit forwards: Escalating high priority $type[$i] message via "
                          . $fw_residentGone;

                        push @type, $fw_residentGone;
                        $forwarded .= "," . $type[$i] . ">" . $fw_residentGone
                          if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_residentGone
                          if ( $forwarded eq "" );
                    }

                    # Forward message
                    # if priority is normal or higher and residents
                    # are not at home but nearby
                    if (   $residentDevState eq "absent"
                        && $loopPriority >= $msgFwPrioAbsent
                        && defined($fw_residentAbsent)
                        && !( $fw_residentAbsent ~~ @type )
                        && $routes{$fw_residentAbsent} == 1 )
                    {
                        Log3 $logDevice, 4,
"msg $device: Implicit forwards: Escalating $type[$i] message via "
                          . $fw_residentAbsent
                          . " due to absence";

                        push @type, $fw_residentAbsent;
                        $forwarded .= "," . $type[$i] . ">" . $fw_residentAbsent
                          if ( $forwarded ne "" );
                        $forwarded .= $type[$i] . ">" . $fw_residentAbsent
                          if ( $forwarded eq "" );
                    }

                }

                last if ( $messageSent == 1 );

                $isRecipientOr++;
            }
        }

        last if ( $messageSent == 1 );

        $isTypeOr++;
    }

    # finalize device readings
    while ( ( my $device, my $types ) = each %sentTypesPerDevice ) {
        readingsBulkUpdate( $defs{$device}, "fhemMsgStateTypes", $types )
          if ( $forwarded eq "" );
        readingsBulkUpdate( $defs{$device}, "fhemMsgStateTypes",
            $types . " forwards:" . $forwarded )
          if ( $forwarded ne "" );
        readingsBulkUpdate( $defs{$device}, "fhemMsgState", $messageSent );
        readingsEndUpdate( $defs{$device}, 1 );
    }

    if ( $messageSent == 1 && $return ne "" ) {
        $return .= "However, message was still sent to some recipients!";
    }

    if ( $messageSent == 2 ) {
        $return .=
          "FATAL ERROR: Message NOT sent. No gateway device was available.";
    }

    return $return;
}

1;

=pod
=begin html

<a name="msg"></a>
<h3>mail</h3>
<ul>
  <code>msg [&lt;type&gt;] [&lt;@device&gt;|&lt;e-mail address&gt;] [&lt;priority&gt;] [|&lt;title&gt;|] &lt;message&gt;</code>
  <br>
  <br>
  No documentation yet, sorry.<br>
  <a href="http://forum.fhem.de/index.php/topic,39983.0.html">FHEM Forum</a>
</ul>

=end html
=begin html_DE

<a name="mail"></a>
<h3>mail</h3>
<ul>
  <code>msg [&lt;type&gt;] [&lt;@device&gt;|&lt;e-mail address&gt;] [&lt;priority&gt;] [|&lt;title&gt;|] &lt;message&gt;</code>
  <br>
  <br>
  Bisher keine Dokumentation, sorry.<br>
  <a href="http://forum.fhem.de/index.php/topic,39983.0.html">FHEM Forum</a>
</ul>


=end html_DE
=cut

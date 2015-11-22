# $Id$
##############################################################################
#
#     97_msgConfig.pm
#     Global configuration settings for FHEM msg command.
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
# - 1.0.0 - 2015-10-18
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use Data::Dumper;
use msgSchema;

sub msgConfig_Set($@);
sub msgConfig_Get($@);
sub msgConfig_Define($$);
sub msgConfig_Undefine($$);

###################################
sub msgConfig_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = "msgConfig_Define";
    $hash->{SetFn}    = "msgConfig_Set";
    $hash->{GetFn}    = "msgConfig_Get";
    $hash->{UndefFn}  = "msgConfig_Undefine";

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
      msgPriorityAudio:-2,-1,0,1,2
      msgPriorityLight:-2,-1,0,1,2
      msgPriorityMail:-2,-1,0,1,2
      msgPriorityPush:-2,-1,0,1,2
      msgPriorityScreen:-2,-1,0,1,2
      msgPriorityText:-2,-1,0,1,2
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
      msgType

    );
    use warnings 'qw';
    $hash->{AttrList} = join( " ", @attrList ) . " " . $readingFnAttributes;

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

###################################
sub msgConfig_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> msgConfig"
      if ( int(@a) < 2 );
    my $name  = $a[0];

    return "Global configuration device already defined: " . $modules{msgConfig}{defptr}{NAME}
      if (defined($modules{msgConfig}{defptr}));

    # create global unique device definition
    $modules{msgConfig}{defptr} = $hash;

    # set default settings on first define
    if ($init_done) {
        my $group = AttrVal("global","group","Global");
        my $room = AttrVal("global","room","");
        my $verbose = AttrVal("global","verbose",3);

        $attr{$name}{group} = $group;
        $attr{$name}{verbose} = $verbose;
        $attr{$name}{room} = $room if ($room ne "");
        $attr{$name}{comment} = "FHEM Global Configuration for command 'msg'";
        $attr{$name}{stateFormat} = "fhemMsgState";

        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "fhemMsgState", "initialized" );
        readingsEndUpdate( $hash, 1 );
    }

    return undef;
}

###################################
sub msgConfig_Undefine($$) {

    my ( $hash, $name ) = @_;

    # release global unique device definition
    delete $modules{msgConfig}{defptr};

    return undef;
}

###################################
sub msgConfig_Set($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    shift @a;
    my $what = shift @a;

    Log3 $name, 5, "msgConfig $name: called function msgConfig_Set()";

    my @msgTypes =
      ( "audio", "light", "mail", "push", "screen" );

    # cleanReadings
    if ( lc($what) eq "cleanreadings" ) {
        my $device = defined($a[0]) ? $a[0] : ".*";

        return fhem ("deletereading $device fhemMsg.*", 1);
    }

    # addLocation
    elsif ( lc($what) eq "addlocation" ) {
        my $location = join(" ", @a);
        my $group = AttrVal($name, "group", "msgConfig");
        my $room = AttrVal($name, "room", "");
        my $return = "";

        return "Missing argument 'location'"
          if ($location eq "");

        my $device = "msgRoom_" . $location;
        $device =~ s/[\s\t-]+/_/g;
        
        return "Device $device is already existing but not a dummy device"
          if (defined($defs{$device}) && $defs{$device}{TYPE} ne "dummy");

        if (!defined($defs{$device})) {
          $return = fhem ("define $device dummy", 1);
          $return .= "Device $device was created"
            if ($return eq "");
        } else {
          $return = "Existing dummy device $device was updated";
        }

        $attr{$device}{group} = $group if (!defined($attr{$device}{group}));
        $attr{$device}{room} = $room if (!defined($attr{$device}{room}) && $room ne "");
        $attr{$device}{comment} = "Auto-created by $name" if (!defined($attr{$device}{comment}));
        $attr{$device}{userattr} .= " msgLocationName" if (defined($attr{$device}{userattr}) && $attr{$device}{userattr} !~ /^msgLocationName$|^msgLocationName\s|\smsgLocationName\s|\smsgLocationName$/);
        $attr{$device}{userattr} = "msgLocationName" if (!defined($attr{$device}{userattr}));
        $attr{$device}{msgLocationName} = $location;
        fhem ("set $device $location");

        $attr{$name}{msgLocationDevs} .= ",".$device if (defined($attr{$name}{msgLocationDevs}) && $attr{$name}{msgLocationDevs} !~ /^$device\$|^$device,|,$device,|,$device$/);
        $attr{$name}{msgLocationDevs} = $device if (!defined($attr{$name}{msgLocationDevs}));
        
        return $return;
    }

    # createSwitcherDev
    elsif ( lc($what) eq "createswitcherdev" ) {
        my $device = AttrVal($name, "msgSwitcherDev", "HouseAnn");
        my $state = AttrVal($device, "state", "???");
        my $return = "";

        my $lang = "en";
        $lang = $a[0]
          if (defined($a[0]) && $a[0] eq "de");

        return "Device $device is already existing but not a dummy device"
          if (defined($defs{$device}) && $defs{$device}{TYPE} ne "dummy");

        if (!defined($defs{$device})) {
          $return = fhem ("define $device dummy", 1);
          $return .= "Device $device was created"
            if ($return eq "");
        } else {
          $return = "Existing dummy device $device was updated";
        }

        if ($lang eq "de") {
          $attr{$device}{alias} = "Durchsagen";
          $attr{$device}{eventMap} = "active:aktiv long:lang short:kurz visual:visuell off:aus";
          $attr{$device}{room} = "Haus" if (!defined($attr{$device}{room}));
          $attr{$device}{setList} = "state:lang,kurz,visuell,aus";
        } else {
          $attr{$device}{alias} = "Announcements";
          $attr{$device}{room} = "House" if (!defined($attr{$device}{room}));
          $attr{$device}{setList} = "state:long,short,visual,off";
          delete $attr{$device}{eventMap} if (defined($attr{$device}{eventMap}));
        }
        $attr{$device}{comment} = "Auto-created by $name" if (!defined($attr{$device}{comment}) || $attr{$device}{comment} ne "Auto-created by $name");
        $attr{$device}{devStateIcon} = 'aktiv:general_an@90EE90 active:general_an@90EE90 lang:general_an@green:off long:general_an@green:off  aus:general_aus@red:long off:general_aus@red:long kurz:general_an@orange:long short:general_an@orange:long visuell:general_an@orange:long visual:general_an@orange:long';
        $attr{$device}{"event-on-change-reading"} = "state" if (!defined($attr{$device}{"event-on-change-reading"}));
        $attr{$device}{group} = "Automation" if (!defined($attr{$device}{group}));
        $attr{$device}{icon} = "audio_volume_mid";
        $attr{$device}{webCmd} = "state";
        fhem ("set $device long") if ($state eq "???");

        $return .= "\nAttribute msgSwitcherDev at device $name was changed to $device"
          if (defined($attr{$name}{msgSwitcherDev}));
        $return .= "\nAdded attribute msgSwitcherDev to device $name"
          if (!defined($attr{$name}{msgSwitcherDev}));
        $attr{$name}{msgSwitcherDev} = $device;

        return $return;
    }

    # createResidentsDev
    elsif ( lc($what) eq "createresidentsdev" ) {
        my $device = AttrVal($name, "msgResidentsDev", "rgr_Residents");
        my $return = "";

        my $lang = "en";
        $lang = $a[0]
          if (defined($a[0]) && $a[0] eq "de");

        return "Device $device is already existing but not a RESIDENTS or ROOMMATE device"
          if (defined($defs{$device}) && ($defs{$device}{TYPE} ne "RESIDENTS" && $defs{$device}{TYPE} ne "ROOMMATE"));

        if (!defined($defs{$device})) {
          $return = fhem ("define $device RESIDENTS", 1);
          $return .= "RESIDENTS device $device was created."
            if ($return eq "");
        } else {
          $return = "Existing ".$defs{$device}{TYPE}." device $device was updated.";
        }

        if ($lang eq "de") {
          $attr{$device}{alias} = "Bewohner";
          $attr{$device}{eventMap} = "home:zu_Hause absent:außer_Haus gone:verreist gotosleep:bettfertig asleep:schläft awoken:aufgestanden";
          $attr{$device}{group} = "Haus Status" if (!defined($attr{$device}{group}));
          $attr{$device}{room} = "Haus" if (!defined($attr{$device}{room}));
          $attr{$device}{widgetOverride} = "state:zu_Hause,bettfertig,außer_Haus,verreist";
        } else {
          $attr{$device}{alias} = "Residents";
          $attr{$device}{group} = "Home State" if (!defined($attr{$device}{group}));
          $attr{$device}{room} = "House" if (!defined($attr{$device}{room}));
          delete $attr{$device}{eventMap} if (defined($attr{$device}{eventMap}));
          delete $attr{$device}{widgetOverride} if (defined($attr{$device}{widgetOverride}));
        }
        $attr{$device}{comment} = "Auto-created by $name" if (!defined($attr{$device}{comment}) || $attr{$device}{comment} ne "Auto-created by $name");
        $attr{$device}{devStateIcon} = '.*home:status_available@green .*absent:status_away_1@orange .*gone:status_standby .*none:control_building_empty .*gotosleep:status_night@green:asleep .*asleep:status_night@green .*awoken:status_available@green:home .*zu_Hause:user_available:absent .*außer_Haus:user_away:home .*verreist:user_ext_away:home .*bettfertig:scene_toilet:asleep .*schläft:scene_sleeping:awoken .*aufgestanden:scene_sleeping_alternat:home .*:user_unknown';

        $return .= "\nIf you would like this device to act as an overall presence device for ALL msg commands, please adjust attribute msgResidentsDev at device $name to $device."
          if (defined($attr{$name}{msgResidentsDev}) && $attr{$name}{msgResidentsDev} ne $device);
        $return .= "\nNext, set a device's msgResidentsDev attribute to '$device' (think of using 'userattr' to add 'msgResidentsDev' to the list of available attributes). \nIf you would like '$device' to act as an overall presence device for ALL msg commands, sett attribute msgResidentsDev at device $name to $device."
          if (!defined($attr{$name}{msgResidentsDev}));

        return $return;
    }

    else {
        return
"Unknown argument $what, choose one of cleanReadings addLocation createSwitcherDev:de,en createResidentsDev:de,en";
    }
}

###################################
sub msgConfig_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    shift @a;
    my $what = shift @a;

    Log3 $name, 5, "msgConfig $name: called function msgConfig_Get()";

    my @msgTypes =
      ( "audio", "light", "mail", "push", "screen" );

    # routeCmd
    if ( lc($what) eq "routecmd" ) {
        my $return = "";
        my $msgTypesReq = defined($a[0]) ? lc($a[0]) : join( ',', @msgTypes );
        my $devicesReq = defined($a[1]) ? $a[1] : $name;
        my $cmdSchema = msgSchema::get();
        my $UserDeviceTypes = "";

        foreach my $msgType (split( /,/, $msgTypesReq )) {

          # Check device
          if ($devicesReq ne "") {
            foreach my $device (split( /,/, $devicesReq )) {
              if (defined($defs{$device})) {
                $UserDeviceTypes .= ",".$defs{$device}{TYPE} if ($UserDeviceTypes ne "" && $msgType ne "mail" && $device ne $name);
                $UserDeviceTypes = $defs{$device}{TYPE} if ($UserDeviceTypes eq "" && $msgType ne "mail" && $device ne $name);
                $UserDeviceTypes .= ",fhemMsgMail" if ($UserDeviceTypes ne "" && $msgType eq "mail" && $device ne $name);
                $UserDeviceTypes = "fhemMsgMail" if ($UserDeviceTypes eq "" && $msgType eq "mail" && $device ne $name);

                  my $typeUc = ucfirst($msgType);

                  my @priorities;
                  @priorities = ("Normal", "ShortPrio", "Short") if ($msgType eq "audio");
                  @priorities = ("Normal", "High", "Low") if ($msgType ne "audio");

                  my $output = 0;
                  foreach my $prio (@priorities) {
                    my $priorityCat = "";
                    $priorityCat = $prio if ($prio ne "Normal");
                    
                    my $cmd =
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
                                                $name,
                                                "msgCmd$typeUc$priorityCat",

                                                # look for global indirect
                                                AttrVal(
                                                    AttrVal(
                                                        $name,
                                                        "msgRecipient$typeUc",
                                                        ""
                                                    ),
                                                    "msgCmd$typeUc$priorityCat",

                                               #look for global indirect general
                                                    AttrVal(
                                                        AttrVal(
                                                            $name,
                                                            "msgRecipient",
                                                            ""
                                                        ), "msgCmd$typeUc$priorityCat",

                                                        # none
                                                        ""
                                                    )
                                                )
                                            )
                                        )
                                    )
                                );

                      next if ($cmd eq "" && $device eq $name && $output == 0);
                      $return .= uc($msgType).": USER DEFINED COMMANDS WITH PRECEDENCE\n-------------------------------------------------------------------------------\n\n" if ($output == 0);
                      $return .= "  $device (DEVICE TYPE: ".$defs{$device}{TYPE}.")\n" if ($output == 0);
                      $output = 1 if ($output == 0);

                      $return .= "    Priority $prio:\n      $cmd\n" if ($cmd ne "");
                      $return .= "    Priority $prio:\n      [DEFAULT COMMAND]\n" if ($cmd eq "");
                  }

                
                
                $return .= "\n" if ($return ne "");
              }
            }

            $return .= "\n" if ($return ne "");
          }

          # Default commands
          if (defined($cmdSchema->{$msgType})) {

            my $deviceTypes = $devicesReq;
            $deviceTypes = join(',', keys $cmdSchema->{$msgType})
              if ($deviceTypes eq "" || $devicesReq eq $name);
            $deviceTypes = $UserDeviceTypes
              if ($UserDeviceTypes ne "");

            my $outout = 0;
            foreach my $deviceType (split( /,/, $deviceTypes )) {

              if (defined($cmdSchema->{$msgType}{$deviceType})) {
                $return .= uc($msgType).": DEFAULT COMMANDS\n-------------------------------------------------------------------------------\n\n"
                  if ($outout == 0);
                $outout = 1;
                $return .= "  $deviceType\n";

                my @priorities;
                @priorities = ("Normal", "ShortPrio", "Short") if ($msgType eq "audio");
                @priorities = ("Normal", "High", "Low") if ($msgType ne "audio");

                foreach my $prio (@priorities) {
                  $return .= "    Priority $prio:\n      ".$cmdSchema->{$msgType}{$deviceType}{$prio}."\n";

                  if (defined($cmdSchema->{$msgType}{$deviceType}{defaultValues}{$prio})) {
                    $return .= "      Default Values:\n";

                    foreach my $key (keys $cmdSchema->{$msgType}{$deviceType}{defaultValues}{$prio}) {
                      if ($cmdSchema->{$msgType}{$deviceType}{defaultValues}{$prio}{$key} ne "") {
                        $return .= "        $key = ".$cmdSchema->{$msgType}{$deviceType}{defaultValues}{$prio}{$key}."\n" ;
                      } else {
                        $return .= "        $key = [EMPTY]\n" ;
                      }
                    }

                  }
                }

                $return .= "\n" if ($return ne "");
              }

            }
          } else {
            $return .= "Unknown messaging type '$msgType'\n" if ($msgType ne "text");
            $return .= "Messaging type 'text' does not have dedicated routing commands. This is a wrapper type to dynamically distinguish between push and mail.\n" if ($msgType eq "text");
          }

          $return .= "\n" if ($return ne "");
        }

        $return = "Non-existing device or unknown module messaging schema definition: $devicesReq" if ($return eq "");
        return $return;
    }

    else {
        return
"Unknown argument $what, choose one of routeCmd:,audio,light,mail,push,screen";
    }
}

1;

=pod

=begin html

    <p>
      <a name="msgConfig" id="msgConfig"></a>
    </p>
    <h3>
      msgConfig
    </h3>
    <ul>
      Provides global settings for FHEM command <a href="#MSG">msg</a>.<br>
      <br>
      <a name="msgConfigdefine" id="msgConfigdefine"></a> <b>Define</b>
      <div style="margin-left: 2em">
        <code>define &lt;name&gt; msgConfig</code><br>
      </div>
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
      Stellt globale Einstellungen für das FHEM Kommando <a href="#MSG">msg</a> bereit.<br>
      <br>
      <a name="msgConfigdefine" id="msgConfigdefine"></a> <b>Define</b>
      <div style="margin-left: 2em">
        <code>define &lt;name&gt; msgConfig</code><br>
      </div>
    </ul>

=end html_DE

=cut

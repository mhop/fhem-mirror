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
    my $what = "";

    Log3 $name, 5, "msgConfig $name: called function msgConfig_Set()";

    my @msgTypes =
      ( "audio", "light", "mail", "push", "screen" );

    $what = $a[1];

    # cleanReadings
    if ( lc($what) eq "cleanreadings" ) {
        my $device = defined($a[2]) ? $a[2] : ".*";

        return fhem ("deletereading $device fhemMsg.*", 1);
    }

    else {
        return
"Unknown argument $what, choose one of cleanReadings";
    }
}

###################################
sub msgConfig_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $what = "";

    Log3 $name, 5, "msgConfig $name: called function msgConfig_Get()";

    my @msgTypes =
      ( "audio", "light", "mail", "push", "screen" );

    $what = $a[1];

    # routeCmd
    if ( lc($what) eq "routecmd" ) {
        my $return = "";
        my $msgTypesReq = defined($a[2]) ? lc($a[2]) : join( ',', @msgTypes );
        my $devicesReq = defined($a[3]) ? $a[3] : $name;
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
                    my $priorityCat;
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

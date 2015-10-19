# $Id$
##############################################################################
#
#     97_messageConfig.pm
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

sub messageConfig_Set($@);
sub messageConfig_Define($$);
sub messageConfig_Undefine($$);

###################################
sub messageConfig_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = "messageConfig_Define";
    $hash->{UndefFn}  = "messageConfig_Undefine";

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
sub messageConfig_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> messageConfig"
      if ( int(@a) < 2 );
    my $name  = $a[0];

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
sub messageConfig_Undefine($$) {

    my ( $hash, $name ) = @_;

    return undef;
}

1;

=pod

=begin html

    <p>
      <a name="messageConfig" id="messageConfig"></a>
    </p>
    <h3>
      messageConfig
    </h3>
    <ul>
      <li>Provides global settings to configure FHEM command 'msg'.<br>
        <br>
      </li>
      <li>
        <a name="messageConfigdefine" id="messageConfigdefine"></a> <b>Define</b>
        <div style="margin-left: 2em">
          <code>define &lt;name&gt; messageConfig</code><br>
          <br>
          Defines the global msg control device instance. Pleae note there can only be one unique definition of this device type.
        </div>
      </li>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="messageConfig" id="messageConfig"></a>
    </p>
    <h3>
      messageConfig
    </h3>
    <div style="margin-left: 2em">
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </div>
    <div style="margin-left: 2em">
      <a href='http://fhem.de/commandref.html#messageConfig'>messageConfig</a>
    </div>

=end html_DE

=cut

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

sub msgConfig_Set($@);
sub msgConfig_Define($$);
sub msgConfig_Undefine($$);

###################################
sub msgConfig_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = "msgConfig_Define";
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
      <li>Provides global settings for FHEM command <a href="#MSG">msg</a>.<br>
        <br>
      </li>
      <li>
        <a name="msgConfigdefine" id="msgConfigdefine"></a> <b>Define</b>
        <div style="margin-left: 2em">
          <code>define &lt;name&gt; msgConfig</code><br>
        </div>
      </li>
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
      <li>Stellt globale Einstellungen für das FHEM Kommando <a href="#MSG">msg</a> bereit.<br>
        <br>
      </li>
      <li>
        <a name="msgConfigdefine" id="msgConfigdefine"></a> <b>Define</b>
        <div style="margin-left: 2em">
          <code>define &lt;name&gt; msgConfig</code><br>
        </div>
      </li>
    </ul>

=end html_DE

=cut

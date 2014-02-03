# $Id$
##############################################################################
#
#     98_GEOFANCY.pm
#     An FHEM Perl module to receive geofencing webhooks from geofancy.com.
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
#
#     Based on HTTPSRV from Dr. Boris Neubert
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
# Version: 1.0.2
#
# Major Version History:
# - 1.0.0 - 2014-01-09
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use Data::Dumper;

sub GEOFANCY_Set($@);
sub GEOFANCY_Define($$);
sub GEOFANCY_Undefine($$);

#########################
sub GEOFANCY_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3 $name, 3, "Registering GEOFANCY $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

sub GEOFANCY_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 3, "Unregistering GEOFANCY $name for URL $url...";
    delete $data{FWEXT}{$url};
}

###################################
sub GEOFANCY_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "GEOFANCY_Initialize: Entering";

    $hash->{SetFn}    = "GEOFANCY_Set";
    $hash->{DefFn}    = "GEOFANCY_Define";
    $hash->{UndefFn}  = "GEOFANCY_Undefine";
    $hash->{AttrList} = "devAlias " . $readingFnAttributes;
}

###################################
sub GEOFANCY_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> GEOFANCY <infix>"
      if ( int(@a) != 3 );
    my $name  = $a[0];
    my $infix = $a[2];

    $hash->{fhem}{infix} = $infix;

    GEOFANCY_addExtension( $name, "GEOFANCY_CGI", $infix );

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "state", "initialized" );
    readingsEndUpdate( $hash, 1 );
    return undef;
}

###################################
sub GEOFANCY_Undefine($$) {

    my ( $hash, $name ) = @_;

    GEOFANCY_removeExtension( $hash->{fhem}{infix} );

    return undef;
}

###################################
sub GEOFANCY_Set($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};

    Log3 $name, 5, "GEOFANCY $name: called function GEOFANCY_Set()";

    return "No Argument given" if ( !defined( $a[1] ) );

    my $usage = "Unknown argument " . $a[1] . ", choose one of clear:readings";

    # clear
    if ( $a[1] eq "clear" ) {
        Log3 $name, 2, "GEOFANCY set $name " . $a[1];

        if ( $a[2] ) {

            # readings
            if ( $a[2] eq "readings" ) {
                delete $hash->{READINGS};
                readingsBeginUpdate($hash);
                readingsBulkUpdate( $hash, "state", "clearedReadings" );
                readingsEndUpdate( $hash, 1 );
            }

        }

        else {
            return "No Argument given, choose one of readings ";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub GEOFANCY_CGI() {

 # /$infix?device=UUID&id=UUID&latitude=xx.x&longitude=xx.x&trigger=(enter|exit)
    my ($request) = @_;

    my $hash;
    my $name;
    my $link;
    my $URI;
    my $device;
    my $id;
    my $lat;
    my $long;
    my $trigger;
    my $msg;

    # data received
    if ( $request =~ m,^(/[^/]+?)(?:\&|\?)(.*)?$, ) {
        $link = $1;
        $URI  = $2;

        # get device name
        $name = $data{FWEXT}{$link}{deviceName} if ( $data{FWEXT}{$link} );

        # return error if no such device
        return ( "text/plain; charset=utf-8",
            "NOK No GEOFANCY device for webhook $link" )
          unless ($name);

        # extract values from URI
        my $webArgs;
        foreach my $pv ( split( "&", $URI ) ) {
            next if ( $pv eq "" );
            $pv =~ s/\+/ /g;
            $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
            my ( $p, $v ) = split( "=", $pv, 2 );

            $webArgs->{$p} = $v;
        }

        if (   !defined( $webArgs->{device} )
            || !defined( $webArgs->{id} )
            || !defined( $webArgs->{latitude} )
            || !defined( $webArgs->{longitude} )
            || !defined( $webArgs->{trigger} )
            || $webArgs->{device} eq ""
            || $webArgs->{id} eq ""
            || $webArgs->{latitude} eq ""
            || $webArgs->{longitude} eq ""
            || $webArgs->{trigger} eq "" )
        {
            $msg = "device=";
            $msg .= $webArgs->{device}    if ( $webArgs->{device} );
            $msg .= " id=";
            $msg .= $webArgs->{id}        if ( $webArgs->{id} );
            $msg .= " latitude=";
            $msg .= $webArgs->{latitude}  if ( $webArgs->{latitude} );
            $msg .= " longitude=";
            $msg .= $webArgs->{longitude} if ( $webArgs->{longitude} );
            $msg .= " trigger=";
            $msg .= $webArgs->{trigger}   if ( $webArgs->{trigger} );

            Log3 $name, 3,
              "GEOFANCY: Insufficient data received for webhook $link:\n"
              . $msg;

            return ( "text/plain; charset=utf-8",
                "NOK\nInsufficient data received for webhook $link:\n" . $msg );
        }

        $device  = $webArgs->{device};
        $id      = $webArgs->{id};
        $lat     = $webArgs->{latitude};
        $long    = $webArgs->{longitude};
        $trigger = $webArgs->{trigger};
    }

    # no data received
    else {
        Log3 undef, 3,
"GEOFANCY: No data received, see API information on http://wiki.geofancy.com";

        return (
            "text/plain; charset=utf-8",
"NOK No data received, see API information on http://wiki.geofancy.com"
        );
    }

    # return error if unknown trigger
    return ( "text/plain; charset=utf-8", "$trigger NOK" )
      if ( $trigger ne "enter" && $trigger ne "exit" && $trigger ne "test" );

    $hash = $defs{$name};

    # Device alias handling
    #
    delete $hash->{helper}{device_aliases}
      if $hash->{helper}{device_aliases};
    delete $hash->{helper}{device_names}
      if $hash->{helper}{device_names};

    if ( defined( $attr{$name}{devAlias} ) ) {
        my @devices = split( ' ', $attr{$name}{devAlias} );

        if (@devices) {
            foreach (@devices) {
                my @device = split( ':', $_ );
                $hash->{helper}{device_aliases}{ $device[0] } =
                  $device[1];
                $hash->{helper}{device_names}{ $device[1] } =
                  $device[0];
            }
        }
    }

    $device = $hash->{helper}{device_aliases}{$device}
      if $hash->{helper}{device_aliases}{$device};

    Log3 $name, 4,
        "GEOFANCY $name: "
      . $device . ": id="
      . $id
      . " latitude="
      . $lat
      . " longitude="
      . $long
      . " trigger="
      . $trigger;

    readingsBeginUpdate($hash);

    # General readings
    readingsBulkUpdate( $hash, "state",
        "dev:$device trig:$trigger id:$id lat:$lat long:$long" );
    readingsBulkUpdate( $hash, "lastDevice", $device );
    readingsBulkUpdate( $hash, "lastArr",    $device . " " . $id )
      if $trigger eq "enter";
    readingsBulkUpdate( $hash, "lastDep", $device . " " . $id )
      if $trigger eq "exit";

    my $time = TimeNow();

    if ( $trigger eq "enter" || $trigger eq "test" ) {
        Log3 $name, 3, "GEOFANCY $name: $device arrived at $id";
        readingsBulkUpdate( $hash, $device,                  "arrived " . $id );
        readingsBulkUpdate( $hash, "currLoc_" . $device,     $id );
        readingsBulkUpdate( $hash, "currLocLat_" . $device,  $lat );
        readingsBulkUpdate( $hash, "currLocLong_" . $device, $long );
        readingsBulkUpdate( $hash, "currLocTime_" . $device, $time );
    }
    if ( $trigger eq "exit" ) {
        my $currReading;
        my $lastReading;

        Log3 $name, 3, "GEOFANCY $name: $device left $id and is underway";

        # backup last known location if not "underway"
        $currReading = "currLoc_" . $device;
        if ( defined( $hash->{READINGS}{$currReading}{VAL} )
            && $hash->{READINGS}{$currReading}{VAL} ne "underway" )
        {
            foreach ( 'Loc', 'LocLat', 'LocLong' ) {
                $currReading = "curr" . $_ . "_" . $device;
                $lastReading = "last" . $_ . "_" . $device;
                readingsBulkUpdate( $hash, $lastReading,
                    $hash->{READINGS}{$currReading}{VAL} )
                  if ( defined( $hash->{READINGS}{$currReading}{VAL} ) );
            }
            $currReading = "currLocTime_" . $device;
            readingsBulkUpdate(
                $hash,
                "lastLocArr_" . $device,
                $hash->{READINGS}{$currReading}{VAL}
            ) if ( defined( $hash->{READINGS}{$currReading}{VAL} ) );
            readingsBulkUpdate( $hash, "lastLocDep_" . $device, $time );
        }

        readingsBulkUpdate( $hash, $device,                  "left " . $id );
        readingsBulkUpdate( $hash, "currLoc_" . $device,     "underway" );
        readingsBulkUpdate( $hash, "currLocLat_" . $device,  "-" );
        readingsBulkUpdate( $hash, "currLocLong_" . $device, "-" );
        readingsBulkUpdate( $hash, "currLocTime_" . $device, $time );
    }

    readingsEndUpdate( $hash, 1 );

    $msg = "$trigger OK";
    $msg .= "\ndevice=$device id=$id lat=$lat long=$long trigger=$trigger"
      if ( $trigger eq "test" );

    return ( "text/plain; charset=utf-8", $msg );
}

1;

=pod
=begin html

<a name="GEOFANCY"></a>
<h3>GEOFANCY</h3>
<ul>
  Provides webhook receiver for geofencing from geofancy.com.<p>

  GEOFANCY is an extension to <a href="FHEMWEB">FHEMWEB</a>. You need to install FHEMWEB to use GEOFANCY.</p>

  <a name="GEOFANCYdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; &lt;infix&gt;</code><br><br>

    Defines the webhook server. <code>&lt;infix&gt;</code> is the portion behind the FHEMWEB base URL (usually
    <code>http://hostname:8083/fhem</code>)

    Example:
    <ul>
      <code>define geofancy GEOFANCY geo</code><br>
    </ul>
    The webhook will be reachable at http://hostname:8083/fhem/geo in that case.<br>
    <br>
  </ul>

  <a name="GEOFANCYset"></a>
  <b>Set</b>
  <ul>
      <li><b>clear</b> &nbsp;&nbsp;readings&nbsp;&nbsp; can be used to cleanup auto-created readings from deprecated devices.</li>
  </ul>
  <br><br>

  <a name="GEOFANCYattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>devAlias: can be used to rename device names in the format DEVICEUUID:Aliasname. Separate using blank to rename multiple devices.</li>
  </ul>
  <br><br>

  <b>Usage information</b>
  <br><br>
  <ul>
    Likely your FHEM installation is not reachable directly from the internet (good idea!).
    It is recommended to have a reverse proxy like nginx or Apache in front of FHEM where you can make sure access is only possible
    to specific subdirectories like /fhem/geo.
    You might also want to think about protecting the access by using HTTP Basic Authentication and encryption via SSL.
    Also the definition of a dedicated FHEMWEB instance for that purpose might help to restrict FHEM's functionality
    (note that the 'hidden' attributes of FHEMWEB currently do NOT protect from just guessing/knowing the correct URL!)
    <br>
    To make that reverse proxy available from the internet, just forward the appropriate port via your internet router.
    <br>
    The actual solution on how you can securely make your Geofancy webhook available to the internet is not part of this documentation
    and depends on your own skills.
  </ul>
  <br><br>
</ul>

=end html

=begin html_DE
Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden.
Die englische Version ist hier zu finden: 

 <a href='http://fhem.de/commandref.html#GEOFANCY>'>GEOFANCY</a> &nbsp;

=end html_DE
=cut

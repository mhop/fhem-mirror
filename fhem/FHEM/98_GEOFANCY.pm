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
# Version: 1.1.0
#
# Major Version History:
# - 1.1.0 - 2014-02-06
# -- Support for both apps: Geofency and Geofancy
#
# - 1.0.0 - 2014-01-09
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use Time::Local;
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

# Geofancy
# /$infix?device=UUIDdev&id=UUIDloc&latitude=xx.x&longitude=xx.x&trigger=(enter|exit)
#
# Geofency
# /$infix?id=UUIDloc&name=locName&entry=(1|0)&date=DATE&latitude=xx.x&longitude=xx.x&device=UUIDdev
    my ($request) = @_;

    my $hash;
    my $name;
    my $link;
    my $URI;
    my $device;
    my $id;
    my $lat;
    my $long;
    my $entry;
    my $msg;
    my $date;
    my $time;
    my $locName;

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

        if (
               !defined( $webArgs->{device} )
            || !defined( $webArgs->{id} )
            || (
                !(
                    defined( $webArgs->{trigger} && $webArgs->{trigger} ne "" )
                )
                && !( defined( $webArgs->{entry} ) && $webArgs->{entry} ne "" )
            )
            || $webArgs->{device} eq ""
            || $webArgs->{id} eq ""
          )
        {
            $msg = " id=";
            $msg .= $webArgs->{id}        if ( $webArgs->{id} );
            $msg .= " name=";
            $msg .= $webArgs->{name}      if ( $webArgs->{name} );
            $msg .= " entry=";
            $msg .= $webArgs->{entry}     if ( $webArgs->{entry} );
            $msg .= " trigger=";
            $msg .= $webArgs->{trigger}   if ( $webArgs->{trigger} );
            $msg .= " date=";
            $msg .= $webArgs->{date}      if ( $webArgs->{date} );
            $msg .= " latitude=";
            $msg .= $webArgs->{latitude}  if ( $webArgs->{latitude} );
            $msg .= " longitude=";
            $msg .= $webArgs->{longitude} if ( $webArgs->{longitude} );
            $msg .= " device=";
            $msg .= $webArgs->{device}    if ( $webArgs->{device} );

            Log3 $name, 3,
              "GEOFANCY: Insufficient data received for webhook $link:\n"
              . $msg;

            return ( "text/plain; charset=utf-8",
                "NOK\nInsufficient data received for webhook $link:\n" . $msg );
        }

        # Geofancy.app
        if ( defined $webArgs->{trigger} ) {
            $id     = $webArgs->{id};
            $entry  = $webArgs->{trigger};
            $lat    = $webArgs->{latitude};
            $long   = $webArgs->{longitude};
            $device = $webArgs->{device};
        }

        # Geofency.app
        elsif ( defined $webArgs->{entry} ) {
            $id      = $webArgs->{id};
            $locName = $webArgs->{name};
            $entry   = $webArgs->{entry};
            $date    = $webArgs->{date};
            $lat     = $webArgs->{latitude};
            $long    = $webArgs->{longitude};
            $device  = $webArgs->{device};
        }
        else {
            return "fatal error";
        }
    }

    # no data received
    else {
        Log3 undef, 3, "GEOFANCY: No data received";

        return ( "text/plain; charset=utf-8", "NOK No data received" );
    }

    # return error if unknown trigger
    return ( "text/plain; charset=utf-8", "$entry NOK" )
      if ( $entry ne "enter"
        && $entry ne "1"
        && $entry ne "exit"
        && $entry ne "0"
        && $entry ne "test" );

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
"GEOFANCY $name: id=$id name=$locName entry=$entry date=$date lat=$lat long=$long dev=$device";

    readingsBeginUpdate($hash);

    # use time from device
    if ( defined $date && $date ne "" ) {
        $hash->{".updateTime"}      = GEOFANCY_ISO8601UTCtoLocal($date);
        $hash->{".updateTimestamp"} = FmtDateTime( $hash->{".updateTime"} );
        $time                       = $hash->{".updateTimestamp"};
    }

    # use local FHEM time
    else {
        $time = TimeNow();
    }

    # General readings
    readingsBulkUpdate( $hash, "state",
"id:$id name:$locName trig:$entry date:$date lat:$lat long:$long dev:$device"
    );

    $id = $locName if ( defined($locName) && $locName ne "" );

    readingsBulkUpdate( $hash, "lastDevice", $device );
    readingsBulkUpdate( $hash, "lastArr",    $device . " " . $id )
      if ( $entry eq "enter" || $entry eq "1" );
    readingsBulkUpdate( $hash, "lastDep", $device . " " . $id )
      if ( $entry eq "exit" || $entry eq "0" );

    if ( $entry eq "enter" || $entry eq "1" || $entry eq "test" ) {
        Log3 $name, 3, "GEOFANCY $name: $device arrived at $id";
        readingsBulkUpdate( $hash, $device,                  "arrived " . $id );
        readingsBulkUpdate( $hash, "currLoc_" . $device,     $id );
        readingsBulkUpdate( $hash, "currLocLat_" . $device,  $lat );
        readingsBulkUpdate( $hash, "currLocLong_" . $device, $long );
        readingsBulkUpdate( $hash, "currLocTime_" . $device, $time );
    }
    if ( $entry eq "exit" || $entry eq "0" ) {
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

    $msg = "$entry OK";
    $msg .= "\ndevice=$device id=$id lat=$lat long=$long trigger=$entry"
      if ( $entry eq "test" );

    return ( "text/plain; charset=utf-8", $msg );
}

sub GEOFANCY_ISO8601UTCtoLocal ($) {
    my ($datetime) = @_;
    $datetime =~ s/T/ /g if ( defined( $datetime && $datetime ne "" ) );
    $datetime =~ s/Z//g  if ( defined( $datetime && $datetime ne "" ) );

    my (
        $date, $time, $y,     $m,       $d,       $hour,
        $min,  $sec,  $hours, $minutes, $seconds, $timestamp
    );

    ( $date, $time ) = split( ' ', $datetime );
    ( $y,    $m,   $d )   = split( '-', $date );
    ( $hour, $min, $sec ) = split( ':', $time );
    $m -= 01;
    $timestamp = timegm( $sec, $min, $hour, $d, $m, $y );
    ( $sec, $min, $hour, $d, $m, $y ) = localtime($timestamp);
    $timestamp = timelocal( $sec, $min, $hour, $d, $m, $y );

    return $timestamp;
}

1;

=pod
=begin html

<a name="GEOFANCY"></a>
<h3>GEOFANCY</h3>
<ul>
  Provides webhook receiver for geofencing via the following iOS apps:<br>
  <br>
  <li>Geofency: https://itunes.apple.com/de/app/geofency-time-tracking-automatic/id615538630?l=en&mt=8</li>
  <li>Geofancy: https://itunes.apple.com/de/app/geofancy/id725198453?l=en&mt=8</li>

  <p>Note: GEOFANCY is an extension to <a href="FHEMWEB">FHEMWEB</a>. You need to install FHEMWEB to use GEOFANCY.</p>

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

<a name="GEOFANCY"></a>
<h3>GEOFANCY</h3>
<ul>
Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden.
Die englische Version ist hier zu finden: 
</ul>
<ul>
<a href='http://fhem.de/commandref.html#GEOFANCY'>GEOFANCY</a>
</ul>

=end html_DE
=cut

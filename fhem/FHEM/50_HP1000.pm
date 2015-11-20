# $Id$
##############################################################################
#
#     50_HP1000.pm
#     An FHEM Perl module to receive data from HP1000 weather stations.
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
##############################################################################

package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use Time::Local;
use Data::Dumper;
use FHEM::98_dewpoint;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

sub HP1000_Define($$);
sub HP1000_Undefine($$);

#########################
sub HP1000_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3 $name, 2, "Registering HP1000 $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

#########################
sub HP1000_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2, "Unregistering HP1000 $name for URL $url...";
    delete $data{FWEXT}{$url};
}

###################################
sub HP1000_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "HP1000_Initialize: Entering";

    $hash->{DefFn}    = "HP1000_Define";
    $hash->{UndefFn}  = "HP1000_Undefine";
    $hash->{AttrList} = $readingFnAttributes;
}

###################################
sub HP1000_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> HP1000 [<ID> <PASSWORD>]"
      if ( int(@a) < 2 );
    my $name  = $a[0];
    $hash->{ID}  = $a[2] if (defined($a[2]));
    $hash->{PASSWORD}  = $a[3] if (defined($a[3]));

    return "Device already defined: " . $modules{HP1000}{defptr}{NAME}
      if (defined($modules{HP1000}{defptr}));

    $hash->{fhem}{infix} = "updateweatherstation";

    # create global unique device definition
    $modules{HP1000}{defptr} = $hash;

    HP1000_addExtension( $name, "HP1000_CGI", "updateweatherstation" );

    return undef;
}

###################################
sub HP1000_Undefine($$) {

    my ( $hash, $name ) = @_;

    HP1000_removeExtension( $hash->{fhem}{infix} );

    # release global unique device definition
    delete $modules{HP1000}{defptr};

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub HP1000_CGI() {

    my ($request) = @_;

    my $hash;
    my $name    = "";
    my $link;
    my $URI;
    my $result = "";
    my $webArgs;

    # data received
    if ( $request =~ /^\/updateweatherstation\.\w{3}\?(.+=.+)/ ) {
        $URI  = $1;

        # get device name
        $name = $data{FWEXT}{"/updateweatherstation"}{deviceName}
          if (defined($data{FWEXT}{"/updateweatherstation"}));

        # return error if no such device
        return ( "text/plain; charset=utf-8",
            "No HP1000 device for webhook /updateweatherstation" )
          unless ($name);

        # extract values from URI
        foreach my $pv ( split( "&", $URI ) ) {
            next if ( $pv eq "" );
            $pv =~ s/\+/ /g;
            $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
            my ( $p, $v ) = split( "=", $pv, 2 );

            $webArgs->{$p} = $v;
        }
        
        return ("text/plain; charset=utf-8", "Insufficient data")
          if (!defined($webArgs->{softwaretype}) || !defined($webArgs->{dateutc}) || !defined($webArgs->{ID}) || !defined($webArgs->{PASSWORD}) || !defined($webArgs->{action}))
    }

    # no data received
    else {
        return ( "text/plain; charset=utf-8", "Missing data" );
    }

    $hash = $defs{$name};

    $hash->{SWVERSION} = $webArgs->{softwaretype};
    $hash->{SYSTEMTIME_UTC} = $webArgs->{dateutc};

    if (defined($hash->{ID}) && defined($hash->{PASSWORD}) && ($hash->{ID} ne $webArgs->{ID} || $hash->{PASSWORD} ne $webArgs->{PASSWORD})) {
      Log3 $name, 4, "HP1000: received data containing wrong credentials:";
      return ("text/plain; charset=utf-8", "Wrong credentials");
    } else {
      Log3 $name, 5, "HP1000: received data:\n" . Dumper($webArgs);
      delete $webArgs->{ID};
      delete $webArgs->{PASSWORD};
      delete $webArgs->{dateutc};
      delete $webArgs->{action};
      delete $webArgs->{softwaretype};
    }

    readingsBeginUpdate($hash);

    # write general readings
    while ( (my $p, my $v) = each %$webArgs ) {
      # ignore those values
      next if ($v eq "");

      # name translation
      $p = "humidityIndoor" if ($p eq "inhumi");
      $p = "temperatureIndoor" if ($p eq "intemp");
      $p = "humidity" if ($p eq "outhumi");
      $p = "temperature" if ($p eq "outtemp");
      $p = "luminosity" if ($p eq "light");
      $p = "pressure" if ($p eq "relbaro");
      $p = "pressureAbs" if ($p eq "absbaro");
      $p = "rain" if ($p eq "rainrate");
      $p = "rainDay" if ($p eq "dailyrain");
      $p = "rainWeek" if ($p eq "weeklyrain");
      $p = "rainMonth" if ($p eq "monthlyrain");
      $p = "rainYear" if ($p eq "yearlyrain");
      $p = "uv" if ($p eq "UV");
      $p = "windChill" if ($p eq "windchill");
      $p = "windDir" if ($p eq "winddir");
      $p = "windGust" if ($p eq "windgust");
      $p = "windSpeed" if ($p eq "windspeed");

      readingsBulkUpdate( $hash, $p, $v );
    }

    # calculated readings
    #

    # dewpointIndoor
    if (defined($webArgs->{intemp}) && defined($webArgs->{inhumi})) {
      my $v = int( dewpoint_dewpoint($webArgs->{intemp}, $webArgs->{inhumi}) + 0.5 );
      readingsBulkUpdate( $hash, "dewpointIndoor", $v );
    }

    # humidityAbs
    if (defined($webArgs->{outtemp}) && defined($webArgs->{outhumi})) {
      my $v = int( dewpoint_absFeuchte($webArgs->{outtemp}, $webArgs->{outhumi}) + 0.5 );
      readingsBulkUpdate( $hash, "humidityAbs", $v );
    }

    # humidityIndoorAbs
    if (defined($webArgs->{intemp}) && defined($webArgs->{inhumi})) {
      my $v = int( dewpoint_absFeuchte($webArgs->{intemp}, $webArgs->{inhumi}) + 0.5 );
      readingsBulkUpdate( $hash, "humidityIndoorAbs", $v );
    }
    
    # condition_forecast (based on pressure trendency)
    
    # day/night
    
    # isRaining
    # solarRadiation
    # soilTemperature
    # brightness in % ??

    # uv_index, uv_risk
    if (defined($webArgs->{UV})) {
      my $wavelength = $webArgs->{UV};      
    }

    $result = "T: ".$webArgs->{outtemp} if (defined($webArgs->{outtemp}));
    $result .= " H: ".$webArgs->{outhumi} if (defined($webArgs->{outhumi}));
    $result .= " Ti: ".$webArgs->{intemp} if (defined($webArgs->{intemp}));
    $result .= " Hi: ".$webArgs->{inhumi} if (defined($webArgs->{inhumi}));
    $result .= " W: ".$webArgs->{windspeed} if (defined($webArgs->{windspeed}));
    $result .= " R: ".$webArgs->{rainrate} if (defined($webArgs->{rainrate}));
    $result .= " WD: ".$webArgs->{winddir} if (defined($webArgs->{winddir}));
    $result .= " D: ".$webArgs->{dewpoint} if (defined($webArgs->{dewpoint}));
    $result .= " P: ".$webArgs->{relbaro} if (defined($webArgs->{relbaro}));

    readingsBulkUpdate( $hash, "state", $result );
    readingsEndUpdate( $hash, 1 );

    return ( "text/plain; charset=utf-8", "success" );
}

1;

=pod

=begin html

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <div style="margin-left: 2em">
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div style="margin-left: 2em">
        <code>define &lt;WeatherStation&gt; HP1000 [<ID> <PASSWORD>]</code><br>
        <br>
          Provides webhook receiver for weather station HP1000 and WH2600 of Fine Offset Electronics.<br>
          There needs to be a dedicated FHEMWEB instance with attribute webname set to "weatherstation".<br>
          No other name will work as it's hardcoded in the HP1000/WH2600 device itself!<br>
          <br>
          As the URI has a fixed coding as well there can only be one single HP1000/WH2600 station per FHEM installation.<br>
        <br>
        Example:<br>
        <div style="margin-left: 2em">
          <code># unprotected instance where ID and PASSWORD will be ignored<br>
          define WeatherStation HP1000<br>
          <br>
          # protected instance: Weather Station needs to be configured<br>
          # to send this ID and PASSWORD for data to be accepted<br>
          define WeatherStation HP1000 MyHouse SecretPassword</code>
        </div><br>
          IMPORTANT: In your HP1000/WH2600 device, make sure you use a DNS name as most revisions cannot handle IP addresses correctly.<br>
      </div><br>
    </div>

=end html

=begin html_DE

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <div style="margin-left: 2em">
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div style="margin-left: 2em">
        <code>define &lt;WeatherStation&gt; HP1000 [<ID> <PASSWORD>]</code><br>
        <br>
          Stellt einen Webhook f&uuml;r die HP1000 oder WH2600 Wetterstation von Fine Offset Electronics bereit.<br>
          Es muss noch eine dedizierte FHEMWEB Instanz angelegt werden, wo das Attribut webname auf "weatherstation" gesetzt wurde.<br>
          Kein anderer Name funktioniert, da dieser hard im HP1000/WH2600 Ger%auml;t hinterlegt ist!<br>
          <br>
          Da die URI ebenfalls fest kodiert ist, kann mit einer einzelnen FHEM Installation maximal eine HP1000/WH2600 Station gleichzeitig verwendet werden.<br>
        <br>
        Beispiel:<br>
        <div style="margin-left: 2em">
          <code># ungesch&uuml;tzte Instanz bei der ID und PASSWORD ignoriert werden<br>
          define WeatherStation HP1000<br>
          <br>
          # gesch&uuml;tzte Instanz: Die Wetterstation muss so konfiguriert sein, dass sie<br>
          # diese ID und PASSWORD sendet, damit Daten akzeptiert werden<br>
          define WeatherStation HP1000 MyHouse SecretPassword</code>
        </div><br>
          WICHTIG: Im HP1000/WH2600 Ger&auml; muss sichergestellt sein, dass ein DNS Name statt einer IP Adresse verwendet wird, da einige Revisionen damit nicht umgehen k&ouml;nnen.<br>
      </div><br>
    </div>

=end html_DE

=cut

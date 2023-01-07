# $Id$
##############################################################################
#
#     59_Weather.pm
#     (c) 2009-2023 Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#       Contributors:
#         - Marko Oldenburg (CoolTux)
#         - Lippie
#
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
use Time::HiRes  qw(gettimeofday);
use experimental qw /switch/;
use Readonly;

use FHEM::Meta;
use vars qw($FW_ss);

# use Data::Dumper;    # for Debug only

my %pressure_trend_txt_en = ( 0 => "steady", 1 => "rising", 2 => "falling" );
my %pressure_trend_txt_de =
  ( 0 => "gleichbleibend", 1 => "steigend", 2 => "fallend" );
my %pressure_trend_txt_nl = ( 0 => "stabiel", 1 => "stijgend", 2 => "dalend" );
my %pressure_trend_txt_fr =
  ( 0 => "stable", 1 => "croissant", 2 => "décroissant" );
my %pressure_trend_txt_pl = ( 0 => "stabilne", 1 => "rośnie", 2 => "spada" );
my %pressure_trend_txt_it =
  ( 0 => "stabile", 1 => "in aumento", 2 => "in diminuzione" );
my %pressure_trend_sym = ( 0 => "=", 1 => "+", 2 => "-" );

my @directions_txt_en = (
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
);
my @directions_txt_de = (
    'N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
);
my @directions_txt_nl = (
    'N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO',
    'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW'
);
my @directions_txt_fr = (
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'
);
my @directions_txt_pl = (
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
);
my @directions_txt_it = (
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'
);

my %wdays_txt_en = (
    'Mon' => 'Mon',
    'Tue' => 'Tue',
    'Wed' => 'Wed',
    'Thu' => 'Thu',
    'Fri' => 'Fri',
    'Sat' => 'Sat',
    'Sun' => 'Sun'
);
my %wdays_txt_de = (
    'Mon' => 'Mo',
    'Tue' => 'Di',
    'Wed' => 'Mi',
    'Thu' => 'Do',
    'Fri' => 'Fr',
    'Sat' => 'Sa',
    'Sun' => 'So'
);
my %wdays_txt_nl = (
    'Mon' => 'Ma',
    'Tue' => 'Di',
    'Wed' => 'Wo',
    'Thu' => 'Do',
    'Fri' => 'Vr',
    'Sat' => 'Za',
    'Sun' => 'Zo'
);
my %wdays_txt_fr = (
    'Mon' => 'Lun',
    'Tue' => 'Mar',
    'Wed' => 'Mer',
    'Thu' => 'Jeu',
    'Fri' => 'Ven',
    'Sat' => 'Sam',
    'Sun' => 'Dim'
);
my %wdays_txt_pl = (
    'Mon' => 'Pon',
    'Tue' => 'Wt',
    'Wed' => 'Śr',
    'Thu' => 'Czw',
    'Fri' => 'Pt',
    'Sat' => 'Sob',
    'Sun' => 'Nie'
);
my %wdays_txt_it = (
    'Mon' => 'Lun',
    'Tue' => 'Mar',
    'Wed' => 'Mer',
    'Thu' => 'Gio',
    'Fri' => 'Ven',
    'Sat' => 'Sab',
    'Sun' => 'Dom'
);

my %status_items_txt_en = (
    0 => "Wind",
    1 => "Humidity",
    2 => "Temperature",
    3 => "Right Now",
    4 => "Weather forecast for "
);
my %status_items_txt_de = (
    0 => "Wind",
    1 => "Feuchtigkeit",
    2 => "Temperatur",
    3 => "Jetzt Sofort",
    4 => "Wettervorhersage für "
);
my %status_items_txt_nl = (
    0 => "Wind",
    1 => "Vochtigheid",
    2 => "Temperatuur",
    3 => "Actueel",
    4 => "Weersvoorspelling voor "
);
my %status_items_txt_fr = (
    0 => "Vent",
    1 => "Humidité",
    2 => "Température",
    3 => "Maintenant",
    4 => "Prévisions météo pour "
);
my %status_items_txt_pl = (
    0 => "Wiatr",
    1 => "Wilgotność",
    2 => "Temperatura",
    3 => "Teraz",
    4 => "Prognoza pogody w "
);
my %status_items_txt_it = (
    0 => "Vento",
    1 => "Umidità",
    2 => "Temperatura",
    3 => "Adesso",
    4 => "Previsioni del tempo per "
);

my %wdays_txt_i18n;
my @directions_txt_i18n;
my %pressure_trend_txt_i18n;
my %status_items_txt_i18n;

my @iconlist = (
    'storm',                  'storm',
    'storm',                  'thunderstorm',
    'thunderstorm',           'rainsnow',
    'sleet',                  'snow',
    'drizzle',                'drizzle',
    'icy',                    'chance_of_rain',
    'chance_of_rain',         'snowflurries',
    'chance_of_snow',         'heavysnow',
    'snow',                   'sleet',
    'sleet',                  'dust',
    'fog',                    'haze',
    'smoke',                  'flurries',
    'windy',                  'icy',
    'cloudy',                 'mostlycloudy_night',
    'mostlycloudy',           'partly_cloudy_night',
    'partly_cloudy',          'sunny',
    'sunny',                  'mostly_clear_night',
    'mostly_sunny',           'heavyrain',
    'sunny',                  'scatteredthunderstorms',
    'scatteredthunderstorms', 'scatteredthunderstorms',
    'scatteredshowers',       'heavysnow',
    'chance_of_snow',         'heavysnow',
    'partly_cloudy',          'heavyrain',
    'chance_of_snow',         'scatteredshowers'
);

###################################
sub Weather_LanguageInitialize {
    my $lang = shift;

    given ($lang) {
        when ('de') {
            %wdays_txt_i18n          = %wdays_txt_de;
            @directions_txt_i18n     = @directions_txt_de;
            %pressure_trend_txt_i18n = %pressure_trend_txt_de;
            %status_items_txt_i18n   = %status_items_txt_de;
        }

        when ('nl') {
            %wdays_txt_i18n          = %wdays_txt_nl;
            @directions_txt_i18n     = @directions_txt_nl;
            %pressure_trend_txt_i18n = %pressure_trend_txt_nl;
            %status_items_txt_i18n   = %status_items_txt_nl;
        }

        when ('fr') {
            %wdays_txt_i18n          = %wdays_txt_fr;
            @directions_txt_i18n     = @directions_txt_fr;
            %pressure_trend_txt_i18n = %pressure_trend_txt_fr;
            %status_items_txt_i18n   = %status_items_txt_fr;
        }

        when ('pl') {
            %wdays_txt_i18n          = %wdays_txt_pl;
            @directions_txt_i18n     = @directions_txt_pl;
            %pressure_trend_txt_i18n = %pressure_trend_txt_pl;
            %status_items_txt_i18n   = %status_items_txt_pl;
        }

        when ('it') {
            %wdays_txt_i18n          = %wdays_txt_it;
            @directions_txt_i18n     = @directions_txt_it;
            %pressure_trend_txt_i18n = %pressure_trend_txt_it;
            %status_items_txt_i18n   = %status_items_txt_it;
        }

        default {
            %wdays_txt_i18n          = %wdays_txt_en;
            @directions_txt_i18n     = @directions_txt_en;
            %pressure_trend_txt_i18n = %pressure_trend_txt_en;
            %status_items_txt_i18n   = %status_items_txt_en;
        }
    }

    return;
}

###################################
sub Weather_DebugCodes {
    my $lang = shift;

    my @YahooCodes_i18n = YahooWeatherAPI_getYahooCodes($lang);

    Debug "Weather Code List, see http://developer.yahoo.com/weather/#codes";
    for ( my $c = 0 ; $c <= 47 ; $c++ ) {
        Debug
          sprintf( "%2d %30s %30s", $c, $iconlist[$c], $YahooCodes_i18n[$c] );
    }

    return;
}

#####################################
sub Weather_Initialize {
    my $hash = shift;

    $hash->{DefFn}   = \&Weather_Define;
    $hash->{UndefFn} = \&Weather_Undef;
    $hash->{GetFn}   = \&Weather_Get;
    $hash->{SetFn}   = \&Weather_Set;
    $hash->{AttrFn}  = \&Weather_Attr;
    $hash->{AttrList} =
        'disable:0,1 '
      . 'forecast:multiple-strict,hourly,daily '
      . 'forecastLimit '
      . 'alerts:0,1 '
      . $readingFnAttributes;
    $hash->{NotifyFn}    = \&Weather_Notify;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

###################################

sub degrees_to_direction {
    my $degrees             = shift;
    my $directions_txt_i18n = shift;

    my $mod = int( ( ( $degrees + 11.25 ) % 360 ) / 22.5 );
    return $directions_txt_i18n->[$mod];
}

sub Weather_ReturnWithError {
    my $hash        = shift;
    my $responseRef = shift;

    my $name = $hash->{NAME};

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, 'lastError', $responseRef->{status} );

    foreach my $r ( keys %{$responseRef} ) {
        readingsBulkUpdate( $hash, $r, $responseRef->{$r} )
          if ( ref( $responseRef->{$r} ) ne 'HASH' );
    }
    readingsBulkUpdate( $hash, 'state',
            'API Maintainer: '
          . $responseRef->{apiMaintainer}
          . ' ErrorMsg: '
          . $responseRef->{status} );
    readingsEndUpdate( $hash, 1 );

    my $next = 60;    # $next= $hash->{INTERVAL};
    Weather_RearmTimer( $hash, gettimeofday() + $next );

    return;
}

sub Weather_DeleteForecastReadings {
    my $hash = shift;

    my $name                    = $hash->{NAME};
    my $forecastConfig          = Weather_ForcastConfig($hash);
    my $forecastLimit           = AttrVal( $name, 'forecastLimit', 5 ) + 1;
    my $forecastLimitNoForecast = 1;

    $forecastLimit = $forecastLimitNoForecast
      if ( !$forecastConfig->{daily} );
    CommandDeleteReading( undef,
        $name . ' ' . 'fc([' . $forecastLimit . '-9]|[0-9]{2})_.*' );

    $forecastLimit = $forecastLimitNoForecast
      if ( !$forecastConfig->{hourly} );
    CommandDeleteReading( undef,
        $name . ' ' . 'hfc([' . $forecastLimit . '-9]|[0-9]{2})_.*' );

    return;
}

sub Weather_DeleteAlertsReadings {
    my $hash        = shift;
    my $alertsLimit = shift // 0;

    my $name                = $hash->{NAME};
    my $alertsConfig        = Weather_ForcastConfig($hash);
    my $alertsLimitNoAlerts = 0;

    $alertsLimit = $alertsLimitNoAlerts
      if ( !$alertsConfig->{alerts} );

    CommandDeleteReading( undef,
        $name . ' ' . 'warn_([' . $alertsLimit . '-9]|[0-9]{2})_.*' );

    return;
}

sub Weather_RetrieveCallbackFn {
    my $name = shift;

    return
      unless ( IsDevice($name) );

    my $hash        = $defs{$name};
    my $responseRef = $hash->{fhem}->{api}->getWeather;

    if ( $responseRef->{status} eq 'ok' ) {
        Weather_WriteReadings( $hash, $responseRef );
    }
    else {
        Weather_ReturnWithError( $hash, $responseRef );
    }

    return;
}

sub Weather_ForcastConfig {
    my $hash = shift;

    my $name = $hash->{NAME};
    my %forecastConfig;

    $forecastConfig{hourly} =
      ( AttrVal( $name, 'forecast', '' ) =~ m{hourly}xms ? 1 : 0 );

    $forecastConfig{daily} =
      ( AttrVal( $name, 'forecast', '' ) =~ m{daily}xms ? 1 : 0 );

    $forecastConfig{alerts} = AttrVal( $name, 'alerts', 0 );

    return \%forecastConfig;
}

sub Weather_WriteReadings {
    my $hash    = shift;
    my $dataRef = shift;

    my $forecastConfig = Weather_ForcastConfig($hash);
    my $name           = $hash->{NAME};

    readingsBeginUpdate($hash);

    # housekeeping information
    readingsBulkUpdate( $hash, 'lastError', '' );
    foreach my $r ( keys %{$dataRef} ) {
        readingsBulkUpdate( $hash, $r, $dataRef->{$r} )
          if ( ref( $dataRef->{$r} ) ne 'HASH'
            && ref( $dataRef->{$r} ) ne 'ARRAY' );
        readingsBulkUpdate( $hash, '.license', $dataRef->{license}->{text} );
    }

    ### current
    if ( defined( $dataRef->{current} )
        && ref( $dataRef->{current} ) eq 'HASH' )
    {
        while ( my ( $r, $v ) = each %{ $dataRef->{current} } ) {
            readingsBulkUpdate( $hash, $r, $v )
              if ( ref( $dataRef->{$r} ) ne 'HASH'
                && ref( $dataRef->{$r} ) ne 'ARRAY' );
        }

        readingsBulkUpdate( $hash, 'icon',
            $iconlist[ $dataRef->{current}->{code} ] );
        if (   defined( $dataRef->{current}->{wind_direction} )
            && $dataRef->{current}->{wind_direction}
            && defined( $dataRef->{current}->{wind_speed} )
            && $dataRef->{current}->{wind_speed} )
        {
            my $wdir =
              degrees_to_direction( $dataRef->{current}->{wind_direction},
                \@directions_txt_i18n );
            readingsBulkUpdate( $hash, 'wind_condition',
                    'Wind: '
                  . $wdir . ' '
                  . $dataRef->{current}->{wind_speed}
                  . ' km/h' );
        }
    }

    ### forecast
    if ( ref( $dataRef->{forecast} ) eq 'HASH'
        && ( $forecastConfig->{hourly} || $forecastConfig->{daily} ) )
    {
        ## hourly
        if (   defined( $dataRef->{forecast}->{hourly} )
            && ref( $dataRef->{forecast}->{hourly} ) eq 'ARRAY'
            && scalar( @{ $dataRef->{forecast}->{hourly} } ) > 0
            && $forecastConfig->{hourly} )
        {
            my $i     = 0;
            my $limit = AttrVal( $name, 'forecastLimit', 5 );
            foreach my $fc ( @{ $dataRef->{forecast}->{hourly} } ) {
                $i++;
                my $f = "hfc" . $i . "_";

                while ( my ( $r, $v ) = each %{$fc} ) {
                    readingsBulkUpdate( $hash, $f . $r, $v )
                      if ( ref( $dataRef->{$r} ) ne 'HASH'
                        && ref( $dataRef->{$r} ) ne 'ARRAY' );
                }
                readingsBulkUpdate(
                    $hash,
                    $f . 'icon',
                    $iconlist[ $dataRef->{forecast}->{hourly}[ $i - 1 ]{code} ]
                );

                if (
                    defined(
                        $dataRef->{forecast}->{hourly}[ $i - 1 ]{wind_direction}
                    )
                    && $dataRef->{forecast}->{hourly}[ $i - 1 ]{wind_direction}
                    && defined(
                        $dataRef->{forecast}->{hourly}[ $i - 1 ]{wind_speed}
                    )
                    && $dataRef->{forecast}->{hourly}[ $i - 1 ]{wind_speed}
                  )
                {
                    my $wdir = degrees_to_direction(
                        $dataRef->{forecast}
                          ->{hourly}[ $i - 1 ]{wind_direction},
                        \@directions_txt_i18n
                    );
                    readingsBulkUpdate(
                        $hash,
                        $f . 'wind_condition',
                        'Wind: '
                          . $wdir . ' '
                          . $dataRef->{forecast}->{hourly}[ $i - 1 ]{wind_speed}
                          . ' km/h'
                    );
                }

                last if ( $i == $limit && $limit > 0 );
            }
        }

        ## daily
        if (   defined( $dataRef->{forecast}->{daily} )
            && ref( $dataRef->{forecast}->{daily} ) eq 'ARRAY'
            && scalar( @{ $dataRef->{forecast}->{daily} } ) > 0
            && $forecastConfig->{daily} )
        {
            my $i     = 0;
            my $limit = AttrVal( $name, 'forecastLimit', 5 );
            foreach my $fc ( @{ $dataRef->{forecast}->{daily} } ) {
                $i++;
                my $f = "fc" . $i . "_";

                while ( my ( $r, $v ) = each %{$fc} ) {
                    readingsBulkUpdate( $hash, $f . $r, $v )
                      if ( ref( $dataRef->{$r} ) ne 'HASH'
                        && ref( $dataRef->{$r} ) ne 'ARRAY' );
                }
                readingsBulkUpdate(
                    $hash,
                    $f . 'icon',
                    $iconlist[ $dataRef->{forecast}->{daily}[ $i - 1 ]{code} ]
                );

                if (
                    defined(
                        $dataRef->{forecast}->{daily}[ $i - 1 ]{wind_direction}
                    )
                    && $dataRef->{forecast}->{daily}[ $i - 1 ]{wind_direction}
                    && defined(
                        $dataRef->{forecast}->{daily}[ $i - 1 ]{wind_speed}
                    )
                    && $dataRef->{forecast}->{daily}[ $i - 1 ]{wind_speed}
                  )
                {
                    my $wdir = degrees_to_direction(
                        $dataRef->{forecast}->{daily}[ $i - 1 ]{wind_direction},
                        \@directions_txt_i18n
                    );
                    readingsBulkUpdate(
                        $hash,
                        $f . 'wind_condition',
                        'Wind: '
                          . $wdir . ' '
                          . $dataRef->{forecast}->{daily}[ $i - 1 ]{wind_speed}
                          . ' km/h'
                    );
                }

                last if ( $i == $limit && $limit > 0 );
            }
        }
    }

    ### alerts
    if (   defined( $dataRef->{alerts} )
        && ref( $dataRef->{alerts} ) eq 'ARRAY'
        && scalar( @{ $dataRef->{alerts} } ) > 0
        && $forecastConfig->{alerts} )
    {
        my $i = 0;
        foreach my $warn ( @{ $dataRef->{alerts} } ) {
            my $w = "warn_" . $i . "_";

            while ( my ( $r, $v ) = each %{$warn} ) {
                readingsBulkUpdate( $hash, $w . $r, $v )
                  if ( ref( $dataRef->{$r} ) ne 'HASH'
                    && ref( $dataRef->{$r} ) ne 'ARRAY' );
            }

            $i++;
        }

        Weather_DeleteAlertsReadings( $hash,
            scalar( @{ $dataRef->{alerts} } ) );
        readingsBulkUpdate( $hash, 'warnCount',
            scalar( @{ $dataRef->{alerts} } ) );
    }
    else {
        Weather_DeleteAlertsReadings($hash);
        readingsBulkUpdate( $hash, 'warnCount',
            scalar( @{ $dataRef->{alerts} } ) )
          if ( defined( $dataRef->{alerts} )
            && ref( $dataRef->{alerts} ) eq 'ARRAY' );
    }

    ### state
    my $val = 'T: '
      . $dataRef->{current}->{temperature} . ' °C' . ' '
      . substr( $status_items_txt_i18n{1}, 0, 1 ) . ': '
      . $dataRef->{current}->{humidity} . ' %' . ' '
      . substr( $status_items_txt_i18n{0}, 0, 1 ) . ': '
      . $dataRef->{current}->{wind} . ' km/h' . ' P: '
      . $dataRef->{current}->{pressure} . ' hPa';

    Log3 $hash, 4, "$name: $val";
    readingsBulkUpdate( $hash, 'state', $val );

    readingsEndUpdate( $hash, 1 );

    Weather_RearmTimer( $hash, gettimeofday() + $hash->{INTERVAL} );

    return;

}

###################################
sub Weather_GetUpdate {
    my $hash = shift;

    my $name = $hash->{NAME};

    if ( IsDisabled($name) ) {
        Log3 $hash, 5,
          "Weather $name: retrieval of weather data is disabled by attribute.";
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "pubDateComment", "disabled by attribute" );
        readingsBulkUpdate( $hash, "validity",       "stale" );
        readingsEndUpdate( $hash, 1 );
        Weather_RearmTimer( $hash, gettimeofday() + $hash->{INTERVAL} );
    }
    else {
        $hash->{fhem}->{api}->setRetrieveData;
    }

    return;
}

###################################
sub Weather_Get {
    my $hash = shift // return;
    my $aRef = shift // return;

    my $name    = shift @$aRef // return;
    my $reading = shift @$aRef // return;
    my $value;

    if ( defined( $hash->{READINGS}->{$reading} ) ) {
        $value = $hash->{READINGS}->{$reading}->{VAL};
    }
    else {
        my $rt = '';
        if ( defined( $hash->{READINGS} ) ) {
            $rt = join( ":noArg ", sort keys %{ $hash->{READINGS} } );
        }

        return "Unknown reading $reading, choose one of " . $rt;
    }

    return "$name $reading => $value";
}

###################################
sub Weather_Set {
    my $hash = shift // return;
    my $aRef = shift // return;

    my $name = shift @$aRef // return;
    my $cmd  = shift @$aRef
      // return qq{"set $name" needs at least one argument};

    # usage check
    if ( scalar( @{$aRef} ) == 0
        && $cmd eq 'update' )
    {
        Weather_DisarmTimer($hash);
        Weather_GetUpdate($hash);

        return;
    }
    elsif ( scalar( @{$aRef} ) == 1
        && $cmd eq "newLocation" )
    {
        if (   $hash->{API} eq 'DarkSkyAPI'
            || $hash->{API} eq 'OpenWeatherMapAPI'
            || $hash->{API} eq 'wundergroundAPI' )
        {
            my ( $lat, $long );
            ( $lat, $long ) = split( ',', $aRef->[0] )
              if ( defined( $aRef->[0] ) && $aRef->[0] );
            ( $lat, $long ) = split( ',', $hash->{fhem}->{LOCATION} )
              unless ( defined($lat)
                && defined($long)
                && $lat  =~ m{(-?\d+(\.\d+)?)}xms
                && $long =~ m{(-?\d+(\.\d+)?)}xms );

            $hash->{fhem}->{api}->setLocation( $lat, $long );
            Weather_DisarmTimer($hash);
            Weather_GetUpdate($hash);
            return;
        }
        else { return 'this API is not ' . $aRef->[0] . ' supported' }
    }
    else {
        return "Unknown argument $cmd, choose one of update:noArg newLocation";
    }
}

###################################
sub Weather_RearmTimer {
    my $hash = shift;
    my $t    = shift;

    Log3( $hash, 4, "Weather $hash->{NAME}: Rearm new Timer" );
    InternalTimer( $t, "Weather_GetUpdate", $hash, 0 );

    return;
}

sub Weather_DisarmTimer {
    my $hash = shift;

    RemoveInternalTimer($hash);

    return;
}

sub Weather_Notify {
    my $hash = shift;
    my $dev  = shift;

    my $name = $hash->{NAME};
    my $type = $hash->{TYPE};

    return if ( $dev->{NAME} ne "global" );

    # set forcast and alerts values to api object
    if ( grep { /^MODIFIED.$name$/x } @{ $dev->{CHANGED} } ) {
        $hash->{fhem}->{api}->setForecast( AttrVal( $name, 'forecast', '' ) );
        $hash->{fhem}->{api}->setAlerts( AttrVal( $name, 'alerts', 0 ) );

        Weather_GetUpdate($hash);
    }

    return
      if (
        !grep {
/^INITIALIZED|REREADCFG|DELETEATTR.$name.disable|ATTR.$name.disable.[0-1]$/x
        } @{ $dev->{CHANGED} }
      );

    # update weather after initialization or change of configuration
    # wait 10 to 29 seconds to avoid congestion due to concurrent activities
    Weather_DisarmTimer($hash);
    my $delay = 10 + int( rand(20) );

    Log3 $hash, 5,
"Weather $name: FHEM initialization or rereadcfg triggered update, delay $delay seconds.";
    Weather_RearmTimer( $hash, gettimeofday() + $delay );

    ### quick run GetUpdate then Demo
    Weather_GetUpdate($hash)
      if ( defined( $hash->{APIKEY} ) && lc( $hash->{APIKEY} ) eq 'demo' );

    return;
}

#####################################
sub Weather_Define {
    my $hash = shift // return;
    my $aRef = shift // return;
    my $hRef = shift // undef;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    my $usage =
"syntax: define <name> Weather [API=<API>] [apikey=<apikey>] [location=<location>] [interval=<interval>] [lang=<lang>]";

    # check minimum syntax
    return $usage unless ( scalar @{$aRef} == 2 );
    my $name = $aRef->[0];

    my $location = $hRef->{location} // undef;
    my $apikey   = $hRef->{apikey}   // undef;
    my $lang     = $hRef->{lang}     // undef;
    my $interval = $hRef->{interval} // 3600;
    my $API      = $hRef->{API}      // "DarkSkyAPI,cachemaxage:600";

    # evaluate API options
    my ( $api, $apioptions ) = split( ',', $API, 2 );
    $apioptions = "" unless ( defined($apioptions) );
    eval { require 'FHEM/APIs/Weather/' . $api . '.pm'; };
    return "$name: cannot load API $api: $@" if ($@);

    $hash->{NOTIFYDEV}          = "global";
    $hash->{fhem}->{interfaces} = "temperature;humidity;wind";
    $hash->{fhem}->{LOCATION}   = (
        ( defined($location) && $location )
        ? $location
        : AttrVal( 'global', 'latitude', 'error' ) . ','
          . AttrVal( 'global', 'longitude', 'error' )
    );
    $hash->{INTERVAL} = $interval;
    $hash->{LANG}     = (
        ( defined($lang) && $lang )
        ? $lang
        : lc( AttrVal( 'global', 'language', 'de' ) )
    );
    $hash->{API}                = $api;
    $hash->{MODEL}              = $api;
    $hash->{APIKEY}             = $apikey;
    $hash->{APIOPTIONS}         = $apioptions;
    $hash->{VERSION}            = version->parse($VERSION)->normal;
    $hash->{fhem}->{allowCache} = 1;

    readingsSingleUpdate( $hash, 'current_date_time', TimeNow(), 0 );
    readingsSingleUpdate( $hash, 'current_date_time', 'none',    0 );

    readingsSingleUpdate( $hash, 'state', 'Initialized', 1 );
    Weather_LanguageInitialize( $hash->{LANG} );

    my $apistring = 'FHEM::APIs::Weather::' . $api;
    $hash->{fhem}->{api} = $apistring->new(
        {
            devName    => $hash->{NAME},
            apikey     => $hash->{APIKEY},
            location   => $hash->{fhem}->{LOCATION},
            apioptions => $hash->{APIOPTIONS},
            language   => $hash->{LANG},
        }
    );

    return;
}

#####################################
sub Weather_Undef {
    my $hash = shift;
    my $arg  = shift;

    RemoveInternalTimer($hash);
    return;
}

sub Weather_Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    given ($attrName) {
        when ('forecast') {
            if ( $cmd eq 'set' ) {
                $hash->{fhem}->{api}->setForecast($attrVal);
            }
            elsif ( $cmd eq 'del' ) {
                $hash->{fhem}->{api}->setForecast();
            }

            InternalTimer( gettimeofday() + 0.5,
                \&Weather_DeleteForecastReadings, $hash );
        }

        when ('forecastLimit') {
            InternalTimer( gettimeofday() + 0.5,
                \&Weather_DeleteForecastReadings, $hash );
        }

        when ('alerts') {
            if ( $cmd eq 'set' ) {
                $hash->{fhem}->{api}->setAlerts($attrVal);
            }
            elsif ( $cmd eq 'del' ) {
                $hash->{fhem}->{api}->setAlerts();
            }

            InternalTimer( gettimeofday() + 0.5,
                \&Weather_DeleteAlertsReadings, $hash );
        }
    }

    return;
}

#####################################

# Icon Parameter

Readonly my $ICONWIDTH => 175;
Readonly my $ICONSCALE => 0.5;

#####################################

sub WeatherIconIMGTag {
    my $icon = shift;

    my $width = int( $ICONSCALE * $ICONWIDTH );
    my $url   = FW_IconURL("weather/$icon");
    my $style = " width=$width";

    return "<img src=\"$url\"$style alt=\"$icon\">";
}

#####################################

sub WeatherAsHtmlV {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = Weather_CheckOptions( $d, $op1, $op2 );

    my $h     = $defs{$d};
    my $width = int( $ICONSCALE * $ICONWIDTH );

    my $ret = '<table class="weather">';
    my $fc;
    if (
        defined($f)
        && (   $f eq 'h'
            || $f eq 'd' )
      )
    {
        $fc = ( $f eq 'd' ? 'fc' : 'hfc' );
    }
    else {
        $fc = (
            (
                defined( $h->{READINGS}->{fc1_day_of_week} )
                  && $h->{READINGS}->{fc1_day_of_week}
            ) ? 'fc' : 'hfc'
        );
    }

    $ret .= sprintf(
'<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue">%s<br>%s°C  %s%%<br>%s</td></tr>',
        $width,
        WeatherIconIMGTag( ReadingsVal( $d, "icon", "" ) ),
        ReadingsVal( $d, "condition",      "" ),
        ReadingsVal( $d, "temp_c",         "" ),
        ReadingsVal( $d, "humidity",       "" ),
        ReadingsVal( $d, "wind_condition", "" )
    );

    for ( my $i = 1 ; $i < $items ; $i++ ) {
        if ( defined( $h->{READINGS}->{"${fc}${i}_low_c"} )
            && $h->{READINGS}->{"${fc}${i}_low_c"} )
        {
            $ret .= sprintf(
'<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: %s</span><br><span class="weatherMin">min %s°C</span> <span class="weatherMax">max %s°C</span><br>%s</td></tr>',
                $width,
                WeatherIconIMGTag( ReadingsVal( $d, "${fc}${i}_icon", "" ) ),
                ReadingsVal( $d, "${fc}${i}_day_of_week",    "" ),
                ReadingsVal( $d, "${fc}${i}_condition",      "" ),
                ReadingsVal( $d, "${fc}${i}_low_c",          " - " ),
                ReadingsVal( $d, "${fc}${i}_high_c",         " - " ),
                ReadingsVal( $d, "${fc}${i}_wind_condition", " - " )
            );
        }
        else {
            $ret .= sprintf(
'<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: %s</span><br><span class="weatherTemp"> %s°C</span><br>%s</td></tr>',
                $width,
                WeatherIconIMGTag( ReadingsVal( $d, "${fc}${i}_icon", "" ) ),
                ReadingsVal( $d, "${fc}${i}_day_of_week",    "" ),
                ReadingsVal( $d, "${fc}${i}_condition",      "" ),
                ReadingsVal( $d, "${fc}${i}_temperature",    " - " ),
                ReadingsVal( $d, "${fc}${i}_wind_condition", " - " )
            );
        }
    }

    $ret .= "</table>";
    return $ret;
}

sub WeatherAsHtml {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = Weather_CheckOptions( $d, $op1, $op2 );

    return WeatherAsHtmlV( $d, $f, $items );
}

sub WeatherAsHtmlH {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = Weather_CheckOptions( $d, $op1, $op2 );

    my $h     = $defs{$d};
    my $width = int( $ICONSCALE * $ICONWIDTH );

    my $format =
'<td><table border=1><tr><td class="weatherIcon" width=%d>%s</td></tr><tr><td class="weatherValue">%s</td></tr><tr><td class="weatherValue">%s°C %s%%</td></tr><tr><td class="weatherValue">%s</td></tr></table></td>';

    my $ret = '<table class="weather">';
    my $fc;
    if (
        defined($f)
        && (   $f eq 'h'
            || $f eq 'd' )
      )
    {
        $fc = ( $f eq 'd' ? 'fc' : 'hfc' );
    }
    else {
        $fc = (
            (
                defined( $h->{READINGS}->{fc1_day_of_week} )
                  && $h->{READINGS}->{fc1_day_of_week}
            ) ? 'fc' : 'hfc'
        );
    }

    # icons
    $ret .= sprintf( '<tr><td class="weatherIcon" width=%d>%s</td>',
        $width, WeatherIconIMGTag( ReadingsVal( $d, "icon", "" ) ) );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        $ret .= sprintf( '<td class="weatherIcon" width=%d>%s</td>',
            $width,
            WeatherIconIMGTag( ReadingsVal( $d, "${fc}${i}_icon", "" ) ) );
    }
    $ret .= '</tr>';

    # condition
    $ret .= sprintf( '<tr><td class="weatherDay">%s</td>',
        ReadingsVal( $d, "condition", "" ) );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        $ret .= sprintf(
            '<td class="weatherDay">%s: %s</td>',
            ReadingsVal( $d, "${fc}${i}_day_of_week", "" ),
            ReadingsVal( $d, "${fc}${i}_condition",   "" )
        );
    }
    $ret .= '</tr>';

    # temp/hum | min
    $ret .= sprintf(
        '<tr><td class="weatherMin">%s°C %s%%</td>',
        ReadingsVal( $d, "temp_c",   "" ),
        ReadingsVal( $d, "humidity", "" )
    );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        if ( defined( $h->{READINGS}->{"${fc}${i}_low_c"} )
            && $h->{READINGS}->{"${fc}${i}_low_c"} )
        {
            $ret .= sprintf( '<td class="weatherMin">min %s°C</td>',
                ReadingsVal( $d, "${fc}${i}_low_c", " - " ) );
        }
        else {
            $ret .= sprintf( '<td class="weatherMin"> %s°C</td>',
                ReadingsVal( $d, "${fc}${i}_temperature", " - " ) );
        }
    }

    $ret .= '</tr>';

    # wind | max
    $ret .= sprintf( '<tr><td class="weatherMax">%s</td>',
        ReadingsVal( $d, "wind_condition", "" ) );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        if ( defined( $h->{READINGS}->{"${fc}${i}_high_c"} )
            && $h->{READINGS}->{"${fc}${i}_high_c"} )
        {
            $ret .= sprintf( '<td class="weatherMax">max %s°C</td>',
                ReadingsVal( $d, "${fc}${i}_high_c", " - " ) );
        }
    }

    $ret .= "</tr></table>";

    return $ret;
}

sub WeatherAsHtmlD {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = Weather_CheckOptions( $d, $op1, $op2 );

    if ($FW_ss) {
        WeatherAsHtmlV( $d, $f, $items );
    }
    else {
        WeatherAsHtmlH( $d, $f, $items );
    }

    return;
}

sub Weather_CheckOptions {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    return "$d is not a Weather instance<br>"
      if ( !$defs{$d} || $defs{$d}->{TYPE} ne "Weather" );

    my $hash  = $defs{$d};
    my $items = $op2;
    my $f     = $op1;

    if ( defined($op1) && $op1 && $op1 =~ m{[0-9]}xms ) { $items = $op1; }
    if ( defined($op2) && $op2 && $op2 =~ m{[dh]}xms )  { $f     = $op2; }

    $f     =~ tr/dh/./cd  if ( defined $f      && $f );
    $items =~ tr/0-9/./cd if ( defined($items) && $items );

    $items = AttrVal( $d, 'forecastLimit', 5 )
      if ( !$items );

    my $forecastConfig = Weather_ForcastConfig($hash);
    $f = (
        $forecastConfig->{daily}
        ? 'd'
        : ( $forecastConfig->{daily} && $forecastConfig->{hourly} ? $f : 'h' )
    ) if !( defined($f) and $f );

    $f = 'h' if ( !$f || length($f) > 1 );

    return ( $f, $items + 1 );
}

#####################################

1;

=pod
=item device
=item summary provides current weather condition and forecast
=item summary_DE stellt Wetterbericht und -vorhersage bereit
=begin html

<a id="Weather"></a>
<h3>Weather</h3>
<ul>
  Note: you need the JSON perl module. Use <code>apt-get install
  libjson-perl</code> on Debian and derivatives.<p><p>

  The Weather module works with various weather APIs:
  <ul>
    <li>DarkSky (<a href="https://darksky.net">web site</a>, standard)</li>
    <li>OpenWeatherMap (<a href="https://openweathermap.org/">web site)</a></li>
    <li>Wunderground (<a href="https://www.wunderground.com/member/api-keys">web site)</a></li>
  </ul>
  <br>
  Such a virtual Weather device periodically gathers current and forecast
  weather conditions from the chosen weather API.<br><br>

  <a id="Weather-define"></a>
  <h4>Define</h4><br><br>
    <ul>
      <code>define &lt;name&gt; Weather [API=&lt;API&gt;[,&lt;apioptions&gt;]] [apikey=&lt;apikey&gt;]
       [location=&lt;location&gt;] [interval=&lt;interval&gt;] [lang=&lt;lang&gt;]</code><br><br>


       The parameters have the following meanings:<br>

       <table>
       <tr><td><code>API</code></td><td>name of the weather API, e.g. <code>DarkSkyAPI</code></td></tr>
       <tr><td><code>apioptions</code></td><td>indivual options for the chosen API</td></tr>
       <tr><td><code>apikey</code></td><td>key for the chosen API</td></tr>
       <tr><td><code>location</code></td><td>location for the weather forecast;
         e.g. coordinates, a town name or an ID, depending on the chosen API</td></tr>
       <tr><td><code>interval</code></td><td>duration in seconds between updates</td></tr>
       <tr><td><code>lang</code></td><td>language of the forecast: <code>de</code>,
         <code>en</code>, <code>pl</code>, <code>fr</code>, <code>it</code> or <code>nl</code></td></tr>
       </table>
       <p>

    A very simple definition is:<br><br>
    <code>define &lt;name&gt; Weather apikey=&lt;DarkSkyAPISecretKey&gt;</code><br><br>
    This uses the Dark Sky API with an individual key that you need to
    retrieve from the Dark Sky web site.<p><p>

    Examples:
    <pre>
      define Forecast Weather apikey=987498ghjgf864
      define MyWeather Weather API=OpenWeatherMapAPI,cachemaxage:600 apikey=09878945fdskv876 location=52.4545,13.4545 interval=3600 lang=de
      define <name> Weather API=wundergroundAPI,stationId:IHAUIDELB111 apikey=ed64ccc80f004556a4e3456567800b6324a
    </pre>


    API-specific documentation follows.<p>

        <h4>Dark Sky</h4><p>

        <table>
        <tr><td>API</td><td><code>DarkSkyAPI</code></td></tr>
        <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code><br>duration
          in seconds to retrieve the forecast from the cache instead from the API</td></tr>
        <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code><br>
          geographic coordinates in degrees of the location for which the
          weather is forecast; if missing, the values of the attributes
          of the <code>global</code> device are taken, if these exist.</td></tr>
        </table>
        <p><p>

        <h4>OpenWeatherMap</h4><p>

        <table>
        <tr><td>API</td><td><code>OpenWeatherMapAPI</code></td></tr>
        <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code><br>duration
          in seconds to retrieve the forecast from the cache instead from the API</td>
          <td><code>version:&lt;version&gt;</code> API version which should be used.
          2.5 by default, 3.0 is still possible but only with an additional subscription</td>
          <td><code>endpoint:onecall</code> only to test whether the API key which not
          officially for onecall is not supported yet onecall via API version 2.5. IMPORTANT!!!
          apioption version must not be set to 3.0</td></tr>
        <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code><br>
          geographic coordinates in degrees of the location for which the
          weather is forecast; if missing, the values of the attributes
          of the <code>global</code> device are taken, if these exist.</td></tr>
        </table>
        <p><p>
        
        <h4>Wunderground</h4><p>

        <table>
        <tr><td>API</td><td><code>wundergroundAPI</code></td></tr>
        <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code><br>duration
          in seconds to retrieve the forecast from the cache instead from the API<br><code>stationId:ID-Num</code>
      <br>Station ID of the station to be read.</td></tr>
        <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code><br>
          geographic coordinates in degrees of the location for which the
          weather is forecast; if missing, the values of the attributes
          of the <code>global</code> device are taken, if these exist.</td></tr>
        </table>
        <p><p>

    The module provides four additional functions <code>WeatherAsHtml</code>,
    <code>WeatherAsHtmlV</code>, <code>WeatherAsHtmlH</code> and
    <code>WeatherAsHtmlD</code>. The former two functions are identical:
    they return the HTML code for a vertically arranged weather forecast.
    The third function returns the HTML code for a horizontally arranged
    weather forecast. The latter function dynamically picks the orientation
    depending on wether a smallscreen style is set (vertical layout) or not
    (horizontal layout). Each version accepts an additional paramter
    to limit the numer of icons to display.<br><br>
    Example:
    <pre>
      define MyWeatherWeblink weblink htmlCode { WeatherAsHtmlH("MyWeather","h",10) }
    </pre>


  </ul>
  <br>

  <a id="Weather-set"></a>
  <h4>Set</h4>
  <ul>
    <a id="Weather-set-update"></a>
    <li>
      <i>set &lt;name&gt; update</i><br><br>

      Forces the retrieval of the weather data. The next automatic retrieval is scheduled to occur
      <code>interval</code> seconds later.
    </li>
    <a id="Weather-set-newLocation"></a>
    <li>
      <i>set &lt;name&gt; newLocation latitude,longitude</i><br><br>
      
      set a new temporary location.
      the value pair Latitude Longitude is separated by a comma.
      if no value is entered (empty value), the location detected by definition is automatically taken.<br><br>
    </li>
  </ul>
  <br>

  <a id="Weather-get"></a>
  <h4>Get</h4>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>

    Valid readings and their meaning (? can be one of 1, 2, 3, 4, 5 and stands
    for today, tomorrow, etc.):<br>
    <table>
    <a id="Weather-get-.license"></a>
    <tr><td>.license</td><td>license of the API provider, if available</td></tr>
    <a id="Weather-get-city"></a>
    <tr><td>city</td><td>name of town returned for location</td></tr>
    <a id="Weather-get-code"></a>
    <tr><td>code</td><td>current condition code</td></tr>
    <a id="Weather-get-condition"></a>
    <tr><td>condition</td><td>current condition</td></tr>
    <a id="Weather-get-current_date_time"></a>
    <tr><td>current_date_time</td><td>last update of forecast on server</td></tr>
     <a id="Weather-get-fc?_code"></a>
    <tr><td>fc?_code</td><td>forecast condition code</td></tr>
    <a id="Weather-get-fc?_condition"></a>
    <tr><td>fc?_condition</td><td>forecast condition</td></tr>
    <a id="Weather-get-fc?_day_of_week"></a>
    <tr><td>fc?_day_of_week</td><td>day of week for day +?</td></tr>
    <a id="Weather-get-fc?_high_c"></a>
    <tr><td>fc?_high_c</td><td>forecasted daily high in degrees centigrade</td></tr>
    <a id="Weather-get-fc?_icon"></a>
    <tr><td>fc?_icon</td><td>forecast icon</td></tr>
    <a id="Weather-get-fc?_low_c"></a>
    <tr><td>fc?_low_c</td><td>forecasted daily low in degrees centigrade</td></tr>
    <a id="Weather-get-humidity"></a>
    <tr><td>humidity</td><td>current humidity in %</td></tr>
    <a id="Weather-get-icon"></a>
    <tr><td>icon</td><td>relative path for current icon</td></tr>
    <a id="Weather-get-pressure"></a>
    <tr><td>pressure</td><td>air pressure in hPa</td></tr>
    <a id="Weather-get-pressure_trend"></a>
    <tr><td>pressure_trend</td><td>air pressure trend (0= steady, 1= rising, 2= falling)</td></tr>
    <a id="Weather-get-pressure_trend_txt"></a>
    <tr><td>pressure_trend_txt</td><td>textual representation of air pressure trend</td></tr>
    <a id="Weather-get-pressure_trend_sym"></a>
    <tr><td>pressure_trend_sym</td><td>symbolic representation of air pressure trend</td></tr>
    <a id="Weather-get-temperature"></a>
    <tr><td>temperature</td><td>current temperature in degrees centigrade</td></tr>
    <a id="Weather-get-temp_c"></a>
    <tr><td>temp_c</td><td>current temperature in degrees centigrade</td></tr>
    <a id="Weather-get-temp_f"></a>
    <tr><td>temp_f</td><td>current temperature in degrees Fahrenheit</td></tr>
    <a id="Weather-get-visibility"></a>
    <tr><td>visibility</td><td>visibility in km</td></tr>
    <a id="Weather-get-wind"></a>
    <tr><td>wind</td><td>wind speed in km/h</td></tr>
    <a id="Weather-get-wind_chill"></a>
    <tr><td>wind_chill</td><td>wind chill in degrees centigrade</td></tr>
    <a id="Weather-get-wind_condition"></a>
    <tr><td>wind_condition</td><td>wind direction and speed</td></tr>
    <a id="Weather-get-wind_direction"></a>
    <tr><td>wind_direction</td><td>direction wind comes from in degrees (0 = north wind)</td></tr>
    <a id="Weather-get-wind_speed"></a>
    <tr><td>wind_speed</td><td>same as wind</td></tr>
    </table>
    <br>
    The weekday of the forecast will be in the language of your FHEM system. Enter {$ENV{LANG}} into the FHEM command line to verify. If nothing is displayed or you see an unexpected language setting, add export LANG=de_DE.UTF-8 or something similar to your FHEM start script, restart FHEM and check again. If you get a locale warning when starting FHEM the required language pack might be missing. It can be installed depending on your OS and your preferences (e.g. dpkg-reconfigure locales, apt-get install language-pack-de or something similar).
    <br>
    Depending on the chosen API, other readings can be shown as well.
    The meaning of these readings can be determined from the API provider's
    documentation.

  </ul>
  <br>

  <a id="Weather-attr"></a>
  <h4>Attributes</h4>
  <ul>
    <a id="Weather-attr-disable"></a>
    <li><i>disable</i> - disables the retrieval of weather data - the timer runs according to schedule,
    though no data is requested from the API.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="Weather-attr-forecast"></a>
    <li><i>forecast</i> - hourly/daily, display of forecast data.</li>
    <a id="Weather-attr-forecastLimit"></a>
    <li><i>forecastLimit</i> - Number of forecast data records which should be written as a reading.</li>
    <a id="Weather-attr-alerts"></a>
    <li><i>alerts</i> - 0/1 should alert messages be written similar to Unwetterwarnung</li>
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a id="Weather"></a>
<h3>Weather</h3>
<ul>
    Hinweis: es wird das Perl-Modul JSON ben&ouml;tigt. Mit <code>apt-get install
    libjson-perl</code> kann es unter Debian und Derivaten installiert
    werden.<p><p>

    Das Weather-Modul arbeitet mit verschiedenen Wetter-APIs zusammen:
    <ul>
      <li>DarkSky (<a href="https://darksky.net">Webseite</a>, Standard)</li>
      <li>OpenWeatherMap (<a href="https://openweathermap.org/">Webseite)</a></li>
      <li>Wunderground (<a href="https://www.wunderground.com/member/api-keys">Webseite)</a></li>
    </ul>
    <br>
    Eine solche virtuelle Wetterstation sammelt periodisch aktuelle Wetterdaten
    und Wettervorhersagen aus dem verwendeten API.<br><br>

  <a id="Weather-define"></a>
  <h4>Define</h4><br><br>
  <ul>
    <code>define &lt;name&gt; Weather [API=&lt;API&gt;[,&lt;apioptions&gt;]] [apikey=&lt;apikey&gt;]
     [location=&lt;location&gt;] [interval=&lt;interval&gt;] [lang=&lt;lang&gt;]</code><br><br>

    Die Parameter haben die folgende Bedeutung:<br>

    <table>
    <tr><td><code>API</code></td><td>Name des Wetter-APIs, z.B. <code>DarkSkyAPI</code></td></tr>
    <tr><td><code>apioptions</code></td><td>Individuelle Optionen f&uuml;r das gew&auml;hlte API</td></tr>
    <tr><td><code>apikey</code></td><td>Schl&uuml;ssel f&uuml;r das gew&auml;hlte API</td></tr>
    <tr><td><code>location</code></td><td>Ort, f&uuml;r den das Wetter vorhergesagt wird.
      Abh&auml;ngig vom API z.B. die Koordinaten, ein Ortsname oder eine ID.</td></tr>
    <tr><td><code>interval</code></td><td>Dauer in Sekunden zwischen den einzelnen
      Aktualisierungen der Wetterdaten</td></tr>
    <tr><td><code>lang</code></td><td>Sprache der Wettervorhersage: <code>de</code>,
      <code>en</code>, <code>pl</code>, <code>fr</code>, <code>it</code> oder <code>nl</code></td></tr>
    </table>
    <p>

    Eine ganz einfache Definition ist:<br><br>
    <code>define &lt;name&gt; Weather apikey=&lt;DarkSkyAPISecretKey&gt;</code><br><br>

    Bei dieser Definition wird die API von Dark Sky verwendet mit einem
    individuellen Schl&uuml;ssel, den man sich auf der Webseite von Dark Sky
     beschaffen muss.<p><p>

    Beispiele:
    <pre>
      define Forecast Weather apikey=987498ghjgf864
      define MyWeather Weather API=OpenWeatherMapAPI,cachemaxage:600 apikey=09878945fdskv876 location=52.4545,13.4545 interval=3600 lang=de
      define <name> Weather API=wundergroundAPI,stationId:IHAUIDELB111 apikey=ed64ccc80f004556a4e3456567800b6324a
    </pre>

    Es folgt die API-spezifische Dokumentation.<p>

    <h4>Dark Sky</h4><p>

    <table>
    <tr><td>API</td><td><code>DarkSkyAPI</code></td></tr>
    <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code><br>Zeitdauer in
      Sekunden, innerhalb derer die Wettervorhersage nicht neu abgerufen
      sondern aus dem Cache zur&uuml;ck geliefert wird.</td></tr>
    <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code><br> Geographische Breite
      und L&auml;nge des Ortes in Grad, f&uuml;r den das Wetter vorhergesagt wird.
      Bei fehlender Angabe werden die Werte aus den gleichnamigen Attributen
      des <code>global</code>-Device genommen, sofern vorhanden.</td></tr>
    </table>
    <p><p>

    <h4>OpenWeatherMap</h4><p>

    <table>
    <tr><td>API</td><td><code>OpenWeatherMapAPI</code></td></tr>
    <tr>
      <td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code> Zeitdauer in
      Sekunden, innerhalb derer die Wettervorhersage nicht neu abgerufen
      sondern aus dem Cache zur&uuml;ck geliefert wird.</td>
      <td><code>version:&lt;version&gt;</code> API Version welche verwendet werden soll.
      Per Default 2.5, m&ouml;glich ist noch 3.0 aber nur mit Zusatzsubscription</td>
      <td><code>endpoint:onecall</code> nur zum testen ob der API Key welcher nicht
      offiziell für onecall ist nicht doch onecall über die API Version 2.5 unterst&uuml;tzt. WICHTIG!!!
      apioption version darf nicht auf 3.0 gesetzt werden</td>
    </tr>
    <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code> Geographische Breite
      und L&auml;nge des Ortes in Grad, f&uuml;r den das Wetter vorhergesagt wird.
      Bei fehlender Angabe werden die Werte aus den gleichnamigen Attributen
      des <code>global</code>-Device genommen, sofern vorhanden.</td></tr>
    </table>
    <p><p>
    
    <h4>Wunderground</h4><p>

    <table>
    <tr><td>API</td><td><code>wundergroundAPI</code></td></tr>
    <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code> Zeitdauer in
      Sekunden, innerhalb derer die Wettervorhersage nicht neu abgerufen
      sondern aus dem Cache zur&uuml;ck geliefert wird.<br><code>stationId:ID-Num</code>
      <br>die ID der Station von welcher die Daten gelesen werden sollen.</td></tr>
    <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code> Geographische Breite
      und L&auml;nge des Ortes in Grad, f&uuml;r den das Wetter vorhergesagt wird.
      Bei fehlender Angabe werden die Werte aus den gleichnamigen Attributen
      des <code>global</code>-Device genommen, sofern vorhanden.</td></tr>
    </table>
    <p><p>

    Das Modul unterst&uuml;tzt zus&auml;tzlich vier verschiedene Funktionen
    <code>WeatherAsHtml</code>, <code>WeatherAsHtmlV</code>,
    <code>WeatherAsHtmlH</code> und <code>WeatherAsHtmlD</code>.
    Die ersten beiden Funktionen sind identisch: sie erzeugen
    den HTML-Kode f&uuml;r eine vertikale Darstellung des Wetterberichtes.
    Die dritte Funktion liefert den HTML-Code f&uuml;r eine horizontale
    Darstellung des Wetterberichtes. Die letztgenannte Funktion w&auml;hlt
    automatisch eine Ausrichtung, die abh&auml;ngig davon ist, ob ein
    Smallcreen Style ausgew&auml;hlt ist (vertikale Darstellung) oder
    nicht (horizontale Darstellung). Alle vier Funktionen akzeptieren
    einen zus&auml;tzlichen optionalen Paramter um die Anzahl der
    darzustellenden Icons anzugeben.<br>
    Zus&auml;tzlich erlauben die Funktionen 2 und 3 noch einen dritten Parameter (d oder h) welcher die Forecast-Art (h-Hourly oder d-Daily) mit an gibt.<br>
    Wird der dritte Parameter verwendet muss auch der zweite Parameter f&uuml;r die Anzahl der darzustellenden Icons gesetzt werden.<br><br>
    Beispiel:
    <pre>
      define MyWeatherWeblink weblink htmlCode { WeatherAsHtmlH("MyWeather","h",10) }
    </pre>

  </ul>
  <br>

  <a id="Weather-set"></a>
    <h4>Set</h4>
  <ul>
    <a id="Weather-set-update"></a>
    <li><i>set &lt;name&gt; update</i><br><br>
        Erzwingt eine Abfrage der Wetterdaten. Die darauffolgende Abfrage
        wird gem&auml;&szlig; dem eingestellten
        Intervall <code>interval</code> Sekunden sp&auml;ter durchgef&uuml;hrt.
    </li>
    <a id="Weather-set-newLocation"></a>
    <li>
      <i>set &lt;name&gt; newLocation latitude,longitude</i><br><br>
      Gibt die M&ouml;glichkeit eine neue tempor&auml;re Location zu setzen.
      Das Wertepaar Latitude Longitude wird durch ein Komma getrennt &uuml;bergeben.
      Wird kein Wert mitgegebn (leere &Uuml;bergabe) wird automatisch die per Definition erkannte Location genommen<br><br>
    </li>
  </ul>
  <br>
  <a id="Weather-get"></a>
  <h4>Get</h4>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>

    G&uuml;ltige ausgelesene Daten (readings) und ihre Bedeutung (das ? kann einen der Werte 1, 2, 3 , 4 oder 5 annehmen und steht f&uuml;r heute, morgen, &uuml;bermorgen etc.):<br><br>
    <table>
    <a id="Weather-get-.license"></a>
    <tr><td>.license</td><td>Lizenz des jeweiligen API-Anbieters, sofern vorhanden</td></tr>
    <a id="Weather-get-city"></a>
    <tr><td>city</td><td>Name der Stadt, der f&uuml;r die location &uuml;bermittelt wird</td></tr>
    <a id="Weather-get-code"></a>
    <tr><td>code</td><td>Code f&uuml;r die aktuellen Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-condition"></a>
    <tr><td>condition</td><td>aktuelle Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-current_date_time"></a>
    <tr><td>current_date_time</td><td>Zeitstempel der letzten Aktualisierung der Wetterdaten vom Server</td></tr>
    <a id="Weather-get-fc?_code"></a>
    <tr><td>fc?_code</td><td>Code f&uuml;r die vorhergesagten Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-fc?_condition"></a>
    <tr><td>fc?_condition</td><td>vorhergesagte Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-fc?_day_of_week"></a>
    <tr><td>fc?_day_of_week</td><td>Wochentag des Tages, der durch ? dargestellt wird</td></tr>
    <a id="Weather-get-fc?_high_c"></a>
    <tr><td>fc?_high_c</td><td>vorhergesagte maximale Tagestemperatur in Grad Celsius</td></tr>
    <a id="Weather-get-fc?_icon"></a>
    <tr><td>fc?_icon</td><td>Icon f&uuml;r Vorhersage</td></tr>
    <a id="Weather-get-fc?_low_c"></a>
    <tr><td>fc?_low_c</td><td>vorhergesagte niedrigste Tagestemperatur in Grad Celsius</td></tr>
    <a id="Weather-get-humidity"></a>
    <tr><td>humidity</td><td>gegenw&auml;rtige Luftfeuchtgkeit in %</td></tr>
    <a id="Weather-get-icon"></a>
    <tr><td>icon</td><td>relativer Pfad f&uuml;r das aktuelle Icon</td></tr>
    <a id="Weather-get-pressure"></a>
    <tr><td>pressure</td><td>Luftdruck in hPa</td></tr>
    <a id="Weather-get-temperature"></a>
    <tr><td>temperature</td><td>gegenw&auml;rtige Temperatur in Grad Celsius</td></tr>
    <a id="Weather-get-temp_c"></a>
    <tr><td>temp_c</td><td>gegenw&auml;rtige Temperatur in Grad Celsius</td></tr>
    <a id="Weather-get-temp_f"></a>
    <tr><td>temp_f</td><td>gegenw&auml;rtige Temperatur in Grad Celsius</td></tr>
    <a id="Weather-get-visibility"></a>
    <tr><td>visibility</td><td>Sichtweite in km</td></tr>
    <a id="Weather-get-wind"></a>
    <tr><td>wind</td><td>Windgeschwindigkeit in km/h</td></tr>
    <a id="Weather-get-wind_condition"></a>
    <tr><td>wind_condition</td><td>Windrichtung und -geschwindigkeit</td></tr>
    <a id="Weather-get-wind_direction"></a>
    <tr><td>wind_direction</td><td>Gradangabe der Windrichtung (0 = Nordwind)</td></tr>
    <a id="Weather-get-wind_speed"></a>
    <tr><td>wind_speed</td><td>Windgeschwindigkeit in km/h (mit wind identisch)</td></tr>
    <a id="Weather-get-validity"></a>
    <tr><td>validity</td><td>stale, wenn der Ver&ouml;ffentlichungszeitpunkt auf dem entfernten Server vor dem Zeitpunkt der aktuellen Daten (readings) liegt</td></tr>
    </table>
    <br>
    Der Wochentag der Prognose wird in der Sprache Ihres FHEM-Systems angezeigt. Geben Sie zur Überprüfung {$ ENV {LANG}} in die Befehlszeile von FHEM ein. Wenn nichts angezeigt wird oder eine unerwartete Spracheinstellung angezeigt wird, fügen Sie export LANG = de_DE.UTF-8 oder etwas Ähnliches zu Ihrem FHEM-Startskript hinzu. Starten Sie FHEM erneut und überprüfen Sie es erneut. Wenn Sie beim Starten von FHEM eine Ländereinstellung erhalten, fehlt möglicherweise das erforderliche Sprachpaket. Sie kann abhängig von Ihrem Betriebssystem und Ihren Präferenzen installiert werden (z. B. Gebietsschemas dpkg-reconfigure, apt-get install language-pack-de oder ähnliches).
    <br>
    Je nach verwendeter API ist es durchaus m&ouml;glich, dass weitere
    Readings geschrieben werden. Die Bedeutung dieser Readings kann man
    der API-Beschreibung des Anbieters entnehmen.
  </ul>
  <br>

  <a id="Weather-attr"></a>
  <h4>Attribute</h4>
  <ul>
    <a id="Weather-attr-disable"></a>
    <li><i>disable</i> - stellt die Abfrage der Wetterdaten ab - der Timer l&auml;ft
    gem&auml;&szlig Plan doch es werden keine Daten vom
    API angefordert.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="Weather-attr-forecast"></a>
    <li><i>forecast</i> - hourly/daily, Anzeige von forecast Daten.</li>
    <a id="Weather-attr-forecastLimit"></a>
    <li><i>forecastLimit</i> - Anzahl der Forecast-Datens&auml;tze welche als Reading geschrieben werden sollen.</li>
    <a id="Weather-attr-alerts"></a>
    <li><i>alerts</i> - 0/1 Sollen Alert Meldungen &auml;nlich Unwetterwarnung geschrieben werden.</li>

  </ul>
  <br>
</ul>

=end html_DE

=for :application/json;q=META.json 59_Weather.pm
{
  "abstract": "Modul to provides current weather condition and forecast",
  "x_lang": {
    "de": {
      "abstract": ""
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Weather",
    "DarkSky",
    "OpenWeatherMap",
    "Underground"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v2.2.20",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "CoolTuxNet"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "JSON": 0,
        "Date::Parse": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut

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

package FHEM::Core::Weather;

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
sub _LanguageInitialize {
    return 0 unless ( __PACKAGE__ eq caller(0) );

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
## deprecated code of older versions
# sub DebugCodes {
#     my $lang = shift;

#     my @YahooCodes_i18n = YahooWeatherAPI_getYahooCodes($lang);

#     ::Debug "Weather Code List, see http://developer.yahoo.com/weather/#codes";
#     for ( my $c = 0 ; $c <= 47 ; $c++ ) {
#         ::Debug
#           sprintf( "%2d %30s %30s", $c, $iconlist[$c], $YahooCodes_i18n[$c] );
#     }

#     return;
# }

###################################

sub _degrees_to_direction {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $degrees             = shift;
    my $directions_txt_i18n = shift;

    my $mod = int( ( ( $degrees + 11.25 ) % 360 ) / 22.5 );
    return $directions_txt_i18n->[$mod];
}

sub _ReturnWithError {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $hash        = shift;
    my $responseRef = shift;

    my $name = $hash->{NAME};

    ::readingsBeginUpdate($hash);
    ::readingsBulkUpdate( $hash, 'lastError', $responseRef->{status} );

    foreach my $r ( keys %{$responseRef} ) {
        ::readingsBulkUpdate( $hash, $r, $responseRef->{$r} )
          if ( ref( $responseRef->{$r} ) ne 'HASH' );
    }
    ::readingsBulkUpdate( $hash, 'state',
            'API Maintainer: '
          . $responseRef->{apiMaintainer}
          . ' ErrorMsg: '
          . $responseRef->{status} );
    ::readingsEndUpdate( $hash, 1 );

    my $next = 60;    # $next= $hash->{INTERVAL};
    _RearmTimer( $hash, gettimeofday() + $next );

    return;
}

sub DeleteForecastreadings {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $hash = shift;

    my $name                    = $hash->{NAME};
    my $forecastConfig          = _ForcastConfig($hash);
    my $forecastLimit           = ::AttrVal( $name, 'forecastLimit', 5 ) + 1;
    my $forecastLimitNoForecast = 1;

    $forecastLimit = $forecastLimitNoForecast
      if ( !$forecastConfig->{daily} );
    ::CommandDeleteReading( undef,
        $name . ' ' . 'fc([' . $forecastLimit . '-9]|[0-9]{2})_.*' );

    $forecastLimit = $forecastLimitNoForecast
      if ( !$forecastConfig->{hourly} );
    ::CommandDeleteReading( undef,
        $name . ' ' . 'hfc([' . $forecastLimit . '-9]|[0-9]{2})_.*' );

    return;
}

sub DeleteAlertsreadings {

    my $hash        = shift;
    my $alertsLimit = shift // 0;

    my $name                = $hash->{NAME};
    my $alertsConfig        = _ForcastConfig($hash);
    my $alertsLimitNoAlerts = 0;

    $alertsLimit = $alertsLimitNoAlerts
      if ( !$alertsConfig->{alerts} );

    ::CommandDeleteReading( undef,
        $name . ' ' . 'warn_([' . $alertsLimit . '-9]|[0-9]{2})_.*' );

    return;
}

sub RetrieveCallbackFn {
    my $name = shift;

    return
      unless ( ::IsDevice($name) );

    my $hash        = $::defs{$name};
    my $responseRef = $hash->{fhem}->{api}->getWeather;

    if ( $responseRef->{status} eq 'ok' ) {
        _Writereadings( $hash, $responseRef );
    }
    else {
        _ReturnWithError( $hash, $responseRef );
    }

    return;
}

sub _ForcastConfig {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $hash = shift;

    my $name = $hash->{NAME};
    my %forecastConfig;

    $forecastConfig{hourly} =
      ( ::AttrVal( $name, 'forecast', '' ) =~ m{hourly}xms ? 1 : 0 );

    $forecastConfig{daily} =
      ( ::AttrVal( $name, 'forecast', '' ) =~ m{daily}xms ? 1 : 0 );

    $forecastConfig{alerts} = ::AttrVal( $name, 'alerts', 0 );

    return \%forecastConfig;
}

sub _Writereadings {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $hash    = shift;
    my $dataRef = shift;

    my $forecastConfig = _ForcastConfig($hash);
    my $name           = $hash->{NAME};

    ::readingsBeginUpdate($hash);

    # housekeeping information
    ::readingsBulkUpdate( $hash, 'lastError', '' );
    foreach my $r ( keys %{$dataRef} ) {
        ::readingsBulkUpdate( $hash, $r, $dataRef->{$r} )
          if ( ref( $dataRef->{$r} ) ne 'HASH'
            && ref( $dataRef->{$r} ) ne 'ARRAY' );
        ::readingsBulkUpdate( $hash, '.license', $dataRef->{license}->{text} );
    }

    ### current
    if ( defined( $dataRef->{current} )
        && ref( $dataRef->{current} ) eq 'HASH' )
    {
        while ( my ( $r, $v ) = each %{ $dataRef->{current} } ) {
            ::readingsBulkUpdate( $hash, $r, $v )
              if ( ref( $dataRef->{$r} ) ne 'HASH'
                && ref( $dataRef->{$r} ) ne 'ARRAY' );
        }

        ::readingsBulkUpdate( $hash, 'icon',
            $iconlist[ $dataRef->{current}->{code} ] );
        if (   defined( $dataRef->{current}->{wind_direction} )
            && $dataRef->{current}->{wind_direction}
            && defined( $dataRef->{current}->{wind_speed} )
            && $dataRef->{current}->{wind_speed} )
        {
            my $wdir =
              _degrees_to_direction( $dataRef->{current}->{wind_direction},
                \@directions_txt_i18n );
            ::readingsBulkUpdate( $hash, 'wind_condition',
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
            my $limit = ::AttrVal( $name, 'forecastLimit', 5 );
            foreach my $fc ( @{ $dataRef->{forecast}->{hourly} } ) {
                $i++;
                my $f = "hfc" . $i . "_";

                while ( my ( $r, $v ) = each %{$fc} ) {
                    ::readingsBulkUpdate( $hash, $f . $r, $v )
                      if ( ref( $dataRef->{$r} ) ne 'HASH'
                        && ref( $dataRef->{$r} ) ne 'ARRAY' );
                }
                ::readingsBulkUpdate(
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
                    my $wdir = _degrees_to_direction(
                        $dataRef->{forecast}
                          ->{hourly}[ $i - 1 ]{wind_direction},
                        \@directions_txt_i18n
                    );
                    ::readingsBulkUpdate(
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
            my $limit = ::AttrVal( $name, 'forecastLimit', 5 );
            foreach my $fc ( @{ $dataRef->{forecast}->{daily} } ) {
                $i++;
                my $f = "fc" . $i . "_";

                while ( my ( $r, $v ) = each %{$fc} ) {
                    ::readingsBulkUpdate( $hash, $f . $r, $v )
                      if ( ref( $dataRef->{$r} ) ne 'HASH'
                        && ref( $dataRef->{$r} ) ne 'ARRAY' );
                }
                ::readingsBulkUpdate(
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
                    my $wdir = _degrees_to_direction(
                        $dataRef->{forecast}->{daily}[ $i - 1 ]{wind_direction},
                        \@directions_txt_i18n
                    );
                    ::readingsBulkUpdate(
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
                ::readingsBulkUpdate( $hash, $w . $r, $v )
                  if ( ref( $dataRef->{$r} ) ne 'HASH'
                    && ref( $dataRef->{$r} ) ne 'ARRAY' );
            }

            $i++;
        }

        DeleteAlertsreadings( $hash, scalar( @{ $dataRef->{alerts} } ) );
        ::readingsBulkUpdate( $hash, 'warnCount',
            scalar( @{ $dataRef->{alerts} } ) );
    }
    else {
        DeleteAlertsreadings($hash);
        ::readingsBulkUpdate( $hash, 'warnCount',
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

    ::Log3 $hash, 4, "$name: $val";
    ::readingsBulkUpdate( $hash, 'state', $val );

    ::readingsEndUpdate( $hash, 1 );

    _RearmTimer( $hash, gettimeofday() + $hash->{INTERVAL} );

    return;

}

###################################
sub GetUpdate {
    my $hash = shift;

    my $name = $hash->{NAME};

    if ( ::IsDisabled($name) ) {
        ::Log3 $hash, 5,
          "Weather $name: retrieval of weather data is disabled by attribute.";
        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate( $hash, "pubDateComment",
            "disabled by attribute" );
        ::readingsBulkUpdate( $hash, "validity", "stale" );
        ::readingsEndUpdate( $hash, 1 );
        _RearmTimer( $hash, gettimeofday() + $hash->{INTERVAL} );
    }
    else {
        $hash->{fhem}->{api}->setRetrieveData;
    }

    return;
}

###################################
sub Get {
    my $hash = shift // return;
    my $aRef = shift // return;

    my $name    = shift @$aRef // return;
    my $reading = shift @$aRef // return;
    my $value;

    if ( defined( $hash->{readings}->{$reading} ) ) {
        $value = $hash->{readings}->{$reading}->{VAL};
    }
    else {
        my $rt = '';
        if ( defined( $hash->{readings} ) ) {
            $rt = join( ":noArg ", sort keys %{ $hash->{readings} } );
        }

        return "Unknown reading $reading, choose one of " . $rt;
    }

    return "$name $reading => $value";
}

###################################
sub Set {
    my $hash = shift // return;
    my $aRef = shift // return;

    my $name = shift @$aRef // return;
    my $cmd  = shift @$aRef
      // return qq{"set $name" needs at least one argument};

    # usage check
    if ( scalar( @{$aRef} ) == 0
        && $cmd eq 'update' )
    {
        _DisarmTimer($hash);
        GetUpdate($hash);

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
            _DisarmTimer($hash);
            GetUpdate($hash);
            return;
        }
        else { return 'this API is not ' . $aRef->[0] . ' supported' }
    }
    else {
        return "Unknown argument $cmd, choose one of update:noArg newLocation";
    }
}

###################################
sub _RearmTimer {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $hash = shift;
    my $t    = shift;

    ::Log3( $hash, 4, "Weather $hash->{NAME}: Rearm new Timer" );
    ::InternalTimer( $t, \&FHEM::Core::Weather::GetUpdate, $hash, 0 );

    return;
}

sub _DisarmTimer {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $hash = shift;

    ::RemoveInternalTimer($hash);

    return;
}

sub Notify {
    my $hash = shift;
    my $dev  = shift;

    my $name = $hash->{NAME};
    my $type = $hash->{TYPE};

    return if ( $dev->{NAME} ne "global" );

    # set forcast and alerts values to api object
    if ( grep { /^MODIFIED.$name$/x } @{ $dev->{CHANGED} } ) {
        $hash->{fhem}->{api}->setForecast( ::AttrVal( $name, 'forecast', '' ) );
        $hash->{fhem}->{api}->setAlerts( ::AttrVal( $name, 'alerts', 0 ) );

        GetUpdate($hash);
    }

    return
      if (
        !grep {
/^INITIALIZED|REREADCFG|DELETEATTR.$name.disable|ATTR.$name.disable.[0-1]$/x
        } @{ $dev->{CHANGED} }
      );

    # update weather after initialization or change of configuration
    # wait 10 to 29 seconds to avoid congestion due to concurrent activities
    _DisarmTimer($hash);
    my $delay = 10 + int( rand(20) );

    ::Log3 $hash, 5,
"Weather $name: FHEM initialization or rereadcfg triggered update, delay $delay seconds.";
    _RearmTimer( $hash, gettimeofday() + $delay );

    ### quick run GetUpdate then Demo
    GetUpdate($hash)
      if ( defined( $hash->{APIKEY} ) && lc( $hash->{APIKEY} ) eq 'demo' );

    return;
}

#####################################
sub Define {
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
        : ::AttrVal( 'global', 'latitude', 'error' ) . ','
          . ::AttrVal( 'global', 'longitude', 'error' )
    );
    $hash->{INTERVAL} = $interval;
    $hash->{LANG}     = (
        ( defined($lang) && $lang )
        ? $lang
        : lc( ::AttrVal( 'global', 'language', 'de' ) )
    );
    $hash->{API}                = $api;
    $hash->{MODEL}              = $api;
    $hash->{APIKEY}             = $apikey;
    $hash->{APIOPTIONS}         = $apioptions;
    $hash->{VERSION}            = version->parse($VERSION)->normal;
    $hash->{fhem}->{allowCache} = 1;

    ::readingsSingleUpdate( $hash, 'current_date_time', ::TimeNow(), 0 );
    ::readingsSingleUpdate( $hash, 'current_date_time', 'none',      0 );

    ::readingsSingleUpdate( $hash, 'state', 'Initialized', 1 );
    _LanguageInitialize( $hash->{LANG} );

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
sub Undef {
    my $hash = shift;
    my $arg  = shift;

    ::RemoveInternalTimer($hash);
    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $AttrVal ) = @_;
    my $hash = $::defs{$name};

    given ($attrName) {
        when ('forecast') {
            if ( $cmd eq 'set' ) {
                $hash->{fhem}->{api}->setForecast($AttrVal);
            }
            elsif ( $cmd eq 'del' ) {
                $hash->{fhem}->{api}->setForecast();
            }

            ::InternalTimer( gettimeofday() + 0.5,
                \&FHEM::Core::Weather::DeleteForecastreadings, $hash );
        }

        when ('forecastLimit') {
            ::InternalTimer( gettimeofday() + 0.5,
                \&FHEM::Core::Weather::DeleteForecastreadings, $hash );
        }

        when ('alerts') {
            if ( $cmd eq 'set' ) {
                $hash->{fhem}->{api}->setAlerts($AttrVal);
            }
            elsif ( $cmd eq 'del' ) {
                $hash->{fhem}->{api}->setAlerts();
            }

            ::InternalTimer( gettimeofday() + 0.5,
                \&FHEM::Core::Weather::DeleteAlertsreadings, $hash );
        }
    }

    return;
}

#####################################

# Icon Parameter

Readonly my $ICONWIDTH => 175;
Readonly my $ICONSCALE => 0.5;

#####################################

sub _WeatherIconIMGTag {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $icon = shift;

    my $width = int( $ICONSCALE * $ICONWIDTH );
    my $url   = ::FW_IconURL("weather/$icon");
    my $style = " width=$width";

    return "<img src=\"$url\"$style alt=\"$icon\">";
}

#####################################
sub ::WeatherAsHtmlV { goto &WeatherAsHtmlV }

sub WeatherAsHtmlV {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = _CheckOptions( $d, $op1, $op2 );

    my $h     = $::defs{$d};
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
                defined( $h->{readings}->{fc1_day_of_week} )
                  && $h->{readings}->{fc1_day_of_week}
            ) ? 'fc' : 'hfc'
        );
    }

    $ret .= sprintf(
'<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue">%s<br>%s°C  %s%%<br>%s</td></tr>',
        $width,
        _WeatherIconIMGTag( ::ReadingsVal( $d, "icon", "" ) ),
        ::ReadingsVal( $d, "condition",      "" ),
        ::ReadingsVal( $d, "temp_c",         "" ),
        ::ReadingsVal( $d, "humidity",       "" ),
        ::ReadingsVal( $d, "wind_condition", "" )
    );

    for ( my $i = 1 ; $i < $items ; $i++ ) {
        if ( defined( $h->{readings}->{"${fc}${i}_low_c"} )
            && $h->{readings}->{"${fc}${i}_low_c"} )
        {
            $ret .= sprintf(
'<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: %s</span><br><span class="weatherMin">min %s°C</span> <span class="weatherMax">max %s°C</span><br>%s</td></tr>',
                $width,
                _WeatherIconIMGTag( ::ReadingsVal( $d, "${fc}${i}_icon", "" ) ),
                ::ReadingsVal( $d, "${fc}${i}_day_of_week",    "" ),
                ::ReadingsVal( $d, "${fc}${i}_condition",      "" ),
                ::ReadingsVal( $d, "${fc}${i}_low_c",          " - " ),
                ::ReadingsVal( $d, "${fc}${i}_high_c",         " - " ),
                ::ReadingsVal( $d, "${fc}${i}_wind_condition", " - " )
            );
        }
        else {
            $ret .= sprintf(
'<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: %s</span><br><span class="weatherTemp"> %s°C</span><br>%s</td></tr>',
                $width,
                _WeatherIconIMGTag( ::ReadingsVal( $d, "${fc}${i}_icon", "" ) ),
                ::ReadingsVal( $d, "${fc}${i}_day_of_week",    "" ),
                ::ReadingsVal( $d, "${fc}${i}_condition",      "" ),
                ::ReadingsVal( $d, "${fc}${i}_temperature",    " - " ),
                ::ReadingsVal( $d, "${fc}${i}_wind_condition", " - " )
            );
        }
    }

    $ret .= "</table>";
    return $ret;
}

sub ::WeatherAsHtml { goto &WeatherAsHtml }

sub WeatherAsHtml {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = _CheckOptions( $d, $op1, $op2 );

    return WeatherAsHtmlV( $d, $f, $items );
}

sub ::WeatherAsHtmlH { goto &WeatherAsHtmlH }

sub WeatherAsHtmlH {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = _CheckOptions( $d, $op1, $op2 );

    my $h     = $::defs{$d};
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
                defined( $h->{readings}->{fc1_day_of_week} )
                  && $h->{readings}->{fc1_day_of_week}
            ) ? 'fc' : 'hfc'
        );
    }

    # icons
    $ret .= sprintf( '<tr><td class="weatherIcon" width=%d>%s</td>',
        $width, _WeatherIconIMGTag( ::ReadingsVal( $d, "icon", "" ) ) );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        $ret .= sprintf( '<td class="weatherIcon" width=%d>%s</td>',
            $width,
            _WeatherIconIMGTag( ::ReadingsVal( $d, "${fc}${i}_icon", "" ) ) );
    }
    $ret .= '</tr>';

    # condition
    $ret .= sprintf( '<tr><td class="weatherDay">%s</td>',
        ::ReadingsVal( $d, "condition", "" ) );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        $ret .= sprintf(
            '<td class="weatherDay">%s: %s</td>',
            ::ReadingsVal( $d, "${fc}${i}_day_of_week", "" ),
            ::ReadingsVal( $d, "${fc}${i}_condition",   "" )
        );
    }
    $ret .= '</tr>';

    # temp/hum | min
    $ret .= sprintf(
        '<tr><td class="weatherMin">%s°C %s%%</td>',
        ::ReadingsVal( $d, "temp_c",   "" ),
        ::ReadingsVal( $d, "humidity", "" )
    );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        if ( defined( $h->{readings}->{"${fc}${i}_low_c"} )
            && $h->{readings}->{"${fc}${i}_low_c"} )
        {
            $ret .= sprintf( '<td class="weatherMin">min %s°C</td>',
                ::ReadingsVal( $d, "${fc}${i}_low_c", " - " ) );
        }
        else {
            $ret .= sprintf( '<td class="weatherMin"> %s°C</td>',
                ::ReadingsVal( $d, "${fc}${i}_temperature", " - " ) );
        }
    }

    $ret .= '</tr>';

    # wind | max
    $ret .= sprintf( '<tr><td class="weatherMax">%s</td>',
        ::ReadingsVal( $d, "wind_condition", "" ) );
    for ( my $i = 1 ; $i < $items ; $i++ ) {
        if ( defined( $h->{readings}->{"${fc}${i}_high_c"} )
            && $h->{readings}->{"${fc}${i}_high_c"} )
        {
            $ret .= sprintf( '<td class="weatherMax">max %s°C</td>',
                ::ReadingsVal( $d, "${fc}${i}_high_c", " - " ) );
        }
    }

    $ret .= "</tr></table>";

    return $ret;
}

sub ::WeatherAsHtmlD { goto &WeatherAsHtmlD }

sub WeatherAsHtmlD {
    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    my ( $f, $items ) = _CheckOptions( $d, $op1, $op2 );
    my $ret;

    if ($FW_ss) {
        $ret = WeatherAsHtmlV( $d, $f, $items );
    }
    else {
        $ret = WeatherAsHtmlH( $d, $f, $items );
    }

    return $ret;
}

sub _CheckOptions {
    return 0 unless ( __PACKAGE__ eq caller(0) );

    my $d   = shift;
    my $op1 = shift;
    my $op2 = shift;

    return "$d is not a Weather instance<br>"
      if ( !$::defs{$d} || $::defs{$d}->{TYPE} ne "Weather" );

    my $hash  = $::defs{$d};
    my $items = $op2;
    my $f     = $op1;

    if ( defined($op1) && $op1 && $op1 =~ m{[0-9]}xms ) { $items = $op1; }
    if ( defined($op2) && $op2 && $op2 =~ m{[dh]}xms )  { $f     = $op2; }

    $f     =~ tr/dh/./cd  if ( defined $f      && $f );
    $items =~ tr/0-9/./cd if ( defined($items) && $items );

    $items = ::AttrVal( $d, 'forecastLimit', 5 )
      if ( !$items );

    my $forecastConfig = _ForcastConfig($hash);
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

__END__

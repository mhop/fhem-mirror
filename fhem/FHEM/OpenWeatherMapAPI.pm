# $Id$
###############################################################################
#
# Developed with Kate
#
#  (c) 2019 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to:
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License,or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
###############################################################################

### Beispielaufruf
# https://api.openweathermap.org/data/2.5/weather?lat=[lat]&lon=[long]&APPID=[API]   Current
# https://api.openweathermap.org/data/2.5/forecast?lat=[lat]&lon=[long]&APPID=[API]   Forecast
# https://openweathermap.org/weather-conditions     Icons und Conditions ID's

package OpenWeatherMapAPI;
use strict;
use warnings;
use FHEM::Meta;
use Data::Dumper;

FHEM::Meta::Load(__PACKAGE__);
use version 0.50; our $VERSION = $main::packages{OpenWeatherMapAPI}{META}{version};

package OpenWeatherMapAPI::Weather;
use strict;
use warnings;

use POSIX;
use HttpUtils;

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
};

if ($@) {
    $@ = undef;

    # try to use JSON wrapper
    #   for chance of better performance
    eval {

        # JSON preference order
        local $ENV{PERL_JSON_BACKEND} =
          'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
          unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

        require JSON;
        import JSON qw( decode_json encode_json );
        1;
    };

    if ($@) {
        $@ = undef;

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        };

        if ($@) {
            $@ = undef;

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            };

            if ($@) {
                $@ = undef;

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                };

                if ($@) {
                    $@ = undef;

                    # Fallback to JSON::backportPP in really rare cases
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                }
            }
        }
    }
}

my $missingModul = '';
eval "use Encode qw(encode_utf8);1" or $missingModul .= "Encode ";

# use Data::Dumper;    # for Debug only
## API URL
use constant URL     => 'https://api.openweathermap.org/data/2.5/';
## URL . 'weather?' for current data
## URL . 'forecast?' for forecast data

my %codes = (
    200 => 45,
    201 => 45,
    202 => 45,
    210 => 4,
    211 => 4,
    212 => 3,
    221 => 4,
    230 => 45,
    231 => 45,
    232 => 45,
    300 => 9,
    301 => 9,
    302 => 9,
    310 => 9,
    311 => 9,
    312 => 9,
    313 => 9,
    314 => 9,
    321 => 9,
    500 => 35,
    501 => 35,
    502 => 35,
    503 => 35,
    504 => 35,
    511 => 35,
    520 => 35,
    521 => 35,
    522 => 35,
    531 => 35,
    600 => 14,
    601 => 16,
    602 => 13,
    611 => 46,
    612 => 46,
    615 => 5,
    616 => 5,
    620 => 14,
    621 => 46,
    622 => 42,
    701 => 19,
    711 => 22,
    721 => 19,
    731 => 23,
    741 => 20,
    751 => 23,
    761 => 19,
    762 => 3200,
    771 => 1,
    781 => 0,
    800 => 32,
    801 => 30,
    802 => 26,
    803 => 26,
    804 => 28,
);

sub new {
    ### geliefert wird ein Hash
    my ( $class, $argsRef ) = @_;
    my $apioptions = parseApiOptions( $argsRef->{apioptions} );

    my $self = {
        devName => $argsRef->{devName},
        key     => (
            ( defined( $argsRef->{apikey} ) and $argsRef->{apikey} )
            ? $argsRef->{apikey}
            : 'none'
        ),
        lang      => $argsRef->{language},
        lat       => ( split( ',', $argsRef->{location} ) )[0],
        long      => ( split( ',', $argsRef->{location} ) )[1],
        fetchTime => 0,
        endpoint  => 'none',
    };

    $self->{cachemaxage} = (
        defined( $apioptions->{cachemaxage} )
        ? $apioptions->{cachemaxage}
        : 900 );
    $self->{cached} = _CreateForecastRef($self);

    bless $self, $class;
    return $self;
}

sub parseApiOptions($) {
    my $apioptions = shift;

    my @params;
    my %h;

    @params = split( ',', $apioptions );
    while (@params) {
        my $param = shift(@params);
        next if ( $param eq '' );
        my ( $key, $value ) = split( ':', $param, 2 );
        $h{$key} = $value;
    }

    return \%h;
}

sub setFetchTime {
    my $self = shift;

    $self->{fetchTime} = time();
    return 0;
}

sub setRetrieveData {
    my $self = shift;

    _RetrieveDataFromOpenWeatherMap($self);
    return 0;
}

sub setLocation {
    my ($self,$lat,$long) = @_;

    $self->{lat}            = $lat;
    $self->{long}           = $long;

    return 0;
}

sub getFetchTime {
    my $self = shift;

    return $self->{fetchTime};
}

sub getWeather {
    my $self = shift;

    return $self->{cached};
}

sub _RetrieveDataFromOpenWeatherMap($) {
    my $self = shift;

    # retrieve data from cache
    if (  ( time() - $self->{fetchTime} ) < $self->{cachemaxage}
        and $self->{cached}->{lat} == $self->{lat}
        and $self->{cached}->{long} == $self->{long}
      )
    {
        return _CallWeatherCallbackFn($self);
    }

    $self->{cached}->{lat}  = $self->{lat}
      unless ( $self->{cached}->{lat} == $self->{lat} );
    $self->{cached}->{long} = $self->{long}
      unless ( $self->{cached}->{long} == $self->{long} );

    my $paramRef = {
        timeout  => 15,
        self     => $self,
        endpoint => ( $self->{endpoint} eq 'none' ? 'weather' : 'forecast' ),
        callback => \&_RetrieveDataFinished,
    };

    $self->{endpoint} = $paramRef->{endpoint};

    if (   $self->{lat} eq 'error'
        or $self->{long} eq 'error'
        or $self->{key} eq 'none'
        or $missingModul )
    {
        _RetrieveDataFinished(
            $paramRef,
'The given location is invalid. (wrong latitude or longitude?) put both as an attribute in the global device or set define option location=[LAT],[LONG]',
            undef
        ) if ( $self->{lat} eq 'error' or $self->{long} eq 'error' );

        _RetrieveDataFinished( $paramRef,
            'No given api key. (define  myWeather Weather apikey=[KEY])',
            undef )
          if ( $self->{key} eq 'none' );

        _RetrieveDataFinished( $paramRef,
            'Perl modul ' . $missingModul . ' is missing.', undef )
          if ($missingModul);
    }
    else {
        $paramRef->{url} =
            URL
          . $paramRef->{endpoint} . '?' . 'lat='
          . $self->{lat} . '&' . 'lon='
          . $self->{long} . '&'
          . 'APPID='
          . $self->{key} . '&' . 'lang='
          . $self->{lang};

        main::HttpUtils_NonblockingGet($paramRef);
    }
}

sub _RetrieveDataFinished($$$) {
    my ( $paramRef, $err, $response ) = @_;
    my $self = $paramRef->{self};

    if ( !$err ) {
        $self->{cached}->{status} = 'ok';
        $self->{cached}->{validity} = 'up-to-date', $self->{fetchTime} = time();
        _ProcessingRetrieveData( $self, $response );
    }
    else {
        $self->{fetchTime} = time() if ( not defined( $self->{fetchTime} ) );
        _ErrorHandling( $self, $err );
        _ProcessingRetrieveData( $self, $response );
    }
}

sub _ProcessingRetrieveData($$) {
    my ( $self, $response ) = @_;

    if (    $self->{cached}->{status} eq 'ok'
        and defined($response)
        and $response )
    {
        if ( $response =~ m/^{.*}$/ ) {
            my $data = eval { decode_json($response) };

            if ($@) {
                _ErrorHandling( $self,
                    'OpenWeatherMap Weather decode JSON err ' . $@ );
            }
            elsif ( defined( $data->{cod} )
                and $data->{cod}
                and $data->{cod} != 200
                and defined( $data->{message} )
                and $data->{message} )
            {
                _ErrorHandling( $self, $data->{cod} . ': ' . $data->{message} );
            }
            else {
                ### Debug
                #                 print 'Response: ' . Dumper $data;
                ###### Ab hier wird die ResponseHash Referenze für die Rückgabe zusammen gestellt
                $self->{cached}->{current_date_time} =
                  strftimeWrapper( "%a, %e %b %Y %H:%M",
                    localtime( $self->{fetchTime} ) );

                if ( $self->{endpoint} eq 'weather' ) {
                    $self->{cached}->{country} = $data->{sys}->{country};
                    $self->{cached}->{city}    = encode_utf8( $data->{name} );
                    $self->{cached}->{license}{text} = 'none';
                    $self->{cached}->{current} = {
                        'temperature' => int(
                            sprintf( "%.1f",
                                ( $data->{main}->{temp} - 273.15 ) ) + 0.5
                        ),
                        'temp_c' => int(
                            sprintf( "%.1f",
                                ( $data->{main}->{temp} - 273.15 ) ) + 0.5
                        ),
                        'low_c' => int(
                            sprintf( "%.1f",
                                ( $data->{main}->{temp_min} - 273.15 ) ) + 0.5
                        ),
                        'high_c' => int(
                            sprintf( "%.1f",
                                ( $data->{main}->{temp_max} - 273.15 ) ) + 0.5
                        ),
                        'tempLow' => int(
                            sprintf( "%.1f",
                                ( $data->{main}->{temp_min} - 273.15 ) ) + 0.5
                        ),
                        'tempHigh' => int(
                            sprintf( "%.1f",
                                ( $data->{main}->{temp_max} - 273.15 ) ) + 0.5
                        ),
                        'humidity' => $data->{main}->{humidity},
                        'condition' =>
                          encode_utf8( $data->{weather}->[0]->{description} ),
                        'pressure' => int(
                            sprintf( "%.1f", $data->{main}->{pressure} ) + 0.5
                        ),
                        'wind' => int(
                            sprintf( "%.1f", ( $data->{wind}->{speed} * 3.6 ) )
                              + 0.5
                        ),
                        'wind_speed' => int(
                            sprintf( "%.1f", ( $data->{wind}->{speed} * 3.6 ) )
                              + 0.5
                        ),
                        'wind_direction' => $data->{wind}->{deg},
                        'cloudCover'     => $data->{clouds}->{all},
                        'visibility' =>
                          int( sprintf( "%.1f", $data->{visibility} ) + 0.5 ),
                        'code'       => $codes{ $data->{weather}->[0]->{id} },
                        'iconAPI'    => $data->{weather}->[0]->{icon},
                        'sunsetTime' => strftimeWrapper(
                            "%a, %e %b %Y %H:%M",
                            localtime( $data->{sys}->{sunset} )
                        ),
                        'sunriseTime' => strftimeWrapper(
                            "%a, %e %b %Y %H:%M",
                            localtime( $data->{sys}->{sunrise} )
                        ),
                        'pubDate' => strftimeWrapper(
                            "%a, %e %b %Y %H:%M",
                            localtime( $data->{dt} )
                        ),
                    };
                }

                if ( $self->{endpoint} eq 'forecast' ) {
                    if ( ref( $data->{list} ) eq "ARRAY"
                        and scalar( @{ $data->{list} } ) > 0 )
                    {
                        ## löschen des alten Datensatzes
                        delete $self->{cached}->{forecast};

                        my $i = 0;
                        foreach ( @{ $data->{list} } ) {
                            push(
                                @{ $self->{cached}->{forecast}->{hourly} },
                                {
                                    'pubDate' => strftimeWrapper(
                                        "%a, %e %b %Y %H:%M",
                                        localtime(
                                            ( $data->{list}->[$i]->{dt} ) - 3600
                                        )
                                    ),
                                    'day_of_week' => strftime(
                                        "%a, %H:%M",
                                        localtime(
                                            ( $data->{list}->[$i]->{dt} ) - 3600
                                        )
                                    ),
                                    'temperature' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{main}
                                                  ->{temp} - 273.15
                                            )
                                        ) + 0.5
                                    ),
                                    'temp_c' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{main}
                                                  ->{temp} - 273.15
                                            )
                                        ) + 0.5
                                    ),
                                    'low_c' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{main}
                                                  ->{temp_min} - 273.15
                                            )
                                        ) + 0.5
                                    ),
                                    'high_c' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{main}
                                                  ->{temp_max} - 273.15
                                            )
                                        ) + 0.5
                                    ),
                                    'tempLow' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{main}
                                                  ->{temp_min} - 273.15
                                            )
                                        ) + 0.5
                                    ),
                                    'tempHigh' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{main}
                                                  ->{temp_max} - 273.15
                                            )
                                        ) + 0.5
                                    ),
                                    'humidity' =>
                                      $data->{list}->[$i]->{main}->{humidity},
                                    'condition' => encode_utf8(
                                        $data->{list}->[$i]->{weather}->[0]
                                          ->{description}
                                    ),
                                    'pressure' => int(
                                        sprintf( "%.1f",
                                            $data->{list}->[$i]->{main}
                                              ->{pressure} ) + 0.5
                                    ),
                                    'wind' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{wind}
                                                  ->{speed} * 3.6
                                            )
                                        ) + 0.5
                                    ),
                                    'wind_speed' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{list}->[$i]->{wind}
                                                  ->{speed} * 3.6
                                            )
                                        ) + 0.5
                                    ),
                                    'cloudCover' =>
                                      $data->{list}->[$i]->{clouds}->{all},
                                    'code' => $codes{
                                        $data->{list}->[$i]->{weather}->[0]
                                          ->{id}
                                    },
                                    'iconAPI' =>
                                      $data->{list}->[$i]->{weather}->[0]
                                      ->{icon},
                                    'rain1h' =>
                                      $data->{list}->[$i]->{rain}->{'1h'},
                                    'rain3h' =>
                                      $data->{list}->[$i]->{rain}->{'3h'},
                                    'snow1h' =>
                                      $data->{list}->[$i]->{snow}->{'1h'},
                                    'snow3h' =>
                                      $data->{list}->[$i]->{snow}->{'3h'},
                                },
                            );

                            $i++;
                        }
                    }
                }
            }
        }
        else { _ErrorHandling( $self, 'OpenWeatherMap ' . $response ); }
    }

    $self->{endpoint} = 'none' if ( $self->{endpoint} eq 'forecast' );

    _RetrieveDataFromOpenWeatherMap($self)
      if ( $self->{endpoint} eq 'weather' );

    _CallWeatherCallbackFn($self) if ( $self->{endpoint} eq 'none' );
}

sub _CallWeatherCallbackFn($) {
    my $self = shift;

    #     print 'Dumperausgabe: ' . Dumper $self;
    ### Aufruf der callbackFn
    main::Weather_RetrieveCallbackFn( $self->{devName} );
}

sub _ErrorHandling($$) {
    my ( $self, $err ) = @_;

    $self->{cached}->{current_date_time} =
      strftimeWrapper( "%a, %e %b %Y %H:%M", localtime( $self->{fetchTime} ) ),
      $self->{cached}->{status} = $err;
    $self->{cached}->{validity} = 'stale';
}

sub _CreateForecastRef($) {
    my $self = shift;

    my $forecastRef = (
        {
            lat  => $self->{lat},
            long => $self->{long},
            apiMaintainer =>
'Leon Gaultier (<a href=https://forum.fhem.de/index.php?action=profile;u=13684>CoolTux</a>)',
            apiVersion    => version->parse(OpenWeatherMapAPI->VERSION())->normal,
        }
    );

    return $forecastRef;
}

sub strftimeWrapper(@) {
    my $string = POSIX::strftime(@_);

    $string =~ s/\xe4/ä/g;
    $string =~ s/\xc4/Ä/g;
    $string =~ s/\xf6/ö/g;
    $string =~ s/\xd6/Ö/g;
    $string =~ s/\xfc/ü/g;
    $string =~ s/\xdc/Ü/g;
    $string =~ s/\xdf/ß/g;
    $string =~ s/\xdf/ß/g;
    $string =~ s/\xe1/á/g;
    $string =~ s/\xe9/é/g;
    $string =~ s/\xc1/Á/g;
    $string =~ s/\xc9/É/g;

    return $string;
}

##############################################################################

1;


=pod

=encoding utf8

=for :application/json;q=META.json OpenWeatherMapAPI.pm
{
  "abstract": "Weather API for Weather OpenWeatherMap",
  "x_lang": {
    "de": {
      "abstract": "Wetter API für OpenWeatherMap"
    }
  },
  "version": "v1.0.0",
  "author": [
    "Marko Oldenburg <leongaultier@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM::Meta": 0,
        "HttpUtils": 0,
        "strict": 0,
        "warnings": 0,
        "constant": 0,
        "POSIX": 0,
        "JSON::PP": 0
      },
      "recommends": {
        "JSON": 0
      },
      "suggests": {
        "JSON::XS": 0,
        "Cpanel::JSON::XS": 0
      }
    }
  }
}
=end :application/json;q=META.json

=cut

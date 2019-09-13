# $Id$

package wundergroundAPI;
use strict;
use warnings;
use FHEM::Meta;
use Data::Dumper;

FHEM::Meta::Load(__PACKAGE__);
use version 0.77; our $VERSION = $main::packages{wundergroundAPI}{META}{version};

package wundergroundAPI::Weather;
use strict;
use warnings;

use POSIX;
use Encode;
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

use Data::Dumper;    # for Debug only
## API URL
use constant DEMODATA =>
'{"daily":{"dayOfWeek":["Freitag","Samstag","Sonntag","Montag","Dienstag","Mittwoch"],"expirationTimeUtc":[1555688120,1555688120,1555688120,1555688120,1555688120,1555688120],"moonPhase":["Vollmond","abnehmender Halbmond","abnehmender Halbmond","abnehmender Halbmond","abnehmender Halbmond","abnehmender Halbmond"],"moonPhaseCode":["F","WNG","WNG","WNG","WNG","WNG"],"moonPhaseDay":[15,16,17,18,19,20],"moonriseTimeLocal":["2019-04-19T20:09:54+0200","2019-04-20T21:30:54+0200","2019-04-21T22:48:07+0200","","2019-04-23T00:00:38+0200","2019-04-24T01:05:27+0200"],"moonriseTimeUtc":[1555697394,1555788654,1555879687,null,1555970438,1556060727],"moonsetTimeLocal":["2019-04-19T06:31:01+0200","2019-04-20T06:54:19+0200","2019-04-21T07:20:19+0200","2019-04-22T07:50:19+0200","2019-04-23T08:25:54+0200","2019-04-24T09:09:28+0200"],"moonsetTimeUtc":[1555648261,1555736059,1555824019,1555912219,1556000754,1556089768],"narrative":["Meistens klar. Tiefsttemperatur 5C.","Meistens klar. Höchsttemperaturen 19 bis 21C und Tiefsttemperaturen 4 bis 6C.","Meistens klar. Höchsttemperaturen 20 bis 22C und Tiefsttemperaturen 6 bis 8C.","Meistens klar. Höchsttemperaturen 20 bis 22C und Tiefsttemperaturen 9 bis 11C.","Teilweise bedeckt und windig. Höchsttemperaturen 21 bis 23C und Tiefsttemperaturen 11 bis 13C.","Teilweise bedeckt. Höchsttemperaturen 22 bis 24C und Tiefsttemperaturen 12 bis 14C."],"qpf":[0.0,0.0,0.0,0.0,0.0,0.0],"qpfSnow":[0.0,0.0,0.0,0.0,0.0,0.0],"sunriseTimeLocal":["2019-04-19T06:00:46+0200","2019-04-20T05:58:38+0200","2019-04-21T05:56:31+0200","2019-04-22T05:54:25+0200","2019-04-23T05:52:20+0200","2019-04-24T05:50:15+0200"],"sunriseTimeUtc":[1555646446,1555732718,1555818991,1555905265,1555991540,1556077815],"sunsetTimeLocal":["2019-04-19T20:11:02+0200","2019-04-20T20:12:46+0200","2019-04-21T20:14:29+0200","2019-04-22T20:16:13+0200","2019-04-23T20:17:56+0200","2019-04-24T20:19:40+0200"],"sunsetTimeUtc":[1555697462,1555783966,1555870469,1555956973,1556043476,1556129980],"temperatureMax":[null,20,21,21,22,23],"temperatureMin":[5,5,7,10,12,13],"validTimeLocal":["2019-04-19T07:00:00+0200","2019-04-20T07:00:00+0200","2019-04-21T07:00:00+0200","2019-04-22T07:00:00+0200","2019-04-23T07:00:00+0200","2019-04-24T07:00:00+0200"],"validTimeUtc":[1555650000,1555736400,1555822800,1555909200,1555995600,1556082000],"daypart":[{"cloudCover":[null,0,25,8,0,0,7,26,55,46,62,44],"dayOrNight":[null,"N","D","N","D","N","D","N","D","N","D","N"],"daypartName":[null,"Heute Abend","Morgen","Morgen Abend","Sonntag","Sonntagnacht","Montag","Montagnacht","Dienstag","Dienstagnacht","Mittwoch","Mittwochnacht"],"iconCode":[null,31,34,33,32,31,34,33,24,29,30,29],"iconCodeExtend":[null,3100,3400,3300,3200,3100,3400,3300,3010,2900,3000,2900],"narrative":[null,"Meistens klar. Tiefsttemperatur 5C. Wind aus NO mit 2 bis 4 m/s.","Meistens klar. Höchsttemperatur 20C. Wind aus NNO mit 2 bis 4 m/s.","Meistens klar. Tiefsttemperatur 5C. Wind aus NO mit 2 bis 4 m/s.","Meistens klar. Höchsttemperatur 21C. Wind aus O und wechselhaft.","Meistens klar. Tiefsttemperatur 7C. Wind aus ONO und wechselhaft.","Meistens klar. Höchsttemperatur 21C. Wind aus O mit 4 bis 9 m/s.","Meistens klar. Tiefsttemperatur 10C. Wind aus O mit 4 bis 9 m/s.","Teilweise bedeckt und windig. Höchsttemperatur 22C. Wind aus OSO mit 9 bis 13 m/s.","Teilweise bedeckt. Tiefsttemperatur 12C. Wind aus SO mit 4 bis 9 m/s.","Teilweise bedeckt. Höchsttemperatur 23C. Wind aus SO mit 4 bis 9 m/s.","Teilweise bedeckt. Tiefsttemperatur 13C. Wind aus SO mit 2 bis 4 m/s."],"precipChance":[null,0,0,0,0,0,20,20,0,0,0,10],"precipType":[null,"rain","rain","rain","rain","rain","rain","rain","rain","rain","rain","rain"],"qpf":[null,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0],"qpfSnow":[null,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0],"qualifierCode":[null,null,null,null,null,null,null,null,null,null,null,null],"qualifierPhrase":[null,null,null,null,null,null,null,null,null,null,null,null],"relativeHumidity":[null,50,44,55,41,55,42,48,45,55,53,64],"snowRange":[null,"","","","","","","","","","",""],"temperature":[null,5,20,5,21,7,21,10,22,12,23,13],"temperatureHeatIndex":[null,21,20,18,20,18,20,18,22,20,23,22],"temperatureWindChill":[null,5,5,5,6,6,7,8,8,10,10,13],"thunderCategory":[null,null,null,null,null,null,null,null,null,null,null,null],"thunderIndex":[null,0,0,0,0,0,0,0,0,0,0,0],"uvDescription":[null,"Niedrig","Mittel","Niedrig","Mittel","Niedrig","Mittel","Niedrig","Mittel","Niedrig","Mittel","Niedrig"],"uvIndex":[null,0,4,0,4,0,4,0,4,0,4,0],"windDirection":[null,45,18,41,85,74,95,98,114,124,139,131],"windDirectionCardinal":[null,"NO","NNO","NO","O","ONO","O","O","OSO","SO","SO","SO"],"windPhrase":[null,"Wind aus NO mit 2 bis 4 m/s.","Wind aus NNO mit 2 bis 4 m/s.","Wind aus NO mit 2 bis 4 m/s.","Wind aus O und wechselhaft.","Wind aus ONO und wechselhaft.","Wind aus O mit 4 bis 9 m/s.","Wind aus O mit 4 bis 9 m/s.","Wind aus OSO mit 9 bis 13 m/s.","Wind aus SO mit 4 bis 9 m/s.","Wind aus SO mit 4 bis 9 m/s.","Wind aus SO mit 2 bis 4 m/s."],"windSpeed":[null,4,3,3,2,2,6,6,9,7,6,4],"wxPhraseLong":[null,"Klar","Meist sonnig","Meist klar","Sonnig","Klar","Meist sonnig","Meist klar","Teilweise bedeckt/Wind","Wolkig","Wolkig","Wolkig"],"wxPhraseShort":[null,"","","","","","","","","","",""]}]},"observations":[{"stationID":"IMUNICH344","obsTimeUtc":"2019-04-19T15:24:22Z","obsTimeLocal":"2019-04-19 17:24:22","neighborhood":"Am Hartmannshofer Baechl 34","softwareType":"weewx-3.8.2","country":"DE","solarRadiation":null,"lon":11.49312592,"realtimeFrequency":null,"epoch":1555687462,"lat":48.18364716,"uv":null,"winddir":null,"humidity":27,"qcStatus":1,"metric_si":{"temp":23,"heatIndex":22,"dewpt":3,"windChill":23,"windSpeed":0,"windGust":1,"pressure":1025.84,"precipRate":0.0,"precipTotal":0.0,"elev":502}}]}';

use constant URL => 'https://api.weather.com/';

sub new {
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
    };

    $self->{cachemaxage} = (
        defined( $apioptions->{cachemaxage} )
        ? $apioptions->{cachemaxage}
        : 900
    );
    $self->{cached} = _CreateForecastRef($self);

    $self->{days} = (
        defined( $apioptions->{days} )
        ? $apioptions->{days}
        : 5
    );

    $self->{units} = (
        defined( $apioptions->{units} )
        ? $apioptions->{units}
        : 'm'
    );

    $self->{stationId} = (
        defined( $apioptions->{stationId} )
        ? $apioptions->{stationId}
        : undef
    );

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

    _RetrieveDataFromWU($self);
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

sub _RetrieveDataFromWU($) {
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
        callback => (
            $self->{stationId}
            ? \&_RetrieveDataFromPWS
            : \&_RetrieveDataFinished
        ),
    };

    if (   $self->{lat} eq 'error'
        or $self->{long} eq 'error'
        or $self->{key} eq 'none' )
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
    }
    else {
        my $options = 'geocode=' . $self->{lat} . ',' . $self->{long};
        $options .= '&format=json';
        $options .= '&units=' . $self->{units};
        $options .= '&language='
          . (
            $self->{lang} eq 'en'
            ? 'en-US'
            : $self->{lang} . '-' . uc( $self->{lang} )
          );
        $options .= '&apiKey=' . $self->{key};

        $paramRef->{url} =
            URL
          . 'v3/wx/forecast/daily/'
          . $self->{days} . 'day' . '?'
          . $options;

        if ( lc( $self->{key} ) eq 'demo' ) {
            _RetrieveDataFinished( $paramRef, undef, 'DEMODATA' . DEMODATA );
        }
        else { main::HttpUtils_NonblockingGet($paramRef); }
    }
}

sub _RetrieveDataFromPWS($$$) {
    my ( $paramRef, $err, $response ) = @_;
    my $self = $paramRef->{self};

    my $paramRefPWS = {
        timeout  => 15,
        self     => $self,
        callback => \&_RetrieveDataFinished,
        forecast => (
            $response =~ /^\{.*\}$/
            ? '{"daily":' . $response . '}'
            : $response
        ),
    };

    my $options = 'stationId=' . $self->{stationId};
    $options .= '&format=json';
    $options .= '&units=' . $self->{units};
    $options .= '&apiKey=' . $self->{key};

    $paramRefPWS->{url} = URL . 'v2/pws/observations/current?' . $options;

    main::HttpUtils_NonblockingGet($paramRefPWS);
}

sub _RetrieveDataFinished($$$) {
    my ( $paramRef, $err, $data ) = @_;
    my $self = $paramRef->{self};
    my $response;

    # we got PWS and forecast data
    if ( defined( $paramRef->{forecast} ) ) {
        if ( !$data || $data eq '' ) {
            $err = 'No Data Found for specific PWS' unless ($err);
            $response = $paramRef->{forecast};
        }
        elsif ( $paramRef->{forecast} =~ m/^\{(.*)\}$/ ) {
            my $fc = $1;

            if ( $data =~ m/^\{(.*)\}$/ ) {
                $response = '{' . $fc . ',' . $1 . '}';
            }
            else {
                $err = 'PWS data is not in JSON format' unless ($err);
                $response = $data;
            }
        }
        else {
            $err = 'Forecast data is not in JSON format' unless ($err);
            $response = $data;
        }
    }

    # just demo data
    elsif ( $data =~ m/^DEMODATA(\{.*\})$/ ) {
        $response = $1;
    }

    # just forecast data
    else {
        $response = $data;
    }

    if ( !$err ) {
        $self->{cached}{status} = 'ok';
        $self->{cached}{validity} = 'up-to-date', $self->{fetchTime} = time();
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

    if (    $self->{cached}{status} eq 'ok'
        and defined($response)
        and $response )
    {
        if ( $response =~ m/^\{.*\}$/ ) {
            my $data = eval { decode_json( encode_utf8($response) ) };
            if ($@) {
                _ErrorHandling( $self,
                    'Weather Underground decode JSON err ' . $@ );
            }

            # elsif ( defined( $data->{code} )
            #     and $data->{code}
            #     and defined( $data->{error} )
            #     and $data->{error} )
            # {
            #     _ErrorHandling( $self,
            #         'Code: ' . $data->{code} . ' Error: ' . $data->{error} );
            # }
            else {
                # print Dumper $response;    ## für Debugging
                # print Dumper $data;    ## für Debugging

                $self->{cached}{current_date_time} =
                  strftimeWrapper( "%a, %e %b %Y %H:%M",
                    localtime( $self->{fetchTime} ) );

                # $self->{cached}{timezone} = $data->{timezone};
                $self->{cached}{license}{text} =
                    'Data provided by Weather Underground; '
                  . 'part of The Weather Company, an IBM Business.';

                if (    ref( $data->{observations} ) eq "ARRAY"
                    and scalar @{ $data->{observations} } > 0
                    and ref( $data->{observations}[0] ) eq "HASH"
                    and scalar keys %{ $data->{observations}[0] } > 0 )
                {
                    my $data = $data->{observations}[0];

                    my $unit = (
                        defined( $data->{metric_si} ) ? 'metric_si'
                        : (
                            defined( $data->{metric} ) ? 'metric'
                            : (
                                defined( $data->{imperial} ) ? 'imperial'
                                : (
                                    defined( $data->{uk_hybrid} ) ? 'uk_hybrid'
                                    : '-'
                                )
                            )
                        )
                    );

                    $self->{cached}{current} = {
                        'dewPoint' =>
                          int( sprintf( "%.1f", $data->{$unit}{dewpt} ) + 0.5 ),
                        'heatIndex'   => $data->{$unit}{heatIndex},
                        'precipRate'  => $data->{$unit}{precipRate},
                        'precipTotal' => $data->{$unit}{precipTotal},
                        'pressure'    => int(
                            sprintf( "%.1f", $data->{$unit}{pressure} ) + 0.5
                        ),
                        'temperature' =>
                          int( sprintf( "%.1f", $data->{$unit}{temp} ) + 0.5 ),
                        'temp_c' =>
                          int( sprintf( "%.1f", $data->{$unit}{temp} ) + 0.5 ),
                        'wind_chill' => int(
                            sprintf( "%.1f", ( $data->{$unit}{windChill} ) ) +
                              0.5
                        ),
                        'windGust' => int(
                            sprintf( "%.1f", ( $data->{$unit}{windGust} ) ) +
                              0.5
                        ),
                        'wind' => int(
                            sprintf( "%.1f", ( $data->{$unit}{windSpeed} ) ) +
                              0.5
                        ),
                        'wind_speed' => int(
                            sprintf( "%.1f", ( $data->{$unit}{windSpeed} ) ) +
                              0.5
                        ),
                        'wind_direction' => $data->{winddir},
                        'solarRadiation' => $data->{solarRadiation},
                        'uvIndex'        => $data->{uv},
                        'humidity'       => $data->{humidity},
                        'pubDate'        => strftimeWrapper(
                            "%a, %e %b %Y %H:%M",
                            localtime(
                                main::time_str2num( $data->{obsTimeLocal} )
                            )
                        ),
                        'pwsLat'               => $data->{lat},
                        'pwsLon'               => $data->{lon},
                        'pwsElevation'         => $data->{$unit}{elev},
                        'pwsQcStatus'          => $data->{qcStatus},
                        'pwsRealtimeFrequency' => $data->{realtimeFrequency},
                        'pwsCountry'           => $data->{country},
                        'pwsStationID'         => $data->{stationID},
                        'pwsNeighborhood'      => $data->{neighborhood},
                        'pwsSoftwareType'      => $data->{softwareType},
                    };
                }

                if (
                    (
                        ref( $data->{temperatureMin} ) eq "ARRAY"
                        and scalar @{ $data->{temperatureMin} } > 0
                    )
                    || ( ref( $data->{daily}{temperatureMin} ) eq "ARRAY"
                        and scalar @{ $data->{daily}{temperatureMin} } > 0 )
                  )
                {
                    ### löschen des alten Datensatzes
                    delete $self->{cached}{forecast};

                    my $data =
                      exists( $data->{daily} ) ? $data->{daily} : $data;
                    my $days = scalar @{ $data->{temperatureMin} };

                    my $i = 0;
                    while ( $i < $days ) {
                        $data->{moonriseTimeLocal}[$i] =~
                          s/^(....-..-..T..:..).*/$1/;
                        $data->{moonsetTimeLocal}[$i] =~
                          s/^(....-..-..T..:..).*/$1/;
                        $data->{sunriseTimeLocal}[$i] =~
                          s/^(....-..-..T..:..).*/$1/;
                        $data->{sunsetTimeLocal}[$i] =~
                          s/^(....-..-..T..:..).*/$1/;

                        push(
                            @{ $self->{cached}{forecast}{daily} },
                            {
                                'day_of_week'   => $data->{dayOfWeek}[$i],
                                'moonPhase'     => $data->{moonPhase}[$i],
                                'moonPhaseCode' => $data->{moonPhaseCode}[$i],
                                'moonPhaseDay'  => $data->{moonPhaseDay}[$i],
                                'moonriseTime'  => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        main::time_str2num(
                                            $data->{moonriseTimeLocal}[$i]
                                        )
                                    )
                                ),
                                'moonsetTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        main::time_str2num(
                                            $data->{moonsetTimeLocal}[$i]
                                        )
                                    )
                                ),
                                'narrative'         => $data->{narrative}[$i],
                                'precipProbability' => $data->{qpf}[$i],
                                'precipProbabilitySnow' => $data->{qpfSnow}[$i],
                                'sunriseTime'           => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        main::time_str2num(
                                            $data->{sunriseTimeLocal}[$i]
                                        )
                                    )
                                ),
                                'sunsetTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        main::time_str2num(
                                            $data->{sunsetTimeLocal}[$i]
                                        )
                                    )
                                ),
                                'low_c' => int(
                                    sprintf( "%.1f",
                                        $data->{temperatureMin}[$i] ) + 0.5
                                ),
                                'high_c' => int(
                                    sprintf(
                                        "%.1f",
                                        (
                                              $data->{temperatureMax}[$i]
                                            ? $data->{temperatureMax}[$i]
                                            : 0
                                        )
                                    ) + 0.5
                                ),
                                'tempLow' => int(
                                    sprintf( "%.1f",
                                        $data->{temperatureMin}[$i] ) + 0.5
                                ),
                                'tempHigh' => int(
                                    sprintf(
                                        "%.1f",
                                        (
                                              $data->{temperatureMax}[$i]
                                            ? $data->{temperatureMax}[$i]
                                            : 0
                                        )
                                    ) + 0.5
                                ),
                            }
                        );

                        $i++;
                    }

                    if (    ref( $data->{daypart} ) eq "ARRAY"
                        and scalar @{ $data->{daypart} } > 0
                        and ref( $data->{daypart}[0] ) eq "HASH"
                        and scalar keys %{ $data->{daypart}[0] } > 0
                        and ref( $data->{daypart}[0]{daypartName} ) eq "ARRAY"
                        and scalar @{ $data->{daypart}[0]{daypartName} } > 0 )
                    {
                        my $data     = $data->{daypart}[0];
                        my $dayparts = scalar @{ $data->{daypartName} };

                        my $i   = 0;
                        my $day = 0;
                        while ( $i < $dayparts ) {

                            my $part = (
                                $data->{dayOrNight}[$i]
                                  && $data->{dayOrNight}[$i] eq 'N'
                                ? 'night'
                                : 'day'
                            );

                            # copy some day values to regular day forecast
                            if ( $part eq 'day' || $part eq 'night' ) {
                                my $self =
                                  $self->{cached}{forecast}{daily}[$day];

                                $self->{cloudCover} = $data->{cloudCover}[$i]
                                  unless ( !$data->{cloudCover}[$i]
                                    || defined( $self->{cloudCover} ) );
                                $self->{code} = $data->{iconCode}[$i]
                                  unless ( !$data->{iconCode}[$i]
                                    || defined( $self->{code} ) );
                                $self->{iconAPI} = $data->{iconCode}[$i]
                                  unless ( !$data->{iconCode}[$i]
                                    || defined( $self->{iconAPI} ) );
                                $self->{codeExtend} =
                                  $data->{iconCodeExtend}[$i]
                                  unless ( !$data->{iconCodeExtend}[$i]
                                    || defined( $self->{codeExtend} ) );
                                $self->{condition} = $data->{wxPhraseShort}[$i]
                                  unless ( !$data->{wxPhraseShort}[$i]
                                    || defined( $self->{condition} ) );
                                $self->{condition} = $data->{wxPhraseLong}[$i]
                                  unless ( !$data->{wxPhraseLong}[$i]
                                    || defined( $self->{condition} ) );
                                $self->{precipProbability} = $data->{qpf}[$i]
                                  unless ( !$data->{qpf}[$i]
                                    || defined( $self->{precipProbability} ) );
                                $self->{precipProbability} = $data->{qpf}[$i]
                                  unless ( !$data->{qpf}[$i]
                                    || defined( $self->{precipProbability} ) );
                                $self->{uvIndex} = $data->{uvIndex}[$i]
                                  unless ( !$data->{uvIndex}[$i]
                                    || defined( $self->{uvIndex} ) );
                            }

                            # if this is today, copy some values to current
                            if ( $i eq '0' || $i eq '1' ) {
                                my $self = $self->{cached}{current};

                                $self->{cloudCover} = $data->{cloudCover}[$i]
                                  unless ( !$data->{cloudCover}[$i]
                                    || defined( $self->{cloudCover} ) );
                                $self->{code} = $data->{iconCode}[$i]
                                  unless ( !$data->{iconCode}[$i]
                                    || defined( $self->{code} ) );
                                $self->{iconAPI} = $data->{iconCode}[$i]
                                  unless ( !$data->{iconCode}[$i]
                                    || defined( $self->{iconAPI} ) );
                                $self->{codeExtend} =
                                  $data->{iconCodeExtend}[$i]
                                  unless ( !$data->{iconCodeExtend}[$i]
                                    || defined( $self->{codeExtend} ) );
                                $self->{condition} = $data->{wxPhraseShort}[$i]
                                  unless ( !$data->{wxPhraseShort}[$i]
                                    || defined( $self->{condition} ) );
                                $self->{condition} = $data->{wxPhraseLong}[$i]
                                  unless ( !$data->{wxPhraseLong}[$i]
                                    || defined( $self->{condition} ) );
                                $self->{precipProbability} = $data->{qpf}[$i]
                                  unless ( !$data->{qpf}[$i]
                                    || defined( $self->{precipProbability} ) );
                                $self->{precipProbability} = $data->{qpf}[$i]
                                  unless ( !$data->{qpf}[$i]
                                    || defined( $self->{precipProbability} ) );
                                $self->{uvIndex} = $data->{uvIndex}[$i]
                                  unless ( !$data->{uvIndex}[$i]
                                    || defined( $self->{uvIndex} ) );
                            }

                            push(
                                @{ $self->{cached}{forecast}{hourly} },
                                {
                                    'cloudCover'  => $data->{cloudCover}[$i],
                                    'dayOrNight'  => $data->{dayOrNight}[$i],
                                    'day_of_week' => $data->{daypartName}[$i],
                                    'code'        => $data->{iconCode}[$i],
                                    'iconAPI'     => $data->{iconCode}[$i],
                                    'codeExtend' => $data->{iconCodeExtend}[$i],
                                    'narrative'  => $data->{narrative}[$i],
                                    'precipChance' => $data->{precipChance}[$i],
                                    'precipType'   => $data->{precipType}[$i],
                                    'precipProbability' => $data->{qpf}[$i],
                                    'precipProbabilitySnow' =>
                                      $data->{qpfSnow}[$i],
                                    'qualifierPhrase' =>
                                      $data->{qualifierPhrase}[$i],
                                    'humidity' => $data->{relativeHumidity}[$i],
                                    'snowRange'   => $data->{snowRange}[$i],
                                    'temp_c'      => $data->{temperature}[$i],
                                    'temperature' => $data->{temperature}[$i],
                                    'heatIndex' =>
                                      $data->{temperatureHeatIndex}[$i],
                                    'wind_chill' =>
                                      $data->{temperatureWindChill}[$i],
                                    'thunderCategory' =>
                                      $data->{thunderCategory}[$i],
                                    'thunderIndex' => $data->{thunderIndex}[$i],
                                    'uvDescription' =>
                                      $data->{uvDescription}[$i],
                                    'uvIndex' => $data->{uvIndex}[$i],
                                    'wind_direction' =>
                                      $data->{windDirection}[$i],
                                    'wind_directionCardinal' =>
                                      $data->{windDirectionCardinal}[$i],
                                    'windPhrase' => $data->{windPhrase}[$i],
                                    'wind'       => $data->{windSpeed}[$i],
                                    'wind_speed' => $data->{windSpeed}[$i],
                                    'condition'  => $data->{wxPhraseLong}[$i],
                                    'wxPhraseShort' =>
                                      $data->{wxPhraseShort}[$i],
                                }
                            ) if ( defined( $data->{temperature}[$i] ) );

                            $i++;
                            $day++ if ( $part eq 'night' );
                        }
                    }

                }
            }
        }
        else {
            _ErrorHandling( $self, 'Weather Underground ' . $response );
        }
    }

    ## Aufruf der callbackFn
    _CallWeatherCallbackFn($self);
}

sub _CallWeatherCallbackFn($) {
    my $self = shift;

    #     ## Aufruf der callbackFn
    main::Weather_RetrieveCallbackFn( $self->{devName} );
}

sub _ErrorHandling($$) {
    my ( $self, $err ) = @_;

    $self->{cached}{current_date_time} =
      strftimeWrapper( "%a, %e %b %Y %H:%M", localtime( $self->{fetchTime} ) ),
      $self->{cached}{status} = $err;
    $self->{cached}{validity} = 'stale';
}

sub _CreateForecastRef($) {
    my $self = shift;

    my $forecastRef = (
        {
            lat           => $self->{lat},
            long          => $self->{long},
            apiMaintainer => 'Julian Pawlowski (loredo)',
            apiVersion    => wundergroundAPI->VERSION(),
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

=for :application/json;q=META.json wundergroundAPI.pm
{
  "abstract": "Weather API for Weather Underground",
  "x_lang": {
    "de": {
      "abstract": "Wetter API für Weather Underground"
    }
  },
  "version": "v1.0.1",
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
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

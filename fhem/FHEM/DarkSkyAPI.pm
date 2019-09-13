# $Id$
###############################################################################
#
# Developed with Kate
#
#  (c) 2019 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to:
#       - Lippie hourly forecast code
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

package DarkSkyAPI;
use strict;
use warnings;
use FHEM::Meta;
use Data::Dumper;

FHEM::Meta::Load(__PACKAGE__);
use version 0.50; our $VERSION = $main::packages{DarkSkyAPI}{META}{version};

package DarkSkyAPI::Weather;
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
use constant DEMODATA =>
'{"latitude":50.112,"longitude":8.686,"timezone":"Europe/Berlin","currently":{"time":1551214558,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":9.65,"apparentTemperature":9.65,"dewPoint":1.39,"humidity":0.56,"pressure":1032.69,"windSpeed":0.41,"windGust":1.35,"windBearing":84,"cloudCover":0,"uvIndex":0,"visibility":10.01,"ozone":276.41},"hourly":{"summary":"Leicht bewölkt am heute Nacht.","icon":"partly-cloudy-night","data":[{"time":1551211200,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":10.59,"apparentTemperature":10.59,"dewPoint":1.84,"humidity":0.55,"pressure":1032.7,"windSpeed":0.28,"windGust":1.15,"windBearing":89,"cloudCover":0,"uvIndex":0,"visibility":10.01,"ozone":277},{"time":1551214800,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":9.58,"apparentTemperature":9.58,"dewPoint":1.36,"humidity":0.56,"pressure":1032.69,"windSpeed":0.42,"windGust":1.37,"windBearing":83,"cloudCover":0,"uvIndex":0,"visibility":10.01,"ozone":276.37},{"time":1551218400,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":8.61,"apparentTemperature":8.61,"dewPoint":0.73,"humidity":0.58,"pressure":1032.63,"windSpeed":0.5,"windGust":1.47,"windBearing":72,"cloudCover":0,"uvIndex":0,"visibility":11.47,"ozone":275.56},{"time":1551222000,"summary":"Leicht bewölkt","icon":"partly-cloudy-night","precipIntensity":0,"precipProbability":0,"temperature":8.06,"apparentTemperature":8.06,"dewPoint":-0.45,"humidity":0.55,"pressure":1032.55,"windSpeed":0.86,"windGust":1.5,"windBearing":40,"cloudCover":0.26,"uvIndex":0,"visibility":16.09,"ozone":274.76},{"time":1551225600,"summary":"Leicht bewölkt","icon":"partly-cloudy-night","precipIntensity":0,"precipProbability":0,"temperature":7.48,"apparentTemperature":7.48,"dewPoint":-1.38,"humidity":0.53,"pressure":1032.4,"windSpeed":1.14,"windGust":1.49,"windBearing":33,"cloudCover":0.42,"uvIndex":0,"visibility":16.09,"ozone":274.13},{"time":1551229200,"summary":"Leicht bewölkt","icon":"partly-cloudy-night","precipIntensity":0,"precipProbability":0,"temperature":6.62,"apparentTemperature":6.62,"dewPoint":-1.89,"humidity":0.54,"pressure":1032.12,"windSpeed":1.11,"windGust":1.43,"windBearing":38,"cloudCover":0.36,"uvIndex":0,"visibility":16.09,"ozone":273.77},{"time":1551232800,"summary":"Leicht bewölkt","icon":"partly-cloudy-night","precipIntensity":0,"precipProbability":0,"temperature":5.73,"apparentTemperature":5.73,"dewPoint":-2.39,"humidity":0.56,"pressure":1031.83,"windSpeed":1.07,"windGust":1.34,"windBearing":46,"cloudCover":0.29,"uvIndex":0,"visibility":16.09,"ozone":273.55},{"time":1551236400,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":4.91,"apparentTemperature":4.91,"dewPoint":-2.81,"humidity":0.57,"pressure":1031.49,"windSpeed":1.03,"windGust":1.23,"windBearing":54,"cloudCover":0.23,"uvIndex":0,"visibility":16.09,"ozone":273.44},{"time":1551240000,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":4.02,"apparentTemperature":4.02,"dewPoint":-3.26,"humidity":0.59,"pressure":1031.18,"windSpeed":0.99,"windGust":1.15,"windBearing":63,"cloudCover":0.21,"uvIndex":0,"visibility":16.09,"ozone":273.43},{"time":1551243600,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":3.26,"apparentTemperature":3.26,"dewPoint":-3.61,"humidity":0.61,"pressure":1030.85,"windSpeed":0.96,"windGust":1.08,"windBearing":73,"cloudCover":0.22,"uvIndex":0,"visibility":16.09,"ozone":273.5},{"time":1551247200,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":3.19,"apparentTemperature":3.19,"dewPoint":-3.51,"humidity":0.61,"pressure":1030.54,"windSpeed":0.92,"windGust":1.01,"windBearing":83,"cloudCover":0.22,"uvIndex":0,"visibility":16.09,"ozone":273.65},{"time":1551250800,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":4.28,"apparentTemperature":4.28,"dewPoint":-2.62,"humidity":0.61,"pressure":1030.25,"windSpeed":0.83,"windGust":0.88,"windBearing":93,"cloudCover":0.2,"uvIndex":0,"visibility":16.09,"ozone":273.79},{"time":1551254400,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":6.29,"apparentTemperature":6.29,"dewPoint":-1.28,"humidity":0.58,"pressure":1029.92,"windSpeed":0.72,"windGust":0.78,"windBearing":105,"cloudCover":0.19,"uvIndex":1,"visibility":16.09,"ozone":273.91},{"time":1551258000,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":8.45,"apparentTemperature":8.45,"dewPoint":-0.11,"humidity":0.55,"pressure":1029.54,"windSpeed":0.68,"windGust":0.77,"windBearing":116,"cloudCover":0.16,"uvIndex":1,"visibility":16.09,"ozone":274.33},{"time":1551261600,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":10.79,"apparentTemperature":10.79,"dewPoint":0.73,"humidity":0.5,"pressure":1028.98,"windSpeed":0.81,"windGust":0.9,"windBearing":125,"cloudCover":0.14,"uvIndex":2,"visibility":16.09,"ozone":275.21},{"time":1551265200,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":13.36,"apparentTemperature":13.36,"dewPoint":1.44,"humidity":0.44,"pressure":1028.33,"windSpeed":1.06,"windGust":1.12,"windBearing":131,"cloudCover":0.11,"uvIndex":3,"visibility":16.09,"ozone":276.39},{"time":1551268800,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":15.58,"apparentTemperature":15.58,"dewPoint":1.98,"humidity":0.4,"pressure":1027.59,"windSpeed":1.26,"windGust":1.28,"windBearing":140,"cloudCover":0.08,"uvIndex":3,"visibility":16.09,"ozone":277.31},{"time":1551272400,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":17.3,"apparentTemperature":17.3,"dewPoint":2.23,"humidity":0.36,"pressure":1026.71,"windSpeed":1.3,"windGust":1.31,"windBearing":154,"cloudCover":0.05,"uvIndex":2,"visibility":16.09,"ozone":277.73},{"time":1551276000,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":18.44,"apparentTemperature":18.44,"dewPoint":2.27,"humidity":0.34,"pressure":1025.7,"windSpeed":1.28,"windGust":1.28,"windBearing":172,"cloudCover":0.02,"uvIndex":2,"visibility":16.09,"ozone":277.96},{"time":1551279600,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":18.49,"apparentTemperature":18.49,"dewPoint":2.21,"humidity":0.34,"pressure":1024.91,"windSpeed":1.24,"windGust":1.27,"windBearing":184,"cloudCover":0,"uvIndex":1,"visibility":16.09,"ozone":278.36},{"time":1551283200,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":17.44,"apparentTemperature":17.44,"dewPoint":2.05,"humidity":0.36,"pressure":1024.53,"windSpeed":1.18,"windGust":1.25,"windBearing":191,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":278.97},{"time":1551286800,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":14.98,"apparentTemperature":14.98,"dewPoint":1.79,"humidity":0.41,"pressure":1024.34,"windSpeed":1.12,"windGust":1.27,"windBearing":194,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":279.76},{"time":1551290400,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":12.61,"apparentTemperature":12.61,"dewPoint":1.52,"humidity":0.47,"pressure":1024.09,"windSpeed":1.11,"windGust":1.39,"windBearing":195,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":280.33},{"time":1551294000,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":10.99,"apparentTemperature":10.99,"dewPoint":1.18,"humidity":0.51,"pressure":1023.68,"windSpeed":1.2,"windGust":1.51,"windBearing":194,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":280.69},{"time":1551297600,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":9.98,"apparentTemperature":9.98,"dewPoint":0.83,"humidity":0.53,"pressure":1023.18,"windSpeed":1.34,"windGust":1.64,"windBearing":191,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":280.94},{"time":1551301200,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":9.18,"apparentTemperature":8.72,"dewPoint":0.53,"humidity":0.55,"pressure":1022.72,"windSpeed":1.49,"windGust":1.77,"windBearing":190,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":281.11},{"time":1551304800,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":8.5,"apparentTemperature":7.72,"dewPoint":0.36,"humidity":0.57,"pressure":1022.32,"windSpeed":1.71,"windGust":1.9,"windBearing":194,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":281.02},{"time":1551308400,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":7.97,"apparentTemperature":6.87,"dewPoint":0.24,"humidity":0.58,"pressure":1021.93,"windSpeed":1.94,"windGust":2.05,"windBearing":200,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":280.74},{"time":1551312000,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":7.47,"apparentTemperature":6.15,"dewPoint":0.17,"humidity":0.6,"pressure":1021.49,"windSpeed":2.11,"windGust":2.19,"windBearing":206,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":280.75},{"time":1551315600,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":6.82,"apparentTemperature":5.37,"dewPoint":0.09,"humidity":0.62,"pressure":1020.9,"windSpeed":2.12,"windGust":2.28,"windBearing":208,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":281.23},{"time":1551319200,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":6.09,"apparentTemperature":4.58,"dewPoint":0.06,"humidity":0.65,"pressure":1020.22,"windSpeed":2.06,"windGust":2.36,"windBearing":210,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":281.97},{"time":1551322800,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":5.44,"apparentTemperature":3.82,"dewPoint":0.01,"humidity":0.68,"pressure":1019.67,"windSpeed":2.06,"windGust":2.58,"windBearing":211,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":282.78},{"time":1551326400,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":4.78,"apparentTemperature":2.93,"dewPoint":-0.17,"humidity":0.7,"pressure":1019.37,"windSpeed":2.18,"windGust":3.01,"windBearing":214,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":283.53},{"time":1551330000,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":4.24,"apparentTemperature":2.13,"dewPoint":-0.34,"humidity":0.72,"pressure":1019.2,"windSpeed":2.36,"windGust":3.59,"windBearing":216,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":284.44},{"time":1551333600,"summary":"Heiter","icon":"clear-night","precipIntensity":0,"precipProbability":0,"temperature":4.24,"apparentTemperature":1.93,"dewPoint":-0.18,"humidity":0.73,"pressure":1019.01,"windSpeed":2.58,"windGust":4.25,"windBearing":218,"cloudCover":0,"uvIndex":0,"visibility":16.09,"ozone":285.68},{"time":1551337200,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":5.15,"apparentTemperature":2.83,"dewPoint":0.57,"humidity":0.72,"pressure":1018.8,"windSpeed":2.82,"windGust":5.04,"windBearing":219,"cloudCover":0.2,"uvIndex":0,"visibility":16.09,"ozone":287.28},{"time":1551340800,"summary":"Leicht bewölkt","icon":"partly-cloudy-day","precipIntensity":0,"precipProbability":0,"temperature":6.58,"apparentTemperature":4.36,"dewPoint":1.66,"humidity":0.71,"pressure":1018.55,"windSpeed":3.07,"windGust":5.91,"windBearing":219,"cloudCover":0.47,"uvIndex":1,"visibility":16.09,"ozone":289.23},{"time":1551344400,"summary":"Überwiegend bewölkt","icon":"partly-cloudy-day","precipIntensity":0,"precipProbability":0,"temperature":8.36,"apparentTemperature":6.28,"dewPoint":2.82,"humidity":0.68,"pressure":1018.24,"windSpeed":3.44,"windGust":6.82,"windBearing":222,"cloudCover":0.66,"uvIndex":1,"visibility":16.09,"ozone":291.68},{"time":1551348000,"summary":"Überwiegend bewölkt","icon":"partly-cloudy-day","precipIntensity":0,"precipProbability":0,"temperature":10.57,"apparentTemperature":10.57,"dewPoint":4.07,"humidity":0.64,"pressure":1017.81,"windSpeed":4.01,"windGust":7.74,"windBearing":226,"cloudCover":0.7,"uvIndex":2,"visibility":16.09,"ozone":294.4},{"time":1551351600,"summary":"Überwiegend bewölkt","icon":"partly-cloudy-day","precipIntensity":0,"precipProbability":0,"temperature":13.39,"apparentTemperature":13.39,"dewPoint":5.36,"humidity":0.58,"pressure":1017.26,"windSpeed":4.7,"windGust":8.69,"windBearing":231,"cloudCover":0.66,"uvIndex":2,"visibility":16.09,"ozone":297.66},{"time":1551355200,"summary":"Leicht bewölkt","icon":"partly-cloudy-day","precipIntensity":0,"precipProbability":0,"temperature":15.38,"apparentTemperature":15.38,"dewPoint":6.21,"humidity":0.54,"pressure":1016.79,"windSpeed":5.32,"windGust":9.65,"windBearing":237,"cloudCover":0.58,"uvIndex":2,"visibility":16.09,"ozone":302.31},{"time":1551358800,"summary":"Leicht bewölkt","icon":"partly-cloudy-day","precipIntensity":0,"precipProbability":0,"temperature":16.34,"apparentTemperature":16.34,"dewPoint":6.33,"humidity":0.52,"pressure":1016.42,"windSpeed":5.9,"windGust":10.76,"windBearing":244,"cloudCover":0.47,"uvIndex":2,"visibility":16.09,"ozone":309.63},{"time":1551362400,"summary":"Leicht bewölkt","icon":"partly-cloudy-day","precipIntensity":0,"precipProbability":0,"temperature":16.41,"apparentTemperature":16.41,"dewPoint":6.01,"humidity":0.5,"pressure":1016.08,"windSpeed":6.41,"windGust":11.88,"windBearing":253,"cloudCover":0.32,"uvIndex":1,"visibility":16.09,"ozone":318.45},{"time":1551366000,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":16.25,"apparentTemperature":16.25,"dewPoint":5.68,"humidity":0.5,"pressure":1015.79,"windSpeed":6.54,"windGust":12.43,"windBearing":257,"cloudCover":0.23,"uvIndex":1,"visibility":16.09,"ozone":325.57},{"time":1551369600,"summary":"Heiter","icon":"clear-day","precipIntensity":0,"precipProbability":0,"temperature":15.56,"apparentTemperature":15.56,"dewPoint":5.41,"humidity":0.51,"pressure":1015.57,"windSpeed":5.99,"windGust":11.93,"windBearing":252,"cloudCover":0.24,"uvIndex":0,"visibility":16.09,"ozone":329.15},{"time":1551373200,"summary":"Leicht bewölkt","icon":"partly-cloudy-night","precipIntensity":0,"precipProbability":0,"temperature":14.88,"apparentTemperature":14.88,"dewPoint":5.13,"humidity":0.52,"pressure":1015.39,"windSpeed":5.11,"windGust":10.86,"windBearing":244,"cloudCover":0.32,"uvIndex":0,"visibility":16.09,"ozone":331.01},{"time":1551376800,"summary":"Leicht bewölkt","icon":"partly-cloudy-night","precipIntensity":0.0102,"precipProbability":0.02,"precipType":"rain","temperature":14.14,"apparentTemperature":14.14,"dewPoint":5.03,"humidity":0.54,"pressure":1015.15,"windSpeed":4.55,"windGust":10.16,"windBearing":239,"cloudCover":0.42,"uvIndex":0,"visibility":16.09,"ozone":334.57},{"time":1551380400,"summary":"Leicht bewölkt","icon":"partly-cloudy-night","precipIntensity":0.0406,"precipProbability":0.06,"precipType":"rain","temperature":13.44,"apparentTemperature":13.44,"dewPoint":5.32,"humidity":0.58,"pressure":1014.77,"windSpeed":4.64,"windGust":10.41,"windBearing":240,"cloudCover":0.53,"uvIndex":0,"visibility":16.09,"ozone":342.62},{"time":1551384000,"summary":"Überwiegend bewölkt","icon":"partly-cloudy-night","precipIntensity":0.1346,"precipProbability":0.14,"precipType":"rain","temperature":12.71,"apparentTemperature":12.71,"dewPoint":5.82,"humidity":0.63,"pressure":1014.32,"windSpeed":4.96,"windGust":11.04,"windBearing":244,"cloudCover":0.67,"uvIndex":0,"visibility":13.53,"ozone":352.36}]},"daily":{"summary":"Leichter Regen von Freitag bis Montag mit fallender Temperatur von 11°C am nächsten Dienstag.","icon":"rain","data":[{"time":1551135600,"summary":"Leicht bewölkt in der Nacht.","icon":"partly-cloudy-night","sunriseTime":1551161800,"sunsetTime":1551200555,"moonPhase":0.75,"precipIntensity":0,"precipIntensityMax":0.0051,"precipIntensityMaxTime":1551186000,"precipProbability":0,"temperatureHigh":21.42,"temperatureHighTime":1551193200,"temperatureLow":3.19,"temperatureLowTime":1551247200,"apparentTemperatureHigh":21.42,"apparentTemperatureHighTime":1551193200,"apparentTemperatureLow":3.19,"apparentTemperatureLowTime":1551247200,"dewPoint":0.24,"humidity":0.55,"pressure":1034.3,"windSpeed":0.51,"windGust":2.01,"windGustTime":1551189600,"windBearing":16,"cloudCover":0.02,"uvIndex":3,"uvIndexTime":1551182400,"visibility":10.2,"ozone":285.07,"temperatureMin":1.38,"temperatureMinTime":1551153600,"temperatureMax":21.42,"temperatureMaxTime":1551193200,"apparentTemperatureMin":1.38,"apparentTemperatureMinTime":1551153600,"apparentTemperatureMax":21.42,"apparentTemperatureMaxTime":1551193200},{"time":1551222000,"summary":"Den ganzen Tag lang heiter.","icon":"clear-day","sunriseTime":1551248079,"sunsetTime":1551287056,"moonPhase":0.78,"precipIntensity":0.0025,"precipIntensityMax":0.0051,"precipIntensityMaxTime":1551229200,"precipProbability":0.02,"precipType":"rain","temperatureHigh":18.49,"temperatureHighTime":1551279600,"temperatureLow":4.24,"temperatureLowTime":1551330000,"apparentTemperatureHigh":18.49,"apparentTemperatureHighTime":1551279600,"apparentTemperatureLow":1.93,"apparentTemperatureLowTime":1551333600,"dewPoint":-0.17,"humidity":0.5,"pressure":1027.91,"windSpeed":0.59,"windGust":1.9,"windGustTime":1551304800,"windBearing":139,"cloudCover":0.13,"uvIndex":3,"uvIndexTime":1551265200,"visibility":16.09,"ozone":276.58,"temperatureMin":3.19,"temperatureMinTime":1551247200,"temperatureMax":18.49,"temperatureMaxTime":1551279600,"apparentTemperatureMin":3.19,"apparentTemperatureMinTime":1551247200,"apparentTemperatureMax":18.49,"apparentTemperatureMaxTime":1551279600},{"time":1551308400,"summary":"Den ganzen Tag lang überwiegend bewölkt.","icon":"partly-cloudy-night","sunriseTime":1551334356,"sunsetTime":1551373557,"moonPhase":0.81,"precipIntensity":0.033,"precipIntensityMax":0.3175,"precipIntensityMaxTime":1551391200,"precipProbability":0.38,"precipType":"rain","temperatureHigh":16.41,"temperatureHighTime":1551362400,"temperatureLow":8.43,"temperatureLowTime":1551423600,"apparentTemperatureHigh":16.41,"apparentTemperatureHighTime":1551362400,"apparentTemperatureLow":6.74,"apparentTemperatureLowTime":1551423600,"dewPoint":3.24,"humidity":0.62,"pressure":1017.5,"windSpeed":3.8,"windGust":12.43,"windGustTime":1551366000,"windBearing":235,"cloudCover":0.34,"uvIndex":2,"uvIndexTime":1551348000,"visibility":15.27,"ozone":307.52,"temperatureMin":4.24,"temperatureMinTime":1551330000,"temperatureMax":16.41,"temperatureMaxTime":1551362400,"apparentTemperatureMin":1.93,"apparentTemperatureMinTime":1551333600,"apparentTemperatureMax":16.41,"apparentTemperatureMaxTime":1551362400},{"time":1551394800,"summary":"Überwiegend bewölkt bis abends.","icon":"partly-cloudy-day","sunriseTime":1551420633,"sunsetTime":1551460057,"moonPhase":0.84,"precipIntensity":0.188,"precipIntensityMax":0.8179,"precipIntensityMaxTime":1551409200,"precipProbability":0.88,"precipType":"rain","temperatureHigh":14.23,"temperatureHighTime":1551452400,"temperatureLow":5.98,"temperatureLowTime":1551506400,"apparentTemperatureHigh":14.23,"apparentTemperatureHighTime":1551452400,"apparentTemperatureLow":4.09,"apparentTemperatureLowTime":1551510000,"dewPoint":5.37,"humidity":0.71,"pressure":1014.79,"windSpeed":2.63,"windGust":8.53,"windGustTime":1551394800,"windBearing":284,"cloudCover":0.62,"uvIndex":2,"uvIndexTime":1551438000,"visibility":13.52,"ozone":343.54,"temperatureMin":8.43,"temperatureMinTime":1551423600,"temperatureMax":14.23,"temperatureMaxTime":1551452400,"apparentTemperatureMin":6.74,"apparentTemperatureMinTime":1551423600,"apparentTemperatureMax":14.23,"apparentTemperatureMaxTime":1551452400},{"time":1551481200,"summary":"Den ganzen Tag lang überwiegend bewölkt.","icon":"partly-cloudy-day","sunriseTime":1551506909,"sunsetTime":1551546556,"moonPhase":0.87,"precipIntensity":0.0381,"precipIntensityMax":0.2667,"precipIntensityMaxTime":1551549600,"precipProbability":0.29,"precipType":"rain","temperatureHigh":13.86,"temperatureHighTime":1551542400,"temperatureLow":9.92,"temperatureLowTime":1551596400,"apparentTemperatureHigh":13.86,"apparentTemperatureHighTime":1551542400,"apparentTemperatureLow":6.67,"apparentTemperatureLowTime":1551596400,"dewPoint":4.98,"humidity":0.73,"pressure":1017.33,"windSpeed":3.4,"windGust":11.14,"windGustTime":1551564000,"windBearing":223,"cloudCover":0.7,"uvIndex":2,"uvIndexTime":1551520800,"visibility":16.09,"ozone":338.68,"temperatureMin":5.98,"temperatureMinTime":1551506400,"temperatureMax":13.86,"temperatureMaxTime":1551542400,"apparentTemperatureMin":4.09,"apparentTemperatureMinTime":1551510000,"apparentTemperatureMax":13.86,"apparentTemperatureMaxTime":1551542400},{"time":1551567600,"summary":"Den ganzen Tag lang leichter Wind und Nacht leichter Regen.","icon":"rain","sunriseTime":1551593184,"sunsetTime":1551633056,"moonPhase":0.9,"precipIntensity":0.3886,"precipIntensityMax":0.8484,"precipIntensityMaxTime":1551650400,"precipProbability":1,"precipType":"rain","temperatureHigh":12.89,"temperatureHighTime":1551618000,"temperatureLow":9.58,"temperatureLowTime":1551664800,"apparentTemperatureHigh":12.89,"apparentTemperatureHighTime":1551618000,"apparentTemperatureLow":7.11,"apparentTemperatureLowTime":1551661200,"dewPoint":6.11,"humidity":0.71,"pressure":1010.92,"windSpeed":6.64,"windGust":18.8,"windGustTime":1551650400,"windBearing":229,"cloudCover":0.94,"uvIndex":2,"uvIndexTime":1551607200,"visibility":10.01,"ozone":332.44,"temperatureMin":9.78,"temperatureMinTime":1551600000,"temperatureMax":12.89,"temperatureMaxTime":1551618000,"apparentTemperatureMin":6.37,"apparentTemperatureMinTime":1551600000,"apparentTemperatureMax":12.89,"apparentTemperatureMaxTime":1551618000},{"time":1551654000,"summary":"Den ganzen Tag lang überwiegend bewölkt sowie leichter Wind bis Nachmittag.","icon":"wind","sunriseTime":1551679459,"sunsetTime":1551719555,"moonPhase":0.93,"precipIntensity":0.3023,"precipIntensityMax":0.8128,"precipIntensityMaxTime":1551654000,"precipProbability":0.92,"precipType":"rain","temperatureHigh":14.28,"temperatureHighTime":1551711600,"temperatureLow":7.89,"temperatureLowTime":1551769200,"apparentTemperatureHigh":14.28,"apparentTemperatureHighTime":1551711600,"apparentTemperatureLow":4.87,"apparentTemperatureLowTime":1551769200,"dewPoint":5.51,"humidity":0.67,"pressure":1003.91,"windSpeed":6.15,"windGust":20.06,"windGustTime":1551657600,"windBearing":230,"cloudCover":0.91,"uvIndex":2,"uvIndexTime":1551693600,"visibility":12.46,"ozone":369.63,"temperatureMin":9.58,"temperatureMinTime":1551664800,"temperatureMax":14.28,"temperatureMaxTime":1551711600,"apparentTemperatureMin":7.11,"apparentTemperatureMinTime":1551661200,"apparentTemperatureMax":14.28,"apparentTemperatureMaxTime":1551711600},{"time":1551740400,"summary":"Nachmittags Nebel.","icon":"fog","sunriseTime":1551765733,"sunsetTime":1551806054,"moonPhase":0.96,"precipIntensity":0.2083,"precipIntensityMax":0.4597,"precipIntensityMaxTime":1551780000,"precipProbability":0.72,"precipType":"rain","temperatureHigh":11.26,"temperatureHighTime":1551794400,"temperatureLow":5.99,"temperatureLowTime":1551855600,"apparentTemperatureHigh":11.26,"apparentTemperatureHighTime":1551794400,"apparentTemperatureLow":2.28,"apparentTemperatureLowTime":1551855600,"dewPoint":3.41,"humidity":0.65,"pressure":1001.87,"windSpeed":5.37,"windGust":16.22,"windGustTime":1551754800,"windBearing":230,"cloudCover":0.79,"uvIndex":1,"uvIndexTime":1551776400,"visibility":8.96,"ozone":442.27,"temperatureMin":7.89,"temperatureMinTime":1551769200,"temperatureMax":11.26,"temperatureMaxTime":1551794400,"apparentTemperatureMin":4.82,"apparentTemperatureMinTime":1551772800,"apparentTemperatureMax":11.26,"apparentTemperatureMaxTime":1551794400}]},"flags":{"sources":["meteoalarm","cmc","gfs","icon","isd","madis"],"meteoalarm-license":"Based on data from EUMETNET - MeteoAlarm [https://www.meteoalarm.eu/]. Time delays between this website and the MeteoAlarm website are possible; for the most up to date information about alert levels as published by the participating National Meteorological Services please use the MeteoAlarm website.","nearest-station":8.711,"units":"si"},"offset":1}';

use constant URL     => 'https://api.darksky.net/forecast/';

my %codes = (
    'clear-day'           => 32,
    'clear-night'         => 31,
    'rain'                => 11,
    'snow'                => 16,
    'sleet'               => 18,
    'wind'                => 24,
    'fog'                 => 20,
    'cloudy'              => 26,
    'partly-cloudy-day'   => 30,
    'partly-cloudy-night' => 29,
    'hail'                => 17,
    'thunderstorm'        => 4,
    'tornado'             => 0,
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
    };

    $self->{cachemaxage} = (
        defined( $apioptions->{cachemaxage} )
        ? $apioptions->{cachemaxage}
        : 900 );
    $self->{extend} =
      ( defined( $apioptions->{extend} ) ? $apioptions->{extend} : 'none' );
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

    _RetrieveDataFromDarkSky($self);
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

sub _RetrieveDataFromDarkSky($) {
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
        callback => \&_RetrieveDataFinished,
    };

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
        my $options = '&units=auto';
        $options .= '&extend=' . $self->{extend}
          if ( $self->{extend} ne 'none' );

        $paramRef->{url} =
            URL
          . $self->{key} . '/'
          . $self->{lat} . ','
          . $self->{long}
          . '?lang='
          . $self->{lang}
          . $options;

        if ( lc( $self->{key} ) eq 'demo' ) {
            _RetrieveDataFinished( $paramRef, undef, DEMODATA );
        }
        else { main::HttpUtils_NonblockingGet($paramRef); }
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
                    'DarkSky Weather decode JSON err ' . $@ );
            }
            elsif ( defined( $data->{code} )
                and $data->{code}
                and defined( $data->{error} )
                and $data->{error} )
            {
                _ErrorHandling( $self,
                    'Code: ' . $data->{code} . ' Error: ' . $data->{error} );
            }
            else {
                #             print Dumper $data;       ## für Debugging

                $self->{cached}->{current_date_time} =
                  strftimeWrapper( "%a, %e %b %Y %H:%M",
                    localtime( $self->{fetchTime} ) );
                $self->{cached}->{timezone} = $data->{timezone};
                $self->{cached}->{license}{text} =
                  $data->{flags}->{'meteoalarm-license'};
                $self->{cached}->{current} = {
                    'temperature' => int(
                        sprintf( "%.1f", $data->{currently}->{temperature} ) +
                          0.5
                    ),
                    'temp_c' => int(
                        sprintf( "%.1f", $data->{currently}->{temperature} ) +
                          0.5
                    ),
                    'dewPoint' => int(
                        sprintf( "%.1f", $data->{currently}->{dewPoint} ) + 0.5
                    ),
                    'humidity'  => $data->{currently}->{humidity} * 100,
                    'condition' => encode_utf8( $data->{currently}->{summary} ),
                    'pressure'  => int(
                        sprintf( "%.1f", $data->{currently}->{pressure} ) + 0.5
                    ),
                    'wind' => int(
                        sprintf( "%.1f",
                            ( $data->{currently}->{windSpeed} * 3.6 ) ) + 0.5
                    ),
                    'wind_speed' => int(
                        sprintf( "%.1f",
                            ( $data->{currently}->{windSpeed} * 3.6 ) ) + 0.5
                    ),
                    'wind_direction' => $data->{currently}->{windBearing},
                    'windGust'       => int(
                        sprintf( "%.1f",
                            ( $data->{currently}->{windGust} * 3.6 ) ) + 0.5
                    ),
                    'cloudCover' => $data->{currently}->{cloudCover} * 100,
                    'uvIndex'    => $data->{currently}->{uvIndex},
                    'visibility' => int(
                        sprintf( "%.1f", $data->{currently}->{visibility} ) +
                          0.5
                    ),
                    'ozone'   => $data->{currently}->{ozone},
                    'code'    => $codes{ $data->{currently}->{icon} },
                    'iconAPI' => $data->{currently}->{icon},
                    'pubDate' => strftimeWrapper(
                        "%a, %e %b %Y %H:%M",
                        localtime( $data->{currently}->{'time'} )
                    ),
                    'precipProbability' =>
                      $data->{currently}->{precipProbability} * 100,
                    'apparentTemperature' => int(
                        sprintf( "%.1f",
                            $data->{currently}->{apparentTemperature} ) + 0.5
                    ),
                    'precipIntensity' => $data->{currently}->{precipIntensity},
                };

                if ( ref( $data->{daily}->{data} ) eq "ARRAY"
                    and scalar( @{ $data->{daily}->{data} } ) > 0 )
                {
                    ### löschen des alten Datensatzes
                    delete $self->{cached}->{forecast};

                    my $i = 0;
                    foreach ( @{ $data->{daily}->{data} } ) {
                        push(
                            @{ $self->{cached}->{forecast}->{daily} },
                            {
                                'pubDate' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]->{'time'}
                                    )
                                ),
                                'day_of_week' => strftime(
                                    "%a",
                                    localtime(
                                        $data->{daily}->{data}->[$i]->{'time'}
                                    )
                                ),
                                'low_c' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]
                                          ->{temperatureLow} ) + 0.5
                                ),
                                'high_c' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]
                                          ->{temperatureHigh} ) + 0.5
                                ),
                                'tempLow' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]
                                          ->{temperatureLow} ) + 0.5
                                ),
                                'tempLowTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{temperatureLowTime}
                                    )
                                ),
                                'tempHigh' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]
                                          ->{temperatureHigh} ) + 0.5
                                ),
                                'tempHighTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{temperatureHighTime}
                                    )
                                ),
                                'apparentTempLow' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]
                                          ->{apparentTemperatureLow} ) + 0.5
                                ),
                                'apparentTempLowTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{apparentTemperatureLowTime}
                                    )
                                ),
                                'apparentTempHigh' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]
                                          ->{apparentTemperatureHigh} ) + 0.5
                                ),
                                'apparentTempHighTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{apparentTemperatureHighTime}
                                    )
                                ),
                                'code' =>
                                  $codes{ $data->{daily}->{data}->[$i]->{icon}
                                  },
                                'iconAPI' =>
                                  $data->{daily}->{data}->[$i]->{icon},
                                'condition' => encode_utf8(
                                    $data->{daily}->{data}->[$i]->{summary}
                                ),
                                'ozone' =>
                                  $data->{daily}->{data}->[$i]->{ozone},
                                'uvIndex' =>
                                  $data->{daily}->{data}->[$i]->{uvIndex},
                                'uvIndexTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{uvIndexTime}
                                    )
                                ),
                                'dewPoint' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]->{dewPoint}
                                    ) + 0.5
                                ),
                                'humidity' =>
                                  $data->{daily}->{data}->[$i]->{humidity} *
                                  100,
                                'cloudCover' =>
                                  $data->{daily}->{data}->[$i]->{cloudCover} *
                                  100,
                                'wind_direction' =>
                                  $data->{daily}->{data}->[$i]->{windBearing},
                                'wind' => int(
                                    sprintf(
                                        "%.1f",
                                        (
                                            $data->{daily}->{data}->[$i]
                                              ->{windSpeed} * 3.6
                                        )
                                    ) + 0.5
                                ),
                                'wind_speed' => int(
                                    sprintf(
                                        "%.1f",
                                        (
                                            $data->{daily}->{data}->[$i]
                                              ->{windSpeed} * 3.6
                                        )
                                    ) + 0.5
                                ),
                                'windGust' => int(
                                    sprintf(
                                        "%.1f",
                                        (
                                            $data->{daily}->{data}->[$i]
                                              ->{windGust} * 3.6
                                        )
                                    ) + 0.5
                                ),
                                'windGustTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{windGustTime}
                                    )
                                ),
                                'moonPhase' =>
                                  $data->{daily}->{data}->[$i]->{moonPhase},
                                'sunsetTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{sunsetTime}
                                    )
                                ),
                                'sunriseTime' => strftimeWrapper(
                                    "%a, %e %b %Y %H:%M",
                                    localtime(
                                        $data->{daily}->{data}->[$i]
                                          ->{sunriseTime}
                                    )
                                ),
                                'pressure' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]->{pressure}
                                    ) + 0.5
                                ),
                                'visibility' => int(
                                    sprintf( "%.1f",
                                        $data->{daily}->{data}->[$i]
                                          ->{visibility} ) + 0.5
                                ),
                            }
                        );

                        $self->{cached}->{forecast}
                          ->{daily}[$i]{precipIntensityMax} = (
                            defined(
                                $data->{daily}->{data}->[$i]
                                  ->{precipIntensityMax}
                              )
                            ? $data->{daily}->{data}->[$i]->{precipIntensityMax}
                            : '-'
                          );
                        $self->{cached}->{forecast}
                          ->{daily}[$i]{precipIntensity} = (
                            defined(
                                $data->{daily}->{data}->[$i]->{precipIntensity}
                              )
                            ? $data->{daily}->{data}->[$i]->{precipIntensity}
                            : '-'
                          );
                        $self->{cached}->{forecast}
                          ->{daily}[$i]{precipProbability} = (
                            defined(
                                $data->{daily}->{data}->[$i]
                                  ->{precipProbability}
                              )
                            ? $data->{daily}->{data}->[$i]->{precipProbability}
                              * 100
                            : '-'
                          );
                        $self->{cached}->{forecast}->{daily}[$i]{precipType} = (
                            defined(
                                $data->{daily}->{data}->[$i]->{precipType}
                              )
                            ? $data->{daily}->{data}->[$i]->{precipType}
                            : '-'
                        );
                        $self->{cached}->{forecast}
                          ->{daily}[$i]{precipIntensityMaxTime} = (
                            defined(
                                $data->{daily}->{data}->[$i]
                                  ->{precipIntensityMaxTime}
                              )
                            ? strftimeWrapper(
                                "%a, %e %b %Y %H:%M",
                                localtime(
                                    $data->{daily}->{data}->[$i]
                                      ->{precipIntensityMaxTime}
                                )
                              )
                            : '-'
                          );

                        $i++;
                    }

                    if ( ref( $data->{hourly}->{data} ) eq "ARRAY"
                        and scalar( @{ $data->{hourly}->{data} } ) > 0 )
                    {
                        ### löschen des alten Datensatzes
                        delete $self->{cached}->{forecast}->{hourly};

                        my $i = 0;
                        foreach ( @{ $data->{hourly}->{data} } ) {
                            push(
                                @{ $self->{cached}->{forecast}->{hourly} },
                                {
                                    'pubDate' => strftimeWrapper(
                                        "%a, %e %b %Y %H:%M",
                                        localtime(
                                            $data->{hourly}->{data}->[$i]
                                              ->{'time'}
                                        )
                                    ),
                                    'day_of_week' => strftime(
                                        "%a, %H:%M",
                                        localtime(
                                            $data->{hourly}->{data}->[$i]
                                              ->{'time'}
                                        )
                                    ),
                                    'temperature' => sprintf( "%.1f",
                                        $data->{hourly}->{data}->[$i]
                                          ->{temperature} ),
                                    'code' =>
                                      $codes{ $data->{hourly}->{data}->[$i]
                                          ->{icon} },
                                    'iconAPI' =>
                                      $data->{hourly}->{data}->[$i]->{icon},
                                    'condition' => encode_utf8(
                                        $data->{hourly}->{data}->[$i]->{summary}
                                    ),
                                    'ozone' =>
                                      $data->{hourly}->{data}->[$i]->{ozone},
                                    'uvIndex' =>
                                      $data->{hourly}->{data}->[$i]->{uvIndex},
                                    'dewPoint' => sprintf( "%.1f",
                                        $data->{hourly}->{data}->[$i]
                                          ->{dewPoint} ),
                                    'humidity' =>
                                      $data->{hourly}->{data}->[$i]->{humidity}
                                      * 100,
                                    'cloudCover' =>
                                      $data->{hourly}->{data}->[$i]
                                      ->{cloudCover} * 100,
                                    'wind_direction' =>
                                      $data->{hourly}->{data}->[$i]
                                      ->{windBearing},
                                    'wind' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{hourly}->{data}->[$i]
                                                  ->{windSpeed} * 3.6
                                            )
                                        ) + 0.5
                                    ),
                                    'wind_speed' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{hourly}->{data}->[$i]
                                                  ->{windSpeed} * 3.6
                                            )
                                        ) + 0.5
                                    ),
                                    'windGust' => int(
                                        sprintf(
                                            "%.1f",
                                            (
                                                $data->{hourly}->{data}->[$i]
                                                  ->{windGust} * 3.6
                                            )
                                        ) + 0.5
                                    ),

                                    'pressure' => sprintf( "%.1f",
                                        $data->{hourly}->{data}->[$i]
                                          ->{pressure} ),
                                    'visibility' => sprintf( "%.1f",
                                        $data->{hourly}->{data}->[$i]
                                          ->{visibility} ),
                                }
                            );

                            $self->{cached}->{forecast}
                              ->{hourly}[$i]{precipIntensity} = (
                                defined(
                                    $data->{hourly}->{data}->[$i]
                                      ->{precipIntensity}
                                  )
                                ? $data->{hourly}->{data}->[$i]
                                  ->{precipIntensity}
                                : '-'
                              );
                            $self->{cached}->{forecast}
                              ->{hourly}[$i]{precipProbability} = (
                                defined(
                                    $data->{hourly}->{data}->[$i]
                                      ->{precipProbability}
                                  )
                                ? $data->{hourly}->{data}->[$i]
                                  ->{precipProbability} * 100
                                : '-'
                              );
                            $self->{cached}->{forecast}
                              ->{hourly}[$i]{precipType} = (
                                defined(
                                    $data->{hourly}->{data}->[$i]->{precipType}
                                  )
                                ? $data->{hourly}->{data}->[$i]->{precipType}
                                : '-'
                              );

                            $i++;
                        }
                    }
                }
            }
        }
        else { _ErrorHandling( $self, 'DarkSky Weather ' . $response ); }
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
            apiVersion    => version->parse(DarkSkyAPI->VERSION())->normal,
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

=for :application/json;q=META.json DarkSkyAPI.pm
{
  "abstract": "Weather API for Weather DarkSky",
  "x_lang": {
    "de": {
      "abstract": "Wetter API für Weather DarkSky"
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

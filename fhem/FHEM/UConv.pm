# $Id$

package main;

use strict;
use warnings;

sub UConv_Initialize() {
}

package UConv;

####################
# Translations

my %pressure_trend_sym = ( 0 => "=", 1 => "+", 2 => "-" );

my %pressure_trend_txt = (
    "en" => { 0 => "steady",         1 => "rising",    2 => "falling" },
    "de" => { 0 => "gleichbleibend", 1 => "steigend",  2 => "fallend" },
    "nl" => { 0 => "stabiel",        1 => "stijgend",  2 => "dalend" },
    "fr" => { 0 => "stable",         1 => "croissant", 2 => "décroissant" },
    "pl" => { 0 => "stabilne",       1 => "rośnie",   2 => "spada" },
);

my %compasspoint_txt = (
    "en" => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
    "de" => [
        'N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
    "nl" => [
        'N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO',
        'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW'
    ],
    "fr" => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'
    ],
    "pl" => [
        'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ],
);

my %wdays_txt_en = (
    "en" => {
        'Mon' => 'Mon',
        'Tue' => 'Tue',
        'Wed' => 'Wed',
        'Thu' => 'Thu',
        'Fri' => 'Fri',
        'Sat' => 'Sat',
        'Sun' => 'Sun',
    },
    "de" => {
        'Mon' => 'Mo',
        'Tue' => 'Di',
        'Wed' => 'Mi',
        'Thu' => 'Do',
        'Fri' => 'Fr',
        'Sat' => 'Sa',
        'Sun' => 'So',
    },
    "nl" => {
        'Mon' => 'Maa',
        'Tue' => 'Din',
        'Wed' => 'Woe',
        'Thu' => 'Don',
        'Fri' => 'Vri',
        'Sat' => 'Zat',
        'Sun' => 'Zon',
    },
    "fr" => {
        'Mon' => 'Lun',
        'Tue' => 'Mar',
        'Wed' => 'Mer',
        'Thu' => 'Jeu',
        'Fri' => 'Ven',
        'Sat' => 'Sam',
        'Sun' => 'Dim',
    },
    "pl" => {
        'Mon' => 'Pon',
        'Tue' => 'Wt',
        'Wed' => 'Śr',
        'Thu' => 'Czw',
        'Fri' => 'Pt',
        'Sat' => 'Sob',
        'Sun' => 'Nie',
    },
);

my %units = (

    # temperature
    "c" => {
        "unit_symbol" => "°",
        "unit"        => "C",
        "unit_prefix" => {
            "de" => "Grad",
            "en" => "degree",
            "fr" => "degree",
            "nl" => "degree",
            "pl" => "degree",
        },
        "unit_long" => {
            "de" => "Celsius",
            "en" => "Celsius",
            "fr" => "Celsius",
            "nl" => "Celsius",
            "pl" => "Celsius",
        },
        "txt_format"      => '%VALUE%%unit_symbol%%unit%',
        "txt_format_long" => '%VALUE% %unit_prefix% %unit_long%',
    },
    "f" => {
        "unit_symbol" => "°",
        "unit"        => "F",
        "unit_prefix" => {
            "de" => "Grad",
            "en" => "degree",
            "fr" => "degree",
            "nl" => "degree",
            "pl" => "degree",
        },
        "unit_long" => {
            "de" => "Fahrenheit",
            "en" => "Fahrenheit",
            "fr" => "Fahrenheit",
            "nl" => "Fahrenheit",
            "pl" => "Fahrenheit",
        },
        "txt_format"      => '%VALUE%%unit_symbol%%unit%',
        "txt_format_long" => '%VALUE% %unit_prefix% %unit_long%',
    },
    "k" => {
        "unit_symbol" => "°",
        "unit"        => "K",
        "unit_prefix" => {
            "de" => "Grad",
            "en" => "degree",
            "fr" => "degree",
            "nl" => "degree",
            "pl" => "degree",
        },
        "unit_long" => {
            "de" => "Kelvin",
            "en" => "Kelvin",
            "fr" => "Kelvin",
            "nl" => "Kelvin",
            "pl" => "Kelvin",
        },
        "txt_format"      => '%VALUE%%unit_symbol%%unit%',
        "txt_format_long" => '%VALUE% %unit_prefix% %unit_long%',
    },

    # hydro
    "hg" => {
        "unit_symbol" => "%",
    },

    # speed
    "bft" => {
        "unit"        => "bft",
        "unit_prefix" => {
            "de" => "Windstärke",
            "en" => "wind force",
            "fr" => "wind force",
            "nl" => "wind force",
            "pl" => "wind force",
        },
        "unit_long" => {
            "de" => "in Beaufort",
            "en" => "in Beaufort",
            "fr" => "in Beaufort",
            "nl" => "in Beaufort",
            "pl" => "in Beaufort",
        },
        "txt_format"      => '%unit_prefix% %VALUE%',
        "txt_format_long" => '%unit_prefix% %VALUE% %unit_long%',
    },
    "fts" => {
        "unit"      => "ft/s",
        "unit_long" => {
            "de" => "Feet pro Sekunde",
            "en" => "feets per second",
            "fr" => "feets per second",
            "nl" => "feets per second",
            "pl" => "feets per second",
        },
    },
    "kmh" => {
        "unit"      => "km/h",
        "unit_long" => {
            "de" => "Kilometer pro Stunde",
            "en" => "kilometer per hour",
            "fr" => "kilometer per hour",
            "nl" => "kilometer per hour",
            "pl" => "kilometer per hour",
        },
    },
    "kn" => {
        "unit"      => "kn",
        "unit_long" => {
            "de" => "Knoten",
            "en" => "knots",
            "fr" => "knots",
            "nl" => "knots",
            "pl" => "knots",
        },
    },
    "mph" => {
        "unit"      => "mi/h",
        "unit_long" => {
            "de" => "Meilen pro Stunde",
            "en" => "miles per hour",
            "fr" => "miles per hour",
            "nl" => "miles per hour",
            "pl" => "miles per hour",
        },
    },
    "mps" => {
        "unit"      => "m/s",
        "unit_long" => {
            "de" => "Meter pro Sekunde",
            "en" => "meter per second",
            "fr" => "meter per second",
            "nl" => "meter per second",
            "pl" => "meter per second",
        },
    },

    # pressure
    "hpa" => {
        "unit"        => "hPa",
        "unit_prefix" => {
            "de" => "hecto",
            "en" => "hecto",
            "fr" => "hecto",
            "nl" => "hecto",
            "pl" => "hecto",
        },
        "unit_long" => {
            "de" => "Pascal",
            "en" => "Pascal",
            "fr" => "Pascal",
            "nl" => "Pascal",
            "pl" => "Pascal",
        },
    },
    "inhg" => {
        "unit"        => "inHg",
        "unit_prefix" => {
            "de" => "Zoll",
            "en" => "inches",
            "fr" => "inches",
            "nl" => "inches",
            "pl" => "inches",
        },
        "unit_long" => {
            "de" => "Quecksilbersäule",
            "en" => "of Mercury",
            "fr" => "of Mercury",
            "nl" => "of Mercury",
            "pl" => "of Mercury",
        },
    },
    "mmhg" => {
        "unit"        => "mmHg",
        "unit_prefix" => {
            "de" => "Millimeter",
            "en" => "milimeter",
            "fr" => "milimeter",
            "nl" => "milimeter",
            "pl" => "milimeter",
        },
        "unit_long" => {
            "de" => "Quecksilbersäule",
            "en" => "of Mercury",
            "fr" => "of Mercury",
            "nl" => "of Mercury",
            "pl" => "of Mercury",
        },
    },
    "torr" => {
        "unit" => "Torr",
    },
    "psi" => {
        "unit"      => "psi",
        "unit_long" => {
            "de" => "Pfund pro Quadratzoll",
            "en" => "Pound-force per square inch",
            "fr" => "Pound-force per square inch",
            "nl" => "Pound-force per square inch",
            "pl" => "Pound-force per square inch",
        },
    },
    "psia" => {
        "unit"      => "psia",
        "unit_long" => {
            "de" => "Pfund pro Quadratzoll absolut",
            "en" => "pound-force per square inch absolute",
            "fr" => "pound-force per square inch absolute",
            "nl" => "pound-force per square inch absolute",
            "pl" => "pound-force per square inch absolute",
        },
    },
    "psig" => {
        "unit"      => "psig",
        "unit_long" => {
            "de" => "Pfund pro Quadratzoll relativ",
            "en" => "pounds-force per square inch gauge",
            "fr" => "pounds-force per square inch gauge",
            "nl" => "pounds-force per square inch gauge",
            "pl" => "pounds-force per square inch gauge",
        },
    },

    # solar
    "lux" => {
        "unit" => "lux",
    },
    "wpsm" => {
        "unit"      => "W/m2",
        "unit_long" => {
            "de" => "Watt pro Quadratmeter",
            "en" => "Watt per square meter",
            "fr" => "Watt per square meter",
            "nl" => "Watt per square meter",
            "pl" => "Watt per square meter",
        },
    },

    # length
    "km" => {
        "unit"      => "km",
        "unit_long" => {
            "de" => "Kilometer",
            "en" => "kilometer",
            "fr" => "kilometer",
            "nl" => "kilometer",
            "pl" => "kilometer",
        },
    },

    "m" => {
        "unit"      => "m",
        "unit_long" => {
            "de" => "Meter",
            "en" => "meter",
            "fr" => "meter",
            "nl" => "meter",
            "pl" => "meter",
        },
    },

    "mm" => {
        "unit"      => "mm",
        "unit_long" => {
            "de" => "Millimeter",
            "en" => "milimeter",
            "fr" => "milimeter",
            "nl" => "milimeter",
            "pl" => "milimeter",
        },
    },

    "cm" => {
        "unit"      => "cm",
        "unit_long" => {
            "de" => "Zentimeter",
            "en" => "centimeter",
            "fr" => "centimeter",
            "nl" => "centimeter",
            "pl" => "centimeter",
        },
    },

    "mi" => {
        "unit"      => "mi",
        "unit_long" => {
            "de" => "Meilen",
            "en" => "miles",
            "fr" => "miles",
            "nl" => "miles",
            "pl" => "miles",
        },
    },

    "in" => {
        "unit"      => "in",
        "unit_long" => {
            "de" => "Zoll",
            "en" => "inch",
            "fr" => "inch",
            "nl" => "inch",
            "pl" => "inch",
        },
    },

    # angular
    "degree" => {
        "unit"      => "°",
        "unit_long" => {
            "de" => "Grad",
            "en" => "degree",
            "fr" => "degree",
            "nl" => "degree",
            "pl" => "degree",
        },
    },
);

# Get unit details in local language as hash
sub UnitDetails ($;$) {
    my ( $unit, $lang ) = @_;
    my $u = lc($unit);
    my $l = lc($lang);
    my %details;

    if ( defined( $units{$u} ) ) {
        foreach my $k ( keys %{ $units{$u} } ) {
            $details{$k} = $units{$u}{$k};
        }
        $details{"unit_abbr"} = $u;

        if ( $lang && $details{"unit_prefix"} ) {
            delete $details{"unit_prefix"};
            if ( $units{$u}{"unit_prefix"}{$l} ) {
                $details{"unit_prefix"} = $units{$u}{"unit_prefix"}{$l};
            }
            else {
                $details{"unit_prefix"} = $units{$u}{"unit_prefix"}{"en"};
            }
        }

        if ( $lang && $details{"unit_long"} ) {
            delete $details{"unit_long"};
            if ( $units{$u}{"unit_long"}{$l} ) {
                $details{"unit_long"} = $units{$u}{"unit_long"}{$l};
            }
            else {
                $details{"unit_long"} = $units{$u}{"unit_long"}{"en"};
            }
        }

        return \%details;
    }
}

my %weather_readings = (
    "dewpoint" => {
        "unified" => "dewpoint_c",    # link only
    },
    "dewpoint_c" => {
        "short" => "D",
        "unit"  => "c",
    },
    "dewpoint_f" => {
        "short" => "Df",
        "unit"  => "f",
    },
    "dewpoint_k" => {
        "short" => "Dk",
        "unit"  => "k",
    },
    "humidity" => {
        "short" => "H",
        "unit"  => "hg",
    },
    "humidityabs" => {
        "unified" => "humidityabs_c",    # link only
    },
    "humidityabs_c" => {
        "short" => "Ha",
        "unit"  => "c",
    },
    "humidityabs_f" => {
        "short" => "Haf",
        "unit"  => "f",
    },
    "humidityabs_k" => {
        "short" => "Hak",
        "unit"  => "k",
    },
    "indoordewpoint" => {
        "unified" => "indoordewpoint_c",    # link only
    },
    "indoordewpoint_c" => {
        "short" => "Di",
        "unit"  => "c",
    },
    "indoordewpoint_f" => {
        "short" => "Dif",
        "unit"  => "f",
    },
    "indoordewpoint_k" => {
        "short" => "Dik",
        "unit"  => "k",
    },
    "indoorhumidity" => {
        "short" => "Hi",
        "unit"  => "hg",
    },
    "indoorhumidityabs" => {
        "unified" => "indoorhumidityabs_c",    # link only
    },
    "indoorhumidityabs_c" => {
        "short" => "Hai",
        "unit"  => "c",
    },
    "indoorhumidityabs_f" => {
        "short" => "Haif",
        "unit"  => "f",
    },
    "indoorhumidityabs_k" => {
        "short" => "Haik",
        "unit"  => "k",
    },
    "indoortemperature" => {
        "unified" => "indoortemperature_c",    # link only
    },
    "indoortemperature_c" => {
        "short" => "T",
        "unit"  => "c",
    },
    "indoortemperature_f" => {
        "short" => "Tf",
        "unit"  => "f",
    },
    "indoortemperature_k" => {
        "short" => "Tk",
        "unit"  => "k",
    },
    "israining" => {
        "short" => "IR",
    },
    "luminosity" => {
        "short" => "L",
        "unit"  => "lux",
    },
    "airpress" => {
        "unified" => "pressure_hpa",    # link only
    },
    "pressure" => {
        "unified" => "pressure_hpa",    # link only
    },
    "pressure_hpa" => {
        "short" => "P",
        "unit"  => "hpa",
    },
    "pressure_in" => {
        "short" => "Pin",
        "unit"  => "inhg",
    },
    "pressure_mm" => {
        "short" => "Pmm",
        "unit"  => "mmhg",
    },
    "pressure_psi" => {
        "short" => "Ppsi",
        "unit"  => "psi",
    },
    "pressure_psig" => {
        "short" => "Ppsi",
        "unit"  => "psig",
    },
    "pressureabs" => {
        "unified" => "pressureabs_hpa",    # link only
    },
    "pressureabs_hpa" => {
        "short" => "Pa",
        "unit"  => "hpa",
    },
    "pressureabs_in" => {
        "short" => "Pain",
        "unit"  => "inhg",
    },
    "pressureabs_mm" => {
        "short" => "Pamm",
        "unit"  => "mmhg",
    },
    "pressureabs_psi" => {
        "short" => "Ppsia",
        "unit"  => "psia",
    },
    "pressureabs_psia" => {
        "short" => "Ppsia",
        "unit"  => "psia",
    },
    "rain" => {
        "unified" => "rain_mm",    # link only
    },
    "rain_mm" => {
        "short" => "R",
        "unit"  => "mm",
    },
    "rain_in" => {
        "short" => "Rin",
        "unit"  => "in",
    },
    "rain_day" => {
        "unified" => "rain_day_mm",    # link only
    },
    "rain_day_mm" => {
        "short" => "Rd",
        "unit"  => "mm",
    },
    "rain_day_in" => {
        "short" => "Rdin",
        "unit"  => "in",
    },
    "rain_week" => {
        "unified" => "rain_week_mm",    # link only
    },
    "rain_week_mm" => {
        "short" => "Rw",
        "unit"  => "mm",
    },
    "rain_week_in" => {
        "short" => "Rwin",
        "unit"  => "in",
    },
    "rain_month" => {
        "unified" => "rain_month_mm",    # link only
    },
    "rain_month_mm" => {
        "short" => "Rm",
        "unit"  => "mm",
    },
    "rain_month_in" => {
        "short" => "Rmin",
        "unit"  => "in",
    },
    "rain_year" => {
        "unified" => "rain_year_mm",     # link only
    },
    "rain_year_mm" => {
        "short" => "Ry",
        "unit"  => "mm",
    },
    "rain_year_in" => {
        "short" => "Ryin",
        "unit"  => "in",
    },
    "sunshine" => {
        "unified" => "solarradiation",    # link only
    },
    "solarradiation" => {
        "short" => "S",
        "unit"  => "wpsm",
    },
    "temp" => {
        "unified" => "temperature_c",     # link only
    },
    "temp_c" => {
        "unified" => "temperature_c",     # link only
    },
    "temp_f" => {
        "unified" => "temperature_f",     # link only
    },
    "temp_k" => {
        "unified" => "temperature_k",     # link only
    },
    "temperature" => {
        "unified" => "temperature_c",     # link only
    },
    "temperature_c" => {
        "short" => "T",
        "unit"  => "c",
    },
    "temperature_f" => {
        "short" => "Tf",
        "unit"  => "f",
    },
    "temperature_k" => {
        "short" => "Tk",
        "unit"  => "k",
    },
    "visibility" => {
        "unified" => "visibility_km",    # link only
    },
    "visibility_km" => {
        "short" => "V",
        "unit"  => "km",
    },
    "visibility_mi" => {
        "short" => "Vmi",
        "unit"  => "mi",
    },
    "wind_chill" => {
        "unified" => "wind_chill_c",     # link only
    },
    "wind_chill_c" => {
        "short" => "Wc",
        "unit"  => "c",
    },
    "wind_chill_f" => {
        "short" => "Wcf",
        "unit"  => "f",
    },
    "wind_chill_k" => {
        "short" => "Wck",
        "unit"  => "k",
    },
    "wind_compasspoint" => {
        "short" => "Wdc",
    },
    "windspeeddirection" => {
        "unified" => "wind_compasspoint",    # link only
    },
    "winddirectiontext" => {
        "unified" => "wind_compasspoint",    # link only
    },
    "wind_direction" => {
        "short" => "Wd",
        "unit"  => "degree",
    },
    "wind_dir" => {
        "unified" => "wind_direction",       # link only
    },
    "winddir" => {
        "unified" => "wind_direction",       # link only
    },
    "winddirection" => {
        "unified" => "wind_direction",       # link only
    },
    "wind_gust" => {
        "unified" => "wind_gust_kmh",        # link only
    },
    "wind_gust_kmh" => {
        "short" => "Wg",
        "unit"  => "kmh",
    },
    "wind_gust_bft" => {
        "short" => "Wgbft",
        "unit"  => "bft",
    },
    "wind_gust_fts" => {
        "short" => "Wgfts",
        "unit"  => "fts",
    },
    "wind_gust_kn" => {
        "short" => "Wgkn",
        "unit"  => "kn",
    },
    "wind_gust_mph" => {
        "short" => "Wgmph",
        "unit"  => "mph",
    },
    "wind_gust_mps" => {
        "short" => "Wgmps",
        "unit"  => "mps",
    },
    "wind_speed" => {
        "unified" => "wind_speed_kmh",    # link only
    },
    "wind_speed_kmh" => {
        "short" => "Ws",
        "unit"  => "kmh",
    },
    "wind_speed_bft" => {
        "short" => "Wsbft",
        "unit"  => "bft",
    },
    "wind_speed_fts" => {
        "short" => "Wsfts",
        "unit"  => "fts",
    },
    "wind_speed_kn" => {
        "short" => "Wskn",
        "unit"  => "kn",
    },
    "wind_speed_mph" => {
        "short" => "Wsmph",
        "unit"  => "mph",
    },
    "wind_speed_mps" => {
        "short" => "Wsmps",
        "unit"  => "mps",
    },
);

# Get reading short name from reading name (e.g. for weather logging)
sub rname2rsname($) {
    my ($reading) = @_;
    my $r = lc($reading);

    if ( $weather_readings{$r}{"short"} ) {
        return $weather_readings{$r}{"short"};
    }
    elsif ( $weather_readings{$r}{"unified"} ) {
        my $dr = $weather_readings{$r}{"unified"};
        return $weather_readings{$dr}{"short"};
    }

    return $reading;
}

# Get unit details in local language from reading name as hash
sub rname2unitDetails ($;$) {
    my ( $reading, $lang ) = @_;
    my $details;
    my $r = lc($reading);
    my $u;
    my %return;

    # known alias reading names
    if ( $weather_readings{$r}{"unified"} ) {
        my $dr = $weather_readings{$r}{"unified"};
        $return{"unified"} = $dr;
        $return{"short"}   = $weather_readings{$dr}{"short"};
        $u                 = $weather_readings{$dr}{"unit"}
          if ( $weather_readings{$dr}{"unit"} );
    }

    # known standard reading names
    elsif ( $weather_readings{$r}{"short"} ) {
        $return{"unified"} = $r;
        $return{"short"}   = $weather_readings{$r}{"short"};
        $u = $weather_readings{$r}{"unit"} if ( $weather_readings{$r}{"unit"} );
    }

    # just guessing the unit from reading name
    elsif ( $r =~ /_([a-z]+)$/ ) {
        $u = $1;
    }

    return if ( !%return && !$u );
    return \%return if ( !$u );

    my $unitDetails = UnitDetails( $u, $lang );

    if ( ref($unitDetails) eq "HASH" ) {
        foreach my $k ( keys %{$unitDetails} ) {
            $return{$k} = $unitDetails->{$k};
        }
    }

    return \%return;
}

# Get unified reading name from reading name
sub rname2urname ($) {
    my ($reading) = @_;
    my $r = lc($reading);

    return $weather_readings{$r}{"unified"}
      if ( $weather_readings{$r}{"unified"} );
    return $reading;
}

#################################
### Inner metric conversions
###

# Temperature: convert Celsius to Kelvin
sub c2k($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data + 273.15, $rnd );
}

# Temperature: convert Kelvin to Celsius
sub k2c($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data - 273.15, $rnd );
}

# Speed: convert km/h (kilometer per hour) to m/s (meter per second)
sub kph2mps($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 3.6, $rnd );
}

# Speed: convert m/s (meter per second) to km/h (kilometer per hour)
sub mps2kph($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 3.6, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to mmHg (milimeter of Mercury)
sub hpa2mmhg($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.00750061561303, $rnd );
}

#################################
### Metric to angloamerican conversions
###

# Temperature: convert Celsius to Fahrenheit
sub c2f($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 1.8 + 32, $rnd );
}

# Temperature: convert Kelvin to Fahrenheit
sub k2f($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( ( $data - 273.15 ) * 1.8 + 32, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to in (inches of Mercury)
sub hpa2inhg($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.02952998751, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to PSI (Pound force per square inch)
sub hpa2psi($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 100.00014504, $rnd );
}

# Speed: convert km/h (kilometer per hour) to mph (miles per hour)
sub kph2mph($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.621, $rnd );
}

# Length: convert mm (milimeter) to in (inch)
sub mm2in($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.039370, $rnd );
}

# Length: convert cm (centimeter) to in (inch)
sub cm2in($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.39370, $rnd );
}

# Length: convert m (meter) to ft (feet)
sub m2ft($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 3.2808, $rnd );
}

#################################
### Inner Angloamerican conversions
###

# Speed: convert mph (miles per hour) to ft/s (feet per second)
sub mph2fts($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 1.467, $rnd );
}

# Speed: convert ft/s (feet per second) to mph (miles per hour)
sub fts2mph($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 1.467, $rnd );
}

#################################
### Angloamerican to Metric conversions
###

# Temperature: convert Fahrenheit to Celsius
sub f2c($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( ( $data - 32 ) * 0.5556, $rnd );
}

# Temperature: convert Fahrenheit to Kelvin
sub f2k($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( ( $data - 32 ) / 1.8 + 273.15, $rnd );
}

# Pressure: convert in (inches of Mercury) to hPa (hecto Pascal)
sub inhg2hpa($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 33.8638816, $rnd );
}

# Pressure: convert PSI (Pound force per square inch) to hPa (hecto Pascal)
sub psi2hpa($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 100.00014504, $rnd );
}

# Speed: convert mph (miles per hour) to km/h (kilometer per hour)
sub mph2kph($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 1.609344, $rnd );
}

# Length: convert in (inch) to mm (milimeter)
sub in2mm($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 25.4, $rnd );
}

# Length: convert in (inch) to cm (centimeter)
sub in2cm($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 0.39370, $rnd );
}

# Length: convert ft (feet) to m (meter)
sub ft2m($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data / 3.2808, $rnd );
}

#################################
### Angular conversions
###

# convert direction in degree to point of the compass
sub degrees2compasspoint($;$) {
    my ( $azimuth, $lang ) = @_;

    my $directions_txt_i18n;

    if ( $lang && defined( $compasspoint_txt{$lang} ) ) {
        $directions_txt_i18n = $compasspoint_txt{$lang};
    }
    else {
        $directions_txt_i18n = $compasspoint_txt{en};
    }

    return @$directions_txt_i18n[
      int( ( ( $azimuth + 11.25 ) % 360 ) / 22.5 )
    ];
}

#################################
### Solar conversions
###

# Power: convert uW/cm2 (micro watt per square centimeter) to UV-Index
sub uwpscm2uvi($) {
    my ($data) = @_;

    # Forum topic,44403.msg501704.html#msg501704
    return int( ( $data - 100 ) / 450 + 1 );
}

# Power: convert lux to W/m2 (watt per square meter)
sub lux2wpsm($;$) {
    my ( $data, $rnd ) = @_;

    # Forum topic,44403.msg501704.html#msg501704
    return roundX( $data / 126.7, $rnd );
}

#################################
### Nautic unit conversions
###

# Speed: convert km/h to knots
sub kph2kn($;$) {
    my ( $data, $rnd ) = @_;
    return roundX( $data * 0.539956803456, $rnd );
}

# Speed: convert km/h to Beaufort wind force scale
sub kph2bft($) {
    my ($data) = @_;
    my $v = "0";

    if ( $data >= 118 ) {
        $v = "12";
    }
    elsif ( $data >= 103 ) {
        $v = "11";
    }
    elsif ( $data >= 89 ) {
        $v = "10";
    }
    elsif ( $data >= 75 ) {
        $v = "9";
    }
    elsif ( $data >= 62 ) {
        $v = "8";
    }
    elsif ( $data >= 50 ) {
        $v = "7";
    }
    elsif ( $data >= 39 ) {
        $v = "6";
    }
    elsif ( $data >= 29 ) {
        $v = "5";
    }
    elsif ( $data >= 20 ) {
        $v = "4";
    }
    elsif ( $data >= 12 ) {
        $v = "3";
    }
    elsif ( $data >= 6 ) {
        $v = "2";
    }
    elsif ( $data >= 1 ) {
        $v = "1";
    }

    return $v;
}

# Speed: convert mph (miles per hour) to Beaufort wind force scale
sub mph2bft($) {
    my ($data) = @_;
    my $v = "0";

    if ( $data >= 73 ) {
        $v = "12";
    }
    elsif ( $data >= 64 ) {
        $v = "11";
    }
    elsif ( $data >= 55 ) {
        $v = "10";
    }
    elsif ( $data >= 47 ) {
        $v = "9";
    }
    elsif ( $data >= 39 ) {
        $v = "8";
    }
    elsif ( $data >= 32 ) {
        $v = "7";
    }
    elsif ( $data >= 25 ) {
        $v = "6";
    }
    elsif ( $data >= 19 ) {
        $v = "5";
    }
    elsif ( $data >= 13 ) {
        $v = "4";
    }
    elsif ( $data >= 8 ) {
        $v = "3";
    }
    elsif ( $data >= 4 ) {
        $v = "2";
    }
    elsif ( $data >= 1 ) {
        $v = "1";
    }

    return $v;
}

####################
# HELPER FUNCTIONS

sub roundX($;$) {
    my ( $v, $n ) = @_;
    $n = 1 if ( !$n );
    return sprintf( "%.${n}f", $v );
}

1;

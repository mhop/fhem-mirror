# $Id$

package main;

use strict;
use warnings;

sub UConv_Initialize() {
}

package UConv;
use Scalar::Util qw(looks_like_number);
use Data::Dumper;

####################
# Translations

my %pressure_trend = ( "=" => "0", "+" => "1", "-" => "2" );

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
sub direction2compasspoint($;$) {
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

#################################
### Textual unit conversions
###

# Condition: convert humidity (percent) to humidity condition
sub humidity2condition($) {
    my ($data) = @_;
    my $v = "dry";

    if ( $data >= 80 ) {
        $v = "wet";
    }
    elsif ( $data >= 70 ) {
        $v = "high";
    }
    elsif ( $data >= 50 ) {
        $v = "optimal";
    }
    elsif ( $data >= 40 ) {
        $v = "low";
    }

    return $v;
}

# Condition: convert UV-Index to UV condition
sub uvi2condition($) {
    my ($data) = @_;
    my $v = "low";

    if ( $data > 11 ) {
        $v = "extreme";
    }
    elsif ( $data > 8 ) {
        $v = "veryhigh";
    }
    elsif ( $data > 6 ) {
        $v = "high";
    }
    elsif ( $data > 3 ) {
        $v = "moderate";
    }

    return $v;
}

sub pressuretrend2sym($) {
    my ($data) = @_;
    return $data if !$pressure_trend_sym{$data};
    return $pressure_trend_sym{$data};
}

sub pressuretrend2condition($;$) {
    my ( $data, $lang ) = @_;
    my $l = ( $lang ? lc($lang) : "en" );
    return $pressure_trend_txt{$l}{$data}
      if $pressure_trend_txt{$l}{$data};
    return $pressure_trend_txt{"en"}{$data};
}

sub sym2pressuretrend($) {
    my ($data) = @_;
    return $data if !$pressure_trend{$data};
    return $pressure_trend{$data};
}

sub values2weathercondition($$$$$) {
    my ( $temp, $hum, $light, $isday, $israining ) = @_;
    my $condition = "clear";

    if ( $israining eq "1" ) {
        $condition = "rain";
    }
    elsif ( $light > 40000 ) {
        $condition = "sunny";
    }
    elsif ( $isday eq "1" ) {
        $condition = "cloudy";
    }

    return $condition;
}

#################################
### Logfile integer conversions
###

sub activity2log($) {
    my ($data) = @_;

    return "1" if ( $data =~ /^(alive|ok)$/i );
    return "0";
}

#TODO rewrite for Unit.pm
sub fmtTime($) {
    my ($value) = @_;
    my $suffix = ' s';

    if ( $value >= 60 ) {
        $value = sprintf( "%.1f", $value / 60 );
        $suffix = ' min';

        if ( $value >= 60 ) {
            $value = sprintf( "%.1f", $value / 60 );
            $suffix = ' h';
        }
    }

    return ( $value, $suffix ) if (wantarray);
    return $value . $suffix;
}

####################
# HELPER FUNCTIONS

sub roundX($;$) {
    my ( $v, $n ) = @_;
    $n = 1 if ( !$n );
    return sprintf( "%.${n}f", $v );
}

1;

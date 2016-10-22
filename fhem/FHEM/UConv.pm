
# $Id$

package main;

use strict;
use warnings;

sub UConv_Initialize() {
}

package UConv;

sub round($;$) {
    my ( $v, $n ) = @_;
    $n = 1 if ( !$n );
    return sprintf( "%.${n}f", $v );
}

#################################
### Inner metric conversions
###

# Temperature: convert Celsius to Kelvin
sub c2k($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data + 273.15, $rnd );
}

# Temperature: convert Kelvin to Celsius
sub k2c($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data - 273.15, $rnd );
}

# Speed: convert km/h (kilometer per hour) to m/s (meter per second)
sub kph2mps($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data / 3.6, $rnd );
}

# Speed: convert m/s (meter per second) to km/h (kilometer per hour)
sub mps2kph($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 3.6, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to mmHg (milimeter of Mercury)
sub hpa2mmhg($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 0.00750061561303, $rnd );
}

#################################
### Metric to angloamerican conversions
###

# Temperature: convert Celsius to Fahrenheit
sub c2f($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 1.8 + 32, $rnd );
}

# Temperature: convert Kelvin to Fahrenheit
sub k2f($;$) {
    my ( $data, $rnd ) = @_;
    return round( ( $data - 273.15 ) * 1.8 + 32, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to in (inches of Mercury)
sub hpa2inhg($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 0.02952998751, $rnd );
}

# Pressure: convert hPa (hecto Pascal) to PSI (Pound force per square inch)
sub hpa2psi($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 100.00014504, $rnd );
}

# Speed: convert km/h (kilometer per hour) to mph (miles per hour)
sub kph2mph($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 0.621, $rnd );
}

# Length: convert mm (milimeter) to in (inch)
sub mm2in($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 0.039370, $rnd );
}

# Length: convert cm (centimeter) to in (inch)
sub cm2in($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 0.39370, $rnd );
}

# Length: convert m (meter) to ft (feet)
sub m2ft($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 3.2808, $rnd );
}

#################################
### Inner Angloamerican conversions
###

# Speed: convert mph (miles per hour) to ft/s (feet per second)
sub mph2fts($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 1.467, $rnd );
}

#################################
### Angloamerican to Metric conversions
###

# Temperature: convert Fahrenheit to Celsius
sub f2c($;$) {
    my ( $data, $rnd ) = @_;
    return round( ( $data - 32 ) * 0.5556, $rnd );
}

# Temperature: convert Fahrenheit to Kelvin
sub f2k($;$) {
    my ( $data, $rnd ) = @_;
    return round( ( $data - 32 ) / 1.8 + 273.15, $rnd );
}

# Pressure: convert in (inches of Mercury) to hPa (hecto Pascal)
sub inhg2hpa($) {
    my ( $data, $rnd ) = @_;
    return round( $data * 33.8638816, $rnd );
}

# Pressure: convert PSI (Pound force per square inch) to hPa (hecto Pascal)
sub psi2hpa($) {
    my ( $data, $rnd ) = @_;
    return round( $data / 100.00014504, $rnd );
}

# Speed: convert mph (miles per hour) to km/h (kilometer per hour)
sub mph2kph($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 1.609344, $rnd );
}

# Length: convert in (inch) to mm (milimeter)
sub in2mm($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 25.4, $rnd );
}

# Length: convert in (inch) to cm (centimeter)
sub in2cm($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data / 0.39370, $rnd );
}

# Length: convert ft (feet) to m (meter)
sub ft2m($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data / 3.2808, $rnd );
}

#################################
### Angular conversions
###

# convert direction in degree to compass point short text
sub direction2compasspoint($;$) {
    my ( $azimuth, $ext ) = @_;

    my @compasspointsExt = (
        'North', 'North-Northeast', 'North-East', 'East-Northeast',
        'East',  'East-Southeast',  'South-East', 'South-Southeast',
        'South', 'South-Southwest', 'South-West', 'West-Southwest',
        'West',  'West-Northwest',  'North-West', 'North-Northwest',
        'North'
    );
    return @compasspointsExt[ sprintf( '%.0f', $azimuth / 22.5 ) ] if ($ext);

    my @compasspoints = (
        'N',  'NNE', 'NE', 'ENE', 'E',  'ESE', 'SE', 'SSE', 'S', 'SSW',
        'SW', 'WSW', 'W',  'WNW', 'NW', 'NNW', 'N'
    );
    return @compasspoints[ sprintf( '%.0f', $azimuth / 22.5 ) ];
}

# convert direction in degree to compass point long text
sub direction2compasspointLong($) {
    my ($azimuth) = @_;
    return ( direction2compasspoint( $azimuth, 1 ) );
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
    return round( $data / 126.7, $rnd );
}

#################################
### Nautic unit conversions
###

# Speed: convert km/h to knots
sub kph2kn($;$) {
    my ( $data, $rnd ) = @_;
    return round( $data * 0.539956803456, $rnd );
}

# Speed: convert mph (miles per hour) to knots
#sub mph2kn($;$) {
#    my ( $data, $rnd ) = @_;
#}

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

1;

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
        "unit"      => "°C",
        "unit_long" => {
            "de" => "Grad Celsius",
            "en" => "Degree Celsius",
            "fr" => "Degree Celsius",
            "nl" => "Degree Celsius",
            "pl" => "Degree Celsius",
        },
    },
    "f" => {
        "unit"      => "°F",
        "unit_long" => {
            "de" => "Grad Fahrenheit",
            "en" => "Degree Fahrenheit",
            "fr" => "Degree Fahrenheit",
            "nl" => "Degree Fahrenheit",
            "pl" => "Degree Fahrenheit",
        },
    },
    "k" => {
        "unit"      => "K",
        "unit_long" => {
            "de" => "Kelvin",
            "en" => "Kelvin",
            "fr" => "Kelvin",
            "nl" => "Kelvin",
            "pl" => "Kelvin",
        },
    },

    # percent
    "pct" => {
        "unit_symbol" => "%",
        "unit_long"   => {
            "de" => "Prozent",
            "en" => "percent",
            "fr" => "percent",
            "nl" => "percent",
            "pl" => "percent",
        },
    },

    # speed
    "bft" => {
        "unit"      => "bft",
        "unit_long" => {
            "de" => "Windstärke",
            "en" => "wind force",
            "fr" => "wind force",
            "nl" => "wind force",
            "pl" => "wind force",
        },
        "txt_format_long" => "%unit_long% %value%",
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
    "bar" => {
        "unit"      => "bar",
        "unit_long" => {
            "de" => "Bar",
            "en" => "Bar",
            "fr" => "Bar",
            "nl" => "Bar",
            "pl" => "Bar",
        },
    },
    "pa" => {
        "unit"      => "Pa",
        "unit_long" => {
            "de" => "Pascal",
            "en" => "Pascal",
            "fr" => "Pascal",
            "nl" => "Pascal",
            "pl" => "Pascal",
        },
    },
    "hpa" => {
        "unit"      => "hPa",
        "unit_long" => {
            "de" => "Hecto Pascal",
            "en" => "Hecto Pascal",
            "fr" => "Hecto Pascal",
            "nl" => "Hecto Pascal",
            "pl" => "Hecto Pascal",
        },
    },
    "inhg" => {
        "unit"      => "inHg",
        "unit_long" => {
            "de" => "Zoll Quecksilbersäule",
            "en" => "Inches of Mercury",
            "fr" => "Inches of Mercury",
            "nl" => "Inches of Mercury",
            "pl" => "Inches of Mercury",
        },
    },
    "mmhg" => {
        "unit"      => "mmHg",
        "unit_long" => {
            "de" => "Millimeter Quecksilbersäule",
            "en" => "Milimeter of Mercury",
            "fr" => "Milimeter of Mercury",
            "nl" => "Milimeter of Mercury",
            "pl" => "Milimeter of Mercury",
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
    "cd" => {
        "unit"      => "cd",
        "unit_long" => {
            "de" => "Candela",
            "en" => "Candela",
            "fr" => "Candela",
            "nl" => "Candela",
            "pl" => "Candela",
        },
    },
    "lx" => {
        "unit"      => "lx",
        "unit_long" => {
            "de" => "Lux",
            "en" => "Lux",
            "fr" => "Lux",
            "nl" => "Lux",
            "pl" => "Lux",
        },
    },
    "lm" => {
        "unit"      => "lm",
        "unit_long" => {
            "de" => "Lumen",
            "en" => "Lumen",
            "fr" => "Lumen",
            "nl" => "Lumen",
            "pl" => "Lumen",
        },
    },
    "uvi" => {
        "unit"      => "UV-Index",
        "unit_long" => {
            "de" => "UV-Index",
            "en" => "UV-Index",
            "fr" => "UV-Index",
            "nl" => "UV-Index",
            "pl" => "UV-Index",
        },
    },
    "uwpscm" => {
        "unit"      => "uW/cm2",
        "unit_long" => {
            "de" => "Micro-Watt pro Quadratzentimeter",
            "en" => "Micro-Watt per square centimeter",
            "fr" => "Micro-Watt per square centimeter",
            "nl" => "Micro-Watt per square centimeter",
            "pl" => "Micro-Watt per square centimeter",
        },
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

    "in" => {
        "unit_symbol" => "″",
        "unit"        => "in",
        "unit_long"   => {
            "de" => "Zoll",
            "en" => "inch",
            "fr" => "inch",
            "nl" => "inch",
            "pl" => "inch",
        },
        "unit_long_pl" => {
            "de" => "Zoll",
            "en" => "inches",
            "fr" => "inches",
            "nl" => "inches",
            "pl" => "inches",
        },
        "txt_format"         => "%value%%unit_symbol%",
        "txt_format_long"    => "%value% %unit_long%",
        "txt_format_long_pl" => "%value% %unit_long_pl%",
    },

    "ft" => {
        "unit_symbol" => "′",
        "unit"        => "ft",
        "unit_long"   => {
            "de" => "Fuss",
            "en" => "foot",
            "fr" => "foot",
            "nl" => "foot",
            "pl" => "foot",
        },
        "unit_long_pl" => {
            "de" => "Fuss",
            "en" => "feet",
            "fr" => "feet",
            "nl" => "feet",
            "pl" => "feet",
        },
        "txt_format"         => "%value%%unit_symbol%",
        "txt_format_long"    => "%value% %unit_long%",
        "txt_format_long_pl" => "%value% %unit_long_pl%",
    },
    "yd" => {
        "unit"      => "yd",
        "unit_long" => {
            "de" => "Yard",
            "en" => "yard",
            "fr" => "yard",
            "nl" => "yard",
            "pl" => "yard",
        },
        "unit_long_pl" => {
            "de" => "Yards",
            "en" => "yards",
            "fr" => "yards",
            "nl" => "yards",
            "pl" => "yards",
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

    # time
    "sec" => {
        "unit" => {
            "de" => "s",
            "en" => "s",
            "fr" => "s",
            "nl" => "s",
            "pl" => "s",
        },
        "unit_long" => {
            "de" => "Sekunde",
            "en" => "second",
            "fr" => "second",
            "nl" => "second",
            "pl" => "second",
        },
        "unit_long_pl" => {
            "de" => "Sekunden",
            "en" => "seconds",
            "fr" => "seconds",
            "nl" => "seconds",
            "pl" => "seconds",
        },
    },

    "min" => {
        "unit" => {
            "de" => "Min",
            "en" => "min",
            "fr" => "min",
            "nl" => "min",
            "pl" => "min",
        },
        "unit_long" => {
            "de" => "Minute",
            "en" => "minute",
            "fr" => "minute",
            "nl" => "minute",
            "pl" => "minute",
        },
        "unit_long_pl" => {
            "de" => "Minuten",
            "en" => "minutes",
            "fr" => "minutes",
            "nl" => "minutes",
            "pl" => "minutes",
        },
    },

    "hr" => {
        "unit" => {
            "de" => "Std",
            "en" => "hr",
            "fr" => "hr",
            "nl" => "hr",
            "pl" => "hr",
        },
        "unit_long" => {
            "de" => "Stunde",
            "en" => "hour",
            "fr" => "hour",
            "nl" => "hour",
            "pl" => "hour",
        },
        "unit_long_pl" => {
            "de" => "Stunden",
            "en" => "hours",
            "fr" => "hours",
            "nl" => "hours",
            "pl" => "hours",
        },
    },

    "d" => {
        "unit" => {
            "de" => "T",
            "en" => "d",
            "fr" => "d",
            "nl" => "d",
            "pl" => "d",
        },
        "unit_long" => {
            "de" => "Tag",
            "en" => "day",
            "fr" => "day",
            "nl" => "day",
            "pl" => "day",
        },
        "unit_long_pl" => {
            "de" => "Tage",
            "en" => "days",
            "fr" => "days",
            "nl" => "days",
            "pl" => "days",
        },
    },

    "w" => {
        "unit" => {
            "de" => "W",
            "en" => "w",
            "fr" => "w",
            "nl" => "w",
            "pl" => "w",
        },
        "unit_long" => {
            "de" => "Woche",
            "en" => "week",
            "fr" => "week",
            "nl" => "week",
            "pl" => "week",
        },
        "unit_long_pl" => {
            "de" => "Wochen",
            "en" => "weeks",
            "fr" => "weeks",
            "nl" => "weeks",
            "pl" => "weeks",
        },
    },

    "m" => {
        "unit" => {
            "de" => "M",
            "en" => "m",
            "fr" => "m",
            "nl" => "m",
            "pl" => "m",
        },
        "unit_long" => {
            "de" => "Monat",
            "en" => "month",
            "fr" => "month",
            "nl" => "month",
            "pl" => "month",
        },
        "unit_long_pl" => {
            "de" => "Monate",
            "en" => "Monat",
            "fr" => "Monat",
            "nl" => "Monat",
            "pl" => "Monat",
        },
    },

    "y" => {
        "unit" => {
            "de" => "J",
            "en" => "y",
            "fr" => "y",
            "nl" => "y",
            "pl" => "y",
        },
        "unit_long" => {
            "de" => "Jahr",
            "en" => "year",
            "fr" => "year",
            "nl" => "year",
            "pl" => "year",
        },
        "unit_long_pl" => {
            "de" => "Jahre",
            "en" => "years",
            "fr" => "years",
            "nl" => "years",
            "pl" => "years",
        },
    },

    # mass
    "b" => {
        "unit"      => "B",
        "unit_long" => {
            "de" => "Bel",
            "en" => "Bel",
            "fr" => "Bel",
            "nl" => "Bel",
            "pl" => "Bel",
        },
    },
    "db" => {
        "unit"      => "dB",
        "unit_long" => {
            "de" => "Dezibel",
            "en" => "Decibel",
            "fr" => "Decibel",
            "nl" => "Decibel",
            "pl" => "Decibel",
        },
    },
    "mol" => {
        "unit" => "mol",
    },
    "n" => {
        "unit"      => "N",
        "unit_long" => {
            "de" => "Newton",
            "en" => "Newton",
            "fr" => "Newton",
            "nl" => "Newton",
            "pl" => "Newton",
        },
    },
    "g" => {
        "unit"      => "g",
        "unit_long" => {
            "de" => "Gramm",
            "en" => "gram",
            "fr" => "gram",
            "nl" => "gram",
            "pl" => "gram",
        },
    },
    "dg" => {
        "unit"      => "dg",
        "unit_long" => {
            "de" => "Dekagramm",
            "en" => "dekagram",
            "fr" => "dekagram",
            "nl" => "dekagram",
            "pl" => "dekagram",
        },
    },
    "kg" => {
        "unit"      => "kg",
        "unit_long" => {
            "de" => "Kilogramm",
            "en" => "kilogram",
            "fr" => "kilogram",
            "nl" => "kilogram",
            "pl" => "kilogram",
        },
    },
    "t" => {
        "unit"      => "t",
        "unit_long" => {
            "de" => "Tonne",
            "en" => "ton",
            "fr" => "ton",
            "nl" => "ton",
            "pl" => "ton",
        },
        "unit_long_pl" => {
            "de" => "Tonnen",
            "en" => "tons",
            "fr" => "tons",
            "nl" => "tons",
            "pl" => "tons",
        },
    },
    "ml" => {
        "unit"      => "ml",
        "unit_long" => {
            "de" => "Milliliter",
            "en" => "mililitre",
            "fr" => "mililitre",
            "nl" => "mililitre",
            "pl" => "mililitre",
        },
        "unit_long_pl" => {
            "de" => "Milliliter",
            "en" => "mililitres",
            "fr" => "mililitres",
            "nl" => "mililitres",
            "pl" => "mililitres",
        },
    },
    "l" => {
        "unit"      => "l",
        "unit_long" => {
            "de" => "Liter",
            "en" => "litre",
            "fr" => "litre",
            "nl" => "litre",
            "pl" => "litre",
        },
        "unit_long_pl" => {
            "de" => "Liter",
            "en" => "litres",
            "fr" => "litres",
            "nl" => "litres",
            "pl" => "litres",
        },
    },
    "oz" => {
        "unit"      => "oz",
        "unit_long" => {
            "de" => "Unze",
            "en" => "ounce",
            "fr" => "ounce",
            "nl" => "ounce",
            "pl" => "ounce",
        },
        "unit_long_pl" => {
            "de" => "Unzen",
            "en" => "ounces",
            "fr" => "ounces",
            "nl" => "ounces",
            "pl" => "ounces",
        },
    },
    "floz" => {
        "unit"      => "fl oz",
        "unit_long" => {
            "de" => "fl. Unze",
            "en" => "fl. ounce",
            "fr" => "fl. ounce",
            "nl" => "fl. ounce",
            "pl" => "fl. ounce",
        },
        "unit_long_pl" => {
            "de" => "fl. Unzen",
            "en" => "fl. ounces",
            "fr" => "fl. ounces",
            "nl" => "fl. ounces",
            "pl" => "fl. ounces",
        },
    },
    "ozfl" => {
        "unit"      => "fl oz",
        "unit_long" => {
            "de" => "fl. Unze",
            "en" => "fl. ounce",
            "fr" => "fl. ounce",
            "nl" => "fl. ounce",
            "pl" => "fl. ounce",
        },
        "unit_long_pl" => {
            "de" => "fl. Unzen",
            "en" => "fl. ounces",
            "fr" => "fl. ounces",
            "nl" => "fl. ounces",
            "pl" => "fl. ounces",
        },
    },
    "quart" => {
        "unit"      => "quart",
        "unit_long" => {
            "de" => "Quart",
            "en" => "quart",
            "fr" => "quart",
            "nl" => "quart",
            "pl" => "quart",
        },
        "unit_long_pl" => {
            "de" => "Quarts",
            "en" => "quarts",
            "fr" => "quarts",
            "nl" => "quarts",
            "pl" => "quarts",
        },
    },
    "gallon" => {
        "unit"      => "gallon",
        "unit_long" => {
            "de" => "Gallone",
            "en" => "gallon",
            "fr" => "gallon",
            "nl" => "gallon",
            "pl" => "gallon",
        },
        "unit_long_pl" => {
            "de" => "Gallonen",
            "en" => "gallons",
            "fr" => "gallons",
            "nl" => "gallons",
            "pl" => "gallons",
        },
    },
    "gallon" => {
        "unit"      => "gallon",
        "unit_long" => {
            "de" => "Gallone",
            "en" => "gallon",
            "fr" => "gallon",
            "nl" => "gallon",
            "pl" => "gallon",
        },
        "unit_long_pl" => {
            "de" => "Gallonen",
            "en" => "gallons",
            "fr" => "gallons",
            "nl" => "gallons",
            "pl" => "gallons",
        },
    },
    "lb" => {
        "unit"      => "lb",
        "unit_long" => {
            "de" => "Pfund",
            "en" => "pound",
            "fr" => "pound",
            "nl" => "pound",
            "pl" => "pound",
        },
    },
    "lbs" => {
        "unit"      => "lbs",
        "unit_long" => {
            "de" => "Pfund",
            "en" => "pound",
            "fr" => "pound",
            "nl" => "pound",
            "pl" => "pound",
        },
    },

    # angular
    "deg" => {
        "unit"      => "°",
        "unit_long" => {
            "de" => "Grad",
            "en" => "degree",
            "fr" => "degree",
            "nl" => "degree",
            "pl" => "degree",
        },
    },

    # electric
    "a" => {
        "unit"      => "A",
        "unit_long" => {
            "de" => "Ampere",
            "en" => "Ampere",
            "fr" => "Ampere",
            "nl" => "Ampere",
            "pl" => "Ampere",
        },
    },

    "v" => {
        "unit"      => "V",
        "unit_long" => {
            "de" => "Volt",
            "en" => "Volt",
            "fr" => "Volt",
            "nl" => "Volt",
            "pl" => "Volt",
        },
    },

    "w" => {
        "unit"      => "Watt",
        "unit_long" => {
            "de" => "Watt",
            "en" => "Watt",
            "fr" => "Watt",
            "nl" => "Watt",
            "pl" => "Watt",
        },
    },

    "j" => {
        "unit"      => "J",
        "unit_long" => {
            "de" => "Joule",
            "en" => "Joule",
            "fr" => "Joule",
            "nl" => "Joule",
            "pl" => "Joule",
        },
    },

    "coul" => {
        "unit"      => "C",
        "unit_long" => {
            "de" => "Coulomb",
            "en" => "Coulomb",
            "fr" => "Coulomb",
            "nl" => "Coulomb",
            "pl" => "Coulomb",
        },
    },

    "far" => {
        "unit"      => "F",
        "unit_long" => {
            "de" => "Farad",
            "en" => "Farad",
            "fr" => "Farad",
            "nl" => "Farad",
            "pl" => "Farad",
        },
    },

    "ohm" => {
        "unit"      => "Ω",
        "unit_long" => {
            "de" => "Ohm",
            "en" => "Ohm",
            "fr" => "Ohm",
            "nl" => "Ohm",
            "pl" => "Ohm",
        },
    },

    "s" => {
        "unit"      => "S",
        "unit_long" => {
            "de" => "Siemens",
            "en" => "Siemens",
            "fr" => "Siemens",
            "nl" => "Siemens",
            "pl" => "Siemens",
        },
    },

    "wb" => {
        "unit"      => "Wb",
        "unit_long" => {
            "de" => "Weber",
            "en" => "Weber",
            "fr" => "Weber",
            "nl" => "Weber",
            "pl" => "Weber",
        },
    },

    "t" => {
        "unit"      => "T",
        "unit_long" => {
            "de" => "Tesla",
            "en" => "Tesla",
            "fr" => "Tesla",
            "nl" => "Tesla",
            "pl" => "Tesla",
        },
    },

    "h" => {
        "unit"      => "H",
        "unit_long" => {
            "de" => "Henry",
            "en" => "Henry",
            "fr" => "Henry",
            "nl" => "Henry",
            "pl" => "Henry",
        },
    },

    "bq" => {
        "unit"      => "Bq",
        "unit_long" => {
            "de" => "Becquerel",
            "en" => "Becquerel",
            "fr" => "Becquerel",
            "nl" => "Becquerel",
            "pl" => "Becquerel",
        },
    },

    "gy" => {
        "unit"      => "Gy",
        "unit_long" => {
            "de" => "Gray",
            "en" => "Gray",
            "fr" => "Gray",
            "nl" => "Gray",
            "pl" => "Gray",
        },
    },

    "sv" => {
        "unit"      => "Sv",
        "unit_long" => {
            "de" => "Sievert",
            "en" => "Sievert",
            "fr" => "Sievert",
            "nl" => "Sievert",
            "pl" => "Sievert",
        },
    },

    "kat" => {
        "unit"      => "kat",
        "unit_long" => {
            "de" => "Katal",
            "en" => "Katal",
            "fr" => "Katal",
            "nl" => "Katal",
            "pl" => "Katal",
        },
    },

);

# Get unit details in local language as hash
sub UnitDetails ($;$) {
    my ( $unit, $lang ) = @_;
    my $u = lc($unit);
    my $l = ( $lang ? lc($lang) : "en" );
    my %details;

    if ( defined( $units{$u} ) ) {
        foreach my $k ( keys %{ $units{$u} } ) {
            $details{$k} = $units{$u}{$k};
        }
        $details{"unit_abbr"} = $u;

        if ($lang) {
            $details{"lang"} = $l;

            if ( $details{"txt_format"} ) {
                delete $details{"txt_format"};
                if ( $units{$u}{"txt_format"}{$l} ) {
                    $details{"txt_format"} = $units{$u}{"txt_format"}{$l};
                }
                elsif ( refs( $units{$u}{"txt_format"} ) ne "HASH" ) {
                    $details{"txt_format"} = $units{$u}{"txt_format"};
                }
            }

            if ( $details{"txt_format_long"} ) {
                delete $details{"txt_format_long"};
                if ( $units{$u}{"txt_format_long"}{$l} ) {
                    $details{"txt_format_long"} =
                      $units{$u}{"txt_format_long"}{$l};
                }
                elsif ( refs( $units{$u}{"txt_format_long"} ) ne "HASH" ) {
                    $details{"txt_format_long"} = $units{$u}{"txt_format_long"};
                }
            }

            if ( $details{"txt_format_long_pl"} ) {
                delete $details{"txt_format_long_pl"};
                if ( $units{$u}{"txt_format_long_pl"}{$l} ) {
                    $details{"txt_format_long_pl"} =
                      $units{$u}{"txt_format_long_pl"}{$l};
                }
                elsif ( refs( $units{$u}{"txt_format_long_pl"} ) ne "HASH" ) {
                    $details{"txt_format_long_pl"} =
                      $units{$u}{"txt_format_long_pl"};
                }
            }

            if ( $details{"unit_long"} ) {
                delete $details{"unit_long"};
                if ( $units{$u}{"unit_long"}{$l} ) {
                    $details{"unit_long"} = $units{$u}{"unit_long"}{$l};
                }
                elsif ( refs( $units{$u}{"unit_long"} ) ne "HASH" ) {
                    $details{"unit_long"} = $units{$u}{"unit_long"};
                }
            }

            if ( $details{"unit_long_pl"} ) {
                delete $details{"unit_long_pl"};
                if ( $units{$u}{"unit_long_pl"}{$l} ) {
                    $details{"unit_long_pl"} = $units{$u}{"unit_long_pl"}{$l};
                }
                elsif ( refs( $units{$u}{"unit_long_pl"} ) ne "HASH" ) {
                    $details{"unit_long_pl"} = $units{$u}{"unit_long_pl"};
                }
            }
        }

        return \%details;
    }
}

my %weather_readings = (
    "airpress" => {
        "unified" => "pressure_hpa",    # link only
    },
    "azimuth" => {
        "short" => "AZ",
        "unit"  => "deg",
    },
    "compasspoint" => {
        "short" => "CP",
    },
    "dewpoint" => {
        "unified" => "dewpoint_c",      # link only
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
    "elevation" => {
        "short" => "EL",
        "unit"  => "deg",
    },
    "feelslike" => {
        "unified" => "feelslike_c",    # link only
    },
    "feelslike_c" => {
        "short" => "Tf",
        "unit"  => "c",
    },
    "feelslike_f" => {
        "short" => "Tff",
        "unit"  => "f",
    },
    "heat_index" => {
        "unified" => "heat_index_c",    # link only
    },
    "heat_index_c" => {
        "short" => "HI",
        "unit"  => "c",
    },
    "heat_index_f" => {
        "short" => "HIf",
        "unit"  => "f",
    },
    "high" => {
        "unified" => "high_c",          # link only
    },
    "high_c" => {
        "short" => "Th",
        "unit"  => "c",
    },
    "high_f" => {
        "short" => "Thf",
        "unit"  => "f",
    },
    "humidity" => {
        "short" => "H",
        "unit"  => "pct",
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
    "horizon" => {
        "short" => "HORIZ",
        "unit"  => "deg",
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
        "unit"  => "pct",
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
        "short" => "Ti",
        "unit"  => "c",
    },
    "indoortemperature_f" => {
        "short" => "Tif",
        "unit"  => "f",
    },
    "indoortemperature_k" => {
        "short" => "Tik",
        "unit"  => "k",
    },
    "israining" => {
        "short" => "IR",
    },
    "level" => {
        "short" => "LVL",
        "unit"  => "pct",
    },
    "low" => {
        "unified" => "low_c",    # link only
    },
    "low_c" => {
        "short" => "Tl",
        "unit"  => "c",
    },
    "low_f" => {
        "short" => "Tlf",
        "unit"  => "f",
    },
    "luminosity" => {
        "short" => "L",
        "unit"  => "lx",
    },
    "pct" => {
        "short" => "PCT",
        "unit"  => "pct",
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
    "rain_night" => {
        "unified" => "rain_night_mm",    # link only
    },
    "rain_night_mm" => {
        "short" => "Rn",
        "unit"  => "mm",
    },
    "rain_night_in" => {
        "short" => "Rnin",
        "unit"  => "in",
    },
    "rain_week" => {
        "unified" => "rain_week_mm",     # link only
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
    "snow" => {
        "unified" => "snow_cm",          # link only
    },
    "snow_cm" => {
        "short" => "S",
        "unit"  => "cm",
    },
    "snow_in" => {
        "short" => "Sin",
        "unit"  => "in",
    },
    "snow_day" => {
        "unified" => "snow_day_cm",      # link only
    },
    "snow_day_cm" => {
        "short" => "Sd",
        "unit"  => "cm",
    },
    "snow_day_in" => {
        "short" => "Sdin",
        "unit"  => "in",
    },
    "snow_night" => {
        "unified" => "snow_night_cm",    # link only
    },
    "snow_night_cm" => {
        "short" => "Sn",
        "unit"  => "cm",
    },
    "snow_night_in" => {
        "short" => "Snin",
        "unit"  => "in",
    },
    "sunshine" => {
        "unified" => "solarradiation",    # link only
    },
    "solarradiation" => {
        "short" => "SR",
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
    "uv" => {
        "unified" => "uvi",    # link only
    },
    "uvi" => {
        "short" => "UV",
        "unit"  => "uvi",
    },
    "uvr" => {
        "short" => "UVR",
        "unit"  => "uwpscm",
    },
    "valvedesired" => {
        "unified" => "valve",    # link only
    },
    "valvepos" => {
        "unified" => "valve",    # link only
    },
    "valveposition" => {
        "unified" => "valve",    # link only
    },
    "valvepostc" => {
        "unified" => "valve",    # link only
    },
    "valve" => {
        "short" => "VAL",
        "unit"  => "pct",
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
        "unit"  => "deg",
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
sub rname2unitDetails ($;$$) {
    my ( $reading, $lang, $value ) = @_;
    my $details;
    my $r = lc($reading);
    my $l = ( $lang ? lc($lang) : "en" );
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
        $return{"value"} = $value if ( defined($value) );
    }

    return if ( !%return && !$u );
    return \%return if ( !$u );

    my $unitDetails = UnitDetails( $u, $l );

    if ( ref($unitDetails) eq "HASH" ) {
        $return{"unit_guess"} = "1" if ( !$return{"short"} );
        foreach my $k ( keys %{$unitDetails} ) {
            $return{$k} = $unitDetails->{$k};
        }
    }

    # generate combined value+unit strings
    if ( defined($value) ) {
        $return{"value"} = $value;

        if ( $return{"unit"} ) {
            my $txt = '%value% %unit%';
            $txt = $return{"txt_format"} if ( $return{"txt_format"} );

            foreach my $k ( keys %return ) {
                $txt =~ s/%$k%/$return{$k}/g;
            }

            $return{"value_unit"} = $txt;
        }

        # plural
        if (   Scalar::Util::looks_like_number($value)
            && $value > 1
            && $return{"unit_long_pl"} )
        {
            my $txt = '%value% %unit_long_pl%';
            $txt = $return{"txt_format_long_pl"}
              if ( $return{"txt_format_long_pl"} );

            foreach my $k ( keys %return ) {
                $txt =~ s/%$k%/$return{$k}/g;
            }

            $return{"value_unit_long"} = $txt;
        }

        # single
        elsif ( $return{"unit_long"} ) {
            my $txt = '%value% %unit_long%';
            $txt = $return{"txt_format_long"} if ( $return{"txt_format_long"} );

            foreach my $k ( keys %return ) {
                $txt =~ s/%$k%/$return{$k}/g;
            }

            $return{"value_unit_long"} = $txt;
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

# Generalized function for DbLog unit support
sub DbLog_split($$) {
    my ( $event, $device ) = @_;
    my ( $reading, $value, $unit ) = "";

    # exclude any multi-value events
    if ( $event =~ /(.*: +.*: +.*)+/ ) {
        ::Log3 $device, 5,
          "UConv::DbLog_split $device: Ignoring multi-value event $event";
        return undef;
    }

    # exclude sum and avg events
    elsif ( $event =~ /^(.*_sum[0-9]+m|.*_avg[0-9]+m): +.*/ ) {
        ::Log3 $device, 5,
          "UConv::DbLog_split $device: Ignoring sum/avg event $event";
        return undef;
    }

    # text conversions
    elsif ( $event =~ /^(pressure_trend): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $value   = "0" if ( $2 eq "=" );
        $value   = "1" if ( $2 eq "+" );
        $value   = "2" if ( $2 eq "-" );
    }
    elsif ( $event =~ /^(Activity): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $value   = "1" if ( $2 eq "alive" );
        $value   = "0" if ( $2 eq "dead" );
    }
    elsif ( $event =~ /^(condition): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $value   = "0" if ( $2 eq "clear" );
        $value   = "1" if ( $2 eq "sunny" );
        $value   = "2" if ( $2 eq "cloudy" );
        $value   = "3" if ( $2 eq "rain" );
    }
    elsif ( $event =~ /^(.*[Hh]umidity[Cc]ondition): +(\S+) *(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $value   = "0" if ( $2 eq "dry" );
        $value   = "1" if ( $2 eq "low" );
        $value   = "2" if ( $2 eq "optimal" );
        $value   = "3" if ( $2 eq "wet" );
    }

    # general event handling
    elsif ( $event =~ /^(.+): +(\S+) *[\[\{\(]? *([\w\°\%\^\/\\]*).*/ ) {
        my $unitDetails = rname2unitDetails( $1, "en", $2 );
        $reading = $1;
        $value   = ( $unitDetails->{"value"} ? $unitDetails->{"value"} : $2 );
        $unit    = ( $unitDetails->{"unit"} ? $unitDetails->{"unit"} : $3 );
    }

    if ( !Scalar::Util::looks_like_number($value) ) {
        ::Log3 $device, 5,
"UConv::DbLog_split $device: Ignoring event $event: value does not look like a number";
        return undef;
    }

    ::Log3 $device, 5,
"UConv::DbLog_split $device: Splitting event $event > reading=$reading value=$value unit=$unit";

    return ( $reading, $value, $unit );
}

sub roundX($;$) {
    my ( $v, $n ) = @_;
    $n = 1 if ( !$n );
    return sprintf( "%.${n}f", $v );
}

1;

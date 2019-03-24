###############################################################################
# $Id$
package main;
use strict;
use warnings;
use Data::Dumper;
use utf8;
use Encode qw(encode_utf8 decode_utf8);

use UConv;

sub Unit_Initialize() { }

# scale helper for metric numbers
my $scales_m = {
    autoscale => {
        '0'     => { format => '%i',   scale => 1000, },
        '0.001' => { format => '%i',   scale => 1000, },
        '0.1'   => { format => '%.1f', scale => 1, },
        '10'    => { format => '%i',   scale => 1, },
        '1.0e3' => { format => '%.1f', scale => 0.001, },
        '2.0e3' => { format => '%i',   scale => 0.001, },
        '1.0e6' => { format => '%.1f', scale => 0.001, },
        '2.0e6' => { format => '%i',   scale => 0.001, },
    },

    '1.0e-12' => {
        'scale_txt_m'      => 'p',
        'scale_txt_long_m' => {
            de => 'Piko',
            en => 'Pico',
        },
    },

    '1.0e-9' => {
        'scale_txt_m'      => 'n',
        'scale_txt_long_m' => {
            de => 'Nano',
            en => 'Nano',
        },
    },

    '1.0e-6' => {
        'scale_txt_m'      => 'μ',
        'scale_txt_long_m' => {
            de => 'Mikro',
            en => 'Micro',
        },
    },

    '1.0e-3' => {
        'scale_txt_m'      => 'm',
        'scale_txt_long_m' => {
            de => 'Milli',
            en => 'Mili',
        },
    },

    '1.0e-2' => {
        'scale_txt_m'      => 'c',
        'scale_txt_long_m' => {
            de => 'Zenti',
            en => 'Centi',
        },
    },

    '1.0e-1' => {
        'scale_txt_m'      => 'd',
        'scale_txt_long_m' => {
            de => 'Dezi',
            en => 'Deci',
        },
    },

    '1.0e0' => {
        'scale_txt_m'      => '',
        'scale_txt_long_m' => '',
    },

    '1.0e1' => {
        'scale_txt_m'      => 'da',
        'scale_txt_long_m' => {
            de => 'Deka',
            en => 'Deca',
        },
    },

    '1.0e2' => {
        'scale_txt_m'      => 'h',
        'scale_txt_long_m' => {
            de => 'Hekto',
            en => 'Hecto',
        },
    },

    '1.0e3' => {
        'scale_txt_m'      => 'k',
        'scale_txt_long_m' => {
            de => 'Kilo',
            en => 'Kilo',
        },
    },

    '1.0e6' => {
        'scale_txt_m'      => 'M',
        'scale_txt_long_m' => {
            de => 'Mega',
            en => 'Mega',
        },
    },

    '1.0e9' => {
        'scale_txt_m'      => 'G',
        'scale_txt_long_m' => {
            de => 'Giga',
            en => 'Giga',
        },
    },

    '1.0e12' => {
        'scale_txt_m'      => 'T',
        'scale_txt_long_m' => {
            de => 'Tera',
            en => 'Tera',
        },
    },

    '1.0e15' => {
        'scale_txt_m'      => 'P',
        'scale_txt_long_m' => {
            de => 'Peta',
            en => 'Peta',
        },
    },
};

# scale helper for metric square numbers
my $scales_sq = {
    'scale_txt_sq'      => chr(0x00B2),
    'scale_txt_long_sq' => {
        de => 'Quadrat',
        en => 'Square',
    },
};

# scale helper for metric cubic numbers
my $scales_cu = {
    'scale_txt_cu'      => chr(0x00B3),
    'scale_txt_long_cu' => {
        de => 'Kubik',
        en => 'Cubic',
    },
};

# scale helper for time related numbers
my $scales_t = {

    # second
    's' => {
        'scale_txt_t'      => 's',
        'scale_txt_long_t' => {
            de => 'Sekunde',
            en => 'second',
        },
        'scale_txt_long_pl_t' => {
            de => 'Sekunden',
            en => 'seconds',
        },
    },

    # minute
    'min' => {
        'scale_txt_t' => {
            de => 'Min',
            en => 'min',
        },
        'scale_txt_long_t' => {
            de => 'Minute',
            en => 'minute',
        },
        'scale_txt_long_pl_t' => {
            de => 'Minuten',
            en => 'minutes',
        },
    },

    # hour
    'h' => {
        'scale_txt_t'      => 'h',
        'scale_txt_long_t' => {
            de => 'Stunde',
            en => 'hour',
        },
        'scale_txt_long_pl_t' => {
            de => 'Stunden',
            en => 'hours',
        },
    },

    # day
    'd' => {
        'scale_txt_t'      => 'd',
        'scale_txt_long_t' => {
            de => 'Tag',
            en => 'day',
        },
        'scale_txt_long_pl_t' => {
            de => 'Tage',
            en => 'days',
        },
    },

    # week
    'w' => {
        'scale_txt_t'      => 'w',
        'scale_txt_long_t' => {
            de => 'Woche',
            en => 'week',
        },
        'scale_txt_long_pl_t' => {
            de => 'Wochen',
            en => 'weeks',
        },
    },

    # month
    'm' => {
        'scale_txt_t'      => 'm',
        'scale_txt_long_t' => {
            de => 'Monat',
            en => 'month',
        },
        'scale_txt_long_pl_t' => {
            de => 'Monate',
            en => 'month',
        },
    },

    # year
    'a' => {
        'scale_txt_t'      => 'a',
        'scale_txt_long_t' => {
            de => 'Jahr',
            en => 'year',
        },
        'scale_txt_long_pl_t' => {
            de => 'Jahre',
            en => 'years',
        },
    },
};

# scale helper for time related numbers
# Overall structure/grouping based on
# https://de.wikipedia.org/wiki/Liste_physikalischer_Gr%C3%B6%C3%9Fen
#
# Scientific range:             0 -  99
# FHEM Builtin range:         900 - 998
# FHEM User Defined range:       >= 999
#
# rtype_base => reference to base rtype in $rtypes used for
#               automatic unit conversion
my $rtype_base = {

    0 => {
        dimension        => 'L',
        formula_symbol   => 'l',
        rtype_base       => 'm',
        base_description => {
            de => 'Länge',
            en => 'length',
        },
        format       => '%.0f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    1 => {
        dimension        => 'M',
        formula_symbol   => 'm',
        rtype_base       => 'kg',
        base_description => {
            de => 'Masse',
            en => 'mass',
        },
        format       => '%.0f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    2 => {
        dimension        => 'T',
        formula_symbol   => 't',
        rtype_base       => 's',
        base_description => {
            de => 'Zeit',
            en => 'time',
        },
        format       => '%.0f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    3 => {
        dimension        => 'I',
        formula_symbol   => 'i',
        rtype_base       => 'a',
        base_description => {
            de => 'elektrische Stromstärke',
            en => 'electric current',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    4 => {
        dimension        => 'θ',
        formula_symbol   => 'T',
        rtype_base       => 'k',
        base_description => {
            de => 'absolute Temperatur',
            en => 'absolute temperature',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    5 => {
        dimension        => 'N',
        formula_symbol   => 'n',
        rtype_base       => 'mol',
        base_description => {
            de => 'Stoffmenge',
            en => 'amount of substance',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    6 => {
        dimension        => 'J',
        formula_symbol   => 'Iv',
        rtype_base       => 'cd',
        base_description => {
            de => 'Lichtstärke',
            en => 'luminous intensity',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    7 => {
        dimension        => 'M L^2 T^−2',
        formula_symbol   => 'E',
        rtype_base       => 'j',
        base_description => {
            de => 'Energie',
            en => 'energy',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    8 => {
        dimension        => 'T^−1',
        formula_symbol   => 'f',
        rtype_base       => 'hz',
        base_description => {
            de => 'Frequenz',
            en => 'frequency',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    9 => {
        dimension        => 'M L^2 T^−3',
        formula_symbol   => 'P',
        rtype_base       => 'w',
        base_description => {
            de => 'Leistung',
            en => 'power',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    10 => {
        dimension        => 'M L^−1 T^−2',
        formula_symbol   => 'p',
        rtype_base       => 'pa',
        base_description => {
            de => 'Druck',
            en => 'pressure',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    11 => {
        dimension        => 'M L^−1 T^−2',
        formula_symbol   => 'pabs',
        rtype_base       => 'pabs',
        base_description => {
            de => 'absoluter Druck',
            en => 'absolute pressure',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    12 => {
        dimension        => 'M L^−1 T^−2',
        formula_symbol   => 'pamb',
        rtype_base       => 'pamb',
        base_description => {
            de => 'Luftdruck',
            en => 'air pressure',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    13 => {
        dimension        => 'M L^2 T^−3 I^−1',
        formula_symbol   => 'U',
        rtype_base       => 'v',
        base_description => {
            de => 'elektrische Spannung',
            en => 'electric voltage',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    14 => {
        dimension        => '1',
        formula_symbol   => '',
        rtype_base       => 'rad',
        base_description => {
            de => 'ebener Winkel',
            en => 'plane angular',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    15 => {
        dimension        => 'L T^−1',
        formula_symbol   => 'v',
        rtype_base       => 'kmph',
        base_description => {
            de => 'Geschwindigkeit',
            en => 'speed',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    16 => {
        dimension        => 'L^−2 J',
        formula_symbol   => 'Ev',
        rtype_base       => 'lx',
        base_description => {
            de => 'Beleuchtungsstärke',
            en => 'illumination intensity',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    17 => {
        dimension        => 'J',
        formula_symbol   => 'F',
        rtype_base       => 'lm',
        base_description => {
            de => 'Lichtstrom',
            en => 'luminous flux',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    18 => {
        dimension        => 'L^3',
        formula_symbol   => 'V',
        rtype_base       => 'm3',
        base_description => {
            de => 'Volumen',
            en => 'volume',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    19 => {
        dimension        => '1',
        formula_symbol   => 'B',
        rtype_base       => 'b',
        base_description => {
            de => 'Logarithmische Größe',
            en => 'logarithmic level',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    20 => {
        dimension        => 'I T',
        formula_symbol   => 'C',
        rtype_base       => 'coul',
        base_description => {
            de => 'elektrische Ladung',
            en => 'electric charge',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    21 => {
        dimension        => '',
        formula_symbol   => 'F',
        rtype_base       => 'far',
        base_description => {
            de => 'elektrische Kapazität',
            en => 'electric capacity',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    22 => {
        dimension        => 'M L2 T−3 I−2',
        formula_symbol   => 'R',
        rtype_base       => 'ohm',
        base_description => {
            de => 'elektrischer Widerstand',
            en => 'electric resistance',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    23 => {
        dimension        => 'L^2',
        formula_symbol   => 'A',
        rtype_base       => 'm2',
        base_description => {
            de => 'Flächeninhalt',
            en => 'surface area',
        },
        format       => '%i',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => { minValue => 0 },
    },

    24 => {
        base_description => {
            de => 'Währung',
            en => 'currency',
        },
        format       => '%.2f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        scope => '^[0-9]*(?:\.[0-9]*)?$',
    },

    25 => {
        base_description => {
            de => 'Zahlen',
            en => 'numbering',
        },
        format       => '%.1f',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        tmpl => '%value%',
    },

    26 => {
        base_description => {
            de => 'Logische Operatoren',
            en => 'logical operators',
        },
        tmpl => '%value%',
    },

    900 => {
        base_description => 'FHEM Builtin Readings Type',
        tmpl             => '%value%',
    },

    999 => {
        base_description => 'FHEM User Defined Readings Type',
        tmpl             => '%value%',
    },
};

# FHEM built-in reading types (RType).
# Values will be combined into a new super-hash using
# cross-references to $rtype_base, $scales_m, $scales_sq, $scales_cu, $scales_t
#
# ref_base => reference to $rtype_base id to include it's keys here
# ref_sq   => include keys from $scales_sq here; normally combined with a scale_sq reference as well
# ref_cu   => include keys from $scales_cu here; normally combined with a scale_cu reference as well
# ref_t    => reference to $scales_t id to include it's keys here; ; normally combined with a scale_t reference as well
# ref      => self-reference to $rtype id to include it's keys here (RType alias helper)
my $rtypes = {

    # others
    url => {
        ref_base          => 900,
        rtype_description => 'General URL including protocol prefix',
        tmpl              => '<html><a href="%value%">%value%</a></html>',
    },

    url_http => {
        ref_base          => 900,
        rtype_description => 'HTTP/S URL w/ or w/o protocol prefix',
        tmpl              => '<html><a href="%value%">%value%</a></html>',
    },

    trend => {
        ref_base => 900,
        symbol   => [ chr(0x2B0C), chr(0x2B08), chr(0x2B0A) ],
        txt      => [ '=', '+', '-' ],
        txt_long => {
            de => [ 'gleichbleibend', 'steigend',  'fallend' ],
            en => [ 'steady',         'rising',    'falling' ],
            fr => [ 'stable',         'croissant', 'décroissant' ],
            nl => [ 'stabiel',        'stijgend',  'dalend' ],
            pl => [ 'stabilne',       'rośnie',   'spada' ],
        },
        scope => [
            '^(=|steady|stable|0)$', '^(\+|rising|up|1)$',
            '^(-|falling|down|2)$'
        ],
        tmpl              => '%symbol%',
        tmpl_long         => '%txt_long%',
        rtype_description => 'Trend',
    },

    oknok => {
        ref_base => 900,
        txt      => {
            de => [ 'Fehler', 'ok', 'Warnung' ],
            en => [ 'error',  'ok', 'warning' ],
        },
        scope => [
            '^(nok|error|dead|invalid|0)$', '^(ok|alive|valid|1)$',
            '^(warning|warn|low|2)$',       '^(.*)$'
        ],
        rtype_description => {
            de =>
'Fehlerstatus; siehe RType roknok, sofern 0<>1 vertauschte Bedeutung haben',
            en => 'error state',
        },
    },

    roknok => {
        ref_base => 900,
        txt      => {
            de => [ 'Fehler', 'ok', 'Warnung' ],
            en => [ 'error',  'ok', 'warning' ],
        },
        scope => [
            '^(nok|error|dead|invalid|1)$', '^(ok|alive|valid|0)$',
            '^(warning|warn|low|2)$',       '^(.*)$'
        ],
        rtype_description => {
            de =>
'verdrehter Fehlerstatus, bei dem 0=ok und 1=Fehler bedeutet; Gegenteil von RType oknok',
            en => 'reversed error state',
        },
    },

    onoff => {
        ref_base => 900,
        txt      => {
            de => [ 'aus', 'an', 'nicht verfügbar' ],
            en => [ 'off', 'on', 'absent' ],
        },
        scope =>
          [ '^(off|no|standby|0)$', '^(on|yes|1)$', '^(absent|offline|2)$', ],
        rtype_description => {
            de => 'Schaltstatus',
            en => 'Switch state',
        },
    },

    reachable => {
        ref_base => 900,
        txt      => {
            de => [ 'nicht verfügbar', 'verfügbar' ],
            en => [ 'unavailable',      'available' ],
        },
        scope => [
            '^(unavailable|absent|disappeared|false|no|0)$',
            '^(available|present|appeared|true|yes|1)$'
        ],
        rtype_description => {
            de => 'Verfügbarkeit/Erreichbarkeit',
            en => 'availability/reachability',
        },
    },

    weekday => {
        ref_base => 900,
        symbol   => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa',  'So' ],
            en => [ 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' ],
        },
        txt => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa',  'So' ],
            en => [ 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' ],
        },
        txt_long => {
            de => [
                'Sonntag',    'Montag',  'Dienstag', 'Mittwoch',
                'Donnerstag', 'Freitag', 'Samstag',  'Sonntag'
            ],
            en => [
                'Sunday',   'Monday', 'Tuesday',  'Wednesday',
                'Thursday', 'Friday', 'Saturday', 'Sunday'
            ],
        },
        scope => {
            de => [
                '^(So|Son|Sonntag|0|7)$',  '^(Mo|Mon|Montag|1)$',
                '^(Di|Die|Dienstag|2)$',   '^(Mi|Mit|Mittwoch|3)$',
                '^(Do|Don|Donnerstag|4)$', '^(Fr|Fre|Freitag|5)$',
                '^(Sa|Sam|Samstag|6)$',
            ],
            en => [
                '^(Sun|Su|Sunday|0|7)$', '^(Mon|Mo|Monday|1)$',
                '^(Tue|Tu|Tuesday|2)$',  '^(Wed|We|Wednesday|3)$',
                '^(Thu|Th|Thursday|4)$', '^(Fri|Fr|Friday|5)$',
                '^(Sat|Sa|Saturday|6)$'
            ],
        },
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de =>
'Wochentag nach englisch-amerikanischer Annahme des Wochenstarts am Sonntag',
            en =>
'Day of the week according to english assumption for the week to start on sunday',
        },
    },

    weekday_iso => {
        ref_base => 900,
        symbol   => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa',  'So' ],
            en => [ 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' ],
        },
        txt => {
            de => [ 'So',  'Mo',  'Di',  'Mi',  'Do',  'Fr',  'Sa',  'So' ],
            en => [ 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' ],
        },
        txt_long => {
            de => [
                'Sonntag',    'Montag',  'Dienstag', 'Mittwoch',
                'Donnerstag', 'Freitag', 'Samstag',  'Sonntag'
            ],
            en => [
                'Sunday',   'Monday', 'Tuesday',  'Wednesday',
                'Thursday', 'Friday', 'Saturday', 'Sunday'
            ],
        },
        scope => {
            de => [
                '^(So|Son|Sonntag|7)$',    '^(Mo|Mon|Montag|1)$',
                '^(Di|Die|Dienstag|2)$',   '^(Mi|Mit|Mittwoch|3)$',
                '^(Do|Don|Donnerstag|4)$', '^(Fr|Fre|Freitag|5)$',
                '^(Sa|Sam|Samstag|6)$'
            ],
            en => [
                '^(Sun|Su|Sunday|7)$',   '^(Mon|Mo|Monday|1)$',
                '^(Tue|Tu|Tuesday|2)$',  '^(Wed|We|Wednesday|3)$',
                '^(Thu|Th|Thursday|4)$', '^(Fri|Fr|Friday|5)$',
                '^(Sat|Sa|Saturday|6)$'
            ],
        },
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de => 'Wochentag nach ISO-Standard, Woche beginnend am Montag',
            en =>
'Day of the week according to ISO standard, week beginning on Mondays',
        },
    },

    weekday_night => {
        ref_base => 900,
        symbol   => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en => [
                'Sun N', 'Mon N', 'Tue N', 'Wed N', 'Thu N', 'Fri N ', 'Sat N'
            ],
        },
        txt => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en => [
                'Sun N', 'Mon N', 'Tue N', 'Wed N', 'Thu N', 'Fri N ', 'Sat N'
            ],
        },
        txt_long => {
            de => [
                'Sonntag Nacht',
                'Montag Nacht',
                'Dienstag Nacht',
                'Mittwoch Nacht',
                'Donnerstag Nacht',
                'Freitag Nacht',
                'Samstag Nacht'
            ],
            en => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
        },
        scope => {
            de => [
                '^(\s*(Nacht|Na)?\s*(So|Son|Sonntag|0)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Mo|Mon|Montag|1)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Di|Die|Dienstag|2)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Mi|Mit|Mittwoch|3)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Do|Don|Donnerstag|4)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Fr|Fre|Freitag|5)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Sa|Sam|Samstag|6)\s*(Nacht|Na)?\s*)$'
            ],
            en => [
                '^(\s*(Night|Na)?\s*(Sun|Su|Sunday|0)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Mon|Mo|Monday|1)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Tue|Tu|Tuesday|2)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Wed|We|Wednesday|3)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Thu|Th|Thursday|4)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Fri|Fr|Friday|5)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Sat|Sa|Saturday|6)\s*(Night|Na)?\s*)$'
            ],
        },
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de =>
'Nächtlicher Wochentag nach englisch-amerikanischem Standard des Wochenstarts am Sonntag',
            en =>
'Nightly day of the week according to english standard for the week to start on sunday',
        },
    },

    weekday_night_iso => {
        ref_base => 900,
        symbol   => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en => [
                'Sun N', 'Mon N', 'Tue N', 'Wed N', 'Thu N', 'Fri N ', 'Sat N'
            ],
        },
        txt => {
            de => [ 'So N', 'Mo N', 'Di N', 'Mi N', 'Do N', 'Fr N', 'Sa N' ],
            en => [
                'Sun N', 'Mon N', 'Tue N', 'Wed N', 'Thu N', 'Fri N ', 'Sat N'
            ],
        },
        txt_long => {
            de => [
                'Sonntag Nacht',
                'Montag Nacht',
                'Dienstag Nacht',
                'Mittwoch Nacht',
                'Donnerstag Nacht',
                'Freitag Nacht',
                'Samstag Nacht'
            ],
            en => [
                'Sunday Night',
                'Monday Night',
                'Tuesday Night',
                'Wednesday Night',
                'Thursday Night',
                'Friday Night',
                'Saturday Night'
            ],
        },
        scope => {
            de => [
                '^(\s*(Nacht|Na)?\s*(So|Son|Sonntag|6)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Mo|Mon|Montag|0)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Di|Die|Dienstag|1)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Mi|Mit|Mittwoch|2)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Do|Don|Donnerstag|3)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Fr|Fre|Freitag|4)\s*(Nacht|Na)?\s*)$',
                '^(\s*(Nacht|Na)?\s*(Sa|Sam|Samstag|5)\s*(Nacht|Na)?\s*)$'
            ],
            en => [
                '^(\s*(Night|Na)?\s*(Sun|Su|Sunday|6)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Mon|Mo|Monday|0)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Tue|Tu|Tuesday|1)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Wed|We|Wednesday|2)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Thu|Th|Thursday|3)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Fri|Fr|Friday|4)\s*(Night|Na)?\s*)$',
                '^(\s*(Night|Na)?\s*(Sat|Sa|Saturday|5)\s*(Night|Na)?\s*)$'
            ],
        },
        tmpl              => '%txt%',
        tmpl_long         => '%txt_long%',
        rtype_description => {
            de =>
'Nächtlicher Wochentag nach ISO-Standard, Woche beginnend am Montag',
            en =>
'Nightly day of the week according to ISO standard, week beginning on Mondays',
        },
    },

    direction => {
        ref_base          => 900,
        formula_symbol    => 'Dir',
        ref               => 'gon',
        scope             => { minValue => 0, maxValue => 360 },
        rtype_description => {
            de => 'Richtungsangabe',
            en => 'direction',
        },
    },

    compasspoint => {
        ref_base       => 900,
        formula_symbol => 'CP',
        ref            => 'gon',
        txt            => {
            de => [
                'N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO',
                'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
            ],
            en => [
                'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
            ],
            nl => [
                'N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO',
                'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW'
            ],
            fr => [
                'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'
            ],
            pl => [
                'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
            ],
        },
        txt_long => {
            de => [
                'Norden', 'Nord-Nordost',  'Nordost',  'Ost-Nordost',
                'Osten',  'Ost-Südost',   'Südost',  'Süd-Südost',
                'Süden', 'Süd-Südwest', 'Südwest', 'West-Südwest',
                'Westen', 'West-Nordwest', 'Nordwest', 'Nord-Nordwest'
            ],
            en => [
                'North',     'North-Northeast',
                'Northeast', 'East-Northeast',
                'East',      'East-Southeast',
                'Southeast', 'South-Southeast',
                'South',     'South-Southwest',
                'Southwest', 'West-Southwest',
                'West',      'West-Northwest',
                'Northwest', 'North-Northwest'
            ],
            nl => [
                'N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO',
                'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW'
            ],
            fr => [
                'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'
            ],
            pl => [
                'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
            ],
        },

        scope => {
            de => [
                {
                    ge        => 0.0,
                    lt        => 22.5,
                    eq        => 360,
                    regex     => '^(N|Norden|0)$',
                    value_num => 0.0,
                },
                {
                    ge        => 22.5,
                    lt        => 45.0,
                    regex     => '^(NNO|Nord-Nordost|1)$',
                    value_num => 22.5,
                },
                {
                    ge        => 45.0,
                    lt        => 67.5,
                    regex     => '^(NO|Nordost|2)$',
                    value_num => 45.0,
                },
                {
                    ge        => 67.5,
                    lt        => 90.0,
                    regex     => '^(ONO|Ost-Nordost|3)$',
                    value_num => 67.5,
                },
                {
                    ge        => 90.0,
                    lt        => 112.5,
                    regex     => '^(O|Osten|4)$',
                    value_num => 90.0,
                },
                {
                    ge        => 112.5,
                    lt        => 135.0,
                    regex     => '^(OSO|Ost-S(ü|u|ue)dost|5)$',
                    value_num => 112.5,
                },
                {
                    ge        => 135.0,
                    lt        => 157.5,
                    regex     => '^(SO|S(ü|u|ue)dost|6)$',
                    value_num => 135.0,
                },
                {
                    ge        => 157.5,
                    lt        => 180.0,
                    regex     => '^(SSO|S(ü|u|ue)d-S(ü|u|ue)dost|7)$',
                    value_num => 157.5,
                },
                {
                    ge        => 180.0,
                    lt        => 202.5,
                    regex     => '^(S|S(ü|u|ue)den|8)$',
                    value_num => 180.0,
                },
                {
                    ge        => 202.5,
                    lt        => 225.0,
                    regex     => '^(SSW|S(ü|u|ue)d-S(ü|u|ue)dwest|9)$',
                    value_num => 202.5,
                },
                {
                    ge        => 225.0,
                    lt        => 247.5,
                    regex     => '^(SW|S(ü|u|ue)dwest|10)$',
                    value_num => 225.0,
                },
                {
                    ge        => 247.5,
                    lt        => 270.0,
                    regex     => '^(WSW|West-S(ü|u|ue)dwest|11)$',
                    value_num => 247.5,
                },
                {
                    ge        => 270.0,
                    lt        => 292.5,
                    regex     => '^(W|Westen|12)$',
                    value_num => 270.0,
                },
                {
                    ge        => 292.5,
                    lt        => 315.0,
                    regex     => '^(WNW|West-Nordwest|13)$',
                    value_num => 292.5,
                },
                {
                    ge        => 315.0,
                    lt        => 337.5,
                    regex     => '^(NW|Nordwest|14)$',
                    value_num => 315.0,
                },
                {
                    ge        => 337.5,
                    lt        => 360,
                    regex     => '^(NNW|Nord-Nordwest|15)$',
                    value_num => 337.5,
                },
            ],
            en => [
                {
                    ge        => 0.0,
                    lt        => 22.5,
                    eq        => 360,
                    regex     => '^(N|North|0)$',
                    value_num => 0.0,
                },
                {
                    ge        => 22.5,
                    lt        => 45.0,
                    regex     => '^(NNE|North-Northeast|1)$',
                    value_num => 22.5,
                },
                {
                    ge        => 45.0,
                    lt        => 67.5,
                    regex     => '^(NE|Northeast|2)$',
                    value_num => 45.0,
                },
                {
                    ge        => 67.5,
                    lt        => 90.0,
                    regex     => '^(ENE|East-Northeast|3)$',
                    value_num => 67.5,
                },
                {
                    ge        => 90.0,
                    lt        => 112.5,
                    regex     => '^(E|East|4)$',
                    value_num => 90.0,
                },
                {
                    ge        => 112.5,
                    lt        => 135.0,
                    regex     => '^(ESE|East-Southeast|5)$',
                    value_num => 112.5,
                },
                {
                    ge        => 135.0,
                    lt        => 157.5,
                    regex     => '^(SE|Southeast|6)$',
                    value_num => 135.0,
                },
                {
                    ge        => 157.5,
                    lt        => 180.0,
                    regex     => '^(SSE|South-Southeast|7)$',
                    value_num => 157.5,
                },
                {
                    ge        => 180.0,
                    lt        => 202.5,
                    regex     => '^(S|South|8)$',
                    value_num => 180.0,
                },
                {
                    ge        => 202.5,
                    lt        => 225.0,
                    regex     => '^(SSW|South-Southwest|9)$',
                    value_num => 202.5,
                },
                {
                    ge        => 225.0,
                    lt        => 247.5,
                    regex     => '^(SW|Southwest|10)$',
                    value_num => 225.0,
                },
                {
                    ge        => 247.5,
                    lt        => 270.0,
                    regex     => '^(WSW|West-Southwest|11)$',
                    value_num => 247.5,
                },
                {
                    ge        => 270.0,
                    lt        => 292.5,
                    regex     => '^(W|West|12)$',
                    value_num => 270.0,
                },
                {
                    ge        => 292.5,
                    lt        => 315.0,
                    regex     => '^(WNW|West-Northwest|13)$',
                    value_num => 292.5,
                },
                {
                    ge        => 315.0,
                    lt        => 337.5,
                    regex     => '^(NW|Northwest|14)$',
                    value_num => 315.0,
                },
                {
                    ge        => 337.5,
                    lt        => 360,
                    regex     => '^(NNW|North-Northwest|15)$',
                    value_num => 337.5,
                },
            ],
        },
        rtype_description => {
            de => 'Himmelsrichtung',
            en => 'point of the compass',
        },
        tmpl_long => '%txt_long%',
    },

    closure => {
        ref_base => 900,
        txt      => {
            de => [ 'geschlossen', 'offen', 'gekippt' ],
            en => [ 'closed',      'open',  'tilted' ],
        },
        scope             => [ '^(closed|0)$', '^(open|1)$', '^(tilted|2)$' ],
        rtype_description => {
            de => 'Status für Fenster und Türen',
            en => 'state for windows and doors',
        },
    },

    condition_weather => {
        ref_base => 900,
        txt      => {
            de => [ 'klar',  'sonnig', 'bewölkt', 'Regen' ],
            en => [ 'clear', 'sunny',  'cloudy',   'rain' ],
        },
        scope => [
            '^((nt_)?clear|nt_sunny|0)$', '^(sunny|1)$',
            '^((nt_)?cloudy|2)$',         '^((nt_)?rain|3)$'
        ],
        rtype_description => {
            de => 'Wetterbedingung',
            en => 'weather condition',
        },
    },

    condition_hum => {
        ref_base => 900,
        txt      => {
            de => [ 'trocken', 'niedrig', 'optimal', 'hoch', 'feucht' ],
            en => [ 'dry',     'low',     'ideal',   'high', 'wet' ],
        },
        scope => [
            '^(dry|0)$',           '^(low|1)$',
            '^(ideal|optimal|2)$', '^(high|3)$',
            '^(wet|4)$'
        ],
        rtype_description => {
            de => 'Feuchtigkeitsbedingung',
            en => 'humidity condition',
        },
    },

    condition_uvi => {
        ref_base => 900,
        txt      => {
            de => [ 'niedrig', 'moderat',  'hoch', 'sehr hoch', 'extrem' ],
            en => [ 'low',     'moderate', 'high', 'very high', 'extreme' ],
        },
        scope => [
            '^(low|0)$',  '^(moderate|1)$',
            '^(high|2)$', '^(veryhigh|3)$',
            '^(extreme|4)$'
        ],
        rtype_description => {
            de => 'UV Bedingung',
            en => 'UV condition',
        },
    },

    # color
    rgbhex => {
        ref_base          => 900,
        rtype_description => {
            de => 'RGB Farbwert in Hex Notation',
            en => 'RGB color value in Hex notation',
        },
        scope => '^#?(([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2}))$',
    },

    rgb => {
        ref_base          => 900,
        rtype_description => {
            de => 'RGB Farbwert in Dezimal Notation',
            en => 'RGB color value in decimal notation',
        },
        scope =>
'^[\s\t\n ]*(?:rgb|RGB)?[\s\t\n ]*\(?[\s\t\n ]*((?:([0-9]{1,2}|1[0-9]{1,2}|2[0-4][0-9]|25[0-5])[\s\t\n ]*,?[\s\t\n ]*)(?:([0-9]{1,2}|1[0-9]{1,2}|2[0-4][0-9]|25[0-5])[\s\t\n ]*,?[\s\t\n ]*)(?:([0-9]{1,2}|1[0-9]{1,2}|2[0-4][0-9]|25[0-5])))[\s\t\n ]*\)?[\s\t\n ]*$',
    },

    # logical operators
    bool => {
        ref_base => 26,
        txt      => {
            de => [ 'falsch', 'wahr' ],
            en => [ 'false',  'true' ],
        },
        scope             => [ '^(false|n|no|0)$', '^(true|y|yes|1)$' ],
        rtype_description => {
            de => 'Boolesch wahr/falsch',
            en => 'Boolean true/false',
        },
    },

    yesno => {
        ref_base => 26,
        txt      => {
            de => [ 'nein', 'ja' ],
            en => [ 'no',   'yes' ],
        },
        scope             => [ '^(no|n|false|0)$', '^(yes|y|true|1)$' ],
        rtype_description => {
            de => 'Boolesch ja/nein',
            en => 'Boolean ja/nein',
        },
    },

    # decimal numbering
    short => {
        ref_base          => 25,
        format            => '%i',
        rtype_description => {
            de => 'Ganzzahl zwischen -32768 und 32767',
            en => 'Integer between -32768 and 32767',
        },
        scope => { minValue => -32768, maxValue => 32767 },
    },

    rshort => {
        ref_base          => 25,
        format            => '%.0f',
        rtype_description => {
            de => 'gerundete Ganzzahl zwischen -32768 und 32767',
            en => 'rounded integer between -32768 and 32767',
        },
        scope => { minValue => -32768, maxValue => 32767 },
    },

    long => {
        ref_base          => 25,
        format            => '%i',
        rtype_description => {
            de => 'Ganzzahl zwischen -2147483648 und 214748364',
            en => 'Integer between -2147483648 and 214748364',
        },
        scope => { minValue => -2147483648, maxValue => 214748364 },
    },

    rlong => {
        ref_base          => 25,
        format            => '%.0f',
        rtype_description => {
            de => 'gerundete Ganzzahl zwischen -2147483648 und 214748364',
            en => 'rounded integer between -2147483648 and 214748364',
        },
        scope => { minValue => -2147483648, maxValue => 214748364 },
    },

    integer => {
        ref_base          => 25,
        format            => '%i',
        rtype_description => {
            de => 'Ganzzahl',
            en => 'Integer',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    rinteger => {
        ref_base          => 25,
        format            => '%.0f',
        rtype_description => {
            de => 'gerundete Ganzzahl',
            en => 'rounded integer',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    float => {
        ref_base          => 25,
        format            => '%.2f',
        rtype_description => {
            de => 'Fließkommazahl',
            en => 'floating number',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    pct => {
        ref_base  => 25,
        format    => '%i',
        symbol    => chr(0x0025),
        suffix    => 'pct',
        tmpl      => '%value%' . chr(0x202F) . '%symbol%',
        tmpl_long => '%value% %txt%',
        txt       => {
            de => 'Prozent',
            en => 'percent',
        },
        scope => { minValue => 0, maxValue => 100 },
    },

    # binary numbering
    bin => {
        rtype_description => {
            de => 'Binärnummer',
            en => 'Binary number',
        },
        scope => '^[01]+$',
    },

    # octal numbering
    oct => {
        rtype_description => {
            de => 'Oktalnummer',
            en => 'Octal number',
        },
        scope => '^[0-7]+$',
    },

    # hexadecimal numbering
    hex => {
        rtype_description => {
            de => 'Hexadezimalnummer',
            en => 'Hexadecimal number',
        },
        scope => '^[0-9a-fA-F]+$',
    },

    # currency

    #https://en.wikipedia.org/wiki/Euro
    #https://en.wikipedia.org/wiki/Linguistic_issues_concerning_the_euro
    euro => {
        ref_base => 24,
        format   => '%.2f',
        symbol   => '€',
        suffix   => 'EUR',
        txt      => {
            de => 'Euro',
            en => 'euro',
        },
        tmpl => {
            de    => '%symbol%%value%',
            de_de => '%value%' . chr(0x202F) . '%symbol%',
            en    => '%symbol%%value%',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    pound_uk => {
        ref_base => 24,
        format   => '%.2f',
        symbol   => '£',
        suffix   => 'GBP',
        txt      => {
            de => 'Pfund',
            en => 'pound',
        },
        txt_long => {
            de => 'Britisches Pfund',
            en => 'British pound',
        },
        txt_long_pl => {
            de => 'Britische Pfund',
            en => 'British pound',
        },
        tmpl  => '%symbol%%value%',
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    dollar_us => {
        ref_base => 24,
        format   => '%.2f',
        symbol   => '$',
        suffix   => 'USD',
        txt      => {
            de => 'Dollar',
            en => 'dollar',
        },
        txt_long => {
            de => 'US Dollar',
            en => 'US dollar',
        },
        tmpl  => '%symbol%%value%',
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    cent => {
        ref_base => 24,
        format   => '%.0f',
        symbol   => {
            de => 'ct',
            en => '¢',
        },
        suffix => {
            de => 'ct',
            en => 'c',
        },
        txt => {
            de => 'Cent',
            en => 'cent',
        },
        tmpl => {
            de    => '%value%%symbol%',
            de_de => '%value%' . chr(0x202F) . '%symbol%',
            en    => '%value%%symbol%',
        },
        scope => '^([0-9]*(?:\.[0-9]*)?)$',
    },

    # plane angular
    gon => {
        ref_base => 14,
        symbol   => chr(0x00B0),
        suffix   => 'gon',
        txt      => {
            de => 'Grad',
            en => 'gradians',
        },
        tmpl         => '%value%%symbol%',
        decimal_mark => {
            de => 2,
            en => 1,
        },
        format => '%i',
    },

    rad => {
        ref_base => 14,
        suffix   => 'rad',
        txt      => {
            de => 'Radiant',
            en => 'radiant',
        },
        decimal_mark => {
            de => 2,
            en => 1,
        },
        format => '%i',
    },

    # temperature
    c => {
        ref_base => 4,
        symbol   => chr(0x00B0) . 'C',
        suffix   => 'C',
        txt      => {
            de => 'Grad Celsius',
            en => 'Degree Celsius',
        },
        txt_pl => {
            de => 'Grad Celsius',
            en => 'Degrees Celsius',
        },
        scope => { minValue => -273.15 },
    },

    f => {
        ref_base => 4,
        symbol   => chr(0x00B0) . 'F',
        suffix   => 'F',
        txt      => {
            de => 'Grad Fahrenheit',
            en => 'Degree Fahrenheit',
        },
        txt_pl => {
            de => 'Grad Fahrenheit',
            en => 'Degrees Fahrenheit',
        },
        scope => { minValue => -459.67 },
    },

    k => {
        ref_base => 4,
        suffix   => 'K',
        txt      => {
            de => 'Kelvin',
            en => 'Kelvin',
        },
    },

    # pressure
    bar => {
        ref_base => 10,
        scale_m  => '1.0e0',
        suffix   => 'bar',
        txt      => {
            de => 'Bar',
            en => 'Bar',
        },
    },

    mbar => {
        ref     => 'bar',
        scale_m => '1.0e-3',
    },

    pa => {
        ref_base => 10,
        scale_m  => '1.0e0',
        suffix   => 'Pa',
        txt      => {
            de => 'Pascal',
            en => 'Pascal',
        },
    },

    hpa => {
        ref     => 'pa',
        scale_m => '1.0e2',
    },

    pamb => {
        ref_base => 12,
        scale_m  => '1.0e0',
        suffix   => 'Pa',
        txt      => {
            de => 'Pascal',
            en => 'Pascal',
        },
    },

    hpamb => {
        ref     => 'pamb',
        scale_m => '1.0e2',
    },

    inhg => {
        ref_base => 12,
        suffix   => 'inHg',
        format   => '%.2f',
        txt      => {
            de => 'Zoll Quecksilbersäule',
            en => 'Inches of Mercury',
        },
    },

    mmhg => {
        ref_base => 12,
        suffix   => 'mmHg',
        txt      => {
            de => 'Millimeter Quecksilbersäule',
            en => 'Milimeter of Mercury',
        },
    },

    # length
    km => {
        ref     => 'm',
        scale_m => '1.0e3',
    },

    hm => {
        ref     => 'm',
        scale_m => '1.0e2',
    },

    dam => {
        ref     => 'm',
        scale_m => '1.0e1',
    },

    m => {
        ref_base => 0,
        scale_m  => '1.0e0',
        suffix   => 'm',
        txt      => {
            de => 'Meter',
            en => 'meter',
        },
    },

    dm => {
        ref     => 'm',
        scale_m => '1.0e-1',
    },

    cm => {
        ref     => 'm',
        scale_m => '1.0e-2',
    },

    mm => {
        ref     => 'm',
        scale_m => '1.0e-3',
    },

    um => {
        ref     => 'm',
        scale_m => '1.0e-6',
    },

    nm => {
        ref     => 'm',
        scale_m => '1.0e-9',
    },

    pm => {
        ref     => 'm',
        scale_m => '1.0e-12',
    },

    fm => {
        ref     => 'm',
        scale_m => '1.0e-15',
    },

    in => {
        ref_base => 0,
        symbol   => '″',
        suffix   => 'in',
        txt      => {
            de => 'Zoll',
            en => 'inch',
        },
        txt_pl => {
            de => 'Zoll',
            en => 'inches',
        },
        tmpl => '%value%%symbol%',
    },

    ft => {
        ref_base => 0,
        symbol   => '′',
        suffix   => 'ft',
        txt      => {
            de => 'Fuss',
            en => 'foot',
        },
        txt_pl => {
            de => 'Fuss',
            en => 'feet',
        },
        tmpl => '%value%%symbol%',
    },

    yd => {
        ref_base => 0,
        suffix   => 'yd',
        txt      => {
            de => 'Yard',
            en => 'yard',
        },
        txt_pl => {
            de => 'Yards',
            en => 'yards',
        },
    },

    mi => {
        ref_base => 0,
        suffix   => 'mi',
        txt      => {
            de => 'Meilen',
            en => 'miles',
        },
    },

    # time
    sec => {
        ref_base => 2,
        scale_t  => 's',
        suffix   => {
            de => 's',
            en => 's',
        },
        txt => {
            de => 'Sekunde',
            en => 'second',
        },
        txt_pl => {
            de => 'Sekunden',
            en => 'seconds',
        },
    },

    min => {
        ref_base => 2,
        scale_t  => 'min',
        suffix   => {
            de => 'Min',
            en => 'min',
        },
        txt => {
            de => 'Minute',
            en => 'minute',
        },
        txt_pl => {
            de => 'Minuten',
            en => 'minutes',
        },
    },

    hr => {
        ref_base => 2,
        scale_t  => 'h',
        suffix   => 'h',
        txt      => {
            de => 'Stunde',
            en => 'hour',
        },
        txt_pl => {
            de => 'Stunden',
            en => 'hours',
        },
    },

    d => {
        ref_base => 2,
        scale_t  => 'd',
        suffix   => {
            de => 'T',
            en => 'd',
        },
        txt => {
            de => 'Tag',
            en => 'day',
        },
        txt_pl => {
            de => 'Tage',
            en => 'days',
        },
    },

    w => {
        ref_base => 2,
        scale_t  => 'w',
        suffix   => {
            de => 'W',
            en => 'w',
        },
        txt => {
            de => 'Woche',
            en => 'week',
        },
        txt_pl => {
            de => 'Wochen',
            en => 'weeks',
        },
    },

    mon => {
        ref_base => 2,
        scale_t  => 'm',
        suffix   => {
            de => 'M',
            en => 'm',
        },
        txt => {
            de => 'Monat',
            en => 'month',
        },
        txt_pl => {
            de => 'Monate',
            en => 'Monat',
        },
    },

    y => {
        ref_base => 2,
        scale_t  => 'a',
        suffix   => {
            de => 'J',
            en => 'y',
        },
        txt => {
            de => 'Jahr',
            en => 'year',
        },
        txt_pl => {
            de => 'Jahre',
            en => 'years',
        },
    },

    epoch => {
        ref_base          => 2,
        scale_t           => 's',
        scope             => { minValue => 0 },
        rtype_description => {
            de => 'Unix Epoche in s seit 1970-01-01T00:00:00Z',
            en => 'Unix epoch in s since 1970-01-01T00:00:00Z',
        },
    },

    time => {
        ref_base          => 2,
        scope             => '^(([0-1]?[0-9]|[0-2]?[0-3]):([0-5]?[0-9]))$',
        rtype_description => {
            de => 'Uhrzeit hh:mm',
            en => 'time hh:mm',
        },
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . 'Uhr',
            en => '%value%',
        }
    },

    datetime => {
        ref_base => 2,
        scope =>
'^(([1-2][0-9]{3})-(0?[1-9]|1[0-2])-(0?[1-9]|[1-2][0-9]|30|31) (0?[1-9]|1[0-9]|2[0-3]):(0?[1-9]|[1-5][0-9]))$',
        rtype_description => {
            de => 'Datum+Uhrzeit YYYY-mm-dd hh:mm',
            en => 'date+time YYYY-mm-dd hh:mm',
        },
    },

    timesec => {
        ref_base => 900,
        scope    => '^(([0-1]?[0-9]|[0-2]?[0-3]):([0-5]?[0-9]):([0-5]?[0-9]))$',
        rtype_description => {
            de => 'Uhrzeit hh:mm:ss',
            en => 'time hh:mm:ss',
        },
    },

    datetimesec => {
        ref_base => 2,
        scope =>
'^(([1-2][0-9]{3})-(0?[1-9]|1[0-2])-(0?[1-9]|[1-2][0-9]|30|31) (0?[1-9]|1[0-9]|2[0-3]):(0?[1-9]|[1-5][0-9]):(0?[1-9]|[1-5][0-9]))$',
        rtype_description => {
            de => 'Datum+Uhrzeit YYYY-mm-dd hh:mm:ss',
            en => 'date+time YYYY-mm-dd hh:mm:ss',
        },
    },

    # speed
    bft => {
        ref_base => 15,
        suffix   => 'bft',
        txt      => {
            de => 'Windstärke',
            en => 'wind force',
        },
        tmpl_long => '%txt% %value%',
    },

    kn => {
        ref_base => 15,
        suffix   => 'kn',
        txt      => {
            de => 'Knoten',
            en => 'knots',
        },
    },

    fts => {
        ref_base  => 15,
        ref       => 'ft',
        ref_t     => 'sec',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_t%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_t%',
        },
    },

    mph => {
        ref_base  => 15,
        ref       => 'mi',
        ref_t     => 'hr',
        tmpl      => '%value%' . chr(0x00A0) . 'mph',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_t%',
        },
    },

    kmph => {
        ref_base  => 15,
        ref       => 'm',
        ref_t     => 'hr',
        scale_m   => '1.0e3',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_t%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_t%',
        },
    },

    mps => {
        ref_base  => 15,
        ref       => 'm',
        ref_t     => 'sec',
        scale_m   => '1.0e0',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_t%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_t%',
        },
    },

    # weight
    mol => {
        ref_base => 5,
        suffix   => 'mol',
    },

    pg => {
        ref     => 'g',
        scale_m => "1.0e-12",
    },

    ng => {
        ref     => 'g',
        scale_m => "1.0e-9",
    },

    ug => {
        ref     => 'g',
        scale_m => "1.0e-6",
    },

    mg => {
        ref     => 'g',
        scale_m => "1.0e-3",
    },

    cg => {
        ref     => 'g',
        scale_m => "1.0e-2",
    },

    dg => {
        ref     => 'g',
        scale_m => "1.0e-1",
    },

    g => {
        ref_base => 1,
        scale_m  => "1.0e0",
        suffix   => 'g',
        txt      => {
            de => 'Gramm',
            en => 'gram',
        },
    },

    kg => {
        ref     => 'g',
        scale_m => "1.0e3",
    },

    t => {
        ref     => 'g',
        scale_m => "1.0e6",
        suffix  => 't',
        txt     => {
            de => 'Tonne',
            en => 'ton',
        },
        txt_pl => {
            de => 'Tonnen',
            en => 'tons',
        },
    },

    lb => {
        ref_base => 1,
        suffix   => 'lb',
        txt      => {
            de => 'Pfund',
            en => 'pound',
        },
    },

    lbs => {
        ref_base => 1,
        suffix   => 'lbs',
        txt      => {
            de => 'Pfund',
            en => 'pound',
        },
    },

    # luminous intensity
    cd => {
        ref_base => 6,
        suffix   => 'cd',
        txt      => {
            de => 'Candela',
            en => 'Candela',
        },
    },

    # illumination intensity
    lx => {
        ref_base => 16,
        suffix   => 'lx',
        txt      => {
            de => 'Lux',
            en => 'Lux',
        },
    },

    # luminous flux
    lm => {
        ref_base => 17,
        suffix   => 'lm',
        txt      => {
            de => 'Lumen',
            en => 'Lumen',
        },
    },

    uvi => {
        ref_base => 900,
        suffix   => 'UVI',
        txt      => {
            de => 'UV-Index',
            en => 'UV-Index',
        },
        tmpl      => '%suffix%' . chr(0x00A0) . '%value%',
        tmpl_long => '%txt%' . chr(0x00A0) . '%value%',
        format    => '%i',
    },

    # surface area
    cm2 => {
        ref_base => 23,
        ref      => 'm',
        scale_m  => '1.0e-2',
        scale_sq => 1,
    },

    m2 => {
        ref_base => 23,
        ref      => 'm',
        scale_m  => '1.0e0',
        scale_sq => 1,
    },

    # volume
    cm3 => {
        ref_base => 18,
        ref      => 'm',
        scale_m  => '1.0e-2',
        scale_cu => 1,
    },

    m3 => {
        ref_base => 18,
        ref      => 'm',
        scale_m  => '1.0e0',
        scale_cu => 1,
    },

    ml => {
        ref     => 'l',
        scale_m => '1.0e-3',
    },

    l => {
        ref_base => 18,
        suffix   => 'l',
        txt      => {
            de => 'Liter',
            en => 'liter',
        },
        txt_pl => {
            de => 'Liter',
            en => 'liters',
        },
    },

    hl => {
        ref     => 'l',
        scale_m => '1.0e2',
    },

    # logarithmic scale
    b => {
        ref_base => 19,
        scale_m  => '1.0e0',
        suffix   => 'B',
        txt      => {
            de => 'Bel',
            en => 'Bel',
        },
    },

    db => {
        ref     => 'b',
        scale_m => '1.0e-1',
    },

    # electric current
    ua => {
        ref     => 'a',
        scale_m => '1.0e-6',
    },

    ma => {
        ref     => 'a',
        scale_m => '1.0e-3',
    },

    a => {
        ref_base => 3,
        scale_m  => '1.0e0',
        suffix   => 'A',
        txt      => {
            de => 'Ampere',
            en => 'Ampere',
        },
    },

    uv => {
        ref     => 'v',
        scale_m => '1.0e-6',
    },

    mv => {
        ref     => 'v',
        scale_m => '1.0e-3',
    },

    v => {
        ref_base => 13,
        scale_m  => '1.0e0',
        suffix   => 'V',
        txt      => {
            de => 'Volt',
            en => 'Volt',
        },
    },

    uj => {
        ref     => 'j',
        scale_m => '1.0e-6',
    },

    mj => {
        ref     => 'j',
        scale_m => '1.0e-3',
    },

    j => {
        ref_base => 7,
        scale_m  => '1.0e0',
        suffix   => 'J',
        txt      => {
            de => 'Joule',
            en => 'Joule',
        },
    },

    uw => {
        ref     => 'w',
        scale_m => '1.0e-6',
    },

    mw => {
        ref     => 'w',
        scale_m => '1.0e-3',
    },

    w => {
        ref_base => 9,
        scale_m  => '1.0e0',
        suffix   => 'W',
        txt      => {
            de => 'Watt',
            en => 'Watt',
        },
    },

    va => {
        ref => 'w',
    },

    kw => {
        ref     => 'w',
        scale_m => '1.0e3',
    },

    megaw => {
        ref     => 'w',
        scale_m => '1.0e6',
    },

    whr => {
        base_ref  => 7,
        ref       => 'w',
        scale_m   => '1.0e0',
        ref_t     => 'hr',
        scale_t   => 'h',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt%',
            en => '%value%' . chr(0x00A0) . '%txt%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl%',
            en => '%value%' . chr(0x00A0) . '%txt_pl%',
        },
        rtype_description => {
            de => 'Wattstunde',
            en => 'Watt hour',
        }
    },

    kwhr => {
        base_ref  => 7,
        ref       => 'w',
        scale_m   => '1.0e3',
        ref_t     => 'hr',
        scale_t   => 'h',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt%',
            en => '%value%' . chr(0x00A0) . '%txt%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl%',
            en => '%value%' . chr(0x00A0) . '%txt_pl%',
        },
        rtype_description => {
            de => 'Kilowattstunde',
            en => 'Kilowatt hour',
        }
    },

    mwhr => {
        base_ref  => 7,
        ref       => 'w',
        scale_m   => '1.0e6',
        ref_t     => 'hr',
        scale_t   => 'h',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%%suffix_t%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt%%txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt% %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt%%txt_pl%',
            en => '%value%' . chr(0x00A0) . '%txt% %txt_pl%',
        },
        rtype_description => {
            de => 'Megawattstunde',
            en => 'Megawatt hour',
        }
    },

    gwhr => {
        base_ref  => 7,
        ref       => 'w',
        scale_m   => '1.0e9',
        ref_t     => 'hr',
        scale_t   => 'h',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%%suffix_t%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt%%txt_t%',
            en => '%value%' . chr(0x00A0) . '%txt% %txt_t%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt%%txt_pl%',
            en => '%value%' . chr(0x00A0) . '%txt% %txt_pl%',
        },
        rtype_description => {
            de => 'Gigawattstunde',
            en => 'Gigawatt hour',
        }
    },

    uwpscm => {
        ref       => 'w',
        scale_m   => '1.0e-6',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_sq%',
        },
    },

    uwpsm => {
        ref       => 'w',
        scale_m   => '1.0e-6',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_sq%',
        },
    },

    mwpscm => {
        ref       => 'w',
        scale_m   => '1.0e-3',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_sq%',
        },
    },

    mwpsm => {
        ref       => 'w',
        scale_m   => '1.0e-3',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_sq%',
        },
    },

    wpscm => {
        ref       => 'w',
        scale_m   => '1.0e0',
        ref_sq    => 'm',
        scale_sq  => '1.0e-2',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_sq%',
        },
    },

    wpsm => {
        ref       => 'w',
        scale_m   => '1.0e0',
        ref_sq    => 'm',
        scale_sq  => '1.0e0',
        format    => '%.0f',
        tmpl      => '%value%' . chr(0x00A0) . '%suffix%/%suffix_sq%',
        tmpl_long => {
            de => '%value%' . chr(0x00A0) . '%txt% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt% per %txt_sq%',
        },
        tmpl_long_pl => {
            de => '%value%' . chr(0x00A0) . '%txt_pl% pro %txt_sq%',
            en => '%value%' . chr(0x00A0) . '%txt_pl% per %txt_sq%',
        },
    },

    coul => {
        ref_base => 20,
        suffix   => 'C',
        txt      => {
            de => 'Coulomb',
            en => 'Coulomb',
        },
    },

    far => {
        ref_base => 21,
        suffix   => 'F',
        txt      => {
            de => 'Farad',
            en => 'Farad',
        },
    },

    ohm => {
        ref_base => 22,
        symbol   => 'Ω',
        suffix   => 'Ohm',
        txt      => {
            de => 'Ohm',
            en => 'Ohm',
        },
    },

};

# helps the user to assign rtypes to existing readings of modules
# w/o built-in rtype support
#
# layer 1 = module name (exception: global is valid for all modules but
#                        with lower preference)
# layer 2 = reading name as used by that module
# layer 3 = template for this reading to be copied to device attribute readingsDesc.
#           aliasname makes a reference to another reading name to avoid duplicates
#           and take the opportunity to harmonise reading names here.
my $readingsDB = {
    global => {
        airpress => {
            aliasname => 'pressure_hpa',    # alias only
        },
        azimuth => {
            rtype => 'gon',
        },
        compasspoint => {
            rtype => 'compasspoint'
        },
        daylight => {
            rtype => 'yesno',
        },
        dewpoint => {
            aliasname => 'dewpoint_c',      # alias only
        },
        dewpoint_c => {
            rtype => 'c',
        },
        elevation => {
            rtype => 'gon',
        },
        feelslike => {
            aliasname => 'feelslike_c',     # alias only
        },
        feelslike_c => {
            rtype => 'c',
        },
        humidity => {
            rtype          => 'pct',
            formula_symbol => 'H',
        },
        humidityabs => {
            aliasname => 'humidityabs_c',    # alias only
        },
        humidityabs_c => {
            rtype          => 'c',
            formula_symbol => 'H',
        },
        humidityabs_f => {
            rtype          => 'f',
            formula_symbol => 'H',
        },
        humidityabs_k => {
            rtype          => 'k',
            formula_symbol => 'H',
        },
        horizon => {
            rtype => 'gon',
        },
        indoordewpoint => {
            aliasname => 'indoordewpoint_c',    # alias only
        },
        indoordewpoint_c => {
            rtype => 'c',
        },
        indoorhumidity => {
            rtype          => 'pct',
            formula_symbol => 'H',
        },
        indoorhumidityabs => {
            aliasname => 'indoorhumidityabs_c',    # alias only
        },
        indoorhumidityabs_c => {
            rtype => 'c',
        },
        indoortemperature => {
            aliasname => 'indoortemperature_c',    # alias only
        },
        indoortemperature_c => {
            rtype => 'c',
        },
        israining => {
            rtype => 'yesno',
        },
        level => {
            rtype => 'pct',
        },
        luminosity => {
            rtype => 'lx',
        },
        pct => {
            rtype => 'pct',
        },
        pressure => {
            aliasname => 'pressure_hpa',    # alias only
        },
        pressure_hpa => {
            rtype => 'hpamb',
        },
        pressure_in => {
            rtype => 'inhg',
        },
        pressure_mm => {
            rtype => 'mmhg',
        },
        pressureabs => {
            aliasname => 'pressureabs_hpamb',    # alias only
        },
        pressureabs_hpamb => {
            rtype => 'hpamb',
        },
        pressureabs_in => {
            rtype => 'inhg',
        },
        pressureabs_mm => {
            rtype => 'mmhg',
        },
        pressureabs_psi => {
            aliasname => 'pressureabs_psia',
        },
        pressureabs_psia => {
            rtype => 'psia',
        },
        rain => {
            aliasname => 'rain_mm',    # alias only
        },
        rain_mm => {
            rtype => 'mm',
        },
        rain_day => {
            aliasname => 'rain_day_mm',    # alias only
        },
        rain_day_mm => {
            rtype => 'mm',
        },
        rain_night => {
            aliasname => 'rain_night_mm',    # alias only
        },
        rain_night_mm => {
            rtype => 'mm',
        },
        rain_week => {
            aliasname => 'rain_week_mm',     # alias only
        },
        rain_week_mm => {
            rtype => 'mm',
        },
        rain_month => {
            aliasname => 'rain_month_mm',    # alias only
        },
        rain_month_mm => {
            rtype => 'mm',
        },
        rain_year => {
            aliasname => 'rain_year_mm',     # alias only
        },
        rain_year_mm => {
            rtype => 'mm',
        },
        snow => {
            aliasname => 'snow_cm',          # alias only
        },
        snow_cm => {
            rtype => 'cm',
        },
        snow_day => {
            aliasname => 'snow_day_cm',      # alias only
        },
        snow_day_cm => {
            rtype => 'cm',
        },
        snow_night => {
            aliasname => 'snow_night_cm',    # alias only
        },
        snow_night_cm => {
            rtype => 'cm',
        },
        sunshine => {
            aliasname => 'solarradiation',    # alias only
        },
        solarradiation => {
            rtype => 'wpsm',
        },
        temp => {
            aliasname => 'temperature_c',     # alias only
        },
        temp_c => {
            aliasname => 'temperature_c',     # alias only
        },
        temperature => {
            aliasname => 'temperature_c',     # alias only
        },
        temperature_c => {
            rtype => 'c',
        },
        uv => {
            aliasname => 'uvi',               # alias only
        },
        uvi => {
            rtype => 'uvi',
        },
        uvr => {
            rtype => 'uwpscm',
        },
        valvedesired => {
            aliasname => 'valve',             # alias only
        },
        valvepos => {
            aliasname => 'valve',             # alias only
        },
        valveposition => {
            aliasname => 'valve',             # alias only
        },
        valvepostc => {
            aliasname => 'valve',             # alias only
        },
        valve => {
            rtype => 'pct',
        },
        visibility => {
            aliasname => 'visibility_km',     # alias only
        },
        visibility_km => {
            rtype => 'km',
        },
        wind_chill => {
            aliasname => 'wind_chill_c',      # alias only
        },
        wind_chill_c => {
            rtype => 'c',
        },
        wind_compasspoint => {
            rtype => 'compasspoint'
        },
        windspeeddirection => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        winddirectiontext => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        wind_direction => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        wind_dir => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        winddir => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        winddirection => {
            aliasname => 'wind_compasspoint',    # alias only
        },
        wind_gust => {
            aliasname => 'wind_gust_kmh',        # alias only
        },
        wind_gust_kmh => {
            rtype => 'kmh',
        },
        wind_speed => {
            aliasname => 'wind_speed_kmh',       # alias only
        },
        wind_speed_kmh => {
            rtype => 'kmh',
        },
    }
};

# Find rtype through reading name
sub rname2rtype ($$@) {
    my ( $name, $reading, $lang ) = @_;
    my $details;
    my $r = $reading;
    my $l = ( $lang ? lc($lang) : "en" );
    my $rt;
    my $guess;
    my %return;

    # reading name exactly matches rtype
    return $reading if ( $rtypes->{$reading} && !wantarray );

    # remove some prefix or other values to
    # flatten reading name
    $r =~ s/^fc\d+_//i;
    $r =~ s/_(min|max|avg|sum|cum|min\d+m|max\d+m|avg\d+m|sum\d+m|cum\d+m)_/_/i;
    $r =~ s/^(min|max|avg|sum|cum|min\d+m|max\d+m|avg\d+m|sum\d+m|cum\d+m)_//i;
    $r =~ s/_(min|max|avg|sum|cum|min\d+m|max\d+m|avg\d+m|sum\d+m|cum\d+m)$//i;
    $r =~ s/.*[-_](temp)$/$1/i;

    # rename capital letter containing readings
    if ( !$readingsDB->{global}{ lc($r) } ) {
        $r =~ s/^([A-Z])(.*)/\l$1$2/;
        $r =~ s/([A-Z][a-z0-9]+)[\/\|\-_]?/_$1/g;
    }

    $r = lc($r);

    # known aliasname reading names
    if ( $readingsDB->{global}{$r}{aliasname} ) {
        my $dr = $readingsDB->{global}{$r}{aliasname};
        $return{aliasname} = $dr;
        $return{shortname} = $readingsDB->{global}{$dr}{shortname};
        $rt                = (
              $readingsDB->{global}{$dr}{rtype}
            ? $readingsDB->{global}{$dr}{rtype}
            : undef
        );
    }

    # known standard reading names
    elsif ( $readingsDB->{global}{$r}{shortname} ) {
        $return{aliasname} = $reading;
        $return{shortname} = $readingsDB->{global}{$r}{shortname};
        $rt                = (
              $readingsDB->{global}{$r}{rtype}
            ? $readingsDB->{global}{$r}{rtype}
            : undef
        );
    }

    # just guessing the rtype from reading name format
    elsif ( $r =~ /^.*_([A-Za-z0-9]+)$/i ) {
        $return{guess} = 1;
        $rt = $1;
    }

    if (wantarray) {
        return ( $reading, $return{aliasname}, $return{shortname},
            $return{guess} )
          if ( $rtypes->{$reading} );
        return ( $rt, $return{aliasname}, $return{shortname}, $return{guess} );
    }
    return $rt if ( $rt && $rtypes->{$rt} );
    return undef;
}

######################################
# package main
#
package main;
use utf8;

# Do the magic to generate value + unit combined text strings
# for specified language
sub replaceTemplate ($$$$;$) {
    my ( $device, $reading, $odesc, $lang, $value ) = @_;
    my $l = ( $lang ? lc($lang) : "en" );
    my $txt;
    my $txt_long;
    my $r = $defs{$device}{READINGS} if ($device);

    return
      if ( !$odesc || ref($odesc) ne "HASH" );

    $value = ${$odesc}{value}{$lang}
      if (!defined($value)
        && defined( $odesc->{value} )
        && defined( $odesc->{value}{$lang} ) );

    return $value
      if ( !defined($value) || $value eq "" || !defined( $odesc->{rtype} ) );

    # clone
    my $desc;
    foreach ( keys %{$odesc} ) {
        next
          if ( $_ eq "scope"
            || $_ eq "format"
            || $_ eq "factor"
            || $_ eq "scale" );
        $desc->{$_} = $odesc->{$_};
    }

    ##########
    # language support
    #

    # keep only defined language if set
    foreach ( keys %{$desc} ) {
        next
          if (!defined( $desc->{$_} )
            || ref( $desc->{$_} ) ne "HASH" );

        # find any direct format
        if ( defined( $desc->{$_}{$l} ) ) {
            my $v;
            $v = $desc->{$_}{$l};
            delete $desc->{$_};
            $desc->{$_} = $v if ( defined($v) );
            Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr $_: value replaced by language specific version ($l)"
            );
        }

        # try base language format instead
        # and extract xx from xx_yz
        elsif ( $l =~ /^([a-z]+)(_([a-z]+))?$/i
            && defined( $desc->{$_}{$1} ) )
        {
            my $v;
            $v = $desc->{$_}{$1};
            delete $desc->{$_};
            $desc->{$_} = $v if ( defined($v) );
            Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr $_: value replaced by base language specific version ($1)"
            );
        }
    }

    # if original value was a text string and we got value_num out of it,
    # now try to find the right standardized text value from the ARRAY
    my $value_num =
      ref( $desc->{value_num} ) eq "ARRAY"
      ? $desc->{value_num}[0]
      : ( defined( $desc->{value_num} ) ? $desc->{value_num} : undef );
    if ( defined($value_num) ) {
        foreach ( 'suffix', 'symbol', 'txt', 'txt_pl', 'txt_long',
            'txt_long_pl' )
        {
            if ( ref( $desc->{$_} ) eq "ARRAY"
                && $desc->{$_}[$value_num] )
            {
                my $v = $desc->{$_}[$value_num];
                delete $desc->{$_};
                $desc->{$_} = $v;
                Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr $_: value replaced based on ARRAY found using value from 'value_num'"
                );
            }
        }
    }

    ##########
    # template support
    #

    # add metric name to suffix and txt
    if (   $desc->{suffix}
        && $desc->{scale_txt_m} )
    {
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix value rewritten by adding value from 'scale_txt_m'"
        );
        $desc->{suffix} = $desc->{scale_txt_m} . $desc->{suffix};
    }
    if (   $desc->{txt}
        && $desc->{scale_txt_long_m} )
    {
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt value rewritten by adding value from 'scale_txt_long_m'"
        );
        $desc->{txt} = $desc->{scale_txt_long_m} . lc( $desc->{txt} );
    }

    # add time information to suffix and txt
    if (   $desc->{suffix}
        && $desc->{scale_txt_t} )
    {
        $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_t};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix value rewritten by adding value from 'scale_txt_t'"
        );
    }
    if (   $desc->{txt}
        && $desc->{scale_txt_long_pl_t} )
    {
        $desc->{txt_pl} = $desc->{txt} . lc( $desc->{scale_txt_long_pl_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_pl value rewritten by adding value from 'scale_txt_long_pl_t'"
        );
    }
    if (   $desc->{txt}
        && $desc->{scale_txt_long_t} )
    {
        $desc->{txt} = $desc->{txt} . lc( $desc->{scale_txt_long_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt value rewritten by adding value from 'scale_txt_long_t'"
        );
    }

    # add square information to suffix and txt
    # if no separate suffix_sq and txt_sq was found
    if (  !$desc->{suffix_sq}
        && $desc->{scale_txt_sq} )
    {
        $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_sq};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix value rewritten by adding value from 'scale_txt_sq'"
        );
    }
    if (  !$desc->{txt_sq}
        && $desc->{scale_txt_long_sq} )
    {
        $desc->{txt} = $desc->{scale_txt_long_sq} . lc( $desc->{txt} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt value rewritten by adding value from 'scale_txt_long_sq'"
        );
    }

    # add cubic information to suffix and txt
    # if no separate suffix_cu and txt_cu was found
    if (  !$desc->{suffix_cu}
        && $desc->{scale_txt_cu} )
    {
        $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_cu};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix value rewritten by adding value from 'scale_txt_cu'"
        );
    }
    if (  !$desc->{txt_cu}
        && $desc->{scale_txt_long_cu} )
    {
        $desc->{txt} = $desc->{scale_txt_long_cu} . lc( $desc->{txt} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt value rewritten by adding value from 'scale_txt_long_cu'"
        );
    }

    # add time information to suffix and txt
    # if no separate suffix_t and txt_t was found
    if (  !$desc->{suffix_t}
        && $desc->{scale_txt_t} )
    {
        $desc->{suffix} = $desc->{suffix} . $desc->{scale_txt_t};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix value rewritten by adding value from 'scale_txt_t'"
        );
    }
    if (  !$desc->{txt_t}
        && $desc->{scale_txt_long_pl_t} )
    {
        $desc->{txt_pl} = $desc->{txt} . lc( $desc->{scale_txt_long_pl_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_pl value rewritten by adding value from 'scale_txt_long_pl_t'"
        );
    }
    if (  !$desc->{txt_t}
        && $desc->{scale_txt_long_t} )
    {
        $desc->{txt} = $desc->{txt} . lc( $desc->{scale_txt_long_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt value rewritten by adding value from 'scale_txt_long_t'"
        );
    }

    # add metric name to suffix_sq
    if (   $desc->{suffix_sq}
        && $desc->{scale_txt_m_sq}
        && $desc->{suffix_sq} !~ /$desc->{scale_txt_m_sq}/ )
    {
        $desc->{suffix_sq} = $desc->{scale_txt_m_sq} . $desc->{suffix_sq};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix_sq value rewritten by adding value from 'scale_txt_m_sq'"
        );
    }
    if (   $desc->{txt_sq}
        && $desc->{scale_txt_long_m_sq} )
    {
        $desc->{txt_sq} = $desc->{scale_txt_long_m_sq} . lc( $desc->{txt_sq} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_sq value rewritten by adding value from 'scale_txt_long_m_sq'"
        );
    }

    # add square information to suffix_sq
    if (   $desc->{suffix_sq}
        && $desc->{scale_txt_sq} )
    {
        $desc->{suffix_sq} = $desc->{suffix_sq} . $desc->{scale_txt_sq};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix_sq value rewritten by adding value from 'scale_txt_sq'"
        );
    }
    if (   $desc->{txt_sq}
        && $desc->{scale_txt_long_sq} )
    {
        $desc->{txt_sq} = $desc->{scale_txt_long_sq} . lc( $desc->{txt_sq} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_sq value rewritten by adding value from 'scale_txt_long_sq'"
        );
    }

    # add time information to suffix_sq
    if (   $desc->{suffix_sq}
        && $desc->{scale_txt_t} )
    {
        $desc->{suffix_sq} = $desc->{suffix_sq} . $desc->{scale_txt_t};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix_sq value rewritten by adding value from 'scale_txt_t'"
        );
    }
    if (   $desc->{txt_sq}
        && $desc->{scale_txt_long_pl_t} )
    {
        $desc->{txt_pl_sq} =
          $desc->{txt_sq} . lc( $desc->{scale_txt_long_pl_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_pl_sq value rewritten by adding value from 'scale_txt_long_pl_t'"
        );
    }
    if (   $desc->{txt_sq}
        && $desc->{scale_txt_long_t} )
    {
        $desc->{txt_sq} = $desc->{txt_sq} . lc( $desc->{scale_txt_long_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_sq value rewritten by adding value from 'scale_txt_long_t'"
        );
    }

    # add metric name to suffix_cu
    if (   $desc->{suffix_cu}
        && $desc->{scale_txt_m_cu} )
    {
        $desc->{suffix_cu} = $desc->{scale_txt_m_cu} . $desc->{suffix_cu};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix_cu value rewritten by adding value from 'scale_txt_m_cu'"
        );
    }
    if (   $desc->{txt_cu}
        && $desc->{scale_txt_long_m_cu} )
    {
        $desc->{txt_cu} = $desc->{scale_txt_long_m_cu} . lc( $desc->{txt_cu} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_cu value rewritten by adding value from 'scale_txt_long_m_cu'"
        );
    }

    # add cubic information to suffix_cu
    if (   $desc->{suffix_cu}
        && $desc->{scale_txt_cu} )
    {
        $desc->{suffix_cu} = $desc->{suffix_cu} . $desc->{scale_txt_cu};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix_cu value rewritten by adding value from 'scale_txt_cu'"
        );
    }
    if (   $desc->{txt_cu}
        && $desc->{scale_txt_long_cu} )
    {
        $desc->{txt_cu} = $desc->{scale_txt_long_cu} . lc( $desc->{txt_cu} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_cu value rewritten by adding value from 'scale_txt_long_cu'"
        );
    }

    # add time information to suffix_cu
    if (   $desc->{suffix_cu}
        && $desc->{scale_txt_t} )
    {
        $desc->{suffix_cu} = $desc->{suffix_cu} . $desc->{scale_txt_t};
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr suffix_cu value rewritten by adding value from 'scale_txt_t'"
        );
    }
    if (   $desc->{txt_cu}
        && $desc->{scale_txt_long_pl_t} )
    {
        $desc->{txt_pl_cu} =
          $desc->{txt_cu} . lc( $desc->{scale_txt_long_pl_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_pl_cu value rewritten by adding value from 'scale_txt_long_pl_t'"
        );
    }
    if (   $desc->{txt_cu}
        && $desc->{scale_txt_long_t} )
    {
        $desc->{txt_cu} = $desc->{txt_cu} . lc( $desc->{scale_txt_long_t} );
        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: RAttr txt_cu value rewritten by adding value from 'scale_txt_long_t'"
        );
    }

    ###############################
    # generate short text string
    #

    # find text template
    $txt = '%value%' . chr(0x00A0) . '%suffix%' if ( !$desc->{symbol} );
    $txt = '%value%' . chr(0x202F) . '%symbol%' if ( $desc->{symbol} );
    $txt = '%value%' . chr(0x202F) . '%symbol%' if ( $desc->{symbol} );
    $txt = $desc->{tmpl}                        if ( $desc->{tmpl} );
    $txt = '%txt%'
      if ( defined( $desc->{txt} ) && !looks_like_number($value) );

    Unit_Log3( $device, $reading, $odesc, 9,
        "replaceTemplate $device $reading: detected txt template: $txt" );

    # Replace all %text% placeholders with text value found
    # in old style READINGS.
    # Normally only TIME & VAL would be available but some modules might have
    # extended this and we want people to be able to make use of it.
    if ( $r && $reading && $r->{$reading} ) {
        foreach my $k ( keys %{ $r->{$reading} } ) {
            next if ( ref( $r->{$reading}{$k} ) );

            $txt =~ s/%$k%/$r->{$reading}{$k}/g;
            Unit_Log3( $device, $reading, $odesc, 10,
                "replaceTemplate $device $reading: RAttr txt: replacing '%$k%'"
            );
        }
    }

    # Replace all %text% placeholders with text value found
    # in matching reading desc hash keys
    foreach my $k ( keys %{$desc} ) {
        my $vdm = $desc->{$k};
        next if ( ref($vdm) );

        $vdm = UConv::decimal_mark( $vdm, $desc->{decimal_mark} )
          if ( defined( $desc->{decimal_mark} ) );
        $txt =~ s/%$k%/$vdm/g;
        Unit_Log3( $device, $reading, $odesc, 10,
            "replaceTemplate $device $reading: RAttr txt: replacing '%$k%'" );
    }

    return ($txt) unless (wantarray);

    ###############################
    # generate long text string in plural
    #

    # find text template
    if (   looks_like_number($value)
        && ( $value eq "0" || $value > 1 || $value < -1 )
        && $desc->{txt_long_pl} )
    {
        $txt_long = '%value%' . chr(0x00A0) . '%txt_long_pl%';
        $txt_long = $desc->{tmpl_long_pl}
          if ( $desc->{tmpl_long_pl} );
    }
    elsif (looks_like_number($value)
        && ( $value eq "0" || $value > 1 || $value < -1 )
        && $desc->{txt_pl} )
    {
        $txt_long = '%value%' . chr(0x00A0) . '%txt_pl%';
        $txt_long = $desc->{tmpl_long_pl}
          if ( $desc->{tmpl_long_pl} );
    }

    ###############################
    # generate long text string in singular
    #

    # find text template
    elsif ( $desc->{txt_long} ) {
        $txt_long = '%value%' . chr(0x00A0) . '%txt_long%';
        $txt_long = $desc->{tmpl_long}
          if ( $desc->{tmpl_long} );
    }
    elsif ( $desc->{txt} ) {
        $txt_long = '%value%' . chr(0x00A0) . '%txt%';
        $txt_long = $desc->{tmpl_long}
          if ( $desc->{tmpl_long} );
    }

    # for either plural or singular long text string
    if ($txt_long) {

        Unit_Log3( $device, $reading, $odesc, 9,
"replaceTemplate $device $reading: detected txt_long template: $txt_long"
        );

       # Replace all %text% placeholders with text value found
       # in old style READINGS.
       # Normally only TIME & VAL would be available but some modules might have
       # extended this and we want people to be able to make use of it.
        if ( $r && $reading && $r->{$reading} ) {
            foreach my $k ( keys %{ $r->{$reading} } ) {
                next if ( ref( $r->{$reading}{$k} ) );

                $txt_long =~ s/%$k%/$r->{$reading}{$k}/g;
                Unit_Log3( $device, $reading, $odesc, 10,
"replaceTemplate $device $reading: RAttr txt_long: replacing '%$k%'"
                );
            }
        }

        # Replace all %text% placeholders with text value found
        # in matching reading desc hash keys
        foreach my $k ( keys %{$desc} ) {
            my $vdm = $desc->{$k};
            next if ( ref($vdm) );

            $vdm = UConv::decimal_mark( $vdm, $desc->{decimal_mark} )
              if ( defined( $desc->{decimal_mark} ) );
            $txt_long =~ s/%$k%/$vdm/g;
            Unit_Log3( $device, $reading, $odesc, 10,
"replaceTemplate $device $reading: RAttr txt_long: replacing '%$k%'"
            );
        }

    }

    my $unit =
      $desc->{symbol} ? $desc->{symbol}
      : (
        $desc->{suffix} ? $desc->{suffix}
        : ( $desc->{txt} ? $desc->{txt} : undef )
      );

    $txt      = Encode::encode_utf8($txt)      if ( defined($txt) );
    $txt_long = Encode::encode_utf8($txt_long) if ( defined($txt_long) );
    $unit     = Encode::encode_utf8($unit)     if ( defined($unit) );

    return ( $txt, $txt_long, $unit );
}

sub Unit_verifyValueNumber($$) {
    my ( $value, $scope ) = @_;
    my $log;
    my $value_num;
    my $verified = 0;

    foreach ( keys %{$scope} ) {
        next
          if ( $_ !~ /^(regex|eq|minValue|maxValue|lt|gt|le|ge)$/ );

        $verified = 1;

        if ( !looks_like_number($value) ) {
            if ( $_ eq 'regex' ) {
                $log .= " '$value' does not match regex $scope->{$_}."
                  if ( $value !~ /$scope->{$_}/ );
                $value_num = $scope->{value_num}
                  if ( defined( $scope->{value_num} ) );
            }
            elsif ( $_ eq 'eq' ) {
                if ( $value ne $scope->{eq} ) {
                    $log .= " $value is not equal to $scope->{eq}.";
                    $value = $scope->{eq}
                      if ( !$scope->{keep} || $scope->{strict} );
                }
                $value_num = $scope->{value_num}
                  if ( defined( $scope->{value_num} ) );
            }
            elsif ( !$scope->{regex} && !defined( $scope->{eq} ) ) {
                $log .= " '$value' is not a number."
                  if ( !$scope->{empty} && !$scope->{empty_replace} );
                $value = "0"
                  if ( !$scope->{keep} && !$scope->{empty_replace} );
                $value = $scope->{empty_replace}
                  if ( defined( $scope->{empty_replace} ) );
                last;
            }
        }
        elsif ( $_ eq 'minValue' ) {
            if ( $value < $scope->{$_} ) {
                $log .= " $value is lesser than $scope->{$_}.";
                $value = $scope->{$_}
                  if ( !$scope->{keep} || $scope->{strict} );
            }
        }
        elsif ( $_ eq 'maxValue' ) {
            if ( $value > $scope->{$_} ) {
                $log .= " $value is greater than $scope->{$_}.";
                $value = $scope->{$_}
                  if ( !$scope->{keep} || $scope->{strict} );
            }
        }
        elsif ( $_ eq 'lt' ) {
            if ( $value >= $scope->{$_} ) {
                $log .= " $value is not $_ $scope->{$_}.";
                $value = $scope->{$_}
                  if ( !$scope->{keep} || $scope->{strict} );
            }
        }
        elsif ( $_ eq 'le' ) {
            if ( $value > $scope->{$_} ) {
                $log .= " $value is not $_ $scope->{$_}.";
                $value = $scope->{$_}
                  if ( !$scope->{keep} || $scope->{strict} );
            }
        }
        elsif ( $_ eq 'gt' ) {
            if ( $value <= $scope->{$_} ) {
                $log .= " $value is not $_ $scope->{$_}.";
                $value = $scope->{$_}
                  if ( !$scope->{keep} || $scope->{strict} );
            }
        }
        elsif ( $_ eq 'ge' ) {
            if ( $value < $scope->{$_} ) {
                $log .= " $value is not $_ $scope->{$_}.";
                $value = $scope->{$_}
                  if ( !$scope->{keep} || $scope->{strict} );
            }
        }
        elsif ( $_ eq 'eq' ) {
            if ( $value ne $scope->{$_} ) {
                $log .= " $value is not equal to $scope->{$_}.";
                $value = $scope->{$_}
                  if ( !$scope->{keep} || $scope->{strict} );
            }
            else {
                $log = undef;
                last;
            }
        }
    }

    return ( $verified, $value, $value_num, $log );
}

# format a number according to desc and optional format.
sub formatValue($$$;$$$$) {
    my ( $device, $reading, $value, $desc, $format, $scope, $lang ) = @_;
    $lang = "en" if ( !$lang );
    my $lang_base = $lang;
    $lang_base =~ s/^(\w+)(_.*)$/$1/;
    my $value_num;

    if (  !defined($value)
        || ref($value)
        || AttrVal( $device, "showUnits", 1 ) eq "0" )
    {
        Unit_Log3( $device, $reading, $desc, 10,
            "formatValue $device $reading: explicit return of original value" );
        return $value;
    }

    $desc = readingsDesc( $device, $reading )
      if ( !$desc || !ref($desc) );
    if ( !$format && ( !$desc || ref($desc) ne 'HASH' )
        || keys %{$desc} < 1 )
    {
        Unit_Log3( $device, $reading, $desc, 10,
                "formatValue $device $reading: "
              . "no readings description found, returning original value" );
        return $value;
    }

    # source value language
    my $slang = "en";
    $slang = $desc->{lang} if ( $desc && $desc->{lang} );
    my $slang_base = $slang;
    $slang_base =~ s/^(\w+)(_.*)$/$1/;

    # factor
    if ( $desc && $desc->{factor} ) {
        if ( ref( $desc->{factor} ) || !looks_like_number( $desc->{factor} ) ) {
            Unit_Log3( $device, $reading, $desc, 5,
                    "formatValue $device $reading: ERROR: "
                  . "RAttr factor is not numeric" );
        }
        elsif ( looks_like_number($value) ) {
            Unit_Log3( $device, $reading, $desc, 9,
                    "formatValue $device $reading: "
                  . "multiply original numeric value with factor "
                  . $desc->{factor} );
            $value *= $desc->{factor};
        }
        else {
            Unit_Log3( $device, $reading, $desc, 8,
                    "formatValue $device $reading: factor "
                  . "multiplication failed - '$value' is not a number" );
        }
    }

    $format = $desc->{format}
      if ( !$format && $desc && $desc->{format} );
    $scope = $desc->{scope} if ( !$scope && $desc && $desc->{scope} );

    # language handling for scope
    if ( ref($scope) eq "HASH" && defined( $scope->{$slang} ) ) {
        my $v;
        $v     = $scope->{$slang};
        $scope = undef;
        $scope = $v;
        Unit_Log3( $device, $reading, $desc, 8,
                "formatValue $device $reading: RAttr scope: "
              . "value replaced by language specific version ($slang)" );
    }
    elsif ( ref($scope) eq "HASH" && defined( $scope->{$slang_base} ) ) {
        my $v;
        $v     = $scope->{$slang_base};
        $scope = undef;
        $scope = $v;
        Unit_Log3( $device, $reading, $desc, 8,
                "formatValue $device $reading: RAttr scope: "
              . "value replaced by language specific version ($slang_base)" );
    }

    Unit_Log3( $device, $reading, $desc, 9,
        "formatValue $device $reading: scope dump:\n" . Dumper($scope) )
      if ($scope);

    ################################
    # scope:
    # Check for value to be in correct scope
    #

    # Use user defined subroutine
    if ( ref($scope) eq 'CODE' && &$scope ) {
        Unit_Log3( $device, $reading, $desc, 9,
                "formatValue $device $reading: scope: "
              . "running external subroutine $scope()" );
        ( $value, $value_num ) = $scope->($value);
    }

    # scope was defined as HASH
    elsif ( ref($scope) eq 'HASH' ) {

        Unit_Log3( $device, $reading, $desc, 9,
                "formatValue $device $reading: scope: "
              . "verifying '$value' based on HASH structure" );

        my ( $log, $verified );
        ( $verified, $value, $value_num, $log ) =
          Unit_verifyValueNumber( $value, $scope );

        Unit_Log3( $device, $reading, $desc, 4,
            "formatValue $device $reading: scope: WARNING -$log" )
          if ($log);
    }

    # scope was defined as ARRAY so let's assume value
    # to be the index for that array to convert
    # this index to a text string.
    # 'value_num' will be defined here to help harmonising text values over
    # different reading names representing similar/comparable content in
    # some way.
    elsif ( ref($scope) eq 'ARRAY' ) {

        Unit_Log3( $device, $reading, $desc, 9,
                "formatValue $device $reading: scope: "
              . "verifying value '$value' based on ARRAY structure" );

        # value found as index within array.
        # assuming this scope was defined as string in regex format
        if (   looks_like_number($value)
            && defined( $scope->[$value] )
            && !ref( $scope->[$value] )
            && $value =~ /$scope->[$value]/gmi )
        {
            $value_num = $value;

            # some language handling
            # to replace original value with language specific
            # and FHEM harmonised value
            #

            # If specified language was found
            if (   ref( $desc->{txt} ) eq "HASH"
                && ref( $desc->{txt}{$lang} ) eq "ARRAY"
                && defined( $desc->{txt}{$lang}[$value] ) )
            {
                Unit_Log3( $device, $reading, $desc, 8,
                        "formatValue $device $reading: scope: rattr value: "
                      . "replaced by language specific value from 'txt' ($lang)"
                );
                $value = $desc->{txt}{$lang}[$value];
            }

            # also try base language
            elsif (ref( $desc->{txt} ) eq "HASH"
                && ref( $desc->{txt}{$lang_base} ) eq "ARRAY"
                && defined( $desc->{txt}{$lang_base}[$value] ) )
            {
                Unit_Log3( $device, $reading, $desc, 8,
                        "formatValue $device $reading: scope: rattr value: "
                      . "replaced by language specific value from 'txt' ($lang_base)"
                );
                $value = $desc->{txt}{$lang_base}[$value];
            }

            # fallback to english
            elsif (ref( $desc->{txt} ) eq "HASH"
                && ref( $desc->{txt}{en} ) eq "ARRAY"
                && defined( $desc->{txt}{en}[$value] ) )
            {
                Unit_Log3( $device, $reading, $desc, 8,
                        "formatValue $device $reading: scope: rattr value: "
                      . "replaced by language specific value from 'txt' (en / default language)"
                );
                $value = $desc->{txt}{en}[$value];
            }

            # if there is no language defined at all
            elsif ( ref( $desc->{txt} ) eq "ARRAY"
                && defined( $desc->{txt}[$value] ) )
            {
                Unit_Log3( $device, $reading, $desc, 8,
                        "formatValue $device $reading: scope: rattr value: "
                      . "replaced by value from 'txt'" );
                $value = $desc->{txt}[$value];
            }

            # if there is no language defined at all
            elsif ( !ref( $desc->{txt} )
                && defined( $desc->{txt} ) )
            {
                Unit_Log3( $device, $reading, $desc, 8,
                        "formatValue $device $reading: scope: rattr value: "
                      . "replaced by plane value from 'txt'" );
                $value = $desc->{txt};
            }

            # if there is no txt definition at all
            # arrays are unbalanced
            else {
                Unit_Log3( $device, $reading, $desc, 7,
                        "formatValue $device $reading: scope: ERROR - "
                      . "unbalanced number of items in arrays" );
            }
        }

        else {
            my $i = 0;
            foreach ( @{$scope} ) {

                #TODO
                if ( !ref($_) && $value =~ /$_/gmi ) {
                    $value_num = $i;

                    # some language handling
                    # to replace original value with language specific
                    # and FHEM harmonised value
                    #

                    # If specified language was found
                    if (   ref( $desc->{txt} ) eq "HASH"
                        && ref( $desc->{txt}{$lang} ) eq "ARRAY"
                        && defined( $desc->{txt}{$lang}[$i] ) )
                    {
                        Unit_Log3( $device, $reading, $desc, 8,
                            "formatValue $device $reading: scope: rattr value: "
                              . "replaced by language specific value from 'txt' ($lang)"
                        );
                        $value = $desc->{txt}{$lang}[$i];
                    }

                    # also try base language
                    elsif (ref( $desc->{txt} ) eq "HASH"
                        && ref( $desc->{txt}{$lang_base} ) eq "ARRAY"
                        && defined( $desc->{txt}{$lang_base}[$i] ) )
                    {
                        Unit_Log3( $device, $reading, $desc, 8,
                            "formatValue $device $reading: scope: rattr value: "
                              . "replaced by language specific value from 'txt' ($lang_base)"
                        );
                        $value = $desc->{txt}{$lang_base}[$i];
                    }

                    # fallback to english
                    elsif (ref( $desc->{txt} ) eq "HASH"
                        && ref( $desc->{txt}{en} ) eq "ARRAY"
                        && defined( $desc->{txt}{en}[$i] ) )
                    {
                        Unit_Log3( $device, $reading, $desc, 8,
                            "formatValue $device $reading: scope: rattr value: "
                              . "replaced by language specific value from 'txt' (en / default language)"
                        );
                        $value = $desc->{txt}{en}[$i];
                    }

                    # if there is no language defined at all
                    elsif ( ref( $desc->{txt} ) eq "ARRAY"
                        && defined( $desc->{txt}[$i] ) )
                    {
                        Unit_Log3( $device, $reading, $desc, 8,
                            "formatValue $device $reading: scope: rattr value: "
                              . "replaced by value from 'txt'" );
                        $value = $desc->{txt}[$i];
                    }

                    # if there is no language defined at all
                    elsif ( !ref( $desc->{txt} )
                        && defined( $desc->{txt} ) )
                    {
                        Unit_Log3( $device, $reading, $desc, 8,
                            "formatValue $device $reading: scope: rattr value: "
                              . "replaced by plane value from 'txt'" );
                        $value = $desc->{txt};
                    }

                    # if there is no txt definition at all
                    # arrays are unbalanced
                    else {
                        $value = $1 if ( defined($1) );
                        if ( !defined($1) ) {
                            Unit_Log3( $device, $reading, $desc, 7,
                                "formatValue device $reading: scope: ERROR - "
                                  . "missing txt value or regex output (i=$i)"
                            );
                        }
                    }

                    last;
                }

                #TODO
                elsif ( ref($_) eq "HASH" ) {
                    if ( !looks_like_number($value) && $_->{regex} ) {
                        Unit_Log3( $device, $reading, $desc, 9,
                                "formatValue $device $reading: scope: "
                              . "searching numeric value for string '$value' (i=$i)"
                        );

                        if ( $value =~ /$_->{regex}/ ) {
                            if ( defined( $_->{value_num} ) ) {
                                Unit_Log3( $device, $reading, $desc, 9,
                                        "formatValue $device $reading: scope: "
                                      . "static numeric value found in HASH" );

                                $value_num->[0] = $i;
                                $value_num->[1] = $_->{value_num};
                            }
                            else {
                                Unit_Log3( $device, $reading, $desc, 9,
                                        "formatValue $device $reading: scope: "
                                      . "assuming indirect numeric value from ARRAY index number"
                                );

                                $value_num = $i;
                            }

                            last;
                        }
                    }

         #TODO: wenn nummer out of scope, dann muss ein maximalwert gesetzt sein
                    else {
                        Unit_Log3( $device, $reading, $desc, 9,
                                "formatValue $device $reading: scope: "
                              . "verifying numeric value '$value' (i=$i)" );

                        my ( $verified, $tval, $tval_num, $log ) =
                          Unit_verifyValueNumber( $value, $_ );

                        if ($log) {
                            Unit_Log3( $device, $reading, $desc, 4,
"formatValue $device $reading: scope: WARNING -$log"
                            );
                        }
                        elsif ( $verified && !$log ) {

                            if ( defined($tval_num) ) {
                                Unit_Log3( $device, $reading, $desc, 9,
                                        "formatValue $device $reading: scope: "
                                      . "static numeric value found in HASH" );

                                $value_num->[0] = $i;
                                $value_num->[1] = $tval_num;
                            }
                            else {
                                Unit_Log3( $device, $reading, $desc, 9,
                                        "formatValue $device $reading: scope: "
                                      . "assuming indirect numeric value from ARRAY index number"
                                );

                                $value_num = $i;
                            }

                            $value = $tval;
                            last;
                        }
                    }
                }

                $i++;
            }
        }
    }

    # scope was defined as string, let's assume it's in regex format
    elsif ( defined($scope) && $scope ne "" && $value =~ /$scope/gmi ) {

        # if regex matches and returns a $1, let's assume this is
        # by intention to replace something
        if ( defined($1) ) {
            Unit_Log3( $device, $reading, $desc, 9,
                    "formatValue $device $reading: scope: "
                  . "'$value' replaced by regex $scope with result from variable \$1"
            );
            $value = $1;
        }
    }

    # scope definition present but value seems to be out of regex scope
    elsif ( defined($scope) && $scope ne "" ) {
        Unit_Log3( $device, $reading, $desc, 8,
                "formatValue $device $reading: scope: WARNING - "
              . "'$value' does not match regex $scope" );
    }

    # format
    #
    if ( $format && !looks_like_number($value) ) {
        Unit_Log3( $device, $reading, $desc, 8,
"formatValue $device $reading: format: ERROR - $value is not a number"
          )
          if ( ref($scope) eq 'HASH'
            && !$scope->{empty}
            && !$scope->{empty_replace} );
    }

    elsif ( ref($format) eq 'CODE' && &$format ) {
        $value = $format->($value);
    }

    elsif ( ref($format) eq 'HASH' ) {
        my $v = $value;
        foreach my $l ( sort { $b <=> $a } keys( %{$format} ) ) {
            next
              if ( ref( $format->{$l} ) ne 'HASH'
                || !$format->{$l}{rescale} );
            if ( $v >= $l ) {
                my $rescale = $format->{$l}{rescale};

                $value *= $rescale if ($rescale);
                $value = sprintf( $format->{$l}{format}, $value )
                  if ( $format->{$l}{format} );
                last;
            }
        }
    }

    elsif ( ref($format) eq 'ARRAY' ) {
        Unit_Log3( $device, $reading, $desc, 8,
                "formatValue($device:$reading:$desc->{rtype})"
              . " format not implemented: ARRAY" );
    }

    elsif ($format) {
        my $rescale = $desc->{rescale};
        $value *= $rescale if ($rescale);
        $value = sprintf( $format, $value );
    }

    $desc->{value}{$lang} = $value;
    $desc->{value_num} = $value_num if ( defined($value_num) );

    my ( $txt, $txt_long, $unit ) =
      replaceTemplate( $device, $reading, $desc, $lang, $value );

    $desc->{value_txt}{$lang}      = $txt;
    $desc->{value_txt_long}{$lang} = $txt_long
      if ( defined($txt_long) );
    delete $desc->{value_txt_long}{$lang}
      if (!defined($txt_long)
        && defined( $desc->{value_txt_long}{$lang} ) );

    return ( $txt, $txt_long, $value, $value_num, $unit ) if (wantarray);
    return $value
      if ( ( defined( $desc->{showUnits} ) && $desc->{showUnits} eq "2" )
        || AttrVal( $device, "showUnits", 1 ) eq "2" );
    return $txt_long
      if ( $desc->{showLong} && !$desc->{showShort} );
    return $txt;
}

# find desc for device:reading
sub readingsDesc($;$) {
    my ( $device, $reading ) = @_;
    $device = "" unless ( defined($device) );
    my $desc = getCombinedKeyValAttr( $device, "readingsDesc", $reading );

    my $rtype;
    if ( $desc->{rtype} ) {
        $rtype = $desc->{rtype};
    }
    else {
        $rtype = rname2rtype( $device, $reading );
        $desc->{rtype} = $rtype;
    }

    if ( $rtype && defined( $rtypes->{$rtype} ) ) {

        # copy information from other hashes until 3rd level
        foreach my $k ( keys %{ $rtypes->{$rtype} } ) {
            if ( ref( $rtypes->{$rtype}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $rtypes->{$rtype}{$k} } ) {

                    if ( ref( $rtypes->{$rtype}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $rtypes->{$rtype}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $rtypes->{$rtype}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $rtypes->{$rtype}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$k} if ( $desc->{$k} );
                $desc->{$k} = $rtypes->{$rtype}{$k};
            }
        }

        foreach ( 'ref', 'ref_t', 'ref_sq', 'ref_cu' ) {
            my $suffix = $_;
            $suffix =~ s/^[a-z]+//;
            if ( defined( $desc->{$_} ) ) {
                my $ref = $desc->{$_};
                if ( !defined( $rtypes->{$ref} ) ) {
                    Log 1, "readingsDesc($rtype) broken reference $_";
                    next;
                }
                foreach my $k ( keys %{ $rtypes->{$ref} } ) {
                    next
                      if ( $k =~ /^scale/ )
                      ;    # exclude scales from referenced rtype
                    if ( !defined( $desc->{$k} ) ) {
                        $desc->{$k} = $rtypes->{$ref}{$k};
                    }
                    else {
                        $desc->{ $k . $suffix } = $rtypes->{$ref}{$k}
                          if ( !defined( $desc->{ $k . $suffix } ) );
                    }
                }
            }
        }

        if ( $desc->{scale_m} ) {
            my $ref = $desc->{scale_m};
            foreach my $k ( keys %{ $scales_m->{$ref} } ) {
                $desc->{$k} = $scales_m->{$ref}{$k}
                  if ( !defined( $desc->{$k} ) );
            }
        }
        if ( $desc->{scale_sq} ) {
            foreach my $k ( keys %{$scales_sq} ) {
                $desc->{$k} = $scales_sq->{$k}
                  if ( !defined( $desc->{$k} ) );
            }
            my $ref = $desc->{scale_sq};
            foreach my $k ( keys %{ $scales_m->{$ref} } ) {
                $desc->{ $k . "_sq" } = $scales_m->{$ref}{$k}
                  if ( !defined( $desc->{ $k . "_sq" } ) );
            }
        }
        if ( $desc->{scale_cu} ) {
            foreach my $k ( keys %{$scales_cu} ) {
                $desc->{$k} = $scales_cu->{$k}
                  if ( !defined( $desc->{$k} ) );
            }
            my $ref = $desc->{scale_cu};
            foreach my $k ( keys %{ $scales_m->{$ref} } ) {
                $desc->{ $k . "_cu" } = $scales_m->{$ref}{$k}
                  if ( !defined( $desc->{ $k . "_cu" } ) );
            }
        }
        if ( $desc->{scale_t} ) {
            my $ref = $desc->{scale_t};
            foreach my $k ( keys %{ $scales_t->{$ref} } ) {
                $desc->{$k} = $scales_t->{$ref}{$k}
                  if ( !defined( $desc->{$k} ) );
            }
        }

        $desc->{ref_base} = 999 if ( !defined( $desc->{ref_base} ) );
        my $ref = $desc->{ref_base};
        foreach my $k ( keys %{ $rtype_base->{$ref} } ) {
            $desc->{$k} = $rtype_base->{$ref}{$k}
              if ( !defined( $desc->{$k} ) );
        }
    }

    Unit_Log3( $device, $reading, $desc, 10,
        "readingsDesc $device $reading:\n" . Dumper($desc) );

    return $desc;
}

# format device:reading with optional default value and optional desc and optional format
sub formatReading($$;$$$$$) {
    my ( $device, $reading, $default, $desc, $format, $scope, $lang ) = @_;

    $desc = readingsDesc( $device, $reading ) if ( !$desc );
    my $value = ReadingsVal( $device, $reading, undef );
    $value = $default if ( !defined($value) );

    return formatValue( $device, $reading, $value, $desc, $format,
        $scope, $lang );
}

# return unit symbol for device:reading
sub readingsUnit($$;$$$) {
    my ( $device, $reading, $long, $combined, $desc ) = @_;
    $desc = readingsDesc( $device, $reading ) if ( !$desc );

    return (
        $desc->{suffix} ? $desc->{suffix} : undef,
        $desc->{symbol} ? $desc->{symbol} : undef,
        $desc->{txt}    ? $desc->{txt}    : undef
    ) if (wantarray);

    my ( $txt, $txt_long, $value, $value_num ) =
      formatReading( $device, $reading, "", $desc );

    $txt =~ s/\s*$value\s*//;
    $txt_long =~ s/\s*$value\s*//;

    return "$txt_long ($txt)"
      if ( $combined
        && defined($txt_long)
        && $txt_long ne ""
        && defined($txt)
        && $txt ne "" );
    return $txt_long
      if ( $long && defined($txt_long) && $txt_long ne "" );
    return $txt if ( defined($txt) && $txt ne "" );
    return '';
}

# return dimension symbol for device:reading
sub readingsShortname($$) {
    my ( $device, $reading ) = @_;

    if ( my $desc = readingsDesc( $device, $reading ) ) {
        return $desc->{formula_symbol} if ( $desc->{formula_symbol} );
        return $desc->{dimension}
          if ( $desc->{dimension} && $desc->{dimension} =~ /^[A-Z]+$/ );
        return $desc->{symbol} if ( $desc->{symbol} );
    }

    return $reading;
}

# format device STATE readings according to stateFormat and optional units
sub makeSTATE($;$$) {
    my ( $device, $stateFormat, $withUnits ) = @_;
    $stateFormat = '' if ( !$stateFormat );

    my $hash = $defs{$device};
    return $stateFormat if ( !$hash );

    $stateFormat = AttrVal( $device, 'stateFormat', undef )
      if ( !$stateFormat );
    return '' if ( !$stateFormat );

    # filter own function name to avoid loops
    $stateFormat =~ s/{.*}//mg
      if ( $stateFormat =~ /makeSTATE/ );

    # use all readings if stateFormat is empty
    $stateFormat = join( ' ', sort keys %{ $hash->{READINGS} } )
      if ( $stateFormat !~ /\w+/ );

    my $txt;
    if ( $stateFormat =~ m/^{(.*)}$/ ) {
        $stateFormat = eval $1;
        if ($@) {
            $stateFormat = "Error evaluating $device stateFormat: $@";
            Log 1, $stateFormat;
        }
    }
    else {
        my $r = $hash->{READINGS};
        my %usedShortnames;
        while ( $stateFormat =~ /\b([A-Za-z\d_\.-]+):?([A-Za-z\d_\.-]+)?\b/g ) {
            $txt .= " " if ($txt);

            if ( defined( $r->{$1} ) ) {
                my $sname = readingsShortname( $device, $1 );
                $usedShortnames{$sname}++
                  if ( $usedShortnames{$sname} );
                $usedShortnames{$sname} = 1
                  if ( !$usedShortnames{$sname} );
                if ( $2 && $2 ne "" ) {
                    $txt .= "$2: ";
                }
                elsif ( $usedShortnames{$sname} > 1 ) {
                    $txt .= "$sname" . $usedShortnames{$sname} . ": ";
                }
                else {
                    $txt .= "$sname: ";
                }

                if ($withUnits) {
                    $txt .= formatReading( $device, $1 );
                }
                else {
                    $txt .= ( formatReading( $device, $1 ) )[2];
                }
            }
            else {
                $txt .= $1;
                $txt .= ":$2" if ($2);
            }
        }

        return $txt;
    }

    return $stateFormat;
}

# get combined hash for settings from module, device, global and device attributes
sub getCombinedKeyValAttr($;$$) {
    my ( $name, $attribute, $reading ) = @_;
    my $d = $defs{$name}           if ( $name && $defs{$name} );
    my $m = $modules{ $d->{TYPE} } if ( $d    && $d->{TYPE} );
    my $g = $defs{"global"};

    # join hashes until 3rd level

    my $desc;
    if (   $m
        && $attribute
        && $m->{$attribute}
        && ref( $m->{$attribute} ) eq "HASH" )
    {
        Log3( $name, 5,
"getCombinedKeyValAttr $name $reading: including HASH from module X_Initialize() function"
        );

        foreach my $k ( keys %{ $m->{$attribute} } ) {
            if ( ref( $m->{$attribute}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $m->{$attribute}{$k} } ) {
                    if ( ref( $m->{$attribute}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $m->{$attribute}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $m->{$attribute}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $m->{$attribute}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$_} if ( $desc->{$k} );
                $desc->{$_} = $m->{$attribute}{$k};
            }
        }
    }

    if (   $g
        && $attribute
        && $g->{$attribute}
        && ref( $g->{$attribute} ) eq "HASH" )
    {
        Log3( $name, 5,
"getCombinedKeyValAttr $name $reading: including HASH from global attribute $attribute"
        );

        foreach my $k ( keys %{ $g->{$attribute} } ) {
            if ( ref( $g->{$attribute}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $g->{$attribute}{$k} } ) {
                    if ( ref( $g->{$attribute}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $g->{$attribute}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $g->{$attribute}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $g->{$attribute}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$_} if ( $desc->{$k} );
                $desc->{$_} = $g->{$attribute}{$k};
            }
        }
    }

    if (   $d
        && $attribute
        && $d->{$attribute}
        && ref( $d->{$attribute} ) eq "HASH" )
    {
        Log3( $name, 5,
"getCombinedKeyValAttr $name $reading: including HASH from device attribute $attribute"
        );

        foreach my $k ( keys %{ $d->{$attribute} } ) {
            if ( ref( $d->{$attribute}{$k} ) eq "HASH" ) {
                foreach my $k2 ( keys %{ $d->{$attribute}{$k} } ) {
                    if ( ref( $d->{$attribute}{$k}{$k2} ) eq "HASH" ) {
                        foreach ( keys %{ $d->{$attribute}{$k}{$k2} } ) {
                            delete $desc->{$k}{$k2}{$_}
                              if ( $desc->{$k}{$k2}{$_} );
                            $desc->{$k}{$k2}{$_} =
                              $d->{$attribute}{$k}{$k2}{$_};
                        }
                    }
                    else {
                        delete $desc->{$k}{$k2} if ( $desc->{$k}{$k2} );
                        $desc->{$k}{$k2} = $d->{$attribute}{$k}{$k2};
                    }
                }
            }
            else {
                delete $desc->{$_} if ( $desc->{$k} );
                $desc->{$_} = $d->{$attribute}{$k};
            }
        }
    }

    return
      if (
        keys %{$desc} < 1
        || (
            $reading
            && (  !defined( $desc->{$reading} )
                || keys %{ $desc->{$reading} } < 1 )
        )
      );
    return $desc->{$reading} if ($reading);
    return $desc;
}

# save key/value pair to device attribute
sub setKeyValAttr($$$$$) {
    my ( $name, $attribute, $reading, $key, $value ) = @_;
    my $d = $defs{$name} if ( $defs{$name} );
    my $ret;

    return
      if (
        !$d
        || (   defined( $d->{$attribute} )
            && defined( $d->{$attribute}{$reading} )
            && defined( $d->{$attribute}{$reading}{$key} )
            && $d->{$attribute}{$reading}{$key} eq $value )
      );

    # rtype
    if ( $key =~ /^rtype$/i ) {
        $key = lc($key);

        # Show all possible values
        if ( $value && $value eq "?" ) {
            return "CURRENTLY KNOWN READING TYPES\n\n"
              . PrintHash( $rtypes, 0 );
        }

        # find rtype based on reading name
        elsif ( !defined($value) || $value eq "" ) {
            $value = rname2rtype( $name, $reading );
            $ret =
              "Set auto-detected $key for device $name $reading: " . $value
              if ($value);
        }

        my $curr;
        no strict "refs";
        $curr = &$attribute( $name, $reading ) if (&$attribute);
        use strict "refs";

        return
          if (
               !defined($value)
            || $value eq ""
            || (   defined($curr)
                && defined( $curr->{$key} )
                && $curr->{$key} eq $value )
            || (   defined( $d->{$attribute} )
                && defined( $d->{$attribute}{$reading} )
                && defined( $d->{$attribute}{$reading}{$key} )
                && $d->{$attribute}{$reading}{$key} eq $value )
          );

        return
"Invalid value $value for $key: Cannot be assigned to device $name $reading"
          if ( !defined( $rtypes->{$value} ) );

        $ret =
            "Changed value $key='"
          . $d->{$attribute}{$reading}{$key}
          . "' for device $name $reading to: "
          . $value
          if ( defined( defined( $d->{$attribute} ) )
            && defined( $d->{$attribute}{$reading} )
            && defined( $d->{$attribute}{$reading}{$key} )
            && $d->{$attribute}{$reading}{$key} ne $value );
    }

    $d->{$attribute}{$reading}{$key} = $value;

    # write attribute
    $Data::Dumper::Terse    = 1;
    $Data::Dumper::Deepcopy = 1;
    $Data::Dumper::Sortkeys = 1;
    my $txt = Dumper( $d->{$attribute} );
    $Data::Dumper::Terse    = 0;
    $Data::Dumper::Deepcopy = 0;
    $Data::Dumper::Sortkeys = 0;
    $txt =~ s/(=>\s*\{|['"],?)\s*\n\s*/$1 /gsm;
    CommandAttr( undef, "$name $attribute $txt" );
    return $ret;
}

sub deleteKeyValAttr($$$;$) {
    my ( $name, $attribute, $reading, $key ) = @_;
    my $d = $defs{$name} if ( $defs{$name} );
    my $rt;

    return
      if ( !$d
        || !defined( $d->{$attribute} )
        || !defined( $d->{$attribute}{$reading} )
        || ( $key && !defined( $d->{$attribute}{$reading}{$key} ) ) );

    if ($key) {
        $rt = " $key=" . $d->{$attribute}{$reading}{$key};
        delete $d->{$attribute}{$reading}{$key};
    }

    delete $d->{$attribute}{$reading}
      if ( !$key || keys %{ $d->{$attribute}{$reading} } < 1 );

    # delete attribute
    if ( keys %{ $d->{$attribute} } < 1 ) {
        CommandDeleteAttr( undef, "$name $attribute" );
    }

    # write attribute
    else {
        $Data::Dumper::Terse    = 1;
        $Data::Dumper::Sortkeys = 1;
        my $txt = Dumper( $d->{$attribute} );
        $Data::Dumper::Terse    = 0;
        $Data::Dumper::Sortkeys = 0;
        $txt =~ s/(=>\s*\{|[\'\"0-9],?)\s*\n\s*/$1 /gsm;
        CommandAttr( undef, "$name $attribute $txt" );
    }

    return "Removed $reading$rt from attribute $name $attribute";
}

################################################################
#
# Wrappers for commonly used core functions in device-specific modules.
#
################################################################

# Generalized function for DbLog rtype support
sub Unit_DbLog_split($$) {
    my ( $event, $name ) = @_;
    my ( $reading, $value, $unit ) = "";

    # exclude any multi-value events
    if ( $event =~ /(.*: +.*: +.*)+/ ) {
        Log3 $name, 5,
          "Unit_DbLog_split $name: Ignoring multi-value event $event";
        return undef;
    }

    # exclude sum/cum and avg events
    elsif ( $event =~
        /^.*(min|max|avg|sum|cum|min\d+m|max\d+m|avg\d+m|sum\d+m|cum\d+m): +.*/
      )
    {
        Log3 $name, 5, "Unit_DbLog_split $name: Ignoring sum/avg event $event";
        return undef;
    }

    # automatic text conversions through reading type
    elsif ( $event =~ /^(.+): +(\S+) *(.*)/ ) {
        $reading = $1;

        my ( $txt, $txt_long, $val, $val_num, $symbol ) =
          formatReading( $name, $reading, "" );

        if ( defined($txt) && defined($reading) && defined($val) ) {
            $txt =~ s/[\s\u202F\u00A0]*$val[\s\u202F\u00A0]*//;
            $value = $val;
            if ( !looks_like_number($val) && defined($val_num) ) {
                if ( ref($val_num) eq "ARRAY" ) {
                    $value = $val_num->[1];
                }
                else {
                    $value = $val_num;
                }
            }
            $unit = defined($symbol) ? $symbol : $txt;
        }
    }

    # general event handling
    if ( !defined($value)
        && $event =~
m/^(.+): +[\D]*(\d+\.?\d*)[\s\u202F\u00A0]*[\[\{\(]?[\s\u202F\u00A0]*([\w\°\%\^\/\\]*).*/
        && defined($1)
        && defined($2) )
    {
        $reading = $1;
        $value   = ReadingsNum( $name, $1, $2 );
        $unit    = defined($3) ? $3 : "";
    }

    if ( !defined($value) || !looks_like_number($value) ) {
        Unit_Log3( $name, $reading, undef, 10,
"Unit_DbLog_split $name: Ignoring event $event: value $value does not look like a number"
        ) if ( defined($value) );
        return undef;
    }

    Unit_Log3( $name, $reading, undef, 9,
"Unit_DbLog_split $name: Splitting event $event > reading=$reading value=$value unit=$unit"
    );

    return ( $reading, $value, $unit );
}

################################################
# the new Log with integrated loglevel checking for readings
sub Unit_Log3($$$$$) {
    my ( $dev, $rname, $desc, $loglevel, $text ) = @_;

    $dev = $dev->{NAME} if ( defined($dev) && ref($dev) eq "HASH" );
    $desc = readingsDesc( $dev, $rname )
      if ( !$desc || !ref($desc) );
    my $rloglevel = $loglevel;

    if (   $desc
        && ref($desc) eq "HASH"
        && defined( my $rlevel = $desc->{verbose} ) )
    {
        return if ( $loglevel > $rlevel );
        $rloglevel = $rloglevel - 9;
    }

    return Log3( $dev, $rloglevel, "RType: " . $text );
}

################################################################
#
# User commands
#
################################################################

# command: setreadingdesc
my %setreadingdeschash = (
    Fn => "CommandSetReadingDesc",
    Hlp =>
"<devspec> <readingspec> [noCheck] <key>=[<value>|?],set reading rtype information for <devspec> <reading>",
);
$cmds{setreadingdesc} = \%setreadingdeschash;

sub CommandSetReadingDesc($@) {
    my ( $cl, $def ) = @_;
    my $attribute = "readingsDesc";
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my ( $a, $h ) = parseParams($def);

    $a->[0] = ".*" if ( !$a->[0] );
    $a->[1] = ".*" if ( !$a->[1] );

    return
"Usage: setreadingdesc <devspec> <readingspec> [noCheck] <key>=[<value>|?]\n$namedef"
      if ( $a->[0] eq "?" || $a->[1] eq "?" || !%{$h} );

    my @rets;
    my $last;
    foreach my $name ( devspec2array( $a->[0], $cl ) ) {
        unless ( IsDevice($name) ) {
            push @rets, "Please define $name first";
            next;
        }

        # do not check for existing reading
        if ( $name eq "global"
            || ( defined( $a->[2] ) && $a->[2] =~ /nocheck/i ) )
        {
            foreach ( keys %$h ) {
                my $ret =
                  setKeyValAttr( $name, $attribute, $a->[1], $_, $h->{$_} );
                push @rets, $ret if ( defined($ret) );
                $last = 1 if ( $h->{$_} eq "?" || $h->{$_} eq "" );
            }
            next;
        }

        # check for existing reading
        my $readingspec = '^' . $a->[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$name}{READINGS} }
          )
        {
            foreach ( keys %$h ) {
                my $ret =
                  setKeyValAttr( $name, $attribute, $reading, $_, $h->{$_} );
                push @rets, $ret if ( defined($ret) );
                $last = 1 if ( $h->{$_} eq "?" || $h->{$_} eq "" );
            }
        }

        last if ($last);
    }
    return join( "\n", @rets );
}

# command: deletereadingdesc
my %deletereadingdeschash = (
    Fn => "CommandDeleteReadingDesc",
    Hlp =>
      "<devspec> <readingspec> [<keyspec>],delete key for <devspec> <reading>",
);
$cmds{deletereadingdesc} = \%deletereadingdeschash;

sub CommandDeleteReadingDesc($@) {
    my ( $cl, $def ) = @_;
    my $attribute = "readingsDesc";
    my $namedef =
"where <devspec> is a single device name, a list separated by comma (,) or a regexp. See the devspec section in the commandref.html for details.\n"
      . "<readingspec> and <keyspec> can be a single reading name, a list separated by comma (,) or a regexp.";

    my ( $a, $h ) = parseParams($def);

    $a->[0] = ".*" if ( !$a->[0] );
    $a->[1] = ".*" if ( !$a->[1] );
    $a->[2] = ".*" if ( !$a->[2] );

    return
      "Usage: deletereadingdesc <devspec> <readingspec> [<keyspec>]\n$namedef"
      if ( $a->[0] eq "?" || $a->[1] eq "?" );

    my @rets;
    my $last;
    foreach my $name ( devspec2array( $a->[0], $cl ) ) {
        unless ( IsDevice($name) ) {
            push @rets, "Please define $name first";
            next;
        }

        my $readingspec = '^' . $a->[1] . '$';
        foreach my $reading (
            grep { /$readingspec/ }
            keys %{ $defs{$name}{$attribute} }
          )
        {
            my $keyspec = '^' . $a->[2] . '$';
            foreach my $key (
                grep { /$keyspec/ }
                keys %{ $defs{$name}{$attribute}{$reading} }
              )
            {
                my $ret = deleteKeyValAttr( $name, $attribute, $reading, $key );
                push @rets, $ret if ( defined($ret) );
            }
        }
    }
    return join( "\n", @rets );
}

1;

=pod
=encoding utf8

=for :application/json;q=META.json Unit.pm
{
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ],
  "keywords": [
    "RType",
    "Unit"
  ]
}
=end :application/json;q=META.json

=cut

# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------

=encoding UTF-8

=head1 NAME

DWD_OpenData - A FHEM Perl module to retrieve forecasts and alerts from the
DWD Open Data Server.

=head1 LICENSE AND COPYRIGHT


  Copyright (C) 2018 Jens B.


Use of HttpUtils instead of LWP::Simple:

  Copyright (C) 2018 JoWiemann
    see https://forum.fhem.de/index.php/topic,83097.msg761015.html#msg761015

Sun position:

  Copyright (c) Plataforma Solar de Almerýa, Spain
    see http://www.psa.es/sdg/sunpos.htm

Sunrise and sunset:

  see https://www.aa.quae.nl/en/reken/zonpositie.html
  see https://en.wikipedia.org/wiki/Sunrise_equation

Julian date conversion:

  Copyright (C) 2012 E. G. Richards
    see Explanatory Supplement to the Astronomical Almanac, 3rd edition, S.E Urban and P.K. Seidelmann eds., chapter 15.11.3, Interconverting Dates and Julian Day Numbers, Algorithm 4

This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

The GNU General Public License can be found at

http://www.gnu.org/copyleft/gpl.html.

A copy is found in the textfile GPL.txt and important notices to the license
from the author is found in LICENSE.txt distributed with these scripts.

This script is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

This copyright notice MUST APPEAR in all copies of the script!

=cut

package DWD_OpenData;

use strict;
use warnings;

use Encode;
use File::Temp qw(tempfile);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use Math::Trig ':pi';
use POSIX;
use Scalar::Util qw(looks_like_number);
use Storable qw(freeze thaw);
use Time::HiRes qw(gettimeofday usleep);
use Time::Local;
use Time::Piece;

use Blocking;
use HttpUtils;

use feature qw(switch);
no if $] >= 5.017011, warnings => 'experimental';

use constant UPDATE_DISTRICTS     => -1;
use constant UPDATE_COMMUNEUNIONS => -2;
use constant UPDATE_ALL           => -3;

require Exporter;
our $VERSION   = 1.014.002;
our @ISA       = qw(Exporter);
our @EXPORT    = qw(GetForecast GetAlerts UpdateAlerts UPDATE_DISTRICTS UPDATE_COMMUNEUNIONS UPDATE_ALL);
our @EXPORT_OK = qw(IsCommuneUnionWarncellId);

my %forecastPropertyAliases = ( 'TX' => 'Tx', 'TN' => 'Tn', 'TG' => 'Tg', 'TM' => 'Tm' );

my %forecastPropertyPeriods = (
                               'DD' => 1, 'DRR1' => 1, 'E_DD' => 1, 'E_FF' => 1, 'E_PPP' => 1, 'E_Td' => 1, 'E_TTT' => 1, 'FF' => 1, 'FX1' => 1, 'FX3' => 1, 'FX625' => 1, 'FX640' => 1, 'FX655' => 1, 'FXh' => 1, 'FXh25' => 1, 'FXh40' => 1, 'FXh55' => 1, 'N' => 1, 'N05' => 1, 'Neff' => 1, 'Nh' => 1, 'Nl' => 1, 'Nlm' => 1, 'Nm' => 1, 'PPPP' => 1, 'R101' => 1, 'R102' => 1, 'R103' => 1, 'R105' => 1, 'R107' => 1, 'R110' => 1, 'R120' => 1, 'R130' => 1, 'R150' => 1, 'R600' => 1, 'R602' => 1, 'R610' => 1, 'R650' => 1, 'RR1c' => 1, 'RR1o1' => 1, 'RR1u1' => 1, 'RR1w1' => 1, 'RR3c' => 1, 'RR6c' => 1, 'RRL1c' => 1, 'RRS1c' => 1, 'RRS3c' => 1, 'RRad1' => 1, 'Rad1h' => 1, 'RRhc' => 1, 'Rh00' => 1, 'Rh02' => 1, 'Rh10' => 1, 'Rh50' => 1, 'SunAz' => 1, 'SunD1' => 1, 'SunD3' => 1, 'SunEl' => 1, 'SunUp' => 1, 'T5cm' => 1, 'Td' => 1, 'TTT' => 1, 'VV' => 1, 'VV10' => 1, 'W1W2' => 1, 'WPc11' => 1, 'WPc31' => 1, 'WPc61' => 1, 'WPcd1' => 1, 'WPch1' => 1, 'ww' => 1, 'ww3' => 1, 'wwC' => 1, 'wwC6' => 1, 'wwCh' => 1, 'wwD' => 1, 'wwD6' => 1, 'wwDh' => 1, 'wwF' => 1, 'wwF6' => 1, 'wwFh' => 1, 'wwL' => 1, 'wwL6' => 1, 'wwLh' => 1, 'wwM' => 1, 'wwM6' => 1, 'wwMd' => 1, 'wwMh' => 1, 'wwP' => 1, 'wwP6' => 1, 'wwPd' => 1, 'wwPh' => 1, 'wwS' => 1, 'wwS6' => 1, 'wwSh' => 1, 'wwT' => 1, 'wwT6' => 1, 'wwTd' => 1, 'wwTh' => 1, 'wwZ' => 1, 'wwZ6' => 1, 'wwZh' => 1,
                               'PEvap' => 24, 'PSd00' => 24, 'PSd30' => 24, 'PSd60' => 24, 'RRdc' => 24, 'RSunD' => 24, 'Rd00' => 24, 'Rd02' => 24, 'Rd10' => 24, 'Rd50' => 24, 'SunD' => 24, 'SunRise' => 24, 'SunSet' => 24, 'Tg' => 24, 'Tm' => 24, 'Tn' => 24, 'Tx' => 24
                              );

my %forecastDefaultProperties = (
                                 'Tg' => 1, 'Tn' => 1, 'Tx' => 1, 'DD' => 1, 'FX1' => 1, 'Neff' => 1, 'RR6c' => 1, 'R600' => 1, 'RRhc' => 1, 'Rh00' => 1, 'TTT' => 1, 'ww' => 1, 'SunUp' => 1
                                );

# conversion of DWD value to: 1 = temperature in K, 2 = integer value, 3 = wind speed in m/s, 4 = pressure in Pa
my %forecastPropertyTypes = (
                             'Tx' => 1, 'Tn' => 1, 'Tg' => 1, 'Tm'=> 1, 'Td'  => 1, 'T5cm'  => 1, 'TTT'   => 1,
                             'DD' => 2, 'Neff' => 2, 'Nh' => 2, 'Nl' => 2, 'Nlm' => 2, 'Nm' => 2, 'Rh00' => 2, 'ww'  => 2, 'ww3' => 2, 'WPc11' => 2, 'WPc31' => 2, 'WPc61' => 2, 'WPch1' => 2, 'WPcd1' => 2,
                             'FF' => 3, 'FX1' => 3, 'FX3' => 3, 'FXh' => 3,
                             'PPPP' => 4
                            );

my @wwdText = ('Bewölkungsentwicklung nicht beobachtet',
               'Bewölkung abnehmend',
               'Bewölkung unverändert',
               'Bewölkung zunehmend',
               # 4 Dunst, Rauch, Staub oder Sand
               'Sicht durch Rauch oder Asche vermindert',
               'trockener Dunst (relative Feuchte < 80 %)',
               'verbreiteter Schwebstaub, nicht vom Wind herangeführt',
               'Staub oder Sand bzw. Gischt, vom Wind herangeführt',
               'gut entwickelte Staub- oder Sandwirbel',
               'Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station',
               # 10 Trockenereignisse
               'feuchter Dunst (relative Feuchte > 80 %)',
               'Schwaden von Bodennebel',
               'durchgehender Bodennebel',
               'Wetterleuchten sichtbar, kein Donner gehört',
               'Niederschlag im Gesichtskreis, nicht den Boden erreichend',
               'Niederschlag in der Ferne (> 5 km), aber nicht an der Station',
               'Niederschlag in der Nähe (< 5 km), aber nicht an der Station',
               'Gewitter (Donner hörbar), aber kein Niederschlag an der Station',
               'Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station',
               'Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis',
               # 20 Ereignisse der letzten Stunde, aber nicht zur Beobachtungszeit
               'nach Sprühregen oder Schneegriesel',
               'nach Regen',
               'nach Schneefall',
               'nach Schneeregen oder Eiskörnern',
               'nach gefrierendem Regen',
               'nach Regenschauer',
               'nach Schneeschauer',
               'nach Graupel- oder Hagelschauer',
               'nach Nebel',
               'nach Gewitter',
               # 30 Staubsturm, Sandsturm, Schneefegen oder -treiben
               'leichter oder mäßiger Sandsturm, an Intensität abnehmend',
               'leichter oder mäßiger Sandsturm, unveränderte Intensität',
               'leichter oder mäßiger Sandsturm, an Intensität zunehmend',
               'schwerer Sandsturm, an Intensität abnehmend',
               'schwerer Sandsturm, unveränderte Intensität',
               'schwerer Sandsturm, an Intensität zunehmend',
               'leichtes oder mäßiges Schneefegen, unter Augenhöhe',
               'starkes Schneefegen, unter Augenhöhe',
               'leichtes oder mäßiges Schneetreiben, über Augenhöhe',
               'starkes Schneetreiben, über Augenhöhe',
               # 40 Nebel oder Eisnebel
               'Nebel in einiger Entfernung',
               'Nebel in Schwaden oder Bänken',
               'Nebel, Himmel erkennbar, dünner werdend',
               'Nebel, Himmel nicht erkennbar, dünner werdend',
               'Nebel, Himmel erkennbar, unverändert',
               'Nebel, Himmel nicht erkennbar, unverändert',
               'Nebel, Himmel erkennbar, dichter werdend',
               'Nebel, Himmel nicht erkennbar, dichter werdend',
               'Nebel mit Reifansatz, Himmel erkennbar',
               'Nebel mit Reifansatz, Himmel nicht erkennbar',
               # 50 Sprühregen
               'unterbrochener leichter Sprühregen',
               'durchgehend leichter Sprühregen',
               'unterbrochener mäßiger Sprühregen',
               'durchgehend mäßiger Sprühregen',
               'unterbrochener starker Sprühregen',
               'durchgehend starker Sprühregen',
               'leichter gefrierender Sprühregen',
               'mäßiger oder starker gefrierender Sprühregen',
               'leichter Sprühregen mit Regen',
               'mäßiger oder starker Sprühregen mit Regen',
               # 60 Regen
               'unterbrochener leichter Regen oder einzelne Regentropfen',
               'durchgehend leichter Regen',
               'unterbrochener mäßiger Regen',
               'durchgehend mäßiger Regen',
               'unterbrochener starker Regen',
               'durchgehend starker Regen',
               'leichter gefrierender Regen',
               'mäßiger oder starker gefrierender Regen',
               'leichter Schneeregen',
               'mäßiger oder starker Schneeregen',
               # 70 Schnee
               'unterbrochener leichter Schneefall oder einzelne Schneeflocken',
               'durchgehend leichter Schneefall',
               'unterbrochener mäßiger Schneefall',
               'durchgehend mäßiger Schneefall',
               'unterbrochener starker Schneefall',
               'durchgehend starker Schneefall',
               'Eisnadeln (Polarschnee)',
               'Schneegriesel',
               'Schneekristalle',
               'Eiskörner (gefrorene Regentropfen)',
               # 80 Schauer
               'leichter Regenschauer',
               'mäßiger oder starker Regenschauer',
               'äußerst heftiger Regenschauer',
               'leichter Schneeregenschauer',
               'mäßiger oder starker Schneeregenschauer',
               'leichter Schneeschauer',
               'mäßiger oder starker Schneeschauer',
               'leichter Graupelschauer',
               'mäßiger oder starker Graupelschauer',
               'leichter Hagelschauer',
               'mäßiger oder starker Hagelschauer',
               # 90 Gewitter
               'Gewitter in der letzten Stunde, zurzeit leichter Regen',
               'Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Regen',
               'Gewitter in der letzten Stunde, zurzeit leichter Schneefall/Schneeregen/Graupel/Hagel',
               'Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Schneefall/Schneeregen/Graupel/Hagel',
               'leichtes oder mäßiges Gewitter mit Regen oder Schnee',
               'leichtes oder mäßiges Gewitter mit Graupel oder Hagel',
               'starkes Gewitter mit Regen oder Schnee',
               'starkes Gewitter mit Sandsturm',
               'starkes Gewitter mit Graupel oder Hagel');

my @alertsData         = [ undef, undef ];
my @alertsReceived     = [ undef, undef ];
my @alertsUpdating     = [ undef, undef ];
my @alertsErrorMessage = [ undef, undef ];


=head1 FHEM CALLBACK FUNCTIONS

=head2 Define($$)

FHEM I<DefFn>

=over

=item * param hash: hash of DWD_OpenData device

=item * param def: module define parameters, will be ignored

=item * return undef on success or error message

=back

=cut

sub Define($$) {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

  # test TZ environment variable
  if (!defined($ENV{"TZ"})) {
    $hash->{FHEM_TZ} = undef;
  } else {
    $hash->{FHEM_TZ} = $ENV{"TZ"};
  }

  # cache timezone attribute
  $hash->{'.TZ'} = ::AttrVal($hash, 'timezone', $hash->{FHEM_TZ});

  ::readingsSingleUpdate($hash, 'state', ::IsDisabled($name)? 'disabled' : 'defined', 1);
  ::InternalTimer(gettimeofday() + 3, 'DWD_OpenData::Timer', $hash, 0);

  return undef;
}

=head2 Undef($$)

FHEM I<UndefFn>

=over

=item * param hash: hash of DWD_OpenData device

=item * param arg: module undefine arguments, will be ignored

=back

=cut

sub Undef($$) {
  my ($hash, $arg) = @_;

  Shutdown($hash);

  return undef;
}

=head2 Shutdown($)

FHEM I<ShutdownFn>

=over

=item * param hash: hash of DWD_OpenData device

=back

=cut

sub Shutdown($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ::RemoveInternalTimer($hash);

  my $warncellId = $hash->{".warncellId"};
  my $communeUnion = IsCommuneUnionWarncellId($warncellId);
  if (defined($hash->{".alertsBlockingCall"})) {
    ::BlockingKill($hash->{".alertsBlockingCall"});
  }
  if (defined($hash->{".alertsFile".$communeUnion})) {
    close($hash->{".alertsFileHandle".$communeUnion});
    unlink($hash->{".alertsFile".$communeUnion});
    delete($hash->{".alertsFile".$communeUnion});
  }

  if (defined($hash->{".forecastBlockingCall"})) {
    ::BlockingKill($hash->{".forecastBlockingCall"});
  }
  if (defined($hash->{".forecastFile"})) {
    close($hash->{".forecastFileHandle"});
    unlink($hash->{".forecastFile"});
    delete($hash->{".forecastFile"});
  }

  return undef;
}

=head2 Attr(@)

FHEM I<AttrFn>

=over

=item * param command: "set" or "del"

=item * param name: name of DWD_OpenData device

=item * param attribute: attribute name

=item * param value: attribute value

=item * return C<undef> on success or error message

=back

=cut

sub Attr(@) {
  my ($command, $name, $attribute, $value) = @_;
  my $hash = $::defs{$name};

  given($command) {
    when("set") {
      given($attribute) {
        when("disable") {
          # enable/disable polling
          if ($::init_done) {
            if ($value) {
              ::RemoveInternalTimer($hash);
              ::readingsSingleUpdate($hash, 'state', 'disabled', 1);
            } else {
              ::readingsSingleUpdate($hash, 'state', 'defined', 1);
              ::InternalTimer(gettimeofday() + 3, 'DWD_OpenData::Timer', $hash, 0);
            }
          }
        }
        when("forecastResolution") {
          if (defined($value) && looks_like_number($value) && $value > 0) {
            my $oldForecastResolution = ::AttrVal($name, 'forecastResolution', 6);
            if ($::init_done && defined($oldForecastResolution) && $oldForecastResolution != $value) {
              ::CommandDeleteReading(undef, "$name ^fc.*");
            }
          } else {
            return "invalid value for forecastResolution (possible values are 1, 3 and 6)";
          }
        }
        when("forecastStation") {
          my $oldForecastStation = ::AttrVal($name, 'forecastStation', undef);
          if ($::init_done && defined($oldForecastStation) && $oldForecastStation ne $value) {
            ::CommandDeleteReading(undef, "$name ^fc.*");
          }
        }
        when("forecastWW2Text") {
          if ($::init_done && !$value) {
            ::CommandDeleteReading(undef, "$name ^fc.*wwd\$");
          }
        }
        when("timezone") {
          if (defined($value) && length($value) > 0) {
            $hash->{'.TZ'} = $value;
          } else {
            return "timezone (e.g. Europe/Berlin) required";
          }
        }
      }
    }

    when("del") {
      given($attribute) {
        when("disable") {
          ::readingsSingleUpdate($hash, 'state', 'defined', 1);
          ::InternalTimer(gettimeofday() + 3, 'DWD_OpenData::Timer', $hash, 0);
        }
        when("forecastResolution") {
          my $oldForecastResolution = ::AttrVal($name, 'forecastResolution', 6);
          if ($oldForecastResolution != 6) {
            ::CommandDeleteReading(undef, "$name ^fc.*");
          }
        }
        when("forecastStation") {
          ::CommandDeleteReading(undef, "$name ^fc.*");
        }
        when("forecastWW2Text") {
          ::CommandDeleteReading(undef, "$name ^fc.*wwd\$");
        }
        when("timezone") {
          $hash->{'.TZ'} = $hash->{FHEM_TZ};
        }
      }
    }
  }

  return undef;
}

=head2 Get($@)

FHEM I<GetFn>

=over

=item * param hash: hash of DWD_OpenData device

=item * param a: array of FHEM command line arguments, min. length 2, a[1] holds get command

=item * return requested data or error message

=back

=cut

sub Get($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  my $result = undef;
  my $command = lc($a[1]);
  given($command) {
    when("alerts") {
      my $warncellId = $a[2];
      $warncellId = ::AttrVal($name, 'alertArea', undef) if (!defined($warncellId));
      if (defined($warncellId)) {
        my $communeUnion = IsCommuneUnionWarncellId($warncellId);
        if (defined($alertsUpdating[$communeUnion]) && (time() - $alertsUpdating[$communeUnion] < 60)) {
          # abort if update is in progress
          $result = "alerts cache update in progress, please wait and try again";
        } elsif (defined($alertsReceived[$communeUnion]) && (time() - $alertsReceived[$communeUnion] < 900)) {
          # use cache if not older than 15 minutes
          $result = UpdateAlerts($hash, $warncellId);
        } else {
          # update cache if older than 15 minutes
          $result = GetAlerts($hash, $warncellId);
        }
      } else {
        $result = "warncell id required for $name get $command";
      }
    }

    when("forecast") {
      my $station = $a[2];
      $station = ::AttrVal($name, 'forecastStation', undef) if (!defined($station));
      if (defined($station)) {
        if (defined($hash->{forecastUpdating}) && (time() - $hash->{forecastUpdating} < 60)) {
          # abort if update is in progress
          $result = "forecast update in progress, please wait and try again";
        } else {
          delete $hash->{".fetchAlerts"};
          $result = GetForecast($hash, $station);
        }
      } else {
        $result = "station code required for $name get $command";
      }
    }

    when("updatealertscache") {
      my $updateMode = undef;
      my $option = lc($a[2]);
      given($option) {
        when("communeunions") {
          $updateMode = UPDATE_COMMUNEUNIONS;
        }
        when("districts") {
          $updateMode = UPDATE_DISTRICTS;
        }
        when("all") {
          $updateMode = UPDATE_ALL;
        }
        default {
          return "update mode 'communeUnions', 'districts' or 'all' required for $name get $command";
        }
      }
      my $communeUnion = IsCommuneUnionWarncellId($updateMode);
      if (defined($alertsUpdating[$communeUnion]) && (time() - $alertsUpdating[$communeUnion] < 60)) {
        # abort if update is in progress
        $result = "alerts cache update in progress, please wait and try again";
      } else {
        # update cache if older than 15 minutes
        $result = GetAlerts($hash, $updateMode);
      }
    }

    default {
      $result = "unknown get command $command, choose one of alerts forecast updateAlertsCache:communeUnions,districts,all";
    }
  }

  return $result;
}

=head2 Timer($)

FHEM I<InternalTimer> function

=over

=item * param args: hash of DWD_OpenData device

=back

=cut

sub Timer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 5, "$name: Timer START";

  my $time = time();
  my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = gmtime($time);
  my $actQuarter = int($tMin/15);

  if ($actQuarter == 0 && !(defined($hash->{".fetchAlerts"}) && $hash->{".fetchAlerts"})) {
    # preset: try to fetch alerts immediately
    $hash->{".fetchAlerts"} = 1;
    my $forecastStation = ::AttrVal($name, 'forecastStation', undef);
    if (defined($forecastStation)) {
      if (!defined($hash->{forecastUpdating}) || ($time - $hash->{forecastUpdating} >= 60)) {
        my $result = GetForecast($hash, $forecastStation);
        if (defined($result)) {
          ::Log3 $name, 4, "$name: error retrieving forecast: $result";
        } else {
          # fetching forecast started: wait for forecast fetch to complete
          $hash->{".fetchAlerts"} = 0;
        }
      }
    }
  }

  if ($actQuarter > 0 || (defined($hash->{".fetchAlerts"}) && $hash->{".fetchAlerts"})) {
    my $warncellId = ::AttrVal($name, 'alertArea', undef);
    if (defined($warncellId)) {
      # skip update if already in progress
      my $communeUnion = IsCommuneUnionWarncellId($warncellId);
      if (!defined($alertsUpdating[$communeUnion]) || ($time - $alertsUpdating[$communeUnion] >= 60)) {
        my $result = GetAlerts($hash, $warncellId);
        if (defined($result)) {
          ::Log3 $name, 4, "$name: error retrieving alerts: $result";
        }
      }
    }

    $hash->{".fetchAlerts"} = $actQuarter < 3;
  }

  # reschedule next run for 5 seconds past next quarter
  ::RemoveInternalTimer($hash);
  my $nextTime = timegm(0, $actQuarter*15, $tHour, $tMday, $tMon, $tYear) + 905;
  ::InternalTimer($nextTime, 'DWD_OpenData::Timer', $hash);

  ::Log3 $name, 5, "$name: Timer END";
}

=head1 MODULE FUNCTIONS

=head2 Timelocal($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param ta: localtime array in device timezone

=item * return epoch seconds

=back

=cut

sub Timelocal($@) {
  my ($hash, @ta) = @_;
  if (defined($hash->{'.TZ'})) {
    $ENV{"TZ"} = $hash->{'.TZ'};
  }
  my $t = timelocal(@ta);
  if (defined($hash->{FHEM_TZ})) {
    $ENV{"TZ"} = $hash->{FHEM_TZ};
  } else {
    delete $ENV{"TZ"};
  }
  return $t;
}

=head2 Localtime(@)

=over

=item * param hash: hash of DWD_OpenData device

=item * param t:    epoch seconds

=item * return localtime array in device timezone

=back

=cut

sub Localtime(@) {
  my ($hash, $t) = @_;
  if (defined($hash->{'.TZ'})) {
    $ENV{"TZ"} = $hash->{'.TZ'};
  }
  my @ta = localtime($t);
  if (defined($hash->{FHEM_TZ})) {
    $ENV{"TZ"} = $hash->{FHEM_TZ};
  } else {
    delete $ENV{"TZ"};
  }
  return @ta;
}

=head2 LocaltimeOffset(@)

=over

=item * param hash: hash of DWD_OpenData device

=item * param t:    epoch seconds

=item * return time zone offset [s]

=back

=cut

sub LocaltimeOffset(@)  {
  my ($hash, $t) = @_;
  if (defined($hash->{'.TZ'})) {
    $ENV{"TZ"} = $hash->{'.TZ'};
  }
  my $z = strftime('%z', localtime($t));
  my $tzo = 3600*floor($z/100) + 60*($z%100);
  if (defined($hash->{FHEM_TZ})) {
    $ENV{"TZ"} = $hash->{FHEM_TZ};
  } else {
    delete $ENV{"TZ"};
  }
  return $tzo;
}

=head2 FormatDateTimeLocal($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param t: epoch seconds

=item * return date time string with with format "YYYY-MM-DD HH:MM:SS" in device timezone

=back

=cut

sub FormatDateTimeLocal($$) {
  return strftime('%Y-%m-%d %H:%M:%S', Localtime(@_));
}

=head2 FormatDateLocal($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param t: epoch seconds

=item * return date string with with format "YYYY-MM-DD" in device timezone

=back

=cut

sub FormatDateLocal($$) {
  return strftime('%Y-%m-%d', Localtime(@_));
}

=head2 FormatTimeLocal($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param t: epoch seconds

=item * return time string with format "HH:MM" in device timezone

=back

=cut

sub FormatTimeLocal($$) {
  return strftime('%H:%M', Localtime(@_));
}

=head2 FormatWeekdayLocal($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param t: epoch seconds

=item * return abbreviated weekday name in device timezone

=back

=cut

sub FormatWeekdayLocal($$) {
  return strftime('%a', Localtime(@_));
}

=head2 ParseDateTimeLocal($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param s: date string with format "YYYY-MM-DD HH:MM:SS" in device timezone

=item * return epoch seconds or C<undef> on error

=back

=cut

sub ParseDateTimeLocal($$) {
  my ($hash, $s) = @_;
  my $t;
  eval { $t = Timelocal($hash, ::strptime($s, '%Y-%m-%d %H:%M:%S')) };
  return $t;
}

=head2 ParseDateLocal($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param s: date string with format "YYYY-MM-DD" in device timezone

=item * return epoch seconds or C<undef> on error

=back

=cut

sub ParseDateLocal($$) {
  my ($hash, $s) = @_;
  my $t;
  eval { $t = Timelocal($hash, ::strptime($s, '%Y-%m-%d')) };
  return $t;
}

=head2 ParseCAPTime($)

=over

=item * param s: time string with format "YYYY-MM-DDThh:mm:ssZZZ:ZZ"

=item * return epoch seconds

=back

=cut

sub ParseCAPTime($) {
  my ($s) = @_;

  $s =~ s|(.+):|$1|; # remove colon from time zone offset
  #Log 1, "ParseCAPTime: " . $s;
  return Time::Piece->strptime($s, '%Y-%m-%dT%H:%M:%S%z')->epoch;
}

=head2 ParseKMLTime($)

=over

=item * param s: time string with format "YYYY-MM-DDThh:mm:ss.000Z"

=item * return epoch seconds

=back

=cut

sub ParseKMLTime($) {
  my ($s) = @_;
  $s =~ s|(.+)\.000Z|$1|; # remove milliseconds and timezone
  return Time::Piece->strptime($s, '%Y-%m-%dT%H:%M:%S')->epoch;
}

=head2 IsCommuneUnionWarncellId($)

=over

=item * param warncellId: numeric wanrcell id

=item * return true if warncell id belongs to commune union group

=back

=cut

sub IsCommuneUnionWarncellId($) {
  my ($warncellId) = @_;
  return int($warncellId/100000000) == 5 || int($warncellId/100000000) == 7 || int($warncellId/100000000) == 8
         || $warncellId == UPDATE_COMMUNEUNIONS || $warncellId == UPDATE_ALL? 1 : 0;
}

=head2 EpochToJulianDate(;$)

=over

=item * param time: epoch time [s], optional, default: now

=item * return Julian date

=back

=cut

sub EpochToJulianDate(;$) {
  my ($epoch) = @_;

  if (!defined($epoch)) {
    $epoch = time();
  }

  return gmtime($epoch)->julian_day;
}

=head2 EpochToGreenwichMeanSideralDate(;$)

Copyright (c) Plataforma Solar de Almerýa, Spain

simplified algorithm, accurate to within 0.5 minutes of arc for the year 1999-2015

=over

=item * param time: epoch time [s], optional, default: now

=item * return Greenwich mean sideral date

=back

=cut

sub EpochToGreenwichMeanSideralDate(;$) {
  my ($epoch) = @_;

  if (!defined($epoch)) {
    $epoch = time();
  }

  my $elapsedDays = EpochToJulianDate($epoch) - 2451545 + 0.0008;
  my ($seconds, $minutes, $hours, $day, $month, $year, $wday, $yday, $isdst) = gmtime($epoch);
  my $timeAsHours = $hours + $minutes/60.0 + $seconds/3600.0;

  return 6.6974243242 + 0.0657098283*$elapsedDays + $timeAsHours;
}

=head2 JulianDateToEpoch(;$)

Copyright (C) 2012 E. G. Richards

=over

=item * param jd: Julian date [day], optional, default: now

=item * return Gregorian date [epoch]

=back

=cut

sub JulianDateToEpoch(;$) {
  my ($jd) = @_;

  if (!defined($jd)) {
    return time();
  } else {
    my $j = floor($jd);
    my $f = $j + 1401;
    $f += 3*floor(floor((4*$jd + 274277.0)/146097)/4) - 38;
    my $e = 4*$f + 3;
    my $g = floor(($e%1461)/4);
    my $h = 5*$g + 2;
    my $day = floor(($h%153)/5) + 1;
    my $month = (floor($h/153) + 2)%12 + 1;
    my $year = floor($e/1461) - 4716 + floor((14 - $month)/12);

    my $seconds = sprintf("%0.0f", 86400*($jd - $j + 0.5)); # round()

    return timegm(0, 0, 0, $day, $month - 1, $year - 1900) + $seconds;
  }
}

=head2 SunCelestialPosition($)

Copyright (c) Plataforma Solar de Almerýa, Spain

simplified algorithm, accurate to within 0.5 minutes of arc for the year 1999-2015

=over

=item * param epoch: epoch time [s], optional, default: now

=item * return array of rightAscension and declination [rad]

=back

=cut

sub SunCelestialPosition($) {
  my ($epoch) = @_;

  # Calculate ecliptic coordinates (ecliptic longitude and obliquity of the
  # ecliptic in radians but without limiting the angle to 2*pi
  # (i.e., the result may be greater than 2*pi)
  my $elapsedDays       = EpochToJulianDate($epoch) - 2451545 + (32.184 + 37)/86400; # 2019: 37 leap seconds
  my $omega             = 2.1429    - 0.0010394594   * $elapsedDays; # [rad]
  my $meanLongitude     = 4.8950630 + 0.017202791698 * $elapsedDays; # [rad]
  my $meanAnomaly       = 6.2400600 + 0.0172019699   * $elapsedDays; # [rad]
  my $eclipticLongitude = $meanLongitude + 0.03341607*sin($meanAnomaly) + 0.00034894*sin(2*$meanAnomaly) - 0.0001134 - 0.0000203*sin($omega);
  my $eclipticObliquity = 0.4090928 - 6.2140e-9*$elapsedDays + 0.0000396*cos($omega);

  # Calculate celestial coordinates (right ascension and declination) in radians
  # but without limiting the angle to 2*pi (i.e., the result may be
  # greater than 2*pi)
  my $sinEclipticLongitude = sin($eclipticLongitude);
  my $y1 = cos($eclipticObliquity)*$sinEclipticLongitude;
  my $x1 = cos($eclipticLongitude);
  my $rightAscension = atan2($y1, $x1);
  if ($rightAscension < 0.0) {
    $rightAscension = $rightAscension + pi2;
  }
  my $declination = asin(sin($eclipticObliquity)*$sinEclipticLongitude);

  return ($rightAscension, $declination);
}

=head2 SunAzimuthElevation(;$$$)

Calculate the azimuth and elevation of the sun for the given time and location.

Copyright (c) Plataforma Solar de Almerýa, Spain

simplified algorithm, accurate to within 0.5 minutes of arc for the year 1999-2015

=over

=item * param epoch: epoch time [s], optional, default: now

=item * param longitude: geographic longitude [deg], optional, default: global longitude or Frankfurt, Germany

=item * param latitude: geographic latitude [deg], optional, default: global latitude or Frankfurt, Germany

=item * return array of azimuth and elevation [deg]

=back

=cut

sub SunAzimuthElevation(;$$$) {
  my ($epoch, $longitudeEast, $latitudeNorth) = @_;

  if (!defined($longitudeEast) || !defined($latitudeNorth)) {
    # undefined: use Frankfurt, Germany
    $longitudeEast = ::AttrVal("global", "longitude", "8.686");
    $latitudeNorth = ::AttrVal("global", "latitude", "50.112");
  }

  my ($rightAscensionRadians, $declinationRadians) = SunCelestialPosition($epoch);

  # Calculate local coordinates (azimuth [deg] and zenith angle [rad])
  my $rad = pi/180;
  my $greenwichMeanSiderealDate = EpochToGreenwichMeanSideralDate($epoch);
  my $localMeanSiderealDateRadians = ($greenwichMeanSiderealDate*15 + $longitudeEast)*$rad;
  my $hourAngleRadians = $localMeanSiderealDateRadians - $rightAscensionRadians;
  my $cosHourAngle = cos($localMeanSiderealDateRadians);
  my $latitudeRadians = $latitudeNorth*$rad;
  my $cosLatitude = cos($latitudeRadians);
  my $sinLatitude = sin($latitudeRadians);
  my $zenithAngle = acos($cosLatitude*$cosHourAngle*cos($declinationRadians) + sin($declinationRadians)*$sinLatitude);
  my $y = -sin($hourAngleRadians);
  my $x = tan($declinationRadians)*$cosLatitude - $sinLatitude*$cosHourAngle;
  my $azimuth = atan2($y, $x);
  if ($azimuth < 0.0) {
    $azimuth = $azimuth + pi2;
  }
  $azimuth = $azimuth/$rad;
  $azimuth = sprintf("%0.1f", $azimuth); # round(1)

  # Parallax correction of zenith angle [deg]
  my $meanEarthRadius = 6371.01; # [km]
  my $astronomicalUnit = 149597890; # [km]
  my $parallax = ($meanEarthRadius/$astronomicalUnit)*sin($zenithAngle);
  $zenithAngle = ($zenithAngle + $parallax)/$rad;

  # Elevation [deg]
  my $elevation = 90 - $zenithAngle;
  $elevation = sprintf("%0.1f", $elevation); # round(1)

  return ($azimuth, $elevation);
}

=head2 Mod($$)

Calculate the arithmetic remainder of a division including fractions.

=cut

sub Mod($$) {
  my ($dividend, $divisor) = @_;
  return 0 if ($divisor == 0);
  return $dividend - int($dividend/$divisor)*$divisor;
}

=head2 SunMeanSolarAnomaly($)

Calculate mean solar anomaly for Julian date.

see https://www.aa.quae.nl/en/reken/zonpositie.html

=over

=item * param jd: Julian date

=item * return mean solar anomaly [deg]

=back

=cut

sub SunMeanSolarAnomaly($) {
  my ($jd) = @_;

  return Mod(357.5291 + 0.98560028*($jd - 2451545), 360);
}

=head2 SunEclipticalLongitude($)

Calculate ecliptical longitude of the sun.

see https://www.aa.quae.nl/en/reken/zonpositie.html

=over

=item * param meanSolarAnomalyRadians: mean solar anomaly [rad]

=item * return ecliptical longitude [rad]

=back

=cut

sub SunEclipticalLongitude($) {
  my ($meanSolarAnomalyRadians) = @_;

  my $rad = pi/180;
  my $equationOfcenter = 1.9148*sin($meanSolarAnomalyRadians) + 0.0200*sin(2*$meanSolarAnomalyRadians) + 0.0003*sin(3*$meanSolarAnomalyRadians);
  return Mod($meanSolarAnomalyRadians/$rad + $equationOfcenter + 180 + 102.9372, 360)*$rad;
}

=head2 SunEquatorialCoordinates($)

Calculate equatorial coordinates of the sun.

see https://www.aa.quae.nl/en/reken/zonpositie.html

=over

=item * param eclipticLongitudeRadians: ecliptic longitude of the sun [rad]

=item * return right ascension and declination [rad]

=back

=cut

sub SunEquatorialCoordinates($) {
  my ($eclipticLongitudeRadians) = @_;

  my $rad = pi/180;
  my $rightAscensionRadians = atan2(sin($eclipticLongitudeRadians)*cos(23.4393*$rad), cos($eclipticLongitudeRadians));
  my $declinationRadians = asin(sin($eclipticLongitudeRadians)*sin(23.4393*$rad));

  return ($rightAscensionRadians, $declinationRadians);
}

=head2 SunEclipticalCoordinates($$$)

Calculate sun hour angle for Julian date.

see https://www.aa.quae.nl/en/reken/zonpositie.html

=over

=item * param jd: Julian date

=item * param rightAscension: right ascension of sun [deg]

=item * param longitudeEast: geographical longitude [deg]

=item * return hour angle of sun [deg], limited to -180 ... +180

=back

=cut

sub SunHourAngle($$$) {
  my ($jd, $rightAscension, $longitudeEast) = @_;

  my $sideralTime = Mod(280.1470 + 360.9856235*($jd - 2451545) + $longitudeEast, 360);
  my $hourAngle = $sideralTime - $rightAscension;
  $hourAngle -= 360 if ($hourAngle > 180);
  $hourAngle += 360 if ($hourAngle < -180);
  return $hourAngle;
}

=head2 SunEclipticalCoordinates($$$)

Calculate solar transit date for Julian date.

see https://en.wikipedia.org/wiki/Sunrise_equation

=over

=item * param jd: Julian date

=item * param meanSolarAnomalyRadians: mean solar anomaly [rad]

=item * param eclipticalLongitudeRadians: ecliptical longitude of sun [rad]

=item * return date of solar transit [Julian date]

=back

=cut

sub SunTransit($$$) {
  my ($jd, $meanSolarAnomalyRadians, $eclipticalLongitudeRadians) = @_;
    
  return $jd + 0.0053*sin($meanSolarAnomalyRadians) - 0.0069*sin(2*$eclipticalLongitudeRadians);
}

=head2 SunElevationCorrection(;$)

Calculate upper solar limb elevation offset angle caused by sun diameter, typical atmospheric refraction and altitude of observer for sunrise.

see https://en.wikipedia.org/wiki/Sunrise_equation

=over

=item * param altitude: altitude of observer [m], optional, default: 0 m

=item * return elevation offset angle of upper solar limb at sunrise [deg]

=back

=cut

sub SunElevationCorrection(;$) {
  my ($altitude) = @_;

  if (!defined($altitude)) {
    # undefined: use 0 m (see level)
    $altitude = 0;
  }

  return -0.83 - 2.076*sqrt($altitude)/60
}

=head2 SunHourAngleOptimization($$$;$$$)

Iteratively improve sun rise (mode = -1), sun transit (mode = 0) and sun set (mode = +1) dates by minimizing hour angle change.

see https://en.wikipedia.org/wiki/Sunrise_equation

=over

=item * param mode: sun rise (mode = -1), sun transit (mode = 0) and sun set (mode = +1)

=item * param jd: estimated Julian date

=item * param longitudeEast: geographical longitude [deg]

=item * param latitudeNorth: geographical latitude [deg], optional, not used for mode = 0

=item * param altitude: altitude of observer [m], optional, not used for mode = 0

=item * param twilightAngle: twilight angle [deg], optional, not used for mode = 0

=item * return array of optimized Julian date and the declination of the sun [rad]

=back

=cut

sub SunHourAngleOptimization($$$;$$$) {
  my ($mode, $jd, $longitudeEast, $latitudeNorth, $altitude, $twilightAngle) = @_;

  # iteratively improve sun rise date
  my $rad = pi/180;
  my $loops = 0;
  my $rightAscensionRadians;
  my $declinationRadians;
  my $hourAngleDelta;
  do {
    # hour angle
    my $meanSolarAnomalyRadians = SunMeanSolarAnomaly($jd)*$rad;
    my $eclipticalLongitudeRadians = SunEclipticalLongitude($meanSolarAnomalyRadians);
    ($rightAscensionRadians, $declinationRadians) = SunEquatorialCoordinates($eclipticalLongitudeRadians);
    my $hourAngle = SunHourAngle($jd, $rightAscensionRadians/$rad, $longitudeEast);

    if ($mode) {
      # sun rise/set hour angle
      my $hourAngleRiseSet = acos((sin((SunElevationCorrection($altitude) + $twilightAngle)*$rad) - sin($latitudeNorth*$rad)*sin($declinationRadians))/(cos($latitudeNorth*$rad)*cos($declinationRadians)))/$rad;

      # improved sun rise/set date
      $hourAngleDelta = $hourAngle - $mode*$hourAngleRiseSet;
      $jd -= $hourAngleDelta/360;

      #::Log3 "", 3, "SunRiseSetOptimization meanSolarAnomaly ". $meanSolarAnomalyRadians/$rad . " eclipticalLongitude " . $eclipticalLongitudeRadians/$rad . " rightAscensionRadians " . $rightAscensionRadians/$rad . " declinationRadians " . $declinationRadians/$rad . " jd $jd hourAngle $hourAngle hourAngleRiseSet $hourAngleRiseSet hourAngleDelta $hourAngleDelta" . JulianDateToEpoch($jd);
    } else {
      # improved solar transit date
      $hourAngleDelta = $hourAngle;
      $jd -= $hourAngleDelta/360;

      #::Log3 "", 3, "SunRiseSetOptimization meanSolarAnomaly ". $meanSolarAnomalyRadians/$rad . " eclipticalLongitude " . $eclipticalLongitudeRadians/$rad . " rightAscensionRadians " . $rightAscensionRadians/$rad . " declinationRadians " . $declinationRadians/$rad . " jd $jd hourAngle $hourAngle " . JulianDateToEpoch($jd);
    }
    $loops++;
  } while (abs($hourAngleDelta) > 0.0005 && $loops < 5);

  return ($jd, $declinationRadians);
}

=head2 SunRiseSet(;$$$$$)

Calculate time of sunrise, sun transit and sunset for given time and position including corrections for astronomical refraction, solar disc diameter and altitude of observer.

see https://www.aa.quae.nl/en/reken/zonpositie.html
see https://en.wikipedia.org/wiki/Sunrise_equation

Note: The calculated times belong to the day in the GMT timezone. If your location is in a different timezone you must add your timezone offset to the epoch time to get the same result for all times between 0:00 and 23:59 of your local time.

Adjust epoch time by time zone offset

=over

=item * param epoch: epoch time [s], optional, default: now

=item * param longitudeEast: geographic longitude [deg], optional, default: global longitude or Frankfurt, Germany

=item * param latitude: geographic latitude [deg], optional, default: global latitude or Frankfurt, Germany

=item * param altitude: altitude of obeserver [m], optional, default: 0 m

=item * param twilightAngle: twilight angle [deg], optional, default: 0 °

=item * return array of sunrise, sun transit and sunset date for a day in the GMT timezone [epoch]

=back

=cut

sub SunRiseSet(;$$$$$) {
  my ($epoch, $longitudeEast, $latitudeNorth, $altitude, $twilightAngle) = @_;

  if (!defined($epoch)) {
    $epoch = time();
  }

  if (!defined($longitudeEast) || !defined($latitudeNorth)) {
    # undefined: use Frankfurt, Germany
    $longitudeEast = ::AttrVal("global", "longitude", "8.686");
    $latitudeNorth = ::AttrVal("global", "latitude", "50.112");
  }
  #$longitudeEast = 5;
  #$latitudeNorth = 52;

  if (!defined($altitude)) {
    # undefined: use 0 m (see level)
    $altitude = 0;
  }
  #$altitude = 0;

  if (!defined($twilightAngle)) {
    # undefined: use 0°
    $twilightAngle = 0;
  }
  #$twilightAngle = 0;

  # initial estimate of solar transit date
  my $julianDateOffset = 2451545 + (32.184 + 37)/86400 - $longitudeEast/360; # 2019: 37 leap seconds
  my $julianCycle = floor(EpochToJulianDate($epoch) - $julianDateOffset + 0.5);
  #$julianCycle = floor(2453097 - $julianDateOffset + 0.5);
  my $solarTransitJD = $julianCycle + $julianDateOffset;

  # improve estimate of solar transit date
  my $rad = pi/180;
  my $meanSolarAnomalyRadians = SunMeanSolarAnomaly($solarTransitJD)*$rad;
  my $eclipticalLongitudeRadians = SunEclipticalLongitude($meanSolarAnomalyRadians);
  $solarTransitJD = SunTransit($solarTransitJD, $meanSolarAnomalyRadians, $eclipticalLongitudeRadians);

  # iteratively improve solar transit date at given longitude
  ($solarTransitJD, my $declinationRadians) = SunHourAngleOptimization(0, $solarTransitJD, $longitudeEast);
  
  # initial estimate of sun rise/set hour angle at given latitude and altitude
  my $hourAngleRiseSet = acos((sin((SunElevationCorrection($altitude) + $twilightAngle)*$rad) - sin($latitudeNorth*$rad)*sin($declinationRadians))/(cos($latitudeNorth*$rad)*cos($declinationRadians)))/$rad;
  my $hourAngleRiseSetRatio = $hourAngleRiseSet/360;

  # initial estimate of sun rise and sun set date
  my $sunRiseJD = $solarTransitJD - $hourAngleRiseSetRatio;
  my $sunSetJD = $solarTransitJD + $hourAngleRiseSetRatio;

  # iteratively improve sun rise and sun set date
  ($sunRiseJD) = SunHourAngleOptimization(-1, $sunRiseJD, $longitudeEast, $latitudeNorth, $altitude, $twilightAngle);
  ($sunSetJD) = SunHourAngleOptimization(+1, $sunSetJD, $longitudeEast, $latitudeNorth, $altitude, $twilightAngle);

  #::Log3 "", 3, "SunRiseSet: sunRiseJD $sunRiseJD solarTransitJD $solarTransitJD sunSetJD $sunSetJD";

  return (JulianDateToEpoch($sunRiseJD), JulianDateToEpoch($solarTransitJD), JulianDateToEpoch($sunSetJD));
}

=head2 RotateForecast($$;$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param station: station name, string

=item * param today: epoch of today 00:00, optional

=item * return count of available forecast days

=back

=cut

sub RotateForecast($$;$)
{
  my ($hash, $station, $today) = @_;
  my $name = $hash->{NAME};

  my $daysAvailable = 0;
  while (defined(::ReadingsVal($name, 'fc'.$daysAvailable.'_date', undef))) {
    $daysAvailable++;
  }
  ::Log3 $name, 5, "$name: RotateForecast: $daysAvailable days exist with readings";

  my $oT = ::ReadingsVal($name, 'fc0_date', undef);
  my $oldToday = defined($oT)? ParseDateLocal($hash, $oT) : undef;

  my $stationChanged = ::ReadingsVal($name, 'fc_station', '') ne $station;
  if ($stationChanged) {
    # different station, delete all existing readings
    ::CommandDeleteReading(undef, "$name ^fc.*");
    $daysAvailable = 0;
  } elsif (defined($oldToday)) {
    # same station, shift existing readings
    if (!defined($today)) {
      my $time = time();
      my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = Localtime($hash, $time);
      $today = Timelocal($hash, 0, 0, 0, $tMday, $tMon, $tYear);
    }

    my $daysForward = sprintf("%0.0f", ($today - $oldToday)/86400.0);  # round() [s] -> [d]
    ::Log3 $name, 5, "$name: RotateForecast: shifting forward by $daysForward day(s) ($oldToday -> $today)";
    if ($daysForward > 0) {
      # different day
      if ($daysForward < $daysAvailable) {
        my @shiftProperties = ( 'date', 'weekday' );
        my $forecastResolution = ::AttrVal($name, 'forecastResolution', 6);
        while (my($property, $period) = each %forecastPropertyPeriods) {
          if ($period == 24) {
            push(@shiftProperties, $property);
          } else {
            for (my $s=0; $s<24/$forecastResolution; $s++) {
              push(@shiftProperties, $s.'_'.$property);
            }
          }
        }
        for (my $s=0; $s<24/$forecastResolution; $s++) {
          push(@shiftProperties, $s.'_time');
          push(@shiftProperties, $s.'_wwd');
        }
        # shift readings forward by days
        for (my $d=0; $d<($daysAvailable - $daysForward); $d++) {
          my $sourcePrefix = 'fc'.($daysForward + $d).'_';
          my $destinationPrefix = 'fc'.$d.'_';
          foreach my $property (@shiftProperties) {
            my $value = ::ReadingsVal($name, $sourcePrefix.$property, undef);
            if (defined($value)) {
              ::readingsBulkUpdate($hash, $destinationPrefix.$property, $value);
            } else {
              ::CommandDeleteReading(undef, $destinationPrefix.$property);
            }
          }
        }
        # delete existing readings of all days that have not been written
        for (my $d=($daysAvailable - $daysForward); $d<$daysAvailable; $d++) {
          ::CommandDeleteReading(undef, "$name ^fc".$d."_.*");
        }
        $daysAvailable -= $daysForward;
      } else {
        # nothing remains after shifting, delete existing day readings
        ::CommandDeleteReading(undef, "$name ^fc\\d+.*");
        $daysAvailable = 0;
      }
    }
  }

  return $daysAvailable;
}

sub ProcessForecast($$$);

=head2 GetForecast($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param station: station name, string

=back

=cut

sub GetForecast($$)
{
  my ($hash, $station) = @_;
  my $name = $hash->{NAME};

  if (!::IsDisabled($name)) {
    ::Log3 $name, 5, "$name: GetForecast START (PID $$)";

    # test if XML module is available
    eval {
      require XML::LibXML;
    };
    if ($@) {
      return "$name: Perl module XML::LibXML not found, see commandref for details how to fix";
    }

    # download, unzip and parse using BlockingCall
    if (defined($hash->{".forecastFile"})) {
      # delete old temp file
      close($hash->{".forecastFileHandle"});
      unlink($hash->{".forecastFile"});
    }
    ($hash->{".forecastFileHandle"}, $hash->{".forecastFile"}) = tempfile(UNLINK => 1);
    $hash->{".station"} = $station;
    if (defined($hash->{".forecastBlockingCall"})) {
      # kill old blocking call
      ::BlockingKill($hash->{".forecastBlockingCall"});
    }
    $hash->{".forecastBlockingCall"} = ::BlockingCall("DWD_OpenData::GetForecastStart", $hash, "DWD_OpenData::GetForecastFinish", 30, "DWD_OpenData::GetForecastAbort", $hash);

    $hash->{forecastUpdating} = time();

    ::readingsSingleUpdate($hash, 'state', 'updating forecasts', 1);

    ::Log3 $name, 5, "$name: GetForecast END";
    return undef;
  } else {
    return "disabled";
  }
}

=head2 GetForecastStart($)

BlockingCall I<BlockingFn> callback

=over

=item * param hash: hash of DWD_OpenData device

=item * return result required by function L</GetForecastFinish(@)>

=back

ATTENTION: This method is executed in a different process than FHEM.
           The device hash is from the time of the process initiation.
           Any changes to the device hash or readings are not visible
           in FHEM.

=cut

sub GetForecastStart($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $station = $hash->{".station"};

  # give main process time to execute
  usleep(100);

  # get forecast for station from DWD server
  my $url = 'https://opendata.dwd.de/weather/local_forecasts/mos/MOSMIX_L/single_stations/' . $station . '/kml/MOSMIX_L_LATEST_' . $station . '.kmz ';
  my $param = {
                url        => $url,
                method     => "GET",
                timeout    => 10,
                hash       => $hash,
                station    => $station
              };
  ::Log3 $name, 5, "$name: GetForecastStart START (PID $$): $url";
  my ($httpError, $fileContent) = ::HttpUtils_BlockingGet($param);

  # process retrieved data
  my $result = ProcessForecast($param, $httpError, $fileContent);

  ::Log3 $name, 5, "$name: GetForecastStart END";

  return $result;
}

=head2 ProcessForecast($$$)

=over

=item * param param: parameter hash from call to HttpUtils_NonblockingGet

=item * param httpError: nothing or HTTP error string

=item * param fileContent: data retrieved from URL

=item * return C<undef> on success or error message

=back

ATTENTION: This method is executed in a different process than FHEM.
           The device hash is from the time of the process initiation.
           Any changes to the device hash or readings are not visible
           in FHEM.

=cut

sub ProcessForecast($$$)
{
  my ($param, $httpError, $fileContent) = @_;
  my $hash    = $param->{hash};
  my $name    = $hash->{NAME};
  my $url     = $param->{url};
  my $code    = $param->{code};
  my $station = $param->{station};

  ::Log3 $name, 5, "$name: ProcessForecast START";

  my %forecast;
  my $relativeDay = 0;
  my @coordinates;
  eval {
    if (defined($httpError) && length($httpError) > 0) {
      die "error retrieving URL '$url': $httpError";
    }
    if (defined($code) && $code != 200) {
      die "HTTP error $code retrieving URL '$url'";
    }
    if (!defined($fileContent) || length($fileContent) == 0) {
      die "no data retrieved from URL '$url'";
    }

    ::Log3 $name, 5, "$name: ProcessForecast: data received, decoding ...";

    # prepare processing
    my $forecastProperties = ::AttrVal($name, 'forecastProperties', undef);
    my @properties = split(',', $forecastProperties) if (defined($forecastProperties));
    my %selectedProperties;
    if (!@properties) {
      # no selection: use defaults
      %selectedProperties = %forecastDefaultProperties;
    } else {
      # use selected properties
      foreach my $property (@properties) {
        $property =~ s/^\s+|\s+$//g; # trim
        $selectedProperties{$property} = 1;
      }
    }

    # create memory mapped file from received data and unzip
    open my $zipFileHandle, '<', \$fileContent;
    my @xmlStrings;
    unzip($zipFileHandle => \@xmlStrings, MultiStream => 1) or die "unzip failed: $UnzipError\n";

    my %header;
    $header{station} = $station;

    # parse XML strings (files from zip)
    foreach my $xmlString (@xmlStrings) {
      if (substr(${$xmlString}, 0, 2) eq 'PK') {
        # empty string, skip
        next;
      }

      # parse XML string
      ::Log3 $name, 5, "$name: ProcessForecast: parsing XML document";
      my $dom = XML::LibXML->load_xml(string => $xmlString);
      if (!$dom) {
        die "parsing XML failed";
      }

      ::Log3 $name, 5, "$name: ProcessForecast: extracting data";

      # extract header data
      my @timestamps;
      my $issuer = undef;
      my $defaultUndefSign = '-';
      my $productDefinitionNodeList = $dom->getElementsByLocalName('ProductDefinition');
      if ($productDefinitionNodeList->size()) {
        my $productDefinitionNode = $productDefinitionNodeList->get_node(1);
        foreach my $productDefinitionChildNode ($productDefinitionNode->nonBlankChildNodes()) {
          if ($productDefinitionChildNode->nodeName() eq 'dwd:Issuer') {
            $issuer = $productDefinitionChildNode->textContent();
            $header{copyright} = "Datenbasis: $issuer";
          } elsif ($productDefinitionChildNode->nodeName() eq 'dwd:IssueTime') {
            my $issueTime = $productDefinitionChildNode->textContent();
            $header{time} = FormatDateTimeLocal($hash, ParseKMLTime($issueTime));
          } elsif ($productDefinitionChildNode->nodeName() eq 'dwd:ForecastTimeSteps') {
            foreach my $forecastTimeStepsChildNode ($productDefinitionChildNode->nonBlankChildNodes()) {
              if ($forecastTimeStepsChildNode->nodeName() eq 'dwd:TimeStep') {
                my $forecastTimeSteps = $forecastTimeStepsChildNode->textContent();
                push(@timestamps, ParseKMLTime($forecastTimeSteps));
              }
            }
          } elsif ($productDefinitionChildNode->nodeName() eq 'dwd:FormatCfg') {
            foreach my $formatCfgChildNode ($productDefinitionChildNode->nonBlankChildNodes()) {
              if ($formatCfgChildNode->nodeName() eq 'dwd:DefaultUndefSign') {
                $defaultUndefSign = $formatCfgChildNode->textContent();
              }
            }
          }
        }
      }
      $forecast{timestamps} = \@timestamps;
      $header{defaultUndefSign} = $defaultUndefSign;

      if (!defined($issuer)) {
        die "error in XML data, forecast issuer not found";
      }

      # extract time data
      my %timeProperties;
      my ($longitude, $latitude, $altitude);
      my $placemarkNodeList = $dom->getElementsByLocalName('Placemark');
      if ($placemarkNodeList->size()) {
        my $placemarkNode = $placemarkNodeList->get_node(1);
        foreach my $placemarkChildNode ($placemarkNode->nonBlankChildNodes()) {
          if ($placemarkChildNode->nodeName() eq 'kml:description') {
            my $description = $placemarkChildNode->textContent();
            $header{description} = encode('UTF-8', $description);
          } elsif ($placemarkChildNode->nodeName() eq 'kml:ExtendedData') {
            foreach my $extendedDataChildNode ($placemarkChildNode->nonBlankChildNodes()) {
              if ($extendedDataChildNode->nodeName() eq 'dwd:Forecast') {
                my $elementName = $extendedDataChildNode->getAttribute('dwd:elementName');
                # convert some elements names for backward compatibility
                my $alias = $forecastPropertyAliases{$elementName};
                if (defined($alias)) { $elementName = $alias };
                my $selectedProperty = $selectedProperties{$elementName};
                if (defined($selectedProperty)) {
                  my $textContent = $extendedDataChildNode->nonBlankChildNodes()->get_node(1)->textContent();
                  $textContent =~ s/^\s+|\s+$//g; # trim outside
                  $textContent =~ s/\s+/ /g; # trim inside
                  my @values = split(' ', $textContent);
                  $timeProperties{$elementName} = \@values;
                }
              }
            }
          } elsif ($placemarkChildNode->nodeName() eq 'kml:Point') {
            my $coordinates = $placemarkChildNode->nonBlankChildNodes()->get_node(1)->textContent();
            $header{coordinates} = $coordinates;
            ($longitude, $latitude, $altitude) = split(',', $coordinates);
          }
        }
      }

      # calculate sun position dependent properties for each timestamp
      if (defined($longitude) && defined($latitude) && defined($altitude)) {
        my @azimuths;
        my @elevations;
        my @sunups;
        my @sunrises;
        my @sunsets;
        my $lastDate = '';
        my $sunElevationCorrection = SunElevationCorrection($altitude);
        foreach my $timestamp (@timestamps) {
          my ($azimuth, $elevation) = SunAzimuthElevation($timestamp, $longitude, $latitude);
          push(@azimuths, $azimuth);     # [deg]
          push(@elevations, $elevation); # [deg]
          push(@sunups, $elevation >= $sunElevationCorrection? 1 : 0);
          my $date = FormatDateLocal($hash, $timestamp);
          if ($date ne $lastDate) {
            # one calculation per day
            my ($rise, $transit, $set) = SunRiseSet($timestamp + LocaltimeOffset($hash, $timestamp), $longitude, $latitude, $altitude);
            push(@sunrises, FormatTimeLocal($hash, $rise));    # round down to current minute
            push(@sunsets, FormatTimeLocal($hash, $set + 30)); # round up to next minute
            $lastDate = $date;
            
            #::Log3 $name, 3, "$name: ProcessForecast " . FormatDateTimeLocal($hash, $timestamp) . " $rise " . FormatDateTimeLocal($hash, $rise) . " $transit " . FormatDateTimeLocal($hash, $transit). " $set " . FormatDateTimeLocal($hash, $set + 30);            
          } else {
            push(@sunrises, $defaultUndefSign); # round down to current minute
            push(@sunsets, $defaultUndefSign);  # round up to next minute
          }
        }
        if (defined($selectedProperties{SunAz})) {
          $timeProperties{SunAz} = \@azimuths;
        }
        if (defined($selectedProperties{SunEl})) {
          $timeProperties{SunEl} = \@elevations;
        }
        if (defined($selectedProperties{SunUp})) {
          $timeProperties{SunUp} = \@sunups;
        }
        if (defined($selectedProperties{SunRise})) {
          $timeProperties{SunRise} = \@sunrises;
        }
        if (defined($selectedProperties{SunSet})) {
          $timeProperties{SunSet} = \@sunsets;
        }
      }

      $forecast{timeProperties} = \%timeProperties;
    }
    $forecast{header} = \%header;
  };

  my $errorMessage = '';
  if ($@) {
    # exception
    my @parts = split(/ at |\n/, $@); # discard anything after " at " or newline
    if (@parts) {
      $errorMessage = $parts[0];
      ::Log3 $name, 4, "$name: ProcessForecast error: $parts[0]";
    } else {
      $errorMessage = $@;
      ::Log3 $name, 4, "$name: ProcessForecast error: $@";
    }
  } else {
    # forecast parsed successfully
    if (defined($hash->{".forecastFile"})) {
      if (open(my $file, ">", $hash->{".forecastFile"})) {
        # write forecast to temp file
        binmode($file);
        my $frozenForecast = freeze(\%forecast);
        ::Log3 $name, 5, "$name: ProcessForecast temp file " . $hash->{".forecastFile"} . " forecast " . keys(%forecast) . " size " . length($frozenForecast);
        print($file $frozenForecast);
        close($file);
      } else {
        $errorMessage = $!;
        ::Log3 $name, 3, "$name: ProcessForecast error opening temp file: $errorMessage";
      }
    } else {
      $errorMessage = 'result file name not defined';
      ::Log3 $name, 3, "$name: ProcessForecast error: temp file name not defined";
    }
  }

  # get rid of newlines and commas because of Blocking InformFn parameter restrictions
  $errorMessage =~ s/\n/; /g;
  $errorMessage =~ s/,/;/g;

  ::Log3 $name, 5, "$name: ProcessForecast END";

  return [$name, $errorMessage];
}

=head2 GetForecastFinish(@)

BlockingCall I<FinishFn> callback, expects array returned by function L</GetForecastStart($)> as single parameter

=over

=item * param name: name of DWD_OpenData device

=item * param errorMessage: empty string or processing error message

=back

=cut

sub GetForecastFinish(@)
{
  my ($name, $errorMessage) = @_;

  if (defined($name)) {
    ::Log3 $name, 5, "$name: GetForecastFinish START (PID $$)";

    my $hash = $::defs{$name};
    delete $hash->{".forecastBlockingCall"};
    delete $hash->{forecastUpdating};

    if (defined($errorMessage) && length($errorMessage) > 0) {
      # error, skip further processing
    } elsif (!defined($hash->{".forecastFile"})) {
      $errorMessage = "internal temp file name missing";
      ::Log3 $name, 3, "$name: GetForecastFinish error: $errorMessage";
    } else {
      # deserialize forecast
      my $fh = $hash->{".forecastFileHandle"};
      my $terminator = $/;
      $/ = undef;        # enable slurp file read mode
      my $frozenForecast = <$fh>;
      $/ = $terminator;  # restore default file read mode
      close($hash->{".forecastFileHandle"});
      unlink($hash->{".forecastFile"});
      my %newForecast = %{thaw($frozenForecast)};
      ::Log3 $name, 5, "$name: GetForecastFinish temp file " . $hash->{".forecastFile"} . " forecast " . keys(%newForecast) . " size " . length($frozenForecast);
      delete($hash->{".forecastFile"});

      UpdateForecast($hash, \%newForecast);
    }

    if (defined($errorMessage) && length($errorMessage) > 0) {
      ::readingsSingleUpdate($hash, 'state', "forecast error: $errorMessage", 1);
      ::readingsSingleUpdate($hash, 'fc_state', "error: $errorMessage", 1);
    } else {
      ::readingsSingleUpdate($hash, 'fc_state', 'updated', 1);
    }

    if (defined($hash->{".fetchAlerts"}) && !$hash->{".fetchAlerts"}) {
      # get forecast was initiated by timer, reschedule to fetch alerts
      $hash->{".fetchAlerts"} = 1;
      ::InternalTimer(gettimeofday() + 1, 'DWD_OpenData::Timer', $hash);
    }

    ::Log3 $name, 5, "$name: GetForecastFinish END";
  } else {
    ::Log 3, "GetForecastFinish error: device name missing";
  }
}

=head2 GetForecastAbort($)

BlockingCall I<AbortFn> callback

=over

=item * param hash: hash of DWD_OpenData device

=back

=cut

sub GetForecastAbort($)
{
  my ($hash, $errorMessage) = @_;
  my $name = $hash->{NAME};
  my $station = $hash->{".station"};

  delete $hash->{".forecastBlockingCall"};
  delete $hash->{forecastUpdating};
  $errorMessage = "downloading and processing weather forecast data failed ($errorMessage)";
  ::Log3 $name, 3, "$name: GetForecastAbort error: $errorMessage";
  ::readingsSingleUpdate($hash, 'state', "forecast error: $errorMessage", 1);
  ::readingsSingleUpdate($hash, 'fc_state', "error: $errorMessage", 1);

  # rotate forecast anyway
  ::readingsBeginUpdate($hash);
  RotateForecast($hash, $station);
  ::readingsEndUpdate($hash, 1);

  if (defined($hash->{".fetchAlerts"}) && !$hash->{".fetchAlerts"}) {
    # get forecast was initiated by timer, reschedule to fetch alerts
    $hash->{".fetchAlerts"} = 1;
    ::InternalTimer(gettimeofday() + 1, 'DWD_OpenData::Timer', $hash);
  }
}

=head2 UpdateForecast($$)

update forecast readings

=over

=item * param hash: hash of DWD_OpenData device

=item * param forecast: hash ref to forecast data

=item * return C<undef> or error message

=back

=cut

sub UpdateForecast($$)
{
  my ($hash, $forecast) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 5, "$name: UpdateForecast: START";

  ::readingsBeginUpdate($hash);

  # preprocess existing time readings
  my $time = time();
  my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = Localtime($hash, $time);
  my $today = Timelocal($hash, 0, 0, 0, $tMday, $tMon, $tYear);
  my $station = $forecast->{header}{station};
  my $daysAvailable = RotateForecast($hash, $station, $today);

  # create header readings
  my $defaultUndefSign = $forecast->{header}{defaultUndefSign};
  delete $forecast->{header}{defaultUndefSign};
  while (my ($property, $value) = each %{$forecast->{header}})
  {
    ::readingsBulkUpdate($hash, 'fc_'.$property, $value);
  }

  # prepare time processing
  my $forecastWW2Text = ::AttrVal($name, 'forecastWW2Text', 0);
  my $forecastDays = ::AttrVal($name, 'forecastDays', 6);
  my $forecastResolution = ::AttrVal($name, 'forecastResolution', 6);

  # create time readings
  my $lastDayPrefix = '';
  my $relativeDay = -1;
  my $timestamps = $forecast->{timestamps};
  for my $i (0 .. $#$timestamps) {
    # analyse date relation between forecast and today
    my $forecastTime = $timestamps->[$i];
    my ($fcSec, $fcMin, $fcHour, $fcMday, $fcMon, $fcYear, $fcWday, $fcYday, $fcIsdst) = Localtime($hash, $forecastTime);
    my $forecastDate = Timelocal($hash, 0, 0, 0, $fcMday, $fcMon, $fcYear);
    $relativeDay = sprintf("%.0f", ($forecastDate - $today)/(24*60*60)); # round()
    if ($relativeDay > $forecastDays) {
      # max. number of days processed, done
      last;
    }
    if ($relativeDay < 0) {
      # forecast is older than today, skip
      next;
    }
    # write data
    my $dayPrefix = 'fc'.$relativeDay.'_';
    if ($dayPrefix ne $lastDayPrefix) {
      ::readingsBulkUpdate($hash, $dayPrefix.'date', FormatDateLocal($hash, $forecastTime));
      ::readingsBulkUpdate($hash, $dayPrefix.'weekday', FormatWeekdayLocal($hash, $forecastTime));
      $lastDayPrefix = $dayPrefix;
    }
    # some values are only available every 3, 6 or 12 hours relative to 00:00 UTC
    my $hourPrefix = undef;
    my $fcHourUTC = (gmtime($forecastTime))[2];
    #::Log3 $name, 5, "$name: fcHourUTC $fcHourUTC";
    if ($fcHourUTC%$forecastResolution == 0) {
      $hourPrefix = int($fcHour/$forecastResolution).'_';
      #::Log3 $name, 5, "$name: hourPrefix $hourPrefix";
      ::readingsBulkUpdate($hash, $dayPrefix.$hourPrefix.'time', FormatTimeLocal($hash, $forecastTime));
    }
    while (my($property, $values) = each %{$forecast->{timeProperties}}) {
      #::Log3 $name, 5, "$name: $property  vs=" . scalar(@$values) . " ts=" . $#$timestamps . " -> " . $values->[$i];
      if (defined($values->[$i])) {
        my $value = $values->[$i];
        if ($value ne $defaultUndefSign) {
          $value =~ s/,/./g; # decimal point
          my $forecastPropertyType = $forecastPropertyTypes{$property};
          if (defined($forecastPropertyType)) {
            if ($forecastPropertyType == 1) {
              $value -= 273.15; # K -> °C
              if (length($value) > 6) {
                $value = sprintf('%0.2f', $value); # round(2) to compensate floating point granularity
              }
            }
            elsif ($forecastPropertyType == 2) {
              $value = sprintf('%0.0f', $value); # round()
              if ($forecastWW2Text && ($property eq 'ww') && defined($hourPrefix) && length($value) > 0) {
                ::readingsBulkUpdate($hash, $dayPrefix.$hourPrefix.'wwd', $wwdText[$value]);
              }
            }
            elsif ($forecastPropertyType == 3) {
              $value *= 3.6; # m/s -> km/h
              $value = sprintf('%0.0f', $value); # round()
            }
            elsif ($forecastPropertyType == 4) {
              $value /= 100; # Pa -> hPa
              $value = sprintf('%0.1f', $value); # round(1)
            }
          }
          #::Log3 $name, 5, "$name: $fcHour $dayPrefix $hourPrefix | $property -> $value | $forecastPropertyType";
          my $forecastPropertyPeriod = $forecastPropertyPeriods{$property};
          if ($forecastPropertyPeriod == 24) {
            # day property
            ::readingsBulkUpdate($hash, $dayPrefix.$property, $value);
          } elsif (defined($hourPrefix)) {
            # hour property
            ::readingsBulkUpdate($hash, $dayPrefix.$hourPrefix.$property, $value);
          }
        }
      }
    }
  }

  # delete existing time readings of all days that have not been written
  if ($relativeDay >= 0 && $daysAvailable > $relativeDay + 1) {
    ::Log3 $name, 5, "$name: deleting days with index " . ($relativeDay + 1) . " to " . ($daysAvailable - 1);
    for (my $d=($relativeDay + 1); $d<$daysAvailable; $d++) {
      ::CommandDeleteReading(undef, "$name ^fc".$d."_.*");
    }
  }

  ::readingsBulkUpdate($hash, 'state', 'forecast updated');
  ::readingsEndUpdate($hash, 1);

  ::Log3 $name, 5, "$name: UpdateForecast: END";

  return undef;
}

=head2 GetAlerts($$)

=over

=item * param hash: hash of DWD_OpenData device

=item * param warncellId: numeric id of warncell, may also be C<UPDATE_DISTRICTS>, C<UPDATE_COMMUNEUNIONS> or C<UPDATE_ALL>

=back

=cut

sub GetAlerts($$)
{
  my ($hash, $warncellId) = @_;
  my $name = $hash->{NAME};

  if (!::IsDisabled($name)) {
    ::Log3 $name, 5, "$name: GetAlerts START (PID $$)";

    # test if XML module is available
    eval {
      require XML::LibXML;
    };
    if ($@) {
      return "$name: Perl module XML::LibXML not found, see commandref for details how to fix";
    }

    # @todo delete expired alerts?

    # download, unzip and parse using BlockingCall
    my $communeUnion = IsCommuneUnionWarncellId($warncellId);
    if (defined($hash->{".alertsFile".$communeUnion})) {
      # delete old temp file
      close($hash->{".alertsFileHandle".$communeUnion});
      unlink($hash->{".alertsFile".$communeUnion});
    }
    ($hash->{".alertsFileHandle".$communeUnion}, $hash->{".alertsFile".$communeUnion}) = tempfile(UNLINK => 1);
    $hash->{".warncellId"} = $warncellId;
    if (defined($hash->{".alertsBlockingCall".$communeUnion})) {
      # kill old blocking call
      ::BlockingKill($hash->{".alertsBlockingCall".$communeUnion});
    }
    $hash->{".alertsBlockingCall".$communeUnion} = ::BlockingCall("DWD_OpenData::GetAlertsStart", $hash, "DWD_OpenData::GetAlertsFinish", 60, "DWD_OpenData::GetAlertsAbort", $hash);

    $alertsUpdating[$communeUnion] = time();

    ::readingsSingleUpdate($hash, 'state', 'updating alerts cache', 1);

    ::Log3 $name, 5, "$name: GetAlerts END";
    return undef;
  } else {
    return "disabled";
  }
}

sub ProcessAlerts($$$);

=head2 GetAlertsStart($)

BlockingCall I<BlockingFn> callback

=over

=item * param hash: hash of DWD_OpenData device

=item * return result required by function L</GetAlertsFinish(@)>

=back

ATTENTION: This method is executed in a different process than FHEM.
           The device hash is from the time of the process initiation.
           Any changes to the device hash or readings are not visible
           in FHEM.

=cut

sub GetAlertsStart($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $warncellId = $hash->{".warncellId"};

  # give main process time to execute
  usleep(100);

  # get communion (5, 7, 8) or district (1, 9) alerts for Germany from DWD server
  my $communeUnion = IsCommuneUnionWarncellId($warncellId);
  my $alertLanguage = ::AttrVal($name, 'alertLanguage', 'DE');
  my $url = 'https://opendata.dwd.de/weather/alerts/cap/'.($communeUnion? 'COMMUNEUNION' : 'DISTRICT').'_CELLS_STAT/Z_CAP_C_EDZW_LATEST_PVW_STATUS_PREMIUMCELLS_'.($communeUnion? 'COMMUNEUNION' : 'DISTRICT').'_'.$alertLanguage.'.zip';
  my $param = {
                url        => $url,
                method     => "GET",
                timeout    => 30,
                hash       => $hash,
                warncellId => $warncellId
              };
  ::Log3 $name, 5, "$name: GetAlertsStart START (PID $$): $url";
  my ($httpError, $fileContent) = ::HttpUtils_BlockingGet($param);

  # process retrieved data
  my $result = ProcessAlerts($param, $httpError, $fileContent);

  ::Log3 $name, 5, "$name: GetAlertsStart END";

  return $result;
}

=head2 ProcessAlerts($$$)

=over

=item * param hash: hash of DWD_OpenData device

=item * return result required by function L</GetAlertsFinish(@)>

=back

ATTENTION: This method is executed in a different process than FHEM.
           The device hash is from the time of the process initiation.
           Any changes to the device hash or readings are not visible
           in FHEM.

=cut

sub ProcessAlerts($$$)
{
  my ($param, $httpError, $fileContent) = @_;
  my $time       = time();
  my $hash       = $param->{hash};
  my $name       = $hash->{NAME};
  my $url        = $param->{url};
  my $code       = $param->{code};
  my $warncellId = $param->{warncellId};

  ::Log3 $name, 5, "$name: ProcessAlerts START (PID $$)";

  my %alerts;
  eval {
    if (defined($httpError) && length($httpError) > 0) {
      die "error retrieving URL '$url': $httpError";
    }
    if (defined($code) && $code != 200) {
      die "HTTP error $code retrieving URL '$url'";
    }
    if (!defined($fileContent) || length($fileContent) == 0) {
      die "no data retrieved from URL '$url'";
    }

    ::Log3 $name, 5, "$name: ProcessAlerts: data received";

    # create memory mapped file from received data and unzip
    open my $zipFileHandle, '<', \$fileContent;
    my @xmlStrings;
    unzip($zipFileHandle => \@xmlStrings, MultiStream => 1) or die "error unzipping data: $UnzipError\n";

    # parse XML strings
    foreach my $xmlString (@xmlStrings) {
      if (substr(${$xmlString}, 0, 2) eq 'PK') {
        # empty string, skip
        next;
      }
      # parse XML string
      ::Log3 $name, 5, "$name: ProcessAlerts: parsing XML document";
      my $dom = XML::LibXML->load_xml(string => $xmlString);
      if (!$dom) {
        die "error parsing XML data";
      }
      my $xpc = XML::LibXML::XPathContext->new($dom);
      $xpc->registerNs('cap', 'urn:oasis:names:tc:emergency:cap:1.2');
      my $alert = {};
      my $alertNode = $dom->documentElement();
      foreach my $alertChildNode ($alertNode->nonBlankChildNodes()) {
        #::Log3 $name, 5, "$name: ProcessAlerts child node: " . $alertChildNode->nodeName();
        if ($alertChildNode->nodeName() eq 'identifier') {
          $alert->{identifier} = $alertChildNode->textContent();
          #::Log3 $name, 5, "$name: ProcessAlerts identifier: " . $alert->{identifier};
        } elsif ($alertChildNode->nodeName() eq 'status') {
          $alert->{status} = $alertChildNode->textContent();
        } elsif ($alertChildNode->nodeName() eq 'msgType') {
          $alert->{msgType} = $alertChildNode->textContent();
        } elsif ($alertChildNode->nodeName() eq 'references') {
          # get list of references, separated by whitespace, each reference consisting of 3 parts: sender, identifier, sent
          $alert->{references} = [];
          my @references = split(' ', $alertChildNode->textContent());
          foreach my $reference (@references) {
            my @parts = split(',', $reference);
            if (scalar(@parts) == 3) {
              push(@{$alert->{references}}, $parts[2]);
            }
          }
        } elsif ($alertChildNode->nodeName() eq 'info') {
          foreach my $infoChildNode ($alertChildNode->nonBlankChildNodes()) {
            #::Log3 $name, 5, "$name: ProcessAlerts child node: '" . $infoChildNode->nodeName() . "'";
            if ($infoChildNode->nodeName() eq 'category') {
              $alert->{category} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'event') {
              $alert->{event} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'responseType') {
              $alert->{responseType} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'urgency') {
              $alert->{urgency} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'severity') {
              $alert->{severity} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'eventCode') {
              $xpc->setContextNode($infoChildNode);
              my $valueName = $xpc->findvalue("./cap:valueName");
              if ($valueName eq 'LICENSE') {
                $alert->{license} = $xpc->findvalue("./cap:value");
              } elsif ($valueName eq 'II') {
                $alert->{eventCode} = $xpc->findvalue("./cap:value");
              } elsif ($valueName eq 'GROUP') {
                $alert->{eventGroup} = $xpc->findvalue("./cap:value");
              } elsif ($valueName eq 'AREA_COLOR') {
                $alert->{areaColor} = $xpc->findvalue("./cap:value");
                $alert->{areaColor} =~ s/ /, /g;
              }
            } elsif ($infoChildNode->nodeName() eq 'onset') {
              $alert->{onset} = ParseCAPTime($infoChildNode->textContent());
            } elsif ($infoChildNode->nodeName() eq 'expires') {
              $alert->{expires} = ParseCAPTime($infoChildNode->textContent());
            } elsif ($infoChildNode->nodeName() eq 'headline') {
              $alert->{headline} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'description') {
              $alert->{description} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'instruction') {
              $alert->{instruction} = $infoChildNode->textContent();
            } elsif ($infoChildNode->nodeName() eq 'area') {
              $xpc->setContextNode($infoChildNode);
              my $valueName = $xpc->findvalue("./cap:geocode/cap:valueName");
              if ($valueName eq 'WARNCELLID') {
                if (!defined($alert->{warncellid})) {
                  $alert->{warncellid} = [];
                  $alert->{areaDesc} = [];
                  $alert->{altitude} = [];
                  $alert->{ceiling} = [];
                }
                #::Log3 $name, 5, "$name: ProcessAlerts warncellid: " . $xpc->findvalue("./cap:geocode/cap:value");
                push(@{$alert->{warncellid}}, $xpc->findvalue("./cap:geocode/cap:value"));
                push(@{$alert->{areaDesc}}, $xpc->findvalue("./cap:areaDesc"));
                push(@{$alert->{altitude}}, $xpc->findvalue("./cap:altitude"));
                push(@{$alert->{ceiling}}, $xpc->findvalue("./cap:ceiling"));
              }
            }
          }
        }
      }
      #::Log3 $name, 5, "$name: ProcessAlerts header: $alert->{identifier}, $alert->{status}, $alert->{msgType}: $alert->{headline}, $alert->{warncellids}[0]";
      if (!defined($alert->{identifier})) {
        die "error in XML data, no alert identifier found";
      }
      if ($alert->{status} ne 'Test' && $alert->{responseType} ne 'Monitor') {
        $alerts{$alert->{identifier}} = $alert;
      }
    }
  };

  my $errorMessage = '';
  if ($@) {
    # exception
    my @parts = split(/ at |\n/, $@); # discard anything after " at " or newline
    if (@parts) {
      $errorMessage = $parts[0];
      ::Log3 $name, 4, "$name: ProcessAlerts error: $parts[0]";
    } else {
      $errorMessage = $@;
      ::Log3 $name, 4, "$name: ProcessAlerts error: $@";
    }
  } else {
    # alerts parsed successfully
    my $communeUnion = IsCommuneUnionWarncellId($warncellId);
    if (defined($hash->{".alertsFile".$communeUnion})) {
      if (open(my $file, ">", $hash->{".alertsFile".$communeUnion})) {
        # write alerts to temp file
        binmode($file);
        my $frozenAlerts = freeze(\%alerts);
        ::Log3 $name, 5, "$name: ProcessAlerts temp file " . $hash->{".alertsFile".$communeUnion} . " alerts " . keys(%alerts) . " size " . length($frozenAlerts);
        print($file $frozenAlerts);
        close($file);
      } else {
        $errorMessage = $!;
        ::Log3 $name, 3, "$name: ProcessAlerts error opening temp file: $errorMessage";
      }
    } else {
      $errorMessage = 'result file name not defined';
      ::Log3 $name, 3, "$name: ProcessAlerts error: temp file name not defined";
    }
  }

  # get rid of newlines and commas because of Blocking InformFn parameter restrictions
  $errorMessage =~ s/\n/; /g;
  $errorMessage =~ s/,/;/g;

  ::Log3 $name, 5, "$name: ProcessAlerts END";

  return [$name, $errorMessage, $warncellId, $time];
}

=head2 GetAlertsFinish(@)

BlockingCall I<FinishFn> callback, expects array returned by function L</GetAlertsStart($)> as single parameter

=over

=item * param name: name of DWD_OpenData device

=item * param errorMessage: empty string or processing error message

=item * param warncellId: numeric warncell id for which alers have been requested, may also be C<UPDATE_DISTRICTS>, C<UPDATE_COMMUNEUNIONS> or C<UPDATE_ALL>

=item * param time: epoch time when alerts where received

=back

=cut

sub GetAlertsFinish(@)
{
  my ($name, $errorMessage, $warncellId, $time) = @_;

  if (defined($name)) {
    ::Log3 $name, 5, "$name: GetAlertsFinish START (PID $$)";

    my $hash = $::defs{$name};
    my $communeUnion = IsCommuneUnionWarncellId($warncellId);
    delete $hash->{".alertsBlockingCall".$communeUnion};

    if (defined($errorMessage) && length($errorMessage) > 0) {
      # error, skip further processing
    } elsif (!defined($hash->{".alertsFile".$communeUnion})) {
      $errorMessage = "internal temp file name missing";
      ::Log3 $name, 3, "$name: GetAlertsFinish error: $errorMessage";
    } else {
      # deserialize alerts
      my $fh = $hash->{".alertsFileHandle".$communeUnion};
      my $terminator = $/;
      $/ = undef;        # enable slurp file read mode
      my $frozenAlerts = <$fh>;
      $/ = $terminator;  # restore default file read mode
      close($hash->{".alertsFileHandle".$communeUnion});
      unlink($hash->{".alertsFile".$communeUnion});
      my %newAlerts = %{thaw($frozenAlerts)};
      ::Log3 $name, 5, "$name: GetAlertsFinish temp file " . $hash->{".alertsFile".$communeUnion} . " alerts " . keys(%newAlerts) . " size " . length($frozenAlerts);
      delete($hash->{".alertsFile".$communeUnion});

      # @todo delete global alert list when no differential updates are available?
      my $alerts = {};

      # update global alert list
      foreach my $alert (values(%newAlerts)) {
        my $indentifierExists = defined($alerts->{$alert->{identifier}});
        if ($indentifierExists) {
          ::Log3 $name, 5, "$name: ProcessAlerts identifier " . $alert->{identifier} . " already known, data not updated";
        } elsif ($alert->{msgType} eq 'Alert') {
          # add new alert
          $alerts->{$alert->{identifier}} = $alert;
        } elsif ($alert->{msgType} eq 'Update') {
          # delete old alerts
          foreach my $reference (@{$alert->{references}}) {
            delete $alerts->{$reference};
          }
          # add new alert
          $alerts->{$alert->{identifier}} = $alert;
        } elsif ($alert->{msgType} eq 'Cancel') {
          # delete old alerts
          foreach my $reference (@{$alert->{references}}) {
            delete $alerts->{$reference};
          }
        }
      }
      $alertsData[$communeUnion] = $alerts;

      if ($warncellId == UPDATE_ALL) {
        if (!defined($alertsUpdating[0]) || (time() - $alertsUpdating[0] >= 60)) {
          # communeunions cache updated, start district cache update;
          GetAlerts($hash, UPDATE_DISTRICTS);
        }
      } elsif ($warncellId < 0) {
        ::readingsSingleUpdate($hash, 'state', 'alerts cache updated', 1);
      }
    }
    $alertsReceived[$communeUnion] = $time;

    if (defined($errorMessage) && length($errorMessage) > 0) {
      $alertsErrorMessage[$communeUnion] = $errorMessage;
      ::readingsSingleUpdate($hash, 'state', "alerts error: $errorMessage", 1);
    } else {
      $alertsErrorMessage[$communeUnion] = undef;
    }

    if ($warncellId >= 0) {
      # update alert readings for warncell id
      UpdateAlerts($hash, $warncellId);
    }

    $alertsUpdating[$communeUnion] = undef;

    $hash->{ALERTS_IN_CACHE} = (ref($alertsData[0]) eq 'HASH'? scalar(keys(%{$alertsData[0]})) : 0) + (ref($alertsData[1]) eq 'HASH'? scalar(keys(%{$alertsData[1]})) : 0);

    ::Log3 $name, 5, "$name: GetAlertsFinish END";
  } else {
    ::Log 3, "GetAlertsFinish error: device name missing";
  }
}

=head2 GetAlertsAbort($)

BlockingCall I<AbortFn> callback

=over

=item * param hash: hash of DWD_OpenData device

=back

=cut

sub GetAlertsAbort($)
{
  my ($hash, $errorMessage) = @_;
  my $name = $hash->{NAME};
  my $warncellId = $hash->{".warncellId"};

  my $communeUnion = IsCommuneUnionWarncellId($warncellId);
  delete $hash->{".alertsBlockingCall".$communeUnion};
  $alertsUpdating[$communeUnion] = undef;
  $errorMessage = "downloading and processing weather alerts data failed ($errorMessage)";
  ::Log3 $name, 3, "$name: GetAlertsAbort error: $errorMessage";
  $alertsErrorMessage[$communeUnion] = $errorMessage;

  if ($warncellId >= 0) {
    # update alert readings for warncell id
    UpdateAlerts($hash, $warncellId);
  } else {
    ::readingsSingleUpdate($hash, 'state', "alerts error: $errorMessage", 1);
  }
}

=head2 UpdateAlerts($$)

update alert readings for given warncell id from global alerts list

=over

=item * param hash: hash of DWD_OpenData device

=item * param warncellId: numeric warncell id greater zero

=item * return C<undef> or error message

=back

=cut

sub UpdateAlerts($$)
{
  my ($hash, $warncellId) = @_;
  my $name = $hash->{NAME};

  # delete existing alert readings
  ::CommandDeleteReading(undef, "$name ^(?!a_count|a_state|a_time)a_.*");

  ::readingsBeginUpdate($hash);

  # create alert for next 24 hours, if retrieval failed
  my $index = 0;
  my $communeUnion = IsCommuneUnionWarncellId($warncellId);
  if (defined($alertsErrorMessage[$communeUnion]) && length($alertsErrorMessage[$communeUnion]) > 0) {
    my $prefix = 'a_'.$index.'_';
    my $time = time();
    ::readingsBulkUpdate($hash, $prefix.'category',     'Met');
    ::readingsBulkUpdate($hash, $prefix.'event',        0);
    ::readingsBulkUpdate($hash, $prefix.'eventDesc',    'STÖRUNG');
    ::readingsBulkUpdate($hash, $prefix.'eventGroup',   'FHEM');
    ::readingsBulkUpdate($hash, $prefix.'responseType', 'Prepare');
    ::readingsBulkUpdate($hash, $prefix.'urgency',      'Immediate');
    ::readingsBulkUpdate($hash, $prefix.'severity',     'Severe');
    ::readingsBulkUpdate($hash, $prefix.'areaColor',    '255, 0, 0');
    ::readingsBulkUpdate($hash, $prefix.'onset',        FormatDateTimeLocal($hash, $time));
    ::readingsBulkUpdate($hash, $prefix.'expires',      FormatDateTimeLocal($hash, $time+24*60*60));
    ::readingsBulkUpdate($hash, $prefix.'headline',     'FHEM: Aktualisierung der Wetterwarnungen fehlgeschlagen');
    ::readingsBulkUpdate($hash, $prefix.'description',  "Fehler: $alertsErrorMessage[$communeUnion]");
    ::readingsBulkUpdate($hash, $prefix.'instruction',  'ACHTUNG! Aktuell stehen aufgrund einer Störung keine aktuellen Wetterwarnungen zur Verfügung.');
    ::readingsBulkUpdate($hash, $prefix.'area',         0);
    ::readingsBulkUpdate($hash, $prefix.'areaDesc',     'DWD Open Data Server');
    ::readingsBulkUpdate($hash, $prefix.'altitude',     0);
    ::readingsBulkUpdate($hash, $prefix.'ceiling',      0);
    $index++;

    ::readingsBulkUpdate($hash, 'a_state', "error: $alertsErrorMessage[$communeUnion]");
  } else {
    ::readingsBulkUpdate($hash, 'a_state', 'updated');
  }

  # prepare processing
  my $alertExcludeEvents = ::AttrVal($name, 'alertExcludeEvents', undef);
  my @excludeEventsList = split(',', $alertExcludeEvents) if (defined($alertExcludeEvents));
  foreach my $excludeEvent (@excludeEventsList) {
    $excludeEvent =~ s/^\s+|\s+$//g; # trim
  }
  my %excludeEvents = map { $_ => 1 } @excludeEventsList;

  # order alerts by onset
  my $alerts = $alertsData[$communeUnion];
  my @identifiers = sort { $alerts->{$a}->{onset} <=> $alerts->{$b}->{onset} } keys(%{$alerts});
  foreach my $identifier (@identifiers) {
    my $alert = $alerts->{$identifier};
    # find alert for selected warncell
    my $areaIndex = 0;
    foreach my $wcId (@{$alert->{warncellid}}) {
      if ($wcId == $warncellId && !(lc($alert->{severity}) eq 'minor' && defined($excludeEvents{$alert->{eventCode}}))) {
        # alert found that is not on the exclude list, create readings
        my $prefix = 'a_'.$index.'_';
        ::readingsBulkUpdate($hash, $prefix.'category',     $alert->{category});
        ::readingsBulkUpdate($hash, $prefix.'event',        $alert->{eventCode});
        ::readingsBulkUpdate($hash, $prefix.'eventDesc',    encode('UTF-8', $alert->{event}));
        ::readingsBulkUpdate($hash, $prefix.'eventGroup',   $alert->{eventGroup});
        ::readingsBulkUpdate($hash, $prefix.'responseType', $alert->{responseType});
        ::readingsBulkUpdate($hash, $prefix.'urgency',      $alert->{urgency});
        ::readingsBulkUpdate($hash, $prefix.'severity',     $alert->{severity});
        ::readingsBulkUpdate($hash, $prefix.'areaColor',    $alert->{areaColor});
        ::readingsBulkUpdate($hash, $prefix.'onset',        FormatDateTimeLocal($hash, $alert->{onset}));
        ::readingsBulkUpdate($hash, $prefix.'expires',      FormatDateTimeLocal($hash, $alert->{expires}));
        ::readingsBulkUpdate($hash, $prefix.'headline',     encode('UTF-8', $alert->{headline}));
        ::readingsBulkUpdate($hash, $prefix.'description',  encode('UTF-8', $alert->{description}));
        ::readingsBulkUpdate($hash, $prefix.'instruction',  encode('UTF-8', $alert->{instruction}));
        ::readingsBulkUpdate($hash, $prefix.'area',         $alert->{warncellid}[$areaIndex]);
        ::readingsBulkUpdate($hash, $prefix.'areaDesc',     encode('UTF-8', $alert->{areaDesc}[$areaIndex]));
        ::readingsBulkUpdate($hash, $prefix.'altitude',     floor(0.3048*$alert->{altitude}[$areaIndex] + 0.5));
        ::readingsBulkUpdate($hash, $prefix.'ceiling',      floor(0.3048*$alert->{ceiling}[$areaIndex] + 0.5));
        $index++;
        last();
      }
      $areaIndex++;
    }

    # license
    if ($index == 1 && defined($alert->{license})) {
      ::readingsBulkUpdate($hash, 'a_copyright', encode('UTF-8', $alert->{license}));
    }
  }

  # alert count and receive time
  ::readingsBulkUpdate($hash, 'a_count', $index);
  ::readingsBulkUpdate($hash, "a_time", FormatDateTimeLocal($hash, $alertsReceived[$communeUnion]));
  ::readingsBulkUpdate($hash, 'state', 'alerts updated');

  ::readingsEndUpdate($hash, 1);

  return undef;
}

# -----------------------------------------------------------------------------

package main;


=head1 FHEM INIT FUNCTION

=head2 DWD_OpenData_Initialize($)

FHEM I<Initialize> function

=over

=item * param hash: hash of DWD_OpenData device

=back

=cut

sub DWD_OpenData_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{DefFn}      = 'DWD_OpenData::Define';
  $hash->{UndefFn}    = 'DWD_OpenData::Undef';
  $hash->{ShutdownFn} = 'DWD_OpenData::Shutdown';
  $hash->{AttrFn}     = 'DWD_OpenData::Attr';
  $hash->{GetFn}      = 'DWD_OpenData::Get';

  $hash->{AttrList} = 'disable:0,1 '
                      .'forecastStation forecastDays forecastProperties forecastResolution:1,3,6 forecastWW2Text:0,1 '
                      .'alertArea alertLanguage:DE,EN alertExcludeEvents '
                      .'timezone '
                      .$readingFnAttributes;
}

# -----------------------------------------------------------------------------

1;

# -----------------------------------------------------------------------------
#
# CHANGES
#
# 11.03.2019 (version 1.14.1) jensb
# feature: support warncells that begin with 7
#
# 04.03.2019 (version 1.14.0) jensb
# coding: replaced Julian date calculation
# change: SunUp based on upper solar limb instead of nautical twilight
# feature: new daily sun position readings SunRise, SunSet
#
# 23.02.2019 (version 1.13.0) jensb
# feature: new hourly sun position readings SunAz, SunEl and SunUp
#
# 10.02.2019 (version 1.12.3) jensb
# feature: do not delete readings a_count, a_state, a_time when updating alerts
#
# 28.12.2018 (version 1.12.2) jensb
# bugfix: modified regexp to delete forecast readings on attribute change
#
# 23.12.2018 (version 1.12.1) jensb
# feature: new attribute alertExcludeEvents
# feature: delete forecast readings if attribute forecastResolution or forecastStation are changed
#
# 20.12.2018 (version 1.12.0) jensb
# feature: enable 1h forecast resolution
#
# 02.12.2018 (version 1.11.0) jensb
# feature: async processing of forecast enhanced (HttpUtils_NonblockingGet replaced by BlockingCall) to further unload FHEM process
# feature: staggered update of forecast and alert to spread load
# feature: improved cleanup of file descriptors on undef and shutdown
# feature: alerts and forecast retrieval error detection improved
# feature: new readings a_state and fc_state
# feature: create internal alert on retrieval error
# bugfix: forecast retrieval timout handling
# bugfix: forecast rotation days calculation
# bugfix: update scheduling when summertime changes
#
# 22.09.2018 jensb
# feature: forecast rotation for offline update reenabled
#
# 20.09.2018 jensb
# feature: CSV based forecast replaced by KML based forecast
#
# 04.07.2018 jensb
# bugfix: mark strptime as non package function in ParseDateTimeLocal and ParseDateLocal
#
# 23.06.2018 jensb
# bugfix: added use for package Encode
#
# 16.06.2018 jensb
# enhancement: trim alert values
#
# 14.06.2018 jensb
# coding: functions converted to package DWD_OpenData
#
# 13.05.2018 jensb
# bugfix: total alerts in cache
#
# 06.05.2018 jensb
# feature: detect empty alerts zip file
# bugfix:  preprocess exception messages from ProcessAlerts because Blocking FinishFn parameter content may not contain commas or newlines
#
# 22.04.2018 jensb
# feature: relaxed installation prerequisites (Text::CSV_XS now forecast specific, TZ does not need to be defined)
#
# 16.04.2018 jensb
# bugfix: alerts push on scalar
#
# 13.04.2018 jensb
# feature: forecast weekday reading
#
# 28.03.2018 jensb
# feature: support for CAP alerts
#
# 22.03.2018 jensb
# bugfix: replaced trunc with round when calculating delta days to cope with summertime
#
# 18.02.2018 jensb
# feature: LWP::Simple replaced by HttpUtils_NonblockingGet (provided by JoWiemann)
#
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
#
# @todo forecast: wwd in English
# @todo forecast: if a property is not available for a given hour the value of the previous or next hour might be used/interpolated?
# @todo alerts: queue get commands while cache is updating?
#
# -----------------------------------------------------------------------------

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary DWD Open Data weather alerts and forecast

=item summary_DE DWD Open Data Wetterwarnungen und Wettervorhersage

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="DWD_OpenData"></a>
<h3>DWD_OpenData</h3>
<ul>
  The Deutsche Wetterdienst (DWD) provides public weather related data via its <a href="https://www.dwd.de/DE/leistungen/opendata/opendata.html">Open Data Server</a>. Any usage of the service and the data provided by the DWD is subject to the usage conditions on the Open Data Server webpage. An overview of the available content can be found at <a href="https://www.dwd.de/DE/leistungen/opendata/help/inhalt_allgemein/opendata_content_de_en_xls.xls">OpenData_weather_content.xls</a>. <br><br>

  This module provides two elements of the available data:
  <ul> <br>
      <li>weather forecasts:
          <a href="https://opendata.dwd.de/weather/local_forecasts/mos/MOSMIX_L/single_stations/">Total lists of local forecasts of WMO, national and interpolated stations, all variables, 3, 9, 15, 21 UTC</a>. More than 70 properties are available for worldwide POIs and the German DWD network. This data typically spans 10 days and is updated by the DWD every 6 hours.<br><br>

          You can request forecasts for different stations in sequence using the command <code>get forecast &lt;station code&gt;</code> or for one station continuously using the attribute <code>forecastStation</code>. To get continuous mode for more than one station you need to create separate DWD_OpenData devices. <br><br>

          In continuous mode the forecast data will be shifted by one day at midnight without requiring new data from the DWD.<br><br>
      </li> <br>

      <li>weather alerts:
          <a href="https://opendata.dwd.de/weather/alerts/cap">Warning status for Germany as union of referenced community/district warnings</a>. This data is updated by the DWD as required. <br><br>

          After updating the alerts cache using the command <code>get updateAlertsCache &lt;mode&gt;</code> you can request alerts for different warncells in sequence using the command <code>get alerts &lt;warncell id&gt;</code>. Setting the attribute <code>alertArea</code> will enable continuous mode. To get continuous mode for more than one station you need to create separate DWD_OpenData devices. <br><br>

          Notes: This function is not suitable to rely on to ensure your safety! It will cause significant download traffic if used in continuous mode (more than 1 GB per day are possible). The device needs to keep all alerts for Germany in memory at all times to comply with the requirements of the common alerting protocol (CAP), even if only one warn cell is monitored. Depending on the weather activity this requires noticeable amounts of memory and CPU.
      </li>
  </ul> <br>

  Installation notes: <br><br>

  <ul>
      <li>This module requires the additional Perl module <code>XML::LibXML</code> for weather alerts. It can be installed depending on your OS and your preferences (e.g. <code>sudo apt-get install libxml-libxml-perl</code> or using CPAN). </li><br>

      <li>Data is fetched from the DWD Open Data Server using the FHEM module HttpUtils. If you use a proxy for internet access you need to set the global attribute <code>proxy</code> to a suitable value in the format <code>myProxyHost:myProxyPort</code>. </li><br>

      <li>Verify that your FHEM time is correct by entering <code>{localtime()}</code> into the FHEM command line. If not, check the system time and timezone of your FHEM server and adjust appropriately. It may be necessary to add <code>export TZ=`cat /etc/timezone`</code> or something similar to your FHEM start script <code>/etc/init.d/fhem</code> or your system configuration file <code>/etc/profile</code>. If <code>/etc/timezone</code> does not exists or is undefined execute <code>tzselect</code> to find your timezone and write the result into this file. After making changes restart FHEM and enter <code>{$ENV{TZ}}</code> into the FHEM command line to verify. To fix the timezone temporarily without restarting FHEM enter <code>{$ENV{TZ}='Europe/Berlin'}</code> or something similar into the FHEM command line. Again use <code>tzselect</code> to fine a valid timezone name. </li><br>

      <li>The weekday of the forecast will be in the language of your FHEM system. Enter <code>{$ENV{LANG}}</code> into the FHEM command line to verify. If nothing is displayed or you see an unexpected language setting, add <code>export LANG=de_DE.UTF-8</code> or something similar to your FHEM start script, restart FHEM and check again. If you get a locale warning when starting FHEM the required language pack might be missing. It can be installed depending on your OS and your preferences (e.g. <code>dpkg-reconfigure locales</code>, <code>apt-get install language-pack-de</code> or something similar). </li><br>

      <li>The digits in a warncell id of a communeunion or a district are mostly identical to an <i>Amtliche Gemeindekennziffer</i> if you strip of the 1st digit from the warncell id. You can lookup an Amtliche Gemeindekennziffer using the name of a communeunion or district e.g. at <a href="https://www.statistik-bw.de/Statistik-Portal/gemeindeverz.asp">Statistische &Auml;mter des Bundes und der L&auml;nder</a>. Then add 8 for a communeunion or 1 or 9 for a district at the beginning and try to find an exact or near match in the <a href="https://www.dwd.de/DE/leistungen/opendata/help/warnungen/cap_warncellids_csv.csv">Warncell-IDs for CAP alerts catalogue</a>. This approach is an alternative to <i>guessing</i> the right warncell id by the name of a communeunion or district. </li><br>

      <li>Like some other Perl modules this module temporarily modifies the TZ environment variable for timezone conversions. This may cause unexpected results in multi threaded environments. </li><br>

      <li>The forecast reading names do not contain absolute days or hours to keep them independent of summertime adjustments. Forecast days are counted relative to "today" of the timezone defined by the attribute of the same name or the timezone specified by the Perl TZ environment variable if undefined. </li><br>

      <li>Starting on 17.09.2018 the forecast data from the DWD is no longer available in CSV format and is based on the KML format instead. While most of the properties of the CSV format are still available in KML format, their names have changed and you will have to adjust your existing installation accordingly. </li><br>

      <li>This module provides sun position related information that is not available from the DWD. The properties for sunrise, sunset and sun up are calculated for the upper solar limb at given altitude and typical atmospheric refraction. </li><br>
  </ul><br>

  <a name="DWD_OpenDatadefine"></a>
  <b>Define</b> <br><br>
  <code>define &lt;name&gt; DWD_OpenData</code> <br><br><br>


  <a name="DWD_OpenDataget"></a>
  <b>Get</b>
  <ul> <br>
      <li>
          <code>get forecast [&lt;station code&gt;]</code><br>
          Fetch forecast for a station from DWD and update readings. The station code is either a 5 digit WMO station code or an alphanumeric DWD station code from the <a href="https://www.dwd.de/DE/leistungen/met_verfahren_mosmix/mosmix_stationskatalog.pdf">MOSMIX station catalogue</a>. If the attribute <code>forecastStation</code> is set, no <i>station code</i> must be provided. <br>
          The operation is performed non-blocking.
      </li> <br>
      <li>
          <code>get alerts [&lt;warncell id&gt;]</code><br>
          Set alert readings for given warncell id. A warncell id is a 9 digit numeric value from the <a href="https://www.dwd.de/DE/leistungen/opendata/help/warnungen/cap_warncellids_csv.csv">Warncell-IDs for CAP alerts catalogue</a>. Supported ids start with 8 (communeunion), 1 and 9 (district) or 5 (coast). If the attribute <code>alertArea</code> is set, no <i>warncell id</i> must be provided. <br>
          If the alerts cache is empty or older than 15 minutes the cache is updated first and the operation is non-blocking. If the cache is valid the operation is blocking. If a cache update is already in progress the operation fails. <br>
          To verify that alerts are provided for the warncell id you selected you should consult another source, wait for an alert situation and compare.
      </li> <br>
      <li>
          <code>get updateAlertsCache { communeUnions|districts|all }</code><br>
          Fetch alerts to update the alerts cache. Note that 'coast' alerts are part of the 'communeUnion' cache data. <br>
          The operation is performed non-blocking because it typically requires several seconds. If a cache update is already in progress the operation fails. <br>
          This command can be used before querying several warncells in sequence or to force a higher update frequency than the built-in 15 minutes. Note that all DWD_OpenData devices share a single alerts cache so updating the cache via one of the devices is sufficient.
      </li>
  </ul> <br><br>


  <a name="DWD_OpenDataattr"></a>
  <b>Attributes</b><br>
  <ul> <br>
      <li>disable {0|1}, default: 0<br>
          Disable fetching data.
      </li><br>
      <li>timezone &lt;tz&gt;, default: OS dependent<br>
          <a href="https://en.wikipedia.org/wiki/List_of_tz_database_time_zones">IANA TZ string</a> for date and time readings (e.g. "Europe/Berlin"), can be used to assume the perspective of a station that is in a different timezone or if your OS timezone settings do not match your local timezone. Alternatively you may use <code>tzselect</code> on the Linux command line to find a valid timezone string.
      </li><br>
  </ul>

  <b>forecast</b> related:
  <ul> <br>
      <li>forecastStation &lt;station code&gt;, default: none<br>
          Setting forecastStation enables automatic updates every hour.
          The station code is either a 5 digit WMO station code or an alphanumeric DWD station code from the <a href="https://www.dwd.de/DE/leistungen/met_verfahren_mosmix/mosmix_stationskatalog.pdf">MOSMIX station catalogue</a>.<br>
          Note: When value is changed all existing forecast readings will be deleted.
      </li><br>
      <li>forecastDays &lt;n&gt;, default: 6<br>
          Limits number of forecast days. Setting 0 will still provide forecast data for today. The maximum value is 9 (for today and 9 future days).
      </li><br>
      <li>forecastResolution {1|3|6}, default: 6 h<br>
          Time resolution (number of hours between 2 samples).<br>
          Note: When value is changed all existing forecast readings will be deleted.
      </li><br>
      <li>forecastProperties [&lt;p1&gt;[,&lt;p2&gt;]...], default: Tx, Tn, Tg, TTT, DD, FX1, Neff, RR6c, RRhc, Rh00, ww<br>
          A list of the properties available can be found <a href="https://opendata.dwd.de/weather/lib/MetElementDefinition.xml">here</a>.<br>
          Notes:<br>
          - Not all properties are available for all stations and for all hours.<br>
          - If you remove a property from the list then already existing readings must be deleted manually in continuous mode.<br>
      </li><br>
      <li>forecastWW2Text {0|1}, default: 0<br>
          Create additional wwd readings containing the weather code as a descriptive text in German language.
      </li><br>
  </ul>

  <b>alert</b> related:
  <ul> <br>
      <li>alertArea &lt;warncell id&gt;, default: none<br>
          Setting alertArea enables automatic updates of the alerts cache every 15 minutes.<br>
          A warncell id is a 9 digit numeric value from the <a href="https://www.dwd.de/DE/leistungen/opendata/help/warnungen/cap_warncellids_csv.csv">Warncell-IDs for CAP alerts catalogue</a>. Supported ids start with 7 and 8 (communeunion), 1 and 9 (district) or 5 (coast). To verify that alerts are provided for the warncell id you selected you should consult another source, wait for an alert situation and compare.
      </li>
      <li>alertLanguage [DE|EN], default: DE<br>
          Language of descriptive alert properties.
      </li>
      <li>alertExcludeEvents &lt;event code&gt;, default: none<br>
          Comma separated list of numeric events codes for which no alerts should be created.<br>
          Only minor alerts may be suppressed. Use at your own risk!
      </li>
  </ul> <br><br>


  <a name="DWD_OpenDatareadings"></a>
  <b>Readings</b> <br><br>

  The <b>forecast</b> readings are build like this: <br><br>

  <code>fc&lt;day&gt;_[&lt;sample&gt;_]&lt;property&gt;</code> <br><br>

  A description of the more than 70 properties available and their units of measurement can be found <a href="https://opendata.dwd.de/weather/lib/MetElementDefinition.xml">here</a>. The units of measurement for temperatures and wind speeds are converted to °C and km/h respectively. Only a few choice properties are listed in the following paragraphs: <br><br>

  <ul>
      <li>day    - relative day (0 .. 9) based on the timezone attribute where 0 is today</li><br>

      <li>sample - relative time (0 .. 3, 7 or 23) equivalent to multiples of 6, 3 or 1 hours UTC depending on the <code>forecastResolution</code> attribute</li><br>

      <li>day properties (typically for 06:00 station time, see raw data of station for actual time relation)
          <ul>
             <li>date          - date based on the timezone attribute</li>
             <li>weekday       - abbreviated weekday based on the timezone attribute in the language of your FHEM system</li>
             <li>Tn [°C]       - minimum temperature of previous 12 hours</li>
             <li>Tx [°C]       - maximum temperature of previous 12 hours (typically at 18:00 station time)</li>
             <li>Tm [°C]       - average temperature of previous 24 hours</li>
             <li>Tg [°C]       - minimum temperature 5 cm above ground of previous 12 hours</li>
             <li>PEvap [kg/m2] - evapotranspiration of previous 24 hours</li>
             <li>SunD [s]      - total sunshine duration of previous day</li>
          </ul>
      </li><br>

      <li>hour properties
          <ul>
             <li>time         - time based on the timezone attribute</li>
             <li>TTT [°C]     - dry bulb temperature at 2 meter above ground</li>
             <li>Td [°C]      - dew point temperature at 2 meter above ground</li>
             <li>DD [°]       - average wind direction 10 m above ground</li>
             <li>FF [km/h]    - average wind speed 10 m above ground</li>
             <li>FX1 [km/h]   - maximum wind speed in the last hour</li>
             <li>SunD1 [s]    - sunshine duration in the last hour</li>
             <li>SunD3 [s]    - sunshine duration in the last 3 hours</li>
             <li>RR1c [kg/m2] - precipitation amount in the last hour</li>
             <li>RR3c [kg/m2] - precipitation amount in the last 3 hours</li>
             <li>RR6c [kg/m2] - precipitation amount in the last 6 hours</li>
             <li>R600 [%]     - probability of rain in the last 6 hours</li>
             <li>RRhc [kg/m2] - precipitation amount in the last 12 hours</li>
             <li>Rh00 [%]     - probability of rain in the last 12 hours</li>
             <li>RRdc [kg/m2] - precipitation amount in the last 24 hours</li>
             <li>Rd00 [%]     - probability of rain in the last 24 hours</li>
             <li>ww           - weather code (see WMO 4680/4677, SYNOP)</li>
             <li>wwd          - German weather code description</li>
             <li>VV [m]       - horizontal visibility</li>
             <li>Neff [%]     - effective cloud cover</li>
             <li>Nl [%]       - lower level cloud cover below 2000 m</li>
             <li>Nm [%]       - medium level cloud cover below 7000 m</li>
             <li>Nh [%]       - high level cloud cover above 7000 m</li>
             <li>PPPP [hPa]   - pressure equivalent at sea level</li>
          </ul>
      </li>

      <li>extra day properties, not provided by the DWD
          <ul>
             <li>SunRise - time of sunrise based on the timezone attribute</li>
             <li>SunSet  - time of sunset based on the timezone attribute</li>
          </ul>
      </li>

      <li>extra hour properties, not provided by the DWD
          <ul>
             <li>SunAz [°] - sun azimuth</li>
             <li>SunEl [°] - sun elevation</li>
             <li>SunUp     - sun up (0: night, 1: day)</li>
          </ul>
      </li>
  </ul> <br>

  Additionally there are global forecast readings:
  <ul>
    <ul>
      <li>fc_state       - state of the last forecast update, possible values are 'updated' and 'error: ...'</li>
      <li>fc_station     - forecast station code (WMO or DWD)</li>
      <li>fc_description - station description</li>
      <li>fc_coordinates - world coordinate and height of station</li>
      <li>fc_time        - time the forecast was issued based on the timezone attribute</li>
      <li>fc_copyright   - legal information, must be displayed with forecast data, see DWD usage conditions</li>
    </ul>
  </ul> <br>

  The <b>alert</b> readings are ordered by onset and are build like this: <br><br>

  <code>a_&lt;index&gt;_&lt;property&gt;</code> <br><br>

  <ul>
      <li>index - alert index, starting with 0, total a_count, ordered by onset</li><br>

      <li>alert properties
          <ul>
             <li>category     - 'Met' or 'Health'</li>
             <li>event        - numeric event code, see DWD documentation for details</li>
             <li>eventDesc    - short event description in selected language</li>
             <li>eventGroup   - event group, see DWD documentation for details</li>
             <li>responseType - 'None' = no instructions, 'Prepare' = instructions, 'AllClear' = alert cleared</li>
             <li>urgency      - 'Immediate' = warning or 'Future' = information</li>
             <li>severity     - 'Minor', 'Moderate', 'Severe' or 'Extreme'</li>
             <li>areaColor    - RGB colour depending on urgency and severity, comma separated decimal triple</li>
             <li>onset        - start time of alert based on the timezone attribute</li>
             <li>expires      - end time of alert based on the timezone attribute</li>
             <li>headline     - headline in selected language, typically a combination of the properties urgency and event</li>
             <li>description  - description of the alert in selected language</li>
             <li>instruction  - safety instructions in selected language</li>
             <li>area         - numeric warncell id</li>
             <li>areaDesc     - description of area, e.g. 'Stadt Berlin'</li>
             <li>altitude     - min. altitude [m]</li>
             <li>ceiling      - max. altitude [m]</li>
          </ul>
      </li><br>
  </ul>

  Additionally there are some global alert readings:<br><br>

  <ul>
    <ul>
      <li>a_state     - state of the last alerts update, possible values are 'updated' and 'error: ...'</li>
      <li>a_time      - time the last alerts update was downloaded, based on the timezone attribute</li>
      <li>a_count     - number of alerts available for selected warncell id</li>
      <li>a_copyright - legal information, must be displayed with forecast data, see DWD usage conditions, not available if count is zero</li>
    </ul>
  </ul> <br>

  Alerts should be considered active for onset <= now < expires and responseType != 'AllClear' independent of urgency.<br>
  Inactive alerts with responseType = 'AllClear' may provide relevant instructions.<br><br>

  Note that all alert readings are completely replaced and reindexed with each update! <br><br>

  Further information regarding the alert properties can be found in the documentation of the <a href="https://www.dwd.de/DE/leistungen/opendata/help/warnungen/cap_dwd_profile_de_pdf.pdf">CAP DWS Profile</a>. <br><br>

  <b>Performance</b> <br><br>

  Note that depending on your device configuration each forecast consists of quite a lot of readings and each reading update will cause a FHEM event that needs to be processed. Depending on your hardware and your FHEM configuration this will take several hundred milliseconds. If you need to improve overall performance you can limit the number of readings created by setting a) the attribute <code>forecastProperties</code> to the ones you actually use, b) the attribute <code>forecastResolution</code> to the highest value suitable for your purposes and c) the attribute <code>forecastDays</code> to the lowest number suitable for your purposes. To further reduce the event processing overhead you can set the attribute <code>event-on-update-reading</code> to a small list of important reading that really need events (e.g. <code>state,fc_state,a_state</code>). For almost the same reason be selective when creating a log device. If you use wildcards for all readings without filtering either at the source device with <a href="#readingFnAttributes">readingFnAttributes</a> or at the destination device with a regexp you will get significant extra file IO when the readings are updated and quite a lot of data. <br>

</ul> <br>

=end html

=begin html_DE

<a name="DWD_OpenData"></a>
<h3>DWD_OpenData</h3>
<ul>
  Der Deutsche Wetterdienst (DWD) stellt Wetterdaten &uuml;ber den <a href="https://www.dwd.de/DE/leistungen/opendata/opendata.html">Open Data Server</a> zur Verf&uuml;gung. Die Verwendung dieses Dienstes und der vom DWD zur Verf&uuml;gung gestellten Daten unterliegt den auf der OpenData Webseite beschriebenen Bedingungen. Einen &Uuml;berblick &uuml;ber die verf&uuml;gbaren Daten findet man in der Tabelle <a href="https://www.dwd.de/DE/leistungen/opendata/help/inhalt_allgemein/opendata_content_de_en_xls.xls">OpenData_weather_content.xls</a>. <br><br>

  Eine Installationsbeschreibung findet sich in der <a href="https://wiki.fhem.de/wiki/DWD_OpenData">FHEMWiki</a>. <br><br>

  Eine detaillierte Modulbeschreibung gibt es auf Englisch - siehe die englische Modulhilfe von <a href="commandref.html#DWD_OpenData">DWD_OpenData</a>. <br>

</ul> <br>

=end html_DE

=cut

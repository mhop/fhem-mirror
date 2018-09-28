# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------

=encoding UTF-8

=head1 NAME

DWD_OpenData - A FHEM Perl module to retrieve forecasts and alerts from the
DWD Open Data Server.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2018 Jens B.

Copyright (C) 2018 JoWiemann (use of HttpUtils instead of LWP::Simple)

All rights reserved

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
use POSIX;
use Storable qw(freeze thaw);
use Time::HiRes qw(gettimeofday);
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
our $VERSION   = 1.010.002;
our @ISA       = qw(Exporter);
our @EXPORT    = qw(GetForecast GetAlerts UpdateAlerts UPDATE_DISTRICTS UPDATE_COMMUNEUNIONS UPDATE_ALL);
our @EXPORT_OK = qw(IsCommuneUnionWarncellId);

my %forecastPropertyAliases = ( 'TX' => 'Tx', 'TN' => 'Tn', 'TG' => 'Tg', 'TM' => 'Tm' );

my %forecastPropertyPeriods = (
                               'DD' => 1, 'DRR1' => 1, 'E_DD' => 1, 'E_FF' => 1, 'E_PPP' => 1, 'E_Td' => 1, 'E_TTT' => 1, 'FF' => 1, 'FX1' => 1, 'FX3' => 1, 'FX625' => 1, 'FX640' => 1, 'FX655' => 1, 'FXh' => 1, 'FXh25' => 1, 'FXh40' => 1, 'FXh55' => 1, 'N' => 1, 'N05' => 1, 'Neff' => 1, 'Nh' => 1, 'Nl' => 1, 'Nlm' => 1, 'Nm' => 1, 'PPPP' => 1, 'R101' => 1, 'R102' => 1, 'R103' => 1, 'R105' => 1, 'R107' => 1, 'R110' => 1, 'R120' => 1, 'R130' => 1, 'R150' => 1, 'R600' => 1, 'R602' => 1, 'R610' => 1, 'R650' => 1, 'RR1c' => 1, 'RR1o1' => 1, 'RR1u1' => 1, 'RR1w1' => 1, 'RR3c' => 1, 'RR6c' => 1, 'RRL1c' => 1, 'RRS1c' => 1, 'RRS3c' => 1, 'RRad1' => 1, 'Rad1h' => 1, 'RRhc' => 1, 'Rh00' => 1, 'Rh02' => 1, 'Rh10' => 1, 'Rh50' => 1, 'SunD1' => 1, 'SunD3' => 1, 'T5cm' => 1, 'Td' => 1, 'TTT' => 1, 'VV' => 1, 'VV10' => 1, 'W1W2' => 1, 'WPc11' => 1, 'WPc31' => 1, 'WPc61' => 1, 'WPcd1' => 1, 'WPch1' => 1, 'ww' => 1, 'ww3' => 1, 'wwC' => 1, 'wwC6' => 1, 'wwCh' => 1, 'wwD' => 1, 'wwD6' => 1, 'wwDh' => 1, 'wwF' => 1, 'wwF6' => 1, 'wwFh' => 1, 'wwL' => 1, 'wwL6' => 1, 'wwLh' => 1, 'wwM' => 1, 'wwM6' => 1, 'wwMd' => 1, 'wwMh' => 1, 'wwP' => 1, 'wwP6' => 1, 'wwPd' => 1, 'wwPh' => 1, 'wwS' => 1, 'wwS6' => 1, 'wwSh' => 1, 'wwT' => 1, 'wwT6' => 1, 'wwTd' => 1, 'wwTh' => 1, 'wwZ' => 1, 'wwZ6' => 1, 'wwZh' => 1,
                               'PEvap' => 24, 'PSd00' => 24, 'PSd30' => 24, 'PSd60' => 24, 'RRdc' => 24, 'RSunD' => 24, 'Rd00' => 24, 'Rd02' => 24, 'Rd10' => 24, 'Rd50' => 24, 'SunD' => 24, 'Tg' => 24, 'Tm' => 24, 'Tn' => 24, 'Tx' => 24
                              );

my %forecastDefaultProperties = (
                                 'Tg' => 1, 'Tn' => 1, 'Tx' => 1, 'DD' => 1, 'FX1' => 1, 'Neff' => 1, 'RR6c' => 1, 'RRhc' => 1, 'Rh00' => 1, 'TTT' => 1, 'ww' => 1
                                );

# 1 = temperature in K, 2 = integer value, 3 = wind speed in m/s, 4 = pressure in Pa
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

my @alerts_data     = [ undef, undef ];
my @alerts_received = [ undef, undef ];
my @alerts_updating = [ undef, undef ];


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
  my $name = $hash->{NAME};

  ::RemoveInternalTimer($hash);

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

  if (defined($hash->{".alertsBlockingCall"})) {
    ::BlockingKill($hash->{".alertsBlockingCall"});
  }

  if (defined($hash->{".alertsFile"})) {
    close($hash->{".alertsFileHandle"});
    unlink($hash->{".alertsFile"});
    delete($hash->{".alertsFile"});
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
          if ($main::init_done) {
            if ($value) {
              ::RemoveInternalTimer($hash);
              ::readingsSingleUpdate($hash, 'state', 'disabled', 1);
            } else {
              ::readingsSingleUpdate($hash, 'state', 'defined', 1);
              ::InternalTimer(gettimeofday() + 3, 'DWD_OpenData::Timer', $hash, 0);
            }
          }
        }
        when("forecastWW2Text") {
          if (!$value) {
            ::CommandDeleteReading(undef, "$name fc.*wwd");
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
        when("forecastWW2Text") {
          ::CommandDeleteReading(undef, "$name fc.*wwd");
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
        if (defined($alerts_updating[$communeUnion]) && (time() - $alerts_updating[$communeUnion] < 60)) {
          # abort if update is in progress
          $result = "alerts cache update in progress, please wait and try again";
        } elsif (defined($alerts_received[$communeUnion]) && (time() - $alerts_received[$communeUnion] < 900)) {
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
        $result = GetForecast($hash, $station);
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
      if (defined($alerts_updating[$communeUnion]) && (time() - $alerts_updating[$communeUnion] < 60)) {
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

=item * param hash: hash of DWD_OpenData device

=back

=cut

sub Timer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 5, "$name: Timer START";

  my $time = time();
  my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = Localtime($hash, $time);
  my $actQuarter = int($tMin/15);

  if ($actQuarter == 0) {
    my $forecastStation = ::AttrVal($name, 'forecastStation', undef);
    if (defined($forecastStation)) {
      my $result = GetForecast($hash, $forecastStation);
      if (defined($result)) {
        ::Log3 $name, 4, "$name: error retrieving forecast: $result";
      }
    }
  }

  my $warncellId = ::AttrVal($name, 'alertArea', undef);
  if (defined($warncellId)) {
    # skip update if already in progress
    my $communeUnion = IsCommuneUnionWarncellId($warncellId);
    if (!defined($alerts_updating[$communeUnion]) || (time() - $alerts_updating[$communeUnion] >= 60)) {
      my $result = GetAlerts($hash, $warncellId);
      if (defined($result)) {
        ::Log3 $name, 4, "$name: error retrieving alerts: $result";
      }
    }
  }

  # schedule next for 5 seconds past next quarter
  my $nextQuarterSeconds = Timelocal($hash, 0, $actQuarter*15, $tHour, $tMday, $tMon, $tYear) + 905;
  ::InternalTimer($nextQuarterSeconds, 'DWD_OpenData::Timer', $hash, 0);

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
  return int($warncellId/100000000) == 5 || int($warncellId/100000000) == 8
         || $warncellId == UPDATE_COMMUNEUNIONS || $warncellId == UPDATE_ALL? 1 : 0;
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
  #::Log3 $name, 5, "$name: A $daysAvailable";

  my $oT = ::ReadingsVal($name, 'fc0_date', undef);
  my $oldToday = defined($oT)? ParseDateLocal($hash, $oT) : undef;

  my $stationChanged = ::ReadingsVal($name, 'fc_station', '') ne $station;
  if ($stationChanged) {
    # different station, delete all existing readings
    ::CommandDeleteReading(undef, "$name fc.*");
    $daysAvailable = 0;
  } elsif (defined($oldToday)) {
    # same station, shift existing readings
    if (!defined($today)) {
      my $time = time();
      my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = Localtime($hash, $time);
      $today = Timelocal($hash, 0, 0, 0, $tMday, $tMon, $tYear);
    }

    my $daysForward = sprintf("%0.0f", $today - $oldToday);  # round()
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
          ::CommandDeleteReading(undef, "$name fc".$d."_.*");
        }
        $daysAvailable -= $daysForward;
      } else {
        # nothing to shift, delete existing readings
        ::CommandDeleteReading(undef, "$name fc.*");
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
    # test if XML module is available
    eval {
      require XML::LibXML;
    };
    if ($@) {
      return "$name: Perl module XML::LibXML not found, see commandref for details how to fix";
    }

    # @TODO move RotateForecast

    # get forecast for station from DWD server
    ::readingsSingleUpdate($hash, 'state', 'fetching', 0);
    my $url = 'https://opendata.dwd.de/weather/local_forecasts/mos/MOSMIX_L/single_stations/' . $station . '/kml/MOSMIX_L_LATEST_' . $station . '.kmz ';
    my $param = {
                  url        => $url,
                  method     => "GET",
                  timeout    => 10,
                  callback   => \&ProcessForecast,
                  hash       => $hash,
                  station    => $station
                };
    ::Log3 $name, 5, "$name: GetForecast START (PID $$): $url";
    ::HttpUtils_NonblockingGet($param);

    ::Log3 $name, 5, "$name: GetForecast END";
  } else {
    return "disabled";
  }
}

=head2 ProcessForecast($$$)

=over

=item * param param: parameter hash from call to HttpUtils_NonblockingGet

=item * param httpError: nothing or HTTP error string

=item * param fileContent: data retrieved from URL

=item * return C<undef> on success or error message

=back

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

  # preprocess existing readings
  ::readingsBeginUpdate($hash);
  my $time = time();
  my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = Localtime($hash, $time);
  my $today = Timelocal($hash, 0, 0, 0, $tMday, $tMon, $tYear);
  my $daysAvailable = RotateForecast($hash, $station, $today);

  my $relativeDay = 0;
  eval {
    if (defined($httpError) && length($httpError) > 0) {
      die "error retrieving URL '$url': $httpError";
    }
    if (defined($code) && $code != 200) {
      die "error $code retrieving URL '$url'";
    }
    if (!defined($fileContent) || length($fileContent) == 0) {
      die "no data retrieved from URL '$url'";
    }

    ::Log3 $name, 5, "$name: ProcessForecast: data received, $daysAvailable days currently exist with readings";

    # prepare processing
    ::readingsBulkUpdate($hash, 'state', 'processing');
    my $forecastWW2Text = ::AttrVal($name, 'forecastWW2Text', 0);
    my $forecastDays = ::AttrVal($name, 'forecastDays', 6);
    my $forecastResolution = ::AttrVal($name, 'forecastResolution', 6);
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

    ::readingsBulkUpdate($hash, "fc_station", $station);

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

      # extract header
      my @timestamps;
      my $defaultUndefSign = '-';
      my $productDefinitionNodeList = $dom->getElementsByLocalName('ProductDefinition');
      if ($productDefinitionNodeList->size()) {
        my $productDefinitionNode = $productDefinitionNodeList->get_node(1);
        foreach my $productDefinitionChildNode ($productDefinitionNode->nonBlankChildNodes()) {
          if ($productDefinitionChildNode->nodeName() eq 'dwd:Issuer') {
            my $issuer = $productDefinitionChildNode->textContent();
            ::readingsBulkUpdate($hash, "fc_copyright", "Datenbasis: $issuer");
          } elsif ($productDefinitionChildNode->nodeName() eq 'dwd:IssueTime') {
            my $issueTime = $productDefinitionChildNode->textContent();
            # ignore issue time, use now
            ::readingsBulkUpdate($hash, "fc_time", FormatDateTimeLocal($hash, $time));
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

      # extract data
      my %properties;
      my $placemarkNodeList = $dom->getElementsByLocalName('Placemark');
      if ($placemarkNodeList->size()) {
        my $placemarkNode = $placemarkNodeList->get_node(1);
        foreach my $placemarkChildNode ($placemarkNode->nonBlankChildNodes()) {
          if ($placemarkChildNode->nodeName() eq 'kml:description') {
            my $description = $placemarkChildNode->textContent();
            ::readingsBulkUpdate($hash, "fc_description", encode('UTF-8', $description));
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
                  my @values = split(' ',$textContent);
                  $properties{$elementName} = \@values;
                }
              }
            }
          } elsif ($placemarkChildNode->nodeName() eq 'kml:Point') {
            my $coordinates = $placemarkChildNode->nonBlankChildNodes()->get_node(1)->textContent();
            ::readingsBulkUpdate($hash, "fc_coordinates", $coordinates);
          }
        }
      }

      ::Log3 $name, 5, "$name: ProcessForecast: creating readings";

      # create readings
      my $lastDayPrefix = '';
      for my $i (0 .. $#timestamps) {
        # analyse date relation between forecast and today
        my $forecastTime = $timestamps[$i];
        my ($fcSec, $fcMin, $fcHour, $fcMday, $fcMon, $fcYear, $fcWday, $fcYday, $fcIsdst) = Localtime($hash, $forecastTime);
        my $forecastDate = Timelocal($hash, 0, 0, 0, $fcMday, $fcMon, $fcYear);
        $relativeDay = sprintf("%.0f", ($forecastDate - $today)/(24*60*60)); # Perl equivalent for round()
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
        while (my($property, $values) = each %properties) {
          #::Log3 $name, 5, "$name: $property  vs=" . scalar(@$values) . " ts=" . $#timestamps . " -> " . $values->[$i];
          if (defined($values->[$i])) {
            my $value = $values->[$i];
            if ($value ne $defaultUndefSign) {
              $value =~ s/,/./g; # decimal point
              my $forecastPropertyType = $forecastPropertyTypes{$property};
              if (defined($forecastPropertyType)) {
                if ($forecastPropertyType == 1) {
                  $value -= 273.15; # K -> °C
                  if (length($value) > 6) {
                    $value = sprintf('%0.2f', $value); # round to compensate floating point granularity
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
    }
  };

  # abort on exception
  if ($@) {
    my @parts = split(' at ', $@);
    if (@parts) {
      ::readingsBulkUpdate($hash, 'state', "forecast error: $parts[0]");
      ::Log3 $name, 4, "$name: ProcessForecast error: $parts[0]";
    } else {
      ::readingsBulkUpdate($hash, 'state', "forecast error: $@");
      ::Log3 $name, 4, "$name: ProcessForecast error: $@";
    }
    ::readingsEndUpdate($hash, 1);
    return @parts? $parts[0] : $@;
  }

  # delete existing readings of all days that have not been written
  if ($daysAvailable > $relativeDay + 1) {
    ::Log3 $name, 5, "$name: deleting days with index " . ($relativeDay + 1) . " to " . ($daysAvailable - 1);
    for (my $d=($relativeDay + 1); $d<$daysAvailable; $d++) {
      ::CommandDeleteReading(undef, "$name fc".$d."_.*");
    }
  }

  ::readingsBulkUpdate($hash, 'state', 'forecast updated');
  ::readingsEndUpdate($hash, 1);

  ::Log3 $name, 5, "$name: ProcessForecast END";

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

    # @TODO delete expired alerts?

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

    $alerts_updating[$communeUnion] = time();

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

  # get communion (5, 8) or district (1, 9) alerts for Germany from DWD server
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
      die "error $code retrieving URL '$url'";
    }
    if (!defined($fileContent) || length($fileContent) == 0) {
      die "no data retrieved from URL '$url'";
    }

    ::Log3 $name, 5, "$name: ProcessAlerts: data received";

    # create memory mapped file from received data and unzip
    open my $zipFileHandle, '<', \$fileContent;
    my @xmlStrings;
    unzip($zipFileHandle => \@xmlStrings, MultiStream => 1) or die "unzip failed: $UnzipError\n";

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
        die "parsing XML failed";
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

    if (defined($errorMessage) && length($errorMessage) > 0) {
      $alerts_updating[$communeUnion] = undef;
      ::readingsSingleUpdate($hash, 'state', "alerts error: $errorMessage", 1);
    } elsif (defined($hash->{".alertsFile".$communeUnion})) {
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

      # @TODO delete global alert list when no differential updates are available
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
      $alerts_data[$communeUnion] = $alerts;
      $alerts_received[$communeUnion] = $time;
      $alerts_updating[$communeUnion] = undef;

      if ($warncellId >= 0) {
        # update alert readings for warncell id
        UpdateAlerts($hash, $warncellId);
      } elsif ($warncellId == UPDATE_ALL) {
        if (!defined($alerts_updating[0]) || (time() - $alerts_updating[0] >= 60)) {
          # communeunions cache updated, start district cache update;
          GetAlerts($hash, UPDATE_DISTRICTS);
        }
      } else {
        ::readingsSingleUpdate($hash, 'state', "alerts cache updated", 1);
      }
    } else {
      ::readingsSingleUpdate($hash, 'state', "alerts error: result file name not defined", 1);
      ::Log3 $name, 3, "$name: GetAlertsFinish error: temp file name not defined";
    }

    $hash->{ALERTS_IN_CACHE} = (ref($alerts_data[0]) eq 'HASH'? scalar(keys(%{$alerts_data[0]})) : 0) + (ref($alerts_data[1]) eq 'HASH'? scalar(keys(%{$alerts_data[1]})) : 0);

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

  ::Log3 $name, 3, "$name: GetAlertsAbort error: retrieving weather alerts failed, $errorMessage";

  ::readingsSingleUpdate($hash, 'state', "alerts error: retrieving weather alerts failed, $errorMessage", 1);
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
  ::CommandDeleteReading(undef, "$name a_.*");

  ::readingsBeginUpdate($hash);

  # order alerts by onset
  my $communeUnion = IsCommuneUnionWarncellId($warncellId);
  my $alerts = $alerts_data[$communeUnion];
  my @identifiers = sort { $alerts->{$a}->{onset} <=> $alerts->{$b}->{onset} } keys(%{$alerts});
  my $index = 0;
  foreach my $identifier (@identifiers) {
    my $alert = $alerts->{$identifier};
    # find alert for selected warncell
    my $areaIndex = 0;
    foreach my $wcId (@{$alert->{warncellid}}) {
      if ($wcId == $warncellId) {
        # alert found, create readings
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
  ::readingsBulkUpdate($hash, "a_time", FormatDateTimeLocal($hash, $alerts_received[$communeUnion]));
  ::readingsBulkUpdate($hash, 'state', "alerts updated");

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
                      .'forecastStation forecastDays forecastProperties forecastResolution:3,6 forecastWW2Text:0,1 '
                      .'alertArea alertLanguage:DE,EN '
                      .'timezone '
                      .$readingFnAttributes;
}

# -----------------------------------------------------------------------------

1;

# -----------------------------------------------------------------------------
#
# CHANGES
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
# @TODO forecast: if a property is not available for a given hour the value of the previous or next hour is to be used/interpolated
# @TODO alerts:   queue get commands while cache is updating
# @TODO history:  https://opendata.dwd.de/weather/weather_reports/poi/
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

  This modules provides two elements of the available data:
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

      <li>The weekday of the forecast will be in the language of your FHEM system. Enter <code>{$ENV{LANG}}</code> into the FHEM command line to verify.
      If nothing is displayed or you see an unexpected language setting, add <code>export LANG=de_DE.UTF-8</code> or something similar to your FHEM start script, restart FHEM and check again. If you get a locale warning when starting FHEM the required language pack might be missing. It can be installed depending on your OS and your preferences (e.g. <code>dpkg-reconfigure locales</code>, <code>apt-get install language-pack-de</code> or something similar). </li><br>

      <li>The digits in a warncell id of a communeunion or a district are mostly identical to an <i>Amtliche Gemeindekennziffer</i> if you strip of the 1st digit from the warncell id. You can lookup an Amtliche Gemeindekennziffer using the name of a communeunion or district e.g. at <a href="https://www.statistik-bw.de/Statistik-Portal/gemeindeverz.asp">Statistische &Auml;mter des Bundes und der L&auml;nder</a>. Then add 8 for a communeunion or 1 or 9 for a district at the beginning and try to find an exact or near match in the <a href="https://www.dwd.de/DE/leistungen/opendata/help/warnungen/cap_warncellids_csv.csv">Warncell-IDs for CAP alerts catalogue</a>. This approach is an alternative to <i>guessing</i> the right warncell id by the name of a communeunion or district. </li><br>

      <li>Like some other Perl modules this module temporarily modifies the TZ environment variable for timezone conversions. This may cause unexpected results in multi threaded environments. </li><br>

      <li>The forecast reading names do not contain absolute days or hours to keep them independent of summertime adjustments. Forecast days are counted relative to "today" of the timezone defined by the attribute of the same name or the timezone specified by the Perl TZ environment variable if undefined. </li><br>

      <li>Starting on 17.09.2018 the forecast data is no longer available in CSV format and is based on the KML format instead. While most of the properties of the CSV format are still available in KML format, their names have changed and you will have to adjust your existing installation accordingly. </li><br>
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
          The station code is either a 5 digit WMO station code or an alphanumeric DWD station code from the <a href="https://www.dwd.de/DE/leistungen/met_verfahren_mosmix/mosmix_stationskatalog.pdf">MOSMIX station catalogue</a>.
      </li><br>
      <li>forecastDays &lt;n&gt;, default: 6<br>
          Limits number of forecast days. Setting 0 will still provide forecast data for today. The maximum value is 9 (for today and 9 future days).
      </li><br>
      <li>forecastResolution {3|6}, default: 6 h<br>
          Time resolution (number of hours between 2 samples).
      </li><br>
      <li>forecastProperties [&lt;p1&gt;[,&lt;p2&gt;]...] , default: Tx, Tn, Tg, TTT, DD, FX1, Neff, RR6c, RRhc, Rh00, ww<br>
          A list of the properties available can be found <a href="https://opendata.dwd.de/weather/lib/MetElementDefinition.xml">here</a>.
          If you remove a property from the list existing readings must be deleted manually in continuous mode.<br>
          Note: Not all properties are available for all stations and for all hours.
      </li><br>
      <li>forecastWW2Text {0|1}, default: 0<br>
          Create additional wwd readings containing the weather code as a descriptive text in German language.
      </li><br>
  </ul>

  <b>alert</b> related:
  <ul> <br>
      <li>alertArea &lt;warncell id&gt;, default: none<br>
          Setting alertArea enables automatic updates of the alerts cache every 15 minutes.
          A warncell id is a 9 digit numeric value from the <a href="https://www.dwd.de/DE/leistungen/opendata/help/warnungen/cap_warncellids_csv.csv">Warncell-IDs for CAP alerts catalogue</a>. Supported ids start with 8 (communeunion), 1 and 9 (district) or 5 (coast). To verify that alerts are provided for the warncell id you selected you should consult another source, wait for an alert situation and compare.
      </li>
      <li>alertLanguage [DE|EN], default: DE<br>
          Language of descriptive alert properties.</a>.
      </li>
  </ul> <br><br>


  <a name="DWD_OpenDatareadings"></a>
  <b>Readings</b> <br><br>

  The <b>forecast</b> readings are build like this: <br><br>

  <code>fc&lt;day&gt;_[&lt;sample&gt;_]&lt;property&gt;</code> <br><br>

  A description of the more than 70 properties available and their units of measurement can be found <a href="https://opendata.dwd.de/weather/lib/MetElementDefinition.xml">here</a>. The units of measurement for temperatures and wind speeds are converted to °C and km/h respectively. Only a few choice properties are listed in the following paragraphs: <br><br>

  <ul>
      <li>day    - relative day (0 .. 9) based on the timezone attribute where 0 is today</li><br>

      <li>sample - relative time (0 .. 3 or 7) equivalent to multiples of 6 or 3 hours UTC depending on the forecastHours attribute</li><br>

      <li>day properties (typically for 06:00 station time, see raw data of station for time relation)
          <ul>
             <li>date          - date based on the timezone attribute</li>
             <li>weekday       - abbreviated weekday based on the timezone attribute in the language of your FHEM system</li>
             <li>Tn [°C]       - minimum temperature of previous 24 hours</li>
             <li>Tx [°C]       - maximum temperature of previous 24 hours (typically for 18:00 station time)</li>
             <li>Tm [°C]       - average temperature of previous 24 hours</li>
             <li>Tg [°C]       - minimum temperature 5 cm above ground of previous 24 hours</li>
             <li>PEvap [kg/m2] - evapotranspiration of previous 24 hours</li>
             <li>SunD [s]      - total sunshine duration of previous 24 hours</li>
          </ul>
      </li><br>

      <li>hour properties
          <ul>
             <li>time         - hour based the timezone attribute</li>
             <li>TTT [°C]     - dry bulb temperature at 2 meter above ground</li>
             <li>Td [°C]      - dew point temperature at 2 meter above ground</li>
             <li>DD [°]       - average wind direction 10 m above ground</li>
             <li>FF [km/h]    - average wind speed 10 m above ground</li>
             <li>FX1 [km/h]   - maximum wind speed in the last hour</li>
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
             <li>Nh [%]       - high level cloud cover obove 7000 m</li>
             <li>PPPP [hPa]   - pressure equivalent at sea level</li>
          </ul>
      </li>
  </ul> <br>

  Additionally there are global forecast readings:
  <ul>
    <ul>
      <li>fc_station     - forecast station code (WMO or DWD)</li>
      <li>fc_description - station description</li>
      <li>fc_coordinates - world coordinat and height of station</li>
      <li>fc_time        - time the forecast updated was downloaded based on the timezone attribute</li>
      <li>fc_copyright   - legal information, must be displayed with forecast data, see DWD usage conditions</li>
    </ul>
  </ul> <br><br>


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
      <li>a_time      - time the last alert update was downloaded based on the timezone attribute</li>
      <li>a_count     - number of alerts available for selected warncell id</li>
      <li>a_copyright - legal information, must be displayed with forecast data, see DWD usage conditions, not available if count is zero</li>
    </ul>
  </ul> <br>

  Alerts should be considered active for onset <= now < expires and responseType != 'AllClear' independent of urgency.<br>
  Inactive alerts with responseType = 'AllClear' may provide relevant instructions.<br><br>

  Note that all alert readings are completely replaced and reindexed with each update! <br><br>

  Further information regarding the alert properties can be found in the documentation of the <a href="https://www.dwd.de/DE/leistungen/opendata/help/warnungen/cap_dwd_profile_de_pdf.pdf">CAP DWS Profile</a>. <br>

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

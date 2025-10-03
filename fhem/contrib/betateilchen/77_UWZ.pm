####################################################################################################
#
#  77_UWZ.pm
#
#  (c) 2015-2016 Tobias D. Oestreicher
#  (c) 2017-2021 Marko Oldenburg
#
#  Special thanks goes to comitters:
#       - Marko Oldenburg (fhemdevelopment at cooltux dot net)
#       - Hanjo (Forum) patch for sort by creation
#       - cb1 <kontakt@it-buchinger.de> patch Replace Iconv with native perl encode()
#       - KölnSolar (Markus) new write UWZAsHtml with smaler Code
#
#  Storm warnings from unwetterzentrale.de
#  inspired by 59_PROPLANTA.pm
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#
#
#  $Id: 77_UWZ.pm 25306 2021-12-06 05:27:48Z CoolTux $
#
####################################################################################################
# also a thanks goes to hexenmeister
##############################################

package FHEM::UWZ;

use strict;
use feature qw/say switch/;
use warnings;
use POSIX;
use GPUtils qw(GP_Import GP_Export);
use FHEM::Meta;
use Encode qw(encode_utf8);

# use Data::Dumper;    # Debug only

no
  if $] >= 5.017011,
  warnings => 'experimental::lexical_subs';

my $missingModul;
eval 'use LWP::UserAgent;1' or $missingModul .= 'LWP::UserAgent ';
eval 'use LWP::Simple;1'    or $missingModul .= 'LWP::Simple ';
eval 'use HTTP::Request;1'  or $missingModul .= 'HTTP::Request ';
eval 'use HTML::Parser;1'   or $missingModul .= 'HTML::Parser ';
eval 'use Encode::Guess;1'  or $missingModul .= 'Encode::Guess ';

require 'Blocking.pm';
require 'HttpUtils.pm';

use vars qw($readingFnAttributes);
use vars qw(%defs);

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

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          defs
          modules
          Log3
          CommandAttr
          CommandDeleteReading
          readingFnAttributes
          AttrVal
          ReadingsVal
          IsDisabled
          gettimeofday
          InternalTimer
          RemoveInternalTimer
          BlockingCall
          BlockingKill
          init_done
          FW_httpheader
          HttpUtils_BlockingGet
          deviceEvents
          contains_string)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      Start
      Run
      Aborted
      Done
      )
);

my @DEweekdays =
  qw(Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag);
my @DEmonths = (
    'Januar', 'Februar', 'März',     'April',   'Mai',      'Juni',
    'Juli',   'August',  'September', 'Oktober', 'November', 'Dezember'
);
my @NLweekdays = qw(zondag maandag dinsdag woensdag donderdag vrijdag zaterdag);
my @NLmonths   = (
    'januari', 'februari', 'maart',     'april',   'mei',      'juni',
    'juli',    'augustus', 'september', 'oktober', 'november', 'december'
);
my @FRweekdays = qw(dimanche lundi mardi mercredi jeudi vendredi samedi);
my @FRmonths   = (
    'janvier', 'février', 'mars',      'avril',   'mai',      'juin',
    'juillet', 'août',    'september', 'octobre', 'novembre', 'decembre'
);
my @ENweekdays = qw(sunday monday thuesday wednesday thursday friday saturday);
my @ENmonths   = (
    'January', 'February', 'March',     'April',   'Mäy',     'June',
    'July',    'August',   'September', 'October', 'November', 'December'
);

# my $countrycode = 'DE';
# my $plz = '77777';
# my $uwz_alert_url = 'https://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=de&areaID=UWZ' . $countrycode . $plz;

########################################
sub Log {
    my $hash     = shift;
    my $loglevel = shift;
    my $text     = shift;

    my $MODUL = 'UWZ';
    my $xline = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/UWZ_//;

    my $instName = ( ref($hash) eq 'HASH' ) ? $hash->{NAME} : $hash;
    Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;

    return;
}

########################################
sub Map2Movie {
    my $smap = shift;

    my $uwz_movie_url = "https://www.meteocentrale.ch/uploads/media/";
    my $lmap;

    $smap = lc($smap);

    ## Euro
    $lmap->{'niederschlag-wolken'} =
      $uwz_movie_url . 'UWZ_EUROPE_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung'}  = $uwz_movie_url . 'UWZ_EUROPE_COMPLETE_stfi.mp4';
    $lmap->{'temperatur'} = $uwz_movie_url . 'UWZ_EUROPE_COMPLETE_theta_E.mp4';

    ## DE
    $lmap->{'niederschlag-wolken-de'} =
      $uwz_movie_url . 'UWZ_EUROPE_GERMANY_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-de'} =
      $uwz_movie_url . 'UWZ_EUROPE_GERMANY_COMPLETE_stfi.mp4';

    ## CH
    $lmap->{'niederschlag-wolken-ch'} =
      $uwz_movie_url . 'UWZ_EUROPE_SWITZERLAND_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-ch'} =
      $uwz_movie_url . 'UWZ_EUROPE_SWITZERLAND_COMPLETE_stfi.mp4';

    ## AT
    $lmap->{'niederschlag-wolken-at'} =
      $uwz_movie_url . 'UWZ_EUROPE_AUSTRIA_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-at'} =
      $uwz_movie_url . 'UWZ_EUROPE_AUSTRIA_COMPLETE_stfi.mp4';

    ## NL
    $lmap->{'neerslag-wolken-nl'} =
      $uwz_movie_url . 'UWZ_EUROPE_BENELUX_COMPLETE_niwofi.mp4';
    $lmap->{'stroming-nl'} =
      $uwz_movie_url . 'UWZ_EUROPE_BENELUX_COMPLETE_stfi.mp4';

    ## FR
    $lmap->{'nuages-precipitations-fr'} =
      $uwz_movie_url . 'UWZ_EUROPE_FRANCE_COMPLETE_niwofi.mp4';
    $lmap->{'courants-fr'} =
      $uwz_movie_url . 'UWZ_EUROPE_FRANCE_COMPLETE_stfi.mp4';

    ## UK
    $lmap->{'clouds-precipitation-uk'} =
      $uwz_movie_url . 'UWZ_EUROPE_GREATBRITAIN_COMPLETE_niwofi.mp4';
    $lmap->{'currents-uk'} =
      $uwz_movie_url . 'UWZ_EUROPE_GREATBRITAIN_COMPLETE_stfi.mp4';

    ## IT
    $lmap->{'niederschlag-wolken-it'} =
      $uwz_movie_url . 'UWZ_EUROPE_ITALY_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-it'} =
      $uwz_movie_url . 'UWZ_EUROPE_ITALY_COMPLETE_stfi.mp4';

    return $lmap->{$smap};
}

########################################
sub Map2Image {
    my $smap = shift;

    my $uwz_de_url = 'https://www.unwetterzentrale.de/images/map/';
    my $uwz_at_url = 'https://unwetter.wetteralarm.at/images/map/';
    my $uwz_ch_url = 'https://alarm.meteocentrale.ch/images/map/';
    my $uwz_en_url = 'https://warnings.severe-weather-centre.co.uk/images/map/';
    my $uwz_li_url = 'https://alarm.meteocentrale.li/images/map/';
    my $uwz_be_url = 'https://alarm.meteo-info.be/images/map/';
    my $uwz_dk_url = 'https://alarm.vejrcentral.dk/images/map/';
    my $uwz_fi_url = 'https://vaaratasot.saa-varoitukset.fi/images/map/';
    my $uwz_fr_url = 'https://alerte.vigilance-meteo.fr/images/map/';
    my $uwz_lu_url = 'https://alarm.meteozentral.lu/images/map/';
    my $uwz_nl_url = 'https://alarm.noodweercentrale.nl/images/map/';
    my $uwz_no_url = 'https://advarsler.vaer-sentral.no/images/map/';
    my $uwz_pt_url = 'https://avisos.centrometeo.pt/images/map/';
    my $uwz_se_url = 'https://varningar.vader-alarm.se/images/map/';
    my $uwz_es_url = 'https://avisos.alertas-tiempo.es/images/map/';
    my $uwz_it_url = 'https://allarmi.meteo-allerta.it/images/map/';

    my $lmap;

    $smap = lc($smap);

    ## Euro
    $lmap->{'europa'} = $uwz_de_url . 'europe_index.png';

    ## DE
    $lmap->{'deutschland'}            = $uwz_de_url . 'deutschland_index.png';
    $lmap->{'deutschland-small'}      = $uwz_de_url . 'deutschland_preview.png';
    $lmap->{'niedersachsen'}          = $uwz_de_url . 'niedersachsen_index.png';
    $lmap->{'bremen'}                 = $uwz_de_url . 'niedersachsen_index.png';
    $lmap->{'bayern'}                 = $uwz_de_url . 'bayern_index.png';
    $lmap->{'schleswig-holstein'}     = $uwz_de_url . 'schleswig_index.png';
    $lmap->{'hamburg'}                = $uwz_de_url . 'schleswig_index.png';
    $lmap->{'mecklenburg-vorpommern'} = $uwz_de_url . 'meckpom_index.png';
    $lmap->{'sachsen'}                = $uwz_de_url . 'sachsen_index.png';
    $lmap->{'sachsen-anhalt'}         = $uwz_de_url . 'sachsenanhalt_index.png';
    $lmap->{'nordrhein-westfalen'}    = $uwz_de_url . 'nrw_index.png';
    $lmap->{'thueringen'}             = $uwz_de_url . 'thueringen_index.png';
    $lmap->{'rheinland-pfalz'}        = $uwz_de_url . 'rlp_index.png';
    $lmap->{'saarland'}               = $uwz_de_url . 'rlp_index.png';
    $lmap->{'baden-wuerttemberg'} = $uwz_de_url . 'badenwuerttemberg_index.png';
    $lmap->{'hessen'}             = $uwz_de_url . 'hessen_index.png';
    $lmap->{'brandenburg'}        = $uwz_de_url . 'brandenburg_index.png';
    $lmap->{'berlin'}             = $uwz_de_url . 'brandenburg_index.png';

    ## AT
    $lmap->{'oesterreich'}       = $uwz_at_url . 'oesterreich_index.png';
    $lmap->{'burgenland'}        = $uwz_at_url . 'burgenland_index.png';
    $lmap->{'kaernten'}          = $uwz_at_url . 'kaernten_index.png';
    $lmap->{'niederoesterreich'} = $uwz_at_url . 'niederoesterreich_index.png';
    $lmap->{'oberoesterreich'}   = $uwz_at_url . 'oberoesterreich_index.png';
    $lmap->{'salzburg'}          = $uwz_at_url . 'salzburg_index.png';
    $lmap->{'steiermark'}        = $uwz_at_url . 'steiermark_index.png';
    $lmap->{'tirol'}             = $uwz_at_url . 'tirol_index.png';
    $lmap->{'vorarlberg'}        = $uwz_at_url . 'vorarlberg_index.png';
    $lmap->{'wien'}              = $uwz_at_url . 'wien_index.png';

    ## CH
    $lmap->{'schweiz'} = $uwz_ch_url . 'schweiz_index.png';
    $lmap->{'aargau'}  = $uwz_ch_url . 'aargau_index.png';
    $lmap->{'appenzell_ausserrhoden'} =
      $uwz_ch_url . 'appenzell_ausserrhoden_index.png';
    $lmap->{'appenzell_innerrhoden'} =
      $uwz_ch_url . 'appenzell_innerrhoden_index.png';
    $lmap->{'basel_landschaft'} = $uwz_ch_url . 'basel_landschaft_index.png';
    $lmap->{'basel_stadt'}      = $uwz_ch_url . 'basel_stadt_index.png';
    $lmap->{'bern'}             = $uwz_ch_url . 'bern_index.png';
    $lmap->{'fribourg'}         = $uwz_ch_url . 'fribourg_index.png';
    $lmap->{'geneve'}           = $uwz_ch_url . 'geneve_index.png';
    $lmap->{'glarus'}           = $uwz_ch_url . 'glarus_index.png';
    $lmap->{'graubuenden'}      = $uwz_ch_url . 'graubuenden_index.png';
    $lmap->{'jura'}             = $uwz_ch_url . 'jura_index.png';
    $lmap->{'luzern'}           = $uwz_ch_url . 'luzern_index.png';
    $lmap->{'neuchatel'}        = $uwz_ch_url . 'neuchatel_index.png';
    $lmap->{'nidwalden'}        = $uwz_ch_url . 'nidwalden_index.png';
    $lmap->{'obwalden'}         = $uwz_ch_url . 'obwalden_index.png';
    $lmap->{'schaffhausen'}     = $uwz_ch_url . 'schaffhausen_index.png';
    $lmap->{'schwyz'}           = $uwz_ch_url . 'schwyz_index.png';
    $lmap->{'solothurn'}        = $uwz_ch_url . 'solothurn_index.png';
    $lmap->{'stgallen'}         = $uwz_ch_url . 'stgallen_index.png';
    $lmap->{'ticino'}           = $uwz_ch_url . 'ticino_index.png';
    $lmap->{'thurgau'}          = $uwz_ch_url . 'thurgau_index.png';
    $lmap->{'uri'}              = $uwz_ch_url . 'uri_index.png';
    $lmap->{'waadt'}            = $uwz_ch_url . 'waadt_index.png';
    $lmap->{'wallis'}           = $uwz_ch_url . 'wallis_index.png';
    $lmap->{'zug'}              = $uwz_ch_url . 'zug_index.png';
    $lmap->{'zuerich'}          = $uwz_ch_url . 'zuerich_index.png';

    ## LI
    $lmap->{'liechtenstein'} = $uwz_li_url . 'liechtenstein_index.png';

    ## UK
    $lmap->{'unitedkingdom'}    = $uwz_en_url . 'unitedkingdom_index.png';
    $lmap->{'eastofengland'}    = $uwz_en_url . 'eastofengland_index.png';
    $lmap->{'eastmidlands'}     = $uwz_en_url . 'eastmidlands-index.png';
    $lmap->{'london'}           = $uwz_en_url . 'london-index.png';
    $lmap->{'northeastengland'} = $uwz_en_url . 'northeastengland-index.png';
    $lmap->{'northernireland'}  = $uwz_en_url . 'northernireland-index.png';
    $lmap->{'northwestengland'} = $uwz_en_url . 'northwestengland-index.png';
    $lmap->{'scotland'}         = $uwz_en_url . 'scotland-index.png';
    $lmap->{'southeastengland'} = $uwz_en_url . 'southeastengland-index.png';
    $lmap->{'southwestengland'} = $uwz_en_url . 'southwestengland-index.png';
    $lmap->{'wales'}            = $uwz_en_url . 'wales-index.png';
    $lmap->{'westmidlands'}     = $uwz_en_url . 'westmidlands-index.png';
    $lmap->{'yorkshireandthehumber'} =
      $uwz_en_url . 'yorkshireandthehumber-index.png';

    ## BE
    $lmap->{'belgique'} = $uwz_be_url . 'belgique_index.png';

    ## DK
    $lmap->{'denmark'} = $uwz_dk_url . 'denmark_index.png';

    ## FI
    $lmap->{'finnland'} = $uwz_fi_url . 'finnland_index.png';

    ## FR
    $lmap->{'france'}            = $uwz_fr_url . 'france_index.png';
    $lmap->{'alsace'}            = $uwz_fr_url . 'alsace_index.png';
    $lmap->{'aquitaine'}         = $uwz_fr_url . 'aquitaine_index.png';
    $lmap->{'basse-normandie'}   = $uwz_fr_url . 'basse-normandie_index.png';
    $lmap->{'bretagne'}          = $uwz_fr_url . 'bretagne_index.png';
    $lmap->{'champagne-ardenne'} = $uwz_fr_url . 'champagne-ardenne_index.png';
    $lmap->{'franche-comte'}     = $uwz_fr_url . 'franche-comte_index.png';
    $lmap->{'haute-normandie'}   = $uwz_fr_url . 'haute-normandie_index.png';
    $lmap->{'ile-de-france'}     = $uwz_fr_url . 'ile-de-france_index.png';
    $lmap->{'languedoc-roussillon'} =
      $uwz_fr_url . 'languedoc-roussillon_index.png';
    $lmap->{'limousin'}      = $uwz_fr_url . 'limousin_index.png';
    $lmap->{'lorraine'}      = $uwz_fr_url . 'lorraine_index.png';
    $lmap->{'bourgogne'}     = $uwz_fr_url . 'bourgogne_index.png';
    $lmap->{'centre'}        = $uwz_fr_url . 'centre_index.png';
    $lmap->{'midi-pyrenees'} = $uwz_fr_url . 'midi-pyrenees_index.png';
    $lmap->{'nord-pas-de-calais'} =
      $uwz_fr_url . 'nord-pas-de-calais_index.png';
    $lmap->{'pays-de-la-loire'} = $uwz_fr_url . 'pays-de-la-loire_index.png';
    $lmap->{'picardie'}         = $uwz_fr_url . 'picardie_index.png';
    $lmap->{'poitou-charentes'} = $uwz_fr_url . 'poitou-charentes_index.png';
    $lmap->{'provence-alpes-cote-dazur'} =
      $uwz_fr_url . 'provence-alpes-cote-dazur_index.png';
    $lmap->{'rhone-alpes'} = $uwz_fr_url . 'rhone-alpes_index.png';

    ## LU
    $lmap->{'letzebuerg'} = $uwz_lu_url . 'letzebuerg_index.png';

    ## NL
    $lmap->{'nederland'}    = $uwz_nl_url . 'nederland_index.png';
    $lmap->{'drenthe'}      = $uwz_nl_url . 'drenthe_index.png';
    $lmap->{'flevoland'}    = $uwz_nl_url . 'flevoland_index.png';
    $lmap->{'friesland'}    = $uwz_nl_url . 'friesland_index.png';
    $lmap->{'gelderland'}   = $uwz_nl_url . 'gelderland_index.png';
    $lmap->{'groningen'}    = $uwz_nl_url . 'groningen_index.png';
    $lmap->{'limburg'}      = $uwz_nl_url . 'limburg_index.png';
    $lmap->{'noordbrabant'} = $uwz_nl_url . 'noordbrabant_index.png';
    $lmap->{'noordholland'} = $uwz_nl_url . 'noordholland_index.png';
    $lmap->{'overijssel'}   = $uwz_nl_url . 'overijssel_index.png';
    $lmap->{'utrecht'}      = $uwz_nl_url . 'utrecht_index.png';
    $lmap->{'zeeland'}      = $uwz_nl_url . 'zeeland_index.png';
    $lmap->{'zuidholland'}  = $uwz_nl_url . 'zuidholland_index.png';

    ## NO
    $lmap->{'norwegen'} = $uwz_no_url . 'norwegen_index.png';

    ## PT
    $lmap->{'portugal'} = $uwz_pt_url . 'portugal_index.png';

    ## SE
    $lmap->{'sverige'} = $uwz_se_url . 'sverige_index.png';

    ## ES
    $lmap->{'espana'} = $uwz_es_url . 'espana_index.png';

    ## IT
    $lmap->{'italia'}            = $uwz_it_url . 'italia_index.png';
    $lmap->{'valledaosta'}       = $uwz_it_url . 'valledaosta_index.png';
    $lmap->{'piemonte'}          = $uwz_it_url . 'piemonte_index.png';
    $lmap->{'lombardia'}         = $uwz_it_url . 'lombardia_index.png';
    $lmap->{'trentinoaltoadige'} = $uwz_it_url . 'trentinoaltoadige_index.png';
    $lmap->{'friuliveneziagiulia'} =
      $uwz_it_url . 'friuliveneziagiulia_index.png';
    $lmap->{'veneto'}        = $uwz_it_url . 'veneto_index.png';
    $lmap->{'liguria'}       = $uwz_it_url . 'liguria_index.png';
    $lmap->{'emiliaromagna'} = $uwz_it_url . 'emiliaromagna_index.png';
    $lmap->{'toscana'}       = $uwz_it_url . 'toscana_index.png';
    $lmap->{'marche'}        = $uwz_it_url . 'marche_index.png';
    $lmap->{'umbria'}        = $uwz_it_url . 'umbria_index.png';
    $lmap->{'lazio'}         = $uwz_it_url . 'lazio_index.png';
    $lmap->{'molise'}        = $uwz_it_url . 'molise_index.png';
    $lmap->{'abruzzo'}       = $uwz_it_url . 'abruzzo_index.png';
    $lmap->{'campania'}      = $uwz_it_url . 'campania_index.png';
    $lmap->{'puglia'}        = $uwz_it_url . 'puglia_index.png';
    $lmap->{'basilicata'}    = $uwz_it_url . 'basilicata_index.png';
    $lmap->{'calabria'}      = $uwz_it_url . 'calabria_index.png';
    $lmap->{'sicilia'}       = $uwz_it_url . 'sicilia_index.png';
    $lmap->{'sardegna'}      = $uwz_it_url . 'sardegna_index.png';

    ## Isobaren
    $lmap->{'isobaren1'} =
      'https://www.unwetterzentrale.de/images/icons/UWZ_ISO_00.jpg';
    $lmap->{'isobaren2'} =
      'https://www.wetteralarm.at/uploads/pics/UWZ_EURO_ISO_GER_00.jpg';
    $lmap->{'isobaren3'} =
'https://www.severe-weather-centre.co.uk/uploads/pics/UWZ_EURO_ISO_ENG_00.jpg';

    return $lmap->{$smap};
}

###################################
sub Initialize {
    my $hash = shift;

    $hash->{DefFn}    = \&Define;
    $hash->{UndefFn}  = \&Undef;
    $hash->{SetFn}    = \&Set;
    $hash->{NotifyFn} = \&Notify;
    $hash->{GetFn}    = \&Get;
    $hash->{AttrFn}   = \&Attr;
    $hash->{AttrList} =
        'download:0,1 '
      . 'savepath ' . 'maps '
      . 'humanreadable:0,1 '
      . 'htmlattr '
      . 'htmltitle '
      . 'htmltitleclass '
      . 'htmlsequence:ascending,descending ' . 'lang '
      . 'sort_readings_by:severity,start,creation '
      . 'localiconbase '
      . 'intervalAtWarnLevel '
      . 'disable:1 '
      . 'disabledForIntervals '
      . $readingFnAttributes;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

###################################
sub Define {
    my $hash = shift // return;
    my $aArg = shift // return;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return "Error: Perl moduls " . $missingModul . "are missing on this system"
      if ($missingModul);

    return
      "Wrong syntax: use define <name> UWZ <CountryCode> <PLZ> <Interval> "
      if ( scalar( @{$aArg} ) != 5
        && lc $aArg->[2] ne 'search' );

    my $name = $hash->{NAME};
    my $lang = '';
    $hash->{VERSION}   = version->parse($VERSION)->normal;
    $hash->{NOTIFYDEV} = 'global,' . $name;

    if ( ( lc $aArg->[2] ) ne 'search' ) {
        readingsSingleUpdate( $hash, 'state', 'Initializing', 1 );
        $hash->{CountryCode} = $aArg->[2];
        $hash->{PLZ}         = $aArg->[3];

        ## URL by CountryCode

        my $URL_language = 'en';
        if (contains_string($hash->{CountryCode},('DE', 'AT', 'CH'))) {
            $URL_language = 'de';
        }
        if ( $hash->{CountryCode} eq 'NL' ) {
            $URL_language = 'nl';
        }
        if ( $hash->{CountryCode} eq 'FR' ) {
            $URL_language = 'fr';
        }

        $hash->{URL} =
'https://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language='
          . $URL_language
          . '&areaID=UWZ'
          . $aArg->[2]
          . $aArg->[3];

        $hash->{fhem}{LOCAL}  = 0;
        $hash->{INTERVAL}     = $aArg->[4];
        $hash->{INTERVALWARN} = 0;
    }
    else {
        readingsSingleUpdate( $hash, 'state', 'Search-Mode', 1 );
        $hash->{CountryCode} = uc $aArg->[2];
    }

    return;
}

#####################################
sub Undef {
    my $hash = shift;
    my $arg  = shift;

    RemoveInternalTimer($hash);
    BlockingKill( $hash->{helper}{RUNNING_PID} )
      if ( defined( $hash->{helper}{RUNNING_PID} ) );

    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            return
"check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
              unless ( $attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3( $name, 3, "UWZ ($name) - disabledForIntervals" );
        }

        elsif ( $cmd eq "del" ) {
            Log3( $name, 3, "UWZ ($name) - enabled" );
            readingsSingleUpdate( $hash, "state", "active", 1 );
        }
    }

    return;
}

#####################################
sub Set {
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg // return;
    my $cmd  = shift @$aArg // return qq{"set $name" needs at least one argument};

    my $usage = "Unknown argument $cmd, choose one of update:noArg "
      if ( ( lc $hash->{CountryCode} ) ne 'search' );

    return $usage if ( scalar( @{$aArg} ) != 0 );

		if ($cmd eq 'update') {
				Log $hash, 4, 'set command: ' . $cmd;
				$hash->{fhem}{LOCAL} = 1;
				Start($hash);
				$hash->{fhem}{LOCAL} = 0;
		} else {             # including $cmd eq '?'
				return $usage;
		}

    return;
}

sub Notify {
    my $hash = shift;
    my $dev  = shift;

    my $name = $hash->{NAME};

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    Start($hash)
      if (
        (
            (
                (
                    grep /^DEFINED.$name$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.disable$/,
                    @{$events}
                    or grep /^ATTR.$name.disable.0$/,
                    @{$events}
                )
                && $devname eq 'global'
                && $init_done
            )
            || (
                (
                    grep /^INITIALIZED$/,
                    @{$events}
                    or grep /^REREADCFG$/,
                    @{$events}
                    or grep /^MODIFIED.$name$/,
                    @{$events}
                )
                && $devname eq 'global'
            )
        )
        && ReadingsVal( $name, 'state', 'Search-Mode' ) ne 'Search-Mode'
      );

    return;
}

sub Get {
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg // return;
    my $cmd  = shift @$aArg // return qq{"get $name" needs at least one argument};

    if (contains_string($hash->{CountryCode},('DE', 'AT', 'CH'))) {
        my $usage =
"Unknown argument $cmd, choose one of Sturm:noArg Schneefall:noArg Regen:noArg Extremfrost:noArg Waldbrand:noArg Gewitter:noArg Glaette:noArg Hitze:noArg Glatteisregen:noArg Bodenfrost:noArg Hagel:noArg ";

        return $usage if ( scalar( @{$aArg} ) != 0 );

        return
            $cmd =~ m{\ASturm}xms         ? GetCurrent( $hash, 2 )
          : $cmd =~ m{\ASchneefall}xms    ? GetCurrent( $hash, 3 )
          : $cmd =~ m{\ARegen}xms         ? GetCurrent( $hash, 4 )
          : $cmd =~ m{\AExtremfrost}xms   ? GetCurrent( $hash, 5 )
          : $cmd =~ m{\AWaldbrand}xms     ? GetCurrent( $hash, 6 )
          : $cmd =~ m{\AGewitter}xms      ? GetCurrent( $hash, 7 )
          : $cmd =~ m{\AGlaette}xms       ? GetCurrent( $hash, 8 )
          : $cmd =~ m{\AHitze}xms         ? GetCurrent( $hash, 9 )
          : $cmd =~ m{\AGlatteisregen}xms ? GetCurrent( $hash, 10 )
          : $cmd =~ m{\ABodenfrost}xms    ? GetCurrent( $hash, 11 )
          : $cmd =~ m{\AHagel}xms         ? GetCurrentHail($hash)
          :                                 $usage;
    }

    elsif ( $hash->{CountryCode} eq 'NL' ) {
        my $usage =
"Unknown argument $cmd, choose one of storm:noArg sneeuw:noArg regen:noArg strenge-vorst:noArg bosbrand:noArg onweer:noArg gladheid:noArg hitte:noArg ijzel:noArg grondvorst:noArg hagel:noArg ";

        return $usage if ( scalar( @{$aArg} ) != 0 );

        return
            $cmd =~ m{\Astorm}xms         ? GetCurrent( $hash, 2 )
          : $cmd =~ m{\Asneeuw}xms        ? GetCurrent( $hash, 3 )
          : $cmd =~ m{\Aregen}xms         ? GetCurrent( $hash, 4 )
          : $cmd =~ m{\Astrenge-vorst}xms ? GetCurrent( $hash, 5 )
          : $cmd =~ m{\Abosbrand}xms      ? GetCurrent( $hash, 6 )
          : $cmd =~ m{\Aonweer}xms        ? GetCurrent( $hash, 7 )
          : $cmd =~ m{\Agladheid}xms      ? GetCurrent( $hash, 8 )
          : $cmd =~ m{\Ahitte}xms         ? GetCurrent( $hash, 9 )
          : $cmd =~ m{\Aijzel}xms         ? GetCurrent( $hash, 10 )
          : $cmd =~ m{\Agrondvorst}xms    ? GetCurrent( $hash, 11 )
          : $cmd =~ m{\Ahagel}xms         ? GetCurrentHail($hash)
          :                                 $usage;
    }

    elsif ( $hash->{CountryCode} eq 'FR' ) {
        my $usage =
"Unknown argument $cmd, choose one of tempete:noArg neige:noArg pluie:noArg strenge-vorst:noArg incendie-de-foret:noArg orage:noArg glissange:noArg canicule:noArg verglas:noArg grondvorst:noArg grele:noArg ";

        return $usage if ( scalar( @{$aArg} ) != 0 );

        return
            $cmd =~ m{\Atempete}xms          ? GetCurrent( $hash, 2 )
          : $cmd =~ m{\Aneige}xms            ? GetCurrent( $hash, 3 )
          : $cmd =~ m{\Apluie}xms            ? GetCurrent( $hash, 4 )
          : $cmd =~ m{\Atempérature}xms     ? GetCurrent( $hash, 5 )
          : $cmd =~ m{\Afeu-de-forêt}xms    ? GetCurrent( $hash, 6 )
          : $cmd =~ m{\Aorage}xms            ? GetCurrent( $hash, 7 )
          : $cmd =~ m{\Aoute-glissante}xms   ? GetCurrent( $hash, 8 )
          : $cmd =~ m{\Achaleur}xms          ? GetCurrent( $hash, 9 )
          : $cmd =~ m{\Apluie-de-verglas}xms ? GetCurrent( $hash, 10 )
          : $cmd =~ m{\Agelée}xms           ? GetCurrent( $hash, 11 )
          : $cmd =~ m{\Agrêle}xms           ? GetCurrentHail($hash)
          :                                    $usage;
    }

    elsif ( ( lc $hash->{CountryCode} ) eq 'search' ) {
        my $usage = "Unknown argument $cmd, choose one of SearchAreaID ";

        return $usage if ( scalar( @{$aArg} ) != 1 );

        if ( $cmd =~ m{\ASearchAreaID}xms ) { UWZSearchLatLon( $name, $aArg->[0] ); }
        elsif ( $cmd =~ m{\AAreaID}xms ) {
            my @splitparam = split( /,/, $aArg->[0] );
            UWZSearchAreaID( $splitparam[0], $splitparam[1] );
        }
        else { return $usage; }

    }
    else {
        my $usage =
"Unknown argument $cmd, choose one of storm:noArg snow:noArg rain:noArg extremfrost:noArg forest-fire:noArg thunderstorms:noArg glaze:noArg heat:noArg glazed-rain:noArg soil-frost:noArg hail:noArg ";

        return $usage if ( scalar( @{$aArg} ) != 0 );

        return
            $cmd =~ m{\Astorm}xms         ? GetCurrent( $hash, 2 )
          : $cmd =~ m{\Asnow}xms          ? GetCurrent( $hash, 3 )
          : $cmd =~ m{\Arain}xms          ? GetCurrent( $hash, 4 )
          : $cmd =~ m{\Aextremfrost}xms   ? GetCurrent( $hash, 5 )
          : $cmd =~ m{\Aforest-fire}xms   ? GetCurrent( $hash, 6 )
          : $cmd =~ m{\Athunderstorms}xms ? GetCurrent( $hash, 7 )
          : $cmd =~ m{\Aglaze}xms         ? GetCurrent( $hash, 8 )
          : $cmd =~ m{\Aheat}xms          ? GetCurrent( $hash, 9 )
          : $cmd =~ m{\Aglazed-rain}xms   ? GetCurrent( $hash, 10 )
          : $cmd =~ m{\Asoil-frost}xms    ? GetCurrent( $hash, 11 )
          : $cmd =~ m{\Ahail}xms          ? GetCurrentHail($hash)
          :                                 $usage;
    }
}

#####################################
sub GetCurrent {
    my $hash = shift;
    my $type = shift;

    my $name = $hash->{NAME};
    my $out;
    my $curTimestamp = time();
    if ( ReadingsVal( $name, 'WarnCount', 0 ) eq 0 ) {
        $out = 'inactive';
    }
    else {
        for ( my $i = 0 ; $i < ReadingsVal( $name, 'WarnCount', 0 ) ; $i++ ) {
            if (
                (
                    ReadingsVal( $name, 'Warn_' . $i . '_Start', '' )
                    le $curTimestamp
                )
                && ( ReadingsVal( $name, 'Warn_' . $i . '_End', '' )
                    ge $curTimestamp )
                && ( ReadingsVal( $name, 'Warn_' . $i . '_Type', '' ) eq $type )
              )
            {
                $out = 'active';
                last;
            }
            else {
                $out = 'inactive';
            }
        }
    }

    return $out;
}

#####################################
sub GetCurrentHail($) {
    my $hash = shift;

    my $name = $hash->{NAME};
    my $out;
    my $curTimestamp = time();

    if ( ReadingsVal( $name, "WarnCount", 0 ) eq 0 ) {
        $out = 'inactive';
    }
    else {
        for ( my $i = 0 ; $i < ReadingsVal( $name, 'WarnCount', 0 ) ; $i++ ) {
            if (
                (
                    ReadingsVal( $name, 'Warn_' . $i . '_Start', '' )
                    le $curTimestamp
                )
                && ( ReadingsVal( $name, 'Warn_' . $i . '_End', '' )
                    ge $curTimestamp )
                && ( ReadingsVal( $name, 'Warn_' . $i . '_Hail', '' ) eq 1 )
              )
            {
                $out = 'active';
                last;
            }
            else {
                $out = 'inactive';
            }
        }
    }

    return $out;
}

#####################################
sub JSONAcquire {
    my $hash = shift;
    my $URL  = shift;

    my $name = $hash->{NAME};

    return
      if ( !defined( $hash->{NAME} ) );

    Log $hash, 4, "Start capturing of $URL";

    my $param = {
        url     => $URL,
        timeout => 5,
        hash    => $hash,
        method  => 'GET',
        header  => '',
    };

    my ( $err, $data ) = HttpUtils_BlockingGet($param);

    if ( $err ne '' ) {
        my $err_log = "Can't get $URL -- " . $err;
        readingsSingleUpdate( $hash, 'lastConnection', $err, 1 );
        Log $hash, 1, 'Error: ' . $err_log;
        return encode_utf8( '{"Error": "' . $err . '"}' );
    }

    Log $hash, 4,
      length($data) . ' characters captured:  ' . encode_utf8($data);
    return encode_utf8($data);
}

#####################################
sub Start {
    my $hash = shift;

    my $name = $hash->{NAME};

    return
      if ( !defined( $hash->{NAME} ) );

    if ( !$hash->{fhem}{LOCAL} && $hash->{INTERVAL} > 0 )
    {    # set up timer if automatically call
        RemoveInternalTimer($hash);
        InternalTimer( gettimeofday() + $hash->{INTERVAL}, 'UWZ_Start', $hash );

        return readingsSingleUpdate( $hash, 'state', 'disabled', 1 )
          if ( IsDisabled($name) );

        readingsSingleUpdate( $hash, 'currentIntervalMode', 'normal', 0 );
    }

    ## URL by CountryCode
    my $URL_language = 'en';
    if ( AttrVal( $hash->{NAME}, 'lang', undef ) ) {
        $URL_language = AttrVal( $hash->{NAME}, 'lang', '' );
    }
    else {
        if (contains_string($hash->{CountryCode},('DE', 'AT', 'CH'))) {
            $URL_language = 'de';
        }
        elsif ( $hash->{CountryCode} eq 'NL' ) {
            $URL_language = 'nl';
        }
        elsif ( $hash->{CountryCode} eq 'FR' ) {
            $URL_language = 'fr';
        }
    }

    $hash->{URL} =
'https://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language='
      . $URL_language
      . '&areaID=UWZ'
      . $hash->{CountryCode}
      . $hash->{PLZ};

    if ( !defined( $hash->{URL} ) ) {

        Log $hash, 3, 'missing URL';
        return;
    }

    $hash->{helper}{RUNNING_PID} = BlockingCall(
        'UWZ_Run',        # callback worker task
        $name,            # name of the device
        'UWZ_Done',       # callback result method
        120,              # timeout seconds
        'UWZ_Aborted',    #  callback for abortion
        $hash
    );                    # parameter for abortion

    return;
}

#####################################
sub Aborted {
    my $hash = shift;

    delete( $hash->{helper}{RUNNING_PID} );

    return;
}

#####################################
# asyncronous callback by blocking
sub Done {
    my $string = shift;

    return
      if ( !defined($string) );

    # all term are separated by '|' , the first is the name of the instance
    my ( $name, %values ) = split( '\\|', $string );
    my $hash = $defs{$name};
    return
      if ( !defined( $hash->{NAME} ) );

    # delete the marker for RUNNING_PID process
    delete( $hash->{helper}{RUNNING_PID} );

    # UnWetterdaten speichern
    readingsBeginUpdate($hash);

    if ( defined $values{Error} ) {
        readingsBulkUpdate( $hash, 'lastConnection', $values{Error} );
        readingsBulkUpdate( $hash, 'state',
            'error at last run, please check >>lastConnection<< reading' );
    }
    else {

        while ( my ( $rName, $rValue ) = each(%values) ) {
            readingsBulkUpdate( $hash, $rName, $rValue );
            Log $hash, 5, "reading:$rName value:$rValue";
        }

        if ( keys %values > 0 ) {
            my $newState;
            Log $hash, 4, "Delete old Readings";
            for my $Counter ( $values{WarnCount} .. 9 ) {
                CommandDeleteReading( undef,
                    "$hash->{NAME} Warn_${Counter}_.*" );
            }

            if ( defined $values{WarnCount} ) {

                # Message by CountryCode

                $newState = 'Warnings: ' . $values{WarnCount};
                $newState = 'Warnungen: ' . $values{WarnCount}
                  if ( contains_string($hash->{CountryCode},('DE', 'AT', 'CH')) );
                $newState = 'Aantal waarschuwingen: ' . $values{WarnCount}
                  if ( $hash->{CountryCode} eq 'NL' );
                $newState = 'Avertissements: ' . $values{WarnCount}
                  if ( $hash->{CountryCode} eq 'FR' );

                # end Message by CountryCode
            }
            else {
                $newState =
'Error: Could not capture all data. Please check CountryCode and PLZ.';
            }

            readingsBulkUpdate( $hash, 'state', $newState );
            readingsBulkUpdate( $hash, 'lastConnection',
                    keys(%values)
                  . ' values captured in '
                  . $values{durationFetchReadings}
                  . ' s' );
            Log $hash, 4, keys(%values) . ' values captured';

        }
        else {

            readingsBulkUpdate( $hash, 'lastConnection', 'no data found' );
            Log $hash, 1, 'No data found. Check city name or URL.';

        }
    }

    readingsEndUpdate( $hash, 1 );

    if (   AttrVal( $name, 'intervalAtWarnLevel', '' ) ne ''
        && ReadingsVal( $name, 'WarnUWZLevel', 0 ) > 1 )
    {

        IntervalAtWarnLevel($hash);
        Log $hash, 5, 'run Sub IntervalAtWarnLevel';
    }

    return;
}

#####################################
sub Run {
    my $name = shift;

    my $ptext = $name;
    my $UWZ_download;
    my $UWZ_savepath;
    my $UWZ_humanreadable;

    return
      if ( !defined($name) );

    my $hash = $defs{$name};
    return
      if ( !defined( $hash->{NAME} ) );

    my $readingStartTime = time();
    my $attrdownload     = AttrVal( $name, 'download', '' );
    my $attrsavepath     = AttrVal( $name, 'savepath', '' );
    my $maps2fetch       = AttrVal( $name, 'maps', '' );

    ## begin redundant Reading switch
    my $attrhumanreadable = AttrVal( $name, 'humanreadable', '' );
    ## end redundant Reading switch

    # preset download
    if ( $attrdownload eq '' ) {

        $UWZ_download = 0;
    }
    else {

        $UWZ_download = $attrdownload;
    }

    # preset savepath
    if ( $attrsavepath eq '' ) {

        $UWZ_savepath = '/tmp/';
    }
    else {

        $UWZ_savepath = $attrsavepath;
    }

    # preset humanreadable
    if ( $attrhumanreadable eq '' ) {

        $UWZ_humanreadable = 0;
    }
    else {

        $UWZ_humanreadable = $attrhumanreadable;
    }

    if ( $UWZ_download == 1 ) {
        if ( !defined($maps2fetch) ) { $maps2fetch = 'deutschland'; }
        Log $hash, 4, 'Maps2Fetch : ' . $maps2fetch;
        my @maps = split( ' ', $maps2fetch );
        my $uwz_de_url = 'https://www.unwetterzentrale.de/images/map/';

        foreach my $smap (@maps) {
            Log $hash, 4, 'Download map : ' . $smap;
            my $img = Map2Image($smap);

            if ( !defined($img) ) {
                $img = $uwz_de_url . 'deutschland_index.png';
            }
            my $code = getstore( $img, $UWZ_savepath . $smap . '.png' );

            if ( $code == 200 ) {
                Log $hash, 4, 'Successfully downloaded map ' . $smap;

            }
            else {

                Log $hash, 3, 'Failed to download map (' . $img . ')';
            }
        }

    }

    # acquire the json-response
    my $response = JSONAcquire( $hash, $hash->{URL} );

    Log $hash, 5, length($response) . ' characters captured';

    my $uwz_warnings = JSON->new->ascii->decode($response);

    my $message;
    my $uwz_warncount;

    if ( !exists $uwz_warnings->{Error} ) {
        my $enc = guess_encoding($uwz_warnings);

        $uwz_warncount = scalar( @{ $uwz_warnings->{'results'} } );
        Log $hash, 4, 'There are ' . $uwz_warncount . ' warnings active';
        my $sortby = AttrVal( $name, 'sort_readings_by', '' );
        my @sorted;

        if ( $sortby eq 'creation' ) {
            Log $hash, 4, 'Sorting by creation';
            @sorted =
              sort { $b->{payload}{creation} <=> $a->{payload}{creation} }
              @{ $uwz_warnings->{'results'} };

        }
        elsif ( $sortby ne 'severity' ) {
            Log $hash, 4, 'Sorting by dtgStart';
            @sorted = sort { $a->{dtgStart} <=> $b->{dtgStart} }
              @{ $uwz_warnings->{'results'} };

        }
        else {
            Log $hash, 4, 'Sorting by severity';
            @sorted = sort { $a->{severity} <=> $b->{severity} }
              @{ $uwz_warnings->{'results'} };
        }

        my $i = 0;

        my %typenames = (
            '1'  => 'unknown',           # <===== FIX HERE
            '2'  => 'sturm',
            '3'  => 'schnee',
            '4'  => 'regen',
            '5'  => 'temperatur',
            '6'  => 'waldbrand',
            '7'  => 'gewitter',
            '8'  => 'strassenglaette',
            '9'  => 'temperatur',        # 9 = hitzewarnung
            '10' => 'glatteisregen',
            '11' => 'temperatur'
        );                               # 11 = bodenfrost

        my %typenames_de_str = (
            '1'  => 'unknown',           # <===== FIX HERE
            '2'  => 'Sturm',
            '3'  => 'Schnee',
            '4'  => 'Regen',
            '5'  => 'Temperatur',
            '6'  => 'Waldbrand',
            '7'  => 'Gewitter',
            '8'  => 'Strassenglaette',
            '9'  => 'Hitze',             # 9 = hitzewarnung
            '10' => 'Glatteisregen',
            '11' => 'Bodenfrost'
        );                               # 11 = bodenfrost

        my %typenames_nl_str = (
            '1'  => 'unknown',           # <===== FIX HERE
            '2'  => 'storm',
            '3'  => 'sneeuw',
            '4'  => 'regen',
            '5'  => 'temperatuur',
            '6'  => 'bosbrand',
            '7'  => 'onweer',
            '8'  => 'gladde wegen',
            '9'  => 'hitte',             # 9 = hitzewarnung
            '10' => 'ijzel',
            '11' => 'grondvorst'
        );                               # 11 = bodenfrost

        my %typenames_fr_str = (
            '1'  => 'unknown',            # <===== FIX HERE
            '2'  => 'tempete',
            '3'  => 'neige',
            '4'  => 'pluie',
            '5'  => 'températur',
            '6'  => 'feu de forêt',
            '7'  => 'orage',
            '8'  => 'route glissante',
            '9'  => 'chaleur',            # 9 = hitzewarnung
            '10' => 'pluie de verglas',
            '11' => 'gelée'
        );                                # 11 = bodenfrost

        my %typenames_en_str = (
            '1'  => 'unknown',            # <===== FIX HERE
            '2'  => 'storm',
            '3'  => 'snow',
            '4'  => 'rain',
            '5'  => 'temperatur',
            '6'  => 'forest fire',
            '7'  => 'thunderstorms',
            '8'  => 'slippery road',
            '9'  => 'heat',               # 9 = hitzewarnung
            '10' => 'black ice rain',
            '11' => 'soil frost'
        );                                # 11 = bodenfrost

        my %severitycolor = (
            '0'  => 'green',
            '1'  => 'unknown',            # <===== FIX HERE
            '2'  => 'unknown',            # <===== FIX HERE
            '3'  => 'unknown',            # <===== FIX HERE
            '4'  => 'orange',
            '5'  => 'unknown',            # <===== FIX HERE
            '6'  => 'unknown',            # <===== FIX HERE
            '7'  => 'orange',
            '8'  => 'gelb',
            '9'  => 'gelb',               # <===== FIX HERE
            '10' => 'orange',
            '11' => 'rot',
            '12' => 'violett'
        );

        my @uwzmaxlevel;
        foreach my $single_warning (@sorted) {

            push @uwzmaxlevel,
              GetUWZLevel( $hash, $single_warning->{'payload'}{'levelName'} );

            Log $hash, 4,
              'Warn_' . $i . '_EventID: ' . $single_warning->{'payload'}{'id'};
            $message .=
                'Warn_'
              . $i
              . '_EventID|'
              . $single_warning->{'payload'}{'id'} . '|';

            my $chopcreation =
              substr( $single_warning->{'payload'}{'creation'}, 0, 10 );
            $chopcreation = $chopcreation;

            Log $hash, 4, 'Warn_' . $i . '_Creation: ' . $chopcreation;
            $message .= 'Warn_' . $i . '_Creation|' . $chopcreation . '|';

            Log $hash, 4, 'Warn_' . $i . '_Type: ' . $single_warning->{'type'};
            $message .=
              'Warn_' . $i . '_Type|' . $single_warning->{'type'} . '|';

            Log $hash, 4,
                'Warn_'
              . $i
              . '_uwzLevel: '
              . GetUWZLevel( $hash, $single_warning->{'payload'}{'levelName'} );
            $message .= 'Warn_'
              . $i
              . '_uwzLevel|'
              . GetUWZLevel( $hash, $single_warning->{'payload'}{'levelName'} )
              . '|';

            Log $hash, 4,
              'Warn_' . $i . '_Severity: ' . $single_warning->{'severity'};
            $message .=
              'Warn_' . $i . '_Severity|' . $single_warning->{'severity'} . '|';

            Log $hash, 4,
              'Warn_' . $i . '_Start: ' . $single_warning->{'dtgStart'};
            $message .=
              'Warn_' . $i . '_Start|' . $single_warning->{'dtgStart'} . '|';

            Log $hash, 4, 'Warn_' . $i . '_End: ' . $single_warning->{'dtgEnd'};
            $message .=
              'Warn_' . $i . '_End|' . $single_warning->{'dtgEnd'} . '|';

            ## Begin of redundant Reading
            if ( $UWZ_humanreadable eq 1 ) {
                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_Start_Date: '
                  . strftime( "%d.%m.%Y",
                    localtime( $single_warning->{'dtgStart'} ) );
                $message .= 'Warn_'
                  . $i
                  . '_Start_Date|'
                  . strftime( "%d.%m.%Y",
                    localtime( $single_warning->{'dtgStart'} ) )
                  . '|';

                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_Start_Time: '
                  . strftime( "%H:%M",
                    localtime( $single_warning->{'dtgStart'} ) );
                $message .= 'Warn_'
                  . $i
                  . '_Start_Time|'
                  . strftime( "%H:%M",
                    localtime( $single_warning->{'dtgStart'} ) )
                  . '|';

                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_End_Date: '
                  . strftime( "%d.%m.%Y",
                    localtime( $single_warning->{'dtgEnd'} ) );
                $message .= 'Warn_'
                  . $i
                  . '_End_Date|'
                  . strftime( "%d.%m.%Y",
                    localtime( $single_warning->{'dtgEnd'} ) )
                  . '|';

                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_End_Time: '
                  . strftime( "%H:%M",
                    localtime( $single_warning->{'dtgEnd'} ) );
                $message .= 'Warn_'
                  . $i
                  . '_End_Time|'
                  . strftime( "%H:%M",
                    localtime( $single_warning->{'dtgEnd'} ) )
                  . '|';

                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_Creation_Date: '
                  . strftime( "%d.%m.%Y", localtime($chopcreation) );
                $message .= 'Warn_'
                  . $i
                  . '_Creation_Date|'
                  . strftime( "%d.%m.%Y", localtime($chopcreation) ) . '|';

                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_Creation_Time: '
                  . strftime( "%H:%M", localtime($chopcreation) );
                $message .= 'Warn_'
                  . $i
                  . '_Creation_Time|'
                  . strftime( "%H:%M", localtime($chopcreation) ) . '|';

                # Begin Language by AttrVal
                if ( contains_string($hash->{CountryCode},('DE', 'AT', 'CH')) ) {
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_Type_Str: '
                      . $typenames_de_str{ $single_warning->{'type'} };
                    $message .= 'Warn_'
                      . $i
                      . '_Type_Str|'
                      . $typenames_de_str{ $single_warning->{'type'} } . '|';
                    my %uwzlevelname = (
                        '0' => 'Stufe Grün (keine Warnung)',
                        '1' => 'Stufe Dunkelgrün (Wetterhinweise)',
                        '2' => 'Stufe Gelb (Vorwarnung für Unwetterwarnung)',
                        '3' => 'Warnstufe Orange (Unwetterwarnung)',
                        '4' => 'Warnstufe Rot (Unwetterwarnung)',
                        '5' => 'Warnstufe Violett (Unwetterwarnung)'
                    );
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_uwzLevel_Str: '
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      };
                    $message .= 'Warn_'
                      . $i
                      . '_uwzLevel_Str|'
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      }
                      . '|';

                }
                elsif ( $hash->{CountryCode} eq 'NL' ) {
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_Type_Str: '
                      . $typenames_nl_str{ $single_warning->{'type'} };
                    $message .= 'Warn_'
                      . $i
                      . '_Type_Str|'
                      . $typenames_nl_str{ $single_warning->{'type'} } . '|';
                    my %uwzlevelname = (
                        '0' => 'niveau groen (geen waarschuwingen)',
                        '1' => 'niveau donkergroen (weermelding)',
                        '2' => 'niveau geel (voorwaarschuwing)',
                        '3' =>
'waarschuwingsniveau oranje (waarschuwing voor matig noodweer)',
                        '4' =>
'waarschuwingsniveau rood (waarschuwing voor zwaar noodweer)',
                        '5' =>
'waarschuwingsniveau violet (waarschuwing voor zeer zwaar noodweer)'
                    );
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_uwzLevel_Str: '
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      };
                    $message .= 'Warn_'
                      . $i
                      . '_uwzLevel_Str|'
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      }
                      . '|';

                }
                elsif ( $hash->{CountryCode} eq 'FR' ) {
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_Type_Str: '
                      . $typenames_nl_str{ $single_warning->{'type'} };
                    $message .= 'Warn_'
                      . $i
                      . '_Type_Str|'
                      . $typenames_nl_str{ $single_warning->{'type'} } . '|';
                    my %uwzlevelname = (
                        '0' => 'niveau vert (aucune alerte)',
                        '1' => 'niveau vert foncé (indication météo)',
                        '2' => 'niveau jaune (pré-alerte)',
                        '3' => 'niveau d\' alerte orange (alerte météo)',
                        '4' => 'niveau d\' alerte rouge (alerte météo)',
                        '5' => 'niveau d\' alerte violet (alerte météo)'
                    );
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_uwzLevel_Str: '
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      };
                    $message .= 'Warn_'
                      . $i
                      . '_uwzLevel_Str|'
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      }
                      . '|';

                }
                else {
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_Type_Str: '
                      . $typenames_en_str{ $single_warning->{'type'} };
                    $message .= 'Warn_'
                      . $i
                      . '_Type_Str|'
                      . $typenames_en_str{ $single_warning->{'type'} } . '|';
                    my %uwzlevelname = (
                        '0' => 'level green (no warnings)',
                        '1' => 'level dark green (weather notice)',
                        '2' => 'level yellow (severe weather watch)',
                        '3' => 'Alert level Orange',
                        '4' => 'Alert level Red',
                        '5' => 'Alert level Violet'
                    );
                    Log $hash, 4,
                        'Warn_'
                      . $i
                      . '_uwzLevel_Str: '
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      };
                    $message .= 'Warn_'
                      . $i
                      . '_uwzLevel_Str|'
                      . $uwzlevelname{
                        GetUWZLevel( $hash,
                            $single_warning->{'payload'}{'levelName'} )
                      }
                      . '|';

                }

            }
            ## End of redundant Reading

            Log $hash, 4,
                'Warn_'
              . $i
              . '_levelName: '
              . $single_warning->{'payload'}{'levelName'};
            $message .= 'Warn_'
              . $i
              . '_levelName|'
              . $single_warning->{'payload'}{'levelName'} . '|';

            Log $hash, 4,
                'Warn_'
              . $i
              . '_AltitudeMin: '
              . $enc->decode( $single_warning->{'payload'}{'altMin'} );

            $message .= 'Warn_'
              . $i
              . '_AltitudeMin|'
              . encode( 'UTF-8',
                decode( 'iso-8859-1', $single_warning->{'payload'}{'altMin'} ) )
              . '|';

            Log $hash, 4,
                'Warn_'
              . $i
              . '_AltitudeMax: '
              . $enc->decode( $single_warning->{'payload'}{'altMax'} );

            $message .= 'Warn_'
              . $i
              . '_AltitudeMax|'
              . encode( 'UTF-8',
                decode( 'iso-8859-1', $single_warning->{'payload'}{'altMax'} ) )
              . '|';

            my $uclang = 'EN';
            if ( AttrVal( $name, 'lang', undef ) ) {
                $uclang = uc AttrVal( $name, 'lang', '' );
            }
            else {
                # Begin Language by AttrVal
                if ( contains_string($hash->{CountryCode},('DE','AT','CH')) ) {
                    $uclang = 'DE';
                }
                elsif ( $hash->{CountryCode} eq 'NL' ) {
                    $uclang = 'NL';
                }
                elsif ( $hash->{CountryCode} eq 'FR' ) {
                    $uclang = 'FR';
                }
                else {
                    $uclang = 'EN';
                }
            }
            Log $hash, 4,
                'Warn_'
              . $i
              . '_LongText: '
              . $enc->decode(
                $single_warning->{'payload'}{'translationsLongText'}{$uclang} );

            $message .= 'Warn_'
              . $i
              . '_LongText|'
              . encode(
                'UTF-8',
                decode(
                    'iso-8859-1',
                    $single_warning->{'payload'}{'translationsLongText'}
                      {$uclang}
                )
              ) . '|';

            Log $hash, 4,
                'Warn_'
              . $i
              . '_ShortText: '
              . $enc->decode(
                $single_warning->{'payload'}{'translationsShortText'}{$uclang}
              );

            $message .= 'Warn_'
              . $i
              . '_ShortText|'
              . encode(
                'UTF-8',
                decode(
                    'iso-8859-1',
                    $single_warning->{'payload'}{'translationsShortText'}
                      {$uclang}
                )
              ) . '|';

            ###
            if ( AttrVal( $name, 'localiconbase', undef ) ) {
                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_IconURL: '
                  . AttrVal( $name, 'localiconbase', undef )
                  . $typenames{ $single_warning->{'type'} } . '-'
                  . $single_warning->{'severity'} . '.png';
                $message .= 'Warn_'
                  . $i
                  . '_IconURL|'
                  . AttrVal( $name, 'localiconbase', undef )
                  . $typenames{ $single_warning->{'type'} } . '-'
                  . GetSeverityColor(
                    $hash,
                    GetUWZLevel(
                        $hash, $single_warning->{'payload'}{'levelName'}
                    )
                  ) . '.png|';

            }
            else {
                Log $hash, 4,
                    'Warn_'
                  . $i
                  . '_IconURL: https://www.unwetterzentrale.de/images/icons/'
                  . $typenames{ $single_warning->{'type'} } . '-'
                  . $single_warning->{'severity'} . '.gif';
                $message .= 'Warn_'
                  . $i
                  . '_IconURL|https://www.unwetterzentrale.de/images/icons/'
                  . $typenames{ $single_warning->{'type'} } . '-'
                  . GetSeverityColor(
                    $hash,
                    GetUWZLevel(
                        $hash, $single_warning->{'payload'}{'levelName'}
                    )
                  ) . '.gif|';
            }
            ###

            ## Hagel start
            my $hagelcount = 0;

            # Begin Language by AttrVal

            if ( contains_string($hash->{CountryCode},('DE', 'AT', 'CH')) ) {

                $hagelcount = my @hagelmatch =
                  $single_warning->{'payload'}{'translationsLongText'}{'DE'} =~
                  /Hagel/g;

            }
            elsif ( $hash->{CountryCode} eq 'NL' ) {

                $hagelcount = my @hagelmatch =
                  $single_warning->{'payload'}{'translationsLongText'}{'NL'} =~
                  /hagel/g;

            }
            elsif ( $hash->{CountryCode} eq 'FR' ) {

                $hagelcount = my @hagelmatch =
                  $single_warning->{'payload'}{'translationsLongText'}{'FR'} =~
                  /grêle/g;

            }
            else {

                $hagelcount = my @hagelmatch =
                  $single_warning->{'payload'}{'translationsLongText'}{'EN'} =~
                  /Hail/g;
            }

            # end language by AttrVal
            if ( $hagelcount ne 0 ) {

                Log $hash, 4, 'Warn_' . $i . '_Hail: 1';
                $message .= 'Warn_' . $i . '_Hail|1|';

            }
            else {

                Log $hash, 4, 'Warn_' . $i . '_Hail: 0';
                $message .= 'Warn_' . $i . '_Hail|0|';
            }
            ## Hagel end

            $i++;
        }

        my $max = 0;
        for (@uwzmaxlevel) {
            $max = $_ if !$max || $_ > $max;
        }

        $message .= 'WarnUWZLevel|';
        $message .= $max . '|';

        Log $hash, 4, 'WarnUWZLevel_Color: ' . GetSeverityColor( $hash, $max );
        $message .=
          'WarnUWZLevel_Color|' . GetSeverityColor( $hash, $max ) . '|';

        ## Begin of redundant Reading
        if ( $UWZ_humanreadable eq 1 ) {
            if ( contains_string($hash->{CountryCode},('DE', 'AT', 'CH')) ) {
                my %uwzlevelname = (
                    '0' => 'Stufe Grün (keine Warnung)',
                    '1' => 'Stufe Dunkelgrün (Wetterhinweise)',
                    '2' => 'Stufe Gelb (Vorwarnung für Unwetterwarnung)',
                    '3' => 'Warnstufe Orange (Unwetterwarnung)',
                    '4' => 'Warnstufe Rot (Unwetterwarnung)',
                    '5' => 'Warnstufe Violett (Unwetterwarnung)'
                );
                Log $hash, 4, 'WarnUWZLevel_Str: ' . $uwzlevelname{$max};
                $message .= 'WarnUWZLevel_Str|' . $uwzlevelname{$max} . '|';

            }
            elsif ( $hash->{CountryCode} eq 'NL' ) {
                my %uwzlevelname = (
                    '0' => 'niveau groen (geen waarschuwingen)',
                    '1' => 'niveau donkergroen (voorwaarschuwing)',
                    '2' => 'niveau geel (voorwaarschuwing)',
                    '3' =>
'waarschuwingsniveau oranje (waarschuwing voor matig noodweer)',
                    '4' =>
'waarschuwingsniveau rood (waarschuwing voor zwaar noodweer)',
                    '5' =>
'waarschuwingsniveau violet (waarschuwing voor zeer zwaar noodweer)'
                );
                Log $hash, 4, 'WarnUWZLevel_Str: ' . $uwzlevelname{$max};
                $message .= 'WarnUWZLevel_Str|' . $uwzlevelname{$max} . '|';

            }
            elsif ( $hash->{CountryCode} eq 'FR' ) {
                my %uwzlevelname = (
                    '0' => 'niveau vert (aucune alerte)',
                    '1' => 'niveau vert foncé (indication météo)',
                    '2' => 'niveau jaune (pré-alerte)',
                    '3' => 'niveau d\' alerte orange (alerte météo)',
                    '4' => 'niveau d\' alerte rouge (alerte météo)',
                    '5' => 'niveau d\' alerte violet (alerte météo)'
                );
                Log $hash, 4, 'WarnUWZLevel_Str: ' . $uwzlevelname{$max};
                $message .= 'WarnUWZLevel_Str|' . $uwzlevelname{$max} . '|';

            }
            else {
                my %uwzlevelname = (
                    '0' => 'level green (no warnings)',
                    '1' => 'level dark green (weather notice)',
                    '2' => 'level yellow (severe weather watch)',
                    '3' => 'Alert level Orange',
                    '4' => 'Alert level Red',
                    '5' => 'Alert level Violet'
                );
                Log $hash, 4, 'WarnUWZLevel_Str: ' . $uwzlevelname{$max};
                $message .= 'WarnUWZLevel_Str|' . $uwzlevelname{$max} . '|';
            }
        }

        $message .= 'durationFetchReadings|';
        $message .= sprintf "%.2f", time() - $readingStartTime;

        Log $hash, 3, 'Done fetching data';
        Log $hash, 4,
          'Will return : ' . "$name|$message|WarnCount|$uwz_warncount";
    }
    else {
        $message       = 'Error|' . $uwz_warnings->{Error};
        $uwz_warncount = -1;
    }

    return "$name|$message|WarnCount|$uwz_warncount";
}

#####################################
sub UWZAsHtml {
    my $name = shift;

    my $ret  = '';
    my $hash = $defs{$name};

    my $htmlsequence   = AttrVal( $name, 'htmlsequence',   'none' );
    my $htmltitle      = AttrVal( $name, 'htmltitle',      '' );
    my $htmltitleclass = AttrVal( $name, 'htmltitleclass', '' );

    my $attr;
    if ( AttrVal( $name, 'htmlattr', 'none' ) ne 'none' ) {
        $attr = AttrVal( $name, 'htmlattr', '' );
    }
    else {
        $attr = 'width="100%"';
    }

    if ( ReadingsVal( $name, 'WarnCount', 0 ) != 0 ) {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block" '
          . $attr
          . '><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';

        if ( $htmlsequence eq 'descending' ) {
            for (
                my $i = ReadingsVal( $name, 'WarnCount', -1 ) - 1 ;
                $i >= 0 ;
                $i--
              )
            {
                $ret .= UWZHtmlFrame( $hash, 'Warn_' . $i, $attr, 1 );

            }
        }
        else {
            for ( my $i = 0 ; $i < ReadingsVal( $name, 'WarnCount', 0 ) ; $i++ )
            {

                $ret .= UWZHtmlFrame( $hash, 'Warn_' . $i, $attr, 1 );
            }
        }

        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';

    }
    else {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block wide" width="600px"><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';
        $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;">';

        # language by AttrVal
        if ( contains_string($hash->{CountryCode},('DE','AT','CH')) ) {
            $ret .= '<b>Keine Warnungen</b>';
        }
        elsif ( $hash->{CountryCode} eq 'NL' ) {
            $ret .= '<b>Geen waarschuwingen</b>';
        }
        elsif ( $hash->{CountryCode} eq 'FR' ) {
            $ret .= '<b>Aucune alerte</b>';
        }
        else {
            $ret .= '<b>No Warnings</b>';
        }

        # end language by AttrVal
        $ret .= '</td></tr>';
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
    }

    return $ret;
}

#####################################
sub UWZAsHtmlLite {
    my $name = shift;

    my $ret            = '';
    my $hash           = $defs{$name};
    my $htmlsequence   = AttrVal( $name, 'htmlsequence', 'none' );
    my $htmltitle      = AttrVal( $name, 'htmltitle', '' );
    my $htmltitleclass = AttrVal( $name, 'htmltitleclass', '' );
    my $attr;

    if ( AttrVal( $name, 'htmlattr', 'none' ) ne 'none' ) {
        $attr = AttrVal( $name, 'htmlattr', '' );
    }
    else {
        $attr = 'width="100%"';
    }

    if ( ReadingsVal( $name, 'WarnCount', '' ) != 0 ) {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block" '
          . $attr
          . '><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';

        if ( $htmlsequence eq 'descending' ) {
            for (
                my $i = ReadingsVal( $name, 'WarnCount', '' ) - 1 ;
                $i >= 0 ;
                $i--
              )
            {
                $ret .= UWZHtmlFrame( $hash, 'Warn_' . $i, $attr, 0 );
            }
        }
        else {
            for ( my $i = 0 ;
                $i < ReadingsVal( $name, 'WarnCount', '' ) ; $i++ )
            {
                $ret .= UWZHtmlFrame( $hash, 'Warn_' . $i, $attr, 0 );
            }
        }
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';

    }
    else {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block wide" width="600px"><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';
        $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;">';

        # language by AttrVal
        if ( contains_string($hash->{CountryCode},('DE','AT','CH')) ) {
            $ret .= '<b>Keine Warnungen</b>';
        }
        elsif ( $hash->{CountryCode} eq 'NL' ) {
            $ret .= '<b>Geen waarschuwingen</b>';
        }
        elsif ( $hash->{CountryCode} eq 'FR' ) {
            $ret .= '<b>Aucune alerte</b>';
        }
        else {
            $ret .= '<b>No Warnings</b>';
        }

        # end language by AttrVal
        $ret .= '</td></tr>';
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
    }

    return $ret;
}

#####################################
sub UWZAsHtmlFP {
    my $name = shift;

    my $tablewidth = ReadingsVal( $name, 'WarnCount', '' ) * 80;
    my $htmlsequence   = AttrVal( $name, 'htmlsequence',   'none' );
    my $htmltitle      = AttrVal( $name, 'htmltitle',      '' );
    my $htmltitleclass = AttrVal( $name, 'htmltitleclass', '' );
    my $ret            = '';

    $ret .=
        '<table class="uwz-fp" style="width:'
      . $tablewidth
      . 'px"><tr><th class="'
      . $htmltitleclass
      . '" colspan="'
      . ReadingsVal( $name, 'WarnCount', 'none' ) . '">'
      . $htmltitle
      . '</th></tr>';
    $ret .= '<tr>';

    if ( $htmlsequence eq 'descending' ) {
        for (
            my $i = ReadingsVal( $name, 'WarnCount', '' ) - 1 ;
            $i >= 0 ;
            $i--
          )
        {
            $ret .=
                '<td class="uwzIcon"><img width="80px" src="'
              . ReadingsVal( $name, 'Warn_' . $i . '_IconURL', '' )
              . '"></td>';
        }
    }
    else {
        for ( my $i = 0 ; $i < ReadingsVal( $name, 'WarnCount', '' ) ; $i++ ) {
            $ret .=
                '<td class="uwzIcon"><img width="80px" src="'
              . ReadingsVal( $name, 'Warn_' . $i . '_IconURL', '' )
              . '"></td>';
        }
    }
    $ret .= '</tr>';
    $ret .= '</table>';

    return $ret;
}

#####################################
sub UWZAsHtmlMovie {
    my $name = shift;
    my $land = shift;

    my $url  = Map2Movie($land);
    my $hash = $defs{$name};

    my $ret = '<table><tr><td>';

    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even"><td>';

    if ( defined($url) ) {
        $ret .= '<video controls="controls">';
        $ret .= '<source src="' . $url . '" type="video/mp4">';
        $ret .= '</video>';

    }
    else {
        # language by AttrVal
        if ( contains_string($hash->{CountryCode} ,('DE','AT','CH')) ) {
            $ret .= 'unbekannte Landbezeichnung';
        }
        elsif ( $hash->{CountryCode} eq 'NL' ) {
            $ret .= 'Onbekende landcode';
        }
        elsif ( $hash->{CountryCode} eq 'FR' ) {
            $ret .= 'code de pays inconnu';
        }
        else {
            $ret .= 'unknown movie setting';
        }

        # end language by AttrVal
    }

    $ret .= '</td></tr></table></td></tr>';
    $ret .= '</table>';

    return $ret;
}

#####################################
sub UWZAsHtmlKarteLand {
    my $name = shift;
    my $land = shift;

    my $url  = Map2Image($land);
    my $hash = $defs{$name};

    my $ret = '<table><tr><td>';

    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even"><td>';

    if ( defined($url) ) {
        $ret .= '<img src="' . $url . '">';

    }
    else {
        # language by AttrVal
        if ( contains_string($hash->{CountryCode},('DE','AT','CH')) ) {
            $ret .= 'unbekannte Landbezeichnung';
        }
        elsif ( $hash->{CountryCode} eq 'NL' ) {
            $ret .= 'onbekende landcode';
        }
        elsif ( $hash->{CountryCode} eq 'FR' ) {
            $ret .= 'code de pays inconnu';
        }
        else {
            $ret .= 'unknown map setting';
        }

        # end language by AttrVal
    }

    $ret .= '</td></tr></table></td></tr>';
    $ret .= '</table>';

    return $ret;
}

#####################################
sub UWZHtmlFrame {
    my ( $hash, $readingStart, $attr, $parm ) = @_;

    my $ret  = '';
    my $name = $hash->{NAME};
    $ret .=
        '<tr><td class="uwzIcon" style="vertical-align:top;"><img src="'
      . ReadingsVal( $name, $readingStart . '_IconURL', '' )
      . '"></td>';
    $ret .=
        '<td class="uwzValue"><b>'
      . ReadingsVal( $name, $readingStart . '_ShortText', '' )
      . '</b><br><br>';
    $ret .= ReadingsVal( $name, $readingStart . '_LongText', '' ) . '<br><br>'
      if ($parm);

    $ret .= UWZHtmlTimestamp( $hash, $readingStart . '_Start', $attr );
    $ret .= UWZHtmlTimestamp( $hash, $readingStart . '_End',   $attr );
    $ret .= '</tr></table>';
    $ret .= '</td></tr>';

    return $ret;
}

#####################################
sub UWZHtmlTimestamp {

    my @DEText = qw(Anfang: Ende: Uhr);
    my @NLText = qw(Begin: Einde: uur);
    my @FRText = ( "Valide à partir du:", "Jusqu\'au:", "heure" );
    my @ENText = qw(Start: End: hour);

    my $hash    = shift;
    my $reading = shift;
    my $attr    = shift;

    my $ret;
    my $StartEnd = '';
    my $name     = $hash->{NAME};

    if ( substr( $reading, 7, 1 ) eq 'S' ) {
        $StartEnd = 0;
        $ret .= '<table ' . $attr . '><tr><th></th><th></th></tr><tr>';
    }
    else { $StartEnd = 1; }

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime( ReadingsVal( $name, $reading, '' ) );

    if ( length($hour) == 1 ) { $hour = "0$hour"; }
    if ( length($min) == 1 )  { $min  = "0$min"; }

    # language by AttrVal
    if ( contains_string($hash->{CountryCode},('DE','AT','CH')) ) {
        $ret .=
            "<td><b>$DEText[$StartEnd]</b></td><td>"
          . "$DEweekdays[$wday], $mday $DEmonths[$mon] "
          . ( 1900 + $year )
          . " $hour:$min "
          . "$DEText[2]</td>";
    }
    elsif ( $hash->{CountryCode} eq 'NL' ) {
        $ret .=
            "<td><b>$NLText[$StartEnd]</b></td><td>"
          . "$NLweekdays[$wday], $mday $NLmonths[$mon] "
          . ( 1900 + $year )
          . " $hour:$min "
          . "$NLText[2]</td>";
    }
    elsif ( $hash->{CountryCode} eq 'FR' ) {
        $ret .=
            "<td><b>$FRText[$StartEnd]</b></td><td>"
          . "$FRweekdays[$wday], $mday $FRmonths[$mon] "
          . ( 1900 + $year )
          . " $hour:$min "
          . "$FRText[2]</td>";
    }
    else {
        $ret .=
            "<td><b>$ENText[$StartEnd]</b></td><td>"
          . "$ENweekdays[$wday], $mday $ENmonths[$mon] "
          . ( 1900 + $year )
          . " $hour:$min "
          . "$ENText[2]</td>";
    }

    return $ret;
}

#####################################
sub GetSeverityColor {
    my $name       = shift;
    my $uwzlevel   = shift;
    my $alertcolor = '';

    my %UWZSeverity = (
        '0' => 'gruen',
        '1' => 'orange',
        '2' => 'gelb',
        '3' => 'orange',
        '4' => 'rot',
        '5' => 'violett'
    );

    return $UWZSeverity{$uwzlevel};
}

#####################################
sub GetUWZLevel {
    my $name     = shift;
    my $warnname = shift;

    my @alert = split( /_/, $warnname );

    if ( $alert[0] eq 'notice' ) {
        return '1';
    }
    elsif ( $alert[1] eq 'forewarn' ) {
        return '2';
    }
    else {

        my %UWZSeverity = (
            'green'  => '0',
            'yellow' => '2',
            'orange' => '3',
            'red'    => '4',
            'violet' => '5'
        );

        return $UWZSeverity{ $alert[2] };
    }

    return;
}

#####################################
sub IntervalAtWarnLevel {
    my $hash = shift;

    my $name        = $hash->{NAME};
    my $warnLevel   = ReadingsVal( $name, 'WarnUWZLevel', 0 );
    my @valuestring = split( ',', AttrVal( $name, 'intervalAtWarnLevel', '' ) );
    my %warnLevelInterval;

    readingsSingleUpdate( $hash, 'currentIntervalMode', 'warn', 0 );

    foreach (@valuestring) {

        my @values = split( '=', $_ );
        $warnLevelInterval{ $values[0] } = $values[1];
    }

    if ( defined( $warnLevelInterval{$warnLevel} )
        && $hash->{INTERVALWARN} != $warnLevelInterval{$warnLevel} )
    {

        $hash->{INTERVALWARN} = $warnLevelInterval{$warnLevel};

        RemoveInternalTimer($hash);
        InternalTimer( gettimeofday() + $hash->{INTERVALWARN},
            'UWZ_Start', $hash );

        Log $hash, 4,
          "restart internal timer with interval $hash->{INTERVALWARN}";

    }
    else {

        RemoveInternalTimer($hash);
        InternalTimer( gettimeofday() + $hash->{INTERVALWARN},
            "UWZ_Start", $hash );

        Log $hash, 4,
          "restart internal timer with interval $hash->{INTERVALWARN}";
    }

    return;
}

#####################################
##
##      UWZ Helper Functions
##
#####################################

sub UWZSearchLatLon {
    my $name = shift;
    my $loc  = shift;

    my $err_log = '';
    my $url =
'https://alertspro.geoservice.meteogroup.de/weatherpro/SearchFeed.php?search='
      . $loc;
    my $agent = LWP::UserAgent->new(
        env_proxy         => 1,
        keep_alive        => 1,
        protocols_allowed => ['http'],
        timeout           => 10
    );
    my $request = HTTP::Request->new( GET => $url );
    my $response = $agent->request($request);
    $err_log = 'Can\'t get ' . $url . ' -- ' . $response->status_line
      if ( !$response->is_success );

    if ( $err_log ne '' ) {
        print 'Error|Error ' . $response->status_line;
    }

    use XML::Simple qw(:strict);
    use Encode qw(decode encode);

    my $uwzxmlparser = XML::Simple->new();
    my $search       = $uwzxmlparser->XMLin(
        $response->content,
        KeyAttr    => { 'city' => 'id' },
        ForceArray => ['city']
    );

    my $ret = '<html><table><tr><td>';

    $ret .= '<table class="block wide">';

    $ret .= '<tr class="even">';
    $ret .= '<td><b>city</b></td>';
    $ret .= '<td><b>country</b></td>';
    $ret .= '<td><b>latitude</b></td>';
    $ret .= '<td><b>longitude</b></td>';
    $ret .= '</tr>';

    foreach my $locres ( $search->{cities}->{city} ) {
        my $linecount = 1;
        while ( my ( $key, $value ) = each(%$locres) ) {
            if ( $linecount % 2 == 0 ) {
                $ret .= '<tr class="even">';
            }
            else {
                $ret .= '<tr class="odd">';
            }
            $ret .= '<td>' . encode( 'utf-8', $value->{'name'} ) . '</td>';
            $ret .= '<td>' . $value->{'country-name'} . '</td>';
            $ret .= '<td>' . $value->{'latitude'} . '</td>';
            $ret .= '<td>' . $value->{'longitude'} . '</td>';

            my $aHref =
                '<a href="/fhem?cmd=get%20'
              . $name
              . '%20AreaID%20'
              . $value->{'latitude'}
              . ','
              . $value->{'longitude'}
              . $::FW_CSRF
              . '">Get AreaID</a>';

            $ret .= '<td>' . $aHref . '</td>';
            $ret .= '</tr>';
            $linecount++;
        }
    }

    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;
}

#####################################
sub UWZSearchAreaID {
    my $lat = shift;
    my $lon = shift;

    my $err_log = '';
    my $url =
'https://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=lookupCoord&lat='
      . $lat . '&lon='
      . $lon;
    my $agent = LWP::UserAgent->new(
        env_proxy         => 1,
        keep_alive        => 1,
        protocols_allowed => ['http'],
        timeout           => 10
    );
    my $request = HTTP::Request->new( GET => $url );
    my $response = $agent->request($request);
    $err_log = "Can't get $url -- " . $response->status_line
      if ( !$response->is_success );

    if ( $err_log ne '' ) {
        print "Error|Error " . $response->status_line;
    }
    use JSON;
    my @perl_scalar = @{ JSON->new->utf8->decode( $response->content ) };

    my $AreaType = $perl_scalar[0]->{'AREA_TYPE'};
    my $CC       = substr $perl_scalar[0]->{'AREA_ID'}, 3, 2;
    my $AreaID   = substr $perl_scalar[0]->{'AREA_ID'}, 5, 5;

    if ( $AreaType eq 'UWZ' ) {
        my $ret =
'<html>Please use the following statement to define Unwetterzentrale for your location:<br /><br />';
        $ret .= '<table width=100%><tr><td>';
        $ret .= '<table class="block wide">';
        $ret .= '<tr class="even">';
        $ret .=
"<td height=100><center><b>define Unwetterzentrale UWZ $CC $AreaID 3600</b></center></td>";
        $ret .= '</tr>';
        $ret .= '</table>';
        $ret .= '</td></tr></table>';

        $ret .= '<br />';
        $ret .=
'You can also use weblinks to add weathermaps. For a list of possible Weblinks see Commandref. For example to add the Europe Map use:<br />';

        $ret .= '<table width=100%><tr><td>';
        $ret .= '<table class="block wide">';
        $ret .= '<tr class="even">';
        $ret .=
"<td height=100><center>define UWZ_Map_Europe weblink htmlCode { UWZAsHtmlKarteLand('Unwetterzentrale','europa') }</center></td>";
        $ret .= '</tr>';
        $ret .= '</table>';
        $ret .= '</td></tr></table>';

        $ret .= '</html>';

        return $ret;
    }
    else {
        return 'Sorry, nothing found or not implemented';
    }

    return;
}

#####################################
1;

=pod

=item device
=item summary       extracts thunderstorm warnings from unwetterzentrale.de
=item summary_DE    extrahiert Unwetterwarnungen von unwetterzentrale.de

=begin html

<a name="UWZ"></a>
<h3>UWZ</h3>
<ul>
   <a name="UWZdefine"></a>
   This modul extracts thunderstorm warnings from <a href="https://www.unwetterzentrale.de">www.unwetterzentrale.de</a>.
   <br/>
   Therefore the same interface is used as the Android App <a href="https://www.alertspro.com">Alerts Pro</a> does.
   A maximum of 10 thunderstorm warnings will be served.
   Additional the module provides a few functions to create HTML-Templates which can be used with weblink.
   <br>
   <i>The following Perl-Modules are used within this module: HTTP::Request, LWP::UserAgent, JSON, Encode::Guess und HTML::Parse</i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; UWZ [CountryCode] [AreaID] [INTERVAL]</code>
      <br><br><br>
      Example:
      <br>
      <code>
        define Unwetterzentrale UWZ UK 08357 1800<br>
        attr Unwetterzentrale download 1<br>
        attr Unwetterzentrale humanreadable 1<br>
        attr Unwetterzentrale maps eastofengland unitedkingdom<br><br>
        define UnwetterDetails weblink htmlCode {FHEM::UWZ::UWZAsHtml("Unwetterzentrale")}<br>
        define UnwetterMapE_UK weblink htmlCode {FHEM::UWZ::UWZAsHtmlKarteLand("Unwetterzentrale","eastofengland")}<br>
        define UnwetterLite weblink htmlCode {FHEM::UWZ::UWZAsHtmlLite("Unwetterzentrale")}
        define UnwetterMovie weblink htmlCode {FHEM::UWZ::UWZAsHtmlMovie("Unwetterzentrale","clouds-precipitation-uk")}
      </code>
      <br>&nbsp;

      <li><code>[CountryCode]</code>
         <br>
         Possible values: DE, AT, CH, UK, ...<br/>
         (for other countries than germany use SEARCH for CountryCode to start device in search mode)
      </li><br>
      <li><code>[AreaID]</code>
         <br>
         For Germany you can use the postalcode, other countries use SEARCH for CountryCode to start device in search mode. 
         <br>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Defines the refresh interval. The interval is defined in seconds, so an interval of 3600 means that every hour a refresh will be triggered onetimes. 
         <br>
      </li><br>

      <br><br><br>
      Example Search-Mode:
      <br>
      <code>
        define Unwetterzentrale UWZ SEARCH<br>
      </code>
      <br>
      now get the AreaID for your location (example shows london):
      <br>
      <code>
        get Unwetterzentrale SearchAreaID London<br>
      </code>
      <br>
      now redefine your device with the outputted CountryCode and AreaID.
      <br>

      <br>&nbsp;


   </ul>
   <br>

   <a name="UWZget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; soil-frost</code>
         <br>
         give info about current soil frost (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; extremfrost</code>
         <br>
         give info about current frost (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; thunderstorm</code>
         <br>
         give info about current thunderstorm (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; glaze</code>
         <br>
         give info about current glaze (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; glazed-rain</code>
         <br>
         give info about current freezing rain (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; hail</code>
         <br>
         give info about current hail (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; heat</code>
         <br>
         give info about current heat (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; rain</code>
         <br>
         give info about current rain (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; snow</code>
         <br>
         give info about current snow (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; storm</code>
         <br>
         give info about current storm (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; forest-fire</code>
         <br>
         give info about current forest fire (active|inactive).
      </li><br>

   </ul>  
  
   <br>

   <b>Get (Search-Mode)</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; SearchAreaID &lt;city&gt;</code>
         <br>
         Get AreaID coresponnding to entered location.
      </li><br>

   </ul>  
  
   <br>



   <a name="UWZset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Executes an imediate update of thunderstorm warnings.
      </li><br>
   </ul>  
  
   <br>
   <a name="UWZattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>download</code>
         <br>
         Download maps during update (0|1). 
         <br>
      </li>
      <li><code>savepath</code>
         <br>
         Define where to store the map png files (default: /tmp/). 
         <br>
      </li>
      <li><code>maps</code>
         <br>
         Define the maps to download space seperated. For possible values see <code>UWZAsHtmlKarteLand</code>.
         <br>
      </li>
      <li><code>humanreadable</code>
         <br>
         Add additional Readings Warn_?_Start_Date, Warn_?_Start_Time, Warn_?_End_Date and Warn_?_End_Time containing the coresponding timetamp in a human readable manner. Additionally Warn_?_uwzLevel_Str and Warn_?_Type_Str will be added to device readings (0|1).
         <br>
      </li>
      <li><code>lang</code>
         <br>
         Overwrite requested language for short and long warn text. (de|en|it|fr|es|..). 
         <br>
      </li>
      <li><code>sort_readings_by</code>
         <br>
         define how readings will be sortet (start|severity|creation).  
         <br>
      </li>
      <li><code>htmlsequence</code>
         <br>
         define warn order of html output (ascending|descending). 
         <br>
      </li>
      <li><code>htmltitle</code>
         <br>
          title / header for the html ouput
          <br>
       </li>
       <li><code>htmltitleclass</code>
          <br>
          css-Class of title / header for the html ouput
          <br>
       </li>
      <li><code>localiconbase</code>
         <br>
         define baseurl to host your own thunderstorm warn pics (filetype is png). 
         <br>
      </li>
      <li><code>intervalAtWarnLevel</code>
         <br>
         define the interval per warnLevel. Example: 2=1800,3=900,4=300
         <br>
      </li>



      <br>
   </ul>  

   <br>

   <a name="UWZreading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>Warn_</b><i>0|1|2|3...|9</i><b>_...</b> - active warnings</li>
      <li><b>WarnCount</b> - warnings count</li>
      <li><b>WarnUWZLevel</b> - total warn level </li>
      <li><b>WarnUWZLevel_Color</b> - total warn level color</li>
      <li><b>WarnUWZLevel_Str</b> - total warn level string</li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMin</b> - minimum altitude for warning </li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMax</b> - maximum altitude for warning </li>
      <li><b>Warn_</b><i>0</i><b>_EventID</b> - warning EventID </li>
      <li><b>Warn_</b><i>0</i><b>_Creation</b> - warning creation </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Date</b> - warning creation datum </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Time</b> - warning creation time </li>
      <li><b>currentIntervalMode</b> - default/warn, Interval is read from INTERVAL or INTERVALWARN Internal</li>
      <li><b>Warn_</b><i>0</i><b>_Start</b> - begin of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Date</b> - start date of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Time</b> - start time of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End</b> - end of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End_Date</b> - end date of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End_Time</b> - end time of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Severity</b> - Severity of thunderstorm (0 no thunderstorm, 4, 7, 11, .. heavy thunderstorm)</li>
      <li><b>Warn_</b><i>0</i><b>_Hail</b> - warning contains hail</li>
      <li><b>Warn_</b><i>0</i><b>_Type</b> - kind of thunderstorm</li>
      <li><b>Warn_</b><i>0</i><b>_Type_Str</b> - kind of thunderstorm (text)</li>
      <ul>
        <li><b>1</b> - unknown</li>
        <li><b>2</b> - storm</li>
        <li><b>3</b> - snow</li>
        <li><b>4</b> - rain</li>
        <li><b>5</b> - frost</li>
        <li><b>6</b> - forest fire</li>
        <li><b>7</b> - thunderstorm</li>
        <li><b>8</b> - glaze</li>
        <li><b>9</b> - heat</li>
        <li><b>10</b> - freezing rain</li>
        <li><b>11</b> - soil frost</li>
      </ul>
      <li><b>Warn_</b><i>0</i><b>_uwzLevel</b> - Severity of thunderstorm (0-5)</li>
      <li><b>Warn_</b><i>0</i><b>_uwzLevel_Str</b> - Severity of thunderstorm (text)</li>
      <li><b>Warn_</b><i>0</i><b>_levelName</b> - Level Warn Name</li>
      <li><b>Warn_</b><i>0</i><b>_ShortText</b> - short warn text</li>
      <li><b>Warn_</b><i>0</i><b>_LongText</b> - detailed warn text</li>
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - cumulated URL to display warn-icons from <a href="https://www.unwetterzentrale.de">www.unwetterzentrale.de</a></li>
   </ul>
   <br>

   <a name="UWZweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      With the additional implemented functions <code>UWZAsHtml, UWZAsHtmlLite, UWZAsHtmlFP, UWZAsHtmlKarteLand and UWZAsHtmlMovie</code> HTML-Code will be created to display warnings and weathermovies, using weblinks.
      <br><br><br>
      Example:
      <br>
      <li><code>define UnwetterDetailiert weblink htmlCode {FHEM::UWZ::UWZAsHtml("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {FHEM::UWZ::UWZAsHtmlLite("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {FHEM::UWZ::UWZAsHtmlFP("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {FHEM::UWZ::UWZAsHtmlKarteLand("Unwetterzentrale","Bayern")}</code></li>
      <ul>
        <li>The second parameter should be one of:
        <ul>
          <li>europa</li>
          <br/>
          <li>deutschland</li>
          <li>deutschland-small</li>
          <li>niedersachsen</li>
          <li>bremen</li>
          <li>bayern</li>
          <li>schleswig-holstein</li>
          <li>hamburg</li>
          <li>mecklenburg-vorpommern</li>
          <li>sachsen</li>
          <li>sachsen-anhalt</li>
          <li>nordrhein-westfalen</li>
          <li>thueringen</li>
          <li>rheinland-pfalz</li>
          <li>saarland</li>
          <li>baden-wuerttemberg</li>
          <li>hessen</li>
          <li>brandenburg</li>
          <li>berlin</li>
          <br/>
          <li>oesterreich</li>
          <li>burgenland</li>
          <li>kaernten</li>
          <li>niederoesterreich</li>
          <li>oberoesterreich</li>
          <li>salzburg</li>
          <li>steiermark</li>
          <li>tirol</li>
          <li>vorarlberg</li>
          <li>wien</li>
          <br/>
          <li>schweiz</li>
          <li>aargau</li>
          <li>appenzell_ausserrhoden</li>
          <li>appenzell_innerrhoden</li>
          <li>basel_landschaft</li>
          <li>basel_stadt</li>
          <li>bern</li>
          <li>fribourg</li>
          <li>geneve</li>
          <li>glarus</li>
          <li>graubuenden</li>
          <li>jura</li>
          <li>luzern</li>
          <li>neuchatel</li>
          <li>nidwalden</li>
          <li>obwalden</li>
          <li>schaffhausen</li>
          <li>schwyz</li>
          <li>solothurn</li>
          <li>stgallen</li>
          <li>ticino</li>
          <li>thurgau</li>
          <li>uri</li>
          <li>waadt</li>
          <li>wallis</li>
          <li>zug</li>
          <li>zuerich</li>
          <br/>
          <li>liechtenstein</li>
          <br/>
          <li>belgique</li>
          <br/>
          <li>denmark</li>
          <br/>
          <li>finnland</li>
          <br/>
          <li>france</li>
          <li>alsace</li>
          <li>aquitaine</li>
          <li>basse-normandie</li>
          <li>bretagne</li>
          <li>champagne-ardenne</li>
          <li>franche-comte</li>
          <li>haute-normandie</li>
          <li>ile-de-france</li>
          <li>languedoc-roussillon</li>
          <li>limousin</li>
          <li>lorraine</li>
          <li>bourgogne</li>
          <li>centre</li>
          <li>midi-pyrenees</li>
          <li>nord-pas-de-calais</li>
          <li>pays-de-la-loire</li>
          <li>picardie</li>
          <li>poitou-charentes</li>
          <li>provence-alpes-cote-dazur</li>
          <li>rhone-alpes</li>
          <br/>
          <li>letzebuerg</li>
          <br/>
          <li>nederland</li>
          <li>drenthe</li>
          <li>flevoland</li>
          <li>friesland</li>
          <li>gelderland</li>
          <li>groningen</li>
          <li>limburg</li>
          <li>noordbrabant</li>
          <li>noordholland</li>
          <li>overijssel</li>
          <li>utrecht</li>
          <li>zeeland</li>
          <li>zuidholland</li>
          <br/>
          <li>norwegen</li>
          <br/>
          <li>portugal</li>
          <br/>
          <li>sverige</li>
          <br/>
          <li>espana</li>
          <br/>
          <li>unitedkingdom</li>
          <li>eastofengland</li>
          <li>eastmidlands</li>
          <li>london</li>
          <li>northeastengland</li>
          <li>northernireland</li>
          <li>northwestengland</li>
          <li>scotland</li>
          <li>southeastengland</li>
          <li>southwestengland</li>
          <li>wales</li>
          <li>westmidlands</li>
          <li>yorkshireandthehumber</li>
          <br/>
          <li>isobaren1</li>
          <li>isobaren2</li>
          <li>isobaren3</li>
        </ul>          
        </li>
      </ul>
      <li><code>define UnwetterKarteMovie weblink htmlCode {FHEM::UWZ::UWZAsHtmlMovie("Unwetterzentrale","currents")}</code></li>
      <ul>
        <li>The second parameter should be one of:
        <ul>
          <li>niederschlag-wolken</li>
          <li>stroemung</li>
          <li>temperatur</li>
          <br/>
          <li>niederschlag-wolken-de</li>
          <li>stroemung-de</li>
          <br/>
          <li>niederschlag-wolken-ch</li>
          <li>stroemung-ch</li>
          <br/>
          <li>niederschlag-wolken-at</li>
          <li>stroemung-at</li>
          <br/>
          <li>neerslag-wolken-nl</li>
          <li>stroming-nl</li>
          <br/>
          <li>nuages-precipitations-fr</li>
          <li>courants-fr</li>
          <br/>
          <li>clouds-precipitation-uk</li>
          <li>currents-uk</li>
          <br/>
        </ul>          
        </li>
      </ul>

      <br/><br/>
   </ul>
   <br>
 

</ul> 



=end html

=begin html_DE

<a name="UWZ"></a>
<h3>UWZ</h3> 
<ul>
   <a name="UWZdefine"></a>
   Das Modul extrahiert Unwetterwarnungen von <a href="https://www.unwetterzentrale.de">www.unwetterzentrale.de</a>.
   <br/>
   Hierfür wird die selbe Schnittstelle verwendet die auch die Android App <a href="https://www.alertspro.com">Alerts Pro</a> nutzt.
   Es werden maximal 10 Standortbezogene Unwetterwarnungen zur Verfügung gestellt.
   Weiterhin verfügt das Modul über HTML-Templates welche als weblink verwendet werden können.
   <br>
   <i>Es nutzt die Perl-Module HTTP::Request, LWP::UserAgent, JSON, Encode::Guess und HTML::Parse</i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; UWZ [L&auml;ndercode] [Postleitzahl] [INTERVAL]</code>
      <br><br><br>
      Beispiel:
      <br>
      <code>define Unwetterzentrale UWZ DE 86405 3600</code>
      <br>&nbsp;

      <li><code>[L&auml;ndercode]</code>
         <br>
         M&ouml;gliche Werte: DE, AT, CH, SEARCH, ...<br/>
         (f&uuml;r ander L&auml;nder als Deutschland bitte den SEARCH Parameter nutzen um die AreaID zu ermitteln.)
      </li><br>
      <li><code>[Postleitzahl/AreaID]</code>
         <br>
         Die Postleitzahl/AreaID des Ortes für den Unwetterinformationen abgefragt werden sollen. 
         <br>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Definiert das Interval zur aktualisierung der Unwetterwarnungen. Das Interval wird in Sekunden angegeben, somit aktualisiert das Modul bei einem Interval von 3600 jede Stunde 1 mal. 
         <br>
      </li><br>
   </ul>
   <br>

   <a name="UWZget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; Bodenfrost</code>
         <br>
         Gibt aus ob aktuell eine Bodenfrostwarnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Extremfrost</code>
         <br>
         Gibt aus ob aktuell eine Extremfrostwarnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Gewitter</code>
         <br>
         Gibt aus ob aktuell eine Gewitter Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Glaette</code>
         <br>
         Gibt aus ob aktuell eine Glaettewarnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Glatteisregen</code>
         <br>
         Gibt aus ob aktuell eine Glatteisregen Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Hagel</code>
         <br>
         Gibt aus ob aktuell eine Hagel Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Hitze</code>
         <br>
         Gibt aus ob aktuell eine Hitze Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Regen</code>
         <br>
         Gibt aus ob aktuell eine Regen Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Schneefall</code>
         <br>
         Gibt aus ob aktuell eine Schneefall Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Sturm</code>
         <br>
         Gibt aus ob aktuell eine Sturm Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Waldbrand</code>
         <br>
         Gibt aus ob aktuell eine Waldbrand Warnung besteht (active|inactive).
      </li><br>


   </ul>  
  
   <br>

   <b>Get (Search-Mode)</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; SearchAreaID &lt;gesuchte_stadt&gt;</code>
         <br>
         Gibt die AreaID zum eingegebenen Ort aus.
      </li><br>

   </ul>  
  
   <br>



   <a name="UWZset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Startet sofort ein neues Auslesen der Unwetterinformationen.
      </li><br>
   </ul>  
  
   <br>

   <a name="UWZattr"></a>
   <b>Attribute</b>
   <ul>
      <br>
      <li><code>download</code>
         <br>
         Download Unwetterkarten während des updates (0|1).
         <br>
      </li>
      <li><code>savepath</code>
         <br>
         Pfad zum speichern der Karten (default: /tmp/). 
         <br>
      </li>
      <li><code>maps</code>
         <br>
         Leerzeichen separierte Liste der zu speichernden Karten. Für mögliche Karten siehe <code>UWZAsHtmlKarteLand</code>.
         <br>
      </li>
      <li><code>humanreadable</code>
         <br>
     Anzeige weiterer Readings Warn_?_Start_Date, Warn_?_Start_Time, Warn_?_End_Date, Warn_?_End_Time. Diese Readings enthalten aus dem Timestamp kalkulierte Datums/Zeit Angaben. Weiterhin werden folgende Readings aktivier: Warn_?_Type_Str und Warn_?_uwzLevel_Str welche den Unwettertyp als auch das Unwetter-Warn-Level als Text ausgeben. (0|1) 
         <br>
      </li>
      <li><code>lang</code>
         <br>
         Umschalten der angeforderten Sprache für kurz und lange warn text. (de|en|it|fr|es|..). 
         <br>
      </li>
      <li><code>sort_readings_by</code>
         <br>
         Sortierreihenfolge der Warnmeldungen. (start|severity|creation).
         <br>
      </li>
      <li><code>htmlsequence</code>
         <br>
         Anzeigereihenfolge der html warnungen. (ascending|descending). 
         <br>
      </li>
      <li><code>htmltitle</code>
         <br>
         Titel / Ueberschrift der HTML Ausgabe 
         <br>
      </li>
      <li><code>htmltitleclass</code>
         <br>
         css-Class des Titels der HTML Ausgabe 
         <br>
      </li>
      <li><code>localiconbase</code>
         <br>
         BaseURL angeben um Warn Icons lokal zu hosten. (Dateityp ist png). 
         <br>
      </li>
      <li><code>intervalAtWarnLevel</code>
         <br>
         konfiguriert den Interval je nach WarnLevel. Beispiel: 2=1800,3=900,4=300
         <br>
      </li>

      <br>
   </ul>  

   <br>

   <a name="UWZreading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>Warn_</b><i>0|1|2|3...|9</i><b>_...</b> - aktive Warnmeldungen</li>
      <li><b>WarnCount</b> - Anzahl der aktiven Warnmeldungen</li>
      <li><b>WarnUWZLevel</b> - Gesamt Warn Level </li>
      <li><b>WarnUWZLevel_Color</b> - Gesamt Warn Level Farbe</li>
      <li><b>WarnUWZLevel_Str</b> - Gesamt Warn Level Text</li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMin</b> - minimum Höhe für Warnung </li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMax</b> - maximum Höhe für Warnung </li>
      <li><b>Warn_</b><i>0</i><b>_EventID</b> - EventID der Warnung </li>
      <li><b>Warn_</b><i>0</i><b>_Creation</b> - Warnungs Erzeugung </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Date</b> - Warnungs Erzeugungs Datum </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Time</b> - Warnungs Erzeugungs Zeit </li>
      <li><b>currentIntervalMode</b> - default/warn, aktuell Verwendeter Interval. Internal INTERVAL oder INTERVALWARN</li>
      <li><b>Warn_</b><i>0</i><b>_Start</b> - Begin der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Date</b> - Startdatum der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Time</b> - Startzeit der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_End</b> - Warn Ende</li>
      <li><b>Warn_</b><i>0</i><b>_End_Date</b> - Enddatum der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_End_Time</b> - Endzeit der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_Severity</b> - Schwere des Unwetters (0 kein Unwetter, 12 massives Unwetter)</li>
      <li><b>Warn_</b><i>0</i><b>_Hail</b> - Hagelwarnung (1|0)</li>
      <li><b>Warn_</b><i>0</i><b>_Type</b> - Art des Unwetters</li>
      <li><b>Warn_</b><i>0</i><b>_Type_Str</b> - Art des Unwetters (text)</li>
      <ul>
        <li><b>1</b> - unbekannt</li>
        <li><b>2</b> - Sturm/Orkan</li>
        <li><b>3</b> - Schneefall</li>
        <li><b>4</b> - Regen</li>
        <li><b>5</b> - Extremfrost</li>
        <li><b>6</b> - Waldbrandgefahr</li>
        <li><b>7</b> - Gewitter</li>
        <li><b>8</b> - Glätte</li>
        <li><b>9</b> - Hitze</li>
        <li><b>10</b> - Glatteisregen</li>
        <li><b>11</b> - Bodenfrost</li>
      </ul>
      <li><b>Warn_</b><i>0</i><b>_uwzLevel</b> - Unwetterwarnstufe (0-5)</li>
      <li><b>Warn_</b><i>0</i><b>_uwzLevel_Str</b> - Unwetterwarnstufe (text)</li>
      <li><b>Warn_</b><i>0</i><b>_levelName</b> - Level Warn Name</li>
      <li><b>Warn_</b><i>0</i><b>_ShortText</b> - Kurzbeschreibung der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_LongText</b> - Ausführliche Unwetterbeschreibung</li>
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - Kumulierte URL um Warnungs-Icon von <a href="https://www.unwetterzentrale.de">www.unwetterzentrale.de</a> anzuzeigen</li>
   </ul>
   <br>

   <a name="UWZweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      &Uuml;ber die Funktionen <code>UWZAsHtml, UWZAsHtmlLite, UWZAsHtmlFP, UWZAsHtmlKarteLand, UWZAsHtmlMovie</code> wird HTML-Code zur Warnanzeige und Wetterfilme über weblinks erzeugt.
      <br><br><br>
      Beispiele:
      <br>
      <li><code>define UnwetterDetailiert weblink htmlCode {FHEM::UWZ::UWZAsHtml("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {FHEM::UWZ::UWZAsHtmlLite("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {FHEM::UWZ::UWZAsHtmlFP("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {FHEM::UWZ::UWZAsHtmlKarteLand("Unwetterzentrale","Bayern")}</code></li>
      <ul>        
        <li>Der zweite Parameter kann einer der folgenden sein:
        <ul>      
          <li>europa</li>
          <br/>
          <li>deutschland</li>
          <li>deutschland-small</li>
          <li>niedersachsen</li>
          <li>bremen</li>
          <li>bayern</li>
          <li>schleswig-holstein</li>
          <li>hamburg</li>
          <li>mecklenburg-vorpommern</li>
          <li>sachsen</li>
          <li>sachsen-anhalt</li>
          <li>nordrhein-westfalen</li>
          <li>thueringen</li>
          <li>rheinland-pfalz</li>
          <li>saarland</li>
          <li>baden-wuerttemberg</li>
          <li>hessen</li>
          <li>brandenburg</li>
          <li>berlin</li>
          <br/>
          <li>oesterreich</li>
          <li>burgenland</li>
          <li>kaernten</li>
          <li>niederoesterreich</li>
          <li>oberoesterreich</li>
          <li>salzburg</li>
          <li>steiermark</li>
          <li>tirol</li>
          <li>vorarlberg</li>
          <li>wien</li>
          <br/>
          <li>schweiz</li>
          <li>aargau</li>
          <li>appenzell_ausserrhoden</li>
          <li>appenzell_innerrhoden</li>
          <li>basel_landschaft</li>
          <li>basel_stadt</li>
          <li>bern</li>
          <li>fribourg</li>
          <li>geneve</li>
          <li>glarus</li>
          <li>graubuenden</li>
          <li>jura</li>
          <li>luzern</li>
          <li>neuchatel</li>
          <li>nidwalden</li>
          <li>obwalden</li>
          <li>schaffhausen</li>
          <li>schwyz</li>
          <li>solothurn</li>
          <li>stgallen</li>
          <li>ticino</li>
          <li>thurgau</li>
          <li>uri</li>
          <li>waadt</li>
          <li>wallis</li>
          <li>zug</li>
          <li>zuerich</li>
          <br/>
          <li>liechtenstein</li>
          <br/>
          <li>belgique</li>
          <br/>
          <li>denmark</li>
          <br/>
          <li>finnland</li>
          <br/>
          <li>france</li>
          <li>alsace</li>
          <li>aquitaine</li>
          <li>basse-normandie</li>
          <li>bretagne</li>
          <li>champagne-ardenne</li>
          <li>franche-comte</li>
          <li>haute-normandie</li>
          <li>ile-de-france</li>
          <li>languedoc-roussillon</li>
          <li>limousin</li>
          <li>lorraine</li>
          <li>bourgogne</li>
          <li>centre</li>
          <li>midi-pyrenees</li>
          <li>nord-pas-de-calais</li>
          <li>pays-de-la-loire</li>
          <li>picardie</li>
          <li>poitou-charentes</li>
          <li>provence-alpes-cote-dazur</li>
          <li>rhone-alpes</li>
          <br/>
          <li>letzebuerg</li>
          <br/>
          <li>nederland</li>
          <li>drenthe</li>
          <li>flevoland</li>
          <li>friesland</li>
          <li>gelderland</li>
          <li>groningen</li>
          <li>limburg</li>
          <li>noordbrabant</li>
          <li>noordholland</li>
          <li>overijssel</li>
          <li>utrecht</li>
          <li>zeeland</li>
          <li>zuidholland</li>
          <br/>
          <li>norwegen</li>
          <br/>
          <li>portugal</li>
          <br/>
          <li>sverige</li>
          <br/>
          <li>espana</li>
          <br/>
          <li>unitedkingdom</li>
          <li>eastofengland</li>
          <li>eastmidlands</li>
          <li>london</li>
          <li>northeastengland</li>
          <li>northernireland</li>
          <li>northwestengland</li>
          <li>scotland</li>
          <li>southeastengland</li>
          <li>southwestengland</li>
          <li>wales</li>
          <li>westmidlands</li>
          <li>yorkshireandthehumber</li>
          <br/>
          <li>isobaren1</li>
          <li>isobaren2</li>
          <li>isobaren3</li>
        </ul>          
        </li>
      </ul>
      <li><code>define UnwetterKarteMovie weblink htmlCode {FHEM::UWZ::UWZAsHtmlMovie("Unwetterzentrale","niederschlag-wolken-de")}</code></li>
      <ul>
        <li>Der zweite Parameter kann einer der folgenden sein:
        <ul>
          <li>niederschlag-wolken</li>
          <li>stroemung</li>
          <li>temperatur</li>
          <br/>
          <li>niederschlag-wolken-de</li>
          <li>stroemung-de</li>
          <br/>
          <li>niederschlag-wolken-ch</li>
          <li>stroemung-ch</li>
          <br/>
          <li>niederschlag-wolken-at</li>
          <li>stroemung-at</li>
          <br/>
          <li>neerslag-wolken-nl</li>
          <li>stroming-nl</li>
          <br/>
          <li>nuages-precipitations-fr</li>
          <li>courants-fr</li>
          <br/>
          <li>clouds-precipitation-uk</li>
          <li>currents-uk</li>
          <br/>
        </ul>          
        </li>
      </ul>


      <br/><br/>
   </ul>
   <br>
 

</ul>

=end html_DE

=for :application/json;q=META.json 77_UWZ.pm
{
  "abstract": "Module to extracts thunderstorm warnings from unwetterzentrale.de",
  "x_lang": {
    "de": {
      "abstract": "Modul zum anzeigen von Unwetterwarnungen von unwetterzentrale.de"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Unwetter",
    "Wetter",
    "Warnungen"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v3.1.0",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
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
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "JSON": 0,
        "Date::Parse": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut

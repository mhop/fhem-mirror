####################################################################################################
#
#  77_UWZ.pm
#
#  (c) 2015-2016 Tobias D. Oestreicher
#
#  Special thanks goes to comitters:
#       - Marko Oldenburg (leongaultier at gmail dot com)
#       - Hanjo (Forum) patch for sort by creation
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
#  $Id$
#
####################################################################################################
# also a thanks goes to hexenmeister
##############################################



package main;
use strict;
use feature qw/say switch/;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::lexical_subs','experimental::smartmatch';

my $missingModul;
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";
eval "use LWP::Simple;1" or $missingModul .= "LWP::Simple ";
eval "use HTTP::Request;1" or $missingModul .= "HTTP::Request ";
eval "use HTML::Parser;1" or $missingModul .= "HTML::Parser ";
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use Encode::Guess;1" or $missingModul .= "Encode::Guess ";
eval "use Text::Iconv;1" or $missingModul .= "Text::Iconv ";

require 'Blocking.pm';
require 'HttpUtils.pm';
use vars qw($readingFnAttributes);

use vars qw(%defs);
my $MODUL           = "UWZ";
my $version         = "1.8.0";




# Declare functions
sub UWZ_Log($$$);
sub UWZ_Map2Movie($$);
sub UWZ_Map2Image($$);
sub UWZ_Initialize($);
sub UWZ_Define($$);
sub UWZ_Undef($$);
sub UWZ_Set($@);
sub UWZ_Get($@);
sub UWZ_GetCurrent($@);
sub UWZ_GetCurrentHail($);
sub UWZ_JSONAcquire($$);
sub UWZ_Start($);
sub UWZ_Aborted($);
sub UWZ_Done($);
sub UWZ_Run($);
sub UWZAsHtml($;$);
sub UWZAsHtmlLite($;$);
sub UWZAsHtmlFP($;$);
sub UWZAsHtmlMovie($$);
sub UWZAsHtmlKarteLand($$);
sub UWZ_GetSeverityColor($$);
sub UWZ_GetUWZLevel($$);
sub UWZSearchLatLon($$);
sub UWZSearchAreaID($$);
sub UWZ_IntervalAtWarnLevel($);




my $countrycode = "DE";
my $plz = "77777";
my $uwz_alert_url = "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=de&areaID=UWZ" . $countrycode . $plz;



########################################
sub UWZ_Log($$$) {

    my ( $hash, $loglevel, $text ) = @_;
    my $xline       = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub         = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/UWZ_//;

    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
    Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

########################################
sub UWZ_Map2Movie($$) {
    my $uwz_movie_url = "http://www.meteocentrale.ch/uploads/media/";
    my ( $hash, $smap ) = @_;
    my $lmap;

    $smap=lc($smap);

    ## Euro
    $lmap->{'niederschlag-wolken'}=$uwz_movie_url.'UWZ_EUROPE_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung'}=$uwz_movie_url.'UWZ_EUROPE_COMPLETE_stfi.mp4';
    $lmap->{'temperatur'}=$uwz_movie_url.'UWZ_EUROPE_COMPLETE_theta_E.mp4';

    ## DE
    $lmap->{'niederschlag-wolken-de'}=$uwz_movie_url.'UWZ_EUROPE_GERMANY_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-de'}=$uwz_movie_url.'UWZ_EUROPE_GERMANY_COMPLETE_stfi.mp4';

    ## CH
    $lmap->{'niederschlag-wolken-ch'}=$uwz_movie_url.'UWZ_EUROPE_SWITZERLAND_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-ch'}=$uwz_movie_url.'UWZ_EUROPE_SWITZERLAND_COMPLETE_stfi.mp4';

    ## AT
    $lmap->{'niederschlag-wolken-at'}=$uwz_movie_url.'UWZ_EUROPE_AUSTRIA_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-at'}=$uwz_movie_url.'UWZ_EUROPE_AUSTRIA_COMPLETE_stfi.mp4';

    ## UK
    $lmap->{'clouds-precipitation-uk'}=$uwz_movie_url.'UWZ_EUROPE_GREATBRITAIN_COMPLETE_niwofi.mp4';
    $lmap->{'currents-uk'}=$uwz_movie_url.'UWZ_EUROPE_GREATBRITAIN_COMPLETE_stfi.mp4';
    
    ## IT
    $lmap->{'niederschlag-wolken-it'}=$uwz_movie_url.'UWZ_EUROPE_ITALY_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-it'}=$uwz_movie_url.'UWZ_EUROPE_ITALY_COMPLETE_stfi.mp4';

    return $lmap->{$smap};
}

########################################
sub UWZ_Map2Image($$) {

    my $uwz_de_url = "http://www.unwetterzentrale.de/images/map/";
    my $uwz_at_url = "http://unwetter.wetteralarm.at/images/map/";
    my $uwz_ch_url = "http://alarm.meteocentrale.ch/images/map/";
    my $uwz_en_url = "http://warnings.severe-weather-centre.co.uk/images/map/";
    my $uwz_li_url = "http://alarm.meteocentrale.li/images/map/";
    my $uwz_be_url = "http://alarm.meteo-info.be/images/map/";
    my $uwz_dk_url = "http://alarm.vejrcentral.dk/images/map/";
    my $uwz_fi_url = "http://vaaratasot.saa-varoitukset.fi/images/map/";
    my $uwz_fr_url = "http://alerte.vigilance-meteo.fr/images/map/";
    my $uwz_lu_url = "http://alarm.meteozentral.lu/images/map/";
    my $uwz_nl_url = "http://alarm.noodweercentrale.nl/images/map/";
    my $uwz_no_url = "http://advarsler.vaer-sentral.no/images/map/";
    my $uwz_pt_url = "http://avisos.centrometeo.pt/images/map/";
    my $uwz_se_url = "http://varningar.vader-alarm.se/images/map/";
    my $uwz_es_url = "http://avisos.alertas-tiempo.es/images/map/";
    my $uwz_it_url = "http://allarmi.meteo-allerta.it/images/map/";


    my ( $hash, $smap ) = @_;
    my $lmap;
    
    $smap=lc($smap);

    ## Euro
    $lmap->{'europa'}=$uwz_de_url.'europe_index.png';

    ## DE
    $lmap->{'deutschland'}=$uwz_de_url.'deutschland_index.png';
    $lmap->{'deutschland-small'}=$uwz_de_url.'deutschland_preview.png';
    $lmap->{'niedersachsen'}=$uwz_de_url.'niedersachsen_index.png';
    $lmap->{'bremen'}=$uwz_de_url.'niedersachsen_index.png';
    $lmap->{'bayern'}=$uwz_de_url.'bayern_index.png';
    $lmap->{'schleswig-holstein'}=$uwz_de_url.'schleswig_index.png';
    $lmap->{'hamburg'}=$uwz_de_url.'schleswig_index.png';
    $lmap->{'mecklenburg-vorpommern'}=$uwz_de_url.'meckpom_index.png';
    $lmap->{'sachsen'}=$uwz_de_url.'sachsen_index.png';
    $lmap->{'sachsen-anhalt'}=$uwz_de_url.'sachsenanhalt_index.png';
    $lmap->{'nordrhein-westfalen'}=$uwz_de_url.'nrw_index.png';
    $lmap->{'thueringen'}=$uwz_de_url.'thueringen_index.png';
    $lmap->{'rheinland-pfalz'}=$uwz_de_url.'rlp_index.png';
    $lmap->{'saarland'}=$uwz_de_url.'rlp_index.png';
    $lmap->{'baden-wuerttemberg'}=$uwz_de_url.'badenwuerttemberg_index.png';
    $lmap->{'hessen'}=$uwz_de_url.'hessen_index.png';
    $lmap->{'brandenburg'}=$uwz_de_url.'brandenburg_index.png';
    $lmap->{'berlin'}=$uwz_de_url.'brandenburg_index.png';

    ## AT
    $lmap->{'oesterreich'}=$uwz_at_url.'oesterreich_index.png';
    $lmap->{'burgenland'}=$uwz_at_url.'burgenland_index.png';
    $lmap->{'kaernten'}=$uwz_at_url.'kaernten_index.png';
    $lmap->{'niederoesterreich'}=$uwz_at_url.'niederoesterreich_index.png';
    $lmap->{'oberoesterreich'}=$uwz_at_url.'oberoesterreich_index.png';
    $lmap->{'salzburg'}=$uwz_at_url.'salzburg_index.png';
    $lmap->{'steiermark'}=$uwz_at_url.'steiermark_index.png';
    $lmap->{'tirol'}=$uwz_at_url.'tirol_index.png';
    $lmap->{'vorarlberg'}=$uwz_at_url.'vorarlberg_index.png';
    $lmap->{'wien'}=$uwz_at_url.'wien_index.png';

    ## CH
    $lmap->{'schweiz'}=$uwz_ch_url.'schweiz_index.png';
    $lmap->{'aargau'}=$uwz_ch_url.'aargau_index.png';
    $lmap->{'appenzell_ausserrhoden'}=$uwz_ch_url.'appenzell_ausserrhoden_index.png';
    $lmap->{'appenzell_innerrhoden'}=$uwz_ch_url.'appenzell_innerrhoden_index.png';
    $lmap->{'basel_landschaft'}=$uwz_ch_url.'basel_landschaft_index.png';
    $lmap->{'basel_stadt'}=$uwz_ch_url.'basel_stadt_index.png';
    $lmap->{'bern'}=$uwz_ch_url.'bern_index.png';
    $lmap->{'fribourg'}=$uwz_ch_url.'fribourg_index.png';
    $lmap->{'geneve'}=$uwz_ch_url.'geneve_index.png';
    $lmap->{'glarus'}=$uwz_ch_url.'glarus_index.png';
    $lmap->{'graubuenden'}=$uwz_ch_url.'graubuenden_index.png';
    $lmap->{'jura'}=$uwz_ch_url.'jura_index.png';
    $lmap->{'luzern'}=$uwz_ch_url.'luzern_index.png';
    $lmap->{'neuchatel'}=$uwz_ch_url.'neuchatel_index.png';
    $lmap->{'nidwalden'}=$uwz_ch_url.'nidwalden_index.png';
    $lmap->{'obwalden'}=$uwz_ch_url.'obwalden_index.png';
    $lmap->{'schaffhausen'}=$uwz_ch_url.'schaffhausen_index.png';
    $lmap->{'schwyz'}=$uwz_ch_url.'schwyz_index.png';
    $lmap->{'solothurn'}=$uwz_ch_url.'solothurn_index.png';
    $lmap->{'stgallen'}=$uwz_ch_url.'stgallen_index.png';
    $lmap->{'ticino'}=$uwz_ch_url.'ticino_index.png';
    $lmap->{'thurgau'}=$uwz_ch_url.'thurgau_index.png';
    $lmap->{'uri'}=$uwz_ch_url.'uri_index.png';
    $lmap->{'waadt'}=$uwz_ch_url.'waadt_index.png';
    $lmap->{'wallis'}=$uwz_ch_url.'wallis_index.png';
    $lmap->{'zug'}=$uwz_ch_url.'zug_index.png';
    $lmap->{'zuerich'}=$uwz_ch_url.'zuerich_index.png';

    ## LI
    $lmap->{'liechtenstein'}=$uwz_li_url.'liechtenstein_index.png';

    ## UK
    $lmap->{'unitedkingdom'}=$uwz_en_url.'unitedkingdom_index.png';
    $lmap->{'eastofengland'}=$uwz_en_url.'eastofengland_index.png';
    $lmap->{'eastmidlands'}=$uwz_en_url.'eastmidlands-index.png';
    $lmap->{'london'}=$uwz_en_url.'london-index.png';
    $lmap->{'northeastengland'}=$uwz_en_url.'northeastengland-index.png';
    $lmap->{'northernireland'}=$uwz_en_url.'northernireland-index.png';
    $lmap->{'northwestengland'}=$uwz_en_url.'northwestengland-index.png';
    $lmap->{'scotland'}=$uwz_en_url.'scotland-index.png';
    $lmap->{'southeastengland'}=$uwz_en_url.'southeastengland-index.png';
    $lmap->{'southwestengland'}=$uwz_en_url.'southwestengland-index.png';
    $lmap->{'wales'}=$uwz_en_url.'wales-index.png';
    $lmap->{'westmidlands'}=$uwz_en_url.'westmidlands-index.png';
    $lmap->{'yorkshireandthehumber'}=$uwz_en_url.'yorkshireandthehumber-index.png';

    ## BE
    $lmap->{'belgique'}=$uwz_be_url.'belgique_index.png';

    ## DK
    $lmap->{'denmark'}=$uwz_dk_url.'denmark_index.png';

    ## FI
    $lmap->{'finnland'}=$uwz_fi_url.'finnland_index.png';

    ## FR
    $lmap->{'france'}=$uwz_fr_url.'france_index.png';

    ## LU
    $lmap->{'letzebuerg'}=$uwz_lu_url.'letzebuerg_index.png';

    ## NL
    $lmap->{'nederland'}=$uwz_nl_url.'nederland_index.png';

    ## NO
    $lmap->{'norwegen'}=$uwz_no_url.'norwegen_index.png';

    ## PT
    $lmap->{'portugal'}=$uwz_pt_url.'portugal_index.png';

    ## SE
    $lmap->{'sverige'}=$uwz_se_url.'sverige_index.png';

    ## ES
    $lmap->{'espana'}=$uwz_es_url.'espana_index.png';
    
    ## IT
    $lmap->{'italia'}=$uwz_it_url.'italia_index.png';
    $lmap->{'valledaosta'}=$uwz_it_url.'valledaosta_index.png';
    $lmap->{'piemonte'}=$uwz_it_url.'piemonte_index.png';
    $lmap->{'lombardia'}=$uwz_it_url.'lombardia_index.png';
    $lmap->{'trentinoaltoadige'}=$uwz_it_url.'trentinoaltoadige_index.png';
    $lmap->{'friuliveneziagiulia'}=$uwz_it_url.'friuliveneziagiulia_index.png';
    $lmap->{'veneto'}=$uwz_it_url.'veneto_index.png';
    $lmap->{'liguria'}=$uwz_it_url.'liguria_index.png';
    $lmap->{'emiliaromagna'}=$uwz_it_url.'emiliaromagna_index.png';
    $lmap->{'toscana'}=$uwz_it_url.'toscana_index.png';
    $lmap->{'marche'}=$uwz_it_url.'marche_index.png';
    $lmap->{'umbria'}=$uwz_it_url.'umbria_index.png';
    $lmap->{'lazio'}=$uwz_it_url.'lazio_index.png';
    $lmap->{'molise'}=$uwz_it_url.'molise_index.png';
    $lmap->{'abruzzo'}=$uwz_it_url.'abruzzo_index.png';
    $lmap->{'campania'}=$uwz_it_url.'campania_index.png';
    $lmap->{'puglia'}=$uwz_it_url.'puglia_index.png';
    $lmap->{'basilicata'}=$uwz_it_url.'basilicata_index.png';
    $lmap->{'calabria'}=$uwz_it_url.'calabria_index.png';
    $lmap->{'sicilia'}=$uwz_it_url.'sicilia_index.png';
    $lmap->{'sardegna'}=$uwz_it_url.'sardegna_index.png';


    ## Isobaren
    $lmap->{'isobaren1'}="http://www.unwetterzentrale.de/images/icons/UWZ_ISO_00.jpg";
    $lmap->{'isobaren2'}="http://www.wetteralarm.at/uploads/pics/UWZ_EURO_ISO_GER_00.jpg";
    $lmap->{'isobaren3'}="http://www.severe-weather-centre.co.uk/uploads/pics/UWZ_EURO_ISO_ENG_00.jpg";

    return $lmap->{$smap};
}

###################################
sub UWZ_Initialize($) {

    my ($hash) = @_;
    $hash->{DefFn}    = "UWZ_Define";
    $hash->{UndefFn}  = "UWZ_Undef";
    $hash->{SetFn}    = "UWZ_Set";
    $hash->{GetFn}    = "UWZ_Get";
    $hash->{AttrList} = "download:0,1 ".
                        "savepath ".
                        "maps ".
                        "humanreadable:0,1 ".
                        "htmlattr ".
                        "htmltitle ".
                        "htmltitleclass ".
                        "htmlsequence:ascending,descending ".
                        "lang ".
                        "sort_readings_by:severity,start,creation ".
                        "localiconbase ".
                        "intervalAtWarnLevel ".
                        $readingFnAttributes;
   
    foreach my $d(sort keys %{$modules{UWZ}{defptr}}) {
        my $hash = $modules{UWZ}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

###################################
sub UWZ_Define($$) {

    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};
    my $lang = "";
    my @a    = split( "[ \t][ \t]*", $def );
   
    return "Error: Perl moduls ".$missingModul."are missing on this system" if( $missingModul );
    return "Wrong syntax: use define <name> UWZ <CountryCode> <PLZ> <Interval> "  if (int(@a) != 5 and  ((lc $a[2]) ne "search"));

    if ((lc $a[2]) ne "search") {

        $hash->{STATE}           = "Initializing";
        $hash->{CountryCode}     = $a[2];
        $hash->{PLZ}             = $a[3];
        
        ## URL by CountryCode

        my $URL_language="en";
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $URL_language="de";
        }
        
        $hash->{URL} =  "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=" . $URL_language . "&areaID=UWZ" . $a[2] . $a[3];
    
        
        $hash->{fhem}{LOCAL}    = 0;
        $hash->{INTERVAL}       = $a[4];
        $hash->{INTERVALWARN}   = 0;
        $hash->{VERSION}        = $version;
       
        RemoveInternalTimer($hash);
       
        #Get first data after 12 seconds
        InternalTimer( gettimeofday() + 12, "UWZ_Start", $hash, 0 ) if ((lc $hash->{CountryCode}) ne "search");
   
    } else {
        $hash->{STATE}           = "Search-Mode";
        $hash->{CountryCode}     = uc $a[2];
        $hash->{VERSION}         = $version;
    }
    
    $modules{UWZ}{defptr}{$hash->{PLZ}} = $hash;
    
    return undef;
}

#####################################
sub UWZ_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer( $hash );
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
    
    delete($modules{UWZ}{defptr}{$hash->{PLZ}});
    
    return undef;
}

#####################################
sub UWZ_Set($@) {

    my ( $hash, @a ) = @_;
    my $name    = $hash->{NAME};
    my $reUINT = '^([\\+]?\\d+)$';
    my $usage   = "Unknown argument $a[1], choose one of update:noArg " if ( (lc $hash->{CountryCode}) ne "search" );

    return $usage if ( @a < 2 );

    my $cmd = lc( $a[1] );
    
    given ($cmd)
    {
        when ("?")
        {
            return $usage;
        }
        
        when ("update")
        {
            UWZ_Log $hash, 4, "set command: " . $a[1];
            $hash->{fhem}{LOCAL} = 1;
            UWZ_Start($hash);
            $hash->{fhem}{LOCAL} = 0;
        }
        
        default
        {
            return $usage;
        }
    }
    
    return;
}

sub UWZ_Get($@) {

    my ( $hash, @a ) = @_;
    my $name    = $hash->{NAME};
   
    if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
        my $usage   = "Unknown argument $a[1], choose one of Sturm:noArg Schneefall:noArg Regen:noArg Extremfrost:noArg Waldbrand:noArg Gewitter:noArg Glaette:noArg Hitze:noArg Glatteisregen:noArg Bodenfrost:noArg Hagel:noArg ";
     
        return $usage if ( @a < 2 );
       
        if    ($a[1] =~ /^Sturm/)            { UWZ_GetCurrent($hash,2); }
        elsif ($a[1] =~ /^Schneefall/)       { UWZ_GetCurrent($hash,3); }
        elsif ($a[1] =~ /^Regen/)            { UWZ_GetCurrent($hash,4); }
        elsif ($a[1] =~ /^Extremfrost/)      { UWZ_GetCurrent($hash,5); }
        elsif ($a[1] =~ /^Waldbrand/)        { UWZ_GetCurrent($hash,6); }
        elsif ($a[1] =~ /^Gewitter/)         { UWZ_GetCurrent($hash,7); }
        elsif ($a[1] =~ /^Glaette/)          { UWZ_GetCurrent($hash,8); }
        elsif ($a[1] =~ /^Hitze/)            { UWZ_GetCurrent($hash,9); }
        elsif ($a[1] =~ /^Glatteisregen/)    { UWZ_GetCurrent($hash,10); }
        elsif ($a[1] =~ /^Bodenfrost/)       { UWZ_GetCurrent($hash,11); }
        elsif ($a[1] =~ /^Hagel/)            { UWZ_GetCurrentHail($hash); }
        else                                 { return $usage; }
    }
    
    elsif ( (lc $hash->{CountryCode}) eq  'search' ) {
        my $usage   = "Unknown argument $a[1], choose one of SearchAreaID ";
        
        return $usage if ( @a < 3 );
        
        if    ($a[1] =~ /^SearchAreaID/)            { UWZSearchLatLon($name, $a[2]); }
        elsif ($a[1] =~ /^AreaID/)                  { my @splitparam = split(/,/,$a[2]); UWZSearchAreaID($splitparam[0],$splitparam[1]); }
        else                                        { return $usage; }
        
    } else {
        my $usage   = "Unknown argument $a[1], choose one of storm:noArg snow:noArg rain:noArg extremfrost:noArg forest-fire:noArg thunderstorms:noArg glaze:noArg heat:noArg glazed-rain:noArg soil-frost:noArg hail:noArg ";
        
        return $usage if ( @a < 2 );
    
        if    ($a[1] =~ /^storm/)            { UWZ_GetCurrent($hash,2); }
        elsif ($a[1] =~ /^snow/)             { UWZ_GetCurrent($hash,3); }
        elsif ($a[1] =~ /^rain/)             { UWZ_GetCurrent($hash,4); }
        elsif ($a[1] =~ /^extremfrost/)      { UWZ_GetCurrent($hash,5); }
        elsif ($a[1] =~ /^forest-fire/)      { UWZ_GetCurrent($hash,6); }
        elsif ($a[1] =~ /^thunderstorms/)    { UWZ_GetCurrent($hash,7); }
        elsif ($a[1] =~ /^glaze/)            { UWZ_GetCurrent($hash,8); }
        elsif ($a[1] =~ /^heat/)             { UWZ_GetCurrent($hash,9); }
        elsif ($a[1] =~ /^glazed-rain/)      { UWZ_GetCurrent($hash,10); }
        elsif ($a[1] =~ /^soil-frost/)       { UWZ_GetCurrent($hash,11); }
        elsif ($a[1] =~ /^hail/)             { UWZ_GetCurrentHail($hash); }
        else                                 { return $usage; }

    }
}

#####################################
sub UWZ_GetCurrent($@) {

    my ( $hash, @a ) = @_;
    my $name         = $hash->{NAME};
    my $out;
    my $curTimestamp = time();
    if ( ReadingsVal($name,"WarnCount", 0) eq 0 ) {
        $out = "inactive";
    } else {  
        for(my $i= 0;$i < ReadingsVal($name,"WarnCount", 0);$i++) {
            if (  (ReadingsVal($name,"Warn_".$i."_Start","") le $curTimestamp) &&  (ReadingsVal($name,"Warn_".$i."_End","") ge $curTimestamp) && (ReadingsVal($name,"Warn_".$i."_Type","") eq $a[0])  ) {
                $out= "active"; 
                last;
            } else {
                $out = "inactive";
            }
        }
    }
    
    return $out;
}

#####################################
sub UWZ_GetCurrentHail($) {

    my ( $hash ) = @_;
    my $name         = $hash->{NAME};
    my $out;
    my $curTimestamp = time();
    
    if ( ReadingsVal($name,"WarnCount", 0) eq 0 ) {
        $out = "inactive";
    } else {
        for(my $i= 0;$i < ReadingsVal($name,"WarnCount", 0);$i++) {
            if (  (ReadingsVal($name,"Warn_".$i."_Start","") le $curTimestamp) &&  (ReadingsVal($name,"Warn_".$i."_End","") ge $curTimestamp) && (ReadingsVal($name,"Warn_".$i."_Hail","") eq 1)  ) {
                $out= "active"; 
                last;
            } else {
                $out= "inactive";
            }
        }
    }

    return $out;
}

#####################################
sub UWZ_JSONAcquire($$) {

    my ($hash, $URL)  = @_;
    my $name    = $hash->{NAME};
    
    return unless (defined($hash->{NAME}));
 
    UWZ_Log $hash, 4, "Start capturing of $URL";

    my $err_log  = "";
    my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );
    my $request   = HTTP::Request->new( GET => $URL );
    my $response = $agent->request($request);
    $err_log = "Can't get $URL -- " . $response->status_line unless( $response->is_success );
     
    if ( $err_log ne "" ) {
        readingsSingleUpdate($hash, "lastConnection", $response->status_line, 1);
        UWZ_Log $hash, 1, "Error: $err_log";
        return "Error|Error " . $response->status_line;
    }

    UWZ_Log $hash, 4, length($response->content)." characters captured";
    return $response->content;
}

#####################################
sub UWZ_Start($) {

    my ($hash) = @_;
    my $name   = $hash->{NAME};
   
    return unless (defined($hash->{NAME}));
   
    if(!$hash->{fhem}{LOCAL} && $hash->{INTERVAL} > 0) {        # set up timer if automatically call
    
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVAL}, "UWZ_Start", $hash, 1 );  
        return undef if( AttrVal($name, "disable", 0 ) == 1 );
        readingsSingleUpdate($hash,'currentIntervalMode','normal',0);
    }

    ## URL by CountryCode
    my $URL_language="en";
    if (AttrVal($hash->{NAME}, "lang", undef) ) {  
        $URL_language=AttrVal($hash->{NAME}, "lang", "");
    } else {
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $URL_language="de";
        }
    }
    $hash->{URL} =  "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=" . $URL_language . "&areaID=UWZ" . $hash->{CountryCode} . $hash->{PLZ};
    
   
    if ( not defined( $hash->{URL} ) ) {

        UWZ_Log $hash, 3, "missing URL";
        return;
    }
  
    $hash->{helper}{RUNNING_PID} =
        BlockingCall( 
            "UWZ_Run",          # callback worker task
            $name,              # name of the device
            "UWZ_Done",         # callback result method
            120,                # timeout seconds
            "UWZ_Aborted",      #  callback for abortion
            $hash );            # parameter for abortion
}

#####################################
sub UWZ_Aborted($) {

    my ($hash) = @_;
    delete( $hash->{helper}{RUNNING_PID} );
}

#####################################
# asyncronous callback by blocking
sub UWZ_Done($) {

    my ($string) = @_;
    return unless ( defined($string) );
   
    # all term are separated by "|" , the first is the name of the instance
    my ( $name, %values ) = split( "\\|", $string );
    my $hash = $defs{$name};
    return unless ( defined($hash->{NAME}) );
   
    # delete the marker for RUNNING_PID process
    delete( $hash->{helper}{RUNNING_PID} );  

    
    # UnWetterdaten speichern
    readingsBeginUpdate($hash);

    if ( defined $values{Error} ) {
    
        readingsBulkUpdate( $hash, "lastConnection", $values{Error} );
        
    } else {

        while (my ($rName, $rValue) = each(%values) ) {
            readingsBulkUpdate( $hash, $rName, $rValue );
            UWZ_Log $hash, 5, "reading:$rName value:$rValue";
        }
      
        if (keys %values > 0) {
            my $newState;
            UWZ_Log $hash, 4, "Delete old Readings"; 
            for my $Counter ($values{WarnCount} .. 9) {
                CommandDeleteReading(undef, "$hash->{NAME} Warn_${Counter}_.*");
            }


            if (defined $values{WarnCount}) {
                # Message by CountryCode
                
                $newState = "Warnings: " . $values{WarnCount};
                $newState = "Warnungen: " . $values{WarnCount} if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] );
                # end Message by CountryCode
            } else {
                $newState = "Error: Could not capture all data. Please check CountryCode and PLZ.";
            }

            readingsBulkUpdate($hash, "state", $newState);
            readingsBulkUpdate( $hash, "lastConnection", keys( %values )." values captured in ".$values{durationFetchReadings}." s" );
            UWZ_Log $hash, 4, keys( %values )." values captured";
            
        } else {
      
        readingsBulkUpdate( $hash, "lastConnection", "no data found" );
        UWZ_Log $hash, 1, "No data found. Check city name or URL.";
        
        }
    }
    
    readingsEndUpdate( $hash, 1 );
    
    if( AttrVal($name,'intervalAtWarnLevel','') ne '' and ReadingsVal($name,'WarnUWZLevel',0) > 1 ) {
    
        UWZ_IntervalAtWarnLevel($hash);
        UWZ_Log $hash, 5, "run Sub IntervalAtWarnLevel"; 
    }
}

#####################################
sub UWZ_Run($) {

    my ($name) = @_;
    my $ptext=$name;
    my $UWZ_download;
    my $UWZ_savepath;
    my $UWZ_humanreadable;
    
    return unless ( defined($name) );
   
    my $hash = $defs{$name};
    return unless (defined($hash->{NAME}));
    
    my $readingStartTime = time();
    my $attrdownload     = AttrVal( $name, 'download','');
    my $attrsavepath     = AttrVal( $name, 'savepath','');
    my $maps2fetch       = AttrVal( $name, 'maps','');
    
    ## begin redundant Reading switch
    my $attrhumanreadable = AttrVal( $name, 'humanreadable','');
    ## end redundant Reading switch
    
    # preset download
    if ($attrdownload eq "") {
    
        $UWZ_download = 0;
    } else {
    
        $UWZ_download = $attrdownload;
    }
    
    # preset savepath
    if ($attrsavepath eq "") {
    
        $UWZ_savepath = "/tmp/";
    } else {
    
        $UWZ_savepath = $attrsavepath;
    }
    
    # preset humanreadable
    if ($attrhumanreadable eq "") {
    
        $UWZ_humanreadable = 0;
    } else {
    
      $UWZ_humanreadable = $attrhumanreadable;
    }

    if ( $UWZ_download == 1 ) {
        if ( ! defined($maps2fetch) ) { $maps2fetch = "deutschland"; }
            UWZ_Log $hash, 4, "Maps2Fetch : ".$maps2fetch;
            my @maps = split(' ', $maps2fetch);
            my $uwz_de_url = "http://www.unwetterzentrale.de/images/map/";
            
            foreach my $smap (@maps) {
                UWZ_Log $hash, 4, "Download map : ".$smap;
                my $img = UWZ_Map2Image($hash,$smap);
                
                if (!defined($img) ) { $img=$uwz_de_url.'deutschland_index.png'; }
                    my $code = getstore($img, $UWZ_savepath.$smap.".png");
                    
                    if($code == 200) {
                        UWZ_Log $hash, 4, "Successfully downloaded map ".$smap;
                        
                    } else {
                    
                UWZ_Log $hash, 3, "Failed to download map (".$img.")";
            }
        } 

    }

    # acquire the json-response
    my $response = UWZ_JSONAcquire($hash,$hash->{URL}); 

    UWZ_Log $hash, 5, length($response)." characters captured";
    my $converter = Text::Iconv->new("windows-1252","UTF-8");
    my $uwz_warnings = JSON->new->ascii->decode($response);
    my $enc = guess_encoding($uwz_warnings);

    my $uwz_warncount = scalar(@{ $uwz_warnings->{'results'} });
    UWZ_Log $hash, 4, "There are ".$uwz_warncount." warnings active";
    my $sortby = AttrVal( $name, 'sort_readings_by',"" );
    my @sorted;
    
    if ( $sortby eq "creation" ) {
        UWZ_Log $hash, 4, "Sorting by creation";
        @sorted =  sort { $b->{payload}{creation} <=> $a->{payload}{creation} } @{ $uwz_warnings->{'results'} };
    
    } elsif ( $sortby ne "severity" ) {
        UWZ_Log $hash, 4, "Sorting by dtgStart";
        @sorted =  sort { $a->{dtgStart} <=> $b->{dtgStart} } @{ $uwz_warnings->{'results'} };
        
    } else {
        UWZ_Log $hash, 4, "Sorting by severity";
        @sorted =  sort { $a->{severity} <=> $b->{severity} } @{ $uwz_warnings->{'results'} };
    }

    my $message;
    my $i=0;
    
    my %typenames       = ( "1" => "unknown",     # <===== FIX HERE
                            "2" => "sturm", 
                            "3" => "schnee",
                            "4" => "regen",
                            "5" => "temperatur",
                            "6" => "waldbrand",     
                            "7" => "gewitter",     
                            "8" => "strassenglaette",
                            "9" => "temperatur",    # 9 = hitzewarnung
                            "10" => "glatteisregen",
                            "11" => "temperatur" ); # 11 = bodenfrost

    my %typenames_de_str= ( "1" => "unknown",     # <===== FIX HERE
                            "2" => "Sturm",
                            "3" => "Schnee",
                            "4" => "Regen",
                            "5" => "Temperatur",
                            "6" => "Waldbrand",
                            "7" => "Gewitter",
                            "8" => "Strassenglaette",
                            "9" => "Hitze",    # 9 = hitzewarnung
                            "10" => "Glatteisregen",
                            "11" => "Bodenfrost" ); # 11 = bodenfrost
    

    my %typenames_en_str= ( "1" => "unknown",     # <===== FIX HERE
                            "2" => "storm",
                            "3" => "snow",
                            "4" => "rain",
                            "5" => "temperatur",
                            "6" => "forest fire",
                            "7" => "thunderstorms",
                            "8" => "slippery road",
                            "9" => "heat",    # 9 = hitzewarnung
                            "10" => "black ice rain",
                            "11" => "soil frost" ); # 11 = bodenfrost

                    
    my %severitycolor   = ( "0" => "green", 
                            "1" => "unknown", # <===== FIX HERE
                            "2" => "unknown", # <===== FIX HERE
                            "3" => "unknown", # <===== FIX HERE
                            "4" => "orange",
                            "5" => "unknown", # <===== FIX HERE
                            "6" => "unknown", # <===== FIX HERE
                            "7" => "orange",
                            "8" => "gelb",
                            "9" => "gelb", # <===== FIX HERE
                            "10" => "orange",
                            "11" => "rot",
                            "12" => "violett" );

    my @uwzmaxlevel;
    foreach my $single_warning (@sorted) {

        push @uwzmaxlevel, UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'});

        UWZ_Log $hash, 4, "Warn_".$i."_EventID: ".$single_warning->{'payload'}{'id'};
        $message .= "Warn_".$i."_EventID|".$single_warning->{'payload'}{'id'}."|";


        my $chopcreation = substr($single_warning->{'payload'}{'creation'},0,10);
        $chopcreation = $chopcreation;

        UWZ_Log $hash, 4, "Warn_".$i."_Creation: ".$chopcreation; 
        $message .= "Warn_".$i."_Creation|".$chopcreation."|"; 


        UWZ_Log $hash, 4, "Warn_".$i."_Type: ".$single_warning->{'type'};
        $message .= "Warn_".$i."_Type|".$single_warning->{'type'}."|";
        
        UWZ_Log $hash, 4, "Warn_".$i."_uwzLevel: ".UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'});
        $message .= "Warn_".$i."_uwzLevel|".UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'})."|";

        UWZ_Log $hash, 4, "Warn_".$i."_Severity: ".$single_warning->{'severity'};
        $message .= "Warn_".$i."_Severity|".$single_warning->{'severity'}."|";
        
        UWZ_Log $hash, 4, "Warn_".$i."_Start: ".$single_warning->{'dtgStart'};
        $message .= "Warn_".$i."_Start|".$single_warning->{'dtgStart'}."|";
        
        UWZ_Log $hash, 4, "Warn_".$i."_End: ".$single_warning->{'dtgEnd'};
        $message .= "Warn_".$i."_End|".$single_warning->{'dtgEnd'}."|";

        ## Begin of redundant Reading
        if ( $UWZ_humanreadable eq 1 ) {
            UWZ_Log $hash, 4, "Warn_".$i."_Start_Date: ".strftime("%d.%m.%Y", localtime($single_warning->{'dtgStart'}));
            $message .= "Warn_".$i."_Start_Date|".strftime("%d.%m.%Y", localtime($single_warning->{'dtgStart'}))."|";
            
            UWZ_Log $hash, 4, "Warn_".$i."_Start_Time: ".strftime("%H:%M", localtime($single_warning->{'dtgStart'}));
            $message .= "Warn_".$i."_Start_Time|".strftime("%H:%M", localtime($single_warning->{'dtgStart'}))."|";
            
            UWZ_Log $hash, 4, "Warn_".$i."_End_Date: ".strftime("%d.%m.%Y", localtime($single_warning->{'dtgEnd'}));
            $message .= "Warn_".$i."_End_Date|".strftime("%d.%m.%Y", localtime($single_warning->{'dtgEnd'}))."|";
            
            UWZ_Log $hash, 4, "Warn_".$i."_End_Time: ".strftime("%H:%M", localtime($single_warning->{'dtgEnd'}));
            $message .= "Warn_".$i."_End_Time|".strftime("%H:%M", localtime($single_warning->{'dtgEnd'}))."|";


            UWZ_Log $hash, 4, "Warn_".$i."_Creation_Date: ".strftime("%d.%m.%Y", localtime($chopcreation));
            $message .= "Warn_".$i."_Creation_Date|".strftime("%d.%m.%Y", localtime($chopcreation))."|";

            UWZ_Log $hash, 4, "Warn_".$i."_Creation_Time: ".strftime("%H:%M", localtime($chopcreation));
            $message .= "Warn_".$i."_Creation_Time|".strftime("%H:%M", localtime($chopcreation))."|";

   

            # Begin Language by AttrVal
            if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
                UWZ_Log $hash, 4, "Warn_".$i."_Type_Str: ".$typenames_de_str{ $single_warning->{'type'} };
                $message .= "Warn_".$i."_Type_Str|".$typenames_de_str{ $single_warning->{'type'} }."|";
                my %uwzlevelname = ( "0" => "Stufe Grün (keine Warnung)",
                                     "1" => "Stufe Dunkelgrün (Wetterhinweise)",
                                     "2" => "Stufe Gelb (Vorwarnung für Unwetterwarnung)",
                                     "3" => "Warnstufe Orange (Unwetterwarnung)",
                                     "4" => "Warnstufe Rot (Unwetterwarnung)",
                                     "5" => "Warnstufe Violett (Unwetterwarnung)");
                UWZ_Log $hash, 4, "Warn_".$i."_uwzLevel_Str: ".$uwzlevelname{ UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'}) };
                $message .= "Warn_".$i."_uwzLevel_Str|".$uwzlevelname{ UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'}) }."|";


            } else {
                UWZ_Log $hash, 4, "Warn_".$i."_Type_Str: ".$typenames_en_str{ $single_warning->{'type'} };
                $message .= "Warn_".$i."_Type_Str|".$typenames_en_str{ $single_warning->{'type'} }."|";
                my %uwzlevelname = ( "0" => "level green (no warnings)",
                                     "1" => "level dark green (weather notice)",
                                     "2" => "level yellow (severe weather watch)",
                                     "3" => "Alert level Orange",
                                     "4" => "Alert level Red",
                                     "5" => "Alert level Violet");
                UWZ_Log $hash, 4, "Warn_".$i."_uwzLevel_Str: ".$uwzlevelname{ UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'}) };
                $message .= "Warn_".$i."_uwzLevel_Str|".$uwzlevelname{ UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'}) }."|";

            }

        }
        ## End of redundant Reading
        
        UWZ_Log $hash, 4, "Warn_".$i."_levelName: ".$single_warning->{'payload'}{'levelName'};
        $message .= "Warn_".$i."_levelName|".$single_warning->{'payload'}{'levelName'}."|";
        
        UWZ_Log $hash, 4, "Warn_".$i."_AltitudeMin: ".$enc->decode($single_warning->{'payload'}{'altMin'});
        $message .= "Warn_".$i."_AltitudeMin|".$converter->convert($single_warning->{'payload'}{'altMin'})."|";

        UWZ_Log $hash, 4, "Warn_".$i."_AltitudeMax: ".$enc->decode($single_warning->{'payload'}{'altMax'});
        $message .= "Warn_".$i."_AltitudeMax|".$converter->convert($single_warning->{'payload'}{'altMax'})."|";

        my $uclang = "EN";
        if (AttrVal( $name, 'lang',undef) ) {
            $uclang = uc AttrVal( $name, 'lang','');
        } else {
            # Begin Language by AttrVal
            if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
                $uclang = "DE";
            } else {
                $uclang = "EN";
            }
        }
        UWZ_Log $hash, 4, "Warn_".$i."_LongText: ".$enc->decode($single_warning->{'payload'}{'translationsLongText'}{$uclang});
        $message .= "Warn_".$i."_LongText|".$converter->convert($single_warning->{'payload'}{'translationsLongText'}{$uclang})."|";
            
        UWZ_Log $hash, 4, "Warn_".$i."_ShortText: ".$enc->decode($single_warning->{'payload'}{'translationsShortText'}{$uclang});
        $message .= "Warn_".$i."_ShortText|".$converter->convert($single_warning->{'payload'}{'translationsShortText'}{$uclang})."|";

###
        if (AttrVal( $name, 'localiconbase',undef) ) {
            UWZ_Log $hash, 4, "Warn_".$i."_IconURL: ".AttrVal( $name, 'localiconbase',undef).$typenames{ $single_warning->{'type'} }."-".$single_warning->{'severity'}.".png";
            $message .= "Warn_".$i."_IconURL|".AttrVal( $name, 'localiconbase',undef).$typenames{ $single_warning->{'type'} }."-".UWZ_GetSeverityColor($hash, UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'} )).".png|";

        } else {
            UWZ_Log $hash, 4, "Warn_".$i."_IconURL: http://www.unwetterzentrale.de/images/icons/".$typenames{ $single_warning->{'type'} }."-".$single_warning->{'severity'}.".gif";
            $message .= "Warn_".$i."_IconURL|http://www.unwetterzentrale.de/images/icons/".$typenames{ $single_warning->{'type'} }."-".UWZ_GetSeverityColor($hash, UWZ_GetUWZLevel($hash,$single_warning->{'payload'}{'levelName'} )).".gif|";
        }
###

        
        ## Hagel start
        my $hagelcount = 0;
        # Begin Language by AttrVal
        
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
        
            $hagelcount = my @hagelmatch = $single_warning->{'payload'}{'translationsLongText'}{'DE'} =~ /Hagel/g;
            
        } else {
        
            $hagelcount = my @hagelmatch = $single_warning->{'payload'}{'translationsLongText'}{'EN'} =~ /Hail/g;
        }
        # end language by AttrVal
        if ( $hagelcount ne 0 ) {
            
            UWZ_Log $hash, 4, "Warn_".$i."_Hail: 1";
            $message .= "Warn_".$i."_Hail|1|";
                
        } else {
            
            UWZ_Log $hash, 4, "Warn_".$i."_Hail: 0";
            $message .= "Warn_".$i."_Hail|0|";
        }
        ## Hagel end

        $i++;
    }
    
    my $max=0;
    for (@uwzmaxlevel) {
        $max = $_ if !$max || $_ > $max
    };

    $message .= "WarnUWZLevel|";
    $message .= $max."|";

    UWZ_Log $hash, 4, "WarnUWZLevel_Color: ".UWZ_GetSeverityColor($hash, $max);
    $message .= "WarnUWZLevel_Color|".UWZ_GetSeverityColor($hash, $max)."|";

    ## Begin of redundant Reading
    if ( $UWZ_humanreadable eq 1 ) {
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            my %uwzlevelname = ( "0" => "Stufe Grün (keine Warnung)",
                                 "1" => "Stufe Dunkelgrün (Wetterhinweise)",
                                 "2" => "Stufe Gelb (Vorwarnung für Unwetterwarnung)",
                                 "3" => "Warnstufe Orange (Unwetterwarnung)",
                                 "4" => "Warnstufe Rot (Unwetterwarnung)",
                                 "5" => "Warnstufe Violett (Unwetterwarnung)");
            UWZ_Log $hash, 4, "WarnUWZLevel_Str: ".$uwzlevelname{ $max };
            $message .= "WarnUWZLevel_Str|".$uwzlevelname{ $max }."|";
        } else {
            my %uwzlevelname = ( "0" => "level green (no warnings)",
                                 "1" => "level dark green (weather notice)",
                                 "2" => "level yellow (severe weather watch)",
                                 "3" => "Alert level Orange",
                                 "4" => "Alert level Red",
                                 "5" => "Alert level Violet");
            UWZ_Log $hash, 4, "WarnUWZLevel_Str: ".$uwzlevelname{ $max };
            $message .= "WarnUWZLevel_Str|".$uwzlevelname{ $max }."|";
        }
    }

    $message .= "durationFetchReadings|";
    $message .= sprintf "%.2f",  time() - $readingStartTime;
    
    UWZ_Log $hash, 3, "Done fetching data";
    UWZ_Log $hash, 4, "Will return : "."$name|$message|WarnCount|$uwz_warncount" ;
    
    return "$name|$message|WarnCount|$uwz_warncount" ;
}

#####################################
sub UWZAsHtml($;$) {

    my ($name,$items) = @_;
    my $ret = '';
    my $hash = $defs{$name};    

    my $htmlsequence = AttrVal($name, "htmlsequence", "none");
    my $htmltitle = AttrVal($name, "htmltitle", "");
    my $htmltitleclass = AttrVal($name, "htmltitleclass", "");


    my $attr;
    if (AttrVal($name, "htmlattr", "none") ne "none") {
        $attr = AttrVal($name, "htmlattr", "");
    } else {
        $attr = 'width="100%"';
    }


    if (ReadingsVal($name, "WarnCount", 0) != 0 ) {
    
        $ret .= '<table><tr><td>';
        $ret .= '<table class="block" '.$attr.'><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';

        if ($htmlsequence eq "descending") {
            for ( my $i=ReadingsVal($name, "WarnCount", -1)-1; $i>=0; $i--){
            
                $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="uwzValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                $ret .= ReadingsVal($name, "Warn_".$i."_LongText", "").'<br><br>';
      
                $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_Start", "")).'</td>';
                
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        } else {
###        
            for ( my $i=0; $i<ReadingsVal($name, "WarnCount", 0); $i++){
            
                $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="uwzValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                $ret .= ReadingsVal($name, "Warn_".$i."_LongText", "").'<br><br>';
      
                $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_Start", "")).'</td>';
                
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        }
###

  
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
        
    } else {
    
        $ret .= '<table><tr><td>';
        $ret .= '<table class="block wide" width="600px"><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';
        $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;">';
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $ret .='<b>Keine Warnungen</b>';
        } else {
            $ret .='<b>No Warnings</b>';
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
sub UWZAsHtmlLite($;$) {

    my ($name,$items) = @_;
    my $ret = '';
    my $hash = $defs{$name}; 
    my $htmlsequence = AttrVal($name, "htmlsequence", "none");
    my $htmltitle = AttrVal($name, "htmltitle", "");
    my $htmltitleclass = AttrVal($name, "htmltitleclass", "");
    my $attr;
    
    if (AttrVal($name, "htmlattr", "none") ne "none") {
        $attr = AttrVal($name, "htmlattr", "");
    } else {
        $attr = 'width="100%"';
    }
    
    if (ReadingsVal($name, "WarnCount", "") != 0 ) {

        $ret .= '<table><tr><td>';
        $ret .= '<table class="block" '.$attr.'><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';
  
        if ($htmlsequence eq "descending") {
            for ( my $i=ReadingsVal($name, "WarnCount", "")-1; $i>=0; $i--){
                $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="uwzValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_Start", "")).'</td>';
                # language by AttrVal
                
                if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        } else {
            for ( my $i=0; $i<ReadingsVal($name, "WarnCount", ""); $i++){
                $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="uwzValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_Start", "")).'</td>';
                # language by AttrVal
                
                if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'.localtime(ReadingsVal($name, "Warn_".$i."_End", "")).'</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        }    
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
        
    } else {
  
        $ret .= '<table><tr><td>';
        $ret .= '<table class="block wide" width="600px"><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';
        $ret .= '<tr><td class="uwzIcon" style="vertical-align:top;">';
        
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $ret .='<b>Keine Warnungen</b>';
        } else {
            $ret .='<b>No Warnings</b>';
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
sub UWZAsHtmlFP($;$) {

    my ($name,$items) = @_;
    my $tablewidth = ReadingsVal($name, "WarnCount", "") * 80;
    my $htmlsequence = AttrVal($name, "htmlsequence", "none");
    my $htmltitle = AttrVal($name, "htmltitle", "");
    my $htmltitleclass = AttrVal($name, "htmltitleclass", "");
    my $ret = '';
    
    $ret .= '<table class="uwz-fp" style="width:'.$tablewidth.'px"><tr><th class="'.$htmltitleclass.'" colspan="'.ReadingsVal($name, "WarnCount", "none").'">'.$htmltitle.'</th></tr>';
    $ret .= "<tr>";
    
    if ($htmlsequence eq "descending") {
        for ( my $i=ReadingsVal($name, "WarnCount", "")-1; $i>=0; $i--){
            $ret .= '<td class="uwzIcon"><img width="80px" src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
        }
    } else {
        for ( my $i=0; $i<ReadingsVal($name, "WarnCount", ""); $i++){
            $ret .= '<td class="uwzIcon"><img width="80px" src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
        }
    } 
    $ret .= "</tr>";
    $ret .= '</table>';

    return $ret;
}

#####################################
sub UWZAsHtmlMovie($$) {

    my ($name,$land) = @_;
    my $url = UWZ_Map2Movie($name,$land);
    my $hash = $defs{$name};

    my $ret = '<table><tr><td>';

    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even"><td>';

    if(defined($url)) {
        $ret .= '<video controls="controls">';
        $ret .= '<source src="'.$url.'" type="video/mp4">';
        $ret .= '</video>';

    } else {
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $ret .= 'unbekannte Landbezeichnung';
        } else {
            $ret .='unknown movie setting';
        }
        # end language by AttrVal
    }

    $ret .= '</td></tr></table></td></tr>';
    $ret .= '</table>';

    return $ret;
}

#####################################
sub UWZAsHtmlKarteLand($$) {

    my ($name,$land) = @_;
    my $url = UWZ_Map2Image($name,$land);
    my $hash = $defs{$name};

    my $ret = '<table><tr><td>';
    
    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even"><td>';
    
    if(defined($url)) {
        $ret .= '<img src="'.$url.'">';
        
    } else {
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $ret .= 'unbekannte Landbezeichnung';
        } else {
            $ret .='unknown map setting';
        }       
        # end language by AttrVal
    }
    
    $ret .= '</td></tr></table></td></tr>';
    $ret .= '</table>';
    
    return $ret;
}

#####################################
sub UWZ_GetSeverityColor($$) {
    my ($name,$uwzlevel) = @_;
    my $alertcolor       = "";

    my %UWZSeverity = ( "0" => "gruen",
                            "1" => "orange",
                            "2" => "gelb",
                            "3" => "orange",
                            "4" => "rot",
                            "5" => "violett");

    return $UWZSeverity{$uwzlevel};
}

#####################################
sub UWZ_GetUWZLevel($$) {
    my ($name,$warnname) = @_;
    my @alert            = split(/_/,$warnname);

    if ( $alert[0] eq "notice" ) {
        return "1";
    } elsif ( $alert[1] eq "forewarn" ) {
        return "2";
    } else {

        my %UWZSeverity = ( "green" => "0",
                            "yellow" => "2",
                            "orange" => "3",
                            "red" => "4",
                            "violet" => "5");

        return $UWZSeverity{$alert[2]};
    }
}

#####################################
sub UWZ_IntervalAtWarnLevel($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $warnLevel   = ReadingsVal($name,'WarnUWZLevel',0);
    my @valuestring = split( ',', AttrVal($name,'intervalAtWarnLevel','') );
    my %warnLevelInterval;
    
    
    readingsSingleUpdate($hash,'currentIntervalMode','warn',0);
    
    foreach( @valuestring ) {
    
        my @values = split( '=' , $_ );
        $warnLevelInterval{$values[0]} = $values[1];
    }
    
    if( defined($warnLevelInterval{$warnLevel}) and $hash->{INTERVALWARN} != $warnLevelInterval{$warnLevel} ) {
    
        $hash->{INTERVALWARN} = $warnLevelInterval{$warnLevel};
    
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVALWARN}, "UWZ_Start", $hash, 1 );
        
        UWZ_Log $hash, 4, "restart internal timer with interval $hash->{INTERVALWARN}";
        
    } else {
        
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVALWARN}, "UWZ_Start", $hash, 1 );
        
        UWZ_Log $hash, 4, "restart internal timer with interval $hash->{INTERVALWARN}";
    }
}

#####################################
##
##      UWZ Helper Functions
##
#####################################

sub UWZSearchLatLon($$) {

    my ($name,$loc)    = @_;
    my $url      = "http://alertspro.geoservice.meteogroup.de/weatherpro/SearchFeed.php?search=".$loc;

    my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );
    my $request  = HTTP::Request->new( GET => $url );
    my $response = $agent->request($request);
    my $err_log  = "Can't get $url -- " . $response->status_line unless( $response->is_success );

    if ( $err_log ne "" ) {
        print "Error|Error " . $response->status_line;
    }
    
    use XML::Simple qw(:strict);
    use Data::Dumper;
    use Encode qw(decode encode);

    my $uwzxmlparser = XML::Simple->new();
    #my $xmlres = $parser->XMLin(
    my $search = $uwzxmlparser->XMLin($response->content, KeyAttr => { city => 'id' }, ForceArray => [ 'city' ]);

    my $ret = '<html><table><tr><td>';

    $ret .= '<table class="block wide">';

            $ret .= '<tr class="even">';
            $ret .= "<td><b>city</b></td>";
            $ret .= "<td><b>country</b></td>";
            $ret .= "<td><b>latitude</b></td>";
            $ret .= "<td><b>longitude</b></td>";
            $ret .= '</tr>';

    foreach my $locres ($search->{cities}->{city})
        {
            my $linecount=1;
            while ( my ($key, $value) = each(%$locres) ) {
                if ( $linecount % 2 == 0 ) {
                    $ret .= '<tr class="even">';
                } else {
                    $ret .= '<tr class="odd">';
                }
                $ret .= "<td>".encode('utf-8',$value->{'name'})."</td>";
                $ret .= "<td>$value->{'country-name'}</td>";
                $ret .= "<td>$value->{'latitude'}</td>";
                $ret .= "<td>$value->{'longitude'}</td>";

                my @headerHost = grep /Host/, @FW_httpheader;
                $headerHost[0] =~ s/Host: //g; 
 
                my $aHref="<a href=\"http://".$headerHost[0]."/fhem?cmd=get+".$name."+AreaID+".$value->{'latitude'}.",".$value->{'longitude'}."\">Get AreaID</a>";
                $ret .= "<td>".$aHref."</td>";
                $ret .= '</tr>';
                $linecount++;
            }
        }
        
    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;

}

#####################################
sub UWZSearchAreaID($$) {
    my ($lat,$lon) = @_;
    my $url = "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=lookupCoord&lat=".$lat."&lon=".$lon;
    
    my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );
    my $request   = HTTP::Request->new( GET => $url );
    my $response = $agent->request($request);
    my $err_log = "Can't get $url -- " . $response->status_line unless( $response->is_success );

    if ( $err_log ne "" ) {
        print "Error|Error " . $response->status_line;
    }
    use JSON;
    my @perl_scalar = @{JSON->new->utf8->decode($response->content)};


    my $AreaType = $perl_scalar[0]->{'AREA_TYPE'};
    my $CC       = substr $perl_scalar[0]->{'AREA_ID'}, 3, 2;
    my $AreaID   = substr $perl_scalar[0]->{'AREA_ID'}, 5, 5;   

    if ( $AreaType eq "UWZ" ) {
        my $ret = '<html>Please use the following statement to define Unwetterzentrale for your location:<br /><br />';
        $ret   .= '<table width=100%><tr><td>';
        $ret   .= '<table class="block wide">';
        $ret   .= '<tr class="even">';
        $ret   .= "<td height=100><center><b>define Unwetterzentrale UWZ $CC $AreaID 3600</b></center></td>";
        $ret   .= '</tr>';
        $ret   .= '</table>';
        $ret   .= '</td></tr></table>';
    
        $ret   .= '<br />';
        $ret   .= 'You can also use weblinks to add weathermaps. For a list of possible Weblinks see Commandref. For example to add the Europe Map use:<br />';
    
        $ret   .= '<table width=100%><tr><td>';
        $ret   .= '<table class="block wide">';
        $ret   .= '<tr class="even">';
        $ret   .= "<td height=100><center>define UWZ_Map_Europe weblink htmlCode { UWZAsHtmlKarteLand('Unwetterzentrale','europa') }</center></td>";
        $ret   .= '</tr>';
        $ret   .= '</table>';
        $ret   .= '</td></tr></table>';
    
        $ret   .= '</html>';
     
        return $ret;
    } else {
        return "Sorry, nothing found or not implemented";
    }
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
   This modul extracts thunderstorm warnings from <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a>.
   <br/>
   Therefore the same interface is used as the Android App <a href="http://www.alertspro.com">Alerts Pro</a> does.
   A maximum of 10 thunderstorm warnings will be served.
   Additional the module provides a few functions to create HTML-Templates which can be used with weblink.
   <br>
   <i>The following Perl-Modules are used within this module: HTTP::Request, LWP::UserAgent, JSON, Encode::Guess, Text::Iconv und HTML::Parse</i>.
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
        define UnwetterDetails weblink htmlCode {UWZAsHtml("Unwetterzentrale")}<br>
        define UnwetterMapE_UK weblink htmlCode {UWZAsHtmlKarteLand("Unwetterzentrale","eastofengland")}<br>
        define UnwetterLite weblink htmlCode {UWZAsHtmlLite("Unwetterzentrale")}
        define UnwetterMovie weblink htmlCode {UWZAsHtmlMovie("Unwetterzentrale","clouds-precipitation-uk")}
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
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - cumulated URL to display warn-icons from <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a></li>
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
      <li><code>define UnwetterDetailiert weblink htmlCode {UWZAsHtml("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {UWZAsHtmlLite("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {UWZAsHtmlFP("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {UWZAsHtmlKarteLand("Unwetterzentrale","Bayern")}</code></li>
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
          <br/>
          <li>letzebuerg</li>
          <br/>
          <li>nederland</li>
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
      <li><code>define UnwetterKarteMovie weblink htmlCode {UWZAsHtmlMovie("Unwetterzentrale","currents")}</code></li>
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
          <li>niederschlag-wolken-uk</li>
          <li>stroemung-uk</li>
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
   Das Modul extrahiert Unwetterwarnungen von <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a>.
   <br/>
   Hierfür wird die selbe Schnittstelle verwendet die auch die Android App <a href="http://www.alertspro.com">Alerts Pro</a> nutzt.
   Es werden maximal 10 Standortbezogene Unwetterwarnungen zur Verfügung gestellt.
   Weiterhin verfügt das Modul über HTML-Templates welche als weblink verwendet werden können.
   <br>
   <i>Es nutzt die Perl-Module HTTP::Request, LWP::UserAgent, JSON, Encode::Guess, Text::Iconv und HTML::Parse</i>.
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
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - Kumulierte URL um Warnungs-Icon von <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a> anzuzeigen</li>
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
      <li><code>define UnwetterDetailiert weblink htmlCode {UWZAsHtml("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {UWZAsHtmlLite("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {UWZAsHtmlFP("Unwetterzentrale")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {UWZAsHtmlKarteLand("Unwetterzentrale","Bayern")}</code></li>
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
          <br/>
          <li>letzebuerg</li>
          <br/>
          <li>nederland</li>
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
      <li><code>define UnwetterKarteMovie weblink htmlCode {UWZAsHtmlMovie("Unwetterzentrale","niederschlag-wolken-de")}</code></li>
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
=cut

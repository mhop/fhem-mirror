########################################################################################
#
# 95_Astro.pm
#
# Collection of various routines for astronomical data
# Prof. Dr. Peter A. Henning
#
# Equations from "Practical Astronomy with your Calculator" by Peter Duffett-Smith
# Program skeleton (with some errors) by Arnold Barmettler 
# http://lexikon.astronomie.info/java/sunmoon/
#
#  $Id$
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
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
########################################################################################

package FHEM::Astro;
use strict;
use warnings; 
use POSIX;
use utf8;

use Encode;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);
use Math::Trig;
use Time::HiRes qw(gettimeofday);
use Time::Local;
use UConv;
#use Data::Dumper;

my $DEG = pi/180.0;
my $RAD = 180./pi;

my $deltaT   = 65;  # Correction time in s

my %Astro;
my %Date;

#-- These we may set on request
my %sets = (
    "update" => "noArg",
);

#-- These we may get on request
my %gets = (
    "json"    => undef,
    "text"    => undef,
    "version" => "noArg",
);

#-- These we may configure
my %attrs = (
    "altitude"    => undef,
    "disable"     => "1,0",
    "horizon"     => undef,
    "interval"    => undef,
    "language"    => "EN,DE,ES,FR,IT,NL,PL",
    "latitude"    => undef,
    "lc_numeric"  => "en_EN.UTF-8,de_DE.UTF-8,es_ES.UTF-8,fr_FR.UTF-8,it_IT.UTF-8,nl_NL.UTF-8,pl_PL.UTF-8",
    "lc_time"     => "en_EN.UTF-8,de_DE.UTF-8,es_ES.UTF-8,fr_FR.UTF-8,it_IT.UTF-8,nl_NL.UTF-8,pl_PL.UTF-8",
    "longitude"   => undef,
    "recomputeAt" => "multiple-strict,MoonRise,MoonSet,MoonTransit,NewDay,SunRise,SunSet,SunTransit,AstroTwilightEvening,AstroTwilightMorning,CivilTwilightEvening,CivilTwilightMorning,CustomTwilightEvening,CustomTwilightMorning",
    "timezone"    => undef,
);

my $json;
my $tt;

#-- Export variables to other programs
our %transtable = (
    EN => {
        "coord"             => "Coordinates",
        "position"          => "Position",
        "longitude"         => "Longitude",
        "latitude"          => "Latitude",
        "altitude"          => "Height a.s.l.",
        "lonecl"            => "Ecliptical longitude",
        "latecl"            => "Ecliptical latitude",
        "ra"                => "Right ascension",
        "dec"               => "Declination",
        "az"                => "Azimuth",
        "alt"               => "Horizontal altitude",
        "age"               => "Age",
        "rise"              => "Rise",
        "set"               => "Set",
        "transit"           => "Transit",
        "distance"          => "Distance",
        "diameter"          => "Diameter",
        "toobs"             => "to observer",
        "toce"              => "to Earth center",
        "progress"          => "Progress",
        "twilightcivil"     => "Civil twilight",
        "twilightnautic"    => "Nautical twilight",
        "twilightastro"     => "Astronomical twilight",
        "twilightcustom"    => "Custom twilight",
        "sign"              => "Zodiac sign",
        "dst"               => "daylight saving time",
        "nt"                => "standard time",
        "switchtodst"       => "Time change ahead to daylight saving time",
        "switchtont"        => "Time change back to standard time",
        "hoursofsunlight"   => "Hours of sunlight",
        "hoursofnight"      => "Hours of night",
        "hoursofvisibility" => "Visibility",

        #--
        "time"          => "Time",
        "date"          => "Date",
        "jdate"         => "Julian date",
        "dayofyear"     => "day of year",
        "days"          => "days",
        "timezone"      => "Time Zone",
        "lmst"          => "Local Sidereal Time",

        #--
        "season" => "Astronomical Season",
        "spring" => "Spring",
        "summer" => "Summer",
        "fall"   => "Fall",
        "winter" => "Winter",

        #--
        "aries"       => "Ram",
        "taurus"      => "Bull",
        "gemini"      => "Twins",
        "cancer"      => "Crab",
        "leo"         => "Lion",
        "virgo"       => "Maiden",
        "libra"       => "Scales",
        "scorpio"     => "Scorpion",
        "sagittarius" => "Archer",
        "capricorn"   => "Goat",
        "aquarius"    => "Water Bearer",
        "pisces"      => "Fish",

        #--
        "sun" => "Sun",

        #--
        "moon"           => "Moon",
        "phase"          => "Phase",
        "newmoon"        => "New Moon",
        "waxingcrescent" => "Waxing Crescent",
        "firstquarter"   => "First Quarter",
        "waxingmoon"     => "Waxing Moon",
        "fullmoon"       => "Full Moon",
        "waningmoon"     => "Waning Moon",
        "lastquarter"    => "Last Quarter",
        "waningcrescent" => "Waning Crescent",
    },

    DE => {
        "coord"             => "Koordinaten",
        "position"          => "Position",
        "longitude"         => "Länge",
        "latitude"          => "Breite",
        "altitude"          => "Höhe ü. NHN",
        "lonecl"            => "Eklipt. Länge",
        "latecl"            => "Eklipt. Breite",
        "ra"                => "Rektaszension",
        "dec"               => "Deklination",
        "az"                => "Azimut",
        "alt"               => "Horizontwinkel",
        "age"               => "Alter",
        "phase"             => "Phase",
        "rise"              => "Aufgang",
        "set"               => "Untergang",
        "transit"           => "Kulmination",
        "distance"          => "Entfernung",
        "diameter"          => "Durchmesser",
        "toobs"             => "z. Beobachter",
        "toce"              => "z. Erdmittelpunkt",
        "progress"          => "Fortschritt",
        "twilightcivil"     => "Bürgerliche Dämmerung",
        "twilightnautic"    => "Nautische Dämmerung",
        "twilightastro"     => "Astronomische Dämmerung",
        "twilightcustom"    => "Konfigurierte Dämmerung",
        "sign"              => "Tierkreiszeichen",
        "dst"               => "Sommerzeit",
        "nt"                => "Normalzeit",
        "switchtodst"       => "Umstellung vorwärts auf Sommerzeit",
        "switchtont"        => "Umstellung zurück auf Normalzeit",
        "hoursofsunlight"   => "Tagesstunden",
        "hoursofnight"      => "Nachtstunden",
        "hoursofvisibility" => "Sichtbarkeit",

        #--
        "time"          => "Zeit",
        "date"          => "Datum",
        "jdate"         => "Julianisches Datum",
        "dayofyear"     => "Tag d. Jahres",
        "days"          => "Tage",
        "timezone"      => "Zeitzone",
        "lmst"          => "Lokale Sternzeit",

        #--
        "season" => "Astronomische Jahreszeit",
        "spring" => "Frühling",
        "summer" => "Sommer",
        "fall"   => "Herbst",
        "winter" => "Winter",

        #--
        "aries"       => "Widder",
        "taurus"      => "Stier",
        "gemini"      => "Zwillinge",
        "cancer"      => "Krebs",
        "leo"         => "Löwe",
        "virgo"       => "Jungfrau",
        "libra"       => "Waage",
        "scorpio"     => "Skorpion",
        "sagittarius" => "Schütze",
        "capricorn"   => "Steinbock",
        "aquarius"    => "Wassermann",
        "pisces"      => "Fische",

        #--
        "sun" => "Sonne",

        #--
        "moon"           => "Mond",
        "phase"          => "Phase",
        "newmoon"        => "Neumond",
        "waxingcrescent" => "Zunehmende Sichel",
        "firstquarter"   => "Erstes Viertel",
        "waxingmoon"     => "Zunehmender Mond",
        "fullmoon"       => "Vollmond",
        "waningmoon"     => "Abnehmender Mond",
        "lastquarter"    => "Letztes Viertel",
        "waningcrescent" => "Abnehmende Sichel",
    },

    ES => {
        "coord"             => "Coordenadas",
        "position"          => "Posición",
        "longitude"         => "Longitud",
        "latitude"          => "Latitud",
        "altitude"          => "Altura sobre el mar",
        "lonecl"            => "Longitud eclíptica",
        "latecl"            => "Latitud eclíptica",
        "ra"                => "Ascensión recta",
        "dec"               => "Declinación",
        "az"                => "Azimut",
        "alt"               => "Ángulo horizonte",
        "age"               => "Años",
        "rise"              => "Salida",
        "set"               => "Puesta",
        "transit"           => "Culminación",
        "distance"          => "Distancia",
        "diameter"          => "Diámetro",
        "toobs"             => "al observar",
        "toce"              => "al centro de la tierra",
        "progress"          => "Progreso",
        "twilightcivil"     => "Crepúsculo civil",
        "twilightnautic"    => "Crepúsculo náutico",
        "twilightastro"     => "Crepúsculo astronómico",
        "twilightcustom"    => "Crepúsculo personalizado",
        "sign"              => "Signo del zodiaco",
        "dst"               => "horario de verano",
        "nt"                => "hora estándar",
        "switchtodst"       => "Conversión adelante a la hora de verano",
        "switchtont"        => "Conversión hacia atrás a la hora estándar",
        "hoursofsunlight"   => "Horas de luz solar",
        "hoursofnight"      => "Horas de la noche",
        "hoursofvisibility" => "Visibilidad",

        #--
        "time"          => "Tiempo",
        "date"          => "Fecha",
        "jdate"         => "Fecha de Julian",
        "dayofyear"     => "Día del año",
        "days"          => "Días",
        "timezone"      => "Zona horaria",
        "lmst"          => "Hora sideral local",

        #--
        "season" => "Temporada Astronomica",
        "spring" => "Primavera",
        "summer" => "Verano",
        "fall"   => "Otoño",
        "winter" => "Invierno",

        #--
        "aries"       => "Aries",
        "taurus"      => "Tauro",
        "gemini"      => "Geminis",
        "cancer"      => "Cáncer",
        "leo"         => "León",
        "virgo"       => "Virgo",
        "libra"       => "Libra",
        "scorpio"     => "Escorpión",
        "sagittarius" => "Sagitario",
        "capricorn"   => "Capricornio",
        "aquarius"    => "Acuario",
        "pisces"      => "Piscis",

        #--
        "sun" => "Sol",

        #--
        "moon"           => "Luna",
        "phase"          => "Fase",
        "newmoon"        => "Luna nueva",
        "waxingcrescent" => "Luna creciente",
        "firstquarter"   => "Primer cuarto",
        "waxingmoon"     => "Luna creciente",
        "fullmoon"       => "Luna llena",
        "waningmoon"     => "Luna menguante",
        "lastquarter"    => "Último cuarto",
        "waningcrescent" => "Creciente menguante",
    },

    FR => {
        "coord"             => "Coordonnées",
        "position"          => "Position",
        "longitude"         => "Longitude",
        "latitude"          => "Latitude",
        "altitude"          => "Hauteur au dessus de la mer",
        "lonecl"            => "Longitude écliptique",
        "latecl"            => "Latitude écliptique",
        "ra"                => "Ascension droite",
        "dec"               => "Déclinaison",
        "az"                => "Azimut",
        "alt"               => "Angle horizon",
        "age"               => "Âge",
        "rise"              => "Lever",
        "set"               => "Coucher",
        "transit"           => "Culmination",
        "distance"          => "Distance",
        "diameter"          => "Diamètre",
        "toobs"             => "à l'observateur",
        "toce"              => "au centre de la terre",
        "progress"          => "Progrès",
        "twilightcivil"     => "Crépuscule civil",
        "twilightnautic"    => "Crépuscule nautique",
        "twilightastro"     => "Crépuscule astronomique",
        "twilightcustom"    => "Crépuscule personnalisé",
        "sign"              => "Signe du zodiaque",
        "dst"               => "heure d'été",
        "nt"                => "heure normale",
        "switchtodst"       => "Conversion en avant à l'heure d'été",
        "switchtont"        => "Conversion de retour à l'heure normale",
        "hoursofsunlight"   => "Heures de soleil",
        "hoursofnight"      => "Heures de la nuit",
        "hoursofvisibility" => "Visibilité",

        #--
        "time"          => "Temps",
        "date"          => "Date",
        "jdate"         => "Date de Julien",
        "dayofyear"     => "jour de l'année",
        "days"          => "jours",
        "timezone"      => "Fuseau horaire",
        "lmst"          => "Heure sidérale locale",

        #--
        "season" => "Saison Astronomique",
        "spring" => "Printemps",
        "summer" => "Été",
        "fall"   => "Automne",
        "winter" => "Hiver",

        #--
        "aries"       => "bélier",
        "taurus"      => "Taureau",
        "gemini"      => "Gémeaux",
        "cancer"      => "Cancer",
        "leo"         => "Lion",
        "virgo"       => "Jeune fille",
        "libra"       => "Balance",
        "scorpio"     => "Scorpion",
        "sagittarius" => "Sagittaire",
        "capricorn"   => "Capricorne",
        "aquarius"    => "Verseau",
        "pisces"      => "Poissons",

        #--
        "sun" => "Soleil",

        #--
        "moon"           => "Lune",
        "phase"          => "Phase",
        "newmoon"        => "Nouvelle lune",
        "waxingcrescent" => "Croissant croissant",
        "firstquarter"   => "Premier quart",
        "waxingmoon"     => "Lune croissante",
        "fullmoon"       => "Pleine lune",
        "waningmoon"     => "Lune décroissante",
        "lastquarter"    => "Le dernier quart",
        "waningcrescent" => "Croissant décroissant",
    },

    IT => {
        "coord"             => "Coordinate",
        "position"          => "Posizione",
        "longitude"         => "Longitudine",
        "latitude"          => "Latitudine",
        "altitude"          => "Altezza sopra il mare",
        "lonecl"            => "Longitudine ellittica",
        "latecl"            => "Latitudine eclittica",
        "ra"                => "Giusta ascensione",
        "dec"               => "Declinazione",
        "az"                => "Azimut",
        "alt"               => "Angolo di orizzonte",
        "age"               => "Età",
        "rise"              => "Crescente",
        "set"               => "Affondamento",
        "transit"           => "Culmine",
        "distance"          => "Distanza",
        "diameter"          => "Diametro",
        "toobs"             => "verso l'osservatore",
        "toce"              => "verso centro della terra",
        "progress"          => "Progresso",
        "twilightcivil"     => "Crepuscolo civile",
        "twilightnautic"    => "Crepuscolo nautico",
        "twilightastro"     => "Crepuscolo astronomico",
        "twilightcustom"    => "Crepuscolo personalizzato",
        "sign"              => "Segno zodiacale",
        "dst"               => "ora legale",
        "nt"                => "ora standard",
        "switchtodst"       => "Conversione in avanti a ora legale",
        "switchtont"        => "Conversione a ritroso in ora standard",
        "hoursofsunlight"   => "Ore di luce solare",
        "hoursofnight"      => "Ore della notte",
        "hoursofvisibility" => "Visibilità",

        #--
        "time"          => "Tempo",
        "date"          => "Data",
        "jdate"         => "Data giuliana",
        "dayofyear"     => "giorno dell'anno",
        "days"          => "giorni",
        "timezone"      => "Fuso orario",
        "lmst"          => "Tempo siderale locale",

        #--
        "season" => "Stagione Astronomica",
        "spring" => "Stagione primaverile",
        "summer" => "Estate",
        "fall"   => "Autunno",
        "winter" => "Inverno",

        #--
        "aries"       => "Ariete",
        "taurus"      => "Toro",
        "gemini"      => "Gemelli",
        "cancer"      => "Cancro",
        "leo"         => "Leone",
        "virgo"       => "Vergine",
        "libra"       => "Libra",
        "scorpio"     => "Scorpione",
        "sagittarius" => "Arciere",
        "capricorn"   => "Capricorno",
        "aquarius"    => "Acquario",
        "pisces"      => "Pesci",

        #--
        "sun" => "Sole",

        #--
        "moon"           => "Luna",
        "phase"          => "Fase",
        "newmoon"        => "Nuova luna",
        "waxingcrescent" => "Luna crescente",
        "firstquarter"   => "Primo quarto",
        "waxingmoon"     => "Luna crescente",
        "fullmoon"       => "Luna piena",
        "waningmoon"     => "Luna calante",
        "lastquarter"    => "Ultimo quarto",
        "waningcrescent" => "Pericolo crescente",
    },

    NL => {
        "coord"             => "Coördinaten",
        "position"          => "Positie",
        "longitude"         => "Lengtegraad",
        "latitude"          => "Breedtegraad",
        "altitude"          => "Hoogte b. Zee",
        "lonecl"            => "Eclipticale Lengtegraad",
        "latecl"            => "Eclipticale Breedtegraad",
        "ra"                => "Juiste klimming",
        "dec"               => "Declinatie",
        "az"                => "Azimuth",
        "alt"               => "Horizon Angle",
        "age"               => "Leeftijd",
        "rise"              => "Opkomst",
        "set"               => "Ondergang",
        "transit"           => "Culminatie",
        "distance"          => "Afstand",
        "diameter"          => "Diameter",
        "toobs"             => "voor de Waarnemer",
        "toce"              => "naar het Middelpunt van de Aarde",
        "progress"          => "Vooruitgang",
        "twilightcivil"     => "Burgerlijke Schemering",
        "twilightnautic"    => "Nautische Schemering",
        "twilightastro"     => "Astronomische Schemering",
        "twilightcustom"    => "Aangepaste Schemering",
        "sign"              => "Sterrenbeeld",
        "dst"               => "Zomertijd",
        "nt"                => "Standaardtijd",
        "switchtodst"       => "Voorwaartse omschakeling naar de zomertijd",
        "switchtont"        => "Omzetting terug naar de normale tijd",
        "hoursofsunlight"   => "Dagen Uur",
        "hoursofnight"      => "Uren van de Nacht",
        "hoursofvisibility" => "Zichtbaarheid",

        #--
        "time"          => "Tijd",
        "date"          => "Datum",
        "jdate"         => "Juliaanse Datum",
        "dayofyear"     => "Dag van het Jaar",
        "days"          => "Dagen",
        "timezone"      => "Tijdzone",
        "lmst"          => "Lokale Sterrentijd",

        #--
        "season" => "Astronomisch Seizoen",
        "spring" => "De lente",
        "summer" => "Zomer",
        "fall"   => "Herfst",
        "winter" => "Winter",

        #--
        "aries"       => "Ram",
        "taurus"      => "Stier",
        "gemini"      => "Tweelingen",
        "cancer"      => "Kanker",
        "leo"         => "Leeuw",
        "virgo"       => "Maagd",
        "libra"       => "Weegschaal",
        "scorpio"     => "Schorpioen",
        "sagittarius" => "Boogschutter",
        "capricorn"   => "Steenbok",
        "aquarius"    => "Waterman",
        "pisces"      => "Vis",

        #--
        "sun" => "Zon",

        #--
        "moon"           => "Maan",
        "phase"          => "Fase",
        "newmoon"        => "Nieuwe Maan",
        "waxingcrescent" => "Wassende halve Maan",
        "firstquarter"   => "Eerste Kwartier",
        "waxingmoon"     => "Wassende Maan",
        "fullmoon"       => "Volle Maan",
        "waningmoon"     => "Afnemende Maan",
        "lastquarter"    => "Het laatste Kwartier",
        "waningcrescent" => "Afnemende halve Maan",
    },

    PL => {
        "coord"             => "Współrzędne",
        "position"          => "Pozycja",
        "longitude"         => "Długość",
        "latitude"          => "Szerokość",
        "altitude"          => "Wysokość nad morzem",
        "lonecl"            => "Długość ekliptyczna",
        "latecl"            => "Szerokość ekliptyczna",
        "ra"                => "Rektascencja",
        "dec"               => "Deklinacja",
        "az"                => "Azymut",
        "alt"               => "Kąt horyzont",
        "age"               => "Wiek",
        "rise"              => "Wschód",
        "set"               => "Zachód",
        "transit"           => "Kulminacja",
        "distance"          => "Dystans",
        "diameter"          => "Średnica",
        "toobs"             => "w kierunku obserwatora",
        "toce"              => "w kierunku środka ziemi",
        "progress"          => "Postęp",
        "twilightcivil"     => "Zmierzch cywilny",
        "twilightnautic"    => "Zmierzch morski",
        "twilightastro"     => "Zmierzch astronomiczny",
        "twilightcustom"    => "Zmierzch niestandardowy",
        "sign"              => "Znak zodiaku",
        "dst"               => "czas letni",
        "nt"                => "standardowy czas",
        "switchtodst"       => "Przeliczenie napastnicy na czas letni",
        "switchtont"        => "Przeliczanie wstecz do czasu normalnego",
        "hoursofsunlight"   => "Godziny światła słonecznego",
        "hoursofnight"      => "Godziny nocy",
        "hoursofvisibility" => "Widoczność",

        #--
        "time"          => "Czas",
        "date"          => "Data",
        "jdate"         => "Juliańska data",
        "dayofyear"     => "dzień roku",
        "days"          => "dni",
        "timezone"      => "Strefa czasowa",
        "lmst"          => "Lokalny czas gwiazdowy",

        #--
        "season" => "Sezon Astronomiczny",
        "spring" => "Wiosna",
        "summer" => "Lato",
        "fall"   => "Jesień",
        "winter" => "Zima",

        #--
        "aries"       => "Baran",
        "taurus"      => "Byk",
        "gemini"      => "Bliźnięta",
        "cancer"      => "Rak",
        "leo"         => "Lew",
        "virgo"       => "Panna",
        "libra"       => "Libra",
        "scorpio"     => "Skorpion",
        "sagittarius" => "Strzelec",
        "capricorn"   => "Koziorożec",
        "aquarius"    => "Wodnik",
        "pisces"      => "Ryby",

        #--
        "sun" => "Słońce",

        #--
        "moon"           => "Księżyc",
        "phase"          => "Faza",
        "newmoon"        => "Nów",
        "waxingcrescent" => "Półksiężyc woskowy",
        "firstquarter"   => "Pierwszym kwartale",
        "waxingmoon"     => "Księżyc przybywający",
        "fullmoon"       => "Pełnia księżyca",
        "waningmoon"     => "Zmniejszający się księżyc",
        "lastquarter"    => "Ostatni kwartał",
        "waningcrescent" => "Zwiększający się księżyc",
    }
);

our @zodiac = ("aries","taurus","gemini","cancer","leo","virgo",
    "libra","scorpio","sagittarius","capricorn","aquarius","pisces");

our @phases = ("newmoon","waxingcrescent", "firstquarter", "waxingmoon", 
    "fullmoon", "waningmoon", "lastquarter", "waningcrescent");

our %seasons = (
    N => [ "winter", "spring", "summer", "fall" ],
    S => [ "summer", "fall", "winter", "spring" ]
);

#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          attr
          AttrVal
          data
          Debug
          defs
          deviceEvents
          FmtDateTime
          FW_pO
          FW_RET
          FW_RETTYPE
          FW_webArgs
          GetType
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3
          maxNum
          minNum
          modules
          readingFnAttributes
          readingsBeginUpdate
          readingsBulkUpdateIfChanged
          readingsEndUpdate
          readingsSingleUpdate
          RemoveInternalTimer
          time_str2num
          toJSON
          )
    );

    # Export to main context
    GP_Export(
        qw(
          Get
          Initialize
          )
    );
}

_LoadOptionalPackages();

sub SunRise($$$$$$$$);
sub MoonRise($$$$$$$);
sub SetTime(;$$$);
sub Compute($;$);

########################################################################################################
#
# Initialize 
# 
#  Parameter hash = hash of device addressed 
#
########################################################################################################

sub Initialize ($) {
  my ($hash) = @_;
		
  $hash->{DefFn}       = "FHEM::Astro::Define";
  $hash->{SetFn}       = "FHEM::Astro::Set";  
  $hash->{GetFn}       = "FHEM::Astro::Get";
  $hash->{UndefFn}     = "FHEM::Astro::Undef";   
  $hash->{AttrFn}      = "FHEM::Astro::Attr";    
  $hash->{NotifyFn}    = "FHEM::Astro::Notify";
  $hash->{AttrList}    = join (" ", map {
                                    defined($attrs{$_}) ? "$_:$attrs{$_}" : $_
                                  } sort keys %attrs
                         )
                         ." "
                         .$readingFnAttributes;

  $hash->{parseParams} = 1;

  $data{FWEXT}{"/Astro_moonwidget"}{FUNC} = "FHEM::Astro::Moonwidget";
  $data{FWEXT}{"/Astro_moonwidget"}{FORKABLE} = 0;		
	
  return FHEM::Meta::InitMod( __FILE__, $hash );
}

########################################################################################################
#
# Define - Implements DefFn function
# 
#  Parameter hash = hash of device addressed, a = array of arguments, h = hash of parameters
#
########################################################################################################

sub Define ($@) {
 my ($hash,$a,$h) = @_;
 my $name = shift @$a;
 my $type = shift @$a;

 return $@ unless ( FHEM::Meta::SetInternals($hash) );
 use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

 $hash->{NOTIFYDEV} = "global";
 $hash->{INTERVAL} = 3600;
 readingsSingleUpdate( $hash, "state", "Initialized", $init_done ); 
 
 $modules{Astro}{defptr}{$name} = $hash;

 # for the very first definition, set some default attributes
 if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
   $attr{$name}{icon}        = 'telescope';
   $attr{$name}{recomputeAt} = 'NewDay,SunRise,SunSet,AstroTwilightEvening,AstroTwilightMorning,CivilTwilightEvening,CivilTwilightMorning,CustomTwilightEvening,CustomTwilightMorning';
   $hash->{RECOMPUTEAT} = $attr{$name}{recomputeAt};
 }

 return undef;
}

########################################################################################################
#
# Undef - Implements Undef function
# 
#  Parameter hash = hash of device addressed, arg = array of arguments
#
########################################################################################################

sub Undef ($$) {
  my ($hash,$arg) = @_;
  
  RemoveInternalTimer($hash);
  
  return undef;
}

########################################################################################################
#
# Notify - Implements Notify function
# 
#  Parameter hash = hash of device addressed, dev = hash of device that triggered notification
#
########################################################################################################

sub Notify ($$) {
  my ($hash,$dev) = @_;
  my $name    = $hash->{NAME};
  my $TYPE    = $hash->{TYPE};
  my $devName = $dev->{NAME};
  my $devType = GetType($devName);

  if ( $devName eq "global" ) {
    my $events = deviceEvents( $dev, 1 );
    return "" unless ($events);

    foreach my $event ( @{$events} ) {
      next unless ( defined($event) );
      next if ( $event =~ m/^[A-Za-z\d_-]+:/ );

      if ( $event =~ m/^INITIALIZED|REREADCFG$/ ) {
        if ( ( defined( $hash->{INTERVAL} ) && $hash->{INTERVAL} > 0 )
            || defined( $hash->{RECOMPUTEAT} ) )
        {
            RemoveInternalTimer($hash);
            InternalTimer(gettimeofday()+5,"FHEM::Astro::Update",$hash,0);
        }
      }
      elsif ( $event =~
          m/^(DEFINED|MODIFIED)\s+([A-Za-z\d_-]+)$/ &&
          $2 eq $name )
      {
        if ( ( defined( $hash->{INTERVAL} ) && $hash->{INTERVAL} > 0 )
            || defined( $hash->{RECOMPUTEAT} ) )
        {
          RemoveInternalTimer($hash);
          InternalTimer(gettimeofday()+1,"FHEM::Astro::Update",$hash,0);
        }
      }

      # only process attribute events
      next
        unless ( $event =~
m/^((?:DELETE)?ATTR)\s+([A-Za-z\d._]+)\s+([A-Za-z\d_\.\-\/]+)(?:\s+(.*)\s*)?$/
        );

      my $cmd  = $1;
      my $d    = $2;
      my $attr = $3;
      my $val  = $4;
      my $type = GetType($d);

      # filter attributes to be processed
      next
        unless ( $attr eq "altitude"
          || $attr eq "language"
          || $attr eq "latitude"
          || $attr eq "lc_numeric"
          || $attr eq "lc_time"
          || $attr eq "longitude"
          || $attr eq "timezone" );

      # when global attributes were changed
      if ( $d eq "global" ) {
        RemoveInternalTimer($hash);
        InternalTimer( gettimeofday() + 1,
            "FHEM::Astro::Update", $hash, 0 );
      }
    }
  }

  return undef;
}

########################################################################################################
#
# Attr - Implements Attr function
# 
#  Parameter do = action, name = name of device, key = attribute name, value = attribute value
#
########################################################################################################

sub Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
  if ( $do eq "set") {
    ARGUMENT_HANDLER: {
      #-- altitude modified at runtime
      $key eq "altitude" and do {
        #-- check value
        return "[Astro] $do $name attribute $key must be a float number >= 0 meters"
          unless($value =~ m/^(\d+(?:\.\d+)?)$/ && $1 >= 0.);
      };
      #-- disable modified at runtime
      $key eq "disable" and do {
        #-- check value
        return "[Astro] $do $name attribute $key can only be 1 or 0"
          unless($value =~ m/^(1|0)$/);
        readingsSingleUpdate($hash,"state",$value?"inactive":"Initialized",$init_done);
      };
      #-- horizon modified at runtime
      $key eq "horizon" and do {
        #-- check value
        return "[Astro] $do $name attribute $key must be a float number >= -45 and <= 45 degrees"
          unless($value =~ m/^(-?\d+(?:\.\d+)?)(?::(-?\d+(?:\.\d+)?))?$/ && $1 >= -45. && $1 <= 45. && (!$2 || $2 >= -45. && $2 <= 45.));
      };
      #-- interval modified at runtime
      $key eq "interval" and do {
        #-- check value
        return "[Astro] $do $name attribute $key must be >= 0 seconds"
          unless($value =~ m/^\d+$/);
        #-- update timer
        $hash->{INTERVAL} = $value;
      };
      #-- latitude modified at runtime
      $key eq "latitude" and do {
        #-- check value
        return "[Astro] $do $name attribute $key must be float number >= -90 and <= 90 degrees"
          unless($value =~ m/^(-?\d+(?:\.\d+)?)$/ && $1 >= -90. && $1 <= 90.);
      };
      #-- longitude modified at runtime
      $key eq "longitude" and do {
        #-- check value
        return "[Astro] $do $name attribute $key must be float number >= -180 and <= 180 degrees"
          unless($value =~ m/^(-?\d+(?:\.\d+)?)$/ && $1 >= -180. && $1 <= 180.);
      };
      #-- recomputeAt modified at runtime
      $key eq "recomputeAt" and do {
        my @skel = split(',', $attrs{recomputeAt});
        shift @skel;
        #-- check value 1/2
        return "[Astro] $do $name attribute $key must be one or many of ".join(',', @skel)
          if(!$value || $value eq "");
        #-- check value 2/2
        my @vals = split(',', $value);
        foreach my $val (@vals) {
          return "[Astro] $do $name attribute value $val is invalid, must be one or many of ".join(',', @skel)
            unless(grep( m/^$val$/, @skel ));          
        }
        $hash->{RECOMPUTEAT} = join(',', @vals);
      };
    }
  }

  elsif ( $do eq "del") {
    readingsSingleUpdate($hash,"state","Initialized",$init_done)
      if ($key eq "disable");
    $hash->{INTERVAL} = 3600
      if ($key eq "interval");
    delete $hash->{RECOMPUTEAT}
      if ($key eq "recomputeAt");
  }

  if (   $init_done
      && exists( $attrs{$key} )
      && ( $hash->{INTERVAL} > 0 || $hash->{RECOMPUTEAT} || $hash->{NEXTUPDATE} )
    )
  {
      RemoveInternalTimer($hash);
      InternalTimer( gettimeofday() + 2, "FHEM::Astro::Update", $hash, 0 );
  }

  return $ret;
}

sub _mod($$) { my ($a,$b)=@_;if( $a =~ /\d*\.\d*/){return($a-floor($a/$b)*$b)}else{return undef}; }
sub _mod2Pi($) { my ($x)=@_;$x = _mod($x, 2.*pi);return($x); }
sub _round($$) { my ($x,$n)=@_; return int(10**$n*$x+0.5)/10**$n};

sub _tzoffset($) {
    my ($t)   = @_;
    my $utc   = mktime(gmtime($t));
    #-- the following does not properly calculate dst
    my $local = mktime(localtime($t));
    #-- this is the correction
    my $isdst = (localtime($t))[8];
    #-- correction
    if($isdst == 1){
      $local+=3600;
    }
    return (($local - $utc)/36);
}

########################################################################################################
#
# _LoadOptionalPackages - Load Perl packages that may not be installed
# 
########################################################################################################

sub _LoadOptionalPackages {

    # JSON preference order
    local $ENV{PERL_JSON_BACKEND} =
      'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
      unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

    # try to use JSON::MaybeXS wrapper
    #   for chance of better performance + open code
    eval {
        require JSON::MaybeXS;
        $json = JSON::MaybeXS->new;
        1;
    };
    if ($@) {
        $@ = undef;

        # try to use JSON wrapper
        #   for chance of better performance
        eval {
            require JSON;
            $json = JSON->new;
            1;
        };

        if ($@) {
            $@ = undef;

            # In rare cases, Cpanel::JSON::XS may
            #   be installed but JSON|JSON::MaybeXS not ...
            eval {
                require Cpanel::JSON::XS;
                $json = Cpanel::JSON::XS->new;
                1;
            };

            if ($@) {
                $@ = undef;

                # In rare cases, JSON::XS may
                #   be installed but JSON not ...
                eval {
                    require JSON::XS;
                    $json = JSON::XS->new;
                    1;
                };

                if ($@) {
                    $@ = undef;

                    # Fallback to built-in JSON which SHOULD
                    #   be available since 5.014 ...
                    eval {
                        require JSON::PP;
                        $json = JSON::PP->new;
                        1;
                    };

                    if ($@) {
                        $@ = undef;

                        # Last chance may be a backport
                        eval {
                            require JSON::backportPP;
                            $json = JSON::backportPP->new;
                            1;
                        };
                        $@ = undef if ($@);
                    }
                }
            }
        }
    }

    if ($@) {
      $@ = undef;
    } else {
      $json->allow_nonref;
      $json->shrink;
      $json->utf8;
    }
}

########################################################################################################
#
# time fragments into minutes, seconds
#
########################################################################################################  
  
sub HHMM($){
  my ($hh) = @_;
  return("---")
    if (!defined($hh) || $hh !~ /^-?\d+/ || $hh==0) ;
  
  my $h = floor($hh);
  my $m = ($hh-$h)*60.;
  return sprintf("%02d:%02d",$h,$m);
}

sub HHMMSS($){
  my ($hh) = @_;
  return("---")
    if (!defined($hh) || $hh !~ /^-?\d+/ || $hh==0) ;
  
  my $m = ($hh-floor($hh))*60.;
  my $s = ($m-floor($m))*60;
  my $h = floor($hh);
  return sprintf("%02d:%02d:%02d",$h,$m,$s);
}

########################################################################################################
#
# Date2JD - Calculate Julian date, adopted from Perl CPAN module Astro::Coord::ECI::Utils
#
########################################################################################################

sub Date2JD {
    my @args = @_;
    unshift @args, 0 while @args < 6.;
    my ( $sec, $min, $hr, $day, $mon, $yr ) = @args;
    return undef if ( ( $yr < -4712. ) or ( $mon < 1. || $mon > 12. ) );
    if ( $mon < 3. ) {
        --$yr;
        $mon += 12.;
    }

    my $JD_GREGORIAN = 2299160.5;
    my $A            = floor( $yr / 100 );
    my $B            = 2 - $A + floor( $A / 4 );
    my $jd =
      floor( 365.25 *  ( $yr + 4716 ) ) +
      floor( 30.6001 * ( $mon + 1 ) ) +
      $day + $B - 1524.5 +
      ( ( ( $sec || 0 ) / 60 + ( $min || 0 ) ) / 60 + ( $hr || 0 ) ) / 24;
    $jd < $JD_GREGORIAN
      and $jd =
      floor( 365.25 *  ( $yr + 4716 ) ) +
      floor( 30.6001 * ( $mon + 1 ) ) +
      $day - 1524.5 +
      ( ( ( $sec || 0 ) / 60 + ( $min || 0 ) ) / 60 + ( $hr || 0 ) ) / 24;
    return $jd;
}

########################################################################################################
#
# GMST - Julian Date to Greenwich Mean Sidereal Time
#
########################################################################################################

sub GMST($){
  my ($JD) = @_;
  my $UT   = ($JD-0.5) - int($JD-0.5);
  $UT      = $UT*24.;              # UT in hours
  $JD      = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  my $T    = ($JD-2451545.0)/36525.0;
  my $T0   = 6.697374558 + $T*(2400.051336 + $T*0.000025862);
  
  return( _mod($T0+$UT*1.002737909,24.));
}

########################################################################################################
#
# GMST2UT - Convert Greenweek mean sidereal time to UT
#
########################################################################################################

sub GMST2UT($$){
  my ($JD, $gmst) = @_;
  $JD             = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  my $T           = ($JD-2451545.0)/36525.0;
  my $T0          = _mod(6.697374558 + $T*(2400.051336 + $T*0.000025862), 24.);
  my $UT          = 0.9972695663*(($gmst-$T0));
  return($UT);
}

########################################################################################################
#
# GMST2LMST - Local Mean Sidereal Time, geographical longitude in radians, 
#                   East is positive
#
########################################################################################################

sub GMST2LMST($$){
  my ($gmst, $lon) = @_;
  my $lmst = _mod($gmst+$RAD*$lon/15, 24.);
  return( $lmst );
}

########################################################################################################
#
# Ecl2Equ - Transform ecliptical coordinates (lon/lat) to equatorial coordinates (RA/dec)
#
########################################################################################################

sub Ecl2Equ($$$){
  my ($lon, $lat, $TDT) = @_;
  my $T = ($TDT-2451545.0)/36525.; # Epoch 2000 January 1.5
  my $eps = (23.+(26+21.45/60.)/60. + $T*(-46.815 +$T*(-0.0006 + $T*0.00181) )/3600. )*$DEG;
  my $coseps = cos($eps);
  my $sineps = sin($eps);
  my $sinlon = sin($lon);
  my $ra  = _mod2Pi(atan2( ($sinlon*$coseps-tan($lat)*$sineps), cos($lon) ));  
  my $dec = asin( sin($lat)*$coseps + cos($lat)*$sineps*$sinlon );
 
  return ($ra,$dec);
}

########################################################################################################
#
# Equ2Altaz - Transform equatorial coordinates (RA/Dec) to horizontal coordinates 
#                   (azimuth/altitude). Refraction is ignored
#
########################################################################################################

sub Equ2Altaz($$$$$){
  my ($ra, $dec, $TDT, $lat, $lmst)=@_;
  my $cosdec = cos($dec);
  my $sindec = sin($dec);
  my $lha    = $lmst - $ra;
  my $coslha = cos($lha);
  my $sinlha = sin($lha);
  my $coslat = cos($lat);
  my $sinlat = sin($lat);
  
  my $N      = -$cosdec * $sinlha;
  my $D      = $sindec * $coslat - $cosdec * $coslha * $sinlat;
  my $az     = _mod2Pi( atan2($N, $D) );
  my $alt    = asin( $sindec * $sinlat + $cosdec * $coslha * $coslat );

  return ($az,$alt);
}

########################################################################################################
#
# GeoEqu2TopoEqu - Transform geocentric equatorial coordinates (RA/Dec) to 
#                        topocentric equatorial coordinates
#
########################################################################################################

sub GeoEqu2TopoEqu($$$$$$$){
  my ($ra, $dec, $distance, $lon, $lat, $radius, $lmst) = @_;

  my $cosdec = cos($dec);
  my $sindec = sin($dec);
  my $coslst = cos($lmst);
  my $sinlst = sin($lmst);
  my $coslat = cos($lat); # we should use geocentric latitude, not geodetic latitude
  my $sinlat = sin($lat);
  my $rho    = $radius; # observer-geocenter in km
  
  my $x = $distance*$cosdec*cos($ra) - $rho*$coslat*$coslst;
  my $y = $distance*$cosdec*sin($ra) - $rho*$coslat*$sinlst;
  my $z = $distance*$sindec - $rho*$sinlat;

  my $distanceTopocentric = sqrt($x*$x + $y*$y + $z*$z);
  my $decTopocentric = asin($z/$distanceTopocentric);
  my $raTopocentric = _mod2Pi( atan2($y, $x) );

  return ( ($distanceTopocentric,$decTopocentric,$raTopocentric) );
}

########################################################################################################
#
# EquPolar2Cart - Calculate cartesian from polar coordinates
#
########################################################################################################

sub EquPolar2Cart($$$){
  my ($lon,$lat,$distance) = @_;
  my $rcd = cos($lat)*$distance;
  my $x   = $rcd*cos($lon);
  my $y   = $rcd*sin($lon);
  my $z   = sin($lat)*$distance;
  return( ($x,$y,$z) );
}

########################################################################################################
#
# Observer2EquCart - Calculate observers cartesian equatorial coordinates (x,y,z in celestial frame) 
#                    from geodetic coordinates (longitude, latitude, height above WGS84 ellipsoid)
#                    Currently only used to calculate distance of a body from the observer
#
########################################################################################################

sub Observer2EquCart($$$$){
  my ($lon, $lat, $height, $gmst ) = @_;

  my $flat   = 298.257223563;        # WGS84 flatening of earth
  my $aearth = 6378.137;             # GRS80/WGS84 semi major axis of earth ellipsoid

  #-- Calculate geocentric latitude from geodetic latitude
  my $co = cos ($lat);
  my $si = sin ($lat);
  $si    = $si * $si;
  my $fl = 1.0 - 1.0 / $flat;
  $fl    = $fl * $fl;
  my $u  = 1.0 / sqrt ($co * $co + $fl * $si);
  my $a  = $aearth * $u + $height;
  my $b  = $aearth * $fl * $u + $height;
  my $radius = sqrt ($a * $a * $co *$co + $b *$b * $si); # geocentric distance from earth center
  my $y  = acos ($a * $co / $radius); # geocentric latitude, rad
  my $x  = $lon; # longitude stays the same
  my $z;
  if ($lat < 0.0) { $y = -$y; } # adjust sign
  
  #-- convert from geocentric polar to geocentric cartesian, with regard to Greenwich
  ($x,$y,$z) = EquPolar2Cart( $x, $y, $radius ); 
  
  #-- rotate around earth's polar axis to align coordinate system from Greenwich to vernal equinox
  my $rotangle = $gmst/24*2*pi; # sideral time gmst given in hours. Convert to radians
  my $x2 = $x*cos($rotangle) - $y*sin($rotangle);
  my $y2 = $x*sin($rotangle) + $y*cos($rotangle);
  
  return( ($x2,$y2,$z,$radius) );
}

########################################################################################################
#
# SunPosition - Calculate coordinates for Sun
# Coordinates are accurate to about 10s (right ascension) 
# and a few minutes of arc (declination)
# 
########################################################################################################

sub SunPosition($$$){
  my ($TDT, $observerlat, $lmst)=@_;
  
  my $D  = $TDT-2447891.5;
  my $eg = 279.403303*$DEG;
  my $wg = 282.768422*$DEG;
  my $e  = 0.016713;
  my $a  = 149598500; # km
  #-- mean angular diameter of sun
  my $diameter0 = 0.533128*$DEG; 
  
  my $MSun = 360*$DEG/365.242191*$D+$eg-$wg;
  my $nu   = $MSun + 360.*$DEG/pi*$e*sin($MSun);
  
  my %sunCoor;
  
  $sunCoor{lon}  =  _mod2Pi($nu+$wg);
  $sunCoor{lat}  = 0;
  $sunCoor{anomalyMean} = $MSun;
  
  my $distance  = (1-$e*$e)/(1+$e*cos($nu));   # distance in astronomical units
  $sunCoor{diameter} = $diameter0/$distance;        # angular diameter
  $sunCoor{distance} = $distance*$a;                # distance in km
  $sunCoor{parallax} = 6378.137/$sunCoor{distance};          # horizontal parallax

  ($sunCoor{ra},$sunCoor{dec}) = Ecl2Equ($sunCoor{lon}, $sunCoor{lat}, $TDT);
  
  #-- calculate horizontal coordinates of sun, if geographic positions is given
  if (defined($observerlat) && defined($lmst) ) {
    ($sunCoor{az},$sunCoor{alt}) = Equ2Altaz($sunCoor{ra}, $sunCoor{dec}, $TDT, $observerlat, $lmst);
  }
  $sunCoor{sign}    = floor($sunCoor{lon}*$RAD/30.);
  $sunCoor{sig}     = $zodiac[$sunCoor{sign}];
  
  return ( \%sunCoor );
}

########################################################################################################
#
# MoonPosition - Calculate data and coordinates for the Moon
#                      Coordinates are accurate to about 1/5 degree (in ecliptic coordinates)
# 
########################################################################################################

sub MoonPosition($$$$$$$){
  my ($sunlon, $sunanomalyMean, $TDT, $observerlon, $observerlat, $observerradius, $lmst) = @_;
  
  my $D = $TDT-2447891.5;
  
  #-- Mean Moon orbit elements as of 1990.0
  my $l0 = 318.351648*$DEG;
  my $P0 =  36.340410*$DEG;
  my $N0 = 318.510107*$DEG;
  my $i  = 5.145396*$DEG;
  my $e  = 0.054900;
  my $a  = 384401; # km
  my $diameter0 = 0.5181*$DEG; # angular diameter of Moon at a distance
  my $parallax0 = 0.9507*$DEG; # parallax at distance a
  
  my $l  = 13.1763966*$DEG*$D+$l0;
  my $MMoon = $l-0.1114041*$DEG*$D-$P0; # Moon's mean anomaly M
  my $N  = $N0-0.0529539*$DEG*$D;          # Moon's mean ascending node longitude
  my $C  = $l-$sunlon;
  my $Ev = 1.2739*$DEG*sin(2*$C-$MMoon);
  my $Ae = 0.1858*$DEG*sin($sunanomalyMean);
  my $A3 = 0.37*$DEG*sin($sunanomalyMean);
  my $MMoon2 = $MMoon+$Ev-$Ae-$A3;  # corrected Moon anomaly
  my $Ec = 6.2886*$DEG*sin($MMoon2);  # equation of centre
  my $A4 = 0.214*$DEG*sin(2*$MMoon2);
  my $l2 = $l+$Ev+$Ec-$Ae+$A4; # corrected Moon's longitude
  my $V  = 0.6583*$DEG*sin(2*($l2-$sunlon));
  my $l3 = $l2+$V; # true orbital longitude;

  my $N2 = $N-0.16*$DEG*sin($sunanomalyMean);
   
  my %moonCoor;
  $moonCoor{lon}      = _mod2Pi( $N2 + atan2( sin($l3-$N2)*cos($i), cos($l3-$N2) ) );
  $moonCoor{lat}      = asin( sin($l3-$N2)*sin($i) );
  $moonCoor{orbitLon} = $l3;
  
  ($moonCoor{ra},$moonCoor{dec}) = Ecl2Equ($moonCoor{lon},$moonCoor{lat},$TDT);
  #-- relative distance to semi mayor axis of lunar oribt
  my $distance = (1-$e*$e) / (1+$e*cos($MMoon2+$Ec) );
  $moonCoor{diameter} = $diameter0/$distance; # angular diameter in radians
  $moonCoor{parallax} = $parallax0/$distance; # horizontal parallax in radians
  $moonCoor{distance} = $distance*$a;         # distance in km

  #-- Calculate horizontal coordinates of moon, if geographic positions is given

  #-- backup geocentric coordinates
  $moonCoor{raGeocentric}       = $moonCoor{ra}; 
  $moonCoor{decGeocentric}      = $moonCoor{dec};
  $moonCoor{distanceGeocentric} = $moonCoor{distance};

  if (defined($observerlat) && defined($observerlon) && defined($lmst) ) {
    #-- transform geocentric coordinates into topocentric (==observer based) coordinates
	my  ($distanceTopocentric,$decTopocentric,$raTopocentric) = 
	  GeoEqu2TopoEqu($moonCoor{ra}, $moonCoor{dec}, $moonCoor{distance}, $observerlon, $observerlat, $observerradius, $lmst);
	#-- now ra and dec are topocentric
	$moonCoor{ra}  = $raTopocentric;
	$moonCoor{dec} = $decTopocentric;
    ($moonCoor{az},$moonCoor{alt})= Equ2Altaz($moonCoor{ra}, $moonCoor{dec}, $TDT, $observerlat, $lmst); 
  }
  
  #-- Age of Moon in radians since New Moon (0) - Full Moon (pi)
  $moonCoor{age}    = _mod2Pi($l3-$sunlon);   
  $moonCoor{phasen} = 0.5*(1-cos($moonCoor{age})); # Moon phase numerical, 0-1
  
  my $mainPhase = 1./29.53*360*$DEG; # show 'Newmoon, 'Quarter' for +/-1 day around the actual event
  my $p = _mod($moonCoor{age}, 90.*$DEG);
  if ($p < $mainPhase || $p > 90*$DEG-$mainPhase){
    $p = 2*floor($moonCoor{age} / (90.*$DEG)+0.5);
  }else{
    $p = 2*floor($moonCoor{age} / (90.*$DEG))+1;
  }
  $p = $p % 8;
  $moonCoor{phases} = $phases[$p]; 
  $moonCoor{phasei} = $p;
  $moonCoor{sign}   = floor($moonCoor{lon}*$RAD/30);
  $moonCoor{sig}    = $zodiac[$moonCoor{sign}];

  return ( \%moonCoor );
}

########################################################################################################
#
# Refraction - Input true altitude in radians, Output: increase in altitude in degrees
# 
########################################################################################################

sub Refraction($){
  my ($alt) = @_;
  my $altdeg = $alt*$RAD;
  if ($altdeg<-2 || $altdeg>=90){
    return(0);
  }
   
  my $pressure    = 1015;
  my $temperature = 10;
  if ($altdeg>15){
    return( 0.00452*$pressure/( (273+$temperature)*tan($alt)) );
  }
  
  my $y = $alt;
  my $D = 0.0;
  my $P = ($pressure-80.)/930.;
  my $Q = 0.0048*($temperature-10.);
  my $y0 = $y;
  my $D0 = $D;
  my $N;

  for (my $i=0; $i<3; $i++) {
	$N = $y+(7.31/($y+4.4));
    $N = 1./tan($N*$DEG);
	$D = $N*$P/(60.+$Q*($N+39.));
	$N = $y-$y0;
	$y0 = $D-$D0-$N;
	if (($N != 0.) && ($y0 != 0.)) { 
	  $N = $y-$N*($alt+$D-$y)/$y0; 
	} else { 
	  $N = $alt+$D; 
	}
	$y0 = $y;
	$D0 = $D;
	$y  = $N;
  }
  return( $D ); 
}

########################################################################################################
#
# GMSTRiseSet - returns Greenwich sidereal time (hours) of time of rise 
# and set of object with coordinates ra/dec
# at geographic position lon/lat (all values in radians)
# Correction for refraction and semi-diameter/parallax of body is taken care of in function RiseSet
# h is used to calculate the twilights. It gives the required elevation of the disk center of the sun
# 
########################################################################################################

sub GMSTRiseSet($$$$$){
  my ($ra, $dec, $lon, $lat, $h) = @_;
  
  $h = (defined($h)) ? $h : 0.0; # set default value
  #Log 1,"-------------------> Called GMSTRiseSet with $ra $dec $lon $lat $h";

  # my $tagbogen = acos(-tan(lat)*tan(coor.dec)); // simple formula if twilight is not required
  my $tagbarg  = (sin($h) - sin($lat)*sin($dec)) / (cos($lat)*cos($dec));
  if( ($tagbarg > 1.000000) || ($tagbarg < -1.000000) ){
    Log 5,"[FHEM::Astro::GMSTRiseSet] Parameters $ra $dec $lon $lat $h give complex angle";
    return( ("---","---","---") );
  };
  my $tagbogen = acos($tagbarg);

  my $transit =     $RAD/15*(          +$ra-$lon);
  my $rise    = 24.+$RAD/15*(-$tagbogen+$ra-$lon); # calculate GMST of rise of object
  my $set     =     $RAD/15*(+$tagbogen+$ra-$lon); # calculate GMST of set of object

  #--Using the modulo function mod, the day number goes missing. This may get a problem for the moon
  $transit = _mod($transit, 24);
  $rise    = _mod($rise, 24);
  $set     = _mod($set, 24);
  
  return( ($transit, $rise, $set) );
}

########################################################################################################
#
# InterpolateGMST - Find GMST of rise/set of object from the two calculated 
# (start)points (day 1 and 2) and at midnight UT(0)
# 
########################################################################################################

sub InterpolateGMST($$$$){
  my ($gmst0, $gmst1, $gmst2, $timefactor) = @_;
  return( ($timefactor*24.07*$gmst1- $gmst0*($gmst2-$gmst1)) / ($timefactor*24.07+$gmst1-$gmst2) );
}

########################################################################################################
#
# RiseSet
#    // JD is the Julian Date of 0h UTC time (midnight)
# 
########################################################################################################

sub RiseSet($$$$$$$$$$$){
  my ($jd0UT, $diameter, $parallax, $ra1, $dec1, $ra2, $dec2, $lon, $lat, $timeinterval, $altip) = @_;
 
  #--altitude of sun center: semi-diameter, horizontal parallax and (standard) refraction of 34'
  #  true height of sun center for sunrise and set calculation. Is kept 0 for twilight (ie. altitude given):
  my $alt      = (!defined($altip)) ? 0.5*$diameter-$parallax+34./60*$DEG : 0.; 
  my $altitude = (!defined($altip)) ? 0. : $altip; 

  my ($transit1, $rise1, $set1) = GMSTRiseSet($ra1, $dec1, $lon, $lat, $altitude);
  my ($transit2, $rise2, $set2) = GMSTRiseSet($ra2, $dec2, $lon, $lat, $altitude);
  
  #-- complex angle
  if( ($transit1 eq "---") || ($transit2 eq "---") ){
    return( ("---","---","---") );
  }
  
  #-- unwrap GMST in case we move across 24h -> 0h
  $transit2 += 24
    if ($transit1 > $transit2 && abs($transit1-$transit2)>18);
  $rise2 += 24
    if ($rise1 > $rise2    && abs($rise1-$rise2)>18);
  $set2 += 24
    if ($set1 > $set2    && abs($set1-$set2)>18);
    
  my $T0 = GMST($jd0UT);
  # my $T02 = T0-zone*1.002738; // Greenwich sidereal time at 0h time zone (zone: hours)
  #-- Greenwich sidereal time for 0h at selected longitude
  my $T02 = $T0-$lon*$RAD/15*1.002738;
  $T02 +=24 if ($T02 < 0);

  if ($transit1 < $T02) { 
    $transit1 += 24; 
    $transit2 += 24; 
  }
  if ($rise1    < $T02) { 
    $rise1    += 24; 
    $rise2    += 24; 
  }
  if ($set1     < $T02) { 
    $set1     += 24; 
    $set2     += 24; 
  }
  
  #-- Refraction and Parallax correction
  my $decMean = 0.5*($dec1+$dec2);
  my $psi = acos(sin($lat)/cos($decMean));
  my $y   = asin(sin($alt)/sin($psi));
  my $dt  = 240*$RAD*$y/cos($decMean)/3600; # time correction due to refraction, parallax

  my $transit = GMST2UT( $jd0UT, InterpolateGMST( $T0, $transit1, $transit2, $timeinterval) );
  my $rise    = GMST2UT( $jd0UT, InterpolateGMST( $T0, $rise1,    $rise2,    $timeinterval) - $dt );
  my $set     = GMST2UT( $jd0UT, InterpolateGMST( $T0, $set1,     $set2,     $timeinterval) + $dt );
  
  return( ($transit,$rise,$set) ); 
}

########################################################################################################
#
# SunRise - Find (local) time of sunrise and sunset, and twilights
#                 JD is the Julian Date of 0h local time (midnight)
#                 Accurate to about 1-2 minutes
#                 recursive: 1 - calculate rise/set in UTC in a second run
#                 recursive: 0 - find rise/set on the current local day. 
#                                This is set when doing the first call to this function
# 
########################################################################################################

sub SunRise($$$$$$$$){
  my ($JD, $deltaT, $lon, $lat, $zone, $horM, $horE, $recursive) = @_;
  
  my $jd0UT = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  
  #-- calculations for noon
  my $sunCoor1 = SunPosition($jd0UT+   $deltaT/24./3600.,undef,undef);

  #-- calculations for next day's UTC midnight
  my $sunCoor2 = SunPosition($jd0UT+1.+$deltaT/24./3600.,undef,undef); 
  
  #-- rise/set time in UTC
  my ($transit,$rise,$set) = RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
    $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1,undef); 
  if( $transit eq "---" ){
    Log 3,"[FHEM::Astro::SunRise] no solution possible - maybe the sun never sets ?";
   return( ($transit,$rise,$set) ); 
  }
  
  my ($transittemp,$risetemp,$settemp);
  #-- check and adjust to have rise/set time on local calendar day
  if ( $recursive==0 ) { 
    if ($zone>0) {
      #rise time was yesterday local time -> calculate rise time for next UTC day
      if ($rise >=24-$zone || $transit>=24-$zone || $set>=24-$zone) {
        ($transittemp,$risetemp,$settemp) = SunRise($JD+1, $deltaT, $lon, $lat, $zone, $horM, $horE, 1);
        $transit = $transittemp
          if ($transit>=24-$zone);
        $rise = $risetemp
          if ($rise>=24-$zone);
        $set = $settemp
          if ($set>=24-$zone);
      }
    }elsif ($zone<0) {
      #rise time was yesterday local time -> calculate rise time for previous UTC day
      if ($rise<-$zone || $transit<-zone || $set<-zone) {
        ($transittemp,$risetemp,$settemp) = SunRise($JD-1, $deltaT, $lon, $lat, $zone, $horM, $horE, 1);
      $transit = $transittemp
        if ($transit<-$zone);
      $rise = $risetemp
        if ($rise<-$zone);
      $set  = $settemp
        if ($set <-$zone);
      }
    }
	
    $transit = _mod($transit+$zone, 24.);
    $rise    = _mod($rise   +$zone, 24.);
    $set     = _mod($set    +$zone, 24.);

	#-- Twilight calculation
	#-- civil twilight time in UTC. 
	my $CivilTwilightMorning;
	my $CivilTwilightEvening;
	($transittemp,$risetemp,$settemp) = RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	   $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, -6.*$DEG);
	if( $transittemp eq "---" ){
      Log 4,"[FHEM::Astro::SunRise] no solution possible for civil twilight - maybe the sun never sets below -6 degrees?";
      $CivilTwilightMorning = "---";
      $CivilTwilightEvening = "---";
    }else{
	  $CivilTwilightMorning = _mod($risetemp +$zone, 24.);
	  $CivilTwilightEvening = _mod($settemp  +$zone, 24.);
    }
    
	#-- nautical twilight time in UTC.
	my $NauticTwilightMorning;
	my $NauticTwilightEvening; 
	($transittemp,$risetemp,$settemp) = RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	  $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, -12.*$DEG);
	if( $transittemp eq "---" ){
      Log 4,"[FHEM::Astro::SunRise] no solution possible for nautical twilight - maybe the sun never sets below -12 degrees?";
      $NauticTwilightMorning = "---";
      $NauticTwilightEvening = "---";
    }else{
      $NauticTwilightMorning = _mod($risetemp +$zone, 24.);
	  $NauticTwilightEvening = _mod($settemp  +$zone, 24.);
	}

	#-- astronomical twilight time in UTC. 
	my $AstroTwilightMorning;
	my $AstroTwilightEvening;
	($transittemp,$risetemp,$settemp) = RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	  $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, -18.*$DEG);
	if( $transittemp eq "---" ){
      Log 4,"[FHEM::Astro::SunRise] no solution possible for astronomical twilight - maybe the sun never sets below -18 degrees?";
      $AstroTwilightMorning = "---";
      $AstroTwilightEvening = "---";
    }else{
	  $AstroTwilightMorning = _mod($risetemp +$zone, 24.);
	  $AstroTwilightEvening = _mod($settemp  +$zone, 24.);
	}
	
	#-- custom twilight time in UTC
	my $CustomTwilightMorning;
	my $CustomTwilightEvening;
    ($transittemp,$risetemp,$settemp) = RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	  $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, $horM*$DEG);
	if( $transittemp eq "---" ){
      Log 4,"[FHEM::Astro::SunRise] no solution possible for custom morning twilight - maybe the sun never sets below ".$horM." degrees?";
      $CustomTwilightMorning = "---";
    }else{
	  $CustomTwilightMorning = _mod($risetemp +$zone, 24.);
	}
    ($transittemp,$risetemp,$settemp) = RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
    $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, $horE*$DEG);
  if( $transittemp eq "---" ){
      Log 4,"[FHEM::Astro::SunRise] no solution possible for custom evening twilight - maybe the sun never sets below ".$horE." degrees?";
      $CustomTwilightEvening = "---";
    }else{
    $CustomTwilightEvening = _mod($settemp  +$zone, 24.);
  }
	
	return( ($transit,$rise,$set,$CivilTwilightMorning,$CivilTwilightEvening,
	  $NauticTwilightMorning,$NauticTwilightEvening,$AstroTwilightMorning,$AstroTwilightEvening,$CustomTwilightMorning,$CustomTwilightEvening) );  
  }else{
    return( ($transit,$rise,$set) );  
  }
}

########################################################################################################
#
# MoonRise - Find local time of moonrise and moonset
# JD is the Julian Date of 0h local time (midnight)
# Accurate to about 5 minutes or better
# recursive: 1 - calculate rise/set in UTC
# recursive: 0 - find rise/set on the current local day (set could also be first)
# returns '' for moonrise/set does not occur on selected day
# 
########################################################################################################

sub MoonRise($$$$$$$){
  my ($JD, $deltaT, $lon, $lat, $radius, $zone, $recursive) = @_;
  my $timeinterval = 0.5;
  
  my $jd0UT = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  #-- calculations for noon
  my $sunCoor1  = SunPosition($jd0UT+ $deltaT/24./3600.,undef,undef);
  my $moonCoor1 = MoonPosition($sunCoor1->{lon}, $sunCoor1->{anomalyMean}, $jd0UT+ $deltaT/24./3600.,undef,undef,undef,undef);
 
  #-- calculations for next day's midnight
  my $sunCoor2  = SunPosition($jd0UT +$timeinterval + $deltaT/24./3600.,undef,undef); 
  my $moonCoor2 = MoonPosition($sunCoor2->{lon}, $sunCoor2->{anomalyMean}, $jd0UT +$timeinterval + $deltaT/24./3600.,undef,undef,undef,undef); 

  # rise/set time in UTC, time zone corrected later.
  # Taking into account refraction, semi-diameter and parallax
  my ($transit,$rise,$set) = RiseSet($jd0UT, $moonCoor1->{diameter}, $moonCoor1->{parallax}, 
    $moonCoor1->{ra}, $moonCoor1->{dec}, $moonCoor2->{ra}, $moonCoor2->{dec}, $lon, $lat, $timeinterval,undef); 
  my ($transittemp,$risetemp,$settemp);
  my ($transitprev,$riseprev,$setprev);
  
  # check and adjust to have rise/set time on local calendar day
  if ( $recursive==0 ) { 
    if ($zone>0) {
      # recursive call to MoonRise returns events in UTC
      ($transitprev,$riseprev,$setprev) = MoonRise($JD-1., $deltaT, $lon, $lat, $radius, $zone, 1);  
      if ($transit >= 24.-$zone || $transit < -$zone) { # transit time is tomorrow local time
        if ($transitprev < 24.-$zone){
           $transit = ""; # there is no moontransit today
        }else{
           $transit  = $transitprev;
        }
      }
      
      if ($rise >= 24.-$zone || $rise < -$zone) { # rise time is tomorrow local time
        if ($riseprev < 24.-$zone){
          $rise = ""; # there is no moonrise today
        }else{ 
          $rise  = $riseprev;
        }
      }

      if ($set >= 24.-$zone || $set < -$zone) { # set time is tomorrow local time
        if ($setprev < 24.-$zone){
          $set = ""; # there is no moonset today
        }else{
          $set  = $setprev;
        }
      }

    }elsif ($zone<0) { # rise/set time was tomorrow local time -> calculate rise time for previous UTC day
      if ($rise<-$zone || $set<-$zone || $transit<-$zone) { 
        ($transittemp,$risetemp,$settemp) = MoonRise($JD+1., $deltaT, $lon, $lat, $radius, $zone, 1);  
        if ($transit < -$zone){
          if ($transittemp > -$zone){
            $transit = ''; # there is no moontransit today
          }else{
            $transit  = $transittemp;
          }
        }
        
        if ($rise < -$zone) {
          if ($risetemp > -$zone){
             $rise = ''; # there is no moonrise today
          }else{
             $rise = $risetemp;
          }
        }
        
        if ($set < -$zone){
          if ($settemp > -$zone){
            $set = ''; # there is no moonset today
          }else{
            $set  = $settemp;
          }
        }     
      }
    }
    #-- correct for time zone, if time is valid
    $transit = _mod($transit +$zone, 24.)
      if( $transit ne ""); 
    $rise = _mod($rise +$zone, 24.)
      if ($rise ne "");    
    $set  = _mod($set +$zone, 24.)
      if ($set ne "");   
  }
  return( ($transit,$rise,$set) );
}

########################################################################################################
#
# Season - Find astronomical season
# 
########################################################################################################

sub Season($$;$) {
    my ( $JD0, $deltaT, $lat ) = @_;

    # season starts during the day so we need to
    #  look for tomorrows quarter at noon
    my $sunCoor = SunPosition( $JD0 + 1. + $deltaT / 86400.0, undef, undef );
    my $quarter = ceil( rad2deg( $sunCoor->{lon} ) / 90. ) % 4;

    return
      wantarray
      ? ( $quarter, $seasons{ $lat && $lat < 0 ? 'S' : 'N' }[$quarter] )
      : $quarter;
}

########################################################################################################
#
# SetTime - update of the %Date hash for today
# 
########################################################################################################

sub SetTime (;$$$) {
    my ( $time, $tz, $lc_time ) = @_;

    #-- readjust locale
    my $old_lctime = setlocale(LC_TIME);
    setlocale(LC_TIME, $lc_time) if ($lc_time);
    use locale ':not_characters';

    #-- readjust timezone
    local $ENV{TZ} = $tz if ($tz);
    tzset();

    $time = gettimeofday() unless ( defined($time) );

    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) =
      localtime($time);
    $year  += 1900;
    $month += 1;
    $Date{timestamp} = $time;
    $Date{timeday}   = $hour + $min / 60. + $sec / 3600.;
    $Date{year}      = $year;
    $Date{month}     = $month;
    $Date{day}       = $day;
    $Date{hour}      = $hour;
    $Date{min}       = $min;
    $Date{sec}       = $sec;
    $Date{isdst}     = $isdst;
    #-- broken on windows
    #$Date{zonedelta} = (strftime "%z", localtime($time))/100;
    $Date{zonedelta} = _tzoffset($time) / 100;
    #-- half broken in windows
    $Date{dayofyear} = 1 * strftime( "%j", localtime($time) );

    $Date{wdayl} = strftime( "%A", localtime($time) );
    $Date{wdays} = strftime( "%a", localtime($time) );
    $Date{monthl} = strftime( "%B", localtime($time) );
    $Date{months} = strftime( "%b", localtime($time) );
    $Date{datetime} = strftime( "%c", localtime($time) );
    $Date{week} = 1 * strftime( "%V", localtime($time) );
    $Date{wday} = 1 * strftime( "%w", localtime($time) );
    $Date{time} = strftime( "%X", localtime($time) );
    $Date{date} = strftime( "%x", localtime($time) );
    $Date{tz} = strftime( "%Z", localtime($time) );

    delete $Date{tz} if (!$Date{tz} || $Date{tz} eq "" || $Date{tz} eq " ");

    delete local $ENV{TZ};
    tzset();

    setlocale(LC_TIME, "");
    setlocale(LC_TIME, $old_lctime);
    no locale;

    return (undef);
}

########################################################################################################
#
# Compute - sequential calculation of properties
# 
########################################################################################################
  
sub Compute($;$){
  my ($hash,$params) = @_;
  undef %Astro;
  my $name = $hash->{NAME};
  SetTime() if (scalar keys %Date == 0); # fill %Date if it is still empty after restart to avoid warnings

  return undef if( !$init_done );

  #-- readjust language
  my $lang = uc(AttrVal($name,"language",AttrVal("global","language","EN")));
  if( defined($params->{"language"}) &&
      exists($transtable{uc($params->{"language"})})
  ){
    $tt = $transtable{uc($params->{"language"})};
  }elsif( exists($transtable{uc($lang)}) ){
    $tt = $transtable{uc($lang)};
  }else{
    $tt = $transtable{EN};
  }

  #-- readjust timezone
  my $tz = AttrVal($name,"timezone",AttrVal("global","timezone",undef));
  $tz = $params->{"timezone"}
    if ( defined( $params->{"timezone"} ) );
  local $ENV{TZ} = $tz if ($tz);
  tzset();

  #-- geodetic latitude and longitude of observer on WGS84  
  if( defined($params->{"latitude"}) ){
    $Astro{ObsLat}  = $params->{"latitude"};
  }elsif( defined($attr{$name}) && defined($attr{$name}{"latitude"}) ){
    $Astro{ObsLat}  = $attr{$name}{"latitude"};
  }elsif( defined($attr{"global"}{"latitude"}) ){
    $Astro{ObsLat}  = $attr{"global"}{"latitude"};
  }else{
    $Astro{ObsLat}  = 50.0;
    Log3 $name,3,"[Astro] No latitude attribute set in global device, using 50.0°";
  }
  if( defined($params->{"longitude"}) ){
    $Astro{ObsLon}  = $params->{"longitude"};
  }elsif( defined($attr{$name}) && defined($attr{$name}{"longitude"}) ){
    $Astro{ObsLon}  = $attr{$name}{"longitude"};
  }elsif( defined($attr{"global"}{"longitude"}) ){
    $Astro{ObsLon}  = $attr{"global"}{"longitude"};
  }else{
    $Astro{ObsLon}  = 10.0;
    Log3 $name,3,"[Astro] No longitude attribute set in global device, using 10.0°";
  } 
  #-- altitude of observer in meters above WGS84 ellipsoid 
  if( defined($params->{"altitude"}) ){
    $Astro{ObsAlt}  = $params->{"altitude"};
  }elsif( defined($attr{$name}) && defined($attr{$name}{"altitude"}) ){
    $Astro{ObsAlt}  = $attr{$name}{"altitude"};
  }elsif( defined($attr{"global"}{"altitude"}) ){
    $Astro{ObsAlt}  = $attr{"global"}{"altitude"};
  }else{
    $Astro{ObsAlt}  = 0.0;
    Log3 $name,3,"[Astro] No altitude attribute set in global device, using 0.0 m above sea level";
  }
  #-- custom horizon of observer in degrees
  if( defined($params->{"horizon"}) &&
      $params->{"horizon"} =~ m/^([^:]+)(?::(.+))?$/
  ){
    $Astro{ObsHorMorning} = $1;
    $Astro{ObsHorEvening} = defined($2) ? $2 : $1;
  }elsif( defined($attr{$name}) && defined($attr{$name}{"horizon"}) &&
      $attr{$name}{"horizon"} =~ m/^([^:]+)(?::(.+))?$/
  ){
    $Astro{ObsHorMorning} = $1;
    $Astro{ObsHorEvening} = defined($2) ? $2 : $1;
  } else {
    $Astro{ObsHorMorning} = 0.0;
    $Astro{ObsHorEvening} = 0.0;
    Log3 $name,5,"[Astro] No horizon attribute defined, using 0.0° for morning and evening";
  }

  #-- internal variables converted to Radians and km 
  my $lat      = $Astro{ObsLat}*$DEG;
  my $lon      = $Astro{ObsLon}*$DEG;
  my $height   = $Astro{ObsAlt} * 0.001;   

  #if (eval(form.Year.value)<=1900 || eval(form.Year.value)>=2100 ) {
  #  alert("Dies Script erlaubt nur Berechnungen"+
  #  return;
  #}

  my $JD0 = Date2JD( $Date{day}, $Date{month}, $Date{year} );
  my $JD  = $JD0 + ( $Date{hour} - $Date{zonedelta} + $Date{min}/60. + $Date{sec}/3600.)/24;
  my $TDT = $JD  + $deltaT/86400.0; 
  
  $Astro{".ObsJD"}  = $JD;
  $Astro{ObsJD}     = _round($JD,2);

  my $gmst          = GMST($JD);
  my $lmst          = GMST2LMST($gmst, $lon); 
  $Astro{".ObsGMST"}  = $gmst;
  $Astro{".ObsLMST"}  = $lmst;
  $Astro{ObsGMST}     = HHMMSS($gmst);
  $Astro{ObsLMST}     = HHMMSS($lmst);
  
  #-- geocentric cartesian coordinates of observer
  my ($x,$y,$z,$radius) = Observer2EquCart($lon, $lat, $height, $gmst); 
 
  #-- calculate data for the sun at given time
  my $sunCoor     = SunPosition($TDT, $lat, $lmst*15.*$DEG);   
  $Astro{SunLon}  = _round($sunCoor->{lon}*$RAD,1);
  #$Astro{SunLat}  = $sunCoor->{lat}*$RAD;
  $Astro{".SunRa"}= _round($sunCoor->{ra} *$RAD/15,1);
  $Astro{SunRa}   = HHMM($Astro{".SunRa"});
  $Astro{SunDec}  = _round($sunCoor->{dec}*$RAD,1);
  $Astro{SunAz}   = _round($sunCoor->{az} *$RAD,1);
  $Astro{SunAlt}  = _round($sunCoor->{alt}*$RAD + Refraction($sunCoor->{alt}),1);  # including refraction WARNUNG => *RAD ???
  $Astro{SunSign} = $tt->{$sunCoor->{sig}};
  $Astro{SunSignN}= $sunCoor->{sign};
  $Astro{SunDiameter}=_round($sunCoor->{diameter}*$RAD*60,1); #angular diameter in arc seconds
  $Astro{SunDistance}=_round($sunCoor->{distance},0);
  
  #-- calculate distance from the observer (on the surface of earth) to the center of the sun
  my ($xs,$ys,$zs) = EquPolar2Cart($sunCoor->{ra}, $sunCoor->{dec}, $sunCoor->{distance});
  $Astro{SunDistanceObserver} = _round(sqrt( ($xs-$x)**2 + ($ys-$y)**2 + ($zs-$z)**2 ),0);
  
  my ($suntransit,$sunrise,$sunset,$CivilTwilightMorning,$CivilTwilightEvening,
    $NauticTwilightMorning,$NauticTwilightEvening,$AstroTwilightMorning,$AstroTwilightEvening,$CustomTwilightMorning,$CustomTwilightEvening) = 
    SunRise($JD0, $deltaT, $lon, $lat, $Date{zonedelta}, $Astro{ObsHorMorning}, $Astro{ObsHorEvening}, 0);
  $Astro{".SunTransit"}            = $suntransit;
  $Astro{".SunRise"}               = $sunrise;
  $Astro{".SunSet"}                = $sunset;
  $Astro{".CivilTwilightMorning"}  = $CivilTwilightMorning;
  $Astro{".CivilTwilightEvening"}  = $CivilTwilightEvening;
  $Astro{".NauticTwilightMorning"} = $NauticTwilightMorning;
  $Astro{".NauticTwilightEvening"} = $NauticTwilightEvening;
  $Astro{".AstroTwilightMorning"}  = $AstroTwilightMorning;
  $Astro{".AstroTwilightEvening"}  = $AstroTwilightEvening;
  $Astro{".CustomTwilightMorning"} = $CustomTwilightMorning;
  $Astro{".CustomTwilightEvening"} = $CustomTwilightEvening;
  $Astro{SunTransit}              = HHMM($suntransit);
  $Astro{SunRise}                 = HHMM($sunrise);
  $Astro{SunSet}                  = HHMM($sunset);
  $Astro{CivilTwilightMorning}    = HHMM($CivilTwilightMorning);
  $Astro{CivilTwilightEvening}    = HHMM($CivilTwilightEvening);
  $Astro{NauticTwilightMorning}   = HHMM($NauticTwilightMorning);
  $Astro{NauticTwilightEvening}   = HHMM($NauticTwilightEvening);
  $Astro{AstroTwilightMorning}    = HHMM($AstroTwilightMorning);
  $Astro{AstroTwilightEvening}    = HHMM($AstroTwilightEvening);
  $Astro{CustomTwilightMorning}   = HHMM($CustomTwilightMorning);
  $Astro{CustomTwilightEvening}   = HHMM($CustomTwilightEvening);

  #-- hours of day and night
  my $hoursofsunlight;
  my $hoursofnight;
  if (
      (!defined($sunset) && !defined($sunrise)) ||
      ($sunset !~ m/^\d+/ && $sunrise !~ m/^\d+/)
  ){
    if ($Astro{SunAlt} > 0.) {
      $hoursofsunlight = 24.;
      $hoursofnight = 0.;
    } else {
      $hoursofsunlight = 0.;
      $hoursofnight = 24.;
    }
  }
  elsif (!defined($sunset) || $sunset !~ m/^\d+/) {
    $hoursofsunlight = 24. - $sunrise;
    $hoursofnight = 24. - $hoursofsunlight;
  }
  elsif (!defined($sunrise) || $sunrise !~ m/^\d+/) {
    $hoursofsunlight = 24. - $sunset;
    $hoursofnight = 24. - $hoursofsunlight;
  } else {
    my $ss = $sunset;
    $ss += 24.
      if ($sunrise > $sunset);
    $hoursofsunlight = $ss - $sunrise;
    $hoursofnight = 24. - $hoursofsunlight;
  }
  $Astro{".SunHrsVisible"}   = $hoursofsunlight;
  $Astro{".SunHrsInvisible"} = $hoursofnight;
  $Astro{SunHrsVisible}   = HHMM($hoursofsunlight);
  $Astro{SunHrsInvisible} = HHMM($hoursofnight);
  
  #-- calculate data for the moon at given time
  my $moonCoor  = MoonPosition($sunCoor->{lon}, $sunCoor->{anomalyMean}, $TDT, $lon, $lat, $radius, $lmst*15.*$DEG);
  $Astro{MoonLon} = _round($moonCoor->{lon}*$RAD,1);
  $Astro{MoonLat} = _round($moonCoor->{lat}*$RAD,1);
  $Astro{".MoonRa"} = _round($moonCoor->{ra} *$RAD/15.,1);
  $Astro{MoonRa}    = HHMM($Astro{".MoonRa"});
  $Astro{MoonDec} = _round($moonCoor->{dec}*$RAD,1);
  $Astro{MoonAz}  = _round($moonCoor->{az} *$RAD,1);
  $Astro{MoonAlt} = _round($moonCoor->{alt}*$RAD + Refraction($moonCoor->{alt}),1);  # including refraction WARNUNG => *RAD ???
  $Astro{MoonSign}     = $tt->{$moonCoor->{sig}};
  $Astro{MoonSignN}    = $moonCoor->{sign};
  $Astro{MoonDistance} = _round($moonCoor->{distance},0);
  $Astro{MoonDiameter} = _round($moonCoor->{diameter}*$RAD*60.,1); # angular diameter in arc seconds
  $Astro{MoonAge}      = _round($moonCoor->{age}*$RAD,1);
  $Astro{MoonPhaseN}   = _round($moonCoor->{phasen},2);
  $Astro{MoonPhaseI}   = $moonCoor->{phasei};
  $Astro{MoonPhaseS}   = $tt->{$moonCoor->{phases}};
  
  #-- calculate distance from the observer (on the surface of earth) to the center of the moon
  my ($xm,$ym,$zm) = EquPolar2Cart($moonCoor->{ra}, $moonCoor->{dec}, $moonCoor->{distance});
  #Log 1,"  distance=".$moonCoor->{distance}."   test=".sqrt( ($xm)**2 + ($ym)**2 + ($zm)**2 )." $xm  $ym  $zm";
  #Log 1,"  distance=".$radius."   test=".sqrt( ($x)**2 + ($y)**2 + ($z)**2 )." $x  $y  $z";
  $Astro{".MoonDistanceObserver"} = sqrt( ($xm-$x)**2 + ($ym-$y)**2 + ($zm-$z)**2 );
  $Astro{MoonDistanceObserver}    = _round($Astro{".MoonDistanceObserver"},0);
  
  my ($moontransit,$moonrise,$moonset) = MoonRise($JD0, $deltaT, $lon, $lat, $radius, $Date{zonedelta}, 0);
  $Astro{".MoonTransit"} = $moontransit;
  $Astro{".MoonRise"}    = $moonrise;
  $Astro{".MoonSet"}     = $moonset;
  $Astro{MoonTransit}    = HHMM($moontransit);
  $Astro{MoonRise}       = HHMM($moonrise);
  $Astro{MoonSet}        = HHMM($moonset);

  #-- moon visiblity
  my $moonvisible;
  my $mooninvisible;
  if (
      (!defined($moonset) && !defined($moonrise)) ||
      ($moonset !~ m/^\d+/ && $moonrise !~ m/^\d+/)
  ){
    if ($Astro{MoonAlt} >= 0.) {
      $moonvisible = 24.;
      $mooninvisible = 0.;
    } else {
      $moonvisible = 0.;
      $mooninvisible = 24.;
    }
  }
  elsif (!defined($moonset) || $moonset !~ m/^\d+/) {
    $moonvisible = 24. - $moonrise;
    $mooninvisible = 24. - $moonvisible;
  }
  elsif (!defined($moonrise) || $moonrise !~ m/^\d+/) {
    $moonvisible = 24. - $moonset;
    $mooninvisible = 24. - $moonvisible;
  } else {
    my $ss = $moonset;
    $ss += 24.
      if ($moonrise > $moonset);
    $moonvisible = $ss - $moonrise;
    $mooninvisible = 24. - $moonvisible;
  }
  $Astro{".MoonHrsVisible"}   = $moonvisible;
  $Astro{".MoonHrsInvisible"} = $mooninvisible;
  $Astro{MoonHrsVisible}   = HHMM($moonvisible);
  $Astro{MoonHrsInvisible} = HHMM($mooninvisible);

  #-- fix date
  $Astro{ObsDate}      = $Date{date};
  $Astro{ObsTime}      = $Date{time};
  $Astro{ObsTimezone}  = $Date{zonedelta};
  $Astro{ObsTimezoneS} = $Date{tz} if ( $Date{tz} );
  $Astro{ObsDayofyear} = $Date{dayofyear};
  $Astro{ObsIsDST}     = $Date{isdst};
  $Astro{".timestamp"} = $Date{timestamp};
  $Astro{".timeday"}   = $Date{timeday};
  $Astro{".year"}      = $Date{year};
  $Astro{".month"}     = $Date{month};
  $Astro{".day"}       = $Date{day};
  $Astro{".hour"}      = $Date{hour};
  $Astro{".min"}       = $Date{min};
  $Astro{".sec"}       = $Date{sec};
  $Astro{".wdayl"}     = $Date{wdayl};
  $Astro{".wdays"}     = $Date{wdays};
  $Astro{".monthl"}    = $Date{monthl};
  $Astro{".months"}    = $Date{months};
  $Astro{".datetime"}  = $Date{datetime};
  $Astro{".week"}      = $Date{week};
  $Astro{".wday"}      = $Date{wday};

  #-- check astro season
  my ($seasonn, $season) = Season($JD0, $deltaT, $Astro{ObsLat});
  $Astro{ObsSeason}  = $tt->{$season};
  $Astro{ObsSeasonN} = $seasonn;

  delete local $ENV{TZ};
  tzset();

  return( undef );
};

########################################################################################################
#
# Moonwidget - SVG picture of the moon 
#
#  Parameter arg = argument array
#
########################################################################################################

sub Moonwidget($){
  my ($arg) = @_;
  my $name = $FW_webArgs{name};
  $name    =~ s/'//g if ($name);
  my $hash = $name && $name ne "" && defined($defs{$name}) ? $defs{$name} : ();
  
  my $mooncolor = 'rgb(255,220,100)';
  my $moonshadow = 'rgb(70,70,100)';

  $mooncolor = $FW_webArgs{mooncolor} 
    if ($FW_webArgs{mooncolor} );
  $moonshadow = $FW_webArgs{moonshadow}
    if ($FW_webArgs{moonshadow} );
    
  my @size = split('x', ($FW_webArgs{size} ? $FW_webArgs{size}  : '400x400'));
  
  $FW_RETTYPE = "image/svg+xml";
  $FW_RET="";
  FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" width="'.$size[0].'px" height="'.$size[1].'px">';
  my $ma = Get($hash,("","text","MoonAge"));
  my $mb = Get($hash,("","text","MoonPhaseS"));

  my ($radius,$axis,$dir,$start,$middle);
  $radius = 250;
  $axis   = sin(($ma+90)*$DEG)*$radius;
  $axis   = -$axis
    if ($axis < 0);
    
  if( (0.0 <= $ma && $ma <= 90) || (270.0 < $ma && $ma <= 360.0) ){
    $dir = 1;
  }else{
    $dir = 0;
  }
  if( 0.0 < $ma && $ma <= 180 ){
    $start  = $radius;
    $middle = -$radius;
  }else{
    $start  = -$radius;
    $middle = $radius;
  }
 
  FW_pO '<g transform="translate(400,400) scale(-1,1)">';
  FW_pO '<circle cx="0" cy="0" r="250" fill="'.$moonshadow.'"/>';
  FW_pO '<path d="M 0 '.$start.' A '.$axis.' '.$radius.' 0 0 '.$dir.' 0 '.$middle.' A '.$radius.' '.$radius.' 0 0 0 0 '.$start.' Z" fill="'.$mooncolor.'"/>'; 
  FW_pO '</g>';
  #FW_pO '<text x="100" y="710" style="font-family:Helvetica;font-size:60px;font-weight:bold" fill="black">'.$mb.'</text>';
  FW_pO '</svg>';
  return ($FW_RETTYPE, $FW_RET); 
}	         

########################################################################################################
#
# Update - Update readings 
#
#  Parameter hash = hash of the bus master
#
########################################################################################################

sub Update($@) {
  my ($hash) = @_;
  
  my $name     = $hash->{NAME};
  RemoveInternalTimer($hash);
  delete $hash->{NEXTUPDATE};

  return undef if (IsDisabled($name));

  my $tz = AttrVal( $name, "timezone", AttrVal( "global", "timezone", undef ) );
  my $lang = AttrVal( $name, "language", AttrVal( "global", "language", undef ) );
  my $lc_time = AttrVal(
      $name,
      "lc_time",
      AttrVal(
          "global", "lc_time",
          ( $lang ? lc($lang) . "_" . uc($lang) . ".UTF-8" : undef )
      )
  );
  my $now = gettimeofday();    # conserve timestamp before recomputing

  SetTime(undef, $tz, $lc_time);
  Compute($hash);

  my @next;

  #-- add regular update interval time
  push @next, $now + $hash->{INTERVAL}
    if ( defined( $hash->{INTERVAL} ) && $hash->{INTERVAL} > 0 );

  #-- add event times
  foreach my $comp (
      defined( $hash->{RECOMPUTEAT} ) ? split( ',', $hash->{RECOMPUTEAT} ) : () )
  {
    if ( $comp eq 'NewDay' ) {
        push @next,
          timelocal( 0, 0, 0, ( localtime( $now + 86400. ) )[ 3, 4, 5 ] );
        next;
    }
    my $k = ".$comp";
    next unless ( defined( $Astro{$k} ) && $Astro{$k} =~ /^\d+(?:\.\d+)?$/ );
    my $t =
      timelocal( 0, 0, 0, ( localtime($now) )[ 3, 4, 5 ] ) + $Astro{$k} * 3600.;
    $t += 86400. if ( $t < $now );    # that is for tomorrow
    push @next, $t;
  }

  #-- set timer for next update
  if (@next) {
    my $n = minNum( $next[0], @next );
    $hash->{NEXTUPDATE} = FmtDateTime($n);
    InternalTimer( $n, "FHEM::Astro::Update", $hash, 1 );
  }

  readingsBeginUpdate($hash);
  foreach my $key (keys %Astro){
    readingsBulkUpdateIfChanged($hash,$key,encode_utf8($Astro{$key}));
  }
  readingsEndUpdate($hash,1); 
  readingsSingleUpdate($hash,"state","Updated",1);
}

########################################################################################################
#
# FormatReading - Convert a reading into text format
#
#  Parameter r = reading name, h = parameter hash, locale = locale string, val = optional value
#
########################################################################################################

sub FormatReading($$;$$) {
  my ( $r, $h, $lc_numeric, $val ) = @_;
  my $ret;
  $val = $Astro{$r} unless ( defined($val) );

  my $f = "%s";

  #-- number formatting
  $f = "%2.1f" if ( $r eq "MoonAge" );
  $f = "%2.1f" if ( $r eq "MoonAlt" );
  $f = "%2.1f" if ( $r eq "MoonAz" );
  $f = "%2.1f" if ( $r eq "MoonDec" );
  $f = "%2.1f" if ( $r eq "MoonDiameter" );
  $f = "%.0f"  if ( $r eq "MoonDistance" );
  $f = "%.0f"  if ( $r eq "MoonDistanceObserver" );
  $f = "%2.1f" if ( $r eq "MoonLat" );
  $f = "%2.1f" if ( $r eq "MoonLon" );
  $f = "%1.2f" if ( $r eq "MoonPhaseN" );
  $f = "%.0f"  if ( $r eq "ObsAlt" );
  $f = "%d"    if ( $r eq "ObsDayofyear" );
  $f = "%2.1f" if ( $r eq "ObsHorEvening" );
  $f = "%2.1f" if ( $r eq "ObsHorMorning" );
  $f = "%.2f"  if ( $r eq "ObsJD" );
  $f = "%.5f"  if ( $r eq "ObsLat" );
  $f = "%.5f"  if ( $r eq "ObsLon" );
  $f = "%2d"   if ( $r eq "ObsTimezone" );
  $f = "%2.1f" if ( $r eq "SunAlt" );
  $f = "%2.1f" if ( $r eq "SunAz" );
  $f = "%2.1f" if ( $r eq "SunDec" );
  $f = "%2.1f" if ( $r eq "SunDiameter" );
  $f = "%.0f"  if ( $r eq "SunDistance" );
  $f = "%.0f"  if ( $r eq "SunDistanceObserver" );
  $f = "%2.1f" if ( $r eq "SunLon" );

  $ret = $val ne "" ? sprintf( $f, $val ) : "";
  $ret = UConv::decimal_mark( $ret, $lc_numeric )
    unless ( $h && ref($h) && defined( $h->{html} ) && $h->{html} eq "0" );

  $ret = ( $val == 1. ? $tt->{"dst"} : $tt->{"nt"} )
    if ( $r eq "ObsIsDST" );

  if ( $h && ref($h) && ( !$h->{html} || $h->{html} ne "0" ) ) {

    #-- add unit if desired
    if ( $h->{unit}
        || ( $h->{long} && ( !defined( $h->{unit} ) || $h->{unit} ne "0" ) ) )
    {
      $ret .= "°"                         if ( $r eq "MoonAge" );
      $ret .= "°"                         if ( $r eq "MoonAlt" );
      $ret .= "°"                         if ( $r eq "MoonAz" );
      $ret .= "°"                         if ( $r eq "MoonDec" );
      $ret .= "′"                         if ( $r eq "MoonDiameter" );
      $ret .= chr(0x00A0) . "km"          if ( $r eq "MoonDistance" );
      $ret .= chr(0x00A0) . "km"          if ( $r eq "MoonDistanceObserver" );
      $ret .= chr(0x00A0) . "h"           if ( $r eq "MoonHrsInvisible" );
      $ret .= chr(0x00A0) . "h"           if ( $r eq "MoonHrsVisible" );
      $ret .= "°"                         if ( $r eq "MoonLat" );
      $ret .= "°"                         if ( $r eq "MoonLon" );
      $ret .= chr(0x00A0) . "h"           if ( $r eq "MoonRa" );
      $ret .= chr(0x00A0) . "m"           if ( $r eq "ObsAlt" );
      $ret .= "."                         if ( $r eq "ObsDayofyear" );
      $ret .= "°"                         if ( $r eq "ObsHorEvening" );
      $ret .= "°"                         if ( $r eq "ObsHorMorning" );
      $ret .= chr(0x00A0) . $tt->{"days"} if ( $r eq "ObsJD" );
      $ret .= "°"                         if ( $r eq "ObsLat" );
      $ret .= "°"                         if ( $r eq "ObsLon" );
      $ret .= "°"                         if ( $r eq "SunAlt" );
      $ret .= "°"                         if ( $r eq "SunAz" );
      $ret .= "°"                         if ( $r eq "SunDec" );
      $ret .= "′"                         if ( $r eq "SunDiameter" );
      $ret .= chr(0x00A0) . "km"          if ( $r eq "SunDistance" );
      $ret .= chr(0x00A0) . "km"          if ( $r eq "SunDistanceObserver" );
      $ret .= chr(0x00A0) . "h"           if ( $r eq "SunHrsInvisible" );
      $ret .= chr(0x00A0) . "h"           if ( $r eq "SunHrsVisible" );
      $ret .= "°"                         if ( $r eq "SunLon" );
      $ret .= chr(0x00A0) . "h"           if ( $r eq "SunRa" );
    }

    #-- add text if desired
    if ( $h->{long} ) {
      my $sep = " ";
      $sep = ": "
        if ( $h->{long} > 1. && ( $h->{long} < 4. || $r !~ /^Sun|Moon/ ) );
      $sep = "" if ($ret eq "");

      $ret = $tt->{"twilightastro"} . $sep . $ret
        if ( $r eq "AstroTwilightEvening" );
      $ret = $tt->{"twilightastro"} . $sep . $ret
        if ( $r eq "AstroTwilightMorning" );
      $ret = $tt->{"twilightcivil"} . $sep . $ret
        if ( $r eq "CivilTwilightEvening" );
      $ret = $tt->{"twilightcivil"} . $sep . $ret
        if ( $r eq "CivilTwilightMorning" );
      $ret = $tt->{"twilightcustom"} . $sep . $ret
        if ( $r eq "CustomTwilightEvening" );
      $ret = $tt->{"twilightcustom"} . $sep . $ret
        if ( $r eq "CustomTwilightMorning" );
      $ret = $tt->{"age"} . $sep . $ret      if ( $r eq "MoonAge" );
      $ret = $tt->{"alt"} . $sep . $ret      if ( $r eq "MoonAlt" );
      $ret = $tt->{"az"} . $sep . $ret       if ( $r eq "MoonAz" );
      $ret = $tt->{"dec"} . $sep . $ret      if ( $r eq "MoonDec" );
      $ret = $tt->{"diameter"} . $sep . $ret if ( $r eq "MoonDiameter" );
      $ret = $ret . $sep . $tt->{"toce"}
        if ( $r eq "MoonDistance" );
      $ret = $ret . $sep . $tt->{"toobs"}
        if ( $r eq "MoonDistanceObserver" );
      $ret = $tt->{"hoursofvisibility"} . $sep . $ret
        if ( $r eq "MoonHrsVisible" );
      $ret = $tt->{"latecl"} . $sep . $ret  if ( $r eq "MoonLat" );
      $ret = $tt->{"lonecl"} . $sep . $ret  if ( $r eq "MoonLon" );
      $ret = $tt->{"phase"} . $sep . $ret   if ( $r eq "MoonPhaseN" );
      $ret = $tt->{"phase"} . $sep . $ret   if ( $r eq "MoonPhaseS" );
      $ret = $tt->{"ra"} . $sep . $ret      if ( $r eq "MoonRa" );
      $ret = $tt->{"rise"} . $sep . $ret    if ( $r eq "MoonRise" );
      $ret = $tt->{"set"} . $sep . $ret     if ( $r eq "MoonSet" );
      $ret = $tt->{"sign"} . $sep . $ret    if ( $r eq "MoonSign" );
      $ret = $tt->{"transit"} . $sep . $ret if ( $r eq "MoonTransit" );
      $ret = $tt->{"twilightnautic"} . $sep . $ret
        if ( $r eq "NauticTwilightEvening" );
      $ret = $tt->{"twilightnautic"} . $sep . $ret
        if ( $r eq "NauticTwilightMorning" );
      $ret = $ret . $sep . $tt->{"altitude"}  if ( $r eq "ObsAlt" );
      $ret = $tt->{"date"} . $sep . $ret      if ( $r eq "ObsDate" );
      $ret = $ret . $sep . $tt->{"dayofyear"} if ( $r eq "ObsDayofyear" );
      $ret = $tt->{"alt"} . $sep . $ret       if ( $r eq "ObsHorEvening" );
      $ret = $tt->{"alt"} . $sep . $ret       if ( $r eq "ObsHorMorning" );
      $ret = ( $val == 1. ? $tt->{"switchtodst"} : $tt->{"switchtont"} )
        if ( $r eq "ObsIsDST" );
      $ret = $tt->{"jdate"} . $sep . $ret     if ( $r eq "ObsJD" );
      $ret = $tt->{"lmst"} . $sep . $ret      if ( $r eq "ObsLMST" );
      $ret = $ret . $sep . $tt->{"latitude"}  if ( $r eq "ObsLat" );
      $ret = $ret . $sep . $tt->{"longitude"} if ( $r eq "ObsLon" );
      $ret = $tt->{"season"} . $sep . $ret    if ( $r eq "ObsSeason" );
      $ret = $tt->{"time"} . $sep . $ret      if ( $r eq "ObsTime" );
      $ret = $tt->{"timezone"} . $sep . $ret  if ( $r eq "ObsTimezone" );
      $ret = $tt->{"alt"} . $sep . $ret       if ( $r eq "SunAlt" );
      $ret = $tt->{"az"} . $sep . $ret        if ( $r eq "SunAz" );
      $ret = $tt->{"dec"} . $sep . $ret       if ( $r eq "SunDec" );
      $ret = $tt->{"diameter"} . $sep . $ret  if ( $r eq "SunDiameter" );
      $ret = $ret . $sep . $tt->{"toce"}
        if ( $r eq "SunDistance" );
      $ret = $ret . $sep . $tt->{"toobs"}
        if ( $r eq "SunDistanceObserver" );
      $ret = $tt->{"hoursofnight"} . $sep . $ret
        if ( $r eq "SunHrsInvisible" );
      $ret = $tt->{"hoursofsunlight"} . $sep . $ret
        if ( $r eq "SunHrsVisible" );
      $ret = $tt->{"lonecl"} . $sep . $ret  if ( $r eq "SunLon" );
      $ret = $tt->{"ra"} . $sep . $ret      if ( $r eq "SunRa" );
      $ret = $tt->{"rise"} . $sep . $ret    if ( $r eq "SunRise" );
      $ret = $tt->{"set"} . $sep . $ret     if ( $r eq "SunSet" );
      $ret = $tt->{"sign"} . $sep . $ret    if ( $r eq "SunSign" );
      $ret = $tt->{"transit"} . $sep . $ret if ( $r eq "SunTransit" );

      #-- add prefix for Sun/Moon if desired
      if ( $h->{long} > 2. && $r =~ /^Sun|Moon/ ) {
        $ret = " " . $ret;

        #-- add a separator after prefix if desired
        $ret = ":" . $ret if ( $h->{long} > 3. );

        $ret = $tt->{"sun"} . $ret
          if ( $r =~ /^Sun/ );
        $ret = $tt->{"moon"} . $ret
          if ( $r =~ /^Moon/ );
      }
    }
  }

  return encode_utf8($ret);
}

########################################################################################################
#
# Set - Implements SetFn function 
#
#  Parameter hash = hash of device addressed, a = array of arguments, h = hash of parameters
#
########################################################################################################

sub Set($@) {
  my ($hash,$a,$h) = @_;

  my $name = shift @$a;

  if ( $a->[0] eq "update" ) {
    return "[FHEM::Astro::Set] $name is disabled" if ( IsDisabled($name) );
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 1, "FHEM::Astro::Update", $hash, 1 );
  }
  else {
    return
      "[FHEM::Astro::Set] $name with unknown argument $a->[0], choose one of "
      . join( " ",
        map { defined( $sets{$_} ) ? "$_:$sets{$_}" : $_ }
        sort keys %sets );
  }

  return "";
}

########################################################################################################
#
# Get - Implements GetFn function 
#
#  Parameter hash = hash of the bus master a = argument array
#
########################################################################################################

sub Get($@) {
  my ($hash,$a,$h,@a) = @_;
  my $name = "#APIcall";
  my $type = "dummy";

  #-- backwards compatibility for non-parseParams requests
  if (!ref($a)) {
    $hash = exists($defs{$hash}) ? $defs{$hash} : ()
      if ($hash && !ref($hash));
    unshift @a, $h;
    $h = undef;
    $type = $a;
    $a = \@a;
  }
  else {
    $type = shift @$a;
  }
  if (defined($hash->{NAME})) {
    $name = $hash->{NAME};
  } else {
    $hash->{NAME} = $name;
  }

  my $wantsreading = 0;
  my $dayOffset = 0;
  my $html = defined( $hash->{CL} ) && $hash->{CL}{TYPE} eq "FHEMWEB" ? 1 : undef;
  my $tz = AttrVal( $name, "timezone", AttrVal( "global", "timezone", undef ) );
  my $lang = AttrVal( $name, "language", AttrVal( "global", "language", undef ) );
  my $lc_numeric = AttrVal(
      $name,
      "lc_numeric",
      AttrVal(
          "global", "lc_numeric",
          ( $lang ? lc($lang) . "_" . uc($lang) . ".UTF-8" : undef )
      )
  );
  my $lc_time = AttrVal(
      $name,
      "lc_time",
      AttrVal(
          "global", "lc_time",
          ( $lang ? lc($lang) . "_" . uc($lang) . ".UTF-8" : undef )
      )
  );
  if ( $h && ref($h) ) {
    $html       = $h->{html}       if ( defined( $h->{html} ) );
    $tz         = $h->{timezone}   if ( defined( $h->{timezone} ) );
    $lc_numeric = $h->{lc_numeric} if ( defined( $h->{lc_numeric} ) );
    $lc_numeric = lc( $h->{language} ) . "_" . uc( $h->{language} ) . ".UTF-8"
      if ( !$lc_numeric && defined( $h->{language} ) );
    $lc_time = $h->{lc_time} if ( defined( $h->{lc_time} ) );
    $lc_time = lc( $h->{language} ) . "_" . uc( $h->{language} ) . ".UTF-8"
      if ( !$lc_time && defined( $h->{language} ) );
  }

  #-- fill %Astro if it is still empty after restart to avoid warnings
  Compute($hash, $h) if (scalar keys %Astro == 0);

  #-- second parameter may be one or many readings
  my @readings;
  if( (int(@$a)>1) ) {
    @readings = split(',', $a->[1]);
    foreach (@readings) {
      if(exists($Astro{$_})) {
        $wantsreading = 1;
        last;
      }
    }
  }

  #-- last parameter may be indicating day offset
  if(
    (int(@$a)>4+$wantsreading && $a->[4+$wantsreading] =~ /^\+?([-+]\d+|yesterday|tomorrow)$/i) ||
    (int(@$a)>3+$wantsreading && $a->[3+$wantsreading] =~ /^\+?([-+]\d+|yesterday|tomorrow)$/i) ||
    (int(@$a)>2+$wantsreading && $a->[2+$wantsreading] =~ /^\+?([-+]\d+|yesterday|tomorrow)$/i) ||
    (int(@$a)>1+$wantsreading && $a->[1+$wantsreading] =~ /^\+?([-+]\d+|yesterday|tomorrow)$/i)
  ){
    $dayOffset = $1;
    pop @$a;
    $dayOffset = -1 if (lc($dayOffset) eq "yesterday");
    $dayOffset = 1  if (lc($dayOffset) eq "tomorrow");
  }

  if( int(@$a) > (1+$wantsreading) ) {
    my $str = (int(@$a) == (3+$wantsreading)) ? $a->[1+$wantsreading]." ".$a->[2+$wantsreading] : $a->[1+$wantsreading];
    if( $str =~ /^(\d{2}):(\d{2})(?::(\d{2}))?|(?:(\d{4})-(\d{2})-(\d{2}))(?:\D+(\d{2}):(\d{2})(?::(\d{2}))?)?$/){
      SetTime(
          timelocal(
              defined($3) ? $3 : (defined($9) ? $9 : 0),
              defined($2) ? $2 : (defined($8) ? $8 : 0),
              defined($1) ? $1 : (defined($7) ? $7 : 12),
              (defined($4)? ($6,$5-1,$4) : (localtime(gettimeofday()))[3,4,5])
          ) + ( $dayOffset * 86400. ), $tz, $lc_time
        )
    }else{
      return "[FHEM::Astro::Get] $name has improper time specification $str, use YYYY-MM-DD [HH:MM:SS] [-1|yesterday|+1|tomorrow]";
    }
  }else{
    SetTime(gettimeofday() + ($dayOffset * 86400.), $tz, $lc_time);
  }

  #-- disable automatic links to FHEM devices
  delete $FW_webArgs{addLinks};

  if( $a->[0] eq "version") {
    return version->parse(FHEM::Astro::->VERSION())->normal;
    
  }elsif( $a->[0] eq "json") {
    Compute($hash, $h);

    #-- beautify JSON at cost of performance only when debugging
    if (ref($json) && AttrVal($name,"verbose",AttrVal("global","verbose",3)) > 3.) {
      $json->canonical;
      $json->pretty;
    }

    if( $wantsreading==1 ){
      my %ret;
      foreach (@readings) {
        next unless(exists($Astro{$_}) && !ref($Astro{$_}));
        if ($h && ref($h) && ($h->{text} || $h->{unit} || $h->{long})) {
          $ret{text}{$_} = FormatReading($_, $h, $lc_numeric);
        }
        $ret{$_} = $Astro{$_};
      }
      return $json->encode(\%ret) if (ref($json));
      return toJSON(\%ret);
    }else{
      if ($h && ref($h) && ($h->{text} || $h->{unit} || $h->{long})) {
        foreach (keys %Astro) {
          next if (ref($Astro{$_}) || $_ =~ /^\./);
          $Astro{text}{$_} = FormatReading($_, $h, $lc_numeric);
        }
      }
      return $json->encode(\%Astro) if (ref($json));
      return toJSON(\%Astro);
    }

  }elsif( $a->[0] eq "text") {
    Compute($hash, $h);
    my $ret = "";

    if ( $wantsreading==1 && $h && ref($h) && scalar keys %{$h} > 0 ) {
      foreach (@readings) {
        next if (!defined($Astro{$_}) || ref($Astro{$_}));
        $ret .= $html && $html eq "1" ? "<br/>\n" : "\n"
          if ( $ret ne "" );
        $ret .= FormatReading( $_, $h, $lc_numeric ) unless($_ =~ /^\./);
        $ret .= encode_utf8($Astro{$_}) if ($_ =~ /^\./);
      }
      $ret = "<html>" . $ret . "</html>" if (defined($html) && $html ne "0");
    }
    elsif ( $wantsreading==1 ) {
      foreach (@readings) {
        next if (!defined($Astro{$_}) || ref($Astro{$_}));
        $ret .= $html && $html eq "1" ? "<br/>\n" : "\n"
          if ( $ret ne "" );
        $ret .= encode_utf8($Astro{$_});
      }
      $ret = "<html>" . $ret . "</html>" if (defined($html) && $html ne "0");
    }
    else {
      $h->{long} = 1 unless ( defined( $h->{long} ) );

      $ret = FormatReading( "ObsDate", $h, $lc_numeric ) . " " . $Astro{ObsTime};
      $ret .= (
        ( $Astro{ObsIsDST} == 1 )
        ? " (" . FormatReading( "ObsIsDST", undef ) . ")"
        : ""
      );
      $ret .= ", " . FormatReading( "ObsTimezone", $h ) . "\n";
      $ret .= FormatReading( "ObsJD", $h, $lc_numeric ) . ", "
        . FormatReading( "ObsDayofyear", $h, $lc_numeric ) . "\n";
      $ret .= FormatReading( "ObsSeason", $h ) . "\n";
      $ret .=
          $tt->{"coord"} . ":  "
        . FormatReading( "ObsLon", $h, $lc_numeric ) . ", "
        . FormatReading( "ObsLat", $h, $lc_numeric ) . ", "
        . FormatReading( "ObsAlt", $h, $lc_numeric ) . "\n";
      $ret .= FormatReading( "ObsLMST", $h ) . "\n\n";

      $ret .= "\n" . $tt->{"sun"} . "\n";
      $ret .=
          FormatReading( "SunRise", $h ) . "   "
        . FormatReading( "SunSet",     $h ) . "   "
        . FormatReading( "SunTransit", $h ) . "\n";
      $ret .= FormatReading( "SunHrsVisible", $h ) . "   "
        . FormatReading( "SunHrsInvisible", $h ) . "\n";
      $ret .= FormatReading( "CivilTwilightMorning", $h ) . "  -  "
        . $Astro{CivilTwilightEvening} . "\n";
      $ret .= FormatReading( "NauticTwilightMorning", $h ) . "  -  "
        . $Astro{NauticTwilightEvening} . "\n";
      $ret .= FormatReading( "AstroTwilightMorning", $h ) . "  -  "
        . $Astro{AstroTwilightEvening} . "\n";
      $ret .=
          $tt->{"distance"} . ":  "
        . FormatReading( "SunDistance",         $h, $lc_numeric ) . " ("
        . FormatReading( "SunDistanceObserver", $h, $lc_numeric ) . ")\n";
      $ret .=
          $tt->{"position"} . ":  "
        . FormatReading( "SunLon", $h, $lc_numeric ) . ", "
        . FormatReading( "SunRa",  $h, $lc_numeric ) . ", "
        . FormatReading( "SunDec", $h, $lc_numeric ) . "; "
        . FormatReading( "SunAz",  $h, $lc_numeric ) . ", "
        . FormatReading( "SunAlt", $h, $lc_numeric ) . "\n";
      $ret .= FormatReading( "SunDiameter", $h, $lc_numeric ) . ", "
        . FormatReading( "SunSign", $h ) . "\n\n";

      $ret .= "\n" . $tt->{"moon"} . "\n";
      $ret .=
          FormatReading( "MoonRise", $h ) . "   "
        . FormatReading( "MoonSet",     $h ) . "   "
        . FormatReading( "MoonTransit", $h ) . "\n";
      $ret .= FormatReading( "MoonHrsVisible", $h ) . "\n";
      $ret .=
          $tt->{"distance"} . ":  "
        . FormatReading( "MoonDistance",         $h, $lc_numeric ) . " ("
        . FormatReading( "MoonDistanceObserver", $h, $lc_numeric ) . ")\n";
      $ret .=
          $tt->{"position"} . ":  "
        . FormatReading( "MoonLon", $h, $lc_numeric ) . ", "
        . FormatReading( "MoonLat", $h, $lc_numeric ) . "; "
        . FormatReading( "MoonRa",  $h, $lc_numeric ) . ", "
        . FormatReading( "MoonDec", $h, $lc_numeric ) . ", "
        . FormatReading( "MoonAz",  $h, $lc_numeric ) . ", "
        . FormatReading( "MoonAlt", $h, $lc_numeric ) . "\n";
      $ret .=
          FormatReading( "MoonDiameter", $h, $lc_numeric ) . ", "
        . FormatReading( "MoonAge",    $h, $lc_numeric ) . ", "
        . FormatReading( "MoonPhaseN", $h, $lc_numeric ) . " = "
        . $Astro{MoonPhaseS} . ", "
        . FormatReading( "MoonSign", $h );

        if ($html && $html eq "1") {
          $ret = "<html>" . $ret . "</html>";
          $ret =~ s/   /&nbsp;&nbsp;&nbsp;/g;
          $ret =~ s/  /&nbsp;&nbsp;/g;
          $ret =~ s/\n/<br\/>\n/g;
        }
    }

    return $ret;
  }else {
    return "[FHEM::Astro::Get] $name with unknown argument $a->[0], choose one of ". 
    join(" ", map { defined($gets{$_})?"$_:$gets{$_}":$_ } sort keys %gets);
  }
}

1;

=pod
=encoding utf8
=item helper
=item summary collection of various routines for astronomical data
=item summary_DE Sammlung verschiedener Routinen für astronomische Daten
=begin html

   <a name="Astro"></a>
        <h3>Astro</h3>
        <ul>
        <p> FHEM module with a collection of various routines for astronomical data</p>
        <a name="Astrodefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; Astro</code>
            <br />Defines the Astro device (only one is needed per FHEM installation). </p>
        <p>
        Readings with prefix <i>Sun</i> refer to the sun, with prefix <i>Moon</i> refer to the moon.
        The suffixes for these readings are:
        <ul>
        <li><i>Age</i> = angle (in degrees) of body along its track</li>
        <li><i>Az,Alt</i> = azimuth and altitude angle (in degrees) of body above horizon</li>
        <li><i>Dec,Ra</i> = declination (in degrees) and right ascension (in HH:MM) of body position</li>
        <li><i>HrsVisible,HrsInvisible</i> = Hours of visiblity and invisiblity of the body</li>
        <li><i>Lat,Lon</i> = latitude and longituds (in degrees) of body position</li>
        <li><i>Diameter</i> = virtual diameter (in arc minutes) of body</li>
        <li><i>Distance,DistanceObserver</i> = distance (in km) of body to center of earth or to observer</li>
        <li><i>PhaseN,PhaseS</i> = Numerical and string value for phase of body</li>
	    <li><i>Sign,SignN</i> = Circadian sign for body along its track</li>
	    <li><i>Rise,Transit,Set</i> = times (in HH:MM) for rise and set as well as for highest position of body</li>
        </ul>
        <p>
        Readings with prefix <i>Obs</i> refer to the observer.
        In addition to some of the suffixes gives above, the following may occur:
        <ul>
        <li><i>Date,Dayofyear</i> = date</li>
        <li><i>JD</i> = Julian date</li>
        <li><i>Time,Timezone,TimezoneS</i> = obvious meaning</li>
        <li><i>IsDST</i> = 1 if running on daylight savings time, 0 otherwise</li>
        <li><i>GMST,LMST</i> = Greenwich and Local Mean Sidereal Time (in HH:MM)</li>
	    </ul>
	    <p>
	    An SVG image of the current moon phase may be obtained under the link 
	    <code>&lt;ip address of fhem&gt;/fhem/Astro_moonwidget?name='&lt;device name&gt;'</code>.
	    Optional web parameters are <code>[&amp;size='&lt;width&gt;x&lt;height&gt;'][&amp;mooncolor=&lt;color&gt;][&amp;moonshadow=&lt;color&gt;]</code>
	    <p>
        Notes: <ul>
        <li>Calculations are only valid between the years 1900 and 2100</li>
        <li>Attention: Timezone is taken from the local Perl settings, NOT automatically defined for a location</li>
        <li>This module uses the global attribute <code>language</code> to determine its output data<br/>
         (default: EN=english). For German output, set <code>attr global language DE</code>.<br/>
         If a local attribute on the device was set for language it will take precedence.</li>
        <li>The time zone is determined automatically from the local settings of the <br/>
        operating system. If geocordinates from a different time zone are used, the results are<br/>
        not corrected automatically.</li>
        <li>Some definitions determining the observer position are used<br/>
        from the global device, i.e.<br/>
        <ul>
        <code>attr global longitude &lt;value&gt;</code><br/>
        <code>attr global latitude &lt;value&gt;</code><br/>
        <code>attr global altitude &lt;value&gt;</code> (in m above sea level)
        </ul>
        These definitions are only used when there are no corresponding local attribute settings on the device.
        </li>
        <li>
        It is not necessary to define an Astro device to use the data provided by this module.<br/>
        To use its data in any other module, you just need to put <code>LoadModule("Astro");</code> <br/>
        at the start of your own code, and then may call, for example, the function<br/> 
        <ul><code>Astro_Get( SOME_HASH_REFERENCE,"dummy","text", "SunRise","2019-12-24");</code></ul>
        to acquire the sunrise on Christmas Eve 2019. The hash reference may also be undefined or an existing device name of any type. Note that device attributes of the respective device will be respected as long as their name matches those mentioned for an Astro device.
        attribute=value pairs may be added in text format to enforce
        settings like language that would otherwise be defined by a real device.<br/>
        You may also add parameters to customize your request:<br/>
        <ul><code>Astro_Get( SOME_HASH_REFERENCE, ["dummy","text"], {html=>1} );</code><br/>
        <code>Astro_Get( SOME_HASH_REFERENCE, ["dummy","text","SunRise,SunSet,SunAz,SunDistanceObserver"], {html=>1, long=>2} );</code></ul>
        </li>
        </ul>
        <a name="Astroset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="Astro_update"></a>
                <code>set &lt;name&gt; update</code>
                <br />trigger to recompute values immediately.</li>
        </ul>
        <a name="Astroget"></a>
        <h4>Get</h4>
        Attention: Get-calls are NOT written into the readings of the device. Readings change only through periodic updates.<br/>
        <ul>
            <li><a name="Astro_json"></a>
                <code>get &lt;name&gt; json [&lt;reading&gt;,[&lt;reading&gt;]] [-1|yesterday|+1|tomorrow]</code><br/>
                <code>get &lt;name&gt; json [&lt;reading&gt;,[&lt;reading&gt;]] YYYY-MM-DD [-1|yesterday|+1|tomorrow]</code><br/>
                <code>get &lt;name&gt; json [&lt;reading&gt;,[&lt;reading&gt;]] HH:MM[:SS] [-1|yesterday|+1|tomorrow]</code><br/>
                <code>get &lt;name&gt; json [&lt;reading&gt;,[&lt;reading&gt;]] YYYY-MM-DD HH:MM[:SS] [-1|yesterday|+1|tomorrow]</code>
                <br />returns the complete set of an individual reading of astronomical data either for the current time, or for a day and time given in the argument. <code>yesterday</code>, <code>tomorrow</code> or any other integer number may be given at the end to get data relative to the given day and time.<br/>
                Formatted values as described below may be generated in a subtree <code>text</code> by adding <code>text=1</code> to the request.</li>
            <li><a name="Astro_text"></a>
                <code>get &lt;name&gt; text [&lt;reading&gt;,[&lt;reading&gt;]] [-1|yesterday|+1|tomorrow]</code><br/>
                <code>get &lt;name&gt; text [&lt;reading&gt;,[&lt;reading&gt;]] YYYY-MM-DD [-1|yesterday|+1|tomorrow]</code><br/>
                <code>get &lt;name&gt; text [&lt;reading&gt;,[&lt;reading&gt;]] HH:MM[:SS] [-1|yesterday|+1|tomorrow]</code><br/>
                <code>get &lt;name&gt; text [&lt;reading&gt;,[&lt;reading&gt;]] YYYY-MM-DD HH:MM[:SS] [-1|yesterday|+1|tomorrow]</code>
                <br />returns the complete set of an individual reading of astronomical data either for the current time, or for a day and time given in the argument. <code>yesterday</code>, <code>tomorrow</code> or any other integer number may be given at the end to get data relative to the given day and time.<br/>
                The return value may be formatted and/or labeled by adding one or more of the following key=value pairs to the request:
                      <ul>
                      <li><i>unit=1</i> = Will add a unit to numerical values. Depending on attribute lc_numeric, the decimal separator will be in regional format as well.</li>
                      <li><i>long=1</i> = A describtive label will be added to the value.</li>
                      <li><i>long=2</i> = Same as long=1 but the label will be separated from the value by a colon.</li>
                      <li><i>long=3</i> = Same as long=2 but Sun or Moon will be added as a prefix.</li>
                      <li><i>long=4</i> = Same as long=3 but the separator will be used to separate Sun/Moon instead.</li>
                      </ul></li>
            <li><a name="Astro_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Display the version of the module</li>             
        </ul>
        <a name="Astroattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="Astro_interval"></a>
                <code>&lt;interval&gt;</code>
                <br />Update interval in seconds. The default is 3600 seconds, a value of 0 disables the periodic update.</li>
            <li><a name="Astro_language"></a>
                <code>&lt;language&gt;</code>
                <br />A language may be set to overwrite global attribute settings.</li>
            <li><a name="Astro_lc_numeric"></a>
                <code>&lt;lc_numeric&gt;</code>
                <br />Set regional settings to format numerical values in textual output. If not set, it will generate the locale based on the attribute <i>language</i> (if set).</li>
            <li><a name="Astro_lc_time"></a>
                <code>&lt;lc_time&gt;</code>
                <br />Set regional settings to format time related values in textual output. If not set, it will generate the locale based on the attribute <i>language</i> (if set).</li>
            <li><a name="Astro_recomputeAt"></a>
                <code>&lt;recomputeAt&gt;</code>
                <br />Enforce recomputing values at specific event times, independant from update interval. This attribute contains a list of one or many of the following values:<br />
                      <ul>
                      <li><i>MoonRise,MoonSet,MoonTransit</i> = for moon rise, set, and transit</li>
                      <li><i>NewDay</i> = for 00:00:00 hours of the next calendar day</li>
                      <li><i>SunRise,SunSet,SunTransit</i> = for sun rise, set, and transit</li>
                      <li><i>*TwilightEvening,*TwilightMorning</i> = for the respective twilight stage begin</li>
                      </ul></li>
            <li><a name="Astro_timezone"></a>
                <code>&lt;timezone&gt;</code>
                <br />A timezone may be set to overwrite global and system settings. Format may depend on your local system implementation but is likely in the format similar to <code>Europe/Berlin</code>.</li>
            <li>Some definitions determining the observer position:<br/>
                <ul>
                <code>attr  &lt;name&gt;  longitude &lt;value&gt;</code><br/>
                <code>attr  &lt;name&gt;  latitude &lt;value&gt;</code><br/>
                <code>attr  &lt;name&gt;  altitude &lt;value&gt;</code> (in m above sea level)<br/>
                <code>attr  &lt;name&gt;  horizon &lt;value&gt;</code> custom horizon angle in degrees, default 0. Different values for morning/evening may be set as <code>&lt;morning&gt;:&lt;evening&gt;</code>
                </ul>
                These definitions take precedence over global attribute settings.</li>
            <li><a name="Astro_disable"></a>
                <code>&lt;disable&gt;</code>
                <br />When set, this will completely disable any device update.</li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        </ul>
=end html
=begin html_DE

<a name="Astro"></a>
<h3>Astro</h3>
<ul>
<a href="https://wiki.fhem.de/wiki/Modul_Astro">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="commandref.html#Astro">Astro</a> 
</ul>
=end html_DE
=for :application/json;q=META.json 95_Astro.pm
{
  "version": "v2.0.2",
  "author": [
    "Prof. Dr. Peter A. Henning <>",
    "Julian Pawlowski <>",
    "Marko Oldenburg <>"
  ],
  "x_fhem_maintainer": [
    "pahenning",
    "loredo",
    "CoolTux"
  ],
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/Modul_Astro"
    }
  },
  "keywords": [
    "astrology",
    "astronomy",
    "constellation",
    "moon",
    "sun",
    "star sign",
    "twilight",
    "zodiac",
    "Astrologie",
    "Astronomie",
    "Mond",
    "Sonne",
    "Sternbild",
    "Sternzeichen",
    "Tierkreiszeichen",
    "Zodiak"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "Encode": 0,
        "GPUtils": 0,
        "Math::Trig": 0,
        "POSIX": 0,
        "Time::HiRes": 0,
        "Time::Local": 0,
        "strict": 0,
        "utf8": 0,
        "warnings": 0
      },
      "recommends": {
        "JSON": 0
      },
      "suggests": {
        "Cpanel::JSON::XS": 0,
        "JSON::XS": 0
      }
    }
  }
}
=end :application/json;q=META.json
=cut

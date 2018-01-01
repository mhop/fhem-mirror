# $Id$

##############################################################################
#
#     YahooWeatherAPI.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;
use JSON;               # apt-get install libperl-JSON on Debian and derivatives
#use Data::Dumper;       # for Debug only

# Yahoo! Weather API: http://developer.yahoo.com/weather/

use constant URL => "https://query.yahooapis.com/v1/public/yql?q=select%%20*%%20from%%20weather.forecast%%20where%%20woeid=%s%%20and%%20u=%%27c%%27&format=%s&env=store%%3A%%2F%%2Fdatatables.org%%2Falltableswithkeys";


# Mapping / translation of current weather codes 0-47
my @YahooCodes_en = (
       'tornado', 'tropical storm', 'hurricane', 'severe thunderstorms', 'thunderstorms', 'mixed rain and snow',
       'mixed rain and sleet', 'mixed snow and sleet', 'freezing drizzle', 'drizzle', 'freezing rain' ,'showers',
       'showers', 'snow flurries', 'light snow showers', 'blowing snow', 'snow', 'hail',
       'sleet', 'dust', 'foggy', 'haze', 'smoky', 'blustery',
       'windy', 'cold', 'cloudy',
       'mostly cloudy', # night
       'mostly cloudy', # day
       'partly cloudy', # night
       'partly cloudy', # day
       'clear',
       'sunny',
       'fair', #night
       'fair', #day
       'mixed rain and hail',
       'hot', 'isolated thunderstorms', 'scattered thunderstorms', 'scattered thunderstorms', 'scattered showers', 'heavy snow',
       'scattered snow showers', 'heavy snow', 'partly cloudy', 'thundershowers', 'snow showers', 'isolated thundershowers');

my @YahooCodes_de = (
       'Tornado', 'schwerer Sturm', 'Orkan', 'schwere Gewitter', 'Gewitter', 'Regen und Schnee',
       'Regen und Graupel', 'Schnee und Graupel', 'Eisregen', 'Nieselregen', 'gefrierender Regen' ,'Schauer',
       'Schauer', 'Schneetreiben', 'leichte Schneeschauer', 'Schneeverwehungen', 'Schnee', 'Hagel',
       'Graupel', 'Staub', 'Nebel', 'Dunst', 'Smog', 'Sturm',
       'windig', 'kalt', 'wolkig',
       'überwiegend wolkig', # night
       'überwiegend wolkig', # day
       'teilweise wolkig', # night
       'teilweise wolkig', # day
       'klar', # night
       'sonnig',
       'heiter', # night
       'heiter', # day
       'Regen und Hagel',
       'heiß', 'einzelne Gewitter', 'vereinzelt Gewitter', 'vereinzelt Gewitter', 'vereinzelt Schauer', 'starker Schneefall',
       'vereinzelt Schneeschauer', 'starker Schneefall', 'teilweise wolkig', 'Gewitterregen', 'Schneeschauer', 'vereinzelt Gewitter');

my @YahooCodes_nl = (
       'tornado', 'zware storm', 'orkaan', 'hevig onweer', 'onweer',
       'regen en sneeuw',
       'regen en ijzel', 'sneeuw en ijzel', 'aanvriezende motregen',
       'motregen', 'aanvriezende regen' ,'buien',
       'buien', 'sneeuw windstoten', 'lichte sneeuwbuien',
       'stuifsneeuw', 'sneeuw', 'hagel',
       'ijzel', 'stof', 'mist', 'waas', 'smog', 'onstuimig',
       'winderig', 'koud', 'bewolkt',
       'overwegend bewolkt', # night
       'overwegend bewolkt', # day
       'gedeeltelijk bewolkt', # night
       'gedeeltelijk bewolkt', # day
       'helder', #night
       'zonnig',
       'mooi', #night
       'mooi', #day
       'regen en hagel',
       'heet', 'plaatselijk onweer', 'af en toe onweer', 'af en toe onweer', 'af en toe regenbuien', 'hevige sneeuwval',
       'af en toe sneeuwbuien', 'hevige sneeuwval', 'deels bewolkt',
       'onweersbuien', 'sneeuwbuien', 'af en toe onweersbuien');

my @YahooCodes_fr = (
       'tornade', 'tempête tropicale', 'ouragan', 'tempête sévère', 'orage', 'pluie et neige',
       'pluie et grésil', 'neige et grésil', 'bruine verglassante', 'bruine', 'pluie verglassante' ,'averse',
       'averses', 'tourbillon de neige', 'légères averses de neige', 'rafale de neige', 'neige', 'grêle',
       'giboulées', 'poussières', 'brouillard', 'brume', 'enfumé', 'orageux',
       'venteux', 'froid', 'nuageux',
       'couverte', # night
       'couvert', # day
       'partiellement couverte', # night
       'partiellement couvert', # day
       'clair',
       'ensoleillé',
       'douce', #night
       'agréable', #day
       'pluie et grêle',
       'chaud', 'orages isolés', 'tempêtes éparses', 'orages épars', 'averses éparses', 'tempête de neige',
       'chûtes de neiges éparses', 'tempêtes de neige', 'partielement nuageux', 'averses orageuses', 'chûte de neige', 'chûtes de neige isolées');

my @YahooCodes_pl = (
       'tornado', 'burza tropikalna', 'huragan', 'porywiste burze', 'burze', 'deszcz ze śniegiem',
       'deszcz i deszcz ze śniegiem', 'śnieg i deszcz ze śniegiem', 'marznąca mżawka', 'mżawka', 'marznący deszcz' ,'deszcz',
       'deszcz', 'przelotne opady śniegu', 'lekkie opady śniegu', 'zamieć śnieżna', 'śnieg', 'grad',
       'deszcz ze śniegiem', 'pył', 'mgła', 'mgła', 'smog', 'przenikliwie',
       'wietrznie', 'zimno', 'pochmurno',
       'pochmurno', # night
       'pochmurno', # day
       'częściowe zachmurzenie', # night
       'częściowe zachmurzenie', # day
       'czyste niebo',
       'słonecznie',
       'ładna noc', #night
       'ładny dzień', #day
       'deszcz z gradem',
       'gorąco', 'gdzieniegdzie burze', 'burze', 'burze', 'przelotne opady śniegu', 'duże opady śniegu',
       'ciężkie opady śniegu', 'dużo śniegu', 'częściowe zachmurzenie', 'burze z deszczem', 'opady śniegu', 'przejściowo burze');

###################################

# Cache
my %YahooWeatherAPI_CachedData= ();
my %YahooWeatherAPI_CachedDataTs= ();

###################################

#
# there is a bug in the Yahoo Weather API that gets all units wrong
# these routines fix that


sub value_to_C($) {
    my ($F)= @_;
    return(int(($F-32)*5/9+0.5));
}

sub value_to_hPa($) {
    my ($inHg)= @_;
    return int($inHg/33.86390+0.5);
}

sub value_to_km($) {
    my ($value)= @_;
    return int($value/1.609347219+0.5);
}

###################################

# call: YahooWeatherAPI_RetrieveData(%%args)
#
# the args hash reference must contain at least
#   woeid          => WOEID [WHERE-ON-EARTH-ID], go to http://weather.yahoo.com to find out
#   format         => xml or json
#   blocking       => 0 or 1
#   callbackFnRef  => reference to callback function with arguments ($argsRef, $err, $result)
# the args hash reference is returned as first argument of the callbackFn
#

sub YahooWeatherAPI_RetrieveData($) {
    my ($argsRef)= @_;
    YahooWeatherAPI_RetrieveDataWithCache(0, $argsRef);
}

sub YahooWeatherAPI_RetrieveDataWithCache($$) {

    my ($maxage, $argsRef)= @_;
    my $woeid= $argsRef->{woeid};

    Log3 undef, 5, "YahooWeatherAPI: retrieve weather for $woeid.";

    # retrieve data from cache
    my $ts= $YahooWeatherAPI_CachedDataTs{$woeid};
    if(defined($ts)) {
        my $now= time();
        my $age= $now- $ts;
        if($age< $maxage) {
            Log3 undef, 5, "YahooWeatherAPI: data is cached, age $age seconds < $maxage seconds.";
            $argsRef->{callbackFnRef}($argsRef, "", $YahooWeatherAPI_CachedData{$woeid});
            return;
        } else {
            Log3 undef, 5, "YahooWeatherAPI: cache is expired, age $age seconds > $maxage seconds.";
        }
    } else {
            Log3 undef, 5, "YahooWeatherAPI: no data in cache.";
    }

    my $format= $argsRef->{format};
    my $blocking= $argsRef->{blocking};
    my $callbackFnRef= $argsRef->{callbackFnRef};

    my $url = sprintf(URL, $woeid, $format);

    #Debug "Retrieve Yahoo Weather data for " . $argsRef->{hash}->{NAME};

    if ($blocking) {
        # do not use noshutdown => 0 in parameters
        my $response = HttpUtils_BlockingGet({ url => $url, timeout => 15 });
        my %param= (argsRef => $argsRef);
        YahooWeatherAPI_RetrieveDataFinished(\%param, undef, $response);
    } else {
        # do not use noshutdown => 0 in parameters
        HttpUtils_NonblockingGet({
            url        => $url,
            timeout    => 15,
            argsRef    => $argsRef,
            callback   => \&YahooWeatherAPI_RetrieveDataFinished,
            });
    }
}

sub YahooWeatherAPI_RetrieveDataFinished($$$) {
    my ($paramRef, $err, $response) = @_;
    my $argsRef= $paramRef->{argsRef};
    #Debug "Finished retrieving Yahoo Weather data for " . $argsRef->{hash}->{NAME};
    if(!$err) {
        my $woeid= $argsRef->{woeid};
        $YahooWeatherAPI_CachedDataTs{$woeid}= time();
        $YahooWeatherAPI_CachedData{$woeid}= $response;
        Log3 undef, 5, "YahooWeatherAPI: caching data.";
    }
    $argsRef->{callbackFnRef}($argsRef, $err, $response);
}


# this decodes a JSON result and returns the Weather Channel hash reference
sub YahooWeatherAPI_JSONReturnChannelData($) {
    my ($response)= @_;
    return("empty response", undef) unless($response);
    #Debug "Decoding response: $response";
    #Debug "response: " . Dumper($response);
    my $data;
    eval { $data= decode_json($response) };
    return($@, undef) if($@);
    my $query= $data->{query};
    #Debug Dumper($query);
    my $count= $query->{count};
    #Debug "$count result(s).";
    return("$count result(s) retrieved", undef) unless($count == 1);
    my $channel= $query->{results}{channel};
    return(undef, $channel);
}

sub YahooWeatherAPI_ConvertChannelData($) {
    my ($data)= @_; # hash reference

    $data->{wind}{chill}= value_to_C($data->{wind}{chill}); # # API delivers wrong value
    $data->{atmosphere}{pressure}= value_to_hPa($data->{atmosphere}{pressure}); # API delivers wrong value


    my $units= YahooWeatherAPI_units($data); # units hash reference

    $data->{wind}{speed}= value_to_km($data->{wind}{speed}); # API delivers km
    $data->{atmosphere}{visibility}= value_to_km($data->{atmosphere}{visibility}); # API delivers km

    return 0 if($units->{temperature} eq "C");

    my $item= $data->{item};
    $item->{condition}{temp}= value_to_C($item->{condition}{temp});

    my $forecast= $item->{forecast};
    foreach my $fc (@{$forecast}) {
        $fc->{low}= value_to_C($fc->{low});
        $fc->{high}= value_to_C($fc->{high});
    }
    return 1;

}


sub YahooWeatherAPI_ParseDateTime($) {

    my ($value)= @_; ### "Fri, 13 Nov 2015 8:00 am CET"

    my @months= qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
    my %monthindex;
    @monthindex{@months} = (0..$#months);

    if($value =~ '^(\w{3}), (\d{1,2}) (\w{3}) (\d{4}) (\d{1,2}):(\d{2}) (\w{2}) (\w{3,4})$') {
        my ($wd, $d, $mon, $y, $h, $n, $p, $tz)= ($1,$2,$3,$4,$5,$6,$7,$8);
        # 12 AM= 0, 12 PM= 12
        $h+=12 if($h==12); if($p eq "PM") { $h= ($h+12) % 24 } else { $h%= 12 };
        my $m= $monthindex{$mon};
        return undef unless defined($m);
        #main::Debug "######  $value -> $wd $d $m $y $h:$n $tz";
        # $mday= 1..
        # $month= 0..11
        # $year is year-1900
        # we ignore the time zone as it probably never changes for a weather device an assume
        # local time zone
        return fhemTimeLocal(0, $n, $h, $d, $m, $y-1900);
    } else {
        return undef;
    }
}

sub YahooWeatherAPI_pubDate($) {

    my ($channel)= @_;

    ### pubDate  Fri, 13 Nov 2015 8:00 am CET
    if(!defined($channel->{item}{pubDate})) {
        return("no pubDate received", "", undef);
    };
    my $pubDate= $channel->{item}{pubDate};
    my $ts= YahooWeatherAPI_ParseDateTime($pubDate);
    if(defined($ts)) {
        return("okay", $pubDate, $ts);
    } else {
        return("could not parse pubDate $pubDate", $pubDate, undef);
    }
}

sub YahooWeatherAPI_units($) {

    my ($channel)= @_;
    return $channel->{units};
}

sub YahooWeatherAPI_getYahooCodes($) {

    my ($lang)= @_;

    if($lang eq "de") {
        return @YahooCodes_de;
    } elsif($lang eq "nl") {
        return @YahooCodes_nl;
    } elsif($lang eq "fr") {
        return @YahooCodes_fr;
    } elsif($lang eq "pl") {
        return @YahooCodes_pl;
    } else {
        return @YahooCodes_en;
    }
}

##############################################################################

1;

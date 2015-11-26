# $Id$

# copyright and license informations
=pod
###################################################################################################
#
#	55_GDS.pm
#
#	An FHEM Perl module to retrieve data from "Deutscher Wetterdienst"
#
#	Copyright: betateilchen ®
#
#   includes:  some patches provided by jensb
#              forecasts    provided by jensb
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###################################################################################################
=cut

package main;

use strict;
use warnings;
use feature qw/switch/;

use Blocking;
use Archive::Extract;
use Net::FTP;
use XML::Simple;

use Data::Dumper;

eval "use GDSweblink";

no if $] >= 5.017011, warnings => 'experimental';

my ($bulaList, $cmapList, %rmapList, $fmapList, %bula2bulaShort, 
    %bulaShort2dwd, %dwd2Dir, %dwd2Name, $alertsXml, %capCityHash,
    %capCellHash, $sList, $aList, $fList, $fcList, $fcmapList, $tempDir, @weekdays);

my %allForecastData;
my @allConditionsData;

###################################################################################################
#
#	Main routines

sub GDS_Initialize($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	return "This module must not be used on microso... platforms!" if($^O =~ m/Win/);

	$hash->{DefFn}		=	"GDS_Define";
	$hash->{UndefFn}	=	"GDS_Undef";
	$hash->{GetFn}		=	"GDS_Get";
	$hash->{SetFn}		=	"GDS_Set";
	$hash->{ShutdownFn}	=	"GDS_Shutdown";
#	$hash->{NotifyFn}   =   "GDS_Notify";
	$hash->{NOTIFYDEV}  =   "global";
	$hash->{AttrFn}		=	"GDS_Attr";
	
	no warnings 'qw';
	my @attrList = qw(
		disable:0,1
		gdsAll:0,1
		gdsDebug:0,1
		gdsFwName
		gdsFwType:0,1,2,3,4,5,6,7
		gdsHideFiles:0,1
		gdsLong:0,1
		gdsPassiveFtp:1,0
		gdsPolygon:0,1
		gdsSetCond
		gdsSetForecast
		gdsUseAlerts:0,1
		gdsUseForecasts:0,1
	);
	use warnings 'qw';
	$hash->{AttrList}  = join(" ", @attrList);
	$hash->{AttrList} .= " $readingFnAttributes";

    $tempDir  = "/tmp/";
	_fillMappingTables($hash);

}
sub _fillMappingTables($){
    my ($hash) = @_;

    $tempDir  = "/tmp/";
    
    $aList    = "no_data";
	$sList    = $aList;
 	$fList    = $aList;
 	$fcList   = $aList;

	$bulaList =	"Baden-Württemberg,Bayern,Berlin,Brandenburg,Bremen,".
				"Hamburg,Hessen,Mecklenburg-Vorpommern,Niedersachsen,".
				"Nordrhein-Westfalen,Rheinland-Pfalz,Saarland,Sachsen,".
				"Sachsen-Anhalt,Schleswig-Holstein,Thüringen";

	$cmapList =	"Deutschland,Mitte,Nordost,Nordwest,Ost,Suedost,Suedwest,West";

	%rmapList = (
	Deutschland	=> "",
	Mitte		=> "central/",
	Nordost		=> "northeast/",
	Nordwest	=> "northwest/",
	Ost			=> "east/",
	Suedost		=> "southeast/",
	Suedwest	=> "southwest/",
	West		=> "west/");

	$fmapList =	"Deutschland_heute_frueh,Deutschland_heute_mittag,Deutschland_heute_spaet,Deutschland_heute_nacht,".
				"Deutschland_morgen_frueh,Deutschland_morgen_spaet,".
				"Deutschland_ueberm_frueh,Deutschland_ueberm_spaet,".
				"Deutschland_tag4_frueh,Deutschland_tag4_spaet,".
				"Mitte_heute_frueh,Mitte_heute_mittag,Mitte_heute_spaet,Mitte_heute_nacht,".
				"Mitte_morgen_frueh,Mitte_morgen_spaet,".
				"Mitte_ueberm_frueh,Mitte_ueberm_spaet,".
				"Mitte_tag4_frueh,Mitte_tag4_spaet,".
				"Nordost_heute_frueh,Nordost_heute_mittag,Nordost_heute_spaet,Nordost_heute_nacht,".
				"Nordost_morgen_frueh,Nordost_morgen_spaet,".
				"Nordost_ueberm_frueh,Nordost_ueberm_spaet,".
				"Nordost_tag4_frueh,Nordost_tag4_spaet,".
				"Nordwest_heute_frueh,Nordwest_heute_mittag,Nordwest_heute_spaet,Nordwest_heute_nacht,".
				"Nordwest_morgen_frueh,Nordwest_morgen_spaet,".
				"Nordwest_ueberm_frueh,Nordwest_ueberm_spaet,".
				"Nordwest_tag4_frueh,Nordwest_tag4_spaet,".
				"Ost_heute_frueh,Ost_heute_mittag,Ost_heute_spaet,Ost_heute_nacht,".
				"Ost_morgen_frueh,Ost_morgen_spaet,".
				"Ost_ueberm_frueh,Ost_ueberm_spaet,".
				"Ost_tag4_frueh,Ost_tag4_spaet,".
				"Suedost_heute_frueh,Suedost_heute_mittag,Suedost_heute_spaet,Suedost_heute_nacht,".
				"Suedost_morgen_frueh,Suedost_morgen_spaet,".
				"Suedost_ueberm_frueh,Suedost_ueberm_spaet,".
				"Suedost_tag4_frueh,Suedost_tag4_spaet,".
				"Suedwest_heute_frueh,Suedwest_heute_mittag,Suedwest_heute_spaet,Suedwest_heute_nacht,".
				"Suedwest_morgen_frueh,Suedwest_morgen_spaet,".
				"Suedwest_ueberm_frueh,Suedwest_ueberm_spaet,".
				"Suedwest_tag4_frueh,Suedwest_tag4_spaet,".
				"West_heute_frueh,West_heute_mittag,West_heute_spaet,West_heute_nacht,".
				"West_morgen_frueh,West_morgen_spaet,".
				"West_ueberm_frueh,West_ueberm_spaet,".
				"West_tag4_frueh,West_tag4_spaet";

	$fcmapList =	"Deutschland_frueh,Deutschland_mittag,Deutschland_spaet,Deutschland_nacht,".
				"Deutschland_morgen_frueh,Deutschland_morgen_spaet,".
				"Deutschland_uebermorgen_frueh,Deutschland_uebermorgen_spaet,".
				"Deutschland_Tag4_frueh,Deutschland_Tag4_spaet,".
				"Mitte_frueh,Mitte_mittag,Mitte_spaet,Mitte_nacht,".
				"Mitte_morgen_frueh,Mitte_morgen_spaet,".
				"Mitte_uebermorgen_frueh,Mitte_uebermorgen_spaet,".
				"Mitte_Tag4_frueh,Mitte_Tag4_spaet,".
				"Nordost_frueh,Nordost_mittag,Nordost_spaet,Nordost_nacht,".
				"Nordost_morgen_frueh,Nordost_morgen_spaet,".
				"Nordost_uebermorgen_frueh,Nordost_uebermorgen_spaet,".
				"Nordost_Tag4_frueh,Nordost_Tag4_spaet,".
				"Nordwest_frueh,Nordwest_mittag,Nordwest_spaet,Nordwest_nacht,".
				"Nordwest_morgen_frueh,Nordwest_morgen_spaet,".
				"Nordwest_uebermorgen_frueh,Nordwest_uebermorgen_spaet,".
				"Nordwest_Tag4_frueh,Nordwest_Tag4_spaet,".
				"Ost_frueh,Ost_mittag,Ost_spaet,Ost_nacht,".
				"Ost_morgen_frueh,Ost_morgen_spaet,".
				"Ost_uebermorgen_frueh,Ost_uebermorgen_spaet,".
				"Ost_Tag4_frueh,Ost_Tag4_spaet,".
				"Suedost_frueh,Suedost_mittag,Suedost_spaet,Suedost_nacht,".
				"Suedost_morgen_frueh,Suedost_morgen_spaet,".
				"Suedost_uebermorgen_frueh,Suedost_uebermorgen_spaet,".
				"Suedost_Tag4_frueh,Suedost_Tag4_spaet,".
				"Suedwest_frueh,Suedwest_mittag,Suedwest_spaet,Suedwest_nacht,".
				"Suedwest_morgen_frueh,Suedwest_morgen_spaet,".
				"Suedwest_uebermorgen_frueh,Suedwest_uebermorgen_spaet,".
				"Suedwest_Tag4_frueh,Suedwest_Tag4_spaet,".
				"West_frueh,West_mittag,West_spaet,West_nacht,".
				"West_morgen_frueh,West_morgen_spaet,".
				"West_uebermorgen_frueh,West_uebermorgen_spaet,".
				"West_Tag4_frueh,West_Tag4_spaet";

#
# Bundesländer den entsprechenden Dienststellen zuordnen
#
	%bula2bulaShort = (
	"baden-württemberg"			=> "bw",
	"bayern"					=> "by",
	"berlin"					=> "be",
	"brandenburg"				=> "bb",
	"bremen"					=> "hb",
	"hamburg"					=> "hh",
	"hessen" 					=> "he",
	"mecklenburg-vorpommern"	=> "mv",
	"niedersachsen"				=> "ni",
	"nordrhein-westfalen"		=> "nw",
	"rheinland-pfalz"			=> "rp",
	"saarland"					=> "sl",
	"sachsen"					=> "sn",
	"sachsen-anhalt"			=> "st",
	"schleswig-holstein"		=> "sh",
	"thüringen"					=> "th",
	"deutschland"				=> "xde",
	"bodensee"					=> "xbo" );

	%bulaShort2dwd = (
	bw => "DWSG",
	by => "DWMG",
	be => "DWPG",
	bb => "DWPG",
	hb => "DWHG",
	hh => "DWHH",
	he => "DWOH",
	mv => "DWPH",
	ni => "DWHG",
	nw => "DWEH",
	rp => "DWOI",
	sl => "DWOI",
	sn => "DWLG",
	st => "DWLH",
	sh => "DWHH",
	th => "DWLI",
	xde => "xde",
	xbo => "xbo" );

#
# Dienststellen den entsprechenden Serververzeichnissen zuordnen
#
	%dwd2Dir = (
	DWSG => "SU", # Stuttgart
	DWMG => "MS", # München
	DWPG => "PD", # Potsdam
	DWHG => "HA", # Hamburg
	DWHH => "HA", # Hamburg
	DWOH => "OF", # Offenbach
	DWPH => "PD", # Potsdam
	DWHG => "HA", # Hamburg
	DWEH => "EM", # Essen
	DWOI => "OF", # Offenbach
	DWLG => "LZ", # Leipzig
	DWLH => "LZ", # Leipzig
	DWLI => "LZ", # Leipzig
	DWHC => "HA", # Hamburg
	DWHB => "HA", # Hamburg
	DWPD => "PD", # Potsdam
	DWRW => "PD", # Potsdam
	DWEM => "EM", # Essen
	LSAX => "LZ", # Leipzig
	LSNX => "LZ", # Leipzig
	THLX => "LZ", # Leipzig
	DWOF => "OF", # Offenbach
	DWTR => "OF", # Offenbach
	DWSU => "SU", # Stuttgart
	DWMS => "MS", # München
	xde  => "D",
	xbo  => "Bodensee");
#	???? => "FG" # Freiburg);

	%dwd2Name = (
	EM => "Essen",
	FG => "Freiburg",
	HA => "Hamburg",
	LZ => "Leipzig",
	MS => "München",
	OF => "Offenbach",
	PD => "Potsdam",
	SU => "Stuttgart");

  
# German weekdays  
    @weekdays = ("So", "Mo", "Di", "Mi", "Do", "Fr", "Sa");  
 
    return;
}

sub GDS_Define($$$) {
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return "syntax: define <name> GDS <username> <password> [<host>]" if(int(@a) != 4 ); 
#	return "You must not define more than one gds device!" if int(devspec2array('TYPE=GDS'));

	$hash->{helper}{USER}		= $a[2];
	$hash->{helper}{PASS}		= $a[3];
	$hash->{helper}{URL}		= defined($a[4]) ? $a[4] : "ftp-outgoing2.dwd.de";
	$hash->{helper}{INTERVAL}   = 1200;

	Log3($name, 4, "GDS $name: created");
	Log3($name, 4, "GDS $name: tempDir=".$tempDir);

    _GDS_addExtension("GDS_CGI","gds","GDS Files");

	readingsSingleUpdate($hash, 'state', 'active',1);

	return undef;
}

sub GDS_Undef($$) {
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	RemoveInternalTimer($hash);
    my $url = '/gds';
    delete $data{FWEXT}{$url} if int(devspec2array('TYPE=GDS')) == 1;
	return undef;
}

sub GDS_Shutdown($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	RemoveInternalTimer($hash);
	Log3 ($name,4,"GDS $name: shutdown requested");
	return undef;
}

sub GDS_Notify ($$) {
	my ($hash,$dev) = @_;
	my $name = $hash->{NAME};
	return if($dev->{NAME} ne "global");
	my $type = $dev->{CHANGED}[0];
	return unless (grep(m/^INITIALIZED/, $type));

	$aList		= "disabled_by_attribute" unless AttrVal($name,'gdsUseAlerts',0);
	$fList		= "disabled_by_attribute" unless AttrVal($name,'gdsUseForecasts',0);
	$fcmapList	= "disabled_by_attribute" unless AttrVal($name,'gdsUseForecasts',0);

	GDS_GetUpdate($hash);
	
	return undef;
}

sub GDS_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage =	"Unknown argument, choose one of ".
	            "clear:alerts,conditions,forecasts,all ".
				"conditions:$sList ".
				"forecasts:$fList ".
	            "help:noArg ".
	            "update:noArg ";				;

	my $command		= lc($a[1]);
	my $parameter	= $a[2] if(defined($a[2]));

	my ($result, $next);

	return $usage if $command eq '?';

	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
		return "GDS $name is disabled. Aborting..." if IsDisabled($name);
	}

	readingsSingleUpdate($hash, 'state', 'active', 0);

	given($command) {
		when("clear"){
			CommandDeleteReading(undef, "$name a_.*")
			       if(defined($parameter) && ($parameter eq "all" || $parameter eq "alerts"));
			CommandDeleteReading(undef, "$name c_.*")    
			       if(defined($parameter) && ($parameter eq "all" || $parameter eq "conditions"));
			CommandDeleteReading(undef, "$name g_.*")
			       if(defined($parameter) && ($parameter eq "all" || $parameter eq "conditions"));
			CommandDeleteReading(undef, "$name fc.?_.*") 
			       if(defined($parameter) && ($parameter eq "all" || $parameter eq "forecasts"));
			}

		when("help"){
			$result = setHelp();
			break;
			}

		when("update"){
			RemoveInternalTimer($hash);
			GDS_GetUpdate($hash,'set update');
			break;
			}

		when("conditions"){
            $attr{$name}{gdsSetCond} = $parameter; #ReadingsVal($name,'c_stationName',undef);
			GDS_GetUpdate($hash,'set conditions');
			break;
			}

		when("forecasts"){
			return "Error: Forecasts disabled by attribute." unless AttrVal($name,'gdsUseForecasts',0);
			CommandDeleteReading(undef, "$name fc.*") if($parameter ne AttrVal($name,'gdsSetForecast',''));
            $attr{$name}{gdsSetForecast} = $parameter;
			GDS_GetUpdate($hash,'set forecasts');
			break;
			}

		default { return $usage; };
	}
	return $result;
}

sub GDS_Get($@) {
	my ($hash, @a) = @_;
	my $command		= lc($a[1]);
	my $parameter	= $a[2] if(defined($a[2]));
	my $name = $hash->{NAME};

	my $usage = "Unknown argument $command, choose one of help:noArg rereadcfg:noArg ".
				"list:stations,capstations,data ".
				"alerts:".$aList." ".
				"conditions:".$sList." ".
				"conditionsmap:".$cmapList." ".
				"forecasts:".$fcList." ".
				"forecastsmap:".$fmapList." ".
				"headlines ".
				"radarmap:".$cmapList." ".
				"warningsmap:"."Deutschland,Bodensee,".$bulaList." ".
				"warnings:".$bulaList;

	return $usage if $command eq '?';

	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
		return "GDS $name is disabled. Aborting..." if IsDisabled($name);
	}

	readingsSingleUpdate($hash, 'state', 'active', 0);
	my $_gdsAll		= AttrVal($name,"gdsAll", 0);
	my $gdsDebug	= AttrVal($name,"gdsDebug", 0);

	my ($result, @datensatz, $found);

	given($command) {

		when("conditionsmap"){
			# retrieve map: current conditions
			$hash->{file}{dir}		= "gds/specials/observations/maps/germany/";
			$hash->{file}{dwd}		= $parameter."*";
			$hash->{file}{target}	= $tempDir.$name."_conditionsmap.jpg";
			retrieveData($hash,'FILE');
			break;
		}

		when("forecastsmap"){
			# retrieve map: forecasts
			$hash->{file}{dir}		= "gds/specials/forecasts/maps/germany/";
			$hash->{file}{dwd}		= $parameter."*";
			$hash->{file}{target}	= $tempDir.$name."_forecastsmap.jpg";
			retrieveData($hash,'FILE');
			break;
		}

		when("headlines"){
			$parameter //= "|";
			return gdsHeadlines($name,$parameter);
		}

		when("warningsmap"){
			# retrieve map: warnings
			if(length($parameter) != 2){
				$parameter = $bula2bulaShort{lc($parameter)};
			}
			$hash->{file}{dwd}		= "Schilder".$dwd2Dir{$bulaShort2dwd{lc($parameter)}}.".jpg";
			$hash->{file}{dir}		= "gds/specials/alerts/maps/";
			$hash->{file}{target}	= $tempDir.$name."_warningsmap.jpg";
			retrieveData($hash,'FILE');
			break;
		}

		when("radarmap"){
			# retrieve map: radar
			$parameter = ucfirst($parameter);
			$hash->{file}{dir}		= "gds/specials/radar/".$rmapList{$parameter};
			$hash->{file}{dwd}		= "Webradar_".$parameter."*";
			$hash->{file}{target}	= $tempDir.$name."_radarmap.jpg";
			retrieveData($hash,'FILE');
			break;
			}

		when("help"){
			$result = getHelp();
			break;
			}

		when("list"){
			given($parameter){
				when("capstations")	{ 
					return "Error: Alerts disabled by attribute." unless AttrVal($name,'gdsUseAlerts',0);
					$result = getListCapStations($hash,$parameter); }
				when("data")		{ $result = latin1ToUtf8(join("\n",@allConditionsData)); } # new
				when("stations")	{
					my @a = map (latin1ToUtf8(substr($_,0,19)), @allConditionsData);    
         			unshift(@a, "Use one of the following stations:", sepLine(40));
					$result = join("\n",@a);
				}
				default				{ $usage  = "get <name> list <parameter>"; return $usage; }
			}
			break;
			}

		when("alerts"){
			return "Error: Alerts disabled by attribute." unless AttrVal($name,'gdsUseAlerts',0);

			if($parameter =~ y/0-9// == length($parameter)){
				while ( my( $key, $val ) = each %capCellHash ) {
					push @datensatz,$val if $key =~ m/^$parameter/;
				}
#				push @datensatz,$capCellHash{$parameter};
			} else {
				push @datensatz,$capCityHash{$parameter};
			}
			CommandDeleteReading(undef, "$name a_.*");
			if($datensatz[0]){
				my $anum = 0;
				foreach(@datensatz) {
					decodeCAPData($hash,$_,$anum);
					$anum++;
				};
				readingsSingleUpdate($hash,'a_count',$anum,1);
			} else {
				$result = "Keine Warnmeldung für die gesuchte Region vorhanden.";
			}
            my $_gdsAll		= AttrVal($name,"gdsAll", 0);
            my $gdsDebug	= AttrVal($name,"gdsDebug", 0);
			break;
			}

		when("headlines"){
			return "Error: Alerts disabled by attribute." unless AttrVal($name,'gdsUseAlerts',0);
			$result = gdsHeadlines($name);
			break;
			}

		when("conditions"){
			getConditions($hash, "g", @a);
			break;
			}

		when("rereadcfg"){
			DoTrigger($name, "REREAD", 1);
			$hash->{GDS_REREAD}  = int(time());
			retrieveData($hash,'conditions') if AttrVal($name,'gdsSetCond',0);
			if (AttrVal($name,'gdsUseAlerts',0)) {
				%capCityHash = ();
				%capCellHash = ();
				retrieveData($hash,'capdata');
				retrieveListCapStations($hash);
			}
			retrieveData($hash,'forecast')   if AttrVal($name,'gdsUseForecasts',0);
#			GDS_GetUpdate($hash);
			break;
			}

		when("warnings"){
			my $vhdl;
			$result =	"     VHDL30 = current          |     VHDL31 = weekend or holiday\n".
						"     VHDL32 = preliminary      |     VHDL33 = cancel VHDL32\n".
						sepLine(31)."+".sepLine(38)."\n";

			if(length($parameter) != 2){
				$parameter = $bula2bulaShort{lc($parameter)};
			}
			my $dwd = $bulaShort2dwd{lc($parameter)};
			my $dir = "gds/specials/warnings/".$dwd2Dir{$dwd}."/";
			$hash->{file}{dir}		= $dir;

			for ($vhdl=30; $vhdl <=33; $vhdl++){
				my $dwd2	= "VHDL".$vhdl."_".$dwd."*";
				my $target	= $tempDir.$name."_warnings_$vhdl";
				unlink $target;
				$hash->{file}{dwd}		= $dwd2;
				$hash->{file}{target}	= $target;
				retrieveData($hash,'FILE');
			}

			sleep 2;
			for ($vhdl=30; $vhdl <=33; $vhdl++){
				my $target	= $tempDir.$name."_warnings_$vhdl";
				$result .= retrieveText($hash, "warnings_$vhdl", "") if (-e $target);
				$result .= "\n".sepLine(70);
			}

			$result .= "\n\n";
			break;
			}

		when("forecasts"){
			return "Error: Forecasts disabled by attribute." unless AttrVal($name,'gdsUseForecasts',0);
			$parameter = "Daten_$parameter";
			my ($k,$v,$data);
			$result = sepLine(67)."\n";

			# retrieve from hash
			$data = undef;
			while(($k, $v) = each %allForecastData){
				if ($k eq $parameter) {
					$data = $v;
					last;
				};
			}
			$data //= "No forecast data found.";
			$data =~ s/\$/\n/g;
			$result .= $data;
			$result .= "\n".sepLine(67)."\n";
			break;
			}

		default { return $usage; };
	}
	return $result;
}

sub GDS_Attr(@){
	my @a = @_;
	my $hash = $defs{$a[1]};
	my ($cmd, $name, $attrName, $attrValue) = @a;
	my $useUpdate = 0;

	given($attrName){
 		when("gdsSetCond"){
			unless ($attrValue eq '' || $cmd eq 'del') {
				$attr{$name}{$attrName} = $attrValue;
				retrieveData($hash,'conditions');
				$useUpdate = 1;
			}
		}
 		when("gdsUseAlerts"){
			if ($attrValue == 0 || $cmd eq 'del') {
		    	$aList = "disabled_by_attribute";
			} else {
				$aList = "data_retrieval_running";
				retrieveData($hash,'capdata');
				retrieveListCapStations($hash);
			}
		}
 		when("gdsUseForecasts"){
			if ($attrValue == 0 || $cmd eq 'del') {
		    	$fList = "disabled_by_attribute";
		    	$fcList = "disabled_by_attribute";
			} else {
				$fcList = $fcmapList;
				$fList = "data_retrieval_running";
				$attr{$name}{$attrName} = $attrValue;
				retrieveData($hash,'forecast');
				$useUpdate = 1;
			}
		}
 		when("gdsHideFiles"){
 		    my $hR = AttrVal($FW_wname,'hiddenroom','');
 		    $hR =~ s/\,GDS.Files//g;
			if($attrValue) {
	 		    $hR .= "," if(length($hR));
 			    $hR .= "GDS Files";
			}
			CommandAttr(undef,"$FW_wname hiddenroom $hR");
 			break;
		}
		default {$attr{$name}{$attrName} = $attrValue;}
	}
	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
	} else {
		readingsSingleUpdate($hash, 'state', 'active', 0);
		if ($useUpdate) {
			RemoveInternalTimer($hash);
			my $next = gettimeofday()+$hash->{helper}{INTERVAL};
			InternalTimer($next, "GDS_GetUpdate", $hash, 0);
		}
	}
	return;
}

sub GDS_GetUpdate($;$) {
	my ($hash,$local) = @_;
	$local //= 0;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash);

	my $fs = AttrVal($name, "gdsSetForecast", 0);
	my $cs = AttrVal($name, "gdsSetCond",     0);

	if(IsDisabled($name)) {
    	readingsSingleUpdate($hash, 'state', 'disabled', 0);
		Log3 ($name, 2, "GDS $name is disabled, data update cancelled.");
	} else {
 		readingsSingleUpdate($hash, 'state', 'active', 0);
		if($cs) {
			if(time() - InternalVal($name,'GDS_CONDITIONS_READ',0) > ($hash->{helper}{INTERVAL}-10)) {
				retrieveData($hash,'conditions') ;
				my $next = gettimeofday() + 1;
				InternalTimer($next, "GDS_GetUpdate", $hash, 1);
				return;
			}
			my @a;
			push @a, undef;
			push @a, undef;
			push @a, $cs;
			getConditions($hash, "c", @a);
		}
		if($fs) {
			retrieveData($hash,'forecast') ;
			my @a;
			push @a, undef;
			push @a, undef;
			push @a, $fs;
			retrieveForecasts($hash, "fc", @a);    
		}
	}

	# schedule next update
	my $next = gettimeofday()+$hash->{helper}{INTERVAL};
	my $gdsAll		= AttrVal($name,"gdsAll", 0);
	my $gdsDebug	= AttrVal($name,"gdsDebug", 0);
	InternalTimer($next, "GDS_GetUpdate", $hash, 1);
	readingsSingleUpdate($hash, "_nextUpdate", localtime($next), 1) if($gdsAll || $gdsDebug);

	return 1;
}

###################################################################################################
#
#	FWEXT implementation

sub _GDS_addExtension($$$) {
    my ($func,$link,$friendlyname)= @_;
  
    my $url = "/" . $link;
    Log3(undef,4,"Register gds webservice in FWEXT");
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = "+$link";
    $data{FWEXT}{$url}{NAME} = $friendlyname;
    $data{FWEXT}{$url}{FORKABLE} = 0;
}
sub GDS_CGI {
  my ($request) = @_;
  my ($name,$ext)= _GDS_splitRequest($request);
  if(defined($name)) {
     my $filename= "$tempDir/$name.$ext";
     my $MIMEtype= filename2MIMEType($filename);
     my @contents;
     if(open(INPUTFILE, $filename)) {
       binmode(INPUTFILE);
       @contents= <INPUTFILE>;
       close(INPUTFILE);
       return("$MIMEtype; charset=utf-8", join("", @contents));
     } else {
       return("text/plain; charset=utf-8", "File not found: $filename");
     }
  } else {
    return _GDS_Overview();
  }
}
sub _GDS_splitRequest($) {
  my ($request) = @_;

  if($request =~ /^.*\/gds$/) {
    # http://localhost:8083/fhem/gds2
    return (undef,undef); # name, ext
  } else {
    my $call= $request;
    $call =~ s/^.*\/gds\/([^\/]*)$/$1/;
    my $name= $call;
    $name =~ s/^(.*)\.(jpg)$/$1/;
    my $ext= $call;
    $ext =~ s/^$name\.(.*)$/$1/;
    return ($name,$ext);
  }
}
sub _GDS_Overview {
  my ($name, $url);
  my $html= __GDS_HTMLHead("GDS Overview") . "<body>\n\n";
  foreach my $def (sort keys %defs) {
     if($defs{$def}{TYPE} eq "GDS") {
        $name  = $defs{$def}{NAME};
        $url   = __GDS_getURL();
        $html .= "$name<br>\n<ul>\n";
        $html .= "<a href=\"$url/gds/$name\_conditionsmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Wetterlage</a><br/>\n";
        $html .= "<a href=\"$url/gds/$name\_forecastsmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Vorhersage</a><br/>\n";
        $html .= "<a href=\"$url/gds/$name\_warningsmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Warnungen</a><br/>\n";
        $html .= "<a href=\"$url/gds/$name\_radarmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Radarkarte</a><br/>\n";
        $html .= "</ul>\n\n";
    }
  }
  $html.="</body>\n" . __GDS_HTMLTail();
  return ("text/html; charset=utf-8", $html);
}
sub __GDS_HTMLHead($) {
  my ($title) = @_;
  my $doctype = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" '.
                '"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
  my $xmlns   = 'xmlns="http://www.w3.org/1999/xhtml"';
  my $code    = "$doctype\n<html $xmlns>\n<head>\n<title>$title</title>\n</head>\n";
  return $code;
}
sub __GDS_getURL {
  my $proto = (AttrVal($FW_wname, 'HTTPS', 0) == 1) ? 'https' : 'http';
  return $proto."://$FW_httpheader{Host}$FW_ME"; #".$FW_ME;
}
sub __GDS_HTMLTail {
  return "</html>";
}

###################################################################################################
#
#	Tools

sub gdsAlertsHeadlines($;$) {
  my ($d,$sep) = @_;
  my $text = "";
  $sep = (defined($sep)) ? $sep : '|';
  my $count = ReadingsVal($d,'a_count',0);
  for (my $i = 0; $i < $count; $i++) {
    $text .= $sep if $i;
    $text .= ReadingsVal('gds','a_'.$i.'_headline','')
  }
  return $text;
}

sub gdsHeadlines($;$) {
  return "gdsHeadlines() is deprecated. Please use gdsAlertsHeadlines()"; 
}

sub setHelp(){
	return	"Use one of the following commands:\n".
			sepLine(35)."\n".
			"set <name> clear alerts|all\n".
			"set <name> conditions <stationName>\n".
			"set <name> forecasts <regionName>/<stationName>\n".
			"set <name> help\n".
			"set <name> rereadcfg\n".
			"set <name> update\n";
}

sub getHelp(){
	return	"Use one of the following commands:\n".
			sepLine(35)."\n".
			"get <name> alerts <region>\n".
			"get <name> conditions <stationName>\n".
			"get <name> forecasts <regionName>\n".
			"get <name> help\n".
			"get <name> list capstations|stations|data\n".
			"get <name> rereadcfg\n".
			"get <name> warnings <region>\n";
}

sub sepLine($;$) {
	my ($len,$c) = @_;
    $c //= '-';
	my ($output, $i);
	for ($i=0; $i<$len; $i++) { $output .= $c; }
	return $output;
}

sub _readDir($) {
   my ($destinationDirectory) = @_;
   eval { opendir(DIR,$destinationDirectory) or warn "$!"; };
   if ($@) {
      Log3(undef,1,'GDS: file system error '.$@);
      return ("");
   }
   my @files = readdir(DIR); 
   close(DIR); 
   return @files;
}

sub retrieveText($$$) {
	my ($hash, $fileName, $separator) = @_;
	my $name = $hash->{NAME};
	my ($err,@a);
	$fileName = $tempDir.$name."_$fileName";
	($err,@a) = FileRead({FileName=>$fileName,ForceType=>"file" });
	return "GDS error reading $fileName" if($err);
	@a = map (latin1ToUtf8($_), @a);
	return join($separator, @a);
}

sub gds_calctz($@) {
	my ($nt,@lt) = @_;
	my $off = $lt[2]*3600+$lt[1]*60+$lt[0];
	$off = 12*3600-$off;
	$nt += $off;  # This is noon, localtime
	my @gt = gmtime($nt);
	return (12-$gt[2]);
}

###################################################################################################
#
#	Data retrieval (internal)

sub getConditions($$@){
	my ($hash, $prefix, @a) = @_;
	my $name		= $hash->{NAME};
	(my $myStation	= utf8ToLatin1($a[2])) =~ s/_/ /g; # replace underscore in stationName by space

	my $searchLen	= length($myStation);
	return unless $searchLen;
	
	my ($line, $item, %pos, %alignment, %wx, %cread, $k, $v);

    foreach my $l (@allConditionsData) {
        $line = $l;                 # save line for further use
 		if ($l =~ /Station/) {		# Header line... find out data positions
 			@a = split(/\s+/, $l);
 			foreach $item (@a) {
 				$pos{$item} = index($line, $item);
 			}
 		}
 		if (index(substr(lc($line),0,$searchLen), substr(lc($myStation),0,$searchLen)) != -1) { last; }
    }	

	%alignment = ("Station" => "l", "H\xF6he" => "r", "Luftd." => "r", "TT" => "r", "Tn12" => "r", "Tx12" => "r", 
	"Tmin" => "r", "Tmax" => "r", "Tg24" => "r", "Tn24" => "r", "Tm24" => "r", "Tx24" => "r", "SSS24" => "r", "SGLB24" => "r", 
	"RR1" => "r", "RR12" => "r", "RR24" => "r", "SSS" => "r", "DD" => "r", "FF" => "r", "FX" => "r", "Wetter/Wolken" => "l", "B\xF6en" => "l");
	
	foreach $item (@a) {
		Log3($hash, 4, "conditions item: $item");
		$wx{$item} = &_readItem($line, $pos{$item}, $alignment{$item}, $item);
	}

	%cread = ();
	$cread{"_dataSource"} = "Quelle: Deutscher Wetterdienst";

	if(length($wx{"Station"})){
		$cread{$prefix."_stationName"}	= utf8ToLatin1($wx{"Station"});
		$cread{$prefix."_altitude"}		= $wx{"H\xF6he"};
		$cread{$prefix."_pressure-nn"}	= $wx{"Luftd."};
		$cread{$prefix."_temperature"}	= $wx{"TT"};
		$cread{$prefix."_tMinAir12"}	= $wx{"Tn12"};
		$cread{$prefix."_tMaxAir12"}	= $wx{"Tx12"};
		$cread{$prefix."_tMinGrnd24"}	= $wx{"Tg24"};
		$cread{$prefix."_tMinAir24"}	= $wx{"Tn24"};
		$cread{$prefix."_tAvgAir24"}	= $wx{"Tm24"};
		$cread{$prefix."_tMaxAir24"}	= $wx{"Tx24"};
		$cread{$prefix."_tempMin"}		= $wx{"Tmin"};
		$cread{$prefix."_tempMax"}		= $wx{"Tmax"};
		$cread{$prefix."_rain1h"}		= $wx{"RR1"};
		$cread{$prefix."_rain12h"}		= $wx{"RR12"};
		$cread{$prefix."_rain24h"}		= $wx{"RR24"};
		$cread{$prefix."_snow"}			= $wx{"SSS"};
		$cread{$prefix."_sunshine"}		= $wx{"SSS24"};
		$cread{$prefix."_solar"}		= $wx{"SGLB24"};
		$cread{$prefix."_windDir"}		= $wx{"DD"};
		$cread{$prefix."_windSpeed"}	= $wx{"FF"};
		$cread{$prefix."_windPeak"}		= $wx{"FX"};
		$cread{$prefix."_weather"}		= utf8ToLatin1($wx{"Wetter\/Wolken"});
		$cread{$prefix."_windGust"}		= $wx{"B\xF6en"};
	} else {
		$cread{$prefix."_stationName"}	= "unknown: $myStation";
	}

	readingsBeginUpdate($hash);
	while (($k, $v) = each %cread) {
		# skip update if no valid data is available
        unless(defined($v))      {delete($defs{$name}{READINGS}{$k}); next;}
		if($v =~ m/^--/)         {delete($defs{$name}{READINGS}{$k}); next;};
        unless(length(trim($v))) {delete($defs{$name}{READINGS}{$k}); next;};
		readingsBulkUpdate($hash, $k, latin1ToUtf8($v)); 
	}
	readingsEndUpdate($hash, 1);

	return ;
}
sub _readItem {
	my ($line, $pos, $align, $item)  = @_;
	my $x;
	
	if ($align eq "l") {
		$x = substr($line, $pos);
		$x =~ s/  .+$//g;	# after two spaces => next field
	}
	if ($align eq "r") {
		$pos += length($item);
		$x = substr($line, 0, $pos);
		$x =~ s/^.+  //g;	# remove all before the item
	}
	return $x;
}

sub getListCapStations($$){
	my ($hash, $command) = @_;
	my $name = $hash->{NAME};
	my (%capHash, $file, @columns, $key, $cList, $count);

	$file = $tempDir.'capstations.csv';
	return "GDS error: $file not found." unless(-e $file);

	# CSV öffnen und parsen
	my ($err,@a) = FileRead({FileName=>$file,ForceType=>"file" });
	return "GDS error reading $file" if($err);
	foreach my $l (@a) {
		next if (substr($l,0,1) eq '#');
		@columns = split(";",$l);
		$capHash{latin1ToUtf8($columns[4])} = $columns[0];
	}

	# Ausgabe sortieren und zusammenstellen
	foreach $key (sort keys %capHash) {
		$cList .= $capHash{$key}."\t".$key."\n";
	}
	return $cList;
}
sub retrieveListCapStations($){
	my ($hash) = @_;
	$hash->{file}{dir}		= "gds/help/";
	$hash->{file}{dwd}		= "legend_warnings_CAP_WarnCellsID.csv";
	$hash->{file}{target}	= $tempDir."capstations.csv";
	unless(-e $hash->{file}{target}) {
		retrieveData($hash,'FILE');
	} else {
		# read capstationslist once a day
		my $alter = time() - (stat($hash->{file}{target}))[9];
		retrieveData($hash,'FILE') if ($alter > 86400);
	}
}

sub decodeCAPData($$$){
	my ($hash, $datensatz, $anum) = @_;
	my $name		= $hash->{NAME};
	my $info		= 9999; # to be deleted
	my $alert		= int($datensatz/100);
	my $area		= $datensatz-$alert*100;

	my (%readings, @dummy, $i, $k, $n, $v, $t);

	my $gdsAll		= AttrVal($name,"gdsAll", 0);
	my $gdsDebug	= AttrVal($name,"gdsDebug", 0);
	my $gdsLong		= AttrVal($name,"gdsLong", 0);
	my $gdsPolygon	= AttrVal($name,"gdsPolygon", 0);

	Log3($name, 4, "GDS $name: Decoding CAP record #".$datensatz);

# topLevel informations
	if($gdsAll || $gdsDebug) {
		@dummy = split(/\./, $alertsXml->{alert}[$alert]{identifier});
		$readings{"a_".$anum."_identifier"}		= $alertsXml->{alert}[$alert]{identifier};
		$readings{"a_".$anum."_idPublisher"}	= $dummy[5];
		$readings{"a_".$anum."_idSysten"}		= $dummy[6];
		$readings{"a_".$anum."_idTimeStamp"}	= $dummy[7];
		$readings{"a_".$anum."_idIndex"}		= $dummy[8];
	}
	
	$readings{"a_".$anum."_sent"}			= $alertsXml->{alert}[$alert]{sent};
	$readings{"a_".$anum."_status"}			= $alertsXml->{alert}[$alert]{status};
	$readings{"a_".$anum."_msgType"}		= $alertsXml->{alert}[$alert]{msgType};

# infoSet informations
	if($gdsAll || $gdsDebug) {
		$readings{"a_".$anum."_language"}	= $alertsXml->{alert}[$alert]{info}{language};
		$readings{"a_".$anum."_urgency"}	= $alertsXml->{alert}[$alert]{info}{urgency};
		$readings{"a_".$anum."_severity"}	= $alertsXml->{alert}[$alert]{info}{severity};
		$readings{"a_".$anum."_certainty"}	= $alertsXml->{alert}[$alert]{info}{certainty};
	}
	
	$readings{"a_".$anum."_category"}		= $alertsXml->{alert}[$alert]{info}{category};
	$readings{"a_".$anum."_event"}			= $alertsXml->{alert}[$alert]{info}{event};
	$readings{"a_".$anum."_responseType"}	= $alertsXml->{alert}[$alert]{info}{responseType};

# eventCode informations
# loop through array
	$i = 0;
	while(1){
		($n, $v) = (undef, undef);
		$n = $alertsXml->{alert}[$alert]{info}{eventCode}[$i]{valueName};
		if(!$n) {last;}
		$n = "a_".$anum."_eventCode_".$n;
		$v = $alertsXml->{alert}[$alert]{info}{eventCode}[$i]{value};
		$readings{$n} .= $v." " if($v);
		$i++;
	}

# time/validity informations
	$readings{"a_".$anum."_effective"}		= $alertsXml->{alert}[$alert]{info}{effective} if($gdsAll);
	$readings{"a_".$anum."_onset"}			= $alertsXml->{alert}[$alert]{info}{onset};
	$readings{"a_".$anum."_expires"}		= $alertsXml->{alert}[$alert]{info}{expires};
	$readings{"a_".$anum."_valid"}			= _checkCAPValid($readings{"a_".$anum."_onset"},$readings{"a_".$anum."_expires"});
	$readings{"a_".$anum."_onset_local"}	= _capTrans($readings{"a_".$anum."_onset"});
	$readings{"a_".$anum."_expires_local"}	= _capTrans($readings{"a_".$anum."_expires"}) 
	         if(defined($alertsXml->{alert}[$alert]{info}{expires}));
	$readings{"a_".$anum."_sent_local"}		= _capTrans($readings{"a_".$anum."_sent"});

	$readings{a_valid} = ReadingsVal($name,'a_valid',0) || $readings{"a_".$anum."_valid"};

# text informations
	$readings{"a_".$anum."_headline"}		= $alertsXml->{alert}[$alert]{info}{headline};
	$readings{"a_".$anum."_description"}	= $alertsXml->{alert}[$alert]{info}{description} if($gdsAll || $gdsLong);
	$readings{"a_".$anum."_instruction"}	= $alertsXml->{alert}[$alert]{info}{instruction}
			if($readings{"a_".$anum."_responseType"} eq "Prepare" & ($gdsAll || $gdsLong));

# area informations
	$readings{"a_".$anum."_areaDesc"} 		=  $alertsXml->{alert}[$alert]{info}{area}[$area]{areaDesc};
	$readings{"a_".$anum."_areaPolygon"}	=  $alertsXml->{alert}[$alert]{info}{area}[$area]{polygon} if($gdsAll || $gdsPolygon);

# area geocode informations
# loop through array
	$i = 0;
	while(1){
		($n, $v) = (undef, undef);
		$n = $alertsXml->{alert}[$alert]{info}{area}[$area]{geocode}[$i]{valueName};
		if(!$n) {last;}
		$n = "a_".$anum."_geoCode_".$n;
		$v = $alertsXml->{alert}[$alert]{info}{area}[$area]{geocode}[$i]{value};
		$readings{$n} .= $v." " if($v);
		$i++;
	}

	$readings{"a_".$anum."_altitude"}		= $alertsXml->{alert}[$alert]{info}{area}[$area]{altitude}		if($gdsAll);
	$readings{"a_".$anum."_ceiling"}		= $alertsXml->{alert}[$alert]{info}{area}[$area]{ceiling}		if($gdsAll);

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "_dataSource", "Quelle: Deutscher Wetterdienst");
	while(($k, $v) = each %readings){
		# skip update if no valid data is available
        next unless(defined($v));
		readingsBulkUpdate($hash, $k, latin1ToUtf8($v)); 
	}

	# convert color value to hex
	my $r = ReadingsVal($name, 'a_'.$anum.'_eventCode_AREA_COLOR', '');
	if(length($r)) {
		my $v = sprintf( "%02x%02x%02x", split(" ", $r));
		readingsBulkUpdate($hash, 'a_'.$anum.'_eventCode_AREA_COLOR_hex', $v);
	}
	
	readingsEndUpdate($hash, 1);

	return;
}
sub _checkCAPValid($$;$$){
	my ($onset,$expires,$t,$tmax) = @_;
	my $valid = 0;
  
	$t = time() if (!defined($t));
	my $offset = gds_calctz($t,localtime($t))*3600; 
	$t -= $offset;
	$tmax -= $offset if (defined($tmax));

	$onset =~ s/T/ /;
	$onset =~ s/\+/ \+/;
	$onset = time_str2num($onset);

	$expires =~ s/T/ /;
	$expires =~ s/\+/ \+/;
	$expires = time_str2num($expires);

	if (defined($tmax)) {  
		$valid = 1 if($tmax ge $onset && $t lt $expires);
	} else {
		$valid = 1 if($onset lt $t && $expires gt $t);
	}
	return $valid;
}
sub _capTrans($) {
	my ($t) = @_;
	my $valid = 0;
	my $offset = gds_calctz(time,localtime(time))*3600; # used from 99_SUNRISE_EL
	$t =~ s/T/ /;
	$t =~ s/\+/ \+/;
	$t = time_str2num($t);
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($t+$offset);
	$mon  += 1;
	$year += 1900;
	$t = sprintf "%02s.%02s.%02s %02s:%02s:%02s", $mday, $mon, $year, $hour, $min, $sec;
	return $t;
}

###################################################################################################
#
#	nonblocking data retrieval

sub retrieveData($$){
	my ($hash,$req) = @_;
	$req = uc($req);
	if ($req eq "FORECAST") {
		my $busyTag = "GDS_".$req."_BUSY";
		if (defined($hash->{$busyTag})) {
			return;
		} else {
			$hash->{$busyTag} = localtime(time());
		}
	}
	my $tag = "GDS_".$req."_READ";
	delete $hash->{$tag};
	$tag = "GDS_".$req."_ABORTED";
	delete $hash->{$tag};
	BlockingCall("_retrieve$req",$hash,"_finished$req",60,"_aborted$req",$hash);
}

#	any file
sub _retrieveFILE {
	my ($hash)		= shift;
	my $name		= $hash->{NAME};
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	my $host		= $hash->{helper}{URL};
	my $proxyName	= AttrVal($name, "gdsProxyName", "");
	my $proxyType	= AttrVal($name, "gdsProxyType", "");
	my $passive		= AttrVal($name, "gdsPassiveFtp", 1);

	my $dir			= $hash->{file}{dir};
	my $dwd			= $hash->{file}{dwd};
	my $target		= $hash->{file}{target};

	my $ret = "";

	eval {
		my $ftp = Net::FTP->new(	$host,
									Debug        => 0,
									Timeout      => 10,
									Passive      => $passive,
									FirewallType => $proxyType,
									Firewall     => $proxyName);
		if(defined($ftp)){
			Log3($name, 4, "GDS $name: ftp connection established.");
			$ftp->login($user, $pass);
			$ftp->binary;
			$ftp->cwd($dir);
			my @files = $ftp->ls($dwd);
			if(@files) {
				@files = sort(@files);
				$dwd   = $files[-1];
 				Log3($name, 4, "GDS $name: file found.");
				Log3($name, 4, "GDS $name: retrieving $dwd");
				if(defined($target)) {
					$ftp->get($dwd,$target);
					my $s = -s $target;
        	        Log3($name, 4, "GDS: ftp transferred $s bytes");
				} else {
					my ($file_content,$file_handle);
					open($file_handle, '>', \$file_content);
					$ftp->get($dwd,$file_handle);
					$file_content = latin1ToUtf8($file_content);
					$file_content =~ s/\r\n/\$/g;
					$ret = $file_content;
				}
			}
			$ftp->quit;
		}
	};
	return "$name;;;$dwd;;;$ret";
}
sub _finishedFILE {
	my ($name,$file,$ret) = split(/;;;/,shift); #@_;
	my $hash = $defs{$name};
	DoTrigger($name,"REREADFILE $file",1);
}
sub _abortedFILE {
	my ($hash) = shift;
}

#	Conditions
sub _retrieveCONDITIONS {
	my ($hash)		= shift;
	my $name		= $hash->{NAME};
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	my $host		= $hash->{helper}{URL};
	my $proxyName	= AttrVal($name, "gdsProxyName", "");
	my $proxyType	= AttrVal($name, "gdsProxyType", "");
	my $passive		= AttrVal($name, "gdsPassiveFtp", 1);
	my $dir			= "gds/specials/observations/tables/germany/";
	my $ret;

	eval {
		my $ftp = Net::FTP->new(	$host,
									Debug        => 0,
									Timeout      => 10,
									Passive      => $passive,
									FirewallType => $proxyType,
									Firewall     => $proxyName);
		if(defined($ftp)){
			Log3($name, 4, "GDS $name: ftp connection established.");
			$ftp->login($user, $pass);
			$ftp->binary;
			$ftp->cwd("$dir");
			my @files = $ftp->ls();
			if(@files) {
 				Log3($name, 4, "GDS $name: filelist found.");
 				@files			= sort(@files);
				my $datafile	= $files[-1];
				Log3($name, 5, "GDS $name: retrieving $datafile");
				my ($file_content,$file_handle);
				open($file_handle, '>', \$file_content);
				$ftp->get($datafile,$file_handle);
#				$file_content = latin1ToUtf8($file_content);
				$file_content //= "";
				$file_content =~ s/\r\n/\$/g;
				$ret = "$datafile;;;$file_content";
			}
			$ftp->quit;
		}
	};
	return "$name;;;$ret" if $ret;
	return "$name";
}
sub _finishedCONDITIONS {
	my ($name,$file_name,$file_content) = split(/;;;/,shift);
	my $hash = $defs{$name};
	return _abortedCONDITIONS($hash) unless $file_content;
	@allConditionsData = split(/\$/,$file_content);

	# fill dropdown list
    my @a = map (trim(substr($_,0,19)), @allConditionsData);    
	@a = map (latin1ToUtf8($_), @a);
	# delete header lines 
	splice(@a, 0, 6);
	# delete legend 
	splice(@a, __first_index("Höhe",@a)-1);
	@a = sort(@a);
	$sList = join(",", @a);
	$sList =~ s/\s+,/,/g; # replace multiple spaces followed by comma with comma
	$sList =~ s/\s/_/g;   # replace spaces in stationName with underscore for list in frontende
	readingsSingleUpdate($hash, "_dF_conditions",$file_name,0) if(AttrVal($name, "gdsDebug", 0));

	$hash->{GDS_CONDITIONS_READ}	= int(time());
	my $cf = AttrVal($name,'gdsSetCond',0);
#	GDS_GetUpdate($hash,1) if $cf; 
	my @b;
	push @b, undef;
	push @b, undef;
	push @b, $cf;
	getConditions($hash, "c", @b);
	DoTrigger($name,"REREADCONDITIONS",1);
}
sub __first_index ($@) {
    my ($reg,@a) = @_;
    my $i        = 0;
    foreach my $l (@a) {
        return $i if ($l =~ m/$reg/);
        $i++;
    }
    return -1;
}
sub _abortedCONDITIONS {
	my ($hash) = shift;
	delete $hash->{GDS_CONDITIONS_READ};
	$hash->{GDS_CONDITIONS_ABORTED} = localtime(time());
}


# 	CapData
sub _retrieveCAPDATA {
	my ($hash)		= shift;
	my $name		= $hash->{NAME};
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	my $host		= $hash->{helper}{URL};
	my $proxyName	= AttrVal($name, "gdsProxyName", "");
	my $proxyType	= AttrVal($name, "gdsProxyType", "");
	my $passive		= AttrVal($name, "gdsPassiveFtp", 1);
	my $dir 		= "gds/specials/alerts/cap/GER/status/";
	my $dwd			= "Z_CAP*";

	my $datafile	= "";
	my $targetDir	= $tempDir.$name."_alerts.dir";
	my $targetFile	= $tempDir.$name."_alerts.zip";
	mkdir $targetDir unless -d $targetDir;

	# delete archive file
	unlink $targetFile;

	eval {
		my $ftp = Net::FTP->new(	$host,
									Debug        => 0,
									Timeout      => 10,
									Passive      => $passive,
									FirewallType => $proxyType,
									Firewall     => $proxyName);
		if(defined($ftp)){
			Log3($name, 4, "GDS $name: ftp connection established.");
			$ftp->login($user, $pass);
			$ftp->binary;
			$ftp->cwd("$dir");
			my @files = $ftp->ls($dwd);
			if(@files) {
 				Log3($name, 4, "GDS $name: filelist found.");
 				@files			= sort(@files);
				$datafile		= $files[-1];
				Log3($name, 5, "GDS $name: retrieving $datafile");
				$ftp->get($datafile,$targetFile);
				my $s = -s $targetFile;
                Log3($name, 5, "GDS: ftp transferred $s bytes");
			}
			$ftp->quit;
		}
	};

	
	# delete old files in directory
	if (-d $targetDir) {
		my @remove = _readDir($targetDir); 
		foreach my $f (@remove){
			next if -d $f;
			next if $targetFile =~ m/$f$/;
			Log3($name, 4, "GDS $name: deleting $targetDir/$f"); 
			unlink("$targetDir/$f"); 
		}
	}

	# unzip
	my $zip;
	eval {
		$Archive::Extract::PREFER_BIN	= 1;
		$Archive::Extract::WARN			= 0;
		$zip = Archive::Extract->new( archive => $targetFile, type => 'zip' );
		my $ok  = $zip->extract( to => $targetDir );
		Log3($name, 5, "GDS $name: error ".$zip->error()) unless $ok;
	};

#	my $zip;
#	eval {
#		$zip = Archive::Zip->new($targetFile);
#		foreach my $member ($zip->members()) {
#			my $fileName = $member->fileName();
#			$zip->extractMember($member,$targetDir."/".$fileName) == AZ_OK || Debug "unzip error: $member";
#		}
#	};

	# merge
    my ($countInfo,$cF)		= _mergeCapFile($hash);
	my ($aList,$cellData)	= _buildCAPList($hash,$countInfo,$cF);

	unlink $targetFile unless AttrVal($name,'gdsDebug',0); 

	return "$name;;;$datafile;;;$aList;;;$cF;;;$cellData";
}
sub _finishedCAPDATA {
	my ($name,$datafile,$aL,$capFile,$cellData) = split(/;;;/,shift);
	my $hash = $defs{$name};
	$aList = $aL;
	my @h = split(/;;/,$cellData);
	foreach(@h) {
		my ($n,$city,$cell)		= split(/:/,$_);
		$capCityHash{$city}		= $n;
		$capCellHash{"$cell$n"}	= $n;
	}

	my $xml		= new XML::Simple;
	eval {
	$alertsXml	= $xml->XMLin($capFile, KeyAttr => {}, ForceArray => [ 'alert', 'eventCode', 'area', 'geocode' ]);
	};
    if ($@) {
       Log3($name,1,'GDS: error analyzing alerts XML:'.$@);
       return;
    }
	readingsSingleUpdate($hash, "_dF_alerts",$datafile,0) if(AttrVal($name, "gdsDebug", 0));
	$hash->{GDS_CAPDATA_READ} = int(time());
	DoTrigger($name,"REREADALERTS",1);
}
sub _abortedCAPDATA {
	my ($hash) = shift;
	delete $hash->{GDS_CAPDATA_READ};
	$hash->{GDS_CAPDATA_ABORTED} = localtime(time());
}
sub _mergeCapFile($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    my $destinationDirectory = $tempDir.$name."_alerts.dir";
    my @capFiles = _readDir($destinationDirectory);

    my @alertsArray;
    my $xmlHeader   = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>';
    push (@alertsArray,$xmlHeader);
    push (@alertsArray,"<gds>");
    my $countInfo   = 0;
	
    foreach my $cF (@capFiles){
       # merge all capFiles
       $cF = $destinationDirectory."/".$cF;
       next if -d $cF;
       next unless -s $cF;
       next unless $cF =~ m/\.xml$/; # read xml files only!
       Log3($name, 4, "GDS $name: analyzing $cF"); 

       my ($err,@a) = FileRead({FileName=>$cF,ForceType=>"file" });
       foreach my $l (@a) {
          next unless length($l);
          next if($l =~ m/^\<\?xml version.*/);
          $l = "<alert>"  if($l =~ m/^\<alert.*/);
#          next if($l =~ m/^\<alert.*/);
#          next if($l =~ m/^\<\/alert.*/);
          next if($l =~ m/^\<sender\>.*/);
          $countInfo++ if($l =~ m/^\<info\>/);
          push (@alertsArray,$l);
       }
    }
    push (@alertsArray,"</gds>");

    # write the big XML file if needed
    if(AttrVal($name,"gdsDebug", 0)) {
       my $cF = $destinationDirectory."/gds_alerts";
       unlink $cF if -e $cF;
       FileWrite({ FileName=>$cF,ForceType=>"file" },@alertsArray);
    }

    my $xmlContent = join('',@alertsArray);
    return ($countInfo,$xmlContent);
}
sub _buildCAPList($$$){
	my ($hash,$countInfo,$cF) = @_;
	my $name = $hash->{NAME};

	$alertsXml		= undef;

	my $xml			= new XML::Simple;
	my $area		= 0;
	my $record		= 0;
	my $n			= 0;
	my ($capCity, $capCell, $capEvent, $capEvt, @a);
    my $destinationDirectory = $tempDir.$name."_alerts.dir";
    
    # make XML array and analyze data
    eval	{	
	  $alertsXml = $xml->XMLin($cF, KeyAttr => {}, ForceArray => [ 'alert', 'eventCode', 'area', 'geocode' ]);
    };
    if ($@) {
       Log3($name,1,'GDS: error analyzing alerts XML:'.$@);
       return (undef,undef);
    }

    # analyze entries based on info and area array
    # array elements are determined by $info and $area
    #

	my $cellData = '';

    for (my $info=0; $info<=$countInfo;$info++) {
       $area = 0;
       while(1){
          $capCity  = $alertsXml->{alert}[$info]{info}{area}[$area]{areaDesc};
          $capEvent = $alertsXml->{alert}[$info]{info}{event};
          last unless $capCity;
          $capCell  = __findCAPWarnCellId($info, $area);
          $n        = 100*$info+$area;
          $capCity  = latin1ToUtf8($capCity.' '.$capEvent);
          push @a, $capCity;
          $capCity =~ s/\s/_/g;
          $cellData .= "$n:$capCity:$capCell$n;;";
          $area++;
          $record++;
          $capCity = undef;
       }
    }

	@a = sort(@a);
    $aList = undef;
	$aList = join(",", @a);
	$aList =~ s/\s/_/g;
	$aList = "No_alerts_published!" if !$record;

    return($aList,$cellData);
}
sub __findCAPWarnCellId($$){
	my ($info, $area) = @_;
	my $i = 0;
	while($i < 100){
		if($alertsXml->{alert}[$info]{info}{area}[$area]{geocode}[$i]{valueName} eq "WARNCELLID"){
			return $alertsXml->{alert}[$info]{info}{area}[$area]{geocode}[$i]{value};
			last;
		}
		$i++; # emergency exit :)
	}
}

#	ForecastData
sub _retrieveFORECAST {
	my ($hash)		= shift;
	my $name		= $hash->{NAME};
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	my $host		= $hash->{helper}{URL};
	my $proxyName	= AttrVal($name, "gdsProxyName", "");
	my $proxyType	= AttrVal($name, "gdsProxyType", "");
	my $passive		= AttrVal($name, "gdsPassiveFtp", 1);
	my $useFritz	= AttrVal($name, "gdsUseFritzkotz", 0);
	my $dir         = "gds/specials/forecasts/tables/germany/";

    my $ret = "";

	eval {
		my $ftp = Net::FTP->new(	$host,
									Debug        => 0,
									Timeout      => 10,
									Passive      => $passive,
									FirewallType => $proxyType,
									Firewall     => $proxyName);
		if(defined($ftp)){
			Log3($name, 4, "GDS $name: ftp connection established.");
			$ftp->login($user, $pass);
			$ftp->binary;
			$ftp->cwd("$dir");
			my @files = $ftp->ls();
			if(@files) {
 				Log3($name, 4, "GDS $name: filelist found.");
 				@files = sort(@files);
				$fcmapList = undef;
 				map ( $fcmapList .= (split(/Daten_/,$_,2))[1].",", @files );
				my $count = 0;
				foreach my $file (@files) {
					my ($file_content,$file_handle);
					open($file_handle, '>', \$file_content);
					$ftp->get($file,$file_handle);
					next unless (length($file_content));
					$file_content = latin1ToUtf8($file_content);
					$file_content =~ s/\r\n/\$/g;
					$ret .= "$file:$file_content;";
					$count++;
					Log3 ($name, 5, "GDS $name retrieved forecast $file");
				}
			}
			$ftp->quit;
		}
	};

	return $name.";;;".$ret;
}
sub _finishedFORECAST {
	my ($name,$ret) = split(/;;;/,shift); #@_;
	my $hash = $defs{$name};
	my @a = split(/;/,$ret);
	%allForecastData = ();
	foreach my $l (@a) {
		my ($fn,$fc) = split(/\:/,$l);
		$allForecastData{$fn} = $fc;
	}
	$hash->{GDS_FORECAST_READ} = int(time());
	DoTrigger($name,"REREADFORECAST",1);
	getListForecastStations($hash);
	my $sf = AttrVal($name,'gdsSetForecast',0);
#	GDS_GetUpdate($hash,1) if $sf; 
	my @b;
	push @b, undef;
	push @b, undef;
	push @b, $sf;
	retrieveForecasts($hash, "fc", @b);    
	delete $hash->{GDS_FORECAST_BUSY};
}
sub _abortedFORECAST {
	my ($hash) = shift;
	delete $hash->{GDS_FORECAST_READ};
	$hash->{GDS_FORECAST_ABORTED} = localtime(time());
	delete $hash->{GDS_FORECAST_BUSY};
}

###################################################################################################
#
#	forecast retrieval - provided by jensb

sub retrieveForecasts($$@) {
	#
	# parameter: hash, prefix, region/station, forecast index (0 .. 10)
	#
	my ($hash, $prefix, @a) = @_;
	my $name		= $hash->{NAME};

	# extract region and station name
	return unless defined($a[2]);

	my ($area,$station) = split(/\//,$a[2]);
	return unless $station;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();  
	my ($dataFile, $found, $line, %fread, $k, $v, $data); 
	$area			=  utf8ToLatin1($area);
	$station		=~ s/_/ /g; # replace underscore in station name by space
	my $searchLen	=  length($station);  
	%fread		= ();

	# define fetch scope (all forecasts or single forecast)
	my $fc = 0;
	my $fcStep = 1;
	if (defined($a[3]) && $a[3] > 0) {
	    # single forecast
	    $fc = $a[3] - 1;
	    $fcStep = 10;
	}

	# fetch up to 10 forecasts for today and the next 3 days
	do {
		my $day;
		my $early;
		if ($fc < 4) {
			$day = 0;
			$early = 0;
		} else {
			$day = int(($fc - 2)/2);
			$early = $fc%2 == 0;
		} 
		my $areaAndTime = $area;
		if ($day == 1) {
			$areaAndTime .= "_morgen";
		} elsif ($day == 2) {
			$areaAndTime .= "_uebermorgen";
		} elsif ($day == 3) {
			$areaAndTime .= "_Tag4";
		}
		my $timeLabel = undef;
		my $tempLabel = '_tAvgAir';
		my $copyDay = undef;
		my $copyTimeLabel = undef;
		if ($day == 0) {
			if ($fc == 0) {
				$areaAndTime .= "_frueh";  # .. 6 h
				$timeLabel = '06';
				$tempLabel ='_tMinAir';
				$copyDay = 1;
				$copyTimeLabel = '12';
			} elsif ($fc == 1) {
				$areaAndTime .= "_mittag"; # .. 12 h
				$timeLabel = '12';
				$tempLabel .= $timeLabel;
			} elsif ($fc == 2) {
				$areaAndTime .= "_spaet";  # .. 18 h
				$timeLabel = '18';
				$tempLabel ='_tMaxAir';
				$copyDay = 1;
				$copyTimeLabel = '24';
			} elsif ($fc == 3) {
				$areaAndTime .= "_nacht";  # .. 24 h
				$timeLabel = '24';
				$tempLabel .= $timeLabel;
			}
		} else {
			if ($early) {    
				$areaAndTime .= "_frueh";  # .. 12 h
				$timeLabel = '12';
				$tempLabel ='_tMinAir';
				if ($day < 3) {
					$copyDay = $day + 1;
					$copyTimeLabel = '12';
				}
			} else {
				$areaAndTime .= "_spaet";  # .. 24 h
				$timeLabel .= '24';
				$tempLabel ='_tMaxAir';
				if ($day < 3) {
					$copyDay = $day + 1;
					$copyTimeLabel = '24';
				}
			}
		} # if ($day == 0) {

		# define forecast date (based on "now" + day)   
		my $fcEpoch = time() + $day*86400;
		if ($fc == 3) {
			# night continues at next day
			$fcEpoch += 86400;
		}
		my ($fcSec,$fcMin,$fcHour,$fcMday,$fcMon,$fcYear,$fcWday,$fcYday,$fcIsdst) = localtime($fcEpoch);
		my $fcWeekday = $weekdays[$fcWday];
		my $fcDate = sprintf("%02d.%02d.%04d", $fcMday, 1+$fcMon, 1900+$fcYear);
		my $fcDateFound = 0;

		# retrieve from hash
		my $noDataFound = 1;
		$data = undef;
		my $hashSize = keys%allForecastData; # checking size of hash seems to make all entries "visible" in loop
		while(($k, $v) = each %allForecastData){
			if ($k eq "Daten_$areaAndTime") {
				$data = $v;
				last;
			};
		}

		if (defined($data) && $data) {
			my @data = split(/\$/,$data);

			foreach my $l (@data) {
				if (index($l, $fcDate) > 0) { 
					# forecast date found
					$fcDateFound = 1; 
				} # if
				if (index(substr(lc($l),0,$searchLen), substr(lc($station),0,$searchLen)) != -1) { 
					# station found
					$line = $l;
					last; 
				} # if
			} # foreach

			# parse file
			if ($fcDateFound && length($line) > 0) {
				if (index(substr(lc($line),0,$searchLen), substr(lc($station),0,$searchLen)) != -1) {
					# station found but there is no header line and column width varies:
					$line =~ s/---/   ---/g;	# column distance may drop to zero between station name 
												# and invalid temp "---" -> prepend 3 spaces
					$line =~ s/   /;/g;			# now min. column distance is 3 spaces -> convert to semicolon 
					$line =~ s/;+/;/g;			# replace multiple consecutive semicolons by one semicolon
					my @b = split(';', $line);	# split columns by semicolon
					$b[0] =~ s/^\s+|\s+$//g;	# trim station name
					$b[1] =~ s/^\s+|\s+$//g;	# trim temperature
					$b[2] =~ s/^\s+|\s+$//g;	# trim weather   
					if (scalar(@b) > 3) {
						$b[3] =~ s/^\s+|\s+$//g; # trim wind gust
					} else {
						$b[3] = ' ';
					}
					$fread{$prefix."_stationName"} = $area.'/'.$b[0];
					$fread{$prefix.$day.$tempLabel}  = $b[1];
					$fread{$prefix.$day."_weather".$timeLabel} = $b[2];
					$fread{$prefix.$day."_windGust".$timeLabel} = $b[3];
					if ($fc != 3) {
						$fread{$prefix.$day."_weekday"} = $fcWeekday;
					}
					$noDataFound = 0;
				} else {
					# station not found, abort
					$fread{$prefix."_stationName"} = "unknown: $station in $area";
					last;
				}
			}
		} # unless

		if ($noDataFound) {
			# forecast period already passed or no data available 			
			$fread{$prefix.$day.$tempLabel} = "---";
			$fread{$prefix.$day."_weather".$timeLabel} = "---";      
			$fread{$prefix.$day."_windGust".$timeLabel} = "---";      
			if ($fc != 3) {
				$fread{$prefix.$day."_weekday"} = $fcWeekday;
			}
		}

		# day change preset by rotation
		my $ltime = ReadingsTimestamp($name, $prefix.$day."_weather".$timeLabel, undef);
		my ($lsec,$lmin,$lhour,$lmday,$lmon,$lyear,$lwday,$lyday,$lisdst);
		if (defined($ltime)) {
			($lsec,$lmin,$lhour,$lmday,$lmon,$lyear,$lwday,$lyday,$lisdst) = localtime(time_str2num($ltime));
		}
		if (!defined($ltime) || $mday != $lmday) {
			# day has changed, rotate old forecast forward by one day because new forecast is not immediately available
			my $temp = $fread{$prefix.$day.$tempLabel};
			if (defined($temp) && substr($temp, 0, 2) eq '--') {
				if (defined($copyTimeLabel)) {
					$fread{$prefix.$day.$tempLabel} = ReadingsVal($name, $prefix.$copyDay.$tempLabel, '---');
				} else {
					# today noon/night and 3rd day is undefined
					$fread{$prefix.$day.$tempLabel} = ' ';
				}
			}
			my $weather = $fread{$prefix.$day."_weather".$timeLabel};
			if (defined($weather) && substr($weather, 0, 2) eq '--') {
				if (defined($copyTimeLabel)) {
					$fread{$prefix.$day."_weather".$timeLabel} = 
						ReadingsVal($name, $prefix.$copyDay."_weather".$copyTimeLabel, '---');
			} else {
				# today noon/night and 3rd day is undefined
				$fread{$prefix.$day."_weather".$timeLabel} = ' ';
			}
		}
		my $windGust = $fread{$prefix.$day."_windGust".$timeLabel};
		if (defined($windGust) && substr($windGust, 0, 2) eq '--') {
			if (defined($copyTimeLabel)) {
				$fread{$prefix.$day."_windGust".$timeLabel} = 
					ReadingsVal($name, $prefix.$copyDay."_windGust".$copyTimeLabel, '---');
			} else {
				# today noon/night and 3rd day is undefined
				$fread{$prefix.$day."_windGust".$timeLabel} = ' ';
			}
		}
	}
	$fc += $fcStep;
	} while ($fc < 10);

	readingsBeginUpdate($hash);
	while (($k, $v) = each %fread) {
		# skip update if no valid data is available
        unless(defined($v))      {delete($defs{$name}{READINGS}{$k}); next;}
		if($v =~ m/^--/)        {delete($defs{$name}{READINGS}{$k}); next;};
        unless(length(trim($v))) {delete($defs{$name}{READINGS}{$k}); next;};
		readingsBulkUpdate($hash, $k, $v); 
	}
	readingsEndUpdate($hash, 1);
}

sub getListForecastStations($) {
	my ($hash)  = @_;
	my $name    = $hash->{NAME};
	my @regions = keys(%rmapList);
	my (@a,$data,$k,$v);

	eval {
		foreach my $region (@regions) {
			$data = "";
			my $areaAndTime = 'Daten_'.$region.'_morgen_spaet';
			while(($k, $v) = each %allForecastData){
				if ($k eq $areaAndTime) {
					$data = $v;
					last;
				};
			}
			next unless $data;
			my @data = split(/\$/,$data);
			splice(@data, 0,2);
			splice(@data,-2);
			map ( push(@a,"$region/".(split(/(\s|--)/,$_,2))[0]), @data );
		}
	};
	   
	Log3($name, 4, "GDS $name: forecast data not found") unless (@a);

	@a = sort(@a);
  	$fList = join(",", @a);
	$fList =~ s/\s+,/,/g; # replace multiple spaces followed by comma with comma
	$fList =~ s/\s/_/g;   # replace spaces in stationName with underscore for list in frontend
	return;
}


1;


# development documentation
=pod
###################################################################################################
#
#   ToDo
#
###################################################################################################
#
#	Changelog
#
###################################################################################################
#
#	2015-11-26	fixed		wrong region handling
#				added		gdsAlertsHeadlines()
#
#	2015-11-17	changed		decodeCAPData - fix wrong cumulation (first try)
#				fixed		minor bugs
#
#	2015-11-06	changed		character encoding in forecast readings (jensb)
#				fixed		problems after global rereadcfg
#				fixed		delete CAP-zipfile unless gdsDebug set
#
#	2015-11-01	changed		getListForecastStations: fixed inverted logging "data not found"
#				changed		GDS_GetUpdate, retrieveData, _finishedFORECAST, _abortedFORECAST: 
#							prevent multiple parallel processing
#				changed		retrieveForecasts: make available data in hash "visible" for processing
#
#	2015-10-31	public		new version released, SVN #9739
#
#	2015-10-30	public		RC6 published, SVN #9727
#				changed		use passive ftp per default
#
#	2015-10-27	changed		add own function gds_calcTz due to announced
#							changes in SUNRISE_EL
#
#	2015-10-26	changed		multiple instances are forbidden
#
#	2015-10-25	public		RC5 published, SVN #9663
#				changed		a lot of code cleanup
#
#	2015-10-24	public		RC3 published, SVN #9627
#
#	2015-10-13	changed		getListForecastStations()	completed
#				changed		retrieveForecasts()			completed
#				added		DoTrigger() according to reread
#
#	2015-10-12  changed		conditions		completed
#				changed		capstationlist	completed
#				changed		conditionsmap	completed
#				changed		forecastsmap	completed
#				changed		radarmap		completed
#				changed		warningsmap		completed
#				changed		warnings		completed
#				changed		get alerts		completed
#
#   2015-10-11 	changed		use Archive::Extract for unzip
#				changed		code cleanup
# 				changed		forecast nonblocking retrieval:
#								hash generation completed
#				changed		capstations nonblocking retrieval:
#								alertslist dropdown completed
#								datafile retrieval completed
#
#
#   ----------  public    RC2 published, SVN #9429
#
#   2015-10-11  renamed   99_gdsUtils.pm to GDSweblink.pm
#               changed   load GDSweblink.pm in eval() on module startup
#
#   2015-10-10  added     attribute gdsHideFile to hide "GDS File" Menu
#               added     optional parameter "host" in define() to override default hostname
#
#               changed   weblink generator           moved into 99_gdsUtils.pm
#               changed   perl module List::MoreUtils is no longer used
#               changed   perl module Text::CSV is no longer needed
#               changed   use binary mode for all ftp transfers to preven errors in images
#
#               fixed     handling for alert items msgType, sent, status
#               fixed     handling for alert messages without "expires" data
#
#               updated   commandref documentation
#
#   ----------  public    RC1 published, SVN #9416
#
#   2015-10-09  removed   createIndexFile()
#               added     forecast retrieval
#               added     weblink generator
#               added     more "set clear ..." commands
#               changed   lots and lots of code cleanup
#               feature   make retrieveFile() nonblocking
#
#
#   2015-10-08  changed   added mergeCapFile()
#                         code cleanup in buildCAPList()
#                         use system call "unzip" instead of Archive::Zip
#               added     NotifyFn for rereadcfg after INITIALIZED
#               improved  startup data retrieval
#               improved  attribute handling
#
#   ----------  public    first publication in ./contrib/55_GDS.2015 for testing
#
#   2015-10-07  changed   remove LWP - we will only use ftp for transfers
#               added     first solution for filemerge
#               added     reliable counter for XML analyzes instead of while(1) loops 
#               added     (implementation started) forecast retrieval by jensb
#               changed   make text file retrieval more generic
#
#   2015-10-06  removed   Coro Support
#               removed   $useFTP - always use http internally 
#               changed   use LWP::Parallel::UserAgent for nonblocking transfers
#               changed   use  Archive::ZIP for alert files transfer and unzip
#
#   2015-10-05  started   redesign for new data structures provided by DWD
#
#   ----------
#
#   2015-09-24  fixed   prevent fhem crash on empty conditions file
#
#   2015-04-07  fixed   a_X_valid calculation: use onset, too
#
#   2015-01-30  changed use own FWEXT instead of HTTPSRV
#
#	2015-01-03	added	multiple alerts handling
#
#	2014-10-15	added	attr disable
#
#	2014-05-23	added	set <name> clear alerts|all
#						fixed some typos in docu and help
#
#	2014-05-22	added	reading a_sent_local
#
#	2014-05-07	added	readings a_onset_local & a_expires_local
#
#	2014-02-26	added	attribute gdsPassiveFtp
#
#	2014-02-04	added	ShutdownFn
#				changed	FTP Timeout
#
#	2013-11-03	added	error handling for malformed XML files from GDS
#
#	2013-08-13	fixed	some minor bugs to prevent annoying console messages
#				added	support for fhem installtions running on windows-based systems
#
#	2013-08-11	added	retrieval for condition maps
#				added	retrieval for forecast maps
#				added	retrieval for warning maps
#				added	retrieval for radar maps
#				modi	use LWP::ua for some file transfers instead of ftp
#						due to transfer errors on image files
#						use parameter #5 = 1 in RetrieveFile for ftp
#				added	get <name> caplist
#
#	2013-08-10	added	some more tolerance on text inputs
#				modi	switched from GetLogList to Log3
#
#	2013-08-09	added	more logging
#				fixed	missing error message if WARNCELLID does not exist
#				update	commandref
#
#	2013-08-08	added	logging
#				added	firewall/proxy support
#				fixed	XMLin missing parameter 
#				added	:noArg to setlist-definitions
#				added	AttrFn
#				modi	retrieval of VHDL messages 30-33
#
#	2013-08-07	public  initial release
#
###################################################################################################
#
# Further informations
#
# DWD's data format is unpleasant to read, 
# since the data columns change depending on the available data
# (e.g. the SSS column for snow disappears when there is no snow).
# It's also in ISO8859-1, i.e. it contains non-ASCII characters. To
# avoid problems, we need some conversion subs in this program.
#
# Höhe  : m über NN
# Luftd.: reduzierter Luftdruck auf Meereshöhe in hPa
# TT    : Lufttemperatur in Grad Celsius
# Tn12  : Minimum der Lufttemperatur, 18 UTC Vortag bis 06 UTC heute, Grad Celsius
# Tx12  : Maximum der Lufttemperatur, 18 UTC Vortag bis 06 UTC heute, Grad Celsius
# Tg24  : Temperaturminimum 5cm ¸ber Erdboden, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tn24  : Minimum der Lufttemperatur, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tm24  : Mittel der Lufttemperatur, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tx24  : Maximum der Lufttemperatur, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tmin  : Minimum der Lufttemperatur, 06 UTC Vortag bis 06 UTC heute, Grad Celsius
# Tmax  : Maximum der Lufttemperatur, 06 UTC Vortag bis 06 UTC heute, Grad Celsius
# RR1   : Niederschlagsmenge, einstündig, mm = l/qm
# RR12  : Niederschlagsmenge, 12st¸ndig, 18 UTC Vortag bis 06 UTC heute, mm = l/qm
# RR24  : Niederschlagsmenge, 24stündig, 06 UTC Vortag bis 06 UTC heute, mm = l/qm
# SSS   : Gesamtschneehöhe in cm
# SSS24 : Sonnenscheindauer 22.05.2014 in Stunden
# SGLB24: Tagessumme Globalstrahlung am 22.05.2014 in J/qcm 
# DD    : Windrichtung 
# FF    : Windgeschwindigkeit letztes 10-Minutenmittel in km/h
# FX    : höchste Windspitze im Bezugszeitraum in km/h
# ---   : Wert nicht vorhanden
#
###################################################################################################
=cut

# commandref documentation
=pod
=begin html

<a name="GDS"></a>
<h3>GDS</h3>
<ul>

	<b>Prerequesits</b>
	<ul>
	
		<br/>
		Module uses following additional Perl modules:<br/><br/>
		<code>Net::FTP, XML::Simple, Archive::Extract</code><br/><br/>
		If not already installed in your environment, 
		please install them using appropriate commands from your environment.

	</ul>
	<br/><br/>
	
	<a name="GDSdefine"></a>
	<b>Define</b>
	<ul>

		<br>
		<code>define &lt;name&gt; GDS &lt;username&gt; &lt;password&gt; [&lt;host&gt;]</code><br>
		<br>
		This module provides connection to <a href="http://www.dwd.de/grundversorgung">GDS service</a> 
		generated by <a href="http://www.dwd.de">DWD</a><br>
		<br/>
		Optional paramater host is used to overwrite default host "ftp-outgoing2.dwd.de".<br/>
		<br>
	</ul>
	<br/><br/>

	<a name="GDSset"></a>
	<b>Set-Commands</b><br/>
	<ul>

		<br/>
		<code>set &lt;name&gt; clear alerts|conditions|forecasts|all</code>
		<br/><br/>
		<ul>
			<li>alerts: Delete all a_* readings</li>
			<li>all: Delete all a_*, c_*, g_* and fc_* readings</li>
		</ul>
		<br/>

		<code>set &lt;name&gt; conditions &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve current conditions at selected station. Data will be updated periodically.</ul>
		<br/>

		<code>set &lt;name&gt; forecasts &lt;region&gt;/&lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve forecasts for today and the following 3 days for selected station.<br/>
		    Data will be updated periodically.</ul>
		<br/>

		<code>set &lt;name&gt; help</code>
		<br/><br/>
		<ul>Show a help text with available commands</ul>
		<br/>

		<code>set &lt;name&gt; update</code>
		<br/><br/>
		<ul>Update conditions and forecasts readings at selected station and restart update-timer</ul>
		<br/>

		<li>condition readings generated by SET use prefix "c_"</li>
		<li>forecast readings generated by SET use prefix "fcd_" and a postfix of "hh"<br/> 
		   with d=relative day (0=today) and hh=last hour of forecast (exclusive)</li>
		<li>readings generated by SET will be updated automatically every 20 minutes</li>

	</ul>
	<br/><br/>

	<a name="GDSget"></a>
	<b>Get-Commands</b><br/>
	<ul>

		<br/>
		<code>get &lt;name&gt; alerts &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve alert message for selected region from previously read alert file (see rereadcfg)</ul>
		<br/>

		<code>get &lt;name&gt; conditions &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve current conditions at selected station</ul>
		<br/>

		<code>get &lt;name&gt; conditionsmap &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) showing current conditions at selected station</ul>
		<br/>

		<code>get &lt;name&gt; forecasts &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve forecasts for today and the following 3 days for selected region as text</ul>
		<br/>

		<code>get &lt;name&gt; forecastsmap &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) showing forecasts for selected region</ul>
		<br/>

		<code>get &lt;name&gt; headlines [separator]</code>
		<br/><br/>
		<ul>Returns a string, containing all alert headlines. <br/>
		    Default separator is | but can be overriden.</ul>
		<br/>

		<code>get &lt;name&gt; help</code>
		<br/><br/>
		<ul>Show a help text with available commands</ul>
		<br/>

		<code>get &lt;name&gt; list capstations|data|stations</code>
		<br/><br/>
		<ul>
			<li><b>capstations:</b> Retrieve list showing all defined warning regions. 
			    You can find your WARNCELLID with this list.</li>
			<li><b>data:</b> List current conditions for all available stations in one single table</li>
			<li><b>stations:</b> List all available stations that provide conditions data</li>
		</ul>
		<br/>

		<code>get &lt;name&gt; radarmap &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) containig radar view from selected region</ul>
		<br/>

		<code>get &lt;name&gt; rereadcfg</code>
		<br/><br/>
		<ul>Reread all required data from DWD Server manually: station list and CAP data</ul>
		<br/>

		<code>get &lt;name&gt; warnings &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve current warnings report for selected region
			<ul>
				<br/>
				<li>report type VHDL30 = regular report, issued daily</li>
				<li>report type VHDL31 = regular report, issued before weekend or national holiday</li>
				<li>report type VHDL32 = preliminary report, issued on special conditions</li>
				<li>report type VHDL33 = cancel report, issued if necessary to cancel VHDL32</li>
			</ul>
		</ul>
		<br/>

		<code>get &lt;name&gt; warningssmap &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) containig current warnings for selected region marked with symbols</ul>
		<br/><br/>
		<b>All downloaded mapfiles</b> can be found inside "GDS Files" area in left navigation bar.

	</ul>
	<br/><br/>

	<a name="GDSattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<br/>
		<li><b>disable</b> - if set, gds will not try to connect to internet</li>
		<li><b>gdsAll</b> - defines filter for "all data" from alert message</li>
		<li><b>gdsDebug</b> - defines filter for debug informations</li>
		<li><b>gdsSetCond</b> - defines conditions area to be used after system restart</li>
		<li><b>gdsSetForecast</b> - defines forecasts region/station to be used after system restart</li>
		<li><b>gdsLong</b> - show long text fields "description" and "instruction" from alert message in readings</li>
		<li><b>gdsPolygon</b> - show polygon data from alert message in a reading</li>
		<li><b>gdsHideFiles</b> - if set to 1, the "GDS Files" menu in the left navigation bar will not be shown</li>
		<br/>
		<li><b>gdsPassiveFtp</b> - set to 1 to use passive FTP transfer</li>
		<li><b>gdsFwName</b> - define firewall hostname in format &lt;hostname&gt;:&lt;port&gt;</li>
		<li><b>gdsFwType</b> - define firewall type in a value 0..7 please refer to
		    <a href="http://search.cpan.org/~gbarr/libnet-1.22/Net/Config.pm#NetConfig_VALUES">cpan documentation</a> 
		    for further informations regarding firewall settings.</li>
	</ul>
	<br/><br/>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>
		<li><b>_&lt;readingName&gt;</b> - debug informations</li>
		<li><b>a_X_&lt;readingName&gt;</b> - weather data from CAP alert messages. Readings will NOT be updated automatically<br/>
			a_ readings contain a set of alert inforamtions, X represents a numeric set identifier starting with 0<br/>
			that will be increased for every valid alert message in selected area<br/></li>
		<li><b>a_count</b> - number of currently valid alert messages, can be used for own loop iterations on alert messages</li>
		<li><b>a_valid</b> - returns 1 if at least one of decoded alert messages is valid</li>
		<li><b>c_&lt;readingName&gt;</b> - weather data from SET weather conditions. 
		    Readings will be updated every 20 minutes.</li>
		<li><b>fc?_&lt;readingName&gt;??</b> - weather data from SET weather forecasts, 
		    prefix by relative day and postfixed by last hour. Readings will be updated every 20 minutes.<br>
			<i><ul>
				<li>0_weather06 and ?_weather12 (with ? greater 0) is the weather in the morning</li>
				<li>0_weather12 is the weather at noon</li>
				<li>0_weather18 and ?_weather24 (with ? greater 0) is the weather in the afternoon</li>
				<li>0_weather24 is the weather at midnight</li>
				<li>0_windGust06 and ?_windGust12 (with ? greater 0) is the wind in the morning</li>
				<li>0_windGust12 is the wind at noon</li>
				<li>0_windGust18 and ?_windGust24 (with ? greater 0) is the wind in the afternoon</li>
				<li>0_windGust24 is the wind at midnight</li>
				<li>?_tMinAir is minimum temperature in the morning</li>
				<li>0_tAvgAir12 is the average temperature at noon</li>
				<li>?_tMaxAir is the maximum temperature in the afternoon</li>
				<li>0_tAvgAir24 is the average temperature at midnight</li>        
			</ul></i>
		</li>
		<li><b>g_&lt;readingName&gt;</b> - weather data from GET weather conditions. 
		    Readings will NOT be updated automatically</li>
	</ul>
	<br/><br/>

	<b>Author's notes</b><br/><br/>
	<ul>

		<li>Module uses following additional Perl modules:<br/><br/>
		<code>Net::FTP, XML::Simple, Archive::Extract</code><br/><br/>
		If not already installed in your environment, please install them using appropriate commands from your environment.</li>
		<br/><br/>
		<li>Have fun!</li><br/>

	</ul>

</ul>

=end html
=begin html_DE

<a name="GDS"></a>
<h3>GDS</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#GDS'>GDS</a><br/>
</ul>
=end html_DE
=cut

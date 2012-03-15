package main;
use strict;
use warnings;
use POSIX;
my @wert;
my $div_class;
sub doMakeHtml($@);
######################################################################################
sub
myFloorplanList_Initialize($$)
{
  my ($hash) = @_;
}
###################################################################################
# Define in fhem by
# define w_WertListe1 weblink htmlCode {doWertListe1()}
# attr w_WertListe1 room Listen
#
sub
doWertListe1() {
	$div_class = "WertListe";  #format in css-file using #WertListe
	
# vvvvvvvvvvvvv Change this list as needed vvvvvvvvvvvvvvv
	$wert[0] = "FHT Ist:"		.','.	ReadingsVal("ez_FHT","measured-temp","ezFHT measured-temp Fehler");
	$wert[1] = "FHT Soll:"		.','.	ReadingsVal("ez_FHT","desired-temp","ezFHT desired-temp Fehler");
	$wert[2] = "FHT Actuator:"	.','.	ReadingsVal("ez_FHT","actuator","ezFHT actuator Fehler");
	$wert[3] = "Aussen:"		.','.	ReadingsVal("ez_Aussensensor","temperature","ez_Aussensensor temperature Fehler");
	$wert[4] = "HomeStatus:"	.','.	Value("HomeStatus"); 
	$wert[5] = "GoogleTemp:"	.','.	ReadingsVal("MunichWeather","temperature","MunichWeather temperature Error");
	$wert[6] = "GoogleSky:"		.','.	ReadingsVal("MunichWeather","condition","MunichWeather condition Error"); 
	$wert[7] = "GoogleIcon:"	.','.	"<img src=\"http://www.google.com".ReadingsVal("MunichWeather","icon","MunichWeather icon Error")."\">"; 
	my $FritzTemp = `ctlmgr_ctl r power status/act_temperature` ;           # read  FritzBox internal temperature
	$wert[8] = "FritzBoxTemp:"	.','.	$FritzTemp . "&deg";				# print FritzBox internal temperature
# ^^^^^^^^^^^^^ Change this list as needed ^^^^^^^^^^^^^^^

	return doMakeHtml($div_class, @wert);
}

###################################################################################
# Define in fhem by
# define w_WertListe2 weblink htmlCode {doWertListe2()}
# attr w_WertListe2 room Listen
#
#sub
#doWertListe2() {
#	$div_class = "WertListe";  #format in css-file using #WertListe
#
#	
# vvvvvvvvvvvvv Change this list as needed vvvvvvvvvvvvvvv
#	$wert[0] = "FHT Ist:"		.','.	ReadingsVal("ez_FHT","measured-temp","ezFHT measured-temp Fehler");
#	$wert[1] = "FHT Soll:"		.','.	ReadingsVal("ez_FHT","desired-temp","ezFHT desired-temp Fehler");
#	$wert[2] = "FHT Actuator:"	.','.	ReadingsVal("ez_FHT","actuator","ezFHT actuator Fehler");
# and so on
# ^^^^^^^^^^^^^ Change this list as needed ^^^^^^^^^^^^^^^
#
#	return doMakeHtml($div_class, @wert);
#}

###################################################################################
# Create html-code
# 
sub
doMakeHtml($@) {
	my ($div_class, @line ) = @_;
	my $htmlcode = '<div  class="'.$div_class."\"><table>\n";
	foreach (@line) {
		my ($title, $value) = split (",",$_);
		my $cssTitle = $title;
		$cssTitle =~ s,[: -],,g;
		$htmlcode .= "<tr><td><span \"$cssTitle-title\">$title</span></td><td><span \"$cssTitle-value\">$value</span></td></tr>\n";
	}
	$htmlcode .= "</table></div>";
	return $htmlcode;
}
1;

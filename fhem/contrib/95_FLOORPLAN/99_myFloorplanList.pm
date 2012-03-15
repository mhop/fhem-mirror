package main;
use strict;
use warnings;
use POSIX;

sub
myFloorplanList_Initialize($$)
{
  my ($hash) = @_;
}
###################################################################################
# Einbinden in fhem mit
# define w_WertListe1 weblink htmlCode {doWertListe1()}
# attr w_WertListe1 room Listen
#
sub
doWertListe1() {
    my @wert;
	my $div_class = "WertListe";  #format in css-file using #WertListe

	
# Change this list as needed	
	$wert[0] = "FHT Ist:"		.','.	ReadingsVal("ez_FHT","measured-temp","ezFHT measured-temp Fehler");
	$wert[1] = "FHT Soll:"		.','.	ReadingsVal("ez_FHT","desired-temp","ezFHT desired-temp Fehler");
	$wert[2] = "FHT Actuator:"	.','.	ReadingsVal("ez_FHT","actuator","ezFHT actuator Fehler");
	$wert[3] = "Aussen:"		.','.	ReadingsVal("ez_Aussensensor","temperature","ez_Aussensensor temperature Fehler");
	$wert[4] = "HomeStatus:"	.','.	Value("HomeStatus"); 
	$wert[5] = "GoogleTemp:"	.','.	ReadingsVal("MunichWeather","temperature","MunichWeather temperature Error");
	$wert[6] = "GoogleSky:"		.','.	ReadingsVal("MunichWeather","condition","MunichWeather condition Error"); 
	$wert[7] = "GoogleIcon:"	.','.	"<img src=\"http://www.google.com".ReadingsVal("MunichWeather","icon","MunichWeather icon Error")."\">"; 
	my $FritzTemp = `ctlmgr_ctl r power status/act_temperature` ;
	$wert[8] = "FritzBoxTemp:"	.','.	$FritzTemp . "&deg";
# Change this list as needed
	

	my $htmlcode = '<div  class="'.$div_class."\"><table>\n";
	foreach (@wert) {
		my ($title, $value) = split (",",$_);
		$htmlcode .= "<tr><td>$title</td><td>$value</td></tr>\n";
	}
	$htmlcode .= "</table></div>";
	return $htmlcode;
}
1;

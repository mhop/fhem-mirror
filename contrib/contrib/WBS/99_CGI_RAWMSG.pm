################################################################################
# Route RAW-Sensor-Data via FHEMWEB/CGI to fhem.pl: Function -> disptach($$$)
# 99_CGI_RAWMSG
#
# Version: 1.0.1
# Date: 24.05.2010
# Author: Axel Rieger
#
################################################################################
# Examples for RAW-Sensor-Data
# WBS = WeB-Sensors
# WBS:SENSOR-CODE:SENSOR-TYPE:VALUE:TIMESTAMP
# HMS -> H909801530400F4
# CUL_WS -> K21500163	
################################################################################
package main;
use strict;
use warnings;
use Data::Dumper;
use vars qw(%data);
use vars qw($__ME);
################################################################################
sub CGI_RAWMSG_Initialize($)
{
  # FHEM Part
  my ($hash) = @_;
  $hash->{Clients} = ":CUL_WS:HMS:WBS:";
  my %mc = (
	"1:CUL_WS"    => "^K.....",
	"2:HMS"       => "^810e04....(1|5|9).a001",
	"3:WBS"       => "^WBS:",
	);
  $hash->{MatchList} = \%mc;
  # CGI Part
  my $cgi_key = "rawmsg";
  my $cgi_name = "CGI_RAWMSG";
  # PRIV-CGI
  my $fhem_url = "/" . $cgi_key ;
  $data{FWEXT}{$fhem_url}{FUNC} = "CGI_RAWMSG_Dispatch";
  $data{FWEXT}{$fhem_url}{LINK} = $cgi_key;
  $data{FWEXT}{$fhem_url}{NAME} = $cgi_name;
  # Create IO-Device for fhem-dispatcher
  $data{$cgi_key}{NAME} = $cgi_name;
  $data{$cgi_key}{MatchList} = \%mc;
  if(!defined($defs{$cgi_name})){
	fhem "define $cgi_name dummy";
	$defs{$cgi_name}{STATE} = "AKTIV 99_CGI_RAWMSG";
	$defs{$cgi_name}{TYPE} = "CGI_RAWMSG";
	fhem "attr $cgi_name comment DUMMY_DEVICE_FOR_99_CGI_RAWMSG";
  }
  
}
################################################################################
sub CGI_RAWMSG_Dispatch($$)
{
  my ($htmlarg) = @_;
  my ($ret_param,$ret_txt,@tmp,$rawmsg,$cgikey);
  Log 5, "CGI_RAWMSG|Dispatch|START: $htmlarg";
  $ret_param = "text/plain; charset=ISO-8859-1";
  $ret_txt = "ERROR;NODATA";
#  print "CGI_RAWMSG|Dispatch: " . Dumper(@_) . "\n";
  # Aufurf: http://[FHEMWEB]/fhem/rawmsg?TEST12345
  # htmlarg = /rawmsg?TEST12345
  if($htmlarg =~ /\?/) {
	@tmp = split(/\?/,$htmlarg);
	$cgikey = shift(@tmp);
	$cgikey =~ s/\///;
	$rawmsg = shift(@tmp);
	# HELP
	if($rawmsg eq "help") {
	  no strict "refs";
	  $ret_txt = &CGI_RAWMSG_help;
	  use strict "refs";
	  return ($ret_param, $ret_txt);
	  }
	# Check rawmsg
	foreach my $m (sort keys %{$data{$cgikey}{MatchList}}) {
	  Log 5, "CGI_RAWMSG|MatchList-RAWMSG: $rawmsg";
	  Log 5, "CGI_RAWMSG|MatchList-Key: $m";
	  Log 5, "CGI_RAWMSG|MatchList-Val: " . $data{$cgikey}{MatchList}{$m};
	  my $match = $data{$cgikey}{MatchList}{$m};
	  if($rawmsg =~ m/$match/) {
		Log 5, "CGI_RAWMSG|MatchList-Key FOUND: $m";
		# $ret_txt = "HTMLARG = $htmlarg\n";
		# $ret_txt .= "CGI-KEY = $cgikey\n";
		# $ret_txt .= "RAWMSG = $rawmsg\n";
		# Dummy-Device
		my $name = $data{$cgikey}{NAME};
		my $hash = $defs{$name};
		$hash->{"${name}_MSGCNT"}++;
		$hash->{"${name}_TIME"} = TimeNow();
		$hash->{RAWMSG} = $rawmsg;
		my %addvals = (RAWMSG => $rawmsg);
		my $ret_disp = &Dispatch($hash, $rawmsg, \%addvals);
		if(defined($ret_disp)) {$ret_txt = "OK;" . join(";" ,@$ret_disp) . "\n";}
		else {$ret_txt = "ERROR;NODEVICEFOUND";}
		return ($ret_param, $ret_txt);
		}
	  }
  $ret_txt = "ERROR;NODATAMATCH";
	}
  return ($ret_param, $ret_txt);
}

################################################################################
sub CGI_RAWMSG_help
{
  my $txt = "Route RAW-Sensor-Data via FHEMWEB/CGI to FHEM\n";
  $txt .= "FHEM.PL Function -> disptach($$$)\n";
  $txt .= "Examples for RAW-Sensor-Data \n";
  $txt .= "WBS = WeB-Sensors\n";
  $txt .= "WBS:SENSOR-CODE:SENSOR-TYPE:VALUE:TIMESTAMP\n";
  $txt .= "HMS -> H909801530400F4\n";
  $txt .= "CUL_WS -> K21500163 \n";
  retrun $txt;
}
################################################################################
sub CGI_RAWMSG_new_iodev
{
}
################################################################################
1;
################################################################################

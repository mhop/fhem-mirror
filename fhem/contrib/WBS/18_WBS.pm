################################################################################
# Web based Sensors = 18_WBS.pm
# Sensors updated only via Web
#
# Version: 1.0.1
# Date: 24.05.2010
# Author: Axel Rieger
#
################################################################################
#
# Define:
# define <NAME> WBS TYPE CODE
#
# Type = READING-NAME f.e.
# CODE = Unique-Code for WBS-Sensors max. 16 Chars
#
# Example
# define WBS001 WBS Temperature 1032D8ED01080011
# $defs$defs{WBS001}{TYPE} = WBS
# $defs$defs{WBS001}{CODE} = 1032D8ED01080011
# $defs{WBS001}{READINGS}{Temperature}{VAL} = 0
# $defs{WBS001}{READINGS}{Temperature}{TIME} = TimeNow()
# Only One READING for each WBS
#
# Updates via WEB:
# MSG-Format:
# WBS:SENSOR-CODE:VALUE
# WBS -> Web Based Sensor -> matching in FHEM
# Sensor-Code -> Unique-Code for WBS-Sensors max. 16 Chars
# Value -> Data from Sensor like 18°C -> Format: INT only [1...90.-]
#			max. lenght Value: -xxx.xxx 8 Chars
# max-Lenght MSG: 3:16:8 = 29 Chars
# Example: Temperature form Dallas 1820-Temp-Sensors 24.32 °Celsius
# WBS:1032D8ED01080011:23.32
# Update via http-get-request
# http://[MY_FHEMWEB:xxxx]/fhem/rawmsg?WBS:1032D8ED01080011:23.32
################################################################################
package main;
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use vars qw(%defs);
use vars qw(%attr);
use vars qw(%data);
use vars qw(%modules);
################################################################################
sub WBS_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = "^WBS:";
  $hash->{DefFn}     = "WBS_Define";
  $hash->{UndefFn}   = "WBS_Undef";
  $hash->{ParseFn}   = "WBS_Parse";
  $hash->{AttrList}  = "IODEV do_not_notify:0,1 loglevel:0,5 disable:0,1";
  $hash->{defptr} = {};
  #Rebuild DefPtr
  my $mod = "WBS";
  foreach my $d (sort keys %defs) {
    next if($defs{$d}{TYPE} ne $mod);
  Log 0, "WBS-DEFPTR-FOUND: " . $defs{$d}{NAME} . " : " . $defs{$d}{CODE};
	$modules{WBS}{defptr}{$defs{$d}{CODE}} = $defs{$d}{NAME};
  }
}
################################################################################
sub WBS_Define($)
{
  # define <NAME> WBS TYPE CODE
  my ($self, $defs) = @_;
  #Log 0, "WBS|DEFINE: " . Dumper(@_);
  my @a = split(/ /, $defs);
  return "WBS|Define|ERROR: Unknown argument count " . int(@a) . " , usage define <NAME> WBS TYPE CODE"  if(int(@a) != 4);
  my $mod = $a[1];
  my $Type = $a[2];
  my $Code = $a[3];
  if(defined($modules{WBS}{defptr}{$Code})) {
	return "WBS|Define|ERROR: Code is used";
  }
  if(length($Code) > 16) {
	return "WBS|Define|ERROR: Max. Length CODE > 16";
	}
  $self->{CODE} = $Code;
  $self->{STATE} = "NEW: " . TimeNow();
  $self->{WBS_TYPE} = $Type;
  $self->{READINGS}{$Type}{VAL} = 0;
  $self->{READINGS}{$Type}{TIME} = TimeNow();
  $modules{WBS}{defptr}{$Code} = $self->{NAME};
  return undef;
}
################################################################################
sub WBS_Undef($$)
{
  my ($hash, $name) = @_;
  Log 0, "WBS|Undef: " . Dumper(@_);
  my $mod = $defs{$name}{TYPE};
  my $Code = $defs{$name}{CODE};
  if(defined($modules{$mod}{defptr}{$Code})) {
	delete $modules{$mod}{defptr}{$Code}
  }
  return undef;
}
################################################################################
sub WBS_Parse($$)
{
  my ($iodev,$rawmsg) = @_;
  # MSG: WBS:1032D8ED01080011:23.32
  my ($null,$code,$value) = split(/:/, $rawmsg);
  if(length($code) > 16 ) {
	return "WBS|Parse|ERROR: Max. Length CODE > 16";
  }
  if(length($value) > 8) {
	return "WBS|Parse|ERROR: Max. Length VALUE > 8";
  }
  # Find Device-Name
  my $mod = "WBS";
  if(!defined($modules{$mod}{defptr}{$code})){
  return "WBS|Parse|ERROR: Unkown Device for $code";
  }
  my $wbs_name = $modules{$mod}{defptr}{$code};
  my $wbs = $defs{$wbs_name};
  #LogLevel
  my $ll = 0;
  if(defined($attr{$wbs_name}{loglevel})) {$ll = $attr{$wbs_name}{loglevel};}
  #Clean-Value
  $value =~ s/[^0123456789.-]//g;
  # Get Reading
  my $reading = $wbs->{WBS_TYPE};
  $wbs->{READINGS}{$reading}{VAL} = $value;
  $wbs->{READINGS}{$reading}{TIME} = TimeNow();
  # State: [FirstChar READING]:VALUE
  my $fc = uc(substr($reading,0,1));
  $wbs->{STATE} = "$fc: $value | " . TimeNow();
  # Changed
  $wbs->{CHANGED}[0] = "$reading: $value";
  return $wbs_name;
}
################################################################################
1;

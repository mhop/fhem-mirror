################################################################################
# Web based Sensors = 18_WBS.pm
# Sensors updated only via Web
#
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
# $defs$defs{WBS001}{CODE} = 12345
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
# Reverse-Lokup-Pointer
my %defptr;
################################################################################
sub WBS_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = "^WBS:";
  $hash->{DefFn}     = "WBS_Define";
  $hash->{UndefFn}   = "WBS_Undef";
  $hash->{ParseFn}   = "WBS_Parse";
  $hash->{AttrList}  = "IODEV do_not_notify:0,1 loglevel:0,5 disable:0,1";
}
################################################################################
sub WBS_Define($)
{
  # define <NAME> WBS TYPE CODE
  my ($self, $defs) = @_;
  Log 0, "WBS|DEFINE: " . Dumper(@_);
  Log 0, "WBS|DEFPTR: " . Dumper(%defptr);
  my @a = split(/ /, $defs);
  return "WBS|Define|ERROR: Unknown argument count " . int(@a) . " , usage define <NAME> WBS TYPE CODE"  if(int(@a) != 4);
  my $Type = $a[2];
  my $Code = $a[3];
  if(defined($defptr{$Code})) {
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
  $defptr{$Code} = $self;
  Log 0, "WBS|DEFPTR: " . Dumper(%defptr);
  return undef;
}
################################################################################
sub WBS_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}})
        if(defined($hash->{CODE}) && defined($defptr{$hash->{CODE}}));
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
  if(!defined($defptr{$code})) {
  return "WBS|Parse|ERROR: Unkown Device for $code";
  }
  Log 0, "WBS|Parse: " . Dumper(%defptr);
  my $wbs = $defptr{$code};
  my $wbs_name = $wbs->{NAME};
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
  $wbs->{STATE} = "$fc: $value";
  # Changed
  $wbs->{CHANGED}[0] = "$reading:$value";
}
################################################################################
1;

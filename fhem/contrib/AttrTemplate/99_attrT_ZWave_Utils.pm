##############################################
# $Id$
#

# packages ####################################################################
package FHEM::attrT_ZWave_Utils;    ## no critic 'Package declaration'

use strict;
use warnings;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          InternalVal
          ReadingsNum
          devspec2array
          FW_makeImage 
          )
    );
}

sub main::attrT_ZWave_Utils_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

sub identify_channel_devices {
  my $devname = shift;
  my $wanted = shift // return;
  
  my $mainId = substr(InternalVal($devname,"nodeIdHex","00"),0,2);
  my $wantedId = $mainId;
  $wantedId .= "0$wanted" if $wanted;
  my @names = devspec2array("TYPE=ZWave:FILTER=nodeIdHex=$wantedId");
  return if !@names;
  return $names[0];
}

sub devStateIcon_shutter {
  my $levelname = shift // return;
  my $model = shift // "FGR223";
  my $mode = shift // "roller"; # or "venetian"
  my $slatname = $levelname;
  my $dimlevel= ReadingsNum($levelname,"dim",0);
  my $ret ="";
  my $slatlevel = 0;
  my $slatcommand_string = "dim ";
  my $moving = 0;
  
  if ($model eq "FGR223") {
    if ($mode eq "venetian") {
      #my ($def,$defnr) = split(" ", InternalVal($levelname,"DEF",$levelname));
      #$defnr++;
      #my @slatnames = devspec2array("DEF=$def".'.'.$defnr);
      
	  $slatname = identify_channel_devices($levelname,2);
      $slatlevel= ReadingsNum($slatname,"state",0);
    }
    $moving = 1 if ReadingsNum($levelname,"power",0) > 0;
  } 
  if ($model eq "FGRM222") {
    if ($mode eq "venetian") {
      $slatlevel= ReadingsNum($slatname,"positionSlat",0);
      $slatcommand_string = "positionSlat ";
    }
    $moving = 1 if ReadingsNum($levelname,"power",0) > 0;
  } 

  #levelicon
  my $symbol_string = "fts_shutter_";
  my $command_string = "dim 99";
  $command_string = "dim 0" if $dimlevel > 50;
  $symbol_string .= int ((109 - $dimlevel)/10)*10;
  $ret .= $moving ? "<a href=\"/fhem?cmd.dummy=set $levelname stop&XHR=1\">" . FW_makeImage("edit_settings","edit_settings") . "</a> " 
                  : "<a href=\"/fhem?cmd.dummy=set $levelname $command_string&XHR=1\">" . FW_makeImage($symbol_string,"fts_shutter_10") . "</a> "; 

  #slat
  if ($mode eq "venetian") {
    $symbol_string = "fts_blade_arc_close_";
    $slatlevel > 49 ? $symbol_string .= "00" : $slatlevel > 24 ? $symbol_string .= "50" : $slatlevel < 25 ? $symbol_string .= "100" : undef;
    $slatlevel > 49 ? $slatcommand_string .= "0" : $slatlevel > 24 ? $slatcommand_string .= "50" : $slatlevel < 25 ? $slatcommand_string .= "25" : undef;
    $symbol_string = FW_makeImage($symbol_string,"fts_blade_arc_close_100");
    $ret .= qq(<a href="/fhem?cmd.dummy=set $slatname $slatcommand_string&XHR=1">$symbol_string $slatlevel %</a>); 
  }

  return "<div><p style=\"text-align:right\">$ret</p></div>";

}



1;

__END__
=pod
=begin html

<a name="attrT_ZWave_Utils"></a>
<h3>attrT_ZWave_Utils</h3>
<ul>
  <b>devStateIcon_shutter</b>
  <br>
  Use this to get a multifunctional iconset to control shutter devices like Fibaro FGRM222 devices in venetian blind mode<br>
  Examples: 
  <ul>
   <code>attr Jalousie_WZ devStateIcon {FHEM::attrT_ZWave_Utils::devStateIcon_shutter($name,"FGRM222")}<br> attr Jalousie_WZ webCmd dim<br>attr Jalousie_WZ userReadings dim:(dim|reportedState).* {$1 =~ /reportedState/ ? ReadingsNum($name,"reportedState",0):ReadingsNum($name,"state",0)}
</code><br>
or <br>
   <code>attr Jalousie_WZ devStateIcon {FHEM::attrT_ZWave_Utils::devStateIcon_shutter($name,"FGR223", "venetian")}<br> attr Jalousie_WZ webCmd dim<br>attr Jalousie_WZ userReadings dim:(dim|reportedState).* {$1 =~ /reportedState/ ? ReadingsNum($name,"reportedState",0):ReadingsNum($name,"state",0)}
</code><br>
   Code can be used for blinds with or without venetian blind mode. In cas if and slat level is not part of the main device (like Fibaro FGR223, the second FHEM device to control slat level has to have a userReadings attribute for state like this:<br>
 <code>attr ZWave_SWITCH_MULTILEVEL_8.02 userReadings state:swmStatus.* {ReadingsNum($name,"swmStatus",0)}</code>
  </ul>
</ul>
=end html
=cut

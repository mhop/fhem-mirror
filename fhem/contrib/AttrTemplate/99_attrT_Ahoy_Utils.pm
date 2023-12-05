##############################################
# $Id$
#

package FHEM::attrT_Ahoy_Utils;    ## no critic 'Package declaration'

use strict;
use warnings;

use Color;
use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          FW_makeImage
          AttrVal
          InternalVal
          ReadingsVal
          ReadingsNum
          ReadingsAge
		  isday
          defs
          )
    );
}

sub main::attrT_Ahoy_Utils_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

sub devStateIcon {
  my $devname = shift // return;
  my $panels  = shift // 4;
  my $colors  = shift // 0;

  return if !defined $defs{$devname};

  my $col = substr(Color::pahColor(-10,50,70,ReadingsNum($devname,'temperature',0),$colors),0,6);
  my $ret = FW_makeImage("sani_solar_temp\@$col",'file_unknown@grey');
  $ret .= ' ';
  $ret .= ReadingsNum($devname,'temperature',0,1);
  $ret .= ' °C<br>';

  my $avail = ReadingsNum($devname,'available',0);
  $avail = $avail > 1 ? '10px-kreis-gruen' : isday() ? '10px-kreis-rot' :'10px-kreis-gelb'; 
  $ret .= FW_makeImage($avail, 'edit_settings');
  $ret .= ' ';

  if ( $panels > 1 ) {
    $ret .= ReadingsNum($devname,'P_AC',0);
    $ret .= ' W / ';
    $ret .= ReadingsNum($devname,'YieldDay',0);
    $ret .= ' Wh';

    my $total = ReadingsNum($devname,'YieldTotal',0,1);
    if ( $total > 0 ) {
      $ret .= ' / ';
      $ret .= $total;
      $ret .= ' kWh';
    }

    for (1..$panels) {
      $ret .= '<br>';
      $col = substr(Color::pahColor(0,50,100,ReadingsNum($devname,"Irradiation$_",0),$colors),0,6);
      $ret .= FW_makeImage("solar\@$col",'file_unknown@grey');
      $ret .= ' ';
      $ret .= ReadingsNum($devname,"P_DC$_",0);
      $ret .= ' W / ';
      $ret .= ReadingsNum($devname,"YieldDay$_",0);
      $ret .= ' Wh';
      $total = ReadingsNum($devname,"YieldTotal$_",0,1);
      if ( $total > 0 ) {
        $ret .= ' / ';
        $ret .= $total;
        $ret .= ' kWh';
      }
    }
  } else {
    $col = substr(Color::pahColor(0,50,100,ReadingsNum($devname,"Irradiation1",0),$colors),0,6);
    $ret .= FW_makeImage("solar\@$col",'file_unknown@grey');
    $ret .= ' ';
    $ret .= ReadingsNum($devname,'P_AC',0);
    $ret .= ' W / ';
    $ret .= ReadingsNum($devname,'YieldDay',0);
    $ret .= ' Wh';

    my $total = ReadingsNum($devname,'YieldTotal',0,1);
    if ( $total > 0 ) {
      $ret .= ' / ';
      $ret .= $total;
      $ret .= ' kWh';
    }
  }
  return qq(<div><p style="text-align:right">$ret</p></div>);
}

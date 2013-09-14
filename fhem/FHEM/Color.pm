
# $Id$

package main;

use strict;
use warnings;

sub
FHEM_colorpickerInit()
{
  $data{webCmdFn}{colorpicker} = "FHEM_colorpickerFn";
  $data{FWEXT}{colorpicker}{SCRIPT} = "/jscolor/jscolor.js";
}

sub
FHEM_colorpickerFn($$$)
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  my @args = split("[ \t]+", $cmd);

  return undef if($values !~ m/^colorpicker,(.*)$/);
  my ($mode) = ($1);
  $mode = "RGB" if( !defined($mode) );
  my $srf = $FW_room ? "&room=$FW_room" : "";
  my $cv = CommandGet("","$d $cmd");
  $cmd = "" if($cmd eq "state");
  if( $args[1] ) {
    my $c = "cmd=set $d $cmd$srf";

    return '<td align="center">'.
             "<div onClick=\"FW_cmd('$FW_ME?XHR=1&$c')\" style=\"width:32px;height:19px;".
             'border:1px solid #fff;border-radius:8px;background-color:#'. $args[1] .';"></div>'.
           '</td>' if( AttrVal($FW_wname, "longpoll", 1));

    return '<td align="center">'.
             "<a href=\"$FW_ME?$c\">".
               '<div style="width:32px;height:19px;'.
               'border:1px solid #fff;border-radius:8px;background-color:#'. $args[1] .';"></div>'.
             '</a>'.
           '</td>';
  } else {
    my $c = "$FW_ME?XHR=1&cmd=set $d $cmd %$srf";
    return '<td align="center">'.
             "<input id='colorpicker.$d-RGB' class=\"color {pickerMode:'$mode',pickerFaceColor:'transparent',pickerFace:3,pickerBorder:0,pickerInsetColor:'red'}\" value='$cv' onChange='colorpicker_setColor(this,\"$mode\",\"$c\")'>".
           '</td>';
  }
}

1;

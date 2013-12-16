
# $Id$

package main;

use strict;
use warnings;

sub
Color_Initialize()
{
  FHEM_colorpickerInit();
}

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
  } elsif(AttrVal($d,"realtimePicker",0)) {
    my $c = "$FW_ME?XHR=1&cmd=set $d $cmd %$srf";
    my $ci = $c;
    $ci = "$FW_ME?XHR=1&cmd=set $d $cmd % : transitiontime 0 : noUpdate$srf" if($defs{$d}->{TYPE} eq "HUEDevice");
    return '<td align="center">'.
             "<input maxlength='6' size='6' id='colorpicker.$d-RGB' class=\"color {pickerMode:'$mode',pickerFaceColor:'transparent',pickerFace:3,pickerBorder:0,pickerInsetColor:'red',command:'$ci',onImmediateChange:'colorpicker_setColor(this)'}\" value='$cv' onChange='colorpicker_setColor(this,\"$mode\",\"$c\")'>".
           '</td>';
  } else {
    my $c = "$FW_ME?XHR=1&cmd=set $d $cmd %$srf";
    return '<td align="center">'.
             "<input maxlength='6' size='6' id='colorpicker.$d-RGB' class=\"color {pickerMode:'$mode',pickerFaceColor:'transparent',pickerFace:3,pickerBorder:0,pickerInsetColor:'red'}\" value='$cv' onChange='colorpicker_setColor(this,\"$mode\",\"$c\")'>".
           '</td>';
  }
}

my %dim_values = (
   0 => "dim06%",
   1 => "dim12%",
   2 => "dim18%",
   3 => "dim25%",
   4 => "dim31%",
   5 => "dim37%",
   6 => "dim43%",
   7 => "dim50%",
   8 => "dim56%",
   9 => "dim62%",
  10 => "dim68%",
  11 => "dim75%",
  12 => "dim81%",
  13 => "dim87%",
  14 => "dim93%",
);
sub
Color_devStateIcon($)
{
  my ($rgb) = @_;

  my @channels = Color::RgbToChannels($rgb,3);
  my $dim = Color::ChannelsToBrightness(@channels);
  my $percent = $dim->{bri};
  my $RGB = Color::ChannelsToRgb(@{$dim->{channels}});

  return ".*:off:toggle"
         if( $rgb eq "off" || $rgb eq "000000" || $percent == 0 );

  $percent = 100 if( $rgb eq "on" );

  my $s = $dim_values{int($percent/7)};
  $s="on" if( $percent eq "100" );

  return ".*:$s@#$RGB:toggle" if( $percent < 100 );
  return ".*:on@#$rgb:toggle";
}

package Color;
require Exporter;
our @ISA = qw(Exporter);
our  %EXPORT_TAGS = (all => [qw(RgbToChannels ChannelsToRgb ChannelsToBrightness BrightnessToChannels)]);
Exporter::export_tags('all');

sub
RgbToChannels($$) {
  my ($rgb,$numChannels) = @_;
  my @channels = ();
  foreach my $channel (unpack("(A2)[$numChannels]",$rgb)) {
    push @channels,hex($channel);
  }
  return @channels;
}

sub
ChannelsToRgb(@) {
  my @channels = @_;
  return sprintf("%02X" x @_, @_);
}

sub
ChannelsToBrightness(@) {
  my (@channels) = @_;

  my $max = 0;
  foreach my $value (@channels) {
    $max = $value if ($max < $value);
  }

  return {
    bri => 0,
    channels => \(255 x @channels),
  } unless ($max > 0);

  my @bri = ();
  my $norm = 255/$max;
  foreach my $value (@channels) {
    push @bri,int($value*$norm);
  }

  return {
    bri => int($max/2.55),
    channels  => \@bri,
  }
}

sub
BrightnessToChannels($) {
  my $arg = shift;
  my @channels = ();
  my $bri = $arg->{bri};
  foreach my $value (@{$arg->{channels}}) {
    push @channels,$value*$bri/100;
  }
  return @channels;
}

1;
